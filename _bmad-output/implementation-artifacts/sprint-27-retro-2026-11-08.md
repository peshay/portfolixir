# Sprint 27 Retrospective — the news layer's first half, and the stacked chart (2026-11-08)

ADR-0026 step 5 for Sprint 27, written by the implementation session as the
sprint PR's last commits (sprint workflow §5). The plan,
`sprint-plan-2026-11-07-sprint27.md`, was adopted by the merge of its
planning PR, which signed ADR-0056's amendment of 2026-11-07 (B1 to B8),
I23's decisions D-4 and D-5 and the `AGENTS.md` corrections of 2026-11-07.
The close-out entry with every criterion and count is in
`sprint-status.yaml`; this file keeps what the sprint teaches.

## What shipped

One PR under the plan's D-10: the sprint PR #1422
(`claude/determined-knuth-u9l6al`, the branch the environment assigned),
75 commits before the close-out's four, against an estimate of about 43;
no stacked PR.

- **Lane M:** M1, the version report, and its row for `saxy` 1.7.0, the
  one dependency the sprint took (N1), audited and pinned exactly.
- **Lane N, the news layer's first half** (FR-52, #1405; risk tier
  security): N1, the parser, its attack fixtures written and seen failing
  first; N2, the tables and a security's `news_identity` and
  `news_watch`; N3, the fetcher and its scheduler, a feed's URL checked
  with resolution at registration and before every fetch, `AGENTS.md`'s
  B3.3 sentence with its gate registry; N4, the matcher over the
  universe; N5, the tier table and stories, pinned by a shuffle test of
  50 orders; N6, retention and health; N7, the four reads with their
  budgets as tests; N8, the three upkeep writes and the news keys of
  `securities.update`; N9, the documentation in English and German.
- **Lane S, the stacked chart** (FR-53, #1419): S1, the bands in the
  performance walk, its other outputs byte-identical; S2, the read in the
  performance family's three forms and two tools; S3, the chart on Wealth
  on board 01, A, with the privacy mode's 100 % stack.
- **The closing act:** for Lane S the money lens and the design critic;
  for Lane N five lenses (correctness, edge cases, security as a hostile
  feed host, order, the agent); ADR-0056's amendment of 2026-11-08 (C1 to
  C7); the fixes; a re-check, which verified 33 of the 34 reports fixed
  and found one S1 older than the sprint (#1423); and the UAT persona's
  walk on the review seed, with eight screenshots in
  `uat-sprint27-2026-11-07/`.

## What went well

* **THE ATTACK CASES CAME FIRST, AND THE PARSER HELD.** Sprint 26's
  carry-forward 6 was applied as written: N1's fixtures (an
  entity-expansion bomb, external entities naming a file and a URL,
  10,000 levels, a body over the cap, 5,001 items, a truncated document,
  1,000 invented names) were seen failing before any parser code, and
  each is refused without the parser reading past the refusal, the atom
  count unchanged. The security lens, attacking as a hostile feed host,
  reported nothing against the parser; its five findings sit around it.
* **THE ORDER LENS ATTACKED WITH TRUE ITEMS, AND THE RECORD WAS AMENDED
  BEFORE ANYTHING WAS STORED.** The shuffle test passed in every order,
  and still the order lens found two ways a party with true items decides
  a story: a chain of lower-tier items joining two primary stories (C1),
  and a survivor key that fell to an attacker's URL within one scheduler
  tick (C2). Both became real tests, shuffled, and the amendment of
  2026-11-08 carries the rules. The news tables hold nothing on an
  instance yet, so no stored row needed correcting.
* **THE MONEY HELD.** The money lens recomputed the pinned band sums
  independently and found no S1; its four findings (a non-EUR base, a
  34th-digit bound under non-terminating FX, a privacy legend over 100 %
  with negative cash, a drilled empty category) were fixed with tests.
  The UAT persona's walk agreed with the API across the digest, a list, a
  story, the health and the companion, and Wealth's stack matched the API
  to the cent at the category level and in a drilled category, with the
  privacy mode clean.
* **A CROSS-CUTTING MODE RAN AGAINST THE NEW PAGE BEFORE THE CLOSING ACT.**
  Carry-forward 2: S3's states ran with the privacy mode forced on in the
  normal job's backstop and in the leak walk from the story's own commits,
  so the stack met the mask before integration, not at it.
