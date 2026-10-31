# Version Report — 2026-10-31 (Sprint 21 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before Lane S's closing
act (the Sprint 21 plan's Lane M; the amendment of 2026-10-27, D-7). The lane
reports what it deliberately did not update and why. A row whose reasoning
has not changed since the last report carries that reasoning again rather
than a cross-reference, so this report reads on its own. Commits are named by
subject, because the branch's history is cleaned before the merge and hashes
change. The lane ran across three sessions (2026-10-27 to 2026-10-31) because
the account's usage limit stopped the build twice; the upstream checks below
are the last session's, of 2026-10-31.

## Applied this lane

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `phoenix` | 1.8.15 → 1.8.16 | "chore(deps): phoenix 1.8.15 -> 1.8.16" | Dependabot #1237 (published 2026-10-20), taken as D-7 orders, with the full check list. A patch release inside `~> 1.8`; lock only. |
| `phoenix_live_view`, and `elixir_make` under it | 1.2.12 → 1.2.13; 0.10.0 → 0.10.1 | "chore(deps): phoenix_live_view 1.2.12 -> 1.2.13, elixir_make 0.10.0 -> 0.10.1" | Dependabot #1235 (1.2.13 published 2026-10-20). The lock move pulled `elixir_make` 0.10.1 (2026-10-24) with it, which Dependabot's own PR carries too, so the commit mirrors the PR. `websock_adapter` 0.7.0 came along in a first resolution and was reverted to 0.6.0 (below), so the commit moves exactly what the PR moves. |
| `pre-commit` (the pinned hook requirements group) | 4.6.2 → 4.7.0 | "chore(ci): pre-commit 4.6.2 -> 4.7.0 in the pinned hook requirements" | Dependabot #1233 (PyPI 2026-10-12), the pre-commit group D-7 names. |
| Node runtime major, in the four pinned places, with `@types/node` | 24 → 26 (`node:26.12.0-alpine3.24`, `engines.node >=26 <27`, CI's `node-version: "26"` in both companion jobs, `ci_test`'s pin); `@types/node` 24.19.1 → 26.6.5 | "chore(node): the companion runs on Node 26 in all four pinned places, with @types/node 26" | Sprint 20's report deferred Node 26 to the first sprint running on or after **2026-10-28**, its LTS date; this build ran on it (D-7). One commit across the four places, as the pin rule asks (#728), with the `@types/node` major that follows the runtime (the Sprint 8 decision). Dependabot #1234 (26.12.0) and #1232 (`@types/node` 24.19.2) close with it. The docs name Node 26 where they named 24 (README, the guides, `llms.txt`), and `dependabot.yml`'s `@types/node` ignore moves to the new major. |
| The companion image's Node release | 26.12.0 → 26.13.0 (`node:26.13.0-alpine3.24`, by digest) | "chore(node): the companion image runs Node 26.13.0, the release that opened line 26's LTS" | Dependabot #1234 proposed 26.12.0 on 2026-10-23, a Current release; the Node release index marks **26.13.0 (2026-10-28)** as the first LTS release of line 26 (codename Lithium, maintenance from 2027-10-20, end of life 2029-04-30). The image follows the promoted release, as CI's `node-version: "26"` resolves to it already. The digest is the tag's index digest read from Docker Hub. |
| `bandit` | 1.14.0 → 1.14.1 | "chore(deps): bandit 1.14.0 -> 1.14.1" | A new advisory turned `mix hex.audit` red on the branch with nobody pushing (GHSA-pxjf-g536-7r93, published with 1.14.1 on 2026-10-28). T-11's hotfix had moved the lock to 1.14.0 two days earlier; the lane takes the fix release, as the lanes take every advisory. Lock only. |
| `express` (the companion) | 5.2.1 → 5.3.0 | "chore(deps): express 5.2.1 -> 5.3.0 in the companion" | Dependabot #1230 (published 2026-10-09). The amendment's count of open Dependabot PRs named five; eight were open (below), and the lane's rule since Sprint 16 is that no Dependabot PR remains neither taken nor declined with a reason. A minor inside `^5`, moving `package.json`'s range to `^5.3.0` as the PR does; `content-disposition` 2.0.1 and `content-type` 2.1.0 come with it. The companion's tests and build are green under it; the schema budget does not read it. |
| `@hono/node-server` (transitive, under the MCP SDK) | 2.1.0 → 2.1.5 | "chore(deps): @hono/node-server 2.1.0 -> 2.1.5 under the MCP SDK" | `npm audit` reported one moderate advisory (GHSA-rmxm-3fg6-px4f: `serveStatic` decodes a request path twice), below CI's `--audit-level=high`, so the gate stayed green. The lanes take a transitive npm entry for an advisory (`ip-address` in Sprint 16, `fast-uri` in Sprint 17, `proxy-addr` in Sprint 19), not for drift; neither the companion's own code nor the SDK's distributed code calls `serveStatic`, so nothing in it fixes a defect the app has met. Lock only; `npm audit` reports 0 vulnerabilities at any level afterwards. |
| `actions/setup-node`, `actions/upload-artifact` | 7.0.0 → 7.1.0; 7.0.1 → 7.0.2 | "chore(ci): actions/setup-node 7.0.0 -> 7.1.0, actions/upload-artifact 7.0.1 -> 7.0.2" | Dependabot #1228 and #1227 (2026-10-16). Both stay pinned by the tag's commit, with the version in a comment; each digest was read from the action's own tag (`git ls-remote`) and matches the PR's. `setup-node` moves in both places the workflow uses it: Lane S's H63 row moved the live-feed audits into a job of their own, which sets up Node too, after the PR was opened, so the PR's one-line diff would have left the second pin behind. |
| `@modelcontextprotocol/sdk` (the companion) | 1.32.1 → 1.32.2 | "chore(deps): @modelcontextprotocol/sdk 1.32.1 -> 1.32.2 in the companion" | Dependabot #1281, from its run of 2026-10-30 (the package was published on 2026-10-23, the day of the previous run). A patch inside `^1.13.0`, lock only; the companion's tests, build and schema budget are unchanged by it. |
| `actions/setup-python` | 7.0.0 → 7.1.0 | "chore(ci): actions/setup-python 7.0.0 -> 7.1.0" | Dependabot #1282 (2026-10-30), pinned by the tag's commit, read from the action's own tag. |
| `phoenix_html` | 4.3.0 → 4.4.0 | "chore(deps): phoenix_html 4.3.0 -> 4.4.0" | Published 2026-10-30 with no Dependabot PR yet; the lane had left it unread. On 2026-10-31 its advisory reached hex.pm (EEF-CVE-2026-117645, medium: attribute injection through unvalidated attribute names in `attributes_escape/1`, the function HEEx uses for dynamic attributes) and turned `mix hex.audit` red on the branch with nobody pushing, so the lane takes the fix release, as it takes every advisory. Lock only, inside `~> 4.1`. |
| Compose's database image digest | `postgres:18.6-alpine3.24` `77f58511…` → `10a5c69a…` | "chore(docker): the Compose database image moves to the rebuilt 18.6-alpine3.24 digest" | Dependabot #1283 (2026-10-30): the same PostgreSQL 18.6 on the same Alpine line, rebuilt on 2026-10-26; the digest is the tag's index digest read from Docker Hub. `docker-compose.dev.yml` moves with `docker-compose.yml`, which Dependabot does not watch, so both files run one image. Proven by CI's `compose-smoke` job on the PR. |

Every row is its own commit, never mixed into a security row (ADR-0036
clause 1). The lane's commits sit at the head of the sprint PR's history
before Lane S, as the amendment's D-2 orders.

## Dependabot

Thirteen Dependabot PRs were open at lane time: eight when the branch opened
(the amendment of 2026-10-27 counted five, #1232, #1233, #1234, #1235 and
#1237, and did not name #1227, #1228 and #1230, open since 2026-10-16), and
five more from Dependabot's run of 2026-10-30, while the lane was building.
Eleven are taken, one is superseded and one is declined:

- **#1237** `phoenix` 1.8.16 and **#1235** `phoenix_live_view` 1.2.13: taken
  (above).
- **#1233** `pre-commit` 4.7.0: taken.
- **#1234** `node` 24.21.0 → 26.12.0 and **#1232** `@types/node` 24.19.2:
  both close with the Node 26 commit; the image then moves on to 26.13.0,
  the LTS release, so #1234's exact version is superseded by the lane's own
  row rather than taken as proposed.
- **#1230** `express` 5.3.0, **#1228** `actions/setup-node` 7.1.0, **#1227**
  `actions/upload-artifact` 7.0.2: taken (above).
- **#1281** `@modelcontextprotocol/sdk` 1.32.2, **#1282** `actions/setup-python`
  7.1.0, **#1283** the Compose `postgres:18.6-alpine3.24` digest: taken
  (above).
- **#1280** `node` 24.21.0 → 26.12.1: superseded by the lane's 26.13.0 (the
  LTS release); it closes with the Node commits, as #1234 does.
- **#1279** `decimal` 3.1.2 → 3.2.0: **declined, with its reason recorded
  below** ("Deliberately not updated"). The PR stays open, as D-7 says of a
  bump the lane does not take.

Dependabot's version updates do not cover transitive dependencies
(`@hono/node-server`, `websock_adapter`, `elixir_make`), and `dependabot.yml`
ignores the `hexpm/elixir` and `debian` images on purpose, so the lane reads
those itself. No Dependabot PR remains that is neither taken nor a recorded
decline.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **T-11's hotfix, the three lock moves** (`decimal` 3.1.2, `plug_crypto` 2.2.1, `bandit` 1.14.0) | the lock on the branch: `decimal` 3.1.2, `plug_crypto` 2.2.1 and `bandit` **1.14.1** (the advisory fix above); `mix hex.audit` and `mix deps.audit` report nothing | **Held.** The hotfix is in the base the branch grew from, and the only move since is Bandit's own fix release. |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 (2026-08-14) and ecto_sql 3.14.0 are still the newest, both in the lock. The newest Elixir tag is now 1.20.5 (1.20.4 at Sprint 20); no 1.21 exists. The newest OTP tags are 27.3.4.19, 28.5.0.8 and 29.1.2. | **No.** D-4 of Sprint 20 closed #727 as not planned and keeps this check here; a trigger firing opens a new issue for the move. An intermediate 1.19 step was never tried. |
| **Node 26 LTS promotion (#728's pin)** | the Node release index and schedule: 26.13.0 is LTS "Lithium" since 2026-10-28; 24.22.2 (2026-10-27) is line 24's newest, now Maintenance LTS until 2028-04-30 | **Yes.** Taken (above). The next check is line 28's, due 2027-10-20. |
| **A BMAD release since 6.12.1** | `git ls-remote --tags` on the method repository: v6.12.2, v6.12.3 and **v6.12.4** exist | **Yes**, and not taken here: Sprint 20's report named a BMAD re-pin the candidate for the *next sprint branch's first commit*, because no story is built under a process that changes halfway, and Sprint 21's plan put no re-pin in Lane M. The next planning session puts v6.12.4 (or newer) into its Lane M, with the module set the manifest records. |
| **An OTP 27 patch after 27.3.4.18** | the OTP tags: **27.3.4.19** exists | **Yes**, and not taken here: the pin moves CI's `otp-version`, both Dockerfile base images and the Dialyzer PLT cache key together, and no `hexpm/elixir` image for 1.18.5 on 27.3.4.19 exists yet on Docker Hub (the newest 1.18.5 images are on 27.3.4.18, bookworm-20261005). It rides the next lane with the image. |
| **A Debian bookworm date after 20261005** | Docker Hub: `bookworm-20261020` and `bookworm-20261027` (both with `-slim`) exist | **Yes**, and not taken here: `hexpm/elixir` publishes no 1.18.5-erlang-27.3.4.18 image on either date, and `ci_test` holds the development image's and the build stage's Debian date equal, so the runtime stage alone cannot move. The next lane re-reads it; a security fix read in the base would force the runtime stage's move on its own, with the test's rule amended. None was read: the Debian archive and security tracker are outside the lane's network policy. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP minors and majors (#727) | Elixir 1.18.5 / OTP 27.3.4.18 | Both halves are still blocked upstream (see the triggers above). The move stays on its own branch and PR, because it moves the CI version pins, the Dockerfile base images and the Dialyzer PLT cache key together. CI compiles with `--warnings-as-errors`, so two Elixir minors of deprecations are a body of work, not a version-string edit. The 27.3.4.19 patch waits for its `hexpm/elixir` image (above). |
| `decimal` | 3.1.2 (3.2.0 published the same day, 2026-10-10; Dependabot #1279 of 2026-10-30 proposes it) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28), which 3.2.0 lies outside, so the PR moves `mix.exs` too. **Declined this lane**, as the triage's H28 row already orders: 3.2.0 changes division and rounding results (its own release notes name `div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, and new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). A release that changes rounding is read against the identities the ledger pins before it is taken, as its own reviewed bump on a quiet branch, never inside a security batch. |
| `websock_adapter` (transitive, under `phoenix`) | 0.6.0 (0.7.0 published 2026-10-27) | Came along with the `phoenix_live_view` resolution and was reverted so the commit mirrors Dependabot #1235's scope. A transitive minor; no advisory, no defect the app has met (the LiveView socket runs on it unchanged). The next lane reads its changes. |
| `floki` (test only) | 0.38.4 (0.38.5 published 2026-10-29) | Published after the sprint PR's base; no Dependabot PR yet. A test-only patch is taken by Dependabot's PR, not ahead of it. |
| `sobelow` (dev, test) | 0.16.0 (0.17.0 on 2026-10-28, 0.18.0 and 0.18.1 on 2026-10-29) | Two minors in two days, of a gate tool. A new Sobelow can add findings and change what `.sobelow-skips` matches, and the sprint's rule is that a gate is never weakened and `.sobelow-skips` not changed inside the security batch (D-6); so the move is its own commit on a quiet branch, where a new finding is a finding and not a gate fight. Dependabot proposes it next week. |
| `@types/node` patch (mcp-server) | 26.6.5 (26.6.6 published 2026-10-28) | Same: inside the range, no PR yet. The major now follows the pinned Node 26 runtime (the Sprint 8 decision); `dependabot.yml`'s ignore moved with it. |
| Transitive npm drift inside its ranges (mcp-server) | for example `jose` 6.2.3 (6.2.14), `express-rate-limit` 8.5.2 (8.7.2), `eventsource-parser` 3.0.8 (3.1.1), `qs` 6.17.0 (6.17.1), `on-finished` 2.4.1 (2.4.2) under the SDK and express; `esbuild` 0.28.1 (0.28.2) under `tsx`; 11 entries with a newer version inside their range (`npm outdated --all`, the platform-specific `@esbuild/*` packages not counted) | `npm audit` reports 0 vulnerabilities at any level after the `@hono/node-server` move, and the lanes take a transitive npm entry for an advisory, not for drift. A lockfile-wide update would move eleven entries in one change with no reason read for any of them. |
| MCP SDK v2 (mcp-server) | `@modelcontextprotocol/sdk` 1.32.1 (v2: `@modelcontextprotocol/server` 2.4.0, 2026-10-23) | The SDK's README names v1.x the maintenance line; v1.x receives bug and security fixes for at least six months after v2's release of 2026-07-27, so until 2027-01-27 at the earliest. Moving the companion is a package migration, not a version bump, and whatever it changes in the tool schemas is measured against the schema budget. #1115 tracks it as its own risk-tier lane before v1's support ends. |
| Dockerfile `HEX_VERSION` | 2.4.2 (local Hex 2.5.1) | The image pin reproduces the image. The advisory gates run in CI against the current Hex, so nothing in this batch sits behind the pin. |
| PostgreSQL major | 18 (`18.6`, by digest) | 18.6 is still the newest 18 patch on Docker Hub. 19 exists as **19rc1** (2026-10-28) only, and a release candidate is not a candidate for a self-hosted instance's data directory. The postgresql.org version feed is outside the lane's network policy, so Docker Hub's tags are the source. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | The tag was rebuilt on 2026-10-28 (now `979bccfd…`), still PostgreSQL 18.6. It serves CI's test database only and ships in no image, no security fix was read that forces it, and Dependabot has proposed nothing for it (it watches Compose, not the workflow's `services:`), so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). Compose's digest, which Dependabot did propose, is taken above. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2 at Sprint 20) | A **major** behind. The between-batches rule applies, plus a read of the major's changes, so it is its own decision. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | BMAD 6.12.0's registry marks the module deprecated in favour of `bmad-loop`. Recorded, not acted on: replacing or re-pinning the automator changes how stories are run, which is a process decision for the owner, not a version bump. |
| BMAD core and method, `tea`, `cis` | 6.12.1; v1.27.2, v0.3.2 (pinned) | Core and method: see the BMAD trigger above (v6.12.4 exists; the next planning session's Lane M). `tea` and `cis` were not re-read this lane; they ride the same re-pin. |

## The OTP inside the release's build image

| Row | Value |
| --- | --- |
| Build image (`Dockerfile.release`, stage `build`) | `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20261005-slim@sha256:312c162a…` |
| `OTP_VERSION` read from that image | **not read this lane** (no Docker daemon in the session, and the script said so) |
| CI's `otp-version` pin | 27.3.4.18 |

The image pin is unchanged since Sprint 20's report, which read **27.3.4.18**
from the same digest by fetching the layer that carries `/usr/local/lib/erlang`
and reading `releases/27/OTP_VERSION`. A digest names one image, so the
reading holds for as long as the pin does; the next lane that moves the pin
reads the new image the same way.

## The picture at lane time

- **Toolchain pins (CI is authoritative):**
  - Elixir 1.18.5, OTP 27.3.4.18.
  - The development image and the release's build stage use
    `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20261005`; the build
    stage uses its `-slim` variant.
  - The runtime stage uses `debian:bookworm-20261005-slim`.
  - The database is `postgres:18.6-alpine3.24` in Compose (both files, the
    digest of 2026-10-26) and `postgres:18.6` in CI.
  - Node 26: `node:26.13.0-alpine3.24`, `engines.node >=26 <27`, and
    `node-version: "26"` in both companion jobs of CI.
  - Every image above is pinned by digest.
- **Hex:**
  - Direct: every dependency *Up-to-date* except `decimal` (requirement),
    `floki` and `sobelow` (above). Transitive:
    `websock_adapter` 0.6.0 (0.7.0 exists, above); everything else
    *Up-to-date* (`mix hex.outdated --all`).
  - `mix hex.audit`: no retired packages, no advisories (after `bandit`
    1.14.1 and `phoenix_html` 4.4.0).
  - `mix deps.audit`: no vulnerabilities.
  - `mix deps.unlock --check-unused`: no unused entries.
- **npm (mcp-server):**
  - `npm audit`: 0 vulnerabilities at any level (after `@hono/node-server`
    2.1.5).
  - Outdated: `@types/node`'s patch among the direct dependencies, and the
    transitive drift above.
- **BMAD install:**
  - The manifest says 6.12.1; core and bmm are 6.12.1.
  - Pinned modules: tea v1.27.2 (`d99ad29`), cis v0.3.2 (`97298b2`), bmb
    v1.8.1 (`3410d95`).
  - automator tracks `main` (`0b94fd7`).
- **Network notes:** hex.pm's API, PyPI, the npm registry, nodejs.org's
  release index and schedule, GitHub's tag lists and Docker Hub's tag API
  were reachable through the session's egress proxy; `registry.hub.docker.com`
  (the registry itself), the Debian archive and the Debian security tracker
  were not. No Docker daemon.

## Gate results on the branch's head

<!-- GATES: filled from the full required check list run before the push -->
Run on the sprint branch carrying Lane M and Lane S before the push, on the
local toolchain Elixir 1.18.5 / OTP 27.3.4.18, PostgreSQL 16, Node 22 (CI runs
the companion on Node 26; `npm install` warns `EBADENGINE` locally and runs).

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | pending |
| `mix compile --force --warnings-as-errors` | pending |
| `mix gettext.extract --check-up-to-date` | pending |
| `mix test` | pending |
| `mix coveralls` | pending |
| `mix credo --strict` | pending |
| `mix sobelow --skip --exit` | pending |
| `mix dialyzer --format short` | pending |
| `mix deps.unlock --check-unused` | pending |
| `mix hex.audit` | pending |
| `mix deps.audit` | pending |
| `pre-commit run --all-files` | pending |
| `npm test --prefix mcp-server` | pending |
| `npm run build --prefix mcp-server` | pending |
| `npm audit --audit-level=high --prefix mcp-server` | pending |
