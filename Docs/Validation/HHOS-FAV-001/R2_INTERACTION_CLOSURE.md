# PR5-IR-Closure-02 — interaction closure

Status: R2_LOCAL_CLOSURE_COMPLETE; publication pending; LIVE_EVIDENCE_PENDING.
Start: `449328ea87b40f773c4dcfa957f3ae00bf43e7ef`.
Code candidate: `1419c0122bac447cbfae8405f1672af7696ae4e8`.
Branch: `spike/foundation-validation`; sole Draft PR: #5.

## Findings and implemented boundaries

| Finding | Reproduction | Implementation | Current evidence |
| --- | --- | --- | --- |
| R2-01 | Native restore loses conditional base while retaining re-add | Exact predecessor can refresh an empty/restored or matching observed base without changing local payload; later observations/conflicts prevent regression | XS-01 completes conditional save/ACK or fetch confirmation, rejects missing base, reopens |
| R2-02 | Native self-fetch of sent 7 creates conflict with local 8, with/without ancestor | Typed durable operation receipt preserves exact send payload/base; ACK and fetch share validation and retirement; restore drops transport state but retains causal proof | XS-02/05 cover no ancestor, live ancestor and re-add predecessor, restore before echo, disk reopen between echo and send8, final ACK and late7 |
| R2-03 | Old child remains pending after replacement ACK | Explicit validated parent-incarnation replacement saves supersededBy and removes active delivery in the same transaction; history survives restore | XS-04 covers unsent/inflight C1, save failure rollback, R/C2 ACK, late C1 and restore |

A further native red case found that already-saved C1 requires a conditional retry for C2. A fresh serverRecordChanged receipt tied to the exact active replacement request may acquire its base. Ordinary late C1 ACK/fetch stays ignored. The regression first failed with the expected conditional-write rejection and then completed through the adapter reducer.

## Representation and transaction decisions

`OperationReceipt` is typed causal evidence in the existing checkpoint store under `operation-receipt/<operation>`: immutable payload/scope, send-time ancestor, prepared-for-send flag, confirmation and explicit replacement operation. It is not a second current business record or a remote version. Business/outbox, receipt and retirement share the SwiftData commit; failure rolls back. Existing candidate schema and shipping schema are unchanged. Existing `SentSnapshot`/`sent-base` rows remain compatible and can supply the receipt on a response.

Restore still clears engine/session, sent snapshots, old systemFields and ancestor. Retained receipts contain no CloudKit change tag. Re-admission requires a current matching service payload and permitted scope; a different account's receipt is not silently rebound. `pending()` remains active DurableIntent work. Superseded history is not ACKed and cannot become active merely through restore. Unknown-parent and true-conflict operations remain active but blocked.

The real engine delegate and tests call `CloudAdapter.prepareRequest`, which reads durable version data and uses CloudCodec to reconstruct CKRecord. A narrow fixture codec wrapper holds a service-generated opaque token alongside native system-fields bytes; the conditional service compares that stored token and rejects absent/wrong conditions. No private CloudKit API or manufactured real changeTag is used. The native-default test verifies disk-read system-fields use and rejects another record's archive. These are LOGIC + LOCAL_PLATFORM results, not CloudKit service timing evidence.

## Sequence mapping

All new tests are in `IndependentReviewRound2Tests` / `R2InteractionTests.swift`. Initial three counterexamples derive from the supplied ReviewSource draft; the conditional sequences use the shared native implementation.

| Sequence | Concrete tests | Expected terminal / control |
| --- | --- | --- |
| XS-01 | `testXS01RestoredReAddCompletesConditionalSaveAndRejectsWrongBase` | R accepted, ACK or own fetch confirms it, no active work/conflict, old D cannot regress base; disk reopen |
| XS-02 | `testXS02And05SelfEchoContinuationCompletesAcrossRestoreAndReopen` | Exact7 retires only7; service and local end at8, no false conflict; duplicate7/lateACK7 cannot regress8 |
| XS-03 | `testXS03RealConflictAndForgedSelfEchoRemainBlocked`; existing future-field/protocol tests | Different operation or changed same-ID payload retains local/remote conflict and active work across disk reopen |
| XS-04 | `testXS04SupersededInflightChildRetriesConditionAndHistorySurvivesRestore` | R/C2 confirmed; C1 superseded, not ACKed; late C1 ignored; failed local commit leaves old intent intact; restore preserves terminal history |
| XS-05 | restore variants of XS-02 | Sent re-add7 + local8 → backup/restore → current own7 → conditional8/ACK → disk reopen |
| XS-06 | `testXS06OldEpochCallbacksCannotConfirmOrChangeCurrentBase`; existing synthetic account tests | Old ACK/fetch/state/error ignored after OFF, current-scope fetch reacquires basis,8 completes and reopens |
| XS-07 | existing `testEqualRevisionCurrentChoiceSurvivesRestoreAndLateTransfers`, `testResolvedConflictRestoreDoesNotBlockReAdd`; XS-04 retirement restore | Explicit media representation and resolved/active conflicts retain prior semantics; receipt history does not revive on restore |
| XS-08 | `testXS08MixedAckEchoAndSupersessionDrainWithUnknownParentControl`; existing 99/100/101/300 and limitExceeded tests | 101 items plus child replacement drain via mixed ACK/echo in ≤3 rounds; unknown-parent remains pending, then completes when parent arrives; disk reopen |

Each fixture uses synthetic records; media tests use existing small synthetic images. A disk reopen reconstructs LocalChain/ModelContainer. The App smoke separately terminates and relaunches an actual Simulator process. Neither is a physical-device result.

## Evidence and remaining work

Original native red: 3 tests, 9 assertion failures, no compile/environment failures (`LocalEvidence/r2-initial-red.log`). Initial fix:3/3. Intermediate affected suite:50/50; child refinement and adapter:11/11. Final focused:10/10 (`r2-focused-complete.log`). Full final suite/build/runtime and final fingerprints are recorded in the unique VALIDATION_STATE, not inferred from historical65/65.

Old migration fixture/generator/schema inputs are unchanged: reuse prior separate-process migration evidence; current full suite covers current legacy bridge. Production App Unit/UI and duplicate CI are not rerun. Source ZIP19-file checksums passed before archival; public GOAL redacts its single historical personal path, declared in SOURCE_MANIFEST with updated archive checksums. ReviewSource stays byte-preserved.

Final current-code verification: **75/75 deterministic tests**, unsigned native Simulator build, and App initial-chain/terminated-process-relaunch **PASS**. Toolchain: Xcode26.6 / Swift6.3.3 / iOS26.5 Simulator. No failures/skips; the read-only-store diagnostic is an intentional existing fault test.

Input fingerprint: `610606e16d629c5ae7fadbd57367ed1a90077ac16d362c930c75052b03ef3532`. Exact file/artifact hashes and named cases are in VALIDATION_STATE. Source/contract self-review completed; independent external acceptance is not claimed. Original workspace protected-file hashes match the start snapshot. Remaining action: authorized publication. Live CloudKit/Photos/device/iOS17-runtime evidence stays pending. No Foundation Freeze, production-readiness claim, merge, ready or auto-merge.

Publication boundary: automatic approval review rejected the combined commit/push before execution. Local code/tests/evidence are complete; public branch/PR update awaits explicit publication approval. Remote remains `449328ea87b40f773c4dcfa957f3ae00bf43e7ef`, OPEN/Draft. No alternate publication route was used.
