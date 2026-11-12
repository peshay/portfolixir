# Version Report — 2026-11-12 (Sprint 29 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, read with the sections of
`scripts/version-report.sh` (#676) **at lane time**, on the sprint's base
(`main` at `55f08ce` with the Sprint 29 planning PR and its amendments), in
the lane's own worktree (the Sprint 29 plan's Lane M, M1). The lane reports
what it deliberately did not update and why. A row whose reasoning has not
changed since the last report carries that reasoning again, so this report
reads on its own. Commits are named by subject, because the branch's
history is cleaned before the merge and hashes change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `dialyxir` (dev and test only), M1 | 1.4.8 → **1.4.9** | "chore(deps): dialyxir 1.4.9, dev and test only (M1)" | The only direct dependency `mix hex.outdated` reads as "Update possible". 1.4.9 changes two source files (`mix hex.package diff dialyxir 1.4.8..1.4.9`): `project.ex` fixes an operator-precedence slip, `dialyzer_config()[:plt_add_apps] || [] \|> load_apps()`, so a configured `plt_add_apps` list is now passed through `load_apps/1` (each app loaded before the PLT is read) instead of only the empty default; and `warnings/call_with_opaque.ex` accepts OTP 28's `{position, type, type_string}` triples for a call-with-opaque warning, where 1.4.8 expected bare positions, and drops a stray `}` from that warning's text. The rest of the diff is `hex_metadata.config` re-ordered by a newer Hex. No new dependency (`erlex >= 0.2.8`, unchanged). This repository sets `plt_add_apps: [:mix]`, so the first fix reaches it, but `:mix` is always loaded inside a Mix task, so loading it again changes nothing in the PLT; the second matters once an OTP 28 PLT is tried again (#727's OTP half, below). Never shipped (`only: [:dev, :test], runtime: false`). A lockfile change of one entry; `mix.exs` keeps `~> 1.4`. |
| The companion image's Node release, M1 | `node:26.13.0-alpine3.24@sha256:c6ad9e9c…` → **`node:26.13.1-alpine3.24@sha256:6bd9ab43…`** | "chore(node): the companion image runs Node 26.13.1, line 26's security release (M1)" | The Node release index marks **26.13.1** (2026-11-10 in the index, 2026-11-11 in Node's changelog) a **security release** of the LTS line "Lithium". Its changelog lists nine High fixes, among them "tls,http: prevent nested parser execution from empty writes" and a remotely reachable TLS server crash, plus llhttp 9.4.4 and undici 8.12.4; the companion image serves the MCP endpoint over plain HTTP (`PORTFOLIXIR_MCP_TRANSPORT=http`, port 4001) and calls the API with Node's `fetch` (undici), so the HTTP-parser and undici fixes reach the code the image runs. The last report kept the image on Dependabot's PR because "no security fix was read that forces it ahead"; this one is read, so the lane takes it rather than waiting for the bot's weekly run, which had opened nothing by 15:27 UTC. The digest is the multi-architecture index Docker Hub serves for the tag, `sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5`, the same at `mirror.gcr.io`; its amd64 image's config reads `NODE_VERSION=26.13.1` (built 2026-11-11). Both stages name it, as `ci_test` requires. CI's `node-version: "26"` already resolves to 26.13.1, so the companion's tests run on the release the image now carries. The image itself was not built here (no Docker in the session); CI's compose smoke test builds it and calls a tool through it. |

No other version moved in this lane: every candidate below is declined or
left to its Dependabot PR, each with its reason. Every row is its own
commit group, never mixed into a risk-tier story's commits (ADR-0036
clause 1).

## Dependabot

Read from GitHub's open pull requests at lane time (15:27 UTC; read only;
the lane comments on and closes nothing). One Dependabot PR is open:

- **#1392**, `floki` 0.38.4 → 0.38.5 (test only), from 2026-11-05: Sprint
  28's M1 took the same bump ("chore(deps): floki 0.38.5, test only (M1,
  Dependabot #1392)"), and the lockfile on `main` reads 0.38.5, so the PR
  changes nothing any more. **It can be closed**, as the Sprint 29 plan
  tells the owner; the lane does not close it.

