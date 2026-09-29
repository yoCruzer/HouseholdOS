// Initial three regressions adapted from ReviewClosure-02/ReviewSource/NativeFollowupTests.swift.
// The additional sequences exercise the native shared sender/reducers with a conditional service.
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

// The fixture token is deliberately outside CKRecord's private changeTag. Native
// archives still round-trip through the real CloudCodec and adapter request path.
private struct FixtureVersion: Codable {
    var native: Data
    var token: String
}
@MainActor private final class ConditionalService {
    let scope: SyncScope
    var rows: [UUID: CKRecord] = [:]
    var accepted = 0
    init(_ scope: SyncScope) { self.scope = scope }
    func configure(_ core: SyncCore) {
        core.archiveServerRecord = { record in
            guard let token = record["fixtureVersion"] as? String else { return CloudCodec.systemFields(record) }
            return try! JSONEncoder().encode(FixtureVersion(native: CloudCodec.systemFields(record), token: token))
        }
        core.nativeSystemFields = { try JSONDecoder().decode(FixtureVersion.self, from: $0).native }
    }
    func seed(_ wire: WireRecord) throws -> CKRecord {
        let record = try CloudCodec.encode(wire, zone: .init(zoneName: scope.zone))
        record["fixtureVersion"] = UUID().uuidString as CKRecordValue
        rows[wire.id] = record
        return record
    }
    func save(_ request: CloudAdapter.PreparedRequest) throws -> CKRecord {
        let wire = try CloudCodec.decode(request.record, scope: scope)
        let expected = rows[wire.id]?["fixtureVersion"] as? String
        let supplied = try request.persistedVersion.map { try JSONDecoder().decode(FixtureVersion.self, from: $0).token }
        guard expected == supplied else { throw CKError(.serverRecordChanged) }
        accepted += 1
        return try seed(wire)
    }
}

