import AVFoundation
import SwiftUI
import UIKit

struct ItemLibraryView: View {
    @Binding var selectedTab: RootTab
    let reportDeletion: (DeletedRecordKind, UUID, MediaMaintenanceResult) -> Void
    let reportMediaRemoval: (UUID, MediaMaintenanceResult) -> Void

    @EnvironmentObject private var library: ItemLibraryService
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var includeArchived = false
    @State private var sort: LibrarySort = .newest

    var body: some View {
        NavigationStack {
            Group {
                if visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label(
                            emptyTitle,
                            systemImage: searchText.isEmpty ? "shippingbox" : "magnifyingglass"
                        )
                        .accessibilityIdentifier("items.empty.title")
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if library.displayItems.isEmpty {
                            Button("Add your first item") {
                                selectedTab = .capture
                            }
                            .buttonStyle(.borderedProminent)
                        } else if hasFilters {
                            Button("Clear filters", action: clearFilters)
                        }
                    }
                } else {
                    List(visibleItems, id: \.id) { item in
                        NavigationLink {
                            ItemDetailView(
                                itemID: item.id,
                                onDeleted: {
                                    reportDeletion(.item, item.id, $0)
                                },
                                onMediaRemoval: reportMediaRemoval
                            )
                        } label: {
                            ItemRow(item: item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Items")
            .accessibilityIdentifier("items.screen")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Name, note, category or location"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedTab = .capture
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                }
            }
        }
    }

    private var visibleItems: [ItemValue] {
        library.visibleItems(
            query: searchText,
            categoryID: selectedCategoryID,
            includeArchived: includeArchived,
            sort: sort
        )
    }

    private var hasFilters: Bool {
        !searchText.isEmpty || selectedCategoryID != nil || includeArchived || sort != .newest
    }

    private var emptyTitle: String {
        if library.displayItems.isEmpty {
            return String(localized: "No items yet")
        }
        return String(localized: "No matching items")
    }

    private var emptyDescription: String {
        if library.displayItems.isEmpty {
            return String(
                localized: "Confirmed drafts will appear in your household library."
            )
        }
        return String(localized: "Try another search, category or archive setting.")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Category", selection: $selectedCategoryID) {
                Text("All Categories").tag(UUID?.none)
                ForEach(library.displayCategories, id: \.id) { category in
                    Text(SystemCategoryLocalization.displayName(for: category))
                        .tag(Optional(category.id))
                }
            }

            Picker("Sort", selection: $sort) {
                Text("Newest").tag(LibrarySort.newest)
                Text("Oldest").tag(LibrarySort.oldest)
                Text("Name").tag(LibrarySort.name)
            }

            Toggle("Include Archived", isOn: $includeArchived)

            if hasFilters {
                Button("Clear Filters", action: clearFilters)
            }
        } label: {
            Label("Filter and sort", systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("items.filters")
    }

    private func clearFilters() {
        searchText = ""
        selectedCategoryID = nil
        includeArchived = false
        sort = .newest
    }
}

private struct ItemRow: View {
    let item: ItemValue

    @EnvironmentObject private var library: ItemLibraryService

