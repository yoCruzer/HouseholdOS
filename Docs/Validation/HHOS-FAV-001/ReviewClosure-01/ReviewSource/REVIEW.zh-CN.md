# HouseholdOS PR #5 — 独立深度 Review

- 审查日期：2026-09-28
- 审查对象：`yoCruzer/HouseholdOS` PR #5，`spike/foundation-validation`
- HEAD：`faae13d93a83694a77da3d962423de2193f0fe88`
- BASE：`f19469fe13be175d1b28d71ddb6b5a917abdcc32`
- 结论：**REQUEST_CHANGES；保持 Draft，不建议 merge / Foundation Freeze。**
- 本报告是只读审查产物，不是新的执行授权，不改变现有 Program 的 Git、数据与平台安全边界。

## 1. 结论边界

不是因为真实 CloudKit/Photos/设备证据尚未取得才要求修改。那些证据可以按合同单列待验。
本次发现 5 个现有代码中的正确性问题，其中 IR-01、IR-02 是不同反例，不能只修其中一个；另有 2 条证据链需要补充或收紧结论。修复主要集中在已有 reducer、选择逻辑和恢复映射，不需要新建同步框架、换技术栈或重启整个 Program。

PR 信息与文件清单经过实时读取，审查结束时 HEAD 未变化。正式 HouseholdOS 的代码和 Xcode 工程不在变更清单中；此 PR 主要增加独立验证工程及交接文档。

### 本次实际做了什么

读取固定 HEAD 的同步核心、CloudKit adapter、本地录入/journal、媒体传输、Photos adapter、候选 schema/旧库迁移、备份/恢复、验证 App/CLI，以及对应的主要测试和 v1.2 验证合同、状态及 Owner Action Pack。
没有运行该项目的 SwiftData/Xcode/Simulator 测试：当前环境是 Linux，不能把对方报告的 51/51 说成本次独立复跑结果。

在当前 Swift 环境执行了：
1. 从实际源码复制的纯 Swift `WireRecord`/`ThreeWayMerge`，验证跨 incarnation 合并问题。
2. 用数组替代持久化，执行与 `nextBatch` 相同的选择循环，验证重复取批次超限。
3. 执行当前 `.max(revision)` 表达式，验证相同 revision 两份表示可能选中非当前表示。

后两项是算法级探针，不是执行真实 SwiftData 方法；本包保留源码和原始结果。其余发现来自可追踪的静态路径，仍需 Codex 在原生测试环境加入失败回归。

## 2. IR-01 [P1] 跨“删除后重新添加”的 incarnation 仍会进入普通字段合并

**位置**：`Sources/ValidationCore/SyncProtocol.swift`，`SyncCore.apply`、`ThreeWayMerge.merge`（约第 499–519 行）。

`ThreeWayMerge` 检查 ID、kind、parentID、format 和 deleted，却不核验 ancestor/local/remote 的 `incarnation`、`parentIncarnation`。它从 `var result = local` 开始，只合并名称、分类、金额、profile、media，因此结果会保留旧 incarnation，并丢掉远端重新添加的 `replacesDeletion` 语义。

**最小反例**：A、B 原来持有 X/generation-A；B 离线改分类；A 删除 X 后明确重新添加为 X/generation-B；B 下次只看见新 generation 的现状（不能要求必须先收到中间 tombstone）。当前代码把不同 generation 的内容自动拼起来，最后生成 generation-A 的新待发送记录。

纯 Swift 探针实测：
`MERGE_CROSS_INCARNATION accepted=true oldIncarnationRetained=true remoteReAddTokenPreserved=false`

**影响**：新持有记录被混入旧生命周期；旧附件可重新满足旧 parentIncarnation，而新附件可能不匹配。不是普通“不同字段修改可自动合并”的场景。

**修复要求**：先做 incarnation/父归属准入，再做同 incarnation 内的字段 merge。遇到新 generation，保留可恢复的旧本地修改，采用明确的接受/冲突策略；不要返回混合代际的记录。旧 profile 也要按相同原则处理，不能仅靠 owner UUID 自动归到新的生命周期。

**回归**：两个客户端，B 缺失中间删除事件；不同字段修改；父/子 incarnation 不同；确认旧子项不会因 merge 回到可见/可发送状态。

## 3. IR-02 [P1] 重放已经知道的旧 tombstone 会撤回明确重新添加的本地意图

**位置**：同文件 `SyncCore.apply`，`remote.deleted` 分支位于“remote 与 known ancestor 相同”的分支之前。

**最小反例**：
1. 本地已经应用云端 tombstone D，ancestor=D。
2. 用户明确重新添加 X，产生新 incarnation、operation R，`replacesDeletion=D.operationID`。
3. R 尚未发送，重新抓取返回的仍是同一个 D。

当前路径会进入 `remote.deleted`：保留 conflict 后调用 `discardDelivery`，删掉 R 的 outbox/在途快照，再把 payload 改回 D。新 Item 消失，重新添加不再待发送。

这不等于字节被彻底销毁（conflict 中仍保留候选），但确实把已经明确作出的新操作错误撤回了。

