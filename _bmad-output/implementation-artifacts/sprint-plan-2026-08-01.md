# Sprint Plan — 2026-08-01

Companion to `sprint-status.yaml`. That file tracks epic/story state; this one
sequences the open GitHub issues, which is where the actual work lives for
epics 1–5 and 7–16 (they carry no story breakdown — their unit is the issue,
per the FR Coverage Map in `epics.md`).

Ground truth: `main` at `ba6a046`, verified against the merge commit, the
closed-issue list **and** the open-PR list (empty; re-checked 2026-08-01 —
**40 open issues, 0 open pull requests**, so no issue-lags-PR cases exist
today). Supersedes `sprint-plan-2026-07-31.md`.

## What Sprint 2 delivered

Everything it set out to, and it closed itself out properly:

- **Gate.** ADR-0033 drafted, reviewed and **accepted**: per-position P&L is
  decomposed into a price-return and a currency-return component over a
  security-currency cost basis (Option A). This unblocks `#569` and `#620`.
- **Lane A — `#398` truthful valuation.** `#406` (the "no price" warning
  distinguishes two honest states, detail and totals unified on the same
  price-resolution semantics) and `#570` (negative holdings flagged per depot
  and total, linked to the security's transactions) merged as the
  owner-approved combined PR `#629`. Tracker `#398` closed.
- **Lane B — `#619` measured.** The measurement report
  (`619-dashboard-mount-measurement-2026-07-31.md`) is in; no code changed,
  by design. Finding: valuation-shaped work is ~92 % of the post-#562 async
  block — one mount prices holdings six times. The optimisation decision is
  explicitly downstream and is **not** made by this plan either.
- **Lane C — planning debt cleared.** The epic-structure reconciliation
  (`epic-structure-reconciliation-2026-07-31.md`) mapped all open issues,
  proposed homes for the unattached pile, and produced the analytics-wishlist
  ranking this plan consumes below.
- **Close-out.** Bookkeeping ran in the same pass as the merge — first time
  with zero carried reconciliation debt — and the commit-authorship gate ran
  **green** on `ba6a046`, the first squash-merge after fix `ee51260`.

## Constraint that shapes this sprint

Still one reviewer, and this sprint is heavier on risk-tier work than the
last: `#569`, `#620` and `#577` are all ledger/money math, and ADR-0026 says
each ships as a **dedicated small PR with real human review**, never inside a
batch. Three risk-tier PRs plus one large cross-cutting batch do not review in
parallel through one person. The sequencing below therefore runs the batch
first and alone, then feeds the risk-tier PRs through one at a time. Drafting
can overlap; review does not.

## Sprint 3 — "Say it plainly, then decompose it"

### Lane A — `#606` microcopy voice sweep, its own epic batch

The sweep applies the owner's microcopy rule (2026-07-23: impersonal, terse,
self-explanatory; du never Sie where address is unavoidable; explanation in
ⓘ tooltips per UX-DR11, not in the sightline) retroactively across all
existing UI and docs. It was deliberately moved out of Sprint 2 — fixing the
numbers came first — and both number-fixing items (`#406`, `#570`) have now
landed, so the sweep no longer polishes wrong surfaces.

Batch mechanics per ADR-0026:

- **Decision gate:** already satisfied. The owner rule of 2026-07-23 plus
  UX-DR11/UX-DR13 in the design spec *are* the reviewed standard — the rule is
  review-blocking for new strings today; this batch applies it to old ones.
  No new ADR needed. (Assumption stated rather than silently made: if the
  owner wants a written sweep spec first, that is a one-pager, not a blocker.)
- **One epic branch** (`agent/<provider>/microcopy-voice-sweep`), commits
  grouped per surface (view/dialog/docs page), every commit passing the local
  gates. Gettext hygiene applies throughout: `mix gettext.extract --merge`,
  full `de` translations, `localization_test.exs` green — a sweep that leaves
  fuzzy entries has not finished.
- **Not risk-tier** — strings and docs, no ledger/money math — so the batch
  form is correct. But it is large and cross-cutting, so the closing act's
  UAT persona walkthrough matters more than usual: read the app end to end in
  both locales, screenshots in the reviewer briefing.
- Proposed home `#356`/E11 (per the reconciliation §2); attaching it is a
  one-click owner action, not a dependency.

### Lane B — the ADR-0033 pair, risk-tier, strictly sequenced

1. **`#569` implementation.** Decompose per-position P&L into price return
   and currency return per accepted ADR-0033 Option A: cost basis in the
   security's currency, both components explained on the surface, portfolio
   totals still reconciling. Dedicated small PR, real human review, exact
   Decimal expectations in tests.
