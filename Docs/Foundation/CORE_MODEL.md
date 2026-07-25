# Core Model

Status: FROZEN
Version: 1.0

## Core Structure

HouseholdOS 采用：

> 物品本体 + 关联事实 + 可计算指标

### Item

正式持有或管理的一件物品。保存稳定身份和当前快照。

### CaptureDraft

尚未确认的录入草稿。可以不完整，不参与正式搜索、统计和生命周期分析。

### WishItem

尚未取得的购买候选对象。独立于 Item，避免未持有对象污染正式持有语义。V1 仅保留概念边界。

### Household / Member

数据归属、家庭空间和人员语境。

### MediaAsset

物品图片、位置图片、票据、保修凭证和其他媒体。需要区分普通图片与敏感附件。

### LocationNode

任意深度的家庭空间树。任何节点都可直接存放物品。

### ItemPlacement

物品在某位置或外部状态下的一段有效期，是位置历史事实来源。

### Acquisition

物品如何进入当前家庭的事实。

### PurchaseOrder / PurchaseLine

一次购买交易及其中的商品行。允许一张订单关联多个物品。

### LifecycleEvent

开始使用、状态改变、借出、维修、出售、赠送、报废等事实事件。

### UsageRecord

一次使用、批量次数或一段时间的使用频率估算。

### MaintenanceRecord / WarrantyRecord

维修、保养、清洁、升级和保修事实。

### CostEvent

围绕物品发生的支出、退款、赔偿和收入。

### ExperienceNote

带时间语境的使用心得、问题、购买复盘和最终评价。

### Reminder

保修、归还、维护和复盘提醒。

## Core Relations

- Household 1--N Item
- Household 1--N LocationNode
- Household 1--N Member
- Item 1--N MediaAsset
- Item 1--N ItemPlacement
- Item 1--N LifecycleEvent
- Item 1--N UsageRecord
- Item 1--N MaintenanceRecord
- Item 1--N WarrantyRecord
- Item 1--N CostEvent
- Item 1--N ExperienceNote
- PurchaseOrder 1--N PurchaseLine
- PurchaseLine N--1 Item

## Fact vs Snapshot

历史事实：

- ItemPlacement
- LifecycleEvent
- UsageRecord
- MaintenanceRecord
- CostEvent

当前快照：

- Item.currentStatus
- Item.currentPlacementId
- Item.defaultLocationId
- Item.coverMediaAssetId

快照由领域服务统一维护，并且必须可以从事实记录重建或验证。

## Container Model

Item 可选择性成为容器：

- 容器 Item 关联一个 LocationNode。
- 其他 Item 放入该 LocationNode。
- 容器上级位置变化时，内部物品完整路径随树结构自然变化。
- V1 后半阶段再实现，不影响基础位置树。
