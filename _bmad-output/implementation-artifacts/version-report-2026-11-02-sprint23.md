# Version Report — 2026-11-02 (Sprint 23 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, on the sprint branch
right after M1 (the MCP SDK v2 move), in the lane's own worktree while Lane R
was built beside it (the Sprint 23 plan's Lane M). The lane reports what it
deliberately did not update and why. A row whose reasoning has not changed
since the last report carries that reasoning again, so this report reads on
its own. Commits are named by subject, because the branch's history is
cleaned before the merge and hashes change.

## Applied this lane

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| MCP SDK v2 (mcp-server), M1, #1115 | `@modelcontextprotocol/sdk` 1.32.2 → `@modelcontextprotocol/server` ^2.4.0 and `@modelcontextprotocol/node` ^2.1.2 (the HTTP transport's Node adapter); the tests' MCP host is `@modelcontextprotocol/client` ^2.4.0, a dev dependency | "test(mcp): pin the stdio surface an agent receives before the SDK v2 move"; "build(mcp): move the companion to the MCP SDK v2 server package"; "test(mcp): the schema budget measures the list the v2 SDK hands a client" | Sprint 22's report deferred the move to this lane (v1.x receives fixes until 2027-01-27 at the earliest; the plan's D-4). A golden file captured from the v1 build over stdio, under each profile, was committed first; on v2 every tool, prompt, instruction, answer and the handshake are byte for byte the v1 build's. Two refusals changed, and contract entry 23 says what an agent sees: an unknown prompt's message loses the `MCP error -32602: ` prefix, and a `tools/call` without params is -32602 "Invalid tools/call request: ..." where it was -32603. The schema budget now counts the list the v2 client receives: read 102,887, book 171,958, full 206,513 bytes, the v1 figures exactly, so the ceilings stay where they were (D-1 criterion 4). The companion still serves the 2025-era protocol through `server.connect`; serving 2026-07-28 is its own decision. The dependency allowlist and the outbound-chokepoint registry name the v2 packages (ADR-0002, NFR-9 B2). |
| Elixir, in every pinned place | 1.18.5 → 1.18.6 (OTP 27.3.4.19 and `bookworm-20261027` unchanged) | "build(toolchain): Elixir 1.18.5 -> 1.18.6 in every pinned place" | New this lane. 1.18.6 (2026-10-29) is a security patch: `URI.parse` bounds the port (CVE-2026-109821) and `JSON` refuses integers beyond the float64 range (CVE-2026-115274); its changelog names nothing else. The Hex team's `1.18.6-erlang-27.3.4.19-debian-bookworm-20261027` image and its `-slim` variant exist since 2026-10-29, on the OTP and Debian date the branch already pins, so the runtime stage does not move. One commit moves CI's `elixir-version` in its five jobs and the Dialyzer PLT cache key, the development image, the release's build stage, the cloud session's toolchain script with the archive's sha256, and the version the README and the development guide name. The sha256 of `elixir-otp-27.zip` is the one the GitHub release's `.sha256sum` asset and builds.hex.pm's `builds.txt` publish, recomputed from both downloads. Each image is pinned by its tag's index digest read from Docker Hub and confirmed by `mirror.gcr.io`'s `docker-content-digest`. `ci_test`'s toolchain parity test was seen failing on the PLT key with only CI's version moved. The gates below ran on 1.18.6. |

Every row is its own commit group, never mixed into a risk-tier story's
commits (ADR-0036 clause 1).

## Dependabot

One Dependabot PR was open at lane time (#1346); #1347 was closed as
superseded by `main` (the plan), and #1348 was taken in Sprint 22.

- **#1346** `sobelow` 0.16.0 → 0.18.0: **declined, with its findings.** The plan took it only if `mix sobelow --skip --exit` stayed green
  without a new skip. Re-read on 0.18.1, the newest 0.18.x (0.18.0 and
  0.18.1 were both published on 2026-10-29; `mix.exs` allows either, so the
  bump is a lockfile change only): the gate exits 1 with the same four
  findings Sprint 22 recorded, all `XSS.Raw` (low confidence) in
  `lib/portfolixir_web/live/securities_live.ex`, the `render_cell` clauses for
  the `:badge` (line 4425), `:code` (4437), `:money_signed` (4490) and
  `:percent_signed` (4517) render hints, which build a `<span>` or `<code>`
  around an interpolated value in `Phoenix.HTML.raw/1`. 0.16.0 does not flag
  that shape (exit 0, re-run after the trial). In each the interpolated value
  passes through `Phoenix.HTML.html_escape/1` and the class name comes from
  code, so none is an injection; but taking the bump needs either four new
  skips (a weakened gate, which the lane may not do) or a rewrite of the four
  clauses into HEEx, which is a change to a screen, not a version bump. The
  rewrite is already a line on the Securities polish list (#1365). The plan
  closes the PR with this finding, so it does not sit open a second sprint;
  Dependabot proposes the bump again once the clauses are HEEx.

No Dependabot PR remains that is neither taken nor a recorded decline.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.4** | npm: `bmad-method` 6.12.4 is still `latest` (2026-10-14), `next` is 6.12.3-next.1, no 7.x on npm; the repository's newest tag is v6.12.4 | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261027, with its image** | Docker Hub: `debian:bookworm-20261027` is the newest bookworm date | **No** |
| **An Elixir 1.18 patch after 1.18.5, with its image** | builds.hex.pm's Elixir build list; Docker Hub's `hexpm/elixir` tags | **Yes**, 1.18.6, taken (above). |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness | `mix hex.outdated --all`: ecto and ecto_sql up to date; Elixir 1.18.6's changelog names only the two security fixes | **No.** D-4 of Sprint 20 closed #727 as not planned and keeps this check here; a trigger firing opens a new issue for the move. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| `sobelow` (dev, test) | 0.16.0 (0.18.1 exists) | Declined with its findings (Dependabot, above). |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (its release notes name `div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, and new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins, as the plan says. |
| `floki` (test only) | 0.38.4 (0.38.5) | No Dependabot PR; a test-only patch is taken by Dependabot's PR, not ahead of it. |
| `websock_adapter` (transitive, under `phoenix`) | 0.6.0 (0.7.0) | A transitive minor with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. |
| `nimble_options` (transitive) | 1.1.1 (1.2.0) | New this lane, the same reason: a transitive minor with no advisory and no defect the app has met. |
| Transitive npm drift inside its ranges (mcp-server) | `npm outdated` lists no direct dependency behind | `npm audit` reports 0 vulnerabilities; the lanes take a transitive npm entry for an advisory, not for drift. |
| Elixir minors and majors (#727) | Elixir 1.18.6 (1.19.7 and 1.20.5 exist) | Both halves are blocked upstream (above). |
| BMAD `tea` | v1.27.2 pinned (latest v3.6.0, 2026-10-31) | **Two majors behind, read for the first time this lane.** 2.0.0 was published on 2026-10-09 and 3.0.0 on 2026-10-14; Sprint 20's report read v1.27.2 as the newest tag on 2026-10-09, and Sprints 21 and 22 kept the pin without re-reading the tags, so those reports missed both majors. The between-batches rule applies, plus a read of each major's changes, as for `bmb`, so it is its own decision; and a BMAD re-pin lands as a branch's first commit before any story is built, which a lane running beside Lane R is not. The candidate for the Sprint 24 planning session, read together with `bmb`. |
| BMAD `bmb` | v1.8.1 pinned (latest v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes, so it is its own decision. |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag, so there is nothing to take. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | BMAD's registry marks the module deprecated in favour of `bmad-loop`; replacing it changes how stories are run, a process decision for the owner, not a version bump. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | The tag was rebuilt again on 2026-10-31 (now `3a426452…` on Docker Hub and on `mirror.gcr.io`), still PostgreSQL 18.6. It serves CI's test database only and ships in no image, no security fix was read that forces it, and Dependabot has proposed nothing for it (it watches Compose, not the workflow's `services:`), so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). |
| PostgreSQL major | 18 (`18.6`, by digest) | No PostgreSQL 19 tag on Docker Hub at lane time. Compose's `18.6-alpine3.24` digest (`10a5c69a…`) is still the tag's, so there is nothing to take there either. |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.6, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.18.6-erlang-27.3.4.19-debian-bookworm-20261027` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261027-slim`; Node 26 in CI (`setup-node`'s major,
  newest 26.13.0 at lane time; the companion's `engines` say `>=26 <27`);
  every image pinned by digest. The script could not read the OTP inside the
  build image (no Docker in the session); the tag names 27.3.4.19.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement), `floki` and `sobelow` (above); `mix hex.audit` and
  `mix deps.audit` report nothing.
- **npm (mcp-server):** every direct dependency at its newest:
  `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2,
  `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7,
  `typescript` 7.0.2, `@types/node` 26.6.6; `npm audit` reports 0
  vulnerabilities.
- **BMAD install:** unchanged; the manifest says 6.12.4; core and bmm are
  6.12.4; tea v1.27.2, cis v0.3.2, bmb v1.8.1 pinned; automator tracks
  `main` (`0b94fd7`).
- **The local toolchain** of the cloud session that ran this lane is OTP
  27.3.4.19 with Elixir 1.18.5 installed; the lane ran its gates on Elixir
  1.18.6 from the verified archive, unpacked into the session's scratch
  space, so the shared installation other lanes compile with did not move.

## Gate results on the lane's head

Run on the lane's head (M1 and the Elixir move, before this report's commit)
on 2026-11-02, local toolchain Elixir 1.18.6 / OTP 27.3.4.19, PostgreSQL 16,
Node 22 (CI runs the companion on Node 26). Each exit status was read
directly, never through a pipe.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix gettext.extract --check-up-to-date` | up to date |
| `mix test` | 5505 tests, 9 properties, 0 failures |
| `mix coveralls` | 94.5 % total; 5505 tests, 9 properties, 0 failures |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 (on 0.16.0) |
| `mix dialyzer --format short` | 0 errors (PLT built fresh in the lane's worktree) |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 268 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |
