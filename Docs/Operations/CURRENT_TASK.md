# Current Task

## Identity

- Goal context: Goal 1 remains `ACCEPTED / CLOSED`
- Title: TestFlight Round 1 Closure & Canonical Baseline
- Task status: ACCEPTED / CLOSED
- Lifecycle: CLOSED
- Readiness base branch: `chore/testflight-readiness-goal1`
- Readiness base HEAD: `79879e969fc5e702b852495c1cb3905d4fde8e0d`
- Working branch: `fix/testflight-round1-device-quality`
- Pull request base/head: `main` <- `fix/testflight-round1-device-quality`
- Goal 2: NOT STARTED
- Foundation Architecture Validation Program: NOT STARTED
- Owner authorization: `HouseholdOS — TestFlight Round 1 Closure & Canonical Baseline`

## Starting Baseline

- Repository: `yoCruzer/HouseholdOS`
- Starting branch: `chore/testflight-readiness-goal1`
- Starting local HEAD: `79879e969fc5e702b852495c1cb3905d4fde8e0d`
- Starting remote HEAD: `79879e969fc5e702b852495c1cb3905d4fde8e0d`
- Remote alignment after fetch: aligned
- Starting worktree: modified `HouseholdOSApp.xcodeproj/project.pbxproj`
- Owner confirmation: the pre-existing Xcode project changes are intentional and must be preserved in this stabilization branch
- Preserved Owner changes: Apple Development Team `83SKX2PM7B`, Lifestyle App Store category, and Xcode-normalized project reference comments

## Goal Statement

把已经存在的 Goal 1 主流程从“功能基本存在”提升到下一轮 iPhone 真机测试前可稳定日常使用的 readiness candidate。本轮只收稳设备适配、英文与简体中文、本地持久化、拍照、照片查看与删除、保存反馈以及基础工程质量。

## Included Scope

1. 修复现代 iPhone launch/full-screen 配置并在两个尺寸等级的 Simulator 验证。
2. 建立 `en` 与 `zh-Hans` String Catalog 本地化基础，包括相机权限说明。
3. 使用稳定系统分类 UUID 提供本地化显示名，不改写已有持久化分类名。
4. 增加使用原始文件的照片查看器，以及独立、明确、有确认的删除入口。
5. 为 Draft 与 Item Save 提供由真实 persistence outcome 驱动的非阻塞成功反馈。
6. 建立 capture-result one-shot boundary，防止重复 callback 产生重复 Draft 或媒体。
7. 保证相机文件 bytes、扩展名与 UTI 一致，并收稳 preview/final geometry 与方向。
8. 增加 Draft、Item、照片删除和 UI terminate/reopen 持久化回归。
9. 增加 English 与 Simplified Chinese localization smoke tests。
10. 增加可手动触发、可选自动启用的 GitHub Actions Simulator CI，并使最终 candidate CI GREEN。

## Explicit Non-goals

- Goal 2 或 Goal 3。
- 连续拍摄、batch capture、OCR、AI、自动分类。
- Household Member、账号、iCloud、CloudKit、同步或新后端。
- 生命周期、成本、统计或大型 UI redesign。
- 第三方 SDK 或 Swift package。
- 重写 SwiftData schema、`ItemLibraryService` 或 `MediaFileStore`。
- TestFlight upload 或 App Store Connect 操作。

## Acceptance Criteria

### Device presentation

- Debug 与 Release built product 有有效 launch-screen declaration。
- 接近 iPhone 16 与 iPhone 17 Pro Max 的 Simulator 全屏运行，无 compatibility black bars。
- Root `TabView`、`NavigationStack` 与 safe area 无裁切。

### Localization

- `Localizable.xcstrings` 和 `InfoPlist.xcstrings` 覆盖 Goal 1 用户可见路径与相机权限说明。
- English locale 无中文、missing translation 或 localization key 泄漏。
- Simplified Chinese locale 核心界面完整中文。
- 系统分类身份和持久化英文 canonical name 不变；自定义分类名不翻译。

### Media and save behavior

- thumbnail 点击打开真实 original 的照片查看器，方向正确并适配屏幕。
- 删除照片使用独立 destructive action 和确认，复用 `ItemLibraryService.removeMedia`。
- 删除记录及文件维护语义在重启后保持正确。
- Draft 与 Item 显式 Save 只在 persistence 成功后显示成功；失败不显示成功。
- `savedButRefreshFailed` 同时显示保存成功状态和现有 reload/recovery banner。

### Capture correctness

- 同一个 logical capture completion 重复 delivery 时只接受一个结果。
- 一次拍摄最多生成一个 Draft 和一份预期媒体。
- camera/photo-library completion 尽量复用同一 one-shot primitive。
- 相机输出 bytes、文件扩展名和 content type 一致，orientation 正确。
- preview 与最终照片采用可解释的一致 geometry strategy，无明显 zoom/crop jump。

### Persistence and CI

