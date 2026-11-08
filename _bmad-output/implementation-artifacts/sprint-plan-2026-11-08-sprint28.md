# Sprint 28 — two S1s in the quote sync, the news layer's second half, the stacked chart's filter

**Status: ADOPTED by the merge of the Sprint 28 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0058](../../docs/decisions/0058-crash-windows-detected-by-rule-ranked-by-price.md)
(crash windows, I24, FR-54; built in Sprint 29, D-2), the five planning
boards in
`design-language/mockups/ux-design-2026-11-08-sprint28/` and the decisions
below. A fresh implementation session builds the sprint on the branch its
environment assigns, or `agent/<provider>/sprint-28`, as **one** sprint PR
(D-10). The severity rule of ADR-0026's amendment of 2026-11-01 applies
unchanged.

## What you need to do

1. **Merge, to adopt the plan.** Nothing in it books or corrects a stored
   money figure. Two things change what you expected:
   - **I24, the crash rankings, is built in Sprint 29, not 28** (D-2). Its
     decision record, ADR-0058, is signed by this merge as Sprint 27's D-9
     promised. Two S1s in the quote sync (#1410, #1411), open since
     2026-11-07, come first, and the news view is due by the end of this
     sprint (Sprint 27's D-3). All of it does not fit under 90 commits.
     "I24 in 28" moves it back here; then FR-57 and the S1s' second half
     (#1415) leave instead.
   - **FR-55 needs one change on your side to show anything but
     „unbekannt“** (D-7): the Docker build never sees `.git`
     (`.dockerignore`, by design), so the version enters the image as a
     build argument. The home-deployment guide will give the one update
     command that sets it; built the old way, the instance honestly reads
     „unbekannt“.
2. **Look at board 01**, the news page. A (recommended) is a page
   „Nachrichten“ in the main navigation with three tabs; B spreads it over
   Verwaltung and a filter on Wertpapiere. And the note markers: pins at
   the chart's top edge (A, recommended) or dots on the line (B). Silence
   adopts A twice.
3. **ADR-0058 §1 answers one point differently from I24's row:** the row
   recommended "the benchmark flagged as the default comparison", and no
   such flag exists. The rule reads one benchmark you choose in a setting;
   until you choose one, only manual windows exist. "Crash-Benchmark je
   Anfrage" flips it.
4. **Optional, still open from earlier plans:** the `browser` CI job as a
   required status check on `main` (Settings → Branches, since Sprint 24);
   Dependabot's #1392 (`floki` 0.38.5, test only) is your merge.

**Not asked:** everything else. **Not raised:** the Bitcoin cycles (I12),
held by you.

**Verification basis:**

- **Sprint 27's merge, as its close-out asked this plan to record:** the
  sprint PR #1422 was merged at 08:06 UTC on 2026-11-08; CI run 1950
  green on `da41f43`; release **2026.11.12**. Its keywords closed #1405,
  #1419 and #1423.
- **Since then on `main`:** #1430 (I27 to I29 worked out, FR-55 to FR-57,
  I30 triaged; docs only, no release), merged at 11:03 UTC; CI run 1953
  green on `3cba116`. `main` is at `3cba116`.
- **The open-issue list of 2026-11-08:** 40 open: 19 `agentic` (#1429,
  #1428, #1427, #1426, #1425, #1424, #1421, #1420, #1417, #1416, #1415,
  #1414, #1413, #1411, #1410, #1396, #1070, #900, #899), 1 `agentic` and
  `needs-decision` (#1220), 1 `needs-decision` (#1177), 2 `needs-uat`
  (#328, #354), 17 trackers (11 polish lists #1355 to #1366 without
  #1364; #991; the five area trackers #416 to #420). One Dependabot PR is
  open: #1392.
- **Read against the code on `3cba116`**, each claim this plan rests on:
  - `QuoteSync.sync_all_unlocked/1` maps `sync_one/3` over
    `Catalog.list_securities()` and dispatches by `provider` alone;
    `feed` and `is_retired` are read nowhere on that path. Hence Q1.
  - `QuoteSync.Yahoo.decode/1` reads `timestamp` and the closes and never
    `meta.currency`. Hence Q2 and Q3.
  - `Portfolios.Performance.Bands`: the category bands are the tree's
    **root** categories, each over its subtree; `category_id` narrows only
    `level: :security`. `StackedChart.stack/1` (`stacked_chart.ex` ~532)
    stacks a negative day below zero and joins the days in one path
    (#1426). The level bar is three `.link patch` options, `Gesamt` the
    default. Hence S1 and S2.
  - The performance walk's TTWROR exists for the scope only; ADR-0051
    defines a position's net flows. Hence S3.
  - `mix.exs` says `version: "0.1.0"`; the calendar version exists only as
    a tag CI's Release workflow makes; `.dockerignore` leaves out `.git`;
    `Dockerfile.release` is the operator's build behind
    `docker compose up --build`. The sidebar's foot holds only
    `#sidebar-logout`, rendered when UI auth is on. Hence V1, V2 and D-7.
  - The news layer on `main`: no `news_labels` table, no consumer cursor,
    no `news.assign`; `news.health` answers
    `yield: "not_measured_until_promotion"` (C4). `Knowledge.append_note/3`
    takes no `cluster_id`; an entry has no `headline`, `event_type` or
    `tone` (ADR-0044's amendment of 2026-11-06 waits for this sprint).
    `security_chart.ex` draws transaction markers only. The security
    pane's tabs are `overview chart transactions trades quotes holdings
    classifications research predictions events`. Hence Lane N.
  - `Portfolixir.Settings` is a keyed store whose writers are private,
    one public helper per key with the actor (#1272); there is no stored
    default benchmark. Hence ADR-0058 §1.
  - The schema budget's ceilings in force are Sprint 27's last row; Sprint
    24's D-2 rule lets them grow by a new tool's own bytes and no more. The
    API contract's head is entry 27; this sprint's is entry 28.
- **Boards:** five, drawn for this PR (D-5, D-6), on the shipped
  `app.css`, the shell and the data-quality block captured from the review
  instance on the synthetic seed, every series synthetic.

## State of play, in five lines

1. **Sprint 27 is on `main`** (release 2026.11.12): the news layer's
   first half, agent first, and the stacked chart.
2. **Two S1s from the agent's data-quality report** (#1410, #1411) have
   waited a sprint: a stored quote series can be wrong while the screen
   says "Manual", or carry USD closes as EUR, and nothing names it.
3. **The news view is owed** by the end of this sprint (Sprint 27's D-3).
4. **You worked out I27 to I29 today**; I30 is triaged, "nur als
   Feedback".
5. **I24's record is signed here, built next sprint.**

## Why this cut

- **The S1s first.** The sprint workflow files an S1 at once; it does not
  say when it is fixed, but a figure that can be wrong without a word
  outranks every feature here. #1415 is the second half of #1411: #1411
  stops new mismatched rows, #1415 names the ones already stored.
- **The news view, because it is due.** The coverage rule makes an
  agent-only capability a close-out finding after the next sprint; Lane N
  delivers §10's view and the rest of ADR-0056 §11's second sprint.
- **The stacked chart's follow-ups, because they are small and fresh.**
  FR-56 changes code Sprint 27 wrote and carries #1426, an S2 in it; FR-57
  needs a per-band return in the walk, the one money computation in the
  lane.
- **I24 waits a sprint.** It is the largest item (a stored object, a rule,
  a new section, five tools) and the only one with nothing overdue. Its
  record is signed now so Sprint 29 starts building.
- **FR-55 rides along**: three commits, and D-7 settles the one thing that
  is not obvious.
- **The estimate is honest this time.** Sprints 26 and 27 took 69 and 79
  commits against estimates of 40 and 43: the closing acts' fixes, one
  commit each, are what the estimates left out. This plan budgets them
  (D-10).
- **What is left out, and why** (each flips by naming it): I24 (Sprint
  29, D-2); #1413, #1414, #1416, #1417 (the rest of the data-quality
  triage; #1416 and #1417 need boards, and #1416 pairs with I24's
  benchmark, Sprint 29); I20 (usage hints, waiting for your examples); I30
  (D-9); the polish lists other than the lines the touched files reach;
  #899, #900, #1070, #1220, #1177, #328, #354 and #1396 keep their
  standing reasons (D-12).

## Lanes (one sprint PR, in this order)

**Lane M, maintenance (first).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | standing rule | the version report `version-report-2026-11-…-sprint28.md`: Hex, npm, Elixir/OTP, PostgreSQL, BMAD core and the external modules, each bump its own commit, what is declined with its reason; #1392 (`floki` 0.38.5) is taken here if you have not merged it | 1–2 |
| M2 | #1425 (S2, flaky) | the log-noise check fails a full run under load on acceptor and checkout errors: the check tells an error a test caused from one the load caused, by the test's own process, or the two tests that trigger it stop leaking; a red run of the old check under `--max-cases` load seen first. **No ignore added** | 1 |

**Lane Q, the quote sync's two S1s** (#1410, #1411, #1415; ADR-0005).
**Risk tier: stored data** (a quote series every figure reads): its own
commit group, a dedicated verification pass, a callout in the briefing.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| Q1 | #1410, its recorded answer | the scheduled run and "sync all" skip a security whose `feed` is `MANUAL` or `NONE` (reason `:manual_feed`) or that is retired (`:retired`), counted as skipped like `:missing_ticker`; an explicit single-security sync of a retired security still runs; `securities.update`'s and `quotes.sync`'s descriptions name the stop. Tests first, each skip reason with a fake adapter that fails the test if called. The release notes name the change for imported securities whose PP feed was "Manual" | — (the skip count renders as today; if the build finds a new string on screen, it boards first) | 2 |
| Q2 | #1411, its recommended answer | the Yahoo adapter compares `meta.currency` with `currency_code` before it returns rows: a mismatch answers `{:error, {:currency_mismatch, provider_currency}}`, written nowhere, reported per security; a missing `meta.currency` passes as today; `GBp` against `GBP` (and the other minor-unit codes) is refused the same way. A fake answer per case, written first | — | 2 |
| Q3 | #1415, OQ-2's answer | one additive nullable column `provider_currency` on the security, set on every sync that reads one (Q2's value, stored before the comparison refuses); the data-quality set `currency_mismatch` (present and different from `currency_code`; benchmarks and retired left out like the other sets), counted on the Overview with the others, its `computation_basis` naming the stored provider currency and when it was read; the Overview clause and the filter chip of **board 05**. A seeded-upgrade test: a security synced before the column exists reads not-yet-known, never a mismatch | 05 | 3 |

**Lane N, the news layer's second half** (#1420; ADR-0056 §7 to §10,
§11's second half, §14 items 6 to 8, A2, C4's end; ADR-0044's amendment of
2026-11-06). **Risk tier: security** (a write from an outside model, a
schema change to the append-only log): its own commit group, a dedicated
verification pass, a callout in the briefing.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| N1 | §7 | **labels.** The `news_labels` table (§7's fields, every check constraint they allow: the event-type enum, materiality 0 to 3, tone −1/0/+1, confidence 0 to 1 as a decimal); `news.label_put` with a **closed schema**, an unknown field refused with 422 naming it (attack cases first: `security_id`, `tier`, `status`, `notes`, a nested object, an over-long string, a label for a cluster that does not exist), idempotent per `(cluster_id, model, prompt_version)`, journaled with its token; `news.unlabeled(prompt_version, limit)` with the universe once per answer and each assigned security's invalidation condition split into numbered clauses; the companion's `label` profile listing only those two tools, absent from the agent's profiles | — | 3 |
| N2 | §7, §14 items 6 to 8, C4 | **labels in the reads.** The active label per `prompt_version`; `min_materiality` and `include_unlabeled` acting on aggregator and thematic stories only, an issuer or regulatory story shown whatever its label (§14 item 7 as a test); `tone` never a filter or sort key (a test that passes it is refused); fail-open with no labels (item 8). With promotion built (N5), `news.health` answers `yield_30d` and `low_yield` as A3 says and drops C4's placeholder, in the same commit as N5's promotion or after it | — | 2 |
| N3 | §9 | **the digest's consumer cursor**: `consumer` and `ack_cursor`, the confirmed position per consumer, a call without confirmation reading again from it, an older cursor a no-op, a cursor the server did not issue to that consumer refused with 422, by `DeltaCursor`'s rule (overlap, never loss). **An order test:** a run that breaks off after the read loses nothing; two consumers never move each other | — | 2 |
| N4 | §9, #1424 | `news.assign(news_id, security_id or null)`, journaled, re-clustering the item's stories in its transaction as a merge does (ORD2's rule); `suggested_security_id` from the active label shown beside an `unassigned` or `ambiguous` item, never applied by itself. #1424's upsert race in `Sources.put_source` fixed here, because N1 and N4 touch the module: a red run under concurrent puts seen first | — | 2 |
| N5 | §8, A2, ADR-0044's amendment | **from story to knowledge.** The entry's `headline` (≤ 80, ADR-0054 §4's text rules), `event_type` (the fixed set, `String.to_existing_atom/1`) and `tone`, set once, accepted on `evidence` and `event_result` only, else 422 naming the field; `notes.append` with `cluster_id` pre-filling kind, `as_of`, `source_url`, `source_quality`, the headline cut at 80 on a word boundary, event type and tone from the active label, the label's id kept; the story `promoted` and linked; `events.create` with `news_id`. A seeded-upgrade test over stored entries without the fields | — | 3 |
| N6 | §9 | `securities.dossier`'s news block (count over 7 days, primary count, highest materiality, the newest primary story; its budget, about 50 tokens, as a test on the companion's text, carry-forward 4) | — | 1 |
| N7 | §10, board 01 A | **the page „Nachrichten“** in the main navigation, three tabs: Meldungen (the health line, the queue with Zuordnen, the digest per security with what it hid), Feeds (each feed with `news.health`'s fields and its state chips), Quellen (domain, tier, set by hand or default). No logic of its own: each region reads the API's read through the context the API uses. `DESIGN.md` gains the anatomy | 01 | 3 |
| N8 | §10, §8, board 01 | **the security's tab „Nachrichten“** after Research: its stories (`news.list`), each row with source, tier, time and label marked „maschinell“; „Ins Research-Log“ opens the note form pre-filled as N5 pre-fills it, and only its save writes (NFR-10) | 01 | 2 |
| N9 | A2, board 01 A | **the markers**: a research note with a headline drawn as a pin at the chart's top edge at its `as_of`, coloured by tone, its tooltip the headline, event type, tone and date; a „Notizen“ toggle beside „Transaktionen“ on the Diagramm tab and the Übersicht's small chart; never a raw item or a story. The privacy mode keeps them (no amount); its backstop and leak walk cover the new states | 01 | 2 |
| N10 | coverage rule | the API reference, `docs/integration` (English, then German), the operator guide's news passage: the page, the tab, the markers, the labeller's profile and token | — | 1 |

**Lane V, the version** (FR-55, #1429; board 04; D-7).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| V1 | FR-55, D-7 | the version read **once at compile time**: `PORTFOLIXIR_VERSION` (and `PORTFOLIXIR_COMMIT`, `PORTFOLIXIR_BUILD_DATE`) when the build sets them; else, in a source tree, the exact calendar tag (`git describe --tags --exact-match`), else branch, short hash and commit date; else `unknown`, never a guess. `Dockerfile.release` takes the three as build arguments and `docker-compose.yml` passes them through from the environment; the home-deployment guide's update command sets them from the checkout. `GET /api/v1/version` and `portfolixir.version` (the value, its kind `release` / `build` / `unknown`, the release-notes or commit URL). A test per kind, each with the source faked | — | 2 |
| V2 | FR-55, board 04 | the sidebar's foot and the phone's menu as board 04 draws them; the link is one the operator follows, the app requests nothing (a test asserts no outbound call). `DESIGN.md` gains the anatomy | 04 | 1 |

**Lane S, the stacked chart's filter and the TTWROR levels** (FR-56,
#1427 with #1426; FR-57, #1428; boards 02 and 03). S1 and S3 decompose a
figure the chart shows, so they get the money lens; S2 and S4 change
rendered output, so they get the design critic. **S3 and S4 are the
sprint's cut line** (D-10).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| S1 | FR-56 | **the filter in the bands.** `category_id` at `level: :category` gives the category's direct sub-categories as bands, each over its subtree, plus one band „‹name› (direkt)“ for the securities filed in the category itself (absent when it holds none), no cash, no `unclassified`; at `level: :security` as today; `category_id=unclassified` as a filter (its securities at either level; at `:category` one band); a category without sub-categories at `:category` is one band; with a filter, `:total` is the filtered category's line. **Pinned with exact `Decimal`s, each seen failing first:** on every day the filtered bands sum exactly to the parent's band; „(direkt)“ plus the sub-categories equal the category; the eight-band merge applies inside the filter; `computation_basis` names the filter and its level. The default level becomes `category` in the read's screen path only; the API's default stays `total` (D-6) | — | 2 |
| S2 | FR-56, #1426; board 02 | **the screen.** A click on a band or legend row sets the filter and keeps the level; the breadcrumb leads up one level at a time; „Nicht zugeordnet“ is drillable, cash and „Sonstige“ are not; „Kategorien“ is the default level. **#1426:** a band that changes sign inside the window sits next to the zero line and its positive and negative parts are separate polygons meeting at zero; a test with a band negative for two days asserts no band's edge crosses another's on any day. The lines of #1366 the touched files reach are fixed | 02 | 3 |
| S3 | FR-57 | **a per-band return in the walk**: each band's own TTWROR over the window, its buys, sells and deliveries as its flows (ADR-0051's net flows of a position, a group's the sum), starting at 0 % on the first day the band holds a value; the walk's other outputs byte-identical, pinned. The read takes `scale=ttwror` on the bands endpoint and tools, at most eight lines by value at the window's end, without `other`, `cash` and `unclassified`, with the filter of S1; the basis names the flows and the start rule. Exact `Decimal` expectations, seen failing first, including a band bought into mid-window and a band sold out mid-window | — | 2 |
| S4 | FR-57; board 03 | the TTWROR mode keeps the level bar and the filter and draws one line per band, the view's (or the filter's) line bold, the legend with TTWROR only and the bold line first, a late band's start as a dot | 03 | 2 |

**Closing act** (D-8), one per risk class when its group is done:

- **Lane Q:** the money lens (a stored series in each failure mode: a
  "Manual" feed, a retired security, a USD answer for a EUR security, a
  `GBp` answer, a missing currency; nothing written in any of them, the
  set naming each stored one) and the edge-case hunter.
- **Lane N:** the correctness hunter; the edge-case hunter; the **security
  lens** as a labeller that wants to write more than a label (fields,
  types, sizes, a cluster it was not given, invisible characters in a
  headline) and as an agent that wants an item assigned or promoted
  without a confirmation; the **order lens** on the cursor (two
  consumers, a broken run, an old cursor, a forged one) and on promotion
  and assignment racing a re-cluster; the **agent's lens** (the budgets on
  the companion's text, the wording, that each tool's answer reads as
  data); the **design critic** against board 01 in both themes at 1200 and
  390 px, with the privacy mode on and off.
- **Lanes V and S:** the money lens on S1 and S3 (every pinned sum and
  return recomputed independently; a buy, a sale, a category change, an
  unpriced day and a negative cash day inside the window); the design
  critic against boards 02, 03 and 04.
- **The UAT persona** on the review seed: syncs with a "Manual" and a
  retired security and a fake mismatched answer and reads the
  Overview; labels a story through the `label` profile, reads the digest
  with a cursor twice, assigns the queue's item on the page, promotes a
  story from the security's tab and finds its pin on the chart; filters
  Wealth's stack by a category with sub-categories at both levels and in
  both modes and compares a day with the API; reads the version on the
  screen and over the API.

**Close-out** (the PR's last commits): `sprint-status.yaml`, `epics.md`'s
FR Coverage Map (FR-52 complete, FR-55, FR-56, FR-57) and a dated
reconciliation, the idea list (I27 to I29 built; I21 built), the
retrospective, the version report.

**Estimate** (D-10): M 2–3, Q 7, N 21, V 3, S 9: **about 43 build
commits**; the closing act's fixes, at Sprints 26 and 27's rate, about 25
to 30; the close-out about 5. **About 75 to 80**, under 90 with S3 and S4
as the cut line.

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **No quote row is written behind a "Manual" or "None" feed, for a
   retired security in the full run, or in a currency the provider did not
   state as the security's**, each pinned by a fake adapter; and every
   security whose stored provider currency differs is in the
   `currency_mismatch` set.
2. **A label can change nothing but a label:** every field outside §7's
   schema is refused with 422 naming it, and the journal names the token
   that wrote each label (§14 item 6).
3. **A label sorts but never hides what is certain:** an issuer story with
   materiality 0 appears in the digest; with no labels at all every read
   answers (§14 items 7 and 8).
4. **The cursor loses nothing:** a run that breaks off after a read sees
   the same stories again; two consumers never move each other.
5. **A story becomes knowledge only by a confirmed write**, and only a note
   with a headline is drawn on the chart.
6. **The operator sees what the agent sees:** the page's regions and the
   security's tab answer the same as the API for the same request.
7. **The filtered bands add up:** on every day of every pinned case the
   bands sum exactly to their parent's band, „(direkt)“ included; the
   per-band returns are pinned with exact `Decimal`s; the walk's other
   outputs are byte-identical.
8. **No band crosses another** (#1426), on any day.
9. **The version is never a guess:** each kind pinned with its source
   faked; the screen makes no request.
10. **Every gate holds by registration, not by weakening**, and the
    regressions this sprint introduced are counted apart from the older
    findings, none an S1 at promotion.

**No criterion counts open issues.** Reported, not judged: 40 open today.

**To flip by comment:** name a criterion to drop or add.

### D-2: I24 waits for Sprint 29; its record is signed now (recommended)

ADR-0058 is on this PR as Sprint 27's D-9 promised, and the merge signs
it. The build moves to Sprint 29 because the sprint cannot hold it with
the two S1s and the news view under 90 commits (see "Why this cut"). Its
screen's planning board (from idea board 03, with the states the record
adds: no benchmark chosen, a provisional window, a name without a window)
comes on Sprint 29's planning PR. **To flip:** "I24 in 28" moves it here,
and then FR-57 (S3, S4) and #1415 (Q3) move to Sprint 29.

### D-3: two-way coverage (standing)

Lane N delivers Sprint 27's owed view (§10), so FR-52's first half stops
being agent-only. **One part stays agent-only by ADR-0056 §10**, which
names assign as the view's only action: feeds and sources are registered,
changed and deleted through the API and the companion, and the page shows
them. That is stated here as the rule asks; "Feeds am Bildschirm pflegen"
adds the forms (about two commits, a board first). Lane Q's set, Lane V's
read and Lane S's reads ship with their screens.

### D-4: the order of the work (recommended)

M, Q, N, V, S, in that order, and inside a lane the story order, so
history goes forward only. Q before N because an S1 should not wait behind
twenty news commits; V before S because it is small and S carries the cut
line. Lane S can run in parallel beside Lane N (no shared file but the
contract entry, `tools.ts`, the schema budget and gettext, each between
its markers); Q3 waits for Q2; N2 waits for N1, and its yield half for N5.

### D-5: board 01, the news view (recommended)

- **A page „Nachrichten“ in the main navigation**, after Wertpapiere,
  with the tabs Meldungen, Feeds and Quellen (board 01 A). *Why:* the
  digest, the queue and the health are one question, "what is new, and
  is the collector alive", which the agent answers with one call; spread
  over Verwaltung and a filter (B), the screen would have no place for
  the digest. "News verteilt" picks B.
- **A tab „Nachrichten“ on the security**, after Research, with „Ins
  Research-Log“, the same write as `notes.append` with `cluster_id`. *Why:*
  §8's promotion is an agent capability; without the button the operator
  could read a story and not keep it. "news promote agent only" drops the
  button.
- **The markers as pins at the top edge** (A), coloured by tone, toggled
  by „Notizen“. *Why:* dots on the line (B) cover the trade triangles and
  the price on the same day. "Marker B" picks B.
- **Feeds and sources are shown, not edited, on screen** (D-3).

### D-6: what boards 02 to 05 fix beyond what you decided (recommended)

- **Board 02 (FR-56):** sub-categories and a filter's securities take the
  palette in order, as Sprint 27's board 01 set for a drilled category;
  „(direkt)“ is the last colour. **The API's default level stays
  `total`**, only the screen's becomes „Kategorien“, so an agent's call
  without `level` answers as before (the contract does not change under
  it). "FR-56 API Kategorien" changes the API's default too.
- **Board 02 (#1426):** the band that changes sign sits next to zero, its
  negative part a little lighter.
- **Board 03 (FR-57):** the legend shows TTWROR only, the bold line first;
  a late band's start is a dot.
- **Board 04 (FR-55):** a small „Version“ label over the value in
  monospace, a hairline above; a build links its commit; „unbekannt“ is
  italic and links nothing.
- **Board 05 (#1415):** one clause in the Overview's problem line after
  the implausible series, with its effect on the total, and a chip
  „Währung abweichend“ beside „Kein Wechselkurs“.

Each flips by naming the board and the point.

### D-7: how the version reaches a Docker build (recommended)

The image never sees `.git`, and that stays: `.dockerignore` mirrors
`.gitignore` so nothing outside the source enters a build (E25 S2). So
the version enters as three **build arguments** that `docker-compose.yml`
passes from the environment, and the home-deployment guide's update
command sets them from the checkout in one line. A build without them
reads `unknown`, which is true, as FR-55 requires ("never a guess"). A run
from source reads git at compile time. *Why not a build stage that reads
`.git`:* it would put the repository's history into the build context of
every build to produce one string, and change a file whose rule has its
own test. **To flip:** "FR-55 git im Build".

### D-8: the closing act and the build (standing, with Sprint 27's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's section "What a story's own tests do
not cover" applies to every story; Sprint 23's four build rules stand.
Sprint 27's carry-forwards, applied:

1. **A gate a story widens gets a lens that attacks it before
   integration:** N1's `label` profile and its closed schema, and any
   registration Lane N adds to B2 to B7, are attacked by an agent other
   than the story's author with a caller or field the registration did
   not name, before the story is integrated.
2. **A public function that performs I/O is a chokepoint:** V1 makes no
   request and says so in a test; nothing in this sprint adds an outbound
   caller, and B2 stays as it is.
3. **The browser job runs locally before each closing act**, on the
   integrated head (`mix test test/browser --only browser`).
4. **Budgets are measured on the companion's text from the first
   commit:** N1's `news.unlabeled`, N3's digest with a cursor, N6's
   dossier block.
5. **An order lens on any rule that reads several records,** and of every
   tie-break key the question which of its parts are constant within one
   batch: N3's cursor, N4's assignment against a re-cluster, S1's merge
   into „Sonstige“ inside a filter.

And the older ones that still apply: a story's item in a shared file
sits between its own markers (contract entry 28 with a Q, an N, a V and
an S part; the contract test; `tools.ts`; the schema budget; and, new for
the conflicts Sprint 27 met, **`news.ex` gets markers per story before
N1 starts**); every parallel agent runs on its own test database; GitHub
writes go through the MCP tools; this planning PR carries no closing
keyword (checked before it was opened), and the sprint PR names `Closes`
for #1410, #1411, #1415, #1420, #1424, #1425, #1426, #1427, #1428 and
#1429 that it finishes.

### D-9: the ideas (the sprint workflow's "Ideas")

- **I27 to I29 leave the list** as their rows asked: FR-55 to FR-57, built
  here. **I24** stays a pointer, its record ADR-0058, built in Sprint 29.
- **I30 (categories through time) has a cheap first answer that needs no
  build:** a classification tree applies to every security, sold ones
  included, so filing the old positions in the new tree (the
  classification page lists securities without holdings behind its
  filter) removes the past „Nicht zugeordnet“; and FR-56 makes that
  remainder a filter, so it shows what is missing. Whether the moves
  between categories should be visible is the row's reading (2), a
  change to ADR-0006 and its own record; nothing is planned until you
  ask for it.
- **The next deep conversation: I9**, the review of every rule, proposed
  by Sprint 27's plan and not held. To make it short, Sprint 29's planning
  session brings the table (every rule in `AGENTS.md` and the two workflow
  pages with its reason, whether a gate enforces it, and its last use),
  and you mark keep, merge or drop per row.

### D-10: one PR, the cut line, no stack (recommended)

About 75 to 80 commits, so one PR merged by your "Rebase and merge"
button. A stack is not available here: the environment pushes only to the
branch it assigns. So the plan carries **a cut line instead of a stack:
if the PR stands above 70 commits when Lane S reaches S3, S3 and S4 move
to Sprint 29** (FR-57 stays planned, #1428 stays open), named in the
briefing, and the closing act and close-out run on what was built.

### D-11: no `AGENTS.md` change

This plan changes no rule. Lane V adds two build arguments and a
deployment step; the home-deployment guide carries them.

### D-12: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger (a switcher's export with those two types). #328 and #354 wait for
your check on real data. #1396 (per-source calibration) waits until the
sample can carry the split (ADR-0055 §9). #1413, #1414, #1416 and #1417
are Sprint 29's candidates with I24 (#1416 and #1417 board first). The
polish lists stay open while they have lines; a story that touches a
screen fixes its lines.

## Registry bookkeeping after the merge (the planning session's last step)

- #1421's body points at ADR-0058 and names Sprint 29.
- #1420's body points at this plan and D-3 (the feed writes stay
  agent-side).
- #1415's body notes it rides in this sprint with #1410 and #1411.
- No closures by hand; no relabels; nothing new to file.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 the version report, M2 the log-noise check (#1425)
- [ ] Lane Q: Q1 the skipped feeds (#1410), Q2 the currency check (#1411),
      Q3 the stored provider currency and its set (#1415)
- [ ] Lane N: N1 labels, N2 labels in the reads, N3 the cursor, N4 assign
      (#1424), N5 promotion, N6 the dossier, N7 the page, N8 the tab,
      N9 the markers, N10 the docs
- [ ] Lane V: V1 the version read, V2 the foot
- [ ] Lane S: S1 the filter in the bands, S2 the screen (#1426), S3 the
      per-band return, S4 the TTWROR lines (the cut line, D-10)
- [ ] Closing acts, fixes, re-check, the UAT persona
- [ ] Close-out, retrospective, briefing, promotion
