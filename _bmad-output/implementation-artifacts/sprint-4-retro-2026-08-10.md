# Sprint 4 Retrospective — Lanes B and C (2026-08-10)

**Final (2026-08-10):** both PRs are merged — **#656** (`#560`) as
`9eaf858`, **#657** (`#568`) as `5167f27` — issues auto-closed with the
squash-merges, merge CI green. Lane A (design-language spec) had merged
earlier as #652 with its own close-out (#655). Sprint 4 is complete; the
ADR-0026 step-5 bookkeeping rides this commit (sprint-status.yaml
close-out block, this retro, the Sprint 5 sequencing draft).

## What shipped

- **Lane B (#560):** income charts scroll horizontally on narrow viewports —
  SVG + labels share an `.income-chart-track` (`min-width: max-content`)
  inside an `.income-chart` scroller with the UX-DR15 affordance (border +
  radius). Desktop unchanged.
- **Lane C (#568, ADR-0034):** XIRR solver aligned (Newton from 0.1 +
  bracketed bisection fallback, Excel-parity pinned), summary gains
  `invested_capital` / `wealth_multiple` / `mwr`, Wealth KPI row shows
  invested capital as two labeled numbers, the multiple with n/a semantics,
  and the MWR label for sub-year windows; API + MCP parity and EN/DE docs.

## What went well

1. **Delta over rebuild.** The IRR machinery from #577 and the projection's
   per-kind `external` flag already covered most of ADR-0034; the "flow
   classifier" resolved as *verification* (pinned in `projection_test.exs`),
   not new code — deliberately avoiding a fork of booking semantics
   (ADR-0011).
2. **The closing act earned its keep.** Two independent verification roles
   (correctness hunter, edge-case hunter) confirmed six findings — float
   island violation, rescue swallowing the fallback, an invented root on
   one-day windows, a negative wealth multiple, a missing scroller
   affordance, a frozen a11y label — all fixed on the branches *before* the
   PRs went up for review. None were hypothetical; each got a pinning test.
3. **Resumable steps worked.** Each step (Lane B, solver, metrics+UI,
   API/MCP/docs, review fixes) was a green commit pushed immediately — the
   session could have died at any point without losing work.
4. **TDD order held per step**, red confirmed for the expected reason each
   time, including the review-fix round.

## What to improve

1. **Branch topology decided late.** The sprint ran on one combined branch
   and was split into per-lane branches only when the per-lane-PR
   instruction arrived. Cheap this time (clean cherry-picks), but the next
   sprint plan should fix the branch/PR topology up front.
2. **CSS comments must not spell `#NNN`.** The css-token-discipline
   invariant reads `#560` as a hex colour; the repo convention in
   `app.css` is `issue 560`. Small, but it cost a full-suite round.
3. **Defensive-path coverage has a floor.** Two `ArithmeticError` rescue
   lines in the solver are documented-unreachable without century-scale
   contrivance; the reachable twin is pinned behaviorally. Accepting
   labeled residual lines beats assertion-free line-touching tests (repo
   policy) — recorded here so the next coverage ratchet discussion has the
   context.
4. **Fixture arithmetic gets verified before it gets asserted.** One
   hand-derived expected value (de-annualization fixture) was off at the
   6th decimal and had to be recomputed; independent numeric verification
   first (as done for the solver fixtures) is the cheaper order.

## Numbers

- Test suite: 1715 → 1727 tests, 0 failures; credo strict, sobelow,
  pre-commit, mcp-server tests (62) and build all green locally and in CI.
- Codecov: project steady at 90.12%; patch 100% (#656) and 96.92% (#657,
  target 90%).

## Closed with the merge

- #656 and #657 squash-merged by the owner; #560 and #568 auto-closed;
  merge CI green; `sprint-status.yaml` carries the Sprint 4 Lanes B+C
  close-out block alongside Lane A's (#655).
- #572 (benchmark comparison) is now unblocked — it reuses the projection's
  flow markers that #568 verified and pinned.
