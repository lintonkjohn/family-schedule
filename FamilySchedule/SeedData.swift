import Foundation
import SwiftData

// App target only. Loads Levin's starter schedule when the store is empty.

enum SeedData {
    static let pt = "America/Los_Angeles"
    static let ist = "Asia/Kolkata"

    /// Starter data only. Add and edit activities in the app (Activities tab).
    /// Bumping this wipes in-app changes and reloads this file — normally leave it alone.
    static let version = 2

    /// Added to every activity once (existing alerts are kept).
    static let standardAlerts: [(Int, String)] = [
        (2 * 1440, "In 2 days"),
        (1440, "Tomorrow"),
        (120, "In 2 hours"),
    ]

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        seedStarterSchedule(context)
        addStandardAlertsOnce(context)
    }

    @MainActor
    static func addStandardAlertsOnce(_ context: ModelContext) {
        let key = "standardAlertsV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for a in (try? context.fetch(FetchDescriptor<Activity>())) ?? [] {
            for (offset, message) in standardAlerts where !a.alertRules.contains(where: { $0.offsetMinutes == offset }) {
                let r = AlertRule(offsetMinutes: offset, message: message)
                context.insert(r)
                r.activity = a
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    @MainActor
    static func seedStarterSchedule(_ context: ModelContext) {
        let key = "seedVersion"
        let count = (try? context.fetchCount(FetchDescriptor<Member>())) ?? 0
        if count > 0 && UserDefaults.standard.integer(forKey: key) >= version { return }

        // Delete one by one (batch delete fails silently with relationships).
        for r in (try? context.fetch(FetchDescriptor<AlertRule>())) ?? [] { context.delete(r) }
        for a in (try? context.fetch(FetchDescriptor<Activity>())) ?? [] { context.delete(a) }
        for m in (try? context.fetch(FetchDescriptor<Member>())) ?? [] { context.delete(m) }
        try? context.save()
        UserDefaults.standard.set(version, forKey: key)

        let levin = Member(name: "Levin", colorHex: "#2563EB")
        context.insert(levin)

        func add(_ a: Activity, _ rules: [(Int, String)]) {
            context.insert(a)
            a.member = levin
            for (offset, message) in rules {
                let r = AlertRule(offsetMinutes: offset, message: message)
                context.insert(r)
                r.activity = a
            }
        }

        // Robolabs — Sundays 3–6pm, Fremont
        add(Activity(name: "Robolabs", location: "Robolabs, Fremont", colorHex: "#F97316",
                     timeZoneID: pt, startHour: 15, durationMinutes: 180,
                     anchorDate: day(2026, 10, 4, pt), driveMinutes: 20),
            [(30, "Leave in 10 min for Robolabs")])

        // Robolabs — Wednesdays 6–8pm, Fremont
        add(Activity(name: "Robolabs", location: "Robolabs, Fremont", colorHex: "#F97316",
                     timeZoneID: pt, startHour: 18, durationMinutes: 120,
                     anchorDate: day(2026, 10, 7, pt), driveMinutes: 20),
            [(30, "Leave in 10 min for Robolabs")])

        // RSM — Tuesdays 6–8pm
        add(Activity(name: "RSM", location: "RSM", colorHex: "#16A34A",
                     timeZoneID: pt, startHour: 18, durationMinutes: 120,
                     anchorDate: day(2026, 10, 6, pt), driveMinutes: 15),
            [(30, "RSM soon — homework + calculator")])

        // Piano — Fridays 9:00am IST (online) = Thursday evening in California
        add(Activity(name: "Piano", location: "Online", colorHex: "#9333EA",
                     timeZoneID: ist, startHour: 9, durationMinutes: 60,
                     anchorDate: day(2026, 10, 2, ist)),
            [(10, "Piano in 10 min — open the class link")])

        // Scouts troop meeting — every other Friday 6–8pm, from Oct 2
        add(Activity(name: "Scouts Troop Meeting", location: "Troop 273", colorHex: "#CA8A04",
                     timeZoneID: pt, startHour: 18, durationMinutes: 120,
                     intervalWeeks: 2, anchorDate: day(2026, 10, 2, pt), driveMinutes: 15),
            [(23 * 60, "Scouts tomorrow — uniform + handbook"),
             (45, "Scouts at 6 — get ready to leave")])

        // PLC — first Wednesday of the month 6–8pm
        add(Activity(name: "PLC Meeting", location: "Troop 273", colorHex: "#DC2626",
                     timeZoneID: pt, startHour: 18, durationMinutes: 120,
                     repeatKind: .monthlyNthWeekday, weekday: 4, weekOrdinal: 1,
                     anchorDate: day(2026, 10, 1, pt), driveMinutes: 15),
            [(24 * 60, "PLC meeting tomorrow"),
             (45, "PLC meeting at 6 — get ready to leave")])

        try? context.save()
    }

    static func day(_ y: Int, _ m: Int, _ d: Int, _ tz: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? .current
        return cal.date(from: DateComponents(year: y, month: m, day: d)) ?? .now
    }
}
