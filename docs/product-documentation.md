---
layout: docs
title: Product Documentation
description: Portfolixir app handbook for current local portfolio tracking behavior.
lang: en
lang_en: /product-documentation.html
lang_de: /de/product-documentation.html
---

# Product Documentation

## Overview

Portfolixir is a self-hosted, local-first Phoenix application for managing a
single portfolio workflow. It is intentionally narrow:

- Manual creation of securities, portfolio, accounts, and transactions.
- Bulk import of Portfolio Performance CSV/JSON v1 transaction exports through
  a preview-and-apply workflow.
- Holdings are derived from transaction history, with cost basis and unrealized
  profit/loss.
- Classification trees organise securities; per-category target weights drive a
  SOLL/IST allocation breakdown with drift.
- Multi-currency portfolios are valued through stored exchange rates.
- Security prices are stored as quote history and shown in a security detail chart.
- Supported functions are available through the UI, JSON API, and MCP companion.
- No broker sync, bank sync, trading engine, payment flow, order flow, rebalancing,
  document ingestion, or AI-assisted behavior.

## Product Modules

The codebase is split into local domain modules plus the web layer:

- `Portfolixir.Catalog`
  - Securities and quote entities
  - Security metadata and quote records
- `Portfolixir.Portfolios`
  - Portfolios
  - Cash accounts
  - Depots
  - Target weights and SOLL/IST allocation
- `Portfolixir.Ledger`
  - Manual buy/sell transactions
  - Holdings calculation from immutable history
- `Portfolixir.Classifications`
  - Custom and built-in classification trees and assignments
- `Portfolixir.Fx`
  - Exchange rates and multi-currency conversion
- `PortfolixirWeb`
  - Routes, pages, LiveViews, and JSON API
- `mcp-server/`
  - TypeScript MCP companion that wraps the JSON API

Integration details for `/api/v1` and `mcp-server/` are documented separately in
[API and MCP](integration/api-and-mcp.html).

## Core Workflow

1. Create one or more securities with basic identifying data.
2. Create a portfolio.
3. Create one cash account and one depot, and link them.
4. Record manual buy and sell transactions with Decimal-based quantity and price values.
5. Optionally import a Portfolio Performance transaction export through
   Imports, review the preview, map missing accounts, then apply atomically.
6. Open the holdings view to verify current position per security.
7. Record security quotes over time and keep history for reproducible charts.
8. Review current holdings and quote chart behavior directly in the app.

## Securities

Each security is a first-class object with stable identity fields and market metadata.
They are the basis for all transaction and holdings calculations.

### Asset class inference

Every security carries an **asset class** field. Its value is determined at
read time by `Security.effective_asset_class/1`: if the stored value is
non-nil it is returned as-is; otherwise the name, ISIN, and ticker are
inspected in priority order:

1. **government_bond** — ISIN country-code prefix in the two-letter list of known
   government-bond issuers (DE, US, GB, FR, IT, ES, JP, …).
2. **etf** — name contains `ETF`, `UCITS ETF`, or an exact ISIN starting with
   `IE00` combined with a known fund-issuer prefix.
3. **crypto** — name matches a known coin name (Bitcoin, Ethereum, Ripple, Cardano,
   Solana, Dogecoin, Avalanche, Tron, …) or ticker matches a known crypto symbol
   (BTC, ETH, XRP, ADA, SOL, DOGE, AVAX, TRX, …).
4. **commodity** — name is an exact bare metal name: Gold, Silber, Silver, Platin,
   Platinum. (Compound names like "Barrick Gold Corp" are not matched here and
   pass through to equity.)
5. **derivative** — name contains `Knock-Out`, `Zertifikat`, or `Turbo` (including
   single-letter suffixes such as TurboP, TurboC, TurboA).
6. **knock_out** — name contains `Turbo` (any single-letter suffix), `Knockout`,
   or `KO` pattern. In practice the Turbo check is shared with the derivative
   branch; the `knock_out` class is stored explicitly when the user corrects the
   inference.
