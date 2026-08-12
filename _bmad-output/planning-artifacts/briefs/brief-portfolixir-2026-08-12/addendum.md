# Addendum — Portfolixir product brief, 2026-08-12

Depth that belongs to downstream documents — the PRD update, ADRs,
`AGENTS.md` amendments and `README.md` — rather than to the brief itself.
Nothing here decides anything the brief did not, with one exception noted at
its place: the maintenance lane is an owner decision of 2026-08-12 that has no
home in the brief. Sections are ordered by downstream artifact; each names the
gate it serves, where the gate IDs resolve in
`planning-artifacts/feedback-triage-2026-08-12.md`.

**Evidence base and privacy.** The brief's Problem section draws its drift cases
and call counts from the portfolio agent's requirements document (2026-08-11) as
triaged in `feedback-triage-2026-08-12.md`. Real figures, positions, policy
thresholds and personal names from that source are deliberately absent from both
files; only the *shape* of each failure is carried across.

## For the PRD update (gate B3.1)

The PRD is the first artifact to change, and this is the material it needs
beyond the brief. Numbering note: FR-36 is the highest requirement in the
current document, so new requirements start at FR-37.

**New requirements from the scope ladder.** Levels (a)–(c) become requirement
families, not one requirement each:

- **(a) derived metrics** — per security (moving averages, realized volatility,
  drawdown, momentum, distance to extremes) and per portfolio or view
  (volatility, risk-adjusted return, maximum drawdown with its window,
  correlation among the largest positions). The existing risk and concentration
  endpoint is the shape to extend, not a thing to replace.
- **(b) comparison and decomposition** — benchmark comparison is already
  tracked as an open issue and needs no new requirement, only a pointer;
  contribution analysis (which position produced how much of the return) and
  factor, sector and region exposure are new.
- **(c) evaluation of decisions** — prediction calibration and rule evaluation.
  Both depend on the knowledge objects below existing first.

**New requirements for read ergonomics.** One family, and the cheapest work in
the whole programme: per-endpoint field selection and projections, roll-up-only
aggregates that omit positions, server-side threshold filters so the caller
receives the deviating rows rather than all of them, and `?since=` delta reads.
Acceptance is measurable — the agent-side criteria in the brief attach here.
Constraint to carry into the requirement: field selection is a validated
per-endpoint whitelist, never a passthrough to a query builder and never an
atom created from input.

**New requirements for the knowledge objects.** Four objects, each needing
identity, provenance and an as-of, each needing API and MCP surface:

| Object | Carries | Depends on |
|---|---|---|
| Policy rule | type (cap / floor / warning band / protected / budget), scope (category, bucket, security), threshold, severity, validity period, history | its own ADR (gate B3.6) |
| Security event | security, type, date, timing qualifier, confirmed flag, source, source quality, checked-at, note | applies to **every** security in the catalog, not only held ones (gate B3.4) |
| Thesis / conviction | thesis text, status, conviction tier, invalidation condition, time stop, last reviewed and by whom, history | the identity decision only |
| Prediction | thesis, stated probability, check date, invalidation, action if right, action if wrong, outcome, resolved-at, resolution note | feeds the calibration report |

The three queries the thesis object must answer are its acceptance criteria in
disguise: theses unreviewed for 90+ days, positions whose thesis is damaged,
and time stops falling due in the next 30 days.

**A sequencing dependency the PRD must state.** The audit-journal rollout is
incomplete — Catalog and FX are armed; Portfolios, Classifications, Ledger and
Imports still write unjournaled — and MCP *write* tools are deliberately blocked
behind it, so that no agent can edit financial data without an audit trail. The
owner has since decided that the agent is the primary write path for tax data,
and this brief adds four more agent-written objects. **Completing the rollout is
therefore a prerequisite for the knowledge objects, not a parallel nicety.**

**What the PRD must not absorb:** limit-price suggestions and estimated
per-trade tax (both cut from the rebalancing digest's first version — see
Parked), and anything from the gated list in the brief's Scope section.

## For the `AGENTS.md` amendment (gate B3.1)

**Project Goal — two edits.** First, the two-audience statement from the brief's
"Who This Serves" section is added at the top of the numbered goals, which
currently enumerate twelve record-keeping and valuation capabilities and read as
a small local tracker. Second — and in a different section of the file — the
ladder from the brief's Scope replaces the blanket Hard Rule *"Do not add
advanced reports or advanced classifications."* The permanent non-goals stay
exactly as they are; they are the part of the old text that was always right.

**API and MCP Coverage becomes symmetric.** Today: *"Every new user-visible
function must include API and MCP coverage, or the PR must explicitly document
why coverage is not applicable."* The amendment adds the matching obligation in
the other direction — an agent-only capability may ship without a human view
when the PR says why — and pairs it with the deadline that keeps it honest: the
view lands in the same or the next batch, and its absence after that is a
close-out finding. Rationale, not amendment text: without the deadline the rule
degrades into "agent only, forever", which would hollow out the operator half of
the identity this brief establishes.

**Every metric documents its computation basis.** Each metric in ladder levels
(a)–(c) states, in its API and MCP payload: the input series, the window, the
reference series or benchmark where one exists, and the treatment of gaps. This
is a review gate in the Story Workflow, not a documentation task — a metric
whose basis is unstated cannot be reviewed, because there is nothing to check
the implementation against. The existing risk and concentration endpoint is the
precedent: responses that state their own basis. _Open for the amendment author:
whether the UI must surface the basis as well, or may leave it to the ⓘ
tooltip pattern._

