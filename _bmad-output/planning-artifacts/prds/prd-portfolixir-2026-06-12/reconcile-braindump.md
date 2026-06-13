# Reconciliation: Brain Dump vs. PRD/Addendum (2026-06-12)

Input-reconciliation only — gaps and flattenings, no quality judgment. Each
bullet: what was said / where it's missing or flattened / suggested home.

## Meaning distortions (highest priority)

- **"Maximum risk performance" became "maximum risk-adjusted performance".**
  Brain dump: until retirement the operator wants *maximum risk* performance
  with stocks and Bitcoin — deliberately high-risk, consciously chosen.
  Addendum ("Investor profile") inserts "risk-adjusted",
  which inverts the spirit (risk-adjusted = Sharpe-style prudence; he said
  max-risk). → Fix wording in addendum "Investor profile"; this shapes how
  rebalancing guidance and benchmarks should be framed (aggressive allocation
  is a feature, not a bug to correct).

- **"NEEDS automatic syncing" — strength of need flattened to a gated phase.**
  Brain dump marks automatic syncing to financial institutions as a hard need
  (emphasized). PRD treats it correctly as Phase 3 behind a scope-unlock ADR
  (consistent with AGENTS.md), but nowhere records that the *user* considers
  it a necessity, not a nice-to-have. The tension (user: must-have; scope
  lock: forbidden until ADR) is itself a fact worth recording. → One sentence
  in PRD §4 Phase 3 or OQ-1: "Operator classifies sync as a hard requirement;
  the gate governs *when*, not *whether*."

## Dropped qualitative ideas

- **"Tooling that helps optimize, analyze, and MAKE UNDERSTANDABLE."** The
  third verb — making finances *understandable* to the human — is dropped.
  PRD vision is LLM-consumption-centric ("decision-ready analytics" for the
  agent); human comprehension/explainability as a product goal appears
  nowhere. → Add to PRD §1 Vision (one clause) or as an NFR-flavored line:
  outputs should make the portfolio understandable to the operator, not only
  machine-consumable.

- **"Wants LESS own research — a system that supports him."** The
  meta-motivation across pension, insurance, payout, and tip topics is that
  the system offloads his personal research burden. The PRD covers each topic
  as an FR but loses the unifying "reduce my research effort" job-to-be-done.
  → Addendum "Origin story" (one bullet); optionally informs Success Metric 2
  phrasing.

- **"Repeatedly consulted LLMs about this" (strategy weights/rebalancing).**
  The fact that LLM consultation was a *recurring habit specifically about
  SOLL-weights and cash allocation* — not just a generic export workflow — is
  flattened into the Numbers→CSV→LLM pipeline description. Mild, but it
  explains why FR-12 guidance must be LLM-legible. → Addendum "Origin story";
  fine to merge into the existing workflow bullet.

## Flattened specifics

- **bunq account types — flattened to "cash accounts".**
  FR-18 and the phasing say generic "cash accounts". The brain dump named
  distinct account types, which raises an unrecorded question: do
  non-personal account types belong in the wealth overview, in a separate
  portfolio scope (like the second household portfolio), or out of scope?
  → New Open Question (OQ) or a parenthetical in FR-18; cheap to record now,
  awkward to discover during Phase 3.

- **"Different financial products need different information /
  representations / derived calculations" — generalized principle reduced to
  bonds.** FR-22 carries the principle as a trailing clause inside the bond
  requirement ("product types carry their own data and their own math"), and
  the *representation/display* dimension (different products need different
  views, not just data+math) is dropped entirely. → Promote to a standalone
  one-line principle at the top of FR section F, including representation;
  bonds (#330) stay the first instance.

- **"Are the podcast tips any good?" — source-quality judgment vs.
  single backtest.** FR-27/UJ-5 cover "blind-follow since date X" well, but
  the brain dump also asks whether the *tip source as such* is any good —
  implying an aggregate verdict over all tips (hit rate, P/L distribution),
  not only one overlay timeline. → Fine as a note in addendum "Tip
  backtesting"; no FR change needed now.

- **"Overview of ALL financial instruments" / "everything countable as wealth
  or passive income".** Covered in Vision and addendum, but the *passive
  income* half (income streams as first-class, beyond dividends/interest in
  FR-10) is only implicit. → Fine to drop for now; optionally one word in the
  addendum "Future visions" bullet ("passive income streams" already hinted
  via #340 parking lot).

## Confirmed covered (no action)

- Founding "2% Tagesgeld" question; SOLL-weights + both-direction cash
  guidance; spreadsheet/PP reconciliation pain; home MCP agent setup;
  investor-profile background (details redacted 2026-06-13 — public repo);
  not-a-playground + invisible-Unicode gate (#350, NFR-3); bonds pain (#330);
  Rentenpunkte marginal value (FR-24) and lump-sum vs. monthly (FR-25);
  provider mapping (comdirect, bunq, bitcoin.de, watch-only wallet);
  second household portfolio as filtered scope in same instance; LLMs both
  read AND maintain data (FR-14); all three 12-month success criteria;
  Zukunftsmusik items (algotrading, iOS/macOS, cloud) correctly parked.
