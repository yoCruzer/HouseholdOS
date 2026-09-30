import XCTest
import SwiftData
@testable import ValidationCore

final class StorageFailureTests: XCTestCase {
    @MainActor func testRealReadOnlySwiftDataSaveFailureHasNoPhantomDraftOrIntent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do { _ = try LocalChain(root: root) }
        let readOnly = try LocalChain(root: root, allowsSave: false)
        XCTAssertThrowsError(try readOnly.capture(MediaFiles.syntheticJPEG()))
        XCTAssertEqual(readOnly.lastCaptureOutcome, .notCommitted)
        let reopened = try LocalChain(root: root)
        XCTAssertEqual(try reopened.counts()["drafts"], 0)
        XCTAssertEqual(try reopened.counts()["outbox"], 0)
        let retained = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("staging"), includingPropertiesForKeys: nil)
        XCTAssertEqual(retained.filter { $0.pathExtension == "original" }.count, 1)
    }
    @MainActor func testSavedButRefreshUnavailableRetainsSuccessAndNoReplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        _ = try chain.capture(MediaFiles.syntheticJPEG(), fault: .refresh)
        XCTAssertEqual(chain.lastCaptureOutcome, .savedRefreshUnavailable)
        XCTAssertEqual(try LocalChain(root: root).counts()["drafts"], 1)
        XCTAssertEqual(try chain.counts()["outbox"], 2)
    }
    func testStorageClassesNeverTreatPermissionAsCorruption() {
        let values: [(Int, StorageFailure)] = [(NSFileReadNoPermissionError, .permissionOrProtection), (NSFileWriteOutOfSpaceError, .capacity), (NSFileReadCorruptFileError, .corrupt), (NSFileReadNoSuchFileError, .missing)]
        for (code, expected) in values { XCTAssertEqual(StorageFailure.classify(NSError(domain: NSCocoaErrorDomain, code: code)), expected) }
        XCTAssertEqual(StorageFailure.classify(NSError(domain: "unknown", code: 1)), .unavailable)
    }
}
