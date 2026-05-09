# Codex Story Queue

## Purpose
Portfolixir tracks implementation stories through a project workflow board and hands work off
through pull requests.
This note keeps only contributor-facing guidance.

## One-card implementation flow
1. Pick one implementation story from the active queue.
2. Implement only that story scope.
3. Run project gates (`mix format`, `mix test`).
4. Push a story branch and open or update the PR.
5. Add a short status note to the story card with PR link and test evidence.
6. Hand off for review; do not continue with another card in the same run.

## Branch naming
Use a story-specific branch:

- `codex/<story-id-kebab-summary>`

Examples:
- `codex/pfx-pay-002-dividend-accumulation-chart`
- `codex/pfx-import-001-raw-import-review-ui`

## PR expectations
Keep PR artifacts concise and repo-facing:

- story ID
- scope summary
- repo-relative changed files
- validation commands and results
- follow-up items, if any

Do not include private runtime, workspace, or internal workflow details.

## Fix-cycle flow
If review requests fixes, continue on the existing PR branch, apply only requested fixes, rerun
gates, push, and hand back to review.
