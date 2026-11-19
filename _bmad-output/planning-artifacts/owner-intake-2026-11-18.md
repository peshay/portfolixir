# Owner Intake — 2026-11-18 (what Portfolixir is, the screens, the docs, the cycle chart)

Source: the owner's own notes, written down in one intake session on
2026-11-18, with two screenshots of the cycle chart on the security page.
This document sorts every point, checks it against the code on `main` at
`1dd7f24` and against the ADRs, the scope ladder and the non-goals, and says
where each point went. It is the triage the sprint workflow's "Ideas" asks
of an agent; nothing here is a decision record. The owner answers Part 3
before any of it becomes a plan.

**Privacy note.** The screenshots come from the owner's instance. They show
public market prices of a public security and no portfolio data, but no
figure from them is reproduced here; only the shape of each point is kept.
The owner's own tooling (a connected agent, the feeds, a separate labelling
agent, a parallel research project) is named generically.

Status: **answered.** OQ-5 on 2026-11-18; OQ-1 to OQ-4 on 2026-11-19:
OQ-1 and OQ-2 „ja“ (the recommendations); OQ-3 only if it looks great,
so the board decides by eye; OQ-4 wanted in the long run, but behind the
redesign.

---

## Part 0 — What governs the rest

1. **The owner set the direction of the next sprints: improve what exists,
   redesign the screens, rewrite the documentation.** No new feature is
   asked for; every point below is about what Portfolixir already has, how
   it reads, and how it presents itself. This is the same call as Sprint
   30's D-2 ("one feature, otherwise consolidation"), made for more than
   one sprint and with the design itself in scope. The next planning
   session takes it as its D-1 and proposes **I35** (tidy the app's
   organisation) as the idea that goes deep, ahead of I20, which the
   current order names first.
2. **Two points touch what Portfolixir is, so only the owner can settle
   them** (Part 3, OQ-1 and OQ-2): whether "self-hosted" is identity or
   only today's way to run it, and whether the screen becomes a view the
   human reads while the agent maintains the data. Both change the brief,
   the PRD's §1 and the first section of `AGENTS.md`, so they land as a
   reviewed PR, never as a code change.
