# Version Report — 2026-10-03 (Sprint 18 maintenance lane, PR α)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before PR α's closing act
(the Sprint 18 plan's Lane M and D-11). The lane reports what it deliberately
did not update and why. A row whose reasoning has not changed since the last
report carries that reasoning again rather than a cross-reference, so this
report reads on its own. Commits are named by subject, because the branch's
history is cleaned before the merge and hashes change.

## Applied this lane

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `sobelow` (dev, test) | 0.15.0 → 0.16.0 | "chore(deps): take sobelow 0.16.0, its six new findings read (#1006)" | Sprint 17 tried the bump, saw six new findings and filed #1006 rather than read them in a lane. D-11 takes it with each finding read. None is a defect; each is a decision already on record, carried where the code can hold it (see the next section). `mix sobelow --skip --exit` exits 0. Lock-only, inside `~> 0.13`. |
| `@modelcontextprotocol/sdk` (mcp-server) | 1.31.0 → 1.32.0 | "chore(deps): @modelcontextprotocol/sdk 1.31.0 -> 1.32.0 in mcp-server" | Published 2026-10-02, after Dependabot's weekly run, and PR β builds two new tools on it. Read from the package diff, since no release notes were reachable from the lane. Server side, `McpServer` gains an opt-in `maxToolInputElements` ceiling (unset means no limit, as before), and the SDK's `requireBearerAuth` gains an opt-in `expectedResource` check. The companion uses neither: it checks its own static bearer token. The rest is client-side status handling and the example servers' session caps. The schema budget measures the same bytes. Lock-only, inside `^1.13.0`. |
| `@types/node` (mcp-server, dev) | 24.19.0 → 24.19.1 | "chore(deps-dev): @types/node 24.19.0 -> 24.19.1 in mcp-server" | A patch of the types for the pinned Node 24 runtime. Lock-only. |

Every row is its own commit, never mixed into a feature story (ADR-0036
clause 1).

## sobelow 0.16.0: the six findings, each read

0.16.0 reworks the HTTPS, CSP and socket checks to read "effective settings",
and reworks `XSS.Raw` to follow local helpers. None of the six is waived with
`--ignore`.

| Finding | Site | Reading | Carried as |
| --- | --- | --- | --- |
| `XSS.Raw` | `AppShell.icon/1` | `raw/1` renders SVG path literals that are fixed at compile time and chosen by the icon's atom. Nothing from a request or the database reaches them. | `# sobelow_skip ["XSS.Raw"]` with that reason |
| `XSS.Raw` | `SecurityChart.chart/1` | The chart payload is JSON written into a `<script type="application/json">` block. Jason encodes it with `escape: :html_safe`, so no stored name or note can close the element. | `# sobelow_skip ["XSS.Raw"]` with that reason |
| `Config.CSP` | the `:browser` pipeline | 0.16 reads `put_secure_browser_headers`' static map on its own. The CSP is set per request, with a nonce, by `PortfolixirWeb.ContentSecurityPolicy` (#382). | `# sobelow_skip ["Config.CSP"]` on the pipeline |
| `Config.CSP` | the `:browser_open` pipeline | as above | as above |
| `Config.HTTPS` | `config/prod.exs` | `force_ssl: false` is the recorded posture: TLS is terminated at the reverse proxy, and `PHX_FORCE_SSL` is the runtime opt-in (the Sprint 11 plan's D-2). | a fingerprint in `.sobelow-skips`, under a comment with the reason |
| `Config.CSWH` | the endpoint's LiveView socket | The socket inherits `check_origin`, which `config/runtime.exs` sets to the Host guard's allow-list (#758). 0.16 reads that list as dynamic and reports it at low confidence. | a fingerprint in `.sobelow-skips`, under a comment with the reason |

The last two have no function or pipeline that could carry an annotation. A
fingerprint changes when its site changes, which brings the finding back for a
fresh reading. A `ci_test` case holds `.sobelow-skips` to exactly those two
types and requires a reason for each.

## Dependabot

One Dependabot PR was open at lane time:

- **#977, `node` 24.21.0 → 26.10.0 in `/mcp-server`:** declined again, as D-11
  rules for a lane that runs before the LTS date. Node 26 becomes LTS on
  **2026-10-28**. When it does, the runtime moves in all four pinned places in
  one commit, together with the `@types/node` major that follows it.

#881 (`codecov/codecov-action`), which the Sprint 18 plan's D-11 listed as an
owner action, is closed. No Dependabot PR remains that is neither taken nor a
recorded decline.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 and ecto_sql 3.14.0 are still the newest releases, and both are already in the lock. The newest Elixir build is still 1.20.4. | **No** |
| **Node 26 LTS promotion (#728's pin)** | nodejs.org release index: 26.10.0 is still **Current** (`lts: false`). 24.21.0 is still the newest Active LTS (Krypton), and it is what the image runs. | **No.** The promotion is scheduled for **2026-10-28**. |
| **A BMAD release since 6.12.0** | `git ls-remote --tags` on the method repository: v6.12.0 is still the newest tag | **No** |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP minors and majors (#727) | Elixir 1.18.5 / OTP 27.3.4.18 | Both halves are still blocked upstream (see the triggers above). The move stays on its own branch and PR, because it moves the CI version pins, the Dockerfile base images and the Dialyzer PLT cache key together. CI also compiles with `--warnings-as-errors`, so two Elixir minors of deprecations are a body of work, not a version-string edit. |
| Node runtime major | 24 (`node:24.21.0-alpine3.24`, by digest) | Node 26 is **Current**, not LTS, until **2026-10-28**. An invariant test (#728) pins the runtime in four places, and the companion pins an LTS line. Dependabot's #977 is declined for the same reason. |
| `@types/node` major (mcp-server) | 24.19.1 (26.6.4 latest) | The major follows the pinned Node 24 runtime (Sprint 8 decision). The Dependabot ignore covers the whole major. |
| Dockerfile `HEX_VERSION` | 2.4.2 (local Hex 2.5.1) | The image pin reproduces the image. The advisory gates run in CI against the current Hex, so nothing in this batch sits behind the pin. |
| PostgreSQL major | 18 (`18.6`, by digest) | 18.6 is still the newest 18 patch. 19 exists only as a beta, and a beta is not a candidate for a self-hosted instance's data directory. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2) | A **major** behind. The between-batches rule applies, plus a read of the major's changes, so it is its own decision. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | Still the head of `main`. Tag v1.15.0 sits on `acafaed`, not on `main`'s head. BMAD 6.12.0's registry marks the module **deprecated in favour of `bmad-loop`**. Recorded, not acted on: replacing or re-pinning the automator changes how stories are run, which is a process decision for the owner, not a version bump. |
| BMAD `tea`, `cis` | v1.27.2, v0.3.2 (pinned) | Both are still the newest tags, so there is nothing to take. |

## The OTP inside the release's build image

| Row | Value |
| --- | --- |
| Build image (`Dockerfile.release`, stage `build`) | `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918-slim@sha256:ada1bbb1…` |
| `OTP_VERSION` read from inside that image | **27.3.4.18** |
| CI's `otp-version` pin | 27.3.4.18 |

They agree, so every instance built from this tree runs the OTP that CI tests.
This time the script read the file itself; the session's Docker daemon was
already running.

## The picture at lane time

- **Toolchain pins (CI is authoritative):**
  - Elixir 1.18.5, OTP 27.3.4.18.
  - The development image and the release's build stage use
    `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918`; the build
    stage uses its `-slim` variant.
  - The runtime stage uses `debian:bookworm-20260918-slim`.
  - The database is `postgres:18.6-alpine3.24` in Compose and `postgres:18.6`
    in CI.
  - Node 24: `node:24.21.0-alpine3.24`, and `node-version: "24"` in CI.
  - Every image above is pinned by digest.
- **Hex:**
  - Every dependency is *Up-to-date*, `sobelow` included, now that it is at
    0.16.0.
  - `mix hex.audit`: no retired packages, no advisories.
  - `mix deps.audit`: no vulnerabilities.
  - `mix deps.unlock --check-unused`: no unused entries.
- **npm (mcp-server):**
  - `npm audit`: 0 vulnerabilities at any level.
  - Outdated: only the `@types/node` major (above).
- **BMAD install:**
  - The manifest says 6.12.0; core and bmm are 6.12.0.
  - Pinned modules: tea v1.27.2 (`d99ad29`), cis v0.3.2 (`97298b2`), bmb
    v1.8.1 (`3410d95`).
  - automator tracks `main` (`0b94fd7`).

## Gate results on PR α's head

Run after PR α's closing act on the branch carrying every lane (C, D, M) and
the closing act's review rounds, `1dde09e7`, before the history was cleaned
(the cleaned tree is byte-identical). Local toolchain: Elixir 1.18.5 / OTP
27.3.4.18, PostgreSQL 16, Node 24.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix gettext.extract --check-up-to-date` | up to date |
| `mix test` (run as `mix coveralls`) | 3714 tests, 9 properties, 0 failures, and no uncaptured Logger warning or error. The two `IO.warn` deprecation traces the Sprint 17 report named are gone (#1019) |
| `mix test --only seeded_upgrade` | 25 tests, 0 failures |
| `mix coveralls` | 93.5 % total |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 (0.16.0; the six findings are read in the section above) |
| `mix dialyzer --format short` | 0 errors |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 182 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities at any level |
