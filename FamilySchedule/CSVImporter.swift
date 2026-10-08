import Foundation
import SwiftData

/// Imports activities from a CSV file.
///
/// Header (any column order; names are case-insensitive):
/// Name, Person, Repeats, FirstDate, StartTime, DurationMin, Location, TimeZone, DriveMin,
/// MonthlyWeek, MonthlyDay, Alerts, SkipDates, Color, Notes
///
/// - Repeats: once | weekly | every2weeks | monthly | yearly
/// - FirstDate: YYYY-MM-DD   StartTime: HH:MM (24h)
/// - TimeZone: PT (default) | IST | any IANA id like Asia/Kolkata
/// - Alerts: "1d;2h;30m" or with messages "1d=Bring uniform;2h"
/// - SkipDates: "2026-11-04;2026-12-02"
/// Rows with the same Name + Person + FirstDate as an existing activity update it.
@MainActor
enum CSVImporter {
    struct Result {
        var added = 0
        var updated = 0
        var newPeople: [String] = []
        var errors: [String] = []

        var summary: String {
            var lines = ["Added \(added), updated \(updated)."]
            if !newPeople.isEmpty { lines.append("New people: \(newPeople.joined(separator: ", ")).") }
            if !errors.isEmpty {
                lines.append("Skipped \(errors.count) row(s):")
                lines.append(contentsOf: errors.prefix(8))
            }
            return lines.joined(separator: "\n")
        }
    }

    static func importCSV(_ text: String, context: ModelContext) -> Result {
        var result = Result()
        let rows = parse(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = rows.first else {
            result.errors.append("The file is empty.")
            return result
        }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func index(_ name: String) -> Int? { columns.firstIndex(of: name.lowercased()) }
        for required in ["name", "person", "repeats", "firstdate", "starttime", "durationmin"] where index(required) == nil {
            result.errors.append("Missing column: \(required)")
        }
        guard result.errors.isEmpty else { return result }

        var members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        let existing = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        var changedActivities: [Activity] = []
        var newMembers: [Member] = []

        for (i, row) in rows.dropFirst().enumerated() {
            let line = i + 2
            func value(_ name: String) -> String {
                guard let idx = index(name), idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let name = value("name")
            let personName = value("person")
            guard !name.isEmpty else { result.errors.append("Row \(line): missing Name"); continue }
            guard !personName.isEmpty else { result.errors.append("Row \(line): missing Person"); continue }

            let tzID = timeZoneID(value("timezone"))
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: tzID) ?? .current

            guard let anchor = date(value("firstdate"), cal: cal) else {
                result.errors.append("Row \(line): FirstDate must be YYYY-MM-DD"); continue
            }
            guard let startTime = time(value("starttime")) else {
                result.errors.append("Row \(line): StartTime must be HH:MM"); continue
            }
            let hour = startTime.0
            let minute = startTime.1
            guard let duration = Int(value("durationmin")), duration > 0 else {
                result.errors.append("Row \(line): DurationMin must be a number"); continue
            }

            let repeats = value("repeats").lowercased()
            let kind: RepeatKind
            var interval = 1
            switch repeats {
            case "once", "one time", "": kind = .once
            case "weekly": kind = .weekly
            case "every2weeks", "biweekly", "every 2 weeks": kind = .weekly; interval = 2
            case "monthly": kind = .monthlyNthWeekday
            case "yearly", "annual", "annually": kind = .yearly
            default:
                result.errors.append("Row \(line): unknown Repeats '\(repeats)'"); continue
            }

            // Person (create if new).
            let member: Member
            if let m = members.first(where: { $0.name.caseInsensitiveCompare(personName) == .orderedSame }) {
                member = m
            } else {
                let color = ActivityDraft.palette[members.count % ActivityDraft.palette.count]
                member = Member(name: personName, colorHex: color)
                context.insert(member)
                members.append(member)
                newMembers.append(member)
                result.newPeople.append(personName)
            }

            // Update if same Name + Person + FirstDate, else insert.
            let key = Activity.dayKey(anchor, cal: cal)
            let activity: Activity
            if let match = existing.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
                    && $0.member?.uid == member.uid
                    && Activity.dayKey($0.anchorDate, cal: $0.calendar) == key
            }) {
                activity = match
                result.updated += 1
            } else {
                activity = Activity(name: name, colorHex: member.colorHex, startHour: hour,
                                    durationMinutes: duration, anchorDate: anchor)
                context.insert(activity)
                result.added += 1
            }

            activity.name = name
            activity.member = member
            activity.location = value("location")
            activity.notes = value("notes")
            let color = value("color")
            activity.colorHex = color.hasPrefix("#") && color.count == 7 ? color : (activity.colorHex.isEmpty ? member.colorHex : activity.colorHex)
            activity.timeZoneID = tzID
            activity.startHour = hour
            activity.startMinute = minute
            activity.durationMinutes = duration
            activity.driveMinutes = Int(value("drivemin")) ?? 0
            activity.repeatKind = kind
            activity.intervalWeeks = interval
            activity.anchorDate = anchor
            activity.weekday = cal.component(.weekday, from: anchor)
            activity.weekOrdinal = 1
            if kind == .monthlyNthWeekday {
                activity.weekOrdinal = Int(value("monthlyweek")) ?? ((cal.component(.day, from: anchor) - 1) / 7 + 1)
                if let wd = weekday(value("monthlyday")) { activity.weekday = wd }
            }
            activity.skippedDays = value("skipdates")
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { date($0, cal: cal) != nil }

            // Alerts (replace).
            let old = activity.alertRules
            for r in old { context.delete(r) }
            let alertText = value("alerts").isEmpty ? "1d;2h" : value("alerts")
            for part in alertText.split(separator: ";") {
                let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard let minutes = offset(pieces[0]) else {
                    result.errors.append("Row \(line): alert '\(pieces[0])' ignored (use 1d, 2h, 30m)")
                    continue
                }
                let message = pieces.count > 1 && !pieces[1].isEmpty ? pieces[1] : defaultMessage(minutes)
                let rule = AlertRule(offsetMinutes: minutes, message: message)
                context.insert(rule)
                rule.activity = activity
            }
            changedActivities.append(activity)
        }

