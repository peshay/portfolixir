# UX Design Pass — 2026-10-27, the security batch's rendered changes (Sprint 21, Lane S)

Scope: **every** rendered change the security review's fix batch makes,
held against the living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html).
The batch is the adopted
[security review triage of 2026-10-12](security-review-triage-2026-10-12.md),
which joins Sprint 21 as Lane S
([the amendment](../implementation-artifacts/sprint-plan-2026-10-27-sprint21-amendment.md),
D-8). `DESIGN.md` and `EXPERIENCE.md` are the authority, and this document
proposes against them. It runs **on the planning PR, before the batch**, as
the sprint workflow's "UI changes are mocked first" requires.

**Why these boards.** Most of the triage's 75 rows change a bound, a lock, a
header or a log line and render nothing. Part 3 was read row by row against
the code it touches; the rows whose fix changes what a page shows are drawn
here, one board per surface. Every other row is listed at the end with the
evidence that its picture does not change ("Rows that render nothing new").

**How the weaknesses are named.** As the triage does: by the row's id, its
class and its fix. This document carries no reproduction, payload,
threshold, request sequence or way of reaching a weakness. A "today" frame
shows what the operator's own screen shows, never how it was brought there.

**The mockups** are in `design-language/mockups/ux-design-2026-10-27/`:

- **One board per surface**, with every variant or its before and after.
  Each board links the real `priv/static/app.css` and uses the live pages'
  markup and German labels (`priv/gettext/de`).
- **Rendering.** Playwright renders each board to PNG at 1200 and 390 px
  (`render.mjs`, unchanged from the 2026-10-09 pass), reduced to a
  256-colour palette.
- **Real widths.** Every frame is a `srcdoc` iframe, so a 390 px frame is a
  real 390 px viewport and `app.css`'s breakpoints fire as on a phone. A
  desktop page frame is 980 px (1200 − the 220 px sidebar); a dialog is
  drawn open, in place, in a 520 px stage.
- **CSS.** "Heute" frames render `app.css` as shipped; "Nachher" and variant
  frames add the board's `<style id="proposal">`, which holds every rule the
  story adds. Dashed outlines mark what is new.

**The data is invented:**

- names in the demo seed's style ("Arbolia Inc.", "Larkspur Rail AG",
  "Wrenfield Gardens AG", "Kestrel Point AG");
- identifiers that pass the app's checks but name nothing (the fixtures'
  style, "XSLARKSPUR33", "DE000000000H");
- generic account and institution names ("Test-Cash", "Tagesgeld",
  "Depot Muster", "Bank A");
- made-up figures and 2026 dates.

**No real instrument, position, balance, account, provider or rate
appears.**

**How a pick is made.** The pick letter is **Q** (the 2026-10-09 pass used
N).

- **The recommendation is the default.** A comment on the planning PR
  naming another variant ("Q1 A") changes it; silence adopts it.
- **A before/after has nothing to pick:** the triage's fix already fixes the
  answer, and the board shows the reader what the words describe.
