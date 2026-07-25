---
title: Portfolixir PRD
status: superseded-in-part
created: 2026-06-12
updated: 2026-07-25
---

# Portfolixir PRD

> **Status note (2026-07-25).** This document records the founding product
> intent and the requirement set as it stood on 2026-06-12, corrected for
> decisions taken since. It is **no longer the live requirement registry** —
> `_bmad-output/planning-artifacts/epics.md` is, and it carries FR-30 and
> beyond. Read this PRD for intent, scope boundaries and non-functional
> requirements; read `epics.md` for what is currently committed. Where the two
> disagree, `epics.md` wins.

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

### Positioning (maintainer's landscape scan, 2026-06)

As of June 2026, **no comparable tool is known to the maintainer** that
combines Portfolixir's four differentiators: Portfolio Performance import
parity, MCP-first precomputed analytics (third-party MCP wrappers exist; no
product ships this as its core contract), German retirement modeling, and
what-if/backtest scenarios. This is a scan, not systematic research — no tool
list, search scope or method was recorded — so it is not load-bearing evidence
for the Phase 4 and Phase 5 investment. Treat it as a prior to be checked
before those phases start.

Two readings of the German-retirement gap, and the PRD holds both: it may be
an **opportunity** (nobody covers it), or a **cost signal** (nobody covers it
because the legal parameters are revalued annually, legislation is sometimes
retroactive, and the failure mode — a confidently wrong number — is silent).
FR-24/FR-25 are specified for the second reading.

Target-weight rebalancing alone is the weakest moat — PP itself covers it — so
its value here comes from guidance quality and MCP exposure. The death of
budgeting-hybrid Maybe Finance (2025) validates staying investment-focused.

### Stakes and quality bar

Solo-first, in sequence: built for one operator now, at a quality grade that
lets others adopt it (community potential decides itself later), keeping the
option of a business open without forcing it.

To be precise about what that claims: the bar is **engineering discipline** —
Decimal-exact money math, invariant meta-tests, CI gates, reviewed
architecture decisions. It is explicitly **not a claim of production
readiness**, which AGENTS.md forbids making. An instance today has an
unauthenticated web UI (NFR-4, OQ-8) and no release, versioning or upgrade
story (OQ-10); the "future self-hosters" persona stays dormant until those
exist.

Development is almost entirely AI-agentic and the owner does not read code —
**mechanical guards (gates, invariant tests, scope locks) are load-bearing
product requirements, not process garnish.** NFR-9 states what that obliges.

## 2. Users

- **The operator-investor (Andi).** Self-hosts the app; invests with a
  deliberate **maximum risk performance** strategy (stocks and Bitcoin) over a
  long horizon and plans retirement under German pension rules. Runs more than
  one scope in the same instance, separated by views rather than by separate
  installations (ADR-0024).
- **The LLM agent (first-class user).** An external agent (any MCP client)
  connected via MCP. Reads analytics, maintains records, answers the
  operator's questions. Its needs drive API/MCP design: precomputed values,
  self-describing responses, no forced client-side math.
- **Future self-hosters (quality bar, not a commitment).** Each runs their own
  instance; single-user tenancy per instance. Dormant until OQ-8 and OQ-10 are
  answered.

## 3. User Journeys

**UJ-1 — Morning briefing (agent journey).** Andi asks his MCP agent: "How is
the depot doing, and where should the new cash go?" The agent calls MCP tools
and receives precomputed values: current valuation, cash quote, TTWROR vs.
benchmark, SOLL/IST drift table, each carrying the age of its newest input
quote and FX rate (FR-13). It answers with the top-drift categories and
concrete candidates — without computing a single number itself. A handful of
tool calls, zero exports; each individual response meets NFR-8, and the
round trip is the sum of those calls, not a separate promise.

**UJ-2 — Data maintenance without spreadsheets.** A broker statement arrives.
Today: Andi imports the PP export (later: read-only sync pulls it). The import
previews what would be created, applies idempotently, flags anything
inconsistent (currency mismatch, unknown securities). The manual spreadsheet
and PP reconciliation stay retired — and stay *verifiably* retired, because
the reconcile endpoint (FR-35, in `epics.md`) can compare an external position
list against derived holdings without importing it. Backup/restore (FR-29)
protects against loss; it is not what makes retirement safe.

