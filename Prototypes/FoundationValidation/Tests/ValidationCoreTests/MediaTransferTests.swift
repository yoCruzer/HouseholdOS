import XCTest
import SwiftData
import CloudKit
import ImageIO
import UniformTypeIdentifiers
@testable import ValidationCore

final class MediaTransferTests: XCTestCase {
    @MainActor func fixture(_ body: (LocalChain, SyncCore, MediaTransfers, UUID) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        _ = try chain.capture(MediaFiles.syntheticJPEG())
        let core = try SyncCore.local(context: chain.context, library: chain.libraryID, root: root)
        try core.setEnabled(true); try core.finishBootstrap(callback: core.session.scope)
        let media = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
        try body(chain, core, MediaTransfers(chain: chain, core: core), media.id)
    }
    @MainActor func testOldUploadAckAndDownloadCannotReplaceNewRepresentation() throws {
        try fixture { chain, core, transfers, id in
            try transfers.setPolicy(.appOwnedOriginals)
            let old = try transfers.beginUpload(id)
            let oldBytes = try Data(contentsOf: chain.root.appendingPathComponent(transfers.current(id).relativePath))
            let newer = try MediaFiles.syntheticJPEG(seed: 99)
            try transfers.replace(id, bytes: newer)
            XCTAssertFalse(try transfers.acknowledge(old))
            XCTAssertFalse(try transfers.receive(oldBytes, for: old))
            XCTAssertEqual(try Data(contentsOf: chain.root.appendingPathComponent(transfers.current(id).relativePath)), newer)
            XCTAssertEqual(try chain.context.fetch(FetchDescriptor<MediaRepresentation>()).filter { $0.mediaID == id }.count, 2)
            let reopened = try LocalChain(root: chain.root)
            let resumedCore = try SyncCore.local(context: reopened.context, library: reopened.libraryID, root: reopened.root)
            let resumed = try MediaTransfers(chain: reopened, core: resumedCore)
            XCTAssertEqual(resumed.state.tickets.first?.phase, "acknowledged-old-representation")
            XCTAssertEqual(try resumed.current(id).revision, 2)
            XCTAssertEqual(try resumed.beginUpload(id).representationID, try resumed.current(id).id)
        }
    }
    @MainActor func testImmutableRepresentationRejectsChangeBeforeReplacingPreview() throws {
        try fixture { chain, core, _, id in
            let wire = try JSONDecoder().decode(WireRecord.self, from: XCTUnwrap(core.document(id)).payload)
            try core.write(wire)
            let asset = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
            let path = chain.root.appendingPathComponent("media/" + (try XCTUnwrap(asset.thumbnailFileName)))
            let preview = try Data(contentsOf: path)
            for corruptHash in [true, false] {
                var changed = wire; changed.operationID = UUID(); changed.revision += 1
                changed.media?.preview = Data("different preview".utf8)
                if corruptHash { changed.media?.hash = String(repeating: "b", count: 64) }
                XCTAssertThrowsError(try core.write(changed))
                XCTAssertEqual(try Data(contentsOf: path), preview)
                XCTAssertEqual(try core.document(id)?.payload, try wire.encoded())
            }
        }
    }

    @MainActor func testPolicyDowngradeDoesNotDeleteCloudCopyAndPhotosSafetyCopyDoesNotEscalateUpload() throws {
        try fixture { chain, core, transfers, id in
            try transfers.setPolicy(.appOwnedOriginals)
            let inFlight = try transfers.beginUpload(id)
            try transfers.setPolicy(.preview)
            XCTAssertTrue(try transfers.acknowledge(inFlight), "already-sent original remains known on cloud after downgrade")
            XCTAssertThrowsError(try transfers.beginUpload(id))
            XCTAssertEqual(transfers.state.tickets.first?.phase, "acknowledged")
            try transfers.setPolicy(.appOwnedOriginals)
            let representation = try transfers.current(id)
            representation.photosReference = "synthetic-cloud-reference"
            try core.commit()
            XCTAssertThrowsError(try transfers.beginUpload(id), "Photos reference plus local safety copy does not duplicate originals by default")
            XCTAssertTrue(FileManager.default.fileExists(atPath: chain.root.appendingPathComponent(representation.relativePath).path))
        }
    }
    @MainActor func testQuotaBackoffAndOffAreConservative() throws {
        try fixture { chain, core, transfers, id in
            try transfers.setPolicy(.appOwnedOriginals)
            let ticket = try transfers.beginUpload(id)
            let now = Date(timeIntervalSince1970: 100)
            try transfers.serviceFailed(CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 60]), callback: core.session.scope, now: now)
            XCTAssertThrowsError(try transfers.beginUpload(id, now: now.addingTimeInterval(10)))
            let resumed = try MediaTransfers(chain: chain, core: core)
            XCTAssertThrowsError(try resumed.downloadTicket(id, now: now.addingTimeInterval(10)))
            XCTAssertEqual(try resumed.downloadTicket(id, now: now.addingTimeInterval(61)).representationID, ticket.representationID)
            XCTAssertEqual(try transfers.beginUpload(id, now: now.addingTimeInterval(61)), ticket)
            try transfers.serviceFailed(CKError(.quotaExceeded), callback: core.session.scope)
            XCTAssertThrowsError(try transfers.beginUpload(id))
            XCTAssertThrowsError(try MediaTransfers(chain: chain, core: core).downloadTicket(id))
            try core.setEnabled(false)
            XCTAssertFalse(try transfers.acknowledge(ticket))
            XCTAssertEqual(transfers.state.tickets.first?.phase, "prepared", "OFF does not assert server cancellation")
        }
    }
    func testRepresentativePlanAndBudgetSurviveReload() throws {
        let media = (0..<50).map { PlannedMedia(id: UUID(), previewBytes: 32_000, originalBytes: 2_000_000, photosBacked: $0 % 2 == 0) }
        let plan = MediaPlanner.plan(itemCount: 250, media: media, policy: .appOwnedOriginals)
        XCTAssertEqual(plan.first?.kind, "metadata")
        XCTAssertTrue(plan.dropFirst().prefix(50).allSatisfy { $0.kind == "preview" })
        XCTAssertEqual(plan.filter { $0.kind == "original" }.count, 25)
        XCTAssertEqual(MediaPlanner.plan(itemCount: 250, media: media, policy: .dataOnly).count, 1)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("budget.json")
        var budget = try LiveBudget.load(url)
        try budget.reserve(payloadBytes: 1024, at: url)
        var resumed = try LiveBudget.load(url)
        XCTAssertEqual(resumed.estimatedBytes, 5120)
        XCTAssertThrowsError(try resumed.reserve(payloadBytes: 100 * 1024 * 1024, at: url))
        XCTAssertEqual(try LiveBudget.load(url).estimatedBytes, 5120)
    }
    @MainActor func testStaticHEICAndTwoPreviewSizes() throws {
        let jpeg = try MediaFiles.syntheticJPEG(seed: 7)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.heic.identifier as CFString, 1, nil), "Installed platform HEIC encoder required")
        CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = output as Data
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chain = try LocalChain(root: root)
        _ = try chain.capture(bytes)
        let media = try XCTUnwrap(chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).first)
        XCTAssertEqual(media.contentTypeIdentifier, "public.heic")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("media/" + media.originalFileName)), bytes)
        for size in [128, 256] {
            let preview = try MediaFiles.preview(bytes, maxPixel: size)
            let decoded = try XCTUnwrap(CGImageSourceCreateWithData(preview as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            XCTAssertEqual(max(image.width, image.height), size)
            XCTAssertLessThan(preview.count, 100_000)
        }
    }
}
