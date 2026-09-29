// ThreeWayMerge copied from SyncProtocol.swift @449328ea87b40f773c4dcfa957f3ae00bf43e7ef.
import Foundation
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
