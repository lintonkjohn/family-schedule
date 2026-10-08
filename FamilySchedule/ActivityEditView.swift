import SwiftUI
import SwiftData

enum RepeatChoice: String, CaseIterable, Identifiable {
    case weekly, everyTwoWeeks, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weekly: return "Every week"
        case .everyTwoWeeks: return "Every 2 weeks"
        case .monthly: return "Monthly (e.g. 1st Wed)"
        case .yearly: return "Every year"
        }
    }
}

struct AlertDraft: Identifiable {
    let id = UUID()
    var offsetMinutes: Int
    var message: String
}

/// Editable copy of an Activity, so Cancel discards changes.
struct ActivityDraft {
    static let palette = ["#2563EB", "#F97316", "#16A34A", "#9333EA", "#CA8A04", "#DC2626", "#0EA5E9", "#DB2777"]
    static let offsets = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 1380, 1440, 2880, 10080]

    var name = ""
    var memberID: PersistentIdentifier?
    var location = ""
    var colorHex = ActivityDraft.palette[0]
    var timeZoneID = TimeZone.current.identifier
    var hour = 18
    var minute = 0
    var durationMinutes = 60
    var driveMinutes = 0
    var repeatChoice: RepeatChoice = .weekly
    var weekday = 4          // monthly only (1 = Sun)
    var weekOrdinal = 1      // monthly only
    var year: Int
    var month: Int
    var day: Int
    var alerts: [AlertDraft] = [
        AlertDraft(offsetMinutes: 1440, message: "Tomorrow"),
        AlertDraft(offsetMinutes: 120, message: "In 2 hours"),
        AlertDraft(offsetMinutes: 30, message: "Starting soon"),
    ]

    init(_ a: Activity?) {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        year = today.year ?? 2026; month = today.month ?? 1; day = today.day ?? 1
        guard let a else { return }
        name = a.name
        memberID = a.member?.persistentModelID
        location = a.location
        colorHex = a.colorHex
        timeZoneID = a.timeZoneID
        hour = a.startHour
        minute = a.startMinute
        durationMinutes = a.durationMinutes
        driveMinutes = a.driveMinutes
        switch a.repeatKind {
        case .monthlyNthWeekday: repeatChoice = .monthly
        case .yearly: repeatChoice = .yearly
        case .weekly: repeatChoice = a.intervalWeeks > 1 ? .everyTwoWeeks : .weekly
        }
        weekday = a.weekday
        weekOrdinal = a.weekOrdinal
        let c = a.calendar.dateComponents([.year, .month, .day], from: a.anchorDate)
        year = c.year ?? year; month = c.month ?? month; day = c.day ?? day
        alerts = a.alertRules
            .sorted { $0.offsetMinutes > $1.offsetMinutes }
            .map { AlertDraft(offsetMinutes: $0.offsetMinutes, message: $0.message) }
    }
}

func offsetLabel(_ m: Int) -> String {
    if m == 10080 { return "1 week before" }
    if m % 1440 == 0 { return m == 1440 ? "1 day before" : "\(m / 1440) days before" }
    if m >= 60 && m % 60 == 0 { return "\(m / 60) hr before" }
    return "\(m) min before"
}