* **PARALLEL LANES, AGAIN.** The build stories and the closing act's
  agents ran in their own worktrees, each on its own test database, and
  were integrated by cherry-pick, history forward only.

## What did not go well

* **THE PARALLEL LANES MET IN SHARED FILES.** Integration conflicted in
  the B4 backstop (N1 and N2), in `news.ex` (N3 and N4, N3 and N6, N6 and
  N8), in the gettext catalogues (N2 and S3) and in the schema budget and
  `llms.txt` (Lane S's fixes against N7). Each was resolved mechanically
  and none left a defect, but one merge did (the context's aliases out of
  order after N3 and N4, CI's quality job red), and the integration order
  followed what had finished rather than the plan's lane order (S1 and S2
  landed between N1 and N2, N3 after N4 and N5). *Cause:* nine stories
  share one context module and four registries; the markers of Sprint
  25's rule help only where a file already has the convention, and
  `news.ex` had none.
* **THE CONTAINER RESTARTED TWICE IN THE CLOSING ACT.** The agents resumed
  from their transcripts, and the cost was the time to rebuild each
  one's state, in the part of the sprint where most agents ran at once.
* **A LENS FOUND AN S1 IN A GATE THE LANE ITSELF REGISTERED.** N3 gave B2
  a new kind of allow-list, `hosts_from: :stored_feed`, mapped to "any
  host" for whichever module declared it, while B2's caller scan saw only
  callers of `Net.Http`. The fetcher's public `get/2` and `request/2` took
  any URL and merged a caller's request options, so an unregistered
  module could reach any host with any header and B2 stayed green
  (SEC1, latent: nothing in `lib/` did it). *Cause:* the story that
  widened the gate wrote its self-test, which attacked a feed URL that
  resolves privately and a redirect (carry-forward 3) but not a caller
  other than the scheduler; a public function that performs I/O was not
  treated as a chokepoint. The re-check then found the same gate blind to
  a call written in atom form (`:"Elixir.Req".post(…)`, `Module.concat`),
  older than the sprint, filed as #1423 under #420 and fixed on the
  branch.
* **THE BROWSER LEAK WAS FOUND LATE.** The privacy leak walk runs only in
  CI's browser job, and it was red on three pushed heads before it was
  read: two figures drawn as text on a bond's Overview (the two-scales
  note, an overview metric's sub-line). The file is not in the sprint's
  diff, so the defect is older than the sprint, reached by the walk's new
  states; the fix draws them as the bar and the backstop's world now
  holds a bond on each scale. *Cause:* the browser suite was not run
  locally before the closing act, though `AGENTS.md`'s Required Local
  Checks list it.
* **THE BUDGETS WERE MEASURED ON THE WRONG TEXT.** N7 measured its token
  budgets on the API's JSON over a plain fixture, while the agent reads
  the companion's text, which spells an invisible character as
  `[U+XXXX]`; soft hyphens and tag characters put the digest at 840 and a
  list at 6,918, and a clip by graphemes let a tag run pass as one. After
  the fix the re-check still found `news.get` at 496 tokens in the worst
  case (a long link and its members), fixed by the last commit of the
  closing act. *Cause:* the budget test sat at the API, one layer short of
  the reader it protects.
* **THREE FLAKY TESTS WERE INTRODUCED.** N1's linear-time bound (1 s,
  missed under a loaded suite; now 10 s, against hours for a quadratic
  parse), PrivacyModeTest reading a category id of 1263 in an address as
  a figure, and the scheduler's isolation test racing the wall clock.
  *Cause:* a wall-clock bound and an id-valued fixture, each true on an
  idle machine.

## The regressions, counted apart

The sprint workflow §3 and ADR-0026's amendment of 2026-11-01: the
regressions this sprint introduced are counted apart from the older
findings it passed.

