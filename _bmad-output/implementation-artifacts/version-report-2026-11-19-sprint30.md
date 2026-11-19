# Version Report — 2026-11-19 (Sprint 30 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, read with the sections of
`scripts/version-report.sh` (#676) **at lane time**, on the sprint's base
(`main` at `8ec5723`: the Sprint 30 planning PR and its amendments, the
owner's intake documents and the `plug` advisory fix), in the lane's own
worktree (the Sprint 30 plan's Lane M, M1). The lane reports what it
deliberately did not update and why. A row whose reasoning has not changed
since the last report carries that reasoning again, so this report reads on
its own. Commits are named by subject, because the branch's history is
cleaned before the merge and hashes change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `plug`, with `telemetry` (transitive) under it, on `main` before this branch | `plug` 1.20.3 → **1.20.4**; `telemetry` 1.4.2 → **1.4.3** | "fix(deps): plug 1.20.4 for EEF-CVE-2026-120287", on `main` (2026-11-19), outside the lane | A new advisory: `Plug.Parsers.MULTIPART` did not charge part and header framing against the `:length` limit, which bounds an upload's size on the import page. The owner asked for the fix on the intake PR, and it closed #1469. A lock bump inside `mix.exs`'s `~> 1.20`; `telemetry` 1.4.3 came with it as plug's dependency. Recorded here because it moved the lockfile after the last report; the lane changed nothing about it. |
| `playwright` (test/browser), M1, Dependabot #1463 | 1.64.1 → **1.65.0**, pinned exactly | "chore(deps): playwright 1.65.0 in test/browser, pinned exactly (M1, Dependabot #1463)" | The Sprint 30 plan takes it in M1. 1.65.0 (published 2026-11-05) moves the Chromium CI's browser job installs from revision 1248 (156.0.8078.4) to **1254 (158.0.8127.18)**, read from `playwright-core` 1.65.0's `browsers.json`. Its release notes' breaking changes that can reach a walk: actions now wait for an element to be not inert, text a browser does not render leaves accessible names and aria snapshots, cookie matching follows RFC 6265, proxy credentials go only to proxies; the rest concern Playwright's test runner, which the walks do not use (they drive the library through `launch.js`), and the request API's `params` option, which the one walk that sends requests (`privacy_leak.js`, `context.request.get`) does not pass. The five walks run here passed under them (gate table). Nothing else pins the version: `package.json` and the lockfile name it, `ci_test` holds them equal and exact, and CI's job runs `npm ci` on the lockfile and then `playwright install --with-deps chromium`, which fetches that release's Chromium. This session's preinstalled Chromium is revision **1243** (Chrome for Testing 153.0.8010.12), not 1254, so the walks below ran on 1.65.0's library with that older browser (`PLAYWRIGHT_CHROMIUM_EXECUTABLE`); **CI's `browser` job verifies the bump on revision 1254**. `npm audit` reports 0 vulnerabilities. Dependabot closes #1463 itself once `main` has the bump. |
| PostgreSQL, Compose and CI, M1 | `postgres:18.6-alpine3.24@sha256:10a5c69a…` → **`postgres:18.7-alpine3.24@sha256:ff64c9e3…`** (both Compose files); CI's `mirror.gcr.io/library/postgres:18.6@sha256:5a5a84b1…` → **`…:18.7@sha256:e754b839…`** (the `test`, `browser` and `migration-roundtrip` jobs) | "chore(docker): PostgreSQL 18.6 -> 18.7, the security release, in Compose and CI (M1)" | **New this lane.** PostgreSQL 18.7 (released 2026-11-12; the images 2026-11-18) fixes **99 CVEs**, read from its release notes (`doc/src/sgml/release-18.sgml` at the `REL_18_7` tag on raw.githubusercontent.com; postgresql.org was blocked from the session): use-after-free and buffer overruns reachable through SQL (among them `tsvector_delete()`, `ts_rank_cd()`, `COPY FROM ON_ERROR`, `pg_show_all_settings()`), server memory disclosure, a crash and restart that a well-timed cancel request can cause (CVE-2026-116322), and privilege-check gaps (`REASSIGN OWNED`, `DROP OWNED BY` and row-level security, `INSERT … ON CONFLICT` through views). The Compose database is the one every instance runs, so the lane's rule ("change nothing unless a security fix forces it") is met: the lane takes it ahead of Dependabot, which watches the Compose files but had opened nothing for 18.7 by lane time, and CI's service image moves with it so the tests run on the release the instances run (`ci_test` holds the jobs equal). Digests: the multi-architecture index Docker Hub serves for each tag, the same at `mirror.gcr.io`; the amd64 configs read `PG_VERSION=18.7` (Alpine) and `PG_VERSION=18.7-1.pgdg13+2` (Debian). **No dump and restore** within 18.x. The release asks to reindex indexes hit by its corruption fixes: GIN posting trees, `pg_trgm` GiST indexes, btree de-duplication on `bpchar`, and TOAST-table indexes after `REINDEX CONCURRENTLY`. The migrations create no GIN index, no `pg_trgm` index and no `char` column (the one GiST index is `btree_gist`'s exclusion constraint on policy rules), and the app runs no `REINDEX CONCURRENTLY`, so an instance has nothing to reindex as far as the schema shows. This session's test database is a local PostgreSQL 16.15, so the move was not exercised here: CI's `test`, `browser` and `migration-roundtrip` jobs run on the 18.7 service image, and the `compose-smoke` job pulls Compose's. |
| `sobelow` (dev and test only), M1 | 0.18.1 → **0.19.0** | "chore(deps): sobelow 0.18.1 -> 0.19.0, dev and test only (M1)" | **New this lane**, one of the two direct dependencies `mix hex.outdated` reads as "Update possible" (published 2026-11-12). 0.19.0 adds denial-of-service checks: `DOS.Zip`, `DOS.Tar`, `DOS.Decompression` and `DOS.CompressedFile` for unbounded extraction, `DOS.XML` for entity expansion, `DOS.Regex` for dynamically compiled patterns; the app parses news feeds as XML and reads uploaded files, so the checks guard code it has. Its changelog says finding locations and skip fingerprints are preserved, and on this tree they are: without the skip list, 0.18.1 and 0.19.0 report the same 20 findings line for line, and `mix sobelow --skip --exit` exits 0 on both. Never shipped (`only: [:dev, :test], runtime: false`), so it is outside the dialyzer PLT's app tree. A lockfile change of one entry; `mix.exs` keeps `~> 0.18`. |

No other version moved in this lane: every candidate below is declined or
left to its Dependabot PR, each with its reason. Every row is its own
commit group, never mixed into a risk-tier story's commits (ADR-0036
clause 1). The plan estimated one to three commits for M1; the lane has
four (three bumps and this report), because PostgreSQL 18.7 shipped after
the plan was written.

## Dependabot

Read from GitHub's open pull requests at lane time (15:48 UTC; read only;
the lane comments on and closes nothing). Two Dependabot PRs are open:

