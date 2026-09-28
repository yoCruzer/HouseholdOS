import Foundation
import SwiftData
import CloudKit

struct LiveConfiguration: Codable {
    var program: String
    var containerID: String
    var environment: String
    var metadataZone: String
    var libraryID: UUID
    var role: String
    var newNamespaceAuthorized: Bool
    var bundleID: String
    var codeSHA256: [String: String]
    var signedEntitlementsVerified: Bool
    var ownerAuthorized: Bool

    func validateArtifact() throws {
        guard program == "HHOS-FAV-001", environment == "Development", ownerAuthorized, signedEntitlementsVerified,
              metadataZone.hasPrefix("HHOSVAL_"), UUID(uuidString: String(metadataZone.dropFirst(8))) != nil,
              ["source", "blankReplica"].contains(role), bundleID == "com.yocruzer.householdos.foundationvalidation",
              Bundle.main.bundleIdentifier == bundleID, let binary = Bundle.main.executableURL else {
            throw ValidationFailure.invariant("signed Development artifact/configuration not verified")
        }
        // Xcode Debug may place application code in a dylib behind a stable launcher.
        let root = Bundle.main.bundleURL
        let libraries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "dylib" }
        let binaries = [binary] + libraries
        guard Set(codeSHA256.keys) == Set(binaries.map(\.lastPathComponent)) else {
            throw ValidationFailure.invariant("signed code file set changed")
        }
        for file in binaries {
            guard try MediaFiles.hash(Data(contentsOf: file)) == codeSHA256[file.lastPathComponent] else {
                throw ValidationFailure.invariant("signed code fingerprint changed")
            }
        }
    }
}

@MainActor final class LiveValidation {
    let config: LiveConfiguration
    let chain: LocalChain
    let core: SyncCore
    let adapter: CloudAdapter
    let database: CKDatabase
    let budgetURL: URL
    private(set) var report: [String: String] = [:]

