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

## Contract assertion map — pre-final audit

This map distinguishes directly exercised behavior from missing evidence. It is a candidate audit, not final acceptance: final dependency fingerprints, one consolidated independent review and candidate closure remain pending. All named tests are under `Prototypes/FoundationValidation/Tests/ValidationCoreTests`; process tools and local artifacts under that prototype. LOCAL_PLATFORM here is macOS SwiftData/SQLite/ImageIO/file flags or separately identified Simulator execution, never a physical-device claim.

| Contract assertion | Current evidence / exact boundary | Status |
| --- | --- | --- |
| G0 independent bundle/store/media/engine paths, preserve existing work | Independent xcodeproj/App paths; baseline diff scope and protected local hashes rechecked at checkpoints | PASS (local isolation; final audit pending) |
| G0 native SDK build / min OS | Actual Swift package + unsigned iOS Simulator builds, deployment iOS17, SDK26.5 | PASS compilation; iOS17 runtime BLOCKED_EXTERNAL |
| G0 create/read/update true service | Native CloudAdapter + signed-config controls compiled; no authorized environment | BLOCKED_EXTERNAL |
| G1 true legacy source / shape | Byte-exact baseline PersistenceModels/Controller in LegacySourceManifest; separate legacy CLI process; real store NSStoreModelVersionHashes for five legacy entities | PASS LOCAL_PLATFORM |
| G1 complete fixture topology, immutable source | LegacyFixture snapshot comparisons; process_checks includes Item/Draft/archive/sourceDraft/location/system/custom/unknown category/cover/multiple media/deleted draft; whole source tree hashes unchanged | PASS LOCAL_PLATFORM |
| G1 clone migrate/reopen/repeat/failure | Separate-process migrate + twice verify; corrupt clone fails without replacing DB; existing migration destination rejected; source remains | PASS LOCAL_PLATFORM; migration-engine mid-operation kill not separately proven |
| G1 retain legacy App-owned bytes | LegacyFixture exact media hashes; no guessed Photos reference conversion | PASS LOCAL_PLATFORM |
| G1 same Draft across replicas / identity | SharedChainTests.testIndependentLibrariesAndClonedDraftConfirm; LocalChainTests.testCaptureReopenConfirmKeepsMediaAndProfileIdentity | PASS LOGIC+LOCAL_PLATFORM |
| G1 category switch retains Profile | ProtocolBoundaryTests.testLateAckPreservesFetchedConflictAndCategoryEditKeepsProfile | PASS LOGIC+LOCAL_PLATFORM |
| G1 same-name identity / independent library / merge plan | SharedChain independent persisted library IDs and rejected cross-library open; explicit same-name distinct-item assertion still to finalize | RUNNING |
| G2 same-save business/outbox, no phantom | SchemaTests; LocalChainTests journal fault matrix; actual read-only SwiftData failure in StorageFailureTests | PASS LOCAL_PLATFORM+LOGIC |
| G2 file/DB/original-preview/finalize/cleanup/refresh errors | LocalChainTests.testJournalFailuresPreserveStagingAndAtomicOutbox; StorageFailureTests.testSavedButRefreshUnavailableRetainsSuccessAndNoReplay | PASS LOCAL_PLATFORM+LOGIC |
| G2 process termination + unique staging retention | process_checks actual SIGKILL at prepared, committed, originalFinalized; reopen counts/hash | PASS LOCAL_PLATFORM |
| G2 permission/protection/capacity/corruption distinctions | StorageFailureTests classifier + actual error513; corrupt synthetic clone failure; source retained | PASS injection/local; physical locked-device access not claimed |
| G3 rev7 ACK must not clear rev8 / repeated ACK / restart | SyncProtocolTests.testOldAckCannotRemoveNewEditAfterReopen | PASS LOGIC+LOCAL_PLATFORM |
| G3 lost ACK / service idempotence / Usage retry vs two actions | SharedChainTests.testLostAckRetryAndTwoRealUsageActions; DeterministicService shares CloudCodec/core | PASS LOGIC+LOCAL_PLATFORM |
| G3 partial successes / engine state loss | Native per-result handler exists; focused explicit mixed-result regression still to finalize | RUNNING |
| G3 durable inbound before checkpoint / replay no echo | ProtocolBoundaryTests.testFailedInboundCannotAdvanceCheckpointOrBootstrap; SyncProtocolTests.testInboundIsDurableNoEchoAndPendingEditRetainsConflict | PASS LOGIC+LOCAL_PLATFORM |
| G3 native event order / send-fetch reentry | Native delegate compiles, no service run | BLOCKED_EXTERNAL |
| G4 bootstrap local/cloud combinations and paging | SharedChain blank replica; ProtocolBoundaryTests.testFetchPagesRequireCompletionAndOffRejectsLateData; failed inbound blocks; explicit full partial/empty/error matrix still to finalize | RUNNING |
| G4 scope/OFF/ON/account A-B-A | SyncProtocolTests OFF/account; AdmissionTests.testAccountABARequiresBindingAndRejectsOldEpoch; durable session rejects retained old adapter | PASS LOGIC+LOCAL_PLATFORM; actual account event BLOCKED_EXTERNAL |
| G4 ancestor merge/coupled fields/no ancestor/same field | ProtocolBoundaryTests three-way test; SyncProtocolTests durable conflict; BackupRestoreTests preserves conflict bytes | PASS LOGIC+LOCAL_PLATFORM |
| G4 late ACK after fetched conflict | ProtocolBoundaryTests.testLateAckPreservesFetchedConflictAndCategoryEditKeepsProfile | PASS LOGIC+LOCAL_PLATFORM |
| G4 unknown top-level/nested fields | ProtocolBoundaryTests two future-field tests; raw payload survives reopen and refused rewrite | PASS LOGIC+LOCAL_PLATFORM |
| G5 tombstone/offline old write/late child/inflight old save | ProtocolBoundaryTests parent-delete test; SyncProtocolTests tombstone/re-add; SharedChain child-first | PASS LOGIC+LOCAL_PLATFORM |
| G5 explicit re-add incarnation / old children | AdmissionTests.testReAddCannotRevivePriorIncarnationChildren | PASS LOGIC+LOCAL_PLATFORM |
| G5 old backup vs remote tombstone | AdmissionTests.testOldBackupCannotUploadOverRemoteTombstone | PASS LOGIC+LOCAL_PLATFORM |
| G5 userDeletedZone / unknown zoneNotFound / key-reset signal | Native error branch conservative; SDK signal/evidence audit and explicit injected classifier assertions remain | RUNNING; live destructive system condition not requested |
| G6 separate Picker/PhotoKit permission and exact fallback | PhotosBoundaryTests permission matrix + Smart restore; actual adapter compiles | PASS LOGIC+LOCAL_PLATFORM fallback; real permission transitions BLOCKED_EXTERNAL |
| G6 reference mapping failure classes / only selected IDs | PhotosBoundaryTests mapping classifier; PhotosMappingBatch native batch calls; no library-wide fetch | PASS LOGIC+compile; actual mapping and cross-device BLOCKED_EXTERNAL |
| G6 stable ID/ref/representation; old ACK/download | MediaTransferTests old representation test, policy safety-copy test; shared wire carries reference; preview/descriptor immutable guard test | PASS LOGIC+LOCAL_PLATFORM |
| G6 JPEG/HEIC / preserve original metadata / strip preview / orientation | LocalChainTests ImageIO metadata test; MediaTransferTests.testStaticHEICAndTwoPreviewSizes | PASS LOCAL_PLATFORM; Live Photo/RAW full resources NOT_APPLICABLE to supported static scope |
| G7 real CKAsset upload/read/temp URL/durable restart | Native OriginalAssetAdapter code compiled; deterministic transfer guards; no actual CKAsset service | BLOCKED_EXTERNAL |
| G7 prove blank metadata fetch has no implicit originals | Deterministic transport explicitly carries previews only; two native zones + desiredKeys compiled; Owner instructions require actual request observation | BLOCKED_EXTERNAL; fake is insufficient |
| G7 policy downgrade/OFF no cloud deletion; Photos original no escalation | MediaTransferTests policy/quota/OFF tests; MediaPlanner representative 250/50 | PASS LOGIC; metadata data-only policy integration scope under audit |
| G7 quota/network/throttle/partial / finite retry | MediaTransferTests quota/backoff; fixed native retry-after; mixed-result coverage under audit | RUNNING |
| G7 cumulative budget / interrupted attempts | LiveEvidenceTests two tests, persisted endpoint allocation and request STARTED survives reload; no LIVE bytes | PASS LOGIC+LOCAL_PLATFORM; actual overhead unknown |
| G8 consistent structure/representation snapshot | BackupRestoreTests consistency + queued mutation single-writer boundary; SQLite backup API includes WAL | PASS LOCAL_PLATFORM within synchronous single-writer fixture; not external-provider concurrency |
| G8 Smart/Full completeness/missing/cloud-only source | BackupRestoreTests missing original/hash; PhotosBoundaryTests picker precision rejects Full; no silent omission | PASS LOCAL_PLATFORM |
| G8 partial/marker/hash/count/cancel/capacity/interruption | BackupRestoreTests interrupted export/switch; no final package on injected failure | PASS LOCAL_PLATFORM+LOGIC; real kill during backup publication not separately proven |
| G8 path/symlink/size/version/input validity | BackupRestoreTests package validation | PASS LOCAL_PLATFORM; no archive/decompression implementation, so decompression bomb support NOT_APPLICABLE |
| G8 atomic generation / old source fallback / conflict/intents | BackupRestoreTests consistency and before/after switch interruption | PASS LOCAL_PLATFORM+LOGIC |
| G8 all retired bytes, clear old ACK/session, fresh cloud admission | BackupRestoreTests.testRestorePreservesRetiredBytesButDropsOldMediaTicketsAndAcknowledgements + AdmissionTests | PASS LOCAL_PLATFORM+LOGIC |
| G8 zero Photos writes / source snapshot target actual hash | Local restore code has no PhotoKit writes; Simulator snapshot/reopen report exact bytes; latest runtime refresh still required | RUNNING final runtime; cross-device erase-old-device promise BLOCKED_EXTERNAL |
| P1 originals backup eligible, cache excluded, no ACK downgrade | BackupRestoreTests.testOriginalAndRecoveryPreviewRemainBackupEligible | PASS real file flags; system backup success not claimed |
| P1 no private data in public evidence / production confidentiality | Scope/privacy audit pending final; private config/evidence gitignored; impact field classification and pre-production decisions | RUNNING; production encryption approval DEFERRED until explicit design |
| Integration normal chain + four counterexamples | SharedChain, ProtocolBoundary old ACK/parent delete, PhotosBoundary fallback restore, Admission old backup tombstone reuse same core | PASS affected evidence; final candidate fingerprints pending |
| Program checkpoint recovery | Existing worktree/commits/process handles verified; no duplicate harness or cloud run; state atomically replaced | PASS operational checkpoint recovery; publication still platform-review blocked |

