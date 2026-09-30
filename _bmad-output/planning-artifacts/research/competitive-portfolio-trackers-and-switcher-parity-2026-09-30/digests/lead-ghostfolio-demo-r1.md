# Digest — hands-on: Ghostfolio live demo — round 1 — lead

Accessed: 2026-09-30. Method: the lead clicked through Ghostfolio's public
landing page and its **Live Demo** account at ghostfol.io in a browser. No
account was created and nothing was entered. Every claim below is an
observation of the live product on that date (publication date "undated, live
app"); the demo is Ghostfolio's hosted edition and may differ from a
self-hosted install.

## Claims

| # | claim | source URL | publisher | pub_date | confidence | class |
|---|---|---|---|---|---|---|
| H1 | The landing page positions Ghostfolio as "a privacy-first, open source dashboard for your personal finances", under the headline "Manage your wealth like a boss". | https://ghostfol.io/en | Ghostfolio | undated, live 2026-09-30 | high | positioning |
| H2 | The landing page carries an explicit "Ghostfolio is for you if you are…" list: trading on multiple platforms, buy-and-hold, interested in portfolio composition, valuing privacy and data ownership, minimalism, diversification, financial independence, "saying no to spreadsheets". | https://ghostfol.io/en | Ghostfolio | undated, live 2026-09-30 | high | positioning |
| H3 | The landing page promises "Get started in only 3 steps" (sign up anonymously with no e-mail address nor credit card, add historical transactions, get insights) and places a "Live Demo" button next to "Get Started". | https://ghostfol.io/en | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H4 | The landing page displays self-reported traction: 1,930 monthly active users, 9,388 GitHub stars and 3,411,102 Docker Hub pulls. | https://ghostfol.io/en | Ghostfolio | undated, live 2026-09-30 | medium (self-reported, single source) | traction |
| H5 | The home view is one net-worth chart and one large total with absolute and percentage change; its sub-views are Overview, Holdings, Summary, Watchlist and Markets. | https://ghostfol.io/en/home | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H6 | The Analysis view shows KPI cards (total, change and performance including currency effect), a performance chart with a "Compare with…" benchmark selector, asset versus currency performance, net performance labelled ROAI, top and bottom performers, portfolio evolution, a monthly/yearly investment timeline with "current streak" and "longest streak" counters, and a monthly/yearly dividend timeline. | https://ghostfol.io/en/portfolio | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H7 | X-ray "uses static analysis to uncover potential issues and risks in the portfolio": 17 built-in rules in the groups liquidity (buying power), emergency fund (setup, coverage), currency cluster risk, asset-class cluster risk (target ranges), account cluster risk, economic-market cluster risk (developed/emerging), regional-market cluster risk (Asia-Pacific, emerging markets, Europe, Japan, North America) and fees (fee ratio), summarised as "7 out of 17 rules align with the portfolio". | https://ghostfol.io/en/portfolio/x-ray | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H8 | The Allocations view shows donut charts by platform, currency, asset class, holding, sector, continent, market (developed/emerging/other), country, account and ETF provider; in the demo part of the market split reads "No data available". | https://ghostfol.io/en/portfolio/allocations | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H9 | The FIRE view is a calculator (monthly savings rate, annual interest rate, retirement date, projected total) plus a "sustainable retirement income" figure at a 4 % safe withdrawal rate. | https://ghostfol.io/en/portfolio/fire | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H10 | The Summary view lists time in market, activity count, buys and sells, invested capital, gross and net performance, fees, ROAI, total assets, holdings, cash, amounts excluded from analysis, liabilities, net worth, annualized performance, emergency fund, interest and dividends. | https://ghostfol.io/en/home/summary | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H11 | The Markets view shows a fear-and-greed style "current market mood" score and a list of indices and assets with their last all-time high and the change from it, noting that calculations use delayed market data. | https://ghostfol.io/en/home/markets | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H12 | Settings offer Presenter View ("protection for sensitive information like absolute performances and quantity values"), Zen Mode ("distraction-free experience for turbulent times"), biometric sign-in, experimental features, data export, base currency, language and locale. | https://ghostfol.io/en/account | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H13 | The Access tab generates a security token and grants access to others: a public "restricted view" and a named grantee with "view" permission, each with an expiration date. | https://ghostfol.io/en/account/access | Ghostfolio | undated, live 2026-09-30 | high | capability |
| H14 | The Resources section has FAQ, guides, markets and a glossary, plus 341 "open-source alternative to <product>" comparison pages, including Parqet, getquin, Finanzfluss Copilot, Sharesight, Snowball Analytics, Wealthfolio, Kubera, Empower and Maybe Finance — and none for Portfolio Performance. | https://ghostfol.io/en/resources/personal-finance-tools | Ghostfolio | undated, live 2026-09-30 | high | positioning |
| H15 | No AI or "copy prompt" feature was visible in the demo's Analysis view or menus (the user menu offers only "My Ghostfolio" and "Log out"). | https://ghostfol.io/en/portfolio | Ghostfolio | undated, live 2026-09-30 | medium (absence in the demo is not absence in the product) | capability |

## Observations for the decision (lead's reading, not claims)

- **A "for you if…" list and a 3-step start** are exactly what a newcomer reads
  in fifteen seconds (H2, H3).
- **Opinionated defaults**: X-ray ships 17 ready rules with thresholds (H7);
  the user does not author rules before seeing value.
- **Privacy toggles as first-class settings** (Presenter View, Zen Mode, H12)
  — cheap, and useful for screenshots and demos.
- **Look-through allocation** by sector, country and market is presented as a
  standard view (H8), though with visible data gaps.
- **Programmatic comparison pages** are a discoverability engine (H14); the
  Portfolio Performance slot is empty.

## Leads worth chasing

- Which data source feeds sector/country/market exposure for ETFs, and is it
  available self-hosted or only with Premium?
- Are Presenter View and Zen Mode in the self-hosted edition too?
- Does Ghostfolio have AI features behind "Experimental Features"?
- Mobile: is Ghostfolio installable as a PWA, and is there a native app?

## Looked for, could not find

- An AI or prompt feature in the demo (H15).
- A comparison page against Portfolio Performance (H14).
