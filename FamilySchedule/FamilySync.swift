import Foundation
import CloudKit
import SwiftData
import UIKit

/// Shares one family schedule across Apple IDs using a CloudKit zone-wide share.
///
/// - The **owner** (whoever taps "Invite family") keeps the data in a "FamilyZone"
///   in their private iCloud database and shares the whole zone.
/// - **Participants** accept the share link and read/write the same zone through
///   their shared database.
/// - iCloud is the source of truth: `sync()` pulls everything and updates the local
///   SwiftData store; every local edit pushes just the changed records.
/// - Alert mutes and the family photo stay per-device.
@MainActor
final class FamilySync: ObservableObject {
    static let shared = FamilySync()
    static let containerID = "iCloud.com.linton.familyschedule"

    @Published private(set) var status = "Not synced yet"
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?

    private let ck = CKContainer(identifier: FamilySync.containerID)
    private let defaults = UserDefaults.standard
    private let defaultZoneName = "FamilyZone"

    private var context: ModelContext { SharedStore.container.mainContext }

    // MARK: - Role

    var isParticipant: Bool { defaults.string(forKey: "sync.ownerName") != nil }
    var ownerDisplayName: String? { defaults.string(forKey: "sync.ownerDisplay") }

    private var zoneID: CKRecordZone.ID {
        if let owner = defaults.string(forKey: "sync.ownerName") {
            return CKRecordZone.ID(zoneName: defaults.string(forKey: "sync.zoneName") ?? defaultZoneName,
                                   ownerName: owner)
        }
        return CKRecordZone.ID(zoneName: defaultZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var database: CKDatabase {
        isParticipant ? ck.sharedCloudDatabase : ck.privateCloudDatabase
    }

    // MARK: - Full sync

    /// Pulls the family schedule from iCloud. On the owner's first run (empty zone),
    /// uploads the local schedule instead.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            guard try await ck.accountStatus() == .available else {
                status = "Sign in to iCloud to share the schedule"
                return
            }
            ensureUIDs()
            if !isParticipant { try await ensureZone() }
            let remote = try await fetchAll()
            let localActivities = allActivities()
            let remoteHasActivities = remote.contains { $0.recordType == "Activity" }
            if !isParticipant && (remote.isEmpty || (!remoteHasActivities && !localActivities.isEmpty)) {
                // Owner's first upload (or a previous upload only half-finished):
                // make iCloud match this phone instead of wiping local activities.
                let local = records(members: allMembers(), activities: localActivities)
                let localIDs = Set(local.map(\.recordID))
                let stale = remote.map(\.recordID).filter { !localIDs.contains($0) }
                try await save(local, deleting: stale)
            } else {
                apply(remote)
            }
            lastSync = .now
            status = "Synced"
            await NotificationScheduler.reschedule(context: context)
        } catch {
            status = "Sync error: \(error.localizedDescription)"
        }
    }

    // MARK: - Pushing local edits

    func push(activity: Activity) {
        let recs = records(members: [], activities: [activity])
        pushInBackground(recs, deleting: [])
    }

    func push(member: Member) {
        let recs = records(members: [member], activities: member.activities)
        pushInBackground(recs, deleting: [])
    }

    /// Call with the uids captured *before* deleting the local objects.
    func delete(uids: [String], thenPush activities: [Activity] = []) {
        let recs = records(members: [], activities: activities)
        pushInBackground(recs, deleting: uids)
    }

    private func pushInBackground(_ recs: [CKRecord], deleting uids: [String]) {
        let ids = uids.filter { !$0.isEmpty }.map(recordID)
        Task {
            do {
                if !isParticipant { try await ensureZone() }
                try await save(recs, deleting: ids)
                lastSync = .now
                status = "Synced"
            } catch {
                status = "Not uploaded yet: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sharing

    /// Opens Apple's share sheet so you can invite family members by Messages / email.
    func presentShareSheet() async {
        guard !isParticipant else { return }
        do {
            try await ensureZone()
            try await save(records(members: allMembers(), activities: allActivities()))
            let share = try await zoneShare()
            let controller = UICloudSharingController(share: share, container: ck)
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            guard let top = topViewController() else { return }
            controller.popoverPresentationController?.sourceView = top.view
            top.present(controller, animated: true)
        } catch {
            status = "Couldn't open sharing: \(error.localizedDescription)"
        }
    }

    private func zoneShare() async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await ck.privateCloudDatabase.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Linton Family Schedule"
        share.publicPermission = .none
        let result = try await ck.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        if case .failure(let error)? = result.saveResults[share.recordID] { throw error }
        return share
    }

    /// Called when someone taps an invite link and opens the app.
    func accept(_ metadata: CKShare.Metadata) async {
        guard metadata.participantRole != .owner else { return }
        do {
            _ = try await ck.accept(metadata)
            let zid = metadata.share.recordID.zoneID
            defaults.set(zid.ownerName, forKey: "sync.ownerName")
            defaults.set(zid.zoneName, forKey: "sync.zoneName")
            if let name = metadata.ownerIdentity.nameComponents {
                defaults.set(PersonNameComponentsFormatter().string(from: name), forKey: "sync.ownerDisplay")
            }
            status = "Joined the family schedule"
            await sync()
        } catch {
            status = "Couldn't join: \(error.localizedDescription)"
        }
    }

    // MARK: - CloudKit helpers

    private func ensureZone() async throws {
        guard !defaults.bool(forKey: "sync.zoneReady") else { return }
        _ = try await ck.privateCloudDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        defaults.set(true, forKey: "sync.zoneReady")
    }

    private func fetchAll() async throws -> [CKRecord] {
        var token: CKServerChangeToken?
        var all: [CKRecord] = []
        var more = true
        while more {
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, result) in page.modificationResultsByID {
                if case .success(let mod) = result { all.append(mod.record) }
            }
            token = page.changeToken
            more = page.moreComing
        }
        return all.filter { $0.recordType == "Member" || $0.recordType == "Activity" }
    }

    private func save(_ recs: [CKRecord], deleting ids: [CKRecord.ID] = []) async throws {
        guard !recs.isEmpty || !ids.isEmpty else { return }
        var start = 0
        repeat {
            let chunk = Array(recs[start..<min(start + 300, recs.count)])
            let dels = start == 0 ? ids : []
            let result = try await database.modifyRecords(saving: chunk, deleting: dels,
                                                          savePolicy: .allKeys, atomically: false)
            for (_, r) in result.saveResults {
                if case .failure(let error) = r { throw error }
            }
            start += 300
        } while start < recs.count
    }

    private func recordID(_ uid: String) -> CKRecord.ID {
        CKRecord.ID(recordName: uid, zoneID: zoneID)
    }

    // MARK: - Local <-> record mapping

    private struct RuleDTO: Codable, Equatable {
        var o: Int
        var m: String
        var e: Bool
    }

    private func records(members: [Member], activities: [Activity]) -> [CKRecord] {
        ensureUIDs()
        var out: [CKRecord] = []
        for m in members {
            let r = CKRecord(recordType: "Member", recordID: recordID(m.uid))
            r["name"] = m.name
            r["colorHex"] = m.colorHex
            if let data = m.photoData {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(m.uid).jpg")
                try? data.write(to: url)
                r["photo"] = CKAsset(fileURL: url)
            } else {
                r.setObject(nil, forKey: "photo")
            }
            out.append(r)
        }
        for a in activities {
            let r = CKRecord(recordType: "Activity", recordID: recordID(a.uid))
            r["name"] = a.name
            r["location"] = a.location
            r["notes"] = a.notes
            r["colorHex"] = a.colorHex
            r["timeZoneID"] = a.timeZoneID
            r["startHour"] = a.startHour
            r["startMinute"] = a.startMinute
            r["durationMinutes"] = a.durationMinutes
            r["repeatKindRaw"] = a.repeatKindRaw
            r["intervalWeeks"] = a.intervalWeeks
            r["weekday"] = a.weekday
            r["weekOrdinal"] = a.weekOrdinal
            r["anchorDate"] = a.anchorDate
            r["driveMinutes"] = a.driveMinutes
            // Stored as one comma-separated string: CloudKit rejects empty lists
            // for a new field, which made Activity uploads fail.
            r["skippedDays"] = a.skippedDays.joined(separator: ",")
            r["memberUID"] = a.member?.uid ?? ""
            r["rules"] = rulesJSON(a)
            out.append(r)
        }
        return out
    }

    private func ruleDTOs(_ a: Activity) -> [RuleDTO] {
        a.alertRules
            .sorted { ($0.offsetMinutes, $0.message) > ($1.offsetMinutes, $1.message) }
            .map { RuleDTO(o: $0.offsetMinutes, m: $0.message, e: $0.isEnabled) }
    }

    private func rulesJSON(_ a: Activity) -> String {
        let data = (try? JSONEncoder().encode(ruleDTOs(a))) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Updates the local store to match iCloud (insert / update / delete).
    private func apply(_ remote: [CKRecord]) {
        let localMembers = allMembers()
        let localActivities = allActivities()

        var memberByUID: [String: Member] = [:]
        for m in localMembers { memberByUID[m.uid] = m }
        var activityByUID: [String: Activity] = [:]
        for a in localActivities { activityByUID[a.uid] = a }

        let remoteMembers = remote.filter { $0.recordType == "Member" }
        let remoteActivities = remote.filter { $0.recordType == "Activity" }

        for r in remoteMembers {
            let uid = r.recordID.recordName
            let m: Member
            if let existing = memberByUID[uid] {
                m = existing
            } else {
                m = Member(name: "", colorHex: "#2563EB")
                m.uid = uid
                context.insert(m)
                memberByUID[uid] = m
            }
            m.name = r["name"] as? String ?? ""
            m.colorHex = r["colorHex"] as? String ?? "#2563EB"
            if let asset = r["photo"] as? CKAsset, let url = asset.fileURL {
                m.photoData = try? Data(contentsOf: url)
            } else {
                m.photoData = nil
            }
        }

        for r in remoteActivities {
            let uid = r.recordID.recordName
            let a: Activity
            if let existing = activityByUID[uid] {
                a = existing
            } else {
                a = Activity(name: "", colorHex: "#2563EB", startHour: 9, durationMinutes: 60, anchorDate: .now)
                a.uid = uid
                context.insert(a)
                activityByUID[uid] = a
            }
            a.name = r["name"] as? String ?? ""
            a.location = r["location"] as? String ?? ""
            a.notes = r["notes"] as? String ?? ""
            a.colorHex = r["colorHex"] as? String ?? "#2563EB"
            a.timeZoneID = r["timeZoneID"] as? String ?? TimeZone.current.identifier
            a.startHour = r["startHour"] as? Int ?? 9
            a.startMinute = r["startMinute"] as? Int ?? 0
            a.durationMinutes = r["durationMinutes"] as? Int ?? 60
            a.repeatKindRaw = r["repeatKindRaw"] as? String ?? RepeatKind.weekly.rawValue
            a.intervalWeeks = r["intervalWeeks"] as? Int ?? 1
            a.weekday = r["weekday"] as? Int ?? 1
            a.weekOrdinal = r["weekOrdinal"] as? Int ?? 1
            a.anchorDate = r["anchorDate"] as? Date ?? .now
            a.driveMinutes = r["driveMinutes"] as? Int ?? 0
            let skipped = r["skippedDays"] as? String ?? ""
            a.skippedDays = skipped.split(separator: ",").map(String.init)
            let memberUID = r["memberUID"] as? String ?? ""
            a.member = memberUID.isEmpty ? nil : memberByUID[memberUID]

            let json = r["rules"] as? String ?? "[]"
            let dtos = (try? JSONDecoder().decode([RuleDTO].self, from: Data(json.utf8))) ?? []
            if dtos != ruleDTOs(a) {
                let old = a.alertRules
                for rule in old { context.delete(rule) }
                for d in dtos {
                    let rule = AlertRule(offsetMinutes: d.o, message: d.m, isEnabled: d.e)
                    context.insert(rule)
                    rule.activity = a
                }
            }
        }

        let remoteActivityUIDs = Set(remoteActivities.map { $0.recordID.recordName })
        for a in localActivities where !remoteActivityUIDs.contains(a.uid) { context.delete(a) }
        let remoteMemberUIDs = Set(remoteMembers.map { $0.recordID.recordName })
        for m in localMembers where !remoteMemberUIDs.contains(m.uid) { context.delete(m) }

        try? context.save()
    }

    // MARK: - Local helpers

    private func allMembers() -> [Member] {
        (try? context.fetch(FetchDescriptor<Member>())) ?? []
    }

    private func allActivities() -> [Activity] {
        (try? context.fetch(FetchDescriptor<Activity>())) ?? []
    }

    /// Gives every object a unique, stable id (older data had none).
    private func ensureUIDs() {
        var seen = Set<String>()
        var changed = false
        for m in allMembers() {
            if m.uid.isEmpty || seen.contains(m.uid) { m.uid = UUID().uuidString; changed = true }
            seen.insert(m.uid)
        }
        for a in allActivities() {
            if a.uid.isEmpty || seen.contains(a.uid) { a.uid = UUID().uuidString; changed = true }
            seen.insert(a.uid)
        }
        if changed { try? context.save() }
    }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
