# Digest — D1 switcher parity — round 1 — assistant 1
Accessed: 2026-09-30

Method note: 8 sources fetched and read (PP App Store listing, PP manual "Using taxonomies", PP manual
"Managing taxonomies", Ghostfolio README, Ghostfolio CHANGELOG, wealthfolio.app, Parqet pricing,
Finanzfluss Copilot page). Claims marked "[search summary, page not fetched]" rest only on a search
engine's summary of the cited URL and carry at most medium confidence. Fetched pages were read through a
summarising fetch tool, so quotes are as extracted by that tool.

## Claims
| # | claim | source URL | publisher | pub_date (YYYY-MM[-DD] or "undated") | confidence (high/medium/low) | class (capability/pricing/positioning/sentiment/traction/trajectory) |
|---|---|---|---|---|---|---|
| 1 | PP's mobile app listing says it offers a statement of assets with charts, performance views and charts, an earnings view with yearly/monthly breakdowns, and taxonomies with pie charts and rebalancing data. | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG (App Store listing) | undated | high | capability |
| 2 | The PP mobile app is read-only for bookkeeping: its listing says "Edit and maintain your transaction history on the desktop, then view and analyze your investments on your device." | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG | undated | high | capability |
| 3 | The PP mobile app reads the same data file as the desktop, syncing via "iCloud, Google Drive, or OneDrive" and opening files "directly from OneDrive, Dropbox, Google Drive, and WebDAV". | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG | undated | high | capability |
| 4 | The PP mobile listing says financial data "remains confined to your phone, with all calculations performed locally", with AES256 encryption for password-protected files. | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG | undated | high | positioning |
| 5 | The PP mobile app is free with an optional Premium subscription (US store: USD 3.00 per month, USD 25.00 per year) that "unlocks dashboards". | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG | undated | high | pricing |
| 6 | The PP mobile listing states it supports "29 of the 46 dashboard widgets available in the desktop version", which puts the desktop dashboard at 46 widget types (desktop count not verified in desktop docs). | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG | undated | medium | capability |
| 7 | The PP mobile listing says users can build custom asset and performance charts with arbitrary data series. | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG | undated | medium | capability |
| 8 | The PP mobile listing showed version 1.13.0 dated "July 9" (year not shown in the extract) and a 4.2/5 rating from only 5 US-store ratings, so US-store traction evidence is thin. | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | MSM Mannheimer Software-Manufaktur UG | undated | medium | trajectory |
| 9 | A search summary of the PP forum announcement and store pages says the app is built with Flutter, is on both the Apple App Store and Google Play, and keeps wealth statement, performance calculation, charts, income statements, classifications with rebalancing data and price/FX updates free while dashboards need a subscription [search summary, page not fetched]. | https://forum.portfolio-performance.info/t/portfolio-performance-app-die-erste-version/27333 | Portfolio Performance community forum | undated | low | capability |
| 10 | The PP manual's navigation lists under View → Reports: Statement of Assets (Chart, Holdings), Performance (Dashboard, Calculation, Chart, Securities, Payments, Trades) and Taxonomies (Managing taxonomies, Using taxonomies). | https://help.portfolio-performance.info/en/reference/view/taxonomies/using-taxonomies/ | Portfolio Performance manual | 2025-05-15 | medium | capability |
| 11 | The PP manual states "you can assign a security to more than one category. The weight however should add up to 100%." | https://help.portfolio-performance.info/en/reference/view/taxonomies/managing-taxonomies/ | Portfolio Performance manual | 2026-09-03 | high | capability |
| 12 | The PP manual explains that "Setting the weight to 50% means only half of the security's value contributes" to a taxonomy category's actual value. | https://help.portfolio-performance.info/en/reference/view/taxonomies/using-taxonomies/ | Portfolio Performance manual | 2025-05-15 | high | capability |
| 13 | The PP manual says "The rebalancing process will calculate the target value for each category based on its allocation and the total portfolio value" and computes the delta when the actual value deviates (page older than the 3-month bar; living doc). | https://help.portfolio-performance.info/en/reference/view/taxonomies/using-taxonomies/ | Portfolio Performance manual | 2025-05-15 | high | capability |
| 14 | Neither PP taxonomy manual page read describes deriving classifications automatically from ETF/fund holdings, so no PP ETF look-through was found this run (absence on two pages, not proof of absence). | https://help.portfolio-performance.info/en/reference/view/taxonomies/managing-taxonomies/ | Portfolio Performance manual | 2026-09-03 | medium | capability |
| 15 | A search summary of PP's PDF-import manual page says PP reads PDF documents from "more than 90 banks and brokers" with one importer per institution, and the wizard lists the importers it tried when none matches [search summary, page not fetched]. | https://help.portfolio-performance.info/en/reference/file/import/pdf-import/ | Portfolio Performance manual | undated | medium | capability |
| 16 | Ghostfolio's README lists transaction create/update/delete, multi-account management, ROAI performance for Today/WTD/MTD/YTD/1Y/5Y/Max, "Various charts", "Static analysis to identify potential risks in your portfolio", transaction import/export, dark mode, "Zen Mode" and a mobile-first PWA. | https://github.com/ghostfolio/ghostfolio | Ghostfolio (GitHub README) | undated | high | capability |
| 17 | Ghostfolio's README names price data sources COINGECKO, GHOSTFOLIO [Premium], MANUAL and YAHOO, and ships as Docker Compose with PostgreSQL and Redis under AGPLv3. | https://github.com/ghostfolio/ghostfolio | Ghostfolio (GitHub README) | undated | high | capability |
| 18 | Ghostfolio's GitHub page showed about 9.4k stars and 1.3k forks at access time. | https://github.com/ghostfolio/ghostfolio | GitHub | 2026-09-30 | medium | traction |
| 19 | Ghostfolio's changelog shows releases 3.74.0 (2026-09-27), 3.75.0 (2026-09-28) and 3.76.0 (2026-09-30), i.e. several releases per week. | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-09-30 | high | trajectory |
| 20 | Ghostfolio's changelog entry 3.72.0 (2026-09-20) reads "Added tool to get watchlist to Model Context Protocol server", indicating Ghostfolio ships an MCP server (its scope was not verified). | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-09-20 | medium | trajectory |
| 21 | Ghostfolio's changelog entry 3.62.0 (2026-08-27) adds "support for dedicated OpenRouter engine for web_fetch tool", indicating LLM/agent tooling in the product (purpose not verified). | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-08-27 | low | trajectory |
| 22 | Ghostfolio's changelog shows a FIRE calculator (improved in 3.35.0, 2026-07-27) and wealth-projection data for a retirement date (2.223.0, 2025-12-07). | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-07-27 | medium | capability |
| 23 | Ghostfolio keeps adding static-analysis ("X-ray"-style) rules, e.g. an Emergency Fund "Coverage" rule (3.45.0, 2026-08-08) and a rule based on total investment (2.239.0, 2026-02-15). | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-08-08 | medium | trajectory |
| 24 | Ghostfolio 2.235.0 (2026-02-03) "Added ability to fetch top holdings for ETF assets from Yahoo", a partial ETF look-through. | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-02-03 | medium | capability |
| 25 | Ghostfolio has allocation charts by continent, country and sector (fixed in 3.65.0, 2026-08-31). | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-08-31 | medium | capability |
| 26 | Ghostfolio's performance chart carries a benchmark (calendar-year benchmark fix in 3.61.0, 2026-08-25). | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-08-25 | medium | capability |
| 27 | Ghostfolio has a watchlist (create dialog migrated in 3.69.0, 2026-09-07) and a "Presenter View" on its allocations page (2.253.0, 2026-04-06). | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-09-07 | medium | capability |
| 28 | Ghostfolio 3.75.0 (2026-09-28) "Extended net performance to include the dividends (experimental)". | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-09-28 | medium | trajectory |
| 29 | Ghostfolio has a Public API, extended in 3.9.0 (2026-06-12) with an endpoint to update asset profile data. | https://raw.githubusercontent.com/ghostfolio/ghostfolio/main/CHANGELOG.md | Ghostfolio (changelog) | 2026-06-12 | medium | capability |
| 30 | Neither Ghostfolio's README nor the changelog extract mentions importing Portfolio Performance files. | https://github.com/ghostfolio/ghostfolio | Ghostfolio | undated | low | capability |
| 31 | Wealthfolio's homepage lists investment and net-worth tracking, "Spending & Budgets", a "Performance Dashboard", a "Retirement & FIRE Planner" with a "Monte Carlo Risk Lab", a "Goals & Save-Up Planner", "Allocation Targets & Rebalance", income tracking for "dividends and interest income", "Contribution Limits" and an "AI Assistant". | https://wealthfolio.app/ | Wealthfolio | undated | high | capability |
| 32 | Wealthfolio advertises "asset allocation, sector exposure, and geographic distribution" views and says users can "benchmark against the S&P 500 or any ETF". | https://wealthfolio.app/ | Wealthfolio | undated | high | capability |
| 33 | Wealthfolio runs as a desktop app (macOS, Windows, Linux), on iPhone/iPad and self-hosted (Docker/Compose, Unraid, Proxmox, Coolify, PikaPods), and states "Your financial data is stored locally on your device." | https://wealthfolio.app/ | Wealthfolio | undated | high | positioning |
| 34 | Wealthfolio is "Free by default" and open source, imports "CSV statements from anywhere", and sells an optional "Wealthfolio Connect" subscription for "Automatic brokerage imports" and sync. | https://wealthfolio.app/ | Wealthfolio | undated | high | pricing |
| 35 | Wealthfolio offers add-ons including an "Investment Fees Tracker", a "Goal Progress Tracker" and a "Stock Trading Tracker". | https://wealthfolio.app/ | Wealthfolio | undated | medium | capability |
| 36 | Parqet's pricing page lists Basic (free), Plus (EUR 11.99 per month) and Investor (EUR 29.99 per month) tiers with a 14-day trial (billing cadence as extracted, not double-checked). | https://parqet.com/en/pricing | Parqet | undated | medium | pricing |
| 37 | Parqet reserves for paid tiers the dividend forecast, a personalized dividend calendar, "X-Ray" (extracted as ETF look-through), benchmark comparison, a tax dashboard, region/sector/country weight analysis, asset-class breakdown, drawdown risk analysis, a performance treemap and a "What-If" comparison, while Basic keeps a dashboard, performance analysis and a dividend dashboard. | https://parqet.com/en/pricing | Parqet | undated | medium | capability |
| 38 | Parqet lists PDF and CSV import for "over 50 brokers", automatic sync (limited on Basic), watchlists (1/5/15 by tier), integrations (2/5/20 by tier), 40+ currencies and iOS/Android apps on every tier. | https://parqet.com/en/pricing | Parqet | undated | medium | capability |
| 39 | Parqet's pricing page lists no import from Portfolio Performance, no privacy mode and no FIRE projection (single-page absence). | https://parqet.com/en/pricing | Parqet | undated | low | capability |
| 40 | Parqet publishes a "Parqet vs Portfolio Performance" page, i.e. it courts PP users directly [search result title, page not fetched; sales-facing]. | https://parqet.com/en/blog/parqet-vs-portfolio-performance | Parqet | undated | medium | positioning |
| 41 | getquin's dividend-tracker page describes a dividend calendar with cumulative payouts, future dividend forecasts, year-on-year growth and yield, plus payout notifications [search summary, page not fetched]. | https://www.getquin.com/dividend-tracker | getquin | undated | medium | capability |
| 42 | getquin says it aggregates brokers and bank accounts in one dashboard across stocks, ETFs, funds, crypto, real estate, collectibles, art, commodities and insurances, offers watchlists and per-stock performance, and imports via "secure API connections to more than 2,000 banks and brokers" [search summary, page not fetched]. | https://www.getquin.com/portfolio-tracker | getquin (site and App Store id1513629447) | undated | medium | capability |
| 43 | Finanzfluss Copilot's page promises a total-wealth overview ("Dein Gesamtvermögen im Überblick"), a "Dividenden Dashboard" with a "Dividendenkalender" and personal dividend yield, and tracking of stocks, ETFs, funds, crypto, real estate and commodities. | https://www.finanzfluss.de/copilot/ | Finanzfluss | undated | high | capability |
| 44 | Finanzfluss Copilot connects to "über 350 Anbieter" via automatic bank connections, alongside PDF import, manual entry and expense categorization. | https://www.finanzfluss.de/copilot/ | Finanzfluss | undated | high | capability |
| 45 | Finanzfluss Copilot offers iOS and Android apps and stresses German servers ("deutsche Server") and no data sales. | https://www.finanzfluss.de/copilot/ | Finanzfluss | undated | high | positioning |
| 46 | The Copilot landing page mentions no ETF look-through, risk check, FIRE projection, benchmark, tax feature, privacy mode, watchlist, pricing or PP import (landing-page absence only). | https://www.finanzfluss.de/copilot/ | Finanzfluss | undated | low | capability |
| 47 | Sharesight's own blog says its paid plans include a Taxable Income Report and a Capital Gains Report, and a Sold Securities Report shows total return on shares sold in a date range [search summary, page not fetched]. | https://sharesight.com/blog/3-ways-sharesight-helps-investors-at-tax-time | Sharesight (blog) | undated | medium | capability |
| 48 | A search summary of Sharesight's blog and a third-party review says Sharesight tracks dividends and corporate actions automatically, handles multiple currencies, compares against benchmarks and exports reports to Excel, PDF or Google Sheets [search summary, page not fetched; review site is secondary]. | https://sharesight.com/blog/5-ways-sharesight-makes-eofy-a-breeze | Sharesight (blog) / thecfoclub.com | undated | low | capability |
| 49 | Snowball Analytics' App Store listing describes consolidating multiple brokerage accounts and a calendar for dividend and coupon income with expected and actual payments, amortizations and redemptions [search summary, page not fetched]. | https://apps.apple.com/app/snowball-analytics/id6463484375 | Snowball Analytics (App Store listing) | undated | medium | capability |
| 50 | Snowball's pages say it tracks dividend yield and dividend growth, the share of profit spent on broker commissions, annualized returns, and local- versus foreign-currency profit [search summary, page not fetched]. | https://snowball-analytics.com/portfolio-tracker | Snowball Analytics | undated | low | capability |
| 51 | Snowball claims automatic connection to "over 1,000 brokers" worldwide and a free plan limited to one portfolio [search summary, page not fetched]. | https://help.snowball-analytics.com/dividend-tracker | Snowball Analytics | undated | low | pricing |

