import Foundation
import SwiftData

public enum LocalFault: String, CaseIterable, Error {
    case none, originalWrite, previewWrite, beforeSave, afterSave, finalize, cleanup, refresh
}

struct FileJournal: Codable {
    var draftID: UUID
    var mediaID: UUID
    var originalHash: String
    var originalName: String
    var previewName: String
}

@MainActor public final class LocalChain {
    let root: URL
    let container: ModelContainer
    let context: ModelContext
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for dir in ["staging", "media", "journals"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        container = try CandidateStore.open(root.appendingPathComponent("library.store"))
        context = ModelContext(container); context.autosaveEnabled = false
    }

    @discardableResult public func capture(_ bytes: Data, fault: LocalFault = .none) throws -> UUID {
        let draftID = UUID(), mediaID = UUID()
        let journal = FileJournal(draftID: draftID, mediaID: mediaID, originalHash: MediaFiles.hash(bytes), originalName: "\(mediaID).original", previewName: "\(mediaID).preview.jpg")
        let journalURL = root.appendingPathComponent("journals/\(mediaID).json")
        try MediaFiles.write(JSONEncoder().encode(journal), to: journalURL)
        if fault == .originalWrite { throw fault }
        try MediaFiles.write(bytes, to: root.appendingPathComponent("staging/\(journal.originalName)"))
        if fault == .previewWrite { throw fault }
        try MediaFiles.write(MediaFiles.preview(bytes), to: root.appendingPathComponent("staging/\(journal.previewName)"))
        let date = Date()
        context.insert(CaptureDraftRecord(id: draftID, name: "Synthetic capture", createdAt: date, updatedAt: date, captureSource: .camera))
        context.insert(WardrobeProfile(ownerID: draftID, size: "M", material: "cotton"))
        context.insert(MediaAssetRecord(id: mediaID, ownerKind: .draft, ownerID: draftID, originalFileName: journal.originalName, thumbnailFileName: journal.previewName, contentTypeIdentifier: "public.jpeg", createdAt: date, sortOrder: 0))
        context.insert(MediaRepresentation(mediaID: mediaID, revision: 1, precision: "importedBytes", originalHash: journal.originalHash, relativePath: "media/\(journal.originalName)"))
        context.insert(DurableIntent(entityID: draftID, revision: 1, kind: "draft", payload: Data("Synthetic capture".utf8), scope: "unbound-local"))
        do {
            if fault == .beforeSave { throw fault }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        if fault == .afterSave || fault == .finalize { throw fault }
        try finalize(journal, journalURL: journalURL, fault: fault)
        // A refresh failure is a committed outcome and must not invite replay of capture.
        return draftID
    }

    func finalize(_ journal: FileJournal, journalURL: URL, fault: LocalFault = .none) throws {
        for name in [journal.originalName, journal.previewName] {
            let source = root.appendingPathComponent("staging/\(name)")
            let target = root.appendingPathComponent("media/\(name)")
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.moveItem(at: source, to: target)
            }
        }
        let original = try Data(contentsOf: root.appendingPathComponent("media/\(journal.originalName)"))
        guard MediaFiles.hash(original) == journal.originalHash else { throw ValidationFailure.invariant("finalize hash mismatch") }
        if fault == .cleanup { throw fault }
        try FileManager.default.removeItem(at: journalURL)
    }

    public func recover() throws {
        let referenced = Set(try context.fetch(FetchDescriptor<MediaAssetRecord>()).map(\.id))
        for url in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("journals"), includingPropertiesForKeys: nil) {
            let journal = try JSONDecoder().decode(FileJournal.self, from: Data(contentsOf: url))
            if referenced.contains(journal.mediaID) { try finalize(journal, journalURL: url) }
            // Uncommitted staging may be the only recoverable copy. Retain it and its journal.
        }
    }

    @discardableResult public func confirm(_ draftID: UUID) throws -> UUID {
        if let existing = try context.fetch(FetchDescriptor<ItemRecord>()).first(where: { $0.sourceDraftID == draftID }) { return existing.id }
        guard let draft = try context.fetch(FetchDescriptor<CaptureDraftRecord>()).first(where: { $0.id == draftID }) else {
            throw ValidationFailure.invariant("draft missing")
        }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationFailure.invariant("name required") }
        // Same Draft produces the same logical Item on independent clients; sourceDraftID remains traceable.
        let item = ItemRecord(id: draftID, householdID: draft.householdID, name: draft.name, categoryID: draft.categoryID, locationID: draft.locationID, note: draft.note, createdAt: draft.createdAt, updatedAt: .now, captureSource: draft.captureSource, sourceDraftID: draftID)
        context.insert(item)
        for media in try context.fetch(FetchDescriptor<MediaAssetRecord>()) where media.ownerID == draftID && media.ownerKind == .draft {
            media.ownerKind = .item
            if item.coverMediaID == nil { item.coverMediaID = media.id }
        }
        context.delete(draft)
        context.insert(DurableIntent(entityID: item.id, revision: 2, kind: "item", payload: Data(item.name.utf8), scope: "unbound-local"))
        do { try context.save() } catch { context.rollback(); throw error }
        return item.id
    }

    public func counts() throws -> [String: Int] {
        ["drafts": try context.fetchCount(FetchDescriptor<CaptureDraftRecord>()),
         "items": try context.fetchCount(FetchDescriptor<ItemRecord>()),
         "media": try context.fetchCount(FetchDescriptor<MediaAssetRecord>()),
         "profiles": try context.fetchCount(FetchDescriptor<WardrobeProfile>()),
         "outbox": try context.fetchCount(FetchDescriptor<DurableIntent>())]
    }
}
