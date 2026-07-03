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
