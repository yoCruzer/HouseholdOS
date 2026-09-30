import Foundation
import SwiftData
import ImageIO

public enum LocalFault: String, CaseIterable, Error {
    case none, originalWrite, previewWrite, beforeSave, afterSave, finalize, cleanup, refresh
}

public enum CaptureOutcome { case notCommitted, saved, savedRefreshUnavailable, savedNeedsMediaRecovery }
struct CommittedCaptureError: LocalizedError {
    var draftID: UUID
    var errorDescription: String? { "Draft 已保存；媒体整理待恢复。请重开恢复，不要重复录入。" }
}

struct FileJournal: Codable {
    var draftID: UUID
    var mediaID: UUID
    var originalHash: String
    var originalName: String
    var previewName: String
    var profileID: UUID?
    var representationID: UUID?
    var draftOperationID: UUID?
    var mediaOperationID: UUID?
    var precision: String?
    var photoReference: String?
}

@MainActor public final class LocalChain {
    let root: URL
    let container: ModelContainer
    let context: ModelContext
    public let libraryID: UUID
    public private(set) var recoveryIssues: [String] = []
    public private(set) var lastCaptureOutcome: CaptureOutcome = .notCommitted
    public init(root: URL, libraryID requestedLibrary: UUID? = nil, allowsSave: Bool = true) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for dir in ["staging", "media", "journals"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        container = try CandidateStore.open(root.appendingPathComponent("library.store"), allowsSave: allowsSave)
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

    @discardableResult public func capture(_ bytes: Data, fault: LocalFault = .none, precision: String = "importedBytes", photoReference: String? = nil, checkpoint: ((String) -> Void)? = nil) throws -> UUID {
        lastCaptureOutcome = .notCommitted
        let draftID = UUID(), mediaID = UUID()
        let journal = FileJournal(draftID: draftID, mediaID: mediaID, originalHash: MediaFiles.hash(bytes), originalName: "\(mediaID).original", previewName: "\(mediaID).preview.jpg", profileID: UUID(), representationID: UUID(), draftOperationID: UUID(), mediaOperationID: UUID(), precision: precision, photoReference: photoReference)
        let journalURL = root.appendingPathComponent("journals/\(mediaID).json")
        try MediaFiles.write(JSONEncoder().encode(journal), to: journalURL)
        if fault == .originalWrite { throw fault }
        try MediaFiles.write(bytes, to: root.appendingPathComponent("staging/\(journal.originalName)"))
        checkpoint?("originalPrepared")
        if fault == .previewWrite { throw fault }
        guard let imageSource = CGImageSourceCreateWithData(bytes as CFData, nil), let type = CGImageSourceGetType(imageSource) as String?, ["public.jpeg", "public.heic"].contains(type) else {
            throw ValidationFailure.invariant("only static JPEG/HEIC is supported; prepared bytes retained")
        }
        let preview = try MediaFiles.preview(bytes)
        try MediaFiles.write(preview, to: root.appendingPathComponent("staging/\(journal.previewName)"))
        checkpoint?("prepared")
        try commitPrepared(journal, type: type, preview: preview, fault: fault)
        lastCaptureOutcome = .saved
        checkpoint?("committed")
        do {
            if fault == .afterSave || fault == .finalize { throw fault }
            try finalize(journal, journalURL: journalURL, fault: fault, checkpoint: checkpoint)
        } catch {
            lastCaptureOutcome = .savedNeedsMediaRecovery
            throw CommittedCaptureError(draftID: draftID)
        }
        if fault == .refresh { lastCaptureOutcome = .savedRefreshUnavailable }
        return draftID
    }

    private func commitPrepared(_ journal: FileJournal, type: String, preview: Data, fault: LocalFault) throws {
        do {
            guard let profileID = journal.profileID, let representationID = journal.representationID,
                  let draftOperationID = journal.draftOperationID, let mediaOperationID = journal.mediaOperationID else { throw ValidationFailure.invariant("prepared identity missing") }
            let draftID = journal.draftID, mediaID = journal.mediaID
            let precision = journal.precision ?? "importedBytes", photoReference = journal.photoReference
            let date = Date()
            context.insert(CaptureDraftRecord(id: draftID, householdID: libraryID, name: "Synthetic capture", createdAt: date, updatedAt: date, captureSource: precision == "pickerDeliveredRepresentation" ? .photoLibrary : .camera))
            let profile = WardrobeProfile(id: profileID, ownerID: draftID, size: "M", material: "cotton")
            context.insert(profile)
            context.insert(MediaAssetRecord(id: mediaID, ownerKind: .draft, ownerID: draftID, originalFileName: journal.originalName, thumbnailFileName: journal.previewName, contentTypeIdentifier: type, createdAt: date, sortOrder: 0))
            let representation = MediaRepresentation(id: representationID, mediaID: mediaID, revision: 1, precision: precision, originalHash: journal.originalHash, relativePath: "media/\(journal.originalName)", photosReference: photoReference)
            context.insert(representation)
            let sync = try SyncCore.local(context: context, library: libraryID, root: root)
            try sync.stageWrite(WireRecord(id: draftID, operationID: draftOperationID, revision: 1, library: libraryID, kind: "draft", name: "Synthetic capture", profile: WireProfile(id: profile.id, size: profile.size, material: profile.material)))
            try sync.stageWrite(WireRecord(id: mediaID, operationID: mediaOperationID, revision: 1, library: libraryID, kind: "media", parentID: draftID, media: WireMedia(representationID: representation.id, revision: 1, hash: journal.originalHash, precision: representation.precision, contentType: type, preview: preview, photosReference: photoReference)))
            if fault == .beforeSave { throw fault }
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func finalize(_ journal: FileJournal, journalURL: URL, fault: LocalFault = .none, checkpoint: ((String) -> Void)? = nil) throws {
        guard journal.originalName == "\(journal.mediaID).original", journal.previewName == "\(journal.mediaID).preview.jpg",
              journal.originalHash.count == 64 else { throw ValidationFailure.invariant("unsafe file journal") }
        for name in [journal.originalName, journal.previewName] {
            let source = root.appendingPathComponent("staging/\(name)")
            let target = root.appendingPathComponent("media/\(name)")
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.moveItem(at: source, to: target)
                if name == journal.originalName { checkpoint?("originalFinalized") }
            }
        }
        let original = try Data(contentsOf: root.appendingPathComponent("media/\(journal.originalName)"))
        guard MediaFiles.hash(original) == journal.originalHash else { throw ValidationFailure.invariant("finalize hash mismatch") }
        if fault == .cleanup { throw fault }
        try FileManager.default.removeItem(at: journalURL)
    }

    public func recover(fault: LocalFault = .none) throws {
        recoveryIssues = []
        for url in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("journals"), includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let bytes = try Data(contentsOf: url)
                let known: Set<String> = ["draftID", "mediaID", "originalHash", "originalName", "previewName", "profileID", "representationID", "draftOperationID", "mediaOperationID", "precision", "photoReference"]
                guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], Set(object.keys).isSubset(of: known) else {
                    throw ValidationFailure.invariant("future journal preserved for compatible recovery")
                }
                var journal = try JSONDecoder().decode(FileJournal.self, from: bytes)
                guard journal.originalName == "\(journal.mediaID).original", journal.previewName == "\(journal.mediaID).preview.jpg" else { throw ValidationFailure.invariant("unsafe journal") }
                let referenced = try context.fetch(FetchDescriptor<MediaAssetRecord>()).contains { $0.id == journal.mediaID }
                if !referenced {
                    // Old journals receive identities once, durably, before any DB mutation.
                    journal.profileID = journal.profileID ?? UUID(); journal.representationID = journal.representationID ?? UUID()
                    journal.draftOperationID = journal.draftOperationID ?? UUID(); journal.mediaOperationID = journal.mediaOperationID ?? UUID()
                    try MediaFiles.write(JSONEncoder().encode(journal), to: url)
                    let original = try Data(contentsOf: root.appendingPathComponent("staging/" + journal.originalName))
                    guard MediaFiles.hash(original) == journal.originalHash,
                          let image = CGImageSourceCreateWithData(original as CFData, nil), let type = CGImageSourceGetType(image) as String?,
                          ["public.jpeg", "public.heic"].contains(type) else { throw ValidationFailure.invariant("prepared original missing or corrupt") }
                    if fault == .previewWrite { throw fault }
                    let preview = try MediaFiles.preview(original)
                    try MediaFiles.write(preview, to: root.appendingPathComponent("staging/" + journal.previewName))
                    try commitPrepared(journal, type: type, preview: preview, fault: fault)
                }
                if fault == .afterSave || fault == .finalize { throw fault }
                try finalize(journal, journalURL: url, fault: fault)
            } catch {
                // Keep the journal and original for another attempt; one broken entry
                // must not prevent independent recoverable captures from advancing.
                recoveryIssues.append("Prepared capture retained; recovery requires retry or source repair")
            }
        }
    }

    @discardableResult public func confirm(_ draftID: UUID) throws -> UUID {
        if let existing = try context.fetch(FetchDescriptor<ItemRecord>()).first(where: { $0.sourceDraftID == draftID }) { return existing.id }
        guard let draft = try context.fetch(FetchDescriptor<CaptureDraftRecord>()).first(where: { $0.id == draftID }) else {
            throw ValidationFailure.invariant("draft missing")
        }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationFailure.invariant("name required") }
        do {
            let sync = try SyncCore.local(context: context, library: libraryID, root: root)
            let prior = try sync.document(draftID).map { try JSONDecoder().decode(WireRecord.self, from: $0.payload) }
            guard prior?.revision != Int.max else { throw ValidationFailure.invariant("revision exhausted") }
            // Same Draft produces the same logical Item on independent clients.
            let item = ItemRecord(id: draftID, householdID: draft.householdID, name: draft.name, categoryID: draft.categoryID, locationID: draft.locationID, note: draft.note, createdAt: draft.createdAt, updatedAt: .now, captureSource: draft.captureSource, sourceDraftID: draftID)
            context.insert(item)
            for media in try context.fetch(FetchDescriptor<MediaAssetRecord>()) where media.ownerID == draftID && media.ownerKind == .draft {
                media.ownerKind = .item
                if item.coverMediaID == nil { item.coverMediaID = media.id }
            }
            context.delete(draft)
            let profile = try context.fetch(FetchDescriptor<WardrobeProfile>()).first { $0.ownerID == draftID }
            var wire = prior ?? WireRecord(id: item.id, operationID: UUID(), revision: 1, library: libraryID, kind: "draft")
            wire.operationID = UUID(); wire.revision += 1; wire.kind = "item"
            wire.name = item.name; wire.category = item.categoryID?.uuidString; wire.sourceDraftID = draftID
            wire.profile = profile.map { WireProfile(id: $0.id, size: $0.size, material: $0.material) }
            try sync.stageWrite(wire)
            try context.save()
            return item.id
        } catch { context.rollback(); throw error }
    }

    public func counts() throws -> [String: Int] {
        ["drafts": try context.fetchCount(FetchDescriptor<CaptureDraftRecord>()),
         "items": try context.fetchCount(FetchDescriptor<ItemRecord>()),
         "media": try context.fetchCount(FetchDescriptor<MediaAssetRecord>()),
         "profiles": try context.fetchCount(FetchDescriptor<WardrobeProfile>()),
         "outbox": try context.fetchCount(FetchDescriptor<DurableIntent>())]
    }
}
