---
layout: docs
title: "ADR-0019: View-scoped performance treats boundary transfers as external flows"
description: Decision that when performance (TTWROR/IRR) is computed for a view, value crossing the view boundary — e.g. buying an in-view security with out-of-view cash — counts as an external flow to the view, so the slice's return is measured like a self-contained sub-portfolio.
---

# ADR-0019: View-scoped performance treats boundary transfers as external flows

- **Status:** Accepted
- **Date:** 2026-06-19

## Context

[ADR-0018](0018-buckets-tag-based-wealth-scoping.html) introduced buckets and
views, and #444 scopes the analytics to a chosen view. Valuation, allocation and
risk are **snapshots**: scoping them is a straightforward filter of the holdings
(merged in #454). Performance is different — it is a **time series** (TTWROR) and
a money-weighted rate (IRR) computed over a daily walk of the transaction history
(ADR-0011, ADR-0010). Measuring the return of a *slice* of holdings raises a
question the snapshot engines never face:

> When value crosses the view's boundary — for example you buy an **in-view**
> security with cash from an **out-of-view** account — is that part of the
> slice's return, or is it a contribution to the slice?

A time-weighted return only means anything if money the owner moves in or out is
**neutralised**; otherwise a large deposit would read as a huge "gain". For the
whole portfolio the boundary is the portfolio itself (deposits/withdrawals are
the flows). For a view, the boundary shrinks, and an internal transaction can now
straddle it.

## Decision

**Value crossing the view boundary is an external flow to the view.** The view's
performance is measured like a self-contained sub-portfolio.

Concretely, during the scoped daily walk:

- **Only in-view legs touch the state.** A transaction's cash legs are kept when
  their account is in the view; its quantity legs are kept when the position
  `{securities_account_id, security_id}` is in the view. The daily value is
  therefore exactly the view's single-count holdings (positions + cash).
- **The day's flow is the value that crossed the boundary:**
  - **External legs** (deposits, dividends, deliveries, removals — the bookings
    the projection already marks external) count as today, but **restricted to
    the kept (in-view) legs**.
  - **Value-conserving internal transactions that straddle the boundary** (a buy,
    sell, security transfer or cash transfer with at least one in-view and at
    least one out-of-view leg) contribute the **net booked value of their kept
    legs** as a flow. For a trade the quantity side is valued at the negated total
    cash movement (so a fully-in-view trade nets to zero); for a cashless transfer
    the moved quantity is valued at market.
  - A transaction that is **fully in-view or fully out-of-view never straddles**,
    so it contributes no boundary flow.

The two everyday consequences: buying an in-view security with out-of-view cash
is an **inflow** to the view (the asset arrived, funded from outside); buying an
out-of-view security with in-view cash is an **outflow** (money left the slice).

### Why this rule

- **Byte-identical default.** For the unscoped walk every leg is "in view", so no
  transaction ever straddles and the boundary-flow term is always zero — the walk
  reduces to the existing portfolio-level logic. An include-everything view equals
  no view; pinned by a test. The unscoped code path is left untouched.
- **Fees and taxes stay return, not flow.** A single-leg internal cost has no
  out-of-view counterpart, so it never straddles; it reduces the view's value and
  reads as a return drag, exactly as for the whole portfolio.
- **Engine purity (ADR-0011, architecture D2).** The boundary decision is the
  pure `Buckets`/`Engines.BucketResolution` membership test over data the context
  shell injects; the walk stays a pure reduction.

### Scope and limitations

- Quantity legs are filtered per `{securities_account_id, security_id}`, so the
  same security held in two depots with different bucket assignments is scoped
  correctly even though the daily value aggregates price per security.
- The booked value of a trade's quantity side is derived from its cash movement;
  cross-currency trades convert through the EUR hub (ADR-0007) like the rest of
  the walk. Multi-security single-cash bookings (not produced by the supported
  transaction kinds) are apportioned by quantity.
- IRR needs no separate change: it is solved from the same scoped dated flows.

## Consequences

- A view's TTWROR/IRR reflect only that slice's holdings and the money moved
  across its edge — the honest, non-misleading sub-portfolio return.
- Performance gains a scoped walk path beside the unchanged unscoped one; the
  boundary-flow rule is the one new money-math concept and is covered by
  Decimal-exact tests (default identity, in-view subset, straddle inflow/outflow).
- The rule is consistent with how the snapshot engines scope (same membership
  helpers), so all four analytics agree on what "in view" means.
