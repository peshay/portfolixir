# Sprint 28, amended — the period that stays, the privacy mode's stack, the chart's basis and its bar

**Status: ADOPTED by the merge of this planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08).
This document amends
[`sprint-plan-2026-11-08-sprint28.md`](sprint-plan-2026-11-08-sprint28.md),
which stays adopted and stays the authority for everything this document
does not move. It adds two stories to Lane S and widens S2 by three polish lines, all
reported by you on 2026-11-08 after the plan's merge, and it sets one
design rule for every page with its gate in Sprint 29.

## What you need to do

1. **Merge, to adopt.** One point changes what you signed yesterday:
   **#1433 retires Sprint 27's D-4 rule that the privacy mode draws a
   100 % stack** (FR-53), at your request. Board 06 shows today and the
   new picture.
2. **Look at D-A1's second half**: besides riding the address, the period
   is remembered per browser, so a return from another page reopens it.
   "Zeitraum nur in der Adresse" drops that half.
3. **Look at board 07 ④** for the new rule "labelled controls start on one
   edge" (D-A5): A, a label column, is recommended; B puts every label
   above its control. Silence adopts A, with B as the floor where A does
   not fit.

**Not asked:** everything else.

**Verification basis:** read against the code on `8f6ee67` (`main` after
the Sprint 28 planning PR #1431):

- `PortfolioLive.param_period/1` reads `?period=` on arrival and falls back
  to `1y`; the comment cites #1122, "read on arrival and stored nowhere".
  `select_period`, `select_year` and the custom range set the assign
  only (`apply_period/2`), no patch.
- `handle_params/3` builds `current_path` from the carried view and the
  stacked chart's choices (`stack_path/2`); the period is not among them.
  The privacy and language switches and the view switcher's
  `view_href/2` link from `current_path`; the Wealth tabs are plain links
  (`wealth_tab_path/1`). Each remounts at 1 year. Hence #1432.
- `portfolio_live.ex` ~2095 writes the benchmark sentence with `%%`; no
  other gettext string in `lib/` does. The stack's bar (`.stack-bar`,
  `.stack-bar__group`) is a wrapping flex row of label-control pairs;
  measured at 390 px on board 07's frame, the controls start at 66, 118 and
  84 px.
- `StackedChart.geometry/2` scales each day's bands to their positive sum
  (`shares/1`) when the privacy mode is on, `range/2` fixes the axis at
  0 to 1, and `shown_shares/2` recomputes the legend's share on that basis
  (M3). Hence #1433.

## Decisions

### D-A1: the period rides the address and is remembered per browser (recommended)

**#1432, S2.** Picking a period patches the URL: `period=` for a token,
`year=` for a calendar year, `from=` and `to=` for a custom range.
`current_path` and every link the page builds from it carry it, and so do
the Wealth tabs. An arrival validates it against the analysis' range; an
invalid one falls back to 1 year with one line saying so (the existing
`range_error`). The last pick is also remembered **per browser**, as
Wealth's column pick is, so a return through the sidebar reopens it; it is
never stored on the server. *Why both:* the address alone fixes the
switches, a reload and a link handed over, but not "I come back to Wealth
and it is 1 year again", which is what you described. *What it reverses:*
#1122 decided that a link may name a token period and that a year or a
range is "a choice made on the page, never one a link makes"; the reason
for the second half is not recorded, and a validated range on arrival
answers the only risk it could have had (a range outside the data).
**To flip:** "Zeitraum nur in der Adresse".

