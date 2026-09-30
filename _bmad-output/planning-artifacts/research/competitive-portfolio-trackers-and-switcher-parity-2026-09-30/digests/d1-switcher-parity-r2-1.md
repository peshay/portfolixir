# Digest — D1 switcher parity — round 2 — assistant 1
Accessed: 2026-09-30

Budget used: 16 tool calls before writing; 9 URL fetches over 8 distinct sources (PP's
repository directory was read twice, through two GitHub API endpoints, because the first
response was truncated). Claims marked "search summary" rest on search-result text for a
manual page that was not fetched, and are rated at most medium.

## Claims
| # | claim | source URL | publisher | pub_date (YYYY-MM[-DD] or "undated") | confidence (high/medium/low) | class (capability/pricing/positioning/sentiment/traction/trajectory) |
|---|---|---|---|---|---|---|
| 1 | PP's Performance report has six sub-views: Dashboard, Calculation, Chart, Securities, Payments and Trades. | https://help.portfolio-performance.info/en/reference/view/reports/performance/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 2 | The Calculation view walks the reporting period from initial value through unrealized capital gains (shown separately from currency effects), realized capital gains, earnings (dividends and interest), fees and taxes, cash currency gains and performance-neutral transfers (deposits, removals, deliveries) to final value. | https://help.portfolio-performance.info/en/reference/view/reports/performance/calculation/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 3 | The Calculation view has expandable categories, can be restricted to a portfolio, one securities account or a custom account combination, offers FIFO or moving-average cost methods and a pre-tax view, and exports to CSV. | https://help.portfolio-performance.info/en/reference/view/reports/performance/calculation/ | Portfolio Performance project (manual) | 2026-09-03 | medium | capability |
| 4 | PP's manual names true time-weighted rate of return (TTWROR, cumulative, with an annualized variant as a dashboard widget), internal rate of return (IRR, money-weighted), absolute change and delta (value change net of external cash flows) as its performance measures. | https://help.portfolio-performance.info/en/reference/view/reports/performance/ ; https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 5 | The manual defines IRR as annualized by definition and TTWROR as computed per reporting period and therefore possibly unannualized (search summary). | https://help.portfolio-performance.info/en/concepts/performance/ | Portfolio Performance project (manual) | undated (not fetched) | medium | capability |
| 6 | Documented risk indicators are maximum drawdown, maximum drawdown duration, volatility (standard deviation of daily returns) and semideviation, and the dashboard adds current drawdown, a drawdown chart and a Sharpe ratio widget. | https://help.portfolio-performance.info/en/reference/view/reports/performance/ ; https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 7 | In the Securities performance report, per-security IRR and TTWROR exist as columns that are hidden by default and enabled through the column chooser (search summary). | https://help.portfolio-performance.info/en/reference/view/reports/performance/securities/ | Portfolio Performance project (manual) | undated (not fetched) | medium | capability |
| 8 | The dashboard manual page groups widgets into six categories: Common, Statement of Assets, Performance, Risk indicators, Earnings and Trades. | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 9 | Performance widgets include TTWROR (cumulative and annualized), IRR, a performance-calculation table, Top Contributors, Top Performers, a performance chart, a monthly-returns heatmap, a yearly-returns heatmap, portfolio tax rate and portfolio fee rate. | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 10 | Statement-of-Assets widgets include total, absolute change, delta variants, performance-neutral transfers, invested capital, a FIRE calculation, a ratio widget, a statement-of-assets chart, holdings and taxonomy pie charts, target value allocation, an actual-versus-target allocation bar chart and all-time high. | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 11 | Earnings widgets include a transactions overview, a monthly earnings table, upcoming dividends, monthly/quarterly/yearly earnings bar charts and earnings by taxonomy, and Trades widgets include trade counts with profit/loss, trade profit/loss, average holding period, portfolio turnover rate and monthly investment/fee/tax tables. | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 12 | Common widgets include heading, description, current date, a collapsible section, exchange rate, trading activity, security limit-price/date/event widgets, latest price, distance from all-time high, an embedded website and a vertical spacer. | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 13 | The dashboard manual page states no total number of widget types. | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 14 | The dashboard page describes several dashboards, a column layout, per-widget reporting periods and data-series selection. | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | 2026-09-03 | medium | capability |
| 15 | Performance > Chart can plot accounts, securities or the whole portfolio (before or after taxes) against a benchmark security or index, such as the S&P 500, on a percentage axis, and a benchmark needs nothing but historical prices. | https://help.portfolio-performance.info/en/how-to/benchmarking/ | Portfolio Performance project (manual) | 2026-09-03 | high | capability |
| 16 | A benchmark line starts at 0% only if its price history covers the start of the reporting period. | https://help.portfolio-performance.info/en/how-to/benchmarking/ | Portfolio Performance project (manual) | 2026-09-03 | medium | capability |
| 17 | The manual's price-download guide lists these sources: Portfolio Performance (built-in), Yahoo Finance, Alpha Vantage, EOD Historical Data, Finnhub, Leeway, Twelve Data, Quandl, JSON, CSV file and Table on Website. | https://help.portfolio-performance.info/en/how-to/downloading-historical-prices/ | Portfolio Performance project (manual) | 2025-08-08 | medium | capability |
| 18 | The same guide recommends only the built-in provider, Yahoo Finance or JSON for a typical portfolio. | https://help.portfolio-performance.info/en/how-to/downloading-historical-prices/ | Portfolio Performance project (manual) | 2025-08-08 | medium | capability |
| 19 | The same guide covers importing historical prices from a CSV file (its example downloads one from Investing.com) and also names Morningstar, Kaggle and NASDAQ, whose role (built-in feed or website to source data from) the fetched text left unclear. | https://help.portfolio-performance.info/en/how-to/downloading-historical-prices/ | Portfolio Performance project (manual) | 2025-08-08 | low | capability |
| 20 | The manual says Alpha Vantage, Finnhub and Quandl have changed their offerings and are less useful as free services, with the free Alpha Vantage key limited to 25 requests per day (search summary). | https://help.portfolio-performance.info/en/how-to/downloading-historical-prices/alpha-vantage/ | Portfolio Performance project (manual) | undated (not fetched) | low | capability |
| 21 | PP has watchlists: manual groupings of securities created via File > New > Watchlist, listed under All Securities with the same column settings, fillable by drag-and-drop, and usable to limit price updates to their securities (search summary). | https://help.portfolio-performance.info/en/reference/file/new/ ; https://help.portfolio-performance.info/en/reference/online/ | Portfolio Performance project (manual) | undated (not fetched) | medium | capability |
| 22 | The manual has a dedicated CSV-import reference page (existence only; contents not read). | https://help.portfolio-performance.info/en/reference/file/import/csv-import/ | Portfolio Performance project (manual) | undated (not fetched) | low | capability |
| 23 | The latest PP desktop release on GitHub as of 2026-09-30 is 0.87.0, dated 2026-08-16. | https://github.com/portfolio-performance/portfolio/releases | Portfolio Performance project (GitHub releases) | 2026-08-16 | high | trajectory |
| 24 | Release 0.87.0 added lot-based trade grouping, collapsible statement-of-assets categories and adjustable line widths in price charts. | https://github.com/portfolio-performance/portfolio/releases | Portfolio Performance project (GitHub releases) | 2026-08-16 | medium | trajectory |
| 25 | Release 0.86.0 added a Rebalancing view with cash-flow allocation, CSV import/export of custom security attributes and a moving-average cost-basis column. | https://github.com/portfolio-performance/portfolio/releases | Portfolio Performance project (GitHub releases) | 2026-07-16 | medium | trajectory |
| 26 | Release 0.85.0 added dashboard reordering, an ownership percentage for grouped accounts and a manual-entry mode for unrecognized PDFs, and 0.84.0 added a collapsible dashboard section widget. | https://github.com/portfolio-performance/portfolio/releases | Portfolio Performance project (GitHub releases) | 2026-07-07; 2026-06-03 | medium | trajectory |
| 27 | Release 0.83.0 added Top Contributors and FIRE calculation dashboard widgets, both of which the 2026-09-03 dashboard manual page lists. | https://github.com/portfolio-performance/portfolio/releases ; https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (GitHub releases; manual) | 2026-04-12 | high | trajectory |
| 28 | Releases 0.83.1 and 0.83.2 added a Trade Republic CSV interface for the complete transaction history and a Scalable Capital CSV template. | https://github.com/portfolio-performance/portfolio/releases | Portfolio Performance project (GitHub releases) | 2026-04-15; 2026-04-19 | medium | trajectory |
| 29 | Nearly every release from April to August 2026 reports new or enhanced PDF importers, including new St. Galler and Thurgauer Kantonalbank importers in 0.86.0 and 0.86.1, both of which appear as extractor files in the repository. | https://github.com/portfolio-performance/portfolio/releases ; https://api.github.com/repos/portfolio-performance/portfolio/git/trees/master:name.abuchen.portfolio/src/name/abuchen/portfolio/datatransfer/pdf | Portfolio Performance project (GitHub releases; repository) | 2026-04-12 to 2026-08-16 | high | trajectory |
| 30 | PP's repository (master, read 2026-09-30) holds 130 institution-named files with the suffix PDFExtractor.java in its PDF import package, excluding the abstract base class, plus two more institution-named extractor files (Hargreaves Lansdown, Schelhammer Capital Bank). | https://api.github.com/repos/portfolio-performance/portfolio/git/trees/master:name.abuchen.portfolio/src/name/abuchen/portfolio/datatransfer/pdf | Portfolio Performance project (GitHub repository) | undated (read 2026-09-30) | medium | capability |
| 31 | A first, truncated read of the same directory through GitHub's contents API returned the same first 73 entries in the same order as the complete git-trees read. | https://api.github.com/repos/portfolio-performance/portfolio/contents/name.abuchen.portfolio/src/name/abuchen/portfolio/datatransfer/pdf | Portfolio Performance project (GitHub repository) | undated (read 2026-09-30) | high | capability |
| 32 | Parqet's comparison page claims PP lacks a unified dashboard overview, online and mobile access, community sharing and automated PDF import, and that PP's interface overwhelms beginners. | https://parqet.com/en/blog/parqet-vs-portfolio-performance | Parqet (vendor blog) | 2020-02-04 | low | positioning |
| 33 | The same page praises PP as a recommendable open-source tool and calls it "the de-facto standard in Germany" for investors, without a source for that standing. | https://parqet.com/en/blog/parqet-vs-portfolio-performance | Parqet (vendor blog) | 2020-02-04 | low | positioning |
| 34 | The same page does not mention any way to import PP data or files into Parqet. | https://parqet.com/en/blog/parqet-vs-portfolio-performance | Parqet (vendor blog) | 2020-02-04 | medium | capability |
| 35 | The same page says Parqet's core is free and a Plus subscription unlocks extra portfolios and watchlists, without stating prices. | https://parqet.com/en/blog/parqet-vs-portfolio-performance | Parqet (vendor blog) | 2020-02-04 | low | pricing |
| 36 | The manual has a Statement of Assets chart reference page, and the dashboard offers a statement-of-assets chart widget. | https://help.portfolio-performance.info/en/reference/view/reports/statement/statement-chart/ ; https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | undated (chart page not fetched); 2026-09-03 | medium | capability |
| 37 | Portfolio tax rate is defined as taxes over (realized and unrealized capital gains plus earnings minus fees) and fee rate as fees over (realized and unrealized capital gains plus earnings) (search summary; exact source page uncertain). | https://help.portfolio-performance.info/en/reference/view/reports/performance/dashboard/ | Portfolio Performance project (manual) | undated (search summary) | low | capability |

