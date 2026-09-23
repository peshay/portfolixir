# Backlog triage — 2026-09-23: what is left, what it costs, and what should not be built

**Status: ADOPTED by the merge of the Sprint 15 planning PR.** The merge is the
signature (ADR-0026 step 1 as amended on PR #780). Each closure recommended in
Part 3 can be undone by a comment naming its issue on that PR; silence adopts
it. After the merge, Lane Z closes the issues **by hand**, with the reason
from this document, because a keyword would record "done" for work that was
never built.

**Why this document exists.** The owner asked three questions when opening
Sprint 15's planning: *how many real todos are left, how many sprints does
that last, and is everything on the waiting list actually worth building?*
The planning rounds so far answered "what next" each sprint. None of them
counted the whole list, and none argued a closure. This document does both
once. It is scoped to the backlog and does not replace the lane plan.

**Verification basis:** the open-issue list read 2026-09-23 after PR #846's
merge (**29 open**, bodies read, not titles); `epics.md`'s Requirements
Inventory and FR Coverage Map for the unfiled requirements; the code, read
for four claims the issues make about it (§2.3 names each read); the
releases (0.11.0 to 0.14.0 all published, so no rollback point is
outstanding); and the cadence of Sprints 9–14 (plans dated 2026-09-03, 09-05,
09-07, 09-12, 09-19, 09-20; Sprint 14 merged 09-23).

**Privacy.** No real instrument, position, balance, account or provider
relationship appears here. Where an issue body mentions the maintainer's own
setup, this document refers to its *shape* only.

---

## Part 0 — The count, in one table

The 29 open issues fall into eight groups, and only the first four contain
buildable work.

| Group | Issues | Count | Buildable? |
|---|---|---|---|
| **A. Sprint 14 closing-act findings**: verified, reproduced, small | #850 #851 #853 #854 #855 #856 #857 #858 | 8 | yes, about one lane |
| **B. Needs a decision** | #849 | 1 | not until decided (§3.7) |
| **C. Operator-floor features with a spec or close to one** | #328 #608 #354 #395 #481 #573 | 6 | yes, but two carry hidden debt (§2) |
| **D. Discovery-first** | #330 | 1 | a discovery story first (§3.8) |
| **E. Standing / blocked**: never "done" in a sprint | #314 (coverage ratchet, rides every batch) · #727 (Elixir/OTP, blocked upstream) | 2 | no; they ride Lane M |
| **F. Area trackers**: filing addresses, not work | #416 #417 #418 #419 #420 #470 | 6 | no |
| **G. Parking lots / umbrellas** | #340 #320 | 2 | no; **close** (§3.1, §3.2) |
| **H. Large features that should not be built as written** | #332 #333 #567 | 3 | **close** (§3.3–§3.5) |

**Real, buildable work inside the open list: 15 issues** (groups A, C, D),
plus one decision (B). The other 13 are trackers, standing lanes or items
this document recommends closing.

The issue list is not the whole backlog. Five **unfiled** requirements in the
registry carry real work, and two of them are this project's most valuable
remaining features:

| Requirement | Gate | Verdict |
|---|---|---|
| **FR-43 policy rules** | B3.6 | **Build, Sprint 15.** Gate closed by ADR-0049 on this PR. |
| **FR-41 contribution analysis** | ladder (b), ungated | **Build, Sprint 16–17.** Check against ADR-0041 first; it may be a thin extension of the category result. |
| **FR-46 / FR-47 predictions and calibration** | B4.2 | **Build only if the agent records predictions.** The agent asked (P1-2); ask it once more with E24 in hand. |
| **NFR-9 backstop meta-tests** (credential schema, bank-domain HTTP, non-goals) | none | **Build, small.** The registry says "this is a requirement, not an inventory". Rides Sprint 16. |
| **FR-42 exposure decomposition** | ladder (b) | **Retire** (§3.6). What is allowed already exists, and what does not exist is forbidden. |

And four stay in the registry **without a sprint**, deliberately:

- **FR-48** (rule evaluation) needs months of E24 findings before it has
  anything to score;
- **B3.5** (the rebalancing digest) needs E24 in use first;
- **FR-24 / FR-25 / FR-26** (pension modelling, retirement projection) are a
  product-sized domain, discovery-first by the PRD's own terms. Nothing on the
  current list depends on them;
- **FR-17–21** (read-only sync) are gated at B3.3. The external-agent route
  (read-only tooling outside the app feeds the agent, and the agent books
  through MCP) already works and keeps credentials out of the product.

---

## Part 1 — The runway: about three sprints of work worth doing

At this project's cadence, a sprint is **two to four days and 15–18 issues**
(Sprint 14: sixteen closed by keyword plus two by hand). Against that:

| Sprint | Content | Why here |
|---|---|---|
| **15** | E24 policy rules (ADR-0049) · the closing-act debt (group A, most of it) · the operator floor, first half: position-level SOLL entry (§2.1), #395's remainder (§2.2), #354 backup/restore | The rules gate was promised for this round (Sprint 14 D-6). The two human-view debts are older than the rule that should have caught them. |
| **16** | Lifecycle merges #328 + #608 under **one** ADR (risk-tier: reassignment and import idempotency) · NFR-9 backstops · #330's discovery story · FR-41's decision · #573 · whatever group A Sprint 15 shrank | These are the last operator-facing gaps with a spec. |
| **17** | FR-41 build · B4.2 predictions + calibration, **if** the agent's next round confirms it will record predictions | The last two agent-native features that are allowed and asked for. |
| **after** | **Maintenance mode**: Lane M, closing-act findings, owner dumps from live use, FR-48 / B3.5 once E24 has history | Nothing on the list after Sprint 17 is both allowed and asked for. |

So the honest answer: **roughly three sprints of planned product work,
about one to two weeks at the current pace.** After that, Portfolixir is
feature-complete against its own identity (the two-user statement in
AGENTS.md's Project Goal), and further work should come from use, not from
the list.

### 1.1 — The one thing that will keep the list from shrinking

The closing act files findings faster than the list can lose them. Sprint 13's
filed **six** outside its scope and Sprint 14's filed **nine**. Group A *is*
Sprint 14's closing act. Most of these are real, reproduced and cheap, and
nearly all belong to one class: **hostile input to a loopback,
single-operator API** — a 20-digit id, a 490-codepoint URL, `offset=10^20`,
`days=10^20`. They are worth fixing, and each fix removes a class, not an
instance. But in maintenance mode they would become the whole backlog, and a
sprint that exists to pay for the previous sprint's review is a treadmill.

**Recommendation, adopted as Sprint 15 plan D-9:** a closing-act finding is
filed with one of two reach labels: *user-reachable* (a person or the agent
hits it in normal use: #857, #858, #854, #851) or *hostile-input only* (it
takes a crafted request: #853, #855, #856). Hostile-input findings are batched
into a debt lane and never set a sprint's theme on their own.

---

## Part 2 — Two debts the issue list hides

Reading the bodies against the code found two gaps that no issue title says.
Both have the same shape as the finding in Sprint 14's D-2: a human surface
the records assume exists and the code does not have.

### 2.1 — Position-level SOLL can only be set over the API

#481 reads as "product direction, deferred slices". The code says more.
ADR-0030's slice 1 shipped per-position targets on the API and MCP, and slice
2a shipped their **display** on the allocation view. The **entry** was deferred
("the classifications editor UI for per-position SOLL entry"), and it has not
been built:

- `ClassificationsLive.parse_weight_entries/1` builds `%{category_id, target_weight}`
  entries and nothing else. The SOLL table's inputs are
  `name="weights[<category_id>]"` plus the cash target.
- No LiveView calls a position-target writer. The only writers are
  `target_controller.ex` and the MCP tools.
- The Wealth page nevertheless tells the operator to "align the position
  targets and the category weight on the Classifications page", a page where
  a position target cannot be set.

So the way the maintainer actually steers (the reason #481 exists, in its
own words) has had no human input since 2026-07-21. It predates the two-way
coverage rule of 2026-08-12, so no deadline was missed. It is the same kind
of debt as the risk lens was until Sprint 14.

**Verdict:** #481 is **rescoped** to exactly this entry surface and built in
Sprint 15 (plan Lane D1, pick F2). Its two convenience slices,
auto-distribution of a category weight across its positions and the
"Summenspiel" 100 %-per-level UX, are **closed as not planned**: the roll-up
of ADR-0030 §2 already derives a category's target from its positions, which
is the point of position-first steering. Auto-distribution adds a second way
to write the same numbers, and nothing in live use has asked for it since
July. Reopen on the first real complaint.

### 2.2 — #395 is half done, and the half that is left is the operator's

#395 lists three tasks from June. Read against the code:

1. **PP import mapping of cross-currency rows: done.**
   `Imports.Applier` populates `settlement_amount` and derives
   `settlement_fx_rate` (applier.ex, around line 1098). The issue was never
   updated.
2. **LiveView settlement inputs: not done.** The booking form
   (`transaction_management_live.ex`, `#transaction-form`) has type, date,
   depot, security, quantity, price, fees, taxes and note. It has no
   settlement field. A booking whose security currency differs from the
   depot's cash account fails validation with
   `settlement_fx_rate "is required for a cross-currency settlement"`, and the
   operator has no field to satisfy it. **Cross-currency buys can only be booked
   over the API.**
3. **The `gross_amount == settlement_amount` guard: decided, not built.** The
   owner decided on 2026-07-19 (issue comment) to add it, "defined net of
   fees/taxes with the ADR-0016 rounding tolerance". `Ledger.Transaction`
   requires the rate and checks its sign. It does not compare the two
   amounts.

**Verdict:** #395 is rescoped to tasks 2 and 3 and built in Sprint 15 (plan
Lane D2, pick F3). Task 3 is a ledger invariant, so it is **risk-tier**
(ADR-0036): its own commit, a verification pass, a briefing callout. Before it
is written, the lane checks that existing rows satisfy the new guard, because
a validation that historical data fails is a migration question, not a
changeset line.

### 2.3 — What was read

- `lib/portfolixir_web/live/classifications_live.ex`, `parse_weight_entries/1`
  and the `#soll-plan-form` markup (§2.1);
- `grep` for position-target writers across `lib/portfolixir_web/` (§2.1);
- `lib/portfolixir/imports/applier.ex` and `lib/portfolixir/ledger/transaction.ex`
  (§2.2);
- `lib/portfolixir_web/live/transaction_management_live.ex`, `#transaction-form`
  (§2.2).

---

## Part 3 — What should not be built, and why

Each item below is recommended for closure **by hand, with this reason**, after
the planning PR merges. A comment naming the issue number on that PR keeps it
open.

### 3.1 — #340, the wealth-management parking lot: close

The umbrella's own first line says none of its items is planned, and every
item has already found a home or a verdict:

- pension contracts and the withdrawal planner are **FR-24 / FR-25 / FR-26**
  in the registry, where they stay (Part 0);
- income and expense tracking: its own assessment says **No**;
- news per position is a **permanent non-goal** ("no raw news archive"), and
  its own assessment already moved it to "the agent with web search";
- broker API sync is **B3.3**;
- multi-user contradicts **NFR-6** and the identity statement;
- real estate is a separate product by the issue's own words;
- PP dashboard widgets: there is no plan to port them, and none should be
  made.

An umbrella that tracks nothing is not a todo. It is a place where ideas wait
to be mistaken for plans.

### 3.2 — #320, the agent roadmap P3/P4: close as superseded

Item by item:

- **earnings dates** and the **dividend calendar**: E23 (ADR-0048), catalog-wide;
- **watchlist**: E23 made the catalog, not the holdings, the default scope,
  and a security with no position has been first-class since then;
- **`securities_merge`** is **#608**, which stays;
- the **batch `quotes_sync` error report** is covered by Wealth's data notes
  (`Catalog.DataQuality`: stale and missing quotes, with the remedy inside,
  Sprint 12 Lane N);
- **docs screenshots**: the docs site and the closing act's screenshot
  convention.

The Tracker Index's **E8** line names #320 as its tracker. That line becomes
"no tracker (gated at B3.3)", and Lane Z makes the edit.

### 3.3 — #332, the what-if simulator: close

The feature has two halves, and neither should be built:

- **Its differentiating half is forbidden.** The "blind-follow series" and
  the "per-source verdict" replay a strategy over history it did not have.
  That is ladder level **(d)**, and FR-27's registry row already says so.
- **Its simple half is already answered.** "What if I had bought X on day D"
  is ADR-0027's snapshot counterfactual (buy-and-hold of a position set over
  real quote history) and ADR-0046's benchmark comparison ("bought once" and
  "as the portfolio's own savings plan" over any flagged catalog security).