- **The story that builds an item writes its anatomy into `DESIGN.md`**
  (the sprint workflow's rule 3); each section below ends with what it
  writes.

| Pick | Item | Board | Lane | Kind | Recommended |
|---|---|---|---|---|---|
| — | H38 — the logo dialog: an upload instead of an image URL | `01-logo-upload` | S3 | before/after | after |
| **Q1** | H45 — the import's security mapping without the catalog in every row | `02-imports-mapping` | γ7 (D-4) | variants | **B**: "Wird neu angelegt" stays the row's line; "Anders zuordnen…" opens the merge dialog's search and its radio cards in the row; a decision row's candidates are its cards |
| **Q2** | H57 — a ticker in the file that the catalog refuses | `02-imports-mapping` | S5 | variants | **B**: a row warning; the security is created without the ticker, every entry imports |
| — | H14 — a rule an agent renamed carries the mark beside its name | `03-author-marks` | S7 | before/after | after |
| — | K12 — the Tax page marks a statement or an allowance order the agent recorded or corrected | `03-author-marks` | S7 | before/after | after |
| **Q3** | K12 — where the budget's basis line marks the institution | `03-author-marks` | S7 | variants | **A**: "(Agent)" after the institution it covers |
| **Q4** | K11 — where the security merge preview states the FIFO restatement | `04-merge-restatement` | S6b | variants | **A**: a block of its own under the holdings, open, in the depot preview's table anatomy |
| — | K11 — the depot preview names its moving average and says FIFO is unchanged | `04-merge-restatement` | S6b | before/after | after |
| — | H11 — a merge refusal names the identity by kind; the values stand as data lines | `04-merge-restatement` | S7 | before/after | after |
| **Q5** | K07 — an income payment with no rate path to the base currency | `05-income-rate-path` | S6b | variants | **A**: out of every total, named in an attention note with the backfill control, as the other Cash-flow facets do |
| **Q6** | H17 — Delete on Accounts asks whatever the menu saw when it opened | `06-delete-confirm` | S6 | variants | **A**: the item always asks; a menu that saw references asks without claiming the account is free |
| — | K13, H36, H37, H39, H56 on a page; H31, H36, H37 over the API | `07-copy-sheet` | S3, S4, S5 | before/after | after |
| — | K10 — the booking drawer offers only buy and sell | none | S6b | identical picture | no board (see "K10 — no board") |

**Added beyond the brief, after reading Part 3:** H57 (Q2), H39 and H56
(board 07) change rendered output and were not in the list this pass was
asked to draw. **Found to render nothing:** K10, and every row listed at
the end.

**What the merge adopts beyond the picks.** Each board ends with "Found
while drawing", each item with its verdict:

- **Fixed in the story that touches the surface** (small, on that
  surface, with the answer in the spec): the logo source's raw adapter
  name (board 01); the missing German for "is not a ticker symbol" and the
  import summary that counts rows, not choices (board 02); the Tax page's
  author per institution in the budget summary (board 03); the term "open
  lots" checked against the Trades tab (board 04); the Income ⓘ's rate
  rule (board 05); a successful delete on Accounts says nothing (board
  06); the account dialog's unassociated field errors, the statement
  form's raw field keys and the holder field's missing `aria-invalid`
  (board 07).
- **Filed at the merge, under the S7 tracker:** "merge refusals on the
  page: stored names (rules, portfolios, depots) as data lines, as H11
  does for identifiers" (board 04).
- **Recorded in the idea list:** "a manual logo as bytes over the API and
  MCP" (board 01).
- **Already built elsewhere in Sprint 21:** the logo dialog's flush
  footer (#1138, γ8) and the costs note's "Kurs" (#1150, γ4).

---

## Board 01 — the logo dialog: an upload instead of an image URL (H38)

**Board:** `design-language/mockups/ux-design-2026-10-27/01-logo-upload.html`,
rendered as `01-logo-upload--1200.png` and `01-logo-upload--390.png`.

- **Frames.** The dialog of `PortfolixirWeb.Securities.LogoOverrideDialog`
  (`dialog/1`), drawn open in a 520 px stage and at 390 px, with the German
  msgstrs. Security: "Arbolia Inc."; files "arbolia-logo.png" (an invented
  leaf drawn on the board) and "arbolia-banner.png".
- **CSS.** One block, `.logo-override__*` (app.css has no rule for the
  dialog's form today; the generic form rules stack its parts).

**Triage row:** H38 (S3) — class: ssrf; fix: the manual logo becomes a
browser-side upload (`allow_upload` in the logo dialog and
`LogoStore.store_manual_bytes/4`, already written and unused), and the URL
form leaves the UI.

**Today.** `LogoOverrideDialog.dialog/1` offers one way to set a logo: the
form "Bild-URL" with "URL speichern" (`phx-submit="save_logo_url"`).
`SecuritiesLive.handle_event("save_logo_url", …)` hands the address to
`store_logo_url/3` → `Catalog.set_logo_override/3` →
`LogoStore.store_manual_override/3`, which fetches it server-side. A logo
whose file is gone says "Die gespeicherte Logodatei fehlt. Über eine
Bild-URL erneut setzen oder das Logo entfernen."

**Before/after (nothing to pick).** The upload takes the URL form's slot;
nothing else in the dialog moves.

- **Nothing chosen:** "Bilddatei", the chooser "Bild wählen…" (the label of
  the visually hidden `live_file_input`, drawn as the outline button), the
  basis line, and "Logo speichern", disabled.
- **A file chosen:** its `live_img_preview` at the detail header's logo size
  (`.security-logo--lg`, 40 px, on the logo plate), the file name and size,
  and an × ("Auswahl entfernen") that cancels the entry; "Logo speichern"
  is enabled. The answer is today's: the dialog closes, the page's result
  says "Logo aktualisiert".
- **A file refused:** a `.field-error` under the chosen file, linked by
  `aria-describedby`, the input `aria-invalid` (UX-DR13). The upload's
  refusals reuse the Imports page's words (`imports_live.ex`
  `error_to_string/1`); a file whose bytes are not the image its type names
  is refused by `store_manual_bytes/4`'s image check after the upload, with
  a new sentence.
- **Dropping a file on the dialog** chooses it too (`phx-drop-target` on the
  form), with no drop zone drawn: the dialog is small, and a phone has
  nothing to drop.
- **Accept list and size** are `LogoStore`'s own (`@allowed_content_types`,
  the manual default `max_bytes`), stated once in the basis line; the
  `allow_upload` options read the same two values, so the browser and the
  store refuse the same files.

**Why this is the answer.** The fix removes the one path on which the
operator's page made the server fetch an address typed into it, instead of
tightening the outbound policy around it once more. The image now comes
from the operator's own machine, which is where an operator who wants a
specific logo has it. Discovery ("Erneut suchen") still fetches from the
configured providers under the outbound policy; that path is unchanged.

**Strings** (new unless marked):

| | English (msgid) | German |
|---|---|---|
| Field label | Image file | Bilddatei |
| Chooser | Choose image… | Bild wählen… |
| Basis line | PNG, JPEG or WebP, at most %{size}. The image is stored on this instance; discovery does not overwrite it. | PNG, JPEG oder WebP, höchstens %{size}. Das Bild wird auf dieser Instanz gespeichert; die automatische Suche überschreibt es nicht. |
| Clear the choice (`aria-label`, `title`) | Remove the selection | Auswahl entfernen |
| Confirm | Save logo | Logo speichern |
| Refused: not an image | The file is not a readable image. | Die Datei ist kein lesbares Bild. |
| Refused: size, type, count | reused: "File too large.", "File type not accepted.", "Only one file at a time." | reused |
| File missing (changed) | The stored logo file is missing. Upload the image again, or remove the logo. | Die gespeicherte Logodatei fehlt. Das Bild erneut hochladen oder das Logo entfernen. |
| Retired | "Image URL", "Save URL", "Enter an image URL first.", "Could not load that image" | — |

**Measured** (Playwright, inside the frames): the dialog is 460 px wide in
the stage and 358 px at 390 px. Its height grows from 341 px today to 375
(nothing chosen), 423 (chosen) and 448 px (refused); at 390 px 393, 441
and 466 px. The chosen file's row is 40 px tall at both widths; the basis
line is two lines at 460 px and three at 390 px. No frame scrolls
sideways.

**What the story writes into `DESIGN.md`** (Components → the logo dialog):
the upload in place of the URL form; its three states; the preview at the
header logo's size; the refusal as a field error with the upload's words;
the drop on the dialog without a drawn zone; the basis line naming what is
accepted and the lock.

### Found while drawing (board 01)

1. **"Aktuelle Logo-Quelle: %{source}" prints the source adapter's stored
   name raw** (`logo_override_dialog.ex`, the `@status.has_logo` branch;
   `Catalog.logo_status/1` passes `attributes["logo_source"]` through). A
   raw stored value in a user-facing sentence breaks Voice and Tone's
   rule of 2026-09-12. **Recommended: fixed in the H38 story**, which owns
   the dialog: a label per source ("manuell hochgeladen" for the manual
   source, "automatisch gefunden" for every adapter), with the meta-test
   the rule asks for. The board draws the "no logo yet" state, so no
   provider is named.
2. **The dialog's footer sits flush with its bottom edge.** That is #1138,
   which Sprint 21's γ8 already builds (board 08 of 2026-10-09); nothing to
   add.
3. **The API and MCP keep setting a logo from a URL** (`logo_controller.ex`,
   under the outbound policy and, after H61, the request's actor). H38
   removes the form from the UI only. The screen and the agent then set a
   manual logo in two different ways, which the coverage rule allows but
   does not like. **Recorded in the idea list at the merge:** "a manual
   logo as bytes over the API and MCP", with the question whether the URL
   path should then retire too.

---

## Board 02 — the Imports page: the security mapping and a refused ticker (H45, H57)

**Board:** `design-language/mockups/ux-design-2026-10-27/02-imports-mapping.html`,
rendered as `02-imports-mapping--1200.png` and `02-imports-mapping--390.png`.

- **Frames.** `imports_live.ex` `render_preview/1` (the section
  `#import-security-mapping` with `security_choice_select/1` and
  `isin_change_offer/1`; the parser-warnings data note; the page error), and
  the merge dialog's step 1 (`merge_dialog.ex` `render_target_step/1`:
  `.search-field`, `.merge-targets`, `.merge-target`), which Q1 B reuses.
  **Drawn on top of board 07 of the 2026-10-09 pass as adopted:** N20 A's
  recount, N21 A's correction lines and #1179's "Eintrag" are the page's
  state; the account and depot sections are elided as board 07 draws them.
  This keeps the amendment's D-4 move: H45 builds in γ7, on board 07's
  surface.
- **Data.** A JSON file with "Sorrel Bay Foods AG" (new), "Larkspur Rail
  Holding AG" (the file's new name of the stored "Larkspur Rail AG", its
  ISIN `DE000000002L` against the stored `DE000000001L`) and "Brightwater
  Utilities SE" (two stored securities of that name). A catalog of thirteen
  invented securities.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **Q1** | H45 — the security mapping without the catalog in every row | variants | **B** |
| **Q2** | H57 — a ticker in the file that the catalog refuses | variants | **B** |

### ① Q1 — H45: the security mapping without the catalog in every row (variants)

**Triage row:** H45 (S4) — class: resource exhaustion; fix: render the
catalog options once (a shared datalist or a searchable picker loaded on
demand) instead of a full select per row; keep "create" as the per-row
default and open the remap control only when the operator asks for it.

**Today.** `security_choice_select/1` (`imports_live.ex`) renders one
`<option>` per security of `@existing_securities`
(`Catalog.list_securities(is_benchmark: false)`, assigned in the preview's
mount path) in **every** row that carries it: each plain create inside
"N neue Wertpapiere werden angelegt", each decision row, and each row whose
bookings are all imported (#923's "Keine Entscheidung nötig" row keeps its
select for the ISIN change). The page's size is rows × catalog, and every
re-render of the preview sends it again. On a phone an opened select is the
system's wheel of every security with no search. A decision row lists its
candidates as text (`security_option_label/1`) and then asks through the
whole catalog.

**Variants:**

- **A — one shared datalist.** The catalog renders once as
  `<datalist id="import-security-options">` (`phx-update="ignore"`); each
  row is `<input list=…>`, empty meaning "create".
