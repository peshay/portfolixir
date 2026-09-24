# UX Design Pass — 2026-09-24, Sprint 16's user-visible items

Scope: **every** user-visible change Sprint 16 proposes, held against the
living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.md).
`DESIGN.md` and `EXPERIENCE.md` are the authority, and this document proposes
against them. It runs **on the planning PR, before the batch**, as the standing
rule of 2026-09-20 requires (AGENTS.md → "A UI change is mocked before it is
built").

Mockups: `design-language/mockups/ux-design-2026-09-24/`, one HTML board per
item with every variant, rendered to PNG with Playwright (`render.mjs` in the
same folder) and reduced to a 256-colour palette so the twelve boards stay
around 6 MB. The boards link the real `priv/static/app.css` and use the live
pages' markup and German labels. Each board was drawn by one author and then
held against `DESIGN.md`, `EXPERIENCE.md` and the review rubric by a separate
design critic, who corrected it before it was committed. The data is invented:
generic account names ("Girokonto", "Tagesgeld (alt)", "Depot 1"), the
committed seed's security names and invented ones in the same style, obviously
fake identifiers such as `XS0000000001`, and made-up figures. **No real
instrument, position, balance, account, provider or rate appears.**

A pick's code is its board's number (board 12, which holds three, numbers
them G12.1 to G12.3). **The owner walked through the boards on 2026-09-24 and
picked every one; each pick is the option marked below.** The story that
builds a pick writes its anatomy into `DESIGN.md`.

| Pick | Item | Board | Variants | Picked |
|---|---|---|---|---|
| **G1** | Lifecycle controls on Accounts & depots (#328, ADR-0050) | `01-accounts-lifecycle` | the existing row menu, one dialog per action · one "edit" dialog with a danger zone | **A** |
| **G2** | The merge preview and confirm (#328, ADR-0050 §7, §8, §10) | `02-merge-preview` | one dialog, target on top and preview below · two steps, target then the preview of exactly that pair | **B** |
| **G3** | The identity choice in the security merge (#608, ADR-0050 §9) | `03-security-merge` | two option cards with one consequence line each · a side-by-side compare | **A** |
| **G4** | Remembering a remap in the import preview (ADR-0050 §3–§5) | `04-import-memory` | a checkbox in the row, only where a prefill was changed · one toggle at the end of the step | **A** |
| — | Numeric inputs in the page's locale (#869) | `05-numeric-inputs` | none (before/after) | n/a |
| **G6** | A view-context rule's reach from a refused delete (#871) | `06-view-rule-reach` | links in the existing message band · a view switcher on Risk · the refusal dialog for views | **A** |
| **G7** | The rule name as a control, and the rename (#872, D-6) | `07-rule-name-affordance` | the name as a link at rest · a row kebab per rule · a visible "edit" button | **A** |
| **G8** | Classification detail at 390 px and the live children-Σ hint (#873, #874) | `08-classification-detail` | for the category row only: two lines under 560 px · "+N" with the rest in the title | **A** |
| — | Allocation → Positions at 390 px (#875) | `09-allocation-positions` | none (before/after) | n/a |
| **G10** | The area tab row at its end (#876) | `10-area-tab-end` | a trailing inset with arrival on a tab boundary · accept the fragment and amend D6 · mandatory snapping with scroll padding | **A** |
| — | E25's visible states (the security pass) | `11-security-visible-states` | none (before/after) | n/a |
| **G12.1** | The author of an agent-written policy rule on Wealth → Risk (G30, T-8) | `12-e25-new-marks` | "Agent" as the last word of the rule's words line, plus the author in the version list · the author in the version list only | **A** |
| **G12.2** | Stored text carrying invisible characters (G20) | `12-e25-new-marks` | an inline escape chip per character · one attention data note with the escaped text in a disclosure | **B** |
| **G12.3** | Editing a stored split row (G07) | `12-e25-new-marks` | the split's facts disabled, only the note editable · no edit item on split rows | **A** |
| — | The bucket-delete confirm (G19, T-10) and a zero-value position's drift (G14) | `12-e25-new-marks` | none (before/after) | n/a |

**Items with no board.** #870 (every row kebab named for its row) changes the
accessible name and nothing a sighted reader sees, which is the rule's stated
exception ("identical picture"). NFR-9 adds tests only. Most E25 items change
no rendered output (session and token handling, headers, Compose and image
pinning, the outbound request path, journal before-images) and need none.
Every E25 item that does is on a board: four before/after repairs on board 11
(Part 11), and three new marks with their picks plus two more before/after
repairs on board 12 (Part 12).

---

## Part 0 — What governs this pass

**Four of the picks are ADR-0050's surfaces**, and one constraint from the ADR
shapes all four: a merge is **preview-then-confirm with a digest**, so the
screen that confirms must show exactly the plan the digest covers, and
nothing above it may change that plan while it is read (§10). That is why G2
recommends two steps over one dialog, and why G3 reuses G2's anatomy rather
than inventing a second one.

**Two picks finish E24's surface** (G6, G7). Both follow the spec's rule
"solve each recurring job once": G6 adds no element and puts a link where the
refusal already speaks, and G7 gives the rule name the same treatment the
scheduled and retired rule names below it already carry.

**Four boards are conformance repairs** (05, 09, 11, and most of 08), and
board 12 carries two more beside its picks. The spec
already fixes their answer, so they show before and after. Board 08 turned one
repair into a pick: the 16 px gutter the spec requires takes the width the
category name needed, so the "+N" collapse the issue sketched would have left
three letters of the name (measured on the board). G8 is the honest answer.

---

## Part 1 — G1: where rename, merge and delete live (#328)

**Before:** the Accounts & depots page has one row menu, on the depot row of a
pair, holding "Getrennt taggen". Rename, merge and delete exist on the API and
MCP only; a cash row has no menu at all.

**Variant A (recommended): the existing row menu, one dialog per action.** Every
entity row gets its kebab (the depot row, the cash row of a pair and the lone
cash account; the repeated row of a shared account gets none). Items are
ordered by consequence: Umbenennen · Getrennt taggen (merged pair only) ·
Zusammenführen in… · Löschen (last, danger colour). The rename dialog says the
old name stays remembered for imports, or, when another account still has that
name as its live name, that an import naming it books to that account
(ADR-0050 §4; the board draws the common case); a blocked delete opens the "cannot be
deleted" dialog the securities page already has, with "Zusammenführen in…" as
its way out (not a flash); former names are listed under the name, each with
"Entfernen" and a confirm that states the consequence. At 390 px the kebab sits
on the name row, the menu opens as the existing sheet.

**Variant B: one "Bearbeiten" dialog per account** with name, former names and
a danger zone for merge and delete. It keeps an account's identity in one place
and shows why delete is blocked before the click. It also introduces a third
treatment for destructive actions next to the red menu item and the rule
dialog's footer, and it would open the merge preview as a dialog on a dialog.

**Why A.** It extends a menu the page already has instead of adding an entry
point, follows the tables pattern (row actions behind the kebab, destructive
last) and reuses overlays the inventory already lists.

**DESIGN.md, written by the story:** an amendment "Accounts & depots: lifecycle
controls (G1-A)" with the menu order, the rename, delete-blocked and
former-names anatomy, and the 390 px behaviour.

---

## Part 2 — G2: the merge preview and confirm (#328)

**Variant A: one dialog**, the target as a select on top and the preview below,
recomputed on every change. Target and consequence are in view together. But
a non-selectable target's reason sits inside a disabled option that is readable
only while the list is open; a target change silently discards the operator's
choice about duplicate pairs; and at 390 px the picker is a screen above the
destructive button.

**Variant B (recommended): two steps.** Step 1 lists every account with a
reason for each one that cannot be chosen ("andere Währung", "andere
Liquiditätsrolle", "andere Buckets"). Step 2 is the preview of **exactly one
pair**, and so of exactly one digest: the "source → target" line; the balances
as a sum (source + target = merged, with the alternative if duplicates are
removed); the counts; each restated anchor as "set + other account = after";
the key-equal pairs with an **unpreselected** choice whose options each state
the resulting balance; the former-names note; and the destructive confirm. A
depot merge shows the affected positions before and after instead of balances.
A changed plan answers with the fresh preview, never a silent re-apply.

**Why B.** It is the shape ADR-0050 §10 describes: the operator confirms what
the digest covers, and nothing can change it on screen while it is read.

**Left to the story, and named so it is decided rather than drifted into:**
whether a choice the operator made survives a `plan_changed` refresh (the
recommendation is that it does not: a changed plan is a new question), and the
new `.modal-footer--band` modifier, the one class the board adds.

**DESIGN.md, written by the story:** an amendment "Lifecycle merge — preview
and confirm (G2-B)": placement, the two steps' anatomy, the refusal and stale
states, and the depot variant.

---

## Part 3 — G3: the security merge (#608)

The flow reuses G2-B, entered from the securities row menu ("Zusammenführen
in…", after "Als Benchmark markieren", not danger-coloured) and from the
existing delete-blocked dialog. The preview lists what the merge does to
bookings (duplicates, with the same unpreselected choice), quotes (gap-filled;
on a collision the target wins, the collisions are counted and only the
colliding manual quotes are listed, the rest go to the merge manifest),
configuration (assignments, position
targets and overrides moved or dropped, each with its reason), events (moved,
with possible duplicates listed) and master data (every difference named). A
source with research notes or policy rules is refused with its remedy ("merge
in the other direction, or keep both"), and the survivor's detail shows
"Zusammengeführt aus …".

**Variant A (recommended): two option cards for the ISIN**, each with one
consequence line ("XS…01 behalten — XS…02 wird frühere ISIN"), no preselection;
only the "adopt the source's ISIN" card, which is ADR-0029 §3's wrong-order
repair, shows the ISO date field for the change.

**Variant B: a side-by-side compare** of both securities with the ISIN pick
inside the table. It shows every identifier at a glance, but two radios in two
cells form no labelled group for a screen reader, the consequence sits two
columns away, and the dialog would have a second form for a choice.

**Why A.** One form for every choice in the merge dialog, a labelled group, and
the consequence next to the option. ADR-0050 §9 now states the choice is
required and never preselected (added on this PR after the board raised it).

---

## Part 4 — G4: what the import preview says after ADR-0050

The mapping step shows, per row, how many of the file's bookings are **already
imported** and, when all are, "nichts anzulegen"; a prefill that came through a
former name says so ("Girokonto, früher Giro"); an ambiguous name gets no
prefill and states why; and the result lists **internal transfers skipped** and
duplicates with the layer that caught them.

**Variant A (recommended): a "Zuordnung merken" checkbox in the row**, ticked by
default, shown only where the operator changed a prefill onto a differently
named account, with one line saying which name becomes a former name of which
account (and "gilt nur für diesen Import" when unticked).

**Variant B: one toggle at the end of the step.** One decision in one place, but
far from the rows it affects, and all-or-nothing: one mistaken remap can only be
left unremembered by dropping all the others.

**Why A.** Each remap is decided where it is made. ADR-0050 §4 now also says
what happens when the remembered name is already another account's former name
(it moves, and the preview says so), which the board raised.

---

## Part 5 — #869: numeric inputs in the page's locale (before/after)

**Before:** prefilled amounts and rates come back with a decimal point on a
German page, next to a price the operator typed with a comma; the rule dialog's
numeric inputs are left-aligned although they carry `class="num"`, because the
generic rule covers table cells only; four places parse a comma, each its own
way.

**After:** one helper renders every decimal input value in the page's locale
(a comma in German, never a thousands separator, the caller's digits unchanged)
and reads it back with one rule; `input.num` is right-aligned with tabular
figures. Date inputs stay ISO (UX-DR19), which is why the issue's date bullets
close as spec-conformant.

**Open points for the story:** whether money fields pad trailing zeros ("45,6"
vs "45,60") is a separate choice to record; a pasted grouped figure
("1.664,40") stays refused, because it is exactly the ambiguity the parser
declines to guess.

---

## Part 6 — G6: a view-context rule's reach (#871)

**Before:** deleting a view that a rule reads is refused in the message band,
which says to look on Risk. Risk shows only the active view's rules and has no
view switcher, so a rule whose context is another view is not where the message
says it is.

**Variant A (recommended): the band links each rule** to `/risk?view=<its
context>` as a full navigation (so the view scope is stored), and names the
view in the parenthesis. No new element, consistent with the Sprint 15 board
`06-rule-reference-409`, which kept the band for view deletes.

**Variant B: a view switcher on Risk.** Useful on its own, but it does not tell
the operator which view the refused rule lives in.

**Variant C: the refusal dialog for views too.** The form the issue asked for;
it reopens the Sprint 15 pick for one of three kinds of delete.

**Why A.** It fixes the reach where the refusal already speaks. The board also
corrected a sentence in ADR-0049 §8: retiring a rule does **not** free the view
it names; the correction is on this PR. The shape half of #871 (the dialog for
a view delete) is declined with this reason, and the issue says so when it
closes.

---

## Part 7 — G7: the rule name as a control, and the rename (#872)

**Variant A (recommended): the name as a link at rest** (accent colour and
underline, still bold, still the only control), the same treatment the
scheduled and retired rule names below it already carry. The edit dialog gains
the name field on edit, with a line saying a rename creates no new version.

**Variant B: a row kebab per rule** with edit, rename and retire: two entries
into the same dialog, and at 390 px the table would scroll sideways (measured).

**Variant C: a visible "Bearbeiten" button per row:** no other table in the app
carries a standing button, and at 390 px it sits half outside the frame
(measured).

**Why A.** One treatment for "open this rule" across the section, nothing new
to build, and the table still fits at 390 px. Its cost is honest: the link
treatment in light mode sits below the spec's contrast bar for body text, as
every link already does; that is a token question, filed separately (Part 13,
item 1), not a reason to keep the name silent. The rename itself is plan D-6,
and ADR-0049 §4 is amended on this PR to say the name is a label outside the
versioning.

---

## Part 8 — G8: the classification detail at 390 px, and the live Σ hint (#873, #874)

**Before/after (no pick):** the page's blocks gain the 16 px side gutter every
other page has; the plan editor's "Umbenennen" disclosure uses the one
disclosure marker (#854) instead of the browser's triangle; the per-parent
"Σ Kinder" hint recomputes live while typing, including categories whose weight
follows their position targets, instead of vanishing until the next save.

**G8, the category row once the gutter is in (a pick the board found):**

- **Variant A (recommended): the row wraps to two lines under 560 px**: the
  name, which may wrap, with its "+1 ohne Bestand" on the first line, and value
  and result under their column heads on the second. The name gets the width it
  needs (measured on the board).
- **Variant B: "+N" only**, the rest in the title, as the issue sketched. With
  the gutter in, the name keeps only a few letters (measured), which misses the
  spec's rule that the name survives under 560 px, and a title is unreachable on
  a touch screen.

**DESIGN.md, written by the story:** the `section-pad-inline` token corrected to
the 16 px floor #790 built, one sentence on pages whose blocks are not all
bands, and the two-line row under 560 px.

---

## Part 9 — #875: Allocation → Positions at 390 px (before/after)

1. The rebalancing hint's verb column sizes to its word, so "Verkauf" no longer
   runs into the "≈", and the "≈" stays on one vertical line across rows.
2. A hint whose quantity rounds to zero is not shown; the drift stays.
3. The cash row's category reads "—" in the row's muted treatment instead of
   "Nicht zugeordnet".
4. The Tree/Positions toggle uses the spec's segmented selected state, so the
   two states look different, not only sound different.
5. The existing basis line gains "— Abweichung gegen den verteilten Anteil"
   when the plan sums below 100 %, following ADR-0040 §2, which already decided
   the computation. The top-level Σ keeps the warning colour only **above**
   100 %, as D3 and ADR-0040 §3 say, so existing tests that pin the warning on
   an under-100 % sum change with the story.

Three things the critic found outside #875 on the same surface are listed in
Part 13.

---

## Part 10 — G10: the area tab row at its end (#876)

**Before:** the AreaTabs hook (#857) centres the active tab, and the browser
clamps the scroll at the row's end. On Steuern and Risiko at 390 px the row
comes to rest with a clipped fragment of the previous tab under the left fade,
which D6 says never happens and board `ux-design-2026-09-23/04`'s "after" did
not show.

**Variant A (recommended): a trailing inset and arrival on a tab boundary.**
When the row overflows, the hook gives it a trailing inset exactly as wide as
the distance from its maximum scroll to the next tab start, and brings the
active tab to rest on the last tab start at or before its centring target at
which it is whole. Measured in Chromium at 390 px, every page then rests with
a whole tab at the left. D6 and board 04 hold as written; the cost is a little
empty space after the last tab at the row's end. A row that does not overflow
gets no inset.

**Variant B: accept the fragment and amend D6.** No code, but the exception
lands exactly where the rule was broken, and every later overflowing row would
inherit it.

**Variant C: mandatory snapping with scroll padding.** CSS only, and it does
not fix #876: a snap point past the maximum scroll is clamped the same way, and
the padding moves every other rest, which spreads the fragment to four of six
pages (measured).

**Why A.** It is the only variant that makes the rule true. The board also
notes that the Wealth tabs' live labels are "Allokation & Ziele", "Cashflow"
and "Snapshots"; board 04 of Sprint 15 drew working names.

**DESIGN.md, written by the story:** one bullet under Tab row overflow (D6),
after #857's bullet, stating the row's end is a tab boundary. The measured
widths are Chromium's; the story's layout test asserts the rule (a whole tab at
the left on arrival), not the pixel values.

---

## Part 11 — E25's visible states (before/after)

Most of E25 changes nothing a reader sees. Four places repair an existing
slot, one each from S2, S3/S4, S5 and S6, and board 11 draws each as it
renders today and as it will after the fix; the new marks are Part 12's. The board shows the
operator-facing message and state only, never how the input is made
(`security-review-triage-2026-09-24.md`, Part 6).

1. **Imports: a file that stalls or crashes the preview** (S5). Today the
   upload stops without a word, and the parked preview brings the failure back
   on every reload. After: the parser refuses the file before anything is
   parked, and the named file error appears in the existing error band above
   the drop zone, where "Unbekanntes Dateiformat" shows today; the drop zone
   takes the next file at once. A security entry without a name and an ISIN
   becomes an ordinary row warning in the existing "Parser-Warnungen" box.
2. **The research log refuses a future date** (S6) in the form's existing
   error list, in the "Feld: Meldung" pattern, and the timeline and the thesis
   stay unchanged. Two requirements the board surfaced ride the story: the
   form's error list is translated through `errors.po` like the booking form's,
   and a refused submit keeps what the operator typed.
3. **Wealth → Risk survives a pair it cannot compute** (S3, S4). Today the page
   fails to render at all. After: the pair reads "nicht berechenbar" with its
   observations, the table's existing treatment for a missing value, and the
   basis line names how many of the largest names the correlations run over.
4. **Error pages for every status** (S2). Today any status other than 404 and
   500 turns into a bodyless 500 and the reason is lost. After: the app's plain
   error body with the correct status and a status line in the page's
   language.

New copy follows the plain-voice rule; the msgids are named on the board. No
pick: each is a conformance repair to an existing slot.

---

## Part 12 — E25's new marks and two changed confirmations (board 12)

Board 11 draws what the hardening says; board 12 draws the three new marks E25
adds and two more before/after repairs, all placed by decisions this merge
signs (T-8, T-10) or by rows it adopts (G07, G14, G20). Operator-facing states
only (triage, Part 6). Because plain G12 to G14 are already finding ids in the
triage, the board's picks are numbered **G12.1** to **G12.3**.

**G12.1 — the author of a policy rule (G30, T-8).** *Before:* no version
carries an author, and every row reads as the operator's standard. *Variant A
(recommended):* "Agent" as the last word of the rule's words line
(`.policy-rule__words`) on rules whose in-force version the agent wrote,
scheduled and retired rules alike, plus the author on every entry of the
dialog's version list ("Operator" / "Agent", the research log's words).
*Variant B:* the author only in the dialog's version list. *Why A:* the
findings table is where "am I inside my limits?" is answered, and under B the
agent's line looks exactly like the operator's there. A badge was weighed and
dropped: in this table `.badge--neutral` already means "met", dashed means
undetermined, accent means "yours" and warning is a severity, so the word
stays calm, survives forced colours and wraps with its line at 390 px. A
rename (D-6) makes no version and does not move the mark; the journal names
who renamed. Choosing B rewords G30's fix to "name the author per version".

**G12.2 — stored text with invisible characters (G20).** *Variant A:* each
invisible character as an inline escape chip. *Variant B (recommended):* one
`attention` data note (`AppShell.data_note`) where the stored text renders,
with its remedy as a child control ("Eintrag anhängen, der #n ersetzt",
"Stammdaten bearbeiten") and the escaped text in a disclosure, spelled the way
the MCP boundary emits it. *Why B:* the spec's component for a fact about the
data, with glyph, word and colour; one line whatever the count; and it works
where A cannot render (`<option>`, `title`, `aria-label`, chart labels) and
where A would split a screen-reader sentence at every chip. Stored text inside
running text is wrapped in `<bdi>`, so any reordering stops at the element's
edge. The surfaces: research entries, invalidation conditions and retraction
reasons (the thesis included), appointment notes, the booking drawer above
"Kosten und Notiz", and names where they are renamed. Lists, selects,
headings and the history's "Notizen" column stay unmarked. One `app.css`
rule is proposed with it (the escaped text's wrap in the note body).

**G12.3 — editing a stored split row (G07).** *Before:* the full booking
drawer: "Kauf", empty required quantity and price, and a demanded depot the
row does not have. *Variant A (recommended):* type, Stichtag, security and
"Verhältnis (neue:alte Aktien)" as disabled fields, the note editable under
"Notiz speichern", and a help line that states the limit without a link: a
wrong split cannot be corrected here; it is deleted over API or MCP and booked
again with "Split erfassen". *Variant B:* no edit item on split rows. *Why A:*
the note stays editable over API and MCP, so the screen keeps the way there,
and an attempted correction gets its answer where it happens; B removes the
row's only action without a word.

**G19 and T-10 (before/after).** The bucket-delete confirm gains one sentence:
a position whose only specific bucket is the deleted one stays at "keine
Buckets (ausgeschlossen)" and does not inherit from its depot. The MCP tool
description says the same.

**G14 (before/after).** A zero-value position's drift cell shows "—" instead of
a signed "-0,00 EUR", the way an unassigned position already renders, and the
row sorts last. The API returns `null` for that value, and the payload's basis
names the case as a gap.

**`DESIGN.md`, written by the stories:** the author word in the rule's words
line; the invisible-character note's anatomy and its one wrap rule; the
split-row drawer state.

---

## Part 13 — What the critics found outside this pass (Scope Lock)

Each is real, each is outside the item its board draws, and each is **filed at
branch opening** by Lane Z rather than fixed on the way (AGENTS.md → Scope
Lock). None is built in Sprint 16: no lane of the plan schedules them, and a
later plan picks each up with its own board.

1. **Link colour contrast in light mode** (board 07). `DESIGN.md` bars
   body-size accent text in light mode, and every `.link-button` already sits
   below that bar; G7-A spreads the treatment to the rule names but does not
   create the gap. The fix belongs to the colour token (or a link-text token),
   and `DESIGN.md`'s computed contrast table should be re-checked in the same
   pass, because one of its verdicts looks inverted.
2. **The import result's summary cards** (board 04): the German label
   "Verrechnungskonten" runs past its card.
3. **The rule dialog's version list** (board 05) shows its list numbers in
   front of "Version 1", "Version 2", which numbers each entry twice.
4. **Allocation → Positions** (board 09): the pinned subject column has no
   effect, because the table is itself the scroll container; the allocation
   section's basis line has no style of its own; and the drift ⓘ does not
   mention the allocated portion.
5. **No booking can be deleted from the screen** (board 12). "Delete and
   rebook" exists only over API and MCP, so G12.3's help line names them and
   carries no link. A "Split löschen" action is the missing human view of an
   existing capability (AGENTS.md → API and MCP coverage, both directions);
   its story adds the link to "Split erfassen".
6. **The history's split-ratio cell** (board 12): "2:1" sits at the left of
   the right-aligned quantity column and carries no `.num`, the alignment
   family `DESIGN.md` already names.
