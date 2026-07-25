# Owner Review Checklist — G0

Use this checklist when reviewing the governance Draft PR.

## Product Integrity

- [ ] Product Design Book v1.0 is present and unchanged.
- [ ] WishItem remains deferred and separate from Item.
- [ ] Local import preserves GPS/EXIF.
- [ ] Ordinary external sharing defaults to stripping GPS.
- [ ] V1 scope has not expanded.

## Repository Governance

- [ ] `AGENTS.md` requires reading CURRENT_STATE and CURRENT_TASK.
- [ ] SSOT priority is explicit.
- [ ] Codex must stop at Stage boundaries.
- [ ] Codex cannot merge to main without approval.
- [ ] Git destructive actions are prohibited by default.

## Current Truth

- [ ] CURRENT_STATE says no Xcode project or Swift code exists.
- [ ] CURRENT_TASK only authorizes G0 import.
- [ ] Known limitations match reality.
- [ ] No tests/build are falsely claimed.

## Files

- [ ] Only text governance files and `.gitignore` are included.
- [ ] No DOCX, PDF, ZIP or generated binaries are committed.
- [ ] Directory structure matches the package README.
- [ ] Working tree is clean.

## Decision

- [ ] ACCEPT G0 and merge.
- [ ] REQUEST CHANGES.
- [ ] DEFER.
