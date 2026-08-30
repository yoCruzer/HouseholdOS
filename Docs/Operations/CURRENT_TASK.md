# Current Task

## Identity

- Goal: Goal 1
- Title: 建立可持续扩展的家庭物品库核心
- Status: ACCEPTED / CLOSED
- Lifecycle: GOAL_1_CLOSED
- Review round: FIFTH_OWNER_REVIEW — APPROVE
- Final branch: `goal/v1-household-library-core`
- Base branch: `main`
- Starting HEAD: `581f970451033a0efd702202eb2845ed2a264360`
- Owner approval reference: `Goal 1 Closure + TestFlight Readiness Preparation`

## Authorization

Owner 已在 Fifth Owner Review 对 approved HEAD
`d2e513804b7e9e2306a5f0aa7041b3b5eb7c3992` 给出 `APPROVE`，并明确授权将 PR #3
标记 Ready 后使用 merge commit 合并到 `main`。该授权仅关闭 Goal 1；Goal 2 不得开始。

允许：

- 核验 PR #3 approved HEAD 和可合并状态；
- 将 PR #3 标记 Ready；
- 使用 merge commit 合并 PR #3；
- 记录 Goal 1 acceptance 和 closure。

不允许：

- 删除远程分支；
- 开始 Goal 2 或 Goal 3；
- 改变 V1 三个 Goal 的产品定义；
- 引入第三方服务、远程 AI、自建后端或账号体系。

## Starting Baseline

- Starting branch: `main`
- Starting HEAD: `581f970451033a0efd702202eb2845ed2a264360`
- `origin/main`: `581f970451033a0efd702202eb2845ed2a264360`
- Ahead / behind at start: `0 / 0`
- Starting worktree: clean
- Remote conflict check: only merged historical G0 and F0 branches; no active product branch
- Project: `HouseholdOSApp.xcodeproj`
- Scheme: `HouseholdOSApp`
- App target: `HouseholdOSApp`
- Unit test target: `HouseholdOSAppTests`
- Minimum deployment target: iOS 17.0
- Swift language mode: 6.0
- Target device family: iPhone
- Third-party dependencies: none

## Environment Reverification

- Date: 2026-07-28
- macOS: 26.5.2 (`25F84`)
- Host architecture: `x86_64`
- Xcode: 26.6 (`17F113`)
- Swift: 6.3.3
- Installed iOS Simulator runtime: iOS 26.5 (`23F77`)
- Selected Simulator: iPhone 17 Pro
- Selected destination ID: `4C8C76D9-41F0-4EB1-9881-836515666D9F`
- F0 clean build: PASS
- F0 full test suite: PASS — 1 test, 0 failures, 0 skips

## Goal Statement

让用户能够真实地录入、保存、查找和维护家里的物品，并建立 Goal 2 与 Goal 3
可以继续演进的核心产品基础。

完成后应形成：

```text
拍摄或创建一件家庭物品
        ↓
信息不完整时保存为草稿
        ↓
稍后继续补充和编辑
        ↓
确认进入正式物品库
        ↓
通过列表、分类或搜索重新找到
        ↓
查看、编辑、归档或删除
        ↓
App 重启后数据仍然存在
```

## V1 Continuity Analysis

### Stable Item Identity

Goal 1 使用稳定 UUID 作为正式 Item 身份。Goal 3 的购买、维修、体验和生命周期
记录将通过该身份关联，不复制 Item，也不把未来字段提前塞入 Item。

### Draft to Item

单件和未来批量录入共享同一 `CaptureDraft` 语义和确认操作。确认以 Draft ID
为幂等边界，在同一持久化保存中创建 Item、转移媒体所有权并清理 Draft；正式写入
失败时必须保留可重试草稿。

### Media Ownership

媒体文件与结构化记录分离。每个媒体记录只有一个明确 owner（Draft 或 Item），
确认时只转移 owner，不复制或重编码原始文件。Goal 2 的连续拍摄直接创建多个现有
Draft 和 Media，不建立第二套 Batch Media。

### Capture Path

相机、照片选择和手工入口最终都进入相同 Draft 创建、编辑和确认路径。Goal 2
只需在该路径前增加 Capture Session 与连续创建能力。

### Location Evolution

Goal 1 使用稳定 Location 身份和可选 location ID，不把位置散落为任意字符串。
Goal 2 可在保留现有 Location ID 和数据的前提下增加父子关系、类型和批量继承。

