# Sprint 15 — the operator's own rules, the two surfaces the records assumed, and a backlog counted to the end

**Status: ADOPTED by the merge of the Sprint 15 planning PR.**
The merge is the signature (ADR-0026 step 1 as amended on PR #780). This
planning PR **signs one decision gate**: **B3.6**, closed by
[ADR-0049](../../docs/decisions/0049-policy-rules-as-first-class-objects.md),
as Sprint 14's D-6 named it would be. The merge also adopts:

- the lane cut and **D-1** to **D-10**;
- the three design picks of **D-4**;
- the backlog triage of 2026-09-23
  (`planning-artifacts/backlog-triage-2026-09-23.md`), with its five closures,
  two rescopes and two registry retirements (**D-3**).

Nothing here is `DRAFT` or `Proposed`. A decision the owner rejects is
removed on the PR before the merge. A closure the owner rejects is undone by
a comment naming its issue.

**Verification basis:**

- **`main` and CI:** `main` at `c0746222` (PR #846's rebase-merge), with
  **CI 1571** and **Commit authorship 585** green on it, read 2026-09-23.
- **The Sprint 14 close-out**, open as **PR #859**. This branch is stacked on
  its commit `d78d5d59` because both touch `sprint-status.yaml` and
  `epics.md`. It is rebased onto `main` once #859 merges, and the stack is
  never merged as one.
- **The open-issue list of 2026-09-23:** 29 open, every body read, not only
  the titles.
- **The published releases:** `0.11.0`, `0.12.0`, `0.13.0` and `0.14.0` all
  exist as tags and GitHub Releases, so **no rollback point is outstanding**
  (D-8).
- **The code, read for four claims the issues make about it:** triage §2.3
  names each read.
- **The design pass** this PR carries: `planning-artifacts/ux-design-2026-09-23-sprint15.md`,
  with five rendered boards.

## State of play, in five lines

1. **Sprint 14 merged and E22 is done.** PR #846 rebase-merged 2026-09-23,
   sixteen issues closed by keyword, #821 and #835 by hand, nothing shrunk.
   The close-out's bookkeeping is PR #859. Every tag the last four
   close-outs prepared is published (D-8).
2. **B3.6 opens here, as promised.** Sprint 14's D-6 held it for one sprint
   so the rules record could name real metric fields and real refusal states.
   The portfolio payload shipped, and ADR-0049 is written against it. A rule
   is a stored predicate over a figure the product already serves. It is
   versioned so "what was the standard on date D" is a read, and it is
   evaluated into findings that carry no action.
3. **The backlog is smaller than it looks, and it has been counted.** 29
   open issues hold **15 buildable ones**. The rest are trackers, standing
   lanes, one decision and five items the triage recommends closing. With
   the unfiled registry work, that is **about three sprints of work worth
   doing**. After Sprint 17 the product is feature-complete against its own
   identity and moves to maintenance (triage Part 1).
4. **The triage found two more surfaces the records assume and the code does
   not have.** Position-level SOLL has been settable only over the API since
   2026-07-21. A cross-currency buy cannot be booked in the form at all. Both
   predate the two-way coverage rule, like Sprint 14's risk lens. Both are
   this sprint's.
5. **The closing act keeps refilling the list.** Nine findings came from
   Sprint 14, six from Sprint 13. D-9 sorts them by reach so that
   hostile-input robustness stops setting sprint themes.

## Why this cut

- **The rules gate is overdue by design, not by drift.** The agent reported
  the prose-rule drift twice. Sprint 14 deferred the gate on an argument
  about order, and that argument is now spent. Deferring again would be the
  first deferral with no reason attached.
- **An operator who cannot enter their own steering is a bigger gap than any
  metric.** The two-way rule exists for the operator half of the identity.
  Lane D pays two debts older than the rule. Each makes a function reachable
  that only the agent could reach before.
- **The debt lane is capped.** Lane B and Lane C carry the eight Sprint 14
  findings. The shrink order cuts the hostile-input three before anything a
  person hits in normal use (D-9).
- **File ownership keeps one branch safe.** Lane A owns new files plus
  `risk_live.ex`, the API and the MCP companion. Lane C owns `app.css`, the
  area-tab component and the row-menu hook. Lane D owns `classifications_live.ex`
  and `transaction_management_live.ex` plus `ledger/transaction.ex`. Lane B
  owns controllers, the LiveView id parsing and `derived/invalidation.ex`.
  **The one shared file is `risk_live.ex`**: A4 builds the rules section in
  it, and #854's disclosure fix touches the correlations disclosure there.
  C lands its one-line template change first, then A4 builds on it
  (sequencing below).

## Lanes

### Lane A — E24 policy rules (ADR-0049, FR-43; first)

Four commit groups. The tracker and the story issues are **filed at branch
opening, not now**. That is the 2026-08-15 precedent: no issue carries a title
with no spec behind it, and this PR's merge is the signature that lets them be
written.

- **A1: the object, its versions and its writes.** `policy_rules` and
  `policy_rule_versions`:
  - **journaled from the first migration** (ADR-0017);
  - `Ecto.Enum`s with gettext label clauses and no fallback;
  - a **database-level exclusion constraint** so versions of one rule never
    overlap (ADR-0049 §4);
  - a version in force is immutable; a future-dated version is editable.

  Writes on API and MCP: create, add a version, retire. Delete only when no
  version was ever in force. Validation follows the measure matrix of §2 and
  the scales of §8. TDD first, starting from the two invariants the closing act
  will mutation-verify: *a version in force cannot be updated or deleted*, and
  *two versions of one rule cannot overlap*.
- **A2: the evaluation and its read.**
  - `Portfolixir.Engines.PolicyEvaluation`, pure over rule versions and a
    measure map;
  - its shell loads the measures from the existing reads (`Risk`,
    `Allocation`, `RiskMetrics`, `Valuation`) and computes none of its own;
  - `GET /api/v1/portfolios/:portfolio_id/policy_findings` with `view=` and
    `status=`, and `portfolixir.portfolios.policy_findings`;
  - registered with ADR-0039 as `policy_findings`, lifetime `:request`, keyed
    on the portfolio basis plus a rules counter every rule write bumps;
  - each finding carries its `computation_basis` (the AGENTS.md metric-basis
    rule applies to findings).

  **The invariant to write first:** *a rule over a refused metric, a missing
  target or a removed subject is `undetermined`, never `ok`, and appears in
  the default read with its reason and, for a refusal, ADR-0047's `required`.*
  The key-set meta-test `test/invariants/findings_carry_no_action_test.exs`
  lands in the same commit group. It fails on `action`, `recommendation`,
  `suggested_*`, `quantity`, `order` and trade verbs anywhere in the payload
  (ADR-0049 §6).
- **A3: identity and survival.**
  - Deleting a security, category or view that a rule version references
    answers **409** and names the rules.
  - A Portfolio Performance re-import preserves rules, pinned in
    `reimport_preservation_test.exs`, in the integration docs' re-import
    section, and **in the MCP tool descriptions** (#831's lesson).
  - The contract-version read reports the family, and the contract takes one
    bump.
- **A4: the human view.** The picked F1 variant (D-4; recommended **A**: a
  section on Wealth → Risk). Findings sort breached, then undetermined, then
  ok. The lens's table is retitled so generic thresholds and the operator's
  rules never read as one mechanism. Create, edit and retire use a native
  dialog that names the version it creates. The anatomy goes into `DESIGN.md`.

**Not risk-tier by ADR-0036's list:** the lane computes no money and touches
no projection. Its two invariants still get a **dedicated, mutation-verified
pass** in the closing act, and the briefing gets a callout (D-10).

### Lane B — the error contract and one freshness defect (four closing-act findings)

- **B1: #851, invalidation sees only the after-image** (*user-reachable*: an
  edit that moves a transaction between securities or portfolios leaves the
  old basis stale).
  - `Journal.record` hands the before-image to the invalidation seam, and the
    radius becomes the union of both images.
  - It changes the seam's contract, which is why it has its own commit. The
    widening invariant of ADR-0039 (`blast_radius_widening_test.exs`) is what
    it is held against.
  - **Risk-tier attention** (derived freshness is projection-adjacent): a
    verification pass and a briefing callout.
- **B2: #853**, `PUT /tax/parameters` with `{}` and `POST /views` with a
  non-map `view` answer 422 naming the field (*hostile input*).
- **B3: #855**, LiveView pages route `handle_params` ids through the shared
  id parser, with a sweep test over the live routes (*hostile input*).
- **B4: #856**, `offset` and `days` get stated upper bounds, answer 422 above
  them, and a sweep test covers the integer params of `/api/v1`
  (*hostile input*).

### Lane C — design-spec conformance (four findings, all boarded)

- **C1: #854**, one disclosure marker (board `04`, before/after). Lands
  **before** A4 touches `risk_live.ex`.
- **C2: #857**, the active area tab scrolled into view on mount (board `04`).
  **The board adds one requirement the issue lacks:** drop the right mask at
  the row's end and add the left fade away from its start, or the repair only
  moves the tab under the mask.
- **C3: #858**, the row menu's keyboard pattern (board `05`). Focus moves to
  the first item on open. ↑/↓ move, Home/End jump, Esc returns focus to the
  kebab, and Tab closes. The fix lives in the hook shared by `/portfolios`,
  `/securities`, `/transactions` and `/buckets`, so the test covers all four.
- **C4: #850**, the column-picker convergence on `.popover` (Sprint 14's board
  `03-column-picker`, pick E3). `ColumnPicker` moves out of the `Securities`
  namespace first. **First in the shrink order.**

### Lane D — the operator floor (two surfaces the records assumed, one document)

- **D1: #481, rescoped to position-level SOLL entry** (triage §2.1, pick F2).
  - Position rows sit inline under each category in the existing SOLL form:
    one save, one live Σ.
  - The category input becomes a read-only "Σ Positionen" once any position
    under it carries a target (ADR-0030 §2).
  - An empty position input means *no position target*, and a test pins it.
  - The Wealth page's hint that points at this page becomes true.
  - #481's two convenience slices close as not planned (D-3).
- **D2: #395, rescoped to its two open tasks** (triage §2.2, pick F3).
  - **The settlement fieldset** appears when the security and account
    currencies differ. Amount and rate derive each other, prefilled from the
    stored hub rate at the booking date.
  - **The guard the owner decided on 2026-07-19**: the cash amount equals the
    settlement amount, net of fees and taxes, within ADR-0016's tolerance.
  - **The guard is risk-tier** (a ledger invariant, ADR-0036). It gets its own
    commit, TDD with exact `Decimal` fixtures, a verification pass and a
    briefing callout. D-5 fixes when it runs.
- **D3: #354, backup and restore, documented and verified.** `pg_dump` /
  `pg_restore` for the shipped Compose setup, EN and DE, with the restore
  verification step the issue names: total value, holdings count and one
  position compared after restoring into a clean instance. The lane **runs
  the procedure itself** against the synthetic seed and records the commands
  it ran. `needs-uat` stays on the issue until the owner has run it once on
  their own instance. The PR says so rather than closing by keyword.

### Lane M — maintenance (always present)

- **Hex, npm, PostgreSQL, Elixir/OTP, BMAD and the external BMAD modules**
  are reviewed at lane time. What passes the gates is applied as its own
  commit. What does not is reported **with its reason** in
  `version-report-2026-09-XX-sprint15.md`, written before the closing act.
- **#727:** both triggers re-checked. The Sprint 14 lane's runtime advisory
  (CVE-2026-75758 in Elixir 1.18.3) is part of the input: if an official
  `1.18.5` image tag exists now, the patch bump is its own commit and does not
  wait for #727's minor move.
- **The Node runtime:** the Node 26 LTS promotion is due in **October 2026**.
  This sprint may or may not reach it. Check it at lane time either way.
- **The npm audit gate needs a look (D-7).**

### Lane Z — registry (small)

- **At branch opening:** file E24's tracker and its story issues (A1–A4)
  under area **#418**, and record the numbers on FR-43's coverage row.
- **Right after the merge, before the branch opens: the triage closures,
  by hand, with the reason** from `backlog-triage-2026-09-23.md` Part 3:
  - #340, #320, #332, #333 and #567 close;
  - #481 and #395 get a comment naming the rescope and are retitled;
  - skip any issue a comment on this PR kept open.
- **Registry edits already on this PR** (triage Part 4):
  - FR-27 and FR-42 retired;
  - FR-43 moved to ADR-0049;
  - FR-5's #333 marked closed;
  - the E8 Tracker Index line loses #320;
  - E24 added.
- **The close-out** reconciles against these rows and adds the dated
  reconciliation. That means ADR-0042's FR Coverage Map, Tracker Index and
  dated reconciliation, never a story row.

## Decisions

### D-1: one branch, rebased after #859 (recommended)

`agent/claude/policy-rules-and-the-operator-floor`, opened on `main` **after
PR #859 merges**, and rebased daily. This planning branch is stacked on #859's
commit only because both touch the same two registry files. Squash-merging a
stack mis-merges it, so this PR is rebased onto `main` the moment #859 lands
and is never merged ahead of it.

### D-2: ADR-0049 closes B3.6 (recommended)

The record is on this PR. Its asks table (ADR-0043) answers FR-43's list and
D-6's two questions. It defers `protected` and `budget` with a reason, since
both are predicates over *flows* and not over *state*. **The deferred flow
rules are filed as one issue by Lane Z at branch opening**, as ADR-0043
requires, so the deferral is visible to the next planning round.

**To flip this by comment:** "B3.6 not yet" removes ADR-0049 and Lane A from
this PR. Lanes B–D then fill the sprint, and the triage's runway moves by one
sprint.

### D-3: the backlog triage is adopted (recommended)

`backlog-triage-2026-09-23.md` answers the owner's three questions. Summary:
**15 buildable issues**, about **three sprints** of work worth doing
(Sprints 15–17), then maintenance. It recommends five closures, all by hand
with the reason:

| Issue | Closed because |
|---|---|
| #340 | an umbrella that says nothing in it is planned; every item already has a home or a "no" |
| #320 | superseded item by item (E23, #608, data notes) |
| #332 | its core is ladder level (d); its simple half is ADR-0027 + ADR-0046 |
| #333 | classifications are Portfolixir-owned, quote history has an API, and nothing left justifies a parser plus a hard-rule amendment |
| #567 | its only concrete recipe is private tooling; its generic half already lives in the tool descriptions |

It also records two rescopes (#481 to its entry surface, #395 to its two open
tasks) and two registry retirements (FR-27 with #332; FR-42, which is covered
by classifications, with the remainder out of scope).

**To flip any one by comment:** name the issue number, and Lane Z leaves it
open.

### D-4: three design picks, recommendation first (recommended)

| Pick | Item | Board | Options | Recommended |
|---|---|---|---|---|
| **F1** | The rules surface (A4) | `01-policy-rules-surface` | section on Risk · seventh tab · Risk + Overview card | **A** |
| **F2** | Position-SOLL entry (D1) | `02-position-soll-entry` | inline under each category · dialog per category | **A** |
| **F3** | Settlement inputs (D2) | `03-settlement-inputs` | shown when currencies differ · always present | **A** |

Same mechanism as Sprint 14's D-10: the recommendation is the default, a
comment naming another option changes it, and the story writes the picked
anatomy into `DESIGN.md`. #854, #857 and #858 have before/after boards (`04`,
`05`). #850 is held against Sprint 14's board `03-column-picker`.

