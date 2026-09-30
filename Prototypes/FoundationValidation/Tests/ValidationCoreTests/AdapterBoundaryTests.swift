import XCTest
import SwiftData
import CloudKit
@testable import ValidationCore

final class AdapterBoundaryTests: XCTestCase {
    @MainActor func fixture(_ body: (LocalChain, SyncCore, CloudAdapter) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: root)
        try core.setEnabled(true); try core.finishBootstrap(callback: core.session.scope)
        try body(chain, core, CloudAdapter(core: core))
    }
    @MainActor func testPartialSuccessRetiresOnlyAckedOperationAndFetchFailureCannotBootstrap() throws {
        try fixture { chain, core, adapter in
            let one = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "same name")
            var two = one; two.id = UUID(); two.operationID = UUID()
            try core.write(one); try core.write(two); _ = try core.nextBatch()
            XCTAssertEqual(try chain.counts()["items"], 2)
            let saved = try CloudCodec.encode(one, zone: .init(zoneName: core.session.scope.zone))
            try adapter.applySendResults(saved: [saved], errors: [CKError(.networkFailure)])
            XCTAssertEqual(try core.pending().map(\.operationID), [two.operationID])
            let reopened = try LocalChain(root: chain.root)
            let resumed = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
            XCTAssertNotNil(resumed.session.retryAfter)
            XCTAssertEqual(try resumed.pending().count, 1)
            try adapter.beginFetch()
            try adapter.recordFetchFailure(CKError(.networkUnavailable))
            try adapter.completeFetch()
            XCTAssertFalse(core.session.bootstrapComplete)
            XCTAssertTrue(try core.nextBatch().isEmpty)
            try core.setEnabled(false)
            try adapter.classify(CKError(.userDeletedZone))
            XCTAssertNil(core.session.pauseReason, "Old error callback after OFF cannot alter the new epoch")
        }
    }
    @MainActor func testZoneLossClassificationDurablyPausesAndCannotSchedule() throws {
        for code in [CKError.Code.userDeletedZone, .zoneNotFound] {
            try fixture { chain, core, adapter in
                try adapter.classify(CKError(code))
                let reopened = try LocalChain(root: chain.root)
                let resumed = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
                XCTAssertTrue(try resumed.nextBatch().isEmpty)
                XCTAssertFalse(resumed.session.bootstrapComplete)
                XCTAssertTrue(try XCTUnwrap(resumed.session.pauseReason).contains(code == .userDeletedZone ? "userDeletedZone" : "zoneNotFound"))
                XCTAssertNil(adapter.engine, "No native engine/service or auto recreation used by failure classification")
            }
        }
    }
    @MainActor func testEncryptedDataResetUsesActualSDKKeyAndNeverInitializesZone() throws {
        try fixture { chain, core, adapter in
            try adapter.classify(CKError(.zoneNotFound, userInfo: [CKErrorUserDidResetEncryptedDataKey: NSNumber(value: true)]))
            let reopened = try LocalChain(root: chain.root)
            let resumed = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
            XCTAssertTrue(try XCTUnwrap(resumed.session.pauseReason).contains("encrypted-data reset reported"))
            XCTAssertTrue(try resumed.nextBatch().isEmpty)
            XCTAssertNil(adapter.engine)
        }
    }

    @MainActor func testConditionalDeleteConflictUsesNativeDelegateReducerAndPauses() throws {
        try fixture { chain, core, adapter in
            let base = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "base")
            let zone = CKRecordZone.ID(zoneName: core.session.scope.zone)
            try core.apply(CloudCodec.encode(base, zone: zone), callback: core.session.scope)
            var deletion = base; deletion.operationID = UUID(); deletion.revision = 2; deletion.name = nil; deletion.deleted = true
            try core.write(deletion); _ = try core.nextBatch()
            var remote = base; remote.operationID = UUID(); remote.revision = 2; remote.name = "concurrent edit"
            let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: try CloudCodec.encode(remote, zone: zone)])
            try adapter.applySendResults(saved: [], errors: [error])
            XCTAssertNotNil(core.session.pauseReason)
            XCTAssertEqual(try chain.context.fetchCount(FetchDescriptor<ConflictCandidate>()), 1)
            XCTAssertTrue(try core.nextBatch().isEmpty)
            XCTAssertEqual(try core.pending().count, 1)
        }
    }
}
