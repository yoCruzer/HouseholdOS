import Foundation
import SwiftData
import SQLite3

struct BackupFile: Codable, Equatable {
    var path: String
    var size: Int
    var sha256: String
}
struct BackupRepresentation: Codable, Equatable {
    var mediaID: UUID
    var representationID: UUID
    var revision: Int
    var precision: String
    var sha256: String
    var path: String
}
struct BackupManifest: Codable {
    var version = 1
    var snapshotID: UUID
    var libraryID: UUID
    var mode: String
    var files: [BackupFile]
    var representations: [BackupRepresentation]
    var externalPhotosDependencies: Int
    var complete: Bool
}
enum BackupFault: Error { case cancelled, capacity, interrupted, beforeSwitch, afterSwitch }

// Directory-package prototype only; no compression, external providers or Photos writes.
@MainActor enum BackupRestore {
    static let maximumFiles = 4096
    static let maximumBytes = 256 * 1024 * 1024

    static func safeURL(_ relative: String, in root: URL) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.hasPrefix("/"), !parts.contains(".."), !parts.contains("."), !parts.contains(""),
              !relative.contains("\\"), !relative.contains("\0") else { throw ValidationFailure.invariant("unsafe package path") }
        var cursor = root
        let rootFlags = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootFlags.isSymbolicLink != true else { throw ValidationFailure.invariant("symlink root") }
        for part in parts {
            cursor.appendPathComponent(String(part))
            if FileManager.default.fileExists(atPath: cursor.path) {
                guard try cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ValidationFailure.invariant("package symlink") }
            }
        }
        guard cursor.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ValidationFailure.invariant("path escapes root") }
        return cursor
    }

    static func sqliteSnapshot(from source: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ValidationFailure.destinationExists }
        var input: OpaquePointer?, output: OpaquePointer?
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if input != nil { sqlite3_close(input) }
            throw ValidationFailure.invariant("cannot read snapshot source")
        }
        defer { sqlite3_close(input) }
        guard sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            if output != nil { sqlite3_close(output) }
            throw ValidationFailure.invariant("cannot create snapshot database")
        }
        defer { sqlite3_close(output) }
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else { throw ValidationFailure.invariant("cannot begin consistent SQLite snapshot") }
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else { throw ValidationFailure.invariant("snapshot busy or failed; retry explicitly") }
    }

    // Synchronous MainActor boundary freezes all fixture writes until structure + media are copied.
    // SQLite backup includes committed WAL content, avoiding a live sqlite-only filesystem copy.
    static func export(_ chain: LocalChain, to destination: URL, full: Bool, fault: BackupFault? = nil) throws -> BackupManifest {
        guard !chain.context.hasChanges else { throw ValidationFailure.invariant("uncommitted transaction prevents snapshot") }
        try chain.recover()
        let partial = destination.appendingPathExtension("partial")
        guard !FileManager.default.fileExists(atPath: destination.path), !FileManager.default.fileExists(atPath: partial.path) else { throw ValidationFailure.destinationExists }
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        let snapshotID = UUID()
        try sqliteSnapshot(from: chain.root.appendingPathComponent("library.store"), to: partial.appendingPathComponent("library.store"))
        if fault == .cancelled || fault == .capacity { throw fault! }
        let media = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>())
        let representations = try chain.context.fetch(FetchDescriptor<MediaRepresentation>())
        var paths = Set<String>()
        var represented: [BackupRepresentation] = []
        for asset in media {
            let current = representations.filter { $0.mediaID == asset.id }.max { $0.revision < $1.revision }
            if let current {
                if full && current.precision == "pickerDeliveredRepresentation" {
                    throw ValidationFailure.invariant("Full unavailable: picker delivery does not prove complete original resource fidelity")
                }
                // Missing cloud-only originals are an incomplete result, never a successful Full.
                let original = try safeURL(current.relativePath, in: chain.root)
                guard FileManager.default.fileExists(atPath: original.path) else { throw ValidationFailure.invariant("backup incomplete: original unavailable") }
                let bytes = try Data(contentsOf: original)
                guard MediaFiles.hash(bytes) == current.originalHash else { throw ValidationFailure.invariant("backup original integrity failure") }
                paths.insert(current.relativePath)
                represented.append(BackupRepresentation(mediaID: asset.id, representationID: current.id, revision: current.revision, precision: current.precision, sha256: current.originalHash, path: current.relativePath))
            } else {
                let managed = "media/" + asset.originalFileName
                let legacy = asset.originalFileName
                let path = FileManager.default.fileExists(atPath: try safeURL(managed, in: chain.root).path) ? managed : legacy
                guard FileManager.default.fileExists(atPath: try safeURL(path, in: chain.root).path) else { throw ValidationFailure.invariant("legacy original unavailable") }
                paths.insert(path)
            }
            if let preview = asset.thumbnailFileName {
                let managed = "media/" + preview
                let path = FileManager.default.fileExists(atPath: try safeURL(managed, in: chain.root).path) ? managed : preview
                guard FileManager.default.fileExists(atPath: try safeURL(path, in: chain.root).path) else { throw ValidationFailure.invariant("recovery preview unavailable") }
                paths.insert(path)
            }
        }
        // Preserve prepared originals and journal recovery intent too, including uncommitted captures.
        for representation in representations where !represented.contains(where: { $0.representationID == representation.id }) {
            let url = try safeURL(representation.relativePath, in: chain.root)
            guard FileManager.default.fileExists(atPath: url.path), MediaFiles.hash(try Data(contentsOf: url)) == representation.originalHash else {
                throw ValidationFailure.invariant("backup incomplete: historical representation unavailable")
            }
            if full && representation.precision == "pickerDeliveredRepresentation" { throw ValidationFailure.invariant("Full fidelity unavailable for picker representation") }
            paths.insert(representation.relativePath)
            represented.append(BackupRepresentation(mediaID: representation.mediaID, representationID: representation.id, revision: representation.revision, precision: representation.precision, sha256: representation.originalHash, path: representation.relativePath))
        }
        for directory in ["media", "staging", "journals"] {
            for url in try FileManager.default.contentsOfDirectory(at: chain.root.appendingPathComponent(directory), includingPropertiesForKeys: nil) {
                paths.insert(directory + "/" + url.lastPathComponent)
            }
        }
        for path in paths.sorted() {
            let source = try safeURL(path, in: chain.root)
            let target = try safeURL(path, in: partial)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
        }
        var files: [BackupFile] = []
        var total = 0
        for path in (["library.store"] + paths.sorted()) {
            let url = try safeURL(path, in: partial)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= maximumBytes - total else { throw ValidationFailure.invariant("package size/type limit") }
            total += size
            files.append(BackupFile(path: path, size: size, sha256: MediaFiles.hash(try Data(contentsOf: url))))
        }
        guard files.count <= maximumFiles else { throw ValidationFailure.invariant("package file limit") }
        let dependencies = representations.filter { $0.photosReference != nil }.count
        let manifest = BackupManifest(snapshotID: snapshotID, libraryID: chain.libraryID, mode: full ? "Full" : "Smart", files: files, representations: represented, externalPhotosDependencies: dependencies, complete: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(manifest)
        try MediaFiles.write(bytes, to: partial.appendingPathComponent("manifest.json"))
        if fault == .interrupted { throw fault! }
        try MediaFiles.write(Data(MediaFiles.hash(bytes).utf8), to: partial.appendingPathComponent("COMPLETE"))
        _ = try validate(partial)
        // Only local same-volume directory finalization is exercised here.
        try FileManager.default.moveItem(at: partial, to: destination)
        return manifest
    }

    static func validate(_ package: URL) throws -> BackupManifest {
        let manifestURL = try safeURL("manifest.json", in: package)
        guard let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024 else { throw ValidationFailure.invariant("manifest too large") }
        let bytes = try Data(contentsOf: manifestURL)
        let marker = try Data(contentsOf: safeURL("COMPLETE", in: package))
        guard marker == Data(MediaFiles.hash(bytes).utf8) else { throw ValidationFailure.invariant("incomplete package marker") }
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: bytes)
        guard manifest.version == 1, manifest.complete, manifest.files.count <= maximumFiles,
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              manifest.files.contains(where: { $0.path == "library.store" }) else { throw ValidationFailure.invariant("unsupported/incomplete manifest") }
        var total = 0
        for file in manifest.files {
            guard file.size >= 0, file.size <= maximumBytes - total else { throw ValidationFailure.invariant("package size limit") }
            total += file.size
            let url = try safeURL(file.path, in: package)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, values.fileSize == file.size,
                  MediaFiles.hash(try Data(contentsOf: url)) == file.sha256 else { throw ValidationFailure.invariant("package integrity failure") }
        }
        for representation in manifest.representations {
            guard manifest.files.contains(where: { $0.path == representation.path && $0.sha256 == representation.sha256 }) else { throw ValidationFailure.invariant("representation absent from snapshot") }
        }
        return manifest
    }

    static func restore(_ package: URL, into generations: URL, fault: BackupFault? = nil) throws -> UUID {
        let manifest = try validate(package)
        try FileManager.default.createDirectory(at: generations, withIntermediateDirectories: true)
        let id = UUID(), stage = generations.appendingPathComponent("generation-" + id.uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        for file in manifest.files {
            let source = try safeURL(file.path, in: package), target = try safeURL(file.path, in: stage)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
        }
        let restored = try LocalChain(root: stage, libraryID: manifest.libraryID)
        let c = restored.context
        for asset in try c.fetch(FetchDescriptor<MediaAssetRecord>()) {
            _ = try safeURL(asset.originalFileName, in: stage)
            if let preview = asset.thumbnailFileName { _ = try safeURL(preview, in: stage) }
        }
        for representation in try c.fetch(FetchDescriptor<MediaRepresentation>()) {
            _ = try safeURL(representation.relativePath, in: stage)
            guard manifest.files.contains(where: { $0.path == representation.relativePath && $0.sha256 == representation.originalHash }) else {
                throw ValidationFailure.invariant("restored representation not covered by manifest")
            }
        }
        for row in try c.fetch(FetchDescriptor<SyncCheckpoint>()) where row.key == "session" || row.key == "media-transfers" { c.delete(row) }
        for snapshot in try c.fetch(FetchDescriptor<SentSnapshot>()) { c.delete(snapshot) }
        let scope = SyncScope(container: "unbound", environment: "Development", account: "unbound", library: manifest.libraryID, zone: "HHOSVAL_" + manifest.libraryID.uuidString, epoch: UUID())
        for row in try c.fetch(FetchDescriptor<SyncedDocument>()) { row.systemFields = nil; row.ancestor = nil; row.scope = scope.key }
        for intent in try c.fetch(FetchDescriptor<DurableIntent>()) { intent.scope = scope.key }
        for conflict in try c.fetch(FetchDescriptor<ConflictCandidate>()) { conflict.scope = scope.key }
        let sync = try SyncCore(context: c, scope: scope, mediaRoot: stage)
        sync.session.pauseReason = "restored snapshot requires cloud admission against current tombstones"
        try sync.saveSession()
        try restored.recover()
        try MediaFiles.write(Data(manifest.snapshotID.uuidString.utf8), to: stage.appendingPathComponent("source-snapshot"))
        if fault == .beforeSwitch { throw fault! }
        // One pointer selects the complete DB+media generation. Previous generations remain intact.
        try MediaFiles.write(Data(stage.lastPathComponent.utf8), to: generations.appendingPathComponent("ACTIVE"))
        if fault == .afterSwitch { throw fault! }
        return manifest.snapshotID
    }

    static func activeGeneration(in root: URL) throws -> URL {
        let name = String(decoding: try Data(contentsOf: root.appendingPathComponent("ACTIVE")), as: UTF8.self)
        guard name.hasPrefix("generation-"), !name.contains("/") else { throw ValidationFailure.invariant("invalid generation pointer") }
        return try safeURL(name, in: root)
    }
}
