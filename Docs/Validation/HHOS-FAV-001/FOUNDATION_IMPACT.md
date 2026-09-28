# Foundation Impact — HHOS-FAV-001 v1.2

状态：候选结论，最终独立审查、最终候选测试与证据指纹尚未完成。不是 Foundation Freeze，也不授权正式实现。基线 `f19469fe13be175d1b28d71ddb6b5a917abdcc32`。

## 逐决策建议

“本地可接受”仅指表内实验形状和边界；不得外推为整个未来产品已验证。具体运行索引见 VALIDATION_EVIDENCE，最终状态以 VALIDATION_STATE 为准。

| 决策 | 当前判断及证据 | 正式实现必须承担的承诺 | 最小推荐方案 |
| --- | --- | --- | --- |
| 真实 V1 → sidecar 候选 Schema | 本地可接受，待最终复核。真实基线模型生成磁盘库，独立进程迁移完整 clone、重开；旧类来源指纹及实体 version hashes 有本机证据（G1） | 保护完整 quiesced 源库及媒体；迁移成功前不得删源；新增正式字段重新验证具体 Schema | 保留现有实体身份，按已批准功能增加明确 typed sidecar。实验 V2 不是最终 V2 |
| Local SwiftData + 同库 outbox | 本地可接受，待最终复核。业务记录与 intent 同一次 save，真实只读 store 失败无 phantom；故障和进程中断测试覆盖（G2） | 业务修改、投影、intent 必须在一个事务；失败 rollback；UI 区分未保存与已保存但整理/刷新失败 | 保留 `.none` 本地 store；不机械去除本地唯一约束，不把约束当分布式幂等 |
| 文件 journal | 本地可接受。三个 SIGKILL 边界恢复原件与引用，唯一 staging 保留（G2） | 文件与 DB 不具备共同原子提交；区分 prepared/committed/finalized；不可删唯一可恢复字节 | 小型 durable journal，已提交后恢复整理；不引入通用恢复框架 |
| stable ID / 同一 Draft 确认 | 本地与确定性协议可接受。两个 replica 的同一 Draft 归于同一 Item；Profile/Media ID 不变；不同库随机持久身份（G1/G3） | 稳定业务身份、重试 operation identity、明确 re-add incarnation 分开；不能同名自动合并 | 同一 Draft 派生确定性 Item 身份；独立本地库不复用 seed Household 身份 |
| durable outbox + 精确 ACK | 确定性可接受，待最终复核。7→8、重复/丢 ACK、重启、迟到 ACK 与已抓取冲突测试（G3） | ACK 仅退休对应 operation；不能覆盖更新的 server 依据；sent snapshot 持久；engine state 可重建 | 同记录一个明确在途版本；业务 outbox 唯一发送事实来源 |
| bootstrap / scope / OFF | 确定性可接受；真实账号事件顺序待证。分页完成前禁止上传；OFF、A→B→A 与恢复准入覆盖（G4） | container/environment/account/library/zone/epoch 全边界；账号变化暂停；空 fetch 与失败区分 | 首次先抓 metadata；旧 scope 回调无效；不自动搬家庭内容到新账号 |
| 三方合并与未知字段 | 确定性可接受。可信 ancestor 的独立字段合并；金额/币种耦合；同字段和无 ancestor 候选持久；顶层及嵌套未来字段原文保留/写保护（G4） | 不能按墙钟选胜者；不能在 Codable 丢字段后重写；冲突候选纳入恢复 | 有限 typed merge；未知内容写保护；人工解决能力在正式功能阶段实现 |
| tombstone / re-add / child 顺序 | 确定性可接受。父删除、旧保存、child 先到/晚到、旧备份、re-add incarnation（G5） | 删除清内容；离线旧写不复活；未知 parent 不能自动 GC；新明确添加有新意图 | 内容清空的 tombstone；稳定业务 ID + 新 incarnation；暂不做 GC |
| CKSyncEngine | 待 LIVE_SERVICE。原生 delegate 与共享 codec/reducer 已在 Apple SDK 编译；未连接已授权签名容器 | 真正 event/checkpoint 时序、重入、部分成功与账号事件需实际证据；system fields 仅同 scope 使用 | 保留当前原生 engine 候选，不另造同步引擎；先执行 Owner 包 |
| original 按需取回 | 设计待 LIVE_SERVICE。逻辑旧版本 ACK/download 拒绝；实际 CKAsset API 编译，未发生云流量（G7） | 证明 metadata/preview 抓取没有隐式原件下载；CKAsset 临时 URL 不可持久化；目标端回校验 | metadata zone + 受控 media zone；原件仅显式 desiredKeys fetch。拆 record 本身不是证明 |
| Photos reference | 持续访问与跨设备待证。权限 reducer、真实 PhotoKit adapter 编译；picker fallback 本地恢复通过（G6） | PHCloudIdentifier 不是授权/副本；只访问选中引用；撤权、缺失、歧义、网络与空间分类；不模糊绑定 | 当前候选保守保留 picker 交付字节和精度，引用与安全副本共存；未证明可省略安全副本或节省重复空间 |
| 媒体表示与精度 | 本地可接受，待最终复核。JPEG/HEIC 实际编码/导入保留字节；preview 方向/元数据；不可变表示与迟到回调（G6/G7） | Media ID、Photos ref、representation/revision 分开；更换字节产生新表示；hash 不等于现实对象 ID | 明确当前静态表示；Live Photo/RAW/完整编辑资源集合不承诺 Full 保真 |
| Smart/Full 快照 | 本地目录范围可接受，待最终复核。SQLite backup API、一致边界、completion marker/hash/数量；缺件拒绝；历史表示保留（G8） | 单写者短暂停写；所有承诺的原件必须可得；取消/失败不能发布完整标志；不可覆盖旧包 | 小目录包及 manifest；外部 provider rename/正式压缩不由此证明 |
| staging restore / 云准入 | 本地可接受，跨设备抹旧机承诺待证。完整 generation 指针切换、旧库可回退、冲突/意图保留；旧 session/ACK 清除；先对账远端 tombstone（G8） | DB/media 同 generation；恢复零 Photos 写入；保留源；目标 snapshot/精度验证后才能谈迁移完成 | 独立 staging + 原子本地 ACTIVE 指针；恢复后关闭同步并重新准入 |
| 系统 Device Backup | 保守默认可接受。实际文件标志验证：原件和 recovery preview 不排除，可重建 cache 可排除（P1） | 不能凭 Cloud ACK 排除唯一原件；不声称验证系统备份成功；披露可能重复占空间 | 暂不实现动态排除；独立备份承诺不能由实时同步副本替代 |
| 生产保密性 | 尚未批准。原生 `encryptedValues` 编译；真实 round-trip 待验；实验目录包明文（P1） | 内容/路由字段分类、生产备份机密性、恢复密钥策略必须单独决策 | 不自制加密/密钥管理；prototype 不能成为生产备份格式的安全批准 |

