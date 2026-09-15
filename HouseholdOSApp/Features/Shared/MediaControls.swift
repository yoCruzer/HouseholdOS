@preconcurrency import AVFoundation
import ImageIO
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

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let completion:
            @MainActor @Sendable (Result<PickedMediaFile?, MediaPickerError>) -> Void
        private let resultGate = CaptureResultGate()

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
            guard resultGate.claimResult() else {
                return
            }
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
    let completion:
        @MainActor @Sendable (Result<PickedMediaFile?, MediaPickerError>) -> Void

    func makeUIViewController(context: Context) -> CameraCaptureViewController {
        CameraCaptureViewController(completion: completion)
    }

    func updateUIViewController(
        _ uiViewController: CameraCaptureViewController,
        context: Context
    ) {}
}

enum CameraAvailability {
    static var isAvailable: Bool {
        AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) != nil
    }
}

enum CapturedPhotoFile {
    static func writeJPEGData(_ data: Data) throws -> PickedMediaFile {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              UTType(sourceType as String)?.conforms(to: .jpeg) == true else {
            throw MediaPickerError.invalidCameraData
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "householdos-camera-\(UUID().uuidString).jpg"
            )
        try data.write(to: temporaryURL, options: .atomic)
        return PickedMediaFile(
            temporaryURL: temporaryURL,
            contentTypeIdentifier: UTType.jpeg.identifier
        )
    }
}

private final class CameraSessionController: @unchecked Sendable {
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()

    private let sessionQueue = DispatchQueue(
        label: "com.yocruzer.householdos.camera-session",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var wantsRunning = false
    private var isConfigured = false

    func start(
        completion: @escaping
            @MainActor @Sendable (Result<Void, MediaPickerError>) -> Void
    ) {
        setWantsRunning(true)
        sessionQueue.async { [self] in
            do {
                try configureIfNeeded()
                guard wantsSessionRunning() else {
                    return
                }
                captureSession.startRunning()
                guard wantsSessionRunning() else {
                    captureSession.stopRunning()
                    return
                }
                Task { @MainActor in
                    completion(.success(()))
                }
            } catch let error as MediaPickerError {
                deliver(error: error, completion: completion)
            } catch {
                deliver(
                    error: .cameraConfigurationFailed(error.localizedDescription),
                    completion: completion
                )
            }
        }
    }

    func stop() {
        setWantsRunning(false)
        sessionQueue.async { [self] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            return
        }
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw MediaPickerError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .photo
        guard captureSession.canAddInput(input),
              captureSession.canAddOutput(photoOutput) else {
            throw MediaPickerError.cameraUnavailable
        }
        captureSession.addInput(input)
        captureSession.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        isConfigured = true
    }

    private func deliver(
        error: MediaPickerError,
        completion: @escaping
            @MainActor @Sendable (Result<Void, MediaPickerError>) -> Void
    ) {
        guard wantsSessionRunning() else {
            return
        }
        Task { @MainActor in
            completion(.failure(error))
        }
    }

    private func setWantsRunning(_ value: Bool) {
        stateLock.lock()
        wantsRunning = value
        stateLock.unlock()
    }

    private func wantsSessionRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return wantsRunning
    }
}

