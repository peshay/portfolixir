# Sprint 9 — the knowledge batch, and the debt the agent round left behind

**Status: ADOPTED 2026-09-03** — owner sign-off on the draft PR (#753,
"passt"), which per this plan's own terms covers the adoption AND signs
**D-1** (the fix shape for #737, below) as recommended. No lane is gated.
Written the day ADR-0044 was signed (4c4cc9e). Verification basis: the merge
commits on `main` since the Sprint 8 close-out (02fa716..4c4cc9e — triage,
ADR-0044 draft and signature, registry catch-up), CI run 1460 on `main`'s head, the open-issue list before
this plan filed anything (28 open), the open pull requests (four Dependabot
PRs, no batch PR — the stop-sign check the Sprint 8 retro prescribed came back
clear), the tag list (0.8.0 **annotated** on ea6617a, the first annotated
sprint tag; release 0.8.0 published 2026-09-03), and the migrations in
`priv/repo/migrations` for the journal-arming claim below.

## State of play, in four lines

1. **`main` is red as of today.** Run 1460 on 4c4cc9e fails at "Audit MCP
   server dependencies (npm)": four high advisories on the transitive
   `fast-uri` plus two moderate on `qs`, new since the green run of
   2026-08-28. Not a regression in the tree; an advisory feed moved. The
   lockfile-only fix is the first commit of this PR (see Lane M), so no PR
   after it inherits a red base.
2. **Gate B4.1 is closed and unscheduled.** ADR-0044 was signed today with
   three clauses named for a deliberate yes: entries never vanish, the table
   is journaled from its first migration, the human timeline lands in the
   same batch. The signature says explicitly that scheduling is a separate
   decision. This plan is that decision.
3. **The agent round left two close-out findings and one decision.** #740
   (FR-37's parameters skipped the view-scoped reads) and #741 (the re-import
   guarantee exists only as a test) are bookkeeping by the triage's own
   ruling; #737 (no path to store a historical FX rate) is what keeps the
   Sprint 8 Realized-gains facet honest but incomplete, and it needs a fix
   shape chosen, not code.
4. **Nothing else is due.** The two-way-coverage ledger is empty (Sprint 8
   discharged it and added no new debt); no human-view deadline falls in
   this batch except the one ADR-0044 §6 sets for itself.

## Why this cut

- **The signed gate goes first because a signed gate that waits gets
  re-litigated.** Sprint 8 said this about the #707 spec and it held. ADR-0044
  is the first new object family since the tax snapshots, the agent nominated
  it as the single largest improvement it could name, and the identity gate
  already settled the principle. The batch is the ADR's scope, no more.
- **The agent-round debt rides along because it is small and it is
  overdue by the rule that shipped FR-37.** #740 is two parameters on two
  reads, both halves; #741 is a documentation pass; #738 (README predates
  Snapshots, Tax, performance) is the same shape from the Sprint 8 close-out.
  Together they are a day, and they are what the agent's next requirements
  edition would otherwise carry a third time.
- **#737 gets a decision on this plan, not a lane that discovers one.** The
  issue asks which of two fix shapes to build. D-1 below picks, with the
  reason, so the lane can start red-test-first the way Lane C did in Sprint
  8 under its D-1.
- **The toolchain stays where it is.** #727's both halves are blocked upstream
  with evidence and re-check triggers on the issue; Lane M re-checks the
  triggers and reports, nothing more.

## Lanes

### Lane A — the knowledge batch (ADR-0044; tracker #747)

The issues were filed by this plan as the work ledger under the tracker, each
a thin pointer to its ADR section. Order is the dependency order:

1. **#748 — the `security_notes` table and context, journal-armed at
   creation** (§§1–5). Append-only enforced at the database like
   `audit_journal` is, not only in the context; `kind` and `source_quality`
   fixed sets via `String.to_existing_atom/1`; `as_of` distinct from the
   write time; `supersedes`, `valid_until`; `author` plus the
   `machine_generated` marker with its source. Extends the re-import
   preservation test so the log is shown to survive a re-applied export —
   the guarantee #741 documents, pinned for the new table.
   **Risk-tier attention label** (ADR-0036): an agent write path and an
   append-only invariant. The closing act verifies the invariant.
2. **#749 — the thesis state as a projection over the log** (§1, the B4.1
   fields: thesis and status, conviction tier, invalidation condition, time
   stop, last reviewed and by whom), computed from `thesis` entries and what
   supersedes or retracts them, carried in the security read and naming the
   entry it derives from.
3. **#750 — API and MCP: append, and the four reads** (§7). Both halves with
   the same parameters; no update, no delete endpoint by §3.
4. **#751 — the research timeline on the security detail pane** (§6, a
   signed clause). A second-level tab per `EXPERIENCE.md`; newest first; kind
   and source quality visible; superseded shown as superseded; retractions
   legible; the operator can append from the pane.
