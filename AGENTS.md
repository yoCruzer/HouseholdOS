# AGENTS.md

本文件定义所有自动化编码代理（包括 Codex）在 HouseholdOS 仓库中的永久执行规则。

## 1. 开始工作前必须读取

每个新会话、上下文恢复或任务继续执行前，依次读取：

1. 本文件。
2. `Docs/Operations/CURRENT_STATE.md`。
3. `Docs/Operations/CURRENT_TASK.md`。
4. `CURRENT_TASK.md` 明确引用的 Foundation Documents。
5. 与待修改代码直接相关的现有实现和测试。

不得仅依赖聊天上下文、旧总结或记忆执行。

## 2. 事实源优先级

1. `Docs/Operations/CURRENT_TASK.md`
2. `Docs/Operations/CURRENT_STATE.md`
3. `Docs/Foundation/*`
4. `Docs/Product/HouseholdOS_Product_Design_Book_v1.0.md`
5. `Docs/Planning/*`
6. 代码注释、Issue、PR 描述和外部讨论

发现冲突时停止实现，列出冲突位置和建议处理方式。不得自行选择方便实现的一方。

## 3. Stage 执行规则

- 只实施当前已批准 Stage 的明确范围。
- Stage 内部实现细节可以自治。
- 不得自行进入下一 Stage。
- 不得以“顺手”“为未来准备”为理由扩大范围。
- 不得把后续功能以不可见方式接入运行路径。
- 允许为当前 Stage 建立最小、明确、可测试的扩展边界。
- 任何偏离 Acceptance Criteria 的行为必须在最终报告中显式列出。

## 4. 可以自主决定的事项

在不改变冻结语义和用户可见行为的前提下，可以自主决定：

- 私有类型、函数和文件的命名。
- Stage 内部目录组织。
- 测试拆分与测试辅助代码。
- 无行为变化的小范围重构。
- 编译错误、警告和阶段内测试失败修复。
- Accessibility Identifier、Preview 与测试数据构造。
- 为满足当前验收标准所需的最小协议和依赖注入边界。

## 5. 必须停止并报告的事项

遇到以下任何情况，不得自行继续：

- 需要修改核心实体或核心语义。
- 需要扩大 V1 范围。
- 需要引入第三方 SDK、外部服务或收费依赖。
- 需要改变本地优先、隐私、同步或导出策略。
- 需要破坏已有数据兼容性或执行不可逆迁移。
- 需要修改 Stage 外的重要模块。
- Foundation Documents 之间存在矛盾。
- 工作区包含无法确认归属的未提交修改。
- 测试或构建失败且无法在当前范围内可靠修复。
- 需要访问真实用户数据、外部账号、生产服务或付费签名能力。

## 6. Git 规则

- 不直接在 `main` 上开发。
- 开始任务前记录：当前分支、HEAD、`git status --short`。
- 使用 `CURRENT_TASK.md` 指定的分支；未指定时停止并报告。
- 不覆盖、丢弃或暂存不属于当前任务的修改。
- 禁止 `git reset --hard`、强制推送和重写共享历史，除非 Owner 明确授权。
- 阶段完成后可以按任务授权创建 commit 和 push。
- 未经明确授权不得合并到 `main`。
- 默认创建 Draft PR，不自动启用 auto-merge。
- 每个 commit 必须范围清晰、主题可审计。

## 7. 代码与架构规则

- Swift 与 SwiftUI 优先使用 Apple 原生能力。
- 目标平台和技术基线以 `Docs/Foundation/ARCHITECTURE.md` 为准。
- 领域规则不能散落在多个 View 中。
- 当前快照必须通过领域服务更新，历史事件才是事实来源。
- 金额不得使用二进制浮点表达。
- 不确定日期和金额不得伪装为精确值。
- AI/OCR 结果只能作为建议，不能绕过用户确认。
- 新增依赖前必须获得 Owner 批准。
- 不为尚未批准的同步、共享、AI 或外部集成提前建立复杂框架。

## 8. 测试与验证

完成 Stage 前至少执行：

1. 当前 Stage 聚焦测试。
2. 全量测试。
3. App 或 Package 构建。
4. `git diff --check`。
5. `git status --short`。
6. `Docs/Planning/TEST_STRATEGY.md` 规定的额外检查。

若环境无法执行某项验证，必须说明原因，不得写成“通过”。

## 9. 文档更新

完成 Stage 时：

- 更新 `Docs/Operations/CURRENT_STATE.md`。
- 将 `Docs/Operations/CURRENT_TASK.md` 标为 `AWAITING_OWNER_REVIEW`。
- 仅在形成永久决策时更新 `DECISION_LOG.md`。
- 仅在确认真实限制时更新 `KNOWN_LIMITATIONS.md`。
- 不要为了显示工作量重写稳定 Foundation Documents。

## 10. 最终 Stage Report

最终回复必须包含：

1. Stage Result
2. 起始与结束分支、HEAD
3. 起始与结束工作区状态
4. 已完成范围
5. 明确未完成和禁止范围
6. 修改文件
7. 测试结果
8. 构建结果
9. 设计决策或偏差
10. 已知限制
11. Git 操作
12. 是否满足全部 Acceptance Criteria
13. 建议下一步

完成报告后停止，等待 Owner Review。