## Feature matrix
Cells: yes / partial / no / unknown, then claim #s. "nf" = looked for on the page read and not found
(treated as unknown, not as no).

| Feature | PP desktop | PP mobile | Ghostfolio | Wealthfolio | Parqet | getquin | FF Copilot | Sharesight | Snowball |
|---|---|---|---|---|---|---|---|---|---|
| Wealth / statement-of-assets overview | yes (10) | yes (1) | partial: multi-account, charts (16) | yes (31) | yes (37) | yes (42) | yes (43) | unknown | partial: consolidated accounts (49) |
| Performance view / return metrics | yes (10) | yes (1) | yes: ROAI (16) | yes (31) | yes (37) | partial (42) | partial (43) | yes (48) | yes: annualized (50) |
| Performance calculation breakdown | partial: "Calculation" nav entry only (10) | partial (9) | unknown | unknown | unknown | unknown | unknown | unknown | partial: commissions/FX split (50) |
| Configurable dashboards / widgets | yes: 46 widget types (6, 10) | yes, Premium: 29 of 46 (5, 6) | unknown | partial: "Performance Dashboard" (31) | partial: basic vs full (37) | partial (42) | partial (43) | unknown | unknown |
| Earnings / dividend history | yes: "Payments" (10) | yes (1) | yes (28) | yes (31) | yes (37) | yes (41) | yes (43) | yes (48) | yes (49, 50) |
| Dividend calendar | unknown | unknown | unknown | unknown | yes; personalized on paid (37) | yes (41) | yes (43) | unknown | yes (49) |
| Dividend forecast | unknown | unknown | unknown | unknown | yes, paid (37) | yes (41) | unknown | unknown | partial: expected payments (49) |
| Allocation by asset class / region / sector | yes, via taxonomies (10-13) | yes (1) | yes (25) | yes (32) | yes, paid (37) | unknown | unknown (nf 46) | unknown | unknown |
| Weighted split of ONE security across categories | yes (11, 12) | partial: displays desktop taxonomies (1, 3); weights unverified | unknown | unknown | unknown (nf 39) | unknown | unknown | unknown | unknown |
| ETF look-through (fund holdings) | unknown (nf 14) | unknown | partial: ETF top holdings (24) | unknown | yes, paid "X-Ray" (37) | unknown | unknown (nf 46) | unknown | unknown |
| Rebalancing vs. target weights | yes (13) | yes: rebalancing data (1) | unknown | yes (31) | unknown | unknown | unknown | unknown | unknown |
| Trades / realized gains | yes: "Trades" (10) | unknown | unknown | partial: add-on (35) | partial: tax dashboard, paid (37) | unknown | unknown | yes (47) | unknown |
| Benchmark comparison | unknown | unknown | yes (26) | yes (32) | yes, paid (37) | unknown | unknown (nf 46) | yes (48) | unknown |
| Rule-based risk checks ("X-ray") | unknown | unknown | yes (16, 23) | partial: Monte Carlo Risk Lab (31) | partial: drawdown analysis, paid (37) | unknown | unknown (nf 46) | unknown | unknown |
| FIRE / projection / goals | unknown | unknown | yes (22) | yes (31) | unknown (nf 39) | unknown | unknown (nf 46) | unknown | unknown |
| Tax reports | unknown | unknown | unknown | partial: contribution limits (31) | yes, paid (37) | unknown | unknown (nf 46) | yes (47) | unknown |
| Privacy mode hiding absolute values | unknown | unknown (file encryption only, 4) | partial: Zen Mode, Presenter View; hiding behaviour unverified (16, 27) | unknown | unknown (nf 39) | unknown | unknown (nf 46) | unknown | unknown |
| Watchlists | unknown | unknown | yes (27) | unknown | yes: 1/5/15 by tier (38) | yes (42) | unknown (nf 46) | unknown | unknown |
| Heatmap / treemap | unknown | unknown | unknown | unknown | yes, paid treemap (37) | unknown | unknown | unknown | unknown |
| PDF import of broker statements | yes: >90 banks/brokers (15) | no: read-only (2) | unknown | unknown | yes: >50 brokers (38) | unknown | yes (44) | unknown | unknown |
| CSV import | unknown | no: read-only (2) | partial: import/export, format not named (16) | yes (34) | yes (38) | unknown | unknown | unknown | unknown |
| Import from PP | n/a | yes: same data file (3) | unknown (nf 30) | unknown | unknown (nf 39; vs-PP page 40) | unknown | unknown (nf 46) | unknown | unknown |
| Broker / bank sync | unknown | no: read-only (2) | unknown | yes, paid "Connect" (34) | yes; limited on Basic (38) | yes: >2,000 (42) | yes: >350 (44) | unknown | yes: >1,000 (51) |
| Mobile app | n/a | yes: iOS + Android (1, 9) | partial: PWA (16) | yes: iPhone/iPad (33) | yes (38) | yes (42) | yes (45) | unknown | yes (49) |
| Local-first / self-hosted | yes: local data file (3) | yes: local computation (4) | yes (17) | yes (33) | unknown (hosted tiers implied, 36) | unknown | no: German servers (45) | unknown | unknown |
| API / MCP / LLM surface | unknown | unknown | yes: Public API, MCP server, LLM tooling (20, 21, 29) | partial: "AI Assistant" (31) | partial: integrations (38) | unknown | unknown | unknown | unknown |

