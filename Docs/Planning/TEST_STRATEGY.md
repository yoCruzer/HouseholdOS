# Test Strategy

Status: PROPOSED BASELINE
Version: 1.0

## Goals

测试优先保护：

1. 用户数据不丢失。
2. 草稿与正式数据边界。
3. 状态、位置和生命周期历史一致。
4. 金额与日期精度。
5. 原子领域操作。
6. 备份、导出和隐私策略。
7. 高频主流程。

## Test Layers

### Domain Unit Tests

覆盖：

- 值对象验证。
- 状态转换。
- 快照与事实一致性。
- 成本公式。
- 日期精度。
- 不变量。

应尽量不依赖 SwiftUI 和真实持久化。

### Repository Tests

使用内存容器验证：

- CRUD。
- 归档语义。
- 查询和排序。
- 关系完整性。
- 错误回滚。
- Schema 迁移（开始存在多个版本后）。

### Application Use Case Tests

覆盖原子操作：

- Draft -> Item。
- Move Item。
- Lend/Return。
- Start/Complete Maintenance。
- Terminate Holding。
- Share with Privacy Policy。

### UI Tests

只覆盖高价值主流程：

- 单件录入。
- 草稿恢复。
- 搜索并定位物品。
- 移动物品。
- 终止持有。
- 导出隐私提示。

### Manual / Simulator / Device

按 Stage 记录：

- 权限流程。
- Camera/Photo Library。
- 大图和多图资源行为。
- App 重启恢复。
- 真机存储和性能。
- 分享 Sheet 元数据检查。

## Required Stage Verification

默认：

```text
git diff --check
focused tests
full tests
app build
git status --short
```

具体命令在 F0 创建工程后写入 `CURRENT_STATE.md`。

## No False Claims

- 未执行不得写“通过”。
- 环境不支持必须写“未执行 + 原因”。
- 仅编译测试文件不等于测试通过。
- 模拟器通过不等于真机通过。
- 自动检查不能代替隐私导出文件的实际抽查。

## Data Safety Regression Suite

从 F1 开始逐步建立永久回归：

- Draft crash/relaunch recovery。
- Formal creation rollback。
- Unknown vs zero。
- ApproximateDate preservation。
- Active placement uniqueness。
- Terminal lifecycle archives rather than deletes。
- Export copy does not mutate original。
- Default share strips GPS。
