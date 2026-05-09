# Portfolixir LLM Story Workflow

This file defines the preferred workflow for coding agents such as Codex Spark.

## Source of truth

The primary product backlog is:

- `docs/product/pp-inspired-product-backlog.md`

Coding agents should read it before selecting or implementing a story.

Concrete per-run Spark/Codex prompt files are one-off inputs and must not be committed.
There is intentionally no root `prompts/` directory in the repository; use chat, issue comments,
or local notes for temporary run instructions.
Product stories belong in the backlog file.
Reusable workflow guidance belongs in this document.

## Working mode

1. Select exactly one story.
2. Create a branch named after the story, for example:
   - `codex/pfx-009-clean-all-securities`
3. Keep scope narrow.
4. Use TDD where practical:
   - failing test
   - minimal implementation
   - green tests
   - refactor
5. Run:
   - `mix format`
   - `mix test`
6. For UI/runtime stories, also run Docker smoke checks:
   - `docker compose down --remove-orphans`
   - `docker compose up --build`
   - `curl -i http://localhost:4000/health`
   - `curl -i http://localhost:4000/`
   - story-specific route checks
7. Open a PR.
8. PR body must include:
   - story ID
   - summary
   - changed files
   - tests run
   - Docker smoke checks if applicable
   - follow-up tasks

## Foundation slices

Foundation work may use architecture-slice IDs such as `PFX-FND-001` when the work is broader than a
single UI user story.

Agents must still keep the scope coherent and avoid unrelated work. A foundation slice can touch
multiple layers only when those changes belong to the same foundation purpose.

Agents must create a branch before editing and must not work directly on `main`.

## Scope control

Agents must not implement later stories opportunistically.

Examples:

- PFX-009 may improve All Securities layout, but must not add edit/delete/search.
- PFX-018 may add buy transactions, but must not build the holdings report.
- PFX-026 may add manual quote entry, but must not add external provider calls.

## UI quality rule

Spark-level agents may produce acceptable functional UI but should avoid major design rewrites.

When in doubt:

- table-first
- simple forms
- clear empty states
- no fake demo data
- no overdesigned dashboards
- no large CSS architecture changes unless the story explicitly asks for it

## Design debt

The current app shell is acceptable as foundation but should be treated as design debt. A future
stronger-model story should improve:

- visual hierarchy
- spacing
- typography
- navigation icons
- primary actions
- form placement
- moving inline styles out of component modules
