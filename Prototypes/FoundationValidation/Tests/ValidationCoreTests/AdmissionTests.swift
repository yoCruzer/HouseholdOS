import XCTest
import CloudKit
import SwiftData
@testable import ValidationCore

final class AdmissionTests: XCTestCase {
    @MainActor func testOldBackupCannotUploadOverRemoteTombstone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try LocalChain(root: root.appendingPathComponent("source"))
        let id = try source.capture(MediaFiles.syntheticJPEG()); _ = try source.confirm(id)
        let sourceCore = try SyncCore.local(context: source.context, library: source.libraryID, root: source.root)
        var tombstone = try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(sourceCore.document(id)).payload)
        tombstone.operationID = UUID(); tombstone.revision += 1; tombstone.deleted = true
        tombstone.name = nil; tombstone.profile = nil
        let package = root.appendingPathComponent("backup")
        _ = try BackupRestore.export(source, to: package, full: true)
        let generations = root.appendingPathComponent("generations")
        _ = try BackupRestore.restore(package, into: generations)
        let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
        let core = try SyncCore.local(context: restored.context, library: restored.libraryID, root: restored.root)
        let scope = SyncScope(container: "approved-fixture", environment: "Development", account: "fixture-A", library: restored.libraryID, zone: "HHOSVAL_fixture", epoch: UUID())
        XCTAssertThrowsError(try core.bindInitial(to: scope), "ordinary bind must not bypass restore admission")
        try core.prepareRestoreAdmission(to: scope)
        XCTAssertTrue(try core.nextBatch().isEmpty)
        try core.apply(CloudCodec.encode(tombstone, zone: .init(zoneName: scope.zone)), callback: scope)
        try core.finishBootstrap(callback: scope)
        XCTAssertTrue(try core.nextBatch().isEmpty, "deleted parent and old media must not upload")
        XCTAssertEqual(try restored.counts()["items"], 0)
        XCTAssertEqual(try restored.counts()["media"], 0)
        XCTAssertEqual(try source.counts()["items"], 1)
    }

    @MainActor func testReAddCannotRevivePriorIncarnationChildren() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        let id = try chain.capture(MediaFiles.syntheticJPEG()); _ = try chain.confirm(id)
        let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: root)
        try core.setEnabled(true); try core.finishBootstrap(callback: core.session.scope)
        var deleted = try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(id)).payload)
        deleted.operationID = UUID(); deleted.revision += 1; deleted.name = nil; deleted.profile = nil; deleted.deleted = true
        try core.apply(CloudCodec.encode(deleted, zone: .init(zoneName: core.session.scope.zone)), callback: core.session.scope)
        var readd = deleted; readd.operationID = UUID(); readd.revision += 1; readd.deleted = false; readd.name = "Explicit new holding"
        readd.replacesDeletion = deleted.operationID
        XCTAssertThrowsError(try core.write(readd))
        readd.incarnation = UUID()
        try core.write(readd); try core.projectVisibleRecord(id); try core.commit()
        XCTAssertEqual(try chain.counts()["items"], 1)
        XCTAssertEqual(try chain.counts()["media"], 0)
        let scheduled = try core.nextBatch()
        XCTAssertFalse(scheduled.contains { $0.kind == "media" })
        XCTAssertTrue(scheduled.contains { $0.id == id && $0.incarnation == readd.incarnation })
    }

    @MainActor func testAccountABARequiresBindingAndRejectsOldEpoch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        let a = SyncScope(container: "fixture", environment: "Development", account: "A", library: chain.libraryID, zone: "HHOSVAL_fixture", epoch: UUID())
        let first = try SyncCore(context: chain.context, scope: a); try first.setEnabled(true)
        var b = a; b.account = "B"; b.epoch = UUID()
        let second = try SyncCore(context: chain.context, scope: b)
        XCTAssertNotNil(second.session.pauseReason)
        XCTAssertFalse(first.accepts(a), "live old adapter consults durable account epoch")
        var returned = a; returned.epoch = UUID()
        let third = try SyncCore(context: chain.context, scope: returned)
        XCTAssertFalse(third.accepts(a)); XCTAssertFalse(third.session.enabled)
        XCTAssertNil(third.session.engineSerialization)
        XCTAssertTrue(try third.nextBatch().isEmpty)
    }
}
