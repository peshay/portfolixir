---
layout: docs
title: "ADR-0030: position-level SOLL targets — positions as the source of truth, categories as a derived roll-up"
description: Decision to extend portfolio_targets with a nullable security_id so a target row steers either a classification category (unchanged) or an individual position under that category, with a category's effective target rolling up from its position rows, the explicit/position conflict stored non-destructively and surfaced by the target-consistency advisory, delivered as a data-model + context + API/MCP foundation ahead of the editor UI.
---

# ADR-0030: position-level SOLL targets — positions as the source of truth, categories as a derived roll-up

- **Status:** Accepted (owner-directed 2026-07-20; design per owner-authored
  [#481](https://github.com/peshay/portfolixir/issues/481))
- **Date:** 2026-07-20

## Context

Today SOLL target weights ([ADR-0020](0020-view-bound-soll-plans.html),
[ADR-0008](0008-target-weights-and-allocation.html)) are settable only per
classification **category**: `portfolio_targets` is keyed by
`(plan_id, category_id)`, and the allocation engine rolls category targets up to
their parents. Issue #481 (owner, PM hat) records that this does not match how
the maintainer actually steers a portfolio, which is **per individual position**:
the classification should behave like a pivot table over positions, where SOLL is
defined primarily on securities and the category/level SOLL is the auto-summed
roll-up of the positions underneath — the maintainer's real question is *which
position to trim or top up*.

That vision is larger than one slice (auto-distribution, a 100%-per-level UX, an
all-positions SOLL layer, and the allocation-view display of position drift). It
is a **risk-tier money-domain change** to the target model, so it is delivered as
dedicated small PRs with real human review, not inside an epic batch
([ADR-0026](0026-epic-batch-workflow.html) risk-tier exception; *delivery clause
superseded 2026-08-04 by [ADR-0036](0036-risk-tier-rides-the-batch.html) — the
follow-on slices ride the batch, with the risk-tier label governing review depth
instead*). This ADR decides
the **foundation** — the data model, context, and machine-usable API/MCP surface —
and explicitly defers the UI and convenience behaviours to named later slices.

## Decision

### 1. Data model — one nullable `security_id` on `portfolio_targets`

`portfolio_targets` gains a nullable `security_id`. A row targets either:

- a **category** (`security_id` NULL) — unchanged behaviour, today's category
  weight; or
- a **position** (`security_id` set) — a SOLL weight on that individual security,
  which must sit **under** the row's `category_id` (its assignment in the
  classification is that category or a descendant of it; an unassigned or foreign
  security is rejected).

The single `(plan_id, category_id)` uniqueness is replaced by **two partial
unique indexes** so one category row and N distinct position rows coexist per
category:

- `(plan_id, category_id) WHERE security_id IS NULL` — at most one category row;
- `(plan_id, category_id, security_id) WHERE security_id IS NOT NULL` — at most
  one row per position.

A plan additionally carries at most **one position row per security** (fix
round): filing the same security under a second category — against an existing
row or twice within one write batch — is rejected, and a batch naming the same
`(category, security)` pair twice is rejected rather than resolved last-wins;
the ancestor-placement freedom governs where the single row sits, not how many
there are.

Positions are the **source of truth**. A category's **effective** target is:

- the **sum of its position rows** when any position row exists (the roll-up); else
- its explicit category-row value (or none).

This reproduces today's behaviour exactly for a category steered without
positions, while making the pivot's position-first steering the resolved number
once positions are present.

### 2. Conflict rule (the #481 open question) — store both, position sum wins, surface the mismatch

When **both** a category row and position rows carry explicit weights, both are
stored **non-destructively** — neither is dropped or overwritten, preserving
auditability. The effective/steering number is defined: **the position sum
wins** (positions are the source of truth). The divergence between the explicit
category weight and the position sum is **surfaced**, never silently dropped, via
the existing **target-consistency advisory** (the display-only Σ/`child_target_sum`
family in `Portfolixir.Portfolios.Allocation`): the effective-target roll-up
exposes the explicit weight, the position sum, the resolved effective weight, and
a `conflict` flag. Nothing blocks saving either row; the maintainer sees the
mismatch and decides.

The same store-and-surface stance covers **stale position rows** (fix round):
reclassifying or unassigning a security does not move or drop its stored
position rows — a row keeps counting under the category it was filed under
(auditability, no silent math change) — but the roll-up surfaces it: each
position row carries a `stale` flag (`true` when its security no longer sits
under the stored category in that classification) and the category roll-up a
`has_stale` flag; re-filing the row is the operator's move. `duplicate_plan`
copies rows as-is without re-validating them during the copy — a stale or
since-invalidated row survives the copy deliberately, and the carried
`stale`/`has_stale` flags provide the visibility on the copy.

### 3. Scope of this slice — data model + context + API/MCP only

Delivered here:

- the migration, schema/changeset, and `Portfolixir.Portfolios.Targets` context
  functions to set/read/delete position targets and compute a category's
  effective roll-up, on the same actor-first, journaled write path
  ([ADR-0017](0017-append-only-audit-journal.html)) as the category functions —
  position-target writes are journaled;
- the JSON API and MCP companion coverage (AR-11): position targets are written
  through the existing `set` endpoint/tool by adding a `security_id` to an entry,
  and read through a dedicated position-targets endpoint/tool that also returns
  the per-category effective roll-up (financial weights as strings). Category-only
  payloads are unchanged (back-compat).

Explicitly **deferred** to later slices, each its own reviewed change:

- the **classifications editor UI** for per-position SOLL entry;
- **auto-distribution** of a category weight evenly across its positions
  (#481 "evenly by default") — and the weight-by-IST / manual-override variants;
- the **100%-per-level firmness UX** (the "Summenspiel"), including graceful
  handling of new/not-yet-bought positions;
- any **allocation-view** position-level SOLL/IST/drift display (this slice does
  not change the `Allocation` breakdown; category reads stay category-only so the
  existing roll-up is untouched). *Delivered by slice 2a below (2026-07-21).*

The gated rebalancing guidance (FR-12, [ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html))
boundary is unchanged: this model is display/steering input only — nothing here
creates, stores, or transmits an order.

### 4. Slice 2a (2026-07-21) — allocation-view wiring

The deferred **allocation-view display** is now live (#481 slice 2a), driven by
an owner-reported bug: the allocation page showed only positions with holdings,
so SOLL set on not-yet-owned positions — the point of position-level SOLL — was
invisible. The owner's display rule is the binding acceptance criterion,
verbatim:

- A position row is shown when it has holdings in scope OR a position SOLL
  target > 0 in the active view's plan.
- A position with SOLL > 0 and zero holdings shows with IST 0 (weight 0,
  value 0) and full underweight drift — it tells the owner "this needs buying".
- A position is hidden ONLY when SOLL is 0/absent AND holdings are zero.

Concretely, in `Portfolixir.Portfolios.Allocation` (and through the JSON API
and MCP allocation surfaces, additively):

- per category, the position rows are the **union** of the in-scope held
  positions and the active plan's position-target rows, matched by security;
  each row carries `target_weight` (its position SOLL, `nil` when none),
  `held`, and — with its own SOLL — its own ADR-0023 drift
  (`drift_weight`/`drift_value`) plus the indicative rebalance quantity. A
  SOLL-only row prices that quantity at the **latest stored quote** (base
  currency) and carries that quote's date as `quote_date` so the hint states
  its price basis; without a price no quantity is invented (`nil`);
- **held means holdings presence** (fix round): any in-scope position with a
  non-zero quantity counts as held, valued or not — a held-but-unpriceable
  security is never re-labelled "not held" and never receives a fabricated
  latest-quote buy hint (it keeps the existing unvalued surfaces). Inside a
  named view the not-held marker reads scope-aware ("not held in this view"),
  since view-scoped absence says nothing about the whole depot;
- **unassigned entries attach their position SOLL too** (fix round): a
  held-but-unassigned security whose (stale) SOLL row still steers its filed
  category's Σ shows that SOLL on its unassigned row. Each entry with an
  attached SOLL row carries the row's `stale` flag so the affected row itself
  is markable, and the breakdown's `deep_target_sum` (the per-subtree topmost
  targeted level, summed) lets the header explain a 0% top-level Σ over a
  plan steered deeper in the tree;
- the category's SOLL in the allocation is now the **effective** target from
  §1 (explicit-or-position-sum; the position sum wins when position rows
  exist), with `conflict` and `has_stale` carried through so the view badges
  them — this closes the UAT conflict-window finding where the allocation
  steered by the explicit weight while the roll-up disagreed. The Σ family
  (`child_target_sum`, `top_level_target_sum`, parent roll-up) consumes the
  same effective values. Categories without position rows behave exactly as
  before (explicit weight; asserted by test).

Still **deferred** to named later slices: the **classifications editor UI** for
per-position SOLL entry, **auto-distribution** (even split and its variants),
and the **100%-per-level firmness UX**.

## Consequences

- Positive: the maintainer's position-first mental model is representable and
  fully usable over the API/MCP now; a category's effective target derives from
  its positions instead of being hand-maintained; the conflict case is auditable
  rather than lossy. The change is additive — existing category plans, their
  reads/writes, and the allocation breakdown behave exactly as before.
- Negative / accepted: `portfolio_targets` now carries two row kinds behind two
  partial indexes, so the upsert conflict target is chosen per row kind and
  category-only reads must filter `security_id IS NULL` to avoid corrupting the
  category-keyed maps that callers (the allocation engine) build. The
  effective/roll-up and 100%-per-level semantics for the allocation view are not
  yet wired in — that is a named follow-on slice. The classifications-page
  "copy from view" prefill shows blanks for categories steered only through
  position rows (the slice-2 editor picks this up). A positions-only first
  write materialises an active plan whose category list looks empty —
  consistent with the pre-existing empty-plan state.
- Risk tier: this and every follow-on slice ship as dedicated small PRs with
  human review; the owner reviews behaviour on the PR against #481.
  *(Superseded 2026-08-04 by [ADR-0036](0036-risk-tier-rides-the-batch.html):
  the slices ride the batch. The owner's behaviour review against #481
  stands — only the PR granularity changes.)*

## References

- [ADR-0008](0008-target-weights-and-allocation.html) — target weights and target/actual allocation
- [ADR-0017](0017-append-only-audit-journal.html) — journaled financial writes this write path follows
- [ADR-0020](0020-view-bound-soll-plans.html) — view-bound SOLL plans the target rows hang off
- [ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html) — the display-only rebalancing-hint boundary
- [ADR-0026](0026-epic-batch-workflow.html) — risk-tier dedicated-PR delivery
- Issue #481 — owner-authored product direction (position-first SOLL, categories as a derived pivot); #335 — cash in the 100% basis
