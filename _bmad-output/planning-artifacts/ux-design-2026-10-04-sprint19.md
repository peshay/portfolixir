# UX Design Pass — 2026-10-04, Sprint 19's user-visible items

Scope: **every** user-visible change Sprint 19 proposes, held against the
living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html).
`DESIGN.md` and `EXPERIENCE.md` are the authority, and this document proposes
against them. It runs **on the planning PR, before the batch**, as the standing
rule of 2026-09-20 requires (AGENTS.md → "A UI change is mocked before it is
built").

**The mockups** are in `design-language/mockups/ux-design-2026-10-04/`:

- **One board per item group**, with every variant or its before and after.
  Each board links the real `priv/static/app.css` and uses the live pages'
  markup and German labels.
- **Rendering.** Boards are rendered to PNG with Playwright (`render.mjs`,
  unchanged from the 2026-10-02 pass) and reduced to a 256-colour palette
  (`convert X.png -colors 256 PNG8:X.png`).
- **Real phone widths.** Most phone frames are `srcdoc` iframes, so a 390 px
  frame is a real 390 px viewport and `app.css`'s breakpoints fire as on a
  phone.
- **Who drew them.** Five authors each drew two boards against `DESIGN.md`,
  `EXPERIENCE.md` and the review rubric, and checked each one by eye at every
  rendered width. Every size quoted below was measured inside its frame.

**The data is invented:**

- names in the demo seed's style, and obviously fake identifiers such as
  `DE000000000A`;
- generic account names;
- made-up figures and 2026 dates.

Where the seed itself puts a well-known company on a surface (its "Fällig"
event, a dividend, a 207-day trade), the board uses an invented name instead.
**No real instrument, position, balance, account, provider or rate appears.**

**How a pick is made.** A pick's code is its board's number, and the letter
skips I, so it does not collide with ADR-0051's identities I1–I9.

- **The recommendation is the default.** A comment naming another variant
  changes it, and silence adopts it.
- **A before/after board has nothing to pick:** the spec already fixes the
  answer, and the board shows the reader what the words describe.
- **The story that builds a pick writes its anatomy into `DESIGN.md`.**

| Pick | Item | Board | Plan | Kind | Recommended |
|---|---|---|---|---|---|
| **J1**, **J1.2** | The Overview's total names what it leaves out; the stale count says its scope (#1081; #1068's and #1087's Overview halves) | `01-overview-total` | α M6, M7; D-3 | variants, two questions | **A**, **A** |
| **J2** | What Wealth says about money it cannot value (#1055; #1068's Wealth half) | `02-money-notes` | α M3, M7; D-15 | one pick, two before/afters | **A** |
| **J3**, **J3.2** | The history's month head; the account on a desktop row (#1083, #1084; #1073 and #1090's subtitle as before/after) | `03-history` | γ U1; D-4 | variants, two questions | **A**, **A** |
| **J4** | Reaching and reading trades (#1082; #1089, #1060, #1059, #1074 as before/after) | `04-trades` | γ U2; D-4 | variants and before/after | **A** |
| **J5** | Displayed dates and the chart axes (#1061, #1087, #1088) | `05-dates-charts` | γ U3 | before/after, one pick (the phone label) | **A** |
| **J6**, **J6.2** | Wealth at 390 px; twin names (#1065, #1057; #1086, #1063 as before/after) | `06-phone-wealth` | γ U4 | variants, two questions | **A**, **A** |
| **J7**, **J7.2** | The touch, focus and colour floor, second pass (#1064, #1085; #1062, #1069, #1071, #1067, #933 as before/after) | `07-floor` | γ U5, β B2 | before/after, two picks | **A**, **A** |
| **J8** | Copy and dialog states (#1066; #1090, #1074, #1072, #944, #945 as before/after) | `08-copy-dialogs` | γ U6 | before/after, one pick | **A** |
| **J9** | Correcting cash already booked from a PP CSV (ADR-0053 §6); the row-error and all-hits states (#1044, #948, #923) | `09-import-correction` | α M2, β B4; D-2 | variants and before/after | **A** |
| **J10**, **J10.2** | The category result's view scope; every scope in EUR (#1091, #1048) | `10-category-results` | γ U7, α M5 | variants, two questions | **A**, **A** |

**What the merge adopts beyond the picks.** Four boards found that a written
line of the spec says otherwise. Each one is decided here, so none of them
passes as a quiet conformance repair:

1. **#1068 reverses ADR-0052's Consequences and DESIGN.md's data-quality
   line** (boards 01 and 02). The plan's **D-15** carries it: the reverse
   case is named, master data is a bond signal, and the Overview's line
   counts the finding.
2. **#1089 overturns the H1 amendment's "the facet's p. a. cells stay
   unsigned"** (board 04). The Accessibility Floor's explicit sign outranks
   it. **To flip by comment:** "keep H1 unsigned".
3. **DESIGN.md's KPI clause lets a currency suffix drop to a second line, and
   EXPERIENCE.md's value slot forbids a value from wrapping** (board 06). The
   board follows EXPERIENCE.md. **To flip by comment:** "J6 suffix may drop".
4. **J5 A makes the chart axis 9 px at every width**, which also shrinks
   today's 10.7 px labels on a 1440 desktop. **To flip by comment:** "J5 A
   with a floor" keeps today's desktop size.

**Items with no board:**

- **PR α's M1, M4 and M7's inference fix** change values, not anatomy.
- **PR β** has no other rendered change. Its migrations, build, companion,
  payloads and documentation render nothing; its two rendered items (#933,
  and B4's row states) are drawn on boards 07 and 09.
- **The screenshots of U8** are regenerated from the seed after γ's stories
  land. They picture the boards' "after", and they are not a design of their
  own.

---

## Part 1 — J1 and J1.2: the Overview's total names what it leaves out, and its stale count says its scope (#1081; the Overview halves of #1068 and #1087)

**Board:** `design-language/mockups/ux-design-2026-10-04/01-overview-total.html`,
rendered as `01-overview-total--1200.png` and `01-overview-total--390.png`.
Plan: PR α M6 and M7, decision D-3. Two picks with variants. #1068 and #1087
are before/after and appear in the "Nachher" frame.

**The data is the demo seed's Overview,** with one invented bond on two
scales added for #1068:

- "Alles 62.639,10 EUR";
- USD Settlement (1.850,00 USD) and US Broker (60,00 USD), with no EUR rate;
- "Placeholder Anleihe 2031 3,25%", with no price;
- "25 veraltet".

The seed's "Fällig" events are on a real instrument taken from
`portfolio_performance_demo.json`, so the board uses "Nordwind Industrie
AG" in its place.

**Before:**

- **The card** (`dashboard_live.ex:271-333`) prints `total_with_cash`,
  which counts only valued positions and valued cash (`valuation.ex:396`,
  `:445-473`). Nothing on the Overview names what is left out.
- **The stale count is catalog-wide.** "25 veraltet" in the quotes cell
  (`:390-418`, with the scope comment at `:399-404`) and "25 Wertpapiere
  ohne Kurs seit 7 Tagen" on the line (`dq_findings/1`, `:983-1015`) are both
  the catalog-wide `stale_quote` count. The strip's basis line next to them
  speaks of held positions.
- **The line is far from the total:** it is the last of six blocks, 1,076 px
  below the total at 1200 px and 1,436 px at 390 px (measured).
- **"Fällig" prints ISO dates** (`Date.to_iso8601`, `:553`).
- **There is a precedent:** the trades card already carries a UX-DR25 note
  (`:628-638`).

**Variants — J1:**

- **A — recommended:** one attention note under the card. It reads "Nicht in
  der Summe: 2 Verrechnungskonten ohne Wechselkurs zu EUR — USD Settlement
  (1.850,00 USD), US Broker (60,00 USD) · 1 gehaltene Position ohne Preis —
  Placeholder Anleihe 2031 3,25%. Details in Vermögen →".
  - **What it carries:** the count, the names and each row's native figure,
    and a link to Wealth instead of a control (UX-DR25 clauses 1–3). Each
    group is shortened by Wealth's own rule: six names, then "+N".
  - **Layout: the section drops its class `grid`.** Measured at 980 px:
    - as a second grid item, the note becomes a second column and the card
      shrinks to 457 px;
    - with `grid-column: 1/-1`, auto-fit stops collapsing empty tracks and
      the card shrinks to 221 px;
    - without `grid`, the card stays 930 px and the note gets its own row.
  - **Code:** the name helpers (`portfolio_live.ex:4023`, `:4072`, `:4133`)
    move into a shared module.
- **B:** the data-quality line gains "2 Konten ohne Wechselkurs · 1 Position
  ohne Preis", linking to `/portfolio`. It is cheaper, but:
  - it carries no names and no figures;
  - it sits six blocks below the total;
  - its links would be the line's first that do not open a securities list;
  - it mixes the view's valuation into a line that counts the catalog.

**Variants — J1.2:**

- **A — recommended:** keep the catalog scope and say so: "25 veraltet im
  Katalog" in the cell, and "25 Wertpapiere im Katalog ohne Kurs seit 7
  Tagen" on the line.
  - This turns the difference from the basis line into a stated one
    (UX-DR26).
  - In the 178 px phone cell the sub-line wraps to two lines, and its glyph
    stays on the first.
  - The list and the count are made to agree: the count leaves out
    benchmarks (`data_quality.ex:99`) and the linked list does not
    (`securities_live.ex:6179-6204`).
- **B:** count held positions only. It has three problems:
  - "Held" means any depot, not the strip's view.
  - It counts never-priced holdings as "veraltet". On the seed it gives 12,
    a third number beside Wealth's 10 and 1.
  - The catalog finding, which is what the line exists for, disappears from
    the Overview.

**Before/after for #1068 and #1087:**

- **#1068:** the line adds "1 Anleihe auf zwei Skalen bepreist", which takes
  the problem severity. It links to `/securities?dq=two_scales`, a new
  `DataQuality` predicate, so the count equals the list. **This reverses a
  settled sentence** (see D-15 in the plan).
- **#1087:** the "Fällig" dates go through `Format.date`.

**Spec:**

- UX-DR25 (DESIGN.md:1415-1435) and the placement rule (DESIGN.md:830).
- UX-DR2 and its 2026-09-14 amendment (EXPERIENCE.md:422, :430).
- UX-DR26, and UX-DR17 (the highest severity present).
- UX-DR19 as amended on 2026-10-03, and the KPI strip (DESIGN.md:1577).

**What the story writes into DESIGN.md:**

- the value card's exclusion note: its wording, groups, "+N" rule and link,
  the section without `grid`, and one `role="status"` region;
- the stale sub-line's "im Katalog" wording;
- the line's two-scales count, which amends the sentence that the line does
  not count that finding.

**Found while drawing:**

1. **`dq=missing_logo` has the same count/list mismatch.** `list_opts` adds
   `is_benchmark: false` (`data_quality.ex:97`), but the list adds only
   `logo_status`. M6 fixes both while it is there.
2. **Between 561 and about 660 px, the strip's dates overflow their cells**,
   by 26 px at 561, 16 at 600 and 6 at 640 (measured). The overflow is
   clipped. Filed at α's opening.
3. **When `without_quote` is 0, the line opens with "4 ohne Anlageklasse"**,
   which has no noun. M6 fixes it on the line it changes.
4. **"Details in Vermögen →" may land on a different scope.** The card reads
   the default view (`dashboard_live.ex:72`, `:121`), but Wealth opens on the
   session's view. Adding `?view=` would also store that choice
   (`ViewScope`). The story decides, and says which it chose in the
   briefing.

---

## Part 2 — J2: what Wealth says about money it cannot value (#1055; the Wealth half of #1068)

**Board:** `design-language/mockups/ux-design-2026-10-04/02-money-notes.html`,
rendered as `02-money-notes--1200.png` and `02-money-notes--390.png`. Plan:
PR α M3 and M7. One pick and two before/afters.

**The data is invented:**

- a "Tagesgeld CHF" account holding 2.000,00 CHF from 14.07.2026, with CHF's
  first stored rate on 01.08.2026;
- three bonds for #1068.

**Before:**

- **The first rate moves the whole balance into the currency effect.**
  `revalue_cash` (`performance.ex:1771-1788`) puts the CHF balance's whole
  value into "Währungseffekt auf Bargeld" on the first rate's day, and into
  the badge's money figure.
- **The contribution note names positions only** (`contribution_table.ex:346-362`,
  filtered at `:390`).
- **`dq-unvalued-cash` prints "USD Settlement (USD)" with no balance**
  (`portfolio_live.ex:2733`).
- **`dq-two-scales` has a fixed sentence about the forward direction.** The
  reverse case and a bond without a stored class count in the totals and are
  named nowhere.
- **ISO dates:** the stale-quote note and the performance basis line
  (`:4109`, `:1692-1701`).

**Variants — J2:**

- **A — recommended:** the contribution note gains the account, in the same
  shape as its positions. It reads "Ein Verrechnungskonto zählte an einigen
  Tagen des Zeitraums null: **Tagesgeld CHF** (2.000,00 CHF, 18 Tage, kein
  Wechselkurs gespeichert). Mit dem ersten Kurs am 01.08.2026 kam sein ganzer
  Saldo in den „Währungseffekt auf Bargeld“ — das ist kein
  Währungsgewinn."
  - Its second sentence renders only when the first rate falls inside the
    period.
  - The remainder row carries the existing `.contribution-unvalued-mark`
    ("Tagesgeld CHF: 18 Tage null").
  - It sits in the same section as both figures that contain the jump, as one
    finding with one note that changes with the period.
- **B:** a sentence in `dq-unvalued-cash`. That section reports today's
  state, so:
  - it has no period;
  - the account has a rate now, so the condition the note exists for is
    gone;
  - its sync button cannot change a past day (clause 3);
  - it sits in another section.

**Before/after:**

- **Native figures** in the unvalued-cash note: "USD Settlement (1.850,00
  USD), US Broker (60,00 USD)". This is the shape `dq-missing-fx` already
  uses (`:4035-4038`).
- **#1068, the forward case:** the existing note keeps its sentence. It also
  names the bond without a stored class, with a neutral "ohne Anlageklasse"
  badge.
- **#1068, the reverse case:** a problem note of its own,
  `dq-two-scales-reverse`.
  - It reads "… (Kurse um 1, gebuchter Preis je Stück um 100) und zählt
    hundertfach zu niedrig in den Summen. Ihre gespeicherten Kurse prüfen —
    ein Kurs um 1 ist kein Prozent vom Nennwert:", and each name links to
    its Quotes tab.
  - It is separate because both the consequence and the fix point the other
    way: here the quotes are on the wrong scale, not the booked quantity.
- **#1087:** the dates go through `Format.date`.

**Spec:**

- UX-DR25 clauses 1–3, the placement rule (DESIGN.md:830) and UX-DR17.
- ADR-0051 §10 and its 2026-10-03 amendment.
- ADR-0052 §4 and its Consequences.
- DESIGN.md's two-scales note and contribution table.

**What the story writes into DESIGN.md:**

- the account sentence and the row marker;
- the reverse-case note and the "ohne Anlageklasse" badge;
- the amended "Settled here" items;
- the native balance in the unvalued-cash note.

**Found while drawing:**

1. **Stacked Wealth notes touch each other:** `[data-role="dq-notes"]` has no
   spacing rule (`.comparison-notes` at `app.css:1411` is the precedent).
   M3 adds it on the surface it changes.
2. **The name inference recognises only government-bond names**
   (`security.ex:400-405`), so every corporate bond without a stored class
   escapes the guard, the seed's own "Placeholder Anleihe 2031 3,25%"
   included. Extending the guard to "has no class" would also flag an
   unclassed share that has risen 20-fold from its booked price. **The guard
   therefore needs a positive bond signal**: the plan's D-15 uses ADR-0052's
   master-data columns.
3. **#1068 reverses two settled statements:**
   - ADR-0052's Consequences says the reverse case is not named;
   - DESIGN.md says the dashboard line does not count the finding.

   That makes it an owner decision, not a conformance repair. The plan's
   D-15 carries it.

---

## Part 3 — J3 and J3.2: the transaction history's month head, and the account on a desktop row (#1083, #1084, #1073; #1090's subtitle)

**Board:** `design-language/mockups/ux-design-2026-10-04/03-history.html`,
rendered as `03-history--1200.png` and `03-history--390.png`. Plan: PR γ U1,
decision D-4.

**How the board is built.** Every frame is a `srcdoc` iframe built from the
live HEEx markup and the German msgstrs. A 390 px frame is therefore a real
390 px viewport, and `app.css`'s 560 px and 900 px blocks fire as on a phone.

**The data** is the seed's September 2026:

- a "Saldo gesetzt" of 1.850,00 USD;
- two buys, 240,00 and 964,90;
- a dividend of 12,50, on "Nordwind Industrie AG" in place of the seed's real
  instrument;
- an Einlage of 1.500,00;
- a sale of 360,00 USD.

**Before:**

- **The head** reads "6 Transaktionen · 2.717,40 EUR · 2.210,00 USD"
  (`transaction_management_live.ex:339–349`; phone at `:412–419`).
  `totals_by_currency/1` (`:1430`) adds `tx_amount/1` (`:1443`) unsigned, for
  every kind. The total mixes:
  - two buys that the rows show as "-";
  - a deposit and a dividend;
  - a balance level;
  - a sale.
- **The rows sign only `@outflow_kinds`** (`:1619`, `:1691`). A positive
  amount carries no "+", and the amount cell has no sign class (`:383`).
- **The filter summary** (`:266`) already gives the per-kind, per-currency
  sums with their basis line.
- **The desktop default columns name no account** (`:37–38`). The phone row
  does (`phone_subject/1`, `:1624`).
- **The price prints at two places** (`:373`).
- **`.phone-row__ids` has no `overflow-wrap`** (`app.css:8032`).
- **The subtitle** reads "Manuelles Kauf- und Verkaufsjournal" (`:95`).

**Variants J3:**

- **A — recommended: the count alone.** The head reads "September 2026 · 6
  Transaktionen".
  - The sums already sit directly above, with their basis line.
  - A signed head would first need correct row signs, and they are not
    correct today (see "Found while drawing").
  - The cost is removing `<.currency_totals>` from the head.
- **B: the signed net per currency, from `Projection.effects/1`.** It reads
  "netto +307,60 EUR · +360,00 USD · Saldo gesetzt nicht enthalten"
  (UX-DR26). It costs more than it looks:
  - DESIGN.md's "subtotals and totals alike" (`:518`, anti-pattern `:706`)
    then requires sign colour on every row, and the Accessibility Floor
    requires "+" on positives.
  - A transfer must flip its sign by the account in view, and net to 0
    unfiltered. A cross-currency transfer has two amounts.
  - B is therefore a second story that has to come before the first.
- **C: turnover by kind — argued against.** It repeats the summary
  (`summarise/1`, `:1412`) without the basis line, grows to four or five
  lines on the phone, and keeps counting a balance level as turnover.

DESIGN.md H2's "the month subtotal follows" holds under all three.

**Variants J3.2:**

- **A — recommended: a "Konto" column after Wertpapier, on by default.**
  - It shows the cash account, which is the account whose view the Betrag
    is. A transfer reads "Demo Cash → Tagesgeld"; a booking with no cash
    account shows its depot.
  - It follows #732's rule that each picker column is the human half of an
    API field (`:27–29`). The phone row stays the condensed form of the
    table (UX-DR27).
  - Cost: one key and one `tx_cell/2` clause. A reader with a saved column
    choice (ColumnPrefs) finds "Konto" in the picker.
- **B: the account muted in the Wertpapier cell,** under the header
  "Wertpapier / Konto". It is the smallest change. But the column then mixes
  two kinds of value, its key no longer matches its API field, and buys and
  dividends still name no account.

**Before/after (no pick needed):**

- **#1073:** `.phone-row__ids { overflow-wrap: anywhere }`, which is the delete
  dialog's R8 fix (`app.css:9839`) moved onto the class. The price and the
  phone row's size go through `stored_figure/1` (`:2014`): 41,1234 and 93,1046
  print as stored, and 24,00 stays 24,00.
- **#1090's history item:** the subtitle reads "Alle Buchungen über alle
  Konten und Depots" (English: "Every booking across accounts and depots").
  It is hidden under 560 px, so there is no phone picture.

**Spec:**

- EXPERIENCE.md: "Every aggregate names what it aggregates", the
  Accessibility Floor, UX-DR26.
- DESIGN.md: `:518`, `:706`, UX-DR27, H2 (`:4000–4001`), R10c.

**What the story writes into DESIGN.md:**

- the head carries the count alone;
- the default columns include Konto, with its rule;
- the price and the phone row's size keep their stored digits;
- `.phone-row__ids` wraps anywhere.

**Found while drawing (each marked: fixed in U1 under D-14, or filed at γ's
opening):**

1. **Fixed in U1.** A cash transfer reads "-200,00" while the filter shows the
   *receiving* account, and the running balance beside it rises by 200
   (`signed_money/2` `:1691`, `account_match?/2` `:1105`, balances `:1069`).
   It is a row defect under every J3 choice, and the spec already fixes the
   answer: the sign is the account's.
2. **Filed.** History amounts carry no "+" on positives and no sign colour on
   rows (`:1694`, `:383`). That is a gap against the Accessibility Floor. It
   changes every row, so it gets its own board.
3. **Fixed with #1073.** `phone_size/1` also rounds the price (`:1649`), and
   the delete dialog's box reads it (`booking_delete_dialog.ex:350`).
4. **Filed.** The price cell carries no currency. On one row a CHF price of
   45,60 sits beside an amount of -964,90 EUR (`:373`); the currency column is
   off by default.
5. **Fixed in U1.** The comment at `:27–29` names a `depot` column that
   `@tx_column_keys` does not have.

**Checked against the assignment:** J3-B's example figure in the brief was
wrong. The six rows net to **+307,60 EUR** and **+360,00 USD**, leaving out
the "Saldo gesetzt"; the board draws the computed figures. Sprint 18's H4 and
H7 boards also drew signed month heads that the code never printed.

---

## Part 4 — J4: reaching and reading trades (#1082, #1089, #1060, #1059, #1074)

**Board:** `design-language/mockups/ux-design-2026-10-04/04-trades.html`,
rendered as `04-trades--1200.png` and `04-trades--390.png`. Plan: PR γ U2,
decision D-4.

**The data follows the seed's section 15:**

- Wrenfield Gardens AG: 780 days, +420,00, +17,8 % p. a.
- Tamarisk Mining Ltd: 600 days, a total loss that no rate solves.
- Brightwater Utilities plc: 460 days, +30,00.
- An invented name stands in for the seed's real 207-day trade.
- The Trades tab is drawn for Nordwind Industrie AG.

**Before:**

- **The page is titled "Cashflow."** `/cashflow?tab=realized` takes that
  title (`income_live.ex:236`). Its subtitle names the facet (`:1399`), but
  it is hidden under 560 px (`app.css:1567`).
- **Reach:** the sidebar highlights "Vermögen" (`app_shell.ex:360–365`), and
  only the Overview card links here (`dashboard_live.ex:618`).
- **#1089, unsigned figures:** the facet prints the result, the return and
  p. a. unsigned (`income_live.ex:473, 493–495, 528–535`). A phone row
  without p. a. shows a bare period return ("-38,9%", "-100,0%").
- **#1060, the Trades tab's formatting:** its dates are ISO
  (`securities_live.ex:2105, 2179, 2219–2220, 2273`), and both "%" columns
  read "+27,07 %" (`signed_percent_or_dash/1`, `:3187`).
- **#1059, the clipped ⓘ pill:** the coarse-pointer rule at `app.css:6245`
  overrides the pill's `width: auto` at `:6117`. With touch emulation the
  pill is 28 × 28 px and its text 189 px wide, so about 50 px fall off the
  left edge.
- **#1074, the English plural:** `gettext("%{quantity} units")` at
  `income_live.ex:366` and `securities_live.ex:2181, :2276`.

**Variants J4:**

- **A — recommended: the top bar reads "Trades" while that facet is open.**
  - The other three facets keep "Cashflow". Titling "Erträge" would reopen an
    ambiguity the information architecture closed.
  - The msgid already exists. The precedent is `classifications_live.ex:207`,
    which titles the page with the tree's name.
  - The title is the page's aria-live region (`app_shell.ex:80`), so
    switching to the facet now announces "Trades".
  - At 390 px, "Trades" stands in a top bar that named nothing before.
  - Cost: one function and one test.
- **B: as built (Sprint 17's G1-A).** The first-look test showed that the
  card works as a path, that nothing else leads here, and that the page does
  not carry its name.
- **C: G1-B,** a sidebar entry with a new glyph and a `/trades` route. Its
  costs, as the 2026-10-01 board listed them:
  - an ADR-0022/ADR-0024 amendment and a new glyph (UX-DR16);
  - a redirect and the `nav_current?` mapping;
  - one member fewer in the facet switch and in the subtitle pair;
  - the tests of four facets.

  At 390 px with the navigation closed, C looks exactly like A.

**Before/after (no pick needed):**

- **#1089:** every result, percent and p. a. gets its explicit sign, in the
  Overview card's form. A figure without p. a. ends in "gesamt", and the
  basis line gains "und nur, wo ein Zinssatz die Zahlungen löst". **This
  overturns a written spec line**, the H1 amendment's "the facet's p. a.
  cells stay unsigned". The Accessibility Floor's explicit sign outranks it,
  and the merge adopts the reversal with this board.
- **#1060:** dates go through `Format.date` and "%" through `signed_pa/1`
  (`:2314`): "14.03.2024", "+27,1%". The board shows why: the spaced "%"
  wraps onto its own line in the narrow column, and an ISO date breaks at its
  hyphen on the phone.
- **#1059:** under `pointer: coarse` the labelled pill keeps `width: auto`
  (rule ④). The renderer has a mouse, so the board injects the coarse rules by
  hand and says so.
- **#1074:** `ngettext` with `plural_count/1`
  (`transaction_management_live.ex:1663`). The quantity prints with four
  places, so the string reads "1.0000 units" today and "1.0000 unit" after,
  under the app's U1 rule. Plain CLDR would treat "1.0000" as plural; the
  rule decides here. German is unchanged.

**Spec:**

- EXPERIENCE.md: the Accessibility Floor's explicit sign, UX-DR7, UX-DR19 as
  amended by #1014, and UX-DR21 extended.
- DESIGN.md: the Amendment 2026-10-01 for Trades, and UX-DR26.

**What the story writes into DESIGN.md:**

- the rule that the top bar is titled "Trades" while that facet is open;
- the signed figures, "gesamt" where there is no p. a., and both limits in
  the basis line;
- deleting the H1 amendment's "stay unsigned" line and its "kept as built"
  note for #1060;
- the labelled ⓘ pill under a coarse pointer, which DESIGN.md does not
  describe today.

**Found while drawing (fixed in U2 or U5 under D-14, or filed):**

1. **Fixed in U2.** "Realisiert gesamt" prints in the accent colour whatever
   its sign (`.stat strong`, `app.css:1075`; `income_live.ex:379`). A loss
   reads violet "-728,00", and a gain would be unsigned. This repeats the
   KPI-card violation DESIGN.md already records.
2. **Fixed in U2.** The facet's FX note says "kein gespeicherter Kurs"
   (the word for a quote), while the Overview card that sends readers there
   says "Wechselkurs".
3. **Fixed in U5.** The coarse ⓘ circle is 28 px, under UX-DR6's 44 px floor,
   and it is missing from that rule's inventory.
4. **Filed.** `signed_percent_or_dash/1` also formats the security Overview
   and the Holdings tab. #1060 changes only the Trades tab.
5. **Fixed with #1059.** The Holdings tab carries the same labelled pill
   (`:2382`), with the same coarse-pointer defect.

---

## Part 5 — J5: displayed dates and the chart axes (#1061, #1087's Wealth half, #1088)

**Board:** `design-language/mockups/ux-design-2026-10-04/05-dates-charts.html`,
rendered as `05-dates-charts--1200.png` and `05-dates-charts--390.png`. Plan:
PR γ U3. It has three before/after repairs and one pick. The chart frames
are real 390 px iframes in both renders, and a table on the board measures
the Wealth chart's SVG width at eight window widths.

**Before:**

- **Security detail:**
  - the head "Letzter 112,40 (2026-09-30)" (`securities_live.ex:1018`);
  - the Transactions tab (`:2018`);
  - the Quotes table and its phone rows (`:3062`, `:3086`);
  - the manual-quotes note (`securities/manual_quotes.ex:54`).
- **Merge dialogs:**
  - "angelegt 2026-10-03" (`securities/merge_preview.ex:157`, via `:166`);
  - the pair table and its phone lines (`:563`, `:578`);
  - the quote collisions (`:639`);
  - the accounts preview's cells and sentences
    (`portfolio_accounts/merge_preview.ex:250, 269, 489, 501` and `:408,
    618, 723, 742, 750`), although `:190` already uses `Format.date`.
- **Wealth (#1087):**
  - the stale-quote note (`portfolio_live.ex:4109`) and the suspect dates
    (`:2724`);
  - the basis line, with a raw `Date` (`:1693`) and
    `strftime("%Y-%m-%d %H:%M UTC")` (`:1699`).
- **The chart axes (#1088):**
  - dates through `Date.to_iso8601` (`security_chart.ex:564, 567`);
  - values as "112.40" and "12500", with no grouping (`:573–577`);
  - percentages as "+10.4 %" (`:583–585`);
  - labels sized at 9 viewBox units (`app.css:3803`), which render 3.2 px at
    a 390 px window, 4.8 at 560, 6.7 at 768, 8.5 at 1200 and 10.7 at 1440
    (measured).

**After (#1061, #1087 and #1088's locale half):**

- Every displayed date goes through `Format.date`.
- Axis values go through `Format.decimal`, with grouping, and axis
  percentages take the house signed percent: "+10,4%".
- The compute instant reads "berechnet 04.10.2026 00:09 UTC".
- These keep ISO: `<time datetime>`, the ISIN-change input
  (`merge_dialog.ex:99`), the API, MCP, and files.

**Variants J5 (the phone label size):**

- **A — recommended: a label that does not scale.**
  - Rule ② is `font-size: calc(9px * var(--chart-upx, 1))`. The
    `ChartCrosshair` hook already computes `view.width / svgRect.width`
    (`layout_view.ex:768`) and writes it to `--chart-upx`.
  - Rule ③ is `.chart-frame { container-type: inline-size }`. On a chart up
    to about 760 px wide, the five values move inside the plot onto their
    grid lines, over a chart-surface halo. The 56-unit gutter is only 20 px
    at 390.
  - The label group is emitted after the series, so the halo paints over the
    line.
  - The result is 9.0 px at every width. Without script, the label is
    exactly today's.
- **B: fewer ticks.**
  - Under 560 px, a constant (`--chart-upx: 2.9`) replaces the measurement,
    and three of the five values show.
  - The result is 9.2 px at 390 but 13.9 px at 560, and it stays 5.5–6.9 px
    from 640 to 1024.
- **Why A:** the defect is in the scale, not in the phone width. A makes the
  9 px token true at every width, for a few lines in a hook that already
  exists.
  - **Its cost:** on a 1440 desktop the labels go from 10.7 to 9 px.
  - **To keep today's desktop size:** "J5 A with a floor" sets
    `max(1, var(--chart-upx, 1))`.

**Spec:**

- UX-DR19 as amended by #1014.
- `{typography.chart-axis}`, 9 px.
- The Accessibility Floor's charts clause. UX-DR10's "Daten als Tabelle"
  stays the fallback.

**What the story writes into DESIGN.md:**

- `{typography.chart-axis}` is 9 CSS pixels at every chart width.
- Under about 760 px of chart, the values sit inside the plot on their lines.
- The sentences that still prescribe ISO for display are rewritten (finding
  2).

**Found while drawing:**

1. **Filed.** The phone chart rule never applies. `app.css:2846–2849` (16:9,
   `--space-1` under 720 px) is overridden by the later global `.chart-frame`
   (`:3720–3729`, 3:1). Phone charts are therefore 3:1, about 113 px tall.
   Fixing the order would letterbox the `meet` viewBox inside a 16:9 box, so
   it needs its own board.
2. **Fixed in U3.** DESIGN.md still prescribes ISO for display in eight places
   (`:398`, `:959`, `:1073`, `:1636`, `:2758`, `:2981`, `:3479`, `:4137`).
3. **Fixed in U3, which becomes a sweep (see the plan's U3).** More ISO
   displays sit outside both issues' lists:
   - the detail Overview;
   - the Termine tab, where a month shows as "2026-10" (`Format` has no
     month form yet);
   - the custom-range chips;
   - the metric window;
   - the list date cells;
   - the bond strip;
   - the superseded-series sentence, which mixes `Format.date` with ISO.
4. **Fixed in U3, by the same sweep.** An ISO date in running text breaks at
   its hyphen: "2026-/09-22" in a narrow pane.

**Checked against the assignment:** the Trades-tab lines that #1061 lists
belong to #1060 (board 04). #1061's "Holdings tab" prints no date at all.

---

## Part 6 — J6 and J6.2: Wealth at 390 px and the twin names (#1065, #1057, #1086, #1063)

**Board:** `design-language/mockups/ux-design-2026-10-04/06-phone-wealth.html`,
rendered at 1200, 768 and 390 px (`06-phone-wealth--1200.png`, `--768.png`,
`--390.png`). The 768 render shows #1063 only. Plan: PR γ U4. Every
measurement on the board is computed inside its frame.

**J6 (#1065), before:**

- The Positions table (`portfolio_live.ex:2462`) shows Depot · Wertpapier ·
  Stückzahl by default (`:75`).
- At 390 px the table is 445 px wide in a 356 px scroller, and "Stückzahl"
  starts at x 366.
- A full swipe (89 px) cuts the depot. The names are cut only once a picked
  column or a longer name widens the table.
- The "Spalten" toggle (`:2427`) stays visible, although the other pickers
  hide under 560 px.

**Variants J6:**

- **A — recommended: `ul#holdings-phone-rows` (UX-DR27).**
  - Each row shows the name over the depot, with "18 Stück" on the right.
  - Rule ①: the wrapper and the toggle hide under 560 px.
  - Rows are 59 px tall (79 when the name wraps) instead of 32.
- **B: the name pinned to the left edge.**
  - It opens as today.
  - Once swiped, the 302 px pinned name plus the 96 px quantity exceed the
    356 px scroller, so the pin covers 42 px of the quantity ("…KZAHL").
  - It adds a second sticky direction beside #730's right-pinned column.
- **Why A:** UX-DR27 names holdings explicitly, Sprint 18 picked A for the
  Quotes tab (H7.1), and the rows need no gesture. J6 is close to a
  conformance repair; it is drawn as a pick because B is a real option.

**J6.2 (#1057 and its comment), before:** only the name is printed
(`contribution_table.ex:177, 275`; `portfolio_live.ex:2595`). DESIGN.md
leaves it "stated, not settled here".

**Variants J6.2:**

- **A — recommended: an identifier after the name, only where names
  collide.** It is muted mono (rule ② `.twin-id`) with a visually hidden
  "ISIN".
  - The chain is ISIN, else WKN, else "Nr. <id>", following the precedent
    "Split am … · Nr." (`merge_preview.ex:1332`).
  - The collision key is the name in the contribution table, checked over
    the whole payload; in Positions it is the depot plus the name.
- **B: the ISIN on every row.** It costs 12 mono characters on each row, does
  nothing for twins without an ISIN, and duplicates the picker's ISIN column.

**#1086, before → after:**

- **The title.** The `h1` (`app.css:591–603`) is a grid item at `min-width:
  auto`: 144 px of text in a 124 px box, so no ellipsis. Rule ③,
  `min-width: 0`, gives "Konten & De…".
- **The KPI cards.**
  - The label (`portfolio_live.ex:1174–1177`) breaks so that "·" opens its
    second line.
  - "182.450,30 EUR" at 22 px (`app.css:7700`) drops "EUR" below the digits.
  - After: a no-break space before "·", and rule ④ sets 16 px under 560 px,
    the ramp step `{typography.subsection-title}` (18 px still drops "EUR").

**#1063, before → after:**

- **Before:** `.securities-workspace--split` (`app.css:2455–2460`) has an
  implicit `auto` column. It takes the pane's min-content: the tabs are
  `flex: none` and need 759 px. The page measures 785 px in a 768 px window,
  a 17 px sideways scroll.
- **After:** rule ⑤, `grid-template-columns: minmax(0, 1fr)`. The page is
  768 px, and the 742 px tab row scrolls inside itself with its fade.

**Spec:**

- UX-DR27 and Phone lists.
- #730 and #1009, and D6.
- The value slot (EXPERIENCE.md), the top-bar title, and UX-DR15.

**What the story writes into DESIGN.md:**

- the holdings phone row;
- the twin rule, replacing "stated, not settled";
- the KPI clause's replacement (see the spec conflict below);
- the `h1`'s `min-width: 0`;
- the split column's zero floor.

**A spec conflict the board resolves by recommendation.** DESIGN.md's
KPI-card clause (`:1557–1559`, and the `app.css:7717` comment) lets the
currency suffix drop to a second line, while EXPERIENCE.md's value slot
(`:1126–1128`) forbids a value from wrapping. **The board follows
EXPERIENCE.md** (a value never wraps), and the story replaces DESIGN.md's
clause. **To flip by comment:** "J6 suffix may drop" keeps DESIGN.md's
reading, and #1086's KPI half then shrinks to the label's no-break space.

**Found while drawing:**

1. **The spec conflict above.**
2. **The contribution payload has no WKN** (`contribution.ex:94–95`). J6.2's
   WKN step needs the payload extended (it is a payload field, not schema
   bytes). Until then, the chain falls through to "Nr.".
3. **Fixed by J6 A.** The holdings column toggle shows under 560 px.

**Checked against the assignment:** "ISIN, else WKN, else the depot" cannot
tell twins apart by the depot: in Positions the depot is already part of the
row, and the contribution table has one row per security across depots.
Hence "Nr. <id>" as the last step. #1065's "names cut once scrolled"
reproduces only with a wider table; with the defaults, a swipe cuts the
depot.

---

## Part 7 — J7 and J7.2: the touch, focus and colour floor, second pass (#1062, #1064, #1069, #1071, #1085, #1067, #933)

**Board:** `design-language/mockups/ux-design-2026-10-04/07-floor.html`,
rendered as `07-floor--1200.png` and `07-floor--390.png`. Plan: PR γ U5, and
β B2 for #933.

- **Kind:** all before/after, except two picks.
- **Touch frames:** the "After · touch" frames apply the proposed coarse
  rules without the media query (`.as-coarse`), because the renderer has a
  mouse.
- **Sizes:** every size quoted was measured with Playwright.

**Before:**

- **#1062, the row menu.** `.row-context-menu__item` has 8/10 px padding on
  the base button's 34 px floor (`app.css:2589–2602`). Only the sheet rule
  under 720 px enlarges it, so on a tablet the eleven items are 34 px tall.
- **#1062, the range buttons** declare `min-height: 32px`
  (`app.css:3451–3465`) and have no coarse clause.
- **#1062, focus.** `.button-primary/-ghost/-danger` have no
  `:focus-visible` rule, so the delete dialog opens with the browser's ring
  on "Abbrechen", which carries `autofocus`.
- **#1064, the alerts.** `.alert-success` (accent on accent-soft) and
  `.alert-error` (danger on coral-soft) are pixel-identical under coral in
  dark mode, and neither carries a word. The slots are in the transaction
  history, Accounts, Buckets and Classifications; Risk has only the success
  half.
- **#1069:** `.drift-table, .cash-table { margin-top: 1rem }` leaves a 17 px
  band inside all five wrappers.
- **#1071:** a tooltip paragraph inherits `th.num`'s right alignment.
- **#1085, Accounts & depots:**
  - The balance cell prints "Stand" (`gettext("as of %{date}")`), which reads
    as stale.
  - The role select's label is visually hidden while the column head is
    also hidden under 640 px, so the phone card shows "Verfügbares Cash"
    with no label.
  - Under a coarse pointer the chip's × is 24 × 24 and its + 32 × 34.
  - The merge-record arrow is in text-subtle.
- **#1067:** the merge record's ISIN line keys on the recorded choice
  (`merge_records.ex:645–666`), so two ISIN-less securities print an empty
  slot.
- **#933:** `security_logo/1` renders an `<img>` for any local path. A
  missing file shows the broken-image glyph, and the data-quality line
  counts 0.

**After, and the variants:**

- **#1062:**
  - ① Menu items are 44 px under a coarse pointer.
  - ② Range buttons are 44 × 44.
  - ③ `:is(.button, .button-primary, .button-ghost, .button-danger,
    .button-secondary):focus-visible` draws the 2 px accent at a 2 px
    offset.
  - These are real sizes, not Sprint 18's H6 padding-plus-negative-margin.
    Menu items stack, so their hit boxes would overlap, and `.range-buttons`
    clips with `overflow: hidden`.
- **J7 — A, recommended:** the slots become `AppShell.inline_result`. A
  success reads as a note ("Hinweis", the asterisk) and a refusal as a
  problem ("Problem", the octagon). DESIGN.md's `inline-result` already
  says so ("no fourth appearance").
- **J7 — B:** a glyph inside the old alert, with the word only visually
  hidden. The ink stays identical under coral dark, and it keeps a
  component the inventory retires.
- **#1069 and #1071:** ⑤ the margin goes at all five call sites; ⑥
  `.metric-tooltip p { text-align: start }`.
- **J7.2 — A, recommended:** "letzte Buchung 31.03.2026" (English: "last
  booking …"), the KPI strip's own word. It needs its own msgid, because "as
  of %{date}" is shared by four call sites.
- **J7.2 — B:** "unverändert seit …".
- **#1085:**
  - ⑦ The role label is hidden only above 640 px.
  - ⑧ The chip's × and + are 44 × 44 on touch.
  - ⑨ The merge arrow takes text-muted (5.89:1 light, 5.91:1 dark).
- **#1067:** the ISIN line follows the stored ISINs; with neither side
  carrying one, there is no line.
- **#933:** a missing file shows the monogram or flag, and the Overview
  counts it in its existing "ohne Logo" finding.

**Spec:**

- UX-DR6 and its amendment 2, and the Accessibility Floor.
- DESIGN.md → Colors (the focus indicator, the text-subtle rule).
- UX-DR7; the `inline-result`, `data-note` and `bucket-cell.role`
  frontmatter.
- The G2-A merge-records amendment, and UX-DR2's data-quality line.

**What the story writes into DESIGN.md:**

- the row-menu and range-button floors, and why not H6's mechanism;
- the button family's focus ring;
- that the page slots are inline results;
- the flush tables and the tooltip's alignment;
- the role label's breakpoint and the chips' 44 px;
- the muted arrow and the ISIN-line rule;
- the balance cell's words (J7.2);
- that a missing logo file counts as missing.

**Found while drawing (fixed in U5 under D-14 unless marked):**

- **The chart toolbar.** `.chart-toggle` is 32 px with no coarse clause, in
  the same toolbar as the range buttons. Neither class has a
  `:focus-visible` rule.
- **The phone card.** On the same card, the role select is 24 px and "Saldo
  setzen" 34 px under a coarse pointer.
- **The bucket +.** `.bucket-chip-add` declares 22 × 22, but the base
  button's 34 px floor wins its height. This is the H6.2 defect class.
- **Focus.** `.icon-button:focus-visible` changes colours only, so the
  browser's ring still draws.
- **Filed.** #1067's payload records an ISIN choice *as given* even when
  none was required (`security_merge.ex:489, 508, 2573–2577`). The empty slot
  therefore comes from API and MCP merges, and the one-sided cases render
  one too.

**Checked against the assignment:**

- J7's suggested words ("Erledigt" / "Fehler") contradict the spec, which has
  no fourth severity word. The board uses "Hinweis" and "Problem".
- #1085's + renders 32 × 34, not 32 × 32.

---

## Part 8 — J8: copy and dialog states (#1090, #1074's drawer half, #1066, #1072, #944, #945)

**Board:** `design-language/mockups/ux-design-2026-10-04/08-copy-dialogs.html`,
rendered as `08-copy-dialogs--1200.png` and `08-copy-dialogs--390.png`.
Plan: PR γ U6. The copy is before/after with one recommended wording per
string, and there is one pick, J8. The history subtitle is on board 03, and
"1 units" is on board 04.

**Before:**

- **#1090, a newcomer's misreadings:**
  - the Positions basis line explains the API (`portfolio_live.ex:2444–2448`);
  - the theme menu is named "Theme" in German;
  - the wealth card's change reads "YTD";
  - the "Liquiditätsrolle" and "Buckets" heads have no ⓘ;
  - a contribution phone row reads "Abfluss 1.420,00" beside +420,00;
  - the delete dialog says "Das Journal behält die Buchung…".
- **#1074:** "journalisiert" in the edit drawer.
- **#1066:** with a 1:2 split booked, a 4:1 preview reads 120 (the 4:1
  alone) beside 60 (both splits stacked; `splits.ex:585–591`). What actually
  stands is 15.
- **#1072:** `merge_into_existing` assigns the atom `:not_found` to the
  dialog's errors. The render then crashes at `:334` (`Access.get/3`, a
  `FunctionClauseError`, verified), and the LiveView remounts silently.
- **#944:** the findings leave out retired securities' names, so the subject
  falls back to "Wertpapier".
- **#945:** the plan-save refusal is one bare sentence with no row.

**After, and the variant:**

- **The #1090 strings:**
  - **Positions:** "Eine Zeile je Depot und Wertpapier, bewertet zum zuletzt
    gespeicherten Kurs."
  - **Theme:** "Erscheinungsbild".
  - **YTD:** "seit Jahresbeginn". The card is a link and cannot hold an ⓘ,
    so the label needs its own msgid ("YTD" is also a period token).
  - **The two heads** gain an ⓘ:
    - Liquiditätsrolle: "wie ein Verrechnungskonto zählt: Verfügbares Cash
      geht in die Cashquote ein, Reserve und Kreditlinie nicht".
    - Buckets: "Tags für Depots und Verrechnungskonten …".
  - **Contribution:** "Abfluss aus der Position 1.420,00" / "Zufluss in die
    Position …".
  - **The delete dialog:** "Das Audit-Journal hält die Löschung mit allen
    Werten fest; wiederherstellen lässt sich die Buchung nicht."
- **#1074:** "…, und das Journal hält die Änderung fest."
- **J8 — A, recommended:** both "after" cells show the not-computable "—".
  A8's warning gains "…, und die Vorschau zeigt keine Stückzahl danach". The
  reason sits outside the table, because on a phone the table scrolls
  sideways.
- **J8 — B:** the figures stay, and the row gets a "würde abgelehnt" badge.
  The contradicting numbers stay on screen.
- **#1072:** Sprint 18's H8.6 path. The dialog closes, the list reloads, and
  a note reads "„Nordwind Industrie AG“ wurde inzwischen gelöscht; die
  Liste ist neu geladen."
- **#944:** the stored name, in `<bdi>`.
- **#945:** the row first, then the rule: "Positionsziel von „…“ unter „…“:
  höchstens vier Nachkommastellen in Prozent". The category, cash and
  0–100 % refusals follow the same pattern.

**Spec:**

- EXPERIENCE.md → Voice and Tone: impersonal, locale-pure, explanatory, one
  explanation in one place.
- UX-DR11, and UX-DR7 (the value slot: a dash and its reason).
- H2's R10d, H8.6 and H8.8.
- The policy-rule words amendment, and the position-targets amendment.

**What the story writes into DESIGN.md:**

- the Positions basis line, and the two ⓘ definitions with their place under
  640 px;
- the contribution phone row's flow words;
- the delete dialog's journal sentence;
- the wizard's conflict state (J8 A);
- the security dialog's vanished conflict row;
- that findings name retired subjects;
- that plan refusals name their row.

**Found while drawing:**

- **#945's refusal cannot be reached from the screen today.** The plan inputs
  are `type="number" step="0.1"` (`classifications_live.ex:961, 996, 1013`).
  Chromium refuses "8.12" before submitting, so two-decimal targets, which
  the store accepts, cannot be typed. **Fixed in U6:** the inputs take
  `step="any"`, and the server refusal becomes the one the operator meets.
- **Five German strings address the reader as "du"**, against the house
  infinitive. **Fixed in U6.**
- **Three more strings use "journalisiert". Fixed in U6.**
- **The German "Logo verwalten" drops the ellipsis** of "Manage logo…".
  **Fixed in U6.**
- **Filed.** The split preview's table is 769 px wide on the phone, in its own
  scroller.
- **Fixed with #1072.** "Vorhandenes aktualisieren" answers the same vanished
  row differently (an in-dialog alert). The board recommends H8.6 for both
  buttons.
- **Applies to board 02.** Board 02 draws the contribution phone rows with
  today's "Abfluss". The wording above applies there too.

**Checked against the assignment:**

- #1066's numbers (120 beside 60) hold only with a booked 1:2 split, and 60
  is then both splits stacked. The board draws that case.
- #933 does change what renders, so board 07 draws it.

---

## Part 9 — J9: correcting cash already booked from a PP CSV, and two import row repairs (ADR-0053 §6; #1044, #948, #923)

**Board:** `design-language/mockups/ux-design-2026-10-04/09-import-correction.html`,
rendered as `09-import-correction--1200.png` and `09-import-correction--390.png`.
Plan: PR α M2 (the correction) and PR β B4 (the row states).

**Before:**

- **A re-drop says nothing about wrong cash.** A PP CSV dropped a second time
  is all hash hits. The preview says once, above the confirm, "Alle 14
  Einträge sind bereits importiert …" (`imports_live.ex:470-476`,
  `nothing_to_import/1` at `:1390`). It never mentions that the stored cash of
  those rows is PP's gross Betrag (`csv_parser.ex:260`, `:317`).
- **A transfer row with a blank Gegenkonto fails the whole file.** It parses
  clean (`csv_parser.ex:418-419`, `:429`). The apply then fails everything
  with "Zeile 7: counter_cash_account_id darf nicht leer sein"
  (`imports_live.ex:2310-2312`, `changeset_error_text/1` at `:2374-2384`).
- **JSON currency codes are not checked at parse time.** The JSON parser only
  trims and upper-cases them (`json_parser.ex:350-354`). "EURO" fails the
  apply ("Anlegen des Kontos Tagesgeld fehlgeschlagen: currency_code muss
  genau 3 Zeichen lang sein", `:2345-2351`), and "XEU" creates an account in
  XEU without a word.
- **#923:** a security decision whose rows are all hash hits still counts as
  missing (`:1951`). The hint appears (`:478`), and Confirm stays disabled
  (`:487-490`).

**Variants (J9):**

- **A — recommended:** a section of its own, "Bereits importiert, mit
  anderem Betrag".
  - **Where it sits:** after the counts and outside `#pp-import-apply`
    (`:218`), because it needs no mapping.
  - **The finding:** an `attention` note — "5 bereits importierte
    Buchungen weichen von dieser Datei ab: Gebucht ist der Bruttowert
    (Spalte „Betrag“); was das Konto bewegt, nennt die Datei als
    „Gesamtpreis“ …".
  - **The list:** Zeile · Datum · Buchung · Gebucht · Laut Datei ·
    Differenz, signed and in the sign colours, as two-line rows under 560 px
    (UX-DR27). A cross-currency trade lists its settlement legs before and
    after.
  - **The action:** a total per account, then "5 Buchungen korrigieren…"
    inside the note, beside "ein eigener Schritt, unabhängig von „Import
    bestätigen“".
  - **The confirm:** "Gebuchte Beträge korrigieren", in the narrow
    booking-delete modal, with the consequence and the journal sentence:
    "Jede Änderung wird mit dem bisherigen Betrag im Journal festgehalten; die
    Import-Hashes bleiben, wie sie sind, also bucht ein erneuter Import
    derselben Datei nichts."
  - **Its button is primary, not danger:** nothing is lost, because every
    old value stays in the journal and in the file's Betrag.
  - **The result:** an inline note where the section stood: "5 Buchungen
    korrigiert: Girokonto -24,31 EUR, Tagesgeld -1,20 EUR. Das Journal hält
    die bisherigen Beträge."
  - **When nothing differs:** no section and no all-clear badge (UX-DR2).
  - **When the import is confirmed first:** the done page says that the 5
    bookings stayed uncorrected.
  - **Why A:** the finding appears during the routine act. ADR-0050 §3
    stays literal (K8).
- **B — a "Beträge prüfen" mode.**
  - **A second entry point:** a plain re-drop still shows today's silence,
    which is the failure ADR-0053 §6 exists to end.
  - **A mode is state to remember,** and other file types need a refusal of
    their own.
  - **A segmented control,** a facet idiom, on a page that has no facets.

**Conformance repairs (before/after):**

- **Row errors.** A reason joins the existing "Parser-Warnungen" box and the
  "Warnungen" card, and the rest of the file still previews:
  - "Zeile 7: Umbuchung ohne Gegenkonto — Zeile nicht übernommen";
  - "Zeile 12: Währung „EURO“ wird nicht unterstützt — Zeile nicht
    übernommen";
  - ADR-0053 §2 and K5's row: "Zeile 4: Gesamtpreis 1.505,00 passt nicht zu
    Betrag 1.502,50 und Gebühren 2,50 — Zeile nicht übernommen".
- **#923.** The security row takes the account rows' anatomy: "6 Buchungen
  bereits importiert · **nichts anzulegen**", with a basis line ("Keine
  Entscheidung nötig: Der Import bucht für dieses Wertpapier nichts. Eine
  gewählte Zuordnung, etwa ein ISIN-Wechsel, wird trotzdem ausgeführt.").
  Confirm is enabled, and a key-collision row still blocks.

**Spec:**

- ADR-0053 §6 with K5, K7 and K8; ADR-0050 §2–§3.
- UX-DR17 (a finding is a data note, with its remedy inside), UX-DR25, UX-DR27
  and UX-DR2.
- UX-DR19 as amended by #1014; DESIGN.md's "semantic colour wherever a sign
  exists".
- The booking-delete dialog's anatomy.

**What the story writes into DESIGN.md:**

- the section's place, wording and columns, and its phone rows;
- the dialog, joining the `.booking-delete-dialog` selector list;
- why its confirm is primary;
- the result line, the "nothing differs" rule and the done page's line;
- the new row-error reasons.

**Found while drawing (the Imports page; fixed in B4 under D-14 unless
marked):**

- **"Preview" is mistranslated as "Übersicht"** (`default.po:1611-1612`,
  used at `imports_live.ex:155`), the Overview's name. It becomes
  "Vorschau".
- **The row-error box is the accent banner UX-DR17 retired**
  (`app.css:3982-3991`). The board keeps it; B4 makes it an attention note.
- **Other insert rejections still print changeset field names**
  (`:2381-2382`). B4 maps them to the field's label.
- **The import result lists print ISO dates** (`imports_live.ex:627, 651,
  1509`). γ's U3 sweep takes them.
- **Filed.** "Zeile N" counts data rows from 1 (`csv_parser.ex:96`), one less
  than the line a spreadsheet shows. Changing it changes every row message,
  so it is a choice of its own.

**Checked against the assignment:**

- **#1044 and #948 are two parsers.** #1044 is the CSV path and #948 the JSON
  path, so the board shows a CSV pair (with ADR-0053 §2's row) and a compact
  JSON pair.
- **The confirm reads "Import bestätigen"**, not "Übernehmen".
- **For a cross-currency trade, the rate is numerically unchanged:** the same
  stored hub rate on the same date. Only the two legs differ on the board.

---

## Part 10 — J10 and J10.2: the classification screen's category result — its view scope and its currency (#1091's screen half; #1048)

**Board:** `design-language/mockups/ux-design-2026-10-04/10-category-results.html`,
rendered as `10-category-results--1200.png` and `10-category-results--390.png`.
Plan: PR γ U7 (J10) and PR α M5 (J10.2).

**Before:**

- **The view picker steers only the plan editor:** "Soll-Plan für Sicht:"
  (`classifications_live.ex:811-824`).
- **The tree mixes two reads.** "Positionen" and "Wert" come from the global
  EUR valuation (`:52`). "Einstand" and "Ergebnis" come from
  `CategoryResult.for_all_portfolios/2` (`:1857`; `category_result.ex:181`),
  which adds each portfolio's cost in its own base currency.
- **What the board shows:** "Plattformen" reads 7.300,00 = 5.800,00 EUR +
  1.500,00 USD, under a title that says "…gekostet haben, in EUR" (`:677`).
  Wert − Einstand ≠ Ergebnis.
- **The basis line** (`:353`) names neither the scope nor the currency.

**Variants (J10):**

- **A — recommended:** the Wealth page's `ViewSwitcher`, unchanged, in a
  controls row under the detail head (chips, plan dots, "Ansichten").
  - **What follows the chosen view:** every figure in the row. The plan
    editor edits that view's plan; its own select goes, and its head says
    "für Ansicht Langfrist".
  - **The basis line** reads "Ansicht Langfrist · in EUR · Ergebnis: …".
  - **Members outside the view** take the existing `.cat-without-holdings`
    slot ("+2 nicht in der Ansicht").
  - **Its side effect:** a chip is a navigation through `ViewScope`, so a
    view picked here is also active on Wealth. The no-plan deep link moves
    from `?soll_view=` to `?view=`.
  - **Why A:** one scope control and one vocabulary across the app (D4,
    Flow 3). The plan dots were built for this question, and built-in trees,
    which have no editor, get it too.
- **B — the editor's select promoted** to a page-local scope select. It
  avoids a navigation and the cross-page side effect. Its costs:
  - a second kind of scope control, the label pattern D4 removed;
  - "Gesamt"/"Sicht" against "Alles"/"Ansicht" everywhere else;
  - two answers to "which view is active";
  - no plan dots.

**J10.2 — A, recommended: every scope, "Alles" included, is in EUR.**

- **The rule:** a member whose cost was not paid in EUR is left out of
  Einstand and Ergebnis, exactly as the #901 read does
  (`category_result.ex:115`, `in_hub_currency/2` at `:157-162`).
- **The note:** one attention note between the basis line and the tree head
  names it. "1 Position ist in „Einstand“ und „Ergebnis“ nicht enthalten,
  weil ihr Einstand nicht in EUR bezahlt wurde: Harborline Freight Inc
  (Plattformen), Einstand 1.500,00 USD. Im „Wert“ ist sie enthalten."
  - It gives the native figure (UX-DR25 clause 2) and carries no button
    (clause 3).
  - It states the difference in Wert (UX-DR26).
- **Rejected:**
  - **Converting through the EUR hub:** it states a cost nobody paid, or
    needs a new metric, and it would disagree with the API.
  - **Per-currency subtotals:** they break C8-A's columns.
  - **Blanking a mixed category.**

**Spec:**

- ADR-0041 §1, §3 and §4; ADR-0033; ADR-0018 and ADR-0024.
- DESIGN.md D4, C8-A and the issue-873 rows.
- EXPERIENCE.md Flow 3, and Voice and Tone (a scoped figure names its view).
- UX-DR2, UX-DR16, UX-DR25 and UX-DR26.

**What the story writes into DESIGN.md:**

- the controls row with the view switcher on the classification screen, and
  the editor's scope text;
- the basis line naming the view and the currency;
- the note on left-out members, which becomes a disclosure past one member;
- `.cat-result-partial`'s rule, and the "+N nicht in der Ansicht" suffix.

**Found while drawing:**

- **`.cat-result-partial` has no rule in `app.css`.** "1/2" prints as a bare
  third line, with its reason only in a title (`:695-705`). Rule ③ fixes
  that.
- **Filed at γ's opening; not built here.** ADR-0041 §3's per-member
  contribution is never rendered. `security_row/1` (`:603-637`) shows quantity
  and value only, and `result.positions` goes unused.
- **The vocabulary splits:** "Gesamt"/"Sicht" (`:817`, `default.po:2832`)
  against "Alles"/"Ansicht" everywhere else. J10 A removes it.
- **J10 must scope all four tree columns:** Positionen and Wert come from a
  different, global read, and scoping only the category result would put two
  scopes in one row.
