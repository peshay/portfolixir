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
  result. No `Multi` introspection magic.

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
  un-armed target table. The context's remaining writers (`cash_accounts`,
  `securities_accounts`) stay grandfathered until their own follow-up slices arm
  those tables, so `Portfolios` is not yet a fully converted context.
- **Next slices:** Portfolios `cash_accounts`/`securities_accounts` →
  Classifications → Ledger → Imports, one table/context per iteration, each
  arming its tables as it becomes actor-first.

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
