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
    var restoring: Bool?
    var retryAfter: Date?
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
                    conflict.scope = "resolved/" + session.scope.key // Retain the candidate as history, unblock the explicit new decision.
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
        var blocked = Set(try context.fetch(FetchDescriptor<ConflictCandidate>()).filter { $0.scope == session.scope.key }.map(\.entityID))
            .union(try context.fetch(FetchDescriptor<SyncedDocument>()).filter { !CloudCodec.writable($0.payload) }.map(\.id))
        for row in try context.fetch(FetchDescriptor<SyncedDocument>()) {
            let wire = try JSONDecoder().decode(WireRecord.self, from: row.payload)
            if let parentID = wire.parentID {
                guard let parent = try document(parentID) else { blocked.insert(wire.id); continue }
                let value = try JSONDecoder().decode(WireRecord.self, from: parent.payload)
                if value.deleted || (wire.parentIncarnation ?? parentID) != value.effectiveIncarnation { blocked.insert(wire.id) }
            }
        }
        let inflight = try context.fetch(FetchDescriptor<SentSnapshot>()).filter { $0.scope == session.scope.key && !blocked.contains($0.entityID) }
        var records = try inflight.map { try JSONDecoder().decode(WireRecord.self, from: $0.payload) }
        var selected = Set(records.map(\.id))
        for intent in try pending().sorted(by: { $0.revision < $1.revision }) where !selected.contains(intent.entityID) && !blocked.contains(intent.entityID) {
            context.insert(SentSnapshot(intent)); selected.insert(intent.entityID)
            records.append(try JSONDecoder().decode(WireRecord.self, from: intent.payload))
            if records.count == 100 { break }
        }
        try commit()
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
            let ancestor = try document.ancestor.map { try JSONDecoder().decode(WireRecord.self, from: $0) }
            let candidates = try context.fetch(FetchDescriptor<ConflictCandidate>()).filter { $0.entityID == wire.id && $0.scope == callback.key }
            let observed = try candidates.map { try JSONDecoder().decode(WireRecord.self, from: $0.remote) } + (ancestor.map { [$0] } ?? [])
            // An exact operation ACK retires its intent, but cannot roll back a later
            // fetched server version/change tag or an unresolved concurrent candidate.
            if !observed.contains(where: { $0.revision >= wire.revision && $0.operationID != wire.operationID }) {
                document.ancestor = try wire.encoded()
                document.systemFields = CloudCodec.systemFields(record)
            }
        }
        try commit()
    }
    func apply(_ record: CKRecord, callback: SyncScope) throws {
        guard accepts(callback) else { return }
        let remote = try CloudCodec.decode(record, scope: callback)
        let raw = record.encryptedValues["payload"] as! Data
        do {
            if let existing = try document(remote.id) {
                guard existing.scope == callback.key else { throw ValidationFailure.invariant("cross-scope inbound requires plan") }
                let local = try JSONDecoder().decode(WireRecord.self, from: existing.payload)
                if local.deleted && !remote.deleted {
                    if remote.replacesDeletion != local.operationID {
                        // A conditional delete can lose to a concurrent server edit. Keep
                        // that content recoverable and block this entity until resolved.
                        try retainConflict(existing: existing, remote: raw)
                        existing.systemFields = CloudCodec.systemFields(record)
                        try commit()
                        return
                    }
                    guard remote.incarnation != nil, remote.effectiveIncarnation != local.effectiveIncarnation else {
                        throw ValidationFailure.invariant("inbound re-add requires new incarnation")
                    }
                }
                if let ancestor = try existing.ancestor.map({ try JSONDecoder().decode(WireRecord.self, from: $0) }), remote.revision < ancestor.revision { return }
                // Fetching the exact sent operation also resolves a lost ACK, never a newer edit.
                for intent in try pending() where intent.operationID == remote.operationID {
                    if try JSONDecoder().decode(WireRecord.self, from: intent.payload) == remote {
                        context.delete(intent)
                        for snapshot in try context.fetch(FetchDescriptor<SentSnapshot>()) where snapshot.operationID == remote.operationID { context.delete(snapshot) }
                    }
                }
                let pendingLocal = try pending().contains { $0.entityID == remote.id }
                if !CloudCodec.writable(raw) {
                    if pendingLocal { try retainConflict(existing: existing, remote: raw) }
                    existing.payload = raw // Preserve the exact future message, and block writes/sends.
                } else if remote == local {
                    existing.systemFields = CloudCodec.systemFields(record)
                } else if remote.deleted {
                    if pendingLocal { try retainConflict(existing: existing, remote: raw) }
                    try discardDelivery(for: remote.id)
                    existing.payload = raw; existing.ancestor = raw
                } else if let known = existing.ancestor, try JSONDecoder().decode(WireRecord.self, from: known) == remote {
                    existing.systemFields = CloudCodec.systemFields(record)
                } else if pendingLocal {
                    let ancestor = try existing.ancestor.map { try JSONDecoder().decode(WireRecord.self, from: $0) }
                    if let ancestor, let merged = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote) {
                        try discardDelivery(for: remote.id)
                        existing.ancestor = raw; existing.systemFields = CloudCodec.systemFields(record)
                        try stageWrite(merged)
                    } else { try retainConflict(existing: existing, remote: raw) }
                } else {
                    existing.payload = raw; existing.ancestor = raw
                }
                existing.systemFields = CloudCodec.systemFields(record)
            } else {
                let row = try SyncedDocument(remote, scope: callback.key)
                row.payload = raw; row.ancestor = raw; row.systemFields = CloudCodec.systemFields(record)
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
        for intent in try pending() where intent.entityID == id { context.delete(intent) }
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
    func removeProjection(_ id: UUID) throws {
        for item in try context.fetch(FetchDescriptor<ItemRecord>()) where item.id == id { context.delete(item) }
        for draft in try context.fetch(FetchDescriptor<CaptureDraftRecord>()) where draft.id == id { context.delete(draft) }
        for media in try context.fetch(FetchDescriptor<MediaAssetRecord>()) where media.id == id { context.delete(media) }
        // Files and representation history remain recoverable; no tombstone GC in this prototype.
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
        for conflict in try context.fetch(FetchDescriptor<ConflictCandidate>()) where conflict.scope == oldScope { conflict.scope = scope.key }
        session = SessionState(scope: scope, enabled: true, restoring: true)
        try saveSession() // Enabled for fetch only; bootstrapComplete is still false.
    }
}
