# Version Report — 2026-11-25 (Sprint 32 maintenance lane)

Point-in-time dependency and toolchain picture, read with the sections of
`scripts/version-report.sh` (#676) **at lane time**, on `main` as the
Sprint 32 sprint branch starts from it (`dd10782`, the merged Sprint 32
plan), in the lane's own worktree (the Sprint 32 plan's Lane M, M1). The
lane reports what it deliberately did not update and why. A row whose
reasoning has not changed since the last report carries that reasoning
again, so this report reads on its own. Commits are named by subject,
because the branch's history is cleaned before the merge and hashes
change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `db_connection`, on `main` before the lane | 2.10.2 → **2.10.3** | "chore(deps): db_connection 2.10.3 (EEF-CVE-2026-133555)" | A new advisory (HIGH) against 2.10.2, published 2026-11-24, turned the advisories job red on `main` and on every branch cut from it. Only its lock line moved. Recorded here because it moved the lockfile after the last report. |
| OTP and the Debian date, in every pinned place, M1 | OTP 27.3.4.19 → **27.3.4.20**; `bookworm-20261104` → **`bookworm-20261123`** | "chore(toolchain): OTP 27.3.4.20 and Debian bookworm 20261123, in every pinned place (S32 M1)" | **The last report's trigger fired** ("an OTP 27 patch after 27.3.4.19, with its image"). OTP 27.3.4.20 (2026-11-24) is a security patch: nine CVEs, among them `binary_to_term` crashes on malformed input (CVE-2026-116293, CVE-2026-117642, CVE-2026-120961), the TLS client's EdDSA curve binding in TLS 1.3 CertificateVerify (OTP-20468), httpc header injection (CVE-2026-116295) and `xmerl_scan`'s external-DTD fetch (CVE-2026-119443, its one potential incompatibility; the app does not use `xmerl_scan`). The release bundles the build image's ERTS, so the image is what every instance runs. `hexpm/elixir` published `1.19.7-erlang-27.3.4.20-debian-bookworm-20261123` (`fc1a8383…`) and its `-slim` variant (`b38c9f54…`) the same day, and `debian:bookworm-20261123-slim` (`e67eeead…`, also confirmed through mirror.gcr.io) exists, so the three Debian dates stay equal as `ci_test` requires. One commit moves CI's `otp-version` in its six jobs and the Dialyzer PLT cache key, the development image, the release's build and runtime stages and the cloud session's toolchain script, with the OTP archive's sha256 from builds.hex.pm (`6402f6d5…`, recomputed from the download). Verified on 27.3.4.20 installed locally from builds.hex.pm (gate table). |
| `postgrex`, M1 | 0.22.4 → **0.23.0** | "chore(deps): postgrex 0.23.0 (S32 M1)" | **New this lane** (published 2026-11-22; no Dependabot PR yet). A minor of the database driver whose hardening reaches the app: the password and the SSL options are no longer kept in the connection state after connect; an authentication downgrade is refused when channel binding is required; type encoders enforce integer bounds, and a `timestamptz` outside the 64-bit wire format is rejected instead of sent; a connection that drops during a `handle_connect` query reconnects. Read from the package itself (`mix hex.package fetch`, its `CHANGELOG.md` and `lib/postgrex.ex`). **One behaviour change no gate reaches:** over TLS against a SCRAM server it now uses channel binding (SCRAM-SHA-256-PLUS) by default (`channel_binding: :prefer`). Neither the suite nor CI connects to the database over TLS; the TLS path is opt-in (`DATABASE_SSL`, K03), and a binding failure would stop the connection at boot, visibly, not change a stored record. Only its lock line moves (`mix deps.update postgrex`; it requires `db_connection ~> 2.9` and `decimal ~> 1.5 or ~> 2.0 or ~> 3.0`, both met by the lock); `mix.exs` keeps `>= 0.0.0`. The worktree's `deps` link was replaced by a copy of its own before the fetch (`scripts/worktree.sh own`, through the `deps.update` alias), so the main checkout's `deps` still hold 0.22.4. |

No other version moved in this lane: every candidate below is declined,
each with its reason. Every bump is its own commit, never mixed into a
risk-tier story's commits (ADR-0036 clause 1). The plan estimated one to
three commits for M1; the lane has three (two bumps and this report).

## Dependabot

Read from GitHub's pull requests at lane time (about 17:50 UTC; read
only, through the GitHub tool's pull-request listing; the lane comments
on and closes nothing). One Dependabot PR is open:

