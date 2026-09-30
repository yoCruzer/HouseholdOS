import XCTest
import SwiftData
import CloudKit
@testable import ValidationCore

final class ReviewRegressionTests: XCTestCase {
    @MainActor func fixture(_ body: (LocalChain, SyncCore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root.appendingPathComponent("source"))
        let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: chain.root)
        try core.setEnabled(true); try core.finishBootstrap(callback: core.session.scope)
        try body(chain, core, root)
    }
    @MainActor func testEditedDraftConfirmationUsesNextRevisionAndFailedStagingCannotLeakIntoLaterSave() throws {
        try fixture { chain, core, _ in
            let id = try chain.capture(MediaFiles.syntheticJPEG())
            var edited = try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(id)).payload)
            edited.operationID = UUID(); edited.revision += 1; edited.name = "edited draft"
            try core.write(edited)
            XCTAssertEqual(try chain.confirm(id), id)
            let confirmed = try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(id)).payload)
            XCTAssertEqual(confirmed.revision, 3); XCTAssertEqual(confirmed.kind, "item")
            let blocked = try chain.capture(MediaFiles.syntheticJPEG(seed: 8))
            let document = try XCTUnwrap(core.document(blocked))
            var future = try XCTUnwrap(JSONSerialization.jsonObject(with: document.payload) as? [String: Any])
            future["futureField"] = "preserve"
            document.payload = try JSONSerialization.data(withJSONObject: future)
            try core.commit()
            let before = try chain.counts()
            XCTAssertThrowsError(try chain.confirm(blocked))
            XCTAssertFalse(chain.context.hasChanges)
            try core.saveSession() // Must not accidentally commit a failed business transaction.
            let reopened = try LocalChain(root: chain.root)
            XCTAssertEqual(try reopened.counts(), before)
            XCTAssertEqual(try reopened.context.fetch(FetchDescriptor<MediaAssetRecord>()).first { $0.ownerID == blocked }?.ownerKind, .draft)
        }
    }
    @MainActor func testRestoreRejectsSelfConsistentManifestOmittingLegacyOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy"), candidate = root.appendingPathComponent("candidate")
        _ = try LegacyFixture.generate(at: legacy)
        try LegacyFixture.migrateClone(from: legacy, to: candidate)
        let chain = try LocalChain(root: candidate)
        let package = root.appendingPathComponent("package")
        var manifest = try BackupRestore.export(chain, to: package, full: true)
        let generations = root.appendingPathComponent("generations")
        _ = try BackupRestore.restore(package, into: generations)
        let active = try BackupRestore.activeGeneration(in: generations)
        let omitted = try XCTUnwrap(manifest.files.first { $0.path.hasSuffix(".bin") })
        manifest.files.removeAll { $0.path == omitted.path }
        try FileManager.default.removeItem(at: package.appendingPathComponent(omitted.path))
        let bytes = try JSONEncoder().encode(manifest)
        try bytes.write(to: package.appendingPathComponent("manifest.json"))
        try Data(MediaFiles.hash(bytes).utf8).write(to: package.appendingPathComponent("COMPLETE"))
        _ = try BackupRestore.validate(package) // Checksums alone cannot authenticate logical completeness.
        XCTAssertThrowsError(try BackupRestore.restore(package, into: generations))
        XCTAssertEqual(try BackupRestore.activeGeneration(in: generations), active)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent(omitted.path).path))
    }
    @MainActor func testInboundReAddRequiresNewIncarnationBeforeChildrenCanReappear() throws {
        try fixture { chain, core, _ in
            let id = try chain.capture(MediaFiles.syntheticJPEG()); _ = try chain.confirm(id)
            var deleted = try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(id)).payload)
            deleted.operationID = UUID(); deleted.revision += 1; deleted.deleted = true
            deleted.name = nil; deleted.profile = nil
            try core.apply(CloudCodec.encode(deleted, zone: .init(zoneName: core.session.scope.zone)), callback: core.session.scope)
            var invalid = deleted; invalid.operationID = UUID(); invalid.revision += 1
            invalid.deleted = false; invalid.name = "bad re-add"; invalid.replacesDeletion = deleted.operationID
            XCTAssertThrowsError(try core.apply(CloudCodec.encode(invalid, zone: .init(zoneName: core.session.scope.zone)), callback: core.session.scope))
            XCTAssertEqual(try chain.counts()["items"], 0); XCTAssertEqual(try chain.counts()["media"], 0)
            XCTAssertTrue(try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(id)).payload).deleted)
        }
    }
    @MainActor func testLocalTombstoneServerConflictRetainedAndStopsRepeatedStaleConditionalSend() throws {
        try fixture { chain, core, _ in
            let base = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "base")
            let zone = CKRecordZone.ID(zoneName: core.session.scope.zone)
            try core.apply(CloudCodec.encode(base, zone: zone), callback: core.session.scope)
            var deleted = base; deleted.operationID = UUID(); deleted.revision = 2; deleted.deleted = true; deleted.name = nil
            try core.write(deleted); _ = try core.nextBatch()
            var remote = base; remote.operationID = UUID(); remote.revision = 2; remote.name = "concurrent server edit"
            try core.apply(CloudCodec.encode(remote, zone: zone), callback: core.session.scope)
            XCTAssertEqual(try chain.context.fetchCount(FetchDescriptor<ConflictCandidate>()), 1)
            XCTAssertTrue(try core.nextBatch().isEmpty)
            XCTAssertEqual(try chain.counts()["items"], 0)
            XCTAssertEqual(try core.pending().count, 1, "Unacknowledged deletion remains durable")
        }
    }
}
