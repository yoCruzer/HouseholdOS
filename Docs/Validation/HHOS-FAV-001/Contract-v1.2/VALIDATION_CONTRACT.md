# HHOS-FAV-001 — Validation Contract v1.2

## 0. 验证方式

沿用一个 Program 的 A（持久化）、B（同步）、C（媒体）工作类别，但只建立一条共享的最小链路：

`测试图片 → durable staging → Draft + typed Profile → 本地提交/outbox → 重启 → 确认 Item → CloudKit → 空白隔离客户端 → 有图可浏览 → 备份/恢复`

正常路径先用真实平台实现，不先造完整 fake 平台。确定性故障使用同一 codec、outbox、reducer 和状态机；fake 只替代服务/时序，不重写另一套“总是正确”的业务逻辑。

以下 G0–G8 是验收问题集合，不对应 9 个 Goal、App、人工审批或全量测试。每个强制断言必须有测试/证据映射；一个参数化用例可以覆盖多项。没写出独立 test class 不代表没覆盖，测试数量也不代表覆盖。

证据标签：LOGIC（注入/fake）、LOCAL_PLATFORM（真实本地框架）、LIVE_SERVICE（真实服务并记录宿主）、LIVE_CROSS_DEVICE（两个实际独立端/图库）。另标设备/OS/SDK。Simulator 两客户端能证明协议/服务行为，不等于双真机 Photos 或光学验证。

每项状态：NOT_STARTED/RUNNING/PASS/FAIL/BLOCKED_EXTERNAL/DEFERRED/NOT_APPLICABLE，附预期、实际、最终代码依赖指纹、fixture、命令/动作、退出结果/计数/hash、证据路径。平台不可用只能待验。DEFERRED 必须指出哪个正式承诺因此不能成立。

## G0 — 隔离、真实 SDK 与最小链路

先确认独立 bundle/store/media/preferences/engine state/云 namespace；正式代码及原工作区不可改。核对当前可用 SDK 与项目最低部署版本，不默认要求最新 beta、不为了新 API 静默提高 iOS 最低版本。缺旧 runtime 时记录兼容性证据缺口，不自动安装大 runtime。

一个独立工程承载全链，必要时有真实旧 Schema generator。只用最小 Draft/Item、Wardrobe 两三个字段、Media、一个代表事实及同步基础记录，不建完整未来模型族。

能接通真实服务时尽早验证一条 create/read/update 与一张真实允许的测试图；不能接通也要验证真实 adapter 在已安装 SDK 下编译。不要把协议 fake 通过当 adapter 可工作。

## G1 — 真实旧库迁移与领域扩展（LOCAL_PLATFORM 强制）

从固定 baseline 的旧模型/容器生成合成磁盘 store；来源、类名、schema checksum/可观察身份和编译输入留证。不得用候选新模型制造“旧 V1”。保留 immutable 原 fixture；只迁移 quiesced 完整 clone（含 WAL/SHM/附属数据，不能只复制活跃 sqlite）。

fixture 包含 Item、Draft、归档、sourceDraftID、位置、系统/自定义/未知分类、封面、多图及删除后状态。当前真实 V1 媒体全部继续 App-owned；不能凭 photoLibrary 来源猜回引用并删除旧原件。

候选 Schema 只引入检验风险所需的 sidecar、少量变更字段、媒体/replica、local outbox。真实迁移、重开、再次调用升级入口、关键中断/失败均验证：身份/字段/关联/原件 hash 保留、无重复、无自动删库。若命名空间重构改变历史 identity，真实解决，不能改旧 fixture 迎合新 schema。

两个客户端确认同一 Draft/重试必须归于一个逻辑 Item；Profile/Media 永久身份不随 draft→item 转移改变。分类切换不删除已录 Profile；同名不等于同对象。两份独立创建的本地库不能因默认 Household UUID 或相同名称被静默视为同库；跨库合并只形成明确计划，不在本阶段实现全库合并 UI。

输出 tested schema shape。它不是最终正式 V2，不冻结未来每个字段/类型。

## G2 — 本地提交、文件 journal、outbox（LOCAL_PLATFORM + LOGIC 强制）

