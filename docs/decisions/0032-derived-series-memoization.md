---
layout: docs
title: "ADR-0032: memoized derived series — cache the daily TTWROR walk in volatile memory, warm it at boot, and never make the maintainer wait on a skeleton"
description: Proposed decision to cache the period-independent daily performance walk in an ETS-backed memo owned by a supervised process, keyed by portfolio, view scope, walk end date and a global data-version counter bumped by every financial write; to warm the memo at boot; and to render the last known series immediately while a fresh one computes in the background, always labelled with its as-of. The cache is defined as a pure memo that never survives a restart and never becomes a source of truth, so ADR-0004 (holdings are never stored) is untouched.
---

# ADR-0032: memoized derived series — cache the daily TTWROR walk in volatile memory, warm it at boot, and never make the maintainer wait on a skeleton

- **Status:** Proposed (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html); owner sign-off pending —
  [#562](https://github.com/peshay/portfolixir/issues/562))
- **Date:** 2026-07-29

## Context

`Portfolixir.Portfolios.Performance.analysis/2` walks
`Date.range(walk_start, today)` day by day, re-projecting holdings and
re-pricing every day of the portfolio's whole history. Issue #562 records the
consequence from the 2026-07-12 product review: **every** dashboard and Wealth
mount shows a multi-second skeleton, on every refresh.

The walk is already cached where it is cheap to cache — on the LiveView socket
(`portfolio_live.ex`), which is why switching periods is instant: `summarise/2`
re-chains an existing analysis without new queries. Nothing survives the mount,
so a page reload pays the full cost again. The dashboard is worse: it computes
per-portfolio valuation, YTD TTWROR, drift alerts and data quality in one async
block.

The reason this has not simply been fixed is a real design tension, and the
issue names it: a cross-mount cache of a derived series brushes against
[ADR-0004](0004-holdings-derived-from-transactions.html) — *holdings are never
stored, they are derived from transactions*. That principle is what makes the
app auditable: there is no second copy of the truth to drift.

**The problem is three waits, not one**, and an early draft of this ADR only
addressed the first (owner review, 2026-07-29):

1. **The repeat wait** — the same series recomputed on every mount and every
   reload. A memo removes it (§1–§4).
2. **The first wait after a restart** — nothing is memoized yet, so the first
   page of the day pays full price. Warming at boot removes it (§6).
3. **The unavoidable wait** — the very first computation, or the one right
   after a write. It cannot be removed, only *hidden*: show the last known
   series immediately, labelled, and swap it when the fresh one lands (§7).

Two further constraints shape the answer:

- The fix must be **output-identical**. `#611` has just corrected the return
  base (trade-price basis steps are not return, ADR-0010 amendment) and left
  behind exactly the right proof material, including the synthetic four-year
  fixture that used to chain to **+2,567.5 %**. Caching a series is only worth
  doing if it provably changes nothing about the numbers.
- Portfolixir is a **single-node, self-hosted** application. There is no
  cluster to keep coherent, and no multi-tenant isolation to get wrong.

## Decision

### 1. A memo, not a store

The cache is defined as a **memoization of a pure function**, and every other
decision here follows from that definition:

```text
analysis(portfolio_id, view, today)  is a pure function of
  (stored transactions, stored quotes, stored exchange rates,
   stored bucket/view definitions, today)
```

The cache holds the result of that function and nothing else. Concretely:

- it lives in **volatile memory only** (ETS owned by a supervised process) and
  is empty after every restart;
- it is **never read as a source of truth**: dropping the table at any moment
  changes latency and nothing else. This is the property that keeps ADR-0004
  intact — no derived holdings are *stored*; a computation is *remembered*
  until the inputs change;
- it is never written to from a request path other than "I just computed this";
- nothing is ever served from it that could not be recomputed on the spot.

This is deliberately a weaker claim than "a cache invalidated correctly". A
cache that must be invalidated correctly to be correct is a second source of
truth. A memo keyed by a version of its inputs is not: a missed bump degrades
to a stale *number on screen* only if the key fails to change, which §3 makes
structurally hard rather than a matter of discipline.

### 2. Key

```text
{portfolio_id, view_scope_key, today, portfolio_data_version}
```

- `view_scope_key` — the view id, or `:unscoped` for the "everything" scope, so
  a scoped and an unscoped walk never collide (#444).
- `today` — the walk's end date, already an explicit option on `analysis/2`
  (`:today`, injected in tests). Including it means a day rollover misses
  naturally, with no timer and no staleness window.
- `data_version` — **this portfolio's** version counter, see §3.

Entries whose `data_version` is not current can never be read *as current*,
because a read always composes the current version into the key. They are not
dead weight either: §6 renders exactly one such entry — the most recent
superseded one — while the fresh series computes.

The sweep therefore keeps **one previous generation per
`{portfolio_id, view_scope_key, today}`** and drops everything older. Two
generations is the whole bound: enough to show something instead of a
skeleton, not enough to accumulate history.

### 3. Invalidation: targeted, with a global fallback that cannot be forgotten

**Owner decision, 2026-07-29.** An earlier draft proposed one global counter
bumped by every write, on the grounds that over-invalidation is cheap and
mis-targeted invalidation is dangerous. The owner chose **targeted
invalidation** — only the affected portfolios lose their memo. This section is
rewritten to that decision, and its job is to make the dangerous half
structurally hard rather than a matter of care.

The danger is real and worth stating plainly: a write whose blast radius is
computed too narrowly leaves a stale series readable *as current*, and nothing
on screen would reveal it. So the design does not rest on getting every case
right. It rests on **failing toward recomputation**.

#### 3.1 Per-portfolio versions, not one counter

Each portfolio carries its own `data_version`. The memo key (§2) uses that
portfolio's version, so invalidating one portfolio leaves every other memo
readable.

#### 3.2 "Affected" is defined per write kind — and historically

The blast radius of a write is **not** "the portfolios currently holding the
thing". The series is historical, so a portfolio that held a security in 2019
and sold it in 2020 is still affected by a 2019 quote for it. Every rule below
therefore reads *ever held*, not *holds now*:

| Write | Portfolios invalidated |
| --- | --- |
| Transaction create / update / delete | the transaction's portfolio, **plus** the counter-portfolio of a transfer (both legs move quantity) |
| Split booking | every portfolio that has ever transacted the security |
| Quote upsert | every portfolio that has ever transacted the security |
| Exchange-rate upsert | every portfolio whose base currency differs from the currency of any account or ever-held security |
| Cash account / depot create, update, delete | the owning portfolio |
| Portfolio update (base currency!) | that portfolio |
| Bucket / view definition change | every portfolio reachable through that view's scope |
| Import apply | the union of the above, per applied transaction |

`ever transacted` is a cheap indexed query the codebase already has in one
form (`Ledger.security_ids_with_transactions/0`); the inverse direction is the
same index read the other way round.

#### 3.3 The fallback: anything unlisted invalidates everything

The table above is an **allowlist of narrow cases**. The resolver's default
clause — every write kind not explicitly listed, and every listed case whose
lookup raises or returns an incomplete answer — invalidates **all** portfolios.

This is the whole safety argument, and it inverts the usual failure direction:

- forgetting to add a new write kind to the table costs **a recomputation**,
  which is exactly today's behaviour;
- there is no path in which a write silently affects nothing.

A default clause that narrowed instead of widened would be the one design
mistake this section exists to prevent, so the resolver has no catch-all that
returns an empty list. That is enforced by an AST meta-test, the same technique
that keeps `Ledger.Projection.effects/1` free of a defensive fallback.

#### 3.4 Where the bump happens

| Write | Seam |
| --- | --- |
| Any journaled financial write | `Portfolixir.Journal.record/3` — every such write must already pass through it (ADR-0017), so the seam cannot be bypassed without also failing the journal guard trigger |
| Quote upserts | `Catalog.Quotes.upsert_many/3` — allowlisted out of the journal (market data), so it needs its own bump |
| Exchange-rate upserts | `Fx.upsert_many/1` — same reason |

The journal seam stays load-bearing: it is the reason a *new* write path cannot
skip invalidation entirely. What §3.2 adds is only *how narrow* the
invalidation may be, and §3.3 guarantees that "narrow" degrades to "everything"
rather than to "nothing".

### 4. Staleness contract

- **Within a request:** none. A read either finds an entry for the current
  version or computes one.
- **Across a write:** the next read for an affected portfolio sees its new
  version and recomputes; unaffected portfolios keep their memo. No read is
  ever served a pre-write series *silently* — the bump happens in the same
  transaction as the journal insert, and §3.3 makes "affected" default to
  "all" whenever the answer is not certain.
- **The one accepted window (§6):** while that recomputation runs, the surface
  may render the previous series — **labelled with its as-of and marked as
  recomputing**, never unmarked. The window closes on its own when the fresh
  series lands. This is the single deliberate exception in this ADR, and it is
  visible by construction; everywhere else, stale means recompute.
- **Across a day boundary:** handled by `today` in the key.
- **Across a restart:** cold, by design.
- **Across nodes:** out of scope — single-node application. Should that ever
  change, this ADR is superseded, not extended.

### 5. Warm the memo at boot

A supervised task recomputes the analyses the maintainer actually opens —
every portfolio at the `:unscoped` scope plus each portfolio's default view —
as soon as the application has booted, and repeats once per calendar day
rollover.

- It runs **after** the supervision tree is up and never blocks it: a slow or
  failing warm-up must not prevent the app from serving.
- It writes through the same memo API as a request would. There is no separate
  "warm" path that could compute the series differently — the warm-up is a
  caller, not a second implementation.
- It is bounded: the scopes above, not the cross product of every view and
  every period. Periods are free (`summarise/2` re-chains an existing
  analysis).
- It is skippable by the same configuration switch that disables the cache
  (§7.3), so "cache off" stays a single, testable state.

### 6. Serve the last known series while a fresh one computes

The memo cannot help the very first computation, or the one immediately after a
write. That wait is real work and cannot be removed — but the maintainer does
not have to *watch* it.

**When a current-version entry is missing but a previous-version entry for the
same `{portfolio_id, view_scope_key}` exists, the surface renders the previous
one immediately, labelled with its as-of and marked as recomputing, and swaps
in the fresh series when it arrives.**

This is a **deliberate, bounded staleness window**, and it is the one place
this ADR accepts one. It is not the TTL rejected below: a TTL means *maybe
old, no one is fixing it*; this means *old, saying so, and being fixed right
now*. The difference is that the staleness is visible and self-terminating.

The honesty rules are therefore load-bearing, not decoration:

- a superseded series is **always** rendered with its as-of and a recomputing
  marker — never silently, never as if current;
- the swap happens in one update, so no number is ever half-old and half-new;
- if the recomputation fails, the marker becomes an error state; the stale
  number is never left standing as if it had been confirmed.

Precedent inside this repo: the tax trim budget shipped in the same batch
already states "as of <date>" plus a stale marker, for the same reason (a
number that decays without the maintainer acting). This reuses that pattern
rather than inventing a second one.

**Scope (owner decision, 2026-07-29).** This applies to the performance series
and its chart **and to the dashboard tiles** that render derived figures. The
draft limited it to the chart; the owner extended it, on the reasoning that the
overview page is exactly where the wait is felt most.

The honesty rules above are what make the wider scope defensible, and they are
therefore not optional on a tile: a tile showing a superseded figure carries
the same as-of and recomputing marker as the chart. A tile too small for both
does not qualify for this treatment and recomputes instead — shrinking the
label is not an option, because an unlabelled stale number is precisely the
failure this section is built to avoid.

Still out of scope: figures a decision is sized against on the spot, such as
the tax trim budget, which already has its own recorded as-of and must not
acquire a second, different notion of "old".

### 7. What must be proven, not assumed

Implementation is gated on an **output-identical** test, not on a benchmark:

1. For every fixture of the `#611` performance suite — including the four-year
   synthetic fixture that used to chain to `+2,567.5 %` — `analysis/2` with a
   warm cache must be `Decimal`-exactly equal to `analysis/2` with the cache
   disabled, series point by series point.
2. A write of each kind in the §3 table, followed by a read, must return the
   post-write series (the invalidation test, one per seam).
3. The cache must be switchable off by configuration, and the whole suite must
   pass with it off — that is what makes "dropping it changes only latency" a
   checked claim rather than a sentence in an ADR. The switch also disables the
   warm-up, so there is one "off" state, not two.
4. The warm-up must produce byte-identical entries to a request-path
   computation for the same key, and a warm-up that raises must leave the
   application serving.
5. A superseded series must never render without its as-of and its recomputing
   marker, and a failed recomputation must surface as an error rather than
   leaving the stale number standing (§6). Asserted on the surface — chart and
   dashboard tile — not only in the engine.
6. **One invalidation test per row of the §3.2 table**, each written as
   "write, then read, and assert the post-write series" — including the two
   historical cases that are easy to get wrong: a quote for a date in a
   portfolio's past that it no longer holds, and an FX rate affecting a
   portfolio through an account currency rather than a holding.
7. **The resolver has no narrowing catch-all.** An AST meta-test asserts that
   its default clause invalidates all portfolios, mirroring the meta-test that
   keeps `Ledger.Projection.effects/1` free of a defensive fallback. A future
   write kind nobody wired up must degrade to full invalidation, never to
   none.

## Consequences

- Warm mounts render without the multi-second skeleton (#562's second
  acceptance criterion). The first mount after a restart is warm too (§5).
  The genuinely uncomputable case renders the previous series immediately
  instead of a skeleton (§6), so the maintainer never watches an empty chart.
- ADR-0004 is untouched and explicitly reaffirmed: no derived holdings are
  persisted. A reviewer checking that principle only has to confirm the memo is
  volatile and keyed by an input version.
- The dashboard's combined async block benefits without being restructured.
  Its other three computations (valuation, drift alerts, data quality) are
  tracked separately as
  [#619](https://github.com/peshay/portfolixir/issues/619), to be measured once
  this lands rather than optimised on suspicion.
- Memory: one analysis map per `(portfolio, scope, day)` actually visited,
  swept on every bump. For a self-hosted single-maintainer instance this is
  small; a bound (max entries, oldest evicted) is part of the implementation,
  not of this decision.
- One accepted staleness window, bounded and visible (§6), now spanning the
  chart and the dashboard tiles. It is the price of never showing a skeleton,
  and it is paid only where a previous series exists.
- Targeted invalidation (§3) keeps unrelated portfolios warm across a write.
  The cost is a per-write blast-radius resolver that must be maintained as new
  write kinds appear — bounded by §3.3, which turns neglect into a
  recomputation rather than a wrong number.
- **Not decided here, deliberately:** persisting the series across restarts,
  incremental/append-only extension of a walk (see Alternatives), caching
  valuation or allocation, and extending §6 to figures other than the
  performance series. Each is a separate decision with its own risk.

## Alternatives considered

- **One global counter for all invalidation.** This was the draft's proposal
  and the owner rejected it in favour of targeted invalidation (§3). The
  concern that motivated it stands — "which portfolios does this write affect?"
  is a non-trivial query for quotes and FX rates, and getting it too narrow
  yields a silently wrong number — so it is answered structurally instead of
  by argument: §3.3 makes every unlisted or uncertain case invalidate
  everything, which is exactly the global behaviour, reached automatically
  whenever the targeted path cannot prove a narrower answer.
- **Incrementally extending a cached walk instead of recomputing it.**
  Rejected, and this is the sharpest trade-off in the decision. It is the
  obvious optimisation — the walk is chronological, so why not append the new
  days and keep the rest? Because the inputs are **not** append-only. A
  back-dated transaction, a quote delivered late for an old date, an imported
  split, a corrected FX rate: each rewrites the series *behind* its own date,
  not just after it. An incremental update is therefore only sound for the
  strictly-appending case, and distinguishing that case reliably from the
  rewriting one is the same dependency-tracking problem §3 rejects, with the
  same failure mode — a series that looks right and is not. Throwing the memo
  away and recomputing costs exactly what the app costs today; getting an
  incremental update wrong costs a wrong number nobody can see is wrong. If
  this is ever revisited, it needs its own ADR and its own proof that the
  append case is detectable, not just that it is common.
- **Time-based expiry (TTL).** Rejected: a TTL is a staleness *window* by
  construction. For a number the maintainer sizes a trim against, "correct
  within five minutes" is not a contract worth having when "correct" is
  available for the same effort.
- **Persisting the series to Postgres.** Rejected: that *is* storing derived
  data, and it inherits the migration, backup and drift problems ADR-0004
  exists to avoid.
- **Doing nothing.** Rejected by #562: the cost is paid by the maintainer on
  every single page load, and the review named it explicitly.

## References

- [ADR-0004](0004-holdings-derived-from-transactions.html) — holdings are
  derived, never stored; the principle this decision is checked against
- [ADR-0010](0010-ttwror-performance-series.html) — the performance definitions being
  memoized, including the 2026-07-24 amendment landed by `#611`
- [ADR-0012](0012-asset-class-inference-at-read-time.html) — the precedent for
  computing derived values at read time
- [ADR-0017](0017-append-only-audit-journal.html) — the journal seam this
  decision hangs invalidation off
- [ADR-0026](0026-epic-batch-workflow.html) — decision gate
- Issue [#562](https://github.com/peshay/portfolixir/issues/562) — the problem
  statement and its acceptance criteria; issue
  [#545](https://github.com/peshay/portfolixir/issues/545) / PR `#611` — the
  return-base fix whose fixtures become this decision's proof material
