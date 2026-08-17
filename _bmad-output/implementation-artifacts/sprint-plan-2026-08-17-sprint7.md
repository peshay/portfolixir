# Sprint Plan — Sprint 7 (ADOPTED, 2026-08-17)

**Status: adopted.** No draft preceded it: the questions a draft would have
asked were answered by the pre-sprint reconciliation (PR #714) and by ADR-0042,
which the owner signed off the same day.

**Revised the same day** after owner challenge on three points — how much was
being deferred, where the lane letters came from, and whether the maintenance
lane really covered the toolchain. All three were right; see "Revision
(2026-08-17)" for what changed and why.

Ground truth: `main` at `1a88ad5`. Verified against the merge commits
(`f0beb8c..1a88ad5`), the open pull-request list (8, all Dependabot), the
open-issue list (40), the Actions runs on `main`, and — new in this revision —
the full output of `scripts/version-report.sh`.

## What this sprint is

**The UI closer, and the first sprint under one planning structure.**

Sprint 6's OQ-2 stated the consequence of its own scope cut plainly: *after
Sprint 6 the UI is aligned but not finished, and Sprint 7 is committed as the
closer.* That promise is kept here rather than rolled forward — see the UI
lane's sequencing, which is the whole reason it is ordered the way it is.

## Revision (2026-08-17) — what the owner's challenge changed

**R-1 — Less is deferred, and the deferral principle was wrong.** The adopted
version pushed #708 and #709 to Sprint 8 on the grounds that they would make
"four money-domain items in one batch". That argument counts items instead of
sizing them, and it treats a small precisely-specified change as equivalent to a
risk-tier subsystem. Actual sizes: **#710 heavy** (projection and refresh
semantics, risk-tier), **#712 medium** — ADR-0041 is explicit that "nothing here
has to be computed for the first time; it has to be **grouped**" —, **#708
medium** (genuinely new pre-cost figures), **#709 small** (ADR-0040 specifies it
exactly: an explicit remainder row, drift against the allocated portion, the
warning reserved for two states).

Worse, the same document called #572's repeated deferral "bookkeeping theatre"
and then made the identical move on #708/#709 one section later.

**The sharper principle, which replaces the count:** what poisons a batch is
**unspecified** work, not domain concentration. #572 stays out because its
semantics are still undecided — starting it would mean deciding them in
implementation. #708, #709 and #712 come in because their ADRs are signed and
their scope is bounded. Domain is not the discriminator; specification is.

**And the pre-emptive deferral duplicated a mechanism this plan already has.**
A shrink order exists precisely so overrun can be absorbed without a new
decision round. Deferring *and* keeping a shrink order is belt-and-braces; the
shrink order does the job.

**R-2 — The lane letters were inherited, inconsistent, and one collided.** See
"On lane names" below. They are gone.

**R-3 — The maintenance lane was incomplete.** It listed the eight Dependabot
PRs and nothing else, which covers npm and GitHub Actions. `AGENTS.md` defines
the lane as covering "Hex, npm, Elixir/OTP, PostgreSQL, BMAD and the external
BMAD modules". Elixir/OTP, PostgreSQL and all of BMAD were simply missing, and
`scripts/version-report.sh` — which exists to produce exactly this picture — had
not been run. It has now; the lane below is rewritten against its output.

## On lane names

The previous version labelled lanes `R / Z / A / B / C / D / M`, which looks
like a vocabulary and is not one. Checked against the record: Sprint 5 used
A–F for tokens, colour independence, loading affordances, tooltips, a defect
sweep and CI/release; Sprint 6 used A–D for UI, agent requests, derived values
and the tax-refund affordance. **The same letters meant different things in
consecutive sprints,** and this plan's "Lane D" would have been the third
distinct meaning for that letter — which makes any cross-sprint reference to
"Lane D" ambiguous in a retrospective.

Only two roles are genuinely stable across sprints: **close-out and structural
debt first**, and **maintenance always present**. Those keep their letters
because the letter carries the role. Everything else is now named for what it
is. A name costs nothing and survives the sprint.

