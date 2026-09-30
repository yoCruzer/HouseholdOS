import Foundation

enum StorageFailure: String {
    case permissionOrProtection, capacity, missing, corrupt, unavailable
    var message: String {
        switch self {
        case .permissionOrProtection: return "存储权限或受保护数据暂不可用；原库保留，请在可访问后重试"
        case .capacity: return "存储空间不足；原件和未完成记录保留"
        case .missing: return "所需文件缺失；停止操作并保留现有库"
        case .corrupt: return "文件格式或校验异常；原库保留，不自动重建"
        case .unavailable: return "操作未完成；数据保留，请核对配置和执行证据"
        }
    }
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