业务写入与 durable outbox 在同一可验证本地事务中提交，不能因为 outbox 是 device-local 就放另一库两次 save。SwiftData 本地 `.none` 可保留有价值的约束，但本地唯一性不等于分布式幂等。

文件与 DB 非同一原子事务：prepared→已提交引用→finalize/clean 用最小 durable journal；覆盖文件失败、DB失败、原件成功preview失败、save成功refresh失败、进程终止、清理失败重开。已经提交的内容保留；唯一可恢复 staging 不当垃圾删；无 phantom Draft、漏 outbox 或假成功。

不可访问数据要区分权限/受保护数据暂不可用、容量、格式/校验损坏；不能因锁屏访问失败就判 corruption 并重建/删库。相关分支先故障注入，不为此操纵用户主设备安全设置。

## G3 — 同步意图、ACK、入站持久化（LOGIC + LOCAL_PLATFORM 强制，真实连接单列）

业务发送意图的权威在 durable outbox。允许使用已安装 SDK 支持的 `hasPendingUntrackedChanges` 或可从 outbox 重建的 engine pending 队列；**不把某一 API 接法当验收答案**。engine state 是调度/checkpoint，不与 outbox 争夺事实真源。

关键反例：revision 7 发送中出现 revision 8；7 的 ACK 只能确认7；不能按 entityID 清掉8。发送快照/operation ID必须持久关联；同 record 的在途版本有明确规则。合并 pending 不能丢“删除”或撤销意图。

server 成功但客户端未收到、部分成功、重复返回、重启、engine state 丢失，均验证幂等。稳定 CKRecord ID 只在固定 scope 中减少物理重复，不代替冲突/显式删除后重新添加的操作语义。同一次 Usage 重试只一次；真正两次使用是两条。

入站 fetched data 必须先持久应用（或 durable inbox），再推进对应已应用 checkpoint。先存 token 再丢数据的崩溃窗必须被抓住；重放不得回声式无限上传。fake 和 live adapter 使用相同映射/校验。真实 event 顺序和 send/fetch 重入按 SDK验证，不在事件处理中制造死锁。

## G4 — OFF/ON、首次抓取、账号与冲突（LOGIC 强制，适用 live 补证）

首次开启覆盖本地有/云空、本地空/云有、两边都有、分页/partial/空 scope/错误。完成必要 metadata fetch/apply 前禁止 bootstrap upload；fetch 失败不等于空库。首次不能悄悄先下载全量 originals。

scope 至少区分 container/environment/account/library/zone 与 engine epoch；system fields、ACK、序列化、投递意图不得跨 scope 误用。A→B→A、同账号重启、OFF→ON及旧 fetch/save/state/error 迟到回调都覆盖。OFF停止新调度且保留对账所需意图，不谎称服务器已收到的操作被撤销。新账号默认暂停绑定，不自动上传旧账号家庭内容；需要显式计划，不通过改本地工作库绕过。

不同字段有可信 ancestor 时三方 merge；金额/币种等耦合字段成组校验；同字段冲突/无 ancestor保留可恢复候选，不靠墙钟挑赢家。并发本地待写不能被入站覆盖。冲突候选不能只存在内存；备份含未解决冲突时要保留其信息或如实报告恢复范围，不报告“无遗漏”。

未知新增字段采用保留不透明内容或兼容写保护；只做一个未来字段/版本 fixture，不建无限兼容框架。无法保真解析的来源不能重写覆盖。

## G5 — 删除、乱序、旧备份和丢 zone（LOGIC 强制）

删除采用最小 tombstone 与受控条件写/冲突规则。覆盖旧客户端离线更新、删除ACK丢失、在途旧保存、child先到/晚到、旧备份重放。父删除不能产幽灵附件；临时 parent 未到不等于可 GC orphan。tombstone 清用户内容；不能让旧记录重新填回。暂不做 tombstone GC 或全设备 watermark 协议。

对真正明确的恢复/重新添加保留新操作身份；不得把所有 re-add 都误判重试，也不得允许 stale upsert复活。保留业务UUID与识别新用户意图是两回事。

