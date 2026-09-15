# Sprint 12 Retrospective — the surface, brought level with its spec (2026-09-15)

ADR-0026 step 5 for the Sprint 12 batch. Written against the merge commits on
`main` and the Actions runs on the merge push, not against this repository's
prior claims. The `0.12.0` tag is an owner action (D-5 of the plan; ADR-0026
step 5 as amended on PR #780); the command is under "Close-out ledger". The
plan was adopted by the merge of PR #783 on 2026-09-12 and its D-1 held: the
branch opened on the commit that merged Sprint 11.

## What shipped

Twenty-two issues across eight lanes on one epic branch
(`agent/claude/ux-alignment-2`), PR #813 rebase-merged 2026-09-15 19:46 UTC,
`main` at `5ea57ea3`, 28 commits linear (`d6466f7d..5ea57ea3`, no merge
commits). Closed by the merge's keywords: #784, #785, #786, #788, #790, #791,
#792, #789, #787, #795, #796, #802, #793, #794, #797, #798, #799, #800, #803,
#804, #805, #801 — all twenty-two verified `closed`/`completed` against the
post-merge issue list, none left open.

The batch was E11's second alignment pass, cut from the 2026-09-12
whole-surface UX review. What a reader of the app now sees that they did not
before:

- **Wealth opens on a two-tier KPI band** (#797): three lead figures — total
  including cash, TTWROR, IRR — over four compact ones, the currency a suffix
  after the digits rather than part of the number, each figure carrying a
  sub-line naming what it is measured against.
- **Overview gained a key-figure strip** (#798): the 1Y return with its
  money-weighted line, the cash quote, the last booking and quote freshness,
  each linking to the surface that owns the figure, over one basis line.
  `newest_quote_date` joined both valuation reads on the API and in MCP.
- **The phone reads as rows under 560 px** (#799, #800, UX-DR27): name over
  identifiers, figures right, row states as words rather than colour, and the
  filter chips behind a "Filter (n)" control that opens a bottom sheet.
- **Transactions opens on its history** (#803): the booking form as a side
  drawer in the detail pane's shape, non-modal on the desktop, a modal bottom
  sheet under 720 px. The duplicate holdings table left the route.
- **The classification tree reads as columns** (#805), **the custom range is a
  popover on its trigger** (#801), and **the securities detail opens on a
  reading surface** (#804) that renders no input element until an edit
  affordance is used.
- **Tax, Snapshots and Views** took their Component-Patterns shape (#795,
  #796, #802), and both charts gained "Daten als Tabelle" (#793, #794).

Against the plan's own definition of done, all seven items hold, each checked
rather than assumed: the three enum-label meta-tests exist
(`transaction_kind_label_test.exs`), the second-person guard exists
(`test/invariants/microcopy_voice_test.exs`), `dashboard.png` was refreshed, all
eight owner picks (C1-A, C2-B, C3-A, C4-B, C5-A, C6-C, C7-A, C8-A) are named in
`DESIGN.md`, `priv/demo/finding_surfaces_seed.exs` is committed and idempotent,
Lane M's report exists, and the `0.12.0` command is below.

## What the closing act found

Three adversarial roles read the batch against the code and against the
design spine — a correctness hunter, an edge-case hunter and a design critic —
and the UAT persona walkthrough ran under D-4's conditions: DE, 1440 px and
390 px, light and dark, on the committed seed script, with a booking walked
end to end through the drawer at 390 px. Thirty-nine route renders, no
horizontal overflow, no console or page errors.

**Twenty-nine confirmed findings were fixed on the branch** in one commit
(`9a3abc20`); `uat-sprint12-2026-09-15/walkthrough.md` lists every one with its
fix. The ones that mattered:

- **The Overview strip's stale count disagreed with the list it links to** —
  two numbers for one finding on one page. It now reads the shared predicate,
  so the count and the list it opens cannot diverge.
- **A retired security's old close was still being turned into a day change**
  on three surfaces, which is precisely the figure the stale marker exists to
  suppress. The staleness predicate now leaves retired rows, and the day
  change blanks with the marker.
- **The classification tree printed `0.00` while the holdings loaded** and
  summed an unpriceable position as zero. A total is now only a total when
  every row carries the figure; otherwise it dashes.
- **The note editor survived a change of security**, handing the next security
  a filled form.
- **Seven date renders printed ISO in German**, the stale marker among them.
- **The not-computable dash rendered at value weight** — the one state the
  band's re-composition exists to separate from "still computing".

Three findings were recorded as issues rather than widened into the batch:
#817 (the detail pane's tab row is held to none of the D6 shipped form), #816
(the transaction history needs the phone filter sheet the securities list got)
and #815 (the `/classifications` index is still a bare bullet list).

## Process findings

1. **The patch-coverage listing worked as a review input, the first batch it
   was one.** Sprint 11's close-out recorded that the closing act's inputs had
   not included it and made it an input from then on. This batch read it, and
   it earned its place twice: once on `asset_classes.ex`, where a de-slugging
   fallback added in the fix round had no meta-test and the batch's own voice
   rule requires one (`714d2126`), and once on `data_quality.ex`, where it
   pointed at a defaulted `today` argument whose `Date.utc_today()` fallback
   would have answered a local-calendar question in UTC (`5ea57ea3`, #609).
   The second was the more valuable: not an untested path but a wrong one,
   dead only because every caller happened to pass the argument.

2. **Both of those landed after promotion, as Sprint 11's did.** The pattern is
   now two batches old: the coverage listing arrives with the CI run on the
   promotion commit, so what it finds is necessarily post-promotion work. The
   fix is not more discipline but ordering — read the listing from the last
   pre-promotion CI run, while the closing act is still open. Recorded here
   rather than filed, because it changes the closing act's sequence, not the
   code.

3. **A "no behavior change" commit still costs a full CI cycle.** Both
   post-promotion commits were provably inert on every surface, and both were
   right to make. Noted only so the next batch's ordering fix is read as
   removing two cycles, not two commits.

4. **The rebase over a sibling close-out worked as designed.** #812 and #813
   touched the same two registry files by construction, and the plan said so
   in advance. The conflict was not semantic — both sides appended a record to
   the same newest-first log — and the check worth doing on a 28-commit replay
   was tree equality against the pre-rebase backup, which came back empty.
   The practice of writing a log entry's closing clause in the future tense
   ("rebases over it once it merges") is what made an edit necessary at
   resolution time; a clause that states the intent without predicting the
   outcome would not have.

5. **The two-way coverage rule fired for the first time, and on this batch's
   own removal.** See below. It is working as designed: the gap was filed the
   day it was created rather than discovered a batch later.

## Two-way coverage

**#814 is this batch's own gap, and its deadline is Sprint 13.** #803 removed
the "Current holdings" panel from Transactions because it duplicated Wealth →
Holdings. That panel carried the column picker #732 added as the human half of
the holdings API's `fields=` sparse fieldset — verified in the diff:
`@holdings_column_defaults`, `@holdings_column_keys` and the `#holdings-panel`
section with its `#732` comment all left with it. So the projection's
valuation fields are now readable over the API and MCP with no human view.

Per "API And MCP Coverage", that is allowed for the batch that creates it
provided the PR states why — #813's briefing does — with the human view due in
the same or the next epic batch. This batch is the "same"; **Sprint 13 is the
"next", and its close-out must find #814 shipped or record a finding.** The
batch filed #814 the same day, 15:48 UTC, under the scope-lock rule rather
than solving it opportunistically.

Nothing else in the batch is agent-only: #798's `newest_quote_date` shipped
with its human view in the same commit (the Overview strip's freshness cell),
and every other issue is a view change with no API surface.

## Surface check

**No new read-ergonomics parameter landed this batch**, so the parameter-family
sentence has nothing to enumerate. The check's spirit still applies to the one
payload field the batch added, and the answer is the good one: **`newest_quote_date`
landed on both valuation scopes, not one.** Verified at the call sites —
`valuation.ex:305` and `valuation.ex:410`, `json.ex:772` (portfolio scope) and
`json.ex:821` (view scope), and both MCP tools
(`portfolixir.portfolios.valuation` and the bucket-view valuation). That is the
same family FR-37 shipped half of, on the portfolio scope only, which became
#740; this batch did not repeat it.

The surface gap the batch *did* leave is a human one and is filed: the phone
filter sheet landed on the securities list (#800) and not on the transaction
history, which is #816.

## Close-out ledger

- **Merged:** PR #813, 2026-09-15 19:46 UTC, rebase-merge, `main` at
  `5ea57ea3`, 28 commits linear (`d6466f7d..5ea57ea3`, no merge commits). The
  rebase-merge replayed the commits, so the SHAs differ from the branch's; the
  tree is byte-identical to the pre-merge head `ceef8665` (empty diff), and all
  28 commits carry the maintainer's own identity with no AI trailer.
- **Closed by the merge's keywords:** the twenty-two above, each verified
  `closed`/`completed`.
- **Closed by hand:** none. E11's tracker #356 stays open deliberately — the
  review's remaining items (#806, #807, #808, #809) are Sprint 13 candidates by
  D-3, and the batch's own three findings (#815, #816, #817) attach to it, so
  the epic is not finished and closing its tracker would lose the thread.
- **Filed by the batch:** #814 (the `fields=` human half, Lane T), #815, #816,
  #817 (the closing act's out-of-scope findings).
- **Stays open with a reason:** #806, #807, #808, #809 (Sprint 13 candidates,
  declared by D-3 before the batch started); #814 (due Sprint 13 by the
  coverage rule); #815, #816, #817 (filed by the closing act, not widened into
  the batch); #727 (both toolchain halves still blocked upstream, both triggers
  re-checked at lane time, neither fired); #811 (Sprint 11's surface-check
  outlier, a Sprint 13 candidate); #314 (the ratchet rides every batch); #356
  (the E11 tracker, per above).
- **Registry:** the dated reconciliation in `epics.md`, the UX-DR1–20 row
  naming what shipped, the Tracker Index's E11 line, and this log's entry in
  `sprint-status.yaml`.
- **Lane M:** nothing applied — every Hex and npm dependency at its latest
  release, both audits clean, and the three Dependabot PRs the plan named
  (#781, #782, #775) already resolved by Sprint 11's lane the same morning.
  Six rows deliberately not updated with their reasons, in
  `version-report-2026-09-15-sprint12.md`.
- **Next:** Sprint 13 is unplanned. Its decision gate has four declared
  candidates (#806, #807, #808, #809), one coverage debt with a deadline
  (#814), Sprint 11's outlier (#811) and this batch's three findings (#815,
  #816, #817).
- **TAG: `0.12.0` is an OWNER ACTION** (D-5). The agent's credential cannot
  push tags. The annotated tag on the merged head, from a clone with push
  rights:

  ```bash
  git fetch origin
  git tag -a 0.12.0 5ea57ea3 -m "0.12.0 — Sprint 12: the surface, brought level with its spec"
  git push origin 0.12.0
  ```

  The push triggers the Release workflow, which creates the GitHub Release
  with generated notes — a rollback point for self-hosted instances plus a
  communicable changelog, never an installable artifact (issue #659).
