import Foundation
import SwiftData
import CloudKit
import ImageIO

enum MediaPolicy: String, Codable { case dataOnly, preview, appOwnedOriginals }
struct TransferTicket: Codable, Equatable {
    var operationID: UUID
    var mediaID: UUID
    var representationID: UUID
    var revision: Int
    var sha256: String
    var scope: SyncScope
    var bytes: Int
    var phase: String
}
struct MediaTransferState: Codable {
    var policy: MediaPolicy = .preview
    var tickets: [TransferTicket] = []
    var pauseReason: String?
    var retryAfter: Date?
}

@MainActor final class MediaTransfers {
    let chain: LocalChain
    let core: SyncCore
    private(set) var state: MediaTransferState
    init(chain: LocalChain, core: SyncCore) throws {
        self.chain = chain; self.core = core
        let row = try chain.context.fetch(FetchDescriptor<SyncCheckpoint>()).first { $0.key == "media-transfers" }
        state = try row.map { try JSONDecoder().decode(MediaTransferState.self, from: $0.data) } ?? MediaTransferState()
    }
    func persist() throws {
        let bytes = try JSONEncoder().encode(state)
        if let row = try chain.context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "media-transfers" }) { row.data = bytes }
        else { chain.context.insert(SyncCheckpoint(key: "media-transfers", data: bytes)) }
        try core.commit()
    }
    func setPolicy(_ policy: MediaPolicy) throws {
        state.policy = policy
        // No delete is enqueued; existing acknowledged copies and files remain.
        try persist()
    }
    func current(_ mediaID: UUID) throws -> MediaRepresentation {
        guard let asset = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first(where: { $0.id == mediaID }),
              let row = try core.document(asset.ownerID),
              !(try JSONDecoder().decode(WireRecord.self, from: row.payload).deleted),
              let representation = try chain.context.fetch(FetchDescriptor<MediaRepresentation>()).filter({ $0.mediaID == mediaID }).max(by: { $0.revision < $1.revision }) else {
            throw ValidationFailure.invariant("media is not currently attached to a live parent")
        }
        return representation
    }
    func beginUpload(_ mediaID: UUID, now: Date = .now) throws -> TransferTicket {
        guard core.accepts(core.session.scope), core.session.bootstrapComplete, state.policy == .appOwnedOriginals,
              state.pauseReason == nil, state.retryAfter.map({ $0 <= now }) ?? true else { throw ValidationFailure.invariant("upload not scheduled by current policy/scope/backoff") }
        let representation = try current(mediaID)
        guard representation.photosReference == nil else { throw ValidationFailure.invariant("Photos-backed originals are not uploaded by default") }
        let bytes = try Data(contentsOf: BackupRestore.safeURL(representation.relativePath, in: chain.root))
        guard MediaFiles.hash(bytes) == representation.originalHash else { throw ValidationFailure.invariant("local original integrity failure") }
        if let pending = state.tickets.first(where: { $0.representationID == representation.id && $0.scope == core.session.scope && $0.phase == "prepared" }) { return pending }
        let ticket = TransferTicket(operationID: UUID(), mediaID: mediaID, representationID: representation.id, revision: representation.revision, sha256: representation.originalHash, scope: core.session.scope, bytes: bytes.count, phase: "prepared")
        state.tickets.append(ticket); try persist()
        return ticket
    }
    func downloadTicket(_ mediaID: UUID, now: Date = .now) throws -> TransferTicket {
        guard core.accepts(core.session.scope), core.session.bootstrapComplete,
              state.pauseReason == nil, state.retryAfter.map({ $0 <= now }) ?? true else { throw ValidationFailure.invariant("download requires current scope, fetched metadata and queue admission") }
        let representation = try current(mediaID)
        return TransferTicket(operationID: UUID(), mediaID: mediaID, representationID: representation.id, revision: representation.revision, sha256: representation.originalHash, scope: core.session.scope, bytes: 0, phase: "download")
    }
    @discardableResult func acknowledge(_ ticket: TransferTicket) throws -> Bool {
        guard core.accepts(ticket.scope), let index = state.tickets.firstIndex(where: { $0.operationID == ticket.operationID && $0 == ticket }) else { return false }
        let current = try current(ticket.mediaID)
        let matches = current.id == ticket.representationID && current.revision == ticket.revision && current.originalHash == ticket.sha256
        state.tickets[index].phase = matches ? "acknowledged" : "acknowledged-old-representation"
        try persist()
        return matches
    }
    @discardableResult func receive(_ bytes: Data, for ticket: TransferTicket) throws -> Bool {
        guard core.accepts(ticket.scope) else { return false }
        let current = try current(ticket.mediaID)
        guard current.id == ticket.representationID, current.revision == ticket.revision, current.originalHash == ticket.sha256 else { return false }
        guard MediaFiles.hash(bytes) == ticket.sha256 else { throw ValidationFailure.invariant("download hash mismatch") }
        let target = try BackupRestore.safeURL(current.relativePath, in: chain.root)
        try MediaFiles.write(bytes, to: target)
        return true
    }
    func serviceFailed(_ error: CKError, callback: SyncScope, now: Date = .now) throws {
        guard core.accepts(callback) else { return }
        switch error.code {
        case .quotaExceeded: state.pauseReason = "quota exceeded; all media queue paused"
        case .requestRateLimited, .serviceUnavailable, .networkFailure, .networkUnavailable:
            state.retryAfter = now.addingTimeInterval(max(error.retryAfterSeconds ?? 30, 1))
        default: state.pauseReason = "service error requires reconciliation"
        }
        try persist()
    }
    func replace(_ mediaID: UUID, bytes: Data) throws {
        let previous = try current(mediaID)
        guard let asset = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first(where: { $0.id == mediaID }),
              let image = CGImageSourceCreateWithData(bytes as CFData, nil), let type = CGImageSourceGetType(image) as String?, ["public.jpeg", "public.heic"].contains(type),
              let document = try core.document(mediaID) else { throw ValidationFailure.invariant("replacement source invalid") }
        var wire = try JSONDecoder().decode(WireRecord.self, from: document.payload)
        let id = UUID(), original = "\(id).original", previewName = "\(id).preview.jpg"
        let preview = try MediaFiles.preview(bytes)
        // Immutable new files first. A failed save leaves the previous representation intact;
        // unreferenced prepared files are retained, never scavenged as disposable thumbnails.
        try MediaFiles.write(bytes, to: chain.root.appendingPathComponent("media/" + original))
        try MediaFiles.write(preview, to: chain.root.appendingPathComponent("media/" + previewName))
        let representation = MediaRepresentation(id: id, mediaID: mediaID, revision: previous.revision + 1, precision: "importedBytes", originalHash: MediaFiles.hash(bytes), relativePath: "media/" + original)
        chain.context.insert(representation)
        asset.originalFileName = original; asset.thumbnailFileName = previewName; asset.contentTypeIdentifier = type
        wire.operationID = UUID(); wire.revision += 1
        wire.media = WireMedia(representationID: id, revision: representation.revision, hash: representation.originalHash, precision: representation.precision, contentType: type, preview: preview)
        do { try core.stageWrite(wire); try core.commit() } catch { chain.context.rollback(); throw error }
    }
}

