# Current State

Status: ACTIVE
Updated: 2026-07-25

## Repository State

- Repository: `yoCruzer/HouseholdOS`
- Default branch: `main`
- Product Design Book: frozen at v1.0
- Governance package: generated, awaiting repository import
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

## Current Risks

- Actual local Xcode version and supported deployment target have not been verified.
- SwiftData architecture remains provisional until F0/F1 validation.
- Empty GitHub repository must receive an initial commit before normal branch/PR workflow.
- No runtime data migration experience exists yet.

## Next Approved Work

See `Docs/Operations/CURRENT_TASK.md`.

## Last Verified Baseline

No code baseline exists. Any report claiming tests or build have passed before F0 is incorrect.
