# Sprint Plan — 2026-07-31

Companion to `sprint-status.yaml`. That file tracks epic/story state; this one
sequences the open GitHub issues, which is where the actual work lives for
epics 1–5 and 7–16 (they carry no story breakdown — their unit is the issue,
per the FR Coverage Map in `epics.md`).

Ground truth: `main` at `02dde3b`, verified against the merge commit, the
closed-issue list **and** the open-PR list (empty). Supersedes
`sprint-plan-2026-07-25.md`.

## What Sprint 1 delivered

All three lanes landed, not only the epic batch:

- **Lane A — Epic 19.** Stories 19.2–19.6 (`#621`–`#625`): year-scoped
  `tax_parameters` with German history seeded 2009–2026, effective-dated
  `tax_profiles`, `allowance_orders`, the `tax_statement_snapshots` table with
  its eleven Decimal columns, the pure consistency engine (C1–C8, tolerance
  band `max(1.00, 0.05 %)`), API/MCP parity, entry surface, EN/DE docs.
  ADR-0031 flipped to *Accepted*; `Portfolixir.Tax` amended into the AGENTS.md
  Active Architecture.
- **Lane B — review debt.** `#607` and `#609` closed.
- **Lane C — `#562`.** The memoized daily walk, with **ADR-0032** written,
  reviewed and accepted along the way (warm-up, targeted invalidation,
  labelled stale-while-revalidate). Two follow-ups opened deliberately before
  measuring: `#619` and `#620`.

Bookkeeping cleared on 2026-07-31: `#338` and `#603` closed (E17/E18 complete),
`sprint-status.yaml` and `epics.md` reconciled with `main`.

## The disagreement this plan has to settle

The previous plan's Sprint 2 preview led with **`#606`** (microcopy voice
sweep). I am not sequencing it first, and the reason is worth stating rather
than quietly reordering.

`#398` is the owner's own tracker titled *"Truthful valuation & allocation:
surfaces that agree and explain themselves"*. Its open child `#406` is a
warning that contradicts what the next screen shows: the portfolio totals use a
portfolio-scoped trade-price fallback **and** require an FX path to the base
currency, while the security detail uses the global fallback and the native
price. The same position is therefore "missing, has no price at all" on one
surface and priced on another. `#569` is the same family: per-position P&L
folds purchase-date FX into what the UI calls performance. `#570` is import
debris — impossible negative quantities flowing silently into holdings,
allocation and valuation.

A microcopy sweep makes wrong numbers read more nicely. Fixing the numbers is
worth more, and it is what the owner priority in `#321` (data completeness and
correctness first) actually asks for. `#606` is genuinely large and
cross-cutting, it is UI priority 3, and running it immediately after a big
tax-surface merge would compete for exactly the scarce resource named below.
It moves to Sprint 3.

## Constraint that shapes this sprint

One reviewer. ADR-0026 makes it explicit, and risk-tier changes — ledger/money
math, security, dependencies, import idempotency, projection semantics — ship
as **dedicated small PRs with real human review**, never inside a batch. Two of
this sprint's three candidate items are money-domain math, so the sequencing
below front-loads the decisions and keeps the batch small.

## Sprint 2 — "Make the surfaces agree"

### Gate first — `#569`, decision only, no code

The P&L decomposition needs an ADR before anything is implemented. Two options
are on the table and they are not equivalent: separate the FX contribution
(price return vs. currency return per position), or compute cost basis in the
quote currency and convert both sides consistently. Whichever wins must keep
portfolio totals reconciling and must be explained on the surface.

This is money-domain math and therefore risk-tier. It also blocks nothing else
in the sprint, so it can be drafted while lane A runs.

**Owner action:** sign off the decision, as with `#612` for Epic 19.

### Lane A — `#398` truthful valuation, one epic branch

1. **`#406`** — the "no price" warning tells the truth, and detail and totals
   reconcile. This is a decision about valuation behaviour before it is code:
   does a position with a resolvable native price but no FX path count as
   valued, and if not, what does the warning say instead? Risk-tier by
   proximity to valuation; ships as its own PR.
