---
title: 'competitive research: Portfolio trackers and switcher parity'
type: 'competitive'
topic: 'Portfolio trackers and switcher parity'
decision: 'Scope of the polish-before-launch phase: what a Portfolio Performance switcher must not miss, how to answer mobile access without a hosted cloud, and which competitor paradigms to adopt'
source: 'native run (parallel web fan-out) plus a hands-on look at the Ghostfolio live demo'
status: complete
claims_verified: 9
claims_unverified: 22
claims_disputed: 1
claims_overturned: 0
preset: 'standard'
validation: 'normal'
created: '2026-09-30'
updated: '2026-09-30'
---

# competitive research: Portfolio trackers and switcher parity

**Decision this research serves:** Scope of the polish-before-launch phase: what a Portfolio Performance switcher must not miss, how to answer mobile access without a hosted cloud, and which competitor paradigms to adopt.

## Executive summary

**What the evidence says to do.** Polish against a concrete bar before inviting
anyone. That bar is Portfolio Performance's report set plus its phone companion,
and it is documented well enough to check item by item. Then compete where no
peer stands: an app that never calls a language model itself, a memory the
agent can trust, and ready-made MCP prompts over the user's own ledger.

Three findings drive that answer:

1. **The switcher's baseline is broad, and two parts of it cannot be matched by
   polishing.** PP's Performance report has six sub-views, and its Calculation
   view walks from initial to final value through gains, earnings, fees, taxes
   and transfers [1][2]. Its dashboards carry
   monthly and yearly returns heatmaps, drawdown, volatility, Sharpe, FIRE and
   earnings widgets [3]. Charts compare against any
   benchmark [4], and 130 PDF extractors feed the ledger
   [5]. The two structural items are weighted assignment of one
   security to several categories [6][7] and a free phone
   companion that reads the same file from a consumer cloud drive and computes
   locally [8][9].
2. **"Agent-first" no longer sets a product apart on its own.** Both
   open-source peers built MCP servers into their apps this quarter: Wealthfolio
   in July 2026, with tokens that separate drafting from committing and a
   visible agent-activity log [10][11][12], and Ghostfolio in
   August 2026, with six tools filtered by the token's scope
   [13][14]. Both now call language models from inside the
   app [15][16][17]. None ships MCP prompts or resources over
   the user's own ledger [11][14][18].
3. **No self-hosted peer reaches the phone without a VPN or a relay.** Ghostfolio
   answers with a mobile-first PWA and a third-party native client
   [19][20]. Wealthfolio answers with a paid end-to-end-encrypted
   relay [21][22]. Actual Budget documents Tailscale for
   HTTPS without internet exposure [23]. Every SaaS peer, and PP, ship
   native apps [24][25][9].

**Biggest caveat:** user voice is thin. No first-person switcher statement from
the last twelve months was found, and Reddit was unreachable for the search tool.
The must-have list below rests on product inventories and forum topic titles,
not on switchers' own words.

## 1. Switcher parity: what a Portfolio Performance user brings along

**PP desktop, evidenced this run.**

- **Performance** has six sub-views: Dashboard, Calculation, Chart, Securities,
  Payments and Trades [1].
- **Calculation** runs from initial value through unrealized gains (currency
  effects shown separately), realized gains, earnings, fees and taxes, cash
  currency gains and performance-neutral transfers to final value. It offers
  FIFO or moving-average cost, a pre-tax view and CSV export [2].
- **Measures** are TTWROR (cumulative and annualized), IRR, absolute change and
  delta. Risk indicators are maximum and current drawdown, drawdown duration,
  volatility, semideviation and a Sharpe ratio
  [1][3].
- **Dashboards** can be several, with columns and per-widget periods. Widgets
  come in six categories and include monthly and yearly returns heatmaps, top
  contributors, FIRE, target-versus-actual allocation, upcoming dividends,
  earnings by month, quarter and year, trade statistics (holding period,
  turnover) and tax and fee rates [3]. The manual states no
  widget total, so the "46 widgets" figure from the phone listing is unverified
  [3][9].
- **Benchmarks:** the performance chart compares the portfolio against any
  security or index with price history, before or after taxes
  [4].
- **Taxonomies:** one security can sit in several categories with weights that
  should add up to 100 %, and the weights feed rebalancing deltas
  [6][26][7]. Release 0.86.0 added a
  Rebalancing view with cash-flow allocation [27].
- **Import:** the repository holds 130 institution-named PDF extractors, above
  the manual's "more than 90" [5][28]. Recent releases
  added broker CSV paths for Trade Republic and Scalable Capital [27].
- **Prices:** a built-in feed plus Yahoo Finance, Alpha Vantage, EOD, Finnhub,
  Leeway, Twelve Data, Quandl, JSON, CSV and "table on website" (low: the guide
  dates from 2025-08) [29].
- **Trajectory:** PP ships monthly. Recent releases: 0.87.0 (2026-08-16) with
  lot-based trade grouping, 0.86.0 with the Rebalancing view, 0.83.0 with Top
  Contributors and FIRE widgets [27].

**PP on the phone.** The companion app reads the desktop's file, in binary
format, from iCloud, Google Drive or OneDrive, computes on the device, and
leaves editing to the desktop [8][9]. It is
free except dashboards: EUR 3 a month or EUR 30 a year in the German store,
USD 3 or USD 25 in the US store [30][9]. The current
version is 1.13.0 from July 2026 [31], and the German listing shows 4.7
stars from 208 ratings [30]. Dropbox and WebDAV support rests on
vendor text only [9].