### Household Context

Goal 1 的 Item、Draft 和 Location 保存稳定 household ID，但不提前实现成员、
权限或共享。Goal 2 可增加本地 Household Member 与归属关系。

### Goal 3 Facts

Goal 1 不实现购买、维修、体验或生命周期历史；这些后续事实以 Item ID 关联。
Item 只保存 Goal 1 必要快照，避免未来整体重建。

### Export and Migration

采用版本化 SwiftData Schema，媒体使用稳定相对文件名。Goal 2/3 可通过轻量迁移
增加字段和关系；完整导出延后，但当前边界不会要求清空数据库。

### UI Coupling

创建、更新、确认、归档、删除、搜索和媒体清理集中在可测试的应用服务与数据边界，
不由单个 SwiftUI View 独占。

## Included Scope

1. 版本化 SwiftData 本地持久化和内存测试容器。
2. 最小 Item、CaptureDraft、MediaAsset、Category 和 Location 模型。
3. Item 与 Draft 的 CRUD、时间戳和数据完整性规则。
4. 幂等且避免半完成正式状态的 Draft -> Item 确认。
5. 原始图片文件保存、缩略图、owner 转移和可恢复清理。
6. 系统照片选择器、可用设备上的相机入口和手工录入。
7. 单件草稿创建、保存、继续编辑、删除和确认。
8. 草稿箱列表、详情、空状态和正式数据区分。
9. 正式物品列表、详情、编辑、归档和永久删除。
10. 文本搜索、分类浏览、最近添加和基础排序。
11. 最小 Location 实体、创建与选择。
12. 启动恢复、Simulator 主流程和关键数据操作验证。

## Explicit Non-goals

- 连续拍摄、多件 Capture Session、批量草稿或批量编辑。
- 完整房间、柜体、抽屉、容器层级和 Spaces 浏览。
- Household Member UI、账号、权限、CloudKit 或跨 Apple ID 共享。
- OCR、AI 识别、AI 分类或任何第三方远程服务。
- 购买、成本、维修、保修、使用体验和生命周期历史。
- 洞察 Dashboard、完整导出、备份和恢复 UI。
- App Store、TestFlight、正式签名、品牌和发布准备。
- 通用事件溯源、插件系统或大型未来抽象。

## Implementation Plan

1. 激活 Goal 1 状态并记录连续性边界。
2. 建立版本化持久化、核心模型、媒体存储和应用服务。
3. 先用自动测试锁定 CRUD、确认、失败边界、搜索和清理语义。
4. 建立照片/相机/手工录入、草稿箱、物品库与编辑导航。
5. 执行聚焦测试、全量测试、clean build、Release build 和 Simulator 主流程。
6. 更新事实文档，创建范围清晰 commits，推送并创建 PR。

## Acceptance Criteria

### User

1. 可以创建物品或从图片开始录入。
2. 可以为记录添加至少一张图片。
3. 信息不完整时可以保存草稿。
4. 可以重新打开并编辑草稿。
5. 可以将有效草稿确认为正式物品。
6. 可以在物品库查看正式物品。
7. 可以通过搜索或分类重新找到物品。
8. 可以编辑正式物品。
9. 可以归档或永久删除物品。
10. App 重启后仍能读取已保存数据。
11. 图片缺失、相机不可用或权限拒绝时仍可手工继续。

### Engineering

1. Item 和 Draft CRUD 有自动化测试。
2. Draft 确认、幂等和无效输入边界有自动化测试。
3. 持久化重开读取有自动化测试。
4. 搜索、分类和排序核心逻辑有自动化测试。
5. Media owner 转移、删除和孤儿清理语义有自动化测试。
6. 时间戳、归档和数据完整性约束有自动化测试。
7. clean Debug build 通过。
8. 完整测试通过。
9. Release 配置基础构建通过。
10. Simulator 安装、启动和主要流程验证通过。
11. `git diff --check` 通过，最终工作区清晰。
12. 状态文档与代码一致。

### Continuity

1. Goal 2 复用同一 Draft、Media 和确认路径。
2. Goal 2 不需要清空数据库或创建平行 Item/Draft/Media。
3. Location 能通过迁移增加层级和批量上下文。
4. Goal 3 能围绕稳定 Item ID 增加长期事实。
5. 核心业务逻辑与 UI 解耦。

