import Foundation
import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import HouseholdOSApp

@MainActor
final class Goal1CoreTests: XCTestCase {
    func testDraftCRUDAndTimestampUpdates() async throws {
        var timestamp = Date(timeIntervalSince1970: 1_000)
        let environment = try makeEnvironment(now: { timestamp })
        defer { environment.removeFiles() }

        let draft = try environment.service.createDraft(source: .manual)
        XCTAssertEqual(environment.service.drafts.count, 1)
        XCTAssertEqual(draft.createdAt, timestamp)
        XCTAssertEqual(
            environment.service.displayDrafts.first(where: { $0.id == draft.id })?.updatedAt,
            timestamp
        )

        timestamp = Date(timeIntervalSince1970: 2_000)
        let location = try environment.service.createLocation(name: "  Storage Room ")
        try environment.service.updateDraft(
            id: draft.id,
            name: "  Cordless Drill ",
            categoryID: DefaultCategoryDefinition.all[2].id,
            locationID: location.id,
            note: "  Battery stored separately. "
        )

        let updated = try XCTUnwrap(
            environment.service.drafts.first(where: { $0.id == draft.id })
        )
        XCTAssertEqual(updated.name, "Cordless Drill")
        XCTAssertEqual(updated.note, "Battery stored separately.")
        XCTAssertEqual(updated.locationID, location.id)
        XCTAssertEqual(updated.updatedAt, timestamp)

        _ = try await environment.service.deleteDraft(id: draft.id)
        XCTAssertTrue(environment.service.drafts.isEmpty)
    }