## Decisions

**D-1 — ADR-0042 is signed off (owner).** The migration runs as Lane Z. Because
the gate was signed before this batch opened, Lane Z is execution, not
decision-making.

**D-2 — #414 and #672 are built in this sprint, after #707, not deferred again
(batch agent).** The triage instructs that both "should follow #707's output
rather than land on the pre-design-language screen". Sprint 6 read a similar
constraint as grounds for deferral. Deferring twice on the same reasoning turns
a sequencing constraint into a permanent excuse, and it would break OQ-2's
commitment for the second time. The constraint is satisfied *within* the batch:
**#707 ships its spec first**, and the two builds are held against it.

**D-3 (revised) — #708 and #709 are in.** Per R-1. Both carry signed ADRs and
bounded scope. If the batch overruns, the shrink order handles it.

**D-4 — #572 stays out, third sprint running (batch agent).** Not on capacity
but on specification: its three design questions are unresolved, and its
inflation/CPI half needs a source gated at B3.3. **Recorded as a standing
recommendation rather than a repeated deferral:** #572 should not appear in a
sprint plan again until a short ADR section settles its semantics. Listing it as
a candidate each sprint and cutting it each sprint is bookkeeping theatre.

## Batch topology

Unchanged from Sprints 5 and 6: **all lanes in ONE batch** on one epic branch,
**one PR for the sprint**, rebase-merged per the ADR-0026 amendment. A lane
splits into its own PR only if it proves big during the batch — flagged in the
briefing, not asked mid-sprint.

Branch: `agent/claude/sprint7-ui-closer`.

## Lanes

### Lane Z — Structural and close-out debt (always first)

