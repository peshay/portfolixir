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
   and transfers [@pp-manual-perf][@pp-manual-calc]. Its dashboards carry
   monthly and yearly returns heatmaps, drawdown, volatility, Sharpe, FIRE and
   earnings widgets [@pp-manual-dashboard]. Charts compare against any
   benchmark [@pp-manual-benchmark], and 130 PDF extractors feed the ledger
   [@pp-repo-pdf]. The two structural items are weighted assignment of one
   security to several categories [@pp-manual-managing-tax][@finanzfisch-blog] and a free phone
   companion that reads the same file from a consumer cloud drive and computes
   locally [@pp-forum-app-launch][@pp-appstore-us].
2. **"Agent-first" no longer sets a product apart on its own.** Both
   open-source peers built MCP servers into their apps this quarter: Wealthfolio
   in July 2026, with tokens that separate drafting from committing and a
   visible agent-activity log [@wf-releases][@wf-docs-mcp][@wf-olares], and Ghostfolio in
   August 2026, with six tools filtered by the token's scope
   [@gf-changelog][@gf-pr-7935]. Both now call language models from inside the
   app [@wf-docs-ai][@hostinger-wf][@gf-ai-service]. None ships MCP prompts or resources over
   the user's own ledger [@wf-docs-mcp][@gf-pr-7935][@fmp-prompts].
3. **No self-hosted peer reaches the phone without a VPN or a relay.** Ghostfolio
   answers with a mobile-first PWA and a third-party native client
   [@gf-readme][@scaryfolio]. Wealthfolio answers with a paid end-to-end-encrypted
   relay [@wf-docs-connect][@wf-connect]. Actual Budget documents Tailscale for
   HTTPS without internet exposure [@actual-https]. Every SaaS peer, and PP, ship
   native apps [@parqet-apps][@ffc-page][@pp-appstore-us].

**Biggest caveat:** user voice is thin. No first-person switcher statement from
the last twelve months was found, and Reddit was unreachable for the search tool.
The must-have list below rests on product inventories and forum topic titles,
not on switchers' own words.

## 1. Switcher parity: what a Portfolio Performance user brings along

**PP desktop, evidenced this run.**

- **Performance** has six sub-views: Dashboard, Calculation, Chart, Securities,
  Payments and Trades [@pp-manual-perf].
- **Calculation** runs from initial value through unrealized gains (currency
  effects shown separately), realized gains, earnings, fees and taxes, cash
  currency gains and performance-neutral transfers to final value. It offers
  FIFO or moving-average cost, a pre-tax view and CSV export [@pp-manual-calc].
- **Measures** are TTWROR (cumulative and annualized), IRR, absolute change and
  delta. Risk indicators are maximum and current drawdown, drawdown duration,
  volatility, semideviation and a Sharpe ratio
  [@pp-manual-perf][@pp-manual-dashboard].
- **Dashboards** can be several, with columns and per-widget periods. Widgets
  come in six categories and include monthly and yearly returns heatmaps, top
  contributors, FIRE, target-versus-actual allocation, upcoming dividends,
  earnings by month, quarter and year, trade statistics (holding period,
  turnover) and tax and fee rates [@pp-manual-dashboard]. The manual states no
  widget total, so the "46 widgets" figure from the phone listing is unverified
  [@pp-manual-dashboard][@pp-appstore-us].
- **Benchmarks:** the performance chart compares the portfolio against any
  security or index with price history, before or after taxes
  [@pp-manual-benchmark].
- **Taxonomies:** one security can sit in several categories with weights that
  should add up to 100 %, and the weights feed rebalancing deltas
  [@pp-manual-managing-tax][@pp-manual-using-tax][@finanzfisch-blog]. Release 0.86.0 added a
  Rebalancing view with cash-flow allocation [@pp-releases].
- **Import:** the repository holds 130 institution-named PDF extractors, above
  the manual's "more than 90" [@pp-repo-pdf][@pp-manual-pdf]. Recent releases
  added broker CSV paths for Trade Republic and Scalable Capital [@pp-releases].
- **Prices:** a built-in feed plus Yahoo Finance, Alpha Vantage, EOD, Finnhub,
  Leeway, Twelve Data, Quandl, JSON, CSV and "table on website" (low: the guide
  dates from 2025-08) [@pp-manual-prices].
