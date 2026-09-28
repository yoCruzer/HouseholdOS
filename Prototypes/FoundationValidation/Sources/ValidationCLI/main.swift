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
