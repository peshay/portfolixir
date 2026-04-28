# Spark Prompt: PFX-009 Clean up All Securities page and table

You are working on Portfolixir.

Read first:

- `AGENTS.md`
- `docs/product/pp-inspired-product-backlog.md`
- `docs/product/llm-story-workflow.md`

Implement exactly this story:

## PFX-009: Clean up All Securities page and table

Goal:
Make the All Securities page feel like a usable product screen instead of a raw prototype form.

Important:
- Do not start edit/delete/search/import.
- Do not create fake securities.
- Do not redesign the entire app shell.
- Keep Phoenix LiveView.
- Keep the current data model unless a tiny change is unavoidable.
- Focus on `/` and `/securities`.

Requirements:

1. Page structure
- `/` and `/securities` should render a page titled `All Securities`.
- The securities list/table should be the primary content.
- The add-security form should be visually secondary.
- If simple and safe, make the add form collapsible behind an `Add security` button.
- If collapsible behavior is too much, keep it as a secondary card below the table.

2. Empty state
- When no securities exist, show:
  - Title: `No securities yet`
  - Text: `Add your first security to start building your portfolio.`
- The empty state should look professional and be part of the list area.

3. Table
- When securities exist, show them in a clean table.
- Include columns:
  - Name
  - Symbol
  - Currency
  - ISIN
  - WKN
  - Provider symbol
  - Exchange
- Use `—` for missing optional values.
- Do not add action buttons yet.

4. Add security form
- Existing create security functionality must continue to work.
- Validation errors must still be visible.
- Form should not dominate the page.
- Submit button should be clear.

5. Tests
- Update or add LiveView tests:
  - `/` renders `All Securities`
  - `/securities` renders `All Securities`
  - empty state appears when no securities exist
  - after creating a security, it appears in the table
  - optional empty fields render as `—`

6. Quality gates
Run:
- `mix format`
- `mix test`

If this story changes runtime route behavior, also run:
- `docker compose down --remove-orphans`
- `docker compose up --build`
- `curl -i http://localhost:4000/health`
- `curl -i http://localhost:4000/`
- `curl -i http://localhost:4000/securities`

Branch:
`codex/pfx-009-clean-all-securities`

Commit:
`feat(ui): clean up all securities page`

PR title:
`feat(ui): clean up all securities page`

PR body:
Include:
- Summary
- Tests run
- Docker smoke checks if run
- Follow-up tasks
