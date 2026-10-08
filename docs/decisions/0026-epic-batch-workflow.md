---
layout: docs
title: "ADR-0026: Epic-batch workflow — humans review decisions and behavior, agents review code"
description: Feature trees are worked agentically on a single epic branch and accepted in one behavior-level review; per-story human review is reserved for high-risk changes.
---

# ADR-0026: Epic-batch workflow — humans review decisions and behavior, agents review code

- **Status:** Accepted; **amended by [ADR-0036](0036-risk-tier-rides-the-batch.html)**
  (2026-08-04 — the "Risk-tier exceptions" clause below is withdrawn; risk-tier
  work now rides the batch and the label governs review depth, not delivery
  mode) **and by the merge-method amendment below** (2026-08-14, owner decision
  on PR #688 — batch PRs are rebase-merged after an agent history cleanup;
  small PRs stay squash-merged), **by the signature-and-tag amendment below**
  (2026-09-07, PR #780) **and by the calendar-version amendment below**
  (2026-10-01, Sprint 17 plan D-11 — step 5's tag is made by the Release
  workflow, not by the owner) **and by the two-PR amendment below**
  (2026-10-08 — a sprint is one planning PR and one sprint PR; lanes become
  commit groups; the close-out rides the sprint PR; the owner is asked only
  what only the owner knows). Everything else here stands.
- **Date:** 2026-07-12

## Context

The issue-driven per-story workflow assumed the maintainer reviews every PR.
With current frontier models that assumption inverts the economics: code
generation is cheap, verification is the bottleneck, and the maintainer's
attention is the most expensive verification resource. The project has direct
evidence for both failure and cure:

- June 2026: individually clean, individually reviewed stories accumulated
  into a scattered UI ("no artifact owned the whole"); scope lock even forbade
  agents from fixing cross-cutting issues (context of ADR-0022).
- July 2026: the reconsolidation branch (PR #557) bundled an entire feature
  tree, closed with a multi-agent adversarial review, a synthetic-data UAT
  persona pass, and one owner walkthrough — and merged cleaner than any of
  the stacked small PRs would have.

Issue #315 (spec-driven development) asked for exactly this decision.

## Decision

Feature work runs in **epic batches** by default:

1. **Decision gate (human, minutes not hours).** Before the batch: an ADR or
   spec with acceptance criteria, signed off by the owner. Direction is
   reviewed here — not in the diff later.
2. **Batch (agentic).** Agents work the feature tree on ONE epic branch
   (`agent/<provider>/<epic-slug>`): one commit (or small commit group) per
   issue for traceability and bisection, every commit passing the local
   gates, the branch rebased onto `main` at least daily. Epic branches live
   days, not weeks. Story-level TDD discipline (AGENTS.md) applies unchanged
   inside the batch — what changes is who reads the result.
3. **Agentic review closing act (mandatory, before the human sees it).**
   Multi-role adversarial review (at minimum: correctness hunter, edge-case
   hunter, UAT persona walkthrough on seeded synthetic data) with confirmed
   findings fixed on the branch, plus a **reviewer briefing** on the PR: what
   is new, what got better, what changed, where to look, which trade-offs
   were made deliberately — with screenshots for UI work.
4. **Acceptance (human, behavior-level).** The owner reviews behavior — a
   walkthrough against the briefing — not lines. Feedback becomes a UAT fix
   round on the same branch. The maintainer squash-merges; agents never merge.

**Risk-tier exceptions — these keep dedicated small PRs with real human
review:** ledger/money-domain math and domain invariants, security-relevant
changes, dependency updates, and anything touching the import idempotency or
projection semantics. A silent error there is expensive and invisible in a
walkthrough.

**Compensating controls** (the review budget moves into automation): the
invariant meta-tests and quality gates (#420, #314), the golden-master import
corpus, and property tests on money invariants are prerequisites this
workflow leans on; weakening a gate to make a batch pass is a review reject.

## Consequences

- The maintainer's touchpoints per epic drop to two: decision sign-off and
  behavior acceptance. Issues stay small (agent work units), PRs get big
  (human review units).
- AGENTS.md gains an "Epic-Batch Workflow" section; the story workflow
  remains binding inside batches and for the risk-tier exceptions.
- Revert unit = one squash-merged epic; inside-branch issue commits keep
  bisection possible before the squash.
- #315 is resolved by this ADR; #420 tracks the compensating-control work.
- First application: the ADR-0024 restructure tree (gate: spike #574, then
  the epic batch under #448).

## Amendment: batch PRs are rebase-merged (2026-08-14, owner decision on PR #688)

Squash-merging a whole sprint collapses 40+ per-issue commits into one
multi-thousand-line commit on `main`, which destroys exactly what ADR-0036
demands of risk-tier work — independent readability and revertability. A
later `git bisect` or `git blame` lands on "the sprint", never on the issue.
The sprint rollback point that squash provided is carried by the per-sprint
`vX.Y.Z` tag either way.

Therefore:

1. **Epic-batch PRs are rebase-merged.** The per-issue commits land on
   `main` as they were reviewed. Small, single-concern PRs stay
   squash-merged — one commit is the right unit there.
2. **The agent cleans the branch history before promotion.** Mechanical
   fix-ups (style passes, formatting, catalog reconciliation, CI-appeasement
   commits) are folded into the commits that caused them; substantive
   review-round commits stay, because they document what the closing act
   changed. The result must satisfy: one commit or small commit group per
   issue, every commit message meaningful on `main`, the final tree
   byte-identical to the pre-cleanup tree (verified by an empty
   `git diff` against a backup ref before force-pushing).
3. **Force-push discipline:** history rewrites on the agent branch use
   `--force-with-lease`, happen before promotion or with a note on the PR
   when later, and never after the owner has started reviewing commits
   individually without saying so on the PR.

The "Revert unit = one squash-merged epic" consequence above is superseded:
the revert unit is the per-issue commit, and the sprint rollback point is
the tag.

## Amendment: the merge is the signature, and the tag is the owner's (2026-09-07, owner decision on PR #780)

Two touchpoints had grown a round trip each that the workflow never asked
for.

1. **Step 1 — the merge is the signature.** Planning PRs were written with a
   `DRAFT` / `Proposed` status and opened as GitHub drafts, so adoption took
   three moves: the owner says "passt", the agent edits the status and
   promotes the PR, the owner merges. The decision was already made at
   "passt"; the other two moves were paperwork. From now on a planning PR —
   the sprint plan, a gate-closing ADR, the decisions it carries — is written
   as adopted, its status naming the PR whose merge adopts it, and is opened
   ready for review. The owner merges to adopt or comments to change; a
   rejected decision is removed on the PR, never merged as "proposed". The
   promotion conditions in AGENTS.md ("You own the PR") do not apply to a
   planning PR, which has no closing act.
2. **Step 5 — the tag is an owner action.** The session credential has
   refused every tag push since 0.8.0 and the owner has run the prepared
   command every time. Step 5 now reads that way: the close-out prepares the
   annotated-tag command, the owner runs it. Reversible the day the
   credential gains tag-push rights.

Both are recorded in AGENTS.md at the step they change.

## Amendment: calendar versions made by the Release workflow (2026-10-01, Sprint 17 plan D-11)

`0.<sprint>.0` coupled the number to the sprint, never left 0.x, and depended
on an owner action the agent's credential cannot perform: three tags were
outstanding when the Sprint 17 plan was written.

Therefore:

1. **The version is the calendar's: `YYYY.M.N`.** `N` counts up within the
   month and starts at 1. The number says when a build shipped, not how
   compatible it is; compatibility is the API contract version
   (`GET /api/v1/contract`, ADR-0044 §8), which every release names.
2. **The Release workflow makes it.** Every push to `main` that touches
   shipped paths (what the release image, the companion's image and the
   operator's Compose file are built from) creates the next number as an
   annotated tag through the API and the GitHub Release in the same job,
   with notes generated from the previous release. The release must be made
   in that job, because a tag the workflow token creates triggers no other
   workflow. Docs-only, test-only, planning and CI pushes make no release.
3. **A merge is a release.** With batches cut into lane PRs (the Sprint 16
   retrospective), each lane PR's merge is a rollback point, which is the
   granularity a self-hoster wants.
4. **The tag-push trigger stays.** A tag pushed by hand still becomes a
   release, so the owner keeps a fallback if the workflow's tag write is
   refused, and the old `X.Y.Z` tags keep their releases.
5. **Step 5 changes accordingly.** The close-out names the release the merge
   produced instead of preparing a tag command. The three `0.x` tags left
   outstanding by Sprints 15 and 16 are not created; the first calendar
   release's notes start from `0.14.0`, so nothing drops out of the
   changelog.

Recorded in AGENTS.md at step 5.

## Amendment: a sprint is two PRs, a planning PR and a sprint PR (2026-10-08, owner decision on the PR that carries this amendment)

**Why.**

- **The owner's touchpoints had crept from two to five.** This record
  promised two per epic: the decision sign-off and the behavior acceptance.
  Sprints 17–19 asked for five: the planning merge, one merge per lane PR
  (each followed by the agent moving the next PR's base and pushing again),
  and a close-out PR. Lanes run in parallel rebase onto each other's merges;
  lanes run in sequence wait for the owner between them. The owner's
  attention is the binding constraint this record was written around.
- **The lanes were a repair, not a principle.** This record's batch was one
  branch and one PR. The Sprint 16 batch reached 336 commits, and GitHub
  refuses "Rebase and merge" beyond 100 commits (GitHub Docs, "Repository
  limits": "Merging a pull request using the 'Rebase and merge' option is
  limited to 100 commits"). `main` requires a linear history, so a merge
  commit is not an option, and squash would undo the merge-method
  amendment above. The Sprint 16 retrospective therefore cut batches into
  lane PRs. Sprint 19 landed 90 commits across its three lanes: a cleaned
  sprint fits under the limit.
- **A fresh session executes a finished plan better than the session that
  wrote it.** Claude Code's best-practice guide: "Once the spec is complete,
  start a fresh session to execute it", because performance degrades as the
  context fills. A fresh session also tests whether the plan is complete:
  the planning session would not notice a gap it carries in its memory.
- **A question the agent could answer still costs the owner a read.** The
  Sprint 20 plan listed fifteen decisions; two of them needed the owner.

**What changes.**

1. **Two PRs per sprint.**
   - **The planning PR**, written by a planning session: the plan, its gate
     ADRs, its boards and the registry edits. Opened ready for review; the
     merge is the signature (unchanged). The planning session carries out
     the plan's registry bookkeeping after the merge and ends there.
   - **The sprint PR**, written by a fresh implementation session on one
     branch, `agent/<provider>/sprint-<N>`. The plan's lanes become commit
     groups in the plan's order. It opens as a draft with its first commit.
     Each risk class's closing act runs when its commit group is done, so
     findings are fixed on the branch while the context is fresh; the UAT
     persona runs at the end. The retrospective and the close-out records
     (`sprint-status.yaml`, the epics registry, any readiness summary) are
     its last commits before promotion. It is promoted under the four
     conditions and rebase-merged by the owner.
2. **A commit budget of 90.** The cleaned history of a sprint PR stays at or
   under 90 commits, ten under GitHub's limit to leave room for review
   rounds. The plan estimates the count. A plan that expects more cuts the
   sprint into a stack of PRs, merged as one operation where GitHub's
   stacked pull requests are available, and says why.
3. **Post-merge facts move to the next planning PR.** The merge's CI run on
   `main` and the calendar release it made are confirmed by the
   implementation session when the merge wakes it, reported to the owner in
   one line, and recorded in the next planning PR's verification basis. No
   separate close-out PR.
4. **The owner is asked only what only the owner knows:** a fact on the
   owner's own instance; a change to how stored money data is booked or
   corrected (signed by the planning merge, as before); scope, non-goals and
   the announcement. Everything else the agent decides and records with its
   reason, flippable by a comment. A plan's and a PR's body opens with
   "What you need to do", which may be nothing but the merge.
5. **The implementation session orchestrates.** It gives each story to a
   subagent with a fresh context and a brief that names its base commit,
   reviews and commits the result, and keeps its state in the plan and the
   PR's checklist, which survive a compaction.

**What does not change:** the decision gate before risk-tier semantics; the
closing act and its lenses; the promotion conditions; rebase-merge for a
batch and squash for a small single-concern PR; agents never merge.

**Consequences.**

- **Two owner touchpoints per sprint**, the two this record started with.
- **A money fix reaches the owner's instance at the sprint's end**, not
  after its lane: up to three or four days later. A fix the owner's instance
  needs sooner is cut by the plan into an early PR, with that reason.
- **One unfinished story blocks the merge.** The shrink order applies; a
  story that cannot be finished is reverted out of the branch as its commit
  group and filed, never waited on.
- **One release per sprint.** Item 3 of the calendar-version amendment
  above ("each lane PR's merge is a rollback point") now reads "each sprint
  PR's merge". The revert unit stays the commit group.
- **GitHub sends no event when `main` moves under an open PR.** The
  implementation session rebases onto `main` before each closing act and
  before promotion.
- **The lane-PR carry-forwards are superseded where they assume lane PRs**
  (the Sprint 16 retrospective's cut, the Sprint 18 and 19 stacking rules).
  Their invariants — move a stacked PR's base to `main` before pushing its
  head; every commit passes the gates — still bind a stack.
- **The Sprint 20 plan's D-9** carries a dated note: its three lanes are
  one sprint PR.
