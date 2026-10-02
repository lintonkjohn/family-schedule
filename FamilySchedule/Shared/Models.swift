import Foundation
import SwiftData

// Shared file — add to BOTH targets: FamilySchedule + NextUpWidgetExtension

@Model
final class Member {
    var name: String
    var colorHex: String
    /// Small avatar JPEG (stored outside the database file).
    @Attribute(.externalStorage) var photoData: Data? = nil
    @Relationship(deleteRule: .nullify, inverse: \Activity.member)
    var activities: [Activity] = []

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }
}

enum RepeatKind: String, Codable, CaseIterable {
    case weekly              // every N weeks, on the weekday of `anchorDate`
    case monthlyNthWeekday   // e.g. first Wednesday of each month
}

@Model
final class Activity {
    var name: String
    var location: String
    var notes: String
    var colorHex: String
    /// Time zone the activity is defined in, e.g. "America/Los_Angeles" or "Asia/Kolkata".
    var timeZoneID: String
    var startHour: Int
    var startMinute: Int
    var durationMinutes: Int
    var repeatKindRaw: String
    /// Weekly: 1 = every week, 2 = every other week.
    var intervalWeeks: Int
    /// Monthly only: 1 = Sunday … 7 = Saturday.
    var weekday: Int
    /// Monthly only: 1 = first, 2 = second …
    var weekOrdinal: Int
    /// First occurrence day (weekly repeats are counted from here).
    var anchorDate: Date
    /// Drive time; used for "Leave by". 0 = online / no travel.
    var driveMinutes: Int
    /// Skipped days as "yyyy-MM-dd" in the activity's time zone.
    var skippedDays: [String]
    var member: Member?
    @Relationship(deleteRule: .cascade, inverse: \AlertRule.activity)
    var alertRules: [AlertRule] = []

    var repeatKind: RepeatKind {
        get { RepeatKind(rawValue: repeatKindRaw) ?? .weekly }
        set { repeatKindRaw = newValue.rawValue }
    }

    init(name: String,
         location: String = "",
         notes: String = "",
         colorHex: String,
         timeZoneID: String = TimeZone.current.identifier,
         startHour: Int,
         startMinute: Int = 0,
         durationMinutes: Int,
         repeatKind: RepeatKind = .weekly,
         intervalWeeks: Int = 1,
         weekday: Int = 1,
         weekOrdinal: Int = 1,
         anchorDate: Date,
         driveMinutes: Int = 0) {
        self.name = name
        self.location = location
        self.notes = notes
        self.colorHex = colorHex
        self.timeZoneID = timeZoneID
        self.startHour = startHour
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.repeatKindRaw = repeatKind.rawValue
        self.intervalWeeks = intervalWeeks
        self.weekday = weekday
        self.weekOrdinal = weekOrdinal
        self.anchorDate = anchorDate
        self.driveMinutes = driveMinutes
        self.skippedDays = []
    }
}

@Model
final class AlertRule {
    /// Minutes before the start time.
    var offsetMinutes: Int
    var message: String
    var isEnabled: Bool
    var activity: Activity?

    init(offsetMinutes: Int, message: String, isEnabled: Bool = true) {
        self.offsetMinutes = offsetMinutes
        self.message = message
        self.isEnabled = isEnabled
    }
}
