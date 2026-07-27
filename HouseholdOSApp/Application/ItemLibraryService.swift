import Combine
import Foundation
import SwiftData

@MainActor
final class ItemLibraryService: ObservableObject {
    @Published private(set) var items: [ItemRecord] = []
    @Published private(set) var drafts: [CaptureDraftRecord] = []
    @Published private(set) var mediaAssets: [MediaAssetRecord] = []
    @Published private(set) var categories: [CategoryRecord] = []
    @Published private(set) var locations: [LocationRecord] = []

    let mediaStore: MediaFileStore

    private let context: ModelContext
    private let now: () -> Date

    init(
        context: ModelContext,
        mediaStore: MediaFileStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.mediaStore = mediaStore
        self.now = now
    }

    func bootstrap() throws {
        try seedDefaultCategories()
        try reload()
        try cleanupOrphanedMediaFiles()
    }

    func reload() throws {
        items = try context.fetch(
            FetchDescriptor<ItemRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        drafts = try context.fetch(
            FetchDescriptor<CaptureDraftRecord>(
                sortBy: [
                    SortDescriptor(\.orderingIndex),
                    SortDescriptor(\.createdAt, order: .reverse)
                ]
            )
        )
        mediaAssets = try context.fetch(
            FetchDescriptor<MediaAssetRecord>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.createdAt)
                ]
            )
        )
        categories = try context.fetch(
            FetchDescriptor<CategoryRecord>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.name)
                ]
            )
        )
        locations = try context.fetch(
            FetchDescriptor<LocationRecord>(
                predicate: #Predicate { $0.archivedAt == nil },
                sortBy: [SortDescriptor(\.name)]
            )
        )
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
            orderingIndex: drafts.count
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

    func deleteDraft(id: UUID) throws {
        let draft = try requireDraft(id: id)
        let ownedMedia = media(for: .draft, ownerID: id)
        let ownedFiles = ownedMedia.map { storedFile(for: $0) }

        for asset in ownedMedia {
            context.delete(asset)
        }
        context.delete(draft)

        try saveAndReload()
        ownedFiles.forEach(mediaStore.remove)
    }

    @discardableResult
    func confirmDraft(id: UUID) throws -> ItemRecord {
        if let existingItem = items.first(where: { $0.sourceDraftID == id }) {
            return existingItem
        }

        let draft = try requireDraft(id: id)
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LibraryError.nameRequired
        }

        let timestamp = now()
        let ownedMedia = media(for: .draft, ownerID: id)
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

        do {
            try saveAndReload()
            return item
        } catch {
            context.rollback()
            try? reload()
            throw error
        }
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

    func deleteItem(id: UUID) throws {
        let item = try requireItem(id: id)
        let ownedMedia = media(for: .item, ownerID: id)
        let ownedFiles = ownedMedia.map { storedFile(for: $0) }

        for asset in ownedMedia {
            context.delete(asset)
        }
        context.delete(item)

        try saveAndReload()
        ownedFiles.forEach(mediaStore.remove)
    }

    @discardableResult
    func createLocation(name: String) throws -> LocationRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LibraryError.locationNameRequired
        }

        if let existing = locations.first(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
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
    ) throws -> MediaAssetRecord {
        try validateOwner(kind: ownerKind, id: ownerID)
        let id = UUID()
        let storedFile = try mediaStore.importFile(
            at: url,
            contentTypeIdentifier: contentTypeIdentifier,
            id: id
        )
        return try insertMedia(
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
    ) throws -> MediaAssetRecord {
        try validateOwner(kind: ownerKind, id: ownerID)
        let id = UUID()
        let storedFile = try mediaStore.importData(
            data,
            contentTypeIdentifier: contentTypeIdentifier,
            id: id
        )
        return try insertMedia(
            id: id,
            storedFile: storedFile,
            ownerKind: ownerKind,
            ownerID: ownerID
        )
    }

    func removeMedia(id: UUID) throws {
        guard let asset = mediaAssets.first(where: { $0.id == id }) else {
            throw LibraryError.mediaNotFound
        }
        let files = storedFile(for: asset)
        let ownerKind = asset.ownerKind
        let ownerID = asset.ownerID
        context.delete(asset)

        if ownerKind == .item,
           let item = items.first(where: { $0.id == ownerID }),
           item.coverMediaID == id {
            item.coverMediaID = media(for: .item, ownerID: ownerID)
                .first(where: { $0.id != id })?
                .id
            item.updatedAt = now()
        }

        try saveAndReload()
        mediaStore.remove(files)
    }

    func media(for ownerKind: MediaOwnerKind, ownerID: UUID) -> [MediaAssetRecord] {
        mediaAssets
            .filter { $0.ownerKind == ownerKind && $0.ownerID == ownerID }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.createdAt < $1.createdAt
                    : $0.sortOrder < $1.sortOrder
            }
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
    func cleanupOrphanedMediaFiles() throws -> [String] {
        var knownFileNames = Set(mediaAssets.map(\.originalFileName))
        knownFileNames.formUnion(mediaAssets.compactMap(\.thumbnailFileName))
        return try mediaStore.cleanupOrphans(keeping: knownFileNames)
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
            try context.save()
        }
    }

    private func insertMedia(
        id: UUID,
        storedFile: StoredMediaFile,
        ownerKind: MediaOwnerKind,
        ownerID: UUID
    ) throws -> MediaAssetRecord {
        let asset = MediaAssetRecord(
            id: id,
            ownerKind: ownerKind,
            ownerID: ownerID,
            originalFileName: storedFile.originalFileName,
            thumbnailFileName: storedFile.thumbnailFileName,
            contentTypeIdentifier: storedFile.contentTypeIdentifier,
            createdAt: now(),
            sortOrder: media(for: ownerKind, ownerID: ownerID).count
        )
        context.insert(asset)

        if ownerKind == .item,
           let item = items.first(where: { $0.id == ownerID }),
           item.coverMediaID == nil {
            item.coverMediaID = asset.id
            item.updatedAt = now()
        }

        do {
            try saveAndReload()
            return asset
        } catch {
            context.rollback()
            mediaStore.remove(storedFile)
            try? reload()
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
        guard let draft = drafts.first(where: { $0.id == id }) else {
            throw LibraryError.draftNotFound
        }
        return draft
    }

    private func requireItem(id: UUID) throws -> ItemRecord {
        guard let item = items.first(where: { $0.id == id }) else {
            throw LibraryError.itemNotFound
        }
        return item
    }

    private func saveAndReload() throws {
        do {
            try context.save()
            try reload()
        } catch {
            context.rollback()
            throw error
        }
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