5. **#752 — the contract-version read** (§8). A code-maintained manifest
   served under `/api/v1` and as an MCP tool, with a meta-test tying the
   route and tool inventory to it so a surface change without a manifest
   entry fails the build. **Lands last**, so its first entry records this
   batch's own additions — including #740's two parameters.

**One verified correction to the ADR's context, recorded here rather than by
editing a signed document.** §5 says the journal rollout covers "Catalog, FX,
targets and tax" and not "Portfolios/Classifications, Ledger and Imports".
The migrations say otherwise: guard-armed today are `securities`,
`security_identifier_aliases`, `buckets`, `portfolios`, the cash and
securities accounts, `transactions`, the classification tables and
assignments, the target tables, the tax tables and tax snapshots; the only
exempt tables are `security_quotes` and `exchange_rates`, by the allowlist
that a meta-test lets shrink and never grow. FX is *not* journaled, by
design. So the §5 dependency costs exactly one migration — the one #748
writes — and the batch inherits no journal debt. The reviewer briefing states
this so nobody re-derives it.

### Lane B — the agent-round debt (small, no gate)

- **#740 — `include_positions` on the view-scoped valuation, and a drift
  threshold on the position-target listing**, API and MCP together, the
  threshold spelled like `allocation_controller.ex`'s `min_drift` (a
  non-negative `Decimal` string), never a second spelling.
- **#741 — the re-import preservation guarantee, documented where an agent
  and an operator read**: the import section of `docs/integration/api-and-mcp.md`
  and the user-facing import documentation, naming what survives, what a
  re-import does, and the one thing not covered. Extended by #748 to name the
  research log.
- **#738 — the README's "What works today"** brought level with
  `docs/product-documentation.md`; do not reword a numbered step
  (`workflow_docs_test.exs`).

### Lane C — the historical FX gap (#737; D-1 below)

The Sprint 8 facets exclude and name a sale whose booking date has no stored
rate, and the exclusion notice deliberately carries no call to action because
the only sync there is fetches the daily feed. D-1 (signed) picks the fix
shape. The lane: the historical ECB series as a one-shot backfill through the existing
`Fx.RateSync` path, on demand from the existing sync endpoint and button,
fake provider in tests, no network. Acceptance: on the Sprint 8 D-1 fixture
(a USD sale whose close date has no stored rate) the facet's `excluded.count`
goes from 1 to 0 after the backfill and the converted total is exact
`Decimal`; the exclusion notice regains a live control pointing at the
backfill (UX-DR25's no-dead-control clause, which is why the Sprint 8 control
was removed). The facet's basis statement in API, MCP and tooltip stays
"exact booking-date rate" — the backfill fills dates, it does not change the
rule.

### Lane M — maintenance (always present; first act already done)

- **The npm audit finding — done in this PR's first commit**, lockfile only,
  five transitive packages within their declared ranges, 0 vulnerabilities,
  MCP tests 73/73, build clean. Its own commit per ADR-0036; it rides the
  planning PR only because the session is bound to one branch and a red
  `main` blocks every PR after it.
- **Dependabot #742 (`actions/setup-node` 5 → 7), #743 (`telemetry_metrics`
  1.2.0), #745 (`phoenix` 1.8.13):** review and apply inside the batch as
  their own commits if the gates pass; #742 must keep the four-place Node 24
  pin invariant test green. Close the bot PRs with a pointer once the commits
  are on the branch.
- **Dependabot #744 (`@types/node` 24 → 26):** the Sprint 8 decision stands —
  types follow the pinned runtime — and the bot reopened it for 26.3.0, so
  the earlier ignore covered one version, not the major. Close it with a
  major-wide ignore and say so on the PR.
