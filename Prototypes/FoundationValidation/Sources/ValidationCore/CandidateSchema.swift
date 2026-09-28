import Foundation
import SwiftData

@Model final class WardrobeProfile {
    @Attribute(.unique) var id: UUID
    var ownerID: UUID
    var size: String?
    var material: String?
    init(id: UUID = UUID(), ownerID: UUID, size: String? = nil, material: String? = nil) {
        self.id = id; self.ownerID = ownerID; self.size = size; self.material = material
    }
}

@Model final class DurableIntent {
    @Attribute(.unique) var operationID: UUID
    var entityID: UUID
    var revision: Int
    var kind: String
    var payload: Data
    var scope: String
    init(operationID: UUID = UUID(), entityID: UUID, revision: Int, kind: String, payload: Data, scope: String) {
        self.operationID = operationID; self.entityID = entityID; self.revision = revision
        self.kind = kind; self.payload = payload; self.scope = scope
    }
}

@Model final class MediaRepresentation {
    @Attribute(.unique) var id: UUID
    var mediaID: UUID
    var revision: Int
    var precision: String
    var originalHash: String
    var relativePath: String
    var photosReference: String?
    init(id: UUID = UUID(), mediaID: UUID, revision: Int, precision: String, originalHash: String, relativePath: String, photosReference: String? = nil) {
        self.id = id; self.mediaID = mediaID; self.revision = revision; self.precision = precision
        self.originalHash = originalHash; self.relativePath = relativePath; self.photosReference = photosReference
    }
}

enum CandidateSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        HouseholdOSSchemaV1.models + [WardrobeProfile.self, DurableIntent.self, MediaRepresentation.self, SyncedDocument.self, SyncCheckpoint.self, ConflictCandidate.self, SentSnapshot.self]
    }
}

enum CandidateMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HouseholdOSSchemaV1.self, CandidateSchema.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: HouseholdOSSchemaV1.self, toVersion: CandidateSchema.self)] }
}

@MainActor enum CandidateStore {
    static func open(_ url: URL, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(CandidateSchema.models)
        return try ModelContainer(for: schema, migrationPlan: CandidateMigration.self,
            configurations: [ModelConfiguration("HouseholdOS", schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none)])
    }
}
