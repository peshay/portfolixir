---
layout: docs
title: "ADR-0022: Task-oriented UI information architecture"
description: Consolidate the navigation from nine issue-grown destinations into five task-oriented areas, and make the target IA the guardrail for where future stories land.
---

# ADR-0022: Task-oriented UI information architecture

- **Status:** Accepted
- **Date:** 2026-07-03

## Context

The web UI grew story by story. Each feature landed where its issue met the
least resistance, and no reviewed artifact ever defined the whole. The result
(reviewed by the owner, 2026-07-03):

- **Nine navigation destinations in six groups**, organised by developer
  categories ("Master data", "Tools") rather than user tasks, plus two
  disabled "Soon" placeholders (Watchlist, Returns & risk).
- **"Portfolio" vs "Portfolios"** as sibling top-level entries — one is the
  holdings/analytics view, the other is account/depot administration. The
  labels are indistinguishable to a user.
- **Analytics are scattered:** the income report sits alone under "Reports",
  the target/actual drift breakdown lives inside the Classifications pages,
  and returns/risk exists only as an API endpoint plus a nav placeholder.
- **Imports sit under "Tools"**, although importing is just the bulk way of
  recording transactions — the same user task as manual entry.
- **Buckets & views is a top-level destination**, although views are already a
  global, cross-page scope (session + cookie via `ViewScope`); the page itself
  is rarely-visited configuration.
- **Two chart implementations:** `security_chart.ex` is a reusable component;
  `portfolio_live.ex` renders its own, visibly weaker SVG chart.
- **The dashboard does not answer a question.** Its recent-activity feed
  restates the audit journal without telling the maintainer whether anything
  needs attention.

The scope-lock rule in AGENTS.md worked as designed — agents never touched
anything cross-cutting — which is precisely why no one owned the whole. This
ADR creates the missing artifact.

## Decision

Restructure the UI into **five task-oriented areas**:

| Area | Route | Contains |
| --- | --- | --- |
| **Overview** | `/` | Dashboard: current value + change, data quality, attention items (see below) |
| **Wealth** | `/portfolio` | Tabs: **Holdings** · **Allocation & targets** · **Income** · **Returns & risk** (when built) |
| **Securities** | `/securities` | List + detail (chart, quotes). Watchlist arrives as a filter/tab, not a nav entry |
| **Transactions** | `/transactions` | History & manual entry · **Import** as a sub-page/tab (moves from "Tools") |
| **Administration** | — | **Accounts & depots** (today "Portfolios") · **Buckets & views** · **Classifications** |

Supporting decisions:

1. **Resolve the Portfolio/Portfolios collision by renaming.** The holdings
   view becomes **"Wealth"** (de: "Vermögen"); the administration page becomes
   **"Accounts & depots"** (de: "Konten & Depots") and moves into
   Administration.
2. **Consolidate analytics under Wealth.** The income report and the
   target/actual drift breakdown become Wealth tabs; the Classifications pages
   keep only tree/assignment administration. The view switcher heads the
   Wealth area, where it already applies. A separate "Reports" group returns
   only if a report ever exists that is not bound to wealth.
3. **Import is a way to record transactions, not a tool.** The "Tools" group
   disappears.
4. **Buckets and Classifications stay two concepts** (overlapping facets vs
   partition with targets — no data-model change), but both live in the
   low-traffic Administration group together with Accounts & depots. The
   per-classification tree leaves the sidebar.
5. **Remove disabled "Soon" placeholders from the navigation.** Roadmap lives
   in issues, not in the nav.
6. **One chart component.** `security_chart.ex` becomes the shared time-series
   chart; the portfolio/dashboard value charts use it, extended with
   context lines (e.g. invested capital) where the surface needs them.
7. **The dashboard answers "did anything change, does anything need me?"** —
   current value and change, data-quality card, and attention items (e.g.
   drift beyond threshold, import anomalies from the audit journal). The raw
   recent-activity feed is dropped; the audit journal remains the place for
   forensic detail.

**Guardrail for future work:** every story that adds or moves a user-visible
surface must name its target area per this table. A feature that fits no area
is a signal to discuss the IA, not to add a nav entry.

## Consequences

- Landed as **individual stories** (rename/regroup nav, move import, extract
  drift view into a Wealth tab, embed income, chart unification, dashboard
  content), each with tests per AGENTS.md — not as one big-bang PR. Stories
  touching the same files ship in one PR.
- Route churn is kept minimal: `/portfolio`, `/securities`, `/transactions`
  stay; tabs become query params or subroutes as each story decides.
- Renamed labels go through the gettext extraction + de translation gate.
- API and MCP are unaffected (navigation only), except where a story
  explicitly says otherwise.
- Docs screenshots and the EN/DE user documentation need a refresh pass as
  areas land.

## Amendment: the Audit journal joins Administration (2026-11-02, Sprint 23 V3; idea U2)

