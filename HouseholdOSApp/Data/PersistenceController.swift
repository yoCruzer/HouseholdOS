import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(
        inMemoryOnly: Bool = false,
        storeURL: URL? = nil
    ) throws -> ModelContainer {
        let schema = Schema(HouseholdOSSchemaV1.models)
        let configuration: ModelConfiguration

        if let storeURL {
            configuration = ModelConfiguration(
                "HouseholdOS",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "HouseholdOS",
                schema: schema,
                isStoredInMemoryOnly: inMemoryOnly,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: HouseholdOSMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
