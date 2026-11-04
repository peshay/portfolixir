# Version Report — 2026-11-05 (Sprint 24 maintenance lane, the sprint PR)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, on the sprint branch
right after M1 (the CI browser job), in the lane's own worktree (the Sprint 24
plan's Lane M, M2 and M3). The lane reports what it deliberately did not
update and why. A row whose reasoning has not changed since the last report
carries that reasoning again, so this report reads on its own. Commits are
named by subject, because the branch's history is cleaned before the merge
and hashes change.

## Applied since the last report

| What | From → to | Commit | Why now |
| --- | --- | --- | --- |
| `ecto` (transitive, under `ecto_sql`), #1381 through #1383, release **2026.11.8** | 3.14.2 → 3.14.3 | "chore(deps): ecto 3.14.2 -> 3.14.3 for EEF-CVE-2026-118391 (#1381)", on `main` before this branch | Taken on `main` between the sprints, not in this lane: `mix hex.audit` and `mix deps.audit` turned red on `main` on 2026-11-04 with nobody pushing (CI 1864 on `1702757`, `advisories`), for a new HIGH advisory on 3.14.2 (EEF-CVE-2026-118391, unbounded query-cache growth from interpolated JSON paths, `splice/1` and `constant/1`). 3.14.3, released the same day, is a patch; `ecto_sql` 3.14.0 accepts it, so the bump is a lockfile line. Its changelog (in `deps/ecto`) lists four `Ecto.Query` fixes: the join query's prefix in the cache key, the join's hints kept, no caching of the three interpolation shapes (the advisory), and interpolated true filters kept for a later `or_where`. `lib/` uses neither `json_extract_path` nor `splice`, so the bump is for the gate and the advisory, with no code change. CI 1865 on `02d7336` was green; the release 2026.11.8 carries it. No entry names Dialyzer or opaqueness, which is #727's OTP question (below). |
| BMAD `tea`, M3 | v1.27.2 → v1.27.3 (tag `c3d4f34`, 2026-10-22), still pinned | "chore(bmad): tea re-pinned from v1.27.2 to v1.27.3, the v1 line's last patch (M3)" | New this lane, found while reading M2's tags: a patch on the v1 line that Sprint 23's report did not list. Its one fix is the handoff this repository runs: ATDD names `bmad-build` instead of the `create-story` and `dev-story` skills BMAD 6.12 ships only as deprecated shims, and its help row moves to follow `bmad-sprint-planning` and precede `bmad-build`. Run through the official installer at the pinned core, `npx bmad-method@6.12.4 install --directory . --action update --modules bmm,tea,cis,automator,bmb --tools claude-code --pin tea=v1.27.3 --pin cis=v0.3.2 --pin bmb=v1.8.1 --next automator --shims --user-name <user_name> --communication-language <communication_language> --document-output-language English -y`, the two placeholders filled from `_bmad/core/config.yaml` (exit 0). The recorded answers are passed explicitly, because the installer's defaults overwrite them (a first trial without them wrote `user_name: BMad` and `communication_language: English`, as Sprint 22's re-pin saw). The installer also adds trailing newlines and CRLF to fifteen skill files the hooks had normalized; `pre-commit` restores them, so the commit is four ATDD files, the two help rows, the manifest's version and sha, the hashes and the dates. The gitignored `config.user.toml` it seeds was removed. A re-pin lands before any story is built; Lane M is the branch's first lane and M2 planned a tea change here. |

Every row is its own commit group, never mixed into a risk-tier story's
commits (ADR-0036 clause 1).

## M2: BMAD `tea` v3.x, read with bmb first — declined

The plan's M2 (D-7): take `tea` v1.27.2 → the newest v3.x "if every
reference resolves and the install is clean; declined with the read's
findings otherwise". The newest v3 is **v3.6.0** (tag `a2819f6`,
2026-10-31; npm `bmad-method-test-architecture-enterprise` 3.6.0). The read
went over the repository at v3.6.0 against v1.27.2 with bmb's Validate
Module checks (structure, the skill list against the module's registry,
every cross-reference resolving) and a trial install in a scratch copy of
the tree.