userDeletedZone硬暂停；一般zoneNotFound不猜原因自动重建。只有确认新测试namespace可初始化；历史库丢失/疑似加密密钥重置需要明确证据与恢复策略，查当前 SDK信号，信号不足标未知，不臆造错误key。允许注入分类，不让用户登出主Apple ID或重置密钥。只删本任务登记的测试zone，删除操作结果不冒充“系统设置主动删除”的证据。

## G6 — Photos 引用、表示版本与恢复保真（LOCAL_PLATFORM/真实授权Photos强制；跨端单列）

Picker选择和后续PhotoKit权限分别验证：无授权、limited可访问/不可访问、充分授权、撤权、nil identifier。只访问选中的测试资产；不能因拒绝广泛授权就禁止普通选图。无法建立持久访问时保存picker交付的bytes为App-owned fallback，说明实际表示精度，不假称一定是未编辑original，不静默仅留小图。

PHCloudIdentifier只作映射线索，非授权或原图副本；暂未找到/权限不足/多候选/需网络/空间不足有不同状态。不可凭identifierNotFound确认用户永久删图，不自动模糊绑定。跨设备不靠localIdentifier；映射在读写边界批量缓存，不在每帧调用。

**稳定Media ID、外部Photos引用、字节representation/revision是三个概念。** Photos修改/转码或用户替换附件时，旧preview/hash不可被静默解释成新原图。用最小模型记录representation版本/来源精度；旧下载/上传ACK必须核验目标revision，不覆盖当前图片。hash只用于该份字节完整性，不去重现实物品。

Reference不是唯一owner的硬枚举：Photos引用可与App安全副本并存。新增安全副本不默默改变cloud upload policy，也不能因Photos暂时可访问就删除备用bytes。以最小状态验证，不做自动去重/双向照片编辑。

正常支持静态JPEG/HEIC；Live Photo/RAW/编辑版需记录支持范围。未支持资源不伪称全保真备份；不为此写视频/RAW处理器。保留导入原件字节/元信息；派生recovery preview移除无关GPS/EXIF并规范显示方向。

小集合比较至多几个preview候选，不做多轮全矩阵调参。recovery preview具有保护职责，不等于可任意清空的thumbnail；原图暂不可访问时业务档案仍可读。

## G7 — CKAsset、按需原图、配额与策略变化（LOGIC + 适用LIVE强制）

用少量真实texture图片验证文件稳定上传、读取回校验、重启、暂存URL迁入durable位置。不能持久保存CKAsset临时URL；不假设字节级续传。所有队列同意图/版本/账号规则。

必须验证：空白客户端接收metadata/preview时有没有隐式下载originals。拆record不是lazy fetch证明。查真实SDK：如engine不能选择asset字段，允许受控media zone或窄的原生desiredKeys fetch；只试满足需求的最小替代，并证明删除/重启/元信息关联仍一致，不自建通用传输平台。[A4]

本地original、recovery preview、云original各自有状态；ACK/上传字节不等于新设备已经恢复。quota/network/throttle/partial以确定性注入为主，LIVE小样本验证连通；不填满账号。quota后可保守暂停相关队列，不保证小记录仍能成功。重试使用平台调度/退避，无竞争无限timer。

MediaPolicy变化只改变后续意图：数据-only/preview/包含App-owned originals，Photos-backed原件默认不重复上传。**降档/关闭同步不等于删除已上传原件，不能声称立刻释放iCloud空间**；清理为独立用户授权。本Program只验证planner和晚到回调，不开发完整云空间管理UI。CloudKit清掉asset引用也不承诺立即回收服务端空间。[A4]

换机突发用代表fixture做计划：结构/metadata→preview→original；小LIVE补证，不传代表fixture全部大图。仅显示本App待传/已确认估算、真实观测进度；不报精确账户剩余空间或虚假ETA。记录iOS后台/强退边界，不保证后台持续运行。

## G8 — 一致快照Backup、Staging Restore与交接（LOCAL_PLATFORM强制）

用小目录包/manifest演示，不开发正式压缩/导出UI/云盘集成。一个snapshot ID或同等边界覆盖结构与确切media revisions；短暂冻结fixture写入可接受。导出中变更/删除必须得到一致快照或明确重试，不能得到混合时间数据仍报成功。