No rendered difference: the same buttons and the same chart, kept across
the switches. So no board (the sprint workflow's exception, "identical
picture").

### D-A2: the stacked chart keeps its shape in the privacy mode (signed by this merge)

**#1433, your request of 2026-11-08, board 06.** The bands keep their
absolute shape. The axis reads in **percent of the total's value on the
window's first day** (100 %), because that is Sprint 26's rule for every
euro axis in the mode and what the mode's „Wert (%)“ line already does,
and an axis without labels would leave a band's growth unreadable. The
legend keeps share and change and drops the value column, as today; its
share is the API's net share again, so M3's privacy share retires. Tooltips
name no amount. The same at every level, with FR-56's filter, and for a
band that changes sign (#1426's drawing). I22's backstop and leak walk run
the new states. **To flip:** "Achse leer" draws no axis labels at all.

*What the mode still guards:* no amount, axis tick or tooltip reaches the
page. The shape reveals ratios over time (a deposit as a step of some
percent), which the mode already shows in every percentage it keeps.

### D-A4: the stacked chart's basis behind its ⓘ, and „%%“ (recommended)

**Two new lines on #1366, fixed by S2**, which already rewrites this
screen. The stacked chart's basis is five open sentences under the chart,
against I1 (#1351, which you adopted on 2026-11-01: method sentences
behind the section ⓘ, the short basis visible). Board 07 ①–③: one line
stays (what the chart shows, the window, when it was computed) and an ⓘ
at its end holds the method, the same sentences shorter. And the benchmark
sentence reads „Ansicht %% (TTWROR)“: the gettext string writes `%%`,
which Elixir's gettext prints as is; the only such string in `lib/`.

*Why it happened:* I1's rule is text in `DESIGN.md` and `EXPERIENCE.md`
with no backstop, and Sprint 27's S3 and its design critic reviewed the
chart against its own board, which drew no basis. #1435 gives the rule its
gate (D-A5). **To flip:** "Basis offen" keeps the sentences visible.

### D-A5: labelled controls start on one edge — a rule for every page (recommended)

**The third line on #1366, and a rule with a gate.** At 390 px the stacked
chart's bar puts each control right after its own label, so they sit
offset (66, 118, 84 px). The cause is general: every bar built as a
wrapping row of `label + control` pairs does this at some width. So
`DESIGN.md` gains, with this merge, the rule **"labelled controls start on
one edge"** (board 07 ④): one line while it fits; when it wraps, a label
column as wide as the longest label and every control from one edge (A);
where that does not fit, every label above its control (B, the floor);
switched by a container query on the bar. **S2 builds the stacked chart's
bar as the rule's first user.** Migrating the other bars and the two gates
(a browser walk at 390 and 1200 px for the shared edge, and the same walk
for I1's open prose, each exception registered with its reason) is
**#1435, Sprint 29**, because the sprint stands at 80 to 85 commits and
the inventory of bars needs its own before/after board. **To flip:** "Leiste
B" makes B the only shape; "Regel-Gate in 28" moves #1435 here, and then
FR-57 leaves.

### D-A3: where the stories go (recommended)

Lane S gains **S5 (#1432)** and **S6 (#1433)**, built **after S2 and
before S3**, so the cut line of D-10 (S3 and S4, FR-57) still protects
them: if the PR stands above 70 commits when Lane S reaches S3, FR-57
moves to Sprint 29 and S5 and S6 are already in.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| S5 | #1432, D-A1 | the period in the address and per browser: a LiveView test per kind (token, year, range) that picks it, then follows the privacy switch, the language switch, a view chip and a tab, and reloads, each seen failing first at 1 year; an invalid range on arrival falls back with the line; the browser memory as a hook with the column pick's storage rules (absent storage leaves 1 year) | — | 2 |
| S6 | #1433, D-A2 | the privacy mode's stack: `geometry/2` without `shares/1`, the axis indexed to the first day's total, `shown_shares/2` retired, the tooltips; tests that no tick, legend cell or tooltip carries an amount at each level and with a filter, and that the picture's band heights are the value mode's scaled by one factor; the backstop's and leak walk's states; `DESIGN.md`'s stacked-chart anatomy updated | 06 | 2 |

**S2 grows** by the three lines of D-A4 and D-A5 (the basis line and its
ⓘ, the `%%`, the bar as the rule's first user, its 390 px check as a
browser test), about one commit.

**Estimate:** about 5 build commits and, at the closing acts' rate, 2 to 3
fixes; the sprint's total moves from about 75 to 80 to **about 80 to 85**,
still under 90 with the cut line in place. The money lens and the design
critic of Lane S cover S6; the UAT persona adds: pick a custom range,
switch the privacy mode and the language, change the view and return
through the sidebar; and compare the stack with the mode on and off.

## Registry bookkeeping

- Filed for this amendment, under #418: **#1432** and **#1433**; under
  #420: **#1435** (Sprint 29).
- Three lines added to #1366 (Polish: Wealth), fixed by S2.
- `DESIGN.md` gains the amendment "Labelled controls start on one edge".
- `epics.md`'s FR-53 gains one clause naming the change and #1433.
- The sprint PR names `Closes #1432` and `Closes #1433` beside the plan's
  list.

## Checklist addition (the implementation session ticks it on the PR)

- [ ] Lane S: S2 also fixes #1366's three new lines (the basis and its
      ⓘ, `%%`, the bar on one edge)
- [ ] Lane S: S5 the period that stays (#1432), S6 the privacy mode's
      stack (#1433), both before S3
