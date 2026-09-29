import Foundation
import SwiftData
import CryptoKit

public enum ValidationFailure: Error { case destinationExists, invariant(String) }

public struct FixtureSummary: Codable, Equatable {
    public var items: [String]
    public var drafts: [String]
    public var media: [String]
    public var categories: [String]
    public var locations: [String]
}

@MainActor public enum LegacyFixture {
    public static func generate(at root: URL) throws -> FixtureSummary {
        guard !FileManager.default.fileExists(atPath: root.path) else { throw ValidationFailure.destinationExists }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try PersistenceController.makeContainer(storeURL: root.appendingPathComponent("library.store"))
        let c = ModelContext(container); c.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let location = LocationRecord(name: "Synthetic shelf", createdAt: date, updatedAt: date)
        c.insert(location)
        for category in DefaultCategoryDefinition.all {
            c.insert(CategoryRecord(id: category.id, name: category.name, sortOrder: category.sortOrder, isSystem: true))
        }
        let custom = CategoryRecord(id: UUID(), name: "Synthetic custom", sortOrder: 9, isSystem: false); c.insert(custom)
        let draft = CaptureDraftRecord(name: "Synthetic draft", categoryID: custom.id, locationID: location.id, note: "preserve draft", createdAt: date, updatedAt: date, captureSource: .photoLibrary)
        c.insert(draft)
        let item = ItemRecord(name: "Synthetic archive", categoryID: UUID(), locationID: location.id, note: "unknown category preserved", createdAt: date, updatedAt: date, captureSource: .camera, sourceDraftID: UUID(), status: .archived, archivedAt: date)
        c.insert(item)
        let active = ItemRecord(name: "Synthetic active", categoryID: DefaultCategoryDefinition.all[0].id, createdAt: date, updatedAt: date, captureSource: .manual); c.insert(active)
        for index in 0..<3 {
            let bytes = Data("HHOS-FAV-001 immutable synthetic legacy bytes \(index)".utf8)
            let filename = "legacy-\(index).bin"
            try bytes.write(to: root.appendingPathComponent(filename), options: .atomic)
            let media = MediaAssetRecord(ownerKind: index == 0 ? .draft : .item, ownerID: index == 0 ? draft.id : item.id, originalFileName: filename, thumbnailFileName: nil, contentTypeIdentifier: "public.data", createdAt: date, sortOrder: index)
            c.insert(media)
            if index == 1 { item.coverMediaID = media.id }
        }
        let deleted = CaptureDraftRecord(name: "deleted fixture", createdAt: date, updatedAt: date, captureSource: .manual)
        c.insert(deleted); try c.save(); c.delete(deleted); try c.save()
        let summary = try snapshot(container, root: root)
        try JSONEncoder().encode(summary).write(to: root.appendingPathComponent("expected.json"), options: .atomic)
        return summary
    }

    static func snapshot(_ container: ModelContainer, root: URL) throws -> FixtureSummary {
        let c = ModelContext(container)
        let items = try c.fetch(FetchDescriptor<ItemRecord>()).map { r in
            "\(r.id)|\(r.householdID)|\(r.name)|\(String(describing:r.categoryID))|\(String(describing:r.locationID))|\(r.note ?? "")|\(r.createdAt.timeIntervalSince1970)|\(r.updatedAt.timeIntervalSince1970)|\(r.captureSourceRaw)|\(String(describing:r.sourceDraftID))|\(r.statusRaw)|\(String(describing:r.archivedAt))|\(String(describing:r.coverMediaID))"
        }.sorted()
        let drafts = try c.fetch(FetchDescriptor<CaptureDraftRecord>()).map { r in
            "\(r.id)|\(r.householdID)|\(r.name)|\(String(describing:r.categoryID))|\(String(describing:r.locationID))|\(r.note ?? "")|\(r.createdAt.timeIntervalSince1970)|\(r.updatedAt.timeIntervalSince1970)|\(r.captureSourceRaw)|\(r.orderingIndex)"
        }.sorted()
        let media = try c.fetch(FetchDescriptor<MediaAssetRecord>()).map { r in
            let hash = SHA256.hash(data: try Data(contentsOf: root.appendingPathComponent(r.originalFileName))).map { String(format: "%02x", $0) }.joined()
            return "\(r.id)|\(r.ownerKindRaw)|\(r.ownerID)|\(r.originalFileName)|\(r.thumbnailFileName ?? "")|\(r.contentTypeIdentifier)|\(r.createdAt.timeIntervalSince1970)|\(r.sortOrder)|\(hash)"
        }.sorted()
        let categories = try c.fetch(FetchDescriptor<CategoryRecord>()).map { "\($0.id)|\($0.householdID)|\($0.name)|\($0.sortOrder)|\($0.isSystem)" }.sorted()
        let locations = try c.fetch(FetchDescriptor<LocationRecord>()).map { "\($0.id)|\($0.householdID)|\($0.name)|\($0.createdAt.timeIntervalSince1970)|\($0.updatedAt.timeIntervalSince1970)|\(String(describing:$0.archivedAt))" }.sorted()
        return FixtureSummary(items: items, drafts: drafts, media: media, categories: categories, locations: locations)
    }

