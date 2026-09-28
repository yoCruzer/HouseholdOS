import Foundation
import Photos

enum PhotosAccess: String, Codable { case noAuthorization, missingIdentifier, inaccessible, accessible }
struct SelectedPhotoResolution {
    var access: PhotosAccess
    var localIdentifier: String?
    var precision = "pickerDeliveredRepresentation"
    // The caller retains the delivered bytes regardless of later Photos permission changes.
    var fallbackBytes: Data
}

enum PhotosAdapter {
    static func resolveSelected(identifier: String?, deliveredBytes: Data) -> SelectedPhotoResolution {
        guard let identifier else { return .init(access: .missingIdentifier, fallbackBytes: deliveredBytes) }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return .init(access: .noAuthorization, fallbackBytes: deliveredBytes) }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard assets.count == 1 else { return .init(access: .inaccessible, fallbackBytes: deliveredBytes) }
        return .init(access: .accessible, localIdentifier: identifier, fallbackBytes: deliveredBytes)
    }
}
