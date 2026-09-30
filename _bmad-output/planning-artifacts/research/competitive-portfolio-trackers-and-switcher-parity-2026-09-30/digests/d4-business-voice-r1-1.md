# Digest — D4 business model, positioning, user voice — round 1 — assistant 1
Accessed: 2026-09-30

Method note: I used all 20 tool calls. I tried 7 page fetches and 5 returned content. The
ghostfol.io pricing page is rendered in the browser, so the fetch got only its title. The
Lemmy thread mirror returned HTTP 500. Claims marked "search summary" come from the web
search tool's summary of the result pages listed, not from a page I read, so they carry at
most medium confidence. No traction claim reached a second independent source. Every
traction claim below is therefore unverified.

## Claims
| # | claim | source URL | publisher | pub_date (YYYY-MM[-DD] or "undated") | confidence (high/medium/low) | class (capability/pricing/positioning/sentiment/traction/trajectory) |
|---|---|---|---|---|---|---|
| 1 | Ghostfolio's README calls the product open-source wealth management software built with web technology. | https://github.com/ghostfolio/ghostfolio | Ghostfolio (GitHub repo) | undated, accessed 2026-09-30 | high | positioning |
| 2 | The README names its target user: someone who trades stocks, ETFs or crypto on several platforms, values privacy and data ownership, and follows a buy-and-hold strategy. | https://github.com/ghostfolio/ghostfolio | Ghostfolio (GitHub repo) | undated, accessed 2026-09-30 | high | positioning |
| 3 | The README offers Ghostfolio Premium as the hosted cloud option ("easiest way to get started") and says its revenue covers running costs and funds development; self-hosting from the official Docker images is the free alternative. | https://github.com/ghostfolio/ghostfolio | Ghostfolio (GitHub repo) | undated, accessed 2026-09-30 | high | pricing |
| 4 | The README says some market-data sources are available only with Ghostfolio Premium; self-hosters set optional provider API keys instead (for example CoinGecko). | https://github.com/ghostfolio/ghostfolio | Ghostfolio (GitHub repo) | undated, accessed 2026-09-30 | medium | pricing |
| 5 | Ghostfolio is licensed under AGPLv3. | https://github.com/ghostfolio/ghostfolio | Ghostfolio (GitHub repo) | undated, accessed 2026-09-30 | high | positioning |
| 6 | The Ghostfolio repository page showed about 9.4k stars and 1.3k forks when accessed (one source, unverified). | https://github.com/ghostfolio/ghostfolio | GitHub | undated, accessed 2026-09-30 | medium | traction |
| 7 | An aggregator says Ghostfolio Premium "starts from $48/yr". The official pricing page (ghostfol.io/en/pricing) showed no pricing content to the fetcher, so the price is unverified. | https://www.findmymoat.com/vs/ghostfolio-vs-wealthfolio | findmymoat (aggregator) | undated | low | pricing |
| 8 | Ghostfolio's site has a series of SEO pages titled "Open Source Alternative to …", aimed at Wealthfolio, Rocket Money, Monarch Money, Microsoft Money and others (titles from search results; pages not fetched). | https://ghostfol.io/en/resources/personal-finance-tools/open-source-alternative-to-wealthfolio | Ghostfolio | undated | medium | positioning |
| 9 | Hostinger lists Ghostfolio as an installable application on its hosting platform (search result, not fetched). | https://www.hostinger.com/applications/ghostfolio | Hostinger | undated | medium | traction |
| 10 | In a selfhosted@lemmy.world thread, a Ghostfolio user called it really good but said you have to build your own import flow, because many brokers do not export data in a usable format (search summary; fetching the thread failed). | https://deddit.petersanchez.com/g/selfhosted@lemmy.world/p/f58f69zV2Fz65D6381-Self-hosted-portfolio-tracking | Lemmy (mirror) | undated (thread date not retrieved) | low | sentiment |
| 11 | Other commenters in the same thread had only tried the demo and called it promising, so interest outweighed hands-on reports (search summary). | https://deddit.petersanchez.com/g/selfhosted@lemmy.world/p/f58f69zV2Fz65D6381-Self-hosted-portfolio-tracking | Lemmy (mirror) | undated | low | sentiment |
| 12 | Wealthfolio's homepage tagline is "Grow Wealth. Keep Control.", and it describes a private, open-source investing and personal-finance app that runs locally on all of the user's devices. | https://wealthfolio.app | Wealthfolio (official site) | undated (© 2026), accessed 2026-09-30 | high | positioning |
| 13 | Wealthfolio's core app is free and needs no account. It covers manual accounts and transactions, CSV import, investment, net-worth and spending tracking, and goal and retirement planning. | https://wealthfolio.app | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | pricing |
| 14 | Wealthfolio ships desktop builds (macOS, Windows, Linux), iPhone/iPad apps, and self-hosted Docker setups (Compose, Unraid, Proxmox, Coolify, PikaPods). | https://wealthfolio.app | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | capability |
| 15 | Wealthfolio promotes an add-ons section, with featured add-ons (investment-fees tracker, goal-progress tracker, stock-trading tracker) and add-ons from the community. | https://wealthfolio.app | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | capability |
| 16 | Wealthfolio's homepage self-reports 9,000+ GitHub stars, one day at #1 on GitHub Trending, 924 Hacker News points for its Show HN, and 1,000+ Discord members (one self-reported source, unverified). | https://wealthfolio.app | Wealthfolio (official site) | undated, accessed 2026-09-30 | medium | traction |
| 17 | Wealthfolio Connect Basic costs $2.99/month or $29/year and gives end-to-end encrypted sync across up to 6 devices, including self-hosted instances. | https://wealthfolio.app/connect/ | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | pricing |
| 18 | Connect Essentials, marked as recommended, costs $7.99/month or $79/year and adds up to 5 institution connections, automatic brokerage sync, and AI with bring-your-own-key. | https://wealthfolio.app/connect/ | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | pricing |
| 19 | Connect Duo costs $12.99/month or $129/year and adds a second person, up to 12 institution connections, and a shared household view. | https://wealthfolio.app/connect/ | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | pricing |
| 20 | A Connect Plus tier marked "coming soon" is priced at $24.99/month or $249/year. It promises personalized portfolio briefs, news, earnings and dividend insights, an AI assistant that needs no user API key, and licensed market data. | https://wealthfolio.app/connect/ | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | trajectory |
| 21 | Wealthfolio's brokerage connections run through SnapTrade, a SOC 2 Type II aggregator that stores the encrypted credentials instead of Wealthfolio. | https://wealthfolio.app/connect/ | Wealthfolio (official site) | undated, accessed 2026-09-30 | high | capability |
| 22 | Wealthfolio says it does not charge for AI insights or market data on Essentials and Duo, because users bring their own third-party accounts (for example OpenAI, Anthropic or market-data providers). Search summary; I could not tell which wealthfolio.app page this came from (the FAQ, the Connect terms, or the Connect page). | https://wealthfolio.app/docs/faq/ | Wealthfolio (official site) | undated | medium | pricing |
| 23 | Aggregators list the entry Connect plan at $3.99/month for device-only sync, but the official page now shows $2.99/month (claim 17). Either the entry price dropped or the aggregators are wrong; the direction is unverified. | https://toolradar.com/tools/wealthfolio/pricing | toolradar (aggregator) | undated | low | trajectory |
| 24 | The Portfolio Performance mobile app is a free download with an optional Premium in-app subscription at €3.00/month or €30.00/year on the German App Store. | https://apps.apple.com/de/app/portfolio-performance/id6451118191 | Apple App Store | undated listing, accessed 2026-09-30 | high | pricing |
| 25 | In the PP app, Premium locks dashboards (viewing dashboards built on the desktop, and creating or editing mobile ones). Statements, performance calculations, dividends and interest, classifications, and price/FX updates stay free. | https://apps.apple.com/de/app/portfolio-performance/id6451118191 | Apple App Store | undated listing, accessed 2026-09-30 | high | pricing |
| 26 | The PP app subscription is presented as unlocking dashboards and supporting the app's future development (search summary). | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | Apple App Store | undated | medium | positioning |
| 27 | The PP app opens the desktop's binary portfolio file from a cloud drive (iCloud, Google Drive or OneDrive) and does all calculations on the device (search summary). | https://apps.apple.com/us/app/portfolio-performance/id6451118191 | Apple App Store | undated | medium | capability |
| 28 | The PP app's store description presents it as a privacy-preserving mobile companion to the desktop program. | https://apps.apple.com/de/app/portfolio-performance/id6451118191 | Apple App Store | undated listing, accessed 2026-09-30 | high | positioning |
| 29 | The PP iOS app's seller is MSM Mannheimer Software-Manufaktur UG (haftungsbeschränkt), a company rather than an individual. | https://apps.apple.com/de/app/portfolio-performance/id6451118191 | Apple App Store | undated listing, accessed 2026-09-30 | high | positioning |
| 30 | The German App Store listing shows an average of 4.7/5 from 208 ratings (iOS only; Android not checked). | https://apps.apple.com/de/app/portfolio-performance/id6451118191 | Apple App Store | undated listing, accessed 2026-09-30 | high | sentiment |
| 31 | The latest PP app version shown is 1.13.0, dated "July 9" with no year. | https://apps.apple.com/de/app/portfolio-performance/id6451118191 | Apple App Store | undated listing, accessed 2026-09-30 | medium | trajectory |
| 32 | The four reviews shown on the German PP listing are all 5-star and date from March–May 2024 (stale). They praise the long-awaited mobile companion, a clean interface that matches the desktop, and correct handling of bonds and coupons. No 1–3-star review was shown. | https://apps.apple.com/de/app/portfolio-performance/id6451118191 | Apple App Store | 2024-03 to 2024-05 (stale) | high | sentiment |
| 33 | AlternativeTo labels Portfolio Performance open source and free and shows 11 likes and 2 comments. Both comments are 5-star (2023 and 2021, stale) and praise data ownership and precise tracking. The site ranks Wealthfolio as the top alternative. | https://alternativeto.net/software/portfolio-performance/about | AlternativeTo | undated; reviews 2021-02 and 2023-09 (stale) | medium | sentiment |
| 34 | AlternativeTo lists Portfolio Performance's GitHub repository at 4,076 stars (aggregator, undated, one source, unverified). | https://alternativeto.net/software/portfolio-performance/about | AlternativeTo | undated | low | traction |
| 35 | German comparison content describes Portfolio Performance as a free but somewhat more technical open-source program, next to Parqet, getquin, Finanzfluss Copilot and justETF Premium. Search summary; the source could be justETF or finanzwissen.de. | https://www.justetf.com/de/academy/parqet-erfahrungsbericht.html | justETF | undated | low | positioning |
| 36 | Rotki published a blog post titled "Why we're changing rotki's pricing after more than 7 years", dated 2025-10-13 in its URL (title and URL from search; not fetched). | https://blog.rotki.com/2025/10/13/rotki-tiers/ | rotki | 2025-10-13 | medium | trajectory |
| 37 | Rotki now has tiers: Basic replaces the former single Premium tier, Advanced raises limits such as devices and database size, and Custom targets businesses, family offices and high-net-worth individuals (search summary). | https://docs.rotki.com/premium/plans-and-pricing | rotki | undated (living docs) | medium | pricing |
| 38 | Rotki's Basic tier is reported at €25/month including VAT (a search-summary figure, not checked against the primary page). | https://docs.rotki.com/premium/plans-and-pricing | rotki | undated | low | pricing |
| 39 | Rotki moved existing Premium subscribers to Basic from 2025-11-10, and yearly billing is cheaper than monthly (search summary; outside the 6-month trajectory window). | https://blog.rotki.com/2025/10/13/rotki-tiers/ | rotki | 2025-10-13 | medium | trajectory |
| 40 | Snowball Analytics publishes an official plans page. Search summaries report a free tier limited in holdings and reports and a Pro plan around $9.99/month, but another review cites $79.99–$249.99/year. The figures conflict and were not checked on the primary page. | https://snowball-analytics.com/public/pricing | Snowball Analytics (via search summary) | undated | low | pricing |
| 41 | A review aggregator says Sharesight's Premium subscription costs USD 24/month, its most expensive plan allows 10 portfolios, and it offers a 7-day free trial. | https://www.capterra.com/p/207519/Sharesight/reviews/ | Capterra (aggregator) | 2026 (per title) | low | pricing |
| 42 | A German affiliate comparison site dates its test 07/2026 and scores Parqet 96% and getquin 93%. It says getquin already has more features than Parqet and that both have free base versions plus paid premium subscriptions (search summary). | https://finanzwissen.de/vergleich/portfolio-apps/ | finanzwissen.de (affiliate comparison) | 2026-07 | low | sentiment |
| 43 | German comparison content calls Parqet one of the most popular trackers in German-speaking countries and getquin probably the most successful known provider (marketing tone, no source given, search summary). | https://www.justetf.com/de/academy/parqet-erfahrungsbericht.html | justETF | undated | low | traction |
| 44 | Finanzfluss Copilot is described as a combined portfolio, spending and budget tracker (search summary). | https://www.justetf.com/de/academy/parqet-erfahrungsbericht.html | justETF | undated | low | positioning |
| 45 | A competitor's comparison page describes Snowball Analytics as a dividend tracker with income dashboards, forward dividend calendars, growth charts and portfolio aggregation (competitor-written, search summary). | https://www.stockrover.com/?p=46673 | Stock Rover (competitor) | 2026 (per title) | low | positioning |

