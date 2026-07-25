# Current Task

## Identity

- Stage: G0
- Title: Governance Foundation Import
- Status: APPROVED
- Intended branch: `docs/governance-foundation-v1`
- Base branch: `main`

## Objective

Import the HouseholdOS Repository Initialization Package v1.0 into the empty repository, establish the first auditable documentation baseline, push it to GitHub, and create a Draft PR for Owner Review.

## Included Scope

1. Initialize or clone `https://github.com/yoCruzer/HouseholdOS`.
2. Preserve the package directory structure exactly unless a path is invalid.
3. Add all Markdown governance files and `.gitignore`.
4. Verify internal Markdown links and required files.
5. Create the initial Git history required by an empty repository.
6. Place the complete governance package on `docs/governance-foundation-v1`.
7. Commit with a documentation-only commit.
8. Push `main` bootstrap if technically necessary.
9. Push the governance branch.
10. Create a Draft PR targeting `main`.
11. Update this file to `AWAITING_OWNER_REVIEW` with actual branch, commit and PR information.
12. Update `CURRENT_STATE.md` with actual repository state.

## Explicit Non-goals

- Do not create an Xcode project.
- Do not write Swift.
- Do not add CI.
- Do not choose a Bundle Identifier.
- Do not change Foundation product semantics.
- Do not add future features.
- Do not merge the Draft PR.
- Do not delete or replace Product Design Book content.
- Do not convert Markdown files to DOCX/PDF in the repository.

## Referenced SSOT

- `AGENTS.md`
- `README.md`
- `Docs/Product/HouseholdOS_Product_Design_Book_v1.0.md`
- All files in `Docs/Foundation/`
- `Docs/Planning/STAGE_DEFINITIONS.md`

## Acceptance Criteria

- Repository has a valid `main` branch.
- Governance changes exist on `docs/governance-foundation-v1`.
- All expected package files exist.
- Product Design Book v1.0 is stored under `Docs/Product/`.
- No Swift, Xcode project, binary document or generated build file is added.
- `git diff --check` passes.
- A Draft PR targets `main`.
- PR body explains scope, non-goals and validation.
- `CURRENT_STATE.md` reflects reality.
- `CURRENT_TASK.md` is marked `AWAITING_OWNER_REVIEW`.
- Working tree is clean after commit/push.

## Git Authorization

Allowed:

- `git init` or clone
- initial bootstrap commit if required by empty remote
- create/switch branch
- add/commit
- push `main` only for minimal bootstrap
- push governance branch
- create Draft PR

Not allowed:

- merge PR
- force push
- rewrite shared history
- delete remote branches
- enable auto-merge

## Required Verification

- List all tracked files.
- Check expected file manifest.
- `git diff --check`
- `git status --short`
- Confirm branch and HEAD.
- Confirm remote refs.
- Confirm Draft PR base/head.
- No tests/build are required because code does not exist.

## Stop Conditions

Stop if:

- Remote contains unexpected commits or files.
- Package files are missing or corrupted.
- Authentication does not permit push/PR creation.
- Any change to frozen product semantics appears necessary.
- An existing working tree has unrelated uncommitted changes.

## Completion Report

Report:

- Initial remote state.
- Bootstrap approach.
- Branches and commit SHAs.
- Files imported.
- Manifest validation.
- Draft PR link/number.
- Final git status.
- No-code confirmation.
