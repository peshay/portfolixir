---
layout: docs
title: "ADR-0041: category result — the positions in a category, rolled up and decomposable"
description: A category shows what the positions currently filed under it have collectively made, expandable to the rows that produced it. Because the figure describes the portfolio as it stands rather than a period, it needs no membership history and carries no restatement caveat. Money-weighted, never an average of percentages; rows whose result cannot be derived are excluded and named rather than silently counted as zero. A time-weighted per-category series is not part of this decision and not rejected: what it would refuse is booking classification changes into the ledger, while a separate membership timeline stays open - and its raw material already accrues in the audit journal, so deferring it loses nothing.
---

# ADR-0041: category result — the positions in a category, rolled up and decomposable

- **Status:** Proposed (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html); owner sign-off outstanding)
- **Date:** 2026-08-15 (rewritten the same day — see "How this decision was
  wrong first")

## Context

Classification trees describe the portfolio: a category has a share, a target
weight ([ADR-0020](0020-view-bound-soll-plans.html)) and a drift
([ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html)). What they
do not carry is any statement of result — how the positions filed under a
category have actually done. The owner's request (feedback triage 2026-08-15,
Round 2/A3 and the follow-up of the same evening) is exact and modest: *put the
gain or loss percentage on the category row too, and let me expand it to see
which position inside contributed what.*

Portfolio Performance does not offer this, which is why it is worth doing; but
the reason it is cheap is that **every number it needs already exists**.
`portfolixir.holdings.list` returns, per position, the cost basis actually paid
in base currency, the market value, the unrealized result and the
[ADR-0033](0033-per-position-pnl-fx-decomposition.html) split into price and
currency return — plus `decomposed: false` with an `undecomposed_reason` where a
row's figure is honestly unavailable. `Ledger.TradeMatcher` supplies realized
results per closed round-trip. The classification tree already maps every
security to exactly one category per tree. Nothing here has to be computed for
the first time; it has to be **grouped**.

### The observation that dissolves the hard problem

A first draft of this ADR turned the request into a **per-category return series
over a period**, and immediately inherited a serious problem: a security's
category is not constant, so a series has to decide whether it follows today's
classification backwards or the classification as it stood each day. That
question is real — and it is entirely an artifact of asking for a series.

**A roll-up over the current composition makes no claim about a period.** It
says: *the positions filed here right now are collectively up X %.* That is true
by construction, however often the tree has been reorganised, because the
sentence is about what the portfolio is, not about what it did between two dates.
No membership history is needed, no restatement can occur, and no caveat has to
be shown — the owner's instinct that an extra hint would be noise is correct, and
under this framing the hint would not merely be noise but wrong.

The owner also identified, unprompted, why the series variant is unattractive
beyond its cost: measuring a category *over time* means treating category changes
as events, and then consistently also bucket and view changes
([ADR-0018](0018-buckets-tag-based-wealth-scoping.html),
[ADR-0024](0024-buckets-and-views-replace-portfolios-in-the-ui.html)), and
computing across all of them. That is organisational metadata leaking into the
ledger, which is the one place this architecture keeps clean — a better argument
than the effort estimate this ADR first offered. §6 draws the line it implies:
the refusal is about the *ledger*, not about ever knowing who was in a category
when.

## Decision

### 1. A category carries a result, defined as a roll-up of its members

Per category, over the positions currently filed under it in the selected tree
and view:

- **invested** — the sum of the members' base-currency cost basis;
- **current value** — the sum of their market values;
- **result** — absolute, in base currency, and as a percentage of invested.

The figure is a statement about the **current composition** and says so. That is
the whole of its computation basis; there is no period, no membership variant and
no as-of qualifier to choose.

### 2. Money-weighted, never an average of percentages

The category percentage is `Σ result ÷ Σ invested`, not the mean of the members'
percentages. The naive average lets a tiny position at +300 % dominate a category
that is flat in money, and it is the single most likely way to ship a plausible
wrong number here. Pinned by a test with exact `Decimal` expectations, not left
to review.

Parent categories roll up from their members the same way, so a level's result
reconstructs from the level below it.

### 3. Expandable to the rows that produced it — part of the feature, not a follow-up

The category row expands to its member positions, each showing its own
contribution to the category figure. A category number that cannot be resolved
into the rows behind it is the same defect this feedback round found in the
data-quality surfaces: an aggregate without an address. The expansion ships with
the aggregate or neither ships.

### 4. Rows that cannot be derived are excluded and named

A position whose result is not derivable — `decomposed: false` with its
`undecomposed_reason`, or no usable price — is **left out of the sums and listed**,
in the same shape the snapshot comparison uses for its gaps (AR-4). It is never
counted as zero, which would understate the category quietly. The category figure
states how many members it covers out of how many it has.

### 5. Realized results and income: same shape, own slice

