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

struct DraftValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let householdID: UUID
    let name: String
    let categoryID: UUID?
    let locationID: UUID?
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    let captureSource: CaptureSource
    let orderingIndex: Int
}

struct ItemValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let householdID: UUID
    let name: String
    let categoryID: UUID?
    let locationID: UUID?
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    let captureSource: CaptureSource
    let sourceDraftID: UUID?
    let status: ItemStatus
    let archivedAt: Date?
    let coverMediaID: UUID?
}

struct MediaValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let ownerKind: MediaOwnerKind
    let ownerID: UUID
    let originalFileName: String
    let thumbnailFileName: String?
    let contentTypeIdentifier: String
    let createdAt: Date
    let sortOrder: Int
}

struct LocationValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let householdID: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
}

struct CategoryValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let householdID: UUID
    let name: String
    let sortOrder: Int
    let isSystem: Bool
}

@dynamicMemberLookup
struct LibraryWriteResult<Value> {
    let value: Value
    let outcome: LibraryCommitOutcome

    subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Member {
        value[keyPath: keyPath]
    }
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
            String(localized: "This draft no longer exists.")
        case .itemNotFound:
            String(localized: "This item no longer exists.")
        case .mediaNotFound:
            String(localized: "This photo no longer exists.")
        case .nameRequired:
            String(localized: "Add a name before moving this draft into the item library.")
        case .locationNameRequired:
            String(localized: "Location name cannot be empty.")
        }
    }
}

enum DefaultHousehold {
    static let id = UUID(uuidString: "9D723A56-C65F-4BB4-BF65-1C99C565204D")!
}
