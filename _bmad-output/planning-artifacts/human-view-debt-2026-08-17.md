# The FR-37 / FR-38 human-view debt, decomposed — 2026-08-17

Source: the two-way coverage rule in `AGENTS.md` ("API And MCP Coverage"),
which let FR-37 and FR-38 ship agent-only in Sprint 6 on condition that the
human view lands in **the same or the next epic batch**. Sprint 7 is that next
batch, so the obligation falls due now, and its absence afterwards is a
close-out finding by the rule's own terms.

`epics.md`, the PRD and the 2026-08-15 triage all record the *obligation* and
none of them records *what the view is*. This document closes that gap by
reading the shipped code.

> **CORRECTED 2026-08-17, after the agentic review.** The first version of this
> document concluded that most of the debt was already discharged, and it was
> **wrong in its central claim** — wrong in a direction that conveniently
> reduced Sprint 7's scope. The correction and what produced it are kept in
> "How this analysis was wrong first", because the error is more instructive
> than the result.

**The headline, corrected: two of the four mechanisms have no human view at
all, one is in flight, and one is partly present.**

Nothing here is a committed scope decision. Per ADR-0038 these become thin
issues only after owner confirmation.

---

## What actually shipped, part by part

FR-37 is three mechanisms, not one, and they landed in different modules with
different human situations. FR-38 is one.

### 1. Field selection — **no human view, on either endpoint that has it**

