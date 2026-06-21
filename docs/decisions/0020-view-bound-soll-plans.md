---
layout: docs
title: "ADR-0020: target plans belong to a view"
description: Decision that allocation target weights (the target plan) and the cash target become a per-view plan keyed by (view, classification), with view_id NULL as the portfolio-wide "Gesamt" plan, so each view carries its own coherent 100% steering plan instead of a single global target set.
---

# ADR-0020: target plans belong to a view

- **Status:** Accepted
- **Date:** 2026-06-20

## Context

[ADR-0018](0018-buckets-tag-based-wealth-scoping.html) introduced buckets and
views, and #444 scoped the analytics so the **actual** side of the
target/actual allocation runs against a chosen view (valuation/allocation/risk accept
a `view`). [ADR-0013](0013-exclude-securities-from-allocation-targets.html) — the
per-security exclude flag — was retired in #447 in favour of "exclude a bucket
from a view".

The **target** side did not move with it. Target weights live in
`portfolio_targets` keyed by `(portfolio, classification, category)`, and the
cash target is a single column `portfolios.cash_target_weight`
([ADR-0008](0008-target-weights-and-allocation.html),
[ADR-0006](0006-classifications-with-target-weights.html), #335). Both are
**global** — they have no view dimension. Once the actual became view-scoped this
created two problems:

1. **No multiple coherent plans.** A maintainer who steers a stock-strategy view
   to 100% *and* a separate crypto view to 100% using the same classification
   cannot: the target weights are shared, so the Σ-check sums to ~200%. There is
   no way to say "within *this* view, this is my 100% plan".
2. **A latent bug.** Under any view, `Portfolixir.Portfolios.Allocation` still
   loads **all** targets for the classification regardless of scope. A category
   that is out of the view's scope but carries a target renders as a **ghost
   row** (0 € actual, full target, −100% drift) and is counted into
   `top_level_target_sum`. (`kept_categories` keeps any category that has a
   target; `top_level_target_sum` sums every root target.) So the target side is
   incoherent under any non-total view even for a single plan.

A target only means something against a scope. A view **is** a scope. So the
plan should belong to the view.

## Decision

**A target plan belongs to a view.**

- Targets become keyed by **(view, classification, category)**. A nullable
  `view_id` is introduced; **`view_id = NULL` is the "Gesamt" (total) plan** —
  the portfolio-wide plan that reproduces today's behaviour.
- A view may carry its **own** plan per classification, **or none**. With no
  plan, the portfolio page shows that view's allocation **actual-only** (no target,
  no drift, no Σ-vs-100%).
- The **cash target** moves into the plan (per view), replacing the single
  global `portfolios.cash_target_weight`. The cash quote itself is unchanged;
  only the *target* for cash becomes part of the plan.
- The active view loads **only its own plan**. Σ, per-row drift, the cash row
  and `top_level_target_sum` are therefore computed over a single coherent plan,
  and the ghost-row / 200% problem is **fixed by construction** (no foreign
  targets leak in).
- **Editing** lives on the **classifications page** with an added view selector
  ("Soll-Plan für Sicht: [Gesamt ▾]"); **viewing** stays on the **portfolio
  page**, driven by the existing view switcher (#446). A deep-link from the
  portfolio drift table opens the editor with the view + classification
  pre-selected, so a plan is never edited fully blind to the actual.
- **API/MCP parity** (AR-11): the target read/write endpoints and the matching
  MCP tool gain a `view` parameter (null = Gesamt); financial decimals serialize
  as strings. The per-plan cash target is readable/writable there too.

### Migration — loss-free, into the Gesamt plan

There is **no behavioural migration**: existing `portfolio_targets` and the
existing `portfolios.cash_target_weight` become the **Gesamt plan**
(`view_id NULL`). The maintainer's current setup simply appears under "Gesamt".
The data migration carries the values over before the old `cash_target_weight`
column is removed, and is reversible.

### Resolved parameters

These were decided with the maintainer (Andi) on 2026-06-20 and are part of this
Accepted decision:

1. **A plan is `(view, classification)`.** The same classification can carry a
   different plan per view, or none. `view_id NULL` = Gesamt.
2. **Cash target is part of the plan** (per view), not a global portfolio field.
3. **Editing on the classifications page** (with a view selector), not the
   portfolio page; the portfolio page stays the read/actual surface and links into
   the editor.

## Consequences

- A maintainer can steer several views as independent 100% plans (e.g. a stock
  strategy and a crypto sleeve), each with its own coherent Σ — exactly the
  case that motivated buckets/views in the first place.
- The current ghost-row / >100% incoherence under a view disappears, because
  only the active view's plan is ever loaded into the breakdown.
- **Trade-off:** more schema than a single global target set — a plan now has a
  `view` dimension and owns its cash target. The "Gesamt" plan keeps the simple
  case (one portfolio-wide plan) working unchanged.
- **Trade-off (accepted):** editing a plan on the classifications page is one
  step removed from the actual it is measured against; the deep-link from the
  portfolio drift table mitigates this.
- Larger surface: a migration that carries data, engine changes to load the plan
  by `(view, classification)`, API/MCP `view` parameter + cash-target move, and
  UI on both the classifications (editor) and portfolio (viewer) pages.
- Net worth and the actual stay exactly as they are; this decision only changes
  where the **target** numbers live and how they are scoped.

## References

Epic #463 and its stories. Builds on ADR-0018 (buckets & views), follows the
retirement of ADR-0013 (#447). Supersedes the *global* placement of target
weights / cash target from [ADR-0008](0008-target-weights-and-allocation.html)
and #335 — the target/actual drift mechanics themselves are unchanged.
