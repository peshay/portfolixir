---
layout: docs
title: API and MCP
description: Portfolixir JSON API and MCP companion reference.
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
  `sort`, `direction`, holding_status (`all`, `held`, or `not_held`), and
  `limit`/`offset` for pagination (both non-negative integers). Use these to
  page large catalogs instead of fetching the whole table at once.
- `POST /api/v1/securities` creates a security with a `security` object.
  `asset_class` is a stable string code: `equity`, `etf`, `fund`,
  `government_bond`, `bond`, `crypto`, `commodity`, `index`, `other`, plus the
  certificate/leverage codes `warrant`, `knock_out`, `factor_certificate`,
  `discount_certificate`, `bonus_certificate`, `express_certificate`,
  `reverse_convertible`. Leave it empty to let the class be inferred from the
  name/ISIN/ticker on read.
- `GET /api/v1/securities/:id` returns one security.
- `PATCH /api/v1/securities/:id` updates a security with a `security` object.
- `DELETE /api/v1/securities/:id` deletes a security when no dependent
  transactions or quote history reference it; referenced securities return
  `409 Conflict`.
- `GET /api/v1/securities/search` searches configured online security providers.
  Query params: `query`; optional `type` with `security` or `crypto`.

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
  object.
- `GET /api/v1/cash_accounts/:id` returns one cash account.
- `PATCH /api/v1/cash_accounts/:id` updates a cash account (`name`,
  `currency_code`, `notes`); `portfolio_id` cannot be changed.
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
  `transaction` object.
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
  Unknown portfolios return `404 Not Found`. Optional filters: `security_id`,
  `securities_account_id`.
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
  the base currency), `total_cash` is the base-currency sum of the valued cash
  accounts, and `total_with_cash` is `total_value + total_cash`. `cash_quote` is
  the cash share of the whole portfolio (`total_cash / total_with_cash`, `0` when
  there is nothing to value yet). An account whose currency has no rate path to
  the base is reported `valued: false` and excluded from `total_cash`, mirroring
  how unpriceable positions are handled.
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
  first plausible day. Securities without quotes are priced at the latest own
  trade price (see the valuation endpoint). Unknown portfolios return
  `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/targets` lists a portfolio's stored
  target weights (the SOLL side of the allocation). Optional `classification_id`
  scopes the list to one tree. Unknown portfolios return `404 Not Found`.
- `PUT /api/v1/portfolios/:portfolio_id/targets` upserts target weights for one
  classification. The body is `{"classification_id": id, "targets": [{"category_id":
  id, "target_weight": "0.25"}]}`. Each `target_weight` is a string fraction in
  `[0, 1]`; targets need not sum to `1`. Only the supplied categories are
  changed. A category from another tree returns `422 Unprocessable Entity`, and an
  unknown classification returns `404 Not Found`.
- `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` removes a
  portfolio's target weight for one category and returns `{deleted}` (the number
  of rows removed).
- `GET /api/v1/portfolios/:portfolio_id/allocation` returns the SOLL/IST
  breakdown for one classification (required `classification_id` query param; a
  missing one returns `422 Unprocessable Entity`). For each category it reports
  `parent_id` and `depth` (the categories form a tree), `color`,
  `own_market_value` (positions assigned directly to it), `market_value` (its
  whole subtree rolled up), `actual_weight` (the rolled-up share of
  `total_value`), `target_weight`, `drift_weight`
  (`target_weight - actual_weight`), and `drift_value` (the drift restated in
  the base currency). A position assigned to a child counts toward that child
  **and every ancestor**, so a parent category with a target is compared
  against its subtree rather than showing 0%; the rows come back in tree order
  (parent before its children). Because parents aggregate their children, the
  per-category `actual_weight` values intentionally do not sum to 1 across
  levels — only the leaves plus `unassigned` do. Securities held but not
  assigned in the tree are summed into `unassigned`. Weights mirror the
  valuation: shares of the valued positions' total, cash excluded. Unknown
  portfolios or classifications return `404 Not Found`.
- `GET /api/v1/securities/:security_id/trades` returns FIFO-matched trades for
  one security: open lots, closed round-trips (with realised P&L and holding
  period in days) and any orphan sells. Optional `from`/`to` (ISO dates) filter
  each leg by its own date: open lots by open date, closed round-trips by close
  date, orphan sells by sell date.

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
- `portfolixir.portfolios.performance`
