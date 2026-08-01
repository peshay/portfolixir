# UAT walkthrough — Sprint 2 Lane A (#406 + #570), 2026-08-01

Screenshots from the mandatory UAT persona walkthrough of the epic-batch
closing act (ADR-0026), taken on a dev instance seeded with **synthetic
data only** (a "Family Portfolio" with invented securities: Global Index
ETF, Orbital Ventures Corp., Delivered Co., Quiet Industries, Doomed
Holdings). No real financial data appears anywhere.

- `portfolio-data-quality.png` — the Wealth page's data-quality section
  showing all four honest states at once: trade-priced, no price at all,
  price known but no FX rate (with the native price), and the negative
  holding listed per depot with the cross-depot total and transaction link.
- `detail-missing-fx.png` — security detail status line for a priced USD
  security without a stored rate ("Not counted in the portfolio totals …").
- `detail-trade-priced.png` — detail status for a quote-less security
  valued at the last own trade price (counted in totals, price shown).
- `detail-negative-holdings.png` — the holdings tab marking a negative
  per-depot quantity with the "negative quantity" chip.
- `allocation-flat.png` — the flat allocation worklist with the negative
  position chip.
- `classifications-negative.png` — the classification tree marking the
  negative holding in the Unsorted folder.

Walkthrough result: all acceptance criteria of #406 and #570 observed on
the live surfaces; the data-quality link lands on the security's
transactions tab (`/securities/:id?tab=transactions`).
