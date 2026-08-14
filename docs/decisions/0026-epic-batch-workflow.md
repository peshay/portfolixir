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
  small PRs stay squash-merged). Everything else here stands.
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