## Current audit checkpoint runs

- `late-ack-projection-tests.log`: 23 affected tests PASS, exit 0. Exact ACK preserves pending edit and newer fetched conflict basis; local protocol write now projects within its transaction.
- First `live-evidence-tests.log`: 2 fixture failures because temporary parent directories were absent. The directory precondition was corrected; no assertions removed or errors swallowed.
- `live-evidence-media-fixed-tests.log`: 26 affected tests PASS, exit 0. Includes durable request evidence/budget, wire Photos reference, representation original path, backup and protocol.
- `snapshot-photos-tests.log`: 10 tests PASS, exit 0. Includes queued mutation snapshot boundary; PhotoKit selected-current-representation adapter compiled, not called against a library.
- `immutable-preview-tests.log`: 16 affected tests PASS, exit 0. Invalid immutable descriptor or changed preview cannot overwrite existing recovery-preview bytes before transaction rejection.
- `process-corrupt-checks.log`: process tool exit 0, evidence directory `LocalEvidence/process-efa42863-0b5f-4bd2-b447-bcea6c783362`. Actual SIGKILL recovery/migration rerun plus corrupt clone and existing destination protection.
- `live-report-photos-app-build.log`: actual unsigned iOS Simulator App build PASS. `pre-review-app-build.log` tracks the subsequent UI/preview-guard candidate build; inspect terminal result before treating as PASS.
- One independent read-only reviewer started per GOAL §9. It has no mutation/service authorization. Findings and remediation remain pending; no claim of final review approval.

