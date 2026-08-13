---
layout: docs
title: "ADR-0039: Durable derived values — one memoization mechanism with a lifetime per analytic, everything eligible, activation decided by measurement"
description: Decision for gate B3.2. Derived values may be materialized and kept, bound by four properties from FR-1 - rebuildable, versioned, never silent about freshness, never authoritative for a write. One uniform mechanism serves all three lifetimes (none, request, durable) rather than a hand-picked list of cached values; every registered analytic is eligible, and which ones run durable is decided by measurement rather than by opinion. Supersedes ADR-0032's volatile memo and inherits ADR-0035's de-duplication as the first line of defence.
---

# ADR-0039: Durable derived values — one memoization mechanism with a lifetime per analytic

- **Status:** Accepted (decision gate B3.2 per
  [ADR-0026](0026-epic-batch-workflow.html); owner sign-off 2026-08-12).
  Supersedes [ADR-0032](0032-derived-series-memoization.html), whose volatile
  memo becomes the `:request` lifetime of this ADR's single axis.
- **Date:** 2026-08-12

## Context

The rule that made Portfolixir trustworthy is that every financial figure is
reproducible from the transaction ledger
([ADR-0004](0004-holdings-derived-from-transactions.html)). It was implemented as
something stricter: *nothing derived may ever be kept*. The product brief of
2026-08-12 (accepted as #663) names that over-reach and its two symptoms, and the
PRD's FR-1 was reworded on the same day to permit materialization under explicit
conditions.

**The symptoms are measured, not felt.** Timing the existing daily performance
walk (`Portfolixir.Portfolios.Performance.analysis/2`) against synthetic ledgers
on a container comparable to a modest self-hosted box:

| Securities | Bookings | Quote rows | Walk days | 1st call | 2nd call |
|---|---|---|---|---|---|
| 50 | 1,001 | 26,100 | 3,650 | 2.78 s | 2.59 s |
| 200 | 4,001 | 104,400 | 3,650 | 11.44 s | 10.90 s |

Two facts follow, and they are the whole case for this ADR:

- **Cost grows about linearly with catalog size** — 4× the securities cost 4.1×
  the time. Extrapolated to the reference volume named in the architecture
  document (500 securities, 10 years), a single walk lands around half a minute.
- **The second call costs the same as the first.** Nothing survives the
  computation, so every dashboard mount, every reload and every agent question
  pays full price again. This is the "repeat wait" that
  [ADR-0032](0032-derived-series-memoization.html) addressed for the lifetime of a
  process and no longer.

*(Measurement caveat, stated so nobody quotes these as budgets: they come from a
synthetic ledger on CI-grade hardware, with weekly quote points rather than daily.
They establish an order of magnitude — seconds to tens of seconds — not a target.
The operator-facing number is produced by the command this ADR mandates in §6.)*

Three decisions already touch this area and must be reconciled rather than
ignored:

- [ADR-0004](0004-holdings-derived-from-transactions.html) — holdings are derived,
  never stored. This ADR does not weaken it: a materialized value is a
  *materialization of the single truth*, not a second copy that could disagree.
- [ADR-0032](0032-derived-series-memoization.html) — an ETS-backed memo of the
  daily walk, deliberately volatile, never surviving a restart.
- [ADR-0035](0035-one-pricing-pass-per-read.html) — chose to *remove* redundant
  computation (one pricing pass per read) rather than to cache it.

The gate's own framing required an argument against ADR-0035 rather than around
it, and required that "everything is materialized" not be accepted as an answer
by default.

## Decision

### 1. One mechanism, three lifetimes — not three mechanisms

A derived value is a **pure function value over a versioned, named basis**.
Everything else is a question of how long the result is kept. That yields a single
axis with a lifetime parameter, not three separate designs:

| Lifetime | Mechanism | Replaces |
|---|---|---|
| `:none` | recompute on every call | today's default |
| `:request` | in-memory memo, dies with the process | ADR-0032 |
| `:durable` | row in a derived-values table carrying `as_of` and `data_version` | new |

**ADR-0032 is superseded**, not amended: its volatile memo becomes the `:request`
case of this axis and stops existing as separate machinery.

### 2. Every registered analytic is eligible; a curated list is explicitly rejected

The four FR-1 properties (§4) are uniform — there is no argument that holds for
one derived value and not another. Hand-picking which values may be materialized
would encode today's guesses into the design and would rot, exactly as the
architecture document's own structure section did.

Therefore: **every analytic that registers a computation basis is eligible for any
lifetime.** The mechanism is uniform; the invariants are proven once against the
mechanism rather than once per value; and **which analytics actually run
`:durable` is a configuration decision informed by measurement, not an
architectural one.**

This is the argued form of the gate's "everything is not an answer" constraint.
The constraint is real but it is about *activation*, not *eligibility*:
materializing a value that computes in two milliseconds buys nothing and still
adds an invalidation path that can be wrong. The cost of materialization is
**invalidation correctness**, not storage — and invalidation is where systems of
this kind fail (§5, I2/I3).

**Initial activation:** the daily performance walk, on the evidence in the Context
section. Further activations are added when a measurement shows a wait, and each
one is a configuration change plus its measurement, never a new mechanism.

### 3. ADR-0035 is inherited, not opposed

Removing a redundant call is strictly better than caching it: a removed call costs
nothing, a cache costs invalidation. **ADR-0035 stays the first line of defence,
and materialization is admissible only for what remains after de-duplication.**
A story that proposes materializing a value which is simply computed more often
than necessary is rejected in favour of computing it once.

### 4. The four binding properties (FR-1, restated as this ADR's acceptance criteria)

Every materialized value must be:

1. **rebuildable** from transactions alone, with drop-and-rebuild a supported and
   tested operation;
2. **versioned** against the data-version counter, so staleness is detectable
   rather than suspected;
3. **never silent about freshness** — `as_of` plus an explicit stale marker, in
   the UI *and* in the API/MCP payload;
4. **never authoritative for a write** — no booking, import decision or
   consistency finding may read the derived layer instead of the ledger.

### 5. Invariants — the acceptance criteria in testable form

The defining property is an equation, so it is tested as invariants rather than as
examples. All are blocking.

| # | Invariant |
|---|---|
| I1 | **Rebuild equivalence** — `derived == rebuild_from_scratch(transactions)` for any ledger state. Property-based, exact `Decimal` equality, no tolerance |
| I2 | **Incremental ≡ full** — `apply_incremental(D, tx) == rebuild(transactions ++ [tx])`. Where such layers die in practice: divergence after a correcting booking, a backdated transaction, a deletion |
| I3 | **Backdating** — a transaction dated before the last materialized point invalidates everything downstream. Its own property, because a generator otherwise rolls backdated inserts too rarely |
| I4 | **Freshness is structural, not a display** — the read returns `{:fresh, v}` or `{:stale, v, as_of}`; no return path may claim freshness without checking the version counter, and a meta-test asserts that no API or MCP serialization drops the field. The agent cannot look at a warning triangle |
| I5 | **Version-counter monotonicity and non-bypassability** — every ledger write bumps it. Same gate construction as `write_actor_test.exs` |
| I6 | **Drop-and-rebuild is a tested operation** — the test actually drops and rebuilds, against a fixture carrying **historical** exchange rates, so it proves reproduction of historical numbers rather than of today's |
| I7 | **Never a write source** — no write path reads from the derived layer. Statically checkable, same construction as `web_repo_boundary_test.exs` |

Two further conditions that are not invariants but block sign-off of the
implementing story:

- **Computation version in the key.** The data-version counter covers data
  changes, not code changes. If a formula changes and the counter does not, the
  layer is silently wrong. The key is therefore
  `(analytic_id, basis_hash, data_version, computation_version)`.
- **Journal actor of a materialization write.** A derived-value write is not a
  financial write and is **not journaled**; `write_actor_test.exs` must know that
  table class **explicitly**, because implicit non-coverage is how the strongest
  existing gate would be bypassed rather than weakened.

### 6. The rebuild budget is a measurement, not a guessed number

Drop-and-rebuild is the emergency procedure, and an emergency procedure with an
unknown runtime is not one. But a budget invented before anything exists is how
[ADR-0032](0032-derived-series-memoization.html) and
[ADR-0035](0035-one-pricing-pass-per-read.html) came to be decided on a felt
symptom.

Therefore:

- drop-and-rebuild is a **single operator command**, not a procedure;
- its runtime is **measured on operator hardware on first run and recorded in this
  ADR** as an amendment;
- the acceptance criterion until then is the shape, not the number: the rebuild
  completes unattended in one command, and reports its own runtime.

If the recorded number later proves intolerable, that is a finding with evidence
behind it rather than a prediction.

## Consequences

**Easier.** The repeat wait disappears for whatever is activated: the walk that
costs seconds today is paid once per invalidation rather than per mount. The agent
reads finished figures instead of reconstructing them, which is what the
agent-side criteria (≤ 5 calls for the weekly run, −70 % response volume) attach
to. FR-39 through FR-42 — derived metrics per security and per view, contribution
analysis, exposure decomposition — gain a place for their values to live, which is
the dependency the requirement registry records against them.

**Harder.** Every activated value needs a correct invalidation path, and the
backdated-transaction case (I3) is the one that naive implementations get wrong.
The test suite grows a property-based layer that is slower than example tests and
harder to debug when it fails. Freshness becomes part of every payload the layer
touches, so the API and MCP surfaces change additively and the contract fixtures
(architecture D5) become more valuable than they already are.

**Off-limits.** The derived layer may never be read by a write path (I7), never be
the answer to a consistency question, and never outlive a formula change silently
(computation version in the key). A curated list of "cacheable values" is off the
table by construction — if a value cannot satisfy the four properties, the answer
is that it is not a derived value at all. The historical-exchange-rate case is
precisely that: a rate observed on a past day is an **observation**, not a derived
value, and conserving it is an input-capture concern upstream of this ADR, not a
reason to weaken "rebuildable". This ADR does not decide that capture; it depends
on it for I6's fixture.

**Accepted trade-off.** Uniform eligibility means the mechanism must be right for
values nobody has thought about yet, which is a higher bar than making one cache
work for one series. That is deliberate: the alternative is a list that ages, and
this repository has just spent a validation pass documenting what an aging list
costs.