@MainActor
final class CameraCaptureViewController: UIViewController,
    @preconcurrency AVCapturePhotoCaptureDelegate {
    private let completion:
        @MainActor @Sendable (Result<PickedMediaFile?, MediaPickerError>) -> Void
    private let cameraSession = CameraSessionController()
    private let previewView = UIView()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(
        session: cameraSession.captureSession
    )
    private let shutterButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let resultGate = CaptureResultGate()
    private var isSessionReady = false
    private var isCapturing = false
    private var isViewActive = true

    init(
        completion: @escaping
            @MainActor @Sendable (Result<PickedMediaFile?, MediaPickerError>) -> Void
    ) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInterface()
        requestPermissionAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutInterface()
        updateVideoOrientation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isViewActive = false
        isSessionReady = false
        shutterButton.isEnabled = false
        cameraSession.stop()
    }

    private func configureInterface() {
        view.backgroundColor = .black

        previewView.backgroundColor = .black
        previewView.clipsToBounds = true
        previewView.accessibilityIdentifier = "camera.preview"
        view.addSubview(previewView)

        previewLayer.videoGravity = .resizeAspect
        previewView.layer.addSublayer(previewLayer)

        var shutterConfiguration = UIButton.Configuration.filled()
        shutterConfiguration.title = String(localized: "Take Photo")
        shutterConfiguration.image = UIImage(systemName: "camera.fill")
        shutterConfiguration.imagePadding = 8
        shutterConfiguration.cornerStyle = .capsule
        shutterButton.configuration = shutterConfiguration
        shutterButton.isEnabled = false
        shutterButton.accessibilityIdentifier = "camera.shutter"
        shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)

        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = String(localized: "Cancel")
        cancelConfiguration.baseForegroundColor = .white
        cancelButton.configuration = cancelConfiguration
        cancelButton.accessibilityIdentifier = "camera.cancel"
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(cancelButton)
    }

    private func layoutInterface() {
        let bounds = view.bounds
        let safeInsets = view.safeAreaInsets
        let controlsHeight: CGFloat = 100
        let available = CGRect(
            x: safeInsets.left,
            y: safeInsets.top + 44,
            width: bounds.width - safeInsets.left - safeInsets.right,
            height: bounds.height - safeInsets.top - safeInsets.bottom - controlsHeight - 52
        )
        let isLandscape = bounds.width > bounds.height
        let targetAspect: CGFloat = isLandscape ? 4.0 / 3.0 : 3.0 / 4.0
        var previewSize = available.size
        if previewSize.width / previewSize.height > targetAspect {
            previewSize.width = previewSize.height * targetAspect
        } else {
            previewSize.height = previewSize.width / targetAspect
        }
        previewView.frame = CGRect(
            x: available.midX - previewSize.width / 2,
            y: available.midY - previewSize.height / 2,
            width: previewSize.width,
            height: previewSize.height
        )
        previewLayer.frame = previewView.bounds

        cancelButton.sizeToFit()
        cancelButton.frame.origin = CGPoint(
            x: safeInsets.left + 16,
            y: safeInsets.top + 4
        )

        let shutterSize = shutterButton.sizeThatFits(
            CGSize(width: bounds.width - 40, height: controlsHeight)
        )
        shutterButton.frame = CGRect(
            x: bounds.midX - shutterSize.width / 2,
            y: bounds.height - safeInsets.bottom - controlsHeight / 2 - shutterSize.height / 2,
            width: shutterSize.width,
            height: shutterSize.height
        )
    }

    private func requestPermissionAndStart() {
        Task {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                granted = true
            case .notDetermined:
                granted = await AVCaptureDevice.requestAccess(for: .video)
            case .denied, .restricted:
                granted = false
            @unknown default:
                granted = false
            }

            guard granted else {
                finish(.failure(.cameraPermissionDenied))
                return
            }

            guard isViewActive else {
                return
            }
            cameraSession.start { [weak self] result in
                guard let self, isViewActive else {
                    return
                }
                switch result {
                case .success:
                    isSessionReady = true
                    updateVideoOrientation()
                    shutterButton.isEnabled = true
                case .failure(let error):
                    finish(.failure(error))
                }
            }
        }
    }

    private func updateVideoOrientation() {
        guard let orientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }
        let angle: CGFloat
        switch orientation {
        case .portrait:
            angle = 90
        case .portraitUpsideDown:
            angle = 270
        case .landscapeLeft:
            angle = 0
        case .landscapeRight:
            angle = 180
        default:
            return
        }
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if let connection = cameraSession.photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    @objc private func capturePhoto() {
        guard isSessionReady, !isCapturing else {
            return
        }
        guard cameraSession.photoOutput.availablePhotoCodecTypes.contains(.jpeg) else {
            finish(.failure(.cameraJPEGUnavailable))
            return
        }
        isCapturing = true
        shutterButton.isEnabled = false
        updateVideoOrientation()
        let settings = AVCapturePhotoSettings(
            format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
        )
        settings.photoQualityPrioritization = .quality
        cameraSession.photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancel() {
        finish(.success(nil))
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finish(.failure(.cameraCaptureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            finish(.failure(.missingFile))
            return
        }

        Task.detached {
            let result: Result<PickedMediaFile?, MediaPickerError>
            do {
                result = .success(try CapturedPhotoFile.writeJPEGData(data))
            } catch let error as MediaPickerError {
                result = .failure(error)
            } catch {
                result = .failure(.readFailed(error.localizedDescription))
            }
            await self.finish(result)
        }
    }

    private func finish(
        _ result: Result<PickedMediaFile?, MediaPickerError>
    ) {
        guard resultGate.claimResult() else {
            discardDuplicatePickedMediaResult(result)
            return
        }
        isViewActive = false
        isSessionReady = false
        shutterButton.isEnabled = false
        cameraSession.stop()
        completion(result)
    }
}

private struct SendableImage: @unchecked Sendable {
    let image: UIImage
}

func discardPickedMediaFile(_ pickedFile: PickedMediaFile) async {
    await Task.detached {
        try? FileManager.default.removeItem(at: pickedFile.temporaryURL)
    }.value
}

@MainActor
func discardDuplicatePickedMediaResult(
    _ result: Result<PickedMediaFile?, MediaPickerError>
) {
    guard case .success(.some(let pickedFile)) = result else {
        return
    }
    Task {
        await discardPickedMediaFile(pickedFile)
    }
}

enum MediaPickerError: LocalizedError, Sendable {
    case missingFile
    case readFailed(String)
    case cameraUnavailable
    case cameraPermissionDenied
    case cameraConfigurationFailed(String)
    case cameraCaptureFailed(String)
    case cameraJPEGUnavailable
    case invalidCameraData

    var errorDescription: String? {
        switch self {
        case .missingFile:
            String(localized: "The selected image could not be read.")
        case .readFailed(let message):
            String(localized: "The selected image could not be copied.") + " \(message)"
        case .cameraUnavailable:
            String(localized: "The back camera is unavailable on this device.")
        case .cameraPermissionDenied:
            String(localized: "Camera access was not granted.")
        case .cameraConfigurationFailed(let message):
            String(localized: "The camera could not be prepared.") + " \(message)"
        case .cameraCaptureFailed(let message):
            String(localized: "The photo could not be captured.") + " \(message)"
        case .cameraJPEGUnavailable:
            String(localized: "This camera cannot deliver a JPEG photo.")
        case .invalidCameraData:
            String(localized: "The captured photo was not valid JPEG data.")
        }
    }
}

struct MediaThumbnailView: View {
    let asset: MediaValue
    var size: CGFloat = 72

    @EnvironmentObject private var library: ItemLibraryService
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
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
        .task(id: asset.id) {
            let path = library.displayURL(for: asset).path
            let loadedImage: SendableImage? = await Task.detached {
                guard let image = UIImage(contentsOfFile: path) else {
                    return nil
                }
                return SendableImage(image: image)
            }.value
            image = loadedImage?.image
        }
    }
}

