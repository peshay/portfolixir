# Semantic citation check — 2026-09-30

Checked: 133. Supported: 105. Partly: 28. Not supported: 0.

A unit is either one prose sentence or clause with its own marker group, one
row of the §1, §2 and §4 tables, or one cell of the §3 table. In three of the
partly-supported units, one clause is not supported by the source it cites
(rows 3, 11 and 12). Rows 1–6 bear on the executive summary, a cross-dimension
insight or what a recommendation rests on. Rows 7–23 follow report order.

Digest keys: D1r1 = d1-switcher-parity-r1-1.md, D1r2 = d1-switcher-parity-r2-1.md,
D2r1 = d2-paradigms-r1-1.md, D2r2 = d2-paradigms-r2-1.md, D3r1 = d3-ai-mcp-r1-1.md,
D3r2 = d3-ai-mcp-r2-1.md, D4r1 = d4-business-voice-r1-1.md,
D4r2 = d4-business-voice-r2-1.md, H = lead-ghostfolio-demo-r1.md,
V = verify-r1-1.md. "Fetch" means this check read the source itself on 2026-09-30.

## Findings (partly or not supported only)

| # | report location (section + first words) | marker(s) | what the report says | what the source/digest says | verdict | suggested fix (confidence downgrade or wording) |
|---|---|---|---|---|---|---|
| 1 | §4 "Testers of a web app built on PP data…" and cross-dimension 1 "Testers check valuations first" (2 units) | [72] | Testers checked valuations first and found them off. Insight 1 ("correct numbers are the first trust test") rests on this | D4r2 #20: "a tester" reported valuations far off, together with internal server errors; another user hit conversion errors. "The first thing testers checked" appears only in D4r2's synthesis, not in its claim table. Fetch of [72]: two testers. One wrote that some valuations were "way off" in the same post as server errors (2026-04-04); the other hit an XML conversion error (2026-05-07). Nothing says valuations were checked first | partly; high impact ("first" and the plural are not in the source) | "One tester … found some valuations way off [72]"; lower insight 1's first clause to low (a single report) |
| 2 | Cross-dimension 1 "…the alternatives' top complaints are wrong figures" | [69][70] | Wrong figures are the alternatives' top complaints | [70], D4r2 #28–#29: true for Wealthfolio (cash and transfer figures; a release that broke calculations). [69], D4r2 #24: Ghostfolio's most-reacted open issue is a failing data provider. "Wrong performance calculation" (#25) is a second theme, and D4r2 ranks data-provider failures first. D4r2 #27: GitHub is a thin signal (top issue 11 reactions) | partly; high impact (wrong for Ghostfolio's top issue) | "Wealthfolio's top complaints, and one of Ghostfolio's top issues, are wrong figures (thin: at most 11 reactions)" |
| 3 | §3 "One of them, pp-terminal, is an analytics companion…" | [63] (and [62]) | pp-terminal is one of the MCP servers that PP forum members published | [63], V5: supports the description (a CLI over the PP XML, `pp-terminal mcp`, never modifies the PP file). No digest links it to the [62] thread: V5 found it by a GitHub search, and D4r2 lists the thread's repositories as an open lead. Fetch of [62] (all 12 posts, 2026-04-19 to 2026-07-26): the thread links two servers, pyfolio-performance-mcp and pp-mcp (pp-mcp is the one with about 20 read-only functions). pp-terminal does not occur | partly ([62] contradicts the "one of them" link) | "A separate project, pp-terminal, …" |
| 4 | §3 table, Wealthfolio "Tools"; §3 "Small agent surfaces. Peers expose six to thirteen tools"; cross-dimension 4 "…through six to thirteen tools" (3 units) | [15]; [14][15]; [15][14][17] | Wealthfolio's MCP server has 13 typed tools, 10 read and 3 write | D3r2 #10: 13 is the in-app assistant's tool list; that MCP exposes the same set is rated medium. D3r2 comparison table: "the MCP tool count is unverified", because the classification suggest/write scopes (#4) have no matching tool. V A3: Wealthfolio issue titles name the MCP tools `prepare_activity_import` and `commit_activity_import`, which are not in the 13-tool list. The report's own open question 5 says the count is unknown | partly (the digest calls the count unverified and records contrary signals; the report states it as fact) | "13 assistant tools, said to be shared with MCP (MCP count unverified)"; "six to thirteen" becomes "six to about thirteen (low)" |
| 5 | Executive summary 2 "None ships MCP prompts or resources…"; §3 Open ground "No peer ships MCP prompts or resources…" (2 units; same wording in cross-dimension 4 "ship no prompts") | [11][14][18] | No peer ships MCP prompts or resources over the user's own ledger | D3r2 #8: Wealthfolio's MCP page documents none, "medium (absence on one page)". D3r2 #28: the Ghostfolio PR #7935 diff registers only tools (medium; the diff was read through a fetch summary). D3r1: prompts are "n/d" for Parqet, Agni Folio and Foliora, and the report's own §3 table shows Parqet as "?". D3r2 names further finance servers "said to ship prompts" that were never read | partly (an absence recorded in two first-party peers' docs is stated as true of the whole field; recommendation 5 keeps the hedge, these sentences drop it) | "No peer whose docs were read documents MCP prompts…" plus "(medium: one docs page and one PR diff; Parqet not determined)" |
| 6 | §3 Open ground "The advice boundary is thinly handled: Wealthfolio says…" (1 unit; same wording in cross-dimension 4 "handle the advice boundary thinly") | [15] | The advice boundary is handled thinly, Wealthfolio included | D3r1 patterns: "mostly unaddressed in public material. Only Wealthfolio shows an explicit safety policy … Evidence here is thin." "Thin" describes the evidence, not how the boundary is handled. D3r1 #18, D3r2 #16: v3.7.0 made one versioned system prompt with safety evaluation fixtures and rubric grading. D3r2 #12: Wealthfolio "deliberately does not fine-tune for advice". The exact clause was not retrieved | partly (the digest treats Wealthfolio as the exception) | "thinly handled outside Wealthfolio", or "unevenly handled (evidence thin)" |
| 7 | Executive summary 2 "…and Ghostfolio in August 2026, with six tools filtered by the token's scope" | [13][14] | Ghostfolio's MCP server launched in August 2026 with six tools filtered by scope | D3r1 #1: 3.59.1 (2026-08-23) added the server "with a tool to get the holdings". Tools kept being added until 2026-09-20 (D3r1 #2, D1r1 #20). Six tools and scope filtering come from PR #7935 of 2026-09-26 (D3r2 #24 medium, #25) | partly (merges the launch month with the current tool set) | "…in August 2026, now with six tools filtered by the token's scope" |
| 8 | Executive summary 3 "Every SaaS peer, and PP, ship native apps" | [24][25][9] | Every SaaS peer ships native apps | The cited sources cover Parqet ([24]; D2r1 #39, search summary) and Finanzfluss Copilot ([25]; D1r1 #45). For getquin, Sharesight and Snowball the evidence is store-listing search summaries the sentence does not cite (D2r1 #42–#44) | partly (claims more than the cited sources cover) | add "(medium: store-listing search summaries)", or cite [40][42] |
| 9 | §1 "Trajectory: PP ships monthly." | [27] | PP releases every month | D1r2 #23–#28: 0.83.0 (2026-04-12), 0.83.1/0.83.2 (04-15, 04-19), 0.84.0 (06-03), 0.85.0 (07-07), 0.86.0 (07-16), 0.87.0 (08-16). No release followed 0.87.0 by 2026-09-30. No digest states a cadence | partly (no May release, and none in the 45 days before access) | "roughly monthly; none since 2026-08-16" |
| 10 | §1 PP on the phone "The current version is 1.13.0 from July 2026" | [31] | The phone app's current version is 1.13.0, July 2026 | D2r2 #19: Android record (AppBrain), 2026-07-08, taken from a search-engine summary because the direct fetch returned HTTP 403. The iOS listing shows "July 9" with no year (D1r1 #8, D4r1 #31), and one fetch read 2024-07-09 (D2r1 #6, low). D2r2: iOS day and year were not re-read | partly (Android only; search summary) | "The Android version is 1.13.0 from July 2026 (search summary) [31]" |
| 11 | §1 peers table, "Look-through by sector, region or country" | [35][34][32] | Wealthfolio has look-through (✓) | [34], D1r1 #32: the homepage advertises "asset allocation, sector exposure, and geographic distribution". D1r1's matrix records that as allocation "yes" but as ETF look-through "unknown" for Wealthfolio. PP's "—" rests on D1r1 #14, taken from [6], which the row does not cite | partly (the Wealthfolio cell is not supported as look-through) | Wealthfolio "◐ sector and geography views; look-through unverified"; add [6] |
| 12 | §1 peers table, "FIRE projection" | [3][33][34][32] | Ghostfolio has FIRE (✓), cited to [33] | [33] (ghostfol.io/en/portfolio) is H6, the Analysis view, which records no FIRE feature. Ghostfolio's FIRE evidence is H9 (ghostfol.io/en/portfolio/fire, not in the appendix) and D1r1 #22 (the [13] changelog) | partly (the Ghostfolio cell is not supported by its cited source, though other sources support the fact) | cite [13], or add the /portfolio/fire page to the appendix |
| 13 | §1 "A dividend calendar appears in every consumer SaaS tracker checked" | [32][41][25][42] | Every consumer SaaS tracker checked has a dividend calendar | D1r1: "in all four consumer-SaaS dividend trackers (37, 41, 43, 49)". Sharesight was also checked, and its calendar is "unknown". [41] and [42] are search summaries | partly | "in the four consumer SaaS trackers where it was looked for (Sharesight unknown)" |
| 14 | §1 "Differentiators held by one or two products: … FIRE projections (Ghostfolio, Wealthfolio, a PP widget)…" | [6][36][34][37][43][32] | FIRE is a differentiator held by one or two products | The sentence itself names three holders. The evidence for Ghostfolio's FIRE (H9, [13]) and for PP's widget ([3]) is not among its markers | partly | drop FIRE from this list, or add [3][13] |
| 15 | §1 Ghostfolio, tried directly "Presenter View and Zen Mode hide sensitive figures" | [37] | Both modes hide sensitive figures | H12: Presenter View is "protection for sensitive information like absolute performances and quantity values". Zen Mode is a "distraction-free experience for turbulent times". D1r1 matrix: hiding behaviour unverified | partly (Zen Mode is not described as hiding figures) | "Presenter View hides sensitive figures; Zen Mode offers a distraction-free view [37]" |
| 16 | §2 table, PP "First run: Install the app"; SaaS row "First run: Sign-up" (2 units) | [8][9]; [24][40][25] | How a first run starts for PP and for the SaaS trackers | D2r1 paradigm table: first run is "Not researched this run" for PP and "Not researched" for Parqet, getquin and Finanzfluss Copilot | partly (the first-run cells have no evidence) | mark those cells "? not researched" |
| 17 | §2 "The costs: every phone runs the Tailscale app, and machine names appear in public Certificate Transparency logs" | [52] | Both costs cited to [52] | [52] (D2r2 #1–#4) supports the Certificate Transparency cost. The phone-app requirement comes from [51] (D2r2 #9) and [50] (D2r2 #11) | partly (citation incomplete) | add [51] |
| 18 | §3 "Ghostfolio dropped a direct create-activity tool in favour of import" | [59] | Ghostfolio chose import over a direct create tool | D3r2 #19: a draft PR for a create-activity tool (#7764) was closed without merging, and the import tool (#7766) was merged. No reason is recorded; D3r2 calls the cautious reading "interpretation" | partly ("in favour of" implies a reason the source does not give) | "A draft create-activity tool was closed unmerged while import was merged [59]" |
| 19 | §3 "Copy-paste client configuration is the cheapest onboarding aid on offer" | [11] | Copy-paste configuration is the cheapest onboarding aid | D3r2 #2 shows only that the snippets exist. D3r2 patterns call them "a cheap way to make onboarding easier" and compare no aids | partly (the superlative is not in the source) | "a cheap onboarding aid" |
| 20 | §4 table, rotki row | [66] | Tiered open core, with limits such as devices and database size | [66], the blog post, was not fetched: D4r1 #36 has its title and URL from search only. The tier names and the device and database-size limits are a search summary of docs.rotki.com/premium/plans-and-pricing (D4r1 #37), which is not in the appendix | partly (the content comes from a URL the row does not cite) | cite the docs page; keep "low" |
| 21 | §4 table, Parqet "What is paid for: Dividend forecast and calendar…" | [32] | The dividend calendar is a paid feature | D1r1 #37: paid tiers get the forecast and a "personalized dividend calendar". Fetch of [32]: Basic includes the "General" dividend calendar; Plus and Investor unlock "Personalized & Forecast" | partly | "Dividend forecast and personalized calendar" |
| 22 | §4 "Its Show HN praised the UI and the local model" | [71] | Commenters praised "the local model" | D4r2 #33: commenters praised "its local, open-source model with no subscription", meaning how the app is run, not a local language model | partly (easy to misread in a report about AI) | "the local-first, subscription-free model" |
| 23 | Cross-dimension 3 "The paid parts across the field are phone dashboards, sync and brokerage links, hosting and data" | [30][22][19] | This list is what the whole field charges for | The cited sources cover PP's phone app, Wealthfolio and Ghostfolio. Parqet's paid tiers gate analytics (forecast, X-Ray, benchmark, tax dashboard; D1r1 #37, [32], and the report's own §4 table) | partly (generalises beyond the three cited products) | "across the self-hosted peers and PP's phone app", or add "and analytics at Parqet [32]" |

## Dropped hedges

- **[5], 130 extractors** (executive summary, §1 text and table): D1r2 #30
  rates the count medium. It comes from a fetch tool's listing, and "classes
  are not institutions": some are group-level, some are P2P, crypto or savings
  platforms. The appendix rates it high. Fix: medium, and "about 130 extractor
  classes".
- **[28], "more than 90"**: D1r1 #15 is a search summary of a page that was
  not fetched, capped at medium. The appendix row names it a search summary
  and still rates it high.
- **[8], launch post of 2024-02-21**: D2r2 labels it "stale; launch-state
  evidence". The report rates it high and uses it for the present-tense
  "in binary format" (§1). The only other support for "binary" is a search
  summary (D4r1 #27).
- **[51][52], Tailscale KB**: D2r2 rates every claim medium, because the pages
  were last validated 2026-01-20 and 2025-12-10 and are stale by the 3-month
  bar. The appendix rates them high, and §2 gives them no label. Serve
  provisions certificates only after HTTPS is enabled for the tailnet, which
  needs MagicDNS (D2r2 #2, #6).
- **Tailscale costs**: D2r2 lists four costs; the §2 costs sentence gives two.
  It leaves out that Tailscale's coordination service is itself a hosted
  product with a free tier (and that the client usually runs as root, #11),
  and that names are fixed to the tailnet domain (#9). The hosted coordination
  service bears directly on the decision's "without a hosted cloud".
- **[12]**: V3a is "verified", but notes "independence is moderate" because
  the token and audit wording may paraphrase vendor docs. The appendix rates
  it high.
- **[10][13], launch dates**: V3b and V4 found no independent source for
  Wealthfolio v3.6.0 (July 2026) or Ghostfolio 3.59.1 (August 2026); both rest
  on the vendors alone. The executive summary gives both months without a
  label.
- **[17], "Both now call language models from inside the app"** (executive
  summary; §3 table "yes"): D3r2 #31 says the service "can call" an LLM through
  OpenRouter, using a key and a model stored as instance properties. H15 saw no
  AI or copy-prompt feature in the hosted demo. Fix: "can call one, once an
  OpenRouter key is configured".
- **[56], Parqet "read-only"** (§3 table and "Hosted commercial servers default
  to read-only"): D3r1 #25–#26 are search summaries. D3r1 #27 records an
  unresolved conflict: the Developer Hub index speaks of adding portfolios,
  holdings and activities.
- **[62]**: D4r2 #16–#18 are medium (read through a summarising fetch tool);
  the appendix rates them high. This check's fetch confirms the content,
  except the pp-terminal link (row 3).
- **[67]**: D4r2 counts topics "judging by their titles" and did not read the
  posts. §4 presents the title-based count as what the topics "are about". The
  executive-summary caveat partly keeps this.
- **[69]**: D4r2 #27 calls GitHub "a thin sentiment signal" for Ghostfolio.
  Cross-dimension 1 drops this.
- **[50], Immich**: D2r2 #10–#11 come from a search-engine extract; the page was
  not fetched. §2 gives them no label.
- **Search-summary labels in the appendix**: [16], [28] and [31] carry
  "(search summary)". [24], [40], [41], [42], [43], [56] and [61] rest on search
  summaries too (D2r1 #39; D1r1 #41, #42, #47, #49; D3r1 #25–#26, #35), but
  carry no label.
- **Cross-dimension 2, "No peer page offers an import of PP data
  [19][34][38]"**: Ghostfolio's absence is rated low (D1r1 #30). Parqet's rests
  on a page from 2020 ([38], low). For Wealthfolio, D1r1's matrix records PP
  import as "unknown" and does not say it was looked for; its homepage
  advertises "CSV statements from anywhere" (D1r1 #34). Label: low.

## Notes

- This check fetched four sources out of the five allowed: [62] (the page,
  then its topic JSON to confirm all 12 posts were read), [72] and [32].
- Resolved: Parqet's prices are monthly (11,99 € and 29,99 € per month; annual
  billing gives three months and one month free), so the cadence hedge on
  D1r1 #36 can be lifted.
- The [62] fetch also confirms that several posters took part. The opening
  poster fed the XML to ChatGPT Plus, Perplexity Pro and Claude, and others
  had the same idea or built MCP tools, so "Forum members feed PP's XML to
  several models" stands. The 0.0.0.0 criticism came on 2026-07-26, five days
  after pp-mcp was announced (2026-07-21). "Immediate" is loose; "within days"
  is exact.
- **Unmarked sentence (not counted).** The lead-in to executive-summary finding
  3 reads "No self-hosted peer reaches the phone without a VPN or a relay."
  D2r1's pattern says "without internet exposure". Ghostfolio's reverse-proxy
  settings (D2r1 #26) and Wealthfolio's authenticated web mode behind a proxy
  (D2r1 #10) both reach a phone with neither a VPN nor a relay, by exposing the
  server. Suggest "without a VPN, a relay or internet exposure".
- **Minor citation gaps in supported units** (no verdict change):
  - §4 table, PP "Free desktop" rests on AlternativeTo (D4r1 #33), not [30].
  - Cross-dimension 4, "ship no prompts" for Wealthfolio rests on [11], not
    the cited [15].
  - §2, "the sync experience is the drive's, not the app's" rests on a stale
    forum thread (D2r1 #7) that is not in the appendix.
- **Staleness map** (outside the sections checked; flagged as a date
  mismatch):
  - [8] (2024-02-21, "stale" in D2r2) and [38] (2020-02-04) are listed under
    2026-12-01 instead of "now (stale)".
  - [7] (2017), [26] (2025-05-15) and [29] (2025-08-08) are not listed at all.
  - [52] was last validated 2025-12-10, earlier than [51], but appears nowhere
    in the map.
- **Not checked:**
  - the frontmatter claim counts (the ledger is outside the files granted);
  - statements labelled project context;
  - the recommendations, which carry no markers. Two of the findings still
    affect them. Rows 1–2 weaken cross-dimension 1, which recommendation 6's
    "figures that state their basis" builds on. Rows 5–6 weaken the "open
    ground" behind recommendations 5 and 6.
