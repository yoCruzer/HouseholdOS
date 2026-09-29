# HHOS-FAV-001 / PR5-IR-Closure-01 — 集中整改指令

## 1. 目标与授权生效

Owner 已决定：先集中解决 PR #5 独立 Review 指出的可自动处理问题，再安排真实平台补证。
发送本包及短引导即授权恢复这个既有 Program，处理 IR-01～IR-05 以及 E-01/E-02；不需要重复审批开始、内部批次、常规测试、commit 或普通 push。

本文件处理执行与权限，`REMEDIATION_CONTRACT.md` 处理行为验收。仓库内 `Contract-v1.2` 仍为基础合同；这份补充只覆盖本轮有限整改、测试节奏和交付状态。环境/系统安全限制保持有效。前次 Closure 的 merge 授权已结束，不继承。

本轮是“复现 → 最小修复 → 定向回归 → 关联复核 → 最终收尾”的一个闭环。不要重造 harness、平行实现同步引擎、重开大架构设计或逐项向 Owner 提问。

## 2. 固定审查对象与工作区恢复

```text
Repository: yoCruzer/HouseholdOS
Accepted baseline: f19469fe13be175d1b28d71ddb6b5a917abdcc32
Reviewed PR head: faae13d93a83694a77da3d962423de2193f0fe88
Branch: spike/foundation-validation
PR: #5; base main; remain Draft
Historical original workspace: /Users/hanghang/Documents/HouseholdOS
```

先读实际适用 AGENTS、CURRENT_TASK、CURRENT_STATE、验证状态、v1.2 Goal/Contract/Context，以及本轮涉及的代码和测试。
记录 remote、branch、HEAD、worktree 列表和 `git status --short`。核验 PR #5 的当前 head/base/draft/merge 状态；远端正常 fetch 已授权。

优先使用已存在的本 Program 独立 worktree。保护原工作区现在的全部既有修改，尤其历史两份 String Catalog；不在原目录 checkout/stash/reset/restore，不 stage 其它人的文件，不扫个人磁盘。不得强行抢占另一 worktree 正在使用的分支。

若 head 已在 reviewed head 后前进：先审新增 diff，复用本轮已经完成的修复和证据；不要 reset 回旧 head。无关修改可隔离则继续，其安全归属无法确认时仅阻塞相应动作。若 PR 已合并、换了非预期基线或出现另一活动写入者，不自动新建 PR/分支或改 main；保存情况，停止冲突动作。

`f19469f…` 是已接受产品基线，不是要求你丢弃验证成果回去重做；正常整改从已有 PR head 继续。

## 3. 激活任务，不让旧“等待 Owner Review”阻塞已获批整改

在验证分支对 CURRENT_TASK 做最小更新，链接本次补充合同与原 v1.2。保持唯一 `VALIDATION_STATE.json`，增加本轮 IR/E 子项及下一安全动作。

把受本次反例推翻的具体断言置为 NEEDS_REMEDIATION/FAIL（使用现有机器状态允许的等效状态）；保留以前 51/51、构建及迁移作为历史证据，不删除失败记录，也不把全部既有 gate 无区别作废。

`remaining_implementation` 不能继续为空，直到本轮真实闭环。旧“只剩 Owner 环境”描述须纠正。默认不重写 AGENTS/冻结 Foundation；任务内规则沿既有 Program-specific 窄授权执行。

可以把本补充与 Review 放进 `Docs/Validation/HHOS-FAV-001/ReviewClosure-01/`，避免再人工重抄一份长计划。原 Review 作为历史事实保留，不改其结论来隐藏缺陷。

## 4. 改动权限与禁止范围

允许改动：
- `Prototypes/FoundationValidation/**` 内本轮相关核心、真实 adapter 边界、既有 App/CLI 最小入口、候选 schema 和定向测试。
- `Docs/Validation/HHOS-FAV-001/**` 的整改记录、证据、状态、impact、Owner Action Pack。
- 必要 Operations 任务/状态更新。

