---
layout: docs
title: "ADR-0062: Every function a widget — dashboards composed from widgets, one period above them"
description: "Decision for idea I56 (FR-60). Every user-visible function becomes a registered widget: one existing read, drawn in fixed sizes, with its computation basis behind its ⓘ. The operator composes dashboards from widgets, stored on the server and journaled, so the agent can compose one too; curated templates ship read-only. One period above every dashboard, remembered per browser, which a widget follows until it pins its own. The available width picks one of three layouts, never the device. Built screen by screen, the Overview first."
---

# ADR-0062: Every function a widget — dashboards composed from widgets, one period above them

- **Status:** Accepted. Adopted by the merge of the Sprint 31 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
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
