import Foundation
import SwiftData
import UserNotifications
import WidgetKit

// App target only.

enum NotificationScheduler {
    /// iOS allows max 64 pending local notifications per app.
    static let maxPending = 60
    static let windowDays = 14.0

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuilds all pending alerts for the next 14 days. Called on launch,
    /// whenever the app comes to the foreground, and after any edit.
    @MainActor
    static func reschedule(context: ModelContext) async {
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let now = Date()
        let muted = MuteStore.all()
        let planned = Planner.alerts(activities, from: now, to: now.addingTimeInterval(windowDays * 86_400))
            .filter { $0.fireDate > now && !muted.contains($0.id) }
            .prefix(maxPending)

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for alert in planned {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: alert.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    static func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Family Schedule"
        content.body = "Test alert — notifications are working."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }
}
