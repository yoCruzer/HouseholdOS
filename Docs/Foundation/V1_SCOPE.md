# V1 Scope

Status: FROZEN
Version: 1.0

## V1 Goal

建立一个能够真实长期使用的本地优先家庭物品管理 App，可靠完成：

> 录入 -> 整理 -> 查找 -> 变化记录 -> 基础复盘

V1 是 Daily Driver 基线，不是所有长期愿景的实现。

## Must Have

### Foundation

- iOS 原生工程与测试基础。
- 本地持久化。
- 媒体保存。
- 可恢复的草稿机制。
- 稳定的领域和 Repository 边界。

### Capture

- 拍照录入。
- 从相册选择。
- 手工录入。
- 单件 CaptureDraft -> Item。
- 自动保存草稿。
- 连续拍摄多件物品统一进入草稿箱。
- 批量设置公共位置、分类、标签和成员语境。
- 合并、删除和单项覆盖。

### Item Library

- Item 创建、读取、编辑和归档。
- 图片、名称、分类、标签、品牌、型号、规格摘要和备注。
- 搜索、筛选和基本排序。
- 正式 Item 唯一必填名称。

### Spaces

- 任意深度 LocationNode。
- 默认位置与当前位置区分。
- 单件和批量移动。
- 位置历史。
- 未分配、未知、外部和无固定位置。

### Acquisition and Cost

- 取得方式。
- 近似日期。
- 金额未知/估算语义。
- 基础 PurchaseOrder/PurchaseLine 数据边界。
- CostEvent。
- 基础净投入计算。

### Lifecycle

- 基础状态和 LifecycleEvent。
- 借出与归还。
- 维修中。
- 出售、赠送、退货、回收和报废。
- 终止后归档而非删除。

### Usage and Review

- “使用一次”。
- 批量次数/估算基础。
- ExperienceNote。
- 是否愿意再次购买。
- 基础指标和数据质量说明。

### Maintenance and Warranty

- 维修/保养记录。
- 保修期限和凭证。
- 费用关联。
- 基础提醒。

### Privacy and Data

- 本地优先。
- 本地导入保留原始元数据。
- 普通对外分享默认删除 GPS。
- 基础导出和备份能力。
- 敏感附件最小披露。

## Should Have if Schedule Allows

- Item 作为容器。
- 更完整 PurchaseOrder UI。
- Home 摘要。
- 归档库高级筛选。
- 批量编辑更多字段。
- 更完善的提醒列表。

## Deferred

- WishItem 完整功能。
- CloudKit 与家庭实时共享。
- OCR。
- AI 识别和购买建议。
- 电商同步。
- 二维码盘点。
- 自动估价。
- 复杂耗材库存。
- 多平台客户端。
- 订阅与商业化体系。

## V1 Stop Criteria

满足以下条件即可停止扩张并进入稳定化：

1. 用户可以可靠补录家庭现有物品。
2. 日常新增物品能在低负担下完成。
3. 查找位置和基础资料明显优于只靠相册/记忆。
4. 核心生命周期操作不破坏历史。
5. 数据可备份和导出。
6. 主流程在真机上连续使用没有 P0/P1 数据安全问题。
7. 新需求主要属于体验增强或后续愿景，而非核心闭环缺口。
