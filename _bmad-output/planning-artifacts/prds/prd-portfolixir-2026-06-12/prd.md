---
title: Portfolixir PRD
status: final
created: 2026-06-12
updated: 2026-06-12
---

# Portfolixir PRD

## 1. Vision

**Portfolixir is the self-hosted wealth data backbone for an LLM agent — and
the human behind it.** It keeps every financial instrument complete,
consistent, and auditable in one place, and serves **precomputed,
decision-ready analytics** so that an external LLM agent (any MCP
client) can manage and advise on the portfolio without doing its own
arithmetic.

The founding question the product must always answer:

> **"Is my investing actually worth it — compared to the alternative?"**

Every flagship capability is this question in a different costume: performance
vs. a fixed-interest benchmark, target-vs-actual allocation drift, "where does
new cash go / where does needed cash come from", podcast-tip backtesting, and
ultimately "when can I retire early, and on how much?".

The unifying job behind all of it: **offload the operator's research burden.**
Pension rules, payout options, tip evaluation, rebalancing math — the system
carries the analysis so the operator decides instead of researching. And the
output must serve two consumers at once: machine-consumable for agents,
**understandable for the human** — numbers always come with enough
representation (visualization, method, context) that the operator can follow
the reasoning, not just receive verdicts.

**Cornerstone principle:** Portfolixir never calls an LLM. LLMs call
Portfolixir — to read precomputed analytics and to maintain data. Intelligence
stays external and replaceable; the product is data plus deterministic
computation.

### Positioning (research snapshot, 2026-06)

As of the June 2026 landscape research, no tool was found that combines
Portfolixir's four differentiators: Portfolio Performance import parity,
MCP-first precomputed analytics (third-party MCP wrappers exist; no product
ships this as its core contract), German retirement modeling (no open-source
coverage found), and what-if/backtest scenarios. Target-weight rebalancing
alone is the weakest moat — PP itself covers it — so its value here comes from
guidance quality and MCP exposure. The death of budgeting-hybrid Maybe Finance
(2025) validates staying investment-focused.

### Stakes and quality bar

Solo-first, in sequence: built for one operator now, at a quality grade that
lets others adopt it (community potential decides itself later), keeping the
option of a business open without forcing it. Development is almost entirely
AI-agentic and the owner does not read code — **mechanical guards (gates,
invariant tests, scope locks) are load-bearing product requirements, not
process garnish.**

## 2. Users

- **The operator-investor ("Alex" — fictional persona name).** Self-hosts
  the app; invests with a deliberate **maximum risk performance** strategy
  (stocks and Bitcoin) over a long horizon and plans retirement under German
  pension rules. Maintains a second household portfolio as a separate,
  filtered scope in the same instance.
- **The LLM agent (first-class user).** An external agent (any MCP client)
  connected via MCP. Reads analytics, maintains records, answers the
  operator's questions. Its needs drive API/MCP design: precomputed values,
  self-describing responses, no forced client-side math.
- **Future self-hosters (quality bar, not a commitment).** Each runs their own
  instance; single-user tenancy per instance.

## 3. User Journeys

**UJ-1 — Morning briefing (agent journey).** Alex asks his MCP agent:
"How is the depot doing, and where should the new 5k in cash go?" The
agent calls MCP tools and receives precomputed values: current valuation, cash
quote, TTWROR vs. benchmark, SOLL/IST drift table. It answers with the
top-drift categories and concrete candidates — without computing a single
number itself. Total round trip: seconds, zero exports.

**UJ-2 — Data maintenance without spreadsheets.** A comdirect statement
arrives. Today: Alex imports the PP export (later: read-only sync pulls it).
The import previews what would be created, applies idempotently, flags
anything inconsistent (currency mismatch, unknown securities). The manual
spreadsheet and PP reconciliation stay retired — safely, because the system itself
provides backup and full export (FR-29).

**UJ-3 — Cash decision, both directions.** Alex needs €10k liquid. The agent
reads the drift table inverted: which overweight categories can release cash
with the least strategic damage? Same data, opposite sign.