- **#1463**, `playwright` 1.64.1 → 1.65.0 in `/test/browser`, from
  2026-11-13: taken by M1 (above). Dependabot closes it itself once
  `main` has the bump, as the Sprint 30 plan tells the owner.
- **#1392**, `floki` 0.38.4 → 0.38.5 (test only), from 2026-11-05: Sprint
  28's M1 took the same bump ("chore(deps): floki 0.38.5, test only (M1,
  Dependabot #1392)"), and the lockfile on `main` reads 0.38.5, so the PR
  changes nothing any more. **It can be closed**, as the last report
  said; the lane does not close it.

No Dependabot PR had opened by lane time for `bandit` 1.15.0, `sobelow`
0.19.0, `playwright` 1.65.1 or PostgreSQL 18.7 in Compose.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.4** | npm: `bmad-method` dist-tags are `latest` 6.12.4, `next` 6.12.3-next.1, `rollback` 4.39.0; the method repository's newest tag is v6.12.4 (`git ls-remote`). `main` is still `e435a22`, as the last report read it, the v7 preview versioned `6.13.0-next` | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261104, with its image** | Docker Hub: `debian:bookworm-20261104` and `-slim` (2026-11-05) are the newest dates; `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` and `-slim` are still the digests the branch pins (`ecb921d9…`, `01499334…`), and the runtime's `bookworm-20261104-slim` is still `734a72b3…` | **No** |
| **An Elixir 1.19 patch after 1.19.7, with its image** | builds.hex.pm's Elixir build list: `v1.19.7-otp-27` (2026-10-29) is the newest 1.19 | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm (`mix hex.outdated --all`): excoveralls 0.18.5 is still the newest release | **No** for 1.20 (newest 1.20.5, 2026-10-29; no 1.21 build exists). |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7 of Sprint 24) | hex.pm: `ecto` and `ecto_sql` read up to date in `mix hex.outdated --all` (3.14.3 and 3.14.0); no Elixir release since 1.19.7 / 1.20.5 | **No**. The trigger's own test was not re-run: neither Ecto nor Elixir moved since Sprint 24 ran it on OTP 28.5.0.8 (still the newest 28 patch; 29.1.2 the newest 29). |
| **A Node 26 security release after the image's** | the Node release index: 26.13.1 (2026-11-10, `security: true`) is still the newest 26; Docker Hub's `26.13.1-alpine3.24` index is still `6bd9ab43…`, the digest both stages pin | **No** |
| **A PostgreSQL 18 minor with security fixes** (read because Docker Hub's `18.7` tags appeared) | Docker Hub: `18.7` (2026-11-19) and `18.7-alpine3.24` (2026-11-18); the 18.7 release notes list 99 CVEs | **Yes.** Taken (above). |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279, closed 2026-11-01) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. No release after 3.2.0; unchanged since. |
| `bandit` | 1.14.1 (1.15.0, published 2026-11-17) | **New this lane.** The HTTP server every instance runs, a minor with behaviour changes (read with `mix hex.package diff bandit 1.14.1..1.15.0`): connection processes hibernate after 15 s, response bodies under 300 bytes and already-compressed types are no longer compressed, HTTP/2 rejects more malformed requests, Bandit's own error responses carry a `date` header and HTTP/1.1. Its one advisory, GHSA-j9wq-h5xx-5qx5 (an HPACK-compressed HTTP/2 trailer section causing large CPU use and log volume), is in the HTTP/2 path the endpoint switches off (`http_2_options: [enabled: false]`, `config/config.exs`). Its WebSocket fix, `max_fragmented_message_size` applied to a fragmented message's first frame, is already covered here: the LiveView socket's `max_frame_size` is the same 512 KiB as the listener's `max_fragmented_message_size` (`PortfolixirWeb.LiveSocket`), so a first frame cannot pass the bound alone. `mix hex.audit` and `mix deps.audit` report nothing. So no fix reaches the app, and a shipped minor without one waits for its Dependabot PR and that PR's CI run. Flippable: say "take bandit" and the lane's next pass takes it. |
| `websock_adapter`, `nimble_options`, `finch`, `nimble_pool` (transitive) | 0.6.0 (0.7.2), 1.1.1 (1.2.0), 0.24.0 (0.25.0, 2026-11-18), 1.1.0 (1.2.0, 2026-11-16) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. `finch` (under `req`, `~> 0.21`) and `nimble_pool` (under `finch`, `~> 1.1`) are new to this row. |
| npm (mcp-server) | every direct dependency at its newest | The lockfile and npm agree: `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2, `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7, `typescript` 7.0.2 (npm's `latest`; `beta` is 7.1.0-beta), `tsx` 4.23.15, `@types/express` 5.0.6, `@types/node` 26.6.6 (npm's `latest`; a `@types/node` major beyond the Node 26 runtime is ignored by Dependabot, #728). `npm outdated` lists four as "MISSING" only because the lane's worktree has no installed `node_modules`; their wanted and latest versions are the locked ones. `npm audit` reports 0 vulnerabilities. |
| `playwright` 1.65.1 (test/browser) | 1.65.0 with M1 (1.65.1 is npm's `latest`, published 2026-11-13) | **New this lane.** A patch that moves the Chromium again, to revision **1255 (159.0.8154.6)**, a new Chromium major, read from `playwright-core` 1.65.1's `browsers.json`; the release notes at its tag list nothing beyond 1.65.0. The plan's reviewed scope and #1463 name 1.65.0, and folding a second Chromium move into it would leave CI's verification of the first unseen. No advisory forces it. It is Dependabot's to propose once `main` has 1.65.0; its PR's browser job verifies revision 1255. |
| Elixir minors and majors (#727) | Elixir 1.19.7 (1.20.5 exists) | 1.20 stays blocked upstream: excoveralls 0.18.5 is still the newest release, and #727's Elixir half waits on one naming 1.20 cover support. |
| OTP 28 and 29 | OTP 27.3.4.19 (28.5.0.8 and 29.1.2 exist) | Waits on #727's OTP half (above): the Sprint 24 run of the trigger's own test was red, and nothing upstream that it depends on has moved since. An OTP 28 move also needs the `@issuers` change in `logo_lookup.ex`. |
| BMAD core v7 | 6.12.4 (`latest`) | No 6.13 or 7.x is published or tagged; v7 is the preview on `main` (still `e435a22`, versioned `6.13.0-next`). Its changelog, as the last report read it at the same commit, lists breaking moves for this repository's layout (`planning_artifacts` and `implementation_artifacts` no longer read, a `bmad migrate method` step, advanced elicitation rebuilt with its `preferences` key renamed to `persistent_facts`, `bmad-spec` and `bmad-correct-course` replaced by a Product Owner agent), so the core move, `tea` and `bmb` majors stay one decision when a release ships (Sprint 24's M2, "When it comes back"). |
| BMAD `tea` v3.x and v4.x | v1.27.3 pinned (newest **v4.1.0**, 2026-11-19) | The v4 line has moved: v4.0.1 (2026-11-13), v4.0.2 (2026-11-17) and v4.1.0 (2026-11-19, `73f5338`, `main`'s head and npm's `latest`), fixes to its enforcement hook and its trace workflow, and a note on red mode in a BMad v7 build. v4.1.0's `skills/bmod-tea/bmod.toml` still requires the core skill at `version = "6.13.0-next"`, so it does not install through the pinned 6.12.4 installer; it belongs to the same v7 decision. The v1 line still ends at v1.27.3 (`c3d4f34`, the pinned commit), so there is no patch to re-pin. |
| BMAD `bmb` | v1.8.1 pinned (latest v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. The v7 preview's changelog says the builder module "joins this repository as Toolsmith" (`bmod-toolsmith`), so in v7 `bmb` stops being an external module at all; the move belongs with the v7 core decision. The v1.8 line has no patch after v1.8.1 (`3410d95`, the pinned commit). |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag (`97298b2`), so there is nothing to take; `main` has moved to `3e89a5d` (the last report read `658e710`), none of it released. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | The installer marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. Its newest tag, v1.15.0 (`acafaed`), is not `main`'s head; the install tracks `main`. |
| PostgreSQL major | 18 (`18.7` with M1, by digest) | Docker Hub's `19rc2` (2026-11-19) is a release candidate, not a release; the major is pinned (Dependabot ignores PostgreSQL majors, and a major needs a dump and a restore). |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.19.7, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261104-slim`; Node 26 in CI (the companion's `engines`
  say `>=26 <27`) and 26.13.1 in the companion's image; PostgreSQL
  **18.7** in Compose and CI with M1; every image pinned by digest. The OTP
  inside the build image was not read (no Docker in the session; the
  script says so); the tag names 27.3.4.19.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement) and `bandit` (declined above); `plug` is at 1.20.4 from
  `main`, `sobelow` at 0.19.0 with M1; `mix hex.audit` and
  `mix deps.audit` report nothing; `mix deps.unlock --check-unused` is
  clean.
- **npm:** mcp-server has no direct dependency behind; test/browser's
  `playwright` is at 1.65.0 with M1, one patch behind (1.65.1, declined
  above); `npm audit` reports 0 vulnerabilities in both.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`). Nothing moved.
- **Sources read:** hex.pm (through `mix`, including `mix hex.package
  diff` for `bandit` and `sobelow`, and its package API for release
  dates), registry.npmjs.org (through `npm`, including `playwright-core`
  1.64.1, 1.65.0 and 1.65.1 for their browser revisions), Playwright's
  release notes at the `v1.65.1` tag and PostgreSQL's 18.7 release notes
  at `REL_18_7`, both on raw.githubusercontent.com, builds.hex.pm,
  nodejs.org's release index, hub.docker.com and mirror.gcr.io (HTTPS,
  including the 18.7 images' configs), this repository's pull requests
  through GitHub's REST API (`gh api`, read only), and the BMAD
  repositories on github.com through `git ls-remote` and a shallow
  `git fetch` of `tea`'s v4.1.0 tag. **Not read:** postgresql.org (blocked
  from the session), the GitHub advisory database and osv.dev for
  GHSA-j9wq-h5xx-5qx5 (not reachable; the advisory is read from Bandit's
  own changelog), Playwright's GitHub release page for 1.65.1 (not
  reachable), the BMAD release pages. The method repository's `main` was
  not fetched again: its head has not moved since the last report read
  it.
- **The local toolchain** of the cloud session that ran this lane is OTP 27
  with Elixir 1.19.7, the pinned pair; Node 22 (CI runs the companion and
  the walks on Node 26); a local PostgreSQL 16.15 serves the test database.

## Gate results on the lane's head

Run on the lane's head (the base plus the three M1 bump commits, before
this report's commit) on 2026-11-19, local toolchain Elixir 1.19.7 / OTP
27, Node 22. Each exit status was read directly, never through a pipe.
With a test-only npm pin, two image pins and a dev-and-test lockfile entry
moved, the gates run are the ones those can turn: the invariants, the
tests that read the lockfiles, the CI pins and the image pins, the audits,
the hooks, `sobelow` itself and a sample of the browser walks. `mix
dialyzer` was not run: no Hex dependency in its PLT moved (`sobelow` is
`runtime: false`, outside the app tree, and `plug` moved on `main` before
the base). The full `mix test`, `mix coveralls` and the browser job run at
the sprint's integration, by the orchestrator, and CI's jobs run on the new
PostgreSQL and Chromium.

| Gate | Result |
| --- | --- |
| `mix test test/invariants` | 311 tests, 0 failures |
| `mix test` on the files that read the lockfiles, the CI and image pins and the BMAD install (`ci_test`, `dev_config_test`, `docs_test`, `workflow_docs_test`) | 135 tests, 0 failures; with `compose_log_rotation_test`, `release_database_password_test` and `listener_bounds_test` beside them, 146 tests, 0 failures |
| `mix format --check-formatted`, `mix compile --force --warnings-as-errors` (`MIX_ENV=test`) | exit 0, exit 0 |
| `mix sobelow --skip --exit` on 0.19.0 | exit 0; without the skip list the same 20 findings as 0.18.1 |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | exit 0, no retired or advisory packages |
| `mix deps.audit` | exit 0, no vulnerabilities |
| `npm audit --audit-level=high --prefix mcp-server` | exit 0, 0 vulnerabilities |
| `npm audit --audit-level=high --prefix test/browser` | exit 0, 0 vulnerabilities |
| Browser walks on Playwright 1.65.0 with the preinstalled Chromium 1243 (`settle_check`, `storage_blocked`, `rail_persists`, `control_bar`, `info_tips_click_away`; `--only browser`) | 15 tests, 0 failures (4 in 26 s, 11 in 654 s on the shared machine); a check of the library against revision 1243, not of revision 1254, which CI's `browser` job verifies |
| `scripts/version-report.sh` | exit 0 (the OTP inside the build image not read: no Docker) |
| `pre-commit run --all-files` | exit 0, every hook passed (pre-commit 4.7.0, the pinned hook requirements installed with `--require-hashes`) |
