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

struct LiveObservation: Codable {
    var action: String
    var outcome: String
    var report: [String: String]
}

struct LiveEvidence: Codable {
    var observations: [LiveObservation] = []
    static func load(_ url: URL) throws -> LiveEvidence {
        guard FileManager.default.fileExists(atPath: url.path) else { return LiveEvidence() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    static func append(at url: URL, action: String, outcome: String, report: [String: String]) throws {
        var evidence = try load(url)
        let merged = (evidence.observations.last?.report ?? [:]).merging(report) { _, new in new }
        evidence.observations.append(LiveObservation(action: action, outcome: outcome, report: merged))
        try MediaFiles.write(JSONEncoder().encode(evidence), to: url)
    }
    static func reserveEndpoint(_ bytes: Int, at url: URL) throws -> Int {
        var budget = try LiveBudget.load(url)
        guard bytes >= 0, budget.estimatedBytes + bytes + 4096 <= 50 * 1024 * 1024 else {
            throw ValidationFailure.invariant("endpoint allocation exhausted; reconcile cumulative Program budget")
        }
        try budget.reserve(payloadBytes: bytes, at: url)
        return budget.estimatedBytes
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

    private init(config: LiveConfiguration, chain: LocalChain, core: SyncCore, budgetURL: URL) throws {
        self.config = config; self.chain = chain; self.core = core; self.budgetURL = budgetURL
        database = CKContainer(identifier: config.containerID).privateCloudDatabase
        adapter = CloudAdapter(core: core)
        report = try LiveEvidence.load(budgetURL.deletingLastPathComponent().appendingPathComponent("live-evidence.json")).observations.last?.report ?? [:]
        report["role"] = config.role
    }
    var evidenceURL: URL { budgetURL.deletingLastPathComponent().appendingPathComponent("live-evidence.json") }
    func observe(_ action: String, _ outcome: String) throws {
        report["estimatedTransferredBytes"] = String(try LiveBudget.load(budgetURL).estimatedBytes)
        report["bootstrapComplete"] = String(core.session.bootstrapComplete)
        report["paused"] = String(core.session.pauseReason != nil)
        report["adapterFetchedRecordsThisConnection"] = String(adapter.fetchedRecordCount)
        try LiveEvidence.append(at: evidenceURL, action: action, outcome: outcome, report: report)
    }
    func countRequest(_ key: String) {
        report[key] = String((Int(report[key] ?? "0") ?? 0) + 1)
    }
    static func start(config: LiveConfiguration, chain: LocalChain, budgetURL: URL) async throws -> LiveValidation {
        try config.validateArtifact()
        guard chain.libraryID == config.libraryID else { throw ValidationFailure.invariant("live configuration does not bind this library") }
        _ = try LiveEvidence.reserveEndpoint(4096, at: budgetURL)
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
        let runner = try LiveValidation(config: config, chain: chain, core: core, budgetURL: budgetURL)
        try await runner.ensureRegisteredNamespace()
        try runner.adapter.connect(authorizedDevelopmentContainer: config.containerID)
        runner.report["signedDevelopmentArtifact"] = "OWNER_TOOL_VERIFIED_AND_CODE_MATCHED"
        try runner.observe("connect", "COMPLETED")
        return runner
    }
    func reserve(_ bytes: Int) throws {
        // Exactly two configured endpoints; never reset this ledger on reconnect or role change.
        report["estimatedTransferredBytes"] = String(try LiveEvidence.reserveEndpoint(bytes, at: budgetURL))
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
        try observe("metadata", "STARTED")
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
        try observe("metadata", core.session.bootstrapComplete && core.session.pauseReason == nil ? "COMPLETED" : "INCOMPLETE")
    }
    func uploadOneOriginal() async throws {
        let transfers = try MediaTransfers(chain: chain, core: core)
        try transfers.setPolicy(.appOwnedOriginals)
        guard let asset = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first else { throw ValidationFailure.invariant("select a synthetic original first") }
        let ticket = try transfers.beginUpload(asset.id)
        let path = try transfers.current(asset.id).relativePath
        try reserve(ticket.bytes)
        countRequest("originalUploadRequests")
        try observe("original-upload", "STARTED")
        do {
            try await OriginalAssetAdapter.upload(ticket, database: database, durableURL: chain.root.appendingPathComponent(path))
            let current = try transfers.acknowledge(ticket)
            report["originalUploadACK"] = current ? "CURRENT_REPRESENTATION" : "OLD_REPRESENTATION"
            try observe("original-upload", "COMPLETED")
        } catch let error as CKError { try transfers.serviceFailed(error, callback: ticket.scope); throw error }
    }
    func fetchOneOriginal() async throws {
        let transfers = try MediaTransfers(chain: chain, core: core)
        guard let asset = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first else { throw ValidationFailure.invariant("fetch metadata first") }
        let ticket = try transfers.downloadTicket(asset.id)
        try reserve(4 * 1024 * 1024) // Conservative reservation for the small live fixture; do not select large originals.
        countRequest("originalFetchRequests")
        try observe("original-download", "STARTED")
        let bytes: Data
        do { bytes = try await OriginalAssetAdapter.fetch(ticket, database: database) }
        catch let error as CKError { try transfers.serviceFailed(error, callback: ticket.scope); throw error }
        guard bytes.count <= 4 * 1024 * 1024 else { throw ValidationFailure.invariant("live fixture exceeded allocation; stop and reconcile observed traffic") }
        let accepted = try transfers.receive(bytes, for: ticket)
        report["targetOriginalHash"] = accepted ? "VERIFIED" : "STALE_RESULT_REJECTED"
        try observe("original-download", accepted ? "COMPLETED" : "STALE")
    }
}
