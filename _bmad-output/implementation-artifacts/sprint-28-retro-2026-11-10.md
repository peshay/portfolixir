# Sprint 28 Retrospective — the news layer's second half, the version, and the stacked chart's second round (2026-11-10)

ADR-0026 step 5 for Sprint 28, written by the implementation session as the
sprint PR's last commits (sprint workflow §5). The plan,
`sprint-plan-2026-11-08-sprint28.md`, and its amendment,
`sprint-plan-2026-11-08-sprint28-amendment.md`, were adopted by the merge
of their planning PRs, which signed ADR-0058 (FR-54, built in Sprint 29)
and the amendment's D-A1 to D-A5. The close-out entry with every
criterion and count is in `sprint-status.yaml`; this file keeps what the
sprint teaches.

## What shipped

One PR under the plan's D-10: the sprint PR #1436
(`claude/busy-meitner-21kgtg`, the branch the environment assigned),
94 commits after the history cleanup and before the UAT's screenshots and
the close-out's three, against an estimate of about 75 to 80; no stacked
PR. The cut line (S3 and S4 to Sprint 29 if the PR stood above 70 commits
when Lane S reached S3) did not apply: it stood under 60.

- **Lane M:** the base red on `main` (PrivacyModeTest read a chart
  coordinate's "644.55" as the figure "44.55"), fixed first; M1, `floki`
  0.38.5 (test only, Dependabot #1392) and the version report; M2, the
  log-noise check's two sources quiet under load (#1425).
- **Lane Q, the quote sync's three gaps** (#1410, #1411, #1415): Q1, a
  "Manual" or "None" feed and a retired security skipped by the full
  sync; Q2, an answer in another currency refused and stored nowhere;
  Q3, the provider's stated currency kept on the security and listed in
  `currency_mismatch` over API, MCP and the Overview.
- **Lane N, the news layer's second half** (FR-52, #1420; risk tier
  security): N1 labels through one closed write under a `label` profile;
  N2 labels in the reads; N3 the per-consumer cursor; N4 `news.assign`;
  N5 promotion to a research note; N6 the dossier's news block; N7 the
  page „Nachrichten“ with the registry read; N8 the security's tab;
  N9 the note pins on the chart; N10 the documentation and ADR-0056's
  amendment of 2026-11-09 (D1 to D10). The flaky #1424 was fixed with N4.
- **Lane V, the version** (FR-55, #1429): V1, the version read at compile
  time from the checkout or the release image's build arguments, over
  `GET /api/v1/version` and `portfolixir.version`; V2, the sidebar's foot.
- **Lane S, the stacked chart's second round:** S1, `category_id` a filter
  at every level (FR-56, #1427); S2, the screen with the filter, the
  breadcrumb and a sign-changing band at the zero line (#1426), three
  lines of #1366; S5, the period kept in the address and the browser
  (#1432); S6, the privacy mode's shape-keeping stack (#1433); S3, each
  band's own TTWROR (FR-57, #1428); S4, the TTWROR lines.
- **The closing act:** attack lenses on Q3, N1 and N3/N4 before each was
  integrated; the Q lens; the S6 privacy lens; the money lens and the
  design critic on Lanes S and V; five N lenses (correctness, edge cases,
  security, the agent, the design critic on board 01); the browser
  privacy walk widened to the new pages; the fixes; a re-check of every
  fix on the integrated head; the UAT persona on the review seed, with
  14 screenshots in `uat-sprint28-2026-11-10/`.

## What went well

* **THE ATTACK LENS CAME BEFORE INTEGRATION, AS CARRIED FORWARD.** Sprint
  27's carry-forward 1 was applied to every story that widened a gate or
  wrote a new kind of record: Q3's provider-currency writer, N1's label
  write, N3's cursor and N4's assignment each met a lens that attacked
  them before they were cherry-picked. Eight findings came back from the
  N attacks alone (five S2: names cut by width, a superseded thesis, a
  deadlock between `news.assign` and a merge, a truncated digest whose
  cursor confirmed past rows it left out, a story hidden while unlabelled
  and lost once labelled), each a red test before its fix. V1's
  subprocess entry in B2 shipped with its own attack self-test.
* **THE MONEY LENS FOUND THE ONE INTRODUCED S1 BEFORE ANYONE ELSE.** A
  short covered inside the window turned its band's TTWROR line to
  −100 % (ML1): the cover day's opening value was negative, so the day's
  factor was zero. The lens wrote the red test; the fix (a day whose
  opening value is not positive adds no return) and its sentence in the
  basis landed before promotion, and the re-check saw the test go red
  with the fix reverted.
* **THE UAT AGREED WITH THE API TO THE CENT.** Wealth's filtered stack
  matched `GET /api/v1/performance/bands` on all 366 days of the window,
  at both levels and in both modes; the version read the same on the
  screen and over the API; the digest's cursor read twice as the
  at-least-once flow documents; a promoted story's pin was on the chart.
* **NO CEILING WAS RAISED TO MAKE ROOM.** The schema budget stood at its
  ceiling after Lane S; every later tool's growth was paid inside its own
  commit by tightening other tools' wording, and only three new tools'
  own bytes raised a ceiling (news.assign, news.registry, the version
  read). The re-check measured every profile exactly at its ceiling.
* **THE RE-CHECK REVERTED THE FIXES.** For every money and security fix
  it reverted the code locally and saw the pinning test go red, then
  restored it: 24 of 38 fix ids tried that way, the rest wording, budgets or UI
  asserted word for word.

## What did not go well

* **THE PR OUTGREW ITS COUNT.** 102 commits stood on the branch before the
  UAT's fixes, against an estimate of 75 to 80, and GitHub's "Rebase and
  merge" refuses a PR above 100. The history cleanup folded twelve
  mechanical follow-ups into the commits they belong to (docs into their
  features, red tests into their fixes, a CI repair into the story it
  repairs), the final tree byte-identical to a backup ref, and merged the
  close-out's registry and idea-list commits into one. *Cause:* the plan
  estimated the closing act's fixes at Sprints 26 and 27's rate, 25 to
  30; this sprint's closing act made about 55, because Lane N alone met
  four attack and lens passes and its UI group was integrated last.
* **THE N UI GROUP LANDED AFTER V AND S.** The plan's lane order (D-4)
  puts N before V and S; N7 to N10 were still in their closing act when
  Lanes V and S were done, so the history reads M, Q, N's backend, V, S,
  then N's screens and their fixes. Parallel lanes were allowed; the
  order is named here and in the briefing.
* **THE BROWSER JOB FAILED TWICE FOR ONE CAUSE.** The privacy walk,
  widened to the new pages, ran past CI's 20 minutes, and a page left
  while its loads ran killed a load task mid-query, which drops the shared
  sandbox's connection and fails every later request with an ownership
  error. The walk learned to wait for every busy marker before it
  leaves, the skeletons learned to say they are busy, and the job's limit
  went to 35 minutes (a loosened bound, named). After integration the
  same cause failed `PeriodMemoryTest` once in CI, S5's own walk, which
  had not taken the rule. *Cause:* the settle rule lives in one script
  (`privacy_leak.js`) and nothing makes the next browser test use it;
  and Sprint 27's carry-forward 3 (the browser job locally before the
  closing act) was kept only after CI had already failed.
* **A STORY'S TEST BROKE UNDER CI'S COVER RUN.** V1's no-outbound checks
  read the beam through `:code.which/1`, which answers `:cover_compiled`
  under `mix coveralls`; the story agents ran `mix test` only, and CI's
  test job was red until the checks read the code path instead.
* **A UI CHANGE LANDED WITHOUT ITS BOARD.** QA1 added the row
  „Anbieterwährung“ to the merge preview as a fix; the design critic drew
  its board after the fact (board 08), and that board showed the row's
  reason cut off at the dialog's edge, fixed only in the closing act's
  last round. *Cause:* a closing-act fix was not treated as a UI change.
* **A PLAN PREMISE WAS WRONG.** The plan said the bands read's default
  level was `total`; it was already `category`. S1 kept "answers as
  before" and pinned it; the briefing names the correction.
* **THE FIRST VERSION DESIGN WAS OVER-BUILT.** V1's first cut read git's
  object store in the app (455 lines and a B6 zlib exemption); it was
  sent back for a compile-time `git` subprocess registered narrowly in B2.
* **ONE COVERAGE GAP REMAINS.** A promoted note's headline, event type and
  tone are written over API and MCP and drawn on the chart, but the
  Research tab does not show them; the view is Sprint 29's, board first.

## The regressions, counted apart

The sprint workflow §3 and ADR-0026's amendment of 2026-11-01: the
regressions this sprint introduced are counted apart from the older
findings it passed.

| | S1 | S2 | S3 | Fixed on the branch |
|---|---|---|---|---|
| Introduced, found in the build, integration and CI (N2's link clipped by graphemes; V's beam check under cover; the privacy walk's time and its mid-load exits; `PeriodMemoryTest`'s mid-load exit; a browser test's listener against M2's rule; stale gettext references; a currency refusal printed as the code's term) | 0 | 4 | 3 | 7 |
| Introduced, found by Lane Q's lens (QA1 to QA5) | 0 | 1 | 4 | 5 |
| Introduced, found by the N attack lenses (AT1 to AT8) | 0 | 5 | 3 | 8 |
| Introduced, found by the N lenses (NL1 to NL5 but NL4, ND1 to ND5, AG1 to AG5, board 01's three lines below the cut) | 0 | 8 | 9 | 17 |
| Introduced, found by the money lens and the design critic on Lanes S and V (ML1 to ML3, D1 to D5, and board 08's cut-off reason) | 1 | 2 | 6 | 9 |
| Introduced, found by the UAT persona (the picker's twins; „max 32“; the labeller's 20-character twins; a negative cash day's depth) and the build's polish lines (the release copy after Q1; „Zuordnen“'s generic answer to a race) | 0 | 1 | 5 | 1 |
| Introduced, found by the re-check (ML1's rule drops a band's day back from zero; two ceiling rows below the one before; the privacy check's digit boundary; QA2's gate blind to `apply/3`) | 0 | 0 | 4 | 0 |
| **Introduced, total** | **1** | **21** | **34** | **47 of 56** |
| Older, fixed on the branch (#1438, the privacy value line's amounts as % ticks; the base red; #1424, news tests sharing domains; NL4, U+2028 and U+2029 in a single-line field) | 1 | 2 | 1 | 4 |
| Older, filed (#1439, the theme boot script with storage blocked; #1440, a heap-cap kill report after its capture) | 0 | 2 | 0 | filed |
| Older, recorded as polish lines (the sync note names no security; a `PATCH` outside its wrapper answers 200; the docs' sync button; the Allocation tab's figure without a busy marker) | 0 | 0 | 4 | recorded |

The one introduced S1, ML1, and the older S1, #1438, are fixed on the
branch before promotion. Of the nine introduced findings not fixed, all
S3: five are polish lines (#1356: „max 32“, the labeller's twins; #1365:
the release copy, „Zuordnen“'s answer to a race; #1366: a negative cash
day's depth), and the re-check's four are recorded here: ML1's rule is
stated in the basis and is a second documented difference between a
band's line and the view's; the ceiling history may only fall; the
privacy check's narrowing removes a calendar-dependent false positive;
QA2's gate sees direct and captured calls, not `apply/3`. The privacy
lens's note (the browser walk reads any number before „%“ as a
percentage, so it cannot catch #1438's class; the server backstop does)
is a property of the walk, recorded here. Nothing is withheld to make a
count.

## Exit criteria (D-1)

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | No quote row behind a "Manual" or "None" feed, for a retired security in the full run, or in another currency; every mismatch in `currency_mismatch` | **PASS** | Q1 to Q3 pinned by fake adapters; QA1 to QA5; the UAT's sync asked nothing of the Manual and retired securities and stored no mismatched close |
| 2 | A label can change nothing but a label | **PASS** | N1's closed write refuses every field outside §7 with 422 naming it (AT3 adds the query string); the journal names the token; the UAT's `label` profile lists two tools |
| 3 | A label sorts but never hides what is certain | **PASS** | N2: an issuer story at materiality 0 in the digest; with no labels every read answers |
| 4 | The cursor loses nothing | **PASS**, as amended (D3) | N3's position moved only by a signed cursor; AT5's paging, AT6's labelled-after rule; two consumers never move each other; the UAT read twice |
| 5 | A story becomes knowledge only by a confirmed write | **PASS** | N5 through `notes.append` with its `cluster_id`, NL1's form stores what it showed; N9 draws only notes with a headline |
| 6 | The operator sees what the agent sees | **PASS** | N7 and N8 read through the context functions the API uses, each region pinned against the API; N7's registry read gives the agent the page's feeds and sources; the UAT agreed |
| 7 | The filtered bands add up | **PASS** | S1 on every pinned day, „(direkt)“ included; S3's returns as exact Decimals; the walk's other outputs byte-identical; the UAT on 366 days |
| 8 | No band crosses another (#1426) | **PASS** | S2's sign-changing band at the zero line, pinned; the UAT's negative cash days |
| 9 | The version is never a guess | **PASS** | V1's three kinds pinned with the source faked; V2 makes no request |
| 10 | Every gate holds by registration; regressions counted, none an S1 at promotion | **PASS** | B2 gains one subprocess entry with its self-test; B4 and B5 name their phrases; the schema ceilings rose only by three new tools' bytes; the browser job's limit went from 20 to 35 minutes, named; ML1 and #1438 fixed |

## Carry-forwards for Sprint 29

1. **Every browser walk leaves a page only after its loads land,** through
   one shared helper in `test/browser/`, and a test asserts that each
   walk script uses it. *Why:* the privacy walk and `PeriodMemoryTest`
   failed CI for the same mid-load exit, the second after the first was
   fixed.
2. **A story agent runs its own tests under `mix coveralls`, CI's cover
   mode,** beside `mix test`. *Why:* V1's checks passed `mix test` and
   failed CI's cover run.
3. **A closing-act fix that changes what a screen shows gets its board
   first.** *Why:* QA1's row landed unboarded, and the board drawn after
   it found a defect the fix had shipped.
4. **The plan counts the closing act's fixes by its lenses, not by the
   last two sprints' rate,** and holds the PR under 100 commits with the
   cut line counted after the fixes. *Why:* this sprint's closing act made
   about 55 fixes against 25 to 30 estimated, and the PR stood at 102.
5. **The attack lens before integration — keep.** *Why:* it found five S2s
   in Lane N before any of them reached the sprint branch.
