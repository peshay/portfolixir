# Version Report — 2026-11-07 (Sprint 27 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, read with the sections of
`scripts/version-report.sh` (#676) **at lane time**, on the sprint's base
(`main` with the Sprint 27 planning PR and the owner's triage of
2026-11-07), in the lane's own worktree (the Sprint 27 plan's Lane M, M1).
The lane reports what it deliberately did not update and why. A row whose
reasoning has not changed since the last report carries that reasoning
again, so this report reads on its own. Commits are named by subject,
because the branch's history is cleaned before the merge and hashes change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `saxy` (new), taken in N1 | TODO(orchestrator): the version N1 locks, and its requirement in `mix.exs` | see N1's commit | The news parser's dependency (Sprint 27 plan D-7): `saxy` in SAX mode, because it builds no atoms, streams, and lets the handler stop at the first depth or count breach; **not** `xmerl`, which makes atoms from names by default. Lane N's N1 (a separate story) takes it, audits it and pins it in its own commit, and registers it in the dependency-class backstop (`scope_b3_dependency_classes_test.exs`). TODO(orchestrator): the audit facts (the package's own dependencies, `mix hex.audit` and `mix deps.audit` on the locked version, its licence, and the backstop's entry), filled in when N1 is integrated. |

No other version moved in this lane: every candidate below is declined or
left to its Dependabot PR, each with its reason. Every row is its own
commit group, never mixed into a risk-tier story's commits (ADR-0036
clause 1); `saxy` lands inside Lane N's commit group because the parser is
the reason it exists, and this table is where it is accounted for.

## Dependabot

Read from GitHub's open pull requests at lane time (read only; the lane
comments on and closes nothing). The same two Dependabot PRs as at the last
report are open, both from 2026-11-05, and none has opened since:

- **#1391**, `sobelow` 0.16.0 → 0.18.1 (dev, test): **superseded** by Sprint
  26's M1, which made the same move on `main` (the lockfile has 0.18.1, and
  `mix hex.outdated` reads it up to date). It can be closed; the Sprint 27
  plan asks the owner to (its "What you need to do", item 3).
- **#1392**, `floki` 0.38.4 → 0.38.5 (test only). The plan names it the
  owner's merge (same item), so the lane does not take it ahead of the PR.

