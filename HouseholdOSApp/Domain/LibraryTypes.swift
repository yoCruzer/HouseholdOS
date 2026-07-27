import Foundation

enum CaptureSource: String, CaseIterable, Codable, Sendable {
    case manual
    case photoLibrary
    case camera
}

enum ItemStatus: String, CaseIterable, Codable, Sendable {
    case active
    case archived
}

enum MediaOwnerKind: String, Codable, Sendable {
    case draft
    case item
}

enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case name

    var id: String { rawValue }
}

enum LibraryError: Error, Equatable {
    case draftNotFound
    case itemNotFound
    case mediaNotFound
    case nameRequired
    case locationNameRequired
}

extension LibraryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .draftNotFound:
            "This draft no longer exists."
        case .itemNotFound:
            "This item no longer exists."
        case .mediaNotFound:
            "This photo no longer exists."
        case .nameRequired:
            "Add a name before moving this draft into the item library."
        case .locationNameRequired:
            "Location name cannot be empty."
        }
    }
}

enum DefaultHousehold {
    static let id = UUID(uuidString: "9D723A56-C65F-4BB4-BF65-1C99C565204D")!
}
