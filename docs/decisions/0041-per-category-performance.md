---
layout: docs
title: "ADR-0041: per-category performance — a classification category carries its own return"
description: Categories describe the portfolio today; they do not evaluate it. This decision gives every category its own return series and contribution figure, so the classification tree answers which part of the strategy worked rather than only how much of it there is. v1 measures under current membership because historical membership is reconstructible only by replaying the audit journal; the basis is stated in every payload and the as-of variant is named as the follow-up rather than implied.
---

# ADR-0041: per-category performance — a classification category carries its own return

- **Status:** Proposed (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html); owner sign-off outstanding — see
  "What needs the owner's yes" below)
- **Date:** 2026-08-15

## Context

Classification trees are a way of **describing** the portfolio: a category has a
share, a target weight ([ADR-0020](0020-view-bound-soll-plans.html)) and a drift
([ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html)). None of
those says whether the category was any good. The owner's observation (feedback
triage 2026-08-15, Round 2/A3) is that Portfolio Performance does not have this
either — its classifications carry no performance series — and that it is
exactly the missing half of a rebalancing decision: today the operator can see
that a category is 4 points overweight and cannot see whether it earned that
weight.

Three things make this the right time rather than a wish:

- **The identity gate already permits it.** The scope ladder that replaced the
  blanket "no advanced reports" rule (product brief #663) puts comparison and
  decomposition — contribution analysis, exposure breakdown — at level **(b)**,
  in scope. No new permission is needed; what is needed is a computation basis.
- **The substrate exists.** [ADR-0039](0039-durable-derived-values.html) made
  derived values materializable with a lifetime per analytic. A per-category
  daily walk is precisely the kind of value that must not be recomputed per page
  view.
- **The engine exists.** `Portfolixir.Portfolios.Performance` already walks days
  and prices positions; [ADR-0035](0035-one-pricing-pass-per-read.html) already
  threads one pricing pass through a read. This is a new *grouping* of an
  existing computation, not a new one.

**The hard part is not the arithmetic — it is membership over time.** A
security's category is not a constant. Reclassifying one changes which bucket
its history belongs to, and the two available answers give different numbers:

- **current membership** — apply today's classification across the whole window;
- **as-of membership** — apply, for each day, the classification as it stood
  that day.

Both are defensible. Shipping one without saying which is not: a metric without
a definition is an opinion with decimal places.

Current membership has a real cost — reclassifying a security silently rewrites
a past category return, so "did this category work?" can change without any trade
happening.

As-of membership avoids that, and a first reading suggested it was merely
*expensive*: `Portfolixir.Classifications.upsert_assignment/4` journals every
custom-tree assignment as a `security_category_assignment` create/update carrying
the prior assignment as its before-image
([ADR-0017](0017-append-only-audit-journal.html), FR-28), and built-in trees
derive from security fields whose changes the Catalog context journals. Two facts
say otherwise, and together they decide this ADR:

1. **The journal is a forensic record, not a temporal index.** Answering "which
   category held this security on a given day" from it means replaying entries
   backwards from today, per security, per day. That is a different data
   structure, not a different query.
2. **The history does not reach back far enough to matter.**
   `20260623130000_arm_assignments_journal.exs` armed assignment journaling on
   **2026-06-23**. Holdings histories in this system come from Portfolio
   Performance imports spanning years. For every day before that migration there
   is no assignment history at all, so an as-of computation would have to fall
   back to current membership anyway.

So as-of membership is not "better but costlier". It is **exact for the weeks
since the journal was armed and identical to current membership for the years
before** — while costing a temporal index, a backfill story it cannot honour, and
a second membership basis in every payload. That is a bad trade today and a
possibly good one in a few years, which is a sequencing fact rather than a
scoping one.

## Decision

### 1. Two figures, not one — they answer different questions

- **Category return** — how did this part of the portfolio perform, measured
  the same way the whole is measured (TTWROR over the daily walk, restricted to
  the category's members).
- **Category contribution** — how much did this part move the total, i.e. the
  weight-times-return term whose sum over a level reconstructs the total return.

The owner's phrasing points at the first; the rebalancing use needs the second.
Shipping only one would send the reader to the wrong conclusion — a small
category with a spectacular return contributes almost nothing, and a figure that
does not say which question it answers invites exactly that error. Contributions
**must sum to the total** at each level, and that identity is a test, not a hope.

### 2. Current membership, with a restatement marker

v1 applies **today's** classification across the whole window — not as a
compromise but because, for the period that carries the portfolio's history, it
is the only membership the system knows (Context, fact 2).

The consequence is real and must not be silent: **reclassifying a security
changes its category's past figures.** A return series that moves without a trade
looks like a arithmetic error to anyone who does not know why, and this system's
whole claim is that its numbers are explainable.

So the basis ships with a **restatement marker**: a category whose membership
changed inside the reported window carries a flag saying its series was
recomputed under the current classification, in the payload and on the surface.
It is cheap — the assignment journal already records exactly the events that set
it, from 2026-06-23 forward, which is precisely the period in which a
reclassification can still surprise the reader.

This is the same principle the rest of this feedback round turned on: a figure
that cannot explain its own movement is an alarm without an address.

### 3. Computation basis in every payload (review-blocking)

Per the identity gate's requirement for level (a)–(c) analytics, each
per-category figure carries, in the API and MCP payload and not only in a doc
page:

- the **membership basis** (`current` in v1), the plain statement that
  reclassification restates history under it, and the **restatement marker** of
  §2 where it applies;
- the **input series and window**, the **base currency**, and the treatment of
  gaps — inherited unchanged from the existing walk
  ([ADR-0016](0016-rounding-policy.html): full precision in compute, rounding
  only at the human display; the AR-4 gap-marker contract for missing quotes);
- the **freshness stamp** (`as_of`, and a stale marker when behind its inputs)
  that [ADR-0039](0039-durable-derived-values.html) §C4 requires of every derived
  value;
- for contribution, the **level** it decomposes and the statement that the level
  sums to the total.

### 4. As-of membership is deferred by arithmetic, not by appetite

The as-of variant is not vetoed and not merely postponed for effort. It is
deferred because **its answer today is mostly the same answer**: exact only back
to 2026-06-23, and identical to `current` for every year before that. Building a
temporal membership index now would buy weeks of precision at the price of a
second basis in every payload.

It becomes worth building when the journaled history is long enough that "as-of"
and "current" genuinely diverge over a period a reader cares about — a question
of elapsed time, not of engineering. When that day comes, the membership basis in
§3 becomes a value the caller chooses, the `current` answer keeps working
unchanged, and the restatement marker of §2 is what will have shown whether the
divergence ever mattered.

*(This section previously named the audit-journal rollout (#677) as the
precondition. That was wrong: assignment writes have been journaled since
2026-06-23, so #677 blocks other write paths, not this one. The real constraint
is the length of the recorded history.)*

### 5. Scope of this decision

In: the two figures, the membership basis, the payload contract, and
materialization under ADR-0039's rules. Out, deliberately: benchmark comparison
per category (that is #572's shape, and should reuse this grouping rather than
grow its own), factor/sector/region exposure beyond what the catalog already
holds, and anything needing partial-weight assignment of one security to several
categories — which `CONTRIBUTING.md` keeps out of scope and this ADR does not
reopen. Every security belongs to exactly one category per tree, which is what
makes the contribution identity in §1 hold at all.

## What needs the owner's yes

Only §2 is a genuine choice; everything else follows from it. Three forms it
could take, with the recommendation stated rather than implied:

| | Basis | Assessment |
|---|---|---|
| **A+** | Current membership **plus the restatement marker** — what §2 decides | **Recommended.** The marker costs almost nothing and converts a silent restatement into an explained property |
| A | Current membership, no marker | Defensible only if reclassification effectively stops once a tree is settled. Then the marker is dead weight |
| B | As-of membership from the start | Exact back to 2026-06-23 and identical to A before that, for the price of a temporal index and a second basis in every payload |

The recommendation is A+. What would change it: if reclassification is genuinely
rare once a tree is stable, A is enough. Nothing plausible argues for B *now* —
its value grows with the length of the journaled history, so it is a decision
worth revisiting in a couple of years, not a fork in this one.

## Consequences

- Positive: the classification tree stops being only a description; a category
  that carries both a target weight and a realized return is the pair a
  rebalancing decision actually needs. It is also the first capability where
  Portfolixir is ahead of Portfolio Performance rather than catching up.
- Negative / accepted: under `current` membership, category history is not
  stable across reclassification. Named in the payload and marked per category,
  not buried.
- Accepted and worth stating plainly: for the imported years this limitation is
  **unavoidable, not chosen** — no membership history exists for them under any
  design short of reconstructing it by hand.
- The per-category walk multiplies the daily walk's cost by the number of
  categories unless it shares one pass. It must be computed as a **grouping
  within the existing walk**, not as N walks — ADR-0035's rule applies with more
  force here than anywhere it has applied so far.
- Risk-tier attention ([ADR-0036](0036-risk-tier-rides-the-batch.html)): the
  contribution identity (level sums to total) is the invariant at stake, pinned
  by exact `Decimal` expectations before implementation.
- Two-way coverage: this is an agent-visible capability first, so the API and
  MCP surface may lead — with the PR stating why, and the human view landing in
  the same or the next batch, where the close-out check will look for it.

## References

- [ADR-0017](0017-append-only-audit-journal.html) — the assignment history, armed
  for assignments by `20260623130000_arm_assignments_journal.exs` and therefore
  reaching back only to 2026-06-23
- [ADR-0020](0020-view-bound-soll-plans.html) — target weights per category
- [ADR-0035](0035-one-pricing-pass-per-read.html) — one pricing pass per read
- [ADR-0039](0039-durable-derived-values.html) — materialization and freshness
- #572 benchmark comparison
- Owner feedback triage 2026-08-15, Round 2/A3
