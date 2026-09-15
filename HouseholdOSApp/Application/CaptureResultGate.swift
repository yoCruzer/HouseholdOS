import Foundation

@MainActor
final class CaptureResultGate {
    private var hasAcceptedResult = false

    func beginCapture() {
        hasAcceptedResult = false
    }

    func claimResult() -> Bool {
        guard !hasAcceptedResult else {
            return false
        }
        hasAcceptedResult = true
        return true
    }
}
