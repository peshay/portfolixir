---
layout: docs
title: Product Documentation
description: Portfolixir app handbook for current local portfolio tracking behavior.
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

### Holdings Calculation

Current holdings are not entered manually. They are derived from all
transactions over time, so the state is reproducible and traceable. Each holding
also carries a moving-average cost basis and the unrealized profit/loss
(absolute and percentage) against the latest stored price, in the security's own
currency.

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

## Exchange Rates and Valuation

Portfolios can hold securities and cash in several currencies. Exchange rates are
stored against a EUR hub (with European Central Bank sync), and other pairs are
triangulated through it. The live portfolio valuation converts each position's
market value and each cash balance into the portfolio base currency; a position
with no quote or no rate path to the base currency is reported as unvalued, so a
missing price or rate never distorts the total or the weights.

## Cash and cash quote

Cash is part of the portfolio, not an afterthought. Each portfolio has one or
more cash accounts, and the live valuation reports the **total cash**, the
**total including cash**, and the **cash quote** — cash as a share of the whole
portfolio (`total_cash / total_with_cash`) — so you can see your liquidity and
dry powder at a glance, converted into the portfolio base currency.

A depot's settlement cash stays up to date on its own: buys, sells, dividends,
interest, fees and taxes move it as you record those transactions, so the cash
that belongs to investing needs no separate upkeep.

For external accounts (a current account, savings, a business account), the goal
is visibility without bookkeeping. Instead of mirroring every booking, you **set
an account's balance directly** — type the figure your banking app shows as a
dated **snapshot** (`POST /api/v1/cash_accounts/:id/balance`, or the
`cash_accounts.set_balance` MCP tool). The balance then anchors to that amount,
and only bookings dated strictly after the snapshot change it; so moving money
between your own accounts needs no transfer entry — you just restate each
balance now and then. The amount may be negative (an overdraft), and the same
snapshot can later be filled automatically over the API (a script or a read-only
bank export) — without turning Portfolixir into a banking app. This follows the
design recorded in
[ADR-0009](decisions/0009-cash-as-balance-snapshots.html).

Still planned: a per-account flag to mark which accounts count toward the cash
quote (so a business account can be visible without distorting your private
quote).

## Imports

The Imports page accepts Portfolio Performance transaction exports in CSV or
JSON v1 format. Files are parsed into a preview before any records are saved.
The preview shows translated transaction-kind labels, the records that would be
created, and account/depot mappings for missing targets.

Parser warnings appear in a scrollable box with a copy button. The copied text
uses stable `Row N: message` lines so the diagnostics can be kept with the
source export. Applying the import is atomic and uses content hashes to skip
duplicates on re-run.

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
  logo candidates on startup, and is also triggered after imports.
  ETF logo discovery tries known issuer names before the individual fund name
  (for example iShares, Vanguard, Lyxor, Amundi, Xtrackers, SPDR, Invesco).
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