## Independent review (one consolidated read-only review) and remediation

Reviewer `final_readonly_review` inspected `d996a1a` plus the pre-review candidate, without edits, tests or service access. It correctly rejected IMPLEMENTATION_COMPLETE at that point. No independent re-review is claimed.

| Finding | Reproduction and remediation evidence |
| --- | --- |
| R1 confirmation fixed rev2 / dirty context after staging throw | ReviewRegressionTests reproduced wrong revision and a subsequent save committing an Item without confirmation outbox. capture/confirm now wrap all mutations and staging in rollback; confirm derives next revision and preserves prior wire values. |
| R2 missing legacy original/preview could pass manifest validation | Self-consistent manifest omission regression reproduced successful ACTIVE switch before fix. Restore now checks each MediaAsset original/preview path, file and manifest hash coverage before switch. |
| R3 local deletion vs concurrent server update repeated stale condition | Previously no candidate and repeat scheduling; now preserves remote candidate, blocks entity and native shared delegate reducer pauses reconciliation. |
| R4 inbound re-add accepted old incarnation | Previously resurrected parent/old child. Same new-incarnation requirement now applies inbound; rejection preserves tombstone. |
| R5 download bypassed backoff/pause | Download ticket now uses persisted queue admission; resumed queue before retry time and quota pause reject requests. |
| R6 incomplete durable Owner observations | Permission, selection access, mapping states and backup/restore snapshot alias/target representation counts now append to the redacted execution history. Final device/runtime observations remain pending. |

- `review-regressions-before.log`: four new tests fail on the previous implementation (14 assertions/errors), confirming actual counterexamples.
- `review-core-fixes.log`: 25 affected tests PASS, exit 0. Real read-only SwiftData error513 in its intentional fault test remains expected, not a swallowed unexpected failure.
- `review-adapter-fixes.log`: 15 affected tests PASS, exit 0. AdapterBoundaryTests exercise the exact beginFetch/recordFetchFailure/completeFetch/applySendResults/classify methods used by native delegate events, without creating CKSyncEngine or network calls. Covers same-name distinct objects, partial success, durable retry, failed fetch, old error after OFF, both zone-loss classes, conditional delete conflict.
- `pre-review-app-build.log` and `review-remediation-app-build.log`: actual unsigned iOS Simulator build PASS, exit 0. Storage failure categories now appear in validation App error messages; committed capture recovery remains explicitly reported as saved.
- Remaining audit items from review: actual migration interruption boundary; precise distinction between backup fault injection and process kill; native service/account event timing; true Photos/CKAsset evidence; final candidate fingerprints/full suite/runtime. Those are not closed by the test counts above.
- Operations stale NOT STARTED line corrected to RUNNING. No formal Foundation file or shipping App input modified.
