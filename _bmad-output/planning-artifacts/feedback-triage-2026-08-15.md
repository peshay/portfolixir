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
