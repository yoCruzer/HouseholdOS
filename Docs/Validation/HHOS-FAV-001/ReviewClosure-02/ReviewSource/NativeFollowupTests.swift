// Proposed native regressions for the existing ValidationCoreTests target.
// NOT RUN or native-compiled in this review environment (Linux has no SwiftData/CloudKit).
// The owner-facing report does not count these as executed tests.
import XCTest
import SwiftData
import CloudKit
@testable import ValidationCore

final class IndependentReviewRound2Tests: XCTestCase {
    @MainActor private func enabled(_ chain: LocalChain) throws -> SyncCore {
        let c = try SyncCore.local(context: chain.context, library: chain.libraryID, root: chain.root)
        try c.setEnabled(true)
        try c.finishBootstrap(callback: c.session.scope)
        return c
    }
    private func record(_ wire: WireRecord, _ scope: SyncScope) throws -> CKRecord {
        try CloudCodec.encode(wire, zone: .init(zoneName: scope.zone))
    }

    @MainActor func testRestoreReAddFetchMustRestoreConditionalWriteBase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root.appendingPathComponent("source"))
        let c = try enabled(chain)
        let deletion = WireRecord(id: UUID(), operationID: UUID(), revision: 2,
            library: chain.libraryID, kind: "item", deleted: true)
        try c.apply(record(deletion, c.session.scope), callback: c.session.scope)
        var readd = deletion
        readd.operationID = UUID(); readd.revision = 3; readd.deleted = false
        readd.name = "Explicit re-add"; readd.incarnation = UUID()
        readd.replacesDeletion = deletion.operationID
        try c.write(readd)
        let package = root.appendingPathComponent("package")
        let generations = root.appendingPathComponent("generations")
        _ = try BackupRestore.export(chain, to: package, full: true)
        _ = try BackupRestore.restore(package, into: generations)
        let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
        let resumed = try SyncCore.local(context: restored.context, library: restored.libraryID, root: restored.root)
        let scope = SyncScope(container: "fixture", environment: "Development", account: "fixture-A",
            library: restored.libraryID, zone: "HHOSVAL_fixture", epoch: UUID())
        try resumed.prepareRestoreAdmission(to: scope)
        let before = try XCTUnwrap(resumed.document(readd.id))
        XCTAssertNil(before.systemFields)
        let serverDeletion = try record(deletion, scope)
        try resumed.apply(serverDeletion, callback: scope)
        let current = try XCTUnwrap(resumed.document(readd.id))
        XCTAssertEqual(try JSONDecoder().decode(WireRecord.self, from: current.payload), readd)
        // This local assertion tests acquisition of the server-record envelope. It does
        // NOT manufacture a real service change tag. Add a faithful conditional-write
        // fake for deterministic send success, and later keep live-service evidence separate.
        XCTAssertNotNil(current.systemFields)
        if let systemFields = current.systemFields {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: systemFields)
            decoder.requiresSecureCoding = true
            let retained = CKRecord(coder: decoder)
            decoder.finishDecoding()
            XCTAssertEqual(retained?.recordID, serverDeletion.recordID)
        }
        try resumed.finishBootstrap(callback: scope)
        XCTAssertEqual(try resumed.nextBatch(), [readd])
    }

    @MainActor func testFetchOfOwnSentVersionCannotConflictWithItsLocalContinuation() throws {
        for hasAncestor in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let chain = try LocalChain(root: root)
            let c = try enabled(chain), scope = c.session.scope
            let six = WireRecord(id: UUID(), operationID: UUID(), revision: 6,
                library: chain.libraryID, kind: "item", name: "six")
            if hasAncestor { try c.apply(record(six, scope), callback: scope) }
            var seven = six; seven.operationID = UUID(); seven.revision = 7; seven.name = "seven"
            try c.write(seven)
            XCTAssertEqual(try c.nextBatch(), [seven])
            var eight = seven; eight.operationID = UUID(); eight.revision = 8; eight.name = "eight"
            try c.write(eight)
            // Server saved seven; success ACK did not arrive. Fetch returns that exact operation.
            try c.apply(record(seven, scope), callback: scope)
            let row = try XCTUnwrap(c.document(eight.id))
            XCTAssertEqual(try JSONDecoder().decode(WireRecord.self, from: row.payload), eight)
            let conflicts = try chain.context.fetch(FetchDescriptor<ConflictCandidate>())
            XCTAssertTrue(try conflicts.filter { try $0.scope == scope.key && !$0.isResolved(in: chain.context) }.isEmpty)
            XCTAssertEqual(try c.pending().map(\.operationID), [eight.operationID])
            XCTAssertEqual(try c.nextBatch(), [eight])
            let reopened = try LocalChain(root: root)
            let resumed = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
            XCTAssertEqual(try resumed.nextBatch(), [eight])
        }
    }

    @MainActor func testSupersededChildIntentMustNotRemainActivePendingAfterCurrentACKs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        let c = try enabled(chain), scope = c.session.scope
        let parent = WireRecord(id: UUID(), operationID: UUID(), revision: 1,
            library: chain.libraryID, kind: "item", name: "old holding")
        try c.apply(record(parent, scope), callback: scope)
        let oldChild = WireRecord(id: UUID(), operationID: UUID(), revision: 1,
            library: chain.libraryID, kind: "usage", parentID: parent.id)
        try c.write(oldChild) // Deliberately never sent: a late ACK cannot retire it.
        var deletion = parent
        deletion.operationID = UUID(); deletion.revision = 2; deletion.deleted = true; deletion.name = nil
        try c.apply(record(deletion, scope), callback: scope)
        var readd = parent
        readd.operationID = UUID(); readd.revision = 3; readd.incarnation = UUID()
        readd.replacesDeletion = deletion.operationID
        try c.write(readd)
        var newChild = oldChild
        newChild.operationID = UUID(); newChild.revision = 2; newChild.parentIncarnation = readd.incarnation
        try c.write(newChild)
        let batch = try c.nextBatch()
        XCTAssertEqual(Set(batch.map(\.operationID)), Set([readd.operationID, newChild.operationID]))
        for wire in batch { try c.acknowledge(record(wire, scope), callback: scope) }
        XCTAssertTrue(try c.nextBatch().isEmpty)
        // A dedicated superseded/quarantined history is acceptable. What must not
        // remain is an active pending item that no sender or resolver can discharge.
        XCTAssertTrue(try c.pending().isEmpty)
        let reopened = try LocalChain(root: root)
        let resumed = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
        XCTAssertTrue(try resumed.pending().isEmpty)
    }
}
