# Version Report — 2026-10-09 (Sprint 20 maintenance lane, PR α)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before PR α's closing act
(the Sprint 20 plan's Lane M, D-3 and D-4). The lane reports what it
deliberately did not update and why. A row whose reasoning has not changed
since the last report carries that reasoning again rather than a
cross-reference, so this report reads on its own. Commits are named by
subject, because the branch's history is cleaned before the merge and hashes
change.

## Applied this lane

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| BMAD core and method (`bmad-method`) | 6.12.0 → 6.12.1 | "chore(bmad): re-pin core and method to 6.12.1; the user-config seed retires" | Sprint 19's report named it the candidate for the Sprint 20 branch's first commit, and the plan's Lane M put it there, before any story, as Sprint 16 took 6.12.0: no story is built under a process that changes halfway. Run through the official installer with the module set the manifest records. 6.12.1 is a patch release with four fixes. 23 bmm skills load config through one merged resolver, so overrides in `_bmad/custom/config.toml` and `config.user.toml` apply everywhere. `config.toml` carries defaults for the user-scope keys. `bmad-create-epics-and-stories` keeps `status: draft` until every check passes. Party mode's collision check sees aliases. tea v1.27.2, cis v0.3.2 and bmb v1.8.1 stay pinned unchanged; the automator was refreshed on its `next` channel at the same `0b94fd7`. |
| #1099's seeding of the BMAD user config | retired | the same commit | The question Sprint 19 left with the re-pin. 6.12.1's committed `_bmad/config.toml` carries the user-scope defaults (`user_name` and `communication_language` under `[core]`, `user_skill_level` under `[modules.bmm]`). With the gitignored `config.user.toml` removed, `render_skill.py` renders `bmad-build` (exit 0), so the seed script and the web session hook's seeding step go. `ci_test` now pins the committed defaults instead, and was seen failing first on the hook's seed call. |
| `phoenix_pubsub` (under `phoenix`) | 2.3.0 → 2.4.1 | "chore(deps): phoenix_pubsub 2.3.0 -> 2.4.1" | Published 2026-10-07 (2.4.0) and 2026-10-08 (2.4.1), after Dependabot's weekly run, and a transitive dependency, which Dependabot's version updates do not cover. Lock-only, inside Phoenix's `~> 2.1`. Read from the package diff: the release adds `Phoenix.PubSub.Sender`, a per-subscription successor to custom dispatchers (2.4.1 adds its optional `finalize/1`), and marks the dispatcher arities of `broadcast` and its siblings deprecated in their docs only (`@doc deprecated`, so no compile warning). What the app relies on stays as it was: `Portfolixir.Catalog.LogoStore` subscribes and broadcasts with the three-argument calls, a plain subscription is still delivered with `send/2`, and Phoenix 1.8.15's channels subscribe with tuple metadata (`{:fastlane, ...}`) and pass their own dispatcher, which is still called. The one new refusal, `subscribe` metadata in the shape `[atom \| term]`, matches no subscription the app or Phoenix makes. Nothing in it fixes a defect the app has met: a currency bump under the lane's rule, green on every gate. |
| The images' Debian date | `bookworm-20260918` → `bookworm-20261005`, all three `FROM` lines | "chore(docker): the release images move to Debian bookworm 20261005" | Sprint 19 held it for a release build that can run (the Sprint 20 plan's D-3). Since the plan's note of 2026-10-08, CI's `compose-smoke` job builds and boots the release image from the branch on every change to it, so the move is proven by CI on the PR, not by a build in this session. **Why now:** between the two `debian` slim images exactly two packages differ, read from each image's dpkg status. `libpcre2-8-0` moves from 10.42-1+deb12u1 to +deb12u2, a `bookworm-security` upload with urgency high (GHSA-r9hj-j2rw-4q3m, a large JIT stack allocation, per the package's Debian changelog read from the non-slim image). `tzdata` moves from 2026b to 2026c (Alberta and Morocco move to permanent offsets). The runtime stage's apt step installs only packages the base lacks, so a fix to a base package reaches the image through the base date alone. Each digest is the hash of the index the registry serves for the tag, verified by hashing the index body. The development image moves too, because `ci_test` holds its Debian date equal to the build stage's. |
| The build CA's trust (#1136) | the rest of the build stage → the step that sources the script | "fix(docker): the build CA leaves the store when the step that trusts it ends (#1136)" | Waited with the Debian date for a build that can run (D-3; D-13). `docker/trust-build-ca.sh` copied the `build_ca` secret into the build stage's store, so every later step of the stage trusted it, the build cache kept it and a `--target build` image carried it. The script now arms an EXIT trap before it adds the CA; when the step's shell exits, the trap removes the CA and runs `update-ca-certificates --fresh`, so the store is rebuilt before BuildKit writes the layer (a run without `--fresh` leaves the CA's symlinks dangling, checked against a real `update-ca-certificates` in a scratch directory). The step keeps its exit status; a CA that cannot be taken out fails a step that would have passed. Test first: `ci_test` sources a copy of the script against a stub and was seen failing on the missing `--fresh` call. The guide (EN, DE) says so, and that `docker builder prune` clears a cache an earlier version built with the secret. **What CI proves:** `compose-smoke` builds without the secret, so it proves the no-secret path unchanged and the script sourced cleanly by the image's `/bin/sh`; the path with the secret is proved by `ci_test`'s run under `dash`, the shell of the build image, not by a build. |