## Table stakes vs. differentiators

Table stakes (evidenced in most products read):
- Dividend / income history is in every column with evidence (1, 10, 28, 31, 37, 41, 43, 48, 49).
- A mobile surface exists for 7 of 8 products (1, 9, 16, 33, 38, 42, 45, 49); Sharesight unknown.
- A performance view with return figures is universal where evidenced (1, 10, 16, 31, 37, 48, 50).
- Cheap data intake: every SaaS peer leads with automated sync (38, 42, 44, 51), PP leads with PDF import (15), self-hosted peers at least with CSV/file import (16, 34); Wealthfolio monetises sync (34).
- Allocation by asset class / region / sector appears in PP, Ghostfolio, Wealthfolio and Parqet (10-13, 25, 32, 37); unknown elsewhere, not "no".
- A dividend calendar is in all four consumer-SaaS dividend trackers (37, 41, 43, 49) but was not evidenced for PP, Ghostfolio or Wealthfolio.
- Benchmark comparison appears in four products (26, 32, 37, 48); PP not verified this run.

Differentiators (one or two products each):
- Weighted assignment of one security to several categories is evidenced only for PP (11, 12); Parqet substitutes a paid fund look-through (37), Ghostfolio a partial ETF top-holdings fetch (24).
- Rebalancing against target weights with a per-category delta: PP and Wealthfolio (13, 31).
- Rule-based risk checks ("X-ray"): Ghostfolio only (16, 23); Parqet's is drawdown analysis (37).
- FIRE / retirement projection: Ghostfolio and Wealthfolio (22, 31), the latter with a Monte Carlo view (31).
- Tax reporting: Sharesight and Parqet (37, 47), jurisdiction-specific.
- Privacy / presenter mode: Ghostfolio only (16, 27).
- LLM surfaces: Ghostfolio's MCP server and LLM tooling (20, 21) and Wealthfolio's "AI Assistant" (31) mean an API + MCP surface is no longer unique among self-hosted trackers, if claim 20 holds.
- Parqet-only paid views: performance treemap and "What-If" comparison (37).

