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

Each quote entry captures a timestamp and price. Price history is persisted so that
security detail charts are built from local records only, not live feeds.

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

