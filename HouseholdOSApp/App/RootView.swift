import SwiftUI

enum RootTab: Hashable {
    case items
    case drafts
    case capture
}

enum DeletedRecordKind: Hashable {
    case draft
    case item
}

enum TransientNoticeKey: Hashable {
    case recordDeletion(DeletedRecordKind, UUID)
    case mediaRemoval(UUID)
}

struct TransientNotice: Identifiable, Equatable {
    let id: TransientNoticeKey
    let title: String
    let message: String
}

struct TransientNoticeQueue: Equatable {
    private(set) var active: TransientNotice?
    private(set) var pending: [TransientNotice] = []

    mutating func enqueue(_ notice: TransientNotice) {
        guard active?.id != notice.id,
              !pending.contains(where: { $0.id == notice.id }) else {
            return
        }
        if active == nil {
            active = notice
        } else {
            pending.append(notice)
        }
    }

    mutating func dismissActive() {
        active = pending.isEmpty ? nil : pending.removeFirst()
    }
}

struct MediaDeletionNotice {
    static func make(
        kind: DeletedRecordKind,
        recordID: UUID,
        result: MediaMaintenanceResult
    ) -> TransientNotice? {
        guard !result.isComplete else { return nil }
        switch kind {
        case .draft:
            return TransientNotice(
                id: .recordDeletion(kind, recordID),
                title: String(localized: "Draft record deleted"),
                message: String(
                    localized: "The draft record was deleted, but some local photo files could not be removed. HouseholdOS will retry during later maintenance or the next launch. There is no manual maintenance control at this time."
                )
            )
        case .item:
            return TransientNotice(
                id: .recordDeletion(kind, recordID),
                title: String(localized: "Item record deleted"),
                message: String(
                    localized: "The item record was deleted, but some local photo files could not be removed. HouseholdOS will retry during later maintenance or the next launch. There is no manual maintenance control at this time."
                )
            )
        }
    }
}

struct MediaRemovalNotice {
    static func make(
        mediaID: UUID,
        result: MediaMaintenanceResult
    ) -> TransientNotice? {
        guard !result.isComplete else { return nil }
        return TransientNotice(
            id: .mediaRemoval(mediaID),
            title: String(localized: "Photo record deleted"),
            message: String(
                localized: "The photo record was deleted, but some local photo files remain. HouseholdOS will retry them during later maintenance or the next launch."
            )
        )
    }
}

struct RootView: View {
    @State private var selectedTab: RootTab = .items
    @State private var transientNotices = TransientNoticeQueue()
    @State private var showsTransientNotice = false
    @State private var deferredRecovery = false
    @State private var isReloading = false

    @EnvironmentObject private var library: ItemLibraryService

    var body: some View {
        TabView(selection: $selectedTab) {
            ItemLibraryView(
                selectedTab: $selectedTab,
                reportDeletion: reportDeletion,
                reportMediaRemoval: reportMediaRemoval
            )
            .tabItem {
                Label("Items", systemImage: "shippingbox")
                    .accessibilityIdentifier("tab.items")
            }
            .tag(RootTab.items)

            DraftInboxView(
                selectedTab: $selectedTab,
                reportDeletion: reportDeletion,
                reportMediaRemoval: reportMediaRemoval
            )
            .tabItem {
                Label("Drafts", systemImage: "tray.full")
                    .accessibilityIdentifier("tab.drafts")
            }
            .badge(library.displayDrafts.count)
            .tag(RootTab.drafts)

            CaptureView(
                selectedTab: $selectedTab,
                reportDeletion: reportDeletion,
                reportMediaRemoval: reportMediaRemoval
            )
            .tabItem {
                Label("Add", systemImage: "plus.circle.fill")
                    .accessibilityIdentifier("tab.add")
            }
            .tag(RootTab.capture)
        }
        .tint(.indigo)
        .safeAreaInset(edge: .top, spacing: 0) {
            if library.refreshRecoveryState != nil {
                recoveryBanner
            }
        }
        .onChange(of: library.refreshRecoveryState) { _, recovery in
            if recovery == nil {
                deferredRecovery = false
            }
        }
        .alert(
            transientNotices.active?.title ?? "",
            isPresented: $showsTransientNotice
        ) {
            Button("OK", action: advanceTransientNotice)
        } message: {
            Text(transientNotices.active?.message ?? "")
        }
    }

    private var recoveryBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Saved, but the display needs to reload", systemImage: "arrow.clockwise")
                .font(.headline)
                .accessibilityIdentifier("library.refreshBanner.title")
            if !deferredRecovery {
                Text(
                    "Your data is saved. The current display has not refreshed. Reload only reads the library and will not repeat the change."
                )
                .font(.footnote)
                .accessibilityIdentifier("library.refreshBanner.message")
            }
            HStack {
                Button(
                    isReloading
                        ? String(localized: "Reloading…")
                        : String(localized: "Reload"),
                    action: retrySnapshot
                )
                    .buttonStyle(.borderedProminent)
                    .disabled(isReloading)
                    .accessibilityIdentifier("library.refreshBanner.reload")
                if !deferredRecovery {
                    Button("Later") {
                        deferredRecovery = true
                    }
                    .accessibilityIdentifier("library.refreshBanner.later")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.refreshBanner")
    }

    private func reportDeletion(
        _ kind: DeletedRecordKind,
        _ recordID: UUID,
        _ result: MediaMaintenanceResult
    ) {
        if let notice = MediaDeletionNotice.make(
            kind: kind,
            recordID: recordID,
            result: result
        ) {
            transientNotices.enqueue(notice)
            showsTransientNotice = true
        }
    }

    private func reportMediaRemoval(
        _ mediaID: UUID,
        _ result: MediaMaintenanceResult
    ) {
        if let notice = MediaRemovalNotice.make(mediaID: mediaID, result: result) {
            transientNotices.enqueue(notice)
            showsTransientNotice = true
        }
    }

    private func advanceTransientNotice() {
        showsTransientNotice = false
        transientNotices.dismissActive()
        guard transientNotices.active != nil else { return }
        Task {
            await Task.yield()
            showsTransientNotice = true
        }
    }

    private func retrySnapshot() {
        isReloading = true
        Task {
            defer { isReloading = false }
            do {
                try library.recoverSnapshot()
            } catch {
                // The persistent recovery state remains the user's safe retry boundary.
            }
        }
    }
}