FR-27's row becomes *retired 2026-09-23*. A future simulator would need a new
gate and an argument this list does not contain.

### 3.4 — #333, the PP XML import: close

The June case for it was three things PP holds and the CSV export does not:
classifications, quote history and master data. Three months later:

- **Classifications and targets are Portfolixir-owned** and survive a
  re-import (E18, ADR-0029). Importing PP's taxonomy would create a second
  source of truth for the one thing this product steers by.
- **Quote history** comes from the providers. For a security no provider
  covers, `PUT /api/v1/securities/:security_id/quotes` already accepts a
  history, and the agent can write one.
- **Master data** is maintained here.

What is left does not justify a three-phase parser with XPath-style reference
resolution plus an amendment of AGENTS.md's hard rule. If one gap is felt
later, it will be narrow, and it gets a narrow story.

### 3.5 — #567, the automation recipes: close

The only concrete recipe in the issue is the maintainer's own external broker
tooling. AGENTS.md's privacy rule forbids attaching a provider to the owner's
accounts, and a "synthetic" rewrite of a real private script disguises very
little. The issue itself adds a second constraint: the repository must not
appear to ship broker sync. The generic half, the reconcile-and-book guidance,
already lives where an agent reads it: the MCP tool descriptions (FR-32,
FR-35's resolution guidance). What remains is either private or already
done.

### 3.6 — FR-42, exposure decomposition: retire from the registry

- **Sector and region exposure** is the allocation breakdown over a
  classification tree whose categories are sectors or regions: goals 10 and
  12, shipped, with drift.
- **Factor exposure** needs either partial-weight assignments (advanced
  classifications: out of scope by `CONTRIBUTING.md`, and FR-42's own
  boundary says so) or external factor data (B3.3).

Nothing is left that is both allowed and new. The row becomes *retired
2026-09-23, covered by classifications; the remainder is out of scope*.

### 3.7 — #849, the conditional read for derived projections: keep, decide after E24

A scheduled run that re-reads valuation to learn whether anything changed
pays in tokens, not in risk. E24's findings read answers the question the run
actually has: **did anything cross a line**. Decide #849 at Sprint 17's
planning, with the agent's report of how it polls once rules exist. It may
then close as not needed.

### 3.8 — #330, bonds: keep, as a discovery story

The issue's serious claim is a **valuation error**: percent-quoted bonds
valued as `quantity × price`. Whether that is true depends on how a Portfolio
Performance export books a bond's quantity. If it books nominal / 100, today's
arithmetic is already right, and the issue shrinks to master data, which has
little value. One discovery story in Sprint 16, over a **synthetic** PP bond
fixture, answers it. Nothing is built before that answer.

---

## Part 4 — What this changes in the registry

Written into `epics.md` on this PR by Lane Z's planning half, and reconciled
at the Sprint 15 close-out:

- FR-27 row: **retired** (§3.3);
- FR-42: **retired** (§3.6);
- FR-43 row: **ADR-0049**, E24, issues filed at branch opening;
- FR-5 row: #333 **closed** (§3.4); XML intake stays forbidden by the hard rule;
- FR-4 row: unchanged (#328, #608 stay);
- Tracker Index: **E24** added; **E8**'s tracker reference removed (§3.2).