**UJ-3 — Cash decision, both directions.** Andi needs a sizeable amount liquid.
The agent reads the drift table inverted: which overweight categories can
release cash with the least strategic damage? Same data, opposite sign.

**UJ-4 — The retirement session.** Andi sits down with his agent: "If I stop
early, what do I live on?" The system holds Rentenpunkte, private pension
policies with their payout options, and the depot trajectory; the projection
shows wealth-at-age and sustainable withdrawal under chosen scenario
parameters, each figure stating the legal parameter set and as-of year it was
computed from (FR-24). [ASSUMPTION] Deterministic scenario projection first
(parameterized growth/inflation paths); Monte Carlo is a later refinement.

**UJ-5 — The podcast test.** A stock-tips podcast recommended a stock three
months ago. Andi asks: "If I had blindly bought a fixed amount of every tip
since January — where would I be?" The what-if engine simulates virtual trades
against real quote history as an overlay timeline, never touching the real
ledger — and can aggregate a verdict per tip source over time. Quote history
for securities never held is an unfunded dependency (OQ-11).

**UJ-6 — Switching scope.** Andi switches to a second view; every surface
(holdings, allocation, performance) filters to that scope. Views are the
user-facing grouping (ADR-0020); portfolios are an internal compatibility
record (ADR-0024). One instance, one operator, several scopes.

## 4. Scope and Phasing

