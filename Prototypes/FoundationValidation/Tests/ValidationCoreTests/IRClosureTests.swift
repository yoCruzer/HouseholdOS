import XCTest
import SwiftData
import CloudKit
@testable import ValidationCore

final class IRClosureTests: XCTestCase {
    func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    @MainActor func core(_ chain: LocalChain) throws -> SyncCore {
        let c = try SyncCore.local(context: chain.context, library: chain.libraryID, root: chain.root)
        try c.setEnabled(true); try c.finishBootstrap(callback: c.session.scope); return c
    }
    @MainActor func apply(_ w: WireRecord, _ c: SyncCore) throws {
        try c.apply(CloudCodec.encode(w, zone: .init(zoneName: c.session.scope.zone)), callback: c.session.scope)
    }
    @MainActor func value(_ id: UUID, _ c: SyncCore) throws -> WireRecord {
        try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(c.document(id)).payload)
    }
    @MainActor func testCrossIncarnationBlocksUnmixedParentAndChildren() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let chain = try LocalChain(root: r), c = try core(chain)
        let a = WireRecord(id: UUID(), operationID: UUID(), revision: 10, library: chain.libraryID, kind: "item", name: "Old", incarnation: UUID())
        try apply(a, c)
        var b = a; b.operationID = UUID(); b.revision += 1; b.category = UUID().uuidString
        try c.write(b)
        let child = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "usage", parentID: a.id, parentIncarnation: a.incarnation)
        try c.write(child)
        var next = a; next.operationID = UUID(); next.revision = 12; next.incarnation = UUID(); next.replacesDeletion = UUID(); next.name = "New"
        XCTAssertNil(ThreeWayMerge.merge(ancestor: a, local: b, remote: next))
        try apply(next, c)
        XCTAssertEqual(try value(a.id, c), b)
        XCTAssertEqual(try chain.context.fetchCount(FetchDescriptor<ConflictCandidate>()), 1)
        XCTAssertTrue(try c.nextBatch().isEmpty)
        let reopen = try LocalChain(root: r)
        XCTAssertTrue(try core(reopen).nextBatch().isEmpty)
    }
    @MainActor func testKnownDeletionReplayPreservesReAddAndInflight() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let chain = try LocalChain(root: r), c = try core(chain)
        let d = WireRecord(id: UUID(), operationID: UUID(), revision: 2, library: chain.libraryID, kind: "item", deleted: true)
        try apply(d, c)
        var readd = d; readd.operationID = UUID(); readd.revision = 3; readd.deleted = false; readd.name = "Re-added"; readd.incarnation = UUID(); readd.replacesDeletion = d.operationID
        try c.write(readd); try apply(d, c)
        XCTAssertEqual(try value(d.id, c), readd); XCTAssertEqual(try c.nextBatch(), [readd])
        let reopened = try LocalChain(root: r), resumed = try core(reopened)
        try apply(d, resumed); try apply(d, resumed)
        XCTAssertEqual(try resumed.nextBatch(), [readd]); XCTAssertEqual(try resumed.pending().count, 1)
        var newer = readd; newer.operationID = UUID(); newer.revision += 1; newer.deleted = true; newer.name = nil
        try apply(newer, resumed)
        XCTAssertTrue(try resumed.nextBatch().isEmpty); XCTAssertEqual(try reopened.counts()["items"], 0)
    }
    @MainActor func testRepeatedBatchPreparationBoundedAndPartialAckDrains() throws {
        for count in [99, 100, 101, 300] {
            let r = root(); defer { try? FileManager.default.removeItem(at: r) }
            let chain = try LocalChain(root: r), c = try core(chain)
            for _ in 0..<count { try c.stageWrite(WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "Batch")) }
            try c.commit()
            let first = try c.nextBatch(); XCTAssertEqual(first.count, min(count, 100))
            XCTAssertEqual(try c.nextBatch(), first); XCTAssertEqual(try c.nextBatch(), first)
            let reopened = try LocalChain(root: r), resumed = try core(reopened)
            XCTAssertEqual(try resumed.nextBatch(), first)
            var rounds = 0
            while !(try resumed.pending().isEmpty) && rounds < 10 {
                let batch = try resumed.nextBatch(); XCTAssertLessThanOrEqual(batch.count, 100); XCTAssertFalse(batch.isEmpty)
                for w in batch.prefix(50) {
                    let record = try CloudCodec.encode(w, zone: .init(zoneName: resumed.session.scope.zone))
                    try resumed.acknowledge(record, callback: resumed.session.scope)
                    try resumed.acknowledge(record, callback: resumed.session.scope)
                }
                rounds += 1
            }
            XCTAssertTrue(try resumed.pending().isEmpty)
        }
    }
    @MainActor func testMediaCurrentIsExplicitNotHighestRevision() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let chain = try LocalChain(root: r); _ = try chain.capture(MediaFiles.syntheticJPEG())
        let c = try core(chain), transfers = try MediaTransfers(chain: chain, core: c)
        let asset = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
        let selected = try transfers.current(asset.id)
        chain.context.insert(MediaRepresentation(mediaID: asset.id, revision: selected.revision + 10, precision: selected.precision, originalHash: selected.originalHash, relativePath: selected.relativePath))
        try c.commit()
        XCTAssertEqual(try transfers.current(asset.id).id, selected.id)
        let manifest = try BackupRestore.export(chain, to: r.appendingPathComponent("backup"), full: true)
        XCTAssertEqual(manifest.representations.first(where: { $0.mediaID == asset.id })?.representationID, selected.id)
    }
    @MainActor func testResolvedConflictRestoreDoesNotBlockReAdd() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let chain = try LocalChain(root: r.appendingPathComponent("source")), c = try core(chain)
        let live = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "Local")
        try c.write(live)
        var d = live; d.operationID = UUID(); d.revision = 2; d.deleted = true; d.name = nil
        try apply(d, c)
        var readd = live; readd.operationID = UUID(); readd.revision = 3; readd.incarnation = UUID(); readd.replacesDeletion = d.operationID
        try c.write(readd)
        var active = live; active.id = UUID(); active.operationID = UUID(); try c.write(active)
        var remote = active; remote.operationID = UUID(); remote.name = "Remote"; try apply(remote, c)
        let conflictBefore = try chain.context.fetch(FetchDescriptor<ConflictCandidate>())
        let preserved = Dictionary(uniqueKeysWithValues: conflictBefore.map { ($0.id, [$0.local, $0.remote]) })
        let resolved = try XCTUnwrap(conflictBefore.first { $0.entityID == readd.id })
        XCTAssertTrue(try resolved.isResolved(in: chain.context))
        // Persist an old candidate's resolved/<scope> representation for compatibility.
        for checkpoint in try chain.context.fetch(FetchDescriptor<SyncCheckpoint>()) where checkpoint.key == "conflict-resolution/" + resolved.id.uuidString { chain.context.delete(checkpoint) }
        resolved.scope = "resolved/" + c.session.scope.key
        try c.commit()
        let package = r.appendingPathComponent("backup"), generations = r.appendingPathComponent("generations")
        _ = try BackupRestore.export(chain, to: package, full: true); _ = try BackupRestore.restore(package, into: generations)
        let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
        let resumed = try SyncCore.local(context: restored.context, library: restored.libraryID, root: restored.root)
        let scope = SyncScope(container: "fixture", environment: "Development", account: "fixture", library: restored.libraryID, zone: "HHOSVAL_fixture", epoch: UUID())
        try resumed.prepareRestoreAdmission(to: scope); try resumed.finishBootstrap(callback: scope)
        let batch = try resumed.nextBatch()
        XCTAssertTrue(batch.contains { $0.id == readd.id }); XCTAssertFalse(batch.contains { $0.id == active.id })
        XCTAssertEqual(try restored.context.fetchCount(FetchDescriptor<ConflictCandidate>()), 2)
        let reopened = try LocalChain(root: restored.root)
        let reopenedCore = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
        for conflict in try reopened.context.fetch(FetchDescriptor<ConflictCandidate>()) {
            XCTAssertEqual([conflict.local, conflict.remote], preserved[conflict.id])
            XCTAssertEqual(try conflict.isResolved(in: reopened.context), conflict.entityID == readd.id)
            XCTAssertEqual(conflict.scope, scope.key)
        }
        try apply(d, reopenedCore)
        XCTAssertEqual(try value(readd.id, reopenedCore), readd)
        XCTAssertTrue(try reopenedCore.nextBatch().contains { $0.id == readd.id })
    }
}

