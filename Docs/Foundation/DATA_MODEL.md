# Data Model

Status: FROZEN AT SEMANTIC LEVEL
Version: 1.0

本文件冻结领域语义，不冻结最终 Swift 类型名称、SwiftData 注解和存储拆分。实现阶段可在不改变语义的前提下调整技术形态。

## Shared Value Types

### ApproximateDate

必须表达日期精度：

- exactDate
- month
- year
- unknown

不得用虚构的 `January 1` 代表只知道年份。

### MoneyAmount

- 使用 Decimal 或等价十进制表示。
- 保存 amount 与 currencyCode。
- 支持 estimated 标记。
- unknown 与 zero 必须可区分。

### RecordIdentity

核心实体使用稳定 UUID，并保存 createdAt、updatedAt（适用时）。

## Item

Required:

- id
- householdId
- name
- createdAt
- updatedAt
- captureSource

Optional / contextual:

- sourceDraftId
- aliases
- brand
- model
- specificationSummary
- serialNumber
- generalNote
- categoryId
- tagIds
- recordForm: single / pair / set
- quantity
- quantityUnit
- ownershipType
- ownerMemberId
- primaryUserMemberId
- currentStatus
- defaultLocationId
- currentPlacementId
- coverMediaAssetId
- archivedAt

规则：

- name 是正式建档唯一必填的用户输入字段。
- draft 不属于 Item 状态。
- currentStatus 和 currentPlacementId 是快照。
- 品类差异属性 V1 使用 specificationSummary，不扩张通用表。

## CaptureDraft

- id
- householdId
- createdAt
- updatedAt
- captureSource
- mediaAssetIds
- suggestedName
- confirmedName
- suggestedCategoryId
- selectedCategoryId
- inheritedLocationId
- selectedLocationId
- selectedOwnerMemberId
- tagIds
- draftState
- orderingIndex
- mergeGroupId
- note

Draft 确认后创建 Item，并保留 sourceDraftId 追溯。

## WishItem

V1 仅冻结语义边界，暂不要求实现。未来可能包含：

- id
- householdId
- candidateName
- categoryId
- desiredFeatures
- targetBudget
- priority
- sourceLinks
- waitUntil
- comparisonNotes
- status
- convertedItemId

WishItem 不得持有 currentPlacement、usage、maintenance 或 active ownership 语义。

## LocationNode

- id
- householdId
- name
- type
- parentId
- note
- mediaAssetId
- sortOrder
- archivedAt
- linkedContainerItemId

任意节点可直接存放物品；类型不强制层级。

## ItemPlacement

- id
- itemId
- locationNodeId (nullable for non-located states)
- placementState
- startedAt
- endedAt
- confirmedAt
- reason
- note
- operatorMemberId

placementState 至少包括：

- located
- unassigned
- unknown
- outsideHousehold
- noFixedLocation

同一 Item 同一时间只能有一个活动 placement。

## Acquisition

- id
- itemId
- type
- acquiredDate: ApproximateDate
- source
- conditionAtAcquisition
- paidAmount: MoneyAmount?
- estimatedValue: MoneyAmount?
- temporaryPossession
- note
- purchaseLineId

type：

- purchase
- gift
- inheritance
- companyProvided
- borrowed
- exchange
- selfMade
- unknown

## PurchaseOrder / PurchaseLine

PurchaseOrder：

- merchant
- platform
- orderNumber
- orderedDate
- receivedDate
- totalAmount
- discountAmount
- shippingAmount
- taxAmount
- sensitiveAttachmentIds

PurchaseLine：

- orderId
- itemId
- quantity
- lineAmount
- allocationNote

## LifecycleEvent

- id
- itemId
- type
- occurredAt
- resultingStatus
- relatedPlacementId
- relatedMaintenanceId
- relatedCostEventIds
- note
- operatorMemberId

建议类型见 Product Design Book。终止性事件不物理删除 Item。

## UsageRecord

- id
- itemId
- mode: occurrence / batchCount / periodEstimate
- occurredAt / periodStart / periodEnd
- count
- estimatedFrequency
- userMemberId
- note

Item 可配置 trackingMode：

- tracked
- occasionalEstimate
- continuous
- notTracked

## MaintenanceRecord

- id
- itemId
- type
- discoveredDate
- startedDate
- completedDate
- problemDescription
- resolution
- provider
- selfHandled
- mediaAssetIds
- costEventIds
- result
- nextMaintenanceDate
- note

## WarrantyRecord

- id
- itemId
- provider
- startDate
- endDate
- coverage
- credentialAssetIds
- contact
- note

## CostEvent

- id
- itemId
- direction: expense / income
- type
- amount: MoneyAmount
- date
- estimated
- description
- purchaseOrderId
- maintenanceRecordId
- lifecycleEventId

计算指标不得作为不可重建事实写入 Item。

## MediaAsset and Metadata

- 本地导入默认保留原始元数据，包括 GPS。
- 媒体必须区分普通照片、位置照片与敏感凭证。
- 对外分享生成派生副本并应用 Export Privacy Policy。
- 普通分享默认删除定位元数据。
- 原始文件不因分享而被修改。

## Delete and Archive

- 有历史引用的核心实体默认归档。
- 草稿和未引用临时媒体可以物理删除。
- 终止持有不是删除。
- 数据迁移必须保留未知和估算语义。
