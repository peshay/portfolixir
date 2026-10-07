# UX Design Pass — 2026-10-07, Sprint 20's user-visible items

Scope: **every** rendered change Sprint 20 proposes, held against the living
design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html).
`DESIGN.md` and `EXPERIENCE.md` are the authority, and this document proposes
against them. It runs **on the planning PR, before the batch**, as the
standing rule of 2026-09-20 requires (AGENTS.md → "A UI change is mocked
before it is built").

**Why only two boards.** Sprint 20 has no screen lane (the plan's D-13). The
boards draw only what its money and import stories change on screen:

- PR α's import preview (board 01);
- PR β's money findings, and γ's one new refusal string (board 02).

Every other story changes values inside an anatomy a signed board already
draws, or renders nothing (the plan's D-12).

**The mockups** are in `design-language/mockups/ux-design-2026-10-07/`:

- **One board per lane surface**, with every variant or its before and
  after. Each board links the real `priv/static/app.css` and uses the live
  pages' markup and German labels.
- **Rendering.** Playwright renders each board to PNG (`render.mjs`,
  unchanged from the 2026-10-04 pass), reduced to a 256-colour palette.
- **Real phone widths.** Every frame is a `srcdoc` iframe, so a 390 px frame
  is a real 390 px viewport and `app.css`'s breakpoints fire as on a phone.
- **Who drew them.** Two authors each drew one board against `DESIGN.md`,
  `EXPERIENCE.md` and the review rubric, and checked it by eye at both
  rendered widths. Every size quoted below was measured inside its frame.

**The data is invented:**

- names in the demo seed's style ("Arbolia Inc.", "Wrenfield Gardens AG",
  "Larkspur Rail AG");
- obviously fake identifiers such as `DE000000000L`;
- generic account names ("Test-Cash", "Tagesgeld", "Depot Muster");
- made-up figures and 2026 dates.

**No real instrument, position, balance, account, provider or rate
appears.**

**How a pick is made.** The pick letter is **L**: it skips K, so it does not
collide with ADR-0053's identities K1–K15.

- **The recommendation is the default.** A comment naming another variant
  changes it, and silence adopts it.
- **A before/after board has nothing to pick:** the spec already fixes the
  answer, and the board shows the reader what the words describe.
- **The story that builds a pick writes its anatomy into `DESIGN.md`.**

| Pick | Item | Board | Plan | Kind | Recommended |
|---|---|---|---|---|---|
| **L1** | A file name the stored history never saw (#904) | `01-import-preview` | α A3; the ADR-0050 amendment | variants | **A**: no prefill, Apply waits |
| — | A re-drop with nothing new (#1168); a credit row that nets to nothing (#1118); the parser-warnings note at 390 px (#1140); "Zeile N" (#1128); a fresh instance's portfolio (#1173); the bucket tag starts empty (#1174); the correction's sentence for a JSON file (ADR-0053 A6) | `01-import-preview` | α A1, A2, A5 | before/after | after |
| **L2** | How loud `implausible_quote` is (#1101) | `02-money-findings` | β B4; D-7 | variants | **A**: problem |
| — | A return on a cost basis of zero (#1142); a category below level 32 (#940) | `02-money-findings` | β B3; γ C3 | before/after | after |

**What the merge adopts beyond the picks.**

- **L1 withholds every prefill**, not only "+ Neu anlegen". A name that
  would resolve onto another account through a live or a former name gets
  the same row state. That is ADR-0050 §2's second half (Part 1, ①).
- **The "found while drawing" items carry their verdicts:**
  - **Fixed in the story that touches the surface (D-14):** fourteen items,
    five from board 01 and nine from board 02.
  - **Filed at the merge, each under its area tracker:** five items. From
    board 01: the done page names no portfolio record it created; a JSON
    row error's "Zeile N" names no line of the file; a row's count does not
    follow the operator's choice; "Transaktionen ansehen" reads as plain
    text. From board 02: a classification tree is unreadable well before
    its 32-level cap (`needs-decision`, with its recommended answer).
  - **Decided without an issue:** the value card stays silent about a
    wrongly valued holding, because the data-quality line is the
    Overview's alarm.
  - **A comment on #1112:** the security's own pages get an
    implausible-quote note in #1112's story.

---

## Part 1 — L1: a file name the stored history never saw, and the import preview's before/afters (#904; #1168, #1118, #1140, #1128, #1173, #1174; ADR-0053 §6 for a JSON file)

**Board:** `design-language/mockups/ux-design-2026-10-07/01-import-preview.html`,
rendered as `01-import-preview--1200.png` and `01-import-preview--390.png`.

- **Frames.** Every frame is a `srcdoc` iframe built from the live markup of
  `imports_live.ex` (`render_preview/1`, `render_done/1`) and `AppShell`
  (`data_note`, `area_tabs`). A desktop frame is 980 px (1200 − 220 sidebar).
  A phone frame is a real 390 px viewport, where `app.css`'s 720 px and 560 px
  blocks fire.
- **CSS.** "Heute" frames render `app.css` as shipped. "Nachher" and variant
  frames also get the board's `<style id="proposal">`, which holds the only
  new rules.
- **Data.** Accounts are "Test-Cash", "Tagesgeld" and "Tagesgeld Extra"; the
  depot is "Depot Muster". Figures and 2026 dates are invented.
- **The pick letter is L.** It skips K, so it does not collide with ADR-0053's
  identities K1–K15.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **L1** | A file cash-account or depot name with no hash hit, in a file whose other names have hits (#904) | variants | **A** |
| — | A re-drop whose rows are all hash hits (#1168) | before/after | — |
| — | A sale whose cash would be 0 or less once its negative tax is split off (#1118) | before/after | — |
| — | The parser-warnings note at 390 px (#1140) | before/after | — |
| — | "Zeile N" counts as a spreadsheet does (#1128) | before/after, value only | — |
| — | A fresh instance with no portfolio (#1173) | before/after | — |
| — | The bucket tag starts empty (#1174) | before/after | — |
| — | The correction section's sentence for a JSON file (ADR-0053 §6) | before/after, one sentence | — |

### ① L1 — #904: a file name the stored history never saw (variants)

**Before.**

- **The scenario.** The instance imported Test-Cash, Tagesgeld and Depot
  Muster from Portfolio Performance. In PP the operator renames "Tagesgeld"
  to "Tagesgeld Extra" and exports again.
- **Every row under the new name is a hash miss.** Account and depot names
  are content-hash inputs (`ImportHash.parts/2`).
- **The name resolves to nothing.** It is neither a live name nor a former
  name. `prefill/2` (`imports_live.ex:1703`) therefore gives "+ Neu anlegen:
  Tagesgeld Extra", and the row reads "13 Buchungen neu".
- **One confirm double-books the history.** It creates "Tagesgeld Extra" and
  books one new interest payment plus Tagesgeld's 12 earlier bookings a
  second time.
- **The economic layer does not catch it.** The #533 layer (`DedupKey`)
  compares *resolved* account ids, and a newly created account holds none of
  the stored bookings.

**The signal** (ADR-0050 §2 as amended on this PR): a file cash-account or
depot name with zero hash hits, live or retired, in a file whose other names
in the same portfolio do have hits.

**Variants:**

- **A — recommended: no prefill.**
  - The select stays on its empty state, "Entscheiden…" (msgid "Decide…",
    the ambiguous row's).
  - An `attention` data note sits under the select, in the place the
    ambiguous note (`data-role="mapping-ambiguous"`) already takes. Its
    `data-role` is `mapping-unseen-name`.
  - "Import bestätigen" is disabled and described by the existing
    `#import-missing-hint`: "Vor dem Import noch zuzuordnen:
    Verrechnungskonto: Tagesgeld Extra" (`aria-describedby`).
  - Once the operator picks "Tagesgeld", the existing "Zuordnung merken" box
    appears, ticked (G4-A): "„Tagesgeld Extra“ wird früherer Name von
    Tagesgeld; ein künftiger Import ordnet den Namen selbst zu." The confirm
    unlocks.
  - The note stays after a choice, as the ambiguous note does, so the row
    does not reflow.
- **B — the prefill stays "+ Neu anlegen".** The same note is shown and the
  confirm stays enabled.

**Why A:**

- **It fails closed.** Re-dropping the export is the routine act. A note
  beside an enabled confirm only guards the reader who already suspects
  something, so under B the double booking stays one click away.
- **Nothing new to learn.** It is ADR-0050 §4's ambiguous row (board 04b):
  no prefill, a note under the select, and the confirm described by the
  still-to-map hint.
- **One small code change.** It is one more outcome of `prefill/2` (`:1702`),
  which then also reads the row's hash hits, returning `""`.
  `cash_row_state/2` and `depot_row_state/2` already read such a row as
  missing, because `decision_needed?/3` is true for every row that is not
  ambiguous.
- **A genuinely new account costs one click.** For example, a fixed-term
  account opened in PP and exported with the old history. A first import is
  untouched (no name has hits), and so is a converter file of fresh rows.
- **A renamed account is remembered.** After its first choice, the next drop
  prefills it through the former name.
- **The spec forbids the silent default.** EXPERIENCE.md → Import pipeline
  (`:243`): "Never silently defaults." A prefill that books a history twice
  is that default.

**Strings** (new; everything else on the row already exists):

| | English (msgid) | German |
|---|---|---|
| Cash row note | No booking under this name has been imported yet, though the file's other names have. If the account was renamed in Portfolio Performance, choose the existing account here; otherwise “+ Create new”. | Unter diesem Namen ist noch keine Buchung importiert, unter den anderen Namen dieser Datei schon. Wurde das Konto in Portfolio Performance umbenannt, hier das bestehende Konto wählen, sonst „+ Neu anlegen“. |
| Depot row note | No booking under this name has been imported yet, though the file's other names have. If the depot was renamed in Portfolio Performance, choose the existing depot here; otherwise “+ Create new”. | Unter diesem Namen ist noch keine Buchung importiert, unter den anderen Namen dieser Datei schon. Wurde das Depot in Portfolio Performance umbenannt, hier das bestehende Depot wählen, sonst „+ Neu anlegen“. |

**Measured:**

- **980 px.** The select is 489 × 34 and the note 489 × 90, with a 373 px
  body. The still-to-map hint is 933 × 42.
- **390 px.** The select is 295 × 34 and the note 295 px wide. Its body keeps
  180 px beside the severity word (note 162 px tall). With rule ① it wraps
  under the word and gets 269 px (note 134 px tall). The hint is 358 × 63,
  and the remember block is 295 × 71.

**CSS.** The note joins rule ① below (the phone wrap). It has no rule of its
own.

**What the story writes into DESIGN.md** (Import preview, the 2026-09-26
amendment's row rules):

- the unseen-name signal;
- that such a row gets no prefill, the note and its two strings;
- that it is counted missing in the still-to-map hint;
- that the note stays after a choice;
- that a first import and a file with no hits elsewhere are unaffected.

**Settled by the amendment, not only for `:none`.** The signal withholds
**every** prefill, including one that resolution would give through a live
or a former name. ADR-0050 §2's second half is the case that matters: a
rename in Portfolio Performance onto a name another account carries makes
the prefill name that other account, which "looks legitimate, and the
history would land there a second time". A name with no hash hit in a file
that otherwise overlaps the stored history is suspect whatever it resolves
to, and the row is drawn the same way in both cases. The story pins it with
P1's variant onto a live name.

### ② #1168 — a re-drop whose rows are all hash hits (before/after)

**Before.**

- **The file opens like a fresh import.** In order: the bucket tag "für neue
  Konten", a select on every account and depot row (a depot row has two),
  then the securities.
- **The answer comes last.** Only at the end, above the confirm, does the
  page say "Alle 47 Einträge sind bereits importiert. Der Import legt nichts
  an: keine Buchung, kein Konto, kein Depot, kein Wertpapier."
  (`nothing_to_import/1`, `:1468`, rendered at `:519-523`).

**After:**

- **The same `note` leads the preview.** It sits under "Quellformat: CSV" and
  before the cards. It is said once and no longer repeated above the confirm.
- **A mapping row with no new booking shows no select.**
  - Its count keeps the existing "N Buchungen bereits importiert · **nichts
    anzulegen**".
  - In the select's place, `.mapping-target` holds one `.mapping-basis`
    line, `data-role="mapping-nothing-new"`. This is the anatomy the #923
    security row took on board 09 ③.
  - A depot row loses its cash select too. Above 720 px it takes the cash
    rows' two columns (rule ③), so all rows read alike.
- **What Apply sends is unchanged.**
  - A read-only row carries its prefill as hidden inputs under the same
    names: `cash[<key>]`, `depot[<key>][target]` and `depot[<key>][cash]`.
  - `mapping_from_params/2`, `mapping_complete?/1` and
    `build_apply_params/2` therefore see what they see today.
  - "Import bestätigen" stays enabled. It writes nothing and reports every
    duplicate with its layer.
- **The rule is per row, so it holds in a mixed file too.** One exception: a
  cash row that a depot row *with* new bookings names as its cash account
  (`"pp:<name>"`) keeps its select. That depot's link reads it
  (`depot_cash_ok?/3`, `:2008`).
- **Nothing is lost by hiding the select.** A remap of a row with nothing
  new books nothing. Its one effect would be "Zuordnung merken", and the next
  file that brings this name a new booking shows the select again.

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Read-only row line | No mapping needed: the import books nothing under this name. | Keine Zuordnung nötig: Der Import bucht unter diesem Namen nichts. |
| Lead note | unchanged (`nothing_to_import/1`) | unchanged |

The line follows #923's "Keine Entscheidung nötig: Der Import bucht für
dieses Wertpapier nichts." The brief's shorthand "nichts neu" is carried by
the count's bold "nichts anzulegen" and this line. **To flip by comment:**
"#1168 nichts neu" makes the line "Nichts neu — keine Zuordnung nötig." /
"Nothing new — no mapping needed."

**Measured:**

| | 980 px | 390 px |
|---|---|---|
| Lead note | 933 × 36 (one line) | 358 × 72 (three lines) |
| Read-only line | 489 × 17 (one line) | 295 × 34 (two lines) |
| Mapping row | 77 px high; source 349, target 489 | — |
| Frame height | 1542 → 1530 px | 2141 → 2086 px |

At 980 px the read-only depot row matches the cash rows' columns. The frame
heights are for this three-row file.

**CSS (rule ③).** `.mapping-row.depot:has(> .mapping-target:last-child)` takes
`minmax(10rem, 1fr) minmax(14rem, 1.4fr)`. It sits under `min-width: 721px`,
so this (0,3,0) selector cannot override the 720 px one-column block.

**What the story writes into DESIGN.md:**

- the lead position of the nothing-to-import note;
- the read-only row and its line;
- the cash-row exception;
- that Apply's parameters are unchanged.

The 2026-09-26 amendment's sentence "A file with nothing new at all says
once, above the confirm …" becomes "… at the head of the preview".

### ③ #1118 — a sale whose cash would be 0 or less once its negative tax is split off (before/after)

**Before.**

- **The row.** The file's row 7: Stück 0,25 · Kurs 30,00 · Betrag 7,50 ·
  Gebühren 9,90 · Steuern -12,40 · Gesamtpreis 10,00.
- **It passes ADR-0053 §2.** The readings agree: 7,50 − (9,90 − 12,40) =
  10,00.
- **Its parent would be credited a negative amount.** Under §5 the negative
  tax becomes a `tax_refund` companion and the parent is credited
  G − r = 10,00 − 12,40 = −2,40 (`booked_cash/4`, `csv_parser.ex:430-433`).
- **The preview is silent.** It counts the row as a "Verkauf" with no
  warning (Einträge 13 with the companion; Verkauf 2).
- **The apply skips it.** `unimportable/1` (`applier.ex:1169`) skips the
  sale, and `process_companion/3` (`:1073`) skips the refund with it.
- **The only trace is the done page,** in the applier's own English:
  "Zeile 6: skipped: zero or missing gross_amount for sell" and "Zeile
  6.tax_refund.1: skipped: the row it was split from (row 6) was not
  imported".

**After.** The parser refuses the row as a row error in the existing
parser-warnings note (the J9 row-error frame, DESIGN.md amendment
2026-10-06):

- the "Warnungen" card counts it;
- the row and its refund leave the counts (Einträge 11, Verkauf 1);
- the rest of the file previews and imports.

The frame numbers the row as #1128 does.

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Reason | sell with Gesamtpreis %{total} and a tax refund of %{refund}: %{rest} would remain for the sale — row not imported. Book the sale by hand, and the refund as a tax refund of its own. | Verkauf mit Gesamtpreis %{total} und Steuererstattung %{refund}: Dem Verkauf blieben %{rest} — Zeile nicht übernommen. Den Verkauf von Hand buchen, die Erstattung als eigene Steuererstattung. |
| As rendered | Row 7: sell with Gesamtpreis 10,00 and a tax refund of 12,40: -2,40 would remain for the sale — row not imported. Book the sale by hand, and the refund as a tax refund of its own. | Zeile 7: Verkauf mit Gesamtpreis 10,00 und Steuererstattung 12,40: Dem Verkauf blieben -2,40 — Zeile nicht übernommen. Den Verkauf von Hand buchen, die Erstattung als eigene Steuererstattung. |

How the reason is written:

- **The pattern is the existing one.** The cells come as the file wrote
  them, then "— row not imported", as the Gesamtpreis mismatch does
  (`reading_message/3`).
- **The number format is the file's.** `%{total}`, `%{refund}` and `%{rest}`
  use the file's notation, as `(erwartet …)` does (`Decimals.format_de/1`);
  `%{refund}` is the magnitude.
- **The remedy is its own sentence,** the way the key-collision text ends.
- **"Steuererstattung", not the brief's "Steuerrückerstattung".** The remedy
  is booked in Portfolixir, and the booking drawer labels the kind
  "Steuererstattung" (`TransactionKindLabel`, msgid "Tax refund").
  "Steuerrückerstattung" is PP's CSV label, which the operator does not meet
  in the drawer.
- **What "by hand" means, for the handbook.** A sale's cash must be above
  zero (`validate_gross_amount_sign/1`). The operator therefore books three
  things: the sale at its Betrag 7,50, the fee 9,90 as "Gebühren", and the
  refund 12,40 as "Steuererstattung". Together they move the Gesamtpreis,
  10,00.
- **Only a credit row can reach this,** because a debit's parent is debited
  G + r. A *Dividende* or *Zinsen* row of the same shape takes the same
  branch. The story either gives each kind its own sentence (one msgid per
  kind, as the account errors do) or pins that PP writes the shape only on a
  sale.

**Measured:**

- **980 px.** The note is 933 × 91, and its list is 818 px wide (two lines).
- **390 px, with rule ①.** The note is 358 × 168, and its list 332 × 87 (five
  lines).

**CSS.** None.

**What the story writes into DESIGN.md:** one more reason in the 2026-10-06
amendment's list, with both strings.

### ④ #1140 — the parser-warnings note at 390 px (before/after)

**Before.** The note is a flex row: the glyph, the word "ACHTUNG", then the
body (`[data-role="parser-warnings"] .data-note__body { flex: 1 }`,
`app.css:4222`). At 390 px:

- the glyph and the word keep their own column down the whole note: glyph 14
  px, "ACHTUNG" 59 px, and two 8 px gaps;
- the head line and the `<pre>` get what is left.

**After.** Under 560 px the note wraps:

- the glyph and the word form a heading row;
- the body (the "Parser-Warnungen" head line with its copy button, then the
  rows) takes the note's full width.

Above 560 px nothing changes. The rows are the same in both frames (#1118's
sentence and #1128's numbers), so only the widths differ.

**Measured** (390 px viewport; the note is 358 px wide in both frames):

| | Today | After |
|---|---|---|
| Row list (`.parser-warnings__rows`) width | 243 px | 332 px |
| Height the three rows need | 243 px | 174 px |
| Third row visible | no — the list's 12rem scroller (192 px) hides it | yes |
| Note height | 248 px | 255 px |

**CSS (rule ①).** Under `max-width: 560px` the note gets
`flex-wrap: wrap`, and its `.data-note__body` gets `flex-basis: 100%`. It is
the same rule board 09 ②b gave the correction note, written as **one selector
list**: `[data-role="parser-warnings"]`, `[data-role="mapping-unseen-name"]`
(L1) and `[data-role="mapping-ambiguous"]` (found while drawing 8). The
correction story adds `#import-correction .data-note` to the same list rather
than a copy.

**What the story writes into DESIGN.md:** the phone wrap of a data note that
carries a list or a remedy, and which notes are in the list.

### ⑤ #1128 — "Zeile N" counts as a spreadsheet shows the file (before/after, the value only)

**Before.** The CSV parser numbers data rows from 1 (`Enum.with_index(1)`
over the rows after the header, `csv_parser.ex:111`). The row a spreadsheet
shows as 7 is therefore "Zeile 6".

**After.** The header is row 1 and the first booking row 2:

- **The value changes everywhere a CSV row is named:** the parser warnings,
  the receiving-side warning ("booked once, from that row") and every list on
  the done page.
- **The anatomy changes nowhere.** Both frames carry rule ①, so only the
  number differs: "Zeile 6: Umbuchung ohne Gegenkonto — Zeile nicht
  übernommen" becomes "Zeile 7: …".
- **The board shows the file as a spreadsheet beside the frames,** with row 7
  highlighted.

**Strings.** None new; "Row %{row}: %{message}" is unchanged.

**Measured.** No size change: the note is 358 × 116 px in both frames.

**For the story:**

- **The split-off refund's row id moves with it.** A refund's
  `source_row` is `"<N>.tax_refund.1"`, built from the parent's number.
- **A stored note moves with it too.** The refund's note reads "Auto-split
  tax refund from row N" (`csv_parser.ex:328`, `json_parser.ex:183`) and is
  stored with the booking. New ones name the new number, and old ones keep
  theirs.
- **Nothing books twice.** Neither the row number nor the note is a hash
  input (`ImportHash.parts/2`).
- **JSON is not touched** (found while drawing 6).

**What the story writes into DESIGN.md:** the 2026-10-06 amendment's
sentence "The 'Row N' prefix and its numbering are unchanged (issue 1128, a
choice of its own)" becomes "a CSV row is numbered as a spreadsheet shows
it, the header being row 1".

### ⑥ #1173 — a fresh instance with no portfolio (before/after)

**What the code does:**

- **The page passes no portfolio.** `build_apply_params/2` (`:2082`) leaves
  the choice to the applier.
- **The applier resolves one.** `resolve_portfolio(nil, _)`
  (`applier.ex:697`) calls `Portfolios.default_portfolio(Actor.import_session())`
  (`portfolios.ex:44-55`).
- **With no portfolio it creates one,** named **"Default"** with base
  currency **EUR** and journaled under the import actor. The admin list
  "Portfoliodatensätze (Kompatibilität)" under Konten & Depots shows it with
  source "Import", and everything the import creates binds to it.
- **With one or more portfolios it books into the earliest.**
- **Before the apply, the preview counts on an empty portfolio.**
  `import_portfolio_id/1` (`imports.ex:159`) gives `nil`, so every row is
  new. Nothing on the page names the portfolio.

**The MCP prompt `first_setup`** (`mcp-server/src/prompts.ts:126`, step 3)
says today:

> "Group with buckets and views, not with portfolios: a portfolio record is
> an internal compatibility container (ADR-0024),
> portfolixir.portfolios.create is deprecated, an account created without
> one lands in the first portfolio, and every import books into that first
> portfolio."

It does not say that on a fresh instance the import creates that first
portfolio, or what it is called.

**After.** A second muted line under "Quellformat", shown only when no
portfolio exists. With a portfolio there is nothing to say (UX-DR2).

**Strings:**

| | English (msgid) | German |
|---|---|---|
| Fresh-instance line | No portfolio record yet: the import creates “%{name}” (%{currency}) and books into it. | Noch kein Portfoliodatensatz: Der Import legt „%{name}“ (%{currency}) an und bucht darin. |
| As rendered | No portfolio record yet: the import creates “Default” (EUR) and books into it. | Noch kein Portfoliodatensatz: Der Import legt „Default“ (EUR) an und bucht darin. |

- **"Portfoliodatensatz" is the admin list's word** (msgid "Portfolio records
  (compatibility)"), so the line points at the one place the operator will
  meet the record again.
- **The name and currency are placeholders** filled from what
  `default_portfolio/1` creates. "Default" is stored data, like the bucket
  name "PP Import …", and is not translated.

**Measured.**

| | 980 px | 390 px |
|---|---|---|
| The line | 933 × 18 (one line) | 358 × 39 (two lines) |
| Frame growth | +60 px | +83 px |

The growth includes the section's 16 px grid gap.

**CSS.** None (`<p class="muted">`).

**What the story writes into DESIGN.md:** the line, its condition and its
string.

**Whether the MCP prompt changes** (to say the first import creates
"Default") is the plan's call. It is not rendered output.

### ⑦ #1174 — the bucket tag field starts empty (before/after)

**Before.** The field is prefilled with `default_bucket_tag/0` (`:1660`),
`"PP Import #{Date.to_iso8601(Clock.today())}"`. Every import that creates an
account therefore also creates a dated tag bucket, unless the operator clears
the field or ticks "Kein Tag".

**After.** `blank_mapping/0` (`:1642`) starts the field as `""`, and it shows
its existing placeholder, "z. B. PP Import" (msgid "e.g. PP Import").

- **The apply needs no change.** An empty field already means no tag:
  `effective_bucket_tag/1` trims it to `nil`, and `apply_bucket_tag(nil, _)`
  is a no-op.

**Strings.** None new.

**Measured.** The input is 879 × 34 at 980 px and 324 × 34 at 390 px; no
height changes.

**CSS.** None.

**What the story writes into DESIGN.md:** the field starts empty. The
sentence over it and the checkbox are found while drawing 5.

### ⑧ ADR-0053 §6 — the correction section for a Portfolio Performance JSON file (before/after, one sentence)

Board 09's section (pick J9 = A, signed) was checked line by line for "CSV".
**The word appears nowhere:**

- the heading, "Bereits importiert, mit anderem Betrag";
- the columns, Zeile · Datum · Buchung · Gebucht · Laut Datei · Differenz;
- the button, the dialog and the result line;
- the done page's "Dieselbe Datei erneut ablegen, um sie zu korrigieren."

**But the note's first sentence names two CSV columns:** "Gebucht ist der
Bruttowert (Spalte „Betrag“); was das Konto bewegt, nennt die Datei als
„Gesamtpreis“." A JSON v1 file has neither column. It states the cash as
`amount`, with the fees and taxes in `units`. That sentence is the one line
the board changes. It now names the Portfolio Performance file, so it holds
for either format. Everything else on board 09 stands.

**Strings:**

| | Text |
|---|---|
| Before (board 09, DE) | 5 bereits importierte Buchungen weichen von dieser Datei ab: Gebucht ist der Bruttowert (Spalte „Betrag“); was das Konto bewegt, nennt die Datei als „Gesamtpreis“. Die Differenz sind die Gebühren und Steuern der Zeile. |
| After (DE) | 5 bereits importierte Buchungen weichen von dieser Datei ab: Gebucht ist der Bruttowert; was das Konto bewegt, nennt die Portfolio-Performance-Datei. Die Differenz sind die Gebühren und Steuern der Zeile. |
| After (EN msgid, plural) | %{count} bookings already imported differ from this file: what was booked is the gross value; the Portfolio Performance file states what the account moved. The difference is the row's fees and taxes. |

**Measured.** The note body is 764 × 80 px at 980 px in both frames. At
390 px there is no picture: the section is board 09's.

**What the correction story writes into DESIGN.md:** the sentence in its
format-neutral form.

### Spec

- **ADRs:** ADR-0050 §2 (as amended on this PR), §3 and §4; ADR-0053 §5 and
  §6; ADR-0024 (the internal default portfolio).
- **UX rules:** UX-DR17 (a finding is a data note with its remedy beside
  it) and UX-DR2 (no all-clear).
- **A disabled confirm states its reason as text** (the merge dialog's rule,
  DESIGN.md `:3618`). The Imports page meets it through
  `#import-missing-hint`, which is wired as the confirm's
  `aria-describedby` (#475).
- **EXPERIENCE.md** → Import pipeline (`:243`): "Never silently defaults."
- **DESIGN.md:** the amendment of 2026-09-26, Import preview after ADR-0050
  (`:2889`); the amendment of 2026-10-06, rows that fail alone (`:5090`).
- **Boards:** 04b (the ambiguous row) and 09 (J9 A, the row-error frame, the
  #923 row and rule ②b).

### Found while drawing (the Imports page)

1. **The done page prints the applier's internal skip reasons in English.**
   - The reasons carry ledger field names: "skipped: zero or missing
     gross_amount for sell" and "skipped: the row it was split from (row 6)
     was not imported" (`unimportable/1`, `applier.ex:1166-1171`;
     `process_companion/3`, `:1073-1081`; rendered at
     `imports_live.ex:719`).
   - A split-off refund is named by its internal id, "Zeile 6.tax_refund.1".
   - The heading is a manual plural, "%{n} nicht importierbare(r)
     Datensatz/Datensätze übersprungen:" (`gettext`, `:713`); EXPERIENCE.md's
     plural rule calls that drift.

   **Fix in the story (D-14):** the #1118 and #1128 stories touch these
   lines.
2. **"Einträge" and "Anzahl pro Art" disagree when a row splits off a
   refund.** The card counts companions (`total_entries/1`, `:1952`), and the
   chips count top-level entries only (`Preview.counts_by_kind/1`). The
   #1118 "Heute" frame reads Einträge 13 over chips that add to 12, and no
   "Steuererstattung" chip. **Fix in the story (D-14):** count a companion
   under its kind.
3. **On a file that creates nothing, the bucket-tag panel still asks for a
   tag "für neue Konten".** It changes nothing (`apply_bucket_tag/2` is a
   no-op without a created account). Hiding it under the lead note's
   condition (`total.new == 0`) leaves Apply's parameters unchanged: an
   absent `bucket_tag` keeps the mapping's value. **Fix in the story
   (D-14)** (#1168).
4. **The done page names no portfolio record**, even on a fresh instance
   where the import created "Default". Its cards count securities, cash
   accounts and depots, and `Result` does not record a created portfolio.
   **File** at the merge (the UI batch).
5. **With #1174's empty default, the bucket-tag panel's text no longer
   fits:**
   - The sentence over the field, "Die von diesem Import angelegten Konten
     erhalten den Bucket-Tag:", promises a tag that is not there. Proposed:
     "Optional: a bucket tag for the accounts this import creates." /
     "Optional: ein Bucket-Tag für die Konten, die dieser Import anlegt."
   - The checkbox "Kein Tag – die neuen Konten bleiben ohne Bucket" says
     what the empty field already means. Dropping it leaves `bucket_skip`
     false, and the apply is unchanged for an empty field.

   **Fix in the story (D-14)** (#1174).
6. **A JSON file's "Zeile N" is not a line of the file.** It is the N-th
   object of its `transactions` array (`json_parser.ex:125`). After #1128 the
   one word means two things. **File** at the merge: a JSON row error
   names its entry ("Eintrag N"), which needs its own string and board.
7. **A row's count does not follow the operator's choice.** After picking
   "Tagesgeld" for "Tagesgeld Extra" (L1 A), the row still reads "13
   Buchungen neu", though the apply's economic layer will skip the 12
   already booked. The counts are computed once per preview under the
   automatic resolution; `mapping_changed` (`:769`) does not recount, and
   recounting costs a dry run per change. **File** at the merge.
8. **The ambiguous row's note** (`data-role="mapping-ambiguous"`) is in the
   same place as L1's note. At 390 px its body keeps 180 px beside the word.
   **Fix in the story (D-14):** it joins rule ①'s selector list, which the
   board's proposal block already shows.
9. **"Transaktionen ansehen" on the done page reads as plain text.** It is a
   `.button-secondary` link, which `app.css` defines only as a text colour
   (`:7941`, a Tax-page rule). It renders as muted text beside the primary
   "Weitere Datei importieren", top-aligned in the flex row. Risk and Tax use
   the class too. **File** at the merge (the UI batch).

### Checked against the assignment

- **"bitte wählen" is "Entscheiden…".** The app's empty select state is
  msgid "Decide…", the ambiguous row's. The board reuses it rather than
  adding a string.
- **"nichts neu" on a read-only row** is the existing count's bold "nichts
  anzulegen" plus one `.mapping-basis` line in #923's wording. The comment
  that flips it is given under ②.
- **"Steuerrückerstattung" became "Steuererstattung",** the drawer's label
  (reason under ③).
- **#1128's "Zeile 7" in #1118's frames.** Sprint 20 ships both, so the
  after frames number rows as a spreadsheet does. The "Heute" done page keeps
  today's "Zeile 6".
- **Apply's parameters do not change for #1168 or #1174:** hidden inputs
  under the same names for #1168, and an empty field read as no tag for
  #1174. `mapping_complete?/1` is untouched.
- **⑧ is drawn on substance, not the literal word.** "CSV" does not appear
  in board 09's heading or its explanatory line, but the line names two CSV
  columns. If the brief meant the literal word only, ⑧ reduces to "nothing
  changes".
- **No real data.** Every name, figure, date and identifier on the board is
  invented. The tag "PP Import 2026-10-07" is today's default format, and
  "Default" is the code's constant.

---

## Part 2 — L2: a quote that does not match the holding's own bookings (#1101); a return on a cost basis of zero (#1142); a category below level 32 (#940)

**Board:** `design-language/mockups/ux-design-2026-10-07/02-money-findings.html`,
rendered as `02-money-findings--1200.png` and `02-money-findings--390.png`.
One pick with two variants (L2) and two before/afters (#1142, #940).

**How the board is built.** Every frame is a `srcdoc` iframe built from the
live HEEx markup and the German msgstrs of `dashboard_live.ex`,
`portfolio_live.ex`, `securities_live.ex`, `income_live.ex` and
`classifications_live.ex`. A 390 px frame is therefore a real 390 px
viewport, and `app.css`'s 560 px and 900 px blocks fire as on a phone.

**The data is invented:**

- "Arbolia Inc." (USD), mapped to another listing: sold 03.04.2026 at
  61,40 USD, no quote stored that day, the quote of 02.04.2026 is
  618,90 USD (ratio 10,08); its 40 held shares count 24.776,00 USD;
- "Wrenfield Gardens AG" (EUR), mapped the other way: bought 12.05.2026 at
  48,20, quote that day 4,87 (ratio 0,10); its 120 shares count 589,20
  where they cost 5.784,00;
- "Larkspur Rail AG": 12 bonus shares booked as a buy at 0,00 on
  03.03.2025, 8 of them sold 13.08.2026 at 41,25 (+330,00 EUR);
- "Fennwick Labs AG": 15 shares delivered in at 0 (a spin-off), worth
  336,00 EUR;
- the tree "Tiefentest", a chain "Stufe 1" … "Stufe 32".

Identifiers are of the `DE000000000L` kind. **No real instrument, position,
balance, account, provider or rate appears.**

### L2 — #1101: how loud the `implausible_quote` finding is

**Kind:** one pick, two variants. **The predicate is decided** and not part
of the pick: for each buy, sell or priced delivery of a held security, the
stored quote on the booking's day (or the latest within N days before it)
against the booking's price per unit in the same currency; the security is
named when the ratio is outside [½, 2]; a security already flagged
`two_scales` is not counted again. It joins `Catalog.DataQuality` beside
`two_scales` (#1068).

**Before:**

- **No finding fires anywhere.** The Overview's line counts catalog hygiene
  and the two-scales bonds (`dashboard_live.ex:1049-1058`); Wealth's notes
  name trade-priced, stale, unpriced and unrated positions, negative
  holdings and two-scales bonds (`portfolio_live.ex:2684-2858`). Nothing
  compares a stored quote with the holding's own booked prices.
- **On the data:** "Alles 81.906,40 EUR" holds about 22.000 USD the
  bookings do not support and misses about 5.200 EUR they do, and the page
  reads as healthy. The line is one row tall at 980 px (36 px).

**Variants — L2:**

- **A — recommended: problem.**
  - **The Overview's line** gains a fifth finding, after two scales:
    "2 gehaltene Wertpapiere, deren Kurse nicht zu ihren Buchungen
    passen", linking to `/securities?dq=implausible_quote`. The line takes
    **Problem**, the highest severity present (UX-DR17). It carries its
    scope word ("gehaltene"), because the line otherwise counts the
    catalog (J1.2), and always its noun, as two scales does.
  - **Wealth** gains a problem note, `dq-implausible-quote`, after the
    other problem notes. Its sentence states the rule, the consequence and
    the remedy in order; each entry names one booking: kind, date, booked
    price, the quote's own date, the quote and the ratio. Arbolia's quote
    date is the day before its sale, because no quote is stored on
    03.04.2026. Each name links to its security's Quotes tab. The figures
    are `Format.exact`, as in the two-scales entries; the ratio has two
    places.
  - **The securities list** opens on the two with a removable chip, "Kurs
    passt nicht zu Buchungen", as `two_scales`' "Auf zwei Skalen
    bepreist"; there is no one-tap chip.
  - **Why A.** UX-DR17 gives problem to a finding where "the data
    contradicts itself; the figure cannot be trusted", and attention to
    one where "the figure stands". This predicate is a contradiction by
    construction: two stored facts about the same security on the same
    day, the booked price and the quote, more than a factor of two apart.
    One of them is wrong, and either way a figure in the totals is — the
    value when the quote is wrong (a mis-mapped ticker, a currency unit),
    or the cost and result when the booking is (a mistyped price). The
    sibling says the same: two scales is this predicate's special case
    (ratio ~100 on a bond), and it is problem on Wealth and on the line. A
    tenfold error should not be quieter than a hundredfold one only
    because a different rule caught it.
- **B — attention.** The same words with "kann … falsch sein", in the
  attention group after the stale-quote note; the line keeps "Achtung".
  - It reads the predicate as a heuristic that an off-market booking could
    trip (employee shares at a discount, a subscription price, a gift at a
    nominal value).
  - **What it costs:** on the Overview a holding ten times off reads
    exactly like "25 Wertpapiere im Katalog ohne Kurs seit 7 Tagen", while
    a bond a hundred times off, one finding along, is "Problem". The false
    positives B guards against are rare at [½, 2], and the commonest one,
    a free share booked at 0,00, has no ratio and is skipped either way
    (found while drawing, 2). A false positive under A costs one look at a
    booking; a true positive under B is a total off by a factor of ten,
    announced as a stale quote.

**Strings (A).**

| Where | German | English |
|---|---|---|
| Line finding (`ngettext`) | "ein gehaltenes Wertpapier, dessen Kurse nicht zu seinen Buchungen passen" / "%{count} gehaltene Wertpapiere, deren Kurse nicht zu ihren Buchungen passen" | "one held security whose quotes do not match its bookings" / "%{count} held securities whose quotes do not match their bookings" |
| Wealth note, one | "Eine gehaltene Position wird mit Kursen bewertet, die nicht zu ihren eigenen Buchungen passen (am Buchungstag unter der Hälfte oder über dem Doppelten des Preises je Stück); ihr Wert oder ihr Einstand ist daher falsch. Ihre Kursquelle prüfen (Ticker, Börse), dann die Buchung:" | "One held position is valued at quotes that do not match its own bookings (on a booking's day, below half or above twice the price per unit), so its value or its cost is wrong. Check its quote source (ticker, exchange), then the booking:" |
| Wealth note, several | "%{count} gehaltene Positionen werden mit Kursen bewertet, die nicht zu ihren eigenen Buchungen passen (am Buchungstag unter der Hälfte oder über dem Doppelten des Preises je Stück); ihr Wert oder ihr Einstand ist daher falsch. Ihre Kursquellen prüfen (Ticker, Börse), dann die Buchungen:" | "%{count} held positions are valued at quotes that do not match their own bookings (on a booking's day, below half or above twice the price per unit), so their value or their cost is wrong. Check their quote sources (ticker, exchange), then the bookings:" |
| Entry | "%{name} (%{kind} %{date} zu %{price} %{currency} · Kurs %{quote_date}: %{close} %{currency}, das %{ratio}-Fache)", kind "Kauf" / "Verkauf" / "Einlieferung" | "%{name} (%{kind} %{date} at %{price} %{currency} · quote %{quote_date}: %{close} %{currency}, %{ratio} times that)", kind "buy" / "sell" / "inbound delivery" |
| Chip and filter label | "Kurs passt nicht zu Buchungen" | "Quote does not match bookings" |
| B's consequence clause | "ihr Wert oder ihr Einstand kann daher falsch sein" | "so its value or its cost may be wrong" |

On the board the entries read "Arbolia Inc. (Verkauf 03.04.2026 zu 61,4 USD ·
Kurs 02.04.2026: 618,9 USD, das 10,08-Fache)" and "Wrenfield Gardens AG (Kauf
12.05.2026 zu 48,2 EUR · Kurs 12.05.2026: 4,87 EUR, das 0,10-Fache)". The
sentence links to the filtered list, as the stale-quote note's does.

**Measured:**

- **The line:** 36 px tall at 980 px today; 54 px with the finding (two
  rows). At 390 px it grows from 72 to 90 px.
- **Wealth's new note:** 90 px tall at 980 px and 270 px at 390 px, in A
  and B alike.
- **The removable chip:** 212 × 44 px.
- **Overflow:** at 980 and 390 px no element runs past the viewport
  outside a scroller.

**Spec:**

- UX-DR17's severity definitions (EXPERIENCE.md, the state table) and its
  "highest severity present";
- DESIGN.md → Data quality, both surfaces, with the two-scales finding
  (2026-10-06);
- J1.2's scope word on the line;
- issue 705's "a count of N opens a list of N".

**What the story writes into DESIGN.md:**

- **The line's fifth finding:** its wording, its scope word, problem
  severity, its link and its place after two scales.
- **Wealth's eighth note** (`dq-implausible-quote`): problem, the sentence,
  the entry anatomy and the Quotes-tab links.
- **The securities page's removable chip.**

### #1142 — a return on a cost basis of zero

**Kind:** before/after. **The spec fixes the answer:** the category
result already refuses it — "a category with no cost has no result to
state, and a zero would claim it is flat" (`classifications_live.ex:2419`).

**Before:**

- **The trades surfaces.** `TradeMatcher.safe_div/2` returns 0 for a zero
  basis (`trade_matcher.ex:325`). The matcher opens lots from buys only
  ("Einlieferungen eröffnen keinen Lot"), so there the case is a buy at
  0,00. Larkspur's trade prints "+330,00 EUR 0,0%" in the facet's Result
  cell and "0,0%" in the Trades tab's "%" column. Both phone rows read
  "0,0% gesamt" (facet) or "0,0%" (tab): a flat trade.
- **The p. a. cell** already shows the dash, but with the solver's reason
  ("Keine annualisierte Rendite: kein Zinssatz löst die Zahlungen dieses
  Trades"), which the spec glosses as a total loss.
- **The open lot** of the four remaining bonus shares prints "0,0%"
  (`decorate_open_lot/4`, `ledger.ex:1058`).
- **The unrealized side**, the issue's own example. Fennwick's delivery at
  0 gives a zero basis (`ledger.ex:720`) and a zero percent
  (`ledger.ex:496`, `:954`). The security's Bestände tab prints "0,00 %"
  in the gain colour, because the cell takes its class from the amount
  beside it (`securities_live.ex:2490`); the cell is 60 × 51 px and wraps
  "0,00" over "%". Wealth's Positionen prints "0" in the optional
  "G&V %" column.

**After:**

- **The dash, with its reason.** Every one of these cells is the existing
  muted dash with #1089's reason anatomy: a `title` and a visually hidden
  sentence. The holdings tab's "%" cell becomes 32 px wide; the row height
  is unchanged (51 px).
- **Desktop.** The facet's Result cell keeps "+330,00 EUR", and its
  sub-line is the dash (12 × 15 px). The p. a. cell takes the zero-basis
  reason, which comes before the 365-day rule and the solver's: with no
  cost there is nothing to annualize.
- **At 390 px the reason is on the row, in words:** "— keine Kostenbasis"
  stands where "0,0% gesamt" stood, the dash `aria-hidden`. It is 118 px
  wide on one 15 px line, and the rows stay 59/60/60 px (facet) and
  59/60 px (tab), as before. There is no "gesamt", because there is no
  total return to qualify.
  - **Why not the basis line:** the two p. a. reasons live there because
    they are rules the row lets the reader check (its days). A zero basis
    is a fact about one booking that the phone row does not show (it has
    no cost column), and a touch screen has no `title`.
- **CSS:** one general rule, `.data-table td.trade-pa--na { color:
  var(--color-text-muted) }`. It replaces the two scoped copies
  (`app.css:10621`, `:10666`), as issue 1010 did for the sign colours,
  because the open lots' table has no id and `.data-table tbody td`
  outranks the bare class.

**Strings:**

| Where | German | English |
|---|---|---|
| "%" / Result sub-line: `title` | "Keine Rendite: keine Kostenbasis" | "No return: no cost basis" |
| "%" / Result sub-line: hidden sentence | "keine Rendite, keine Kostenbasis" | "no return, no cost basis" |
| p. a.: `title` | "Keine annualisierte Rendite: keine Kostenbasis" | "No annualized return: no cost basis" |
| p. a.: hidden sentence | "keine annualisierte Rendite, keine Kostenbasis" | "no annualized return, no cost basis" |
| Phone row, visible after the `aria-hidden` "—" | "keine Kostenbasis" | "no cost basis" |

**Spec:**

- DESIGN.md → the trades facet (the dash, the phone row, "a figure that
  reads zero is directionless") and the Trades tab (the dash, the phone
  row without "gesamt");
- the Amendment of 2026-10-07 (#1089, #1060);
- ADR-0041's category result.

**What the story writes into DESIGN.md:**

- **Where a return on no cost is the reason dash:** the facet's Result
  cell and phone row, the Trades tab's two "%" columns and phone row, the
  holdings tab's "%" and Wealth's "G&V %". The reason reads "keine
  Kostenbasis", in words at 390 px, and comes before the p. a. reasons.
- **The one general muted-dash rule.**

### #940 — a category below level 32 is refused

**Kind:** before/after. The decision fixes the answer: the write is
refused. The board shows where and in which words.

**Before:**

- **Nothing checks the depth on write.** `Classifications.max_tree_depth/0`
  (32) is the cycle guard every parent walk stops at
  (`classifications.ex:216-225`), but no write checks it. Picking
  "Stufe 32" as the parent and pressing "Hinzufügen" says "Kategorie
  angelegt" (a 36 px note) and creates "Stufe 33".
- **From then on the tree is read wrong:** `path_to_root/4` returns that
  category's path without its root, so `category_at_level/3` reads its
  securities' level-1 column as "Stufe 2".

**After:**

- **The slot.** The refusal is a problem note with its ×, in the page's
  result slot above the head (`#classifications-result`,
  `AppShell.inline_result`, `classifications_live.ex:270-275`, the alert
  region). Every refusal on this screen already lands there; the create
  form has no slot of its own.
- **The form** keeps what was typed ("Stufe 33", the picked parent).
- **No control re-homes a category on this screen:** the edit form changes
  name, description and colour, and drag and drop moves securities. A move
  is refused through the API's 422, with the changeset message below.
- **Its own `error_message/1` clause,** not `changeset_error/1`, whose
  field prefix would read "Parent würde …" (found while drawing, 6).

**Strings:**

| Where | German | English |
|---|---|---|
| The page (create) | "Nicht angelegt: Unter „%{parent}“ läge die neue Kategorie auf Ebene %{level} — eine Klassifizierung hat höchstens %{max} Ebenen. Bei „Übergeordnet“ eine Kategorie weiter oben wählen." | "Not added: under “%{parent}” the new category would sit on level %{level} — a classification has at most %{max} levels. Under “Parent”, pick a category higher up." |
| Changeset error on `parent_id` (errors domain; API 422 and MCP) | "würde eine Kategorie auf Ebene %{level} legen; eine Klassifizierung hat höchstens %{max} Ebenen" | "would put a category on level %{level}; a classification has at most %{max} levels" |

For a move, `%{level}` is the level the deepest category of the moved
subtree would take. "Übergeordnet" / "Parent" is the select's own label.

**Measured:**

- **The refusal note:** 54 px tall at 980 px and 108 px at 390 px.
- **The slot is far from the form.** From the note's top edge to the
  bottom of "Hinzufügen" is 570 px at 980 px and 736 px at 390 px, with no
  plan. The plan editor's empty state is 166 and 155 px of that, and a
  plan adds its table, one row per category.
- **The parent select** with "Stufe 32" picked is 609 px wide at 980 px
  and 358 px at 390 px.
- **The deep tree, every level open, at 980 px:** each level indents 22 px
  and its row loses 29 px. The name cell is 398 px at Stufe 1 and 136 px
  at Stufe 10, under 48 px from Stufe 14 and 0 px from Stufe 15. From
  Stufe 21, "✎" and "×" are clipped past the page's edge.

**Spec:**

- `{components.inline-result}` and UX-DR17's alert contract (a problem
  answering an action just taken);
- J7 A, the page's result slot (#1064);
- #945, a refusal brought into view.

**What the story writes into DESIGN.md:**

- the classification screen's refusals: the depth refusal's sentence, in
  the page's result slot, with focus moved to it (found while drawing, 5).

### Found while drawing

1. **One price basis.** Stored quotes may be split-adjusted (ADR-0028 §2)
   while a booked price is not.
   - Compared raw, every security with a recorded split since a booking is
     named.
   - An unrecorded split is a true finding whose remedy is "Split
     erfassen", not the mapping.

   **Fix in the story (D-14).**
2. **A booking at 0,00 has no ratio.** #1142's bonus shares (a buy at
   0,00) and a delivery at 0 would divide by zero, or name every security
   with a free share. The predicate skips a booking whose price per unit
   is 0. **Fix in the story (D-14).**
3. **A bond booked per piece** of a 1.000 denomination beside percent
   quotes has a ratio of ~1/10.
   - That is outside both two-scales bands, so the bond lands here.
   - Its fix is the booked quantity, not the mapping. The note's "dann die
     Buchung" covers it, and the story pins it with a test.

   **Fix in the story (D-14).**
4. **Wealth's "G&V %" prints the raw fraction.** It shows every digit —
   "0,1871401151631477927063339731" for +18,7 % — under a "%" header
   (`holdings_cell/2` → `Format.exact/1`, `portfolio_live.ex:2640`).
   **Fix in the story (D-14),** not filed: B3 changes exactly this cell,
   and DESIGN.md's percent format is the answer.
5. **The create form's refusal is not brought into view.** A plan write's
   is (`answer_plan_write/1`, #945). The form sits 570 px under the slot at
   980 px and 736 px at 390 px. **Fix in the story (D-14):** give
   `create_category`'s refusal the same focus.
6. **"Parent würde …".** `changeset_error/1` labels every field but `:name`
   through `Phoenix.Naming.humanize/1`, in English, on the German page.
   The cycle refusal reads "Parent würde die Kategorie zu ihrer eigenen
   Oberkategorie machen" today (`classifications_live.ex:3201-3202`).
   **Fix in the story (D-14),** on the message path it touches.
7. **32 levels are not readable.** At 980 px the name cell is under five
   characters from Stufe 14 and gone from Stufe 15, and the row's buttons
   are clipped from Stufe 21. The cap is a cycle guard, not a depth anyone
   can read; whether the refused depth should be lower is a decision.
   **File** at the merge, together with item 8, as one `needs-decision`
   issue carrying its recommended answer (the plan's D-4 rule).
8. **The parent select at depth.** `indent/1` puts one "— " per level
   before a name. At 390 px the picked "Stufe 32" shows as dashes only.
   **Filed with item 7.**
9. **The Overview's trades card** prints the same zero for a zero-basis
   trade, "0,0% gesamt" (`dashboard_live.ex:700`). **Fix in the story
   (D-14).**
10. **The payload half of #1142.** `realized_pnl_pct` and
    `unrealized_pnl_pct` are served as "0" for a zero basis (`json.ex:537`,
    `:683`, and the realized reads). They become null, with the reason in
    the computation basis, as `annualized_return_reason` does. **Fix in
    the story (D-14).**
11. **The holdings tab's "%" has the old format.**
    - It prints two decimals and a breaking space, so "0,00 %" wraps to two
      lines at 980 px.
    - It takes its colour from the amount beside it
      (`signed_percent_or_dash/1`, `securities_live.ex:3239`; `pnl_class/1`,
      `:2490`).

    #1060 aligned the Trades tab only. **Fix in the story (D-14),** in the
    cell it changes.
12. **The value card stays silent** about a holding valued ten times off.
    J1 A's note under the total names rows out of it, not rows wrongly in
    it, and the line is six blocks below. **Decided here, not filed:**
    the Overview's alarm for a finding is its data-quality line (#703's
    routing, confirmed by the owner on 2026-08-15 and kept by Sprint 19's
    D-3). J1 A's note names what the total leaves out, and a wrongly valued
    row is not left out. L2 A puts the line at problem severity, which is
    the alarm.
13. **The security's own pages say nothing.** Wealth's entry links to the
    Quotes tab, where no sentence names the booking and the quote that day.
    The Overview tab's two-scales note (`bond_strip.ex:289`) has no
    sibling. **Not filed:** Lane Z comments on #1112 (the detail page's
    note for a bond on the reverse scales), whose story in the UI batch
    draws both notes on one board.

**What clears the L2 finding** is not a found item, but the story says it in
its briefing. The Yahoo adapter fetches the whole series on every sync
(`period1=0`, `yahoo.ex:7`), so the first sync after the mapping is fixed
rewrites the quotes on the booking dates. A day the new listing does not
trade keeps the old quote, and a manual quote is not overwritten.
