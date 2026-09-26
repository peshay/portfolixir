# Version Report — 2026-09-26 (Sprint 16 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 16 plan's Lane M). The lane reports what it deliberately did
not update and why. A row whose reasoning has not changed since the last report
carries that reasoning again rather than a cross-reference, so this report
reads on its own. From this report on, the OTP inside the release's build image
is its own row, as the plan asked after the 2026-09-24 runtime hotfix.

## Applied this batch

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| BMAD core and method (`bmad-method`) | 6.11.0 → 6.12.0 | `0b6bd7f`, the branch's first commit | Deferred by Sprint 15 to the opening of this branch, so no batch is reviewed under a process that changed halfway. Run through the official installer with the module set and target the manifest records. |
| BMAD `tea` | v1.19.0 → v1.27.2 (pinned tag) | `0b6bd7f` | Rode the opening re-pin, as Sprint 15 planned. v1.27.2 is still the newest tag. |
| BMAD `cis` | v0.2.1 → v0.3.2 (pinned tag) | `0b6bd7f` | Same. v0.3.2 is still the newest tag. |
| `lazy_html` (test only) | 0.1.12 → 0.1.13 | `70d5d74` | EEF-CVE-2026-92106 (low) was published against 0.1.12 on 2026-09-25 and turned CI's `hex.audit` gate red. It is LiveView's test DOM parser, so no shipped build carried it. |
| `hpax` (transitive) | 1.0.4 → 1.1.0 | `9eaaca6` | A hardening release of the HPACK codec Mint and Bandit use (plan, Lane M). |
| Compose and companion images by digest (E25 S2, F25) | tags → exact tag plus `sha256` digest | `c72b88e` | `postgres:18.6-alpine3.24@sha256:77f58511…` in both Compose files; the MCP companion's base `node:24.21.0-alpine3.24@sha256:ebfe2f90…`. Dependabot gained the `docker-compose` ecosystem, which moves tag and digest together and never proposes a PostgreSQL major. |
| CI service images and toolchains (E25 S8, F60) | tags → digest; unchecked downloads → SHA-256 | `a17c3fa` | CI's database service is `postgres:18.6@sha256:5a5a84b1…` in both jobs; both stages of the MCP image name the Node base by digest; the agent install script refuses an OTP or Elixir archive whose SHA-256 does not match. S8's other supply-chain commits: pre-commit installed by hash and its hooks by commit (`015b448`, `467a6bb`), the MCP image and install run no dependency scripts (`55d7cfb`). |
| Codecov project target (#314) | 85 % → 90 % | `2fab181` | The next ratchet step, confirmed against the current figure first (below). The stale comment in `codecov.yml` now states this step. |
| Credo complexity ceiling (#314) | 15 → 13 | `ef6a0c0` | The two functions at 15 were split without a change in behaviour; the rest of the grandfathered debt is reported below, not forced. |

Every row is its own commit or commit group, never mixed into a feature story
(ADR-0036 clause 1).

Context, not this lane: the runtime hotfix (Lane H, #880) moved Elixir 1.18.3 →
1.18.5 on OTP 27.3.4.18 (`b510d72`) on `main` before this branch opened. That
closes Sprint 14's CVE-2026-75758 row, which earlier reports carried.

## #314: the figure and the second half

- **The figure the target was checked against.** `mix coveralls` on the
  branch, after the S7 review round: **93.5 %** total. Codecov reported
  about 93.7 % on the batch's pull request. The 90 % floor keeps some 3.5
  points of headroom, and the patch target (90 % of changed lines) and the 1 %
  threshold stay as they were. The maintainer's 2026-06-11 rule still bounds
  the ratchet: it stops where assertions stay meaningful.
- **Credo, measured with `mix credo --strict` at each candidate threshold:**

  | Check | Now | Next step would need |
  | --- | --- | --- |
  | `CyclomaticComplexity` | 13 (was 15) | 12: `PortfolioPerformance.map_asset_class/2` (13). 10: seven functions. 9, the default: twelve. |
  | `Nesting` | 4 (unchanged) | 3: ten offenders. 2, the default: sixty-seven. |

  The step taken is the one that needed no judgement: two functions split into
  helpers, the path and the labels they produce unchanged, and `ImportsLive`'s
  thirteen-branch label switch replaced by `PortfolixirWeb.TransactionKindLabel`,
  which already held the same labels. Each further step is a refactor of
  logic-bearing code and belongs to its own story, as #314 says; the
  grandfather comment in `.credo.exs` stays until the defaults are reached.

## Dependabot

Two Dependabot PRs are open at lane time, both against `main`:

- **#882, `node` 24.21.0 → 26.9.0 in `/mcp-server`:** declined again, for the
  reason in the table below. Node 26 is not an LTS release yet.
- **#881, `codecov/codecov-action` 7.1.0 → 7.1.1:** a patch release of a CI
  action. It is not taken on this branch. Dependabot PRs are reviewed and
  merged by the maintainer like any dependency PR, never folded into a batch,
  and this one changes nothing the batch's gates depend on.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release (`mix hex.outdated --all`: up to date) | **No** |
| **#727, OTP half:** an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 and ecto_sql 3.14.0 are still the newest releases, both already in the lock; the newest Elixir builds are still 1.20.4 and 1.19.6 (both 2026-08-28, builds.hex.pm) | **No** |
| **Node 26 LTS promotion (#728's pin)** | nodejs.org release index: 26.10.0 (2026-09-21) is still **Current**, not LTS; 24.21.0 (2026-09-07) is still the newest Active LTS (Krypton) and is what the image runs | **No.** The promotion is scheduled for **2026-10-28**, after this sprint. When it lands, the runtime moves in all four pinned places in one commit, with the `@types/node` major that follows it. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP minors and majors (#727) | Elixir 1.18.5 / OTP 27.3.4.18 | Both halves are still blocked upstream (triggers above). The move stays its own branch and PR: it moves the CI version pins, the Dockerfile base images and the Dialyzer PLT cache key together, and CI compiles with `--warnings-as-errors`, so two Elixir minors of deprecations are a body of work rather than a version-string edit. The hotfix's move to 1.18.5 was a patch within the pinned minor and needed neither trigger. |
| Node runtime major | 24 (`node:24.21.0-alpine3.24`, by digest) | Node 26 is **Current**, not LTS, until **2026-10-28**, and the runtime is pinned in four places by an invariant test (#728). Dependabot's #882 is declined for the same reason. |
| `@types/node` (mcp-server) | 24.13.6 (24.19.0 in range, 26.6.3 latest) | The major follows the pinned Node 24 runtime (Sprint 8 decision; the Dependabot ignore is major-wide). A newer 24.x, 24.19.0, has appeared since Sprint 15's report. It is not taken in this lane: the plan's Lane M did not name it, and it goes to the next lane. |
| `phoenix` | 1.8.14 (1.8.15 published 2026-09-25) | Published a day after the plan fixed this lane's list. It is a patch of the web framework, and it is not added to the batch hours before the closing act; it goes to the next lane. |
| Dockerfile `HEX_VERSION` | 2.4.2 (local Hex 2.5.1) | The image pin reproduces the image. The advisory gates run in CI against the current Hex, so nothing in this batch sits behind the pin. |
| PostgreSQL major | 18 (`18.6`, by digest) | 18.6 is still the newest 18 patch (Docker Hub has no 18.7). 19 exists only as **19beta4** (tagged 2026-09-25), and a beta is not a candidate for a self-hosted instance's data directory. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2) | A **major** behind. The between-batches rule applies, plus a read of the major's changes; that is its own decision, not part of the opening re-pin. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | Still the head of `main` (`git ls-remote`); the newest tag is `v1.15.0-next.1`. BMAD 6.12.0's registry marks the module **deprecated in favour of `bmad-loop`** (the re-pin commit records it). Recorded, not acted on: replacing the automator changes how stories are run, which is a process decision for the owner, not a version bump. |

## The OTP inside the release's build image

| Row | Value |
| --- | --- |
| Build image (`Dockerfile.release`, stage `build`) | `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918-slim@sha256:ada1bbb1…` |
| `OTP_VERSION` read from inside that image | **27.3.4.18** |
| CI's `otp-version` pin | 27.3.4.18 |

They agree: every instance built from this tree runs the OTP CI tests. The
script started the image with `docker run` and read the file the release
bundles. This session's Docker daemon pulled the image straight from Docker Hub,
without the rate limit Sprint 15 met.

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.5, OTP 27.3.4.18. The
  development image and the release's build stage use
  `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918` (the build
  stage the `-slim` variant); the runtime stage uses
  `debian:bookworm-20260918-slim`; all three are pinned by digest. The database
  is `postgres:18.6-alpine3.24` in Compose and `postgres:18.6` in CI, both by
  digest. Node 24: `node:24.21.0-alpine3.24` by digest, and `node-version: "24"`
  in CI.
- **Hex:** every dependency is *Up-to-date* except `phoenix` (above).
  `mix hex.audit`: no retired packages, no advisories. `mix deps.audit`: no
  vulnerabilities. `mix deps.unlock --check-unused`: no unused entries.
- **npm (mcp-server):** `npm audit`: 0 vulnerabilities at any level. One
  outdated package, `@types/node` (above).
- **BMAD install:** manifest 6.12.0; core and bmm 6.12.0, tea v1.27.2 (pinned,
  `d99ad29`), cis v0.3.2 (pinned, `97298b2`), automator `main` (`0b94fd7`), bmb
  v1.8.1 (pinned, `3410d95`).

## Gate results on the lane's head

Run on the branch carrying every lane so far plus the S7 review round and this
lane's commits. Local toolchain: Elixir 1.18.5 / OTP 27.3.4.18.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` (dev and test) | clean |
| `mix test`, PostgreSQL 16 | 3258 tests, 9 properties, 0 failures |
| `mix test`, PostgreSQL 18 (as CI runs it) | 3258 tests, 9 properties, 0 failures |
| `mix coveralls` | 93.5 % total (run after the S7 review round, before this lane's `hpax`, Codecov and Credo commits) |
| `mix credo --strict` | no issues, at the new complexity ceiling of 13 |
| `mix sobelow --skip --exit` | exit 0 |
| `mix dialyzer --format short` | 0 errors, passed successfully |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 150 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |

**Node version.** The local Node is 22, not the pinned 24, so the companion's
gates above ran on an older runtime than CI's. CI's `Setup Node` step (Node 24)
is the authoritative run for them and for the npm audit.