- **#1477**, `playwright` 1.65.0 → 1.65.1 in `/test/browser`, from
  2026-11-20. **Nothing to take:** `main` already pins 1.65.1 exactly in
  `test/browser/package.json` and its lockfile, taken by Sprint 31's M1
  ("chore(deps): playwright 1.65.1 in test/browser, pinned exactly (M1,
  #1477)"). Dependabot closes the PR itself on its next run against
  `main`; the lane takes nothing twice.

**#1476** (`bandit` 1.15.0) is no longer open: Sprint 31 took the
version, and `main`'s lockfile reads `bandit` 1.15.0.

No Dependabot PR had opened by lane time for `postgrex` 0.23.0,
`lazy_html` 0.1.15/0.1.16, `@types/node` 26.6.10 or PostgreSQL 19.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: **27.3.4.20** (2026-11-24); Docker Hub: `hexpm/elixir` 1.19.7 images on it from 2026-11-24 | **Yes.** Taken (above). |
| **A Debian bookworm date after 20261104, with its image** | Docker Hub: `debian:bookworm-20261123` and `-slim` (2026-11-24); `hexpm/elixir` 1.19.7 on 27.3.4.20 is published on that date | **Yes.** Taken with the OTP move (above). |
| **A BMAD release since 6.12.4** | npm: `bmad-method` dist-tags are `latest` 6.12.4, `next` 6.12.3-next.1, `rollback` 4.39.0; the method repository's newest tag is v6.12.4 (`git ls-remote`), and `main` is still `e435a22` | **No** |
| **An Elixir 1.19 patch after 1.19.7, with its image** | builds.hex.pm's Elixir build list: `v1.19.7-otp-27` (2026-10-29) is the newest 1.19 | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No**; 1.20.5 (2026-10-29) is still the newest 1.20, and no 1.21 build exists. |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7 of Sprint 24) | `mix hex.outdated --all`: `ecto` (3.14.3) and `ecto_sql` (3.14.0) up to date; no Elixir release since 1.19.7 / 1.20.5 | **No**. OTP 28.5.0.9 and 29.1.3 appeared on 2026-11-24 (security patches of those lines, alongside 27.3.4.20), but neither is the Ecto or Elixir release the trigger waits on, so the trigger's own test was not re-run. |
| **A Node 26 security release after the image's** | nodejs.org's release index: 26.13.1 (2026-11-10, `security: true`) is still the newest 26; Docker Hub's `26.13.1-alpine3.24` is still `6bd9ab43…`, the digest both stages pin | **No** |
| **A PostgreSQL 18 minor with security fixes** | Docker Hub: 18.7 is the newest 18 minor. Its `18.7-alpine3.24` tag now points at index `0115267a…` (pushed again 2026-11-21), but mirror.gcr.io serves that index and the pinned `ff64c9e3…` with the same amd64 (`68e33adb…`) and arm64 (`c69207a8…`) images: no new build reached the pinned platforms | **No** |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279, closed 2026-11-01) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. No release after 3.2.0; unchanged since. |
| `phoenix_live_view` | 1.2.14 (1.2.15, published 2026-11-21) | Its changelog: "the same code as 1.2.14, but it fixes the generated client type declarations missing in the previous version". Read from the package itself by the last lane (`mix hex.package fetch`): against 1.2.14 the release adds only `assets/js/types/*.d.ts` files. The app ships no TypeScript client and builds nothing from them, so the release changes nothing the app runs; no advisory names 1.2.14. Left for its Dependabot PR or the next fix. Unchanged since the last report. |
| `lazy_html` (test only) | 0.1.14 (0.1.16) | **New this lane.** 0.1.15 (2026-11-24) copies text and comment binaries in `to_tree/2` so a result does not keep the whole document in memory; 0.1.16 (published 2026-11-25 17:08 UTC, under an hour before the lane read it) fixes a crash in `query/2` and `filter/2` on an invalid CSS selector. A test-only HTML parser with a native extension; neither fix is a defect the suite has met (its selectors are valid, its documents small), and no advisory names 0.1.14. Left for its Dependabot PR once the series settles. |
| `websock_adapter`, `nimble_options`, `finch`, `nimble_pool` (transitive) | 0.6.0 (0.7.2), 1.1.1 (1.2.0), 0.24.0 (0.25.0), 1.1.0 (1.2.0) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. Unchanged since the last report. |
| `@types/node` (mcp-server, dev only) | 26.6.6 (26.6.10) | **New this lane.** Four patches in about twelve hours (26.6.7 on 2026-11-24, 26.6.8 to 26.6.10 on the morning of 2026-11-25). Type declarations only: the companion's build erases them and ships none, and its build and tests pass on 26.6.6. Left for its Dependabot PR (weekly) once the series settles. Every other direct dependency of the companion is at its newest; `npm audit` reports 0 vulnerabilities. |
| `playwright` 1.66 (test/browser) | 1.65.1 | npm's `next` is a 1.66.0 alpha (`1.66.0-alpha-2026-11-25`); no 1.66 release exists. `latest` is 1.65.1, the pinned version. |
| Elixir minors and majors (#727) | Elixir 1.19.7 (1.20.5 exists) | 1.20 stays blocked upstream: excoveralls 0.18.5 is still the newest release, and #727's Elixir half waits on one naming 1.20 cover support. |
| OTP 28 and 29 | OTP 27.3.4.20 with M1 (28.5.0.9 and 29.1.3 exist) | Waits on #727's OTP half (above): the Sprint 24 run of the trigger's own test was red, and nothing upstream that it depends on has moved since. An OTP 28 move also needs the `@issuers` change in `logo_lookup.ex`. |
| PostgreSQL major | 18 (`18.7`, by digest) | PostgreSQL **19.0** images are on Docker Hub (first seen by the last report on 2026-11-20; the tags were pushed again on 2026-11-23 and 2026-11-24). A major needs a dump and a restore of every instance's data, and Dependabot ignores PostgreSQL majors by configuration; it is a decision of its own, with its release notes read (not read in this lane), not a lane bump. Unchanged since the last report. |
| BMAD core v7 | 6.12.4 (`latest`) | No 6.13 or 7.x is published or tagged; v7 is the preview on `main` (still `e435a22`, versioned `6.13.0-next`). Its changelog, as the Sprint 30 report read it at the same commit, lists breaking moves for this repository's layout (`planning_artifacts` and `implementation_artifacts` no longer read, a `bmad migrate method` step, advanced elicitation rebuilt with its `preferences` key renamed to `persistent_facts`, `bmad-spec` and `bmad-correct-course` replaced by a Product Owner agent), so the core move, `tea` and `bmb` majors stay one decision when a release ships (Sprint 24's M2, "When it comes back"). |
| BMAD `tea` v3.x and v4.x | v1.27.3 pinned (newest **v4.6.0**) | The v4 line moved again: v4.4.0 to v4.4.3 (2026-11-23), v4.5.0 (2026-11-24, a BMad v7 compatibility section in the installation guide) and v4.6.0 (2026-11-25, target findings in Evaluate); npm's `latest` is 4.6.0 and the repository's head `6d231e6`. v4.6.0's `skills/bmod-tea/bmod.toml` still requires the core skill at `version = "6.13.0-next"`, so it does not install through the pinned 6.12.4 installer; it belongs to the v7 decision. The v1 line still ends at v1.27.3 (`c3d4f34`, the pinned commit), so there is no patch to re-pin. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. The v7 preview's changelog says the builder module "joins this repository as Toolsmith" (`bmod-toolsmith`), so in v7 `bmb` stops being an external module; the move belongs with the v7 core decision. No v1.8 patch after v1.8.1 (`3410d95`, the pinned commit). |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag (`97298b2`); `main` is still `3e89a5d`, unreleased. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | The installer marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. npm's `bmad-story-automator` is still 1.15.0 (last modified 2026-05-17). **Its repository was not read this lane:** the session's network refused github.com for `bmad-code-org/bmad-automator` (403 from the agent proxy), so whether `main` moved past `0b94fd7` is unknown; nothing is taken either way. |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.19.7, OTP 27.3.4.20
  with M1; the development image and the release's build stage on
  `hexpm/elixir:1.19.7-erlang-27.3.4.20-debian-bookworm-20261123` (the
  build stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261123-slim`; Node 26 in CI (the companion's
  `engines` say `>=26 <27`) and 26.13.1 in the companion's image;
  PostgreSQL 18.7 in Compose and CI; every image pinned by digest. The OTP
  inside the build image was not read (no Docker in the session; the
  script says so); the tag names 27.3.4.20.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement), `phoenix_live_view` 1.2.15 and `lazy_html` 0.1.16
  (declined above); `postgrex` 0.23.0 with M1, `db_connection` 2.10.3 from
  `main`'s advisory fix; `mix hex.audit` and `mix deps.audit` report
  nothing; `mix deps.unlock --check-unused` is clean.
- **npm:** mcp-server has one direct dependency behind, the dev-only
  `@types/node` patch (declined above); test/browser's `playwright` is at
  1.65.1, npm's `latest`; `npm audit` reports 0 vulnerabilities in both.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`). Nothing moved.
