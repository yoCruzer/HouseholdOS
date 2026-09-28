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

## Shared protocol checkpoint — partial G3/G4/G5

- `swift build`: real CloudKit/PhotoKit adapters compile on macOS. No cloud connection or selected-photo API executed.
- `swift build --triple x86_64-apple-ios17.0-simulator --sdk <installed-iphonesimulator-sdk> --scratch-path LocalEvidence/ios-build --target ValidationCore`: PASS, log `LocalEvidence/ios-core-build.log`. This proves core/adapter iOS compile, not a built App or live service behavior.
- `swift test --filter SyncProtocolTests`: 5/5 PASS (`LocalEvidence/sync-protocol-tests.log`). Revision 7 ACK leaves revision 8 after disk reopen; in-flight identity survives; OFF epochs reject late ACK/state while preserving intents; account switch pauses; inbound has no echo and retains pending conflict durably; tombstone rejects stale upsert and permits explicit new intent. CKRecord encode/decode is shared with the actual delegate.
- Candidate schema grew with sync sidecars. Reused immutable baseline fixture, migrated full clone to `LocalEvidence/candidate-v2-sync`, separate-process verify PASS. Initial candidate-v2 directory remains retained with its previous experimental schema; it is not the final candidate.
- Affected `SchemaTests|LocalChainTests`: 4/4 PASS after schema expansion, log `LocalEvidence/schema-affected-tests.log`. Final full candidate suite has NOT run.
- Publication attempt was blocked by automatic approval review before execution. Requested user confirmation; no push or PR created, no alternate channel used.

Current code is an intermediate checkpoint. Local business outbox payloads still require wiring to the shared protocol; no end-to-end sync or completed contract gate is claimed. Remaining work is explicit in VALIDATION_STATE.json.

## Shared business chain, recovery and iOS App checkpoint

LocalChain now uses typed WireRecord documents and Draft/Media intents within the business transaction. Each new library has a distinct persisted identity. SharedChainTests uses a conditional transport fake only; native CKRecord codec, SwiftData outbox, reducer, projection and ACK logic are shared with CloudAdapter. Blank-client preview is actual image bytes; missing original is explicitly tested.

Focused evidence (not final full suite): `shared-chain-tests.log` 8/8; `shared-replication-tests.log` 8/8; `protocol-boundaries-tests.log` 13/13; `backup-restore-tests-fixed.log` 5/5; `photos-fallback-tests.log` 11/11. Counts overlap. Backup test source initially omitted two `try` annotations; fixed before execution. No runtime test was weakened.

Backup uses native sqlite3_backup while the synchronous MainActor fixture boundary freezes writes, then copies exact media and writes hash manifest/completion marker. Restore validates into an independent complete generation, clears device ACK/session state and leaves cloud admission paused. Pointer switch covers DB and media together. Original generations and package remain. Photos writes are absent by implementation; no PHAssetChangeRequest/performChanges path exists.

Independent App bundle `com.yocruzer.householdos.foundationvalidation`, no production source/build-input changes. Unsigned Simulator Debug build PASS (`ios-app-selftest-build.log`); actual installed iOS SDK is **26.5**, Xcode is 26.6 (prior note saying iOS 26.6 was incorrect). Initial real iOS self-test report: `ios-initial-report.json`, 1 Item/Media/Profile, 3 pending intents, one target representation verified, liveService NOT_RUN. This build predates the subsequent Photos mapping UI wiring; final App build evidence must be renewed for that affected change.

New Photos adapter batches only supplied selected identifiers at persistence/load boundaries. Identifier-not-found, ambiguity, network need, space and authorization remain distinct. Mapping APIs compile; permission/cross-device behavior remains external evidence pending. Smart fallback backup restores picker-delivered bytes and precision; Full refuses to claim complete original resources from picker delivery alone.

