# Sprint 25 — predictions that score the agent, what a sale missed, dry-run deletes, and the home-screen icon

**Status: ADOPTED by the merge of the Sprint 25 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0055](../../docs/decisions/0055-predictions-scored-for-calibration.md)
(gate B4.2: predictions and the calibration report, idea F1), the story
workflow's new section "What a story's own tests do not cover" (Sprint 24's
carry-forwards 1 to 4), and board 01's pick. A fresh implementation session
builds the sprint on `agent/<provider>/sprint-25` as **one** sprint PR
(D-9). The severity rule of ADR-0026's amendment of 2026-11-01 applies
unchanged.

## What you need to do

1. **Merge, to adopt the plan.** ADR-0055 writes down the shape you
   accepted on 2026-11-05 ("ja f1") with its four conditions; nothing in it
   books or corrects a stored money figure, so every choice inside it is
   decided with its reason and flips by a comment.
2. **Optional, once the sprint's release is out:** on the iPhone, remove
   the Portfolixir shortcut from the home screen and add it again. iOS
   stores the icon when the shortcut is made, so the old „P“ stays until
   then.
3. **Optional, still open from Sprint 24 if not done yet:** the `browser`
   CI job as a required status check on `main` (Settings → Branches). It
   has been green on `main` since the merge of #1388.

**One correction to what you were told in the session of 2026-11-05.**
The session said a research note carries only its write time, so a
publication date for news (I13) would need a new field and an ADR-0044
amendment. **That was wrong.** Every note already has `as_of`, "the
statement's cut-off date, distinct from `inserted_at`" (ADR-0044 §2; the
`notes.append` tool says "an entry written today about last quarter
carries last quarter's date"). For a news item the cut-off date is the date
it became public. So I13's date needs no migration and no amendment, only
the convention written into the tool and the agent's guide (N1, D-5).