extension IRClosureTests {
    @MainActor func testPreparedPreviewFailureRecoversOneCaptureAndBackup() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let bytes = try MediaFiles.syntheticJPEG()
        let chain = try LocalChain(root: r.appendingPathComponent("source"))
        XCTAssertThrowsError(try chain.capture(bytes, fault: .previewWrite))
        let journalURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: chain.root.appendingPathComponent("journals"), includingPropertiesForKeys: nil).first)
        let journal = try JSONDecoder().decode(FileJournal.self, from: Data(contentsOf: journalURL))
        let reopened = try LocalChain(root: chain.root)
        try reopened.recover(); try reopened.recover()
        XCTAssertEqual(try reopened.counts(), ["drafts": 1, "items": 0, "media": 1, "profiles": 1, "outbox": 2])
        guard try reopened.counts()["drafts"] == 1 else { return }
        XCTAssertEqual(try reopened.confirm(journal.draftID), journal.draftID)
        let before = try reopened.counts(); try reopened.recover(); XCTAssertEqual(try reopened.counts(), before)
        let package = r.appendingPathComponent("backup"), generations = r.appendingPathComponent("generations")
        _ = try BackupRestore.export(reopened, to: package, full: true); _ = try BackupRestore.restore(package, into: generations)
        let target = try LocalChain(root: BackupRestore.activeGeneration(in: generations)); try target.recover()
        XCTAssertEqual(try target.counts(), before)
        XCTAssertEqual(try Data(contentsOf: target.root.appendingPathComponent("media/" + journal.originalName)), bytes)
    }
    @MainActor func testLegacyMigrationBootstrapPartialAckRestartAndBlankReceiver() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let source = r.appendingPathComponent("legacy"), clone = r.appendingPathComponent("clone")
        try LegacyFixture.generateSyncFixture(at: source)
        let original = try Data(contentsOf: source.appendingPathComponent("legacy-original.jpg"))
        let expected = try Data(contentsOf: source.appendingPathComponent("expected.json"))
        let sourceID = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: source.appendingPathComponent("legacy-source-id.json")))
        try LegacyFixture.migrateClone(from: source, to: clone)
        let chain = try LocalChain(root: clone)
        let item = try XCTUnwrap(chain.context.fetch(FetchDescriptor<ItemRecord>()).first)
        XCTAssertThrowsError(try chain.bootstrapLegacy(sourceID: sourceID, itemIDs: [item.id], failCommit: true))
        XCTAssertEqual(try chain.counts()["outbox"], 0)
        try chain.bootstrapLegacy(sourceID: sourceID, itemIDs: [item.id])
        let c = try SyncCore.local(context: chain.context, library: chain.libraryID, root: clone)
        try c.setEnabled(true); XCTAssertTrue(try c.nextBatch().isEmpty)
        try c.finishBootstrap(callback: c.session.scope)
        let first = try c.nextBatch(); XCTAssertEqual(first.count, 2)
        let target = try LocalChain(root: r.appendingPathComponent("target"), libraryID: chain.libraryID), receiver = try core(target)
        for wire in first { try apply(wire, receiver) }
        let ack = try CloudCodec.encode(first[0], zone: .init(zoneName: c.session.scope.zone))
        try c.acknowledge(ack, callback: c.session.scope)
        let reopened = try LocalChain(root: clone)
        try reopened.bootstrapLegacy(sourceID: sourceID, itemIDs: [item.id])
        let resumed = try core(reopened)
        XCTAssertEqual(try resumed.pending().count, 1)
        for wire in try resumed.nextBatch() {
            try apply(wire, receiver)
            try resumed.acknowledge(CloudCodec.encode(wire, zone: .init(zoneName: resumed.session.scope.zone)), callback: resumed.session.scope)
        }
        try reopened.bootstrapLegacy(sourceID: sourceID, itemIDs: [item.id])
        XCTAssertTrue(try resumed.pending().isEmpty)
        let targetItem = try XCTUnwrap(target.context.fetch(FetchDescriptor<ItemRecord>()).first)
        XCTAssertEqual(try target.counts()["items"], 1); XCTAssertEqual(targetItem.id, item.id); XCTAssertEqual(targetItem.name, item.name)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("legacy-original.jpg")), original)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("expected.json")), expected)
        XCTAssertEqual(try Data(contentsOf: clone.appendingPathComponent("legacy-original.jpg")), original)
        let receiptRow = try XCTUnwrap(reopened.context.fetch(FetchDescriptor<SyncCheckpoint>()).first { $0.key.hasPrefix("legacy-bootstrap/") })
        let receipt = try JSONDecoder().decode(LegacyBootstrapReceipt.self, from: receiptRow.data)
        XCTAssertEqual(receipt.householdID, item.householdID); XCTAssertEqual(receipt.libraryID, chain.libraryID)
        XCTAssertEqual(receipt.itemID, item.id)
    }
}

