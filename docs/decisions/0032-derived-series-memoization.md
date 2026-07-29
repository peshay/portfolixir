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
{portfolio_id, view_scope_key, today, data_version}
```

- `view_scope_key` — the view id, or `:unscoped` for the "everything" scope, so
  a scoped and an unscoped walk never collide (#444).
- `today` — the walk's end date, already an explicit option on `analysis/2`
  (`:today`, injected in tests). Including it means a day rollover misses
  naturally, with no timer and no staleness window.
- `data_version` — see §3.

Entries whose `data_version` is not current can never be read *as current*,
because a read always composes the current version into the key. They are not
dead weight either: §6 renders exactly one such entry — the most recent
superseded one — while the fresh series computes.

The sweep therefore keeps **one previous generation per
`{portfolio_id, view_scope_key, today}`** and drops everything older. Two
generations is the whole bound: enough to show something instead of a
skeleton, not enough to accumulate history.

### 3. Invalidation: one global counter, bumped at the write seams

**A single monotonic `data_version` counter, bumped by every write that can
change any walk.** Not per-portfolio, not per-security, not dependency-tracked.

Fine-grained invalidation is where cache bugs live: a quote write affects every
portfolio holding that security, an FX write affects every portfolio whose base
currency differs from any holding, a view edit re-scopes an arbitrary set. The
dependency graph is real work to compute and easy to get subtly wrong, and the
failure mode is *a wrong number the maintainer cannot tell is wrong*.

Over-invalidation costs one recomputation — the exact cost we have today. The
asymmetry is overwhelming, so the coarse counter wins.

Bump sites:

| Write | Seam |
| --- | --- |
| Any journaled financial write (transactions, portfolios, accounts, splits, classifications, targets, tax) | `Portfolixir.Journal.record/3` — every such write is already required to pass through it (ADR-0017), so this is one seam that cannot be forgotten |
| Quote upserts | `Catalog.Quotes.upsert_many/3` — allowlisted out of the journal (market data), so it needs its own bump |
| Exchange-rate upserts | `Fx.upsert_many/1` — same reason |
| Import apply | already journaled per transaction; no extra site |

The journal seam is the load-bearing part: "every financial write is journaled"
is an invariant this repo already enforces with a per-table guard trigger and a
meta-test. Hanging invalidation off it means a new write path cannot silently
skip invalidation without also skipping the journal, which fails loudly.

The two market-data seams are the deliberate exception and are named in the
implementation's test list.

### 4. Staleness contract

- **Within a request:** none. A read either finds an entry for the current
  version or computes one.
- **Across a write:** the next read after a committed write sees the new
  version and recomputes. No read is ever served a pre-write series *silently*
  — the bump happens in the same transaction as the journal insert.
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

**Scope limit.** This applies to the performance series and its chart. It is
deliberately *not* extended here to figures a decision is sized against on the
spot — those either recompute or say nothing. Extending it is a later
decision, not an implied one.

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
   leaving the stale number standing (§6). Asserted on the surface, not only in
   the engine.

## Consequences

- Warm mounts render without the multi-second skeleton (#562's second
  acceptance criterion). The first mount after a restart is warm too (§5).
  The genuinely uncomputable case renders the previous series immediately
  instead of a skeleton (§6), so the maintainer never watches an empty chart.
- ADR-0004 is untouched and explicitly reaffirmed: no derived holdings are
  persisted. A reviewer checking that principle only has to confirm the memo is
  volatile and keyed by an input version.
- The dashboard's combined async block benefits without being restructured; if
  it still feels slow afterwards, that is a separate finding about its other
  three computations, not about this cache.
- Memory: one analysis map per `(portfolio, scope, day)` actually visited,
  swept on every bump. For a self-hosted single-maintainer instance this is
  small; a bound (max entries, oldest evicted) is part of the implementation,
  not of this decision.
- One accepted staleness window, bounded and visible (§6). It is the price of
  never showing a skeleton, and it is paid only where a previous series exists.
- **Not decided here, deliberately:** persisting the series across restarts,
  incremental/append-only extension of a walk (see Alternatives), caching
  valuation or allocation, and extending §6 to figures other than the
  performance series. Each is a separate decision with its own risk.

## Alternatives considered

- **Per-portfolio invalidation.** Rejected: quotes and FX rates are global
  inputs, so the "which portfolios does this write affect?" query is itself
  non-trivial and its failure mode is a silently wrong number.
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