## Required Verification

使用 iPhone 17 Pro / iOS 26.5 Simulator，Derived Data 写入仓库外：

```sh
xcodebuild -project HouseholdOSApp.xcodeproj -scheme HouseholdOSApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=4C8C76D9-41F0-4EB1-9881-836515666D9F' \
  -derivedDataPath /private/tmp/HouseholdOS-Goal1-DerivedData clean build

xcodebuild -project HouseholdOSApp.xcodeproj -scheme HouseholdOSApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=4C8C76D9-41F0-4EB1-9881-836515666D9F' \
  -derivedDataPath /private/tmp/HouseholdOS-Goal1-DerivedData test
```

另需执行：

- 聚焦核心服务和持久化测试；
- Release Simulator build；
- App 安装、启动和截图检查；
- 草稿、确认、搜索、编辑、归档/删除和重启恢复手工检查；
- `git diff --check`；
- `git status --short`；
- remote/ahead/behind 核验。

## Completion Evidence

- Goal activation commit: `9627268`
- Persistence and service core commit: `6ea3852`
- User flows and UI regression commit: `7f45a0d`
- First Owner Review result: REQUEST_CHANGES
- Second Owner Review result: REQUEST_CHANGES
- Third Owner Review result: REQUEST_CHANGES
- Closure Design Audit result: APPROVED_WITH_AMENDMENTS
- Fourth Owner Review result: REQUEST_CHANGES
- Fifth Owner Review result: APPROVE
- Approved PR HEAD: `d2e513804b7e9e2306a5f0aa7041b3b5eb7c3992`
- PR #3 state at merge: Ready, clean and mergeable
- PR #3 merge method: merge commit
- PR #3 merge commit: `0bf55833beb55cf96d00ecbe8db4c76c929cff22`
- Immutable display overlay/tombstones and explicit write outcomes: COMPLETE
- Persistent Reload banner and Root FIFO transient notice queue: COMPLETE
- Resolve-before-mutate media transaction boundary: COMPLETE
- Focused media transaction T1–T5 tests: PASS — 5 tests, 0 failures, 0 skips
- Focused Goal1Core tests: PASS — 29 tests, 0 failures, 0 skips
- Full suite: PASS — 36 tests (29 core and 7 UI), 0 failures, 0 skips
- FIFO transient-notice ordering: unit tested
- Combined recovery and deletion-notice coexistence: UI tested
- End-to-end UI journey: PASS — capture fallback, draft save/relaunch,
  confirmation, search, editor Close/Save semantics, edit/relaunch, archive exclusion
  and archived inclusion
- clean Debug Simulator build: PASS
- clean Release Simulator build: PASS
- Simulator install and launch: PASS — PID `53499`
- Final screenshot inspection: PASS — Items empty state, search, filters, add and
  three-tab navigation rendered without startup error
- 4032 × 3024 image validation: PASS — two imports, unique files, thumbnails,
  owner/order integrity and non-main-thread media operations
- Persistence failure validation: PASS — preflight isolation, unrelated-save checks,
  save rollback/file cleanup, committed save with refresh failure, reopen recovery and
  idempotent confirmation
- Media maintenance validation: PASS — per-file failure isolation, `.incoming-*`
  cleanup, prepared-file reservation, startup availability and later retry
- `git diff --check`: PASS before completion documentation
- Third-party dependencies, CloudKit, account, remote service and Goal 2 scope: none

## Review State

PR #3 passed Fifth Owner Review with `APPROVE`. Immediately before merge, GitHub
reported the approved HEAD unchanged, Ready, clean and mergeable. PR #3 was merged to
`main` using merge commit `0bf55833beb55cf96d00ecbe8db4c76c929cff22`.
Goal 1 is accepted and closed. Goal 2 remains not started.

## Stop Conditions

除 Owner Prompt 已明确解决的 Goal 驱动授权外，沿用 `AGENTS.md` 和 Goal Prompt
中的停止条件。尤其在需要改变冻结核心语义、不可逆迁移、外部服务、隐私策略变化、
未知工作区修改或无法排除的数据完整性风险时停止。

## Completion Updates

Goal 1 completion updates are complete:

- `Docs/Operations/CURRENT_STATE.md` records `ACCEPTED / CLOSED`;
- D-011 through D-016 are accepted;
- PR #3 merge commit is recorded;
- Goal 2 remains explicitly not started.
