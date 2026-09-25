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
on the host's loopback interface only and never publishes the database. Inside
their containers both listen on every interface, so in Compose the port
mappings, not the application, keep them on the host's loopback ("Reach"
below).

## Prerequisites

- Docker Engine 28.3.3 or newer, with Docker Compose. From 28.0 the engine
  stops other machines on the network from reaching a port published on
  `127.0.0.1` directly, and 28.3.3 closes the case in which a firewall reload
  reopened that path (CVE-2025-54388). On an older engine the loopback port
  mappings do not keep the instance on this machine;
- a checkout of this repository;
- a `.env` file with the secrets (see below);
- no real portfolio, bank, broker, wallet, or statement data in fixtures.

## Secrets and settings

Create `.env` from `.env.example`, readable by you only, and keep it that way:

```bash
install -m 600 .env.example .env
```

The stack refuses to start while a secret is missing, the application and the
MCP companion refuse to start with a token shorter than 32 bytes or equal to a
placeholder, and the application refuses a `SECRET_KEY_BASE` shorter than 64
bytes, equal to a placeholder, or equal to a value committed in this
repository. Generate each token and `SECRET_KEY_BASE`
with `openssl rand -base64 48`, and `POSTGRES_PASSWORD` with
`openssl rand -hex 32`:
the Compose file splices it into the database URL, where a `/` or `#` from
base64 would break the connection string.

