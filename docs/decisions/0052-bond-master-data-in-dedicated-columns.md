---
layout: docs
title: "ADR-0052: bond master data in dedicated columns, read with display-only metrics"
description: "The decision #330 asks for, recorded by its story (Sprint 18 PR γ, U7). A bond's coupon, payment frequency, maturity, issue date and denomination are six typed, nullable columns on securities, not keys of the free-form attributes map. Under Portfolio Performance's hundredth convention the nominal held is quantity × 100; remaining term, current yield and a linear yield to maturity are computed at read, display only, each with its basis; a bond priced on two scales is named, never converted."
---

# ADR-0052: bond master data in dedicated columns, read with display-only metrics

- **Status:** Accepted. Recorded by the story that builds it, #330 (Sprint 18
  PR γ, U7, as rescoped by the Sprint 17 plan's D-13); the merge of PR γ
  adopts it (ADR-0026 step 1, as amended on PR #780: the merge is the
  signature). Not risk-tier: nothing here changes how a position is valued.
- **Date:** 2026-10-03

## Context

A bond imported from a Portfolio Performance export is a bare security: the
catalog has no coupon, maturity or denomination. The issue's first criterion
asks whether that master data goes into dedicated columns or into the
`attributes` map the security already carries.

`attributes` is a free-form JSONB map. Any writer may add any key, a `nil`
removes one, and the changeset bounds it only as text
(`Text.validate_map/3`, `Security.protect_attributes/1`). The securities list
shows its keys as columns, but filtering on them is off in v1 and the range
operators are blocked for them (`SecurityFields`, `jsonb_range_block?/2`).

The discovery verdict (`bond-discovery-2026-09-25.md`) and the owner's
answer (*hundredth*, 2026-10-01) settled the valuation: the export books a
percent-quoted bond's quantity as a hundredth of its face amount, so quantity
× a percent quote is already the market value. No quotation type is needed.

## Decision

1. **Six nullable, typed columns on `securities`:** `coupon_rate`
   (`numeric(9,6)`, percent of face per year, 2.5 not 0.025, from 0 to 100),
   `coupon_frequency` (`annual` or `semi_annual`), `maturity_date`,
   `issue_date` (optional, before the maturity), `face_value` (`numeric(20,6)`,
   the denomination, above 0) and `face_value_currency_code` (a supported
   currency). `Security.changeset/2` validates them like every other column,
   and the shared sweeps (bounded decimals, bounded dates, closed sets) cover
   them by construction. Nothing is required. The values are kept when the
   asset class changes. They are read only while the effective asset class
   is `bond` or `government_bond`.
2. **The quantity convention is stated wherever the face amount is derived:**
   one unit of the holding is a hundredth of the face amount, so the nominal
   held is quantity × 100 in the face value's currency (the security's when
   none is set). The screen's cell and the API's `nominal_held` both say so.
3. **Display-only metrics, scope-ladder level (a), computed at read, never
   stored.** Remaining term counts calendar days from today to the maturity,
   in years of 365 days. Current yield is coupon ÷ price. The yield to
   maturity is the linear approximation (coupon + (100 − price) ÷ remaining
   years) ÷ price, without compounding. The price is the one the valuation
   uses: the latest stored quote, or the last own trade price when there is
   none. Yields are ratios rounded at scale 6, as in ADR-0047. Accrued
   interest, fees and taxes are excluded. A matured bond has no yield. Each
   metric carries its computation basis in the API and MCP payload.
4. **The two-scales guard names; it does not convert.** A bond whose latest
   stored quote is between 20 and 500 times a booked buy price per unit is
   named as priced on two scales: the export then booked the nominal as the
   quantity, and every money figure of the bond is a hundred times too high
   while the TTWROR hides it (bond discovery, point 5). The guard is silent
   without a quote, for agreeing scales and for every other asset class.

**Why columns.** Typed columns give field errors for free: the security
dialog and the API's 422 already name the failing field, and an impossible
date or a coupon of 250 is refused on its own field. With the map, each key
would need its validation re-implemented and its error mapped back to an
input. Columns can later be filtered and sorted ("matures before 2028")
with the operators the list already has for dates and decimals. And a read
of a column never meets a shape no writer validated, which the map allows.
An embedded schema inside `attributes` was rejected for the same reasons: it
would still be JSONB, still unfilterable, and it would sit outside the
sweeps.

## Consequences

- Six columns on every security row, null for everything but bonds; the
  security payload grows by six keys, and the detail read by a `bond` block
  for the two bond classes. The migration adds nullable columns only, with
  no constraint, so no stored row can stop the upgrade.
- Coupons booked as INTEREST stay unattributed to the bond (#928); no
  per-bond income figure exists. A coupon schedule, accrued interest, an
  exact (iterated) yield, yield curves, automatic sourcing and a quotation
  type stay out of scope (#330's non-goals). A future export that proves the
  face-amount convention reopens the quotation type, not this record.
- The guard keys on the effective asset class, so a bond with no class and a
  name the inference does not recognise escapes it. The reverse case (quotes
  near 1, bookings near 100) is not named: it needs a quote stored in a
  convention the catalog does not have.
