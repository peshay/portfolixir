---
layout: docs
title: "ADR-0046: benchmark comparison — a benchmark is a price series the portfolio's own flows are replayed into"
description: Design decision for issue #572 (FR-9), written for the Sprint 11 decision gate. Two benchmark kinds behind one interface (a fixed annual rate, and a catalog security flagged as a benchmark whose quotes come through the existing sync), two comparisons that are both Portfolio Performance's ("bought once" as a rebased overlay next to TTWROR, and "savings plan" as the portfolio's own external flows invested into the benchmark, giving an end-value delta and two IRRs on identical flows). Portfolio-wide and per view, API and MCP first. Inflation is a fixed rate in v1; the after-tax dimension (OQ-9) and a dated CPI table are deferred and named.
---

# ADR-0046: benchmark comparison — a benchmark is a price series the portfolio's own flows are replayed into

- **Status:** Accepted — owner sign-off is the merge of PR #780, the Sprint
  11 planning PR ([ADR-0026](0026-epic-batch-workflow.html) step 1 as
  amended on that PR: the merge is the signature).
- **Date:** 2026-09-07
- **Answers:** FR-9 (PRD 2026-06-12, released from the advanced-reports gate
  on 2026-08-12 as scope-ladder level (b)), OQ-3 (the quote source), and the
  three design questions on
  [#572](https://github.com/peshay/portfolixir/issues/572). The asks it
  defers are listed in §6, per [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html).

## Context

The product's founding question, in the owner's words, is *"war der Aufwand
das wert?"* — was the effort worth it. The two figures the performance surface
already carries do not answer it. TTWROR
([ADR-0010](0010-ttwror-performance-series.html)) answers "how did the
investments do, as if the money had always been there"; the money-weighted
set ([ADR-0034](0034-money-weighted-metrics.html)) answers "what did my money
earn". Neither says **compared to what** — to having put the same money, on
the same days, into a broad index, or to having left it on a savings account.
Portfolio Performance shows both comparisons and its users expect them.

The prerequisites named on #572 are shipped: #545 (trade-price re-pricing no
longer inflates long-period TTWROR, closed 2026-07-25) and #568 (the flow
classifier of ADR-0034 §1, **parameterized by scope so that the benchmark
comparison can reuse it** — the ADR says so in as many words). The shared
chart component renders two series with a two-series tooltip and a
percent-rebased mode; the quote sync already fetches any security's history
without a new provider. What was missing was a decision on three questions,
and FR-9 carries two more from the PRD. This record answers them.

## Decision

### 1. Two benchmark kinds behind one interface

A benchmark is anything that yields a daily price in the base currency for
every day of the walk.

