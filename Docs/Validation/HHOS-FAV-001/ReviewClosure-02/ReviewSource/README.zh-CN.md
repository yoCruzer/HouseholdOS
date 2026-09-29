# HouseholdOS PR #5 第二轮独立 Review

结论：REQUEST_CHANGES（2 项 P1，1 项 P2）；本地自动整改尚不能全部关闭。真实平台证据继续单列待验，不因此要求现在操作真机。

- 审查增量：`faae13d93a83694a77da3d962423de2193f0fe88` → `449328ea87b40f773c4dcfa957f3ae00bf43e7ef`
- 代码候选：`b45cb840c2e65ca25c062cde450c235a0195f670`
- 正式已接受基线：`f19469fe13be175d1b28d71ddb6b5a917abdcc32`
- 审查日期：2026-09-29
- 没有修改远端、提交 GitHub review、执行 merge/ready/Freeze 或触发 CI。

## 文件

- REVIEW.zh-CN.md：逐项发现、已修复项、风险和最小回归要求。
- ProbeTypes.swift / ExtractedMerge.swift / ExtractedSyncMethods.swift：用于逻辑探针的值类型与提取函数体。
- ProbeSupport.swift：明确标识的内存存储/CloudKit 记录替身。不是 SwiftData/CloudKit 本身。
- main.swift：反例和正向对照。
- run-probes.sh / probe-results.txt / toolchain.txt：实际执行命令、输出和工具版本。
- NativeFollowupTests.swift：供 Codex 纳入真实 ValidationCoreTests 的原生回归草案；本环境**未编译或运行**这个文件。
- SOURCE_MANIFEST.json / SHA256SUMS.txt：源码锚点与包内完整性校验。

## 证据强度

已实际执行的是 Linux 上的纯 Swift / 内存逻辑探针。apply、nextBatch、ThreeWayMerge 函数体取自所审 HEAD；宿主类型、commit/rollback、CloudKit 记录序列化等用显式替身。

因此输出证明的是所列已确定状态下的分支/队列逻辑，不证明 Apple 框架持久性、真正 change tag、服务回调时序、崩溃恢复或 UI。没有把 Codex 报告的 65/65 当作本次新执行结果。

R2-03 的探针对成功 ACK 仅模拟“移除被 ACK 的精确 operation”，原生回归草案才会调用真正的 acknowledge。全部探针 fixture 都是已知、合法格式；writable 返回 true 的替身不用于未来字段测试。

运行 `./run-probes.sh` 可复现逻辑输出；不需要联网/账号/签名，不接触任何用户库。

本包是只读 Review 产物，不自动授予新的远端修改、真实设备/云操作或合并权限。