    var body: some View {
        HStack(spacing: 12) {
            if let asset = library.media(for: .item, ownerID: item.id).first {
                MediaThumbnailView(asset: asset)
            } else {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 72)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.headline)
                    if item.status == .archived {
                        Text("Archived")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                if let category = library.categoryDisplayName(for: item.categoryID) {
                    Text(category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let location = library.locationName(for: item.locationID) {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("item.row.\(item.id.uuidString)")
    }
}

struct ItemDetailView: View {
    let itemID: UUID
    let onDeleted: (MediaMaintenanceResult) -> Void
    let onMediaRemoval: (UUID, MediaMaintenanceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ItemLibraryService
    @State private var showsEditor = false
    @State private var showsDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var viewedMedia: MediaValue?

    var body: some View {
        Group {
            if let item {
                List {
                    if !assets.isEmpty {
                        Section("Photos") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(assets, id: \.id) { asset in
                                        MediaThumbnailButton(
                                            asset: asset,
                                            size: 180,
                                            view: { viewedMedia = $0 }
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section("Overview") {
                        LabeledContent("Name", value: item.name)
                        LabeledContent(
                            "Category",
                            value: library.categoryDisplayName(for: item.categoryID)
                                ?? String(localized: "Uncategorized")
                        )
                        LabeledContent(
                            "Location",
                            value: library.locationName(for: item.locationID)
                                ?? String(localized: "Not recorded")
                        )
                        LabeledContent(
                            "Status",
                            value: item.status == .archived
                                ? String(localized: "Archived")
                                : String(localized: "Active")
                        )
                    }

                    if let note = item.note {
                        Section("Notes") {
                            Text(note)
                        }
                    }

                    Section("Record") {
                        LabeledContent(
                            "Created",
                            value: item.createdAt.formatted(date: .abbreviated, time: .shortened)
                        )
                        LabeledContent(
                            "Updated",
                            value: item.updatedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Edit") {
                            showsEditor = true
                        }
                        .accessibilityIdentifier("item.edit")

                        Menu {
                            Button {
                                toggleArchive()
                            } label: {
                                Label(
                                    item.status == .archived
                                        ? String(localized: "Restore Item")
                                        : String(localized: "Archive Item"),
                                    systemImage: item.status == .archived
                                        ? "arrow.uturn.backward"
                                        : "archivebox"
                                )
                            }
                            Button("Delete Permanently", role: .destructive) {
                                showsDeleteConfirmation = true
                            }
                            .accessibilityIdentifier("item.delete")
                        } label: {
                            Label("More actions", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showsEditor) {
                    NavigationStack {
                        ItemEditorView(
                            itemID: itemID,
                            onMediaRemoval: onMediaRemoval
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "Item unavailable",
                    systemImage: "shippingbox",
                    description: Text("It may have been deleted.")
                )
            }
        }
        .fullScreenCover(item: $viewedMedia) { asset in
            OriginalPhotoViewer(asset: asset) {
                viewedMedia = nil
            }
        }
        .confirmationDialog(
            "Delete this item and its photos permanently?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive, action: deleteItem)
                .accessibilityIdentifier("item.delete.confirm")
        } message: {
            Text("Archive the item instead if you may need it later.")
        }
        .alert("Couldn’t update item", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var item: ItemValue? {
        library.displayItems.first(where: { $0.id == itemID })
    }

    private var assets: [MediaValue] {
        library.media(for: .item, ownerID: itemID)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func toggleArchive() {
        guard let item else { return }
        do {
            try library.setArchived(item.status != .archived, itemID: itemID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem() {
        Task {
            do {
                let result = try await library.deleteItem(id: itemID)
                onDeleted(result.value)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ItemEditorView: View {
    let itemID: UUID
    let onMediaRemoval: (UUID, MediaMaintenanceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ItemLibraryService

    @State private var name = ""
    @State private var categoryID: UUID?
    @State private var locationID: UUID?
    @State private var note = ""
    @State private var newLocationName = ""
    @State private var didLoad = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var showsRemovePhotoConfirmation = false
    @State private var pendingMediaID: UUID?
    @State private var isProcessingMedia = false
    @State private var isSaving = false
    @State private var showsSaveSuccess = false
    @State private var errorMessage: String?
    @State private var viewedMedia: MediaValue?
    @State private var photoResultGate = CaptureResultGate()
    @State private var cameraResultGate = CaptureResultGate()

    var body: some View {
        Form {
            CoreFieldsView(
                name: $name,
                categoryID: $categoryID,
                locationID: $locationID,
                note: $note,
                newLocationName: $newLocationName,
                nameIsRequired: true,
                addLocation: addLocation
            )

            MediaGridView(
                assets: assets,
                view: { viewedMedia = $0 },
                remove: { asset in
                    pendingMediaID = asset.id
                    showsRemovePhotoConfirmation = true
                }
            )

            Section {
                Button {
                    openPhotoLibrary()
                } label: {
                    Label("Add from Photos", systemImage: "photo.badge.plus")
                }
                .disabled(isProcessingMedia)

                Button(action: openCamera) {
                    Label("Take Photo", systemImage: "camera")
                }
                .disabled(!cameraAvailable || isProcessingMedia)

                if isProcessingMedia {
                    ProgressView("Updating photos…")
                }
            }

            Section("Saving") {
                Text(
                    "Field changes are saved only when you tap Save. Photos and newly created locations are saved immediately. Close discards unsaved field changes."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("item.savingSemantics")
            }
        }
        .navigationTitle("Edit Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
                .accessibilityIdentifier("item.close")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(isSaving)
                    .accessibilityIdentifier("item.save")
            }
        }
        .onAppear(perform: loadFieldsIfNeeded)
        .sheet(isPresented: $showsPhotoPicker) {
            PhotoLibraryPicker(completion: handlePhotoResult)
        }
        .fullScreenCover(item: $viewedMedia) { asset in
            OriginalPhotoViewer(asset: asset) {
                viewedMedia = nil
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(completion: handleCameraResult)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Delete this photo permanently?",
            isPresented: $showsRemovePhotoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive, action: removePendingPhoto)
                .accessibilityIdentifier("item.photo.delete.confirm")
        }
        .alert("Couldn’t save item", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "Please try again."))
        }
        .overlay(alignment: .top) {
            if showsSaveSuccess {
                SaveSuccessBadge(accessibilityIdentifier: "item.saveSuccess")
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var item: ItemValue? {
        library.displayItems.first(where: { $0.id == itemID })
    }

    private var assets: [MediaValue] {
        library.media(for: .item, ownerID: itemID)
    }

    private var cameraAvailable: Bool {
        CameraAvailability.isAvailable
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadFieldsIfNeeded() {
        guard !didLoad, let item else { return }
        name = item.name
        categoryID = item.categoryID
        locationID = item.locationID
        note = item.note ?? ""
        didLoad = true
    }

    private func save() {
        isSaving = true
        do {
            _ = try library.updateItem(
                id: itemID,
                name: name,
                categoryID: categoryID,
                locationID: locationID,
                note: note
            )
            withAnimation {
                showsSaveSuccess = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private func addLocation() {
        do {
            let location = try library.createLocation(name: newLocationName)
            locationID = location.id
            newLocationName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePendingPhoto() {
        guard let pendingMediaID else { return }
        isProcessingMedia = true
        Task {
            defer { isProcessingMedia = false }
            do {
                let result = try await library.removeMedia(id: pendingMediaID)
                self.pendingMediaID = nil
                onMediaRemoval(pendingMediaID, result.value)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            errorMessage = String(
                localized: "Camera access is unavailable. You can use Photos instead."
            )
        case .authorized, .notDetermined:
            cameraResultGate.beginCapture()
            showsCamera = true
        @unknown default:
            errorMessage = String(localized: "Camera access is unavailable.")
        }
    }

    private func openPhotoLibrary() {
        photoResultGate.beginCapture()
        showsPhotoPicker = true
    }

    private func handlePhotoResult(
        _ result: Result<PickedMediaFile?, MediaPickerError>
    ) {
        showsPhotoPicker = false
        guard photoResultGate.claimResult() else {
            discardDuplicatePickedMediaResult(result)
            return
        }
        switch result {
        case .success(.none):
            return
        case .success(.some(let pickedFile)):
            isProcessingMedia = true
            Task {
                defer { isProcessingMedia = false }
                do {
                    try await library.addMediaFile(
                        at: pickedFile.temporaryURL,
                        contentTypeIdentifier: pickedFile.contentTypeIdentifier,
                        ownerKind: .item,
                        ownerID: itemID
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
                await discardPickedMediaFile(pickedFile)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleCameraResult(
        _ result: Result<PickedMediaFile?, MediaPickerError>
    ) {
        showsCamera = false
        guard cameraResultGate.claimResult() else {
            discardDuplicatePickedMediaResult(result)
            return
        }
        switch result {
        case .success(.none):
            return
        case .success(.some(let pickedFile)):
            isProcessingMedia = true
            Task {
                defer { isProcessingMedia = false }
                do {
                    try await library.addMediaFile(
                        at: pickedFile.temporaryURL,
                        contentTypeIdentifier: pickedFile.contentTypeIdentifier,
                        ownerKind: .item,
                        ownerID: itemID
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
                await discardPickedMediaFile(pickedFile)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