2. **`#570`** — flag negative holdings from unmodeled corporate actions. The
   data-quality report lists them per depot and total, and they are visibly
   marked on allocation/valuation instead of blending in.

   **Rescope needed:** its second acceptance criterion points at `#338` for
   repair wizards, and `#338` closed with E17 complete — ADR-0028 draws the
   boundary at splits. The criterion becomes "links to the security's
   transactions", not "offers a repair wizard". Confirm before starting.

Once `#406` and `#570` land, `#398` closes.

### Lane B — `#619`, measure before optimising

`#562` has landed, so the baseline is finally the right one. The issue exists
precisely so the finding was not lost, and it is explicitly **not**
pre-diagnosed: `dashboard_live.ex` computes four things in one async block on
mount, ADR-0032 addressed one of them. Step one is measuring which of the
remaining three dominates a cold mount. Only then does anyone decide whether
the answer is the same memoisation, a narrower query, or a different page
composition.

Cheap, unblocked, and best done now while the ADR-0032 context is still warm —
the same reasoning that put `#562` in Sprint 1.

### Lane C — planning debt, no code

The epic-structure reconciliation, carried unaddressed since 2026-07-25:
`epics.md` defines E1–E19 while GitHub carries a separate tracker set (`#416`,
`#417`, `#418`, `#419`, `#420`, `#470`, `#398`, `#356`), and roughly twenty
open issues hang off neither. `#321` (roadmap index) indexes mostly-closed
issues. One pass makes future sprint planning mechanical instead of
archaeological. It costs no review capacity and it is the reason this status
check took an afternoon instead of ten minutes.

## Decisions needed, not code

- **Commit-authorship gate red on `main` since 2026-07-24.** A squash-merge
  through the GitHub UI sets the *committer* to `GitHub <noreply@github.com>`,
  which `scripts/check-commit-authorship.sh` rejects. Every commit's **author**
  is correct; only the merge committer is not. ADR-0026 prescribes owner
  squash-merge, so policy and enforcement contradict each other by
  construction. Either the check exempts GitHub's merge committer explicitly
  (author-only rule for merge commits) or merges move local. A permanently red
  gate trains everyone to ignore it, which is worse than either fix.
- **`#610`** — unchanged from the last plan. The `B_d` gate emits a basis step
  only for a security carrying no quote from any earlier day; a security that
  *was* quoted and later loses its feed keeps booking trade-price re-pricings
  as return. Closing it needs a staleness rule and risks re-classifying
  legitimate off-quote days. Worth doing only if delisted or feed-dropped
  holdings actually occur in practice — an owner call, and risk-tier when it
  happens.
- **Analytics wishlist has no owning epic.** `#563`, `#564`, `#568`, `#572`,
  `#577` accumulated without one. They need a single prioritisation pass before
  any of them starts; folding it into the Lane C reconciliation is the cheap
  way to do it.
- **No retrospective has been run for E17, E18 or E19.** All three sit at
  `optional` in `sprint-status.yaml`. ADR-0026 names the closing act as
  mandatory; the retro is the part that never gets asked for. One combined
  session over three consecutive epic batches would be more useful than three
  separate ones, and it is the natural moment — the batch cadence itself is now
  the thing worth reviewing.
- **UAT pile** (`needs-uat`): `#328`, `#330`, `#332`, `#333`, `#354`, `#412`,
  `#564`. Owner time, not development capacity; listed so the sprint stays
  honest about what is actually waiting.

## Explicitly out of this sprint

- **`#606`** microcopy voice sweep — Sprint 3, as its own batch.
- **`#620`** (which FIFO lots a sale consumes) — real, but it wants the `#569`
  decomposition decision settled first; the two touch the same surface.
- **`#608`** (merge and repair securities) — the analogue of `#328`, which is
  itself still in the UAT pile. Sequence it behind its own precedent.
- **19.7** and everything under E4/E8/E9/E10 — gated by design.

## Sprint 3 preview

1. **`#606`** microcopy sweep as its own epic batch.
2. **`#569` implementation**, once its ADR is signed off, followed by `#620`.
3. **The triaged analytics wishlist**, in whatever order Lane C's
   prioritisation pass produces.

## Addendum — same day, after the owner's go

Three of the "decisions needed" above were resolved on 2026-07-31:

- **Authorship gate:** fixed (`ee51260`) — GitHub's web-flow merge committer
  is accepted for the committer role only, and only when the author is
  allowlisted. Goes green with the next squash-merge to `main`; watch that
  first run.
