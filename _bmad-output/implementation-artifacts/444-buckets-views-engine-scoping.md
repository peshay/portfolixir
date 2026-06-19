# Story: Buckets & views — engine scoping (GitHub #444)

Status: in-progress

> **Tracking:** GitHub issue [#444](https://github.com/peshay/portfolixir/issues/444),
> story 2 of epic [#448](https://github.com/peshay/portfolixir/issues/448). Builds on
> #443 (data model + `Portfolixir.Engines.BucketResolution`, merged in #453).
> Next: API/MCP (#445), UI (#446), retire the exclude flag (#447).

## Story

As a local portfolio maintainer,
I want valuation, allocation, performance and risk to optionally run against a chosen **view**,
so that I can analyse a slice of my wealth (e.g. "everything except the long-term Bitcoin reserve") while the default stays my whole, single-count wealth.

## Acceptance Criteria (verbatim from #444)

1. `Valuation`, `Allocation`, `Performance`, `Risk` accept a view scope and restrict to the holdings matching it (using story-1 helpers).
2. Totals computed **once per holding** (single-count); a holding in multiple buckets is never double-counted.
3. **No view passed → byte-for-byte identical results to today**, pinned by tests (mirrors ADR-0013's "total identical whether flagged or not").
4. Engines stay **pure** (no Repo/clock/config); the scope is injected data, not a query inside the engine (architecture D2 / AR-2).
5. Cash respects its bucket (a view excluding "Leo" excludes Leo's cash too).
6. Deterministic **Decimal-exact** tests per engine: total, per-view, multi-tag overlap, cash-in-view.

### Out of scope
API/MCP exposure (#445); UI switcher (#446); rebalancing (gated FR-12).

## Design — the shared scope seam

Positions are keyed `{securities_account_id, security_id}` (`Ledger.positions_for_portfolio/1`)
and cash by `cash_account_id` — exactly the keys `Portfolixir.Buckets` resolves. So:

- **Pure engine addition:** `Portfolixir.Engines.BucketResolution.in_view?(view, effective_buckets)`
  — the boolean behind `holdings_matching_view/2` (include — `:all` or intersect — AND
  not excluded; exclude wins). `holdings_matching_view/2` is refactored to call it.
- **Context seam (shell, loads data once):** `Portfolixir.Buckets.load_scope(portfolio_id, view_id)`
  returns an opaque scope that pre-loads, in bulk, the view filter + depot defaults +
  position overrides + cash-account assignments for that portfolio. `view_id == nil` →
  `:unscoped`.
  - `Buckets.position_in_scope?(scope, sa_id, sec_id)` → bool (`true` for `:unscoped`).
  - `Buckets.cash_in_scope?(scope, cash_account_id)` → bool (`true` for `:unscoped`).
  The membership boolean is delegated to the **pure** engine; the loading is the shell's job
  (satisfies AC 4: scope is injected data, not a query inside the compute core).
- **Each read model** gains an optional `:view` opt (a `view_id`). Default `nil` →
  `:unscoped` → **no filtering** → identical output (AC 3). When set, the holding/position
  list and the cash-account list are filtered through the scope before any total is computed,
  so totals stay single-count (AC 2).

### Per-engine wiring
- **Valuation** (`for_portfolio/2`): filter `positions` by `position_in_scope?` and
  `cash_for` accounts by `cash_in_scope?` before `total_value`/weights/cash quote.
- **Allocation** (`for_portfolio/2`): same position/cash filter feeding the steering basis.
  (Keep the existing `excluded_from_allocation_targets` behavior untouched — ADR-0013 lives
  until #447.)
- **Performance** (`for_portfolio/2`): restrict the transaction stream to positions whose
  `{sa, sec}` is in scope (a security's view membership is its current bucketing) and cash
  accounts in scope. TTWROR/IRR then run on the scoped cashflows.
- **Risk** (`for_portfolio/2`): risk is computed from the weighted scoped positions, so it
  inherits scoping through the valuation/positions it consumes.

## Tasks / Subtasks

- [ ] **Task 1 — Pure `in_view?/2`** (AC 1,4): add to `BucketResolution`, refactor
      `holdings_matching_view/2` to use it; unit tests (incl. exclude-wins, untagged).
- [ ] **Task 2 — `Buckets.load_scope/2` + `position_in_scope?/3` + `cash_in_scope?/2`** (AC 1,2,4,5):
      bulk-load per portfolio; `nil` → `:unscoped`; DataCase tests (inherit, override,
      explicit-empty, multi-tag overlap single-count, cash membership).
- [ ] **Task 3 — Valuation `:view`** (AC 1,2,3,5,6): filter positions + cash; byte-identical
      default test; per-view + multi-tag + cash-in-view Decimal-exact tests.
- [ ] **Task 4 — Allocation `:view`** (AC 1,2,3,6): filter; default identical; keep ADR-0013.
- [ ] **Task 5 — Risk `:view`** (AC 1,2,3,6): scoped positions; default identical.
- [ ] **Task 6 — Performance `:view`** (AC 1,2,3,5,6): scoped transaction stream; default
      identical (the highest-risk engine — pin the default hard).
- [ ] **Task 7 — Gates & docs**: format, test, coveralls, credo, sobelow, dialyzer,
      pre-commit. API/MCP n/a here (#445). No user-visible surface yet (#446) → no product docs.

## Dev Notes

- **Byte-identical default is the headline guarantee (AC 3).** Every engine keeps its current
  code path when `:view` is absent; scoping is an *additional filter step* gated on a non-nil
  scope. Pin with a test asserting the `:view`-less result equals the pre-change result
  (Decimal-exact).
- **Holdings never stored (ADR-0004); positions are `{sa, sec}`** — never add a holdings table.
- **Decimal discipline:** `Decimal.equal?`/exact serialized strings in tests; no float deltas.
- **Engine purity:** the membership decision is pure (`in_view?/2`); the bulk DB loads live in
  `Buckets.load_scope/2` (shell), called by the read models before compute.
- **Cash in view (AC 5):** filter cash accounts by `cash_in_scope?` in both valuation and
  performance so an excluded person's cash leaves the scoped totals.
- **Exemplars:** `lib/portfolixir/portfolios/valuation.ex` (`for_portfolio/2`),
  `lib/portfolixir/buckets.ex`, `lib/portfolixir/engines/bucket_resolution.ex`, ADR-0018, ADR-0013.

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (high reasoning), Claude Code dev-story workflow.

### Completion Notes List

### File List

## Change Log

| Date | Change |
| --- | --- |
| 2026-06-19 | Started #444 engine scoping. |
