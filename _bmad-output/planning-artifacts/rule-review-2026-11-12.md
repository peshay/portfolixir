# Rule review for I9 (2026-11-12)

The table promised by the Sprint 28 plan, D-9, for idea I9
(`ideas.md`, row I9): every rule in `AGENTS.md`, the sprint workflow and
the story workflow, with its reason, the gate that checks it and the last
time it was used. Mark keep, merge or drop per row in the Owner column.
Nothing in this file changes a rule. A change still goes through an ADR
amendment or an `AGENTS.md` PR.

## How to read this

1. One row per rule. A rule written in several places gets one row, with every place under Where. **A** = `AGENTS.md`, **SW** = `docs/development/sprint-workflow.md`, **ST** = `docs/development/story-workflow.md`, `inv/` = `test/invariants/`, **wdt** = `test/portfolixir/workflow_docs_test.exs`, `IA/` = `_bmad-output/implementation-artifacts/`. "S28 retro" is `IA/sprint-28-retro-2026-11-10.md`, and the same pattern holds for S22 to S27. The S18, S19 and S21 retrospectives are inside `IA/sprint-status.yaml`.
2. **Enforced by.** **gate**: a check fails the build when someone breaks the rule. **partial**: a check covers part of the rule. **text pin**: a test checks that the wording exists, not that anyone follows it. **text only**: nothing checks it. **contradicted**: the repository does the opposite of the rule.
3. **Reason.** **yes**: a reason is recorded, and its source is named. *(inferred)*: the files themselves mark the reason as inferred. **none**: no reason is given. **cited, not found**: the cited source does not say it.
4. **Last use.** The most recent record of the rule being applied or broken. "none found" means a search of the S22 to S28 retrospectives, the plans and `sprint-status.yaml` turned up nothing.
5. **Recommendations.** keep; merge copies (keep one text and have the other places point to it); merge with Rn; shorten-because-gated; record the reason; correct the text; drop. Mark the Owner column with K, M or D, or write your own.

## Headline counts

