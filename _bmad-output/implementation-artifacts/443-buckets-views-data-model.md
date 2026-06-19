---
baseline_commit: ed0d90e7f16750bfd172792a5d21e2fea3e6e974
---

# Story: Buckets & views — data model (GitHub #443)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

> **Tracking:** GitHub issue [#443](https://github.com/peshay/portfolixir/issues/443),
> first story of epic [#448](https://github.com/peshay/portfolixir/issues/448)
> "Buckets & views: tag-based wealth scoping (ADR-0018)".
> Epic chain: **#443 (this, data model) → #444 (engine scoping) → #445 (API/MCP) →
> #446 (UI) → #447 (retire `excluded_from_allocation_targets`, supersede ADR-0013)**.
> This epic is **not** in `epics.md` (that artifact predates ADR-0018); the issue
> set is the authoritative story unit ("one issue = one chat = one PR").

## Story

As a **local portfolio maintainer**,
I want **a persisted bucket/view model that tags holdings (many-to-many) with correct depot-default + per-position inheritance and a mechanical double-count guard**,
so that **later stories can scope valuation, allocation, performance and risk to a named view without ever double-counting the single wealth universe**.

## Acceptance Criteria

Copied verbatim from issue #443, renumbered for task traceability:

1. **Migrations + schemas (additive, reversible):** `buckets`, depot/cash-account
   default-bucket links, position-level bucket overrides, `views` (include/exclude
   bucket sets).
2. **Assignment resolution:** a position inherits its depot's default bucket set
   unless it carries its own; **"explicit-empty"** (deliberately no bucket) is
   representable and distinct from "inherit". Pinned by tests.
3. **Many-to-many:** a holding can carry multiple buckets.
4. **A new context (`Portfolios.Buckets` or `Buckets`) owns all writes;** writes are
   **born actor-first and journaled** via `Journal.record/3` in the same `Ecto.Multi`
   (ADR-0017); view-definition edits are **not** journaled (ADR-0018 §5).
5. **Pure helpers:** "effective buckets for a holding" and "holdings matching a view
   filter" (**exclude wins**).
6. **Double-count guard meta-test:** the single-count holding universe under any view
   never exceeds the unfiltered total; per-bucket breakdowns may overlap and are never
   summed as a partition.
7. **DataCase tests** for inheritance, override, explicit-empty, multi-tag, and the
   view filter algebra.
8. **ADR-0018 authored and committed in this PR** (see Critical Finding #1). The repo
   rule is "architecture changes need an ADR, landed in the same PR as the change". The
   locked parameters below are the decision content; write the ADR from them, add it to
   `docs/decisions/index.md`, and ensure `docs_test.exs` passes.

### Out of scope (do NOT build here)

- Wiring engines to views (story 2 / #444).
- JSON API + MCP CRUD and the `view` scope param (story 3 / #445).
- UI: bucket assignment + view switcher (story 4 / #446).
- Removing `excluded_from_allocation_targets` / superseding ADR-0013 (story 5 / #447).
  **Leave the existing flag and its allocation behavior fully intact in this story.**

## Locked parameters (ADR-0018 — author these into the ADR)

These are fixed decisions from the issue. Do not redesign them; encode them.

- **Tags are many-to-many.** A holding can carry multiple buckets.
- **Assignment is depot-default + per-position override.** A position inherits its
  depot's default bucket set unless it carries its own override.
- **Totals are single-count** over the holding universe — **never the sum of buckets.**
  Per-bucket breakdowns may overlap and must never be summed as a partition.
- **Views are `{include | :all, exclude}` with exclude winning.** A bucket in both
  include and exclude is excluded.
- **Views are global** (not portfolio-scoped, not per-session).
- **Cash accounts are bucketable** (same assignment model as depots/positions).
- **Bucket assignment changes are journaled; view-definition edits are not.**

## Tasks / Subtasks

- [x] **Task 0 — Author ADR-0018** (AC: 8)
  - [x] Create `docs/decisions/0018-buckets-tag-based-wealth-scoping.md` with Jekyll
        frontmatter (`layout: docs`, `title:`, `description:`), Status: Accepted,
        Date: 2026-06-18. Model it on `0013-...md` / `0017-...md`.
  - [x] Capture every locked parameter above, plus §4 (this generalizes
        `excluded_from_allocation_targets`/ADR-0013 — but ADR-0013 is **superseded
        later**, in #447, not here) and §5 (assignment journaled, view-definition not).
  - [x] **Resolve and document the write-actor reconciliation** (Critical Finding #3):
        how view-definition writes (not journaled) satisfy the P2 `write_actor_test.exs`
        AST gate. State the chosen mechanism in the ADR.
  - [x] Add the entry to `docs/decisions/index.md` (keep `docs_test.exs` green).
- [x] **Task 1 — Migrations** (AC: 1) — additive, reversible, raw-SQL triggers
  - [x] `buckets` table (name, optional color, timestamps; unique name).
  - [x] Default-bucket link tables for **both** `securities_accounts` and
        `cash_accounts` (many-to-many: depot/cash-account ↔ bucket).
  - [x] Position-level override table keyed on **(securities_account_id,
        security_id)** — NOT a holdings row (holdings are derived, ADR-0004). Must
        represent "explicit-empty" distinctly from "inherit" (see Dev Notes).
  - [x] `views` table (name + include/exclude bucket sets; global).
  - [x] **Arm the journaled bucket-assignment tables** with the existing
        `portfolixir_require_journal_actor` guard trigger (copy the
        `arm_securities_journal` migration shape). Do **not** arm `views`.
  - [x] New migration timestamp **after** `20260616120000` (e.g. `20260618120000`).
- [x] **Task 2 — Schemas** (AC: 1, 2, 3) — `Ecto.Schema` + changeset per existing style
  - [x] Bucket, default-assignment, position-override, view schemas with closed-enum
        discipline and explicit validations.
- [x] **Task 3 — New context, actor-first + journaled** (AC: 4)
  - [x] `Portfolixir.Buckets` (top-level, locked) is the **only** writer.
  - [x] Every journaled write follows the **P9 write path** (Dev Notes) with
        `Actor` as the **first positional arg** and `Journal.record/3` in the Multi.
  - [x] View-definition CRUD: not journaled — but still satisfy the write-actor gate
        per the ADR-0018 decision from Task 0.
  - [x] Add new `resource_type` string codes (e.g. `"bucket"`,
        `"bucket_assignment"`) — stable codes, never module names.
- [x] **Task 4 — Pure resolution helpers** (AC: 5) — live under `Portfolixir.Engines.*`
  - [x] `effective_buckets(holding_key, …)` — depot default unless overridden;
        explicit-empty ⇒ no buckets; inherit ⇒ depot defaults.
  - [x] `holdings_matching_view(view, holdings, …)` — `{include|:all, exclude}`,
        **exclude wins**.
  - [x] **No `Repo`, no clock, no config inside these helpers** (P3 engine purity).
- [x] **Task 5 — Tests** (AC: 2, 3, 5, 6, 7)
  - [x] DataCase tests: inheritance, per-position override, explicit-empty vs inherit,
        multi-tag, view filter algebra (include, `:all`, exclude-wins).
  - [x] **Double-count guard meta-test** (AC 6): single-count universe under any view
        ≤ unfiltered total; per-bucket overlap never summed as a partition.
  - [x] Journaling tests: a bucket-assignment write produces exactly one journal entry
        with correct actor + before/after; a view-definition edit produces **none**.
  - [x] Guard-trigger negative test (`async: false`, outside sandbox): a raw write to an
        armed bucket-assignment table with no actor **raises** (mirror
        `test/portfolixir/journal/append_only_test.exs` style).
- [x] **Task 6 — Gates & docs**
  - [x] `mix format`, `mix test`, `mix coveralls`, `pre-commit run --all-files`.
  - [x] Confirm `write_actor_test.exs` / journal allowlist meta-tests pass with the new
        context (it cannot be grandfathered — grandfather lists only shrink).
  - [x] API/MCP coverage: **n/a for this story** (data model only; API/MCP is #445) —
        state this explicitly in the PR body.
  - [x] User docs: data-model-only, no user-visible surface yet → note "no
        `product-documentation.md` change; UI lands in #446" in the PR.

### Review Findings (code review 2026-06-18)

- [x] [Review][Decision] Task 1 said "arm the assignment tables" but only `buckets` is armed — **RATIFIED (accept: only buckets armed)**. Arming the assignment join tables would make the journal guard reject legitimate FK-cascade deletes from not-yet-actor-first Portfolios contexts (confirmed by edge-case review). Recorded in ADR-0018; arming follows in the Portfolios actor-first slice.
- [x] [Review][Patch] Setters crash on duplicate bucket ids instead of returning cleanly [`lib/portfolixir/buckets.ex`] — FIXED: `Enum.uniq` on the id lists in all setters.
- [x] [Review][Patch] `position_override/2` silently collapses a corrupt mixed (NULL + bucket) row set to `{:explicit, …}` [`lib/portfolixir/buckets.ex`] — FIXED: raises (crash-by-design) on mixed state; covered by a test that injects the corrupt state via a raw insert.
- [x] [Review][Patch] Non-deterministic ordering of public read APIs [`lib/portfolixir/buckets.ex`] — FIXED: `order_by: [asc: bucket_id]` on depot/cash/position reads.
- [x] [Review][Patch] Assignment journaling tests assert `[_ | _]` not "exactly one" [`test/portfolixir/buckets_test.exs`] — FIXED: tightened to `[_]`.
- [x] [Review][Patch] ADR-0018 doc drift (`create_view/4` → `create_view/2`) + cascade-delete journaling note [`docs/decisions/0018-buckets-tag-based-wealth-scoping.md`] — FIXED: arity corrected; added a consequence documenting that cascade-deleted assignment rows are not individually journaled.
- [x] [Review][Dismiss] Aggregate assignment journal entries carry `resource_id = nil` — by design; the `after` payload carries the owning ids. No action.
- [x] [Review][Dismiss] Dev Notes mention `engine_purity_test.exs` which does not exist — the engine is genuinely pure; gate is future work. No code impact.
- [x] [Review][Dismiss] Return-shape `:ok` (set_*) vs `{:ok, _}` (create/update/delete) — intentional, consistent convention.
- [x] [Review][Dismiss] `NULLS NOT DISTINCT` requires PostgreSQL 15+ — project runs postgres:18; commented.

## Dev Notes

### Critical Finding #1 — ADR-0018 must be written in this PR
The issue cites "ADR-0018 (Accepted)" and `docs/decisions/0018-buckets-tag-based-wealth-scoping.html`,
but **that file does not exist** — `docs/decisions/` stops at `0017`. `architecture.md`
(completed 2026-06-12 against 12 ADRs) contains **no** buckets/views/scope/single-count
design. Per the repo rule ("architecture changes need an ADR — landed in the same PR")
this foundation story is the home for ADR-0018. All decision content is in *Locked
parameters* above. **Do not implement the model without committing the ADR.**

### Critical Finding #2 — Holdings are NEVER stored (ADR-0004)
A "position" is **not** a row. Holdings are derived from the transaction ledger
(`Ledger.Projection`, ADR-0011) — there is no holdings table and you must not add one
(project-context Don't-Miss #1). Therefore the **per-position override cannot reference a
holding id**. Key it on the durable pair **(securities_account_id, security_id)**. The
"effective buckets for a holding" helper takes that key, not a holdings struct.

### Critical Finding #3 — View writes vs. the P2 write-actor AST gate
`write_actor_test.exs` classifies *any* public context function that transitively reaches
`Repo.insert/update/delete/*_all` or a writing `Repo.transaction` as a "write function"
that must carry the `Actor` first argument, **unless grandfathered** — and the grandfather
list only shrinks, so a **new** context cannot be added to it. But ADR-0018 says
view-definition edits are **not** journaled. Reconcile this in the ADR (Task 0).

**Decision (locked, 2026-06-18):** use **option (a)** — view-CRUD takes `Actor` as its
first positional arg for signature uniformity but does **not** call `Journal.record/3`
(satisfies the P2 AST gate; emits no journal row). Do **not** grow the allowlist. Record
this rationale in ADR-0018.

### Critical Finding #4 — "explicit-empty" vs "inherit" are different states
AC 2 requires three distinguishable states for a position:
  - **inherit** — no override row ⇒ use the depot's default bucket set.
  - **explicit-empty** — an override row that says "deliberately no buckets" (NOT the same
    as inherit, and NOT the same as the depot defaults).
  - **explicit set** — an override row listing one or more buckets.
Model this so a row's *absence* means inherit and a row's *presence with zero buckets*
means explicit-empty (e.g. an override header row + a join table; an empty join = empty).
Pin all three in tests — this is the silent-corruption trap.

### The canonical write path (P9) — copy `Catalog` exactly
The exemplar is `lib/portfolixir/catalog.ex` (`create_security/2`, `update_security/3`,
`delete_security/2`). Every journaled write:
1. Build the changeset.
2. `Multi.new() |> Multi.insert/update/delete(:step, changeset)`.
3. `|> Journal.record(actor, resource_type: "...", operation: :create|:update|:delete, source: :step[, before: prior])`.
4. `Repo.transaction(multi)`; return `{:ok, record}` / `{:error, changeset}`.

Key references:
- `Portfolixir.Journal.record/3` — `lib/portfolixir/journal.ex` (sets the
  `portfolixir.journal_actor` GUC, appends the journal insert, resets the GUC).
- `Portfolixir.Actor` — `lib/portfolixir/actor.ex`. Closed taxonomy
  `:owner_ui | :api_token_rw | :api_token_ro | :import_session | :system_job`.
  Always the **first** positional arg; never via the process dictionary.
- `Portfolixir.Journal.Entry` — `lib/portfolixir/journal/entry.ex`. `operation` enum is
  `:create | :update | :delete | :upsert`.
- `Portfolixir.Journal.Serializer` — `lib/portfolixir/journal/serializer.ex`. Decimals →
  strings, dates → ISO; **raises** on any unmapped type (so a new field can't be silently
  dropped — keep bucket schemas to JSON-safe field types).
- Migration trigger shapes — `priv/repo/migrations/20260614120000_create_audit_journal.exs`
  (guard fn `portfolixir_require_journal_actor`) and
  `20260614130000_arm_securities_journal.exs` (per-table arming).

### Architecture conformance (from `architecture.md`)
- **Pure engines vs. journaling shell** (D2/P3): resolution helpers go under
  `Portfolixir.Engines.*` and must contain **no** `Repo.*`, `DateTime.utc_now`,
  `Date.utc_today`, `System.*_time`, `:rand`, HTTP, or `Process.*` — `engine_purity_test.exs`
  enforces this via an explicit module whitelist; add the new pure modules to it.
- **Per-context guard arming is leaf-first** (Amendment 1): the order is
  Catalog/Fx → **Portfolios/Classifications** → Ledger → Imports. The *existing*
  Portfolios tables (`portfolios`, `cash_accounts`, `securities_accounts`) are **not yet
  armed** and **not actor-first** (`portfolios.ex` has zero `Actor` usage). Do **not**
  arm or convert them here — that is a separate slice. The **new** bucket tables are born
  journaled+armed regardless.
- **Closed taxonomies everywhere** — bucket `resource_type` codes, any enums: closed sets,
  validated, never `String.to_atom/1` on external input.
- **Decimal discipline** — unlikely to apply (buckets carry no money), but if any weight/
  ratio is persisted, use `:decimal` with explicit precision/scale, never float.

### Testing standards
- `DataCase`, `async: true` by default; **`async: false`** for the guard-trigger negative
  test (it commits outside the sandbox — see `journal/append_only_test.exs`).
- Test fixtures must go through the **real actor-first context writes** (Amendment 3) —
  no test-only journaling bypass, no GUC-setting helper.
- Place tests under `test/portfolixir/buckets/` (new) mirroring the context location;
  follow the user-story-comment-above-test shape from AGENTS.md.
- Exact assertions; no float tolerance.

### Project Structure Notes
- New files (delta): `lib/portfolixir/buckets.ex` (or `portfolios/buckets.ex`),
  `lib/portfolixir/buckets/*.ex` (schemas), pure helpers under `lib/portfolixir/engines/`,
  migrations under `priv/repo/migrations/`, ADR under `docs/decisions/`, tests under
  `test/portfolixir/buckets/`.
- Module naming **(locked, 2026-06-18): top-level `Portfolixir.Buckets` context.** It owns
  cross-cutting tags over depots, cash accounts and positions, so it is not a child of
  `Portfolios`; this mirrors how `architecture.md` lists `Actor`/`Journal` as top-level
  modules. Schemas live under `lib/portfolixir/buckets/`.
- Existing schemas you will reference (read before touching):
  `lib/portfolixir/portfolios/securities_account.ex`,
  `lib/portfolixir/portfolios/cash_account.ex`,
  `lib/portfolixir/portfolios/portfolio.ex`,
  `lib/portfolixir/catalog/security.ex`.

### References
- [Source: GitHub issue #443] — acceptance criteria, locked parameters, "for a fresh chat".
- [Source: docs/decisions/0017-append-only-audit-journal.md] — journal seam, actor
  taxonomy, guard-trigger arming, allowlist, serializer rules.
- [Source: docs/decisions/0013-exclude-securities-from-allocation-targets.md] — the flag
  this generalizes (superseded in #447, not here).
- [Source: lib/portfolixir/catalog.ex#create_security/2,update_security/3,delete_security/2]
  — canonical actor-first + `Journal.record/3` write path (P9).
- [Source: lib/portfolixir/journal.ex, actor.ex, journal/entry.ex, journal/serializer.ex,
  journal/allowlist.ex] — journaling infrastructure to reuse, not reinvent.
- [Source: priv/repo/migrations/20260614120000_create_audit_journal.exs,
  20260614130000_arm_securities_journal.exs] — trigger + arming migration shapes.
- [Source: _bmad-output/planning-artifacts/architecture.md#D1,#D2,#P1,#P2,#P3,#P9, Amendments 1-4]
  — conformance contract (journaling seam, engine purity, per-context arming, test rules).
- [Source: _bmad-output/project-context.md] — Decimal discipline, holdings-never-stored
  (#1), closed enums, no `String.to_atom/1`, additive migrations, meta-test culture.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (high reasoning), Claude Code dev-story workflow.

### Debug Log References

- `mix test` — 762 tests, 0 failures.
- `mix coveralls` — total 84.1%; `lib/portfolixir/buckets.ex` 91.0%,
  `lib/portfolixir/engines/bucket_resolution.ex` 100%.
- `mix credo --strict` — no issues.
- `mix sobelow --skip --exit --ignore Config.CSP,Config.HTTPS` — exit 0
  (only pre-existing Low-confidence findings in unrelated files).
- `mix dialyzer` — 0 errors.
- `mix ecto.migrate && ecto.rollback && ecto.migrate` — clean roundtrip.
- `pre-commit run --all-files` — all hooks pass.

### Completion Notes List

- TDD throughout: pure engine red→green, then context red→green, then meta-test
  and guard-trigger tests.
- **Key design decision (recorded in ADR-0018):** only the root `buckets` table
  is guard-armed. The assignment join tables FK-cascade from
  `securities_accounts`/`cash_accounts`/`securities`, which are deleted through
  contexts that are not yet actor-first (Portfolios is a later leaf-first arming
  slice). Arming them now would make the guard reject legitimate cascade deletes,
  so they are journaled at the application level via `Journal.record/3` but left
  un-armed until the Portfolios actor-first conversion. `write_actor_test`'s
  `@armed_tables` updated to `{"securities", "buckets"}` accordingly.
- **Position override encoding:** single `position_bucket_overrides` table keyed
  on `(securities_account_id, security_id)`; a single `NULL`-bucket row
  (`NULLS NOT DISTINCT` unique index) is the explicit-empty marker, distinct from
  inherit (no rows). All three states pinned by tests.
- **View writes** take an `Actor` first arg (so the P2 AST gate accepts them) but
  do not journal (ADR-0018 §5); a test asserts no journal entry is emitted.
- `Portfolixir.Buckets` registered in `write_actor_test`'s `@context_files` so the
  AST gate now covers it; all its writers are actor-first.
- API/MCP coverage: **n/a** for this story (data model + engine only). The JSON
  API + MCP surface is story #445 (AR-11 parity reviewed there).
- User docs: no `product-documentation.md` change — no user-visible surface yet
  (UI is #446). ADR-0018 added and listed in `docs/decisions/index.md`.

### File List

New:
- `docs/decisions/0018-buckets-tag-based-wealth-scoping.md`
- `priv/repo/migrations/20260618120000_create_buckets_and_views.exs`
- `lib/portfolixir/buckets.ex`
- `lib/portfolixir/buckets/bucket.ex`
- `lib/portfolixir/buckets/securities_account_bucket.ex`
- `lib/portfolixir/buckets/cash_account_bucket.ex`
- `lib/portfolixir/buckets/position_bucket_override.ex`
- `lib/portfolixir/buckets/view.ex`
- `lib/portfolixir/buckets/view_include_bucket.ex`
- `lib/portfolixir/buckets/view_exclude_bucket.ex`
- `lib/portfolixir/engines/bucket_resolution.ex`
- `test/portfolixir/engines/bucket_resolution_test.exs`
- `test/portfolixir/buckets_test.exs`
- `test/portfolixir/buckets/buckets_guard_test.exs`

Modified:
- `docs/decisions/index.md` (ADR-0018 listed)
- `test/write_actor_test.exs` (`@context_files` += Buckets; `@armed_tables` += "buckets")

## Change Log

| Date | Change |
| --- | --- |
| 2026-06-18 | Implemented #443: buckets & views data model, pure resolution engine, actor-first journaled Buckets context, ADR-0018. All gates green; status → review. |
| 2026-06-18 | Code review: 5 patches applied (dedup setters, mixed-state fail-loud guard, deterministic ordering, exactly-one journaling assertions, ADR doc fixes), arming deviation ratified, 4 findings dismissed. All gates green; status → done. |
