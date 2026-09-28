import XCTest
import SwiftData
import CloudKit
@testable import ValidationCore

// This fake implements only service conditional delivery and failure timing. Application
// encoding, persistence, projection, outbox and ACK handling are the real shared implementation.
@MainActor final class DeterministicService {
    var records: [UUID: CKRecord] = [:]
    func save(_ record: CKRecord, scope: SyncScope, expectedOperation: UUID?, loseACK: Bool = false) throws -> CKRecord {
        let wire = try CloudCodec.decode(record, scope: scope)
        if let old = records[wire.id] {
            let prior = try CloudCodec.decode(old, scope: scope)
            if prior.operationID == wire.operationID { return old }
            guard prior.operationID == expectedOperation else {
                throw CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: old])
            }
        } else if expectedOperation != nil { throw CKError(.unknownItem) }
        records[wire.id] = record
        if loseACK { throw CKError(.networkFailure) }
        return record
    }
}

final class SharedChainTests: XCTestCase {
    @MainActor func testSharedCaptureReopenConfirmReplicatesPreviewToBlankClient() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let first = try LocalChain(root: base.appendingPathComponent("source"))
        let draft = try first.capture(MediaFiles.syntheticJPEG())
        let source = try LocalChain(root: first.root)
        try source.recover(); _ = try source.confirm(draft)
        let sender = try SyncCore.local(context: source.context, library: source.libraryID, root: source.root)
        try sender.setEnabled(true); try sender.finishBootstrap(callback: sender.session.scope)
        let blank = try LocalChain(root: base.appendingPathComponent("blank"), libraryID: source.libraryID)
        let receiver = try SyncCore(context: blank.context, scope: sender.session.scope, mediaRoot: blank.root)
        try receiver.setEnabled(true)
        let service = DeterministicService()
        while !(try sender.pending().isEmpty) {
            for wire in try sender.nextBatch() {
                let document = try XCTUnwrap(sender.document(wire.id))
                let ancestor = try document.ancestor.map { try JSONDecoder().decode(WireRecord.self, from: $0).operationID }
                let encoded = try CloudCodec.encode(wire, zone: .init(zoneName: sender.session.scope.zone))
                let saved = try service.save(encoded, scope: sender.session.scope, expectedOperation: ancestor)
                try sender.acknowledge(saved, callback: sender.session.scope)
            }
        }
        let cloudRecords = Array(service.records.values)
        // Child first: keep it durable, invisible until the parent arrives.
        let child = try XCTUnwrap(cloudRecords.first { (try? CloudCodec.decode($0, scope: sender.session.scope).kind) == "media" })
        try receiver.apply(child, callback: receiver.session.scope)
        XCTAssertEqual(try blank.counts()["media"], 0)
        for record in cloudRecords where record.recordID != child.recordID { try receiver.apply(record, callback: receiver.session.scope) }
        XCTAssertEqual(try blank.counts()["items"], 1)
        XCTAssertEqual(try blank.counts()["drafts"], 0)
        XCTAssertEqual(try blank.counts()["media"], 1)
        XCTAssertTrue(try receiver.pending().isEmpty)
        let media = try XCTUnwrap(blank.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
        XCTAssertNotNil(try Data(contentsOf: blank.root.appendingPathComponent("media/" + XCTUnwrap(media.thumbnailFileName))))
        XCTAssertFalse(FileManager.default.fileExists(atPath: blank.root.appendingPathComponent("media/" + media.originalFileName).path), "Metadata/preview fixture transport must not imply restored original")
        let sourceProfile = try XCTUnwrap(source.context.fetch(FetchDescriptor<WardrobeProfile>()).first)
        XCTAssertEqual(try blank.context.fetch(FetchDescriptor<WardrobeProfile>()).first?.id, sourceProfile.id)
    }

    @MainActor func testLostAckRetryAndTwoRealUsageActions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: root)
        try core.setEnabled(true); try core.finishBootstrap(callback: core.session.scope)
        let service = DeterministicService()
        let parent = UUID()
        let parentRecord = WireRecord(id: parent, operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "Usage parent")
        try core.apply(CloudCodec.encode(parentRecord, zone: .init(zoneName: core.session.scope.zone)), callback: core.session.scope)
        let usage = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "usage", parentID: parent)
        try core.write(usage); try core.write(usage)
        let proposal = try XCTUnwrap(core.nextBatch().first)
        let ck = try CloudCodec.encode(proposal, zone: .init(zoneName: core.session.scope.zone))
        XCTAssertThrowsError(try service.save(ck, scope: core.session.scope, expectedOperation: nil, loseACK: true))
        let saved = try service.save(ck, scope: core.session.scope, expectedOperation: nil)
        try core.acknowledge(saved, callback: core.session.scope)
        XCTAssertEqual(service.records.count, 1)
        let second = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "usage", parentID: parent)
        try core.write(second)
        XCTAssertEqual(try core.pending().count, 1)
        XCTAssertNotEqual(usage.id, second.id)
    }

    @MainActor func testIndependentLibrariesAndClonedDraftConfirm() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try LocalChain(root: root.appendingPathComponent("one"))
        let second = try LocalChain(root: root.appendingPathComponent("two"))
        XCTAssertNotEqual(first.libraryID, second.libraryID)
        XCTAssertThrowsError(try LocalChain(root: second.root, libraryID: first.libraryID))
        let draft = try first.capture(MediaFiles.syntheticJPEG())
        let peer = try LocalChain(root: root.appendingPathComponent("peer"), libraryID: first.libraryID)
        let source = try SyncCore.local(context: first.context, library: first.libraryID, root: first.root)
        let target = try SyncCore(context: peer.context, scope: source.session.scope, mediaRoot: peer.root)
        try target.setEnabled(true)
        for intent in try source.pending() {
            let wire = try JSONDecoder().decode(WireRecord.self, from: intent.payload)
            try target.apply(CloudCodec.encode(wire, zone: .init(zoneName: target.session.scope.zone)), callback: target.session.scope)
        }
        XCTAssertEqual(try first.confirm(draft), try peer.confirm(draft))
        XCTAssertEqual(try first.confirm(draft), draft)
    }
}
