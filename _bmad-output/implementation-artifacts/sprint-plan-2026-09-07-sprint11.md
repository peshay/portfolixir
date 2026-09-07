# Sprint 11 — the perimeter's remainder, and the founding question

**Status: DRAFT 2026-09-07 — awaiting owner adoption on the planning PR.**
Per this plan's own terms, adoption ("passt") covers the lane cut AND signs
**D-1** (ADR-0046), **D-2**, **D-3** and **D-4** below as recommended; a
"nein" on any one of them removes that lane or reshapes it and leaves the
rest standing. Verification basis: `main` at 8d178e35 (the Sprint 10
close-out plus #777), the open-issue list before this plan filed anything
(26 open), the open pull requests (two Dependabot PRs, #774 and #775, no batch
PR), and the tag list (`0.10.0` annotated on 8d178e35, release published
2026-09-07 17:24 UTC — the retro's open item is closed).

## State of play, in four lines

1. **Sprint 10 ruled on half of this sprint before it was planned.** The
   2026-09-05 security triage names Lanes C (#382, CSP + HTTPS posture) and D
   (#772, Bandit) as "the next batch by the triage's own ruling", and the
   close-out filed #776 as the surface check's first catch. Letting them age
   contradicts the rule Sprint 10 ran under: one batch between naming a
   weakness and fixing it, not a backlog age.
2. **The founding question is unblocked and has been waiting since
   2026-08-12.** #572 (FR-9, "was it worth it?") was released by the scope
   ladder; its two prerequisites, #545 and #568, are closed; what it lacked
   was a decision on its three design questions. ADR-0046 is that decision,
   drafted for this gate.
3. **#610's own condition is met, and the reading behind it found a larger
   defect.** The owner confirmed that failed, delisted and renamed holdings
   occur in their data. Re-reading the walk for the rule #610 needs showed
   that an outbound delivery of such a holding leaves at its stale quote,
   so the total loss never enters TTWROR (#779). D-3 fixes both with one
   signal that already exists.
4. **The tag question is answered by the owner's hands, four times.** The
   session's credential has refused the tag push every sprint since 0.8.0;
   the owner has tagged every time. D-4 writes that down.

## Why this cut

- **Engineering lanes that cost the owner nothing make room for exactly one
  product lane.** C, D, W and M are `agentic`, no UAT, their acceptance is a
  gate going green or a list being complete. That is why the batch can carry
  #572, whose acceptance is a behaviour walkthrough.
- **#572 over #608/#328.** Both merge/repair issues are the owner's first
  priority by theme (data consistency), but both need their spec first and
  #608's idempotency reasoning is a decision, not a lane. Filed for the
  Sprint 12 gate; not pulled forward half-decided.
- **Lane X rides because the rule is already known.** #610 said "needs a
  rule before code"; the rule is the `is_retired` flag the catalog already
  has, and #779's fix aligns two accepted ADRs that disagree on one booking.
  Neither needs a discovery story — they need a fixture and a commit group.
- **The toolchain stays where it is unless a trigger fired.** #727's
  triggers (excoveralls cover support for 1.20, the `Ecto.Multi`/`MapSet`
  opaqueness) are unrelated to the Bandit swap; Lane M re-checks and
  reports, and #775 is applied only if they did.

## Lanes

### Lane D — the HTTP server (#772; first, because C sits on top of it)

Cowboy → Bandit, Phoenix 1.8's default. Removes `cowlib` and its three
open advisories from the tree, lets the Hex 2.4.1 pin and its comment in
`ci.yml` go, restores `hex.audit` to the current Hex. Its own commit group
(ADR-0036, a dependency change), browser-verified at the section-G
conditions like ADR-0037 was: LiveView boots, the socket reconnects, the
Host guard and the login of ADR-0045 behave identically. GitHub Actions
pinned to SHAs ride the same lane, as the triage prescribed.

### Lane C — CSP and the HTTPS posture (#382; D-2 below)

A per-request nonce wired through the root layout to the theme bootstrap and
the LiveView boot script (and any inline style that survives the audit), a
`Content-Security-Policy` header built from it, and the two Sobelow ignores
removed from `ci.yml`. Done means `mix sobelow --skip --exit` is green with
**no** ignores. The HTTPS half is D-2. The closing act verifies CSP the way
Sprint 10 verified the confirmations: in a browser, with the console open —
a CSP that blocks the boot script is a green CI and a white page.

### Lane W — the `limit` surface, finished (#776)

Nine collection reads, one recorded decision each. The expected split: the
four `notes` reads, `/realized_gains`, `/snapshots`, `/external_flows` and
`/costs` gain `limit` through `ListLimit` and their MCP twins in the same
commit; `/securities/:id/trades` records "`from`/`to` is the bound" if that
is the answer. The close-out's surface check names all nine and what each
carries — the third time this family is checked and the last time it is
half-done.

### Lane X — performance on retired securities (#779, #610; D-3 below)

**Risk-tier attention label** (ADR-0036): the daily walk. One commit group,
fixture-first:

1. **#779 —** a delivery carrying a booked price enters `F_d` at that price;
   a price-less delivery keeps the day's-quote rule. ADR-0010 amended in the
   same commit (its "valued at that day's quote" clause gains the exception,
   citing ADR-0034 §1). Fixture: a total loss booked out at price 0 shows
   the loss in the period's TTWROR; the same booking without a price stays
   as today and is named by the stale-quote flag.
2. **#610 —** a retired security's carried quote is not a measurement:
   `measured?` is `false` while `is_retired` is set and no newer quote row
   exists, so the trade point that replaces the stale quote emits the basis
   step, and it re-latches on the next quote row. Fixture: a retired
   security with a quote gap and a later sell shows zero return across the
   gap.
3. **The stale-quote flag** on the valuation: `price_date` is surfaced in
   the human view and the data-quality check lists held positions whose
   latest quote is older than the sync horizon, so an operator learns which
   holdings to mark retired — the flag #610's rule keys on.

Non-regression: the existing quoted-portfolio fixtures stay byte-identical
(the #545 criterion), asserted as such.

### Lane B — the benchmark comparison (#572; D-1 = ADR-0046)

Order is the dependency order, API and MCP before the UI (the daily operator
is an agent):

1. The `is_benchmark` flag on securities (additive migration), the
   securities read's filter, booking forms and data-quality nags excluding
   it.
2. The comparison engine: the fixed-rate series, the series benchmark over
   existing quotes, the "bought once" rebased series, the "savings plan"
   replay of ADR-0034 §1's flows at the same scope, the end-value delta and
   the two IRRs, excluded-and-named flows before the first quote, memoized
   under ADR-0039. **Risk-tier attention label**: the three pinned
   identities of ADR-0046's consequences are the first tests.
3. `GET /api/v1/portfolios/:id/performance/benchmark` and
   `/views/:id/performance/benchmark`, the MCP twins, the contract-manifest
   entry (#752) — in the same commit.
4. The Wealth chart overlay (≤ 2 benchmarks) and the comparison block next
   to TTWROR/IRR with its one-line explanation, DE and EN.

### Lane M — maintenance (always present)

- **Dependabot #775 (Elixir 1.20.3-otp-29 image):** this is #727's move,
  not a routine bump. Re-check the two triggers; apply as its own commit
  group with CI as the evidence if both fired, otherwise close with the
  reason and the re-check date on #727.
- **Dependabot #774 (Node 26 image):** Node 26 is Current, not LTS, until
  October 2026, and the runtime is pinned in four places by an invariant
  test. Close with the reason; the trigger is the LTS promotion.
- **#727 triggers reported either way.** `version-report-2026-09-XX.md`
  written at lane time, before the closing act starts.

### Lane Z — registry (small)

No new epic: this sprint's lanes are E21's remainder (C, D, W), E5/E1's
correctness (X) and E10's first shipped item (B). The FR Coverage Map's
FR-9 row gains the issue numbers; `sprint-status.yaml` carries the planning
entry; the close-out reconciles against the existing rows.

## Decisions

### D-1 — the benchmark's shape — ADR-0046 (recommended)

Signing ADR-0046 as drafted: two benchmark kinds (a fixed annual rate, a
catalog security flagged `is_benchmark` fed by the existing sync — no new
quote source, which answers OQ-3), two comparisons (a rebased "bought once"
overlay next to TTWROR; a "savings plan" replay of the portfolio's own
external flows with an end-value delta and two IRRs on identical flows),
portfolio-wide and per view, API and MCP first. Inflation is a typed rate
in v1. Deferred with reasons in the ADR's §6: a dated CPI table, the
after-tax dimension (OQ-9), a stored per-view default.

### D-2 — the HTTPS posture for #382 (recommended)

**Document the reverse-proxy TLS contract and keep `PHX_FORCE_SSL` as the
runtime opt-in Sprint 10 shipped; no unconditional in-app `force_ssl`.**
The deployment model is self-hosting behind an operator's proxy (ADR-0045);
an unconditional redirect breaks the loopback default that ADR-0045 made the
safe baseline. Sobelow's `Config.HTTPS` finding is satisfied by the opt-in
being present and documented; the check confirms it is configured, not that
it is forced. Both halves of the operator docs (EN/DE) name what the proxy
must do and what the variable does.

### D-3 — retired securities in the walk (recommended)

**(a)** A delivery with a booked price is valued at that price in the walk;
price-less deliveries are unchanged (ADR-0010 amendment, ADR-0034 §1
alignment). **(b)** `is_retired` is the staleness signal for #610 — no day
count, so the byte-identical guarantee for actively quoted portfolios holds
by construction and nothing in a quoted portfolio is reclassified. **(c)**
The valuation surfaces `price_date` and the data-quality check names held
positions with a quote older than the sync horizon.

### D-4 — the sprint tag is an owner action (recommended)

One sentence amending ADR-0026 step 5 (and its AGENTS.md mirror), landed as the batch's first commit once signed: **the
agent prepares the annotated tag command in the close-out; the owner runs
it.** Four sprints of a 403 on the tag push are the process, not a finding;
writing it down stops every retrospective from re-discovering it. Reversible
the day the session credential gains tag-push rights.

## Sequencing

```
Lane D: #772 ──▶ Lane C: #382 (the CSP plugs sit on the server D installs)
Lane W: #776 ── independent, after D so the route table is final
Lane X: #779 ──▶ #610 ──▶ stale-quote flag ── independent of B
Lane B: D-1 signed ──▶ flag ──▶ engine ──▶ API/MCP + manifest ──▶ UI
Lane M: triggers and the two bot PRs at lane time; report before the closing act
Lane Z: registry rows when the branch opens
```

## Shrink order (cut from the bottom, name the cut in the briefing)

1. Lane B step 4 — the chart overlay and the comparison block; **the API/MCP
   comparison never shrinks** (the agent is the daily operator, and a
   comparison an agent can read is the deliverable).
2. Lane X step 3 — the stale-quote flag; steps 1 and 2 are the correctness
   fix and do not shrink.
3. Lane W — the recorded decisions stay; the `limit` commits follow in the
   next batch with the surface check naming them as missing.

Lanes C and D do not shrink: a Sobelow ignore or a cowlib advisory left in
place is the batch not being done.

## What is deliberately not in this sprint

- **#608 (merge securities) and #328 (merge/rename/delete accounts):**
  Sprint 12's gate — the spec and the idempotency reasoning are decisions,
  and they belong in one ADR, not two lanes.
- **#333 (PP XML), #332 (what-if), #330 (bonds), #354 (backup/restore):**
  gated, discovery-first or `needs-uat`, unchanged.
- **#573, #567 (docs guides):** ride only if the closing act leaves a day;
  named here so their absence is a shrink, not a surprise.
- **#314, #395:** standing engineering debt; the coverage ratchet rides
  the batch as always, no lane.
- **A per-year CPI table, an after-tax benchmark, a stored per-view
  benchmark default:** deferred by ADR-0046 §6 with reasons.

## What "done" means for this sprint

1. `mix sobelow --skip --exit` runs in CI with **no** `--ignore`, and a
   real browser at the section-G conditions boots LiveView under the CSP
   header with an empty console.
2. `cowlib` is absent from `mix.lock`, the Hex pin and its comment are gone
   from `ci.yml`, `hex.audit` and `deps.audit` are green on the current Hex,
   and every Actions step is pinned to a SHA.
3. The close-out's surface check names all nine `limit` endpoints and what
   each carries; none says "later".
4. The quoted-portfolio fixtures are byte-identical before and after Lane X;
   the total-loss fixture shows the loss; the retired-gap fixture shows zero
   return across the gap.
5. The benchmark comparison is readable on API and MCP with a manifest
   entry, ADR-0046's three identities are pinned by exact-Decimal tests, and
   the UI shows the overlay and the block in DE and EN — or the briefing
   names step 4 as the shrink.
6. Lane M's report exists before the closing act starts; both Dependabot
   PRs are applied as their own commits or closed with the reason.
7. The closing act runs the ADR-0026 roles plus the risk-tier verification
   pass on Lanes X and B, and the briefing carries screenshots in a
   comment, not the PR body (Sprint 10's finding).
8. ADR-0026 step 5 carries D-4's sentence, and the `0.11.0` command is in
   the close-out for the owner to run.
