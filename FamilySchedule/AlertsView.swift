import SwiftUI
import SwiftData

struct AlertsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.name) private var activities: [Activity]
    @State private var mutedIDs: Set<String> = MuteStore.all()

    var body: some View {
        NavigationStack {
            let now = Date()
            let upcoming = Planner.alerts(activities, from: now, to: now.addingTimeInterval(7 * 86_400))

            List {
                Section("Next 7 days") {
                    if upcoming.isEmpty {
                        Text("No alerts scheduled").foregroundStyle(.secondary)
                    }
                    ForEach(upcoming) { alert in
                        Toggle(isOn: Binding(
                            get: { !mutedIDs.contains(alert.id) },
                            set: { on in
                                MuteStore.set(alert.id, muted: !on)
                                mutedIDs = MuteStore.all()
                                reschedule()
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.title).font(.headline)
                                Text(alert.body).font(.subheadline)
                                Text(alert.fireDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Rules") {
                    ForEach(activities) { act in
                        DisclosureGroup {
                            ForEach(act.alertRules.sorted { $0.offsetMinutes > $1.offsetMinutes }) { rule in
                                RuleRow(rule: rule, onChange: {
                                    reschedule()
                                    FamilySync.shared.push(activity: act)
                                })
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(act.name).font(.headline)
                                Text(act.scheduleSummary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Send test alert (5 sec)") { NotificationScheduler.sendTest() }
                } footer: {
                    Text("Lock your phone after tapping to see the alert.")
                }
            }
            .navigationTitle("Alerts")
        }
    }

    private func reschedule() {
        Task { await NotificationScheduler.reschedule(context: context) }
    }
}

struct RuleRow: View {
    @Bindable var rule: AlertRule
    let onChange: () -> Void

    var body: some View {
        Toggle(isOn: $rule.isEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.message)
                Text(offsetText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: rule.isEnabled) { onChange() }
    }

    private var offsetText: String {
        let m = rule.offsetMinutes
        if m % 1440 == 0 { return m == 1440 ? "1 day before" : "\(m / 1440) days before" }
        if m >= 60 && m % 60 == 0 { return "\(m / 60) hr before" }
        return "\(m) min before"
    }
}
