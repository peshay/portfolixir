# Codex Story Queue (Planka)

## Purpose
Portfolixir uses a Planka board as the execution queue for implementation stories.
This document describes the repo-facing workflow for taking one story from queue to PR handoff.

## Board lanes
Current lane flow:

1. **Inbox** — unprocessed ideas
2. **Backlog** — valid cards not yet queued for implementation
3. **Ready for Codex** — implementation-ready card for a builder
4. **In Progress** — actively claimed and worked card
5. **PR Open** — PR exists, awaiting review/merge
6. **Needs Fix** — reviewer requested changes
7. **Merged** — PR merged
8. **Blocked** — cannot continue without a decision or dependency

## Label model
Labels are used for participation and ownership routing:

- `Agent: <Name>`: cumulative participation marker
- `Owner: <Name>`: active lock while one role is working the card

Handoff lanes (`Ready for Codex`, `PR Open`, `Needs Fix`, `Merged`) should be ownerless.

## One-card-at-a-time execution flow
1. Select one eligible implementation card from `Ready for Codex`.
2. Claim it with labels and move it to `In Progress`.
3. Implement only that story scope.
4. Run gates (`mix format`, `mix test`).
5. Push a branch and open/update PR.
6. Add a concise card comment with PR link and evidence.
7. Remove owner label and move card to `PR Open`.

## Branch naming
Use a story-specific branch name:

- `codex/<story-id-kebab-summary>`

Examples:
- `codex/pfx-pay-002-dividend-accumulation-chart`
- `codex/pfx-import-001-raw-import-review-ui`

## PR expectations (repo-facing)
PR title/body should be concise and include:

- Story ID
- Scope summary
- Changed files (repo-relative)
- Validation commands and results
- Follow-up items (if any)

Keep artifacts public-safe: do not include private runtime/workspace details.

## Needs Fix workflow
When a card moves to `Needs Fix`:

1. Claim the card.
2. Work on the existing PR branch.
3. Implement only requested fixes.
4. Re-run gates.
5. Push fixes and comment summary.
6. Remove owner label and return card to `PR Open`.

## Review/merge handoff
Builder role ends at PR handoff in `PR Open`.
Review and merge are handled by the review role via the board workflow.