Simulator process relaunch completed: `LocalEvidence/ios-reopen-report.json` PASS, same source snapshot as initial report, 1 restored representation verified, 1 Item/Media/Profile, 3 outbox intents. Screenshot `ios-selftest-screen.png` inspected: independent App title, explicit cloud/device pending status and readable controls. No live platform assertion inferred.

## Admission, media and real failure checkpoint

`restore-admission-tests-fixed.log`: 16/16 affected cases PASS. Initial run failed because a Usage fixture had no parent; the fixture now includes its legitimate parent while the scheduler continues to block missing-parent sends. New incarnation blocks resurrection of old attachments after explicit re-add. A-B-A writes a new paused epoch; stale adapter callbacks consult durable session identity. Ordinary initial binding cannot bypass restored-cloud admission.

`media-transfer-tests-fixed.log`: 13/13 affected cases PASS (5 media, 5 backup, 3 admission). Initial compile had a test-only missing try annotation, fixed before execution. Media revisions keep immutable original files, late downloads/ACK do not switch current images, Photos safety copies do not change original-upload policy, policy downgrade has no cloud-delete operation, quota pauses media and transient errors obey retry-after. 250 Items/50 Media is a planner fixture only. HEIC encoder/import and preview sizes 128/256 passed on actual ImageIO. Original CKAsset upload/read code compiles, but no service request was performed.

`storage-failure-tests.log`: 6/6 PASS. A real `allowsSave: false` SwiftData store returned NSCocoa error 513 during save; no Draft/outbox persisted and prepared original remained. Permission/protection, space, missing, corruption and unknown are distinct classifications; no path deletes/recreates a failed store. Saved-but-refresh-unavailable is explicitly a committed result.

`process-checks-latest.json`: three actual subprocess SIGKILL cases (exit -9), at prepared, DB-committed and first-file-finalized boundaries. Recovered counts are respectively 0 Draft/0 outbox and 1 Draft/2 outbox; original hash preserved in all cases. Driver also generates true baseline store in a terminated process, clones full directory, migrates and reopens twice, retains source file hashes and records observable NSStoreModelVersionHashes for all five baseline entity names. Schema metadata probing now uses a disposable clone to avoid even shared-memory changes to immutable source; this driver-only refinement remains to be rerun at final evidence collection.

## Checkpoint: nested compatibility and live execution controls

- Contract archive rechecked: all seven SHA256SUMS entries PASS. Existing validation worktree resumed; original protected file hashes remain unchanged.
- Fixed a concrete compatibility gap: unknown fields nested in typed Profile or Media now prevent rewrite, just like unknown top-level fields. Raw payload survives disk reopen; attempted rewrite leaves it byte-identical.
- `swift test --filter 'ProtocolBoundaryTests|BackupRestoreTests|MediaTransferTests'`: 17 tests, zero failures, exit 0. Adds explicit retired-representation restore byte equality and removal of both prepared and acknowledged media tickets. Log: `LocalEvidence/nested-fields-restore-tests.log`.
- `python3 Tools/process_checks.py`: exit 0, actual SIGKILL at prepared/committed/originalFinalized and independent-process baseline clone migration/reopen. Schema identity probe uses a separate copy. Evidence: `LocalEvidence/process-063a1064-6f56-4ac9-bc20-f21f8f68e293`.
- Independent App now exposes Owner-configured Development connection, metadata fetch/send, update, explicit original upload/download, OFF, and redacted summary. Blank replica uses a separate persistent root; existing local library is retained. No live service call executed.
- Private configuration tool verifies an already signed bundle and Development entitlements without provisioning. Runtime binds config to executable plus Debug dylibs; these controls still require signed-device execution evidence.
- Actual iOS Simulator Debug build, iOS 17 deployment target / installed iOS 26.5 SDK, unsigned: PASS, exit 0. Latest log: `LocalEvidence/live-code-binding-app-build.log`. This is compilation evidence, not signed/live or final runtime acceptance.
- Remaining control audit includes durable live reporting, cumulative budget accounting, service errors and Owner setup instructions. Final reviewer/full candidate suite not yet performed.
