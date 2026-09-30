import Foundation
import ValidationCore
import Darwin

@main struct ValidationCLI {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else { throw ValidationFailure.invariant("usage: legacy|verify <directory>; migrate <source> <clone>") }
        let root = URL(fileURLWithPath: args[2])
        switch args[1] {
        case "crash-capture":
            guard args.count == 4 else { throw ValidationFailure.invariant("checkpoint required") }
            let target = args[3]
            let chain = try LocalChain(root: root)
            _ = try chain.capture(MediaFiles.syntheticJPEG(), checkpoint: { phase in
                if phase == target {
                    FileHandle.standardOutput.write(Data("CHECKPOINT \(phase)\n".utf8))
                    raise(SIGSTOP)
                }
            })
        case "crash-migrate":
            guard args.count == 5 else { throw ValidationFailure.invariant("clone path and checkpoint required") }
            try LegacyFixture.migrateClone(from: root, to: URL(fileURLWithPath: args[3]), checkpoint: { phase in
                if phase == args[4] {
                    FileHandle.standardOutput.write(Data("CHECKPOINT \(phase)\n".utf8))
                    raise(SIGSTOP)
                }
            })
        case "recover-capture":
            let chain = try LocalChain(root: root)
            try chain.recover()
            let result = try JSONSerialization.data(withJSONObject: chain.counts(), options: [.sortedKeys])
            FileHandle.standardOutput.write(result + Data("\n".utf8))
        case "confirm":
            guard args.count == 4, let id = UUID(uuidString: args[3]) else { throw ValidationFailure.invariant("draft ID required") }
            let chain = try LocalChain(root: root); _ = try chain.confirm(id)
            print(String(decoding: try JSONSerialization.data(withJSONObject: chain.counts(), options: [.sortedKeys]), as: UTF8.self))
        case "prepare-preview-failure":
            let chain = try LocalChain(root: root)
            do { _ = try chain.capture(MediaFiles.syntheticJPEG(), fault: .previewWrite) }
            catch LocalFault.previewWrite { print("EXPECTED_PREVIEW_FAILURE") }
        case "simulate-legacy-delivery":
            guard args.count == 5, let maximum = Int(args[4]), maximum > 0 else { throw ValidationFailure.invariant("target directory and batch bound required") }
            let result = try LegacyFixture.simulateDelivery(from: root, to: URL(fileURLWithPath: args[3]), maximum: maximum)
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
        case "legacy-sync":
            try LegacyFixture.generateSyncFixture(at: root)
            print("Legacy JPEG fixture generated")
        case "bootstrap-legacy":
            guard args.count == 5, let sourceID = UUID(uuidString: args[3]), let itemID = UUID(uuidString: args[4]) else { throw ValidationFailure.invariant("explicit source and item IDs required") }
            let chain = try LocalChain(root: root)
            try chain.bootstrapLegacy(sourceID: sourceID, itemIDs: [itemID])
            print(String(decoding: try JSONSerialization.data(withJSONObject: chain.counts(), options: [.sortedKeys]), as: UTF8.self))
        case "legacy":
            let summary = try LegacyFixture.generate(at: root)
            print("Legacy generated: \(summary.items.count) items, \(summary.drafts.count) drafts, \(summary.media.count) media")
        case "migrate":
            guard args.count == 4 else { throw ValidationFailure.invariant("clone path required") }
            try LegacyFixture.migrateClone(from: root, to: URL(fileURLWithPath: args[3]))
            print("Candidate migration preserves complete legacy snapshot")
        case "verify":
            try LegacyFixture.verifyCandidate(at: root)
            print("Candidate reopen preserves complete legacy snapshot")
        default: throw ValidationFailure.invariant("unknown command")
        }
    }
}
