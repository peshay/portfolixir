# Version Report — 2026-11-05 (Sprint 25 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, on the sprint branch
right after M1 (Elixir 1.19.7), in the lane's own worktree (the Sprint 25
plan's Lane M, M3). The lane reports what it deliberately did not update and
why. A row whose reasoning has not changed since the last report carries
that reasoning again, so this report reads on its own. Commits are named by
subject, because the branch's history is cleaned before the merge and
hashes change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| Elixir, in every pinned place (M1, #1390) | 1.18.6 → **1.19.7** on OTP 27.3.4.19 (OTP and `bookworm-20261027` unchanged by M1) | "build(elixir): Elixir 1.18.6 -> 1.19.7, CI, both images, the PLT key and the install script (M1)", "style(elixir): the three files Elixir 1.19's formatter lays out differently (M1)", "fix(elixir): the struct updates Elixir 1.19's type checker refuses (M1)" | The attempt Sprint 20's D-4 named and Sprint 24's M4 made once: #727's Elixir half had only ever been tried at 1.20.x. M4 found 1.19.7 green on every CI job (scratch PR #1389, closed unmerged) but not the mechanical three-place bump, so it was filed as #1390 and built here as its own reviewed change, Lane M's first story. The first commit moves every CI job's `elixir-version` and the Dialyzer PLT cache key, the development image and the release's build stage (`hexpm/elixir` 1.19.7 on the same OTP and Debian date, pinned by digest), the cloud session's install script with the SHA-256 of `elixir-otp-27.zip` as builds.hex.pm and the release's `.sha256sum` asset publish it, and the version the README and the development guide name. The second is the 1.19 formatter's layout of `lib/portfolixir/imports/correction.ex`, `test/portfolixir/imports/cash_correction_test.exs` and `test/portfolixir/imports/import_hash_reimport_test.exs` (two long calls broken, one tuple joined differently). The third matches the two `Result` struct updates in `Imports.Applier` (`enrich_after_commit/1`, `resolve_portfolio/2`) as `%Result{}`, which 1.19's type checker requires before a struct update, and one `%Transaction{}` update in `test/portfolixir/ledger/settlement_backfill_test.exs`, which the scratch run did not report because CI compiles tests without `--warnings-as-errors`. Nothing else warns on 1.19.7. Every gate below ran on 1.19.7. |
| The Debian date, in both images (M3) | `bookworm-20261027` → `bookworm-20261104` (Elixir 1.19.7 and OTP 27.3.4.19 unchanged) | "chore(toolchain): Debian bookworm 20261027 -> 20261104 in both images (M3)" | New this lane: the trigger below fired. Docker Hub carries `debian:bookworm-20261104` and the Hex team's `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` with its `-slim` variant (all three 2026-11-05), on the Elixir and OTP the branch already pins. One commit moves the three places that name the date together, so `ci_test`'s parity (the development image, the build stage and the runtime stage on one Debian date) holds: the development image, the release's build stage and its runtime stage (`debian:bookworm-20261104-slim`). CI does not move: it runs the toolchain through `setup-beam`, not these images. Each image is pinned by its tag's index digest read from Docker Hub (`ecb921d9…`, `01499334…`, `734a72b3…`) and confirmed by `mirror.gcr.io`'s `docker-content-digest`. Dependabot ignores `hexpm/elixir` and `debian` by design (`.github/dependabot.yml`: it reads the OTP patch and the Debian date as a fixed suffix), so the lane moves them. The images could not be built in the session (no Docker); CI's compose-smoke job builds the release image (both its stages, since the change touches `Dockerfile.release`), and no CI job builds the development image. |

Every row is its own commit group, never mixed into a risk-tier story's
commits (ADR-0036 clause 1).

## Dependabot

Read from GitHub's open pull requests at lane time (read only; the lane
comments on and closes nothing). Two Dependabot PRs are open, both from
2026-11-05:

- **#1392**, `floki` 0.38.4 → 0.38.5 (test only). This is the route the last
  report named for the test-only patches, so the lane does not take it ahead
  of the PR; it is the owner's merge.