extension IndependentReviewRound2Tests {
    @MainActor private func current(_ id: UUID, _ c: SyncCore) throws -> WireRecord {
        try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(c.document(id)).payload)
    }
    @MainActor private func assertComplete(_ c: SyncCore, _ expected: WireRecord, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try current(expected.id, c), expected, file: file, line: line)
        XCTAssertTrue(try c.pending().isEmpty, file: file, line: line)
        XCTAssertTrue(try c.nextBatch().isEmpty, file: file, line: line)
        XCTAssertTrue(try c.context.fetch(FetchDescriptor<ConflictCandidate>()).filter { try !$0.isResolved(in: c.context) }.isEmpty, file: file, line: line)
    }
    @MainActor func testXS01RestoredReAddCompletesConditionalSaveAndRejectsWrongBase() throws {
        for lostACK in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let chain = try LocalChain(root: root.appendingPathComponent("source")), c = try enabled(chain)
            let d = WireRecord(id: UUID(), operationID: UUID(), revision: 2, library: chain.libraryID, kind: "item", deleted: true)
            try c.apply(record(d, c.session.scope), callback: c.session.scope)
            var r = d; r.operationID = UUID(); r.revision = 3; r.deleted = false; r.name = "new"; r.incarnation = UUID(); r.replacesDeletion = d.operationID
            try c.write(r)
            let package = root.appendingPathComponent("backup"), generations = root.appendingPathComponent("generations")
            _ = try BackupRestore.export(chain, to: package, full: true); _ = try BackupRestore.restore(package, into: generations)
            let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
            let resumed = try SyncCore.local(context: restored.context, library: restored.libraryID, root: restored.root)
            var scope = c.session.scope; scope.epoch = UUID()
            try resumed.prepareRestoreAdmission(to: scope)
            let server = ConditionalService(scope); server.configure(resumed)
            let deletion = try server.seed(d)
            XCTAssertNil(try resumed.document(r.id)?.systemFields)
            try resumed.apply(deletion, callback: scope); try resumed.finishBootstrap(callback: scope)
            let adapter = CloudAdapter(core: resumed)
            XCTAssertEqual(try adapter.prepareBatch(), [r])
            let request = try adapter.prepareRequest(r)
            XCTAssertThrowsError(try server.save(.init(record: request.record, persistedVersion: nil)))
            XCTAssertEqual(server.accepted, 0)
            let saved = try server.save(request)
            if lostACK { try resumed.apply(saved, callback: scope) }
            else { try adapter.applySendResults(saved: [saved], errors: []) }
            let base = try resumed.document(r.id)?.systemFields
            try resumed.apply(deletion, callback: scope)
            XCTAssertEqual(try resumed.document(r.id)?.systemFields, base)
            try assertComplete(resumed, r)
            let reopen = try LocalChain(root: restored.root)
            let final = try SyncCore.local(context: reopen.context, library: reopen.libraryID, root: reopen.root)
            try assertComplete(final, r)
            XCTAssertEqual(try CloudCodec.decode(XCTUnwrap(server.rows[r.id]), scope: scope), r)
        }
    }
    @MainActor func testXS02And05SelfEchoContinuationCompletesAcrossRestoreAndReopen() throws {
        for restore in [false, true] { for ancestorKind in ["none", "live", "deleted"] {
            let ancestor = ancestorKind != "none", deleted = ancestorKind == "deleted"
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let chain = try LocalChain(root: root.appendingPathComponent("source")), c = try enabled(chain)
            let scope = c.session.scope, server = ConditionalService(c.session.scope); server.configure(c)
            let six = WireRecord(id: UUID(), operationID: UUID(), revision: 6, library: chain.libraryID, kind: "item", name: deleted ? nil : "six", deleted: deleted)
            if ancestor { try c.apply(server.seed(six), callback: scope) }
            var seven = six; seven.operationID = UUID(); seven.revision = 7; seven.name = "seven"; seven.deleted = false
            if deleted { seven.incarnation = UUID(); seven.replacesDeletion = six.operationID }
            try c.write(seven)
            let adapter = CloudAdapter(core: c); XCTAssertEqual(try adapter.prepareBatch(), [seven])
            var eight = seven; eight.operationID = UUID(); eight.revision = 8; eight.name = "eight"; try c.write(eight)
            let saved7 = try server.save(adapter.prepareRequest(seven))
            var active = chain, resumed = c
            if restore {
                let package = root.appendingPathComponent("backup"), generations = root.appendingPathComponent("generations")
                _ = try BackupRestore.export(chain, to: package, full: true); _ = try BackupRestore.restore(package, into: generations)
                active = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
                resumed = try SyncCore.local(context: active.context, library: active.libraryID, root: active.root)
                var newScope = scope; newScope.epoch = UUID(); try resumed.prepareRestoreAdmission(to: newScope)
            }
            server.configure(resumed)
            try resumed.apply(saved7, callback: resumed.session.scope)
            XCTAssertEqual(try current(eight.id, resumed), eight)
            XCTAssertEqual(try resumed.pending().map(\.operationID), [eight.operationID])
            try resumed.finishBootstrap(callback: resumed.session.scope)
            // Reconstruct the disk container between self-echo and the continuation.
            let reopened = try LocalChain(root: active.root)
            let final = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root); server.configure(final)
            let sender = CloudAdapter(core: final)
            XCTAssertEqual(try sender.prepareBatch(), [eight])
            let saved8 = try server.save(sender.prepareRequest(eight))
            try sender.applySendResults(saved: [saved8], errors: [])
            let version = try final.document(eight.id)?.systemFields
            try final.apply(saved7, callback: final.session.scope); try final.acknowledge(saved7, callback: final.session.scope)
            XCTAssertEqual(try final.document(eight.id)?.systemFields, version)
            try assertComplete(final, eight)
            XCTAssertEqual(try CloudCodec.decode(XCTUnwrap(server.rows[eight.id]), scope: scope), eight)
            let terminal = try LocalChain(root: active.root)
            try assertComplete(SyncCore.local(context: terminal.context, library: terminal.libraryID, root: terminal.root), eight)
        } }
    }
    @MainActor func testXS03RealConflictAndForgedSelfEchoRemainBlocked() throws {
        for forged in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let chain = try LocalChain(root: root), c = try enabled(chain), scope = c.session.scope
            let initial = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "base")
            try c.apply(record(initial, scope), callback: scope)
            var local = initial; local.operationID = UUID(); local.revision = 2; local.name = "local"; try c.write(local); _ = try c.nextBatch()
            var remote = local; if !forged { remote.operationID = UUID() }; remote.name = "different"
            try c.apply(record(remote, scope), callback: scope)
            XCTAssertEqual(try current(local.id, c), local)
            XCTAssertEqual(try c.pending().count, 1); XCTAssertTrue(try c.nextBatch().isEmpty)
            XCTAssertEqual(try chain.context.fetchCount(FetchDescriptor<ConflictCandidate>()), 1)
            let reopened = try LocalChain(root: root), resumed = try enabled(reopened)
            XCTAssertEqual(try resumed.pending().count, 1); XCTAssertTrue(try resumed.nextBatch().isEmpty)
        }
    }
}

