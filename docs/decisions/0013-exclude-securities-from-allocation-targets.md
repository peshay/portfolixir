---
layout: docs
title: "ADR-0013: Exclude flagged securities from the allocation steering basis"
description: Decision to let a per-security flag keep a position (e.g. Bitcoin) inside the totals and performance while leaving it out of the allocation steering basis (the 100%) and drift, mirroring the cash-account counts-toward-cash-quote flag from ADR-0009.
---

# ADR-0013: Exclude flagged securities from the allocation steering basis

- **Status:** Superseded by [ADR-0018](0018-buckets-tag-based-wealth-scoping.html)
- **Date:** 2026-06-13

> **Superseded (2026-06-20, #447).** The per-security
> `excluded_from_allocation_targets` flag described here was removed in the
> buckets/views cutover. Its job — carving a position out of the allocation
> steering basis while it still counts toward total wealth — is now done by
> tagging the security with a bucket and excluding that bucket from a view
> (ADR-0018 §4). The separate "outside the steering basis" block is gone; the
> behaviour is reproduced by viewing allocation under a view that excludes the
> bucket. The text below is kept as the historical record of the original
> decision.

## Context

Portfolixir compares a portfolio's actual category weights against stored target
weights and reports the per-category drift (see
[ADR-0008](0008-target-weights-and-allocation.html)). The actual side is a share
of the valued positions' total — the **steering basis**, the 100% the targets
are measured against.

Some holdings should be **visible and valued** but should not be **steered**. The
motivating case is a Bitcoin position held as a long-term store of value: it must
stay in the total value, the holdings, and the performance figures, but it should
not dilute the target mix of the steered part of the portfolio. With no flag, the
operator faces a bad choice: either the Bitcoin distorts every category's actual
percentage and the drift, or it is dropped from the valuation entirely and the
totals stop matching reality.

This is the security-side sibling of the cash-account problem solved in
[ADR-0009](0009-cash-as-balance-snapshots.html): there a reference-only cash
account stays listed and inside the total cash, but the **cash quote** is
computed as if it did not exist (`counts_toward_cash_quote`). The forces are the
same — a position must stay visible in the totals while one specific ratio is
computed without it — so the solution mirrors that pattern.

## Decision

Add a per-security boolean **`excluded_from_allocation_targets`** (default
`false`, non-null), cast and validated on the security changeset exactly like the
cash account's `counts_toward_cash_quote`.

- **Allocation only.** The flag changes only the allocation view. The steering
  basis (the 100%) is the valued positions' total **minus** flagged positions;
  category percentages, target/actual/drift, and the sunburst all compute on this
  basis. The allocation's reported `total_value` is this steering basis.
- **Valuation and performance untouched.** Total value, total including cash,
  the cash quote, holdings, and TTWROR/IRR ignore the flag entirely. A test pins
  this down: the portfolio total is identical whether or not a position is
  flagged.
- **Excluded positions stay visible.** Flagged positions surface in a separate
  `excluded` block ("outside the steering basis: X €", with a per-security
  breakdown) in the allocation result, the API, and the Portfolio page — they are
  moved out of the 100%, not dropped.

The flag is readable and settable over the JSON API and MCP (on the security
object) and toggled in security management, with documentation and a DocsTest,
matching the API/MCP coverage rule.

## Consequences

- An operator can hold a store-of-value position (Bitcoin, physical gold, a
  long-term reserve) that counts toward net worth and performance without
  skewing the SOLL/IST steering of the rest of the portfolio.
- Excluding a position raises every other category's actual percentage
  consistently (the basis shrinks) while the total value is unchanged.
- **Trade-off:** the allocation's `total_value` is the steering basis, not the
  full valuation, so a caller that wants the grand total reads it from the
  valuation endpoint (where it is unaffected) and reads the excluded amount from
  the allocation's `excluded` block. This is documented.
- New surface: one security column and changeset field, an allocation `excluded`
  block, plus API/MCP fields and a UI toggle — each with tests and user
  documentation. The migration is additive and reversible.
