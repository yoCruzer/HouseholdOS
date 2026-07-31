import Combine
import Foundation
import SwiftData

enum LibraryCommitOutcome: Equatable {
    case savedAndReloaded
    case savedButRefreshFailed(String)
}

struct LibraryRefreshRecoveryState: Equatable {
    let message: String
}

@MainActor
struct LibrarySnapshot {
    let items: [ItemValue]
    let drafts: [DraftValue]
    let mediaAssets: [MediaValue]
    let categories: [CategoryValue]
    let locations: [LocationValue]

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
            items: items.map(ItemValue.init),
            drafts: drafts.map(DraftValue.init),
            mediaAssets: mediaAssets.map(MediaValue.init),
            categories: categories.map(CategoryValue.init),
            locations: locations.map(LocationValue.init)
        )
    }
}

private struct CommittedDisplayDelta {
    var draftUpserts: [UUID: DraftValue] = [:]
    var draftTombstones: Set<UUID> = []
    var itemUpserts: [UUID: ItemValue] = [:]
    var itemTombstones: Set<UUID> = []
    var mediaUpserts: [UUID: MediaValue] = [:]
    var mediaTombstones: Set<UUID> = []
    var locationUpserts: [UUID: LocationValue] = [:]
}

typealias LibraryContextSave = @MainActor (ModelContext) throws -> Void
typealias LibrarySnapshotLoader = @MainActor (ModelContext) throws -> LibrarySnapshot

@MainActor
final class ItemLibraryService: ObservableObject {
    @Published private(set) var displayItems: [ItemValue] = []
    @Published private(set) var displayDrafts: [DraftValue] = []
    @Published private(set) var displayMedia: [MediaValue] = []
    @Published private(set) var displayCategories: [CategoryValue] = []
    @Published private(set) var displayLocations: [LocationValue] = []
    @Published private(set) var lastCommitOutcome: LibraryCommitOutcome = .savedAndReloaded
    @Published private(set) var refreshRecoveryState: LibraryRefreshRecoveryState?
    @Published private(set) var lastMediaMaintenanceResult: MediaMaintenanceResult = .empty

    var items: [ItemValue] { displayItems }
    var drafts: [DraftValue] { displayDrafts }
    var mediaAssets: [MediaValue] { displayMedia }
    var categories: [CategoryValue] { displayCategories }
    var locations: [LocationValue] { displayLocations }
    let mediaStore: MediaFileStore