- **#1391**, `sobelow` 0.16.0 → 0.18.1 (dev, test). Sprint 23 closed #1346
  (0.16.0 → 0.18.0) with its findings; #1391 is the same move one patch
  further. 0.18.1's whole diff against 0.18.0 (`mix hex.package diff sobelow
  0.18.0..0.18.1`) is one bug fix in `Sobelow.Parse.Variables` (bracket
  access no longer leaks AST tuples into finding labels and aborts scans;
  "existing finding source locations and skip fingerprints are unchanged"),
  so the four `XSS.Raw` findings that decided the decline are untouched. The
  decline stands (below); #1391 can be closed with the same findings.

No Dependabot PR is open for `lazy_html` 0.1.14 or `playwright` 1.65.0
(below); why the bot has not opened the first is not visible from the
repository.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.4** | npm: `bmad-method` dist-tags are `latest` 6.12.4 (2026-10-14), `next` 6.12.3-next.1, `rollback` 4.39.0; the method repository's newest tag is v6.12.4, and `main` is still `022be93` (the v7 preview, `bmod-core-tools` 6.13.0-next) | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261027, with its image** | Docker Hub: `debian:bookworm-20261104` and `-slim`, and `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` and `-slim`, all 2026-11-05 | **Yes**, taken (above). |
| **An Elixir 1.19 patch after 1.19.7, with its image** | builds.hex.pm's Elixir build list: 1.19.7 (2026-10-29) is the newest 1.19; the branch pins its `bookworm-20261104` pair (above) | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** for 1.20 (newest 1.20.5, 2026-10-29). The half's 1.19 step is taken (M1, above); 1.20 still waits on excoveralls. |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7) | hex.pm: no Ecto release after 3.14.3 (2026-11-04), whose changelog has no opaqueness entry; `ecto_sql` unchanged at 3.14.0; Elixir 1.19.7 (M1) names none | **No**. The trigger's own test was not re-run: nothing upstream moved since Sprint 24 ran it on OTP 28.5.0.8 (117 opaqueness errors in 29 files, and `logo_lookup.ex`'s `@issuers` regex attribute does not compile on OTP 28). |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `sobelow` (dev, test) | 0.16.0 (0.18.1 exists; Dependabot #1391) | Declined in Sprint 23 with its findings: 0.18.x flags four `XSS.Raw` (low confidence) in `securities_live.ex`'s `render_cell` clauses, which escape their value, so taking it needs four new skips (a weakened gate) or a rewrite into HEEx, a screen change on the Securities polish list (#1365). 0.18.1 changes label parsing only (Dependabot, above). Unchanged since. |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. |
| `floki` (test only) | 0.38.4 (0.38.5; Dependabot #1392) | A test-only patch is taken by Dependabot's PR, not ahead of it; that PR is now open (above). |
| `lazy_html` (test only) | 0.1.13 (0.1.14, 2026-11-03) | The same reason as `floki`: a test-only patch, taken by Dependabot's PR when it opens (`phoenix_live_view` requires `~> 0.1.0`, so it is a lockfile line). |
| `fine` (transitive, under `lazy_html`) | 0.1.6 (0.2.0) | "Update not possible", `lazy_html` 0.1.13 pins it; it moves with `lazy_html`, if at all. |
| `websock_adapter`, `nimble_options` (transitive) | 0.6.0 (0.7.1, up from 0.7.0), 1.1.1 (1.2.0) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. |
| npm (mcp-server) | every direct dependency at its newest | `npm outdated` lists nothing: `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2, `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7, `typescript` 7.0.2, `tsx` 4.23.15, `@types/express` 5.0.6, `@types/node` 26.6.6 (the newest 26.x; a `@types/node` major beyond the Node 26 runtime is ignored by Dependabot, #728). `npm audit` reports 0 vulnerabilities. The companion image's `node:26.13.0-alpine3.24` digest (`c6ad9e9c…`) is still the tag's, and Dependabot watches `/mcp-server`'s Dockerfile. |
| npm (test/browser) | `playwright` 1.64.1, pinned exactly (Sprint 24 M1) | New this lane: `playwright` **1.65.0** became `latest` on 2026-11-05 (18:28 UTC, hours before this read). A test-only minor that also moves the Chromium CI's browser job installs; `test/browser` is watched by Dependabot weekly, so it is taken by Dependabot's PR, as `floki` is, not ahead of it. `npm audit` reports 0 vulnerabilities. |
| Elixir minors and majors (#727) | Elixir 1.19.7 (1.20.5 exists) | 1.19.7 is taken (M1, above). 1.20 stays blocked upstream: excoveralls 0.18.5 is still the newest release, and #727's Elixir half waits on one naming 1.20 cover support. |
| OTP 28 | OTP 27.3.4.19 (28.5.0.8 and 29.1.2 exist) | Waits on #727's OTP half (above): the Sprint 24 run of the trigger's own test was red, and nothing upstream has moved since. An OTP 28 move also needs the `@issuers` change in `logo_lookup.ex`. |
| BMAD core v7 | 6.12.4 (`latest`) | No 6.13 or 7.x is published or tagged; v7 is the preview on `main`. The core move, `tea` v3 and `bmb` v2 are one decision when a release ships (Sprint 24's M2, "When it comes back"). |
| BMAD `tea` v3.x | v1.27.3 pinned (latest v3.6.0, 2026-10-31) | Declined in Sprint 24 with the read's findings: no 2.x or 3.x installs through the pinned 6.12.4 installer, and every 2.x and 3.x requires the unreleased v7 core. The v1 line still ends at v1.27.3, so there is no patch to re-pin; no tag after v3.6.0. |
| BMAD `bmb` | v1.8.1 pinned (latest v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. Read beside tea's: the move belongs with the v7 core decision. The v1.8 line has no patch after v1.8.1. |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag, so there is nothing to take. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | The installer marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | Docker Hub's `18.6` index is now `bd5dfa49…` (rebuilt 2026-11-05), still PostgreSQL 18.6, as the last two reports read for earlier rebuilds. It serves CI's test database only and ships in no image, no security fix was read that forces it, and Dependabot does not watch the workflow's `services:`, so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). |
| Compose's database image digest | `postgres:18.6-alpine3.24@sha256:10a5c69a…` | New this lane: Docker Hub's `18.6-alpine3.24` index is now `8a334ab9…` (rebuilt 2026-11-05), the same PostgreSQL 18.6. Dependabot watches the Compose files (tag and digest together), so the rebuild is taken by its PR, and no security fix was read that forces it ahead. |
| PostgreSQL major | 18 (`18.6`, by digest) | No 18.7 exists; Docker Hub has `19rc1` tags, a release candidate, not a release; the major is pinned (Dependabot ignores PostgreSQL majors, and a major needs a dump and a restore). |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.19.7, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.19.7-erlang-27.3.4.19-debian-bookworm-20261104` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261104-slim`; Node 26 in CI (the companion's `engines`
  say `>=26 <27`); every image pinned by digest. The script could not read
  the OTP inside the build image (no Docker in the session); the tag names
  27.3.4.19.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement), `floki`, `lazy_html` and `sobelow` (above); `mix hex.audit`
  and `mix deps.audit` report nothing; `mix deps.unlock --check-unused` is
  clean.
- **npm:** mcp-server has no direct dependency behind; test/browser's
  `playwright` is one minor behind (1.65.0, released at lane time); `npm
  audit` reports 0 vulnerabilities in both.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`). Nothing moved.
