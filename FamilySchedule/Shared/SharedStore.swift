import Foundation
import SwiftData
import SwiftUI

// Shared file — add to BOTH targets.

enum SharedStore {
    static let appGroup = "group.com.linton.familyschedule"

    static let container: ModelContainer = {
        let schema = Schema([Member.self, Activity.self, AlertRule.self])
        // cloudKitDatabase: .none — we sync ourselves in FamilySync.swift.
        // Without this, SwiftData sees the iCloud entitlement and tries its own
        // CloudKit mirroring, which fails for this schema and crashes on launch.
        let config = ModelConfiguration(schema: schema,
                                        groupContainer: .identifier(appGroup),
                                        cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

/// Per-occurrence mutes (e.g. silence just this Wednesday's Robolabs alert).
enum MuteStore {
    private static let key = "mutedAlertIDs"
    private static var defaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup) ?? .standard }

    static func all() -> Set<String> { Set(defaults.stringArray(forKey: key) ?? []) }
    static func isMuted(_ id: String) -> Bool { all().contains(id) }
    static func set(_ id: String, muted: Bool) {
        var s = all()
        if muted { s.insert(id) } else { s.remove(id) }
        defaults.set(Array(s), forKey: key)
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
