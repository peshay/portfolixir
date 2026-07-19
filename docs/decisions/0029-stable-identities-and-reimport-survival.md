---
layout: docs
title: "ADR-0029: stable identities and re-import survival — an identity ladder with ISIN-change aliases"
description: Decision that strategy configuration survives a PP re-import through deterministic import-time matching on a stable-identity ladder (ISIN incl. journaled ISIN-change aliases, then WKN, ticker+currency, name+currency, each tier only when unambiguous), with unmatched leftovers surfaced in the preview — and that the FR-35 read-only holdings reconcile is built as a small endpoint rather than closed as a documented procedure.
---

# ADR-0029: stable identities and re-import survival — an identity ladder with ISIN-change aliases

- **Status:** Proposed (owner sign-off pending; [ADR-0026](0026-epic-batch-workflow.html)
  decision gate — E18 implementation stories start only after sign-off)
- **Date:** 2026-07-19

## Context

A fresh Portfolio Performance import that fails to recognise an existing
security creates a duplicate row with a new internal id — and every piece of
strategy configuration keyed to the old row silently stops describing the
portfolio the owner actually holds. That configuration is the accumulated
E13/E15/E16 investment (FR-34, E18): classification trees with category
assignments, named target-plan versions with per-category weights, and
per-view cash targets.

What the import actually does today (verified in
`Portfolixir.Imports.Applier`):

- Securities resolve **by ISIN when present**, else by `(name, currency)`;
  a miss creates a new security. Cash accounts and depots resolve by name
  within the portfolio, with a user-driven mapping step in the LiveView
  path; **user-driven security match overrides are a named but unbuilt
  follow-up** in the applier's own moduledoc.