**Review conditions (#706)** run before anything else, because they change the
quality of this batch's own closing act. The design-critic pass ran at desktop
width, in EN, against data that triggered no finding surface — and four of six
defects in the 2026-08-15 round were invisible under exactly those conditions.
Deliverable: the design-critic and UAT walkthroughs run in **DE**, at **≤390 px**
as well as desktop, against seed data that **triggers the finding surfaces**
(stale quotes, missing FX, unclassified securities, a plan short of 100 %).

**The ADR-0042 migration**, mechanical, before any other lane writes to the
planning documents:

1. Move each Epic Detail intent paragraph into its tracker issue body **before**
   deleting it — the migration's one real risk.
2. Delete the Epic List, Epic Detail and `##### Story` rows from `epics.md`;
   keep the Requirements Inventory, FR Coverage Map, scope-ladder boundaries and
   the dated reconciliations.
3. Narrow `sprint-status.yaml` to its close-out/reconciliation log; drop
   `development_status` and with it the five schema-invalid keys.
4. Preserve #321's "working agreement" section into `AGENTS.md`, then close #321
   **by hand with the reason** — invalidated, not implemented, so no keyword.
5. Amend `AGENTS.md` where it references the removed structures.

### The UI closer (the committed lane)

Ordered, because the order is the point:

1. **#707 — the design engagement.** Control vocabulary, card naming, and the
   two surfaces that predate the design language (Transactions, Income).
   Delivers a **spec** against the living design-language document, not a build.
2. **#702 — Wealth tab row clips on a phone.** A #668 regression leaving the
   fifth tab unreachable at 390 px. Ships the overflow fix; the "should these be
   burger sub-items" navigation question belongs to #707 and is not answered
   here.
3. **#700 — asset class: stored vs. effective.** Render an inferred class as
   visibly *derived*, and pick one of stored/effective for the count, the filter
   and the quick-assign affordance. **The decision taken here governs #705** —
   record it in the commit, since it is a semantic choice made in
   implementation.
4. **#701** — securities table headers through gettext, **plus** the meta-test
   asserting no field-definition label bypasses the catalog. Without it the next
   field table repeats the bug.
5. **#703** — the `trade_priced` row names its positions; Overview keeps the
   alarm, Wealth states the consequence and drops the restatement.
6. **#704** — the ADR citation leaves user-facing copy, the computation-basis
   content stays, **plus** a meta-test that no gettext msgid matches
   `ADR-\d{4}`.
7. **#414 and #672**, built against #707's spec.

### Agent and operator surface

- **#705** — data-quality predicates over the filter builder, API and MCP.
  **Strictly after #700**: the predicate must mean what the count means.
- **The `?since=` human view** — the one genuinely undischarged part of the
  two-way coverage obligation (PR #714's analysis). Needs an issue filed first,
  per ADR-0038. Shape follows `SinceParam`: an operator-chosen cut, the rows
  created or updated since it, and **the deletion gap stated on the surface** —
  the computation-basis rule makes gap treatment part of the contract, and the
  agent half already documents it.

### Durable derived values (risk-tier)

- **#710 — refresh on the invalidating write, coalesced.** **Risk-tier.**
  Invariant at stake: one import must not produce thousands of full
  recomputations. `BlastRadius` widens most resource types to `:all` and an
  import bumps the version per booking, so **import is the acceptance scenario
  by construction**, not an edge case.
- **#711 — measure and activate the figures the operator actually waits on.**
  Measurement precedes activation; activating without it is guessing.

### Shipping the signed decisions

- **#712 — category result** (ADR-0041). Money-weighted roll-up on the category
  row, expandable to its member positions. `Σ result ÷ Σ invested`, never a mean
  of percentages. Rows whose result cannot be derived are **excluded and named**,
  never silently counted as zero. No membership history, no restatement caveat,
  no as-of qualifier — the figure describes the current composition. Also
  discharges the roll-up half of the FR-37 human-view obligation.
- **#709 — unallocated remainder** (ADR-0040). Explicit remainder as a named
  part of the plan; drift computed against the allocated portion; the warning
  reserved for the two states that really are wrong (a sum above 100 %, a
  position-vs-category conflict).
- **#708 — transaction costs in the snapshot comparison** (ADR-0027 amendment).
  Return before transaction costs, and whether they are earned back.

### Lane M — Maintenance (always present, rewritten in this revision)

`AGENTS.md` scopes this lane to **Hex, npm, Elixir/OTP, PostgreSQL, BMAD and the
external BMAD modules.** Point-in-time picture from `scripts/version-report.sh`,
run 2026-08-17:

| Ecosystem | State | Lane action |
|---|---|---|
| **Hex** | all 22 deps up-to-date | nothing to update — Dependabot's `mix` ecosystem correctly opened no PRs |
| **Hex advisories** | `cowlib` 2.19.0 carries EEF-CVE-2026-43966 (MEDIUM, HTTP response splitting) and -43969 (LOW, cookie header injection) | **known and already handled** — no fixed release exists upstream; `ci.yml` documents the ignore under all three ids and says "revisit when a fixed cowlib ships". **The lane's job is that re-check**, not a new finding |
| **npm (mcp-server)** | `zod` 3.25.76 → **4.4.3 (major)**; `@modelcontextprotocol/sdk` and `express` already at latest | the one real npm decision. `npm audit`: 0 vulnerabilities |
| **GitHub Actions** | 5 open Dependabot PRs, all majors: `checkout` 5→7, `cache` 4→6, `setup-python` 5→7, `upload-artifact` 4→7, `codecov-action` 5→7 | review and apply what passes the gates |
| **npm dev deps** | `typescript` 5.9.3 → **7.0.2 (major)**, `@types/node` 24 → 26 | majors, real breakage risk in the MCP build |
| **Elixir / OTP** | 1.18.3 / 27 (CI authoritative), Docker `elixir:1.18.3-otp-27` | **was missing from the previous plan.** Review; a bump moves CI `elixir-version`/`otp-version` **and the PLT cache key together** |
| **PostgreSQL** | `postgres:18-alpine` | **was missing.** Review |
| **BMAD core / bmm** | 6.11.0 | **was missing.** Review against upstream |
| **BMAD external modules** | `tea` v1.19.0, `cis` v0.2.1, `bmb` v1.8.1 — all pinned by sha | **was missing.** Review each pin |
| **BMAD `automator`** | version `main`, channel `next`, sha `0b94fd7` | **was missing, and it is the one worth attention:** it tracks a moving branch rather than a tag, so it can change under us with no PR and no visibility. The lane should decide whether to pin it — recorded either way |

Each update lands as **its own commit or commit group**, never folded into a
feature story. **What is deliberately not updated is reported with the reason** —
that report is part of the lane, not optional.

## Sequencing

```
Lane Z: #706 review conditions ──▶ ADR-0042 migration
        │
        ├── UI closer: #707 ──▶ #702, #700, #701, #703, #704 ──▶ #414, #672
        │                          │
        │                          └──▶ Agent surface: #705
        ├── Agent surface: ?since= human view (independent)
        ├── Derived values: #710 ──▶ #711
        ├── Signed decisions: #712, #709, #708 (independent of each other)
        └── Lane M: independent throughout
```

Hard constraints; everything else is free:

- **#705 after #700** — semantic dependency, not preference.
- **#414/#672 after #707** — the whole of D-2.
- **#711 after #710** — measure the mechanism you actually shipped.
- **Lane Z before any `epics.md` / `sprint-status.yaml` write.**

## If this batch must shrink

Named up front so a mid-sprint cut needs no new decision round — the gap Sprint
6 fell into. **The binding uncertainty is #707's output size:** a design spec's
consequences are not knowable before it is written, which is exactly why the two
builds that depend on it head the list. Cut in this order, stop as soon as it
fits:

1. **#672** — largest new surface.
2. **#414** — but cutting it breaks OQ-2's commitment for the second time, and
   that must be said in the briefing rather than absorbed.
3. **#708** — the least constrained of the three signed decisions; nothing
   degrades while it waits.
4. **#711** — #710 alone still fixes the defect; measurement can follow.
5. **Nothing else.** Lane Z, #710, #709, #712 and the UI defect set are not
   cuttable: Z protects this batch's own review and is a signed decision, #710
   is a live performance defect, #709 and #712 are small-to-medium with signed
   ADRs, and #702 leaves a phone tab unreachable.

## Explicitly out of scope

- **#572** — D-4; needs an ADR section before it is planned again.
- **The ADR-0038 amendment** named in ADR-0042's consequences. It is a decision
  about how the project decides, so it belongs to the owner.
- **The Round 7 gate-closure rule** (F8) — same reason, still unanswered.
- **FR-39/FR-40 themselves.** The derived-values lane ships the *mechanism*; the
  metrics that ride on it are not filed and are not in this batch.
- Anything behind B3.3, B3.4, B3.6, B3.7, B4.1, B4.2, or ladder level (d).

## Gates

Every commit passes the local gates; the branch rebases onto `main` at least
daily. Batch-level, per ADR-0026 step 3, with two additions this sprint:

- multi-role agentic review: correctness hunter, edge-case hunter, UAT persona
  walkthrough on seeded synthetic data, design critic against the living
  design-language spec — **all run under Lane Z's corrected conditions**;
- a dedicated verification pass on **#710's invariant** (the import scenario),
  per ADR-0036's risk-tier requirement, findings verified before they surface;
- the reviewer briefing calls out the risk-tier change, the #700 semantic
  decision, and what Lane M did **not** update.

## What "done" means for this sprint

1. `epics.md` and `sprint-status.yaml` carry one structure, and
   `sprint_plan.py validate` no longer returns schema-invalid keys.
2. The UI closer is closed — or its remainder is named in the briefing with the
   OQ-2 consequence stated, not absorbed.
3. `?since=` has a human view, or its absence is recorded as the close-out
   finding the two-way rule prescribes.
4. #710's invariant is pinned by a test that fails without the coalescing.
5. The maintenance lane reports what it did not update and why — **including the
   toolchain and BMAD rows, which is where the previous version of this plan was
   silent.**
6. Close-out per ADR-0026 step 5, including an **annotated** `0.7.0` tag —
   annotated, because F4 of the 2026-08-17 reconciliation found both existing
   tags lightweight.
