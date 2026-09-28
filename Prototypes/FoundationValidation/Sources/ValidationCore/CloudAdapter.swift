import Foundation
import CloudKit

@MainActor final class CloudAdapter: CKSyncEngineDelegate {
    let core: SyncCore
    let callbackScope: SyncScope
    let zone: CKRecordZone.ID
    private(set) var engine: CKSyncEngine?
    private var fetchFailed = false
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
            case .willFetchChanges: fetchFailed = false
            case .fetchedRecordZoneChanges(let value):
                for modification in value.modifications { try core.apply(modification.record, callback: callbackScope) }
                if !value.deletions.isEmpty { try core.pause("unexpected physical record deletion; reconcile retained tombstones") }
            case .stateUpdate(let value):
                // Delegate delivery is serial. A failed durable apply sets pause before state can advance.
                try core.persistEngineState(JSONEncoder().encode(value.stateSerialization), callback: callbackScope)
            case .didFetchRecordZoneChanges(let value):
                if let error = value.error { fetchFailed = true; try classify(error) }
            case .didFetchChanges:
                if !fetchFailed { try core.finishBootstrap(callback: callbackScope) }
            case .sentRecordZoneChanges(let value):
                for record in value.savedRecords { try core.acknowledge(record, callback: callbackScope) }
                for failed in value.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                        try core.apply(server, callback: callbackScope)
                        try core.pause("server conflict requires durable reconciliation")
                    } else { try classify(failed.error) }
                }
            case .accountChange: try core.pause("account changed; explicit binding required")
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
    private func classify(_ error: CKError) throws {
        switch error.code {
        case .userDeletedZone: try core.pause("userDeletedZone")
        case .zoneNotFound: try core.pause("zoneNotFound; cause requires evidence")
        case .quotaExceeded: try core.pause("quota exceeded; uploads paused")
        case .notAuthenticated: try core.pause("account unavailable")
        default: lastFailure = "service failure; platform retry/backoff applies"
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
    static func fetch(recordID: CKRecord.ID, database: CKDatabase, expectedHash: String, durableURL: URL) async throws {
        let results = try await database.records(for: [recordID], desiredKeys: ["original"])
        guard let result = results[recordID], let asset = try result.get()["original"] as? CKAsset,
              let temporary = asset.fileURL else { throw ValidationFailure.invariant("original unavailable") }
        let bytes = try Data(contentsOf: temporary)
        guard MediaFiles.hash(bytes) == expectedHash else { throw ValidationFailure.invariant("original integrity failure") }
        // CKAsset temporary location never becomes the persisted replica location.
        try MediaFiles.write(bytes, to: durableURL)
    }
}