7. **equity** — name contains a legal-form suffix (Corporation, Company, Co.,
   Aktiengesellschaft, AG, S.A., S.p.A., A/S, ASA, KGaA, Azioni, Acciones,
   Aktier, Ltd., PLC, Inc., GmbH, NV, SA) or a depositary-receipt marker
   (ADR, GDR, Sp.ADR, Depos. Receipts, INH.ON, Registered Part. Shares).
8. **fund** — name starts with or contains a known fund-issuer prefix (iShares,
   Vanguard, Lyxor, Amundi, AIS-AM, Xtrackers, SPDR, Invesco, WisdomTree,
   VanEck, Fidelity, Deka) but did not match the ETF pattern above.
9. **nil** — no heuristic fired; the security is considered unclassified.

Because inference runs at read time, improving a heuristic in the code
retroactively reclassifies all matching securities without a data migration.

#### Finding and fixing unclassified securities

The securities list accepts an **"is unclassified"** filter on the asset-class
column (`operator: :is_nil`). It returns all rows where the stored value is nil
and `effective_asset_class` also returned nil — i.e. the heuristics have no
confident match. For each such row the asset-class cell shows an inline
**quick-assign** dropdown so you can set the class directly from the list
without opening the security detail page.

A stored class is a permanent override: once set it is returned by
`effective_asset_class` regardless of what the heuristics would produce, so the
quick-assign choice survives any future heuristic changes.

#### Letter-spaced names from Portfolio Performance

Portfolio Performance sometimes exports names with a space between every
character — e.g. `I b e r d r o l a S . A . A c c i o n e s`. The JSON
parser detects this pattern (majority of whitespace-separated tokens are
single characters, minimum four tokens) and collapses the tokens before
heuristics run, so legal-form suffixes are reliably detected even from such
exports.

## Portfolios and Accounts

The portfolio owns one working set of account models:

- cash account: tracks available liquidity context
- depot/account: stores security positions linked to that cash account

## Transactions and Holdings

### Manual Transactions

Transactions are explicit and auditable. A transaction defines:

- date
- security
- direction (buy/sell)
- quantity (Decimal)
- unit price (Decimal)
- optional taxes, fees, and notes

A transaction is booked in the currency of its linked cash account. Its
currency must match that cash account's currency (and, for a cash transfer,
the counter cash account's currency too); a mismatched booking is rejected
rather than silently converted. Record the booking against a cash account in
the same currency, or add one. No exchange-rate conversion of stored amounts
happens here — exchange rates are only applied when valuing a portfolio in its
base currency.

### Holdings Calculation

Current holdings are not entered manually. They are derived from all
transactions over time, so the state is reproducible and traceable. Held
quantities move with buys and sells, with inbound/outbound **deliveries**
(shares entering or leaving without a cash leg, e.g. a depot transfer from
another bank), and with **security transfers** between your own depots. Each
holding also carries a moving-average cost basis and the unrealized
profit/loss (absolute and percentage) against the latest stored price, in the
security's own currency; cost basis and P&L consider only priced buy/sell
trades, since a delivery carries no own cost.

## Classifications, Targets, and Allocation

Securities can be organised into **classification trees**. Custom trees are
free-form folders with colours; built-in trees for **asset class** and
**currency** are derived from each security and always present. The asset-class
tree is an editable taxonomy: a security's class is seeded from an inferred
default and corrected by dragging it between categories.

Each portfolio can store a **target weight** per category (a fraction of the
portfolio, for example 25%). The **allocation** breakdown then compares, per
category, the actual weight (its share of the valued positions) against the
stored target and reports the **drift** — both as a weight and as a base-currency
amount, i.e. how much to buy or sell to reach the target. Securities held but not
assigned in the chosen tree are summed into an unassigned bucket. Only the
targets are stored; the actual side is derived from the live valuation on read.

