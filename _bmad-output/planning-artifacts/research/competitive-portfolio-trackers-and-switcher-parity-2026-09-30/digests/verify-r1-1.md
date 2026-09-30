# Verification digest — load-bearing claims — verifier 1
Accessed: 2026-09-30

Budget used: 12 searches, 3 page fetches, plus 1 call to load the web tools.
V3 is split into V3a (the capability) and V3b (the version and date it first
shipped) because the one independent source confirms the capability but says
nothing about when it first shipped.

| id | claim (short) | independent source URL | publisher | pub_date | outcome (verified / disputed / unverified / overturned) | note |
|---|---|---|---|---|---|---|
| V1 | PP lets one security be assigned to several categories of a taxonomy, with weights that add up to 100% | https://der-finanzfisch.de/klassifizierung-von-etfs-in-portfolio-performance/ | Der Finanzfisch (personal-finance blog, hands-on tutorial) | 2017-04-12 | verified | The author splits one world-equity ETF across several region categories of a single classification by percentage. Setting a weight to 60% returns the other 40% to "Ohne Klassifizierung" so it can be assigned elsewhere, which means the weights are shares of 100% of the security. The article does not use the words "should add up to 100%". It dates from 2017, so it describes an older PP UI; the mechanism matches the manual claim. |
| V2 | The PP dashboard offers a monthly returns heatmap widget and a yearly returns heatmap widget | none fetched | n/a | n/a | unverified | Two searches with PP's own domains blocked returned mostly other products' heatmaps (a Parqet blog post, Portfolio Charts, J.P. Morgan). A search-engine summary named PP widgets "Monthly returns in a heat map" and "Yearly returns in a heat map" in the Performance section, but no source page could be pinned to it, and the wording may have leaked from PP's own manual, so it is not counted. Leads not fetched: the northern.finance PP step-by-step tutorial, the YouTube video "Performance Dashboard einrichten - Portfolio Performance Tutorial #5", and page 112 of the PP thread on wertpapier-forum.de. |
| V3a | Wealthfolio ships a built-in MCP server gated by scoped personal access tokens | https://github.com/abidals/Wealthfolio-Olares | abidals: an unofficial Olares app package on GitHub (a third-party packager) | undated (5 commits; the package ships Wealthfolio 3.8.0) | verified | The README offers an optional "AI Agent Access (MCP)" setting, turned on with the `WF_MCP_ENABLED` variable. Tokens are scoped and revocable, are created inside the app under Settings → AI Agent Access, and every agent call is audit-logged. The setup steps are the packager's own, so this is a different publisher. The token and audit wording may paraphrase the vendor's docs, so independence is moderate. The fetch model described the section as packager configuration. The tokens are still created in Wealthfolio's own settings screen, so the MCP capability belongs to the app; the packager only exposes the switch. |
| V3b | Wealthfolio's MCP server first shipped in v3.6.0 (July 2026) | none | n/a | n/a | unverified | No non-vendor source mentioned the first version or the date. The only v3.6.0 result was the vendor's own release page (github.com/wealthfolio/wealthfolio/releases/tag/v3.6.0), which is not counted. |
| V4 | Ghostfolio ships a built-in, experimental MCP server since release 3.59.1 (August 2026) | none | n/a | n/a | unverified | The non-vendor results were: (i) community Ghostfolio MCP servers such as mhajder/ghostfolio-mcp, which say nothing about a built-in server; (ii) WinterFlow.io's copy of the Ghostfolio 3.72.0 release notes, which republishes the vendor's text and so is not independent; (iii) an Umbrel App Store listing, not fetched. A search-engine summary describes an experimental MCP endpoint at `/mcp`. It most likely drew on the vendor changelog or that copy, so it agrees with the claim but comes from one publisher. No retrieved source mentions 3.59.1 or August 2026. |
| V5 | Community MCP servers expose a Portfolio Performance XML file to LLM assistants | https://github.com/ma4nn/pp-terminal | ma4nn (GitHub repository, GPL-3.0) | not visible in the fetched page (425 commits on master) | verified | Name: pp-terminal, "The Analytic Companion for Portfolio Performance". It is a command-line tool over the PP XML file, and `pp-terminal mcp` starts an MCP server. The README says it does not modify the original PP file and works completely offline, so it is read-only towards the source file. The README excerpt does not state how many MCP tools there are, and no release or commit dates were visible. It is a broader analytics tool with an MCP mode, not a dedicated MCP server. |

