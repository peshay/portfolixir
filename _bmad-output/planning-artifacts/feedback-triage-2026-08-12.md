# Owner Feedback Triage — 2026-08-12

Source: an unstructured owner feedback dump from day-to-day use of the live
instance, plus a requirements document written by the owner's portfolio agent
("requirements from agent operation", dated 2026-08-11) and handed to the PM
role. This document is the PM triage per ADR-0038.

**Privacy note.** The agent's document contains real policy thresholds, real
position references, household member names and dated real-world events. None
of that is reproduced here. Rules are described by their *type* ("a hard cap on
a satellite category", "a protected-position rule"), never by their value or
their instrument. Response sizes and call counts are system metrics, not
financial data, and are kept. The source document is not committed.

Status: triaged. Nothing here is a committed scope decision — issue creation
and the decision gates below await owner confirmation.

---

## Part 0 — The one finding that governs the rest

Four separate inputs of this round point at the same missing decision:

- the owner wants numbers **computed continuously and kept**, not derived per
  page view;
- the owner states Portfolixir is **primarily a tool for LLM agents** with a
  human visual surface as the second first-class audience;
- the agent asks for **decision-ready answers instead of raw data** (its P1),
  for **indicators and portfolio metrics computed server-side** (its P1-5), and
  for **derived values that carry their own freshness** (its P4);
- the agent's most expensive recurring run is ~25 calls, most of which are data
  fetching and recomputation, not judgment.

All four are the same architectural statement: **derived values should be a
first-class, continuously maintained, freshness-labelled layer of this system**
— for both audiences, from one computation. That is not what the current
authoritative texts say. `AGENTS.md` describes a small local tracker whose
holdings are derived on read (ADR-0004), ADR-0032 explicitly defines the one
existing cache as volatile and non-durable, and the Hard Rules forbid "advanced
reports" outright.

So the sequencing recommendation of this whole triage is: **two decision gates
first, then everything else becomes ordinary scoped work.** Without them, most
of the agent's list is either blocked by a rule or would be built without a
gate. Both gates are described in Part 1 (Q2, Q4).

---

## Part 1 — The owner's four direct questions

### Q1 — BMAD is at 6.8.0, 6.11.0 exists. Update? And what about every other tool?

**Facts.** `_bmad/_config/manifest.yaml`: installation 6.8.0, installed
2026-06-11, `lastUpdated` unchanged since — so two months without an update.
External modules are pinned by SHA (`tea` v1.19.0, `cis` v0.2.1) and one is
pinned to a moving ref (`automator` → `main`, which is a different risk: it can
change under us without any version bump). We carry local overrides in
`_bmad/custom/` (dev agent, sprint planning) and a customization resolver — that
is exactly the surface a minor-version jump can break.

**Assessment.** Runtime dependencies have a written policy
(`project-context.md` → Dependency Update Policy: track latest stable, dedicated
update PRs, never inside feature stories). **Agent tooling has no policy at
all** — BMAD, the external BMAD modules, the Claude Code side, and the MCP SDK
sit outside it. And the policy that does exist is unautomated: there is no
`dependabot.yml` and no Renovate config in this repo, although "automate update
visibility" has been an open follow-up in `project-context.md` since June and is
item 3 of the Quality Gate Roadmap. That is why the question had to be asked by
a human instead of being answered by a dashboard.

**Recommendation — three things, in this order:**

1. **Yes, update BMAD — as its own maintenance PR, never inside a feature
   batch.** Suggested procedure, which should become the documented one:
   read the 6.9→6.11 changelogs specifically for skill-format and
   customization-override changes; update on a branch; diff `_bmad/` and review
   what the installer rewrote; re-resolve `_bmad/custom/*.toml` and confirm both
   overrides still apply; smoke-test one workflow per role we actually use (PM
   triage, story creation, dev story, code review); pin `automator` to a SHA
   like the other external modules. If a workflow's output format changed,
   `sprint-status.yaml` and the epics document are the artifacts at risk —
   check them before merging.
2. **Institutionalize a maintenance lane.** Every sprint batch carries one lane
   whose job is versions: hex + npm, Elixir/OTP + Postgres, BMAD + external BMAD
   modules, agent tooling. It runs the checks, updates what is green, and
   reports what it deliberately did not update. The batch already has the gate
   discipline to make this safe; what is missing is that nobody owns the
   question.
3. **Finally file the automation** (Renovate or Dependabot for hex and npm,
   `mix hex.outdated` in the maintenance lane, and a version report the lane can
   read). This closes an item that has been open as a note for two months.

Deliverables: one issue for the BMAD update, one issue for the maintenance-lane
convention (with the `AGENTS.md` amendment that makes it binding), one issue for
update automation. None of them needs a decision gate.

### Q2 — Numbers should not be computed at page view. It is self-hosted; compute continuously and keep the last state.

**The owner is right, and the architecture already half-agrees.** Two ADRs
attacked this and both shipped: ADR-0032 (the daily TTWROR walk is memoized,
warmed at boot, and the last known series is served immediately with its
as-of label) and ADR-0035 (market data is priced once per read and threaded
through, which took the warm dashboard block from ~1.1 s to ~265 ms and 2,614
queries to 115). The app also already runs scheduled background work —
`QuoteSync`, `Fx.RateSync` and the performance `Warmup` are supervised
processes. "A job every minute" is therefore not new infrastructure; it is a
new *policy* for existing infrastructure.

**What the owner is asking for is a genuine step beyond ADR-0032, in two ways:**

1. **Durability.** ADR-0032's memo is defined as volatile — it never survives a
   restart, by design, so that it can never become a source of truth. The
   owner wants the last computed state kept.
2. **Push instead of pull.** Today recomputation is triggered by a read (plus a
   boot warm-up). The owner wants it triggered by the write that invalidated it,
   or by a schedule — so that a read is never the thing that pays.

Both cross a line ADR-0032 drew deliberately, and the second one brushes
ADR-0004 (holdings are never stored). That is what makes this a **decision gate,
not a story**.

**PM recommendation: open the gate, and expect it to pass.** A durable derived
layer is defensible if the ADR pins these invariants, which also happen to be
exactly what the agent's P4 principle demands:

- **Rebuildable at all times** from transactions alone; dropping the whole
  derived store and rebuilding it must be a supported, tested operation. This is
  what keeps ADR-0004's auditability guarantee intact: there is still exactly
  one source of truth, and the derived layer is a *materialization* of it, not a
  second copy that could disagree.
- **Versioned** against the existing data-version counter, so a stale entry is
  detectable rather than merely old.
- **Never silent about its own freshness.** Every derived value carries `as_of`
  and, when it is behind its inputs, an explicit stale marker — in the UI *and*
  in the API/MCP payload. The value-slot vocabulary from Sprint 5 (pending /
  settling / final / not-computable) is the UI half of this and already exists;
  the API half does not.
- **Never authoritative for a write.** No booking, no import decision, no
  consistency finding may read the derived layer instead of the ledger.

The prize is that this single decision serves both audiences from one
computation: the human surface stops waiting on a skeleton, and the agent's
metric requests (P1-5) become cheap lookups instead of series-through-context
work. It is also the precondition that makes the agent's acceptance criterion
("the weekly run needs ≤ 5 calls") reachable at all.

Scope note for the ADR: it should decide *which* derived values are
materialized, and say no to the rest. Everything is not the answer.

### Q3 — Is all the UI work actually done? The Wealth tabs are still plain text.

**No, and the tab item specifically was a deliberate deferral, not an
oversight — but the way it was deferred is itself a finding.**

What Sprint 5 shipped (lanes A–F, PR #661): tokens and contrast, colour
independence, the loading/motion vocabulary incl. the count-up, hint prose moved
into on-demand tooltips (UX-DR11), a defect sweep, and CI/release engineering.
The adopted Sprint 5 plan lists, under "Queued behind the lanes", verbatim:
*"Assets-view tabs, period selector and date picker rework"*, alongside the
contra-account UI, the snapshots makeover, the income view set, the tax view
rework and the Overview card's plan context. So the owner is looking at the
exact item the plan knowingly left for later.

The observation is also **already decided in the spec, and confirmed in the
code**. `DESIGN.md` → Components → Tabs: *first-level tabs carry an icon +
label*, second-level tabs are the same control, smaller and iconless; both take
the touch-target floor under `pointer: coarse`. `app_shell.ex` `area_tabs/1`
renders `tab.label` and nothing else, and `.area-tab` declares no `min-height`
— so the first level currently fails both halves. `EXPERIENCE.md` additionally
records that "first level has icons, second does not" is a sighted-only nesting
cue and needs a structural carrier as well (H5 of the accessibility review).
That is a well-bounded story with its work list already written.

**The process finding is worth more than the story.** That queue exists only as
prose inside a sprint-plan document. It has no issue, so "is this done?" is not
answerable from the backlog — it is answerable only by reading a planning
artifact and knowing which one. The same rot shows in the reference itself: the
plan points at "#415 umbrella" for the income view set, and #415 has been closed
since July. Meanwhile three Cash-flow facets that the design spec marks
*specified, unbuilt* (realized gains, deposits & withdrawals, costs) have no
open issue either.

This is precisely the failure mode the agent's document describes as *"the fact
had no home with an ID"* — applied to our own backlog. **Recommendation: file
the queued design items as thin issues under tracker #356 now**, before any of
them is scheduled, and make "a queue item without an issue number" a review
finding in the close-out step.

### Q4 — What Portfolixir actually is: an LLM tool first, and a human overview second

The owner's framing, restated: the project exists because the investment history
lived in Portfolio Performance and the LLM agent had no good way in. Portfolixir
should be the place where all the data is gathered, where every tool is
available, where the agent saves tokens and always reads current, consistent
data — **and** the visual surface where a human keeps the overview and sees what
is happening in the depot. What is still missing versus PP is the strength of
its visualization and evaluation, including "how well did I sell this".

The agent's document says the same thing from the other side, and adds the
operational evidence: every fact it had to keep *next to* Portfolixir rotted,
with several documented drift cases in a two-day window.

**PM assessment: this is a product-identity change and it has to be written
down, because the authoritative text currently contradicts it.**

- `AGENTS.md` → Project Goal describes a small self-hosted tracker with twelve
  numbered capabilities, all of them record-keeping and valuation.
- `AGENTS.md` → Hard Rules: *"Do not add advanced reports or advanced
  classifications."*
- The API/MCP surface (102 MCP tools) is treated as *coverage of app functions*
  — "every new user-visible function must include API and MCP coverage". That
  wording makes the agent a mirror of the UI. The owner is now saying the agent
  is the primary audience, which inverts the relationship: some capabilities may
  exist for the agent first, with a human view derived from them.

The consequence today is visible in this very triage: indicators, attribution,
calibration, signals and benchmark work all read as "advanced reports" to an
agent following the rules literally. So each request either gets refused by the
rule or slips in without a gate. Neither outcome is acceptable, and this is the
same gap the 2026-08-05 triage flagged as "from data to information" and parked
behind a product brief. That brief is now overdue, and it should be **widened
from an insights question to an identity question**.

**Recommendation.** Run the product brief with this scope: two first-class
audiences (agent, operator), one data spine, and an explicit replacement for the
blanket "no advanced reports" rule — a bounded list of what is now in scope
(derived metrics, attribution, benchmark, calibration of the agent's own
predictions, structured decision inputs) and what stays out permanently and
non-negotiably (no broker connection, no order creation or transmission, no
automated trading or payment, no advice, no raw news archive, no external LLM
calls from the app). Output: product brief → PRD update → ADR → `AGENTS.md`
Project Goal and Hard Rules amendment. Until that lands, the items in Part 2
Bucket 3 cannot legitimately be scoped, and the ones in Bucket 4 have no
justification for existing.

The owner's PP-parity wish ("how well did I sell") is partly already built and
unsurfaced: `Ledger.TradeMatcher` computes closed round-trips with realized P&L
per sell, exposed over the API and in the Securities detail pane, but it has no
cash-flow surface — which is one of the three *specified, unbuilt* facets from
Q3. That one is a UI story, not a new capability.

---

## Part 2 — Triage of the agent's requirements document

Six buckets, ordered by how they should be treated. Bucket 5 is the dedup pass:
several requests are already built or already tracked.

### Bucket 1 — Ship-now: fits the current rules, small, high leverage

**B1.1 — Sparse fieldsets, projections and server-side filters on read
endpoints (agent P0-1).** The pattern already exists and is proven:
`securities.list` defaults to a slim projection and takes `projection=full`
(FR-33, #584). The request is to generalize it: `fields=` / `projection=` on
read endpoints, `include_positions=false` on allocation and valuation to get
category roll-ups only, and a server-side `drift_min=` filter so the caller
receives the deviating rows instead of all of them. The agent estimates 70–85 %
less response volume on its four heaviest calls.

Assessment: **the cheapest item in the entire document and the largest immediate
effect.** No gate, no new domain concepts, no money math. It also has a direct
human-side benefit: the same roll-up-only read is what a fast dashboard wants.
Requires API + MCP parity by the standing rule (both halves in one story).
Caveat to write into the story: `fields=` must be a validated whitelist per
endpoint — never an atom created from input, never a passthrough to a query
builder.

**B1.2 — `?since=` delta reads (agent P1-6, first half).** Read-only, additive,
same story family as B1.1: the caller asks what changed since a timestamp
instead of pulling the full state and diffing it locally. The *push* half of
P1-6 (webhooks) is a separate decision — see B3.7.

**B1.3 — Tax snapshot staleness and allowance-order entry (agent P0-5,
non-gated part).** The agent reports one recorded snapshot, marked stale, and an
empty allowance-order table. The direction was already settled on 2026-08-05:
MCP/LLM is the primary write path, the UI becomes a review and overview surface,
document intake is rejected. What remains is small and unbuilt: a warning when
the newest snapshot is older than N days **or when tax-relevant trades were
booked since it was taken**, and the trim-budget/pot state exposed where the
decision is made. The second condition is the interesting one — it makes
staleness a function of activity, not only of the calendar.

**B1.4 — Backlog hygiene from Q3.** File the queued design items as thin issues
(assets-view tabs + pickers; contra-account UI; snapshots makeover; the three
unbuilt Cash-flow facets; the Overview card's view+plan context label). Pure
bookkeeping, no scope decision, unblocks planning.

### Bucket 2 — Verify before scoping: one possible data-loss defect

**B2.1 — "A fresh PP import destroys the classification, all target weights and
the cash target; whether `note` and `attributes` survive is untested" (agent
P2-1).**

If true, this is the most urgent item in the document — it is silent
destruction of exactly the data the agent maintains, and it contradicts the
intent of ADR-0029 (stable identities and re-import survival, accepted
2026-07-22). The agent also notes it has left three annotated securities in
place as a canary.

**But it is a claim, not a finding, and it must not be scoped as a bug yet.** A
first code reading argues against the literal reading: the import path
(`lib/portfolixir/imports/`) contains no bulk delete of any kind, and import
idempotency is content-hash based, so re-applying the same export is defined as
a no-op. The likelier explanation is that the observation comes from a
database-reset-and-reimport workflow rather than from the importer itself — in
which case the real gap is that the reset path has no documented survival
story, which is a different (and still real) problem.

**Action: a bounded verification story before any design work.** Synthetic
fixture, no real data: classify securities, set target weights and a cash
target, write notes and attributes, re-import the same PP export, and assert
each of them survives — with the assertions checked in as the permanent
regression guard ADR-0029 should have had. Whatever the outcome, the story ends
with a documented answer to the agent's open question 1. Treat as **risk-tier
attention** (its own commit, its own verification pass in the review, called out
in the briefing) because the invariant at stake is "an import never destroys
operator-maintained data".

**B2.2 — Not our defect.** The agent's report that source quality is inferred
from a domain and mis-grades secondary sources describes *its own* local
collector, not Portfolixir. It becomes a requirement — not a bug — if and when
we build collection (B3.3): source quality is **set, not guessed**, and a manual
correction is never overwritten by the next collection run.

### Bucket 3 — Needs a decision gate before any story

Ordered by what unblocks the most.

**B3.1 — Product identity / "from data to information" (Q4).** Governs B3.5,
B3.6, Bucket 4, the metrics request (P1-5), backtesting (P2-2) and the
visualization wishes (P2-3). Do this one first.

**B3.2 — Durable, continuously maintained derived values (Q2).** Governs the
perceived-performance complaint and makes the agent's metric requests cheap.
Amends or supersedes ADR-0032; must state its relationship to ADR-0004
explicitly.

**B3.3 — Data acquisition beyond quotes (agent P1-3, and the data half of
P0-4).** The agent wants Portfolixir to collect what its local cron scripts
collect today: filings, company announcements, event dates, research and news
with an instrument reference — and, importantly, to expose **collector health**
(last run, error count, freshness) so that a dead collector is visibly dead
within a day rather than silently producing false calm. That last requirement is
good product thinking and should survive into whatever we build.

Gate questions: which sources, which providers, what happens on failure, how
much is stored (the agent itself sets the non-goal: condensed dated signals with
source links, never a full-text archive), and how this sits against the existing
network-boundary rules. Quote and FX sync are the precedent that this is
possible; the scope jump is what needs deciding.

**B3.4 — Security events as a first-class object (agent P0-4, model half).** The
object itself is modest: instrument, type, date, timing qualifier, confirmed
flag, source URL, source quality, checked-at, note. Two things make it
interesting:

- Its sharpest requirement is structural, not technical: **events must be
  tracked for every security in the catalog, not only for held positions.** The
  agent's local collector builds from holdings, so a purchase candidate with
  zero holdings is structurally invisible — and that is precisely the security
  whose upcoming dates matter most. Good news: our catalog is already
  independent of holdings, so "the universe" already exists as a concept and
  needs no new model.
- It is related to but distinct from corporate actions (ADR-0028, shipped):
  those are *ledger events* that change positions; these are *calendar facts*
  that inform a decision and never book anything. Keep them separate — sharing a
  table would be the kind of shortcut that costs later.

Gate-wise the object can be decided cheaply; its *automatic* population is
B3.3.

**B3.5 — The rebalancing digest (agent P0-2), with a reduced first scope.** One
call returning, per candidate: identity, actual/target weight, drift in points
and currency, indicative quantity, a fresh price with timestamp, expected
proceeds or outlay, the relevant tax context, the next known date, cash quote
after the trade and after all proposed trades, plus rule-violation flags. The
agent is explicit that this stays a proposal — Portfolixir has no broker
connection and must not get one — and that its weekly run would drop from ~25
calls to one plus judgment.

Most of this is aggregation of things that already exist, and ADR-0023 already
permits display-only corrective quantities. **Two elements cross lines and
should be cut from the first version:**

- **The limit-price suggestion** (sell slightly under, buy slightly over the
  current price) is no longer allocation guidance — it is order preparation. It
  is the first element of the whole document that shapes *how* a trade is
  placed rather than *whether* the allocation is off. It belongs in an explicit
  ADR-0023 amendment, decided on its own merits, not smuggled in as a digest
  field.
- **The per-trade tax estimate** needs a documented method before it can be a
  number on a screen. ADR-0031 covers *recorded* snapshots; forward projection
  was deliberately deferred behind its own gate (story 19.7). Version one should
  carry the recorded state and the trim budget — facts we hold — and not an
  estimate we would have to invent.

With those two cut, the digest is a large but ordinary aggregation story, and it
still delivers most of the claimed saving.

**B3.6 — Policy rules as objects (agent P0-3).** Caps, floors, warning bands,
protected positions and budgets live today as prose inside cron prompts, and the
agent documents drift from exactly that. Modelling them — type, scope, threshold,
severity, validity period, history — turns them into structured findings
evaluated server-side, and gives the human surface the rule-status view the
owner has asked for in a different form ("which cap is how close to its limit").

This is the single strongest embodiment of the agent's "one truth, one ID"
principle, and it is well-aligned with the existing target/plan family (E15/E16,
ADR-0020/0027/0030). It needs an ADR because it introduces a rules engine whose
output drives warnings, and because rule *history* is a data-retention decision.
Recommended after B3.1/B3.2; high value, medium size.

**B3.7 — Push triggers and webhooks (agent P1-6, second half).** A retrievable
alarm list is ordinary scoped work and can ride B3.6 (a rule that is violated is
an alarm). **Outbound HTTP to a user-configured endpoint is a separate security
decision** — request forgery surface, stored secrets, retry semantics — and the
agent itself notes that delivery to a chat channel is handled by other software
anyway. Recommendation: build pull, defer push to its own gate, and do not let
the two be scoped as one story.

**B3.8 — A local model inside the application (agent P1-4).** The agent proposes
a locally hosted model for parsing broker PDFs, condensing announcements into
signals, extracting event dates and filtering mis-tagged items — explicitly
bounded to *structuring*, never to judging money, with every machine-produced
field carrying a source link and a `machine_generated` marker.

The boundary in `AGENTS.md` says "no external LLM calls from the app". A locally
hosted model is not external, so the rule does not literally forbid it — which
is exactly why it must not be resolved by literal reading. **Recommendation: do
not open a general local-model gate.** Take the narrow path that already has a
passed gate: ADR-0021 (broker-PDF transaction intake — accepted, and per the
current tree unbuilt) already prescribes sandboxed, text-extraction-only,
per-broker, preview-then-confirm intake. Build that as specified; if extraction
quality genuinely requires a model, that is an *amendment to ADR-0021* with the
same sandbox and confirm-step constraints, not a blanket permission. The
condensation and event-extraction uses can then be judged against real
experience instead of against a proposal.

The agent's own open question 2 — should the model write structured fields or
only propose them? — should be answered as a standing rule regardless of
outcome: **machine-extracted data is a proposal until a human or an agent
confirms it**, carries its source and a `machine_generated` marker, and never
lands silently. That is the same preview-then-apply shape the PP import already
uses, and it is the right default for everything in B3.3/B3.4 as well.

### Bucket 4 — The agent's own memory: structured knowledge objects

Two requests that are technically modest, touch no money math, break no rule —
and have no justification for existing *until* Q4 is decided, because a plain
portfolio tracker has no business storing investment theses. Sequence them
behind B3.1; they can be specified in parallel with it.

**B4.1 — Theses and conviction as structured fields (agent P1-1).** Thesis text
and status, conviction tier, invalidation condition, time stop, last reviewed
and by whom, with history so a flip is visible after the fact. The agent's local
file for this is orphaned: built against a classification taxonomy that has been
dead since July, keyed on ticker symbols instead of stable identifiers, last
touched in May. The free-text `note` field is a better home but cannot be
queried. The three queries it needs are the acceptance criteria in disguise:
theses unreviewed for 90+ days, positions with a damaged thesis, time stops due
in the next 30 days.

**B4.2 — Predictions with a calibration report (agent P1-2).** A prediction
object (thesis, stated probability, check date, invalidation, action if right,
action if wrong, outcome, resolution note), a query for due check dates, and a
calibration report — hit rate per probability band against the stated
probability. The agent frames this as the thing that makes its own speculative
calls accountable; the owner-facing framing is sharper: **a view that shows
whether the agent's guesses are worth anything.** That is a genuinely good
feature and it is cheap. It also produces the honest failure mode the whole
system should have more of: a number that can embarrass its author.

### Bucket 5 — Already built or already tracked (dedup)

| Agent request | Status |
|---|---|
| Money-weighted view: invested capital, wealth multiple, IRR/MWR | **Shipped 2026-08-10** (#568, ADR-0034) |
| Benchmark comparison vs. indices and inflation | **Tracked, #572** — the Sprint 6 front-runner, unblocked by ADR-0034's flow markers |
| Loading affordances, count-up, progressive sunburst | **Shipped Sprint 5** (lane C) |
| Tax UI as a review/overview surface | **Decided 2026-08-05**, queued, unbuilt |
| Income view set beyond bars-per-year | Scoped 2026-08-05, design spec has the facets; the referenced umbrella issue is closed — **needs re-filing** (B1.4) |
| "How well did I sell" / closed trades | **Computed and exposed** (`TradeMatcher`, API, Securities detail) — missing only its cash-flow surface, one of the *specified, unbuilt* facets |
| Deposits and withdrawals as a view | **Specified, unbuilt** (`/cashflow?tab=flows`) — needs an issue |
| Concentration / HHI / asset-class caps | **Shipped** (`portfolios/risk.ex`) — the agent names it as the model to extend, which is the right read |
| Multi-user / household separation | **Parking lot #340**; buckets and views (ADR-0018/0024) are the intended mechanism today |
| Backtesting a rule against own price history (P2-2) | Nothing exists; nearest neighbours are the what-if simulator (#332, gated) and the parking lot. Defer until B3.1 and B3.6 exist — a rule prüfstand without rule objects is premature |

### Bucket 6 — Answers to the agent's open questions

1. **Do `note` and `attributes` survive a PP re-import?** Unverified. A first
   code reading finds no destructive operation in the import path, but the
   answer must come from the test in B2.1, not from a reading. The canary is
   noted and useful; the checked-in regression test replaces it.
2. **Should a local model write structured fields, or only propose them?**
   **Propose only** — with source link, `machine_generated` marker, and an
   explicit confirm step. Standing rule for all machine-extracted data,
   independent of the B3.8 outcome.
3. **Multi-tenancy?** **No — not as a new concept.** Buckets and views already
   scope holdings for separate household members, and true multi-user support is
   explicitly in the parking lot (#340). If the separation needs to be stronger
   than tagging, that is a scoping decision on buckets, not a tenancy model.
4. **How deep should history go?** **Per object, not globally.** Rules and
   theses need real history — knowing *when* something flipped is their entire
   point. Derived metrics need only `as_of` plus guaranteed recomputability
   (B3.2). Who-changed-what is the audit journal's job (ADR-0017).

**And one dependency nobody has scheduled.** The audit-journal rollout is
incomplete: Catalog and FX are armed, but Portfolios/Classifications, Ledger and
Imports still write unjournaled — and MCP *write* tools (FR-14) are deliberately
blocked behind that rollout, because arming agent writes first would let an
agent edit transactions without an audit trail. The owner has meanwhile decided
that MCP/LLM is the **primary write path** for tax data, and this feedback round
proposes agent-written theses, predictions, events and rules. **Finishing the
audit-journal rollout therefore moves from "nice to have" to a prerequisite for
Bucket 4 and for B1.3.** It should be scheduled deliberately rather than
discovered as a blocker when the first write story starts.

### On the agent's acceptance criteria

They are unusually good and mostly adoptable verbatim as story criteria. Two
notes: the "≤ 5 calls for the weekly run" and "−70 % response volume" targets
are measurable and should be attached to B1.1 and B3.5 respectively. "No date,
thesis or target weight lives in a local file any more" is a *migration*
criterion — it can only be met after the objects exist, so it belongs to a
closing story, not to each one. And "a purchase candidate with zero holdings is
monitored exactly like a held position" should be lifted out of its bucket and
carried as a design constraint across B3.3/B3.4, because it names a structural
blind spot rather than a feature.

---

## Part 3 — Proposed sequencing

Nothing below is committed; it is the order I would work in.

**Immediately, no gate needed:**

1. **B2.1** — verify the PP re-import survival claim (risk-tier attention). If
   it confirms, it becomes the most urgent defect on the board.
2. **B1.1 + B1.2** — sparse fieldsets, projections, server-side drift filter,
   `?since=` deltas, API and MCP together. Cheapest, largest agent payoff, and
   the roll-up-only reads help the human surface too.
3. **B1.4** — file the queued design items as issues, including the assets-view
   tabs story the owner asked about (its spec and work list already exist).
4. **Q1** — the BMAD update PR, plus the maintenance-lane convention and the
   update automation that has been an open note since June.

**In parallel, no code — the two gates:**

5. **B3.1** — product brief → PRD → ADR → `AGENTS.md` amendment: two first-class
   audiences, and a bounded replacement for the blanket "no advanced reports"
   rule. This one governs the rest.
6. **B3.2** — the durable derived-value ADR (amends/supersedes ADR-0032).

**Then, in this order:**

7. **B3.6** policy rules as objects → unlocks the rule status view and the
   digest's flags.
8. **Audit-journal rollout completion** → prerequisite for agent writes.
9. **B4.1 / B4.2** theses and predictions with calibration.
10. **B3.5** the digest, without limit suggestions and without estimated
    per-trade tax.
11. **B3.4** security events as an object (manual and API/MCP population first).

**Later gates, in rough order of readiness:** B3.3 collection with collector
health · B3.8 via ADR-0021's narrow path · B3.7 push delivery · backtesting.

**Open for the owner:**

- Confirm or correct the routing above, in particular the two gates in Part 0
  and the three cuts I propose (limit suggestions, per-trade tax estimate, and
  the general local-model permission).
- Q1: is the maintenance lane wanted as a standing part of every batch, or as
  its own periodic PR outside the sprint rhythm?
- Q4: the product brief needs the owner in the room — it is an identity
  decision, not a scoping exercise. Whether the agent is the primary audience or
  a co-equal one changes what gets built first for the next several sprints.
