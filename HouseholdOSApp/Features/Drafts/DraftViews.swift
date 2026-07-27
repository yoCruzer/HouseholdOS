import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DraftInboxView: View {
    @Binding var selectedTab: RootTab

    @EnvironmentObject private var library: ItemLibraryService
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.drafts.isEmpty {
                    ContentUnavailableView {
                        Label("No drafts", systemImage: "tray")
                    } description: {
                        Text("Incomplete captures will stay here until you finish them.")
                    } actions: {
                        Button("Add an item") {
                            selectedTab = .capture
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(library.drafts, id: \.id) { draft in
                        NavigationLink(value: draft.id) {
                            DraftRow(draft: draft)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Drafts")
            .navigationDestination(for: UUID.self) { draftID in
                DraftEditorView(
                    draftID: draftID,
                    onConfirmed: {
                        path.removeAll()
                        selectedTab = .items
                    },
                    onDeleted: {
                        path.removeAll()
                    }
                )
            }
            .toolbar {
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
}

private struct DraftRow: View {
    let draft: CaptureDraftRecord

    @EnvironmentObject private var library: ItemLibraryService

    var body: some View {
        HStack(spacing: 12) {
            if let asset = library.media(for: .draft, ownerID: draft.id).first {
                MediaThumbnailView(asset: asset)
            } else {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 72)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.isEmpty ? "Untitled draft" : draft.name)
                    .font(.headline)
                Text(draft.updatedAt, format: .relative(presentation: .named))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let category = library.categoryName(for: draft.categoryID) {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("draft.row.\(draft.id.uuidString)")
    }
}

struct DraftEditorView: View {
    let draftID: UUID
    let onConfirmed: () -> Void
    let onDeleted: () -> Void

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
    @State private var showsDeleteConfirmation = false
    @State private var showsRemovePhotoConfirmation = false
    @State private var pendingMediaID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if draft != nil {
                Form {
                    CoreFieldsView(
                        name: $name,
                        categoryID: $categoryID,
                        locationID: $locationID,
                        note: $note,
                        newLocationName: $newLocationName,
                        nameIsRequired: false,
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

                    Section {
                        Button {
                            confirmDraft()
                        } label: {
                            Label("Move to Item Library", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("draft.confirm")

                        Text("A name is required only when you move this draft to the library.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Draft")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            _ = saveDraft()
                        }
                        .accessibilityIdentifier("draft.save")
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete Draft", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Draft unavailable",
                    systemImage: "tray",
                    description: Text("It may already have been confirmed or deleted.")
                )
            }
        }
        .onAppear(perform: loadFieldsIfNeeded)
        .onDisappear {
            if draft != nil {
                _ = saveDraft(showError: false)
            }
        }
        .sheet(isPresented: $showsPhotoPicker) {
            PhotoLibraryPicker(completion: handlePhotoResult)
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(completion: handleCameraResult)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Delete this draft and its photos?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Draft", role: .destructive, action: deleteDraft)
        }
        .confirmationDialog(
            "Remove this photo permanently?",
            isPresented: $showsRemovePhotoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Photo", role: .destructive, action: removePendingPhoto)
        }
        .alert("Couldn’t save", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var draft: CaptureDraftRecord? {
        library.drafts.first(where: { $0.id == draftID })
    }

    private var assets: [MediaAssetRecord] {
        library.media(for: .draft, ownerID: draftID)
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
        guard !didLoad, let draft else { return }
        name = draft.name
        categoryID = draft.categoryID
        locationID = draft.locationID
        note = draft.note ?? ""
        didLoad = true
    }

    @discardableResult
    private func saveDraft(showError: Bool = true) -> Bool {
        do {
            try library.updateDraft(
                id: draftID,
                name: name,
                categoryID: categoryID,
                locationID: locationID,
                note: note
            )
            return true
        } catch {
            if showError {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func confirmDraft() {
        guard saveDraft() else { return }
        do {
            _ = try library.confirmDraft(id: draftID)
            onConfirmed()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDraft() {
        do {
            try library.deleteDraft(id: draftID)
            onDeleted()
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
            errorMessage = "Camera access is unavailable. You can use Photos or continue without one."
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
                    ownerKind: .draft,
                    ownerID: draftID
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
                    ownerKind: .draft,
                    ownerID: draftID
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