- **Trajectory:** PP ships monthly. Recent releases: 0.87.0 (2026-08-16) with
  lot-based trade grouping, 0.86.0 with the Rebalancing view, 0.83.0 with Top
  Contributors and FIRE widgets [@pp-releases].

**PP on the phone.** The companion app reads the desktop's file, in binary
format, from iCloud, Google Drive or OneDrive, computes on the device, and
leaves editing to the desktop [@pp-forum-app-launch][@pp-appstore-us]. It is
free except dashboards: EUR 3 a month or EUR 30 a year in the German store,
USD 3 or USD 25 in the US store [@pp-appstore-de][@pp-appstore-us]. The current
version is 1.13.0 from July 2026 [@pp-appbrain], and the German listing shows 4.7
stars from 208 ratings [@pp-appstore-de]. Dropbox and WebDAV support rests on
vendor text only [@pp-appstore-us].

**Peers: switcher-critical rows.** Cells: ✓ evidenced · ◐ partial or paid ·
— looked for, not found on the pages read · ? not researched.

| Capability | PP | Ghostfolio | Wealthfolio | Parqet | Sources |
|---|---|---|---|---|---|
| Calculation breakdown, initial to final value | ✓ | ? | ? | ? | [@pp-manual-calc] |
| Returns heatmap | ✓ | ? | ? | ◐ paid treemap | [@pp-manual-dashboard][@parqet-pricing] |
| Benchmark comparison | ✓ | ✓ | ✓ | ◐ paid | [@pp-manual-benchmark][@gf-analysis][@wf-home][@parqet-pricing] |
| Weighted multi-category assignment | ✓ | ? | ? | — | [@pp-manual-managing-tax][@parqet-pricing] |
| Look-through by sector, region or country | — | ◐ with data gaps | ✓ | ◐ paid | [@gf-allocations][@wf-home][@parqet-pricing] |
| Rule-based risk checks | ◐ indicators | ✓ 17 rules | ◐ risk lab | ◐ paid drawdown | [@pp-manual-dashboard][@gf-xray][@wf-home][@parqet-pricing] |
| FIRE projection | ✓ widget | ✓ | ✓ | — | [@pp-manual-dashboard][@gf-analysis][@wf-home][@parqet-pricing] |
| Privacy mode hiding absolute values | ? | ✓ | ? | — | [@gf-settings][@parqet-pricing] |
| Broker PDF import | ✓ 130 | ? | ? | ✓ over 50 | [@pp-repo-pdf][@parqet-pricing] |
| Import of PP data | n/a | — | — | — | [@gf-readme][@wf-home][@parqet-vs-pp] |
| Native phone app | ✓ | ◐ PWA | ✓ iOS | ✓ | [@pp-appstore-us][@gf-readme][@wf-docs-mobile][@parqet-apps] |

**Table stakes across the field:** income and dividend history, a phone
surface, performance views, allocation charts, and low-effort intake through
bank sync or PDF import [@pp-manual-dashboard][@parqet-pricing][@getquin-tracker][@ffc-page].
A dividend calendar appears in every consumer SaaS tracker checked
[@parqet-pricing][@getquin-dividends][@ffc-page][@snowball-appstore].
**Differentiators held by one or two products:** weighted categories (PP), rule
libraries (Ghostfolio's X-ray), FIRE projections (Ghostfolio, Wealthfolio, a PP
widget), privacy mode (Ghostfolio), tax reports (Sharesight, Parqet) and paid
look-through (Parqet)
[@pp-manual-managing-tax][@gf-xray][@wf-home][@gf-settings][@sharesight-blog][@parqet-pricing].

**Ghostfolio, tried directly.** The landing page names its reader in a "for you
if you are…" list and promises a three-step start beside a live demo
[@gf-landing]. X-ray ships 17 ready rules with thresholds, from currency and
account clusters to emergency fund and fee ratio [@gf-xray]. Allocations break
down by platform, currency, asset class, sector, continent, market, country,
account and ETF provider, with visible "no data" gaps [@gf-allocations].
Presenter View and Zen Mode hide sensitive figures [@gf-settings]. Read access
can be granted with an expiry [@gf-access]. A resources section runs 341
"open-source alternative to…" pages, including Parqet, getquin, Finanzfluss
Copilot and Wealthfolio, and none for Portfolio Performance [@gf-tools-pages].

