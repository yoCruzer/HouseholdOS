import Foundation

enum SystemCategoryLocalization {
    static func displayName(for category: CategoryValue) -> String {
        guard category.isSystem else {
            return category.name
        }

        if category.id == UUID(uuidString: "30DAA9EE-70B6-48D3-B360-297DAB9A80DE")! {
            return String(localized: "Electronics", comment: "System category name")
        }
        if category.id == UUID(uuidString: "9EC97C0C-17A2-43ED-BD52-B35BEF0DD3D7")! {
            return String(localized: "Kitchen", comment: "System category name")
        }
        if category.id == UUID(uuidString: "1D98917C-E0FD-402F-9CE5-423DA8D3660D")! {
            return String(localized: "Tools", comment: "System category name")
        }
        if category.id == UUID(uuidString: "436EC959-E4C6-4B6F-B1F4-E0B8AD5A3C4E")! {
            return String(localized: "Home", comment: "System category name")
        }
        if category.id == UUID(uuidString: "3DBE767F-4C5A-4D11-A180-DB8B25F9FFCD")! {
            return String(localized: "Clothing", comment: "System category name")
        }
        if category.id == UUID(uuidString: "31F561BD-C53E-4DE8-A110-1E77D20E89B6")! {
            return String(localized: "Other", comment: "System category name")
        }
        return category.name
    }
}
