# HouseholdOS Engineering Governance Snapshot v0.1

> Status: PROPOSED FOR F0 ACTIVATION
> Version: 0.1
> Date: 2026-07-26
> Scope: HouseholdOS repository only
> Recommended path: `Docs/Operations/ENGINEERING_GOVERNANCE_SNAPSHOT.md`

## 0. 文档定位

本文档是 HouseholdOS 在通用 AI Software Engineering Governance 研究尚未完成期间采用的**项目级最小充分治理快照**。

它的目标不是建立一套通用、永久、自动化的 AI 工程治理体系，而是确保 HouseholdOS 可以在以下条件下持续推进：

* 产品语义不被编码代理擅自改变；
* 每次只执行一个明确 Stage；
* 实现范围、验证结果和 Git 状态可审计；
* Codex 可以在阶段内部自主工作，但不能越过 Owner Gate；
* 治理研究不会成为 HouseholdOS 初版开发的长期前置阻塞。

本快照适用于 HouseholdOS，不自动适用于其他项目。

本快照补充但不替代：

* `AGENTS.md`
* `Docs/Operations/CURRENT_STATE.md`
* `Docs/Operations/CURRENT_TASK.md`
* `Docs/Foundation/*`
* 已冻结的 Product Design Book

发生冲突时，不得使用本快照覆盖更高优先级的项目事实源。

---

## 1. 核心运行模型

HouseholdOS 采用：

> **Stage 内自治 + Stage 间 Owner Gate**

其含义是：

1. Owner 定义并批准当前 Stage 的目标、范围、禁止范围和验收条件。
2. Codex 可以在当前 Stage 内自主完成普通实现决策。
3. Codex 不得自行扩大 Stage、进入下一 Stage、合并到 `main` 或改变产品语义。
4. 每个 Stage 完成验证后停在 `AWAITING_OWNER_REVIEW`。
5. 只有 Owner 可以决定接受、退回、补证、延期或拒绝当前 Stage。

阶段顺序是规划，不是自动授权。

---

## 2. 项目事实源

### 2.1 永久执行规则

`AGENTS.md` 定义所有编码代理在仓库中的永久执行行为。

### 2.2 项目事实和任务授权优先级

1. `Docs/Operations/CURRENT_TASK.md`
2. `Docs/Operations/CURRENT_STATE.md`
3. `Docs/Foundation/*`
4. `Docs/Product/HouseholdOS_Product_Design_Book_v1.0.md`
5. `Docs/Planning/*`
6. PR、Issue、代码注释、聊天记录和旧报告

### 2.3 冲突处理

发现以下情况时必须停止：

* 两份 Foundation Documents 对同一语义存在矛盾；
* 当前代码与已记录项目状态不一致；
* 当前任务与 Owner 最新明确授权无法同时成立；
* 实现验收条件需要改变冻结产品语义；
* 无法判断某项未提交修改的归属。

不得为了继续执行而自行选择更方便的解释。

报告不确定性时使用：

* `CONFIRMED`
* `HIGH-CONFIDENCE INFERENCE`
* `UNKNOWN / OWNER DECISION REQUIRED`

---

## 3. Stage 启动规则

任何实现 Stage 开始前，必须：

1. 核验本地与远程仓库状态。
2. 记录当前分支、HEAD、remote 和 `git status --short`。
3. 拉取远程引用，但不得覆盖未提交修改。
4. 确认当前 Stage 状态是 `APPROVED`。
5. 确认 Stage 指定了唯一工作分支。
6. 阅读当前任务引用的 Foundation Documents。
7. 检查当前环境是否能够完成该 Stage 要求的测试和构建。

若仓库存在无法确认归属的修改，不得清理、丢弃、覆盖或用新实现掩盖。

---

## 4. 范围与自治边界

### 4.1 Codex 可以自主决定

在不改变冻结产品语义和用户可见范围的前提下，可以自主决定：

* 私有类型、函数和文件命名；
* Stage 内部的局部目录组织；
* 测试文件和测试辅助结构；
* 满足当前验收条件所需的最小协议边界；
* 编译错误、警告和当前 Stage 测试失败的范围内修复；
* 不改变行为的小范围重构；
* Preview、测试数据和 Accessibility Identifier；
* 可逆、局部、低风险的实现细节。

### 4.2 必须由 Owner 决定

以下事项不得由 Codex 自行决定：

* 修改核心实体及其冻结语义；
* 扩大 V1 范围；
* 改变本地优先、隐私、同步、导出或数据所有权策略；
* 引入第三方 SDK、外部服务、收费依赖或云服务；
* 添加尚未批准的 OCR、AI、CloudKit、家庭实时共享或外部平台集成；
* 执行不可逆数据迁移；
* 改变正式 Bundle Identifier、CloudKit Container、App Group 或签名策略；
* 删除兼容性边界；
* 改变 Stage 顺序或直接进入下一 Stage；
* 合并到 `main`。

### 4.3 最小实现原则

允许：

> 为已批准能力建立最小、明确、可测试的演进边界。

不允许：

> 以“未来可能需要”为理由预先实现通用框架、隐藏运行路径、抽象层或尚未批准的功能。

原则是：

> **允许可演进，不允许预实现。**

---

## 5. 架构约束