The Administration group gains a fourth entry, **Audit journal** (de:
„Audit-Journal“, `/journal`), after Classifications. It is the operator's
view of `GET /api/v1/journal`, which ADR-0017 named a follow-up of its
read surface.

*Why here:* the group holds the record-keeping pages, and the journal is
the record of every stored change. There is no Settings page to hang it
from, and a Transactions tab would claim the journal is about bookings
while it holds every kind of entry (board
`ux-design-2026-11-02-sprint23/03-journal`, pick Q6, adopted with the
Sprint 23 plan, D-5 and D-8). Decision 7 stands: the Overview keeps no
activity feed; the journal is the place for forensic detail, now with a
screen of its own.

## Amendment: News joins the top level, after Securities (2026-11-09, Sprint 28 N7; ADR-0056 §10)

The first group gains a sixth area, **News** (de: „Nachrichten“,
`/news`), after Securities, with the tabs **Reports** („Meldungen“: the
collector's health, the queue of unassigned and ambiguous items with the
one assign action, the digest per security), **Feeds** and **Sources**
(„Quellen“). It is the operator's view of the news reads ADR-0056 §9 gave
the agent, and §10 owed it by Sprint 28.

*Why a new area and not a place in an existing one:* the guardrail above
asks to discuss the IA first, and the Sprint 28 planning board did
(`ux-design-2026-11-08-sprint28/01`, plan D-5). Spread over
Administration and a filter on the securities list (variant B), the
digest — "what is new, and is the collector alive", the one question the
agent answers with one call — would have no place on screen. Variant A
was adopted with the plan; "News verteilt" flips it to B. A security's
own stories stay on its page, as a tab (Sprint 28 N8).

## Amendment: dashboards become the menu, maintenance moves to one quiet group (2026-11-21, Sprint 31 planning; ideas I56, I47, I35)

Adopted by the merge of the Sprint 31 planning PR, with
[ADR-0062](0062-widgets-and-composed-dashboards.html), which turns every
function into a widget and the screens into dashboards composed from
widgets. The table of areas above gives way to three groups (the owner's
pick of board 02 A, `ux-design-2026-11-21-idea-i56/02-navigation`,
2026-11-21: „Ja A finde ich super“):

| Group | Contains |
| --- | --- |
| **Dashboards** | the stored dashboards in their order, then „Neues Dashboard“; with none stored, the template „Überblick“ (ADR-0062 §3). The Overview's route `/` opens the first one |
| **Entdecken** („Discover“) | Securities (the list and each security's page), News, „Alle Widgets“ (the catalogue, ADR-0062 §1), and, **while their sections are not yet widgets**, the screens still built as pages: Wealth with its tabs (Cash flow, Snapshots, Tax, Risk and Predictions among them) |
| **Pflege** („Maintenance“), at the foot, quiet | Transactions with Import, Accounts & depots, Views, Classifications, the Audit journal |

1. **A screen leaves „Entdecken“ when its pass has turned its sections
   into widgets**: it stays reachable as the full view of its widgets
   („Ganze Ansicht“) and from „Alle Widgets“, but no longer as a menu
   entry. Wealth leaves last, since most widgets come from it.
2. **The guardrail is restated.** A story that adds a user-visible
   function names its widget kind and the template it joins, if any (ADR-
   0062 §1, §3); a page of its own needs a reason why the function cannot
   be a widget. A new menu entry is still a signal to discuss the IA.
3. **The screen is a view; the forms move to „Pflege“** (I47, the owner's
   „ja“ to OQ-2 of `owner-intake-2026-11-18.md`): no new write form lands
   on a reading screen; existing forms move into the maintenance group as
   their screens' passes reach them. What a human must still do on a
   screen stays: drop an import file, confirm a machine proposal (NFR-10),
   log in, the settings. The edit mode of a dashboard (ADR-0062 §7) is
   arrangement, not data, and stays on the dashboard.
4. **Decision 7 stands in its new form.** The template „Überblick“ answers
   "did anything change, does anything need me?" with the Overview's
   cards as widgets; the Overview keeps no activity feed.
5. **On a compact width** (ADR-0062 §6) the three groups become a tab bar:
   „Dashboards“ (with the dashboard switcher in the title), „Wertpapiere“,
   „Nachrichten“ and „Mehr“ (the rest of „Entdecken“ and „Pflege“).

*Why:* the areas were drawn when the app had five screens; with seven Wealth
tabs and nine Holdings sections, functions the owner values were found by
nobody (I35, 2026-11-10; 2026-11-21: the drift table, snapshots and the
crash comparison „versteckt“). Dashboards put a function where its reader
looks, and the maintenance pages, which the agent mostly does (I47), stop
taking the menu's top. **To flip:** „Bereiche behalten“ (board 02 B: the
areas stay, each tab a fixed dashboard, own dashboards beside them).
