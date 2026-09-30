# 独立 Review：REQUEST_CHANGES

## 结论与边界

PR #5 的本轮整改有实质进展；旧的跨生命周期字段合并和 100→300 批次越界反例已被逻辑对照拒绝/约束。明确 representation、冲突解决状态保留、prepared 录入恢复、旧库最小 bootstrap 桥接都有实际代码与回归，不是只改文档。

仍发现三项同步收敛问题（R2-01、R2-02、R2-03）。不需要推翻架构、重新做整套验证或扩展产品功能；应在现有同步 admission/ACK/outbox 边界内集中解决。保持 Draft，不 merge/ready/Freeze，暂不要求 Owner 做设备补证。

固定 HEAD：449328ea87b40f773c4dcfa957f3ae00bf43e7ef。
代码候选 b45cb840c2e65ca25c062cde450c235a0195f670 后到最终 HEAD 的三个提交，远端 compare 显示仅操作/验证交接文档变化。65/65 与原生构建是仓库记录的既有证据，本次未独立重跑。

## R2-01 / P1 — 恢复后的合法 re-add 无法重新获得条件写依据

位置：Sources/ValidationCore/SyncProtocol.swift，apply 的 predecessor tombstone 提前返回（约 373–377 行）；prepareRestoreAdmission；BackupRestore.restore 的 systemFields/ancestor 清理；CloudAdapter 的条件编码/冲突回调。

触发：

1. 已知删除 D 后，用户明确重新添加 R（新 incarnation，replacesDeletion=D.operationID）。
2. R 尚未上传，生成备份并恢复。
3. restore/prepareRestoreAdmission 正确清空旧 systemFields 与 ancestor。
4. 重新准入抓取当前云端 D。
5. apply 发现 D 是 R 的前代，直接 return。R 保留，但云端版本依据仍是 nil。
6. CloudCodec.encode 因没有 systemFields 而创建新 CKRecord；云端同 ID 的 D 已存在。条件写需要当前服务端 change tag。
7. 收到 serverRecordChanged 再 apply D，仍直接 return；重试没有获得新依据。

逻辑探针：readd_preserved=true，system_fields_nil=true，ancestor_nil=true，ready_count=1，条件 tag 不匹配。实际网络失败路径是结合上述源码和 Apple 条件写语义推导，不声称已运行真实 CloudKit。

最小修复：分离“是否覆盖本地业务 payload”和“是否采用已确认当前云记录作为条件写依据”。保留 R 的业务值/意图，同时在明确准入边界重新取得正确的服务端条件基准；不能盲用旧备份 change tag，不能改为无条件覆盖，也不能用旧 D 覆盖更晚已观察到的新状态。

回归：备份恢复后 R+D → 条件写到确定性服务 → ACK → 重开，R 同一意图收敛；还覆盖服务端已经进入另一 incarnation、真正新删除、迟到旧回调。现有 testResolvedConflictRestoreDoesNotBlockReAdd 只验证队列还含 R，未完成条件写闭环。

## R2-02 / P1 — 自己已发送版本的 fetch 被误当另一端冲突

位置：SyncProtocol.apply，约 396–423 行。

触发：本地写 revision 7 → nextBatch 持久化发送快照 → 用户继续写 revision 8（同字段由 seven 改成 eight）→ 服务端已经保存 7，但 ACK 丢失或晚到 → fetch 返回准确的 7。

当前逻辑匹配 operation 后删除 7 的 intent、sent-base、SentSnapshot；但没有先把这个“已确认自己的发送结果”作为 8 的新 ancestor。随后 pendingLocal 仍为 true，按旧 ancestor（或 nil）执行三方合并，同字段被误判冲突。

探针结果（有/无此前 ancestor 两种）：local8_preserved=true，pending=[8]，conflict_count=1，nextBatch=0。

这是没有其他设备改动的连续编辑。内容仍留本地，但正常可自动完成的同步被停在人工冲突处理，不符合本 Program 的目标。迟到 ACK 无法补救：SentSnapshot 已被 fetch 分支删除。

最小修复：用持久发送快照、send-time ancestor、已观察服务端依据验证准确自回声；退休 7 时同步推进适用的 server base，保留 8 待发送。不把所有相同 operationID 都盲目当成功；payload、scope、生命周期及较新远端状态仍须验证。不能通过跳过所有同字段冲突实现“全绿”。

回归：有/无 ancestor 的 7→8→fetch7→ACK8→重启；同一 Draft 确认前后正常发送的版本链；重复 fetch7/迟到 ACK7；以及真正另一端改同字段仍要保留冲突。

## R2-03 / P2 — 旧生命周期子项只是不可发送，未得到最终队列状态

位置：SyncProtocol.nextBatch 的 admitted 过滤；discardDelivery；pending；acknowledge。

