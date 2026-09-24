---
layout: docs
title: Home Deployment
description: Local Docker Compose setup for running Portfolixir at home.
lang: en
lang_en: /home-deployment.html
lang_de: /de/home-deployment.html
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
bytes or equal to a placeholder, and with a `SECRET_KEY_BASE` shorter than 64
bytes, equal to a placeholder, or equal to a value committed in this
repository. Generate each token and `SECRET_KEY_BASE` with
`openssl rand -base64 48`, and `POSTGRES_PASSWORD` with `openssl rand -hex 32`:
the Compose file splices it into the database URL, where a `/` or `#` from
base64 would break the connection string.

| Variable | Required | What it does |
|---|---|---|
| `SECRET_KEY_BASE` | yes | Signs the session cookie; the signing salts are derived from it. |
| `POSTGRES_PASSWORD` | yes | The database password; the app builds its connection string from it. |
| `PORTFOLIXIR_API_TOKEN` | yes | The bearer token of the JSON API and of the MCP companion's upstream calls. |
| `PORTFOLIXIR_MCP_TOKEN` | yes | The bearer token an MCP client presents to the companion. |
| `PORTFOLIXIR_UI_PASSWORD` | no | Set it to require a login on the web UI (ADR-0045). Unset, the UI is open — acceptable only behind reverse-proxy authentication. Changing it ends every login made with the old password. |
| `PORTFOLIXIR_SESSION_DAYS` | no | How many days a UI login stays valid (default 30). The window slides: using the instance renews it, so you are asked again only after a full period of not using it. `0` ends the login when the browser closes. |
| `PHX_HOST` | no | The name the reverse proxy serves (default `localhost`). Requests under any other `Host` are refused with 421. |
| `PORTFOLIXIR_ALLOWED_HOSTS` | no | Further names, comma-separated (a LAN address, a second proxy name). The Compose file adds `app`, the name the MCP companion reaches the application under. |
| `PHX_FORCE_SSL` | no | `true` redirects plain HTTP to HTTPS and sets HSTS. Set it once the reverse proxy terminates TLS and sends `X-Forwarded-Proto` from loopback or from an address named in `PORTFOLIXIR_TRUSTED_PROXIES`; off by default, because a loopback instance has no TLS to redirect to and the application never terminates TLS itself. |
| `PORTFOLIXIR_TRUSTED_PROXIES` | no | Addresses or CIDR blocks, comma-separated, whose `X-Forwarded-For` (the login and token throttle's source) and `X-Forwarded-Proto` (the scheme) the application believes. Empty, the throttle counts the connecting address, which behind a proxy is the proxy, and only a proxy on loopback can mark a request as HTTPS. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | no | Further `Host` names the MCP companion answers under (a proxy name), comma-separated. |

Without a UI password and with the port opened beyond loopback, the
application logs a warning at startup naming this table; with a UI password
shorter than 12 characters it warns as well, and starts either way.

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
operator included. The same setting decides whose `X-Forwarded-Proto` is
believed: loopback and the named addresses only, so a proxy reaching the
container through the Docker bridge must be named there for the cookie to be
`Secure` and for `PHX_FORCE_SSL` to see HTTPS. Failed logins are also counted
across all sources together over a rolling window, so guesses spread over many
addresses cannot multiply; past that ceiling the login asks everyone to wait,
the operator included, while sessions already logged in keep working.
Reverse-proxy authentication and the built-in UI password compose: keep
either, or both.

### The TLS contract

TLS is the proxy's job, in full. The application never terminates TLS and
never redirects to HTTPS on its own, because its safe default is a loopback
instance that has no certificate; what it offers is the opt-in. The contract,
in four lines:

1. The proxy terminates TLS and forwards plain HTTP to `127.0.0.1:4000`.
2. It forwards `Host`, `X-Forwarded-Proto` and `X-Forwarded-For` unchanged,
   and it forwards WebSocket upgrades on `/live/websocket` (Caddy does by
   default; nginx needs `proxy_set_header Upgrade $http_upgrade;` and
   `proxy_set_header Connection "upgrade";`) — the live pages run over that
   socket.
3. Once that is in place, `PHX_FORCE_SSL=true` makes the application redirect
   any plain-HTTP request it still sees to HTTPS and send
   `Strict-Transport-Security` on the HTTPS answers. Without the variable the
   application serves what it is given; with it, a proxy that forgets
   `X-Forwarded-Proto`, or whose address is neither loopback nor named in
   `PORTFOLIXIR_TRUSTED_PROXIES`, produces a redirect loop, which is the
   variable telling you the header is missing or not believed.
4. The proxy passes the application's response headers through unchanged and
   injects nothing into the pages. Every page carries a Content-Security-Policy
   (next section); a proxy that adds a script or a stylesheet — a banner, an
   analytics tag — sees it blocked in the browser, and one that rewrites the
   header disables the protection.

## Content Security Policy

Every browser page is served with a `Content-Security-Policy` header, built
per request. Scripts run only from the instance itself and from the three
boot scripts in the page's own `<head>` and `<body>`, each admitted by a
nonce minted for that request; there is no inline event handler anywhere,
no `eval`, and no script from any other origin. Styles come from the
instance's stylesheet plus inline `style` attributes (the pages colour
swatches and indent tree rows with them); images from the instance plus
`data:` URLs, which the chart export uses to draw its picture; connections
go to the instance and to its own WebSocket origin under the name the
browser addressed it by; nothing is embedded, nothing frames the pages from
another site, and forms post only to the instance.

