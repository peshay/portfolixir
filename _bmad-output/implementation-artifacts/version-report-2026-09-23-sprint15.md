# Version Report — 2026-09-23 (Sprint 15 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 15 plan's Lane M). The lane reports what it deliberately did
not update and why; a row whose reasoning is unchanged since the last report
carries that reasoning again rather than a cross-reference, so this report
reads on its own.

## Applied this batch

| What | From → to | Why now |
| --- | --- | --- |
| CI: the npm audit gate's position in the `quality` job | before `Setup Node` → after it | **D-7**, below. The gate now reads through the pinned Node 24 toolchain's npm instead of the runner image's. Level unchanged (`--audit-level=high`), no failure allowance; a CI test pins the order and the level. |

No package moved: at lane time every Hex dependency, direct and transitive, is
*Up-to-date* (`mix hex.outdated --all` lists nothing outdated), and the one
outdated npm package is held on purpose (below). The change lands as the
lane's own commit, never mixed into a feature story (ADR-0036 clause 1).

## D-7: what turned the npm audit red on CI 1558

The plan asked the lane to establish which of two readings was true: an
advisory published after the merge, or the registry endpoint. The failed log of
CI 1558 (`quality`, run 35892956461) answers it:

```text
npm notice This endpoint is being retired. Use the bulk advisory endpoint instead.
npm warn audit 400 Bad Request - POST https://registry.npmjs.org/-/npm/v1/security/audits/quick - Bad Request
  message: 'Invalid package tree, run  npm install  to rebuild your package-lock.json'
npm error audit endpoint returned an error
```

The request that failed went to the **quick** audit endpoint — npm's fallback
path, the one the registry itself says it is retiring — and the answer was a
400, not a finding. And the step ran **before `Setup Node`**, so on whatever
npm the `ubuntu-latest` image shipped that day: the one unpinned toolchain left
in the job, which #728 had pinned for every other companion gate. The Sprint 14
close-out's reading (an advisory, fixed by the SDK patch) does not match the
log; the SDK patch was real and harmless, but it was not what went red.

The fix is where the plan put it: make the gate read the right endpoint, never
make it optional. The step now runs after `Setup Node` (Node 24, npm 11, the
bulk endpoint first), still at `--audit-level=high`. What it cannot promise:
npm 11 still falls back to the quick endpoint when the bulk request fails, so a
registry outage can still turn the gate red. That red is honest — the audit did
not run — and is cleared by a re-run, not by a lowered level.

## Dependabot