- **Sources read:** hex.pm (through `mix`, including `mix hex.outdated
  --all`, `mix hex.package fetch` of `postgrex` 0.23.0 and `lazy_html`
  0.1.16, and its package API for release dates), registry.npmjs.org
  (through `npm`), builds.hex.pm (the OTP and Elixir build lists and the
  27.3.4.20 archive), OTP 27.3.4.20's README from its GitHub release,
  `tea`'s `bmod.toml` and changelog at `v4.6.0` on
  raw.githubusercontent.com, nodejs.org's release index, hub.docker.com's
  tag listings and mirror.gcr.io's manifests, cdn.playwright.dev (the
  1.65.1 Chromium and headless shell, revision 1255, for the walks), this
  repository's open pull requests through the GitHub tool (read only), and
  the BMAD repositories through `git ls-remote`. **Not read:**
  erlang.org (refused by the session's network; the OTP README came from
  GitHub instead), the `bmad-automator` repository (refused, above),
  mirror.gcr.io's `hexpm/elixir` manifests (rate-limited, HTTP 429; the
  digests are Docker Hub's, as in earlier lanes), PostgreSQL 19's release
  notes, postgresql.org, and the GitHub advisory database and osv.dev
  directly (the advisories are read through `mix hex.audit`, `mix
  deps.audit`, `npm audit` and the packages' changelogs).
- **The local toolchain** of the cloud session that ran this lane is
  Elixir 1.19.7 with OTP 27.3.4.19 in `/opt/otp` (shared with other
  agents, so not replaced); the lane installed OTP 27.3.4.20 from
  builds.hex.pm (sha256 verified) into its own scratch directory and ran
  every gate below with it first on `PATH`. Node 22 (CI runs the companion
  and the walks on Node 26); a local PostgreSQL 16 serves the test
  database.

## Gate results on the lane's head

Run on 2026-11-25 on OTP 27.3.4.20 (above), Elixir 1.19.7, Node 22. Each
exit status was read directly, never through a pipe. "OTP" is the head
with the toolchain commit only; "postgrex" is the head with both bumps.

| Gate | OTP | postgrex |
| --- | --- | --- |
| `mix test` (full) | 7438 tests, 14 properties, 0 failures | 7438 tests, 14 properties, 0 failures |
| `mix test --only sweep` | 401 tests, 0 failures | 401 tests, 0 failures |
| `mix test test/portfolixir/ci_test.exs` (the pin parity) | 47 tests, 0 failures | (in the full run) |
| Browser walks (`--only browser`) on Playwright 1.65.1's headless shell, revision 1255 | `launch_check`, `settle_check`, `storage_blocked`, `dashboard_edit`, `control_bar`, `shipped_font`: 18 tests, 0 failures | `launch_check`, `storage_blocked`, `dashboard_edit`, `dashboard_period`: 4 tests, 0 failures |
| `mix format --check-formatted`; `mix compile --force --warnings-as-errors` (dev and test) | exit 0; exit 0 | exit 0; exit 0 |
| `mix gettext.extract --check-up-to-date` | exit 0 | exit 0 |
| `mix credo --strict` | exit 0, no issues | exit 0, no issues |
| `mix sobelow --skip --exit --no-config` | exit 0 | exit 0 |
| `mix deps.unlock --check-unused` | exit 0 | exit 0 |
| `mix hex.audit` | exit 0, no retired or advisory packages | exit 0, no retired or advisory packages |
| `mix deps.audit` | exit 0, no vulnerabilities | exit 0, no vulnerabilities |
| `mix dialyzer --format short` (a PLT built fresh on 27.3.4.20) | (one run, on the head with both) | exit 0, 0 errors |
| `npm test --prefix mcp-server`; `npm run build --prefix mcp-server` | 374 tests, 0 failures; exit 0 | (untouched) |
| `npm audit --audit-level=high` in `mcp-server` and `test/browser` | exit 0, exit 0 | (untouched) |
| `pre-commit run --all-files` | exit 0, every hook passed | exit 0, every hook passed (with this report) |

`mix coveralls` and the full browser suite run at the sprint's
integration, by the orchestrator, and CI's jobs run on OTP 27.3.4.20
from the toolchain commit on.
