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

- Create securities.
- Create portfolios.
- Link depots to cash accounts.
- Record manual buy and sell transactions.
- Review current holdings derived from transaction history.
- Store and display quote history with a security detail chart.

Open the [App Handbook](product-documentation.html) for the product walkthrough,
[Home Deployment](home-deployment.html) for a local Docker Compose setup, or
[API and MCP](integration/api-and-mcp.html) for integration details.

## Product Workflow

1. Create securities with local identifying data.
2. Create a portfolio.
3. Link one depot to one cash account.
4. Record manual buy and sell transactions.
5. Review current holdings.
6. Store quote history and inspect charts.

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
