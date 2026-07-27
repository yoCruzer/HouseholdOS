import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ItemLibraryView: View {
    @Binding var selectedTab: RootTab

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
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if library.items.isEmpty {
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
                            ItemDetailView(itemID: item.id)
                        } label: {
                            ItemRow(item: item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Items")
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

    private var visibleItems: [ItemRecord] {
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
        if library.items.isEmpty {
            return "No items yet"
        }
        return "No matching items"
    }

    private var emptyDescription: String {
        if library.items.isEmpty {
            return "Confirmed drafts will appear in your household library."
        }
        return "Try another search, category or archive setting."
    }

    private var filterMenu: some View {
        Menu {
            Picker("Category", selection: $selectedCategoryID) {
                Text("All Categories").tag(UUID?.none)
                ForEach(library.categories, id: \.id) { category in
                    Text(category.name).tag(Optional(category.id))
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
    let item: ItemRecord

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

                if let category = library.categoryName(for: item.categoryID) {
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

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ItemLibraryService
    @State private var showsEditor = false
    @State private var showsDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let item {
                List {
                    if !assets.isEmpty {
                        Section("Photos") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(assets, id: \.id) { asset in
                                        MediaThumbnailView(asset: asset, size: 180)
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
                            value: library.categoryName(for: item.categoryID) ?? "Uncategorized"
                        )
                        LabeledContent(
                            "Location",
                            value: library.locationName(for: item.locationID) ?? "Not recorded"
                        )
                        LabeledContent(
                            "Status",
                            value: item.status == .archived ? "Archived" : "Active"
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
                                    item.status == .archived ? "Restore Item" : "Archive Item",
                                    systemImage: item.status == .archived
                                        ? "arrow.uturn.backward"
                                        : "archivebox"
                                )
                            }
                            Button("Delete Permanently", role: .destructive) {
                                showsDeleteConfirmation = true
                            }
                        } label: {
                            Label("More actions", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showsEditor) {
                    NavigationStack {
                        ItemEditorView(itemID: itemID)
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
        .confirmationDialog(
            "Delete this item and its photos permanently?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive, action: deleteItem)
        } message: {
            Text("Archive the item instead if you may need it later.")
        }
        .alert("Couldn’t update item", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var item: ItemRecord? {
        library.items.first(where: { $0.id == itemID })
    }

    private var assets: [MediaAssetRecord] {
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
        do {
            try library.deleteItem(id: itemID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ItemEditorView: View {
    let itemID: UUID

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
    @State private var errorMessage: String?

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

            MediaGridView(assets: assets) { asset in
                pendingMediaID = asset.id
                showsRemovePhotoConfirmation = true
            }

            Section {
                Button {
                    showsPhotoPicker = true
                } label: {
                    Label("Add from Photos", systemImage: "photo.badge.plus")
                }

                Button(action: openCamera) {
                    Label("Take Photo", systemImage: "camera")
                }
                .disabled(!cameraAvailable)
            }
        }
        .navigationTitle("Edit Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .accessibilityIdentifier("item.save")
            }
        }
        .onAppear(perform: loadFieldsIfNeeded)
        .sheet(isPresented: $showsPhotoPicker) {
            PhotoLibraryPicker(completion: handlePhotoResult)
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(completion: handleCameraResult)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Remove this photo permanently?",
            isPresented: $showsRemovePhotoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Photo", role: .destructive, action: removePendingPhoto)
        }
        .alert("Couldn’t save item", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var item: ItemRecord? {
        library.items.first(where: { $0.id == itemID })
    }

    private var assets: [MediaAssetRecord] {
        library.media(for: .item, ownerID: itemID)
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
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
        do {
            try library.updateItem(
                id: itemID,
                name: name,
                categoryID: categoryID,
                locationID: locationID,
                note: note
            )
            dismiss()
        } catch {
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
        do {
            try library.removeMedia(id: pendingMediaID)
            self.pendingMediaID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            errorMessage = "Camera access is unavailable. You can use Photos instead."
        case .authorized, .notDetermined:
            showsCamera = true
        @unknown default:
            errorMessage = "Camera access is unavailable."
        }
    }

    private func handlePhotoResult(
        _ result: Result<PickedMediaFile?, MediaPickerError>
    ) {
        showsPhotoPicker = false
        switch result {
        case .success(.none):
            return
        case .success(.some(let pickedFile)):
            defer { try? FileManager.default.removeItem(at: pickedFile.temporaryURL) }
            do {
                try library.addMediaFile(
                    at: pickedFile.temporaryURL,
                    contentTypeIdentifier: pickedFile.contentTypeIdentifier,
                    ownerKind: .item,
                    ownerID: itemID
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleCameraResult(_ result: Result<Data?, MediaPickerError>) {
        showsCamera = false
        switch result {
        case .success(.none):
            return
        case .success(.some(let data)):
            do {
                try library.addMediaData(
                    data,
                    contentTypeIdentifier: UTType.jpeg.identifier,
                    ownerKind: .item,
                    ownerID: itemID
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