- **B — recommended: "create" is the row's line; the picker opens on
  ask.** A plain create reads "Wird neu angelegt: **Sorrel Bay Foods AG**"
  with "Anders zuordnen…" (a `.link-button`). Pressed, the row's target
  column opens the merge dialog's search field ("Name, ISIN, WKN oder
  Ticker", debounced, server-side, capped, nothing suggested before a
  search) and the hits as radio cards (`.merge-target`: name, currency,
  ISIN, creation date, bookings), with "+ Neu anlegen: …" as the first
  card, checked. A pick closes the picker into "Zugeordnet: **Larkspur Rail
  AG** · EUR · DE000000001L" with "Ändern…", and `isin_change_offer/1`
  follows the chosen target as today. A decision row shows its candidates
  as the radio cards themselves, "+ Neu anlegen" beside them, and
  "Anderes Wertpapier suchen…" for the rare case that is neither; nothing
  is preselected, as today.

**Why B.**

- **No catalog at rest.** The common row renders one line and one button;
  only the row the operator opened holds a list, and only of what the
  search found. A bounds the page at one catalog per preview; B bounds it
  at one capped search.
- **The picker exists.** The merge dialog's step 1 already searches the
  catalog this way (ADR-0050 §14: nothing suggested), with the touch floor
  and the focus ring its closing act gave the cards. One search, one card
  anatomy, one set of tests.
- **Accessibility.** A labelled search field and a fieldset of native
  radios behave the same in every browser, for a screen reader and in the
  suite's LiveView tests. A's suggestions are drawn by the browser: their
  filtering, keyboard behaviour and announcement differ by browser, they
  shrink to the keyboard's strip on a phone, and none of it can be styled
  or tested.
- **A datalist answers with text.** A typed or picked label must be
  matched back to a security, and two securities with one label — the
  decision row's very case, and every twin — cannot be told apart by it; A
  needs a hidden id and a script to keep them in step.
- **The default reads as an answer** in B ("Wird neu angelegt: …"), and as
  an empty field in A.
- **Phone width.** B's cards wrap inside the 295 px target column at 390 px
  with no sideways scroll; A at 390 px is a full-width text field whose
  suggestions the keyboard owns.

**Measured** (Playwright): at 980 px the section is 593 px tall today with
the closed selects (a select is 34 px, the opened one in the frame is
drawn at nine rows), 578 px in B at rest and 848 px with one picker open
(the picker 276 px: the field, three cards of 44–56 px, the basis line).
At 390 px: 805 px today, 816 px in B at rest, 1 146 px with the picker
open (the picker 341 px); a card is 295 × 56–73 px. No frame scrolls
sideways.

**Strings** (B; new unless marked):

