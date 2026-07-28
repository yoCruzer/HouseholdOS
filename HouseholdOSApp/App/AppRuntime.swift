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
            if isUITesting {
                try FileManager.default.createDirectory(
                    at: uiTestingRoot,
                    withIntermediateDirectories: true
                )
                container = try PersistenceController.makeContainer(
                    storeURL: uiTestingRoot.appendingPathComponent("HouseholdOS.store")
                )
                mediaStore = try MediaFileStore(
                    rootURL: uiTestingRoot.appendingPathComponent("Media", isDirectory: true)
                )
            } else {
                container = try PersistenceController.makeContainer()
                mediaStore = try MediaFileStore.applicationSupport()
            }

            let library = ItemLibraryService(
                context: container.mainContext,
                mediaStore: mediaStore
            )
            try library.bootstrap()
            self.container = container
            self.library = library
            self.startupError = nil
            Task {
                await library.performStartupMediaMaintenance()
            }
        } catch {
            self.container = nil
            self.library = nil
            self.startupError = error.localizedDescription
        }
    }
}