## 2. Paradigms: deployment, phone access, sync, first run

| Product | Deployment | Phone | Sync | First run | Sources |
|---|---|---|---|---|---|
| Portfolio Performance | Desktop app writing a data file | Read-only companion app, local computation | The user's cloud drive | Install the app | [@pp-forum-app-launch][@pp-appstore-us] |
| Ghostfolio | Self-hosted Docker (PostgreSQL, Redis) or hosted Premium | Mobile-first PWA; third-party native iOS client using the instance token | One server | One compose command; live demo; CasaOS, Umbrel, Unraid, Home Assistant, Runtipi, TrueCharts, Easypanel | [@gf-readme][@scaryfolio] |
| Wealthfolio | Local-first desktop app (SQLite); official Docker web mode | iOS app with its own database; Android planned; web UI as PWA | Paid end-to-end-encrypted relay; self-hosted instances are peers | Single `docker run`; PikaPods, Unraid, Proxmox, Coolify | [@wf-readme][@wf-docs-mobile][@wf-docs-connect][@wf-home] |
| Actual Budget (budgeting analog) | Local-first, optional sync server | Installed web app, works offline, needs a server | The user's own server | Demo or desktop app first; PikaPods with a donated share | [@actual-install] |
| Parqet, getquin, Finanzfluss Copilot | Vendor cloud | Native iOS and Android apps | Vendor account, bank and broker sync | Sign-up | [@parqet-apps][@getquin-tracker][@ffc-page] |

**Findings.**

- **The switcher's status quo needs no server and no VPN.** A consumer cloud
  drive moves the file, the phone recomputes locally, and the sync experience is
  the drive's, not the app's [@pp-forum-app-launch][@pp-appstore-us].
- **Self-hosted peers answer the phone in two ways.** Ghostfolio relies on the
  PWA and leaves network reachability to the user; its README offers only
  reverse-proxy settings [@gf-readme][@scaryfolio]. Wealthfolio keeps a full
  database on each iPhone and syncs ciphertext through its paid relay, with the
  self-hosted web UI as the only documented route without it
  [@wf-docs-mobile][@wf-docs-connect]. An unofficial project re-implements that
  relay for self-hosting, a demand signal (low) [@wf-selfhosted-relay].
- **The documented no-exposure path is a tailnet.** Actual's HTTPS guide names
  Tailscale, or Caddy with a DNS challenge, for certificates without exposing the
  server [@actual-https]. Immich's remote-access guide recommends Tailscale when a
  router port cannot be opened, citing protection against zero-days
  [@immich-remote]. Tailscale Serve proxies a local port to tailnet devices only
  and provisions Let's Encrypt certificates automatically
  [@tailscale-serve][@tailscale-https]. The costs: every phone runs the Tailscale
  app, and machine names appear in public Certificate Transparency logs
  [@tailscale-https]. Whether an installed PWA works through Serve on iOS and
  Android was not evidenced.
- **Cloudflare Tunnel removes the VPN app and moves TLS termination to
  Cloudflare.** Cloudflare can then read requests, credentials included, and
  community voices treat that as the objection for private data (low: stale or
  undated sources) [@nextcloud-cf][@pluggie-cf].
- **First run is a solved pattern among self-hosted peers:** a live demo
  (Ghostfolio), one command, and listings in home-server app stores and managed
  hosts [@gf-readme][@wf-readme][@wf-home][@actual-install]. None states a setup
  time.

## 3. AI, agents and MCP

