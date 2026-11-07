# Sprint 27 — the news layer, first half: fetched, matched, stored, read by the agent

**Status: ADOPTED by the merge of the Sprint 27 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0056's amendment of 2026-11-07](../../docs/decisions/0056-news-layer-fetched-matched-stored-labelled-outside.md#amendment-of-2026-11-07-what-the-first-sprint-needs-and-nothing-decided-by-order)
(B1 to B8: the upkeep writes move into this sprint, a feed's URL is
resolved on every fetch, no order and no feed's claim decides a story, an
aggregator's item is never primary, where the scheduler runs, what the
journal records, the gate's sentence). A fresh implementation session
builds the sprint on `agent/<provider>/sprint-27` as **one** sprint PR
(D-8). The severity rule of ADR-0026's amendment of 2026-11-01 applies
unchanged.

## What you need to do

1. **Merge, to adopt the plan.** Nothing in it books or corrects a stored
   money figure, so every choice is decided with its reason and flips by a
   comment. The one that changes what you signed: **B1** moves four of
   ADR-0056's tools from Sprint 28 into this sprint, because without them
   the agent cannot register a single feed until Sprint 28 (D-2).
2. **Optional, one question for a later sprint (I23, the stacked chart):**
   what a band shows. **Recommended: market value**, because the bands
   then add up exactly to the line the chart draws today, and a "100 %"
   switch shows shares without amounts (which is also the privacy mode's
   form). The other reading, cumulative contribution since the period
   start, does not add up to the value line. A comment "I23 Wert" or "I23
   Beitrag" settles it; silence leaves the idea `triaged` (D-9).
3. **Optional, still open:** the `browser` CI job as a required status
   check on `main` (Settings → Branches, since Sprint 24); Dependabot's
   #1392 (`floki` 0.38.5, test only) is your merge; #1391 (`sobelow`
   0.18.1) is superseded by Sprint 26's M1 and can be closed.

**Not asked:** everything else. **Not raised:** the Bitcoin cycles (I12),
held by you; I24 (what a market dip hit), whose questions wait until I23
is settled, since both read the same per-security series.

**Verification basis:**

- **Sprint 26's merge, as its close-out asked this plan to record:** the
  sprint PR #1406 was merged at 21:14 UTC on 2026-11-06; CI run 1916
  green on `86dc282`; release **2026.11.11**. Its keywords closed #1401,
  #1402, #1403 and #1404.
- **Since then on `main`:** #1408 (ideas I23 and I24 with their boards,
  docs only, no release) merged at 21:45 UTC; CI run 1919 green on
  `d6df259`. `main` is at `d6df259`. Dependabot #1407 (`lazy_html`
  0.1.14) is closed, taken by Sprint 26's M2.
