# HHOS-FAV-001 — 执行指令 v1.2

## 1. 任务与权威边界

建立一个轻量、隔离、可恢复的 Foundation 验证工程，回答哪些设计可以进入正式实现、哪些仍需平台证据或修改。只实现证明合同所需的最小代码；**验证目的不是实现完整同步产品，也不是让所有既有设想都得到 PASS。**

完整读取本文件、`VALIDATION_CONTRACT.md`、`ARCHITECTURE_CONTEXT.md`。本文件管执行和权限，Contract 管用例/证据，Context 管业务语义。v1.2 完整替代旧执行包；更高优先级系统/环境约束仍生效。发现真实矛盾先隔离受影响动作，不无视安全约束。

默认使用用户选定的 GPT-6 Astra／中推进，不要求 High 才能开始。不自行改用户模型/推理/计费/权限配置。资料缺失、权限不够、工具报错不归因于“推理档位太低”。只有已形成最小反例、排除环境误用且仍无法解决的一致性/迁移难题，才在集中报告中提出针对性的高推理复核建议；其它工作继续。

## 2. 基线与隔离工作区

```text
Repository: yoCruzer/HouseholdOS
Baseline: f19469fe13be175d1b28d71ddb6b5a917abdcc32
Reviewed production: 5d0c4c347f4069432d94459b1c3c204c748a68b6
Closure docs: dd3fc5940dc7c8bc87faa5e62bdbd89f348d80d3
PR #4: 已合并；不重新 closure
Branch: spike/foundation-validation
Historical workspace hint: /Users/hanghang/Documents/HouseholdOS
Suggested worktree: 相邻的 HouseholdOS-FoundationValidation
```

先在当前已提供项目范围检查 remote、HEAD、工作区、已有 worktree/validation branch/状态文件，再 fetch 指定仓库。旧绝对路径只是提示：在新 Mac、不同用户名或受管环境中使用实际授权项目路径，不扫描整个个人磁盘。找不到已提供仓库才报告路径/访问阻塞。

原工作区曾有两份 String Catalog 修改。保护目前所有既有修改；可记录路径/大小/hash（只保留本机）核验，但不上传私人 diff。原目录不 checkout、不 stash/reset/restore、不 stage 既有文件，不强制抢占分支/目录。优先恢复确属本 Program 的独立 worktree；否则从固定 SHA 创建安全的新 worktree。Git 元数据正常更新不等于改动用户工作文件。

若已存在 v1.0/v1.1 执行成果，先做合同差异对照，保留代码、提交和有效证据，只补 v1.2 受影响部分，不另建重复 harness/PR。未知修改不覆盖；能够隔离时继续其它工作。

main 正常前进时记录 drift，不自动重基线/重写历史；固定 SHA 必须仍是合法可读取基线。出现主线冲突仅阻塞相应 PR 发布，不自动合并 main。不要在 main 开发。

## 3. 治理激活

读取适用的 AGENTS、Operations 当前状态/任务及直接相关 Foundation/测试策略。Owner 发送本包引导即授权启动本 Program，不继承旧 closure 的 merge 权限。

在验证分支归档旧 CURRENT_TASK，激活新 CURRENT_TASK，链接本合同与唯一状态文件。明确本 Program 的窄覆盖：内部 gate 自动推进；隔离候选模型/同步试验已获批准；测试按影响范围，而非每 Stage 全量。默认不修改 AGENTS；只有适用规则确实无法消歧，才追加仅限本 Program 的简短指针，不移除通用安全要求。

## 4. 改动范围与最小工程

允许：`Prototypes/FoundationValidation/**`、`Docs/Validation/HHOS-FAV-001/**`，必要的 Operations 激活、gitignore、专用手动 workflow。正式 `HouseholdOSApp/**`、正式 xcodeproj、Schema、entitlements 和现有测试不改。

一个原生验证工程/应用及必要测试 target；同一条业务链共用真实持久层、同步 codec/reducer、媒体适配。可有 legacy fixture generator target/process 以确保旧 Schema 身份，不能为每个 gate 各建 App。已有合适设施则复用。不引入第三方框架、通用插件平台或通用 RecoveryCoordinator。

只读引用正式源码或有来源指纹的最小副本；不能把新模型注册进正式容器。验证 App 必须有独立 bundle ID、store/media/preferences/engine state 路径，不能覆盖 `com.yocruzer.householdos` 或访问正式 App container。

少量技术按钮、状态、脱敏 JSON 导出即可；提示至少让 Owner 能理解，不进行设计系统/动画/完整多语言工程。选择器权限由系统处理，不模拟授权成功。

每个正式决策只试一个首选实现；首选被证伪时可试 Contract 明列的最小 fallback。不要平行实现三套同步引擎或预建未来二十种实体。重要新产品取舍写入 impact，不自行扩大范围。

## 5. 推进顺序：先真实链路，再加深失败测试

一次只读预检：实际 Mac/SDK/runtime、可用测试端、签名/Development entitlement、容器授权、网络及 GitHub、旧成果。提前登记缺失外部条件，能用的真实 Apple 平台尽早试，不能先花全部资源把 fake server 做完整才发现 adapter 编译不了。

内部顺序：
1. 最小可编译 harness、真实 V1 fixture、一个 Draft/Item/Profile/Media 的本地重开链。
2. 条件具备时尽早跑最小真实 CKSyncEngine create/fetch 和 PhotoKit 访问；否则生成可编译 adapter 与集中设置待办，继续本地逻辑。
3. 在同一链上注入 ACK/账号/删除/媒体/恢复等关键故障，按 Contract 闭环。
4. 一次跨边界演练、收尾测试、一次集中只读审查、证据/发布。

A/B/C 是内部工作类别，不是串行 Owner 审批。可并行独立只读审查/fixture 工作；同一工作树、状态文件、云 namespace 只允许一个协调写入者。不启动无界代理或额外付费服务。

环境受阻的 case 标 BLOCKED_EXTERNAL 并继续其它安全工作。缺 SDK 的非 Mac 环境可以做纯逻辑和材料，但必须说明 Apple-framework build 未验证，不能制造模拟 API 声称已编译成功，也不能以纯文档冒充自动化工作完成。

## 6. 测试频率与可复用证据

日常：改动后 focused tests；跨边界改动才 affected integration。修测试必须保留能抓住原缺陷的断言。不得 skip、吞错、删边界来换绿灯。

本 Program 收尾：在候选版本运行 harness 的完整确定性集合一次，并构建实际交付配置。真实平台用例按需要单列；只有 Release/优化或缓存问题有风险时追加相应 build/clean。正式 App 源码/构建输入未变则不机械重跑正式 App 全量 Unit/UI。既有 45/45 与 CI 33572746681 仅是旧 reviewed code/SDK 的历史证据，不覆盖新 harness、当前 SDK 或真机。

最后出现局部修复时，更新受影响代码及依赖的 evidence fingerprint，重跑 affected 集合；只有广泛影响才再全量。**最终证据必须覆盖最终代码，不能用修复前的 PASS 掩盖新代码未测。** 文档-only 提交不失效运行证据。

本机/CI 选一个主要执行位置，复用同 code/config/fixture/相关工具链证据。不要本机全量后又 CI 全量。先查看现有 opt-in workflow；不更改仓库变量、不取消别人的任务、不绕过 required checks；确需新 workflow 默认手动触发。平台强制检查照做并复用。

开发默认约 20 Items/8 Media；代表规划约 250/50，仅验证容量调度时使用。大规模压力和并发调优不是本 Program 默认任务。小真实样本揭示机制，大逻辑样本验证规划；不要重复搬运 GB 数据。

沿用旧授权的保守网络范围：本 Program 新发起的 live validation 估算上传+下载预算共 100 MiB（包括本次恢复后累计、重复读取和合法重试；原始字节与传输开销分开）。实际系统额外传输无法完全预估时标为估算，不伪造精确流量。接近预算停止新增大对象并记录待办，不重新生成 run ID 重置预算。不填满 iCloud 或真实磁盘制造故障；用注入或受限测试存储。

测试疑似 flaky 不以反复重跑一次绿作结论。每轮需新诊断/反例/修复；重复无信息增益时换诊断路径或局部阻塞，继续其它 gate。一次普通失败不是 Owner gate，也不是自动升级 High 的理由。

## 7. Git 与外部写入授权

授权仅在核验的 `yoCruzer/HouseholdOS`：指定 worktree/branch、stage 本任务文件、commit、普通 push、创建和更新一个 Draft PR（base main）。按有意义 checkpoint 批量 push，不逐函数 push；不再聊天询问这些已授权动作。平台自身审批必须遵守，不能换通道、复制凭据、降沙箱绕过拒绝。

