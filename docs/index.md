---
layout: docs
title: Local portfolio tracking
description: Portfolixir public documentation for local portfolio tracking.
---

# Local portfolio tracking

Portfolixir is a self-hosted Phoenix application for securities tracking with
auditable manual transactions, derived holdings, and stored quote history.

## Current Scope

The application is intentionally scoped to local portfolio records. It stays
small, deterministic, and available through the web UI, JSON API, and MCP
companion.

- Create securities, portfolios, cash accounts, and depots.
- Record manual transactions across the Portfolio Performance kinds (buy, sell,
  dividend, interest, deposit, removal, fee, tax, tax refund, cash transfer,
  and the delivery/transfer kinds) and derive holdings with cost basis and
  unrealized profit/loss.
- Bulk-import Portfolio Performance CSV/JSON v1 exports through a
  preview-and-apply Imports view with content-hash idempotency.
- Organise securities into classification trees (custom plus built-in
  asset-class and currency trees), set per-category target weights, and read a
  target/actual allocation breakdown with per-category drift.
- Value multi-currency holdings and cash through stored exchange rates (EUR hub).
- Scope wealth into buckets and views (ADR-0018) to report on subsets.
- Store and display quote history with a security detail chart, and review
  performance (TTWROR) and income (dividends/interest) reports.
- Audit every financial write through an append-only journal.

Open the [App Handbook](product-documentation.html) for the product walkthrough,
[Home Deployment](home-deployment.html) for a local Docker Compose setup, or
[API and MCP](integration/api-and-mcp.html) for integration details.

## Product Workflow

1. Create securities, a portfolio, and depots linked to cash accounts — or
   bulk-import a Portfolio Performance export to seed all of them at once.
2. Record manual transactions, or apply the imported ones after previewing.
3. Review holdings, cost basis, and unrealized profit/loss derived from history.
4. Organise securities into classification trees and set per-category targets.
5. Read the target/actual allocation breakdown with drift to plan rebalancing.
6. Store quote history, inspect charts, and review performance and income.

## Theme, Accent, and Language

The UI supports System, Light, and Dark themes, Violet, Teal, and Coral accent
choices, and English and German language switching. The initial state follows
the browser language and system theme. Language, theme, and accent are runtime
preferences and do not affect persisted financial values.

## API and MCP

Supported local actions are available through `/api/v1`. The MCP companion
lives in `mcp-server/` and wraps that API so MCP clients use the same local
application contract as other integrations. The supported routes and tools are
documented in [API and MCP](integration/api-and-mcp.html).

## Architecture

For a high-level view of how Portfolixir is built, see the
[Architecture Overview](architecture.html) and the
[Architecture Decisions](decisions/index.html) log.

## Development

Start with the [Story Workflow](development/story-workflow.html) and
[Development Guide](development/guide.html) before changing behavior.