- **The local toolchain** of the cloud session that ran this lane is OTP 27
  with Elixir 1.19.7, the pinned pair after M1.

## Gate results on the lane's head

Run on the lane's head (M1 and the Debian move, before this report's
commit) on 2026-11-05, local toolchain Elixir 1.19.7 / OTP 27, PostgreSQL
16, Node 22 (CI runs the companion on Node 26). Each exit status was read
directly, never through a pipe. No Hex dependency moved in this lane, so the
full `mix test`, `mix coveralls` and `mix dialyzer` run at the sprint's
integration, by the orchestrator; the Debian move touches only the two
Dockerfiles, whose pins `ci_test` reads.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --force --warnings-as-errors` | exit 0 |
| `mix gettext.extract --check-up-to-date` | exit 0 |
| `mix test` on the files that read the BMAD install and the CI pins (`docs_test`, `workflow_docs_test`, `dev_config_test`, `ci_test`, `scope_b3_dependency_classes_test`) | 139 tests, 0 failures |
| `mix credo --strict` | exit 0 |
| `mix sobelow --skip --exit` | exit 0 (on 0.16.0) |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | exit 0, no retired or advisory packages |
| `mix deps.audit` | exit 0, no vulnerabilities |
| `pre-commit run --all-files` | the four local hooks pass (invisible Unicode, tracked symlinks, the gate scripts' unit tests, Elixir formatting); the four hygiene hooks could not run through pre-commit, because the session's shell would not put the hashed `pre-commit-hooks` 6.0.0 install on `PATH`, so they ran from that install on the lane's three changed files: `trailing-whitespace-fixer`, `end-of-file-fixer` and `mixed-line-ending` exit 0 (no YAML changed, so `check-yaml` has nothing new to read). CI's `pre-commit` job runs all eight. |
| `npm test --prefix mcp-server` | 279 tests, 0 failures |
| `npm run build --prefix mcp-server` | exit 0 |
| `npm audit --audit-level=high --prefix mcp-server` | exit 0, 0 vulnerabilities |
| `npm audit --audit-level=high --prefix test/browser` | exit 0, 0 vulnerabilities |
