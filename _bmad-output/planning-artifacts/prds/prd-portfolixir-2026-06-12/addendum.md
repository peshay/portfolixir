# PRD Addendum — Portfolixir (2026-06-12, revised 2026-08-12)

Depth that informs downstream documents (architecture, UX, epics) but does not
belong in the PRD narrative itself.

**Privacy scope (owner decision, 2026-07-25).** This is a public repo. The
operator is named openly and named integration targets stay — that is a
deliberate, recorded choice. What stays out, permanently: **concrete financial
values** of any kind (balances, net worth, invested capital, position sizes,
performance figures, credit lines) and **anything about the operator's family
or household**. Illustrative amounts in journeys are hypothetical and carry no
information about real holdings.

## Origin story (condensed)

- Started as a Portfolio Performance (PP) user driven by one question: **"Is
  my investing actually beating the alternative?"** — e.g. vs. 2% fixed
  deposit. Opportunity-cost benchmarking is the founding job.
- PP gap that triggered the build: classifications exist, but **no target
  weights (SOLL)** and no drift-based guidance. Wanted: "X% growth, Y% energy
  transition…" and answers to *"new cash arrives — where does it go? cash
  needed — where does it come from?"* (rebalancing as guidance, not orders).
- Pre-Portfolixir workflow (the pain being replaced): a manual spreadsheet as
  source of truth → broker PDFs imported into PP → manual reconciliation →
  CSV export → paste into an LLM chat. LLM consultation about SOLL weights
  and cash allocation was a recurring habit, which is why FR-12 guidance must
  be LLM-legible. Portfolixir unifies this.
- The operator runs a self-hosted LLM agent with several MCP integrations;
  the always-on self-hosted app is the data backbone that agent attaches to.

## Investor profile (persona depth)

- Strategy until retirement: **maximum risk performance** with stocks +
  Bitcoin — deliberately high-risk, consciously chosen. Long-horizon goal is
  early-retirement readiness. (An earlier draft said "risk-adjusted" — that
  inverted the intent; corrected per reconciliation review. Aggressive
  allocation is a feature, not a bug to correct.)
- German pension context matters: gesetzliche Rentenpunkte, private
  Zusatzversicherungen, payout-option questions (lump sum vs. monthly, from
  which age, marginal value of additional contributions). The PRD specifies
  FR-24/FR-25 around **operator-maintained, effective-dated parameter
  tables**, because these parameters are revalued annually and a derived
  number would be confidently wrong (ADR-0031).

## Tech-stack motivation (for architecture context)

- Elixir was a deliberate greenfield choice; the stack is judged right
  because: always-on self-hosted BEAM app + LLM/MCP attachment.
- The project is deliberately **bleeding-edge AI-agentic engineering** — the
  owner does not read the code himself, so mechanical guards (gates,
  invariant tests, scope locks) are load-bearing, not optional. Calling it a
  "playground" understates the stakes; modern AI-driven development methods
  are part of the product's point.
- **Precision on the quality claim:** what the evidence supports is
  *engineering discipline* — Decimal-exact math, invariant meta-tests, CI
  gates, reviewed ADRs. It is **not** production readiness, which AGENTS.md
  forbids claiming and which the unauthenticated web UI (NFR-4, OQ-8) and the
  missing release/upgrade story (OQ-10) would not support anyway.

## Future visions (explicitly Zukunftsmusik, not roadmap)

- **Algotrading on top of the data backbone — forbidden until a dedicated
  scope decision.** AGENTS.md's no-trading/no-order rules stand unamended;
  this note travels with the item so the line cannot be quoted out of context
  as a roadmap entry.
- "Everything countable as wealth or passive income" managed in one place
  (insurance, real estate, passive income streams — parking lot #340).
- iOS/macOS app; possibly cloud-hosted service IF genuine outside interest
  emerges. No commitment.

## Tip backtesting (feeds #332 what-if simulator)

- Wanted: "if I had blindly followed tip X (e.g. from a stock-tips podcast)
  at date Y, where would I be today?" — blind-follow simulation as a what-if
  scenario class with real quote history, plus an aggregate per-source
  verdict (hit rate, P/L distribution) over all tips of a source.
- **Unfunded dependency:** this needs price history for securities the
  operator has never held — a breadth/depth/licence problem that ADR-0005's
  provider split was not designed for. Tracked as OQ-11.

## Identity gate B3.1 — what this run left for downstream documents (2026-08-12)

Source: the product brief of 2026-08-12 and its addendum. That addendum is the
fuller handoff and is not restated here; this section records only what the
PRD update itself produced and could not carry.

### For the derived-value ADR (gate B3.2)

FR-1 now permits materialized derived values and binds four properties to
them. The ADR owes three things the PRD deliberately does not decide:

- **Which** values are materialized, and an explicit no to the rest.
  "Everything" is not an answer, and an unbounded layer would recreate the
  staleness problem it was built to remove.
- Its relationship to **ADR-0032**, which defines today's memo as volatile —
  never surviving a restart, never a source of truth. A durable layer reverses
  that, so the new ADR supersedes or amends it rather than sitting beside it.
  Two of FR-1's four properties are inherited from ADR-0032, not invented: the
  data-version mechanism and the as-of labelling rule.
- Its relationship to **ADR-0035**, the adjacent precedent that deliberately
  *removed* redundant computation instead of caching it, with a measured
  result (1,105 ms → 265 ms, 2,614 → 115 queries, output identical). The ADR
  must say why that choice does not extend to this case. An author who starts
  from FR-1 alone would otherwise rediscover or contradict an accepted
  decision.

The Sprint 5 value-slot vocabulary (pending / settling / final /
not-computable) is the UI half of FR-1's freshness property and already
exists; the payload half does not.

### Two pre-existing inconsistencies found while editing, not fixed here

Both are outside this gate's scope and neither blocks it. Recorded rather than
silently corrected, per the rule that code and documents disagreeing is a
finding.

- **`project-context.md` states "LiveView 0.20.x — NOT 1.x"** and warns that
  1.0-only patterns will not compile. The installed version is **1.2.8** (seen
  in the test run of this batch). The file's own instruction is to flag such a
  disagreement rather than pick a side. It misleads any agent that reads it
  before writing a LiveView.
- **`epics.md`'s Requirements Inventory carries a pre-2026-07-25 copy of
  FR-1..FR-29** — for instance FR-4 still describes portfolios as partitioning
  the wealth space, which ADR-0024 superseded. This run aligned FR-1 (because
  the gate required it) and added the missing NFR-9, but did not reconcile the
  rest. The PRD's own registry note already says `epics.md` wins on conflict,
  which makes this drift more expensive than it looks.

### A tension in the README rewrite, resolved and worth confirming

`project-context.md` carries the owner's microcopy rule of 2026-07-23: write UI
**and doc** text impersonally, avoid addressing the reader. The 2026-08-12
brief prescribes the README tone as *"your holdings, your agent, your
machine"*, which is direct address. The later and more specific instruction was
followed for that one phrase, and the rest of the section stays impersonal. If
the owner reads the phrase as a rule violation rather than a deliberate
exception, the fix is one sentence.
