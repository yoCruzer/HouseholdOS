import Combine
import Foundation
import SwiftData

enum LibraryCommitOutcome: Equatable {
    case savedAndReloaded
    case savedButRefreshFailed(String)
}

@MainActor
struct LibrarySnapshot {
    let items: [ItemRecord]
    let drafts: [CaptureDraftRecord]
    let mediaAssets: [MediaAssetRecord]
    let categories: [CategoryRecord]
    let locations: [LocationRecord]

    static func load(from context: ModelContext) throws -> LibrarySnapshot {
        let items = try context.fetch(
            FetchDescriptor<ItemRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        let drafts = try context.fetch(
            FetchDescriptor<CaptureDraftRecord>(
                sortBy: [
                    SortDescriptor(\.orderingIndex),
                    SortDescriptor(\.createdAt, order: .reverse)
                ]
            )
        )
        let mediaAssets = try context.fetch(
            FetchDescriptor<MediaAssetRecord>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.createdAt)
                ]
            )
        )
        let categories = try context.fetch(
            FetchDescriptor<CategoryRecord>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.name)
                ]
            )
        )
        let locations = try context.fetch(
            FetchDescriptor<LocationRecord>(
                predicate: #Predicate { $0.archivedAt == nil },
                sortBy: [SortDescriptor(\.name)]
            )
        )
        return LibrarySnapshot(
            items: items,
            drafts: drafts,
            mediaAssets: mediaAssets,
            categories: categories,
            locations: locations
        )
    }
}

typealias LibraryContextSave = @MainActor (ModelContext) throws -> Void
typealias LibrarySnapshotLoader = @MainActor (ModelContext) throws -> LibrarySnapshot

@MainActor
final class ItemLibraryService: ObservableObject {
    @Published private(set) var items: [ItemRecord] = []
    @Published private(set) var drafts: [CaptureDraftRecord] = []
    @Published private(set) var mediaAssets: [MediaAssetRecord] = []
    @Published private(set) var categories: [CategoryRecord] = []
    @Published private(set) var locations: [LocationRecord] = []
    @Published private(set) var lastCommitOutcome: LibraryCommitOutcome = .savedAndReloaded
    @Published private(set) var lastMediaMaintenanceResult: MediaMaintenanceResult = .empty

    let mediaStore: MediaFileStore

    private let context: ModelContext
    private let now: () -> Date
    private let contextSave: LibraryContextSave
    private let snapshotLoader: LibrarySnapshotLoader

    init(
        context: ModelContext,
        mediaStore: MediaFileStore,
        now: @escaping () -> Date = Date.init,
        contextSave: @escaping LibraryContextSave = { try $0.save() },
        snapshotLoader: @escaping LibrarySnapshotLoader = {
            try LibrarySnapshot.load(from: $0)
        }
    ) {
        self.context = context
        self.mediaStore = mediaStore
        self.now = now
        self.contextSave = contextSave
        self.snapshotLoader = snapshotLoader
    }

    func bootstrap() throws {
        try seedDefaultCategories()
        try reload()
    }

    func reload() throws {
        let snapshot = try snapshotLoader(context)
        apply(snapshot)
        lastCommitOutcome = .savedAndReloaded
    }

    func performStartupMediaMaintenance() async {
        _ = await cleanupOrphanedMediaFiles()
    }

    @discardableResult
    func createDraft(
        source: CaptureSource,
        name: String = "",
        categoryID: UUID? = nil,
        locationID: UUID? = nil,
        note: String? = nil
    ) throws -> CaptureDraftRecord {
        let timestamp = now()
        let draft = CaptureDraftRecord(
            name: name,
            categoryID: categoryID,
            locationID: locationID,
            note: normalizedOptional(note),
            createdAt: timestamp,
            updatedAt: timestamp,
            captureSource: source,
            orderingIndex: try fetchDrafts().count
        )
        context.insert(draft)
        try saveAndReload()
        return draft
    }

    func updateDraft(
        id: UUID,
        name: String,
        categoryID: UUID?,
        locationID: UUID?,
        note: String?
    ) throws {
        let draft = try requireDraft(id: id)
        draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.categoryID = categoryID
        draft.locationID = locationID
        draft.note = normalizedOptional(note)
        draft.updatedAt = now()
        try saveAndReload()
    }

