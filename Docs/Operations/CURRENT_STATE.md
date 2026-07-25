# Current State

Status: G0_ACCEPTED
Updated: 2026-07-25

## Repository State

- Repository: `yoCruzer/HouseholdOS`
- Default branch: `main`
- Main bootstrap commit: `1769b87b8227188edeef9dcb33962091feb9fcb6`
- Main before G0 merge: `1769b87b8227188edeef9dcb33962091feb9fcb6`
- Governance branch: `docs/governance-foundation-v1`
- Governance import commit: `5dd90c8594c37ae492c3c84530fe62ae107c11d6`
- G0 PR head: `f6d49d5ea3ef37af2b42c43a8d240b1d5c761404`
- G0 merge commit: `4149469f136a9501905a699b0e59b3ee339cb73a`
- Merged PR: [#1](https://github.com/yoCruzer/HouseholdOS/pull/1)
- Merge method: merge commit
- Product Design Book: frozen at v1.0
- Governance package: imported, approved and merged
- Repository license: existing AGPL-3.0 `LICENSE` preserved
- Xcode project: not created
- Swift source code: none
- Tests: none
- Build baseline: not established
- CI: not configured
- App distribution: not configured

## Completed

- Product vision and boundary.
- Core model.
- Data model semantics.
- Information architecture.
- Privacy and metadata decisions.
- V1 scope.
- Proposed implementation stages.
- Codex governance rules.
- G0 governance foundation import.
- Draft PR creation for Owner Review.
- G0 Owner approval and PR #1 merge.

## Key Frozen Decisions

- Local-first.
- CaptureDraft is separate from Item.
- `WishItem` is a separate future candidate concept, not an Item status.
- Formal Item requires only name.
- Historical facts are not overwritten by current snapshots.
- Local photo import preserves original metadata, including GPS.
- Ordinary external sharing defaults to stripping GPS via Export Privacy Policy.
- V1 does not depend on OCR or AI.
- Stage execution uses Owner Gates.
- The existing AGPL-3.0 repository license is preserved.

## Current Risks

- Actual local Xcode version and supported deployment target have not been verified.
- SwiftData architecture remains provisional until F0/F1 validation.
- No runtime data migration experience exists yet.
- No implementation Stage is currently approved.

## Next Stage Planning

The next planned Stage is `F0 — Repository & Xcode Foundation Definition`. F0 is not approved for execution. Wait for the Owner to complete and approve the F0 Definition.

## Last Verified Baseline

G0 was approved and merged through PR #1 using merge commit `4149469f136a9501905a699b0e59b3ee339cb73a`. The repository still contains no product implementation code, Xcode project or CI. Tests and builds remain not applicable until an implementation Stage is approved.
