# Sprint 27 — the news layer's first half, and the stacked chart

**Status: ADOPTED by the merge of the Sprint 27 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0056's amendment of 2026-11-07](../../docs/decisions/0056-news-layer-fetched-matched-stored-labelled-outside.md#amendment-of-2026-11-07-what-the-first-sprint-needs-and-nothing-decided-by-order)
(B1 to B8: the upkeep writes move into this sprint, a feed's URL is
resolved on every fetch, no order and no feed's claim decides a story, an
aggregator's item is never primary, where the scheduler runs, what the
journal records, the gate's sentence), the decisions D-4 and D-5 for I23
(the stacked chart, worked out by you on 2026-11-07) and the two
`AGENTS.md` corrections of 2026-11-07. A fresh implementation session
builds the sprint on `agent/<provider>/sprint-27` as **one** sprint PR
(D-10). The severity rule of ADR-0026's amendment of 2026-11-01 applies
unchanged.

## What you need to do

1. **Merge, to adopt the plan.** Nothing in it books or corrects a stored
   money figure, so every choice is decided with its reason and flips by a
   comment. The one that changes what you signed: **B1** moves four of
   ADR-0056's tools from Sprint 28 into this sprint, because without them
   the agent cannot register a single feed until Sprint 28 (D-2).
2. **Look at D-5**, the four points I23's row left to the plan; each
   carries its recommendation, and silence adopts it.
3. **Optional, still open:** the `browser` CI job as a required status
   check on `main` (Settings → Branches, since Sprint 24); Dependabot's
   #1392 (`floki` 0.38.5, test only) is your merge; #1391 (`sobelow`
   0.18.1) is superseded by Sprint 26's M1 and can be closed.

**Not asked:** everything else. **Not raised:** the Bitcoin cycles (I12),
held by you. **I24** (crash rankings) is worked out and placed in Sprint
28, its decision record on Sprint 28's planning PR (D-9).

**Verification basis:**

- **Sprint 26's merge, as its close-out asked this plan to record:** the
  sprint PR #1406 was merged at 21:14 UTC on 2026-11-06; CI run 1916
  green on `86dc282`; release **2026.11.11**. Its keywords closed #1401,
  #1402, #1403 and #1404.
- **Since then on `main`:** #1408 (ideas I23 and I24 with their boards,
  docs only, no release; CI run 1919 green on `d6df259`), then the
  owner's `d2d185d` and `1d59e43` (I23 and I24 worked out, boards 01 and
  03 redrawn and drawn, docs only). `main` is at `1d59e43`. Dependabot
  #1407 (`lazy_html` 0.1.14) is closed, taken by Sprint 26's M2.
