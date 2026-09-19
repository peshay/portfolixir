# Owner Feedback Triage — 2026-09-19 (agent round 3)

Source: a status assessment written by the owner's portfolio agent, handed to
the PM role on 2026-09-19. It reads **Contract v4 (2026-09-15, 121 endpoints,
113 tools)** against the agent's own requirements list of 2026-08-27, ticks
off what shipped, and ranks what is left. It is the **third edition** of the
document triaged on 2026-08-12 and 2026-08-27. This document is the PM triage
per ADR-0038.

**Privacy note.** The source names real instruments, a real near-missed
corporate date, real policy thresholds and a real protected position. **None
of it is reproduced here.** Rules are described by *type* — "a hard cap on a
satellite category", "a cash floor", "a protected-position rule" — never by
value or instrument, and the near-miss is kept only as the *shape* of a
failure ("a purchase candidate's reporting date"). Endpoint and tool counts
are system metrics, not financial data, and are kept. The source document is
not committed.

Status: triaged, and **acted on in the same pass**. The one item the agent
ranks as risk-bearing is gated, and the gate is closed by
[ADR-0048](../../docs/decisions/0048-security-events-as-first-class-objects.md)
on the Sprint 13 planning PR rather than filed as a question. One
already-shipped guarantee is refuted for the third time and needs a delivery
fix, not a documentation fix. One complaint is half right in a way that is
more useful than the complaint.

---

## Part 0 — The finding that governs the rest

**An agent reading the contract version can still be reading a stale copy of
its own document.**

The 2026-08-27 round's Part 0 said an agent had no way to learn that the
surface changed, and ADR-0044 §8 answered it with a contract-version read.
This edition proves the read works — the agent cites "Contract v4, 121
endpoints, 113 tools" and correctly ticks off five shipped items, including
two from the previous sprint. So the mechanism is doing its job.

And yet the document's single most expensive claim is **false, and false for
the third consecutive edition** (§1 below). The contract version tells an
agent *that* the surface changed; it does not make it re-read the prose that
explains a guarantee. The agent re-derived its "still missing" list from its
own previous edition rather than from the integration documentation, and the
refuted premise rode along both times.

The remedy is not another document. It is that a **guarantee an agent must
not get wrong belongs in the payload or the tool description**, where the
agent reads by construction, rather than only in a page it has to choose to
open. That is the same lesson the metric-basis rule already encodes for
metrics ("a doc page does not satisfy it"), applied to a contract guarantee.
Recorded as the finding worth carrying, and filed — see Part 4.

---

## Part 1 — The claim that is false, with the evidence

The document raises, as its one "unresolved and potentially expensive" item,
whether the new notes log survives a Portfolio Performance re-import —
stating that for classification and target weights the documented answer is
no, that a research log which disappears at the next import is worthless, and
that this is its appendix-B question 1, still open. (Paraphrased rather than
quoted: repository artifacts are written in English, and the source document
is not committed.)

**It is not open, it is not "documented no", and the research log is
explicitly covered.** Verified against the code on 2026-09-19:

1. **The test covers it by name.**
   `test/portfolixir/imports/reimport_preservation_test.exs` — "re-importing
   the identical export preserves classification, targets, cash target, notes
   and attributes" — asserts `research_log_snapshot(...) == snapshot.research_log`,
   `Knowledge.count_notes() == 2` and
   `Knowledge.thesis_state(acme.id).derived_from_entry_id == thesis.id`, and a
   second test repeats the guarantee for a **mutated** re-import (a rename
   plus a recorded ISIN change).
2. **The applier never deletes a security.** The only `delete` calls in
   `lib/portfolixir/imports/applier.ex` are index bookkeeping on the ISIN
   maps.
3. **It is documented, in the place an agent reads.**
   `docs/integration/api-and-mcp.md` → Imports states the re-import
   preservation guarantee and names the research log inside it, with the test
   path and the issue numbers, and closes with: *"A research log, a plan or an
   assignment therefore never 'disappears at the next import'; an agent that
   observes otherwise has found a defect, not a documented limitation."*

The history of this claim is the point. The first edition asserted that a
re-import destroys classification and target weights; **#664 refuted it on
2026-08-14** and pinned it as a permanent regression guard. The second
edition repeated it; the 2026-08-27 triage filed **#741** so the guarantee
would exist outside the test file, and #741 shipped. The third edition
repeats it again, now against a documentation page that says the opposite.

**Verdict: refuted, third time, no work in the product.** The work is in
delivery (Part 0), not in the guarantee. **What goes back to the agent:** the
three pointers above, and the note that its appendix-B question 1 is closed.

---

## Part 2 — Correctly ticked off

The agent's "delivered, and cleanly" list is accurate. Recorded so the next
edition does not re-ask:

| Agent item | Reality |
|---|---|
| P0-6 research log | Shipped Sprint 9 (ADR-0044, E20): append-only notes, the four reads, `thesis_state` on the security read. Correctly noted as covering P1-1's core. |
| P0-1 token economy | Shipped Sprint 6/8/9: `limit=` across the collection reads, `include_positions=false`, `min_drift=`, `fields=`/`projection`. |
| P4 principle (derivations no quieter than their inputs) | Shipped Sprint 11/12: `price_date` per position, `stale_priced_count` and `newest_quote_date` on both valuation scopes. |
| Benchmark comparison | Shipped Sprint 11 (ADR-0046, FR-9), both performance scopes. |
| Tax layer | Shipped Sprint 4/E19 (ADR-0031). |

One correction to the framing: the agent lists **P1-5 (metrics and
indicators)** as still living locally on its side. As of this planning PR it is **signed
and scheduled**: [ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)
settles FR-39/FR-40 (moving averages, realized volatility, drawdown,
momentum, distance to extremes per security; volatility, risk-adjusted
return, drawdown and correlation per portfolio or view) and Sprint 13 builds
the per-security half. The agent's list and the pipeline moved past each
other again, which is Part 0 in miniature.

---

## Part 3 — The remainder, sorted by what it actually is

The agent sorts by pain. This sorts by **what stands between the request and
the work**, which is the only ordering a plan can act on.

### 3.1 — P0-4 security events: gated, and the gate closes here

**The agent's own ranking is right and this triage adopts it.** Its argument
is that this is the only gap that hides *risk* rather than costing *tokens* —
everything else on the list is a number it can recompute, this is a date it
can miss. The structural half is the part worth quoting back: the agent built
its calendar **out of the holdings**, so a security not yet owned has nowhere
to keep a date, and a purchase candidate's reporting date came close to being
missed for that reason.

FR-44 has said the same since the requirements inventory, including both
structural boundaries (catalog-wide, not holdings-scoped; distinct from
ADR-0028 corporate actions). It was **gated at B3.4** and nothing else was
missing.

**Action: the gate is closed in this pass, not filed as a question.**
[ADR-0048](../../docs/decisions/0048-security-events-as-first-class-objects.md)
is written as adopted on the Sprint 13 planning PR, and Sprint 13 takes it as
Lane E. The ADR deliberately says no to the three things a "security events"
table invites and nobody asked for — a calendar feed (B3.3), alerting or push
(B3.7), rules over events (B3.6) — because the 2026-08-15 finding about
generalising a request before satisfying it applies to exactly this shape.

### 3.2 — P1-6 `?since=`: half right, and the right half is filable today

The agent writes that `?since=` is missing, and that every scheduled run
therefore pulls full state and diffs it against its own state files.

`?since=` **exists** — FR-38's pull half shipped 2026-08-14 with its human
view in Sprint 8. But it exists on **two reads**: `GET /api/v1/securities` and
`GET /api/v1/transactions` (plus the contract read). Verified at the call
sites: `SinceParam` is aliased in `security_controller.ex` and
`transaction_controller.ex` and nowhere else.

So the agent is not describing an absent parameter. It is describing a
parameter that is absent **from the reads its scheduled run actually polls** —
valuation, allocation, targets, the notes reads. Re-read that way the
complaint is precise, correct, and **exactly the shape of #740**: a coverage
rule stated per requirement let FR-38 be "discharged" while the surface was
half-done, which is the finding the 2026-08-27 round already recorded and the
close-out surface check exists to catch.

**Action: filed** as the FR-38 surface gap, ungated and small, with the
close-out's surface-check sentence naming every read of the family. Not in
Sprint 13 — the batch is full (Part 5) — but filed with its evidence so it is
a queued item rather than a fourth-edition complaint. **The threshold-alarm
half of P1-6 is a different thing entirely:** a retrievable alarm list is
FR-43's output (B3.6) and outbound delivery is B3.7. Both stay gated.

### 3.3 — P0-2 rebalance digest, P0-3 policy rules: gated, and the drift is evidence

The agent reports that its caps and floors live as prose inside scheduled
prompts, and that prose drifts — with the note that this has demonstrably
happened.

That is FR-43 verbatim — the requirement already says caps and floors live
today as prose inside scheduled prompts *"which is exactly where the observed
drift came from."* The agent has now supplied a second, independent
observation of the same drift, which is the strongest argument yet for
opening **B3.6**, and it changes nothing about the fact that B3.6 needs its
own ADR (a rules engine plus a rule-history retention decision).

The rebalancing digest (P0-2) sits behind **B3.5** and additionally depends
on the policy rules to have anything to evaluate.