    func testInvalidDraftConfirmationKeepsDraftRecoverable() throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .photoLibrary)

        XCTAssertThrowsError(try environment.service.confirmDraft(id: draft.id)) { error in
            XCTAssertEqual(error as? LibraryError, .nameRequired)
        }

        XCTAssertEqual(environment.service.drafts.map(\.id), [draft.id])
        XCTAssertTrue(environment.service.items.isEmpty)
    }

    func testCreateDraftCommitSuccessRefreshFailureDoesNotDuplicateDraft() throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let saveBaseline = saveGate.saveAttempts
        snapshotGate.failNextReloads(2)

        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Committed once"
        )

        guard case .savedButRefreshFailed = draft.outcome else {
            return XCTFail("Expected a committed-but-unrefreshed outcome")
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertEqual(environment.service.displayDrafts.map(\.id), [draft.id])
        XCTAssertNotNil(environment.service.refreshRecoveryState)
        XCTAssertEqual(
            try environment.container.mainContext.fetch(
                FetchDescriptor<CaptureDraftRecord>()
            ).map(\.id),
            [draft.id]
        )

        try environment.service.recoverSnapshot()
        XCTAssertEqual(environment.service.drafts.map(\.id), [draft.id])
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertNil(environment.service.refreshRecoveryState)
    }

    func testManualReloadCanFailWithoutRepeatingCommittedDraftWrite() throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let saveBaseline = saveGate.saveAttempts
        snapshotGate.failNextReloads(3)

        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Reload remains read-only"
        )
        guard case .savedButRefreshFailed = draft.outcome else {
            return XCTFail("Expected persistent refresh recovery")
        }

        XCTAssertThrowsError(try environment.service.recoverSnapshot()) { error in
            XCTAssertEqual(error as? InjectedFailure, .reload)
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertNotNil(environment.service.refreshRecoveryState)
        XCTAssertEqual(environment.service.displayDrafts.map(\.id), [draft.id])

        try environment.service.recoverSnapshot()
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertNil(environment.service.refreshRecoveryState)
        XCTAssertEqual(environment.service.displayDrafts.map(\.id), [draft.id])
    }

    func testCreateDraftRefreshRecoveryReturnsOriginalDraft() throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let saveBaseline = saveGate.saveAttempts
        let reloadBaseline = snapshotGate.loadAttempts
        snapshotGate.failNextReloads(1)

        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Recovered automatically"
        )

        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertEqual(snapshotGate.loadAttempts, reloadBaseline + 2)
        XCTAssertEqual(environment.service.drafts.map(\.id), [draft.id])
        XCTAssertEqual(environment.service.lastCommitOutcome, .savedAndReloaded)
        XCTAssertNil(environment.service.refreshRecoveryState)
    }

    func testConfirmationTransfersMediaAndIsIdempotent() async throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .photoLibrary,
            name: "Camera"
        )
        let asset = try await environment.service.addMediaData(
            Data("original-image-data".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        let originalURL = environment.service.originalURL(for: asset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))

        let item = try environment.service.confirmDraft(id: draft.id)
        XCTAssertTrue(environment.service.drafts.isEmpty)
        XCTAssertEqual(environment.service.items.map(\.id), [item.id])
        XCTAssertEqual(item.sourceDraftID, draft.id)

        let transferred = try XCTUnwrap(
            environment.service.mediaAssets.first(where: { $0.id == asset.id })
        )
        XCTAssertEqual(transferred.ownerKind, .item)
        XCTAssertEqual(transferred.ownerID, item.id)
        XCTAssertEqual(item.coverMediaID, asset.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))

        let retryResult = try environment.service.confirmDraft(id: draft.id)
        XCTAssertEqual(retryResult.id, item.id)
        XCTAssertEqual(environment.service.items.count, 1)
    }

    func testRemoveMediaPreflightFailureCannotLeakIntoLaterSave() async throws {
        var timestamp = Date(timeIntervalSince1970: 1_000)
        let preflightGate = MediaPreflightGate()
        let environment = try makeEnvironment(
            now: { timestamp },
            mediaPreflightGate: preflightGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Preflight removal"
        )
        let item = try environment.service.confirmDraft(id: draft.id)

        timestamp = Date(timeIntervalSince1970: 2_000)
        let first = try await environment.service.addMediaData(
            Data("first".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .item,
            ownerID: item.id
        )
        timestamp = Date(timeIntervalSince1970: 3_000)
        let second = try await environment.service.addMediaData(
            Data("second".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .item,
            ownerID: item.id
        )
        let originalOwner = try XCTUnwrap(
            environment.service.displayItems.first(where: { $0.id == item.id })
        )
        let originalFileURLs = [
            environment.service.originalURL(for: first),
            environment.service.originalURL(for: second)
        ]

        timestamp = Date(timeIntervalSince1970: 4_000)
        preflightGate.failNext = .removeAfterDependencyResolution
        do {
            _ = try await environment.service.removeMedia(id: first.id)
            XCTFail("Expected the last removeMedia preflight to fail")
        } catch {
            XCTAssertEqual(error as? InjectedFailure, .mediaPreflight)
        }

        XCTAssertEqual(
            Set(environment.service.displayMedia.map(\.id)),
            Set([first.id, second.id])
        )
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id }),
            originalOwner
        )
        XCTAssertEqual(
            Set(try environment.container.mainContext.fetch(
                FetchDescriptor<MediaAssetRecord>()
            ).map(\.id)),
            Set([first.id, second.id])
        )
        XCTAssertTrue(originalFileURLs.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })

        _ = try environment.service.createLocation(name: "Unrelated write")
        try environment.service.reload()

        XCTAssertEqual(
            Set(environment.service.displayMedia.map(\.id)),
            Set([first.id, second.id])
        )
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id }),
            originalOwner
        )
        XCTAssertTrue(originalFileURLs.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func testInsertMediaPreflightFailureCleansPreparedFilesAndCannotLeak() async throws {
        var timestamp = Date(timeIntervalSince1970: 1_000)
        let preflightGate = MediaPreflightGate()
        let environment = try makeEnvironment(
            now: { timestamp },
            mediaPreflightGate: preflightGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .camera)
        let originalOwner = try XCTUnwrap(environment.service.displayDrafts.first)
        preflightGate.mediaRoot = environment.mediaRoot

        timestamp = Date(timeIntervalSince1970: 2_000)
        preflightGate.failNext = .insertAfterFilePreparationAndDependencyResolution
        do {
            _ = try await environment.service.addMediaData(
                Data("prepared-file".utf8),
                contentTypeIdentifier: UTType.jpeg.identifier,
                ownerKind: .draft,
                ownerID: draft.id
            )
            XCTFail("Expected the post-import media preflight to fail")
        } catch {
            XCTAssertEqual(error as? InjectedFailure, .mediaPreflight)
        }

        let preparedFileName = try XCTUnwrap(preflightGate.preparedFileNames.first)
        XCTAssertTrue(environment.service.displayMedia.isEmpty)
        XCTAssertEqual(environment.service.displayDrafts.first, originalOwner)
        XCTAssertTrue(
            try environment.container.mainContext.fetch(
                FetchDescriptor<MediaAssetRecord>()
            ).isEmpty
        )
        XCTAssertEqual(try mediaFileNames(at: environment.mediaRoot), [])

        let recreatedURL = environment.mediaRoot.appendingPathComponent(preparedFileName)
        try Data("reservation-check".utf8).write(to: recreatedURL)
        let reservationCheck = await environment.service.cleanupOrphanedMediaFiles()
        XCTAssertTrue(reservationCheck.removedFileNames.contains(preparedFileName))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recreatedURL.path))

        _ = try environment.service.createLocation(name: "Later write")
        try environment.service.reload()
        XCTAssertTrue(environment.service.displayMedia.isEmpty)
        XCTAssertEqual(environment.service.displayDrafts.first, originalOwner)
        XCTAssertTrue(
            try environment.container.mainContext.fetch(
                FetchDescriptor<MediaAssetRecord>()
            ).isEmpty
        )
    }

    func testMediaSaveFailureRollsBackOwnerPreparedFilesAndLaterSave() async throws {
        var timestamp = Date(timeIntervalSince1970: 1_000)
        let saveGate = SaveGate()
        let environment = try makeEnvironment(
            now: { timestamp },
            saveGate: saveGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .camera,
            name: "Save rollback"
        )
        let item = try environment.service.confirmDraft(id: draft.id)
        let originalOwner = try XCTUnwrap(environment.service.displayItems.first)

        timestamp = Date(timeIntervalSince1970: 2_000)
        saveGate.failNextSave = true
        do {
            _ = try await environment.service.addMediaData(
                Data("prepared-file".utf8),
                contentTypeIdentifier: UTType.jpeg.identifier,
                ownerKind: .item,
                ownerID: item.id
            )
            XCTFail("Expected the injected save failure")
        } catch {
            XCTAssertEqual(error as? InjectedFailure, .save)
        }

        _ = try environment.service.createLocation(name: "Later save")
        try environment.service.reload()
        XCTAssertTrue(environment.service.mediaAssets.isEmpty)
        XCTAssertEqual(
            environment.service.items.first(where: { $0.id == item.id }),
            originalOwner
        )
        XCTAssertNil(environment.service.items.first?.coverMediaID)
        XCTAssertTrue(
            try environment.container.mainContext.fetch(
                FetchDescriptor<MediaAssetRecord>()
            ).isEmpty
        )
        XCTAssertEqual(try mediaFileNames(at: environment.mediaRoot), [])
    }

    func testSaveSuccessReloadFailureKeepsCommittedMediaAndReopens() async throws {
        var timestamp = Date(timeIntervalSince1970: 1_000)
        let baseURL = temporaryDirectory(prefix: "ReloadBoundary")
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let storeURL = baseURL.appendingPathComponent("HouseholdOS.store")
        let mediaRoot = baseURL.appendingPathComponent("Media", isDirectory: true)
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()

        var firstContainer: ModelContainer? = try PersistenceController.makeContainer(
            storeURL: storeURL
        )
        var firstService: ItemLibraryService? = ItemLibraryService(
            context: try XCTUnwrap(firstContainer).mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot),
            now: { timestamp },
            contextSave: { context in
                _ = saveGate.consumeFailure()
                try context.save()
            },
            snapshotLoader: snapshotGate.load
        )
        try firstService?.bootstrap()
        let draft = try XCTUnwrap(
            firstService?.createDraft(source: .manual, name: "Reload boundary")
        )
        let item = try XCTUnwrap(firstService?.confirmDraft(id: draft.id))
        let saveBaseline = saveGate.saveAttempts
        timestamp = Date(timeIntervalSince1970: 2_000)
        snapshotGate.failNextReloads(2)

        let asset = try await XCTUnwrap(firstService).addMediaData(
            Data("committed".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .item,
            ownerID: item.id
        )
        let assetID = asset.id
        let assetURL = try XCTUnwrap(firstService).originalURL(for: asset)
        guard case .savedButRefreshFailed = firstService?.lastCommitOutcome else {
            return XCTFail("Expected an explicit saved-but-refresh-failed outcome")
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertEqual(firstService?.displayMedia.map(\.id), [assetID])
        XCTAssertEqual(firstService?.displayItems.first?.coverMediaID, assetID)
        XCTAssertEqual(firstService?.displayItems.first?.updatedAt, timestamp)
        XCTAssertEqual(
            try firstContainer?.mainContext.fetch(
                FetchDescriptor<MediaAssetRecord>()
            ).map(\.id),
            [assetID]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path))

        try firstService?.recoverSnapshot()
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertEqual(firstService?.displayMedia.map(\.id), [assetID])

        firstService = nil
        firstContainer = nil
        let reopenedContainer = try PersistenceController.makeContainer(
            storeURL: storeURL
        )
        let reopenedService = ItemLibraryService(
            context: reopenedContainer.mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot)
        )
        try reopenedService.bootstrap()

        XCTAssertEqual(reopenedService.mediaAssets.map(\.id), [assetID])
        XCTAssertEqual(reopenedService.items.first?.coverMediaID, assetID)
        XCTAssertEqual(reopenedService.items.first?.updatedAt, timestamp)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: reopenedService.originalURL(
                    for: try XCTUnwrap(reopenedService.mediaAssets.first)
                ).path
            )
        )
    }

    func testLocationAndMediaDeltasRemainTruthfulUntilReloadSucceeds() async throws {
        let snapshotGate = SnapshotGate()
        var timestamp = Date(timeIntervalSince1970: 100)
        let environment = try makeEnvironment(
            now: { timestamp },
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Overlay owner"
        )

        timestamp = Date(timeIntervalSince1970: 200)
        snapshotGate.failNextReloads(2)
        let location = try environment.service.createLocation(name: "Garage")
        guard case .savedButRefreshFailed = location.outcome else {
            return XCTFail("Expected committed Location overlay")
        }
        XCTAssertEqual(environment.service.displayLocations.map(\.id), [location.id])
        try environment.service.recoverSnapshot()

        timestamp = Date(timeIntervalSince1970: 300)
        snapshotGate.failNextReloads(2)
        let media = try await environment.service.addMediaData(
            Data("overlay-media".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        guard case .savedButRefreshFailed = media.outcome else {
            return XCTFail("Expected committed Media overlay")
        }
        XCTAssertEqual(environment.service.displayMedia.map(\.id), [media.id])
        XCTAssertEqual(
            environment.service.displayDrafts.first?.updatedAt,
            timestamp
        )
        try environment.service.recoverSnapshot()

        timestamp = Date(timeIntervalSince1970: 400)
        snapshotGate.failNextReloads(2)
        let removal = try await environment.service.removeMedia(id: media.id)
        guard case .savedButRefreshFailed = removal.outcome else {
            return XCTFail("Expected committed Media tombstone")
        }
        XCTAssertTrue(environment.service.displayMedia.isEmpty)
        try environment.service.recoverSnapshot()
        XCTAssertTrue(environment.service.displayMedia.isEmpty)
    }

    func testConfirmDraftRefreshFailureDoesNotCreateSecondItem() throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "One item"
        )
        let saveBaseline = saveGate.saveAttempts
        snapshotGate.failNextReloads(2)

        let item = try environment.service.confirmDraft(id: draft.id)
        guard case .savedButRefreshFailed = item.outcome else {
            return XCTFail("Expected an explicit saved-but-refresh-failed outcome")
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertTrue(environment.service.displayDrafts.isEmpty)
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.sourceDraftID,
            draft.id
        )
        XCTAssertTrue(
            try environment.container.mainContext.fetch(
                FetchDescriptor<CaptureDraftRecord>()
            ).isEmpty
        )
        XCTAssertEqual(
            try environment.container.mainContext.fetch(
                FetchDescriptor<ItemRecord>()
            ).map(\.id),
            [item.id]
        )

        try environment.service.recoverSnapshot()
        XCTAssertEqual(environment.service.items.map(\.id), [item.id])
        XCTAssertTrue(environment.service.drafts.isEmpty)
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
    }

    func testLatestCommittedUpsertWinsUntilSnapshotAbsorbsOverlay() throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Original"
        )
        let item = try environment.service.confirmDraft(id: draft.id)
        let saveBaseline = saveGate.saveAttempts
        snapshotGate.failNextReloads(6)

        let first = try environment.service.updateItem(
            id: item.id,
            name: "First committed",
            categoryID: nil,
            locationID: nil,
            note: nil
        )
        let second = try environment.service.updateItem(
            id: item.id,
            name: "Latest committed",
            categoryID: nil,
            locationID: nil,
            note: nil
        )
        let archived = try environment.service.setArchived(true, itemID: item.id)

        guard case .savedButRefreshFailed = first.outcome,
              case .savedButRefreshFailed = second.outcome,
              case .savedButRefreshFailed = archived.outcome else {
            return XCTFail("Expected all three commits to remain in the overlay")
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 3)
        XCTAssertEqual(environment.service.displayItems.count, 1)
        XCTAssertEqual(environment.service.displayItems.first?.name, "Latest committed")
        XCTAssertEqual(environment.service.displayItems.first?.status, .archived)

        try environment.service.recoverSnapshot()
        XCTAssertNil(environment.service.refreshRecoveryState)
        XCTAssertEqual(environment.service.displayItems.first?.name, "Latest committed")
        XCTAssertEqual(environment.service.displayItems.first?.status, .archived)
    }

    func testUpdateItemRefreshFailureDoesNotInviteSecondWrite() throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Before"
        )
        let item = try environment.service.confirmDraft(id: draft.id)
        let saveBaseline = saveGate.saveAttempts
        snapshotGate.failNextReloads(2)

        try environment.service.updateItem(
            id: item.id,
            name: "After",
            categoryID: nil,
            locationID: nil,
            note: nil
        )

        guard case .savedButRefreshFailed =
            environment.service.lastCommitOutcome else {
            return XCTFail("Expected a committed-but-unrefreshed outcome")
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.name,
            "After"
        )

        try environment.service.recoverSnapshot()
        XCTAssertEqual(environment.service.items.first?.name, "After")
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
    }

    func testArchiveRefreshFailurePreservesSingleCommittedTransition() throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Archive once"
        )
        let item = try environment.service.confirmDraft(id: draft.id)
        let saveBaseline = saveGate.saveAttempts
        snapshotGate.failNextReloads(2)

        try environment.service.setArchived(true, itemID: item.id)

        guard case .savedButRefreshFailed =
            environment.service.lastCommitOutcome else {
            return XCTFail("Expected a committed-but-unrefreshed outcome")
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.status,
            .archived
        )

        try environment.service.recoverSnapshot()
        XCTAssertEqual(environment.service.items.count, 1)
        XCTAssertEqual(environment.service.items.first?.status, .archived)
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)

        snapshotGate.failNextReloads(2)
        let restored = try environment.service.setArchived(false, itemID: item.id)
        guard case .savedButRefreshFailed = restored.outcome else {
            return XCTFail("Expected committed restore overlay")
        }
        XCTAssertEqual(environment.service.displayItems.first?.status, .active)
        try environment.service.recoverSnapshot()
        XCTAssertEqual(environment.service.displayItems.first?.status, .active)
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 2)
    }

    func testRemoveMediaCleanupFailureKeepsCommittedDeleteTruthfulAndRetryable() async throws {
        let snapshotGate = SnapshotGate()
        let removal = RemovalController()
        let environment = try makeEnvironment(
            snapshotGate: snapshotGate,
            removal: removal
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .manual)
        let asset = try await environment.service.addMediaData(
            Data("residual-file".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        let originalURL = environment.service.originalURL(for: asset)
        removal.failFileNames = [asset.originalFileName]
        snapshotGate.failNextReloads(2)

        let result = try await environment.service.removeMedia(id: asset.id)

        guard case .savedButRefreshFailed = result.outcome else {
            return XCTFail("Expected committed media tombstone during refresh failure")
        }
        XCTAssertTrue(environment.service.displayMedia.isEmpty)
        XCTAssertTrue(
            try environment.container.mainContext.fetch(
                FetchDescriptor<MediaAssetRecord>()
            ).isEmpty
        )
        XCTAssertEqual(result.value.failures.map(\.fileName), [asset.originalFileName])
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))

        try environment.service.recoverSnapshot()
        XCTAssertTrue(environment.service.displayMedia.isEmpty)
        removal.failFileNames = []
        let retry = await environment.service.cleanupOrphanedMediaFiles()
        XCTAssertTrue(retry.removedFileNames.contains(asset.originalFileName))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }

    func testDraftDeleteCleanupFailureReturnsObservablePartialCompletion() async throws {
        let removal = RemovalController()
        let environment = try makeEnvironment(removal: removal)
        defer { environment.removeFiles() }

        let draft = try environment.service.createDraft(source: .camera)
        let draftAsset = try await environment.service.addMediaData(
            Data("draft-photo".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        removal.failFileNames = [draftAsset.originalFileName]
        let draftDelete = try await environment.service.deleteDraft(id: draft.id)
        XCTAssertFalse(draftDelete.isComplete)
        XCTAssertTrue(environment.service.drafts.isEmpty)
        XCTAssertTrue(environment.service.mediaAssets.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: environment.service.originalURL(for: draftAsset).path
            )
        )
        let notice = try XCTUnwrap(
            MediaDeletionNotice.make(
                kind: .draft,
                recordID: draft.id,
                result: draftDelete.value
            )
        )
        XCTAssertEqual(notice.title, String(localized: "Draft record deleted"))
        XCTAssertEqual(
            notice.message,
            String(
                localized: "The draft record was deleted, but some local photo files could not be removed. HouseholdOS will retry during later maintenance or the next launch. There is no manual maintenance control at this time."
            )
        )
        XCTAssertFalse(notice.message.localizedCaseInsensitiveContains("delete failed"))

        removal.failFileNames = []
        let draftRetry = await environment.service.cleanupOrphanedMediaFiles()
        XCTAssertTrue(draftRetry.isComplete)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: environment.service.originalURL(for: draftAsset).path
            )
        )
    }

    func testItemDeleteCleanupFailureReturnsObservablePartialCompletion() async throws {
        let removal = RemovalController()
        let environment = try makeEnvironment(removal: removal)
        defer { environment.removeFiles() }
        let itemDraft = try environment.service.createDraft(
            source: .manual,
            name: "Item"
        )
        let item = try environment.service.confirmDraft(id: itemDraft.id)
        let itemAsset = try await environment.service.addMediaData(
            Data("item-photo".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .item,
            ownerID: item.id
        )
        removal.failFileNames = [itemAsset.originalFileName]
        let itemDelete = try await environment.service.deleteItem(id: item.id)
        XCTAssertFalse(itemDelete.isComplete)
        XCTAssertTrue(environment.service.items.isEmpty)
        XCTAssertTrue(environment.service.mediaAssets.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: environment.service.originalURL(for: itemAsset).path
            )
        )
        let notice = try XCTUnwrap(
            MediaDeletionNotice.make(
                kind: .item,
                recordID: item.id,
                result: itemDelete.value
            )
        )
        XCTAssertEqual(notice.title, String(localized: "Item record deleted"))
        XCTAssertEqual(
            notice.message,
            String(
                localized: "The item record was deleted, but some local photo files could not be removed. HouseholdOS will retry during later maintenance or the next launch. There is no manual maintenance control at this time."
            )
        )
        XCTAssertFalse(notice.message.localizedCaseInsensitiveContains("delete failed"))

        removal.failFileNames = []
        let itemRetry = await environment.service.cleanupOrphanedMediaFiles()
        XCTAssertTrue(itemRetry.isComplete)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: environment.service.originalURL(for: itemAsset).path
            )
        )
    }

    func testCombinedDeleteFailureKeepsRecoveryAndTransientNoticeIndependent() async throws {
        let saveGate = SaveGate()
        let snapshotGate = SnapshotGate()
        let removal = RemovalController()
        let environment = try makeEnvironment(
            saveGate: saveGate,
            snapshotGate: snapshotGate,
            removal: removal
        )
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Combined failure"
        )
        let asset = try await environment.service.addMediaData(
            Data("combined".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        removal.failFileNames = [asset.originalFileName]
        let saveBaseline = saveGate.saveAttempts
        snapshotGate.failNextReloads(2)

        let deletion = try await environment.service.deleteDraft(id: draft.id)
        guard case .savedButRefreshFailed = deletion.outcome else {
            return XCTFail("Expected committed delete with persistent refresh recovery")
        }
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)
        XCTAssertTrue(environment.service.displayDrafts.isEmpty)
        XCTAssertTrue(environment.service.displayMedia.isEmpty)
        XCTAssertNotNil(environment.service.refreshRecoveryState)
        XCTAssertTrue(
            try environment.container.mainContext.fetch(
                FetchDescriptor<CaptureDraftRecord>()
            ).isEmpty
        )
        XCTAssertTrue(
            try environment.container.mainContext.fetch(
                FetchDescriptor<MediaAssetRecord>()
            ).isEmpty
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: environment.service.originalURL(for: asset).path
            )
        )

        var queue = TransientNoticeQueue()
        queue.enqueue(
            try XCTUnwrap(
                MediaDeletionNotice.make(
                    kind: .draft,
                    recordID: draft.id,
                    result: deletion.value
                )
            )
        )
        XCTAssertNotNil(queue.active)
        queue.dismissActive()
        XCTAssertNil(queue.active)
        XCTAssertNotNil(environment.service.refreshRecoveryState)
        queue.enqueue(
            try XCTUnwrap(
                MediaDeletionNotice.make(
                    kind: .draft,
                    recordID: draft.id,
                    result: deletion.value
                )
            )
        )

        try environment.service.recoverSnapshot()
        XCTAssertNil(environment.service.refreshRecoveryState)
        XCTAssertNotNil(queue.active)
        XCTAssertEqual(saveGate.saveAttempts, saveBaseline + 1)

        removal.failFileNames = []
        let maintenance = await environment.service.cleanupOrphanedMediaFiles()
        XCTAssertTrue(maintenance.isComplete)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: environment.service.originalURL(for: asset).path
            )
        )
    }

    func testTransientNoticeQueuePromotesFIFOAndDeduplicatesSemantically() {
        let firstID = UUID()
        let secondID = UUID()
        let first = TransientNotice(
            id: .recordDeletion(.draft, firstID),
            title: "First",
            message: "First message"
        )
        let second = TransientNotice(
            id: .mediaRemoval(secondID),
            title: "Second",
            message: "Second message"
        )
        var queue = TransientNoticeQueue()

        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(first)

        XCTAssertEqual(queue.active, first)
        XCTAssertEqual(queue.pending, [second])
        queue.dismissActive()
        XCTAssertEqual(queue.active, second)
        XCTAssertTrue(queue.pending.isEmpty)
        queue.dismissActive()
        XCTAssertNil(queue.active)
    }

    func testCompleteOwnerDeletionDoesNotCreateResidualFileNotice() async throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .manual)
        let draftResult = try await environment.service.deleteDraft(id: draft.id)
        XCTAssertTrue(draftResult.isComplete)
        XCTAssertNil(
            MediaDeletionNotice.make(
                kind: .draft,
                recordID: draft.id,
                result: draftResult.value
            )
        )

        let itemDraft = try environment.service.createDraft(
            source: .manual,
            name: "Complete deletion"
        )
        let item = try environment.service.confirmDraft(id: itemDraft.id)
        let itemResult = try await environment.service.deleteItem(id: item.id)
        XCTAssertTrue(itemResult.isComplete)
        XCTAssertNil(
            MediaDeletionNotice.make(
                kind: .item,
                recordID: item.id,
                result: itemResult.value
            )
        )
    }

    func testCleanupIsolatesFailuresPreservesKnownFilesAndRemovesIncoming() async throws {
        let removal = RemovalController()
        let environment = try makeEnvironment(removal: removal)
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .manual)
        let knownAsset = try await environment.service.addMediaData(
            Data("known".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        let knownURL = environment.service.originalURL(for: knownAsset)
        let blockedURL = environment.mediaRoot.appendingPathComponent("blocked.jpg")
        let removableURL = environment.mediaRoot.appendingPathComponent("orphan.jpg")
        let incomingURL = environment.mediaRoot.appendingPathComponent(".incoming-stale")
        try Data("blocked".utf8).write(to: blockedURL)
        try Data("orphan".utf8).write(to: removableURL)
        try Data("incoming".utf8).write(to: incomingURL)
        removal.failFileNames = ["blocked.jpg"]

        let result = await environment.service.cleanupOrphanedMediaFiles()

        XCTAssertEqual(result.failures.map(\.fileName), ["blocked.jpg"])
        XCTAssertEqual(
            Set(result.removedFileNames),
            Set(["orphan.jpg", ".incoming-stale"])
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: knownURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: blockedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removableURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: incomingURL.path))

        removal.failFileNames = []
        let retry = await environment.service.cleanupOrphanedMediaFiles()
        XCTAssertEqual(retry.removedFileNames, ["blocked.jpg"])
    }

    func testPreparedMediaIsReservedFromConcurrentOrphanCleanup() async throws {
        let baseURL = temporaryDirectory(prefix: "PreparedReservation")
        let mediaRoot = baseURL.appendingPathComponent("Media", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = try MediaFileStore(rootURL: mediaRoot)
        let storedFile = try await store.importData(
            Data("prepared".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            id: UUID()
        )

        let whilePrepared = await store.cleanupOrphans(keeping: [])
        XCTAssertTrue(whilePrepared.removedFileNames.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: store.url(for: storedFile.originalFileName).path
            )
        )

        await store.markPersisted(storedFile)
        let afterReservationReleased = await store.cleanupOrphans(keeping: [])
        XCTAssertEqual(
            afterReservationReleased.removedFileNames,
            [storedFile.originalFileName]
        )
    }

    func testStartupAvailabilityDoesNotDependOnMediaCleanup() async throws {
        let baseURL = temporaryDirectory(prefix: "StartupCleanup")
        let mediaRoot = baseURL.appendingPathComponent("Media", isDirectory: true)
        let removal = RemovalController()
        let store = try MediaFileStore(
            rootURL: mediaRoot,
            removeFile: removal.remove
        )
        let orphanURL = mediaRoot.appendingPathComponent("blocked.jpg")
        try Data("orphan".utf8).write(to: orphanURL)
        removal.failFileNames = ["blocked.jpg"]
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let container = try PersistenceController.makeContainer(inMemoryOnly: true)
        let service = ItemLibraryService(
            context: container.mainContext,
            mediaStore: store
        )
        XCTAssertNoThrow(try service.bootstrap())
        XCTAssertEqual(service.categories.count, DefaultCategoryDefinition.all.count)

        await service.performStartupMediaMaintenance()
        XCTAssertEqual(
            service.lastMediaMaintenanceResult.failures.map(\.fileName),
            ["blocked.jpg"]
        )
        XCTAssertEqual(service.categories.count, DefaultCategoryDefinition.all.count)
    }

    func testEveryMediaMutationUpdatesOwnerTimestampIncludingCoverChanges() async throws {
        var timestamp = Date(timeIntervalSince1970: 100)
        let environment = try makeEnvironment(now: { timestamp })
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .manual)

        timestamp = Date(timeIntervalSince1970: 200)
        let draftFirst = try await environment.service.addMediaData(
            Data("draft-first".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        XCTAssertEqual(
            environment.service.displayDrafts.first(where: { $0.id == draft.id })?.updatedAt,
            timestamp
        )

        timestamp = Date(timeIntervalSince1970: 300)
        _ = try await environment.service.addMediaData(
            Data("draft-second".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        XCTAssertEqual(
            environment.service.displayDrafts.first(where: { $0.id == draft.id })?.updatedAt,
            timestamp
        )

        timestamp = Date(timeIntervalSince1970: 400)
        _ = try await environment.service.removeMedia(id: draftFirst.id)
        XCTAssertEqual(
            environment.service.displayDrafts.first(where: { $0.id == draft.id })?.updatedAt,
            timestamp
        )

        timestamp = Date(timeIntervalSince1970: 500)
        let itemDraft = try environment.service.createDraft(
            source: .manual,
            name: "Item"
        )
        let item = try environment.service.confirmDraft(id: itemDraft.id)

        timestamp = Date(timeIntervalSince1970: 600)
        let firstItemAsset = try await environment.service.addMediaData(
            Data("item-first".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .item,
            ownerID: item.id
        )
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.updatedAt,
            timestamp
        )

        timestamp = Date(timeIntervalSince1970: 700)
        let secondItemAsset = try await environment.service.addMediaData(
            Data("item-second".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .item,
            ownerID: item.id
        )
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.updatedAt,
            timestamp
        )

        timestamp = Date(timeIntervalSince1970: 800)
        _ = try await environment.service.removeMedia(id: secondItemAsset.id)
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.updatedAt,
            timestamp
        )
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.coverMediaID,
            firstItemAsset.id
        )

        timestamp = Date(timeIntervalSince1970: 900)
        _ = try await environment.service.removeMedia(id: firstItemAsset.id)
        XCTAssertEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.updatedAt,
            timestamp
        )
        XCTAssertNotEqual(
            environment.service.displayItems.first(where: { $0.id == item.id })?.coverMediaID,
            firstItemAsset.id
        )
    }

    func testMultipleLargeImageImportsAreUniqueOrderedAndOffMainThread() async throws {
        let operations = OperationRecorder()
        let environment = try makeEnvironment(operationRecorder: operations)
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .photoLibrary)
        let largeImage = UIGraphicsImageRenderer(
            size: CGSize(width: 4_032, height: 3_024)
        ).jpegData(withCompressionQuality: 0.88) { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4_032, height: 3_024))
        }

        let first = try await environment.service.addMediaData(
            largeImage,
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        let second = try await environment.service.addMediaData(
            largeImage,
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )

        XCTAssertNotEqual(first.originalFileName, second.originalFileName)
        XCTAssertEqual(first.ownerID, draft.id)
        XCTAssertEqual(second.ownerID, draft.id)
        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(second.sortOrder, 1)
        XCTAssertNotNil(first.thumbnailFileName)
        XCTAssertNotNil(second.thumbnailFileName)
        XCTAssertFalse(operations.observations.isEmpty)
        XCTAssertTrue(operations.observations.allSatisfy { !$0.ranOnMainThread })
    }

    func testImmediateMediaAndLocationPersistWhenItemFieldSaveIsRejected() async throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .manual,
            name: "Original"
        )
        let item = try environment.service.confirmDraft(id: draft.id)
        let location = try environment.service.createLocation(name: "Garage")
        let media = try await environment.service.addMediaData(
            Data("immediate".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .item,
            ownerID: item.id
        )

        XCTAssertThrowsError(
            try environment.service.updateItem(
                id: item.id,
                name: "  ",
                categoryID: nil,
                locationID: location.id,
                note: "unsaved"
            )
        ) { error in
            XCTAssertEqual(error as? LibraryError, .nameRequired)
        }
        try environment.service.reload()

        XCTAssertEqual(environment.service.items.first?.name, "Original")
        XCTAssertEqual(environment.service.locations.map(\.id), [location.id])
        XCTAssertEqual(environment.service.mediaAssets.map(\.id), [media.id])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: environment.service.originalURL(for: media).path
            )
        )
    }

    func testSearchCategoryLocationArchiveAndSorting() throws {
        var timestamp = Date(timeIntervalSince1970: 100)
        let environment = try makeEnvironment(now: { timestamp })
        defer { environment.removeFiles() }
        let office = try environment.service.createLocation(name: "Office")

        let firstDraft = try environment.service.createDraft(
            source: .manual,
            name: "Blue Camera",
            categoryID: DefaultCategoryDefinition.all[0].id,
            locationID: office.id,
            note: "Travel"
        )
        _ = try environment.service.confirmDraft(id: firstDraft.id)

        timestamp = Date(timeIntervalSince1970: 200)
        let secondDraft = try environment.service.createDraft(
            source: .manual,
            name: "Hammer",
            categoryID: DefaultCategoryDefinition.all[2].id
        )
        let hammer = try environment.service.confirmDraft(id: secondDraft.id)
        try environment.service.setArchived(true, itemID: hammer.id)

        XCTAssertEqual(
            environment.service.visibleItems(
                query: "office",
                categoryID: nil,
                includeArchived: false,
                sort: .newest
            ).map(\.name),
            ["Blue Camera"]
        )
        XCTAssertEqual(
            environment.service.visibleItems(
                query: try XCTUnwrap(
                    environment.service.categoryDisplayName(
                        for: DefaultCategoryDefinition.all[0].id
                    )
                ),
                categoryID: nil,
                includeArchived: false,
                sort: .newest
            ).map(\.name),
            ["Blue Camera"]
        )
        XCTAssertEqual(
            environment.service.visibleItems(
                query: "",
                categoryID: DefaultCategoryDefinition.all[2].id,
                includeArchived: true,
                sort: .name
            ).map(\.name),
            ["Hammer"]
        )
        XCTAssertEqual(
            environment.service.visibleItems(
                query: "",
                categoryID: nil,
                includeArchived: true,
                sort: .newest
            ).map(\.name),
            ["Hammer", "Blue Camera"]
        )
    }

    func testRound1DuplicateCaptureCompletionCreatesOneDraftAndOneMedia() async throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let gate = CaptureResultGate()
        gate.beginCapture()
        let jpegData = UIGraphicsImageRenderer(
            size: CGSize(width: 120, height: 160)
        ).jpegData(withCompressionQuality: 0.95) { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }

        for _ in 0 ..< 2 where gate.claimResult() {
            let draft = try environment.service.createDraft(source: .camera)
            _ = try await environment.service.addMediaData(
                jpegData,
                contentTypeIdentifier: UTType.jpeg.identifier,
                ownerKind: .draft,
                ownerID: draft.id
            )
        }

        XCTAssertEqual(environment.service.drafts.count, 1)
        XCTAssertEqual(environment.service.mediaAssets.count, 1)
        XCTAssertEqual(
            environment.service.mediaAssets.first?.ownerID,
            environment.service.drafts.first?.id
        )
    }

    func testRound1CaptureResultGateAcceptsOneResultPerCapture() {
        let gate = CaptureResultGate()

        gate.beginCapture()
        XCTAssertTrue(gate.claimResult())
        XCTAssertFalse(gate.claimResult())

        gate.beginCapture()
        XCTAssertTrue(gate.claimResult())
        XCTAssertFalse(gate.claimResult())
    }

    func testRound1SystemCategoryLocalizationPreservesIdentityAndCustomNames() {
        let householdID = UUID()
        let definition = DefaultCategoryDefinition.all[0]
        let systemCategory = CategoryValue(
            id: definition.id,
            householdID: householdID,
            name: definition.name,
            sortOrder: definition.sortOrder,
            isSystem: true
        )
        let customCategory = CategoryValue(
            id: UUID(),
            householdID: householdID,
            name: "工作室",
            sortOrder: 100,
            isSystem: false
        )

        XCTAssertEqual(
            SystemCategoryLocalization.displayName(for: systemCategory),
            String(localized: "Electronics", comment: "System category name")
        )
        XCTAssertEqual(
            SystemCategoryLocalization.displayName(for: customCategory),
            "工作室"
        )
        XCTAssertEqual(systemCategory.id, definition.id)
        XCTAssertEqual(systemCategory.name, definition.name)
    }

    func testRound1CapturedPhotoFileUsesJPEGBytesExtensionAndType() throws {
        let jpegData = UIGraphicsImageRenderer(
            size: CGSize(width: 80, height: 60)
        ).jpegData(withCompressionQuality: 1) { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        let pickedFile = try CapturedPhotoFile.writeJPEGData(jpegData)
        defer { try? FileManager.default.removeItem(at: pickedFile.temporaryURL) }

        XCTAssertEqual(pickedFile.temporaryURL.pathExtension, "jpg")
        XCTAssertEqual(pickedFile.contentTypeIdentifier, UTType.jpeg.identifier)
        let source = try XCTUnwrap(
            CGImageSourceCreateWithURL(pickedFile.temporaryURL as CFURL, nil)
        )
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)

        XCTAssertThrowsError(
            try CapturedPhotoFile.writeJPEGData(Data("not-jpeg".utf8))
        ) { error in
            guard case MediaPickerError.invalidCameraData = error else {
                XCTFail("Expected invalid camera JPEG data")
                return
            }
        }
    }

    func testRound1DraftItemAndPhotoDeletionPersistAcrossReopen() async throws {
        let baseURL = temporaryDirectory(prefix: "Round1Reopen")
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let storeURL = baseURL.appendingPathComponent("HouseholdOS.store")
        let mediaRoot = baseURL.appendingPathComponent("Media", isDirectory: true)
        let jpegData = UIGraphicsImageRenderer(
            size: CGSize(width: 180, height: 240)
        ).jpegData(withCompressionQuality: 0.95) { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 240))
        }

        var container: ModelContainer? = try PersistenceController.makeContainer(
            storeURL: storeURL
        )
        var service: ItemLibraryService? = ItemLibraryService(
            context: try XCTUnwrap(container).mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot)
        )
        try service?.bootstrap()
        let draft = try XCTUnwrap(
            service?.createDraft(source: .photoLibrary, name: "Round 1 Photo")
        )
        let optionalMedia = try await service?.addMediaData(
            jpegData,
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        let media = try XCTUnwrap(optionalMedia)
        let mediaID = media.id
        let originalURL = try XCTUnwrap(service?.originalURL(for: media))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        service = nil
        container = nil

        container = try PersistenceController.makeContainer(storeURL: storeURL)
        service = ItemLibraryService(
            context: try XCTUnwrap(container).mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot)
        )
        try service?.bootstrap()
        XCTAssertEqual(service?.drafts.map(\.id), [draft.id])
        XCTAssertEqual(service?.mediaAssets.first?.ownerKind, .draft)
        XCTAssertEqual(service?.mediaAssets.first?.ownerID, draft.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))

        let item = try XCTUnwrap(service?.confirmDraft(id: draft.id))
        let itemID = item.id
        service = nil
        container = nil

        container = try PersistenceController.makeContainer(storeURL: storeURL)
        service = ItemLibraryService(
            context: try XCTUnwrap(container).mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot)
        )
        try service?.bootstrap()
        XCTAssertTrue(service?.drafts.isEmpty == true)
        XCTAssertEqual(service?.items.map(\.id), [itemID])
        XCTAssertEqual(service?.mediaAssets.first?.ownerKind, .item)
        XCTAssertEqual(service?.mediaAssets.first?.ownerID, itemID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))

        _ = try await service?.removeMedia(id: mediaID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        service = nil
        container = nil

        let finalContainer = try PersistenceController.makeContainer(storeURL: storeURL)
        let finalService = ItemLibraryService(
            context: finalContainer.mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot)
        )
        try finalService.bootstrap()
        XCTAssertEqual(finalService.items.map(\.id), [itemID])
        XCTAssertTrue(finalService.mediaAssets.isEmpty)
        XCTAssertNil(finalService.items.first?.coverMediaID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }

    func testDataCanBeReadAfterContainerReopens() throws {
        let baseURL = temporaryDirectory(prefix: "Persistence")
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let storeURL = baseURL.appendingPathComponent("HouseholdOS.store")
        let mediaRoot = baseURL.appendingPathComponent("Media", isDirectory: true)

        var firstContainer: ModelContainer? = try PersistenceController.makeContainer(
            storeURL: storeURL
        )
        var firstService: ItemLibraryService? = ItemLibraryService(
            context: try XCTUnwrap(firstContainer).mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot)
        )
        try firstService?.bootstrap()
        let draft = try XCTUnwrap(
            firstService?.createDraft(source: .manual, name: "Persistent Item")
        )
        let item = try XCTUnwrap(firstService?.confirmDraft(id: draft.id))
        let itemID = item.id
        firstService = nil
        firstContainer = nil

        let reopenedContainer = try PersistenceController.makeContainer(storeURL: storeURL)
        let reopenedService = ItemLibraryService(
            context: reopenedContainer.mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot)
        )
        try reopenedService.bootstrap()

        XCTAssertEqual(reopenedService.items.map(\.id), [itemID])
        XCTAssertEqual(reopenedService.items.map(\.name), ["Persistent Item"])
        XCTAssertTrue(reopenedService.drafts.isEmpty)
    }

    private func makeEnvironment(
        now: @escaping () -> Date = Date.init,
        saveGate: SaveGate? = nil,
        snapshotGate: SnapshotGate? = nil,
        mediaPreflightGate: MediaPreflightGate? = nil,
        removal: RemovalController? = nil,
        operationRecorder: OperationRecorder? = nil
    ) throws -> TestEnvironment {
        let baseURL = temporaryDirectory(prefix: "Tests")
        let mediaRoot = baseURL.appendingPathComponent("Media", isDirectory: true)
        let container = try PersistenceController.makeContainer(inMemoryOnly: true)
        let service = ItemLibraryService(
            context: container.mainContext,
            mediaStore: try MediaFileStore(
                rootURL: mediaRoot,
                removeFile: removal?.remove ?? MediaFileStore.defaultTestRemoval,
                operationObserver: operationRecorder?.record
            ),
            now: now,
            contextSave: { context in
                if saveGate?.consumeFailure() == true {
                    throw InjectedFailure.save
                }
                try context.save()
            },
            snapshotLoader: { context in
                if snapshotGate?.consumeFailure() == true {
                    throw InjectedFailure.reload
                }
                return try LibrarySnapshot.load(from: context)
            },
            mediaMutationPreflightCheck: { point in
                try mediaPreflightGate?.check(point)
            }
        )
        try service.bootstrap()
        return TestEnvironment(
            baseURL: baseURL,
            mediaRoot: mediaRoot,
            container: container,
            service: service
        )
    }

    private func temporaryDirectory(prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "HouseholdOS-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func mediaFileNames(at rootURL: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(atPath: rootURL.path).sorted()
    }
}