| | S1 | S2 | S3 | Fixed on the branch |
|---|---|---|---|---|
| Introduced, found in the build and integration (the flaky bound, the „1263“ leak, the fetch's stamp before its wait, the scheduler's race; a raw U+200B in a test, the aliases' order) | 0 | 4 | 2 | 6 |
| Introduced, found by Lane S's closing act (money lens 4, design critic 5) and the UAT persona (the 1200 px line) | 0 | 3 | 7 | 9 of 10 |
| Introduced, found by Lane N's five lenses (25 reports, 24 distinct, SEC2 and EDGE1 the same) and their three polish lines | 1 | 12 | 14 | 27 |
| Introduced, found by the re-check and the suite under load (two news polish lines; an upsert race in a news test, filed as #1424) | 0 | 1 | 2 | 0 |
| **Introduced, total** | **1** | **20** | **25** | **42 of 46** |
| Older, found by the re-check and the leak walk (#1423; a bond's Overview in the privacy mode) | 1 | 1 | 0 | 2 |
| Older, recorded and not fixed (the log-noise check failing under load, filed as #1425; other adapters merging a caller's `req:` options) | 0 | 1 | 1 | off the diff's surface |

The one introduced S1 is SEC1, the B2 bypass through the fetcher's public
functions; it was fixed with an attack case in B2's self-test before
promotion. The older S1, #1423, is fixed on the branch before promotion
too. Of the four introduced findings not fixed, three are S3s: the stack's axis
values inside the plot at 1200 px with a heavy halo (a line for #1366),
two news lines for #1356 (short names that share 19 characters coincide;
a feed deleted and registered again stores its items again), all S3, and
one S2, a flaky test: an upsert race in `Sources.put_source` seen once
under the full suite, filed as #1424. Nothing is withheld to make a
count.

## Exit criteria (D-1)

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | ADR-0056 §14's sprint items on synthetic fixtures | **PASS**, item 2 with the closing act's last fix | identity, size (the budgets through the companion's text, C5), dedupe per language, freshness by a fixture clock, health and no archive each pinned; items 6 and 7 are Sprint 28's, item 8 holds because no read needs a label |
| 2 | A1's attack fixtures refused | **PASS** | each refused before the parser reads past it; the atom count unchanged over 1,000 invented names |
| 3 | No order and no feed's claim decides | **PASS**, as amended (C1, C2) | the shuffle test in 50 orders; the chain and the URL tie-break as real tests, shuffled; a future `published_at` clamped; an aggregator item naming a primary domain reads `secondary` |
| 4 | No request to a host the URL policy refuses | **PASS** | a privately resolving name refused at registration and makes no request at fetch; a redirect to another host makes no request; the request path private (SEC1) and a trailing dot read away (C6) |
| 5 | The bands add up | **PASS**, with one stated bound | on every day of every pinned case the bands sum exactly to the series; the walk's other outputs byte-identical; the screen equals the API; with non-terminating FX a category stack sits within one unit in the 34th digit, stated in the basis and pinned (M2) |
| 6 | Every gate holds by registration | **PASS** | B2, B3, B4, B5, B6 and B7 name the new entries with their reasons; no ignore, no skipped test; the schema ceilings grew by the new tools' own bytes and were lowered after the closing act's wording; N1's time bound was loosened from 1 s to 10 s, which still tells linear from quadratic, named here |
| 7 | Regressions counted, none an S1 at promotion | **PASS** | the table above; SEC1 and #1423's gate fixed on the branch |

## Carry-forwards for Sprint 28

1. **A gate a story widens gets the lens that attacks it before
   integration.** When a story adds a new kind of entry to a backstop (an
   allow-list from stored data, a new excuse), a lens other than the
   story's author attacks that entry with a caller or input the
   registration did not name, before the story is cherry-picked. *Why:*
   SEC1 sat green in B2 from N3 to the closing act.
2. **A public function that performs I/O is a chokepoint and is
   registered as one,** with the modules allowed to call it, and the
   backstop sees a call however it is spelled. *Why:* the fetcher's
   public functions bypassed B2, and the same gate missed a call written
   as an atom (#1423).
3. **The browser job runs locally before the closing act**, on the
   integrated head, as the Required Local Checks list it. *Why:* the leak
   walk's verdict came from CI, three heads late.
4. **Budgets are measured on the companion's text from the first
   commit,** with invisible characters spelled as the agent reads them
   and the worst-case fixture beside the plain one. *Why:* N7 measured
   the API's JSON, and AG1 found the reader's text up to six times its
   budget.
5. **An order lens on any rule that reads several records — keep.** And
   ask, of every tie-break key, which of its parts are constant within one
   batch. *Why:* C1 and C2 passed a shuffle test; within one scheduler
   tick `first_seen_at` is constant, so the key fell to a URL the
   attacker chose.