| | Wealthfolio | Ghostfolio | Community Ghostfolio server | Parqet |
|---|---|---|---|---|
| Since | v3.6.0, 2026-07-05 [@wf-releases] | 3.59.1, 2026-08-23, experimental [@gf-changelog] | registry entry since 2026-04 [@mcp-registry-folio] | first-party guides [@parqet-mcp] |
| Tools | 13 typed tools, 10 read and 3 write, shared with the in-app assistant [@wf-docs-ai] | 6: four reads, import, asset search [@gf-pr-7935] | 38–39, read and write [@gf-mcp-community] | read-only [@parqet-mcp] |
| Access control | Tokens with 7 read and 4 write scopes; a draft-only token can never commit [@wf-docs-mcp][@wf-olares] | Two access levels; the tool list shows only what the token may call [@gf-pr-7935] | Read-only mode, tag groups, tool search [@gf-mcp-community] | OAuth 2.0 [@parqet-mcp] |
| Audit | Agent-activity log with tool, outcome and token; can be switched off [@wf-docs-mcp] | none found [@gf-readme] | rate limits only [@gf-mcp-community] | ? |
| Client setup | Copy-paste entries for Claude Desktop, Cursor, Windsurf, Cline [@wf-docs-mcp] | no client example [@gf-readme] | `uvx`, pip, Docker [@gf-mcp-community] | hosted URL [@parqet-mcp] |
| MCP prompts or resources | none documented [@wf-docs-mcp] | none registered [@gf-pr-7935] | none documented [@gf-mcp-community] | ? |
| App calls a model itself | yes, the user's provider incl. Ollama [@wf-docs-ai] | yes, via OpenRouter [@gf-ai-service] | n/a | ? |

**Patterns worth studying.**

- **Draft and commit as separate token scopes.** A credential that can only
  stage changes enforces preview-then-apply at the auth layer [@wf-docs-mcp].
  Wealthfolio adds a rule that tool output and attachments cannot authorize a
  draft [@wf-release-370].
- **A tool list filtered by the token's scope,** so the agent sees only what it
  may call [@gf-pr-7935]. The community server goes further with tag groups and a
  search-then-call mode that hides the full list [@gf-mcp-community].
- **Small agent surfaces.** Peers expose six to thirteen tools
  [@gf-pr-7935][@wf-docs-ai]. Ghostfolio dropped a direct create-activity tool in
  favour of import [@gf-prs-mcp].
- **Copy-paste client configuration** is the cheapest onboarding aid on offer
  [@wf-docs-mcp].
- **Hosted commercial servers default to read-only with OAuth** (Parqet), and
  Agni Folio splits revocable read and write scopes (medium: directory source)
  [@parqet-mcp][@agni-glama]. AI-native entrants now register their own servers
  in the official registry, one of them advertising agent execution of
  human-approved changes [@mcp-registry-folio].

**Open ground.** No peer ships MCP prompts or resources over the user's own
ledger; the only finance server found with prompts works on market data alone
[@wf-docs-mcp][@gf-pr-7935][@fmp-prompts]. The advice boundary is thinly handled:
Wealthfolio says its assistant tells you "what you own, not what you should own"
[@wf-docs-ai], Ghostfolio's generated analysis prompt asks for "Optimization
Ideas" without a disclaimer [@gf-ai-service], and getquin markets questions such
as whether it is time to harvest losses [@getquin-ai].

**PP users are already wiring agents to their data.** Forum members feed PP's XML
to several models for written reports and publish MCP servers over it, one with
about 20 read-only functions; a default binding to all interfaces drew immediate
criticism [@pp-forum-ai]. One of them, pp-terminal, is an analytics companion
over the PP file with an MCP mode that never modifies the file [@pp-terminal].

## 4. Business models, positioning and user voice

| Product | Model | Paid price | What is paid for | Sources |
|---|---|---|---|---|
| Ghostfolio | AGPLv3, plus hosted Premium funding hosting, data and development | unverified ("from $48/yr" per an aggregator) | Hosting; a Premium-only data source | [@gf-readme][@gf-price-aggregator] |
| Wealthfolio | Free local core, optional Connect | $2.99, $7.99, $12.99 a month on the official page (aggregators list the entry tier at $3.99: disputed); a $24.99 tier announced | Encrypted sync, brokerage sync, household view; hosted AI and licensed data in the coming tier | [@wf-connect][@wf-price-aggregator] |
| Portfolio Performance | Free desktop, freemium phone app | EUR 3 a month or EUR 30 a year | Phone dashboards only | [@pp-appstore-de] |
| rotki | Tiered open core | not verified | Limits such as devices and database size | [@rotki-blog] |
| Parqet | Freemium SaaS | EUR 11.99 and EUR 29.99 a month | Dividend forecast and calendar, X-Ray, benchmark, tax dashboard | [@parqet-pricing] |

