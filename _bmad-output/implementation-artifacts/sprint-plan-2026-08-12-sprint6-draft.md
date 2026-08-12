# Sprint Plan — Sprint 6 (DRAFT, 2026-08-12)

**Status: draft.** It is written from the owner's stated expectation for this
sprint — *finish the UI topics, solve the computed-numbers/cache problem,
implement some of the LLM agent's feature requests* — and it records where that
expectation meets the repository's own rules. Three open questions at the end
need the owner's answers before this becomes the adopted plan; OQ-1 is a hard
gate, the other two are scope calls.

Ground truth: `main` at `541fb89`. Verified against the merge commits, the open
pull-request list (**empty**), the open-issue list (46 open) and the Actions
runs on `main` — not against tracking files. CI is green through `14c18a0`; the
run on the head commit was still in progress at writing time.

## The expectation, checked against the board

| Owner expectation | Verdict | Where it lands |
|---|---|---|
| Finish the UI topics | **Partly.** Alignment and defect closure fit one batch; two items are new-surface builds, not polish | Lane A + OQ-2 |
| Solve the computed-numbers/cache problem | **Blocked, not missing.** ADR-0039 is *Proposed*, owner sign-off pending — ADR-0026 step 1 requires the gate before the batch starts | Lane C + OQ-1 |
| Implement some of the agent's feature requests | **Yes, fully ready.** #665 and #666 are ship-now, no gate; #667 and #664 join them | Lane B |

Nothing in the expectation is unreasonable and nothing is already done. One
third of it depends on a signature that has not been given yet, which is the
single most useful thing this document says.

## Sources

- Owner feedback triage 2026-08-12 (`planning-artifacts/feedback-triage-2026-08-12.md`),
  Rounds 3 and 4 — the identity answers and the issue index.
- ADR-0039 (durable derived values, gate B3.2) — **Proposed**.
- `design-language/DESIGN.md` + `EXPERIENCE.md` — the authority every
  user-visible lane is held against (ADR-0038).
- `epics.md` section J (FR-37..FR-48) and the FR Coverage Map.
- Sprint 5 retrospective and close-out (`sprint-5-retro-2026-08-10.md`).

## Batch topology (carried forward, confirm or override)

The Sprint 5 owner decisions are carried forward unchanged, because nothing
since has argued against them: **all lanes in ONE batch on one epic branch**
(`agent/claude/sprint-6-…`), **one PR for the sprint**, a lane split into its
own PR only if it turns out big during the batch — decided up front, flagged in
the reviewer briefing rather than asked mid-sprint.

## Lanes

### Lane A — UI: close the design-language debt (the "finish the UI" half that is closeable)

Fourteen E11 issues are open. Eleven of them are alignment and defect work
against a spec that already exists, which is what makes them closeable in one
batch: the 2026-08-05 design session left a work list, not a survey to repeat.

**A1 — surfaces still off the design language** (one commit group per surface):

- #668 Wealth tabs: icons, touch-target floor, structural nesting carrier.
- #669 performance period selector and date picker are bare text fields.
- #670 contra-account value-setting UI, own design language under the chart.
- #671 snapshots view brought onto the design language.
- #673 Overview "needs attention" card names the view and plan it refers to.

**A2 — the addressability cluster** (#651 first, it unblocks the other two):

- #651 securities filters are not URL-addressable → nothing can link to a
  filtered list.
- #561 data-quality counts without a path to fix (URL filters, missing
  logo/quote filters, bulk retriggers) — depends on #651.
- The Overview data-quality link recorded as impossible in the Sprint 4 Lane A
  close-out becomes possible once #651 lands. Close the loop explicitly.

**A3 — the remaining spec deviations:**

- #412 forms and inputs: alignment, heights, design (`needs-uat`).
- #491 master-data creation UX: two design languages plus smaller fixes.
- #565 securities table: classification categories as configurable columns.
- #566 replace toasts with inline busy/result states app-wide.
- #564 wealth chart data table: meaningful summaries instead of a downsampled
  daily dump (`needs-uat`).

**Not in Lane A — see OQ-2.** #672 (`/cashflow` parent plus three specified but
unbuilt facets) and #414 (turn the flat transactions list into a real overview:
filters, grouping, running balance, summaries) are **new surfaces**, not
alignment. Calling them "UI polish" is how a sprint quietly doubles. They are
sized as their own batch.

