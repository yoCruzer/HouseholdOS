import Foundation
import SwiftData

@Model
final class ItemRecord {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var name: String
    var categoryID: UUID?
    var locationID: UUID?
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var captureSourceRaw: String
    @Attribute(.unique) var sourceDraftID: UUID?
    var statusRaw: String
    var archivedAt: Date?
    var coverMediaID: UUID?

    init(
        id: UUID = UUID(),
        householdID: UUID = DefaultHousehold.id,
        name: String,
        categoryID: UUID? = nil,
        locationID: UUID? = nil,
        note: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        captureSource: CaptureSource,
        sourceDraftID: UUID? = nil,
        status: ItemStatus = .active,
        archivedAt: Date? = nil,
        coverMediaID: UUID? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.categoryID = categoryID
        self.locationID = locationID
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.captureSourceRaw = captureSource.rawValue
        self.sourceDraftID = sourceDraftID
        self.statusRaw = status.rawValue
        self.archivedAt = archivedAt
        self.coverMediaID = coverMediaID
    }

    var captureSource: CaptureSource {
        get { CaptureSource(rawValue: captureSourceRaw) ?? .manual }
        set { captureSourceRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class CaptureDraftRecord {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var name: String
    var categoryID: UUID?
    var locationID: UUID?
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var captureSourceRaw: String
    var orderingIndex: Int

    init(
        id: UUID = UUID(),
        householdID: UUID = DefaultHousehold.id,
        name: String = "",
        categoryID: UUID? = nil,
        locationID: UUID? = nil,
        note: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        captureSource: CaptureSource,
        orderingIndex: Int = 0
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.categoryID = categoryID
        self.locationID = locationID
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.captureSourceRaw = captureSource.rawValue
        self.orderingIndex = orderingIndex
    }

    var captureSource: CaptureSource {
        get { CaptureSource(rawValue: captureSourceRaw) ?? .manual }
        set { captureSourceRaw = newValue.rawValue }
    }
}

@Model
final class MediaAssetRecord {
    @Attribute(.unique) var id: UUID
    var ownerKindRaw: String
    var ownerID: UUID
    var originalFileName: String
    var thumbnailFileName: String?
    var contentTypeIdentifier: String
    var createdAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        ownerKind: MediaOwnerKind,
        ownerID: UUID,
        originalFileName: String,
        thumbnailFileName: String?,
        contentTypeIdentifier: String,
        createdAt: Date,
        sortOrder: Int
    ) {
        self.id = id
        self.ownerKindRaw = ownerKind.rawValue
        self.ownerID = ownerID
        self.originalFileName = originalFileName
        self.thumbnailFileName = thumbnailFileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    var ownerKind: MediaOwnerKind {
        get { MediaOwnerKind(rawValue: ownerKindRaw) ?? .draft }
        set { ownerKindRaw = newValue.rawValue }
    }
}

@Model
final class CategoryRecord {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var name: String
    var sortOrder: Int
    var isSystem: Bool

    init(
        id: UUID,
        householdID: UUID = DefaultHousehold.id,
        name: String,
        sortOrder: Int,
        isSystem: Bool
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }
}

@Model
final class LocationRecord {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        householdID: UUID = DefaultHousehold.id,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }
}

struct DefaultCategoryDefinition: Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int

    static let all: [DefaultCategoryDefinition] = [
        .init(
            id: UUID(uuidString: "30DAA9EE-70B6-48D3-B360-297DAB9A80DE")!,
            name: "Electronics",
            sortOrder: 0
        ),
        .init(
            id: UUID(uuidString: "9EC97C0C-17A2-43ED-BD52-B35BEF0DD3D7")!,
            name: "Kitchen",
            sortOrder: 1
        ),
        .init(
            id: UUID(uuidString: "1D98917C-E0FD-402F-9CE5-423DA8D3660D")!,
            name: "Tools",
            sortOrder: 2
        ),
        .init(
            id: UUID(uuidString: "436EC959-E4C6-4B6F-B1F4-E0B8AD5A3C4E")!,
            name: "Home",
            sortOrder: 3
        ),
        .init(
            id: UUID(uuidString: "3DBE767F-4C5A-4D11-A180-DB8B25F9FFCD")!,
            name: "Clothing",
            sortOrder: 4
        ),
        .init(
            id: UUID(uuidString: "31F561BD-C53E-4DE8-A110-1E77D20E89B6")!,
            name: "Other",
            sortOrder: 5
        )
    ]
}

enum HouseholdOSSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ItemRecord.self,
            CaptureDraftRecord.self,
            MediaAssetRecord.self,
            CategoryRecord.self,
            LocationRecord.self
        ]
    }
}

enum HouseholdOSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [HouseholdOSSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