extension IRClosureTests {
    @MainActor func testOversizedHistoricalInflightAndServiceLimitStayBounded() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let chain = try LocalChain(root: r), c = try core(chain)
        for _ in 0..<101 { try c.stageWrite(WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "Overflow")) }
        for intent in try c.pending() { chain.context.insert(SentSnapshot(intent)) }
        try c.commit()
        XCTAssertEqual(try c.nextBatch().count, 100)
        XCTAssertEqual(try chain.context.fetchCount(FetchDescriptor<SentSnapshot>()), 101)
        let adapter = CloudAdapter(core: c)
        for limit in [50, 25, 12, 6, 3, 1] {
            _ = try adapter.prepareBatch()
            try adapter.applySendResults(saved: [], errors: Array(repeating: CKError(.limitExceeded), count: 7))
            try adapter.applySendResults(saved: [], errors: [CKError(.limitExceeded)])
            XCTAssertEqual(try c.nextBatch().count, limit)
            XCTAssertEqual(try c.pending().count, 101)
        }
        _ = try adapter.prepareBatch()
        try adapter.applySendResults(saved: [], errors: [CKError(.limitExceeded)])
        XCTAssertNotNil(c.session.pauseReason); XCTAssertTrue(try c.nextBatch().isEmpty)
        let reopened = try LocalChain(root: r)
        let resumed = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
        XCTAssertNotNil(resumed.session.pauseReason); XCTAssertEqual(try resumed.pending().count, 101)
        XCTAssertTrue(try resumed.nextBatch().isEmpty)
    }
    @MainActor func testEqualRevisionCurrentChoiceSurvivesRestoreAndLateTransfers() throws {
        for reverse in [false, true] {
            let r = root(); defer { try? FileManager.default.removeItem(at: r) }
            let chain = try LocalChain(root: r.appendingPathComponent("source")); _ = try chain.capture(MediaFiles.syntheticJPEG())
            let c = try core(chain), transfers = try MediaTransfers(chain: chain, core: c)
            let asset = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
            try transfers.setPolicy(.appOwnedOriginals)
            let old = try transfers.beginUpload(asset.id)
            let oldDownload = try transfers.downloadTicket(asset.id)
            let oldBytes = try Data(contentsOf: chain.root.appendingPathComponent(transfers.current(asset.id).relativePath))
            // Settle metadata so the new explicit choice is an inbound projection.
            for wire in try c.nextBatch() { try apply(wire, c) }
            var wire = try value(asset.id, c)
            let original = try transfers.current(asset.id)
            let bytes = try MediaFiles.syntheticJPEG(seed: 99), preview = try MediaFiles.preview(bytes)
            let selectedID = UUID(), historicalID = UUID()
            for id in (reverse ? [selectedID, historicalID] : [historicalID, selectedID]) {
                let name = "media/" + id.uuidString + ".original"
                let representationBytes = id == selectedID ? bytes : try MediaFiles.syntheticJPEG(seed: 101)
                try MediaFiles.write(representationBytes, to: chain.root.appendingPathComponent(name))
                chain.context.insert(MediaRepresentation(id: id, mediaID: asset.id, revision: original.revision, precision: "importedBytes", originalHash: MediaFiles.hash(representationBytes), relativePath: name))
            }
            try c.commit()
            wire.operationID = UUID(); wire.revision += 1
            wire.media = WireMedia(representationID: selectedID, revision: original.revision, hash: MediaFiles.hash(bytes), precision: "importedBytes", contentType: "public.jpeg", preview: preview)
            try apply(wire, c)
            XCTAssertEqual(try transfers.current(asset.id).id, selectedID)
            XCTAssertFalse(try transfers.acknowledge(old)); XCTAssertFalse(try transfers.receive(oldBytes, for: oldDownload))
            let package = r.appendingPathComponent("backup"), generations = r.appendingPathComponent("generations")
            let manifest = try BackupRestore.export(chain, to: package, full: true)
            XCTAssertEqual(manifest.representations.first?.representationID, selectedID)
            _ = try BackupRestore.restore(package, into: generations)
            let target = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
            let resumed = try SyncCore.local(context: target.context, library: target.libraryID, root: target.root)
            let scope = SyncScope(container: "fixture", environment: "Development", account: "new", library: target.libraryID, zone: "HHOSVAL_restore", epoch: UUID())
            try resumed.prepareRestoreAdmission(to: scope); try resumed.finishBootstrap(callback: scope)
            let restoredTransfers = try MediaTransfers(chain: target, core: resumed)
            XCTAssertEqual(try restoredTransfers.current(asset.id).id, selectedID)
            XCTAssertFalse(try restoredTransfers.acknowledge(old)); XCTAssertFalse(try restoredTransfers.receive(oldBytes, for: oldDownload))
            XCTAssertEqual(try target.context.fetchCount(FetchDescriptor<MediaRepresentation>()), 3)
            let selected = try restoredTransfers.current(asset.id); target.context.delete(selected); try resumed.commit()
            XCTAssertThrowsError(try restoredTransfers.downloadTicket(asset.id))
            XCTAssertThrowsError(try BackupRestore.export(target, to: r.appendingPathComponent("missing-current"), full: true))
        }
    }
    @MainActor func testPreparedRecoveryRetryCorruptionAndIndependentProgress() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let chain = try LocalChain(root: r), bytes = try MediaFiles.syntheticJPEG()
        XCTAssertThrowsError(try chain.capture(bytes, fault: .originalWrite))
        XCTAssertThrowsError(try chain.capture(bytes, fault: .previewWrite))
        let journals = try FileManager.default.contentsOfDirectory(at: r.appendingPathComponent("journals"), includingPropertiesForKeys: nil)
        let originalJournals = try journals.map { try JSONDecoder().decode(FileJournal.self, from: Data(contentsOf: $0)) }
        let prepared = try XCTUnwrap(originalJournals.first { FileManager.default.fileExists(atPath: r.appendingPathComponent("staging/" + $0.originalName).path) })
        for fault in [LocalFault.previewWrite, .beforeSave] {
            let retry = try LocalChain(root: r); try retry.recover(fault: fault)
            XCTAssertEqual(try retry.counts()["drafts"], 0); XCTAssertEqual(try retry.counts()["outbox"], 0)
            XCTAssertEqual(retry.recoveryIssues.count, 2)
        }
        let valid = try LocalChain(root: r); try valid.recover(fault: .cleanup)
        XCTAssertEqual(try valid.counts()["drafts"], 1); XCTAssertEqual(try valid.counts()["outbox"], 2)
        let final = try LocalChain(root: r); try final.recover(); try final.recover()
        XCTAssertEqual(try final.counts()["drafts"], 1); XCTAssertEqual(final.recoveryIssues.count, 1)
        XCTAssertEqual(try Data(contentsOf: r.appendingPathComponent("media/" + prepared.originalName)), bytes)
        XCTAssertThrowsError(try final.capture(bytes, fault: .previewWrite))
        let next = try FileManager.default.contentsOfDirectory(at: r.appendingPathComponent("staging"), includingPropertiesForKeys: nil).first { $0.pathExtension == "original" }
        try Data("corrupt".utf8).write(to: XCTUnwrap(next))
        try final.recover(); XCTAssertEqual(final.recoveryIssues.count, 2); XCTAssertEqual(try final.counts()["drafts"], 1)
    }
    @MainActor func testLegacyDistinctLibrariesAndRemoteTombstoneAdmission() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        var libraries = Set<UUID>(), households = Set<UUID>()
        for index in 0..<2 {
            let source = r.appendingPathComponent("legacy-\(index)"), clone = r.appendingPathComponent("clone-\(index)")
            try LegacyFixture.generateSyncFixture(at: source); try LegacyFixture.migrateClone(from: source, to: clone)
            let chain = try LocalChain(root: clone)
            let item = try XCTUnwrap(chain.context.fetch(FetchDescriptor<ItemRecord>()).first)
            libraries.insert(chain.libraryID); households.insert(item.householdID)
            let sourceID = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: source.appendingPathComponent("legacy-source-id.json")))
            try chain.bootstrapLegacy(sourceID: sourceID, itemIDs: [item.id])
            let c = try SyncCore.local(context: chain.context, library: chain.libraryID, root: clone)
            try c.setEnabled(true); XCTAssertTrue(try c.nextBatch().isEmpty)
            var deletion = try value(item.id, c); deletion.operationID = UUID(); deletion.revision += 1; deletion.deleted = true; deletion.name = nil; deletion.category = nil
            try apply(deletion, c); try c.finishBootstrap(callback: c.session.scope)
            XCTAssertTrue(try c.nextBatch().isEmpty); XCTAssertEqual(try chain.counts()["items"], 0)
            try chain.bootstrapLegacy(sourceID: sourceID, itemIDs: [item.id])
            XCTAssertTrue(try c.nextBatch().isEmpty)
        }
        XCTAssertEqual(households.count, 1); XCTAssertEqual(libraries.count, 2)
    }
}

