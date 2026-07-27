import Foundation

enum LibrarySearch {
    static func filter(
        _ items: [ItemRecord],
        query: String,
        categoryID: UUID?,
        includeArchived: Bool,
        sort: LibrarySort,
        categoryName: (UUID?) -> String?,
        locationName: (UUID?) -> String?
    ) -> [ItemRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return items
            .filter { item in
                (includeArchived || item.status == .active)
                    && (categoryID == nil || item.categoryID == categoryID)
                    && matches(
                        item,
                        query: normalizedQuery,
                        categoryName: categoryName(item.categoryID),
                        locationName: locationName(item.locationID)
                    )
            }
            .sorted { lhs, rhs in
                switch sort {
                case .newest:
                    lhs.createdAt == rhs.createdAt
                        ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                        : lhs.createdAt > rhs.createdAt
                case .oldest:
                    lhs.createdAt == rhs.createdAt
                        ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                        : lhs.createdAt < rhs.createdAt
                case .name:
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
    }

    private static func matches(
        _ item: ItemRecord,
        query: String,
        categoryName: String?,
        locationName: String?
    ) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        return [
            item.name,
            item.note ?? "",
            categoryName ?? "",
            locationName ?? ""
        ]
        .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