private extension MediaFileStore {
    static func defaultTestRemoval(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

@MainActor
private final class SaveGate {
    var failNextSave = false
    private(set) var saveAttempts = 0

    func consumeFailure() -> Bool {
        saveAttempts += 1
        defer { failNextSave = false }
        return failNextSave
    }
}

@MainActor
private final class SnapshotGate {
    private var failuresRemaining = 0
    private(set) var loadAttempts = 0

    func failNextReloads(_ count: Int) {
        failuresRemaining = count
    }

    func consumeFailure() -> Bool {
        loadAttempts += 1
        guard failuresRemaining > 0 else {
            return false
        }
        failuresRemaining -= 1
        return true
    }

    func load(_ context: ModelContext) throws -> LibrarySnapshot {
        if consumeFailure() {
            throw InjectedFailure.reload
        }
        return try LibrarySnapshot.load(from: context)
    }
}

private enum InjectedFailure: LocalizedError, Equatable {
    case save
    case reload
    case mediaPreflight
    case remove

    var errorDescription: String? {
        switch self {
        case .save:
            "Injected database save failure"
        case .reload:
            "Injected snapshot reload failure"
        case .mediaPreflight:
            "Injected media mutation preflight failure"
        case .remove:
            "Injected media removal failure"
        }
    }
}

@MainActor
private final class MediaPreflightGate {
    var failNext: MediaMutationPreflightPoint?
    var mediaRoot: URL?
    private(set) var preparedFileNames: [String] = []

    func check(_ point: MediaMutationPreflightPoint) throws {
        guard failNext == point else { return }
        failNext = nil
        if let mediaRoot {
            preparedFileNames = try FileManager.default.contentsOfDirectory(
                atPath: mediaRoot.path
            ).sorted()
        }
        throw InjectedFailure.mediaPreflight
    }
}

private final class RemovalController: @unchecked Sendable {
    private let lock = NSLock()
    private var _failFileNames: Set<String> = []

    var failFileNames: Set<String> {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _failFileNames
        }
        set {
            lock.lock()
            _failFileNames = newValue
            lock.unlock()
        }
    }

    func remove(_ url: URL) throws {
        if failFileNames.contains(url.lastPathComponent) {
            throw InjectedFailure.remove
        }
        try FileManager.default.removeItem(at: url)
    }
}

private final class OperationRecorder: @unchecked Sendable {
    struct Observation: Sendable {
        let operation: MediaFileOperation
        let ranOnMainThread: Bool
    }

    private let lock = NSLock()
    private var _observations: [Observation] = []

    var observations: [Observation] {
        lock.lock()
        defer { lock.unlock() }
        return _observations
    }

    func record(_ operation: MediaFileOperation, _ ranOnMainThread: Bool) {
        lock.lock()
        _observations.append(
            Observation(
                operation: operation,
                ranOnMainThread: ranOnMainThread
            )
        )
        lock.unlock()
    }
}

@MainActor
private struct TestEnvironment {
    let baseURL: URL
    let mediaRoot: URL
    let container: ModelContainer
    let service: ItemLibraryService

    func removeFiles() {
        try? FileManager.default.removeItem(at: baseURL)
    }
}