Nothing needs configuring. Two things follow from it for an operator: the
proxy must pass the `Host` header the browser sent (the socket origin in the
policy is that name, so a proxy that rewrites `Host` leaves the live pages
unable to connect), and a page that renders but does not update, with
`Content-Security-Policy` errors in the browser console, means a proxy or a
browser extension injected script into it — the policy did its job.

## Development stack

The development configuration — source mounted, Mix present, debug pages,
origin checks off, the database port published for local tooling — lives in
`docker-compose.dev.yml` and is never the documented deployment:

```bash
docker compose -f docker-compose.dev.yml up --build
```

## Backup and restore

The whole instance is one PostgreSQL database, so a backup is one `pg_dump`
file. It holds **all** of the instance's data: securities, quotes and exchange
rates, portfolios, depots and cash accounts, every transaction, the
classifications with their assignments, the target plans with their category
and position targets and the cash targets, the policy rules, the research log
and events, tax records, and the audit journal. It does **not** hold `.env` —
keep a copy of that file somewhere safe as well: without `POSTGRES_PASSWORD`
and the tokens a restored database is still intact, but the instance has to be
configured anew.

The commands below run from the directory that holds `docker-compose.yml` and
`.env`. No PostgreSQL tools on the host are needed: they run inside the `db`
container.

### Take a backup

Before the backup, note three figures the restore will be checked against
(see "Check the restore" below). Then:

```bash
docker compose exec -T db \
  pg_dump -U portfolixir -d portfolixir_prod --format=custom \
  > portfolixir-$(date +%F).dump
```

The instance keeps running while the dump is taken; the file is a consistent
snapshot of one moment. To see that the file is readable, list its contents:

```bash
docker compose exec -T db pg_restore --list < portfolixir-2026-09-23.dump | head
```

Take a backup before every upgrade: migrations are additive, and a rollback
across a release restores the backup taken before it.

### Restore

A restore replaces the database with the backup. The application migrates the
database when it starts, so it is stopped first and started only once the
restore is complete — on a new host, start only the database for the same
reason:

```bash
# 1. The database only (on a new host: `docker compose up -d db`).
docker compose stop app mcp

# 2. An empty database under the same name.
docker compose exec -T db dropdb -U portfolixir --if-exists portfolixir_prod
docker compose exec -T db createdb -U portfolixir portfolixir_prod

# 3. The backup.
docker compose exec -T db \
  pg_restore -U portfolixir -d portfolixir_prod --no-owner --exit-on-error \
  < portfolixir-2026-09-23.dump

# 4. The instance, which migrates the restored database forward if the
#    backup came from an older release.
docker compose up -d
```

`--exit-on-error` stops at the first problem rather than leaving a half-filled
database behind. A backup restores into the same or a newer PostgreSQL major
version; the `db` image in `docker-compose.yml` is the one to use.

### Check the restore

Compare three figures before the backup and after the restore: the total value,
the number of holdings, and one position you know. On the Wealth page they are
the total at the top, the rows of the Positions table and any one row of it.
Over the API (the token is `PORTFOLIXIR_API_TOKEN` from `.env`; `1` is the
portfolio id the first call lists):

```bash
TOKEN=$(grep '^PORTFOLIXIR_API_TOKEN=' .env | cut -d= -f2-)
API=http://127.0.0.1:4000/api/v1

curl -s -H "Authorization: Bearer $TOKEN" $API/portfolios
curl -s -H "Authorization: Bearer $TOKEN" $API/portfolios/1/valuation   # "total_value"
curl -s -H "Authorization: Bearer $TOKEN" $API/portfolios/1/holdings    # one entry per holding
```

The figures are full-precision decimal strings, so a restore that lost nothing
shows them character for character the same. The procedure was run end to end
on 2026-09-23 against the synthetic review dataset with the shipped
`docker-compose.yml`: backup, a new database volume, restore, and the three
figures, the audit journal's row count and the policy rules compared equal.

## Reset

If the local database should be reset, remove the Compose volume:

```bash
docker compose down -v
docker compose up --build
```

## Upgrade

Take a database backup before an upgrade (see "Backup and restore" above):
migrations are additive, and a rollback across a release restores that backup.

After pulling a new version of the repository, fetch the images, rebuild and
start:

```bash
docker compose pull db
docker compose build --pull
docker compose up -d
```

The application's Erlang/OTP and Debian base images are pinned by digest in
the repository, so a runtime fix in them arrives with the new version itself.
The database image and the MCP companion's Node base are named by tag: a
plain `docker compose up --build` reuses the copies already on the host, so
`docker compose pull db` and `--pull` are what bring their fixes. The release
notes say when an upgrade carries such a fix.

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
