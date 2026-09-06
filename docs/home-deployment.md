---
layout: docs
title: Home Deployment
description: Local Docker Compose setup for running Portfolixir at home.
---

# Home Deployment

Portfolixir is a local self-hosted application. For a small home setup, build
the production release with Docker Compose and put your own reverse proxy in
front of it. The Compose file publishes the application and the MCP companion
on the host's loopback interface only and never publishes the database.

## Prerequisites

- Docker and Docker Compose;
- a checkout of this repository;
- a `.env` file with the secrets (see below);
- no real portfolio, bank, broker, wallet, or statement data in fixtures.

## Secrets and settings

Copy `.env.example` to `.env`. The stack refuses to start while a secret is
missing, and the application refuses to boot with a token shorter than 32
bytes or equal to a placeholder. Generate each token with
`openssl rand -base64 48`, and `POSTGRES_PASSWORD` with `openssl rand -hex 32`:
the Compose file splices it into the database URL, where a `/` or `#` from
base64 would break the connection string.

| Variable | Required | What it does |
|---|---|---|
| `SECRET_KEY_BASE` | yes | Signs the session cookie; the signing salts are derived from it. |
| `POSTGRES_PASSWORD` | yes | The database password; the app builds its connection string from it. |
| `PORTFOLIXIR_API_TOKEN` | yes | The bearer token of the JSON API and of the MCP companion's upstream calls. |
| `PORTFOLIXIR_MCP_TOKEN` | yes | The bearer token an MCP client presents to the companion. |
| `PORTFOLIXIR_UI_PASSWORD` | no | Set it to require a login on the web UI (ADR-0045). Unset, the UI is open — acceptable only behind reverse-proxy authentication. |
| `PHX_HOST` | no | The name the reverse proxy serves (default `localhost`). Requests under any other `Host` are refused with 421. |
| `PORTFOLIXIR_ALLOWED_HOSTS` | no | Further names, comma-separated (a LAN address, a second proxy name). The Compose file adds `app`, the name the MCP companion reaches the application under. |
| `PHX_FORCE_SSL` | no | `true` redirects plain HTTP and sets HSTS when TLS is terminated for this instance. |
| `PORTFOLIXIR_TRUSTED_PROXIES` | no | Addresses or CIDR blocks, comma-separated, whose `X-Forwarded-For` the login and token throttle believes. Empty, the throttle counts the connecting address, which behind a proxy is the proxy. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | no | Further `Host` names the MCP companion answers under (a proxy name), comma-separated. |

Without a UI password and with the port opened beyond loopback, the
application logs a warning at startup naming this table.

## Start

```bash
docker compose up --build
```

The first start builds the release image, runs the migrations and starts the
application. Open the app through your reverse proxy, or directly on the host
at:

```text
http://127.0.0.1:4000
```

The MCP companion is exposed on localhost only:

```text
http://127.0.0.1:4001/mcp
```

## Reverse proxy

The application listens on loopback; a reverse proxy on the same host (Caddy,
nginx, Traefik) terminates TLS and forwards to `127.0.0.1:4000`. It must pass
the original `Host` header (set `PHX_HOST` to that name) and
`X-Forwarded-Proto: https`, which is what marks the session cookie `Secure`
and what `PHX_FORCE_SSL` reads, and `X-Forwarded-For`. Name the address the
proxy connects from in `PORTFOLIXIR_TRUSTED_PROXIES` — through the published
port that is the Docker bridge gateway (`docker network inspect` shows it, a
block such as `172.16.0.0/12` covers it) — so that the throttle counts the
client behind the proxy rather than the proxy: without it, ten wrong passwords
from anyone the proxy admits lock the login for everyone behind it, the
operator included. Reverse-proxy authentication and the built-in UI password
compose: keep either, or both.

## Development stack

The development configuration — source mounted, Mix present, debug pages,
origin checks off, the database port published for local tooling — lives in
`docker-compose.dev.yml` and is never the documented deployment:

```bash
docker compose -f docker-compose.dev.yml up --build
```

## Reset

If the local database should be reset, remove the Compose volume:

```bash
docker compose down -v
docker compose up --build
```

Take a database backup before an upgrade: migrations are additive, and a
rollback across a release restores that backup.

## Rebuild Derived Values

Expensive analytics (currently the daily performance walk) are kept as
durable derived values (ADR-0039): pure recomputable materializations of the
transaction ledger, versioned against every write. They can be dropped and
rebuilt from the ledger at any time with one command, which reports its own
runtime:

```bash
mix portfolixir.derived.rebuild
# inside the release container:
docker compose exec app bin/portfolixir eval "Portfolixir.Release.rebuild_derived()"
```

This never touches financial data — the ledger is read, never written. It is
the recovery step if a derived value is ever suspected stale or corrupt; in
normal operation invalidation is automatic. Freshness is always visible: the
performance chart's basis line and every API/MCP performance payload carry
`as_of` and a `stale` flag.

### Background refresh

A write does not only mark the affected figures stale — it schedules their
recomputation. Shortly after a booking, an import or a quote update, the
affected values are re-materialized in the background, so the next page you
open shows a number instead of a "computing" cue. Bookings are collected and
drained together: importing a large export costs one refresh, not one per row.

Two settings tune it, both in `config/config.exs`:

| Setting | Default | What it does |
|---|---|---|
| `quiet_ms` | `500` | How long the refresher waits for the writing to stop before recomputing. |
| `max_delay_ms` | `10_000` | The longest it will wait, so a continuous stream of writes still gets drained. |

The refresh is an optimisation of *when* the work happens, never of whether
the number is right: a stale value is still recomputed on read, so a refresher
that is slow, failing or switched off costs latency and never freshness.

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

- This setup uses the root `docker-compose.yml` (a production release built
  from `Dockerfile.release`); `docker-compose.dev.yml` is the development
  stack.
- The web UI is open by default and locked by one variable
  (`PORTFOLIXIR_UI_PASSWORD`); the instance binds loopback and refuses
  foreign `Host` names (ADR-0045).
- The MCP companion wraps the local JSON API and does not access the database
  directly.
- This setup does not configure broker sync, bank sync, document intake (beyond
  the Portfolio Performance CSV/JSON import), trading, payments, orders,
  rebalancing, or LLM features.
- Public docs are published with GitHub Pages at `portfolixir.app`.
