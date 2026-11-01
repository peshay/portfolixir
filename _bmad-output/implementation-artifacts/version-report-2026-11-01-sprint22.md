# Version Report — 2026-11-01 (Sprint 22 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, right after Lane F and
before Lane R (the Sprint 22 plan's Lane M). The lane reports what it
deliberately did not update and why. A row whose reasoning has not changed
since the last report carries that reasoning again, so this report reads on
its own. Commits are named by subject, because the branch's history is
cleaned before the merge and hashes change.

## Applied this lane

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| BMAD core and method | 6.12.1 → 6.12.4; `tea` v1.27.2, `cis` v0.3.2, `bmb` v1.8.1 kept pinned; `automator` on `next` at `0b94fd7`, unchanged | "chore(bmad): BMAD re-pinned from 6.12.1 to 6.12.4, with the module set the manifest records" | Sprint 21's report deferred the re-pin to this branch's first commit after Lane F, so no story is built under a process that changes halfway. The install answers are the recorded ones (the installer's defaults would have overwritten them; the second run restored them). The upstream diff that survives the line-ending hook is a UTF-8 guard in six scripts and the regenerated config headers. |
| `pre-commit-hooks` (the pinned hook requirements group) | 5.0.0 → 6.0.0 | "chore(ci): pre-commit-hooks 5.0.0 -> 6.0.0 in the pinned hook requirements" | Dependabot #1348. The four hooks the repository runs from it as local system hooks exist unchanged in 6.0.0; the wheel's sha256 read from PyPI matches the PR's; `pre-commit run --all-files` passes on it. |
| `@types/node` (mcp-server) | 26.6.5 → 26.6.6 | "chore(deps): @types/node 26.6.5 -> 26.6.6 in the companion" | Dependabot #1347. The major follows the pinned Node 26 runtime (the Sprint 8 decision). |
| OTP and the Debian date, in every pinned place | OTP 27.3.4.18 → 27.3.4.19; `bookworm-20261005` → `bookworm-20261027` | "chore(toolchain): OTP 27.3.4.18 -> 27.3.4.19 and Debian bookworm 20261005 -> 20261027, in every pinned place" | The plan took both only if a `hexpm/elixir` 1.18.5 image on them existed; Docker Hub carries `1.18.5-erlang-27.3.4.19-debian-bookworm-20261027` and its `-slim` variant since 2026-10-28. (Sprint 21's report read none on 27.3.4.19; the tag list shows images on it from 2026-10-14, so that reading missed them.) One commit moves CI's `otp-version` in its five jobs and the Dialyzer PLT cache key, the development image, the release's build stage, its runtime stage (`debian:bookworm-20261027-slim`, so the three Debian dates stay equal as `ci_test` requires) and the cloud session's toolchain script with the OTP archive's sha256 from builds.hex.pm. Every image is pinned by the tag's index digest read from Docker Hub. |

Every row is its own commit, never mixed into a risk-tier story's commits
(ADR-0036 clause 1).

## Dependabot

Three Dependabot PRs were open at lane time (#1346, #1347, #1348). Two are
taken (above) and one is declined:

- **#1346** `sobelow` 0.16.0 → 0.18.0: **declined, with its findings.** The
  plan took it only if `mix sobelow --skip --exit` stayed green without a
  new skip. Under 0.18.0, and under 0.18.1 (published since), the gate
  exits 1 with four new findings, all `XSS.Raw` (low confidence) in
  `lib/portfolixir_web/live/securities_live.ex`: the `render_cell` clauses
  for the `:badge`, `:code`, `:money_signed` and `:percent_signed` render
  hints, which build a `<span>` or `<code>` around an interpolated value in
  `Phoenix.HTML.raw/1`. 0.16.0 did not flag that shape. In each the
  interpolated value passes through `Phoenix.HTML.html_escape/1` and the
  class name comes from code, so none is an injection; but taking the bump
  needs either four new skips (a weakened gate, which the lane may not do)
  or a rewrite of the four clauses into HEEx, which is a change to a
  screen, not a version bump. The rewrite is a line on the Securities
  polish list's next pass; the PR stays open, as the plan says of a bump
  the lane does not take.

No Dependabot PR remains that is neither taken nor a recorded decline.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.1** | npm: `bmad-method` 6.12.4 is `latest` (2026-10-14); `next` is 6.12.3-next.1 | **Yes**, taken (above). The installer announces a v7 preview with a v6-to-v7 migration in beta; a beta migration is not a re-pin, and the next lane re-reads it. |
| **An OTP 27 patch after 27.3.4.18, with its image** | Docker Hub's `hexpm/elixir` tags; builds.hex.pm's OTP build list | **Yes**, taken (above). |
| **A Debian bookworm date after 20261005, with its image** | Docker Hub: `bookworm-20261027` for both `debian` and `hexpm/elixir` 1.18.5 on 27.3.4.19 | **Yes**, taken (above). |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness | `mix hex.outdated --all`: ecto and ecto_sql up to date | **No.** D-4 of Sprint 20 closed #727 as not planned and keeps this check here; a trigger firing opens a new issue for the move. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `sobelow` (dev, test) | 0.16.0 (0.18.1 exists) | Declined with its findings (Dependabot, above). |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (its release notes name `div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, and new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins, as the plan says. |
| `floki` (test only) | 0.38.4 (0.38.5) | No Dependabot PR; a test-only patch is taken by Dependabot's PR, not ahead of it. |
| `websock_adapter` (transitive, under `phoenix`) | 0.6.0 (0.7.0) | A transitive minor with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. |
| Transitive npm drift inside its ranges (mcp-server) | `npm outdated` lists no direct dependency behind | `npm audit` reports 0 vulnerabilities; the lanes take a transitive npm entry for an advisory, not for drift. |
| MCP SDK v2 (mcp-server) | `@modelcontextprotocol/sdk` 1.32.2 | v1.x receives fixes until 2027-01-27 at the earliest; the move is a package migration, tracked by #1115 for Sprint 23's maintenance lane (the plan's D-4). |
| Elixir minors and majors (#727) | Elixir 1.18.5 | Both halves are blocked upstream (above). |
| BMAD `bmb` | v1.8.1 pinned | A major behind; the between-batches rule applies, plus a read of the major's changes, so it is its own decision. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` | BMAD's registry marks the module deprecated in favour of `bmad-loop`; replacing it changes how stories are run, a process decision for the owner, not a version bump. |
| PostgreSQL major | 18 (`18.6`, by digest) | No 19 release beyond its release candidates at lane time. |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.5, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.18.5-erlang-27.3.4.19-debian-bookworm-20261027` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261027-slim`; Node 26 unchanged; every image pinned by
  digest.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement), `floki` and `sobelow` (above); `mix hex.audit` and
  `mix deps.audit` report nothing.
- **npm (mcp-server):** `npm audit` reports 0 vulnerabilities.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.2, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`).
- **The local toolchain** of the cloud session that ran this lane is OTP
  27.3.4.18 (installed before the script's pin moved); CI runs 27.3.4.19.

## Gate results on the lane's head

Run on the lane's head (Lane F and Lane M, before Lane R) on 2026-11-01,
local toolchain Elixir 1.18.5 / OTP 27.3.4.18, PostgreSQL 16, Node 22 (CI
runs OTP 27.3.4.19 and the companion on Node 26).

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix gettext.extract --check-up-to-date` | up to date |
| `mix test` | 5381 tests, 9 properties, 0 failures |
| `mix coveralls` | 94.4 % total; one failure, `CITest` "the committed BMAD config carries the user-scope defaults…", whose `git check-ignore` exited 128 while another worktree of the same repository was committing; the test passes on its own re-run, and in the `mix test` run above |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 (on 0.16.0) |
| `mix dialyzer --format short` | 0 errors |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass (on pre-commit-hooks 6.0.0) |
| `npm test --prefix mcp-server` | 263 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |
