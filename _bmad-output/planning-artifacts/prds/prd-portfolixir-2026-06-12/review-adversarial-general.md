# Adversarial Review — Portfolixir PRD (2026-06-12)

Second-pass cynical review, performed 2026-07-25 against `prd.md` (status:
`final`, `updated: 2026-06-12`) and `addendum.md`, cross-checked against
`AGENTS.md`, `_bmad-output/project-context.md`, `_bmad-output/planning-artifacts/epics.md`,
`docs/decisions/0016`–`0031`, `lib/portfolixir/actor.ex`,
`lib/portfolixir/journal/entry.ex`, and `lib/portfolixir_web/router.ex`.
The 2026-06-12 `review-adversarial.md` was read only to audit its claimed fixes.

## Verdict

The document is well written and, in its June form, was an honest artifact. It
is no longer a usable contract, for two independent reasons. First, its own
authority claim is false: the PRD says "**the PRD is authoritative — issues
track implementation**", but the authoritative requirement registry migrated to
`epics.md` six weeks ago. FR-30 through FR-36 were added and owner-confirmed
there (2026-07-18, 2026-07-22, 2026-07-25) and never appended here, despite the
PRD's own rule that "new requirements append, never renumber". FR-29 was
**rescoped by owner decision on 2026-07-22** — the PP-compatible export was
dropped, leaving a `pg_dump` procedure — and the PRD still promises the dropped
capability in three places, including the safety argument that licenses the
product's headline success metric. ADR-0024 demoted the portfolio entity to an
internal compatibility record on 2026-07-12; FR-4 and UJ-6 still describe
portfolios as the user-facing grouping. A reader who takes this file at its word
will build the wrong product.

Second, the "all criticals and highs fixed" claim in the decision log does not
survive inspection. Of the prior review's two criticals and seven highs, four
were genuinely resolved, one has since **regressed**, one was addressed only
cosmetically, and three (H-2 mechanical scope backstop, H-5 unfalsifiable
counter-metric, H-7 pension legal-parameter churn) were never touched at all —
the fix list in the decision log simply does not mention them, while the summary
sentence claims blanket resolution. On top of that, the June review missed a
standing scope-lock violation that is still open: AGENTS.md's hard rule "Do not
add advanced reports" is contradicted by four unannotated FRs, and FR-12's
self-imposed safety line ("never places, **prepares**, or **suggests**
executable orders") is drawn in a materially different place than the ADR-0023
behaviour that has already shipped. The metrics section remains the weakest
part: not one of the three success metrics can be measured from anything the
product stores.

## Findings

### F-1. The PRD claims authority it no longer has; the live FR registry is elsewhere

**Severity:** critical
**Location:** § 5 preamble; frontmatter `status: final`, `updated: 2026-06-12`

> "IDs are stable and globally numbered; new requirements append, never
> renumber. […] **the PRD is authoritative — issues track implementation.**"

`epics.md` carries FR-30 (ISIN/WKN in holdings payloads), FR-31 (MCP create for
all 13 kinds), FR-32 (booking-semantics docs), FR-33 (slim `securities_list`),
FR-34 (re-import survival), FR-35 (read-only reconcile endpoint) and FR-36
(recorded tax-statement snapshots) — all "owner-confirmed", several already
shipped (#582, #581), one carrying its own accepted ADR (ADR-0029) and one a
proposed decision gate (ADR-0031, 2026-07-25). `epics.md` has quietly amended
the authority claim to "The PRD/**epics** are authoritative". The PRD does not
know any of this exists. Downstream: an agent handed `prd.md` as the requirement
source will treat FR-30..36 as out of scope, and any future adversarial or
readiness review run against the PRD will "discover" gaps that were closed
months ago (and miss the ones that weren't). A requirements document that is
`final` while its requirement set grows elsewhere is a decoy, not a contract.

**Fix:** Either append FR-30..FR-36 here and re-date the document, or demote the
PRD explicitly: change § 5's preamble to "the epics document is the live FR
registry; this PRD records the founding intent as of 2026-06-12" and set
`status: superseded-in-part` with a pointer. Silence is the only wrong option —
one of the two documents must stop claiming to be authoritative.

### F-2. FR-29 was rescoped away, and the safety argument that depends on it was never re-examined

**Severity:** critical
**Location:** FR-29, UJ-2, § 7 Success Metric 1

> "FR-29 The system provides a documented backup/restore procedure and a **full
> data export in PP-compatible format** (roundtrip: Portfolixir → PP →
> Portfolixir), available via UI and MCP. Retiring external copies (Numbers, PP)
> is only safe because this exists"

ADR-0029 records the reality: "FR-29 — rescoped 2026-07-22 to documented
`pg_dump` backup/restore, PP export dropped (#354)". ADR-0028 carries the same
note and drops the round-trip marker mapping. `architecture.md` had already
flagged the risk (A3: "Portfolixir today discards data PP carries (e.g.
per-transaction FX rates, ADR-0007)"). So the capability the PRD calls the
precondition for retiring the operator's independent copy of his financial
history no longer exists as a plan. This is the June review's critical C-2
regressing: a `pg_dump` is a copy of the same schema interpreted by the same
code. If the defect is a projection bug, a mis-signed import, or a hallucinated
agent write, the dump faithfully preserves it — it is a disaster-recovery
artifact, not an independent verification artifact, and the PRD's sentence
"retiring external copies … is only safe because this exists" is exactly the
claim a database dump cannot support. UJ-2 ("the manual spreadsheet and PP
reconciliation stay retired — safely, because …") and Success Metric 1's gate
both inherit the false premise.

**Fix:** Rewrite FR-29 to the shipped scope (`pg_dump` backup/restore with a
verified restore procedure) and **remove the safety claim from it**. Then either
re-gate Success Metric 1 on something that actually detects wrong numbers — the
FR-35 reconcile endpoint is the obvious candidate and already exists — or state
plainly that retiring the independent copy is an accepted, unmitigated risk.

### F-3. Claimed fix H-6 did not land: FR-14 still specifies an LLM writer with no failure modes

**Severity:** high
**Location:** FR-14

> "MCP tools cover data maintenance (create/update records) as well as reads —
> an LLM can fully replace manual UI data entry, within the same validation
> rules, with every write captured by the audit journal (FR-28)."

The decision log claims "All criticals/highs … fixed". The only change to FR-14
is the trailing audit-journal clause. Every one of H-6's four named gaps
survives verbatim: (a) **delete is still unlisted** although the MCP surface
ships deletes; (b) **no write idempotency** — FR-6's content-hash covers file
imports only, so an MCP client that times out and retries `transactions_create`
duplicates a financial record, the single most predictable agent failure there
is; (c) **no dry-run**, while file imports get preview-before-apply; (d) **no
runaway bound**. An audit journal makes the damage *legible afterwards*; it
prevents none of it. Downstream, the epics document had to invent the missing
contract piecemeal and out of band — FR-31's "delivery cost-basis guard", FR-32's
"fix-it-hammer warnings", FR-35's embedded resolution guidance are all
after-the-fact patches for a write contract this FR should have specified.

Separately, "an LLM can **fully** replace manual UI data entry" is an unbounded
parity claim over a UI that keeps growing. It is untestable as written and
silently false the day any new LiveView form ships without a tool.

**Fix:** Split FR-14 into: (a) write coverage including delete, enumerated
against the API surface; (b) idempotency keys required on every API/MCP write;
(c) a dry-run mode mirroring import preview; (d) machine-readable validation
errors designed for agent recovery. Replace "fully replace" with a falsifiable
parity statement ("every write endpoint in `/api/v1` has a matching MCP tool" —
which is checkable).

### F-4. Claimed fix H-2 did not land: the scope gates are paper, in a PRD that calls mechanical guards load-bearing

**Severity:** high
**Location:** § 1 "Stakes and quality bar", NFR-3, Phase 3 scope gate, FR-5, FR-12

> "**mechanical guards (gates, invariant tests, scope locks) are load-bearing
> product requirements, not process garnish.**"

> "NFR-3 … scope changes only via ADR + AGENTS.md amendment, never silent."

The document's most consequential boundary — the one separating a portfolio
tracker from something holding live bank credentials — is enforced by a solo
owner writing a document and editing a Markdown file, with the same person as
author, approver and enforcer, and by the PRD's own admission not reading the
code. Nothing fails CI if an OAuth client, a credentials table, or a bank
hostname lands before the ADR. The project already builds invariant meta-tests
for far cheaper invariants (`no :float in schemas`, `no DB deps in
mcp-server`, `no catch-all in Ledger.Projection.effects/1`). The June review
asked for a dependency/schema/hostname allowlist meta-test; the decision log
does not mention H-2 at all, and no such requirement appears in the current
text. A PRD that declares mechanical guards load-bearing and then specifies its
riskiest boundary as prose is arguing against itself.

**Fix:** Add an NFR: the Phase-3/XML/rebalancing boundaries are backed by
meta-tests in the invariant suite (dependency allowlist, no credential-bearing
schema, no bank-domain HTTP config), removable only in the same PR as the ADR
and AGENTS.md amendment. Reference it from NFR-3 so the "never silent" clause
has a mechanism behind it.

### F-5. Claimed fix H-7 did not land: FR-24/FR-25 sell a moat that is an unbounded legal-maintenance liability

**Severity:** high
**Location:** § 1 Positioning, FR-24, FR-25, UJ-4

> "FR-24 German statutory pension: Rentenpunkte as a tracked asset with
> projected payout ('what does one more point buy me?')."

Unchanged from the reviewed draft. There is still no assumption block, no
gross/net scoping, no statement about Rentenwert revaluation, Abschläge,
nachgelagerte Besteuerung or KVdR, and — the operationally fatal omission — **no
requirement for owning and dating the legal parameter tables**. "What does one
more point buy me?" has no correct answer without them, so as specified FR-24
ships a confidently wrong number to an LLM that will repeat it verbatim. The
positioning section compounds this by selling the gap as a moat ("German
retirement modeling (no open-source coverage found)") without entertaining the
obvious alternative explanation: nobody covers it because the parameters change
annually and being wrong is worse than being absent.

The project has since proved the finding. FR-36 (2026-07-25, ADR-0031) had to
build precisely the machinery H-7 asked for — a seeded, operator-editable
`tax_parameters` table keyed by `(jurisdiction, tax_year)` and an
**effective-dated** `tax_profiles` table — and its ADR states outright that
derivation "is structurally impossible". That is a discovery the PRD could have
forced eighteen months earlier by applying its own `[ASSUMPTION]` discipline
here.

**Fix:** Add to FR-24/FR-25 the assumption block the June review specified: v1 =
gross, current-law, **parameter-table-driven** projection with parameters as
operator-maintained, effective-dated data surfaced with as-of dates per FR-13;
taxes and KVdR explicitly out of scope v1 and stated in every response. Add an
OQ for parameter-update ownership. Align with FR-36's `tax_parameters` pattern
rather than inventing a second one.

### F-6. Scope-lock violation: four FRs are "advanced reports", which AGENTS.md forbids, with no gate annotation

**Severity:** high
**Location:** FR-9, FR-10, FR-26, FR-27 (vs. AGENTS.md Hard Rules)

AGENTS.md, unamended: "**Do not add advanced reports or advanced
classifications.**" The PRD is meticulous about gating the *named* forbidden
classes (XML intake, sync, rebalance) and completely silent about this one, yet
FR-9 (multi-scenario benchmark comparison with after-cost and after-tax
dimensions across three named German tax mechanics), FR-10 (income analytics
gross/net per year and position), FR-26 (retirement projection with
sustainable-withdrawal curves) and FR-27 (what-if simulator with per-source
aggregate verdicts) are not plausibly anything else. Nor does AGENTS.md's
twelve-item goal list contain sync, pensions, bonds, corporate actions or
simulation. This reproduces exactly the defect H-3 identified for FR-5 and FR-12
— contradictory contracts in a project whose entire methodology is "agents obey
written contracts" — and the fix applied there (annotate the gate) was never
generalised.

**Fix:** Either annotate FR-9/10/26/27 with the same scope-gate note as FR-5 and
FR-12, or fold the required goal-list and hard-rule amendment into OQ-1's
deliverable so one ADR settles the whole set. Do not leave the rule standing
while four FRs walk through it.

### F-7. FR-12 and ADR-0023 draw the guidance-versus-action line in different places

**Severity:** high
**Location:** FR-12 (vs. `docs/decisions/0023-*`, accepted 2026-07-03)

> "Guidance only — the system never places, **prepares**, or **suggests
> executable orders**. (AGENTS.md 'no rebalance action' stays untouched; the
> amendment for this FR clarifies guidance vs. action.)"

The amendment landed as ADR-0023, and it permits the UI/API to show "the
quantity to buy or sell **at the latest stored quote** that would close the
gap". A concrete instrument, a concrete side, a concrete quantity, priced — that
is an order minus the send button, and it is very hard to read as neither
"preparing" nor "suggesting" an executable order under FR-12's own wording. Two
governing documents now define the product's most safety-relevant boundary
differently, and the narrower one is the PRD that claims to be authoritative.
Whichever is correct, the divergence means a reviewer cannot decide whether a
future feature crosses the line by reading either document alone.

Note also that FR-12's *actual* content — "ranked 'where new cash goes' and
'where needed cash comes from'" — remains open per `epics.md` ("Ranked
both-directions cash guidance remains open"); only the drill-down hint shipped.
The PRD records neither the partial closure nor the boundary shift.

**Fix:** Restate FR-12's boundary in ADR-0023's terms verbatim ("indicative
corrective quantity at the latest stored quote, never created, stored or
transmitted as an order") so the two documents cannot be read against each
other, and mark which half of FR-12 has shipped.

### F-8. FR-4 and UJ-6 describe a grouping model the product deliberately abandoned

**Severity:** high
**Location:** FR-4, UJ-6 (vs. ADR-0024, accepted 2026-07-12)

> "FR-4 Portfolios partition the wealth space; every view and every analytic can
> be scoped to one portfolio (filtered views, UJ-6)."

ADR-0024 demotes "the portfolio entity to an internal compatibility record" and
makes buckets (ADR-0018) and views (ADR-0020) the only user-facing grouping,
with SOLL plans bound to views. It names FR-4's own issues (#327, #328) as
existing "purely as maintenance cost of the container concept". So the PRD's
grouping FR, the journey that motivates it (UJ-6, "Alex switches to the second
household portfolio"), and the two issues it cites are all obsolete. The June
review's M-8 flagged that FR-4's scoping claim was broader than the model
supported; it was rated medium and never fixed, and the product then solved the
problem by replacing the model — leaving the PRD describing neither the old
design nor the new one.

**Fix:** Rewrite FR-4 in bucket/view terms (which entities are scoped, which are
instance-global, where SOLL plans bind, how the additivity constraint that
ADR-0024 gates on is stated as a requirement) and rewrite UJ-6 as a view switch.

### F-9. Not one of the three success metrics can be measured from what the product stores

**Severity:** high
**Location:** § 7 Success Metrics 1–3 and Counter-metrics

> "2. **Agent autonomy:** the MCP agent answers … via MCP **without any export,
> file handoff, or client-side computation**."

Portfolixir cannot observe whether its client did arithmetic; the absence of
client-side computation is unobservable by construction, so Metric 2 resolves to
the operator's impression. Metric 1 ("zero manual cross-checking workflows
remain") is likewise self-reported — the product cannot see a spreadsheet that
is not open. Metric 3 ("a first early-retirement projection **runs** on real
pension data") is satisfied by any non-crashing output and says nothing about
correctness; its acceptance is deferred to an FR-26 discovery story which
`epics.md` still lists as `future` with no issue. All three are one-shot demo
events wearing a "12 months" label (the June review's L-1, unresolved).

The counter-metrics are worse. Counter-metric 1 targets zero "financial-
correctness incidents (wrong number reaching a view/API)" — wrong numbers are
only ever *discovered* by comparison against an independent source, which is
exactly what Metric 1 defines success as eliminating. Achieving Metric 1
therefore drives Counter-metric 1 to zero by construction. This is H-5 verbatim;
the "fix" applied was gating Metric 1 on FR-29, which is egress, not
verification — and FR-29's verification half has since been dropped (F-2).
Counter-metric 2 ("reconciliation drift … surfaced") has no FR producing that
surface for the pre-sync era; FR-35 later built one, outside this document.

**Fix:** Give each metric an instrument. Metric 2: count MCP tool-call sessions
per week that terminate without a `securities_list`-style bulk pull (server-side
observable). Metric 1: gate on FR-35's reconcile endpoint reporting zero
unexplained differences over N consecutive months — that is both measurable and
the missing detector for Counter-metric 1. Metric 3: name the discovery story's
acceptance criteria or drop the metric until FR-26 has one.

### F-10. OQ-8 misroutes the web UI's no-auth posture as a community question when it is a Phase-3 blocker

**Severity:** high
**Location:** NFR-4, OQ-8

> "**The web UI itself is unauthenticated by design** — an instance must run on a
> trusted network or behind reverse-proxy authentication … (optional built-in
> auth: OQ-8)."

> "OQ-8 … needed before any non-trusted-network deployment **or serious
> community adoption**; decide trigger condition."

Verified: `lib/portfolixir_web/router.ex`'s `:browser` pipeline has session,
CSRF, locale and view-scope plugs and no auth plug. Making that explicit was the
right fix for M-6. But the trigger condition OQ-8 leaves open is stated in terms
of deployment topology and adoption, and omits the one that actually forces the
decision: **Phase 3 parks live bank and broker credentials on the same box,
behind that unauthenticated UI**. Whatever the sync UI looks like — connect,
re-authenticate, trigger a pull — it is reachable by anyone who reaches the
port. "Trusted network" is doing enormous unexamined work here for a home LAN
with an always-on agent, guest devices, and a PhotoTAN flow. As currently
phrased, an implementer can enter Phase 3 with OQ-8 still open and be compliant
with this PRD.

Related overclaim: FR-28 says the journal makes an erroneous edit "always
detectable and **attributable**". The implementation is genuinely good — a
closed actor taxonomy (`:owner_ui | :api_token_rw | :api_token_ro |
:import_session | :system_job`) with append-only enforcement — but `:owner_ui`
is backed by no authentication whatsoever, so for UI writes "attributable"
means attributable to a label, not to a person. The FR should not claim more
than the auth posture can deliver.

**Fix:** Make OQ-8 a hard precondition of the Phase 3 scope gate, not an
open-ended trigger question, and add the credential-exposure rationale. Soften
FR-28 to "attributable to actor class; UI writes carry no identity while the UI
is unauthenticated (OQ-8)".

### F-11. FR-9 is five capabilities in one requirement, and its method still cannot answer the founding question

**Severity:** high
**Location:** FR-9, § 1 founding question, OQ-3, OQ-9

> "Benchmark comparison: any performance series can be compared against a
> configurable alternative … The comparison supports an after-cost / after-tax
> dimension … Index comparison scenarios include 'bought once and held' and 'as
> a savings plan'. [ASSUMPTION] Fixed-rate baseline first; index/security-series
> benchmarks — and with them the index scenarios — second (OQ-3)."

Two defects. **Sizing:** this single FR contains a fixed-rate baseline, an
index/security-series baseline, two index scenario shapes, an after-cost
dimension, and an after-tax dimension spanning three named German tax mechanics
whose depth is itself an open question (OQ-9). One `[ASSUMPTION]` tag splitting
it into "first/second" does not make it buildable; no architect can estimate it
and no reviewer can say when it is done.

**Method:** the June review's M-3 (medium, unresolved) observed that comparing a
TTWROR series against a flat 2 % line is apples-to-oranges — TTWROR deliberately
removes cash-flow timing, and "would I be richer in Tagesgeld?" depends entirely
on when the cash flowed. Bolting the after-tax dimension on has made this worse,
not better: capital-gains tax applies to realised money-weighted outcomes, not
to a time-weighted index of returns, so an "after-tax TTWROR vs. 2 %" number is
not merely imprecise but categorically ill-defined. This is the product's
headline analytic, served to an LLM that will restate it as fact.

**Fix:** Split FR-9 into at least three FRs (fixed-rate cash-flow-replay
baseline; index/security-series baseline with its scenario shapes; after-cost
and after-tax overlays). Specify the method in the FR itself: replay the actual
cash flows into the alternative and compare end wealth or IRR. If v1 ships the
TTWROR-vs-rate approximation, require the caveat to be embedded in the
self-describing response per FR-13, not left in a planning document.

### F-12. The persona is labelled fictional while carrying the maintainer's real broker, bank, strategy and pension profile

**Severity:** high
**Location:** § 2 Users, UJ-2, FR-17/18/19, Success Metric 3, addendum § "Investor profile"

> "The operator-investor ('Alex' — **fictional persona name**). Self-hosts the
> app; invests with a deliberate **maximum risk performance** strategy (stocks
> and Bitcoin) over a long horizon and plans retirement under German pension
> rules. Maintains a second household portfolio…"

The label is narrowly true (the *name* is invented) and broadly misleading. The
surrounding document identifies the person: § 1 says "the owner does not read
code"; the addendum's "Investor profile (persona depth, **anonymized**)" repeats
the same maximum-risk stocks-plus-Bitcoin strategy as fact about the real
operator; UJ-2 opens "A **comdirect statement arrives**"; the decision log
records the sync providers as "**operator-stated must-have**" and "Sync provider
scope **confirmed**: comdirect (depot), bunq (cash accounts), bitcoin.de (BTC
trades)". AGENTS.md forbids exactly this: "The maintainer's personal banking
relationships … which banks/brokers hold their accounts" and "Never label test
data or examples as 'the owner's real case' — synthetic data must be synthetic
all the way down". Naming comdirect as a generic integration target is
explicitly permitted; attaching it to the operator's own arriving statement is
the case the rule prohibits. Success Metric 3's "runs on **real pension data**"
completes the picture. This is a public repository, and the June 2026 redaction
pass (decision log, 2026-06-13) rewrote branch history specifically to remove
this class of content — but retained the parts that, combined, still identify
one person's broker, bank, crypto venue, risk posture, household structure and
retirement plan.

The decision log's "Product scope (provider integrations as planned features)
intentionally retained" is a recorded, defensible decision **for the FR-17..21
roadmap entries**. It does not cover UJ-2's first-person statement arrival, § 2's
investor profile, or the addendum's strategy paragraph.

**Fix:** Make the persona genuinely fictional or drop the label. Rewrite UJ-2 to
"A broker statement arrives" and § 2 to a strategy-neutral operator description;
move the risk-posture detail out of the repo. Keep FR-17/18/19 as named
integration targets — that is the recorded and permitted decision — but sever
them from the operator's own accounts. Reword Success Metric 3 to avoid "real
pension data".

### F-13. The triage claim "no phase-blockers among OQ-1..8" is false for OQ-1

**Severity:** medium
**Location:** OQ-1 vs. § 4 Phase 1; decision log 2026-06-12 "Triage"

> "**OQ-1** Phase 3 + FR-5(XML) + FR-12 scope ADR: exact wording of the AGENTS.md
> amendment … Owner: maintainer, **before the first affected story**."

The decision log asserts "no phase-blockers among OQ-1..8; all deferred with
owner + revisit condition". But § 4 schedules "PP XML full import (#333)" inside
**Phase 1 — now**, and FR-5's own gate says XML intake cannot begin without
OQ-1's deliverable. An open question that must be answered before the current
phase's work can start is the definition of a phase blocker. (The FR-12 third of
OQ-1 has since resolved via ADR-0023; the XML third has not — `epics.md` still
lists FR-5 as `gated`.) The consequence is that Phase 1 reads as executable when
part of it is not, and a batch planner will schedule #333 into a sprint it
cannot legally start.

**Fix:** Split OQ-1 into its three independent halves, mark the XML half as a
Phase-1 blocker with a due-by, and record ADR-0023 as closing the FR-12 half.

### F-14. NFR-2's "immutable inputs" is factually wrong, and it is the load-bearing word

**Severity:** medium
**Location:** NFR-2

> "**Auditability:** every number is reproducible from immutable inputs; editing
> is allowed, hidden state is not"

The sentence contradicts itself in eleven words, and the second half is the true
one. `project-context.md` states the rule explicitly: "Editing IS allowed
(`update_transaction/2`, `delete_transaction/1`): auditability = reproducibility
from inputs, **not append-only immutability** — do not build soft-delete
workarounds." The inputs are mutable; what is immutable is the *journal of
changes to them* (ADR-0017). Getting this backwards in the NFR that defines the
product's central quality claim invites an implementer to either build the
soft-delete workaround project-context explicitly forbids, or to assume
reproducibility guarantees that the schema does not provide.

**Fix:** "Every number is reproducible from the ledger as it stands, and every
change to the ledger is recorded in the append-only audit journal (FR-28).
Ledger records are editable; edits are never hidden."

### F-15. FR-27's flagship journey has an unfunded historical-quote dependency

**Severity:** medium
**Location:** FR-27, UJ-5, OQ-3

> "UJ-5 … 'If I had blindly bought €1k of every tip since January — where would I
> be?' The what-if engine simulates virtual trades against **real quote
> history**"

Blind-follow backtesting needs price history from each tip date for securities
the operator has **never held** — a different acquisition problem (breadth,
depth, provider terms) than maintaining quotes for the current portfolio, and
one that ADR-0005's provider split was not designed for. OQ-3 covers index
series for FR-9 benchmarks only. The June review raised this as M-4; it was
rated medium, so the "all criticals/highs fixed" claim does not cover it — but
it remains an unowned architecture dependency behind a journey the PRD showcases
and a Phase-5 FR with an issue already assigned (#332).

**Fix:** Add an OQ (source, depth, retention, licence, ADR-0005 fit) for
historical-quote acquisition for never-held securities, owned before the first
FR-27 story. Same treatment for FR-20's chain-data source, which has the same
shape and the same silence (June M-5, also unaddressed).

### F-16. Requirements whose acceptance is a matter of opinion

**Severity:** medium
**Location:** FR-13, FR-15, FR-16, NFR-1, NFR-8

- **FR-13** — "**Every analytic the app computes** is exposed via JSON API and
  MCP". Universally quantified over a set the document never enumerates. No
  reviewer can prove compliance or breach; there is no register of analytics.
- **FR-15** — "Tool descriptions are **written for LLM tool-choice**". No
  criterion, no evaluation method. It is a taste statement in an FR slot.
  (FR-33's "slim projection … so logos/timestamps don't ride along" shows what a
  falsifiable version of this looks like.)
- **FR-16** — "parity between API and MCP is **reviewed every PR**". This is a
  process, not a product requirement, and `project-context.md` lists
  "API/MCP parity gate" under **"Deliberately NOT adopted … stays a PR-review
  checklist item"**. So the PRD's only enforcement for its central integration
  invariant is the one mechanism the project decided not to mechanise — in a
  document that calls mechanical guards load-bearing (see F-4).
- **NFR-8** — "p95 < 2 s … at realistic scale". Falsifiable in principle, but
  `project-context.md` also lists "performance/load gates" as deliberately not
  adopted, so nothing measures it. A number with no instrument is a wish.
- **NFR-1** — "Correctness over features" is a value statement, not a
  requirement; the release-blocking content is in the clause that follows it.

**Fix:** FR-13 → require a machine-readable analytics register that the parity
check runs against. FR-15 → state the measurable property (e.g. every tool
description names its precondition and its paging bound; response size ceiling).
FR-16 → move the process to the workflow doc and keep only the invariant here.
NFR-8 → either name the benchmark harness and dataset or mark it aspirational.

### F-17. The positioning moat rests on one uncited search, and reads the evidence backwards

**Severity:** medium
**Location:** § 1 "Positioning (research snapshot, 2026-06)"

> "As of the June 2026 landscape research, **no tool was found** that combines
> Portfolixir's four differentiators … German retirement modeling (**no
> open-source coverage found**)"

The only backing is the decision log's "Market research digest (web subagent)" —
no artifact, no method, no search scope, no list of tools examined. The claim is
an unfalsifiable negative doing strategic work: it is the justification for
Phases 4 and 5, the most expensive part of the roadmap. And the German-pension
datum is interpreted as opportunity when the far likelier reading is cost —
annually revalued parameters, retroactive legislation, and a wrongness mode that
is silent (see F-5). The section is at least honest about the weakest item
("Target-weight rebalancing alone is the weakest moat"), which makes the
unexamined optimism about the strongest claim more conspicuous.

**Fix:** Either attach the research artifact (tools evaluated, date, method) as a
linked file, or downgrade the section to "no comparable tool known to the
maintainer as of 2026-06" and stop calling it research. Add the cost reading of
the pension gap alongside the opportunity reading.

### F-18. "Launch-grade" and "production-grade" collide with a hard rule the PRD never mentions

**Severity:** medium
**Location:** § 1 "Stakes and quality bar"; addendum § "Tech-stack motivation"

> "at a quality grade that lets others adopt it" / decision log: "**launch-grade**
> quality bar from the start" / addendum: "modern AI-driven development methods
> are part of the product's point, with **production-grade discipline**."

AGENTS.md hard rule: "**Do not claim production readiness.**" The PRD's framing
walks right up to it and, in the addendum, arguably past it. This is not
pedantry: the quality-bar framing is what licenses Phase 3's credential storage,
the "future self-hosters" persona, and the business-option-stays-open posture,
all on a deployment with an unauthenticated web UI (F-10) and no release,
versioning or upgrade requirement anywhere (the June review's L-3, still
unaddressed). Either the rule is stale and should be amended, or the framing is.

**Fix:** Distinguish explicitly between *engineering discipline* (which is what
the evidence supports and what the addendum means) and *production readiness*
(which AGENTS.md forbids claiming), in one sentence, and cite the rule so the
reconciliation is visible. Add the missing release/upgrade NFR or state that the
self-hoster persona is dormant until it exists.

### F-19. FR-11/FR-12 left "drift" undefined in sign and unit, and it cost a breaking API change

**Severity:** medium
**Location:** FR-11, FR-12, § 9 Glossary

> "FR-12 … **Primary ranking criterion: drift magnitude against target weights**"

> Glossary: "Drift | Deviation of actual category weight from its target weight"

Neither the FR nor the glossary states the sign convention or the unit.
"Deviation of actual from target" is ambiguous enough that the implementation
chose `target − actual`, the owner read it the other way, and ADR-0023 §1 had to
flip the convention across the Allocation module, the UI, the JSON API, the MCP
tool schemas and the docs — "a **breaking API change**". The unit is still
unspecified: ranking by percentage-point deviation and ranking by absolute
currency deviation produce different orderings, and FR-12's ranking is the
product's decision output. This is the concrete, already-paid downstream cost of
under-specified capability language, and the same ambiguity is still live for
FR-12's ranking.

**Fix:** Pin both in the glossary: drift = `actual_weight − target_weight`
(positive = overweight, per ADR-0023) and state whether FR-12 ranks on relative
weight deviation or absolute currency deviation — or on both, with the primary
named.

### F-20. No requirement addresses data freshness, so UJ-1's briefing can be confidently stale

**Severity:** low
**Location:** FR-13, UJ-1, NFR-8

> "FR-13 … responses are self-describing: method, **as-of date**, currency, and
> conversion basis stated"

An as-of date helps only an agent that checks it and knows what "too old" means.
Nothing requires a staleness flag, a newest-quote age, a last-FX-update
indicator, or a threshold beyond which a response self-marks as stale. UJ-1's
"Total round trip: seconds, zero exports" will happily report a valuation built
on last week's prices with no signal that anything is off. This was the June
review's M-7; it was rated medium and never fixed.

**Fix:** Extend FR-13: every valuation-bearing response carries the age of its
newest input quote and FX rate, and self-marks stale beyond a configured
threshold.

## Claimed-fix audit

The decision log (2026-06-12, "Reviewer gate (finalize)") states: "All
criticals/highs and reconciliation gaps fixed in one revision."

| Old | Title | Status in current `prd.md` |
|---|---|---|
| C-1 | No audit trail for an LLM that edits financial records | **Resolved.** FR-28 added and well specified; ADR-0017 accepted and the journal shipped (`Portfolixir.Actor` closed taxonomy, `audit_journal` append-only, arming migrations for securities/portfolios/accounts/assignments/transactions/classifications/targets). One residual overclaim, see F-10. |
| C-2 | No backup/restore/export while retiring the redundant source of truth | **Regressed.** FR-29 was added as claimed, then rescoped by owner decision on 2026-07-22 (#354) to `pg_dump` only with the PP export dropped. The PRD still promises the dropped capability in FR-29, UJ-2 and Metric 1, and still rests the "safe to retire external copies" argument on it. See F-2. |
| H-1 | "Read-only sync" is a behavioural promise, not a security property | **Resolved.** FR-21 reworded honestly ("read-only as implemented and audited in this codebase", write-capable credentials acknowledged, key-management limits "documented rather than overpromised"); OQ-6 added for the PhotoTAN/unattended question. |
| H-2 | The scope gate is self-amended paper with no mechanical backstop | **Not fixed.** No meta-test requirement was added; NFR-3 still specifies process only. Not mentioned in the decision log's fix list despite the blanket claim. See F-4. |
| H-3 | FR-5 (XML) and FR-12 forbidden by AGENTS.md, no gate annotation | **Resolved for the two named FRs** — both now carry scope-gate notes. Not generalised: four other FRs sit on the "no advanced reports" rule with no annotation (F-6), and FR-12's boundary now diverges from the ADR that closed its gate (F-7). |
| H-4 | Counter-metric violated by the repo's baseline on day zero | **Resolved.** Reworded to "gates are never weakened to ship a feature — grandfathered baselines … only ratchet downward", which matches `project-context.md`. |
| H-5 | Metric 1 dismantles the detection mechanism for Counter-metric 1 | **Not fixed.** The applied change (gating Metric 1 on FR-29) addresses egress, not verification, and FR-29's verification half has since been dropped. The counter-metric is still unfalsifiable once Metric 1 is achieved. FR-35 later built the missing detector, outside this document. See F-9. |
| H-6 | FR-14 understates the live write surface and specifies no failure modes | **Partial / cosmetic.** Only the audit-journal clause was appended. Delete still unlisted; no idempotency keys, no dry-run, no runaway bound. See F-3. |
| H-7 | German pension modelling sold as a moat without acknowledging legal churn | **Not fixed.** FR-24/FR-25 unchanged; no assumption block, no parameter-table requirement, no OQ for update ownership. Not mentioned in the decision log's fix list. FR-36/ADR-0031 later built the machinery this asked for. See F-5. |

Score: 4 of 9 genuinely resolved, 1 resolved-then-regressed, 1 cosmetic, 3
untouched. The blanket claim in the decision log is not accurate, and because the
log is described as the "canonical memory and audit trail", the inaccuracy is
load-bearing — it is what any future reviewer will trust instead of re-reading.

## Mechanical notes

- Frontmatter says `updated: 2026-06-12`, but the decision log records a
  privacy-redaction pass on **2026-06-13** and a post-architecture FR-9/OQ-9
  update run. The `updated` field is wrong on the document's own evidence, and
  `status: final` has been wrong since 2026-07-12 at the latest.
- The decision log's last entry is 2026-06-13. The FR-29 rescope (2026-07-22),
  ADR-0023 (2026-07-03), ADR-0024 (2026-07-12) and FR-30..36 are all absent,
  contradicting its opening claim to record "every decision, change, and
  override".
- § 4: "each phase ships in **story-sized increments** per the roadmap (#321)" —
  superseded by ADR-0026 (2026-07-12), which makes epic batches the default
  delivery unit.
- § 5: "Where a GitHub issue exists it is referenced (**about two-thirds of FRs
  today**)". The June review's M-2 asked for a per-FR → issue table; one was
  built, in `epics.md` (lines 143–179). The PRD still carries the vague fraction
  and no pointer to the table.
- § 4 intro: "Phases are sequential priorities, **not strict gates**" — except
  Phase 3, FR-5(XML) and FR-12, which are strict gates. The June review's L-2;
  still unreconciled.
- FR numbering interleaves by section (A: FR-1..4 then FR-28; B: FR-5..7 then
  FR-29). Deliberate under the append-never-renumber rule, but there is no note
  saying so; a reader reasonably assumes an editing error.
- Glossary omits terms the product now depends on: bucket, view, SOLL plan,
  balance snapshot vs. balance adjustment naming (`project-context.md` warns
  that ADR-0009's "snapshot" is spelled `balance_adjustment` in data — the
  glossary entry mentions both but does not flag the trap).
- FR-11 marks "SOLL/IST drift per category **(shipped)**" without noting that
  ADR-0023 shipped a breaking sign flip on that surface — an API consumer
  reading the PRD gets the old semantics.
- UJ-1's "Total round trip: **seconds**" and NFR-8's "p95 < 2 s" are different
  claims (a multi-tool agent round trip vs. a single response) and neither
  references the other.
- Addendum § "Future visions": "Algotrading on top of the data backbone" is
  listed as Zukunftsmusik with no scope-gate note, while § 4 correctly marks it
  "forbidden until a dedicated scope decision". Add the same note in the
  addendum so it cannot be quoted out of context.
- `project-context.md` line 197 still requires a `Model:`/`Thinking level:`
  commit footer, which the current `AGENTS.md` and `CLAUDE.md` now forbid. Not a
  PRD defect, but it will confuse any agent that reads both — worth a separate
  fix.
