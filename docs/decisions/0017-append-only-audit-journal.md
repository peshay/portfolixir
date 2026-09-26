---
layout: docs
title: "ADR-0017: Append-only audit journal for financial writes"
description: Decision to record every financial write across UI, API and MCP in an append-only journal written in the same database transaction as the business write.
---

# ADR-0017: Append-only audit journal for financial writes

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

FR-14 lets an LLM agent write financial data through the MCP/API surface.
Once a non-human actor can create, change and delete transactions, accounts
and classifications, **attribution and reversibility stop being a nicety and
become a safety requirement** (PRD FR-28, NFR-2): a hallucinated or erroneous
edit must be detectable, attributable, and traceable after the fact — including
deletions, which today leave no trace.

The codebase already derives every read model from the immutable transaction
history (ADR-0004, ADR-0011), but that history is itself mutable: a row can be
updated or deleted with nothing recorded about who did it, when, or what the
value was before. There are three independent write entry points (LiveView,
the JSON API, the MCP companion via the API per ADR-0002) and several write
contexts (`Ledger`, `Portfolios`, `Classifications`, `Catalog`, `Fx`,
`Imports`). Auditability is only trustworthy if **no** write path can bypass
the record — a convention ("remember to journal") is not enough when an agent
and future contributors keep adding write paths.

The forces that shaped the decision:

- **Atomicity.** A journal entry that can commit without its business write (or
  vice versa) is worse than none — it lies. The two must be one transaction.
- **Engine purity (ADR-0011, architecture D2).** Computation engines are pure
  functions over injected data. Journaling is a side effect and must live in
  the imperative shell (the contexts), never in engines or read-model loaders.
- **Mechanical completeness.** Whether a write is journaled must be enforced by
  the database, not by reviewer vigilance, so that a newly added write path
  fails loudly instead of silently skipping the journal.
- **Append-only.** The journal is the one table that must not be rewritable,
  even by the application role that owns it.

## Decision

Introduce an append-only `audit_journal` table and a single `Portfolixir.Journal`
context that is the **only** writer of it. Every committed financial write
records exactly one journal entry in the **same database transaction** as the
business write.

### Table and schema

- Table `audit_journal`, context `Portfolixir.Journal`, schema
  `Journal.Entry`. Columns: `actor_type`, `actor_label`, `operation`,
  `resource_type`, `resource_id`, `before` and `after` (both JSONB),
  `scenario_id` (nullable), and `inserted_at`. There is **no `updated_at`** —
  rows are never updated.
- `operation` is a closed enum: `create | update | delete | upsert`. `upsert`
  exists because an `on_conflict` write cannot deterministically report whether
  it created or updated.
- `resource_type` is a closed list of stable **string codes** (e.g.
  `"transaction"`, `"cash_account"`) — never module names, so the codes survive
  refactors.

### Append-only enforcement (database level)

Append-only is enforced by PostgreSQL triggers that raise on `UPDATE`, `DELETE`
**and `TRUNCATE`** of `audit_journal`. `REVOKE` alone is insufficient because
the application role owns the table. A standing test issues a real
`UPDATE`/`DELETE` against the table and asserts the raise, so a migration that
drops the trigger turns CI red.

Residual risk (a superuser, or a deliberate data-fix migration) is accepted and
documented. The **named legitimate escape hatch** for a data-fix or restore is
`SET session_replication_role = replica`, which disables triggers for the
session; the first such migration must use it explicitly rather than improvise.
Disaster recovery against the triggers is documented in `docs/backup-restore.md`
(restore runs with `session_replication_role = replica`).

### Single entry point and atomicity

- All journal writes go through one fixed function, `Journal.record/3`, which
  takes an `Ecto.Multi` and returns an `Ecto.Multi` with the journal step
  appended. No journal insert exists anywhere else.