- **`#570` rescope:** confirmed and recorded in the issue body — the
  data-quality item links to the security's transactions; repair wizards
  beyond splits stay gated behind ADR-0028.
- **Retrospective:** the combined E17–E19 session ran — see
  `epic-17-18-19-retro-2026-07-31.md`. Its action items extend the closing
  act with a bookkeeping close-out (AGENTS.md amendment) and codify the
  check-PRs-not-issues planning rule.

Still genuinely open for the owner: the `#569` ADR sign-off (the Sprint 2
gate), `#610`, and the UAT pile — now including the tax entry surface (19.6)
per the retro's action item 5.

## Standing findings

1. **Planning artifacts drift silently.** `sprint-status.yaml` sat at "awaiting
   review" for two days after the work merged, and `epics.md` called Epic 19
   gated after its ADR was accepted and its five stories had shipped. Nothing
   catches this — the sprint-status update is the last step of a batch and the
   easiest one to skip. Making it part of the closing act, next to the reviewer
   briefing, would cost nothing.
2. **An issue's state lags its PR.** Carried forward from the last plan and
   still true: `#607` and `#609` stayed open for two days after their fixes
   merged. Check open pull requests when planning, never issue state alone.
3. **Two parallel epic structures.** See Lane C. Unchanged since 2026-07-25 and
   now slightly worse — `#619` and `#620` joined the unattached pile.

## Addendum 2 — 2026-07-31, evening: gate cleared, Lane A decisions made

The Sprint 2 gate and the Lane A behaviour questions were resolved by owner
sign-off; recorded here so the implementation session inherits decisions, not
open questions:

- **ADR-0033 accepted** (the `#569` gate): per-position P&L is decomposed into
  a price-return and a currency-return component over a security-currency cost
  basis, Option A. This unblocks the `#569` implementation and `#620` — both
  remain Sprint 3, each risk-tier.
- **`#406` behaviour decided:** a position with a resolvable native price but
  no stored FX path to the base currency counts as **not valued** in
  base-currency totals; the warning distinguishes two honest states ("no price
  at all" vs. "price available, no exchange rate to EUR stored"); totals and
  security detail unify on the same price-resolution semantics (global
  trade-price fallback on both surfaces).
- **Delivery decision:** the remaining Sprint 2 code — `#406` + `#570` — ships
  as **one combined PR** (owner override of the risk-tier separation for this
  pair; the `#406` part gets focused review). `#398` closes with that PR.
- Lane B (`#619`) is measured, Lane C is delivered, and the analysis package
  (ADR, measurement report, reconciliation) is on PR `#627`.

## Addendum 3 — 2026-08-01: Lane A merged; bookkeeping close-out and mini-retro

Sprint 2's remaining code landed: `#406` + `#570` merged as the combined
PR `#629` (`ba6a046`) after the mandatory UAT persona walkthrough (screenshots
under `uat-sprint2-lane-a-2026-08-01/`). Close-out per the closing act:

- `#406` and `#570` closed with the merge; tracker `#398` closed — both
  sub-issues complete, as this plan's Lane A predicted.
- `sprint-status.yaml` and `epics.md` reconciled with `main` at `ba6a046`
  **same-day**, addressing standing finding 1 (planning artifacts drift
  silently) instead of re-observing it.
- CI on the merge is green **including the commit-authorship gate** — this
  was the first squash-merge after fix `ee51260`, the run this plan said to
  watch. The gate's policy-vs-enforcement contradiction is resolved.

Mini-retro for the batch (short, per the E17–E19 retro's cadence):

- **Worked:** front-loading the decisions (gate ADR, `#406` behaviour,
  delivery override) in Addendum 2 meant the implementation session started
  with zero open questions; the combined-PR override kept one reviewer's load
  bounded while the `#406` part still got focused review.
- **Worked:** running the close-out in the same pass as the merge — the first
  time since the rule was written that no reconciliation debt was carried.
- **Carry forward:** Sprint 3 sequence stands as previewed — `#606` as its
  own batch, then the `#569` implementation followed by `#620` (both
  risk-tier, now unblocked by ADR-0033), then the triaged analytics wishlist.
- **Still with the owner:** `#610` and the UAT pile (`#328`, `#330`, `#332`,
  `#333`, `#354`, `#412`, `#564`, plus the 19.6 tax entry surface).
