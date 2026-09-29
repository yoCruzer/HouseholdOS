// Independent review probes for yoCruzer/HouseholdOS PR #5 @ faae13d93a83694a77da3d962423de2193f0fe88.
// Wire types, validation and ThreeWayMerge copied from SyncProtocol.swift.
// This executes the pure Swift merge code; it does NOT execute SwiftData, CloudKit or iOS.
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
enum ThreeWayMerge {
    static func merge(ancestor: WireRecord, local: WireRecord, remote: WireRecord) -> WireRecord? {
        guard ancestor.id == local.id, local.id == remote.id, !ancestor.deleted, !local.deleted, !remote.deleted,
              ancestor.kind == local.kind, local.kind == remote.kind, local.parentID == remote.parentID,
              ancestor.format == 1, local.format == 1, remote.format == 1 else { return nil }
        var result = local
        func field<T: Equatable>(_ base: T, _ ours: T, _ theirs: T) -> T? {
            if ours == theirs || theirs == base { return ours }
            if ours == base { return theirs }
            return nil
        }
        // Wrap optional values to distinguish a successful nil from a merge conflict.
        guard let name = field([ancestor.name], [local.name], [remote.name]),
              let category = field([ancestor.category], [local.category], [remote.category]),
              let money = field([ancestor.amount, ancestor.currency], [local.amount, local.currency], [remote.amount, remote.currency]),
              let profile = field([ancestor.profile], [local.profile], [remote.profile]),
              let media = field([ancestor.media], [local.media], [remote.media]) else { return nil }
        result.name = name[0]; result.category = category[0]; result.amount = money[0]; result.currency = money[1]
        result.profile = profile[0]; result.media = media[0]
        result.operationID = UUID(); result.revision = max(local.revision, remote.revision) + 1
        return try? result.validated()
    }
}

// Probe 1: actual copied merge accepts a new incarnation and silently retains the old one.
let oldIncarnation = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let newIncarnation = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
let base = WireRecord(id: UUID(), operationID: UUID(), revision: 1, library: UUID(), kind: "item", name: "old item", category: "category-A", incarnation: oldIncarnation)
var local = base
local.operationID = UUID(); local.revision = 2; local.category = "offline local category"
var remote = base
remote.operationID = UUID(); remote.revision = 4; remote.name = "explicitly re-added item"
remote.incarnation = newIncarnation; remote.replacesDeletion = UUID()
let merged = ThreeWayMerge.merge(ancestor: base, local: local, remote: remote)
print("MERGE_CROSS_INCARNATION accepted=\(merged != nil) oldIncarnationRetained=\(merged?.effectiveIncarnation == oldIncarnation) remoteReAddTokenPreserved=\(merged?.replacesDeletion == remote.replacesDeletion)")

// Probe 2: same selection loop as SyncCore.nextBatch, with persistence replaced by arrays.
// Scheduling algorithm only -- not an execution of the repository's SwiftData method.
struct Intent { let entityID: Int; let revision: Int }
let pending = (1...300).map { Intent(entityID: $0, revision: 1) }
var inflight: [Intent] = []
func selectionLoop() -> [Intent] {
    var records = inflight
    var selected = Set(records.map(\.entityID))
    for intent in pending.sorted(by: { $0.revision < $1.revision }) where !selected.contains(intent.entityID) {
        inflight.append(intent); selected.insert(intent.entityID)
        records.append(intent)
        if records.count == 100 { break }
    }
    return records
}
let first = selectionLoop().count
let second = selectionLoop().count
let third = selectionLoop().count
print("BATCH_SELECTION repeated_without_ACK=[\(first),\(second),\(third)] configuredLimit=100")

// Probe 3: actual max-by-revision expression with two valid same-revision representations.
struct Rep { var id: String; var revision: Int }
let a = Rep(id: "old-local-A", revision: 2)
let b = Rep(id: "current-wire-B", revision: 2)
let chosen = [a,b].max { $0.revision < $1.revision }
print("REPRESENTATION_SELECTION wirePointsTo=current-wire-B selected=\(chosen!.id)")