A security can be flagged **excluded from allocation targets** (the toggle in
security management; the API/MCP field is `excluded_from_allocation_targets`).
An excluded position — for example a Bitcoin held as a long-term store of value
rather than part of the steered mix — still counts in the total value, holdings,
and performance, but it is left **out of the allocation steering basis** (the
100%) and the drift table. So switching one on raises every other category's
actual percentage consistently without changing the total. The excluded
positions do not disappear: the drift table shows them in a separate
*Outside the steering basis* row with their summed value.

Classification trees are **hierarchical**, and the allocation rolls them up: a
position assigned to a sub-category counts toward that sub-category **and every
parent above it**. So if *Growth* holds a 50% target and you only assign
holdings to its sub-categories (*Tech*, *Emerging*, …), *Growth*'s actual
weight is their sum — not 0% — and its drift is measured against that sum. The
drift table lists categories in tree order with sub-categories indented under
their parent; because each parent already includes its children, the displayed
actual percentages add up to 100% only across the leaves (plus unassigned),
not across every level.

Targets stay **loose on purpose**: you can set a weight at the top level and at
sub-levels without the app forcing them to add up. To keep that freedom while
making divergence visible, the Portfolio page shows two **advisory consistency
hints** — read-only, never blocking a save:

- A subtle line under each parent that has child targets reads
  *subcategories: X% of Y%*, where X is the sum of the direct children's
  targets and Y is the parent's own target. It turns **yellow** when X and Y
  differ.
- The allocation header shows *Σ target top level: Z%* — the sum of the
  top-level categories' targets **plus the cash target** — highlighted when Z is
  not 100%.

Equality is checked exactly (to the stored weight precision), so a hint only
highlights when the numbers genuinely differ. The hints are guidance only; the
target save path is unchanged and never rejects freely chosen weights.

**Cash is part of the allocation.** A portfolio can store a **cash target**
(`cash_target_weight`, e.g. 5%) — the SOLL share of cash inside the same 100%
basis as the categories. With a cash target set, the allocation's 100% basis is
**securities (minus excluded) + the cash that counts toward the cash quote**
(the accounts flagged *counts toward the cash quote*). The drift table then shows
a dedicated **Cash** row in its own neutral colour with the cash actual, target
and drift, the sunburst gains a cash segment, and every category percentage
shrinks accordingly once cash joins the basis. Set the cash target over the API
(`PATCH /api/v1/portfolios/:id`) or MCP (`portfolixir.portfolios.set_cash_target`),
or clear it with `null` to stop steering a cash quote.

## Exchange Rates and Valuation

Portfolios can hold securities and cash in several currencies. Exchange rates are
stored against a EUR hub (with European Central Bank sync), and other pairs are
triangulated through it. The live portfolio valuation converts each position's
market value and each cash balance into the portfolio base currency.

A security without any quote yet is priced at your **latest own trade price**
— a buy or sell is a price observation, exactly how Portfolio Performance
seeds prices from bookings — so a freshly imported portfolio is not valued at
zero while quotes are still being fetched. Such positions carry
`price_source: "trade"` in the API and are counted in `trade_priced_count`;
the Portfolio page flags them as a data-quality hint. A position with neither
a quote nor a trade price, or with no rate path to the base currency, is
reported as unvalued, so a missing price or rate never silently distorts the
total or the weights.

## Cash and cash quote

Cash is part of the portfolio, not an afterthought. Each portfolio has one or
more cash accounts, and the live valuation reports the **total cash**, the
**total including cash**, and the **cash quote** — cash as a share of the whole
portfolio — so you can see your liquidity and dry powder at a glance, converted
into the portfolio base currency.

A depot's settlement cash stays up to date on its own: buys, sells, dividends,
interest, fees and taxes move it as you record those transactions, so the cash
that belongs to investing needs no separate upkeep.