    private init(config: LiveConfiguration, chain: LocalChain, core: SyncCore, budgetURL: URL) {
        self.config = config; self.chain = chain; self.core = core; self.budgetURL = budgetURL
        database = CKContainer(identifier: config.containerID).privateCloudDatabase
        adapter = CloudAdapter(core: core)
    }
    static func start(config: LiveConfiguration, chain: LocalChain, budgetURL: URL) async throws -> LiveValidation {
        try config.validateArtifact()
        guard chain.libraryID == config.libraryID else { throw ValidationFailure.invariant("live configuration does not bind this library") }
        var budget = try LiveBudget.load(budgetURL)
        try budget.reserve(payloadBytes: 4096, at: budgetURL)
        let container = CKContainer(identifier: config.containerID)
        guard try await container.accountStatus() == .available else { throw ValidationFailure.invariant("test iCloud account unavailable") }
        let account = try await container.userRecordID()
        let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: chain.root)
        let scope = SyncScope(container: config.containerID, environment: "Development", account: MediaFiles.hash(Data(account.recordName.utf8)), library: config.libraryID, zone: config.metadataZone, epoch: core.session.scope.epoch)
        if core.session.pauseReason == "restored snapshot requires cloud admission against current tombstones" {
            try core.prepareRestoreAdmission(to: scope)
        } else if core.session.scope.account == "unbound" { try core.bindInitial(to: scope) }
        else if core.session.scope.key != scope.key {
            try core.pause("account or library changed; explicit recovery plan required")
            throw ValidationFailure.invariant("existing binding cannot be transferred to another account")
        }
        guard core.session.pauseReason == nil else { throw ValidationFailure.invariant("previous platform failure requires reconciliation") }
        try core.setEnabled(true)
        let runner = LiveValidation(config: config, chain: chain, core: core, budgetURL: budgetURL)
        try await runner.ensureRegisteredNamespace()
        try runner.adapter.connect(authorizedDevelopmentContainer: config.containerID)
        runner.report["signedDevelopmentArtifact"] = "VERIFIED"
        return runner
    }
    func reserve(_ bytes: Int) throws {
        var budget = try LiveBudget.load(budgetURL)
        // Two planned endpoints at most 50 MiB each; preserve this ledger across role/run changes.
        guard budget.estimatedBytes + bytes + 4096 <= 50 * 1024 * 1024 else { throw ValidationFailure.invariant("endpoint allocation exhausted; reconcile cumulative Program budget") }
        try budget.reserve(payloadBytes: bytes, at: budgetURL)
        report["estimatedTransferredBytes"] = String(budget.estimatedBytes)
    }
    private func ensureRegisteredNamespace() async throws {
        let key = "namespace-attempted:" + config.metadataZone
        let registered = try chain.context.fetch(FetchDescriptor<SyncCheckpoint>()).contains { $0.key == key }
        let ids = [CKRecordZone.ID(zoneName: config.metadataZone), CKRecordZone.ID(zoneName: config.metadataZone + "_media")]
        if config.newNamespaceAuthorized && !registered {
            // Register before the first service write. Ambiguous failures never auto-recreate on restart.
            chain.context.insert(SyncCheckpoint(key: key, data: Data("creation-attempted".utf8)))
            try core.commit(); try reserve(8192)
            let result = try await database.modifyRecordZones(saving: ids.map(CKRecordZone.init(zoneID:)), deleting: [])
            for id in ids {
                guard let save = result.saveResults[id] else { throw ValidationFailure.invariant("zone initialization result missing") }
                _ = try save.get()
            }
        } else {
            for id in ids { try reserve(4096); _ = try await database.recordZone(for: id) }
        }
        report["namespace"] = "REGISTERED_TEST_ZONES_ONLY"
    }
    func metadataRoundTrip() async throws {
        try reserve(4 * 1024 * 1024)
        try await adapter.fetch()
        for _ in 0..<3 {
            let batch = try core.nextBatch()
            if batch.isEmpty { break }
            try reserve(try batch.reduce(0) { try $0 + $1.encoded().count })
            try await adapter.send()
        }
        try reserve(4 * 1024 * 1024)
        try await adapter.fetch()
        report["metadataFetchApply"] = core.session.bootstrapComplete ? "COMPLETED" : "INCOMPLETE"
        report["pendingIntents"] = String(try core.pending().count)
        report["originalFetchRequests"] = report["originalFetchRequests"] ?? "0"
        report["originalUploadRequests"] = report["originalUploadRequests"] ?? "0"
        report["readablePreviews"] = String(try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).filter { asset in
            asset.thumbnailFileName.map { FileManager.default.fileExists(atPath: chain.root.appendingPathComponent("media/" + $0).path) } ?? false
        }.count)
    }
    func uploadOneOriginal() async throws {
        let transfers = try MediaTransfers(chain: chain, core: core)
        try transfers.setPolicy(.appOwnedOriginals)
        guard let asset = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first else { throw ValidationFailure.invariant("select a synthetic original first") }
        let ticket = try transfers.beginUpload(asset.id)
        let path = try transfers.current(asset.id).relativePath
        try reserve(ticket.bytes)
        do {
            try await OriginalAssetAdapter.upload(ticket, database: database, durableURL: chain.root.appendingPathComponent(path))
            let current = try transfers.acknowledge(ticket)
            report["originalUploadRequests"] = String((Int(report["originalUploadRequests"] ?? "0") ?? 0) + 1)
            report["originalUploadACK"] = current ? "CURRENT_REPRESENTATION" : "OLD_REPRESENTATION"
        } catch let error as CKError { try transfers.serviceFailed(error, callback: ticket.scope); throw error }
    }
    func fetchOneOriginal() async throws {
        let transfers = try MediaTransfers(chain: chain, core: core)
        guard let asset = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first else { throw ValidationFailure.invariant("fetch metadata first") }
        let ticket = try transfers.downloadTicket(asset.id)
        try reserve(4 * 1024 * 1024) // Conservative reservation for the small live fixture; do not select large originals.
        let bytes = try await OriginalAssetAdapter.fetch(ticket, database: database)
        guard bytes.count <= 4 * 1024 * 1024 else { throw ValidationFailure.invariant("live fixture exceeded allocation; stop and reconcile observed traffic") }
        let accepted = try transfers.receive(bytes, for: ticket)
        report["originalFetchRequests"] = String((Int(report["originalFetchRequests"] ?? "0") ?? 0) + 1)
        report["targetOriginalHash"] = accepted ? "VERIFIED" : "STALE_RESULT_REJECTED"
    }
}
