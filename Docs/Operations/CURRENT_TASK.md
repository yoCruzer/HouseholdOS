# Current Task

## Identity

- Stage: F0
- Title: Repository & Xcode Foundation
- Status: ACCEPTED
- Lifecycle: CLOSED
- Intended branch: `chore/f0-repository-xcode-foundation`
- Actual branch: `chore/f0-repository-xcode-foundation`
- Base branch: `main`
- Owner approval reference: `Codex Execution Prompt — HouseholdOS F0 Repository & Xcode Foundation`

## Execution Record

- Starting branch: `main`
- Starting HEAD: `2f3dd1ba1241470a8dac0eb939f39eee5af1e2b2`
- Actual base HEAD: `2f3dd1ba1241470a8dac0eb939f39eee5af1e2b2`
- Working branch: `chore/f0-repository-xcode-foundation`
- Activation commit: `85fc499c11965271ee0d86eb8c985335ca2177fc`
- Implementation commit: `00883987b7baffd2b46ed5dcde694610a9083709`
- Approved PR head: `703890ddda2be35dae03cb67b981511e476275fd`
- Merge commit: `8844aab9deb9e10d46ed8ffba072874430715b07`
- Merged PR: [#2](https://github.com/yoCruzer/HouseholdOS/pull/2)
- Merge method: merge commit
- Acceptance record commit: this commit (`docs: record F0 owner acceptance`)
- Final main HEAD: the acceptance record commit at the `main` branch tip; exact SHA is recorded in the final closure report
- F1 status: NOT DEFINED / NOT APPROVED / NOT STARTED

## Closure

- Owner decision: APPROVED
- F0 result: accepted and closed
- PR #2 was marked Ready only after the approved head and review state were reverified.
- PR #2 was merged with a normal merge commit.
- Auto-merge, squash, rebase and remote branch deletion were not used.
- Current approved implementation Stage: none
- F1: NOT DEFINED / NOT APPROVED / NOT STARTED

## Verification Results

- Environment: PASS — Xcode 26.5, Swift 6.3.2 and iOS 26.5 Simulator runtime verified.
- Project inspection: PASS — approved App target, Unit Test target and shared scheme discovered.
- Effective settings: PASS — iOS 17.0, Swift 6.0, device family 1 and temporary Bundle Identifier confirmed.
- Clean build: PASS — `BUILD SUCCEEDED`, exit status 0.
- Full tests: PASS — `TEST SUCCEEDED`, 1 test, 0 failures, 0 skips, exit status 0.
- Focused test: PASS — `TEST SUCCEEDED`, 1 test, 0 failures, 0 skips, exit status 0.
- Simulator install: PASS after explicitly booting the selected device.
- Simulator launch: PASS — PID returned and remained live after two seconds.
- Visual review: PASS — `HouseholdOS` and `Foundation ready` confirmed.
- Forbidden-scope scan: PASS.
- `git diff --check`: PASS.
- Unverified: real-device installation, paid signing, TestFlight and CI.
- F1: NOT STARTED / NOT APPROVED.

## Objective

在不实现任何业务模型、持久化或产品功能的前提下，建立一个可以在本机稳定构建、运行最小测试并由后续 Stage 继续演进的原生 iOS Xcode 工程基线。

F0 结束时必须新增以下可验证能力：

> HouseholdOS 已拥有明确的平台和工程配置、可编译的最小 SwiftUI App Target、可运行的 Unit Test Target、稳定 Scheme、实际环境记录和首个 build/test baseline。

## Technical Baseline

- Platform: Native iOS
- UI: SwiftUI
- Language: Swift
- Language mode: Swift 6
- Minimum deployment target: iOS 17.0
- Dependency policy: Apple native frameworks only
- Device family: iPhone (`TARGETED_DEVICE_FAMILY = 1`)
- Project: `HouseholdOSApp.xcodeproj`
- App Target: `HouseholdOSApp`
- Unit Test Target: `HouseholdOSAppTests`
- Shared Scheme: `HouseholdOSApp`
- Product / Display Name: `HouseholdOS`
- Temporary Bundle Identifier: `com.yocruzer.householdos.dev`

## Included Scope

1. Add `Docs/Operations/ENGINEERING_GOVERNANCE_SNAPSHOT.md` from the Owner-approved Governance Snapshot v0.1.
2. Activate F0 through this Stage Definition.
3. Create a native iOS `.xcodeproj` with the approved project, target and shared scheme names.
4. Establish the minimal architecture-aligned directory structure.
5. Add a minimal SwiftUI app lifecycle and Foundation placeholder view.
6. Add an XCTest Unit Test Target with one deterministic module smoke test.
7. Validate project discovery and actual build settings.
8. Build, run unit tests, install and launch on an available iPhone Simulator.
9. Scan for prohibited F0 scope.
10. Record the actual environment and validation baseline in repository documentation.
11. Create clear commits, push the F0 branch and open a Draft PR to `main`.

## Explicit Non-goals

- SwiftData, `ModelContainer`, Schema or migrations.
- Repository or Domain Entity definitions.
- Item, CaptureDraft, WishItem, Household, Member or LocationNode.
- Acquisition, LifecycleEvent, CostEvent, UsageRecord, MaintenanceRecord or ExperienceNote.
- Camera, Photo Library, media storage, drafts, search, export or backup.
- OCR, AI, CloudKit, iCloud or household sharing.
- App Group, Push Notifications, App Intents, Widget, Share Extension or Spotlight.
- Third-party dependencies, GitHub Actions, TestFlight or release configuration.
- Real-device signing or a formal Apple Development Team.
- Formal App Icon, branding or Design System.
- F1 or any later Stage implementation.
- Marking the Draft PR Ready, enabling auto-merge or merging the PR.

## Referenced SSOT

- `AGENTS.md`
- `Docs/Operations/ENGINEERING_GOVERNANCE_SNAPSHOT.md`
- `Docs/Operations/CURRENT_STATE.md`
- `Docs/Foundation/ARCHITECTURE.md`
- `Docs/Foundation/V1_SCOPE.md`
- `Docs/Foundation/PRODUCT_BOUNDARY.md`
- `Docs/Planning/IMPLEMENTATION_PLAN.md`
- `Docs/Planning/STAGE_DEFINITIONS.md`
- `Docs/Planning/TEST_STRATEGY.md`
- `Docs/Operations/DECISION_LOG.md`
- `Docs/Operations/KNOWN_LIMITATIONS.md`

## Acceptance Criteria

1. The F0 branch was created from the verified latest `main`.
2. Governance Snapshot v0.1 is present in the repository.
3. `CURRENT_TASK.md` correctly activates F0.
4. Native `HouseholdOSApp.xcodeproj` exists.
5. `HouseholdOSApp` App Target exists.
6. `HouseholdOSAppTests` Unit Test Target exists.
7. A discoverable Shared Scheme exists and includes the test target.
8. Deployment target, Swift version, device family and temporary Bundle Identifier match the approved baseline.
9. The minimal SwiftUI app builds successfully.
10. The Unit Test actually runs and passes.
11. Simulator install and launch smoke succeeds.
12. No SwiftData, business models, CloudKit, third-party dependencies or later-Stage features are present.
13. `CURRENT_STATE.md` records the real environment and verification baseline.
14. Final status is `AWAITING_OWNER_REVIEW`.
15. `git diff --check` passes.
16. Commits are scoped and auditable.
17. The F0 branch is pushed.
18. A Draft PR targeting `main` is created.
19. The final worktree is clean.
20. The PR is not merged and F1 is not started.

## Required Verification

### Environment

- `xcode-select -p`
- `xcodebuild -version`
- `xcrun swift --version`
- `xcodebuild -showsdks`
- `xcrun simctl list runtimes`
- `xcrun simctl list devices available`

### Project Inspection

- `xcodebuild -list -project HouseholdOSApp.xcodeproj`
- `xcodebuild -project HouseholdOSApp.xcodeproj -scheme HouseholdOSApp -showdestinations`
- `xcodebuild -project HouseholdOSApp.xcodeproj -scheme HouseholdOSApp -showBuildSettings`

### Build and Tests

- Use an actual available iPhone Simulator destination.
- Write Derived Data outside the repository.
- Run a clean App build and require `BUILD SUCCEEDED`.
- Run the XCTest suite and require `TEST SUCCEEDED`.
- Report actual tests, failures, skips, destination, runtime and exit status.

### Simulator Launch

- Install the built app using `simctl`.
- Launch the app using `simctl`.
- Report build, test, install, launch and visual inspection separately.

### Repository Checks

- Scan for SwiftData, CoreData, CloudKit, third-party packages, entitlements, protected-resource usage descriptions, GitHub Actions, business entities and Repository definitions.
- `git diff --check`
- `git status --short`
- `git diff --stat`
- `git diff --name-status`
- `git log --oneline --decorate -5`
- Require an empty final `git status --short`.

## Documentation Updates

- Update `Docs/Operations/CURRENT_STATE.md` with only verified repository, environment and validation facts.
- Finish this file at `Status: AWAITING_OWNER_REVIEW` and `Lifecycle: OPEN`.
- Append `D-009 — Native iOS Xcode Foundation` and `D-010 — Temporary Development Identifier` only if environment validation supports them.
- Update `Docs/Operations/KNOWN_LIMITATIONS.md` with confirmed limitations only.
- Minimally update `README.md` with open, scheme, deployment target, build/test commands and F0 boundary.

## Git Authorization

Allowed:

- Fetch and safely fast-forward local `main`.
- Create and switch to `chore/f0-repository-xcode-foundation`.
- Modify files within F0 scope.
- Create scoped commits.
- Push the F0 branch.
- Create a Draft PR targeting `main`.

Not allowed:

- Direct development on `main`.
- Force push, rebase or shared-history rewriting.
- Delete remote branches.
- Mark the PR Ready, merge it or enable auto-merge.
- Create a release or tag.
- Modify the repository license.
- Start F1.

## Stop Conditions

Stop if:

1. The worktree contains changes of unknown ownership.
2. Remote `main` contains unknown product implementation or another active Stage.
3. The installed Xcode cannot support iOS 17.0.
4. The Swift toolchain cannot support Swift 6.
5. No iPhone Simulator runtime can run the Unit Test.
6. A native Xcode project requires a third-party generator.
7. Build or tests fail and cannot be reliably fixed inside F0.
8. A real Apple Developer Team, formal Bundle Identifier or entitlements become necessary.
9. SwiftData or business models become necessary.
10. Foundation Documents conflict with the Owner-approved F0 Prompt.
11. A destructive Git operation becomes necessary.
12. Actual build or test execution cannot be confirmed.

## Completion Report

Report:

1. Stage result and recommendation.
2. Starting and ending branch, HEAD, ahead/behind and worktree state.
3. Environment and actual Simulator destination.
4. Project configuration.
5. Completed scope.
6. Explicitly unimplemented and prohibited scope.
7. All changed files.
8. Project inspection, build, test, Simulator and repository-check results.
9. Documentation updates.
10. Commits, push and Draft PR details.
11. Every Acceptance Criterion as PASS or FAIL.
12. Confirmed limitations.
13. Deviations and decisions.
14. F1 status and recommended next action.