## PP desktop feature inventory

**Statement of assets**
- Statement-of-assets chart, as a report page and a dashboard widget — evidenced (#36, #10).
- Holdings and taxonomy pie charts, invested capital, all-time high, FIRE calculation — evidenced (#10).
- Collapsible categories in the statement of assets — evidenced as a 0.87.0 addition (#24).
- Asset-allocation history (category shares over time) — not found; what the statement-of-assets chart plots was not read.

**Performance**
- Six sub-views: Dashboard, Calculation, Chart, Securities, Payments, Trades — evidenced (#1).
- Calculation breakdown: initial value, unrealized capital gains (currency-separated), realized gains, earnings, fees and taxes, cash currency gains, performance-neutral transfers, final value — evidenced (#2). Whether fees and taxes are one line or two — not resolved.
- Calculation filters, FIFO/moving-average cost methods, pre-tax view, CSV export — evidenced, medium (#3).
- Return measures: TTWROR (cumulative and annualized), IRR, absolute change, delta — evidenced (#4, #5).
- Risk: maximum and current drawdown, drawdown duration, volatility, semideviation, Sharpe ratio, drawdown chart — evidenced (#6).
- Per-security IRR/TTWROR columns, hidden by default — evidenced, search summary only (#7); moving-average cost-basis column added in 0.86.0 (#25). The full column list of the securities table — not found.
- Portfolio tax rate and fee rate — widgets evidenced (#9); formulas thin (#37).

**Earnings / payments**
- Payments sub-view exists — evidenced (#1); its per-month/per-year layout — not read.
- Monthly/quarterly/yearly earnings charts, monthly earnings table, upcoming dividends, earnings by taxonomy — evidenced (#11).

**Trades**
- Trades sub-view — evidenced (#1); lot-based trade grouping added in 0.87.0 (#24).
- Average holding period, turnover rate and trade profit/loss widgets — evidenced (#11). A per-trade holding-period column in the Trades view — not found (page not read).

**Taxonomies / rebalancing**
- Weighted assignment and rebalancing deltas — carried over from round 1, not re-checked this round.
- Target value allocation and actual-versus-target bar chart widgets — evidenced (#10).
- A dedicated Rebalancing view with cash-flow allocation (0.86.0) — evidenced from release notes only, medium (#25); no manual page read.

**Dashboards / widgets**
- Six widget categories — evidenced (#8).
- Returns heatmap: yes, monthly and yearly — evidenced (#9).
- Earnings per year (bar chart), drawdown chart, key indicators (TTWROR, IRR, drawdown, volatility, Sharpe) — evidenced (#6, #9, #11).
- Several dashboards, columns, per-widget periods — evidenced, medium (#14); reordering added in 0.85.0, collapsible sections in 0.84.0 (#26).
- Total widget count — not stated by the manual (#13). My tally of the category lists in #6 and #9–#12 comes to at least fifty named entries, depending on how variants are grouped, so the round-1 figure of 46 widget types stays unverified and may be dated.

**Charts / benchmarks**
- Benchmark comparison in Performance > Chart against any security or index with prices, portfolio series before or after taxes, percentage axis — evidenced (#15, #16).
- Adjustable line widths in price charts (0.87.0) — evidenced, medium (#24).
- A benchmark inside heatmap or other widgets — not found.

**Watchlists**
- Watchlists exist (File > New > Watchlist, drag-and-drop, price updates scoped to a watchlist) — evidenced, search summary only (#21).

**Import**
- PDF: 130 institution-named PDF extractors in the repository (#30, #31); new or enhanced importers in nearly every recent release (#29); manual entry for unrecognized PDFs (#26).
- CSV: a CSV-import reference page exists (#22); broker-specific CSV paths for Trade Republic and Scalable Capital (#28); custom security attributes (#25); historical prices from CSV (#19). The full list of CSV import types — not found.

**Prices**
- Built-in PP feed, Yahoo Finance, Alpha Vantage, EOD Historical Data, Finnhub, Leeway, Twelve Data, Quandl, JSON, CSV, Table on Website — evidenced, medium; the guide is dated 2025-08-08, older than the freshness bar (#17, #18, #20).
- CoinGecko, ECB or central-bank FX feeds, crypto-exchange feeds — not found on the fetched guide.

**Currency**
- Cash currency gains and currency-separated capital gains in Calculation (#2); an exchange-rate widget (#12). Reporting-currency conversion mechanics — not researched.

**Export**
- CSV export of the Calculation view (#3). Other report exports — not found (the File > Export page was not read).

**Switcher angle (vendor copy)**
- Parqet's comparison page is from 2020 (#32–#35). Two of its claims do not describe today's PP: the no-dashboard claim is contradicted by the 2026-09-03 dashboard page (#8–#12), and the limited-PDF-import claim by the repository's extractor count (#30). Its no-mobile claim was not re-checked this round. The page offers no PP import path (#34).

## Verification outcome
- **Claim under test:** PP's PDF import covers more than 90 banks/brokers (round 1, from a search summary of PP's manual).
- **Independent source checked:** PP's GitHub repository, the PDF import package on master, read through GitHub's git-trees API (complete, not truncated), with a truncated contents-API read agreeing on the first 73 entries (#30, #31).
- **Number found:** 130 institution-named PDFExtractor classes, plus two more institution-named extractor files (#30).
- **Outcome: verified.** The more-than-90 figure holds as a lower bound, and the repository count is well above it.
- **Caveats:**
  1. Same project as the manual. The source is independent in underlying information (shipping code versus documentation prose), not in publisher. No press or forum count was checked within budget.
  2. Classes are not institutions. Some names are group-level (DZ Bank Gruppe, Raiffeisen Bankgruppe, Drei Banken EDV), so institution coverage may be higher. Others are P2P-lending, crypto or savings platforms (for example Bondora Capital, EstateGuru, Bison, BSDEX, Raisin) rather than securities brokers. This is an inference from file names only.
  3. The count comes from a fetch tool's enumerated listing, cross-checked by the second read. A direct count in a clone would settle the exact number.

## Leads worth chasing
- Count dashboard widget types in PP's source (its dashboard widget registry) to settle the 46-widget figure (#13).
- Read the manual's CSV-import page (#22) to list the CSV import types (account and portfolio transactions, securities, prices, and so on).
- Find the manual page or forum announcement for the 0.86.0 Rebalancing view and what its cash-flow allocation does (#25). It may raise the parity bar beyond taxonomy deltas.
- List the built-in quote feeds from PP's source code. The prices guide (2025-08-08) may lag the code, for example on crypto feeds (#17).
- Read the Payments and Trades manual pages: per-month/per-year payment views, per-trade holding period, lot grouping (#1, #24).
- Check Parqet's help centre for a PP import path, since the comparison page is from 2020 and says nothing about it (#34).
- Find a third-party (forum or press) PDF-importer count to make the verification fully publisher-independent.

## Looked for, could not find
- A total widget count on the manual's dashboard page (#13).
- CoinGecko, ECB or crypto-exchange feeds, per-provider API-key requirements and manual price entry on the fetched prices guide.
- Any mention of importing PP data on Parqet's comparison page (#34), and any Parqet comparison page dated within the last six months.
- A release newer than 0.87.0 on PP's GitHub releases page as of 2026-09-30 (#23).
- What the statement-of-assets chart plots (value only, or allocation over time); the page was not read.
- Report exports other than the Calculation CSV export; the File > Export page was not read.
- Whether the Calculation view splits fees and taxes into one line or two.
