import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StoredMediaFile: Equatable, Sendable {
    let originalFileName: String
    let thumbnailFileName: String?
    let contentTypeIdentifier: String
}

struct MediaMaintenanceFailure: Equatable, Sendable {
    let fileName: String
    let message: String
}

struct MediaMaintenanceResult: Equatable, Sendable {
    var removedFileNames: [String] = []
    var failures: [MediaMaintenanceFailure] = []

    var isComplete: Bool {
        failures.isEmpty
    }

    static let empty = MediaMaintenanceResult()
}

enum MediaFileOperation: Equatable, Sendable {
    case importOriginal
    case createThumbnail
}

enum MediaFileStoreError: LocalizedError, Sendable {
    case moveAndCleanupFailed(move: String, cleanup: String)

    var errorDescription: String? {
        switch self {
        case .moveAndCleanupFailed(let move, let cleanup):
            String(
                localized: "The media import failed, and its staging file could not be removed."
            ) + " \(move) \(cleanup)"
        }
    }
}

typealias MediaFileRemoval = @Sendable (URL) throws -> Void
typealias MediaFileOperationObserver = @Sendable (MediaFileOperation, Bool) -> Void

actor MediaFileStore {
    nonisolated let rootURL: URL

    private let removeFile: MediaFileRemoval
    private let operationObserver: MediaFileOperationObserver?
    private var activeIncomingFileNames: Set<String> = []
    private var reservedFileNames: Set<String> = []

    init(
        rootURL: URL,
        removeFile: @escaping MediaFileRemoval = MediaFileStore.defaultRemove,
        operationObserver: MediaFileOperationObserver? = nil
    ) throws {
        self.rootURL = rootURL
        self.removeFile = removeFile
        self.operationObserver = operationObserver
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    static func applicationSupport() throws -> MediaFileStore {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try MediaFileStore(
            rootURL: applicationSupport
                .appendingPathComponent("HouseholdOSMedia", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        )
    }

    func importFile(
        at sourceURL: URL,
        contentTypeIdentifier: String,
        id: UUID
    ) throws -> StoredMediaFile {
        operationObserver?(.importOriginal, Thread.isMainThread)
        let fileExtension = preferredExtension(
            contentTypeIdentifier: contentTypeIdentifier,
            fallback: sourceURL.pathExtension
        )
        let originalFileName = "\(id.uuidString.lowercased()).\(fileExtension)"
        let destinationURL = url(for: originalFileName)
        let incomingFileName = ".incoming-\(UUID().uuidString.lowercased())"
        let incomingURL = url(for: incomingFileName)
        activeIncomingFileNames.insert(incomingFileName)
        defer {
            activeIncomingFileNames.remove(incomingFileName)
        }

        try FileManager.default.copyItem(at: sourceURL, to: incomingURL)
        do {
            try FileManager.default.moveItem(at: incomingURL, to: destinationURL)
        } catch let moveError {
            do {
                try removeFile(incomingURL)
            } catch let cleanupError {
                throw MediaFileStoreError.moveAndCleanupFailed(
                    move: moveError.localizedDescription,
                    cleanup: cleanupError.localizedDescription
                )
            }
            throw moveError
        }

        let thumbnailFileName = makeThumbnail(
            sourceURL: destinationURL,
            id: id
        )

        let storedFile = StoredMediaFile(
            originalFileName: originalFileName,
            thumbnailFileName: thumbnailFileName,
            contentTypeIdentifier: contentTypeIdentifier
        )
        reserve(storedFile)
        return storedFile
    }

    func importData(
        _ data: Data,
        contentTypeIdentifier: String,
        id: UUID
    ) throws -> StoredMediaFile {
        operationObserver?(.importOriginal, Thread.isMainThread)
        let fileExtension = preferredExtension(
            contentTypeIdentifier: contentTypeIdentifier,
            fallback: "jpg"
        )
        let originalFileName = "\(id.uuidString.lowercased()).\(fileExtension)"
        let destinationURL = url(for: originalFileName)
        try data.write(to: destinationURL, options: .atomic)

        let thumbnailFileName = makeThumbnail(
            sourceURL: destinationURL,
            id: id
        )

        let storedFile = StoredMediaFile(
            originalFileName: originalFileName,
            thumbnailFileName: thumbnailFileName,
            contentTypeIdentifier: contentTypeIdentifier
        )
        reserve(storedFile)
        return storedFile
    }

    nonisolated func url(for fileName: String) -> URL {
        rootURL.appendingPathComponent(fileName)
    }

    func remove(_ storedFile: StoredMediaFile) -> MediaMaintenanceResult {
        release(storedFile)
        var result = MediaMaintenanceResult()
        removeIfPresent(fileName: storedFile.originalFileName, result: &result)
        if let thumbnailFileName = storedFile.thumbnailFileName {
            removeIfPresent(fileName: thumbnailFileName, result: &result)
        }
        return result
    }

    func markPersisted(_ storedFile: StoredMediaFile) {
        release(storedFile)
    }

    func cleanupOrphans(
        keeping knownFileNames: Set<String>
    ) -> MediaMaintenanceResult {
        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            return MediaMaintenanceResult(
                failures: [
                    MediaMaintenanceFailure(
                        fileName: "<media-directory>",
                        message: error.localizedDescription
                    )
                ]
            )
        }

        var result = MediaMaintenanceResult()
        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            let isRegularFile = (
                try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey]
                ).isRegularFile
            ) == true
            guard !knownFileNames.contains(fileName),
                  !activeIncomingFileNames.contains(fileName),
                  !reservedFileNames.contains(fileName),
                  isRegularFile else {
                continue
            }
            removeIfPresent(fileName: fileName, result: &result)
        }
        return result
    }

    private static func defaultRemove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    private func reserve(_ storedFile: StoredMediaFile) {
        reservedFileNames.insert(storedFile.originalFileName)
        if let thumbnailFileName = storedFile.thumbnailFileName {
            reservedFileNames.insert(thumbnailFileName)
        }
    }

    private func release(_ storedFile: StoredMediaFile) {
        reservedFileNames.remove(storedFile.originalFileName)
        if let thumbnailFileName = storedFile.thumbnailFileName {
            reservedFileNames.remove(thumbnailFileName)
        }
    }

    private func removeIfPresent(
        fileName: String,
        result: inout MediaMaintenanceResult
    ) {
        let fileURL = url(for: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try removeFile(fileURL)
            result.removedFileNames.append(fileName)
        } catch {
            result.failures.append(
                MediaMaintenanceFailure(
                    fileName: fileName,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func preferredExtension(
        contentTypeIdentifier: String,
        fallback: String
    ) -> String {
        if let type = UTType(contentTypeIdentifier),
           let preferred = type.preferredFilenameExtension {
            return preferred
        }

        let sanitized = fallback.lowercased().filter { $0.isLetter || $0.isNumber }
        return sanitized.isEmpty ? "img" : sanitized
    }

    private func makeThumbnail(sourceURL: URL, id: UUID) -> String? {
        operationObserver?(.createThumbnail, Thread.isMainThread)
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        let fileName = "\(id.uuidString.lowercased())-thumb.jpg"
        let destinationURL = url(for: fileName)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        return CGImageDestinationFinalize(destination) ? fileName : nil
    }
}
