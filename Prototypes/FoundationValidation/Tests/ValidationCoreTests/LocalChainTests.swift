import XCTest
import SwiftData
import ImageIO
@testable import ValidationCore

final class LocalChainTests: XCTestCase {
    @MainActor func testCaptureReopenConfirmKeepsMediaAndProfileIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try MediaFiles.syntheticJPEG()
        let chain = try LocalChain(root: root)
        let draftID = try chain.capture(bytes)
        let mediaID = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first?.id)
        let profileID = try XCTUnwrap(chain.context.fetch(FetchDescriptor<WardrobeProfile>()).first?.id)
        let reopened = try LocalChain(root: root)
        try reopened.recover()
        XCTAssertEqual(try reopened.confirm(draftID), draftID)
        XCTAssertEqual(try reopened.confirm(draftID), draftID)
        XCTAssertEqual(try reopened.counts(), ["drafts": 0, "items": 1, "media": 1, "profiles": 1, "outbox": 3])
        XCTAssertEqual(try reopened.context.fetch(FetchDescriptor<MediaAssetRecord>()).first?.id, mediaID)
        XCTAssertEqual(try reopened.context.fetch(FetchDescriptor<WardrobeProfile>()).first?.id, profileID)
        let representation = try XCTUnwrap(reopened.context.fetch(FetchDescriptor<MediaRepresentation>()).first)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(representation.relativePath)), bytes)
    }

    @MainActor func testJournalFailuresPreserveStagingAndAtomicOutbox() throws {
        for fault in [LocalFault.originalWrite, .previewWrite, .beforeSave, .afterSave, .finalize, .cleanup] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let bytes = try MediaFiles.syntheticJPEG()
            let chain = try LocalChain(root: root)
            XCTAssertThrowsError(try chain.capture(bytes, fault: fault))
            let reopened = try LocalChain(root: root)
            try reopened.recover()
            let committed = [.afterSave, .finalize, .cleanup].contains(fault)
            XCTAssertEqual(try reopened.counts()["drafts"], committed ? 1 : 0, fault.rawValue)
            XCTAssertEqual(try reopened.counts()["outbox"], committed ? 2 : 0, fault.rawValue)
            if fault != .originalWrite {
                let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(committed ? "media" : "staging"), includingPropertiesForKeys: nil)
                let original = try XCTUnwrap(files.first { $0.pathExtension == "original" })
                XCTAssertEqual(try Data(contentsOf: original), bytes)
            }
        }
    }

    func testPreviewStripsGPSAndOriginalRetainsMetadata() throws {
        let original = try MediaFiles.syntheticJPEG()
        let preview = try MediaFiles.preview(original)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(original as CFData, nil))
        let output = try XCTUnwrap(CGImageSourceCreateWithData(preview as CFData, nil))
        let before = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let after = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [String: Any])
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary as String])
        XCTAssertNil(after[kCGImagePropertyGPSDictionary as String])
        let originalEXIF = try XCTUnwrap(before[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertNotNil(originalEXIF[kCGImagePropertyExifDateTimeOriginal as String])
        let outputEXIF = after[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        XCTAssertNil(outputEXIF[kCGImagePropertyExifDateTimeOriginal as String])
        XCTAssertNil(outputEXIF[kCGImagePropertyExifUserComment as String])
        XCTAssertTrue(Set(outputEXIF.keys).isSubset(of: ["ColorSpace", "PixelXDimension", "PixelYDimension"]))
        XCTAssertEqual(after[kCGImagePropertyPixelHeight as String] as? Int, 256)
        XCTAssertEqual(after[kCGImagePropertyPixelWidth as String] as? Int, 192)
    }
}