#1407 (`lazy_html` 0.1.14) was closed on 2026-11-06, taken by Sprint 26's
M2. No Dependabot PR is open for `playwright` 1.65.0 or for the image
rebuilds below: each came after the bot's weekly run of 2026-11-05, so
their PRs are due at the next run.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.4** | npm: `bmad-method` dist-tags are `latest` 6.12.4 (2026-10-14), `next` 6.12.3-next.1, `rollback` 4.39.0; the method repository's newest tag is v6.12.4 (`git ls-remote`). `main` has moved to `e734d3a` (2026-11-06; the last report read `022be93`), still the v7 preview: its `CHANGELOG.md` heads "Unreleased", and every `skills/bmod-*/bmod.toml` reads `version = "6.13.0-next"` | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261104, with its image** | Docker Hub: `debian:bookworm-20261104` and `-slim` (2026-11-05) are the newest dates; `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` and `-slim` are still the digests the branch pins (`ecb921d9…`, `01499334…`), and the runtime's `bookworm-20261104-slim` is still `734a72b3…` | **No** |
| **An Elixir 1.19 patch after 1.19.7, with its image** | builds.hex.pm's Elixir build list: `v1.19.7-otp-27` (2026-10-29) is the newest 1.19 | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm (`mix hex.outdated`): excoveralls 0.18.5 is still the newest release | **No** for 1.20 (newest 1.20.5, 2026-10-29). |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7 of Sprint 24) | hex.pm: `ecto` and `ecto_sql` read up to date in `mix hex.outdated --all` (3.14.3 and 3.14.0); no Elixir release since 1.19.7 / 1.20.5 | **No**. The trigger's own test was not re-run: nothing upstream moved since Sprint 24 ran it on OTP 28.5.0.8 (still the newest 28 patch). |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `floki` (test only) | 0.38.4 (0.38.5; Dependabot #1392) | The owner's merge per the plan (above); a test-only patch is taken by Dependabot's PR, not ahead of it. |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279, closed 2026-11-01) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. Unchanged since. |
| `websock_adapter`, `nimble_options` (transitive) | 0.6.0 (0.7.1), 1.1.1 (1.2.0) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. Unchanged since. |
| npm (mcp-server) | every direct dependency at its newest | `npm outdated` lists nothing: `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2, `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7, `typescript` 7.0.2, `tsx` 4.23.15, `@types/express` 5.0.6, `@types/node` 26.6.6 (npm's `latest`; a `@types/node` major beyond the Node 26 runtime is ignored by Dependabot, #728). `npm audit` reports 0 vulnerabilities. |
| The companion image's digest | `node:26.13.0-alpine3.24@sha256:c6ad9e9c…` | Docker Hub's `26.13.0-alpine3.24` index is still `8996bb58…` (rebuilt 2026-11-05, confirmed again by `mirror.gcr.io`'s `docker-content-digest`), Node 26.13.0; no 26.14 exists. Dependabot watches `/mcp-server`'s Dockerfile (tag and digest together), so the rebuild is taken by its PR at the next weekly run; no security fix was read that forces it ahead. |
| npm (test/browser) | `playwright` 1.64.1, pinned exactly (Sprint 24 M1) | `playwright` **1.65.0** is still `latest` (since 2026-11-05, after Dependabot's weekly run; `next` is a 1.66.0 alpha). A test-only minor that also moves the Chromium CI's browser job installs, which this session cannot reproduce (it runs a preinstalled Chromium); `test/browser` is watched by Dependabot weekly, so its PR is due at the next run and CI's browser job verifies the new Chromium there. `npm audit` reports 0 vulnerabilities. |
| Elixir minors and majors (#727) | Elixir 1.19.7 (1.20.5 exists) | 1.20 stays blocked upstream: excoveralls 0.18.5 is still the newest release, and #727's Elixir half waits on one naming 1.20 cover support. |
| OTP 28 and 29 | OTP 27.3.4.19 (28.5.0.8 and 29.1.2 exist) | Waits on #727's OTP half (above): the Sprint 24 run of the trigger's own test was red, and nothing upstream has moved since. An OTP 28 move also needs the `@issuers` change in `logo_lookup.ex`. |
| BMAD core v7 | 6.12.4 (`latest`) | No 6.13 or 7.x is published or tagged; v7 is the preview on `main` (now `e734d3a`, versioned `6.13.0-next`). Its changelog lists breaking moves for this repository's layout (`planning_artifacts` and `implementation_artifacts` no longer read, a `bmad migrate method` step, `bmad-spec` and `bmad-correct-course` replaced by a product-owner agent), so the core move, `tea` and `bmb` majors stay one decision when a release ships (Sprint 24's M2, "When it comes back"). |
| BMAD `tea` v3.x and v4.x | v1.27.3 pinned (newest v4.0.0, 2026-11-06) | Unchanged since the last report: `main` is still the v4.0.0 release commit (`f54bf04`), npm's `latest` is 4.0.0, and v4.0.0's `skills/bmod-tea/bmod.toml` still requires the unreleased `6.13.0-next` core, so it does not install through the pinned 6.12.4 installer. It belongs to the same v7 decision. The v1 line still ends at v1.27.3, so there is no patch to re-pin. |
| BMAD `bmb` | v1.8.1 pinned (latest v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. New this lane: the v7 preview's changelog says the builder module "joins this repository as Toolsmith" (`bmod-toolsmith`, one agent and `bmad-eval`), so in v7 `bmb` stops being an external module at all; one more reason the move belongs with the v7 core decision. The v1.8 line has no patch after v1.8.1. |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag, so there is nothing to take. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | The installer marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | Docker Hub's `18.6` index is now `e3d24f69…` (rebuilt 2026-11-06, after the `bd5dfa49…` the last report read; confirmed by `mirror.gcr.io`), still PostgreSQL 18.6. It serves CI's test database only and ships in no image, no security fix was read that forces it, and Dependabot does not watch the workflow's `services:`, so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). |
| Compose's database image digest | `postgres:18.6-alpine3.24@sha256:10a5c69a…` | Docker Hub's `18.6-alpine3.24` index is still `123b1799…` (rebuilt 2026-11-06, as the last report read; confirmed by `mirror.gcr.io`), the same PostgreSQL 18.6. Dependabot watches the Compose files (tag and digest together), so the rebuild is taken by its PR, and no security fix was read that forces it ahead. |
| PostgreSQL major | 18 (`18.6`, by digest) | No 18.7 exists; Docker Hub has `19rc1` tags (rebuilt again on 2026-11-06), a release candidate, not a release; the major is pinned (Dependabot ignores PostgreSQL majors, and a major needs a dump and a restore). |

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
  report nothing; `mix deps.unlock --check-unused` is clean. `saxy` arrives
  with N1 (above).
- **npm:** mcp-server has no direct dependency behind; test/browser's
  `playwright` is one minor behind (1.65.0); `npm audit` reports 0
  vulnerabilities in both.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`). Nothing moved.
- **Sources read:** hex.pm (through `mix`), registry.npmjs.org (through
  `npm`), builds.hex.pm, hub.docker.com and mirror.gcr.io (HTTPS), this
  repository's open pull requests through GitHub's REST API (`gh api`, read
  only), and the BMAD repositories on github.com through `git ls-remote` and
  shallow `git fetch` of `main` (the method and `tea` repositories).
  raw.githubusercontent.com answered 404 for the method repository's
  `main:package.json` (the v7 tree has none; its version lives in the
  `bmod.toml` files), so that tree was read from the fetch instead; the
  BMAD release pages were not read.
- **The local toolchain** of the cloud session that ran this lane is OTP 27
  with Elixir 1.19.7, the pinned pair.

## Gate results on the lane's head

Run on the lane's base (no Hex or npm move in this lane, before this
report's commit and before N1's `saxy` lands) on 2026-11-07, local
toolchain Elixir 1.19.7 / OTP 27, Node 22 (CI runs the companion on Node
26). Each exit status was read directly, never through a pipe. With no bump
taken, the gates run are the ones a dependency picture can turn: the
invariants, the tests that read the lockfile, the CI pins and the BMAD
install, the audits and the hooks. The full `mix test`, `mix coveralls`,
`mix dialyzer` and the browser job run at the sprint's integration, by the
orchestrator, on a lockfile that includes `saxy`.

| Gate | Result |
| --- | --- |
| `mix test test/invariants` (with `scope_b3_dependency_classes_test`, `advisory_fixed_releases_test` and `mcp_dependency_allowlist_test`) | 276 tests, 0 failures |
| `mix test` on the files that read the lockfile, the CI pins and the BMAD install (`docs_test`, `workflow_docs_test`, `dev_config_test`, `ci_test`) | 132 tests, 0 failures |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | exit 0, no retired or advisory packages |
| `mix deps.audit` | exit 0, no vulnerabilities |
| `npm audit --audit-level=high --prefix mcp-server` | exit 0, 0 vulnerabilities |
| `npm audit --audit-level=high --prefix test/browser` | exit 0, 0 vulnerabilities |
| `pre-commit run --all-files` | exit 0, every hook passed (pre-commit 4.7.0 from CI's hash-pinned `.github/pre-commit/requirements.txt`, installed into a scratch environment because the session had none) |
