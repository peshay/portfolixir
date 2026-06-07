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
  `asset_class` is a stable string code such as `equity`, `etf`, `crypto`,
  `bond`, or `government_bond`.
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
  account and credits the counter account).
- `POST /api/v1/cash_accounts` creates a cash account with a `cash_account`
  object.
- `GET /api/v1/securities_accounts` lists depots/securities accounts.
- `POST /api/v1/securities_accounts` creates a depot/securities account with a
  `securities_account` object.

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

- `GET /api/v1/transactions` lists manual transactions.
- `POST /api/v1/transactions` creates a manual buy or sell transaction with a
  `transaction` object.
- `GET /api/v1/portfolios/:portfolio_id/holdings` lists derived holdings for a
  portfolio; unknown portfolios return `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/valuation` returns a live valuation of a
  portfolio: each held position priced from its latest quote close, a
  `total_value`, and each valued position's `weight` (its share of the total).
  Each position's market value is converted into the portfolio
  `base_currency` (top-level field) from stored exchange rates; per-position
  `security_currency` shows the native currency. A position with no quote **or**
  no exchange-rate path to the base currency is returned with `valued: false`
  and `null` market value and weight, so a missing price or rate never distorts
  the total. Unknown portfolios return `404 Not Found`.
  Weights are raw shares (`market_value / total_value`) emitted at full Decimal
  precision; because they are normalized ratios they need not sum to exactly
  `1` (round for display). Market values and `total_value` are exact.
  The valuation also carries cash: `cash_balances` lists each cash account
  (`balance` in its own currency, plus `base_value`/`valued` after converting to
  the base currency), `total_cash` is the base-currency sum of the valued cash
  accounts, and `total_with_cash` is `total_value + total_cash`. An account whose
  currency has no rate path to the base is reported `valued: false` and excluded
  from `total_cash`, mirroring how unpriceable positions are handled.
- `GET /api/v1/securities/:security_id/trades` returns FIFO-matched trades for
  one security: open lots, closed round-trips (with realised P&L and holding
  period in days) and any orphan sells.

## Exchange Rates

- `GET /api/v1/exchange_rates` lists stored exchange rates. Rates are kept
  against the EUR hub (`1 base_currency = rate quote_currency`); other pairs are
  derived by triangulation, and `GBX` (pence) is handled as `GBP × 100`.
- `POST /api/v1/exchange_rates/sync` fetches the latest rates from the configured
  provider (ECB daily reference rates by default) and returns `{provider,
  status, upserted}`. A provider failure returns `502 Bad Gateway`.

## Classifications

Classification trees organise securities like folders. Built-in trees
(`asset_class`, `currency`) are derived automatically and locked; custom trees
are editable. Editing a built-in tree returns `422 Unprocessable Entity`.

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
- `portfolixir.securities.search_online`
- `portfolixir.quotes.sync`
- `portfolixir.quotes.list`
- `portfolixir.quotes.upsert`
- `portfolixir.portfolios.list`
- `portfolixir.portfolios.create`
- `portfolixir.cash_accounts.list`
- `portfolixir.cash_accounts.create`
- `portfolixir.securities_accounts.list`
- `portfolixir.securities_accounts.create`
- `portfolixir.transactions.list`
- `portfolixir.transactions.create`
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
