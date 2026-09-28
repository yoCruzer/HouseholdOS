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

    func validated() throws -> WireRecord {
        guard revision > 0, ["draft", "item", "media", "usage"].contains(kind),
              (amount == nil) == (currency == nil),
              amount == nil || Decimal(string: amount!, locale: Locale(identifier: "en_US_POSIX")) != nil else {
            throw ValidationFailure.invariant("invalid wire data")
        }
        if deleted && [name, category, amount, currency].contains(where: { $0 != nil }) {
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
        id = record.id; payload = try JSONEncoder().encode(record); self.scope = scope
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

@Model final class SentSnapshot {
    @Attribute(.unique) var operationID: UUID
    var entityID: UUID
    var payload: Data
    var scope: String
    init(_ intent: DurableIntent) {
        operationID = intent.operationID; entityID = intent.entityID; payload = intent.payload; scope = intent.scope
    }
}

struct SessionState: Codable {
    var scope: SyncScope
    var enabled = false
    var bootstrapComplete = false
    var pauseReason: String?
    var engineSerialization: Data?
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
        record.encryptedValues["payload"] = try JSONEncoder().encode(wire) as CKRecordValue
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
    static func systemFields(_ record: CKRecord) -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder); encoder.finishEncoding()
        return encoder.encodedData
    }
}

@MainActor final class SyncCore {
    let context: ModelContext
    var session: SessionState
    init(context: ModelContext, scope: SyncScope) throws {
        self.context = context
        if let saved = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "session" }) {
            session = try JSONDecoder().decode(SessionState.self, from: saved.data)
            if session.scope != scope {
                session = SessionState(scope: scope, pauseReason: "explicit account/library binding required")
            }
        } else { session = SessionState(scope: scope) }
        context.autosaveEnabled = false
    }
    func saveSession() throws {
        let data = try JSONEncoder().encode(session)
        if let row = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: { $0.key == "session" }) { row.data = data }
        else { context.insert(SyncCheckpoint(key: "session", data: data)) }
        try context.save()
    }
    func setEnabled(_ value: Bool) throws {
        session.enabled = value
        if !value { session.scope.epoch = UUID(); session.bootstrapComplete = false; session.engineSerialization = nil }
        try saveSession()
    }
    func accepts(_ scope: SyncScope) -> Bool { session.enabled && session.scope == scope && session.pauseReason == nil }
    func document(_ id: UUID) throws -> SyncedDocument? {
        try context.fetch(FetchDescriptor<SyncedDocument>()).first { $0.id == id }
    }
    func pending() throws -> [DurableIntent] {
        try context.fetch(FetchDescriptor<DurableIntent>()).filter { $0.scope == session.scope.key }
    }
    func write(_ record: WireRecord) throws {
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
            guard old.format == 1 else { throw ValidationFailure.invariant("future data is write protected") }
            guard !old.deleted || record.deleted || record.replacesDeletion == old.operationID else { throw ValidationFailure.invariant("explicit re-add intent required") }
            current.payload = try JSONEncoder().encode(record)
        } else { context.insert(try SyncedDocument(record, scope: session.scope.key)) }
        if !(try context.fetch(FetchDescriptor<DurableIntent>()).contains { $0.operationID == record.operationID }) {
            context.insert(DurableIntent(operationID: record.operationID, entityID: record.id, revision: record.revision, kind: record.kind, payload: try JSONEncoder().encode(record), scope: session.scope.key))
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func nextBatch() throws -> [WireRecord] {
        guard session.enabled, session.bootstrapComplete, session.pauseReason == nil else { return [] }
        let inflight = try context.fetch(FetchDescriptor<SentSnapshot>()).filter { $0.scope == session.scope.key }
        var records = try inflight.map { try JSONDecoder().decode(WireRecord.self, from: $0.payload) }
        var selected = Set(records.map(\.id))
        for intent in try pending().sorted(by: { $0.revision < $1.revision }) where !selected.contains(intent.entityID) {
            context.insert(SentSnapshot(intent)); selected.insert(intent.entityID)
            records.append(try JSONDecoder().decode(WireRecord.self, from: intent.payload))
            if records.count == 100 { break }
        }
        try context.save()
        return records
    }
    func acknowledge(_ record: CKRecord, callback: SyncScope) throws {
        guard accepts(callback) else { return }
        let wire = try CloudCodec.decode(record, scope: callback)
        guard let snapshot = try context.fetch(FetchDescriptor<SentSnapshot>()).first(where: { $0.scope == callback.key && $0.operationID == wire.operationID }),
              try JSONDecoder().decode(WireRecord.self, from: snapshot.payload) == wire else { return }
        for intent in try pending() where intent.operationID == wire.operationID { context.delete(intent) }
        context.delete(snapshot)
        if let document = try document(wire.id) {
            document.ancestor = try JSONEncoder().encode(wire)
            document.systemFields = CloudCodec.systemFields(record)
        }
        try context.save()
    }
    func apply(_ record: CKRecord, callback: SyncScope) throws {
        guard accepts(callback) else { return }
        let remote = try CloudCodec.decode(record, scope: callback)
        if let existing = try document(remote.id) {
            guard existing.scope == callback.key else { throw ValidationFailure.invariant("cross-scope inbound requires plan") }
            let local = try JSONDecoder().decode(WireRecord.self, from: existing.payload)
            if local.deleted && !remote.deleted && remote.replacesDeletion != local.operationID { return }
            if remote == local { existing.systemFields = CloudCodec.systemFields(record); try context.save(); return }
            if try pending().contains(where: { $0.entityID == remote.id }) {
                context.insert(ConflictCandidate(entityID: remote.id, local: existing.payload, remote: try JSONEncoder().encode(remote), scope: callback.key))
            } else {
                existing.payload = try JSONEncoder().encode(remote)
                existing.ancestor = existing.payload
                existing.systemFields = CloudCodec.systemFields(record)
            }
        } else {
            let document = try SyncedDocument(remote, scope: callback.key)
            document.ancestor = document.payload; document.systemFields = CloudCodec.systemFields(record)
            context.insert(document)
        }
        // No outbox is generated by inbound application; failures propagate before token persistence.
        try context.save()
    }
    func persistEngineState(_ bytes: Data, callback: SyncScope) throws {
        guard accepts(callback) else { return }
        session.engineSerialization = bytes; try saveSession()
    }
    func finishBootstrap(callback: SyncScope) throws {
        guard accepts(callback) else { return }
        session.bootstrapComplete = true; try saveSession()
    }
    func pause(_ reason: String) throws {
        session.pauseReason = reason; session.bootstrapComplete = false; try saveSession()
    }
}
