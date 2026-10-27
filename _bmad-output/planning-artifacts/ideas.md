# Ideas

Every idea that is not yet worked out enough to build. This is the stage
before the registry ([ADR-0042, amendment of
2026-10-27](../../docs/decisions/0042-one-planning-structure.md)); the rule
that runs it is the sprint workflow's
["Ideas"](../../docs/development/sprint-workflow.md#ideas).

**How to add one:** say "Idee: …" (or "Idea: …") in any session. The session
writes it here as said and touches no code.

**This file is public.** It carries no instance facts, figures or names. An
idea that came with them is stated generically.

## Statuses

| Status | Meaning |
|---|---|
| `captured` | recorded as said; nobody has looked yet |
| `triaged` | an agent has searched where it is already described, checked it against the ADRs, the scope ladder and the non-goals, and named its kind and its open questions |
| `discussing` | the owner and an agent are working it through; the open question is in its row |
| `worked-out` | ready to plan; it moves to `epics.md` or an issue, and its row becomes a pointer |
| `planned` | named in a sprint plan |
| `built` | its sprint built it; the close-out sets this |
| `dropped` | not pursued, with the reason and what would reopen it |
| `gated` | behind a decision gate that names it; only that gate's decision reopens it |

A **`no-brainer`** mark on a `triaged` idea says it needs no conversation: one
obvious answer, inside scope, no money semantics. A plan may take it
straight away and says so.

**Kinds:** feature, UI, docs, app page, process, data.

**Per session, one idea goes deep.** A planning session proposes the next
one; the order below is the recommended one.

## The list

### The owner's ideas, newest first (2026-10-20 to 2026-10-27)

| # | Idea | Kind | Status | Where described | Open question | Stands against |
|---|---|---|---|---|---|---|
| I1 | **Explanatory texts and warnings move out of the way**, behind a mouse-over or a disclosure | UI | `triaged` | this list (owner, 2026-10-27) | Which texts are *explanations* (how a figure is computed, what a control does) and which are *data notes* (something is wrong with this figure now)? An inventory per page is the homework. | `DESIGN.md` separates the two: ⓘ is the metric-definition affordance (UX-DR11) and a note states a fact about this data. No meaning may live only in a `title` attribute or a tooltip, because touch screens, keyboards and screen readers do not get it (the value-slot and bucket-chip rules). A hover-only tip also fails the 390 px phone rule. So the likely shape is: explanations behind ⓘ disclosures (the `PopoverDisclosure` hook exists), data notes stay visible but shorter. Needs a board. Sprint 21's γ boards are adopted; this idea comes after them, not into them. |
| I2 | **Simulation (paper) accounts**: an agent runs a play-money depot whose figures never leak into the real ones | Feature, data | `triaged` | this list (an agent's feature request, 2026-10-20) | Three answers only the owner has: is a second instance enough (zero code)? should FIFO be per depot for real depots too? may a simulation account ever turn real? | ADR-0018's first invariant (everything held counts exactly once in "everything"); views already exclude buckets and a default view is settable, so part of it works today. The FIFO queue is one per security across portfolios by the ADR-0015 amendment of 2026-10-09, and T-21 of the 2026-10-12 security review builds on that: per-account FIFO would reopen an adopted decision. Comes after Sprint 21's Lane S. Not a backtest: paper trades are recorded forward, ladder level (c). |
| I3 | **Switch the agent method from BMAD to OpenSpec** | Process | `triaged` | this list (owner, 2026-10-20) | Pilot a living spec for one capability (scope, views and FIFO), or not? | The process is not BMAD's: it is ADR-0026, the sprint workflow, the story workflow and 54 ADRs. A switch renames, it does not lighten. Recommended: no switch; take OpenSpec's change-proposal shape for ideas (this list is the first step), pilot one living spec, and prune the BMAD skills the docs never name. |
| I4 | **This idea list** | Process | `planned` | ADR-0042 amendment of 2026-10-27; sprint workflow "Ideas" | none | built by the Sprint 21 amendment's planning PR |

### Harvested from the repository (2026-10-27)

Every row was found in a planning artifact, an ADR or an open issue that
nobody has decided, specified with acceptance criteria and a sprint, or
built. Where an open issue already holds it, the issue is named and stays
the authority. Board repairs already filed as issues (#1219 to #1226) are
not ideas and are not listed: they wait in the tracker for the next
decision pass.

**Features**

| # | Idea | Status | Where described | Open question | Stands against |
|---|---|---|---|---|---|
| F1 | Predictions and a calibration report | `gated` (B4.2) | `epics.md` FR-46/47; ADR-0044 asks; backlog triage 2026-09-23 | the agent has never confirmed it will record predictions | ladder (c); basis in the payload |
| F2 | Rule evaluation and signal quality | `triaged` | `epics.md` FR-48; ADR-0049 §10–11 | needs months of findings; "mattered" is undefined | a replay over past data is ladder (d) |
| F3 | Further policy-rule measures and subjects | `captured` | ADR-0049 §11 | each needs its own argument | close to "no advice"; event alerts lead to B3.7 |
| F4 | Rebalancing digest in one call | `gated` (B3.5) | feedback triages 2026-08-12, 2026-09-19; addendum "Parked" | E24 in real use first; v1 scope | display-only (ADR-0023) |
| F5 | Limit-price suggestions and a per-trade tax estimate | `gated` (B3.5) | addendum "Parked"; feedback triage 2026-08-27 | an ADR-0023 amendment on its own merits | a limit price prepares an order: the permanent non-goal |
| F6 | Ranked cash guidance, both directions (rest of FR-12) | `triaged` | PRD §5 C, OQ-5; `epics.md` FR-12 | no ranking spec; tax awareness | display-only; never advice |
| F7 | Tax forward projection and a `tax_bucket` attribute | `gated` (own ADR) | ADR-0031 §7; `epics.md` FR-36 | its own gate | never a pot balance; "not tax advice" |
| F8 | Benchmark: after-tax view, CPI table, stored default per view | `captured` | ADR-0046 §4, §6; PRD OQ-9 | where CPI comes from | automatic CPI is acquisition (B3.3); a hand table is not |
| F9 | Pension modelling | `captured` | `epics.md` FR-24/25; PRD OQ-12 | discovery; who maintains the legal tables | forward projection, near "no advice" |
| F10 | Retirement projection and withdrawal planner | `captured` | `epics.md` FR-26; PRD OQ-2, OQ-13 | ladder position (OQ-13) | nearest to "no advice" of anything |
| F11 | What-if simulator and rule backtesting | `gated` (ladder d) | `epics.md` FR-27 (retired); PRD OQ-11 | a new gate | ladder (d) is forbidden |
| F12 | Data collectors and their health | `gated` (B3.3) | feedback triages 2026-08-12 to 2026-09-19; addendum | sources, failures, retention | never a raw news archive |
| F13 | Read-only bank, broker and wallet sync | `gated` (B3.3, Phase 3) | `epics.md` FR-17–21; PRD §5 E; import PRD OD-2 | the Phase 3 ADR; credential storage | read-only only; stored credentials (B1) |
| F14 | Push alarms and webhooks | `gated` (B3.7) | FR-38; ADR-0049 §10 | request forgery, stored secrets, retries | B3.7 |
| F15 | A local model for structuring jobs | `gated` (B3.8) | feedback triage 2026-08-12 | when a model is right at all | output is a `machine_generated` proposal (NFR-10) |
| F16 | **Broker-PDF intake** (and tax-statement documents) | `triaged` | ADR-0021 (accepted, **unbuilt, no issue**); import PRD Feature D | which broker first; the PDF dependency; does the converter prompt already cover it | ADR-0021's shape only; NFR-10 |
| F17 | Generic broker CSV import with saved mappings | `triaged` | import PRD Feature A, OD-3 | does the converter prompt make it unnecessary | `AGENTS.md` allows only PP v1 and ADR-0021 intake: needs a scope amendment |
| F18 | Seed holdings from a position list | `captured` | import PRD FR-DI-8 | does anyone want it | ADR-0004 (holdings derive from transactions) |
| F19 | An import route under `/api/v1` | `triaged` | Sprint 17–21 "not in this sprint"; ADR-0029 | the reopen evidence (a failed launch test, a report) | ADR-0029: the import is an operator action |
| F20 | `Idempotency-Key` on irreversible writes | `triaged` | **#899**; architecture D11 | D11 still proposed; after the announcement | — |
| F21 | Dry run for cascading deletes | `triaged` | **#894** | a parameter or a read tool | — |
| F22 | Realized result and income per category | `triaged` | **#900**; ADR-0041 §5 | own story or part of FR-41 | risk tier (ADR-0036) |
| F23 | Per-category series over time | `captured` | ADR-0041 §6; ADR-0051 §8 | its gate; when the journal covers enough | never booked into the ledger (ADR-0011) |
| F24 | Per-security IRR | `captured` | ADR-0034 | nobody has asked | basis in the payload |
| F25 | Dividends in the snapshot counterfactual | `captured` | ADR-0027 | no distribution history | replaying a rebalance is ladder (d) |
| F26 | Bond depth: coupon schedule, accrued interest, exact yield | `captured` | ADR-0052; bond discovery 2026-09-25 | reopens only if an export proves the face-amount convention | automatic bond data is B3.3 |
| F27 | Upcoming dividends in the calendar; event-to-booking links | `captured` | ADR-0048 §9 | tax and FX in a forecast; the matching rule | an amount makes it a forecast |
| F28 | Full-text search in the research log | `captured` | ADR-0044 "Out of v1" | its cost | — |
| F29 | Merge previews: flow effects and bond fields | `triaged` | **#957**, **#1070** | one ADR-0050 reading and a board | merge semantics (ADR-0050) |
| F30 | Performance and benchmark reads over every portfolio | `captured` | Sprint 18 D-5 | nobody has asked; schema budget | — |
| F31 | Merge the duplicate `views.*` / `portfolios.*` tools | `triaged` | feedback triage 2026-10-01 OQ-4 | only if steering by descriptions fails | changes a surface agents know |
| F32 | More MCP prompts for recurring work | `captured` | competitive research 2026-09-30, rec. 5 | which ones, at what schema cost | each carries the no-advice framing |
| F33 | Trade statistics at PP's report parity | `captured` | competitive research, rec. 1 | which statistics | basis in the payload; a board each |

**Data**

| # | Idea | Status | Where described | Open question | Stands against |
|---|---|---|---|---|---|
| D1 | Ledger kinds `interest_charge` and `fee_refund` | `triaged` | **#1177** (its recommended answer) | its trigger: a switcher's export | data model, risk tier |
| D2 | Deleting an imported booking retires its hash | `captured` | Sprint 18 D-6 | a signed record first | ADR-0029, ADR-0050 |
| D3 | Take the import parse off the page process | `captured` | security triage 2026-10-12, T-18 | the design issue Lane S files | — |
| D4 | Fold portfolios into buckets and views | `triaged` | ADR-0024 §5; design session 2026-07-12 | is the exit criterion met | a risk-tier migration |
| D5 | Market-data robustness: backoff, more providers | `captured` | import PRD follow-up notes | nothing specified | ADR-0005; the outbound policy |

**Screens and app pages**

| # | Idea | Status | Where described | Open question | Stands against |
|---|---|---|---|---|---|
| U1 | Phone access as an installable PWA, with a private-network recipe | `triaged` | feedback triage 2026-10-01 OQ-5; Sprint 17 D-8 | the hands-on test on two phones; the widening phase | no native app |
| U2 | **An audit journal viewer** | `captured` | product documentation ("a planned follow-up"); the API and MCP read exist | no issue, no board | **the two-way coverage rule: the journal has no human view** |
| U3 | Income per instrument, readable | `captured` | feedback triage 2026-08-05 | a design session | — |
| U4 | Feedback for background actions | `captured` | brainstorming 2026-06-18 | whether later inline results already cover it | — |
| U5 | A manual logo sent as bytes over the API and MCP | `captured` | security design pass 2026-10-27 (H38) | once H38 lands, the API's URL path is the only non-screen way to set a manual logo; is an upload route wanted | the outbound policy; the API's body bounds |

**Docs and process**

| # | Idea | Status | Where described | Open question | Stands against |
|---|---|---|---|---|---|
| P1 | A comparison and migration page for PP users | `captured` | competitive research, rec. 6 | the owner called a PP migration path "not a priority" (2026-10-01) | synthetic examples only |
| P2 | A metric's computation basis on screen (OQ-14) | `triaged` | PRD OQ-14; addendum | is the ⓘ enough; overlaps I1 | — |
| P3 | Learn what PP switchers miss | `captured` | competitive research, open question 2 | who, when | record only the shape of what is learned |

### Decided "not now", with what reopens them

Closed on purpose by a plan; listed so they are findable. Status `dropped`
unless a gate holds them.

| Idea | Status | Where | Reopened by |
|---|---|---|---|
| Excess return per trade; returns heatmap; presenter (privacy) mode | `dropped` | #1002, #1003, #1004 | the announcement decision plus a feature lane, or a request |
| Contribution variants (pp to TTWROR, pp of capital, price/FX split, today's tree) | `dropped` | #987–#990; ADR-0051 | each section's own trigger |
| `protected` and `budget` policy rules | `dropped` | #866; ADR-0049 §11 | an owner request for such a rule, or B3.5 |
| Income received during an open trade | `dropped` | #1000 | the operator asking whether a trade was worth it with its income |
| Per-depot FIFO; lots for delivered-in positions | `dropped` | #1001; Sprint 17 D-7 | a non-empty `unmatched_sells` on the live instance; overlaps I2 |
| Merger and spin-off as ledger events | `dropped` | #907; ADR-0028 §4 | a booking or an export that carries one |
| Unmerge, tombstones, generalised aliases, economic matching | `dropped` | #902, #903, #905, #906 | each issue's own trigger |
| Write-scoped API tokens | `dropped` | #999 | an agent on another host with its own token |
| Draft-then-commit for agent research entries | `dropped` | #1080 | an entry someone would have stopped |
| Parse-only check of a converted file; a settlement field in JSON v1 | `dropped` | #1038, #1025 | a stranger's report |
| "Has the valuation changed?" conditional read | `dropped` | #849 | an agent showing the cost of re-reading |
| A per-portfolio Risk page | `dropped` | #946 | D4 being scheduled |
| A suspect list of PP CSV bookings without the file | `dropped` | #1097 | an operator who cannot export again |
| Store the inferred asset class at write time | `dropped` | #1079 | a second inference fix that must reach old rows |
| Readable deep classification trees | `dropped` | #1182 | a tree deeper than about 8 to 10 levels, or a tree import |
| SOLL auto-distribution; the 100 %-per-level UX | `dropped` | #481's slices; ADR-0030 | the first real complaint |
| A complete PP XML import as a one-time seed | `gated` | #333; `epics.md` FR-5 | an `AGENTS.md` amendment and an ADR; the binary `.portfolio` stays out |
| Weighted multi-category assignment | `gated` | competitive research, rec. 2(a) | its own decision against the "advanced classifications" rule |
| Multi-tenancy; real estate; income and expense tracking | `dropped` | #340; addendum "Parked" | declined: "no tenancy" is identity, the others a separate product |

### Recommended order for going deep

1. **I1**, the explanatory texts: it touches many screens, so it should be
   settled before the next UI batch draws new notes.
2. **U2**, the audit journal viewer: a standing two-way coverage debt.
3. **I2**, simulation accounts: after Lane S's K09 lands.
4. **I3**, the method: after one sprint has run with this list.
