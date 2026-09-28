import Foundation

enum StorageFailure: String {
    case permissionOrProtection, capacity, missing, corrupt, unavailable
    static func classify(_ error: Error) -> StorageFailure {
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain {
            switch value.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .permissionOrProtection
            case NSFileWriteOutOfSpaceError: return .capacity
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .missing
            case NSFileReadCorruptFileError: return .corrupt
            default: break
            }
        }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { return classify(underlying) }
        return .unavailable
    }
}
