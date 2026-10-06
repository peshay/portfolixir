# Version Report — 2026-10-06 (Sprint 19 maintenance lane, PR α)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before PR α's closing act
(the Sprint 19 plan's Lane M and D-11). The lane reports what it deliberately
did not update and why. A row whose reasoning has not changed since the last
report carries that reasoning again rather than a cross-reference, so this
report reads on its own. Commits are named by subject, because the branch's
history is cleaned before the merge and hashes change.

## Applied this lane

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `proxy-addr` (mcp-server, under `express`) | 2.0.7 → 2.0.8 | "chore(deps): proxy-addr 2.0.8 for GHSA-jqcg-44mw-7w3h" | Taken on the branch before the lane ran, because the companion's `npm audit` gate turned red with nobody pushing. A critical advisory published on 2026-10-05 covers proxy-addr 1.1.0 to 2.0.7 (IP spoofing through an IPv4-mapped IPv6 trust subnet), and `express` 5.2.1 pulls it in. `npm audit fix --package-lock-only` moved only that transitive entry; `package.json` is unchanged. |
| `finch` (under `req`) | 0.23.0 → 0.24.0 | "chore(deps): finch 0.23.0 -> 0.24.0" | Finch is the pool under Req, so every outbound provider call runs through it. 0.24.0 (2026-09-29) closes an HTTP/1 connection after a request or response error before the connection goes back to the pool. Under Mint 1.11 a stale response from a receive timeout therefore no longer reaches the next request. "fix(net): a request after a receive timeout gets a connection nobody has used" works around that same interaction with a zero idle time. The workaround stays, and `http_pool_test` still pins the behaviour through the real transport. 0.24.0 also closes a discarded HTTP/1 connection in its own process, so a slow TLS shutdown no longer holds up the pool's checkouts. The zero-idle pool discards the used connection at every checkout that finds one, so the app gains from that too. The rest is the HTTP `QUERY` method, pool types and HTTP/2 pool fixes, none of which the app uses. Lock-only, inside req's `~> 0.21`; Finch's own requirements are unchanged. |
| `@modelcontextprotocol/sdk` (mcp-server) | 1.32.0 → 1.32.1 | "chore(deps): @modelcontextprotocol/sdk 1.32.0 -> 1.32.1 in mcp-server" | Published 2026-10-05, after Dependabot's weekly run. Read from the package diff: only `package.json`'s version and the README change, so nothing changes for the companion. The README is the news. It names v1.x the maintenance line and v2 the current stable release (see "Deliberately not updated"). Lock-only, inside `^1.13.0`. |
| `req` | 0.7.4 → 0.7.5 | "chore(deps): req 0.7.4 -> 0.7.5" | Published 2026-10-06. Two fixes. AWS SigV4 signing on retries is not used here. A 303 redirect now turns any method except `HEAD` into `GET`. `Portfolixir.Net.Http` switches Req's own redirect following off and follows each hop itself, with `GET` only, so neither change reaches the app. Lock-only, inside `~> 0.5`. |

Every row is its own commit, never mixed into a feature story (ADR-0036
clause 1).

## Dependabot

One Dependabot PR was open at lane time:

- **#977, `node` 24.21.0 → 26.10.0 in `/mcp-server`:** declined again, as D-11
  rules for a lane that runs before the LTS date. Node 26 becomes LTS on
  **2026-10-28**, after this sprint's window. The next sprint that runs on or
  after that date takes it: the runtime moves in all four pinned places in one
  commit, together with the `@types/node` major that follows it.

Dependabot's weekly run of 2026-10-05 opened nothing else. The SDK's 1.32.1
and req 0.7.5 were published after it, and Finch is a transitive dependency,
which Dependabot's version updates do not cover. No Dependabot PR remains that
is neither taken nor a recorded decline.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm and the repository's tags: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 and ecto_sql 3.14.0 are still the newest releases, and both are already in the lock. The newest Elixir is still 1.20.4, on builds.hex.pm and in the language's tags; no 1.21 exists. | **No** |
| **Node 26 LTS promotion (#728's pin)** | nodejs.org release index: 26.10.0 is still **Current** (`lts: false`). The Node release schedule still dates 26's LTS to **2026-10-28**. 24.21.0 is still the newest Active LTS (Krypton), and it is what the image runs. | **No.** Line 24 moves to Maintenance LTS on 2026-10-20 and keeps security releases until 2028-04-30, so nothing forces the move before the 28th. |
| **A BMAD release since 6.12.0** | `git ls-remote --tags` on the method repository: **v6.12.1** is tagged, and npm's `bmad-method` `latest` is 6.12.1, published 2026-10-04 | **Yes.** It is a patch release, declined inside this batch by the between-batches rule (see the BMAD core row below). |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP minors and majors (#727) | Elixir 1.18.5 / OTP 27.3.4.18 | Both halves are still blocked upstream (see the triggers above). The move stays on its own branch and PR, because it moves the CI version pins, the Dockerfile base images and the Dialyzer PLT cache key together. CI also compiles with `--warnings-as-errors`, so two Elixir minors of deprecations are a body of work, not a version-string edit. The OTP patch pin has nothing to move: 27.3.4.18 is still the newest OTP 27 tag. |
| The images' Debian date | `bookworm-20260918` in all three `FROM` lines (latest `bookworm-20261005`) | New this lane. The Hex team's `1.18.5-erlang-27.3.4.18-debian-bookworm-20261005` tags and `debian:bookworm-20261005-slim` were pushed on 2026-10-06, the day of the lane. Dependabot never proposes this move (`dependabot.yml` ignores `hexpm/elixir` and `debian` on purpose), so the lane reads it. What was verified: the new `-slim` build image still carries OTP **27.3.4.18** and Elixir 1.18.5. Between the two `debian` slim images, exactly two packages differ: `libpcre2-8-0` moves from 10.42-1+deb12u1 to +deb12u2, and `tzdata` from 2026b to 2026c. The runtime stage's own packages (`openssl`, `libstdc++6`, `ca-certificates` and the rest) come from the archive at build time, whatever the base date. What could not be verified is a release build on the new images. CI does not build the release image, so `ci_test`'s text parity is the only gate on these lines, and it says nothing about whether the image builds and boots. A local build cannot run in this session: its `apt-get` steps cannot reach the Debian archive (HTTP 403 direct, 405 through the session's egress proxy). The Debian changelog and security tracker are outside the lane's network policy too, so whether +deb12u2 is a security fix was not read. An image move without a release build is not a lane bump. PR β's B2 changes the same Dockerfiles' `apt` steps and gives a host that cannot reach the Debian mirrors a documented route, which is what a build in a session like this one lacks. The move is the next lane's candidate, read again then: three `FROM` lines with new digests, with the build stage's and the runtime stage's dates moving together, as `ci_test`'s parity requires. |
| Node runtime major | 24 (`node:24.21.0-alpine3.24`, by digest) | Node 26 is **Current**, not LTS, until **2026-10-28**. An invariant test (#728) pins the runtime in four places, and the companion pins an LTS line. Dependabot's #977 is declined for the same reason. |
| `@types/node` major (mcp-server) | 24.19.1 (26.6.4 latest) | The major follows the pinned Node 24 runtime (Sprint 8 decision). The Dependabot ignore covers the whole major. |
| MCP SDK v2 (mcp-server) | `@modelcontextprotocol/sdk` 1.32.1 (v2: `@modelcontextprotocol/server` 2.3.1) | New this lane. The SDK's 1.32.1 README names v1.x the maintenance line, implementing the MCP spec up to 2025-11-25. v2 implements the 2026-07-28 spec and ships as separate packages, `@modelcontextprotocol/server` and `@modelcontextprotocol/client`, with a migration guide. v1.x receives bug and security fixes for at least six months after v2's release on 2026-07-27, so until 2027-01-27 at the earliest. Moving the companion is a package migration, not a version bump. Whatever it changes in the tool schemas is measured against a schema budget with zero headroom (D-10). So it is its own decision, and the date above is what bounds it. The lane did not read the migration guide. No issue tracks it yet. |
| Dockerfile `HEX_VERSION` | 2.4.2 (local Hex 2.5.1) | The image pin reproduces the image. The advisory gates run in CI against the current Hex, so nothing in this batch sits behind the pin. |
| PostgreSQL major | 18 (`18.6`, by digest) | 18.6 is still the newest 18 patch on Docker Hub. 19 exists only as a beta (`19beta4`), and a beta is not a candidate for a self-hosted instance's data directory. The postgresql.org version feed is outside the lane's network policy, so Docker Hub's tags are the source. |
| BMAD core and method (`bmad-method`) | 6.12.0 (latest 6.12.1, 2026-10-04) | The trigger fired. 6.12.1 is a patch release with four fixes. 23 bmm skills load config through one merged resolver, so overrides in `_bmad/custom/config.toml` and `config.user.toml` apply everywhere. `config.toml` carries defaults for the user-scope keys, so `bmad-build` renders on a fresh clone without `config.user.toml`, once the installer is run again. `bmad-create-epics-and-stories` keeps `status: draft` until every check passes. Party mode's collision check sees aliases. It is declined inside the batch by the between-batches rule: re-pinning runs the installer, which rewrites `_bmad/` and the workflows this batch's closing act is about to run under. A batch is never reviewed under a process that changed halfway. The re-pin is a candidate for **the first commit of the Sprint 20 branch**, before any lane starts, as Sprint 16 took 6.12.0. That commit also asks whether "fix(bmad): seed the gitignored BMAD user config in web sessions" is still needed, because 6.12.1's `config.toml` defaults address the same missing-config halt upstream. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2) | A **major** behind. The between-batches rule applies, plus a read of the major's changes, so it is its own decision. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | Still the head of `main`. Tag v1.15.0 sits on `acafaed`, not on `main`'s head. BMAD 6.12.0's registry marks the module **deprecated in favour of `bmad-loop`**. Recorded, not acted on: replacing or re-pinning the automator changes how stories are run, which is a process decision for the owner, not a version bump. |
| BMAD `tea`, `cis` | v1.27.2, v0.3.2 (pinned) | Both are still the newest tags, so there is nothing to take. |

## The OTP inside the release's build image

| Row | Value |
| --- | --- |
| Build image (`Dockerfile.release`, stage `build`) | `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918-slim@sha256:ada1bbb1…` |
| `OTP_VERSION` read from inside that image | **27.3.4.18** |
| CI's `otp-version` pin | 27.3.4.18 |

They agree, so every instance built from this tree runs the OTP that CI tests.
The session had no Docker daemon when the script first ran, and the script said
so. A daemon started inside the session then pulled the image by its digest,
and the script's rerun read the file the release bundles.

## The picture at lane time

- **Toolchain pins (CI is authoritative):**
  - Elixir 1.18.5, OTP 27.3.4.18.
  - The development image and the release's build stage use
    `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918`; the build
    stage uses its `-slim` variant.
  - The runtime stage uses `debian:bookworm-20260918-slim`.
  - The database is `postgres:18.6-alpine3.24` in Compose and `postgres:18.6`
    in CI.
  - Node 24: `node:24.21.0-alpine3.24`, and `node-version: "24"` in CI.
  - Every image above is pinned by digest.
- **Hex:**
  - Every dependency is *Up-to-date*, direct and transitive
    (`mix hex.outdated --all`), now that req is at 0.7.5 and Finch at 0.24.0.
  - `mix hex.audit`: no retired packages, no advisories.
  - `mix deps.audit`: no vulnerabilities.
  - `mix deps.unlock --check-unused`: no unused entries.
- **npm (mcp-server):**
  - `npm audit`: 0 vulnerabilities at any level.
  - Outdated: only the `@types/node` major (above).
- **BMAD install:**
  - The manifest says 6.12.0; core and bmm are 6.12.0 (6.12.1 is out, above).
  - Pinned modules: tea v1.27.2 (`d99ad29`), cis v0.3.2 (`97298b2`), bmb
    v1.8.1 (`3410d95`).
  - automator tracks `main` (`0b94fd7`).

## Gate results on PR α's head

Run after PR α's closing act on the branch carrying every story, Lane M and
the closing act's review rounds, `d729bbe7`, before the history was cleaned
(the cleaned tree is byte-identical). Local toolchain: Elixir 1.18.5 / OTP
27.3.4.18, PostgreSQL 16, Node 24.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix gettext.extract --check-up-to-date` | up to date |
| `mix test` (and as `mix coveralls`) | 4147 tests, 9 properties, 0 failures |
| `mix test --only seeded_upgrade` | 25 tests, 0 failures |
| `mix coveralls` | 93.9 % total |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 |
| `mix dialyzer --format short` | 0 errors |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 189 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |
