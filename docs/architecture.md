---
layout: docs
title: Architecture Overview
description: Lightweight arc42-style architecture overview for Portfolixir.
---

# Architecture Overview

This page is a deliberately small architecture overview. It follows a subset
of the [arc42](https://arc42.org/) template, keeping only the sections that
earn their place for a small self-hosted monolith. Sections that arc42 defines
but Portfolixir does not need yet are listed under
[Omitted sections](#omitted-arc42-sections) with the reason.

To avoid duplication, this page links to existing documents instead of
restating them:

- product behaviour: [Product Documentation](product-documentation.html)
- agent and contributor rules: [`AGENTS.md`](https://github.com/peshay/portfolixir/blob/main/AGENTS.md)
- API and MCP contract: [API and MCP](integration/api-and-mcp.html)
- local deployment: [Home Deployment](home-deployment.html)
- recorded decisions: [Architecture Decisions](decisions/index.html)

## 1. Introduction and Goals

Portfolixir is a self-hosted Phoenix application for local portfolio tracking.
It keeps securities, portfolios, depots, cash accounts, manual transactions,
derived holdings, and quote history in one auditable local app.

Top quality goals, in priority order:

1. **Auditability** — financial state is reproducible from immutable inputs.
2. **Correctness of money** — exact decimal arithmetic, never floats.
3. **Smallness** — the scope stays narrow and the codebase stays readable.
4. **Local-first operation** — runs fully on the operator's own machine.

Explicit non-goals: it is not a broker, bank, trading, payment, order, or
rebalance platform. See "Non-goals today" in the
[Product Documentation](product-documentation.html#non-goals-today).

## 2. Constraints

- Elixir/Phoenix monolith plus a thin TypeScript MCP companion.
- PostgreSQL as the only data store.
- `Decimal` for all persisted money, quantities, prices, fees, taxes, and FX
  rates. Floats are not allowed for persisted financial values.
- No external LLM calls from the app.
- No market-data network calls in tests; synthetic fixtures only.
- No stored API keys in source; local bearer tokens come from the environment.
- Architecture decisions must not change silently — they are recorded as
  [ADRs](decisions/index.html).

The binding rule set lives in
[`AGENTS.md`](https://github.com/peshay/portfolixir/blob/main/AGENTS.md)
("Hard Rules", "Security Boundaries"); this page only summarises it.

## 3. Context and Scope

Portfolixir runs locally and talks to a small set of external systems. All
network egress is for read-only market data and logos.

```text
                         +------------------------+
        Web browser ---> |                        |
                         |      Portfolixir       | ---> PostgreSQL (local)
   MCP client --> MCP    |   (Phoenix monolith)   |
   companion --> JSON    |                        | ---> Yahoo Finance  (quote history)
   API ----------------> |   /api/v1  +  Web UI   | ---> CoinGecko      (crypto search)
                         |                        | ---> Portfolio Perf.(security search)
                         +------------------------+ ---> Wikipedia      (logo lookup)
```

- **Inbound:** a human via the web UI, and integrations via `/api/v1`. The MCP
  companion is itself a client of `/api/v1`; it never reaches the database or
  Elixir contexts directly.
- **Outbound:** read-only quote and search providers plus logo lookup. There
  are no write integrations to banks, brokers, wallets, or payment systems.

## 4. Solution Strategy

| Goal | Strategy |
| --- | --- |
| Auditability | Holdings and trades are **derived** from an immutable transaction history, never stored as mutable state. |
| Money correctness | `Decimal` everywhere; decimals serialise as strings across the API and MCP boundary. |
| Smallness | A modular monolith with a few bounded contexts instead of services. |
| Local-first | Single Docker Compose stack; the MCP companion is optional and separable. |
| Safe integrations | The MCP companion is a thin wrapper over the public JSON API only. |

These choices are recorded individually in the
[Architecture Decisions](decisions/index.html) log.

## 5. Building Block View

### Level 1 — system

The OTP application supervises (`lib/portfolixir/application.ex`):

- `Portfolixir.Repo` — Ecto/PostgreSQL access.
- `Phoenix.PubSub` — in-process messaging.
- `Task.Supervisor` (`LogoSupervisor`) — background logo fetches.
- `Portfolixir.Catalog.QuoteSync` — scheduler that pulls daily closes on a
  configurable interval.
- `PortfolixirWeb.Endpoint` — HTTP, LiveView, and JSON API.

### Level 2 — domain contexts

| Context | Responsibility | Key modules |
| --- | --- | --- |
| `Portfolixir.Catalog` | Securities, quote history, quote sync, online search, logos | `security`, `quotes`, `quote_sync` (Yahoo), `security_search` (CoinGecko, Portfolio Performance) |
| `Portfolixir.Portfolios` | Portfolios, cash accounts, depots | `portfolio`, `cash_account`, `securities_account` |
| `Portfolixir.Ledger` | Manual transactions, derived holdings, FIFO trades | `transaction`, `positions`, `trade_matcher` |
| `Portfolixir.Imports` | Portfolio Performance CSV/JSON v1 import (parse, preview, apply) | `portfolio_performance` (csv/json parsers), `preview`, `applier`, `mapping` |
| `PortfolixirWeb` | LiveViews, JSON API controllers, auth plug, components | `live/*`, `controllers/api/v1/*`, `plugs/api_auth_plug` |
| `mcp-server/` | TypeScript MCP companion wrapping `/api/v1` | `server.ts`, `tools.ts`, `api-client.ts`, `http.ts` |

Domain contexts stay separate from LiveViews, controllers, and MCP wrapper
code. The dependency direction is one-way: web and MCP depend on contexts;
contexts do not depend on the web layer.

## 8. Crosscutting Concepts

- **Decimal money** — all financial fields use `Decimal`; API/MCP responses
  serialise them as strings. See
  [ADR-0003](decisions/0003-decimal-for-money.html).
- **Derived holdings** — current positions and FIFO trades are computed from
  transactions on read. See
  [ADR-0004](decisions/0004-holdings-derived-from-transactions.html).
- **Idempotent imports** — Portfolio Performance imports preview before
  applying and use content hashes to skip duplicates on re-run; applying is
  atomic.
- **Quote provider split** — search uses Portfolio Performance (stocks/ETFs)
  and CoinGecko (crypto); quote history uses Yahoo Finance for both. See
  [ADR-0005](decisions/0005-quote-provider-split.html).
- **Local bearer auth** — `/api/v1` requires `PORTFOLIXIR_API_TOKEN`; the MCP
  HTTP transport requires `PORTFOLIXIR_MCP_TOKEN`. No keys live in source.
- **Internationalisation and theming** — System/Light/Dark themes, accent
  choice, and EN/DE language are runtime preferences and never affect persisted
  financial values.
- **Test isolation** — tests use synthetic fixtures and fake providers; no real
  network calls.

## 11. Risks and Technical Debt

- **External provider drift** — Yahoo/CoinGecko/Portfolio Performance are
  unofficial endpoints and can change shape or rate-limit without notice.
- **Single-portfolio assumption** — several flows assume one working portfolio;
  broadening this would touch multiple contexts.
- **No runtime quality gates documented** — performance and availability targets
  are intentionally unspecified for a local single-user app.

## 9. Architecture Decisions

Decisions are recorded as short ADRs in the
[Architecture Decisions](decisions/index.html) log. Per
[`AGENTS.md`](https://github.com/peshay/portfolixir/blob/main/AGENTS.md),
architecture decisions must not change silently; add or supersede an ADR when a
decision changes.

## Omitted arc42 sections

Kept out on purpose to stay lightweight:

- **6. Runtime View** — the supervision tree in section 5 plus the request flow
  in [API and MCP](integration/api-and-mcp.html) cover the few notable runtime
  paths.
- **7. Deployment View** — covered by [Home Deployment](home-deployment.html)
  and the root `docker-compose.yml`.
- **10. Quality Requirements** — no formal quality scenarios for a local
  single-user app beyond the goals in section 1.
- **12. Glossary** — domain terms are defined inline in the
  [Product Documentation](product-documentation.html).
</content>
</invoke>
