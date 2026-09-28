# Validation evidence

## Preflight — 2026-09-28

All seven SHA256SUMS entries pass. README, GOAL, VALIDATION_CONTRACT and ARCHITECTURE_CONTEXT v1.2 read completely. Local fixed baseline exists; authenticated remote main is the same SHA. No prior Program worktree, branch, artifacts or PR found. Original worktree remains on `fix/testflight-round1-device-quality` at `dd3fc5940dc7c8bc87faa5e62bdbd89f348d80d3`; its two existing catalog edits are protected by local hashes.

Xcode 26.6 (17F113), Swift 6.3.3, Intel host, iOS 26.5 Simulator available. iOS 17 runtime absent. No available physical device. No approved Development container/signing configuration supplied. No live service calls made. SSH authentication failed; existing gh HTTPS authentication read remote successfully. No credentials copied or configuration changed. Existing CI is opt-in; repository variables unchanged.

Runtime evidence belongs in ignored `Prototypes/FoundationValidation/LocalEvidence/`; public summaries must omit private paths, device identity, account and Photos identifiers.

## Initial real local chain — LOCAL_PLATFORM (macOS, SwiftData/ImageIO)

- `swift build`: PASS. Initial build log: `LocalEvidence/initial-build.log`.
- `hhos-validation legacy LocalEvidence/legacy-v1`, process exits; then `migrate ... LocalEvidence/candidate-v2`, then separate `verify`: PASS. Baseline source copies are byte identical, fingerprinted in `LegacySourceManifest.json`. Fixture has 2 Items, 1 surviving Draft, 3 media byte fixtures, system/custom/unknown categories, archived Item, location, cover and deleted Draft. Media here are opaque byte fixtures; image behavior uses real JPEG in LocalChainTests. Source directory remains retained.
- `swift test --filter SchemaTests`: 1/1 PASS, disk-backed business/profile/outbox commit and reopen.
- `swift test --filter LocalChainTests`: initial 2/3; preview test incorrectly rejected ImageIO-generated structural EXIF. Added source timestamp/comment fixture and assertions excluding source privacy metadata while allowing only dimension/color fields. Affected rerun: 3/3 PASS (`LocalEvidence/local-chain-tests-fixed.log`). Covers actual JPEG, orientation-normalized preview, GPS/source EXIF removal, unchanged original, reopen/confirm idempotency, stable profile/media IDs, original/preview write interruptions, pre-save rollback, post-save/finalize/cleanup recovery.

These are partial G1/G2/G6 evidence, not completed gates, iOS evidence, or live-service PASS. Journal faults are injection, not yet OS process termination or real disk-full.

## SDK reading

Installed iOS 26.6 CloudKit Swift interface supports CKSyncEngine on iOS 17. FetchChangesOptions has scope and operationGroup but no desiredKeys; direct CKDatabase records fetch supports desiredKeys. Asset scheduling must be validated with a controlled media zone or narrow direct fetch. [Apple delegate ordering](https://developer.apple.com/documentation/cloudkit/cksyncenginedelegate-1q7g8) prohibits reentrant send/fetch from handleEvent. [Encrypted values](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues) cannot be indexed and are for new fields; service round-trip remains pending.