Every row is its own commit, never mixed into a feature story (ADR-0036
clause 1).

## Dependabot

One Dependabot PR was open at lane time:

- **#977, `node` 24.21.0 → 26.10.0 in `/mcp-server`:** declined again, as the
  plan's Lane M rules. Node 26 becomes LTS on **2026-10-28**, after this
  sprint's window. The next sprint that runs on or after that date takes it:
  the runtime moves in all four pinned places in one commit, together with the
  `@types/node` major that follows it. Node 26.11.1 (2026-10-07) is now the
  newest Current release, so the PR's 26.10.0 is behind as well.

No other Dependabot PR is open. `phoenix_pubsub` is a transitive dependency,
which Dependabot's version updates do not cover, and Dependabot ignores the
`hexpm/elixir` and `debian` images on purpose (`dependabot.yml`), so the lane
reads both itself. No Dependabot PR remains that is neither taken nor a
recorded decline.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm and the repository's tags: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 and ecto_sql 3.14.0 are still the newest releases and tags, and both are already in the lock. The newest Elixir is still 1.20.4, on builds.hex.pm (2026-08-28) and in the language's tags; no 1.21 exists. The newest OTP tags are 28.5.0.7 and 29.1.1. | **No.** D-4 closed #727 as not planned on 2026-10-08 and keeps this check here; a trigger firing opens a new issue for the move. D-4's note for the next look: an intermediate 1.19 step was never tried (1.19.6 is the newest 1.19 tag). |
| **Node 26 LTS promotion (#728's pin)** | nodejs.org release index: 26.11.1 is still **Current** (`lts: false`). The Node release schedule still dates 26's LTS to **2026-10-28**. 24.21.0 is still the newest Active LTS (Krypton), and it is what the image runs. | **No.** Line 24 moves to Maintenance LTS on 2026-10-20 and keeps security releases until 2028-04-30, so nothing forces the move before the 28th. |
| **A BMAD release since 6.12.1** | `git ls-remote --tags` on the method repository: v6.12.1 is still the newest tag; npm's `bmad-method` `latest` is still 6.12.1 (2026-10-04), `next` is 6.12.1-next.1 | **No** |
| **A release build that can run (D-3), for the Debian date and #1136** | the plan's note of 2026-10-08: CI's `compose-smoke` job builds both images from the branch whenever `Dockerfile.release` or `docker/**` changes | **Yes.** Both are taken (above). |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP minors and majors (#727) | Elixir 1.18.5 / OTP 27.3.4.18 | Both halves are still blocked upstream (see the triggers above). The move stays on its own branch and PR, because it moves the CI version pins, the Dockerfile base images and the Dialyzer PLT cache key together. CI also compiles with `--warnings-as-errors`, so two Elixir minors of deprecations are a body of work, not a version-string edit. The OTP patch pin has nothing to move: 27.3.4.18 is still the newest OTP 27 tag. |
| Node runtime major | 24 (`node:24.21.0-alpine3.24`, by digest) | Node 26 is **Current**, not LTS, until **2026-10-28**. An invariant test (#728) pins the runtime in four places, and the companion pins an LTS line. Dependabot's #977 is declined for the same reason. The pinned digest is still the tag's current one. |
| `@types/node` major (mcp-server) | 24.19.1 (26.6.4 latest) | The major follows the pinned Node 24 runtime (Sprint 8 decision). The Dependabot ignore covers the whole major. |
| Transitive npm drift inside its ranges (mcp-server) | for example `hono` 4.13.8 (4.13.13), `jose` 6.2.3 (6.2.12), `express-rate-limit` 8.5.2 (8.7.1) and `@hono/node-server` 2.1.0 (2.1.4) under the MCP SDK; `esbuild` 0.28.1 (0.28.2) under `tsx`; 13 entries in all (`npm outdated --all`) | New this lane as a written row; the practice is Sprint 16's. `npm audit` reports 0 vulnerabilities at any level, and the lanes take a transitive npm entry for an advisory (`ip-address` in Sprint 16, `fast-uri` in Sprint 17, `proxy-addr` in Sprint 19), not for drift. A lockfile-wide update would move 13 entries under the SDK, express and `tsx` in one change with no reason read for any of them. The companion's direct dependencies are all at their newest inside their ranges. |
| MCP SDK v2 (mcp-server) | `@modelcontextprotocol/sdk` 1.32.1 (v2: `@modelcontextprotocol/server` 2.3.1) | The SDK's README names v1.x the maintenance line, implementing the MCP spec up to 2025-11-25. v2 implements the 2026-07-28 spec and ships as separate packages with a migration guide. v1.x receives bug and security fixes for at least six months after v2's release on 2026-07-27, so until 2027-01-27 at the earliest. Moving the companion is a package migration, not a version bump, and whatever it changes in the tool schemas is measured against the schema budget. #1115 now tracks it as its own risk-tier lane before v1's support ends (the plan's D-13). 1.32.1 is still the newest 1.x. |
| Dockerfile `HEX_VERSION` | 2.4.2 (local Hex 2.5.1) | The image pin reproduces the image. The advisory gates run in CI against the current Hex, so nothing in this batch sits behind the pin. |
| PostgreSQL major | 18 (`18.6`, by digest) | 18.6 is still the newest 18 patch on Docker Hub. 19 exists only as a beta (`19beta4`), and a beta is not a candidate for a self-hosted instance's data directory. The postgresql.org version feed is outside the lane's network policy, so Docker Hub's tags are the source. Compose's `postgres:18.6-alpine3.24` digest is still the tag's current one. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | New this lane. The tag was rebuilt on 2026-10-06 on a newer `debian:trixie-slim` base (index annotations; today's digest is `74935e72…`), still PostgreSQL 18.6. It serves CI's test database only and ships in no image, and no security fix was read that forces it, so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). Dependabot has proposed nothing for it. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2) | A **major** behind. The between-batches rule applies, plus a read of the major's changes, so it is its own decision. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | Still the head of `main`. Tag v1.15.0 sits on `acafaed`, not on `main`'s head. BMAD 6.12.0's registry marks the module **deprecated in favour of `bmad-loop`**. Recorded, not acted on: replacing or re-pinning the automator changes how stories are run, which is a process decision for the owner, not a version bump. |
| BMAD `tea`, `cis` | v1.27.2, v0.3.2 (pinned) | Both are still the newest tags, so there is nothing to take. |

## The OTP inside the release's build image

| Row | Value |
| --- | --- |
| Build image (`Dockerfile.release`, stage `build`) | `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20261005-slim@sha256:312c162a…` |
| `OTP_VERSION` read from that image | **27.3.4.18** |
| Elixir in that image (`elixir.app`) | 1.18.5 |
| CI's `otp-version` pin | 27.3.4.18 |

They agree, so every instance built from this tree runs the OTP that CI tests.
The session had no Docker daemon, and the script said so. The lane read the
image without one instead: it fetched the amd64 layer that carries
`/usr/local/lib/erlang` from the registry by its digest and read
`releases/27/OTP_VERSION` from it. The image's amd64 base layer is the
`debian:bookworm-20261005-slim` layer the runtime stage pulls.

## The picture at lane time

- **Toolchain pins (CI is authoritative):**
  - Elixir 1.18.5, OTP 27.3.4.18.
  - The development image and the release's build stage use
    `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20261005`; the build
    stage uses its `-slim` variant.
  - The runtime stage uses `debian:bookworm-20261005-slim`.
  - The database is `postgres:18.6-alpine3.24` in Compose and `postgres:18.6`
    in CI.
  - Node 24: `node:24.21.0-alpine3.24`, and `node-version: "24"` in CI.
  - Every image above is pinned by digest.
- **Hex:**
  - Every dependency is *Up-to-date*, direct and transitive
    (`mix hex.outdated --all`), now that `phoenix_pubsub` is at 2.4.1.
  - `mix hex.audit`: no retired packages, no advisories.
  - `mix deps.audit`: no vulnerabilities.
  - `mix deps.unlock --check-unused`: no unused entries.
- **npm (mcp-server):**
  - `npm audit`: 0 vulnerabilities at any level.
  - Outdated: only the `@types/node` major among the direct dependencies, and
    the transitive drift above.
- **BMAD install:**
  - The manifest says 6.12.1; core and bmm are 6.12.1.
  - Pinned modules: tea v1.27.2 (`d99ad29`), cis v0.3.2 (`97298b2`), bmb
    v1.8.1 (`3410d95`).
  - automator tracks `main` (`0b94fd7`).
- **Network notes:** the Debian archive and security tracker are still outside
  the lane's network policy (HTTP 403 through the egress proxy), so the
  `pcre2` advisory was read from the package changelog inside the image, not
  from the tracker. Docker Hub's API and registry were reachable.

## Gate results on the lane's head

Run on the branch carrying the BMAD re-pin, this lane's four commits and
nothing else, before PR α's closing act. Local toolchain: Elixir 1.18.5 / OTP
27.3.4.18, PostgreSQL 16, Node 22 (CI runs the companion on Node 24).

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix gettext.extract --check-up-to-date` | up to date |
| `mix test` | 4561 tests, 9 properties, 0 failures |
| `mix coveralls` | 94.3 % total (4561 tests, 9 properties, 0 failures) |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 |
| `mix dialyzer --format short` | 0 errors |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 220 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |
