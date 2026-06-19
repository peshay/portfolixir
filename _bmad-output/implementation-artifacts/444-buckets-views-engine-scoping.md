# Story: Buckets & views — engine scoping (GitHub #444)

Status: review (partial — valuation/allocation/risk; performance deferred)

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
5. Cash respects its bucket (a view excluding "Family" excludes that bucket's cash too).
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

- [x] **Task 1 — Pure `in_view?/2`** (AC 1,4): add to `BucketResolution`, refactor
      `holdings_matching_view/2` to use it; unit tests (incl. exclude-wins, untagged).
- [x] **Task 2 — `Buckets.load_scope/2` + `position_in_scope?/3` + `cash_in_scope?/2`** (AC 1,2,4,5):
      bulk-load per portfolio; `nil` → `:unscoped`; DataCase tests (inherit, override,
      explicit-empty, multi-tag overlap single-count, cash membership).
- [x] **Task 3 — Valuation `:view`** (AC 1,2,3,5,6): filter positions + cash; byte-identical
      default test; per-view + multi-tag + cash-in-view Decimal-exact tests.
- [x] **Task 4 — Allocation `:view`** (AC 1,2,3,6): filter; default identical; keep ADR-0013.
- [x] **Task 5 — Risk `:view`** (AC 1,2,3,6): scoped positions; default identical.
- [ ] **Task 6 — Performance `:view`** (AC 1,2,3,5,6) — **DEFERRED to a focused follow-up.**
      Performance is a time-weighted/money-weighted series, not a snapshot: scoping it
      correctly means **reclassifying transfers across the view boundary as external flows**
      (e.g. buying an in-view security with out-of-view cash is an inflow to the view).
      This sub-portfolio flow rule is a deliberate money-math decision and is split out so the
      TTWROR/IRR semantics are designed, not rushed. Tracked as the remaining part of #444.
- [x] **Task 7 — Gates & docs**: format, test, coveralls, credo, sobelow, dialyzer,
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

- Shared scope seam: pure `BucketResolution.in_view?/2` + `Buckets.load_scope/2`,
  `position_in_scope?/3`, `cash_in_scope?/2`. `nil` view → `:unscoped` → byte-identical.
- Valuation scoped (positions + cash); allocation and risk inherit scoping via the
  valuation they compute over (allocation already forwards `opts`; risk's `Keyword.split`
  gained `:view`).
- Decimal-exact tests per engine incl. the include-everything == no-view identity.
- Performance (Task 6) deferred: scoped TTWROR/IRR needs deliberate boundary-flow
  semantics (transfers across the view boundary become external flows) — split to a
  focused follow-up so returns are not computed wrong. #444 stays open for it.
- Gates: `mix test` 776/0, coveralls 84.2% (buckets 94.6%, valuation 97.8%, risk 96.7%,
  allocation 97.6%), credo clean, sobelow 0, dialyzer 0, pre-commit pass.
- API/MCP: n/a here (#445). No user-visible surface (#446) → no product-docs change.

### File List

Modified:
- `lib/portfolixir/engines/bucket_resolution.ex` (`in_view?/2`)
- `lib/portfolixir/buckets.ex` (`load_scope/2`, `position_in_scope?/3`, `cash_in_scope?/2`, shared `classify_override/1`)
- `lib/portfolixir/portfolios/valuation.ex` (`:view` scoping of positions + cash)
- `lib/portfolixir/portfolios/risk.ex` (`:view` forwarded to valuation)
- `test/portfolixir/engines/bucket_resolution_test.exs`
- `test/portfolixir/buckets_test.exs`
- `test/portfolixir/portfolios/valuation_test.exs`
- `test/portfolixir/portfolios/risk_test.exs`
- `test/portfolixir/portfolios/allocation_test.exs`

New:
- `_bmad-output/implementation-artifacts/444-buckets-views-engine-scoping.md`

(Allocation needed no source change — it already forwards `opts` to `Valuation`.)

## Change Log

| Date | Change |
| --- | --- |
| 2026-06-19 | #444 (partial): scoped valuation/allocation/risk by view via a shared seam; performance deferred. All gates green; status → review. |
| 2026-06-19 | Started #444 engine scoping. |
