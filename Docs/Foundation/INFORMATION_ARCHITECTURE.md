# Information Architecture

Status: FROZEN
Version: 1.0

## Primary Navigation

V1 建议采用四个主要入口：

1. **Home**
2. **Items**
3. **Spaces**
4. **More**

全局突出一个 Capture 入口，可通过 Tab 中央按钮、工具栏或浮动操作实现，具体样式留给 UX Stage。

## Home

聚焦近期行动和低负担入口：

- 快速拍照/相册/手工录入
- 未整理草稿
- 最近添加或移动的物品
- 即将到期的保修/归还/维护提醒
- 基础摘要

V1 不把复杂洞察作为首页主角。

## Items

- 全部正式物品
- 搜索
- 分类和标签筛选
- 状态、位置、成员筛选
- 归档物品入口
- 列表/网格视图（具体实现可分阶段）

Item Detail 建议分区：

- Overview
- Location
- Acquisition & Cost
- Usage
- Maintenance & Warranty
- Timeline
- Notes & Review

默认先展示高频信息，复杂历史按需展开。

## Spaces

- 家庭空间树
- 当前节点直接物品
- 所有下级物品
- 位置面包屑
- 未分配/未知/外部物品快捷入口
- 批量移动

## More

- 草稿箱
- 分类与标签管理
- 家庭与成员（按 Stage 开放）
- 提醒
- 导出与备份
- 隐私与分享设置
- App 设置
- 已知限制和数据说明（开发/测试版本可见）

## Capture Flow

统一入口：

Capture -> CaptureDraft -> Confirm -> Item

入口方式：

- Camera
- Photo Library
- Manual

批量录入：

- 选择盘点位置（可选）
- 连续拍摄
- 草稿列表
- 批量设置公共字段
- 单项覆盖
- 合并/删除/排序
- 批量确认

## Search Semantics

V1 搜索范围：

- name
- alias
- brand
- model
- specificationSummary
- serialNumber
- generalNote
- category
- tags
- location path

图片语义搜索、OCR 文本搜索和 AI 搜索后续实现。

## Empty and Unknown States

界面必须区分：

- 尚未记录
- 明确没有
- 未知
- 无固定位置
- 当前不在家
- 已归档

不能用空白 UI 抹平这些语义。
