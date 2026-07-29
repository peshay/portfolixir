---
layout: docs
title: "ADR-0032: memoized derived series — cache the daily TTWROR walk in volatile memory, keyed by a global data version"
description: Proposed decision to cache the period-independent daily performance walk in an ETS-backed memo owned by a supervised process, keyed by portfolio, view scope, walk end date and a global data-version counter bumped by every financial write, with the cache defined as a pure memo that never survives a restart and never becomes a source of truth, so ADR-0004 (holdings are never stored) is untouched.
---

# ADR-0032: memoized derived series — cache the daily TTWROR walk in volatile memory, keyed by a global data version

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

Entries whose `data_version` is not current are dead weight, not wrong answers:
they can never be read, because reads always compose the current version into
the key. A sweep on bump keeps the table bounded.

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
  version and recomputes. There is no window in which a post-write read can be
  served a pre-write series, because the bump happens in the same transaction
  as the journal insert.
- **Across a day boundary:** handled by `today` in the key.
- **Across a restart:** cold, by design.
- **Across nodes:** out of scope — single-node application. Should that ever
  change, this ADR is superseded, not extended.

### 5. What must be proven, not assumed

Implementation is gated on an **output-identical** test, not on a benchmark:

1. For every fixture of the `#611` performance suite — including the four-year
   synthetic fixture that used to chain to `+2,567.5 %` — `analysis/2` with a
   warm cache must be `Decimal`-exactly equal to `analysis/2` with the cache
   disabled, series point by series point.
2. A write of each kind in the §3 table, followed by a read, must return the
   post-write series (the invalidation test, one per seam).
3. The cache must be switchable off by configuration, and the whole suite must
   pass with it off — that is what makes "dropping it changes only latency" a
   checked claim rather than a sentence in an ADR.

## Consequences

- Warm mounts render without the multi-second skeleton (#562's second
  acceptance criterion). Cold mounts are unchanged.
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
- **Not decided here, deliberately:** persisting the series across restarts,
  incremental/append-only extension of a walk, caching valuation or allocation,
  and any background pre-warming. Each is a separate decision with its own
  risk; this ADR buys the cheapest correct win and stops.

## Alternatives considered

- **Per-portfolio invalidation.** Rejected: quotes and FX rates are global
  inputs, so the "which portfolios does this write affect?" query is itself
  non-trivial and its failure mode is a silently wrong number.
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
