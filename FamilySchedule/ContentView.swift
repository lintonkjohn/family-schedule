import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "rectangle.grid.1x2") }
            ActivitiesView()
                .tabItem { Label("Activities", systemImage: "list.bullet.rectangle") }
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
        }
        .task {
            SeedData.seedIfNeeded(context)
            _ = await NotificationScheduler.requestPermission()
            await NotificationScheduler.reschedule(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await NotificationScheduler.reschedule(context: context) }
            }
        }
    }
}
