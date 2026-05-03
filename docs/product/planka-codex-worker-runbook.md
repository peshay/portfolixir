# Planka/Codex Worker Runbook (One Card)

## Purpose
This runbook describes how a builder executes one Portfolixir story card from Planka to PR handoff.

## Scope
- One implementation card at a time.
- Use board lanes and labels as workflow state.
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

## Label model
- `Agent: <name>`: participation marker.
- `Owner: <name>`: active lock while working.

Only one `Owner:` label should be active per in-flight card.

## Builder flow (new implementation)
1. Pick one card from `Ready for Codex`.
2. Claim card:
   - add `Agent: <name>`
   - add `Owner: <name>`
   - move card to `In Progress`
3. Re-read card and verify acceptance criteria.
4. Implement only in-card scope.
5. Run project gates:
   - `mix format`
   - `mix test`
6. Commit and push story branch.
7. Open/update PR with concise story summary and validation evidence.
8. Add card comment with PR link and evidence.
9. Remove `Owner:` label.
10. Move card to `PR Open`.
11. Re-check that card in `PR Open` has no `Owner:` label.
12. Stop (one-card policy).

## Fix flow (`Needs Fix`)
1. Claim card (same lock steps).
2. Work on the existing PR branch.
3. Implement only requested fixes.
4. Re-run gates (`mix format`, `mix test`).
5. Push fix commits.
6. Comment fix summary and evidence on card/PR.
7. Remove `Owner:` label.
8. Move card back to `PR Open`.
9. Verify ownerless handoff.

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
Worker run is complete when exactly one card is handed off ownerless in `PR Open` or moved to a true `Blocked` state with evidence.
