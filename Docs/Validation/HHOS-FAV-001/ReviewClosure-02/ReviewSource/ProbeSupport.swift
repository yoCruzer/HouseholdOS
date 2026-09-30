// Review-only Linux doubles. NOT SwiftData, NOT CloudKit, no disk/crash validation.
// Only data access/commit and CKRecord encoding are replaced. The extracted reducers are separate.
import Foundation
struct SyncScope: Equatable { var library = UUID(); var key = "review-scope" }
struct SessionState { var scope: SyncScope; var enabled = true; var bootstrapComplete = true; var pauseReason: String?; var retryAfter: Date?; var batchLimit: Int? }
struct FetchDescriptor<T> { init() {} }
final class ModelContext {
    var rows: [AnyObject] = []
    func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] { rows.compactMap { $0 as? T } }
    func insert(_ row: AnyObject) { rows.append(row) }
    func delete(_ row: AnyObject) { rows.removeAll { $0 === row } }
    func rollback() {} // Faults/rollback intentionally NOT exercised by these probes.
}
final class SyncedDocument {
    var id: UUID; var payload: Data; var ancestor: Data?; var systemFields: Data?; var scope: String
    init(_ wire: WireRecord, scope: String) throws { id=wire.id; payload=try wire.encoded(); self.scope=scope }
}
final class SyncCheckpoint { var key: String; var data: Data; init(key: String,data: Data){self.key=key;self.data=data} }
final class DurableIntent {
    var operationID: UUID;var entityID:UUID;var revision:Int;var kind:String;var payload:Data;var scope:String
    init(_ w: WireRecord, scope:String) throws { operationID=w.operationID;entityID=w.id;revision=w.revision;kind=w.kind;payload=try w.encoded();self.scope=scope }
}
final class SentSnapshot {
    var operationID:UUID;var entityID:UUID;var payload:Data;var scope:String
    init(_ i:DurableIntent){operationID=i.operationID;entityID=i.entityID;payload=i.payload;scope=i.scope}
}
final class ConflictCandidate {
    var id=UUID();var entityID:UUID;var local:Data;var remote:Data;var scope:String
    init(entityID:UUID,local:Data,remote:Data,scope:String){self.entityID=entityID;self.local=local;self.remote=remote;self.scope=scope}
    func isResolved(in c: ModelContext) throws -> Bool { try scope.hasPrefix("resolved/") || c.fetch(FetchDescriptor<SyncCheckpoint>()).contains { $0.key == "conflict-resolution/"+id.uuidString } }
}
struct CKRecord {
    var wire:WireRecord; var tag:String
    var encryptedValues:[String:Any]
    init(_ wire:WireRecord,tag:String)throws{self.wire=wire;self.tag=tag;encryptedValues=["payload":try wire.encoded()]}
}
enum CloudCodec {
    static func decode(_ record:CKRecord,scope:SyncScope)throws->WireRecord{try record.wire.validated()}
    static func systemFields(_ record:CKRecord)->Data{Data(record.tag.utf8)}
    static func writable(_ bytes:Data)->Bool{true} // All fixtures are known format=1, no unknown data.
}
final class SyncCoreProbe {
    let context=ModelContext();var session=SessionState(scope:SyncScope())
    func accepts(_ scope:SyncScope)->Bool{session.enabled && session.pauseReason == nil && scope == session.scope}
    func document(_ id:UUID)throws->SyncedDocument?{try context.fetch(FetchDescriptor<SyncedDocument>()).first{$0.id==id}}
    func pending()throws->[DurableIntent]{try context.fetch(FetchDescriptor<DurableIntent>()).filter{$0.scope==session.scope.key}}
    func commit()throws{} // No native persistence claims.
    func saveSession()throws{}
    func projectVisibleRecord(_ id:UUID)throws{} // Projection does not change these outbox/base/conflict outcomes.
    func stageWrite(_ wire:WireRecord)throws{
        if let row=try document(wire.id){row.payload=try wire.encoded()}else{context.insert(try SyncedDocument(wire,scope:session.scope.key))}
        context.insert(try DurableIntent(wire,scope:session.scope.key))
    }
    func retainConflict(existing:SyncedDocument,remote:Data)throws{
        let w=try JSONDecoder().decode(WireRecord.self,from:remote)
        let found=try context.fetch(FetchDescriptor<ConflictCandidate>()).contains{$0.entityID==existing.id && (try? JSONDecoder().decode(WireRecord.self,from:$0.remote).operationID)==w.operationID}
        if !found { context.insert(ConflictCandidate(entityID:existing.id,local:existing.payload,remote:remote,scope:session.scope.key)) }
    }
    func discardDelivery(for id:UUID)throws{
        for i in try pending() where i.entityID==id {context.delete(i)}
        for s in try context.fetch(FetchDescriptor<SentSnapshot>()) where s.entityID==id {context.delete(s)}
    }
}
