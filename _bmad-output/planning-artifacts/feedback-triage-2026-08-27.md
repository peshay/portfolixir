# Owner Feedback Triage — 2026-08-27 (agent round 2)

Source: a requirements document written by the owner's portfolio agent
("requirements from agent operation", dated 2026-08-27) and handed to the PM
role. It is the **second edition of the document triaged on 2026-08-12** —
same numbering (P0-1 … P2-3), same principles, with one new requirement
(P0-6), one corrected rule inside P0-2, and an unchanged remainder. This
document is the PM triage per ADR-0038.

**Privacy note.** The agent's document contains real position references
(instrument names and catalog ids), real policy thresholds, household member
names, dated real-world events on named companies, and a real tax-pot state.
None of it is reproduced here. Rules are described by their *type* ("a hard cap
on a satellite category", "a protected-position rule"), never by value or
instrument; the retraction and mis-scaled-figure examples are kept only as
*shapes* of failure, never with the security they happened to. Response sizes
and call counts are system metrics, not financial data, and are kept. The
source document is not committed.

Status: triaged. **Amended the same day** (Part 5): the two items that complete
already-shipped work are filed as #740 and #741 rather than held for
confirmation — completing a shipped requirement and documenting an existing
guarantee are bookkeeping, not new scope. New scope is untouched and still
needs its signed gate; what is left for the owner is one signature on ADR-0044,
not a list of questions.

---

## Part 0 — The finding that governs the rest

**The agent's most expensive complaint is a feature it already has.**

Its section 3 ("where the tokens burn") measures four calls, and asks in P0-1
for sparse fieldsets, roll-up-only aggregates and a server-side drift filter —
"the right pattern, missing almost everywhere else". That is FR-37, shipped
2026-08-14 in Sprint 6 (#665, PR #688) together with FR-38's `?since=` delta
reads (#666), with a **≥ 70 % volume cut pinned by test**. Acceptance criterion
2 of this very document ("−70 % response volume on the four main calls") was
met and made permanent thirteen days before the document was written.

Verified in the tree as of `125d656`:

| Ask (P0-1 / P1-6 first half) | State |
|---|---|
| `fields=` whitelist | `field_selection.ex`, used by the securities, transactions and holdings controllers; mirrored in the MCP schemas as enums |
| `projection=slim\|full` | securities, defaulted slim |
| `include_positions=false` | `allocation_controller.ex:88`, `valuation_controller.ex:39` — and their MCP twins |
| `min_drift=` server-side filter | `allocation_controller.ex:99`, MCP `min_drift` |
| `?since=` delta reads | `since_param.ex`, securities + transactions, both surfaces |

So the interesting question is not *what to build*. It is **why a shipped
capability did not reach the only consumer it was built for.** Three readings,
and all three are product findings rather than agent errors:

### 0.1 — An agent has no way to learn that the surface changed

The MCP tool descriptions do document every one of these parameters, at length.
But a description is read at connect time and cached by the client; there is no
"what changed since" for the *contract* the way `?since=` is a "what changed
since" for the *data*. The agent's operating instructions were written against
the pre-Sprint-6 shape, and nothing in the system contradicts them. **A
product whose primary consumer is an LLM ships its release notes as a tool, or
it does not ship them.**

This is the exact inversion of what we did well: we built a delta read for rows
and none for capabilities.

### 0.2 — The cheap path exists and is not the default

`portfolixir.portfolios.allocation` returns position rows unless asked not to;
`securities.list` is the one heavy read that defaults slim, and the agent's
measurement of it (~25,000 characters) shows it explicitly passing
`projection=full` when `fields=` would have answered. Defaults decide what a
caller gets when the caller has not thought about it, and for the calls above
the default is still "everything".

### 0.3 — And one gap that is not a reading at all: FR-37 was rolled out per endpoint, and the endpoints this operator uses were missed

Code-verified, and the sharpest item in this round:

- **`views.valuation` has no `include_positions`** — neither in the API
  (`view_valuation_controller.ex` takes `view_id` and nothing else) nor in MCP
  (`idSchema`). Its portfolio-scoped twin `portfolios.valuation` has it. The
  agent's second-heaviest call (~12,000 characters, of which it needs three
  figures) is the cross-portfolio view valuation, because **bucket views are
  how this instance separates strategy and household scopes** (ADR-0018/0024).
  The roll-up shipped on the scope the operator does not read.
- **`targets.list_positions` has no threshold filter** — the schema takes
  `portfolio_id`, `classification_id`, `view` and nothing else. The agent's
  fourth call (~6,000 characters) wants "the rows with a deviation", which is
  `min_drift` one level down.

**The finding worth carrying: the two-way coverage rule is stated per
requirement, and a requirement can be *done* while its surface is half-done.**
That is the same defect the 2026-08-17 human-view-debt analysis found on the
human/agent axis, on a second axis: portfolio-scoped versus view-scoped. FR-37
is marked shipped in the FR Coverage Map, correctly, and two of the four reads
its own acceptance criterion names still cost full price.

**Recommendation:** a *surface* check at close-out, not a second rule — when a
read-ergonomics parameter lands, the close-out names every endpoint of that
family and states which ones carry it. Cheap, and it is the only mechanism that
would have caught this.

---

## Part 1 — Dedup: what this edition asks for that has already happened

This is the largest part of the document by volume and the smallest by news.
Everything below is the 2026-08-11 edition unchanged, and the pipeline has
moved under it.

| Ask | Status as of 2026-08-27 |
|---|---|
| **P0-1** sparse fieldsets, roll-ups, `drift_min` | **Shipped** (FR-37, #665, 2026-08-14) — except the two surfaces in §0.3 |
| **P1-6** first half, `?since=` deltas | **Shipped** (FR-38, #666, 2026-08-14), pull-only; human view #731 shipped in Sprint 8 |
| **P0-5** staleness warning, activity-aware | **Shipped** (#667) — a snapshot is stale by calendar *or* by tax-relevant bookings since it was taken, with its computation basis in every payload |
| **P0-5** allowance orders "table completely empty" | **Not a gap.** `Tax.AllowanceOrder` ships with entry, API/MCP and consistency checks (ADR-0031). An empty table is unentered data, not a missing feature |
| **P0-5** broker-PDF intake for snapshots | Unchanged: ADR-0021 is accepted and unbuilt. Still the only sanctioned path (sandboxed, text-extraction-only, per-broker, preview-then-confirm) |
| **P1-5** metrics per security / per view | Mechanism shipped (ADR-0039, #710/#711); FR-39/FR-40 are issue-ready, ungated by the scope ladder. The metric-basis rule already binds them |
| **P2-1** "a fresh PP import destroys classification, targets, cash target" | **Refuted and test-pinned** — see Part 4, question 1. This edition still carries the claim as documented fact; it is not |
| **P2-1** "how well did I sell", deposits/withdrawals, costs | **Shipped in Sprint 8** as the three Cash-flow facets (#724/#725/#726), realized gains on the D-1 FX basis |
| **P0-3 / P0-4 / P1-1 / P1-2 / P1-3 / P1-4 / P1-6 push / P2-2** | Unchanged from the 2026-08-12 triage; their gates stand: B3.3, B3.4, B3.6, B3.7, B3.8, B4.1, B4.2, and backtesting as ladder level (d) |
| **P2-3** visualization | Unchanged: each item is the human half of a gated object. It lands when its object does, per the two-way rule — not as a separate wish |

Two items in this table are worth reading twice. The tax-staleness warning
(#667) was **specified out of this agent's own previous document** and shipped
within two days of it; the agent does not know. And the "how well did I sell"
surface it has asked for twice now exists. Both reinforce §0.1: the feedback
loop delivers, and the delivery is invisible to its addressee.

---

## Part 2 — What is genuinely new

### 2.1 — P0-6: an append-only research log per security. **New, and the strongest item in the document.**

The agent nominates this itself as the single feature that would make the
largest difference, and the case it makes is sound. Verified: `securities.note`
is one `:string` column (`catalog/security.ex:21`); `attributes` is a free map.
Every write to either replaces what was there. Into that one field the agent
currently presses a thesis, invalidation criteria, quarterly results, buying
blocks, counterparty warnings — and withdrawn false alarms.

The requested object: `security_id`, `created_at`, `author`, `kind`
(`thesis` · `evidence` · `invalidation_check` · `event_result` · `risk` ·
`retraction` · `decision`), `body`, `source_url`, `source_quality`, `as_of`
(the statement's cut-off, not the write's), `supersedes`, `valid_until`. Four
list queries and a full-text search.

**Why this is not "widen the note field":**

- **`retraction` is the point, and it is the part that is not obvious.** The
  agent reports the same premise being re-raised in successive weekly runs and
  refuted each time, because "checked on date X, premise refuted, forecast
  withdrawn" has nowhere to live next to the position. A log that drops
  disproved findings reproduces exactly the error it exists to prevent. This is
  the first requirement in three rounds of agent feedback that asks the system
  to remember *being wrong* — which is the same instinct behind B4.2's
  calibration report, and the reason both are worth more than they cost.
- **`as_of` separate from `created_at`** is the P3 freshness principle applied
  to a statement rather than a datum, and it is what makes the log queryable
  for review hygiene at all.
- **`supersedes` and `valid_until`** are what let the *current state*
  (B4.1/FR-45) be derived from the log instead of maintained beside it.

**Where it belongs.** The agent proposes promoting P1-1 (theses and conviction,
gate **B4.1**, FR-45) to P0 and building both as one thing. **Recommend
accepting that,** with the framing sharpened: the log is the evidence chain,
the thesis fields are the state, and a state without its chain cannot say why
it flipped — which is the entire reason the current `thesis_status` file is
dead. One ADR, one object family, one gate.

Three things that must be in the gate rather than discovered during the build:

1. **The audit journal is a prerequisite and is still unscheduled.** The
   2026-08-12 triage recorded that the journal rollout is incomplete and that
   agent-written objects need it first. Two rounds later nothing has been
   scheduled. Note-writing is an agent write path by design (the agent is the
   author), so this stops being a background finding and becomes a dependency
   with a date.
2. **`author` must distinguish agent, local model and owner** — and per NFR-10,
   anything a model extracted is a proposal carrying `machine_generated` and
   its source until confirmed. That rule already exists; the log is its first
   home outside the PP import.
3. **The human view lands with it, not after it.** A research timeline on the
   security detail pane is cheap and it is what makes the log auditable by the
   person who owns the decisions. Under the two-way rule it is due in the same
   or the next batch anyway; building it in the same batch avoids a third entry
   in the human-view-debt ledger.

**Scope discipline for v1:** the four list queries are acceptance criteria in
disguise and should be built. Full-text search over all entries is a different
capability with different costs — recommend deferring it to v2 and stating that
in the ADR, rather than letting it ride in unpriced.

### 2.2 — The corrected limit rule in P0-2 sharpens the 2026-08-12 verdict rather than softening it

The agent corrects its own earlier rule: a sell limit belongs on the ask side
and a buy limit on the bid side, because the previous formulation gave away the
spread. Taken at face value that is a better rule. It is also, stated plainly,
**an instruction for capturing spread on an execution** — which moves it
further from "is the allocation off?" and further into *how* a trade is placed.

The 2026-08-12 triage cut limit suggestions from the digest's first version as
order preparation, under the ADR-0023 boundary. **That verdict stands, and this
correction is evidence for it, not against it.** If Andi wants limit
suggestions, they are an ADR-0023 amendment argued on their own merits — a
display-only price band beside a drift figure, with an explicit statement of
why it is not order preparation — never a field that arrives inside a digest
story.

The rest of P0-2 (gate **B3.5**) is unchanged, including the second cut: the
per-trade tax estimate stays out of v1 until forward projection has its own
gate (ADR-0031 deferred it deliberately). The digest carries recorded pot state
and trim budget — facts we hold — and not an estimate we would have to invent.

### 2.3 — Two small requirements inside old items that should not be lost

- **P0-4:** "a purchase candidate with zero holdings is monitored exactly like a
  held position." Already carried as a design constraint across B3.3/B3.4 since
  2026-08-12. Restated here because this edition supplies the concrete failure:
  the agent's local collector rebuilds its calendar from holdings and therefore
  cannot see the candidate whose dates matter most. Our catalog is
  holdings-independent, so the constraint costs nothing — as long as it is
  written into the gate.
- **P0-4:** "`source_quality` is **set, not guessed**; if derived, then
  traceably and overridably, and a manual correction is never overwritten by
  the next collection run." This is B2.2 from the last round, and it is now
  requested twice. It belongs in B3.3/B3.4 as a stated invariant, and it
  applies verbatim to P0-6's `source_quality` field.

---

## Part 3 — Recommended sequencing

Nothing below is committed. Sprint 8's work is merged and its close-out is the
next scheduled act; this is the shape I would give Sprint 9.

**Immediately, no gate, small:**

1. **Close the FR-37 surface gap** (§0.3) — **filed as #740**:
   `include_positions` on the view-scoped valuation, API and MCP together, and
   a drift threshold on `targets.list_positions`. This is what stands between
   the agent's acceptance criterion 1 (≤ 5 calls for the weekly run) and
   reality for a view-scoped operator. It is also a close-out finding by the
   standard of the rule that shipped FR-37.
2. **Document the re-import guarantee** — **filed as #741**. It is the reason a
   refuted claim survived into a second edition, and it costs a documentation
   pass.
3. **Agent discoverability** (§0.1): the cheapest honest version is a
   contract-version read the agent can poll — not a changelog document. It is
   specified inside the gate below rather than filed separately, because
   deciding what an agent may ask about the surface belongs with deciding what
   the agent may store on it.

**The gate, in parallel and with no code:**

3. **B4.1 + P0-6 as one ADR** — the thesis state and its evidence log, with the
   journal dependency, the `author`/`machine_generated` rule and the human
   timeline named in the gate. Highest new value in the document.

**Then, unchanged from the 2026-08-12 ordering:**

4. **Audit-journal rollout completion** — now a dated dependency of item 3,
   not a background note.
5. **B3.6** policy rules as objects → unlocks the rule-status view and the
   digest's flags.
6. **B4.2** predictions and calibration — small, and it produces the honest
   failure mode this system should have more of.
7. **B3.4** security events, manual and API/MCP population first; **B3.5** the
   digest without limit suggestions and without estimated tax; **B3.3**
   collection with collector health; then B3.8, B3.7, backtesting.

---

## Part 4 — Answers to the document's open questions (its appendix B)

1. **"Does the log survive a PP re-import? For classification and target
   weights the documented answer is no."** — **The premise is wrong, and the
   answer for the log is: it will, by the same guarantee.** Issue #664 verified
   this on synthetic fixtures in Sprint 6 and left the assertions in the tree as
   a permanent regression guard (`test/portfolixir/imports/reimport_preservation_test.exs`):
   a re-applied export is a content-hash no-op that creates no securities and no
   transactions; classification assignments keep their rows and ids; every plan
   version, category and position target keeps its id and its exact `Decimal`
   value; the cash target is Decimal-exact; and `note` and `attributes` come
   back byte-for-byte identical, custom attribute keys included. The three
   annotated securities the agent left as a canary are no longer needed — the
   checked-in test replaces them. **The gap that remains is documentation**: the
   guarantee is pinned by a test nobody outside the repo reads, which is why the
   claim survived into a second edition. It belongs in the agent-facing docs.
2. **"Should the local model write structured fields, or only propose them?"** —
   **Propose only.** Unchanged standing rule (NFR-10): source link,
   `machine_generated` marker, explicit confirm step. Independent of whether a
   local model is ever adopted.
3. **"Multi-tenancy — should household separation become its own concept?"** —
   **No, not as a new concept.** Buckets and views are the mechanism
   (ADR-0018/0024); true multi-user support is parked (#340). Unchanged.
4. **"How deep should history go?"** — **Per object.** Rules, theses and now
   notes need real history; derived metrics need `as_of` plus guaranteed
   recomputability (ADR-0039); who-changed-what is the journal's job
   (ADR-0017). Unchanged.

## On the document's acceptance criteria

Still unusually good, and now partly measurable against reality:

- **2 (−70 % response volume): met and pinned** since 2026-08-14 — on the
  endpoints that got the parameters.
- **1 (≤ 5 calls for the weekly run): blocked by §0.3**, not by the digest. Two
  of the four heavy reads cannot be made cheap today no matter how the caller
  asks.
- **5 (a zero-holdings candidate is monitored like a position):** carried as a
  B3.3/B3.4 design constraint.
- **3 (no date, thesis or target weight lives in a local file):** a migration
  criterion — it belongs to a closing story after the objects exist, not to each
  one.
- **4 (a dead collector is visibly dead within a day)** and **6 (the
  calibration report needs no handwork):** adoptable verbatim once B3.3 and
  B4.2 exist.

---

## Part 5 — Decided here, and the one thing that is not mine to decide

The first version of this section put four questions to the owner. Three of
them were not owner questions — they were decisions this role is supposed to
make and hand over finished. They are made below, each with the rule it follows,
and any of them is overrulable by one sentence.

**Decided — the FR-37 surface gap is filed, not asked about.** Completing a
shipped requirement on the endpoints it skipped is not new scope; it is a
close-out finding by the standard of the rule that shipped FR-37, and
`AGENTS.md` says an idea discovered while working is filed immediately.
**#740.**

**Decided — the documentation gap is filed too.** A guarantee that exists only
as a test did not reach the consumer whose behaviour it should have changed:
that is what let the refuted re-import claim survive into a second edition.
**#741.**

**Decided — limit suggestions stay out, and the reason is recorded so the
request stops returning.** A limit placed on the spread side is an instruction
for *how* a trade is executed, which is what ADR-0023 and the permanent
non-goals in `AGENTS.md` draw the line against; the agent's own correction makes
that clearer, not less clear. This needs no new decision because the existing
one already covers it. If the owner wants it anyway, it is an ADR-0023
amendment argued on its own merits — never a field that arrives inside a digest
story.

**Decided — agent discoverability is ours, and it rides the gate below rather
than becoming a fifth question.** Three capabilities shipped in this round were
invisible to the consumer they were built for. For a product whose first user
is an agent, that is a product defect, and the smallest honest fix is a
contract-version read the agent can poll — the same shape as `?since=`, applied
to the surface instead of the rows. It is specified inside the ADR below.

**Not mine: the signature.** ADR-0026 step 1 requires an owner-signed decision
gate before a batch starts, and P0-6 + B4.1 is new scope — a portfolio tracker
storing investment theses is a product-identity commitment, even though the
identity gate already settled the principle (FR-45/FR-46 are in the requirements
inventory as decided in principle). So the ask is not a question in a chat: it
is **ADR-0044, drafted for signature**, carrying the object family, the journal
dependency, the human timeline, the v1 scope cut (the four list queries in,
full-text search out) and the discoverability read. Sign it, amend it, or reject
it — that is the whole owner action.

## Part 6 — What goes back to the agent

The appendix-B questions in the source document are the agent's questions to
*us*; Part 4 answers them. Those answers do not reach the agent by being
committed here — it does not read this repository, which is the same failure
mode as §0.1 one level up. The following is what has to travel back, and it is
worth sending before the next weekly run rather than after:

1. **P0-1 is built.** `fields=`, `projection=`, `include_positions=false` and
   `min_drift=` exist on the endpoints listed in Part 0, over API and MCP, and
   the measured saving is already the one it asked for. Two reads are still
   missing them (#740) — those two, not the family.
2. **`?since=` exists** on securities and transactions, pull-only, with
   deletions deliberately unrepresented and that stated in the payload.
3. **The re-import claim is false** and has been since 2026-08-14, with the
   detail in Part 4. It should stop being carried as a premise — in particular
   it is not a blocker for P0-6.
4. **The tax-staleness warning it asked for is built** (#667), including the
   activity-aware condition, and the allowance-order object exists and is
   simply unfilled.
5. **Limit suggestions are out**, with the reason in Part 5, so the next edition
   need not re-argue it.
6. **P0-6 is accepted in principle** and is going to a signed decision as
   ADR-0044; the `retraction` requirement is the part that carried the case.
