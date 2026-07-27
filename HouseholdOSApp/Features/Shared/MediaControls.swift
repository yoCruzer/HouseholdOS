@preconcurrency import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct PickedMediaFile: Sendable {
    let temporaryURL: URL
    let contentTypeIdentifier: String
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let completion: @MainActor @Sendable (Result<PickedMediaFile?, MediaPickerError>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: PHPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let completion:
            @MainActor @Sendable (Result<PickedMediaFile?, MediaPickerError>) -> Void

        init(
            completion: @escaping
                @MainActor @Sendable (Result<PickedMediaFile?, MediaPickerError>) -> Void
        ) {
            self.completion = completion
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            picker.dismiss(animated: true)
            guard let result = results.first else {
                completion(.success(nil))
                return
            }

            let provider = result.itemProvider
            let typeIdentifier = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .image) == true
            } ?? UTType.image.identifier

            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) {
                [completion] sourceURL, error in
                if let error {
                    Task { @MainActor in
                        completion(.failure(.readFailed(error.localizedDescription)))
                    }
                    return
                }

                guard let sourceURL else {
                    Task { @MainActor in
                        completion(.failure(MediaPickerError.missingFile))
                    }
                    return
                }

                let fileExtension = sourceURL.pathExtension.isEmpty
                    ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "img")
                    : sourceURL.pathExtension
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "householdos-picker-\(UUID().uuidString).\(fileExtension)"
                    )

                do {
                    try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
                    Task { @MainActor in
                        completion(
                            .success(
                                PickedMediaFile(
                                    temporaryURL: temporaryURL,
                                    contentTypeIdentifier: typeIdentifier
                                )
                            )
                        )
                    }
                } catch {
                    Task { @MainActor in
                        completion(.failure(.readFailed(error.localizedDescription)))
                    }
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let completion: @MainActor @Sendable (Result<Data?, MediaPickerError>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {
        private let completion:
            @MainActor @Sendable (Result<Data?, MediaPickerError>) -> Void

        init(
            completion: @escaping
                @MainActor @Sendable (Result<Data?, MediaPickerError>) -> Void
        ) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            completion(.success(nil))
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)

            do {
                if let imageURL = info[.imageURL] as? URL {
                    completion(.success(try Data(contentsOf: imageURL)))
                } else if let image = info[.originalImage] as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.95) {
                    completion(.success(data))
                } else {
                    completion(.failure(MediaPickerError.missingFile))
                }
            } catch {
                completion(.failure(.readFailed(error.localizedDescription)))
            }
        }
    }
}

enum MediaPickerError: LocalizedError, Sendable {
    case missingFile
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            "The selected image could not be read."
        case .readFailed(let message):
            "The selected image could not be copied: \(message)"
        }
    }
}

struct MediaThumbnailView: View {
    let asset: MediaAssetRecord
    var size: CGFloat = 72

    @EnvironmentObject private var library: ItemLibraryService

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: library.displayURL(for: asset).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Item photo")
    }
}

struct MediaGridView: View {
    let assets: [MediaAssetRecord]
    let remove: (MediaAssetRecord) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 88), spacing: 12)
    ]

    var body: some View {
        Section("Photos") {
            if assets.isEmpty {
                Label(
                    "No photo yet. You can still save this record.",
                    systemImage: "photo.badge.plus"
                )
                .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(assets, id: \.id) { asset in
                        ZStack(alignment: .topTrailing) {
                            MediaThumbnailView(asset: asset, size: 96)
                            Button(role: .destructive) {
                                remove(asset)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.65))
                            }
                            .accessibilityLabel("Remove photo")
                            .offset(x: 5, y: -5)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
