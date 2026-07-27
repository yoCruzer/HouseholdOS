import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import HouseholdOSApp

@MainActor
final class Goal1CoreTests: XCTestCase {
    func testDraftCRUDAndTimestampUpdates() throws {
        var timestamp = Date(timeIntervalSince1970: 1_000)
        let environment = try makeEnvironment(now: { timestamp })
        defer { environment.removeFiles() }

        let draft = try environment.service.createDraft(source: .manual)
        XCTAssertEqual(environment.service.drafts.count, 1)
        XCTAssertEqual(draft.createdAt, timestamp)
        XCTAssertEqual(draft.updatedAt, timestamp)

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

        try environment.service.deleteDraft(id: draft.id)
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

    func testConfirmationTransfersMediaAndIsIdempotent() throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(
            source: .photoLibrary,
            name: "Camera"
        )
        let asset = try environment.service.addMediaData(
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

    func testItemUpdateArchiveRestoreAndPermanentDelete() throws {
        var timestamp = Date(timeIntervalSince1970: 10_000)
        let environment = try makeEnvironment(now: { timestamp })
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .manual, name: "Lamp")
        let item = try environment.service.confirmDraft(id: draft.id)

        timestamp = Date(timeIntervalSince1970: 20_000)
        try environment.service.updateItem(
            id: item.id,
            name: "Desk Lamp",
            categoryID: DefaultCategoryDefinition.all[3].id,
            locationID: nil,
            note: "Warm light"
        )
        XCTAssertEqual(item.name, "Desk Lamp")
        XCTAssertEqual(item.note, "Warm light")
        XCTAssertEqual(item.updatedAt, timestamp)

        timestamp = Date(timeIntervalSince1970: 30_000)
        try environment.service.setArchived(true, itemID: item.id)
        XCTAssertEqual(item.status, .archived)
        XCTAssertEqual(item.archivedAt, timestamp)
        XCTAssertTrue(
            environment.service.visibleItems(
                query: "",
                categoryID: nil,
                includeArchived: false,
                sort: .newest
            ).isEmpty
        )

        try environment.service.setArchived(false, itemID: item.id)
        XCTAssertEqual(item.status, .active)
        XCTAssertNil(item.archivedAt)

        try environment.service.deleteItem(id: item.id)
        XCTAssertTrue(environment.service.items.isEmpty)
    }

    func testDeletingOwnerRemovesMediaFilesAndRecords() throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .camera)
        let asset = try environment.service.addMediaData(
            Data("camera-data".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        let originalURL = environment.service.originalURL(for: asset)

        try environment.service.deleteDraft(id: draft.id)

        XCTAssertTrue(environment.service.mediaAssets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }

    func testOrphanedMediaIsCleanedWithoutRemovingKnownFiles() throws {
        let environment = try makeEnvironment()
        defer { environment.removeFiles() }
        let draft = try environment.service.createDraft(source: .manual)
        let asset = try environment.service.addMediaData(
            Data("known".utf8),
            contentTypeIdentifier: UTType.jpeg.identifier,
            ownerKind: .draft,
            ownerID: draft.id
        )
        let knownURL = environment.service.originalURL(for: asset)
        let orphanURL = environment.mediaRoot.appendingPathComponent("orphan.jpg")
        try Data("orphan".utf8).write(to: orphanURL)

        let removed = try environment.service.cleanupOrphanedMediaFiles()

        XCTAssertEqual(removed, ["orphan.jpg"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: knownURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
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
                query: "electronics",
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

    func testDataCanBeReadAfterContainerReopens() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HouseholdOS-Persistence-\(UUID().uuidString)", isDirectory: true)
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
        var firstService: ItemLibraryService? = try ItemLibraryService(
            context: try XCTUnwrap(firstContainer).mainContext,
            mediaStore: MediaFileStore(rootURL: mediaRoot)
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
        now: @escaping () -> Date = Date.init
    ) throws -> TestEnvironment {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HouseholdOS-Tests-\(UUID().uuidString)", isDirectory: true)
        let mediaRoot = baseURL.appendingPathComponent("Media", isDirectory: true)
        let container = try PersistenceController.makeContainer(inMemoryOnly: true)
        let service = ItemLibraryService(
            context: container.mainContext,
            mediaStore: try MediaFileStore(rootURL: mediaRoot),
            now: now
        )
        try service.bootstrap()
        return TestEnvironment(
            baseURL: baseURL,
            mediaRoot: mediaRoot,
            container: container,
            service: service
        )
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
