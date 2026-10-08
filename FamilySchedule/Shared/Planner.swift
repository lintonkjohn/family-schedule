import Foundation
import SwiftData

// Shared file — add to BOTH targets.

struct Occurrence: Identifiable, Hashable {
    let id: String
    let activityName: String
    let memberName: String
    let location: String
    let colorHex: String
    let start: Date
    let end: Date
    let driveMinutes: Int
    var activityID: PersistentIdentifier? = nil

    var leaveBy: Date? {
        driveMinutes > 0 ? start.addingTimeInterval(Double(-driveMinutes * 60)) : nil
    }

    static let sample = Occurrence(id: "sample", activityName: "Robolabs", memberName: "Levin",
                                   location: "Fremont", colorHex: "#F97316",
                                   start: .now.addingTimeInterval(3600),
                                   end: .now.addingTimeInterval(3 * 3600), driveMinutes: 20)
}

struct Conflict: Identifiable {
    let a: Occurrence
    let b: Occurrence
    var id: String { a.id + "~" + b.id }
}

struct PlannedAlert: Identifiable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
    let occurrence: Occurrence
}

extension Activity {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return cal
    }

    func occurrences(from: Date, to: Date) -> [Occurrence] {
        let cal = calendar
        let anchorDay = cal.startOfDay(for: anchorDate)
        // Start one day early so an activity already in progress is included.
        var day = max(cal.startOfDay(for: from.addingTimeInterval(-86_400)), anchorDay)
        var result: [Occurrence] = []

        while day < to {
            if matches(day, cal: cal, anchorDay: anchorDay),
               !skippedDays.contains(Self.dayKey(day, cal: cal)),
               let start = cal.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day) {
                let end = start.addingTimeInterval(Double(durationMinutes * 60))
                if end > from && start < to {
                    result.append(Occurrence(
                        id: "\(name)|\(Int(start.timeIntervalSince1970))",
                        activityName: name,
                        memberName: member?.name ?? "",
                        location: location,
                        colorHex: colorHex,
                        start: start,
                        end: end,
                        driveMinutes: driveMinutes,
                        activityID: persistentModelID))
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private func matches(_ day: Date, cal: Calendar, anchorDay: Date) -> Bool {
        switch repeatKind {
        case .weekly:
            let diff = cal.dateComponents([.day], from: anchorDay, to: day).day ?? -1
            return diff >= 0 && diff % (7 * max(intervalWeeks, 1)) == 0
        case .monthlyNthWeekday:
            let c = cal.dateComponents([.weekday, .day], from: day)
            guard let wd = c.weekday, let dom = c.day else { return false }
            return wd == weekday && ((dom - 1) / 7 + 1) == weekOrdinal
        case .yearly:
            guard day >= anchorDay else { return false }
            let a = cal.dateComponents([.month, .day], from: anchorDay)
            let c = cal.dateComponents([.month, .day], from: day)
            return a.month == c.month && a.day == c.day
        }
    }

    static func dayKey(_ day: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// e.g. "Sun 3:00 PM", "Every 2 wks Fri 6:00 PM", "Fri 9:00 AM GMT+5:30"
    var scheduleSummary: String {
        let cal = calendar
        let wd = repeatKind == .weekly ? cal.component(.weekday, from: anchorDate) : weekday
        let dayName = cal.shortWeekdaySymbols[wd - 1]
        let h12 = startHour % 12 == 0 ? 12 : startHour % 12
        let time = String(format: "%d:%02d ", h12, startMinute) + (startHour < 12 ? "AM" : "PM")
        let tz = timeZoneID == TimeZone.current.identifier
            ? "" : " " + (TimeZone(identifier: timeZoneID)?.abbreviation() ?? timeZoneID)
        switch repeatKind {
        case .weekly:
            return intervalWeeks > 1
                ? "Every \(intervalWeeks) wks \(dayName) \(time)\(tz)"
                : "\(dayName) \(time)\(tz)"
        case .monthlyNthWeekday:
            let ord = ["", "1st", "2nd", "3rd", "4th", "5th"][min(max(weekOrdinal, 0), 5)]
            return "\(ord) \(dayName) monthly \(time)\(tz)"
        case .yearly:
            let md = anchorDate.formatted(.dateTime.month(.abbreviated).day())
            return "Every year \(md) \(time)\(tz)"
        }
    }
}

enum Planner {
    static func occurrences(_ activities: [Activity], from: Date, to: Date) -> [Occurrence] {
        activities.flatMap { $0.occurrences(from: from, to: to) }.sorted { $0.start < $1.start }
    }

    /// Overlapping occurrences for the same person.
    static func conflicts(in occ: [Occurrence]) -> [Conflict] {
        var result: [Conflict] = []
        for i in occ.indices {
            var j = i + 1
            while j < occ.count && occ[j].start < occ[i].end {
                if occ[j].memberName == occ[i].memberName {
                    result.append(Conflict(a: occ[i], b: occ[j]))
                }
                j += 1
            }
        }
        return result
    }

    static func alerts(_ activities: [Activity], from: Date, to: Date) -> [PlannedAlert] {
        var result: [PlannedAlert] = []
        for act in activities {
            let rules = act.alertRules.filter { $0.isEnabled }
            guard !rules.isEmpty else { continue }
            let maxOffset = rules.map(\.offsetMinutes).max() ?? 0
            for occ in act.occurrences(from: from, to: to.addingTimeInterval(Double(maxOffset * 60))) {
                for rule in rules {
                    let fire = occ.start.addingTimeInterval(Double(-rule.offsetMinutes * 60))
                    guard fire >= from, fire < to else { continue }
                    let when = occ.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
                    result.append(PlannedAlert(
                        id: "\(occ.id)|\(rule.offsetMinutes)",
                        fireDate: fire,
                        title: occ.memberName.isEmpty ? occ.activityName : "\(occ.memberName) · \(occ.activityName)",
                        body: "\(rule.message) · \(when)",
                        occurrence: occ))
                }
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }
}