- **#727 re-check triggers only:** an excoveralls release naming Elixir 1.20
  cover support; an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet`
  opaqueness. Report the check either way. No bump lands in this batch unless
  a trigger fired — and then as its own commit group with CI, not a local
  run, as the evidence.
- **Report written when the lane runs**, `version-report-2026-09-XX.md`,
  regenerated from `scripts/version-report.sh`; the tea/cis/bmb rows keep
  their Sprint 8 reasoning restated, not cross-referenced.

### Lane Z — structural (small)

- **E20 in the registry.** When the batch branch opens, one Tracker Index
  line in `epics.md` for E20 (name, tracker #747, intent) and an `epic-20`
  key in `sprint-status.yaml`; the FR-45 row gains the issue numbers. The
  close-out then has a row to reconcile against instead of inventing one.
- **The surface check, as one sentence in the close-out.** The triage's
  recommendation from §0.3: when a read-ergonomics parameter lands, the
  close-out names every endpoint of that family and states which carry it.
  Lands in AGENTS.md step 5 as a clause, not a new step (the numbering is
  shared state with three other documents). #740 is the first use.

## D-1 — the fix shape for #737 — SIGNED 2026-09-03 (owner, on PR #753)

**Fetch the historical ECB series (`eurofxref-hist.xml`) as a one-shot,
on-demand backfill through the existing rate-sync path; no manual dated-rate
entry in v1.** Three reasons, in order of weight:

1. **It is acquisition the scope already permits.** The gated set is "data
   acquisition beyond quotes and FX" (AGENTS.md, B3.3); this is FX, from the
   provider the hub is already defined against (ADR-0007, ECB semantics). No
   gate opens.
2. **It fills every past date at once, which is what the gap is.** A manual
   entry closes one date per write and reintroduces the "converted at a
   neighbouring date's rate" temptation that D-1 of Sprint 8 ruled out; a
   series fetch closes the class of gap.
3. **A manual rate write is a different kind of object.** `exchange_rates`
   is exempt from the audit journal as machine-refreshed operational data;
   an operator-typed rate is an authored financial value and would have to
   be journaled, which shrinks the allowlist and changes the table's
   classification. That may be right one day; it is a decision of its own,
   and it should not ride in on a backfill. Deferred, filed only if asked
   for.

Rate-availability behaviour after the backfill is unchanged: a booking date
still absent from the series (a weekend, a currency the ECB does not publish)
stays **excluded and named**, exactly as the Sprint 8 D-1 requires.

## Sequencing

```
Lane M: npm audit fix ── landed in this PR, before anything else
Lane A: #748 ──▶ #749 ──▶ (#750, #751 independent) ──▶ #752 last
Lane B: #740, #741, #738 ── independent, any time after #748 for #741's log row
Lane C: D-1 signed ──▶ #737
Lane M: Dependabot rows and #727 triggers ── independent, report at lane time
Lane Z: E20 registry row when the branch opens; the step-5 clause any time
```

## Shrink order (cut from the bottom, name the cut in the briefing)

1. #738 (README) — documentation, the product doc is still authoritative.
2. #737 (Lane C) — the exclusion stays named and honest without it; D-1 stays
   signed for the next batch.
3. #751's entry form — shrinks to the read-only timeline; **the timeline
   itself never shrinks**, it is a signed clause.

Lane A otherwise never shrinks: the ADR's scope list is what the owner
signed. Lane B's #740 and #741 do not shrink — they are the close-out
findings of a rule that already fired once.

## What is deliberately not in this sprint

- **FR-39/FR-40 (derived metrics per security and per view):** issue-ready
  since Sprint 7's mechanism, still unfiled. One new object family per batch;
  these are next, and the research log gives them a place to be cited from.
- **B3.6 (policy rules) and B4.2 (predictions and calibration):** the next
  gates in the triage's Part 3 order; each needs its ADR drafted for
  signature first. Drafting can start during this batch as a no-code
  planning PR, the way ADR-0044 was drafted during Sprint 8's tail.
- **#610 (TTWROR on a lost quote feed):** needs a staleness rule before code
  and no observed case yet. **#608 (merge securities):** needs its spec
  first. **#572 (benchmark):** needs the quote-source decision (OQ-3).
- **#328, #354, #330, #332, #333:** `needs-uat`, gated or discovery-first,
  unchanged.
- **#314, #382, #395:** standing engineering debt; Lane M candidates when a
  gate story is cut for them, not opportunistic riders.

## What "done" means for this sprint

1. Every ADR-0044 scope item — the entry, the derived state, the four
   queries, the timeline, the journal arming, the contract read — is merged,
   or this close-out records which one is not and the ADR clause it leaves
   open. The timeline is a signed clause: its absence is not a shrink, it is
   a finding.
2. `security_notes` is guard-armed in its creating migration and the
   append-only property is pinned by a test that tries to update and delete
   at the database and is refused.
3. #740's two parameters exist on both halves, and the close-out's surface
   check names every endpoint of the `include_positions` and threshold
   families and states which carry them (Lane Z's clause, first use).
4. The contract-version read's first manifest entry names this batch's own
   additions, and the meta-test fails when a route or tool changes without
   one.
5. Lane M's report exists BEFORE the closing act starts, and every Dependabot
   PR open at batch start is either applied as its own commit or closed with
   the reason.
6. The closing act runs under section G's conditions (DE, ≤ 390 px, a seed
   with a superseded and a retracted entry, a security with no entry for 90
   days, a block expiring within 7 days) plus the risk-tier verification pass
   on the append-only invariant and, if Lane C ships, on the Sprint 8 D-1
   fixture after backfill.
7. Close-out per ADR-0026 step 5, with an annotated `0.9.0` via the
   prepared-command path (0.8.0 was the first annotated one; keep it that
   way), the E20 row reconciled, and the two-way coverage check recording
   that the batch's agent-visible capabilities shipped with their human view.