候选 schema 因最小修复需要演进时，允许最小迁移/兼容处理；保护已有验证 store/证据，不用删除 store 绕过不兼容。旧 V1 来源和原 fixture 保持不可变，不改旧模型迎合新候选。

不修改 `HouseholdOSApp/**`、正式 xcodeproj、正式 Schema、正式测试、发布配置或正式 entitlements。不使用真实用户 store、系统相册、账号切换、云删除/上传、Developer Portal、签名资源创建、Production、TestFlight。没有新增真实服务流量预算；逻辑故障优先注入。

不引入 CRDT、通用同步/恢复/冲突工作流平台；不实现全部三档媒体产品 UI、全库 Photos 匹配、tombstone GC、动态系统备份排除等已延期能力。

普通局部修复顺带发现同一状态机/同一新增路径的必然缺陷，可在不扩大产品语义的条件下修复并加最小反例。不要用“只允许五条”留下同根缺陷，也不要借此开启全仓任意重构。

## 5. 内部推进顺序

建议按依赖收敛为三个内部批次，不是三个 Goal/审批：
1. **同步状态与发送**：IR-01、IR-02、IR-04；一起核对父子 incarnation、Profile 投影、Draft→Item、重复/迟到事件。
2. **当前媒体与恢复**：IR-03、IR-05；统一当前 representation 选择及冲突状态恢复，再做跨边界组合回归。
3. **最小链路补齐与收尾**：E-01、E-02；复用前两批核心，完成证据和最终候选。

每项先核实原发现，优先在实际共享生产候选代码路径上写出会失败的原生回归，再修复。Review 并非不可质疑：若某项在当前代码确实不成立，提供准确路径、受控反例、原生证据与假设差异，标 `DISPUTED_WITH_EVIDENCE` 待独立复核；不能盲改，也不能以“已有51项通过”否定新反例。

不能通过 skip、吞错、调整期望去接受错误行为、缩小测试输入逃避缺陷。轻量源码探针用于定位，不能替代最终 SwiftData/adapter 边界回归；fake 只替代服务和交付时序，与真实 adapter 共用 codec/reducer/选择逻辑。

E-01/E-02 默认完成本合同定义的最小实现与回归，**不允许只改措辞就把缺口标成已完成**。真有不可自动决定的语义问题时，保留准确缺口与最小反例，完成其它安全工作后统一报告。

## 6. 测试节奏与最终代码证据

- 启动不要为仪式先跑一次全量；先跑会抓住本次缺陷的 focused tests。
- 每次修复跑直接相关测试；触达公共 Sync/Schema/Projection/Backup 时扩大到 affected 集成集合。
- 三批不分别跑完整 Unit/UI/clean build；使用一个主要执行位置，不能本机全量后再无依据复制到 CI。
- 本轮跨同步、媒体、备份和迁移引导，最终候选安排 **一次验证工程完整确定性测试集合**，并构建实际交付的原生验证 App/Simulator 配置。
- 当 shared core / schema / App/CLI 入口变化时，补一条小型原生本地链路、进程重开检查，确认不是只有 macOS package 测试绿。E-01/E-02 的必要断点/幂等证据不能省略。
- 不机械重跑正式 App 全量 Unit/UI，也不无故追加 clean/Release build。required checks 如平台要求必须遵守，优先复用相同候选证据，不绕过/关闭检查。
- 修改了 legacy/candidate model、迁移入口、工具链或实际依赖时，相关迁移/重开证据重新验证；未变的旧库证据可复用，但 E-02 新桥接测试必须运行。
- 收尾后出现局部修复：失效受影响证据，运行 affected 集合并记录依据。只有影响再次扩到核心全局才重跑完整 gate。“一次”是计划默认，不是失败后禁止必要复验的次数上限。

所有结果绑定最终源文件/config/fixture/toolchain指纹；文档-only/PR元数据变化不使全部运行证据失效。禁止用修复前51/51代替新候选。不要承诺固定新增测试数或覆盖百分比；可以参数化少量测试覆盖多个反例。

## 7. 审查、证据与交付状态