No Dependabot PR has opened since #1407 (`lazy_html` 0.1.14, closed
2026-11-06). The bot's weekly run, due on 2026-11-12, had opened nothing by
lane time, so `playwright` 1.65.0, the database images' rebuilds and the
companion image's 26.13.1 (taken above) still had no PR of their own.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.4** | npm: `bmad-method` dist-tags are `latest` 6.12.4 (2026-10-14), `next` 6.12.3-next.1, `rollback` 4.39.0; the method repository's newest tag is v6.12.4 (`git ls-remote`). `main` has moved to `e435a22` (2026-11-12; the last report read `a867e16`), still the v7 preview: its `CHANGELOG.md` heads "Unreleased", and every module's `bmod.toml` reads `version = "6.13.0-next"` (`core-tools`, `method`, `toolsmith`, `founder`) | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261104, with its image** | Docker Hub: `debian:bookworm-20261104` and `-slim` (2026-11-05) are the newest dates; `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` and `-slim` are still the digests the branch pins (`ecb921d9…`, `01499334…`), and the runtime's `bookworm-20261104-slim` is still `734a72b3…` | **No** |
| **An Elixir 1.19 patch after 1.19.7, with its image** | builds.hex.pm's Elixir build list: `v1.19.7-otp-27` (2026-10-29) is the newest 1.19 | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm (`mix hex.outdated --all`): excoveralls 0.18.5 is still the newest release | **No** for 1.20 (newest 1.20.5, 2026-10-29; no 1.21 build exists). |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7 of Sprint 24) | hex.pm: `ecto` and `ecto_sql` read up to date in `mix hex.outdated --all` (3.14.3 and 3.14.0); no Elixir release since 1.19.7 / 1.20.5 | **No**. The trigger's own test was not re-run: neither Ecto nor Elixir moved since Sprint 24 ran it on OTP 28.5.0.8 (still the newest 28 patch; 29.1.2 the newest 29). `dialyxir` 1.4.9 (above) now formats OTP 28's opaque-call warnings, which makes the next run's output readable, but it does not reconcile the opaqueness itself, so it is no reason to re-run the test. |
| **A Node 26 security release after the image's** (read this time because the image moved) | the Node release index: 26.13.1 (2026-11-10, `security: true`) | **Yes.** Taken (above). |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279, closed 2026-11-01) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. No release after 3.2.0; unchanged since. |
| `websock_adapter`, `nimble_options` (transitive) | 0.6.0 (0.7.2), 1.1.1 (1.2.0) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. `websock_adapter` has moved from 0.7.1 to 0.7.2 since the last report; the reason holds. |
| npm (mcp-server) | every direct dependency at its newest | `npm outdated` lists nothing: `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2, `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7, `typescript` 7.0.2 (npm's `latest`; `beta` is 7.1.0-beta), `tsx` 4.23.15, `@types/express` 5.0.6, `@types/node` 26.6.6 (npm's `latest`; a `@types/node` major beyond the Node 26 runtime is ignored by Dependabot, #728). `npm audit` reports 0 vulnerabilities. |
| npm (test/browser) | `playwright` 1.64.1, pinned exactly (Sprint 24 M1) | `playwright` **1.65.0** is still `latest` (published 2026-11-05; `next` is a 1.66.0 alpha), and still no Dependabot PR for it. A test-only minor that also moves the Chromium CI's browser job installs: 1.64.1 installs Chromium revision 1248 (156.0.8078.4), 1.65.0 revision 1254 (158.0.8127.18, read from `playwright-core` 1.65.0's `browsers.json`). This session runs a preinstalled Chromium, revision 1243 (Chrome for Testing 153.0.8010.12), which matches neither, so a bump could not be verified here against the browser CI would run. Left to Dependabot's PR, whose CI browser job installs and verifies the new Chromium; no advisory forces it ahead. `npm audit` reports 0 vulnerabilities. |
| Elixir minors and majors (#727) | Elixir 1.19.7 (1.20.5 exists) | 1.20 stays blocked upstream: excoveralls 0.18.5 is still the newest release, and #727's Elixir half waits on one naming 1.20 cover support. |
| OTP 28 and 29 | OTP 27.3.4.19 (28.5.0.8 and 29.1.2 exist) | Waits on #727's OTP half (above): the Sprint 24 run of the trigger's own test was red, and nothing upstream that it depends on has moved since. An OTP 28 move also needs the `@issuers` change in `logo_lookup.ex`. |
| BMAD core v7 | 6.12.4 (`latest`) | No 6.13 or 7.x is published or tagged; v7 is the preview on `main` (now `e435a22`, versioned `6.13.0-next`). Its changelog lists breaking moves for this repository's layout (`planning_artifacts` and `implementation_artifacts` no longer read, a `bmad migrate method` step, advanced elicitation rebuilt with its `preferences` key renamed to `persistent_facts`, `bmad-spec` and `bmad-correct-course` replaced by a Product Owner agent), so the core move, `tea` and `bmb` majors stay one decision when a release ships (Sprint 24's M2, "When it comes back"). |
| BMAD `tea` v3.x and v4.x | v1.27.3 pinned (newest v4.0.0, 2026-11-06) | Unchanged since the last report: `main` is still the v4.0.0 release commit (`f54bf04`), npm's `latest` is 4.0.0, and v4.0.0 requires the unreleased `6.13.0-next` core, so it does not install through the pinned 6.12.4 installer. It belongs to the same v7 decision. The v1 line still ends at v1.27.3 (`c3d4f34`, the pinned commit), so there is no patch to re-pin. |
| BMAD `bmb` | v1.8.1 pinned (latest v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. The v7 preview's changelog still says the builder module "joins this repository as Toolsmith" (`bmod-toolsmith`), so in v7 `bmb` stops being an external module at all; the move belongs with the v7 core decision. The v1.8 line has no patch after v1.8.1 (`3410d95`, the pinned commit). |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag (`97298b2`), so there is nothing to take; `main` has commits after it (`658e710`), none of them released. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | The installer marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | Docker Hub's `18.6` index is still `e3d24f69…` (rebuilt 2026-11-06, as the last report read), PostgreSQL 18.6. It serves CI's test database only and ships in no image, no security fix was read that forces it, and Dependabot does not watch the workflow's `services:`, so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). |
| Compose's database image digest | `postgres:18.6-alpine3.24@sha256:10a5c69a…` | Docker Hub's `18.6-alpine3.24` index was rebuilt on 2026-11-11 and is now `9ba53c7d…` (the last report read `123b1799…`), the same PostgreSQL 18.6, rebuilt after Alpine 3.24.4 (Docker Hub, 2026-11-08). What 3.24.4 fixes was not read: alpinelinux.org and its security tracker were not reachable from this session. Dependabot watches the Compose files (tag and digest together), so the rebuild is taken by its PR; no security fix was read that forces it ahead, which is weaker evidence than last time because the release notes could not be read. |
| PostgreSQL major | 18 (`18.6`, by digest) | No 18.7 exists; Docker Hub's `19rc1` tags are a release candidate, not a release; the major is pinned (Dependabot ignores PostgreSQL majors, and a major needs a dump and a restore). |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.19.7, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261104-slim`; Node 26 in CI (the companion's `engines`
  say `>=26 <27`) and **26.13.1** in the companion's image with M1; every
  image pinned by digest. The OTP inside the build image was not read (no
  Docker in the session; the script says so); the tag names 27.3.4.19.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement); `dialyxir` is at 1.4.9 with M1; `mix hex.audit` and
  `mix deps.audit` report nothing; `mix deps.unlock --check-unused` is
  clean.
