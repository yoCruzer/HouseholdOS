import SwiftUI

enum RootTab: Hashable {
    case items
    case drafts
    case capture
}

enum DeletedRecordKind: String {
    case draft = "Draft"
    case item = "Item"
}

struct MediaDeletionNotice: Identifiable {
    let id = UUID()
    let kind: DeletedRecordKind

    var title: String {
        "\(kind.rawValue) record deleted"
    }

    var message: String {
        "The \(kind.rawValue.lowercased()) record was deleted, but some local photo "
            + "files could not be removed. HouseholdOS will retry during later "
            + "maintenance or the next launch. There is no manual maintenance "
            + "control at this time."
    }

    static func make(
        kind: DeletedRecordKind,
        result: MediaMaintenanceResult
    ) -> MediaDeletionNotice? {
        result.isComplete ? nil : MediaDeletionNotice(kind: kind)
    }
}

private enum HouseholdNotice: Identifiable {
    case deletion(MediaDeletionNotice)
    case refresh(LibraryRefreshFailure)

    var id: UUID {
        switch self {
        case .deletion(let notice):
            notice.id
        case .refresh(let failure):
            failure.id
        }
    }
}

struct RootView: View {
    @State private var selectedTab: RootTab = .items
    @State private var notice: HouseholdNotice?

    var body: some View {
        TabView(selection: $selectedTab) {
            ItemLibraryView(
                selectedTab: $selectedTab,
                reportDeletion: reportDeletion
            )
                .tabItem {
                    Label("Items", systemImage: "shippingbox")
                }
                .tag(RootTab.items)

            DraftInboxView(
                selectedTab: $selectedTab,
                reportDeletion: reportDeletion
            )
                .tabItem {
                    Label("Drafts", systemImage: "tray.full")
                }
                .badge(draftBadge)
                .tag(RootTab.drafts)

            CaptureView(
                selectedTab: $selectedTab,
                reportDeletion: reportDeletion
            )
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(RootTab.capture)
        }
        .tint(.indigo)
        .onChange(of: library.refreshFailure) { _, failure in
            if let failure {
                notice = .refresh(failure)
            }
        }
        .alert(item: $notice) { notice in
            switch notice {
            case .deletion(let deletion):
                Alert(
                    title: Text(deletion.title),
                    message: Text(deletion.message),
                    dismissButton: .default(Text("OK"))
                )
            case .refresh:
                Alert(
                    title: Text("Saved, but the display needs to reload"),
                    message: Text(
                        "Your data was saved, but the current view could not refresh. "
                            + "Reload is safe and will not repeat the change."
                    ),
                    primaryButton: .default(Text("Reload"), action: retrySnapshot),
                    secondaryButton: .cancel(Text("Later"))
                )
            }
        }
    }

    @EnvironmentObject private var library: ItemLibraryService

    private var draftBadge: Int {
        library.drafts.count
    }

    private func reportDeletion(
        _ kind: DeletedRecordKind,
        _ result: MediaMaintenanceResult
    ) {
        if let deletion = MediaDeletionNotice.make(kind: kind, result: result) {
            notice = .deletion(deletion)
        }
    }

    private func retrySnapshot() {
        Task {
            await Task.yield()
            do {
                try library.recoverSnapshot()
            } catch {
                if let failure = library.refreshFailure {
                    notice = .refresh(failure)
                }
            }
        }
    }
}