## Additional claims found (if any)
| # | claim | source URL | publisher | pub_date | confidence | class |
|---|---|---|---|---|---|---|
| A1 | A third-party tool writes proportional assignments of ETFs to countries, regions and holdings directly into the PP XML file, and the results appear under Classifications | https://github.com/cschalm/Portfolio-Performance-Security-Classifier | cschalm (GitHub) | unknown | low (search summary only, not fetched) | supports V1 |
| A2 | pp-terminal reads the PP XML file with ppxml2db into pandas dataframes. Its MCP mode is described as anonymising sensitive data and reducing context length and token use | https://github.com/ma4nn/pp-terminal | ma4nn (GitHub) | unknown | low to medium (search summary; the fetched excerpt did not confirm it) | detail for V5 |
| A3 | Wealthfolio's MCP server can write, not just read. Issue #1784 names the MCP tools `prepare_activity_import` and `commit_activity_import`. Issue #1621 reports that external MCP clients cannot commit categorization-rule drafts. Maintainer PR #1802 is titled "fix(mcp): preserve reviewed asset identity during imports" | https://github.com/wealthfolio/wealthfolio/issues/1784 ; https://github.com/wealthfolio/wealthfolio/issues/1621 ; https://github.com/wealthfolio/wealthfolio/pull/1802 | Wealthfolio's own GitHub tracker (issue authors not checked) | unknown | medium (titles copied exactly from search results) | supports V3 but is not independent; points to draft/commit write access |
| A4 | The unofficial Olares package ships Wealthfolio 3.8.0, so releases after 3.6.x existed by the access date | https://github.com/abidals/Wealthfolio-Olares | abidals (GitHub) | undated | medium | version context for V3 |
| A5 | Separately run community MCP servers exist for Wealthfolio (toomy1992/wealthfolio-mcp, datamoc/WFmcp; LobeHub entries for wirux and samlyu servers) and for Ghostfolio (mhajder/ghostfolio-mcp on PyPI, installable with pip or uvx, with read and write operations; forks by driosalido and pierdom) | https://github.com/toomy1992/wealthfolio-mcp ; https://github.com/mhajder/ghostfolio-mcp | various GitHub authors, plus listings on glama.ai, lobehub.com and socket.dev | unknown | medium that they exist; the directory listings repeat the READMEs | competitive context for V3 and V4 |
| A6 | Later Ghostfolio releases extended the experimental MCP server with an asset-profile search tool and a watchlist tool | https://winterflow.io/catalog/ghostfolio/releases/3.72.0/ (copy of the vendor changelog) | Ghostfolio, via a release-notes copy | unknown | low (search summary; not certain which page it came from) | context for V4 from the vendor; not independent |

## What was searched and not found
- Queries run (12): "Portfolio Performance MCP server github";
  "Wealthfolio MCP server"; "Ghostfolio MCP server";
  "\"Portfolio Performance\" XML MCP"; "Wealthfolio 3.6 built-in MCP";
  "Portfolio Performance Klassifizierung Gewichtung";
  "Portfolio Performance MCP xml" (github.com, pypi.org and npmjs.com only);
  "Portfolio Performance Heatmap Dashboard" (PP domains blocked);
  "Ghostfolio experimental MCP server" (MCP directories blocked);
  "Wealthfolio MCP access tokens" (glama.ai and wealthfolio.app blocked);
  "Portfolio Performance Tutorial Klassifizierung ETF aufteilen"
  (PP domains blocked); "Portfolio Performance Dashboard Heatmap Widget"
  (PP domains, parqet.com and portfoliocharts.com blocked).
- Pages fetched (3): github.com/ma4nn/pp-terminal,
  the der-finanzfisch.de classification article,
  github.com/abidals/Wealthfolio-Olares.
- V2: no fetched third-party page confirms either PP heatmap widget. Other
  vendors' heatmap features (Parqet, Portfolio Charts) dominate the results.
- V3: no news article, blog post, HN or Reddit thread, or podcast covering
  Wealthfolio's built-in MCP server or naming v3.6.0 / July 2026 as its
  debut. The results were the vendor's GitHub pages and MCP directory
  listings of community servers.
- V4: no independent source (neither the vendor nor a copy of its text) for
  Ghostfolio's built-in MCP server or for 3.59.1 / August 2026. One unfetched
  lead: vendor-hosted GitHub Discussion #6608 ("Make Ghotfolio as a MCP
  compatible tool").
- V5: the search restricted to GitHub, PyPI and npm found no dedicated
  "PP XML MCP server" repository other than pp-terminal (it also returned
  XML parsers without MCP, such as d-a-n/portfolio-performance-xml-parser).
  pp-terminal's MCP tool count and release dates were not visible, and its
  PyPI release history was not checked.
- V1: PP forum threads on weighted classifications came up (for example
  "Branchen: Gewichtung im Fonds in Klassifizierungen darstellen"). They were
  not used because the forum is on the vendor's own domain. Unfetched
  third-party candidates: be-jo.net (2025-09) and teilzeitoeko.de.
