# Planka/Codex Worker Runbook (One Card)

## Purpose
This runbook describes how a builder executes one Portfolixir story card from Planka to PR handoff.

## Scope
- One implementation card at a time.
- Use board lanes as workflow state.
- Stop after the card is handed off in `PR Open`.

## Prerequisites
- Local repository is up to date.
- Card is in `Ready for Codex` or explicitly assigned in `Needs Fix`.
- Card acceptance criteria and constraints are clear.

## Lane model
- `Ready for Codex`: card can be claimed by a builder.
- `In Progress`: active implementation work.
- `PR Open`: PR is open and ready for review handoff.
- `Needs Fix`: reviewer requested changes on existing PR branch.
- `Blocked`: progress requires external decision/input.

## Builder flow (new implementation)
1. Pick one card from `Ready for Codex`.
2. Move it to `In Progress` and verify acceptance criteria.
3. Implement only in-card scope.
4. Run project gates:
   - `mix format`
   - `mix test`
5. Commit and push story branch.
6. Open/update PR with concise story summary and validation evidence.
7. Add card comment with PR link and evidence.
8. Move card to `PR Open`.
9. Stop (one-card policy).

## Fix flow (`Needs Fix`)
1. Move the card to `In Progress`.
2. Work on the existing PR branch.
3. Implement only requested fixes.
4. Re-run gates (`mix format`, `mix test`).
5. Push fix commits.
6. Comment fix summary and evidence on card/PR.
7. Move card back to `PR Open`.
8. Stop.

## Blocker handling
If the card cannot safely proceed:
- capture concrete blocker evidence,
- leave a concise card comment,
- move to `Blocked` when appropriate,
- keep scope narrow (do not invent extra work).

## PR expectations (repo-facing)
Include:
- Story ID
- concise scope summary
- changed files (repo-relative)
- validation commands/results
- follow-up items if any

Do not include private runtime/workspace details.

## Stop condition
Worker run is complete when exactly one card is handed off in `PR Open` or moved to a true `Blocked` state with evidence.