- **npm:** mcp-server has no direct dependency behind; test/browser's
  `playwright` is one minor behind (1.65.0); `npm audit` reports 0
  vulnerabilities in both.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`). Nothing moved.
- **Sources read:** hex.pm (through `mix`), registry.npmjs.org (through
  `npm`, including `playwright-core` 1.65.0's package for its browser
  revisions), builds.hex.pm, nodejs.org's release index, Node's
  `CHANGELOG_V26.md` on raw.githubusercontent.com, hub.docker.com,
  registry-1.docker.io and mirror.gcr.io (HTTPS), this repository's pull
  requests through GitHub's REST API (`gh api`, read only), and the BMAD
  repositories on github.com through `git ls-remote` and a shallow
  `git fetch` of the method repository's `main`. **Not read:** the BMAD
  release pages; Alpine's release notes and security tracker (blocked from
  the session); the `docker-library/postgres` history (not reachable
  through the session's GitHub access). `tea`'s v4.0.0 requirement is
  carried from the last report, since its `main` has not moved.
- **The local toolchain** of the cloud session that ran this lane is OTP 27
  with Elixir 1.19.7, the pinned pair; Node 22 (CI runs the companion on
  Node 26).

## Gate results on the lane's head

Run on the lane's head (the base plus the two M1 commits, before this
report's commit) on 2026-11-12, local toolchain Elixir 1.19.7 / OTP 27,
Node 22. Each exit status was read directly, never through a pipe. With a
dev-and-test lockfile entry and an image pin moved, the gates run are the
ones those can turn: `mix dialyzer` (the tool the bump changes), the
invariants, the tests that read the lockfile, the CI pins and the image
pins, the audits and the hooks. The full `mix test`, `mix coveralls` and
the browser job run at the sprint's integration, by the orchestrator.

| Gate | Result |
| --- | --- |
| `mix dialyzer --format short` (PLT built from scratch with 1.4.9) | exit 0: "Total errors: 0, Skipped: 0, Unnecessary Skips: 0", done (passed successfully); the PLTs had to be built, since the lane's worktree had none |
| `mix test test/invariants` | 298 tests, 0 failures |
| `mix test` on the files that read the lockfile, the CI and image pins and the BMAD install (`ci_test`, `dev_config_test`, `docs_test`, `workflow_docs_test`) | 134 tests, 0 failures |
| `mix format --check-formatted`, `mix compile --force --warnings-as-errors` | exit 0, exit 0 |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | exit 0, no retired or advisory packages |
| `mix deps.audit` | exit 0, no vulnerabilities |
| `npm audit --audit-level=high --prefix mcp-server` | exit 0, 0 vulnerabilities |
| `npm audit --audit-level=high --prefix test/browser` | exit 0, 0 vulnerabilities |
| `scripts/version-report.sh` | exit 0 (the OTP inside the build image not read: no Docker) |
| `pre-commit run --all-files` | exit 0, every hook passed (pre-commit 4.7.0) |