- The business write and the journal insert run in **one** `Repo.transaction/1`
  — both commit or neither. Completeness ("no committed financial write without
  a journal entry") is a testable invariant and an acceptance criterion of the
  journal story.
- `before` is the changeset's `data` serialized; `after` is built in a
  `Multi.run` step placed after the named business step, from that step's
  result. No `Multi` introspection magic. *(Amended in Sprint 16: `before` is
  the row re-read under the write's own lock inside the transaction, `after`
  the row as stored, and an update that changes nothing writes no entry — see
  "Amendment: before-images under the write's lock" below.)*

### Mechanical completeness via a session-variable guard

- Journaled tables carry a guard trigger that requires a transaction-local
  session variable, `portfolixir.journal_actor`, to be set. Only
  `Journal.record/3` (and the allowlisted non-journaled paths) set it, via
  `SET LOCAL`. A raw `Repo.update`/`Repo.delete`/`Repo.insert` on a journaled
  table with no actor set **fails loudly**.
- The guard reads `current_setting('portfolixir.journal_actor', true)` with
  `missing_ok = true`, so an absent variable raises the defined guard exception
  rather than PostgreSQL's `unrecognized configuration parameter`. It rejects
  both `NULL` **and** the empty string: resetting a custom GUC via
  `set_config(name, NULL, true)` leaves an empty string (not `NULL`) on the
  connection, so on a pooled/recycled connection a later un-journaled write
  would otherwise pass an `IS NULL`-only check. Treating `""` as "no actor"
  closes that gap (verified against PostgreSQL 16).
- `Journal.record/3` prepends the `SET LOCAL` step and resets the variable in a
  final step, because under the Ecto SQL sandbox a test's outer transaction
  would otherwise keep the variable alive past the business transaction and hide
  a missing-actor bug. Guard-trigger tests run `async: false` outside the
  sandbox (real commit + cleanup).

### Actor attribution

- `Portfolixir.Actor` is an explicit struct (`type` + optional `label`) passed
  as the **first** positional argument of every public context write function:
  `Ledger.create_transaction(actor, attrs)`. Smuggling the actor through the
  process dictionary is forbidden.
- The actor `type` is a closed taxonomy:
  `owner_ui | api_token_rw | api_token_ro | import_session | system_job`,
  extended only by amending this decision (the Phase-3 sync framework is
  expected to add per-provider types).

### Scope

- Only **committed** writes are journaled. Changeset rejections, constraint
  violations and domain-rule rejections never reach the journal — nothing
  committed, nothing journaled.
- **Deletions are journaled** (the `before` snapshot keeps a deleted record
  traceable; it is not silently gone).
- Bulk imports journal **per-record** entries (a 5 000-row import is 5 000
  entries) with actor `import_session`.
- Persisted what-if scenario writes (FR-27, future) are journaled with a
  scenario marker (`scenario_id`); journal queries default-filter to real
  (non-scenario) writes.
- The journal is **active from activation, with no backfill** — pre-existing
  history is not retro-journaled (operator decision, 2026-06-12). Writes that
  happen before a given context is journaled are a documented audit-trail gap.

### Allowlist of non-journaled writes

Market-data ingestion (quote sync, FX-rate sync) writes operational data, not
financial records, and is **not** journaled. The exempt write paths are a
closed list in one module, `Portfolixir.Journal.Allowlist`, guarded by a
meta-test so the exception set can only shrink, never grow silently. The
`idempotency_keys` table (future, FR/AR write idempotency) is likewise
operational state — not journaled, no guard trigger, never on the allowlist
(the allowlist governs only *journaled-table* writers).

### Read surface

The journal is queryable through the JSON API **and** a matching MCP tool
(API/MCP parity, FR-16/AR-11), with a self-describing response (FR-13: `as_of`,
filters applied, ordering). A UI viewer is explicitly a follow-up; the API/MCP
surface comes first.

### Rollout sequencing

The actor-first signature change and table arming land as **sequenced
per-context PRs**, not big-bang, in leaf-first order
(`Catalog`/`Fx` → `Portfolios`/`Classifications` → `Ledger` → `Imports`). Each
context's journaled tables are armed by their own migration the moment that
context is fully actor-first. A meta-test couples the two mechanically: if a
context's grandfather list is empty but its tables are not armed (or vice
versa), CI fails. This ADR and the journal infrastructure
(`audit_journal` table, append-only triggers, the reusable guard-trigger
function, `Journal`, `Actor`, `Journal.Serializer`, `Journal.Allowlist`) land
first; arming no table, they cannot break existing writes.

### Rollout status

- **Slice 0 — infrastructure (landed):** `audit_journal` table, append-only and
  guard-trigger functions, `Journal`, `Actor`, `Journal.Serializer`,
  `Journal.Allowlist`; no business table armed.
- **Slice 1 — Catalog/Fx (landed):** `Catalog`'s security writes
  (`create`/`update`/`delete`/`set_asset_class` and the search-result writers)
  are actor-first and routed through `Journal.record/3`; the `securities` table
  is armed by its own migration. `Fx`'s only write (`upsert_many` → market-data
  `exchange_rates`) stays allowlisted. The journal read surface ships as
  `GET /api/v1/journal` and the matching `portfolixir.journal.list` MCP tool.
  Logo writes (operational, on `securities`) are journaled under a fixed
  `system_job` actor; the migration-only `backfill_inferred_asset_classes/0`
  keeps its arity (immutable migrations) and is excluded from the actor gate.
  Meta-tests landed: append-only, allowlist, and the AST write-actor gate with a
  shrink-only grandfather list coupling arming to conversion.
