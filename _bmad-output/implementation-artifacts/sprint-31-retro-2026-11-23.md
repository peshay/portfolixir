# Sprint 31 Retrospective — the first dashboard of widgets, one period above it, a price of 0 read as none, four S2s (2026-11-23)

ADR-0026 step 5 for Sprint 31, written by the implementation session as the
last commits of the sprint's second PR (sprint workflow §5). The plan,
`sprint-plan-2026-11-21-sprint31.md`, was adopted by the merge of its
planning PR, which signed ADR-0062 (FR-60, idea I56), ADR-0022's and
ADR-0051's amendments of 2026-11-21, I46's identity sentence, the I56 idea
boards 01 to 06 and planning board 01 of `ux-design-2026-11-21-sprint31`.
The close-out entry with every criterion and count is in
`sprint-status.yaml`; this file keeps what the sprint teaches. Commits are
named by their subjects, because the second PR's history was rebased and
its hashes changed.

## What shipped

Two stacked PRs, cut at the boundary the plan's D-9 prepared (after Lane
P), built by one implementation session (Claude Code on the web) that ran
story, lens and fix agents in worktrees from `scripts/worktree.sh`:

| PR | Branch | Lanes | Commits | Closes | State at this record |
|---|---|---|---|---|---|
| #1483 | `claude/confident-goodall-jaqa08` | M, K, Z, P, and the older Monday test fix | 24 on `main`'s `01542f7` | #1470, #1473, #1474, #1475 | draft, not merged |
| #1486 | `claude/confident-goodall-jaqa08-pr2` (based on #1483) | D (D1 to D8), the closing act's four fix batches, the UAT persona, this close-out | 91 before the close-out, 95 with it | #1480 (FR-60's first slice) | draft, not merged |

**Why stacked:** the sprint passed GitHub's 100-commit "Rebase and merge"
limit (115 commits before the close-out, against the plan's estimate of
about 88). Lane D alone took 32 commits, the closing act's fix batches 1 to
3 took 47 and the UAT with fix batch 4 took 12, against D-9's estimate of
about 35 for all the closing act's fixes. The cut is the one D-9 prepared,
so the risk-tier lanes (K and Z) merge on their own PR first. They merge in
order, #1483 then #1486, in one sitting.

