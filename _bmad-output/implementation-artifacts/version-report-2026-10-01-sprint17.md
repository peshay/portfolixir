# Version Report — 2026-10-01 (Sprint 17 maintenance lane, PR α)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before PR α's closing act
(the Sprint 17 plan's Lane M). The lane reports what it deliberately did not
update and why. A row whose reasoning has not changed since the last report
carries that reasoning again rather than a cross-reference, so this report
reads on its own. Commits are named by subject, because the branch's history is
cleaned before the merge and hashes change.

## Applied this lane

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `phoenix` | 1.8.14 → 1.8.15 | "chore(deps): phoenix 1.8.14 -> 1.8.15" | Dependabot #975, named by the plan. Two bug fixes and a generator bump. One of them is client-side: `phoenix.js` no longer tears down the replacement transport when the old one closes asynchronously. The endpoint serves `phoenix.min.js` straight from the dependency's `priv/static`, so the new file reaches the browser, but the changed code only runs on a long-poll fallback, which this endpoint does not mount and the LiveSocket does not configure: no behaviour changes here (PR α's closing act, N7). The lock line is identical to the Dependabot PR's. |
| `@types/node` (mcp-server, dev) | 24.13.6 → 24.19.0 | "chore(deps-dev): @types/node 24.13.6 -> 24.19.0 in mcp-server" | Dependabot #976, named by the plan. Types only, on the 24 line the runtime is pinned to; `undici-types` follows inside the types package's own range. The lock is identical to the Dependabot PR's. |
| `fast-uri` (transitive, mcp-server, under the MCP SDK → `ajv`) | 3.1.7 → 3.1.8 | "chore(deps): fast-uri 3.1.7 -> 3.1.8 in mcp-server (GHSA-hrr3-gc8f-f4qj)" | A moderate advisory against `<= 3.1.7` (inconsistent host case normalisation through percent-encoded octets). It sits below the `--audit-level=high` gate, so CI stayed green with it. `ajv` uses the package as its URI resolver (`ajv/dist/runtime/uri.js`) when the SDK resolves schema ids. The fix is taken rather than carried, as Sprint 16 did with `ip-address`: it is a lockfile-only patch release through `npm audit fix`. |
| `@modelcontextprotocol/sdk` (mcp-server) | 1.30.1 → 1.31.0 | "chore(deps): @modelcontextprotocol/sdk 1.30.1 -> 1.31.0 in mcp-server" | Published 2026-09-28, after Dependabot's weekly run. PR β builds the companion's prompts and profiles on this SDK, so the lane takes the current minor now rather than in the middle of that work. The release's one change binds stored OAuth credentials to the issuer that granted them. That is client-side OAuth, which the companion does not use (it is a server authenticating with a static bearer token). Lock-only, inside the existing `^1.13.0` range. |

Every row is its own commit, never mixed into a feature story (ADR-0036
clause 1).

## Dependabot

Four Dependabot PRs were open when the plan was written:

- **#975, `phoenix` 1.8.15:** taken (above). The PR is closed with the commit
  named.
- **#976, `@types/node` 24.19.0:** taken (above). The PR is closed with the
  commit named.
- **#977, `node` 24.21.0 → 26.10.0 in `/mcp-server`:** declined, for the reason
  in the triggers table below. Node 26 is not an LTS release until 2026-10-28.
- **#881, `codecov/codecov-action` 7.1.0 → 7.1.1:** stays the maintainer's, as
  the Sprint 16 report recorded. Dependabot PRs for CI actions are reviewed and
  merged by the maintainer, never folded into a batch, and this one changes
  nothing the batch's gates depend on.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 (2026-08-14) and ecto_sql 3.14.0 are still the newest releases, both already in the lock; the newest Elixir build is still 1.20.4 (2026-08-28, builds.hex.pm) | **No** |
| **Node 26 LTS promotion (#728's pin)** | nodejs.org release index: 26.10.0 (2026-09-21) is still **Current** (`lts: false`); 24.21.0 (2026-09-07) is still the newest Active LTS (Krypton) and is what the image runs | **No.** The promotion is scheduled for **2026-10-28**. When it lands, the runtime moves in all four pinned places in one commit, with the `@types/node` major that follows it. |
| **A BMAD release since 6.12.0** | `git ls-remote --tags` on the method repository: v6.12.0 is still the newest tag | **No** |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `sobelow` (dev, test) | 0.15.0 (0.16.0 published 2026-09-30) | **Tried and reverted.** 0.16.0 is a minor of a blocking security gate and inside the `~> 0.13` requirement, so it is a lock-only bump. Under it, `mix sobelow --skip --exit` exits 1 with six findings 0.15.0 does not raise: HTTPS not enabled in `config/prod.exs`, two `XSS.Raw` (the icon helper in `app_shell.ex`, the chart payload in `security_chart.ex`), cross-site websocket hijacking on the endpoint, and a missing CSP on the `browser` and `browser_open` pipelines. The release notes rework the HTTPS, CSP and socket checks to read "effective settings" and `XSS.Raw` to follow local helpers. Some of the six sit where the code already has a deliberate answer (the nonce-bearing CSP plug of #382, the reverse-proxy HTTPS posture of the Sprint 11 plan's D-2); the two `XSS.Raw` sites and the websocket-origin finding were not read in this lane. Taking the bump means reading each finding against its new rule and fixing the site or recording a skip with its reason: gate work with its own story, not a version-string edit. Filed as #1006. |
| Elixir / OTP minors and majors (#727) | Elixir 1.18.5 / OTP 27.3.4.18 | Both halves are still blocked upstream (triggers above). The move stays its own branch and PR: it moves the CI version pins, the Dockerfile base images and the Dialyzer PLT cache key together, and CI compiles with `--warnings-as-errors`, so two Elixir minors of deprecations are a body of work, not a version-string edit. |
| Node runtime major | 24 (`node:24.21.0-alpine3.24`, by digest) | Node 26 is **Current**, not LTS, until **2026-10-28**. The runtime is pinned in four places by an invariant test (#728), and the companion pins an LTS line. Dependabot's #977 is declined for the same reason. |
| `@types/node` major (mcp-server) | 24.19.0 (26.6.3 latest) | The major follows the pinned Node 24 runtime (Sprint 8 decision; the Dependabot ignore is major-wide). |
| Dockerfile `HEX_VERSION` | 2.4.2 (local Hex 2.5.1) | The image pin reproduces the image. The advisory gates run in CI against the current Hex, so nothing in this batch sits behind the pin. |
| PostgreSQL major | 18 (`18.6`, by digest) | 18.6 is still the newest 18 patch. 19 exists only as a beta, and a beta is not a candidate for a self-hosted instance's data directory. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2) | A **major** behind. The between-batches rule applies, plus a read of the major's changes; that is its own decision. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | Still the head of `main`. A tag **v1.15.0** now exists (on `acafaed`, not on `main`'s head); the Sprint 16 report knew only `v1.15.0-next.1`. BMAD 6.12.0's registry marks the module **deprecated in favour of `bmad-loop`**. Recorded, not acted on: replacing or re-pinning the automator changes how stories are run, which is a process decision for the owner, not a version bump. |
| BMAD `tea`, `cis` | v1.27.2, v0.3.2 (pinned) | Both are still the newest tags; nothing to take. |

## The OTP inside the release's build image

| Row | Value |
| --- | --- |
| Build image (`Dockerfile.release`, stage `build`) | `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918-slim@sha256:ada1bbb1…` |
| `OTP_VERSION` read from inside that image | **27.3.4.18** |
| CI's `otp-version` pin | 27.3.4.18 |

They agree: every instance built from this tree runs the OTP CI tests. The
session had no Docker daemon when the script first ran and the script said so;
a daemon started inside the session then pulled the image by its digest and
the same command the script runs read the file the release bundles.

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.5, OTP 27.3.4.18. The
  development image and the release's build stage use
  `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918` (the build
  stage the `-slim` variant); the runtime stage uses
  `debian:bookworm-20260918-slim`; all three are pinned by digest. The database
  is `postgres:18.6-alpine3.24` in Compose and `postgres:18.6` in CI, both by
  digest. Node 24: `node:24.21.0-alpine3.24` by digest, and `node-version: "24"`
  in CI.
- **Hex:** every dependency is *Up-to-date* except `sobelow` (above).
  `mix hex.audit`: no retired packages, no advisories. `mix deps.audit`: no
  vulnerabilities. `mix deps.unlock --check-unused`: no unused entries.
- **npm (mcp-server):** `npm audit`: 0 vulnerabilities at any level (after the
  `fast-uri` row above). Outdated: only the `@types/node` major (above).
- **BMAD install:** manifest 6.12.0; core and bmm 6.12.0, tea v1.27.2 (pinned,
  `d99ad29`), cis v0.3.2 (pinned, `97298b2`), automator `main` (`0b94fd7`), bmb
  v1.8.1 (pinned, `3410d95`).

## Gate results on PR α's head

Run at PR α's closing act on the branch carrying every lane (Z, M, G, P, D)
and the harness coverage round, `27dc31a`. Local toolchain: Elixir 1.18.5 /
OTP 27.3.4.18, PostgreSQL 16, Node 24.21.0.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix gettext.extract --check-up-to-date` (new, #924) | up to date |
| `mix test` | 3583 tests, 9 properties, 0 failures, and no uncaptured Logger warning or error (the new noise gate, #927; it sees Logger events only, so five `IO.warn` deprecation traces still print: two from Req's function `adapter:` in `http_pool_test.exs`, three from the tuple application-env key in `test/support/fx/fake.ex`), on `4a462c9`; the harness self-tests added after it pass on their own (26 tests) |
| `mix coveralls` | CI's `coveralls.json` on `27dc31a`: 93.54 % total, patch 97.45 % |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 (0.15.0; see the `sobelow` row) |
| `mix dialyzer --format short` | 0 errors |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 155 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities at any level |

The companion's gates ran on Node 24.21.0 this time, the pinned runtime; earlier
reports ran them on Node 22.