- **Slice 2 — Portfolios.portfolios (landed):** `Portfolios.create_portfolio`
  and `update_portfolio` are actor-first and routed through `Journal.record/3`
  (`resource_type: "portfolio"`); the `portfolios` table is armed by its own
  migration. The virtual cash-target weight still persists separately to its
  un-armed target table.
- **Slice 3 — Portfolios accounts (landed):** `create`/`update`/`delete` for both
  cash accounts and securities accounts are actor-first and journaled
  (`resource_type: "cash_account"` / `"securities_account"`); deletions keep the
  referential `{:error, :referenced}` guard and journal the full `before`
  snapshot. The `cash_accounts` and `securities_accounts` tables are armed, so
  **`Portfolios` is now a fully converted context** (in `@converted_contexts`).
- **Slice 4 — Ledger + Imports transactions (landed):** `Ledger.create`/`update`/
  `delete_transaction` and `set_cash_balance` are actor-first and journaled
  (`resource_type: "transaction"`); the `transactions` table — the ledger crown
  jewel — is armed. The import applier now journals each inserted booking under
  `Actor.import_session()` in the same (nested) transaction as the insert, the
  same way it already journals created securities, so imported history is fully
  attributable. `Ledger` joins `@converted_contexts`.
- **Slice 5 — Classifications stage 1 (landed):** custom classification/category
  `create`/`update`/`delete` + `recolor` are actor-first and journaled
  (`resource_type: "classification"`/`"category"`); the `classifications` and
  `classification_categories` tables are armed. **Built-in tree seeding** writes
  under a fixed `system_job` actor — and because the seeding is check-then-insert
  (`Repo.get_by` first), a re-seed on a later read does NOT write, so reads never
  spam the journal; only the genuine first creation journals. `ensure_builtins/0`
  and the read paths that trigger it (`list_trees/0`, `security_category_map/1`)
  journal internally rather than via a first-arg actor, so Classifications is
  journaled but **not** in `@converted_contexts`.
- **Slice 6 — Classifications stage 2 (landed):** `assign_security`/
  `unassign_security` and the bulk `assign_securities`/`unassign_securities` are
  actor-first and journaled; the `security_category_assignments` table is armed.
  A `(security, classification)` upsert journals a `:create` for a new pair or an
  `:update` (with the prior assignment as `before`) when reassigning to another
  category. The bulk paths journal **one entry per affected security** (2(a)),
  all in one transaction. `Classifications` joins `@converted_contexts`.

### Rollout complete

Every context that writes financial data — Catalog/Fx, Portfolios, Ledger,
Classifications — is converted: its public writers are actor-first (or, for
built-in tree seeding, journal internally under a fixed `system_job` actor) and
its tables are guard-armed. The grandfather list is empty. The follow-up #529
(seed built-in trees at startup instead of on read paths) is orthogonal to
journaling and tracked separately.

### Amendment: before-images under the write's lock, and no entry for no change (Sprint 16, F49, G02)

The security review of Sprint 16 (E25, findings F49 and G02 of its triage)
found that a before-image was the struct the caller had read earlier, outside
the writing transaction and without a lock: two writers acting on one read
both claimed the same prior state, and the journal's change history did not
chain. It also found that an update changing nothing copied the whole row
twice into the append-only table. `Journal.record/3` now holds these rules
for every writer at once:

- **The before-image is the row as stored under the write's lock.** For an
  `update`, a `delete` or an `upsert` whose `:before` is a stored row, a step
  `{:journal_lock, step}` runs right after the actor is set and ahead of the
  business write, and re-reads that row under the lock the write itself takes
  — `FOR NO KEY UPDATE` for an update or an upsert, so a booking's
  foreign-key check does not wait, and `FOR UPDATE` for a delete. That row is
  the entry's `before`, and an update's changeset is built on it
  (`Journal.locked_row/2`), so the write and its before-image start from the
  same state. Two writes from one read chain: the second's `before` is the
  first's `after`.
- **The after-image of an update is the row re-read after the write**, as
  stored, not the caller's struct with the changes applied.
- **A row gone by then answers not found**: the lock step fails with
  `:not_found` before anything is written, and the contexts answer
  `{:error, :not_found}` (a 404 over the API; a named message on the pages).
  An upsert whose prior row is gone inserts it afresh, with no before-image.
- **An update that changes nothing writes no entry** (G02), and — since the
  review round — bumps no derived-data basis either: nothing it could affect
  changed. ADR-0017's full `before` and `after` snapshots stay for every real
  change.
- A writer that must hold another lock first keeps its order by taking that
  lock as the transaction's first step, ahead of the journal's: every ISIN
  writer takes the ISIN write lock before the security's row (review round).

Pinned by `test/portfolixir/journal/before_image_lock_test.exs`,
`test/portfolixir/journal/no_op_update_test.exs` and
`test/portfolixir/derived/before_image_radius_test.exs` ("an update that
changes nothing bumps no basis").

### Amendment: two resource codes for the lifecycle merges (ADR-0050 §13)

[ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html) adds two
codes to the `resource_type` list: `merge_record`, one per merge of a cash
account, depot or security (table `merge_records`), and
`retired_import_hash`, one per row a merge removes (table
`retired_import_hashes`). Both tables are append-only (UPDATE, DELETE and
TRUNCATE raise) and armed with the journal-actor guard in the migrations that
create them, and both are written by the `Portfolixir.Lifecycle` context,
actor-first. The operations stay `create | update | delete | upsert`.

### Amendment: the quote exemption covers the sync writers only (Sprint 16, T-9)

The security review of Sprint 16 (E25, finding G27, decision T-9 of its
triage) found that the quote exemption above covered more than market-data
ingestion: the quote upsert of the API, and of the MCP companion through it,
wrote closes an agent or a person authored through the same unjournaled path,
so an authored write could replace a stored close of any source and leave no
before-image. The exemption is narrowed to the writers that ingest:

- **Exempt:** the quote sync (`Portfolixir.Catalog.QuoteSync`, through
  `Quotes.upsert_many/3`) and the exchange-rate sync, as before; and the
  security merge writer of [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html)
  §13 (`Quotes.merge_gap_fill/4`, called by the security merge alone), whose
  moved and dropped quotes are recorded in the append-only merge manifest
  instead, the dropped closes with the target's close that won.
- **Journaled:** every **authored** quote write — the upsert
  (`Catalog.upsert_quotes/3`) and the new release of manual quotes back to
  provider data (`Catalog.release_manual_quotes/4`), over the API and MCP, and
  the demo seeds through the same path. Each is one entry of the new
  `resource_type` `security_quotes`, filed under the security's id (the new
  `:resource_id` option of `Journal.record/3`), operation `upsert` or
  `delete`, with the stored rows it replaced or released as the before-image,
  in the same transaction as the rows. An authored row is always stored as
  `manual` (finding F20), and ADR-0028's rule that a manual close wins over
  provider data stays.

The `security_quotes` table stays unarmed — the sync still writes it without
an actor — so the split rests on the writers: a test pins, from the compiled
call graph, that no module other than the sync calls the unjournaled upsert
under any alias and none other than the security merge calls the merge
writer, and, by a scan of `lib/` and the seeds, that no file other
than the quote module writes the quote schema or the `security_quotes` table
by a Repo write, a changeset or SQL (review round). The operations stay
`create | update | delete | upsert`.

## Consequences

- **Every change to financial data becomes attributable and reversible by
  inspection**, including deletions and agent-made edits — the safety net FR-14
  requires before agents get write grants.
- Adding a new write path is **not** a place to forget journaling: the guard
  trigger rejects an un-journaled write to an armed table, so the failure is
  loud and immediate rather than a silent audit gap.
- The actor becomes a **mandatory first argument** of every public context
  write function. This is a deliberate, wide signature change carried out as
  sequenced per-context refactors; callers in LiveView, API controllers and the
  import applier must thread an `Actor` through. Tests construct writes through
  the real actor-first functions — there is no test-only journaling bypass.
- Engines and read-model loaders stay pure: journaling lives only in the context
  shell (consistent with ADR-0011 and architecture D2). Engines compute; the
  shell writes and journals.
- The journal table grows unbounded by design. Retention and partitioning are a
  named future concern (a follow-up ADR); the table carries indexes on
  `(resource_type, resource_id)`, `actor_type`, `inserted_at` and `scenario_id`
  to keep the read surface usable in the meantime.
- A restore or data-fix must consciously use the `session_replication_role =
  replica` escape hatch; this is documented so the first disaster recovery is
  not the moment of discovery.
- `before`/`after` are stored as JSONB through a single `Journal.Serializer`
  that encodes Decimals as strings and dates as ISO strings (Jason's defaults
  would emit Decimals as floats and lose precision), with a `raise` fallback on
  any unmapped type so a new field cannot be silently dropped from the audit
  record.
