# Sprint 11 Retrospective — the perimeter's remainder, and the founding question (2026-09-15)

**Status: written at close-out.** PR #810 was rebase-merged 2026-09-15
(12:16 UTC), 23 commits linear on `main`, head `c2164f54`. The annotated
`0.11.0` tag is **an owner action** (D-4, ADR-0026 step 5 as amended on PR
#780); the command is under "Close-out ledger". The plan was adopted
2026-09-07; the branch opened 06:28 UTC on the 15th and the merge came six
hours later.

## What shipped

One batch on one branch, one PR (#810), per the adopted plan
(sprint-plan-2026-09-07-sprint11.md) and the decision gate ADR-0046, with
D-2, D-3 and D-4 executed as signed. Six issues closed by the merge's
keywords, verified against the post-merge open-issue list: #772, #382, #776,
#779, #610, #572.

- **Lane D — the HTTP server (#772):** Bandit 1.12.5 serves the endpoint;
  `plug_cowboy`, `cowboy` and `cowlib` leave the tree with cowlib's three
  advisories; CI installs the current Hex with no pin and `mix deps.audit`
  runs with no ignore, which is what surfaced two mint advisories (mint
  1.10.0, its own commit); every Action is pinned to a commit SHA with its
  version as a comment.
- **Lane C — the CSP (#382):** a per-request nonce for the browser pages,
  `script-src 'self' 'nonce-…'`, no inline event handler left in any
  template (data attributes and document-level listeners in the root
  layout), `connect-src` naming the validated Host's socket origin; the
  HTTPS posture stated in `config/prod.exs` and opt-in through
  `PHX_FORCE_SSL` (D-2), so Sobelow runs with no `--ignore`. Thirteen routes
  boot, connect and reconnect under the header in a real browser with an
  empty console.
- **Lane W — the limit surface (#776):** the nine remaining collection reads
  take a bound — the four research-log reads, the snapshot list, the three
  cash-flow roll-ups (a number of years of the annual matrix, the basis
  naming a cut), the trades read bounded by `from`/`to` and saying so; every
  bounded payload echoes the limit it applied, the MCP twins the same.
- **Lane X — the walk on retired securities (#779, #610; D-3, risk-tier):**
  a delivery carrying a booked price enters F_d and the lot queue at that
  price (a total loss booked out at 0 is a −100 % day, not a withdrawal at
  the stale quote) and seeds the price of a security that has none; a
  retired security's stale quote is not a measurement, so its next own trade
  restates the basis instead of chaining a phantom return; `price_date` per
  position and `stale_priced_count` on the valuation, retired holdings left
  out, and the Wealth page names the holdings to retire. ADR-0010 amended;
  registry computation version 3; twelve exact-Decimal fixtures.
- **Lane B — the benchmark comparison (#572; D-1, risk-tier):** the
  `is_benchmark` flag (listable, never bookable), the engine — a fixed rate
  compounding daily Act/365 or a flagged security priced like a holding,
  "bought once" and "savings plan", the covered window with its rebase day,
  excluded flows named, memoised under ADR-0039 and never from a superseded
  walk — the two API reads with their MCP tools and the manifest v4 entry,
  and the Wealth page's picker, the ≤ 2 overlays with legend, table columns
  and tooltip, and the comparison block beside TTWROR/IRR, DE and EN.
  ADR-0046's three identities are pinned exactly: a 0 % savings plan ends at
  ADR-0034's invested capital; a benchmark that is the single holding gives
  a zero delta and equal IRRs; a flow before the first quote is excluded and
  named with the window stated.
- **Lane M:** `version-report-2026-09-15.md` at lane time; applied as their
  own commits: the Bandit swap's moves, mint 1.10.0, phoenix 1.8.14, dialyxir
  1.4.8 (superseding #781), the MCP lockfile (hono 4.13.8); left with
  reasons: Elixir/OTP (#727, triggers re-checked, none fired, #775 closed),
  the Node 26 image (#782 closed until the LTS promotion), the @types/node
  major, the Dockerfile Hex pin, PostgreSQL, the BMAD modules.
- **Lane Z:** the registry rows at branch opening; this close-out reconciles
  the rest.

## What the closing act found

Five roles ran on the branch — correctness hunter, edge-case hunter, a
risk-tier verification pass on Lanes X and B, the design critic against the
living spec, and the UAT persona walkthrough under the #706 conditions (DE,
1280 px and 390 px, real Chromium under the nonce CSP, the synthetic demo
dataset, every write through the operator's own path). Thirty-odd confirmed
items, every one in scope fixed on the branch in five commits before
promotion; the walkthrough with its twelve shots is in
`uat-sprint11-2026-09-15/walkthrough.md`, the shots in a PR comment from the
start.

1. **A comparison built from a superseded walk was memoised as fresh.** The
   Wealth page renders the previous analysis while the fresh one computes;
   a comparison built from that one landed in the memo under the current
   data version and was served as fresh afterwards, its delta ignoring the
   write the TTWROR beside it showed. Never memoised from a stale analysis
   now, and the memo suite runs with the derived layer on.
2. **An unbounded rate crashed the daily factor.** A rate a hair above
   −100 %, or beyond the float range, was a 500 on the API and a Wealth
   page that died on every mount through its own cookie. One bound — the
   IRR solver's domain — shared by the engine, the API parser and the
   selection plug; the plug also refuses an id beyond int8.
3. **A priced delivery was no price observation** (risk-tier pass): a
   security whose first booking is an inbound delivery with a price was
   valued at 0 the day its units arrived, a total loss for ever. The
   delivery seeds the price now.
4. **Retiring the stale-quoted holding left the finding standing** (UAT):
   the remedy the finding named did not clear it. A retired holding leaves
   the count, the finding and the predicate the finding links to.
5. **The design critic's round:** the figure named ("Benchmark comparison",
   "savings plan: …"); the period MWR pair on short windows instead of a
   hard-coded IRR label, which put `portfolio_mwr`/`benchmark_mwr` on the
   wire; overlays reachable as table columns and in the chart's accessible
   name (UX-DR10); slot 2 dotted in every swatch (UX-DR7, the rule's table
   extended); the value chart's missing overlay stated (UX-DR26); chips in
   the picker; one row composition at 390 px; 44 px picker controls on a
   coarse pointer; DE copy.
6. **Small, all fixed:** a blank date in the uncovered-window note; a stored
   close of 0; a flow on the rebase day listed as excluded; a negative
   delivery price accepted; the IRR solver's signed zero; the computation
   basis not disclosing the rebase rule, the float factor, the exclusion
   cause and the opening-value entry.

Recorded, not changed: the single-holding identity is exact when the
base-currency price terminates and differs by one unit in the 34th digit
otherwise; the memo key composes the comparison's own computation version,
so a future bump of the walk's version must bump it too; money on the wire
stays unrounded.

## Process findings

- **The closing act did not read the coverage report, and it should.** After
  promotion, Codecov listed 45 changed lines without a test — above the 90 %
  patch target, so no gate was red — and a local reproduction sorted them:
  half defensive fallbacks unreachable from outside, half documented
  behaviour paths without a test, several in risk-tier code (the engine's
  GBX pricing through GBP, its unpriced days before the first stored FX
  rate, the year period, the covered-window note with the anchored overlay,
  the CSP's `connect-src` from the Host header). Four review roles had read
  the code and none had asked for these; a listing of uncovered changed
  lines would have. Pinned in one tests-only commit before the merge (patch
  coverage 96.7 %, the remaining twenty lines named as deliberately
  untested). **Standing rule from here:** the patch-coverage listing is an
  input to the correctness and edge-case hunters, and the briefing names
  what stays uncovered and why.
- **The check-in held.** Sprint 10's watch lapsed when a one-shot check-in
  disabled itself after firing; this time it was re-armed on every firing
  and its prompt updated after promotion, so every event reached the
  session — the Codecov edit, the check-suite completion, the merge. The
  cost is one call per hour; the alternative was proven in Sprint 10.
- **The history cleanup for the rebase-merge worked as written.** Three
  `fixup!` commits (a CSP fix and two credo findings — an alias order and a
  predicate name) were folded into the commits that caused them with a
  scripted `rebase --autosquash`, the final tree verified byte-identical
  against a backup ref, and the force-push went with `--force-with-lease`.
  Worth keeping as the pattern: record mechanical fixes as fix-ups at the
  time, fold once before promotion, never rewrite after.
- **Two proposals the closing act made and the branch refused, recorded in
  the briefing rather than argued on the PR:** rebasing "bought once" at the
  prior close even when the window opens with no value (it would break the
  0 % and 2 % identities for a fixed rate), and one common window cut to the
  shortest history (it would silently shorten the fixed-rate comparison). A
  deliberate trade-off stated where the reviewer reads is cheaper than a
  round.
- **Sprint 10's screenshot finding was acted on:** the shots went into a PR
  comment from the start and rendered; nothing was lost to the API's
  escaping.
- **Nothing died on a session limit.** The review roles completed; the
  session was compacted once mid-batch without loss. The pre-flight stands.
- **Codecov's check runs appeared on the second head and not the first.**
  On the promoted head the report was a comment only and the head carried
  no status; on the tests commit two check runs (`codecov/patch`,
  `codecov/project`) appeared and were green. Both heads were verified from
  the check runs rather than the comment; noted so the next close-out does
  not read the absence of a status as a passing one.

## Close-out ledger

- **Merged:** PR #810, 2026-09-15 12:16 UTC, rebase-merge, `main` at
  `c2164f54`, 23 commits linear (cc70b9f..c2164f54). Actions on the merge
  push verified green before this entry: CI 1506, Commit authorship 520.
- **Closed by the merge's keywords:** #772 #382 #776 #779 #610 #572 —
  verified against the post-merge open-issue list (48 open), none remained
  open.
- **Closed by hand:** none — no tracker of the sprint's own (Lane Z: no new
  epic); E21's #757 was closed in Sprint 10.
- **Filed by the batch:** #811 (the journal read's own limit parser clamps
  where the shared parser refuses; the surface check's outlier). Filed by
  the plan: #779.
- **Stays open with a reason:** #727 (both toolchain halves blocked
  upstream; both triggers re-checked 2026-09-15, neither fired; #775 closed
  with the reason), #314 (the ratchet rides every batch), #811 (a Sprint 13
  candidate; Sprint 12's cut is adopted).
- **Registry:** E10 to in-progress on its first shipped item; E21's
  remainder shipped, nothing in the family open; the FR-9, FR-8 and NFR-4–6
  rows and the Tracker Index E10 and E21 lines updated; the two-way
  coverage ledger empty; the surface check's sentence in the log.
- **Next:** Sprint 12 per `sprint-plan-2026-09-12-sprint12.md` (adopted by
  the merge of PR #783), D-1 satisfied by this merge: its branch
  `agent/claude/ux-alignment-2` opens on `main` at or after `c2164f54`.
- **TAG: `0.11.0` is an OWNER ACTION** (D-4). The annotated tag on the
  merged head, from a clone with push rights:

  ```bash
  git fetch origin
  git tag -a 0.11.0 c2164f54 -m "0.11.0 — Sprint 11: the perimeter's remainder and the benchmark comparison"
  git push origin 0.11.0
  ```

  The push triggers the Release workflow, which creates the GitHub Release
  with generated notes.