**Not asked:** everything else. Each decision below carries its reason and
flips by a comment. The announcement stays yours (Sprint 17's D-1).

**Verification basis:**

- **Sprint 24's merge, as its close-out asked this plan to record:** the
  sprint PR #1388 was merged by your "Rebase and merge" at 06:54 UTC on
  2026-11-05; CI 1881 green on `dc8b102`; release **2026.11.9**. Its
  keywords closed #1378, #1386 and #1387.
- **Since then on `main`:** `7cbbf02` (the idea list: F1 accepted, gate
  B4.2 opened); CI 1885 green on it. `main` is at `7cbbf02`.
- **The open-issue list of 2026-11-05:** 26 open: 5 `agentic` (#1390,
  filed by Sprint 24's M4; #1070, #900, #899, #894), 1 `agentic` and
  `needs-decision` (#1220), 1 `needs-decision` (#1177), 2
  `needs-uat` (#328, #354), 17 trackers (11 polish lists #1355 to #1366
  without #1364; #991; the five area trackers #416 to #420).
- **Read against the code on `7cbbf02`**, each claim this plan rests on:
  - The root layout (`lib/portfolixir_web/layout_view.ex`, lines 32–33)
    links `favicon.svg` and `favicon.ico`, which is a 64 × 64 PNG; there is
    no `apple-touch-icon` and no manifest, and `Plug.Static`'s `only` list
    (`endpoint.ex:62`) is `app.css favicon.ico favicon.svg images
    theme-boot.js`. The page title is „Portfolixir“.
  - `priv/static/images/logo-app-icon.svg` draws the icon on a full-bleed
    square whose colours switch with `prefers-color-scheme`.
  - A research note has `as_of` (a date, required, never after today) and
    `inserted_at`; `author` is derived from the credential;
    `machine_generated` is reserved for a local-model path and refused in
    the body (`SecurityNote`, `notes.append`'s description).
  - `BenchmarkParam` reads `rate:<decimal>` and `security:<id>`, the
    latter only for a security flagged `is_benchmark`;
    `Benchmark.daily_rate_factor/1` is public.
  - `GET /api/v1/securities/:security_id/trades` answers open lots, closed
    round-trips and orphan sells per security; there is no read across
    securities of what happened after a sale.
  - The research log's references are `merge: :refuse` and
    `delete: :restrict` (`Lifecycle.ForeignKeys`), guarded append-only by
    a statement trigger (`portfolixir_security_notes_append_only`).
  - The cascading deletes #894 names are `Classifications.delete_classification/2`,
    `delete_category/2` and `Buckets.delete_view/2`; the hardened deletes of
    `Lifecycle.Delete` (cash account, depot, security) refuse when
    referenced and remove memberships one by one, journaled. The UI
    confirms with a browser `data-confirm` text that names no count.
  - #1390's evidence: Elixir 1.19.7 green in every CI job on the scratch
    PR #1389, with a formatter layout of three files and two `%Result{}`
    matches in `Imports.Applier`.
- **The schema budget in force** (Sprint 24's last row): ceilings 104,310
  / 173,381 / 207,936 bytes for read, book and full. **The contract's head
  is entry 24.**
- **Board 01** was rendered from the shipped `logo-app-icon.svg` with one
  palette pinned (D-6).

## State of play, in five lines

1. **Sprint 24 is on `main`** (release 2026.11.9). Nothing is agent-only
   and overdue.
2. **F1 is accepted** and its decision is written (ADR-0055); nothing of
   it exists in code.
3. **I18 is worked out** for two of its three comparisons; the third (the
   trade the money went into) needs its own decision.
4. **I13 needs no data change** (the correction above), and **I12** is
   Bitcoin-only with its details still owed.
5. **You reported a defect on 2026-11-05:** the iPhone home-screen icon is
   a „P“.

## Why this cut

- **Data that accumulates comes first, screens second.** A prediction
  scores only months after it is made, and a news note's date is fixed
  when it is written. Every week without F1's write path or I13's
  convention is data lost; a view can only show what exists. So F1, I18
  and F21 ship over API and MCP in this sprint, and **their human views
  are Sprint 26's** (D-7), which the two-way coverage rule allows with the
  reason stated.
- **About 47 commits**, one PR, no stack (D-9).
- **One idea went deep this time: I18**, in the session of 2026-11-05. Its
  modes 1 and 2 are planned; mode 3 waits for its decision (D-3).
- **What is left out, and why** (each flips by naming it):
  - **I18 mode 3, the trade the money went into:** a stored link from a
    sale to a buy is new data with a hindsight problem of its own; its ADR
    comes with Sprint 26's planning PR, together with the I18 view it
    shares.
  - **I12 and I13's chart markers:** one board for every marker on the
    security chart (transactions, events, notes, later resolved
    predictions), drawn when the details of I12 are settled with you.
  - **I20, usage hints in the MCP companion:** `triaged`, not worked out;
    its open question is which questions the "where to start" passage
    answers, best taken from real sessions where your agent picked the
    wrong tool.
  - **A polish pass:** Sprint 26 is a screen sprint (D-7), and a polish
    pass belongs with it. W1 fixes the one #1357 line in the file it
    touches.
  - **#899, #900, #1070, #1220, #1177, #328, #354** keep their standing
    reasons (D-10).

## Lanes (one sprint PR, `agent/<provider>/sprint-25`, in this order)

**Lane M, maintenance (first, so every later story is built and checked
on the new Elixir).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | #1390 | Elixir 1.18.6 → 1.19.7 on OTP 27.3.4.19, as #1390's three commits: the pins (every CI job, the PLT key, both images by digest, the install script's default and SHA-256, README and the development guide); the 1.19 formatter's layout of three files; the two `%Result{}` matches in `Imports.Applier`. Closes #1390 | 3 |
| M2 | #1365's line (Sprint 24 close-out) | `securities_sync_rearm_test` saw four provider fetches for two securities once under load: reproduce under parallel load (the suite with `--repeat-until-failure` or four schedulers busy); if the single flight races, it is an S2 in the sync and fixed test-first; if the test races, the test is fixed. Either way the line on #1365 is ticked with the cause | 1–2 |
| M3 | standing rule | the version report `version-report-2026-11-…-sprint25.md`: Elixir 1.19.7 as its first row; Hex, npm, OTP, PostgreSQL, BMAD core and the external modules as every sprint, each bump its own commit | 2 |

**Lane W, the home-screen icon (the owner's report).**

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| W1 | the owner, 2026-11-05 | `priv/static/apple-touch-icon.png`, 180 × 180, opaque, rendered from `logo-app-icon.svg` with the light palette pinned (board 01, A), and the script that renders it; `<link rel="apple-touch-icon" href="/apple-touch-icon.png">` in the root layout's head; the file in `Plug.Static`'s `only`. A test, seen failing first: the root layout links it; `GET /apple-touch-icon.png` answers 200 `image/png` **with the UI password set and no session**; the PNG's header says 180 × 180 and colour type 2 (no alpha). The product documentation's phone section says to re-add the shortcut after an upgrade. #1357's line on `layout_view.ex`'s misplaced CountUp comment is fixed in the same file and ticked | 01, A (D-6) | 2 |

**Lane S, what a sale missed (I18, modes 1 and 2; ladder (c)).**

| Story | Source | What it does | Decision | Commits |
|---|---|---|---|---|
| S1 | I18; ADR-0055 §3 | **one function for a window's price return in EUR** from stored closes and EUR-hub rates, with the staleness bound of 7 days and the named reasons for no answer; used by S2 here and by F1's resolution, so the two cannot drift. Pinned with exact `Decimal`s: same currency, a USD security, a stale close, a missing rate | D-3 | 1 |
| S2 | I18 | `GET /api/v1/sales/hindsight` and `portfolixir.sales.hindsight` (read-only, every profile): one row per sale booking, filtered by `portfolio_id`, `security_id` and a sale-date range, with the optional `benchmark=` of ADR-0046; per row four spans (1, 3 and 12 months after the sale, and to the latest close), each with the security's return, the benchmark's and the difference, or `pending` / `incomplete` with its reason; `computation_basis` per D-3; contract entry 25; the API reference and `docs/integration` | D-3 | 3 |

**Lane F, predictions and calibration (F1, ADR-0055; its write path gets
its own verification pass: a record that must never change).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| F1 | ADR-0055 §§1–2 | the `predictions` table, its schema and context: the fields of §1 with their bounds, `made_at` from the server, `author` and `actor` from the credential, `model` required for an agent; the append-only statement trigger, pinned by a test that tries `UPDATE` and `DELETE` and is refused; the two references in `Lifecycle.ForeignKeys` (`merge: :refuse`, `delete: :restrict`) with the 409 naming the predictions; journaled | 3 |
| F2 | ADR-0055 §3 | resolution at read through S1's function: `open`, `resolved` (hit or miss) and `unresolved` with its four reasons; the start close strictly before the day made; `rate:` through `Benchmark.daily_rate_factor/1`; `excess = 0` a miss. Pinned with exact `Decimal`s for each case, at a moving FX rate too | 2 |
| F3 | ADR-0055 §4 | the calibration report: Brier, its standard error, the 0.25 reference, sharpness, the hit rate with its standard error, the five bands with `too_few` under 20, the groups by author and model, `computation_basis`. Pinned on a fixture whose figures are computed by hand in the test's comment | 2 |
| F4 | ADR-0055 §5 | the four API routes and the four MCP tools (`create` in `book` and `full`; the reads in every profile), each description saying a prediction is permanent; the schema ceilings raised by the new tools' own bytes; contract entry 25; the API reference, `docs/llms.txt` and `docs/integration` | 3 |
| F5 | ADR-0055 §5; F32 | the MCP prompt `position_review`: reads the dossier, the open theses and their invalidation conditions and the upcoming events, then asks for predictions (direction, probability, date, benchmark) or none, with the no-advice framing in its text; listed beside `first_setup` and `import_converter` | 1 |

**Lane N, the news convention (I13, D-5).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| N1 | I13 | `notes.append`'s description and `docs/integration` say how an outside aggregator records a news item: `kind` `evidence`, `as_of` the date the item became public, `source_url` the article, `source_quality` as judged; a summary and a link, never the article (no raw news archive); a direction read from the item is recorded as a prediction (F4) with `note_id` pointing at the note. The schema ceilings rise by the description's own bytes | 1 |

**Lane X, dry-run deletes (F21, #894; risk tier: a delete path whose dry
run must write nothing, its own commit group and verification pass).**

| Story | Source | What it does | Decision | Commits |
|---|---|---|---|---|
| X1 | #894 | `dry_run=true` on `DELETE` of a classification, a category and a view, and `dry_run: true` on their three MCP delete tools: the delete runs in a transaction that **always rolls back**, and the answer lists what it would have removed (per kind, the count and the ids) or the refusal it would have answered. Pinned: a dry run and the real delete that follows name the same rows; database and journal are unchanged after a dry run, counted before and after; the tool descriptions name the parameter. Contract entry 25 | D-4 | 3 |

**Closing act** (D-8): the correctness hunter; the money and idempotency
lens on S1, F2, F3 and X1 (the window return, the scores, the rollback);
the agent's lens on S2, F4, F5 and N1 (a description says what the tool
does, a prediction recorded through the prompt resolves); the design critic
on W1 against board 01; the UAT persona adds the icon on an emulated
iPhone home screen (the PNG at 180 px) and records, resolves (with a
back-dated fixture through the test seam, never the API) and scores a
prediction. About 7 commits.

**Close-out** (the PR's last commits): `sprint-status.yaml`, `epics.md`'s
FR Coverage Map (FR-46, FR-47, FR-50) and a dated reconciliation, the idea
list (F1 and I18's modes 1 and 2 `built`, I13's convention `built`), the
retrospective, the version report. About 5 commits.

**Estimate:** M 6–7, W 2, S 4, F 11, N 1, X 3, closing act 7, close-out 5:
**about 40**, with room for one review round under ADR-0026's 90.

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **ADR-0055 is built as signed:** a prediction cannot be changed or
   deleted (the trigger refuses both, pinned); resolution and the report
   are pinned with exact `Decimal`s on every case §3 and §4 name; every
   ask of §9 is answered in code or deferred with its issue.
2. **I18 modes 1 and 2 answer for every sale:** on the seed, each span's
   three figures equal a hand computation in the test, for no benchmark, a
   rate and a security; a span not yet reached reads `pending`.
3. **A dry run equals its delete** for the three cascading deletes, row
   for row, and leaves database and journal unchanged.
4. **The icon:** the root layout links a 180 × 180 opaque PNG that is
   served without a session.
5. **Elixir 1.19.7 is on `main`** with every CI job green; #1390 closes by
   keyword.
6. **The sync re-arm flake has a named cause**, fixed in the sync or in
   the test.
7. **The regressions this sprint introduced are counted** apart from the
   older findings, and none is an S1 at promotion.

**No criterion counts open issues.** Reported, not judged: 26 open today;
24 after #894's and #1390's keywords.

**To flip by comment:** name a criterion to drop or add.

### D-2: F1 is ADR-0055, signed by this merge (recommended)

The ADR says it in full. The choices it makes that you did not make
yourself, each flippable by a comment naming its section:

- **Probability from 0.50 to 0.99** (§1): one spelling per belief.
- **No withdrawal of any kind** (§2): a withdraw path is a path that
  removes the losing calls.
- **Measured from the last close before the day made** (§3): no call is
  measured from a close it could have seen coming.
- **In EUR, price only** (§3): what you hold, and what the closes carry.
- **Bands from 20 resolved predictions** (§4): ten over five bands is two
  per band.
- **Per-source calibration deferred** (§9): a source is not an author,
  and the sample cannot carry the split yet.

### D-3: I18 modes 1 and 2, the shape (recommended)

- **The comparison is optional and chosen per request** with ADR-0046's
  `benchmark=` (`rate:<decimal>` or `security:<id>`), so modes 1 and 2
  need no new decision. Without it, the read answers the security's own
  move only.
- **A security benchmark must be flagged `is_benchmark`**, as in the
  benchmark comparison, because `BenchmarkParam` is reused unchanged. A
  flag is one click on the security's page, and a held ETF may carry it.
  **To flip:** "I18 any security", which accepts any catalogue security
  with quotes in this read only.
- **One row per sale booking**, not per FIFO lot: the decision was the
  sale. Orphan sells count.
- **Closes on both ends:** the start is the security's close on the sale
  day (or the last before it, within 7 days), so the security and the
  benchmark are measured alike; the booked sale price is shown beside it.
- **Spans:** 1, 3 and 12 calendar months after the sale (`Date.shift/2`),
  and to the latest close; a span whose end is after today is `pending`.
- **In EUR, price only** (S1's function): distributions after a sale are
  not booked, so a dividend payer's miss is understated, and the basis
  says so.
- **No verdict.** No field says "too early" or "right"; the figures are
  the answer (no advice).
- **Mode 3** (the trade the money went into, with its booked fees and
  taxes as a cost line, compared before latent tax) is worked out in the
  idea list and gets its ADR with Sprint 26's planning PR: a stored link
  chosen after the outcome shows needs the time it was set, and the
  latent tax of the kept position would be F7's projection, which stays
  gated.

### D-4: F21 runs the real delete and rolls it back (recommended)

**Why not a separate count query:** a preview computed beside the delete
can drift from it, and the first drift is a preview that says less than
the delete does. Running the delete itself in a transaction that always
rolls back answers with exactly what the delete would do, refusals
included; ADR-0050's probe reads its merge dry run the same way (amended
2026-10-09). Only the three cascading deletes #894 names take it; the
hardened deletes of `Lifecycle.Delete` refuse instead of cascading, and
their 409 already names what blocks them. **To flip:** "F21 all deletes",
which adds the parameter to the cash-account, depot and security deletes.

### D-5: I13 is a convention, not a field (recommended)

`as_of` already is the date a statement stands for, so a news item's
publication date is its `as_of` (the correction at the top). **A time of
day is not added:** closes are daily (ADR-0005), and a marker on the
publication date sits next to the close of that day and the next; whether
an item came after the close matters only to a computed correlation, which
is a metric of its own and not asked for. **To flip:** "I13 time", which
adds a nullable `published_at` to the log and needs an ADR-0044 amendment
in the next planning PR.

### D-6: board 01 and its pick (recommended; silence adopts it)

Under `_bmad-output/planning-artifacts/design-language/mockups/ux-design-2026-11-05-sprint25/`,
rendered from the shipped icon with one palette pinned; the README lists
what W1 builds.

- **Board 01, the home-screen icon:** today's letter tile; **A**, the
  light palette (recommended: it reads on both wallpapers and matches the
  favicon in light mode); B, the dark palette, whose tile edge disappears
  on a dark wallpaper.

**What needs no board, and why:** every other story of this sprint changes
no rendered page. S2, F4, F5, N1 and X1 are API, MCP and documentation;
their screens are Sprint 26's and are boarded on its planning PR (D-7).

### D-7: what Sprint 26 owes (standing; the close-out checks it)

The two-way coverage rule gives this sprint's agent-only capabilities until
the end of Sprint 26 for their human view. Sprint 26's planning PR boards:

- **F1:** the security page lists a security's predictions with status and
  outcome; the calibration report's block (where it lives is the board's
  question);
- **I18:** the sale rows with their spans, and mode 3's ADR;
- **F21:** the delete confirmations name what a delete removes, from the
  dry run;
- **I12 and I13:** the marker board for the security chart, once I12's
  details are settled with you.

That makes Sprint 26 a screen sprint, and a polish pass rides with it.

### D-8: the closing act and the build (standing, with Sprint 24's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's new section ("What a story's own tests
do not cover", signed by this merge) applies to every story; Sprint 23's
four build rules stand (commit before a long gate run; integrations run
their gates in the foreground; a story's scratch files live in its
worktree; a remedy is tested by following it literally). For this sprint
in particular:

1. **F1's permanence is attacked**, not only asserted: an `UPDATE`, a
   `DELETE`, a caller-supplied `made_at`, a probability of `0.49` and of
   `1.00`, an agent write without `model`; each refused.
2. **X1's rollback is checked by counting** every table the delete
   touches and the journal before and after a dry run.
3. **The window return is checked at a moving rate** (a USD security
   whose rate changes between the two closes), as every money identity is.

Every catalogue integration uses Sprint 23's E2 tool; one "Closes #n" line
per issue.

### D-9: one PR, no stack (recommended)

About 40 commits, so one PR merged by your "Rebase and merge" button. The
build order is the plan's lane order (M, W, S, F, N, X), so history goes
forward only and S1's function exists before F2 uses it. A PR nearing 85
commits is cut at its last finished lane into a stacked PR, named in the
briefing.

### D-10: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger (a switcher's export with those two types). #328 and #354 wait for
your check on real data. The polish lists stay open while they have lines;
a story that touches a screen fixes its lines.

## Registry bookkeeping after the merge (the planning session's last step)

- File F1's issue (FR-46 and FR-47 as ADR-0055 amends them, pointing at
  the ADR) under #419, and the deferred ask's issue (per-source
  calibration, ADR-0055 §9) under #419; file I18's issue (FR-50, modes 1
  and 2, pointing at D-3) under #418. #894 and #1390 exist.
- No closures by hand; no relabels.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 Elixir 1.19.7 (#1390), M2 the re-arm flake, M3 version
      report
- [ ] Lane W: W1 the home-screen icon (and #1357's comment line)
- [ ] Lane S: S1 the window return, S2 the hindsight read
- [ ] Lane F: F1 the table and its guard, F2 resolution, F3 the report,
      F4 API and MCP, F5 the prompt
- [ ] Lane N: N1 the news convention
- [ ] Lane X: X1 dry-run deletes
- [ ] Closing act, fixes, re-check
- [ ] Close-out, retrospective, briefing, promotion