For external accounts (a current account, savings, a business account), the goal
is visibility without bookkeeping. Instead of mirroring every booking, you **set
an account's balance directly** — type the figure your banking app shows as a
dated **snapshot** (the set-balance form on the Portfolio page,
`POST /api/v1/cash_accounts/:id/balance`, or the `cash_accounts.set_balance`
MCP tool). The balance then anchors to that amount,
and only bookings dated strictly after the snapshot change it; so moving money
between your own accounts needs no transfer entry — you just restate each
balance now and then. The amount may be negative (an overdraft), and the same
snapshot can later be filled automatically over the API (a script or a read-only
bank export) — without turning Portfolixir into a banking app. This follows the
design recorded in
[ADR-0009](decisions/0009-cash-as-balance-snapshots.html).

Each cash account carries a flag for whether it counts toward the cash quote
(on by default; the toggle sits next to the account on the Portfolios page,
and the API/MCP field is `counts_toward_cash_quote`). An account switched off —
a business account, say — stays listed with its balance and inside the total
cash, but the quote is computed as if it did not exist, so it never distorts
your private quote. The Portfolio page marks such accounts as "not in cash
quote".

## Portfolio Page

The **Portfolio** entry in the navigation opens the portfolio overview: the
total value including cash, the cash quote, and both the TTWROR and the
money-weighted **IRR** for a selectable period (year-to-date, one/three/five
years, or since the first transaction) with the cumulative performance chart. Below it, the **allocation sunburst**
shows the classification as concentric rings — the inner ring is the top-level
categories, each outer ring breaks one level down with sub-category arcs nested
inside their parent, and the **outermost ring shows the individual positions**
as shaded arcs of their category's colour (the Portfolio Performance style) —
with a grey slice for unassigned holdings. Like PP the slices carry no
in-chart text: hovering a slice shows its name, share and value in an
**instant custom tooltip** that follows the pointer (no browser hover delay),
and a slice can be **tapped** to echo the same below the chart (the mobile
substitute for hover). With JavaScript disabled the slices fall back to the
native browser tooltip. The chart scales to the available width. Pick any
classification tree from the selector. The drift table beneath it lists every category in tree
order with **sub-categories indented** under their parent, comparing the
rolled-up actual weight against the stored target and restating the drift in
the base currency. The cash section lists each account's balance and carries
the **set-balance form**: type the balance your bank shows and the snapshot is
recorded without booking individual transactions.

The page paints immediately and computes its figures **asynchronously**; each
section fills in when its data is ready. The expensive daily performance walk
runs once and is cached on the page — switching the period re-chains the
cached series, so the period buttons respond instantly. The chart is
downsampled to a bounded number of points, so a decade of daily history stays
light in the browser. Money and percentages follow the chosen language
(German `1.234.567,89`, English `1,234,567.89`; money always with two
decimals).

A **data-quality panel** appears above the chart when something would
otherwise silently skew the figures: positions valued at their last trade
price because no quote exists yet, positions with no price at all (excluded
from the totals, listed by name), and bookings with implausible dates (before
1970) that were applied on the first plausible day instead.

## Performance (TTWROR)

Portfolixir reports the **true time-weighted rate of return** the way Portfolio
Performance does: the portfolio is valued every day from the first transaction
onward, money you put in or take out (deposits, removals, deliveries, and
balance-snapshot jumps) is neutralised, and the daily returns are chained. The
result measures how well the **investments** performed, regardless of when cash
moved — dividends, interest, fees and taxes count as part of the return.

Next to it Portfolixir shows the **money-weighted return (IRR)** — the single
annualised rate that discounts the period's dated deposits, withdrawals and the
terminal value back to zero, the figure Portfolio Performance shows beside
TTWROR. Where TTWROR ignores the timing of your cash, the IRR reflects it, so
the two read differently when money moved at good or bad moments. The IRR shows
`—` when there is no rate to compute (no flows of both signs, or the solver does
not converge).

Performance is shown on the Portfolio page and available per period —
year-to-date, one, three, or five years, or since the first transaction —
over the API
(`GET /api/v1/portfolios/:id/performance`) and the
`portfolixir.portfolios.performance` MCP tool, optionally with the full daily
valuation series for charting. The method and its trade-offs are recorded in
[ADR-0010](decisions/0010-ttwror-performance-series.html).

## Income (dividends and interest)