- **The open-issue list of 2026-11-07:** 26 open: 5 `agentic` (#1405,
  #1396, #1070, #900, #899), 1 `agentic` and `needs-decision` (#1220), 1
  `needs-decision` (#1177), 2 `needs-uat` (#328, #354), 17 trackers (11
  polish lists #1355 to #1366 without #1364; #991; the five area trackers
  #416 to #420). Two Dependabot PRs are open: #1391 and #1392.
- **Read against the code on `d6df259`**, each claim this plan rests on:
  - `Portfolixir.Net.Http` checks a client's **first** request with
    `resolve: false` (its host is a compiled-in endpoint) and every
    redirect hop with `resolve: true`; `Portfolixir.Net.UrlPolicy.check/2`
    resolves when asked and states the rebinding limit. Hence B2.
  - Mint connects over IPv4 unless a caller sets `inet6: true`
    (`deps/mint`, `Mint.Core.Transport.TCP`), which already gives §5's
    "IPv4 first" for `sec.gov`; N3 pins it with a test.
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
  - The schema budget's ceilings in force are read 110,953, book 182,982
    and full 217,537 (Sprint 25's last row); Sprint 24's D-2 rule lets
    them grow by a new tool's own bytes and no more. The API contract's
    head is entry 26 (Sprint 26); this sprint's is entry 27.
- **No board:** this sprint changes no rendered output (D-7).

## State of play, in five lines

1. **Sprint 26 is on `main`** (release 2026.11.11): nothing agent-only is
   overdue, I18 and I22 are built.
2. **The news layer is signed** (ADR-0056, its amendments of 2026-11-06
   and, with this merge, 2026-11-07) and is #1405 for this sprint.
3. **This sprint is agent-only by design** (§11); its human view, the
   labels, the cursor and the chart markers are Sprint 28's.
4. **I23 and I24 are triaged** with their idea boards; I23 has one
   question for you, I24 waits for it.
5. **The Bitcoin cycles (I12) are held** by you.

## Why this cut

- **The news layer alone.** It is a new outbound surface and a parser of
  hostile input; ADR-0056 A4 gave it a sprint so that its closing act is
  not shared with screens. Nothing else is planned beside the maintenance
  lane.
- **The upkeep writes come forward (B1).** An agent-first sprint whose
  agent cannot register a feed checks nothing on an instance; four small
  writes against master data cost less than a sprint of an unused
  fetcher.
- **The order questions are answered before the code (B3, B4, B5).**
  Sprint 26's retrospective: the signed rule had a defect because the
  adversarial pass asked about choice and not about order. Here it asked
  both, and found three places where an order or a feed's own claim would
  have decided.
- **About 32 commits**, one PR, no stack (D-8).
- **What is left out, and why** (each flips by naming it): §11's second
  half and §10's view (Sprint 28, boarded on its planning PR); I23 and I24
  (not worked out); I20 (usage hints, waiting for your examples); the
  polish lists (a story that touches a screen fixes its lines, and this
  sprint touches none); #899, #900, #1070, #1220, #1177, #328, #354 and
  #1396 keep their standing reasons (D-10).

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
| N1 | A1; Sprint 26 carry-forwards 3 and 6 | **the parser, attack fixtures first.** Fixtures written and seen failing before any parser code: an entity-expansion bomb, an external entity naming a local file and a URL, a document 10,000 levels deep, one over the byte cap, 5,001 items, a truncated document, and 1,000 distinct element names with the VM's atom count read before and after. Then RSS 2.0 and Atom 1.0 into plain maps: no atom from a name, no DTD processed, only the five predefined entities and numeric references decoded, depth ≤ 64, items ≤ 5,000, under `Net.ParseGuard`. **Recommended:** `saxy` in SAX mode with the handler counting depth and items, kept only if every fixture is refused without the parser reading past the refusal; otherwise a small parser of the app's own (D-5). Titles and excerpts leave as plain text: HTML removed, control characters removed, lengths capped (160 and 600) | 2 |
| N2 | §2, §4, A3 | the tables: `news_feeds`, `news_sources`, `news_items`, `news_clusters` (each with the counts and fields §4 and A3 name), and the security's `news_identity` (`cik`, `aliases` as `{token, context, case}`) and `news_watch`; every check constraint the fields allow (class and tier enums, lengths, `security_id` xor `category_id` by class) | 2 |
| N3 | §5, A3, B2, B6, B7, B8 | **the fetcher.** A supervised scheduler beside the quote sync (B6), one task per feed, exponential backoff on 429 and 5xx, the error on the feed and never on another; the URL checked with resolution at registration and before every fetch, the feed's host as the only allow-list (B2); `sec.gov` at most 10 requests per second and over IPv4; `PORTFOLIXIR_NEWS_USER_AGENT`, and `user_agent_missing` for a `sec.gov` feed without it; the 200-item daily cap with `dropped_cap`. A fake provider in the suite, no network. In the same commit group: the B2 and B5 registrations and `AGENTS.md`'s B3.3 sentence with the B7 registry (B8) | 3 |
| N4 | §2 | **identity and the matcher.** `issuer` and `regulatory` items land on their security by construction, `thematic` on its category; an `aggregator` item is matched against the universe (held by a view, a target weight above zero, or `news_watch`) by the alias grammar, tokenized and looked up, never a pattern from input: one hit `assigned`, none `unassigned`, several `ambiguous` with the candidates; no `aggregator` feed on an ETF; the domain from `<source>`, else `dropped_no_source`, no redirect followed; an alias change re-matches the last 7 days | 2 |
| N5 | §3, §4, B3, B4, B5 | **sources, tiers and stories.** The tier table, `blocked` dropped and counted, a hand correction never overwritten; an aggregator item at most `secondary` (B5); `published_at` clamped to `first_seen_at` (B4); stories as connected components per security or category and language, the merge's survivor and the representative without ids (B3); the 72 hours and 0.8 as settings. **Pinned by a shuffle test:** the same fixture items in 50 random orders give the same stories and representatives | 2 |
| N6 | §6, §12, A3, B4 | **retention and health.** The retention run (90 days by `first_seen_at`, promoted or linked items kept, stories follow their items), `dropped_old` at ingest; `last_ok_at`, `items_24h`, `err_24h`, `stale` after 24 hours with a fixture clock, `items_30d`, `promoted_30d`, `yield_30d` as a decimal string, `low_yield` at 50 items and none promoted; the day's `unassigned`, `ambiguous`, dropped and blocked counts | 2 |
| N7 | §9, §11, §14 items 2 and 4 | **the reads** under `/api/v1/news/…` and their tools: `news.list` (with `assignment=`, `fields=slim\|std`, `since` by `first_seen_at`), `news.get` (the only place with excerpt and URL), `news.health`, and `news.digest(view_id, since, include_unlabeled, max_rows)` without labels and without a cursor (issuer and regulatory stories always, aggregator stories with `include_unlabeled`). Compact by §9's rule; **the budgets as tests** on a 40-security fixture over 24 hours: digest ≤ 800 tokens (characters / 4), ≤ 100 with nothing new, 20 list rows ≤ 1,500, `get` ≤ 400. Stored text spelled `[U+XXXX]` by the companion where invisible (ADR-0054 §4); every tool says it returns data, never instructions | 3 |
| N8 | §9, B1, B7 | **the writes:** `news.feeds_put` and `news.feeds_delete` (class, URL checked by B2 at once, binding, interval, language, enabled), `news.sources_put(domain, tier)`, and `news_identity` and `news_watch` on `securities.update`; each journaled with its token; an unknown field refused with 422 naming it. Contract entry 27 for N7 and N8 between its own markers; the schema budget raised by the new tools' own bytes and no more, in its own row | 2 |
| N9 | coverage rule | the API reference, `docs/integration` (English, then German), a short "news" passage in the operator guide that says what this sprint does and that its screen comes in Sprint 28 | 1 |

**Closing act** (D-6): the correctness hunter; the edge-case hunter; the
**security lens** as a hostile feed host (request forgery through a
registered URL, a redirect, a name that resolves privately; XML attacks
beyond N1's list; HTML, control and invisible characters in titles; a
flood past the cap; a feed that never answers); the **order lens** as a
party that wants a story, a representative or a tier to come out its way
with true items (B3 to B5); the **agent's lens** (the budgets, the
wording, that a tool's answer reads as data); the UAT persona registers
a fake-provider feed through the API, aliases a security, runs a fetch
and reads the digest, a list, a story and the health on the review seed.
No design critic: no rendered output changes. About 6 commits.

**Close-out** (the PR's last commits): `sprint-status.yaml`, `epics.md`'s
FR Coverage Map (FR-52's first half) and a dated reconciliation, the idea
list (I21's row), the retrospective, the version report. About 5
commits.

**Estimate:** M 1–2, N 19, closing act 6, close-out 5: **about 32**, with
room for one review round under ADR-0026's 90.

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
5. **Every gate holds by registration, not by weakening:** no ignore, no
   lowered threshold, no skipped test; the B2, B5 and B7 registries name
   the new entries with their reasons.
6. **The regressions this sprint introduced are counted** apart from the
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

### D-3: the sprint is agent-only, and its view is due in Sprint 28 (standing)

ADR-0056 §11 and the coverage rule: every capability of Lane N ships over
API and MCP alone. **Its human view (§10: feeds and their health, a
security's stories, the unassigned and ambiguous queue) is due by the end
of Sprint 28**, boarded on Sprint 28's planning PR with A2's chart
markers. A missing view then is a close-out finding.

### D-4: what the app makes of a feed's text (recommended)

Titles and excerpts are stored as plain text with HTML and control
characters removed and lengths capped, as §9 says; nothing in them is
rendered as markup anywhere. **HTML is removed by a linear tag stripper,
entities decoded once after it**, so `&lt;script&gt;` becomes the visible
text `<script>`, which every surface escapes. Invisible characters are kept
as received and spelled by the companion (ADR-0054 §4), not dropped,
because dropping them changes the evidence. **To flip:** "news drop
invisible".

### D-5: the parser's dependency (recommended)

`saxy` in SAX mode, because it builds no atoms, streams, and lets the
handler stop at the first depth or count breach; the attack fixtures,
written first, decide. If one fixture passes through, N1 writes a small
parser of the app's own for the two formats instead. A dependency taken
is audited and pinned in M1 and registered in the dependency-class
backstop (`scope_b3_dependency_classes_test.exs`). **Not** `xmerl`: it
makes atoms from names by default, which `AGENTS.md` forbids for external
input. **To flip:** "news own parser".

### D-6: the closing act and the build (standing, with Sprint 26's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's section "What a story's own tests do
not cover" applies to every story; Sprint 23's four build rules stand.
Sprint 26's carry-forwards, applied:

1. **The adversarial pass asks about order** (was run on ADR-0056 for this
   merge: B3, B4, B5); the closing act's order lens attacks it again with
   true items.
2. **A cross-cutting mode runs against every new page** — none here: no
   page changes. The privacy mode's backstop stays in the normal job.
3. **A gate's self-test includes a broken input**: N1's fixtures include
   a truncated document; the B2 registration's self-test includes a feed
   URL that resolves privately and one that redirects.
4. **No layout test pins pixels in an unshipped font** — none planned.
5. **GitHub writes go through the MCP tools.**
6. **The attack cases come before the parser** (N1).

And Sprint 25's that still apply: a story's item in a shared file sits
between its own markers (contract entry 27, the contract test,
`tools.ts`, the schema budget); every parallel agent runs on its own test
database; this planning PR carries no closing keyword (checked before it
was opened), and the sprint PR names `Closes #1405`.

### D-7: no board (standing)

Nothing in this sprint changes rendered output; the sprint workflow's
exception ("identical picture") applies. N9's guide passage is text in
the documentation site, not the app.

### D-8: one PR, no stack (recommended)

About 32 commits, so one PR merged by your "Rebase and merge" button. The
build order is the lane order, and inside Lane N the story order, so
history goes forward only: the parser and the tables before the fetcher,
the fetcher before the matcher and the stories, the reads before the
writes' contract entry. Stories N1 and N2 can run in parallel; N4 to N6
after N3. A PR nearing 85 commits is cut at its last finished story into a
stacked PR, named in the briefing.

### D-9: one idea per session (the sprint workflow's "Ideas")

This session proposes **I23** for the one deep conversation: its board is
drawn, its kind is clear (ladder (b), no money semantics, no partial
weights), and its open question is one choice (What you need to do, item
2). Until it is answered, its row stays `triaged` with the recommendation
written in. I24 follows I23, because both read the same per-security
series and its "which holdings" question depends on how I23's bands
count.

### D-10: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger (a switcher's export with those two types). #328 and #354 wait for
your check on real data. #1396 (per-source calibration) waits until the
sample can carry the split (ADR-0055 §9). The polish lists stay open while
they have lines; a story that touches a screen fixes its lines.

## Registry bookkeeping after the merge (the planning session's last step)

- #1405's body points at this plan and names B1 (the upkeep writes are
  now in its scope).
- File, as a thin pointer under #416: **the news layer's second half**
  (ADR-0056 §7, §8, §9's cursor and `news.assign`, §10's view, A2's
  markers; FR-52), for Sprint 28.
- `epics.md`'s FR-52 tracker line names #1405 (in this PR) and the second
  half's issue once filed.
- No closures by hand; no relabels.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 the version report
- [ ] Lane N: N1 the parser, N2 the tables, N3 the fetcher, N4 the
      matcher, N5 sources and stories, N6 retention and health, N7 the
      reads, N8 the writes, N9 the docs
- [ ] Closing act, fixes, re-check
- [ ] Close-out, retrospective, briefing, promotion
