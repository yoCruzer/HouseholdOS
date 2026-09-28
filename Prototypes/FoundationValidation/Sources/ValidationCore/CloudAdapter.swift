import Foundation
import CloudKit
import SwiftData

@MainActor final class CloudAdapter: CKSyncEngineDelegate {
    let core: SyncCore
    let callbackScope: SyncScope
    let zone: CKRecordZone.ID
    private(set) var engine: CKSyncEngine?
    private var fetchFailed = false
    private(set) var fetchedRecordCount = 0
    private(set) var lastFailure: String?

    init(core: SyncCore) {
        self.core = core; callbackScope = core.session.scope
        zone = CKRecordZone.ID(zoneName: callbackScope.zone)
    }

    // Caller must verify actual signed Development entitlements before invoking this entry.
    func connect(authorizedDevelopmentContainer: String) throws {
        guard callbackScope.environment == "Development", callbackScope.container == authorizedDevelopmentContainer,
              callbackScope.zone.hasPrefix("HHOSVAL_") else { throw ValidationFailure.invariant("unapproved namespace") }
        let serialization = try core.session.engineSerialization.map {
            try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        var configuration = CKSyncEngine.Configuration(database: CKContainer(identifier: authorizedDevelopmentContainer).privateCloudDatabase,
                                                        stateSerialization: serialization, delegate: self)
        configuration.automaticallySync = false
        engine = CKSyncEngine(configuration)
    }

    func fetch() async throws {
        guard core.accepts(callbackScope), let engine else { throw ValidationFailure.invariant("inactive scope") }
        try await engine.fetchChanges(.init(scope: .zoneIDs([zone])))
    }
    func send() async throws {
        guard core.accepts(callbackScope), core.session.bootstrapComplete, let engine else { throw ValidationFailure.invariant("bootstrap incomplete") }
        let batch = try core.nextBatch()
        engine.state.add(pendingRecordZoneChanges: batch.map { .saveRecord(CKRecord.ID(recordName: $0.id.uuidString, zoneID: zone)) })
        try await engine.sendChanges(.init(scope: .zoneIDs([zone])))
    }
    func stop() async throws {
        try core.setEnabled(false)
        await engine?.cancelOperations()
    }
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard core.accepts(callbackScope) else { return }
        do {
            switch event {
            case .willFetchChanges:
                try beginFetch()
            case .fetchedRecordZoneChanges(let value):
                for modification in value.modifications { try core.apply(modification.record, callback: callbackScope); fetchedRecordCount += 1 }
                if !value.deletions.isEmpty { try core.pause("unexpected physical record deletion; reconcile retained tombstones") }
            case .stateUpdate(let value):
                // Delegate delivery is serial. A failed durable apply sets pause before state can advance.
                try core.persistEngineState(JSONEncoder().encode(value.stateSerialization), callback: callbackScope)
            case .didFetchRecordZoneChanges(let value):
                if let error = value.error { try recordFetchFailure(error) }
            case .didFetchChanges:
                try completeFetch()
            case .sentRecordZoneChanges(let value):
                try applySendResults(saved: value.savedRecords, errors: value.failedRecordSaves.map(\.error))
            case .accountChange(let value):
                switch value.changeType {
                case .signIn(let user) where MediaFiles.hash(Data(user.recordName.utf8)) == callbackScope.account: break
                default: try core.pause("account changed; explicit binding required")
                }
            case .fetchedDatabaseChanges(let value):
                if value.deletions.contains(where: { $0.zoneID == zone }) { try core.pause("zone removed; no automatic recreation") }
            case .sentDatabaseChanges(let value):
                for failed in value.failedZoneSaves { try classify(failed.error) }
            default: break
            }
        } catch {
            lastFailure = "durable event handling failed"
            core.session.pauseReason = lastFailure
            // Keep serialization at the previous successful checkpoint; restart must replay.
            do { try core.saveSession() } catch { lastFailure = "durable checkpoint unavailable; stopped" }
        }
    }
    // Deterministic tests call these same delegate reducers; only service delivery is replaced.
    func beginFetch() throws {
        guard core.accepts(callbackScope) else { return }
        fetchFailed = false; try core.beginFetch(callback: callbackScope)
    }
    func recordFetchFailure(_ error: CKError) throws {
        guard core.accepts(callbackScope) else { return }
        fetchFailed = true; try classify(error)
    }
    func completeFetch() throws {
        guard core.accepts(callbackScope), !fetchFailed else { return }
        try core.finishBootstrap(callback: callbackScope)
    }
    func applySendResults(saved: [CKRecord], errors: [CKError]) throws {
        guard core.accepts(callbackScope) else { return }
        for record in saved { try core.acknowledge(record, callback: callbackScope) }
        for error in errors {
            if error.code == .serverRecordChanged, let server = error.serverRecord {
                try core.apply(server, callback: callbackScope)
                if try core.context.fetch(FetchDescriptor<ConflictCandidate>()).contains(where: { $0.entityID.uuidString == server.recordID.recordName && $0.scope == callbackScope.key }) {
                    try core.pause("server conflict requires durable reconciliation")
                }
            } else { try classify(error) }
        }
    }
    func classify(_ error: CKError) throws {
        guard core.accepts(callbackScope) else { return }

        switch error.code {
        case .userDeletedZone: try core.pause("userDeletedZone")
        case .zoneNotFound: try core.pause("zoneNotFound; cause requires evidence")
        case .quotaExceeded: try core.pause("quota exceeded; uploads paused")
        case .notAuthenticated: try core.pause("account unavailable")
        case .requestRateLimited, .serviceUnavailable, .networkFailure, .networkUnavailable:
            core.session.retryAfter = Date().addingTimeInterval(max(error.retryAfterSeconds ?? 30, 1)); try core.saveSession()
            lastFailure = "platform retry-after retained; no custom timer"
        default: lastFailure = "service failure; explicit retry/reconciliation required"
        }
    }
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard core.accepts(callbackScope) else { return nil }
        do {
            let records = try core.nextBatch().compactMap { wire -> CKRecord? in
                let id = CKRecord.ID(recordName: wire.id.uuidString, zoneID: zone)
                guard context.options.scope.contains(id) else { return nil }
                return try CloudCodec.encode(wire, zone: zone, systemFields: core.document(wire.id)?.systemFields)
            }
            return records.isEmpty ? nil : .init(recordsToSave: records, atomicByZone: false)
        } catch {
            lastFailure = "batch preparation failed"; core.session.pauseReason = lastFailure
            return nil
        }
    }
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        .init(scope: .zoneIDs([zone]))
    }
}