**Closing act for this lane:** a design-critic review against the living spec is
mandatory for user-visible surface (ADR-0026 step 3 / ADR-0038), and the Sprint 5
retro's evidence says the UAT persona on a live server with screenshots is the
only role that catches computed-style regressions. Both run.

### Lane B — The agent's feature requests (ship-now, no gate)

These are the confirmed items from the owner's own triage of the agent's
requirements document, already filed as thin issues.

- **#665 (FR-37) — read ergonomics.** Per-endpoint field selection and
  projections, roll-up-only aggregates that omit the position rows, and
  server-side threshold filters. The constraint is part of the requirement: a
  validated per-endpoint whitelist, never a query-builder passthrough, and
  `String.to_existing_atom/1` at the boundary. Acceptance is measured — −70 %
  response volume on the four heaviest reads, with a field inventory proving
  nothing load-bearing was cut. Supersedes FR-33's scope lock for this family
  only. API and MCP together (AR-11).
- **#666 (FR-38) — `?since=` delta reads.** A caller asks what changed since a
  timestamp or version instead of re-reading full state. **The push half stays
  gated at B3.7 and must not be scoped into this story** — that boundary is the
  story's own acceptance criterion.
- **#667 — tax snapshot staleness warning and allowance-order entry.** Follow-up
  on the shipped E19 surface; the trim budget already carries `as_of`, this
  makes the staleness visible and lets the Freistellungsauftrag be entered
  rather than only recorded.
- **#664 — verify a PP re-import preserves classification, target weights, notes
  and attributes.** **Verification first, risk-tier attention.** Story 18.2
  shipped this guarantee with a golden-path test; this re-tests it against
  today's code. If it confirms a regression, it becomes the most urgent defect
  on the board and the rest of the sprint re-sequences around it. Run it early
  in the batch, not late.

**Two-way coverage rule (amended 2026-08-12).** #665 and #666 are agent-visible
capabilities and may ship over API/MCP with no human view, provided the PR says
why. That is a commitment with a deadline: the human view lands in this or the
next batch, and its absence after that is a close-out finding.

**Metric basis rule.** Anything in this lane that ships a metric states its
computation basis in the API *and* MCP payload — input series, window, reference
series, gap treatment. Review-blocking; a docs page does not satisfy it.

### Lane C — Durable derived values (CONDITIONAL — see OQ-1)

This is the owner's "numbers should not be computed at page view" item, and it
is the one lane that **cannot start today**. ADR-0039 is *Proposed*; ADR-0026
step 1 requires a signed-off decision gate before a batch touches the tree.
Deliberately, no issues have been filed for it — filing them before the
signature would produce titles with no authoritative spec behind them.

If the ADR is signed off, the lane is:

- **C1 — the mechanism.** One derived-value axis with a lifetime parameter
  (`:none` / `:request` / `:durable`); ADR-0032's volatile memo becomes the
  `:request` case and stops existing as separate machinery.
- **C2 — the invariants before the activation.** ADR-0039 §5 is blocking and
  states the acceptance criteria as an equation, so it is tested as invariants,
  including the backdated-transaction invalidation case (I3) that naive
  implementations get wrong, and the write-path prohibition (I7).
- **C3 — first activation: the daily performance walk**, on the ADR's own
  measured evidence (11.4 s at 200 securities, second call identical to the
  first). Nothing else is activated by opinion.
- **C4 — freshness in the payload.** `as_of` plus an explicit stale marker, in
  the UI *and* in the API/MCP payload — property 3 of four, and the one users
  and agents actually see.
- **C5 — drop-and-rebuild as a single operator command** that reports its own
  runtime; the runtime is measured on operator hardware and recorded back into
  ADR-0039 as an amendment (§6).

**Risk tier: projection semantics.** TDD first with exact `Decimal`
expectations, its own commit group, a dedicated verification pass on the
invalidation invariant in the agentic review, and an explicit callout in the
reviewer briefing.

**If OQ-1 is not answered before the batch starts, Lane C is out of Sprint 6**
and the sprint runs as A + B + M. It does not run "informally in parallel" — a
gate that can be worked around is not a gate.

### Lane M — Maintenance (mandatory, every batch)