extension IRClosureTests {
    @MainActor func testActualOldChildSnapshotCannotCrossReAddAndNewIntentAdvances() throws {
        for inflight in [false, true] {
            let r = root(); defer { try? FileManager.default.removeItem(at: r) }
            let chain = try LocalChain(root: r), c = try core(chain)
            let parent = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "item", name: "Old", profile: WireProfile(id: UUID(), size: "M"))
            try apply(parent, c)
            let child = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "usage", parentID: parent.id)
            try c.write(child)
            if inflight { _ = try c.nextBatch() }
            var d = parent; d.operationID = UUID(); d.revision = 2; d.deleted = true; d.name = nil; d.profile = nil
            try apply(d, c)
            var readd = parent; readd.operationID = UUID(); readd.revision = 3; readd.incarnation = UUID(); readd.replacesDeletion = d.operationID; readd.profile = nil
            try c.write(readd)
            var newChild = child; newChild.operationID = UUID(); newChild.revision = 2; newChild.parentIncarnation = readd.incarnation
            try c.write(newChild); try apply(d, c)
            let batch = try c.nextBatch()
            XCTAssertFalse(batch.contains { $0.operationID == child.operationID })
            XCTAssertTrue(batch.contains { $0.operationID == newChild.operationID })
            XCTAssertTrue(batch.contains { $0.operationID == readd.operationID })
            XCTAssertEqual(try chain.counts()["profiles"], 0, "Old profile cannot follow only the owner UUID")
            let reopened = try LocalChain(root: r), resumed = try core(reopened)
            let after = try resumed.nextBatch()
            XCTAssertFalse(after.contains { $0.operationID == child.operationID })
            XCTAssertTrue(after.contains { $0.operationID == newChild.operationID })
            // A delayed old child ACK cannot change the new child ancestor.
            let prior = try resumed.document(child.id)?.ancestor
            try resumed.acknowledge(CloudCodec.encode(child, zone: .init(zoneName: resumed.session.scope.zone)), callback: resumed.session.scope)
            XCTAssertEqual(try resumed.document(child.id)?.ancestor, prior)
        }
    }
    @MainActor func testNewAndOldChildrenArrivalOrdersAndLowRevisionReAdd() throws {
        for newFirst in [false, true] {
            let r = root(); defer { try? FileManager.default.removeItem(at: r) }
            let chain = try LocalChain(root: r), c = try core(chain)
            let parent = WireRecord(id: UUID(), operationID: UUID(), revision: 50, library: chain.libraryID, kind: "item", name: "Old", profile: WireProfile(id: UUID(), size: "M"))
            try apply(parent, c)
            var readd = parent; readd.operationID = UUID(); readd.revision = 2; readd.incarnation = UUID(); readd.replacesDeletion = UUID(); readd.name = "New"; readd.profile = nil
            let preview = try MediaFiles.preview(MediaFiles.syntheticJPEG())
            let oldChild = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: chain.libraryID, kind: "media", parentID: parent.id, media: WireMedia(representationID: UUID(), revision: 1, hash: String(repeating: "a", count: 64), precision: "importedBytes", contentType: "public.jpeg", preview: preview))
            var newChild = oldChild; newChild.id = UUID(); newChild.operationID = UUID(); newChild.parentIncarnation = readd.incarnation; newChild.media?.representationID = UUID()
            try apply(newFirst ? newChild : oldChild, c)
            try apply(readd, c)
            try apply(newFirst ? oldChild : newChild, c)
            try apply(oldChild, c); try apply(newChild, c)
            XCTAssertEqual(try value(parent.id, c), readd)
            XCTAssertEqual(try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).map(\.id), [newChild.id])
            XCTAssertEqual(try chain.counts()["profiles"], 0)
            let reopened = try LocalChain(root: r), resumed = try core(reopened)
            XCTAssertEqual(try reopened.context.fetch(FetchDescriptor<MediaAssetRecord>()).map(\.id), [newChild.id])
            XCTAssertTrue(try resumed.nextBatch().isEmpty)
        }
    }
    @MainActor func testLegacyJournalCompatibilityAndFutureJournalIsPreserved() throws {
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let chain = try LocalChain(root: r)
        XCTAssertThrowsError(try chain.capture(MediaFiles.syntheticJPEG(), fault: .previewWrite))
        let path = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: r.appendingPathComponent("journals"), includingPropertiesForKeys: nil).first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        for key in ["profileID", "representationID", "draftOperationID", "mediaOperationID", "precision", "photoReference"] { json.removeValue(forKey: key) }
        try JSONSerialization.data(withJSONObject: json).write(to: path)
        let reopened = try LocalChain(root: r); try reopened.recover(fault: .beforeSave)
        let upgraded = try Data(contentsOf: path)
        try reopened.recover(fault: .beforeSave)
        XCTAssertEqual(try JSONDecoder().decode(FileJournal.self, from: Data(contentsOf: path)).profileID, try JSONDecoder().decode(FileJournal.self, from: upgraded).profileID)
        try reopened.recover(); XCTAssertEqual(try reopened.counts()["drafts"], 1)
        XCTAssertThrowsError(try reopened.capture(MediaFiles.syntheticJPEG(), fault: .previewWrite))
        let futurePath = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: r.appendingPathComponent("journals"), includingPropertiesForKeys: nil).first)
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: futurePath)) as? [String: Any]); future["futureMeaning"] = "preserve"
        let bytes = try JSONSerialization.data(withJSONObject: future); try bytes.write(to: futurePath)
        try reopened.recover()
        XCTAssertEqual(try Data(contentsOf: futurePath), bytes); XCTAssertEqual(reopened.recoveryIssues.count, 1)
        XCTAssertEqual(try reopened.counts()["drafts"], 1)
    }
}
