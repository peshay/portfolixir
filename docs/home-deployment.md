---
layout: docs
title: Home Deployment
description: Local Docker Compose setup for running Portfolixir at home.
---

# Home Deployment

Portfolixir is a local self-hosted application. For a small home setup, run it
from source with Docker Compose.

## Prerequisites

- Docker and Docker Compose;
- a checkout of this repository;
- local `PORTFOLIXIR_API_TOKEN` and `PORTFOLIXIR_MCP_TOKEN` values;
- no real portfolio, bank, broker, wallet, or statement data in fixtures.

## Start

```bash
docker compose up --build
```

Open the app at:

```text
http://localhost:4000
```

The MCP companion is exposed on localhost only:

```text
http://127.0.0.1:4001/mcp
```

## Reset

If the local database should be reset, remove the Compose volume:

```bash
docker compose down -v
docker compose up --build
```

## Rebuild Derived Values

Expensive analytics (currently the daily performance walk) are kept as
durable derived values (ADR-0039): pure recomputable materializations of the
transaction ledger, versioned against every write. They can be dropped and
rebuilt from the ledger at any time with one command, which reports its own
runtime:

```bash
mix portfolixir.derived.rebuild
# inside Docker Compose:
docker compose exec app mix portfolixir.derived.rebuild
```

This never touches financial data — the ledger is read, never written. It is
the recovery step if a derived value is ever suspected stale or corrupt; in
normal operation invalidation is automatic. Freshness is always visible: the
performance chart's basis line and every API/MCP performance payload carry
`as_of` and a `stale` flag.

## Separate MCP Install

The MCP server is developed in this repository but can be installed and run
separately:

```bash
npm install --prefix mcp-server
npm run build --prefix mcp-server
PORTFOLIXIR_API_BASE_URL=http://127.0.0.1:4000 \
PORTFOLIXIR_API_TOKEN=replace-me \
npm start --prefix mcp-server
```

## Versions And Rollback

Every sprint merge is tagged (`vX.Y.Z`, starting at `v0.5.0`) and published
automatically as a GitHub Release with generated notes. A release is a
known-good point to pin or roll a self-hosted instance back to (check out the
tag before building) plus a readable changelog — never an installable
artifact. Migrations are additive; when rolling back across a release that
added migrations, restore the database backup taken before that upgrade.

## Notes

- This setup uses the root `docker-compose.yml`.
- The MCP companion wraps the local JSON API and does not access the database
  directly.
- This setup does not configure broker sync, bank sync, document intake (beyond
  the Portfolio Performance CSV/JSON import), trading, payments, orders,
  rebalancing, or LLM features.
- Public docs are published with GitHub Pages at `portfolixir.app`.