Smart包含结构、引用、previews及其承诺的全部App-owned原件；Photos原件依赖外部库。Full包含范围内可获得全部original；缺失/只有云原件需取回或标不完整。表示hash/数量/completion marker都有；只复制可用图不能声称Full成功。

partial→验证→安全finalize；原备份不覆盖/删除。外部provider不保证原子rename时不外推成功。取消/写满/缺件/hash错/中断必测。读取包校验路径穿越/越界链接/解压限额/版本，checksum不是来源认证。

Restore先在隔离store/media验证，再原子或journal化切换完整generation；不能先切DB后media仍指旧root。测试切换中断，旧测试库仍可回退。迁移/恢复成功之前不删源。冲突/未同步本地意图不被无声丢弃。

**Restore对系统Photos新增写操作为零**：可重新绑定已有照片；无可靠引用但包内有bytes保留App-owned安全副本，不自动写相册/模糊删副本。cloud admission再次执行scope/tombstone/版本检查，旧备份不自动上传覆盖新库；不复用旧设备ACK/engine/session状态。

记录source snapshot ID与目标端实际校验。没有第二端/原图验证时可以说“云端副本准备/条件性可恢复”，不能说“安全抹除旧机”。本Program输出两端证据或明确待办，不开发完整MigrationWizard。

## P1 — 安全策略与可延期优化（不是省略安全门槛）

本Program必须：保护唯一原件；不向公开证据泄露个人数据；不把明文prototype冻结为生产备份；输出Cloud字段分类/生产备份机密性待决策；验证读取/写入失败不会导致删库。

具备LIVE环境时复用最小云record验证敏感字段encryptedValues round-trip；没有环境保留平台待验。查询/路由ID与内容字段分开，按官方SDK检查兼容与索引限制。不实现自制加密/密钥管理。正式Production前相关安全设计必须另有明确结论。[A7]

**系统Device Backup政策更新**：不可重建且尚无可靠替代恢复途径的App-owned原件不得排除备份；可重建thumbnail/cache可以排除。不要仅凭上传ACK自动切换原件backup eligibility。若产品承诺独立备份，实时同步副本也不能自动替代它。v1.2只验证基本文件标志/分类及保守安全默认；动态排除、云副本失效后自动恢复、空间精确收益属于后续优化。无法证明可持续重下载时保留备份资格并如实披露可能重复占用。系统备份成功与否不能成为本App可验证PASS。[A6]

暂不实现：完整备份加密UI、tombstone GC、全库Photos指纹匹配、通用多旧版本协议、大规模吞吐调参、自动云配额清理。它们进入有明确触发条件的非阻断优化/发布前决策表，不能被忘记或当已通过。

## 集成检查与完整Freeze边界

用同一fixture执行一次跨边界演练：正常本地链→重启→确认→最小服务复制；随后分别注入“旧ACK与新编辑”“父删除与晚到图片”“无持续Photos权限fallback→恢复”“旧备份→已有远端tombstone”。这些覆盖可复用上面测试结果，不能再平铺全部组合。另验证Program checkpoint恢复，不建新测试平台。

Foundation建议按决策，不用一个总绿标覆盖缺证据：
- 本地Schema/事务/备份安全：G1/G2/G8必须真实本地框架证据。
- 协议应用正确性：G3/G4/G5及跨边界反例必须确定性通过。
- CKSyncEngine连通/时序与媒体按需：必须适用LIVE，不用mock替代。
- Photos引用持续访问/跨端恢复：分别有对应证据，未测则依赖fallback及明确限制。
- 真实迁移抹旧机承诺：需要目标端按snapshot及表示精度校验；仅source ACK不足。
- 安全：P1最低要求必须满足；未来生产加密/备份策略不能被实验包默认为已批准。

正式Freeze由Owner后续审查批准。证伪原设想并有安全最小替代也是有效成果；不能为了全PASS偷换需求。

集中Owner Action Pack：按设置→一次设备执行→一份脱敏证据导出组织。PR #4五项deferred真机行为需对应已接受生产构建，prototype同名按钮PASS不替代；可以并入同次操作说明，但不改正式代码、不卸载真实数据。
