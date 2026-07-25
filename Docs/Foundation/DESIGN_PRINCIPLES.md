# Design Principles

Status: FROZEN
Version: 1.0

1. **Capture First, Enrich Later**
   先可靠保存，再逐步补全。任何高级能力失败都不能阻止草稿保存。

2. **Local First**
   拍照、浏览、编辑、搜索和核心统计在离线状态下可用。

3. **User Confirmation Before Formal Data**
   OCR、视觉识别和 AI 只生成建议，不直接写入正式数据。

4. **Unknown Is Valid**
   日期、金额、位置和来源可以未知或估算，不得以默认值伪造精确事实。

5. **History Is Not a Mutable Field**
   位置、状态、维修、借出和成本通过事件保留过程；Item 只保存可重建的当前快照。

6. **Fast Path and Complete Path Are Separate**
   基础建档唯一必填字段是名称，高级字段按需展开。

7. **Model Complexity Must Be Hidden**
   底层可以严谨，前台语言必须符合家庭生活习惯。

8. **No Premature Universal Framework**
   为未来留清晰边界，但不提前构建复杂自动化、同步或企业级抽象。

9. **Data Autonomy**
   用户应能备份、导出和迁移；不得通过订阅锁定数据。

10. **Privacy at Egress, Fidelity at Rest**
    本地导入尽量忠实保留原始数据；对外分享默认应用隐私清理策略。

11. **Evidence Before Advice**
    洞察和购买建议必须引用用户自己的使用、成本、闲置和心得证据。

12. **Daily Driver over Demo**
    真实可用、可靠和低负担优先于展示性功能。
