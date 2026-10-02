import SwiftUI
import SwiftData

struct ActivitiesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.name) private var activities: [Activity]
    @Query(sort: \Member.name) private var members: [Member]
    @State private var editing: Activity?
    @State private var showingNew = false
    @State private var showingAddPerson = false
    @State private var newPersonName = ""
    @State private var editingMember: Member?

    var body: some View {
        NavigationStack {
            List {
                if !members.isEmpty {
                    Section("People") {
                        ForEach(members) { m in
                            Button { editingMember = m } label: {
                                HStack(spacing: 12) {
                                    MemberAvatar(member: m, size: 40)
                                    VStack(alignment: .leading) {
                                        Text(m.name).font(.headline)
                                        Text(m.photoData == nil ? "Tap to add a photo" : "\(m.activities.count) activities")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if activities.isEmpty {
                    Text("No activities yet. Tap + to add one.").foregroundStyle(.secondary)
                }
                ForEach(members) { member in
                    let acts = activities.filter { $0.member?.persistentModelID == member.persistentModelID }
                    Section(member.name) {
                        if acts.isEmpty {
                            Text("Nothing scheduled").foregroundStyle(.secondary)
                        }
                        ForEach(acts) { act in
                            Button { editing = act } label: { ActivityListRow(activity: act) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { delete(acts, at: $0) }
                    }
                }
                let unassigned = activities.filter { $0.member == nil }
                if !unassigned.isEmpty {
                    Section("No person") {
                        ForEach(unassigned) { act in
                            Button { editing = act } label: { ActivityListRow(activity: act) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { delete(unassigned, at: $0) }
                    }
                }
            }
            .navigationTitle("Activities")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New activity", systemImage: "calendar.badge.plus") { showingNew = true }
                        Button("New person", systemImage: "person.badge.plus") { showingAddPerson = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) { ActivityEditView(activity: nil) }
            .sheet(item: $editing) { ActivityEditView(activity: $0) }
            .sheet(item: $editingMember) { MemberEditView(member: $0) }
            .alert("New person", isPresented: $showingAddPerson) {
                TextField("Name", text: $newPersonName)
                Button("Add") { addPerson() }
                Button("Cancel", role: .cancel) { newPersonName = "" }
            }
        }
    }

    private func delete(_ list: [Activity], at offsets: IndexSet) {
        for i in offsets { context.delete(list[i]) }
        try? context.save()
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespaces)
        newPersonName = ""
        guard !name.isEmpty else { return }
        let color = ActivityDraft.palette[members.count % ActivityDraft.palette.count]
        context.insert(Member(name: name, colorHex: color))
        try? context.save()
    }
}

struct ActivityListRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: activity.colorHex)).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name).font(.headline)
                Text(activity.scheduleSummary).font(.subheadline).foregroundStyle(.secondary)
                let n = activity.alertRules.count
                Text(n == 1 ? "1 alert" : "\(n) alerts").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
