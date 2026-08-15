# Owner Feedback Triage — 2026-08-15

Source: an unstructured owner feedback dump from day-to-day use of the live
instance, handed to the PM role. This document is the PM triage per ADR-0038.
Nothing here is a committed scope decision — issue creation awaits owner
confirmation, as in the 2026-08-12 round.

**Privacy note.** The dump referenced real plan weights, a strategy category of
the owner's own naming, and the instrument mix behind one data-quality count.
None of that is reproduced here. A plan weight is described by its *shape* ("a
top-level plan deliberately left just short of 100 %"), never by its value. The
instrument observation is kept only as a product fact about **quote-feed
coverage by instrument class**, not as a statement about anyone's holdings.
Data-quality counts are kept: they count catalog rows, not money.

**What this round is.** Five of the six design issues filed on 2026-08-12 —
#668 (tabs), #669 (period selector), #670 (contra-account), #671 (snapshots),
#673 (attention basis) — shipped in Sprint 6 and merged this week. The owner is
looking at exactly those surfaces. Under ADR-0026 step 4 and ADR-0038 there is
no separate per-epic UAT session; day-to-day observation *is* the acceptance
channel. So this dump should be read as **the acceptance round for Sprint 6's
design lane**, not as a fresh backlog.

---

## Part 0 — The two findings that govern the rest

### 0.1 — Portfolixir counts data-quality problems well and identifies them badly

Three separate observations in this dump are the same defect wearing three
costumes:

- *"Warning: 11 without asset class. I click it and every row shows a class."*
  The dashboard counts securities whose **stored** `asset_class` is `NULL`
  (`dq_findings/1`, `dashboard_live.ex:530`, linking to
  `?filter[]=asset_class:is_nil`). The list column resolves
  `Security.effective_asset_class/1` (`security_fields.ex:241`), which
  **infers** a class from name/ISIN/logo. So the count says "unclassified" and
  every row says "Equity". Worse: the inline quick-assign dropdown — the
  remediation affordance the whole filtered list was built for (#561) — only
  renders when the cell value is `nil` (`securities_live.ex:2191`). Because the
  value is the *inferred* class, it never appears. The fix loop is dead on
  arrival.
- *"A hint says a held position has no current price. But which one?"* The
  Wealth page's data-quality list names its rows in every entry — `no_price`,
  `missing_fx`, `unvalued_cash` all join their names — **except**
  `trade_priced`, which states a count and stops (`portfolio_live.ex:1746`).
  It is the one row the owner asked about, and it is the one row that withholds
  the answer.
- *"I can reach the stale-quote set only through the link on the main page, not
  through the filter menu."* Correct, and deliberate: `@dq_filters` are
  documented as "conditions that are not expressible as a plain column filter"
  (`securities_live.ex:45`). The filter builder offers Column / Operator /
  Value; "no quote in 7 days" is metric-derived and has no column.

The unifying statement: **a count you cannot resolve into named, actionable
rows is an alarm without an address.** Every one of these surfaces was built to
answer "does anything need me?" — and each stops one step before "what,
exactly?".

**And the agent half is worse, which makes this a two-way coverage finding.**
The owner's instinct in the dump is exactly right and worth quoting in effect:
*"I thought about a CSV export to show you — but forget it, that kind of access
should go through MCP by design, and then I can ask my other agent."* That is
the two-first-class-audiences identity (#663) applied correctly by the person
who decided it. Today it does not work: `portfolixir.securities.list` exposes
`query`, `sort`, `direction`, `holding_status`, `projection`, `limit`,
`offset`, `since` — and **no data-quality predicate at all**
(`mcp-server/src/tools.ts:1767`). The human UI can ask "which securities have
no quote in 7 days"; the agent cannot. That is the inverse of the gap the
coverage rule normally catches, and it is exactly what the close-out check in
ADR-0026 step 5 exists to find.

**Recommendation.** One story, both halves: the data-quality conditions become
first-class, addressable predicates — in the filter builder, in
`/api/v1/securities`, and in the MCP tool. Then the count links to a named set,
the set is filterable without a magic link, and the agent can be asked the same
question. No CSV export, per the owner's own routing.

### 0.2 — The design review ran and these still shipped

Sprint 6's batch carried the mandatory ADR-0038 design-critic pass against the
living spec. It nonetheless shipped: a tab row that clips on a phone, an
untranslated table header row on a DE-locale instance, an internal ADR
identifier in user-facing copy, and a cryptic "Σ-Konflikt" badge. Those are not
subtle. They are invisible only under the conditions the review actually ran
in: **desktop width, EN locale, seeded data that does not trigger the
finding surfaces.**

**Recommendation — a review-condition change, not a new gate.** The
design-critic walkthrough (and the UAT persona walkthrough beside it) gains
three binding conditions, recorded in `review-rubric.md`:

1. **DE locale**, because the app has exactly one translated locale and the
   owner runs it;
2. **a ≤ 390 px viewport** for at least one full pass, because the owner's
   primary casual-use device is a phone;
3. **seeded data that triggers every finding surface on the touched screens** —
   an unclassified security, a stale quote, a plan that does not sum to 100 %.

This costs one extra pass and would have caught four of the six confirmed
defects below. It is the cheapest item in this document.

---

## Part 1 — Confirmed defects (verified in code)

Each was checked against the tree at `93179b9`. All six are ordinary scoped
work; none needs a decision gate.

**F1 — The asset-class count, column and editor use three different
vocabularies for one concept.** The dashboard says "unclassified" (stored
`NULL`), the list column shows the inferred class as a plain badge
indistinguishable from a stored one, and the detail editor calls the same state
"Automatic". Three names, no visible relationship. Fix has two parts, and the
second is the real one: (a) render an inferred class as visibly *derived* — the
existing value-slot vocabulary already has the shape for "computed, not stated";
(b) decide which of stored-vs-effective the count, the filter and the quick-
assign affordance are keyed on, and use that one consistently. Today the count
is keyed on stored and the column on effective, which is why the surface
contradicts itself. Note the secondary consequence: the inline quick-assign
control is currently unreachable, so #561's remediation loop does not work.

**F2 — Securities table headers are never translated.** `SecurityFields`
carries hard-coded English `label:` values (`security_fields.ex:48–167`) and
`securities_live.ex:469` renders `column.label` raw. The *values* are localized
(`AssetClasses.label/1` runs through gettext), which is why the owner sees
German cells under English headers. `localization_test.exs` cannot catch this —
the strings never enter a gettext catalog, so there is nothing for the
meta-test to find missing. The fix is the labels through gettext **plus** an
extension to the meta-test that asserts no field-definition label bypasses the
catalog; otherwise the next field table repeats it.

**F3 — The Wealth tab row clips on a phone and cannot be scrolled — a
regression introduced by #668.** `.area-tabs` is `display: flex` with a gap, no
`overflow-x`, no `flex-wrap`, no scroll affordance (`app.css:4647`). Five Wealth
tabs, each now carrying an icon plus a German label, exceed a 390 px viewport;
the fourth ("Snapshots") lands half-cut and the fifth ("Tax") is unreachable.
The icons the owner likes are what pushed the row over the edge, so this is
literally #668's own side effect. Minimum fix: horizontal overflow with scroll
snap and an edge fade. **But the owner raised a better question than the bug** —
whether these belong in the burger menu as sub-items on small screens. That is
a navigation-model decision, not a CSS fix; it belongs to Sally (see D-block).
Recommendation: ship the overflow fix now because the fifth tab is currently
unreachable on a phone, and let the navigation question run separately.

**F4 — The "no current quote" data-quality row states a count and withholds the
names, and duplicates the Overview.** Both halves are real and they have
different fixes. *Naming:* it is the only row in that list that does not join
its entries — a one-line inconsistency against its own siblings. *Duplication:*
the Overview and the Wealth page both render a data-quality block linking to the
same `/securities?dq=stale_quote`. That is not automatically wrong — the
Overview is the "does anything need me?" surface and the Wealth page is where
the number is distorted — but the two say the same sentence twice. Proposal: the
Overview keeps the count as the *alarm*; the Wealth page states the
*consequence* ("N positions are valued at their last trade price, affecting the
total"), names them, and drops the restatement. That is a microcopy split with a
clear rule behind it, not a deletion.

**F5 — A user-facing string cites an internal ADR.** `"The comparison is gross
and price development only — dividends are not yet included (ADR-0027 v1)."`
(`snapshots_live.ex:343`, translated verbatim into DE). The owner is right that
this has no place in a product surface. The *content* is correct and must stay —
it is exactly the computation-basis disclosure the identity gate made
mandatory — but the citation goes. Worth one grep across the catalogs as part of
the fix; this is the only current instance, and a meta-test asserting that no
gettext msgid matches `ADR-\d{4}` would keep it the last one.

**F6 — Data-quality conditions have no API/MCP expression.** See Part 0.1.
Filed as its own item because it is the half that unblocks the owner's actual
stated workflow.

---

## Part 2 — Design and microcopy: one engagement, not six issues

Six of the owner's observations are the same request at different points on the
screen, and the owner said so explicitly: *"generally, creative UI ideas would
be great."* Splitting these into thin issues would be the wrong move — each fix
in isolation produces another locally-reasonable control, which is how the
surface got here. They go to the **UX designer role (Sally)** as one brief
against the living design-language spec (ADR-0038), which returns a `DESIGN.md`
/ `EXPERIENCE.md` amendment plus mockups; issues are cut from *that*.

**D1 — "Needs attention" / "Braucht Aufmerksamkeit" is a vague name for a
precise card.** The card contains exactly one thing: categories drifting beyond
±5 pp from their target weight. It is not a general inbox. An anthropomorphic
"needs attention" also sits awkwardly against the impersonal microcopy rule.
Recommended direction: name it for what it shows — EN **"Off target"**, DE
**"Ziel-Abweichungen"** — and keep the basis line #673 added. If the card is
ever meant to carry more than drift, that is a scope decision to take first;
naming a card for a future it does not have is what produced the current name.

**D2 — The filter menu is a query builder, and it reads like one.** Column /
Operator / Value with operator labels like "is unclassified" is a database UI
wearing a popover. It is also the most-used control on the securities page. The
design question is not "make the three dropdowns prettier" but **what the
common filters actually are** — held/not-held, unclassified, stale quote,
currency, asset class — and whether those become one-tap chips with the generic
builder demoted behind "more". This is where F6's data-quality predicates land
naturally.

**D3 — "Σ-Konflikt" is jargon, and the plan-sum warning fires on a deliberate
choice.** Two separate things, both worth carrying into the brief. The *visual*:
a warning-coloured `<summary>` pill inline in the category name cell
(`app.css:4987`), which is what the owner calls optically odd. The *semantics*,
which matter more: the plan editor flags any sum ≠ 100 % as a mismatch
(`is-target-mismatch`, red ✗). A plan deliberately left short — because one
satellite category is intentionally not fully used — is a legitimate,
well-understood state, and the UI has no way to say it. Proposal for the brief:
an **explicit unallocated remainder**. The plan states the gap on purpose, the
editor shows it as a named row rather than an error, and the warning is reserved
for sums *over* 100 % and for genuine position-vs-category conflicts, which are
the two states that really are wrong.

**D4 — "Ansicht:" and "Verwalten…" are labels standing in for design.** A
label-colon prefix on a switcher and a trailing-ellipsis "manage" link are both
the shape a control takes when nobody decided what it should look like. Part of
the same brief.

**D5 — Custom date-range selection.** Shipped in Sprint 6 as part of #669: a
`<details>` disclosure holding two date inputs (`portfolio_live.ex:945`). It
works and it is not good. Range selection is a well-solved interaction pattern
and this is not one of them.

**D6 — The Wealth tabs on small screens (from F3).** Whether five icon+label
tabs remain a tab row at phone width, or become burger sub-items as the owner
suggested. A navigation-model question; it should be answered for *all* tab
rows (Wealth, Transactions, detail panes), not for Wealth alone.

**Recommended shape of the engagement.** One design session with Sally covering
D1–D6 plus the transactions and income surfaces from Part 4, held against
`DESIGN.md` / `EXPERIENCE.md`, with Portfolio Performance as the explicit
comparison object for the two views where the owner keeps naming it. Output:
spec amendment + mockups → then issues. This is a larger ask than any single
item and it is the right size for what the owner actually asked for.

---

## Part 3 — The one genuine product question: the cost of restructuring

The owner asks whether the snapshot comparison factors out fees and taxes — the
**cost of restructuring** — so they can see whether the changes are ahead
*before* those costs are earned back.

**Answer: no, and the comparison is currently biased against the real side by
exactly that amount.** The counterfactual side values the frozen holdings
buy-and-hold over stored quotes: *"No trades and no flows enter this side"*
(`snapshot_comparison.ex:14`) — it pays nothing, ever. The real side is TTWROR
from the performance walk, where *"Dividends, interest, fees and taxes are
internal (they are return)"* (`performance.ex:17`) — so every fee and every tax
actually booked depresses it. The two sides are therefore not measured on the
same basis, and the frozen side wins by default for as long as the rebuild costs
are unrecovered. The v1 note discloses the *dividend* asymmetry (F5) and is
silent on the cost one, which is the larger of the two in the first months —
precisely the window the owner is asking about.

**This is a good product question and it is well-formed.** The owner is not
asking to hide the costs; they explicitly say the costs have to be earned back.
They are asking to separate two things the single number conflates: *was the
restructuring right?* and *has it paid for itself yet?*

**Proposal for the decision gate.** A second figure beside the real TTWROR:
return **gross of transition costs** — the same walk with fees and taxes booked
in the comparison window treated as external rather than internal — plus the
cumulative cost figure itself, stated in currency. Three properties make it
honest: the cost-free figure is never shown alone; the cost total is always
beside it; and the payback framing ("N of the restructuring cost recovered") is
the natural third line. This is level (b) analytics under the identity gate's
scope ladder — decomposition of a return the system already computes — so it is
in scope, and the computation basis disclosure it needs is the same one F5
cleans up.

It amends ADR-0027 (the comparison's basis) and should be decided there rather
than bolted on as a field. It is the most valuable single item in this dump.

---

## Part 4 — The two standing PP-parity complaints

Both are re-statements of known gaps, and both are worth recording again
*because* they were restated — a complaint the owner makes twice unprompted is a
priority signal.

**Income ("Erträge") is far from the PP overview.** Tracked as **#672** (the
`/cashflow` parent and its three specified-unbuilt facets: realized gains,
deposits & withdrawals, costs), the only issue from the 2026-08-12 batch still
open. The design spec already carries the facets. What #672 does not carry, and
should before it is scheduled, is the concrete PP comparison: which PP screens
the owner is measuring us against, and which of their columns matter. That is a
20-minute question to the owner and it changes the scope materially.

**Transactions are cluttered and PP is better and more informative.** Tracked as
**#414** (turn the flat list into a usable overview — filters, grouping, running
balance, summaries) and **#471** (visible portfolio selector), both under epic
tracker #470, both open since June. The owner adds a third dimension the issues
do not mention: *the UI itself is poor there*, not just the information density.
`transaction_management_live.ex` is one of the oldest screens in the app and
predates the design language entirely. Recommendation: fold the transactions
surface into the Part 2 design engagement rather than implementing #414 against
the current visual vocabulary — otherwise the information fix ships onto a
screen that then needs a second pass.

---

## Part 5 — Dedup against the pipeline

| Observation | Status |
|---|---|
| Wealth tabs carry icons | **Shipped** (#668, Sprint 6) — F3 is its regression |
| Attention card names its basis | **Shipped** (#673) — D1 is about its *name*, not its basis |
| Snapshots surface reworked | **Shipped** (#671) — F5 is a leftover string in it |
| Period selector + custom range | **Shipped** (#669) — D5 says the range half is not good enough |
| Data-quality counts link to a fixable list | **Shipped** (#561/#651) — F1 and F6 are why the loop does not close |
| Sparse fieldsets, `?since=` delta reads | **Shipped** (#665/#666) — F6 extends the same surface |
| Income view set | **Open, #672** — needs the PP comparison scoped before scheduling |
| Transactions overview | **Open, #414 + #471** under #470 — add the UI dimension |
| CSV export of a filtered securities list | **Declined by the owner in the dump itself** — MCP is the intended access path (F6) |
| Σ-conflict badge semantics | Part of ADR-0030 slice 2a as shipped; D3 proposes the missing *unallocated remainder* concept |

---

## Part 6 — Proposed sequencing, and what needs owner confirmation

Nothing below is committed. Recommended order:

**Immediately, no gate — one small batch:**

1. **F3** (tab overflow) — the fifth Wealth tab is unreachable on a phone today.
2. **F5** (ADR string) + the `msgid` meta-test — one commit, trivial.
3. **F2** (untranslated headers) + the field-label meta-test.
4. **F4** (name the positions, split Overview/Wealth microcopy).
5. **F1 + F6** together — the stored/effective decision, the dead quick-assign
   affordance, and the data-quality predicates over filter builder + API + MCP.
   Largest of the group; risk-tier attention is not needed, but it is the one
   that wants its own commit group.

**In parallel, no code:**

6. **The 0.2 review conditions** — DE locale, ≤ 390 px, finding-triggering seed
   data — into `review-rubric.md`.
7. **The Part 2 design engagement** with Sally (D1–D6 + transactions + income),
   returning a spec amendment and mockups. Issues are cut from its output.

**Then, behind a decision gate:**

8. **The ADR-0027 amendment** for the cost-of-transition figure (Part 3).

**Open for the owner — three questions, all of which change the work:**

- **Q1.** Part 3: is "return gross of transition costs, with the cost total
  always beside it" the figure you want, or do you want the payback framing
  ("N % of the restructuring cost recovered") as the primary number?
- **Q2.** D3: confirm that a plan deliberately summing to under 100 % should
  become an explicit **unallocated remainder** rather than a warning — that is a
  semantic change to plans, not just a visual one.
- **Q3.** Part 4: which Portfolio Performance screens are you measuring Income
  and Transactions against, and which of their columns matter? Screenshots or
  column names are enough; this scopes #672 and #414 materially and is currently
  guesswork on our side.

---

## Round 2 — owner responses (2026-08-15, same day)

### A1 — Both figures, and the name was wrong

The owner wants **both** halves: the return without the costs, *and* whether
those costs have been earned back yet. And — correctly — flags the working term
"Umbaukosten" / "restructuring costs" as off.

**The term was wrong for a reason worth writing down.** "Restructuring costs"
claims an attribution the arithmetic does not have: it implies these costs were
*caused by the switch*. Whatever we subtract, we subtract by rule, not by
knowing why a trade happened. A name that asserts causality the computation
cannot establish is the same defect as a metric without a computation basis —
which is what the identity gate made review-blocking in the first place.

**Recommended definition, and it is the narrow one:** fees and taxes booked on
`buy` / `sell` transactions inside the comparison window. That *is* honestly
attributable — a fee on a trade is caused by that trade, no inference needed —
and it is what the owner is actually asking about. It deliberately leaves
dividend and interest taxation alone, which belongs with the dividend
asymmetry the v1 note already discloses and should be fixed there, not here.

**Naming: `transaction costs` (EN) / `Transaktionskosten` (DE).** Precise,
standard in the domain, and it overclaims nothing. It also has a quiet
advantage the "Umbau" framing lacked: it stays meaningful when the owner did
*not* restructure at all — a snapshot taken as a plain checkpoint still shows
what trading since then has cost.

**The figure set, then, is four numbers and one sentence:**

| Slot | What it is |
|---|---|
| Frozen return | The counterfactual, unchanged — buy-and-hold of the frozen holdings |
| Real return | TTWROR as shipped today: net, every booked fee and tax inside it |
| Real return before transaction costs | The same walk with window trade fees/taxes treated as external |
| Transaction costs | The sum itself, in currency and in percentage points |

Plus the recovery line the owner asked for, which is the comparison of the
first and second slots against the fourth: how much of what the trading cost
has been earned back by the difference the trading made. Three honest states,
and the third is the one that makes the figure worth having:

- **earned back** — the real net return is ahead of the frozen one;
- **partly earned back** — the pre-cost return is ahead, the net one is not
  yet, with the remaining gap stated;
- **not earned back** — the pre-cost return is behind too, so the costs are
  not the reason and the changes have not paid off on their own merits.

That third state is the whole point of separating the two questions. Today one
number conflates "the decisions were wrong" with "the decisions have not paid
for themselves yet", and those call for opposite responses.

**Rule for the ADR: the pre-cost return is never rendered alone.** It always
carries the cost figure and the recovery state beside it. On its own it is a
number that flatters, and this is a system whose value rests on producing
figures that can embarrass their author.

### A2 — Unallocated remainder: confirmed

A plan deliberately summing to under 100 % becomes an **explicit unallocated
remainder** (D3), not a warning. Consequences to carry into the design brief
and the story:

- the remainder is a **named row** in the plan editor, stated on purpose, not
  an error state;
- the red ✗ / `is-target-mismatch` cue is **reserved for sums over 100 %** and
  for genuine position-vs-category conflicts — the two states that really are
  wrong;
- **drift is computed against the allocated portion**, so an intentionally
  unused category does not smear a phantom deviation across the siblings and
  into the Overview card;
- the remainder needs a place in the API and MCP plan payload, or an agent
  reading the plan sees weights that do not add up and has to guess.

This is a semantic change to plans, not a visual one — so it rides ADR-0020 /
ADR-0027 / ADR-0030 rather than the design brief alone. The design brief owns
how it *looks*; the plan semantics need their own short decision.

### A3 — Income was already scoped; Transactions gained a concrete shape

**Income: the question was redundant and the owner said so.** The PP
walkthrough is recorded in the 2026-08-05 triage under "Income view — scoping
input from the owner", and it is specific enough to build from: bar charts per
month/quarter/year (keep, good); an **accumulated-per-month chart** (wanted,
"great as a chart"); per-instrument tables explicitly **not** wanted, because
even PP's are unreadable; taxes and fees at overview level only; closed trades
valued; deposits/withdrawals wanted. Plus a terminology requirement — our
income view must state what it aggregates rather than inheriting PP's unclear
"Erträge" vs. "Dividenden" split.

**Action: fold that section into #672 as its scope, and drop the discovery
question.** Asking again was a process failure of this triage, not an open
question: the answer had a home and it was not read before the question was
put. That is the same rot Q3 of the 2026-08-12 round diagnosed — a decision
recorded in a planning artifact that the backlog cannot see — showing up one
level higher, in an artifact that *had* been written.

**Transactions: PP's Trades view, named concretely.** Per position, its start
date and end date, whether it is still open, and the return achieved. Most of
this already computes: `Ledger.TradeMatcher` folds priced buys and sells into
`closed_trades` (one entry per sell, weighted-average cost across consumed
lots) and `open_lots` (remaining unmatched buys, oldest first), and it is
exposed over the API and in the Securities detail pane. What is missing is a
**surface** and two derived fields — the holding period, and the return per
round-trip — plus the open side, where "still open" and the unrealized figure
come from holdings rather than from the matcher.

So this is largely a surfacing story, and it is the second time the same
computation has been identified as built-but-unsurfaced: the 2026-08-12 round
recorded "how well did I sell" as *computed and exposed, missing only its
cash-flow surface". A Trades view and that facet are plausibly one thing seen
from two directions — worth resolving before either is scheduled, so we do not
build the same table twice under two names.

**And one genuinely new idea, which is the most interesting item in this
round.** The owner wants the same treatment for **categories**: concrete
performance figures per category, inspectable as charts — and notes that PP
does not have this.

That reading is right, and it matters. PP's classifications are a *structure*
for allocation; they carry no performance series of their own. A category that
knows its own return turns the classification tree from a way of describing the
portfolio into a way of **evaluating** it: which part of the strategy is
actually working, not merely how much of it there is. It composes directly with
the target/plan family (ADR-0020/0027/0030) — a category that carries both a
target weight and a realized return is the pair a rebalancing decision actually
needs, and today the owner has only one of them.

**Scope placement.** This is level (b) on the identity gate's scope ladder —
comparison and decomposition, contribution analysis — which is **in scope**,
so it needs no new permission. Three things it does need:

1. **A computation basis, stated in the payload** (review-blocking, and here it
   is genuinely hard rather than ceremonial): a category's membership changes
   over time as securities are classified and reclassified, so the ADR must
   decide whether the series follows *today's* membership backwards or the
   membership as it stood on each day. Those are different numbers and both are
   defensible; what is not defensible is shipping one without saying which.
2. **The derived-value layer as its substrate** — ADR-0039 shipped in Sprint 6,
   and a per-category daily walk is exactly the kind of value that must be
   materialized rather than computed per page view.
3. **A decision on contribution vs. return**: a category's own return
   (how did this part perform?) and its contribution to the total (how much did
   it move the needle?) are different questions with different arithmetic. The
   owner's phrasing points at the first; the rebalancing use points at the
   second. Probably both, but the ADR should say so deliberately rather than
   discover it in review.

Recommendation: this is not a Transactions story and should not be filed under
#414. It is its own decision gate — small, well-motivated, and squarely inside
what the identity gate already opened. Given that it is also the first feature
in a while where we would be **ahead of Portfolio Performance rather than
catching up**, it deserves to be sequenced on purpose rather than queued behind
the parity work.

### Revised sequencing after Round 2

Unchanged for the defect batch (F1–F6) and the review conditions (0.2). The
design engagement now carries the unallocated-remainder semantics as an input
rather than an open question. Beyond that:

- **ADR-0027 amendment** — the pre-cost return, the transaction-cost figure and
  the recovery state (A1). Ready for the gate; the definition is settled.
- **Plan semantics decision** — the unallocated remainder in the plan model,
  the drift computation and the API/MCP payload (A2). Small, and it blocks the
  visual work rather than following it.
- **#672 rescoped** from the 2026-08-05 walkthrough; discovery question closed.
- **Trades view** — reconcile against the "how well did I sell" cash-flow facet
  before filing, so one table is built once.
- **Category performance** — its own decision gate (A3), sequenced on purpose.

**Nothing further is open for the owner.** Issues on confirmation.

---

## Round 3 — issues filed (2026-08-15)

The owner confirmed the routing, so the confirmed items became thin issues per
ADR-0038. From here the backlog, not this document, answers "is it done?".

### Confirmed defects

| Issue | Item | Parent |
|---|---|---|
| #700 | F1 — asset class: stored vs. effective, and the dead quick-assign affordance | #417 |
| #701 | F2 — securities table headers bypass gettext | #356 |
| #702 | F3 — Wealth tab row clips on a phone (#668 regression) | #356 |
| #703 | F4 — "no current quote" withholds its positions; Overview/Wealth duplication | #356 |
| #704 | F5 — ADR identifier in user-facing copy | #356 |
| #705 | F6 — data-quality predicates over filter builder, API and MCP | #419 |

#705 depends on #700: the predicate has to mean what the count means, so the
stored-vs-effective decision governs both.

### Process and design

| Issue | Item | Parent |
|---|---|---|
| #706 | 0.2 — design-critic and UAT review conditions (DE locale, ≤390 px, finding-triggering seed data) | #420 |
| #707 | Part 2 + Part 4 — the design engagement (D1–D6, Transactions, Income) | #356 |

### Not filed, deliberately

The three decision gates: the **ADR-0027 amendment** (pre-cost return,
transaction costs, recovery state), the **plan-semantics decision** (explicit
unallocated remainder, drift against the allocated portion, the payload), and
**per-category performance**. Each needs its ADR signed off before an issue
would carry any authority — filing them now would produce titles with no spec
behind them, which is the failure mode this repository's issue convention
exists to prevent.

Two are ready for their gate the moment the owner wants them scheduled: the
ADR-0027 amendment's definition is settled in A1, and the plan semantics are
settled in A2. Per-category performance still needs its membership-over-time
basis decided, which is the substance of its ADR rather than a preliminary.

### Backlog updates that follow from this round

- **#672** takes its scope from the PP walkthrough in
  `feedback-triage-2026-08-05.md`; the discovery question is closed.
- **#414 / #471** gain the UI dimension, and should follow #707's output rather
  than land on the pre-design-language screen.
- The **Trades view** is not filed yet on purpose: it must first be reconciled
  against the "how well did I sell" cash-flow facet from the 2026-08-12 round,
  so one table is specified once rather than twice under two names.

---

## Round 4 — decisions written (2026-08-15)

The three gate items are now written decisions rather than recommendations, so
this triage closes here: the ADRs and the backlog carry it from now on.

| Decision | Status | Issue |
|---|---|---|
| [ADR-0027 amendment](../../docs/decisions/0027-plan-versions-and-depot-snapshots.md) — the comparison states its transaction costs (A1) | Accepted | #708 |
| [ADR-0040](../../docs/decisions/0040-unallocated-remainder-in-target-plans.md) — a target plan states its unallocated remainder (A2) | Accepted | #709 |
| [ADR-0041](../../docs/decisions/0041-per-category-performance.md) — per-category return and contribution, current membership + restatement marker (A3) | **Proposed** | none yet, by design |

Three things settled in the writing that the triage had left one level too
abstract, and each of them changes the work:

**The cost boundary is narrower than "fees and taxes".** Only fees and taxes
*carried by a `buy` or `sell`* leave the return. A standalone `fee` or `tax`
booking — a custody charge, an account fee — stays internal, because the frozen
holder would have paid it too; removing it would flatter the real side rather
than level the comparison. Dividend and interest taxation stays internal as
well, with the dividend asymmetry it belongs to.

**The remainder forces a second change nobody asked for, and it is the
important one.** Making the unallocated share explicit is cosmetic on its own.
What matters is that drift must then be computed against the **allocated
portion**: today a deliberately unused category has its share redistributed as
apparent overweight across its siblings, and the Overview's attention card
reports deviations that are an artifact of the gap. That makes ADR-0040
risk-tier work — it changes a number the operator steers by — rather than the
visual fix the original observation looked like.

**Per-category performance is one decision away from ready, and it is not the
one the triage predicted.** The membership-over-time question first looked like
"both are defensible, one is costlier": as-of membership *is* reconstructible,
because `upsert_assignment/4` journals every custom-tree assignment with its
before-image and Catalog journals the security fields the built-in trees derive
from. Checking *when that recording started* settled it instead —
`20260623130000_arm_assignments_journal.exs` armed assignment journaling on
**2026-06-23**, while holdings histories here come from Portfolio Performance
imports spanning years. An as-of computation would therefore be exact for the
weeks since and fall back to current membership for everything before it: not
better-but-costlier, but **costlier and, over the period that carries the
history, the same answer**.

ADR-0041 accordingly decides **current membership plus a restatement marker** —
a category whose composition changed inside the reported window says so, because
a return series that moves without a trade otherwise reads as an arithmetic
error. That is Part 0.1 of this triage applied to a figure instead of a finding.
The basis is the only thing needing an owner yes; the as-of variant is worth
revisiting when the recorded history is long enough for the two to genuinely
diverge, which is a matter of elapsed time rather than engineering.

*(An earlier revision of this section and of ADR-0041 §4 named the audit-journal
rollout (#677) as the precondition for as-of membership. That was wrong:
assignment writes have been journaled since 2026-06-23, so #677 blocks other
write paths, not this one. Corrected the same day, before the decision was acted
on.)*

### Where this round ends

Ten issues (#700–#709), two accepted decisions, one proposed. The design
engagement (#707) is the largest remaining piece and is a UX-designer
engagement, not a PM one. Nothing from this dump is unrouted.

---

## Round 5 — the category figure, corrected down (2026-08-15)

The owner read ADR-0041 and rejected its shape: *"you are overcomplicating this.
I wasn't thinking about history at all. I just wanted the trade return to stand
on the category too — how much percent gain or loss they have together — and then
I expand it and see which position inside was how good. An extra hint would just
bother me there."*

**That is a smaller feature than the ADR described, and the difference is not
scope — it is kind.**

A per-category return **over a period** needs to know who was in the category
when, which is where the membership problem, the journal-arming date and the
restatement marker all came from. A roll-up over the **current composition**
makes no claim about a period at all: *the positions filed here right now are
collectively up X %.* True by construction however often the tree was
reorganised. No history, no restatement, no marker — and the owner's instinct
that the marker would be noise is right twice over, because under this framing it
would also be false.

Every number it needs exists: `holdings.list` already returns base-currency cost,
market value and the ADR-0033 result per position with its `decomposed: false`
contract, and the tree already maps each security to one category. The work is
grouping, not computing.

**The owner also produced the better argument against the series variant**, and
it is architectural rather than economic: measuring a category over time means
treating category changes as events — and then, consistently, bucket and view
changes too, and computing across all of them. That is organisational metadata
leaking into the ledger, which is the one place this architecture keeps clean.
ADR-0041 §6 now rests on that, not on an effort estimate.

**And the owner named the natural second slice**: realized gains from sells, plus
dividends, attributed to the category. Same framing, same absence of a membership
problem, so it is a second slice rather than a second decision — with the rule
that the category row states which components it includes, so the aggregate does
not quietly change meaning between screens.

### The process finding, which is the reusable part

The request was a table column. It was generalised into its most powerful form
before it was satisfied in its plain one, and every difficulty of the previous
two rounds — the membership question, the journal-date correction, the
restatement marker, the three-option recommendation — followed from the
generalisation rather than from the problem. The membership question was not
solved; it was **removed**, by building what was asked for.

Worth carrying beyond this document: *when a request names a screen and a
control, the first design is the one that fits that screen.* The general version
is a separate proposal that has to argue for itself, and stating it as the
default hides how much was invented rather than asked for. ADR-0041 records the
same finding in "How this decision was wrong first", where the next reader of
that decision will actually encounter it.

The correction is recorded rather than edited away: the over-built version was on
the PR for roughly three hours, and Rounds 3–4 read differently without knowing
that.

---

## Round 6 — the category history is not off the table (2026-08-15)

Two owner questions closed the round, and the first one corrects this document
rather than adding to it.

**"Is the ledger category history off the table for you? Wouldn't that be a
feature worth building?"** — It is not off the table, and Round 5 pushed it too
far away. The owner's argument was against booking classification changes into
the **transaction ledger**, which is right and stands:
`Ledger.Projection.effects/1` owns a closed set of booking kinds and raises on an
unknown one by design (ADR-0011), so organisational metadata booked there is the
corruption that guard exists to prevent. Round 5 then applied that argument to
the whole idea — but a **membership timeline** (a small append-only record of
which category held a security between which dates) is not the ledger and none of
it applies.

**And deferring it loses nothing, which is the unusual part.**
`upsert_assignment/4` journals `:create`, `:update` with the prior assignment as
its before-image, and `:delete`, continuously since
`20260623130000_arm_assignments_journal.exs`. The raw material is therefore
already accruing without anyone deciding to build anything. A history feature
normally gets more expensive the longer it waits, because the history is being
lost meanwhile; here the recorded span grows for free and the right moment to
build is simply when it covers a period a reader would ask about.

ADR-0041 §6 is rewritten accordingly: refused / not refused / why later is free.

**"Didn't we have the idea of a version counter on the ledger — recompute only
on change, store results once computed?"** — Yes, and it shipped in Sprint 6 as
**ADR-0039**. `Portfolixir.Derived` is one mechanism with three lifetimes; a
`:durable` value is a row in `derived_values` carrying `as_of` and
`data_version`, every read composes the basis's current data version and the
analytic's computation version into its key, and every write announces itself
through `Derived.Invalidation` **inside its own transaction** — so a read after a
committed write cannot be served a pre-write value.

Worth recording because it answers the owner's worry directly: **reclassification
already invalidates correctly.** Assignment writes pass through
`Journal.record`, which calls the invalidation seam; `Derived.BlastRadius` does
not list `security_category_assignment`, and its documented rule is that anything
unproven widens to `:all`. So a reclassification triggers a broad recomputation
rather than serving a stale figure — the safe failure direction, asserted by
`blast_radius_widening_test.exs`.

The practical consequence for the roll-up in ADR-0041: it needs no invalidation
work of its own. The mechanism it would ride is built and already covers the one
event that changes its inputs.

---

## Round 7 — why "computing" is still everywhere (2026-08-15)

The owner: *"if we already have all the numbers computed, why am I still shown a
'computing' cue for a second, on all sorts of figures? They should be held ready
and refreshed automatically."*

Three causes, verified in the tree, and the third is a finding against our own
process rather than against the code.

**1. Almost nothing is activated.** `Derived.Registry` holds **two** analytics;
`config/config.exs` activates exactly one at `:durable`
(`lifetimes: [performance_analysis: :durable]`). Everything else the operator
looks at — valuation, allocation and drift, holdings, income, tax, risk, the
snapshot comparison, the securities metrics — is not registered at all and is
recomputed on every read exactly as before ADR-0039. The cues are not cache
misses; those figures were never in the layer.

**2. Even the activated value is refreshed by its next reader.**
`Performance.Warmup` triggers on boot and on day rollover. Neither is a write. So
after any booking: the version bumps, the entry goes stale, and the first page
view pays the recomputation synchronously. "Paid once per invalidation rather
than per mount" is true and is not what was asked for.

**3. The push half was the gate's second ask and never reached the decision.**
The 2026-08-12 triage, Q2, states it in the owner's terms: recomputation should
be triggered by the write that invalidated it, or by a schedule — *"so that a
read is never the thing that pays"*. ADR-0039 decided durability and is silent on
push. Nobody removed it; it fell out between the gate and the ADR, and no step
compared the two.

**The process finding, which outlives this fix.** A decision gate is opened on a
set of asks and closed by an ADR, and nothing in ADR-0026 checks that the ADR
answers the asks the gate was opened for. Here that cost the more visible half of
the feature and it went unnoticed through the batch, the review closing act and
the close-out — because every one of those holds the work against the *ADR*, and
the ADR was internally complete. Worth carrying into the gate step: an ADR that
closes a gate names the asks it is answering **and the ones it is not**, so a
silent drop becomes a written deferral.

### Filed

| Issue | Item |
|---|---|
| #710 | Refresh on the invalidating write, coalesced — ADR-0039 amendment §§1–3, risk-tier |
| #711 | Measure and activate the figures the operator waits on — ADR-0039 §2 and amendment §4 |

The coalescing in #710 is not a refinement: an import bumps the version per
booking and `BlastRadius` widens most resource types to `:all`, so an uncoalesced
refresher would turn one import into thousands of full recomputations. Import is
the worst case by construction and is therefore the acceptance scenario.