| | Count |
|---|---|
| Rules in total | **84** |
| Reason recorded | 64 |
| Reason *(inferred)* | 11 rows (14 markers in the files: 7 in A, 6 in SW, and one "not recorded" for `.portfolio`, which matches I9's count) |
| No reason given | 6 (R5, R44, R77, R78, R79, R80) |
| Reason cited but not found in its source | 3 (R2, R6, R45; see "Sources that say something else") |
| Enforced by a gate | 10 |
| Partly enforced | 12 |
| Wording pinned by a test only | 14 |
| Text only | 46 |
| Contradicted by the repository | 2 (R26, R30) |
| Recommended **drop** | 2 (R54, R66) |
| Recommended **merge** | 24 (21 merge copies, 3 merge with another row) |
| Recommended **shorten-because-gated** | 7 |
| Recommended **record the reason** | 11 |
| Recommended **correct the text** | 3 (R26, R30, R36) |
| Recommended **keep** | 37 |

## The three rules that most often stood in an agent's way

I9 says the review should start from such cases. They are ranked by how much evidence each one has.

1. **The permanent non-goals and "no advice" (R17, with R12 and R16).** I9's
   first cases. On 2026-11-01 an agent read the trading non-goal as
   forbidding I8 outright. The owner then ruled that the non-goal binds the
   app, not what a listener does with a signal (`ideas.md`, row I8). The same
   day the owner said the app calling an LLM should not be ruled out. The rule,
   the PRD's cornerstone ("Portfolixir never calls an LLM", PRD §1) and the
   B2 to B4 backstops all forbid that. Where "no advice" ends for a
   described pattern or a threshold signal is still open (`ideas.md`, rows
   I6 and I8). The "two precisions" sentence now in A narrows the misreading
   in prose. The LLM question is unanswered.
2. **Stay in scope, together with "an agent does not edit a process rule"
   (R6, R7 and R45).** The S13 retro (`sprint-13-retro-2026-09-19.md:82-88`)
   says the agent knew the Required Local Checks list was missing four
   commands from CI. It left the list alone because "the list is a
   documented process rule, so an agent does not edit it". It was the third
   batch to run those commands out of habit, and the gap cost a CI round.
   ADR-0022's Context says the scope lock "worked as designed — agents never
   touched anything cross-cutting — which is precisely why no one owned the
   whole". Filing every finding as its own issue made Sprint 21 file 96
   issues, which led to the amendment of 2026-11-01. The preamble now invites
   a PR, which covers the first half of this case. The second half, who owns
   cross-cutting work, has no rule.
3. **The commit budget, the stacked PR and the history cleanup (R36, R41
   and R42).** Sprints 24 and 25 could not force-push, so their PRs got no
   history cleanup and no rebase (S24 retro; S25 retro;
   `sprint-status.yaml:732`). A standing grant followed on 2026-11-06. In
   Sprint 28 the rule's remedy was unavailable. The rule says to cut the
   sprint into a stack of PRs above 90 commits, but the environment pushes
   only to its assigned branch (Sprint 28 plan, D-10). The PR reached 102
   commits, and 94 after cleanup, which is above ADR-0026's budget of 90
   (S28 retro).

## The table

### `AGENTS.md`: the preamble and the hard rules

| # | Rule | Where | Reason recorded? | Enforced by | Last use | Recommendation | Why | Owner |
|---|---|---|---|---|---|---|---|---|
| R1 | No `CLAUDE.md` or `CLAUDE.local.md`; Claude Code reads A only without one | A preamble; SW Tool notes | yes: Claude Code docs (external, not checked here) | text only (no such file in the tree, checked) | none found | merge copies | The same fact appears twice. | |
| R2 | Every rule carries its reason and source; challenge it by PR; a new rule needs its reason | A preamble; SW intro | **cited, not found**: ADR-0026's amendment of 2026-10-08 says neither | text only | S25 retro, carry-forwards ("each is a rule with its reason"); this review | record the reason | The cited ADR doesn't contain it. | |
| R3 | A stays short; procedures live on linked pages | A preamble; SW Tool notes (Codex) | yes: Codex's 32 KiB limit (the incident has no cited record) | text only (A is 19,314 bytes) | none found | merge copies | The same reason appears twice. | |
| R4 | Test first: the test fails for the expected reason, then the smallest code | A Hard Rules; ST steps 1–4; SW §2 | yes: PRD §1; ADR-0036 | text pin (wdt, the nine steps); nothing checks that a test failed first | S28 retro: each attack finding was a red test before its fix; 24 of 38 fixes were reverted and seen red | merge copies | Three copies of one rule. | |
| R5 | The user-story comment sits directly above the functional test | ST template | none | text pin (wdt; `.github/ISSUE_TEMPLATE/user_story.md`) | in use in every new test file (for example `inv/`) | record the reason | It is used everywhere and nowhere explained. | |
| R6 | Stay in scope: no adjacent feature, nothing fixed opportunistically | A Hard Rules; SW Owning ("never fix outside the PR's scope"); ST intro | **cited, not found**: ADR-0022's Context records the rule's cost; E17–E19 §5 doesn't address scope | text pin (wdt: "Record a defect found on the way at once") | S28 close-out: 4 older findings fixed on the surface, 2 filed, 4 polish lines | merge copies | See the top three, case 2. | |
| R7 | A finding is placed by severity: fixed on the PR's surface; S1 filed; S2 filed if the diff reaches it; S3 goes on a polish line | A Hard Rules; SW §3; SW Issues ("one topic = one issue") | yes: S19 plan D-14; ADR-0026 amendment of 2026-11-01 | text pin (wdt, the S1/S2/S3 wording) | S28 close-out: #1439 and #1440 filed, the rest went on polish lists | merge copies | SW §3 is the source; A restates it. | |
| R8 | Don't change an architecture decision silently; amend the ADR | A Hard Rules | yes: ADR-0026 step 1 | partial: `inv/scope_b7_gate_registry_test.exs`, for gate sentences only | S28: ADR-0056 amended on 2026-11-09 inside the sprint PR | keep | |  |
| R9 | `Decimal` for money, quantities, prices and rates; never persist a float | A Hard Rules | yes: ADR-0003 | **gate**: `inv/decimal_persistence_test.exs`, `inv/decimal_input_test.exs` | S28 retro: S3's returns are exact Decimals | shorten-because-gated | The invariant holds the rule; one line is enough. | |
| R10 | No external network call in a test; fakes only | A Hard Rules | *(inferred)*; ADR-0005's Consequences state the rule, not its reason | partial: `config/test.exs` wires the fakes, `FakeResolver` and `News.NoNetwork`; no check fails on a new call (inferred) | S28: Q1–Q3 pinned by fake adapters; the UAT made no outbound call | record the reason | | |
| R11 | Never `String.to_atom/1` on external input | A Hard Rules | *(inferred)* | **gate**: Sobelow `DOS.StringToAtom` in CI `quality` (`.github/workflows/ci.yml:218`); `test/portfolixir/ci_test.exs:1014` pins "no ignore" | S27 retro: 1,000 invented names left the atom count unchanged | shorten-because-gated | | |
| R12 | Out of scope unless a story changes it: document intake, sync, trading, payment, orders, rebalancing, LLM behavior; the exceptions PP CSV/JSON, broker PDF and display-only hints | A Hard Rules | yes: PRD §4; ADR-0021; ADR-0023. Why `.portfolio` stays out is "not recorded" | **gate**: `inv/scope_b6_intake_formats_test.exs`, `scope_b3`, `scope_b4`, `scope_b7` | S28 retro: V1's B6 zlib exemption was sent back | merge with R16 and R17 | Three overlapping lists of forbidden things. | |
| R13 | Scope ladder: (a)–(c) allowed, (d) backtesting forbidden | A Hard Rules | yes: PRD §4; ADR-0049 §4 (the (c)/(d) boundary, line 194) | **gate**: `inv/metrics_carry_no_verdict_test.exs`; `scope_b4` and `scope_b5` (`gated.level_d_backtesting`) | `ideas.md` I6 (2026-11-01): a pattern scored by replaying prices is (d) | keep | | |
| R14 | Every (a)–(c) metric states its computation basis in its API and MCP payload | A Hard Rules | yes: brief addendum | partial: per-metric tests (for example `test/portfolixir/catalog/security_metrics_test.exs`); no invariant (inferred) | S28 retro: ML1's fix added its sentence to the basis | keep | | |
| R15 | Advanced classifications (partial weights) are out of scope; (b) may report from existing data | A Hard Rules | yes: PRD §4 | text only | `ideas.md` I23 (S27): one category per security, so no partial weights are needed | keep | | |
| R16 | Gated: (d), B3.3 beyond quotes, FX and news, B3.7 push, B3.8 local model; the ladder cannot open them | A Hard Rules | yes: brief addendum, "Parked"; ADR-0056 B8 | **gate**: `inv/scope_b7_gate_registry_test.exs` pins the sentence; `scope_b2` to `scope_b5` | S27: the B3.3 sentence was widened for news together with its registry (ADR-0056 B8) | shorten-because-gated | The registry ties the sentence to its backstops. | |
| R17 | Permanent non-goals: no order-placing connection, orders, automated trading or payment, advice, raw news archive, or external LLM calls from the app | A Hard Rules; A Security, third bullet | yes: product brief; PRD §1, cornerstone | **gate**: `inv/scope_b1` to `scope_b5`, `scope_b7`, `metrics_carry_no_verdict`, `findings_carry_no_action` | `ideas.md` I8 and I9 (2026-11-01): misread as forbidding I8; the owner wouldn't rule out the app calling an LLM | keep | Your call: the LLM line and the "advice" line (top three, case 1). | |
| R18 | Machine-extracted data is a proposal until confirmed (source link, `machine_generated`) | A Hard Rules | yes: PRD NFR-10 | partial: per-feature tests (`test/portfolixir/knowledge_test.exs`, `news/labels_test.exs`) | S28, exit criterion 5: a story becomes knowledge only by a confirmed write | keep | | |
| R19 | Don't claim production readiness | A Hard Rules | yes: the launch-readiness report of Sprint 19 (line 191) | text pin: `test/portfolixir/docs_test.exs:3179` | `IA/launch-readiness-2026-10-09-sprint20.md:268` | keep | | |
| R20 | Public files are normal, readable multiline files | A Hard Rules | *(inferred)* | partial: the pre-commit hooks `mixed-line-ending`, `end-of-file-fixer` and `check-invisible-unicode`; one-line files are not checked | none found | shorten-because-gated | The hooks cover the part that can be checked. | |
| R21 | Every repository artifact is in English; the German docs translate | A Hard Rules | *(inferred)*; PRD NFR-7 states the rule only | partial: `test/portfolixir/docs_test.exs:648` (the core docs exist in English and German) | none found | record the reason | | |

### `AGENTS.md`: privacy, authorship, security, architecture, coverage

| # | Rule | Where | Reason recorded? | Enforced by | Last use | Recommendation | Why | Owner |
|---|---|---|---|---|---|---|---|---|
| R22 | Never commit a real person's private life or finances: data, names, banking, machine details, agent state; this includes the idea list | A Privacy; SW Ideas ("the list is public") | yes: S16 plan D-11 (five records scrubbed); `SECURITY.md` | partial: `.gitignore:56-57` (`_bmad/config.user.toml`, `_bmad/memory/`); `ci_test.exs:84` refutes `/Users/` in the workflow docs only | the S16 plan D-11 scrub; every UAT since runs on the synthetic seed (S28) | merge copies | | |
| R23 | Commits are authored by the accountable human; no AI co-author, model or session footers; the PR names the agent | A Commit Authorship | yes: S17 plan D-10; owner, 2026-11-07 | **gate**: `scripts/check-commit-authorship.sh` as the pre-commit `commit-msg` hook and in `.github/workflows/commit-authorship.yml`; `.claude/settings.json` turns attribution off | S27 plan: the A correction of 2026-11-07 (the model name became optional) | shorten-because-gated | Keep only the PR sentence and its reason. | |
| R24 | No secrets in source; API and MCP use bearer tokens from the environment | A Security | yes: `SECURITY.md`; `scope_b1` | partial: `inv/scope_b1_no_stored_credentials_test.exs` covers stored credentials; no secret scan of the source was found | S28: N1's label profile has its own token | keep | | |
| R25 | The web UI never writes `.env` | A Security | *(inferred)* (ADR-0045) | text only | none found | record the reason | | |
| R26 | Modular monolith; contexts never depend on the web layer | A Architecture | yes: ADR-0001 | **contradicted**: 11 context lines use `PortfolixirWeb.Gettext` (for example `lib/portfolixir/catalog/currencies.ex:10`), and `lib/portfolixir/release.ex:66` uses the Endpoint; `inv/web_repo_boundary_test.exs` checks only the other direction | n/a | correct the text | As written, it doesn't hold. | |
| R27 | MCP tools call the public JSON API only | A Architecture | yes: ADR-0002 | **gate**: `inv/mcp_dependency_allowlist_test.exs` | S28: news.assign, news.registry and the version read all go through the API | shorten-because-gated | | |
| R28 | Coverage both ways: an agent-only capability is allowed if its view lands in the same or the next sprint; otherwise it is a close-out finding | A API and MCP; SW §5 (two-way check); ST steps 5–6 and the paragraph after | yes: brief addendum | text pin (wdt); checked by hand at close-out | S28 close-out: the Research tab gap, due in S29 | merge copies | Three copies. | |
| R29 | Endpoints live under `/api/v1`; financial decimals are strings in the API and MCP | A API and MCP | yes: ADR-0003 | partial: per-tool tests (`mcp-server/test/tools.test.ts`, "decimal-string output"); no app-wide check found | S28: `GET /api/v1/version` (FR-55) | keep | | |
| R30 | The MCP companion installs and runs on its own, outside Docker Compose | A API and MCP | *(inferred)* | **contradicted**: `docker-compose.yml:130` runs an `mcp` service, and CI `compose-smoke` calls a tool through it | n/a | correct the text | It probably means "also runs on its own"; otherwise drop it. | |

### How work is done: planning and implementation

| # | Rule | Where | Reason recorded? | Enforced by | Last use | Recommendation | Why | Owner |
|---|---|---|---|---|---|---|---|---|
| R31 | A sprint is two sessions and two PRs; a fresh session executes the plan without the planning session's memory | A How Work; SW intro; SW §2 | yes: ADR-0026 amendment of 2026-10-08; Claude Code best practices | text only | S28: the planning PRs and the sprint PR #1436 | merge copies | | |
| R32 | Decision gate: an ADR or spec with acceptance criteria is signed before the sprint that builds it | SW §1; SW Risk-tier, item 4 | yes: ADR-0026 step 1; E17–E19 §5 | text only | S28 planning PR: signed ADR-0058 for S29 | keep | | |
| R33 | A gate-closing ADR names its asks; a deferred ask is filed | SW §1 | yes: ADR-0043 | text only | ADR-0058 §10 (S28 planning) | keep | | |
| R34 | The merge is the signature: the planning PR is written as adopted and opens ready for review | SW §1 | yes: ADR-0026 amendment of 2026-09-07 | text only | S28 retro: the plan and its amendment were adopted by their merges | keep | | |
| R35 | Ask the owner only what only the owner knows; decide the rest, flippable by a comment; open with "What you need to do" | A How Work; SW §1 | yes: ADR-0038; ADR-0026 amendment of 2026-10-08 | text only | S28 plan; S28 close-out, "the owner's questions" | merge copies | | |
| R36 | The plan estimates the commit count; above 90, cut the sprint into a stack of PRs | SW §1 | yes: ADR-0026 amendment of 2026-10-08 (GitHub's limit of 100) | text only | S28 plan D-10: no stack possible, a cut line instead; the PR reached 102 commits, 94 after cleanup | correct the text | A stack isn't available, and the budget was exceeded (top three, case 3). | |
| R37 | After the planning merge, the planning session does the registry bookkeeping and ends | SW §1 | yes, but only as a pointer ("see below") | text only | S25 retro: the planning session filed #1395 to #1397 | merge with R31 | | |
| R38 | One branch, one PR, opened as a draft; lanes as commit groups in the plan's order; one commit per issue; every commit passes the gates | SW §2; A "What it is" (small commits) | yes: ADR-0026 step 2 | text only | S28 retro: N's UI group landed after V and S, out of the plan's order | keep | | |
| R39 | The session orchestrates: one subagent per story, with a brief that names its base commit | SW §2 | yes: S18 retro | text only | S27 retro: each story in its own worktree with its own test database | keep | | |
| R40 | Read a gate's exit status directly, never through a pipe | SW §2 | yes: S19 retro | text only | S23 retro: gates moved to the foreground after monitors stalled (related); nothing since | keep | | |
| R41 | Keep the branch current: rebase onto `main` before each closing act and before promotion; ask only when both sides changed the same logic | A How Work; SW §2; SW Owning | yes: ADR-0026 amendment of 2026-10-08 (no event fires when `main` moves) | text only (linear history is a GitHub setting, not in the repository) | S25 retro: the rebase was blocked without a force-push | merge copies | Three copies. | |
| R42 | On your own branch, rebase and `--force-with-lease` without asking; the cleanup folds fix-ups and ends with a tree byte-identical to the backup ref | A How Work; SW §4 | yes: S25 retro; owner, 2026-11-06; S18 retro | text only | S28 retro: 12 fix-ups folded, the tree byte-identical | merge copies | | |
| R43 | Branches are named `agent/<provider>/<topic>`; a branch the environment assigns is used as assigned | A How Work; SW §2 | *(inferred)*; the exception's reason is the owner's, 2026-11-07 | text only | S28: `claude/busy-meitner-21kgtg`, by the exception; S25 used `agent/claude/sprint-25` | record the reason | | |
| R44 | Stop the moment the owner says stop | A How Work | none | text only | none found | record the reason | | |
| R45 | Run the Required Local Checks before a PR and before every push | A Required Local Checks; ST, last paragraph | **cited, not found**: A and ST say the old list "omitted eight", but the S13 retro (lines 82–88) names four | partial: CI's five jobs run the same commands (`ci.yml`); `ci_test.exs:1076` keeps the list copies equal | S27 retro: the browser suite was not run locally; S28 retro: story agents skipped `coveralls` | merge copies | CI is the gate; the local run only saves a round. | |

### Sprint workflow: the closing act, promotion and close-out

| # | Rule | Where | Reason recorded? | Enforced by | Last use | Recommendation | Why | Owner |
|---|---|---|---|---|---|---|---|---|
| R46 | Each risk class gets a closing act: correctness, edge cases, a design critic for UI, a UAT persona on synthetic data | SW §3 | yes: ADR-0026 step 3; ADR-0038 | text only | S28: lenses per lane; the UAT with 14 screenshots | keep | | |
| R47 | A closing act reviews its diff; at most five findings per lens; a re-check files only an S1; an audit of older code is a planned lane | SW §3 | yes: ADR-0026 amendment of 2026-11-01 | text pin (wdt) | S28 re-check | keep | | |
| R48 | One polish list per screen; a story that touches the screen fixes its lines; a polish pass is one test-first story | SW §3 | yes: ADR-0026 amendment of 2026-11-01 | text pin (wdt) | S28: lines on #1356, #1365 and #1366 | keep | | |
| R49 | Count the introduced regressions separately; no exit criterion counts open issues | SW §3 | yes: S21 retro | text only | the S28 retro's table | keep | | |
| R50 | The reviewer briefing says what is new, what changed, where to look, the deliberate trade-offs, with screenshots | SW §3 | yes: ADR-0026 steps 3–4 | text only | S28: the plan-premise correction is named in the briefing | keep | | |
| R51 | Risk-tier work gets its own commit group, a verification pass and a callout in the briefing | A How Work; SW Risk-tier | yes: ADR-0036 | text only | S28: Lane N, security tier | merge copies | | |
| R52 | Promote the PR yourself once the four conditions hold; leave one comment on what changed | SW §4 | yes: E17–E19 §3; the comment's reason is *(inferred)* | text only | S28: promoted after the closing act | keep | | |
| R53 | A recorded open question doesn't block promotion; an unanswered owner question does | SW §4 | yes (stated inline, with no source) | text only | S28: ADR-0056's open questions D5 and D10 recorded | keep | | |
| R54 | Don't flip the PR status back and forth | SW §4 | *(inferred)* | text only | none found | drop | No recorded use, and the reason is a guess. | |
| R55 | Agents never merge; the owner merges (rebase for a sprint PR, squash for a small one) | A How Work; SW §4 | yes: ADR-0026 step 4; the merge-method amendment | text only (no branch protection in the repository) | S28 close-out: "#1436's merge" is among the owner's questions | merge copies | | |
| R56 | The close-out records are the sprint PR's last commits, written by the session that built it | SW §5 | yes: E17–E19 §3; ADR-0026 amendment of 2026-10-08 | text only | S28 retro | keep | | |
| R57 | Records: the `sprint-status.yaml` entry, `epics.md`'s map, Tracker Index and reconciliation, no story rows; what owns what | SW §5; SW Issues ("what owns what") | yes: ADR-0042 | **gate**: wdt:197 refutes story rows in `epics.md` and `sprint-status.yaml` | S28 close-out | merge copies | | |
| R58 | Name the issues the diff finishes (`Closes #n`); close invalidated ones by hand; a planning PR carries no keyword for sprint work | SW §5; SW Issues | yes: E17–E19 §3 | text pin (wdt:110) | S25 retro: planning PR #1394 closed #1390 early (rule broken); S28: 13 keywords | merge copies | | |
| R59 | Surface check: when a read parameter lands, name every endpoint of its family and which ones carry it | SW §5 | yes: #740; triage of 2026-08-27, §0.3 | text only | `sprint-status.yaml:437` (S27, `since=` and `fields=` on news) | keep | | |
| R60 | A maintenance lane every sprint, with a version report of what was not updated and why | SW §5 | yes: triage of 2026-08-12, Q1; ADR-0036 | text pin (wdt:110) | `IA/version-report-2026-11-09-sprint28.md` | keep | | |
| R61 | After the merge, confirm `main`'s CI and the calendar release; tell the owner in one line | SW §5 | yes: ADR-0026, calendar-version amendment | **gate**: `.github/workflows/release.yml`, job `calendar-release`; `ci_test.exs:153` | `sprint-status.yaml` line 2 (releases 2026.11.10 to 2026.11.12) | shorten-because-gated | The workflow makes the release; only the confirmation is the session's job. | |

### Sprint workflow: owning a PR, UI, ideas, issues

| # | Rule | Where | Reason recorded? | Enforced by | Last use | Recommendation | Why | Owner |
|---|---|---|---|---|---|---|---|---|
| R62 | Watch a PR by subscription from the moment it exists; never offer and wait; never poll | A How Work; SW Owning | yes: S10 retro | text only | none found after the S10 retro | merge copies | | |
| R63 | Every CI failure gets a visible outcome: a fix, or a comment saying why not | A How Work ("drive CI to green"); SW Owning | *(inferred)* | text only | S28 retro: the browser job went red twice, then was fixed | record the reason | | |
| R64 | A failure that also happens on the base branch: say so, port the fix, act when the base recovers | SW Owning | yes: S13 retro | text only | S28 Lane M: the red on `main` was fixed first | keep | | |
| R65 | Never weaken a quality gate: no threshold, ignore, skip or baseline | A How Work; SW Owning | yes: ADR-0026, "Compensating controls"; ADR-0036 | partial: `ci_test.exs:1014` and `:1045` (Sobelow has no ignore, the skip file holds two lines); `scope_b7` | S28: the browser job's limit went from 20 to 35 min; S27: N1's bound went from 1 s to 10 s, each "a loosened bound, named" | keep | Your call: is a named loosening allowed? | |
| R66 | Losing an approval by pushing a fix is an accepted cost | SW Owning | *(inferred)* | text only | none found | drop | Merges carry no approvals (inferred), so there is no case. | |
| R67 | A UI change gets a board before code, even a one-rule CSS change: options or before/after, a recommended default, real `app.css`, a PNG; the only exception is an identical picture | A How Work; SW §1; SW UI section | yes: S14 plan D-10 and D-11; the PNG reason is *(inferred)* | text only | S28 retro: QA1's row landed without a board, and board 08, drawn afterwards, found a defect | merge copies | | |
| R68 | An idea is recorded, not built: it goes into `ideas.md` as said, status `captured`, with no code | A Hard Rules and How Work; SW Ideas | yes: ADR-0042 amendment of 2026-10-27 | text pin (wdt:298) | commit `9420a41`: I43 and I44 recorded and triaged | merge copies | | |
| R69 | Triage is the agent's job: search, check against ADRs, the ladder and the non-goals, name the kind, merge duplicates | SW Ideas | yes: ADR-0038 | text only | commit `9420a41` | keep | | |
| R70 | One idea per planning session goes deep | SW Ideas | *(inferred)* | text only | S28 plan D-9: I9 was proposed in S27 and not held, so this table exists | record the reason | | |
| R71 | A no-brainer idea skips the conversation and is named as such in the plan | SW Ideas | yes (inline) | text only | S24 plan: I16 "is not the no-brainer its row said" | keep | | |
| R72 | A worked-out idea leaves the list as a pointer; the close-out marks it built | SW Ideas | yes: ADR-0042 | text only | S28 close-out: I21 and I27 to I29 built | keep | | |
| R73 | Issues are thin pointers; acceptance criteria are never copied in | A How Work; SW Issues | yes: ADR-0042 | text only | S27 plan | merge copies | | |
| R74 | Filing an issue is bookkeeping; what the owner needs goes in an ADR, a triage, the plan or the briefing | SW Issues | yes: ADR-0042, "Who reads what" | text only | S28 close-out: "open issues, reported, not judged" | keep | | |
| R75 | One topic, one issue: under its parent tracker, open titles searched first, complete without earlier sessions | SW Issues | yes: #321's working agreement; S19 retro | text pin (wdt:244) | S28: #1439 and #1440 filed under #420 | merge with R7 | | |
| R76 | A `needs-decision` issue carries its recommended answer and what would reopen it | SW Issues | yes: S20 plan D-4 | text only | S22 retro: #1371, answer (b) recommended | keep | | |
| R77 | Label meanings: `agentic`, `needs-uat`, `needs-decision`, `tracking` | SW Issues | none | text only | S28 plan D-12: #328 and #354 wait for a check on real data | keep | It's a glossary, not a rule. | |

### Story workflow

| # | Rule | Where | Reason recorded? | Enforced by | Last use | Recommendation | Why | Owner |
|---|---|---|---|---|---|---|---|---|
| R78 | User docs are reviewed for every story and updated when behavior changes; background-only work records "no update" | ST step 7; ST lines 25 and 89–92 | none | text pin (wdt:43) | S28 N10: the documentation in English and German | merge copies | The rule is written twice in ST, with no reason. | |
| R79 | A security audit per story (step 8) | ST step 8 | none | text pin (wdt) | S28: the security lenses on Lane N | record the reason | It has no reason and no stated content. | |
| R80 | Visible copy is English-first, with German gettext translations | ST | none (PRD NFR-7 states the rule only) | partial: `mix gettext.extract --check-up-to-date` in CI `quality` (`ci.yml:173`) checks that the catalogues are current, not that German is filled in (inferred) | S28 retro: stale gettext references (introduced, fixed) | record the reason | | |
| R81 | Run `test/invariants` beside the story's own tests | ST, "What a story's own tests do not cover", 1 | yes: S24 retro, J3 | text only | S28 re-check: 296 invariant tests, 0 failures; S28's carry-forward 2 adds `coveralls` | keep | | |
| R82 | A story that changes a writer searches the whole suite for the changed shape, `seeded_upgrade/` included | ST, same section, 2 | yes: S24 retro, J1 | text only | none found after S24 | keep | | |
| R83 | A screen test drives the field as the operator does; a figure is compared with the API for the same period | ST, same section, 3 | yes: S24 retro, B2 and J3 | text only | S28: N7 and N8 pinned against the API; the UAT matched to the cent | keep | | |
| R84 | A gate a story adds gets an attack case in its self-test | ST, same section, 4 | yes: S24 retro, D1 | text only | S28: V1's B2 entry came with an attack self-test; S26 retro: applied to the happy path only | keep | | |

## Sources that say something else

- **R2.** A's preamble cites ADR-0026's amendment of 2026-10-08 for "every
  rule carries its reason" and for "a model follows an instruction better
  when it knows the goal". Neither sentence is in that amendment or
  anywhere else in `docs/decisions/0026-epic-batch-workflow.md`. A search
  of `_bmad-output/` and `docs/` found no other source.
- **R45.** A ("a shorter list omitted eight of CI's checks") and ST ("the
  six-command copy … omitted eight") cite the S13 retro. That retro says
  the six-command list was missing four commands from the quality job
  (`IA/sprint-13-retro-2026-09-19.md:82-88`). "Eight" may count checks
  added later, but that is inferred.
- **R6.** A cites ADR-0022's Context for "every change stays reviewable".
  The Context says the scope lock left the whole unowned. A also cites the
  E17–E19 retro §5, which covers gates before code, the aftermath, red
  gates and "lessons need mechanisms", but not scope.
- **R26 and R30.** The cited ADRs exist, but the repository does the
  opposite of the rule text (see their rows).
- **R42.** For the grant, A cites the S25 retro: "Sprint 25's PR sat
  conflicting and without CI for hours while the session asked". The
  retro records that the force-push was refused and the owner was asked.
  It does not mention "hours" or "conflicting"; `sprint-status.yaml:732`
  records the wait. This is a minor mismatch.
