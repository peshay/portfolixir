# UX Design Pass — 2026-10-02, Sprint 18's user-visible items

Scope: **every** user-visible change Sprint 18 proposes, held against the
living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html).
`DESIGN.md` and `EXPERIENCE.md` are the authority, and this document proposes
against them. It runs **on the planning PR, before the batch**, as the standing
rule of 2026-09-20 requires (AGENTS.md → "A UI change is mocked before it is
built").

Mockups: `design-language/mockups/ux-design-2026-10-02/`, one HTML board per
item group with every variant or its before and after, rendered to PNG with
Playwright (`render.mjs` in the same folder, unchanged from the 2026-10-01
pass) and reduced to a 256-colour palette. The boards link the real
`priv/static/app.css` and use the live pages' markup and German labels. Each
board was drawn by one author against `DESIGN.md`, `EXPERIENCE.md` and the
review rubric, and checked by eye at every rendered width. The data is
invented: names in the demo seed's style, obviously fake identifiers such as
`XS0000000001`, generic account names ("Girokonto", "Tagesgeld", "Depot 1"),
and made-up figures and 2026 dates. **No real instrument, position, balance,
account, provider or rate appears.**

A pick's code is its board's number. **The recommendation is the default; a
comment naming another variant changes it; silence adopts it.** For a
before/after board there is nothing to pick: the spec already fixes the
answer, and the board shows the reader what the words describe. The story
that builds a pick writes its anatomy into `DESIGN.md`.

| Pick | Item | Board | Kind | Recommended |
|---|---|---|---|---|
| **H1** | The security's Trades tab: the p. a. column (#1029, two-way deadline; plan F6) | `01-trades-tab-pa` | before/after | after |
| **H2** | Deleting a booking from the screen (#912; plan U1), and **H2b**, "Bearbeiten" on the kinds the drawer cannot book | `02-booking-delete` | variants: action in the row menu · only in the edit drawer · only "Split löschen"; H2b: notes-only drawer · no "Bearbeiten" | **A**; H2b **A** |
| **H3** | Bond master data, display-only metrics and the two-scales guard (#330; plan U7) | `03-bond-master-data` | variants: a second figure grid on the Overview · a conditional "Anleihe" tab | **A** |
| **H4** | Tables: #1009, #1010, #913, #911, #1011 (plan U2) | `04-tables-conformance` | before/after; one pick for #911: hint into the Drift cell · pin both columns | after; **A** for #911 |
| **H5** | Light-mode contrast (#908; plan U3) | `05-light-contrast` | before/after (one token) | after |
| **H6** | Touch and focus: #1013, #1033 (plan U4) | `06-touch-focus` | before/after; one pick for #1013: tap area by padding · own line on touch | after; **A** for #1013 |
| **H7** | The phone at 390 px: #1012, #1033, #909, the history's phone rows (plan U5) | `07-phone-390` | before/after; picks for #1012 (two-line rows · pinned column) and #909 (soft hyphen · `hyphens: auto`) | after; **A** for each |
| **H8** | Dialogs and messages: #910, #918, #921, #969, #966, #920, #1032's UI half, #968 (plan U6) | `08-dialogs-copy` | before/after; picks for #918, #969, #966 and #920 | after; **A** for each |

**FR-41's screen is not redrawn.** ADR-0051's own board
(`mockups/fr41-2026-09-25/01-contribution-surface.html`, pick A, a
contribution table under the Wealth performance chart) was adopted with the
record at Sprint 17's planning. The design critic in β's closing act holds
the built table against it.

**Items with no board.** Everything in the plan's PR α changes no rendered
output: the import fix (unless C1 finds that an affected instance needs a
notice, which is then boarded mid-batch), the solver, the migrations, the
companion's write outcome, the release's fetch switch, the hygiene and the
maintenance lane. PR δ is the documentation site and the README, not the
app. In β, F2, F4, F5 and F7 change the payload or the performance only.
#1014 amends `EXPERIENCE.md` to the date format the screens already show, so
the picture is identical.

---

## Part 1 — H1: the security's Trades tab gets its p. a. column (#1029)

**Board:** `design-language/mockups/ux-design-2026-10-02/01-trades-tab-pa.html`,
rendered as `01-trades-tab-pa--1200.png` and `01-trades-tab-pa--390.png`.
Before/after, with no choice between variants. The data is synthetic:
"Nordwind Industrie AG" (`DE000000000A`) with one open lot, four closed trades
held 863, 526, 408 and 128 days, and two sells of delivered-in shares. Two
further states use "Birkenhain Wasser AG" and "Halvorsen Shipping AS".

**Before:** `trades_tab_panel/1` (`securities_live.ex:2016–2157`) shows two
FIFO tables. "Abgeschlossene Trades (FIFO)" (heading at :2109) has the columns
Eröffnet · Geschlossen · Stückzahl · Ø Kauf · Ø Verkauf · Tage ·
Realisierter G/V · %. It has no p. a. column. The data is already there:
`Ledger.list_trades_for_security/2` (`ledger.ex:195–222`, the merge at :220)
attaches `annualized_return` and `annualized_return_reason` to every closed
trade, and the template never reads them. Every row of the Trades facet and of
the Overview card links to this tab. Sign colour is lost in both tables:
`.data-table tbody td { color }` outranks the bare `is-positive` /
`is-negative` (#1010). Under the tables, `p.detail-tab-warning` (:2146–2152)
says "Einige Verkäufe konnten keinem vorangegangenen Kauf zugeordnet werden —
möglicherweise fehlen Daten." It gives no count, no date and no quantity, and
it does not mention the usual, legitimate cause: an inbound delivery opens no
lot. When a security's only sells are of delivered-in shares, the tab also
shows the empty sentence "Noch keine zugeordneten Trades — erfasse zuerst
Käufe und Verkäufe." (:2026–2030), which is wrong because there is no buy to
record. At 390 px the table scrolls sideways, and Result and % are off-screen.
The code-only inaccuracy is the comment in `RealizedGains.closed_trades/2`
(`realized_gains.ex:198–200`): "…that security's Trades tab, where the same
round-trip is shown with its lots". The tab shows one row per closed trade
with average prices, not the consumed lots.

**Decided by the spec / the plan:** `DESIGN.md` → "Amendment 2026-10-01 —
Trades" covers the p. a. column: placed directly left of Result, with the
figure from 365 days of holding, judged on the row's own holding period. Below
that threshold the cell is a muted "—" (`.trade-pa--na`, `aria-hidden`,
`cursor: help`) whose reason goes in the `title` and in a `.visually-hidden`
sentence. There are two reasons with their existing German strings, and there
is no ⓘ in the header. The same amendment covers the unmatched-sells note (an
`attention` data note with the count, the delivery cause and a closed
disclosure listing each sell, and no remedy), the list's basis line, and the
trades phone row under 560 px (UX-DR27). Issue #1029 sets the two-way deadline
at the end of Sprint 18.

**After:**

- **p. a. column** between "Tage" and "Realisierter G/V". The threshold and
  the figure it is judged by sit side by side. The figure is
  `annualized_return` in the trade's currency, as is the % it annualizes.
  Values: "+10,7%", "-3,6%", "+16,5%", and a dash for the 128-day trade, with
  the title drawn. State N2 draws the second reason: a trade held 1736 days
  that was a total loss, where no rate solves the flows.
- **Rule ① (proposal)** applies to `#detail-closed-trades-table` only. It sets
  `td.is-positive` / `td.is-negative` to the sign colours and
  `td.trade-pa--na` to muted. This follows the facet's rule ⑥. It also
  restores the colour of Realised P&L and % in this table.
- **The unmatched-sells note** is the facet's `AppShell.data_note` (attention)
  and leads the closed-trades section under its heading (UX-DR25), with the
  facet's wording adapted to the tab: "2 Verkäufe haben für ihre ganze
  Stückzahl oder einen Teil davon keinen zugeordneten Kauf (z. B. aus
  Einlieferungen): Diese Stückzahl ist in keinem abgeschlossenen Trade
  enthalten." Its disclosure "Die 2 Verkäufe" lists date · quantity from the
  `orphan_sells` the tab already loads. The list has two columns because the
  security is the page's own (rule ②, which also keeps two columns under
  560 px, where the facet's rule would put the date on a line of its own).
  `.detail-tab-warning` loses its last user, and the story removes the rule.
- **The basis line** sits under the list in the pane's existing
  `.detail-tab-hint`, so no new type rule is needed (rule ③ only adds its top
  margin): "Über alle Depots · Einlieferungen eröffnen keinen Lot · Gebühren
  und Steuern im G/V, nicht in Ø Kauf und Ø Verkauf · Erträge während der
  Haltedauer nicht enthalten · p. a. erst ab 365 Tagen Haltedauer". It renders
  whenever the table or the note does.
- **N1: only delivered-in shares were sold.** The section shows its heading,
  the note and the basis line, with no table. When a sell without a buy
  exists, the empty sentence is dropped.
- **At 390 px** (rule ④): `ul#detail-closed-trades-phone-rows` uses the
  facet's trades phone row without the name. The name line is "2023-02-06 →
  2025-06-18", over "30,0000 Stück · 863 Tage". On the right is "+502,20 EUR"
  over "+27,1% · +10,7% p. a.". Rows under 365 days, or with no rate, show only
  the period return. Ø Kauf and Ø Verkauf are dropped on the phone, as cost
  and proceeds are in the facet. The board measured no horizontal overflow at
  390 px.
- **Code only:** the `RealizedGains` comment becomes "…where the same
  round-trip is a row of its closed trades." Nothing on screen changes.

**Stated doubts the story settles:**

- **Sign.** The facet's p. a. cells are unsigned ("10,0%"). This board signs
  them ("+10,7%") because every figure in this table is signed
  (`signed_decimal_or_dash`) and the Overview card already signs p. a. The
  story picks one and writes it into `DESIGN.md`.
- **Decimals.** p. a. follows `DESIGN.md` (one decimal, % glued). The tab's
  own "%" column keeps two decimals with no % sign ("+27,07"), and the phone
  row uses the facet's one decimal ("+27,1%"). The same number therefore
  appears with two precisions on one tab at two widths. Aligning the "%"
  column is outside this item.
- **Order with H4.** Board 04 of this pass (pick H4) repairs #1010 with a
  general `.data-table td.is-positive / .is-negative`. If H4 lands first, the
  two sign lines of rule ① are redundant and the story drops them. The muted
  dash line stays, or becomes `.data-table td.trade-pa--na` and retires the
  facet's own rule. If H1 lands first, the open-lots table above stays
  text-coloured until H4.
- **Note placement.** The note leads the closed-trades section. It does not
  lead the whole tab, although the open lots come from the same matcher and
  also leave out delivered-in shares. The basis line ("Einlieferungen eröffnen
  keinen Lot") covers both tables.
- **Basis-line wording.** One link differs from the facet's line ("im G/V,
  nicht in Ø Kauf und Ø Verkauf" instead of "in Einstand und Erlös"), because
  this table shows gross average prices, not cost and proceeds. That means a
  new gettext string, not reuse of the facet's.
- **Dates.** This tab prints ISO dates (`Date.to_iso8601`) and the facet uses
  `Format.date`. The board keeps ISO throughout the tab, including the note's
  list and the phone rows. This is the EXPERIENCE.md vs built-UI split that
  Sprint 17's Part 4 named.
- **Phone-row ids.** The detail pane at 390 px is the whole page (UX-DR12), so
  the phone rows sit in the pane. The table wrapper needs an id
  (`detail-closed-trades-table-wrap`) so the 560 px block can hide it.

**Outside this pass (Scope Lock):**

- The open-lots table ("Offene Positionen (FIFO)", nine columns) stays a
  UX-DR15 scroller at 390 px, where Unrealised P&L and the decomposition are
  off-screen. UX-DR27 arguably covers a list of lots too. This needs a
  follow-up issue.
- A security held only through an inbound delivery, with no sell, still reads
  "erfasse zuerst Käufe und Verkäufe" on this tab. There is no buy to record,
  and its shares appear in no lot. The empty sentence needs the delivery case
  (follow-up issue).
- The tab's "%" columns (open and closed) use two decimals with no % sign.
  Everywhere else the app uses `Format.percent` (follow-up issue, possibly
  with H4's table family).

## Part 2 — H2: deleting a booking from the screen (#912)

**Board:** `design-language/mockups/ux-design-2026-10-02/02-booking-delete.html`,
rendered as `02-booking-delete--1200.png` (Today, A, B, C, verdict) and
`02-booking-delete--390.png` (variant A only). The data is synthetic: a buy of
40 "Global Aktien ETF" in "Depot 1" paid from "Girokonto", an imported
dividend of "Nordwind Industrie AG", a 2:1 split of "Kestrel Robotik SE"
booked in two portfolios ("Hauptportfolio", "Sparplan-Portfolio"), and a
deposit.

**Before:** the history's row menu has one item, "Bearbeiten"
(`transaction_management_live.ex:465–482`). No screen deletes any of the 15
booking kinds. `Ledger.delete_transaction/2` (`ledger.ex:1298–1313`) is
reachable only through `DELETE /api/v1/transactions/:id`
(`transaction_controller.ex:172–183`) and `portfolixir.transactions.delete`
(`mcp-server/src/tools.ts:3343`). The split drawer's help line (G12.3-A, :1651)
says a wrong split "wird über API oder MCP gelöscht", with no link. "Split
erfassen" refuses a different ratio on the same day ("…das bestehende Ereignis
zuvor löschen, falls es falsch ist", `split_wizard_dialog.ex:350`) and also
gives no way to do that. The history shows a split as one row per portfolio,
so the board's split appears twice.

What delete does today, read from the code:
- It deletes one row in one transaction and writes one journal entry
  (`delete`, `transaction`) holding the row re-read under the delete's lock as
  the before-image. Only the API and MCP read the journal
  (`GET /api/v1/journal`), and nothing restores a booking from it.
- Everything derived follows at read time: holdings, cash balances,
  performance, trades and realized gains, snapshot comparisons (a snapshot is
  a marker, not a copy). A cash transfer or security transfer is one row, so
  both legs go.
- The import hash goes with the row. A deleted imported booking's
  `import_hash` is not retired (only a merge retires one, ADR-0050 §3), so
  re-importing the same file books it again.
- For a split, only that row is deleted. A split booked in two portfolios
  keeps its other row, and with it the security-level event:
  `Quotes.split_events/1` folds the rows into one event, so the chart keeps
  adjusting. "Split erfassen" keeps refusing the corrected ratio. No group
  delete exists. `Splits` names the group key (security, date, reduced ratio)
  and says "deleting the group means deleting those rows"
  (`splits.ex:14–18`).

What the API and MCP refuse:
- **404** when the booking is unknown or already gone, including when it
  vanished before the delete took its lock (`Journal` lock step). The page
  already has the sentence "Diese Transaktion existiert nicht mehr."
- **409** only on a changeset error, which a delete cannot produce today.
- **No dependency check.** A buy whose shares a later sell consumed can be
  deleted. The sell is then unmatched, and the position can go below zero. No
  foreign key points at a booking (`retired_import_hashes.former_transaction_id`
  is a plain integer). The dialog therefore states no refusal beyond the 404
  and warns about nothing the API does not check.

**Decided by the spec / the plan:** issue #912 calls this the missing human
view of an existing capability, owed under the two-way rule, and asks for the
link from "Split erfassen" and from G12.3's help line. EXPERIENCE.md: a
destructive action confirms once, never twice; modals are native dialogs, and
no dialog opens from a dialog (UX-DR9). `DESIGN.md` (Accounts & depots
lifecycle): menus are ordered by consequence, with Delete last in
`.row-context-menu__item--danger`, and the row menu names its row on the
phone sheet. The app's existing deletes (security, account, depot, snapshot,
view, rule, category) all use one native `data-confirm` (#765), and each asks
only when nothing depends on the record. The one consequential removal
designed since then, G3-A's manual-quote release, uses a narrow modal with a
`.button-danger` that names the act.

**Variant A (recommended): "Löschen…" in every row's menu.**
- **The menu** shows Bearbeiten · **Löschen…**, last, danger colour, trash
  glyph, on every row of every kind, including kinds that "Bearbeiten" cannot
  open properly yet. The ellipsis says a dialog follows, as with
  "Zusammenführen in…". Under 720 px the menu is the existing sheet, and the
  page now passes `caption_name` (the `row_name/2` it already builds for the
  kebab's label): "Kauf, Global Aktien ETF, 22.09.2026 · Transaktion".
- **The dialog** (`.booking-delete-dialog`, which joins the
  `.quote-release-dialog` rules: 460 px wide, a bottom sheet under 720 px) is
  titled "Transaktion löschen". It names the booking in the history's own
  phone-row shape inside a bordered box (proposal ②): "22.09.2026 · Kauf" over
  "Global Aktien ETF · Depot 1", and on the right "-2.504,90 EUR" over
  "40 × 62,50". One sentence says what changes, concretely: "Danach hält
  Depot 1 40 Stück Global Aktien ETF weniger, und Girokonto hat 2.504,90 EUR
  mehr." It is built from `Projection.effects/1`, so no per-kind copy is
  needed except for split and balance snapshot. This is followed by the
  general recompute sentence and the journal sentence ("…zurückholen kann die
  Oberfläche sie nicht"). The band foot has Abbrechen and a `.button-danger`
  "Transaktion löschen", with no `data-confirm` after it.
- **States:**
  - A3, imported (`import_hash` set): an attention note says a re-import of
    the same file books the booking again.
  - A4, split: titled "Split löschen". It names the ratio and "2 Zeilen" and
    says both portfolios' rows go in one step, holdings count without the
    split from its date, and the chart's series drops the adjustment while
    stored quotes stay. The button reads "Split löschen (2 Zeilen)", or
    "Split löschen" for one row.
  - A5, after: the page's existing `.alert-success` slot, like "Transaktion
    erfasst", reads "Transaktion gelöscht: Kauf · Global Aktien ETF ·
    22.09.2026." The row is gone and the month subtotal follows.
  - A6, gone meanwhile: `.alert-error` "Diese Transaktion existiert nicht
    mehr."
- **The two links:**
  - A7: G12.3's help line becomes "…Ein falscher Split wird gelöscht und
    danach am Wertpapier mit „Split erfassen“ neu erfasst. [Split löschen…]".
    The link-button closes the drawer and opens A4.
  - A8: "Split erfassen"'s conflict warning, and the matching booking
    refusal, carry "Gebuchten Split löschen…". It closes the wizard and opens
    the same dialog on the securities page, so the delete and the rebooking
    happen in one place.

**Variant B: delete only inside the edit drawer**, as a danger zone in its
foot ("Löschen…" set apart at the right). The drawer is itself a modal sheet
under 720 px, so the confirmation cannot be a second dialog. It becomes an
inline strip replacing the foot: "Diese Transaktion löschen? …", with
"Transaktion löschen" and "Zurück". Point in its favour: the whole booking is
visible field by field before deleting. Points against: delete hides behind
"Bearbeiten". The drawer knows only buy, sell and (since G12.3) split.
"Bearbeiten" on any of the other twelve kinds opens the buy form with "Kauf"
preselected (frame B3; the type select offers only buy and sell,
`transaction_management_live.ex:1757`). B therefore either deletes from a form
that misstates the booking or first has to teach the drawer every kind. It
also adds a second form of destructive confirmation to the app.

**Variant C: only "Split löschen"**, in the split drawer's foot and from
"Split erfassen", using A4's dialog. It is the smallest change that matches
#912's title, and a booking that moves money stays undeletable on screen.
Against it: the gap #912's first sentence names stays open for 14 of 15 kinds,
so a double-imported or mistyped buy still needs the agent. The dialog C
builds is A's dialog; A only places it on every row.

**Why A.** It gives the screen what the API and MCP can do, for every kind,
where every other row action in the app already sits. Its confirmation uses
the narrow destructive form the app already has for writes with consequences.
`data-confirm` stays with the consequence-free deletes, which ask only when
nothing depends on the record, while deleting a booking always has
consequences. Splits are deleted the way the operator booked them, as one
fact, and both places where a wrong split shows up lead to that dialog.

**Stated doubts the story settles:**

- **Group delete for splits needs a write that does not exist.** It needs a
  function that deletes a split's rows (same security, date and reduced
  ratio) in one transaction, with each row journaled. It also needs its API
  and MCP counterpart under the two-way rule. Today the agent deletes row by
  row, and between calls the ledger is in the half state described above. The
  alternative is per-row delete with a dialog naming the remaining rows. The
  board argues against it.
- **Modal instead of `data-confirm`.** `layout_view.ex:49` says "Every
  destructive control carries data-confirm (#765)". The story states that the
  modal replaces it for this control: one confirmation, not two.
- **The "Danach …" sentence** comes from `Projection.effects/1`. A later
  "Saldo gesetzt" on the same account anchors the balance from its date
  onward, so "Girokonto hat 2.504,90 EUR mehr" holds only until that anchor.
  The story either adds that clause when an anchor exists or keeps the
  sentence about the booking's own effect.
- **No dependency warning.** The dialog does not warn that a later sell
  loses its matched buy or that a position goes negative, because the API
  checks neither. A dry-run read serving both sides would be its own story.
- **The import hash.** The dialog states today's behaviour (a re-import
  rebooks). Whether a delete should retire the hash, as a merge does, is a
  ledger decision (ADR-0050 territory) and is not part of this item.
- **Copy in A8.** The warning names the booked ratio ("(2:1)"), but the
  preview warning is an atom today. The story either passes the ratio along
  or keeps the existing sentence and only adds the link.
- **Focus.** The board proposes opening the dialog with focus on "Abbrechen".
  After the delete the row and its kebab are gone, so focus goes to the
  result or the history heading, never to `<body>` (WCAG 2.4.3, as G3's
  `data-focus-fallback`).
- **Shared component.** A8 needs the dialog on the securities page as well as
  on the history, as one component with one handler per page. A cheaper
  fallback is a link to `/transactions?delete=<id>`, which opens the dialog
  server-side. Nothing writes before the confirm.

**H2b — what "Bearbeiten" does on the twelve kinds the drawer cannot book
(added on the coordinator's request; last section of board 02).**

- **Before (verified by a throwaway LiveView test on the branch):**
  "Bearbeiten" on a deposit opens the buy/sell drawer. Its type select offers
  only buy and sell with none selected, so "Kauf" shows. Saving is refused
  ("Wertpapier/Depot/Stückzahl/Preis darf nicht leer sein") and the deposit
  is unchanged. The data is not damaged, but for every kind except buy, sell
  and split the form can only refuse. The drawer also creates only buy and
  sell (AGENTS.md goal 4). The other kinds arrive by import or API, and
  "Saldo gesetzt" also comes from Accounts & depots. So on screen, "delete
  and rebook" exists only for trades and set balances.
- **What the API and MCP allow:** `PATCH /api/v1/transactions/:id` and
  `portfolixir.transactions.update` (`Ledger.update_transaction/3`) set every
  public field of a non-split booking, including its kind: date, accounts,
  security, quantity, price, amount, fees, taxes, settlement and notes. They
  refuse three things: a change to a split (422 at the endpoint), an imported
  row becoming a split or a balance anchor, and per-kind or settlement
  violations (#395). Every change is journaled. So the agent can correct a
  dividend in place, and the screen cannot under either variant.
- **Variant A (recommended):** a notes-only drawer, generalising G12.3-A's
  `editing_split` state to every kind the drawer does not book. The sub-line
  reads "Eine Dividende bucht die Oberfläche nicht; hier ändert sich nur die
  Notiz…". The booking's facts are shown in disabled fields; which fields
  depends on the kind's required fields (a dividend shows Typ, Datum,
  Wertpapier, Verrechnungskonto, Betrag, Steuern; a transfer shows both
  accounts). A help line states the limit and both correction paths: "…Korrigiert
  wird die Buchung über API oder MCP, oder sie wird gelöscht und neu
  importiert. [Löschen…]". For "Saldo gesetzt" the help line instead says
  "…oder er wird gelöscht und unter Konten & Depots neu gesetzt". The drawer
  keeps the Notes field, "Notiz speichern" and "Abbrechen". The delete link
  closes the drawer and opens H2-A's dialog.
- **Variant B:** these kinds get no "Bearbeiten", so their menu holds only
  "Löschen…".
- **Why A.** Every row keeps the same two-item menu. B makes the menu change
  from row to row and leaves a single destructive item behind the kebab for
  twelve kinds. A keeps the note editable, as it is on the API and MCP. It
  shows the stored fields that the history only partly has as columns. The
  pattern is already built and accepted (G12.3-A). A promises less than the
  agent can do, never more, and says so where the correction is attempted
  (UX-DR26). Its cost is a third drawer state and a per-kind field list.

**Outside this pass (Scope Lock):**

- **Correcting the twelve non-trade kinds on screen.** The API and MCP
  correct every field in place (PATCH). The screen, even with H2b-A, changes
  only the note, and it rebooks only buy and sell (and set balances on
  Accounts & depots). That is a two-way gap of its own, outside #912, and it
  needs an issue. H2b-A's help line is the stated limit until then.
- **The history's phone row puts its kebab on a line of its own** under the
  date, at the left. `#transaction-phone-rows .phone-row` (`app.css:7757`)
  has two grid tracks for three children since #809 added the kebab, and its
  comment still says the row "has no kebab". The board's 390 px render shows
  it as it is. This needs an issue (possibly for H7's phone pass).
- The transactions row menu passes no `caption_name`, so under 720 px its
  sheet does not say which booking it acts on. A fixes this for its own
  purpose, and it is noted here because it predates H2.

---

## Part 3 — H3: bond master data and display-only key metrics (#330, rescoped 2026-10-01)

**Board:** `design-language/mockups/ux-design-2026-10-02/03-bond-master-data.html`,
rendered as `03-bond-master-data--1200.png` and `03-bond-master-data--390.png`.
One synthetic bond is used throughout: "Musterland Anleihe 2031", `XS0000000001`,
2.50 % annual coupon, issued 2021-06-15, maturing 2031-06-15, denomination
1,000 EUR, 100 units held in "Depot 1", bought at 98.50, last quote 97.25. The
guard frames show the same purchase booked the other way: 10,000 units at 0.985.

**Before:** a bond is a security like any other. `Security` has no field for
coupon, maturity, denomination or payment frequency
(`lib/portfolixir/catalog/security.ex:16-38`, and the characterization test
asserts that no such field exists). The edit dialog
(`SecurityFormDialog.render_confirm/1`, `security_form_dialog.ex:304`) offers
name, ticker, ISIN, WKN, currency, exchange, asset class, quote feed, feed URL,
the raw-quotes toggle and the note. Nothing in it is bond-specific. The
Overview (`securities_live.ex:1564`) shows the same six figures for every
security. For a bond that means "100 Stück" with nothing saying this is a
nominal of 10,000 EUR, and "97,25 EUR" with nothing saying this is also
97.25 % of face. If an export booked the nominal as the quantity, the value
is a hundred times too high from the first quote on. The TTWROR does not show
it (bond discovery, point 5), and no surface warns.

**Decided by the spec / the plan:**

- D-13 (Sprint 17 plan) and the rescoped issue: the valuation half is void
  because quantity × percent quote is already correct under the hundredth
  convention. What remains: master data (coupon p.a. as a Decimal %,
  maturity, denomination plus currency, annual/semi-annual payment, optional
  issue date), display-only metrics (remaining term, current yield = coupon ÷
  price, optionally a linear-approximation yield to maturity), no accrued
  interest and no tax, the form only for `bond` / `government_bond`, and a
  guard that names a bond priced on two scales.
- Every metric states its computation basis in the API and MCP payload
  (AGENTS.md). On screen this is a basis line, in the anatomy of the
  ADR-0047 metric grid: per-cell variable parts in the sub-line, the shared
  basis once underneath (`securities_live.ex:3196`, `data-role="metrics-basis"`).
- Master data is edited in the one security dialog. The Overview renders no
  input until an edit control is used (C7-A, #804).
- A data note sits inside the section whose data it describes, and its
  remedy is a child of the note (UX-DR17). An excluded or wrong row is named
  where the total is read, with its count and its names (UX-DR25).
- Decimal fields follow the numeric-input rule (`DecimalInput`, `class="num"`,
  locale separator, never grouped, strict reading). Dates are ISO text inputs
  (UX-DR19).
- The `.overview-metrics` grid has two cells per row under 720 px (DESIGN.md
  `security-metric-grid.cells`).

**Variant A (recommended): the bond data in the Overview.** For asset class
`bond` / `government_bond` only, the Overview's main column gets one more
block directly under the six figures. It has a heading "Anleihe", then the
same `.overview-metrics` grid three by two, then a basis line. The first row
holds what was entered: maturity (with the issue date as its sub-line),
coupon (with "jährlich, am 15.06."), and "Nominal im Bestand" (10,000.00 EUR,
sub-line "100 Stück × 100 EUR · Stückelung 1.000 EUR"). The second row holds
what follows, each figure under its input: remaining term under maturity
("4 J. 8 M.", "4,70 Jahre ab 2026-10-02"), current yield under coupon (2.57 %,
"2,50 ÷ 97,25 (2026-09-30)"), and the optional yield to maturity
("≈ 3,17 %", "linear angenähert"). The basis line says that coupon and price
are percent of face and that one unit is a hundredth of the nominal, which is
why the price is also the price per unit. It then gives both formulas, the
day count (calendar days from today, a 365-day year), and states that accrued
interest, fees and taxes are excluded and that the figures are reported, not
evaluated. States drawn: no master data (one sentence plus "Anleihedaten
erfassen…" opening the dialog, with the nominal still shown together with the
convention), matured ("fällig seit …", both yields "nicht berechenbar"), and
trade-priced (the yields use the last own purchase price and the sub-line
says so). Dates are ISO, as everywhere else in the detail pane.

**Variant B: a tab "Anleihe".** The tab is second in the row, present only for
the two bond classes. It holds the master data as a read-only list in a card
with "Bearbeiten" (which opens the same dialog), plus four metrics, the latest
price as a percentage and the value in the same grid, with the same basis
line. The Overview stays identical for every security.

**Why A.** The metrics are computed from the price and the holding that the
Overview already shows. DESIGN.md placed the ADR-0047 grid under its chart
"never on a tab of its own" for exactly this reason. The guard has to sit on
the Overview anyway, because the wrong figure is the value shown there; B
would carry the guard on two tabs and repeat price and value. B also makes
the tab row depend on the asset class: nine tabs or ten, a fallback for
`?tab=bond` on a non-bond, and one more tab behind the edge at 390 px. "Dates"
was the one tab the budget allowed (#828), and it applies to every security.
B's real advantage is room for a coupon schedule or attributed coupons
(#928), and neither is in #330.

**Shared by both variants:**

- **The form section (F1, F2).** A `fieldset` "Anleihedaten" in the security
  dialog, shown while the asset class select reads Anleihe or Staatsanleihe.
  The dialog already re-renders on every change (`form_change`,
  `security_form_dialog.ex:651`), so the section appears and disappears as
  the select changes, when creating and when editing alike. The fields are
  coupon p.a. (%) as a decimal text field typed as a percentage (2,5, not
  0,025), payment as a select (jährlich / halbjährlich), maturity and issue
  date (optional) as ISO text fields, and denomination (decimal) with its
  currency (defaulting to the security's). A `.form-help` line states the
  convention ("Im Bestand ist ein Stück ein Hundertstel des Nominals…").
  The line is needed because "Stückelung" and the holding's "Stück" are
  different units. The anatomy is the booking drawer's `.settlement-fieldset`
  (a block shown only when it applies). Errors land on their field (F2).
- **The guard (W1, W2).** A **problem** data note (UX-DR17: when it fires,
  every money figure of the bond is wrong, not incomplete). It sits at the top
  of the Overview panel above the figures it concerns: "Auf zwei Skalen
  bepreist: Kurse um 100 (zuletzt 97,25 am …), gebuchter Preis je Stück um 1
  (1 Kauf: 0,985 am …). Dann ist das Nominal als Stückzahl gebucht, und Wert,
  Gewinn und Gewicht sind hundertfach zu hoch; die Rendite (TTWROR) zeigt es
  nicht." Its remedy links to the security's Transactions tab. The same
  finding is the seventh condition in Wealth → Holdings → Datenqualität, the
  place where totals are read. It mirrors the negative-holdings problem note
  there, which also links to `/securities/:id?tab=transactions`
  (`portfolio_live.ex:2592`). The guard converts nothing and offers no
  rescale, because that would be the struck quotation type. The figures stay
  visible (W1 shows 972,500.00 value and 1,000,000.00 nominal). It is silent
  while the bond has no quote (the value is then right), when the two scales
  agree, and for every other asset class.

**The ADR paragraph (columns vs the `attributes` map), as far as the
screen goes:** dedicated nullable columns (or an embedded schema with its
own changeset) give the screen two things for free. Errors land on the
field, because the dialog maps changeset errors by field name, so an `attributes`
map would need per-key validation re-implemented and mapped back to inputs.
And the securities list can filter and sort by maturity or coupon:
`SecurityFields` shows JSONB keys in the column picker, but filtering on
attributes is off in v1 (`security_fields.ex:167`) and `gt`/`lt` are blocked
for them (`jsonb_range_block?/2`, `:303`). The map also accepts any key from
any writer (`protect_attributes/1`), so the Overview would have to render
values it did not validate. The drawn surfaces look the same either way. The
decision belongs to the story's ADR paragraph.

**Rules in the board's `#proposal`:** ① `.bond-strip` (the heading in the
overview-card head voice; grid and basis line are existing classes);
② `.bond-fieldset` joins the `.settlement-fieldset` selector lists; ③ dates
and figure-with-unit stay whole inside a cell's sub-line; ④ **a conformance
repair**: under 720 px `.overview-reading .overview-metrics` goes to two
columns. Today the three-column rule (`app.css:8331`) outranks the spec'd
two-column rule (`app.css:2810`) by specificity. So at 390 px the existing
six figures stand in three columns of about 105 px: "TAGESÄNDERUNG" runs
into "1Y" and "Durchschnittseinstand" overflows the cell. The board draws
this before (phone-only frame) and after. The bond strip is the same grid in
the same column and would inherit the defect. Whichever of this story and
the Sprint 18 UI polish lane lands first carries ④.

**Stated doubts the story settles:**

- Which linear approximation: the board uses
  (C + (100 − P) ÷ n) ÷ P (3.17 % here). The other common form divides by
  (100 + P) ÷ 2 (3.13 %). Name one in the basis line and the payload, or drop
  the optional metric (the grid then has five cells).
- Which price the yields use when the bond is trade-priced (A4 uses the last
  own purchase and says so), and what "near 100" and "near 1" mean for the
  guard (a ratio band around 100 between the latest quote and the booked
  average price is the obvious reading). Whether the reverse case (quotes
  near 1, bookings near 100) is named too.
- Whether the guard is keyed on the two bond classes only (as the issue
  says), so a bond with no asset class escapes it.
- Whether the dashboard's one-line data-quality summary counts the finding
  as well.
- Whether "Bestand 100 Stück" on a bond's Overview should itself say nominal,
  and whether "Letzter Kurs 97,25 EUR" should read as a percentage. The board
  leaves both cells unchanged and puts the convention in the strip and its
  basis line.
- What the form requires once the section shows (coupon and maturity
  together, or nothing), whether maturity after issue date is checked, and
  what happens to stored bond fields when the asset class changes away from
  a bond. Hidden values are kept or cleared, and the screen hides them either
  way.
- Whether the denomination currency may differ from the security's currency.
  The board defaults it to the security's currency and lets it be changed,
  as the issue lists "face value + currency".
- Zero coupon: current yield 0.00 %, payment "keine". Not drawn.

**`DESIGN.md`, written by the story:** "Securities detail: bond master data
and key metrics (H3-A)": the strip's placement, cells, sub-lines, basis line
and states; the dialog's bond section; the two-scales note on the Overview
and in Wealth data quality; rule ④ (unless the polish lane landed it first).

**Outside this pass (Scope Lock):**

- The Overview's six figures stand in three columns at phone width (rule ④
  above). This defect exists today, independent of #330. If the story does
  not carry ④, it is filed for the polish lane.
- The security Transactions tab prints the booked price at two places
  (`Format.decimal(tx.price, 2)`), so the guard's remedy shows a booked
  0.985 as "0,99". This is readable but loses the digit the guard quotes.
- Coupons booked as INTEREST are not attributed to the bond (#928, already
  filed). No per-bond income figure is possible until that is resolved.

---

## Part 4 — H4: tables, five conformance repairs (#1009, #1010, #913, #911, #1011)

**Board:** `design-language/mockups/ux-design-2026-10-02/04-tables-conformance.html`,
rendered as `04-tables-conformance--1200.png` and `04-tables-conformance--390.png`.
Each item is a before/after pair except one: how the positions worklist pins a
subject that spans two columns (#911 a) is a real choice, so that item has
variants. The "Heute" frames render with `app.css` as built. The "Nachher"
frames also get the rules in `<style id="proposal">`. On the board those rules
sit inside `@scope (.after)`, which adds no specificity; the stories write them
without that wrapper. At 1200 px each frame is 980 px wide, the content width
of a 1200 px window with the 220 px sidebar open. A small script on the board
measures the pinned column against its scroller and prints the result under
each frame, so the before/after claims are measured, not described. All data
is synthetic.

**Before:**

1. **#1009, the sticky subject column sticks nowhere.** Two rules make every
   table its own scroll container: `table { overflow: hidden }`
   (`app.css:1196`) and, under 560 px, `table { display: block; overflow-x:
   auto }` (`app.css:1569`). `.col-subject { position: sticky; right: 0 }`
   (`app.css:5117`) therefore sticks inside the table. The table is exactly as
   wide as its content (`.data-table-wrapper > table { min-width: max-content
   }`, `app.css:2009`), so the column never moves. Measured on Cash flow →
   Realized → "Matrix nach Jahr und Monat": the Total column ends 87 px outside
   its 930 px scroller at 1200 px and 677 px outside at 390 px. Every
   `.col-subject` has the same defect: the four Cash-flow matrices, the
   trades table, the drift tree, the positions worklist and the history's
   Balance.
2. **#1010, sign colour is lost in table cells.** `.data-table tbody td {
   color: var(--color-text) }` (`app.css:2032`, specificity 0,1,2) outranks
   `.is-positive` / `.is-negative` (`app.css:3200`, 0,1,0). It shows on
   Securities → Trades, in all three tables (`securities_live.ex:2081–2094`,
   `:2133–2136`, `:2246–2281`). The drift tables have the same defect:
   `.drift-table tr.is-muted td` (`app.css:5564`, 0,2,2) turns a position
   row's negative drift grey. The trades table on Cash flow already has its own
   repair, scoped to its ID (Sprint 17 rule ⑥, `app.css:9696`). A `<span>`
   that carries the class inside a cell was never affected.
3. **#913, the split ratio sits left.** `<td data-role="split-ratio">` has no
   `num` (`transaction_management_live.ex:357`), so "2:1" sits at the left of
   the right-aligned Quantity column in proportional digits. Seen while
   drawing, and not in #913: the Balance column has the same problem. Its
   header (`:322`) carries only `col-subject`, and its cells (`:385`) carry
   `numeric`, a class that no rule backs, so the header and the figures sit
   left too. Under 560 px the table gives way to the phone rows, where both
   already sit right, so nothing changes at 390 px.
4. **#911, Allocation → Positions.** (a) In the worklist the Drift cell
   carries `col-subject` (`portfolio_live.ex:2218`) but its header does not
   (`:2160–2171`), and the Hint column follows it (`:2172`). The pin is inert
   because of #1009. At 390 px Drift ends 193 px outside the 344 px scroller,
   and Hint is further out. (b) The allocation basis line
   `p.summary-basis.allocation-basis` (`:1644`) matches no rule, so it renders
   as a body paragraph: 13 px, text colour, 1 em margins. (c) The tree's Drift
   ⓘ (`:1853`) says "Ist-Gewicht minus Soll-Gewicht". When the plan allocates
   less than 100 %, the drift is actually taken against the target divided by
   the allocated sum (`allocation.ex:938`, ADR-0040 §2), while the Target
   column shows the raw target. The reader cannot reconcile the three numbers.
5. **#1011, stylesheet drift.** (a) `.summary-basis` has only scoped rules
   (`app.css:5175`, `:5184`, `:8353`, `:9665`). Nineteen other uses have no
   size or colour, and most have no margin either: the four Cash-flow facets,
   Risk ×2, Tax ×3, Views and Buckets ×3, Snapshots, the Quotes tab, the KPI
   strip, Classifications, Allocation, and the two "since" notes. They render
   as body text. (b) `.disclosure-summary` is defined twice, at `:4889`
   (12 px) and at `:8441` (0.85rem / 600). The second wins, so every
   disclosure summary renders at 13.6 px / 600 instead of
   {typography.control-label} (12 px / 500). (c) "Portfoliodatensätze
   (Kompatibilität)" on Accounts & depots is a bare `<summary>` with the
   browser's triangle (`portfolio_accounts_live.ex:312`).

**Decided by the spec:**

- `DESIGN.md` → Amendment 2026-08-22: the subject column pins to the right
  edge of its own scroller, with an opaque background and a border for the
  seam, and is inert while the table fits.
- Colors: semantic colour applies wherever a sign exists, at every level of a
  table.
- Data tables / Value slot: the `.num` alignment family.
- {components.disclosure}: {typography.control-label} in
  {colors.text-muted} with the defined chevron (UX-DR19).
- The basis voice: 12 px, muted.
- ADR-0040 §2: drift is taken against the allocated portion.

**After** (the rules are in the board's `#proposal`):

- **① #1009:** `.data-table-wrapper > table { overflow: visible }`, one line,
  so that UX-DR15's wrapper becomes the sticky container. A bare table outside
  a wrapper keeps its own scroller. Drawing the fix showed it needs three
  companion rules, and without them ① introduces new defects:
  - **①b:** the seam becomes an inset shadow: `.col-subject { border-left:
    0; box-shadow: inset 1px 0 0 var(--color-border) }`. In the drift tables
    (`border-collapse: collapse`) the table paints the border, so the border
    stays behind when the cell sticks.
  - **①c:** `thead .col-subject { background: var(--color-bg-muted) }`.
    Outside `.data-table`, the pinned header cell takes `.col-subject`'s white
    and stands out of the grey header row.
  - **①d:** the pinned cell is opaque on striped and hovered rows. The stripe
    `.data-table tbody tr:nth-child(even) td` (`app.css:2044`) is 24 %
    bg-muted over transparent and outranks `.col-subject`, so once the column
    sticks the figures scrolling beneath it show through every second row. The
    board's frame "① allein" shows "8.554,00" printed over "2.044,60".
- **② #1010:** `.data-table td.is-positive` / `.is-negative` (0,2,1), plus
  `.drift-table tr.is-muted td.is-negative` (0,3,2). Rule ⑥ for the Cash-flow
  trades table becomes redundant. Removing it changes no pixel.
- **③ #913:** markup only. The split-ratio cell gets `class="num"`, which
  `#transaction-list td.num` already right-aligns with tabular figures. The
  board also draws the Balance column with `num` on its header and cells.
- **④ #911:** (a) is the choice below. (b) is fixed by ⑤a. (c) is a copy
  change: one more sentence in the ⓘ, shown only when `drift_basis` is
  `allocated_portion` (the same condition under which the basis line says
  "Abweichung gegen den verteilten Anteil"). The board's German draft: "Der
  Plan verteilt 85,0 %: Jedes Soll wird vor dem Vergleich auf diesen Anteil
  hochgerechnet, 34,0 % zählen als 40,0 %. Der unverteilte Rest erscheint
  nicht als Abweichung." The story sets the final wording.
- **⑤ #1011:**
  - (a) a context-free `.summary-basis { margin: 0; font-size: 12px; color:
    var(--color-text-muted) }`, placed before `app.css:5175` so that the later
    single-class rules that set their own margin (`.kpi-strip__basis`,
    `.tree-basis`) keep winning.
  - (b) the second definition is deleted, and the first takes the spec's
    12 px / 500. **This is not pixel-identical**: it would be only if the
    13.6 px / 600 winner were kept, and that keeps the violation.
  - (c) the compatibility summary gets `class="disclosure-summary"` and the
    chevron icon. `details[open] > .disclosure-summary .disclosure-chevron`
    already turns the chevron.

**#911 (a), the one choice: where the worklist's two-column subject pins.**
`DESIGN.md` says the flat table's "Drift is followed by the Hint column, which
is part of the same subject". `right: 0` can hold only one column.

**Variant A (recommended): the hint moves into the Drift cell.** The cell shows
the figure with the hint beneath it, which is the anatomy the tree's position
rows already have (`portfolio_live.ex:1973–1989`). The header gains
`col-subject`. One column, one `right: 0`, and no two widths to keep in step.
Sorting is still by Drift. Measured at 390 px, it leaves 186 px for the name
(more than the 144 px name column).

**Variant B: pin both columns.** Hint pins at `right: 0` with a fixed 10.5rem,
and Drift pins at `right: 10.5rem`. The columns stay as `DESIGN.md` describes
them. But the offset must equal the Hint's width exactly: a quantity that runs
wider widens the column, and Drift then covers the hint by the difference. At
390 px the pair takes about 280 of 344 px and leaves the name 62 px
(measured).

**Not drawn, C: pin Drift only** (add the header class, nothing else). The
smallest change, but the hint, which belongs to the same subject, sits
off-screen at rest.

**Why A.** It is the only variant that keeps the whole subject on screen at
390 px without coupling two widths, and the tree and the list then show a
position the same way. Its cost is one fewer column header and taller rows.

**Stated doubts the story settles:**

- ① moves clipping from the table to the wrapper. `overflow-x: auto` computes
  `overflow-y: auto`, so a popover inside a header cell (the tree's Drift ⓘ)
  can scroll a short table's wrapper vertically, where today the table clips
  it. Check the ⓘ in a tree with two rows.
- On `#transaction-list` the row hover wash sits on the `tr` and stops at the
  opaque pinned Balance cell. ①d covers `.data-table` only.
- Should the Balance column's `numeric` → `num` (same table, same one-word
  repair, same alignment family) ride #913, or be filed separately?
- #911 A removes the "Hinweis" header and the "—" of a row without a hint.
  `DESIGN.md`'s sentence about the flat table is rewritten. The tests that
  select the drift by `td.col-subject` keep working.
- The ⓘ sentence (#911 c) needs the allocated sum. The worked example (first
  category with a target) is optional, and the story may drop it.
- ⑤a gives `.kpi-strip__basis` (the Overview) and `.tree-basis`
  (Classifications) the 12 px muted voice for the first time; today they set
  only a margin. ⑤b changes 24 disclosure summaries in 15 modules, and the
  local 12 px / 500 on `.merge-manifest > .disclosure-summary`
  (`app.css:9420`) becomes redundant.
- H1 (#1029) draws the same Securities → Trades tables and names #1010. The
  generic rule ② repairs them, so H1 needs no table-scoped copy of rule ⑥.

**Outside this pass (Scope Lock):**

- Muted classes inside `.data-table` cells are outranked the same way as the
  sign classes. `#realized-trades-table td.trade-pa--na` (Sprint 17) is a
  local repair. A generic rule would have the same shape, but it is not in
  #1010's text.
- The open-lots table's "%" column wraps "+18,71 %" onto two lines at desktop
  width, because `.detail-trades-table td.num` has no `nowrap`.
- `.drift-table { margin-top: 1rem }` draws an empty strip inside
  `.data-table-wrapper` above every allocation table's header row.
- The securities detail tables sit in `.data-table-wrap`, which only sets
  `overflow-x`. ① does not reach them, and nothing there carries
  `col-subject`.

## Part 5 — H5: link text in light mode (#908)

**Board:** `design-language/mockups/ux-design-2026-10-02/05-light-contrast.html`,
rendered as `05-light-contrast.png` (1200 px). The board has no variants: it
shows before and after and one token change. `<html data-theme="light">` forces
light mode, which is how the app selects a theme (`layout_view.ex:1615` sets
`document.documentElement.dataset.theme`). Each frame sets its own
`data-theme` and `data-accent`. The board computes every ratio from the
rendered colours (WCAG 2.x relative luminance, translucent tints composited
in sRGB), and the results match an independent computation from the hex
values in `app.css` to two decimals.

**Before:** link text is the accent colour at body size, at rest:
`.link-button` (`app.css:7317`, also `.policy-rule__name`), `.merge-date-link`
(`:9484`), `.merge-record__target` (`:9388`) and `.kpi-summary__link`
(`:7553`). Accent text on the tint is the same case: `.alert-success`
(`:1310`), the active navigation. A plain `<a>` inherits its colour (`:230`).
Only coral fails, and only in light mode:

| Light, accent as 13 px link text on | violet #7c3aed | teal #0f766e | coral #e11d48 (today) | coral #ce1b42 (after) |
|---|---|---|---|---|
| bg #f6f7fa (canvas) | 5.32 | 5.11 | **4.38 fail** | 5.08 |
| bg-elevated #ffffff (panels, tables) | 5.70 | 5.47 | 4.70 | 5.44 |
| bg-muted #eef1f6 (note-severity data note) | 5.03 | 4.83 | **4.15 fail** | 4.81 |
| own accent-soft (#ede9fe / #ccfbf1 / #ffe4e6) | 4.80 | 4.86 | **3.91 fail** | 4.53 |
| warning-soft #fffbeb (attention note) | 5.50 | 5.28 | 4.53 | 5.25 |
| danger-soft #ffe4e6 (problem note) | 4.75 | 4.56 | **3.91 fail** | 4.53 |
| white label on the accent fill | 5.70 | 5.47 | 4.70 | 5.44 |

| Dark, accent as link text on (unchanged by the proposal) | violet #a78bfa | teal #2dd4bf | coral #fb7185 |
|---|---|---|---|
| bg #0b0f14 | 7.06 | 10.32 | 7.14 |
| bg-elevated #131a23 | 6.43 | 9.40 | 6.50 |
| bg-muted #1a2230 | 5.87 | 8.58 | 5.93 |
| own soft, composited over bg-elevated | 4.98 | 6.77 | 5.89 |

| Muted and subtle text (unchanged) | bg | bg-elevated | bg-muted | violet tint | teal tint | coral tint |
|---|---|---|---|---|---|---|
| light muted #5a6577 | 5.50 | 5.89 | 5.21 | 4.96 | 5.23 | 4.91 |
| light subtle #94a0b4 | 2.47 | 2.64 | 2.33 | 2.23 | 2.35 | 2.20 |
| dark muted #8b97a8 (tints over bg-elevated) | 6.49 | 5.91 | 5.39 | 4.58 | **4.25 fail** | 5.35 |
| dark subtle #5c667a (tints over bg-elevated) | 3.33 | 3.03 | 2.76 | 2.35 | 2.18 | 2.74 |

The board puts the real content side by side: a basis line with
`.merge-date-link`, the manual-quotes note with its "Freigeben…" remedy (note
severity, on bg-muted), the invisible-character note with "Stammdaten
bearbeiten" (attention), the Risk rule names as links in the findings table,
and "Regel gespeichert." as `.alert-success`. Today: 4.70 · 4.15 · 4.53 · 4.70
· 3.91. After: 5.44 · 4.81 · 5.25 · 5.44 · 4.53. The dark frames measure the
same before and after.

**Re-checking `DESIGN.md`'s computed contrast table.** Every ratio in it is
correct to two decimals. One verdict is inverted: "accent-coral /
bg-elevated 4.70 — fail normal text", although 4.70 passes 4.5:1. The table
has no row for the surfaces where a remedy link actually sits: bg-muted,
warning-soft and danger-soft, for any accent. Two rows are stale. Since #644,
`--color-selected` is `var(--color-accent-soft)`, so "selected #ede9fe" is
only the violet case, and "selected-dark #1f2c42" (4.74) cites a colour that
`app.css` no longer has.

**Decided by the spec:** "Normal-size text ≥ 4.5:1 on its surface in both
modes"; "Accent as text: violet and teal pass at body size in both modes;
coral passes only as large text … Body-size coral text in light mode is
barred (4.38:1)". The link treatment is the accent colour plus an underline at
rest (G7-A). So the spec already bars what the build does: with the coral
accent picked, every link is body-size coral text.

**After:** one token in two lines. `--color-accent-coral` changes from
`#e11d48` to `#ce1b42` in `:root` (`app.css:15`) and in `[data-theme="light"]`
(`app.css:126`). It keeps the same hue (HSL 347°, saturation 77 %); lightness
goes from 49.8 % to 45.7 %, the smallest step that clears 4.5:1 on all six
light surfaces. The binding surface is coral-soft, which is also danger-soft:
4.53. The dark blocks (`app.css:92` under `prefers-color-scheme: dark`,
`:159` under `[data-theme="dark"]`) keep `#fb7185`, and the board's dark
frames measure identically. The coral fills (`.button-primary`, the active
segment), the accent dot, the SMA-200 line and the benchmark-2 overlay move
with the token, and all gain contrast. `--brand-coral-2` (`app.css:10`, the
logo gradient) stays `#e11d48`. `DESIGN.md`, written by the story: the
frontmatter value; the coral rows recomputed; the inverted verdict corrected;
rows for bg-muted, warning-soft and danger-soft for all three accents; the
"selected" rows re-keyed to accent-soft; and the commitment bullet changed to
"all three accents pass at body size in both modes".

**Stated doubts the story settles:**

- Smallest step or a palette step? `#be123c` (rose-700, the same step teal
  uses) leaves more margin (5.24 on coral-soft), but it changes the look more.
  The brief asks for the smallest change, so the board proposes `#ce1b42`.
  Both meet the bar.
- A separate link-text token (`--color-link`) was considered. It would leave
  the coral fills and chart lines alone, but it needs a token in five blocks
  and a sweep of every rule that colours text with `var(--color-accent)`. It
  also misses `.alert-success` and the active navigation on the tint, which
  are accent text but not links.
- 4.53 on coral-soft and danger-soft leaves 0.03 of margin, and teal on
  danger-soft is 4.56. Lightening either tint later reopens the row, and the
  table should say so.
- The accent menu's coral swatch and every coral chart line get slightly
  darker. The operator sees this.

**Outside this pass (Scope Lock):**

- Dark mode: muted text on the teal tint, the meta line of a selected row
  under the teal accent, measures 4.25:1 (the tint composites to `#17383c` over
  bg-elevated). That is below the 4.5:1 floor `DESIGN.md` sets for
  {colors.text-muted}. Not link text. It needs its own note.
- Plain `<a>` inherits its colour and has no underline (`app.css:230`), and
  `.hint a` has no rule. So the inline links in hints ("Plan anlegen",
  "Im Bereich Klassifizierungen zuordnen") have no link affordance at all:
  no accent and no underline. Links inside data notes are fine: they inherit
  the note's colour and are underlined (`.data-note__body a`).

---

## Part 6 — H6: touch targets and focus (#1013, #1033)

**Board:** `design-language/mockups/ux-design-2026-10-02/06-touch-focus.html`,
rendered as `06-touch-focus--1200.png` and `06-touch-focus--390.png`. There
are four items. H6.2, H6.3 and H6.4 are before/after pairs. H6.1 is a real
choice, because UX-DR6 leaves the mechanism to the implementation ("padding
vs. min-height per control class is the implementation's call") and the two
mechanisms draw different pictures.

**The coarse-pointer state is drawn, not emulated.** The renderer has a
mouse, so `@media (pointer: coarse)` never matches during the render. The
"after" frames carry a board class, `.as-coarse`, which applies the proposal's
coarse rules exactly as written but with no media query; the board's pickbar
and phone caption say this. The "before" frames need no such trick, because no
coarse rule reaches these controls today. Every "before" number below was
measured with Playwright using `hasTouch`, which does match `pointer: coarse`,
at 1200 and 390 px. The dashed red and green boxes on the board are a drawing
aid: they show each control's hit box as the browser lays it out.

### H6.1 — a remedy inside a data note is 18 px tall on touch (#1013)

**Before:** since F26, `.link-button` carries none of the button's chrome:
`min-height: 0` and no padding (`app.css:7317`). Inside a note's sentence
(12 px at line-height 1.5) a remedy is therefore an 18 px hit box, with or
without `pointer: coarse`. "Freigeben…" measures 71 × 18 px at both widths and
under both pointers. There are eight call sites in five kinds of note:
`manual_quotes.ex:40` (Release…), `securities_live.ex:2815` ("Kurse
aktualisieren" in the release result), `:1064`, `:2500` and `:2682` (the
invisible-characters note), and `tax_live.ex:618`, `:894` and `:900` (the Tax
notes). Not affected: `.policy-rule__name` already has 44 px, and the
rule lists on Risk and the year buttons in the income table are not remedies
inside a note.

**Decided by the spec:** a target of at least 44 px under `pointer: coarse`
(UX-DR6), and the remedy is a child of its note (UX-DR17).

**Variant A (recommended): the hit area grows and the line does not.** Rule
① sets `padding-block: 13px; margin-block: -13px` on
`.data-note__body .link-button` under `pointer: coarse`. The button's box is
44 px tall and its line stays at 18 px, so no note reflows: the three notes
measure 144, 72 and 126 px in both the before and the after frame. The
`.positions-toggle` already uses this technique. The picture at rest is
identical. The box reaches into the neighbouring lines, which hold only text,
and on a note's first or last line it extends about 4 px past the note's
border.

**Variant B: on touch the remedy gets its own 44 px line.** This is robust
and nothing overlaps, but the remedy leaves the sentence, every note becomes
26 px taller on touch, and desktop and touch render the same note
differently.

**Why A.** The remedy stays inside its sentence, no note changes height, and
the technique already exists in the stylesheet.

### H6.2 — every dialog's close button stays 30 px wide on touch (#1033)

**Before:** there are seventeen `<dialog>` elements, and each one's × is a
`<button class="icon-button">`. `.icon-button` sets `width: 30px; height:
30px` (`app.css:1733`), but the base rule `button { min-height: 34px }`
(`app.css:1178`) wins the height, so every × measures 30 × 34 px. That
includes the merge dialog, which #1033 names, and every other dialog too.
Beside a title that wraps, the × also shrinks in width (`flex: 0 1 auto`):
24 px at 1200, 18 px at 390 for a long security name, and 28 px for "Tagesgeld
(alt) zusammenführen" in a narrow frame. Only the release dialog was repaired
in Sprint 17 (closing act γ D6). It has three rules: `.quote-release-dialog
.modal-head { gap: var(--space-2) }`, `> .icon-button { flex: none }`, and
44 × 44 inside `@media (pointer: coarse)` (`app.css:9506–9519`).

**Decided by the spec:** UX-DR6, and `DESIGN.md`'s release amendment ("keeps
its 30 px beside a title that wraps, 44 px under a coarse pointer").

**After:** rule ② applies the release dialog's three rules to every dialog
head: `.modal-head` and `.filter-sheet__head` get the gap; `.modal-head >
.icon-button`, `.filter-sheet__head > .icon-button` and `.booking-drawer
.detail-pane-head__actions > .icon-button` get `flex: none`, plus 44 × 44 under
`pointer: coarse`. The three `.quote-release-dialog` rules are dropped
because rule ② covers them. That covers twelve `.modal-head`s (account and
security merge, set balance, rename, new account, new security, rule, logo,
buckets, split, and "Kann nicht gelöscht werden" twice), two filter sheets,
and the booking drawer (two render paths). On desktop nothing changes except
that the × no longer shrinks.

### H6.3 — an Overview row shows the browser's focus ring (#1033)

**Before:** `.attention-item` (`app.css:1025`) has no `:focus-visible` rule.
Tabbing through the Overview draws Chromium's default ring (`outline: auto`,
1 px, tight around the text) on "Abgeschlossene Trades", "Ziel-Abweichungen"
and "Fällig". The KPI strip directly above draws the 2 px accent ring.

**Decided by the spec:** "Focus indicator: solid 2px accent outline"
(`DESIGN.md` → Colors), the form that `.stat--link`, `.filter-chip` and
`.row-actions__kebab` already carry.

**After:** rule ③ sets `.attention-item:focus-visible { outline: 2px solid
var(--color-accent); outline-offset: 2px; border-radius: var(--radius-sm) }`.
The list's 6 px row gap keeps the ring clear of the next row. One rule covers
all three cards. #1033 names two of them; "Fällig" uses the same class.

### H6.4 — the × raises a one-line result's line (#1033)

**Before:** `.inline-result__dismiss` declares `height: 1.4rem`
(`app.css:6145`), but `button { min-height: 34px }` wins, so the × is a
22 × 34 px box that is middle-aligned on its line. A one-line result such as
"Kurse aktualisiert." is 52 px tall instead of 36, and the severity word, which
is aligned to the top, sits 8 px above its sentence. So the cause is the
34 px floor, not the 1.4rem the issue names.

**After:** rule ④ sets `min-height: 0; height: 1rem`. The × fits the 18 px
line, the note measures 36 px, and the word and the sentence share a line.
The width, the margin and the hover stay as they are. Under `pointer: coarse`
the × gets `width: 44px; height: 44px; padding-block: 14px; margin-block:
-14px`. That keeps a 44 px target while the line stays at 18 px. This half is
required: without it, rule ④ would shrink the touch target from 34 px to
16 px.

**Stated doubts the story settles:**

- **H6.2 is bigger than its issue.** The UX-DR6 call-site table in
  `EXPERIENCE.md` lists `.icon-button` itself as an uncovered class, and
  amendment 1 binds the floor to every call site of a class. A class rule,
  `@media (pointer: coarse) { .icon-button { min-width: 44px; min-height:
  44px } }`, would cover the dialogs and also every toolbar icon button (on
  Securities: New, Sync prices, Columns), and those toolbars would grow on
  touch. The dialog picture is the same either way. The plan decides the
  scope: the dialog selector list, as #1033 asks, or the class rule, as the
  spec reads.
- In H6.1-A, the keyboard focus ring of a remedy under a coarse pointer
  would wrap the 44 px box. `.link-button` has no `:focus-visible` rule, so
  that ring is the browser's own (see Scope Lock).
- Rule ① covers `.link-button` only. A remedy written as an `<a>` inside a
  note (`.data-note__body a`, for example the Overview's data-quality links)
  is also 18 px tall on touch. Whether ① takes `.data-note__body a` along is
  for the story to decide. #1013 names only the button.
- H6.1-A and H6.4 put two 44 px targets side by side in the release result
  ("Kurse aktualisieren" and ×). Both grow only vertically, so they do not
  overlap. The story's test should pin that.

**`DESIGN.md`, written by the stories:** the remedy's touch target (Data
note), the dialog close button's rule for every dialog head (it replaces the
release amendment's sentence), the attention row's focus ring
(needs-attention card), and the dismiss's size (inline result).

**Outside this pass (Scope Lock):**

- Every `<button class="icon-button">` in the app is 30 × 34 px, not 30 × 30,
  because `.icon-button` sets `height` while the base `button` sets
  `min-height: 34px`. This applies to toolbars as well as dialogs.
- `.link-button` has no `:focus-visible` rule, so every remedy and every
  rule name except `.policy-rule__name` draws the browser's ring. This is the
  same defect class as H6.3.
- `.row-actions__kebab` keeps the base button's `box-shadow` (it resets the
  border and the background but not the shadow), so on a phone each kebab
  shows a faint box. It is visible on board 07, H7.6.

## Part 7 — H7: the phone at 390 px (#1012, #1033, #909, the history's kebab)

**Board:** `design-language/mockups/ux-design-2026-10-02/07-phone-390.html`,
rendered as `07-phone-390--390.png` (the reference) and
`07-phone-390--1200.png` (the same frames on desktop, where they should not
change). There are six items. H7.1b, H7.2, H7.3 and H7.6 are before/after
pairs. H7.1 and H7.5 are real choices. H7.4 is code only and has no picture.
At 390 px the board renders in a true 390 px viewport, so `app.css`'s rules
under 720 and 560 px fire. The coarse-pointer 44 px floors (detail tabs,
kebab) are set by hand, because the renderer has a mouse. The security
Overview's six-figure grid, which stays in three columns at phone width, is
drawn on board 03 (H3, rule ④), so board 07 does not redraw it.

### H7.1 — the quote table's "Quelle" column sits off-screen at 390 px (#1012)

**Before:** under 560 px every table is its own horizontal scroller (`table
{ display: block; overflow-x: auto }`, `app.css:1569`). The quote table needs
about 470 px and its frame has 368 px. "Quelle" is the only per-row marker of a
manual close, and it starts at x 326, so it is fully visible only after a
swipe. The default range is 1Y, so a year of rows (about 250) is read this
way.

**Variant A (recommended): two-line rows (UX-DR27).** Rule ① adds `<ul
id="quote-phone-rows" class="phone-rows">` beside the table, with the date
(`.phone-row__name`) over the source badge (`.phone-row__ids`), and the close
on the right. "gespeichert …" (`.phone-row__figure2`) appears only where a
split adjusted the close, because elsewhere it repeats the same number. The
table's wrapper gets `id="quotes-table-wrapper"` and `display: none` under
560 px. `.phone-rows { display: block }` already ships. On desktop nothing
changes. The cost is height: a row is 61 px instead of 34.

**Variant B: pin "Quelle" (`.col-subject`, #730).** Under 560 px the pin does
stick on this table (measured), because its wrapper is `.data-table-wrap`
without `min-width: max-content`. That is unlike the tables in H4 #1009.
However, the 153 px "Portfolio Performance" badge takes 40 % of the width,
"Gespeichert" scrolls underneath it, and on even rows the zebra rule
(`.data-table tbody tr:nth-child(even) td`) outranks `.col-subject`'s opaque
background, so the value underneath shows through. Board 04 (H4 ①) repairs
that background.

**Why A.** The source sits where the eye starts a row, the rule already
governs three phone lists (securities, history, trades), and no column is
covered. Rejected without a picture: hiding "Gespeichert" under 560 px. It
fits only when there is no split, and when there is a split it is the column
that matters.

### H7.1b — "Kurse aktualisiert." does not count the manual quotes that stayed (#1012)

**Before:** the sync keeps a manual quote wherever the provider returns a
close for the same day (`Quotes.upsert_many(…, protect_manual: true)`). Each
security's result counts this as `skipped_manual`
(`quote_sync.ex:236–243`), and the counts are only logged.
`sync_flash/1` (`securities_live.ex:5621`) reads only `ok`, `skipped` and
`error`, so it says either "Kurse aktualisiert." or "Kurssync abgeschlossen:
12 synchronisiert, 2 übersprungen, 0 fehlgeschlagen." and is silent about
them. Since #566 the message is no longer a toast. It is the page-level
inline result `#securities-action-result`, which at 390 px sits above the
detail pane.

**After:** a second sentence appears when the sum of `skipped_manual` across
the results is above zero, built with `ngettext`: "3 manuelle Kurse blieben
stehen, wo der Anbieter einen Schlusskurs lieferte." ("Ein manueller Kurs
blieb stehen, …" for one). It applies to both forms of the message. With zero,
the message stays as it is today. The verb repeats the note on the Quotes tab
("lässt ihn stehen, bis er freigegeben wird"). The word "übersprungen" stays
reserved for securities the sync does not query at all. The clause "wo der
Anbieter … lieferte" says what is counted: collisions, not all manual quotes
(the tab's note counts those). The OS notification (`notify_os`) carries the
same text.

### H7.2 — the selected "Kurse" tab sits off-screen and nothing scrolls it into view (#1033)

**Before:** the detail pane's tab row has nine tabs (about 760 px). It scrolls
as D6 requires, but it always opens at `scrollLeft: 0`, because the
`DetailTabs` hook (`layout_view.ex:288`) has only the keyboard half. Arriving
with `?tab=quotes` puts "Kurse" half under the right fade (measured at
x 350–410 in a row that ends at 380). The selected tab is in the URL, so this
happens after a reload, back or forward, or a shared link. Arriving with
`?tab=events`, where the Overview's "Fällig" rows link, leaves the tab wholly
outside the row. The trades card and list link to `?tab=trades`; Wealth links
to `?tab=transactions`. A security opened from the list starts on "Übersicht"
and is not affected.

**Decided by the spec, so no variants:** D6 ("the active tab is in view on
arrival", recorded for `.area-tabs` by #857 and #876, "so every tab row is
held to it"). UX-DR22 rejects both of the other forms the brief suggested:
"a within-area tab row scrolls; it never collapses into the area menu, and it
never wraps". A wrapping row and an overflow menu are the two options it
names and rejects.

**After:** `DetailTabs` gains the mount half of `AreaTabs`. It scrolls the
selected tab into the row's view with `scrollTo` on the row (never
`scrollIntoView`, so the page does not move), with no animation under
`prefers-reduced-motion`. The resting place is the last tab start before the
centring target at which the selected tab is whole. The hook marks
`data-scroll-start` / `data-scroll-end` and sets the trailing inset
(`--detail-tabs-tail`), so the row's end is a tab boundary. Rule ② lets the
fades follow the edges. In `app.css`, `.detail-pane-tabs` joins the three
`.area-tabs` selector lists. The board runs the same arithmetic in a small
script: "Kurse" rests with "Transaktionen" first and a left fade. "Termine"
rests at the end with no right fade and a 7 px inset. The server renders
`data-scroll-start` on the row, so the first paint, before the hook runs,
carries only the right fade. A tap on a tab scrolls nothing, because the tab
is already in view. At 1200 px with the sidebar the nine tabs fit (about 760
of 930 px). Below a window width of about 1000 px the row overflows on desktop
too, and the repair applies there as well.

### H7.3 — "Zeitraum 1Y" in German, where the Overview says "1J" (#1033)

**Before:** the Quotes basis line interpolates the raw code (`gettext("Range
%{range} · as on the Chart tab", range: @range)`, `securities_live.ex:2827`).
The chart it points to labels its buttons just as raw (`<%= range %>`,
`:1122`): "1M 3M 6M YTD 1Y 3Y 5Y MAX". Wealth and the Overview's KPI strip
translate the same tokens (`gettext("1Y")` → "1J", "Max";
`portfolio_live.ex:4445–4449`, `dashboard_live.ex:348`). The default range is
1Y, so a German reader sees "Zeitraum 1Y" on every first visit to the tab.

**Decided by the spec:** one token vocabulary app-wide (`EXPERIENCE.md` →
Period control), German labels for a German UI, and `MAX` becomes `Max`
("only the `MAX` casing changes", `EXPERIENCE.md`, 2026-08-05).

**After, and bigger than its issue:** if only the basis line were translated,
it would read "Zeitraum 1J · wie im Diagramm" next to a button labelled "1Y".
So the repair is one label function for the detail's eight tokens, used by
the buttons and by the basis line: "1M 3M 6M YTD 1J 3J 5J Max" in German, and
"…1Y 3Y 5Y Max" in English (the English buttons change from "MAX" to "Max").
The URL and event value (`phx-value-range`) stay the code. "1M", "3M" and
"6M" are new msgids and read the same in German. The fallback "Standard"
stays.

### H7.4 — the release result's "Kurse aktualisieren" syncs every security (#1033; code only, no picture)

**Before:** the follow-up is `phx-click="sync_now"` (`securities_live.ex:2815`),
and `handle_event("sync_now", …)` calls `QuoteSync.sync_all()` (`:4320`), so it
syncs the whole catalog, not the security just released.
`QuoteSync.sync_security/2` exists.

**Does the fix change rendered text? Yes.** Today the follow-up answers with
the catalog sentence. As soon as any security has no provider adapter, which
is true of every holding without a provider, for example one from an import,
that sentence reads "Kurssync abgeschlossen: 12 synchronisiert, 2
übersprungen, 0 fehlgeschlagen.". With `sync_security/2` the result is a single
map, and `sync_flash/1` says "Kurse aktualisiert." or "Kurssync
fehlgeschlagen: …" about the one security. With H7.1b, it adds that security's
count of manual quotes that stayed. The board says this in a callout and
draws no frame.

**Stated for the story:** the single path can print a raw reason, because
`sync_flash/1` inserts it with `Atom.to_string` or `inspect`. If the scheduled
sync is running, `sync_security/2` returns `:sync_in_progress` (single-flight),
and the message would read "Kurssync übersprungen: sync_in_progress". The
follow-up also clears the release result (`assign(:quotes_release_result,
nil)`), and its own result lands in the page-level slot, not next to its
trigger. The other two triggers (the list toolbar and the Chart tab) keep
`sync_all`, which is what they intend.

### H7.5 — "Verrechnungskonten" runs past its card (#909)

**Before:** `.import-stat-card .label` (`app.css:3848`) is 13.6 px, uppercase,
with 0.04 em tracking. It is a grid item with `min-width: auto`, so a long
word can neither wrap nor shrink. "VERRECHNUNGSKONTEN" needs 180 px in the
renderer. The card offers 140 px inside at 390 px (two columns) and 152 px on
desktop (three columns in `.import-done .summary`'s `max-width: 36rem`). The
word ends 23 px past the card edge at 390 px, which also takes it past the
screen edge, and 12 px past the card edge on desktop. The import preview's
figures use the same class, and there the label usually fits because the
columns are wider. The spec has no rule for this, and the issue leaves open
whether the label should wrap, hyphenate or fit.

**Variant A (recommended): a soft hyphen at the compound joint.** U+00AD goes
into the German msgstr, giving "Verrechnungs|konten" (the bar marks the
invisible U+00AD here), and rule ③
(`.import-stat-card .label { min-width: 0; overflow-wrap: anywhere }`) serves
as a floor. Where the card is wide enough, the reader sees nothing. Otherwise
the label breaks as "VERRECHNUNGS-" / "KONTEN", with a hyphen, in every browser.
The floor keeps any other long word, in any locale, inside the card: it breaks
without a hyphen but never runs past the edge.

**Variant B: the browser's hyphenation (`hyphens: auto`, plus the same
floor).** `lang="de"` is already set. Safari, Firefox, and Chrome on macOS and
Android hyphenate German. The renderer (Chromium without a German dictionary)
does not, so the floor takes over and the word breaks at an arbitrary letter
with no hyphen ("VERRECHNUNGSK" / "ONTEN"), as drawn. The result would depend on
the device.

**Why A.** It is deterministic on every device, costs one character in a
translation and one rule, and does not depend on a browser's dictionary.
Rejected without a picture: fitting the label (the `stat-label` token at
12 px, and one card per row on the phone). It fits this word in this font and
breaks again on the next long word.

### H7.6 — the history's phone row drops its kebab under the date (no issue yet)

**Before:** the history's two-line row has three children: the body, the
figures and the kebab (`<.row_kebab id="tx-phone-kebab-…">`,
`transaction_management_live.ex:443`). `#transaction-phone-rows .phone-row`
(`app.css:7757`) still declares two tracks (`minmax(0, 1fr) auto`), and its
comment still says the row has no kebab. Grid auto-placement puts the kebab
on a second line in the first column. It sits at the left under the subject,
every booking grows by the kebab's height (44 px on touch), and the kebab
reads as if it belonged to the next row.

**Decided by the spec:** UX-DR27 places the kebab at the row's end, as on the
securities rows.

**After:** rule ④ changes the existing rule to three tracks, `minmax(0, 1fr)
auto auto`, and corrects the comment. `.phone-row .row-actions__kebab {
align-self: center }` already ships, so the kebab stays centred when the
running balance adds a third line on the right. The trades rows have no
kebab, and their two tracks are correct.

**Stated doubts the stories settle:**

- H7.1-A renders a year of quotes twice in the DOM (table and rows), as the
  other phone lists already do. For `Max` that can mean thousands of rows.
  The story decides whether the rows need a cap with a stated limit
  (UX-DR26).
- H7.1b's sentence counts across every security the sync touched. Naming
  which securities kept manual quotes ("davon 3 bei Nordwind Industrie AG")
  is possible from the per-security results, but the board does not propose
  it.
- H7.2: `AreaTabs` and `DetailTabs` would carry the same reveal arithmetic.
  The story decides whether to extract a shared helper or copy it.
  `css_layout_sweep_test.exs` pins `.detail-pane-tabs`' one-sided fade, and
  the story extends it with the edge rules.
- H7.3 changes English rendered text ("MAX" → "Max"). No test asserts the
  old labels.
- H7.5-A: the soft hyphen either goes into the shared msgstr of "Cash
  accounts" (five call sites, harmless where nothing breaks) or into a
  card-scoped msgid (`pgettext("import summary", …)`, two call sites). The
  scoped msgid is the narrower change. Copying the label may carry the
  U+00AD in some browsers.
- H7.5-A meets the repository's invisible-Unicode gate
  (`check-invisible-unicode` in pre-commit and CI), which refuses a raw
  U+00AD. The gate's own mechanism is an entry in `.unicode-allowlist.txt`
  with a written reason, scoped to that one msgstr. That entry is the
  story's to add and to argue in its commit; the board itself writes the
  character as `&shy;`.

**`DESIGN.md`, written by the stories:** the quote phone row (Phone lists,
UX-DR27), the sync result's sentence (releasing manual quotes), the detail
tab row's arrival rule (D6, beside #857), the detail range labels (Period
control), the stat card label's break rule, and the history row's three
tracks.

**Outside this pass (Scope Lock):**

- With a custom range applied, the Quotes basis line still names the last
  preset ("Zeitraum 1Y"), while the table shows the custom range.
  `quotes_tab_panel` receives only `range={@detail_range}`
  (`securities_live.ex:1391`), but the rows are loaded from
  `@detail_custom_range` (`:5281–5285`).
- The page-level `#securities-action-result` has no horizontal margin
  (`.inline-result__region` sets only `margin: 8px 0`, and `.workspace-panel`
  has no padding), so at 390 px its note sits flush with the screen edges.
  `EXPERIENCE.md` → App shell says nothing is flush with the screen edge.
- `.area-tabs` carries no server-rendered `data-scroll-start`, so before the
  `AreaTabs` hook runs (the dead render, or with no script at all),
  `.area-tabs:not([data-scroll-start])` draws a left fade over the first
  tab. `DESIGN.md` D6 says that without script the row keeps the one-sided
  right fade. This was read from the CSS and markup, not rendered.
- `.import-stat-card .label` is 13.6 px (`0.85rem`), while the spec's
  `stat-label` is 12 px.

---

## Part 8 — H8: dialogs and messages, eight repairs (#910, #918, #921, #969, #966, #920, #1032 UI half, #968)

Board: `mockups/ux-design-2026-10-02/08-dialogs-copy.html`
(`08-dialogs-copy--1200.png`, `08-dialogs-copy--390.png`). One section per
issue. Four are before/after repairs: H8.1, H8.3, H8.7 and H8.8. Four contain
a real choice and show variants: H8.2, H8.4, H8.5 and H8.6, with **A
recommended in each**. The 390 px rendering shows only the after or
recommended states. The board adds three `app.css` rules (in
`<style id="proposal">`). Every other element on it is markup and classes that
already ship. All names, ISINs and figures are invented. The stored invisible
characters are written as HTML entities, never raw.

### H8.1 — #910: the rule dialog's version list numbers each version twice

**Before:** `risk/policy_rule_dialog.ex:403–412` renders the list as
`<ol class="policy-rule-versions">`. In app.css, `.policy-rule-versions`
(line 8503) sets only the font size and colour, and the global `ol` rule keeps
the browser's markers. Each entry therefore reads "1. Version 1 · 01.02.2026 –
31.05.2026 · 12,5 % · hart · Operator".

**Decided by the spec / the plan:** the issue asks for one numbering. G12.1-A
puts the author ("· Operator", "· Agent") at the end of each entry.

**After:** the label stays and the marker goes: `list-style: none;
padding-left: 0` on the existing rule, and `role="list"` on the `<ol>`. Keeping
"1." and dropping the label is the worse choice, because the version note
("Speichern legt Version 4 an. Version 3 (7,5 %) gilt seit …") and the retire
confirmation refer to versions by the label.

**Stated doubts the story settles:**

- `role="list"` is there because Safari drops list semantics from a list
  without markers. The story keeps it and tests it.

### H8.2 — #918: the security delete confirmation and "Cannot delete"

**Before:**

- **The confirmation** (`securities/row_context_menu.ex:180`, de "Dieses
  Wertpapier löschen? Vorhandene Buchungen blockieren das Löschen; Notizen und
  Logo gehen verloren.") says the notes are lost. In fact they block the
  delete. `security_notes` is `delete: :restrict` in `Lifecycle.ForeignKeys`
  (ADR-0044), and so are quotes and events. Policy rules are refused before
  this check, in `Catalog.delete_security/2`.
- **What actually goes with the security**, each through a journaled writer:
  category assignments, position targets, position bucket overrides and
  identifier aliases. The logo goes with the row.
- **"Cannot delete"** (`delete_blocked_dialog/1`) says "%{name} is referenced
  by existing transactions or quote history". It leaves out notes and events.
- **The merge line and "Merge into…"** appear only when `Delete.remedy/2`
  returns `:merge`, and nothing on screen says why.
- **The refusal already counts what blocks it.** It carries
  `{:referenced, counts}` per table (`securities_live.ex:4932`), and the page
  uses this only to choose the remedy.

**Decided by the spec / the plan:** the issue asks for both texts, in English
and German, to match what blocks the delete. The logo clause stays. The delete
path, the API and MCP stay unchanged. The board decides whether the dialog
names counts or lists the kinds in general terms. Precedent: the accounts page's
"Cannot delete" already names counts (`blocked_sentence/1`: "„Girokonto“ hat
noch 42 Buchungen — zuerst zusammenführen.").

**The confirmation, in both variants:** it opens before the check, and unlike
the accounts menu, the securities menu does not read references when it opens.
So it can only speak in general terms:

- en: "Delete this security? Bookings, quotes, events, research entries and
  policy rules block the deletion. Removed with it: its classifications,
  position targets, bucket assignments and former ISINs, each journaled, and
  its logo."
- de: "Dieses Wertpapier löschen? Buchungen, Kurse, Termine,
  Research-Einträge und eigene Regeln blockieren das Löschen. Mit entfernt
  werden seine Klassifizierungen, Positionsziele, Bucket-Zuordnungen und
  früheren ISINs, jede im Journal, und das Logo."

**Variant A (recommended): the dialog names what blocks, with counts.** The
first line says "„Nordwind Industrie AG“ hat noch 12 Buchungen, 840 Kurse und
3 Research-Einträge." The second line depends on the remedy:

- **Research entries block it:** "Research-Einträge werden nie entfernt und
  ziehen bei keiner Zusammenführung mit. Stilllegen blendet das Wertpapier aus
  der aktiven Liste aus; alles bleibt erhalten." The footer offers Cancel and
  Retire instead.
- **Only what a merge carries blocks it:** "Ist es ein Duplikat, führt
  „Zusammenführen in…“ seine Buchungen, Kurse und Termine in das andere
  Wertpapier. Stilllegen blendet es aus der aktiven Liste aus; alles bleibt
  erhalten." The footer offers Cancel, Merge into… and Retire instead.

The policy-rule state (the rule list) stays as it is.

**Variant B: the kinds in general terms.** "„Nordwind Industrie AG“ hat
Buchungen, Kurse, Termine oder Research-Einträge und kann nicht gelöscht
werden. Stilllegen …" One sentence fits every case. But the operator still
cannot tell which kind blocks, so Merge into… appears for one security and not
for the next, with no reason given.

**Why A.** The counts are already in the refusal, and the accounts page is the
precedent. It also makes the reason for the remedy visible: research entries
mean retire, anything else means merge.

**Stated doubts the story settles:**

- Joining three or more parts: only "%{first} and %{second}" exists, so the
  story needs a list join and a plural msgid for each kind.
- One word for security events. The merge record says "Events" in English and
  "Termine" in German, and the board uses those.
- `policy_rule_versions` can appear in the counts, but rules are refused before
  the count is made. The story decides whether that key gets a label anyway.
- The merge sentence gains "Termine", because events move in a merge
  (`merge: :repoint`).
- `DESIGN.md` records the adopted wording, as the issue asks.

### H8.3 — #921: field errors in the security and account dialogs, in German

**Before:**

- `securities/security_form_dialog.ex:843–851` builds each message by hand
  from the raw changeset text.
- `portfolio_accounts/account_form_dialog.ex:436–464` passes
  `AccountNames.name_error/3` and the changeset messages through unchanged.
- On a German page, "Neues Depot mit Verrechnungskonto" therefore shows "is
  already the name of securities account #4 in this portfolio" under the depot
  name. The same goes for "can't be blank", the ISIN check, the currency freeze
  ("is frozen once referenced (12 transactions, 840 quotes)") and the
  former-name guard.

**Decided by the spec / the plan:** German at the field (EXPERIENCE.md,
"Language (binding)"). The API and MCP stay in English. The issue offers two
mechanisms, and both produce the same picture.

**After:** German at the field.

- **Plain Ecto and catalog messages** go through the `errors` domain. Their
  German text is already in `errors.po`: "darf nicht leer sein", "ist keine ISIN
  (zwei Buchstaben, neun Buchstaben oder Ziffern und eine Prüfziffer)".
- **The name guard** maps to the rename dialog's own copy. Drawn: "„Depot 1“
  heißt bereits ein anderes Depot. Einen anderen Namen wählen oder jenes Depot
  zusammenführen oder umbenennen."
- **The former-name guard** uses the rename dialog's "„Depot 1“ ist ein
  früherer Name von „Depot Süd“ — …".
- **The freeze** needs new copy. Drawn: "steht fest, sobald etwas darauf
  verweist (12 Buchungen, 840 Kurse)".

**A finding inside the scope:** the two live-name `msgstr`s the after adopts
("„%{name}“ heißt bereits ein anderes Verrechnungskonto/Depot. Wählen Sie
einen anderen Namen, oder führen Sie …") are the only strings in `default.po`
that address the reader as "Sie". EXPERIENCE.md's binding impersonal voice
rules that out. The after shows them impersonal. The msgids are shared with
the rename dialog, so the fix changes that dialog too.

**Stated doubts the story settles:**

- Which mechanism: placeholder form in the domain, or mapping in the dialog by
  the `validation:` key. Nothing on screen shows the difference.
- The freeze's counts are built in the domain with English nouns
  (`Freeze.counts/1`), so the placeholder form needs them as a separate part.
- The same hand-built messages exist in `securities/merge_dialog.ex`,
  `tax_live.ex` and `snapshots_live.ex`, as the issue lists. The story either
  covers them or names them.

### H8.4 — #969: the plan editor, a sum under 100 %

**Before:** `put_sum/1` (`classifications_live.ex:1704`) sets `mismatch?:
not Decimal.equal?(sum, @hundred)`. The footer row (`:1029–1037`) then adds
`is-target-mismatch` and ✗ for every Σ that is not 100. A plan that is
deliberately short, at 92 %, shows the warning colour and ✗.

**Decided by the spec / the plan:**

- **ADR-0040 §3:** the ✗ and the warning colour are kept for a sum above 100 %
  and for the position-vs-category conflict. A sum under 100 % shows as a
  remainder row, at ordinary weight, without warning colouring.
- **DESIGN.md D3** fixes that row: it is the last row, it has a category row's
  rhythm, its label is `text-muted`, its figure sits in the tabular slot, and
  it is neither selectable nor editable.
- **The issue:** the cue above 100 % stays unchanged, and the story also fixes
  the checklist line and the demo seed.

**Variant A (recommended): no mark under 100 %.** Under 100 % the Σ row shows
the sum with no glyph and no colour. Below it comes "Nicht verteilt 8%" (en
"Not allocated"), styled by proposal ② `.soll-row--remainder`. At exactly
100 % the row reads "100% ✓" and there is no remainder row. Above 100 %
nothing changes: "104% ✗".

**Variant B: ✓ for every Σ up to 100 %.**

**Why A.** Since #467, ✓ has meant "adds up to 100". Placed next to 92 %, it
would contradict the remainder row right below it. A keeps one meaning for ✓
and one for ✗, and the remainder row explains the gap.

**Stated doubts the story settles:**

- **The label.** "Nicht verteilt", not "Nicht zugeordnet": that is the
  Unassigned bucket on Allocation. It matches the Allocation basis clause
  ("verteilter Anteil").
- **No row at 0 %.**
- **One formula.** The editor's remainder is 100 − the live Σ, cash included.
  `Allocation.unallocated_remainder/1` works the same way, from a top-level sum
  that includes cash, so the two agree. The story checks the currency tree,
  where cash is distributed.

### H8.5 — #966: Accounts & depots, the rename dialog's invisible-character note

**Before:** `portfolio_accounts/rename_dialog.ex:62–135` has no note. Its
field refuses invisible characters, as every writer does, so retyping the name
is the remedy. Retyping turns the old spelling into a former name. Former names
are written without the text check (`former_names_changeset/2` in
`cash_account.ex` and `securities_account.ex`). After the remedy, the list
therefore shows "Depot Nord" (still carrying a U+200B ZERO WIDTH SPACE) under
an account named "Depot Nord".

**Decided by the spec / the plan:** the G20 amendment (pick G12.2-B) places
one attention note where stored text is renamed. The remedy is the sentence
"Typed in anew, it is clean." (de "Neu eingegeben ist er sauber."). The note
follows the field (`texts={[@name]}`), as in the rule dialog, and sits after
the form, as with the inline rename of views, buckets and categories. Both
variants share this.

**Variant A (recommended): former names are marked too.** When any former name
carries such characters, a second note sits inside the open "Frühere Namen"
disclosure, above the list:

- de: "Ein früherer Name enthält 1 unsichtbares Zeichen. Ein Import, der ihn
  genau so schreibt, bucht weiter auf dieses Depot."
- en: "A former name contains 1 invisible character. An import that writes it
  exactly so keeps booking to this depot."

Its disclosure, "Namen mit sichtbar gemachten Zeichen", spells out each
affected former name.

**Variant B: only the current name is marked.** The amendment keeps lists
unmarked.

**Why A.** The former-name list is the one list in this dialog that can be
edited, and it is where the remedy leaves the old spelling. Removing that entry
decides whether an import still finds the depot. The MCP companion already
gives the agent the escaped spelling, so without A the operator alone cannot
see it. This is one note per subject, as the rule dialog has one for its name
and one for its note.

**Stated doubts the story settles:**

- A third subject for `AppShell.invisible_text_note/1` (`:former_name`), with
  its sentence, plural and summary, in a cash form and a depot form.
- Former names that arrived by a merge are covered too.
- The row itself carries no mark: the disclosure says which name it is.
- The amendment's "Where it stands" point is rewritten.

### H8.6 — #920: the securities list, when a row action finds its security gone

**Before:** `securities_live.ex:4784–4793` looks the security up. If the
lookup finds nothing, it only closes the menu, so the row stays and every
action on it does nothing. The delete's own `{:error, :not_found}` branch
(`:4926`) reloads silently, but the page reaches it only in the race after the
lookup.

**Decided by the spec / the plan:** reload the list, and drop any selection or
detail pane that points at the vanished security. The API and MCP do not
change.

**Variant A (recommended): reload with one note.** The note appears in the
page's inline result slot (`put_action_result(:note, …)`):

- **Merged away:** "„Meridian Global Equity ETF · XS0000000002“ wurde
  inzwischen in Meridian Global Equity ETF · XS0000000001 zusammengeführt; die
  Liste ist neu geladen." The survivor is linked. It comes from
  `Lifecycle.merged_into/2`, which the page's link handling already uses.
- **Deleted, or a merge chain that ends at a deleted row:** "„Helios Solar
  Systems SE“ wurde inzwischen gelöscht; die Liste ist neu geladen."

The name and its twin tag come from the stale list (`SecurityNames.label/2`).
The delete's own not-found branch shows the same note.

**Variant B: reload silently**, which is the issue's literal wording.

**Why A.** For a delete, the row going away is what the operator asked for. For
Edit, Retire or Merge into… it is not, and a row vanishing without a word reads
as a lost click.

**Stated doubts the story settles:**

- Severity: `note`, as drawn.
- English copy: "“%{name}” was merged into %{target} meanwhile; the list is
  reloaded." and "“%{name}” was deleted meanwhile; the list is reloaded."
- The name parts go through `<bdi>`, per H8.8.

### H8.7 — #1032 (UI half): merge records, the result phrase and empty merges

**Before:**

- `portfolio_accounts/merge_records.ex` `result_phrase(:security, …)`
  (`:410–436`) counts only `collapsed_duplicate`. Its own open line
  (`line_value(:bookings)`) does list "1 Split zusammengelegt".
- `securities/merge_preview.ex` `result_message/2` (`:1425`) has the same gap
  in the inline result after a merge.
- `line_value(:check)` (`:673–708`): both writers start `check_dates` with
  `Clock.today()` (`cash_merge.ex:536`, `depot_merge.ex:488`). The depot keys
  "nichts zu prüfen" on `securities_checked = 0`, and the cash account has no
  such key. An empty cash merge therefore reads "Saldo an 1 Tag bestätigt",
  while an empty depot merge reads "nichts zu prüfen".

**Decided by the spec / the plan:** the merge-records amendment (G2-A) and
ADR-0050 §12/§13. The result is stated in the confirmation's own words and
counted from `manifest_summary/1`.

**After:**

- The security phrase adds "1 Split zusammengelegt" after the duplicates, in
  both places. It uses the open line's own msgid (`pngettext("merge record",
  "%{count} split collapsed", …)`).
- An empty merge reads "nichts zu prüfen" for every kind.

The phrase does not use a total ("3 entfernt"), as account merges do, because
a total would mix the operator's choice (duplicates) with an automatic step
(a split on the same day).

**The liveness half changes no picture.** The page already resolves its own
rows into `{:live, …}`, `{:merged, …}`, `{:merged_gone, …}` and `:deleted`
(`MergeRecords.target/4`), and the words for each exist ("jetzt in einem
inzwischen gelöschten Depot"). A flag in `GET /api/v1/merges` would replace
that lookup, not the words, so it needs no board.

**Stated doubts the story settles:**

- **What counts as "empty" is a bigger question than the issue states.** The
  cash merge loads both accounts' rows (`cash_merge.ex:477–483`), so its check
  dates include the target's booking dates. An empty source merged into a
  target with history reads "Saldo an 15 Tagen bestätigt" today. "1 Tag" is
  only the case where both are empty.
- **The story picks the rule:**
  - in the words: key on the source having moved nothing (no payload change);
  - in the writer: stop counting today when nothing moves (a payload change,
    with a contract entry).

### H8.8 — #968: stored names isolated in flash messages and headings

**Before:**

- **Flashes put the name into finished strings:** `securities_live.ex:4866`
  "Retired %{name}" (de "%{name} stillgelegt"), `:4910` "Deleted %{name}", and
  `merge_preview.ex` "Merged into %{target}: …".
- **Headings do the same:** "Merge %{name}" (de "%{name} zusammenführen") in
  both merge dialogs, and "Rename — %{name}" (`rename_dialog.ex:73`).
- **The effect:** a name stored before G20 that carries a U+202E RIGHT-TO-LEFT
  OVERRIDE, with no U+202C POP DIRECTIONAL FORMATTING after it, reverses the
  rest of the line. It renders as "Nordwind tgelegllits GA eirtsudnI", and the
  heading as "Depot nerhüfnemmasuz droN".

**Decided by the spec / the plan:** the G20 amendment's `<bdi>` bullet. The
translated sentence is split around its placeholder, and the stored name is set
in `<bdi>` (`policy_rule_dialog.ex` `frame/1` and `isolated/1`, `:139–160`).
Flash messages and headings are listed there as the follow-up.

**After:** the name sits in `<bdi>`, and the reversal ends with the name:
"Nordwind GA eirtsudnI stillgelegt", and "Depot droN zusammenführen".
Only the stored name itself still reads oddly, and the G20 note marks it
wherever it is renamed. Ordinary names render exactly as today, which is why
the issue said no board was needed. The picture changes only for such names.
No CSS is needed.

**Stated doubts the story settles:**

- **One helper.** The rule dialog's `frame/1` and `isolated/1` become a shared
  component.
- **Flash messages.** The flash carries the name as its own part. The inline
  result's `message` is `:any`, so it can hold a rendered fragment.
- **Attribute strings.** Strings such as `data-confirm` and `aria-label` that
  contain a name cannot take `<bdi>`. The story either uses Unicode isolates
  there, written as escapes, or leaves them out and says so.
- **Headings that end with the name** ("Rename — %{name}") render the same
  either way. They are isolated anyway, so the rule has no exceptions.

### Outside this pass (Scope Lock)

- **"Cannot delete" at 390 px.** With three buttons (Cancel, Merge into…,
  Retire instead) it wraps two labels onto two lines each. This has been live
  since Sprint 16 added the merge button. The rule dialog has a phone rule for
  its three actions (app.css 8512–8530). File it as a follow-up.
- **Field errors are bold.** A `.field-error` inside a `<label>` takes
  `label span`'s weight of 680 (app.css:1090), so a two-line German error reads
  as a bold red block (visible in H8.3). DESIGN.md does not specify it.
- **The securities row menu could read references as it opens**, as
  `open_account_menu` does (`Delete.referenced_by/1`). A refused delete would
  then skip the confirmation, and the confirmation could name exactly what
  goes. #918 keeps the delete path unchanged, so this stays out.
- **The plan table at 390 px.** The global `table { display: block }` under
  560 px (app.css:1568) keeps the plan table at content width. This predates
  #969, and the remainder row follows it.

---

## Part 9 — What the authors found outside this pass (Scope Lock)

Each Part above ends with its own list. This is the consolidated view the
plan's Lane Z files at PR γ's branch opening.

**Already folded into a plan lane,** so nothing is filed for them:

- every `.icon-button` is 30×34, because the base button's 34 px floor
  overrides the class (H6; plan U4 fixes it on the class);
- the chart tab's range buttons show "1Y 3Y 5Y MAX" in German too (H7; U5);
- the security Overview's six figures stay in three columns at phone width
  (H3, rule ④; U5);
- the transaction history's phone-row kebab drops to its own line (H2's
  phone render, drawn on H7; U5);
- the Balance column's `numeric` class has no CSS rule (H4; U2, with #913);
- the transactions row menu passes no caption to the phone sheet (H2;
  variant A fixes it).

**To file, each with its source Part:**

- correcting the facts of the twelve kinds the drawer cannot book is
  possible over the API and not on screen: a two-way gap outside #912 (H2b);
- the security's Transactions tab rounds a booked price to two places
  (0,985 reads "0,99"), and that is where the two-scales guard sends the
  operator (H3);
- in dark mode, muted text on the teal tint (a selected row's meta line)
  measures 4.25:1, below the 4.5 floor (H5);
- plain links inside hints ("Plan anlegen", "Im Bereich Klassifizierungen
  zuordnen") carry neither the accent colour nor an underline (H5);
- with a custom range applied, the Quotes basis line still names the last
  preset (H7);
- at 390 px the page-level `#securities-action-result` sits flush with the
  screen edges (H7);
- before its hook runs, `.area-tabs` draws a left fade over its first tab,
  against D6; read from the CSS, not rendered (H7);
- `.link-button` has no `:focus-visible` rule (H7);
- `.row-actions__kebab` keeps the base button's shadow (H7);
- the import card's label is 13.6 px where the spec's `stat-label` is
  12 px (H7);
- on a phone, "Kann nicht gelöscht werden" with three buttons wraps two
  labels onto two lines, live since Sprint 16 (H8);
- a field error inside a label inherits `label span`'s weight 680 (H8);
- the securities row menu does not read references before its confirm
  opens, unlike the accounts menu (H8);
- under 560 px the global `table { display: block }` keeps the plan table
  at content width (H8).
