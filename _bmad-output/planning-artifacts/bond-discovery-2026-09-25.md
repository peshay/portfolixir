# Bond discovery — what today's valuation does with a bond (#330)

**Status:** Sprint 16, Lane R ("#330's discovery story" in
`implementation-artifacts/sprint-plan-2026-09-24-sprint16.md`). This is a
verdict with its evidence, not a decision record. Nothing is built on
valuation. The verdict branches on one fact that only the owner's own export
can settle, and the owner can confirm it without any figure entering the
repository.

**Evidence:** `test/portfolixir/portfolios/valuation_bond_characterization_test.exs`,
over the fixture `test/support/fixtures/portfolio_performance/bond_invented.json`.
The fixture is a Portfolio Performance JSON v1 export with one invented bond.
The issuer is made up, and so is the ISIN (`XSEXMPL20355`). Its check digit is
valid, but it has letters in the national part, which no real `XS` number
has. Every amount is invented too. The same bond is imported twice, once in
each reading of the export's `shares` figure, and valued before and after a
percent-of-nominal quote is stored. The test pins today's behaviour. If bond
valuation changes, the test has to be changed on purpose.

## What today's code does

1. **Nothing in the valuation is specific to bonds.** Wherever a position is
   valued (the valuation, the holdings and the performance walk), its value is
   the quantity times the latest price. A stored quote is treated as a unit
   price. The catalog has no field for quotation type, face amount, coupon or
   maturity.
2. **The quantity is the export's `shares` figure, unchanged.** The importer
   derives a buy's price per share as (amount − fees − taxes) ÷ shares. Until a
   quote exists, the valuation prices the bond at that trade price.
3. **The name is enough to classify it.** The existing name inference files
   the invented bond under `government_bond`.
4. **A coupon has no link to the bond.** A coupon booked as INTEREST that
   names the bond lands on the cash account. The importer keeps only the cash
   account for an interest booking.

The same bond in both readings. The figures are synthetic: a face amount of
10,000 EUR is bought at 98.50 % with a fee of 5.00, and a quote of 97.25 is
stored later. After the purchase and one coupon, 370.00 of cash is left.

| | `shares` is a hundredth of the face amount | `shares` is the face amount |
|---|---|---|
| Quantity | 100 | 10,000 |
| Derived trade price | 98.5 | 0.985 |
| Value while priced by the trade | 9,850.00, correct | 9,850.00, correct |
| Value after the 97.25 quote | 9,725.00, correct | 972,500.00, **a hundred times too high** |
| Cost basis | 9,850.00 | 9,850.00 |
| End value of the walk (with the cash) | 10,095.00 | 972,870.00 |
| TTWROR | +2.2 % | +2.2 %, **the same** |
| Wealth multiple | 1.0095 | 97.2870 |

5. **The TTWROR does not show the error.** The bond's first quote arrives
   while the bond is still priced only by its own trade. The walk therefore
   treats that re-pricing as a basis step (#545), and both readings report
   the same return. Every money figure is a hundred times too high in the
   second reading: value, P&L, weight, allocation, wealth multiple and IRR.

## The verdict

#330 bundles two things: master data with key metrics, and a "valuation trap".
The characterization shows that the valuation half depends on the exported
quantity, not on bonds as such.

- **If `shares` is a hundredth of the face amount, #330 shrinks.** Quantity
  times a percent quote is then the face amount times the percentage ÷ 100.
  That is already correct everywhere, with no change, so the valuation half
  of the issue is void. What is left is master data (coupon, maturity,
  payment frequency, denomination) and display-only metrics (remaining term,
  current yield) on the security detail, with API and MCP coverage. That is a
  small Sprint 17 story and not risk-tier. If the owner does not want the
  master data, #330 closes instead.
- **If `shares` is the face amount, #330 grows** into its own ADR, risk-tier
  (ADR-0036). There are two ways to fix it, and the ADR chooses:
  - A quotation type per security. It has to reach the valuation, the
    holdings cost fold, the performance walk (including #545's basis step),
    the pricing context, allocation and drift, the quantities of the
    rebalancing hints, and the API and MCP payloads.
  - The importer converts the quantity on intake. That changes import
    semantics and the re-import contract (ADR-0029, ADR-0050).

  Neither fix is small. Point 5 adds a risk: a half-finished migration would
  not show on the return figure.
- **If the export mixes both** (some bookings one way, some the other),
  #330 grows too. The reading is then a property of each security, which
  needs the same quotation type.

## The one unknown, confirmed privately

The unknown is whether the owner's export books a bond's quantity as its face
amount or as a hundredth of it. Portfolio Performance has no percent
quotation, and booking a hundredth of the nominal is the usual workaround.
That makes the shrink branch the expected one, but only the owner's export
decides it.

To check, open any one bond purchase in Portfolio Performance and compare its
shares with the nominal on the statement. If they are equal, the export uses
the face amount. If the shares are a hundredth of the nominal, it uses the
hundredth. A shortcut gives the same answer: a price per share near 100 means
the hundredth, and one near 1 means the face amount.

The answer on the issue is one word: *hundredth*, *face* or *mixed*. No
figure is needed.

## Observed, but outside the verdict

- **Coupons are not attributed to the bond** (point 4). No per-position
  income figure can see a coupon, and that includes FR-41's income term.
  The FR-41 design-gate record books interest to its remainder row for this
  reason. Whether interest should carry a security is a separate small
  question, not part of #330.
