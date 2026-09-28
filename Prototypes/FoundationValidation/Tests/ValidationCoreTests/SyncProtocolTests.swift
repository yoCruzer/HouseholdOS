import XCTest
import SwiftData
import CloudKit
@testable import ValidationCore

final class SyncProtocolTests: XCTestCase {
    @MainActor func withCore(_ body: (SyncCore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        let scope = SyncScope(container: "synthetic", environment: "Development", account: "account-A", library: UUID(), zone: "HHOSVAL_fixture", epoch: UUID())
        let core = try SyncCore(context: chain.context, scope: scope)
        try core.setEnabled(true)
        try body(core, root)
    }
    func wire(_ scope: SyncScope, id: UUID = UUID(), revision: Int = 1, name: String = "Fixture") -> WireRecord {
        WireRecord(id: id, operationID: UUID(), revision: revision, library: scope.library, kind: "item", name: name)
    }
    func record(_ wire: WireRecord, scope: SyncScope) throws -> CKRecord {
        try CloudCodec.encode(wire, zone: CKRecordZone.ID(zoneName: scope.zone))
    }

    @MainActor func testOldAckCannotRemoveNewEditAfterReopen() throws {
        try withCore { core, root in
            let scope = core.session.scope
            let seven = wire(scope, revision: 7)
            try core.write(seven)
            XCTAssertTrue(try core.nextBatch().isEmpty, "No bootstrap upload before fetch/apply")
            try core.finishBootstrap(callback: scope)
            XCTAssertEqual(try core.nextBatch(), [seven])
            var eight = seven; eight.revision = 8; eight.operationID = UUID(); eight.name = "Edited"
            try core.write(eight)
            XCTAssertEqual(try core.nextBatch(), [seven], "One persisted in-flight version per record")
            let reopened = try LocalChain(root: root)
            let resumed = try SyncCore(context: reopened.context, scope: scope)
            try resumed.acknowledge(record(seven, scope: scope), callback: scope)
            try resumed.acknowledge(record(seven, scope: scope), callback: scope)
            XCTAssertEqual(try resumed.pending().map(\.revision), [8])
            XCTAssertEqual(try resumed.nextBatch(), [eight])
        }
    }

    @MainActor func testOffLateCallbacksAndOnKeepPendingIntent() throws {
        try withCore { core, _ in
            let oldScope = core.session.scope
            let value = wire(oldScope)
            try core.write(value); try core.finishBootstrap(callback: oldScope)
            _ = try core.nextBatch()
            try core.setEnabled(false)
            try core.acknowledge(record(value, scope: oldScope), callback: oldScope)
            try core.persistEngineState(Data("stale".utf8), callback: oldScope)
            XCTAssertEqual(try core.pending().count, 1)
            XCTAssertNil(core.session.engineSerialization)
            try core.setEnabled(true)
            XCTAssertTrue(try core.nextBatch().isEmpty)
            try core.finishBootstrap(callback: core.session.scope)
            XCTAssertEqual(try core.nextBatch(), [value])
        }
    }

    @MainActor func testInboundIsDurableNoEchoAndPendingEditRetainsConflict() throws {
        try withCore { core, root in
            let scope = core.session.scope
            let first = wire(scope)
            try core.apply(record(first, scope: scope), callback: scope)
            XCTAssertTrue(try core.pending().isEmpty)
            var local = first; local.operationID = UUID(); local.revision = 2; local.name = "local"
            try core.write(local)
            var remote = first; remote.operationID = UUID(); remote.revision = 2; remote.name = "remote"
            try core.apply(record(remote, scope: scope), callback: scope)
            let reopened = try LocalChain(root: root)
            let candidates = try reopened.context.fetch(FetchDescriptor<ConflictCandidate>())
            XCTAssertEqual(candidates.count, 1)
            XCTAssertEqual(try JSONDecoder().decode(WireRecord.self, from: candidates[0].local), local)
            XCTAssertEqual(try JSONDecoder().decode(WireRecord.self, from: candidates[0].remote), remote)
        }
    }

    @MainActor func testTombstoneBlocksStaleUpsertAndExplicitReAddIsNewIntent() throws {
        try withCore { core, _ in
            let scope = core.session.scope
            let old = wire(scope)
            try core.apply(record(old, scope: scope), callback: scope)
            var deletion = old; deletion.operationID = UUID(); deletion.revision = 2; deletion.deleted = true; deletion.name = nil
            try core.apply(record(deletion, scope: scope), callback: scope)
            try core.apply(record(old, scope: scope), callback: scope)
            XCTAssertEqual(try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(old.id)).payload), deletion)
            var readd = wire(scope, id: old.id, revision: 3)
            XCTAssertThrowsError(try core.write(readd))
            readd.replacesDeletion = deletion.operationID
            try core.write(readd)
            XCTAssertEqual(try core.pending().count, 1)
        }
    }

    @MainActor func testAccountSwitchDoesNotSendOldLibrary() throws {
        try withCore { core, root in
            let a = core.session.scope
            try core.write(wire(a))
            var b = a; b.account = "account-B"; b.epoch = UUID()
            let reopened = try LocalChain(root: root)
            let switched = try SyncCore(context: reopened.context, scope: b)
            XCTAssertFalse(switched.session.enabled)
            XCTAssertNotNil(switched.session.pauseReason)
            XCTAssertTrue(try switched.nextBatch().isEmpty)
            XCTAssertEqual(try reopened.context.fetchCount(FetchDescriptor<DurableIntent>()), 1)
        }
    }
}
