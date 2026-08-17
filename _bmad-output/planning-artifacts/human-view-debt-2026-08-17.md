# The FR-37 / FR-38 human-view debt, decomposed — 2026-08-17

Source: the two-way coverage rule in `AGENTS.md` ("API And MCP Coverage"),
which let FR-37 and FR-38 ship agent-only in Sprint 6 on condition that the
human view lands in **the same or the next epic batch**. Sprint 7 is that next
batch, so the obligation falls due now, and its absence afterwards is a
close-out finding by the rule's own terms.

`epics.md`, the PRD and the 2026-08-15 triage all record the *obligation* and
none of them records *what the view is*. This document closes that gap by
reading the shipped code rather than by asking, and it reaches a different
conclusion than the obligation's phrasing suggests.

**The headline: this is not one undefined obligation. It is four, and three of
them are already discharged, in flight, or half-present.** Exactly one has
nothing at all — and that one has an obvious shape, dictated by the module that
implements its agent half.

Nothing here is a committed scope decision. Per ADR-0038 these become thin
issues only after owner confirmation.

---

## What actually shipped, part by part

FR-37 is three mechanisms, not one, and they landed in different modules with
different human situations. FR-38 is one.

### 1. Field selection — human view **already shipped**

`PortfolixirWeb.Api.V1.FieldSelection` resolves `fields=` against a
per-endpoint whitelist (a precomputed string→atom map; no atom is ever created
from input, which is stricter than the requirement's stated minimum).

Its human equivalent is the **securities table column picker** —
`visible_columns` / `SecurityFields.visible_default()` in `securities_live.ex`,
persisted client-side under `securities.columns`. That shipped in the *same
batch*, as **#565**.

**Verdict: discharged for the securities table.** The two-way rule is satisfied
for this mechanism and nobody noticed, because the FR map tracked #565 as UI
work and `fields=` as agent work without connecting them.

**Residual gap, smaller than the debt:** the other heavy lists — transactions,
holdings — have no column picker. That is a generalization of an existing
affordance, not undischarged debt.

### 2. Roll-up-only aggregates — human view **in flight as #712**

`allocation_controller.ex:87` implements the roll-up as
`include_positions=false`: a read that returns category totals and omits the
position rows.

Its human equivalent is precisely the shape **ADR-0041** specifies and **#712**
carries: *a money-weighted roll-up on the category row, expandable to its
member positions.* Collapsed is `include_positions=false`; expanded is the full
read.

**Verdict: discharged if #712 ships in Sprint 7.** This is an argument for
scheduling #712 in this batch rather than a later one — it is not only a
feature the owner asked for, it is the settlement of a coverage obligation. The
two were filed independently and nobody connected them.

### 3. Threshold filters — human view **partially present**

Two threshold surfaces shipped: `min_drift` on the allocation endpoint
(`allocation_controller.ex:96`, a non-negative `Decimal` string) and
`stock_thresholds` / `etf_thresholds` on the risk endpoint.

On the human side, `securities_live.ex` has a filter builder (`@filter_ops`)
and a fixed data-quality set (`@dq_filters` — `stale_quote`, `missing_quote`,
`missing_logo`). So *a* threshold/predicate vocabulary exists for the
securities list, and **none** exists for the allocation drift or the risk
thresholds: an operator cannot ask "show only categories drifting more than
X %", which is exactly the question the agent half was built to answer.

Worth noting: **#705 runs the same gap in the opposite direction** — it wants
the human filter builder's data-quality predicates expressible over API and
MCP. Same asymmetry, mirrored. Under the two-way rule these are one concern
seen from two sides, and specifying them together is cheaper than twice.

**Verdict: partially discharged.** The missing piece is a drift-threshold
control on the allocation surface.

### 4. `?since=` delta reads — **nothing, and this is the real debt**

`PortfolixirWeb.Api.V1.SinceParam` implements FR-38: rows created or updated
strictly after a UTC cut, by `updated_at`, with the response's `as_of` intended
as the caller's next `since`. Deletions are deliberately not represented — a
caller needing them performs a full read.

**There is no human counterpart anywhere in the application.** No "what changed"
view, no since-cut, no changed-rows surface. This is the one part of the
obligation that is genuinely undefined and genuinely unbuilt.

**The shape is dictated by the mechanism, so it does not need inventing:**

- a cut the operator chooses (a date, defaulting to something meaningful like
  the last visit or the last import);
- the rows created or updated since it, across the surfaces the API already
  covers (securities, transactions, holdings, snapshots);
- **the deletion gap stated on the surface itself.** This is not a nicety: the
  identity gate's computation-basis rule requires a metric to state its window
  and its treatment of gaps in its payload, and a human view that silently
  omits deletions while the API documents them would be *less* honest than the
  agent half. The gap is the interesting part of the contract.

**Verdict: undischarged. One issue, and it is the only one this obligation
strictly requires.**

---

## Summary

| FR-37/38 mechanism | Human view | Status |
|---|---|---|
| field selection (`fields=`) | securities column picker (#565) | **shipped**, same batch |
| roll-up-only (`include_positions=false`) | category roll-up expandable to positions | **in flight — #712** |
| threshold filters (`min_drift`, risk thresholds) | filter builder exists; no drift threshold | **partial** — pairs with #705 |
| delta reads (`?since=`) | — | **missing** |

## Proposed for owner confirmation

1. **File one issue** — the changed-since view, with the deletion gap stated on
   the surface. This is what the two-way rule actually obliges.
2. **Schedule #712 in Sprint 7** on the strength of it also discharging the
   roll-up half.
3. **Fold the drift-threshold control into #705's specification**, since #705
   is already the same asymmetry from the other side.
4. **Record #565 in the FR Coverage Map as FR-37's field-selection human view**,
   so the map stops implying a debt that was paid in the same batch.
5. **Leave the column-picker generalization** (transactions, holdings) as an
   ordinary backlog item — it is a feature, not a coverage obligation.

## The finding worth carrying

The two-way coverage rule was recorded as a single undifferentiated debt
("the human view is due next batch") against a requirement that is three
mechanisms wide. Under that phrasing the obligation looked large and undefined,
and it was neither: most of it was already paid, and one part of it had been
paid *in the same batch by a differently-numbered issue*. A coverage rule
stated per requirement, when the requirement is a family, will keep producing
this — the rule should attach to the mechanism, which is the unit that has a
surface.
