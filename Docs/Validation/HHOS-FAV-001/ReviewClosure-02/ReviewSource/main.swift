import Foundation
func decode(_ c: SyncCoreProbe,_ id:UUID)throws->WireRecord{try JSONDecoder().decode(WireRecord.self,from:c.document(id)!.payload)}

// Positive control: the original cross-incarnation merge counterexample is fixed.
do {
    let c=SyncCoreProbe(), id=UUID()
    let a=WireRecord(id:id,operationID:UUID(),revision:1,library:c.session.scope.library,kind:"item",name:"base")
    var l=a;l.operationID=UUID();l.revision=2;l.category="local"
    var r=a;r.operationID=UUID();r.revision=3;r.name="new";r.incarnation=UUID();r.replacesDeletion=UUID()
    print("CONTROL cross_incarnation_merge_rejected=\(ThreeWayMerge.merge(ancestor:a,local:l,remote:r)==nil)")
}
// R2-01: state after BackupRestore.restore + prepareRestoreAdmission: local re-add,
// no systemFields/ancestor. Fetch exact predecessor from current server.
do {
    let c=SyncCoreProbe()
    let d=WireRecord(id:UUID(),operationID:UUID(),revision:2,library:c.session.scope.library,kind:"item",deleted:true)
    var r=d;r.operationID=UUID();r.revision=3;r.deleted=false;r.name="explicit re-add";r.incarnation=UUID();r.replacesDeletion=d.operationID
    try c.stageWrite(r)
    let remote=try CKRecord(d,tag:"SERVER_D_V1")
    for _ in 0..<3 { try c.apply(remote,callback:c.session.scope) }
    let doc=try c.document(r.id)!
    print("R2-01 readd_preserved=\(try decode(c,r.id)==r) system_fields_nil=\(doc.systemFields==nil) ancestor_nil=\(doc.ancestor==nil) ready_count=\(try c.nextBatch().count) conditional_tag_matches_server=\(doc.systemFields==Data(remote.tag.utf8))")
}
// R2-02: true local continuation, not a concurrent remote edit. Exact sent version
// is returned by fetch before the newer local revision is sent.
for hasAncestor in [false,true] {
    let c=SyncCoreProbe()
    let base=WireRecord(id:UUID(),operationID:UUID(),revision:6,library:c.session.scope.library,kind:"item",name:"six")
    if hasAncestor {try c.apply(CKRecord(base,tag:"SERVER_6"),callback:c.session.scope)}
    var seven=base;seven.operationID=UUID();seven.revision=7;seven.name="seven"
    try c.stageWrite(seven);_ = try c.nextBatch()
    var eight=seven;eight.operationID=UUID();eight.revision=8;eight.name="eight"
    try c.stageWrite(eight)
    try c.apply(CKRecord(seven,tag:"SERVER_7"),callback:c.session.scope)
    print("R2-02 ancestor_initially_present=\(hasAncestor) local8_preserved=\(try decode(c,eight.id)==eight) pending_revisions=\(try c.pending().map(\.revision)) conflict_count=\(try c.context.fetch(FetchDescriptor<ConflictCandidate>()).count) ready_count=\(try c.nextBatch().count)")
}
// R2-03: old unsent child belongs to the prior parent incarnation. New parent and
// explicit child rebind can be sent, but the old child has no terminal outbox state.
do {
    let c=SyncCoreProbe()
    let parent=WireRecord(id:UUID(),operationID:UUID(),revision:1,library:c.session.scope.library,kind:"item",name:"old")
    try c.apply(CKRecord(parent,tag:"P1"),callback:c.session.scope)
    let oldChild=WireRecord(id:UUID(),operationID:UUID(),revision:1,library:c.session.scope.library,kind:"usage",parentID:parent.id)
    try c.stageWrite(oldChild)
    var d=parent;d.operationID=UUID();d.revision=2;d.name=nil;d.deleted=true
    try c.apply(CKRecord(d,tag:"D2"),callback:c.session.scope)
    var readd=parent;readd.operationID=UUID();readd.revision=3;readd.incarnation=UUID();readd.replacesDeletion=d.operationID
    try c.stageWrite(readd)
    var newChild=oldChild;newChild.operationID=UUID();newChild.revision=2;newChild.parentIncarnation=readd.incarnation
    try c.stageWrite(newChild)
    let batch=try c.nextBatch()
    // Emulate exact success retirement only; the ACK method only deletes its own op.
    for w in batch {
        for i in try c.pending() where i.operationID==w.operationID {c.context.delete(i)}
        for s in try c.context.fetch(FetchDescriptor<SentSnapshot>()) where s.operationID==w.operationID {c.context.delete(s)}
    }
    let remaining=try c.pending()
    print("R2-03 acknowledged_current_ops=\(batch.count) pending_count=\(remaining.count) only_old_child_pending=\(remaining.map(\.operationID)==[oldChild.operationID]) next_ready_count=\(try c.nextBatch().count) conflict_count=\(try c.context.fetch(FetchDescriptor<ConflictCandidate>()).count)")
}
// Positive control: repeated preparation stays bounded after the IR-04 patch.
do {
    let c=SyncCoreProbe()
    for _ in 0..<300 {try c.stageWrite(WireRecord(id:UUID(),operationID:UUID(),revision:1,library:c.session.scope.library,kind:"item",name:"batch"))}
    let counts = try (0..<3).map{_ in try c.nextBatch().count}
    print("CONTROL repeated_batch_counts=\(counts)")
}
