# Consistency and edge-case review — identity gate B3.1 (2026-08-12)

**Reviewer role:** edge-case and consistency hunter (internal contradictions,
unhandled cases).
**Scope:** the four commits on this branch against `origin/main`
(`f636e1c`, `283217a`, `1fa44e0`, `90ccbd8`) — `prd.md`, `addendum.md`,
`.decision-log.md`, `epics.md`, `AGENTS.md`, `README.md`, `docs/index.md`.
**Method:** repo-wide search for the retired rule and for the FR-1 wording,
per-FR status trace for FR-9/FR-10/FR-26/FR-27, boundary probing of the new
ladder text, obligation-conflict check against the rest of `AGENTS.md`, and a
read plus an actual run of the doc meta-tests
(`mix test test/portfolixir/docs_test.exs test/portfolixir/workflow_docs_test.exs test/portfolixir/ci_test.exs`
→ **21 tests, 0 failures**; nothing in this change breaks a meta-test today).

**Verdict: request changes.** The scope ladder is a genuine improvement over
the blanket rule and the document is unusually honest about its own gaps
(OQ-13, OQ-14, the partial gate lift, the recorded pre-existing drift). But the
amendment does not reach the two public documents that carry the same rules
(`CONTRIBUTING.md`, `_bmad-output/project-context.md`), it widens a claim about
mechanical backstops that were never built, and one ladder level contradicts a
sentence in the same `AGENTS.md` bullet.

---

## Critical

### C-1. "Advanced *classifications* remain out of scope" forbids ladder level (b)

`AGENTS.md` (amended):

> - **(b) comparison and decomposition** — benchmark, contribution analysis,
>   factor/sector/region exposure: **allowed**;

…and eight lines later in the same bullet:

> Advanced *classifications* remain out of scope; the ladder covers analytics
> only.

The project's only published definition of the retired term is in
`CONTRIBUTING.md:39`:

> - advanced classifications (e.g. splitting one security across categories with
>   partial weights).

Factor, sector and region exposure for anything other than a single-sector
single-country equity **is** splitting one security across categories with
partial weights — that is what decomposing an ETF or a multinational into
sector/region buckets means. So FR-42 in `epics.md`

> - FR-42: **Exposure decomposition** (ladder level (b)): factor, sector and
>   region exposure.

is simultaneously "allowed" by the ladder and "out of scope" by the sentence
that closes the same bullet. The decision log shows this was deliberate —

> - 2026-08-12 — **Advanced *classifications* stay out of scope.** The retired
>   hard rule covered reports *and* classifications; the ladder covers analytics
>   only.

— but the carve-out was written without checking it against level (b), and the
term is never defined in `AGENTS.md` itself, so the only definition a reader can
find is the one that contradicts FR-42. **Fix:** either define "advanced
classification" narrowly in `AGENTS.md` (persisted partial-weight *assignments*
in the classification trees, as opposed to computed exposure figures that store
nothing), or state explicitly that FR-42's decomposition is a derived analytic
and not a classification. As it stands, the first FR-42 story has a defensible
review-reject waiting for it.

### C-2. NFR-9 now asserts mechanical backstops for two more gates that do not exist

`prd.md` NFR-9, as amended:

> - **NFR-9 Mechanical scope backstop:** the hard gates (Phase 3 sync, FR-5
>   XML intake, and — since 2026-08-12 — the permanent non-goals and the
>   level-(d) backtesting gate in place of the retired blanket analytics gate)
>   are backed by meta-tests in the invariant suite — a dependency allowlist, no
>   credential-bearing schema, no bank-domain HTTP configuration — …

`epics.md` repeats it:

> - NFR-9: … Since the identity gate the guarded set is Phase 3 sync, FR-5 XML
>   intake, the permanent non-goals and the level-(d) backtesting gate, in place
>   of the retired blanket analytics gate …

