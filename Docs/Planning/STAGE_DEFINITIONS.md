# Stage Definitions

Status: PROPOSED BASELINE
Version: 1.0

## Required Stage Template

每个 Stage 必须包含：

### Identity

- Stage ID
- Title
- Status
- Branch
- Owner approval reference

### Objective

一句话说明本阶段结束后新增的可验证能力。

### Included Scope

只列必须实现的内容。

### Explicit Non-goals

列出最容易被误实现的未来能力。

### Referenced SSOT

列出必须阅读的 Foundation Documents。

### Acceptance Criteria

使用可以测试、构建或审计的条件。

### Required Verification

- 聚焦测试
- 全量测试
- 构建
- git diff --check
- git status
- 额外手工/模拟器检查

### Git Authorization

明确：

- 是否允许创建分支
- 是否允许 commit
- 是否允许 push
- 是否允许 Draft PR
- 是否允许 merge（默认否）

### Stop Conditions

列出必须停止并请求 Owner 判断的情况。

### Completion Updates

明确更新：

- CURRENT_STATE
- CURRENT_TASK
- DECISION_LOG（如适用）
- KNOWN_LIMITATIONS（如适用）

## Stage Status Values

- PROPOSED
- APPROVED
- IN_PROGRESS
- BLOCKED
- AWAITING_OWNER_REVIEW
- ACCEPTED
- REJECTED
- DEFERRED

只有 `APPROVED` 可以开始实现。

## Stage Size Guidance

一个合理 Stage 应：

- 1 个清晰目标。
- 通常涉及 1 个主要领域。
- 能独立测试。
- 不依赖大量尚未实现的未来模块。
- 失败时容易回退。
- Review 时能理解完整 diff。

若 Acceptance Criteria 超过约 10–12 个独立结果，应考虑拆分。
