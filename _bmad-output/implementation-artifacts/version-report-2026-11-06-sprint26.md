# Version Report — 2026-11-06 (Sprint 26 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, read with the sections of
`scripts/version-report.sh` (#676) **at lane time**, on the sprint branch
right after M1 (`render_cell` as HEEx and `sobelow` 0.18.1), in the lane's
own worktree (the Sprint 26 plan's Lane M, M2). The lane reports what it
deliberately did not update and why. A row whose reasoning has not changed
since the last report carries that reasoning again, so this report reads on
its own. Commits are named by subject, because the branch's history is
cleaned before the merge and hashes change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `sobelow` (dev, test), M1 | 0.16.0 → **0.18.1**, requirement floor `~> 0.18` | "refactor(securities): render_cell's badge, code and signed cells as HEEx, no raw/1 (M1)", "build(deps): sobelow 0.16.0 -> 0.18.1, the gate clean with no skip added (M1)" | Declined in Sprints 23 and 25 because 0.18.x flags four `XSS.Raw` findings in `securities_live.ex`'s `render_cell` clauses, so taking it needed four new skips (a weakened gate) or a rewrite into HEEx. M1 is the rewrite, pinned by a characterization test of each clause's markup, and then the bump: `mix sobelow --skip --exit` exits 0 with `.sobelow-skips` unchanged (D-1's criterion 4). **Dependabot #1391 (0.16.0 → 0.18.1) is superseded by it**; it can be closed once the sprint PR merges. |
| `lazy_html` (test only), M2, with `fine` (transitive) | `lazy_html` 0.1.13 → **0.1.14**; `fine` 0.1.6 → **0.2.0** | "build(deps): lazy_html 0.1.13 -> 0.1.14, with fine 0.1.6 -> 0.2.0 (M2)" | New this lane. The last two reports left it for Dependabot's PR "when it opens"; 0.1.14 was published on 2026-11-03, the bot's weekly Mix run on 2026-11-05 opened #1391 and #1392 but no PR for it, and none is open at lane time, so that route has not delivered it. Its whole diff (`mix hex.package diff lazy_html 0.1.13..0.1.14`) adds `:max_depth`, `:max_memory`, `:max_attributes` and `:timeout` options to `LazyHTML.from_document/2` and `from_fragment/2`, which "default to no limit", so no caller's behaviour changes; the NIF is the precompiled one (`lazy_html-nif-2.16-x86_64-linux-gnu-0.1.14`, checked against the package's `checksum.exs`). `fine` is the C++ NIF helper `lazy_html` 0.1.14 requires as `~> 0.2.0`; it is what kept `fine` at "Update not possible" in the last report. Test only: LiveView's test DOM, never shipped. A lockfile change of two lines; `mix.exs` keeps `>= 0.1.0`. |

Every row is its own commit group, never mixed into a risk-tier story's
commits (ADR-0036 clause 1).

## Dependabot

Read from GitHub's open pull requests at lane time (read only; the lane
comments on and closes nothing). Two Dependabot PRs are open, both from
2026-11-05:

- **#1391**, `sobelow` 0.16.0 → 0.18.1 (dev, test): **superseded by M1**,
  which makes the same move on the sprint branch together with the HEEx
  rewrite that keeps the gate clean without a skip. Taken alone, #1391
  would turn `mix sobelow --skip --exit` red on `main` (the four findings).
  It can be closed after the sprint PR's merge.
- **#1392**, `floki` 0.38.4 → 0.38.5 (test only). The plan names it the
  owner's merge (Sprint 26 plan, "What you need to do", item 4), so the lane
  does not take it ahead of the PR.

No Dependabot PR is open for `playwright` 1.65.0 (below): it was released
after the bot's 2026-11-05 run, so its PR is due at the next weekly run.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.4** | npm: `bmad-method` dist-tags are `latest` 6.12.4 (2026-10-14), `next` 6.12.3-next.1, `rollback` 4.39.0; the method repository's newest tag is v6.12.4 (`git ls-remote`), and `main` is still `022be93` (the v7 preview) | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261104, with its image** | Docker Hub: `debian:bookworm-20261104` and `-slim` (2026-11-05) are the newest dates; `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` and `-slim` are still the digests the branch pins (`ecb921d9…`, `01499334…`), and the runtime's `bookworm-20261104-slim` is still `734a72b3…` | **No** |
| **An Elixir 1.19 patch after 1.19.7, with its image** | builds.hex.pm's Elixir build list: `v1.19.7-otp-27` (2026-10-29) is the newest 1.19 | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm (`mix hex.outdated`): excoveralls 0.18.5 is still the newest release | **No** for 1.20 (newest 1.20.5, 2026-10-29). |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7 of Sprint 24) | hex.pm: `ecto` 3.14.3 and `ecto_sql` 3.14.0 are still the newest (`mix hex.outdated --all`); no Elixir release since 1.19.7 / 1.20.5 | **No**. The trigger's own test was not re-run: nothing upstream moved since Sprint 24 ran it on OTP 28.5.0.8 (still the newest 28 patch). |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `floki` (test only) | 0.38.4 (0.38.5; Dependabot #1392) | The owner's merge per the plan (above); a test-only patch is taken by Dependabot's PR, not ahead of it. |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. Unchanged since. |
| `websock_adapter`, `nimble_options` (transitive) | 0.6.0 (0.7.1), 1.1.1 (1.2.0) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. (`fine` moved with `lazy_html`, above.) |
| npm (mcp-server) | every direct dependency at its newest | `npm outdated` lists nothing: `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2, `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7, `typescript` 7.0.2, `tsx` 4.23.15, `@types/express` 5.0.6, `@types/node` 26.6.6 (npm's `latest`; a `@types/node` major beyond the Node 26 runtime is ignored by Dependabot, #728). `npm audit` reports 0 vulnerabilities. |
| The companion image's digest | `node:26.13.0-alpine3.24@sha256:c6ad9e9c…` | New this lane: Docker Hub's `26.13.0-alpine3.24` index is now `8996bb58…` (rebuilt 2026-11-05, confirmed by `mirror.gcr.io`'s `docker-content-digest`), still Node 26.13.0; no newer 26.x exists. Dependabot watches `/mcp-server`'s Dockerfile (tag and digest together), so the rebuild is taken by its PR; no security fix was read that forces it ahead. |
| npm (test/browser) | `playwright` 1.64.1, pinned exactly (Sprint 24 M1) | `playwright` **1.65.0** is `latest` (since 2026-11-05, after Dependabot's weekly run). A test-only minor that also moves the Chromium CI's browser job installs, which this session cannot reproduce (it runs a preinstalled Chromium); `test/browser` is watched by Dependabot weekly, so its PR is due at the next run and CI's browser job verifies the new Chromium there. `npm audit` reports 0 vulnerabilities. |
| Elixir minors and majors (#727) | Elixir 1.19.7 (1.20.5 exists) | 1.20 stays blocked upstream: excoveralls 0.18.5 is still the newest release, and #727's Elixir half waits on one naming 1.20 cover support. |
| OTP 28 and 29 | OTP 27.3.4.19 (28.5.0.8 and 29.1.2 exist) | Waits on #727's OTP half (above): the Sprint 24 run of the trigger's own test was red, and nothing upstream has moved since. An OTP 28 move also needs the `@issuers` change in `logo_lookup.ex`. |
| BMAD core v7 | 6.12.4 (`latest`) | No 6.13 or 7.x is published or tagged; v7 is the preview on `main` (`022be93`, unchanged). The core move, `tea` and `bmb` majors are one decision when a release ships (Sprint 24's M2, "When it comes back"). |
| BMAD `tea` v3.x and v4.x | v1.27.3 pinned (newest v4.0.0, 2026-11-06) | New this lane: v3.6.1 and **v4.0.0** were both tagged and published on npm on 2026-11-06. Neither changes Sprint 24's findings: v4.0.0's `skills/bmod-tea/bmod.toml` still requires `{ skill = "bmad", version = "6.13.0-next" }`, the unreleased v7 core, and has no `src/module.yaml` (HTTP 404 at the tag), so it does not install through the pinned 6.12.4 installer. 4.0.0 adds the `bmad setup` and `bmad migrate tea` path from 2.x and folds ATDD and CI settings into `bmad-tea-automate` and `bmad-tea-framework`; that belongs to the same v7 decision. The v1 line still ends at v1.27.3, so there is no patch to re-pin. |
| BMAD `bmb` | v1.8.1 pinned (latest v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. Read beside tea's: the move belongs with the v7 core decision. The v1.8 line has no patch after v1.8.1. |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag, so there is nothing to take. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | The installer marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | Docker Hub's `18.6` index is `bd5dfa49…` (rebuilt 2026-11-05, as the last report read), still PostgreSQL 18.6. It serves CI's test database only and ships in no image, no security fix was read that forces it, and Dependabot does not watch the workflow's `services:`, so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). |
| Compose's database image digest | `postgres:18.6-alpine3.24@sha256:10a5c69a…` | Docker Hub's `18.6-alpine3.24` index is now `123b1799…` (rebuilt again on 2026-11-06, after the `8a334ab9…` the last report read; confirmed by `mirror.gcr.io`), the same PostgreSQL 18.6. Dependabot watches the Compose files (tag and digest together), so the rebuild is taken by its PR, and no security fix was read that forces it ahead. |
| PostgreSQL major | 18 (`18.6`, by digest) | No 18.7 exists; Docker Hub has `19rc1` tags (rebuilt 2026-11-05 and 06), a release candidate, not a release; the major is pinned (Dependabot ignores PostgreSQL majors, and a major needs a dump and a restore). |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.19.7, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261104-slim`; Node 26 in CI (the companion's `engines`
  say `>=26 <27`); every image pinned by digest. The OTP inside the build
  image was not read (no Docker in the session); the tag names 27.3.4.19.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement) and `floki` (#1392); `mix hex.audit` and `mix deps.audit`
  report nothing; `mix deps.unlock --check-unused` is clean.
- **npm:** mcp-server has no direct dependency behind; test/browser's
  `playwright` is one minor behind (1.65.0); `npm audit` reports 0
  vulnerabilities in both.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`). Nothing moved.
- **Sources read:** hex.pm (through `mix`), registry.npmjs.org (through
  `npm`), builds.hex.pm, hub.docker.com and mirror.gcr.io (HTTPS), and the
  BMAD repositories on github.com through `git ls-remote` and
  raw.githubusercontent.com. GitHub's REST API was reachable for this
  repository's pull requests only; the BMAD repositories' API answered 403
  in this session, so their tags were read with `git ls-remote` instead,
  and their release pages were not read.
- **The local toolchain** of the cloud session that ran this lane is OTP 27
  with Elixir 1.19.7, the pinned pair.

## Gate results on the lane's head

Run on the lane's head (M1 and the `lazy_html` move, before this report's
commit) on 2026-11-06, local toolchain Elixir 1.19.7 / OTP 27, Node 22
(CI runs the companion on Node 26). Each exit status was read directly,
never through a pipe. The only Hex move in this lane is test-only, so the
tests run are the ones that render through LiveView's test DOM (all of
`test/portfolixir_web`) and the invariants; the full `mix test`, `mix
coveralls`, `mix dialyzer` and the browser job run at the sprint's
integration, by the orchestrator.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --force --warnings-as-errors` (dev and test) | exit 0 |
| `mix gettext.extract --check-up-to-date` | exit 0 |
| `mix test --max-cases 2 test/portfolixir_web test/invariants` on `lazy_html` 0.1.14 | 2905 tests, 0 failures |
| `mix test` on the files that read the lockfile, the CI pins and the BMAD install (`docs_test`, `workflow_docs_test`, `dev_config_test`, `ci_test`; `scope_b3_dependency_classes_test` and `advisory_fixed_releases_test` ran with the invariants) | 132 tests, 0 failures |
| `mix credo --strict` | exit 0 |
| `mix sobelow --skip --exit` | exit 0 (on 0.18.1, `.sobelow-skips` unchanged) |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | exit 0, no retired or advisory packages |
| `mix deps.audit` | exit 0, no vulnerabilities |
| `pre-commit run --all-files` | exit 0, every hook passed |
| `npm test --prefix mcp-server` | 288 tests, 0 failures |
| `npm run build --prefix mcp-server` | exit 0 |
| `npm audit --audit-level=high --prefix mcp-server` | exit 0, 0 vulnerabilities |
| `npm audit --audit-level=high --prefix test/browser` | exit 0, 0 vulnerabilities |
