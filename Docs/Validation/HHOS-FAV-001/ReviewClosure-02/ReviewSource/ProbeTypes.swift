import Foundation

enum ValidationFailure: Error { case invariant(String) }
struct WireProfile: Codable, Equatable, Sendable {
    var id: UUID
    var size: String?
    var material: String?
}
struct WireMedia: Codable, Equatable, Sendable {
    var representationID: UUID
    var revision: Int
    var hash: String
    var precision: String
    var contentType: String
    var preview: Data
    var photosReference: String?
}
struct WireRecord: Codable, Equatable, Sendable {
    var id: UUID
    var operationID: UUID
    var revision: Int
    var library: UUID
    var kind: String
    var parentID: UUID?
    var name: String?
    var category: String?
    var amount: String?
    var currency: String?
    var deleted: Bool = false
    var replacesDeletion: UUID?
    var format: Int = 1
    var profile: WireProfile?
    var media: WireMedia?
    var sourceDraftID: UUID?
    var incarnation: UUID?
    var parentIncarnation: UUID?
    var effectiveIncarnation: UUID { incarnation ?? id }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    func validated() throws -> WireRecord {
        guard revision > 0, ["draft", "item", "media", "usage"].contains(kind),
              (amount == nil) == (currency == nil),
              amount == nil || (amount!.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil && Decimal(string: amount!, locale: Locale(identifier: "en_US_POSIX")) != nil && currency!.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil) else {
            throw ValidationFailure.invariant("invalid wire data")
        }
        guard parentID != id, (["draft", "item"].contains(kind) ? parentID == nil : parentID != nil) else {
            throw ValidationFailure.invariant("invalid parent topology")
        }
        if deleted && ([name, category, amount, currency].contains(where: { $0 != nil }) || profile != nil || media != nil) {
            throw ValidationFailure.invariant("tombstone contains content")
        }
        return self
    }
}