## Cloud 字段分类与发布前决策

- `HHOSVAL_Entity`：record/zone/library/operation/revision 是路由与条件写元信息；不放照片名称、价格、位置或成员内容。typed payload 放 `encryptedValues`，包括 Profile、媒体描述、Photos 引用和 recovery preview。真实 round-trip 尚未验证。不能假设 encrypted 字段可用作查询/索引。
- `HHOSVAL_Original`：不可变 representation ID、media ID、revision、该份字节 hash 是完整性/关联元信息；`CKAsset` 承载测试原件。文件可能有 GPS/EXIF，实际云端资产保密性和字段策略须另行审查；不能把 encrypted payload 推广为所有资源已有相同保护。
- UUID/hash 也可能构成关联信息。公开证据只导出计数、固定状态、合成 fixture 指纹与构建指纹；真实账号、Photos ID、GPS、原始云 dump、个人路径和真实照片 hash 留在私有配置/本机。
- 官方文档及本机 SDK 已确认：encryptedValues 不能将既有普通字段改为加密字段，不能用于 public database，也不参与 CKQuery predicate/sort。`zoneNotFound` 可携带真实 `CKErrorUserDidResetEncryptedDataKey`；已注入验证该信号的持久暂停。无该信号时原因仍未知。实际平台密钥恢复、生产兼容与索引方案继续待验。来源见 VALIDATION_EVIDENCE 的官方 SDK 审计。