- **Lane M:** M1, the version report `version-report-2026-11-21-sprint31.md`:
  phoenix 1.8.17 (two HIGH advisories turned CI's advisories job red
  mid-sprint), bandit 1.15.0 (#1476, its Dependabot CI run was the declared
  trigger), Playwright 1.65.1 (#1477, headless shell revision 1255); the
  rest declined with reasons. M2, the walks launch the pinned release's
  `chromium-headless-shell` by default and say which browser they launched
  (`AGENTS.md`'s fact line corrected). M3 (#1475), every test database is
  created with libc `C.UTF-8` from `template0`, CI's services no longer
  pre-create it, and `test_database_collation_test.exs` asserts it. M4, a
  worktree links `deps` only when the lock files match, else copies them,
  and `worktree.sh own` with the `deps.*` aliases replaces a link before a
  fetch. M5 (#1474), the privacy walk requests each address once and
  patches `/portfolio`'s stack views into an open page: 22.7 s of CPU and
  18.9k queries down to 9.3 s and 6.2k; 20 of 20 loaded runs green
  (15.8 to 44.1 s), the 60 s bound unchanged.
- **Lane K, one lock order** (#1470; risk tier stored data): reproduced in
  three interleavings (`40P01` each); a recluster, a retention and a lock
  take the scope's security or category FOR KEY SHARE before the advisory
  lock (lock table row 28). The attack lens found two older deadlocks of a
  security's delete; the delete now takes its own security and the
  securities its items fall to in one id-ordered pass, re-reads, and
  retries at most three times (row 29). Each race test red first, 50 of 50
  loaded runs green.
- **Lane Z, a close of 0 or below is no price** (#1473; risk tier money
  math; ADR-0051's amendment of 2026-11-21): the walk skips such a close
  as it skips a missing one; every analytic derived from the walk moved
  one computation version (performance analysis 4 to 5, contribution 6 to
  7, bands 1 to 2, benchmark comparison 4 to 5, portfolio metrics 2 to 3,
  policy findings 2 to 3); every walk basis says "(a stored close of 0 or
  below is not a price)"; the snapshot comparison and the benchmark seed
  skip it too. The attack lens carried the rule into the live valuation,
  the change tiles and sale hindsight's span, and kept a booked price of 0
  marked `no_price`. ADR-0051 gained a dated "Built (Sprint 31, Lane Z)"
  note.
- **Lane P, faster charts, step 2** (I34): P1, the warm-up also warms the
  1-year bands and contribution table for everything and each view (low
  priority, cancellable, stopping at half the memo's budget, off in tests;
  ADR-0039 amended). P2, `Bands.cached_for_view/2`, so a memo hit draws
  Wealth's chart without the skeleton.
- **Lane D, every function a widget, the first slice** (FR-60, #1480;
  ADR-0062): D1, the context `Portfolixir.Dashboards` (the registry of
  eleven kinds, the template „Überblick“, the table, every §2 refusal,
  journaled writes, `lock_version` with 409, the 50-dashboard limit under
  an advisory count lock at row 30, no atom from a sent key), with its
  attack lens before integration. D2, `/api/v1/widgets`, the dashboards'
  routes and `portfolixir.dashboards.list`, `.get`, `.put` and `.delete`
  (the schema budget raised by Sprint 24 D-2's registered procedure for new
  tools). D3, the dashboard page at `/` with the Overview's seven cards as
  widgets and the seven lines of #1358 fixed in them (ADR-0061 amended:
  „Tag“'s `P` within 7 days, twins in one half). D4, the four widgets the
  owner named. D5, one period above every dashboard. D6, the edit mode by
  pointer and keyboard, one save one journal entry. D7, the menu
  (Dashboards, Entdecken, Pflege), „Alle Widgets“, „Neues Dashboard“ and the
  compact tab bar. D8, `DESIGN.md` and `EXPERIENCE.md`, and the width walks
  at 375, 393, 440, 760 × 580, 834, 1200 and 844 × 390.
- **The closing act:** the lenses for correctness, money, security, the
  agent, edge cases and order, accessibility and the design critic; fix
  batch 1 (the page), 2 (API, MCP and bases), 3 (board 02, accessibility
  and design, with three S forms within their budget); the re-check; the
  UAT persona; fix batch 4 (the UAT's findings, board 02 ⑩ first).

## What went well

* **THE ATTACK LENS BEFORE INTEGRATION FOUND THE WORST FINDINGS AGAIN.**
  Z1's lens found the sprint's only confirmed S1 before any screen showed it:
  the live valuation still priced a latest close of 0 (an older read the
  amendment's "one rule for every price read" reached; the walk read 10
  where the Overview read 0). K1's lens found two older deadlocks K1's own
  races never tried; D1's lens found a stale `view_id` that blocked every
  save. Each was found by a session that did not write the code (Sprint
  30's carry-forward 10).
* **EVERY PINNED FIGURE WAS RECOMPUTED, NOT TRUSTED.** Lane Z's
  implementer, its attack lens and the money lens recomputed every expected
  figure in Python's `decimal` at 34 digits. When the pinned payload
  digests had to move, the build proved over all 115 pinned reads that
  only the basis sentence had changed before it re-took them, and said so
  in ADR-0051's note.
* **THREE S2s FIXED AT THEIR CAUSE, NO BOUND MOVED.** #1474's walk was
  measured before it was changed and its 60 s bound stands; #1470
  reproduced red in three interleavings and ran 50 of 50 loaded runs
  green; #1475's collation is one and asserted. The trades card's cost
  test, which timed out in CI under the page's new read cap, was narrowed
  to the widget it measures, not given more time.
* **I34'S STEP 2 SHOWS.** On a warm period switch the skeleton went from
  100 of 100 to 0 of 100, the browser median from 204 to 116 ms
  (Kategorien € 1y 172 to 102 ms), and the order lens's O2 kept a
  dashboard write from discarding the warmed memo.
* **THE GATES CAME OUT STRICTER THAN THEY WENT IN.** The width walk's
  KNOWN baseline and fix batch 3's name exemption were both removed; the
  walk excepts nothing and measures each template widget against its size's
  budget, in Inter and in DejaVu Sans. The full suite ran green after
  every fix batch (7,319, 7,331, 7,339 and 7,342 tests), the full browser
  suite 46 of 46 on the final head.
* **THE RE-CHECK PROVED THE FIXES BY MUTATION.** All nine closing-act S2
  fixes and seven sampled S3 fixes went red with their key line reverted
  and green restored; the Monday movers fix red and green on a Monday and,
  by a time-zone shift, on a Tuesday. It found nothing a fix broke.
* **THE UAT FOUND EVERY FIGURE EQUAL TO THE API.** At all eight periods
  and with a pin, every widget's figure matched its route; reading `/` at
  every period, width and theme stored nothing; Lane Z's legacy 0, placed
  where it hurts most, was skipped by every read but one older chart.
* **THE WORKTREE HELPER HELD.** M4's copy on a lock mismatch kept every
  dependency bump of the sprint (phoenix, bandit) out of the main checkout
  and the other lanes.
* **THE CUT WAS PREPARED, SO STACKING COST NOTHING.** D-9 named the
  boundary; the risk-tier lanes sit on their own PR and #1486 rebased onto
  it with its fixups folded and its tree byte-identical to the tested tip
  but for gettext references.

## What did not go well

* **THE ORCHESTRATOR READ A GATE THROUGH A PIPE — SPRINT 19'S LESSON,
  REPEATED.** The session read `mix gettext.extract --check-up-to-date`
  through a pipe, so its exit status was the pipe's, and a stale
  `default.pot` passed locally and turned CI's quality job red. The brief
  to every agent said "read each gate's exit status directly"; the
  orchestrator did not follow its own brief.
* **AN AGENT'S REPORT CLAIMED TESTS IT HAD NOT RUN.** D4 reported its
  dashboard tests green while `dashboard_test.exs`, which pinned the
  Overview's old card, had eight failures: it ran other files. CI caught
  it. A report is evidence only for the files it ran.
* **A WALK SHIPPED WITH A BASELINE, AND A FIX WITH AN EXEMPTION.** D8's
  first width walk listed its three real breaks in a `KNOWN` array and
  passed; fix batch 3's first height budget exempted „Gesamtwert“,
  „Datenqualität“ and „Fällig“ by name. Both are the shape the gates
  forbid; both were removed and their defects fixed, but by the
  orchestrator after the fact, not by the agent that wrote them.
* **TWO LANES TOOK THE SAME LOCK-TABLE ROW.** K and D1, built in parallel,
  both registered row 28; the integration renumbered the dashboards' row to
  30, and D7's and the order lens's notes found comments still citing 28.
* **THE ACCOUNT'S WEEKLY USAGE LIMIT STOPPED A FIX AGENT FOR ABOUT 38
  HOURS** (from about 04:00 UTC on 2026-11-22 to 18:00 UTC on
  2026-11-23), mid-gates. Its commits were complete; the orchestrator ran
  the gates afterwards. Nothing was lost, but the sprint's end moved by
  more than a day and a half, and no plan had counted the limit as a
  constraint.
* **FLAKY TESTS: TWO OLDER, ONE NEW.** The Tops und Flops test failed
  every Monday (the share's last close before the week's start), and the
  security merge test read printable bucket ids in creation order; both
  older and fixed on the branch. D1's attack test counted queries through
  a global telemetry handler in an async module and caught a neighbour's
  INSERT once in CI; fixed to count its own process only.
* **BOARDS DRAWN AFTER THE CODE, THREE TIMES.** Fix batch 1's two visible
  changes and one frame of fix batch 4 (the crash widget's compact line,
  whose first version overflowed at 375 px) were drawn on board 02 after
  their code, where the plan asks the frame first.
* **TWO AGENTS EDITED ONE FILE AT ONCE.** D4 and D5 both changed
  `dashboard_live.ex`; D4 rebased onto D5 itself. It worked, at the cost
  of a second review of the merged file.
* **THE CLOSING ACT WAS UNDERESTIMATED BY HALF.** D-9 counted about 35
  closing-act fixes; the four batches took 58 commits (47 and 11), which
  is what pushed the sprint past 100.
* **ONE DESIGN RULE WAS ADJUSTED BY A FIX.** Fix batch 4 relaxed DS3's
  "the ⓘ on the title's line" to "directly under its title" where DejaVu
  Sans cannot fit both: a rule of this sprint, changed with its reason in
  the commit and in the walk, not a gate weakened.

## The regressions, counted apart

The sprint workflow §3 and ADR-0026's amendment of 2026-11-01: the
regressions this sprint introduced are counted apart from the older
findings it passed. **How counted:** from the closing-act ledger, the
orchestrator's summary, the UAT's README and the fix commits' bodies. Each
finding is counted once, at the source that first recorded it; a later
source that found it again is named in its row and not counted twice
(MO1 is C1; A1 is D8b's F2; A2 is C3; O4 is D7's lock-table note; DS1 is
D8's grid-row note; DS2's blank band is D5's note; the order lens's older
finding is MO6). A finding with two parts is one finding. A flaky test
counts S2, as this sprint's own commits class them. C3 (get → put
refused `title` and `source`) is counted S3, as the ledger and the
re-check class it; its two fix commits call it S2, and with that reading
the introduced S2s are 16, not 15.

| Source | S1 | S2 | S3 | Fixed on the branch |
|---|---|---|---|---|
| The build, the integration and the fix batches (the lock-table row taken by K and D1; D8's KNOWN baseline; its three breaks: „Achtung“ at 11 px, the drift table past its frame in DejaVu Sans, „Gesamtwert“'s period rule; D8b's F1 „Gesamtwert“ M's head against its sub-line, F2 the registry's source without the performance routes, F3 wide table heads at 11 px; P's new view bumping no basis, a hit leaving a queued older read; D2's companion cutting a long 409 body; D7's lock-table writer list and "row 28" comments; D5's „six chips“ comment, the blank band at 1200 px; D8's grid rows growing past the board's 112 px; fix batch 3's name exemption; fix batch 4's crash line past 375 px; `gettext("Cash")` in an async task without the locale; a queued dashboard read's older period running before the newest; an instance with no booking showing the wizard, so the edit mode is empty) | 0 | 0 | 20 | 12 |
| CI (a stale `default.pot`, read locally through a pipe; D4's eight stale expectations in `dashboard_test.exs`; D1's attack test counting a neighbour's query, flaky; the trades card's cost test timing out under the read cap, flaky) | 0 | 2 | 2 | 4 |
| K1's attack lens (nothing introduced; its two finds are older, below) | 0 | 0 | 0 | 0 |
| Z1's attack lens (a booked price of 0 losing its `no_price` mark) | 0 | 1 | 0 | 1 |
| D1's attack lens (a stale `view_id` blocking every save; a delete answering the row read before its lock; a `view_id` on a kind without views; a position past the maximum; the 41-item refusal's index) | 0 | 1 | 4 | 5 |
| The correctness lens (C1 the short periods a day early, „folgt · 1W“ unlabelled; C2's remainder, the total's link carrying `period=ytd`; C3 get → put; C4 a retired kind blocking every save; C5 Back keeping 3M) | 0 | 1 | 4 | 5 |
| The money lens (MO2 „Allokation und Drift“'s raw target beside a renormalised drift; MO4 three off-target rules; MO5 the line's axis extremes off its thinned path) | 0 | 2 | 1 | 3 |
| The security lens (SE1 unbounded parallel reads from one layout; SE2 the item kind uncapped in the companion) | 0 | 1 | 1 | 2 |
| The agent's lens (A3 Lane Z's rule missing from the snapshot comparison's basis and contract v31; A4 `list`'s description of templates and `data.widgets`) | 0 | 0 | 2 | 2 |
| The edge-case and order lens (O1 „Weiter bearbeiten“ reverting the agent's change; O2 every dashboard write bumping the global basis; O3 a period or scope pick dropping an open edit) | 0 | 2 | 1 | 3 |
| The accessibility lens (Y1 compact focus lost after ↑, ↓, ×; Y3 focus to `body` after the edit's buttons; Y4 the period strip not scrolling to a focused chip; Y5 compact targets under 44 px; four smaller: ⓘ and ⋯ without the widget's name, a repeated refusal unsaid, the sidebar's group titles plain text, the handle's label against its announcement) | 0 | 1 | 7 | 8 |
| The design critic (DS4 the edit mode at 1200 px clipping content; DS2 „Gesamtwert“ S as a nested card; DS3 the wide head; DS5 crash figures breaking and the cycle widget's inner heading; „Alle Widgets“' search at 0 px; the rail's labels edge to edge; the catalogue's sizes as bare letters; „Leer beginnen“ not opening the edit) | 0 | 1 | 7 | 8 |
| The UAT persona (no sign-out in the compact and short-wide classes; „Mehr“ cut at 844 × 390; Crashes' compact „Depot −3,1 %“ mislabelled; the 1T empty plot; „1W → Woche“ one day on a Monday; Tops und Flops M dropping its fifth row unsaid; „bearbeiten“ and the drawer over the edit's buttons; titles cut under their ⓘ; the short-wide subtitle and the rail's hyphens) | 0 | 3 | 6 | 8 |
| **Introduced, total** | **0** | **15** | **55** | **61 of 70** |
| Older, fixed on the branch (the live valuation pricing a latest close of 0, from Z1's lens; a security's delete against a merge and two deletes of one item's candidates, from K1's lens; the change tiles and price change reading a 0, sale hindsight's span ending on a 0, from Z1's lens; Y2, the closed sidebar's 13 off-screen tab stops, made worse by D7; the sidebar's shadow bleed, from the design critic; the Monday movers test and the printable bucket ids, from CI; „eins ohne Anlageklasse“, from the UAT) | 1 | 5 | 4 | 10 |
| Older, filed (#1485: a plan with targets only on subcategories is renormalised by the top-level sum alone, an S1 candidate with `needs-decision`, from the money lens) | 1 | 0 | 0 | filed |
| Older, recorded (M5's three: the walk's per-security quote queries, the bands walked twice on a period and level patch, a sort or scale change walking again; MO6 `QuoteAdjustment.basis_check` and the plausibility check against a legacy 0, on #1365; Performance's own 1y baseline one day before the movers' 1y; the security's price chart drawing a stored 0, from the UAT, on #1365) | 0 | 0 | 6 | recorded |

**No introduced S1.** The one S1 the sprint met is older and fixed: the
live valuation priced a latest close of 0 while the walk, after Lane Z,
did not. It is counted older because the valuation read the newest stored
row before the sprint began; Lane Z's change is what made the two reads
disagree, which is how the lens saw it. #1485, an older S1 candidate, is
filed with its recommended answer and stays open at promotion: it is a
money semantics question (ADR-0040 §2), the owner's to answer.

**The nine introduced findings not fixed** are all S3: F3 (wide table heads
at 11 px, decided to stay and written into `DESIGN.md`); P's new view
bumping no basis and its hit leaving a queued older read; D2's companion
cutting a long error body; D5's „six chips“ comment in `app.css`; the
async `gettext("Cash")` without the locale; a queued dashboard read's older
period; the wizard leaving the edit mode empty; the UAT's „1W → Woche“ on a
Monday, which ADR-0062 §5's translation rule gives by design.

**Not counted:** K1's suspected late scope lock in `assign_item`, which
needs a third writer and did not reproduce with two (recorded as a
carry-forward, not as a defect); Wertentwicklung's „—“ in every row at Max,
checked by the UAT against the API (every start value is 0, `change:
null`); the UAT's "as designed" items; process findings (the pipe, D4's
report, the parallel edits, the usage limit, a CI job's 403 fetching a
NIF from github.com, re-run once). Nothing is withheld to make a count.

## Exit criteria (D-1)

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | Every widget draws its source's figures, no figure of its own, no verdict word | **PASS** | "test(dashboards): every widget figure against its source route" and D4's tests per kind; the money lens's MO2, MO4 and MO5 fixed; `metrics_carry_no_verdict_test.exs` walks the catalogue; the UAT: every figure equal to the API at 1T to Max and with a pin |
| 2 | A dashboard is stored, validated and journaled; 409 with the stored layout; a read never writes; the template never stored; API and MCP answer what the screen shows | **PASS** | D1, every §2 refusal red first; D1's attack lens (eight replaces on one `lock_version`, one wins; 51 creates, 50 stored); C3's get → put fixed; the UAT: `/` read at every period, width and theme left the table empty, one journal entry per save, the stale save both ways |
| 3 | One period above every dashboard, remembered, kept, in the address; a pin marked; a translated or absent period labelled | **PASS** | D5's tests; C1 (the short periods) and C5 (Back) fixed; the UAT: `?period=` carried, the pin kept at every dashboard period |
| 4 | The width picks the layout, never the device; the walks fail type under 12 pt at three phone widths; the type checked on a real phone, or said | **PASS, its real-phone check OPEN** | `no_user_agent_read_test.exs`; the width walks at 375, 393 and 440 px, medium, wide and 844 × 390, in Inter and DejaVu Sans, nothing excepted; the UAT: no text under 12 px; **no real phone was at hand in this environment**, as the UAT's README says, so the type on a handset stays open (carry-forward 1) |
| 5 | The edit mode by pointer and keyboard; one save one journal entry | **PASS** | D6's tests; Y1, Y3, O1, O3 and DS4 fixed; the UAT: arrows, drag, size, ×, Delete, the drawer, one entry for three changes |
| 6 | A close of 0 or below is no price in the walk; the cases in Python's `decimal`; the digests stay; every analytic moves its version | **PASS, one clause deviated** | Z1 and its attack lens, every figure at 34 digits; six analytics moved a version; the digests did **not** stay: the basis sentence moved them, and the build proved over 115 reads that nothing else did before re-taking them (ADR-0051's "Built" note) |
| 7 | The four S2s closed at their cause | **PASS** | #1470 red in three interleavings, 50 of 50 loaded runs green; #1475 one collation and its invariant; #1474 20 of 20 loaded runs green, the 60 s bound unchanged; the walks in CI's headless shell (M2) |
| 8 | I34's step 2: the warm default period, a hit without the skeleton, the medians recorded | **PASS** | P1's warm-up tests; P2: skeleton 100 of 100 → 0 of 100, warm switch 204 → 116 ms in the browser, recorded in its commit |
| 9 | Every gate by registration; regressions counted, none an S1 at promotion | **PASS at this record** | above: no introduced S1, the older S1 fixed, #1485 filed; the schema budget raised only by Sprint 24 D-2's procedure for the new tools, then lowered to the measured figure; the KNOWN baseline and the name exemption removed; no time bound moved |

## UAT persona

The operator's walk on the review seed, recorded in
`uat-sprint31-2026-11-23/` (37 screenshots and a README), in CI's headless
shell at 1200 × 900, 834 × 1112, 760 × 580, 440 × 956, 393 × 852, 375 × 667
and 844 × 390, German first, English spot-checked, light and dark, with one
legacy close of 0 placed for Lane Z on the day before the walk's Monday.
A fresh instance showed the template read-only; „Anpassen“ stored one
copy; the edit mode, the stale save both ways, „Alle Widgets“, „Neues
Dashboard“ and an agent's own dashboard over the API all behaved as
ADR-0062 says. Every widget figure matched its route at all eight periods
and with a pin; every Lane Z read skipped the 0 except the security's own
price chart (older).

It found three S2 and eight S3, no S1. The three S2 (no sign-out on a
phone, „Mehr“ cut at 844 × 390, the crash widget's compact label) and six
S3 were fixed in fix batch 4, after board 02 ⑩; „1W → Woche“ on a Monday is
by design; the price chart's 0 is a line on #1365. On the type: rows are
16 px, titles 17, the total 28 at 393 px, and what reads large is the
density (the template is 6.6 screens long at 393 × 852), not the size; no
real phone was at hand to say more.

## Carry-forwards for Sprint 32

1. **The compact type, on a real phone.** Board 06 looked large to the
   owner; the UAT measured no text under 12 px and a handset's body size,
   and found density, not size, makes it read large. *Owner:* the owner,
   who decides between keeping board 06's sizes and one step down
   (ADR-0062 §6 "text 15–17"), on a phone. *Why:* D-1 criterion 4's phone
   check is open, and no phone is at hand in this environment.
2. **#1485's decision** (S1 candidate, older, `needs-decision`, filed under
   #416 because #418 is full): count a deep target in the allocated sum
   when no ancestor carries one, and amend ADR-0040 §2. *Owner:* the owner,
   through the next plan's recommendation. *Why:* it changes how stored
   targets are read into money figures.
3. **The Datenqualität widget's legacy-0 hint** (D-5, ADR-0062 §13),
   deferred to that widget's pass, with the UAT's older finding that the
   security's price chart draws a stored 0 (#1365), which ADR-0051's
   amendment should rule on. *Owner:* the next plan. *Why:* a stored 0 is
   skipped everywhere but listed nowhere for removal.
4. **I48 next** (the colours and the card), before the second widget pass
   redraws the cards; Wealth's pass after it. *Owner:* the next planning
   session. *Why:* D-10, so no card is drawn twice.
5. **Lane P's two S3s**: a new view bumps no basis, so it is warmed only at
   the next write; a memo hit leaves an older queued read to run. *Owner:*
   the Wealth pass. *Why:* both are recorded, neither has a list row yet.
6. **The other recorded S3s onto their polish lists**: introduced (F3's
   wide heads, the companion's cut 409 body, the „six chips“ comment, the
   async „Cash“ without the locale, a queued dashboard read's older
   period, the empty edit mode behind the wizard) and older (M5's three
   `/portfolio` costs, Performance's 1y baseline one day before the
   movers', MO6 on #1365), and K1's suspected late scope lock in
   `assign_item`, which needs a three-writer harness. *Owner:* the next
   plan. *Why:* a session's memory ends with it; a list row does not.
7. **An agent's report counts only the files it ran, and every gate's exit
   is read directly.** A story agent runs the test files of every module it
   touched and names them in its report; the orchestrator re-runs those
   files at integration, and reads no gate through a pipe. *Owner:* the
   implementation session's briefs. *Why:* D4's report and the
   orchestrator's gettext check each turned CI red.
8. **No gate ships with a baseline or a named exemption**, not even for one
   commit; a walk that finds a defect fails until the defect is fixed or
   filed. *Owner:* the implementation session. *Why:* D8's KNOWN array and
   fix batch 3's exemption both reached the branch.
9. **A closing-act fix that changes the screen gets its frame first.**
   *Owner:* the fix briefs. *Why:* three frames were drawn after their
   code.
10. **The account's weekly usage limit is a planning constraint.** Plan a
    sprint's agent work within it, keep every agent's commits whole so a
    stop loses nothing, and estimate the closing act at about one and a
    half fixes per build commit on a new surface. *Owner:* the next
    planning session. *Why:* the limit stopped a fix agent for about 38
    hours, and the closing act took 58 commits against about 35 planned.
11. **One lock-table row per lane, reserved in the plan.** *Owner:* the
    next plan with a lock order. *Why:* K and D1 took row 28 in parallel.