Per the AGENTS.md Epic-Batch amendment of 2026-08-12 (owner: *"unbedingt immer
mit rein"*), every batch reviews available updates for Hex, npm, Elixir/OTP,
PostgreSQL, BMAD and the external BMAD modules, applies what passes the gates,
and **reports what it deliberately did not update, with the reason**. Each
update lands as its own commit group, never mixed into a feature story.

- #674 BMAD 6.8.0 → 6.11.0, and pin the `automator` module to a SHA.
- #676 Renovate/Dependabot plus a version report the lane can read — the lane
  is only cheap if it does not start with a manual survey every time.
- The dependency posture inherited from Sprint 3: two cowlib advisories, neither
  HIGH, both without an upstream fix, already documented as tolerated in
  `ci.yml`. Re-check, do not re-litigate.

### Lane Z — Close-out debt from Sprint 5 (small, do it first)

- **The v0.5.0 tag was never pushed.** The Sprint 5 close-out records an
  annotated tag on `73affc5` triggering the new Release workflow. The remote
  carries exactly one tag (`before-agentic-run`) and the repository has zero
  releases, so ADR-0026 step 5 is incomplete for Sprint 5 and the #659 release
  automation has never actually run. Push the tag on `73affc5` (or record why
  not), and confirm the workflow produces the release — an automation whose
  first run is the Sprint 6 close-out is an automation nobody has tested.
- **#682** (intermittent multi-test failure bursts — make them capturable
  first) rides here if it stays cheap; it is diagnosis before fix by its own
  title, and #654's test-failure artifact is the instrument it needs.

## Sequencing

1. **Lane Z** — tag first, it is minutes and it closes a false record.
2. **#664** (Lane B verification) — early, because a confirmed regression
   re-sequences everything after it.
3. **Lane B** ship-now stories, API and MCP together.
4. **Lane A** in the order A2 → A1 → A3 (#651 unblocks #561, so addressability
   leads).
5. **Lane C** if and only if OQ-1 is answered yes; risk-tier, own commit groups.
6. **Lane M** reviewed throughout, reported at the close-out.

## Explicitly out of scope

- #672 and #414 — new surfaces, see OQ-2.
- Everything behind an unsigned gate: policy rules (B3.6), security events
  (B3.4), theses and predictions (B4.1/B4.2), the rebalancing digest (B3.5),
  collection (B3.3), push delivery (B3.7), the local model (B3.8), backtesting
  (ladder level (d)). FR-39..FR-42 depend on Lane C's mechanism for where their
  values live and are not scoped here either.
- The structural epic decision (epics.md E1–E19 vs. the GitHub tracker set) and
  the fact that section J's FR-37..FR-48 hang off no epic row. Recorded as a
  standing finding in `sprint-status.yaml`; it is an owner decision, not batch
  work, and #321 stays stale until it is made.

## Gates

Unchanged and blocking: `mix format`, `mix test`, `mix coveralls`,
`pre-commit run --all-files`, `npm test --prefix mcp-server`,
`npm run build --prefix mcp-server`, `--warnings-as-errors` clean, Credo strict,
Sobelow, Dialyzer. Weakening any of them to make the batch pass is a review
reject. The agentic review closing act runs with four roles for this sprint,
because Lane A is user-visible surface and Lane C, if it runs, is risk-tier.

## Open questions

**OQ-1 (blocking for Lane C) — is ADR-0039 signed off?** It is *Proposed* as of
`541fb89`. ADR-0026 step 1 makes the signature the precondition for the batch,
not a formality to catch up on later. Answer yes → Lane C runs as specified.
Answer no or not yet → Sprint 6 is A + B + M + Z, and the cache problem moves to
Sprint 7 with the ADR review as its own owner task. There is no third option
that respects the gate.

**OQ-2 (scope) — does "finish the UI topics" include the two new surfaces?**
Lane A closes eleven alignment and defect issues. #672 (`/cashflow` and its
three unbuilt facets) and #414 (transactions overview: filters, grouping,
running balance, summaries) are builds, not alignment, and together they are
plausibly a batch of their own. Options: (a) Lane A as scoped, the two surfaces
get Sprint 7; (b) add #414 only; (c) add both and accept that Lane C or Lane B
loses room.

**OQ-3 (carry-over) — #572 benchmark comparison.** The Sprint 5 plan named it
"the unblocked front-runner for Sprint 6", and FR-9 was ungated on 2026-08-12 by
the scope ladder as level (b). The stated expectation for this sprint does not
mention it. In or out? It is money-domain analytics and it is not small.
