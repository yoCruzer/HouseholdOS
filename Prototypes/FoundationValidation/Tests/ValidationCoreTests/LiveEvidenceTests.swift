import XCTest
@testable import ValidationCore

final class LiveEvidenceTests: XCTestCase {
    func testInterruptedAttemptSurvivesReloadWithoutClaimingSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("live-evidence.json")
        try LiveEvidence.append(at: url, action: "original-download", outcome: "STARTED", report: ["originalFetchRequests": "1"])
        let resumed = try LiveEvidence.load(url)
        XCTAssertEqual(resumed.observations.count, 1)
        XCTAssertEqual(resumed.observations[0].outcome, "STARTED")
        XCTAssertNil(resumed.observations[0].report["targetOriginalHash"])
        try LiveEvidence.append(at: url, action: "metadata", outcome: "COMPLETED", report: resumed.observations[0].report)
        try LiveEvidence.append(at: url, action: "manual-control", outcome: "STARTED", report: [:])
        XCTAssertEqual(try LiveEvidence.load(url).observations.count, 3)
        XCTAssertEqual(try LiveEvidence.load(url).observations.last?.report["originalFetchRequests"], "1")
    }
    func testConnectionReservationsCannotBypassEndpointBudgetAfterReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("budget.json")
        _ = try LiveEvidence.reserveEndpoint(50 * 1024 * 1024 - 8192, at: url)
        XCTAssertThrowsError(try LiveEvidence.reserveEndpoint(4096, at: url))
        XCTAssertEqual(try LiveBudget.load(url).estimatedBytes, 50 * 1024 * 1024 - 4096)
        XCTAssertThrowsError(try LiveEvidence.reserveEndpoint(-1, at: url))
    }
}