- Idempotency is two-layered (#533): a content `import_hash` skips exact
  re-inserts, and a formatting-tolerant dedup key over the *resolved* DB
  identity (portfolio, security/account ids, normalized Decimals) skips
  re-imports whose only difference is PP-export drift.

So the golden path — re-import a mutated export into a **live** database —
already mostly works for ISIN-bearing securities. What is actually at risk,
verified against the schemas:

1. **Stored category assignments** are the only strategy data keyed to a
   security (`security_category_assignments.security_id`, FK
   `on_delete: :delete_all`). Built-in trees (`asset_class`, `currency`) are
   derived on read ([ADR-0006](0006-classifications-with-target-weights.html))
   and cannot orphan. Target plans, targets, and cash targets hang off
   `(portfolio, view, classification, category)` — a re-import never touches
   them. The survival problem is therefore precisely a **security identity**
   problem.
2. **ISIN-less securities** (crypto, watch-only, some certificates): `isin`
   is nullable and only unique-when-present. The `(name, currency)` fallback
   breaks on any rename in PP — the import then creates a duplicate and the
   assignments stay on the old, now position-less row. ISIN-only matching
   would orphan exactly these positions; this ADR must decide the fallback.
3. **A changed ISIN** (corporate action rename/ISIN change): the old ISIN no
   longer appears in the export, the ISIN tier misses, and a duplicate is
   created. [ADR-0028](0028-corporate-actions-as-ledger-events.html) §4
   explicitly deferred this slice to this record.

Out of scope here, recorded as the honest limit of any import-time matching:
restoring strategy configuration into a **fresh** database. The PP export
does not carry Portfolixir's strategy data, so no matcher can resurrect what
the database no longer contains — that is FR-29's native backup/export
(#354, still unbuilt), which will serialize strategy config keyed by the
same stable identities decided here. Follow-up note, not FR-34 scope.

Dependencies, verified in code on 2026-07-19:

- **E16's Targets/Plans journal arming has landed**: `Portfolios.Targets`
  ("Every write is journaled … the tables are guard-armed") and
  `Portfolios.TargetPlan` state and implement journaled, guard-armed writes
  ([ADR-0017](0017-append-only-audit-journal.html)); `Classifications` and
  `Catalog` security writes are likewise journaled. The named E18
  precondition is satisfied.
- **FR-30 has shipped**: holdings payloads (JSON API and MCP) carry
  `isin`/`wkn` (verified in `Api.V1.JSON`), which the FR-35 section below
  must weigh.

## Decision

### 1. FR-34 mechanism: import-time stable matching, not a config export format

**Recommended: harden the existing import-time matching into a
deterministic stable-identity ladder (§2).** The strategy configuration
itself is never exported, re-imported, or re-attached — it simply keeps
pointing at security rows that the import reliably recognises instead of
duplicating. This directly serves the golden path (re-import a mutated
export into a live database), builds on matching logic and two-layer
idempotency that already exist and are tested, and adds no new file format.

**Rejected: strategy-config export/import** as the FR-34 mechanism. It does
not fix the golden path (nothing was exported before the re-import that
orphans the config); it introduces a second serialization format to
version and round-trip-test; and it cannot dodge the identity question —
re-attaching an exported assignment still requires deciding *which*
security "the BTC position" now is, i.e. it presupposes the ladder anyway.
Its one real strength, fresh-database restore, is FR-29's backup scope
(see Context) and will reuse the identities decided here.

### 2. The identity ladder, and the fallback for ISIN-less securities

A security in the import stream resolves against existing securities by
descending a fixed ladder; each tier applies only when the field is present
on **both** sides, and only when it selects **exactly one** candidate
(neither `wkn` nor `ticker_symbol` is unique in the schema — verified):

1. **ISIN** — current ISINs first, then the alias table of §3.
2. **WKN.**
3. **`(ticker_symbol, currency)`.**
4. **`(name, currency)`** — today's fallback, kept as the last tier.

Determinism rules, all binding:

- A tier that matches **ambiguously** (two candidates share the WKN) does
  not fall through to a weaker tier and does not silently pick: the entry
  is surfaced in the import preview for an explicit user decision.
- The preview grows the **user-driven security match override** already
  named as a follow-up in the applier (mirroring the existing cash/depot
  mapping step): every to-be-created security is listed with its ladder
  result, and can be remapped to an existing security instead.
- **Config-at-risk warning (FR-7):** when a to-be-created security
  near-matches an existing one (same name in a different currency, same
  ticker, matching alias candidates) **and** that existing security carries
  stored category assignments, the preview flags it — creation still
  requires the user to pass a visible warning, never a silent duplicate
  that strands configuration.
- Matching never mutates the matched security's master data; a rename in
  the export updates nothing implicitly (the owner edits, journaled, when
  intended).

This answers the mandatory ISIN-less question: crypto and watch-only
positions ride tiers 2–4, and where those are absent or ambiguous the
outcome is a *surfaced decision*, not a silent orphan.

**Rejected:** ISIN-only matching (orphans exactly the ISIN-less positions);
fuzzy/normalized name matching (non-deterministic, and a wrong silent match
is worse than a surfaced miss); introducing a synthetic Portfolixir UUID
that PP exports could never carry (dead weight on the import path).

### 3. ISIN change and rename: a journaled catalog alias, not a ledger kind

This decides the rename/ISIN-change slice deferred by
[ADR-0028](0028-corporate-actions-as-ledger-events.html) §4.

**Recommended: a journaled identifier-alias record in the Catalog
context.** Recording an ISIN change (via UI, API, and MCP — AR-11 parity)
moves the security's current ISIN into a `security_identifier_aliases` row
(`security_id`, `former_isin`, `changed_on`, optional note) and writes the
new ISIN onto the same security row, both in one journaled transaction
([ADR-0017](0017-append-only-audit-journal.html)). The §2 ladder's ISIN
tier consults current ISINs first, then aliases; an alias hit is labeled in
the preview ("matched via former ISIN"). A plain rename needs no alias at
all — it is a journaled edit of `name`, and matching does not depend on the
name when a stronger tier holds.

Guards: an alias value that collides with a live ISIN or another security's
alias is rejected; the unique-when-present property of the identity space
is preserved across current ISINs and aliases together.

**Rejected: a first-class ledger kind** (`isin_change`). Unlike a split it
has **no projection effect** — no quantity leg, no cash leg, no external
flow, nothing for any fold to do — so a ledger kind would force every
`effects/1` consumer (AR-7 no-catch-all) to learn a no-op. It is master
data about the security, and the audit journal already gives it the
required traceability. Because the security row itself persists, quote
history, category assignments, and all derived charts continue
uninterrupted — the continuity problem ADR-0028 had to solve for splits
does not arise here. Merger/spin-off (a different security row genuinely
appears) remains the E17 follow-on slice; the alias table is deliberately
shaped so a merger slice can reuse it.

### 4. What "survives" means — the survival contract

Binding enumeration of what a re-import must leave intact, given the
security rows resolve per §2/§3:

- **Classifications:** custom trees, categories, and stored category
  assignments — unchanged rows, same ids. Built-in trees survive trivially
  (derived on read).
- **Target plans:** **all versions** — active, draft, and archived
  ([ADR-0027](0027-plan-versions-and-depot-snapshots.html)), with their
  per-category target weights, names, and statuses. Restricting survival to
  the active plan is rejected: plan history is the point of versioning.
- **Per-view cash targets:** every plan's `cash_target_weight`, including
  the portfolio-wide cash-only plan
  ([ADR-0020](0020-view-bound-soll-plans.html)).
- **Leftovers are surfaced, never dropped (FR-7):** a security that ends up
  with stored assignments but no position after the re-import, and every
  entry the ladder could not resolve unambiguously, appear in the import
  result/preview. No automatic deletion, no automatic reassignment.

**Epic acceptance criterion — the golden-path round-trip test:** a
`DataCase` test imports a synthetic fixture, attaches a custom
classification with assignments, a multi-version target plan, and a cash
target, then re-imports a **mutated** fixture (renamed ISIN-less security,
one changed ISIN routed through a §3 alias, drifted decimal formatting) and
asserts the surviving strategy configuration matches **exactly** — Decimal
values compared with `Decimal.eq?`-exactness, ids unchanged, plan versions
and statuses intact — plus the surfaced-leftover assertions above.

### 5. Sequencing and risk tier

- The named E16 dependency is **satisfied**: Targets/Plans (and
  Classifications, and Catalog securities) journal arming is verified
  landed (see Context). E18 write paths (§3 alias writes, §2 override
  choices that create records) inherit journaled writes from day one.
- Everything touching the applier's matching and idempotency is
  **risk-tier**: dedicated small PRs with real human review (AGENTS.md
  risk-tier exception), not epic-batch content. The two-layer idempotency
  is load-bearing here and must be re-asserted in tests: after an ISIN
  change, a new export carries the new ISIN, so content hashes drift — the
  resolved dedup key (#533) keeps the re-import a no-op **because** the
  alias tier resolves the same `security_id`. That interaction gets its own
  test.
- Order inside E18: §3 alias slice first (it feeds the §2 ladder), then the
  ladder + preview overrides, then the §4 round-trip test closes the epic.

### 6. FR-35 verdict: build the read-only reconcile endpoint

**Recommended: build it** (Story 18.3 proceeds), exactly inside the
boundary pinned in FR-35: the external position list arrives **only** as
user-supplied paste/file content, no network acquisition, no credential
storage, the list is **never persisted**, and the response **embeds the
resolution guidance** ("resolve a difference by booking the missing
transaction of the correct kind; balance snapshots and unpriced deliveries
are last resorts that distort cost basis").

The close-as-documented-procedure outcome was evaluated honestly, as the
epic requires. Its case is real: FR-30 has shipped (verified — holdings
payloads carry ISIN/WKN), so the operating agent can fetch holdings and
compare against a pasted list with no join, and closing costs zero code.
It is **rejected** for three reasons:

1. **The diff is Decimal arithmetic, and NFR-1 says a token predictor does
   not do the ledger's arithmetic.** Per-position quantity deltas computed
   "in the head" of an LLM are exactly the class of silent numeric error
   this project's correctness culture exists to exclude; a pure read-only
   engine computes them exactly.
2. **The guidance must live at the moment of temptation.** FR-35's steering
   text works because it arrives *in the response the agent is looking at*
   when it sees a discrepancy; a procedure document read once (or never) at
   session start does not. FR-32 extends the same warning into the
   `set_balance`/delivery tool descriptions — the reconcile response is the
   third leg of that same defense.
3. **It is the first non-import consumer of the §2 ladder.** External lists
   carry the same messy identities (ISIN-less crypto lines, stale ISINs);
   matching them through the identical ladder — alias hits included —
   dogfoods FR-34's mechanism and keeps one identity semantics, not two.

Shape (binding for Story 18.3): `POST /api/v1/holdings/reconcile` plus an
MCP tool at AR-11 parity; request rows of `identifier` + `quantity`
(optional currency); response per row: the ladder-matched security, ledger
quantity, external quantity, and delta as Decimal **strings**, plus
unmatched external rows and ledger positions absent from the list — both
surfaced, per FR-7 — and the embedded guidance block. Read-only, gap-marker
contract (AR-4), synthetic fixtures only.

## Consequences

- Positive: strategy configuration stops being disposable — the golden-path
  re-import preserves it by construction, with every unresolvable case
  surfaced instead of silently duplicated; the alias record closes
  ADR-0028's rename/ISIN slice without touching projection semantics; the
  reconcile endpoint turns discrepancy handling into exact, guided,
  bookable facts for the MCP-first operator.
- Negative / accepted: the ladder adds matching complexity and a new
  master-data concept (aliases) to the Catalog; tiers 2–4 remain weaker
  identities and an ISIN-less security renamed *and* re-tickered in PP will
  still surface as "decide me" in the preview — deliberate, since the
  silent alternative is worse. The preview grows a security-mapping step
  (more UI surface, mirroring the existing account mapping).
- Fresh-database restore of strategy configuration is explicitly **not**
  solved here; it lands with FR-29's native backup/export (#354), keyed by
  the identities this ADR fixes. Follow-up note per scope lock.
- Import-idempotency and matcher changes are risk-tier throughout (§5);
  weakening either dedup layer to make a batch pass is a review reject.
- **Review status:** per the ADR-0028 precedent, the three-method
  adversarial review round (red team vs. blue team, pre-mortem, edge-case
  walk) runs **before** owner sign-off and is scheduled for the next
  session — this draft is decision-complete but **not yet
  review-hardened**; findings land as amendments to the sections above
  ahead of the sign-off.

## References

- [ADR-0006](0006-classifications-with-target-weights.html) — built-in trees derived on read; custom assignments stored
- [ADR-0017](0017-append-only-audit-journal.html) — journaled writes the alias record and overrides ride on
- [ADR-0020](0020-view-bound-soll-plans.html) — view-bound plans and the cash target that must survive
- [ADR-0026](0026-epic-batch-workflow.html) — decision-gate workflow this ADR follows
- [ADR-0027](0027-plan-versions-and-depot-snapshots.html) — plan versions (all of which survive per §4); E16 journal arming verified landed
- [ADR-0028](0028-corporate-actions-as-ledger-events.html) — §4 defers the rename/ISIN-change slice decided in §3 here
- FR-34/FR-35 — section H in `_bmad-output/planning-artifacts/epics.md`; FR-29 — fresh-DB restore follow-up (#354); FR-30 — shipped ISIN/WKN holdings payloads (#582); FR-7 — surfaced import gaps
- `Portfolixir.Imports.Applier` — current matching and the two-layer idempotency (#533) this decision hardens
- Epic tracking: E18 in `_bmad-output/planning-artifacts/epics.md`
