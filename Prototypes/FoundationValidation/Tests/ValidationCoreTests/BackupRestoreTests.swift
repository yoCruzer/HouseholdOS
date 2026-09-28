import XCTest
import SwiftData
@testable import ValidationCore

final class BackupRestoreTests: XCTestCase {
    @MainActor func fixture(_ body: (LocalChain, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root.appendingPathComponent("source"))
        let draft = try chain.capture(MediaFiles.syntheticJPEG())
        _ = try chain.confirm(draft)
        try body(chain, root)
    }

    @MainActor func testConsistentSnapshotRestoreKeepsBytesConflictsAndPendingButClearsDeviceState() throws {
        try fixture { chain, root in
            let sync = try SyncCore.local(context: chain.context, library: chain.libraryID, root: chain.root)
            try sync.setEnabled(true); try sync.finishBootstrap(callback: sync.session.scope)
            _ = try sync.nextBatch()
            let item = try XCTUnwrap(chain.context.fetch(FetchDescriptor<ItemRecord>()).first)
            chain.context.insert(ConflictCandidate(entityID: item.id, local: Data("local fixture candidate".utf8), remote: Data("remote fixture candidate".utf8), scope: sync.session.scope.key))
            try chain.context.save()
            let destination = root.appendingPathComponent("backup")
            let manifest = try BackupRestore.export(chain, to: destination, full: true)
            XCTAssertTrue(manifest.complete)
            let sourceHash = try manifest.representations.map { try MediaFiles.hash(Data(contentsOf: chain.root.appendingPathComponent($0.path))) }
            let generations = root.appendingPathComponent("restored")
            XCTAssertEqual(try BackupRestore.restore(destination, into: generations), manifest.snapshotID)
            let recovered = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
            XCTAssertEqual(try recovered.counts(), try chain.counts())
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<SentSnapshot>()), 0)
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<ConflictCandidate>()), 1)
            let restoredSync = try SyncCore.local(context: recovered.context, library: recovered.libraryID, root: recovered.root)
            XCTAssertFalse(restoredSync.session.enabled)
            XCTAssertNotNil(restoredSync.session.pauseReason)
            XCTAssertNil(restoredSync.session.engineSerialization)
            XCTAssertTrue(try recovered.context.fetch(FetchDescriptor<SyncedDocument>()).allSatisfy { $0.systemFields == nil && $0.ancestor == nil })
            XCTAssertEqual(try manifest.representations.map { try MediaFiles.hash(Data(contentsOf: recovered.root.appendingPathComponent($0.path))) }, sourceHash)
            XCTAssertTrue(FileManager.default.fileExists(atPath: chain.root.appendingPathComponent("library.store").path))
            XCTAssertEqual(try BackupRestore.validate(destination).snapshotID, manifest.snapshotID)
        }
    }

    @MainActor func testRestorePreservesRetiredBytesButDropsOldMediaTicketsAndAcknowledgements() throws {
        try fixture { chain, root in
            let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: chain.root)
            try core.setEnabled(true); try core.finishBootstrap(callback: core.session.scope)
            let transfers = try MediaTransfers(chain: chain, core: core)
            let media = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
            try transfers.setPolicy(.appOwnedOriginals)
            let acknowledged = try transfers.beginUpload(media.id)
            XCTAssertTrue(try transfers.acknowledge(acknowledged))
            try transfers.replace(media.id, bytes: MediaFiles.syntheticJPEG(seed: 99))
            _ = try transfers.beginUpload(media.id)
            XCTAssertEqual(transfers.state.tickets.count, 2)
            let backup = root.appendingPathComponent("history-backup")
            let manifest = try BackupRestore.export(chain, to: backup, full: true)
            XCTAssertEqual(manifest.representations.count, 2)
            let target = root.appendingPathComponent("history-restored")
            _ = try BackupRestore.restore(backup, into: target)
            let restored = try LocalChain(root: BackupRestore.activeGeneration(in: target))
            let resumed = try SyncCore.local(context: restored.context, library: restored.libraryID, root: restored.root)
            let restoredTransfers = try MediaTransfers(chain: restored, core: resumed)
            XCTAssertTrue(restoredTransfers.state.tickets.isEmpty)
            XCTAssertEqual(restoredTransfers.state.policy, .preview)
            XCTAssertEqual(try restored.context.fetchCount(FetchDescriptor<MediaRepresentation>()), 2)
            for representation in manifest.representations {
                XCTAssertEqual(try Data(contentsOf: restored.root.appendingPathComponent(representation.path)), try Data(contentsOf: chain.root.appendingPathComponent(representation.path)))
            }
            XCTAssertFalse(resumed.session.enabled)
            XCTAssertThrowsError(try restoredTransfers.beginUpload(media.id))
        }
    }

    @MainActor func testSnapshotSerializesQueuedMutationAtSingleWriterBoundary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root.appendingPathComponent("source"))
        _ = try chain.capture(MediaFiles.syntheticJPEG())
        let queued = Task { @MainActor in try chain.capture(MediaFiles.syntheticJPEG(seed: 91)) }
        let package = root.appendingPathComponent("snapshot")
        let manifest = try BackupRestore.export(chain, to: package, full: true)
        XCTAssertEqual(manifest.representations.count, 1)
        _ = try await queued.value
        XCTAssertEqual(try chain.counts()["drafts"], 2)
        let generations = root.appendingPathComponent("generations")
        _ = try BackupRestore.restore(package, into: generations)
        let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
        XCTAssertEqual(try restored.counts()["drafts"], 1)
        XCTAssertEqual(try restored.context.fetchCount(FetchDescriptor<MediaRepresentation>()), 1)
        XCTAssertEqual(try BackupRestore.validate(package).snapshotID, manifest.snapshotID)
    }

    @MainActor func testInterruptedExportAndSwitchLeavePriorGenerationUsable() throws {
        try fixture { chain, root in
            let backup = root.appendingPathComponent("good")
            _ = try BackupRestore.export(chain, to: backup, full: false)
            for fault in [BackupFault.cancelled, .capacity, .interrupted] {
                let path = root.appendingPathComponent(UUID().uuidString)
                XCTAssertThrowsError(try BackupRestore.export(chain, to: path, full: false, fault: fault))
                XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
                XCTAssertThrowsError(try BackupRestore.validate(path.appendingPathExtension("partial")))
            }
            let generations = root.appendingPathComponent("generations")
            _ = try BackupRestore.restore(backup, into: generations)
            let previous = try BackupRestore.activeGeneration(in: generations)
            XCTAssertThrowsError(try BackupRestore.restore(backup, into: generations, fault: .beforeSwitch))
            XCTAssertEqual(try BackupRestore.activeGeneration(in: generations), previous)
            XCTAssertThrowsError(try BackupRestore.restore(backup, into: generations, fault: .afterSwitch))
            let next = try BackupRestore.activeGeneration(in: generations)
            XCTAssertNotEqual(previous, next)
            XCTAssertEqual(try LocalChain(root: previous).counts(), try LocalChain(root: next).counts())
            XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path))
        }
    }

    @MainActor func testMissingOriginalIsIncompleteAndChecksumRejectsTampering() throws {
        try fixture { chain, root in
            let backup = root.appendingPathComponent("backup")
            let manifest = try BackupRestore.export(chain, to: backup, full: true)
            let rep = try XCTUnwrap(manifest.representations.first)
            try Data("changed".utf8).write(to: backup.appendingPathComponent(rep.path))
            XCTAssertThrowsError(try BackupRestore.validate(backup))
            // Simulates an unavailable original in a test store, retaining original bytes elsewhere.
            let unavailable = root.appendingPathComponent("retained-original")
            try FileManager.default.moveItem(at: chain.root.appendingPathComponent(rep.path), to: unavailable)
            XCTAssertThrowsError(try BackupRestore.export(chain, to: root.appendingPathComponent("incomplete"), full: true))
            XCTAssertTrue(FileManager.default.fileExists(atPath: unavailable.path))
        }
    }

    @MainActor func testPathSymlinkVersionAndSizeLimits() throws {
        try fixture { chain, root in
            let backup = root.appendingPathComponent("backup")
            let original = try BackupRestore.export(chain, to: backup, full: false)
            func mutate(_ update: (inout BackupManifest) -> Void) throws {
                var manifest = original; update(&manifest)
                let bytes = try JSONEncoder().encode(manifest)
                try bytes.write(to: backup.appendingPathComponent("manifest.json"))
                try Data(MediaFiles.hash(bytes).utf8).write(to: backup.appendingPathComponent("COMPLETE"))
            }
            try mutate { $0.files[0].path = "../outside" }
            XCTAssertThrowsError(try BackupRestore.validate(backup))
            try mutate { $0.version = 999 }
            XCTAssertThrowsError(try BackupRestore.validate(backup))
            try mutate { $0.files[0].size = BackupRestore.maximumBytes + 1 }
            XCTAssertThrowsError(try BackupRestore.validate(backup))
            try mutate { _ in }
            let originalPath = try XCTUnwrap(original.representations.first?.path)
            let target = backup.appendingPathComponent(originalPath)
            let retained = root.appendingPathComponent("retained")
            try FileManager.default.moveItem(at: target, to: retained)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: retained)
            XCTAssertThrowsError(try BackupRestore.validate(backup))
        }
    }

    @MainActor func testOriginalAndRecoveryPreviewRemainBackupEligible() throws {
        try fixture { chain, _ in
            let media = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
            for name in [media.originalFileName, try XCTUnwrap(media.thumbnailFileName)] {
                XCTAssertEqual(try chain.root.appendingPathComponent("media/" + name).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
            }
            let cache = chain.root.appendingPathComponent("recreatable-thumbnail")
            try MediaFiles.write(Data("cache".utf8), to: cache, recreatable: true)
            XCTAssertEqual(try cache.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
    }
}
