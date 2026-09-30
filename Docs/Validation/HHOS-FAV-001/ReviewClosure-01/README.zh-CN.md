# HouseholdOS PR #5 — 集中整改执行包 v1.0

Program：`HHOS-FAV-001`；本轮任务：`PR5-IR-Closure-01`。

这是既有 Foundation Validation v1.2 的**有限整改补充授权**，不是重新启动 Program，不是 Foundation v1.3，也不是正式产品实现。

## 使用

上传本 ZIP 后发送 `SHORT_START_PROMPT.txt`。只需这一份 ZIP；已包含前次独立 Review 和探针原始资料，不需再上传旧 Review 包。既有 v1.2 合同从仓库读取。

执行时完整读取：
1. `GOAL.md`：范围、权限、顺序、测试与交付。
2. `REMEDIATION_CONTRACT.md`：IR-01～IR-05、E-01/E-02 的修复与验收。
3. `ReviewSource/REVIEW.zh-CN.md`：此前独立 Review 的背景、源码定位与证据边界。

先检查 `SHA256SUMS.txt`。探针和结果只是历史诊断证据，不是新的 SwiftData/Xcode/CloudKit 验证结果；不能用它们代替本轮原生回归。

## 不变的边界

- 仓库：`yoCruzer/HouseholdOS`。
- 已接受 main 基线：`f19469fe13be175d1b28d71ddb6b5a917abdcc32`。
- 本轮已审 PR HEAD：`faae13d93a83694a77da3d962423de2193f0fe88`。
- 继续分支 `spike/foundation-validation` 和 **Draft PR #5**。
- 不修改正式 App，不合并、不 mark ready、不 Freeze、不发 TestFlight。
- 本轮不运行真实云/Photos/设备试验，不要求 Owner 配置账号/设备；外部补证保留待验。
- 尊重用户已选模型/推理档位，不自动改计费、权限或模型配置。

## 这轮要交付什么

五项代码发现得到实证处置，两条最小链路补齐，受影响的最终证据与代码匹配，普通 push 更新同一个 Draft PR，然后停在独立复核。

`LOCAL_REMEDIATION_COMPLETE` **不等于**全部 Program 验收完成、正式产品可发布或可以抹除旧设备。

本 ZIP 是执行指令，不是已经修好的源码。打包校验不代表代码修复或原生测试已经执行。
