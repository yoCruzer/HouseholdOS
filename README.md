# HouseholdOS

HouseholdOS 是一款本地优先、以拍照录入为主要入口的 iOS 家庭物品记录、查找、生命周期管理与使用复盘应用。

## 当前状态

仓库当前处于 **F0 — Repository & Xcode Foundation / Owner Review** 阶段：

- 产品设计母本已冻结为 `HouseholdOS Product Design Book v1.0`。
- Foundation、Planning 与 Operations 文档已建立。
- 原生 iOS Xcode 工程、App Target、Unit Test Target 和 Shared Scheme 已建立。
- F0 的本地 build、test 和 Simulator launch baseline 已通过验证。
- 尚未开始任何 Swift 业务实现。
- 当前唯一获批任务见 `Docs/Operations/CURRENT_TASK.md`。

## 本地开发

使用 Xcode 打开：

```sh
open HouseholdOSApp.xcodeproj
```

当前 Shared Scheme 为 `HouseholdOSApp`，最低部署版本为 iOS 17.0。当前已验证命令使用 iPhone 17 Pro / iOS 26.5 Simulator：

```sh
xcodebuild -project HouseholdOSApp.xcodeproj -scheme HouseholdOSApp -configuration Debug -destination 'platform=iOS Simulator,id=4C8C76D9-41F0-4EB1-9881-836515666D9F' -derivedDataPath /private/tmp/HouseholdOS-F0-DerivedData clean build
xcodebuild -project HouseholdOSApp.xcodeproj -scheme HouseholdOSApp -configuration Debug -destination 'platform=iOS Simulator,id=4C8C76D9-41F0-4EB1-9881-836515666D9F' -derivedDataPath /private/tmp/HouseholdOS-F0-DerivedData test
```

F0 只建立工程和测试基线。持久化、业务模型和产品功能尚未实现，F1 也尚未批准。

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
