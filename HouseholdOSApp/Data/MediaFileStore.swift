import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

struct StoredMediaFile: Sendable {
    let originalFileName: String
    let thumbnailFileName: String?
    let contentTypeIdentifier: String
}

struct MediaFileStore: Sendable {
    let rootURL: URL

    init(rootURL: URL) throws {
        self.rootURL = rootURL
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
        let fileExtension = preferredExtension(
            contentTypeIdentifier: contentTypeIdentifier,
            fallback: sourceURL.pathExtension
        )
        let originalFileName = "\(id.uuidString.lowercased()).\(fileExtension)"
        let destinationURL = rootURL.appendingPathComponent(originalFileName)
        let incomingURL = rootURL.appendingPathComponent(".incoming-\(UUID().uuidString)")

        try FileManager.default.copyItem(at: sourceURL, to: incomingURL)
        do {
            try FileManager.default.moveItem(at: incomingURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: incomingURL)
            throw error
        }

        let thumbnailFileName = makeThumbnail(
            sourceURL: destinationURL,
            id: id
        )

        return StoredMediaFile(
            originalFileName: originalFileName,
            thumbnailFileName: thumbnailFileName,
            contentTypeIdentifier: contentTypeIdentifier
        )
    }

    func importData(
        _ data: Data,
        contentTypeIdentifier: String,
        id: UUID
    ) throws -> StoredMediaFile {
        let fileExtension = preferredExtension(
            contentTypeIdentifier: contentTypeIdentifier,
            fallback: "jpg"
        )
        let originalFileName = "\(id.uuidString.lowercased()).\(fileExtension)"
        let destinationURL = rootURL.appendingPathComponent(originalFileName)
        try data.write(to: destinationURL, options: .atomic)

        let thumbnailFileName = makeThumbnail(
            sourceURL: destinationURL,
            id: id
        )

        return StoredMediaFile(
            originalFileName: originalFileName,
            thumbnailFileName: thumbnailFileName,
            contentTypeIdentifier: contentTypeIdentifier
        )
    }

    func url(for fileName: String) -> URL {
        rootURL.appendingPathComponent(fileName)
    }

    func remove(_ storedFile: StoredMediaFile) {
        try? FileManager.default.removeItem(
            at: url(for: storedFile.originalFileName)
        )
        if let thumbnailFileName = storedFile.thumbnailFileName {
            try? FileManager.default.removeItem(
                at: url(for: thumbnailFileName)
            )
        }
    }

    @discardableResult
    func cleanupOrphans(keeping knownFileNames: Set<String>) throws -> [String] {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var removed: [String] = []

        for fileURL in fileURLs where !knownFileNames.contains(fileURL.lastPathComponent) {
            try FileManager.default.removeItem(at: fileURL)
            removed.append(fileURL.lastPathComponent)
        }

        return removed
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
        ),
        let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else {
            return nil
        }

        let fileName = "\(id.uuidString.lowercased())-thumb.jpg"
        do {
            try data.write(to: rootURL.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }
}
