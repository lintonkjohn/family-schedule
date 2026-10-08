import SwiftUI
import SwiftData

enum ScheduleRange: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 31, threeMonths = 92, sixMonths = 183
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .threeMonths: return "3 Mo"
        case .sixMonths: return "6 Mo"
        }
    }
}

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.name) private var activities: [Activity]
    @Query(sort: \Member.name) private var members: [Member]
    @State private var memberFilter = "All"
    @State private var editing: Activity?
    @State private var showingNew = false
    @State private var range: ScheduleRange = .week
    @State private var dayOffset = 0

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { tl in
                let now = tl.date
                let cal = Calendar.current
                let selectedDay = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) ?? now
                let week = filtered(Planner.occurrences(activities, from: now, to: now.addingTimeInterval(7 * 86_400)))
                let occ: [Occurrence] = switch range {
                case .day: filtered(Planner.occurrences(activities, from: selectedDay,
                                                        to: cal.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay))
                case .week: week
                default: filtered(Planner.occurrences(activities, from: now,
                                                      to: now.addingTimeInterval(Double(range.rawValue) * 86_400)))
                }
                let conflicts = Planner.conflicts(in: occ)
                let weekCount = week.count

                List {
                    Section {
                        FamilyHeader(weekCount: weekCount, members: members)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    if members.count > 1 {
                        Picker("Person", selection: $memberFilter) {
                            Text("All").tag("All")
                            ForEach(members) { Text($0.name).tag($0.name) }
                        }
                        .pickerStyle(.segmented)
                    }

                    Picker("Range", selection: $range) {
                        ForEach(ScheduleRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let next = week.first {
                        Section("Next up") {
                            NextUpCard(occ: next, now: now, member: member(for: next))
                                .listRowBackground(
                                    LinearGradient(colors: [Color(hex: next.colorHex).opacity(0.28),
                                                            Color(.secondarySystemGroupedBackground)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }

                    if !conflicts.isEmpty {
                        Section("Conflicts (\(conflicts.count))") {
                            ForEach(conflicts.prefix(range == .week ? conflicts.count : 3)) { c in
                                Label {
                                    Text("\(c.a.activityName) overlaps \(c.b.activityName) · \(c.a.start, format: .dateTime.weekday(.abbreviated).month().day())")
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                .foregroundStyle(.orange)
                                Menu {
                                    Button("Skip \(c.a.activityName) that day") { skip(c.a) }
                                    Button("Skip \(c.b.activityName) that day") { skip(c.b) }
                                } label: {
                                    Label("Resolve…", systemImage: "calendar.badge.minus")
                                }
                                .font(.subheadline)
                            }
                        }
                    }

                    if range == .day {
                        Section {
                            HStack {
                                Button { dayOffset -= 1 } label: { Image(systemName: "chevron.left") }
                                Spacer()
                                VStack(spacing: 2) {
                                    Text(dayTitle(dayOffset)).font(.headline)
                                    Text(selectedDay, format: .dateTime.weekday(.wide).month().day())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .onTapGesture { dayOffset = 0 }
                                Spacer()
                                Button { dayOffset += 1 } label: { Image(systemName: "chevron.right") }
                            }
                            .buttonStyle(.borderless)

                            if occ.isEmpty {
                                Text("Nothing scheduled").foregroundStyle(.secondary)
                            }
                            ForEach(occ) { o in
                                Button { editing = activity(for: o) } label: { OccurrenceRow(occ: o, member: member(for: o)) }
                                    .buttonStyle(.plain)
                                    .opacity(o.end < now ? 0.45 : 1)
                            }
                        }
                    } else if range == .week {
                        ForEach(groupByDay(occ), id: \.day) { group in
                            Section {
                                ForEach(group.items) { o in
                                    Button { editing = activity(for: o) } label: { OccurrenceRow(occ: o, member: member(for: o)) }
                                        .buttonStyle(.plain)
                                }
                            } header: {
                                Text(group.day, format: .dateTime.weekday(.wide).month().day())
                            }
                        }
                    } else {
                        ForEach(groupByMonth(occ), id: \.day) { group in
                            Section {
                                ForEach(group.items) { o in
                                    Button { editing = activity(for: o) } label: { OccurrenceRow(occ: o, showDate: true, member: member(for: o)) }
                                        .buttonStyle(.plain)
                                }
                            } header: {
                                Text("\(group.day, format: .dateTime.month(.wide).year()) · \(group.items.count) events")
                            }
                        }
                    }
                }
                .navigationTitle("Family Schedule")
                .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) { ActivityEditView(activity: nil) }
            .sheet(item: $editing) { ActivityEditView(activity: $0) }
        }
    }

    private func filtered(_ list: [Occurrence]) -> [Occurrence] {
        memberFilter == "All" ? list : list.filter { $0.memberName == memberFilter }
    }

    private func dayTitle(_ offset: Int) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return offset > 0 ? "In \(offset) days" : "\(-offset) days ago"
        }
    }

    private func member(for o: Occurrence) -> Member? {
        members.first { $0.name == o.memberName }
    }

    private func activity(for o: Occurrence) -> Activity? {
        activities.first { $0.persistentModelID == o.activityID }
    }

    /// Skip one occurrence (e.g. Robolabs on a PLC Wednesday).
    private func skip(_ o: Occurrence) {
        guard let act = activity(for: o) else { return }
        act.skippedDays.append(Activity.dayKey(o.start, cal: act.calendar))
        try? context.save()
        FamilySync.shared.push(activity: act)
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    private struct DayGroup { let day: Date; let items: [Occurrence] }

    private func groupByDay(_ occ: [Occurrence]) -> [DayGroup] {
        let grouped = Dictionary(grouping: occ) { Calendar.current.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { DayGroup(day: $0, items: grouped[$0] ?? []) }
    }

    private func groupByMonth(_ occ: [Occurrence]) -> [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: occ) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.start)) ?? $0.start
        }
        return grouped.keys.sorted().map { DayGroup(day: $0, items: grouped[$0] ?? []) }
    }
}

struct NextUpCard: View {
    let occ: Occurrence
    let now: Date
    var member: Member? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Color(hex: occ.colorHex)).frame(width: 10, height: 10)
                Text(occ.activityName).font(.title2.bold())
                Spacer()
                if let member {
                    VStack(spacing: 2) {
                        MemberAvatar(member: member, size: 44)
                        Text(member.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text("\(occ.start, format: .dateTime.weekday(.abbreviated).hour().minute()) – \(occ.end, format: .dateTime.hour().minute())")
                .font(.subheadline)

            if occ.start > now {
                Text("Starts in \(occ.start, style: .relative)").foregroundStyle(.secondary)
            } else {
                Text("In progress · ends \(occ.end, style: .time)").foregroundStyle(.green)
            }

            if let leave = occ.leaveBy, leave > now {
                Label {
                    Text("Leave by \(leave, style: .time)")
                } icon: {
                    Image(systemName: "car.fill")
                }
                .foregroundStyle(.blue)
                .font(.headline)
            }

            if !occ.location.isEmpty {
                Label(occ.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct OccurrenceRow: View {
    let occ: Occurrence
    var showDate = false
    var member: Member? = nil

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: occ.colorHex))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(occ.activityName).font(.headline)
                if showDate {
                    Text(occ.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.subheadline.bold())
                }
                Text("\(occ.start, format: .dateTime.hour().minute()) – \(occ.end, format: .dateTime.hour().minute())\(occ.memberName.isEmpty ? "" : " · " + occ.memberName)")
                    .font(.subheadline)
                if let leave = occ.leaveBy {
                    Text("Leave by \(leave, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            if let member {
                MemberAvatar(member: member, size: 30)
            }
        }
        .contentShape(Rectangle())
    }
}
