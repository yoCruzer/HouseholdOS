# HHOS-FAV-001 / PR5-IR-Closure-02
# 第二轮集中整改：跨模块恢复与同步收敛

## 1. 目标与授权

Owner 已批准在现有验证 Program 内继续集中解决可自动处理的问题。你负责完成实现、验证、
失败诊断、修复、针对性重测、文档和现有 Draft PR 更新，不按内部子任务请求人工批准。

本轮必须：
- 复现并闭环 R2-01、R2-02、R2-03；使用实际源代码路径而非仅修改 Review 探针。
- 在同一条最小业务链上验证跨模块组合，不仅让各模块单独测试通过。
- 同时满足安全性与有条件的可完成性；真实冲突/外部不可用不能被伪装成已同步。
- 保留上轮已经修好的 IR-01～IR-05、E-01/E-02，以及真实平台待验边界。
- 交付可独立复核的最终代码和证据，保持 Draft，不 merge/ready/auto-merge/Freeze。

继续原 Program 与分支：
`yoCruzer/HouseholdOS` / `spike/foundation-validation` / PR #5。
起始审查 HEAD：`449328ea87b40f773c4dcfa957f3ae00bf43e7ef`。
正式已接受基线：`f19469fe13be175d1b28d71ddb6b5a917abdcc32`。

## 2. 先恢复真实工作状态

读 AGENTS.md、Docs/Operations/CURRENT_STATE.md、CURRENT_TASK.md、
Docs/Validation/HHOS-FAV-001/VALIDATION_STATE.json、原 Contract-v1.2 及 ReviewClosure-01。
完整读取本包的 GOAL/INTERACTION_CONTRACT 和 Review 报告。

记录当前分支、HEAD、工作区、PR base/head/draft、现有验证 worktree。
核对 origin 确实指向批准仓库，不向别的 remote 推送。优先继续现有隔离验证 worktree。
历史目录 `<original-worktree>` 和两份 String Catalog 改动只是保护提示，
不假定路径/主机/修改数量至今未变；保护目前所有已有修改，不 stash/reset/clean/覆盖或切换原目录分支。
可记录私有路径、大小、SHA-256核对保护；不把私人差异或个人路径提交公开 Git。

若 HEAD 已前进，查看新增提交是否属于当前 Program，复用已完成成果及有效证据。
不因同任务已开始而重建 harness；不因原目录脏而停止可在隔离 worktree 完成的工作。
未知修改只能保持隔离；确实无法安全隔离时才汇报具体阻塞。

把本补充及 Review 资料归档到 `Docs/Validation/HHOS-FAV-001/ReviewClosure-02/`，
CURRENT_TASK 引用本轮授权。将受影响本地断言恢复为待整改，不把旧 PASS 删除或改写成新证据。
原合同中的数据安全/隐私/隔离规则继续生效；“上轮结束等 Owner Review”由本次明确启动授权替代。
仅本 Program 内部自治和风险驱动测试生效，不放宽永久治理规则，不默认改 AGENTS。

## 3. 修复范围与顺序

先核对实际实现，再把 Review 的最小反例纳入真正 ValidationCoreTests。
ReviewSource/NativeFollowupTests.swift 是草案，需适配当前 API；先使反例在旧代码下合理失败，
不能将编译失败、空测试集合、缺 SDK 或无关 fixture 错误计为成功复现。

建议在一次内部计划中处理：
1. R2-01/R2-02：服务端已观察基准、发送快照、自回传识别、后续本地意图之间的共同边界。
2. R2-03：被新明确意图替代的旧子操作如何退出活动 pending，同时保留必要历史。
3. 运行交互合同的组合与对照，修复直接关联的新反例，再做一次本轮收尾验证。

这三个步骤不是三个 Goal，也不对应三次全量测试/人工审批。
允许对直接受影响的 SyncCore、CloudAdapter、BackupRestore、LocalChain、MediaTransfers、
LegacyFixture 和现有报告/测试辅助代码做最小修改。不要为列名方便批量搬文件或重写所有模块。
新增窄辅助类型/回执可以，但需解释权威来源与重建关系，不能再造第二套业务真源。
不为避免所有 schema 变化而把不清楚的数据塞进万能 checkpoint；也不为命名美观迁移全库。
若不得不更改实验 schema，只处理隔离实验库的兼容，明确留证，绝不触碰 shipping schema/真实库。

Review发现允许有据驳回：给出当前代码路径、原生反例和预期语义，并保持对应断言；不能盲目照改，
也不能用旧65/65、不相关测试或降低约束来声称发现不成立。

## 4. 交互验证是本轮收口的一部分

详见 INTERACTION_CONTRACT.md 和 SCENARIOS.json。
优先扩展现有 XCTest helper 与确定性服务，不写 JSON 解析执行平台。
服务替身只模拟网络交付/条件版本/故障时机，不重写业务 merge/admission/outbox/restore。
真实和 fake 路径必须调用相同 codec、reducer、持久化和生成发送记录的代码；adapter wiring 也要检查。

不要只验证某一行 guard 加上了：场景必须继续到 ACK、目标状态、队列终态和重启。
中断后既验证本地未丢，也验证恢复后可继续；真实外部阻塞应保持准确状态。

## 5. 自动修复与停止边界