| | English (msgid) | German |
|---|---|---|
| The row's default | Created as new: %{name} | Wird neu angelegt: %{name} |
| Opens the picker | Map elsewhere… | Anders zuordnen… |
| A remapped row | Mapped to: %{name} | Zugeordnet: %{name} |
| Reopens the picker | Change… | Ändern… |
| The cards' legend | Map to | Zuordnen zu |
| Search field label | Search securities: name, ISIN, WKN or ticker | Wertpapier suchen: Name, ISIN, WKN oder Ticker |
| Placeholder | reused: "Name, ISIN, WKN or ticker" | reused |
| Basis line | The catalog is searched by name, ISIN, WKN and ticker; nothing is suggested. | Gesucht wird im Katalog nach Name, ISIN, WKN und Ticker; vorgeschlagen wird nichts. |
| No hit | No security matches. | Kein Wertpapier passt. |
| A decision row's search | Search for another security… | Anderes Wertpapier suchen… |
| The create card | reused: "+ Create new: %{name}" | reused |
| Retired | "Decide…" (the decision row's radios start unchecked) | — |

**CSS** (B): `.mapping-target__current` (the row's line),
`.mapping-remap` (the opened picker in the target column),
`.mapping-remap__basis`, and the decision row's search link standing clear
of its cards. The cards and the field are the merge dialog's classes,
reused as they are.

**What the story writes into `DESIGN.md`** (Components → the import
mapping, beside board 07's amendments): a security row's line and its
"Anders zuordnen…"; the picker as the merge dialog's search-and-pick list
(named once as a shared anatomy, used by both); the decision row's
candidates as the first cards; that no row carries the catalog.

### ② Q2 — H57: a ticker in the file that the catalog refuses (variants)

**Triage row:** H57 (S5) — class: hardening gap; fix: expose the catalog's
ticker rule (a `Security.ticker_valid?/1` beside `identifier_valid?/2`)
and apply it in `PortfolioPerformance.row_error` as a named row error, or
drop an unusable ticker with a row warning so the security is still
created by ISIN or name.

**Today.** The preview checks a row's ISIN (`portfolio_performance.ex`,
"ISIN … ist keine gültige ISIN … — Zeile nicht übernommen") but not its
ticker. A ticker the catalog's changeset refuses (`Security.changeset`,
`validate_format(:ticker_symbol, …, message: "is not a ticker symbol")`)
surfaces only at "Import bestätigen": the security's insert fails, the
whole apply rolls back, and `apply_error_message/1` prints "Anlegen des
Wertpapiers fehlgeschlagen: Ticker is not a ticker symbol" — the message
in English, because `errors.po` has no German for it.

**Variants:**

- **A — a named row error.** Every entry of that security reads "Eintrag
  N: …: Der Ticker aus der Datei ist kein gültiges Ticker-Symbol — Eintrag
  nicht übernommen. …"; the entries are left out, the rest imports.
- **B — recommended: a row warning.** One warning on the security's first
  entry: "Eintrag 12: Sorrel Bay Foods AG: Der Ticker aus der Datei ist
  kein gültiges Ticker-Symbol und wird nicht übernommen; das Wertpapier
  wird ohne Ticker angelegt. Den Ticker danach am Wertpapier erfassen."
  Every entry imports.

**Why B.** The ticker is the weakest identifier a file carries and the one
the catalog may lack; the security is still matched and created by its
ISIN or name (ADR-0029's tiers), and the quote sync is the only reader of
the field. A drops the operator's bookings to protect it; B keeps every
booking, says once what was left out, and names the remedy on the
security, where the field's own error explains the rule. B is a parser
warning like board 07's, so it adds no anatomy. A remains the honest
choice if a security should never be created without what its file named.

**Strings** (new):

| | English (msgid) | German |
|---|---|---|
| B, the warning | %{name}: the ticker in the file is not a valid ticker symbol and is not adopted; the security is created without a ticker. Record the ticker on the security afterwards. | %{name}: Der Ticker aus der Datei ist kein gültiges Ticker-Symbol und wird nicht übernommen; das Wertpapier wird ohne Ticker angelegt. Den Ticker danach am Wertpapier erfassen. |
| A, the row error | %{name}: the ticker in the file is not a valid ticker symbol — row not imported. Create the security by hand and book the entries. | %{name}: Der Ticker aus der Datei ist kein gültiges Ticker-Symbol — Eintrag nicht übernommen. Das Wertpapier von Hand anlegen und die Einträge buchen. |
| `errors` domain (both) | is not a ticker symbol | ist kein Ticker-Symbol |

The warning names the security, not the refused value: the row's own
label already locates it, and the value is what the rule refused.

**What the story writes into `DESIGN.md`** (the import's row warnings): a
refused ticker is dropped with a warning naming its remedy.

### Found while drawing (board 02)

1. **`errors.po` has no German for "is not a ticker symbol"**, so a
   refused ticker reads in English on a German page, wherever the
   changeset's message is shown (the import's apply error today, the
   security dialog's field error). **Fixed in the H57 story** (the msgstr,
   whichever variant).
2. **A decision row lists its candidates as text and then repeats the
   question through the whole catalog.** Q1 B answers it (the candidates
   are the cards); under A it stays, and would be filed.
3. **"N neue Wertpapiere werden angelegt" counts the rows, not the
   choices**: after a remap the summary still counts the remapped row. B's
   summary follows the choice and the row stays where it is (drawn in "B —
   zugeordnet"). **Fixed in the Q1 story.**

---

## Board 03 — the agent's mark on a rule's name and on the Tax page (H14, K12)

**Board:** `design-language/mockups/ux-design-2026-10-27/03-author-marks.html`,
rendered as `03-author-marks--1200.png` and `03-author-marks--390.png`.

- **Frames.** `risk_live.ex` (the own-rules section: `#policy-findings`,
  `.policy-rule__name`, `.policy-rule__words`, `author_mark/1`) and
  `tax_live.ex` (`render/1`: the budget meter with
  `[data-role="budget-basis"]`, the statement list's
  `.tax-statement__head`, the allowance-order disclosure and
  `orders_summary/1`), with the German msgstrs.
- **The mark reused.** Every mark on the board is rule versions' existing
  author mark (`DESIGN.md`, amendment 2026-09-26, pick G12.1-A): "Agent"
  after a middle dot, in the line's muted text, a `.visually-hidden` lead
  before it, no badge, no colour, only at the exception.
- **Data.** Rules "Klumpengrenze Larkspur", "Cash-Puffer", "Anleihen im
  Band"; taxpayer "Family", tax year 2026, institutions "Bank A", "Bank B",
  "Bank C"; invented figures that add up (612,00 + 400,00 + 272,50 =
  1.284,50).

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| — | H14 — a rule an agent renamed carries the mark beside its name | before/after | after |
| — | K12 — a statement or an allowance order the agent recorded or corrected, on the Tax page | before/after | after |
| **Q3** | K12 — where the budget's basis line marks the institution | variants | **A** |

### ① H14 — a rule an agent renamed carries the mark beside its name (before/after)

**Triage row:** H14 (S7) — class: integrity; fix: record who last named the
rule (`name_author` set from the actor in `create_rule` and `rename_rule`,
serialised in rules and findings, an Agent mark beside the name on the Risk
page), or show the rename's actor from the journal; state in
`POLICY_RULE_AUTHOR` that author covers the version, not the name.

**Today.** `RiskLive`'s own-rules table renders the name as a
`.link-button` and, in the muted words line under it, `author_mark/1` from
`finding.author` — the author of the version in force. A rule an API
token renamed keeps no trace of it: `DESIGN.md` says so on purpose ("A
rename is no version and moves no mark: the word follows the line, not the
name"). The token's name reads as the operator's.

**After.** A second mark of the same anatomy follows the name's button,
outside it, from `name_author`: " · Agent", hidden lead "Name von:" /
"Named by:". The version's mark keeps its place and its lead, so a rule the
agent both named and wrote reads "Anleihen im Band · Agent" over "Drift ·
Anleihen · Band · Warnung · Agent", and a reader hears which mark is which.
The scheduled and retired lists under the table carry the name's mark after
the name's link the same way; the rule dialog's head names "Name von:
Agent" where the agent named it. The mark is the **current** name's author;
the journal keeps every rename.

**CSS (one rule).** `[data-role="policy-rule-name-author"]` takes the words
line's voice (12 px, `--color-text-muted`) and does not wrap inside
"· Agent"; without it the mark would sit in the name cell's body text.

**Measured:** at 980 px the findings table stays 187 px tall (the mark
fits beside the name); at 390 px it grows from 284 to 305 px, the mark
wrapping under a two-line name. No frame scrolls sideways.

**Strings** (new): hidden lead "Named by:" / "Name von:". "Agent" is
reused.

**What the story writes into `DESIGN.md`** (amending the 2026-09-26
amendment): the line "A rename is no version and moves no mark" becomes
"A rename moves the name's own mark: the name carries 'Agent' when the
agent gave it, the words line when the agent wrote the version in force;
each with its hidden lead."

### ② K12 — the Tax page marks what the agent recorded or corrected (before/after)

**Triage row:** K12 (S7) — class: integrity; fix: record an actor-derived
author on statement snapshots and allowance orders at create and on every
update, as rule versions do; serialise it in the tax reads; mark a row the
agent recorded or corrected on the Tax page and in the budget's basis
line; keep the source system-set but stop presenting a token's write as a
manual transcription (T-16).

**Today.** `TaxLive.source_label/1` maps the stored source `"manual"` to
"manuell erfasst", and a token's write is stored with that source, so a
statement the agent recorded reads as the operator's own transcription.
The budget meter's basis line ("Freistellungsauftrag … verbraucht · Stand …
· Bank A, Bank B, Bank C") sums the statements and names no author; the
allowance orders (`orders_summary/1` and the list) neither.

**After** (the statement head's last words):

| Who | Head line |
|---|---|
| the operator recorded it, nobody else changed it | "manuell erfasst" (unchanged) |
| the agent recorded it | "erfasst · Agent" (hidden lead "Erfasst von:") — "erfasst" is the existing msgstr of `source_label/1`'s fallback |
| the operator recorded it, the agent corrected it last | "manuell erfasst · korrigiert · Agent" (hidden lead "Zuletzt korrigiert von:") |
| the agent recorded and corrected it | "erfasst · Agent" |
| from a PDF import | "aus einem PDF-Import" (unchanged; that path writes as its own actor) |

An allowance order the agent put reads "Bank B · Agent" in the list
(hidden lead "Freistellungsauftrag von:"), and "Bank B 400,00 (Agent)" in
the disclosure's summary, which is a comma-like list and takes Q3's form.

### ③ Q3 — K12: where the budget's basis line marks the institution (variants)

- **A — recommended: "(Agent)" after the institution.** "… · Bank A, Bank
  B (Agent), Bank C (Agent)", the word joined to its institution by a
  no-break space, hidden lead "Abrechnung von:".
- **B — a closing clause.** "… · Bank A, Bank B, Bank C · vom Agenten:
  Bank B, Bank C".

**Why A.** The mark stands next to what it qualifies, as on Risk. In a
comma list a closing "· Agent" would read as a mark on the last
institution or on the whole line, so the word takes parentheses after the
institution it covers; one word per institution. B names each institution
twice, grows by a clause, and leaves the reader to match two lists.

**Measured:** the basis line is two lines at 420 px in every frame (A, B
and today), and three lines at 320 px in A and B (two today). No frame
scrolls sideways.

**Strings** (new; "Agent" reused):

| | English (msgid) | German |
|---|---|---|
| Hidden lead, statement head (agent recorded) | Recorded by: | Erfasst von: |
| Visible word, statement head | corrected | korrigiert |
| Hidden lead, statement head (agent corrected last) | Last corrected by: | Zuletzt korrigiert von: |
| Hidden lead, basis line (A) | Statement by: | Abrechnung von: |
| Hidden lead, allowance order | Allowance order by: | Freistellungsauftrag von: |
| B only, the clause | by the agent: %{institutions} | vom Agenten: %{institutions} |

**What the story writes into `DESIGN.md`** (Components → the Tax page,
and the 2026-09-26 author amendment's list of places): the statement
head's words per author, the order list and its summary, the basis line's
"(Agent)" after the institution it covers.

### Found while drawing (board 03)

1. **"manuell erfasst" is the source's label, not the author's.** After K12
   the head combines two facts (the source and the author); the table
   above decides how. A statement the agent recorded and the operator then
   corrected keeps "erfasst · Agent": the operator's own writes carry no
   word anywhere, as G12.1-A rules. **Decided here; flips by a comment.**
2. **The budget's basis line has no author per institution to read**:
   `@summary.institutions` is a list of names. The K12 story extends the
   summary's institution entries with the counted statement's author;
   noted so the read-model change is not missed.

---

## Board 04 — the merges: the FIFO restatement, the moving average named, refusals with values as data (K11, H11)

**Board:** `design-language/mockups/ux-design-2026-10-27/04-merge-restatement.html`,
rendered as `04-merge-restatement--1200.png` and `04-merge-restatement--390.png`.

- **Frames.** The merge dialog (`securities/merge_dialog.ex`) with its step
  2 (`securities/merge_preview.ex`: `step/1`, `pair/1`, `body/1`,
  `counts/1`, `refusal/1`), and the depot merge's preview
  (`portfolio_accounts/merge_preview.ex`: "Betroffene Positionen",
  `.merge-positions`, `.merge-lines`, its `.merge-basis`). A desktop frame
  is a 980 px viewport with the 640 px dialog in it; at 390 px the dialog
  is the bottom sheet `app.css` makes it under 720 px, drawn in place.
- **Data.** Source "Larkspur Rail Holding AG" (`DE000000002L`, 10 shares
  bought 2024), target "Larkspur Rail AG" (`DE000000001L`, bought 2025,
  partly sold 2025 and 2026). After the pooled queue the 2026 sale closes
  the source's older, cheaper lot first: realized 2026 +205,00 → +251,40
  (+46,40), open cost 3.640,00 → 3.593,60 (−46,40); 2025 unchanged. The
  depot merge: "Depot Alt" into "Depot Muster".

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **Q4** | K11 — where the security preview states the FIFO restatement | variants | **A** |
| — | K11 — the depot preview names its moving average and says FIFO is unchanged | before/after | after |
| — | H11 — a merge refusal names the identity by kind; the values stand as data | before/after | after |

### ① Q4 — K11: the security merge states the FIFO restatement (variants)

**Triage row:** K11 (S6) — class: integrity; fix: state the figure the
merge changes — compute the FIFO closed trades over each security before
and over the combined rows after, put the realized total per close year
and the open lots' cost for source, target and result into the preview,
its digest and the dialog; in the depot preview say FIFO gains are
unchanged and name the moving-average figure for what it is; extend the
merge invariant test to compare the preview's after-figure with the
report.

**Today.** `MergePreview.body/1` states the holdings as a checked sum
(`.merge-identity` and its basis line), the counts (`counts/1`), the equal
bookings, quotes, settings, events and master data. Nothing states realized
gains. Since ADR-0015's amendment of 2026-10-09 a security has one FIFO
queue across portfolios, so a merge pools two queues and restates realized
gains of closed years; the operator learns it from the Trades facet after
the confirm.

**Variants:**

- **A — recommended: a block of its own, under the holdings, open.**
  "Realisierte Gewinne (FIFO)": per close year "Quelle · Ziel → danach"
  and the change, then "Offene Posten (Einstand)" "Quelle + Ziel →
  danach" and its change, and a basis line. The anatomy is the depot
  preview's: `.merge-block-head`, a `.merge-wide` table, `.merge-lines`
  rows under 720 px, `.merge-basis`; before above, after below in each
  cell. A pair whose figures do not move shows one line, "Realisierte
  Gewinne (FIFO) ändern sich nicht", in place of the table.
- **B — a counts line and a closed disclosure.** "1 Abschlussjahr ändert
  seine realisierten Gewinne (FIFO), 2026: +46,40 — Tabelle" in
  `.merge-counts`, the table behind a closed `details`.

**Why A.** It is the merge's one money consequence: holdings are conserved
and checked, realized gains are not, and closed years change. A states it
next to the holdings identity it complements, with no new anatomy; B
hides how much behind a click while the preview's other money figure is
never hidden. B is the better shape only if previews spanning many years
become common.

**Measured** (Playwright): at 980 px the dialog is 640 px wide; today
459 px tall, A 711 px (the block 604 × 240 px), B 524 px. In a 1200 × 800
window the dialog's cap is 724 px (`calc(100vh - 76px)`), so A fits for two
years and the body scrolls inside the dialog beyond that, as the preview's
other tables do. At 390 px the sheet is 717 px today, 1 045 px in A (the
block 358 × 316 px as three two-line rows) and 800 px in B; the sheet
scrolls inside its 88 vh cap. No frame scrolls sideways.

**Strings** (A; new):

| | English (msgid) | German |
|---|---|---|
| Block head | Realized gains (FIFO) | Realisierte Gewinne (FIFO) |
| Column / row | Close year · Source · Target → afterwards · Change | Abschlussjahr · Quelle · Ziel → danach · Änderung |
| Phone row head | Realized %{year} | Realisiert %{year} |
| Open lots row | Open lots (cost) | Offene Posten (Einstand) |
| Unchanged cell | unchanged | unverändert |
| Phone change line | Change %{amount} | Änderung %{amount} |
| Nothing moves | Realized gains (FIFO) do not change. | Realisierte Gewinne (FIFO) ändern sich nicht. |
| Basis line | In %{currency}, the security's currency. Before, each security over its own FIFO queue; afterwards over the merged one, so a sale closes the oldest lots of both. Realized and open cost change by the same amount; the proceeds stay. | In %{currency}, der Währung des Wertpapiers. Vorher je Wertpapier über seine eigene FIFO-Reihe, danach über die zusammengeführte: Ein Verkauf schließt dann die ältesten Posten beider. Realisiert und offener Einstand ändern sich um denselben Betrag; die Erlöse bleiben. |
| B only, the counts line | %{count} close year changes its realized gains (FIFO), %{years} | %{count} Abschlussjahr ändert seine realisierten Gewinne (FIFO), %{years} |

**What the story writes into `DESIGN.md`** (Components → the security
merge preview): the restatement block, its place under the holdings, its
one-line unchanged state, and that it is the depot preview's anatomy.

### ② K11 — the depot preview names its moving average (before/after)

**Today.** The depot preview's last column is "Realisierter G/V" and its
basis line explains a moving average over both depots' buys
(`portfolio_accounts/merge_preview.ex`). No other screen shows that
figure; the realized gains the Trades facet and a security's Trades tab
read are FIFO over the security's one queue, which a depot merge does not
move. Two different "realisiert" stand side by side with no word on which
is which.

**After.** The column (and the phone line's label) reads "Realisiert
(gleit. Ø)"; the basis line names it ("„Realisiert (gleit. Ø)“: das
Ergebnis des Depots nach gleitendem Durchschnitt …") and ends with "Die
realisierten Gewinne nach FIFO (Erträge → Realisiert, der Trades-Tab)
ändern sich nicht: Die FIFO-Reihe gehört dem Wertpapier, nicht dem Depot."

**Measured:** the dialog grows from 455 to 487 px at 980 px and from 605
to 653 px at 390 px (the basis line's added sentence). The renamed column
head fits on one line at 980 px.

**Strings:** column "Realized (moving avg.)" / "Realisiert (gleit. Ø)"
(new); the basis line's msgid changes to "In each cell before above
(%{source} + %{target}, or %{source} · %{target}), after below. Avg. cost
and “Realized (moving avg.)”: the depot's result by moving average over
both depots' buys, in the security's currency, fees and taxes not
included. Quantity per security = the sum of both depots, checked on
every day; the market value of both depots together stays the same.
Realized gains by FIFO (Income → Realized, the Trades tab) do not change:
the FIFO queue belongs to the security, not the depot." with the German
drawn on the board.

**What the story writes into `DESIGN.md`:** the depot preview's column
name and the basis line's FIFO sentence.

### ③ H11 — a merge refusal names the identity by kind (before/after)

**Triage row:** H11 (S7) — class: injection; fix: apply #965's rule to
identifiers — merge guards and refusals name the identity by kind and
carry the stored values as data fields, never inside the sentence; a
meta-test asserts that no merge refusal message contains a stored
identifier value.

**Today.** The row's core is the guard's `detail`, the sentence the API
and the companion hand the agent (`security_merge.ex`); that half renders
nothing. The page builds its own sentences in `MergePreview.reason/4`, and
they embed the same values: `identifier/1` writes "ISIN %{isin}", "Ticker
%{ticker} (%{currency})" and 'Name „%{name}“ (%{currency})' into
"Nach der Zusammenführung führte eine Kennung der beiden nicht mehr zum
Ziel: %{identifiers}." (the name not isolated in `<bdi>`), the
check-digit reason writes the ISIN into its sentence, and the other-way
remedy writes the target's ISIN or name into its own.

**After** (the page follows the API's shape, so both read the same):

- The sentence names the kind and the count: "Nach der Zusammenführung
  führten 2 Kennungen der beiden nicht mehr zum Ziel:"; "Die ISIN der
  Quelle hat eine falsche Prüfziffer, und die Zusammenführung würde sie
  auf das Ziel schreiben."; "Abhilfe: in die andere Richtung zusammenführen
  — das Ziel in dieses Wertpapier." (the pair cards above already name
  both).
- Each value stands on its own `.merge-refusal__position` line — the line
  `detail_lines/1` already uses for positions — its kind as a muted label
  ("ISIN der Quelle (wie importiert):", "Name der Quelle (wie
  importiert):"), the value in `<bdi>`, an identifier in the pair cards'
  mono face, a name in the text face.

**Measured:** the refusal region grows from 331 to 381 px at 980 px; the
sheet from 792 to 860 px at 390 px. No frame scrolls sideways.

**Strings** (changed or new; the kind labels per identity are new):

| | English (msgid) | German |
|---|---|---|
| Identity reason | after the merge, %{count} identifier of the two would no longer lead to the target: / … %{count} identifiers … | Nach der Zusammenführung führte %{count} Kennung der beiden nicht mehr zum Ziel: / … führten %{count} Kennungen … |
| Kind labels | ISIN of the source (as imported): · Name of the target: · Ticker of the source: … (one per side, identity and kind) | ISIN der Quelle (wie importiert): · Name des Ziels: · Ticker der Quelle: … |
| Check digit | the source's ISIN fails its check digit, and the merge would write it onto the target. | Die ISIN der Quelle hat eine falsche Prüfziffer, und die Zusammenführung würde sie auf das Ziel schreiben. |
| Other-way remedy | Remedy: merge the other way — the target into this security. | Abhilfe: in die andere Richtung zusammenführen — das Ziel in dieses Wertpapier. |

**What the story writes into `DESIGN.md`** (the merge refusal): a reason
names identities by kind; their values follow as data lines.

### Found while drawing (board 04)

1. **Other stored text still stands inside the page's refusal sentences**
   beyond H11's identifiers: rule names in "the target is read by policy
   rules: %{names}", a portfolio name in the split-ratio reason, a depot
   name in the split-linearity reason (`merge_preview.ex` `reason/4`).
   They are names, isolated nowhere in these sentences. **Filed at the
   merge** under the S7 tracker as a follow-up of the same rule
   ("merge refusals on the page: stored names as data lines, as H11 does
   for identifiers"); not widened into H11 here.
2. **"Offene Posten (Einstand)" is a new term on screen.** The Trades tab
   calls the same thing open lots in its own words; the K11 story checks
   the existing msgid and reuses it if one exists. **Fixed in the story.**

---

## Board 05 — Income: a payment with no rate path to the base currency (K07)

**Board:** `design-language/mockups/ux-design-2026-10-27/05-income-rate-path.html`,
rendered as `05-income-rate-path--1200.png` and `05-income-rate-path--390.png`.

- **Frames.** `income_live.ex`, the income facet: the basis line
  (`[data-role="facet-basis"]` and its ⓘ), "Jahresübersicht"
  (`#income-chart`: legend, stacked bars, year labels), "Top-Beiträge",
  and, for A, the realized facet's exclusion note with
  `fx_backfill_control/1`, moved to this facet unchanged.
- **Data.** "Velden Water AG" paid 52,00 CHF into a CHF account on
  08.01.2026; the instance stores CHF rates only from 12.01.2026 (daily
  sync, no history backfill). 2025: 318,40 dividends + 41,20 interest;
  2026: 308,85 convertible dividends + 52,00 interest.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **Q5** | K07 — a payment with no rate path to the base currency | variants | **A** |

### ① Q5 — K07 (variants)

**Triage row:** K07 (S6) — class: integrity; fix: keep a booking without a
rate path out of the income's base-currency totals and name it (count and
currencies), or, if parity stays by decision, state it where the figure is
read: a computation basis on the income payload, in the conversion note,
the MCP description and on the page.

**Today.** `Portfolixir.Portfolios.Income.convert/4` falls back to parity
when `Fx.convert/4` finds no rate on or before the booking date: the
amount enters every base-currency total as if it were in the base
currency, and the entry counts in `unconverted_count`, which the JSON API
serialises (`json.ex`) and no page reads. The facet's ⓘ says the amounts
are converted "zum gespeicherten Kurs des jeweiligen Buchungsdatums". The
three sibling facets do otherwise: Realisiert (`#realized-excluded`), Ein-
& Auszahlungen (`#flows-excluded`) and Kosten (`#costs-excluded`) exclude
such an amount and name it in an attention note that leads the facet.

**Variants:**

- **A — recommended: out of every total, named.** An attention note leads
  the facet, in the siblings' shape: "1 Zahlung konnte nicht umgerechnet
  werden — kein gespeicherter Wechselkurs nach EUR an oder vor ihrem
  Buchungstag — und ist aus jeder Summe ausgeschlossen. Betroffene
  Währung: CHF (Velden Water AG)." with `fx_backfill_control/1` inside it,
  as on Realisiert. The bars, year labels, matrix, top contributors and
  per-position table leave the payment out; the drilled year's payments
  table keeps it, in its own currency, as it lists native amounts.
- **B — parity stays, stated.** The basis line gains "· 1 Zahlung in CHF
  ohne Wechselkurs nach EUR, 1 : 1 gezählt", and the ⓘ the same clause; no
  figure changes.

**Why A.** It is the page's own rule: every other Cash-flow facet, and
Sprint 21's α3 for an unavailable trade (board 09 of 2026-10-09, N8),
leaves out what it cannot convert and says so, never converting at a
neighbouring date's rate — and parity is the furthest neighbour of all.
The remedy exists and sits in the note; after a backfill the payment
converts at its own day's rate and the note disappears. B keeps a sum of
two currencies and asks the reader to discount it, in a basis line, the
weakest place for a fact that makes a total wrong (UX-DR17 puts it in an
attention note). The code shows no reason against A: the flag the
exclusion needs (`converted`) is already computed per entry.

**Measured** (Playwright): A's note is 933 × 140 px at 980 px and 358 ×
302 px at 390 px (with the backfill control); B's basis line stays one
line at 980 px and grows from two to three lines at 390 px. No frame
scrolls sideways.

**Strings** (A; new, in the costs note's form, with "Wechselkurs" as
#1150 rules):

| | English (msgid) | German |
|---|---|---|
| The note (`ngettext`) | %{count} payment could not be converted — no stored exchange rate to %{currency} on or before its booking date — and is excluded from every total. Affected currency: %{currencies}. / %{count} payments … their booking dates — and are excluded … Affected currencies: %{currencies}. | %{count} Zahlung konnte nicht umgerechnet werden — kein gespeicherter Wechselkurs nach %{currency} an oder vor ihrem Buchungstag — und ist aus jeder Summe ausgeschlossen. Betroffene Währung: %{currencies}. / %{count} Zahlungen konnten … an oder vor ihren Buchungstagen — und sind … Betroffene Währungen: %{currencies}. |
| The ⓘ (changed) | … Amounts converted to %{currency} via the EUR hub at the most recent stored rate on or before each booking date; a payment with no such rate is excluded and named. Original currency retained. | … Beträge über den EUR-Hub zum letzten gespeicherten Kurs an oder vor dem jeweiligen Buchungsdatum in %{currency} umgerechnet; eine Zahlung ohne solchen Kurs ist ausgeschlossen und genannt. Originalwährung beibehalten. |
| B only, the basis clause | %{count} payment in %{currencies} without an exchange rate to %{currency}, counted 1 : 1 | %{count} Zahlung in %{currencies} ohne Wechselkurs nach %{currency}, 1 : 1 gezählt |

The currencies list carries the securities in parentheses, as the realized
note names its securities; the API and MCP carry the same as data
(count, currencies) beside the payload's computation basis.

**What the story writes into `DESIGN.md`** (State Patterns → the Cash-flow
facets' exclusion note): Income joins the three facets that exclude and
name an amount they cannot convert, with the backfill as its remedy.

### Found while drawing (board 05)

1. **The ⓘ says "zum gespeicherten Kurs des jeweiligen Buchungsdatums";
   the code uses the latest rate on or before it** (`Income`'s moduledoc
   and `Valuation`). **Fixed in the K07 story** (the changed ⓘ above).
2. **The costs note says "Kurs" where it means "Wechselkurs"** — #1150,
   which Sprint 21's γ4 already builds (board 04 of 2026-10-09); the new
   note is written with "Wechselkurs" from the start.

---

## Board 06 — Accounts and depots: Delete asks, whatever the menu saw (H17)

**Board:** `design-language/mockups/ux-design-2026-10-27/06-delete-confirm.html`,
rendered as `06-delete-confirm--1200.png` and `06-delete-confirm--390.png`.

- **Frames.** `portfolio_accounts_live.ex` `account_menu/1` (through
  `AppShell.row_menu/1`: the caption "Tagesgeld · Verrechnungskonto", the
  items, Delete last in the danger colour), drawn in place; the page's
  inline result. The confirmation is the **browser's own prompt**: the
  root layout's capture-phase listener turns `data-confirm` into
  `window.confirm` (`layout_view.ex`, pinned by
  `test/invariants/destructive_confirmations_test.exs`). The board draws
  it schematically, as board chrome; the app never styles it.
- **Data.** The cash account "Tagesgeld", whose 12 bookings are merged
  into another account while its menu is open; "Depot Muster", "Depot
  USD" as the rest of the list.

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| **Q6** | H17 — Delete asks whatever the menu saw when it opened | variants | **A** |

### ① Q6 — H17 (variants)

**Triage row:** H17 (S6) — class: hardening gap; fix: render the
confirmation on the Delete item regardless of the menu's snapshot, or
refuse the delete when the menu was opened with references and ask once
more; add the control to the destructive-confirmations invariant.

**Which menu.** Of the five `data-confirm={…}` expressions in the web
layer, one is conditional on a snapshot: the Accounts & depots row menu,
`portfolio_accounts_live.ex` `account_menu/1`,
`data-confirm={if @menu.refs == %{}, do: delete_confirmation(@kind,
@account, @menu.buckets?)}`. The references are read when the menu opens
(`handle_event("open_account_menu", …)`); a free account asks once, a
referenced one opens "Kann nicht gelöscht werden" directly (G1-A).

**Today.** When the references go between the menu's opening and the
click, the item renders no confirmation, and `delete_account/3` finds the
account free and deletes it — no prompt, and, since a successful delete
sets no result, no word on the page. The invariant passes: it checks that
the element's text contains `data-confirm=`, which the conditional does.

**Variants:**

- **A — recommended: the item always asks.** `data-confirm` is
  unconditional. A menu that saw a free account asks as today; a menu that
  saw references asks "„Tagesgeld“ löschen? Hat das Konto noch Buchungen
  oder ein verknüpftes Depot, wird das Löschen abgelehnt, und nichts
  ändert sich." After OK: still referenced → the refusal dialog, as today;
  free → deleted, as asked.
- **B — a stale menu never deletes.** The item keeps its snapshot; a
  delete sent from a menu that saw references is refused by the server.
  Still referenced → the refusal; free now → nothing is deleted, and the
  page's result says "Nichts wurde gelöscht: Tagesgeld hat seit dem Öffnen
  des Menüs keine Buchungen mehr. Zum Löschen das Menü erneut öffnen."

**Why A.** It is the fix's first clause and makes #765's rule literal: the
attribute is always there, so the invariant can assert a non-empty value
on the element and no state can switch the ask off. Its sentence never
claims what the menu could not know. The cost is one prompt before a
refusal the operator usually expects. B keeps G1-A untouched but needs two
menus and two clicks to delete what is now free, adds a result for a state
the operator did not cause, and moves the invariant from the element to
the event's handling.

**Measured:** the prompt is the browser's, so nothing in the app's layout
changes in A; B's result note is the page's existing inline result. No
frame scrolls sideways.

**Strings** (new):

| | English (msgid) | German |
|---|---|---|
| A, cash account, menu saw references | Delete “%{name}”? If the account still has bookings or a linked depot, the deletion is refused and nothing changes. | „%{name}“ löschen? Hat das Konto noch Buchungen oder ein verknüpftes Depot, wird das Löschen abgelehnt, und nichts ändert sich. |
| A, depot, menu saw references | Delete “%{name}”? If the depot still has bookings, the deletion is refused and nothing changes. | „%{name}“ löschen? Hat das Depot noch Buchungen, wird das Löschen abgelehnt, und nichts ändert sich. |
| B only, the result | Nothing was deleted: %{name} has had no bookings since the menu was opened. Open the menu again to delete it. | Nichts wurde gelöscht: %{name} hat seit dem Öffnen des Menüs keine Buchungen mehr. Zum Löschen das Menü erneut öffnen. |

**What the story writes into `DESIGN.md`** (amending G1-A's row menu):
Delete always asks once; the sentence follows what the menu saw; a
referenced account's refusal follows the ask.

### Found while drawing (board 06)

1. **A successful delete on Accounts says nothing** (`delete_account/3`
   assigns `result: nil`): the row vanishes with no result, unlike a
   rename or a merge. Small and on the surface Q6 touches. **Fixed in the
   H17 story**: "„%{name}“ gelöscht." as a note-severity inline result.

---

## Board 07 — the copy sheet: a field error or a named answer where a page stopped (H31, K13, H36, H37, H39, H56)

**Board:** `design-language/mockups/ux-design-2026-10-27/07-copy-sheet.html`,
rendered as `07-copy-sheet--1200.png` and `07-copy-sheet--390.png`.

- **What it holds.** One table of every string (German as the page shows
  it, the English msgid), then the four surfaces where the answer
  renders: the account dialog (K13), the statement form (H36), the
  securities list's sort and its result slot (H37, H39).
- **"Heute" frames** show what the operator's screen shows when the page
  process stops: the LiveView remounts, the dialog or form is closed, the
  input is gone, and nothing is said (EXPERIENCE.md records that no
  connection state is styled). They show the screen, not how it was
  reached.
- **Copy rules held:** the errors domain's existing wording wherever one
  exists (`errors.po`); "<label> <message>" for a field
  (`FieldLabel.changeset_message/1`); impersonal voice, the fact and its
  remedy (Voice and Tone); a field error linked by `aria-describedby`
  with `aria-invalid` on the field (UX-DR13).

| Pick | Item | Kind | Recommended |
|---|---|---|---|
| — | K13, H36, H37, H39, H56 (on a page); H31, H36, H37 (API and MCP) | before/after | after |

### The rows

- **K13 (S4) — class: hardening gap; fix:** refuse before binding — the
  tag-bucket and account-name helpers run the text rule first and answer a
  field error or a named refusal instead of querying; a NUL-bearing string
  joins the LiveView event payload sweep. **On screen:** the account
  dialog (`AccountFormDialog.render_form/1`) keeps its input and shows
  the errors domain's existing "darf keine Steuerzeichen und keine
  Zeilenumbrüche enthalten" under the name field, and its alert "Neuer
  Tag darf keine Steuerzeichen und keine Zeilenumbrüche enthalten." for
  the tag; the Imports page's bucket-tag field answers through its
  existing `bucket_tag_error_message/1` path, which gains this refusal
  beside its two (`:name_too_long`, `:name_taken_by_scope_bucket`), in the
  same words.
- **H36 (S4) — class: hardening gap; fix:** never query with a field of an
  invalid changeset — the tax parameter upsert takes its fetch branch only
  for a valid changeset, and the statement changeset checks the holder's
  text rule before the profile lookup. **On screen:** the statement
  form's existing problem note (`#tax-form-error`) says "Steuerpflichtige
  Person: darf keine Steuerzeichen und keine Zeilenumbrüche enthalten",
  and the field carries `aria-invalid`. The tax parameters have no page;
  the API answers 422.
- **H37 (S4) — class: hardening gap; fix:** type the registry's
  attribute-backed numeric fields at write (coerce or refuse with 422) and
  make the sort total with a numeric-pattern guard before the cast.
  **On screen:** sorting the securities list by "Rang
  Marktkapitalisierung" (`SecurityFields`' attribute-backed integer field,
  ordered by `Catalog.order_by_field/3`) works; a stored value that is no
  number sorts with the empty ones, last, and its cell shows what is
  stored, as today. No string. The API answers a non-integer value with
  422.
- **H39 (S3) — class: resource exhaustion; fix:** refuse the sync and
  retry events server-side while a run is in flight, give the quote sync a
  catalog-wide single-flight key, and make the logo retry a no-op while a
  drain is pending. **On screen:** "Kurse aktualisieren" pressed while the
  scheduled sync or another window's runs answers in the page's result
  slot: "Eine Kursaktualisierung aller Wertpapiere läuft bereits; sie
  wurde nicht ein zweites Mal gestartet." (note severity: nothing is
  wrong, nothing is lost). The single-security sync keeps its existing
  "Eine Kursaktualisierung dieses Wertpapiers läuft bereits." The logo
  retry's no-op keeps today's result ("Logo-Suche für alle Wertpapiere
  ohne Logo eingereiht.", still true): no new string.
- **H56 (S5) — class: hardening gap; fix:** name the version only when it
  is a string or an integer; answer every other value with the generic
  "could not be read as a Portfolio Performance export" message. **On
  screen:** the existing "Die Datei ist nicht als
  Portfolio-Performance-Export lesbar." where the page stopped; no new
  string, no frame (the message's anatomy ships).
- **H31 (S4) — class: hardening gap; fix:** bound `position` to the
  database integer's range in the four classification and category
  changesets, and in the four MCP schemas. **No page renders it:** no
  form posts a position (`classifications_live.ex`'s category forms carry
  name, parent, colour and description); the API and MCP answer 422 with
  the errors domain's existing "must be greater than or equal to" / "less
  than or equal to %{number}" messages. Listed for completeness; the
  picture of every page is identical.

**Strings** (new; everything else above is reused):

| | English (msgid) | German |
|---|---|---|
| H39, the result | A price sync of every security is already running; it was not started a second time. | Eine Kursaktualisierung aller Wertpapiere läuft bereits; sie wurde nicht ein zweites Mal gestartet. |
| K13, the tag alert | New tag %{message}. (`FieldLabel` "New tag" + the errors-domain message) | Neuer Tag %{message}. |
| H36, the field label in the note | Taxpayer (existing msgid, now used by `error_text/1`) | Steuerpflichtige Person |
| H37, API only | attributes: market_cap_rank must be a whole number | — (the API answers in English) |

**Measured:** the account dialog stays 460 px wide; the field error is one
line at 460 px. No frame scrolls sideways at 980 or 390 px.

**What the stories write into `DESIGN.md`:** nothing new in anatomy; the
H39 result joins the securities page's result list, and the account
dialog's field association is recorded under UX-DR13's call sites.

### Found while drawing (board 07)

1. **The account dialog's text fields are not associated with their
   errors** (`account_form_dialog.ex` `text_field/1`: a `.field-error`
   under the input, no `aria-invalid`, no `aria-describedby`), a UX-DR13
   violation independent of K13. **Fixed in the K13 story**, which is the
   first to give those fields an error a reader must find.
2. **The statement form's problem note prints a raw field key for every
   non-money field** (`tax_live.ex` `field_label_or_name/1` falls back to
   `to_string(field)`: "institution: …", "as_of: …"), a raw value in a
   user-facing string (Voice and Tone, 2026-09-12). **Fixed in the H36
   story** (labels for holder, institution and date, with the meta-test
   the rule asks for).
3. **The holder field carries no `aria-invalid`** while the institution
   and date fields do. **Fixed in the H36 story.**

---

## K10 — no board: the picture does not change

**Triage row:** K10 (S6) — class: hardening gap; fix: refuse a split-typed
booking on the ledger's generic create path unless the split flow calls
it, as the update path already does, and offer only buy and sell in the
booking drawer.

**Why no board** (the sprint workflow's exception: "identical picture").

- **Today** the drawer's "Typ" lists exactly "Kauf" and "Verkauf"
  (`transaction_management_live.ex` `booking_drawer/1`,
  `for type <- ["buy", "sell"]`). Nothing on the page offers a split; the
  weakness is that `save_transaction` passes the posted type on, so a
  value no control offers reaches the ledger's generic create path.
- **After Sprint 21's α6 (board 03 of 2026-10-09, pick N12 A, adopted),**
  "Typ" lists Kauf, Verkauf, Dividende, Zinsen, Einlage, Entnahme,
  Gebühren, Steuern, Steuererstattung — still no split, which stays on the
  security's "Split erfassen" flow.
- **K10's fix** is an allow-list of the drawer's own kinds on the server
  and the ledger's refusal; both pictures — today's and N12's — are
  unchanged by it. A posted kind that no control offers is refused as the
  drawer refuses any invalid field today; no operator path reaches that
  state.

The amendment's D-4 table names "board Q-K10 on top of board 03's N12";
this document finds that board would draw N12's drawer unchanged, so none
is drawn. **The plan's line should read "no board: K10 renders nothing;
N12's kind list already has no split".**

---

## Rows that render nothing new

Every other row of Part 3 was read against the code it touches. These
change no picture, or change a state only through anatomy that already
ships:

- **S1** (H03, H04, H18, H22, H41, H19, H20, H49, K02, K18): throttles,
  boot checks, cookies, socket origins and documents. H19's expiry
  re-check sends a mounted page to the existing login; H41 and K02 change
  whether a remembered preference is kept, not how it shows.
- **S2** (H27, H09, H69, H70, H71, H06, H72, K01, K03, K04, K05, K16):
  listener, logs, boot and release tooling; no page.
- **S3** H50, H51, H52: provider parsing and file hygiene; no page. (H38
  and H39 are on boards 01 and 07.)
- **S4** H01, H02, H58, H59, H26, H16, H30, H55, K06, K08: parsers,
  bounds, redirects and the API's renderer. K06's non-positive rate takes
  the existing excluded-and-named paths (the exclusion notes on Income's
  facets and Wealth), which already render. **H07 and H08** park the
  preview differently; they render nothing **provided** the H08 story
  takes the fix's first shape (park what the remount needs). Its second
  shape ("refuse to park, with a message") would add a message to the
  Imports page and needs a board before it is built.
- **S5** H53, H54: the dry run and the default portfolio's lock; no page.
- **S6** H61, H62 (actors and journal), H35 (a refusal through the
  existing 422 and the drawer's existing settlement field error), H44 (the
  picker's refusal now changes nothing; the same note, the stored state
  unchanged), H60 (lock order), H10 (compaction), K09 (the figures follow
  the shares actually held; the anatomy is unchanged), K14 (the dialog's
  writes in one transaction; the refusal renders as today), K17 (API
  paging).
- **S7** H12 (wider invisible-character sets: the existing
  `invisible_text_note/1` and field errors carry them), H13 (MCP hints),
  H21, H25, K19 (tests and documents).
- **S8** all rows: CI and supply chain.