## 正式实现地图（后续单独授权）

| 实验代码 | 处理方式 | 正式边界建议 |
| --- | --- | --- |
| `Legacy/*`, `LegacyFixture`, CLI, process_checks | 仅 fixture；保留迁移回归输入和来源，不接入运行路径 | Data/Persistence/Migrations 的历史模型与迁移测试 |
| `CandidateSchema` | 仅试验；正式字段/版本重新设计验收，不能注册进 shipping container | Data/Persistence/Schema；Domain 的 typed Profile |
| `LocalChain` | 可提炼事务/journal/结果边界；合成名称、按钮和 fixture 业务流程应丢弃 | Application/Capture、Domain/DraftConfirmation、Data/MediaJournal |
| `SyncProtocol` 的 codec/outbox/scope/merge | 可提炼已验证不变量；最小 DTO/投影不是现有全量业务模型的同步覆盖 | Data/Sync/Outbox、CloudCodec、InboundApply；Application/SyncAdmission |
| `CloudAdapter`, `LiveValidation` | adapter 为待 LIVE 的候选；配置导入、50MiB 端配额和技术按钮仅试验 | Data/Sync/CKSyncEngineAdapter；正式设置流程另行授权 |
| `MediaTransfers`, `PhotosAdapter`, `MediaFiles` | 可提炼 revision guard、保守策略、字节保护；合成生成器丢弃；Photos 访问待真机证据 | Data/Media、Data/Photos、Application/MediaTransfer；不得写 Photos 或偷偷升级上传策略 |
| `BackupRestore` | 可提炼快照 manifest/校验/generation 切换不变量；目录实验不是产品导出 UI/加密格式 | Application/BackupSnapshot、Application/RestoreAdmission、Data/BackupPackage |
| Tests / LocalEvidence / redacted evidence | 保留可复现回归与最终依赖指纹；不把 raw 本机证据打包发布 | 对应正式模块的 Domain/Application/Repository 回归 |
| 验证 App、私有签名配置工具 | 仅试验；应留在 Prototypes | 不接入正式 navigation、entitlements、资源或 App container |

## 延期及触发条件

- tombstone GC / 全设备 watermark：只有删除记录体积成为已测瓶颈且离线恢复协议明确后再设计；当前不回收。
- 动态 Device Backup 排除：仅在可持续重下载及独立备份产品承诺明确后；单次 ACK 不触发。
- 完整生产备份加密/密钥恢复：真实用户备份发布前必须决策，当前明文包禁止当生产承诺。
- 全库 Photos 指纹匹配：用户明确请求重绑定功能后再讨论；当前不扫描、不模糊匹配。
- 通用多版本协议：出现实际支持的第二个生产协议版本后再扩展；当前只做有限未来 fixture 写保护。
- 大规模吞吐/后台长传：真实容量测量显示需求后；250/50 仅调度计划，不是大对象传输或后台保证。
- 云空间清理：需独立用户删除授权；降档/OFF 不删云，不承诺即时释放服务端空间。

## 明确尚不能承诺

不能宣布 CKSyncEngine 可用于生产、Photos 跨端引用可靠、后台持续上传、完整 Live Photo/RAW 备份、生产包机密性、系统备份成功、可安全抹除旧机。最终独立审查与候选运行结束前，也不能宣布全部本地核心合同通过。

最小 wire DTO 只证明本次 typed Profile/身份/金额 unknown 与确定值/代表事实意图的协议边界，不能直接承担生产全模型同步；其 fixture 投影日期不得作为正式日期映射复用。G7 三档策略目前验证 planner 和原件调度意图，不承诺完整设置 UI 或实时重写所有既有 metadata。
