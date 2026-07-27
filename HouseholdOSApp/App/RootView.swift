import SwiftUI

enum RootTab: Hashable {
    case items
    case drafts
    case capture
}

struct RootView: View {
    @State private var selectedTab: RootTab = .items

    var body: some View {
        TabView(selection: $selectedTab) {
            ItemLibraryView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Items", systemImage: "shippingbox")
                }
                .tag(RootTab.items)

            DraftInboxView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Drafts", systemImage: "tray.full")
                }
                .badge(draftBadge)
                .tag(RootTab.drafts)

            CaptureView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(RootTab.capture)
        }
        .tint(.indigo)
    }

    @EnvironmentObject private var library: ItemLibraryService

    private var draftBadge: Int {
        library.drafts.count
    }
}
