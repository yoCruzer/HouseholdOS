import Foundation
import SwiftData
import CloudKit

struct SyncScope: Codable, Equatable, Sendable {
    var container: String
    var environment: String
    var account: String
    var library: UUID
    var zone: String
    var epoch: UUID
    var key: String { [container, environment, account, library.uuidString, zone].joined(separator: "/") }
}

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

@Model final class SyncedDocument {
    @Attribute(.unique) var id: UUID
    var payload: Data
    var ancestor: Data?
    var systemFields: Data?
    var scope: String
    init(_ record: WireRecord, scope: String) throws {
        id = record.id; payload = try record.encoded(); self.scope = scope
    }
}

@Model final class SyncCheckpoint {
    @Attribute(.unique) var key: String
    var data: Data
    init(key: String, data: Data) { self.key = key; self.data = data }
}

@Model final class ConflictCandidate {
    @Attribute(.unique) var id: UUID
    var entityID: UUID
    var local: Data
    var remote: Data
    var scope: String
    init(entityID: UUID, local: Data, remote: Data, scope: String) {
        id = UUID(); self.entityID = entityID; self.local = local; self.remote = remote; self.scope = scope
    }
}

// Resolution is stored separately from account/library scope. Checkpoints keep the
// existing candidate schema compatible; legacy resolved/<scope> rows are normalized.
@MainActor extension ConflictCandidate {
    func isResolved(in context: ModelContext) throws -> Bool {
        try scope.hasPrefix("resolved/") || (context.fetch(FetchDescriptor<SyncCheckpoint>()).contains { $0.key == "conflict-resolution/" + id.uuidString })
    }
    func resolve(in context: ModelContext) throws {
        if !(try context.fetch(FetchDescriptor<SyncCheckpoint>()).contains { $0.key == "conflict-resolution/" + id.uuidString }) {
            context.insert(SyncCheckpoint(key: "conflict-resolution/" + id.uuidString, data: Data("resolved".utf8)))
        }
        if scope.hasPrefix("resolved/") { scope = String(scope.dropFirst("resolved/".count)) }
    }
    func rebind(to scope: String, in context: ModelContext) throws {
        if try isResolved(in: context) { try resolve(in: context) }
        self.scope = scope
    }
}

@Model final class SentSnapshot {
    @Attribute(.unique) var operationID: UUID
    var entityID: UUID
    var payload: Data
    var scope: String
    init(_ intent: DurableIntent) {
        operationID = intent.operationID; entityID = intent.entityID; payload = intent.payload; scope = intent.scope
    }
}

// Durable operation provenance, not a second business snapshot. It survives restore
// without transport tags; the current server must still confirm the exact payload.
struct OperationReceipt: Codable {
    var payload: Data
    var scope: String
    var sentBase: Data?
    var wasSent: Bool
    var confirmed: Bool = false
    var supersededBy: UUID?
}

struct SessionState: Codable {
    var scope: SyncScope
    var enabled = false
    var bootstrapComplete = false
    var pauseReason: String?
    var engineSerialization: Data?
    var restoring: Bool?
    var retryAfter: Date?
    var batchLimit: Int?
}

// One codec is used by the real CloudKit delegate and deterministic transport tests.
enum CloudCodec {
    static func encode(_ wire: WireRecord, zone: CKRecordZone.ID, systemFields: Data? = nil) throws -> CKRecord {
        _ = try wire.validated()
        let record: CKRecord
        if let systemFields {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: systemFields)
            decoder.requiresSecureCoding = true
            guard let restored = CKRecord(coder: decoder) else { throw ValidationFailure.invariant("invalid system fields") }
            decoder.finishDecoding(); record = restored
            guard record.recordID == CKRecord.ID(recordName: wire.id.uuidString, zoneID: zone) else { throw ValidationFailure.invariant("system fields scope mismatch") }
        } else {
            record = CKRecord(recordType: "HHOSVAL_Entity", recordID: CKRecord.ID(recordName: wire.id.uuidString, zoneID: zone))
        }
        record["library"] = wire.library.uuidString as CKRecordValue
        record["operation"] = wire.operationID.uuidString as CKRecordValue
        record["revision"] = wire.revision as CKRecordValue
        record.encryptedValues["payload"] = try wire.encoded() as CKRecordValue
        return record
    }
    static func decode(_ record: CKRecord, scope: SyncScope) throws -> WireRecord {
        guard record.recordType == "HHOSVAL_Entity", record.recordID.zoneID.zoneName == scope.zone,
              record["library"] as? String == scope.library.uuidString,
              let bytes = record.encryptedValues["payload"] as? Data else { throw ValidationFailure.invariant("record scope/type mismatch") }
        let wire = try JSONDecoder().decode(WireRecord.self, from: bytes).validated()
        guard wire.id.uuidString == record.recordID.recordName, wire.library == scope.library,
              wire.operationID.uuidString == record["operation"] as? String,
              wire.revision == record["revision"] as? Int else { throw ValidationFailure.invariant("record envelope mismatch") }
        return wire
    }
    static func writable(_ bytes: Data) -> Bool {
        let known: Set<String> = ["id", "operationID", "revision", "library", "kind", "parentID", "name", "category", "amount", "currency", "deleted", "replacesDeletion", "format", "profile", "media", "sourceDraftID", "incarnation", "parentIncarnation"]
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys).isSubset(of: known), object["format"] as? Int == 1 else { return false }
        // Codable ignores unknown nested keys too. Never rewrite a representation or
        // profile after silently dropping fields introduced by a newer client.
        let nested: [String: Set<String>] = [
            "profile": ["id", "size", "material"],
            "media": ["representationID", "revision", "hash", "precision", "contentType", "preview", "photosReference"]
        ]
        for (key, fields) in nested {
            guard let value = object[key], !(value is NSNull) else { continue }
            guard let dictionary = value as? [String: Any], Set(dictionary.keys).isSubset(of: fields) else { return false }
        }
        return true
    }
    static func systemFields(_ record: CKRecord) -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder); encoder.finishEncoding()
        return encoder.encodedData
    }
}

