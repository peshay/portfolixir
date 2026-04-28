# GitHub Issues and Project Board Notes

## Should Portfolixir use a GitHub Project board?

A GitHub Project board can be useful for human planning, but it should not be the primary source of truth for LLM-driven development.

For LLMs, a versioned Markdown backlog inside the repository is more useful because:

- it is available in the code checkout
- it can be reviewed in PRs
- it evolves with the code
- agents can read it without separate GitHub Project permissions
- story IDs stay stable

Recommended approach:

1. Keep the canonical backlog in:
   - `docs/product/pp-inspired-product-backlog.md`
2. Use GitHub Issues only for selected ready-to-build stories.
3. Optionally use a GitHub Project board later as a visual layer over Issues.

## Suggested issue labels

- `type:story`
- `type:bug`
- `type:docs`
- `area:ui`
- `area:domain`
- `area:accounts`
- `area:transactions`
- `area:reports`
- `area:imports`
- `area:market-data`
- `priority:high`
- `priority:medium`
- `priority:low`
- `status:ready`
- `status:blocked`
- `llm:good-first-spark`
- `llm:needs-strong-model`

## Suggested first issues

Create issues only when you are ready to implement them:

1. PFX-009 Clean up All Securities page and table
2. PFX-010 Edit existing security
3. PFX-011 Delete or archive security
4. PFX-012 Add active/inactive status to securities
5. PFX-015 Create deposit accounts
6. PFX-016 Create securities accounts
7. PFX-018 Record buy transaction
8. PFX-020 All transactions list

## Suggested `gh issue create` example

```sh
gh issue create \
  --repo peshay/portfolixir \
  --title "PFX-009: Clean up All Securities page and table" \
  --label "type:story,area:ui,priority:high,llm:good-first-spark" \
  --body-file docs/product/pfx-009-issue-body.md
```
