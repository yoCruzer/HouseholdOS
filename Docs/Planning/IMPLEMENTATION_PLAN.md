# Implementation Plan

Status: PROPOSED BASELINE
Version: 1.0

## Governance Model

采用：

> Stage 内自治 + Stage 间 Owner Gate

每个 Stage 必须：

- 范围有限。
- 验收条件可验证。
- 有明确禁止范围。
- 完成后自动测试、构建、更新文档并停止。
- 经 Owner Review 后才进入下一 Stage。

## Proposed Stages

### G0 — Governance Foundation

目标：建立文档 SSOT、执行规则、状态机制和初始仓库基线。

不包含 Swift 或 Xcode 工程。

### F0 — Repository & Xcode Foundation

目标：

- 创建 iOS App 工程。
- 固化最低部署版本、Bundle Identifier 临时策略和 Scheme。
- 建立目录与测试 Target。
- 完成首次 build 和空测试。
- 记录本机/Xcode 验证环境。

不实现业务模型。

### F1 — Persistence Foundation

目标：

- 建立 SwiftData 容器。
- 测试内存容器。
- Repository 基础。
- 媒体存储接口和错误边界。
- 最小迁移与 Schema 版本策略。

不实现完整 Item UI。

### I1 — Core Item Foundation

目标：

- Item 最小领域语义。
- 创建、读取、编辑和归档。
- 基础 Repository 测试。
- 不实现 Acquisition、位置历史或使用记录。

### C1 — Single Item Capture

目标：

- Camera/Photo Library/Manual 入口。
- CaptureDraft 本地保存。
- 单件确认成为 Item。
- 失败恢复。

### C2 — Draft Inbox & Editing

目标：

- 草稿列表。
- 编辑、删除、恢复、确认。
- 未完成草稿不污染正式统计。

### L1 — Item Library

目标：

- 正式物品列表、详情、搜索和基础筛选。
- 图片和基础资料编辑。

### S1 — Location Foundation

目标：

- LocationNode 树。
- 默认位置。
- 当前 placement 和移动历史。
- Spaces 浏览。

### C3 — Batch Capture

目标：

- 连续拍摄。
- 公共位置继承。
- 批量编辑、单项覆盖、合并和确认。

必须在 C1/C2/S1 稳定后执行。

### A1 — Acquisition & Cost Foundation

目标：

- Acquisition。
- ApproximateDate。
- MoneyAmount。
- CostEvent。
- 基础净投入。

### E1 — Lifecycle Events

目标：

- 状态快照。
- 生命周期事件。
- 借出、归还、终止持有和归档。

### M1 — Maintenance & Warranty

目标：

- 维修/保养。
- 保修与凭证。
- 费用和状态联动。
- 提醒基础。

### U1 — Usage & Experience

目标：

- 使用一次。
- 批量使用记录。
- ExperienceNote。
- 再次购买意愿。

### I2 — Insights

目标：

- 统一计算口径。
- 数据质量提示。
- 基础复盘视图。

### D1 — Export, Backup & Privacy

目标：

- 结构化导出。
- 媒体备份。
- Export Privacy Policy。
- 分享副本默认删除 GPS。

### H1 — Household Context

目标：

- Household/Member 最小语境。
- 所有者与主要使用者。
- 不实现实时多人同步。

### R1 — V1 Readiness

目标：

- 全量数据一致性审计。
- 真机主流程。
- 性能和资源边界。
- 迁移、备份、恢复验证。
- 已知限制和发布候选判断。

## Stage Ordering

默认顺序：

G0 -> F0 -> F1 -> I1 -> C1 -> C2 -> L1 -> S1 -> C3 -> A1 -> E1 -> M1 -> U1 -> I2 -> D1 -> H1 -> R1

Owner 可调整顺序，但必须更新本文件和 CURRENT_TASK。

## Autonomy Expansion

- G0、F0、F1、I1：单 Stage 严格 Review。
- 工作流稳定后，可一次批准两个高度相关的实现 Stage。
- 数据迁移、隐私、共享和发布阶段始终保持独立 Owner Gate。