    public static func migrateClone(from source: URL, to target: URL, checkpoint: ((String) -> Void)? = nil) throws {
        guard !FileManager.default.fileExists(atPath: target.path) else { throw ValidationFailure.destinationExists }
        // Caller uses a terminated generator process: copy every store sidecar and media file.
        try FileManager.default.copyItem(at: source, to: target)
        checkpoint?("cloneComplete")
        try verifyCandidate(at: target, checkpoint: checkpoint)
    }

    public static func verifyCandidate(at root: URL, checkpoint: ((String) -> Void)? = nil) throws {
        let expected = try JSONDecoder().decode(FixtureSummary.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let container = try CandidateStore.open(root.appendingPathComponent("library.store"))
        checkpoint?("candidateOpened")
        guard try snapshot(container, root: root) == expected else { throw ValidationFailure.invariant("legacy snapshot changed") }
    }
}

// A separate, newly generated fixture uses the unchanged V1 schema and real JPEG.
// Existing legacy fixtures and their source manifest remain immutable.
@MainActor extension LegacyFixture {
    public static func generateSyncFixture(at root: URL) throws {
        guard !FileManager.default.fileExists(atPath: root.path) else { throw ValidationFailure.destinationExists }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try PersistenceController.makeContainer(storeURL: root.appendingPathComponent("library.store"))
        let c = ModelContext(container); c.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = ItemRecord(name: "Legacy JPEG item", categoryID: UUID(), createdAt: date, updatedAt: date, captureSource: .camera)
        let media = MediaAssetRecord(ownerKind: .item, ownerID: item.id, originalFileName: "legacy-original.jpg", thumbnailFileName: nil, contentTypeIdentifier: "public.jpeg", createdAt: date, sortOrder: 0)
        item.coverMediaID = media.id
        try MediaFiles.syntheticJPEG().write(to: root.appendingPathComponent(media.originalFileName), options: .atomic)
        c.insert(item); c.insert(media); try c.save()
        try JSONEncoder().encode(snapshot(container, root: root)).write(to: root.appendingPathComponent("expected.json"), options: .atomic)
        try JSONEncoder().encode(UUID()).write(to: root.appendingPathComponent("legacy-source-id.json"), options: .atomic)
    }
}

struct LegacyBootstrapReceipt: Codable, Equatable {
    var sourceID: UUID
    var householdID: UUID
    var itemID: UUID
    var sourceDraftID: UUID?
    var libraryID: UUID
    var mediaIDs: [UUID]
    var operationIDs: [UUID]
}

@MainActor extension LocalChain {
    // Explicit admission only for named legacy Items. This prototype maps stable identity,
    // name/category/sourceDraftID and static JPEG media, not all production history/fields.
    public func bootstrapLegacy(sourceID: UUID, itemIDs: [UUID], failCommit: Bool = false) throws {
        let sync = try SyncCore.local(context: context, library: libraryID, root: root)
        do {
            for id in itemIDs {
                let key = "legacy-bootstrap/" + sourceID.uuidString + "/" + id.uuidString
                if let row = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == key }) {
                    let receipt = try JSONDecoder().decode(LegacyBootstrapReceipt.self, from: row.data)
                    guard receipt.libraryID == libraryID, receipt.itemID == id else { throw ValidationFailure.invariant("legacy mapping mismatch") }
                    continue
                }
                guard let item = try context.fetch(FetchDescriptor<ItemRecord>()).first(where: { $0.id == id }),
                      try sync.document(id) == nil else { throw ValidationFailure.invariant("legacy mapping requires an explicitly unmapped Item") }
                var operations: [UUID] = []
                let wire = WireRecord(id: item.id, operationID: UUID(), revision: 1, library: libraryID, kind: "item", name: item.name, category: item.categoryID?.uuidString, sourceDraftID: item.sourceDraftID)
                try sync.stageWrite(wire); operations.append(wire.operationID)
                let assets = try context.fetch(FetchDescriptor<MediaAssetRecord>()).filter { $0.ownerID == id && $0.ownerKind == .item }
                for asset in assets {
                    guard asset.contentTypeIdentifier == "public.jpeg" else { throw ValidationFailure.invariant("legacy bootstrap fixture supports static JPEG only") }
                    let original = try BackupRestore.safeURL(asset.originalFileName, in: root)
                    let bytes = try Data(contentsOf: original), preview = try MediaFiles.preview(bytes)
                    let representation = MediaRepresentation(mediaID: asset.id, revision: 1, precision: "importedBytes", originalHash: MediaFiles.hash(bytes), relativePath: asset.originalFileName)
                    context.insert(representation)
                    // Preserve the legacy original reference. Only add a derived recovery preview.
                    let previewName = representation.id.uuidString + ".preview.jpg"
                    try MediaFiles.write(preview, to: root.appendingPathComponent("media/" + previewName))
                    asset.thumbnailFileName = previewName
                    let media = WireRecord(id: asset.id, operationID: UUID(), revision: 1, library: libraryID, kind: "media", parentID: id,
                        media: WireMedia(representationID: representation.id, revision: 1, hash: representation.originalHash, precision: representation.precision, contentType: "public.jpeg", preview: preview))
                    try sync.stageWrite(media); operations.append(media.operationID)
                }
                let receipt = LegacyBootstrapReceipt(sourceID: sourceID, householdID: item.householdID, itemID: id, sourceDraftID: item.sourceDraftID, libraryID: libraryID, mediaIDs: assets.map(\.id), operationIDs: operations)
                context.insert(SyncCheckpoint(key: key, data: try JSONEncoder().encode(receipt)))
                sync.session.bootstrapComplete = false
            }
            sync.failNextCommit = failCommit
            try sync.saveSession() // Mapping, business sidecars and outbox commit together.
        } catch { context.rollback(); throw error }
    }
}