@MainActor final class SyncCore {
    let context: ModelContext
    let mediaRoot: URL?
    var session: SessionState
    var failNextCommit = false
    // Test transport may wrap native archives with an opaque conditional token.
    // Default/live paths always use the actual CloudKit system fields.
    var archiveServerRecord: (CKRecord) -> Data = CloudCodec.systemFields
    var nativeSystemFields: (Data) throws -> Data = { $0 }
    init(context: ModelContext, scope: SyncScope, mediaRoot: URL? = nil) throws {
        self.context = context; self.mediaRoot = mediaRoot
        if let saved = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "session" }) {
            session = try JSONDecoder().decode(SessionState.self, from: saved.data)
            if session.scope != scope {
                session = SessionState(scope: scope, pauseReason: "explicit account/library binding required")
            }
        } else { session = SessionState(scope: scope) }
        context.autosaveEnabled = false
        if let saved = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "session" }),
           try JSONDecoder().decode(SessionState.self, from: saved.data).scope != session.scope {
            try saveSession() // Persist the new blocked epoch before accepting any callbacks.
        }
    }
    func commit() throws {
        if failNextCommit {
            failNextCommit = false
            context.rollback()
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func beginFetch(callback: SyncScope) throws {
        guard accepts(callback) else { return }
        session.bootstrapComplete = false; try saveSession()
    }
    func saveSession() throws {
        let data = try JSONEncoder().encode(session)
        if let row = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "session" }) { row.data = data }
        else { context.insert(SyncCheckpoint(key: "session", data: data)) }
        try commit()
    }
    func setEnabled(_ value: Bool) throws {
        session.enabled = value
        if !value { session.scope.epoch = UUID(); session.bootstrapComplete = false; session.engineSerialization = nil }
        try saveSession()
    }
    func accepts(_ scope: SyncScope) -> Bool {
        guard session.enabled, session.scope == scope, session.pauseReason == nil,
              let row = try? context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "session" }),
              let durable = try? JSONDecoder().decode(SessionState.self, from: row.data) else { return false }
        return durable.enabled && durable.scope == scope && durable.pauseReason == nil
    }
    func document(_ id: UUID) throws -> SyncedDocument? {
        try context.fetch(FetchDescriptor<SyncedDocument>()).first { $0.id == id }
    }
    func pending() throws -> [DurableIntent] {
        try context.fetch(FetchDescriptor<DurableIntent>()).filter { $0.scope == session.scope.key }
    }
    func write(_ record: WireRecord) throws {
        do { try stageWrite(record); try projectVisibleRecord(record.id); try commit() }
        catch { context.rollback(); throw error }
    }
    // Business models and their wire intent share the caller's single SwiftData save.
    func stageWrite(_ record: WireRecord) throws {
        _ = try record.validated()
        guard record.library == session.scope.library, record.format == 1 else { throw ValidationFailure.invariant("write outside library/version") }
        if let current = try document(record.id) {
            guard current.scope == session.scope.key else { throw ValidationFailure.invariant("explicit cross-scope plan required") }
            let old = try JSONDecoder().decode(WireRecord.self, from: current.payload)
            if old.operationID == record.operationID {
                guard old == record else { throw ValidationFailure.invariant("operation identity reused with different content") }
                return
            }
            guard record.revision > old.revision else { throw ValidationFailure.invariant("non-increasing revision") }
            guard CloudCodec.writable(current.payload) else { throw ValidationFailure.invariant("future data is write protected") }
            guard !old.deleted || record.deleted || record.replacesDeletion == old.operationID else { throw ValidationFailure.invariant("explicit re-add intent required") }
            if old.deleted && !record.deleted {
                guard record.incarnation != nil, record.effectiveIncarnation != old.effectiveIncarnation else {
                    throw ValidationFailure.invariant("re-add requires new incarnation")
                }
                for conflict in try context.fetch(FetchDescriptor<ConflictCandidate>()) where conflict.entityID == record.id && conflict.scope == session.scope.key {
                    let candidate = try JSONDecoder().decode(WireRecord.self, from: conflict.remote)
                    if candidate.operationID == old.operationID { try conflict.resolve(in: context) }
                }
            }
            if old.parentID != nil, old.parentID == record.parentID,
               (old.parentIncarnation ?? old.parentID) != record.parentIncarnation,
               let parent = try document(record.parentID!),
               let parentWire = try? JSONDecoder().decode(WireRecord.self, from: parent.payload),
               !parentWire.deleted, record.parentIncarnation == parentWire.effectiveIncarnation {
                for intent in try pending() where intent.entityID == record.id {
                    let prior = try JSONDecoder().decode(WireRecord.self, from: intent.payload)
                    guard prior.parentID == old.parentID, (prior.parentIncarnation ?? prior.parentID) != record.parentIncarnation else { continue }
                    var receipt = try operationReceipt(prior.operationID) ?? OperationReceipt(payload: intent.payload, scope: intent.scope, wasSent: false)
                    receipt.supersededBy = record.operationID
                    try saveReceipt(receipt, operation: prior.operationID)
                    try retireDelivery(prior.operationID)
                }
            }
            current.payload = try record.encoded()
        } else { context.insert(try SyncedDocument(record, scope: session.scope.key)) }
        if !(try context.fetch(FetchDescriptor<DurableIntent>()).contains { $0.operationID == record.operationID }) {
            context.insert(DurableIntent(operationID: record.operationID, entityID: record.id, revision: record.revision, kind: record.kind, payload: try record.encoded(), scope: session.scope.key))
        }
    }
    func nextBatch() throws -> [WireRecord] {
        guard accepts(session.scope), session.bootstrapComplete, session.retryAfter.map({ $0 <= Date() }) ?? true else { return [] }
        var blocked = Set(try context.fetch(FetchDescriptor<ConflictCandidate>()).filter { try $0.scope == session.scope.key && !$0.isResolved(in: context) }.map(\.entityID))
            .union(try context.fetch(FetchDescriptor<SyncedDocument>()).filter { !CloudCodec.writable($0.payload) }.map(\.id))
        for row in try context.fetch(FetchDescriptor<SyncedDocument>()) {
            let wire = try JSONDecoder().decode(WireRecord.self, from: row.payload)
            if let parentID = wire.parentID {
                guard let parent = try document(parentID) else { blocked.insert(wire.id); continue }
                let value = try JSONDecoder().decode(WireRecord.self, from: parent.payload)
                if blocked.contains(parentID) || value.deleted || (wire.parentIncarnation ?? parentID) != value.effectiveIncarnation { blocked.insert(wire.id) }
            }
        }
        let limit = max(1, min(session.batchLimit ?? 100, 100))
        func admitted(_ payload: Data) throws -> Bool {
            let wire = try JSONDecoder().decode(WireRecord.self, from: payload)
            guard !blocked.contains(wire.id), let row = try document(wire.id) else { return false }
            let current = try JSONDecoder().decode(WireRecord.self, from: row.payload)
            guard wire.effectiveIncarnation == current.effectiveIncarnation,
                  wire.parentID == current.parentID, wire.parentIncarnation == current.parentIncarnation else { return false }
            if let parentID = wire.parentID {
                guard !blocked.contains(parentID), let row = try document(parentID) else { return false }
                let parent = try JSONDecoder().decode(WireRecord.self, from: row.payload)
                return !parent.deleted && (wire.parentIncarnation ?? parentID) == parent.effectiveIncarnation
            }
            return true
        }
        let inflight = try context.fetch(FetchDescriptor<SentSnapshot>()).filter { try $0.scope == session.scope.key && admitted($0.payload) }
            .sorted { $0.operationID.uuidString < $1.operationID.uuidString }
        // Old oversized checkpoints are sliced, not discarded. Inflight gets priority
        // until ACK; pending only occupies the remaining capacity.
        var records = try inflight.prefix(limit).map { try JSONDecoder().decode(WireRecord.self, from: $0.payload) }
        var selected = Set(inflight.map(\.entityID))
        let pending = try pending().sorted {
            $0.revision == $1.revision ? $0.operationID.uuidString < $1.operationID.uuidString : $0.revision < $1.revision
        }
        for intent in pending where records.count < limit && !selected.contains(intent.entityID) {
            guard try admitted(intent.payload) else { continue }
            context.insert(SentSnapshot(intent)); selected.insert(intent.entityID)
            let baseKey = "sent-base/" + intent.operationID.uuidString
            if !(try context.fetch(FetchDescriptor<SyncCheckpoint>()).contains { $0.key == baseKey }) {
                context.insert(SyncCheckpoint(key: baseKey, data: try document(intent.entityID)?.ancestor ?? Data()))
            }
            if try operationReceipt(intent.operationID) == nil {
                try saveReceipt(OperationReceipt(payload: intent.payload, scope: intent.scope,
                    sentBase: try document(intent.entityID)?.ancestor, wasSent: true), operation: intent.operationID)
            }
            records.append(try JSONDecoder().decode(WireRecord.self, from: intent.payload))
        }
        records.sort { $0.operationID.uuidString < $1.operationID.uuidString }
        try commit()
        return records
    }
    func operationReceipt(_ operation: UUID) throws -> OperationReceipt? {
        try context.fetch(FetchDescriptor<SyncCheckpoint>()).first { $0.key == "operation-receipt/" + operation.uuidString }
            .map { try JSONDecoder().decode(OperationReceipt.self, from: $0.data) }
    }
    func saveReceipt(_ value: OperationReceipt, operation: UUID) throws {
        let key = "operation-receipt/" + operation.uuidString
        let bytes = try JSONEncoder().encode(value)
        if let row = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == key }) { row.data = bytes }
        else { context.insert(SyncCheckpoint(key: key, data: bytes)) }
    }
    func retireDelivery(_ operation: UUID) throws {
        for intent in try pending() where intent.operationID == operation { context.delete(intent) }
        for row in try context.fetch(FetchDescriptor<SentSnapshot>()) where row.scope == session.scope.key && row.operationID == operation { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SyncCheckpoint>()) where row.key == "sent-base/" + operation.uuidString { context.delete(row) }
    }
    // ACK and fetched self-delivery share the same exact provenance and retirement.
    // A known historical operation is consumed without rolling back a later base.
    func receiveOwnOperation(_ record: CKRecord, wire: WireRecord, raw: Data) throws -> Bool {
        guard CloudCodec.writable(raw) else { return false }
        var receipt = try operationReceipt(wire.operationID)
        if receipt == nil, let snapshot = try context.fetch(FetchDescriptor<SentSnapshot>()).first(where: {
            $0.scope == session.scope.key && $0.operationID == wire.operationID && $0.entityID == wire.id
        }) {
            let base = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first { $0.key == "sent-base/" + wire.operationID.uuidString }?.data
            receipt = OperationReceipt(payload: snapshot.payload, scope: snapshot.scope, sentBase: base.flatMap { $0.isEmpty ? nil : $0 }, wasSent: true)
        }
        guard var proof = receipt, proof.scope == session.scope.key,
              CloudCodec.writable(proof.payload),
              try JSONDecoder().decode(WireRecord.self, from: proof.payload) == wire else { return false }
        if proof.supersededBy != nil { return true }
        guard proof.wasSent else { return false }
        if proof.confirmed && session.restoring != true { return true }
        if let row = try document(wire.id), row.scope == session.scope.key {
            let current = try JSONDecoder().decode(WireRecord.self, from: row.payload)
            let unresolved = try context.fetch(FetchDescriptor<ConflictCandidate>()).contains {
                try $0.entityID == wire.id && $0.scope == session.scope.key && !$0.isResolved(in: context)
            }
            let sameBase = row.ancestor == proof.sentBase || row.ancestor == raw || (session.restoring == true && row.ancestor == nil)
            if !unresolved && sameBase && current.effectiveIncarnation == wire.effectiveIncarnation &&
                current.parentID == wire.parentID && current.parentIncarnation == wire.parentIncarnation {
                row.ancestor = raw; row.systemFields = archiveServerRecord(record)
            }
        }
        proof.confirmed = true
        try saveReceipt(proof, operation: wire.operationID)
        try retireDelivery(wire.operationID)
        return true
    }
    // A fresh conditional rejection of the replacement is distinct from a late
    // response for the retired child. Only the former may supply its retry base.
    func reconcileSupersededServerRecord(_ server: CKRecord, rejected: CKRecord, callback: SyncScope) throws -> Bool {
        guard accepts(callback) else { return false }
        let remote = try CloudCodec.decode(server, scope: callback)
        let local = try CloudCodec.decode(rejected, scope: callback)
        let raw = server.encryptedValues["payload"] as! Data
        guard CloudCodec.writable(raw), let proof = try operationReceipt(remote.operationID),
              proof.scope == callback.key, proof.supersededBy == local.operationID,
              try JSONDecoder().decode(WireRecord.self, from: proof.payload) == remote,
              let row = try document(local.id), row.scope == callback.key,
              try JSONDecoder().decode(WireRecord.self, from: row.payload) == local,
              let snapshot = try context.fetch(FetchDescriptor<SentSnapshot>()).first(where: {
                  $0.scope == callback.key && $0.operationID == local.operationID
              }), try JSONDecoder().decode(WireRecord.self, from: snapshot.payload) == local,
              var replacement = try operationReceipt(local.operationID), !replacement.confirmed,
              replacement.sentBase == row.ancestor else { return false }
        let native = try row.systemFields.map(nativeSystemFields)
        let currentRequest = try CloudCodec.encode(local, zone: rejected.recordID.zoneID, systemFields: native)
        guard rejected.recordChangeTag == currentRequest.recordChangeTag else { return false }
        guard try !context.fetch(FetchDescriptor<ConflictCandidate>()).contains(where: {
            try $0.entityID == local.id && $0.scope == callback.key && !$0.isResolved(in: context)
        }) else { return false }
        do {
            row.ancestor = raw; row.systemFields = archiveServerRecord(server)
            replacement.sentBase = raw
            try saveReceipt(replacement, operation: local.operationID)
            if let base = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "sent-base/" + local.operationID.uuidString }) { base.data = raw }
            try commit(); return true
        } catch { context.rollback(); throw error }
    }
    func acknowledge(_ record: CKRecord, callback: SyncScope) throws {
        guard accepts(callback) else { return }
        do {
            let wire = try CloudCodec.decode(record, scope: callback)
            _ = try receiveOwnOperation(record, wire: wire, raw: record.encryptedValues["payload"] as! Data)
            try commit()
        } catch { context.rollback(); throw error }
    }
    func apply(_ record: CKRecord, callback: SyncScope) throws {
        guard accepts(callback) else { return }
        let remote = try CloudCodec.decode(record, scope: callback)
        let raw = record.encryptedValues["payload"] as! Data
        do {
            if try receiveOwnOperation(record, wire: remote, raw: raw) { try commit(); return }
            if let existing = try document(remote.id) {
                guard existing.scope == callback.key else { throw ValidationFailure.invariant("cross-scope inbound requires plan") }
                let local = try JSONDecoder().decode(WireRecord.self, from: existing.payload)
                if local.deleted && !remote.deleted {
                    if remote.replacesDeletion != local.operationID {
                        // A conditional delete can lose to a concurrent server edit. Keep
                        // that content recoverable and block this entity until resolved.
                        try retainConflict(existing: existing, remote: raw)
                        existing.systemFields = archiveServerRecord(record)
                        try commit()
                        return
                    }
                    guard remote.incarnation != nil, remote.effectiveIncarnation != local.effectiveIncarnation else {
                        throw ValidationFailure.invariant("inbound re-add requires new incarnation")
                    }
                }
                // A replay of the exact predecessor cannot revoke an explicit re-add.
                if remote.deleted, !local.deleted, local.replacesDeletion == remote.operationID,
                   local.effectiveIncarnation != remote.effectiveIncarnation {
                    // Only the predecessor or an empty post-restore observation can
                    // accept this base; a later observed incarnation must not regress.
                    let unresolved = try context.fetch(FetchDescriptor<ConflictCandidate>()).contains {
                        try $0.entityID == remote.id && $0.scope == callback.key && !$0.isResolved(in: context)
                    }
                    if !unresolved && (existing.ancestor == nil || existing.ancestor == raw) && CloudCodec.writable(raw) {
                        existing.ancestor = raw; existing.systemFields = archiveServerRecord(record)
                        try commit()
                    }
                    return
                }
                // Cross-generation deletes/updates are not ordered by device-local revision.
                // Missing an intermediate delete is safe: retain both candidates and block
                // the old generation (including its children) rather than mixing fields.
                if local.effectiveIncarnation != remote.effectiveIncarnation,
                   !(local.deleted && remote.replacesDeletion == local.operationID),
                   (try remote.deleted || local.replacesDeletion != nil || remote.replacesDeletion == nil || pending().contains { $0.entityID == remote.id }) {
                    try retainConflict(existing: existing, remote: raw)
                    try commit(); return
                }
                if local.parentID != remote.parentID || local.parentIncarnation != remote.parentIncarnation {
                    let parent = try remote.parentID.flatMap { try document($0) }
                    let parentWire = try parent.map { try JSONDecoder().decode(WireRecord.self, from: $0.payload) }
                    let remoteMatches = parentWire.map { !$0.deleted && (remote.parentIncarnation ?? remote.parentID) == $0.effectiveIncarnation } ?? false
                    if try !remoteMatches || pending().contains(where: { $0.entityID == remote.id }) {
                        try retainConflict(existing: existing, remote: raw)
                        try commit(); return
                    }
                }
                let pendingLocal = try pending().contains { $0.entityID == remote.id }
                if !CloudCodec.writable(raw) {
                    if pendingLocal { try retainConflict(existing: existing, remote: raw) }
                    existing.payload = raw // Preserve the exact future message, and block writes/sends.
                } else if remote == local {
                    existing.ancestor = raw
                    existing.systemFields = archiveServerRecord(record)
                } else if remote.deleted {
                    if pendingLocal { try retainConflict(existing: existing, remote: raw) }
                    try discardDelivery(for: remote.id)
                    existing.payload = raw; existing.ancestor = raw
                } else if let known = existing.ancestor, try JSONDecoder().decode(WireRecord.self, from: known) == remote {
                    existing.systemFields = archiveServerRecord(record)
                } else if pendingLocal {
                    let ancestor = try existing.ancestor.map { try JSONDecoder().decode(WireRecord.self, from: $0) }
                    if let ancestor, let merged = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote) {
                        try discardDelivery(for: remote.id)
                        existing.ancestor = raw; existing.systemFields = archiveServerRecord(record)
                        try stageWrite(merged)
                    } else { try retainConflict(existing: existing, remote: raw) }
                } else {
                    existing.payload = raw; existing.ancestor = raw
                }
                existing.systemFields = archiveServerRecord(record)
            } else {
                let row = try SyncedDocument(remote, scope: callback.key)
                row.payload = raw; row.ancestor = raw; row.systemFields = archiveServerRecord(record)
                context.insert(row)
            }
            try projectVisibleRecord(remote.id)
            try commit()
        } catch {
            context.rollback()
            session.pauseReason = "inbound persistence/validation failure; checkpoint retained"
            session.bootstrapComplete = false
            // If storage remains unavailable, the previous persisted engine state still replays.
            do { try saveSession() } catch { /* Preserve the original application error. */ }
            throw error
        }
    }
    func discardDelivery(for id: UUID) throws {
        for intent in try pending() where intent.entityID == id {
            for base in try context.fetch(FetchDescriptor<SyncCheckpoint>()) where base.key == "sent-base/" + intent.operationID.uuidString { context.delete(base) }
            context.delete(intent)
        }
        for snapshot in try context.fetch(FetchDescriptor<SentSnapshot>()) where snapshot.entityID == id && snapshot.scope == session.scope.key { context.delete(snapshot) }
    }
    func retainConflict(existing: SyncedDocument, remote: Data) throws {
        let remoteWire = try JSONDecoder().decode(WireRecord.self, from: remote)
        let duplicates = try context.fetch(FetchDescriptor<ConflictCandidate>()).contains {
            $0.entityID == existing.id && (try? JSONDecoder().decode(WireRecord.self, from: $0.remote).operationID) == remoteWire.operationID
        }
        if !duplicates { context.insert(ConflictCandidate(entityID: existing.id, local: existing.payload, remote: remote, scope: session.scope.key)) }
    }
    func persistEngineState(_ bytes: Data, callback: SyncScope) throws {
        guard accepts(callback) else { return }
        session.engineSerialization = bytes; try saveSession()
    }
    func finishBootstrap(callback: SyncScope) throws {
        guard accepts(callback) else { return }
        session.bootstrapComplete = true; session.restoring = false; try saveSession()
    }
    func pause(_ reason: String) throws {
        session.pauseReason = reason; session.bootstrapComplete = false; try saveSession()
    }
}