`PortfolixirWeb.Api.V1.FieldSelection` resolves `fields=` against a
per-endpoint whitelist (a precomputed string→atom map; no atom is ever created
from input, stricter than the requirement's stated minimum).

**It is aliased by exactly two controllers** — `transaction_controller.ex:6`
and `holding_controller.ex:6`. `security_controller.ex` does not reference it;
there is no `fields=` on the securities endpoint.

The application's only column picker is on the **securities** list
(`lib/portfolixir_web/live/securities/column_picker.ex`, `visible_columns` in
`securities_live.ex`, persisted under `securities.columns`). Transactions and
holdings have none.

**The agent half and the human half therefore do not overlap on a single
surface.** Field selection has an operator affordance on the one list with no
`fields=`, and no operator affordance on the two lists that implement it.

**Verdict: undischarged.** A picker on the transactions and holdings lists is
the actual obligation, and nothing in the backlog covers it.

### 2. Roll-up-only aggregates — human view **in flight as #712**

`allocation_controller.ex:87` implements the roll-up as
`include_positions=false`: a read that returns category totals and omits the
position rows.

Its human equivalent is precisely the shape **ADR-0041** specifies and **#712**
carries: *a money-weighted roll-up on the category row, expandable to its
member positions.* Collapsed is `include_positions=false`; expanded is the full
read. Same endpoint, same semantics, both halves.

**Verdict: discharged if #712 ships in Sprint 7.** Unlike §1, this is a real
correspondence and not a retroactive nomination: the surfaces match, and #712
was specified against the same ADR-0041 arithmetic the endpoint returns.

### 3. Threshold filters — **partially present**

Two threshold surfaces shipped: `min_drift` on the allocation endpoint
(`allocation_controller.ex:96`, a non-negative `Decimal` string) and
`stock_thresholds` / `etf_thresholds` on the risk endpoint.

On the human side, `securities_live.ex` has a filter builder (`@filter_ops`)
and a fixed data-quality set (`@dq_filters` — `stale_quote`, `missing_quote`,
`missing_logo`). So a predicate vocabulary exists for the securities list, and
**none** exists for allocation drift or the risk thresholds: an operator cannot
ask "show only categories drifting more than X %", which is the question the
agent half was built to answer.

**#705 runs the same gap in the opposite direction** — it wants the human filter
builder's data-quality predicates expressible over API and MCP. Under the
two-way rule these are one concern seen from two sides, and specifying them
together is cheaper than twice.

**Verdict: partially discharged.** The missing piece is a drift-threshold
control on the allocation surface.

### 4. `?since=` delta reads — **no human view**

`PortfolixirWeb.Api.V1.SinceParam` implements FR-38 on `security_controller`
and `transaction_controller`: rows created or updated strictly after a UTC cut,
by `updated_at`, with the response's `as_of` intended as the caller's next
`since`. Deletions are deliberately not represented — a caller needing them
performs a full read.

**There is no human counterpart anywhere in the application.** Verified against
`lib/portfolixir_web/**` and both gettext catalogues: every `since` hit is
TTWROR-comparison or tax-staleness copy, none a changed-rows surface.

**The shape is dictated by the mechanism, so it does not need inventing:**

- a cut the operator chooses (a date, defaulting to something meaningful);
- the rows created or updated since it, on the surfaces the API already covers;
- **the deletion gap stated on the surface itself.** The computation-basis rule
  requires a metric to state its window and its treatment of gaps, and a human
  view that silently omits deletions while the API documents them would be
  *less* honest than the agent half.

**Verdict: undischarged.**

---

## Summary

| FR-37/38 mechanism | Endpoints | Human view | Status |
|---|---|---|---|
| field selection (`fields=`) | transactions, holdings | picker exists on **securities only** | **missing** |
| roll-up (`include_positions=false`) | allocation | category roll-up, expandable | **in flight — #712** |
| threshold filters | allocation, risk | filter builder on securities; no drift threshold | **partial** |
| delta reads (`?since=`) | securities, transactions | — | **missing** |

## How this analysis was wrong first

The first version claimed field selection's human view had "already shipped, as
#565, in the same batch", and drew a methodological lesson from it: that a
coverage rule stated per requirement will mark debts paid without anyone
noticing. Both halves were wrong, and the second was wrong *because* it was
pleasing.

Two independent facts refute it. **The securities column picker predates FR-37
entirely** — `column_picker.ex` and the `securities.columns` storage key exist
at `73affc5`, the Sprint 5 head, before the Sprint 6 batch; `#565` is titled
"securities table **classification** columns are configurable" and added
classification columns to a picker that already existed. And **the securities
list has no `fields=`**, so the picker was never that mechanism's human half on
any reading.

The deeper error is the method, not the facts. Nobody ever *decided* that #565
discharged FR-37; the analysis nominated a pre-existing affordance in hindsight
and then proposed recording that nomination in the FR Coverage Map, where it
would have become the authoritative entry with the reasoning buried in a dated
planning artifact. A strict reader of the two-way rule would reject this
outright: the rule says the human view "**then lands** in the same or the next
epic batch" — a temporal obligation to build something — and `AGENTS.md` states
its own purpose, that without the deadline the rule "degrades into 'agent only,
forever', which hollows out the operator half". **A retroactive nominee can
always be found after the fact.** That is precisely the degradation, performed
by the document meant to enforce the rule.

It also had a motive. The conclusion reduced Sprint 7's scope, and it was
written by the agent that would otherwise have had to schedule the work.

**The finding worth carrying is therefore about the method:** an obligation is
discharged by a decision recorded before the fact, not by an inventory taken
afterwards. When an audit of one's own scope concludes that the scope is
smaller than believed, that conclusion needs an adversarial check before it is
acted on — which is what happened here, one round too late to have saved the
work.

## Proposed for owner confirmation

1. **File the changed-since view** (`?since=` human counterpart), with the
   deletion gap stated on the surface.
2. **File the field-selection picker** for the transactions and holdings lists
   — the two endpoints that actually implement `fields=`. This is the item the
   first version wrongly marked paid.
3. **Schedule #712 in Sprint 7**, on the strength of it also discharging the
   roll-up half. This one survives the correction unchanged.
4. **Fold the drift-threshold control into #705's specification**, since #705 is
   already the same asymmetry from the other side.
5. **WITHDRAWN** — the first version proposed recording #565 in the FR Coverage
   Map as FR-37's field-selection human view. It is not, on either count above.
   The FR-37 row must keep stating the debt, and it now understates it: the
   obligation is two surfaces wide.

**If items 1 and 2 do not both fit Sprint 7,** that is a legitimate outcome, but
it is a *deferral to be recorded as the close-out finding the two-way rule
prescribes* — not an obligation to be reasoned away.
