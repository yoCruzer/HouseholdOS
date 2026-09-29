# HouseholdOS PR #5 — 第二轮集中整改与交互验证

**Program：HHOS-FAV-001；整改：PR5-IR-Closure-02；执行包：v1.0。**
这是现有 PR #5 的整改补充，不是重启 Program、替换 Foundation v1.2 或批准正式实现。

## 本轮终点

在同一个验证工程、分支及 Draft PR 中，闭环第二轮 Review 的 R2-01、R2-02、R2-03，
并用少量跨模块事件序列证明：数据安全保留，而且在具备必要条件时正确的新操作能完成；
确实需要等待/用户决策的操作有准确原因，已终结的历史操作不再冒充活动 pending。

不安排 Owner 真机/账号/签名操作，不开始正式 App 改造。终点是独立复核，不是 merge 或 Freeze。

## 读取顺序

1. 本文件、`GOAL.md`、`INTERACTION_CONTRACT.md`。
2. `ReviewSource/REVIEW.zh-CN.md`（三项发现及历史证据边界）。
3. `SCENARIOS.json`（八类场景的覆盖索引，不是必须实现的执行引擎格式）。
4. 仓库 AGENTS、CURRENT_TASK、v1.2 合同及上轮整改/唯一状态；以实际代码验证发现。

`ReviewSource` 完整保留第二轮独立 Review 包，包括提取逻辑探针、历史运行结果和未执行的原生回归草案。
只需上传本 ZIP，不必再上传上一份 Review ZIP。不要把历史探针输出或回归草案计为本轮执行结果。

## 固定锚点

- 仓库：`yoCruzer/HouseholdOS`
- 已接受 main 基线：`f19469fe13be175d1b28d71ddb6b5a917abdcc32`
- 本轮起始审查 HEAD：`449328ea87b40f773c4dcfa957f3ae00bf43e7ef`
- 上轮测试代码候选：`b45cb840c2e65ca25c062cde450c235a0195f670`
- 工作分支：`spike/foundation-validation`；唯一 Draft PR：`#5`

以上是检查锚点，不是重置命令。发现同一任务已有更新，先识别并恢复，不回退或覆盖。

## 不扩大工程

使用现有 Swift/XCTest/SwiftData/CloudKit adapter、少量 fixture、一个窄的测试服务替身。
不新建同步框架、测试平台、通用模型检查器、图可视化工具、海量随机压力测试或第三方依赖。
模块内 focused tests 保留；增加的是边界与终态断言，而不是固定数量的新测试。

## 完整性与实际执行范围

`SHA256SUMS.txt` 校验本包除自身之外的全部文件；`SOURCE_MANIFEST.json` 记录来源。
`SCENARIOS.json` 只是验收规格，不能作为测试报告。本包没有运行原生整改测试、没有修改仓库。
短引导见 `SHORT_START_PROMPT.txt`；模型沿用 Owner 当前选择，不要求升档或人工轮流切模型。