Phases are sequential priorities. Most are soft — work can start when capacity
allows. **Three are hard gates and cannot be entered without their ADR:**
Phase 3 (sync), FR-5's XML intake, and FR-12's rebalancing guidance (the last
of which has since been opened by ADR-0023). A gate blocks *building*, not
*wanting*; XML additionally carries no priority right now, so its gate is
dormant. Delivery unit is the **epic batch** per ADR-0026, not story-sized
increments; the roadmap issue (#321) predates that decision.

**Phase 1 — Correctness & data completeness (now).**
Invariant hardening (#343 currency consistency, #344 rounding ADR, #346–#348
gate suites, #350 Unicode gate), write audit journal (FR-28), documented
backup/restore (FR-29), account lifecycle tools (#327, #328 — reframed by
ADR-0024), import data quality (#326 logos).

*PP XML full import (#333) was removed from Phase 1 on 2026-07-25 (owner
decision): it carries no priority. **PP JSON v1 is the operator's actual data
base** and has proven the better path. XML may return to the list later; until
then its scope gate (OQ-1a) is dormant rather than blocking.*

**Phase 2 — LLM-first consumption.**
MCP/API analytics audit and exposure (#349), IRR (#316), income report (#331),
classification view (#334), allocation mechanics (#318, #329, #335). Every
analytic in the analytics register (FR-13) becomes MCP-consumable with method,
basis date, currency and input age stated.

**Phase 3 — Read-only sync.**
Operator-stated **must-have** — the scope gate below governs *when and how*,
not *whether*. Sources: comdirect REST API (depot, official API,
OAuth2+PhotoTAN), bunq API (cash accounts), bitcoin.de (trade history,
conditional on the OQ-4 spike), watch-only wallet tracking for offline BTC
(xpub/address — keys never touch the system). **Hard gate:** AGENTS.md
currently forbids broker/bank sync; entering Phase 3 requires (a) an ADR plus
AGENTS.md amendment limited to read-only data acquisition, (b) the NFR-9
mechanical backstop in place, and (c) **OQ-8 answered** — Phase 3 parks live
bank and broker credentials on a box whose web UI is unauthenticated, so
built-in auth is a precondition, not a later trigger question. Aggregators are
explicitly avoided (free tiers collapsing, 2025) in favor of direct official
APIs. Unattended-sync feasibility per provider is open (OQ-6 — PhotoTAN may
require interactive sessions).

**Phase 4 — Product-type depth.**
Bonds with native semantics (#330), corporate actions (#338), German pension
modeling: gesetzliche Rentenpunkte, private policies with payout options
(lump-sum vs. monthly, age brackets), insurance as wealth components. Each
modeling FR here is preceded by its own discovery story that fixes acceptance
criteria before implementation. **Scope note:** FR-26/FR-27 and the analytics
in FR-9/FR-10 sit against the AGENTS.md hard rule "do not add advanced
reports" — see the gate annotation on those FRs.

**Phase 5 — Planning & simulation.**
Early-retirement projection (wealth-at-age, sustainable withdrawal),
benchmark comparison ("vs. 2% fixed deposit") as a first-class analytic,
what-if simulator incl. blind-follow backtesting (#332).

**Deprioritized / parked:** PP XML full import (#333 — no priority as of
2026-07-25; JSON v1 covers the operator's needs), Dashboard v2 (#337 —
explicitly after data/LLM tracks), algotrading (vision only; **forbidden until
a dedicated scope decision** — this applies wherever it is mentioned,
including the addendum), iOS/macOS apps, cloud hosting, multi-user (#340).

## 5. Functional Requirements

Capabilities, not implementation. IDs are stable and globally numbered; new
requirements append, never renumber — which is why numbering interleaves by
section (A: FR-1..4 then FR-28; B: FR-5..7 then FR-29). That is deliberate,
not an editing error. Sub-ids (FR-9a/b/c) split an over-large requirement
without consuming new global ids.

**Registry authority:** the live FR registry is
`_bmad-output/planning-artifacts/epics.md`, which holds FR-30 and beyond and
maps every FR to its issue. This section is the founding set as corrected on
2026-07-25. New requirements go to `epics.md`, not here.

### A. Ledger & data integrity

- **FR-1** All financial state derives from the transaction ledger (13 PP
  kinds + balance adjustment + split); holdings, balances, and performance are
  projections, never stored facts.
- **FR-2** The system rejects inconsistent records: currency mismatches
  (#343), invalid kinds, signed amounts where magnitudes are required.
- **FR-3** A written rounding policy governs every Decimal operation (#344);
  all money math is Decimal-exact end to end.
- **FR-4** **Views** are the user-facing grouping and every surface and
  analytic can be scoped to one view (UJ-6); **buckets** (ADR-0018) group
  holdings within a view; **portfolios** remain as an internal compatibility
  record only (ADR-0024) and are not a user-facing concept. SOLL plans bind to
  views. A view's category weights must be additive over its members —
  ADR-0024 gates on this, so it is a requirement, not an implementation
  detail. Depots and cash accounts can be moved between scopes (#327) and
  merged/renamed/deleted with transaction reassignment (#328); both issues
  exist as maintenance cost of the superseded container concept.
- **FR-28** Every write to financial data — via UI, API, or MCP — is recorded
  in an append-only audit journal: actor class, timestamp, operation,
  before/after values. The journal is queryable via API and MCP, so a
  hallucinated or erroneous agent edit is always detectable and **attributable
  to an actor class**. Note the limit: while the web UI is unauthenticated
  (NFR-4, OQ-8), a `:owner_ui` write is attributable to a label, not to a
  person. Deletions remain traceable through the journal.

### B. Import & reconciliation

- **FR-5** Portfolio Performance exports import losslessly. **CSV/JSON v1 is
  shipped and is the operator's live data base** — JSON holdings import has
  proven the better path in practice. XML with classifications, quote history
  and master data (#333) is **parked, no priority** (owner decision
  2026-07-25); **hard gate** if it ever returns: XML intake is on the AGENTS.md
  forbidden list and requires the amendment + ADR (OQ-1a) before any
  implementation work. CSV/JSON v1 is the standing exception.
- **FR-6** Imports are previewed (what will be created), idempotent, and
  atomic. Idempotency is **two-layered** (#533, ADR-0029): a per-record
  `import_hash` over stable identity, plus a formatting-tolerant dedup key
  over the resolved database identity. Both layers are load-bearing; any
  import-path change preserves both.
- **FR-7** Import gaps are surfaced, not silently defaulted: unclassified
  securities, missing logos (#326), unknown record kinds, unresolved
  securities and config-at-risk warnings (ADR-0029).
- **FR-29** The system provides a **documented backup and restore procedure**
  (`pg_dump`-based) with a verified restore path, available to the operator as
  documentation rather than as an application feature. *Rescoped 2026-07-22
  (#354): the PP-compatible export was dropped — Portfolixir is a one-way
  import destination, and data egress for external consumers is the JSON API.*
  This FR is disaster recovery. It is explicitly **not** an independent
  verification of correctness: a dump is the same schema read by the same
  code, so a projection bug or a wrong import is preserved faithfully.
  Verification is FR-35's reconcile endpoint (`epics.md`).

### C. Analytics engine

> **Scope gate for FR-9, FR-10, FR-26, FR-27.** AGENTS.md's hard rule "do not
> add advanced reports or advanced classifications" stands unamended, and
> these four requirements are not plausibly anything else. They require the
> same ADR + AGENTS.md amendment as the other gated items; OQ-1c carries the
> wording. No implementation before it lands.

- **FR-8** Performance: TTWROR (shipped) and IRR/money-weighted (#316) per
  view, depot, and security, over selectable periods.
- **FR-9a** **Fixed-rate benchmark.** A performance series can be compared
  against a fixed-rate alternative ("2% Tagesgeld"). **Method is part of the
  requirement:** the actual cash flows are replayed into the alternative and
  compared on end wealth and IRR. A TTWROR series compared against a flat rate
  is apples-to-oranges — TTWROR deliberately removes cash-flow timing, and
  "would I be richer in Tagesgeld?" depends entirely on when the cash flowed.
  If a first version ships the TTWROR approximation, the caveat is embedded in
  the self-describing response (FR-13), not left in a planning document.
- **FR-9b** **Index/security-series benchmark.** The same comparison against
  an index or security series, in two named scenarios: "bought once and held"
  and "as a savings plan". Depends on a quote-source decision (OQ-3).
- **FR-9c** **After-cost / after-tax overlay.** Trading fees and German
  capital-gains taxes (Abgeltungsteuer, Vorabpauschale, Teilfreistellung) can
  be included, so the answer is not flattered by pre-cost figures. Applies to
  the money-weighted result of FR-9a/FR-9b, never to a time-weighted series —
  capital-gains tax attaches to realised outcomes, so "after-tax TTWROR" is
  ill-defined and must not be produced. Tax-model depth: OQ-9.
- **FR-10** Income analytics: received dividends and interest, gross/net, per
  year and position (#331).
- **FR-11** Allocation: classification trees with target weights, SOLL/IST
  drift per category (shipped — note ADR-0023 changed the drift sign
  convention, a breaking API change; consumers reading this PRD's earlier
  wording get the old semantics), target-consistency hints (#318), cash as
  part of the 100% basis (#335), per-security exclusion flags (#329).
- **FR-12** Rebalancing guidance, both directions: ranked "where new cash
  goes" and "where needed cash comes from". **Primary ranking criterion:**
  drift magnitude in **percentage points** of weight deviation; absolute
  currency deviation is a secondary, separately labelled ordering. Further
  criteria (e.g. tax awareness, OQ-5) extend the ranking later.
  **Boundary, in ADR-0023's terms:** the system may show an *indicative
  corrective quantity at the latest stored quote*; it never creates, stores or
  transmits an order. *Shipped:* the drill-down hint. *Open:* the ranked
  both-directions cash guidance.

### D. LLM/MCP surface

- **FR-13** Every analytic in the **analytics register** — a machine-readable
  list of computed analytics maintained in the repo — is exposed via JSON API
  and MCP (#349), and the API/MCP parity check runs against that register.
  Responses are self-describing: method, as-of date, currency, and conversion
  basis stated; financial values serialized as strings. Every
  valuation-bearing response additionally carries **the age of its newest
  input quote and FX rate** and self-marks stale beyond a configured
  threshold, so a briefing cannot be confidently stale (UJ-1).
- **FR-14** The API/MCP write surface is a specified contract, not a parity
  aspiration:
  - **FR-14a** Write coverage is enumerated against the API surface and
    includes **delete**. Falsifiable form: every write endpoint under
    `/api/v1` has a matching MCP tool.
  - **FR-14b** Every API/MCP write accepts an **idempotency key**; a retried
    request with the same key and body is a no-op, and the same key with a
    different body is an error. This is separate from FR-6's content-hash
    record dedup: keys dedupe the *request*, the content hash dedupes the
    *records*, and both hold.
  - **FR-14c** A **dry-run mode** mirrors import preview: the caller sees what
    would change before it changes.
  - **FR-14d** Validation errors are machine-readable and designed for agent
    recovery (which field, which rule, what would satisfy it).
  - All of the above is captured by the audit journal (FR-28).
- **FR-15** Tool descriptions carry, for every tool: when to use it, its
  preconditions, and its paging/response-size bound. FR-33's slim projection
  is the worked example of what this means concretely.
- **FR-16** The MCP companion remains a thin wrapper over the public JSON API
  (ADR-0002) — that invariant is the requirement. *How* it is enforced is a
  workflow matter: `project-context.md` records API/MCP parity as a PR-review
  checklist item, deliberately not mechanised. FR-13's register is what would
  make mechanisation possible later.

### E. Read-only sync (Phase 3, behind the hard gate)

- **FR-17** comdirect: depot positions and transactions via the official REST
  API; reconciliation against the existing ledger with preview before apply.
- **FR-18** bunq: account balances and transactions for cash accounts.
- **FR-19** bitcoin.de: executed trades into the ledger — conditional on the
  OQ-4 technical spike (API capabilities, rate limits, history depth).
- **FR-20** Watch-only crypto: balance tracking for offline-wallet addresses/
  xpubs; private keys are out of scope by design, permanently. Chain-data
  source is an unfunded dependency (OQ-11).
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
  **Assumptions and scope, v1:** gross payout, current law, **driven by an
  operator-maintained, effective-dated parameter table** — never derived in
  code, which ADR-0031 states is structurally impossible. Rentenwert
  revaluation, Abschläge for early retirement, nachgelagerte Besteuerung and
  KVdR are **out of scope for v1** and every response states so. Every figure
  carries the parameter set and as-of year it used (FR-13). Align with FR-36's
  `tax_parameters` / `tax_profiles` pattern (ADR-0031) rather than inventing a
  second mechanism. Parameter-update ownership: OQ-12.
- **FR-25** Private pension/insurance policies: payout options modeled
  (lump-sum vs. monthly, eligibility ages), comparable against depot
  withdrawal. Same v1 assumption block and parameter-table discipline as
  FR-24.

### G. Planning & simulation (Phase 5 — under the section C scope gate)

- **FR-26** Retirement projection: wealth-at-age and sustainable-withdrawal
  curves from current holdings, savings rate, and pension components under
  named scenario parameter sets (discovery story fixes the acceptance
  criteria backing Success Metric 3).
- **FR-27** What-if simulator: virtual trade scenarios as overlay timelines
  against real quote history — including "blind-follow" series (buy a fixed
  amount on each tip date) and an aggregate per-source verdict ("are this
  podcast's tips any good?") — strictly separated from the real ledger (#332).
  Historical quotes for **never-held** securities are an unfunded acquisition
  dependency (OQ-11).

## 6. Non-Functional Requirements

- **NFR-1 Correctness over features:** Decimal-only persistence, exact-value
  tests, invariant meta-tests, and the quality-gate roadmap
  (project-context.md) are release-blocking. Silent financial corruption is
  the defining failure class.
- **NFR-2 Auditability:** every number is reproducible from the ledger as it
  stands, and every change to the ledger is recorded in the append-only audit
  journal (FR-28). Ledger records are **editable**; edits are never hidden.
  Auditability here means reproducibility from inputs, **not** append-only
  immutability — soft-delete workarounds are explicitly forbidden.
- **NFR-3 AI-agentic development guards:** CI gates per project-context.md,
  including invisible-Unicode/Trojan-Source rejection (#350); scope changes
  only via ADR + AGENTS.md amendment, never silent. NFR-9 supplies the
  mechanism that makes "never silent" more than a promise.
- **NFR-4 Security boundaries:** no in-app LLM calls; no trading, payment, or
  order functionality; read-only sync only (Phase 3+); API/MCP access via
  local bearer tokens; no secrets in source. **The web UI itself is
  unauthenticated by design** — an instance must run on a trusted network or
  behind reverse-proxy authentication; the deployment docs state this
  prominently. Built-in auth (OQ-8) is a **precondition of Phase 3**, because
  Phase 3 stores live bank and broker credentials behind that UI.
- **NFR-5 Self-hosted operations:** docker-compose deployment, PostgreSQL as
  the only store, runs always-on on the operator's hardware; MCP companion
  installable separately.
- **NFR-6 Single-user tenancy:** one instance, one operator; view-scoped
  filtering instead of multi-user.
- **NFR-7 Localization:** UI localized (de/en via gettext); repository
  artifacts in English.
- **NFR-8 Performance:** a single interactive view or MCP analytic response
  completes within p95 < 2 s on commodity home-server hardware at realistic
  scale (hundreds of securities, tens of thousands of transactions). This is
  currently **aspirational**: `project-context.md` lists performance/load
  gates as deliberately not adopted, so no instrument measures it. Either a
  named benchmark harness and dataset land with the first FR that depends on
  it, or the number stays labelled as an intent. Correctness always beats
  speed.
- **NFR-9 Mechanical scope backstop:** the hard gates (Phase 3 sync, FR-5
  XML intake, the section C analytics gate) are backed by meta-tests in the
  invariant suite — a dependency allowlist, no credential-bearing schema, no
  bank-domain HTTP configuration — each removable only in the same PR as the
  corresponding ADR and AGENTS.md amendment. Without this, the project's most
  consequential boundary is enforced by one person editing Markdown as author,
  approver and enforcer, in a codebase that already meta-tests far cheaper
  invariants.

## 7. Success Metrics (12 months)

Each metric names the instrument that reads it. A metric without an instrument
is an intent, not a metric.

1. **Spreadsheet retirement:** zero manual cross-checking workflows remain.
   *Instrument:* FR-35's reconcile endpoint reports **zero unexplained
   differences** against an external position list over three consecutive
   monthly checks. This replaces the earlier FR-29 gate: backup is not
   verification.
2. **Agent autonomy:** the MCP agent answers "where does new cash go?", "is
   the depot beating the baseline?", and "what did my income look like?" via
   MCP without exports or file handoff. *Instrument:* server-side count of MCP
   sessions per week that answer these questions **without** a bulk
   `securities_list`-style pull — the absence of client-side arithmetic is not
   observable, but the bulk pull that would enable it is.
3. **Retirement credibility:** a first early-retirement projection runs with
   the FR-26 discovery story's acceptance criteria met. *Instrument:* those
   criteria. Until the discovery story exists (`epics.md` lists FR-26 as
   `future`, no issue), this metric has no acceptance definition and should be
   treated as unmeasured rather than unmet.

**Counter-metrics (what must not degrade while chasing the above):**

- Financial-correctness incidents (wrong number reaching a view/API): target
  zero; every occurrence becomes an invariant test. *Instrument:* the same
  reconcile endpoint as Metric 1 — this is deliberate. Without an independent
  comparison there is no detector, and Metric 1 must not be achieved by
  removing the only thing that can find wrong numbers.
- Reconciliation drift between synced data and official statements: surfaced,
  never silently absorbed. *Instrument:* FR-35 for the pre-sync era, provider
  reconciliation (FR-17) afterwards.
- Gate health: **gates are never weakened to ship a feature** — grandfathered
  baselines (Credo thresholds, documented Sobelow ignores) only ratchet
  downward, per project-context.md.

## 8. Open Questions

- **OQ-1a** **[dormant]** FR-5 XML intake: ADR + AGENTS.md amendment wording.
  *Was a Phase-1 blocker until 2026-07-25, when the owner removed PP XML from
  the roadmap for lack of priority.* Nothing is blocked while XML stays
  parked; the question reactivates the moment #333 returns to a phase. Owner:
  maintainer, due before any #333 story is scheduled.
- **OQ-1b** Phase 3 sync scope ADR: which rules relax, which stay absolute.
  Owner: maintainer, before Phase 3. Bundled with OQ-8 and NFR-9.
- **OQ-1c** Advanced-reports amendment covering FR-9/FR-10/FR-26/FR-27 and the
  AGENTS.md goal list. Owner: maintainer, before the first affected story.
  *(The FR-12 third of the original OQ-1 is **resolved** — ADR-0023, accepted
  2026-07-03.)*
- **OQ-2** [ASSUMPTION] Retirement projection starts deterministic
  (scenario parameters), Monte Carlo later — confirm when Phase 5 nears.
- **OQ-3** [ASSUMPTION] Benchmark FR-9a starts with fixed-rate baselines;
  FR-9b index-series benchmarks need a quote source decision.
- **OQ-4** bitcoin.de API capabilities (rate limits, history depth) need a
  technical spike before FR-19 is committed.
- **OQ-5** Tax-awareness in rebalancing guidance (FR-12) is desirable but
  unscoped — German capital-gains rules are a deep well; needs its own
  discovery before any commitment (shared with OQ-9).
- **OQ-6** Unattended-sync feasibility per provider: comdirect PhotoTAN may
  force interactive sessions; determine per-provider what "automatic" can
  honestly mean.
- **OQ-7** bunq account-type scope: are non-personal account types part of
  the wealth overview, their own scope, or out of scope? Owner: maintainer,
  before FR-18.
- **OQ-8** Built-in web-UI authentication. **Precondition of Phase 3**, not an
  open-ended trigger: Phase 3 stores live bank and broker credentials on a box
  whose UI is reachable by anyone who reaches the port, and "trusted network"
  is doing heavy unexamined work for a home LAN with an always-on agent and
  guest devices. Also required before any non-trusted-network deployment or
  community adoption.
- **OQ-9** Tax-model depth for FR-9c: how deep the German capital-gains model
  goes (Abgeltungsteuer incl. Soli/church tax, Sparer-Pauschbetrag,
  Vorabpauschale mechanics, Teilfreistellung rates per fund type). Shares its
  discovery with OQ-5 — one tax-model decision serves FR-9c and FR-12. Owner:
  maintainer, before the first FR-9c story.
- **OQ-10** Release, versioning and upgrade story: self-hosters upgrade their
  own instances, and nothing in this PRD requires a release process, a version
  scheme, or a migration guarantee. Owner: maintainer, before the
  future-self-hoster persona stops being dormant.
- **OQ-11** Historical-quote acquisition for **never-held** securities
  (FR-27's blind-follow backtesting) and chain data for FR-20: source, depth,
  retention, licence, and fit with ADR-0005's provider split. This is a
  different acquisition problem from maintaining quotes for held positions.
  Owner: maintainer, before the first FR-27 or FR-20 story.
- **OQ-12** Ownership and update cadence of the legal parameter tables behind
  FR-24/FR-25 (and FR-36's `tax_parameters`): who updates them, on what
  trigger, and what the app does when they are stale. Owner: maintainer,
  before the first FR-24 story.

## 9. Glossary

| Term | Meaning here |
|---|---|
| PP | Portfolio Performance, the desktop tool whose data model Portfolixir imports and parallels |
| TTWROR | True time-weighted rate of return — performance excluding cash-flow timing effects |
| IRR | Internal rate of return — money-weighted performance including flow timing |
| SOLL/IST | Target vs. actual (allocation weights) |
| Drift | `actual_weight − target_weight`; positive means overweight (sign convention fixed by ADR-0023, a breaking change from the earlier implementation). Ranked in percentage points by default (FR-12) |
| View | The user-facing scope; every surface and analytic filters to one view. SOLL plans bind here (ADR-0020, ADR-0024) |
| Bucket | Grouping of holdings within a view (ADR-0018) |
| Portfolio | Internal compatibility record only; not a user-facing grouping since ADR-0024 |
| Tagesgeld | German instant-access savings account; the canonical "safe alternative" baseline |
| Abgeltungsteuer | German flat-rate capital-gains tax withheld on investment income |
| Vorabpauschale | German advance lump-sum taxation of accumulating funds |
| Teilfreistellung | Partial tax exemption on fund income, rate depends on fund type |
| Rentenpunkte | German statutory pension points; accrue from contributions, convert to monthly pension |
| Depot | Securities account at a broker |
| Watch-only | Tracking a crypto wallet by address/xpub without holding any keys |
| Balance adjustment | Ledger kind anchoring a cash account to an absolute balance. **Naming trap:** ADR-0009 calls this concept a "snapshot", but the data spells it `balance_adjustment` — and ADR-0027's "snapshot" is a different thing again (a ledger marker that copies nothing) |
| Split | Ledger kind for share splits (ADR-0028); ratio only, no cash/price/quantity fields |