**Peers: switcher-critical rows.** Cells: ✓ evidenced · ◐ partial or paid ·
— looked for, not found on the pages read · ? not researched.

| Capability | PP | Ghostfolio | Wealthfolio | Parqet | Sources |
|---|---|---|---|---|---|
| Calculation breakdown, initial to final value | ✓ | ? | ? | ? | [2] |
| Returns heatmap | ✓ | ? | ? | ◐ paid treemap | [3][32] |
| Benchmark comparison | ✓ | ✓ | ✓ | ◐ paid | [4][33][34][32] |
| Weighted multi-category assignment | ✓ | ? | ? | — | [6][32] |
| Look-through by sector, region or country | — | ◐ with data gaps | ✓ | ◐ paid | [35][34][32] |
| Rule-based risk checks | ◐ indicators | ✓ 17 rules | ◐ risk lab | ◐ paid drawdown | [3][36][34][32] |
| FIRE projection | ✓ widget | ✓ | ✓ | — | [3][33][34][32] |
| Privacy mode hiding absolute values | ? | ✓ | ? | — | [37][32] |
| Broker PDF import | ✓ 130 | ? | ? | ✓ over 50 | [5][32] |
| Import of PP data | n/a | — | — | — | [19][34][38] |
| Native phone app | ✓ | ◐ PWA | ✓ iOS | ✓ | [9][19][39][24] |

**Table stakes across the field:** income and dividend history, a phone
surface, performance views, allocation charts, and low-effort intake through
bank sync or PDF import [3][32][40][25].
A dividend calendar appears in every consumer SaaS tracker checked
[32][41][25][42].
**Differentiators held by one or two products:** weighted categories (PP), rule
libraries (Ghostfolio's X-ray), FIRE projections (Ghostfolio, Wealthfolio, a PP
widget), privacy mode (Ghostfolio), tax reports (Sharesight, Parqet) and paid
look-through (Parqet)
[6][36][34][37][43][32].

**Ghostfolio, tried directly.** The landing page names its reader in a "for you
if you are…" list and promises a three-step start beside a live demo
[44]. X-ray ships 17 ready rules with thresholds, from currency and
account clusters to emergency fund and fee ratio [36]. Allocations break
down by platform, currency, asset class, sector, continent, market, country,
account and ETF provider, with visible "no data" gaps [35].
Presenter View and Zen Mode hide sensitive figures [37]. Read access
can be granted with an expiry [45]. A resources section runs 341
"open-source alternative to…" pages, including Parqet, getquin, Finanzfluss
Copilot and Wealthfolio, and none for Portfolio Performance [46].

## 2. Paradigms: deployment, phone access, sync, first run

| Product | Deployment | Phone | Sync | First run | Sources |
|---|---|---|---|---|---|
| Portfolio Performance | Desktop app writing a data file | Read-only companion app, local computation | The user's cloud drive | Install the app | [8][9] |
| Ghostfolio | Self-hosted Docker (PostgreSQL, Redis) or hosted Premium | Mobile-first PWA; third-party native iOS client using the instance token | One server | One compose command; live demo; CasaOS, Umbrel, Unraid, Home Assistant, Runtipi, TrueCharts, Easypanel | [19][20] |
| Wealthfolio | Local-first desktop app (SQLite); official Docker web mode | iOS app with its own database; Android planned; web UI as PWA | Paid end-to-end-encrypted relay; self-hosted instances are peers | Single `docker run`; PikaPods, Unraid, Proxmox, Coolify | [47][39][21][34] |
| Actual Budget (budgeting analog) | Local-first, optional sync server | Installed web app, works offline, needs a server | The user's own server | Demo or desktop app first; PikaPods with a donated share | [48] |
| Parqet, getquin, Finanzfluss Copilot | Vendor cloud | Native iOS and Android apps | Vendor account, bank and broker sync | Sign-up | [24][40][25] |

**Findings.**

- **The switcher's status quo needs no server and no VPN.** A consumer cloud
  drive moves the file, the phone recomputes locally, and the sync experience is
  the drive's, not the app's [8][9].
- **Self-hosted peers answer the phone in two ways.** Ghostfolio relies on the
  PWA and leaves network reachability to the user; its README offers only
  reverse-proxy settings [19][20]. Wealthfolio keeps a full
  database on each iPhone and syncs ciphertext through its paid relay, with the
  self-hosted web UI as the only documented route without it
  [39][21]. An unofficial project re-implements that
  relay for self-hosting, a demand signal (low) [49].
- **The documented no-exposure path is a tailnet.** Actual's HTTPS guide names
  Tailscale, or Caddy with a DNS challenge, for certificates without exposing the
  server [23]. Immich's remote-access guide recommends Tailscale when a
  router port cannot be opened, citing protection against zero-days
  [50]. Tailscale Serve proxies a local port to tailnet devices only
  and provisions Let's Encrypt certificates automatically
  [51][52]. The costs: every phone runs the Tailscale
  app, and machine names appear in public Certificate Transparency logs
  [52]. Whether an installed PWA works through Serve on iOS and
  Android was not evidenced.
