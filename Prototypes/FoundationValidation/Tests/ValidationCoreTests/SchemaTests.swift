import XCTest
import SwiftData
@testable import ValidationCore

final class SchemaTests: XCTestCase {
    @MainActor func testCandidateSidecarsCommitWithDraftAndOutbox() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        let container = try CandidateStore.open(url)
        let c = ModelContext(container); c.autosaveEnabled = false
        let draft = CaptureDraftRecord(name: "Fixture", createdAt: .now, updatedAt: .now, captureSource: .manual)
        c.insert(draft)
        let profile = WardrobeProfile(ownerID: draft.id, size: "M", material: "cotton"); c.insert(profile)
        c.insert(DurableIntent(entityID: draft.id, revision: 1, kind: "draft", payload: Data(), scope: "local-test"))
        try c.save()
        let reopened = try CandidateStore.open(url)
        let read = ModelContext(reopened)
        XCTAssertEqual(try read.fetch(FetchDescriptor<CaptureDraftRecord>()).map(\.id), [draft.id])
        XCTAssertEqual(try read.fetch(FetchDescriptor<WardrobeProfile>()).map(\.id), [profile.id])
        XCTAssertEqual(try read.fetch(FetchDescriptor<DurableIntent>()).count, 1)
    }
}
