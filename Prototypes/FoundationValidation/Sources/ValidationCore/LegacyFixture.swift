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

    public static func migrateClone(from source: URL, to target: URL) throws {
        guard !FileManager.default.fileExists(atPath: target.path) else { throw ValidationFailure.destinationExists }
        // Caller uses a terminated generator process: copy every store sidecar and media file.
        try FileManager.default.copyItem(at: source, to: target)
        try verifyCandidate(at: target)
    }

    public static func verifyCandidate(at root: URL) throws {
        let expected = try JSONDecoder().decode(FixtureSummary.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let container = try CandidateStore.open(root.appendingPathComponent("library.store"))
        guard try snapshot(container, root: root) == expected else { throw ValidationFailure.invariant("legacy snapshot changed") }
    }
}