**修复要求**：识别“已知前代 tombstone”与“真正更新的删除”。同一已知 D 的重放不能取消指向 D 的合法新 R；不可简单对所有 tombstone 无条件获胜。与 IR-01 一起审查，但两个独立反例都必须通过。

**回归**：D → 本地合法 R → 重放 D → 重启 → 再次重放 D；R 仍可见且仍待发送。另保留真正较新删除应该生效的测试，避免反向放过 stale upsert。

## 4. IR-03 [P1] 当前媒体表示由最大 revision 猜出，会与实际 wire/界面引用不一致

**位置**：`MediaTransfers.swift/current`、`SyncProtocol.swift/projectVisibleRecord`、`BackupRestore.swift/export`。

入站投影采用 wire 中明确的 `representationID` 更新 MediaAsset 的图片路径，但 `MediaTransfers.current` 又按所有历史表示的最大 revision 选当前值。备份挑选 current 也采用相同 max 逻辑。

**最小反例**：两个端都从 revision 1 替换图片，产生不同 representation ID 的 A2/B2。收到并采用 B2 后，旧 A2 仍应保留为历史；`.max { revision < revision }` 在相等 revision 时不能表达“B2 是当前选定表示”。改变记录枚举顺序就可能选择 A2。

探针实测：
`REPRESENTATION_SELECTION wirePointsTo=current-wire-B selected=old-local-A`

**影响**：界面/MediaAsset 指 B2，但上传、download ticket、ACK 判定却依据 A2；可能校验了旧图却把操作当成当前图成功。备份目前保留历史原件，不能说它必然丢 B2；问题是“当前版本”的解释不一致。

**修复要求**：用明确的 current representation 引用（或实际 wire.media.representationID）作为唯一选择依据；revision/hash 负责验证，不负责推断当前选择。历史保留不等于当前生效；缺少对应表示时应明确 unavailable，不退回猜测。

**回归**：同 revision 不同 ID、不同枚举/到达顺序、重开、远端选中表示、迟到 upload ACK/download、备份当前表示核对。

## 5. IR-04 [P1] 重复取批次绕过 100 条限制，且超限失败缺少前进策略

**位置**：`SyncProtocol.swift/nextBatch`（约 260–281 行）；`CloudAdapter.swift/send`、delegate batch provider、`classify`；`LiveValidation.swift/metadataRoundTrip`。

代码先把全部 SentSnapshot 加到 records，然后继续追加 pending，追加后才判断 `records.count == 100`。已有 100 条在途时追加第 101 条，之后永远不会等于 100。

算法级探针结果：
`BATCH_SELECTION repeated_without_ACK=[100,300,300] configuredLimit=100`

真实调用结构本身就会在 ACK 前多次取批次：LiveValidation 预取、CloudAdapter.send 取一次、delegate 再取。不能用“正常不会连续调用”规避。

**影响**：第一次正常的小批次准备即可在下一层膨胀；大量本地记录首次启用同步时容易超服务限制。`classify` 的 default 只写 lastFailure，`limitExceeded` 没有缩批或持久阻止原样再次发送。

**修复要求**：先计算剩余容量，再选择/登记在途内容；已有 inflight 也必须受限。处理项目上限及实际 SDK 的请求限制；对超限应缩批/明确阻塞，不能无限重送不变批次。不要以移除上限或增加测试上限来修复。

**回归**：99/100/101/300 条，连续准备无 ACK、100 条在途后重启、部分 ACK、limitExceeded 注入。不需要上传几百张真实图。

Apple 文档：CKSyncEngine 会持续请求 batch，直到 delegate 返回 nil 或取消；超服务限制要拆请求，而不是依赖其自动拆分 recordsToSave 数组。

## 6. IR-05 [P2] 备份恢复会把已解决历史冲突重新激活

**位置**：`SyncProtocol.swift/stageWrite`、`prepareRestoreAdmission`；`BackupRestore.swift/restore`。

重新添加时，旧冲突通过 `conflict.scope = "resolved/" + scope` 标记为历史，从当前阻塞集合排除。恢复时却对所有 ConflictCandidate 无差别执行 `conflict.scope = scope.key`，丢掉 resolved 状态；恢复准入再把它们改到新绑定 scope。

**影响**：恢复后旧问题重新成为 active conflict，`nextBatch` 将对应实体继续阻塞。现有“冲突数量被保留”测试不会检测冲突是否从 resolved 变回 unresolved。

**修复要求**：解决状态与账号/library scope 不混用；至少完整保留 active/resolved 语义，跨 scope 重绑定只改变 scope。不得靠删除所有冲突来使队列恢复。

**回归**：同时有一个未解决冲突与一个通过真实 re-add 路径解决的历史冲突；备份→恢复→准入→重开后，只阻塞未解决项，双方候选数据均保留。

## 7. 两条证据边界需要补充（不冒充已经发现物理数据丢失）

### E-01 原件已写入、preview 失败：证明了留存，未证明可用恢复闭环

`LocalChain.capture` 在 preview 失败时尚未写入 Draft/outbox；`recover` 只 finalize 已被 MediaAsset 引用的 journal，未提交的 journal 被保留但没有继续建档的分支。CLI `recover-capture` 也只调用同一个 recover。测试明确断言这时 Draft=0/outbox=0，再检查 staging 原件还在。