No Dependabot PR is open for this lane at lane time. The Node 26 image bump
Sprints 11, 12 and 13 closed (#774, #782, #819) has not been reopened; its
trigger is re-checked below regardless, because it is a calendar event
Dependabot cannot see.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 (2025-01-26) is still the newest release | **No** |
| **#727, OTP half:** an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness | ecto 3.14.2 (2026-08-14, already in the lock) and ecto_sql 3.14.0 (2026-05-19) are still the newest releases | **No** |
| **CVE-2026-75758 patch (Sprint 14's security note):** an official `elixir:1.18.5` image | Docker Hub's tag search for `1.18.5` returns no result, and `elixir:1.18.5-otp-27` does not resolve; `1.18.4-otp-27` and `1.19.6-otp-27` do | **No** — the plan's condition for a patch-bump commit ("if an official 1.18.5 image tag exists now") does not hold |
| **Node 26 LTS promotion (#728's pin)** | nodejs.org release index: 26.10.0 (2026-09-21) is still **Current**, not LTS; 24.21.0 (2026-09-07) is still the newest Active LTS (Krypton) and is what the image already runs | **No** — declined a fifth time, same reason: the promotion is scheduled for October 2026. When it lands the runtime moves in all four pinned places in one commit, with the `@types/node` major that follows it |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Node runtime major | 24 (image `24.21.0-alpine3.24`) | Node 26 is **Current**, not LTS, until **October 2026**, and the runtime is pinned in four places by an invariant test (#728). The trigger is the LTS promotion; checked on 2026-09-23 and it has not landed. |
| `@types/node` major (mcp-server) | 24.13.6 (latest 26.6.2) | The types follow the pinned Node 24 runtime (Sprint 8 decision; the Dependabot ignore is major-wide). They move when the runtime moves; moving them first would type-check the companion against a runtime it does not run on. 24.13.6 is the newest 24.x. |
| Elixir / OTP (#727) | 1.18.3 / 27 | Both halves still blocked upstream (triggers above). The move stays its own branch and PR: it moves the CI version pins, the Dockerfile base image and the Dialyzer PLT cache key together, and CI compiles with `--warnings-as-errors`, so two Elixir minors of deprecations are a body of work rather than a version-string edit. |
| Elixir patch for CVE-2026-75758 | 1.18.3 (fixed in 1.18.5 / 1.19.6 / 1.20.4) | Unchanged since Sprint 14 and re-measured: every `List.to_string/1` / `to_charlist` call in `lib/` still takes a charlist the code built itself from a binary, so the trigger (an *invalid* charlist) is not reachable from input. The patch cannot move the four places together — there is still no official `1.18.5` image — and a 1.19.6 step is #727's decision, not maintenance. Recorded again as input to #727's next re-check: 1.19.6 has an official image. |
| Dockerfile `HEX_VERSION` | 2.4.2 (local Hex 2.5.1) | The image pin reproduces the image; the advisory gate runs in CI against the current Hex, so nothing in this batch sits behind the pin. |
| PostgreSQL image | `postgres:18-alpine` (CI `postgres:18`) | 18 is the current major and the floating tag resolves to **18.6**, its newest patch (read from the image itself this lane). 19 exists only as `19beta3`; a beta is not a candidate for a self-hosted instance's data directory. |
| BMAD core/bmm | 6.11.0 (latest 6.12.0, npm `bmad-method`, 2026-09-05) | Sprint 14 named it a candidate for this lane. Declined inside the batch for the reason that made it a candidate: re-pinning runs the installer, which rewrites `_bmad/` and the workflows this batch's closing act is about to run under. The re-pin is the **first commit of the Sprint 16 branch**, before any lane starts, so a batch is never reviewed under a process that changed halfway. |
| BMAD `tea` | v1.19.0 pinned (latest tag v1.27.2) | Same between-batches reason, and eight minors is a re-install with a read of what changed in the test-architecture workflows. Rides the Sprint 16 opening re-pin. |
| BMAD `cis` | v0.2.1 pinned (latest tag v0.3.2) | Same reason; a 0.x minor may break. Rides the Sprint 16 opening re-pin. |
| BMAD `bmb` | v1.8.1 pinned (latest tag v2.2.2) | A **major** behind: the between-batches rule plus a read of the major's changes; its own decision, not part of the opening re-pin. |
| BMAD `automator` | `main` at `0b94fd7` | Current: `git ls-remote` shows the recorded SHA is still the head of `main`. |

## A tool this lane could use for the first time

The Docker daemon could be started in this session (earlier lanes had none),
which let Lane D3 run the backup/restore procedure against the shipped
`docker-compose.yml` for real. Docker Hub rate-limited the anonymous pull
(HTTP 429); the `postgres:18-alpine` image came through `mirror.gcr.io`, the
same image. The release image itself was not built: the lane changed nothing
the image contains.

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.3, OTP 27,
  `elixir:1.18.3-otp-27`, `postgres:18-alpine` (18.6; CI `postgres:18`),
  Node 24 (`node:24.21.0-alpine3.24`).
- **Hex:** every dependency *Up-to-date* (`mix hex.outdated --all`).
  `mix hex.audit`: no retired packages, no advisories. `mix deps.audit`: no
  vulnerabilities. `mix deps.unlock --check-unused`: no unused entries.
- **npm (mcp-server):** `npm audit`: 0 vulnerabilities at any level. One
  outdated package, `@types/node`, held at 24.x on purpose (above).
- **BMAD install:** manifest 6.11.0 with the four external modules at the SHAs
  the report script lists.

## Gate results on the lane's head

Run on the batch's head carrying every lane (A–D, M), local toolchain Elixir
1.18.3 / OTP 27.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` (dev and test) | clean |
| `mix test` | 2563 tests, 9 properties, 0 failures (after the fix below) |
| `mix coveralls` | 92.3 % total |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 |
| `mix dialyzer --format short` | passed successfully, no warnings (after the fix below) |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 95 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |

**Two reds this pass caught, both in this batch's own code, both fixed before
the report was written:** Dialyzer named an unknown type in the settlement
form's new spec (`Transaction.t/0` does not exist; the spec now names the
struct), and the localisation meta-test (issue 636) caught the plan editor's
"Positions (n)" counting through `gettext` instead of `ngettext`. CI on the D3
head had gone red on the same two; the local run reproduced both before the
fix and passes after it.

**Node version.** The local Node is 22, not the pinned 24, so the companion's
gates above ran on an older runtime than CI's. CI's `Setup Node` step (Node 24)
is the authoritative run for them — and, since D-7, for the npm audit too.