@MainActor extension SyncCore {
    static func local(context: ModelContext, library: UUID, root: URL) throws -> SyncCore {
        let stored = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first { $0.key == "session" }
        let scope = try stored.map { try JSONDecoder().decode(SessionState.self, from: $0.data).scope }
            ?? SyncScope(container: "unbound", environment: "Development", account: "unbound", library: library, zone: "HHOSVAL_" + library.uuidString, epoch: UUID())
        guard scope.library == library else { throw ValidationFailure.invariant("library binding mismatch") }
        return try SyncCore(context: context, scope: scope, mediaRoot: root)
    }

    func bindInitial(to scope: SyncScope) throws {
        guard session.pauseReason == nil, session.scope.account == "unbound", session.scope.container == "unbound", scope.library == session.scope.library,
              scope.environment == "Development", scope.zone.hasPrefix("HHOSVAL_") else {
            throw ValidationFailure.invariant("new account requires explicit recovery/binding plan")
        }
        for intent in try pending() { intent.scope = scope.key }
        for row in try context.fetch(FetchDescriptor<SyncedDocument>()) where row.scope == session.scope.key { row.scope = scope.key }
        for conflict in try context.fetch(FetchDescriptor<ConflictCandidate>()) where conflict.scope == session.scope.key || conflict.scope == "resolved/" + session.scope.key {
            try conflict.rebind(to: scope.key, in: context)
        }
        session = SessionState(scope: scope)
        try saveSession()
    }

    func projectVisibleRecord(_ id: UUID) throws {
        guard let row = try document(id), row.scope == session.scope.key else { return }
        let wire = try JSONDecoder().decode(WireRecord.self, from: row.payload)
        guard CloudCodec.writable(row.payload) else { return }
        if wire.deleted {
            try removeProjection(id)
            for child in try context.fetch(FetchDescriptor<SyncedDocument>()) {
                let value = try JSONDecoder().decode(WireRecord.self, from: child.payload)
                if value.parentID == id { try removeProjection(value.id) }
            }
            return
        }
        if let parent = wire.parentID {
            guard let parentRow = try document(parent) else { return } // Quarantine until its parent arrives.
            let parentWire = try JSONDecoder().decode(WireRecord.self, from: parentRow.payload)
            guard !parentWire.deleted, (wire.parentIncarnation ?? parent) == parentWire.effectiveIncarnation else { try removeProjection(id); return }
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000) // Fixture projection, not a precision claim about user dates.
        if wire.kind == "draft" {
            if let draft = try context.fetch(FetchDescriptor<CaptureDraftRecord>()).first(where: { $0.id == id }) {
                draft.name = wire.name ?? ""; draft.categoryID = wire.category.flatMap(UUID.init(uuidString:))
            } else {
                context.insert(CaptureDraftRecord(id: id, householdID: wire.library, name: wire.name ?? "", categoryID: wire.category.flatMap(UUID.init(uuidString:)), createdAt: date, updatedAt: date, captureSource: .manual))
            }
        } else if wire.kind == "item" {
            if let item = try context.fetch(FetchDescriptor<ItemRecord>()).first(where: { $0.id == id }) {
                item.name = wire.name ?? ""; item.categoryID = wire.category.flatMap(UUID.init(uuidString:))
            } else {
                context.insert(ItemRecord(id: id, householdID: wire.library, name: wire.name ?? "", categoryID: wire.category.flatMap(UUID.init(uuidString:)), createdAt: date, updatedAt: date, captureSource: .manual, sourceDraftID: wire.sourceDraftID))
            }
            for draft in try context.fetch(FetchDescriptor<CaptureDraftRecord>()) where draft.id == wire.sourceDraftID { context.delete(draft) }
        }
        if wire.kind == "item" || wire.kind == "draft" {
            for profile in try context.fetch(FetchDescriptor<WardrobeProfile>()) where profile.ownerID == id && profile.id != wire.profile?.id {
                context.delete(profile)
            }
        }
        if let profile = wire.profile {
            if let existing = try context.fetch(FetchDescriptor<WardrobeProfile>()).first(where: { $0.id == profile.id }) {
                existing.ownerID = id; existing.size = profile.size; existing.material = profile.material
            } else { context.insert(WardrobeProfile(id: profile.id, ownerID: id, size: profile.size, material: profile.material)) }
        }
        if wire.kind == "media", let descriptor = wire.media, let parent = wire.parentID, let root = mediaRoot {
            let previewName = "\(descriptor.representationID).preview.jpg"
            let ownerKind: MediaOwnerKind = try context.fetch(FetchDescriptor<ItemRecord>()).contains { $0.id == parent } ? .item : .draft
            let retained = try context.fetch(FetchDescriptor<MediaRepresentation>()).first { $0.id == descriptor.representationID }
            if let retained {
                guard retained.mediaID == id, retained.revision == descriptor.revision, retained.originalHash == descriptor.hash else {
                    throw ValidationFailure.invariant("immutable representation descriptor changed")
                }
            }
            let previewURL = root.appendingPathComponent("media/" + previewName)
            if FileManager.default.fileExists(atPath: previewURL.path) {
                guard try Data(contentsOf: previewURL) == descriptor.preview else {
                    throw ValidationFailure.invariant("immutable recovery preview changed")
                }
            } else { try MediaFiles.write(descriptor.preview, to: previewURL) }
            let originalName = retained.map { URL(fileURLWithPath: $0.relativePath).lastPathComponent } ?? "\(descriptor.representationID).original"
            if let existing = try context.fetch(FetchDescriptor<MediaAssetRecord>()).first(where: { $0.id == id }) {
                existing.ownerID = parent; existing.ownerKind = ownerKind; existing.thumbnailFileName = previewName
                existing.originalFileName = originalName; existing.contentTypeIdentifier = descriptor.contentType
            } else {
                context.insert(MediaAssetRecord(id: id, ownerKind: ownerKind, ownerID: parent, originalFileName: originalName, thumbnailFileName: previewName, contentTypeIdentifier: descriptor.contentType, createdAt: date, sortOrder: 0))
            }
            if !(try context.fetch(FetchDescriptor<MediaRepresentation>()).contains { $0.id == descriptor.representationID }) {
                context.insert(MediaRepresentation(id: descriptor.representationID, mediaID: id, revision: descriptor.revision, precision: descriptor.precision, originalHash: descriptor.hash, relativePath: "media/\(descriptor.representationID).original", photosReference: descriptor.photosReference))
            }
        }
        if wire.kind == "item" || wire.kind == "draft" {
            for child in try context.fetch(FetchDescriptor<SyncedDocument>()) {
                let value = try JSONDecoder().decode(WireRecord.self, from: child.payload)
                if value.parentID == id { try projectVisibleRecord(value.id) }
            }
        }
    }
}


@MainActor extension SyncCore {
    func currentRepresentation(_ mediaID: UUID) throws -> MediaRepresentation {
        guard let row = try document(mediaID), row.scope == session.scope.key else { throw ValidationFailure.invariant("current media wire unavailable") }
        let wire = try JSONDecoder().decode(WireRecord.self, from: row.payload)
        guard !wire.deleted, let descriptor = wire.media,
              let representation = try context.fetch(FetchDescriptor<MediaRepresentation>()).first(where: { $0.id == descriptor.representationID }),
              representation.mediaID == mediaID, representation.revision == descriptor.revision,
              representation.originalHash == descriptor.hash, representation.precision == descriptor.precision else {
            throw ValidationFailure.invariant("current representation unavailable or descriptor mismatch")
        }
        return representation
    }

    func removeProjection(_ id: UUID) throws {
        for item in try context.fetch(FetchDescriptor<ItemRecord>()) where item.id == id { context.delete(item) }
        for draft in try context.fetch(FetchDescriptor<CaptureDraftRecord>()) where draft.id == id { context.delete(draft) }
        for media in try context.fetch(FetchDescriptor<MediaAssetRecord>()) where media.id == id { context.delete(media) }
        for profile in try context.fetch(FetchDescriptor<WardrobeProfile>()) where profile.ownerID == id { context.delete(profile) }
        // Files and representation history remain recoverable; no tombstone GC in this prototype.
    }
}

