// The following apply() and nextBatch() bodies are copied from
// SyncProtocol.swift @449328ea87b40f773c4dcfa957f3ae00bf43e7ef.
// Hosting class/SDK types are test doubles from ProbeSupport.swift.
import Foundation
extension SyncCoreProbe {
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
                // A replay of the exact predecessor cannot revoke an explicit re-add.
                if remote.deleted, !local.deleted, local.replacesDeletion == remote.operationID,
                   local.effectiveIncarnation != remote.effectiveIncarnation {
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
                // Fetching the exact sent operation also resolves a lost ACK, never a newer edit.
                for intent in try pending() where intent.operationID == remote.operationID {
                    if try JSONDecoder().decode(WireRecord.self, from: intent.payload) == remote {
                        context.delete(intent)
                        for base in try context.fetch(FetchDescriptor<SyncCheckpoint>()) where base.key == "sent-base/" + remote.operationID.uuidString { context.delete(base) }
                        for snapshot in try context.fetch(FetchDescriptor<SentSnapshot>()) where snapshot.operationID == remote.operationID { context.delete(snapshot) }
                    }
                }
                let pendingLocal = try pending().contains { $0.entityID == remote.id }
                if !CloudCodec.writable(raw) {
                    if pendingLocal { try retainConflict(existing: existing, remote: raw) }
                    existing.payload = raw // Preserve the exact future message, and block writes/sends.
                } else if remote == local {
                    existing.ancestor = raw
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
            records.append(try JSONDecoder().decode(WireRecord.self, from: intent.payload))
        }
        records.sort { $0.operationID.uuidString < $1.operationID.uuidString }
        try commit()
        return records
    }
}
