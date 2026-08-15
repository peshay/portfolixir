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
happening. As-of membership avoids that and is **reconstructible in principle**:
`Portfolixir.Classifications.upsert_assignment/4` journals every custom-tree
assignment as a `security_category_assignment` create/update with the prior
assignment as its before-image ([ADR-0017](0017-append-only-audit-journal.html),
FR-28), and built-in trees derive from security fields whose changes the Catalog
context journals. But the audit journal is an append-only forensic record, not a
temporal index: answering "which category held this security on 2019-04-11"
means replaying its entries backwards from today, for every security, for every
day of the window. That is a different data structure, not a different query.

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

### 2. v1 measures under current membership, and says so

v1 applies **today's** classification across the whole window. Rationale: it is
exact, cheap, reproducible from data the system holds directly, and needs no new
storage. As-of membership stays out of v1 because it needs a temporal membership
index the system does not have, and building one inside a first slice would put
the hardest part of the feature in the same commit as its first number.

The consequence is stated rather than hidden: **reclassifying a security changes
its category's past figures.** That is a real limitation, it is visible in the
payload, and it is the reason §4 exists.

### 3. Computation basis in every payload (review-blocking)

Per the identity gate's requirement for level (a)–(c) analytics, each
per-category figure carries, in the API and MCP payload and not only in a doc
page:

- the **membership basis** (`current` in v1) and the plain statement that
  reclassification restates history under it;
- the **input series and window**, the **base currency**, and the treatment of
  gaps — inherited unchanged from the existing walk
  ([ADR-0016](0016-rounding-policy.html): full precision in compute, rounding
  only at the human display; the AR-4 gap-marker contract for missing quotes);
- the **freshness stamp** (`as_of`, and a stale marker when behind its inputs)
  that [ADR-0039](0039-durable-derived-values.html) §C4 requires of every derived
  value;
- for contribution, the **level** it decomposes and the statement that the level
  sums to the total.

### 4. As-of membership is the named follow-up, with its precondition

The as-of variant is not vetoed — it is sequenced behind the thing it needs: a
temporal membership index derived from the journaled assignment history, built
once and maintained forward, rather than replayed per query. That work sits
directly behind the audit-journal rollout completion (#677) and should be judged
on whether the restatement problem actually bites in use. When it lands, the
membership basis in §3 becomes a value the caller can choose, and the existing
`current` answer keeps working unchanged.

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

Only §2 is a genuine choice rather than a consequence: **v1 measures under
current membership, accepting that reclassification restates past category
figures, with as-of membership sequenced behind #677.** The rest follows from
it. If the restatement is unacceptable at v1, this ADR does not shrink — it
grows a temporal membership index and a much larger first slice.

## Consequences

- Positive: the classification tree stops being only a description; a category
  that carries both a target weight and a realized return is the pair a
  rebalancing decision actually needs. It is also the first capability where
  Portfolixir is ahead of Portfolio Performance rather than catching up.
- Negative / accepted: under `current` membership, category history is not
  stable across reclassification. Named in the payload, not buried.
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

- [ADR-0017](0017-append-only-audit-journal.html) — the assignment history this
  decision reads as *possible but not yet queryable*
- [ADR-0020](0020-view-bound-soll-plans.html) — target weights per category
- [ADR-0035](0035-one-pricing-pass-per-read.html) — one pricing pass per read
- [ADR-0039](0039-durable-derived-values.html) — materialization and freshness
- #572 benchmark comparison · #677 audit-journal rollout completion
- Owner feedback triage 2026-08-15, Round 2/A3
