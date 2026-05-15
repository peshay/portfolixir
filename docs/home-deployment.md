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

## Notes

- This setup uses the root `docker-compose.yml`.
- The MCP companion wraps the local JSON API and does not access the database
  directly.
- This setup does not configure broker sync, bank sync, imports, document
  intake, trading, payments, orders, rebalancing, or LLM features.
- Public docs are published with GitHub Pages at `portfolixir.app`.