    private let context: ModelContext
    private let now: () -> Date
    private let contextSave: LibraryContextSave
    private let snapshotLoader: LibrarySnapshotLoader
    private var snapshot = LibrarySnapshot(
        items: [],
        drafts: [],
        mediaAssets: [],
        categories: [],
        locations: []
    )
    private var committedDisplay = CommittedDisplayDelta()

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
        let loadedSnapshot = try snapshotLoader(context)
        apply(loadedSnapshot)
        lastCommitOutcome = .savedAndReloaded
        refreshRecoveryState = nil
    }

    func recoverSnapshot() throws {
        do {
            try reload()
        } catch {
            publishRefreshFailure(message: error.localizedDescription)
            throw error
        }
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
    ) throws -> LibraryWriteResult<DraftValue> {
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
        let value = DraftValue(draft)
        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(draftUpserts: [value.id: value])
        )
        return LibraryWriteResult(value: value, outcome: outcome)
    }

    @discardableResult
    func updateDraft(
        id: UUID,
        name: String,
        categoryID: UUID?,
        locationID: UUID?,
        note: String?
    ) throws -> LibraryWriteResult<Void> {
        let draft = try requireDraft(id: id)
        draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.categoryID = categoryID
        draft.locationID = locationID
        draft.note = normalizedOptional(note)
        draft.updatedAt = now()
        let value = DraftValue(draft)
        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(draftUpserts: [value.id: value])
        )
        return LibraryWriteResult(value: (), outcome: outcome)
    }

    @discardableResult
    func deleteDraft(id: UUID) async throws -> LibraryWriteResult<MediaMaintenanceResult> {
        let draft = try requireDraft(id: id)
        let ownedMedia = try fetchMedia(ownerKind: .draft, ownerID: id)
        let ownedFiles = ownedMedia.map(storedFile)

        for asset in ownedMedia {
            context.delete(asset)
        }
        context.delete(draft)

        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(
                draftTombstones: [id],
                mediaTombstones: Set(ownedMedia.map(\.id))
            )
        )
        let maintenance = await removeStoredFiles(ownedFiles)
        return LibraryWriteResult(value: maintenance, outcome: outcome)
    }

    @discardableResult
    func confirmDraft(id: UUID) throws -> LibraryWriteResult<ItemValue> {
        if let existingItem = try fetchItems().first(where: { $0.sourceDraftID == id }) {
            return LibraryWriteResult(
                value: ItemValue(existingItem),
                outcome: lastCommitOutcome
            )
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
        let itemValue = ItemValue(item)
        let mediaValues = ownedMedia.map(MediaValue.init)
        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(
                draftTombstones: [id],
                itemUpserts: [itemValue.id: itemValue],
                mediaUpserts: Dictionary(
                    uniqueKeysWithValues: mediaValues.map { ($0.id, $0) }
                )
            )
        )
        return LibraryWriteResult(value: itemValue, outcome: outcome)
    }

    @discardableResult
    func updateItem(
        id: UUID,
        name: String,
        categoryID: UUID?,
        locationID: UUID?,
        note: String?
    ) throws -> LibraryWriteResult<Void> {
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
        let value = ItemValue(item)
        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(itemUpserts: [value.id: value])
        )
        return LibraryWriteResult(value: (), outcome: outcome)
    }

    @discardableResult
    func setArchived(
        _ archived: Bool,
        itemID: UUID
    ) throws -> LibraryWriteResult<Void> {
        let item = try requireItem(id: itemID)
        let timestamp = now()
        item.status = archived ? .archived : .active
        item.archivedAt = archived ? timestamp : nil
        item.updatedAt = timestamp
        let value = ItemValue(item)
        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(itemUpserts: [value.id: value])
        )
        return LibraryWriteResult(value: (), outcome: outcome)
    }

    @discardableResult
    func deleteItem(id: UUID) async throws -> LibraryWriteResult<MediaMaintenanceResult> {
        let item = try requireItem(id: id)
        let ownedMedia = try fetchMedia(ownerKind: .item, ownerID: id)
        let ownedFiles = ownedMedia.map(storedFile)

        for asset in ownedMedia {
            context.delete(asset)
        }
        context.delete(item)

        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(
                itemTombstones: [id],
                mediaTombstones: Set(ownedMedia.map(\.id))
            )
        )
        let maintenance = await removeStoredFiles(ownedFiles)
        return LibraryWriteResult(value: maintenance, outcome: outcome)
    }

    @discardableResult
    func createLocation(name: String) throws -> LibraryWriteResult<LocationValue> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LibraryError.locationNameRequired
        }

        if let existing = try fetchLocations().first(where: {
            $0.archivedAt == nil
                && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            return LibraryWriteResult(
                value: LocationValue(existing),
                outcome: lastCommitOutcome
            )
        }

        let timestamp = now()
        let location = LocationRecord(
            name: trimmedName,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(location)
        let value = LocationValue(location)
        let outcome = try saveAndReload(
            delta: CommittedDisplayDelta(locationUpserts: [value.id: value])
        )
        return LibraryWriteResult(value: value, outcome: outcome)
    }

    @discardableResult
    func addMediaFile(
        at url: URL,
        contentTypeIdentifier: String,
        ownerKind: MediaOwnerKind,
        ownerID: UUID
    ) async throws -> LibraryWriteResult<MediaValue> {
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
    ) async throws -> LibraryWriteResult<MediaValue> {
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
    func removeMedia(id: UUID) async throws -> LibraryWriteResult<MediaMaintenanceResult> {
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

        let ownerValue: CommittedDisplayDelta
        switch ownerKind {
        case .draft:
            let draft = try requireDraft(id: ownerID)
            ownerValue = CommittedDisplayDelta(
                draftUpserts: [ownerID: DraftValue(draft)],
                mediaTombstones: [id]
            )
        case .item:
            let item = try requireItem(id: ownerID)
            ownerValue = CommittedDisplayDelta(
                itemUpserts: [ownerID: ItemValue(item)],
                mediaTombstones: [id]
            )
        }
        let outcome = try saveAndReload(delta: ownerValue)
        let result = await mediaStore.remove(files)
        lastMediaMaintenanceResult = result
        return LibraryWriteResult(value: result, outcome: outcome)
    }

    func media(for ownerKind: MediaOwnerKind, ownerID: UUID) -> [MediaValue] {
        displayMedia
            .filter { $0.ownerKind == ownerKind && $0.ownerID == ownerID }
            .sorted(by: mediaSort)
    }

    func visibleItems(
        query: String,
        categoryID: UUID?,
        includeArchived: Bool,
        sort: LibrarySort
    ) -> [ItemValue] {
        LibrarySearch.filter(
            displayItems,
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
        return displayCategories.first(where: { $0.id == id })?.name
    }

    func locationName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return displayLocations.first(where: { $0.id == id })?.name
    }

    func displayURL(for asset: MediaValue) -> URL {
        mediaStore.url(for: asset.thumbnailFileName ?? asset.originalFileName)
    }

    func displayURL(for result: LibraryWriteResult<MediaValue>) -> URL {
        displayURL(for: result.value)
    }

    func originalURL(for asset: MediaValue) -> URL {
        mediaStore.url(for: asset.originalFileName)
    }

    func originalURL(for result: LibraryWriteResult<MediaValue>) -> URL {
        originalURL(for: result.value)
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
    ) async throws -> LibraryWriteResult<MediaValue> {
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
            let mediaValue = MediaValue(asset)
            let delta: CommittedDisplayDelta
            switch ownerKind {
            case .draft:
                delta = CommittedDisplayDelta(
                    draftUpserts: [ownerID: DraftValue(try requireDraft(id: ownerID))],
                    mediaUpserts: [mediaValue.id: mediaValue]
                )
            case .item:
                delta = CommittedDisplayDelta(
                    itemUpserts: [ownerID: ItemValue(try requireItem(id: ownerID))],
                    mediaUpserts: [mediaValue.id: mediaValue]
                )
            }
            let outcome = try saveAndReload(delta: delta)
            await mediaStore.markPersisted(storedFile)
            return LibraryWriteResult(value: mediaValue, outcome: outcome)
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

    private func mediaSort(
        _ lhs: MediaValue,
        _ rhs: MediaValue
    ) -> Bool {
        lhs.sortOrder == rhs.sortOrder
            ? lhs.createdAt < rhs.createdAt
            : lhs.sortOrder < rhs.sortOrder
    }

    @discardableResult
    private func saveAndReload(
        delta: CommittedDisplayDelta
    ) throws -> LibraryCommitOutcome {
        do {
            try contextSave(context)
        } catch {
            context.rollback()
            throw error
        }

        applyCommitted(delta)

        var refreshError: Error?
        for _ in 0..<2 {
            do {
                try reload()
                return .savedAndReloaded
            } catch {
                refreshError = error
            }
        }

        let message = refreshError?.localizedDescription
            ?? "The saved library could not be refreshed."
        let outcome = LibraryCommitOutcome.savedButRefreshFailed(
            message
        )
        lastCommitOutcome = outcome
        publishRefreshFailure(message: message)
        return outcome
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        committedDisplay = CommittedDisplayDelta()
        publishDisplay()
        refreshRecoveryState = nil
    }

    private func publishRefreshFailure(message: String) {
        refreshRecoveryState = LibraryRefreshRecoveryState(message: message)
    }

    private func applyCommitted(_ delta: CommittedDisplayDelta) {
        committedDisplay.draftUpserts.merge(delta.draftUpserts) { _, latest in latest }
        committedDisplay.draftTombstones.formUnion(delta.draftTombstones)
        committedDisplay.itemUpserts.merge(delta.itemUpserts) { _, latest in latest }
        committedDisplay.itemTombstones.formUnion(delta.itemTombstones)
        committedDisplay.mediaUpserts.merge(delta.mediaUpserts) { _, latest in latest }
        committedDisplay.mediaTombstones.formUnion(delta.mediaTombstones)
        committedDisplay.locationUpserts.merge(delta.locationUpserts) { _, latest in latest }
        publishDisplay()
    }

    private func publishDisplay() {
        displayDrafts = mergedValues(
            base: snapshot.drafts,
            upserts: committedDisplay.draftUpserts,
            tombstones: committedDisplay.draftTombstones
        ) {
            $0.orderingIndex == $1.orderingIndex
                ? $0.createdAt > $1.createdAt
                : $0.orderingIndex < $1.orderingIndex
        }
        displayItems = mergedValues(
            base: snapshot.items,
            upserts: committedDisplay.itemUpserts,
            tombstones: committedDisplay.itemTombstones
        ) {
            $0.createdAt == $1.createdAt
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.createdAt > $1.createdAt
        }
        displayMedia = mergedValues(
            base: snapshot.mediaAssets,
            upserts: committedDisplay.mediaUpserts,
            tombstones: committedDisplay.mediaTombstones,
            sortedBy: mediaSort
        )
        displayLocations = mergedValues(
            base: snapshot.locations,
            upserts: committedDisplay.locationUpserts,
            tombstones: []
        ) {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        displayCategories = snapshot.categories
    }

    private func mergedValues<Value: Identifiable>(
        base: [Value],
        upserts: [UUID: Value],
        tombstones: Set<UUID>,
        sortedBy: (Value, Value) -> Bool
    ) -> [Value] where Value.ID == UUID {
        var values = Dictionary(
            uniqueKeysWithValues: base.map { ($0.id, $0) }
        )
        values.merge(upserts) { _, latest in latest }
        for id in tombstones {
            values.removeValue(forKey: id)
        }
        return values.values.sorted(by: sortedBy)
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

private extension DraftValue {
    init(_ record: CaptureDraftRecord) {
        self.init(
            id: record.id,
            householdID: record.householdID,
            name: record.name,
            categoryID: record.categoryID,
            locationID: record.locationID,
            note: record.note,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            captureSource: record.captureSource,
            orderingIndex: record.orderingIndex
        )
    }
}

private extension ItemValue {
    init(_ record: ItemRecord) {
        self.init(
            id: record.id,
            householdID: record.householdID,
            name: record.name,
            categoryID: record.categoryID,
            locationID: record.locationID,
            note: record.note,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            captureSource: record.captureSource,
            sourceDraftID: record.sourceDraftID,
            status: record.status,
            archivedAt: record.archivedAt,
            coverMediaID: record.coverMediaID
        )
    }
}

private extension MediaValue {
    init(_ record: MediaAssetRecord) {
        self.init(
            id: record.id,
            ownerKind: record.ownerKind,
            ownerID: record.ownerID,
            originalFileName: record.originalFileName,
            thumbnailFileName: record.thumbnailFileName,
            contentTypeIdentifier: record.contentTypeIdentifier,
            createdAt: record.createdAt,
            sortOrder: record.sortOrder
        )
    }
}

private extension LocationValue {
    init(_ record: LocationRecord) {
        self.init(
            id: record.id,
            householdID: record.householdID,
            name: record.name,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            archivedAt: record.archivedAt
        )
    }
}

private extension CategoryValue {
    init(_ record: CategoryRecord) {
        self.init(
            id: record.id,
            householdID: record.householdID,
            name: record.name,
            sortOrder: record.sortOrder,
            isSystem: record.isSystem
        )
    }
}