        try? context.save()
        FamilySync.shared.push(members: newMembers, activities: changedActivities)
        return result
    }

    // MARK: - Parsing helpers

    /// Minimal RFC 4180 CSV parser: quotes, escaped quotes (""), commas and newlines in quotes.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }   // BOM from Excel
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    private static func timeZoneID(_ text: String) -> String {
        switch text.uppercased() {
        case "", "PT", "PST", "PDT", "PACIFIC": return "America/Los_Angeles"
        case "IST", "INDIA": return "Asia/Kolkata"
        default: return TimeZone(identifier: text) != nil ? text : "America/Los_Angeles"
        }
    }

    private static func date(_ text: String, cal: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func time(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    private static func weekday(_ text: String) -> Int? {
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        guard let i = names.firstIndex(of: String(text.lowercased().prefix(3))) else { return nil }
        return i + 1
    }

    /// "1d" → 1440, "2h" → 120, "30m" → 30, "1w" → 10080
    private static func offset(_ text: String) -> Int? {
        let t = text.lowercased()
        guard let unit = t.last, let n = Int(t.dropLast()), n >= 0 else { return Int(t) }
        switch unit {
        case "w": return n * 10080
        case "d": return n * 1440
        case "h": return n * 60
        case "m": return n
        default: return nil
        }
    }

    private static func defaultMessage(_ minutes: Int) -> String {
        switch minutes {
        case 1440: return "Tomorrow"
        case let m where m % 1440 == 0: return "In \(m / 1440) days"
        case let m where m % 60 == 0: return m == 60 ? "In 1 hour" : "In \(m / 60) hours"
        default: return "In \(minutes) min"
        }
    }
}