- **Fixed-rate baseline** — a constant annual rate compounding daily from a
  base of 1 (the savings-account alternative; "fixed-rate first" is the
  PRD's own ordering under OQ-3). In v1 this is also how **inflation** is
  expressed: an operator types the rate. No table, no provider, no
  persistence beyond the request.
- **Series benchmark** — a security in the catalog carrying a new boolean
  `is_benchmark` (additive migration), whose quotes arrive through the
  existing quote sync. An index is proxied by an ETF, gold by an ETC; that
  is the quote-source decision of OQ-3: **no new source**. A benchmark
  security is never offered in booking forms and is excluded from the
  data-quality checks that nag about unheld securities; it may also be held
  (the ETF an operator owns can be their benchmark) — then it is simply both.

### 2. Two comparisons, both Portfolio Performance's

- **Bought once** — the benchmark rebased to the period start, drawn next to
  the portfolio's cumulative TTWROR on the same chart. Flow-neutral, so it is
  the honest companion of TTWROR: it answers "did my selection beat the
  index".
- **Savings plan** (flow-matched) — every external flow of the portfolio,
  as ADR-0034 §1 classifies it at the same scope, is invested into the
  benchmark at that day's price (a fixed rate: at par). The synthetic series
  has an end value; the comparison figure is the **real end value minus the
  synthetic end value** in the base currency, beside the two IRRs computed
  by ADR-0034's XIRR on identical flows. This is the number that answers the
  founding question.

Rules the savings plan inherits rather than invents: a flow on a day without
a benchmark close uses the most recent close on or before that day, exactly
as the daily walk prices positions; a flow dated before the benchmark's
first quote is **excluded and named**, and the comparison states the window
it covers (the Sprint 8 D-1 shape, applied uniformly). The synthetic
portfolio is frictionless — no fees, no taxes — and the explanation line
says so; the bias runs against the real portfolio, which is the conservative
direction.

### 3. Scope and period

Portfolio-wide and per view — the classifier is scope-parameterized, and a
strategy view's "was it worth it" is a different question from the
household's. The period is the existing period picker; both comparisons use
the same window as the figures they sit next to.

### 4. Surfaces, agent first

- **API:** the comparison is a read under `/api/v1` on the two performance
  scopes (`/portfolios/:id/performance/benchmark`,
  `/views/:id/performance/benchmark`) taking `benchmark=` (`security:<id>`
  or `rate:<decimal>`) and `period=`, returning both comparisons with every
  financial value as a string and a `computation_basis` naming the window,
  the exclusions and the frictionless assumption. Benchmark securities are
  listed through the existing securities read with an `is_benchmark` filter.
  The contract manifest (#752) gains the entry in the same commit.
- **MCP:** the twin tools, schemas with the decimals as strings, per
  ADR-0002.
- **UI:** an overlay of at most two benchmarks on the Wealth performance
  chart, and a comparison block next to TTWROR/IRR carrying the one-line
  "what this answers" explanation `EXPERIENCE.md` requires of every figure.
  The selection is explicit per request in v1 (a query parameter the page
  remembers in the session); a stored per-view default is deferred until the
  choice proves stable enough to deserve a column.

### 5. What the engine does not do

Nothing is persisted: the synthetic series is derived on read and memoized
under the one mechanism ADR-0039 provides, with the same lifetime as the
walk it depends on. There is no benchmark blend, no per-security benchmark,
and no attempt to model what a real savings plan would have cost.

### 6. The asks, answered and deferred (ADR-0043)

| Ask | Source | Outcome |
|---|---|---|
| Fixed-rate baseline | FR-9, OQ-3 "fixed-rate first" | **Answered** — §1 |
| Index / security series | FR-9, OQ-3 "index second" | **Answered** — §1, proxied through the existing sync; no new quote source |
| Scenarios "bought once" and "savings plan" | FR-9 | **Answered** — §2, both |
| Benchmark data source | #572 Q1 | **Answered** — §1 |
| Comparison semantics | #572 Q2 | **Answered** — §2 |
| Presentation | #572 Q3 | **Answered** — §4 |
| Inflation / CPI as a dated series | #572 Q1 | **Deferred** — v1 expresses inflation as a fixed rate; a yearly rate table is a small follow-up once a constant proves too coarse |
| After-cost / after-tax dimension | FR-9, OQ-9 | **Deferred** — the tax pot is recorded, never derived (ADR-0031); an after-tax benchmark needs Vorabpauschale and Teilfreistellung modelling, which is its own gate |
| Stored per-view default benchmark | this record | **Deferred** — §4 |

## Consequences

- **Risk-tier attention label** ([ADR-0036](0036-risk-tier-rides-the-batch.html)):
  money math on the performance surface. Its own commit group, exact-Decimal
  fixtures, and three pinned identities: a 0 % fixed-rate savings plan ends
  at exactly the net invested capital of ADR-0034; a benchmark that *is* the
  portfolio's single holding with the same flows yields a zero end-value
  delta and equal IRRs; a flow before the first quote is excluded and named.
- The FR Coverage Map's FR-9 row moves from "future" to the issue numbers
  the Sprint 11 plan files; E10 in the Tracker Index gains its first shipped
  item.
- The comparison is a read model over data the ledger already has. It
  introduces no write path, no order, no transmission of anything — the
  scope ladder's level (b) and nothing beyond it.