禁止 merge/mark-ready/auto-merge/force-push/重写共享历史/删除远端分支/tag/release、正式发布、TestFlight、Developer Portal 修改、Production CloudKit。PR #4 已结束，不重新操作它。

真实 CloudKit 只使用已经配置并明确允许测试的 Development container 与本 Program 登记的 run zones/合成 records。核验实际签名 entitlement/environment，不凭 Debug 名称推断。record type 稳定使用 HHOSVAL_ 前缀，不每个 run 发明新类型。schema 是 container 级，删除 zone 不清 schema；记录 side effects，不 reset 全开发环境、不部署 Production。

独立验证 App ID、container 关联/签名/推送 capability 缺失集中进入 OWNER_ACTION_PACK；不得让 Automatic Signing 或 `-allowProvisioningUpdates` 在无单独授权时创建资源，不用正式 bundle ID 代替。不扫描钥匙串、不展示账号/真实照片/GPS/本机个人路径/原始云 dump。真实 Photos 仅访问用户在测试中明确选中的素材，不扫全图库、不写/删除真实照片。

允许清理仅本任务创建且登记归属的测试记录/文件；先校验 namespace 和 manifest。无法确认不删。网络失败有限重试，保留提交并继续不依赖远端的工作，不将发布失败等同工程不存在。

## 8. 持久状态与审查材料

只维护少量产物：
```text
VALIDATION_STATE.json   唯一机器状态：gate、证据、依赖、下一动作、预算、发布
VALIDATION_EVIDENCE.md  运行索引与最小关键反例，不复制全部日志
FOUNDATION_IMPACT.md   逐决策结论、可用边界、正式实现映射
OWNER_ACTION_PACK.md   一次集中设置/真机动作，缺失时也存在
```

完整合同保存在验证文档区。无需再手写一份重复大计划。JSON 保存 program/version/baseline/branch、相对 worktree 信息、last good commit、case status/evidence level、tested source/config/SDK/fixture 指纹、外部阻塞、下一安全动作、存活进程/异步操作线索、累计 live budget。私人路径、账号/Photos ID、真实哈希放本机 gitignored 配置，公开证据用不暴露身份的代号。

checkpoint 原子替换；重要 gate/有风险合成试验/外部等待前保存，长期操作自身有 journal。硬中断不保证最后保存，因此定期写。恢复时核验真实进程/Git/服务结果，避免双重运行；从未完成或证据失效部分继续，不重造工程/PR。

大 xcresult/日志/store/图片放持久 gitignored evidence 目录，不把唯一证据留在 /tmp；可再生成 fixture 记录 seed/hash，Git 只放小安全样本和摘要。

FOUNDATION_IMPACT 对每个决策写：可接受/被证伪/待证据，证据等级，所需生产承诺，最小推荐方案；对代码写“可复用/仅试验/应丢弃”，标出未来正式文件边界。不能以行数、测试数、报告页数当成功。

## 9. 停止与交付

安全边界/产品取舍/不兼容主线只阻塞相应动作。常规编译、测试、接口、fixture 修复自治；全部剩余工作依赖外部行动时才整体停。

结束前一次集中只读审查，优先看“不变量被绕过、fake 与真实 adapter 不同、未测最终代码、虚报平台 PASS”。若工具确有独立 reviewer 可用就使用一次；否则明确自审，提供给 ChatGPT 的审查材料，不假装独立审查已完成。不新增每 gate 必审或 High 必审要求。

工程状态与验证结论分开：
- READY_FOR_FOUNDATION_REVIEW：合同核心证据完整，但还未 Freeze。
- IMPLEMENTATION_COMPLETE — LIVE_EVIDENCE_PENDING：适配/逻辑工程完成，相应 live 承诺尚未通过。
- BLOCKED — ENVIRONMENT_ACTION_REQUIRED / DECISION_REQUIRED：明确阻塞边界。
缺 Apple-framework build 或核心用例不能报 IMPLEMENTATION_COMPLETE。

最终中文报告：基线/HEAD/Draft PR、既有工作保留、实际测试与复用、核心发现、外部动作、逐决策 Freeze 建议。设备包按一次集中操作组织，不保证无法自动化的现场一次必然全通过。没有已授权环境时不要索要主 Apple ID 登出。

不自动合并、不修改正式 Foundation 为 FROZEN、不开始 Foundation Rebaseline 或 Wardrobe。所有安全可执行工作完成后统一交付，不逐步要求用户回复“继续”。