The invariant suite is `test/invariants/`, and it contains:
`blast_radius_widening_test.exs`, `cost_fold_kind_coverage_test.exs`, five
`css_*` tests, `decimal_persistence_test.exs`, `iso_date_input_test.exs`,
`mcp_dependency_allowlist_test.exs`, `native_dialog_test.exs`,
`projection_no_catch_all_test.exs`, `web_repo_boundary_test.exs`. Of the three
meta-tests NFR-9 names, only the dependency allowlist exists. There is **no**
"no credential-bearing schema" test, **no** "no bank-domain HTTP configuration"
test (`grep -rl "credential\|bank-domain\|fints\|hbci\|backtest" test/` returns
only two unrelated API controller tests), and nothing whatsoever guarding the
permanent non-goals or level (d).

Two of those three claims are pre-existing, and a reviewer could let them lie.
What makes this critical is that the change **extends** the false claim to two
new gates while asserting, in the same paragraph, that the retirement of the old
gate makes NFR-9 *more* load-bearing:

> The retirement of the analytics gate makes this *more* load-bearing, not less:
> a gate that lifts partially is exactly the kind a reader mistakes for lifted
> entirely.

That sentence is correct, and it is the argument for adding a level-(d)
meta-test in this batch rather than restating an unbacked inventory. NFR-9's own
closing clause names the failure mode this creates: "the project's most
consequential boundary is enforced by one person editing Markdown as author,
approver and enforcer". **Fix:** either add the guards (a grep-style invariant
over `lib/` for a backtest/simulation entry point and for broker/order/advice
surfaces is a dozen lines, in the style of
`test/invariants/projection_no_catch_all_test.exs`), or reword NFR-9 to state
which gates are backed today and which are aspirational. Do not leave a
requirement that describes tests that were never written.

### C-3. `CONTRIBUTING.md` still carries the retired rule and the one-way coverage rule

`CONTRIBUTING.md:30-39`, untouched by this change:

> Out of scope unless a reviewed story explicitly changes it:
> …
> - advanced reports;
> - advanced classifications (e.g. splitting one security across categories with
>   partial weights).

and `CONTRIBUTING.md:153`:

> Every new user-visible function must include JSON API and MCP companion
> coverage, or the PR must explain why coverage is not applicable.

`CONTRIBUTING.md` is a public, top-level contributor document; `docs_test.exs`
and `workflow_docs_test.exs` both treat it as a peer of `AGENTS.md`. After this
change it states, as current policy, a rule `AGENTS.md` describes as "the former
blanket rule", and it states the coverage rule in exactly the one direction the
amendment says is no longer the whole rule:

> Coverage runs **both ways** (amended 2026-08-12, identity gate B3.1). Either
> direction may lead; neither may be silently skipped.