### D-5: the settlement guard runs on writes that touch the amounts (recommended)

A validation added to a ledger changeset runs on every future write to a row.
If it ran unconditionally, **editing the note of an old cross-currency
booking** that predates the guard and misses it by a rounding step would
start failing. That would be a correctness rule turned into a data trap. So
the guard runs when `gross_amount`, `settlement_amount`, `fees`, `taxes` or
the type **change**, and on insert. Rows that already exist are not
revalidated behind the operator's back.

The lane adds a read-only check over the synthetic seed and documents, in the
PR, what the operator can run on their own instance to list rows that would
fail the guard. Rows are listed, never rewritten: repairing a historical
booking is the operator's decision (NFR-2).

### D-6: #849 stays open and is decided at Sprint 17's planning (recommended)

The conditional read for derived projections saves tokens, not risk, and
E24's findings read answers the question a scheduled run actually polls for:
did anything cross a line? It is decided with the agent's next report of how
it polls once rules exist. It may then close as not needed (triage §3.7).

### D-7: the npm audit gate is looked at, and never weakened (recommended)

CI 1558 on `d085572` (the Sprint 14 planning merge) went red in `quality`. The
Sprint 14 close-out (#859) records it as an advisory published after the
merge and fixed by the maintenance lane's SDK patch. **The failed log of that
run reads differently:**

> npm error audit endpoint returned an error

The same log also carries npm's notice that the endpoint it called "is being
retired" in favour of the bulk advisory endpoint. Both can be true. **Lane M
establishes which**:

- if the registry endpoint is being retired, move the gate to an npm version
  that uses the bulk endpoint;
- keep `--audit-level=high` unchanged. A gate that can go red because the
  registry changed an API is still a gate, and the fix is to make it read the
  right endpoint, never to make it optional (AGENTS.md: never weaken a gate).

### D-8: no tags outstanding (standing, corrected)

`0.11.0` to `0.14.0` all exist as tags and GitHub Releases:

- `0.11.0`, `0.12.0` and `0.13.0` were published 2026-09-20 at 11:19 UTC;
- `0.14.0` was published 2026-09-23 at 19:24 UTC, and the Release workflow
  ran on `c0746222`.

So Sprint 14's plan ("three outstanding, latest 0.10.0") was stale by the
time its PR merged. PR #859 ("four outstanding, latest still 0.10.0") read
the old record rather than the releases list, and was committed two minutes
before `0.14.0` went out. **The check that would have caught both is
`gh release list`**, and from this sprint on the close-out reads it before
writing a tag sentence. The Sprint 15 close-out prepares **`0.15.0`** and
nothing else.

### D-9: closing-act findings carry their reach (recommended, from the triage)

A finding filed by a closing act is labelled with one of two reaches:

- **user-reachable:** the operator or the agent hits it in normal use. In
  this sprint: #851, #854, #857, #858;
- **hostile-input only:** it takes a crafted request, such as a 20-digit id,
  a 490-codepoint URL or `offset=10^20`. In this sprint: #853, #855, #856.

Hostile-input findings still get fixed. Each fix removes a whole class, and
the error contract matters to an agent that cannot tell a bad request from a
broken server. But they ride a debt lane and **never set a sprint's theme on
their own**, and they are the first cut in a shrink order. The reason is
arithmetic (triage §1.1): at six to nine findings per batch, a backlog made
of the previous review's findings never ends.

### D-10: the closing act's conditions (standing, with the screenshot limit made explicit)

**The #706 conditions stand:** DE, one full pass at 390 px, light and dark, on
`priv/demo/finding_surfaces_seed.exs`, screenshots in a PR **comment**. The
seed is extended by the stories with rules in every state and position
targets in one category.

**Screenshot links.** Sprint 14's D-8 made reference-style links the
convention. Sprint 14's retrospective (in #859) found that the convention
also needs a length limit: a URL past roughly 145 characters was wrapped in a
code span again, and short file names fixed it. **Standing from here:** every
image URL in a screenshot comment stays under ~140 characters, and the author
reads the posted comment back before treating it as delivered.

**Four roles**, as in Sprint 14:

- the correctness hunter;
- the edge-case hunter;
- a UAT persona walkthrough on seeded synthetic data;
- the design critic against each board and the spec.

Every finding is reproduced before it is surfaced and carries its D-9 reach
label.

**Mutation-verified passes:**

- ADR-0049's two invariants: undetermined never passes; a version in force is
  immutable and versions never overlap;
- D2's settlement guard;
- B1's union radius.

Each assertion is shown red against a deliberately broken implementation
before it is trusted green. **The patch-coverage listing is read from the
last pre-promotion CI run.**

## Sequencing

```text
after the merge ── Lane Z: triage closures by hand; #859 merged first
branch opens on main ──▶ Lane Z files E24 + the flow-rules deferral
Lane A1 ─── tables, versions, journal, writes; the two §4 invariants first
Lane A2 ─── engine + findings read + no-action meta-test, after A1
Lane A3 ─── 409s, re-import guarantee, contract bump, after A2
Lane C1 ─── #854 first (it touches risk_live.ex before A4 does)
Lane A4 ─── the rules section on Risk (F1), after A2 and C1
Lane B ──── in parallel: controllers, live id parsing, the invalidation seam
Lane C2–C4 ─ in parallel: app.css, area tabs, row-menu hook, column picker
Lane D1 ─── classifications_live.ex, independent
Lane D2 ─── transaction.ex (risk-tier guard first), then the form (F3)
Lane D3 ─── docs, independent, any time
Lane M ──── at lane time; the version report before the closing act
closing act ─ D-10, the mutation passes, promotion
```

## Shrink order (cut from the bottom, name the cut in the briefing)

1. **#850** (the column-picker convergence) moves to Sprint 16. Two working
   pickers that look different are a spec drift, not a broken function.
2. **#853, #855, #856** (hostile input, D-9) move to Sprint 16's debt lane.
3. **#354** (backup/restore docs) moves to Sprint 16. It has waited since
   June, and one more sprint changes nothing. It is the first thing Sprint 16
   does.
4. **A4** (the rules surface) moves to Sprint 16, with the two-way deadline
   recorded in the close-out, which is the rule working as intended.

**What does not shrink:**

- **A1–A3** are the gate's build.
- **D1 and D2** are the operator floor this sprint exists to pay.
- **#851** is a stale answer an operator can get in normal use.
- **#857, #858 and #854** are the accessibility floor and one CSS rule.

## What is deliberately not in this sprint

- **Flow rules** (`protected`, `budget`), **rules over events**, **the lens
  defaulting its caps from rules**, and **historical findings**: ADR-0049 §11,
  each with its reason. Flow rules are filed at branch opening.
- **B3.5** (the rebalancing digest) and **B3.7** (push delivery) stay shut,
  and ADR-0049 §10 names how.
- **#328 / #608**, the lifecycle merges: Sprint 16, under **one** ADR that
  covers both, because reassignment and import idempotency are the same risk
  twice (triage Part 1).
- **FR-41** (contribution analysis) is Sprint 16's decision and Sprint 17's
  build. It is checked against ADR-0041 first, because it may be a thin
  extension.
- **B4.2** (predictions and calibration): Sprint 17, if the agent's next
  round confirms it will record predictions.
- **NFR-9 backstops**, **#330's discovery story** and **#573**: Sprint 16.
- **#314** rides this batch as every batch does. **#727** is Lane M's.

## What "done" means for this sprint

1. **E24 ships in both directions.**
   - The rules object with its versions and writes is on API and MCP.
   - The findings read carries `status=` and a `computation_basis` per
     finding.
   - The no-action meta-test is green.
   - Rules survive a re-import, and that is pinned.
   - The 409s name the rules.
   - The contract takes one bump.
   - The human view renders in the F1 pick, matches its board, and its
     anatomy is in `DESIGN.md`. **Or** the close-out names the shrink and the
     Sprint 16 deadline.
2. **ADR-0049's two invariants are pinned and mutation-verified:** undetermined
   never passes; a version in force is immutable and versions never overlap.
3. **The operator can do what only the agent could.**
   - Position targets are enterable on Classifications (F2).
   - A cross-currency buy is bookable in the form (F3).
   - The settlement guard is live on writes that touch the amounts (D-5),
     mutation-verified.
   - #481 and #395 close by keyword on their rescoped content.
4. **#851's radius is the union of both images**, held against the widening
   invariant.
5. **#854, #857 and #858 ship and each matches its board.** #857 does not
   move the active tab under the mask.
6. **The triage closures are done by hand** with their reasons, and the
   registry matches Part 4.
7. **Lane M's report exists** before the closing act. The npm audit gate reads
   an endpoint that answers (D-7). #727's triggers and the Node LTS date are
   recorded either way.
8. **The closing act ran under D-10.** Every finding carries a reach label,
   and the patch-coverage listing was read before promotion.
9. **The `0.15.0` command is in the close-out**, and it is the only one.
