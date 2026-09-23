# Version Report — 2026-09-23 (Sprint 14 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 14 plan's Lane M). The lane reports what it deliberately did
not update and why; a row whose reasoning is unchanged since the last report
carries that reasoning again rather than a cross-reference, so this report
reads on its own.

## Applied this batch

| What | From → to | Why now |
| --- | --- | --- |
| `@modelcontextprotocol/sdk` (mcp-server) | 1.30.0 → 1.30.1 | A patch inside the declared `^1.13.0` range. The SDK is the companion's whole protocol surface, so a patch behind on it is the wrong place to save a commit. `npm update` moved its lockfile entry and nothing else. |
| `tsx` (mcp-server, dev) | 4.23.13 → 4.23.15 | A patch inside `^4.19.0`; it is the companion's test runner, and the suite passes on it. Same commit as the SDK — both are one `npm update` of two patches. |
| MCP companion image | `node:24.20.0-alpine3.24` → `node:24.21.0-alpine3.24` | 24.21.0 (2026-09-07) is a semver-minor on the **Active LTS** line the runtime is pinned to. The major stays 24, so the four-place invariant (#728: CI `setup-node`, the image, `engines.node`, `@types/node`) holds and its test passes. **Not verified by an image build:** the lane's environment has no Docker daemon, and CI does not build the image either — the change is the tag edit Dependabot's docker ecosystem would otherwise open. |
| `phoenix_template` (transitive: phoenix, phoenix_live_view) | 1.0.4 → 1.1.0 | A minor inside both parents' `~> 1.0`. The changelog is additive — an `:html_formats` option, `locals_without_parens` exported for `embed_templates`, and a fix for warnings on recent Elixir versions — which is the kind of fix the toolchain move in #727 will want already in place. |
| `yaml_elixir` (transitive: mix_audit, dev/test) | 2.12.1 → 2.12.2 | A patch inside `mix_audit`'s `~> 2.11`; it parses the advisory database `mix deps.audit` reads. Same commit as `phoenix_template` — one `mix deps.update` of two transitive packages, two lines of `mix.lock`. |

Each lands as this lane's own commit, never mixed into a feature story
(ADR-0036 clause 1).

## Dependabot

No Dependabot PR is open for this lane at lane time. The Node 26 image bump
Sprints 11, 12 and 13 closed (#774, #782, #819) has not been reopened; its
trigger is re-checked below regardless, because it is a calendar event
Dependabot cannot see.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 (2026-08-14, already in the lock) and ecto_sql 3.14.0 are the newest releases; neither the ecto 3.14.2 changelog nor its unreleased 3.15.0-dev section, nor Elixir 1.20.4's (2026-08-28), carries an opaqueness or Dialyzer entry | **No** |
| **Node 26 LTS promotion (#728's pin)** | nodejs.org release index: 26.10.0 (2026-09-21) is still flagged **Current**, not LTS; 24.21.0 is the newest Active LTS (Krypton) | **No** — declined a fourth time, with the same reason: promotion is scheduled for October 2026, after this sprint closes. When it lands, the runtime moves in all four pinned places in one commit, together with the `@types/node` major that follows it. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Node runtime major | 24 (image `24.21.0-alpine3.24`) | Node 26 is **Current**, not LTS, until **October 2026**, and the runtime is pinned in four places by an invariant test (#728). The trigger is the LTS promotion; checked at lane time on 2026-09-23 and it has not landed. |
| `@types/node` major (mcp-server) | 24.13.6 (latest 26.6.2) | The types follow the pinned Node 24 runtime (Sprint 8 decision; the Dependabot ignore is major-wide). They move when the runtime moves, and moving them first would mean type-checking the companion against a runtime it does not run on. 24.13.6 is the newest 24.x. |
| Elixir / OTP (#727) | 1.18.3 / 27 | Both halves still blocked upstream (triggers above). The move also stays its own branch and PR: it moves the CI version pins, the Dockerfile base image and the Dialyzer PLT cache key together, and CI compiles with `--warnings-as-errors`, so two Elixir minors of deprecations become a body of work rather than a version-string edit. **See the security note below — this row has a new input this sprint.** |
| Dockerfile `HEX_VERSION` | 2.4.2 (latest 2.5.1) | The image pin reproduces the image; the advisory gate runs in CI against the current Hex release, so nothing this batch sits behind the pin. Not built locally either (no Docker daemon). |
| PostgreSQL image | `postgres:18-alpine` (CI `postgres:18`) | 18 is the current major (18.6 is its newest patch, which the floating `18-alpine` tag already resolves to). 19 exists only as `19beta3`; a beta is not a candidate for a self-hosted instance's data directory. |
| BMAD core/bmm | 6.11.0 (latest 6.12.0, 2026-09-04) | A minor of the installer and the core workflows this sprint's own planning, lanes and closing act run under. Moving it mid-batch would change the process the batch is being reviewed under; the lane re-pins between batches, never inside one. Candidate for the Sprint 15 lane. |
| BMAD `tea` | v1.19.0 pinned (latest tag v1.27.2) | Same reason as core — and eight minors is a re-install with a read of what changed in the test-architecture workflows, not a pin edit. Candidate for the Sprint 15 lane. |
| BMAD `cis` | v0.2.1 pinned (latest tag v0.3.2) | Same reason; a 0.x minor may break. Candidate for the Sprint 15 lane. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2) | A **major** behind. Same between-batches rule, plus a major needs its own read. |
| BMAD `automator` | `main` at `0b94fd7` | Current: the recorded SHA is the head of `main`. Nothing to move. |

BMAD versions were read from the public npm registry (`bmad-method`) and the
modules' public git tags; the GitHub API for those repositories is not reachable
from the lane's session, so release dates for the modules were not checked.

## Security note: CVE-2026-75758 on the pinned Elixir line

Elixir **1.18.5**, **1.19.6** and **1.20.4** (all 2026-08-28) fix
CVE-2026-75758 (GHSA-jf5q-v438-665c): unbounded recursion when an *invalid*
charlist is passed to `List.to_string/1` or `List.to_charlist/1`. The tree pins
**1.18.3**, which is affected. Neither `mix hex.audit` nor `mix deps.audit`
reports it — both audit Hex packages, not the language runtime — so no gate in
this project can see it.

Why it is recorded rather than applied in this lane:

- **Reachability, measured:** every `List.to_string/1` / `to_charlist` call in
  `lib/` takes a charlist the code itself built from a binary (`String.to_charlist/1`
  or `Kernel.to_charlist/1` on a string), so no call site hands the functions an
  externally shaped charlist. The trigger condition is not reachable from input
  on today's code.
- **The four places cannot move together on a patch:** the official `elixir`
  Docker image has **no 1.18.5 tag** (the 1.18 line stops at 1.18.4 there), so
  a patch bump would split CI (setup-beam can fetch 1.18.5) from the Dockerfile,
  which is exactly what #727 says must not happen. Closing the gap therefore
  means either a 1.19.6 move or an image-source change — both decisions, not
  maintenance.
- **Local evidence would be the wrong evidence:** #727's own history records a
  "green locally" claim on a toolchain CI did not run; a runtime bump is proven
  on CI, on its own branch.

Recommended as input to #727's next re-check, not as a new trigger: the
advisory is a reason to weigh a 1.19.x step (which has official images) against
waiting for the 1.20 cover fix.

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.3, OTP 27,
  `elixir:1.18.3-otp-27`, `postgres:18-alpine` (CI `postgres:18`), Node 24
  (`node:24.21.0-alpine3.24` after this lane).
- **Hex:** 21 direct dependencies, all *Up-to-date*; after the two transitive
  updates `mix hex.outdated --all` reports nothing outdated. `mix hex.audit`
  reports no retired packages and no advisories; `mix deps.audit` finds no
  vulnerabilities. `mix deps.unlock --check-unused` reports no unused entries.
- **npm (mcp-server):** `npm audit` finds 0 vulnerabilities at any level. One
  outdated package, `@types/node`, held at 24.x on purpose (above).
- **BMAD install:** manifest 6.11.0 with the four external modules at the SHAs
  the report script lists.

## Gate results on the lane's head

Run on the tree carrying all three update commits, local toolchain Elixir
1.18.3 / OTP 27.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` (dev and test) | clean |
| `mix test` | 2418 tests, 8 properties, 0 failures |
| `mix coveralls` | 91.7 % total; green on a clean run (see the note below) |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 |
| `mix dialyzer --format short` | passed successfully, no warnings |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `npm test --prefix mcp-server` | 89 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |

Two caveats, stated so they are not mistaken for coverage.

**Suite stability under host load.** The full suite and one `mix coveralls`
run were green. Three further `mix coveralls` runs on the same tree failed 2,
9 and 28 tests — every failure a `DBConnection.ConnectionError` (pool checkout
dropped from the queue after roughly 100–300 ms, or a sandbox owner exiting), taken while the host's load average
sat near 30 on four cores from other lanes running their suites in parallel.
Nothing in the updates touches the database path, and a run that is not
starved passes, so this is recorded as an environment effect rather than a
regression. It is still a real property of the suite: its sandbox timeouts are
tight enough that host contention reads as test failure. CI, on a runner of its
own, is the authoritative run.

**Node version.** The local Node is 22,
not the pinned 24, so the companion's gates above ran on an older runtime than
CI's. CI's `setup-node` step (Node 24) is the authoritative run for them.
