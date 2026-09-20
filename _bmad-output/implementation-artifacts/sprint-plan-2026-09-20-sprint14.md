# Sprint 14 — the portfolio half of the metrics, the surface the risk lens never had, and the closing act's debt

**Status: ADOPTED by the merge of the Sprint 14 planning PR (2026-09-20).**
The merge is the signature (ADR-0026 step 1 as amended on PR #780). Unlike
Sprint 13's, this planning PR **signs no new decision gate**: every build item
below already has a signed ADR behind it, and the one gate with accumulating
evidence — **B3.6**, policy rules — is deliberately not opened here (D-6). What
the merge does adopt is the lane cut, **D-1** to **D-9**, the correction to
ADR-0047 §9 that D-2 carries, and the two process amendments in D-7 and D-8.
Nothing in this PR is `DRAFT` or `Proposed`; a decision the owner rejects is
removed on the PR before the merge.

**Verification basis:** `main` at `dabcd27` (the Sprint 13 close-out commit)
with CI run **1554** and Commit authorship 568 green on it, read 2026-09-20;
the open-issue list of 2026-09-20 (34 open before this planning round, one
filed by it — #844); the open pull requests (**none**, the first
sprint opening with an empty PR list since Sprint 11); the published releases
(latest **0.10.0** of 2026-09-07, three tags outstanding); the Sprint 12 and
Sprint 13 retrospectives; the 2026-09-19 agent round
(`planning-artifacts/feedback-triage-2026-09-19.md`) and its two declared
Sprint 14 candidates; the Sprint 13 version report; and **the code**, read for
ADR-0047's unbuilt half and for the human-view claim in its §9 rather than
summarized from this repository's prior statements. Where this plan contradicts
an existing record it says so and shows the read (D-2).

## State of play, in five lines

1. **Sprint 13 merged and closed out.** PR #832 rebase-merged 2026-09-19,
   fourteen issues closed by keyword and three by hand, **E11 and E23 done**.
   The two-way coverage deadline fired end to end for the first time and was
   met (#814). No PR is open and nothing is in flight.
2. **E22 is the only epic this sprint can finish, and finishing it is the
   point.** Tracker **#821** stays open on exactly three things, all declared:
   ADR-0047's portfolio and view figures — **Sprint 13's Lane A2**, this
   sprint's **Lane A1**, with identities I1, I3 and I4's portfolio half —
   **#838** (the payload half of §6's amendment) and **#825** (the
   per-security invalidation basis). Nothing else is needed for the epic to
   close.
3. **ADR-0047 §9 names a surface that does not exist**, and this plan found it
   by reading the code rather than the record — see **D-2**. The portfolio
   figures were to land "on the Wealth risk surface"; `Portfolixir.Portfolios.Risk`
   is consumed by `risk_controller.ex` and by nothing else in
   `lib/portfolixir_web/**`. The concentration lens has been **agent-only since
   it shipped**, which predates the two-way coverage rule and is therefore a
   debt the rule never caught.
4. **The closing act left ten findings and they are cheap, not deferred.**
   Three are error-contract defects that answer **500** where the contract
   promises 4xx (#839, #840, #841); six are design-spec conformance (#833,
   #834, #835, #836, #837, #842). E11 is closed and **does not reopen** — these
   are held against the living spec by the standing design-critic gate
   (ADR-0038), not by a tracker.
5. **The agent's two declared candidates are the last of its surface
   complaints**, and one of them turns out to carry a decision rather than a
   build (#830, **D-5**). #831 is one sentence in each of several tool
   descriptions.

## Why this cut

- **An epic that closes is worth more than an epic that advances.** E22 has
  been half-built since 2026-09-19 by a trade this project made deliberately
  (Sprint 13's D-7) and recorded as Sprint 14's to discharge. Three items
  close it. Leaving any of them out means carrying an open epic into a third
  sprint for the sake of work that was already sized.
- **The debt is small, verified, and in the way.** Every Lane B and Lane C item
  arrived with a reproduction attached (Sprint 13 process finding 4). None
  needs investigation; they need a commit each. A repo-wide id parser (#840)
  and a single held-predicate (#839) each remove a whole class rather than an
  instance, which is the only kind of debt work worth a lane.
- **One lane is bigger than the record said it was, and the plan says so
  before the batch discovers it.** D-2 turns ADR-0047 §9's one-line placement
  into a scoped decision with three options and a recommendation. Sprint 13
  made its capacity trade at planning time (D-7) rather than inside the shrink
  order, and that is the precedent being followed.
- **The two lanes do not fight over files.** Lane A is `portfolios/risk.ex`,
  the engines, the API layer, the MCP companion and one new LiveView; Lane C is
  `app.css` and `securities_live.ex`; Lane B is controllers and two changesets;
  Lane D is controllers and tool descriptions. The one overlap is Lane C's
  `securities_live.ex` against nothing in Lane A — A4's surface is a Wealth
  page, not the securities detail pane, which is what makes this a one-branch
  batch with no ordering problem to solve.
- **What waits, and why:** **B3.6** stays shut (D-6) with its trigger named;
  the level (b) requirements (FR-41 contribution, FR-42 exposure) stay unfiled
  — each needs its own argument, and FR-42's boundary against partial-weight
  advanced classifications is a decision, not a story. #835's *convergence* is
  cut at planning time (D-4) while its *decision* is taken here, which is the
  cheap half and the valuable one. #328/#608, #354 and the rest of the standing
  backlog are unchanged from Sprint 13's list.

## Lanes

### Lane A — ADR-0047's portfolio half, and E22's close (FR-40; risk-tier; first)

Five commit groups. The engine and its read are **filed at branch opening, not
now** — the 2026-08-15 precedent, reaffirmed by Sprint 13's Lane Z: no issue
carries a title with no spec behind it, and this PR's merge is the signature
that lets them be written. #838 and #825 exist already and keep their numbers.

- **A1 — the portfolio and view figures on the risk read.** `volatility`,
  `max_drawdown` with `peak_date` / `trough_date` / `recovery_date` and its
  window, `risk_adjusted_return`, and the Top-N `correlations` matrix.
  **Additive** on `GET /api/v1/portfolios/:portfolio_id/risk` and
  `portfolixir.portfolios.risk` — ADR-0047 §9 states the family has exactly one
  endpoint and the view arrives as the `?view=` parameter the lens already
  honours, which is the sentence the close-out's surface check repeats rather
  than rediscovers (D-9).
  - Over the **TTWROR chain's flow-adjusted daily return factors** (§2), never
    the day-over-day change of the portfolio's value. This is the invariant the
    whole record exists for.
  - `risk_free_rate=` is a request parameter, a Decimal string, **defaulting to
    `0`**, reusing ADR-0046's fixed-rate kind and its daily-compounding
    convention. At the default the payload's `reference` says in words that the
    figure is return per unit of risk. No rate is inferred, fetched or stored.
  - `correlations` **converts first** — base currency, the deliberate opposite
    of §1's per-security rule — computes each pair over the days on which both
    securities have a stored close, and carries the overlap count per pair. A
    security whose currency has no stored rate path is **absent from the matrix
    rather than silently unconverted** (I7).
  - Annualization is `√365` for the calendar walk (§4), stated in the basis.
    The float island is `:math.sqrt/1` and the boundary convention is the IRR
    solver's: Decimals in, `Decimal.from_float/1` then `Decimal.round/2` at
    **scale 6** out. AR-3 already names it — amended on the Sprint 13 planning
    PR — so nothing in `architecture.md` moves this sprint.
  - Registers `portfolio_metrics` with ADR-0039 §2 at computation version 1,
    default lifetime **`:request`**, keyed under `DataVersion.portfolio_basis/1`
    exactly as `performance_analysis` does (§8).
  - TDD first with exact-`Decimal` fixtures. **I1**, **I3** and **I4**'s
    portfolio half land here. I1 is the one to write first and the one the
    risk-tier pass re-derives: *a portfolio whose prices never move, with any
    number of deposits and withdrawals, has volatility exactly `0` and maximum
    drawdown exactly `0`.*
  - **The scale clause is asserted, not assumed.** Sprint 13's risk-tier pass
    found I2 unpinned because the helper compared with `Decimal.equal?/2`,
    which ignores scale. I3 is stated *at scale 6* and this lane's helper
    compares the string, not the value.
- **A2 — `required` on every metric, in both states (#838).** ADR-0047 §6 as
  amended 2026-09-19. `required` carries §5's minimum `observations` on **every**
  metric whether it computed or refused, so a reader comparing two payloads does
  not have to know which state they are in to find the threshold; `window` is
  `null` where the metric is defined over a count of closes. Both payloads — the
  per-security one that shipped in Sprint 13 and A1's new portfolio one — plus
  the contract-manifest entry, the MCP schema mirror and the EN/DE integration
  doc lines. **Rides A1 so the surface takes one contract bump rather than
  two**, which is the reason the issue names this sprint.
- **A3 — the boundary, extended.** `test/invariants/metrics_carry_no_verdict_test.exs`
  walks the **portfolio-scope** payload as well. Its moduledoc already names
  this sprint, which is the meta-test doing its job: the boundary was written
  down where the next batch would read it. Rides A1 rather than trailing it —
  a boundary test written after the payload tends to describe the payload.
- **A4 — the human view, and the surface it needs.** **See D-2**; it is the one
  item in this lane whose shape is decided on this PR rather than by ADR-0047.
- **A5 — the per-security invalidation basis (#825).** `DataVersion.security_basis/1`,
  bumped by `Invalidation.after_quote_write/1` alongside the portfolio bases, so
  a quote write for a security **no portfolio has ever held** bumps a counter
  that exists. `BlastRadius.for_quote/1` answers the portfolios that ever
  transacted the security, which for a benchmark or a watch-only candidate is
  the empty list — precisely the security whose research metrics are most
  wanted.
  **What A5 does not do:** it does not move `security_metrics` off lifetime
  `:none`. That move is a measurement question (ADR-0039 C3) which this issue
  unblocks and does not answer; ADR-0035 already says a value merely computed
  more often than necessary gets computed once rather than cached. The lane
  lands the seam and records the measurement as available, not taken.

**Risk-tier** (ADR-0036): money math on the analytics surface. Its own commit
group, TDD-first with exact-`Decimal` expectations, a dedicated verification
pass in the closing act taking I1, I3, I4 and I7 one at a time with findings
reproduced before they are surfaced, and an explicit callout in the reviewer
briefing (D-8).

### Lane B — the error contract, one class at a time (three closing-act findings)

- **B1 — #840, an id beyond bigint answers 500 across the JSON API.** Repo-wide
  and not a Sprint 13 regression: `/securities/<big>`, `/securities/<big>/quotes`,
  `/trades` and `/notes` all reach the driver and raise `DBConnection.EncodeError`
  where every other malformed id answers 404 or 422. **One shared id parser at
  the controller boundary**, and the Sprint 13 endpoints inherit whatever it
  does. The contract is `docs/integration/api-and-mcp.md`; a 500 is not in it.
- **B2 — #841, a research note's `source_url` over 255 characters answers 500.**
  `Knowledge.SecurityNote` validates the URL's format and not its length against
  a `character varying(255)` column, so a link carrying tracking parameters
  raises `Postgrex.Error 22001`. The fix is the one `SecurityEvent` already
  carries: `validate_length(:source_url, max: 255)` with the bound stated beside
  the column width. One line and its test.
- **B3 — #839, two more copies of the "is it held?" predicate.** `Catalog` and
  `Knowledge` each carry a holdings-total subquery filtered to
  `t.type in ["buy", "sell"]` while `Ledger.Projection.effects/1` also moves
  quantity with `inbound_delivery`, `outbound_delivery` and `security_transfer`.
  A depot transferred in — the Portfolio Performance import's normal shape — is
  reported as not held. Sprint 13 fixed the copy it introduced and filed these
  two.
  **B3 is risk-tier**: this is projection semantics, and ADR-0036 names them.
  Its own commit, a verification pass on the invariant (what the canonical
  projection moves quantity with), a briefing callout. Either route all three
  through one predicate — the option this plan prefers, because a third copy is
  how the first two happened — or correct the claims the other two make in their
  docstrings and payloads, and say on the PR which was done and why.

### Lane C — design-spec conformance, and the ADR front matter (five findings plus #844)

Held against the living spec (`design-language/DESIGN.md` + `EXPERIENCE.md`) by
the standing design-critic gate, **not** under a reopened E11.

- **C1 — #833, `.num` has no generic rule.** `app.css` carries 15 `.num` rules
  and every one is descendant-scoped, so a plain `.data-table` renders
  `class="num"` with nothing behind it and `thead th { text-align: left }` is
  never overridden. DESIGN.md:947 already names the defect and its cause. One
  generic rule; it changes every table in the app, which is why it was out of
  Sprint 13's scope and is in this one deliberately, with the CSS layout sweep
  re-run.
- **C2 — #834, the kebab's focus ring and its coarse-pointer floor.**
  `.row-actions__kebab` and `.row-context-menu__item` both set `outline: none`
  with a background change as the substitute, which DESIGN.md's Do's and Don'ts
  names as the "don't" and lists these two rules by name. The compliant example
  is `.filter-sheet-toggle:focus-visible`, added in Sprint 13. Separately the
  kebab is `var(--space-1)` around a 16 px glyph — under the 44 px floor — and
  Sprint 13 put it on three more phone-reachable surfaces.
- **C3 — #836, `aria-pressed` / `aria-expanded` as bare booleans.** HEEx treats
  `attr={true}` on an arbitrary attribute as a boolean attribute: it renders the
  bare name and omits it entirely on `false`, which is wrong in both directions
  for an ARIA state. Six sites in `securities_live.ex`; the fix is `to_string(...)`,
  as the MA toggles already do. Reproduced in a browser with the rendered HTML
  in the issue.
- **C4 — #842, the `+N` overflow chip keeps its content in a `title`.**
  `bucket-cell.scope` says the scope sub-line is readable without interacting
  and that it replaces a `title`-carried meaning; three lines away the overflow
  chip still carries one. Show the overflow on tap through the row menu that is
  already there, or state the count differently.
- **C5 — #837, the detail pane's `role="tablist"`.** Carries a decision — **D-3**.
- **C6 — #844, four ADRs whose front matter does not parse.** Filed by this
  planning round; verified with Ruby's Psych, the parser Jekyll uses, against
  `main` at `dabcd27`. ADR-0036, ADR-0041, ADR-0042 and ADR-0043 carry an
  unquoted `description` containing `": "`. The story **confirms the effect on
  the published site before claiming one** — the Pages build has not failed and
  there is no `_config.yml`, so `strict_front_matter` is off — then quotes the
  four strings and adds the assertion that keeps them quoted, which
  `docs_test.exs` does not have today.

**#835 is decided here and built later** (D-4): the decision is this sprint's,
the convergence is not.

### Lane D — the agent's surface, finished (#830, #831)

- **D1 — #830, `?since=` on the reads a scheduled run polls.** Carries a
  decision — **D-5**. What ships is the parameter on the **row-collection**
  reads, with the close-out naming every member of the family and both shapes
  the parameter deliberately does not reach.
- **D2 — #831, the re-import guarantee in the tool descriptions.** The
  guarantee that a Portfolio Performance re-import does not destroy the research
  log — and, since Sprint 13, the security events — is true, tested and
  documented in a page the consumer does not open. Three editions of the agent's
  requirements document have carried the refuted premise. One sentence in the
  MCP tool descriptions of the reads it protects, where the consumer reads by
  construction. This is the metric-basis rule's "a doc page does not satisfy
  it" applied to a contract guarantee, and ADR-0048's Consequences already names
  the same mechanism for the new surface.

### Lane M — maintenance (always present)

- **Hex, npm, PostgreSQL, Elixir/OTP, BMAD and the external BMAD modules**
  reviewed at lane time; what passes the gates is applied as its own commit or
  commit group, and what is deliberately not updated is reported **with its
  reason** in `version-report-2026-09-XX-sprint14.md`, written **before** the
  closing act starts.
- **#727 (Elixir 1.20.x / OTP 29):** both triggers re-checked at lane time, as
  in Sprints 11, 12 and 13 — an excoveralls release naming Elixir 1.20 cover
  support, and an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet`
  opaqueness. Still its own branch and PR when it fires.
- **The Node runtime image:** no Dependabot PR is open this sprint, and the
  trigger is unchanged — Node 26 is Current until **October 2026** and the
  runtime is pinned in four places by an invariant test (#728). Sprint 11,
  Sprint 12 and Sprint 13 each closed the same bump for the same reason. On this
  project's cadence — the Sprint 9 to Sprint 13 plans are dated 2026-09-03,
  09-05, 09-07, 09-12 and 09-19 — the promotion falls **after** this sprint
  closes, so the expected
  outcome is a fourth decline with the same reason. **Re-check it at lane time
  anyway**, and if it has landed, apply the bump as its own commit together with
  the `@types/node` major that follows the runtime, and record it as applied.
  The trigger is a calendar event Dependabot cannot see; a lane that stops
  looking because the answer was "not yet" four times is how it gets missed the
  first time the answer changes.
- **The advisory database is read at run time.** Sprint 13's process finding 3
  is standing guidance for this lane, not history: a `quality` job that was
  green can go red with nobody pushing anything, and a red `mix hex.audit` on a
  Markdown-only commit is an advisory published since, not a regression.

### Lane Z — registry (small)

- **Files the Lane A story issues at branch opening** (A1, A3 rides A1, A4 in
  the shape D-2 picks) under area **#418**, and records the numbers on the
  FR-39/FR-40 coverage row beside #823, #824, #825 and #838.
- **FR-38's coverage row** gains #830 and the scope sentence D-5 decides — which
  members of the family carry `?since=`, and the two shapes that deliberately do
  not.
- **E22's Tracker Index line** is marked done at the close-out and **#821 is
  closed by hand** with the evidence: a tracking issue carries no direct PR, so
  no keyword reaches it.
- **Whatever D-4 decides about the column-picker treatment is written into
  `DESIGN.md`** in this lane, and the convergence is filed as its own issue with
  the decided treatment named — so the follow-up carries a spec rather than a
  question.
- The close-out reconciles against these rows and adds the dated reconciliation
  (ADR-0042: the FR Coverage Map, the Tracker Index and a dated reconciliation,
  never a story row).

## Decisions

### D-1 — one branch, and the reason it needs no ordering rule (recommended)

`agent/claude/portfolio-metrics-and-the-surface-debt`, opened on `main` at or
after `dabcd27`. Rebased onto `main` at least daily (ADR-0026 step 2); the
branch lives days, not weeks.

Sprint 13 needed a file-order safeguard because two lanes converged on
`securities_live.ex`. This batch does not: Lane A's human view is a **Wealth**
surface, Lane C's five conformance items are `app.css` and the securities detail
pane, and the two never open the same file. The sequencing below is therefore a
dependency order, not a safety rail — which is worth saying, because a plan that
carries a ceremony it does not need trains the next one to skip the ceremony
when it does.

### D-2 — A4's human view: ADR-0047 §9 names a surface that does not exist (recommended: **A**)

*(This lane was Sprint 13's "Lane A2". The letters are re-cut for this batch:
A1 is the engine and its read, A4 is the human view.)*

**The finding.** ADR-0047 §9 says the portfolio figures land "on the Wealth risk
surface". Read against the code on 2026-09-20: `Portfolixir.Portfolios.Risk` is
referenced by `lib/portfolixir_web/controllers/api/v1/risk_controller.ex`, by
the route, and by `mix portfolixir.derived.measure`. **There is no LiveView, no
component and no test in `lib/portfolixir_web/live/**` that reads it**, and the
only strings naming concentration, HHI or a cap violation anywhere in the tree
are in `risk.ex`'s own moduledoc and in `json.ex`'s basis prose — neither is UI
copy, and the German catalogue carries none of them. The single `Risk` hit in
`securities_live.ex` is `kind_label("risk")`, an ADR-0044 research-note kind.

So the concentration lens — FR-8's Top-N with severity, the HHI with its band,
FR-9's asset-class cap violations — is **agent-only, and has been since it
shipped**. That predates the two-way coverage rule of 2026-08-12, so it is not a
rule violation and no deadline was ever missed. It is the older thing the rule
was written to stop accumulating, sitting under an ADR clause that assumed it
had already been paid.

**Why this is the plan's decision and not the batch's.** A1 adds four
agent-visible figures, so the two-way rule fires on **A1**, and ADR-0047 §9
additionally committed their human view to the same batch. The question is not
*whether* — it is *onto what*, and the honest answers differ in size by a factor
of several. Sprint 13's D-7 is the precedent: make the trade at planning time.

| | Option | What it costs | What it leaves |
|---|---|---|---|
| **A** | **A sixth Wealth tab, "Risk", carrying the existing lens *and* A1's four figures** | One new LiveView and one tab entry | Nothing. FR-8/FR-9/FR-10 get the operator half they never had, and FR-40's figures land where §9 assumed they would |
| B | A1's four figures folded into an existing Wealth surface; the lens stays agent-only | A metric strip on a page that already exists | The older debt, now with four more figures on top of it and no deadline attached to any of it |
| C | No human view this batch; the coverage deadline recorded for Sprint 15 | Nothing now | A new debt beside the old one, which is the outcome Sprint 13's D-2 argued against by name |

**Recommended: A**, for three reasons that are checkable rather than
aesthetic.

1. **The tab row is already built for a sixth tab.** `AppShell.area_tabs/1`
   renders `.area-tabs`, which carries the D6 shipped form in `app.css` today —
   `overflow-x: auto`, `scroll-snap-type: x proximity`, the 40 px right-edge
   mask, no scrollbar, and `flex: none` with `scroll-snap-align: start` on the
   tab so overflow is real overflow rather than a compressed label (#790, #702).
   It is the row #817 *copied from*. Wealth carries five tabs today (Holdings,
   Allocation & targets, Cash flow, Snapshots, Tax). A sixth costs a list entry,
   not a layout problem — the opposite of Sprint 13's tab budget, where the
   detail pane's ninth tab made #817 load-bearing.
2. **The figures belong to the same question.** "How concentrated am I" and
   "how much does this portfolio move" are one screen's worth of question, and
   splitting them puts A1's volatility on a page that cannot show what it is the
   volatility of.
3. **It is the only option that reduces the debt rather than moving it.** B and
   C both end the sprint with the lens still agent-only and no date on it.

**What the surface carries (the spec; the anatomy is the design pass's).**
The existing lens, unchanged in meaning: the Top-N single names with their
percentage weight and `ok`/`warn`/`hard` severity, the HHI with its band, and
the asset-class cap violations where any are configured — all on the **steerable
basis**, scoped by the active view, with the basis named on the surface as
UX-DR26 requires. Plus A1's four figures with their window, observation count
and `required`, refusing visibly where §5's minimum is not met rather than
rendering a dash. The correlation matrix is a **disclosure**, not a default —
the precedent is #807's year matrix behind "Realisiert je Periode".

**What this decision does not do.** It does not change what the lens computes,
it adds no threshold, and it displays no verdict: an HHI band and a `warn`
severity are the lens's own existing vocabulary, not a signal (ADR-0047 §7). No
rebalancing hint rides in on it; ADR-0023 permits those and this batch does not
build them.

**One consequence rides with A and the sequencing states it:** the design pass
for this surface has **not** run — the finding is a day old. It runs at branch
opening, before A4 opens, on the same mechanism as Sprint 13's D-8: variant
boards, the recommendation as the default pick, a comment naming another letter
changes it, and the picked anatomy written into `DESIGN.md`. **If the pass shows
the surface is larger than this spec**, A4 is the last item in the shrink order
and the close-out records the coverage deadline — which is the rule working, not
the rule being waived.

**To flip this by comment:** "B" keeps A1's figures and leaves the lens where it
is; "C" defers both with the deadline recorded. Either is a legitimate outcome;
neither is the outcome of not deciding.

### D-3 — #837: the detail pane keeps its `tablist` role and gains the roving tabindex (recommended)

The issue names two ways out and says the choice is the decision it needs. Read
against the markup:

- `AppShell.area_tabs/1` renders `<nav><a href>` with `aria-current="page"` and
  **no `tablist` role** — it is navigation, and correctly unmarked.
- The detail pane renders `<nav role="tablist">` with `<button role="tab"
  phx-click="select_detail_tab">` — it switches panels inside one pane and
  changes no route. That **is** a tab widget.

The two are different things, which is exactly why one carries the role and the
other must not. So the role stays and the pattern gets completed: a roving
`tabindex` (`0` on the selected tab, `-1` on the rest), Arrow Left/Right with
Home/End, and `aria-controls` **only on the selected tab**, because the panel
ids the other eight point at do not exist while their tab is inactive — which is
the half of the finding that is invalid markup today rather than missing
keyboard support.

Dropping the role is the cheaper fix and it is the wrong one: it would tell a
screen-reader user that nine panel switchers are nine unrelated buttons, and it
would make the detail pane disagree with the only other tab row in the app about
what a tab row is.

### D-4 — #835: `.popover` wins, and the convergence is filed rather than built (recommended)

Two treatments coexist. `DESIGN.md` → Inventory → Overlays names **`.popover`**
as the treatment for column pickers and filters, which
`PortfolixirWeb.Securities.ColumnPicker` implements — `role="dialog"`,
`aria-label`, a `.popover-head` heading, grouped `<fieldset>`/`<legend>`. The
transaction history's `#tx-column-picker` and Wealth Positions'
`#holdings-column-picker` are both a `<details>` with a flat checkbox list.

**The decision: `.popover` is the treatment, and the spec is not amended to
match the drift.** Under ADR-0038 the living spec is the authority the
design-critic review holds work against; amending it because two surfaces
diverged inverts that. The `<details>` pickers are the non-conforming side.

**The convergence is cut from this sprint at planning time.** The issue says
converging the three is larger than one batch, the component is namespaced under
`Securities` and has to become shared first, and two surfaces get rebuilt.
What this PR spends is the decision: Lane Z writes it into `DESIGN.md` and files
the convergence as its own issue **with the treatment named**, so the follow-up
carries a spec instead of the same question.

This is the plan's second capacity trade, made here rather than discovered in
the shrink order.

### D-5 — #830: `?since=` is a row-delta parameter, and two shapes of read cannot carry it (recommended)

The agent reports that `?since=` is missing from the reads its scheduled run
polls — "valuation, allocation, targets, the notes reads". The 2026-09-19
triage verified the parameter exists on `GET /api/v1/securities` and
`GET /api/v1/transactions` and nowhere else. Read against the mechanism, the
complaint splits into three, not one:

1. **Row collections** — rows with an `updated_at` the cut compares against.
   `SinceParam` applies unchanged: same strictly-after semantics, same `as_of`
   echo, same stated deletion gap. **This is what #830 builds**, on the reads a
   scheduled run actually polls: the targets reads, the per-security notes read
   and the per-security events read, and the remaining row collections the
   close-out's family sentence names.
2. **Derived projections** — valuation, allocation, performance, risk. These
   have no rows and therefore no `updated_at`; "has the valuation changed since
   I last read it" is a **basis-version** question, and ADR-0039's
   `DataVersion.portfolio_basis/1` already answers it internally. Exposing it is
   a conditional-read mechanism — an ETag or a basis token — and that is a
   decision with its own argument, not this issue's build. **Named and filed by
   Lane Z** (Scope Lock).
3. **Time-derived queues** — `/notes/unreviewed`, `/notes/expiring`,
   `/notes/uncorroborated`, `/events/upcoming`, `/events/stale`,
   `/events/unconfirmed`. Membership changes **because time passes**, with no
   row changing. A `?since=` here would silently drop exactly the rows a poller
   needs: the note that became unreviewed overnight without being touched.
   **Deliberately absent, and the close-out says so** — the same shape as Sprint
   13's `days=` absence from `/events/unconfirmed`, which is the surface check
   working as designed.

The distinction is the finding: `?since=` was never one parameter short of
complete, it is one mechanism applied to the reads it fits. Stating which reads
those are — and which two shapes it cannot fit, with the reason — is what turns
a fourth-edition complaint into a closed surface.

### D-6 — B3.6 stays shut this sprint, and its trigger is named (recommended)

Sprint 13's triage recorded the 2026-09-19 round's prose-rule drift as "a second
independent observation… the strongest argument yet for opening B3.6 — recorded
as evidence for Sprint 14's planning, not opened here". This is that planning
round and the verdict is **not yet**, for reasons that are about order rather
than merit:

- **E22 is open and this sprint closes it.** Opening a new object family while
  an epic is half-built is the pattern this project's retrospectives keep
  recording, and the last three sprints each paid for it.
- **A rules engine reads the metrics A1 ships.** FR-43's caps and floors are
  predicates over allocation drift and the risk figures; writing the ADR *after*
  the portfolio payload exists lets it name real fields, real refusal states and
  real `required` thresholds instead of anticipated ones. Written now it would
  be a spec ahead of its inputs, which is the "the spec has been ahead of the
  build for four sprints" finding Sprint 12 was cut to fix.
- **The cost is tokens, not risk.** This project's own ordering — adopted from
  the agent in Sprint 13's D-7 — is that a missing date hides risk and a missing
  figure costs tokens. Prose drift is the second kind. ADR-0048 was signed
  immediately because a missed reporting date is the first.

**The trigger, so this is a decision and not a deferral:** B3.6's gate opens on
the **Sprint 15 planning PR**, with ADR-0047's portfolio payload in hand, unless
a third drift observation arrives first — in which case it opens on the next
planning round whenever that is. The ADR has two things to decide and the plan
records them now so the gate is cheap to write: **what a rule is** (a predicate
over a named metric with its own computation basis, stored as an object rather
than as prose) and **what happens to a rule's history** when it is edited —
retention being the half that ADR-0044's append-only log answers one way and
ADR-0048's journaled table answers the other, which is the argument the record
will have to make rather than inherit.

**To flip this by comment:** a comment naming B3.6 opens the gate on this PR,
and the shrink order below takes A4 and Lane C to make room — a rules engine is
the size of Lane A.

### D-7 — "Required Local Checks" names the gates CI runs (recommended, amended on this PR)

Sprint 13's process finding 2 and its version report both record the same thing,
and both deliberately stopped short of fixing it: `AGENTS.md` → "Required Local
Checks" lists **six** commands and CI's `quality` job runs more that none of
them cover. One round of Sprint 13 went red on exactly two of the missing ones,
and the fix commit (`b6f521b`) should never have existed. This is the third
batch to run the missing gates out of habit rather than instruction.

**The count in that finding is low.** It names four —
`mix compile --warnings-as-errors`, `mix credo --strict`, `mix sobelow` and
`mix dialyzer`. Read against `.github/workflows/ci.yml` on `dabcd27` the
`quality` job runs **eight** the list omits: those four plus
`mix deps.unlock --check-unused`, `mix hex.audit`, `mix deps.audit` and
`npm audit --audit-level=high --prefix mcp-server`. Three of the four the
finding missed are the supply-chain gates, which is the half of the job a local
run is least likely to reproduce by habit — so the undercount was in the
direction that made the gap look smaller.

The lane did not edit the list because a documented process rule is not a
maintenance-lane edit, and the version report says so explicitly: it is "a
decision for the close-out or an owner call". **A planning PR whose merge is the
owner's signature is that call** — the same mechanism by which the Sprint 13
planning PR amended AR-3 in `architecture.md` rather than letting a requirement
go on disagreeing with the code.

**Amended on this PR**, in `AGENTS.md` and in `CONTRIBUTING.md` — both carry the
list, and a list that is right in one document and wrong in the other is the
defect with an extra step:

```bash
mix format
mix compile --force --warnings-as-errors
mix test
mix coveralls
mix credo --strict
mix sobelow --skip --exit
mix dialyzer --format short
mix deps.unlock --check-unused
mix hex.audit
mix deps.audit
pre-commit run --all-files
npm test --prefix mcp-server
npm run build --prefix mcp-server
npm audit --audit-level=high --prefix mcp-server
```

Two notes ride the list rather than a fourteenth command. `mix dialyzer` builds
a PLT on first run and is slow once, not every time. And `mix hex.audit` and
`mix deps.audit` read a live advisory database, so a green local run does not
stay green — which is the thing worth knowing before reading a red check as a
regression (Sprint 13 process finding 3).

**If the owner would rather the list stayed short**, removing this commit before
the merge is the whole of the rejection, and the finding goes back to being
recorded once per sprint.

### D-8 — the closing act's conditions (standing, with one addition)

The #706 conditions stand unchanged: DE, one full pass at 390 px, light and
dark, on `priv/demo/finding_surfaces_seed.exs`, screenshots in a PR **comment**
rather than the PR body — and in **Markdown image syntax**, because Sprint 13's
first attempt used HTML `<img>` and the API mangled the URLs into code spans.
Sprint 12's ordering fix is standing too: **the patch-coverage listing is read
from the last pre-promotion CI run**, which produced its first negative result
in Sprint 13 and is worth keeping for that reason rather than despite it.

Four roles as in Sprint 13 — correctness hunter, edge-case hunter, a UAT persona
walkthrough on seeded synthetic data, and the design critic against the living
spec (ADR-0038), the last being mandatory here because Lane C and A4 are both
user-visible.

**The addition, from Sprint 13's process finding 4:** *a subagent report is
evidence, not a verdict.* Every role is briefed to reproduce before it surfaces
a finding, and the two findings that mattered most last sprint arrived with
mutation proofs rather than readings. **The risk-tier passes carry that
explicitly**: Lane A's identities and Lane B3's projection-semantics invariant
are each mutation-verified — the assertion is shown red against a deliberately
broken implementation before it is trusted green — because Sprint 13 found two
of ADR-0047's own identities passing while unpinned.

### D-9 — the tags, now four outstanding (standing)

This sprint prepares **`0.14.0`**. Recorded plainly because the close-out
mechanism cannot fix it: **`0.11.0`, `0.12.0` and `0.13.0` were prepared by
their close-outs and none is pushed.** The latest published release is `0.10.0`
of 2026-09-07, so **three rollback points are missing for self-hosted
instances** and the gap is now four sprints wide. The tag is an owner action by
the 2026-09-07 decision and the agent's credential cannot push one; the Sprint
14 close-out restates all four commands in one block rather than adding a fifth
place to look. Four sprints of a refused push is the process working as decided,
and a growing list of unpushed rollback points is a fact about the published
releases either way.

## Sequencing

```text
branch opens on main @ dabcd27 ──▶ Lane Z files the Lane A issues
design pass ─ FIRST, on D-2's picked option: variant boards for the Risk
              surface, recommendation as default pick, anatomy into DESIGN.md.
              A4 does not open before it.
Lane A1 ──── the portfolio figures over the TTWROR chain, the risk read, the
             MCP tool; I1, I3, I4, I7; A3 rides it
Lane A2 ──── #838's `required` on both payloads, one contract bump, after A1
Lane B ───── in parallel: controllers and changesets, no overlap with A
Lane C ───── in parallel: app.css and securities_live.ex, no overlap with A
Lane D ───── #830 after D-5's scope, #831 any time
Lane A4 ──── the Risk surface, after the design pass and after A1's payload
Lane A5 ──── #825, independent, any time after A1
Lane M ───── at lane time; the version report before the closing act
closing act ─ D-8's conditions, the risk-tier passes on A1 and B3, then
             promotion
```

## Shrink order (cut from the bottom, name the cut in the briefing)

Two cuts are already spent at planning time: **#835's convergence** (D-4) and
**B3.6's gate** (D-6). What is left to give, in order:

1. **#842** (the `+N` overflow chip) → Sprint 15. One chip on one cell.
2. **#844** (the ADR front matter) → Sprint 15. It has been broken since at
   least 2026-09-19 and one more sprint changes nothing, now that it is filed
   rather than remembered.
3. **#830's build half** → Sprint 15. **The family sentence stays** either way:
   naming which reads carry `?since=` and which two shapes cannot is the
   surface check, and it costs a paragraph in the close-out rather than a
   commit.
4. **A4** (the Risk surface) → Sprint 15, with the coverage deadline recorded
   in the close-out. Last, for the same reason Sprint 13 put its human view
   last: it costs one screen, it discharges ADR-0047 §9's same-batch clause, and
   recording the deadline is the rule working rather than the rule being waived.

**Lanes A1, A2, A3, A5, B and the rest of C do not shrink.** A1, A2, A3 and A5
are E22's close and the epic has already waited a sprint for them. Lane B is
three defects that answer 500 where the contract promises 4xx — an error
contract that is wrong is worse than a feature that is missing, because a caller
cannot tell the difference between a bad request and a broken server. #833,
#834, #836 and #837 are the accessibility floor and one CSS rule; if they do not
fit, nothing does.

## What is deliberately not in this sprint

- **FR-43 / policy rules (B3.6)** — D-6, with the trigger and the ADR's two
  open questions named so the next gate is cheap to write. The rebalancing
  digest (B3.5) depends on it and stays shut behind it.
- **FR-41 (contribution) and FR-42 (exposure decomposition)** — level (b),
  ungated, unfiled, each needing its own argument. FR-42 in particular has a
  boundary to draw against partial-weight advanced classifications, which is a
  decision and not a story. Unchanged from Sprint 13's list.
- **#835's convergence** — decided here (D-4), filed with the treatment named,
  built later.
- **The derived-read delta mechanism** — D-5's second shape. A conditional read
  over a basis version is its own decision; filed by Lane Z, not built.
- **Moving `security_metrics` off lifetime `:none`** — A5 lands the seam that
  makes the move possible; the move itself is ADR-0039 C3's measurement
  question and stays unanswered by design.
- **Anything with a verdict in it.** No signal, no rule, no rating, no alert —
  ADR-0047 §7, pinned by A3's extended meta-test across both payloads. A rule
  over a metric is FR-43 and stays gated at B3.6; scoring one is level (c)
  behind FR-46 at B4.2; replaying one is level (d) and is a boundary rather
  than a backlog item.
- **Everything else the 2026-09-19 agent round asks for**, each for a reason in
  that triage: a collector or signal feed (**B3.3**), prediction calibration
  (FR-47, needs FR-46 at **B4.2**), threshold alarms (FR-43's output at B3.6,
  delivery at **B3.7**), and backtesting (ladder level **(d)**).
- **#328 / #608 (lifecycle merges), #354 (backup/restore), #333, #332, #330,
  #573, #567, #395, #481, #314** — unchanged from Sprint 13's list. #314's
  ratchet rides this batch as it rides every batch.

## What "done" means for this sprint

1. **E22 closes.** A1's four figures ship on `GET /api/v1/portfolios/:portfolio_id/risk`
   and `portfolixir.portfolios.risk`, additively, over the TTWROR chain's
   flow-adjusted factors; **I1, I3, I4 and I7 are pinned by tests**, with I3's
   scale clause asserted on the rendered string rather than with
   `Decimal.equal?/2`. #838 and #825 ship. Tracker **#821 is closed by hand**
   with the evidence, and the Tracker Index line and `sprint-status.yaml` say
   done.
2. **`required` sits on every metric in both payloads and both states**, `window`
   is `null` where the metric is defined over a count of closes, and the
   contract takes **one** bump covering both surfaces.
3. **A4 renders**, in the variant the design pass picks, with `DESIGN.md`
   naming its anatomy — **or** the close-out names the shrink and the coverage
   deadline it inherits, which is Sprint 15 by the rule's own terms.
4. **No JSON API read answers 500 for an out-of-range id** (#840), an over-long
   note `source_url` answers 422 (#841), and the "is it held?" predicate is one
   predicate or three honest docstrings (#839), with the projection-semantics
   invariant mutation-verified.
5. **Lane C's five conformance items ship**, D-3's and D-4's picks are written
   into `DESIGN.md`, and #844's effect on the published site is established
   before it is fixed.
6. **#830 ships on the row-collection reads**, and the close-out's surface-check
   sentence **names every member of the family** — those that carry `?since=`,
   the derived projections that need a different mechanism, and the time-derived
   queues that must not carry it, each with its reason. **#831's sentence is in
   the tool descriptions** of the reads the guarantee protects.
7. **Lane M's report exists**, written before the closing act; #727's triggers
   are re-checked and the result recorded either way; the Node LTS promotion is
   applied if it landed and declined with its reason if it did not.
8. **The closing act ran under D-8's conditions**, the patch-coverage listing
   was read **before** promotion, and both risk-tier passes — A1's identities
   and B3's projection semantics — are in the reviewer briefing with their
   mutation proofs.
9. **The contract-version read reports the extended risk payload**, and the
   answers this plan owes the agent (D-5's three shapes, #831's guarantee) have
   gone back to it.
10. **The `0.14.0` command is in the close-out**, together with the still-unpushed
    `0.11.0`, `0.12.0` and `0.13.0`.
