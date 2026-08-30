import SwiftUI

@main
struct HouseholdOSApp: App {
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            if let library = runtime.library {
                RootView()
                    .environmentObject(library)
            } else {
                ContentUnavailableView(
                    "HouseholdOS couldn’t open",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(
                        runtime.startupError
                            ?? "The local library is unavailable. Your files were not deleted."
                    )
                )
                .padding()
            }
        }
    }
}
