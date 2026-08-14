# Sprint Plan — Sprint 6 (ADOPTED, 2026-08-12)

**Status: adopted.** This plan supersedes
`sprint-plan-2026-08-12-sprint6-draft.md` and answers its three open questions.
OQ-1 was decided by the owner; OQ-2 and OQ-3 were delegated to the batch agent
and are decided here, with the reasoning recorded so the calls can be
overturned on their merits rather than re-argued from scratch.

Ground truth: `main` at `541fb89`. Verified against the merge commits, the open
pull-request list (empty), the open-issue list (46 open) and the Actions runs on
`main`.

## Decisions (2026-08-12)

**OQ-1 — ADR-0039 is signed off (owner).** Gate B3.2 is closed. The ADR flips
from *Proposed* to *Accepted* in this batch's first commit, ADR-0032 becomes
*Superseded by ADR-0039*, and Lane C runs as specified. The owner also asked why
an ADR sat on `main` in *Proposed* state at all; the answer and the guard are in
"On merged-but-Proposed ADRs" below.

**OQ-2 — Lane A ships the eleven alignment and defect issues; #672 and #414
stay out (batch agent).** With Lane C confirmed, this sprint already carries a
new subsystem with projection semantics and its own invariant suite. Adding two
new-surface builds on top would make it the largest batch attempted here, with
one reviewer, and ADR-0036 exists precisely because reviewer capacity — not
agent capacity — is the binding constraint. The honest consequence is stated
rather than hidden: **after Sprint 6 the UI is aligned but not finished.**
Sprint 7 is therefore committed as the UI-closing sprint (#672, #414 and
whatever Lane A's UAT surfaces), so "endlich abschließen" gets a date instead of
a hope.

**OQ-3 — #572 benchmark comparison stays out (batch agent).** Three reasons,
in order of weight:

1. **It is not specified yet.** #572's own body carries three unresolved design
   questions — benchmark data source, comparison semantics (TTWROR overlay vs.
   the "invested like the portfolio" number that actually answers the owner's
   question), and presentation. Per the Issue Tracking Convention the
   authoritative spec lives in an ADR or the epics document, and for #572 it
   does not exist yet. Starting it would mean deciding the semantics in
   implementation.
2. **Its inflation/CPI half needs a data source that is not quotes or FX**,
   which is gate B3.3 and still closed. Index proxies via existing quote
   providers are fine; CPI is not, and the issue treats them as one feature.
3. **Two money-domain heavyweights in one batch.** Lane C is risk-tier
   projection semantics. Benchmark comparison is money-domain analytics. Pairing
   them is the WIP problem ADR-0036 was written about.

Recommendation attached to the deferral: Sprint 7 or 8, preceded by a short ADR
section settling #572's three questions — most cheaply as a section of an
existing analytics decision rather than a gate of its own, since FR-9 is already
ungated by the scope ladder as level (b).

## Batch topology

Carried forward from Sprint 5, unchanged: **all lanes in ONE batch** on one epic
branch, **one PR for the sprint**, a lane split into its own PR only if it turns
out big during the batch — decided up front, flagged in the reviewer briefing
rather than asked mid-sprint.

## On merged-but-Proposed ADRs

The owner's objection — *an ADR should not sit on `main` in "Proposed" state* —
is worth recording, because the answer is a mechanism and the objection is still
half right.

The mechanism: ADR-0026 step 1 makes the ADR itself the decision-gate artifact.
It is drafted, reviewed and merged so the owner has something concrete and
citable to sign off on, and a **separate later commit flips the status**. That
is the established path here — ADR-0033 was flipped by `58c90f5`, ADR-0031 by
the Sprint 1 batch after gate #612. Merging it as *Proposed* is what makes the
signature a real event rather than a formality.

Where the objection lands: a merged ADR at *Proposed* is easy to misread as
decided, and nothing but the status line separates the two. Three guards apply,
and all three held this time:

- the status line is the single truth, and the ADR index repeats it;
- no work is scheduled behind an unsigned gate — the Sprint 6 draft put Lane C
  behind OQ-1 rather than starting it;
- the flip is its own commit with the sign-off date, so the decision has a
  timestamp.

No process change follows. If the pattern keeps causing this question, the
cheapest fix is a status badge at the top of the ADR index rather than changing
when ADRs merge.

## Lanes

### Lane Z — Close-out debt from Sprint 5 (first, it is minutes)

- **Push the v0.5.0 tag.** The Sprint 5 close-out records an annotated tag on
  `73affc5` triggering the release workflow. The remote carries exactly one tag
  (`before-agentic-run`) and the repository has **zero releases**, so ADR-0026
  step 5 is incomplete for Sprint 5 and the #659 automation has never run.
  Push it, confirm the workflow produces the release, and fix the workflow if it
  does not — an automation whose first real exercise is the Sprint 6 close-out
  is an automation nobody has tested.
- **#682** — intermittent multi-test failure bursts, *make them capturable
  first*. Diagnosis before fix by its own title; #654's test-failure artifact is
  the instrument. Rides here if it stays cheap, drops out if it does not.

### Lane B — The agent's feature requests (ship-now, no gate)

- **#664 — verify a PP re-import preserves classification, target weights, notes
  and attributes.** Runs **early**, before the rest of the lane. Story 18.2
  shipped this guarantee with a golden-path test; this re-tests it against
  today's code. A confirmed regression is the most urgent defect on the board
  and re-sequences everything after it. Risk-tier attention.
- **#665 (FR-37) — read ergonomics.** Per-endpoint field selection and
  projections, roll-up-only aggregates that omit position rows, server-side
  threshold filters. The constraint is part of the requirement: a validated
  per-endpoint whitelist, never a query-builder passthrough,
  `String.to_existing_atom/1` at the boundary. Acceptance is measured — −70 %
  response volume on the four heaviest reads plus a field inventory proving
  nothing load-bearing was cut. Supersedes FR-33's scope lock for this family
  only.
- **#666 (FR-38) — `?since=` delta reads.** The push half stays gated at B3.7
  and must not be scoped into this story; that boundary is its own acceptance
  criterion.
- **#667 — tax snapshot staleness warning and allowance-order entry.**
  Follow-up on the shipped E19 surface.

API and MCP together (AR-11). #665 and #666 are agent-visible capabilities and
may ship without a human view provided the PR says why — a commitment with a
deadline: the view lands in this or the next batch, and its absence after that
is a close-out finding. Any metric states its computation basis in the API *and*
MCP payload.

### Lane A — UI: close the design-language debt

Eleven issues, all alignment or defect work against a spec that already exists.

**A1 — the addressability cluster (first, it unblocks the rest):** #651
securities filters are not URL-addressable → #561 data-quality counts with a
path to fix (URL filters, missing logo/quote filters, bulk retriggers) → close
the Overview data-quality link that the Sprint 4 Lane A close-out recorded as
currently impossible.

**A2 — surfaces still off the design language,** one commit group each: #668
Wealth tabs (icons, touch-target floor, structural nesting carrier), #669
period selector and date picker, #670 contra-account value-setting UI, #671
snapshots view, #673 Overview "needs attention" card names its view and plan.

**A3 — remaining spec deviations:** #412 forms and inputs, #491 master-data
creation UX, #565 securities table configurable classification columns, #566
inline busy/result states replacing toasts, #564 wealth chart data table
summaries.

Design-critic review against the living spec is mandatory (ADR-0026 step 3 /
ADR-0038), and the Sprint 5 retro's evidence says the UAT persona on a live
server with screenshots is the only role that catches computed-style
regressions. Both run.

### Lane C — Durable derived values (ADR-0039, gate B3.2 closed)

Risk-tier: projection semantics. TDD first with exact `Decimal` expectations,
own commit groups, a dedicated verification pass on the invalidation invariant
in the agentic review, and an explicit callout in the reviewer briefing.

- **C0 — the status flip**, first commit: ADR-0039 → *Accepted*, ADR-0032 →
  *Superseded by ADR-0039*, index and the FR-1 / FR-39-40 registry rows updated.
- **C1 — the mechanism.** One derived-value axis with a lifetime parameter
  (`:none` / `:request` / `:durable`) over a versioned, named basis. ADR-0032's
  volatile memo becomes the `:request` case and stops existing as separate
  machinery.
- **C2 — the invariants before any activation.** ADR-0039 §5 is blocking and
  states its acceptance criteria as an equation, so they are tested as
  invariants — including the backdated-transaction invalidation case (I3) that
  naive implementations get wrong, and the write-path prohibition (I7).
- **C3 — first activation: the daily performance walk**, on the ADR's measured
  evidence (11.44 s at 200 securities / 4,001 bookings, second call identical to
  the first). Nothing else is activated by opinion; further activations are a
  configuration change plus a measurement.
- **C4 — freshness in the payload.** `as_of` plus an explicit stale marker, in
  the UI *and* in the API/MCP payload. Property 3 of the four binding ones, and
  the one both audiences actually see.
- **C5 — drop-and-rebuild as a single operator command** that reports its own
  runtime; the runtime is measured on operator hardware and recorded back into
  ADR-0039 as an amendment (§6).

ADR-0035 stays the first line of defence: a value that is merely computed more
often than necessary gets computed once, not materialized.

### Lane D — Agent affordance: the tax-refund path is undiscoverable

Added 2026-08-14 by owner report, filed as **#686**. **Re-scoped the same day
after the first diagnosis proved wrong** — the correction is recorded here
rather than quietly overwritten, because the way it was wrong is the reusable
lesson.

A sale that realises a loss refunds tax. Portfolixir models this correctly and
has all along: a separate `tax_refund` transaction, never a negative tax. The
kind is in live use — most of the existing bookings arrived through the PP
import, and the agent that reported the capability missing had itself booked one
weeks earlier. What
failed was not the ledger but the path to it — the agent hit `taxes >= 0`, got a
bare Ecto message back, found no kind named in the direction enumeration that
credits a refund, and concluded the refund was unbookable. Its fallback was a
balance anchor, which the MCP schema itself describes as making the balance look
right while hiding what happened.

That is the argument for fixing it, and it is a data-quality argument rather
than a convenience one: **the surface steers agents toward `set_balance`.**

Four gaps, all of them text, schema or one message:

- **D1 — the rejection names no alternative.** `%{taxes: ["must be greater than
  or equal to 0"]}`, verified against the live changeset. This is the moment the
  agent has stated its intent unambiguously and gets a rule with no remedy. Best
  fixed at changeset level so every surface inherits it, not per caller.
- **D2 — `tax_refund` is missing from the direction enumeration** in
  `portfolixir.transactions.create` (`mcp-server/src/tools.ts:1821`), which lists
  `removal/fee/tax` debit and `deposit/dividend/interest` credit and stops. The
  sentence also ends at "never send negative values" without the remedy.
- **D3 — `portfolixir.holdings.reconcile` omits it from its repair list**
  (`tools.ts:1854`) — the tool used to compare a broker statement against the
  ledger, i.e. exactly where refunds surface. It names `set_balance` in full
  while the list of correct kinds trails off before reaching `tax_refund`.
- **D4 — the type value is undocumented.** One occurrence in all of `docs/`,
  inside ADR-0031. `api-and-mcp.md:211` says "tax refunds … add cash" in prose
  but never names the value or the workflow.

Pin it with a test that the prose kind-lists stay in sync with
`Transaction.kinds/0`. The root cause is a hand-maintained list drifting from the
schema, and without a pin the next kind goes missing the same way.

**Not risk-tier, no ADR.** No ledger semantics, no money math, no migration. The
`taxes >= 0` validation stays exactly as it is — it is what keeps one
representation of a refund.

**Withdrawn on 2026-08-14: OQ-4 and its option A.** The lane originally proposed
teaching the manual form to accept a negative tax and auto-split it the way the
importers do. The importers split a signed value because PP's *file format* hands
them one; manual entry carries no such constraint, so building it would have
added a second way to express a refund in order to fix a discoverability problem
— and made the input shape the ledger rejects look supported. Option B
(sign-bearing `taxes` on `buy`/`sell`) was rejected then and stays rejected, for
what is now the whole point of the lane: the ledger has one representation of a
refund and keeps it. **No open owner question remains.**

**Deliberately out of this lane:** the transaction form's type selector is
hard-coded to `["buy", "sell"]` (`transaction_management_live.ex:62-68`), and it
is the only LiveView that creates transactions — so no cash-only kind can be
booked by hand at all, `tax_refund` included. Real, but broader than this fix, it
predates the report, and it sits in #471/#414 territory. Recorded in #686 so it
is not lost; solving it opportunistically here would be a scope-lock breach.

### Lane M — Maintenance (mandatory, every batch)

Per the AGENTS.md Epic-Batch amendment of 2026-08-12. Reviews available updates
for Hex, npm, Elixir/OTP, PostgreSQL, BMAD and the external BMAD modules,
applies what passes the gates, and **reports what it deliberately did not
update, with the reason**. Each update is its own commit group.

- #674 BMAD 6.8.0 → 6.11.0, pin the `automator` module to a SHA.
- #676 Renovate/Dependabot plus a version report the lane can read.
- Inherited posture: two cowlib advisories, neither HIGH, no upstream fix,
  already documented as tolerated in `ci.yml`. Re-check, do not re-litigate.

## Sequencing

1. **Lane Z** — the tag, then #682 if cheap.
2. **C0** — the ADR status flip, so the tree stops contradicting the decision.
3. **#664** — verification; a confirmed regression re-sequences the rest.
4. **Lane B** ship-now stories, API and MCP together.
5. **Lane C** C1 → C2 → C3 → C4 → C5, risk-tier throughout.
6. **Lane D** D1 → D2 → D3 → D4 — small, text-and-schema only, independent of
   everything else; slots in wherever a review slot frees up. Runs with Lane B
   by affinity: both are agent-surface work, so the API/MCP review pass covers
   them together. The earlier "before Lane A, it is a correctness defect"
   sequencing is **withdrawn** — the re-scope showed nothing recorded is wrong.
7. **Lane A** A1 → A2 → A3.
8. **Lane M** reviewed throughout, reported at the close-out.

Lanes B, C, D and A are independent enough to interleave; the order above is the
priority if they compete for a review slot.

## Explicitly out of scope

- **#672 and #414** — new surfaces, deferred to Sprint 7 (OQ-2).
- **#572** — benchmark comparison, deferred pending its spec (OQ-3).
- Everything behind an unsigned gate: policy rules (B3.6), security events
  (B3.4), theses and predictions (B4.1/B4.2), the rebalancing digest (B3.5),
  collection (B3.3), push delivery (B3.7), the local model (B3.8), backtesting
  (level (d)).
- **FR-39..FR-42** — now unblocked in principle by ADR-0039's acceptance (they
  gain a home for their values), but they are not scoped here: the mechanism has
  to exist first, and they have no issues yet.