The **Income** page is the retrospective income report: the dividends and
interest already booked in your ledger, with no external data or forecast. It
shows an **annual overview** — a year × month matrix split into a *Dividends* and
an *Interest* series, each year with a totals column — and a **per-position
table** with, for each security, the gross paid, the withheld tax, the net, the
number of payments and the date of the last one. A dividend's **gross** is the
net cash credited plus the withheld tax recorded on the transaction; interest
(Portfolio Performance INTEREST: account interest or bond coupons) carries no
withholding and is tracked as its own series next to dividends. Clicking a year
opens the per-transaction detail for that year.

Amounts are reported in the portfolio's base currency, converted through the
EUR hub at each booking date's stored rate (the same conversion the valuation
uses); the original currency stays visible on each row. The report is also
available over the API (`GET /api/v1/portfolios/:id/income`) and the
`portfolixir.portfolios.income` MCP tool.

## Imports

The Imports page accepts Portfolio Performance transaction exports in CSV or
JSON v1 format. Files are parsed into a preview before any records are saved.
The preview shows translated transaction-kind labels, the records that would be
created, and account/depot mappings for missing targets.

Parser warnings appear in a scrollable box with a copy button. The copied text
uses stable `Row N: message` lines so the diagnostics can be kept with the
source export. Applying the import is atomic and uses content hashes to skip
duplicates on re-run.

Rows with **implausible dates** (before 1900, e.g. a `0217-12-05` typo for
2017) are rejected per row with a clear message instead of poisoning every
derived metric — fix the booking in the source and re-import; the content
hashes keep the re-run free of duplicates. After an import, quote and logo
enrichment for the created securities runs as one throttled background job,
so the app stays responsive while hundreds of securities are synced.

## Quotes and Charts

### Quote History

Each quote entry captures a date and a Decimal close. Price history is
persisted so security detail charts are built from local records.

Two ways quotes enter the system:

- **Automatic sync**: a background scheduler ticks every six hours
  (configurable in `config :portfolixir, Portfolixir.Catalog.QuoteSync`)
  and pulls daily closes from each security's configured provider.
- **Sync now**: the toolbar's *Sync prices* button (and the per-security
  button on the detail page) triggers an immediate sync without waiting
  for the next tick.

Quote sources in this iteration:

- Search step (which catalog the security came from) uses Portfolio
  Performance for stocks/ETFs/funds and CoinGecko for crypto.
- New securities start background quote/logo enrichment when configured.
  Logo discovery runs through a single background queue, scans missing
  logo candidates on startup, is also triggered after imports, and runs a
  periodic rescan, so large imports fill in over time. The queue is throttled
  (one request every few hundred ms) to stay under the upstream rate limits
  instead of firing a burst that mostly fails. Per security, sources are tried in order: CoinGecko
  (crypto), Wikipedia/Wikidata (equities/ETFs/funds), then companieslogo.com
  as a fallback.
  ETF logo discovery tries known issuer names before the individual fund name
  (for example iShares, Vanguard, Lyxor, Amundi, Xtrackers, SPDR, Invesco).
  Structured/leverage products (warrants, knock-outs, certificates) carry no
  own logo but show their issuer's logo (BNP Paribas, Morgan Stanley, Société
  Générale, …) when the issuer is recognizable. A manual override (image URL)
  always wins and locks the security against background discovery.
  Government bonds use the `government_bond` asset class for ISIN country flag fallbacks.
- Quote-history fetch uses Yahoo Finance for both. Two reasons:
  - PP's own API exposes only search, no price history.
  - CoinGecko's free public API caps history at 365 days
    (`error_code 10012`); Yahoo returns the full daily series for
    crypto via the `<TICKER>-<CURRENCY>` symbol form (e.g. `BTC-USD`).
- Portfolio Performance search can provide symbols for some bonds and leveraged products.
  Yahoo remains usable when a suitable symbol exists and is stored on the
  security.
- Ariva is not used as a quote adapter. Its historical endpoint for leveraged
  products is currently blocked for this local default use case.
