---
layout: docs
title: "ADR-0062: Every function a widget — dashboards composed from widgets, one period above them"
description: "Decision for idea I56 (FR-60). Every user-visible function becomes a registered widget: one existing read, drawn in fixed sizes, with its computation basis behind its ⓘ. The operator composes dashboards from widgets, stored on the server and journaled, so the agent can compose one too; curated templates ship read-only. One period above every dashboard, remembered per browser, which a widget follows until it pins its own. The available width picks one of three layouts, never the device. Built screen by screen, the Overview first."
---

# ADR-0062: Every function a widget — dashboards composed from widgets, one period above them

- **Status:** Accepted. Adopted by the merge of the Sprint 31 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
  Amended on 2026-11-25 by the Sprint 32 planning PR (resize makes room,
  the tabs ship as starter dashboards, the periods; see the amendment at
  the end).
  To be built from Sprint 31, Lane D, the Overview first (the Sprint 31
  plan, D-4); the other screens follow screen by screen.
- **Date:** 2026-11-21
- **Answers:** FR-60 (`epics.md`); idea I56
  (`_bmad-output/planning-artifacts/ideas.md`, the owner, 2026-11-21:
  „Ich denke das wir alle funktionen auf widget basis umstellen brauche
  … dann kann jeder sich auch sein Dashboard zusammenstellen. Wir können
  bestimmte Dashboards zusammenstellen und vorschlagen.“), which gives I35
  (the app's organisation) its shape and answers I47's open question (the
  screen is a view; how its layout is edited); the owner's picks on the
  idea board `design-language/mockups/ux-design-2026-11-21-idea-i56/`:
  navigation A (board 02, „Ja A finde ich super“), the period A (board 05,
  „Ja“), the width classes and compact forms (board 06).
- **Builds on:** [ADR-0001](0001-modular-phoenix-monolith.html) (one
  context per domain, the web layer apart);
  [ADR-0002](0002-thin-mcp-over-json-api.html) (one integration contract);
  [ADR-0017](0017-append-only-audit-journal.html) (every stored write journaled);
  [ADR-0022](0022-task-oriented-information-architecture.html) (the
  navigation, amended on the same PR for this record); the existing reads
  each widget draws, and the computation basis every metric payload
  already carries (`AGENTS.md`, "Every metric … must state its computation
  basis").
- **Ladder:** none. A widget draws an answer the app already gives; it
  computes no new figure. A widget that would need a new figure needs that
  figure's own decision first.
- Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), §13
  lists each ask as answered or deferred.

## Context

The owner found the app overloaded (I35, 2026-11-10): Wealth carries seven
tabs and its Holdings tab nine sections, and functions the owner values sit
where they are not found — the drift table in the second tab, snapshots in
the fourth, the crash comparison in the sixth (2026-11-21). Moving them
inside today's structure would hide something else. The owner's answer was
a change of structure: every function a widget, and the screens composed
from widgets, by the project as curated dashboards and by the operator as
their own. The same unit should later carry into native widgets on a phone,
a desktop or a wall (I53, step 3), so it must not depend on the browser.

Each function already has a read: the API and MCP give an agent every
figure a screen shows (`AGENTS.md`, "Coverage runs both ways"). What is
missing is a shared unit for the screen, a stored arrangement of those
units, and a rule for how the arrangement adapts to the screen it is on.

## Decision

### 1. A widget is one registered read, drawn in fixed sizes

A **widget kind** is registered once, in code, in a context
(`Portfolixir.Dashboards`, the name the context's conventions give), and
holds:

- `kind`: a stable string key (`"total_value"`, `"performance"`,
  `"movers"`, …). Keys are matched against the registered list as strings;
  **no atom is ever made from a stored or sent key** (`AGENTS.md`).
- `title` (translated on the screen), `group` (the catalogue's topic,
  board 01's table).
- `sizes`: the subset of **S** (3 columns × 1 row), **W** (6 × 1), **M**
  (6 × 2), **T** (4 × 3), **L** (8 × 3) and **full** (its own page, reached
  through „Ganze Ansicht“) it supports.
- `source`: the **one existing read** it draws — its `/api/v1` route and the
  context function behind it. The widget shows that read's figures; a test
  per kind compares every figure the widget draws with the route's answer
  for the same scope and period.
- `period`: `none`, or the periods it supports and how a period it does not
  support is translated (§5).
- `scope`: whether it takes a view (all of today's portfolio reads do).

The widget's **basis** is the source's basis: its ⓘ shows the payload's
computation basis, as every metric's ⓘ does today. A widget carries no
figure of its own and no verdict word (`metrics_carry_no_verdict_test.exs`
walks the widget catalogue's payload too).

Every widget has a **compact form** for the compact width class (§6): its
own narrow layout at phone type, not the wide widget made narrower (board
06; the first draw of board 04 showed why). A kind is registered only with
its compact form.

**The catalogue** is the registry read: `GET /api/v1/widgets` lists every
kind with its title key, group, sizes, source route, period rule and scope,
so an agent can compose a dashboard without reading the code (§8).

### 2. A dashboard is a stored layout, journaled

A **dashboard** is a row: `name` (1 to 60 characters, trimmed, no control
characters), `position` (its place in the menu), `layout`, `lock_version`.
The `layout` is an ordered list of at most **40 items**; each item names a
registered `kind`, a supported `size`, its `col` (1 to 12) and `row`
(1 or more) on the wide grid, and optional `settings`: `view_id` (a view
that exists, overriding the dashboard's scope for this widget) and
`period` (a pin, §5). At most **50 dashboards**.

- **Validated on write**, refused with 422 naming the first bad item: an
  unknown kind, a size the kind lacks, a position off the grid, two items
  overlapping, a `view_id` that does not exist, a pinned period the kind
  does not take. Nothing is repaired silently.
- **Journaled** (ADR-0017): one entry per stored write (create, replace,
  rename, reorder, delete) with the actor, as every write is. The edit mode
  (§7) saves once, on „Fertig“, so a drag is not a journal entry.
- **Concurrent writes**: a replace carries the `lock_version` it read; a
  stale one is refused with 409 and the stored layout, so neither the
  operator's edit nor the agent's is lost unseen.
- A deleted view leaves an item's `view_id` dangling: the widget then reads
  the dashboard's scope and says so on its footer; the next save drops the
  stale id. No cascade rewrites a layout.
- A dashboard holds **no figure**: it is arrangement, not data. It is not
  part of the ledger, not exported with it, and no money read depends on it.

### 3. Curated templates ship read-only

The project ships **templates**, defined in code and versioned with the
release: „Überblick“, „Performance“, „Allokation & Drift“, „Risiko &
Crashes“, „Einkommen & Steuer“ (board 03), each a layout over registered
kinds. A template is never stored and never edited; „Anpassen“ copies it
into a stored dashboard, which is then the operator's. A template names
only kinds that exist in its release; a template whose kinds are not all
built yet is not offered (Sprint 31 ships „Überblick“ only, §12).

**A fresh instance stores nothing.** With no stored dashboard, the first
menu entry shows the template „Überblick“ read-only, with „Anpassen“; a
read never writes.

### 4. The grid

The wide grid has **12 columns** and a row unit (board 03). Items are placed
by their `col` and `row`; the server stores what it was sent and refuses an
overlap (§2) rather than moving anything. The **reading order** of a layout
is by `row`, then `col`: it is the order the compact and medium layouts use
(§6) and the order a screen reader meets the widgets.

### 5. One period above every dashboard; a widget may pin its own

- **One period selector** in the dashboard's top bar (1T, 1W, 1M, 3M, YTD,
  1J, 3J, Max), applying to every widget that takes a period. It is
  **remembered per browser**, as the theme and Wealth's period are today,
  and it **stays when the operator switches dashboards** (board 05). The
  address carries it as `period=` when it is not the default, so a link can
  open a dashboard on a period. The default is today's Wealth default, 1J.
- A widget **follows** the selector and says so quietly („folgt · 3M“).
- A widget may **pin** its own period in its ⋯ menu; the pin is stored in
  the item's `settings`. A pinned widget is marked in the accent („📌
  eigener: Max“) so a pinned figure is never read as the selector's.
- A widget that **lacks** the selected period shows its nearest supported
  one, by a rule its kind states, and says so („3M → Quartal“): tops and
  flops (ADR-0061's windows) map 1T to Tag, 1W to Woche, 1M to Monat, 3M to
  Quartal, YTD to YTD, 1J, 3J and Max to 1J. A widget with no period says
  „ohne Zeitraum“ (the cycle chart, the crash list, data quality).
- *Why not a period per widget only (B):* a period change would be one
  click per widget, and dashboards would drift apart; *why not one per
  dashboard (C):* switching dashboards would jump the period, which the
  owner asked not to happen (2026-11-21).

### 6. The available width picks the layout, never the device

| Class | Available width | Layout |
|---|---|---|
| **compact** | under 600 pt | one column of compact forms in reading order; a bottom tab bar; the period as a swipeable strip |
| **medium** | 600 to 1000 pt | two columns of compact forms, the reading order filled column by column; a chart may span two cards' height |
| **wide** | from 1000 pt | the 12-column grid of §4 with the sidebar |

A window wider than tall whose height is short (an unfolded folding phone,
a phone turned sideways, a split tablet screen) turns the bottom tab bar
into a side rail and moves the period strip into the top bar (the owner's
question of 2026-11-21). The class is chosen in CSS from the window's width
and height; **no device or user agent is ever detected**. A new device
falls into a class by its size. Type in the compact forms: text 15 to 17
pt, figures 22 to 30 pt, nothing under 12 pt, tap rows at least 44 pt; the
owner found board 06's type large, which is taken for a drawing effect and
checked on a real phone in the UAT, not fixed on the board.

### 7. The edit mode

„Bearbeiten“ switches the dashboard into its edit mode (board 03): each
widget has a handle, a size switch with the sizes its kind supports, and ×;
the catalogue opens beside the grid to add a widget; „Zurücksetzen“
discards the unsaved edit, „Fertig“ saves it as one write (§2). Every
action has a keyboard path (move with the arrow keys, size with the
switch's buttons, remove with Delete), announced to a screen reader. The
edit mode is available in the wide and medium classes; in the compact class
it offers reorder, size and remove, not placement on the grid. A template
has no edit mode; „Anpassen“ copies it first.

### 8. API and MCP

- `GET /api/v1/widgets`: the catalogue (§1).
- `GET /api/v1/dashboards` (the stored dashboards and the offered
  templates, each marked), `GET /api/v1/dashboards/:id`,
  `POST /api/v1/dashboards` (create, or copy a template by its key),
  `PUT /api/v1/dashboards/:id` (replace name and layout, with
  `lock_version`), `PATCH /api/v1/dashboards/:id` (rename, reposition),
  `DELETE /api/v1/dashboards/:id` (with `dry_run`, as the cascading deletes
  have: a dashboard deletes nothing else, and the dry run says so).
- MCP: `portfolixir.dashboards.list`, `portfolixir.dashboards.get` (the
  layout with each item's source route, so the agent can read what a widget
  shows), `portfolixir.dashboards.put` (create or replace) and
  `portfolixir.dashboards.delete`, within the companion's schema budget;
  the catalogue is part of `list`'s answer, not a fifth tool.
- **The agent composes, the operator looks** (I47): „stell mir ein
  Dashboard für kurzfristige Bewegungen zusammen“ is one `put`. A dashboard
  an agent wrote is journaled under its token's actor and is the operator's
  like any other.

### 9. Navigation

ADR-0022's areas give way to dashboards (its amendment of 2026-11-21, on
this PR): the menu lists the dashboards first, then „Entdecken“, then
„Pflege“. A screen whose sections are not yet widgets stays a page under
„Entdecken“ until its pass turns it into widgets; it then leaves the menu
and stays reachable as the full view of its widgets.

### 10. Not this record

- **Native apps and native widgets** (I53, step 3): the widget contract and
  the API are what they would read; building them is a plan's decision and
  a repository of its own.
- **Live updates** of a widget between reads: a widget reads when the page
  loads, when the period or scope changes, and when the operator returns to
  the tab, as the cards do today.
- **Free placement** beyond the grid: rejected (board 01), so a layout
  adapts to every width.
- **A new figure** for a widget: each needs its own record.

### 11. Security

The layout is input from the screen and from the API: bounded (§2), its
keys matched as strings, its `name` escaped wherever it is drawn, never
interpreted as HTML or as a route. A widget's `source` is the registry's,
never the layout's: a stored layout cannot make the server read an
arbitrary route. The dashboard routes take the API's bearer token like every
write.

### 12. The first slice (Sprint 31)

The dashboard page, the registry, the storage, the API and MCP, the period
selector with its pins, the edit mode, the three width classes and the
transitional menu; the widgets of today's Overview (Gesamtwert,
Datenqualität, Fällig, Abseits des Ziels, Tops und Flops, Bitcoin-Zyklus,
Verkaufsrückblick) and the four the owner named hidden or most read
(Wertentwicklung, Allokation und Drift, Snapshots, Crashes im Vergleich);
the template „Überblick“. The Overview's route `/` becomes the first
dashboard. Wealth, Securities, Cash flow, Tax, Risk, Predictions and News
stay pages under „Entdecken“ until their passes.

### 13. The asks, answered and deferred (ADR-0043)

| Ask | Answer |
|---|---|
| Navigation: dashboards as the menu, or beside today's areas | **Answered**: dashboards as the menu (board 02 A, the owner) |
| The period per widget, per dashboard or above all | **Answered**: above all, a widget may pin (§5; board 05 A, the owner) |
| Phone layout | **Answered**: compact forms, chosen by width (§6; board 06) |
| Where a layout is stored | **Answered**: on the server, journaled (§2), so it follows the operator and the agent can write it |
| Edit as an area or a mode (I47's open question) | **Answered**: a mode (§7) |
| Which templates ship | **Answered**: five, each offered once its kinds exist (§3) |
| One layout per device class | **Deferred**: one layout, adapted by width (§6); reopens if a compact order is wanted that differs from the wide one, filed as its own issue after the merge |
| The period stored on the server, so it follows across devices | **Deferred**: per browser, as the theme (§5); reopens on the owner's ask, filed after the merge |
| Native widgets and apps | **Deferred** to I53 step 3, its own plan decision (§10) |
| A data-quality hint for stored closes of 0 or below (#1473's companion) | **Deferred** to the Datenqualität widget's pass in Sprint 32, so the hint is drawn once, in the widget |

## Consequences

- The screens are rebuilt screen by screen, each pass boarded first and
  each turning one screen's sections into widgets; no screen is redesigned
  twice, because the widget is the unit from the first pass on.
- A new user-visible function lands as a widget kind with its compact form
  and its source read; "where does it go" is answered by the templates and
  the operator's own dashboards, not by a new menu entry.
- The coverage rule holds as written: the source read is the agent's, the
  widget the human's view of it.
- The docs' screenshots and the user documentation follow the passes (I36,
  I37, I52), after the screens settle.

## Choices and how to flip them

| Choice | Flip phrase |
|---|---|
| Dashboards are the menu (§9) | „Bereiche behalten“ (board 02 B) |
| One period above all, pins allowed (§5) | „Zeitraum je Widget“ (B) or „Zeitraum je Dashboard“ (C) |
| The period remembered per browser | „Zeitraum auf dem Server“ |
| The grid of fixed sizes (§4) | „Freie Anordnung“ (reopens §10) |
| Width classes at 600 and 1000 pt (§6) | the two numbers, named |
| Templates read-only, copied to change (§3) | „Vorlagen bearbeitbar“ |
| Edit in the compact class without placement (§7) | „Bearbeiten nur am großen Bildschirm“ |

## Amendment: the others make room, the tabs ship as dashboards, the periods are the operator's (2026-11-25, Sprint 32 planning; ideas I57 to I59, I61)

Adopted by the merge of the Sprint 32 planning PR. It answers the owner's
review of the first slice (2026-11-25): a resize that is refused with a
message far from the click („was muss ich machen, die löschen? Das ist doch
quatsch“), a „Gesamtwert“ at M that reads cluttered, a first dashboard that
does not look like the screens it replaces („das sieht scheiße aus. Total
unübersichtlich“), a „Neues Dashboard“ with nothing to choose from, and
periods too few and too fixed. The boards are
`design-language/mockups/ux-design-2026-11-25-sprint32/` 01 to 05.

1. **§7, the edit mode: the others make room** (I58; board 01 A). A resize,
   a move or an add always succeeds while the layout holds fewer than 40
   widgets and a place exists up to row 200. The widget acted on keeps the
   place it was given; every widget it would cover moves down to the first
   row below it, in reading order, and so on for every widget that one
   move covers; then every widget, in reading order, floats up as far as
   no other widget stops it. The arrangement is a pure function of the
   layout and the action, computed by the context
   (`Portfolixir.Dashboards`), so the screen, a test and an agent get the
   same answer. **Feedback stands at the widget acted on**, announced to a
   screen reader, with „Rückgängig“ for that one step (and Ctrl+Z);
   „Zurücksetzen“ still discards the whole edit. The two refusals left (the
   41st widget, no row left) stand there too. *Why:* the operator expects
   to tidy up after a change, not to delete something first; a message at
   the top of a long page answers a click the operator can no longer see.
   *Note of 2026-11-25 (Sprint 32, E1): the wording above and board 01 ②
   differ, and the board is built.* „Moves down to the first row below it“
   would put „Datenqualität“, „Fällig“ and „Abseits“ under the grown
   „Gesamtwert“; the board, signed with this amendment, moves them into the
   free cells beside it. `Portfolixir.Dashboards.Arrange` follows the board:
   a covered widget moves to the first free place after its own in reading
   order (on along its row, then the rows below), and so on; then the gaps
   close. Every other clause stands. *Why the board:* it is the picture the
   owner chose, and it leaves fewer widgets moved. Flipped by „nur nach
   unten schieben“.
2. **§2, the API stays strict.** A stored write is still refused with 422
   on an overlap and nothing is repaired silently; the edit mode sends a
   layout it has already arranged. An agent that wants the arrangement
   sends `arrange: "push"` with the item it changed on `PUT`, and the
   server applies rule 1 before it validates; without it, an overlap is
   still refused. *Why:* a write that moves what it was not asked to move
   would surprise an agent that composed a layout on purpose.
3. **§1, sizes: one more, and one rule** (I57, I58; boards 01 ④, 02 ③).
   - **„Zeile“** (`row`): the full width, as tall as its content. It is
     12 columns by 1 row in the stored grid, so validation, the
     arrangement of rule 1 and the API treat it as any item; it is drawn
     at its content's height, and every row after it starts below it. It
     is the size of a **section widget**: a widget that draws one section
     of today's screens as the screen draws it, from the read that section
     reads today (§1's one existing read). Its compact form is the narrow
     layout that section already has.
   - **The grid sizes are Apple's widget families** (WidgetKit; board 09,
     the owner's question of 2026-11-25): one square unit, every size a
     multiple of it, **every size of a fixed height**: **S** (small, 3
     columns × 2 rows, about 240 × 236 px at the wide class), **M** (medium,
     6 × 2), **L** (large, 6 × 4), **XL** (extra large, 12 × 4). A row is a
     fixed 7 rem; no row grows with its content, so a widget draws its own
     layout per size and shows what fits (the top rows, „Alle anzeigen“),
     as Apple asks of a widget. Stored layouts are read with S as S, W as M,
     M as L, T as L, L as XL, the rows doubled, and are arranged by rule 1
     on their next save. In the compact class two S stand side by side and
     M, L and XL take the full width, as on a phone's home screen; native
     widgets (I53) take the same families. *Why:* today's sizes follow the
     pattern only half (S is not square, L and T are no multiple of S, no
     size has a fixed height), which leaves empty columns, ragged rows and
     an S widget 593 px tall (boards 08, 09).
   - **Each size shows more of the same, never something else.** S one
     figure, M the figure with two or three companions, L the figure with
     its course, XL the figure, its course and a breakdown. A size that
     adds nothing readable is not offered. „Gesamtwert“ takes S, M and L
     by this rule (board 01 ④ draws them as S, W and M, today's names);
     Sprint 32 checks every registered kind against it.
4. **§2, a dashboard may hold a scope of its own** (I61; board 03 ②):
   an optional `view_id`, validated as an item's is, read before the
   address's scope and the default view, overridden by an item's own. A
   deleted view leaves it dangling as an item's does, read as the default
   and said in the top bar. A dashboard also records the `template_key` it
   was copied from, if any, which reads nothing and only answers „where
   did this come from“.
5. **§3, the starter dashboards and the gallery** (I57, I61; boards 02 A,
   03). The paragraph „A fresh instance stores nothing“ is replaced:
   - **Each template marked as a starter is stored once**, on the first
     start of the release that brings it, by a boot task under the system
     actor (`Actor.system_job/1`), journaled, and recorded in a seed table
     by its key, so a starter the operator deleted is never stored again.
     From then on it is a dashboard like any other: renamed, changed,
     reordered, deleted. An instance that already stores a dashboard counts
     „Überblick“ as seeded. A read still never writes.
   - The starters are today's screens: „Überblick“ and, as their passes
     land, „Bestände“, „Allokation & Ziele“, „Snapshots“, „Risiko“
     (Sprint 32), „Cashflow“, „Steuer“, „Prognosen“ (the next widget pass), each its
     screen's sections as section widgets in the screen's order.
   - **„Neues Dashboard“ opens a gallery**: „Leer“, the starters, then the
     themes, each with its grid in miniature and its widgets; a click asks
     for the name and, for a template that names one, a scope. The themes
     in Sprint 32 are „Krypto Lover“ and the template for falls (its name
     the owner's answer: „Buy The Dip“ or another; its two new kinds draw
     ADR-0058's windows, rankings and the stored closes, no new figure); „Performance“ and
     „Einkommen & Steuer“ follow with their widgets. A template is
     offered only when all its kinds exist, as before.
   - *Why:* the owner wants the screens kept as they are, as dashboards
     that can be changed piece by piece, and to start a new one from
     something; a starter shown but not stored (board 02 B) would need a
     second memory for „deleted“.
6. **§5, the periods** (I59; board 04 A).
   - **The vocabulary** is one module (`Portfolixir.Periods`), resolved
     against `Clock.today()` into the terms the reads already take (a
     fixed key or `{:range, from, to}`): rolling `1d 1w 1m 3m 6m 1y 3y 5y
     max`; calendar `mtd` (this month), `prev_month`, `qtd` (this quarter),
     `prev_quarter`, `q1` to `q4` of the current year (a quarter not yet
     begun is refused, not read as empty), `ytd`, `prev_year`, `year:YYYY`;
     and `saved:<id>`, a stored period by reference. Every route that takes
     `period=` through `PeriodParam` accepts the same keys; `from` and `to`
     keep their precedence.
   - **Saved periods are stored on the server**: a name (1 to 40
     characters, trimmed, no control characters), `from`, and `to` or
     „until today“; at most 50; journaled; read and written over
     `/api/v1/periods` and the MCP companion. A pin may name one by
     reference, so a change to the period reaches every widget pinned to
     it; a deleted one leaves the pin dangling, read as the top bar's
     period and said in the widget's footer, as a deleted view is.
   - **The quick choice** in the top bar is the operator's: up to six keys,
     stored on the server, defaulting to `1w mtd ytd 1y max`; the rest sits
     behind one button that opens the menu (rolling, calendar, year, own).
   - **The active period stays per browser** and in the address, as
     before; what follows across devices is the vocabulary the operator
     built. This answers #1482 („the period stored on the server“) in that
     shape.
   - A widget that lacks a calendar period translates it by its stated
     rule (tops and flops: `mtd` and `prev_month` to Monat, `qtd`,
     `prev_quarter` and `q1` to `q4` to Quartal, `prev_year` and
     `year:YYYY` to 1J) and says so, as §5 already orders.
7. **§9, Wealth leaves the menu** when all seven of its tabs are starters
   (the next widget pass); until then the tabs not yet passed stay pages under
   „Entdecken“. A section's write form does not move into its widget: the
   widget links to the page that holds it (ADR-0022's amendment of
   2026-11-21, point 3).
8. **The asks** (ADR-0043):

   | Ask | Answer |
   |---|---|
   | Refuse an overlap, push down, or push down and close the gaps | **Answered**: push down and close the gaps (1), the API strict unless asked (2) |
   | Where a refusal stands | **Answered**: at the widget (1) |
   | How a section of today's screens becomes a widget | **Answered**: a section widget in the size „Zeile“ (3) |
   | Do the sizes follow Apple's recommendations | **Answered**: they become Apple's families S, M, L, XL with fixed heights (3; board 09) |
   | Starters stored once, or shown until changed | **Answered**: stored once, with a seed record (5) |
   | Which periods, and in what menu | **Answered**: the vocabulary, the quick choice and the menu (6) |
   | The period on the server (#1482) | **Answered** in the shape of 6: own periods and the quick choice on the server, the active period per browser |
   | The name of the theme „Buy The Dip“ | **The owner's**: a shipped name that says „buy“ may read as advice (`AGENTS.md`, permanent non-goals). Recommended „Rücksetzer“; flipped by „Buy The Dip heißt Buy The Dip“ |
   | The monthly-return heatmap and the trading activity (I60) | **Deferred** to the next widget pass's planning PR: both are new figures (§10), each with its decision record (ADR-0063) |

**Choices and how to flip them** (added to the table above):

| Choice | Flip phrase |
|---|---|
| The others make room, gaps closed (1) | „Lücken stehen lassen“ (board 01 B) or „Überlappung verweigern“ |
| The API arranges only when asked (2) | „API ordnet immer“ |
| Starters stored once (5) | „Start-Dashboards erst beim Ändern speichern“ (board 02 B) |
| A quick choice and a menu (6) | „alle Tasten zeigen“ (board 04 B) |
| Apple's families with fixed heights (3) | „Größen wie bisher“ |
| The active period per browser (6) | „aktiver Zeitraum auf dem Server“ |
| „Rücksetzer“ (8) | „Buy The Dip heißt Buy The Dip“ |