| Variable | Required | What it does |
|---|---|---|
| `SECRET_KEY_BASE` | yes | Signs the session cookie; the signing salts are derived from it. |
| `POSTGRES_PASSWORD` | yes | The database password; the app builds its connection string from it. |
| `PORTFOLIXIR_API_TOKEN` | yes | The bearer token of the JSON API and of the MCP companion's upstream calls. |
| `PORTFOLIXIR_MCP_TOKEN` | yes | The bearer token an MCP client presents to the companion. |
| `PORTFOLIXIR_UI_PASSWORD` | no | Set it to require a login on the web UI (ADR-0045). Unset, the UI is open — acceptable only behind reverse-proxy authentication. Changing it ends every login made with the old password. |
| `PORTFOLIXIR_SESSION_DAYS` | no | How many days a UI login stays valid (default 30). The window slides: using the instance renews it, so you are asked again only after a full period of not using it. `0` turns the server-side expiry off: the browser forgets the login when it closes, but a copy of the session cookie never expires, so prefer a number of days. A logout clears the login in that browser only, and a copy of the session cookie taken earlier stays valid; to end every login, change `PORTFOLIXIR_UI_PASSWORD` or rotate `SECRET_KEY_BASE`. |
| `PHX_HOST` | no | The name the reverse proxy serves (default `localhost`). Requests under any other `Host` are refused with 421. |
| `PORTFOLIXIR_ALLOWED_HOSTS` | no | Further names, comma-separated (a LAN address, a second proxy name). The Compose file adds `app`, the name the MCP companion reaches the application under. |
| `PHX_FORCE_SSL` | no | `true` redirects plain HTTP to HTTPS and sets HSTS. Set it once the reverse proxy terminates TLS and sends `X-Forwarded-Proto` from loopback or from an address named in `PORTFOLIXIR_TRUSTED_PROXIES`; off by default, because a loopback instance has no TLS to redirect to and the application never terminates TLS itself. |
| `PORTFOLIXIR_TRUSTED_PROXIES` | no | Addresses or CIDR blocks, comma-separated, whose `X-Forwarded-For` (the login and token throttle's source) and `X-Forwarded-Proto` (the scheme) the application believes. Empty, the throttle counts the connecting address, which behind a proxy is the proxy, and only a proxy on loopback can mark a request as HTTPS. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | no | Further `Host` names the MCP companion answers under (a proxy name), comma-separated. |
| `TZ` | no | The zone that decides what "today" is, as a tz name (`Europe/Berlin`); empty is UTC. Every date check — a statement or a quote not in the future, a rule version not backdated — reads the application's calendar day in this zone, and each database session takes the same zone when it connects, so the database's own date checks agree with it; the database server's `timezone` setting then does not matter. A value the database does not know as a zone name is logged once at startup and the session keeps the server's zone. |
| `PORTFOLIXIR_LOGO_DIR` | no | The absolute directory stored logos are kept in. The release image sets it to `/var/lib/portfolixir/logos`, the `portfolixir-logos` volume, because the release itself is read-only for the user it runs as; leave it alone in Compose. |

Without a UI password and with the port opened beyond loopback, the
application logs a warning at startup naming this table; with a UI password
shorter than 12 characters it warns as well, and starts either way.

### Reach

A release started on its own listens on loopback unless `PHX_BIND_ALL` says
otherwise. In the Compose deployment the application listens on every
interface inside its container, because a port mapping forwards to the
container's network interface, never to its loopback, and the port mapping,
not the application, keeps it on the host's loopback. What reaches it there is
this host, through the loopback mapping and through the container's own
address, and the other containers of the stack; nothing else on the network,
on Docker Engine 28.3.3 or newer. The application cannot tell this apart from
a port opened to the network, so without a UI password the startup warning
appears in every Compose install. Set
`PORTFOLIXIR_UI_PASSWORD` for a Compose install: it also locks the web UI
against the other containers and against whatever else runs on this host.

Outbound, the application fetches logos and follows provider redirects only to
public addresses (`SECURITY.md`). On an IPv6-only host behind DNS64, use the
well-known NAT64 prefix `64:ff9b::/96`: an address in it is judged by the IPv4
address it carries. The local-use translation prefix `64:ff9b:1::/48` is a
special-purpose block like the private ranges, so every address a DNS64 builds
in it is refused, and logo downloads and redirected provider requests fail.

## Database roles (recommended for a new install)

As shipped, the application connects as the database's bootstrap superuser, the
role the `db` image creates from `POSTGRES_USER`, which also owns every table.
The append-only and audit-journal triggers then bind the application's code,
not its credential: a superuser or a table's owner can switch a trigger off or
drop it. The recommended setup gives the database three roles, each with one
job:

- the bootstrap superuser, for administration only: backups, restores and the
  grants below;
- `portfolixir_owner`, not a superuser, which owns the tables and runs the
  migrations;
- `portfolixir_app`, which the application connects as: it reads and writes
  rows, owns nothing and holds no `TRUNCATE`, so it can neither change a table
  nor switch off or drop a trigger.

This is for a new install, before its first start. Moving an existing instance
onto these roles is a migration of that instance and is not described here.

1. Add two passwords to `.env`, each from `openssl rand -hex 32`:
   `PORTFOLIXIR_OWNER_DB_PASSWORD` and `PORTFOLIXIR_APP_DB_PASSWORD`.
2. Start the database alone and create the roles. The passwords reach `psql` on
   its standard input, never on a command line:

   ```bash
   docker compose up -d db
   OWNER_PW=$(grep '^PORTFOLIXIR_OWNER_DB_PASSWORD=' .env | cut -d= -f2-)
   APP_PW=$(grep '^PORTFOLIXIR_APP_DB_PASSWORD=' .env | cut -d= -f2-)
   docker compose exec -T db psql -v ON_ERROR_STOP=1 -U portfolixir -d portfolixir_prod <<SQL
   CREATE ROLE portfolixir_owner LOGIN PASSWORD '$OWNER_PW';
   CREATE ROLE portfolixir_app LOGIN PASSWORD '$APP_PW';
   ALTER DATABASE portfolixir_prod OWNER TO portfolixir_owner;
   REVOKE ALL ON DATABASE portfolixir_prod FROM PUBLIC;
   GRANT CONNECT ON DATABASE portfolixir_prod TO portfolixir_app;
   REVOKE CREATE ON SCHEMA public FROM PUBLIC;
   GRANT USAGE ON SCHEMA public TO portfolixir_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE portfolixir_owner IN SCHEMA public
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO portfolixir_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE portfolixir_owner IN SCHEMA public
     GRANT USAGE, SELECT ON SEQUENCES TO portfolixir_app;
   SQL
   ```

   The two default-privilege lines reach every table a migration adds, now or
   later: each is granted to the runtime role as the owner creates it, and
   `TRUNCATE` never is.
3. Create `docker-compose.override.yml` beside `docker-compose.yml`; Compose
   reads it with every command. It connects the application as the runtime
   role, starts the release without the migration step, which the runtime role
   cannot run, and adds a one-off `migrate` service that runs the migrations as
   the owner:

   ```yaml
   services:
     app:
       entrypoint: ["/opt/app/bin/portfolixir"]
       command: ["start"]
       environment:
         DATABASE_URL: postgres://portfolixir_app:${PORTFOLIXIR_APP_DB_PASSWORD:?set it in .env}@db:5432/portfolixir_prod

     migrate:
       build:
         context: .
         dockerfile: Dockerfile.release
       profiles: ["migrate"]
       depends_on:
         db:
           condition: service_healthy
       entrypoint: ["/opt/app/bin/portfolixir", "eval", "Portfolixir.Release.migrate()"]
       environment:
         DATABASE_URL: postgres://portfolixir_owner:${PORTFOLIXIR_OWNER_DB_PASSWORD:?set it in .env}@db:5432/portfolixir_prod
         SECRET_KEY_BASE: ${SECRET_KEY_BASE:?set SECRET_KEY_BASE in .env}
         PORTFOLIXIR_API_TOKEN: ${PORTFOLIXIR_API_TOKEN:?set PORTFOLIXIR_API_TOKEN in .env}
         PHX_HOST: ${PHX_HOST:-localhost}
   ```

4. Migrate as the owner, then start:

   ```bash
   docker compose run --rm --build migrate
   docker compose up --build -d
   ```

With these roles, two procedures below change. An upgrade runs
`docker compose run --rm --build migrate` after the build and before
`docker compose up -d`, because the application no longer migrates on start. A
restore gives the new database back to the owner after its step 2, restores as
the owner in step 3 by adding `--role=portfolixir_owner` to `pg_restore`, so
the tables keep their owner and their grants, and migrates as in the upgrade
before step 4:

```bash
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U portfolixir -d portfolixir_prod <<'SQL'
ALTER DATABASE portfolixir_prod OWNER TO portfolixir_owner;
REVOKE ALL ON DATABASE portfolixir_prod FROM PUBLIC;
GRANT CONNECT ON DATABASE portfolixir_prod TO portfolixir_app;
SQL
```

The recipe was checked with PostgreSQL's own tools and the release outside
Compose: the runtime role writes journaled records and is refused `TRUNCATE`,
switching a trigger off, dropping one and creating a table; a backup restored
as the owner keeps every trigger and grant.

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

The application is reachable on the host's loopback; a reverse proxy on the
same host (Caddy, nginx, Traefik) terminates TLS and forwards to
`127.0.0.1:4000`. It passes the
original `Host` header through (set `PHX_HOST` to that name) and sets the two
forwarding headers itself: it sets `X-Forwarded-Proto` to the scheme the
browser used, which is what marks the session cookie `Secure` and what
`PHX_FORCE_SSL` reads, and it appends the connecting address to
`X-Forwarded-For` or overwrites it with that address. It never passes a value
the client sent through: a forwarding header that reaches the application as
the client wrote it lets the client choose the throttle's source.

Name the exact address the proxy connects from in
`PORTFOLIXIR_TRUSTED_PROXIES`. Through the published port that is the Docker
bridge gateway, which `docker network inspect` shows, for example
`PORTFOLIXIR_TRUSTED_PROXIES=172.18.0.1`. Docker picks that address when it
creates the stack's network, so check it again whenever the stack's network is
recreated, after a `docker compose down` for instance: an address that no
longer matches is as good as none. Name the one address rather than a
private block: every address inside a named block is believed, so a block also
trusts whatever else shares that network. With the address named, the throttle
counts the client behind the proxy rather than the proxy: without it, ten
wrong passwords from anyone the proxy admits lock the login for everyone behind
it, the operator included. The same setting decides whose `X-Forwarded-Proto` is
believed: loopback and the named addresses only, so a proxy reaching the
container through the Docker bridge must be named there for the cookie to be
`Secure` and for `PHX_FORCE_SSL` to see HTTPS. Failed logins are also counted
across all sources together over a rolling window, so guesses spread over many
addresses cannot multiply; past that ceiling the login asks everyone to wait,
the operator included, while sessions already logged in keep working.
Restarting the application clears the counts, the ceiling's included, because
they are kept in memory only: `docker compose restart app` gives the login
back at once. Changing `PORTFOLIXIR_UI_PASSWORD` in `.env` and running
`docker compose up -d` recreates the container, which clears them too.
Reverse-proxy authentication and the built-in UI password compose: keep
either, or both.

### The TLS contract

TLS is the proxy's job, in full. The application never terminates TLS and
never redirects to HTTPS on its own, because its safe default is a loopback
instance that has no certificate; what it offers is the opt-in. The contract,
in four lines:

1. The proxy terminates TLS and forwards plain HTTP to `127.0.0.1:4000`.
2. It passes `Host` through, sets `X-Forwarded-Proto` itself, and appends the
   connecting address to `X-Forwarded-For` or overwrites it; it never passes a
   value the client sent through. It also forwards WebSocket upgrades on
   `/live/websocket` — the live pages run over that socket. Caddy's
   `reverse_proxy` does all of this by default. nginx needs:

   ```nginx
   proxy_http_version 1.1;
   proxy_set_header Host $host;
   proxy_set_header X-Forwarded-Proto $scheme;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   ```

   HAProxy needs the lines below, with `option forwardfor` written without
   `if-none`, which would keep a header the client sent:

   ```text
   option forwardfor
   http-request set-header X-Forwarded-Proto https if { ssl_fc }
   http-request set-header X-Forwarded-Proto http if !{ ssl_fc }
   ```

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

It runs on public development secrets — the database password `postgres` and
the `SECRET_KEY_BASE` committed in `config/dev.exs` — so both of its ports, the
application's and the database's, are published on the host's loopback only,
and it holds synthetic data only.

### Moving off the development stack

Before the production release (Sprint 10, #760), the documented deployment was
this development stack, then named `docker-compose.yml`, with its ports open on
every interface. An instance still running that way moves to the production
stack by a backup and a restore, not in place: the production database is set
up only on an empty volume, and the old volume keeps the development user. From
the checkout, after pulling the current version:

```bash
# 1. A backup of the development database, while it still runs.
umask 077
mkdir -p ~/portfolixir-backups
docker compose -f docker-compose.dev.yml exec -T db \
  pg_dump -U postgres -d portfolixir_dev --format=custom \
  > ~/portfolixir-backups/portfolixir-dev.dump

# 2. The file lists its contents; only then remove the development stack and
#    its volumes, which leaves the backup as the only copy.
docker compose -f docker-compose.dev.yml exec -T db \
  pg_restore --list < ~/portfolixir-backups/portfolixir-dev.dump | head
docker compose -f docker-compose.dev.yml down -v

# 3. The production database, on a new volume.
docker compose up -d db
```

Then restore that file from step 3 of "Restore" below, and check the restore.

## Backup and restore

The whole instance is one PostgreSQL database, so a backup is one `pg_dump`
file. It holds **all** of the instance's data: securities, quotes and exchange
rates, portfolios, depots and cash accounts, every transaction, the
classifications with their assignments, the target plans with their category
and position targets and the cash targets, the policy rules, the research log
and events, tax records, and the audit journal. It does **not** hold `.env` —
keep a copy of that file somewhere safe as well: without `POSTGRES_PASSWORD`
and the tokens a restored database is still intact, but the instance has to be
configured anew. Nor does it hold the stored logos: they are files in the
`portfolixir-logos` volume, outside both the database and the release, and a
logo uploaded or chosen by hand exists only there, so the volume is backed up
beside the dump.

The commands below run from the directory that holds `docker-compose.yml` and
`.env`. No PostgreSQL tools on the host are needed: they run inside the `db`
container. They write the backups into `~/portfolixir-backups`, outside the
checkout, under `umask 077`, so that only you can read them: a dump holds all
of the instance's data. `umask 077` holds for the rest of that shell session.
A copy that leaves this machine, on a disk or in a cloud folder: encrypt it
first, for example with `age -p` or `gpg --symmetric`.

### Take a backup

Before the backup, note the three figures and the trigger count the restore
will be checked against (see "Check the restore" below). Then:

```bash
umask 077
mkdir -p ~/portfolixir-backups
docker compose exec -T db \
  pg_dump -U portfolixir -d portfolixir_prod --format=custom \
  > ~/portfolixir-backups/portfolixir-$(date +%F).dump
```

The instance keeps running while the dump is taken; the file is a consistent
snapshot of one moment. To see that the file is readable, list its contents:

```bash
docker compose exec -T db \
  pg_restore --list < ~/portfolixir-backups/portfolixir-2026-09-23.dump | head
```

The stored logos, from the running application container:

```bash
docker compose exec -T app tar -C /var/lib/portfolixir/logos -cf - . \
  > ~/portfolixir-backups/portfolixir-logos-$(date +%F).tar
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

# 3. The backup, in one transaction: all of it or nothing.
docker compose exec -T db \
  pg_restore -U portfolixir -d portfolixir_prod --no-owner --exit-on-error \
  --single-transaction < ~/portfolixir-backups/portfolixir-2026-09-23.dump \
  && echo "restore complete"

# 4. Only if step 3 ended without an error ("restore complete"): the
#    instance, which migrates the restored database forward if the backup
#    came from an older release.
docker compose up -d

# 5. The stored logos, into the running application container.
docker compose exec -T app tar -C /var/lib/portfolixir/logos -xf - \
  < ~/portfolixir-backups/portfolixir-logos-2026-09-23.tar
```

`--single-transaction` makes the restore all or nothing: at the first error
(`--exit-on-error`) everything it did is rolled back, and the database is left
empty rather than half filled — a half-filled one can lack the append-only and
audit-journal triggers that guard the records, which are restored with the
tables. Start the instance only after a restore that ended without an error:
on an empty database it would run the migrations and start without data. Find
the cause and repeat from step 2. A backup restores into the same or a newer
PostgreSQL major version; the `db` image in `docker-compose.yml` is the one to
use.

### Check the restore

Compare three figures before the backup and after the restore: the total value,
the number of holdings, and one position you know. On the Wealth page they are
the total at the top, the rows of the Positions table and any one row of it.
Compare, too, the number of the database's triggers, the append-only and
audit-journal guards among them; a restore that lost none shows the same
number:

```bash
docker compose exec -T db psql -U portfolixir -d portfolixir_prod -tAc \
  "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal"
```

Over the API (the token is `PORTFOLIXIR_API_TOKEN` from `.env`; `1` is the
portfolio id the first call lists):

```bash
TOKEN=$(grep '^PORTFOLIXIR_API_TOKEN=' .env | cut -d= -f2-)
API=http://127.0.0.1:4000/api/v1
# The token reaches curl on its standard input, never on its command line,
# where every local user could read it in the process list.
api() { printf 'Authorization: Bearer %s\n' "$TOKEN" | curl -s -H @- "$API$1"; }

api /portfolios
api /portfolios/1/valuation   # "total_value"
api /portfolios/1/holdings    # one entry per holding
```

The figures are full-precision decimal strings, so a restore that lost nothing
shows them character for character the same. The procedure was run end to end
on 2026-09-23 against the synthetic review dataset with the shipped
`docker-compose.yml`: backup, a new database volume, restore, and the three
figures, the audit journal's row count and the policy rules compared equal.
The single transaction and the trigger count came later (2026-09-24) and were
checked with the same PostgreSQL tools outside Compose, on a restore that
succeeds and on one that is refused.

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

Every image the stack runs on is pinned by tag and digest in the repository —
the application's Erlang/OTP and Debian base images, the MCP companion's Node
base and the database image — so a fix in one of them arrives with the version
that moves its digest, and the release notes say when an upgrade carries one.
`docker compose pull db` and `--pull` fetch exactly the images the new version
names.

Upgrading from 0.15.x or earlier, four changes of the security pass reach an
instance that already runs. Check them before the `up`:

- **The proxy's address.** `X-Forwarded-Proto` is now believed only from
  loopback and from the addresses named in `PORTFOLIXIR_TRUSTED_PROXIES`. A
  reverse proxy that reaches the container through the Docker bridge, as every
  proxy does through the published port, is neither until it is named. Without
  it, `PHX_FORCE_SSL=true` redirects every request in a loop, and without
  `PHX_FORCE_SSL` the session cookie silently loses `Secure`. Name the bridge
  gateway before upgrading ("Reverse proxy" above).
- **One login.** A session is now bound to the UI password, and a session
  issued by an earlier release carries no binding, so every browser logs in
  once after the upgrade.
- **The MCP token's floor.** The companion now refuses a
  `PORTFOLIXIR_MCP_TOKEN` shorter than 32 bytes or equal to a placeholder, as
  the application already refused such an API token, and stops with the
  variable's name.
- **The secret key's floor.** The application refuses a `SECRET_KEY_BASE`
  shorter than 64 bytes, equal to a placeholder or equal to a value committed
  in this repository, and stops with the variable's name. A new
  `SECRET_KEY_BASE` ends every session.

Replace a refused value with the output of `openssl rand -base64 48`, as
"Secrets and settings" above describes.

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
  (`PORTFOLIXIR_UI_PASSWORD`). A release started on its own binds loopback;
  in Compose the port mapping keeps it on the host's loopback ("Reach" above).
  Either way it refuses foreign `Host` names (ADR-0045).
- The MCP companion wraps the local JSON API and does not access the database
  directly.
- The release logs at `info`: the request lines, each live page's socket
  connect with its CSRF token filtered out, warnings and errors. The database
  queries, the parameters of each request and page event, and the session
  contents that the `debug` level writes stay out of the log.
- Every request and every open page runs in its own process under a heap
  cap of 512 MiB, counting the large binaries it holds: a request that grows
  past it fails alone, logged, instead of exhausting the machine's memory.
  No ordinary read or write comes near it; `max_heap_bytes` under
  `PortfolixirWeb.HeapCap` in `config/config.exs` changes it. The in-memory
  cache of derived figures keeps to its own budget (5000 entries, 128 MiB).
- The release starts without Erlang distribution, so it opens no listener
  towards the other containers: `bin/portfolixir eval` works inside the
  container, `remote` and `rpc` do not.
- This setup does not configure broker sync, bank sync, document intake (beyond
  the Portfolio Performance CSV/JSON import), trading, payments, orders,
  rebalancing, or LLM features.
- Public docs are published with GitHub Pages at `portfolixir.app`.
