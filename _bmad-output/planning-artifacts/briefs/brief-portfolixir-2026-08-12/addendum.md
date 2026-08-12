# Addendum — Portfolixir product brief, 2026-08-12

Depth that belongs to downstream documents (PRD, ADRs, `AGENTS.md` amendments)
rather than to the brief itself. Nothing here is a new decision; it is the
detail behind the brief's compressed statements.

## For the `AGENTS.md` amendment

**Project Goal.** The current text enumerates twelve record-keeping and
valuation capabilities and reads as a small local tracker. It needs the
two-audience statement at the top and the ladder from the brief's Scope section
replacing the blanket "Do not add advanced reports or advanced classifications"
Hard Rule. The permanent non-goals stay exactly as they are — they are the part
of the old text that was always right.

**API and MCP Coverage becomes two-way.** Today: *"Every new user-visible
function must include API and MCP coverage, or the PR must explicitly document
why coverage is not applicable."* The amendment adds the reverse direction — an
agent-only capability may ship without a human view when the PR says why — and
pairs it with the deadline that keeps it honest: the view lands in the same or
the next batch, and its absence after that is a close-out finding. Without the
deadline this rule degrades into "agent only, forever", which would hollow out
the operator half of the identity this brief establishes.

**Epic-Batch Workflow gains a maintenance lane.** Owner decision 2026-08-12:
every batch carries a lane covering hex, npm, Elixir/OTP, Postgres, BMAD and the
external BMAD modules, reporting what it deliberately did not update. It is an
`AGENTS.md` step, not a scheduling habit — habits depend on someone remembering.

## Metric basis documentation (the quality bar, in practice)

Every metric in ladder levels (a)–(c) publishes: the input series, the window,
the reference where one exists, and the treatment of gaps. This is a review
gate, not a docs task — a metric whose basis is not stated cannot be reviewed,
because there is nothing to check the implementation against. The existing
risk/concentration endpoint is the shape to follow: self-describing responses
that state their own basis.

## The derived-value layer — invariants for its ADR (gate B3.2)

Carried here so the ADR starts from them rather than rediscovering them:

1. Rebuildable from transactions alone; drop-and-rebuild is a supported, tested
   operation. This is what keeps ADR-0004's guarantee intact — the layer is a
   materialization of the single truth, not a second copy that could disagree.
2. Versioned against the existing data-version counter, so staleness is
   detectable rather than merely suspected.
3. Never silent about freshness: `as_of` plus an explicit stale marker, in the
   UI *and* in the API/MCP payload. The Sprint 5 value-slot vocabulary
   (pending / settling / final / not-computable) is the UI half and already
   exists; the payload half does not.
4. Never authoritative for a write. No booking, import decision or consistency
   finding may read the derived layer instead of the ledger.
5. The ADR decides *which* values are materialized and says no to the rest.
   "Everything" is not an answer.

## The local model — why the permission question is the wrong question

The owner's intent is narrower than a general capability: offload simple jobs to
a weaker local model to save tokens, and only where a tool cannot do the job
better. That ordering is the whole design:

1. deterministic code first — a parser, a query or an existing tool beats a
   model on any job it can do at all, and cannot invent;
2. a model only as fallback for genuinely unstructured input;
3. structuring only, never judgment about money;
4. output is a proposal carrying its source and a `machine_generated` marker,
   confirmed before it lands — the same preview-then-apply shape the PP import
   already uses;
5. the first and only currently gated use is ADR-0021's PDF intake.

So the eventual ADR asks "when is a local model the correct implementation
choice", and its default answer is "rarely".

## README scope, when that story comes

The README is this gate's public output. Scope: the opening definition rewritten
from the brief's Executive Summary, an introduction carrying a few concrete
worked examples of what the tool is *for* (not a feature list), and a
consistency pass so `README.md`, the docs site landing page and `AGENTS.md` →
Project Goal state one identity. Tone follows the audience decision — "your
holdings, your agent, your machine", not "the data layer for portfolio agents".
The screenshot and tour section stays; it already does its job.

The honest test of the gate: if the identity cannot be stated in one short
README paragraph a stranger understands in fifteen seconds, the decision is not
finished.

## Parked, with reasons

- **Backtesting** (ladder level d) — a rule test-bench without rule objects is
  premature; revisit after the policy-rules work.
- **Data acquisition beyond quotes and FX** — needs its own gate covering
  sources, failure behaviour, retention (the agent's own non-goal: condensed
  dated signals with source links, never a full-text archive) and collector
  health, so that a dead collector is visibly dead within a day instead of
  producing false calm.
- **Push delivery to external endpoints** — request-forgery surface, stored
  secrets and retry semantics make it a security decision; the pull-based alarm
  list delivers most of the value without it.
- **Multi-tenancy** — declined. Buckets and views already scope holdings within
  one instance; true multi-user stays in the parking lot.
- **Limit-price suggestions and estimated per-trade tax** — cut from the
  rebalancing digest's first version. The first is order preparation rather than
  allocation guidance and needs its own decision; the second needs a documented
  method before it can be a number on a screen.

## Evidence base

The problem section's drift cases and call counts come from the portfolio
agent's requirements document (2026-08-11) as triaged in
`planning-artifacts/feedback-triage-2026-08-12.md`. Real figures, positions,
policy thresholds and personal names from that source are deliberately absent
here and from the brief; only the *shape* of each failure is carried across.