// CLI deterministic process evidence: substitutes service delivery only, using the
// same codec, durable apply, exact ACK and fetch barrier as the native adapter.
@MainActor extension LegacyFixture {
    public static func simulateDelivery(from source: URL, to target: URL, maximum: Int) throws -> [String: Any] {
        let chain = try LocalChain(root: source)
        let receiver = try LocalChain(root: target, libraryID: chain.libraryID)
        let sender = try SyncCore.local(context: chain.context, library: chain.libraryID, root: source)
        let inbound = try SyncCore.local(context: receiver.context, library: receiver.libraryID, root: target)
        try sender.setEnabled(true); try inbound.setEnabled(true)
        try sender.beginFetch(callback: sender.session.scope)
        guard try sender.nextBatch().isEmpty else { throw ValidationFailure.invariant("bootstrap barrier bypassed") }
        try sender.finishBootstrap(callback: sender.session.scope)
        let batch = try sender.nextBatch()
        for wire in batch.prefix(maximum) {
            let record = try CloudCodec.encode(wire, zone: .init(zoneName: sender.session.scope.zone))
            try inbound.apply(record, callback: inbound.session.scope)
            try sender.acknowledge(record, callback: sender.session.scope)
        }
        let items = try receiver.context.fetch(FetchDescriptor<ItemRecord>())
        return ["targetCounts": try receiver.counts(), "pending": try sender.pending().count,
                "ids": items.map { $0.id.uuidString }, "names": items.map(\.name), "barrier": "PASS", "evidence": "LOCAL_PLATFORM+LOGIC"]
    }
}
