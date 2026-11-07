---
layout: docs
title: "ADR-0046: benchmark comparison — a benchmark is a price series the portfolio's own flows are replayed into"
description: 'Design decision for issue #572 (FR-9), written for the Sprint 11 decision gate. Two benchmark kinds behind one interface (a fixed annual rate, and a catalog security flagged as a benchmark whose quotes come through the existing sync), two comparisons that are both Portfolio Performance''s ("bought once" as a rebased overlay next to TTWROR, and "savings plan" as the portfolio''s own external flows invested into the benchmark, giving an end-value delta and two IRRs on identical flows). Portfolio-wide and per view, API and MCP first. Inflation is a fixed rate in v1; the after-tax dimension (OQ-9) and a dated CPI table are deferred and named.'
---

# ADR-0046: benchmark comparison — a benchmark is a price series the portfolio's own flows are replayed into

- **Status:** Accepted — owner sign-off is the merge of PR #780, the Sprint
  11 planning PR ([ADR-0026](0026-epic-batch-workflow.html) step 1 as
  amended on that PR: the merge is the signature).
- **Date:** 2026-09-07
- **Amended:** 2026-11-04, the comparison reports the fees and taxes the
  real portfolio paid in its window (idea I17; see "Amendment (2026-11-04)"
  below). Adopted by the merge of the Sprint 24 planning PR.
- **Amended:** 2026-11-07, `benchmark=security:<id>` accepts any security
  with stored quotes, so a held security can be the benchmark without the
  flag (see "Amendment (2026-11-07)" below). The owner's answer to OQ-3 of
  the triage of 2026-11-07
  (`_bmad-output/planning-artifacts/feedback-triage-2026-11-07.md`);
  signed by the merge of the PR that carries it.
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

## Amendment (2026-11-04): the costs the real portfolio paid, beside the gap

**Status:** adopted by the merge of the Sprint 24 planning PR. Scope ladder
level (b), a decomposition that reports what was booked. It answers idea
I17. Risk tier as the decision itself (money math on the performance
surface, ADR-0036).

**Why.** §2 makes the savings-plan benchmark frictionless and says the bias
runs against the real portfolio. The reader is told the bias exists, never
how large it was: the fees and taxes the portfolio paid in the same window
are booked, and nothing puts them next to the gap. The deferral in §6
(after-cost and after-tax *benchmark*) stays: nothing here models a cost
for the benchmark.

**What changes.**

1. **The figure.** Each comparison payload carries `costs_paid`: the fees
   and the taxes booked in **the comparison's own window and scope** (the
   portfolio, the view, or the total), each as a Decimal string in the base
   currency, with their own `computation_basis`. It is the same for every
   benchmark of one request, so the screen shows it once.
2. **The series rule is the cost facet's** (`Portfolios.Costs`, #726): the
   fee and tax legs riding any transaction plus the standalone `fee` and
   `tax` bookings, `tax_refund` netted against taxes, each read in its cash
   account's currency and converted through the EUR hub at its booking
   date's stored rate; a cost with no stored rate is excluded from the
   totals and named. Taxes are the recorded ones only (ADR-0031): nothing
   is derived. The facet itself stays overview-level, as #726 requires:
   this is a per-scope sum computed beside the comparison, not a per-scope
   cost table.
3. **The scope rule follows the money.** The facet reads every cost in its
   cash account's currency, because that account pays it; so a cost counts
   where that cash account counts: in a portfolio when the account belongs
   to it, in a view when the account is in the view's buckets. A fee on a
   buy whose depot is in a view and whose cash account is not is therefore
   outside the view, as the cash it moved is; the basis says so. The window
   is the comparison's, its bounds read as the comparison reads them.
4. **What it is not.** It is not subtracted from the gap, and the payload
   names no residual: a fee paid early would have compounded until the
   window's end, which the booked figure leaves out; flows the comparison
   excludes and taxes settled at the year's end move the gap too. The
   `computation_basis` says so in one sentence, and so does the screen's ⓘ.
   Board `ux-design-2026-11-04-sprint24/02`, variant A.

**The identities the building batch pins.** A window with no fee and no
tax reads `0.00` for both; a portfolio whose only cost in the window is a
5.00 EUR fee on a buy reads fees `5.00` and taxes `0.00`, and the same buy
dated one day before the window reads `0.00`; a `tax_refund` of 2.00 in the
window against a 10.00 tax reads taxes `8.00`; a USD fee with no stored
rate on its day is excluded and named, and the totals leave it out.

**Asks (ADR-0043).**

| Ask | Answer |
|---|---|
| Subtract the costs and name the rest ("selection and timing")? | **No**, point 4: the arithmetic does not make that decomposition. |
| After-cost benchmark (§6's deferral)? | **Still deferred.** This reports the portfolio's costs; the benchmark stays frictionless. |
| Per-instrument costs in the comparison? | **No.** #726's overview-only rule for cost tables stands. |

*To flip by comment:* "I17 B": the payload and the screen then also carry
the residual, labelled as what is left after the booked costs, never as
selection and timing.

## Amendment (2026-11-07): any security with quotes can be the benchmark

**Status:** the owner answered OQ-3 of the
triage of 2026-11-07
(`_bmad-output/planning-artifacts/feedback-triage-2026-11-07.md`)
with its recommendation on 2026-11-07; signed by the merge of the PR that
carries this text. Not risk tier: no figure's arithmetic changes, only which
series may enter it.

**Why.** §1 says a benchmark security "may also be held … then it is simply
both". The rest of §1 makes that impossible in practice. A flagged security
is never offered in booking forms, so a held fund that gets the flag can no
longer be bought or sold on the screen. It also leaves every data-quality
set (`Catalog.DataQuality.list_opts/1`), so its stale or implausible quotes
are no longer named. An operator who wants the fund they hold as their
benchmark has two choices today: a fixed rate, or a second security with
the same quote series.

**What changes.**

1. **`benchmark=security:<id>` accepts any security with at least one
   stored quote**, flagged or not, on every read that takes it: the
   portfolio and view comparisons (§4), sale hindsight (FR-50) and
   predictions (ADR-0055). A security with no stored quote is refused with
   422 as before, and so is a merged-away one, named by `merged_into`
   (#959). A prediction's protection of its benchmark security from merge
   and delete applies to the security it names, flagged or not.
2. **`is_benchmark` keeps its meaning and nothing else changes with it.** It
   marks a reference-only instrument: never offered in booking forms, out
   of the data-quality sets, listed by `is_benchmark=true`, and the
   default content of the screen's benchmark picker. A held security used
   as a benchmark stays bookable and stays in every check, because it is
   not flagged.
3. **The picker** offers the flagged securities first and the held ones
   after them. That is a UI change, so it gets a board before it is built.
   The API and MCP half does not wait for it.
4. **The basis says which kind it read.** Each comparison's
   `computation_basis` names the benchmark security and whether it is
   flagged or a held or unheld catalog security. The arithmetic is §2's,
   unchanged.

*To flip by comment:* "OQ-3 B" keeps the flag as the gate and makes the
booking form and the data-quality sets exclude only *unheld* flagged
securities instead.

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
