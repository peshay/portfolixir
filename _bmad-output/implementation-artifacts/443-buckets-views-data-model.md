# Story: Buckets & views — data model (GitHub #443)

Status: ready-for-dev

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

- [ ] **Task 0 — Author ADR-0018** (AC: 8)
  - [ ] Create `docs/decisions/0018-buckets-tag-based-wealth-scoping.md` with Jekyll
        frontmatter (`layout: docs`, `title:`, `description:`), Status: Accepted,
        Date: 2026-06-18. Model it on `0013-...md` / `0017-...md`.
  - [ ] Capture every locked parameter above, plus §4 (this generalizes
        `excluded_from_allocation_targets`/ADR-0013 — but ADR-0013 is **superseded
        later**, in #447, not here) and §5 (assignment journaled, view-definition not).
  - [ ] **Resolve and document the write-actor reconciliation** (Critical Finding #3):
        how view-definition writes (not journaled) satisfy the P2 `write_actor_test.exs`
        AST gate. State the chosen mechanism in the ADR.
  - [ ] Add the entry to `docs/decisions/index.md` (keep `docs_test.exs` green).
- [ ] **Task 1 — Migrations** (AC: 1) — additive, reversible, raw-SQL triggers
  - [ ] `buckets` table (name, optional color, timestamps; unique name).
  - [ ] Default-bucket link tables for **both** `securities_accounts` and
        `cash_accounts` (many-to-many: depot/cash-account ↔ bucket).
  - [ ] Position-level override table keyed on **(securities_account_id,
        security_id)** — NOT a holdings row (holdings are derived, ADR-0004). Must
        represent "explicit-empty" distinctly from "inherit" (see Dev Notes).
  - [ ] `views` table (name + include/exclude bucket sets; global).
  - [ ] **Arm the journaled bucket-assignment tables** with the existing
        `portfolixir_require_journal_actor` guard trigger (copy the
        `arm_securities_journal` migration shape). Do **not** arm `views`.
  - [ ] New migration timestamp **after** `20260616120000` (e.g. `20260618120000`).
- [ ] **Task 2 — Schemas** (AC: 1, 2, 3) — `Ecto.Schema` + changeset per existing style
  - [ ] Bucket, default-assignment, position-override, view schemas with closed-enum
        discipline and explicit validations.
- [ ] **Task 3 — New context, actor-first + journaled** (AC: 4)
  - [ ] `Portfolixir.Buckets` (or `Portfolios.Buckets`) is the **only** writer.
  - [ ] Every journaled write follows the **P9 write path** (Dev Notes) with
        `Actor` as the **first positional arg** and `Journal.record/3` in the Multi.
  - [ ] View-definition CRUD: not journaled — but still satisfy the write-actor gate
        per the ADR-0018 decision from Task 0.
  - [ ] Add new `resource_type` string codes (e.g. `"bucket"`,
        `"bucket_assignment"`) — stable codes, never module names.
- [ ] **Task 4 — Pure resolution helpers** (AC: 5) — live under `Portfolixir.Engines.*`
  - [ ] `effective_buckets(holding_key, …)` — depot default unless overridden;
        explicit-empty ⇒ no buckets; inherit ⇒ depot defaults.
  - [ ] `holdings_matching_view(view, holdings, …)` — `{include|:all, exclude}`,
        **exclude wins**.
  - [ ] **No `Repo`, no clock, no config inside these helpers** (P3 engine purity).
- [ ] **Task 5 — Tests** (AC: 2, 3, 5, 6, 7)
  - [ ] DataCase tests: inheritance, per-position override, explicit-empty vs inherit,
        multi-tag, view filter algebra (include, `:all`, exclude-wins).
  - [ ] **Double-count guard meta-test** (AC 6): single-count universe under any view
        ≤ unfiltered total; per-bucket overlap never summed as a partition.
  - [ ] Journaling tests: a bucket-assignment write produces exactly one journal entry
        with correct actor + before/after; a view-definition edit produces **none**.
  - [ ] Guard-trigger negative test (`async: false`, outside sandbox): a raw write to an
        armed bucket-assignment table with no actor **raises** (mirror
        `test/portfolixir/journal/append_only_test.exs` style).
- [ ] **Task 6 — Gates & docs**
  - [ ] `mix format`, `mix test`, `mix coveralls`, `pre-commit run --all-files`.
  - [ ] Confirm `write_actor_test.exs` / journal allowlist meta-tests pass with the new
        context (it cannot be grandfathered — grandfather lists only shrink).
  - [ ] API/MCP coverage: **n/a for this story** (data model only; API/MCP is #445) —
        state this explicitly in the PR body.
  - [ ] User docs: data-model-only, no user-visible surface yet → note "no
        `product-documentation.md` change; UI lands in #446" in the PR.

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
view-definition edits are **not** journaled. Reconcile this in the ADR (Task 0). Two
viable options to choose between and record:
  - **(a)** View-CRUD still takes `Actor` as its first arg for signature uniformity,
    but does **not** call `Journal.record/3` (satisfies the AST gate; no journal row).
  - **(b)** Add `views` to a non-journaled allowlist category — but note the allowlist is
    documented as *shrink-only* for *market-data* exemptions; growing it needs an explicit
    ADR justification. Option (a) is the lower-friction path; confirm with Andi if unsure.

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
- Module naming: the issue allows `Portfolios.Buckets` **or** `Buckets`. `architecture.md`
  lists `Actor`/`Journal` as top-level value/context modules; **recommend a top-level
  `Portfolixir.Buckets` context** (it owns cross-cutting tags over depots, cash accounts
  and positions, so it is not strictly a child of `Portfolios`). Confirm with Andi if a
  strong preference exists; either is acceptable per the issue.
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

(to be filled by the dev agent)

### Debug Log References

### Completion Notes List

### File List
