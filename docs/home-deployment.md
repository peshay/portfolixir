# Home Deployment

Portfolixir is currently a reboot foundation, not a production-ready service.
For a small local or home setup, run it from source with Docker Compose.

## Prerequisites

- Docker and Docker Compose;
- a checkout of this repository;
- no real portfolio, bank, broker, wallet, or statement data in fixtures.

## Start

```bash
docker compose up --build
```

Open the app at:

```text
http://localhost:4000
```

## Reset

If the local database contains old prototype data, reset the Compose volume:

```bash
docker compose down -v
docker compose up --build
```

## Notes

- This setup uses the root `docker-compose.yml`.
- It is for local and home evaluation of the MVP foundation.
- It does not configure broker sync, bank sync, imports, document intake,
  trading, payments, orders, rebalancing, MCP, or LLM features.
- Public docs are published with GitHub Pages at `portfolixir.app`.
