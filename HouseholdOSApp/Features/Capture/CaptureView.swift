import AVFoundation
import SwiftUI
import UIKit

struct CaptureView: View {
    @Binding var selectedTab: RootTab
    let reportDeletion: (DeletedRecordKind, UUID, MediaMaintenanceResult) -> Void
    let reportMediaRemoval: (UUID, MediaMaintenanceResult) -> Void

    @EnvironmentObject private var library: ItemLibraryService
    @State private var editingDraftID: UUID?
    @State private var showsDraftEditor = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var isImportingMedia = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "shippingbox.and.arrow.backward")
                            .font(.system(size: 44))
                            .foregroundStyle(.indigo)
                        Text("Add one household item")
                            .font(.largeTitle.bold())
                        Text(
                            "Start with a photo or an empty draft. "
                                + "You can fill in the details later."
                        )
                        .foregroundStyle(.secondary)
                    }

                    captureButton(
                        title: "Choose a photo",
                        subtitle: "Keep the selected original in HouseholdOS",
                        systemImage: "photo.on.rectangle",
                        action: { showsPhotoPicker = true }
                    )
                    .disabled(isImportingMedia)
                    .accessibilityIdentifier("capture.photoLibrary")

                    captureButton(
                        title: "Take a photo",
                        subtitle: cameraAvailable
                            ? "Capture now and continue in a saved draft"
                            : "Camera is unavailable on this device",
                        systemImage: "camera",
                        action: openCamera
                    )
                    .disabled(!cameraAvailable || isImportingMedia)
                    .accessibilityIdentifier("capture.camera")

                    captureButton(
                        title: "Start without a photo",
                        subtitle: "Create a saved draft immediately",
                        systemImage: "square.and.pencil",
                        action: startManualDraft
                    )
                    .disabled(isImportingMedia)
                    .accessibilityIdentifier("capture.manual")

                    if isImportingMedia {
                        ProgressView("Saving photo…")
                    }

                    Label(
                        "A formal item only requires a name. "
                            + "Photos, category, location and notes stay optional.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Add")
            .sheet(isPresented: $showsPhotoPicker) {
                PhotoLibraryPicker(completion: handlePhotoResult)
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker(completion: handleCameraResult)
                    .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $showsDraftEditor) {
                if let editingDraftID {
                    DraftEditorView(
                        draftID: editingDraftID,
                        onConfirmed: {
                            showsDraftEditor = false
                            selectedTab = .items
                        },
                        onDeleted: { result in
                            reportDeletion(.draft, editingDraftID, result)
                            showsDraftEditor = false
                            selectedTab = .drafts
                        },
                        onMediaRemoval: reportMediaRemoval
                    )
                }
            }
            .alert(
                "Couldn’t complete that action",
                isPresented: errorBinding
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Try again or continue without a photo.")
            }
        }
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

    private func captureButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.secondary.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func startManualDraft() {
        do {
            let draft = try library.createDraft(source: .manual)
            presentEditor(for: draft.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            errorMessage = "Camera access is unavailable. Choose a photo or start without one."
        case .authorized, .notDetermined:
            showsCamera = true
        @unknown default:
            errorMessage = "Camera access is unavailable. Choose a photo or start without one."
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
            isImportingMedia = true
            Task {
                defer { isImportingMedia = false }
                let draft: DraftValue
                do {
                    draft = try library.createDraft(source: .photoLibrary).value
                } catch {
                    errorMessage = error.localizedDescription
                    await discardPickedMediaFile(pickedFile)
                    return
                }
                do {
                    try await library.addMediaFile(
                        at: pickedFile.temporaryURL,
                        contentTypeIdentifier: pickedFile.contentTypeIdentifier,
                        ownerKind: .draft,
                        ownerID: draft.id
                    )
                } catch {
                    errorMessage = "The draft was saved, but the photo could not be added."
                    await discardPickedMediaFile(pickedFile)
                    presentEditor(for: draft.id)
                    return
                }
                await discardPickedMediaFile(pickedFile)
                presentEditor(for: draft.id)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleCameraResult(
        _ result: Result<PickedMediaFile?, MediaPickerError>
    ) {
        showsCamera = false
        switch result {
        case .success(.none):
            return
        case .success(.some(let pickedFile)):
            isImportingMedia = true
            Task {
                defer { isImportingMedia = false }
                let draft: DraftValue
                do {
                    draft = try library.createDraft(source: .camera).value
                } catch {
                    errorMessage = error.localizedDescription
                    await discardPickedMediaFile(pickedFile)
                    return
                }
                do {
                    try await library.addMediaFile(
                        at: pickedFile.temporaryURL,
                        contentTypeIdentifier: pickedFile.contentTypeIdentifier,
                        ownerKind: .draft,
                        ownerID: draft.id
                    )
                } catch {
                    errorMessage = "The draft was saved, but the photo could not be added."
                    await discardPickedMediaFile(pickedFile)
                    presentEditor(for: draft.id)
                    return
                }
                await discardPickedMediaFile(pickedFile)
                presentEditor(for: draft.id)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func presentEditor(for draftID: UUID) {
        editingDraftID = draftID
        showsDraftEditor = true
    }
}
