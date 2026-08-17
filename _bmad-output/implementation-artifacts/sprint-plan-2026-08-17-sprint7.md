# Sprint Plan — Sprint 7 (ADOPTED, 2026-08-17)

**Status: adopted.** No draft preceded it: the questions a draft would have
asked were answered by the pre-sprint reconciliation (PR #714) and by ADR-0042,
which the owner signed off the same day.

**Revised twice on 2026-08-17.** First after owner challenge (deferral volume,
lane letters, maintenance scope); then after the four-role agentic review, which
found the first revision's central scope claim to be wrong in the direction that
suited it. Both revisions are recorded below rather than folded away.

Ground truth: `main` at `1a88ad5`. Verified against the merge commits
(`f0beb8c..1a88ad5`), the open pull-request list (8, all Dependabot), the
open-issue list (40), the Actions runs on `main`, and `scripts/version-report.sh`.

## What this sprint is

**The UI closer, and the first sprint under one planning structure.**

Sprint 6's OQ-2 committed Sprint 7 as the closer for "#672, #414 and whatever
Lane A's UAT surfaces". That commitment is **partly kept and partly renegotiated
in the open**, which is the honest position — see D-2 and "On OQ-2".

## Revision 1 (owner challenge)

**R-1 — the deferral principle was wrong.** The adopted version pushed #708 and
#709 to Sprint 8 on the grounds of "four money-domain items in one batch". That
counts items instead of sizing them. Actual sizes: **#710 heavy** (projection
and refresh semantics, risk-tier), **#712 medium** — ADR-0041 is explicit that
"nothing here has to be computed for the first time; it has to be **grouped**"
—, **#708 medium**, **#709 small** (ADR-0040 specifies it exactly). The same
document called #572's repeated deferral "bookkeeping theatre" and made the
identical move one section later.

**The principle that replaces the count:** what poisons a batch is
**unspecified** work, not domain concentration. Specification is the
discriminator.

**R-2 — the lane letters were inherited and inconsistent.** Sprint 5 used A–F
for six things; Sprint 6 used A–D for four different things; this plan's "Lane
D" would have been a third meaning, making cross-sprint references ambiguous in
a retrospective. Only two roles are stable — structural/close-out debt first,
maintenance always present — so those keep their letters and everything else is
named.

**R-3 — the maintenance lane was incomplete.** It covered npm and GitHub
Actions; `AGENTS.md` scopes it to "Hex, npm, Elixir/OTP, PostgreSQL, BMAD and
the external BMAD modules". `scripts/version-report.sh` had not been run. It has.

## Revision 2 (agentic review) — what the reviewers changed

**A-1 — the human-view scope claim was wrong, and wrong in a self-serving
direction.** The revision-1 plan rested on `human-view-debt-2026-08-17.md`
concluding that most of the FR-37/38 obligation was already discharged. It is
not. `fields=` is implemented on the **transactions and holdings** endpoints
only (`FieldSelection` is aliased there and nowhere else); the securities column
picker predates FR-37 and sits on the one list with **no** `fields=`. The
mapping was inverted, so the obligation is **two unbuilt surfaces**, not one.
Sprint 7's scope had been reduced on a false premise by the agent that would
otherwise have had to schedule the work. Both items are now in.

**A-2 — #672 was scheduled where the triage names #471, and #672 fails this
plan's own test.** The triage says "**#414 / #471** gain the UI dimension, and
should follow #707's output"; the plan wrote "#414 and #672", while the same
PR's `epics.md` row wrote it correctly. And of #672 the triage says the concrete
PP comparison "is a 20-minute question to the owner and **it changes the scope
materially**" — i.e. it is exactly the unspecified work R-1 says poisons a
batch. It was scheduled anyway and the exemption was never argued. **#471 is in,
#672 is out pending the owner question.**

**A-3 — the migration would have broken the batch that performs it.** Deleting
`development_status` makes `validate` fail on a *required* key, hard-fails the
status view this decision claims to keep, and deletes the
retrospective-completion ledger that ADR-0026 step 5 depends on — Sprint 7's own
close-out being the first casualty. ADR-0042 §4 is corrected; Lane Z now keeps
the `epic-N` and `epic-N-retrospective` keys and removes only the story rows.

**A-4 — the shrink order's top two entries were the sprint's commitment**, it
had no trigger and no evaluator, and Lane M was not in it at all. All three
fixed below. The claim that a mid-sprint cut "needs no new decision round" also
mischaracterised Sprint 6, whose amendment *was* a dated written decision round
and worked.

