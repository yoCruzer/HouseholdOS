# HouseholdOS

HouseholdOS 是一款本地优先、以拍照录入为主要入口的 iOS 家庭物品记录、查找、生命周期管理与使用复盘应用。

## 当前状态

仓库当前处于 **G0 — Governance Foundation / Owner Review** 阶段：

- 产品设计母本已冻结为 `HouseholdOS Product Design Book v1.0`。
- Foundation、Planning 与 Operations 文档已建立。
- 尚未创建 Xcode 工程。
- 尚未开始任何 Swift 业务实现。
- 当前唯一获批任务见 `Docs/Operations/CURRENT_TASK.md`。

## 文档入口

建议阅读顺序：

1. `AGENTS.md`
2. `Docs/Operations/CURRENT_STATE.md`
3. `Docs/Operations/CURRENT_TASK.md`
4. `Docs/Foundation/V1_SCOPE.md`
5. 当前任务引用的其他 Foundation Documents

完整产品设计母本：

- `Docs/Product/HouseholdOS_Product_Design_Book_v1.0.md`

## 文档分层

- `Docs/Product/`：面向 Owner 的完整产品设计母本。
- `Docs/Foundation/`：稳定的产品、领域、架构与隐私事实。
- `Docs/Planning/`：实现路线、Stage 定义、测试策略。
- `Docs/Operations/`：当前状态、当前任务、决策和已知限制。

## 开发原则

- Local-first。
- Capture First, Enrich Later。
- 阶段内自治，阶段间 Owner Gate。
- 不直接在 `main` 上开发。
- 不把未来能力提前塞入 V1。
- 测试、构建和文档状态必须一起更新。

## Repository SSOT 优先级

发生冲突时：

1. `Docs/Operations/CURRENT_TASK.md`：当前任务范围与禁止边界。
2. `Docs/Operations/CURRENT_STATE.md`：仓库当前真实状态。
3. `Docs/Foundation/`：已冻结产品和技术规则。
4. `Docs/Product/HouseholdOS_Product_Design_Book_v1.0.md`：产品设计母本。
5. `Docs/Planning/`：路线建议。
6. 代码注释、PR 描述与聊天内容。

任何下层内容不得静默覆盖上层事实。