What a PP switcher would look for first (PP-specific evidence):
- PDF import breadth, more than 90 banks/brokers (15), against Parqet's "over 50 brokers" (38).
- Weighted multi-category taxonomies (11, 12) feeding rebalancing deltas (13).
- The Performance sub-views Calculation, Payments and Trades (10).
- Configurable dashboards with 46 widget types (6).
- A mobile companion that reads the same file, computes locally and is free except dashboards (1-5).

## Leads worth chasing
1. Ghostfolio's MCP server: first release, tool list, auth model, read-only or read-write, plus what the OpenRouter/web_fetch tool does (20, 21); single primary source so far, no second publisher.
2. Wealthfolio's "AI Assistant": local or external model, what data it can see (31); check Wealthfolio's GitHub releases for trajectory.
3. PP desktop gaps: content of the performance "Calculation" view, the 46-widget list, heatmap, benchmark, watchlists, CSV import and price-feed providers (6, 10); PP GitHub releases for trajectory.
4. PP-file import in peers: read the Parqet vs PP page as a sales-facing claim to verify (40), and Ghostfolio/Wealthfolio import docs; a migration path is a switcher's first question.
5. ETF look-through at getquin, Finanzfluss Copilot and Snowball, and Parqet's X-Ray docs to see what it derives (37).
6. Primary feature and pricing pages for Sharesight, Snowball and getquin (47-51 rest on search summaries).