- Draft + original media、confirmed Item + original media、photo deletion 均通过 disk-backed reopen regression。
- 至少一条 UI test 覆盖 Draft 保存、terminate、reopen。
- English 与 zh-Hans UI smoke tests 通过且导航不依赖单一语言文本。
- GitHub Actions 支持 `workflow_dispatch`；自动 push/PR CI 仅在 `HOUSEHOLDOS_AUTO_CI == true` 时分配 macOS runner。
- 最终 workflow 实际运行并 GREEN。

## Required Verification

最终 candidate 必须执行并记录：

1. `git diff --check`
2. Round 1 focused tests
3. existing Goal1Core tests
4. full unit tests
5. full UI tests
6. clean Debug Simulator build
7. Release Simulator build
8. English localization smoke
9. zh-Hans localization smoke
10. 两个现代 iPhone 尺寸等级的 install/launch/screenshot inspection
11. Debug 与 Release generated Info.plist launch-screen verification
12. `git status --short` 与 local/remote alignment
13. GitHub Actions latest run GREEN

真机 camera、permission、preview/final agreement、orientation、one physical shutter 和真实照片重启恢复只能标记 `DEVICE TEST PENDING`，不得由 Simulator 或自动测试替代。

## Execution Plan

1. 激活稳定化事实源并审计现有实现、built Info.plist 和本地化缺口。
2. 实现 launch 与 localization foundation。
3. 实现照片查看/删除和真实 save success feedback。
4. 实现 one-shot capture boundary、相机格式正确性与一致 preview geometry。
5. 增加 disk-backed persistence、duplicate delivery、format 和 localization/UI tests。
6. 增加 GitHub Actions，执行本地完整 gate 与双尺寸 Simulator 验证。
7. 更新状态文档，形成可审计 commits，推送、创建 Draft PR 并使 CI GREEN。

## Stop Conditions

沿用 `AGENTS.md`。尤其在需要改变冻结核心语义、SwiftData schema、隐私/同步策略、引入第三方依赖、执行不可逆迁移、修改 Stage 外重要模块或无法排除数据完整性风险时停止。不得上传 TestFlight、开始 Foundation Architecture Validation Program 或开始 Goal 2。

## Completion Record

- Recovered interrupted work: yes; no reset, restore or stash was used.
- Preserved Owner project configuration: Team `83SKX2PM7B`, Lifestyle category and
  Xcode-normalized project reference comments.
- Implementation commits: `6d1986c` and `3bcffa8`.
- Focused Round 1 tests: 5 passed, 0 failed, 0 skipped.
- Goal1Core final evidence: the locale-sensitive failing subset passed 3/3 after
  replacing hard-coded English expectations; the full candidate run then passed all
  34 Goal1Core tests.
- Full suite run 1: 42 passed, 2 failed, 0 skipped; both failures were localized UI
  test interaction issues and were repaired with targeted evidence.
- Full suite run 2: 43 passed, 1 failed, 0 skipped; the only failure was duplicate
  wrapper/inner XCTest elements for one confirmation button. The query was corrected,
  and the remaining viewer/delete/relaunch test passed 1/1 in the final targeted run.
- English localization smoke: passed. Simplified Chinese localization smoke: passed.
- Clean Debug Simulator build: passed. Clean Release Simulator build: passed.
- Debug and Release built Info.plist: `UILaunchScreen` present.
- Exact iPhone 16 and iPhone 17 Pro Max Simulator clean-install/launch/layout smoke:
  passed on iOS 26.5; screenshots show full-screen content with normal safe areas.
- GitHub Actions: manual `workflow_dispatch`, `macos-26`, dynamic modern iPhone
  Simulator selection, Debug full tests and Release build; push/PR runner allocation
  remains gated by `HOUSEHOLDOS_AUTO_CI == 'true'`.
- Remote workflow conclusion is tracked in Draft PR checks and the final Stage report.
- Device acceptance remains pending for real camera permission/capture, true optical
  preview/final agreement, true orientation, one physical shutter-to-one-Draft and
  real-photo relaunch persistence.
- Independent-review closure remediation: Draft overlay suppression is derived from
  the live Photos/Camera/viewer presentation bindings; camera session configure,
  start and stop run on one serial execution boundary and the shutter becomes enabled
  only after `startRunning()` returns; CI checks the committed HEAD with
  `git show --check --oneline HEAD`.
- Picker-cancel autosave targeted regression: passed. Final local full suite: 45 passed,
  0 failed, 0 skipped. Clean Debug and Release Simulator builds: passed.
- ChatGPT closure review: `APPROVE`.
- TestFlight Round 1 Device Quality Stabilization: `ACCEPTED / CLOSED`.
- Reviewed production-code HEAD: `5d0c4c347f4069432d94459b1c3c204c748a68b6`.
- The closure commit changes operational documentation only and does not represent a
  separate product-code review.
- Manual GitHub Actions run `33572746681` was GREEN against reviewed production-code
  HEAD `5d0c4c347f4069432d94459b1c3c204c748a68b6`; opt-in PR runs may be intentionally skipped.
- Real camera permission/capture, optical preview/final agreement, real orientation,
  one physical shutter-to-one-Draft behavior and real-photo relaunch persistence are
  deferred to the consolidated later Device Validation Pack and are not marked PASS.
- Goal 2 and the Foundation Architecture Validation Program were not started. No
  TestFlight upload was performed.