- **Cloudflare Tunnel removes the VPN app and moves TLS termination to
  Cloudflare.** Cloudflare can then read requests, credentials included, and
  community voices treat that as the objection for private data (low: stale or
  undated sources) [53][54].
- **First run is a solved pattern among self-hosted peers:** a live demo
  (Ghostfolio), one command, and listings in home-server app stores and managed
  hosts [19][47][34][48]. None states a setup
  time.

## 3. AI, agents and MCP

| | Wealthfolio | Ghostfolio | Community Ghostfolio server | Parqet |
|---|---|---|---|---|
| Since | v3.6.0, 2026-07-05 [10] | 3.59.1, 2026-08-23, experimental [13] | registry entry since 2026-04 [55] | first-party guides [56] |
| Tools | 13 typed tools, 10 read and 3 write, shared with the in-app assistant [15] | 6: four reads, import, asset search [14] | 38–39, read and write [57] | read-only [56] |
| Access control | Tokens with 7 read and 4 write scopes; a draft-only token can never commit [11][12] | Two access levels; the tool list shows only what the token may call [14] | Read-only mode, tag groups, tool search [57] | OAuth 2.0 [56] |
| Audit | Agent-activity log with tool, outcome and token; can be switched off [11] | none found [19] | rate limits only [57] | ? |
| Client setup | Copy-paste entries for Claude Desktop, Cursor, Windsurf, Cline [11] | no client example [19] | `uvx`, pip, Docker [57] | hosted URL [56] |
| MCP prompts or resources | none documented [11] | none registered [14] | none documented [57] | ? |
| App calls a model itself | yes, the user's provider incl. Ollama [15] | yes, via OpenRouter [17] | n/a | ? |

**Patterns worth studying.**

- **Draft and commit as separate token scopes.** A credential that can only
  stage changes enforces preview-then-apply at the auth layer [11].
  Wealthfolio adds a rule that tool output and attachments cannot authorize a
  draft [58].
- **A tool list filtered by the token's scope,** so the agent sees only what it
  may call [14]. The community server goes further with tag groups and a
  search-then-call mode that hides the full list [57].
- **Small agent surfaces.** Peers expose six to thirteen tools
  [14][15]. Ghostfolio dropped a direct create-activity tool in
  favour of import [59].
- **Copy-paste client configuration** is the cheapest onboarding aid on offer
  [11].
- **Hosted commercial servers default to read-only with OAuth** (Parqet), and
  Agni Folio splits revocable read and write scopes (medium: directory source)
  [56][60]. AI-native entrants now register their own servers
  in the official registry, one of them advertising agent execution of
  human-approved changes [55].

**Open ground.** No peer ships MCP prompts or resources over the user's own
ledger; the only finance server found with prompts works on market data alone
[11][14][18]. The advice boundary is thinly handled:
Wealthfolio says its assistant tells you "what you own, not what you should own"
[15], Ghostfolio's generated analysis prompt asks for "Optimization
Ideas" without a disclaimer [17], and getquin markets questions such
as whether it is time to harvest losses [61].

**PP users are already wiring agents to their data.** Forum members feed PP's XML
to several models for written reports and publish MCP servers over it, one with
about 20 read-only functions; a default binding to all interfaces drew immediate
criticism [62]. One of them, pp-terminal, is an analytics companion
over the PP file with an MCP mode that never modifies the file [63].

## 4. Business models, positioning and user voice

| Product | Model | Paid price | What is paid for | Sources |
|---|---|---|---|---|
| Ghostfolio | AGPLv3, plus hosted Premium funding hosting, data and development | unverified ("from $48/yr" per an aggregator) | Hosting; a Premium-only data source | [19][64] |
| Wealthfolio | Free local core, optional Connect | $2.99, $7.99, $12.99 a month on the official page (aggregators list the entry tier at $3.99: disputed); a $24.99 tier announced | Encrypted sync, brokerage sync, household view; hosted AI and licensed data in the coming tier | [22][65] |
| Portfolio Performance | Free desktop, freemium phone app | EUR 3 a month or EUR 30 a year | Phone dashboards only | [30] |
| rotki | Tiered open core | not verified | Limits such as devices and database size | [66] |
| Parqet | Freemium SaaS | EUR 11.99 and EUR 29.99 a month | Dividend forecast and calendar, X-Ray, benchmark, tax dashboard | [32] |

**Positioning.** Ghostfolio: "a privacy-first, open source dashboard for your
personal finances", for multi-platform buy-and-hold investors who value data
ownership [44][19]. Wealthfolio: "Grow Wealth. Keep Control.",
private and local on every device [34]. PP's phone app: a
privacy-preserving companion to the desktop [30]. Finanzfluss
Copilot stresses German servers [25].

**User voice (thin).**

- **PP.** Seven of the forum's 50 top topics this year are about prices that
  stop updating. Broker imports (Trade Republic CSV, DEGIRO) and bookkeeping edge
  cases (spin-offs, splits, gifted shares) draw long threads, and users ask what
  figures such as invested capital mean [67]. When the maintainer of
  the PDF importers stepped down in June 2026, replies feared entering bookings
  by hand [68]. One top thread asks for research notes on a
  security [67].
