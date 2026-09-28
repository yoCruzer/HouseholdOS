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
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let authorized = status == .authorized || status == .limited
        let count = authorized ? identifier.map { PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).count } ?? 0 : 0
        return selectedAccess(identifier: identifier, authorized: authorized, assetCount: count, bytes: deliveredBytes)
    }
}

enum PhotosMappingState: String, Codable {
    case mapped, noAuthorization, temporarilyNotFound, multipleCandidates, networkRequired, insufficientSpace, unavailable
}
struct PhotosMappingResult {
    var state: PhotosMappingState
    var identifier: String?
}

extension PhotosAdapter {
    static func classify(_ error: Error) -> PhotosMappingState {
        let ns = error as NSError
        guard ns.domain == PHPhotosErrorDomain else { return .unavailable }
        switch ns.code {
        case PHPhotosError.identifierNotFound.rawValue: return .temporarilyNotFound
        case PHPhotosError.multipleIdentifiersFound.rawValue: return .multipleCandidates
        case PHPhotosError.networkAccessRequired.rawValue: return .networkRequired
        case PHPhotosError.notEnoughSpace.rawValue: return .insufficientSpace
        case PHPhotosError.accessRestricted.rawValue, PHPhotosError.accessUserDenied.rawValue: return .noAuthorization
        default: return .unavailable
        }
    }

    static func selectedAccess(identifier: String?, authorized: Bool, assetCount: Int, bytes: Data) -> SelectedPhotoResolution {
        guard let identifier else { return .init(access: .missingIdentifier, fallbackBytes: bytes) }
        guard authorized else { return .init(access: .noAuthorization, fallbackBytes: bytes) }
        guard assetCount == 1 else { return .init(access: .inaccessible, fallbackBytes: bytes) }
        return .init(access: .accessible, localIdentifier: identifier, fallbackBytes: bytes)
    }
}

// Instance is created at a selection/load boundary, never in a SwiftUI row's render body.
// No identifiers or fallback bytes are emitted in the public evidence summary.
final class PhotosMappingBatch {
    private(set) var cache: [String: PhotosMappingResult] = [:]
    func cloudReferences(forSelectedIdentifiers identifiers: [String]) -> [String: PhotosMappingResult] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            cache = Dictionary(uniqueKeysWithValues: Set(identifiers).map { ($0, PhotosMappingResult(state: .noAuthorization)) })
            return cache
        }
        let requested = Array(Set(identifiers))
        let results = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: requested)
        for id in requested {
            switch results[id] {
            case .success(let cloud): cache[id] = .init(state: .mapped, identifier: cloud.stringValue)
            case .failure(let error): cache[id] = .init(state: PhotosAdapter.classify(error))
            case nil: cache[id] = .init(state: .temporarilyNotFound)
            }
        }
        return cache
    }
    func localReferences(forCloudReferences references: [String]) -> [String: PhotosMappingResult] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return Dictionary(uniqueKeysWithValues: Set(references).map { ($0, PhotosMappingResult(state: .noAuthorization)) })
        }
        let identifiers = Array(Set(references)).map(PHCloudIdentifier.init(stringValue:))
        let results = PHPhotoLibrary.shared().localIdentifierMappings(for: identifiers)
        for cloud in identifiers {
            switch results[cloud] {
            case .success(let local):
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [local], options: nil)
                cache[cloud.stringValue] = assets.count == 1 ? .init(state: .mapped, identifier: local) : .init(state: .temporarilyNotFound)
            case .failure(let error): cache[cloud.stringValue] = .init(state: PhotosAdapter.classify(error))
            case nil: cache[cloud.stringValue] = .init(state: .temporarilyNotFound)
            }
        }
        return cache
    }
}

extension PhotosAdapter {
    // Reads only a previously selected/mapped asset. No broad fetch, library mutation,
    // or implicit iCloud download. This checks current still-image access, not original fidelity.
    static func readSelectedCurrentRepresentation(_ identifier: String) throws -> Data {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.accessUserDenied.rawValue)
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard assets.count == 1, let asset = assets.firstObject else {
            throw NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.identifierNotFound.rawValue)
        }
        let options = PHImageRequestOptions()
        options.isSynchronous = true; options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat; options.version = .current
        var bytes: Data?
        var failure: Error?
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            bytes = data
            failure = info?[PHImageErrorKey] as? Error
            if data == nil, failure == nil, info?[PHImageResultIsInCloudKey] as? Bool == true {
                failure = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.networkAccessRequired.rawValue)
            }
        }
        if let failure { throw failure }
        guard let bytes else { throw ValidationFailure.invariant("selected Photos representation unavailable") }
        return bytes
    }
}
