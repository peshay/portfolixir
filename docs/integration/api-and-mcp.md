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
  `sort`, `direction`, and holding_status (`all`, `held`, or `not_held`).
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
- `GET /api/v1/cash_accounts` lists cash accounts.
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
  Positions without a quote are returned with `valued: false` and `null`
  market value and weight. Unknown portfolios return `404 Not Found`.
  Weights are raw shares (`market_value / total_value`) emitted at full Decimal
  precision; because they are normalized ratios they need not sum to exactly
  `1` (round for display). Market values and `total_value` are exact.
  Single currency: quote closes are summed without FX conversion, so
  `total_value` and weights are only meaningful when all positions share one
  currency (consistent with holdings and trades; an FX layer is future work).
- `GET /api/v1/securities/:security_id/trades` returns FIFO-matched trades for
  one security: open lots, closed round-trips (with realised P&L and holding
  period in days) and any orphan sells.

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
- `portfolixir.trades.list`
