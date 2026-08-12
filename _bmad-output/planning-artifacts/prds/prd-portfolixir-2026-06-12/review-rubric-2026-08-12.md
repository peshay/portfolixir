# PRD Quality Review — Portfolixir (identity gate B3.1 update)

Reviewed: `prd.md` and `addendum.md` in
`_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/`, as updated
2026-08-12, against `.claude/skills/bmad-prd/assets/prd-validation-checklist.md`.
Cross-checked against the source brief
(`briefs/brief-portfolixir-2026-08-12/`), `epics.md` and the amended
`AGENTS.md`.

**Verdict: strong document, two self-contradictions that block it being used as
the identity reference.** The gate's substance landed well — FR-1's rewrite
names four binding properties instead of a vibe, OQ-13 records the FR-26 gap
rather than papering it, and the metric quality bar ("a metric without a
definition is an opinion with decimal places") is a real review gate. But the
brief's permanent non-goal list was copied verbatim into a document that still
carries Phase 3 broker sync as an operator must-have, and the registry
precedence rule now points downstream readers at an inventory the PRD's own
addendum records as stale. Both are paragraph-sized fixes; until they land, the
PRD answers "who is this for and how far does it reach" twice, differently.

## Dimension judgments

| Dimension | Judgment |
|---|---|
| 1. Decision-readiness | **strong** — decisions are stated as decisions; the persona contradiction and the unmeasured central bet are the exceptions |
| 2. Substance over theater | **strong** — no furniture; two personas, both load-bearing; NFRs are product-specific |
| 3. Strategic coherence | **adequate** — thesis intact, but the new metric set collides with the new read-ergonomics family and skips the update's own headline change |
| 4. Done-ness clarity | **thin** — the ladder opens the largest new surface in the document and its only acceptance criterion is self-description |
| 5. Scope honesty | **thin** — omissions are usually explicit, but the non-goal list and the gate enumeration now contradict live scope |
| 6. Downstream usability | **adequate** — good pointers, one actively harmful one |
| 7. Shape fit | **strong** — capability-spec shape is right; §3 was not carried forward with the rest |

Requirement numbering absent from §5H is **by design** (registry authority sits
with `epics.md`) and is not treated as a finding anywhere below.

---

## Critical

### C1 — A permanent non-goal cancels a committed phase (§4 "Permanent non-goals" vs §4 "Phase 3", §5E, NFR-4)

§4 states, under a heading that says these are identity: *"These are not
'later'. They are what the product is not, and no capacity argument reopens
them: **no broker connection**, no order creation or transmission, no automated
trading or payment, no advice, no raw news archive, no external LLM calls from
the app."*

Forty lines earlier the same section says: *"**Phase 3 — Read-only sync.**
Operator-stated **must-have** — the scope gate below governs *when and how*,
not *whether*. Sources: comdirect REST API (depot, official API,
OAuth2+PhotoTAN), bunq API (cash accounts), bitcoin.de…"* — and FR-17 commits
to *"comdirect: depot positions and transactions via the official REST API"*,
while NFR-4 permits *"read-only sync only (Phase 3+)"*.

comdirect is a broker. The document therefore says both that a broker
connection is permanently out of scope and that a read-only broker connection
is a must-have whose gate governs only timing. The brief's list was written
without Phase 3 in view; the PRD inherited it unreconciled. This is the single
most consequential sentence pair in the document, because NFR-9 makes the
non-goal list mechanically enforceable ("no bank-domain HTTP configuration"),
so an agent implementing the meta-test has to choose which sentence is true.

*Fix:* qualify the non-goal as written in the sync context — e.g. "no
*order-capable* broker connection; read-only data acquisition is Phase 3 and is
governed by its own gate (OQ-1b)" — or state that Phase 3 is withdrawn. One
sentence, either way, but it must be decided rather than left to the reader.

### C2 — The precedence rule points at text the PRD knows is superseded (status note, §5 "Registry authority", addendum "Two pre-existing inconsistencies")

The status note instructs: *"read `epics.md` for what is currently committed.
Where the two disagree, `epics.md` wins."* §5 repeats it: *"the live FR registry
is `_bmad-output/planning-artifacts/epics.md`."*

The addendum then records, without fixing it: *"`epics.md`'s Requirements
Inventory carries a pre-2026-07-25 copy of FR-1..FR-29 — for instance FR-4 still
describes portfolios as partitioning the wealth space, which ADR-0024
superseded."* That is confirmed: `epics.md` line 39 reads *"FR-4: Portfolios
partition the wealth space; every view/analytic can be scoped to one
portfolio"*, while the PRD's FR-4 reads *"**portfolios** remain as an internal
compatibility record only (ADR-0024) and are not a user-facing concept."*

So the PRD's own conflict rule hands a downstream agent the superseded
definition of the product's core scoping concept, and the correction lives in an
addendum that §5 never points to. The addendum itself notes the cost: *"The
PRD's own registry note already says `epics.md` wins on conflict, which makes
this drift more expensive than it looks."* Recording a known-harmful instruction
is not the same as not issuing it.

*Fix:* scope the precedence rule to where it is true — "`epics.md` is
authoritative for FR-30 and beyond and for issue mapping; for FR-1..FR-29 this
PRD is the corrected text until the inventory is reconciled" — and file the
reconciliation. Two sentences.

---

## High

### H1 — The identity gate states the third persona's status twice, oppositely (§1 "Stakes and quality bar" vs §2, OQ-10)

§1: *"An instance today has an unauthenticated web UI (NFR-4, OQ-8) and no
release, versioning or upgrade story (OQ-10); the 'future self-hosters' persona
stays dormant until those exist."*

§2: *"**Everyone else who self-hosts it — the deployment model, not a growth
target.** … This is no longer a dormant persona, but it carries a standing
caveat rather than a commitment."*

OQ-10 sides with §1: *"Owner: maintainer, before the future-self-hoster persona
stops being dormant."* §2 was rewritten from the brief; §1 and OQ-10 were not.
For a gate whose entire product was "who Portfolixir is for", answering it twice
in one document is the expensive kind of drift — and the two readings imply
different obligations (OQ-8 and OQ-10 as blockers vs. as caveats).

*Fix:* pick the §2 wording (it is the newer decision) and rewrite §1's clause
and OQ-10's trigger to match — dormancy is replaced by a documented caveat, not
by a commitment.

### H2 — The PRD withdraws more scope than the binding amendment does (§4 "Scope ladder", Glossary)

§4: *"The blanket rule *'do not add advanced reports or advanced
classifications'* is withdrawn and replaced by a bounded ladder."* The Glossary
repeats it: *"Scope ladder | The bounded replacement for the retired 'no
advanced reports' rule."*

The amended `AGENTS.md` withdrew only half of it and says so explicitly:
*"Advanced *classifications* remain out of scope; the ladder covers analytics
only."* The PRD's sentence releases classifications that the binding document
still forbids. NFR-9 names exactly this failure mode one page later: *"a gate
that lifts partially is exactly the kind a reader mistakes for lifted
entirely."*

*Fix:* "the *analytics* half of the blanket rule is withdrawn; advanced
classifications remain out of scope," matching `AGENTS.md` word for word.

### H3 — The hard-gate enumeration is stale against its own section (§4 opening vs §4 "Gated, not in", NFR-9)

§4 opens: *"**Three are hard gates and cannot be entered without their ADR:**
Phase 3 (sync), FR-5's XML intake, and FR-12's rebalancing guidance (the last of
which has since been opened by ADR-0023)."*

Twenty-five lines later the same section adds four more: *"**Gated, not in:**
ladder level (d); data acquisition beyond quotes and FX (gate B3.3); push
delivery to external endpoints (gate B3.7); a local model beyond the
already-gated ADR-0021 PDF-intake path (gate B3.8)."* NFR-9 gives a third,
different set: *"Phase 3 sync, FR-5 XML intake, and — since 2026-08-12 — the
permanent non-goals and the level-(d) backtesting gate."*

Three enumerations of the gate set, no two identical, in a document whose
scope-control mechanism *is* the gate set. A reader who stops at the opening
sentence concludes that push delivery and local-model work need no gate.

*Fix:* one canonical gate table in §4 (gate, what it blocks, where its ID
resolves, whether it is open/dormant/hard), with NFR-9 and the "Gated, not in"
list referencing it instead of restating it.

### H4 — The ladder's quality bar mandates disclosure, not definition (§4 "Quality bar for every metric in (a)–(c)", §5H H2/H3)

The bar reads: *"it ships with its computation basis stated in the API and MCP
payload — input series, window, reference series or benchmark where one exists,
and the treatment of gaps. This is a review gate, not a documentation chore."*

That makes the *statement* testable and leaves the *choice* unowned. Nothing in
the PRD or in OQ-14 says who decides whether realized volatility is annualized,
over which trading-day convention, or what "momentum" and "distance to extremes"
mean numerically. Two implementations can both pass the review gate and produce
different numbers for the same security. In a product whose operator requirement
is stated as *"trust a figure without checking it elsewhere"* (§2), a metric's
definition is the requirement, not its metadata — and §5H's H2/H3 carry no
testable consequence of their own beyond *"The existing risk and concentration
endpoint is the shape to extend, not a thing to replace."*

Note this is not covered by delegating numbers to `epics.md`: FR-39–FR-42 there
are capability lists too, and the cross-cutting rule they carry is the same
disclosure rule.

*Fix:* add an OQ owning the definitional conventions (who fixes windows,
annualization, gap treatment — the PM/owner with the first ladder-(a) story), or
state that each metric's discovery story fixes them, as Phase 4 already does for
FR-22–FR-25 (*"each FR preceded by a discovery story"*).

### H5 — §3 was not carried forward with the rest of the update (§3 User Journeys vs §1, §5H)

§1 now says the founding failure is that *"the fact had no home with an
identity"*, and §5H builds four object families to fix it. §3 is unchanged from
before the gate: six journeys covering briefing, import, cash, retirement,
podcast backtest and scope switching. Not one shows a thesis being recorded, a
prediction resolving, a policy rule firing, or an upcoming security event
surfacing for a security with no holdings — even though Success Metric 7 is
exactly that scenario (*"A purchase candidate with no holdings is monitored for
upcoming dates exactly like a held position"*).

UJ-5 meanwhile still narrates the podcast backtest as if live (*"The what-if
engine simulates virtual trades against real quote history"*) although §4 just
moved it under the level-(d) gate — the journeys now advertise the one thing the
gate closed and skip everything it opened.

*Fix:* one new UJ for the knowledge-object loop (record thesis → prediction →
resolution → calibration), and a gate marker on UJ-5 matching the §5C treatment
of FR-27.

### H6 — Success Metric 2's instrument is invalidated by the new H1 family (§7 Metric 2 vs §5H H1)

Metric 2's instrument: *"server-side count of MCP sessions per week that answer
these questions **without** a bulk `securities_list`-style pull — the absence of
client-side arithmetic is not observable, but the bulk pull that would enable it
is."*

§5H H1 now makes projected reads the intended path: *"Per-endpoint field
selection and projections, roll-up-only aggregates that omit positions,
server-side threshold filters…"* — generalizing FR-33, whose worked example is
*a slim `securities_list`*. After FR-37 ships, a `securities_list` call is no
longer evidence of client-side arithmetic; it is the recommended read. The
proxy's logic ("the bulk pull that would enable it") stops holding precisely
when the programme succeeds.

*Fix:* re-express the detector in terms the new surface supports — e.g. "no
unprojected full-collection read", or response-volume above a threshold — since
FR-37 makes that distinction observable server-side.

### H7 — The update's central bet has no success metric (§1 "Second cornerstone", §7, NFR-8)

The largest change in this revision is FR-1's durable derived layer, motivated
in §1 as *"the operator waits while a page computes what it computed last time,
and the agent burns a context window reconstructing figures the server could
have handed over finished."*

§7 gains five agent-side criteria — all of them about call counts, response
volume, file migration, event coverage and calibration — and one counter-metric,
*"Silent staleness"*. None of them moves if the derived layer never ships:
metrics 4 and 5 are satisfied by FR-37/FR-38 read ergonomics alone. The only
statement about the felt symptom is NFR-8, which the same document marks
*"currently **aspirational**: `project-context.md` lists performance/load gates
as deliberately not adopted, so no instrument measures it"*, and then adds *"It
does not supply the missing instrument."*

So the riskiest structural change in the document — introducing stored derived
state into an auditability-first ledger product — carries a guard against its
failure mode but no evidence of its benefit. §7's own rule is *"A metric without
an instrument is an intent, not a metric"*; here there is not even the intent.

*Fix:* one instrumented criterion tied to FR-1 (a named page or MCP analytic,
its current cost, its post-layer target on the reference dataset), or an
explicit statement that the derived layer is justified structurally and will not
be measured — the second is acceptable, the current silence is not.

---

## Medium

### M1 — Two gates plausibly govern the same acquisition work (§4 "Gated, not in" vs §4 Phase 3, OQ-1b)

*"data acquisition beyond quotes and FX (gate B3.3)"* is listed as gated, while
Phase 3 acquires depot positions, transactions and cash balances — data beyond
quotes and FX — under a different gate (*"entering Phase 3 requires (a) an ADR
plus AGENTS.md amendment…"*, OQ-1b). The brief's addendum scopes B3.3 to signal
collection (*"condensed dated signals with source links, never a full-text
archive"*), but the PRD's phrasing does not carry that limit, so a reader cannot
tell whether Phase 3 now needs B3.3 as well. *Fix:* qualify as "data acquisition
beyond quotes, FX and the Phase 3 sync sources (gate B3.3 — external signals)".

### M2 — Two new metrics use the deliverable as their own instrument (§7 Metrics 7 and 8)

*"A purchase candidate with no holdings is monitored for upcoming dates exactly
like a held position. *Instrument:* the security-event query for a catalog entry
with zero holdings returns its dates."* and *"The calibration report is available
without manual work after ten resolved predictions. *Instrument:* the report
itself."* Both reduce to "the feature exists" — shipped/not-shipped, not a
measurement. Metric 6 got the honest caveat (*"unmeasurable until they do"*) and
metric 3 got *"treated as unmeasured rather than unmet"*; 7 and 8 depend on
gated objects (FR-44 behind B3.4, FR-46/FR-47 behind #677) and carry no such
note. *Fix:* add the same caveat, and give metric 8 a measurable form (e.g.
calibration produced for ≥ 10 resolved predictions without manual data
assembly).

### M3 — §5H gives no family → FR mapping (§5H preamble)

*"the numbered requirements (FR-37 and beyond) live in `epics.md`, which is the
registry"* — correct by design, but the PRD never says which FR range each of
H1–H5 corresponds to, while `epics.md` does carry the back-pointer (*"the PRD
describes these as families in its section 5H"*). A reader arriving from the PRD
must reconstruct H2 → FR-39/FR-40 by matching prose. This is a pointer, not a
duplicate registry. *Fix:* one column or one clause per family: "H1 → FR-37,
FR-38; H2 → FR-39, FR-40; H3 → FR-41, FR-42; H4 → FR-47, FR-48; H5 → FR-43..46".

### M4 — Gate IDs are used 18 times and resolved zero times (whole document)

B3.1, B3.2, B3.3, B3.4, B3.6, B3.7 and B3.8 appear throughout (*"gate B3.2's
ADR"*, *"revisit after the policy-rules work (gate B3.6)"*, the §5H table's Gate
column), but no sentence says where a gate ID resolves. The brief's addendum
does — *"where the gate IDs resolve in
`planning-artifacts/feedback-triage-2026-08-12.md`"* — and the PRD does not
carry it, nor does the Glossary define "gate". *Fix:* one line in §4 plus a
Glossary entry.

### M5 — The agent-first deadline has an enforcer but no instrument (§4 "Two working rules", §7)

*"The human view then lands in the same or the next epic batch, and its absence
after that is a close-out finding. Without the deadline this rule quietly
degrades into 'agent only, forever', which would hollow out the operator half of
the identity above."* The PRD names the degradation risk itself, and the whole
operator-side metric set is deliberately qualitative (*"Operator-side criteria
stay qualitative, deliberately"*). The counter-metric list — correctness
incidents, reconciliation drift, gate health, silent staleness — has nothing for
it. Given that this update pushes the agent ahead structurally, the one rule
protecting the human half rests entirely on a reviewer remembering. *Fix:* add a
counter-metric — e.g. "count of shipped agent-only capabilities with no human
view older than one batch: target zero" — which is countable from the epic
close-outs the rule already requires.

### M6 — NFR-8 remains an aspiration while being cited as motivation (§6 NFR-8, §1)

*"p95 < 2 s on commodity home-server hardware… This is currently
**aspirational**… no instrument measures it. Either a named benchmark harness
and dataset land with the first FR that depends on it, or the number stays
labelled as an intent."* The conditional now has a trigger: FR-1's derived layer
is a performance-motivated change, and §1 argues from responsiveness (*"it can
afford to compute continuously in the background"*). The PRD's own escape clause
therefore fires and is not acted on. Related to H7; separate because the fix is
different. *Fix:* name the harness and dataset as a deliverable of the B3.2 ADR,
or delete the numeric p95 and keep only "correctness always beats speed".

### M7 — "No advice" is reconciled for FR-26 only (§4 "Permanent non-goals", §5C FR-12, §4 ladder level (c), OQ-13)

OQ-13 handles the sharpest case honestly (*"a sustainable-withdrawal curve sits
closer to that line than any analytic currently shipped"*). But the same
non-goal (*"no advice"*) sits beside FR-12's *"ranked 'where new cash goes' and
'where needed cash comes from'"* — bounded by ADR-0023 but not by the non-goal
sentence — and beside ladder level (c), *"Evaluation of decisions… Prediction
calibration, rule evaluation, signal quality"*. The boundary that makes these
compatible ("the system prepares decisions; the operator executes them") is
stated once and never applied to the ladder. *Fix:* one clause in the ladder
saying that levels (b)–(c) evaluate past decisions and never recommend a
transaction, which is the distinction already doing the work in ADR-0023.

---

## Low

### L1 — An `[ASSUMPTION]` added on 2026-08-12 is not indexed (§7 "Operator-side criteria")

*"Two cheap proxies if one is ever wanted: no view opens on a placeholder that
has to fill itself in, and Portfolio Performance stops being opened for
questions Portfolixir should answer. `[ASSUMPTION]` — proposed, not
requested."* The document's other three assumption tags round-trip into OQ-2 and
OQ-3; this one has no owner and no OQ. *Fix:* an OQ, or drop the tag and mark it
"not adopted".

### L2 — Glossary gaps on terms the update made load-bearing (§9)

The Glossary gained "Derived layer", "Scope ladder", "Knowledge object",
"Security event" and "Calibration" — good. It still omits **"analytics
register"**, which FR-13 bold-defines and Phase 2 depends on (*"a
machine-readable list of computed analytics maintained in the repo"*), **"gate
B3.x"** (see M4), and the Sprint 5 **value-slot vocabulary** (pending /
settling / final / not-computable) that the addendum calls *"the UI half of
FR-1's freshness property"*.

### L3 — The compute-continuously argument is made three times (§1 second cornerstone, §1 Positioning, §6 NFR-8 note)

*"one instance with one dataset can afford to compute continuously in the
background"* (NFR-8) restates *"which is precisely why it can afford to compute
continuously in the background. Larger systems cannot spend compute that
casually. This one can."* (§1 Positioning), which restates the second
cornerstone's framing. §1 is now roughly a third of the document before the
first requirement. Not wrong — just three payments for one idea.

### L4 — One reference is a bare filename (§7 agent-side criteria)

*"sources sit in `feedback-triage-2026-08-12.md`"* — every other cross-document
reference in the PRD carries its path
(`_bmad-output/planning-artifacts/epics.md`). *Fix:* use the full path.

### L5 — FR-1 names a mechanism inside a section that forbids mechanisms (§5 preamble, FR-1)

§5 opens *"Capabilities, not implementation."* FR-1 then binds *"**versioned**
against the existing data-version counter"*. Defensible (the addendum notes it
is *inherited* from ADR-0032, not invented) but it is the one place where the
section's own rule bends. *Fix:* "versioned against a data-version mechanism
(today's counter, per ADR-0032)".

### L6 — Gate B3.5 is described but never named (§5H "What this section deliberately does not absorb")

*"limit-price suggestions… and estimated per-trade tax"* are excluded with
reasons, but without the gate ID the brief's addendum assigns them (B3.5), while
every other exclusion in the document carries its ID. *Fix:* add "(gate B3.5)".

---

## Mechanical notes

- **ID continuity:** FR-1..FR-29 present and unique; sub-IDs FR-9a/b/c and
  FR-14a–d resolve; the interleaved numbering is explained in the §5 preamble
  (*"That is deliberate, not an editing error"*). NFR-1..NFR-10 and UJ-1..UJ-6
  contiguous. OQ-1a/1b/1c plus OQ-2..OQ-14 contiguous, with OQ-1c marked
  resolved and OQ-1a dormant. §5H's H1–H5 are lettered, not numbered — correct
  per the registry rule.
- **Cross-references checked against `epics.md`:** FR-33, FR-35, FR-36 and #677
  resolve; #665/#666 map to FR-37/FR-38 as stated; the §5H sequencing paragraph
  matches `epics.md`'s binding note on FR-43..FR-46 almost verbatim. UX-DR11
  (OQ-14) resolves in `design-language/`.
- **Assumptions roundtrip:** four inline tags, three indexed (UJ-4 → OQ-2, FR-9
  → OQ-3), one orphaned (L1). Open Questions still doubles as the assumptions
  index without being labelled one — carried over from the previous review,
  still cosmetic.
- **Glossary drift:** the same object is called *"durable derived layer"* (§1),
  *"materialized value"* (FR-1, NFR-2, counter-metrics), *"derived layer"*
  (Glossary) and *"the layer"* (§1). Consistent enough to follow; the Glossary
  entry anchors it. "Depot" and "view/bucket/portfolio" are used consistently
  with ADR-0024 throughout, including in the new sections.
- **Frontmatter:** `status: superseded-in-part`, `updated: 2026-08-12` — accurate
  and unusually honest for a founding-intent document, and it is what makes C2's
  precedence rule so load-bearing.
- **Addendum:** now referenced only implicitly; the previous review's finding
  ("the addendum is never referenced from the PRD") still stands, and C2 raises
  its cost, because the correction to the stale `epics.md` inventory lives only
  there.
- **Privacy:** no financial values, household details or local paths in either
  file; the addendum's privacy-scope paragraph is restated and still governs.