struct PlannedMedia {
    var id: UUID
    var previewBytes: Int
    var originalBytes: Int
    var photosBacked: Bool
}
struct PlannedTransfer {
    var kind: String
    var mediaID: UUID?
    var estimatedBytes: Int
}
enum MediaPlanner {
    static func plan(itemCount: Int, media: [PlannedMedia], policy: MediaPolicy) -> [PlannedTransfer] {
        var plan = [PlannedTransfer(kind: "metadata", estimatedBytes: itemCount * 1024)]
        if policy != .dataOnly { plan += media.map { PlannedTransfer(kind: "preview", mediaID: $0.id, estimatedBytes: $0.previewBytes) } }
        if policy == .appOwnedOriginals { plan += media.filter { !$0.photosBacked }.map { PlannedTransfer(kind: "original", mediaID: $0.id, estimatedBytes: $0.originalBytes) } }
        return plan
    }
}

// Estimate reservation survives restart; retry reserves again. Never reports exact account capacity.
struct LiveBudget: Codable {
    var estimatedBytes = 0
    static let limit = 100 * 1024 * 1024
    mutating func reserve(payloadBytes: Int, at url: URL) throws {
        guard payloadBytes >= 0, payloadBytes <= Self.limit - estimatedBytes - 4096 else { throw ValidationFailure.invariant("live budget exhausted") }
        estimatedBytes += payloadBytes + 4096
        try MediaFiles.write(JSONEncoder().encode(self), to: url)
    }
    static func load(_ url: URL) throws -> LiveBudget {
        if !FileManager.default.fileExists(atPath: url.path) { return LiveBudget() }
        return try JSONDecoder().decode(LiveBudget.self, from: Data(contentsOf: url))
    }
}
