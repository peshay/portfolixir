# Product Documentation

## Positioning and scope

Portfolixir is a self-hosted, local-first Phoenix application for managing a
single portfolio workflow. It is intentionally narrow:

- Manual creation of securities, portfolio, accounts, and transactions.
- Holdings are derived from transaction history.
- Security prices are stored as quote history and shown in a security detail chart.
- No broker sync, bank sync, trading engine, payment flow, order flow, rebalancing,
  document ingestion, or AI-assisted behavior.

## Product modules in practice

The codebase is split into three local domain modules plus the web layer:

- `Portfolixir.Catalog`
  - Securities and quote entities
  - Security metadata and quote records
- `Portfolixir.Portfolios`
  - Portfolios
  - Cash accounts
  - Depots
- `Portfolixir.Ledger`
  - Manual buy/sell transactions
  - Holdings calculation from immutable history
- `PortfolixirWeb`
  - Routes, pages, and LiveViews

## Core workflow

1. Create one or more securities with basic identifying data.
2. Create a portfolio.
3. Create one cash account and one depot, and link them.
4. Record manual buy and sell transactions with Decimal-based quantity and price values.
5. Open the holdings view to verify current position per security.
6. Record security quotes over time and keep history for reproducible charts.
7. Review current holdings and quote chart behavior directly in the app.

## Features explained

### Securities

Each security is a first-class object with stable identity fields and market metadata.
They are the basis for all transaction and holdings calculations.

### Portfolio and accounts

The portfolio owns one working set of account models:

- cash account: tracks available liquidity context
- depot/account: stores security positions linked to that cash account

### Manual transactions

Transactions are explicit and auditable. A transaction defines:

- date
- security
- direction (buy/sell)
- quantity (Decimal)
- unit price (Decimal)
- optional taxes, fees, and notes

### Holdings calculation

Current holdings are not entered manually. They are derived from all
transactions over time, so the state is reproducible and traceable.

### Quote history

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
- Quote-history fetch uses Yahoo Finance for both. Two reasons:
  - PP's own API exposes only search, no price history.
  - CoinGecko's free public API caps history at 365 days
    (`error_code 10012`); Yahoo returns the full daily series for
    crypto via the `<TICKER>-<CURRENCY>` symbol form (e.g. `BTC-USD`).

Yahoo is queried with `period1=0` and `period2=<now>` so it returns the
full available daily history — `range=max` silently downsamples to
monthly for long-history tickers.

Securities whose `provider` is unrecognised are skipped silently.

### Security detail chart

Clicking a row in the securities list opens `/securities/:id`. The detail
page shows a server-rendered SVG price chart with:

- Time-range buttons (1M / 3M / 6M / YTD / 1Y / 3Y / 5Y / MAX).
- A *Log scale* toggle (logarithmic Y-axis).
- A *Show transactions* toggle that overlays Buy/Sell markers from the
  ledger.
- A *Sync prices for this security* button.

## Interface behavior

- Theme: system, light, and dark modes are supported.
- Language: English and German can be selected in the UI.
- Theme and language are user preferences and do not affect stored financial
  values.

## Non-goals today

- No automatic trading or order execution.
- No bank, broker, or wallet integrations.
- No payment scheduling or settlement workflows.
- No external import/parsing features for statements.
