# UX Design Pass — 2026-10-09, Sprint 21's user-visible items

Scope: **every** rendered change Sprint 21 proposes, held against the living
design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html).
`DESIGN.md` and `EXPERIENCE.md` are the authority, and this document proposes
against them. It runs **on the planning PR, before the batch**, as the
standing rule of 2026-09-20 requires (`AGENTS.md` → "A UI change is mocked on
a board before it is built").

**Why nine boards.** Sprint 21 carries the UI batch Sprint 20's D-13 deferred,
the repairs Sprint 20's build and closing acts filed since, and the screens
the money lane α changes:

- the UI batch γ draws one board per surface: the Overview (01), the
  securities list and a security's page (02), the history (03), Wealth,
  Income and Cash flow (04), Accounts and depots (05), Classifications (06),
  the Imports page (07), and the shared components and copy (08);
- α's screens are on board 03 (the drawer, #1052, #1206, #1209, #1213), board
  07 (the correction section and the row errors, #1188, #1193, #1194, #1195,
  #1197, #1205) and board 09 (an unavailable trade, a cross-currency row's
  currencies and a bond's coupon, #1198, #1213, #928).

β renders nothing, and #1200 (β8) brings `DESIGN.md` to the build, whose
picture does not change. Both have no board.

**The mockups** are in `design-language/mockups/ux-design-2026-10-09/`:

- **One board per surface**, with every variant or its before and after. Each
  board links the real `priv/static/app.css` and uses the live pages' markup
  and German labels.
- **Rendering.** Playwright renders each board to PNG (`render.mjs`, unchanged
  from the 2026-10-07 pass), reduced to a 256-colour palette.
- **Real widths.** Every frame is a `srcdoc` iframe, so a 390 px frame is a
  real 390 px viewport and `app.css`'s breakpoints fire as on a phone. Boards
  whose items live between 561 and 1199 px add 600, 768 or 1024 px renders.
- **Who drew them.** Five authors each drew one or two boards against
  `DESIGN.md`, `EXPERIENCE.md`, the triage of every issue against the code on
  `6f9d7d1`, and the four amendments this PR signs. Each author checked the
  renders by eye at every width. Every size quoted below was measured inside
  its frame unless it says otherwise.

**The data is invented:**

- names in the demo seed's style ("Arbolia Inc.", "Wrenfield Gardens AG",
  "Larkspur Rail AG");
- identifiers that pass the app's checks but name nothing (the bond
  fixture's style, "XSLARKSPUR33");
- generic account names ("Test-Cash", "Tagesgeld", "Depot Muster");
- made-up figures and 2026 dates.

**No real instrument, position, balance, account, provider or rate
appears.**

**How a pick is made.** The pick letter is **N**: it skips M, which names the
maintenance lane.

- **The recommendation is the default.** A comment naming another variant
  changes it, and silence adopts it — **except N1**, which reverses the
  owner's ruling of 2026-08-05 and so was the owner's to make. **The owner
  picked B on 2026-10-09** (the plan's D-3).
- **A before/after board has nothing to pick:** the spec already fixes the
  answer, and the board shows the reader what the words describe.
- **The story that builds a pick writes its anatomy into `DESIGN.md`.**

| Pick | Item | Board | Plan | Kind | Recommended |
|---|---|---|---|---|---|
| **N1** | The Overview total counts up from 0,00 (#1169) — **owner pick** | `01-overview` | γ1 | variants | **B**, the owner's pick of 2026-10-09: the computed total appears at once, and a count runs only between two real figures |
| **N2** | The KPI strip's dates fill their cells between 561 and ~665 px (#1114) | `01-overview` | γ1 | variants | **A**: the two-by-two switch moves from 560 to 680 px |
| **N3** | A wrongly valued holding and the total above it — the card half (#1121) | `01-overview` | γ1 | variants | **A**: the data-quality line's two findings say what they do to the total; the card stays silent |
| **N4** | "Details in Vermögen →" lands on another view and period (#1122) | `01-overview` | γ1 | options 1–3, **3 adopted** (Sprint 20 D-4) | **3**: the link carries `?period=ytd`, read on arrival and not stored; the note names the active view where it differs |
| — | The closed-trades card's basis line names both limits of p. a. (#1171); no doubled full stop after a name that ends in one, card and Trades facet (#1208) | `01-overview` | γ1 | before/after | after |
| **N6** | A boolean filter chip reads "Stillgelegt = false" (#1104) | `02-securities` | γ2 | variants | **A**: "Stillgelegt: nein", one rule for every boolean field; the builder's options read "ja" / "nein" |
| **N3.2** | `?dq=two_scales` lists the bonds with no direction and no remedy (#1121, the list half) | `02-securities` | γ2 | variants | **A**: a problem note per direction above the list, W2's entries, each bond linking to its remedy's tab |
| **N7** | The detail page is silent about the reverse two scales and about an implausible quote (#1112, widened by #1101) | `02-securities` | γ2 | variants | **A**: both as problem notes in the Overview's W1 slot, linking to Kurse (and Transaktionen) |
| — | Phone rows touch the viewport edges (#1139); an open column picker survives a resize below 560 px (#1151); the chart tooltip and markers in German (#1163); the Overview tab's and the list's percentages (#1201) | `02-securities` | γ2 | before/after | after |
| **N10** | An inflow and an outflow differ only by a minus (#1147) | `03-history-drawer` | γ3 | variants | **A**: an explicit „+“ on inflows, no colour; a zero reads „0,00“ |
| **N11** | The Preis cell names no currency (#1148) | `03-history-drawer` | γ3 | variants | **A**: always the price's own currency as the value suffix |
| **N12** | The drawer books and corrects the one-amount cash kinds (#1052, #1206) | `03-history-drawer` | α6 | variants | **A**: one drawer, the kind select first; edit opens the same form prefilled, kind and cash account frozen |
| — | The Betrag is the cash the balance moves; a zero is unsigned (#1209) | `03-history-drawer` | α11 | before/after | after |
| — | The drawer's amount label names the account's currency (#1213, drawer half) | `03-history-drawer` | α11 | before/after | after |
| **N5** | Wealth's optional value columns print "2.569,676EUR" (#1125) | `04-wealth-income` | γ4 | variants | **A**: money columns through `Format.money`, price columns by the stored-figure rule R10c, a space before the suffix (amends DESIGN.md's "money columns keep the projection's unrounded digits" in favour of ADR-0016 §4) |
| — | The contribution table's phone row names a position's costs (#1123); a figure that reads zero has no sign and no gain/loss colour (#1149); the Costs matrix shows each month's total (#1210); "Wechselkurs", never "Kurs", in the backfill control and the Flows and Costs notes (#1150) | `04-wealth-income` | γ4 | before/after | after |
| **N15** | At 768 and 1024 px the accounts table is cut, not scrolled, and its kebab column is lost (#1145) | `05-accounts` | γ5 | variants | **A**: the shipped card layout takes over wherever the table does not fit, by a container query on the table's own wrapper (bound 840 px of content); the amount and "Saldo setzen" never wrap |
| **N16** | At 390 px the Buckets ⓘ explains a word the card never shows (#1162) | `05-accounts` | γ5 | variants | **A**: the card opens the bucket cell with "Buckets ⓘ", as rule ⑦ opens the role with "Liquiditätsrolle ⓘ" |
| — | A bucket chip's × on the desktop is 14.7 × 34 px, so a chip holding one is 40 px tall (#1161); Accounts' empty result slot takes 8 px and a 16 px grid gap at rest (#1160) | `05-accounts` | γ5; #1160 with γ8 | before/after | after |
| **N17** | Between 561 and 720 px the tree's name column collapses and "Kategorie" runs into "Positionen" (#1165) | `06-classifications` | γ6 | variants | **A**: the tree's existing two-line phone rows apply up to 720 px |
| **N18** | A category cannot be moved under another parent on screen (#1211) | `06-classifications` | γ6 | variants | **A**: "Übergeordnet" in the category's edit form, the new-category form's select without the category itself and its descendants; the existing cycle and level-32 refusals |
| — | At 390 px an open category's security rows run past the screen (#1158); the SOLL editor writes into an archived plan version (#1187) | `06-classifications` | γ6 | before/after | after |
| **N21** | The correction section's three new line states — a stored booking whose row A5 now refuses, a booking changed by hand since its import, a row found by its figures (#1193, #1194, #1205) | `07-imports` | α7 | variants | **A**: one table in file order; each state a line under its booking, „bleibt“ in its „Korrigiert“ cell; the confirm, the total and the dialog count only the lines they change; the price stays in the shipped detail lines (the briefed „Kurs“ column is drawn, measured and not recommended) |
| **N20** | A mapping row's „N Buchungen neu“ after the operator's choice (#1180) | `07-imports` | γ7 | variants | **A**: recount through the existing async dry run; the count dims and carries the computing cue meanwhile |
| — | #1188 and the negative FEE unit (row errors); #1195 (withheld only until the dry run answers); #1130 (leftover-configuration note); #1179 („Eintrag N“); #1207 (lead note, done page); #1197 (the absorbing set balance); #1178, #962, #1181 (done page; #1181 also Risk and Tax) | `07-imports` | α5, α7, α8; γ7 | before/after | after |
| **N13** | Dismissing an inline result drops the focus to the page body (#1166) | `08-shared-copy` | γ8 | variants (+ the ring, before/after) | **A**: the control that produced the result, else the section's heading |
| **N14** | A twin security named in a note's sentence (#1155) | `08-shared-copy` | γ8 | variants (+ the tables, before/after) | **A**: the `.twin-id` tag after the name, inside the sentence |
| — | The dismiss draws the family ring (#1166); twin tags in the history, the Trades facet, Wealth's allocation, the Overview (#1155); a dialog's own footer padded (#1138); an empty result slot takes no room (#1160); progress labels in the house form (#1157); the former-name and ISIN-alias refusals in German (#1191) | `08-shared-copy` | γ8 | before/after | after |
| **N8** | A closed trade whose lot has no leg in the sale's currency (#1198) | `09-money-states` | α3 | variants | **A**: the security's Trades tab keeps the row with the reason dash and names its remedy; Income and the Overview card leave it out and name it in their existing exclusion note |
| **N9** | A cross-currency booking's money figures name no currency (#1213) | `09-money-states` | α11 | variants | **A**: a suffix on every money cell of a cross-currency row, only there; the Trades tab's result cell always names the trade's currency |
| — | The drawer's "Betrag (USD)" names the booking's currency (#1213); a bond's coupon in the contribution table and on Income (#928) | `09-money-states` | α11, α4 | before/after | after |

**N19 is not used:** #1187 needed no choice, so it is a before/after on board 06.

**What the merge adopts beyond the picks.**

- **The "found while drawing" items carry their verdicts.** Each board's part
  ends with them:
  - **Fixed in the story that touches the surface (the plan's D-13):** small,
    on that surface, with the answer in the spec.
  - **Filed at the merge, each under its area tracker,** after a title
    search (the plan's Lane Z):
    - "A refused row's 'book it by hand' remedy is shown although the
      booking already exists" — a hand booking made after an earlier drop
      (board 07), or a stored row whose re-export drifted and is found by
      its hash alone (ADR-0053's deferred ask); `needs-decision` under #416,
      recommended answer: match the remedy's bookings by their figures and
      say "already booked" instead;
    - "The rename probe could count a former name the import preview's
      'remember' wrote" (ADR-0050's deferred ask); `needs-decision` under
      #416, with its trigger;
    - "The app names Inter but ships no font file, so every width floor
      depends on the reader's system font" (board 01), under #420;
    - "Overview: when the total leaves nothing out, nothing says Wealth opens
      on another view" (board 01), under #418;
    - "Cash flow → Ein- & Auszahlungen: the Netto row never shows a month's
      net" (board 04), under #418;
    - "With the booking drawer open the history hides Preis and Betrag
      behind a sideways scroll" (board 03), under #416;
    - "Accounts: 'Saldo setzen' sits under the balance below about 1500 px,
      where #670 put it beside" (board 05), under #417;
    - "A duplicated plan version is named '… (copy)' in English" (board 06),
      `needs-decision` under #417, because the name is stored.
  - **Folded into an issue the sprint already builds:** the securities list's
    percent cells join #1201 (board 02); the Cash-flow matrices' zero joins
    #1149 (board 04); the booking sheet's foot joins N12's story (board 03).
  - **One owner per item drawn twice:** #1160's component rule is board 08's,
    and board 05's ④ shows Accounts' slot under it; the drawer's amount label
    (#1213) is board 03's, and board 09 repeats it beside the security's
    tabs.

---

## Board 01 — the Overview

**Board:** `design-language/mockups/ux-design-2026-10-09/01-overview.html`,
rendered as `01-overview--1200.png`, `--768.png`, `--600.png` and `--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup of
  `dashboard_live.ex` (`overview/1`, `closed_trades_card/1`,
  `wealth_card_excluded/1`, `dq_findings/1`), `portfolio_live.ex` (the KPI
  band, the view-switcher row, the period tokens), `view_switcher.ex` and
  `income_live.ex` (the Trades facet's exclusion note), with the German
  msgstrs. Each frame is a real viewport of the width it is labelled with:
  980 px desktop (1200 − 220 sidebar), 768, 681, 600, 561 and 390 px, so
  app.css's 560 and 720 px blocks fire as on a device.
- **CSS.** "Heute" frames render app.css as shipped; "Nachher" and variant
  frames add `<style id="proposal">`. Its rules are scoped to their own
  variant's frames by `data-n1` / `data-n2` on the frame's `<html>` — board
  scaffolding only; the story writes each rule bare.
- **Renders.** 1200 shows everything; 768 shows the whole Overview, Heute and
  Nachher (all adopted items together); 600 shows N2's frames and the
  Nachher page; 390 shows every item's phone frame.
- **Font.** Frames use Inter (installed on the drawing machine) except N2's,
  which use DejaVu Sans unless labelled Inter — see N2.

### ① N1 — #1169: the total counts up from 0,00 (variants; owner pick)

**Today.** The CountUp hook (`layout_view.ex:1371-1470`, the ninth inline
hook, owner decision of 2026-08-05) counts a money slot from **0** on its
first value (`var from = this.lastValue === null ? 0 : this.lastValue;`,
`:1413`) over 600 ms, ease-out cubic, digits muted and the 2 px accent bar
growing beneath them (the settling state, pick S1). Three slots use it: the
Overview's "Alles" total (`dashboard_live.ex:323-330`) and Wealth's "Gesamt
inkl. Cash" and "Wertpapiere" (`portfolio_live.ex:1039-1044`, `:1153-1158`).
The Overview gets one value per page load, so it counts from 0,00 on every
visit. The board's stills are the hook's own frames for 0 → 62.639,10: at
16 ms "4.812,30", at 300 ms "54.809,21". #1169's evidence: the Sprint 19
first-look test read "73.645,32" for 73.657,92.

**The ruling it reverses.** Owner, 2026-08-05
(`feedback-triage-2026-08-05.md`, "Decisions from the owner"): "a cosmetic
count-up animation to the final value is acceptable and wanted, provided it
is visually evident that the number is still counting and not final";
DESIGN.md → Motion records it and declines "dropping count-up on money".
**Silence keeps today's behaviour**, and #1169 closes as not planned.

**Variants** (stills at 390 px; a 980 px Heute frame 300 ms into the count):

- **A — no count on money figures.** The three money slots lose
  `phx-hook="CountUp"`; every figure lands whole, and a re-value swaps the
  digits in one frame. The hook then serves nothing, so the story removes it
  and DESIGN.md's Motion entry with it.
- **B — recommended by the planning session.** One line in the hook: `var
  from = this.lastValue === null ? target : this.lastValue;`. A page load
  paints the figure that exists; pending is unchanged (on the Overview the
  last known YTD return, dimmed, with its cue and date — the only memoised
  figure); a count runs only from one real figure to the next, so no frame
  lies outside two figures the ledger produced, and the bar still says "not
  final". It keeps what the ruling was for — "anything beats staring at
  three dots" is about the wait, which is pending's.
- **C — the digits hidden while counting.** One rule,
  `.count-up.is-settling [data-count-digits] { visibility: hidden }`. No
  wrong figure is readable, but the slot is blank under a running bar for
  600 ms on every load — the void the ruling disliked, after the wait.

**What B builds, against the code (found while drawing 1).** The plan's
D-3 says B counts "after a view or period switch". The Overview has neither
control; Wealth's view switch is a full page load (`view_switcher.ex:140`,
plain `href`), so the hook mounts afresh; the period moves neither counted
figure. The only place B still counts is a figure re-valued in place:
Wealth after the rate sync (`portfolio_live.ex:801-813`), drawn as the
second half of each film (62.639,10 → 63.104,85, 300 ms frame "63.046,63").
In practice B shows money as A does and keeps the hook for that one case.

**Unchanged in every variant:** `prefers-reduced-motion: reduce` already
paints the final value; `aria-busy` flips as today; the server-rendered
digits are the value of record.

**Strings:** none, in any variant.

**Measured:** nothing to measure beyond the stills; the hook pins the slot's
final footprint before the first frame, which the stills reproduce.

**What the story writes into DESIGN.md** (only if N1 is picked): Motion's
count-up bullet and Value slot → Settling, with the picked variant —
for B: "a first value is painted as it is; a count runs only from one
received figure to the next"; for A: the count-up and the ninth hook are
retired from money; for C: the digits are hidden while settling.

### ② N2 — #1114: the KPI strip between 561 and ~665 px (variants)

**Today.** Four equal columns down to 561 px, two by two below
(`app.css:8439-8460`, `:8551-8563`); a value is 20 px/700, tabular,
`nowrap` (`:8482-8490`), so the widest value — a date, "02.10.2026" — is the
floor.

**The measurement depends on the reader's font (found while drawing 2).**
`--font-sans` names Inter first, and the app ships no font file (no
`@font-face` in app.css, nothing in `priv/static`). A Playwright sweep of
real viewports, 540–780 px in 1 px steps, this strip's markup and data:

| Variant · font | ink in the padding | ink past the cell's edge | 561 px | 600 px | 640 px | value 561–680 |
|---|---|---|---|---|---|---|
| Heute · DejaVu Sans | 561–664 | **561–597** | 9.8 past | 16.0 in (at the edge) | 6.0 in | 20 px |
| Heute · Inter | 561–612 | none | 13.4 in | 3.7 in | clear | 20 px |
| **A** · DejaVu Sans | none | none | 2×2, 106.0 clear | 2×2, 125.5 clear | 2×2, 145.5 clear | 20 px |
| **A** · Inter | none | none | 2×2, 118.3 clear | 2×2, 137.8 clear | 2×2, 157.8 clear | 20 px |
| B · DejaVu Sans | 561–562 | none | 0.9 in | 2.6 clear | 2.7 clear | 16 → 20 px |
| B · Inter | none | none | 9.0 clear | 13.1 clear | 14.2 clear | 16 → 20 px |
| C · DejaVu Sans | 561–613 | **561–573** | 3.8 past | 4.0 in | 6.0 clear | 20 px |
| C · Inter | 561–564 | none | 1.4 in | 8.3 clear | 18.3 clear | 20 px |

With DejaVu Sans (the common Linux fallback) the date crosses its cell's
edge up to 597 px — clipped in the fourth cell by the frame's `overflow:
hidden`, laid over the divider in the third — and sits in the padding up to
664 px, the issue's "about 660". With Inter it never crosses. #1114's "26 px
at 561, 16 at 600, 6 at 640" were taken in a padded board frame, not a real
viewport.

**Variants:**

- **A — recommended: the two-by-two switch moves to 680 px.** The existing
  560 px block's three rules move to `@media (max-width: 680px)` (an edit,
  not an addition). 680 is measured: with DejaVu Sans the four columns hold
  their dates inside the content box from 665 px; 680 adds 15 px for a
  wider fallback.
- **B — the value shrinks.** `font-size: clamp(16px, calc(4vw - 7px),
  20px)` between 561 and 720 px: clears the edge in both fonts, but the four
  key figures read 16–19.6 px there, smaller than the phone's 20 px.
- **C — the cells' padding drops to 10 px under 720 px.** 12 px more per
  cell; with DejaVu Sans the date still crosses the edge up to 573 px. Not
  enough on its own.

**Why A.** The only variant that clears the padding with both fonts at every
width, and it changes no anatomy: the two-by-two strip is the phone's
already (DESIGN.md → Overview KPI strip), and the value keeps the spec's
20 px. B adds a third, window-dependent size for one anatomy; C does not
fix it. A's cost is height between 561 and 680 px (below).

**Measured** (in the board's frames, DejaVu Sans unless noted):

| Frame | columns | cell | widest date | strip height |
|---|---|---|---|---|
| Heute 561 | 4 | 132 px | 9.8 px past the edge | 127 px |
| Heute 600 | 4 | 142 px | 16.0 px into the 16 px padding | 127 px |
| Heute 600, Inter | 4 | 142 px | 3.7 px into the padding | 127 px |
| A 600 | 2 | 283 px | 125.5 px clear | 186 px (+59) |
| A 681 | 4 | 162 px | 4.0 px clear | 110 px |
| B 600 | 4 | 142 px (value 17.0 px) | 2.6 px clear | 124 px |
| C 600 | 4 | 142 px | 4.0 px into the 10 px padding | 127 px |
| A 390 (= Heute) | 2 | 178 px | 20.5 px clear | 203 px |

The whole page under the recommendations: 768 px — strip four columns,
110 px, page 1107 → 1143 px (N3's and N4's sentences), no element past the
viewport; 600 px — strip two by two, 186 px, page 1302 px, none past the
viewport.

**CSS (A):** `@media (max-width: 680px) { .kpi-strip__cells {
grid-template-columns: repeat(2, minmax(0, 1fr)); }
.kpi-strip__cell:nth-child(3) { border-left: 0; }
.kpi-strip__cell:nth-child(n + 3) { border-top: 1px solid
var(--color-border); } }` — replacing the 560 px block.

**Strings:** none.

**What the story writes into DESIGN.md** (Overview KPI strip, Frame):
"two by two under 680 px" instead of 560, with the reason — the dates' floor
measured with a fallback font, since the app ships none.

### ③ N3 — #1121, the card half: a wrongly valued holding and the total (variants)

**Today.** Since #1068 and #1101 the data-quality line (`dq_findings/1`,
`dashboard_live.ex:1066-1162`) counts "eine Anleihe auf zwei Skalen
bepreist" and "2 gehaltene Wertpapiere, deren Kurse nicht zu ihren
Buchungen passen" at problem severity, six blocks under the total those
holdings distort. The card's note (J1 A) names only rows *out* of the
total, and DESIGN.md:861 (Sprint 20 D-7) says "The Overview's value card
says nothing about it … this line is the alarm" — EXPERIENCE.md's #703
split (UX-DR2, amended 2026-10-06): for a condition *in* a total, the
Overview counts, Wealth names.

**Variants:**

- **A — recommended: the line says what each finding does to the total.**
  Each finding keeps its link (the count and its noun, to the pre-filtered
  list) and gains a clause after it, in the note's body ink: "— gehalten
  zählt sie in der Summe oben hundertfach zu hoch oder zu niedrig", "— ihr
  Wert in der Summe oben oder ihr Einstand ist daher falsch". The card, its
  note and both severities are untouched.
- **B — the card's note gains an in-the-total clause.** "In der Summe, aber
  falsch bewertet: eine Anleihe auf zwei Skalen — Kestrel Anleihe 2030 2,75%
  (hundertfach zu hoch) · 2 Wertpapiere, deren Kurse nicht zu ihren
  Buchungen passen — Arbolia Inc., Wrenfield Gardens AG." The note mixes
  rows out of the total with rows in it and takes problem severity.
- **C — a second note under the card**, problem severity, with the same
  names. The alarm is then said twice on one page.

**Why A.** It answers #1121 where the spec puts the alarm and keeps both
recorded rules (#703's split, D-7's sentence), so nothing is amended. It
needs no new read — the clauses need only the line's counts; B and C need
the per-bond names and directions the Overview does not read today (Wealth's
`two_scales` and `implausible_quotes`). The words are Wealth's own
("zählt hundertfach zu hoch in den Summen", "ihr Wert oder ihr Einstand ist
daher falsch"). The two-scales clause is conditional ("gehalten") because
that count is catalog-wide on purpose (sold-out, retired and benchmark
bonds kept) and only a held bond is in the total.

**Strings (A, new):**

| | English (msgid) | German (msgstr) |
|---|---|---|
| Two scales, effect | ngettext: "— if held, it counts a hundredfold too high or too low in the total above" / "— each one held counts a hundredfold too high or too low in the total above" | "— gehalten zählt sie in der Summe oben hundertfach zu hoch oder zu niedrig" / "— gehalten zählt jede in der Summe oben hundertfach zu hoch oder zu niedrig" |
| Implausible quote, effect | ngettext: "— so its value in the total above, or its cost, is wrong" / "— so their value in the total above, or their cost, is wrong" | "— sein Wert in der Summe oben oder sein Einstand ist daher falsch" / "— ihr Wert in der Summe oben oder ihr Einstand ist daher falsch" |

The clause sits after the `<a>`, outside it, so the link still names the
list it opens.

**Measured:**

| | 980 px | 390 px |
|---|---|---|
| Data-quality note, Heute / A | 54 → 72 px | 108 → 180 px |
| Card section, Heute = A / B / C | 238 / 274 / 300 px | 300 / 408 / 452 px |

**What the story writes into DESIGN.md** (Data quality → the two-scales and
implausible-quote paragraphs): the effect clause of each finding, both
strings, and that the card stays silent — D-7's sentence gains "the line
says what the finding does to the total above".

### ④ N4 — #1122: "Details in Vermögen →" (options; option 3 adopted)

**Today.** The card reads the default view ("Alles") and says "seit
Jahresbeginn"; its note's link (`dashboard_live.ex:747`) and the card itself
(`:321`) open `/portfolio`, which shows the session's view (`ViewScope`) at
1J (`portfolio_live.ex:160`). In the frames, "Nur Neuzugang" was picked on
Wealth earlier: the link lands on 240,00 EUR with no notes, at 1J.

**The options** (#1122 and its comments; all three carry the card's period):

- **1 — link with the card's view, and store it** (`?view=total&period=ytd`).
  Lands on the named figures, but `?view=` is a stored choice (session and
  year-long cookie): one click on the Overview replaces "Nur Neuzugang" on
  every page. #1081 rejected it for that reason.
- **2 — the card says its view** ("Ansicht Alles", the existing "View
  %{name}"), always. The reader can compare it with Wealth's "Eingegrenzt
  auf Ansicht: Nur Neuzugang" only after arriving, and only by noticing.
- **3 — adopted (Sprint 20 D-4): the period travels; the note names the
  active view where it differs.** The note's link and the card's `href`
  become `/portfolio?period=ytd`; Wealth reads `period` in `mount/3` (a
  valid token, else 1J) and stores nothing. When the session's view is not
  the card's, one sentence before the link: "Vermögen ist gerade auf die
  Ansicht „Nur Neuzugang“ eingegrenzt; diese Summe zählt „Alles“." With
  the views equal, the note is as today. No choice is made for the operator
  (#1081's rule; EXPERIENCE.md Flow 3).

**Strings (option 3, new):**

| | English (msgid) | German (msgstr) |
|---|---|---|
| View sentence | "Wealth is currently scoped to the view “%{active}”; this total counts “%{card}”." | "Vermögen ist gerade auf die Ansicht „%{active}“ eingegrenzt; diese Summe zählt „%{card}“." |

`%{card}` is the card's own label (`@wealth_card.name || gettext("Everything")`);
both names are stored text, set in `<bdi>` by `StoredText` (H8.8).

**Measured:** the note 54 → 72 px at 980 px (the sentence takes two line
boxes) and 126 → 180 px at 390 px; options 1 and 2 leave it at 54 / 126 px.

**What the story writes into DESIGN.md** (The Overview's value card → "The
link, and no control"): the link and the card carry `?period=ytd`, read on
arrival and never stored; the view sentence and when it renders. The
paragraph's "consequence" sentence (Wealth may name other rows) is replaced
by the sentence that now says so on the page.

### ⑤ #1171 — the closed-trades card's basis line (before/after)

**Today.** "Die 3 zuletzt abgeschlossenen · Ergebnis in EUR · FIFO über alle
Depots, unabhängig von der Ansicht · p. a. erst ab 365 Tagen Haltedauer"
(`dashboard_live.ex:665-672`). The Trades facet and the security's Trades
tab name both limits since #1089 (`income_live.ex:601`,
`securities_live.ex:2347`), so "Saltmarsh Logistics SE", held 604 days,
"-100,0% gesamt", reads as the card breaking its own rule.

**Rule applied:** DESIGN.md → Amendment 2026-10-01 → The list's basis line
(amended 2026-10-07, issue 1089): "… · p. a. erst ab 365 Tagen Haltedauer
und nur, wo ein Zinssatz die Zahlungen löst" — the facet's clause, word for
word. DESIGN.md → The Overview card "Abgeschlossene Trades" → Basis line
(`:3479-3481`) is stale and is updated.

**Strings (changed msgid and msgstr, ngettext):**

| English (msgid / msgid_plural) | German |
|---|---|
| "The most recently closed · result in %{currency} · FIFO across every depot, whatever the view · p. a. only from 365 days of holding and only where a rate solves the flows" / "The %{count} most recently closed · …" (same tail) | "Der zuletzt abgeschlossene · Ergebnis in %{currency} · FIFO über alle Depots, unabhängig von der Ansicht · p. a. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz die Zahlungen löst" / "Die %{count} zuletzt abgeschlossenen · …" (same tail) |

**Measured:** the basis line 17 → 34 px at 980 px (one line → two); 50 px
(three lines) at 390 px, before and after.

**What the story writes into DESIGN.md:** the card's basis line in its new
wording, as the facet's.

### ⑥ #1208 — no doubled full stop after a name that ends in one (before/after)

**Today.** Two sentences end their name list with the sentence's own full
stop: the card's exclusion note, "… fehlt bei den Trades: Larkspur Rail
Corp.. Das Nachladen …" (`dashboard_live.ex:656-663`), and the Trades
facet's, "… ausgeschlossen: Larkspur Rail Corp.." (`income_live.ex:326-331`).
#1081's M6 fixed the same doubling for the total's note only
(`excluded_sentence/1`, `dashboard_live.ex:752-760`, two msgids).

**Rule applied:** DESIGN.md → Stored names in results and headings (H8.8,
"One body sentence joined, for its punctuation"): no name's last character
meets a full stop of the app's. M6's guard becomes one shared helper (a
list whose last name ends in "." takes the msgid without the stop), and the
M6 site moves onto it, with a test per site.

**Strings (new msgids, the stop-less twins):**

| English (msgid / plural) | German |
|---|---|
| "%{count} sale with no stored rate on its close date is left out of the trades: %{securities} The rate backfill is under “All trades”." / "%{count} sales … their close dates are left out of the trades: %{securities} The rate backfill …" | "%{count} Verkauf ohne gespeicherten Wechselkurs an seinem Schlussdatum fehlt bei den Trades: %{securities} Das Nachladen der Wechselkurse steht unter „Alle Trades“." / "%{count} Verkäufe … fehlen bei den Trades: %{securities} Das Nachladen …" |
| "%{count} sale could not be converted — no stored rate at its close date — and is excluded from every total: %{securities}" / plural likewise | "%{count} Verkauf konnte nicht konvertiert werden — kein gespeicherter Wechselkurs an seinem Schlussdatum — und ist aus jeder Summe ausgeschlossen: %{securities}" / plural likewise |

The Nachher facet frame carries #1150's control wording (board 04), which
ships in the same sprint.

**Measured:** no size changes (one character fewer).

**What the story writes into DESIGN.md** (H8.8): the two sentences join the
list the rule covers, and the guard is named as the one helper.

### Found while drawing (board 01)

1. **B's count "after a view or period switch" does not exist in the
   code.** See N1: a view switch is a full page load and the period moves no
   counted figure; under B only Wealth's in-place re-value after the rate
   sync counts. **Fixed in the story that touches the surface (D-14)** if
   N1 B is picked: the story's DESIGN.md sentence says "a later value
   received in place"; the plan's D-3 and its owner question should say the
   same before the merge.
2. **#1114's figures do not reproduce in a real viewport, and the strip's
   fit depends on a font the app does not ship.** Measured above. N2 A's
   680 px is set for the wide fallback, so **fixed in the story**. The
   font itself is off-surface and a choice (bundle Inter, or accept system
   fallbacks and measure every floor against one): **filed at the merge** —
   "The app names Inter but ships no font file, so every width floor depends
   on the reader's system font".
3. **The card's own link opens Wealth too.** Option 3 applies the period to
   the card's `href` as well as the note's link: **fixed in the story
   (D-14)**. **With nothing left out of the total there is no note**, so a
   differing active view is named nowhere: **filed at the merge** —
   "Overview: when the total leaves nothing out, nothing says Wealth opens
   on another view" (needs a choice: a sentence under the card without a
   note, or accept).
4. **The view switcher's accessible name reads "Aktive Filter"** in German
   (msgid "Active view", `view_switcher.ex:42`, `:46`; po:2554): a view is
   not a filter, and N4's sentence calls it "Ansicht". One msgstr,
   "Aktive Ansicht": **fixed in the story that touches the surface (N4,
   D-14)**; no rendered difference.
5. **The Overview's own sign helpers decide on the raw value**
   (`dashboard_live.ex:1035-1047`, `signed_percent/1`, `sign_class/1`): a
   YTD return of +0,0004 reads "+0,0%" in the gain colour on the card.
   **Fixed in #1149's sweep (board 04, D-14).**
6. **"LETZTE BUCHUNG" wraps to two lines** in a four-column cell between
   561 and ~640 px with DejaVu Sans (and B and C keep it so), so the labels
   misalign across the strip; under A the strip is two by two there and every
   label is one line. No separate fix: **resolved by N2 A**.


---

## Board 02 — the securities list and a security's page

**Board:** `design-language/mockups/ux-design-2026-10-09/02-securities.html`,
rendered as `02-securities--1200.png` and `02-securities--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup of
  `securities_live.ex` (the list's `render/1`, `overview_tab_panel/1`,
  `quotes_tab_panel/1`, the Chart tab), `bond_strip.ex` (the W1 slot),
  `filter_popover.ex`, `column_picker.ex`, `security_chart.ex` and the
  `ChartCrosshair` hook (`layout_view.ex`), with the German msgstrs. A desktop
  frame is 980 px (1200 − 220 sidebar); a phone frame is a real 390 px
  viewport, where `app.css`'s 560 px and 720 px blocks fire. The chart frames
  apply the hook's `--chart-upx` and `data-axis-inside` after load, as the
  hook does.
- **CSS.** "Heute" frames render `app.css` as shipped; "Nachher" and variant
  frames add `<style id="proposal">`: rule ② (N3.2 A's slot), ④ (#1139) and ⑤
  (#1151). N6, N7, #1163 and #1201 need no CSS.
- **Data.** "Fennwick Labs AG", "Halvorsen Shipping AS", "Wrenfield Gardens AG"
  (unclassified); the bonds "Ostsee Hafen 2029 3,00%", "Kestrel Kommunal 2033
  1,75%" (no asset class) and "Brackwater Anleihe 2031 2,50%" (reverse);
  "Arbolia Inc." (USD, mapped to another listing), "Larkspur Rail AG",
  "Tamarisk Systems Inc."; "Depot Muster"; identifiers of the `DE000000000L`
  kind; 2026 dates. Nothing real.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **N6** | A boolean filter chip reads "Stillgelegt = false" (#1104) | variants | **A** |
| **N3.2** | `?dq=two_scales` shows no direction and no remedy (#1121, list half) | variants | **A** |
| **N7** | The detail page says nothing about the reverse two scales or an implausible quote (#1112, #1101) | variants | **A** |
| — | #1139 phone rows' gutter; #1151 the column picker below 560 px; #1163 the chart tooltip and markers; #1201 the Overview's percentages | before/after | — |

### ① N6 — #1104: a boolean filter chip reads "Stillgelegt = false" (variants)

**Today.** The Overview's asset-class finding links to
`/securities?filter[]=asset_class:is_nil&filter[]=is_retired:is_false` (PR
#1102). The list shows the one-tap chip "Ohne Anlageklasse" active and the
builder's condition as a removable chip. `chip_label/1`
(`securities_live.ex:4478-4482`) joins the field's label, `operator_label/1`
and `format_value/2`:

- `operator_label(:is_false)` is the literal `"= false"` (`:4490-4491`), not
  gettext;
- `format_value(_, false)` is `""`.

The chip therefore reads "Stillgelegt = false" on the German page. The
builder that sets it names the operator "ist falsch"
(`filter_popover.ex:246-247`). The registry has two boolean fields,
Stillgelegt and Benchmark (`SecurityFields`).

**Variants:**

- **A — recommended: "Stillgelegt: nein".**
  - The chip reads the field, a colon and the value: "Stillgelegt: nein",
    "Stillgelegt: ja", "Benchmark: nein". It is one rule for every boolean
    field, present and future.
  - It is the family chips' rule (DESIGN.md → Filter chips, D2: "Family chips
    render their value in the label"), applied to a family with two values.
  - **The popover follows A.** For a boolean field the builder shows no value
    input (`@operator not in [:is_true, :is_false, :is_nil]`), so its operator
    select *is* the value. Under A its label reads "Wert" (the existing msgid
    "Value") and its two options "ja" / "nein", so what the operator picks is
    the word the chip shows.
  - The stored filter stays `is_retired:is_false`: URLs, the API and MCP are
    unchanged.
- **B — "Nicht stillgelegt" / "Stillgelegt".** Reads most naturally for this
  field, but it needs a hand-written negation per field and value ("Kein
  Benchmark"): four msgids today and two more with each boolean field. The
  popover's "ist wahr / ist falsch" stays a second vocabulary.
- **C — "Stillgelegt ist falsch".** Reuses the popover's msgstr, adds no
  string and makes the two agree. But it reads as a statement about the data
  ("the retired flag is wrong"), on a page whose other removable chips are
  data-quality findings ("Auf zwei Skalen bepreist", "Kurs passt nicht zu
  Buchungen"). It names the predicate, not the set the list shows.

**Why A:** one rule, two new words, the anatomy the chip row already uses,
and a builder that speaks the chip's words.

**Strings** (A):

| | English (msgid) | German |
|---|---|---|
| Chip label | `%{field}: %{value}` | `%{field}: %{value}` |
| Value, msgctxt "boolean filter" | yes | ja |
| Value, msgctxt "boolean filter" | no | nein |
| Popover label for a boolean field | Value (existing) | Wert |

The literal `"= true"` / `"= false"` go. The popover's msgids "is true" /
"is false" lose their last call site and leave the catalogue.

**Measured** (the removable chip; 44 px tall at both widths, the coarse
pointer floor):

| | 980 px | 390 px |
|---|---|---|
| Heute "Stillgelegt = false" | 134 × 44 | 134 × 44 |
| A "Stillgelegt: nein" | 123 × 44 | 123 × 44 |
| B "Nicht stillgelegt" | 124 × 44 | — |
| C "Stillgelegt ist falsch" | 146 × 44 | — |

**What the story writes into DESIGN.md** (Filter chips, D2): a builder
condition on a boolean field renders as "<field>: ja" / "<field>: nein", and
the builder offers the same two words for a boolean field.

### ② N3.2 — #1121, the list half: `?dq=two_scales` lists the bonds with no direction and no remedy (variants)

**Today.** The Overview's line counts the bonds priced on two scales,
catalog-wide and in both directions, at problem severity, and links to
`/securities?dq=two_scales` (#1068, D-15). The list opens on them under the
removable chip "Auf zwei Skalen bepreist" (`dq_label("two_scales")`,
`securities_live.ex:6543`) and says nothing else. Which way each bond is off,
and what to check, is said only on Wealth (W2 and its reverse note) and on a
forward bond's own Overview.

**Variants:**

- **A — recommended: a problem note per direction above the list.**
  - **The notes.** Wealth's two notes, as a block between the removable chips
    and the list, forward first, one note per direction present (UX-DR17: one
    finding per note, because consequence and remedy point opposite ways).
    They sit in one `role="status"` region
    (`data-role="securities-dq-notes"`), in the slot where `missing_logo`'s
    bulk action sits (`:672`).
  - **The entries** are W2's (`PortfolioLive.two_scales_entry/1`): the name
    linking to the tab where the fix is made (forward → Transaktionen, the
    booked quantity; reverse → Kurse, the stored quotes), the neutral "ohne
    Anlageklasse" badge where the bond shows none, and "(Kurs 97,25 · Preis
    je Stück 0,985)" as `Format.exact` writes them.
  - **A count of N opens a list of N** (#705): the notes name exactly the
    rows below.
  - **One clause differs from Wealth's sentence.** Wealth says "zählt
    hundertfach zu hoch *in den Summen*", because its notes follow the page's
    scope. This list is catalog-wide on purpose: sold-out, retired and
    benchmark bonds stay (D-15). The clause therefore reads "*wo immer sie
    bewertet wird*", which is true for a held bond's total, a sold bond's
    past values and a benchmark's comparison alike. This is J1.2's rule: a
    scope word where the scope differs.
  - **The gutter** is rule ②: `margin: 12px clamp(14px, 2.2vw, 24px) 0` and
    the `--space-2` gap, as `.workspace-panel > .alert-success` and Wealth's
    `[data-role="dq-notes"]`.
- **B — a direction badge per row, no remedy.** A `badge badge--danger`,
  "hundertfach zu hoch" / "hundertfach zu niedrig", after the name on the
  table row and in the phone row's identifier line. It is compact and stays
  with its row when the list is sorted or searched.
  - It says which way, not why and not what to check. The reader still
    leaves for Wealth or the bond's page to learn that a forward bond's
    *quantity* is wrong and a reverse bond's *quotes* are.
  - It is a second anatomy for the same finding.
  - A tinted badge in a table row is the "ad-hoc chip" the data note replaced
    (DESIGN.md → Data note).

**Why A:** the list is where the Overview's alarm lands. A answers there with
the words and remedies the reader would otherwise have to find on Wealth.

**Strings** (A; new, both `ngettext`; the entries reuse "quote %{close} ·
price per unit %{price}" and "no asset class"):

| | English (msgid / msgid_plural) | German |
|---|---|---|
| Forward | One bond is priced on two scales (quotes around 100, booked price per unit around 1) and counts a hundred times too high wherever it is valued; the return does not show it. Check the quantity of its bookings against the nominal on the statement: / %{count} bonds are priced on two scales (quotes around 100, booked price per unit around 1) and count a hundred times too high wherever they are valued; the return does not show it. Check the quantity of their bookings against the nominal on the statement: | Eine Anleihe ist auf zwei Skalen bepreist (Kurse um 100, gebuchter Preis je Stück um 1) und zählt hundertfach zu hoch, wo immer sie bewertet wird; die Rendite zeigt es nicht. Stückzahl ihrer Buchungen gegen das Nominal der Abrechnung prüfen: / %{count} Anleihen sind auf zwei Skalen bepreist (…) und zählen hundertfach zu hoch, wo immer sie bewertet werden; die Rendite zeigt es nicht. Stückzahl ihrer Buchungen gegen das Nominal der Abrechnung prüfen: |
| Reverse | One bond is priced on two scales (quotes around 1, booked price per unit around 100) and counts a hundred times too low wherever it is valued. Check its stored quotes — a quote around 1 is not a percent of face: / %{count} bonds … count a hundred times too low wherever they are valued. Check their stored quotes — a quote around 1 is not a percent of face: | Eine Anleihe ist auf zwei Skalen bepreist (Kurse um 1, gebuchter Preis je Stück um 100) und zählt hundertfach zu niedrig, wo immer sie bewertet wird. Ihre gespeicherten Kurse prüfen — ein Kurs um 1 ist kein Prozent vom Nennwert: / %{count} Anleihen … und zählen hundertfach zu niedrig, wo immer sie bewertet werden. Ihre gespeicherten Kurse prüfen — ein Kurs um 1 ist kein Prozent vom Nennwert: |
| B's badge | a hundred times too high / a hundred times too low | hundertfach zu hoch / hundertfach zu niedrig |

**Measured:**

| | 980 px | 390 px |
|---|---|---|
| Heute: first row starts | 228 px down | 154 px down |
| A: the two notes | 937 × 95 and 937 × 72 (block 175, left edge 22) | 362 × 221 and 362 × 162 (block 391, left edge 14) |
| A: first row starts | 414 px down | 557 px down |
| B: badges | 135 / 125 / 125 px wide; rows 49 / 49 / 48 px (unchanged) | rows 131 / 132 / 113 px (Heute 92 / 93 / 93): the badge takes a line under the class select |

At 390 px, A's notes take a phone screen before the first row. This is
accepted: the list is the finding's own page, and the rows follow.

**What the story writes into DESIGN.md** (Data quality → the two-scales
paragraph):

- the list's notes, their slot, their order and their entries;
- the "wo immer sie bewertet wird" clause and why it differs from Wealth's;
- rule ②.

**For the story:** the list needs each flagged bond's direction and both
figures, catalog-wide. Wealth reads them from the valuation's bond readings
(`Portfolios.Bonds.reading/2`), and the list from `Catalog.DataQuality`'s id
set. The note must read the same set as the count, or the count of N stops
opening a list of N.

### ③ N7 — #1112: the detail page is silent about the reverse two scales and about an implausible quote (variants)

**Today.**

- **The reverse two scales.** `BondStrip.two_scales_note/1` renders only
  `direction: :forward` (`bond_strip.ex:289`; `:316` renders nothing
  otherwise). DESIGN.md → The two-scales note → "The reverse case" records
  it: "a reverse finding renders nothing there yet (issue 1112, needs a
  board)".
  - The data: "Brackwater Anleihe 2031 2,50%", 100 units bought at 98,4,
    quotes around 1.
  - Its Overview reads "Wert 98,10 EUR" and "Unrealisiert -9.741,90" with no
    word.
- **The implausible quote** (#1101, Sprint 20; the widening comment of
  2026-10-08). Wealth names the position and links to its Quotes tab. The
  security's own pages say nothing.
  - The data: "Arbolia Inc.", sold 03.04.2026 at 61,40 USD; the quote of
    02.04.2026 is 618,90 (ratio 10,08).
  - Its Overview reads "+22.320,00" Unrealisiert.
- A security on two scales is left to that finding, so one security never
  carries both notes.

**Variants:**

- **A — recommended: both notes in the Overview's W1 slot.** Each is a
  problem note above the figures it falsifies, with W1's anatomy: a bold
  lead, the facts, the consequence, the remedy, the link.
  - **Reverse** (`data-role="two-scales-reverse-note"`): "**Auf zwei Skalen
    bepreist:** Kurse um 1 (zuletzt 0,981 am 05.10.2026), gebuchter Preis je
    Stück um 100 (1 Buchung: 98,4 am 12.03.2026). Dann zählen Wert, Gewinn
    und Gewicht hundertfach zu niedrig. Die gespeicherten Kurse prüfen — ein
    Kurs um 1 ist kein Prozent vom Nennwert: Kurse". The link goes to the
    Quotes tab; the forward note's goes to Transaktionen.
  - **Implausible** (`data-role="implausible-quote-note"`): "**Kurs passt
    nicht zu den Buchungen:** Verkauf 03.04.2026 zu 61,4 USD · Kurs
    02.04.2026: 618,9 USD, das 10,08-Fache (am Buchungstag unter der Hälfte
    oder über dem Doppelten des Preises je Stück). Wert oder Einstand dieser
    Position ist daher falsch. Die Kursquelle prüfen (Ticker, Börse), dann
    die Buchung: Kurse · Transaktionen".
    - It names the latest booking outside the band, and how many there are
      when there is more than one ("2 Buchungen, zuletzt: …"), as W1 does.
    - Kurse comes first because the remedy checks the quote source first.
- **B — the reverse note on the Overview, the implausible note at the head of
  the Quotes tab**, above the range line. A reader arriving from Wealth's
  entry (`?tab=quotes`, L2 A) lands on it.
  - **What B costs.** A reader who opens Arbolia from the list or a search
    lands on the Overview and reads "+22.320,00" with no word that it is
    wrong.
  - On the Quotes tab, the note's own "Kurse" link would point at itself, so
    B drops it.

**Why A:**

- **The Overview is the tab a security opens on,** from the list, a search,
  Wealth's names and the Overview's links.
- **Its Wert and Unrealisiert are exactly the figures each finding makes
  wrong.**
- **UX-DR17's placement rule** puts the note in the section with the data it
  describes, above it, as W1 already does for the forward case.

**Decided here, not filed:** under A the Quotes tab stays silent for a reader
who arrives from Wealth's entry. The entry already states the booking, the
quote and the ratio, and the Overview carries the note one tap back.

**Strings** (A; new, unless marked):

| | English (msgid) | German |
|---|---|---|
| Reverse lead | Priced on two scales: (existing) | Auf zwei Skalen bepreist: |
| Reverse quotes | quotes around 1 (latest %{close} on %{date}), | Kurse um 1 (zuletzt %{close} am %{date}), |
| Reverse bookings (`ngettext`) | booked price per unit around 100 (1 booking: %{price} on %{date}). / booked price per unit around 100 (%{count} bookings, the last %{price} on %{date}). | gebuchter Preis je Stück um 100 (1 Buchung: %{price} am %{date}). / gebuchter Preis je Stück um 100 (%{count} Buchungen, zuletzt %{price} am %{date}). |
| Reverse consequence and remedy | That means value, gain and weight count a hundred times too low. Check the stored quotes — a quote around 1 is not a percent of face: | Dann zählen Wert, Gewinn und Gewicht hundertfach zu niedrig. Die gespeicherten Kurse prüfen — ein Kurs um 1 ist kein Prozent vom Nennwert: |
| Implausible lead | Quote does not match the bookings: | Kurs passt nicht zu den Buchungen: |
| Implausible entry | %{kind} %{date} at %{price} %{currency} · quote %{quote_date}: %{close} %{currency}, %{ratio} times that (existing, Wealth's) | %{kind} %{date} zu %{price} %{currency} · Kurs %{quote_date}: %{close} %{currency}, das %{ratio}-Fache |
| Several bookings (`ngettext`; singular is the entry alone) | %{entry} / %{count} bookings, the last: %{entry} | %{entry} / %{count} Buchungen, zuletzt: %{entry} |
| Implausible rule, consequence, remedy | (on a booking's day, below half or above twice the price per unit). The value or the cost of this position is therefore wrong. Check the quote source (ticker, exchange), then the booking: | (am Buchungstag unter der Hälfte oder über dem Doppelten des Preises je Stück). Wert oder Einstand dieser Position ist daher falsch. Die Kursquelle prüfen (Ticker, Börse), dann die Buchung: |
| Links | Quotes · Transactions (existing) | Kurse · Transaktionen |

**Measured:**

| | 980 px | 390 px |
|---|---|---|
| A, reverse note | 907 × 72 (three lines) | 336 × 180 |
| A, implausible note | 907 × 72 | 336 × 180 |
| Note to the six figures | 18 px (the panel's gap) | 18 px |
| B, implausible note on Kurse | 907 × 72; the table starts 64 px below | — |

**What the story writes into DESIGN.md** (The two-scales note, W1 and W2):

- "The reverse case": the security's Overview renders the reverse note, with
  its sentence and its Kurse link;
- a sibling paragraph: the implausible-quote note on any security's
  Overview, its anatomy and its two links;
- that W1 holds at most one of the three, since a security on two scales is
  left to that finding.

**For the story:** the slot today is `BondStrip.two_scales_note/1`, which
renders only for a bond reading. The implausible note concerns any security,
so the slot becomes a small function of its own in the Overview, with one
case per finding, that reads the security's `implausible_quote` finding from
`Catalog.DataQuality`.

### ④ #1139 — the phone rows touch the viewport edges (before/after)

**Before.** `.phone-row` has `padding: 10px 0` (`app.css:8635-8642`), and
`.workspace-panel` has no inline padding.

**After.** `#securities-phone-rows .phone-row { padding-inline: 16px }` (rule
④), the gutter the toolbar's search field keeps. The border between rows
still runs edge to edge, as in the other phone lists.

**Measured** (390 px):

| | Before | After |
|---|---|---|
| Monogram from the left edge | 0 px | 16 px |
| Kebab's end from the right edge | 0 px | 16 px |
| Name column | 226 px | 194 px |
| Row height | 92 px | 92 px |

**Strings.** None.

**What the story writes into DESIGN.md** (Phone lists — two-line rows,
UX-DR27): the securities list's row carries the 16 px page gutter on both
sides.

### ⑤ #1151 — an open column picker survives a resize below 560 px (before/after)

**Before.** The 560 px block hides `#toggle-column-popover`,
`.column-picker-bar`, `#holdings-column-toggle` and
`#holdings-column-picker` (`app.css:8908-8913`), but not the securities
list's `#column-picker` (`securities_live.ex:518-526`). A picker opened at
1200 px stays open over the list at 390 px, and its toggle is gone.

**After.** `#column-picker` joins that selector list (rule ⑤).
`@open_popover` stays `:columns`, so widening the window shows the panel
again, as on Wealth.

**Measured** (390 px; a still, the picker rendered open):

- **Before:** the toggle is hidden; the panel is shown, 240 × 392 px, from
  x 140 to 380 over the rows.
- **After:** the panel is out of the layout.

**Strings.** None.

**What the story writes into DESIGN.md** (Inventory → Overlays, the column
picker): every picker's panel hides with its toggle under 560 px; name the
three.

### ⑥ #1163 — the chart tooltip and the trade markers read ISO dates, raw decimals and English (before/after)

**The spec rule:** DESIGN.md → Amendment 2026-10-07 — Displayed dates and the
chart axes. "Every displayed date goes through `Format`"; its "one known
exception" is this tooltip. The 2026-10-07 amendment's chart-axes section
says how the values read.

**Before.**

- **The tooltip.** `renderTooltip` (`layout_view.ex:955-972`) prints the
  payload as it comes: "2026-05-15", "41.4 USD", "buy 12 @ 41.12".
  - `points` are `[iso, Decimal.to_string(close), x, y]`
    (`security_chart.ex:181`, `point_display/1`).
  - `txs` carry `type`, `quantity` and `price` raw (`:238-242`).
- **The marker's SVG `<title>`** is "buy on 15.05.2026 at 41.12" (`:425`).

**After.**

- **The server sends display strings beside the raw values.** `points[i][4]`
  is the display date, and `txs[i].label` the trade line.
- **The ISO date stays at `points[i][0]`,** because the zoom sends it back as
  the custom range. `points[i][1]` was already a display slot, which Wealth's
  and the snapshots' charts fill with a `label`.
- **The tooltip reads** "15.05.2026" / "41,40 USD" / "Kauf 12 zu 41,12 USD":
  - the date through `Format.date`;
  - the close through `Format.decimal(close, 2)`, the Quotes table's and the
    pane head's form;
  - the kind through `TransactionKindLabel`, the quantity as stored
    (`Format.exact`), the price by the history's stored-figure rule (R10c),
    and the booking's currency.
- **A percent-mode point** prints the axis's signed percent ("+10,4%").
- **The marker title** reads "Kauf am 15.05.2026 zu 41,12 USD".
- **Every value still goes in through `textContent`** (#770).

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Tooltip trade line | %{kind} %{quantity} at %{price} %{currency} | %{kind} %{quantity} zu %{price} %{currency} |
| Marker title | %{kind} on %{date} at %{price} %{currency} | %{kind} am %{date} zu %{price} %{currency} |

**Measured:**

| | 980 px (chart 907 px wide) | 390 px (chart 336 px wide) |
|---|---|---|
| Tooltip before | 111 × 69 | 111 × 69 |
| Tooltip after | 150 × 69 | 150 × 69 |

At 390 px the wider tooltip no longer fits to the right of the crosshair at
this point, so the hook's existing rule places it to the left
(`positionTooltip`). It then covers two of the in-plot axis values while the
pointer rests. This is the hook's behaviour today for any point near the
right edge; it is not changed.

**What the story writes into DESIGN.md:** the 2026-10-07 amendment's "one
known exception" sentence becomes the rule: the tooltip and the marker title
read the page's language from display strings the server sends, and the raw
values stay for the zoom.

### ⑦ #1201 — the Overview tab prints "+10,00 %", coloured from the raw value (before/after)

**The spec rule:** DESIGN.md → Amendment 2026-10-08 — A return on no cost
basis, and the percent cells it changes. The Holdings tab's "%" moved to
`signed_pa/1` and `shown_percent_class/1`. The Trades amendment's "a
figure's sign and its colour are decided on the figure as displayed" applies
too.

**Before.**

- `signed_percent_or_dash/1` (`securities_live.ex:3302-3313`) prints two
  decimals and a breaking space before "%".
- `pnl_class/1` (`:3234`) colours the cell from the raw value. Larkspur's day
  change of +0,0041 % prints "0,00 %" in the gain colour.

**After.**

- **The figures** use `signed_pa/1`: one decimal and the sign glued on.
  Tagesänderung reads "0,0%" in body ink (`is-flat`), 1J reads "+10,0%".
- **The colour** comes from the percent as shown.
- **Unrealisiert** keeps its amount at two places, with `shown_class(amount,
  2)`. Its sub-line's percent ("+26,1%") is a `decimal-positive` /
  `decimal-negative` span inside the muted line, the phone rows'
  second-line anatomy.

**Measured:**

| | 980 px | 390 px |
|---|---|---|
| Tagesänderung colour, before | rgb(4, 120, 87), the gain colour | same |
| Tagesänderung colour, after | rgb(14, 20, 27), body ink | same |
| 1J cell | 182 × 40 | 150 × 40 |
| Unrealisiert cell | 182 × 55 | 150 × 55 |
| Figure grid | 166 px | 235 px |

No size changes: the repair is to the value and the colour only.
`security_detail_overview_test.exs:99` pins "+10,00 %" and flips on purpose.

**Also in this story** (found while drawing, 4): the securities list's
Tagesänderung %, Performance 1M and Performance 1J columns, and the phone
row's day change. They take the same form ("+0,4%") and the colour of the
figure as shown, through `render_cell(:percent_signed)` and
`phone_change/1`. The list frames on this board draw today's "+0,42 %"; the
rule is ⑦'s, so there is no separate picture.

**Strings.** None.

**What the story writes into DESIGN.md** (Amendment 2026-10-08, the percent
cells): the Overview tab's day change, 1J and the Unrealisiert sub-line, and
the securities list's three percent columns and phone day change, join the
list.

### Spec

- **UX rules:** UX-DR17 (one finding per note; placement in the section with
  its data), UX-DR25, UX-DR27, UX-DR15.
- **DESIGN.md:**
  - Filter chips (D2);
  - Data quality → the two-scales paragraph and `dq-implausible-quote`;
  - The two-scales note (W1 and W2), with "The reverse case";
  - Amendment 2026-10-07 — Displayed dates and the chart axes;
  - Amendment 2026-10-08 — the percent cells;
  - Phone lists — two-line rows.
- **Decisions:** D-15 (Sprint 19, catalog-wide two scales); L2 A (Sprint 20,
  #1101); the comment on #1112 of 2026-10-08.

### Found while drawing

1. **The chip label ends in a space.** `format_value(_, false)` returns `""`,
   so `chip_label/1` builds "Stillgelegt = false ". **Fixed in the story
   that touches the surface (D-14):** N6's formatter replaces the
   concatenation.
2. **The `missing_logo` list's "Logo-Suche für alle wiederholen" has no
   gutter.** `.dq-bulk-action` is a direct child of `.workspace-panel` with
   `margin-top` only. Measured on a scratch page with `app.css`: the button
   starts at x 0 at 980 and 390 px, while the chip above it starts at 18 and
   10 px. It is N3.2 A's slot. **Fixed in the story that touches the surface
   (D-14):** `.workspace-panel > .dq-bulk-action` joins rule ②'s margin.
3. **Wealth's and the snapshots' chart tooltips read ISO dates too.** They
   share `build_payload/6`. **Fixed in the story (D-14):** the display date
   is built in the shared payload, so all three charts get it. Their `label`
   is already localised.
4. **The securities list's percent columns still print the retired form.**
   Tagesänderung %, Performance 1M and 1J print "+0,42 %": two places, a
   breaking space, colour from the raw value. They go through
   `render_cell(%Field{render_hint: :percent_signed})`
   (`securities_live.ex:4058-4077`), and so does the phone row's
   `phone_change/1`. #1201 says the Overview tab "is the last one left"; it
   is not. **Folded into #1201's story (D-14, the coordinator's call):** the
   list's three columns and its phone row's day change take the same form
   and colour rule as the Overview (⑦). The list frames on this board still
   draw today's form.
5. **A's notes fill a phone screen.** At 390 px the two two-scales notes are
   391 px tall and the first row starts 557 px down. **Decided here:** the
   list is the finding's own page; nothing is collapsed.


---

## Board 03 — the transaction history and its booking drawer

**Board:** `design-language/mockups/ux-design-2026-10-09/03-history-drawer.html`,
rendered as `03-history-drawer--1200.png` and `03-history-drawer--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup of
  `transaction_management_live.ex` (the history `#transaction-list`, the phone
  rows `#transaction-phone-rows`, the booking drawer and the notes-only drawer,
  both `dialog.detail-pane.booking-drawer`) and `AppShell` (`area_tabs`,
  `inline_result`, `data_note`, `row_kebab`). A desktop frame is 980 px
  (1200 − 220 sidebar). A phone frame is a real 390 px viewport; the drawer's
  phone frames are 390 × 844 with the sheet opened by `showModal()`, as the
  `ModalDialog` hook opens it under 720 px.
- **CSS.** "Heute" frames render `app.css` as shipped; variant and "Nachher"
  frames add the board's `<style id="proposal">`, which holds one rule (N12 A).
- **Data.** Accounts "Test-Cash", "Tagesgeld", "USD-Konto", depot "Depot
  Muster"; securities "Arbolia Inc." (USD), "Wrenfield Gardens AG", "Larkspur
  Rail AG"; October 2026. All invented.

### N10 — #1147: an inflow and an outflow differ only by a minus (variants)

**Today.** `signed_money/3` (`transaction_management_live.ex:1806-1819`) negates
`@outflow_kinds` (buy, removal, fee, tax; a transfer by the account in view) and
prints every other amount bare through `Format.money/1`. "Steuererstattung
12,40" and "Gebühren -4,90" differ by one hyphen; a zero outflow prints "-0,00".
No sign class on the cell (`:400-404`) or the phone row (`phone_amount/2`,
`:1743-1751`). DESIGN.md → Transactions → the target vocabulary records it:
"Positive amounts still carry no "+" and history rows no sign colour; that gap
against the Accessibility Floor is its own story."

**Variants:**

- **A — recommended: "+" on every inflow, no colour; "0,00" unsigned.**
  `signed_money/3` keeps deciding the direction and formats through
  `Format.signed_decimal(amount, 2)`, which already prints "+", "-" and nothing
  for a figure that rounds to zero. The cell, the phone row and the delete
  dialog's box (which reads `phone_amount/2`) follow. A balance snapshot is a
  level and keeps its stored sign.
- **B — the sign and the gain/loss colour** (`.is-positive` / `.is-negative` on
  the cell; the history is no `.data-table`, so the bare classes colour it
  without a new rule). Every buy reads red, every deposit green.
- **C — colour on the running balance only** (risen positive, fallen danger).
  The balance column exists only when the chips narrow to one account, so on the
  default, unfiltered history C changes nothing.

**Why A.** A booking's amount is a flow, and a flow's sign is a direction, not a
gain — the contribution table's settled rule (DESIGN.md → the contribution
table: "Zu-/Abflüsse and Erträge signed and **uncoloured**"). The sign closes the
Accessibility-Floor gap by text (UX-DR7), works in forced colours, and keeps
green and red meaning gain and loss across the app. B colours a month of buying
as a month of losing; C is colour-only and absent on the default view.

**Strings.** None new (`Format.signed_decimal/2`).

**Measured (980 px; 390 px):** the Betrag cell is 119.8 px today and 128.3 px
under A (nine rows); the table stays 931 px in its 933 px wrapper — no overflow.
Phone: the widest amount line grows from 93.5 px ("1.500,00 EUR") to 102.6 px
("+1.500,00 EUR"); rows stay 59.4 px.

**What the story writes into DESIGN.md** (Transactions → the target vocabulary):
the amount is a flow, signed "+"/"-" and uncoloured, a zero unsigned, a set
balance unsigned; the "that gap … is its own story" sentence goes, and Colors'
"Semantic colour applies wherever a sign exists" gains "a gain or a loss; a
flow's sign is a direction (the contribution table, the history)".

### N11 — #1148: the Preis cell names no currency (variants)

**Today.** The Preis cell prints `stored_figure(transaction.price)` with no
suffix (`:394`), the phone row's size "8 × 100,00" likewise (`phone_size/1`,
`:1761-1762`). The Betrag beside it names the cash account's currency
(`money_currency/1`). The price is in the **booking's** currency
(`currency_code`): the security's for a cross-currency trade, the account's for
a trade an import booked in the account's currency (ADR-0015's amendment,
#1198's case 1). The board's row 1 reads "100,00" beside "-806,00 EUR" (800 USD
settled); row 3, the same USD security imported at 88,10 EUR, reads the same.

**Variants:**

- **A — recommended: always the price's own currency** as the value suffix
  (`<small class="value-suffix">`), in the cell and in `phone_size/1`
  ("8 × 100,00 USD"); the delete dialog's box follows. A split's ratio and a
  dash carry none.
- **B — only where it differs from the amount's currency.** Quietest; a bare
  price then means "same as the Betrag", and the column mixes suffixed and bare
  figures, so its digits stop lining up.
- **C — the Währung column on by default.** No new markup, but the column names
  `currency_code` after the Betrag (the picker's key order): "-806,00 EUR · USD".
  The phone row is a fixed composition, so C changes nothing there; a stored
  column choice never shows it.

**Why A.** One rule, the page's existing currency anatomy, nothing to infer:
row 1's USD and row 3's EUR are each right, which only A says without the reader
comparing figures.

**Strings.** None.

**Measured (980 px; 390 px):** the Preis cell is 86.1 px today and 119.5 px
under A (the suffix 23.2–24.5 px); the table stays 931 px in its wrapper under A
and C. Phone: the size line is 64.1 px today and 92.7 px under A ("8 × 100,00
USD"); the figures column is at most 92.7 px and the row's body keeps 221–242 px;
row heights unchanged.

**What the story writes into DESIGN.md** (Transactions → "The price keeps its
stored digits"): the price carries its booking currency as the value suffix in
the cell, the phone row's size and the delete dialog's box.

### N12 — #1052, #1206: the drawer books and corrects the one-amount cash kinds (variants)

**Today.** The drawer's Typ offers Kauf and Verkauf only
(`transaction_management_live.ex:2262`, `for type <- ["buy", "sell"]`); "Bearbeiten"
on any other kind opens the notes-only drawer (`fixed_booking/2`, `:889-894`;
pick H2b A) with the help line "Datum, Beträge und Konten dieser Buchung stehen
hier fest; die Oberfläche bucht nur Käufe und Verkäufe. Korrigiert wird die
Buchung über API oder MCP, oder sie wird gelöscht und neu importiert." No screen
books a fee or a tax refund — the remedy ADR-0053 A5's refusal names.
**The decision:** booking and in-place correction of dividend, interest, deposit,
removal, fee, tax and tax refund through `Ledger.create_transaction/3` /
`Ledger.update_transaction/3`; transfers, deliveries and balance snapshots keep
the notes-only drawer and delete-and-re-import.

**Variants:**

- **A — recommended: one drawer, the kind first.** Typ lists Kauf, Verkauf,
  Dividende, Zinsen, Einlage, Entnahme, Gebühren, Steuern, Steuererstattung. A
  cash kind shows Datum, Verrechnungskonto (select; the account fixes the
  currency, as the depot does for a trade, #473), Wertpapier (required for a
  dividend; optional "Kein Wertpapier" for interest — ADR-0051's
  security-linked interest, #928 — fee, tax and tax refund; absent for deposit
  and removal), "Betrag (EUR)" (paired with "Steuern (EUR)" for a dividend or
  interest), one direction line ("Wird Test-Cash gutgeschrieben." / "Wird von
  Test-Cash abgebucht.", so no sign is ever typed) and Notizen. The booking is in
  the account's currency (as `Ledger.set_cash_balance/3` books a level);
  `portfolio_id` comes from the account. **Edit** opens the same form prefilled;
  the kind and the cash account are disabled, the help line states that limit
  with "Löschen…" as its remedy; an imported booking carries one attention note
  on what the next import does. **Refusal** (amount ≤ 0) is today's pair: the
  field error "muss größer als 0 sein" under the amount (`aria-invalid`) and the
  page's result "Betrag muss größer als 0 sein"; what was typed stays.
- **B — a menu and one dialog per kind.** "Transaktion erfassen ▾" lists "Kauf
  oder Verkauf…" and seven kinds; each opens a narrow modal ("Steuererstattung
  erfassen"). Two booking surfaces (a non-modal drawer, modal dialogs over the
  history), eight places an edit opens, about sixteen new strings, and a second
  click for a buy.
- **C — inline edit in the history row.** No panel; but a new booking has no
  row (#1206 unanswered), the phone has no table, a refusal has nowhere to stand,
  and the reading table must squeeze inputs (measured below).

**Why A.** The drawer is already the one place a booking is made and corrected
(#803, "shaped for the edit view to reuse"); A adds one choice where the operator
already makes it, and every kind books, reads and corrects the same way. The
remedy of ADR-0053 A5 — sale, fee, refund — becomes three drawer bookings.

**"Identity fields frozen per ADR-0050 §16" — the board's reading.** ADR-0050's
freezes (§11, pinned by §16 invariant 15) are an account's currency and
portfolio and a security's currency; they name no booking field, and
`Ledger.update_transaction/3` lets the API change every public field. The board
freezes **the kind** (a different kind is a different booking, and ADR-0050 §1
already forbids an imported row becoming an anchor or a split) and **the cash
account** (it fixes the amount's currency — moving a booking to an account of
another currency re-denominates it, §11's own reason). Date, amount, taxes,
security and note are corrected in place. To flip by comment: "N12 account
editable".

**Strings** (new unless marked):

| | English (msgid) | German |
|---|---|---|
| Sub line, new cash booking | Books to the chosen cash account, in its currency. | Bucht auf das gewählte Verrechnungskonto, in dessen Währung. |
| Account select, empty | Select cash account | Verrechnungskonto auswählen |
| Optional security, empty | No security | Kein Wertpapier |
| Direction, credit | Credited to %{account}. | Wird %{account} gutgeschrieben. |
| Direction, debit | Debited from %{account}. | Wird von %{account} abgebucht. |
| Before an account is chosen | Currency is set by the selected cash account. | Die Währung wird durch das gewählte Verrechnungskonto bestimmt. |
| Taxes label | Taxes (%{currency}) | Steuern (%{currency}) |
| Edit help (+ "Delete…") | The kind and the cash account of a booked transaction are fixed; a booking of the wrong kind or on the wrong account is deleted and recorded again. | Art und Verrechnungskonto einer gebuchten Transaktion stehen fest; eine Buchung der falschen Art oder auf dem falschen Konto wird gelöscht und neu erfasst. |
| Edit, imported booking (attention note) | This booking came from an import. Corrected here, it stays so: a re-import of the same file does not book it again, and the import's correction names it as edited by hand. | Diese Buchung stammt aus einem Import. Hier korrigiert, bleibt sie so: Ein erneuter Import derselben Datei bucht sie nicht noch einmal, und die Import-Korrektur nennt sie als von Hand bearbeitet. |
| Notes-only help, imported (changed) | The date, amounts and accounts of this booking are fixed here; the screen books buys, sells and cash bookings, not this kind. The booking is corrected over the API or MCP, or it is deleted and imported again. | Datum, Beträge und Konten dieser Buchung stehen hier fest; die Oberfläche bucht Käufe, Verkäufe und Kontobuchungen, diese Art nicht. Korrigiert wird die Buchung über API oder MCP, oder sie wird gelöscht und neu importiert. |
| Notes-only help, API (changed) | … or it is deleted and booked again there. | … oder sie wird gelöscht und dort neu gebucht. |
| Reused | Record transaction, Edit transaction, Save changes, Cancel, Type, Date, Cash account, Security, Notes, Amount (%{currency}), the kind labels, "must be greater than %{number}" (errors) | unchanged |

The imported-booking note depends on ADR-0053's A11, signed on this PR (#1194:
a hand-edited booking is named, not rewritten); if A6 slips, the note's second
clause goes.

**Measured:**

- **980 px.** The drawer is 380 px beside a 560 px history; "Betrag (EUR)" is
  354 px on its own row (the proposal's rule), 169 px paired with Steuern. Drawer
  heights: today's trade 603 px; A new 679, refused 704, edit 925 px. In a
  1200 × 800 window the drawer's cap is 724 px, so the edit state scrolls inside
  the drawer (as a buy with its costs open does today). The import note is
  354 × 108 px.
- **390 × 844.** The sheet is 684 px (new), 709 px (refused) and 743 px (edit:
  the 88 vh cap, content 934 px, so "Änderungen speichern" is reached by scrolling
  the sheet). Amount 356 px alone, 170 px paired.
- **C at 980 px.** The date input is 88 px for 92 px of text, the security select
  132 px with its name cut, the actions column 204 px; the table just fits
  (931/931). Under the table's ~780 px floor the edited row scrolls.

**CSS (the proposal's one rule).** `.booking-drawer .form-grid >
label:nth-child(5):last-child { grid-column: 1 / -1 }` — a kind without taxes
leaves the amount as the fifth and last label; it takes the full row.

**What the story writes into DESIGN.md** (Components → Booking drawer; the
H2b amendment): the drawer books the seven one-amount cash kinds, their fields
per kind, the direction line, edit with kind and account frozen and its help
line, the imported-booking note; the notes-only drawer now serves transfers,
deliveries, the balance snapshot, the split and a cash kind booked in another
currency than its account's.

### #1209 — the Betrag is the cash the balance moves (before/after)

**Today.** The Betrag is `tx_money/1` (`:1795-1798`): the stored `gross_amount`,
else quantity × price; the summary adds `tx_amount/1` (`:1490-1495`) the same
way. The balance follows `Projection.effects/1`, which adds a buy's fees and
taxes (`buy_cost/1`, `projection.ex:338-346`; a sell subtracts them). A buy of
20 × 48,20 with a fee of 1,00 and no gross amount reads -964,00 while the Saldo
falls 965,00; a buy at 0,00 reads "-0,00".

**After.** The Betrag, the summary and the phone row read the cash leg of
`Projection.effects/1` for the row's cash account (one exposed function); a zero
reads "0,00". Spec: ADR-0004 (balances derive from the ledger) and ADR-0015 (a
booking's fees and taxes are in its account's currency); DESIGN.md → Transactions
→ the target vocabulary ("the Betrag is that account's view").

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Summary basis (changed) | Counts and the cash moved per kind of the transactions this filter selects, summed per currency, unsigned and not converted. | Anzahl und bewegtes Geld je Art der Transaktionen, die dieser Filter auswählt — je Währung summiert, ohne Vorzeichen und nicht umgerechnet. |

**Measured** (Test-Cash alone, four rows): Σ Betrag is -270,00 today and
-271,00 after; the Saldo moves from 3.035,50 to 2.764,50, by -271,00. "Kauf: 3"
reads 1.770,00 EUR today (the issue's figure) and 1.771,00 EUR after. The cell
stays 114.9 px; the basis line stays one line (933 px) at 980 px.

**What the story writes into DESIGN.md:** the Betrag is the cash the row moved
in its account (the projection's cash leg), the summary sums the same figure,
and a zero is unsigned; the test pins Σ Betrag = Δ Saldo for a drawer buy, an API
buy without a gross amount and a sell.

### #1213, the drawer's half — the amount's label names the account's currency (before/after)

**Today.** The notes-only drawer labels a cash kind's amount
`gettext("Amount (%{currency})", currency: tx.currency_code)` (`:2127`; a
transfer `:2084`). A USD dividend credited 80,00 EUR over the API with its rate
stored reads "Betrag (USD) 80,00" while the history reads "80,00 EUR"; its taxes
name no currency.

**After.** "Betrag (EUR)" and "Steuern (EUR)": the cash account's currency, the
history's `money_currency/1` rule (ADR-0015, amendment of 2026-10-07, point 1).
A transfer's and a balance snapshot's `currency_code` is their account's, so
their labels do not change. Under N12 A the editable form carries the same two
labels; this API-booked dividend keeps the notes-only drawer (found while
drawing 3).

**Strings.** "Taxes (%{currency})" → "Steuern (%{currency})" (shared with N12);
"Amount (%{currency})" unchanged, its binding changes.

**Measured:** the label is 82.3 px ("Betrag (USD)") and 80.8 px ("Betrag
(EUR)"); the panel is 776 px tall in both.

**What the story writes into DESIGN.md** (H2b amendment, "The facts,
disabled"): "Betrag (EUR)" names the cash account's currency, and Steuern
carries it too.

### Found while drawing

1. **The drawer's own same-currency buy stores no gross amount.**
   `SettlementForm.prepare(params, nil)` sends no `gross_amount`, so #1209 is not
   only the API's route: every hand-booked buy with a fee reads less than the
   balance moves. **Fixed in the story that touches the surface (D-14)** — the
   #1209 display rule covers it; its test books one buy through the drawer.
2. **With the drawer open at 1200 px the history scrolls sideways.** The history
   column keeps 560 px; its table needs 676 px in a 511 px wrapper, so Preis and
   Betrag of the row being corrected are out of view while its drawer is open
   (today, and more often once N12 sends every cash kind there). **Filed at the
   merge:** "With the booking drawer open the history hides Preis and Betrag
   behind a sideways scroll".
3. **A one-amount booking in a currency other than its account's** (an API
   booking with a stored `settlement_fx_rate`; the importer books these kinds in
   the account's currency) would keep a stale rate if its amount were corrected
   alone. **Fixed in the story (D-14), failing closed:** such a booking keeps the
   notes-only drawer (its help line already names API/MCP); no money-data rule
   changes. Flip by comment if the owner wants it editable.
4. **Under 720 px a long drawer state puts its primary action below the fold:**
   the edit form needs 934 px in a 743 px sheet (as a buy with its costs open
   does today). **Fixed in N12's story (D-14, decided at the planning):** α6
   makes the drawer taller, so the sheet's foot stays at the sheet's edge
   while its body scrolls; it is the same surface, and the spec's sheet
   anatomy already puts the actions at its foot.
5. **The triage note's line for the drawer's kinds is off:** `:994` is
   `:2262` today; the board cites the live line. No action.


---

## Board 04 — Wealth, Income and Cash flow

**Board:** `design-language/mockups/ux-design-2026-10-09/04-wealth-income.html`,
rendered as `04-wealth-income--1200.png` and `04-wealth-income--390.png`.

- **Frames.** `srcdoc` iframes built from the live markup of
  `portfolio_live.ex` (the Positions table, `holdings_cell/2`),
  `portfolio/contribution_table.ex` (`desktop_table/1`, `phone_rows/1`,
  `phone_line/1`), `securities_live.ex` (`overview_tab_panel/1`) and
  `income_live.ex` (the Trades, Flows and Costs facets,
  `fx_backfill_control/1`), with the German msgstrs. Desktop frames are
  980 px; phone frames are real 390 px viewports, where Positions and the
  contribution table give way to phone rows and the matrices scroll.
- **CSS.** None of these stories adds CSS; the proposal block holds only the
  comment listing the markup and format changes.
- **Data.** Two depots ("Depot Muster", "Depot Nord"), six positions in the
  demo seed's style, "Nordwind Industrie AG" (DE000000000N), "USD
  Settlement"; invented figures, 2025–2026 dates.

### ① N5 — #1125: Wealth's optional value columns (variants)

**Today.** The column picker (#814) offers the holdings projection's
valuation fields. `holdings_cell/2` prints every one through
`Format.exact` — every digit the projection carries, trailing zeros trimmed
(`portfolio_live.ex:2697-2704`, `:2721-2729`) — and the template puts the
suffix straight after the digits (`:2506-2512`), so a cell's text reads
"1.100USD", "2.569,676EUR", "7.011,6EUR", "0EUR"; a computed average reads
"33,33333333333333333333333333 EUR" (100 ÷ 3 at 28 digits). It is
deliberate: DESIGN.md (2026-10-08 amendment, `:6242-6243`): "The table's
money columns keep the projection's unrounded digits". ADR-0016 §4: the
human boundary rounds money to two places. #1125's comment adds the missing
fixed decimals ("167,2 EUR", "336 EUR").

**Variants:**

- **A — recommended.** "Marktwert" and "G&V" are money: `Format.money`, two
  places. "Ø Kosten" and "Letzter Kurs" are prices per unit: the history's
  stored-figure rule R10c (DESIGN.md, the history's price column, amended
  2026-10-07) — every digit up to four places, at least two, a price under 1
  at least three significant digits — so "128,4838" reads as the Kurse tab
  and the history print the same quote, and the average becomes "33,3333".
  Quantities keep their digits. A text space before every suffix.
- **B — every value column through `Format.money`.** One rule, the simplest
  code; it rounds prices to cents ("128,48" beside the Kurse tab's
  "128,4838"; a price under a cent reads "0,00").
- **C — keep every digit, add the space.** Keeps DESIGN.md's sentence; the
  figures still disagree with every other money cell, and a computed
  average's 28 digits set the column's width.

**Why A.** It follows ADR-0016 §4, which the DESIGN.md sentence contradicts;
that sentence was a side remark of the "G&V %" repair, not a decision with a
reason of its own. Its reason — "the human read of what the API serves" — is
kept where it matters: the API and MCP serve every digit. And a price is not
money: rounding it (B) makes Wealth disagree with the security's Kurse tab
and the history for one stored quote.

**Strings:** none (format calls and one text space).

**Measured** (980 px, every column on):

| | table / scroller | "Ø Kosten" column | digits → suffix | a cell's text |
|---|---|---|---|---|
| Heute | 1064 / 931 px — **133 px out of view**, "G&V" and "G&V %" scrolled off | 270 px | 4.0 px (margin only) | "1.100USD" |
| A | 931 / 931 px — fits | 104 px | 7.2 px | "1.100,00 USD" |
| B | 931 / 931 px — fits | 97 px | 7.2 px | "1.100,00 USD" |
| C | 1084 / 931 px — 153 px out of view | 273 px | 7.2 px | "1.100 USD" |

At 390 px nothing changes: the table gives way to phone rows that show the
quantity alone (#1065).

**What the story writes into DESIGN.md:** the 2026-10-08 amendment's
sentence becomes "The table's money columns print as money (`Format.money`,
two places); its price columns as the history prints a stored price (R10c);
quantities keep their digits; a space precedes every suffix" — citing
ADR-0016 §4; and "G&V" joins the signed cells (found while drawing 1).

### ② #1123 — the contribution table's phone row names a position's costs (before/after)

**Today.** At 1200 px the table has a "Kosten" column
(`contribution_table.ex:179`, `:204`). Under 560 px the row's second line is
`phone_line/1` (`:621-629`): the ends, the flow and the income where not
zero — never the costs. Larkspur Rail AG reads "zu Beginn nicht im Bestand ·
Zufluss in die Position 920,00" over "+32,50": 962,50 − 920,00 is 42,50, and
the 10,00 of costs are the difference.

**Rule applied:** DESIGN.md → the contribution table → "Under 560 px
(UX-DR27)", which the issue extends: "· Kosten 10,00" after the income,
where not zero — the basis line's order (flows, income, costs) and the
desktop column's figure, unsigned as there. The remainder row's
"Gebühren/Steuern" (fees and taxes on no trade) is unchanged.

**Strings (new):**

| English (msgid) | German (msgstr) |
|---|---|
| "costs %{amount}" | "Kosten %{amount}" |

**Measured** (390 px): position rows 58 / 76 / 76 / 59 → 58 / 93 / 93 / 59
px; their second lines 1 / 2 / 2 / 1 → 1 / 3 / 3 / 1 lines; the list 447 →
480 px.

**What the story writes into DESIGN.md** ("Under 560 px", A position): the
costs clause; and it corrects the paragraph's flow words, which still say
"Zufluss x" / "Abfluss x" where the build says "Zufluss in die Position x"
since #1090 (found while drawing 6).

### ③ #1149 — a figure that reads zero has no sign and no gain/loss colour (before/after)

**Today.** The Trades amendment's rule (DESIGN.md, 2026-10-07: "The sign
and the colour are decided on the figure as displayed",
`Format.displayed_sign/2`) holds on the Trades facet and the security's
Trades tab only.

- **The colour:** `pnl_class/1` (`securities_live.ex:3234-3245`) colours by
  the raw value: on Nordwind Industrie AG's Übersicht a day change of
  +0,004 % reads "0,00 %" in the gain colour, an unrealised result of
  −0,004 EUR "0,00" in the loss colour.
- **The negative zero:** `Format.money/2` and `Format.percent/2`
  (`format.ex:21-41`) print `Decimal`'s "-0.00", so the "Realisiert je
  Periode" matrix (`income_live.ex:647`) shows "-0,00" for a February whose
  one sale netted −0,004 EUR.

**Rule applied:** the Trades amendment's (DESIGN.md → Trades → "Realisiert
gesamt" is signed): a figure that reads zero carries neither a sign nor a
gain/loss colour. Nachher: "0,00 %" and "0,00" in body ink; "0,00" in the
matrix. One rule for every caller: `Format.money/2` and `Format.percent/2`
drop the negative zero (the private `signed_text/2` already does for the
signed forms), and every raw-sign class helper takes
`Format.displayed_sign/2` — `pnl_class/1` and those found while drawing (2,
3). Its own commit, with a sweep test over exact strings (the plan's G4).

The percents keep today's form in the frames; #1201 (board 02) changes their
digits ("+12,48 %" → Format.signed_percent) on the same metrics.

**Strings:** none.

**Measured:** no size changes.

**What the story writes into DESIGN.md:** the Trades amendment's sentence
generalised under Colors ("a figure that reads zero carries no sign and no
gain/loss colour, wherever it is printed"), with `Format.money/2` and
`Format.percent/2` named.

### ④ #1210 — the Costs matrix shows each month's total (before/after)

**Today.** The Costs read's months carry `fees` and `taxes` only
(`costs.ex:156-160`), so the "Gesamt" row spans its twelve month cells with
one empty cell (`income_live.ex:825-829`): a January with 5,00 of fees and
1,00 of taxes never shows its 6,00 — the figure ADR-0015's amendment of
2026-10-07 names in identity 2.

**Rule applied:** ADR-0015, amendment of 2026-10-07, identity 2; the matrix's
own anatomy (each row prints its months). The read gains
`months[m].total` (fees + taxes) with its computation basis and contract
entry 19 (the plan's G4); the row prints it in each month through `money/1`,
as the series rows print theirs — "0,00" in an empty month (see found while
drawing 5 for the matrix-zero rule).

**Strings:** none (no new label; the row is "Gesamt" already).

**Measured:** the "Gesamt" row has 14 cells instead of 3, 32 px tall; at
980 px the matrix still fits (931 / 931 px); at 390 px it scrolls, 798 px in
a 356 px scroller (UX-DR15), as before.

**What the story writes into DESIGN.md** (the Cash-flow facets, Costs): the
Total row prints each month's fees + taxes, and the read's field and basis.

### ⑤ #1150 — "Wechselkurs", never "Kurs" (before/after, German copy)

**Today.** `fx_backfill_control/1` (`income_live.ex:100-146`) renders inside
the exclusion note of the Trades, Flows and Costs facets. Since #1089 the
Trades note says "kein gespeicherter Wechselkurs"; the control beside it
says "Die tägliche Kurssynchronisation …", "Historische Kurse nachladen" and
"Nachladen hat 214 Kurse gespeichert.", and the Flows and Costs notes say
"kein gespeicherter Kurs".

**Rule applied:** DESIGN.md → the contribution table's account sentence
(`:4019`): "‘Wechselkurs’, never ‘Kurs’, which the screen keeps for a
security's price"; and the Trades currency note (`:3326-3329`).

**Strings (msgstr only; the English msgids already say "rate"):**

| msgid (unchanged) | German before | German after |
|---|---|---|
| "The daily rate sync cannot fill a past date. The backfill fetches …" | "Die tägliche Kurssynchronisation kann einen vergangenen Tag nicht nachtragen. …" | "Die tägliche Synchronisation der Wechselkurse kann einen vergangenen Tag nicht nachtragen. …" (rest unchanged) |
| "Backfill historical rates" | "Historische Kurse nachladen" | "Historische Wechselkurse nachladen" |
| "Backfill stored %{count} rate." / "… rates." | "Nachladen hat %{count} Kurs gespeichert." / "… Kurse gespeichert." | "Nachladen hat %{count} Wechselkurs gespeichert." / "… Wechselkurse gespeichert." |
| Flows note, "%{count} flow could not be converted — no stored rate at its booking date — …" (and plural) | "… kein gespeicherter Kurs zu seinem Buchungsdatum …" / "… zu ihren Buchungsdaten …" | "… kein gespeicherter Wechselkurs zu seinem Buchungsdatum …" / "… zu ihren Buchungsdaten …" |
| Costs note, "%{count} cost could not be converted — no stored rate at its booking date — …" (and plural) | "… kein gespeicherter Kurs …" | "… kein gespeicherter Wechselkurs …" |
| Flows and Costs ⓘ (found while drawing 4) | "zum Kurs seines eigenen Buchungstags", "kein Kurs gespeichert", "zum Kurs eines Nachbartags" | "zum Wechselkurs …", "kein Wechselkurs gespeichert", "zum Wechselkurs eines Nachbartags" |

"Lädt nach…" and "Historische Reihe wird geholt…" are unchanged. The German
docs follow: `docs/de/product-documentation.md:2456-2458` and
`docs/de/integration/api-and-mcp.md:3072` (the triage's), and `:1687` of the
product documentation (found while drawing 5).

**Measured:** the button "Historische Wechselkurse nachladen" 232 × 34 px,
one line at 980 and 390 px; the Trades note 140 px tall at 980, 284 px at
390.

**What the story writes into DESIGN.md:** the account sentence's rule
extended to the backfill control and the three facets' notes and ⓘ.

### Found while drawing (board 04)

1. **Wealth's "G&V" column prints a signed figure without its "+" or its
   colour** ("60", "-65"), against DESIGN.md → Colors ("wherever a sign
   exists, at every level of a table") and issue 1010's rule. **Fixed in
   N5's story (D-14):** signed, in its sign colour decided on the displayed
   figure (#1149); drawn dashed in every variant.
2. **The contribution table decides sign and colour on the raw value**
   (`contribution_table.ex:663-675`, `signed_money/1`, `sign_class/1`; and
   Wealth's badge, `portfolio_live.ex:3506-3517`, whose rule it copies): a
   contribution of 0,004 reads "+0,00" in the gain colour. **Fixed in
   #1149's sweep (D-14).**
3. **The Overview's card and trades helpers do the same**
   (`dashboard_live.ex:1035-1047`): "+0,0%" in the gain colour for a YTD of
   +0,0004. **Fixed in #1149's sweep (D-14)** (also listed on board 01).
4. **The Income matrix's zero dash is decided on the raw value**
   (`matrix_cell/1`, `income_live.ex:1305-1311`): 0,004 prints "0,00", not
   DESIGN.md's Matrix-zero dash, and −0,004 prints "-0,00". **Fixed in
   #1149's story (D-14):** "zero" means displayed as zero.
5. **The Trades, Flows and Costs matrices never use DESIGN.md → Matrix zero**
   ("–" where a sum is 0,00, `:1667`): they print "0,00" in every empty month
   (`income_live.ex:647`, `:725-734`, `:814-821`), while the Income facet's
   matrix uses the dash. Whether the rule covers the three Cash-flow
   matrices — and #1210's new row with them — is a choice. **Decided at the
   planning, fixed in #1149's story (D-14):** one rule for every matrix on
   the page, so the three Cash-flow matrices and #1210's row print "–"
   where a month sums to zero, as the Income facet's matrix does.
6. **The Flows matrix's "Netto" row has the same empty span as Costs'
   "Gesamt"** (`income_live.ex:736-740`, `colspan="12"`): a month's net
   deposits never shows. It needs the ExternalFlows read's own field, basis
   and contract change. **Filed at the merge:** "Cash flow → Ein- &
   Auszahlungen: the Netto row never shows a month's net".
7. **The Flows and Costs ⓘ say "Kurs" three times each**, where the Trades
   facet's ⓘ says "Wechselkurs". **Fixed in #1150's story (D-14).**
8. **A third German doc names the button**: `docs/de/product-documentation.md:1687`
   ("Von Hand holt **Historische Kurse nachladen** …"), beyond the two the
   triage found. **Fixed in #1150's story (D-14).**
9. **DESIGN.md's "Under 560 px" paragraph of the contribution table is
   stale**: it says "Zufluss x" / "Abfluss x"; the build says "Zufluss in die
   Position x" / "Abfluss aus der Position x" since #1090. **Fixed in
   #1123's story (D-14),** which edits that paragraph.


---

## Board 05 — Accounts and depots

**Board:** `design-language/mockups/ux-design-2026-10-09/05-accounts.html`,
rendered as `05-accounts--1200.png`, `--1024.png`, `--768.png` and
`--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup of
  `portfolio_accounts_live.ex` (`render/1`, `bucket_chips/1`, `chip/1`,
  `liquidity_role_field/1`, `cash_balance_cell/1`, `term_info/1`) and
  `AppShell` (`shell/1` with its sidebar and top bar, `inline_result/1`), with
  the German msgstrs. **Each frame is as wide as the render it sits in** (1200,
  1024, 768 or 390 px), so it is a real viewport: `app.css`'s 900 px sidebar
  rule and the table's 640 px card rules fire as on the device. At 1200 and
  1024 px the frame carries the 220 px sidebar; at 768 and 390 px it is gone.
- **CSS.** "Heute" frames render `app.css` as shipped. The other frames add
  the `<style>` blocks named on their tag. The blocks are split by pick, so a
  variant frame carries only its own rules: `proposal` (what every outcome
  adds: the nowrap rule, #1161, #1160), `proposal-n15-a|b|c`,
  `proposal-n16-a|b|c`. **Silence adopts `proposal` + `proposal-n15-a` +
  `proposal-n16-a`.** Two `shim-*` blocks are board scaffolding only: they
  cancel an `app.css` selector the story rewrites in place (named in each).
- **Renders.** 1200 shows N15 where the table fits, #1161 and #1160; 1024 and
  768 show N15's four frames each; 390 shows N16's four frames.
- **Data.** Two depots with their cash accounts — "Depot Muster" with
  "Test-Cash" (tagged together: the scope bucket "Default" and "Langfristig"),
  "Depot Sparplan" (former name "Depot 2") with "Wertpapierverrechnungskonto"
  (tagged apart: "Sparplan"; "Notgroschen" and "PP Import 2026-10-07") — and
  the lone "Tagesgeld" (former name "Tagesgeld (alt)", no bucket). Balances
  4.230,15, 812,40 and 12.500,00 EUR, last bookings in September and October
  2026. The 27-letter compound is a generic German account name; with it the
  table needs 795 px, the figure the issue reports for its own instance.
  Nothing real.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **N15** | The accounts table between the card and the desktop (#1145) | variants | **A** |
| **N16** | The Buckets ⓘ on the phone card (#1162) | variants | **A** |
| — | #1161 the chip's × on the desktop; #1160 the empty result slot | before/after | — |

### ① N15 — #1145: the accounts table is cut, not scrolled (variants)

**Today.** The table's wrapper is `overflow: visible`
(`.data-table-wrapper:has(.accounts-table)`, `app.css:7246`), on purpose: the
bucket picker is an absolutely placed popover under its + and must leave the
wrapper. Because it cannot scroll, the table is `width: 100%; min-width: 0`
(`:7254`) and is meant to fit. It does not fit between the card layout
(`@media (max-width: 640px)`, `:7713`) and the content width it needs, so it
grows past its wrapper and `.workspace-page { overflow-x: clip }` (`:5302`)
cuts its right edge: the kebab column first, then the bucket cell. The
issue's comment adds two words that break inside the cell at 768 and 1024 px:
the amount (`.cash-balance__amount`, "4.230,15 / EUR") and "Saldo setzen"
(a 60 × 48 button on two lines).

**Variants:**

- **A — recommended: the card follows the table's own width.** The wrapper
  becomes a query container (`container: accounts / inline-size`) and the
  three 640 px blocks of the table — the card (`:7713-7805`), the kebab grid
  (`:9741-9768`) and rule ⑦'s label (`@media (width > 640px)`, `:7384`) —
  move unchanged into `@container accounts (width < 840px)` (rule ⑦ into
  `width >= 840px`). Nothing new is drawn: under the bound the operator sees
  the card the phone already shows, with every kebab at the end of its own
  name line, the role label and both ⓘ in the rows (and N16's label). The
  wrapper stays `overflow: visible`, so the picker still escapes. The Name
  column keeps a floor of 13.5 rem and breaks a longer name inside the cell
  (`overflow-wrap: anywhere`), so no stored name moves the bound.
- **B — the wrapper scrolls.** The reading-table rule (UX-DR15): the wrapper
  takes `overflow-x: auto` and the table scrolls inside its border. The
  bucket picker becomes a `popover` in the top layer, placed under its + by a
  small hook. The head's two ⓘ panels, which open upward over the page head,
  move to the top layer too: `overflow-x: auto` forces `overflow-y: auto`,
  so a panel inside would be cut.
- **C — the table gives up width.** Cell padding 6 px instead of 9, a 168 px
  bucket floor instead of 220, chip names at 10ch instead of 14ch, a narrower
  role select.

**Any variant:** `.cash-balance__amount` and `.cash-balance__action` take
`white-space: nowrap` (the design critic's comment on the issue). "letzte
Buchung …" keeps wrapping under 1200 px, as the 2026-10-07 amendment
specifies.

**Why A:**

- **No width cuts anything.** The table shows where it fits and the card
  everywhere else, measured on the wrapper. Under "Heute" and C there is a
  band at every sidebar state where the table is cut (table below).
- **The sidebar needs no breakpoint of its own.** At the same viewport the
  sidebar moves the table's width by 220 px (open), 72 px (rail) or 0
  (≤ 900 px). A viewport breakpoint is right for one of the three; the
  container query is right for all.
- **Nothing new to build or learn.** The card is shipped and pinned (Sprint
  16 board 01 ④, rule ⑦); A only changes which width selects it. No hook, no
  top layer.
- **Against B:** this is a control surface, not a reading table. Two of its
  five data cells are controls (the role select; the chips with their
  picker), and B pays for the scroll with three top-layer panels and a name
  column that scrolls off-screen when the kebab scrolls in (the table has no
  sticky subject column).
- **Against C:** it buys 80 px (831 → 751 with the nowrap rule) and keeps
  the cut: 21 px past the wrapper at 768 px, and cut with the sidebar open up
  to 1022 px. It also shortens every chip name by four characters at every
  width.

**Strings:** none. A, B and C add or change no string.

**Measured** (in the frames; the board's data):

| | the table needs | fits, sidebar open | at its rail | no sidebar (≤ 900) |
|---|---|---|---|---|
| Heute | 795 px | from 1069 px | from 913 px | 838–900 px |
| + nowrap (any variant) | 831 px | from 1107 px | from 951 px | 875–900 px |
| C | 751 px | from 1023 px | from 901 px | 791–900 px |
| **A** | bound **840** | table from 1116, card below | table from 961, card below | table 885–900, card 641–884 |

- **The bound.** 618 px of columns that do not depend on the data (Währung
  80, Liquiditätsrolle with its ⓘ 155, Saldo 121, Buckets 220, the kebab 42)
  and a Name column of 216 px (13.5 rem) that holds a 27-letter compound on a
  cash row's indented line make 834 px; a seven-digit balance
  ("1.250.000,00 EUR") widens Saldo by 4 px (measured 837.4 px at 834), so
  the bound is 840. Checked at 839 px (card) and 840 px (table fits, every
  name on one line). From 1200 px of viewport the date line's nowrap raises
  the need to 872 px; the container there is at least 920 px.
- **768 px.** Heute: wrapper 731 px, table 795 px, 66 px past the wrapper and
  46 px past the page edge — all five kebabs gone; the amount on 2 lines;
  "Saldo setzen" 60 × 48. A: card layout, five kebabs whole, the amount on
  one line, "Saldo setzen" 95 × 34. B: the wrapper scrolls 101 px, the five
  kebabs out of view until scrolled; the picker 344 × 100 px, whole, over the
  scroller. C: table 750 px, 21 px past the wrapper.
- **1024 px (sidebar open).** Heute: wrapper 755 px, table 795 px, 42 px past
  the wrapper, all five kebabs cut. A: the card. B: scrolls 77 px. C: fits
  (753 px).
- **1200 px.** Heute fits (922 in 924 px); every variant draws the same table.

**CSS.** `proposal-n15-a` on the board: the container declaration, the Name
column's floor and `overflow-wrap`, and the three 640 px blocks rewritten as
`@container accounts`. `proposal` carries the nowrap rule. (`shim-n15-a` is
the board's stand-in for deleting the old `@media (width > 640px)` rule.)

**What the story writes into DESIGN.md** (Amendment 2026-10-07 → Accounts &
depots, and the front matter's `bucket-cell`): the accounts table becomes the
card wherever its wrapper is narrower than 840 px (a container query, not a
viewport breakpoint), with the bound's derivation; the Name column's 13.5 rem
floor; the amount and "Saldo setzen" never wrap. The rule ⑦ sentence
"visually hidden only above 640 px" becomes "only where the table shows its
head".

### ② N16 — #1162: the Buckets ⓘ on the phone card (variants)

**Today.** Under 640 px the head row is hidden, so the card never shows the
word "Buckets". The row copy of its ⓘ (`term_info(:buckets, phone)` inside
`.bucket-chip-group__scope`, `portfolio_accounts_live.ex:847-851`, placed by
board 08 of Sprint 19) stands after the scope sentence "Gilt für das
Verrechnungskonto" and explains a word the reader cannot see. The role's ⓘ
had the same defect until rule ⑦ (#1085) gave its select a visible label.

**Variants:**

- **A — recommended: "Buckets ⓘ" opens the bucket cell.** A
  `.bucket-chip-group__label` span, first in the chip group, holds the word
  and the ⓘ that today trails the scope line; the scope line keeps its
  sentence only. 11 px, weight 600, `{colors.text-muted}`: the role label's
  voice. Shown only where the head is hidden (the 640 px block, or N15 A's
  container query), `display: none` above, where the head says it once.
- **B — "Buckets ·" before the scope line.** The scope line reads "Buckets ·
  Gilt für das Verrechnungskonto ⓘ" on the card.
- **C — no ⓘ on the card's bucket cell.** The row copy is not rendered; the
  role's ⓘ stays.

**Why A:**

- **It is rule ⑦ applied to the second term.** A term and its ⓘ stand
  together, and the card names each cell the head names on the desktop.
- **No new string.** The label is msgid "Buckets", the head's own; the ⓘ is
  the existing phone copy, moved.
- **Against B:** the scope line then carries two things, a name and a
  sentence, and the ⓘ still trails the sentence: measured 181 px after the
  word.
- **Against C:** it removes the only definition the phone has. #1090 added
  the ⓘ because a newcomer misread the word; it also appears on Views and in
  the import's tag field.

**Strings:** none new. The label reuses msgid "Buckets" ("Buckets"); the ⓘ
keeps "About buckets" / "Zu den Buckets" and its sentence.

**Measured** at 390 px, on "Wertpapierverrechnungskonto":

| | the word "Buckets" | its ⓘ | bucket cell |
|---|---|---|---|
| Heute | nowhere on the card | x 207, 49 px down the cell, after the scope sentence | 296 × 69 px |
| **A** | x 26–69, on the chips' line | 10 px after the word, on its line | 296 × 78 px |
| B | x 26–83, on the scope line | 181 px after the word, at the sentence's end | 296 × 53 px |
| C | nowhere | none | 296 × 50 px |

**CSS.** `proposal-n16-a`: the label's rule, hidden by default and shown in
the card band (both the 640 px block and N15 A's container query are drawn).

**What the story writes into DESIGN.md** (the front matter's
`bucket-cell.role`, and rule ⑦ in Amendment 2026-10-07 → Accounts & depots):
the card names the bucket cell "Buckets" with its ⓘ beside the word, in the
role label's voice, wherever the head is hidden; the sentence "The Buckets ⓘ
keeps its place after the scope line, as board 08 draws it" is replaced.

### ③ #1161 — a bucket chip's × on the desktop (before/after)

**Today.** With a fine pointer the × (`.bucket-chip__remove`,
`app.css:7470-7485`) has no `min-height: 0`, so it takes the base button's
34 px floor (`app.css:1233`): measured 12.5 × 34 px, and every chip holding
one is 40 px tall, where a chip without one is 23.9 px.

**After.** The × is the 22 × 22 that rule ⑧ declares for the + (`width`,
`height`, `min-height: 0`, `padding: 0`), with the pill's end as its corners
(`border-radius: 0 999px 999px 0`), outside `pointer: coarse` too; the coarse
block (`:7686-7700`, 44 × 44) still wins on touch. The chip holding it gives
up its block and right padding, as the coarse rule already does, so the ×
fills the chip's end. **Found while drawing:** the 22 × 22 alone makes the
chip 28 px tall (22 + its 2 px padding twice + the border), still taller than
its neighbours; with the padding given up it is 24 px.

**The spec it applies:** DESIGN.md → Amendment 2026-10-07 → Accounts &
depots, rule ⑧, and the front matter's `bucket-cell.target-size` ("On the
desktop the + is the 22px circle it declares"). The inset focus ring (the PR
γ closing act) already fits the shape.

**Strings:** none.

**Measured** at 1200 px: the × 12.5 × 34 → 22 × 22 px; the chip holding it
88.5 × 40 → 90.1 × 24 px (a chip without one: 23.9 px); the + 22 × 22 px
unchanged; the "Depot Sparplan" band 79 → 63 px tall.

**What the story writes into DESIGN.md:** `bucket-cell.target-size` adds "and
the × is the same 22 px, at the pill's end, in a chip that gives up its block
and right padding, so a chip holding one is no taller than one without".

### ④ #1160 — Accounts' empty result slot (before/after)

*In the decisions' board list (board 05, "#1160 inline result slot"); not in
this board's assignment. Drawn here so the story has its board.*

**Today.** `AppShell.inline_result/1` renders two live regions that always
hold template whitespace, so `.inline-result__region:not(:empty)`
(`app.css:6712`) gives each its 8 px margin at rest. `#accounts-result` is a
child of the section's grid, which adds its 16 px gap for it. Sprint 19's
`.inline-result--page` fixed four page slots (`:879-907`) and left Accounts'
own, Snapshots, Securities and the quotes release.

**After.** The component's rule asks for a result, not for an empty node:
`.inline-result__region:has(> *) { margin: 8px 0 }` replaces `:not(:empty)`,
and the page slot's out-of-flow rule widens from `.inline-result--page` to
every inline result that is a section's grid child
(`.workspace-section > .inline-result:not(:has(.inline-result__region > *))
{ position: absolute }`), so an empty slot is still a live region and takes
no row. A result lands exactly as today.

**The spec it applies:** DESIGN.md → Amendment 2026-10-07 → "A page's result
is an inline result" ("nothing at rest"), whose last sentence ("The other
inline results … keep their footprint") this removes.

**Strings:** none.

**Measured** at 1200 px: the slot at rest 8 → 0 px, out of the flow; section
head → table 52 → 28 px.

**What the story writes into DESIGN.md:** in the page-slot amendment, "every
inline result is empty at rest" replaces the sentence that excepts Accounts,
Snapshots and Securities, and `{components.inline-result}` states the
`:has(> *)` rule.

### Spec

- **UX rules:** UX-DR15 (every wide block owns its scroller; here the card is
  the answer, because the table is a control surface), UX-DR6 (targets),
  UX-DR27 (the phone card).
- **DESIGN.md:** Amendment 2026-09-26 → Accounts & depots: lifecycle controls
  (the card's kebab grid); Amendment 2026-10-07 → Copy and dialog states ④
  (the two ⓘ and their phone copies); Amendment 2026-10-07 → Accounts &
  depots, rules ⑦ and ⑧; → A page's result is an inline result.
- **Boards:** Sprint 19 `ux-design-2026-10-04/07-floor` (rules ⑦, ⑧) and
  `08-copy-dialogs` ④.

### Found while drawing

1. **The Name column needs a floor under A.** `overflow-wrap: anywhere` alone
   lets the table's automatic layout squeeze a long name: drawn at 1200 px it
   broke "Wertpapierverrechnungskonto" over three lines. With a 13.5 rem
   floor on the head cell the name holds its line and the bound stops
   depending on any name. **Fixed in the story (D-14),** in
   `proposal-n15-a`.
2. **#1161's 22 × 22 alone leaves the chip 28 px tall** (measured), against
   23.9 px for a chip without a ×. The chip gives up its block and right
   padding outside a coarse pointer too. **Fixed in the story (D-14),** in
   `proposal`.
3. **B needs three panels in the top layer, not one.** Scrolling the wrapper
   also clips the head's two ⓘ panels, which open upward over the page head.
   Stated in B; no action unless B is picked.
4. **#1160 changes three more slots at rest** (Snapshots, Securities, the
   quotes release); the board draws Accounts'. Same rule, same picture
   (nothing at rest). **Fixed in the story (D-14):** its test measures each
   slot's rest footprint.
5. **"Saldo setzen" sits under the balance up to about 1500 px.** The
   Saldo column is 174 px wide at 1200 px and 237 px at 1440 px (measured,
   with the nowrap rule), so the button wraps below the amount; it stands
   beside it from 1600 px (277 px). `app.css`'s comment on
   `.cash-balance` (#670) says "with the set-balance action beside it".
   Putting it beside costs some 100 px of table width and would move N15's
   bound. **Filed at the merge:** "Accounts: 'Saldo setzen' sits under the
   balance below ~1500 px, where #670 put it beside" (needs a choice).


---

## Board 06 — the classification screen

**Board:** `design-language/mockups/ux-design-2026-10-09/06-classifications.html`,
rendered as `06-classifications--1200.png`, `--600.png` and `--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup of
  `classifications_live.ex` (`render/1` for `:show`, `category_node/1`,
  `security_row/1`, `soll_editor/1`), `ViewSwitcher` and `AppShell`
  (`shell/1`, `inline_result/1`, `data_note/1`), with the German msgstrs.
  **Each frame is as wide as the render it sits in** (1200, 600 or 390 px), a
  real viewport: `app.css`'s 900 px sidebar rule and the tree's 560 px blocks
  fire as on the device. The search, the toggle and "Neue Kategorie" are
  stubbed as unchanged.
- **CSS.** "Heute" frames render `app.css` as shipped; the other frames add
  the `<style>` blocks named on their tag: `proposal` (#1158; #1187 needs no
  rule), `proposal-n17-a|b|c`, `proposal-n18-a|b`. **Silence adopts
  `proposal` + `proposal-n17-a` + `proposal-n18-a`.**
- **Renders.** 1200 shows N18, the N17 measurement table, #1158 above 560 px
  and #1187; 600 shows N17's four frames; 390 shows N18 A, #1158 and #1187.
- **Data.** The custom tree "Regionen": Europa (Deutschland, Frankreich),
  Amerika (Kanada), Asien (empty) and USA at the top level; securities
  "Wrenfield Gardens AG", "Example Holdings International SE", "Larkspur Rail
  AG", "Belcourt Énergie SA", "Maison Ardenne SA" (no ticker), "Halvorsen
  Northern Rail Inc." (CAD), "Arbolia Inc." and "Fennwick Labs Inc." (USD);
  views "Alles", "Langfrist", "Sparplan"; plan versions "Plan 2026" (active),
  "Plan 2025" (archived) and a draft. Figures invented. Nothing real.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **N17** | The tree between 561 and 720 px (#1165) | variants | **A** |
| **N18** | Moving a category under another parent (#1211) | variants | **A** |
| — | #1158 security rows at 390 px; #1187 an archived plan version | before/after | — |

### ① N17 — #1165: the tree between 561 and 720 px (variants)

**Today.** Above 560 px every category row is one grid line
(`.cat-summary`, `app.css:9021`): 0.7 + 4.5 + 7 + 7 + 7 + 3.6 rem of fixed
columns and six 0.45 rem gaps, about 520 px; the name gets what is left, and
each level of nesting takes another indent from it. At 600 px that is 33 px at
the top level and 4 px one level down ("Eu…", "D"); the head's "Kategorie"
(`.tree-head`, `minmax(0, 1fr)`) is wider than its cell and is drawn 30 px
into "Positionen". Under 560 px the tree already lies on two lines and drops
"Positionen" and "Einstand" (`:9137`, `:9159`; issue 873, G8 = A).

**Variants:**

- **A — recommended: the phone rows up to 720 px.** The two 560 px blocks of
  the tree become 720 px blocks, unchanged: the marker, swatch, name (which
  may wrap) and the actions on the first line, "Wert" and "Ergebnis" on the
  second, under their heads; "Positionen" and "Einstand" stay in the cells'
  titles and on wider screens.
- **B — a middle band.** From 561 to 720 px the row stays one line and drops
  "Positionen" and "Einstand"; the name takes their 11.5 rem.
- **C — a floor and a scroller.** The head and the tree get one wrapper
  (`.tree-scroller`, new markup) that scrolls sideways from 561 to 720 px,
  with the tree at a 40 rem minimum, so the name column keeps about 105 px.

**Why A:**

- **It is built and read already.** The two-line row is pinned (issue 873)
  and every phone shows it; A moves one number.
- **Against B:** it is a third layout of the same tree (desktop, middle band,
  phone) for a 160 px band, dropping the same two figures as the phone but
  keeping the desktop's one line. Its name column is fine (232 px at 600).
- **Against C:** a category's result needs a sideways scroll, beside a
  drag-and-drop surface that scrolls vertically, and the level-2 name is
  still cut (76 px for "Deutschland"); it is the only variant with new
  markup.

**Strings:** none.

**Measured** — the name column (swatch and name) at level 1 / level 2, px; ²
two lines (the name has the row's width); * sidebar open:

| viewport | 560 | 600 | 640 | 700 | 720 | 721 | 800 | 901* | 940* | 960* | 1024* | 1200* |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Heute | 446 / 417 ² | 33 / 4 | 73 / 44 | 132 / 103 | 151 / 122 | 152 / 123 | 227 / 198 | 103 / 74 | 140 / 111 | 159 / 130 | 220 / 191 | 389 / 360 |
| **A** | 446 / 417 ² | 486 / 457 ² | 526 / 497 ² | 584 / 555 ² | 604 / 574 ² | 152 / 123 | 227 / 198 | 103 / 74 | 140 / 111 | 159 / 130 | 220 / 191 | 389 / 360 |
| B | 446 / 417 ² | 232 / 203 | 272 / 243 | 330 / 301 | 349 / 320 | 152 / 123 | … | | | | | |
| C | 446 / 417 ² | 105 / 76 | 105 / 76 | 118 / 89 | 137 / 108 | 152 / 123 | … | | | | | |
| the tree's width | 528 | 568 | 608 | 666 | 685 | 686 | 762 | 638 | 675 | 694 | 755 | 924 |

At 600 px: Heute's head runs 30 px into "Positionen"; under A "Kategorie"
ends 217 px before "Wert" and a row is 65 px (two lines) instead of 34; under C
the scroller is 566 px wide and scrolls 86 px. At 721 px (the first width A
leaves on one line) the name is 152 / 123 px.

**CSS.** `proposal-n17-a` repeats the two blocks at `max-width: 720px`; in
the story the two `560px` become `720px`.

**What the story writes into DESIGN.md** (Classification tree rows — columns,
C8-A, its "Under 560 px the row lies on two lines" sentence): the two-line row
holds up to 720 px, with the measured reason (the name column is 33 / 4 px at
600 px on one line).

### ② N18 — #1211: moving a category under another parent (variants)

**Today.** "✎" opens the edit form inside the category's body: name,
description, colour, "Speichern", "Abbrechen" (`category_node/1`,
`classifications_live.ex:1101-1122`). The parent select exists only in "Neue
Kategorie" (`:390`). The context already takes a parent on update
(`Classifications.update_category/3` → `validate_parent/1`): it refuses the
category itself or a descendant ("would make the category its own ancestor")
and a subtree past level 32 (#940), and `handle_event("update_category")`
passes the form's params through (`:1529-1532`). Moving "USA" under
"Amerika" takes the API, or a delete and re-create that loses its
assignments.

**Variants:**

- **A — recommended: "Übergeordnet" in the edit form.** A select labelled
  "Übergeordnet" (in `.recolor-label`, the built-in tree's colour label)
  after the description, with "— Oberste Ebene —" and every category,
  indented as in "Neue Kategorie" (`indent/1`), the current parent selected.
  The category itself and its descendants are left out, so the cycle cannot
  be picked; a parent that would push the subtree past level 32 is listed
  and refused on save. After the save the moved category's new parent chain
  renders open, so the row stays in view where it landed, and the slot says
  where. The description's basis drops from 14 to 10 rem when the select is
  there, so the form keeps one line at 1200 px.
- **B — "Verschieben nach…" as a row action.** A third icon (↳) beside ✎
  and ×, opening a dialog "„USA“ verschieben" with the tree as a radio list
  and "Verschieben". The actions column grows from 3.6 to 5.4 rem on every
  row.
- **C — drag a category onto another.** The category's summary becomes a
  drag source; dropping it on a category's node re-homes it (the drop zone's
  `.is-dropping` tint exists for securities).

**Why A:**

- **A move changes one attribute,** and the edit form is where the others
  change; the API and MCP move a category the same way (`parent_id` on the
  update).
- **Nothing new to learn:** the "Neue Kategorie" select with its label,
  "— Oberste Ebene —" and indent; the page's result slot answers, as every
  write here does.
- **Against B:** a fourth way to act on a row (✎, ×, the disclosure, ↳), a
  wider actions column on every row at every width (measured 58 → 86 px,
  28 px off every name), and a dialog for one choice.
- **Against C:** no keyboard path (it would need A or B anyway); HTML5 drag
  does not start on touch; the dragged element is the disclosure's own
  summary; and the drop zones already take securities — one gesture, two
  meanings.

**Strings** (A; the select's label and first option exist):

| | English (msgid) | German |
|---|---|---|
| Select label (exists) | Parent | Übergeordnet |
| First option (exists) | — Top level — | — Oberste Ebene — |
| Moved (new) | “%{name}” now sits under “%{parent}”. | „%{name}“ liegt jetzt unter „%{parent}“. |
| Moved to the top (new) | “%{name}” now sits on the top level. | „%{name}“ liegt jetzt auf der obersten Ebene. |
| Refused past level 32 (new) | Not moved: under “%{parent}” a category would sit on level %{level} — a classification has at most %{max} levels. Under “Parent”, pick a category higher up. | Nicht verschoben: Unter „%{parent}“ käme eine Kategorie auf Ebene %{level} — eine Klassifizierung hat höchstens %{max} Ebenen. Bei „Übergeordnet“ eine Kategorie weiter oben wählen. |

An edit that does not change the parent keeps "Kategorie aktualisiert". A
cycle that a concurrent edit makes possible keeps the changeset's "Übergeordnete
Kategorie würde die Kategorie zu ihrer eigenen Oberkategorie machen". Stored
names sit in `<bdi>` (H8.8). `%{level}` is the deepest level the moved
subtree would reach, the changeset's own value. *B, if picked:* "Move to…" /
"Verschieben nach…", "Move “%{name}”" / "„%{name}“ verschieben", "Pick the
parent category. The assignments and sub-categories of “%{name}” move with
it." / "Übergeordnete Kategorie wählen. Die Zuordnungen und Unterkategorien
von „%{name}“ ziehen mit.", "Move" / "Verschieben".

**Measured:** at 1200 px the edit form is 895 × 44 px with the select (one
line; the label and select 260 px, the select 165 px); at 390 px it is
329 × 162 px (123 without the select). Under B the dialog is 440 × 470 px and
the top-level name column 389 → 361 px.

**CSS.** `proposal-n18-a`: the select's width inside `.recolor-label`, and the
description's 10 rem basis when the form holds the select.

**What the story writes into DESIGN.md** (the classification screen, beside
the 2026-10-08 depth amendment, whose "A move has no control on this screen"
it replaces): the edit form's "Übergeordnet" select, what it leaves out, the
two success sentences, the refusal, and that the new parent chain opens.

### ③ #1158 — security rows at 390 px (before/after)

**Today.** A security row (`li.dnd-row`, `security_row/1`) is a nowrap flex
line: name, ticker, currency, quantity, value; the last two have no rule of
their own (`app.css:4820-4853`, `:5313-5319`). At 390 px the rows run to
x 467 inside a category body that ends at x 359 — 77 px past the screen,
which `.workspace-page { overflow-x: clip }` cuts: no value in view.

**After.** Under 560 px the row is a two-track grid, the Wealth Positions
row's shape: the name (600, wrapping) over "TICKER · CCY", the value (600)
over the quantity with its unit word ("120,00 Stück", 12 px muted) on the
right. No markup moves except a phone-only unit span: the li stays the drag
source with `draggable` and `data-drag-security`, and the hook finds rows by
`closest("[data-drag-security]")` (`layout_view.ex:1650`). On a phone the
move is the select toolbar's "In Kategorie verschieben", as today. Above
560 px the row is unchanged. The list's `flex-wrap` becomes `nowrap` at every
width (found while drawing, 1).

**The spec it applies:** DESIGN.md → Phone lists — two-line rows (UX-DR27),
"Wealth's Positions" (Sprint 19 board `06-phone-wealth`, rule ①).

**Strings:** none new: the unit word is msgid "units" ("Stück"), shown under
560 px only.

**Measured** at 390 px: rows end at x 467 → 359 (inside); values in view 0 →
3 of 3; rows 29 / 30 / 30 → 47 / 67 / 48 px ("Example Holdings International
SE" wraps to two lines); every row still `draggable`. At 600 and 1200 px the
rows are unchanged (29–30 px).

**What the story writes into DESIGN.md** (Phone lists — two-line rows, a new
"Classification rows" entry): the composition, the unit word, and that the
rows stay the drag source.

### ④ #1187 — an archived plan version in the SOLL editor (before/after)

**Today.** Picking an archived version in "Plan-Version:" loads it with
every weight editable and "Plan speichern" live; `save_soll_plan/2` sends
`plan: <id>` and `Targets.edit_plan/5` writes it (`targets.ex:448-462`, no
status check). Since #1133 the API and MCP refuse that write
(`target_controller.ex:270`, "is archived: activate it, or duplicate it into
a draft"). The version hint reads "Archiviert — die Vermögensseite folgt dem
aktiven Plan; aktiviere ihn, um ihn wiederzuverwenden." (`version_hint/1`,
`:2917`): it neither says the version is read-only nor names the copy, and it
addresses the reader as "du" (found while drawing, 3).

**After.**

- **The version bar** keeps the picker and "Umbenennen" (they act on the
  version, not its targets). "Plan duplizieren" and "Diesen Plan aktivieren"
  leave the bar for an archived version: they become the note's remedies.
- **A `note` data note** under the bar (`data-role="soll-archived-note"`):
  the sentence, then two `.link-button` remedies, "Aktivieren" · "Als Entwurf
  duplizieren" (H6.1: the remedy inside the note). They fire the existing
  `activate_soll_plan` and `duplicate_soll_plan`.
- **The weights are `disabled`,** as the cash target already is for a
  version; "Plan speichern" and "Aus anderer Ansicht übernehmen…" are not
  rendered (a copy-in fills inputs nothing can save); "Plan löschen" stays,
  since deleting a version is not a write into it.
- **The context refuses too:** `Targets.edit_plan/5` returns
  `{:error, :plan_archived}` for an archived plan, so the screen and the
  controller read one rule. A form loaded while the version was active and
  saved after another tab archived it gets a problem note in the page's
  result slot, brought into view and focused as every plan refusal is
  (#945), and the editor reloads as archived.

**The spec it applies:** ADR-0027 §3 and its note of 2026-10-08 ("An archived
plan … steers nothing, and is reused by activating it or duplicating it into
a draft"); UX-DR17 with the remedy inside the note (H6.1); DESIGN.md → Plan
refusals name their row (#945) for the refusal's path.

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Note (new; replaces "Archived — the Wealth page follows the active plan; activate to reuse it.") | Archived — this version steers nothing and is read-only; the Wealth page follows the active plan. To change it, activate it or duplicate it as a draft. | Archiviert — diese Version steuert nichts und ist nur lesbar; die Vermögensseite folgt dem aktiven Plan. Zum Ändern aktivieren oder als Entwurf duplizieren. |
| Remedy (new) | Activate | Aktivieren |
| Remedy (new) | Duplicate as draft | Als Entwurf duplizieren |
| Refusal (new) | Not saved: “%{name}” is archived and steers nothing. Activate it or duplicate it as a draft, then edit. | Nicht gespeichert: „%{name}“ ist archiviert und steuert nichts. Aktivieren oder als Entwurf duplizieren, dann ändern. |

**The verb.** The board says "duplizieren", not the brief's "kopieren": the
bar's button is "Plan duplizieren", the success note "Plan als Entwurf
dupliziert", the API's refusal "duplicate it into a draft" and the MCP tool
`portfolixir.plans.duplicate`. **To flip by comment:** "#1187 kopieren" makes
the remedy "Als Entwurf kopieren" / "Copy as draft" (and the note's verb
with it).

**Measured:** editable target inputs 7 of 8 → 0 of 8 (the eighth, cash, is
disabled today already); "Plan speichern" present → absent; the note 924 ×
54 px at 1200 px and 358 × 108 px at 390 px.

**What the story writes into DESIGN.md** (Amendment 2026-09-24 → Position
targets in the plan editor, or a new "Plan versions in the editor" part): an
archived version is read-only, its note and remedies, what the bar keeps, and
that the context refuses the write.

### Spec

- **ADRs:** ADR-0027 §3 and its note of 2026-10-08 (#1187); ADR-0041 (the
  category result the move recomputes, #1110).
- **UX rules:** UX-DR15, UX-DR17, UX-DR27; H6.1 (the remedy inside a note).
- **DESIGN.md:** Classification tree rows — columns (C8-A, issue 873's two
  lines); Amendment 2026-10-08 → A category below level 32 is refused; Plan
  refusals name their row (#945); Phone lists — two-line rows.
- **Boards:** Sprint 16 `ux-design-2026-09-24/08-classification-detail`
  (G8 = A); Sprint 19 `ux-design-2026-10-04/06-phone-wealth` (rule ①) and
  `10-category-results`; Sprint 20 `ux-design-2026-10-07/02-money-findings`
  (#940).

### Found while drawing

1. **#1158's cause is the list's `flex-wrap`.** `ul.cat-securities` is a
   column flexbox that keeps the base rule's `flex-wrap: wrap`
   (`app.css:4647`), and a wrapping flex line is as wide as its widest item's
   max-content, so every row took the width of its whole line. Measured:
   `flex-wrap: nowrap` alone brings the rows from x 467 back to x 359. The
   board's `proposal` carries it at every width beside the grid. **Fixed in
   the story (D-14).**
2. **The sidebar band of N17.** The tree's breakpoints are the viewport's.
   With the sidebar open, 901 to about 950 px give the tree less room than
   721 px without it (638 px of tree at 901 against 686 at 721; name column
   103 / 74 px). A written as a container query on the page at the tree width
   720 px leaves (686 px; and the existing 560 px block at 528 px) covers that
   band too, the N15 A pattern. **Fixed in the story (D-14):** the same rules,
   selected by the tree's width.
3. **A "du" imperative the invariant misses.** The archived hint's German
   "aktiviere ihn" addresses the reader; `test/invariants/microcopy_voice_test.exs`
   lists the verbs it rejects and "aktiviere" is not among them. A search of the
   German catalogs for 23 imperatives the list lacks found only this one. **Fixed in
   the story (D-14):** #1187 replaces the string, and the story adds
   "aktiviere" to `@du_imperative_de`.
4. **The view switcher's German label is "Aktive Filter".** Its group and
   nav carry `aria-label={gettext("Active view")}` (`view_switcher.ex:42`,
   `:46`), translated "Aktive Filter" (`default.po:2555`): a screen reader on
   this screen and on Wealth hears the wrong word. **Fixed in the story that
   touches the surface (D-14):** one msgstr, "Aktive Ansicht".
5. **A duplicated plan is named "… (copy)" in English.**
   `Targets.duplicate_plan/3` names the copy `source.name <> " (copy)"`
   (`portfolios/targets.ex:841`), a stored name on a German screen and in the API. The
   #1187 remedy creates such copies. **Filed at the merge:** "A duplicated
   plan version is named '… (copy)' in English" (needs a choice: a stored name
   has no locale).
6. **After a move the category can vanish from view.** Categories render
   closed unless the tree is filtered, so "USA" moved under a closed
   "Amerika" would leave the screen. A opens the new parent chain and the
   slot names the place. **Fixed in the story (D-14),** part of A.


---

## Board 07 — the Imports page: the preview, the correction and the done page

**Board:** `design-language/mockups/ux-design-2026-10-09/07-imports.html`,
rendered as `07-imports--1200.png` and `07-imports--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup of
  `imports_live.ex` (`render_preview/1`, `correction_dialog/1`,
  `render_done/1`), `risk_live.ex` (the own-rules head), `tax_live.ex` (the
  statement form's actions) and `AppShell` (`data_note`, `inline_result`,
  `area_tabs`), with the German msgstrs of `default.po`. A desktop frame is
  980 px (1200 − the 220 px sidebar); a phone frame is a real 390 px
  viewport, so `app.css`'s 720 and 560 px blocks fire. The dialogs are drawn
  in a 520 px stage, as board 03 of 2026-10-07 did.
- **CSS.** "Heute" frames render `app.css` as shipped; "Nachher" and variant
  frames add `<style id="proposal">` (and `#proposal-n21b` / `#proposal-n20b`
  for those variants only).
- **Data.** Test-Cash, Tagesgeld (Plus/Extra), Depot Muster; Wrenfield
  Gardens AG, Larkspur Rail AG, Fennwick Labs AG, Kestrel Point AG,
  Halvorsen Mills AG (`DE000000000H`), Brightwater Utilities SE
  (`DE000000000B`); invented figures, 2026 dates.
- **Every size below was measured** inside its frame with Playwright
  (`getBoundingClientRect`, `scrollWidth`/`clientWidth`) unless marked as an
  estimate. No frame scrolls horizontally at 980 or 390 px (document
  `scrollWidth − clientWidth` = 0 in every frame).

### ① N21 — the correction section's line states (#1193, #1194, #1205; ADR-0053 amendment of 2026-10-09) — variants

**Today.** `Imports.cash_corrections/2` → `Correction.detect/3` lists a
booking only on a content-hash hit whose stored cash differs
(`correction.ex:121-133`); `changes/3` compares cash only. A row A5 refuses
is not an entry: `Correction.stored_refusals/2` only swaps its parser
warning for "— bereits importiert und hier nicht zu korrigieren. Den Verkauf
nicht noch einmal buchen; siehe „Eine negative Steuer in einer Zeile“ in der
Produktdokumentation." The journal is not read. On the board's JSON re-drop
the section lists three lines (Zeile 4, 9, 21; "Zusammen -3,81 EUR"), and
one confirm (1) rewrites Eintrag 9's hand edit 8,00 → 7,80, (2) leaves
Larkspur's drifted sale (15) 20,00 too high and unlisted, (3) leaves
Wrenfield's hand-fixed sale (12) at the old price 12,50, (4) leaves
Fennwick's refused sale (7) as a warning only, Test-Cash 25,00 too high,
(5) says nothing about Kestrel's twin dividend (18).

**Variants:**

- **A — recommended.** All seven lines in the one table, in file order. Each
  line's state is a line under its booking (`.import-correction__state`, the
  legs' basis voice): a line found by its figures (15) says so muted and
  keeps its confirm (exactly one stored booking matches and no other row
  claims it); a line the confirm leaves leads with its reason in bold, then
  "— bleibt, wie es ist", then what to do, and its „Korrigiert“ cell reads
  **bleibt**. The confirm („3 Buchungen korrigieren…“), the total and the
  dialog count only the three lines it changes; the sentence splits so the
  board-03 cause sentence covers only those three. A JSON trade listed on its
  price alone (12) keeps the shipped „Kurs gebucht / Kurs laut Datei“
  detail lines.
- **B.** The table keeps only the three lines the confirm changes (exactly
  as shipped); the four others go to a prose list „Nicht automatisch
  korrigierbar“ after the button, each "Eintrag N · date · kind · names:
  gebucht X, laut Datei Y. Reason."
- **A + „Kurs“ column (as briefed; not recommended).** Drawn and measured:
  see below.

**Why A.** One finding, one list in the file's order: the operator who
checks the file against the screen finds every listed booking where its
entry is, and the sentence's count and the table agree. The state is read
where the figures are, and „bleibt“ answers the „Korrigiert“ column in words,
not colour. B splits one finding into two lists with two anatomies (three
on the phone), puts the lines that need the operator's hand after the act
that ignores them, and turns their figures into prose. B's merit: no word
inside a figure column.

**Why no „Kurs“ column.** Measured at 980 px: the figure columns already sit
at their min-content (70 · 85 · … · 76 · 89 · 82 px), so the column's 105 px
come out of the booking column (360 → 254 px) and the refused line's reason
grows from 6 to 9 lines (108 → 162 px; table 636 → 722 px). The only line it
helps is a price-only one, and a price-only difference arises only from a
hand edit of a JSON trade's cash (A2 derives the price from the cash), which
is a kept line whose state already names the price. Flips by comment:
„N21 Kurs-Spalte".

**Spec it applies.** ADR-0053 §6, A5, A6 and the 2026-10-09 amendment
(#1193 (a), #1194 (a), #1205 (a) + twin rule); DESIGN.md, Amendment
2026-10-08 — "Import preview: bookings already imported with a different
amount"; UX-DR17 rule 3 (the remedy inside the note); UX-DR2 (a kept line is
a finding, not an all-clear).

**Strings** (new unless marked; the cause sentence is board 03's, unchanged):

| | English (msgid) | German (msgstr) |
|---|---|---|
| Sentence, split (A and B; plural forms by `%{count}`) | %{count} bookings already imported differ from this file. The step below corrects %{fixable} of them: [board-03 cause sentence] %{kept} stay as they are; each line says why. | 7 bereits importierte Buchungen weichen von dieser Datei ab. 3 davon korrigiert der Schritt unten: [Ursachensatz] 4 bleiben, wie sie sind; jede Zeile nennt den Grund. |
| B's last sentence | %{kept} more cannot be corrected automatically (below). | 4 weitere sind nicht automatisch zu korrigieren (unten). |
| Only kept lines (A) | One booking already imported differs from this file and stays as it is; its line says why. / %{count} … differ … and stay as they are; each line says why. | Eine bereits importierte Buchung weicht von dieser Datei ab und bleibt, wie sie ist; die Zeile nennt den Grund. |
| „Korrigiert“ cell of a kept line | kept | bleibt |
| State — refused (#1193), sale | **Not corrected automatically** — stays as it is: once the tax refund of %{refund} is split off, %{rest} would remain for the sale per the file, and a sale books more than zero. Put it right by hand in the history: change the sale to %{gross} without fees, enter the fees of %{fees} as a booking of their own; the tax refund is already booked. | **Nicht automatisch korrigierbar** — bleibt, wie es ist: Nach der Steuererstattung 25,00 blieben dem Verkauf laut Datei -4,90, und ein Verkauf bucht mehr als 0. In der Historie von Hand richtigstellen: den Verkauf auf 0,10 ohne Gebühren ändern, die Gebühren 5,00 als eigene Buchung erfassen; die Steuererstattung ist schon gebucht. |
| State — hand-edited (#1194) | **Changed by hand since its import** (%{date}) — stays as it is. Per the file: %{stated}. | **Seit dem Import von Hand geändert** (14.09.2026) — bleibt, wie es ist. Laut Datei: +7,80. |
| State — hand-edited, price only | **Changed by hand since its import** (%{date}) — stays as it is. The amount agrees with the file; the price does not. | **Seit dem Import von Hand geändert** (20.09.2026) — bleibt, wie es ist. Der Betrag stimmt mit der Datei überein, der Kurs nicht. |
| State — found by figures (#1205), confirmable | Found by its date and figures: Portfolio Performance has written this entry differently since the import. (CSV: "this row") | Über Datum und Beträge gefunden: Portfolio Performance schreibt diesen Eintrag seit dem Import anders. (CSV: „diese Zeile“) |
| State — twin (#1205) | **%{count} stored bookings match** its date and figures — stays as it is. Correct the right one by hand in the history. | **2 gespeicherte Buchungen passen** zu Datum und Beträgen — bleibt, wie es ist. Die richtige von Hand in der Historie korrigieren. |
| Total with kept lines (A) | The %{count} bookings the step corrects, together %{total}: %{accounts}. | Die 3 Buchungen, die der Schritt korrigiert, zusammen -23,61 EUR: Test-Cash -22,41 EUR, Tagesgeld -1,20 EUR. |
| Dialog, extra sentence | The other %{count} lines of the list stay as they are. | Die 4 übrigen Einträge der Liste bleiben, wie sie sind. |
| Parser warning of a stored refused row (replaces "— already imported, and it cannot be corrected here. Do not book …") | … — already imported; listed under “Already imported, with a different amount”. | … — bereits importiert; aufgeführt unter „Bereits importiert, mit anderem Betrag“. |
| B's list head | Not corrected automatically | Nicht automatisch korrigierbar |

"Historie" is a link to `/transactions` (the history has no per-booking
URL; it reads `?since=` only). The refused sentence takes one msgid per kind
pair (sell / booking), as A5's do; `%{gross}` is the cash cell + fees −
refund (+ positive taxes).

**Measured.**

| | 980 px | 390 px |
|---|---|---|
| Today's table | 762 wide, rows 33/33/32 | phone rows 79/80/62 |
| A's table | 762 in a 762 wrapper (no scroll); booking column 360; rows 33/143/71/127/109/89/32 (636 tall); note 879 × 805 | phone rows 79/208/118/176/176/136/62; state lines 298 wide (full row); note 324 × 1384 |
| A + „Kurs" | booking column 254; rows 51/197/89/125/89/107/32 (722 tall) | — |
| B | table rows 33/109/32; kept list 764 × 211 | kept list 298 × 473 |
| Only kept lines | note 879 × 148 | — |
| Dialog (520 stage) | modal 460 × 442 | — |

Without the proposal's floor rule, the table sizes to its max-content inside
its scroller: with the state lines contained it measured 788 px in a 762 px
wrapper (26 px clipped); uncontained, the sentence set the table's width and
pushed every figure column out of view (seen, not measured).

**CSS** (A): `.import-correction__state` (12 px, muted; `--kept` in the text
colour, its lead bold); `td.import-correction__kept` muted; on a phone row
the state is a direct child spanning `grid-column: 1 / -1`;
`.data-table-wrapper > #import-correction-table { min-width: min-content }`.

**What the story writes into DESIGN.md** (Amendment 2026-10-08, the
correction): the four line states and their sentences, „bleibt“ in the
„Korrigiert“ column, the split sentence, the total/button/dialog counting
only the confirmable lines, the section without a confirm when every line
stays, the parser warning's pointer, and the table's min-content floor.

### ② N20 — #1180: the count after the operator's choice — variants

**Today.** `assign_account_states/2` counts once per preview (hash layers at
once, `refine_counts/2`'s dry run under `CappedAsync` with a token);
`handle_event("mapping_changed", …)` (`imports_live.ex:955`) recounts
nothing. After „Tagesgeld" is chosen for „Tagesgeld Extra" the row keeps
„13 Buchungen neu" (`mapping_count/1`), though the apply skips the 12
already booked.

- **A — recommended.** A change starts the dry run again with the operator's
  mapping (new token; a stale answer is dropped). Meanwhile the count dims
  (`.stale-value`) and the cue stands under it: „vor der Wahl gezählt · wird
  neu berechnet". Then „12 Buchungen bereits importiert · **1 neu**"; the
  lead note and the cards follow from the same answer.
- **B.** The count stays; a muted line under it: „vor der Wahl gezählt; was
  unter Tagesgeld schon gebucht ist, überspringt der Import".
- **C.** No count on a changed row.

**Why A.** The count is the row's promise of what the confirm books, and
after a choice it is the one figure that disagrees with the apply — on the
row just decided. The machinery exists; the cue is DESIGN.md's recomputing
cue. Near the risk tier: an equality test pins the recounted row to the
apply's inserted and skipped counts. B leaves the wrong number in bold and
asks for mental subtraction; C hides the one figure that tells a renamed
account (12 booked) from a new one (13 new).

**Strings:** "counted before the choice" / „vor der Wahl gezählt" (cue
basis, A); "recomputing" / „wird neu berechnet" (new msgid in this domain;
the cue's spec word); B: "counted before the choice; what is already booked
under %{account} the import skips" / „vor der Wahl gezählt; was unter
%{account} schon gebucht ist, überspringt der Import".

**Measured:** the count is 349 × 17 today and 349 × 36 with the cue at
980 px; the row stays 209 px (its target column is taller). At 390 px the
count is 295 × 36 and the row 370 px. B's count block is 349 × 50.

**CSS:** `.mapping-count .stale-value b { color: muted }`,
`.mapping-count > .recomputing-cue { margin-top: 2px }` (B:
`.mapping-count__basis`).

**DESIGN.md** (Amendment 2026-09-26, the row's count): a changed row is
recounted under the chosen mapping; while it runs, the count dims and
carries the cue.

### ③ #1188 and the negative FEE unit — before/after

**Today.** `json_parser.ex:180-202` splits a negative TAX unit into a
`tax_refund` companion for every kind; on an `INBOUND_DELIVERY` it names no
cash account, so „Import bestätigen" fails on it and rolls back the whole
file: „Zeile 5.tax_refund.1: Verrechnungskonto darf nicht leer sein"
(`apply_error_message/1`; built from the code, not run). A FEE unit of
−1,90 is folded to its magnitude (`fold_unit/5`, `:401-406`): fees 6,80
instead of 3,00, silently.

**After** (ADR-0053 amendment of 2026-10-09; the 2026-10-06 row-error
anatomy): two row errors in the parser-warnings note, "Warnungen 2",
„Einträge" 24 → 21, the rest previews.

| | English (msgid) | German |
|---|---|---|
| Delivery / security transfer | %{kind} with a tax refund of %{refund}: a %{kind} moves no cash, so the refund would have no account — row not imported. Book the %{kind} by hand without it; if money did move, book that as a tax refund of its own. | Einlieferung mit Steuererstattung 12,40: Eine Einlieferung bewegt kein Geld, die Erstattung hätte kein Konto — Eintrag nicht übernommen. Die Einlieferung ohne sie von Hand buchen; ist Geld geflossen, das als eigene Steuererstattung. |
| Cash transfer | transfer with a tax refund of %{refund}: a transfer moves cash between two accounts, and a refund split off it would land on one side only — row not imported. Book the transfer by hand without it; if money did move, book that as a tax refund of its own. | Umbuchung mit Steuererstattung %{refund}: Eine Umbuchung bewegt Geld zwischen zwei Konten, eine abgespaltene Erstattung landete nur auf einer Seite — Zeile nicht übernommen. Die Umbuchung ohne sie von Hand buchen; ist Geld geflossen, das als eigene Steuererstattung. |
| Negative FEE (sell; "booking" for other kinds) | sell with a negative fee (%{fee}): the import does not book a fee refund yet — row not imported. Book the sale by hand, with its fees less the refund (%{net}). | Verkauf mit einer negativen Gebühr (-1,90): Eine Gebührenerstattung bucht der Import noch nicht — Eintrag nicht übernommen. Den Verkauf von Hand buchen, mit den Gebühren abzüglich der Erstattung (3,00). |

One msgid per kind (`%{kind}` stands for the board's shorthand). **Measured:**
note 933 × 143, rows 818 × 87 (980); note 358 × 273 at 390, where both rows
fit the 12rem scroller (191 of 192 px). **CSS:** none. **DESIGN.md**
(2026-10-06 row-error list): the three reasons and their strings.

### ④ #1195 — before/after

**Today.** The probe (`unseen_names`, `applier.ex:504-530`; LiveView
`:1346-1358`) rests on the hash layers alone. Renamed in both places,
„Tagesgeld Plus" reads, once the dry run answers, „12 Buchungen bereits
importiert · nichts anzulegen" beside „Unter diesem Namen ist noch keine
Buchung importiert…", the lead note says nothing is created, and Confirm
waits (hint „Vor dem Import noch zuzuordnen: Verrechnungskonto: Tagesgeld
Plus") — on every re-drop.

**After** (ADR-0050 amendment of 2026-10-09): (1) while the dry run runs
the row is withheld as today, its count dimmed with the cue „vorläufig ·
wird neu berechnet" (only on a withheld row, the one row that can still
change; under N20 B/C no cue); (2) when the dry run finds every row booked
on the resolution, the name is not unknown: the row gets its prefill, which
with nothing new is #1168's read-only line „Keine Zuordnung nötig: Der
Import bucht unter diesem Namen nichts." (`cash[<key>] = existing:<id>`),
the hint goes, Confirm unlocks, the lead note leads; (3) **a remembered
former name is not counted as seen — by design** (the amendment's point 3):
`former_names` records no author (a rename, a merge and a remembered remap
write the same list), so counting it could prefill the wrong account and book
a history twice (P1). After „Tagesgeld Extra" was remembered for Tagesgeld,
a later export carrying one new booking under it stays withheld — „12
Buchungen bereits importiert · **1 neu**", „Entscheiden…", the note, the hint,
Confirm waits — exactly today's state, until a booking under the name has
been imported and its hash holds it. The board draws it as „Nachher = heute,
gewollt". A re-drop of the same file or a drifted re-export stops asking
once the dry run answers (2).

**Strings:** "provisional" / „vorläufig" (cue basis); the remember
sentence stays as shipped. **Measured:** the row is 150 px withheld and
77 px read-only at 980 (the remembered-name row, withheld, 150 px); lead
note 933 × 36. **CSS:** N20's. **DESIGN.md** (Amendment 2026-09-26, the
unseen-name bullet): the dry-run release, the withheld-until-answered state
with its cue, and that a remembered former name still asks while its export
brings a new booking.

### ⑤ #1130 — before/after

**Today.** `#import-unmatched-config` (`imports_live.ex:662`) wears
`.import-warning-box` (`app.css:4208`): accent text on the accent tint, no
word, no glyph. **After:** `AppShell.data_note` `attention`
(`data-role="unmatched-config"`, id kept): the `<h3>`, the sentence, the
list, each name linking to its security; under 560 px it joins the ONE
wrap selector list (DESIGN.md 2026-10-06). `.import-warning-box` leaves
`app.css`. Strings unchanged. **Measured:** 933 × 147 (980), 358 × 277 with
a 332 px body (390). **CSS:** body stretch/grid, `margin: 16px 0`, the list
in the text colour, the phone wrap. **DESIGN.md:** the 2026-10-06 "Drift
recorded" bullet becomes the note's anatomy.

### ⑥ #1179 — before/after

**Today.** JSON numbers by array position (`json_parser.ex:132`,
`Enum.with_index(1)`) and prints „Zeile N" (`parser_warning_text/1`
`:3387`, and `:356, :776, :826, :851, :876, :901`). **After:** a JSON
preview and done page say „Eintrag" on every row label: parser warnings and
the reason's own ending („— Eintrag nicht übernommen"), the correction
table's first column and phone rows, the dialog („Einträge 4, 15, 21"), the
refusal result, every done-page list, „Eintrag 7 (Steuererstattung)", the
apply error line. CSV keeps „Zeile". **Strings:** "Entry %{row}: %{message}"
/ „Eintrag %{row}: %{message}", "Entry %{row}: %{reason}", "Entry" /
„Eintrag", "Entry %{row}" / „Eintrag %{row}", "Entry %{rows}"/"Entries
%{rows}" / „Eintrag %{rows}"/„Einträge %{rows}", "— entry not imported" /
„— Eintrag nicht übernommen", and the done-page lines' "Entry %{row}: …"
twins. **Measured:** the column header is 70 px („EINTRAG") vs 59 px
(„ZEILE") at 980; no other size changes. **CSS:** none. **DESIGN.md:**
2026-10-06 "A JSON row's number is untouched (its own issue)" becomes the
rule.

### ⑦ #1207 (1) — before/after

**After:** when the correction section shows, the nothing-to-import note
ends „3 bereits importierte Buchungen weichen aber von der Datei ab: unten
unter „Bereits importiert, mit anderem Betrag“ korrigieren." (the heading
an anchor to `#import-correction`); the note stays `note`. With only kept
lines: "…: unten unter „…“ steht, warum." EN: "%{count} bookings already
imported differ from the file, though: correct them under “Already
imported, with a different amount” below." / "…: see why under “…” below."
**Measured:** 933 × 36 → 933 × 54 (980); 358 × 126 (390). **CSS:** none.

### ⑧ #1197 — before/after

**Today.** `correction_consequence/2` (`:2044-2060`) and
`correction_result/1` read no `balance_adjustment`. **After:** per account,
the first set balance on or after its earliest corrected booking is named.

| | English | German |
|---|---|---|
| Dialog, per absorbed account | On %{account}, the set balance of %{date} absorbs the %{amount}: its balance stays as it is. | Bei Tagesgeld nimmt der gesetzte Saldo vom 01.10.2026 die 1,20 EUR auf: Sein Kontostand bleibt, wie er ist. |
| Result, per absorbed account | — the set balance of %{date} holds %{account}'s balance | — den Kontostand von Tagesgeld hält der gesetzte Saldo vom 01.10.2026 |

**Measured:** consequence 428 × 72 → 428 × 90 (520 stage); 326 × 125 at
390. **CSS:** none. **DESIGN.md:** the dialog's and result's sentences.

### ⑨ The done page — #1178, #1207 (2), #1179, #1181; #962 — before/after

- **#1178:** a muted line under the counts, from a created-portfolio field
  of `Applier.Result`: "The import created the portfolio record “%{name}”
  (%{currency}) and booked into it." / „Der Import hat den
  Portfoliodatensatz „Default“ (EUR) angelegt und darin gebucht."
  Measured 505 × 18 (980), 358 × 39 (390).
- **#1207 (2):** first among the lists (after the correction left undone),
  `.import-skipped`, `data-role="refused-rows"`: "One row the preview
  refused was not imported:" / "%{count} rows …" (JSON: "entries") /
  „2 Einträge, die die Vorschau abgelehnt hat, sind nicht importiert:",
  each row's message with its remedy. Measured 736 × 94 (980), 358 × 203
  (390).
- **#962:** beside the former-ISIN line, `.import-skipped`
  (`data-role="former-name-matches"`): "%{count} bookings booked through a
  former name:" / „3 Buchungen über einen früheren Namen gebucht:", items
  "“%{name}”, now %{account} · %{count} bookings" / „„Tagesgeld Extra“,
  jetzt Tagesgeld · 1 Buchung". Measured 736 × 59. The former-ISIN line
  gets a real plural: "One record matched via a former ISIN." / „Ein
  Datensatz über eine frühere ISIN zugeordnet."
- **#1181:** today the `.button-secondary` link is muted text
  (rgb(90,101,119)) whose text sits at the top of its 34 px flex item.
  After: the family's outline secondary — text colour, 1 px border,
  transparent, `a.button-secondary` inline-flex centred, 169 × 34, top-aligned
  with the primary (both at the same y, measured). Risk's „Regel anlegen"
  (a `<button>`: elevated box with muted text, reads disabled) becomes the
  same outline; Tax's „Abbrechen" (`button button-secondary`) keeps
  `.button`'s 13.6 px and only its colour changes. In `app.css`
  `.button-secondary` joins `.button-ghost`'s two selector lists (before
  `.button`), and the Tax-page colour rule (`:8057`) retires; the focus-ring
  list and its invariant test stay. Flips by comment to "retire the class,
  use `.button-ghost`".
- **Frame height (a) at 980:** 430 → 601 px.
- **DESIGN.md:** the done page's order (correction left undone, refused
  rows, matches, skips), the portfolio line, the two new lists; the button
  family: `.button-secondary` is the outline secondary.

### Found while drawing

1. **The correction table sizes to its max-content** (`app.css`
   `.data-table-wrapper > table { min-width: max-content }`), so N21's state
   sentences — and already a long name with its legs line — widen it past
   the note. **Fixed in the story (D-14):** N21's min-content floor rule.
2. **Board 03's cause sentence is false for a kept line** (a hand edit or a
   twin was not "booked as an earlier version of the import read" it).
   **Fixed in the story:** the split sentence.
3. **A refused row's remedy repeats on every re-drop.** After the operator
   booked the sale by hand (no import hash), the next drop of the same file
   says again „Den Verkauf von Hand buchen…": a double booking one step
   away. **Filed at the merge,** together with ADR-0053's deferred ask: "A refused
   row's 'book it by hand' remedy is shown although the booking already
   exists" (needs a choice: match
   hand bookings by their economics, or word the remedy "if not done yet").
4. **State precedence.** A refused booking the operator put right by hand is
   both "refused" and "hand-edited". **Fixed in the story:** hand-edited
   wins, so it reads „Seit dem Import von Hand geändert — bleibt".
5. **A price-only line is always a kept line** (A2 derives a JSON price from
   the cash, so only a hand edit separates them): the confirm never writes a
   price alone. **Fixed in the story:** the test pins it; no "price only"
   confirm path.
6. **#1188's refusals need the stored-refusal path too.** A CSV cash
   transfer with a negative Steuern stored since Sprint 19 becomes a refused
   row; `stored_refusals/2` covers A5's credits only. **Fixed in the story
   (α7 lists it as a refused line).**
7. **`apply_error_message/1` prints a companion's internal id**
   („Zeile 5.tax_refund.1"; it does not use `row_label/2`). **Fixed in the
   #1179 story** (every row label).
8. **A JSON refund's stored note says "row N"** („Auto-split tax refund from
   row N", `json_parser.ex:183`). **Fixed in the #1179 story** (new notes
   only; no hash reads it).
9. **The done page's manual plurals:** "%{n} Datensatz/Datensätze über
    frühere ISIN zugeordnet." and "%{n} row(s) collapsed…". **Fixed in the
    #962 story.**
10. **The recount cue and the seconds-class rule** (DESIGN.md 2026-08-22): a
    small file's dry run is sub-second and the cue would flicker. **Fixed in
    the N20 story:** `aria-busy` at once, the cue only when the answer has
    not arrived after ~500 ms.
11. **"von Hand"** covers any journal actor other than the importer and the
    correction, an API token included. **Fixed in the story:** DESIGN.md
    defines it; string kept.
12. **#1197's mixed case:** a set balance between two corrected bookings of
    one account absorbs only part. **Fixed in the story:** the sentence names
    the absorbed part and the balance's real change; a test pins it.


---

## Board 08 — shared components and copy

**Board:** `design-language/mockups/ux-design-2026-10-09/08-shared-copy.html`,
rendered as `08-shared-copy--1200.png` and `08-shared-copy--390.png`.

- **Frames.** `srcdoc` iframes built from the live markup of `AppShell`
  (`inline_result`, `data_note`), `securities_live.ex` (toolbar, chips,
  `#securities-action-result`), `transaction_management_live.ex`,
  `portfolio_accounts_live.ex`, `snapshots_live.ex`, `logo_override_dialog.ex`,
  `security_form_dialog.ex`, `portfolio_live.ex` (`fx_sync_control`, the
  allocation tables, the data notes), `income_live.ex`, `dashboard_live.ex`,
  `contribution_table.ex`, `rename_dialog.ex`, `merge_dialog.ex` /
  `merge_preview.ex`. Desktop frames are 980 px, phone frames real 390 px
  viewports; dialogs open with `showModal()`.
- **Focus is drawn.** A frame cannot hold keyboard focus in nine places at once,
  so `.ring-ua` stands in for Chromium's `outline: auto 1px` and `.ring-house`
  for the 2 px accent ring at a 2 px offset that the named rule declares.
- **Data.** "Arbolia Inc." twice (ISINs `DE000000000A`, `DE000000000B`),
  "Larkspur Rail AG", "Wrenfield Gardens AG", "Tagesgeld", Verrechnungskonto #12,
  Wertpapier #31. All invented.

### N13 — #1166: dismissing an inline result (variants, and the ring before/after)

**Today.** The dismiss (`.inline-result__dismiss`, `app_shell.ex:506-514`) has
no `:focus-visible` rule (`app.css:6729-6753`), so Chromium draws its `auto 1px`
ring. Its `phx-click` removes the note and the focused button with it, so the
focus falls to `<body>` and the next Tab starts at the top of the page.
Classifications already answers it: `dismiss_focus/1`
(`classifications_live.ex:3221-3225`) gives the focus to the input the refusal
named, else the plan editor's heading, else the tree's.

**The ring (before/after).** `.inline-result__dismiss:focus-visible { outline:
2px solid {colors.accent}; outline-offset: 2px }` — the button family's rule
(issue 1062, rule ③), the ring the toolbar's icon buttons beside it draw. Spec:
EXPERIENCE.md → Accessibility Floor ("visible focus is a solid 2px accent
outline … on every interactive element"); DESIGN.md → the focus ring of the
button family.

**Variants (where the focus goes):**

- **A — recommended: the control that produced the result, else the section's
  heading.** The handler that sets a result knows its trigger; the slot carries
  it (`focus_return`) and a fallback (`focus_fallback`, the section's heading),
  and the dismiss focuses the first still on the page. Classifications'
  `dismiss_focus/1` becomes the general rule. A fallback heading takes
  `tabindex="-1"` and `.result-focus-fallback`; a page without a section heading
  (Securities) falls back to its toolbar's first control, the search field. Only
  the ×'s own removal moves the focus.
- **B — the emptied slot** (`tabindex="-1"`, as `#securities-action-result` is
  for #920). One target per page, nothing to remember; but the ring draws around
  nothing and a screen reader announces an empty group.
- **C — always the heading.** Predictable; but where the trigger still stands it
  sends the operator away from it, and Securities, Snapshots and the Quotes tab
  have no section heading — the Securities heading is the top bar's
  "Wertpapiere".

**Why A.** It returns the operator to where the action started — the answer the
page's dialogs already give (`data-focus-return`, else `data-focus-fallback`;
WCAG 2.4.3) and the one Classifications gives a dismiss. The history after a
confirmed delete already lands on `#transaction-history-heading` (issue 912),
which A keeps as its fallback.

**Strings.** None.

**Measured (980 px):** the × is 22.4 × 16 px (the same at 390 px); with the ring
its box is 30.4 × 24 px, 6.7 px inside the note's top edge and 5.3 px inside its
bottom edge — nothing clips it. A lands on "Kurse aktualisieren", 30 × 30 px. B's
target is 980 × 0 px with #1160 shipped (8 px tall without). C's heading is 35 px
above the trigger but two Tab stops before it (three at 390 px, where "Filter"
shows), and its ring runs over the top bar's subtitle line.

**CSS:** rule ① (the dismiss's ring) and rule ② (`.result-focus-fallback`:
`scroll-margin-top` below the sticky top bar, the house ring with
`{rounded.sm}` corners).

**What the story writes into DESIGN.md** (`{components.inline-result}`, the
J7 amendment): the dismiss's ring; after a dismiss the focus goes to the
result's trigger, else the section's heading, else the toolbar's first control;
the headings that take it.

### N14 — #1155: twin names (the tables before/after; a note's sentence, variants)

**Today.** `SecurityNames.put_twin_ids/2` runs for Wealth's Positions and the
contribution table only; DESIGN.md → "Twin names" names the surfaces it has not
reached: the contribution's unvalued note, the allocation tree and flat
positions, the history, the trades, the Overview.

**The tables (before/after).** Each surface hands its rows to `put_twin_ids/2`
and renders `<SecurityNames.twin_id tag={row.twin_id} />` after the name: the
history's Wertpapier cell and phone row (decided over the loaded history, so a
filter never adds or removes a tag), Cashflow → Abgeschlossene Trades (table and
phone rows), Wealth's allocation tree position rows and flat positions, the
Overview's "Abgeschlossene Trades" card. The security's Trades tab lists one
security and is unchanged. Spec: DESIGN.md → "Twin names" (the collision key over
the whole payload, the ISIN/WKN/"Nr." chain, the anatomy).

**Variants (a note's sentence):**

- **A — recommended: the `.twin-id` tag after the name, inside the sentence.**
  Same anatomy as the tables; a unique name stays bare; the note decides over
  the names it lists.
- **B — "(ISIN …)" in brackets.** Plain text, so no msgid changes; but a second
  anatomy, a double bracket in the contribution note ("Arbolia Inc. (ISIN …)
  (12 Tage, …)"), and "(WKN …)" / "(Nr. …)" words the tables never print.
- **C — no identifier (today).** "Arbolia Inc., Arbolia Inc." reads as a
  stutter; the Overview's note has no table below it to resolve which.

**Why A.** A name in a sentence is the same name as in the table, so it carries
the same tag; the tag is quieter than the sentence and reads as part of the name.

**Strings.** None new. Under A three msgids that interpolate the joined names
split so the list renders as markup after the colon: Wealth's `dq-missing-fx`
("… so it is missing from the totals: %{entries}."), the Overview's and Income's
excluded sales ("… left out of the trades: %{securities}. The rate backfill is
under “All trades”." — the list moves out, the second sentence becomes its own
msgid). The stale-quote, no-price and contribution notes already render their
list outside the msgid.

**Measured:** the tag is 86.7 px at 980 and at 390 px (12 px mono, nowrap); in
the phone's flat positions the name cell is 144 px and the tag wraps under the
name (row 50.8 px). The three notes under A are 54 px tall each at 980 px and
126–144 px at 390 px.

**What the story writes into DESIGN.md** ("Twin names"): the surfaces now
covered (replacing the "Not here" list) and the sentence rule: a note that lists
names tags a twin the way the table does.

### #1138 — a dialog's own footer sits flush with its edge (before/after)

**Today.** `.modal-footer` has no padding (`app.css:2335-2340`); the logo
dialog's footer is the dialog's own child (`logo_override_dialog.ex:79`), so
"Logo entfernen" touches the right and bottom edges and `dialog.modal {
overflow-y: auto }` cuts its accent ring (issue 1062 fixed the ring's colour).
Of the ten `.modal-footer` call sites, three are the dialog's own child (this one
and the two "cannot delete" dialogs, which have the precedent `.confirm-delete-
blocked .modal-footer { padding: 0 18px 18px }`, `:2757`).

**After.** `.modal > .modal-footer:not(.modal-footer--band) { padding: 0 18px
18px }`; the scoped precedent becomes redundant (removed in the story). Spec:
DESIGN.md → dialogs; the focus ring of the button family.

**Strings.** None.

**Measured:** today "Logo entfernen" ends 0 px from the dialog's right and
bottom edges (980 and 390 px; at 390 the dialog is the full 390 px wide); after,
18 px and 18 px, and the dialog grows by 18 px (336 → 354 px at 980).

**What the story writes into DESIGN.md** (dialogs): a footer that is the
dialog's own child takes the body's 18 px padding; a band footer keeps its own.

### #1160 — an empty result slot takes room at rest (before/after)

**Today.** The component's regions always hold whitespace (`app_shell.ex:471-491`),
so `.inline-result__region:not(:empty) { margin: 8px 0 }` (`app.css:6712`) always
matches; in a section's grid the slot is also a grid row.

**After.** The component's rule asks for a result (`:has(> *)`; replaces
`:6712`), and the page slot's grid rule (`:901`) is widened to every inline
result. A result keeps today's 8 px margins. Spec: DESIGN.md → "A page's result
is an inline result" ("nothing at rest").

**Strings.** None.

**Measured** (the band between the block above the slot and the block below):
Accounts 52 → 28 px at 980 and at 390 px (the 8 px slot and one 16 px grid gap
gone); Securities 8 → 0 px; Snapshots 24 → 16 px. The Quotes tab's release
result loses its 8 px (not drawn).

**What the story writes into DESIGN.md:** the J7 amendment's "The other inline
results … keep their footprint" becomes "every inline result takes no room at
rest".

### #1157 — progress labels in the first person (before/after)

**Today.** "Suche…" (`security_form_dialog.ex:250`), "Suche Logo…"
(`securities_live.ex:5385`), "Synchronisiere…" (`portfolio_live.ex:4241, 4245`).
`microcopy_voice_test.exs` misses them (its du-imperative pattern needs a
lower-case verb mid-sentence or a space after a capitalised one). Spec:
EXPERIENCE.md → Voice and Tone, impersonal voice (binding); the house form
"Wird importiert…", "Wird gebucht…", "Wird korrigiert…", "Wechselkurse werden
synchronisiert…".

**Strings** (msgids unchanged):

| msgid | Heute | Nachher |
|---|---|---|
| Searching… | Suche… | Wird gesucht… |
| Looking up logo… | Suche Logo… | Logo wird gesucht… |
| Syncing… | Synchronisiere… | Wird synchronisiert… |
| Saving… (found) | Speichern… | Wird gespeichert… |
| Backfilling… (found) | Lädt nach… | Wird nachgeladen… |

**Measured:** "Wird gesucht…" fits the search list's line (482 × 42 px at 980);
the sync button grows to 160 px at 390 px, one line.

**What the story writes into EXPERIENCE.md / the invariant:** a running action's
label is the impersonal passive; `microcopy_voice_test.exs` gains "every msgid
whose first word ends in '-ing' and that ends in '…' has a German msgstr with
'wird' or 'werden'".

### #1191 — the former-name and ISIN-alias refusals in German (before/after)

**Today.** `NamedRecordRefusal.screen/1` (`named_record_refusal.ex:21-49`) swaps
the id-naming message for the screen's sentence, which has no `errors.po` entry,
so it prints in English. The rename dialog's `changeset_error/1`
(`rename_dialog.ex:363-370`) drops the field, so the sentence starts "include …";
the merge dialog's `changeset_errors/1` (`merge_dialog.ex:619-631`) prints the
raw key ("former_isin") and fills the bindings itself.

**After.** The ten sentences get `dgettext_noop("errors", …)` and German
msgstrs; both dialogs name the field by `FieldLabel.label/1`. The API and MCP keep
their English (the swap runs on the screen's path only). Spec: EXPERIENCE.md →
the language rule (no user-facing string bypasses gettext); ADR-0054 (a record
named by kind and id).

**Strings** (errors domain; `%{…}` bindings unchanged):

| English (msgid) | German |
|---|---|
| is still the current ISIN of "%{security_name}" (security #%{security_id}) | ist noch die aktuelle ISIN von „%{security_name}“ (Wertpapier #%{security_id}) |
| is already the current ISIN of "%{security_name}" (security #%{security_id}) | ist bereits die aktuelle ISIN von „%{security_name}“ (Wertpapier #%{security_id}) |
| is recorded as a former ISIN of "%{security_name}" (security #%{security_id}) | ist als frühere ISIN von „%{security_name}“ (Wertpapier #%{security_id}) erfasst |
| … ; delete that alias or record an ISIN change instead | … ; diesen Alias löschen oder stattdessen einen ISIN-Wechsel erfassen |
| is a former name of cash account #%{holder_id} ("%{holder_name}"): an import naming it books there. Remove it from that account's former names first | ist ein früherer Name von Verrechnungskonto #%{holder_id} („%{holder_name}“): Ein Import unter diesem Namen bucht dort. Zuerst aus den früheren Namen jenes Kontos entfernen |
| (the same for securities account) | … von Depot #%{holder_id} („%{holder_name}“) … aus den früheren Namen jenes Depots entfernen |
| include "%{former_name}", the name of cash account #%{holder_id} in this portfolio | enthalten „%{former_name}“, den Namen von Verrechnungskonto #%{holder_id} in diesem Portfolio |
| include "%{former_name}", a former name of cash account #%{holder_id} in this portfolio | enthalten „%{former_name}“, einen früheren Namen von Verrechnungskonto #%{holder_id} in diesem Portfolio |
| (the two "include" sentences for securities account) | … von Depot #%{holder_id} … |

As rendered: "Frühere Namen enthalten „Tagesgeld“, einen früheren Namen von
Verrechnungskonto #12 in diesem Portfolio" (rename) and "Nichts wurde
zusammengeführt: Eine Zeile ließ sich nicht schreiben (Frühere ISIN ist als
frühere ISIN von „Larkspur Rail AG“ (Wertpapier #31) erfasst). Erneut prüfen."
(merge).

**Measured:** the rename field error goes from one line to two (604 × 17 → 604 ×
38 px at 980; 354 × 38 px at 390); the merge problem note stays 604 × 54 px at
980 and is 358 × 90 px at 390.

**What the story writes into DESIGN.md** (H8.3/H8.8 refusals): the named-record
refusals read German on the screen, field-labelled, the record by kind and id.

### Found while drawing

1. **Two more first-person or ambiguous progress labels:** "Speichern…"
   (`Saving…`, Accounts' "Saldo setzen", `portfolio_accounts_live.ex:444`) reads
   as a dialog-opening button, and "Lädt nach…" (`Backfilling…`,
   `income_live.ex:114, 117`). **Fixed in the story that touches the surface
   (D-14)** — #1157, same rule, same catalog.
2. **The rename dialog prints a field error without its field**, so "include …"
   / "enthalten …" starts with a verb. **Fixed in the story (D-14)** — #1191's,
   on the message path it touches (`FieldLabel.label/1` prefix).
3. **The merge dialog prints the raw field key** ("former_isin") inside its
   German sentence. **Fixed in the story (D-14)** — #1191's.
4. **The scoped `.confirm-delete-blocked .modal-footer` padding** becomes a
   duplicate of rule ③. **Fixed in the story (D-14)** — #1138 removes it.
5. **A twin list inside an interpolated msgid** (`dq-missing-fx`, the Overview's
   and Income's excluded sales) cannot carry markup; under N14 A the three msgids
   split. **Fixed in the story (D-14)** — #1155's.
6. **#1160 is drawn twice.** Board 05 draws Accounts' slot with the same two
   rules; this board draws the component on Securities and Snapshots too. **No
   action** beyond one story owning it.


---

## Board 09 — money states: an unavailable trade, a cross-currency row, a bond's coupon

**Board:** `design-language/mockups/ux-design-2026-10-09/09-money-states.html`,
rendered as `09-money-states--1200.png` and `09-money-states--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup:
  - `securities_live.ex` (`trades_tab_panel/1`, `transactions_tab_panel/1`);
  - `income_live.ex` (the realized facet; the income facet's "Top-Beiträge"
    and "Je Position");
  - `dashboard_live.ex` (`closed_trades_card/1`);
  - `transaction_management_live.ex` (the notes-only drawer);
  - `portfolio/contribution_table.ex`.

  The German msgstrs come from `priv/gettext/de`. N8 stacks its three
  surfaces in one frame per variant and width.
- **CSS.** "Heute" frames render `app.css` as shipped; the others add
  `<style id="proposal">`:
  - rule ① mutes the dash in the Trades tab's phone row (the card's selector
    serves variant B);
  - rule ② is variant C's currency line (C only).

  #928 needs no CSS.
- **Data.** Invented throughout:
  - "Arbolia Inc." (USD) in "Depot Muster" (cash account "Test-Cash", EUR)
    and "Depot USD" ("US Broker", USD);
  - "Larkspur Rail AG", "Wrenfield Gardens AG";
  - #928 uses ADR-0051's I12 fixture as amended on 2026-10-09: "Larkspur
    Rail AG 4,00 % Anleihe 2031", `XSLARKSPUR33`, the window 01.01.2026 –
    30.06.2026.

**Read before drawing:** ADR-0015's "Amendment (2026-10-09)", points 2, 3
and 6, as signed; N8 A draws point 3 as written. ADR-0051's "Amendment
(2026-10-09)" was read in full; #928 uses its I12 figures.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **N8** | An unavailable closed trade (#1198) | variants | **A** |
| **N9** | A cross-currency booking's money cells (#1213) | variants | **A** |
| — | The drawer's amount label (#1213); a coupon as its bond's income (#928) | before/after | — |

### ① N8 — #1198: a closed trade whose lot has no leg in the sale's currency (variants)

**Today.** A buy of 10 Arbolia imported from Portfolio Performance on
12.02.2025 in the account's currency, at 80,00 EUR per share. It carries no
settlement legs: no hub rate was stored for its day at import, and no
history backfill has run since. A hand-booked sale of those 10 on 14.08.2026
at 120,00 USD, settled 960,00 EUR at 0,80, with a fee of 3,00 EUR.

The matcher multiplies the lot's price as stored (`trade_matcher.ex:209-212`)
and gives the trade the sale's currency (`:271`). Every surface therefore
reads a good trade:

- **The Trades tab:** Ø Kauf "80,00" (euros under a USD sale), G/V
  "+396,25", "+49,5%", p. a. "+30,7%".
- **The facet:** Einstand "800,00 USD", Ergebnis "+317,00 EUR"
  (`realized_gains.ex:336` converts the mixed result). It is summed into
  "Realisiert gesamt" (+512,02 EUR), the hit rate (75,0 % over 4), the
  average holding period (434 days) and the matrix.
- **The Overview card:** "+317,00 EUR · +30,7% p. a.".

**Signed** (ADR-0015 amendment 2026-10-09, point 3): a lot without the leg it
needs makes its closed trade **unavailable**, never summed.

- **The trades read keeps it** with its sell's own figures: the quantity,
  the dates, `avg_sell_price`, the sell's fees and taxes, and `proceeds`
  (1.196,25 USD). Every figure derived from the lots is null, and the reason
  is `missing_settlement_leg`, with each lacking lot's open date and booking
  currency.
- **The realized-gains report, the Overview card and Income** name it in
  `excluded`, told apart from a sale excluded for a missing close-date rate.
  They leave it out of `trades`, the matrix and the three figures.
- **The Trades tab** names it unavailable, with its remedy: the lot's legs
  (point 6: the history backfill derives them), or a rate for the lot's
  date.

**Variants:**

- **A — recommended: the signed text, drawn.**
  - **The Trades tab keeps the row.** Ø Kauf, p. a., Realisierter G/V and
    "%" are the reason dash: #1089's anatomy, Sprint 20's zero-basis
    pattern. The dash is muted and `aria-hidden`; the reason "Ohne
    Umrechnung: Ein Kauf in EUR hat keinen Gegenwert in USD" rides the
    `title` and a visually hidden sentence. Ø Verkauf, Tage and Stückzahl
    stay. At 390 px the row says "ohne Umrechnung" under a muted dash in the
    result slot.
  - **The tab names it, with its remedy.** An attention note leads
    "Abgeschlossene Trades", as the unmatched-sells note does
    (`data-role="trades-unavailable"`). Its words are under Strings. The
    remedy points at the backfill control under "Alle Trades".
  - **Income's realized list and the Overview card leave it out.** Each
    names it in the exclusion note it already has for a sale with no
    close-date rate (`realized-excluded`, `trades-card-excluded`), in a
    reason sentence of its own: the two remedies differ.
    - The facet's note keeps the existing backfill control
      (`fx_backfill_control/1`). Since point 6, that control also derives
      the missing legs, and its sentence says so (found while drawing, 2).
    - The figures read "+195,02 EUR · 66,7% über 3 abgeschlossene Trades ·
      396 Tage".
    - The card's basis line counts the three rows it shows.
  - **One exclusion shape on the aggregates:** out of the rows, the matrix
    and the figures, named in one note (UX-DR25 clause 1), with no figure
    converted (clause 2).
- **B — the row leaves every list, the Trades tab's included.** It is named
  in a note of its own above each list:
  - the facet: "1 Trade ohne Umrechnung ist aus jeder Summe und aus der Liste
    ausgeschlossen: …";
  - the tab: "1 Trade ohne Umrechnung ist in keinem abgeschlossenen Trade
    enthalten: …";
  - the card: "1 Trade ohne Umrechnung fehlt bei den Trades: Arbolia Inc.
    Mehr unter „Alle Trades“."

  **What B costs.** The tab lists one trade for a security that closed two.
  The reader must match dates against Transaktionen to find the sale, and
  the proceeds and the 548 days, both correct, are gone. On Income and the
  card, B puts a second note beside the no-rate one. B also departs from the
  signed text, which keeps the trade in the trades read and on the tab.

**Why A:** it is point 3 as signed.

- **The security's own page keeps the trade that happened** and says what
  fixes it, where the operator looks at that security. A sale in
  Transaktionen with no trade would read like an unmatched sell.
- **The aggregates, whose job is the totals,** keep the one shape they
  already have for a trade they cannot convert.

**Strings** (A; new):

| | English (msgid) | German |
|---|---|---|
| Tab dash `title` (Ø Kauf, p. a., G/V, "%") | Not convertible: a buy in %{lot_currency} has no figure in %{currency} | Ohne Umrechnung: Ein Kauf in %{lot_currency} hat keinen Gegenwert in %{currency} |
| Tab dash, visually hidden | not convertible, a buy in %{lot_currency} with no figure in %{currency} | ohne Umrechnung, ein Kauf in %{lot_currency} ohne Gegenwert in %{currency} |
| Tab phone row, visible | not convertible | ohne Umrechnung |
| Tab note (`ngettext`; one sentence per lacking lot) | %{count} trade not convertible: the buy of %{lot_date} is booked in %{lot_currency} and has no figure in %{currency}, the sale's currency; the trade's cost and result are missing, and it counts in no total. Remedy: a rate for %{lot_date} — the rate backfill under “All trades” stores it and derives the figure from it — or the figure in %{currency} on the booking. | %{count} Trade ohne Umrechnung: Der Kauf vom %{lot_date} ist in %{lot_currency} gebucht und hat keinen Gegenwert in %{currency}, der Währung des Verkaufs; Einstand und Ergebnis des Trades fehlen, und er zählt in keiner Summe. Abhilfe: ein Wechselkurs für den %{lot_date} — das Nachladen der Wechselkurse unter „Alle Trades“ speichert ihn und leitet daraus den Gegenwert ab — oder der Gegenwert in %{currency} an der Buchung. |
| Facet exclusion sentence (`ngettext`) | %{count} sale is not convertible — a buy it closes has no figure in the sale's currency — and is excluded from every total: %{securities}. / %{count} sales are not convertible — a buy each closes has no figure in its sale's currency — and are excluded from every total: %{securities}. | %{count} Verkauf ist ohne Umrechnung — ein Kauf, den er schließt, hat keinen Gegenwert in der Währung des Verkaufs — und aus jeder Summe ausgeschlossen: %{securities}. / %{count} Verkäufe sind ohne Umrechnung — je ein Kauf, den sie schließen, hat keinen Gegenwert in der Währung ihres Verkaufs — und aus jeder Summe ausgeschlossen: %{securities}. |
| Card exclusion sentence (`ngettext`; the existing pointer to the backfill follows) | %{count} sale not convertible — a buy it closes has no figure in the sale's currency — is left out of the trades: %{securities}. / %{count} sales not convertible — … — are left out of the trades: %{securities}. | %{count} Verkauf ohne Umrechnung — ein Kauf, den er schließt, hat keinen Gegenwert in der Währung des Verkaufs — fehlt bei den Trades: %{securities}. / %{count} Verkäufe ohne Umrechnung — … — fehlen bei den Trades: %{securities}. |
| Backfill control's sentence (changed) | The daily rate sync cannot fill a past date. The backfill fetches the historical ECB series once, stores every published day and derives from it the settlement legs imported buys and sells lack; a day the ECB did not publish stays excluded. | Die tägliche Kurssynchronisation kann einen vergangenen Tag nicht nachtragen. Das Nachladen holt die historische EZB-Reihe einmalig, speichert jeden veröffentlichten Tag und leitet daraus die Gegenwerte ab, die importierten Käufen und Verkäufen fehlen; ein Tag, den die EZB nicht veröffentlicht hat, bleibt ausgeschlossen. |

**Measured:**

| | 980 px | 390 px |
|---|---|---|
| Trades tab rows (A) | 33 / 33 | phone rows 59 / 59 |
| Tab note (A) | 907 × 72 | 336 × 234 |
| "ohne Umrechnung" on the tab's phone row (A) | — | 105 × 15 (one line) |
| Facet rows (A and B; the trade is out) | 32 / 32 / 31 | phone rows 59 / 60 / 60 |
| Facet exclusion note with the backfill control (A) | 933 × 158 | 358 × 320 |
| Card rows (A and B) | 36 / 36 / 36 | 37 / 37 / 37 |
| Card exclusion note (A) | 933 × 54 | 358 × 108 |
| Facet note (B) | 933 × 72 | 358 × 162 |
| Card note (B) | 933 × 36 | 358 × 72 |

The unavailable row on the tab is as tall as its neighbour at both widths.

**What the story writes into DESIGN.md:**

- **The security's Trades tab:** the unavailable trade's row, its reason,
  its phone words, and the note with its remedy.
- **The Trades facet and the Overview card:** the second reason sentence in
  the existing exclusion note; the backfill control's sentence; that the
  trade is out of the rows, the matrix and the figures.

### ② N9 — #1213: a cross-currency booking's money figures name no currency (variants)

**Today.**

- **The booking's currency.** Since the ADR-0015 amendment of 2026-10-07, a
  booking's cash, fees and taxes are in its cash account's currency, and its
  price and gross (quantity × price, `tx_gross/1`,
  `securities_live.ex:3284-3290`) in the booking's.
- **Where the cells are.** The bare cells are on the security's
  **Transaktionen** tab (`transactions_tab_panel/1`, `:2044-2046`), not on
  the Trades tab as the issue, triage B and the decisions file name it.
- **What they read.** The hand-booked sale of 14.08.2026 reads Preis
  "120,00 USD", Gebühren "3,00", Steuern "0,00", Brutto "1.200,00". The fee
  is euros, the gross dollars, and both read as dollars beside the price.
- **The Trades tab's own gap** is the desktop result cell: "+98,89" with no
  currency, while its phone row says "+98,89 USD" (the issue's comment of
  2026-10-09).

**Variants:**

- **A — recommended: a suffix only on cross-currency rows.** A row whose
  booking currency differs from its cash account's (the drawer's settlement
  case) gets the `<small>` suffix the Preis cell already carries: Gebühren
  and Steuern name the account's currency ("EUR"), and Brutto the booking's
  ("USD"). A same-currency row stays as it is: the Depot USD buy, and the
  EUR buy imported in Portfolio Performance's form. Its Preis already names
  the one currency all its figures are in.
  - **The Trades tab under A's rule:** "Realisierter G/V" carries the trade's
    currency at every width ("+98,89 USD"), as the phone row does. After the
    ADR-0015 amendment of 2026-10-09 a closed trade is in its sale's
    currency, so two trades of one security can be in two currencies, and a
    bare result cell cannot say which. Ø Kauf and Ø Verkauf stay bare, in the
    result's currency.
- **B — a suffix on every money cell of every row.** One rule, no
  condition, never wrong.
  - Its cost is not width. A column is as wide as its widest cell, which A
    already suffixes: 816 against A's 815 px of table at 390.
  - Its cost is noise: a currency three more times on every row of every
    security, and the row that matters looks like all the others.
- **C — a currency line under a cross-currency row:** "Preis und Brutto in
  USD · Gebühren und Steuern in EUR (Test-Cash)".
  - It explains the split in words, but each such row grows by a line.
  - The line sits under the Depot and Notizen columns.
  - At 390 px it scrolls away with the table while the figures it explains
    stay in view.
  - It is the only variant with CSS (rule ②).

**Why A:** the suffix appears exactly where the reader would assume the
price's currency and be wrong. A same-currency history, which is most of
them, looks as it does today.

**Strings.** None new for A or B (the suffix is the currency code). C's line
would be new: "Price and gross in %{booking_currency} · fees and taxes in
%{account_currency} (%{account})" / "Preis und Brutto in
%{booking_currency} · Gebühren und Steuern in %{account_currency}
(%{account})".

**Measured** (the Transaktionen table; five rows, 35 px each in every
variant except C):

| | Gebühren / Steuern / Brutto at 980 px | Table at 390 px (its own scroller) |
|---|---|---|
| Heute | 97 / 85 / 89 px | 781 px of content in a 336 px box |
| A | 93 / 85 / 119 px | 815 px |
| B | 92 / 87 / 119 px | 816 px |
| C | 97 / 85 / 89 px; three 24–25 px lines added | 781 px; the same three lines |

The tab has no phone rows. Under 560 px the table scrolls inside itself
(`app.css`'s phone rule `table { display: block; overflow-x: auto }`), and
the board draws it scrolled to its end.

**What the story writes into DESIGN.md** (Transactions → the security's
Transaktionen tab; the Trades tab's closed trades):

- the cross-currency row's suffixes;
- that a same-currency row stays bare;
- the result cell's currency at every width.

### ③ #1213 — the drawer's "Betrag (USD)" (before/after)

**The spec rule:** ADR-0015 amendment 2026-10-07, point 1: a booking's cash,
fees and taxes are in its cash account's currency.

**Before.** A dividend of Arbolia Inc. credited 80,00 EUR to Test-Cash, with
12,00 EUR withheld. The notes-only drawer labels the amount
`gettext("Amount (%{currency})", currency: tx.currency_code)`: "Betrag
(USD)" (`transaction_management_live.ex:2127`; the cash transfer's at
`:2084`). Meanwhile the history reads "80,00 EUR" and Erträge counts EUR 80.

**After.** The label names the cash account's currency, "Betrag (EUR)", and
the withheld tax beside it names it too, "Steuern (EUR)". The drawer's
controls change with board 03's N12 (the one-amount kinds booked on screen);
this label rule holds there unchanged.

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Amount label | Amount (%{currency}) (existing; the argument changes) | Betrag (%{currency}) |
| Taxes label | Taxes (%{currency}) (new) | Steuern (%{currency}) |

**Measured.** By eye only: the two fields keep their row of two in the 380 px
drawer and in the 390 px sheet; each label swaps three letters for three
("(USD)" → "(EUR)") or gains six ("Steuern" → "Steuern (EUR)").

**What the story writes into DESIGN.md** (Edit on the kinds the drawer does
not book; and N12's drawer): a cash kind's amount and taxes name the cash
account's currency.

### ④ #928 — a bond's coupon is its position's income (before/after)

**The spec rule:** ADR-0051 amendment 2026-10-09, points 3 and 6, and
identity I12.

**Before.** The importer drops the coupon's security
(`applier.ex:2036-2037`), and the walk puts every interest booking in the
remainder. On I12:

- **The contribution table:** the bond contributes **+125,00** (its price
  move) with Erträge 0,00, and "Zinsen" reads **+401,10**.
- **Income's "Je Position":** one row without a security, "Zinsen", 401,10
  from 2 payments; "Top-Beiträge" shows the same single row.
- **The note under "Zinsen":** "Konto und Kupons; eine Zinsbuchung trägt
  kein Wertpapier".

**After.**

- **The contribution table.** The bond's Erträge reads **+400,00** and its
  Beitrag **+525,00** (its bar keeps 45 % of the track; it is still the
  largest). "Zinsen" reads **+1,10**, and the sum row's Erträge +400,00. The
  result stays **+526,10 EUR** (I1).
- **At 390 px** the bond's line gains "· Erträge 400,00", and the remainder
  row reads "Zinsen +1,10 · Gebühren/Steuern 0,00 · Währung 0,00".
- **"Je Position"** splits into the bond's row (400,00, 1 payment, last
  15.04.2026) and "Zinsen" (1,10, 1 payment, last 31.03.2026).
  "Top-Beiträge" follows. The year bars, the matrix and 2026's interest
  total (401,10) split by kind and do not change.
- **The note under "Zinsen"** (desktop only; the phone's remainder row has no
  note) changes from "Konto und Kupons; eine Zinsbuchung trägt kein
  Wertpapier" to "Zinsbuchungen ohne Wertpapier: Kontozinsen und Kupons, die
  ohne ihre Anleihe gebucht sind". It is the line §3 now defines.
  - **It names no release date.** The planning session's draft, "… coupons
    imported before 2026.10.15", would not hold: a coupon written over the
    API without its security after the build lands here too (point 2), and a
    date would go stale. The condition is what holds.

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Interest line note (replaces "Account interest and coupons; an interest booking carries no security") | Interest bookings that name no security: account interest, and coupons stored without their bond | Zinsbuchungen ohne Wertpapier: Kontozinsen und Kupons, die ohne ihre Anleihe gebucht sind |

**Measured:**

| | Before | After |
|---|---|---|
| 980 px: the "Zinsen" line | 49 px tall; note 347 × 17 (one line) | 65 px; note 347 × 34 (two lines) |
| 980 px: the contribution table | 302 px | 319 px |
| 980 px: "Je Position" table | 61 px | 93 px |
| 390 px: phone rows (position / remainder / sum) | 58 / 76 / 60 px | 58 / 59 / 60 px |
| 390 px: "Je Position" (its own scroller, 356 px) | 673 px wide | 812 px wide |

The remainder row is shorter after: "Zinsen +1,10 · …" fits on one line.

**What the story writes into DESIGN.md:**

- **The contribution table:** the "Zinsen" line's new note and the English
  pair, and that a coupon naming its bond is that position's income.
- **Income:** a coupon naming its bond is that bond's row.

### Spec

- **ADRs:** ADR-0015 (amendments of 2026-10-07 and 2026-10-09); ADR-0051 §1,
  §3, §5 and its amendment of 2026-10-09 (I1, I12); ADR-0033.
- **UX rules:** UX-DR25 (clauses 1–3), UX-DR26, UX-DR27.
- **DESIGN.md:**
  - Amendment 2026-10-01 — Trades: the facet, the p. a. column, the
    Overview card, the security's Trades tab;
  - Amendment 2026-10-08 — A return on no cost basis (the dash);
  - Amendment 2026-10-03 — the contribution table;
  - Edit on the kinds the drawer does not book.

### Found while drawing

1. **#1213's cells are on the Transaktionen tab.** The fees, taxes and gross
   are in `transactions_tab_panel/1`; the Trades tab has none. The issue,
   triage B and the decisions file say "Trades tab". **Fixed in the story
   that touches the surface (D-14):** A10 covers both tabs, as drawn.
2. **The backfill control's sentence under-describes it** once ADR-0015
   point 6 lands. It says the backfill "stores every published day"; it now
   also derives the legs imported buys and sells lack, and that is the
   remedy the unavailable trade's sentence points to. **Fixed in the story
   that touches the surface (D-14):** the control's sentence gains the
   clause (Strings, last row). The ADR orders #1196 before #1198, so the
   control acts on the trade by the time the trade is named.
3. **The control's label says "Kurse"** ("Historische Kurse nachladen", and
   "Kurssynchronisation" in its sentence) for exchange rates, which the
   Overview card's note calls "Wechselkurse". **Decided here:** it is
   #1150's word rule, on board 04; this board reuses the label as it stands.

The first draft's filing, "one exclusion shape on the Trades facet", is
withdrawn. The signed point 3 gives the aggregates one shape: the
unavailable trade leaves their rows and is named in the no-rate note.

4. **The drawer label is on two boards.** The decisions file lists "#1213
   drawer label" under board 03 too. This board draws it on request.
   **Decided here:** board 03 owns the drawer and keeps this rule; one of
   the two sections should point at the other.
5. **#928 is not value-only.** The "Zinsen" note changes its sentence (④).
   ADR-0051's amendment, point 5, already lists "the screen's note".
   **Fixed in the story (D-14).**
