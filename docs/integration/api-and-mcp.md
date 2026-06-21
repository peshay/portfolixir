---
layout: docs
title: API and MCP
description: Portfolixir JSON API and MCP companion reference.
lang: en
lang_en: /integration/api-and-mcp.html
lang_de: /de/integration/api-and-mcp.html
---

# API and MCP

Portfolixir exposes the supported local workflow through the JSON API under
`/api/v1`. The MCP companion in `mcp-server/` is intentionally thin: MCP tools
call the JSON API only and do not access the database directly.

## Authentication

API requests require a local bearer token:

```text
Authorization: Bearer <PORTFOLIXIR_API_TOKEN>
```

The MCP companion uses `PORTFOLIXIR_API_TOKEN` to call Portfolixir.
`PORTFOLIXIR_MCP_TOKEN` is required for HTTP transport so local HTTP clients can
authenticate to the companion.

## Data Rules

All responses use JSON envelopes with either `data` or `errors`. Financial
decimals are serialized as strings, including quantities, prices, fees, taxes,
quote closes, and monetary totals. Request payloads for those values should also
send strings.

`DELETE /api/v1/securities/:id` is the success exception: it returns
`204 No Content` with an empty body. Clients should not parse a JSON body for
that successful delete response.

## Securities

- `GET /api/v1/securities` lists securities. Optional query params: `query`,
  `sort`, `direction`, holding_status (`all`, `held`, or `not_held`),
  `logo_status` (`missing` or `present` — `missing` powers the "securities
  without a logo" overview and excludes rows explicitly set to no logo), and
  `limit`/`offset` for pagination (both non-negative integers). Use these to
  page large catalogs instead of fetching the whole table at once.
- `POST /api/v1/securities` creates a security with a `security` object.
  `asset_class` is a stable string code: `equity`, `etf`, `fund`,
  `government_bond`, `bond`, `crypto`, `commodity`, `index`, `other`, plus the
  certificate/leverage codes `warrant`, `knock_out`, `factor_certificate`,
  `discount_certificate`, `bonus_certificate`, `express_certificate`,
  `reverse_convertible`. Leave it empty to let the class be inferred from the
  name/ISIN/ticker on read. To keep a position out of the allocation steering
  basis (the 100%) and the drift table while leaving it in the valuation totals
  and performance — e.g. a Bitcoin held as a store of value — tag it with a
  bucket and exclude that bucket from a view, then read allocation under that
  view.
- `GET /api/v1/securities/:id` returns one security.
- `PATCH /api/v1/securities/:id` updates a security with a `security` object.
- `DELETE /api/v1/securities/:id` deletes a security when no dependent
  transactions or quote history reference it; referenced securities return
  `409 Conflict`.
- `GET /api/v1/securities/search` searches configured online security providers.
  Query params: `query`; optional `type` with `security` or `crypto`.

### Logos

Each security can carry a logo, resolved automatically (CoinGecko for crypto,
Wikipedia for equities/ETFs/funds) or set manually. A manual logo, or an
explicit "no logo", *locks* the security so background discovery never
overwrites the choice.

- `GET /api/v1/securities/:security_id/logo` returns the logo status:
  `{ "data": { "security_id", "path", "source", "has_logo", "locked" } }`.
  `source` is one of `coingecko`, `wikipedia`, or `manual`.
- `PUT /api/v1/securities/:security_id/logo` sets a manual logo from an image
  URL (`{ "logo": { "url": "https://…" } }` or `{ "url": "https://…" }`). The
  image is downloaded once, validated (png/jpg/jpeg/webp, max 256 KiB) and
  stored locally; the security is locked to the manual choice. A missing URL
  returns `422`.
- `DELETE /api/v1/securities/:security_id/logo` removes the logo and records an
  explicit "no logo" decision (the row falls back to its initials/flag), also
  locking it against discovery.
- `POST /api/v1/securities/:security_id/logo/discover` re-runs automatic
  discovery ("search again"). The response includes a `result` of `updated`,
  `no_source`, or `failed`. Locked securities are left untouched.

Example create payload:

```json
{
  "security": {
    "name": "Example ETF",
    "ticker_symbol": "EXM",
    "currency_code": "EUR"
  }
}
```

## Quotes

- `GET /api/v1/securities/:security_id/quotes` lists quote history for one
  security. Optional query params: `from` and `to`, formatted as ISO dates.
  Invalid date filters return `422 Unprocessable Entity` with field errors.
- `PUT /api/v1/securities/:security_id/quotes` upserts manual quote rows.
- `POST /api/v1/securities/:security_id/sync_quotes` triggers quote sync for
  one security. The response includes `status` (`ok`, `skipped`, or `error`);
  skipped and error responses may include a `reason` such as
  `missing_ticker` or `no_provider_adapter`.

Example quote upsert payload:

```json
{
  "quotes": [
    {
      "date": "2026-05-15",
      "close": "123.45",
      "source": "manual"
    }
  ]
}
```

Example quote sync response:

```json
{
  "data": {
    "status": "skipped",
    "reason": "missing_ticker"
  }
}
```

## Portfolios and Accounts

- `GET /api/v1/portfolios` lists portfolios.
- `POST /api/v1/portfolios` creates a portfolio with a `portfolio` object.
- `GET /api/v1/cash_accounts` lists cash accounts. Each carries a `balance`
  (decimal string, in the account's own currency) derived on read from the
  ledger: amounts are stored as positive magnitudes and the transaction `type`
  implies the direction (deposits, dividends, interest, tax refunds and sells
  add cash; removals, fees, taxes and buys remove it; a cash transfer debits its
  account and credits the counter account). A `balance_adjustment` snapshot (see
  below) anchors the balance to a stated absolute amount as of its date, after
  which only later bookings adjust it.
- `POST /api/v1/cash_accounts/:id/balance` records an absolute **balance
  snapshot** for one account (ADR-0009): the current balance as of a date,
  instead of mirroring every booking. Body `{"date": "2026-06-01", "amount":
  "4250.00"}` (`notes` optional); `amount` is a decimal string and may be
  negative (an overdraft). It stores a `balance_adjustment` transaction and
  returns it. The balance then anchors to that amount and only bookings dated
  strictly after the snapshot change it, so moving money between your own
  accounts needs no transfer entry. Unknown accounts return `404 Not Found`.
- `POST /api/v1/cash_accounts` creates a cash account with a `cash_account`
  object. The optional `liquidity_role` (default `free_cash`) classifies the
  account: `free_cash` is genuine deployable cash; `credit_line` is an
  overdraft/Lombard facility whose negative balance is a liability and whose
  unused headroom is never liquidity (it never enters deployable cash, even
  with a positive balance — type beats sign); `reserve` is a visible-but-
  excluded bucket (e.g. a business account). Only `free_cash` accounts with a
  non-negative balance contribute to the valuation's deployable cash and its
  `cash_quote`. An unknown value is rejected with `422 Unprocessable Entity`.
- `GET /api/v1/cash_accounts/:id` returns one cash account.
- `PATCH /api/v1/cash_accounts/:id` updates a cash account (`name`,
  `currency_code`, `notes`, `liquidity_role`); `portfolio_id` cannot
  be changed.
- `DELETE /api/v1/cash_accounts/:id` deletes a cash account, or returns
  `409 Conflict` when a transaction or securities account still references it.
- `GET /api/v1/securities_accounts` lists depots/securities accounts.
- `POST /api/v1/securities_accounts` creates a depot/securities account with a
  `securities_account` object.
- `GET /api/v1/securities_accounts/:id` returns one securities account.
- `PATCH /api/v1/securities_accounts/:id` updates a securities account
  (`name`, `notes`, `cash_account_id`); `portfolio_id` cannot be changed.
- `DELETE /api/v1/securities_accounts/:id` deletes a securities account, or
  returns `409 Conflict` when a transaction still references it.

Example account payloads:

```json
{
  "portfolio": {
    "name": "Household Portfolio",
    "base_currency_code": "EUR"
  }
}
```

```json
{
  "cash_account": {
    "portfolio_id": 1,
    "name": "Settlement EUR",
    "currency_code": "EUR"
  }
}
```

```json
{
  "securities_account": {
    "portfolio_id": 1,
    "cash_account_id": 1,
    "name": "Main Depot"
  }
}
```

## Transactions and Holdings

- `GET /api/v1/transactions` lists transactions. Optional filters: `from`/`to`
  (ISO dates, inclusive), `portfolio_id`, `security_id`, `securities_account_id`.
  Invalid filters return `422 Unprocessable Entity` with the offending field.
- `POST /api/v1/transactions` creates a manual buy or sell transaction with a
  `transaction` object. A security settled through a different-currency cash
  account (for example a USD security bought through a EUR account) is booked in
  the security's own currency and carries the cross-currency settlement fields
  `security_amount` (trade amount in the security currency), `settlement_amount`
  (cash amount debited or credited in the account currency) and
  `settlement_fx_rate` (account-currency units per one unit of the security
  currency). When the rate is omitted but both amounts are supplied it is derived
  as `settlement_amount / security_amount` (the broker's actual rate); a currency
  mismatch with no rate and no amounts to derive one is rejected. Cost basis stays
  in the security currency so per-position P&L is FX-honest. All three are Decimal
  strings and `null` for same-currency bookings.
- `GET /api/v1/transactions/:id` returns one transaction.
- `PATCH /api/v1/transactions/:id` updates a transaction (e.g. to fix a
  mis-imported booking); the per-kind validation still applies.
- `DELETE /api/v1/transactions/:id` deletes a transaction. Because trades and
  holdings are derived, correcting or removing the transaction fixes them too.
- `GET /api/v1/portfolios/:portfolio_id/holdings` lists derived holdings for a
  portfolio, one row per (depot, security). Each row carries `quantity`, a
  moving-average `avg_cost` and `cost_basis` (price-based, so fees and taxes are
  not folded into the unit cost), the `latest_price`, `market_value`, and
  `unrealized_pnl_abs`/`unrealized_pnl_pct` against that price, plus
  `security_name` and `currency_code`. All monetary figures are in the security's
  own currency (no FX conversion — see the valuation for base-currency totals); a
  holding whose security has no quote returns `null` price, market value and P&L.
  The response is self-describing (FR-13): it carries `currency_basis:
  "security_currency"` (so a client never has to assume whether FX was applied)
  and an `as_of` date. Holdings are derived on read with no stored snapshot, so
  `as_of` is the read date. Unknown portfolios return `404 Not Found`. Optional
  filters: `security_id`, `securities_account_id`.
- `GET /api/v1/holdings/by_security` returns the **global per-security
  valuation** across **all** portfolios: one `holdings` row per currently held
  security with its `security_id` (an integer), total `quantity`, and current
  `market_value` converted to the **EUR hub**, plus a `valued` flag. `valued`
  is `false` (and `market_value` is `null`) when the security has neither a
  quote nor a trade price, or no exchange-rate path to EUR, so a missing quote
  or rate never silently distorts a value. Rows are sorted by `security_id`.
  The response is self-describing: a top-level `currency` of `"EUR"`, an
  `as_of` read date (the report is derived on read, so `as_of` is today's date,
  not a stored snapshot), and a `note` describing the hub conversion. This is
  the cross-portfolio, base-currency counterpart to the per-portfolio holdings
  list (which stays in each security's own currency with no FX); for one
  portfolio's totals and weights use the valuation endpoint instead.
- `GET /api/v1/portfolios/:portfolio_id/valuation` returns a live valuation of a
  portfolio: each held position priced from its latest quote close, a
  `total_value`, and each valued position's `weight` (its share of the total).
  Each position's market value is converted into the portfolio
  `base_currency` (top-level field) from stored exchange rates; per-position
  `security_currency` shows the native currency. A security without any quote
  is priced at the latest own trade price (`price_source: "trade"`, counted in
  the top-level `trade_priced_count`); a quoted position carries
  `price_source: "quote"`. A position with neither price **or** no
  exchange-rate path to the base currency is returned with `valued: false`,
  `price_source: null` and `null` market value and weight, so a missing price
  or rate never distorts the total. Unknown portfolios return `404 Not Found`.
  Weights are raw shares (`market_value / total_value`) emitted at full Decimal
  precision; because they are normalized ratios they need not sum to exactly
  `1` (round for display). Market values and `total_value` are exact.
  The valuation also carries cash: `cash_balances` lists each cash account
  (`balance` in its own currency, plus `base_value`/`valued` after converting to
  the base currency, its `liquidity_role`, and a `deployable` flag), `total_cash`
  is the base-currency sum of the valued cash accounts (so a drawn credit line's
  negative balance still reduces it), and `total_with_cash` is
  `total_value + total_cash`. `cash_quote` is the deployable-cash share of the
  portfolio: deployable cash is the sum of `free_cash` accounts with a
  non-negative balance (`deployable: true`), and the quote is computed as if the
  other accounts did not exist (`counting_cash / (total_value + counting_cash)`,
  `0` when there is nothing to value yet) — so a reserve account or a credit line
  stays listed and inside `total_cash` without ever reporting fake liquidity. The
  response also emits `counting_cash` (Decimal string) — the deployable cash that
  enters the quote — so a consumer can reconstruct `cash_quote` itself. An
  account whose currency has no rate path to the base is reported
  `valued: false` and excluded from `total_cash`, mirroring how unpriceable
  positions are handled.
  The response is self-describing (FR-13): it carries an `as_of` date (the read
  date — the valuation is computed live with no stored snapshot) and a
  `valuation_note` stating that totals are in `base_currency` via the EUR hub and
  that the per-position `price_source` and `valued` fields indicate price
  staleness.
- `GET /api/v1/portfolios/:portfolio_id/performance` returns the portfolio's
  **true time-weighted rate of return (TTWROR)**, computed the Portfolio
  Performance way: the portfolio is valued daily (quotes on or before each day,
  converted at that day's rates, plus cash), external flows — deposits,
  removals, deliveries, and balance-snapshot jumps — are neutralised, and daily
  returns chain geometrically (see ADR-0010). Optional query params: `period`
  (`ytd`, `1y`, `3y`, `5y`, `max` — default `max`; an unknown period returns
  `422 Unprocessable Entity`) and `series=true` to include the daily points
  (`date`, `value`, `flow`, `cumulative_ttwror`). The response carries
  `ttwror`, `start_date`/`end_date`, `start_value`/`end_value`,
  `net_external_flows` as Decimal strings, and `suspect_dates` — dates of
  bookings older than 1970 (import typos) whose effects were applied on the
  first plausible day. Alongside `ttwror` the response also carries the
  **money-weighted return** `irr` — the single annualised rate that discounts
  the period's dated external flows and terminal value back to zero
  (`NPV(r) = Σ cf/(1+r)^(days/365) = 0`), the figure Portfolio Performance
  shows next to TTWROR. It is a Decimal string, or `null` when no rate exists
  (fewer than two flows, all flows the same sign, or the solver does not
  converge). Securities without quotes are priced at the latest own trade
  price (see the valuation endpoint). Unknown portfolios return
  `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/income` returns the **retrospective
  income report**: the dividends and interest already booked in the ledger,
  aggregated three ways (no forecast — the dividend calendar is a separate
  feature). `annual` is a list of years (newest first), each with `months` (a
  map keyed by month number `"1"`–`"12"`, each carrying `dividends` and
  `interest`), and per-year `dividends_total`, `interest_total` and `total`.
  `positions` is the per-position table: `security_id`, `security_name`,
  `security_currency` (the original booking currency), `gross`, `tax` (the
  withheld tax, from the dividend's TAX units stored on the transaction), `net`
  (`gross - tax`), `payment_count` and `last_payment`. `transactions` is the
  per-transaction detail for a year drilldown (`kind`, `date`, `year`,
  `security_id`/`security_name`, `currency`, the native `native_gross`/
  `native_tax`/`native_net`, the base-currency `gross`/`tax`/`net`, and
  `converted`). A dividend's gross is its net cash (`gross_amount`) plus the
  withheld tax; interest carries no withholding. All amounts are Decimal strings
  in the portfolio's `base_currency`, converted via the EUR hub at each
  booking date's stored rate (the same mechanics as the valuation endpoint), with
  the original currency retained; `unconverted_count` counts bookings with no
  rate path (converted at parity), and `conversion_note` states the basis.
  Unknown portfolios return `404 Not Found`.
  Since ADR-0020 a SOLL target plan **belongs to a view**: the target read/write
  endpoints accept an optional `view` (a view id). Omitting it (or sending
  `null`) addresses the portfolio-wide **Gesamt** plan — the behaviour before
  views existed. A view carries its own plan, so the same classification can hold
  a different plan per view without the plans summing across each other. A
  malformed `view` returns `422 Unprocessable Entity` (`{"view": ["is
  invalid"]}`) and an unknown view id returns `404 Not Found`, the same
  structured contract the analytics endpoints use.
- `GET /api/v1/portfolios/:portfolio_id/targets` lists a portfolio's stored
  target weights (the SOLL side of the allocation). Optional `classification_id`
  scopes the list to one tree; optional `view` selects the plan (omitted =
  Gesamt). Unknown portfolios return `404 Not Found`.
- `PUT /api/v1/portfolios/:portfolio_id/targets` upserts target weights for one
  classification. The body is `{"classification_id": id, "targets": [{"category_id":
  id, "target_weight": "0.25"}]}` and may carry an optional `"view": id` to write
  that view's plan (omitted = Gesamt). Each `target_weight` is a string fraction
  in `[0, 1]`; targets need not sum to `1`. Only the supplied categories are
  changed. A category from another tree returns `422 Unprocessable Entity`, and an
  unknown classification returns `404 Not Found`.
- `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` removes a
  portfolio's target weight for one category and returns `{deleted}` (the number
  of rows removed). Optional `view` selects the plan (omitted = Gesamt).
- `GET /api/v1/portfolios/:portfolio_id/allocation` returns the SOLL/IST
  breakdown for one classification (required `classification_id` query param; a
  missing one returns `422 Unprocessable Entity`). For each category it reports
  `parent_id` and `depth` (the categories form a tree), `color`,
  `own_market_value` (positions assigned directly to it), `market_value` (its
  whole subtree rolled up), `actual_weight` (the rolled-up share of
  `total_value`), `target_weight`, `drift_weight`
  (`target_weight - actual_weight`), and `drift_value` (the drift restated in
  the base currency). Each row also carries `child_target_sum` (Decimal string):
  the advisory sum of its **direct** children's targets, or `null` when no direct
  child carries a target — a target-consistency hint the UI can flag against the
  row's own `target_weight`. A position assigned to a child counts toward that child
  **and every ancestor**, so a parent category with a target is compared
  against its subtree rather than showing 0%; the rows come back in tree order
  (parent before its children). Because parents aggregate their children, the
  per-category `actual_weight` values intentionally do not sum to 1 across
  levels — only the leaves plus `unassigned` do. Each category (and
  `unassigned`) also carries `positions`: the per-security breakdown of its
  **own** (directly assigned) value — `security_id`, `security_name`,
  `market_value`, `weight` — largest first, securities merged across depots;
  this is what the sunburst's outermost ring renders. Securities held but not
  assigned in the tree are summed into `unassigned`. Weights are shares of the
  **steering basis**: the valued positions' total (scoped by the active `view`
  when one is passed), **plus the deployable cash** (`free_cash`
  accounts with a non-negative balance). `total_value`
  here is that steering basis (not the full valuation). The response carries a
  `cash` object — `market_value` (the counting cash), `actual_weight` (its share
  of `total_value`), `target_weight` (the active view's plan cash target, or `0`
  when unset; see the cash-target endpoints below), `drift_weight`
  (`target_weight - actual_weight`),
  `drift_value` (restated in the base currency), and `distributed` (boolean) —
  so cash is steered in the same drift logic as the categories. When the active
  classification is the built-in **currency** tree, each cash account's
  deployable balance is attributed to its own currency-code category instead of
  appearing as a separate cash row: EUR cash flows into the EUR category, USD
  cash into USD, and so on. In that case `cash.distributed` is `true` and
  consumers should omit the separate cash row; for all other classifications
  `distributed` is `false` and the cash row behaves as before. Because cash is
  part of the 100% basis, the category percentages shrink accordingly once cash
  is present. The `top_level_target_sum` is the sum of the root categories'
  targets **plus the cash target** (except for the currency classification where
  cash is distributed into categories), compared against `1`. To keep a holding
  out of the steering basis while it still counts toward total wealth, tag it
  with a bucket and exclude that bucket from the `view` you read allocation
  under — it then falls outside the scoped positions. Since ADR-0020 the **SOLL**
  side reflects the **active view's plan**: passing `view=<id>` reports that
  view's target weights, cash target and `top_level_target_sum` (omitting it uses
  the Gesamt plan), so the drift table steers against one coherent 100% plan per
  view. Unknown portfolios or classifications return `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/risk` returns a **risk/concentration
  lens** for one portfolio over the **steerable basis** (the valued positions,
  scoped by the active `view`, the same
  basis the allocation drift uses). A security held across several depots is
  merged into one single-name exposure. Weights, caps and the HHI are all on a
  **0-100 percentage scale** (Decimal strings, full precision, no rounding):
  - `steerable_basis` is the basis the weights are a share of, and
    `base_currency` the portfolio's base currency.
  - `top_holdings` is the largest single-name exposures, largest first, default
    **N = 10** (override with the `top_n` query param). Each entry carries
    `security_id`, `security_name`, `asset_class`, `market_value`, `weight` and a
    `severity` (`ok`/`warn`/`hard`). The severity is **instrument-type aware**: a
    single stock warns above `7` and goes hard above `10`; an **ETF** (the `etf`
    asset class) warns above `25` and never goes hard. Override the defaults with
    the `stock_thresholds[warn]`/`stock_thresholds[hard]` and
    `etf_thresholds[warn]` query params.
  - `hhi` carries the Herfindahl-Hirschman Index of the single-name weights
    (`value` = the sum of the squared percentage weights, on the `0-10000`
    scale) plus a `band`: `low` (`< 1500`), `moderate` (`[1500, 2500]`) or
    `concentrated` (`> 2500`). Override the cutoffs with the `hhi_bands[low]` and
    `hhi_bands[high]` query params.
  - `asset_class_violations` are **opt-in** asset-class cap violations: there are
    no shipped defaults, so caps are configured per call with the
    `asset_class_caps[<asset_class>]` query param (a percentage, e.g.
    `asset_class_caps[equity]=50`). Only classes whose current percentage weight
    exceeds the cap come back, each with `asset_class`, `current_weight`, `cap`
    and `overage` (current − cap, in percentage points).

  The lens is a pure read-time derivation of the live valuation and the
  securities' asset classification — nothing is stored, so it is deterministic on
  read. A malformed override (e.g. a non-positive `top_n`) returns `422
  Unprocessable Entity`; unknown portfolios return `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/cash_target` reads a plan's cash target,
  the SOLL cash share of the allocation's 100% basis (securities + counting
  cash). The response is `{"cash_target_weight": "0.05"}` (a string fraction in
  `[0, 1]`, or `null` when none is steered). Optional `view` selects the plan
  (omitted = the Gesamt plan). Unknown portfolios return `404 Not Found`, a
  malformed `view` returns `422`, and an unknown view id returns `404`.
- `PUT /api/v1/portfolios/:portfolio_id/cash_target` sets (or clears with
  `null`) a plan's cash target. The body is `{"cash_target_weight": "0.05"}` and
  may carry an optional `"view": id` (omitted = Gesamt). It echoes the stored
  value back. Out-of-range weights return `422 Unprocessable Entity`. The cash
  target feeds the allocation's `cash` row and the `top_level_target_sum` for the
  addressed view.
- `PATCH /api/v1/portfolios/:portfolio_id` patches a portfolio's master data.
  The body is `{"portfolio": {...}}`. **Cash target move (ADR-0020):** the cash
  target moved off the portfolio object onto the per-view SOLL plan, served by
  the two `cash_target` endpoints above. For **back-compatibility** the portfolio
  object still exposes `cash_target_weight` — a string fraction in `[0, 1]` (e.g.
  `"0.05"` for 5%), or `null` to stop steering a cash quote — and patching it
  reads/writes the **Gesamt** plan's cash target (`view` omitted). So a client
  that only knows the old field keeps working unchanged; use `PUT
  /cash_target?view=<id>` to steer a per-view cash target. Out-of-range weights
  return `422 Unprocessable Entity`; unknown portfolios return `404 Not Found`.
  The `cash_target_weight` is also included in the portfolio objects returned by
  `GET`/`POST /api/v1/portfolios` (the Gesamt cash target).
- `GET /api/v1/securities/:security_id/trades` returns FIFO-matched trades for
  one security: open lots, closed round-trips (with realised P&L and holding
  period in days) and any orphan sells. The response is self-describing (FR-13):
  it carries `method: "fifo"`, so a client never has to assume how lots were
  paired against sells. Optional `from`/`to` (ISO dates) filter each leg by its
  own date: open lots by open date, closed round-trips by close date, orphan
  sells by sell date.

## Exchange Rates

- `GET /api/v1/exchange_rates` lists stored exchange rates. Rates are kept
  against the EUR hub (`1 base_currency = rate quote_currency`); other pairs are
  derived by triangulation, and `GBX` (pence) is handled as `GBP × 100`.
- `POST /api/v1/exchange_rates/sync` fetches the latest rates from the configured
  provider (ECB daily reference rates by default) and returns `{provider,
  status, upserted}`. A provider failure returns `502 Bad Gateway`.

## Classifications

Classification trees organise securities like folders. Built-in trees
(`asset_class`, `currency`) are derived automatically and their structure is
locked; editing the structure of a built-in tree returns `422 Unprocessable
Entity`. The **asset-class** tree's membership, however, is just a view of each
security's `asset_class` field: in the UI you can drag a security between its
categories (which sets that field), and the same effect is achieved over the API
with `PATCH /api/v1/securities/:id` (`{"security": {"asset_class": "etf"}}`) or
the `securities.update` MCP tool. Set it to empty/`null` for "automatic", which
re-infers the class from the security's name/ISIN/ticker on read. The currency
tree stays intrinsic and cannot be reassigned.

- `GET /api/v1/classifications` lists every classification as a tree with its
  `categories` and `assignments` (`{security_id, category_id}`). Built-in trees
  carry `built_in: true` and a `key`.
- `POST /api/v1/classifications` creates a custom classification from a
  `classification` object (`name`, optional `position`, `description`).
- `PATCH /api/v1/classifications/:id` updates a custom classification's
  `classification` object (`name`, `position`, `description` — all optional).
- `DELETE /api/v1/classifications/:id` deletes a custom classification and
  cascades its categories and assignments.
- `POST /api/v1/classifications/:classification_id/categories` adds a `category`
  (`name`, optional `color`, `description`, `parent_id`, `position`) to a custom
  classification.
- `PATCH /api/v1/classifications/:classification_id/categories/:id` patches a
  `category` (`name`, `color`, `description`, `parent_id`, `position` — all
  optional). The category's `classification_id` cannot be changed this way.
- `DELETE /api/v1/classifications/:classification_id/categories/:id` deletes a
  category and cascades its child categories and assignments.
- `PUT /api/v1/classifications/:classification_id/assignments` assigns a security
  to a category (`security_id`, `category_id`), replacing any existing assignment
  for that security in the classification. The response carries a `status` of
  `created`, `moved`, or `unchanged` plus `previous_category_id`.
- `PUT /api/v1/classifications/:classification_id/assignments/bulk` assigns many
  securities to one category in a single call (`category_id`, `security_ids`),
  returning `{assigned, category_id, security_ids}`.
- `DELETE /api/v1/classifications/:classification_id/assignments/:security_id`
  removes a security's assignment from the classification.

Example transaction payload:

```json
{
  "transaction": {
    "portfolio_id": 1,
    "securities_account_id": 1,
    "security_id": 1,
    "type": "buy",
    "date": "2026-05-15",
    "quantity": "10.00000000",
    "price": "123.45",
    "fees": "1.50",
    "taxes": "0",
    "currency_code": "EUR"
  }
}
```

## Buckets and Views

Buckets are overlapping tags applied to holdings (depots, cash accounts and
individual security positions) for tag-based wealth scoping. Views are named,
global filters over those buckets: a holding matches when it is included
(always under `include_all`, otherwise when it carries one of the view's include
buckets) and carries none of the view's exclude buckets — exclude always wins.
Bucket-definition and assignment writes are journaled (ADR-0017); view-definition
writes are deliberately not journaled (ADR-0018 §5).

- `GET /api/v1/buckets` lists buckets (`id`, `name`, `color`).
- `POST /api/v1/buckets` creates a bucket from a `bucket` object (`name`
  required, optional `color`). A blank or duplicate name returns `422`.
- `GET /api/v1/buckets/:id` returns one bucket; unknown ids return `404`.
- `PATCH /api/v1/buckets/:id` patches a bucket's `name`/`color`.
- `DELETE /api/v1/buckets/:id` deletes a bucket and cascades it out of every
  assignment and view set, returning `204 No Content`.
- `GET /api/v1/views` lists views. Each view carries `include_all`, the resolved
  `include` set (the literal `"all"` under `include_all`, otherwise a list of
  bucket ids) and the `exclude` list of bucket ids.
- `POST /api/v1/views` creates a view from a `view` object (`name` required,
  optional `include_all` defaulting to `true`).
- `GET /api/v1/views/:id` returns one view with its resolved filter.
- `PATCH /api/v1/views/:id` patches a view's `name`/`include_all`.
- `DELETE /api/v1/views/:id` deletes a view and its bucket sets (`204`).
- `PUT /api/v1/views/:id/buckets` replaces a view's include/exclude bucket sets.
  Body: `{"include": [..], "exclude": [..]}` (both optional, default `[]`,
  arrays of bucket ids). A malformed id list returns `422`.
- `PUT /api/v1/securities_accounts/:id/buckets` replaces a depot's default
  bucket set (the buckets each position inherits unless overridden). Body:
  `{"bucket_ids": [..]}`.
- `PUT /api/v1/cash_accounts/:id/buckets` replaces a cash account's bucket set.
  Body: `{"bucket_ids": [..]}`.
- `PUT /api/v1/securities_accounts/:id/positions/:security_id/buckets` sets the
  per-position override for one security in one depot. An empty `bucket_ids`
  records the **explicit-empty** state (deliberately no buckets), distinct from
  inheriting the depot default; the override always wins over the depot default.
  The response reports the resolved `override` (`inherit`, `explicit_empty` or
  `explicit`) and the `effective_bucket_ids`.
- `DELETE /api/v1/securities_accounts/:id/positions/:security_id/buckets` clears
  the override, returning the position to inherit the depot default.

The analytics endpoints accept an optional `view` query param (a view id) to
scope the result to the holdings matching that view:

- `GET /api/v1/portfolios/:portfolio_id/valuation?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/allocation?classification_id=<id>&view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/performance?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/risk?view=<id>`

When a `view` is supplied, the response echoes the active view as
`view: {id, name}` (FR-13); the unscoped/default call is unchanged and carries
no `view` field. A malformed view id returns `422`; an unknown view id returns
`404`. The same `view` scope (and the same `422`/`404` contract) applies to the
SOLL target endpoints — `GET`/`PUT
/api/v1/portfolios/:portfolio_id/targets`, `DELETE
/api/v1/portfolios/:portfolio_id/targets/:category_id` and the cash-target
endpoints `GET`/`PUT /api/v1/portfolios/:portfolio_id/cash_target` — where a
view selects the SOLL plan (omitted = the Gesamt plan). The holdings endpoint
(`GET /api/v1/portfolios/:portfolio_id/holdings`) is **not** view-scoped: it
returns the raw per-(depot, security) rows in each security's own currency, so a
client can apply the buckets/views model itself using each row's
`securities_account_id` and `security_id`.

## Audit Journal

Every financial write (create, update, delete) is recorded in an append-only
audit journal in the same database transaction as the write itself, so any
change — including deletions — stays attributable and reversible by inspection.
Market-data ingestion (quote and exchange-rate sync) is operational data and is
deliberately **not** journaled.

- `GET /api/v1/journal` lists journal entries, newest first. Each entry carries
  `actor_type` (`owner_ui`, `api_token_rw`, `api_token_ro`, `import_session`,
  `system_job`) and an optional `actor_label`, the `operation`
  (`create`, `update`, `delete`, `upsert`), the `resource_type`/`resource_id`
  it touched, and the `before`/`after` snapshots (Decimal values are strings).
  Optional filters: `resource_type`, `resource_id`, `actor_type`, `operation`,
  `limit` (default 100, max 1000) and `include_scenarios` (`true` to include
  persisted what-if writes; real writes only by default). The response is
  self-describing: a `meta` object echoes the `as_of` instant, the `order`
  (`inserted_at:desc,id:desc`), the `count` and the `filters` applied.

The journal currently covers the Catalog/Fx contexts (security master-data
writes); the remaining write contexts are armed in sequence.

## MCP Tools

The MCP companion exposes the same local contract as tool calls. Decimal inputs
in MCP schemas are strings.

- `portfolixir.securities.list`
- `portfolixir.securities.create`
- `portfolixir.securities.update`
- `portfolixir.securities.delete`
- `portfolixir.securities.search_online`
- `portfolixir.quotes.sync`
- `portfolixir.quotes.list`
- `portfolixir.quotes.upsert`
- `portfolixir.portfolios.list`
- `portfolixir.portfolios.create`
- `portfolixir.cash_accounts.list`
- `portfolixir.cash_accounts.create`
- `portfolixir.cash_accounts.update`
- `portfolixir.cash_accounts.delete`
- `portfolixir.cash_accounts.set_balance`
- `portfolixir.securities_accounts.list`
- `portfolixir.securities_accounts.create`
- `portfolixir.securities_accounts.update`
- `portfolixir.securities_accounts.delete`
- `portfolixir.transactions.list`
- `portfolixir.transactions.create`
- `portfolixir.transactions.update`
- `portfolixir.transactions.delete`
- `portfolixir.holdings.list`
- `portfolixir.holdings.by_security`
- `portfolixir.portfolios.valuation`
- `portfolixir.exchange_rates.list`
- `portfolixir.exchange_rates.sync`
- `portfolixir.classifications.list`
- `portfolixir.classifications.create`
- `portfolixir.classifications.categories.create`
- `portfolixir.classifications.update`
- `portfolixir.classifications.delete`
- `portfolixir.classifications.categories.update`
- `portfolixir.classifications.categories.delete`
- `portfolixir.classifications.assign`
- `portfolixir.classifications.assign_bulk`
- `portfolixir.classifications.unassign`
- `portfolixir.trades.list`
- `portfolixir.targets.list`
- `portfolixir.targets.set`
- `portfolixir.targets.delete`
- `portfolixir.portfolios.allocation`
- `portfolixir.portfolios.risk`
- `portfolixir.portfolios.cash_target`
- `portfolixir.portfolios.set_cash_target`
- `portfolixir.portfolios.income`
- `portfolixir.portfolios.performance`
- `portfolixir.journal.list`
- `portfolixir.buckets.list`
- `portfolixir.buckets.get`
- `portfolixir.buckets.create`
- `portfolixir.buckets.update`
- `portfolixir.buckets.delete`
- `portfolixir.views.list`
- `portfolixir.views.get`
- `portfolixir.views.create`
- `portfolixir.views.update`
- `portfolixir.views.delete`
- `portfolixir.views.set_buckets`
- `portfolixir.securities_accounts.set_buckets`
- `portfolixir.cash_accounts.set_buckets`
- `portfolixir.securities_accounts.set_position_buckets`
- `portfolixir.securities_accounts.clear_position_buckets`

The `portfolixir.portfolios.valuation`, `portfolixir.portfolios.allocation`,
`portfolixir.portfolios.performance` and `portfolixir.portfolios.risk` tools
accept an optional `view` (a view id) that scopes the result to the holdings
matching that bucket view; the response then echoes the active view.

Since ADR-0020 the SOLL target tools (`portfolixir.targets.list`,
`portfolixir.targets.set`, `portfolixir.targets.delete`) and the cash-target
tools (`portfolixir.portfolios.cash_target` to read,
`portfolixir.portfolios.set_cash_target` to set or clear) also accept an optional
`view` (a view id) that selects the SOLL plan; omitting it addresses the
portfolio-wide Gesamt plan. The cash target moved off the portfolio object onto
the plan, but `portfolixir.portfolios.set_cash_target` without a `view` still
steers the Gesamt cash target, so it keeps the same effect as the legacy
portfolio `cash_target_weight` field. All cash targets and target weights are
exposed and accepted as Decimal strings.