enum ThreeWayMerge {
    static func merge(ancestor: WireRecord, local: WireRecord, remote: WireRecord) -> WireRecord? {
        guard ancestor.id == local.id, local.id == remote.id, !ancestor.deleted, !local.deleted, !remote.deleted,
              local.library == remote.library, ancestor.library == local.library,
              ancestor.effectiveIncarnation == local.effectiveIncarnation, local.effectiveIncarnation == remote.effectiveIncarnation,
              ancestor.parentID == local.parentID, local.parentID == remote.parentID,
              ancestor.parentIncarnation == local.parentIncarnation, local.parentIncarnation == remote.parentIncarnation,
              ancestor.replacesDeletion == local.replacesDeletion, local.replacesDeletion == remote.replacesDeletion,
              local.kind == remote.kind,
              (ancestor.kind == local.kind || (ancestor.kind == "draft" && local.kind == "item" && local.sourceDraftID == ancestor.id && remote.sourceDraftID == ancestor.id)),
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


@MainActor extension SyncCore {
    func prepareRestoreAdmission(to scope: SyncScope) throws {
        guard session.pauseReason == "restored snapshot requires cloud admission against current tombstones",
              session.scope.account == "unbound", scope.library == session.scope.library,
              scope.environment == "Development", scope.zone.hasPrefix("HHOSVAL_") else {
            throw ValidationFailure.invariant("restore admission scope mismatch")
        }
        let oldScope = session.scope.key
        for row in try context.fetch(FetchDescriptor<SyncedDocument>()) where row.scope == oldScope {
            row.scope = scope.key; row.ancestor = nil; row.systemFields = nil
            let wire = try JSONDecoder().decode(WireRecord.self, from: row.payload)
            if CloudCodec.writable(row.payload), !(try context.fetch(FetchDescriptor<DurableIntent>()).contains { $0.operationID == wire.operationID }) {
                context.insert(DurableIntent(operationID: wire.operationID, entityID: wire.id, revision: wire.revision, kind: wire.kind, payload: row.payload, scope: scope.key))
            }
        }
        for intent in try context.fetch(FetchDescriptor<DurableIntent>()) where intent.scope == oldScope { intent.scope = scope.key }
        for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>()) where checkpoint.key.hasPrefix("operation-receipt/") {
            var receipt = try JSONDecoder().decode(OperationReceipt.self, from: checkpoint.data)
            if receipt.scope == scope.key || receipt.scope.hasPrefix("unbound/Development/unbound/") {
                receipt.scope = scope.key
                checkpoint.data = try JSONEncoder().encode(receipt)
            }
        }
        for conflict in try context.fetch(FetchDescriptor<ConflictCandidate>()) where conflict.scope == oldScope || conflict.scope == "resolved/" + oldScope { try conflict.rebind(to: scope.key, in: context) }
        session = SessionState(scope: scope, enabled: true, restoring: true)
        try saveSession() // Enabled for fetch only; bootstrapComplete is still false.
    }
}
