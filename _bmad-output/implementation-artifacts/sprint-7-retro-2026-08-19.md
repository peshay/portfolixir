# Sprint 7 Retrospective — the UI closer, first batch under one structure (2026-08-19)

**Status: written at close-out.** PR #716 was rebase-merged 2026-08-19
(~05:54 UTC), 37 commits linear on `main`, head `80d3e7e`. The annotated
`0.7.0` tag is **prepared as an owner action** — the session's git proxy
allows pushes to the designated branch only, the same block Sprint 6 hit
with `0.5.0`. Command below under "Close-out ledger".

## What shipped

One batch on one branch, one PR (#716), per the adopted plan
(sprint-plan-2026-08-17-sprint7.md, Revision 3). Sixteen issues closed by the
merge's keywords: #706 #702 #700 #701 #703 #704 #707 #414 #672 #705 #710
#711 #712 #709 #708 #722.

- **Lane Z:** #706 walkthrough conditions as section G of the review
  checklist, meta-test-pinned; the ADR-0042 migration executed (tracker index
  in `epics.md`, story rows out of `sprint-status.yaml` with `epic-N` keys
  kept, #321's working agreement preserved into `AGENTS.md`, docs repointed,
  ADR-0043 applied retroactively to ADR-0039).
- **The UI closer:** the five-defect set (#702 tab row, #700 stored vs.
  effective asset class, #701 gettext headers, #703 trade-priced positions,
  #704 ADR id in copy — two now pinned by meta-tests), #707's design
  engagement spec, #414 transaction history (chips, month groups with
  per-currency subtotals, running-balance column), #672 the `/cashflow`
  parent with the stacked income chart. #471 was closed by hand as
  invalidated — ADR-0024 forbids what it asked for, and the defect it named
  no longer exists.
- **Agent and operator surface:** #705 data-quality predicates over one
  module (`Catalog.DataQuality`) feeding the filter popover, the API and MCP;
  the drift-threshold chips on the allocation table (the `min_drift=` human
  view), sharing one predicate with the JSON serializer.
- **Durable derived values (risk-tier):** #710 refresh-on-write coalesced
  behind a 500 ms quiet window with a 10 s ceiling — the import invariant
  (one refresh per basis, never per booking) mutation-verified; #711
  measured activation via `mix portfolixir.derived.measure`, figures in
  ADR-0039.
- **Signed decisions:** #708 transaction costs in the snapshot comparison
  (two chains over one walk, recovery states), #709 explicit unallocated
  remainder with drift against the allocated portion, #712 per-category
  money-weighted result.
- **Lane M:** five GitHub Actions majors applied (verified against how each
  is used, not against "CI is green"), zod 4 and TypeScript 7 (both proved
  trivial and were applied), a third cowlib CVE recorded. The
  deliberately-not-updated list, including the toolchain and BMAD rows the
  plan singled out, is `version-report-2026-08-19.md` — written late (see
  below).

Gates at merge: 1969 tests / 0 failures, coverage 90.5 % (project 90.79 % on
Codecov, +0.28 vs. base), Dialyzer zero, Credo strict clean, sobelow clean,
MCP 69 tests + build, pre-commit green.

## Agentic review closing act — what it caught

Two passes. The first (multi-role, plus the UAT walkthrough under #706's own
conditions) produced three confirmed findings; a second full-diff pass after
promotion produced a fourth. All fixed on the branch before the merge:

1. **API/MCP parity gap on the running balance** — the n/a claim was wrong
   (`cash_balances/1` returns only the current balance). Fixed as
   `?running_balance_for=` + MCP parameter over the same fold as the UI.
2. **#705 shipped short of its own scope** — the drift-threshold control the
   issue's plan named was never built. Fixed as chips sharing
   `Allocation.drift_at_least?/2` with the serializer.
3. **The filter chips never filtered.** LiveView's client overwrites
   `phx-value-value` with the element's own DOM value (empty string on a
   button), so the chips shipped dead with a fully green suite —
   `render_click/1` reads attributes off the markup and cannot see it. Found
   only by the browser walkthrough #706 mandates. Renamed to
   `phx-value-option`, pinned by `invariants/phx_value_value_test.exs`.
4. **The fourth recovery state crashed the page.** `recovery_label/1` had no
   `:not_comparable` clause, defended by a comment claiming the render guard
   made it dead code — verified against the guard's inputs but not against
   the state's producer. Reachable by a natural flow (all-cash snapshot,
   then a costly buy). Reproduced with a failing test, then fixed; the same
   pass found the comparison endpoint's API docs were pre-#708 and the MCP
   description enumerated three of four states.

## What worked

- **#706 paid for itself in its own batch.** The conditions it made binding
  (real browser, 390 px, DE, finding-triggering seed) caught finding 3 —
  a defect invisible to 1900+ green tests. The rule and its first catch
  shipped in the same PR.
- **Mutation-as-verification caught two false passes** before they could
  become false confidence: a docs meta-test whose probe silently did not
  apply, and a drift-filter test asserting on names that also appear in the
  donut legend.
- **One predicate, two surfaces** (drift threshold) and **one module, three
  surfaces** (data quality) made "the same rows" a structural fact instead
  of a claim.

## What to carry forward

- **A comment claiming unreachability is a claim to verify against the
  producer, not the guard.** Finding 4's comment was thorough, plausible and
  wrong; the state it dismissed arises precisely when its guard passes. The
  second-pass habit — re-derive reachability from the state's producer —
  is what caught it.
- **The done-list is a checklist, not a memory.** Lane M's
  review-and-report rows (PostgreSQL, BMAD, toolchain) were reviewed but
  never written down; nothing failed, and only re-reading the plan's own
  "what done means" list surfaced it. The report was written at close-out
  (`version-report-2026-08-19.md`) — one batch later than the lane intended.
- **Debt with a deadline, filed:** #731 (`?since=` human view) and #732
  (`fields=` column picker) are due by the end of the next batch under the
  two-way coverage rule; #729 (built-in tree names in DE) and #730 (the
  just-requested column is the last one in the scroller) are walkthrough
  findings outside this batch's scope.

## Close-out ledger

- Merge: PR #716 rebase-merged, `main` at `80d3e7e`, CI green on the merge
  commits (required checks included).
- Tag: **owner action** (session git proxy blocks tag pushes; verified by
  dry-run showing `[new tag]` and the remote tag list still ending at
  `0.6.0`). ADR-0026 step 5 asks for an ANNOTATED tag — `0.5.0`/`0.6.0` are
  lightweight, so `-a` below is the part not to drop:

  ```
  git fetch origin main
  git tag -a 0.7.0 80d3e7e1996ba535e8c5b79362a102c9676c7b29 \
    -m "Sprint 7: the UI closer, and the first batch under one planning structure"
  git push origin 0.7.0
  ```

  The tag push triggers the Release workflow (#659), which writes the
  GitHub release with generated notes.
- Issues: 16 closed by keywords (verified against the open-issue list, none
  remained open); #471 closed by hand 2026-08-18 (invalidated); #321 closed
  by hand at this close-out (superseded by ADR-0042 — the roadmap-index job
  it performed no longer exists; its working agreement was preserved into
  `AGENTS.md` by Lane Z).
- Epic tracker: Sprint 7 had no dedicated tracking issue (the batch drew on
  the standing trackers #356, #417, #419, #420, which stay open by design).
- `sprint-status.yaml` and `epics.md`: updated in the same pass (close-out
  entry, FR Coverage Map, dated reconciliation).