**Verdict: declined. The install is not clean; it does not run.** The
pinned installer refuses the module:

```text
npx bmad-method@6.12.4 install --directory . --action update \
  --modules bmm,tea,cis,automator,bmb --tools claude-code \
  --pin tea=v3.6.0 --pin cis=v0.3.2 --pin bmb=v1.8.1 --next automator --shims -y
x  Installation failed: Module 'tea' was downloaded but its module definition
   was not found. Expected 'src/module.yaml' to exist in version v3.6.0, but it
   is missing. The repository may have been restructured after this release
   was tagged.
```

The findings, in the order they decide:

1. **tea left the classic installer at 2.0.0.** Its 2.0.0 changelog: "TEA
   is a bmod: `bmad setup tea` sets it up, replacing the classic
   installer"; `src/module.yaml` and `src/module-help.csv` are removed, and
   the module is `skills/bmod-tea/bmod.toml` plus a member `bmod.toml` per
   skill. Every tag from v2.0.0 to v3.6.0 has that shape and no
   `src/module.yaml`, so **no 2.x or 3.x installs through bmad-method
   6.12.4**, the core the manifest pins. The v1 line ends at v1.27.3
   (taken above).
2. **It requires an unreleased core.** Every 2.x and 3.x `bmod.toml` says
   `required_skills = [{ skill = "bmad", version = "6.13.0-next", ... }]`:
   the v7 `bmad` skill (`bmod-core-tools`, `version = "6.13.0-next"` on
   BMAD-METHOD's `main` at `022be93`, 2026-11-02). npm's `bmad-method` is
   still `latest` 6.12.4 and `next` 6.12.3-next.1; no 6.13 or 7.x is
   published or tagged. The 6.12.4 installer itself says v7 is a preview
   ("`bmad migrate` tests the v6 to v7 migration (still in beta)"). Taking
   tea v3 therefore means moving the whole BMAD install to the v7 preview
   (`npx skills add bmad-code-org/BMAD-METHOD`, `bmad setup`, `bmad
   migrate`), which changes how every story is planned and built (v7
   tickets, `tickets.py`, a Product Owner agent `bmad-agent-po` that tea's
   red-mode checklist already names). That is a process decision for the
   owner, not a module bump.
3. **The renames (3.0.0) and removals (2.0.3).** 3.0.0: "TEA 3.0 publishes
   all eight direct workflows as `bmad-tea-*` commands. The former
   `bmad-testarch-*` and `bmad-teach-me-testing` commands are removed."
   2.0.3 removed ATDD and CI as skills ("Automate handles red acceptance
   tests and Framework handles CI setup"; the Murat agent keeps the `AT`
   and `CI` menu codes). What a `.claude/skills` reinstall would change:

   | Installed today (v1.27.x) | At v3.6.0 |
   | --- | --- |
   | `bmad-tea` (Murat) | `bmad-tea`, kept |
   | `bmad-teach-me-testing` | renamed `bmad-tea-teach-me-testing` |
   | `bmad-testarch-atdd` | **removed**; red mode of `bmad-tea-automate` |
   | `bmad-testarch-automate` | renamed `bmad-tea-automate` (red and expand modes) |
   | `bmad-testarch-ci` | **removed**; the CI scope of `bmad-tea-framework` |
   | `bmad-testarch-framework` | renamed `bmad-tea-framework` |
   | `bmad-testarch-nfr` | renamed `bmad-tea-nfr` |
   | `bmad-testarch-test-design` | renamed `bmad-tea-test-design` |
   | `bmad-testarch-test-review` | renamed `bmad-tea-test-review` |
   | `bmad-testarch-trace` | renamed `bmad-tea-trace` |
   | — | **new** `bmad-tea-evaluate` (Evaluate, menu `EV`) |
   | — | **new** `bmod-tea` (the module's record and the one knowledge base; "never invoke") |

   Nine skill folders go and ten come. `_bmad/tea/config.yaml` and
   `_bmad/tea/module-help.csv` retire (tea's `migration-1.toml` offers to
   delete them; settings move to `[modules.tea]` in `_bmad/config.toml`);
   the nine per-skill `resources/knowledge` copies become one under
   `bmod-tea/knowledge`.
4. **What the repository references: nothing that would break.** No tea
   skill name (`bmad-testarch-*`, `bmad-teach-me-testing`, `bmad-tea`) or
   `_bmad/tea` path appears in `AGENTS.md`, `docs/` (with
   `docs/development/*`), `CONTRIBUTING.md`, `README.md`, `_bmad/custom/`,
   `.claude/commands`, `.claude/scripts`, `.github/`, `scripts/`, `lib/` or
   `test/`. The references that exist are the installer's own output
   (`_bmad/_config/bmad-help.csv`, `skill-manifest.csv`,
   `files-manifest.csv`, `_bmad/config.toml`'s `[agents.bmad-tea]`), which
   an install regenerates, and two labels in the automator
   (`testarch_automate_workflow_paths` and the stop-hook table's
   `testarch-automate` row), whose `auto` step runs bmm's
   `bmad-qa-generate-e2e-tests`, not a tea skill. `_bmad/custom/` holds no
   `bmad-testarch-*.toml`, so `tea-migrate-customizations` would have
   nothing to move and v3's activation guard (it stops when a legacy
   customization file exists) would not fire. Point 4 alone would have let
   the bump through; points 1 and 2 stop it.
5. **bmb's check over v3.6.0.** Inside its own format the module is
   consistent: the nine skills `bmod.toml` lists are exactly the nine skill
   folders beside `bmod-tea`, each member `bmod.toml` names `bmod-tea` and
   the module's source, the roster has Murat, and every `bmad-tea-*` name
   the skills cite exists. The names they cite that do not resolve here are
   v7's (`bmad-agent-po`, the `bmad` skill, `tickets.py`) and the
   transition names (`bmad-tea-atdd` and `bmad-tea-ci` as customization file
   names, `bmad-testarch-*` in the migration guards). The bmb v1.8.1
   `validate-module.py` script exits `fail` ("No setup skill found
   (*-setup directory) and no standalone module detected") on v3.6.0 and
   on v1.27.2's `src/` alike: it checks the setup-skill and standalone
   shapes bmb v1 builds, not a classic-installer module or a bmod, so its
   verdict decides nothing here and the checks were applied by reading the
   files, as the Validate Module procedure allows when the script does not
   fit.

**When it comes back:** with a BMAD core release that ships the `bmad` skill
the bmods require (6.13 or 7.0 on npm's `latest`), as one decision: the core
move, tea v3 and `bmb` v2 (a major behind, below) together, on a branch's
first commits. The renames above are then a regenerated install, not a
documentation change, since nothing outside the install names a tea skill.

## Dependabot

The lane read Dependabot's state from the plan, not from GitHub (the lane
does not touch GitHub). The plan names no open Dependabot PR; #1381 was
closed by #1383 (above), and #1346 (`sobelow`) was closed with its findings
in Sprint 23. `test/browser/package.json` (M1's Playwright pin) is watched
from this sprint on.

## Triggers re-checked at lane time

| Trigger | Checked against | Fired? |
| --- | --- | --- |
| **A BMAD release since 6.12.4** | npm: `bmad-method` 6.12.4 is still `latest` (2026-10-14), `next` is 6.12.3-next.1; the method repository's newest tag is v6.12.4. v7 exists only as the preview on `main` (`bmod-core-tools` 6.13.0-next) | **No** |
| **An OTP 27 patch after 27.3.4.19, with its image** | builds.hex.pm's OTP build list for ubuntu-24.04: 27.3.4.19 (2026-10-14) is the newest 27 patch | **No** |
| **A Debian bookworm date after 20261027, with its image** | Docker Hub: `debian:bookworm-20261027` is the newest bookworm date | **No** |
| **An Elixir 1.18 patch after 1.18.6, with its image** | builds.hex.pm's Elixir build list: 1.18.6 (2026-10-29) is the newest 1.18; `hexpm/elixir`'s newest 1.18.6 tags are the `bookworm-20261027` pair the branch pins | **No** |
| **#727, Elixir half:** an excoveralls release naming Elixir 1.20 cover support | hex.pm: excoveralls 0.18.5 is still the newest release | **No** for 1.20. The half was only ever tested at 1.20.x, so M4 tried **1.19.7** once (below): it builds and passes every CI check, but not as the mechanical three-place bump, so it is filed as **#1390**, not taken in this lane. |
| **#727, OTP half:** an Ecto or Elixir release that reconciles `Ecto.Multi`/`MapSet` opaqueness, tested as "a `mix dialyzer` on an OTP 28+ PLT comes back clean" (D-7) | ecto 3.14.3's changelog (no opaqueness entry; `ecto_sql` unchanged at 3.14.0); **and the trigger's own test, run once**: OTP 28.5.0.8 from builds.hex.pm (sha256 checked against `builds.txt`), unpacked into the session's scratch space with its own `MIX_HOME` and Elixir 1.18.6 (no `-otp-28` build of 1.18.6 exists; the `otp-27` build runs on 28) | **No; the test ran and is red.** (1) The code base does not compile on OTP 28 with Elixir 1.18.6: `lib/portfolixir/catalog/logo_lookup.ex:242` fails with "cannot inject attribute @issuers into function/macro because cannot escape #Reference<...>", because OTP 28 compiles a regex to a reference and `@issuers` holds regexes inside a list of tuples (the top-level `@x ~r/.../` attributes elsewhere compile). (2) With that one attribute turned into a private function in the scratch copy only (nothing in the branch changed), `mix compile` is clean and `mix dialyzer --format short` on a fresh `erlang-28.5.0.8_elixir-1.18.6` PLT exits 2: **117 errors in 29 files, every one an opaqueness mismatch** (113 `call_without_opaque`, 4 `call_with_opaque`): about 90 on `Ecto.Multi` (`run` 27, `update` 26, `insert` 23, `delete` 14, `prepend` 2) and the rest on `MapSet` (`member?` 7, `union`, `size`) and a few callers of both, which is the `Ecto.Multi`/`MapSet` opaqueness #727 named. So the trigger has not fired, now by its own test, not only by the changelog read. The scratch install was removed; an OTP 28 move needs both an upstream fix and the `@issuers` change. |

## M4: one attempt at Elixir 1.19.x (#727's closing note)

The orchestrator ran M4 on scratch branch `agent/claude/sprint-24-elixir-1.19`
as scratch PR #1389 (closed unmerged): Elixir 1.18.6 → **1.19.7**, OTP
27.3.4.19 unchanged, with CI's pins, the Dockerfile and the PLT key moved
together.

| Run | Result |
| --- | --- |
| 1 | `pre-commit` red: the 1.19 formatter lays out three files differently (`lib/portfolixir/imports/correction.ex`, `test/portfolixir/imports/cash_correction_test.exs`, `test/portfolixir/imports/import_hash_reimport_test.exs`). |
| 2 | `quality` red at `mix compile --force --warnings-as-errors`: two "a struct for Portfolixir.Imports.Applier.Result is expected on struct update" warnings, in `applier.ex`'s `enrich_after_commit/1` (line 1271) and `resolve_portfolio/2` (line 1320). |
| 3 | With both matched as `%Result{}`: all eleven checks green on `e9a6748` (test, quality with Dialyzer, browser, advisories, compose-smoke, migrations). |

**Verdict: not taken in this lane.** The plan takes the move in Lane M
only if it is the mechanical three-place bump and nothing else; this one
also needs a formatter pass over three files and two pattern changes in
the import applier, which is code under review, not a version bump. So
1.19.x is a real move, not a blocked trigger, and the move is filed as
**#1390** (`agentic`, under #420) to be built as its own reviewed change.

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| BMAD `tea` v3.x | v1.27.3 pinned (latest v3.6.0, 2026-10-31) | Declined with the read's findings (M2, above): no 2.x or 3.x installs through the pinned 6.12.4 installer, and every 2.x and 3.x requires the unreleased v7 core. |
| `sobelow` (dev, test) | 0.16.0 (0.18.1 exists) | Declined in Sprint 23 with its findings: 0.18.x flags four `XSS.Raw` (low confidence) in `securities_live.ex`'s `render_cell` clauses, which escape their value, so taking it needs four new skips (a weakened gate) or a rewrite into HEEx, a screen change on the Securities polish list (#1365). Unchanged since. |
| `decimal` | 3.1.2 (3.2.0; Dependabot #1279) | `mix hex.outdated` reads "Update not possible": `mix.exs` requires `~> 3.1.2`, the floor T-11's hotfix set for the advisory fix (H28). 3.2.0 changes division and rounding results (`div/2` rounding fixes affecting about 5 % of random divisions at the default precision, a carry fix in rounding, new `:subnormal` and `:clamped` signals), and `Decimal` is the money type (ADR-0003). It stays declined until its own reviewed bump on a quiet branch, read against the identities the ledger pins. |
| `floki` (test only) | 0.38.4 (0.38.5) | No Dependabot PR; a test-only patch is taken by Dependabot's PR, not ahead of it. |
| `lazy_html` (test only) | 0.1.13 (0.1.14, 2026-11-03) | New this lane, the same reason as `floki`: a test-only patch, taken by Dependabot's PR when it opens (`phoenix_live_view` requires `~> 0.1.0`, so it is a lockfile line). |
| `fine` (transitive, under `lazy_html`) | 0.1.6 (0.2.0) | New in the listing: "Update not possible", `lazy_html` 0.1.13 pins it; it moves with `lazy_html`, if at all. |
| `websock_adapter`, `nimble_options` (transitive) | 0.6.0 (0.7.0), 1.1.1 (1.2.0) | Transitive minors with no advisory and no defect the app has met; the lanes take a transitive entry for an advisory, not for drift. |
| npm (mcp-server) | every direct dependency at its newest | `npm outdated` lists nothing: `@modelcontextprotocol/server` 2.4.0, `@modelcontextprotocol/node` 2.1.2, `@modelcontextprotocol/client` 2.4.0, `express` 5.3.0, `zod` 4.6.7, `typescript` 7.0.2, `tsx` 4.23.15, `@types/express` 5.0.6, `@types/node` 26.6.6 (the newest 26.x; a `@types/node` major beyond the Node 26 runtime is ignored by Dependabot, #728). `npm audit` reports 0 vulnerabilities. |
| npm (test/browser) | `playwright` 1.64.1, pinned exactly (M1) | `npm outdated` lists nothing: 1.64.1 is `latest` (2026-10-14); 1.65.0 is a beta and 1.66.0 an alpha. |
| Elixir minors and majors (#727) | Elixir 1.18.6 (1.19.7 and 1.20.5 exist) | 1.20 stays blocked upstream (above). 1.19.7 is no longer blocked but is not taken here: M4's attempt (below) needed code changes beyond the three pinned places, so the plan files it as #1390 instead of taking it in Lane M. This lane does not move Elixir or OTP. |
| OTP 28 | OTP 27.3.4.19 (28.5.0.8 and 29.1.2 exist) | Waits on #727's OTP half (above). |
| BMAD `bmb` | v1.8.1 pinned (latest v2.2.2, unchanged since Sprint 20) | A major behind; the between-batches rule applies, plus a read of the major's changes. Read beside tea's: the move belongs with the v7 core decision (M2's "When it comes back"). |
| BMAD `cis` | v0.3.2 pinned | Still the newest tag, so there is nothing to take. |
| BMAD `automator` | `main` at `0b94fd7`, channel `next` (`main`'s head is still `0b94fd7`) | The installer again marks it deprecated in favour of BMad Loop (`bmad-loop`); replacing it changes how stories are run, a process decision for the owner, not a version bump. |
| CI's database image digest | `postgres:18.6@sha256:5a5a84b1…` | Docker Hub's `18.6` index is `3a426452…` (rebuilt 2026-10-31), still PostgreSQL 18.6, as Sprint 23's report read. It serves CI's test database only and ships in no image, no security fix was read that forces it, and Dependabot does not watch the workflow's `services:`, so the lane changes nothing (Lane M: "change nothing unless a security fix forces it"). |
| PostgreSQL major | 18 (`18.6`, by digest) | Docker Hub has `19rc1` tags, a release candidate, not a release; the major is pinned (Dependabot ignores PostgreSQL majors). Compose's `18.6-alpine3.24` digest (`10a5c69a…`) is still the tag's, so there is nothing to take there either. |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.6, OTP 27.3.4.19;
  the development image and the release's build stage on
  `hexpm/elixir:1.18.6-erlang-27.3.4.19-debian-bookworm-20261027` (the build
  stage on its `-slim` variant); the runtime stage on
  `debian:bookworm-20261027-slim`; Node 26 in CI (the companion's `engines`
  say `>=26 <27`); every image pinned by digest. The script could not read
  the OTP inside the build image (no Docker in the session); the tag names
  27.3.4.19.
- **Hex:** every direct dependency up to date except `decimal`
  (requirement), `floki`, `lazy_html` and `sobelow` (above); `mix hex.audit`
  and `mix deps.audit` report nothing; `mix deps.unlock --check-unused` is
  clean.
- **npm:** mcp-server and test/browser have no direct dependency behind;
  `npm audit` reports 0 vulnerabilities.
- **BMAD install:** the manifest says 6.12.4; core and bmm are 6.12.4; tea
  v1.27.3, cis v0.3.2, bmb v1.8.1 pinned; automator tracks `main`
  (`0b94fd7`).
- **The local toolchain** of the cloud session that ran this lane is OTP
  27.3.4.19 with Elixir 1.18.6, the pinned pair; the OTP 28 run used its own
  unpacked OTP and `MIX_HOME` in the session's scratch space, so the shared
  installation other lanes compile with did not move.

## Gate results on the lane's head

Run on the lane's head (M1 and the tea re-pin, before this report's commit)
on 2026-11-04, local toolchain Elixir 1.18.6 / OTP 27.3.4.19, PostgreSQL 16,
Node 22 (CI runs the companion on Node 26). Each exit status was read
directly, never through a pipe. The full `mix test`, `mix coveralls` and
`mix dialyzer` on OTP 27 run at the sprint's integration, by the
orchestrator, not in this lane: no Hex dependency moved here, and the tea
re-pin touches no Elixir file.

| Gate | Result |
| --- | --- |
| `mix format --check-formatted` | clean |
| `mix compile --force --warnings-as-errors` | clean |
| `mix gettext.extract --check-up-to-date` | up to date |
| `mix test` on the files that read the BMAD install (`docs_test`, `workflow_docs_test`, `dev_config_test`, `ci_test`, `scope_b3_dependency_classes_test`) | 139 tests, 0 failures |
| `mix credo --strict` | no issues |
| `mix sobelow --skip --exit` | exit 0 (on 0.16.0) |
| `mix deps.unlock --check-unused` | exit 0 |
| `mix hex.audit` | no retired or advisory packages |
| `mix deps.audit` | no vulnerabilities |
| `pre-commit run --all-files` | all hooks pass |
| `npm test --prefix mcp-server` | 272 tests, 0 failures |
| `npm run build --prefix mcp-server` | clean |
| `npm audit --audit-level=high --prefix mcp-server` | 0 vulnerabilities |
