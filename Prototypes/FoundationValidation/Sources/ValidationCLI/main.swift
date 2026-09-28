import Foundation
import ValidationCore

@main struct ValidationCLI {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else { throw ValidationFailure.invariant("usage: legacy|verify <directory>; migrate <source> <clone>") }
        let root = URL(fileURLWithPath: args[2])
        switch args[1] {
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