extension IndependentReviewRound2Tests {
    @MainActor func testXS04SupersededInflightChildRetriesConditionAndHistorySurvivesRestore() throws {
        for inflight in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let chain = try LocalChain(root: root.appendingPathComponent("source")), c = try enabled(chain)
            let scope = c.session.scope, server = ConditionalService(c.session.scope); server.configure(c)
            let p = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "parent")
            try c.apply(server.seed(p), callback: scope)
            let child = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "usage", parentID: p.id)
            try c.write(child)
            let adapter = CloudAdapter(core: c)
            var savedChild: CKRecord?
            if inflight {
                XCTAssertEqual(try adapter.prepareBatch(), [child])
                savedChild = try server.save(adapter.prepareRequest(child)) // Server saved; ACK is delayed.
            }
            var d = p; d.operationID = UUID(); d.revision = 2; d.name = nil; d.deleted = true
            try c.apply(server.seed(d), callback: scope)
            var r = p; r.operationID = UUID(); r.revision = 3; r.incarnation = UUID(); r.replacesDeletion = d.operationID
            try c.write(r)
            var next = child; next.operationID = UUID(); next.revision = 2; next.parentIncarnation = r.incarnation
            c.failNextCommit = true; XCTAssertThrowsError(try c.write(next))
            XCTAssertEqual(try current(child.id, c), child)
            XCTAssertTrue(try c.pending().contains { $0.operationID == child.operationID })
            try c.write(next)
            XCTAssertEqual(try c.operationReceipt(child.operationID)?.supersededBy, next.operationID)
            XCTAssertFalse(try c.pending().contains { $0.operationID == child.operationID })
            let before = try c.document(child.id)?.systemFields
            if let savedChild {
                try c.acknowledge(savedChild, callback: scope); try c.apply(savedChild, callback: scope)
                XCTAssertEqual(try c.document(child.id)?.systemFields, before)
            }
            let batch = try adapter.prepareBatch()
            XCTAssertEqual(Set(batch.map(\.operationID)), Set([r.operationID, next.operationID]))
            let savedParent = try server.save(adapter.prepareRequest(r)); try adapter.applySendResults(saved: [savedParent], errors: [])
            if inflight {
                let request = try adapter.prepareRequest(next)
                XCTAssertThrowsError(try server.save(request))
                let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: try XCTUnwrap(savedChild), CKRecordChangedErrorClientRecordKey: request.record])
                try adapter.applySendResults(saved: [], errors: [error])
            }
            let savedNext = try server.save(adapter.prepareRequest(next)); try adapter.applySendResults(saved: [savedNext], errors: [])
            try assertComplete(c, next)
            let base = try c.document(child.id)?.systemFields
            if let savedChild { try c.apply(savedChild, callback: scope); try c.acknowledge(savedChild, callback: scope) }
            XCTAssertEqual(try c.document(child.id)?.systemFields, base)
            let package = root.appendingPathComponent("backup"), generations = root.appendingPathComponent("generations")
            _ = try BackupRestore.export(chain, to: package, full: true); _ = try BackupRestore.restore(package, into: generations)
            let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
            let resumed = try SyncCore.local(context: restored.context, library: restored.libraryID, root: restored.root)
            var rebound = scope; rebound.epoch = UUID(); try resumed.prepareRestoreAdmission(to: rebound); server.configure(resumed)
            try resumed.apply(savedParent, callback: rebound); try resumed.apply(savedNext, callback: rebound)
            try resumed.finishBootstrap(callback: rebound)
            try assertComplete(resumed, next)
            XCTAssertEqual(try resumed.operationReceipt(child.operationID)?.supersededBy, next.operationID)
        }
    }
}

