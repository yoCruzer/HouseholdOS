# UX Flows

Status: FROZEN AT FLOW LEVEL
Version: 1.0

## Flow 1 — Single Item Capture

1. 用户选择拍照、相册或手工录入。
2. 系统立即创建本地 CaptureDraft。
3. 图片保存成功后展示确认页。
4. 用户至少输入或确认名称。
5. 可选填写分类、位置、状态。
6. 用户确认。
7. 领域服务原子创建 Item、初始 Acquisition/Placement（如适用）和媒体关系。
8. 草稿标为 converted 或安全清理。
9. 返回 Item Detail 或继续录入。

失败原则：

- 媒体或草稿一旦成功保存，后续识别失败不得丢失。
- 正式创建失败时保留草稿。
- 不允许产生“半个正式 Item”。

## Flow 2 — Batch Capture

1. 可选选择当前盘点位置。
2. 连续拍摄多件物品。
3. 每件或每组照片进入独立草稿。
4. 用户在草稿箱批量设置位置、分类、所有者和标签。
5. 单个草稿可覆盖公共值。
6. 支持重新排序、合并误拆、删除错误草稿。
7. 用户分批或全部确认。
8. 未确认草稿继续本地保存。

Batch Capture 位于单件流程稳定之后。

## Flow 3 — Find an Item

1. 用户从 Items 搜索或从 Spaces 浏览。
2. 输入名称、品牌、型号、标签或位置关键词。
3. 结果展示封面、名称、当前位置和状态。
4. 点击进入详情。
5. 当前位置明确时展示完整路径。
6. 未知或外部状态使用清晰文案，不伪造位置。

## Flow 4 — Move Item

1. 从 Item Detail 或批量选择进入“移动”。
2. 选择目标 LocationNode 或非位置状态。
3. 可选填写时间、原因和备注。
4. 领域服务关闭旧活动 ItemPlacement。
5. 创建新 ItemPlacement。
6. 更新 Item.currentPlacementId。
7. Timeline 展示移动事实。

## Flow 5 — Lend Out / Return

借出：

- 选择借给谁、日期、预计归还、备注。
- 原子创建 LifecycleEvent 和 outsideHousehold placement。
- 保留 defaultLocation。

归还：

- 创建 returnedFromLoan 事件。
- 选择恢复默认位置或其他位置。
- 关闭外部 placement，创建新 placement。

## Flow 6 — Maintenance

1. 新建维修/保养记录。
2. 可选同步状态为 awaitingRepair 或 underRepair。
3. 记录问题、处理方、照片和费用。
4. 完成后填写结果和下次维护时间。
5. 原子更新生命周期状态和提醒。

## Flow 7 — Terminate Holding

出售、赠送、退货、回收或报废：

1. 选择终止类型和日期。
2. 可选记录收入/退款。
3. 可选完成最终复盘。
4. 创建终止 LifecycleEvent。
5. 关闭活动 placement。
6. Item 进入归档库，不物理删除。

## Flow 8 — Share Media

1. 用户选择分享图片或物品摘要。
2. App 生成分享副本。
3. 默认应用 Export Privacy Policy，删除 GPS。
4. 共享界面明确提示隐私处理。
5. 用户可在设置中了解并修改默认策略。
6. 原始本地文件保持不变。