Sells and distributions belong to the same question and the owner named them:
what a category has *made*, not only what it currently shows. They fit this
framing without reopening the membership problem, because "realized under the
category the security is filed under today" is again a statement about the
current composition — `TradeMatcher`'s closed round-trips and the income series
grouped by the same tree.

They are a **second slice, not a second decision**: the first slice is the
unrealized roll-up in the positions view, because that is what was asked for and
it is where the numbers already sit side by side. The second adds realized and
income, and when it lands the category row states which of the three components
it includes — an aggregate that silently changes meaning between screens would
undo §3's point.

### 6. A time-weighted per-category series is not part of this decision — and not rejected

Out of *this* ADR, with the route left open and named, because a first draft of
this section over-rejected it and the distinction it missed matters.

**What is genuinely refused:** treating classification changes as **ledger
events**. `Ledger.Projection.effects/1` owns a closed set of booking kinds and
raises on an unknown one by design
([ADR-0011](0011-unified-ledger-projection.html)); organisational
metadata booked there would be exactly the corruption that guard exists to
prevent, and the same then follows for bucket and view changes. That is the
owner's argument and it stands.

**What is not refused:** a **membership timeline** — a separate, small,
append-only record of which category held a security between which dates. It
touches no booking, so none of the above applies to it. Under
[ADR-0039](0039-durable-derived-values.html) a series built on it would be an
ordinary registered analytic with a `:durable` lifetime, recomputed only when its
basis version moves; reclassification already bumps that version, since
assignment writes pass through `Journal.record` and
`Derived.BlastRadius` widens an unlisted resource type to `:all`.

**Why later costs nothing.** `upsert_assignment/4` journals `:create`, `:update`
with the prior assignment as its before-image, and `:delete` — continuously since
`20260623130000_arm_assignments_journal.exs`. The raw material for the timeline
is therefore **already accruing without anyone deciding to build it**, which is
the unusual case: deferring a history feature normally means losing history, and
here it means only that the recorded span keeps growing for free. The right
moment to build it is when that span covers a period a reader would actually ask
about, which is elapsed time rather than engineering.

Should it be taken up, it is its own decision with its own gate; nothing here
prejudges its shape, and §1's roll-up keeps working unchanged beside it.

### 7. Payload and coverage

The API and MCP payloads carry the roll-up with financial values as Decimal
strings, the covered/total member counts, the excluded rows with their reasons,
and the one-line basis statement from §1. Materialization follows
[ADR-0039](0039-durable-derived-values.html) if measurement shows it is needed;
this is an aggregation over data a read already loads
([ADR-0035](0035-one-pricing-pass-per-read.html)), so the expectation is that it
is not.

## How this decision was wrong first

The first version of this ADR specified a per-category **return series**, spent
its length on the membership-over-time question, and proposed a restatement
marker to manage the consequences. The owner had asked for a column in a table.

Recording it because the failure is reusable: the request was generalised into
its most powerful form before it was satisfied in its plain one, and every
difficulty after that followed from the generalisation rather than from the
problem. The membership question was not solved here — it was **removed**, by
building what was asked for.

## Consequences

- Positive: the classification tree gains a result column and stops being purely
  descriptive; the numbers come from data already loaded, so the slice is small;
  and the hardest question in the first draft disappears rather than being
  managed.
- Negative / accepted: the figure cannot answer "how did this category do last
  year" — it is about the portfolio as it stands. Stated in the payload, and the
  reason it is not merely a missing feature is §6.
- Accepted: a position that moved category takes its whole result with it. Under
  a current-composition statement that is correct rather than a distortion, but
  it will surprise anyone who reads the number as a period return — which is why
  §1's basis line is not optional.
- Risk-tier attention ([ADR-0036](0036-risk-tier-rides-the-batch.html)): the
  money-weighting of §2 and the exclusion rule of §4 are where a plausible wrong
  number would come from. Both pinned by exact `Decimal` tests before
  implementation.
- Two-way coverage: this one is human-first — it was asked for as a table column
  — so the view leads and the API/MCP roll-up ships with it rather than after it.

## References

- [ADR-0033](0033-per-position-pnl-fx-decomposition.html) — the per-position
  figures this rolls up, including the `decomposed: false` contract §4 relies on
- [ADR-0020](0020-view-bound-soll-plans.html) — target weights per category, the
  other half of the pair a rebalancing decision needs
- [ADR-0035](0035-one-pricing-pass-per-read.html) · [ADR-0039](0039-durable-derived-values.html)
  — the version-counter mechanism §6's deferred series would use, already built:
  a `:durable` value is a `derived_values` row carrying `as_of` and
  `data_version`, and every write announces itself through
  `Derived.Invalidation` inside its own transaction
- [ADR-0011](0011-unified-ledger-projection.html) — the closed booking-kind set
  that makes "classification changes as ledger events" a refusal rather than a
  preference
- Owner feedback triage 2026-08-15, Round 2/A3 and Round 5