**A-5 — R-1 answered the counting argument but never the capacity one.** Sprint
6's OQ-2 rested on **reviewer capacity**, not on a count. Addressed in
"On capacity" below, rather than left standing.

## On capacity

Sprint 6 shipped 20 issues in 41 commits and its own close-out called it the
largest batch attempted, with one reviewer. This plan is larger. That is
deliberate and it is bounded by three things, stated so the bound can be
checked rather than assumed:

1. **Six of the items are defects on existing surfaces** (#700–#704, #702), not
   new subsystems.
2. **Only one item is risk-tier** (#710), against Sprint 6's one (Lane C).
3. **The shrink order has a trigger and a checkpoint** (below), so overrun is
   caught mid-sprint rather than reported at the briefing.

If the reviewer role is the binding constraint, the correct response is the
checkpoint, not a smaller plan chosen by guesswork in advance.

## On OQ-2

OQ-2 committed "#672, #414 and whatever Lane A's UAT surfaces". After the review:

- **#414** stays committed, sequenced after #707.
- **#471** is added — the triage's actual pairing, and it is *not* blocked by
  #707: its acceptance criteria specify reusing `view_switcher.ex`'s existing
  chip/link and a11y pattern, so it is a contained addition to a
  design-language component that already exists, not the redesign #707 governs.
- **#672 is out**, and this is a renegotiation of OQ-2 made **at planning time,
  in writing**, not absorbed in a briefing. It cannot be scheduled until the
  owner answers which PP screens and columns it is measured against. Recorded as
  an open item for the batch, not as a question blocking PR #714.

## Decisions

**D-1 — ADR-0042 is signed off (owner).** The migration runs as Lane Z; it is
execution, not decision-making.

**D-2 (revised twice) — #414 and #471 are built this sprint; #672 is not.** Per
A-2 and "On OQ-2".

**D-3 (revised) — #708 and #709 are in.** Per R-1; both carry signed ADRs and
bounded scope.

**D-4 — #572 stays out, third sprint running.** Not on capacity but on
specification. **Standing recommendation:** it should not appear in a sprint
plan again until an ADR section settles its three questions.

**D-5 (new) — #707 ships its spec in this batch and is not cuttable.** It is the
design equivalent of a decision gate under ADR-0038, and the triage calls it
"the largest remaining piece". The builds it governs (#414) are cuttable; the
spec is not.

## Batch topology

All lanes in ONE batch on one epic branch, one PR, rebase-merged per the
ADR-0026 amendment. Branch: `agent/claude/sprint7-ui-closer`.

## Lanes

### Lane Z — Structural and close-out debt (always first)

**Review conditions (#706)** first, because they change the quality of this
batch's own closing act: design-critic and UAT walkthroughs run in **DE**, at
**≤390 px** as well as desktop, against seed data that **triggers the finding
surfaces** (stale quotes, missing FX, unclassified securities, a plan short of
100 %).

**The ADR-0042 migration**, before any other lane writes to the planning
documents:

1. Condense each Epic Detail intent paragraph into the new **tracker index** in
   `epics.md` — one line per epic: name, tracker issue where one exists, intent.
   Not into issue bodies: `AGENTS.md` forbids the authoritative spec living
   there, and E7 has no tracker at all while E1–E5 point at issue lists.
2. Delete the Epic Detail sections and the `##### Story` rows; keep the
   Requirements Inventory, FR Coverage Map, scope-ladder boundaries and the
   dated reconciliations.
3. In `sprint-status.yaml`, remove **only the story rows** from
   `development_status` — the five schema-invalid `6-dx-*`/`6-c-1` keys and the
   E17/E18/E19 story keys. **Keep `epic-N` and `epic-N-retrospective`**, per
   ADR-0042 §4: `development_status` is a required key, the status view fails
   without it, and the retro-completion ledger has no other home.
4. Preserve #321's "working agreement" section into `AGENTS.md`, then close #321
   by hand with the reason — invalidated, not implemented, so no keyword.
5. Amend `AGENTS.md` where it references the removed structures — including the
   **Issue Tracking Convention** and Epic-Batch **step 5**. Both contain strings
   asserted verbatim by `test/portfolixir/workflow_docs_test.exs` ("Maintenance
   lane", "reviews available updates for Hex, npm, Elixir/OTP", "reports what it
   deliberately did not update", "invalidates rather than implements"); pasting
   #321's text can also trip `docs_test.exs`'s `@process_claims` refutation.
   **Run both meta-tests before committing this step.**
6. Sweep `docs/` for references into the deleted sections and repoint them:
   ADR-0027 (E16), ADR-0028 (E17), ADR-0029 (E18 + section H), ADR-0031 (E19),
   and `docs/development/pr-review-checklist.md`.

### The UI closer

1. **#707 — the design engagement.** Control vocabulary, card naming, and the
   two surfaces that predate the design language. Delivers a **spec**, and is
   not cuttable (D-5).
2. **#702 — Wealth tab row clips on a phone.** A #668 regression leaving the
   fifth tab unreachable at 390 px. Overflow fix; the burger-sub-item navigation
   question belongs to #707.
3. **#700 — asset class: stored vs. effective.** Render an inferred class as
   visibly *derived*, and pick one of stored/effective for the count, the filter
   and the quick-assign affordance. **Governs #705** — record the choice in the
   commit.
4. **#701** — headers through gettext, **plus** the meta-test that no
   field-definition label bypasses the catalog.
5. **#703** — the `trade_priced` row names its positions; Overview keeps the
   alarm, Wealth states the consequence.
6. **#704** — the ADR citation leaves user-facing copy, the computation-basis
   content stays, **plus** a meta-test that no gettext msgid matches
   `ADR-\d{4}`.
7. **#471** — visible portfolio selector, mirroring `view_switcher.ex`.
   Independent of #707.
8. **#414** — built against #707's spec.

### Agent and operator surface

- **#705** — data-quality predicates over the filter builder, API and MCP.
  **Strictly after #700.** Scope includes the **drift-threshold control** on the
  allocation surface: it is the same asymmetry from the other side, and
  specifying them together is cheaper than twice.
- **The `?since=` human view** — a changed-since surface with the deletion gap
  stated on it. Issue to be filed per ADR-0038.
- **The field-selection picker for transactions and holdings** — the item A-1
  recovered. These are the two endpoints that implement `fields=`, and neither
  has an operator affordance. Issue to be filed per ADR-0038.

### Durable derived values (risk-tier)

- **#710 — refresh on the invalidating write, coalesced. Risk-tier.** Invariant:
  one import must not produce thousands of full recomputations. `BlastRadius`
  widens most resource types to `:all` and an import bumps the version per
  booking, so **import is the acceptance scenario by construction**.
- **#711 — measure and activate the figures the operator waits on.**

### Shipping the signed decisions

- **#712 — category result** (ADR-0041). `Σ result ÷ Σ invested`, never a mean
  of percentages; underivable rows **excluded and named**. Also discharges the
  roll-up half of FR-37.
- **#709 — unallocated remainder** (ADR-0040).
- **#708 — transaction costs in the snapshot comparison** (ADR-0027 amendment).

### Lane M — Maintenance (always present)

Point-in-time picture from `scripts/version-report.sh`, 2026-08-17. **Split into
apply-candidates and review-and-report up front**, so "review and apply what
passes the gates" is not the decision rule for a TypeScript major:

| Ecosystem | State | Lane action |
|---|---|---|
| **Hex** | all 21 deps up-to-date | nothing to update — Dependabot's `mix` ecosystem correctly opened no PRs |
| **Hex advisories** | `cowlib` 2.19.0: EEF-CVE-2026-43966 (MEDIUM, HTTP response splitting) and -43969 (LOW) | **known, two different mechanisms.** `ci.yml:160` ignores the **LOW** under its three ids; the **MEDIUM** is why Hex is pinned to 2.4.1 for the retirement-only audit (`ci.yml:133-139`). No fixed release exists. **Lane job: re-check whether one shipped** |
| **GitHub Actions** (5 majors) | checkout 5→7, cache 4→6, setup-python 5→7, upload-artifact 4→7, codecov-action 5→7 | **apply-candidates** — gate-verifiable |
| **npm `zod` 3.25.76 → 4.4.3** | major, validation/error-shape changes | **review-and-report** — not applied this batch unless it proves trivial |
| **npm `typescript` 5.9.3 → 7.0.2** | major | **review-and-report** — real breakage risk in the MCP build |
| **npm `@types/node` 24 → 26** | major | review-and-report, decide with the TypeScript row |
| **Elixir / OTP** | 1.18.3 / 27 (CI authoritative) | review. A bump moves CI `elixir-version`/`otp-version` **and the PLT cache key together** |
| **PostgreSQL** | `postgres:18-alpine` | review |
| **BMAD core / bmm** | 6.11.0 | review against upstream |
| **BMAD external pins** | `tea` v1.19.0, `cis` v0.2.1, `bmb` v1.8.1 — pinned by sha | review each pin |
| **BMAD `automator`** | version `main`, channel `next`, sha `0b94fd7` | **the one worth attention:** it tracks a moving branch, so it can change with no PR and no visibility. Decide whether to pin — record either way |

Each update lands as its own commit or commit group. **What is deliberately not
updated is reported with the reason** — part of the lane, not optional.

## Sequencing

```
Lane Z: #706 review conditions ──▶ ADR-0042 migration (steps 1-6)
        │
        ├── UI: #707 ──▶ #414
        │    └── #702, #700, #701, #703, #704, #471  (independent of #707)
        │                │
        │                └──▶ Agent surface: #705 (after #700)
        ├── Agent surface: ?since= view, fields= picker (independent)
        ├── Derived values: #710 ──▶ #711
        ├── Signed decisions: #712, #709, #708
        └── Lane M: independent throughout
```

Hard constraints:

- **#705 after #700** — semantic dependency.
- **#414 after #707** — #471 is not subject to this.
- **#711 after #710.**
- **Lane Z before any `epics.md` / `sprint-status.yaml` write.**

## If this batch must shrink

**Trigger and evaluator, which the previous version lacked:** at the **daily
rebase**, the batch agent checks whether #707's spec is merged by **day 3** and
whether Lane Z is complete by **day 2**. If either misses, the next cut is taken
that day and **posted as a comment on the batch PR when it happens** — not saved
for the briefing. Saying it in the briefing is absorbing it.

Cut order, one consistent criterion — least-constrained first, nothing whose
absence leaves a defect live or a signed decision unshipped:

1. **`?since=` human view** and **`fields=` picker** — newly recovered, no issue
   filed yet, and their deferral has a *defined* consequence: the close-out
   finding the two-way rule prescribes.
2. **#708** — the least constrained signed decision; nothing degrades while it
   waits.
3. **#711** — #710 alone still fixes the defect.
4. **#414** — the last resort, because cutting it renegotiates OQ-2 a second
   time. If taken, it goes to the owner as a comment the day it is taken.
5. **Lane M's review-and-report rows** may compress to a report with no
   application; the apply-candidates and the advisory re-check stay.

**Not cuttable:** Lane Z (signed decision, and it protects this batch's own
review), #707 (D-5), #710 (live performance defect), #709/#712 (small-to-medium,
signed ADRs), and the UI defect set (#702 leaves a phone tab unreachable).

## Explicitly out of scope

- **#672** — needs the owner's PP-comparison answer first. Recorded open item.
- **#572** — D-4.
- **The ADR-0038 amendment** named in ADR-0042's consequences — owner's.
- **The Round 7 gate-closure rule** (F8) — owner's, still unanswered.
- **FR-39/FR-40 themselves** — the mechanism ships, the metrics are not filed.
- Anything behind B3.3, B3.4, B3.6, B3.7, B4.1, B4.2, or ladder level (d).

## Gates

Every commit passes the local gates; the branch rebases onto `main` at least
daily. Batch-level per ADR-0026 step 3, with three additions:

- multi-role agentic review **under Lane Z's corrected conditions**;
- a dedicated verification pass on **#710's invariant** (the import scenario),
  findings verified before they surface;
- **`workflow_docs_test.exs` and `docs_test.exs` run against every AGENTS.md
  edit in Lane Z**, since both assert exact strings in the sections it touches;
- the reviewer briefing calls out the risk-tier change, the #700 semantic
  decision, the OQ-2 renegotiation, and what Lane M did **not** update.

## What "done" means for this sprint

1. `epics.md` and `sprint-status.yaml` carry one structure, and
   **`sprint_plan.py validate` returns `valid: true`** — not merely "no
   unrecognized keys", which the migration could satisfy while leaving the file
   invalid on a missing required key.
2. `bmad-retrospective` detects Sprint 7's epic and its close-out runs.
3. The UI closer is closed to the extent D-2 commits, with the #672
   renegotiation stated in the briefing.
4. `?since=` and the `fields=` picker have human views, **or** their absence is
   recorded as the close-out finding the two-way rule prescribes.
5. #710's invariant is pinned by a test that fails without the coalescing.
6. Lane M reports what it did not update and why, **including the toolchain and
   BMAD rows**.
7. Close-out per ADR-0026 step 5, including an **annotated** `0.7.0` tag.