    @discardableResult
    func deleteDraft(id: UUID) async throws -> MediaMaintenanceResult {
        let draft = try requireDraft(id: id)
        let ownedMedia = try fetchMedia(ownerKind: .draft, ownerID: id)
        let ownedFiles = ownedMedia.map(storedFile)

        for asset in ownedMedia {
            context.delete(asset)
        }
        context.delete(draft)

        try saveAndReload()
        return await removeStoredFiles(ownedFiles)
    }

    @discardableResult
    func confirmDraft(id: UUID) throws -> ItemRecord {
        if let existingItem = try fetchItems().first(where: { $0.sourceDraftID == id }) {
            return existingItem
        }

        let draft = try requireDraft(id: id)
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LibraryError.nameRequired
        }

        let timestamp = now()
        let ownedMedia = try fetchMedia(ownerKind: .draft, ownerID: id)
        let item = ItemRecord(
            name: trimmedName,
            categoryID: draft.categoryID,
            locationID: draft.locationID,
            note: normalizedOptional(draft.note),
            createdAt: timestamp,
            updatedAt: timestamp,
            captureSource: draft.captureSource,
            sourceDraftID: draft.id,
            coverMediaID: ownedMedia.first?.id
        )

        context.insert(item)
        for asset in ownedMedia {
            asset.ownerKind = .item
            asset.ownerID = item.id
        }
        context.delete(draft)
        try saveAndReload()
        return item
    }

    func updateItem(
        id: UUID,
        name: String,
        categoryID: UUID?,
        locationID: UUID?,
        note: String?
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LibraryError.nameRequired
        }

        let item = try requireItem(id: id)
        item.name = trimmedName
        item.categoryID = categoryID
        item.locationID = locationID
        item.note = normalizedOptional(note)
        item.updatedAt = now()
        try saveAndReload()
    }

    func setArchived(_ archived: Bool, itemID: UUID) throws {
        let item = try requireItem(id: itemID)
        let timestamp = now()
        item.status = archived ? .archived : .active
        item.archivedAt = archived ? timestamp : nil
        item.updatedAt = timestamp
        try saveAndReload()
    }

    @discardableResult
    func deleteItem(id: UUID) async throws -> MediaMaintenanceResult {
        let item = try requireItem(id: id)
        let ownedMedia = try fetchMedia(ownerKind: .item, ownerID: id)
        let ownedFiles = ownedMedia.map(storedFile)

        for asset in ownedMedia {
            context.delete(asset)
        }
        context.delete(item)

        try saveAndReload()
        return await removeStoredFiles(ownedFiles)
    }

    @discardableResult
    func createLocation(name: String) throws -> LocationRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LibraryError.locationNameRequired
        }

        if let existing = try fetchLocations().first(where: {
            $0.archivedAt == nil
                && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            return existing
        }

        let timestamp = now()
        let location = LocationRecord(
            name: trimmedName,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(location)
        try saveAndReload()
        return location
    }

    @discardableResult
    func addMediaFile(
        at url: URL,
        contentTypeIdentifier: String,
        ownerKind: MediaOwnerKind,
        ownerID: UUID
    ) async throws -> MediaAssetRecord {
        try validateOwner(kind: ownerKind, id: ownerID)
        let id = UUID()
        let storedFile = try await mediaStore.importFile(
            at: url,
            contentTypeIdentifier: contentTypeIdentifier,
            id: id
        )
        return try await insertMedia(
            id: id,
            storedFile: storedFile,
            ownerKind: ownerKind,
            ownerID: ownerID
        )
    }

    @discardableResult
    func addMediaData(
        _ data: Data,
        contentTypeIdentifier: String,
        ownerKind: MediaOwnerKind,
        ownerID: UUID
    ) async throws -> MediaAssetRecord {
        try validateOwner(kind: ownerKind, id: ownerID)
        let id = UUID()
        let storedFile = try await mediaStore.importData(
            data,
            contentTypeIdentifier: contentTypeIdentifier,
            id: id
        )
        return try await insertMedia(
            id: id,
            storedFile: storedFile,
            ownerKind: ownerKind,
            ownerID: ownerID
        )
    }

    @discardableResult
    func removeMedia(id: UUID) async throws -> MediaMaintenanceResult {
        guard let asset = try fetchMediaAssets().first(where: { $0.id == id }) else {
            throw LibraryError.mediaNotFound
        }
        let files = storedFile(for: asset)
        let ownerKind = asset.ownerKind
        let ownerID = asset.ownerID
        context.delete(asset)

        let timestamp = now()
        switch ownerKind {
        case .draft:
            try requireDraft(id: ownerID).updatedAt = timestamp
        case .item:
            let item = try requireItem(id: ownerID)
            if item.coverMediaID == id {
                item.coverMediaID = try fetchMedia(ownerKind: .item, ownerID: ownerID)
                    .first(where: { $0.id != id })?
                    .id
            }
            item.updatedAt = timestamp
        }

        try saveAndReload()
        let result = await mediaStore.remove(files)
        lastMediaMaintenanceResult = result
        return result
    }

    func media(for ownerKind: MediaOwnerKind, ownerID: UUID) -> [MediaAssetRecord] {
        mediaAssets
            .filter { $0.ownerKind == ownerKind && $0.ownerID == ownerID }
            .sorted(by: mediaSort)
    }

    func visibleItems(
        query: String,
        categoryID: UUID?,
        includeArchived: Bool,
        sort: LibrarySort
    ) -> [ItemRecord] {
        LibrarySearch.filter(
            items,
            query: query,
            categoryID: categoryID,
            includeArchived: includeArchived,
            sort: sort,
            categoryName: categoryName,
            locationName: locationName
        )
    }

    func categoryName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })?.name
    }

    func locationName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return locations.first(where: { $0.id == id })?.name
    }

    func displayURL(for asset: MediaAssetRecord) -> URL {
        mediaStore.url(for: asset.thumbnailFileName ?? asset.originalFileName)
    }

    func originalURL(for asset: MediaAssetRecord) -> URL {
        mediaStore.url(for: asset.originalFileName)
    }

    @discardableResult
    func cleanupOrphanedMediaFiles() async -> MediaMaintenanceResult {
        let persistedMedia: [MediaAssetRecord]
        do {
            persistedMedia = try fetchMediaAssets()
        } catch {
            let result = MediaMaintenanceResult(
                failures: [
                    MediaMaintenanceFailure(
                        fileName: "<database-reference-scan>",
                        message: error.localizedDescription
                    )
                ]
            )
            lastMediaMaintenanceResult = result
            return result
        }

        var knownFileNames = Set(persistedMedia.map(\.originalFileName))
        knownFileNames.formUnion(persistedMedia.compactMap(\.thumbnailFileName))
        let result = await mediaStore.cleanupOrphans(keeping: knownFileNames)
        lastMediaMaintenanceResult = result
        return result
    }

    private func seedDefaultCategories() throws {
        let existing = try context.fetch(FetchDescriptor<CategoryRecord>())
        let existingIDs = Set(existing.map(\.id))
        var inserted = false

        for definition in DefaultCategoryDefinition.all
        where !existingIDs.contains(definition.id) {
            context.insert(
                CategoryRecord(
                    id: definition.id,
                    name: definition.name,
                    sortOrder: definition.sortOrder,
                    isSystem: true
                )
            )
            inserted = true
        }

        if inserted {
            do {
                try contextSave(context)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func insertMedia(
        id: UUID,
        storedFile: StoredMediaFile,
        ownerKind: MediaOwnerKind,
        ownerID: UUID
    ) async throws -> MediaAssetRecord {
        do {
            try validateOwner(kind: ownerKind, id: ownerID)
        } catch {
            lastMediaMaintenanceResult = await mediaStore.remove(storedFile)
            throw error
        }

        let timestamp = now()
        let ownedMedia = try fetchMedia(ownerKind: ownerKind, ownerID: ownerID)
        let asset = MediaAssetRecord(
            id: id,
            ownerKind: ownerKind,
            ownerID: ownerID,
            originalFileName: storedFile.originalFileName,
            thumbnailFileName: storedFile.thumbnailFileName,
            contentTypeIdentifier: storedFile.contentTypeIdentifier,
            createdAt: timestamp,
            sortOrder: ownedMedia.count
        )
        context.insert(asset)

        switch ownerKind {
        case .draft:
            try requireDraft(id: ownerID).updatedAt = timestamp
        case .item:
            let item = try requireItem(id: ownerID)
            if item.coverMediaID == nil {
                item.coverMediaID = asset.id
            }
            item.updatedAt = timestamp
        }

        do {
            try saveAndReload()
            await mediaStore.markPersisted(storedFile)
            return asset
        } catch {
            let cleanupResult = await mediaStore.remove(storedFile)
            lastMediaMaintenanceResult = cleanupResult
            throw error
        }
    }

    private func validateOwner(kind: MediaOwnerKind, id: UUID) throws {
        switch kind {
        case .draft:
            _ = try requireDraft(id: id)
        case .item:
            _ = try requireItem(id: id)
        }
    }

    private func requireDraft(id: UUID) throws -> CaptureDraftRecord {
        guard let draft = try fetchDrafts().first(where: { $0.id == id }) else {
            throw LibraryError.draftNotFound
        }
        return draft
    }

    private func requireItem(id: UUID) throws -> ItemRecord {
        guard let item = try fetchItems().first(where: { $0.id == id }) else {
            throw LibraryError.itemNotFound
        }
        return item
    }

    private func fetchItems() throws -> [ItemRecord] {
        try context.fetch(FetchDescriptor<ItemRecord>())
    }

    private func fetchDrafts() throws -> [CaptureDraftRecord] {
        try context.fetch(FetchDescriptor<CaptureDraftRecord>())
    }

    private func fetchMediaAssets() throws -> [MediaAssetRecord] {
        try context.fetch(FetchDescriptor<MediaAssetRecord>())
    }

    private func fetchLocations() throws -> [LocationRecord] {
        try context.fetch(FetchDescriptor<LocationRecord>())
    }

    private func fetchMedia(
        ownerKind: MediaOwnerKind,
        ownerID: UUID
    ) throws -> [MediaAssetRecord] {
        try fetchMediaAssets()
            .filter { $0.ownerKind == ownerKind && $0.ownerID == ownerID }
            .sorted(by: mediaSort)
    }

    private func mediaSort(
        _ lhs: MediaAssetRecord,
        _ rhs: MediaAssetRecord
    ) -> Bool {
        lhs.sortOrder == rhs.sortOrder
            ? lhs.createdAt < rhs.createdAt
            : lhs.sortOrder < rhs.sortOrder
    }

    @discardableResult
    private func saveAndReload() throws -> LibraryCommitOutcome {
        do {
            try contextSave(context)
        } catch {
            context.rollback()
            throw error
        }

        do {
            try reload()
            return .savedAndReloaded
        } catch {
            let outcome = LibraryCommitOutcome.savedButRefreshFailed(
                error.localizedDescription
            )
            lastCommitOutcome = outcome
            return outcome
        }
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        items = snapshot.items
        drafts = snapshot.drafts
        mediaAssets = snapshot.mediaAssets
        categories = snapshot.categories
        locations = snapshot.locations
    }

    private func removeStoredFiles(
        _ storedFiles: [StoredMediaFile]
    ) async -> MediaMaintenanceResult {
        var combined = MediaMaintenanceResult()
        for storedFile in storedFiles {
            let result = await mediaStore.remove(storedFile)
            combined.removedFileNames.append(contentsOf: result.removedFileNames)
            combined.failures.append(contentsOf: result.failures)
        }
        lastMediaMaintenanceResult = combined
        return combined
    }

    private func storedFile(for asset: MediaAssetRecord) -> StoredMediaFile {
        StoredMediaFile(
            originalFileName: asset.originalFileName,
            thumbnailFileName: asset.thumbnailFileName,
            contentTypeIdentifier: asset.contentTypeIdentifier
        )
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