struct MediaThumbnailButton: View {
    let asset: MediaValue
    var size: CGFloat = 96
    let view: (MediaValue) -> Void

    var body: some View {
        Button {
            view(asset)
        } label: {
            MediaThumbnailView(asset: asset, size: size)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel("View photo")
        .accessibilityIdentifier("media.view.\(asset.id.uuidString)")
    }
}

struct OriginalPhotoViewer: View {
    let asset: MediaValue
    let close: () -> Void

    @EnvironmentObject private var library: ItemLibraryService
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    GeometryReader { proxy in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height
                            )
                            .accessibilityLabel("Original photo")
                            .accessibilityIdentifier("photoViewer.image")
                    }
                } else if didFail {
                    ContentUnavailableView(
                        "Photo unavailable",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("The original photo could not be opened.")
                    )
                    .foregroundStyle(.white)
                } else {
                    ProgressView("Loading photo…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: close)
                    .accessibilityIdentifier("photoViewer.close")
                }
            }
        }
        .task(id: asset.id) {
            let path = library.originalURL(for: asset).path
            let loadedImage: SendableImage? = await Task.detached {
                guard let image = UIImage(contentsOfFile: path) else {
                    return nil
                }
                return SendableImage(image: image)
            }.value
            image = loadedImage?.image
            didFail = loadedImage == nil
        }
    }
}

struct MediaGridView: View {
    let assets: [MediaValue]
    let view: (MediaValue) -> Void
    let remove: (MediaValue) -> Void

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
                        VStack(spacing: 6) {
                            MediaThumbnailButton(asset: asset, view: view)
                            Button("Delete Photo", role: .destructive) {
                                remove(asset)
                            }
                            .font(.caption)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("media.delete.\(asset.id.uuidString)")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