`docs/development/story-workflow.md` has the same one-way gap ("API and MCP
coverage is part of the story contract. When a visible function is added or
changed…"). The change's own `AGENTS.md` text says the story workflow is
mirrored across four documents that must move together; three of the four did
not move. **Fix:** amend `CONTRIBUTING.md`'s Active Scope list and both
coverage sections in the same PR — but read H-7 first, because the obvious edit
breaks a meta-test.

---

## High

### H-1. The new permanent non-goal "no advice" contradicts the ADR-0023 bullet ten lines above it

`AGENTS.md`, consecutive Hard Rules bullets:

> Display-only rebalancing hints are an in-scope exception per ADR-0023:
> computing and showing indicative corrective quantities next to the
> allocation drift is allowed…

> - The permanent non-goals are identity, not backlog, and no capacity argument
>   reopens them: no broker connection, no order creation or transmission, no
>   automated trading or payment, **no advice**, no raw news archive, no external
>   LLM calls from the app.

"Show the operator how many shares to sell to correct the drift" is advice under
any plain reading; ADR-0023 spent a whole decision drawing the guidance-vs-action
boundary precisely because the two are hard to separate. The new bullet
introduces an absolute term ("no capacity argument reopens them") without
defining it and without pointing at the ADR that already drew the line. It also
collides forward: FR-43's "a violated rule is the retrievable alarm list", FR-45's
conviction tiers, and FR-26's sustainable-withdrawal curve are all closer to
"advice" than to "records". OQ-13 notices the FR-26 half of this —

> …given that "no advice" is a permanent non-goal and a sustainable-withdrawal
> curve sits closer to that line than any analytic currently shipped.

— which shows the author saw the tension for one FR and did not generalise it.
**Fix:** define the non-goal as ADR-0023 does (no order created, stored or
transmitted; no personalised recommendation to buy or sell a named security at a
named time), or cross-reference ADR-0023 from the non-goals bullet.

### H-2. `AGENTS.md` now makes a factually wrong claim about `workflow_docs_test.exs`

New text in `AGENTS.md`:

> The nine steps above are the canonical order and are asserted verbatim by
> `workflow_docs_test.exs` across this file, `README.md`, `CONTRIBUTING.md` and
> `docs/development/story-workflow.md` — change them in all four or in none.

Both halves are wrong.

1. `README.md` does not contain the nine steps at all
   (`grep -n "1\. User Story documented\." README.md` → no match; they are in
   `CONTRIBUTING.md:87`, `AGENTS.md:267`, `docs/development/story-workflow.md:15`).
   "Change them in all four" is not currently satisfiable, and an editor who
   obeys the instruction would add a nine-step process list to a README whose
   meta-test story is "readme is a concise project entry page".
2. The test does not assert the steps per file. It concatenates:

   ```elixir
   workflow_text = @workflow_docs |> Enum.map(&File.read!/1) |> Enum.join("\n")
   for step <- [...] do assert workflow_text =~ step end
   ```

   The assertion is satisfied by **any one** of the four files. Deleting the
   steps from three of them leaves the suite green. So the sentence also
   over-promises protection that is not there.

The same mistaken belief is recorded in `.decision-log.md` as the reason a tenth
step was not added —

> `workflow_docs_test.exs` asserts the nine steps verbatim across `AGENTS.md`,
> `README.md`, `CONTRIBUTING.md` and `docs/development/story-workflow.md` …
> Caught by reading the meta-test before committing, not by the test failing.

— which is the right instinct applied to a misread of the code. The *decision*
(keep nine steps) is fine; the *justification* now sits in a normative sentence
in `AGENTS.md` that future agents will act on. **Fix:** correct the sentence to
what the test does ("asserted as a set across the workflow docs; the canonical
list lives in `AGENTS.md`, `CONTRIBUTING.md` and
`docs/development/story-workflow.md`"), or make the test per-file and add the
list to `README.md` deliberately.

### H-3. The two-way coverage deadline conflicts with Scope Lock and has no place to be executed

`AGENTS.md`:

> - Every new **agent-visible** capability may ship over API and MCP alone, with
>   no human view, provided the PR states why. The human view then lands in the
>   **same or the next epic batch**, and its absence after that is a close-out
>   finding.

Three unresolved collisions, all inside `AGENTS.md` itself:

1. **Against the Hard Rules.** "Work only on the requested story or story
   batch." and "Do not add adjacent features." An epic batch is a feature tree
   with a signed-off decision gate (ADR-0026 step 1). The *next* batch is by
   definition a different tree; landing a leftover human view inside it is
   adding an adjacent feature to that batch. Nothing in the amendment carves an
   exception, and the Scope Lock section reinforces the opposite ("leave a
   follow-up note instead of solving it opportunistically").
2. **Against the close-out checklist.** Step 5 of the Epic-Batch Workflow
   enumerates the close-out duties (sprint-status, epics doc + FR Coverage Map,
   close issues, retrospective, CI green, annotated tag) and was edited in this
   very change to add the maintenance lane — but the human-view debt was **not**
   added. So "its absence after that is a close-out finding" names a finding
   that no listed close-out activity would produce. There is also no register of
   outstanding debts, so nothing carries the memory from the batch that incurred
   it to the batch that owes it.
3. **The consequence is undefined.** Elsewhere `AGENTS.md` grades obligations
   ("this is a review-blocking standard", "Weakening a quality gate to make a
   batch pass is a review reject"). "A close-out finding" has no defined
   severity — it does not say the batch cannot close, and close-out happens
   *after* the squash-merge, when the branch is gone.

The amendment states the risk correctly ("without it the rule degrades into
'agent only, forever'") and then does not build the mechanism that prevents it.
**Fix:** add one line to Epic-Batch step 5 ("confirm every agent-only capability
from this batch and the previous one has its human view, or record the debt in
the epics document"), which also gives the debt a durable home.

### H-4. FR-1's rewording never names ADR-0004 or `project-context.md`, which are where "never stored" actually lives

`prd.md` FR-1 instructs the future ADR to reconcile two ADRs:

> Which values are materialized is decided by the derived-value ADR (gate
> B3.2), which must supersede or amend ADR-0032 (today's memo is deliberately
> volatile) and argue explicitly against ADR-0035…

ADR-0004 is not in that list, yet it is the decision the retired wording came
from and the one every downstream artifact cites:

- `docs/decisions/0004-holdings-derived-from-transactions.md`, **Decision**:
  "…are derived from transactions on read, **not stored** or entered manually."
- `_bmad-output/project-context.md`, Critical Don't-Miss Rules #1:
  "**Holdings are never stored** — derived from transactions (ADR-0004; no
  holdings table exists). Wrong holdings ⇒ fix projection or data, **never add a
  table/cache**."
- `priv/repo/migrations/20260618120000_create_buckets_and_views.exs:52`,
  `lib/portfolixir/portfolios/performance/cache.ex:12`,
  `lib/portfolixir/buckets/position_bucket_override.ex:4`,
  `lib/portfolixir/portfolios/snapshot_comparison.ex:8`,
  `docs/architecture.md:83`, `docs/decisions/0027…:29`.

`project-context.md` is the file coding agents read before touching projection
code, and its rule #1 now says the opposite of FR-1 in operational terms ("never
add a table/cache"). The addendum's new section records two pre-existing
inconsistencies it deliberately did not fix (the LiveView version claim and the
stale FR-1..FR-29 copy in `epics.md`) — this third one, which the change itself
creates, is not recorded.

Mitigating: ADR-0004's Consequences already anticipate the reversal —
"if data volume ever makes this expensive, caching or materialised views would
be a future decision (new ADR)" — so FR-1 is compatible with ADR-0004's intent.
That is exactly why it costs one clause to say so. **Fix:** add ADR-0004 to the
B3.2 supersede/amend list, and add `project-context.md` rule #1 to the
addendum's "found while editing, not fixed here" section so the next agent is
not steered wrong.

### H-5. FR-48 (level c, in scope) is not distinguishable from level (d) (forbidden)

`prd.md` section 4:

> - **(c) Evaluation of decisions — in scope.** Prediction calibration, rule
>   evaluation, signal quality.
> - **(d) Backtesting rules against stored price history — out for now**, behind
>   its own decision gate.

`epics.md` FR-48:

> - FR-48: **Rule evaluation and signal quality** (ladder level (c)): whether the
>   policy rules of FR-43 are producing findings that turn out to matter.

"Turn out to matter" is a statement about what the price did *after* the finding
fired — i.e. evaluating a rule against stored price history. The only difference
from (d) is whether the rule was live at the time (forward record) or replayed
over history it never ran on (simulation), and **neither document draws that
distinction**. FR-47 (calibration) is safe because it consumes recorded
predictions with recorded outcomes; FR-48 is not. A first FR-48 story that
computes "of the 14 cap-breach findings in the last year, 9 preceded a drawdown
over the following 30 days" is a defensible reading of (c) and a defensible
reading of (d).

This is precisely the boundary the ladder was written to fix, and it is the one
place the ladder's own levels overlap. **Fix:** one clause on level (c) — "over
findings the rule actually produced while live; replaying a rule over history it
did not run on is level (d)."

### H-6. `README.md` claims a capability the PRD says does not exist

`README.md`, new prose:

> - *What did my agent base that on?* — the same figures the agent read over MCP,
>   each stating the age of its inputs, on a page a person can look at.

The addendum says the payload half of that is unbuilt:

> The Sprint 5 value-slot vocabulary (pending / settling / final /
> not-computable) is the UI half of FR-1's freshness property and already
> exists; **the payload half does not.**

and the PRD's new counter-metric confirms it is a future obligation, not a
present property ("no materialized value reaches a view or a payload without its
`as_of`"). `docs_test.exs` exists specifically to keep public docs from claiming
unbuilt capability (`@deferred_claims`); its literal string list will not catch
this one, but it is the same class of defect. The surrounding bullets are
carefully written as present capability ("moving-average cost basis, unrealized
P&L, and a price chart from local quote history" — all shipped), which makes the
third bullet read as shipped too. **Fix:** reword to intent ("…so a figure can
be traced to the inputs and the moment it was computed") or drop the clause.

### H-7. The follow-up edit C-3 requires will break `workflow_docs_test.exs`

`test/portfolixir/workflow_docs_test.exs`:

```elixir
assert workflow_text =~
         "Every new user-visible function must include JSON API and MCP companion coverage"
```

That exact string exists in exactly one file in the repo — `CONTRIBUTING.md:153`
(verified by grep across all four workflow docs plus `docs/development/guide.md`).
`AGENTS.md`'s own wording differs ("must include API and MCP coverage"), so
`AGENTS.md` does not satisfy the assertion. Consequence: the moment someone
rewrites `CONTRIBUTING.md`'s coverage section to be two-way — the fix C-3
demands — the meta-test fails, and the tempting repair is to keep the stale
one-way sentence alongside the new one.

This is the "load-bearing on a future innocent edit" case the review was asked
to look for, and it is live right now because the change deliberately left
`CONTRIBUTING.md` behind. **Fix:** in the same PR that amends `CONTRIBUTING.md`,
relax the assertion to the direction-neutral part (`"must include JSON API and
MCP companion coverage"` plus a second assertion for the agent-first direction),
so the meta-test guards both halves of the new rule instead of pinning the
retired half.

---

## Medium

### M-1. Gate B3.5 disappears between the brief and the PRD

The brief's addendum registers eight gates; B3.5 is one of them:

> - **Limit-price suggestions and estimated per-trade tax** (gate B3.5) — cut
>   from …

The PRD's gated list omits it:

> **Gated, not in:** ladder level (d); data acquisition beyond quotes and FX
> (gate B3.3); push delivery to external endpoints (gate B3.7); a local model
> beyond the already-gated ADR-0021 PDF-intake path (gate B3.8).

Section 5H and `epics.md` both describe the same two items as merely "not
absorbed":

> **What this section deliberately does not absorb:** limit-price suggestions
> (order preparation, not allocation guidance — it needs an explicit ADR-0023
> amendment decided on its own merits) and estimated per-trade tax…
> Anything on the gated list in section 4 is likewise out.

The final sentence is the catch-all — and because B3.5 is not on the section 4
list, the catch-all does not reach the two items above it. Net effect: the
brief's eight gates become seven downstream, and the one that vanished is the
one nearest the "no order creation" non-goal. **Fix:** add B3.5 to the section 4
gated list.

### M-2. FR-26: "neither released nor gated" vs OQ-13's owner precondition

Three places say FR-26 is not gated:

- `prd.md` section C: "**FR-26 is neither released nor gated, and that is a
  gap.**"
- `prd.md` section 4 Phase 4 note: "FR-26 falls outside the ladder entirely
  (OQ-13)."
- `epics.md` FR Coverage Map: "**Outside the scope ladder** … the 2026-08-12
  gate neither released nor gated it … **Not blocking:** no issue, Phase 5 not
  started".

OQ-13 says the opposite in effect:

> Owner: maintainer, **before the FR-26 discovery story.** Not blocking anything
> today…

Either an owner decision is required before the first FR-26 story (a gate) or it
is not (no gate). Read literally today, an agent may start FR-26 — a
sustainable-withdrawal curve, the analytic the PRD itself says "sits closer to
that line [no advice] than any analytic currently shipped" — with no gate to
stop it, because the section C box explicitly declares it ungated. Compounding
it, section G's heading changed to "(Phase 5 — gating revised 2026-08-12)"
without saying *to what*, so a reader who lands on FR-26 directly gets no status
at all. **Fix:** say "gated on OQ-13" in all four places, or say "ungated, and
OQ-13 is advisory". Pick one.

### M-3. FR-33's scope lock is superseded one-way, and the "only for it" narrowing is empty

`epics.md` FR-33 (unchanged, two places):

> Scope lock: `securities_list` ONLY — explicitly **no generic field-selection
> framework across endpoints**.
> …
> | FR-33 | #584 | slim `securities_list` projection, scope-locked (E6 DX batch, story 4) |

`epics.md` FR-37 (new):

> Generalizes FR-33, whose scope lock confined slim projections to
> `securities_list`; that lock is **superseded for this family and only for it**.

Two problems. First, FR-33's own entry and its coverage-map row carry no marker,
so a reader arriving at FR-33 (or at #584) still reads an absolute prohibition.
Second, and more substantively, "only for it" has no residual content: FR-37
*is* "per-endpoint field selection and projections" across endpoints — the exact
thing FR-33 banned. Once FR-37 ships, nothing is left inside FR-33's lock to
enforce. The narrowing language reads as a careful limitation and is in fact a
full repeal. **Fix:** mark FR-33 as superseded by FR-37 in both places, and drop
"and only for it" or replace it with the constraint that actually survives (the
validated per-endpoint whitelist, no query-builder passthrough).

### M-4. The H5 table relabels the brief's "Depends on" column as "Gate"

Brief addendum:

> | Object | Carries | **Depends on** |
> | Thesis / conviction | … | the identity decision only |
> | Prediction | … | feeds the calibration report |

`prd.md` section 5H:

> | Object | Carries | **Gate** |
> | Thesis / conviction | … | B3.1 |
> | Prediction | … | B3.1 |

Two consequences. B3.1 is the gate this very change *closes*, so listing it in a
"Gate" column beside the still-open B3.4 and B3.6 reads as "still gated" —
`epics.md` says the opposite ("Decided in principle by the identity gate"). And
the prediction row's real content ("feeds the calibration report", i.e. FR-47
depends on FR-46) was overwritten; it survives only in `epics.md`'s FR-47 line.
**Fix:** restore the column as "Gate / depends on" and write "none — closed by
B3.1" for the two decided objects.

### M-5. "a human **or an agent** confirms it" lets the extractor confirm itself

`AGENTS.md` and `prd.md` NFR-10, identically:

> …lands only after a human **or an agent** confirms it — the same
> preview-then-apply shape the Portfolio Performance import uses.

With the agent established as a first-class user in the same change, "an agent
confirms it" permits the LLM that produced the extraction to approve its own
proposal in the next tool call. That is not a preview-then-apply shape; it is an
auto-apply with two HTTP requests. No document states that the confirming actor
must be distinct from the extracting one, or that the confirmation must be
recorded (actor + timestamp) — even though FR-28's audit journal exists exactly
for that and is named as a prerequisite for the H5 objects two paragraphs later.
This is a genuine gap, not a hypothetical: ADR-0021's PDF intake is named as the
first binding use. **Fix:** add "the confirming actor is recorded in the audit
journal and must not be the extracting process".

### M-6. "Computation basis" has no sufficiency criterion and no enforcement point

`AGENTS.md`:

> **A story that adds or changes a metric** must state that metric's
> **computation basis** in the API and MCP payload (series, window, reference,
> gap treatment) **before step 9 passes.** Review-blocking…

Two unresolved cases:

1. **Trivially-true basis.** For a metric with no window and no reference —
   "distance to extremes", a count, a current-value roll-up — the required basis
   degenerates to restating the field's own name plus `"gaps": "none"`. The rule
   says an *unstated* basis cannot be reviewed; it says nothing about what makes
   a stated basis adequate, so a payload that satisfies the letter and conveys
   nothing passes. The stated rationale ("there is nothing to check the
   implementation against") applies verbatim to the trivial case.
2. **Wrong enforcement point.** Step 9 is "Required gates run", and the Required
   Local Checks list is a fixed set of six commands (`mix format`, `mix test`,
   `mix coveralls`, `pre-commit`, `npm test`, `npm run build`), none of which can
   observe a payload field. "Before step 9 passes" therefore attaches the
   obligation to the one step that cannot carry it. It belongs on step 5/6
   (API/MCP coverage) or in the PR template's API and MCP evidence section.

Neither `docs_test.exs` nor any invariant test guards the rule — a fair
candidate for the meta-test NFR-9 promises, since a schema assertion over the
analytics endpoints is mechanical.

### M-7. The current sprint plan still cites the retired rule

`_bmad-output/implementation-artifacts/sprint-plan-2026-08-10-sprint5.md:145`
(and the `-draft` twin at :90), under "Explicitly not Sprint 5":

> - The "from data to information" insights direction (needs a product brief and
>   a decision gate; **Hard Rule "no advanced reports" stands**).

Sprint 5 is the live sprint (`sprint-5-retro-2026-08-10.md` exists but the plan
is the working document). The precondition it names — "needs a product brief and
a decision gate" — was met on 2026-08-12 by the brief and this gate, and the
rule it cites no longer exists. Historical sprint plans (`2026-08-05`) are
snapshots and can stay; the current one misdirects. **Fix:** one dated line on
the Sprint 5 plan.

### M-8. Section 5H duplicates the registry content it says it will not duplicate

`prd.md` section 5H opens by refusing duplication —

> **This section describes the families and their boundaries; the numbered
> requirements (FR-37 and beyond) live in `epics.md`** … the owner decided
> against writing them in two places, because copies drift…

— and then reproduces, near-verbatim in both documents: the field-selection
constraint sentence, the FR-33 supersession clause, the issue numbers ("Tracked
as #665 and #666"), the whole audit-journal sequencing paragraph, the
security-events-for-every-catalog-security boundary, the corporate-actions
distinction, the thesis object's three queries, and the excluded-items
paragraph. Roughly 300 words exist twice with small wording differences already
(`epics.md` says "Blocked by #677"; the PRD says "prerequisite for H5"). The
addendum flags exactly this failure mode as an expensive pre-existing problem:

> **`epics.md`'s Requirements Inventory carries a pre-2026-07-25 copy of
> FR-1..FR-29** … which makes this drift more expensive than it looks.

**Fix:** in section 5H, keep the family names, the boundaries that are genuinely
product statements, and a pointer; delete the restated constraints and issue
numbers.

### M-9. `AGENTS.md`'s numbered Project Goal list was not extended

The Project Goal gained the two-user paragraph but its enumerated scope
(goals 1–12, ending at "Store per-category target weights and report the
target/actual allocation breakdown…") is unchanged, and `CONTRIBUTING.md`'s
"Active Scope" mirrors it. Under the project's own convention — scope changes
land as ADR + `AGENTS.md` amendment, and goal #9/#12 were added exactly that way
— the numbered list is the canonical enumeration of what the product does. A
reviewer asking "is a per-security volatility endpoint in scope?" gets "yes"
from the ladder and "not listed" from the goals, with no statement of which
governs. Previous scope expansions (PP import, target weights) added a numbered
goal; this one did not. **Fix:** add goal #13 (derived analytics per the scope
ladder) and #14 (knowledge objects), or state that the ladder governs analytics
and the numbered list enumerates record-keeping only.

### M-10. "Rebuildable" is unbounded in cost, and NFR-8 explicitly cannot bound it

FR-1 binds:

> - **rebuildable** from transactions alone, with drop-and-rebuild a supported
>   and tested operation;

Nothing states a cost ceiling, and the only performance requirement disclaims
itself in the same change:

> - NFR-8 … Still **aspirational**: no instrument measures it. FR-1's durable
>   derived layer is the structural answer to the felt version of this NFR; it
>   **does not supply the missing instrument.**

NFR-8's p95 < 2 s is also scoped to "interactive views and MCP analytics", not
to a rebuild. So a materialized layer whose full rebuild takes six hours
satisfies every word of FR-1: it is rebuildable, it is versioned, it labels its
freshness, it is never authoritative for a write. But a rebuild nobody can
afford to run is not a real audit path, and "drop and rebuild" is the operation
the whole reproducibility argument rests on. The `epics.md` copy of FR-1 has the
same gap ("drop-and-rebuild supported and tested"). **Fix:** one acceptance
criterion in the B3.2 hand-off — a bounded rebuild time on the reference dataset
the NFR-8 harness would use — or an explicit statement that rebuild cost is
B3.2's to decide.

---

## Low

- **L-1. The identity statement now exists in four places with no guard.**
  `AGENTS.md` ("two first-class users: the operator, and the LLM agent the
  operator runs"), `README.md`, `docs/index.md` and `prd.md` §1 carry near-identical
  paragraphs; `docs_test.exs` pins only the older feature sentences
  ("Record manual buy and sell transactions."). Given NFR-9's philosophy and that
  the project meta-tests CSS token usage, a single assertion that the two-user
  sentence appears in `README.md`, `docs/index.md` and `AGENTS.md` would be
  cheap and would stop silent divergence of the public identity.
- **L-2. The README's direct address is self-reported but unresolved.** The
  addendum records it honestly ("your holdings, your agent, your machine" vs the
  2026-07-23 microcopy rule in `project-context.md`) and leaves it to the owner.
  Noting it here only so it is not lost: `project-context.md` was not annotated,
  so the next agent applying the microcopy rule will "fix" the README.
- **L-3. The non-goals now exist as two lists with different contents.** Hard
  Rules: "no broker connection, no order creation or transmission, no automated
  trading or payment, no advice, no raw news archive, no external LLM calls".
  Security Boundaries (unchanged): "no real bank, broker, wallet, payment, order,
  trading, or rebalance action; no automatic trading or payment functionality"
  plus "no external LLM calls from the app". Neither cross-references the other;
  "advice", "raw news archive" and "wallet" appear in one list only.
- **L-4. `sprint-status.yaml` was not touched.** FR-37..FR-48 and issues #665,
  #666, #677 entered the registry with no sprint/epic rows. Defensible for a
  planning-only change, but the Epic-Batch close-out treats `sprint-status.yaml`
  and the epics document as a pair.
- **L-5. Positioning is annotated stale for one differentiator of four.** The
  note covers what-if/backtest; the same paragraph's German-retirement
  differentiator rests on FR-26, which this change left unclassified (M-2), so
  the "describes an ambition rather than a current position" caveat arguably
  covers two of the four.
- **L-6. Two agent-side success criteria describe the maintainer's private
  tooling.** "The weekly rebalancing run costs ≤ 5 calls, down from roughly 25"
  and "*Instrument:* the agent's own file inventory" describe the owner's
  personal agent setup and prompt contents. No figures or holdings are exposed
  and this is likely fine, but the Privacy And Disclosure rule names "private
  tooling" explicitly, so it is worth an owner glance.
- **L-7. ADR-0032's frontmatter still reads "Proposed decision to cache… so
  ADR-0004 (holdings are never stored) is untouched"** while its status is
  Accepted. FR-1 now points at that ADR as the thing B3.2 must supersede or
  amend, which makes the stale description a little more visible than before.
- **L-8. Issue numbers unverified.** #663, #665, #666, #675, #677 could not be
  checked from this environment; the FR Coverage Map now depends on them.

---

## What I checked and found clean

- No ADR under `docs/decisions/` references "advanced reports" or the retired
  rule; nothing in `lib/`, `test/` or `mcp-server/` does either.
- The three doc meta-tests pass unchanged after this branch (21 tests, 0
  failures). No sentence altered by this change is currently asserted by
  `docs_test.exs`, `workflow_docs_test.exs` or `ci_test.exs`; the README's
  five load-bearing capability strings and `ci_test.exs`'s
  `"creates and pushes an annotated"` all survive intact.
- FR-9's and FR-10's status is consistent across the PRD section C box, the
  Phase 4 scope note, OQ-1c and the `epics.md` coverage map. FR-27's re-gating is
  consistent across the same four places (the OQ-11 blocker is carried in both).
- `docs/index.md`'s "Current Scope" list describes shipped capability only and
  did not need to move with the ladder.
- The permanent non-goals do not contradict the ADR-0021 PDF-intake exception or
  the NFR-10 marker rule.
- Multi-tenancy is handled carefully and consistently: recorded as
  "declined for this horizon, not forbidden forever" in the PRD, absent from the
  permanent list in `AGENTS.md`, and `README.md`/`docs/index.md` say only
  "no tenancy" as a description of the deployment model.