触发：父 P 存在，子记录 C1 在本地待发送但从未发送 → 收到父删除 D → 明确 re-add R → 用户明确将该子记录更新到新 parentIncarnation，产生 C2 → R 与 C2 都成功 ACK。

nextBatch 正确拒绝 C1，并允许 R/C2。问题是 C1 仍在 DurableIntent；父删除只清父 delivery，ACK C2 只清 C2。最终 pending=1、nextBatch=0、conflict=0。旧 C1 从未发送，不会凭空等来可退休它的迟到 ACK；重启只会继续同样状态。

逻辑探针结果：acknowledged_current_ops=2，pending_count=1，only_old_child_pending=true，next_ready_count=0，conflict_count=0。

不能把它说成数据已丢失；这是队列/状态不收敛：当前 live report 使用 pending() 数量，永久保留一项无法发送、也没有明确解决入口的待同步事项。

最小修复：给已被新明确意图替代的旧 operation 一个明确终态（superseded/retired 或有原因的 quarantine）。历史内容需要保存时放在可审计历史中，不再作为活动 pending。真正 parent 未到、暂时冲突的记录不能一并清掉。不要直接清空所有 outbox，更不要把“nextBatch 为空”误当“全部同步完成”。

回归：继续现有 testActualOldChildSnapshotCannotCrossReAddAndNewIntentAdvances，在 ACK R/C2 后检查剩余活动工作；分别覆盖旧 C1 从未发送和已在途；重复 ACK/重启保持终态；另保留 unknown-parent 等待而非终止的控制用例。

## 原七项整改的审查状态

- IR-01：直接跨代字段合并已拒绝，实际发送也检查 parentIncarnation；旧子项终态仍见 R2-03。
- IR-02：旧 D 重放不再直接撤销 R；恢复后的条件写依据仍见 R2-01。
- IR-03：传输和备份使用 wire representationID，未发现需要撤回这次修复的阻塞项。
- IR-04：容量在追加前受限，在途切片和实际批次缩减已有回归；逻辑对照为 [100,100,100]。
- IR-05：解决状态用独立 checkpoint 保留，scope rebind 迁移旧前缀；这项修复本身可保留。
- E-01：prepared journal 持久身份、幂等建档、独立条目恢复和原件校验已有实现；不重新要求更大的恢复 UI。
- E-02：真实 V1 JPEG fixture → clone → 明确 receipt/outbox → 空白端已搭桥；接受其最小范围，不外推全量生产历史同步。

这些“可保留”是源码及对应断言的审查结论，不是本次重新执行 65 项原生测试的声明。

## 实际执行与未执行

实际执行：Linux Swift（具体版本见 toolchain.txt）上的提取逻辑探针，输出见 probe-results.txt。apply/nextBatch/ThreeWayMerge 函数体照抄当前源码；内存持久化及 CKRecord 用显式替身。R2-03 仅模拟精确 ACK 退休效果。探针不会证明真正 SQLite 事务、SwiftData 重开、CloudKit change tags、网络时序、设备照片权限。

NativeFollowupTests.swift 是原生回归草案，未编译/运行；R2-01 的本地断言只检查恢复 server envelope，实际条件 tag 应由忠实的确定性服务检查，并保留后续 LIVE 补证。

## 建议本轮收尾方式

同一分支/PR 聚焦三个收敛反例，不重启 Program，不新增正式模型/后台平台。先加入真正失败回归，再修共享逻辑和真实 adapter 调用关系；日常只跑受影响的 Sync/Admission/IRClosure 回归；最终一个协调后的验证工程完整确定性 gate 与必要构建。旧模型/fixture/迁移输入不变时复用旧迁移证据，不重复正式 App 全量 UI。

更新 IR_CLOSURE/VALIDATION_STATE 的受影响断言，不把原 65/65 删除或重写；新结果单独记录。LIVE_SERVICE/Photos/设备待验仍然单列。

## 源码与平台依据

所有源码固定到：
https://github.com/yoCruzer/HouseholdOS/tree/449328ea87b40f773c4dcfa957f3ae00bf43e7ef/Prototypes/FoundationValidation

- Sources/ValidationCore/SyncProtocol.swift
- Sources/ValidationCore/CloudAdapter.swift
- Sources/ValidationCore/BackupRestore.swift
- Sources/ValidationCore/LocalChain.swift
- Sources/ValidationCore/LegacyFixture.swift
- Sources/ValidationCore/MediaTransfers.swift
- Tests/ValidationCoreTests/IRClosureTests.swift

Apple 官方：
https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/savepolicy
https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged
https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/event/sentrecordzonechanges

官方条件写比较 change tag；成功发送后需保存 system fields 供下一次发送；serverRecordChanged 需先解决版本依据并重新调度，不能靠 recordID 相同替代。
