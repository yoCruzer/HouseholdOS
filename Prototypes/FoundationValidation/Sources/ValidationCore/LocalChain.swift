import Foundation
import SwiftData
import ImageIO

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
    public let libraryID: UUID
    public init(root: URL, libraryID requestedLibrary: UUID? = nil) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for dir in ["staging", "media", "journals"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        container = try CandidateStore.open(root.appendingPathComponent("library.store"))
        context = ModelContext(container); context.autosaveEnabled = false
        if let identity = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "localLibrary" }) {
            libraryID = try JSONDecoder().decode(UUID.self, from: identity.data)
            guard requestedLibrary == nil || requestedLibrary == libraryID else { throw ValidationFailure.invariant("cross-library merge requires plan") }
        } else {
            libraryID = requestedLibrary ?? UUID()
            context.insert(SyncCheckpoint(key: "localLibrary", data: try JSONEncoder().encode(libraryID)))
            try context.save()
        }
    }

    @discardableResult public func capture(_ bytes: Data, fault: LocalFault = .none, precision: String = "importedBytes", photoReference: String? = nil) throws -> UUID {
        let draftID = UUID(), mediaID = UUID()
        let journal = FileJournal(draftID: draftID, mediaID: mediaID, originalHash: MediaFiles.hash(bytes), originalName: "\(mediaID).original", previewName: "\(mediaID).preview.jpg")
        let journalURL = root.appendingPathComponent("journals/\(mediaID).json")
        try MediaFiles.write(JSONEncoder().encode(journal), to: journalURL)
        if fault == .originalWrite { throw fault }
        try MediaFiles.write(bytes, to: root.appendingPathComponent("staging/\(journal.originalName)"))
        if fault == .previewWrite { throw fault }
        guard let imageSource = CGImageSourceCreateWithData(bytes as CFData, nil), let type = CGImageSourceGetType(imageSource) as String?, ["public.jpeg", "public.heic"].contains(type) else {
            throw ValidationFailure.invariant("only static JPEG/HEIC is supported; prepared bytes retained")
        }
        let preview = try MediaFiles.preview(bytes)
        try MediaFiles.write(preview, to: root.appendingPathComponent("staging/\(journal.previewName)"))
        let date = Date()
        context.insert(CaptureDraftRecord(id: draftID, householdID: libraryID, name: "Synthetic capture", createdAt: date, updatedAt: date, captureSource: precision == "pickerDeliveredRepresentation" ? .photoLibrary : .camera))
        let profile = WardrobeProfile(ownerID: draftID, size: "M", material: "cotton")
        context.insert(profile)
        context.insert(MediaAssetRecord(id: mediaID, ownerKind: .draft, ownerID: draftID, originalFileName: journal.originalName, thumbnailFileName: journal.previewName, contentTypeIdentifier: type, createdAt: date, sortOrder: 0))
        let representation = MediaRepresentation(mediaID: mediaID, revision: 1, precision: precision, originalHash: journal.originalHash, relativePath: "media/\(journal.originalName)", photosReference: photoReference)
        context.insert(representation)
        let sync = try SyncCore.local(context: context, library: libraryID, root: root)
        try sync.stageWrite(WireRecord(id: draftID, operationID: UUID(), revision: 1, library: libraryID, kind: "draft", name: "Synthetic capture", profile: WireProfile(id: profile.id, size: profile.size, material: profile.material)))
        try sync.stageWrite(WireRecord(id: mediaID, operationID: UUID(), revision: 1, library: libraryID, kind: "media", parentID: draftID, media: WireMedia(representationID: representation.id, revision: 1, hash: journal.originalHash, precision: representation.precision, contentType: type, preview: preview)))
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
        guard journal.originalName == "\(journal.mediaID).original", journal.previewName == "\(journal.mediaID).preview.jpg",
              journal.originalHash.count == 64 else { throw ValidationFailure.invariant("unsafe file journal") }
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
        let sync = try SyncCore.local(context: context, library: libraryID, root: root)
        let profile = try context.fetch(FetchDescriptor<WardrobeProfile>()).first { $0.ownerID == draftID }
        try sync.stageWrite(WireRecord(id: item.id, operationID: UUID(), revision: 2, library: libraryID, kind: "item", name: item.name, category: item.categoryID?.uuidString, profile: profile.map { WireProfile(id: $0.id, size: $0.size, material: $0.material) }, sourceDraftID: draftID))
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
