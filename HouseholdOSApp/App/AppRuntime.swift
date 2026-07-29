import Combine
import Foundation
import SwiftData

@MainActor
final class AppRuntime: ObservableObject {
    let container: ModelContainer?
    let library: ItemLibraryService?
    let startupError: String?

    init() {
        do {
            let environment = ProcessInfo.processInfo.environment
            let isUITesting = environment["HOUSEHOLDOS_UI_TESTING"] == "1"
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let uiTestingRoot = applicationSupport
                .appendingPathComponent("HouseholdOSUITesting", isDirectory: true)

            if isUITesting, environment["HOUSEHOLDOS_UI_TEST_RESET"] == "1" {
                try? FileManager.default.removeItem(at: uiTestingRoot)
            }

            let container: ModelContainer
            let mediaStore: MediaFileStore
            let refreshGate: UITestRefreshFailureGate?
            if isUITesting {
                try FileManager.default.createDirectory(
                    at: uiTestingRoot,
                    withIntermediateDirectories: true
                )
                container = try PersistenceController.makeContainer(
                    storeURL: uiTestingRoot.appendingPathComponent("HouseholdOS.store")
                )
                let failMediaRemoval =
                    environment["HOUSEHOLDOS_UI_TEST_FAIL_MEDIA_REMOVAL"] == "1"
                mediaStore = try MediaFileStore(
                    rootURL: uiTestingRoot.appendingPathComponent("Media", isDirectory: true),
                    removeFile: { url in
                        if failMediaRemoval {
                            throw AppRuntimeUITestError.injectedMediaRemovalFailure
                        }
                        try FileManager.default.removeItem(at: url)
                    }
                )
                refreshGate =
                    environment["HOUSEHOLDOS_UI_TEST_FAIL_NEXT_REFRESH"] == "1"
                    ? UITestRefreshFailureGate()
                    : nil
            } else {
                container = try PersistenceController.makeContainer()
                mediaStore = try MediaFileStore.applicationSupport()
                refreshGate = nil
            }

            let library = ItemLibraryService(
                context: container.mainContext,
                mediaStore: mediaStore,
                snapshotLoader: { context in
                    if refreshGate?.consumeFailure() == true {
                        throw AppRuntimeUITestError.injectedRefreshFailure
                    }
                    return try LibrarySnapshot.load(from: context)
                }
            )
            try library.bootstrap()
            refreshGate?.failNextRefresh()
            self.container = container
            self.library = library
            self.startupError = nil
            Task {
                await library.performStartupMediaMaintenance()
                if let deletionKind =
                    environment["HOUSEHOLDOS_UI_TEST_SEED_DELETION_KIND"] {
                    await Self.seedDeletionFixture(
                        deletionKind,
                        library: library
                    )
                }
            }
        } catch {
            self.container = nil
            self.library = nil
            self.startupError = error.localizedDescription
        }
    }

    private static func seedDeletionFixture(
        _ kind: String,
        library: ItemLibraryService
    ) async {
        do {
            let draft = try library.createDraft(
                source: .manual,
                name: kind == "item" ? "Residual Item" : "Residual Draft"
            )
            _ = try await library.addMediaData(
                Data("ui-test-photo".utf8),
                contentTypeIdentifier: "public.jpeg",
                ownerKind: .draft,
                ownerID: draft.id
            )
            if kind == "item" {
                _ = try library.confirmDraft(id: draft.id)
            }
        } catch {
            assertionFailure("Unable to seed deletion fixture: \(error)")
        }
    }
}

@MainActor
private final class UITestRefreshFailureGate {
    private var failuresRemaining = 0

    func failNextRefresh() {
        failuresRemaining = 1
    }

    func consumeFailure() -> Bool {
        guard failuresRemaining > 0 else {
            return false
        }
        failuresRemaining -= 1
        return true
    }
}

private enum AppRuntimeUITestError: LocalizedError {
    case injectedMediaRemovalFailure
    case injectedRefreshFailure

    var errorDescription: String? {
        switch self {
        case .injectedMediaRemovalFailure:
            "Injected UI test media removal failure"
        case .injectedRefreshFailure:
            "Injected UI test snapshot refresh failure"
        }
    }
}
