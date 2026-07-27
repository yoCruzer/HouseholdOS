import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct CaptureView: View {
    @Binding var selectedTab: RootTab

    @EnvironmentObject private var library: ItemLibraryService
    @State private var editingDraftID: UUID?
    @State private var showsDraftEditor = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
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
                    .accessibilityIdentifier("capture.photoLibrary")

                    captureButton(
                        title: "Take a photo",
                        subtitle: cameraAvailable
                            ? "Capture now and continue in a saved draft"
                            : "Camera is unavailable on this device",
                        systemImage: "camera",
                        action: openCamera
                    )
                    .disabled(!cameraAvailable)
                    .accessibilityIdentifier("capture.camera")

                    captureButton(
                        title: "Start without a photo",
                        subtitle: "Create a saved draft immediately",
                        systemImage: "square.and.pencil",
                        action: startManualDraft
                    )
                    .accessibilityIdentifier("capture.manual")

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
            .sheet(isPresented: $showsDraftEditor) {
                if let editingDraftID {
                    NavigationStack {
                        DraftEditorView(
                            draftID: editingDraftID,
                            onConfirmed: {
                                showsDraftEditor = false
                                selectedTab = .items
                            },
                            onDeleted: {
                                showsDraftEditor = false
                                selectedTab = .drafts
                            }
                        )
                    }
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
            defer { try? FileManager.default.removeItem(at: pickedFile.temporaryURL) }
            do {
                let draft = try library.createDraft(source: .photoLibrary)
                do {
                    try library.addMediaFile(
                        at: pickedFile.temporaryURL,
                        contentTypeIdentifier: pickedFile.contentTypeIdentifier,
                        ownerKind: .draft,
                        ownerID: draft.id
                    )
                } catch {
                    errorMessage = "The draft was saved, but the photo could not be added."
                }
                presentEditor(for: draft.id)
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
                let draft = try library.createDraft(source: .camera)
                do {
                    try library.addMediaData(
                        data,
                        contentTypeIdentifier: UTType.jpeg.identifier,
                        ownerKind: .draft,
                        ownerID: draft.id
                    )
                } catch {
                    errorMessage = "The draft was saved, but the photo could not be added."
                }
                presentEditor(for: draft.id)
            } catch {
                errorMessage = error.localizedDescription
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
