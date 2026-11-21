# Version Report — 2026-11-21 (Sprint 31 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, read with the sections of
`scripts/version-report.sh` (#676) **at lane time**, on the sprint branch
as the lane found it (`main` with the Sprint 31 planning PR, then the
branch's two advisory fixes and M2 to M4), in the lane's own worktree
(the Sprint 31 plan's Lane M, M1). The lane reports
what it deliberately did not update and why. A row whose reasoning has
not changed since the last report carries that reasoning again, so this
report reads on its own. Commits are named by subject, because the
branch's history is cleaned before the merge and hashes change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `phoenix_live_view`, on the branch before the lane | 1.2.13 → **1.2.14** | "deps: phoenix_live_view 1.2.14, for EEF-CVE-2026-126334" (closes #1479) | A new advisory (MEDIUM): a LiveView joined without a `url` skipped its `live_session`'s `on_mount` hooks, `LiveUiAuth` among them. It turned CI's advisories job red on every branch, Dependabot's #1476 and #1477 included. Only its lock line moved. Recorded here because it moved the lockfile after the last report. |
| `phoenix`, on the branch before the lane | 1.8.16 → **1.8.17** | "deps: phoenix 1.8.17, for EEF-CVE-2026-128361 and EEF-CVE-2026-129344" | Two advisories against 1.8.16, both HIGH: an unsanitized presence key crashes the Presence tracker; a client-selected V1 serializer crashes a shared broadcast on binary payloads. `mix hex.audit` turned the advisories job red on the sprint branch. Only its lock line moved (`phoenix` unlocked alone, not `deps.update`, which would have taken `bandit` and `websock_adapter` along). |
| `bandit`, M1, Dependabot #1476 | 1.14.1 → **1.15.0** | "deps: bandit 1.15.0, its Dependabot run green (M1, #1476)" | **Sprint 30's declared trigger fired.** Sprint 30 declined it because no fix in it reaches the app (its HTTP/2 advisory GHSA-j9wq-h5xx-5qx5 is in the path the endpoint switches off; its WebSocket fragment fix is already covered by the LiveView socket's 512 KiB `max_frame_size`), so it waited "for its Dependabot PR and that PR's CI run". #1476 (opened 2026-11-20) ran CI on 2026-11-21: test (7102 tests, 0 failures), browser, quality, advisories, compose-smoke, migration-roundtrip and pre-commit green. Its two red jobs are not the bump's: the test job's Codecov upload ("Token required because branch is protected": a Dependabot branch gets no secrets) and human-accountability (the commit is `dependabot[bot]`'s). Taken on the branch rather than by merging #1476, whose commit cannot pass the authorship gate. Behaviour changes, as Sprint 30 read them with `mix hex.package diff bandit 1.14.1..1.15.0`: idle connection processes hibernate after 15 s, bodies under 300 bytes and already-compressed types are no longer compressed, HTTP/2 rejects more malformed requests, Bandit's own error responses carry `date` and HTTP/1.1. Only its lock line moves (it requires `thousand_island ~> 1.6`, locked at 1.6.0); `mix.exs` keeps its requirement. The worktree's `deps` link was replaced by a copy of its own before the fetch (M4's `scripts/worktree.sh own`, through the `deps.update` alias), and the main checkout's `deps` still hold 1.14.1. |
| `playwright` (test/browser), M1, Dependabot #1477 | 1.65.0 → **1.65.1**, pinned exactly | "chore(deps): playwright 1.65.1 in test/browser, pinned exactly (M1, #1477)" | **Sprint 30's declared trigger fired**, weighed against M2. Sprint 30 declined 1.65.1 so that CI's check of 1.65.0's Chromium move was not folded into a second one, and left it "to Dependabot once `main` has 1.65.0; its PR's browser job verifies revision 1255". #1477 (2026-11-20) ran CI with the **browser job green** on 1.65.1; its advisories and test-job audit were red on `phoenix_live_view` 1.2.13 (fixed on the branch since), its suite passed (7102 tests, 0 failures) and only the Codecov upload and the authorship check failed, as on #1476. M2 now launches the pinned release's `chromium-headless-shell`, so the version is the browser: 1.65.1 moves it to revision **1255 (159.0.8154.6)**, a new Chromium major, read from `playwright-core` 1.65.1's `browsers.json`; the release notes at `v1.65.1` list nothing beyond 1.65.0. Taken now so the walks measure in the browser CI already verified for this release. Its headless shell was installed in the session (cdn.playwright.dev reachable), and `launch.js` reports "launched chromium-headless-shell of Playwright 1.65.1, Chromium 159.0.8154.6"; six walks passed on it (gate table). `npm audit` reports 0 vulnerabilities. |

No other version moved in this lane: every candidate below is declined,
each with its reason. Every bump is its own commit, never mixed into a
risk-tier story's commits (ADR-0036 clause 1). The plan estimated one to
three commits for M1; the lane has three (two bumps and this report).

## Dependabot

Read from GitHub's pull requests at lane time (about 17:30 UTC; read
only, through `gh api`; the lane comments on and closes nothing). Two
Dependabot PRs are open, both taken by M1 above:

- **#1476**, `bandit` 1.14.1 → 1.15.0, from 2026-11-20: the lane's
  commit carries the same lock line; Dependabot closes the PR itself
  once `main` has the version.
- **#1477**, `playwright` 1.65.0 → 1.65.1 in `/test/browser`, from
  2026-11-20: the same, for `test/browser`'s manifest and lockfile.

**#1392** (`floki` 0.38.4 → 0.38.5) is **closed**: the owner closed it
on 2026-11-21 at 10:02 UTC, and the lockfile reads `floki` 0.38.5 (Sprint
28's M1 took it). The planning session's registry step "close #1392 by
hand if Dependabot has not" is therefore done; nothing is left to do for
it.

No Dependabot PR had opened by lane time for `phoenix_live_view` 1.2.15,
the transitive minors or PostgreSQL 19.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#1476's CI run** (Sprint 30's trigger for `bandit` 1.15.0) | the PR's check runs and its test job's log | **Yes.** Taken (above). |
| **#1477's browser job on revision 1255** (Sprint 30's trigger for `playwright` 1.65.1) | the PR's check runs | **Yes.** Taken (above). |
| **A BMAD release since 6.12.4** | npm: `bmad-method` dist-tags are `latest` 6.12.4, `next` 6.12.3-next.1, `rollback` 4.39.0; the method repository's newest tag is v6.12.4 (`git ls-remote`), and `main` is still `e435a22` | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261104, with its image** | Docker Hub: `debian:bookworm-20261104` and `-slim` (2026-11-05) are the newest dates, `-slim` still `734a72b3…`; `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` and `-slim` still `ecb921d9…` and `01499334…`, the digests the branch pins | **No** |
| **An Elixir 1.19 patch after 1.19.7, with its image** | builds.hex.pm's Elixir build list: `v1.19.7-otp-27` (2026-10-29) is the newest 1.19 | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No**; 1.20.5 (2026-10-29) is still the newest 1.20, and no 1.21 build exists. |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7 of Sprint 24) | `mix hex.outdated --all`: `ecto` and `ecto_sql` up to date; no Elixir release since 1.19.7 / 1.20.5 | **No**. The trigger's own test was not re-run: nothing it depends on moved (OTP 28.5.0.8 and 29.1.2 are still the newest 28 and 29). |
| **A Node 26 security release after the image's** | nodejs.org's release index: 26.13.1 (2026-11-10, `security: true`) is still the newest 26; Docker Hub's `26.13.1-alpine3.24` is still `6bd9ab43…`, the digest both stages pin | **No** |
| **A PostgreSQL 18 minor with security fixes** | Docker Hub: 18.7 is the newest 18 minor. Its tag listing shows `18.7-alpine3.24` pushed again on 2026-11-21, but `mirror.gcr.io` serves the pinned index `ff64c9e3…` and the tag's current index with the same amd64 image (`68e33adb…`, built 2026-11-18): no new build reached the pinned platforms | **No** |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279, closed 2026-11-01) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. No release after 3.2.0; unchanged since. |
| `phoenix_live_view` | 1.2.14 (1.2.15, published 2026-11-21) | **New this lane.** Its changelog: "the same code as 1.2.14, but it fixes the generated client type declarations missing in the previous version". Read from the package itself (`mix hex.package fetch`): against the installed 1.2.14 the release adds only `assets/js/types/*.d.ts` files. The app ships no TypeScript client and builds nothing from them, so the release changes nothing the app runs; no advisory names 1.2.14. Left for its Dependabot PR or the next fix. |
| `websock_adapter`, `nimble_options`, `finch`, `nimble_pool` (transitive) | 0.6.0 (0.7.2), 1.1.1 (1.2.0), 0.24.0 (0.25.0), 1.1.0 (1.2.0) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. Unchanged since the last report. |
| npm (mcp-server) | every direct dependency at its newest | The lockfile and npm agree: `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2, `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7, `typescript` 7.0.2, `tsx` 4.23.15, `@types/express` 5.0.6, `@types/node` 26.6.6 (a `@types/node` major beyond the Node 26 runtime is ignored by Dependabot, #728). `npm audit` reports 0 vulnerabilities. |
| `playwright` 1.66 (test/browser) | 1.65.1 with M1 | npm's `next` is a 1.66.0 alpha (2026-11-21); no 1.66 release exists. |
| Elixir minors and majors (#727) | Elixir 1.19.7 (1.20.5 exists) | 1.20 stays blocked upstream: excoveralls 0.18.5 is still the newest release, and #727's Elixir half waits on one naming 1.20 cover support. |
| OTP 28 and 29 | OTP 27.3.4.19 (28.5.0.8 and 29.1.2 exist) | Waits on #727's OTP half (above): the Sprint 24 run of the trigger's own test was red, and nothing upstream that it depends on has moved since. An OTP 28 move also needs the `@issuers` change in `logo_lookup.ex`. |
| PostgreSQL major | 18 (`18.7`, by digest) | **New this lane:** PostgreSQL **19.0** images appeared on Docker Hub on 2026-11-20 (`19.0`, `19.0-alpine3.24` and the others; the last report saw `19rc2`). A major needs a dump and a restore of every instance's data, and Dependabot ignores PostgreSQL majors by configuration; it is a decision of its own, with its release notes read (not read in this lane), not a lane bump. |
| BMAD core v7 | 6.12.4 (`latest`) | No 6.13 or 7.x is published or tagged; v7 is the preview on `main` (still `e435a22`, versioned `6.13.0-next`). Its changelog, as the Sprint 30 report read it at the same commit, lists breaking moves for this repository's layout (`planning_artifacts` and `implementation_artifacts` no longer read, a `bmad migrate method` step, advanced elicitation rebuilt with its `preferences` key renamed to `persistent_facts`, `bmad-spec` and `bmad-correct-course` replaced by a Product Owner agent), so the core move, `tea` and `bmb` majors stay one decision when a release ships (Sprint 24's M2, "When it comes back"). |
| BMAD `tea` v3.x and v4.x | v1.27.3 pinned (newest **v4.3.1**) | The v4 line moved again: v4.2.0 and v4.3.0 (both 2026-11-19, `eval-quality` 10.0.0 and 10.1.0 adopted, evidence artifacts at schema version 5) and v4.3.1 (2026-11-20, the red-mode guide on BMad v7's `workflow.implementation_handoff`); npm's `latest` is 4.3.1 and the repository's head `6fba06e`. v4.3.1's `skills/bmod-tea/bmod.toml` still requires the core skill at `version = "6.13.0-next"`, so it does not install through the pinned 6.12.4 installer; it belongs to the v7 decision. The v1 line still ends at v1.27.3 (`c3d4f34`, the pinned commit), so there is no patch to re-pin. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. The v7 preview's changelog says the builder module "joins this repository as Toolsmith" (`bmod-toolsmith`), so in v7 `bmb` stops being an external module; the move belongs with the v7 core decision. No v1.8 patch after v1.8.1 (`3410d95`, the pinned commit). |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag (`97298b2`); `main` is still `3e89a5d`, unreleased. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | The installer marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. Its newest tags are v1.15.0 and v1.15.0-next.1, neither `main`'s head; the install tracks `main`. |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.19.7, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261104-slim`; Node 26 in CI (the companion's `engines`
  say `>=26 <27`) and 26.13.1 in the companion's image; PostgreSQL 18.7 in
  Compose and CI; every image pinned by digest. The OTP inside the build
  image was not read (no Docker in the session; the script says so); the
  tag names 27.3.4.19.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement) and `phoenix_live_view` 1.2.15 (declined above); `phoenix`
  1.8.17 and `phoenix_live_view` 1.2.14 from the branch's advisory fixes,
  `bandit` 1.15.0 with M1; `mix hex.audit` and `mix deps.audit` report
  nothing; `mix deps.unlock --check-unused` is clean.
- **npm:** mcp-server has no direct dependency behind; test/browser's
  `playwright` is at 1.65.1 with M1, npm's `latest`; `npm audit` reports 0
  vulnerabilities in both.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`). Nothing moved.
- **Sources read:** hex.pm (through `mix`, including `mix hex.outdated
  --all`, `mix hex.package fetch` of `phoenix_live_view` 1.2.15, and its
  package API for release dates and `bandit` 1.15.0's requirements),
  registry.npmjs.org (through `npm`, including `playwright-core` 1.65.1's
  `browsers.json`), cdn.playwright.dev (the 1.65.1 headless shell),
  Playwright's release notes at `v1.65.1` and `tea`'s `bmod.toml` and
  changelog at `v4.3.1`, both on raw.githubusercontent.com,
  builds.hex.pm, nodejs.org's release index, hub.docker.com's tag
  listings and mirror.gcr.io's manifests, this repository's pull requests,
  their check runs and job logs through GitHub's REST API (`gh api`, read
  only), and the BMAD repositories through `git ls-remote`. **Not read:**
  registry-1.docker.io (its unauthenticated pull limit refused the
  manifest reads; mirror.gcr.io answered instead), GitHub's API for the
  `tea` repository (not enabled for the session; the tag dates come from
  its changelog), PostgreSQL 19's release notes, postgresql.org, and the
  GitHub advisory database and osv.dev directly (the advisories are read
  through `mix hex.audit` and `mix deps.audit` and the packages'
  changelogs).
- **The local toolchain** of the cloud session that ran this lane is OTP 27
  with Elixir 1.19.7, the pinned pair; Node 22 (CI runs the companion and
  the walks on Node 26); a local PostgreSQL 16 serves the test database.

## Gate results on the lane's head

Run on the lane's head (the branch plus M5 and the two M1 bump commits,
before this report's commit) on 2026-11-21, local toolchain Elixir 1.19.7
/ OTP 27, Node 22. Each exit status was read directly, never through a
pipe. With the HTTP server's lock line and a test-only npm pin moved, the
gates run are the ones those can reach; the full `mix test`, `mix
coveralls`, `mix dialyzer` and the browser job run at the sprint's
integration, by the orchestrator, and CI's jobs run on revision 1255.

| Gate | Result |
| --- | --- |
| `mix test test/invariants` | 325 tests, 0 failures |
| `bandit` 1.15.0: the listener, socket, plug, controller, UI-auth and CI-pin tests with the portfolio, dashboard and import LiveView tests | 1171 tests, 0 failures |
| `playwright` 1.65.1: `ci_test`, `docs_test`, `workflow_docs_test`, `dev_config_test` | 137 tests, 0 failures |
| Browser walks on 1.65.1's headless shell, revision 1255 (`launch_check`, `settle_check`, `storage_blocked`, `rail_persists`, `control_bar`, `info_tips_click_away`; `--only browser`) | 18 tests, 0 failures (582 s on the shared machine) |
| `mix format --check-formatted`, `mix compile --force --warnings-as-errors` (`MIX_ENV=test`) | exit 0, exit 0 |
| `mix sobelow --skip --exit` | exit 0 |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | exit 0, no retired or advisory packages |
| `mix deps.audit` | exit 0, no vulnerabilities |
| `npm audit --audit-level=high --prefix mcp-server` | exit 0, 0 vulnerabilities |
| `npm audit --audit-level=high --prefix test/browser` | exit 0, 0 vulnerabilities |
| `scripts/version-report.sh` | exit 0 (the OTP inside the build image not read: no Docker) |
| `pre-commit run --all-files` | exit 0, every hook passed |