HouseholdOS 起步阶段遵守：

* Native iOS；
* Swift；
* SwiftUI；
* Apple 原生框架优先；
* Local-first；
* 初始阶段不引入第三方依赖；
* 领域规则不得散落在 SwiftUI View 中；
* 媒体文件与结构化数据保持独立边界；
* 所有可能失败的正式写入必须避免产生半完成状态；
* 不确定日期、金额和事实不得伪装成精确值；
* 不得为了尚未批准的同步、共享、AI 或外部集成搭建复杂框架。

具体 SwiftData、Repository、媒体存储和迁移实现由相应 Stage 决定，不得在 F0 中提前实现。

---

## 6. 文档状态语义

### `CURRENT_STATE.md`

只记录：

* 已确认的仓库现实；
* 已接受或当前正在 Review 的能力状态；
* 最近实际验证基线；
* 已知限制；
* 下一计划 Stage。

不得把未实现、未验证或仅计划中的能力写成已经完成。

### `CURRENT_TASK.md`

必须只描述一个活动 Stage，包括：

* Identity
* Status
* Objective
* Included Scope
* Explicit Non-goals
* Referenced SSOT
* Acceptance Criteria
* Required Verification
* Git Authorization
* Stop Conditions
* Completion Report

一个 Stage 完成后，应将状态改为 `AWAITING_OWNER_REVIEW`，不得自行替换成下一 Stage。

### `DECISION_LOG.md`

仅记录长期影响产品语义、架构、隐私、兼容性或治理方式的永久决定。

### `KNOWN_LIMITATIONS.md`

只记录已经由实现或验证确认的真实限制，不记录纯假设。

---

## 7. 测试和证据规则

每个代码 Stage 默认执行：

1. 聚焦测试；
2. 全量测试；
3. App 或 Package 构建；
4. `git diff --check`；
5. `git status --short`；
6. 当前 Stage 指定的模拟器、真机或手工检查。

F0 建立工程后，应把实际可执行命令记录到项目状态文档中。

禁止虚假证据：

* 未运行不得写成通过；
* 编译成功不等于测试通过；
* 测试通过不等于 App 成功启动；
* 模拟器通过不等于真机通过；
* 环境失败不得写成源代码通过；
* 保留的历史基线不得描述为本阶段重新运行结果；
* 估算值不得描述为实测值。

---

## 8. Git 与审查规则

* 不直接在 `main` 上开发。
* 每个 Stage 使用独立分支。
* 不得使用 `git reset --hard` 清理问题。
* 不得 force push 或重写共享历史。
* 不得覆盖、暂存或提交不属于当前 Stage 的修改。
* commit 必须范围清晰并可审计。
* 只有当前 Stage 明确授权时才允许 commit、push 或创建 Draft PR。
* 默认只创建 Draft PR。
* 未经 Owner 明确批准，不得将 PR 标记为 Ready、启用 auto-merge 或合并。
* Stage 完成报告必须同时说明本地和远程状态。

---

## 9. 中断与恢复

发生网络中断、额度耗尽、Codex 上下文耗尽、终端退出或电脑重启后，不得直接重新开始实现。

必须先执行只读恢复审计：

1. 当前分支和 HEAD；
2. staged、unstaged 和 untracked 文件；
3. 本地 commits；
4. remote refs；
5. ahead/behind；
6. 当前 Stage 的已完成范围；
7. 尚未完成的验收条件；
8. 是否存在来源不明的修改。

不得用删除、重置或重新生成工程的方式制造“干净现场”。

---

## 10. Stage 完成规则

Codex 完成当前 Stage 后必须：

1. 执行全部规定验证；
2. 更新 `CURRENT_STATE.md`；
3. 将 `CURRENT_TASK.md` 改为 `AWAITING_OWNER_REVIEW`；
4. 必要时更新 `DECISION_LOG.md` 和 `KNOWN_LIMITATIONS.md`；
5. 按授权完成 commit、push 和 Draft PR；
6. 输出结构化 Stage Report；
7. 停止并等待 Owner Review。

Codex 不得在报告末尾自行开始下一 Stage。

---

## 11. 治理反馈但不阻塞开发

执行中发现的通用治理问题可以记录为治理改进候选，例如：

* Prompt 中哪些规则重复；
* 哪些验收条件仍存在歧义；
* 哪些证据可以自动生成；
* 哪些 Review 适合独立 Agent；
* 哪些恢复流程可以模板化。

除非问题会造成：

* 数据损坏；
* 隐私风险；
* 产品语义冲突；
* 无法审计的 Git 状态；
* 无法验证的实现结果；

否则这些治理问题不应阻塞当前 HouseholdOS Stage。

---

## 12. v0.1 生效与演进

本快照在以下条件同时满足时生效：

1. Owner 发送明确批准它的 Stage Execution Prompt；
2. 文件进入对应 Stage 分支；
3. `CURRENT_TASK.md` 引用本文件。

本快照不是永久冻结文档。

升级时应遵循：

* 只吸收已经通过实际 Stage 验证的治理经验；
* 不为了理论完整性频繁重写；
* 重大规则变化必须经过 Owner Review；
* 通用治理研究的成果可以逐步回流，但不得自动覆盖当前项目事实。