## Pricing table
| product | model | free tier | paid price | what is gated | recent change |
|---|---|---|---|---|---|
| Ghostfolio | AGPLv3 open source plus a hosted "Premium" SaaS whose revenue funds operations and development (#3, #5) | Self-hosting via Docker is free (#3) | Aggregator says "from $48/yr"; not confirmed on the official page (#7) | Hosting; some market-data sources (#4) | None found; the pricing page could not be read (#7) |
| Wealthfolio | Open-source, local-first app, an optional Connect subscription, and an add-ons ecosystem (#12, #13, #15) | Full app, no account (#13) | Basic $2.99/mo or $29/yr; Essentials $7.99/mo or $79/yr; Duo $12.99/mo or $129/yr; Plus $24.99/mo or $249/yr, "coming soon" (#17–#20) | Encrypted sync, brokerage aggregation via SnapTrade, household sharing, hosted AI and licensed data (#17–#21); on paid tiers, AI and data are bring-your-own-key (#22) | Plus tier announced (#20); entry price possibly cut from $3.99 to $2.99, unverified (#23) |
| Portfolio Performance | Free, open-source desktop app (#33); the mobile app is freemium, sold by a company (#24, #29) | Desktop free (#33); mobile core features free (#25) | Mobile Premium €3.00/mo or €30.00/yr (#24) | Mobile dashboards only (#25) | None found (#31 shows only that it is actively released) |
| Rotki | Open core with tiered subscription (#36, #37) | Not checked this run | Basic reported at €25/mo incl. VAT (#38); Advanced and Custom prices not found | Limits such as devices and database size (#37) | Moved from a single Premium tier to Basic, Advanced and Custom in 2025-10/11 (#36, #39); outside the 3–6-month window |
| Parqet | Freemium (#42) | Free base version (#42) | Not found | Not found | Not found |
| getquin | Freemium (#42) | Free base version (#42) | Not found | Not found | Not found |
| Finanzfluss Copilot | Not established (#44) | Not found | Not found | Not found | Not found |
| Sharesight | Subscription SaaS (#41) | 7-day trial per aggregator (#41) | USD 24/mo Premium per aggregator (#41) | Number of portfolios, capped at 10 on top plan per aggregator (#41) | Not found |
| Snowball Analytics | Freemium SaaS (#40) | Free, limited holdings and reports (#40) | About $9.99/mo Pro; annual figures conflict (#40) | Holdings, reports (#40) | Not found |

## Positioning lines
- **Ghostfolio.** Pitch: open-source wealth management software built with web technology (#1). Target user: a privacy-minded buy-and-hold investor with holdings on several platforms (#2). SEO pages position it as the open-source alternative to budgeting apps such as Rocket Money and Monarch, and to Wealthfolio (#8).
  - Gap (inference, not a sourced claim): the pitch leans on privacy and data ownership (#2), while the paid product is vendor-hosted (#3). Self-hosters also do not get every data source (#4).
- **Wealthfolio.** Pitch: "Grow Wealth. Keep Control.", a private, open-source app that runs locally on all devices (#12). Target user: someone who wants tracking without a mandatory account (#13).
  - Gap (inference): the core is local-first, but the paid features rely on cloud third parties: SnapTrade for brokerage links (#21), BYO LLM providers for AI (#22), and licensed data in the coming Plus tier (#20).
- **Portfolio Performance.** The mobile listing calls the app a privacy-preserving companion to the desktop program (#28). The desktop app is "open source and free" (#33). A third-party description calls it "more technical" than Parqet or getquin (#35). The PP homepage pitch was not retrieved this run.
- **Rotki.** Homepage pitch not retrieved. Its tier ladder reaches up to family offices and high-net-worth individuals (#37).
- **Parqet, getquin, Finanzfluss Copilot, Sharesight, Snowball.** No homepage pitch was retrieved; only third-party descriptions (#42–#45). Snowball's comes from a competitor (#45).

## Praise and complaints (per product)
- **Ghostfolio.** Evidence is thin and low-confidence (#10, #11).
  - Praise: works well once running (#10); the demo impresses (#11).
  - Complaint: importing is do-it-yourself, because brokers' exports are awkward (#10).
  - No GitHub issues, Discussions or Reddit threads were read. No top-3 lists can be supported.
- **Portfolio Performance.** Every available review is stale (#32, #33).
  - Praise: a long-awaited mobile companion, a UI that matches the desktop, correct bond and coupon handling (#32); data ownership and precise tracking (#33). Aggregate iOS rating is 4.7 from 208 ratings (#30).
  - Complaints: none retrieved. No 1–3-star review was visible on the iOS listing (#32), and no fresh r/Finanzen, r/eupersonalfinance or forum complaint was read.
  - The only indirect hint is "more technical" (#35). Absence of complaints here reflects a sampling gap, not satisfaction.
- **Wealthfolio, Rotki, Parqet, getquin, Copilot, Sharesight, Snowball.** No user voice was collected. Test scores for Parqet and getquin (#42) come from reviewers, not users.
- **Switchers.** No first-hand statement of what users miss after moving between these tools was found. The only proxy is that AlternativeTo ranks Wealthfolio as PP's top alternative (#33).

## Leads worth chasing
1. Rotki's pricing rationale post (https://blog.rotki.com/2025/10/13/rotki-tiers/): an open-core peer's own account of why it restructured pricing after 7 years. It also gives the primary source for #37–#39.
2. Wealthfolio Connect:
   - check the Plus launch status and date (#20);
   - use a Wayback snapshot of https://wealthfolio.app/connect/ to settle whether the entry price dropped from $3.99 to $2.99 (#23);
   - the closest open-source peer is moving to paid AI and licensed data, which bears directly on an MCP/agent product.
3. Ghostfolio's price and history via Wayback snapshots of https://ghostfol.io/en/pricing (the live page does not render for fetchers). Also read GitHub Discussions and the most-reacted issues for complaints.
4. Portfolio Performance user voice:
   - the forum announcement thread https://forum.portfolio-performance.info/t/portfolio-performance-app-die-erste-version/27333 for how the app and its subscription were received;
   - the Google Play listing for 1–3-star reviews;
   - Reddit searches restricted by domain (reddit.com, r/Finanzen).
5. The self-hosted portfolio-tracking thread on selfhosted@lemmy.world through another mirror (the deddit mirror in #10). It holds switcher comparisons of Ghostfolio against the others.
6. Primary prices for Parqet, getquin, Finanzfluss Copilot, Sharesight and Snowball (https://snowball-analytics.com/public/pricing). Query "Copilot" alone returns Microsoft Copilot; use "Finanzfluss Copilot Preis" or restrict to finanzfluss.de. The heise.de 7-tool tracker comparison is a second German source.

## Looked for, could not find
- Ghostfolio Premium's price on the official page: the page renders in the browser and returned no content. There was also no evidence of any Ghostfolio pricing change.
- Prices and gating for Parqet, getquin and Finanzfluss Copilot: the combined query was swamped by Microsoft Copilot results, and the budget ran out before separate queries.
- Primary pricing pages for Sharesight and Snowball: only aggregator figures, which conflict (#40, #41).
- Rotki's current prices on its primary page, and its homepage pitch.
- Recent (on or after 2025-10-01) 1–3-star reviews of the PP mobile app; the iOS page showed only 5-star reviews from 2024 (#32).
- Reddit threads (r/Finanzen, r/eupersonalfinance, r/selfhosted) on PP or Ghostfolio: the searches surfaced AlternativeTo and Lemmy mirrors instead.
- First-hand switcher statements about what users miss.
- Any traction figure confirmed by a second independent source (#6, #9, #16, #34, #43 are all single-source).
- Pricing direction from the Wayback Machine for any product: not attempted within the budget.