- Bundesbank is relevant for German federal securities and yield data, not a general ISIN quote provider.
- No API-key-based providers and no unofficial scraping dependency are used as
  default quote sources.
- No new bond or leveraged-product quote adapter is implemented in this batch.

Yahoo is queried with `period1=0` and `period2=<now>` so it returns the
full available daily history — `range=max` silently downsamples to
monthly for long-history tickers.

Securities whose provider has no quote adapter, or whose adapter cannot run
because required fields such as ticker are missing, are reported as skipped
with a reason. Failed adapter calls are reported separately from successful
syncs.

### Security Detail Chart

With no selected security, the securities list fills the page workspace.
Clicking a row opens `/securities/:id` in a vertical split workspace: the list
stays in the upper scrollable pane and the selected detail pane opens below it.
The horizontal separator can be dragged or adjusted with the keyboard on
desktop; mobile uses a stacked layout.

The detail pane shows a server-rendered SVG price chart with:

- Time-range buttons (1M / 3M / 6M / YTD / 1Y / 3Y / 5Y / MAX).
- A *Log scale* toggle (logarithmic Y-axis).
- A *Show transactions* toggle that overlays Buy/Sell markers from the
  ledger.
- A *Sync prices for this security* button.

## Interface behavior

- The active page title and short context line live in the top bar. Page content
  starts directly with a full-width workspace, so every active menu route uses
  the available space without a repeated page-level heading or outer page
  gutters.
- The securities list uses a full-width workspace instead of generic panel
  chrome; the toolbar remains pinned to the workspace top and the table uses
  the full horizontal width below it.
- In a classification tree, categories are collapsed by default (click a
  category to expand it); searching expands the matching categories. Long
  security names are truncated to one line with the full name on hover, and the
  ticker is shown next to the name.
- Each assigned security shows its **current quantity** (summed across every
  securities account of every portfolio) and its **current market value** in
  the EUR hub, valued from the latest quote (falling back to the latest own
  trade price, like the portfolio valuation). Holdings and values are loaded
  **once** for the whole tree after the page connects, so a large tree never
  triggers a query per row.
- A **Current positions only** toggle is on by default. It hides securities you
  no longer hold (zero current quantity) so legacy or fully sold assignments do
  not clutter the tree. Nothing is silently dropped: each category shows a
  **+N without holdings** counter for the hidden securities, and turning the
  toggle off reveals them again.
- Each category row aggregates the **value** and the **position count** of the
  securities currently visible in it and its sub-categories, so the totals
  follow the toggle.
- The sidebar lists only routes that exist plus the few planned features that
  have an open issue behind them. Two entries are shown disabled with a "Soon"
  pill: **Watchlist** and **Returns & risk**. The **Income** report is a live
  entry (received dividends and interest). Allocation, holdings, and performance
  are not separate menu entries — the **Portfolio** page already covers asset
  allocation (the sunburst), holdings, and TTWROR performance.
- Theme: system, light, and dark modes are supported.
- Accent: violet, teal, and coral logo accent choices are supported.
- Language: first load follows the browser language when it is English or
  German. Explicit EN/DE links override the browser language and persist that
  choice.
- Theme, accent, and language are user preferences and do not affect stored
  financial values.

## Non-goals today

- No automatic trading or order execution.
- No bank, broker, or wallet integrations.
- No payment scheduling or settlement workflows.
- No broker PDFs, binary Portfolio Performance workspaces, bank sync, broker
  sync, or document intake beyond the Portfolio Performance CSV/JSON v1
  transaction export workflow.

Savings plans are deliberately not supported. A savings plan only describes an
*intended* recurring contribution, and its target values inevitably diverge from
the real executions a broker performs — typically by cent-level differences in
price, fee, and quantity. Portfolixir treats the imported, real transactions as
the single source of truth for holdings and performance, so modelling separate
savings-plan targets would add a parallel set of numbers that never quite
matches reality. Recurring contributions are therefore captured simply as the
transactions they actually produced.