- **Alternatives.** Ghostfolio's top open issues are a failing data provider
  and a disputed performance calculation [69]. Wealthfolio's
  most-discussed issues are wrong cash and transfer figures, including a release
  that broke calculations [70]. Its Show HN praised the UI and the local
  model, and called missing automated sync a dealbreaker [71]. Testers of a
  web app built on PP data checked valuations first and found them off
  [72].
- **Switchers.** No first-person statement from the last twelve months was
  found in either direction.

## Cross-dimension insights

1. **Correct numbers are the first trust test, and incumbents bleed there.**
   Testers check valuations first [72], the alternatives' top
   complaints are wrong figures [69][70], and PP users ask what
   their figures mean [67]. A switcher will judge a new tool by
   whether its numbers match PP's and whether it can say why.
2. **Import is the lock-in, and nobody imports PP.** PP's extractor base is large
   and its users fear manual entry [5][68]. No peer
   page offers an import of PP data
   [19][34][38]. PP users build on the XML themselves
   instead [62][72]. A complete PP import is both the
   migration path and unclaimed ground.
3. **The phone is where self-hosting loses, and convenience at the edge is what
   people pay for.** SaaS peers and PP ship native apps; self-hosted peers answer
   with a PWA or a paid relay [24][9][19][21].
   The paid parts across the field are phone dashboards, sync and brokerage
   links, hosting and data [30][22][19].
4. **The agent axis converged in one quarter, but not on memory, prompts or
   restraint.** Peers expose holdings, activities and accounts through six to
   thirteen tools, ship no prompts, call models in-app and handle the advice
   boundary thinly [15][14][17]. What remains
   unclaimed: sourced memory the agent reads and writes under confirmation,
   prompts that carry the no-advice stance, and an app that never calls a model.
5. **The Portfolio Performance slot in discovery is empty.** Ghostfolio's 341
   comparison pages skip PP [46], Parqet's PP comparison dates from
   2020 [38], and PP's own forum is where users discuss agents on PP
   data [62].

## Contrary evidence

The red-team pass did not run (off by configuration). Two counter-signals
surfaced during the run and deserve weight. PP users already build their own MCP
servers on the PP file, so part of the intended audience may prefer a thin
do-it-yourself bridge to a second application [62]. And Wealthfolio
already bundles an MCP server, an iOS app, a polished UI and optional sync
[11][39][71], which is the closest existing answer to
"a PP switcher who uses an agent".

## Recommendations

Each recommendation names the artifact that consumes it. Statements about
Portfolixir's current state are project context from the repository on
2026-09-30, not research evidence.

1. **Adopt PP's report set as the parity bar and close it view by view.** Order:
   a Calculation-style breakdown from initial to final value; monthly and yearly
   returns heatmaps; earnings by month, quarter and year with upcoming dividends;
   trade statistics (holding period, turnover); benchmark overlays on the
   performance chart. *Confidence: medium, single primary source per view (PP's
   manual, 2026-09-03).* Feeds the owner-feedback triage and a polish lane, with
   a mockup board per view before it is built.
2. **Decide the two structural gaps explicitly; polishing will not close them.**
   (a) Weighted multi-category assignment is evidenced only in PP; a switcher
   with weighted regional or sector taxonomies loses it here (project context:
   forbidden by the "advanced classifications" hard rule, so it needs an owner
   decision). (b) A complete PP-file import is the migration path and no peer
   offers it (project context: the XML import was closed on 2026-09-23 with
   single-operator reasoning; a one-time seed for a newcomer is a different
   case). *Confidence: medium; the absence claims are scoped to the pages read.*
   Feeds an ADR or decision record on the planning PR.
3. **Answer the phone with an installable PWA plus a documented Tailscale Serve
   recipe; build no native app and no relay in this phase.** Test PWA
   installation through Serve on iOS and Android first. Keep Cloudflare Tunnel
   out of the recommended path for financial data. *Confidence: medium; Tailscale
   Serve is documented, PWA-through-Serve is not.* Feeds the home-deployment
   guide and a mockup board for the phone layout.
4. **Adopt the peers' agent-safety patterns.** Tool lists scoped to the token, or
   toolsets, so a new agent sees a small, relevant set; copy-paste client
   configurations; a draft-versus-commit split for agent writes, which fits the
   standing "machine-extracted data is a proposal" rule; and an agent-activity
   log that cannot be switched off. *Confidence: medium, vendor primary docs.*
   Feeds the MCP companion's backlog (project context: 139 tools today).
5. **Claim the open ground with MCP prompts over the user's own ledger:** a weekly
   check-up, a drift and rule check, a thesis review, upcoming events, a PP-import
   walkthrough, each carrying the no-advice framing inside the template.
   *Confidence: medium; absence is scoped to the servers read and one registry
   query.* Feeds the "second user" lane.
6. **Position on what peers gave up.** "The app never calls a model; your agent
   does", a memory the agent can trust, and figures that state their basis. Aim
   one comparison page at the empty PP slot, written as a migration guide.
   *Confidence: medium for the peer facts; whether users value "no in-app model"
   is not evidenced.* Feeds the brief amendment and the README.
7. **Add a presenter or privacy mode.** It is cheap, one peer ships it, and it
   also serves screenshots and demos. *Confidence: medium, one peer.* Feeds the
   polish lane.
8. **For the private strategy note, outside this repository:** the evidenced
   revenue patterns are hosted premium with data (Ghostfolio), an encrypted sync
   relay with brokerage links and hosted AI (Wealthfolio), paid phone dashboards
   (PP), and tiered open core (rotki). *Confidence: medium for the Wealthfolio
   and PP prices, low for Ghostfolio and rotki.*