struct ActivityEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.name) private var members: [Member]

    let activity: Activity?
    @State private var d: ActivityDraft

    init(activity: Activity?) {
        self.activity = activity
        _d = State(initialValue: ActivityDraft(activity))
    }

    private var tzCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: d.timeZoneID) ?? .current
        return cal
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { tzCalendar.date(bySettingHour: d.hour, minute: d.minute, second: 0, of: .now) ?? .now },
            set: {
                let c = tzCalendar.dateComponents([.hour, .minute], from: $0)
                d.hour = c.hour ?? d.hour
                d.minute = c.minute ?? d.minute
            })
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { tzCalendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12)) ?? .now },
            set: {
                let c = tzCalendar.dateComponents([.year, .month, .day], from: $0)
                d.year = c.year ?? d.year; d.month = c.month ?? d.month; d.day = c.day ?? d.day
            })
    }

    private var weekdayName: String {
        let wd = tzCalendar.component(.weekday, from: dateBinding.wrappedValue)
        return tzCalendar.weekdaySymbols[wd - 1]
    }

    private var timeZoneIDs: [String] {
        var ids = [TimeZone.current.identifier, "America/Los_Angeles", "Asia/Kolkata"]
        if !ids.contains(d.timeZoneID) { ids.append(d.timeZoneID) }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private var offsetChoices: [Int] {
        Array(Set(ActivityDraft.offsets + d.alerts.map(\.offsetMinutes))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("Name (e.g. Swim)", text: $d.name)
                    Picker("Person", selection: $d.memberID) {
                        Text("None").tag(PersistentIdentifier?.none)
                        ForEach(members) { m in
                            Text(m.name).tag(Optional(m.persistentModelID))
                        }
                    }
                    TextField("Location", text: $d.location)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ActivityDraft.palette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: d.colorHex == hex ? 3 : 0))
                                    .onTapGesture { d.colorHex = hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Picker("Repeats", selection: $d.repeatChoice) {
                        ForEach(RepeatChoice.allCases) { Text($0.label).tag($0) }
                    }
                    if d.repeatChoice == .monthly {
                        Picker("Week", selection: $d.weekOrdinal) {
                            ForEach(1...4, id: \.self) { Text(["1st", "2nd", "3rd", "4th"][$0 - 1]).tag($0) }
                        }
                        Picker("Day", selection: $d.weekday) {
                            ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                        }
                        DatePicker("Starting from", selection: dateBinding, displayedComponents: .date)
                    } else {
                        DatePicker("First date", selection: dateBinding, displayedComponents: .date)
                    }
                    DatePicker("Start time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    Stepper("Duration: \(durationText)", value: $d.durationMinutes, in: 15...720, step: 15)
                    Picker("Time zone", selection: $d.timeZoneID) {
                        ForEach(timeZoneIDs, id: \.self) { id in
                            Text(TimeZone(identifier: id)?.localizedName(for: .generic, locale: .current) ?? id).tag(id)
                        }
                    }
                    Stepper("Drive time: \(d.driveMinutes == 0 ? "None" : "\(d.driveMinutes) min")",
                            value: $d.driveMinutes, in: 0...120, step: 5)
                } header: {
                    Text("When")
                } footer: {
                    if d.repeatChoice == .yearly {
                        Text("Repeats every year on \(dateBinding.wrappedValue.formatted(.dateTime.month(.wide).day())).")
                    } else if d.repeatChoice != .monthly {
                        Text("Repeats on \(weekdayName)s. Drive time sets the \"Leave by\" time.")
                    }
                }
                .environment(\.timeZone, TimeZone(identifier: d.timeZoneID) ?? .current)

                Section("Alerts") {
                    ForEach($d.alerts) { $alert in
                        VStack(alignment: .leading) {
                            Picker("When", selection: $alert.offsetMinutes) {
                                ForEach(offsetChoices, id: \.self) { Text(offsetLabel($0)).tag($0) }
                            }
                            TextField("Message", text: $alert.message)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { d.alerts.remove(atOffsets: $0) }
                    Button("Add alert", systemImage: "bell.badge") {
                        d.alerts.append(AlertDraft(offsetMinutes: 30,
                                                   message: d.name.isEmpty ? "Starting soon" : "\(d.name) soon"))
                    }
                }

                if activity != nil {
                    Section {
                        Button("Delete activity", role: .destructive) { deleteActivity() }
                    }
                }
            }
            .navigationTitle(activity == nil ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(d.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if activity == nil && d.memberID == nil { d.memberID = members.first?.persistentModelID }
            }
        }
    }

    private var durationText: String {
        let h = d.durationMinutes / 60, m = d.durationMinutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    private func save() {
        let a: Activity
        if let activity {
            a = activity
        } else {
            a = Activity(name: "", colorHex: d.colorHex, startHour: d.hour, durationMinutes: d.durationMinutes, anchorDate: .now)
            context.insert(a)
        }
        a.name = d.name.trimmingCharacters(in: .whitespaces)
        a.location = d.location
        a.colorHex = d.colorHex
        a.timeZoneID = d.timeZoneID
        a.startHour = d.hour
        a.startMinute = d.minute
        a.durationMinutes = d.durationMinutes
        a.driveMinutes = d.driveMinutes
        switch d.repeatChoice {
        case .monthly: a.repeatKind = .monthlyNthWeekday
        case .yearly: a.repeatKind = .yearly
        default: a.repeatKind = .weekly
        }
        a.intervalWeeks = d.repeatChoice == .everyTwoWeeks ? 2 : 1
        a.weekday = d.weekday
        a.weekOrdinal = d.weekOrdinal
        a.anchorDate = tzCalendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) ?? .now
        a.member = members.first { $0.persistentModelID == d.memberID }

        let oldRules = a.alertRules
        for r in oldRules { context.delete(r) }
        for draft in d.alerts {
            let r = AlertRule(offsetMinutes: draft.offsetMinutes, message: draft.message)
            context.insert(r)
            r.activity = a
        }

        try? context.save()
        FamilySync.shared.push(activity: a)
        Task { await NotificationScheduler.reschedule(context: context) }
        dismiss()
    }

    private func deleteActivity() {
        let uid = activity?.uid ?? ""
        if let activity { context.delete(activity) }
        try? context.save()
        FamilySync.shared.delete(uids: [uid])
        Task { await NotificationScheduler.reschedule(context: context) }
        dismiss()
    }
}
