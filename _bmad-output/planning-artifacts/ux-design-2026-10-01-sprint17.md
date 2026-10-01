# UX Design Pass — 2026-10-01, Sprint 17's user-visible items

Scope: **every** user-visible change Sprint 17 proposes, held against the
living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html).
`DESIGN.md` and `EXPERIENCE.md` are the authority, and this document proposes
against them. It runs **on the planning PR, before the batch**, as the standing
rule of 2026-09-20 requires (AGENTS.md → "A UI change is mocked before it is
built").

Mockups: `design-language/mockups/ux-design-2026-10-01/`, one HTML board per
item with every variant, rendered to PNG with Playwright (`render.mjs` in the
same folder, unchanged from the 2026-09-24 pass) and reduced to a 256-colour
palette. The boards link the real `priv/static/app.css` and use the live
pages' markup and German labels. Each board was drawn by one author against
`DESIGN.md`, `EXPERIENCE.md` and the review rubric, and checked by eye at
every rendered width. The data is invented: the committed seed's names and
invented ones in the same style, obviously fake identifiers such as
`XS0000000001`, generic account names ("Girokonto", "Tagesgeld (alt)",
"Depot 1"), and made-up figures and 2026 dates. **No real instrument,
position, balance, account, provider or rate appears.**

A pick's code is its board's number. **The recommendation is the default; a
comment naming another variant changes it; silence adopts it.** The story
that builds a pick writes its anatomy into `DESIGN.md`.

| Pick | Item | Board | Variants | Recommended |
|---|---|---|---|---|
| **G1** | Trades: reach, the p.a. column and the unmatched sells (#984 rescoped, Lane T) | `01-trades-reach` | the facet renamed "Trades" plus an Overview card with the last five closed trades · a top-level nav entry and route `/trades`, the facet removed and redirected | **A** |
| **G2** | The merge-record list (ADR-0050 §12, two-way deadline, Lane V1) | `02-merge-records` | a collapsed section at the end of Accounts & depots, all three kinds in one list · the same section on the Imports page · no list, a disclosure per survivor | **A** |
| **G3** | Releasing manual quotes (T-9, two-way deadline, Lane V2) | `03-quote-release` | a data note on the Quotes tab with the count and span of manual quotes, its remedy opening a range dialog · an item in the securities row menu, same dialog · a selection on the quote table's manual rows | **A** |

**Items with no board.** Everything in the plan's Lanes A, G, P, D and M
changes no rendered output: the MCP profiles, descriptions, schema budget and
prompts, `llms.txt` and the "Connect an agent" page (documentation site, not
the app), the README, the harnesses, the release workflow, and the first-run
debt (Lane D stops and boards any item that turns out to change a pixel). T1
and T1b change the payload; what they put on the screen is board 01's.

---

## Part 1 — G1: trades, reached (#984 rescoped)

**Before:** the closed round-trips already exist as Cash flow → "Realisierte
Gewinne", two levels below an Overview that says nothing about whether a
trade paid off. A sell with no matched buy (shares that arrived by an inbound
delivery, which opens no lot) is left out of every figure and named nowhere.

**Decided by the plan (D-7), drawn in both variants:**

- a "p. a." column directly left of Result, from 365 days of holding; below
  that a muted "—" whose reason rides the cell's title, a visually hidden
  sentence and the basis line (an ⓘ in the header would be clipped by the
  table wrapper's overflow);
- a basis line under the list: FIFO per security across all depots, fees and
  taxes in basis and proceeds, income while open not included, deliveries
  open no lot, p.a. only from 365 days;
- an attention note naming the unmatched sells, with a security · date ·
  quantity disclosure (UX-DR25), after the existing currency-exclusion note
  when both appear;
- two-line rows under 560 px (UX-DR27).

**Variant A (recommended):** the facet switch reads "Trades" (the URL stays),
and the Overview gains an "Abgeschlossene Trades" card under the KPI strip:
the last five, with the result over "p. a." or "gesamt", and "Alle Trades →"
in its head. The board draws the card at 1440 and 390 px and in its
currency-exclusion, pending and absent states. The title follows the app's
existing German ("Abgeschlossene Trades (FIFO)" on the security's Trades tab).

**Variant B:** a navigation entry and route `/trades`, the facet removed and
redirected. It costs a route, a glyph and an ADR-0022 amendment, and the
Overview still says nothing about trades.

**Why A.** The owner lands on the Overview, and the owner's finding was reach.
A puts the answer there with existing components and no change to the
information architecture.

**Stated doubts the story settles:**

- the card covers every depot while the rest of the Overview follows the
  selected view, so its basis line says so, and UX-DR2 gains a fifth block
  (ADR-0022 §7 dropped "the raw recent-activity feed"; the card lists
  results, not activity, which the story states against that line);
- p.a. annualizes the trade-currency return shown beside it, not the
  base-currency result, and the payload's `computation_basis` says so;
- the facet's opening line and the new basis line both repeat FIFO and the
  scope; the story trims one;
- the table (996 px with p.a.) is wider than its scroller below a viewport of
  about 1270 px with the sidebar open, which with the sticky-column defect
  below cuts Result first on a small laptop.

**`DESIGN.md`, written by the story:** the card and its states, the p.a.
column and its dash, the unmatched-sells note, the trades phone row; UX-DR2's
amendment.

**Rules in the board's `#proposal`:** ① to ⑥, among them ⑥, which restores
the sign colour of Result and p.a. in `#realized-trades-table` only (see
Part 4).

## Part 2 — G2: the merge-record list (ADR-0050 §12, two-way deadline)

**Before:** a merge shows only on its survivor ("zusammengeführt aus … ·
date", G13.1-A) and links nothing. What it moved, who ran it, and any merge
whose target was later merged away or deleted exist only in the API.

**Variant A (recommended): a section at the end of Accounts & depots.** After
the accounts table and before the compatibility records, an h2 with Cash
flow's `.section-disclosure`, collapsed ("5 Einträge · zuletzt 30.09.2026").
One `.data-table` for all three kinds, newest first as the API orders it.
Each row: the date, the kind, "source → target", the result in the
confirmation's own words ("142 Buchungen verschoben, 6 entfernt"), and who
ran it ("Operator" or "Agent", G12.1-A's words). The source is muted, not
struck, because its name lives on as a former name. The target is a link; a
later merge reads "jetzt in …", a deleted target "ein inzwischen gelöschtes
Depot". The result is a disclosure that opens the count per table, the
choice made and the passed check. The date on the survivor's sub-line
becomes the way in (`?merge=<id>`, which opens the section server-side,
because a fragment does not reliably open a `<details>`). Under 560 px the
rows become two-line rows (UX-DR27). An empty list shows one `.empty-state`
sentence naming where a merge starts.

**Variant B: the same section on the Imports page.** Argued from "a merge
changes what a re-import does", but `/imports` is a three-stage flow with no
history surface, so the list would show only in the idle stage below the drop
zone. Nobody arrives there after merging.

**Variant C: a disclosure per survivor.** It fails the two-way rule: a
survivor shows only the merges into itself, so a merge whose target was later
merged or deleted hangs on no row. The board names two records the API lists
that C never shows.

**Why A.** One list, every kind, newest first — the capability the agent reads
— on the page where accounts are merged and survivors already speak, with no
new component.

**Stated deviations and doubts the story settles:**

- the phone row has no figure for its right edge (UX-DR27 expects one; a
  merge has no amount), so the date moves into the identifier line;
- the empty state has no action, because the list creates nothing (the
  precedent is Realized's "no closed sales" sentence);
- every `manifest_summary` key needs a fixed German label and a meta-test,
  because raw keys never reach the screen;
- `transactions.deleted` is one count across reasons; grouping it by reason
  is a payload change the contract entry names;
- security merges appear on a page titled for accounts and depots; the
  board's "Gegen A" accepts the cost, and the page subtitle may want a word.

**`DESIGN.md`, written by the story:** "Accounts & depots: the merge records
(G2-A)", with the placement, the row's anatomy, the disclosure's labels, the
390 px row and the empty state; and G13.1's "the line links nothing … until
its view lands" replaced by the date link.

## Part 3 — G3: releasing manual quotes (T-9, two-way deadline)

**What the write does** (`Quotes.release_manual/4`): in one transaction that
locks the security, it deletes the security's rows whose `source` is
`manual` from `from` to `to` inclusive, and journals them as one entry whose
before-image is the released rows. Provider rows in the range stay. It
fetches nothing: the next quote sync stores the provider's close for those
days, and a security whose provider has no sync adapter keeps no quote for
them.

**Before:** the Quotes tab lists the chart range's closes with the source as a
word per row ("Manuell", "Portfolio Performance"). The page says nowhere how
many manual quotes a security has or where they lie, and it cannot write a
quote.

**Variant A (recommended): a data note on the Quotes tab.** "7 manuelle Kurse
in der gespeicherten Historie, vom … bis …", counted over the whole history,
with "Freigeben…" as the note's remedy. It opens a dialog titled with the
security: the custom range's ISO date pair prefilled with the first and last
manual date; one chip per stretch of manual quotes plus "Alle"; one sentence
on what happens (removed, journaled with their closes, provider quotes stay,
the next sync fills the days, until then they have none); and a
`.button-danger` that names the count. Its states: no provider adapter (an
attention note says the days stay empty), a range with no manual quote (the
confirm disabled with its reason beside it), "Bis" before "Von" (an error at
the field, nothing written), the result as an inline note in the tab with
"Kurse aktualisieren" as the follow-up, and no manual quote at all (no note
and no control). At 390 px the dialog becomes the merge dialog's bottom
sheet.

**Variant B: an item in the securities row menu**, same dialog. Reachable from
the list, but nothing before the menu says manual quotes exist, the item would
be absent or disabled on almost every security, and the menu grows to twelve
items.

**Variant C: checkboxes on the manual rows of the quote table.** The mark sits
on the quote itself, but the release takes a range, not rows: a selection with
a gap is two writes or releases the gap too, and the table shows only the
chart's range.

**Why A.** It answers both questions — which quotes are manual, and how to
release them — where the source is already shown, in the API's own range
shape, from components the inventory lists.

**What the story must add, because no read exists:** a summary of a
security's manual quotes (count, first, last, the stretches), a count for a
given range, and a public check of whether the provider has a sync adapter.

**Stated doubts the story settles:** where the result lands (a panel-local
inline result beside its trigger, as `EXPERIENCE.md` asks, against the page's
existing page-level slot); `.merge-footer__why` reused for the disabled
confirm's reason (reuse or generalise it); the remedy link-button's tap
target under `pointer: coarse` (a pre-existing gap of every link-button
remedy, filed rather than fixed here); danger or primary for the confirm
(danger, because nothing in the UI restores a release even though the journal
keeps it).

**`DESIGN.md`, written by the story:** "Securities detail: releasing manual
quotes (G3-A)", with the note's wording and placement, the dialog's anatomy
and its states, the result, and the 390 px sheet.

## Part 4 — What the boards found outside this pass (Scope Lock)

Filed at PR γ's branch opening, not built in this sprint unless a story needs
it:

- **The sticky subject column does nothing anywhere.** The global
  `table { overflow: hidden }` makes the table itself the sticky container, so
  `.col-subject` (#730) never sticks: at 390 px, and on any table wider than
  its scroller, the last column scrolls out of view. Measured in the
  renderer (Chromium) while drawing board 01.
- **Sign colour is lost in `.data-table` cells.** `.data-table tbody td
  { color }` outranks the bare `.is-positive` / `.is-negative`, so the
  realized facet's Result prints in the text colour today. Board 01's rule ⑥
  repairs it for the trades table only; the other tables with the same
  pattern are the follow-up.
- `.summary-basis` has no context-free rule; outside four scoped selectors it
  renders as body text, the facet's own opening line and the Risk basis line
  among them.

- `.disclosure-summary` is defined twice in `app.css` with different sizes,
  so a section summary renders at 13.6 px/600 instead of the spec's control
  label.
- The "Portfolio records (compatibility)" disclosure on Accounts & depots uses
  a bare `<summary>` with the browser's triangle (UX-DR19 drift).
- At 390 px the quote table's "Quelle" column, the only per-row source
  marker, sits off-screen inside the table's own scroller.
- "Kurse aktualisiert." does not say how many manual rows the sync skipped.
- Every `.link-button` remedy inside a data note is below the 44 px coarse
  pointer floor (UX-DR6).
- `EXPERIENCE.md` says "ISO in display" for dates, while the built UI and the
  last three passes' boards use `Format.date` (DD.MM.YYYY in German). One of
  the two should change.
