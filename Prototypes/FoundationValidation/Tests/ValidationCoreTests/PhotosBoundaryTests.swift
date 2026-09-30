import XCTest
import Photos
import SwiftData
@testable import ValidationCore

final class PhotosBoundaryTests: XCTestCase {
    func testSelectionAndPersistentPermissionAreSeparateWithFallbackBytes() throws {
        let bytes = try MediaFiles.syntheticJPEG()
        for (identifier, authorized, count, expected) in [
            (nil, false, 0, PhotosAccess.missingIdentifier),
            ("selected-fixture", false, 0, .noAuthorization),
            ("selected-fixture", true, 0, .inaccessible),
            ("selected-fixture", true, 1, .accessible),
            ("selected-fixture", false, 1, .noAuthorization)
        ] {
            let result = PhotosAdapter.selectedAccess(identifier: identifier, authorized: authorized, assetCount: count, bytes: bytes)
            XCTAssertEqual(result.access, expected)
            XCTAssertEqual(result.fallbackBytes, bytes)
            XCTAssertEqual(result.precision, "pickerDeliveredRepresentation")
        }
    }
    func testMappingFailuresAreNotPermanentDeletionOrAutomaticRebinding() {
        let cases: [(PHPhotosError.Code, PhotosMappingState)] = [(.identifierNotFound, .temporarilyNotFound), (.multipleIdentifiersFound, .multipleCandidates), (.networkAccessRequired, .networkRequired), (.notEnoughSpace, .insufficientSpace), (.accessUserDenied, .noAuthorization)]
        for (code, state) in cases { XCTAssertEqual(PhotosAdapter.classify(NSError(domain: PHPhotosErrorDomain, code: code.rawValue)), state) }
    }
    @MainActor func testNoPersistentPermissionFallbackRestoresWithoutPhotosWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try LocalChain(root: root.appendingPathComponent("source"))
        let bytes = try MediaFiles.syntheticJPEG()
        let result = PhotosAdapter.selectedAccess(identifier: nil, authorized: false, assetCount: 0, bytes: bytes)
        _ = try source.capture(result.fallbackBytes, precision: result.precision)
        let backup = root.appendingPathComponent("smart")
        let manifest = try BackupRestore.export(source, to: backup, full: false)
        let generations = root.appendingPathComponent("restored")
        _ = try BackupRestore.restore(backup, into: generations)
        let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
        let representation = try XCTUnwrap(restored.context.fetch(FetchDescriptor<MediaRepresentation>()).first)
        XCTAssertEqual(representation.precision, "pickerDeliveredRepresentation")
        XCTAssertEqual(try Data(contentsOf: restored.root.appendingPathComponent(representation.relativePath)), bytes)
        XCTAssertEqual(manifest.representations.first?.precision, representation.precision)
        XCTAssertThrowsError(try BackupRestore.export(source, to: root.appendingPathComponent("full"), full: true), "Picker bytes alone cannot prove a full original resource collection")
    }
}