**Machine-extracted data is a proposal until confirmed.** Standing rule,
independent of whether a local model is ever adopted: anything extracted from an
unstructured source carries its source link and a `machine_generated` marker,
and lands only after a human or an agent confirms it — the same preview-then-
apply shape the Portfolio Performance import already uses.

**The Epic-Batch Workflow gains a maintenance lane** (owner decision,
2026-08-12; recorded here because it has no home in the brief). Every batch
carries a lane that reviews available updates for Hex, npm, Elixir/OTP,
Postgres, BMAD and the external BMAD modules, applies what passes the gates, and
reports what it deliberately did not update — attaching to step 5, the
bookkeeping close-out. It is an `AGENTS.md` step, not a scheduling habit; habits
depend on someone remembering.

## For the derived-value ADR (gate B3.2)

**Its relationship to the existing ADRs must be stated explicitly, because it
overturns one of them.** ADR-0032 defines the current memo as volatile — it
never survives a restart and never becomes a source of truth — and a durable
layer directly reverses that, so the new ADR **supersedes or amends ADR-0032**
rather than sitting beside it. Invariant 2 below *is* ADR-0032's data-version
mechanism and invariant 3 *is* its as-of labelling rule; both are inherited, not
invented. ADR-0035 is the adjacent precedent that must also be addressed: it
deliberately chose to *remove* redundant computation rather than cache it, and
the new ADR should say why that choice does not extend to this case. ADR-0004
is the constraint invariant 1 protects.

The five invariants, carried here so the ADR starts from them:

1. **Rebuildable from transactions alone**; drop-and-rebuild is a supported,
   tested operation. This is what keeps ADR-0004's guarantee intact — the layer
   is a materialization of the single truth, not a second copy that could
   disagree.
2. **Versioned** against the existing data-version counter, so staleness is
   detectable rather than merely suspected.
3. **Never silent about freshness:** `as_of` plus an explicit stale marker, in
   the UI *and* in the API/MCP payload. The Sprint 5 value-slot vocabulary
   (pending / settling / final / not-computable) is the UI half and already
   exists; the payload half does not.
4. **Never authoritative for a write.** No booking, import decision or
   consistency finding may read the derived layer instead of the ledger.
5. **The ADR decides *which* values are materialized** and says no to the rest.
   "Everything" is not an answer.

## For the README rewrite (gate B3.1, after the brief is accepted)

The README is this gate's public output. Scope: the opening definition rewritten
from the brief's Executive Summary, an introduction carrying two or three
concrete examples of what the tool is *for* (not a feature list), and a
consistency pass so `README.md`, the docs site landing page and `AGENTS.md` →
Project Goal state one identity. Tone follows the audience decision — "your
holdings, your agent, your machine", not "the data layer for portfolio agents".
The screenshot and tour section stays; it already does its job.

The honest test of the gate: if the identity cannot be stated in one short
README paragraph a stranger understands in fifteen seconds, the decision is not
finished.

## Parked, with reasons

- **Backtesting** (ladder level (d)) — a rule test-bench without rule objects is
  premature; revisit after the policy-rules work (gate B3.6).
- **Data acquisition beyond quotes and FX** (gate B3.3) — needs its own gate
  covering sources, failure behavior, retention (the agent's own stated
  boundary: condensed dated signals with source links, never a full-text
  archive) and collector health, so that a dead collector is visibly dead within
  a day instead of producing false calm.
- **Push delivery to external endpoints** (gate B3.7) — request-forgery surface,
  stored secrets and retry semantics make it a security decision; the
  pull-based alarm list delivers most of the value without it.
- **Limit-price suggestions and estimated per-trade tax** (gate B3.5) — cut from
  the rebalancing digest's first version. The first is order preparation rather
  than allocation guidance and needs its own decision against ADR-0023; the
  second needs a documented method before it can be a number on a screen, and
  forward tax projection was already deferred behind its own gate.
- **Multi-tenancy** — **declined for this brief's horizon, and that is a
  stronger state than parked.** Buckets and views already scope holdings within
  one instance, and the brief states single-operator as identity. It is not on
  the permanent non-goals list, because the owner declined it rather than
  forbidding it forever; a future reversal would start from the wealth-vision
  parking-lot issue, not from this brief.
- **A local model inside the application** (gate B3.8) — the owner's intent is
  narrower than a general capability: offload simple jobs to a weaker local
  model to save tokens, and only where a tool cannot do the job better. The
  question is therefore not whether a local model is permitted. That ordering,
  and the constraints under it, are the whole design:
  1. **deterministic code first** — a parser, a query or an existing tool beats
     a model on any job it can do at all, and cannot invent;
  2. **a model only as fallback** for genuinely unstructured input;
  3. **structuring only**, never judgment about money;
  4. **output is a proposal** carrying its source and a `machine_generated`
     marker (the standing rule above), confirmed before it lands;
  5. **the only use approved so far is ADR-0021's PDF intake** — build that, and
     judge further uses against real experience.

  So the eventual ADR asks "when is a local model the correct implementation
  choice", and its default answer is "rarely".