常规编译错误、反例失败、fixture错误、事务/状态关联错误、同范围内新增组合反例，都自主诊断修复。
若多个补丁都无法让同一已最小化反例通过，不继续盲目试补丁：先把事件、状态所有者、提交点整理清楚，
然后调整最小实现。只有确实需要改变已批准产品语义/安全要求或超出隔离范围，才合并为一个 Owner 决策。

不以“发现数量达到N”“内部阶段结束”“需要推送”作为停止理由。
不允许无限扩大修复范围：新问题只有能给出本轮相关不变量的最小反例才进入本轮；
不相关产品缺陷准确登记，不借机新增功能。不得为了清空 pending 而静默丢弃有效待发送意图。

真实 CloudKit、Photos、真机、签名、旧 iOS runtime 不足继续 pending；本轮不触发真实云连接、
图库读取/修改、设备账号切换、quota填充或 Developer Portal操作。不要让 Owner 现在拿设备排查逻辑。
当前机器如能跑原生本地测试就用它；平台确实不支持时记录缺口并完成其余工作，不能伪造原生PASS。
本轮不自动下载大runtime或增加付费资源。

## 6. 测试经济性

- 起步复用可信历史基线，不仪式性重跑65项全量。
- 每次改动跑 focused，共享入口修改后跑 affected（Sync/Admission/IRClosure/Backup/Media等实际涉及部分）。
- 新的八类场景是覆盖索引，不是强制八个新文件/八次运行；已有用例有效时复用。
- 主要使用几条实体、一两个小媒体、确定性时序；批次边界最多沿用小型101/300条结构记录，
  不做真实大量传输、不做全部排列组合或无界随机压力测试。
- 集中审计与修复完成后，协调一次最终验证工程全量确定性测试与必要 unsigned 原生构建。
  不强制额外clean Release/完整UI；只有实际修改影响运行入口/重开路径才补最小Simulator smoke。
- “一次”是目标，不是阻止最终正确验证的硬上限：收尾后再改代码，按影响补验；
  仅高影响变化或证据失效才再跑整套，并记录原因。
- 不把本机和CI同一重型集合机械跑两遍，不为checkpoint推送开启全量自动CI。
  不绕过repo必需检查；如现有策略强制，说明原因。
- 旧schema/generator/fixture无变化就复用迁移证据；修改关联输入后才重测相应迁移/进程恢复。
- 不能降低/删除原测试来制造绿灯；若纠正测试的错误假设，保留原失败及明确新语义依据。

## 7. 检查点、证据及最终报告

唯一机器检查点仍是 `VALIDATION_STATE.json`。新增本轮节点/病例映射，不建第二个相互竞争的状态文件。
保存 current candidate、已完成及失效断言、输入指纹、最近有效命令、下一安全动作和外部待验。
中断恢复从首个未完成/证据失效项继续，不重新从头设计或全量重测。

新增一份短 `R2_INTERACTION_CLOSURE.md`；历史IR_CLOSURE和65/65证据保留。
更新 CURRENT_TASK/STATE、VALIDATION_EVIDENCE、FOUNDATION_IMPACT 和 PR 正文的受影响部分；
实际未改变的Owner设备步骤无需重写。源review的探针是历史LOGIC，原生测试要记录自己的运行证据。

每个R2项给：REPRODUCED_FIXED / NOT_REPRODUCED_WITH_EVIDENCE / BLOCKED，实际源码、测试和范围。
每类序列记录预期终态、实际状态、具体测试标识、fixture、失败/通过与final input fingerprint；
不能把“最终一共X/X”贴到每个断言当唯一证据。重启测试注明disk reopen或真实process termination。

可提交：精简总结、合成最小反例、声明来源的测试代码/fixture、脱敏小JSON。
不提交：原始个人照片、账号/Photos ID、绝对个人路径、整库、备份包、巨型log/xcresult或签名材料。

最终返还：
- Result：READY_FOR_INDEPENDENT_REVIEW — R2_LOCAL_CLOSURE_COMPLETE；LIVE_EVIDENCE_PENDING；
  若实际未完如实写 LOCAL_WORK_REMAINING/BLOCKED，不通过措辞隐藏。
- 三项处置、交互序列覆盖、真实冲突/未知parent对照、队列终态定义。
- 实际验证及证据缺口，复用/重测理由。
- 起止HEAD、受测code候选与docs-only最终HEAD区别、工作区保护、唯一PR链接。
- 明确不等于Foundation Freeze/生产就绪；无merge/ready/云操作。

## 8. Git与权限

本轮明确授权：沿用批准分支、task-owned commit、普通push到该repo origin、更新现有Draft PR #5的正文/评论。
每个内部 gate 不再问“是否继续/是否push”。checkpoint按有意义的整合点批量推送，不为每条测试产生push。
平台批准提示仍必须遵守；请求被明确拒绝时不换命令/通道/凭据绕过。
临时网络失败可以合理重试；确实缺权限时保留本地成果，完成不依赖发布的工作，最后统一报告。

没有授权：main直写、merge/mark-ready/auto-merge、force push/rebase共享历史、删除分支、tag/release、
TestFlight/签名资源、生产CloudKit、真实库迁移、正式App修改或启动下一生产阶段。

若已批准边界内所有工作完成，交付并停在独立复核。不要替外部 reviewer 自己宣布独立批准。
