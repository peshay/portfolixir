---
layout: docs
title: "ADR-0035: one pricing pass per read — shared preloaded market data instead of six re-derivations"
description: Decision for issue #619. A dashboard mount prices the same holdings six times and issues per-position lookups for securities, quotes and exchange rates. Rather than memoizing that redundancy (the ADR-0032 extension), the redundancy is removed - market data is preloaded once per read into an explicit pricing context and threaded into every valuation and allocation in that read. No new stored state, no cache, no invalidation surface; Decimal-identical output is the acceptance criterion.
---

# ADR-0035: one pricing pass per read — shared preloaded market data instead of six re-derivations

- **Status:** Accepted (owner sign-off 2026-08-03 —
  [#619](https://github.com/peshay/portfolixir/issues/619); decision gate per
  [ADR-0026](0026-epic-batch-workflow.html))
- **Date:** 2026-08-03

## Context

### What was measured

Issue [#619](https://github.com/peshay/portfolixir/issues/619) measured the
dashboard mount's async block after [ADR-0032](0032-derived-series-memoization.html)
landed (`_bmad-output/implementation-artifacts/619-dashboard-mount-measurement-2026-07-31.md`,
synthetic dataset, one fresh VM per run). In the warm steady state the block
costs ~388 ms, split as:

| Step | Median | Share |
| --- | --- | --- |
| View valuation | 167.8 ms | 43 % |
| Drift alerts (5 × allocation) | 188.7 ms | 49 % |
| YTD TTWROR (memoized, ADR-0032) | 8.3 ms | 2 % |
| Data quality | 9.2 ms | 2 % |

The report's own structural reading: **valuation-shaped work is ~92 % of the
block**, because `Allocation.for_portfolio/3` embeds a fresh
`Valuation.for_portfolio/2`, and `Valuation.for_view/2` walks every portfolio
in turn. One mount therefore prices holdings **six times** — once view-wide
and once per portfolio — and the view-wide pass is itself essentially the same
five per-portfolio valuations the drift loop then repeats.

### What preparing this decision additionally found

Inside a single valuation, market data is fetched **per row**, not per read:

- `Portfolixir.Catalog.get_security/1` — one `Repo.get` per position.
- `Portfolixir.Catalog.Quotes.adjusted_latest/1` — per security: a latest-quote
  query, a split-events query and a `Repo.get(Security)`. A batched
  equivalent, `adjusted_latest_by_security_ids/1`, **already exists** and is
  simply not used by the valuation path.
- `Portfolixir.Fx.convert/4` → `rate/3` → one `Repo.one` per currency lookup,
  issued per position and per cash account, re-asking the same question for
  every row in the same currency.

So the cost is not one expensive computation; it is the same small queries
asked hundreds of times per mount, across six passes that do not know about
each other.

### Constraints

- [ADR-0004](0004-holdings-derived-from-transactions.html) — holdings,
  valuation and trades are derived on read and never stored.
- [ADR-0032](0032-derived-series-memoization.html) — the daily TTWROR walk is
  memoized in a volatile memo that "never becomes a source of truth"; its
  Consequences **deliberately deferred** caching valuation and allocation as a
  separate decision with its own risk.
- [ADR-0003](0003-decimal-for-money.html) / [ADR-0016](0016-rounding-policy.html)
  — Decimal throughout, rounding at display only.
- [ADR-0026](0026-epic-batch-workflow.html) — valuation code paths are
  risk-tier.

## Options

**A. Extend ADR-0032-style memoization to valuation and allocation.** Attacks
~92 % of the block by remembering each of the six passes.

**B. One pricing pass per read.** Load the market data a read needs once,
thread it through every valuation and allocation in that read, and use the
existing batch APIs instead of per-row lookups.

**C. Split the async block into per-section asyncs.** The cheap sections paint
~380 ms earlier; total work unchanged.

## Decision

**Option B**, on the merits rather than on delivery risk.

The six passes are not expensive work that deserves remembering — they are the
*same* work done repeatedly within one request. Caching them would memoize a
redundancy: the duplication would remain in the architecture, and each memo
entry would hold its own copy of it. Worse, it would buy an invalidation
surface spanning transactions, quotes, exchange rates, splits and bucket
membership, for **the wealth total** — the one number this project's own
design sessions named as the figure an audit tool must never contradict. The
Sprint 3 review found exactly this class of defect in the far more forgiving
ADR-0032 memo (an empty blast radius skipped a scope bump, so a rate write
could leave a stale series live). Option A multiplies that surface; Option B
has none of it: nothing is remembered, so nothing can go stale.

Option C is not a fix. It changes when the user sees a number, not how long
the instance works. It remains available afterwards as an independent
presentation change.

Option B also **makes Option A cheap and safe if it is ever still wanted**:
memoizing one well-defined pricing pass is a small, single-keyed surface,
whereas memoizing six differently-shaped valuations is the surface ADR-0032
rightly refused. The reverse order does not work — once the redundancy is
cached, it is never removed.

### Shape

A **pricing context** is plain preloaded data, built once per read and passed
down:

- securities by id;
- adjusted latest quotes by security id (via the existing
  `Quotes.adjusted_latest_by_security_ids/1`);
- latest own trade prices by security id (`Ledger.latest_trade_prices/0`);
- EUR-hub exchange rates by currency, loaded once for the currencies in play;
- where a read needs them for several consumers, positions per portfolio and
  cash balances.

It is threaded as an **option**, exactly like the existing `:prices` test
override: callers that pass nothing get a context built internally for that
call, which is today's behaviour. `Portfolixir.Portfolios.Allocation` already
forwards its options to the valuation, so a caller computing both a total and
its drift supplies one context for both.

### Hard requirements

1. **Decimal-identical output.** Every affected read returns exactly what it
   returns today, with and without a supplied context. This is the acceptance
   criterion and is pinned by tests, not by inspection.
2. **No stored state.** The context is data with the lifetime of one read: not
   a process, not ETS, never persisted, never shared between requests.
   ADR-0004 is untouched, and no invalidation rule is introduced.
3. **Purity preserved.** Loading stays at the edge; the reducers and the
   valuation arithmetic keep taking data as arguments (ADR-0011, ADR-0015).
4. **Honesty paths unchanged.** `valued` / `unvalued_reason` /
   `price_source` semantics (#406) and the ADR-0033 decomposition behave
   identically — a missing quote or rate must still be reported, never
   papered over by a preloaded map's absent key.
5. **Measured, not asserted.** The mount is re-measured after the change with
   the #619 methodology and the result recorded; a claim of improvement
   without a measurement is not an outcome.

## Consequences

- `Portfolixir.Portfolios.Valuation` gains an optional pricing context and
  uses batch loads internally when it builds its own; the per-row
  `get_security` / `adjusted_latest` / `Fx.rate` lookups leave the hot path.
- `Portfolixir.Fx` gains a bulk hub-rate loader so a read resolves rates from
  memory instead of one query per row.
- `Portfolixir.Portfolios.Allocation` forwards the context (its option
  pass-through already exists).
- The dashboard mount builds one context for its whole async block; the Wealth
  page does the same where it computes a total and its allocation together.
- ADR-0032's memo is untouched: the daily walk stays memoized, this decision
  changes only what a *fresh* computation costs. Caching valuation stays
  deferred — and becomes a materially smaller decision afterwards.
- Delivery is risk-tier (ADR-0026). The owner directed it to ship inside the
  Sprint 3 bundle PR #631 together with the other risk-tier work of this
  sprint — a recorded deviation from the dedicated-small-PR rule, not an
  oversight.

## References

- Issue [#619](https://github.com/peshay/portfolixir/issues/619) and its
  measurement report (`_bmad-output/implementation-artifacts/619-dashboard-mount-measurement-2026-07-31.md`)
- [ADR-0032](0032-derived-series-memoization.html) — the memo this decision
  deliberately does not extend;
  [ADR-0004](0004-holdings-derived-from-transactions.html) — derived on read;
  [ADR-0003](0003-decimal-for-money.html) / [ADR-0016](0016-rounding-policy.html)
  — Decimal and rounding; [ADR-0026](0026-epic-batch-workflow.html) —
  risk-tier delivery
- [ADR-0033](0033-per-position-pnl-fx-decomposition.html) — the per-position
  decomposition whose honesty paths this change must preserve unchanged