2. **`#620`** — show which FIFO lots a sale consumes, where the sale is
   decided. Sequenced behind `#569` because the two touch the same
   per-position surface and `#620` wants the decomposition's vocabulary
   already in place. Also risk-tier, also its own PR.

Both were explicitly parked in Sprint 2 pending the gate; the gate is
cleared, nothing else blocks them.

### Lane C — the triaged analytics wishlist, in the reconciliation's order

Lane C of Sprint 2 produced the ranking (reconciliation §3, applying the
`#321` owner priority: correctness first, LLM-first consumption second, UI
third). This plan adopts it verbatim:

1. **`#577` — cross-portfolio performance walk.** The only wishlist item
   where a shipped surface shows a *wrong* number (TTWROR/IRR silently covers
   one portfolio next to a total covering all). Risk-tier, dedicated small
   PR — it joins the Lane B queue behind `#620` for review capacity.
2. **`#568` — money-weighted metrics.** Starts with the short design session
   its own body requires; the session is a Sprint 3 deliverable even if the
   implementation spills.
3. **`#572` — benchmark comparison.** Explicitly after `#568` (reuses its
   external-flow definitions); its data-source decision (index proxies vs.
   CPI) needs the owner anyway. Realistically Sprint 4.
4. **`#563` — period picker.** Cheap, `agentic`, unblocked — batch filler at
   any point.
5. **`#564`** stays in the UAT pile — owner time, not agent time.

**Capacity honesty:** the committed core of this sprint is Lane A plus
`#569` + `#620`. `#577` is next in the review queue if capacity allows;
`#568`'s design session fits regardless because it costs no review;
everything below that is stretch, and saying so now beats re-planning later.

## Decisions needed, not code

- **`#619` follow-on.** The measurement is done and constrains three options
  (extend ADR-0032-style memoisation to valuation; share one pricing pass
  across the six per-mount valuations; split the async block so cheap
  sections paint ~380 ms earlier). Any of them is a separate reviewed
  decision — the first two touch valuation semantics and would be risk-tier.
  Owner call whether Sprint 3 review capacity goes here or the issue waits;
  this plan does not spend the capacity, it is already allocated above.
- **Structural proposal from the reconciliation (§2).** Attach the unattached
  issues to their proposed trackers and cross-reference `epics.md` ↔ tracker
  set; decide the closable candidates (`#419`, `#321`, `#470`). Owner clicks,
  no agent code. Doing the `#418` attachments before Lane C starts would make
  the wishlist's bookkeeping mechanical.
- **`#610`** — unchanged for the third plan running: worth doing only if
  delisted or feed-dropped holdings occur in practice. Owner call, risk-tier
  when it happens.
- **UAT pile** (`needs-uat`, owner time): `#328`, `#330`, `#332`, `#333`,
  `#354`, `#412`, `#564`, plus the 19.6 tax entry surface per the E17–E19
  retro's action item 5. Listed so the sprint stays honest about what is
  actually waiting on whom.

## Explicitly out of this sprint

- **`#608`** (merge and repair securities) — still sequenced behind `#328`'s
  UAT precedent, which is still in the pile.
- **`#619` optimisation** — until its decision is made (see above).
- **`#481`** (position-first SOLL) and **`#471`** (portfolio selector,
  pending its ADR-0024 re-cut) — parked, by earlier decisions.
- **19.7** and everything under E4/E8/E9/E10 — gated by design; not planned.

## Sprint 4 preview

1. The analytics wishlist tail in ranked order: `#572` after `#568`, `#563`/
   `#564` as filler.
2. The `#619` decision's implementation, if the owner opens that gate.
3. Whatever the UAT pile releases — `#328` first would also unblock `#608`.

## Standing findings

1. **Planning artifacts drift silently — countermeasure holding.** The
   same-pass close-out has now run clean twice (Sprint 1 bookkeeping on
   2026-07-31, Sprint 2 on 2026-08-01). Keep it in the closing act; the
   finding stays listed until it has held across a full multi-PR sprint —
   this one, with its batch plus serialized risk-tier PRs, is the real test.
2. **An issue's state lags its PR.** No instance today (0 open PRs, verified
   2026-08-01). The rule stands: plan from open PRs and merge commits on
   `main`, never issue state alone.
3. **Two parallel epic structures.** No longer archaeology — the
   reconciliation mapped every issue and proposed the end-state — but still
   undecided. It graduates from standing finding to closed the day the owner
   applies (or rejects) the §2 structural proposal.
