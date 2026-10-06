---
layout: docs
title: "ADR-0052: bond master data in dedicated columns, read with display-only metrics"
description: "The decision #330 asks for, recorded by its story (Sprint 18 PR γ, U7). A bond's coupon, payment frequency, maturity, issue date and denomination are six typed, nullable columns on securities, not keys of the free-form attributes map. Under Portfolio Performance's hundredth convention the nominal held is quantity × 100; remaining term, current yield and a linear yield to maturity are computed at read, display only, each with its basis; a bond priced on two scales is named, never converted."
---

# ADR-0052: bond master data in dedicated columns, read with display-only metrics

- **Status:** Accepted: a story-level decision, recorded by #330's story
  (Sprint 18 PR γ, U7, as rescoped by the Sprint 17 plan's D-13) and
  adopted by the merge of Sprint 18's PR γ (#1054). Not risk-tier: nothing
  here changes how a position is valued.
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
   interest, fees and taxes are excluded. A matured bond has no yield. Nor
   has a bond whose price is the last own trade price at **at most 5**
   (`price_on_unit_scale`): the two-scales band's mirror, 100 ÷ 20, the
   price per unit of a booking that recorded the nominal as the quantity,
   which is not percent of face; the guard of §4 cannot name it without a
   quote. A stored quote is used at any level. Each metric carries its
   computation basis in the API and MCP payload.
4. **The two-scales guard names; it does not convert.** A bond whose latest
   stored quote is between 20 and 500 times a booked price per unit is
   named as priced on two scales: the export then booked the nominal as the
   quantity, and every money figure of the bond is a hundred times too high
   while the TTWROR hides it (bond discovery, point 5). A booked price per
   unit is a buy's or a priced inbound delivery's: since #779 a delivery's
   booked price opens its lot and drives its flow as a buy's does. The guard
   is silent without a quote, for agreeing scales and for every other asset
   class.

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
- Both rules read a price, not the intent behind it, and each has a known
  false positive. A distressed bond legitimately booked at about 3 % of par
  and quoted at 65 sits inside the guard's band (65 ÷ 3 ≈ 22) and is named
  as priced on two scales; the note asks for the quantity to be checked
  against the statement and converts nothing, so the false positive costs
  one check. The same bond before its first quote meets §3's rule: its own
  trade price is at most 5, so both yields read *not computable* with the
  reason rather than a figure, and the first stored quote restores them.
  Neither is fixed by a threshold: a bond near par booked at its nominal
  (about 1 per unit) and a distressed bond booked in hundredths at about 3 %
  of par (3 per unit) both sit under 5, and only the statement tells them
  apart.

> **Note 2026-10-06 (#1068, Sprint 19 plan D-15):** the merge of the Sprint
> 19 planning PR adopted D-15, which reverses two statements of the
> Consequences above. §1 to §4 stand as taken: the columns, the hundredth
> convention, the display-only metrics, and a guard that names and converts
> nothing. What changes:
>
> - **The reverse case is named.** "It needs a quote stored in a
>   convention the catalog does not have" was a reason not to *convert*, not
>   a reason to stay silent. A bond whose latest stored quote is 1/500 to
>   1/20 of a booked price per unit, both ends included — the forward band
>   inverted, quotes near 1 beside bookings near 100 — counts a hundred
>   times too low in every total. The quote itself must be on the unit
>   scale, at most 5 (100 ÷ 20, the constant §3 already uses): a percent
>   quote of 98.5 beside a booking of 4,925 per piece is a denomination
>   booked per piece, not quotes near 1. The engine reports the case with
>   `direction: :reverse` (`direction: :forward` for §4's case, which is
>   reported where a bond's bookings fall in both bands). Wealth names it in
>   a problem note of its own, `dq-two-scales-reverse`, each name linking to
>   the security's Quotes tab, and the detail read's `bond.two_scales`
>   carries its direction. The security's own Overview does not name it yet
>   (#1112). Nothing is converted.
> - **A bond with no class is no longer out of reach.** The guard, and the
>   bond reading with it (`Portfolixir.Portfolios.Bonds.bond?/1`), reads a
>   security as a bond when its effective asset class is `bond` or
>   `government_bond`, **or** when it has no asset class as shown — none
>   stored and none inferred, which is what the list and the dialog show —
>   and carries this record's master data, a maturity date or a coupon rate,
>   under a name the inference does not read as a structured product's. That
>   is the one place §1's "read only while the effective asset class is
>   `bond` or `government_bond`" widens. It does not widen to every
>   unclassed security, which would name an unclassed share that rose
>   twentyfold, nor to a certificate whose expiry is stored as a maturity
>   date; and a security shown under any other class, stored or inferred,
>   stays no bond, whatever master data it keeps. A bond named without a
>   class carries the neutral "no asset class" badge, and the security
>   dialog shows its bond data while its class reads blank.
>
> And one consequence that was DESIGN.md's rather than this record's: the
> Overview's data-quality line now counts the bonds priced on two scales,
> in either direction, at problem severity, and links to the
> `dq=two_scales` list, a `Portfolixir.Catalog.DataQuality` predicate, so
> the count equals the list. The count is **catalog-wide on purpose**, and
> keeps sold-out, retired and benchmark bonds: what such a bond inflates or
> deflates is not only today's total but its booked history — its past
> values and its realized result — which stays wrong until the bookings or
> the quotes are corrected. The two false positives above are unchanged:
> the reverse band mirrors the forward one, so a bond legitimately booked
> near par and quoted at under 5 % of it would be named the same way, and
> costs the same one check.