// Originals are kept outside the engine metadata zone. This is only an explicit request entry;
// real-service evidence is required before claiming that metadata fetch is original-free.
enum OriginalAssetAdapter {
    static func recordID(_ ticket: TransferTicket) -> CKRecord.ID {
        CKRecord.ID(recordName: ticket.representationID.uuidString, zoneID: .init(zoneName: ticket.scope.zone + "_media"))
    }
    static func upload(_ ticket: TransferTicket, database: CKDatabase, durableURL: URL) async throws {
        let bytes = try Data(contentsOf: durableURL)
        guard MediaFiles.hash(bytes) == ticket.sha256, bytes.count == ticket.bytes else { throw ValidationFailure.invariant("upload representation changed") }
        let record = CKRecord(recordType: "HHOSVAL_Original", recordID: recordID(ticket))
        record["original"] = CKAsset(fileURL: durableURL)
        record["revision"] = ticket.revision as CKRecordValue
        record["sha256"] = ticket.sha256 as CKRecordValue
        record["mediaID"] = ticket.mediaID.uuidString as CKRecordValue
        do {
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            guard let saved = result.saveResults[record.recordID] else { throw ValidationFailure.invariant("missing asset result") }
            _ = try saved.get()
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let saved = error.serverRecord, saved["sha256"] as? String == ticket.sha256,
                  saved["revision"] as? Int == ticket.revision, saved["mediaID"] as? String == ticket.mediaID.uuidString else { throw error }
            // Immutable representation ID with matching descriptor resolves a lost upload ACK.
        }
    }
    static func fetch(_ ticket: TransferTicket, database: CKDatabase) async throws -> Data {
        let id = recordID(ticket)
        let results = try await database.records(for: [id], desiredKeys: ["original", "sha256", "revision", "mediaID"])
        guard let result = results[id] else { throw ValidationFailure.invariant("original unavailable") }
        let record = try result.get()
        guard record["sha256"] as? String == ticket.sha256, record["revision"] as? Int == ticket.revision,
              record["mediaID"] as? String == ticket.mediaID.uuidString,
              let asset = record["original"] as? CKAsset, let temporary = asset.fileURL else { throw ValidationFailure.invariant("original descriptor mismatch") }
        let bytes = try Data(contentsOf: temporary)
        guard MediaFiles.hash(bytes) == ticket.sha256 else { throw ValidationFailure.invariant("original integrity failure") }
        return bytes // Caller validates the still-current ticket then writes to durable storage.
    }
}