修复后做一次聚焦只读交叉复核：重点看“re-add→旧删除重放→子项、同revision两图→恢复→迟到ACK、旧库bootstrap→重启重复→空白端”。能用独立 reviewer 且不引入新资源/计费权限时可用一次；否则如实称自审，不伪称再次独立通过。无需每批重新叫 Owner 或换 High。

唯一机器状态记录 IR/E 项的处置、失败前后证据、相关文件/测试、指纹与剩余外部项；短小 `IR_CLOSURE.md` 用一张表总结即可。

更新 FOUNDATION_IMPACT：只保留新证据支持的结论；更新实现地图中受影响路径。对真正被证据改变的窄协议规则说明依据，不擅自把候选决策标成永久 Foundation Freeze。修正文档里已过时的“Draft PR 缺失”等事实，不新增无关文档重构。

Owner Action Pack 本轮只是维护后续步骤，不要求 Owner 现在执行。若入口变化会让原操作步骤失效，要修正步骤、按钮与证据出口；保留真实 CloudKit/Photos/iOS17/光学等待项，不能把本轮本地结果提升为 live PASS。

结束状态首选：
`READY_FOR_INDEPENDENT_REVIEW — LOCAL_REMEDIATION_COMPLETE; LIVE_EVIDENCE_PENDING`
条件：五项问题实证修复、E-01/E-02最小链路完成、最终本地回归/构建通过、同一Draft PR已更新。

若有有据争议：`READY_FOR_INDEPENDENT_REVIEW — FINDING_DISPOSITION_REQUIRED`，清楚注明，不能宣告无遗漏完成。
若缺执行环境且核心原生回归未运行：`BLOCKED — LOCAL_VALIDATION_ENVIRONMENT_REQUIRED`；不能冒称只是等真实云环境。
若远端发布受阻：分别报告本地代码/验证状态与发布状态，不丢弃成果，不把未推送称已交付。

## 8. Git 授权与边界

Owner 已授权：在已有验证 worktree/分支 stage本轮自有文件、合理commit、普通push到该分支、更新现有Draft PR #5正文/追加简短整改说明。不要为这些动作再次聊天询问“可以push吗”。按有意义的远端恢复点批量push，不每修一个测试就推一次。

不创建新的PR、不得retarget现有PR、不merge/mark-ready/auto-merge/force-push/rebase改共享历史、不删分支/tag/release、不直接提交main。拒绝或缺少平台权限时不得换通道/复制凭据/降低沙箱绕过；保存本地checkpoint，继续不依赖远端的工作，有必要时集中报告。

最终 fetch/核验远端head与本地目标一致、PR仍Draft且未合并。允许任务自有工作区变干净；原工作区既有Owner修改必须仍保留，不为“干净”而处理它们。

## 9. 不停与真阻塞

常规编译、定向失败、fixture错误、局部迁移适配、轻量文档修正、普通网络重试，都属于自治责任；缺真实云/Photos/真机证据不能成为本轮本地修复的停止理由。

需要正式产品取舍、破坏真实数据、操作生产/外部账号、覆盖未知Owner成果或所有剩余工作依赖不存在的Apple本地环境时，才隔离并统一报告阻塞。不要重复空跑：每轮失败应带来新诊断/反例/修正；持续无信息增益就变更诊断方法并继续其它项。

## 10. 最终中文报告（简短）

- 结果；起止HEAD；PR #5；远端对齐；原工作保留。
- IR-01～IR-05、E-01/E-02各一行：是否复现/如何修复/新回归/结果。
- 实际跑了哪些focused/affected/final原生测试与build；哪些复用及理由；不得虚报独立测试或live evidence。
- 代码候选SHA与docs-only终点SHA区分；已知非blocker/外部待验。
- 剩余可自动解决的事项必须明确，无则写“本轮本地整改未发现未闭环项”，不要写“项目零风险”。

交付后停止，等待ChatGPT独立复核；不直接进入真机补证、最终Freeze或正式Foundation/Wardrobe实现。