- The structural epic decision (epics.md E1–E19 vs. the GitHub tracker set, and
  section J's FR-37..FR-48 hanging off no epic row). Owner decision, not batch
  work; #321 stays stale until it is made.

## Gates

Unchanged and blocking: `mix format`, `mix test`, `mix coveralls`,
`pre-commit run --all-files`, `npm test --prefix mcp-server`,
`npm run build --prefix mcp-server`, `--warnings-as-errors` clean, Credo strict,
Sobelow, Dialyzer. Weakening any of them to make the batch pass is a review
reject. The agentic review closing act runs with four roles: correctness hunter,
edge-case hunter, design critic (Lane A is user-visible surface) and a UAT
persona walkthrough on seeded synthetic data, with the correctness pass carrying
a dedicated verification of Lane C's invalidation invariant.

## What "done" means for this sprint

- The v0.5.0 release exists and the automation that makes it is proven.
- A re-import provably preserves strategy configuration, or the regression is
  filed with evidence.
- The agent's four read/ergonomics requests are live over API and MCP.
- The repeat wait on the performance walk is gone for the activated value, with
  freshness visible in the UI and in every payload, and a rebuild command whose
  runtime is a measured number in ADR-0039.
- Eleven UI issues are closed and the UI is aligned — **not finished**; Sprint 7
  closes it.
- An agent that meets a tax refund is led to `tax_refund` by the surface itself
  — by the rejection message, by the create tool's direction list and by the
  reconcile tool's repair list — instead of reaching for a balance anchor.

## Amendments after adoption

- **2026-08-14 — Lane D added (#686), then re-scoped the same day.** As filed,
  the lane read the `taxes >= 0` rejection as the defect and proposed teaching
  the manual form to accept a negative tax and auto-split it. The owner reported
  that `tax_refund` is not only present but in live use — including a booking
  made by the reporting agent itself, weeks earlier — so the diagnosis was wrong
  at the root. **OQ-4 and its option A are withdrawn**;
  the `taxes >= 0` rule stays, because it is what keeps one representation of a
  refund. The lane is now the affordance gap that actually caused the failure:
  the bare rejection message, `tax_refund` missing from two hand-maintained
  kind-lists in the MCP schema, and a type value documented nowhere. Smaller and
  cheaper than what was scheduled, not risk-tier, no ADR, and no open owner
  question.

  Two process notes, recorded because the correction cost a full cycle:

  - **The first pass verified the rule and the form, then stopped.** It never
    read the MCP tool descriptions, never reproduced the error message an agent
    actually receives, and never checked whether the capability was already in
    use — which a single query against the instance would have answered. For a
    defect reported *by an agent*, the agent-facing surface is the primary
    evidence, not a secondary consideration.
  - **The reporter's own transcript contained the disproof** and was read past.
    An agent reporting "X is impossible" is reporting that it could not find X,
    which is a claim about the surface first and about the capability second.