extension IndependentReviewRound2Tests {
    @MainActor func testXS06OldEpochCallbacksCannotConfirmOrChangeCurrentBase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root), c = try enabled(chain), old = c.session.scope
        let server = ConditionalService(old); server.configure(c)
        let seven = WireRecord(id: UUID(), operationID: UUID(), revision: 7, library: chain.libraryID, kind: "item", name: "seven")
        try c.write(seven); let adapter = CloudAdapter(core: c); _ = try adapter.prepareBatch()
        let saved = try server.save(adapter.prepareRequest(seven))
        var eight = seven; eight.operationID = UUID(); eight.revision = 8; eight.name = "eight"; try c.write(eight)
        try c.setEnabled(false)
        try c.apply(saved, callback: old); try c.acknowledge(saved, callback: old)
        try c.persistEngineState(Data("stale".utf8), callback: old)
        try adapter.classify(CKError(.quotaExceeded))
        XCTAssertNil(try c.document(seven.id)?.systemFields); XCTAssertEqual(try c.pending().count, 2)
        XCTAssertNil(c.session.pauseReason); XCTAssertNil(c.session.engineSerialization)
        try c.setEnabled(true)
        XCTAssertTrue(try c.nextBatch().isEmpty)
        try c.apply(saved, callback: c.session.scope); try c.finishBootstrap(callback: c.session.scope)
        let sender = CloudAdapter(core: c); XCTAssertEqual(try sender.prepareBatch(), [eight])
        try sender.applySendResults(saved: [server.save(sender.prepareRequest(eight))], errors: [])
        let version = try c.document(eight.id)?.systemFields
        try c.apply(saved, callback: old); try c.acknowledge(saved, callback: old)
        XCTAssertEqual(try c.document(eight.id)?.systemFields, version)
        try assertComplete(c, eight)
        let reopened = try LocalChain(root: root)
        try assertComplete(SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root), eight)
    }
    @MainActor func testXS08MixedAckEchoAndSupersessionDrainWithUnknownParentControl() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root), c = try enabled(chain), scope = c.session.scope
        let server = ConditionalService(scope); server.configure(c)
        var expected: [UUID: WireRecord] = [:]
        for i in 0..<101 {
            let wire = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "fixture-\(i)")
            try c.stageWrite(wire); expected[wire.id] = wire
        }
        try c.commit()
        let parentID = UUID()
        let waiting = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "usage", parentID: parentID)
        try c.write(waiting)
        let p = WireRecord(id: UUID(), operationID: UUID(), revision: 2, library: chain.libraryID, kind: "item", name: "new generation", incarnation: UUID())
        try c.apply(server.seed(p), callback: scope)
        let old = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "usage", parentID: p.id)
        try c.write(old)
        var next = old; next.operationID = UUID(); next.revision = 2; next.parentIncarnation = p.incarnation; try c.write(next); expected[next.id] = next
        let sender = CloudAdapter(core: c)
        let first = try sender.prepareBatch(); XCTAssertEqual(first.count, 100)
        XCTAssertEqual(try sender.prepareBatch(), first)
        for _ in 0..<3 {
            let batch = try sender.prepareBatch(); XCTAssertLessThanOrEqual(batch.count, 100)
            for (index, wire) in batch.enumerated() {
                let saved = try server.save(sender.prepareRequest(wire))
                if index.isMultiple(of: 2) { try c.apply(saved, callback: scope) }
                else { try sender.applySendResults(saved: [saved], errors: []) }
            }
        }
        XCTAssertEqual(try c.pending().map(\.operationID), [waiting.operationID])
        XCTAssertTrue(try c.nextBatch().isEmpty)
        XCTAssertNil(try c.operationReceipt(waiting.operationID))
        for (id, wire) in expected { XCTAssertEqual(try CloudCodec.decode(XCTUnwrap(server.rows[id]), scope: scope), wire) }
        let parent = WireRecord(id: parentID, operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "arrived")
        try c.apply(server.seed(parent), callback: scope)
        XCTAssertEqual(try sender.prepareBatch(), [waiting])
        try sender.applySendResults(saved: [server.save(sender.prepareRequest(waiting))], errors: [])
        try assertComplete(c, waiting)
        let reopened = try LocalChain(root: root), resumed = try enabled(reopened)
        try assertComplete(resumed, waiting)
        XCTAssertEqual(try resumed.operationReceipt(old.operationID)?.supersededBy, next.operationID)
        XCTAssertEqual(server.accepted, 103)
    }
}

extension IndependentReviewRound2Tests {
    @MainActor func testNativeSenderRehydratesPersistedSystemFieldsAndRejectsWrongIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root), c = try enabled(chain), scope = c.session.scope
        let base = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "base")
        try c.apply(record(base, scope), callback: scope)
        var next = base; next.operationID = UUID(); next.revision = 2; next.name = "next"; try c.write(next)
        let reopened = try LocalChain(root: root), resumed = try enabled(reopened), sender = CloudAdapter(core: resumed)
        XCTAssertEqual(try sender.prepareBatch(), [next])
        let request = try sender.prepareRequest(next)
        XCTAssertEqual(request.persistedVersion, try resumed.document(base.id)?.systemFields)
        XCTAssertEqual(try CloudCodec.decode(request.record, scope: scope), next)
        let wrong = CKRecord(recordType: "HHOSVAL_Entity", recordID: .init(recordName: UUID().uuidString, zoneID: .init(zoneName: scope.zone)))
        try XCTUnwrap(resumed.document(base.id)).systemFields = CloudCodec.systemFields(wrong)
        try resumed.commit()
        XCTAssertThrowsError(try sender.prepareRequest(next))
        XCTAssertEqual(try resumed.pending().map(\.operationID), [next.operationID])
    }
}
