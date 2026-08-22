# Sprint 8 Retrospective — the design-language execution, and the debt with a deadline (2026-08-22)

**Status: written at close-out.** PR #735 was rebase-merged 2026-08-22
(~16:24 UTC), 24 commits linear on `main`, head `125d656`. The annotated
`0.8.0` tag is **prepared as an owner action** — command under "Close-out
ledger". The Lane Z guard shipped in this very batch makes a lightweight tag
loud in the release body, so the fourth repetition of the reminder is now a
mechanism instead of a sentence.

## What shipped

One batch on one branch, one PR (#735), per the adopted plan
(sprint-plan-2026-08-20-sprint8.md, D-1 signed on adoption). Fourteen issues
closed by the merge's keywords, verified against the post-merge open-issue
list: #731 #732 #717 #718 #719 #720 #721 #723 #729 #730 #724 #725 #726 #728.

- **Lane Z:** the Release workflow resolves the pushed tag's object type and
  warns — plus a line in the release body — when it is lightweight, failing
  soft on API outage. `AGENTS.md` step 5 carries the prepared-command path.
- **Lane A (the deadline lane):** #731 `?since=` on `/transactions` and
  `/securities` with one-tap windows, the deletions clause stated on the
  surface; #732 column pickers on the history and holdings tables plus
  `fields=` on `GET /api/v1/securities` and its MCP tool. The two-way
  coverage rule's debt from Sprint 6 is **discharged inside its deadline**.
- **Lane B (#707 execution):** filter chips replace the query builder as the
  primary securities filter (#717, incl. the new `missing_fx` predicate);
  the drift card and view switcher named for their content (#718, #720); the
  custom date range validating as a range (#721); the computing cue earned,
  not automatic (#723); built-in classification trees speaking the locale
  (#729); the subject column staying reachable (#730).
- **Lane C (risk-tier):** the Cash-flow area goes from one facet to four —
  Realized gains (#724, decision D-1), Deposits & withdrawals (#725), Costs
  (#726, overview level only *by requirement*). Every facet ships its API
  endpoint, MCP tool and a computation basis in the payload, and every facet
  names what it excludes.
- **Lane D:** #728 pins Node to the 24 LTS line in the four places that must
  agree — CI, `engines.node`, the companion image, `@types/node` — with an
  invariant test holding them together. The `@types/node` 24→26 major is
  **declined and recorded**: types follow the pinned runtime, and 26 is not
  LTS until October.
- **Lane M:** `version-report-2026-08-22.md`, written at lane time (Sprint
  7's process miss, not repeated). Applied rows in their own commits
  (phoenix, phoenix_live_view, req); the deliberately-not-updated rows carry
  reasons, including both toolchain halves.

## Agentic review closing act — what it caught

Run under section G's conditions and **stating them**: DE locale, 390 px,
a synthetic seed firing every finding surface (an unclassified security, a
stale quote, a plan summing to 75 %, a USD sale whose close date has no
stored rate), plus a pass over the new facets' empty and excluded states.
Five confirmed findings, all fixed on the branch before promotion:

1. **The facets contradicted the decision they were built under** (risk-tier,
   money). All three converted through `Fx.convert/4` — most recent rate *on
   or before* the date — where D-1 says "never converted at a neighboring
   date's rate". A test on D-1's exact shape returned `excluded.count == 0`
   against the decision's required 1. Fixed with the exact-date
   `Fx.convert_on/4`/`rate_on/3`; valuation keeps at-or-before.
2. **Five blocks on /transactions were clipped and unreachable at 390 px** —
   grid `min-width: auto` under `overflow-x: clip`, defeating UX-DR15's
   per-block scrollers; the new changed-since chip row was among the victims.
3. **The Cash-flow matrices had no scroller**, so the sticky year-total
   column rendered on top of the clipped months ("0,00" printed over
   "260,90").
4. **Stale basis statements** in three MCP tool descriptions, three UI
   tooltips and four doc sections after the FX fix — under the metric rule a
   wrong gap statement *is* the defect, wherever it sits.
5. **A control that could not act:** "Store the missing exchange rates."
   linked to a page with no rate control, and rate sync fetches the daily
   feed so it cannot fill a past date regardless (filed as #737). Replaced
   by the sentence that says why.

Findings 2, 3 and 5 hardened into the living spec as **UX-DR25** (an
excluded row is named where the total is read — with the no-dead-control
clause) and **UX-DR26** (a deliberate limit is stated on the surface that
lacks it), because the batch built each shape three times.

## What worked

- **The signed decision caught its own violation.** D-1's rate-availability
  clause was spelled out verbatim at adoption; that precision is what made
  "the code does something else" a checkable claim instead of a taste
  dispute, and the risk-tier verification pass (ADR-0036 step 2) is where it
  surfaced.
- **Section G earned its keep again.** All three UI findings were invisible
  at desktop width in EN with bland seed data — the exact blind spot the
  rubric section was written against after Sprint 6.
- **The Lane M report at lane time** meant the toolchain reversal had a
  place to be recorded the same day, not reconstructed at close-out.

## What to carry forward

1. **"Green" means CI on the branch, never a local run.** The Elixir 1.20.3
   bump broke the coverage gate (`:cover` cannot instrument 1.20.3 BEAMs;
   excoveralls dies before a single test), and it stayed invisible for six
   and a half hours because the local toolchain was still 1.18.3 — local
   suites kept passing while every CI run failed. The claim "full gate set
   green on the new compiler" was a local claim. The bump was reverted; the
   1.20 type-checker's dead-clause removals were kept; #727 carries both
   blocked halves with evidence and re-check triggers. Habit: after any
   toolchain change, the first authoritative signal is the CI run, and a
   session joining a branch checks that branch's CI state before building
   on it.
2. **Two sessions built the same sprint in parallel** (#735 and #736, created
   a minute apart), and the duplication was only caught when the second
   session inspected the first's PR. Cost: one full parallel implementation.
   The owner picked #735; everything of unique value in the duplicate (the
   exact-date FX path, the D-1 test, the Node invariant test) was ported.
   Worth a look at session start discipline: an open PR claiming the same
   closing keywords is a stop sign.
3. **A payload's basis statement is part of the diff.** Three MCP
   descriptions and three tooltips kept describing at-or-before after the
   behaviour changed. The metric rule's point — the payload is where the
   reviewer and the agent both read it — cuts both ways: change the
   behaviour, grep for its old description.

## Close-out ledger

- **Issues:** 14 closed by the merge's keywords (verified — none remained
  open). Closed by hand: none needed. Stays open by design: #727 (both
  toolchain halves blocked upstream, evidence and re-check triggers on the
  issue), #737 (no path to store a historical FX rate — filed from Lane C),
  #738 (README predates Snapshots/Tax/performance — filed from the
  close-out), and the standing trackers #356, #417, #418, #419, #420, #470.
- **Two-way coverage check (the close-out's own duty):** the Sprint-6 debt
  #731/#732 is discharged. The batch's new agent-visible capabilities (three
  facet endpoints + tools, `fields=`) all shipped **with** their human views
  in the same batch — no new debt enters the ledger.
- **Merge CI:** run 1445 on `125d656` — verified green before this close-out
  was pushed, required checks included.
- **Tag (owner action, annotated — the Lane Z guard will call out anything
  else).** Merge the bookkeeping PR first, then tag the resulting `main`
  head — the 0.7.0 precedent, where the tag sits on the bookkeeping commit
  because a docs-only delta still marks the right software. (Tagging the
  batch head `125d656` directly is equally valid; a squash-merge adds a new
  commit and changes nothing about existing ones.)

  ```bash
  git fetch origin main
  git tag -a 0.8.0 origin/main -m "Sprint 8 — design-language execution, four Cash-flow facets, the two-way-rule debt discharged"
  git push origin 0.8.0
  ```

  **That is the whole ceremony.** The tag push triggers the Release
  workflow, which creates the GitHub release with generated notes by
  itself — do NOT create one via the release UI afterwards; the UI path is
  exactly what produced the three lightweight tags.