**Positioning.** Ghostfolio: "a privacy-first, open source dashboard for your
personal finances", for multi-platform buy-and-hold investors who value data
ownership [@gf-landing][@gf-readme]. Wealthfolio: "Grow Wealth. Keep Control.",
private and local on every device [@wf-home]. PP's phone app: a
privacy-preserving companion to the desktop [@pp-appstore-de]. Finanzfluss
Copilot stresses German servers [@ffc-page].

**User voice (thin).**

- **PP.** Seven of the forum's 50 top topics this year are about prices that
  stop updating. Broker imports (Trade Republic CSV, DEGIRO) and bookkeeping edge
  cases (spin-offs, splits, gifted shares) draw long threads, and users ask what
  figures such as invested capital mean [@pp-forum-top]. When the maintainer of
  the PDF importers stepped down in June 2026, replies feared entering bookings
  by hand [@pp-forum-farewell]. One top thread asks for research notes on a
  security [@pp-forum-top].
- **Alternatives.** Ghostfolio's top open issues are a failing data provider
  and a disputed performance calculation [@gf-issues]. Wealthfolio's
  most-discussed issues are wrong cash and transfer figures, including a release
  that broke calculations [@wf-issues]. Its Show HN praised the UI and the local
  model, and called missing automated sync a dealbreaker [@hn-wf]. Testers of a
  web app built on PP data checked valuations first and found them off
  [@pp-forum-quovibe].
- **Switchers.** No first-person statement from the last twelve months was
  found in either direction.

## Cross-dimension insights

1. **Correct numbers are the first trust test, and incumbents bleed there.**
   Testers check valuations first [@pp-forum-quovibe], the alternatives' top
   complaints are wrong figures [@gf-issues][@wf-issues], and PP users ask what
   their figures mean [@pp-forum-top]. A switcher will judge a new tool by
   whether its numbers match PP's and whether it can say why.
2. **Import is the lock-in, and nobody imports PP.** PP's extractor base is large
   and its users fear manual entry [@pp-repo-pdf][@pp-forum-farewell]. No peer
   page offers an import of PP data
   [@gf-readme][@wf-home][@parqet-vs-pp]. PP users build on the XML themselves
   instead [@pp-forum-ai][@pp-forum-quovibe]. A complete PP import is both the
   migration path and unclaimed ground.
3. **The phone is where self-hosting loses, and convenience at the edge is what
   people pay for.** SaaS peers and PP ship native apps; self-hosted peers answer
   with a PWA or a paid relay [@parqet-apps][@pp-appstore-us][@gf-readme][@wf-docs-connect].
   The paid parts across the field are phone dashboards, sync and brokerage
   links, hosting and data [@pp-appstore-de][@wf-connect][@gf-readme].
4. **The agent axis converged in one quarter, but not on memory, prompts or
   restraint.** Peers expose holdings, activities and accounts through six to
   thirteen tools, ship no prompts, call models in-app and handle the advice
   boundary thinly [@wf-docs-ai][@gf-pr-7935][@gf-ai-service]. What remains
   unclaimed: sourced memory the agent reads and writes under confirmation,
   prompts that carry the no-advice stance, and an app that never calls a model.
5. **The Portfolio Performance slot in discovery is empty.** Ghostfolio's 341
   comparison pages skip PP [@gf-tools-pages], Parqet's PP comparison dates from
   2020 [@parqet-vs-pp], and PP's own forum is where users discuss agents on PP
   data [@pp-forum-ai].

## Contrary evidence

The red-team pass did not run (off by configuration). Two counter-signals
surfaced during the run and deserve weight. PP users already build their own MCP
servers on the PP file, so part of the intended audience may prefer a thin
do-it-yourself bridge to a second application [@pp-forum-ai]. And Wealthfolio
already bundles an MCP server, an iOS app, a polished UI and optional sync
[@wf-docs-mcp][@wf-docs-mobile][@hn-wf], which is the closest existing answer to
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
