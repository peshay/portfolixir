# PRD Addendum — Portfolixir (2026-06-12)

Depth that informs downstream documents (architecture, UX, epics) but does not
belong in the PRD narrative itself. Personal details were deliberately
redacted on 2026-06-13 (public repo); what remains is the product-shaping
essence.

## Origin story (condensed, anonymized)

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

## Investor profile (persona depth, anonymized)

- Strategy until retirement: **maximum risk performance** with stocks +
  Bitcoin — deliberately high-risk, consciously chosen. Long-horizon goal is
  early-retirement readiness. (An earlier draft said "risk-adjusted" — that
  inverted the intent; corrected per reconciliation review. Aggressive
  allocation is a feature, not a bug to correct.)
- German pension context matters: gesetzliche Rentenpunkte, private
  Zusatzversicherungen, payout-option questions (lump sum vs. monthly, from
  which age, marginal value of additional contributions).

## Tech-stack motivation (for architecture context)

- Elixir was a deliberate greenfield choice; the stack is judged right
  because: always-on self-hosted BEAM app + LLM/MCP attachment.
- The project is deliberately **bleeding-edge AI-agentic engineering** — the
  owner does not read the code himself, so mechanical guards (gates,
  invariant tests, scope locks) are load-bearing, not optional. Calling it a
  "playground" understates the stakes; modern AI-driven development methods
  are part of the product's point, with production-grade discipline.

## Future visions (explicitly Zukunftsmusik, not roadmap)

- Algotrading on top of the data backbone.
- "Everything countable as wealth or passive income" managed in one place
  (insurance, real estate, passive income streams — parking lot #340).
- iOS/macOS app; possibly cloud-hosted service IF genuine outside interest
  emerges. No commitment.

## Tip backtesting (feeds #332 what-if simulator)

- Wanted: "if I had blindly followed tip X (e.g. from a stock-tips podcast)
  at date Y, where would I be today?" — blind-follow simulation as a what-if
  scenario class with real quote history, plus an aggregate per-source
  verdict (hit rate, P/L distribution) over all tips of a source.