**UJ-4 — The retirement session.** Alex sits down with his agent: "If I stop
early, what do I live on?" The system holds Rentenpunkte, private pension
policies with their payout options, and the depot trajectory; the projection
shows wealth-at-age and sustainable withdrawal under chosen scenario
parameters. [ASSUMPTION] Deterministic scenario projection first (parameterized
growth/inflation paths); Monte Carlo is a later refinement.

**UJ-5 — The podcast test.** A stock-tips podcast recommended a stock three
months ago. Alex asks: "If I had blindly bought €1k of every tip since January — where
would I be?" The what-if engine simulates virtual trades against real quote
history as an overlay timeline, never touching the real ledger — and can
aggregate a verdict per tip source over time.

**UJ-6 — The family view.** Alex switches to the second household portfolio; every
view (holdings, allocation, performance) filters to that scope. PP-style
filtered views, one instance.

## 4. Scope and Phasing

Phases are sequential priorities, not strict gates; each phase ships in
story-sized increments per the roadmap (#321).

**Phase 1 — Correctness & data completeness (now).**
Invariant hardening (#343 currency consistency, #344 rounding ADR, #346–#348
gate suites, #350 Unicode gate), write audit journal (FR-28), backup & PP
export (FR-29), PP XML full import (#333 — **scope gate:** XML intake is on
the AGENTS.md forbidden list; requires the ADR + AGENTS.md amendment before
implementation), account lifecycle tools (#327 portfolio switcher, #328
merge/rename/delete), import data quality (#326 logos).

**Phase 2 — LLM-first consumption.**
MCP/API analytics audit and exposure (#349), IRR (#316), income report (#331),
classification view (#334), allocation mechanics (#318, #329, #335). Every
analytic the app computes becomes MCP-consumable with method, basis date, and
currency stated.

**Phase 3 — Read-only sync.**
Operator-stated **must-have** — the scope gate below governs *when and how*,
not *whether*. Sources: comdirect REST API (depot, official API,
OAuth2+PhotoTAN), bunq API (cash accounts), bitcoin.de (trade history,
conditional on the OQ-4 spike), watch-only wallet tracking for offline BTC
(xpub/address — keys never touch the system). **Scope gate:** AGENTS.md
currently forbids broker/bank sync; entering Phase 3 requires an ADR plus
AGENTS.md amendment limited to read-only data acquisition. Aggregators are
explicitly avoided (free tiers collapsing, 2025) in favor of direct official
APIs. Unattended-sync feasibility per provider is open (OQ-6 — PhotoTAN may
require interactive sessions).

**Phase 4 — Product-type depth.**
Bonds with native semantics (#330), corporate actions (#338), German pension
modeling: gesetzliche Rentenpunkte, private policies with payout options
(lump-sum vs. monthly, age brackets), insurance as wealth components. Each
modeling FR here is preceded by its own discovery story that fixes acceptance
criteria before implementation.

**Phase 5 — Planning & simulation.**
Early-retirement projection (wealth-at-age, sustainable withdrawal),
benchmark comparison ("vs. 2% fixed deposit") as a first-class analytic,
what-if simulator incl. blind-follow backtesting (#332).

**Deprioritized / parked:** Dashboard v2 (#337 — explicitly after data/LLM
tracks), algotrading (vision only; forbidden until a dedicated scope decision),
iOS/macOS apps, cloud hosting, multi-user (#340).

## 5. Functional Requirements

Capabilities, not implementation. IDs are stable and globally numbered; new
requirements append, never renumber. Where a GitHub issue exists it is
referenced (about two-thirds of FRs today); **the PRD is authoritative —
issues track implementation.**

### A. Ledger & data integrity

- **FR-1** All financial state derives from the transaction ledger (13 PP
  kinds + balance adjustments); holdings, balances, and performance are
  projections, never stored facts.
- **FR-2** The system rejects inconsistent records: currency mismatches
  (#343), invalid kinds, signed amounts where magnitudes are required.
- **FR-3** A written rounding policy governs every Decimal operation (#344);
  all money math is Decimal-exact end to end.
- **FR-4** Portfolios partition the wealth space; every view and every
  analytic can be scoped to one portfolio (filtered views, UJ-6). Depots and
  cash accounts can be moved between portfolios (#327) and merged/renamed/
  deleted with transaction reassignment (#328).
- **FR-28** Every write to financial data — via UI, API, or MCP — is recorded
  in an append-only audit journal: actor (UI session vs. API/MCP token),
  timestamp, operation, before/after values. The journal is queryable via API
  and MCP, so a hallucinated or erroneous agent edit is always detectable and
  attributable. Deletions remain traceable through the journal.

### B. Import & reconciliation

- **FR-5** Portfolio Performance exports import losslessly: CSV/JSON v1
  (shipped) and XML with classifications, quote history, and master data
  (#333). **Scope gate:** XML intake requires the AGENTS.md amendment + ADR
  (it is on the current forbidden list; CSV/JSON v1 is the standing
  exception).
- **FR-6** Imports are previewed (what will be created), idempotent
  (content-hash; re-import is a no-op), and atomic.
- **FR-7** Import gaps are surfaced, not silently defaulted: unclassified
  securities, missing logos (#326), unknown record kinds.
- **FR-29** The system provides a documented backup/restore procedure and a
  **full data export in PP-compatible format** (roundtrip: Portfolixir → PP →
  Portfolixir), available via UI and MCP. Retiring external copies (Numbers,
  PP) is only safe because this exists; it ships before or with the workflows
  it replaces.

### C. Analytics engine

- **FR-8** Performance: TTWROR (shipped) and IRR/money-weighted (#316) per
  portfolio, depot, and security, over selectable periods.
- **FR-9** Benchmark comparison: any performance series can be compared
  against a configurable alternative (fixed-rate baseline such as "2%
  Tagesgeld", or an index/security series) — the founding "worth it?"
  question as a first-class analytic. The comparison supports an
  after-cost / after-tax dimension: trading fees and German capital-gains
  taxes (Abgeltungsteuer, Vorabpauschale, Teilfreistellung) can be included,
  so the answer is not flattered by pre-cost figures (tax-model depth:
  OQ-9). Index comparison scenarios include "bought once and held" and "as
  a savings plan". [ASSUMPTION] Fixed-rate baseline first; index/security-
  series benchmarks — and with them the index scenarios — second (OQ-3).
- **FR-10** Income analytics: received dividends and interest, gross/net, per
  year and position (#331).
- **FR-11** Allocation: classification trees with target weights, SOLL/IST
  drift per category (shipped), target-consistency hints (#318), cash as part
  of the 100% basis (#335), per-security exclusion flags (#329).
- **FR-12** Rebalancing guidance, both directions: ranked "where new cash
  goes" and "where needed cash comes from". Primary ranking criterion: drift
  magnitude against target weights; further criteria (e.g. tax awareness,
  OQ-5) extend the ranking later. Guidance only — the system never places,
  prepares, or suggests executable orders. (AGENTS.md "no rebalance action"
  stays untouched; the amendment for this FR clarifies guidance vs. action.)

### D. LLM/MCP surface

- **FR-13** Every analytic the app computes is exposed via JSON API and MCP
  (#349); responses are self-describing: method, as-of date, currency, and
  conversion basis stated; financial values serialized as strings.
- **FR-14** MCP tools cover data maintenance (create/update records) as well
  as reads — an LLM can fully replace manual UI data entry, within the same
  validation rules, with every write captured by the audit journal (FR-28).
- **FR-15** Tool descriptions are written for LLM tool-choice: when to use
  which tool, with paging/limits to keep responses small.
- **FR-16** The MCP companion remains a thin wrapper over the public JSON API
  (ADR-0002); parity between API and MCP is reviewed every PR.

### E. Read-only sync (Phase 3, behind scope ADR)

- **FR-17** comdirect: depot positions and transactions via the official REST
  API; reconciliation against the existing ledger with preview before apply.
- **FR-18** bunq: account balances and transactions for cash accounts.
- **FR-19** bitcoin.de: executed trades into the ledger — conditional on the
  OQ-4 technical spike (API capabilities, rate limits, history depth).
- **FR-20** Watch-only crypto: balance tracking for offline-wallet addresses/
  xpubs; private keys are out of scope by design, permanently.
- **FR-21** Sync is read-only **as implemented and audited in this codebase**;
  bank credentials themselves may be technically write-capable, so the
  deployment docs state the residual risk plainly. Credentials are stored
  locally and encrypted; key-management limits of a single-box deployment are
  documented rather than overpromised; provider API scopes are minimized
  where the provider supports it. Every synced record passes the same
  validation and idempotency rules as imports (FR-2, FR-6) and is captured by
  the audit journal (FR-28).

### F. Product-type modeling (Phase 4 — each FR preceded by a discovery story)

- **FR-22** Product types carry their own data, their own math, **and their
  own representations**: bonds with coupon, maturity, face value,
  percent-of-nominal valuation and yield metrics (#330) are the first case of
  the general principle — a stock, a bond, a pension policy, and a crypto
  position do not render alike.
- **FR-23** Corporate actions as guided, manual wizards: split, rename/ISIN
  change, merger/spin-off (#338), keeping history reproducible.
- **FR-24** German statutory pension: Rentenpunkte as a tracked asset with
  projected payout ("what does one more point buy me?").
- **FR-25** Private pension/insurance policies: payout options modeled
  (lump-sum vs. monthly, eligibility ages), comparable against depot
  withdrawal.

### G. Planning & simulation (Phase 5)

- **FR-26** Retirement projection: wealth-at-age and sustainable-withdrawal
  curves from current holdings, savings rate, and pension components under
  named scenario parameter sets (discovery story fixes the acceptance
  criteria backing Success Metric 3).
- **FR-27** What-if simulator: virtual trade scenarios as overlay timelines
  against real quote history — including "blind-follow" series (buy X amount
  on each tip date) and an aggregate per-source verdict ("are this podcast's
  tips any good?") — strictly separated from the real ledger (#332).

## 6. Non-Functional Requirements

- **NFR-1 Correctness over features:** Decimal-only persistence, exact-value
  tests, invariant meta-tests, and the quality-gate roadmap
  (project-context.md) are release-blocking. Silent financial corruption is
  the defining failure class.
- **NFR-2 Auditability:** every number is reproducible from immutable inputs;
  editing is allowed, hidden state is not — enforced mechanically by the
  audit journal (FR-28).
- **NFR-3 AI-agentic development guards:** CI gates per project-context.md,
  including invisible-Unicode/Trojan-Source rejection (#350); scope changes
  only via ADR + AGENTS.md amendment, never silent.
- **NFR-4 Security boundaries:** no in-app LLM calls; no trading, payment, or
  order functionality; read-only sync only (Phase 3+); API/MCP access via
  local bearer tokens; no secrets in source. **The web UI itself is
  unauthenticated by design** — an instance must run on a trusted network or
  behind reverse-proxy authentication; the deployment docs state this
  prominently (optional built-in auth: OQ-8).
- **NFR-5 Self-hosted operations:** docker-compose deployment, PostgreSQL as
  the only store, runs always-on on the operator's hardware; MCP companion
  installable separately.
- **NFR-6 Single-user tenancy:** one instance, one operator; portfolio-scoped
  filtered views instead of multi-user.
- **NFR-7 Localization:** UI localized (de/en via gettext); repository
  artifacts in English.
- **NFR-8 Performance:** interactive views and MCP analytics respond within
  p95 < 2 s on commodity home-server hardware at realistic scale (hundreds of
  securities, tens of thousands of transactions). Correctness always beats
  speed.

## 7. Success Metrics (12 months)

1. **Spreadsheet retirement:** the manual spreadsheet and PP reconciliation
   fully replaced — zero manual cross-checking workflows remain. (Gated on
   FR-29: backup/export ships first.)
2. **Agent autonomy:** the MCP agent answers "where does new cash go?",
   "is the depot beating the baseline?", and "what did my income look like?"
   via MCP without any export, file handoff, or client-side computation.
3. **Retirement credibility:** a first early-retirement projection runs on
   real pension data (acceptance defined by the FR-26 discovery story).

**Counter-metrics (what must not degrade while chasing the above):**

- Financial-correctness incidents (wrong number reaching a view/API): target
  zero; every occurrence becomes an invariant test.
- Reconciliation drift between synced data and official statements: surfaced,
  never silently absorbed.
- Gate health: **gates are never weakened to ship a feature** — grandfathered
  baselines (Credo thresholds, documented Sobelow ignores) only ratchet
  downward, per project-context.md.

## 8. Open Questions

- **OQ-1** Phase 3 + FR-5(XML) + FR-12 scope ADR: exact wording of the
  AGENTS.md amendment (which rules relax, which stay absolute). Owner:
  maintainer, before the first affected story.
- **OQ-2** [ASSUMPTION] Retirement projection starts deterministic
  (scenario parameters), Monte Carlo later — confirm when Phase 5 nears.
- **OQ-3** [ASSUMPTION] Benchmark FR-9 starts with fixed-rate baselines;
  index-series benchmarks (e.g. MSCI World) need a quote source decision.
- **OQ-4** bitcoin.de API capabilities (rate limits, history depth) need a
  technical spike before FR-19 is committed.
- **OQ-5** Tax-awareness in rebalancing guidance (FR-12) is desirable but
  unscoped — German capital-gains rules are a deep well; needs its own
  discovery before any commitment (shared with OQ-9).
- **OQ-6** Unattended-sync feasibility per provider: comdirect PhotoTAN may
  force interactive sessions; determine per-provider what "automatic" can
  honestly mean.
- **OQ-7** bunq account-type scope: are non-personal account types part of
  the wealth overview, their own portfolio scope, or out of scope? Owner:
  maintainer, before FR-18.
- **OQ-8** Optional built-in web-UI authentication: needed before any
  non-trusted-network deployment or serious community adoption; decide
  trigger condition.
- **OQ-9** Tax-model depth for the after-tax benchmark comparison (FR-9):
  how deep the German capital-gains model goes (Abgeltungsteuer incl.
  Soli/church tax, Sparer-Pauschbetrag, Vorabpauschale mechanics,
  Teilfreistellung rates per fund type). Shares its discovery with OQ-5 —
  one tax-model decision should serve both FR-9 and FR-12. Owner:
  maintainer, before the first after-tax FR-9 story.

## 9. Glossary

| Term | Meaning here |
|---|---|
| PP | Portfolio Performance, the desktop tool whose data model Portfolixir imports and parallels |
| TTWROR | True time-weighted rate of return — performance excluding cash-flow timing effects |
| IRR | Internal rate of return — money-weighted performance including flow timing |
| SOLL/IST | Target vs. actual (allocation weights) |
| Drift | Deviation of actual category weight from its target weight |
| Tagesgeld | German instant-access savings account; the canonical "safe alternative" baseline |
| Abgeltungsteuer | German flat-rate capital-gains tax withheld on investment income |
| Vorabpauschale | German advance lump-sum taxation of accumulating funds |
| Teilfreistellung | Partial tax exemption on fund income, rate depends on fund type |
| Rentenpunkte | German statutory pension points; accrue from contributions, convert to monthly pension |
| Depot | Securities account at a broker |
| Watch-only | Tracking a crypto wallet by address/xpub without holding any keys |
| Balance adjustment | Ledger kind anchoring a cash account to an absolute balance (ADR-0009 snapshot concept) |