## Looked for, could not find
- PP manual "reference/view/" index returned HTTP 404; the PP view inventory comes only from one page's navigation (10).
- Ghostfolio's features page (ghostfol.io/en/features) is client-rendered; the fetch returned only a title, so Ghostfolio evidence comes from README and changelog (16-29).
- PP desktop heatmap, benchmark comparison, watchlists, CSV import and price data sources were not evidenced this run (not shown in the nav extract; not proof of absence).
- The content of PP's performance "Calculation" breakdown (only its nav entry, 10).
- The PP mobile Google Play listing and Android pricing (only a search summary, 9).
- Any peer importing PP files: not found in any source read (30, 39, 46).
- Weighted multi-category assignment in any peer: not found (39); no other peer page addressed it.
- A privacy mode in any product except Ghostfolio (16, 27).
- Pricing for Finanzfluss Copilot, getquin and Sharesight; Snowball only as "free plan = one portfolio" (51).
- The first Snowball query returned Snowplow Analytics results (irrelevant) and was re-run.
- Freshness: every vendor page read was undated (living pages, accessed 2026-09-30); the PP "Using taxonomies" page (2025-05-15) is older than the 3-month bar, but the key weighted-assignment claim is confirmed by the 2026-09-03 page (11); the rebalancing quote (13) rests on the older page only.
- Two-source bar: no independent second publisher was found for any differentiation-bearing claim (11, 15, 20, 37); PP's two manual pages share one publisher.