## Open questions

1. **Does an installed PWA work through Tailscale Serve on iOS Safari and Android
   Chrome?** Needs a hands-on test on a live instance, about half an hour.
2. **What do PP switchers actually miss?** No first-person statements were found
   and Reddit was unreachable. Answer with the owner's log of each time PP is
   opened, three to five interviews with PP users who run agents, or a drafted
   prompt for a research tool with Reddit access.
3. **Does PP's statement-of-assets chart plot allocation over time?** Its page
   was not read.
4. **What does Ghostfolio Premium cost, and are its AI features gated?** The
   pricing page does not render for fetchers; check an archived snapshot.
5. **Wealthfolio's exact MCP tool count and advice clause** are in its
   repository (`system_prompt.txt`), not its docs.
6. **The "46 widgets" figure** needs a count of PP's widget registry in source.

## Source appendix

Accessed 2026-09-30 unless stated. Confidence is the confidence of the finding the row supports.

| [n] | Claim or finding it supports | Publisher | Pub date | Accessed | Confidence |
|---|---|---|---|---|---|
| [1] | Performance report has six sub-views; TTWROR, IRR, absolute change and delta; drawdown, volatility, semideviation | [Portfolio Performance manual](https://help.portfolio-performance.info/en/reference/view/reports/performance/) | 2026-09-03 | 2026-09-30 | medium |
| [2] | Calculation view from initial to final value; FIFO or moving average; pre-tax view; CSV export | [Portfolio Performance manual](https://help.portfolio-performance.info/en/reference/view/reports/performance/calculation/) | 2026-09-03 | 2026-09-30 | medium |
| [3] | Six widget categories incl. monthly and yearly returns heatmaps, FIRE, top contributors, earnings, trade statistics; no widget total stated | [Portfolio Performance manual](https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/) | 2026-09-03 | 2026-09-30 | medium |
| [4] | Performance chart compares against any security or index with price history | [Portfolio Performance manual](https://help.portfolio-performance.info/en/how-to/benchmarking/) | 2026-09-03 | 2026-09-30 | medium |
| [5] | 130 institution-named PDF extractor classes on master | [Portfolio Performance GitHub repository](https://api.github.com/repos/portfolio-performance/portfolio/git/trees/master:name.abuchen.portfolio/src/name/abuchen/portfolio/datatransfer/pdf) | undated (read 2026-09-30) | 2026-09-30 | high |
| [6] | One security can be assigned to several taxonomy categories with weights adding up to 100 % | [Portfolio Performance manual](https://help.portfolio-performance.info/en/reference/view/taxonomies/managing-taxonomies/) | 2026-09-03 | 2026-09-30 | high |
| [7] | Independent confirmation: one ETF split across several region categories by weight in PP; the unassigned remainder returns to the pool | [Der Finanzfisch (blog tutorial)](https://der-finanzfisch.de/klassifizierung-von-etfs-in-portfolio-performance/) | 2017-04-12 | 2026-09-30 | high |
| [8] | Phone companion reads the same binary file from iCloud, Google Drive or OneDrive, computes on the device, no edits; dashboards need a subscription | [Portfolio Performance forum (maintainer announcement)](https://forum.portfolio-performance.info/t/portfolio-performance-app-the-first-version/27334) | 2024-02-21 | 2026-09-30 | high |
| [9] | Phone app reads the desktop file from a cloud drive, computes locally, leaves editing to the desktop; Premium ($3/month, $25/year) unlocks dashboards; Dropbox/WebDAV named in vendor text | [Apple App Store (seller MSM Mannheimer Software-Manufaktur UG)](https://apps.apple.com/us/app/portfolio-performance/id6451118191) | undated | 2026-09-30 | high |
| [10] | MCP server in v3.6.0 (2026-07-05) on desktop and web; audited scoped tokens; writes as drafts | [Wealthfolio (GitHub releases)](https://github.com/afadil/wealthfolio/releases) | 2026-07-05 to 2026-09-27 | 2026-09-30 | medium |
| [11] | MCP at /mcp; client snippets for Claude Desktop, Cursor, Windsurf, Cline; 7 read and 4 write scopes with draft separate from commit; agent activity log that can be switched off | [Wealthfolio docs](https://wealthfolio.app/docs/guide/mcp-server/) | 2026-09-30 | 2026-09-30 | medium |
| [12] | Independent confirmation: Wealthfolio's built-in MCP server with scoped, revocable, audit-logged tokens | [abidals (third-party package, GitHub)](https://github.com/abidals/Wealthfolio-Olares) | undated (ships Wealthfolio 3.8.0) | 2026-09-30 | high |
| [13] | MCP server since 3.59.1 (2026-08-23); copy-AI-prompt actions; several releases a week | [Ghostfolio (changelog)](https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md) | 2026-09-30 | 2026-09-30 | medium |
| [14] | Six MCP tools under two access levels; tool list filtered by the access's scope; no prompts or resources | [Ghostfolio (pull request diff)](https://github.com/ghostfolio/ghostfolio/pull/7935/files) | 2026-09-26 | 2026-09-30 | medium |
| [15] | 13 typed tools shared with MCP; user's own model provider incl. Ollama; 'what you own, not what you should own' | [Wealthfolio docs](https://wealthfolio.app/docs/guide/ai-assistant/) | 2026-09-30 | 2026-09-30 | medium |
| [16] | Built-in AI assistant with local and cloud providers (search summary) | [Hostinger (app catalogue)](https://www.hostinger.com/vn/applications/wealthfolio) | undated | 2026-09-30 | medium |
| [17] | Analysis prompt asks for 'Optimization Ideas' without a disclaimer; the service can call an LLM via OpenRouter | [Ghostfolio (source code)](https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/apps/api/src/app/endpoints/ai/ai.service.ts) | undated (main, read 2026-09-30) | 2026-09-30 | medium |
| [18] | A market-data MCP server that ships MCP prompts and resources, not over a user's ledger | [jackdark425 (GitHub)](https://github.com/jackdark425/aigroup-fmp-mcp) | undated | 2026-09-30 | medium |
| [19] | Docker with PostgreSQL and Redis; mobile-first PWA; home-server app stores; data sources; hosted Premium; experimental MCP behind a feature flag; about 9.4k stars | [Ghostfolio (GitHub README)](https://github.com/ghostfolio/ghostfolio) | undated (read 2026-09-30) | 2026-09-30 | high |
| [20] | Unofficial native iOS client for cloud or self-hosted Ghostfolio via its security token; paid Pro for writes | [Apple App Store (third-party developer)](https://apps.apple.com/app/id6755882228) | undated (read 2026-09-30) | 2026-09-30 | high |
| [21] | Self-hosted instances are sync peers; changes travel as end-to-end-encrypted blobs through Connect | [Wealthfolio docs](https://wealthfolio.app/docs/guide/connect-broker-sync/) | 2026-09-30 | 2026-09-30 | medium |
| [22] | Connect tiers: $2.99, $7.99, $12.99, and a coming $24.99 tier with hosted AI and licensed data | [Wealthfolio](https://wealthfolio.app/connect/) | undated (read 2026-09-30) | 2026-09-30 | medium |
| [23] | Tailscale or Caddy with a DNS challenge for certificates without exposing the server to the internet | [Actual Budget docs](https://actualbudget.org/docs/config/https) | undated (read 2026-09-30) | 2026-09-30 | high |
| [24] | Native iOS and Android apps | [Parqet](https://parqet.com/en/blog/android-app) | undated | 2026-09-30 | medium |
| [25] | Dividend dashboard and calendar; over 350 bank connections; iOS and Android apps; German servers | [Finanzfluss](https://www.finanzfluss.de/copilot/) | undated (read 2026-09-30) | 2026-09-30 | medium |
| [26] | A weight counts that share of the value into the category; rebalancing computes target and delta per category | [Portfolio Performance manual](https://help.portfolio-performance.info/en/reference/view/taxonomies/using-taxonomies/) | 2025-05-15 | 2026-09-30 | high |
| [27] | 0.87.0 lot-based trades; 0.86.0 Rebalancing view with cash-flow allocation; 0.83.0 Top Contributors and FIRE widgets; broker CSV paths | [Portfolio Performance GitHub releases](https://github.com/portfolio-performance/portfolio/releases) | 2026-08-16 | 2026-09-30 | medium |
| [28] | PDF import from more than 90 banks and brokers (search summary) | [Portfolio Performance manual](https://help.portfolio-performance.info/en/reference/file/import/pdf-import/) | undated | 2026-09-30 | high |
| [29] | Built-in price feed plus Yahoo Finance, Alpha Vantage, EOD, Finnhub, Leeway, Twelve Data, Quandl, JSON, CSV, table on website | [Portfolio Performance manual](https://help.portfolio-performance.info/en/how-to/downloading-historical-prices/) | 2025-08-08 | 2026-09-30 | low |
| [30] | Premium EUR 3/month or EUR 30/year, dashboards only; 4.7 from 208 ratings | [Apple App Store (seller MSM Mannheimer Software-Manufaktur UG)](https://apps.apple.com/de/app/portfolio-performance/id6451118191) | undated | 2026-09-30 | medium |
| [31] | Android app version 1.13.0, July 2026 (search summary) | [AppBrain](https://www.appbrain.com/app/portfolio-performance/software.msm.portfolio_performance) | 2026-07-08 | 2026-09-30 | medium |
| [32] | Basic free, Plus EUR 11.99/month, Investor EUR 29.99/month; paid dividend forecast and calendar, X-Ray, benchmark, tax dashboard; PDF/CSV import for over 50 brokers | [Parqet](https://parqet.com/en/pricing) | undated (read 2026-09-30) | 2026-09-30 | medium |
| [33] | Analysis view with benchmark selector, asset versus currency performance, investment streaks, dividend timeline | [Ghostfolio (live demo, hands-on)](https://ghostfol.io/en/portfolio) | undated (live 2026-09-30) | 2026-09-30 | medium |
| [34] | Positioning line; feature list incl. FIRE, rebalancing, AI assistant; self-host targets; self-reported traction | [Wealthfolio](https://wealthfolio.app/) | undated (read 2026-09-30) | 2026-09-30 | high |
| [35] | Allocations by platform, currency, asset class, holding, sector, continent, market, country, account, ETF provider, with visible data gaps | [Ghostfolio (live demo, hands-on)](https://ghostfol.io/en/portfolio/allocations) | undated (live 2026-09-30) | 2026-09-30 | medium |
| [36] | X-ray: 17 built-in rules with thresholds | [Ghostfolio (live demo, hands-on)](https://ghostfol.io/en/portfolio/x-ray) | undated (live 2026-09-30) | 2026-09-30 | medium |
| [37] | Presenter View and Zen Mode settings | [Ghostfolio (live demo, hands-on)](https://ghostfol.io/en/account) | undated (live 2026-09-30) | 2026-09-30 | medium |
| [38] | Parqet's PP comparison page dates from 2020 and names no PP import path | [Parqet (vendor blog)](https://parqet.com/en/blog/parqet-vs-portfolio-performance) | 2020-02-04 | 2026-09-30 | low |
| [39] | Each iOS device runs its own database; no native Android app yet; self-hosted web UI usable as a PWA | [Wealthfolio docs](https://wealthfolio.app/docs/guide/mobile/) | 2026-09-30 | 2026-09-30 | medium |
| [40] | Imports through API connections to more than 2,000 banks and brokers | [getquin](https://www.getquin.com/portfolio-tracker) | undated | 2026-09-30 | medium |
| [41] | Dividend calendar and forecast | [getquin](https://www.getquin.com/dividend-tracker) | undated | 2026-09-30 | medium |
| [42] | Native app with dividend and coupon calendar and broker consolidation | [Apple App Store (Snowball Analytics)](https://apps.apple.com/app/snowball-analytics/id6463484375) | undated | 2026-09-30 | medium |
| [43] | Taxable income and capital gains reports on paid plans | [Sharesight (blog)](https://sharesight.com/blog/3-ways-sharesight-helps-investors-at-tax-time) | undated | 2026-09-30 | medium |
| [44] | Positioning line, a 'for you if' list, a three-step start next to a live demo, self-reported traction | [Ghostfolio (live site, hands-on)](https://ghostfol.io/en) | undated (live 2026-09-30) | 2026-09-30 | medium |
| [45] | Read-access grants (public restricted view, named grantee) with expiry | [Ghostfolio (live demo, hands-on)](https://ghostfol.io/en/account/access) | undated (live 2026-09-30) | 2026-09-30 | medium |
| [46] | 341 'open-source alternative to' pages incl. Parqet, getquin, Finanzfluss Copilot, Wealthfolio; none for Portfolio Performance | [Ghostfolio (live site, hands-on)](https://ghostfol.io/en/resources/personal-finance-tools) | undated (live 2026-09-30) | 2026-09-30 | medium |
| [47] | Local-first desktop app on SQLite; official Docker web mode with single-command start and password/OIDC | [Wealthfolio (GitHub README)](https://github.com/afadil/wealthfolio) | undated (read 2026-09-30) | 2026-09-30 | high |
| [48] | Local-first with optional sync server; phone use needs a server; installed web app works offline; demo or desktop first; PikaPods with a donated share | [Actual Budget docs](https://actualbudget.org/docs/install/) | undated (read 2026-09-30) | 2026-09-30 | high |
| [49] | Unofficial self-hostable replacement for the Connect relay | [festivities (community, GitHub)](https://github.com/festivities/wealthfolio-connect-self-hosted) | undated | 2026-09-30 | low |
| [50] | Recommends Tailscale when a router port cannot be opened, citing protection against zero-days | [Immich docs](https://docs.immich.app/guides/remote-access/) | undated (search extract) | 2026-09-30 | medium |
| [51] | Serve proxies a local port to tailnet devices only and provisions certificates automatically | [Tailscale docs](https://tailscale.com/kb/1312/serve) | 2026-01-20 | 2026-09-30 | high |
| [52] | Let's Encrypt certificates for tailnet names; names appear in Certificate Transparency logs | [Tailscale docs](https://tailscale.com/kb/1153/enabling-https) | 2025-12-10 | 2026-09-30 | high |
| [53] | Cloudflare Tunnel means Cloudflare decrypts all TLS traffic | [Nextcloud community forum](https://help.nextcloud.com/t/is-cloudflare-tunnel-safe-privacy-focused/150268) | undated (stale) | 2026-09-30 | low |
| [54] | Cloudflare's edge decrypts the full request including credentials | [Pluggie (blog)](https://pluggie.io/blog/cloudflare-tunnel-tls-privacy) | undated | 2026-09-30 | low |
| [55] | Community Ghostfolio server and AI-native entrants listed; no Wealthfolio or Portfolio Performance entry for 'folio' | [Official MCP Registry](https://registry.modelcontextprotocol.io/v0/servers?search=folio&limit=100) | 2026-09-30 | 2026-09-30 | medium |
| [56] | Hosted MCP with OAuth 2.0; read-only per the guide | [Parqet Developer Hub](https://developer.parqet.com/docs/give-ai-portfolio-context-with-the-parqet-mcp) | undated | 2026-09-30 | medium |
| [57] | Community server with 38-39 tools, read-only mode, tag-based tool groups, tool-search mode | [mhajder (community, GitHub)](https://github.com/mhajder/ghostfolio-mcp) | undated (read 2026-09-30) | 2026-09-30 | medium |
| [58] | Tool output and attachments cannot authorize drafts; one versioned system prompt with safety fixtures | [Wealthfolio (GitHub release)](https://github.com/wealthfolio/wealthfolio/releases/tag/v3.7.0) | 2026 (exact date unverified) | 2026-09-30 | medium |
| [59] | First-party MCP PR series; a direct create-activity tool was dropped in favour of import | [Ghostfolio (pull requests)](https://github.com/ghostfolio/ghostfolio/pulls?q=is%3Apr+mcp) | 2026-08-23 to 2026-09-26 | 2026-09-30 | high |
| [60] | Agni Folio hosted MCP with OAuth 2.1, separate read and write scopes, revocable | [Glama (directory)](https://glama.ai/mcp/servers/sx89qje90t) | undated | 2026-09-30 | medium |
| [61] | AI agents marketed with advice-adjacent questions such as whether to harvest losses | [getquin](https://www.getquin.com/getquin-ai/) | undated | 2026-09-30 | medium |
| [62] | Users feed PP XML to LLMs and publish MCP servers over it; a 0.0.0.0 default was criticised | [Portfolio Performance forum](https://forum.portfolio-performance.info/t/using-ai-to-analyze-a-portfolio-performance-xml-file-has-anyone-else-tried-this/39153) | 2026-04-19 to 2026-07-26 | 2026-09-30 | high |
| [63] | Analytics companion over the PP XML file with an MCP mode; never modifies the PP file | [ma4nn (GitHub)](https://github.com/ma4nn/pp-terminal) | undated (read 2026-09-30) | 2026-09-30 | high |
| [64] | Ghostfolio Premium 'from $48/yr' (unconfirmed on the official page) | [findmymoat (aggregator)](https://www.findmymoat.com/vs/ghostfolio-vs-wealthfolio) | undated | 2026-09-30 | low |
| [65] | Lists Wealthfolio Connect's entry tier at $3.99 a month, against $2.99 on the official page | [Toolradar (aggregator)](https://toolradar.com/tools/wealthfolio/pricing) | undated | 2026-09-30 | low |
| [66] | rotki replaced its single Premium tier with Basic, Advanced and Custom after seven years | [rotki (blog)](https://blog.rotki.com/2025/10/13/rotki-tiers/) | 2025-10-13 | 2026-09-30 | low |
| [67] | Top topics: failing price updates (7 of 50), broker imports, bookkeeping edge cases, what figures mean, research notes on securities | [Portfolio Performance forum (yearly top listing)](https://forum.portfolio-performance.info/top.json?period=yearly) | 2025-10 to 2026-09 | 2026-09-30 | medium |
| [68] | Maintainer of the PDF importers stepped down; users fear manual entry | [Portfolio Performance forum](https://forum.portfolio-performance.info/t/abschied-vom-pp-team-und-projekt/39393) | 2026-06-06 | 2026-09-30 | medium |
| [69] | Top open issues: a failing data provider, a wrong performance calculation, crashes | [GitHub (Ghostfolio issues)](https://api.github.com/search/issues?q=repo:ghostfolio/ghostfolio+is:issue+is:open&sort=reactions&order=desc&per_page=20) | 2025-10 to 2026-09 | 2026-09-30 | medium |
| [70] | Most-discussed issues: cash balances and transfers; a release that broke calculations | [GitHub (Wealthfolio issues)](https://api.github.com/repos/afadil/wealthfolio/issues?state=open&sort=comments&direction=desc&per_page=30) | 2025-09 to 2026-07 | 2026-09-30 | medium |
| [71] | Praise for UI, local model, platforms; missing automated sync called a dealbreaker | [Hacker News](https://news.ycombinator.com/item?id=46006016) | 2025-11 (approx.) | 2026-09-30 | medium |
| [72] | Testers of a web app built on PP data checked valuations first and found them off | [Portfolio Performance forum](https://forum.portfolio-performance.info/t/new-app-created-based-on-ppxml2db/39100) | 2026-04 | 2026-09-30 | medium |

## Staleness map

Computed with `recon_kit.py staleness` from the claims ledger in `.memlog.md`.
Windows follow the competitive pack: capability and pricing 3 months;
trajectory, traction and positioning 6 months; sentiment 12 months.

| Re-check by | Claims |
|---|---|
| now (stale) | [51] Tailscale Serve gives tailnet-only HTTPS: the vendor page was last validated in 2026-01; the independent Actual docs page is undated |
| 2026-11-01 | [13] Ghostfolio's built-in MCP server · [71] missing sync as a dealbreaker for Wealthfolio |
| 2026-12-01 | Every other capability and pricing claim: PP's report set, heatmaps, weighted taxonomies, benchmarks, PDF extractors and phone app [2]–[6] [8] [30]; Wealthfolio's and Ghostfolio's agent surfaces [11] [12] [14] [16] [17]; the absence of ledger prompts [18] and of PP import [38]; phone answers [20] [21]; prices [22] [32]; X-ray and Presenter View [36] [37]; community PP tooling [63] |
| 2027-01-01 | [10] Wealthfolio's MCP release date |
| 2027-03-01 | [19] Ghostfolio's star count · [46] Ghostfolio's comparison pages |
| 2027-06-01 to 2027-09-01 | User voice: [68] (June), [70] (July), [67] (August), [69] (September) |

Earliest re-check: [51], now. The next wave falls on 2026-11-01, and by
2026-12-01 most capability and pricing claims need a Refresh. The Cloudflare
claim [53] carries no date and is left out of the computation.
