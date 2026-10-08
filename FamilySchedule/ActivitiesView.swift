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
    @ObservedObject private var sync = FamilySync.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: sync.isParticipant ? "person.2.fill" : "icloud.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sync.isParticipant ? "Shared by \(sync.ownerDisplayName ?? "family")" : "Family sharing")
                                .font(.headline)
                            Text(syncStatusText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if sync.isSyncing { ProgressView() }
                    }
                    if !sync.isParticipant {
                        Button("Invite family…", systemImage: "person.badge.plus") {
                            Task { await sync.presentShareSheet() }
                        }
                    }
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await sync.sync() }
                    }
                    .disabled(sync.isSyncing)
                }

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
            .refreshable { await sync.sync() }
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

    private var syncStatusText: String {
        guard let last = sync.lastSync else { return sync.status }
        return "\(sync.status) · \(last.formatted(.relative(presentation: .named)))"
    }

    private func delete(_ list: [Activity], at offsets: IndexSet) {
        let uids = offsets.map { list[$0].uid }
        for i in offsets { context.delete(list[i]) }
        try? context.save()
        FamilySync.shared.delete(uids: uids)
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespaces)
        newPersonName = ""
        guard !name.isEmpty else { return }
        let color = ActivityDraft.palette[members.count % ActivityDraft.palette.count]
        let member = Member(name: name, colorHex: color)
        context.insert(member)
        try? context.save()
        FamilySync.shared.push(member: member)
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