- **The open-issue list of 2026-11-07:** 26 open: 5 `agentic` (#1405,
  #1396, #1070, #900, #899), 1 `agentic` and `needs-decision` (#1220), 1
  `needs-decision` (#1177), 2 `needs-uat` (#328, #354), 17 trackers (11
  polish lists #1355 to #1366 without #1364; #991; the five area trackers
  #416 to #420). Two Dependabot PRs are open: #1391 and #1392.
- **Read against the code on `1d59e43`**, each claim this plan rests on:
  - `Portfolixir.Net.Http` checks a client's **first** request with
    `resolve: false` (its host is a compiled-in endpoint) and every
    redirect hop with `resolve: true`; `Portfolixir.Net.UrlPolicy.check/2`
    resolves when asked and states the rebinding limit. Hence B2.
  - Mint connects over IPv4 unless a caller sets `inet6: true`
    (`Mint.Core.Transport.TCP`), which already gives §5's "IPv4 first" for
    `sec.gov`; N3 pins it with a test.
  - The app parses no XML with a library today: the ECB feeds are read by
    binary splits and anchored patterns under `Net.ParseGuard`
    (`fx/rate_sync/ecb.ex`); no XML dependency is in `mix.exs`. A1's
    parser is new.
  - `scope_b2_outbound_chokepoint_test.exs` registers every caller of
    `Net.Http` with its literal, attribute or config allow-list, and an
    `any:` reason where none exists; `scope_b5_…` registers every system
    job and self-scheduling process; `scope_b7_gate_registry_test.exs`
    pins `AGENTS.md`'s sentence "data acquisition beyond quotes and FX
    (B3.3)". Hence B7 and B8.
  - The quote sync's switch: on in production, `PORTFOLIXIR_BACKGROUND_FETCH`
    in development, off in tests (`config/*.exs`). Hence B6.
  - `Portfolixir.DeltaCursor` gives overlap, never loss, for `since=`
    reads by a server-stamped column. Hence B4.
  - `portfolixir.securities.update` is the one write for a security's
    master data; the news keys join its schema.
  - **For I23:** the performance walk values every held security every day
    (`security_value/3`) and sums it away with the cash in
    `portfolio_value/2` (`portfolios/performance.ex`); ADR-0051's
    contribution keeps positions apart in the same walk without moving its
    other outputs, and defines a position's net flows. The Wealth chart is
    `performance_chart/1` in `portfolio_live.ex`, with the modes `ttwror`
    and `value`; a category's colour is the operator's, else
    `@category_palette` in tree order, as the sunburst draws it. The
    contribution read exists in the performance family's forms
    (`/portfolios/:id/…`, `/views/:id/…`, `/performance/…`) with the tools
    `portfolixir.portfolios.contribution` and `portfolixir.views.contribution`.
  - The schema budget's ceilings in force are read 110,953, book 182,982
    and full 217,537 (Sprint 25's last row); Sprint 24's D-2 rule lets
    them grow by a new tool's own bytes and no more. The API contract's
    head is entry 26 (Sprint 26); this sprint's is entry 27.
- **Board:** I23's idea board 01
  (`design-language/mockups/ux-design-2026-11-06-ideas-i23-i24/`), A, as
  you picked and recoloured it on 2026-11-07. Lane N changes no rendered
  output.

## State of play, in five lines

1. **Sprint 26 is on `main`** (release 2026.11.11): nothing agent-only is
   overdue, I18 and I22 are built.
2. **The news layer is signed** (ADR-0056, its amendments of 2026-11-06
   and, with this merge, 2026-11-07) and is #1405 for this sprint, agent
   first; its view, labels, cursor and markers are Sprint 28's.
3. **I23 and I24 are worked out** (2026-11-07): I23 is built here, I24 in
   Sprint 28 after its decision record.
4. **`AGENTS.md`** no longer requires the model in a PR body and accepts
   an environment-assigned branch (this PR, your request of 2026-11-07).
5. **The Bitcoin cycles (I12) are held** by you.

## Why this cut

- **The news layer with its own commit group and closing act.** It is a
  new outbound surface and a parser of hostile input (ADR-0056 A4). The
  stacked chart rides beside it as a separate lane with separate lenses:
  it shares no code with Lane N, and building it now puts the idea you
  settled today on screen within a sprint instead of two.
- **I23 needs no decision record.** It decomposes a figure the chart
  already draws, one category per security (ADR-0006), with ADR-0051 as
  the precedent for keeping positions apart in the walk; the four points
  its row left open are plan decisions (D-5).
- **I24 does need one.** A crash window is a new stored object with a
  detection rule over a benchmark's closes, and the rule has the order
  questions Sprint 26's retrospective warns about (ties of peaks and
  troughs, gaps, overlapping windows). Its ADR goes on Sprint 28's
  planning PR with the adversarial pass, and Sprint 28 builds it (D-9).
- **The upkeep writes come forward (B1).** An agent-first sprint whose
  agent cannot register a feed checks nothing on an instance.
- **About 43 commits**, one PR, no stack (D-10).
- **What is left out, and why** (each flips by naming it): §11's second
  half and §10's view (Sprint 28); I24 (Sprint 28, after its ADR); I20
  (usage hints, waiting for your examples); the polish lists other than
  the lines on Wealth that Lane S's files reach; #899, #900, #1070, #1220,
  #1177, #328, #354 and #1396 keep their standing reasons (D-12).

## Lanes (one sprint PR, `agent/<provider>/sprint-27`, in this order)

**Lane M, maintenance (first).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | standing rule | the version report `version-report-2026-11-…-sprint27.md`: Hex, npm, Elixir/OTP, PostgreSQL, BMAD core and the external modules, each bump its own commit, what is declined with its reason; N1's new dependency, if it takes one, is audited and pinned here | 1–2 |

**Lane N, the news layer's first half** (#1405; ADR-0056 §§1–6, §9, §11,
§12, §14, A1, A3 and the amendment of 2026-11-07). **Risk tier: security**
(a hostile-input parser and a new outbound surface): its own commit
group, a dedicated verification pass, a callout in the briefing
(sprint workflow, "Risk-tier attention").

| Story | Source | What it does | Commits |
|---|---|---|---|
| N1 | A1; Sprint 26 carry-forwards 3 and 6 | **the parser, attack fixtures first.** Fixtures written and seen failing before any parser code: an entity-expansion bomb, an external entity naming a local file and a URL, a document 10,000 levels deep, one over the byte cap, 5,001 items, a truncated document, and 1,000 distinct element names with the VM's atom count read before and after. Then RSS 2.0 and Atom 1.0 into plain maps: no atom from a name, no DTD processed, only the five predefined entities and numeric references decoded, depth ≤ 64, items ≤ 5,000, under `Net.ParseGuard` (D-7). Titles and excerpts leave as plain text: HTML removed, control characters removed, lengths capped (160 and 600; D-6) | 2 |
| N2 | §2, §4, A3 | the tables: `news_feeds`, `news_sources`, `news_items`, `news_clusters` (each with the counts and fields §4 and A3 name), and the security's `news_identity` (`cik`, `aliases` as `{token, context, case}`) and `news_watch`; every check constraint the fields allow (class and tier enums, lengths, `security_id` xor `category_id` by class) | 2 |
| N3 | §5, A3, B2, B6, B7, B8 | **the fetcher.** A supervised scheduler beside the quote sync (B6), one task per feed, exponential backoff on 429 and 5xx, the error on the feed and never on another; the URL checked with resolution at registration and before every fetch, the feed's host as the only allow-list (B2); `sec.gov` at most 10 requests per second and over IPv4; `PORTFOLIXIR_NEWS_USER_AGENT`, and `user_agent_missing` for a `sec.gov` feed without it; the 200-item daily cap with `dropped_cap`. A fake provider in the suite, no network. In the same commit group: the B2 and B5 registrations and `AGENTS.md`'s B3.3 sentence with the B7 registry (B8) | 3 |
| N4 | §2 | **identity and the matcher.** `issuer` and `regulatory` items land on their security by construction, `thematic` on its category; an `aggregator` item is matched against the universe (held by a view, a target weight above zero, or `news_watch`) by the alias grammar, tokenized and looked up, never a pattern from input: one hit `assigned`, none `unassigned`, several `ambiguous` with the candidates; no `aggregator` feed on an ETF; the domain from `<source>`, else `dropped_no_source`, no redirect followed; an alias change re-matches the last 7 days | 2 |
| N5 | §3, §4, B3, B4, B5 | **sources, tiers and stories.** The tier table, `blocked` dropped and counted, a hand correction never overwritten; an aggregator item at most `secondary` (B5); `published_at` clamped to `first_seen_at` (B4); stories as connected components per security or category and language, the merge's survivor and the representative without ids (B3); the 72 hours and 0.8 as settings. **Pinned by a shuffle test:** the same fixture items in 50 random orders give the same stories and representatives | 2 |
| N6 | §6, §12, A3, B4 | **retention and health.** The retention run (90 days by `first_seen_at`, promoted or linked items kept, stories follow their items), `dropped_old` at ingest; `last_ok_at`, `items_24h`, `err_24h`, `stale` after 24 hours with a fixture clock, `items_30d`, `promoted_30d`, `yield_30d` as a decimal string, `low_yield` at 50 items and none promoted; the day's `unassigned`, `ambiguous`, dropped and blocked counts | 2 |
| N7 | §9, §11, §14 items 2 and 4 | **the reads** under `/api/v1/news/…` and their tools: `news.list` (with `assignment=`, `fields=slim\|std`, `since` by `first_seen_at`), `news.get` (the only place with excerpt and URL), `news.health`, and `news.digest(view_id, since, include_unlabeled, max_rows)` without labels and without a cursor (issuer and regulatory stories always, aggregator stories with `include_unlabeled`). Compact by §9's rule; **the budgets as tests** on a 40-security fixture over 24 hours: digest ≤ 800 tokens (characters / 4), ≤ 100 with nothing new, 20 list rows ≤ 1,500, `get` ≤ 400. Stored text spelled `[U+XXXX]` by the companion where invisible (ADR-0054 §4); every tool says it returns data, never instructions | 3 |
| N8 | §9, B1, B7 | **the writes:** `news.feeds_put` and `news.feeds_delete` (class, URL checked by B2 at once, binding, interval, language, enabled), `news.sources_put(domain, tier)`, and `news_identity` and `news_watch` on `securities.update`; each journaled with its token; an unknown field refused with 422 naming it. Contract entry 27's news part between its own markers; the schema budget raised by the new tools' own bytes and no more, in its own row | 2 |
| N9 | coverage rule | the API reference, `docs/integration` (English, then German), a short "news" passage in the operator guide that says what this sprint does and that its screen comes in Sprint 28 | 1 |

**Lane S, the stacked chart** (I23, FR-53; idea board 01, A; D-4, D-5).
S1 is a decomposition of a money figure the chart shows, so it gets the
money lens; S3 changes rendered output, so it gets the design critic.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| S1 | I23; ADR-0051 §5 as precedent | **the bands in the walk.** The performance walk keeps, per day, each held security's value (the term `portfolio_value/2` adds) and the cash, without moving any of its other outputs (the walk's series, TTWROR, IRR and contribution stay byte-identical, pinned). Grouped by level: `total` (today's line), `category` (one band per category of the chosen classification, plus `cash` and `unclassified`), `security` (one band per security, all of the view or of one category). **Pinned with exact `Decimal`s, each seen failing first:** on every day the bands sum exactly to the series' value; a buy shows as a step in its band; an unpriced day counts zero as the line does; a security that changes category mid-window stays in the category it has now (D-5); more than eight bands merge the smallest into `other` by value on the window's last day, ties by name, never by id; the band's change over the window without flows (end − start − the band's net flows by ADR-0051's terms, over the start value; none without a start value) | — | 2 |
| S2 | coverage rule; ladder (b) | the read in the performance family's three forms (`…/performance/bands` beside `…/contribution`) and the tools `portfolixir.views.bands` and `portfolixir.portfolios.bands`: `level`, `classification_id`, `category_id`, `sort=size\|change`, the window as the family takes it; each band's daily values as decimal strings, its share and its change; the `computation_basis` (the walk's value series, the window, the level and classification, the merge rule, the treatment of unpriced days and of a category change). Contract entry 27's bands part between its own markers; the schema budget by the tools' own bytes | — | 2 |
| S3 | I23; board 01 A | **the chart.** In the value mode, one bar above the chart: Ebene (Gesamt · Kategorien · Einzelwerte), Klassifikation, Sortieren (Größe · Veränderung); Gesamt is today's chart, unchanged. The stacked bands with the largest at the bottom, the legend as a table (Wert, Anteil, Veränd.), a click on a band or its legend row opens the category stacked by its securities, the breadcrumb leads back. Colours: a category's own colour, else the palette in tree order as the sunburst; a drilled category's securities the palette's hues in order; cash in the cash colour, unclassified grey. **In the privacy mode** the stack is drawn as a 100 % stack by itself and the legend keeps share and change (I22's backstop and leak walk cover the new states). `DESIGN.md` gains the anatomy; the lines of #1366 (Polish: Wealth) the touched files reach are fixed | 01 | 3 |

**Closing act** (D-8): for Lane N, the correctness hunter; the
edge-case hunter; the **security lens** as a hostile feed host (request
forgery through a registered URL, a redirect, a name that resolves
privately; XML attacks beyond N1's list; HTML, control and invisible
characters in titles; a flood past the cap; a feed that never answers);
the **order lens** as a party that wants a story, a representative or a
tier to come out its way with true items (B3 to B5); the **agent's lens**
(the budgets, the wording, that a tool's answer reads as data). For Lane
S, the **money lens** (every pinned band sum recomputed independently;
a buy, a sale, a category change and an unpriced day inside the window)
and the **design critic** against board 01 in both themes, at 1200 and
390 px, with the privacy mode on and off. The UAT persona registers a
fake-provider feed through the API, aliases a security, runs a fetch and
reads the digest, a list, a story and the health on the review seed, then
opens Wealth, stacks by categories, drills into one and compares a day's
bands with the API. About 8 commits.

**Close-out** (the PR's last commits): `sprint-status.yaml`, `epics.md`'s
FR Coverage Map (FR-52's first half, FR-53) and a dated reconciliation,
the idea list (I21's and I23's rows), the retrospective, the version
report. About 5 commits.

**Estimate:** M 1–2, N 19, S 7, closing act 8, close-out 5: **about 41
to 43**, with room for one review round under ADR-0026's 90.

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **§14's sprint items hold on synthetic fixtures:** identity (1), size
   (2), dedupe per language (3), freshness by a fixture clock (4), health
   (5), no archive (9); items 6 and 7 (labels) are Sprint 28's, and item 8
   (fail-open) holds because no read needs a label.
2. **A1's attack fixtures are each refused** without the parser reading
   past the refusal, and the atom count is unchanged.
3. **No order and no feed's claim decides:** the shuffle test gives the
   same stories and representatives in every order; a future
   `published_at` is clamped; an aggregator item naming a primary domain
   reads `secondary`.
4. **No request leaves for a host the URL policy refuses:** a feed whose
   name resolves to a private address is refused at registration and at
   fetch; a redirect to another host makes no request.
5. **The bands add up:** on every day of every pinned case the bands sum
   exactly to the value the chart draws, and the walk's other outputs are
   byte-identical; the screen matches the API for the same request.
6. **Every gate holds by registration, not by weakening:** no ignore, no
   lowered threshold, no skipped test; the B2, B5 and B7 registries name
   the new entries with their reasons.
7. **The regressions this sprint introduced are counted** apart from the
   older findings, and none is an S1 at promotion.

**No criterion counts open issues.** Reported, not judged: 26 open today.

**To flip by comment:** name a criterion to drop or add.

### D-2: ADR-0056's amendment of 2026-11-07, signed by this merge (recommended)

The amendment says it in full. The choices it makes that you did not make
yourself, each flippable by its phrase:

- **B1, the upkeep writes now** ("news upkeep in 28"): registration of
  feeds, sources and aliases comes with the fetcher; `news.assign` stays
  in 28.
- **B3, stories as connected components, merges without ids** ("news
  first match").
- **B5, an aggregator's item at most `secondary`** ("news trusts
  source").
- **B6, the scheduler runs where the quote sync runs, an enabled feed is
  the opt-in** ("news switch").

B2, B4, B7 and B8 offer no flip: each closes a hole (a forged request, a
claimed date, an unrecorded write, a gate sentence that no longer says
what is gated).

### D-3: two-way coverage (standing)

Lane N is agent-only by ADR-0056 §11; **its human view (§10: feeds and
their health, a security's stories, the unassigned and ambiguous queue)
is due by the end of Sprint 28**, boarded on Sprint 28's planning PR with
A2's chart markers. Lane S ships its read, its tools and its screen
together, so it owes nothing.

### D-4: I23 as you settled it (signed by this merge)

A only: the level bar, the classification and the sort above the value
chart; market-value bands; a click on a category shows only it, stacked
by its securities; no "Anteil %" and no "Beitrag" series (what produced a
period stays the contribution table's, FR-41); the privacy mode draws a
100 % stack by itself; colours as the sunburst's, a drilled category's
securities in the palette's hues. Recorded in the idea list, now FR-53.

### D-5: the four points I23 left to the plan (recommended)

- **Cash is its own band**, in the cash colour, because the line counts
  it and the bands must add up to the line. "I23 ohne Cash" drops it,
  and the bands then no longer add up to the line, so the line would be
  drawn above them.
- **The unclassified remainder is its own grey band**, for the same
  reason. "I23 ohne Rest" drops it, with the same consequence.
- **More than eight bands merge the smallest into „Sonstige“**, smallest
  by value on the window's last day, ties by name. "I23 zehn" (or any
  number) changes the eight.
- **A view with several classification trees stacks by the one its
  allocation targets use**, and the bar's chooser offers the others.
  "I23 erste Klassifikation" makes it the first tree instead.

One more the board decided without naming it: **a security that moved
between categories inside the window is drawn in its category of
today** for the whole window, because a classification is stored as it
is now, not with a history; the basis says so. "Veränderung" sorts by the
band's change without flows, as board 01's basis line states.

### D-6: what the app makes of a feed's text (recommended)

Titles and excerpts are stored as plain text with HTML and control
characters removed and lengths capped, as ADR-0056 §9 says; nothing in
them is rendered as markup anywhere. **HTML is removed by a linear tag
stripper, entities decoded once after it**, so `&lt;script&gt;` becomes
the visible text `<script>`, which every surface escapes. Invisible
characters are kept as received and spelled by the companion (ADR-0054
§4), not dropped, because dropping them changes the evidence. **To flip:**
"news drop invisible".

### D-7: the parser's dependency (recommended)

`saxy` in SAX mode, because it builds no atoms, streams, and lets the
handler stop at the first depth or count breach; the attack fixtures,
written first, decide. If one fixture passes through, N1 writes a small
parser of the app's own for the two formats instead. A dependency taken
is audited and pinned in M1 and registered in the dependency-class
backstop (`scope_b3_dependency_classes_test.exs`). **Not** `xmerl`: it
makes atoms from names by default, which `AGENTS.md` forbids for external
input. **To flip:** "news own parser".

### D-8: the closing act and the build (standing, with Sprint 26's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's section "What a story's own tests do
not cover" applies to every story; Sprint 23's four build rules stand.
Sprint 26's carry-forwards, applied:

1. **The adversarial pass asks about order** (run on ADR-0056 for this
   merge: B3, B4, B5; on I23: the merge into „Sonstige“ and its ties, the
   category change); the closing act's order lens attacks it again with
   true items.
2. **A cross-cutting mode runs against every new page before the closing
   act:** S3's states (the level bar, a drilled category) run with the
   privacy mode forced on, and its backstop stays in the normal job.
3. **A gate's self-test includes a broken input**: N1's fixtures include
   a truncated document; the B2 registration's self-test includes a feed
   URL that resolves privately and one that redirects.
4. **No layout test pins pixels in an unshipped font**: S3's 390 px
   check holds with a stand-in wide font or does not measure text.
5. **GitHub writes go through the MCP tools.**
6. **The attack cases come before the parser** (N1).

And Sprint 25's that still apply: a story's item in a shared file sits
between its own markers (contract entry 27 with a news part and a bands
part, the contract test, `tools.ts`, the schema budget); every parallel
agent runs on its own test database; this planning PR carries no closing
keyword (checked before it was opened), and the sprint PR names
`Closes #1405` and the I23 issue.

### D-9: the ideas (the sprint workflow's "Ideas")

- **I23 and I24 leave the list** as their rows asked: FR-53 and FR-54 in
  `epics.md`, the rows pointers. I23 is Lane S. **I24 is Sprint 28's**,
  with its decision record on Sprint 28's planning PR, which settles the
  four points its row left (the benchmark the rule reads, overlapping
  manual windows, the 3-month recovery span, a fixed 10 %) with the
  adversarial pass on the detection rule. "I24 in 27" moves it here; the
  record would then come as a follow-up commit on this PR before its
  merge.
- **The next deep conversation: I9**, the review of every rule and ADR.
  You said on 2026-11-07 that the rules are too many, not consistent and
  pull away from where the project should go; I9 is that question, and it
  is triaged. Proposed shape for the conversation: an agent lists every
  rule in `AGENTS.md` and the two workflow pages with its reason and its
  last use, marks the ones whose reason is `(inferred)`, unused for ten
  sprints or contradicted by another, and you decide keep, merge or drop
  per row. Nothing is built before that conversation.

### D-10: one PR, no stack (recommended)

About 43 commits, so one PR merged by your "Rebase and merge" button. The
build order is the lane order (M, N, S), and inside a lane the story
order, so history goes forward only. N1 and N2 can run in parallel, as
can Lane S beside Lane N (no shared file but the contract entry and the
schema budget, each between its markers). A PR nearing 85 commits is cut
at its last finished lane into a stacked PR, named in the briefing.

### D-11: the `AGENTS.md` corrections (signed by this merge)

At your request of 2026-11-07: **the PR description names the agent, and
its model where the environment allows**, because Claude Code on the web
forbids a model name in a PR body and `CONTRIBUTING.md` already asked for
it only "if useful"; **an environment-assigned branch is the agent's own
branch** (named as assigned, covered by the rebase-and-force-push grant),
because that environment pushes only to the branch it assigns.

### D-12: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger (a switcher's export with those two types). #328 and #354 wait for
your check on real data. #1396 (per-source calibration) waits until the
sample can carry the split (ADR-0055 §9). The polish lists stay open while
they have lines; a story that touches a screen fixes its lines.

## Registry bookkeeping after the merge (the planning session's last step)

- #1405's body points at this plan and names B1 (the upkeep writes are
  now in its scope).
- File, as thin pointers: **the stacked chart** (I23, FR-53; Lane S)
  under #418 for this sprint; **the news layer's second half** (ADR-0056
  §7, §8, §9's cursor and `news.assign`, §10's view, A2's markers; FR-52)
  under #416 and **the crash rankings** (I24, FR-54) under #418, both for
  Sprint 28.
- `epics.md`'s tracker lines for FR-52 to FR-54 name the issues once
  filed.
- No closures by hand; no relabels.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 the version report
- [ ] Lane N: N1 the parser, N2 the tables, N3 the fetcher, N4 the
      matcher, N5 sources and stories, N6 retention and health, N7 the
      reads, N8 the writes, N9 the docs
- [ ] Lane S: S1 the bands in the walk, S2 the read, S3 the chart
- [ ] Closing act, fixes, re-check
- [ ] Close-out, retrospective, briefing, promotion
