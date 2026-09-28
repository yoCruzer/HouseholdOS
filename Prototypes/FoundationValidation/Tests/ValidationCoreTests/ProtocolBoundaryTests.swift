import XCTest
import SwiftData
import CloudKit
@testable import ValidationCore

final class ProtocolBoundaryTests: XCTestCase {
    @MainActor func fixture(_ body: (LocalChain, SyncCore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: root)
        try core.setEnabled(true)
        try body(chain, core)
    }
    func record(_ wire: WireRecord, _ core: SyncScope) throws -> CKRecord { try CloudCodec.encode(wire, zone: .init(zoneName: core.zone)) }
    func item(_ library: UUID) -> WireRecord { WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: library, kind: "item", name: "Fixture", category: "original", amount: "0.00", currency: "CNY") }

    @MainActor func testThreeWayIndependentFieldsMergeAndCoupledMoneyConflicts() throws {
        try fixture { chain, core in
            let base = item(chain.libraryID), scope = core.session.scope
            try core.apply(record(base, scope), callback: scope)
            var local = base; local.operationID = UUID(); local.revision = 2; local.name = "local name"
            try core.write(local)
            var remote = base; remote.operationID = UUID(); remote.revision = 2; remote.category = "remote category"
            try core.apply(record(remote, scope), callback: scope)
            let merged = try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(base.id)).payload)
            XCTAssertEqual(merged.name, local.name); XCTAssertEqual(merged.category, remote.category)
            XCTAssertEqual(merged.revision, 3)
            XCTAssertEqual(try core.pending().count, 1)
            var moneyLocal = base; moneyLocal.amount = "10.00"
            var moneyRemote = base; moneyRemote.currency = "USD"
            XCTAssertNil(ThreeWayMerge.merge(ancestor: base, local: moneyLocal, remote: moneyRemote), "amount/currency merge as one group")
            var invalid = base; invalid.amount = "1garbage"
            XCTAssertThrowsError(try invalid.validated())
        }
    }

    @MainActor func testFutureFieldRetainedAndWriteProtected() throws {
        try fixture { chain, core in
            let value = item(chain.libraryID), scope = core.session.scope
            let ck = try record(value, scope)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
            object["futureSensitiveField"] = ["unknown": "must survive"]
            let opaque = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            ck.encryptedValues["payload"] = opaque as CKRecordValue
            try core.apply(ck, callback: scope)
            XCTAssertEqual(try core.document(value.id)?.payload, opaque)
            var rewrite = value; rewrite.operationID = UUID(); rewrite.revision = 2
            XCTAssertThrowsError(try core.write(rewrite))
            try core.finishBootstrap(callback: scope)
            XCTAssertTrue(try core.nextBatch().isEmpty)
        }
    }

    @MainActor func testFailedInboundCannotAdvanceCheckpointOrBootstrap() throws {
        try fixture { chain, core in
            let scope = core.session.scope
            try core.persistEngineState(Data("previous".utf8), callback: scope)
            try core.beginFetch(callback: scope)
            core.failNextCommit = true
            let value = item(chain.libraryID)
            XCTAssertThrowsError(try core.apply(record(value, scope), callback: scope))
            try core.persistEngineState(Data("lost-data-window".utf8), callback: scope)
            try core.finishBootstrap(callback: scope)
            let reopened = try LocalChain(root: chain.root)
            let resumed = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
            XCTAssertEqual(resumed.session.engineSerialization, Data("previous".utf8))
            XCTAssertFalse(resumed.session.bootstrapComplete)
            XCTAssertNotNil(resumed.session.pauseReason)
            XCTAssertNil(try resumed.document(value.id))
        }
    }

    @MainActor func testParentDeletionHidesEarlyAndLateChildrenAndRejectsOldInFlightSave() throws {
        try fixture { chain, core in
            let scope = core.session.scope, parent = item(chain.libraryID)
            try core.apply(record(parent, scope), callback: scope)
            let bytes = try MediaFiles.preview(MediaFiles.syntheticJPEG())
            let child = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "media", parentID: parent.id,
                media: WireMedia(representationID: UUID(), revision: 1, hash: String(repeating: "a", count: 64), precision: "importedBytes", contentType: "public.jpeg", preview: bytes))
            try core.apply(record(child, scope), callback: scope)
            XCTAssertEqual(try chain.counts()["media"], 1)
            var pending = parent; pending.operationID = UUID(); pending.revision = 2; pending.name = "offline change"
            try core.write(pending); try core.finishBootstrap(callback: scope); _ = try core.nextBatch()
            var deleted = parent; deleted.operationID = UUID(); deleted.revision = 3; deleted.deleted = true
            deleted.name = nil; deleted.category = nil; deleted.amount = nil; deleted.currency = nil
            try core.apply(record(deleted, scope), callback: scope)
            try core.apply(record(child, scope), callback: scope)
            try core.acknowledge(record(pending, scope), callback: scope)
            XCTAssertEqual(try chain.counts()["items"], 0)
            XCTAssertEqual(try chain.counts()["media"], 0)
            XCTAssertTrue(try core.pending().isEmpty)
            XCTAssertEqual(try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(parent.id)).payload), deleted)
            XCTAssertEqual(try chain.context.fetchCount(FetchDescriptor<ConflictCandidate>()), 1, "offline content remains recoverable in explicit conflict")
        }
    }

    @MainActor func testFetchPagesRequireCompletionAndOffRejectsLateData() throws {
        try fixture { chain, core in
            let scope = core.session.scope
            let local = item(chain.libraryID); try core.write(local)
            try core.beginFetch(callback: scope)
            for _ in 0..<3 { try core.apply(record(item(chain.libraryID), scope), callback: scope) }
            XCTAssertTrue(try core.nextBatch().isEmpty)
            try core.finishBootstrap(callback: scope)
            XCTAssertEqual(try core.nextBatch().count, 1)
            try core.setEnabled(false)
            let late = item(chain.libraryID)
            try core.apply(record(late, scope), callback: scope)
            XCTAssertNil(try core.document(late.id))
        }
    }
}