3. **Most of the screen and documentation points already have a row.**
   I35 (the app's organisation), I36 (the features grouped on the site),
   I37 (screenshots in the site's theme), I19 (hosting, as a far vision),
   I20 and F32 (usage hints and prompts), P1 (a page for PP users), F13 and
   F17 (sync, generic CSV import). This intake adds the owner's new words
   to those rows and opens seven new ones (I46 to I52) only where nothing
   held the point.
4. **No point is an S1 or an S2.** The returned ⓘ fault on the cycle chart
   could not be reproduced in Chromium (Part 1, O13), so it is a polish
   line with one question to the owner (OQ-5), not an issue.

## Part 1 — Item by item

| # | The owner's point | What is true today | Kind | Where it went |
|---|---|---|---|---|
| O1 | Portfolixir grew out of Portfolio Performance plus a spreadsheet, and out of copying figures into a chat by hand for every question; PP's desktop app with a file synced to a phone was the other pain. It needs to run all the time somewhere and be reachable over MCP. | The brief and the PRD say this (brief 2026-08-12, "Problem"; PRD §1–2). | Product | Kept as the origin story; it is the strongest opening for the README and the site (I36). |
| O2 | "Self-hosted" was stated too hard. It does not have to be; offering it as a hosted service later is a wish, far off. It is a portfolio tracker like the others, with far more information. | "Self-hosted" is in the first sentence of the README, `docs/index.md`, `docs/features.md`, the brief (lines 22, 134), the PRD and `AGENTS.md`. I19's triage (2026-11-04) found that hosting **one instance per customer** keeps "one dataset, one instance, one operator, no tenancy" intact. | Product | **I46**, OQ-1. I19 keeps the hosting vision. |
| O3 | Data maintenance should be automatic. The owner never creates a security, a trade or a category on the screen; the agent does it all. Editing on the screen makes little sense; the UI is a view for the human. Data still has to come in, by automation rather than by hand. | The UI carries write forms on most screens: about two dozen LiveViews and dialogs with a `phx-submit` (securities, classifications, views, transactions, accounts, policy rules, splits, merges, logos, tax, imports). The coverage rule asks for a human **view** of each agent capability, not a human form (`AGENTS.md`, "API And MCP Coverage"). NFR-10 needs a human or an agent to confirm machine-extracted data. | Product, UI | **I47**, OQ-2. Feeds I35's inventory. |
| O4 | GitHub: the badges belong at the very top, as is usual. | The badges sit after "How your data gets in", below the tagline (README lines 46–53). | Docs | **I36**, its README part; a `no-brainer`. |
| O5 | GitHub: the intro, then "How your data gets in", then the badges, then a second intro — redundant. "What works today" still bothers the owner; the functions should be broken down instead. | The tagline paragraph (README 11–18) and "What is Portfolixir" (53–99) say the same twice; "What works today" (100–152) is a flat list of about forty lines. | Docs | **I36**: one intro, the feature groups replace "What works today". |
| O6 | Look at the competition's imports and offer imports from all of them; someone starting out may rather want a sync, to look at Portfolixir beside PP during a transition. | The import reads PP CSV and JSON v1; the `import_converter` prompt has the agent convert any other export. The competitive research of 2026-09-30 found that **no** tracker imports PP data and that import is the lock-in. A **complete PP XML import** is `gated` (an `AGENTS.md` amendment and an ADR); binary `.portfolio` intake is out of scope; bank and broker sync is F13, behind B3.3. | Feature, data | **I49**, OQ-4. |
| O7 | The documentation site lacks a clear structure of functions. Learn from Kugelblitz's features page, with far more images. | `docs/features.md` has seven sections and no image; the screenshots and the tour GIF are only in the README (I36's row). The reference page could not be fetched from this session (its host is not on the environment's network allowlist), so the board session reads it or the owner pastes it. | Docs | **I36**, with the reference and the image rule. |
| O8 | The UI is overloaded and not sorted: areas in the menu, then on every page many cards, charts and tables, and tabs on top. It all needs to be sorted anew, by function. | I35's row holds the owner's answer of 2026-11-10 and the inventory: seven Wealth tabs, nine sections on Holdings, ADR-0022's five areas. | UI | **I35**, now the next deep idea and the redesign's backbone. |
| O9 | Why do all cards carry a stripe at the top? Is there no better design? | `.stat::before` draws a 3 px gradient of the three logo colours over every stat card (`priv/static/app.css` ~1086). DESIGN.md calls it "the only moment all three logo colors coexist". | UI | **I48**, OQ-3. |
| O10 | The accent colours were a good idea at the start but no longer fit: gains had to be green and losses red, which clashes when teal or coral is the chosen accent. The owner would like to keep the three colours somehow, or find other places for the logo's colours, or leave them out. | Since 2026-11-03 `positive` and `danger` are aliases of the brand teal and coral (DESIGN.md, Colors). With the accent on teal, active navigation, chart lines and selected rows wear the gain colour; with coral, the loss colour. DESIGN.md's own "Avoid: using accent colors for gain/loss" is broken by its own aliases. DESIGN.md calls the accent switch "owner-loved, binding". | UI | **I48**, OQ-3. |
| O11 | News is new; make it less prominent as an official feature, or hide it while no agent fills it. For the agent it is decision input; for the human it disappoints: messy, items without a label. It should become a news page where the human reads into current topics with the relevance already rated. | News has its own menu entry under the primary areas (`app_shell.ex`, `/news`). ADR-0056 has items labelled outside the app, so an unlabelled item is the normal state until the agent runs. I35's row already holds the owner's principle of 2026-11-10: hide a function while it holds no data. | UI, app page | **I50**. Hiding follows I35's rule; the reading page needs a board. |
| O12 | In parallel, the owner works on a separate project that tries to predict from news and price data. | Outside this repository. A prediction made elsewhere can be recorded through ADR-0055's predictions and scored for calibration (level (c)); Portfolixir itself makes none (no advice, no in-app model). | Outside | No row. Noted in I50 as the way such a project's output would meet the app. |
| O13 | The new Bitcoin chart is poor: reached only by clicking through the securities list, then many switches; text and legends hard to read; the table under it is not understandable (every cell says something different: ×2.4, −87 %, "provisional", what is n?). And the ⓘ fault is back: it does not close by itself, and a second ⓘ opens a second panel. | The Overview has a cycle card with "Open in chart →" (Sprint 29 H8), but the owner did not find it, so it does not work as the way in. The chart needs Max, then „Zyklen“, then per-line switches. The screenshots show labels crossed by the band lines and the trend line, and the anchor marker inside its own label. The intervals table mixes days with a factor in one row and days with a drawdown in another, and marks cells „vorläufig“ and „Teil“ with n in its own column. **The ⓘ:** reproduced in Chromium at 1400 px on the synthetic cycle coin of `cycle_chart_test.exs` (four ⓘ on the cycle section): one opens at a time, a click elsewhere closes it, the second click closes the first. So the fault is not in the shared script as Chromium runs it; the browser gate runs Chromium only, and which browser the owner used is not known (OQ-5). | UI | **I51** (the rework, a board first). Two lines on the polish lists: the label overlaps on #1365, the ⓘ report on #1357, with OQ-5. |
| O14 | The next sprints should optimise the existing features and rework the design, including the documentation: more images or short, calm GIFs. | See Part 0.1. I37 (screenshots per theme) and `priv/demo/screenshots.mjs` exist; the README has one tour GIF. | Process | The next planning session's D-1; I36, I37. |
| O15 | Recommend prompts: show a portfolio being imported, then a prompt ("sort my securities on two levels, think of fitting strategies and categories under them, assign the securities, check today's distribution, propose a new weighting and enter it all in Portfolixir"); the agent works, and the human sees the allocation and the drift — the actual state categorised, and a target to work towards. So users see how easily data gains meaning. | The MCP companion has two prompts (`first_setup`, `import_converter`, `mcp-server/src/prompts.ts`); F32 asks for more; `docs/features.md` has "Prompts that carry the no-advice stance". Target weights with drift and display-only rebalancing hints exist (ADR-0023). | Docs, feature | **I52**. |

## Part 2 — A sequence to propose (no decision needed now)

The next planning session decides; this is the order the points suggest,
because each step feeds the next.

1. **Foundations, on boards.** The inventory I35 asks for (every screen,
   section, tab and menu entry, which have data on a fresh instance and on
   the demo seed, clicks to each function), written by an agent with no
   owner time. Then one board for the colour system and the card (I48,
   after OQ-3) and one board for the new navigation (I35, after OQ-2,
   since a view-first screen sorts differently from a form-first one).
   The README's two `no-brainer` moves (badges on top, one intro) can ride
   along.
2. **The screens.** Wealth first, as I35's row says; the news page (I50)
   and the cycle chart (I51) as their own boards in the same pass, since
   both are recent and both were reported as unreadable.
3. **The documentation.** The site's feature groups mirror the new
   navigation (I36), with screenshots per theme (I37), a few calm GIFs, and
   the prompt walkthrough (I52) as the first guided example. Done last on
   purpose: screenshots of screens about to change would be redone.
4. **Imports (I49)** after the redesign: a research step on what the other
   trackers export first, then a decision on the transition path.

## Part 3 — The owner's questions

Each has a recommendation; the phrase after it flips the answer.

**The owner's answers, 2026-11-19:**

- **OQ-1: „ja“.** The recommendation stands; I46 is `worked-out`. The
  next planning PR rewords the brief, the PRD §1 and `AGENTS.md` together
  with I36's README, so the identity sentence is written once.
- **OQ-2: „ja“.** The recommendation stands; I47 is `worked-out`. Whether
  the maintenance place is an area of its own or an edit mode is drawn on
  I35's board; the planning PR amends ADR-0022 and the coverage rule's
  wording.
- **OQ-3: unsure, „nur wenn es geil aussieht“.** Nothing is decided
  ahead of the look. I48's board shows today's accent switch and the
  one-meaning-per-colour proposal side by side, light and dark, with and
  without the card stripe; the owner picks by eye, and if the new look
  does not convince, the accent switch stays. I48 is `discussing`.
- **OQ-4: solutions wanted in the long run, but later.** I49 waits behind
  the redesign sprints, the agent-run MCP prompt included; it stays
  `triaged` and last in the order.

- **OQ-1 — Is "self-hosted" identity?** *Recommended:* no. Identity
  becomes "your portfolio, always on and reachable by your agent; one
  dataset, one instance, one operator, no tenancy". Self-hosting is how it
  runs today; a hosted instance per customer stays I19's far vision and is
  not built ahead. The README, the site, the brief, the PRD §1 and
  `AGENTS.md` are reworded in one reviewed PR. *Flip:* „self-hosted
  bleibt Identität“.
- **OQ-2 — Is the screen a view?** *Recommended:* "the agent maintains,
  the human reads and confirms". New features ship no write form on the
  screen (API and MCP write, the screen reads). Existing forms are not
  deleted in one go: the I35 rework moves them out of the reading screens
  into one maintenance place, and keeps on the screen only what a human
  must do there — dropping an import file, confirming a machine proposal
  (NFR-10), the login, the settings. Needs ADR-0022 amended and the
  coverage rule's wording made explicit. *Flip:* „Formulare ganz raus“
  (remove them), or „Formulare bleiben, wo sie sind“.
- **OQ-3 — The three colours.** *Recommended:* drop the accent switch and
  give each logo colour one meaning: **violet** for everything you can
  click or select (navigation, focus, chart lines, the brand), **teal**
  for up, **coral** for down — which they already are. The logo's three
  colours stay, each with one job, and no choice can clash with gain or
  loss. The card stripe goes; cards get a calm surface without a coloured
  edge, and the gradient stays in the logo. A board first. *Flip:*
  „Akzent-Schalter behalten“, or „klassisches Grün/Rot für Gewinn und
  Verlust“.
- **OQ-4 — A transition path from every competing tool, not only PP.**
  *The owner, 2026-11-18:* the import and the transition sync are meant
  for every tool a newcomer may come from (Ghostfolio and the others), not
  only Portfolio Performance. Two routes with different gates: a **file**
  the old tool exports, read by the import (allowed today; a new format is
  a story), and a **continuous read** of the old tool's API or file during
  a transition (data acquisition beyond quotes and FX, gated by B3.3; for
  PP's XML also the `gated` PP-XML row). *Recommended:* first the research
  of which tools export transactions as a file and which offer a read API
  (I49's first step), then one ADR for the transition route, after the
  redesign sprints. *Flip:* „Übergangs-Sync jetzt angehen“, which needs
  that ADR and an `AGENTS.md` amendment in a planning PR.
  **Refined the same day by Part 5's research:** a third route needs no
  gate at all. The operator's agent reads the old tool (Ghostfolio's API,
  Parqet's MCP server and API, PP's export) and books into Portfolixir
  over its own API, as the `import_converter` prompt already does for
  files; Portfolixir stores no token of the old tool and calls no other
  service. *Recommended:* this agent-run transition as an MCP prompt
  (F32, I52's companion), the in-app sync stays gated. (The owner put
  I49 behind the redesign on 2026-11-19, the prompt included.)
- **OQ-5 — The ⓘ fault: which browser, and where?** *Answered by the
  owner, 2026-11-18:* Safari; on a later look the fault was gone, without
  a known cause. With the Chromium non-reproduction, the polish line on
  #1357 is closed as not reproducible; it reopens with steps if Safari
  shows it again. A stale page from before a deploy (an old script with a
  newer server) is one possible cause, not a confirmed one.

## Part 4 — Where each item went (2026-11-18)

- **New rows in the idea list:** I46 (identity wording), I47 (the screen
  as a view), I48 (the colour system and the card), I49 (imports from
  other trackers and a transition path), I50 (news as a reading page),
  I51 (the cycle chart, reworked), I52 (the prompt walkthrough). All
  `triaged`.
- **Rows updated with the owner's words of 2026-11-18:** I35 (the next
  deep idea), I36 (the README, the reference page, the images), I19
  (pointer to I46).
- **Polish lines:** on [#1365](https://github.com/peshay/portfolixir/issues/1365),
  the cycle chart's label overlaps seen on the owner's screenshots; on
  [#1357](https://github.com/peshay/portfolixir/issues/1357), the ⓘ
  report with its Chromium non-reproduction, ticked as not reproducible
  after the owner's answer to OQ-5.
- **The recommended order** in the idea list now names I35 first.
- **An S1 found on the way, not this intake's:** CI's `advisories` job
  turned red on a new `plug` advisory (EEF-CVE-2026-120287); filed as
  [#1469](https://github.com/peshay/portfolixir/issues/1469).

## Part 5 — Why switch: what the field looks like on 2026-11-18

The owner asked what Portfolixir does better than its competitors and why
anyone would switch. This updates the competitive research of 2026-09-30
(`research/competitive-portfolio-trackers-and-switcher-parity-2026-09-30/`)
with a web pass of 2026-11-18. Several vendor pages could not be opened
from the session, so some claims rest on search results; those are marked
unverified. It feeds I46 (what Portfolixir says it is) and I36 (the README
and the site).

**What changed since September.**

- **Portfolio Performance has its own local REST API and an experimental
  MCP endpoint** since 0.89.0 (2026-10-11), off by default: loopback only,
  a bearer token per client, 16 tools (14 read, 2 write), responses that
  repeat their parameters, amounts as JSON numbers, and no transaction
  list yet
  ([release](https://github.com/portfolio-performance/portfolio/releases/tag/0.89.0),
  [README](https://github.com/portfolio-performance/portfolio/tree/master/name.abuchen.portfolio.rest)).
  The pain Portfolixir was born from — PP's data out of reach of an agent —
  is now partly answered by PP itself, as long as the desktop app runs.
- **MCP is everywhere:** Ghostfolio (8 tools, 2 writing, OAuth 2.1 since
  3.99.0), Wealthfolio (agent writes with a preview before saving, since
  3.10 to 3.13), Parqet (an official hosted MCP server with read and write
  scopes), Kubera, Snowball (top plan only), rotki. Scalable Capital opened
  a broker MCP that prepares orders.
- **Most of them call a language model from inside the app** (Wealthfolio,
  Ghostfolio AI, getquin, Snowball, Sure); Wealthfolio 3.13 made sending
  spending data to the AI provider the default.
- **Still nobody ships MCP prompts** (checked in the code of PP, Ghostfolio
  and Wealthfolio).

**Where Portfolixir is different, and it holds up.**

1. **Always on, reachable from anywhere the operator allows**, not a
   desktop app that must be open (PP) — the owner's origin story.
2. **Every figure states its basis** — input series, window, reference,
   treatment of gaps — and money travels as decimal strings. PP now
   repeats its parameters, so the lead is narrower than it was, but still
   real.
3. **A research log per security that is never rewritten**, and
   predictions scored for calibration (ADR-0044, ADR-0055): a memory the
   agent can trust. No competitor shows one.
4. **The app never calls a model and never advises.** The data goes only
   to the agent the operator chose.
5. **Allocation the agent can work with**: classification trees, target
   weights, drift and indicative corrections over API and MCP; PP's 16
   tools have none for taxonomies or rebalancing.
6. **MCP prompts that carry whole workflows**, including one that writes
   import converters; nobody else ships prompts.

**Where it is weaker, honestly.** No phone app (PP, Parqet, getquin,
Delta and Snowball have one); far fewer bank and broker formats than PP's
PDF importers; no bank or broker sync; a small community and less polish
than the established tools; and PP's new API comes with PP's whole user
base.

**Why someone would switch**, in one sentence for I46: *"Your portfolio,
always on, for you and your agent: every figure says how it was computed,
the agent remembers why you bought, and the app itself never talks to a
model."* The people it fits: PP users who already use an agent and are
tired of an app that must be open, and people who want an agent on their
finances without handing them to an AI provider.

**Getting the data over (I49).**

| Tool | Export file | Read API for transactions |
|---|---|---|
| Portfolio Performance | XML (the full file) and CSV | local API, no transaction list yet |
| Ghostfolio | JSON export | yes, bearer token |
| Wealthfolio | ZIP/JSON and CSV | server mode, endpoints undocumented (unverified) |
| Parqet | activity CSV (unverified) | yes, OAuth, read scope, `externalId` |
| Sharesight | report CSVs (unverified) | yes, OAuth on request |
| Finanzfluss Copilot | transaction CSV, paid plan | none found |
| Snowball, Delta | transaction CSV | none found |
| getquin | unclear, no self-service export found | none found |

The three that would cover most switchers: **PP's XML**, **Parqet's API**
and **Ghostfolio's JSON**. Users of getquin, Finanzfluss and Delta are
best served by their broker's own files. A sync the app runs itself would
store another service's token, which the no-stored-credentials invariant
and B3.3 rule out today; the agent-run route of OQ-4 needs neither.

## Part 6 — The owner's follow-up of 2026-11-19

- **The app (I53).** The page saved to the iOS home screen already works
  well as an app. First step: recognise iOS Safari and suggest saving the
  page to the home screen once, with a web app manifest behind it. Later:
  native apps for macOS, iOS, watchOS and visionOS, with widgets and a
  layout for the folding iPhone, in a repository of their own. U1's "no
  native app" was a phase decision, so the native step needs a plan's
  decision; widgets that need data pushed to the device meet the push gate
  (B3.7).
- **Import and sync routes (I54).** Automatic data comes from outside: the
  operator's agent builds a converter or a sync and connects it to the
  API. The documentation collects the routes known to work; bank syncs
  might get a parallel repository. Recommended: recipes in the docs first,
  a sibling repository only when working code arrives, with the read-only
  line written down before it starts.