这符合“不要删除唯一 staging 字节”的一部分要求，但不是“用户已经能找回并继续整理这次录入”。不能把 G2 PASS 外推为 prepared 阶段恢复闭环。

建议补最小的“降级 Draft 或显式 prepared 恢复”路径及幂等测试；若本阶段仅验证留存，必须在证据与 Foundation Impact 中明确缺少该行为，不能宣告全部恢复实现完成。不要为了它新增通用恢复框架。

### E-02 旧 V1 库迁移成功与首次同步之间没有连起来

`LegacyFixture.migrateClone` 验证旧实体/媒体不变；但不建立旧对象的 SyncedDocument/DurableIntent。`bindInitial` 只重绑定已经存在的同步行，`nextBatch` 只消费 outbox，没有首次扫描旧 Item/Draft 的引导步骤。

所以“历史库迁移 PASS”与“新 capture 的 outbox 首次同步 PASS”不能直接拼成“使用多年后首次开 iCloud 的历史库会同步”。这不是要求本 PR 实现正式全字段同步，而是需要一条最小旧记录迁移→首次同步 fixture 来证明接口，或者明确记为实现/验收缺口。

原系统固定 householdID 与 LocalChain 新 libraryID 的归属映射，也应在这个最小衔接用例中明确，不得静默忽略。

### 不额外扩范围的一项说明

dataOnly 当前是 planner 证据，不是实际线上零图片 payload 的证明：WireMedia.preview 非 optional，CloudCodec 会编码它，MediaTransfers.policy 不控制 metadata 编码。v1.2 合同明确允许本阶段只验证 planner 和晚到回调，FOUNDATION_IMPACT 也作了限定。因此本审查不把完整 dataOnly UI/发送策略列为新阻塞开发任务；但不能在 Freeze 或后续发布说明中把该证据升级为真实零图同步。

## 8. 已有值得保留的工作

- 独立 prototype/bundle/数据目录；不修改 shipping App。
- 同库业务/outbox 提交，错误 rollback；不把 Cloud 失败当本地保存失败。
- 精确 operation ACK 与持久 SentSnapshot；基本的 revision 7→8 防吞更新测试。
- 入站 apply 失败阻止 checkpoint 推进；不会因错误自动删正式库。
- Picker 选择与 PhotoKit 持续权限分开；保留交付字节并注明表示精度，不写系统相册。
- SQLite backup API 捕获 WAL 内容；完整 generation 切换；恢复保留源数据；备份标志与 hash 校验。
- live evidence 明确 pending，没有把 mock 测试宣称为跨设备平台通过。

这些无需推翻。局部 @Attribute(.unique) 在 .none 本地 store 并非本次错误，不能套用 managed CloudKit 限制机械去掉。

## 9. 建议的一次集中修复/复核

保持当前 Program、分支和 Draft PR，不重开一轮架构设计、不动正式 App。

先为 IR-01..IR-05 加能失败的定向回归，再修对应共享核心，必要时补 E-01/E-02 的最小衔接用例或精确收紧断言。不要把解决方法写成让 Owner 去手工验证本地 reducer。

日常只跑 Sync/Admission/Media/Backup 等 affected tests；修复候选收尾时协调一次验证工程整套确定性测试和受影响的原生 build，不循环跑正式 App 全量 UI，也不重复跑无关且输入未变化的迁移证据。

更新 VALIDATION_STATE/FOUNDATION_IMPACT：当前不能保持 remaining_implementation=[] 并写成只剩 Owner 平台准备。将受影响 G3/G4/G5/G7/G8 子断言降为 FAIL/需修复，未受影响证据保留；修复后绑定新代码/fixture 指纹。

本次报告不授权 merge、mark-ready、Foundation Freeze、Production CloudKit 或真实数据迁移。

## 10. 源码与官方参考

所有源码定位均为上述固定 HEAD。关键相对路径：
- Prototypes/FoundationValidation/Sources/ValidationCore/{SyncProtocol,CloudAdapter,LocalChain,MediaTransfers,BackupRestore,LegacyFixture}.swift
- Prototypes/FoundationValidation/Tests/ValidationCoreTests/{AdmissionTests,ProtocolBoundaryTests,SyncProtocolTests,MediaTransferTests,BackupRestoreTests,LocalChainTests,SharedChainTests,ReviewRegressionTests}.swift
- Docs/Validation/HHOS-FAV-001/{VALIDATION_STATE.json,FOUNDATION_IMPACT.md,OWNER_ACTION_PACK.md}
- Docs/Validation/HHOS-FAV-001/Contract-v1.2/VALIDATION_CONTRACT.md

固定提交：https://github.com/yoCruzer/HouseholdOS/tree/faae13d93a83694a77da3d962423de2193f0fe88
Apple CKSyncEngine：https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5
Apple limitExceeded：https://developer.apple.com/documentation/cloudkit/ckerror/limitexceeded

本报告没有向 GitHub 写入 review/comment，没有变更远端代码或 PR 状态。