**Action: no filing, no gate opened here.** Recorded as accumulating evidence
for the B3.6 gate, which is a Sprint 14 planning candidate. Two gates in one
planning PR is already the limit of what an owner can read and sign in one
sitting, and a rules engine deserves the same care ADR-0047 and ADR-0048 got.

### 3.4 — P1-2, P1-3, P2-2: gated or forbidden, and unchanged

| Item | Where it stands |
|---|---|
| P1-2 prediction calibration | FR-47, ladder level (c). Needs FR-46 (predictions as objects, **B4.2**) first — calibration without recorded predictions has nothing to score. |
| P1-3 collector / signals | Data acquisition beyond quotes and FX, **B3.3**. Unchanged by anything in this edition. |
| P2-2 backtesting | Ladder level **(d)** — replaying a rule against stored price history — and out behind its own gate. Not a backlog item; a boundary. |

**Action: none.** Restated so the fourth edition can find the reasons without
re-asking.

---

## Part 4 — What is filed by this triage

| What | Why it is bookkeeping rather than new scope |
|---|---|
| **FR-38's surface gap** (`?since=` on the reads a scheduled run polls) | Completing a shipped requirement's surface, the #740 pattern. Ungated, small, evidence in §3.2. |
| **The delivery finding of Part 0** — a contract guarantee an agent must not get wrong belongs in the tool description or the payload, not only in a page | Applying an existing rule (the metric-basis rule's "a doc page does not satisfy it") to a second case. Concretely: the re-import preservation guarantee gets a sentence in the MCP tool descriptions of the reads it protects. |

Both are filed at the Sprint 13 branch opening with the rest of Lane Z's
bookkeeping, and both are **Sprint 14 candidates**, declared now so their
absence from Sprint 13's closing act is a plan rather than a surprise.

Nothing else in the document is filed. The gated items are gated with reasons
that have not changed, and filing an issue for a gated requirement would
create a title with no spec behind it.

---

## Part 5 — What this costs Sprint 13, said plainly

Sprint 13 was cut on 2026-09-19 with a metrics lane (ADR-0047), the E11
surface close, the #814 coverage deadline, the journal limit parser and
maintenance. Adding Lane E (security events, ADR-0048) to that is **two new
object families plus an epic close on one branch**, which is more than
"epic branches live days, not weeks" survives.

The plan's D-7 therefore makes the trade explicit rather than letting the
shrink order discover it: **Lane E goes in, and ADR-0047's portfolio-scope
metrics (Lane A2) move to Sprint 14.** The argument is the agent's own and
this triage adopts it — a missing date hides risk, a missing volatility
figure costs tokens. ADR-0047 stays signed whole; only the build order
changes, and the per-security half stays because it is the half the agent's
P1-5 actually asks for and it shares the securities detail surface with Lane
E's event list, so both land in one pass over one screen.

---

## Part 6 — What goes back to the agent

1. **appendix-B question 1 is closed.** The research log survives a PP
   re-import — identical and mutated — pinned by
   `reimport_preservation_test.exs` and documented in
   `docs/integration/api-and-mcp.md` → Imports. Classification and target
   weights have survived since #664 (2026-08-14); the "documented no" has
   been wrong in all three editions. Read that section before the fourth.
2. **P0-4 is accepted and scheduled.** The gate is signed (ADR-0048); Sprint
   13 builds the table, the four reads on API and MCP, and the per-security
   list on the detail pane. Catalog-wide by default — the unheld candidate is
   the case the decision is built around. No feed, no alerts, no rules: those
   are three separate gates and each is named.
3. **P1-5 is signed and in build** (ADR-0047), per-security half in Sprint 13.
4. **`?since=` exists on two reads, not zero.** Use it on
   `/api/v1/securities` and `/api/v1/transactions` today; the gap on the
   valuation, allocation, target and notes reads is filed with your evidence.
5. **P0-2, P0-3, P1-2, P1-3, P2-2 stay gated**, each for a reason in Part 3.
   The prose-drift observation is recorded as evidence for the B3.6 gate; it
   is the most useful thing in the document after P0-4.
6. **Yes — update your feature-request document**, and please build the next
   edition from the contract and the integration documentation rather than
   from the previous edition. Three editions have now carried one refuted
   premise, and it is the only item in your list that ever cost anything to
   answer.

---

## The finding worth carrying

*A machine-readable "what changed" is not the same as a machine-read "what is
guaranteed".* The contract-version read was built so an agent could notice the
surface moved, and it worked — this edition reads it. But a guarantee that
lives only in prose is still re-derived from the consumer's own stale notes,
and a false premise about durability is more expensive than any missing
endpoint: it makes an agent distrust data that is fine. Put the guarantee
where the consumer reads by construction.
