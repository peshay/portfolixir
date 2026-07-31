# Epic-Structure Reconciliation — 2026-07-31

Lane C of `sprint-plan-2026-07-31.md` ("planning debt, no code"). One pass over
every open GitHub issue, the epics document (`epics.md`, E1–E19 + FR Coverage
Map), the GitHub tracker-issue set (#416–#420, #470, #398, #356) and the
roadmap index #321, so that future sprint planning is mechanical instead of
archaeological.

**Ground truth:** GitHub open-issue list fetched 2026-07-31 — **43 open
issues**, **0 open pull requests** (so no issue-lags-PR cases exist today;
standing finding 2 re-checked and currently clean). Strictly read-only on
GitHub: nothing was commented, labeled, closed or edited there.

**Reading key.** "Epic" = the E1–E19 structure in `epics.md`. "Tracker" = the
GitHub `tracking`-labeled umbrella issue. An issue is **unattached** when it is
neither mapped by the FR Coverage Map / Epic List nor a GitHub sub-issue of a
tracker.

---

## 1. Full mapping table — every open issue

### 1a. Trackers and umbrellas (11)

| # | Title (short) | Epic (epics.md) | Open children | Status notes |
|---|---|---|---|---|
| #321 | Roadmap / Backlog (tracking) | meta-index over E1–E12 | n/a (index, not sub-issues) | **Stale.** ~24 of ~30 indexed issues are closed; #338 still shown unticked though closed 2026-07-31; #354 still described with the pre-rescope scope ("full PP-compatible export", dropped 2026-07-22). Closable candidate or one refresh — owner call (§4). |
| #320 | Feature backlog: agent roadmap P3/P4 (tracking) | E8 per FR map — **wrongly** (see §5, contradiction 2) | items are inline, no sub-issues | Body lists quotes-sync error report, dividend calendar, earnings dates, watchlist, securities_merge, doc screenshots. None of that is FR-17–21 broker sync. |
| #416 | Epic — Data: import, export, audit & correctness | overlays E2 + E4 | #333, #395, #354 | 2/5 done (#348, #353). Healthy tracker. |
| #417 | Epic — Portfolio structure & instrument lifecycle | overlays E3 + E9 (+ former E17) | #328, #330 | 2/4 done (#327, #338). Body's sub-issue list still names #338 as "corporate action wizards"; hygiene note (2026-07-22) already recorded the E17 repurpose; #338 closed 2026-07-31. |
| #418 | Epic — Analytics, dashboard & charts | overlays E5 + E10 | #332 | 2/3 done (#336, #337 both closed-completed). Hygiene note still lists **#562 as unattached-open — #562 closed in Sprint 1** (stale). Names but does not attach #563/#564/#568/#572/#577. Natural home for the analytics wishlist (§3). |
| #419 | Epic — LLM / MCP capabilities | overlays E6 | none | **100 % complete** (only child #355 done). Closable candidate — or attach #567 first, which its own hygiene note names (§4). |
| #420 | Epic — Engineering quality & process | overlays E1 (partially) | #314, #382 | 2/4 done (#359, #315). #382 has no E-epic home (see §2). |
| #470 | Epic — Transactions & Imports UX hardening | none (no E-number; E11-adjacent) | #471 | 4/5 done (#472–#475). Not indexed anywhere in `epics.md`. Nearly closable — one child left, and that child is parked (see #471 row). |
| #398 | Truthful valuation & allocation (tracking) | none (no E-number) | #406 | 1/2 done. Sprint 2 Lane A: closes once #406 and #570 land (note: #570 is *not* a GitHub sub-issue of #398 — the linkage exists only in the sprint plan). |
| #356 | UX & Accessibility: DESIGN/EXPERIENCE spec (tracking) | E11 | #412, #414 | 4/6 sub-issues done (#410, #411, #413, #415). The E11 tracker; the unattached UI issues in §2 propose to attach here. |
| #340 | Parking lot: wealth-management vision (tracking) | E9 (FR-24/25 per map) | none | Genuine parking lot; fine as-is. |

### 1b. Working issues (32)

| # | Title (short) | Epic / tracker | Status notes |
|---|---|---|---|
| #314 | CI coverage ratchet + Credo thresholds | E1 / #420 | `agentic`, unblocked. Only E1 remainder. |
| #328 | Merge, rename, delete cash accounts & depots | E3 / #417 | `needs-uat` (UAT pile). Only E3 remainder. Precedent for #608. |
| #330 | Bonds: master data + percent-of-nominal valuation | E9 / #417 | `needs-uat`, Phase 4, discovery-first — gated by design. |
| #332 | What-if simulator (design + MVP) | E10 / #418 | `needs-uat`, Phase 5 — gated by design (AR-8 scenario isolation). |
| #333 | PP full import: XML | E4 / #416 | `needs-uat`, **gated**: needs ADR + AGENTS.md amendment (FR-5). |
| #354 | FR-29 rescoped: pg_dump backup/restore | E2 / #416 | `needs-uat` (UAT pile). Rescoped 2026-07-22; #321 and the old #416 body text still carry the pre-rescope wording. |
| #382 | Remove Sobelow ignores (CSP nonce + TLS) | — / #420 | Security posture; no E-epic. Proposed home: fold into E1's guard family (proposal, §2). |
| #395 | FX settlement follow-ups (#388) | — / #416 | No E-epic. Import-mapping part touches projection semantics → risk-tier when picked up. |
| #406 | "No price" warning tells the truth; detail/totals reconcile | — / #398 | **Sprint 2 Lane A, item 1.** Valuation-behaviour decision before code; risk-tier by proximity to valuation; own PR. |
| #412 | Forms & inputs consistency | E11 / #356 | `needs-uat` (UAT pile). |
| #414 | Transactions view: usable overview | E11 / #356 | `agentic`. |
| #471 | Transactions — visible portfolio selector | — / #470 | **Parked** pending its ADR-0024 re-cut (de-labeled 2026-07-22): the portfolio selector concept predates buckets/views. Last open child of #470. |
| #481 | Product direction: position-first SOLL (deferred) | unattached | Deliberately deferred product-direction note (E15-family). Keep parked; do not schedule. |
| #491 | Master-data creation UX review (Steve) | unattached | UI review findings. Proposed home: #356/E11. |
| #560 | Income chart bars overflow on mobile | unattached | `bug`, UI. Proposed home: #356/E11 (responsive, UX-DR12 family). |
| #561 | Data quality: counts without a path to fix | unattached | `agentic`. Proposed home: #416 (data quality) — the data-quality panel is its surface. |
| #563 | Wealth period picker: previous year + custom range | unattached | `agentic`, cheap. Analytics wishlist → §3. Proposed home: #418/E5. |
| #564 | Wealth chart data table: meaningful summaries | unattached | `needs-uat` (UAT pile). Analytics wishlist → §3. Proposed home: #418/E5. |
| #565 | Securities table: classification columns (PP parity) | unattached | `agentic`. Proposed home: #356/E11 (table-configuration UI). |
| #566 | Replace toasts with inline busy/result states | unattached | `agentic`. Proposed home: #356/E11 (state patterns, UX-DR13). |
| #567 | Docs: automation recipes (external read-only sync via API/MCP) | unattached | Named by #419's hygiene note but never attached. Proposed home: E12 (docs) or #419 before closing it. |
| #568 | Money-weighted metrics: net invested, wealth multiple, IRR/MWR | unattached | Analytics wishlist → §3. Needs a short design session first (own issue says so). |
| #569 | Per-position P&L FX artifacts | unattached | **Sprint 2 gate: decision only, ADR before code.** Money-domain math → risk-tier. Owner sign-off pending. Proposed home: #398 family / E5. |
| #570 | Data quality: flag negative holdings | unattached | **Sprint 2 Lane A, item 2.** Rescope confirmed 2026-07-31 (links to transactions, no repair wizard). Proposed home: #398 (it co-closes #398 per the sprint plan — attaching it as a GitHub sub-issue would make that mechanical). |
| #572 | Benchmark comparison vs. indices and inflation | unattached | Analytics wishlist → §3. This **is** FR-9's subject (FR map still says "future, no issue") — see §5/§6. Sequenced after #568 (reuses its flow definitions). |
| #573 | Docs: bucket/view use-case guide | unattached | Proposed home: E12 (docs). |
| #577 | Cross-portfolio performance walk (view scopes) | unattached | Correctness-adjacent (performance number silently narrower than the header total). Risk-tier (money math). Analytics wishlist → §3. Proposed home: #418/E5. |
| #606 | Microcopy voice sweep | unattached | `agentic`, large, cross-cutting. **Sprint 3 by decision** (own epic batch). Proposed home: #356/E11. |
| #608 | Merge and repair securities (analogue of #328) | unattached | Explicitly out of Sprint 2; sequenced behind #328's UAT precedent. Proposed home: #417/E3. |
| #610 | TTWROR: lost quote feed books trade-price steps as return | unattached | Owner call whether it happens in practice; risk-tier when it does. Proposed home: E5 / #418. |
| #619 | Dashboard: other three mount computations | **NFR-8** (epics.md) / no tracker | Sprint 2 Lane B: measure before optimising. The only "unattached-pile" issue that already has an epics.md home (NFR-8 row). |
| #620 | Show which FIFO lots a sale consumes | unattached | Explicitly out of Sprint 2 — wants the #569 decomposition decision first. Proposed home: #418/E5, sequenced behind #569. |

**Totals: 43 open issues — 11 trackers/umbrellas, 32 working issues.
19 working issues are unattached** (#481, #491, #560, #561, #563, #564, #565,
#566, #567, #568, #569, #570, #572, #573, #577, #606, #608, #610, #620); #619
is epics.md-attached (NFR-8) but hangs off no tracker.

---

## 2. Unattached issues — proposed homes (proposal — owner decision)

Grouped by the proposed owning structure. "Attach" means: make it a GitHub
sub-issue of the tracker and (where an FR/epic applies) name it in `epics.md`.

**→ #418 / E5–E10 (analytics):** #563, #564, #568, #572, #577, #620, #610
(the whole §3 wishlist plus the two ledger-math follow-ups; #418's hygiene
note already points here for five of them).

**→ #398 (truthful valuation family):** #569, #570 — the sprint plan already
treats #570 as a co-closer of #398; making that a real sub-issue link removes
the archaeology. #569 is the same family (surfaces that agree and explain
themselves).

**→ #356 / E11 (UX):** #491, #560, #565, #566, #606 — matching the
sprint-status epic-11 comment, which already informally lists most of these.

**→ #416 (data):** #561 (data-quality panel affordances).

**→ #417 / E3:** #608 (securities analogue of #328).

**→ E12 (docs):** #567, #573 — small docs issues; E12 has no open tracker, so
either attach #567 to #419 before closing it, or leave both mapped in
`epics.md` only.

**→ E1 / #420:** #382 (security-posture gate work; #420 already carries it —
the proposal is only to name it under E1's guard family in `epics.md`).

**Stay parked, no home needed:** #481 (deferred product direction), #471
(parked pending ADR-0024 re-cut — already housed in #470).

**Structural proposal (owner decision):** the two parallel epic structures
should not persist. Cheapest coherent end-state: keep the GitHub `Epic —`
trackers as the *live* grouping for open work, keep `epics.md` as the
*authoritative spec*, and add one cross-reference line per tracker in the
`epics.md` Epic List (e.g. "E5 ↔ #418") so each structure names the other.
#470 and #398 additionally deserve E-numbers or an explicit "sub-epic of E11 /
of E5" note. Alternative (heavier): dissolve the trackers into the E-structure.
Not applied — this is a structure decision, not a factual correction.

---

## 3. Analytics-wishlist prioritisation (proposal — owner decision)

#563, #564, #568, #572, #577 have no owning epic. Proposed owner: **#418 /
E5**. Proposed rank, applying the #321 owner priority (data correctness first,
LLM-first consumption second, UI third):

1. **#577 — cross-portfolio performance walk.** The only wishlist item where a
   shipped surface shows a *wrong* number (TTWROR/IRR silently covers one
   portfolio next to a total covering all) — priority-1 correctness, and the
   ADR-0032/#562 walk context is still warm. Risk-tier (money math, dedicated
   small PR).
2. **#568 — money-weighted metrics.** Fixes the most misleading headline
   number (max-period TTWROR read as a wealth multiple) and delivers exactly
   the decision-ready figures the LLM-first priority asks for. Starts with the
   design session its own body requires.
3. **#572 — benchmark comparison.** The founding "was it worth it?" question
   (FR-9), but explicitly sequenced after #568 — it reuses #568's external-flow
   definitions. Its data-source decision (index proxies vs. CPI) needs the
   owner anyway.
4. **#563 — period picker.** Cheap, `agentic`, unblocked — a good
   fill-in/parallel item at any point; ranked here only because it is UI
   convenience (priority 3), not because it is hard.
5. **#564 — wealth chart data table.** Pure presentation, `needs-uat`, costs
   owner time rather than agent time; last.

Suggested consumption: #577 as its own risk-tier PR when review capacity
allows; #568 → #572 as a two-step; #563 (+ #564 if UAT time exists) as batch
filler. Sprint 3 already reserves a slot for "the triaged analytics wishlist,
in whatever order Lane C's prioritisation pass produces" — this is that order.

---

## 4. Closable candidates (suggestions only — nothing was closed)

- **#419** — its only child (#355) is done; 100 % complete. Either close, or
  first attach #567 (its own hygiene note names it) and keep it as the E6/E12
  LLM-DX home.
- **#321** — the roadmap index has been superseded in practice by
  `epics.md` + the FR Coverage Map + the tracker set; ~24 of ~30 indexed
  issues are closed and two entries are factually stale (#338 open-marked,
  #354 pre-rescope scope). Options: close with a pointer to `epics.md`, or one
  final refresh that reduces it to a pointer. Its "working agreement" section
  (one issue = one chat = one PR, label taxonomy) is worth preserving — it
  could move into AGENTS.md or the epics doc before closing.
- **#470** — after #471 is either done or explicitly closed-as-parked
  (ADR-0024 re-cut), the tracker is complete (4/5 done today).
- **#398** — closes when #406 and #570 land (Sprint 2 Lane A exit criterion;
  already the plan of record).

No working issue looked closable-as-obsolete: with zero open PRs, every open
issue describes genuinely unshipped work.

---

## 5. Contradictions found

1. **`epics.md` Epic List said E17 and E18 were "next" while both are done**
   — their stories merged, review debt cleared, trackers #338/#603 closed
   2026-07-31, and the same document's own reconciliation section says so.
   *Corrected in epics.md (factual — see §6).*
2. **FR Coverage Map claims FR-17–21 (Phase-3 read-only broker sync) are
   "tracked in #320", but #320 is a different list entirely** — the old agent
   roadmap P3/P4 (quotes-sync error report, dividend calendar, earnings dates,
   watchlist, securities_merge, doc screenshots). The sync FRs have **no**
   tracking issue. Left in epics.md untouched: where FR-17–21 should be
   tracked is a decision, not a fact. Proposal: create a thin E8 tracker when
   (if ever) the sync gate opens, and re-label #320 as what it is — a
   P3/P4 feature parking lot feeding E5/E9/E10.
3. **#321 (roadmap index) is stale in ways that mislead:** #338 listed as open
   (closed 2026-07-31), #354 described with its dropped pre-rescope scope,
   and the "Recommended order" section sequences mostly-closed work. Same
   family: **#418's hygiene note lists #562 as an unattached open issue —
   #562 closed in Sprint 1**; #417's sub-issue list still titles #338 as the
   wizard issue it stopped being on 2026-07-19.
4. **Two issues carry Sprint-2 semantics that GitHub does not know about:**
   the sprint plan treats #570 as a co-closer of #398, but #570 is not a
   sub-issue of #398; #619 is mapped in epics.md (NFR-8) yet hangs off no
   tracker. Anyone planning from GitHub alone reconstructs neither.
5. **Minor:** #419 is a fully-completed tracker still open (also in §4);
   `epics.md`'s E11/FR map rows still enumerate #336, #337, #339, #319 without
   noting all four are closed (the map maps requirements, not state, so this
   was left alone); E5/E12–E16 sit in the Epic List with their original
   priority labels ("next"/"now") although sprint-status marks them done — the
   column is "Priority", so only E17/E18, whose cells carried explicit status
   text, were corrected.

Standing finding 2 (issue state lags PR): **no instance today** — the open-PR
list is empty and no open issue's work is merged.

---

## 6. Proposed epics.md edits

**Applied (purely factual, verifiable against GitHub + the document's own
2026-07-31 reconciliation):**

1. Epic List, E17 row: "next (ADR-0028 accepted)" → "done (stories merged;
   tracker #338 closed 2026-07-31)".
2. Epic List, E18 row: "next (ADR-0029 accepted 2026-07-22)" → "done (stories
   merged; tracker #603 closed 2026-07-31)".
3. FR Coverage Map, FR-23 row: note appended that #588–#591 shipped and #338
   closed 2026-07-31.

**Left as proposals (judgement involved — owner decides):**

- FR-9 row: reference #572 as the benchmark-comparison issue (scope is close
  but not identical — #572 omits FR-9's after-cost/after-tax dimension, so
  declaring it *the* FR-9 issue is a scope call).
- FR-17–21 row: stop pointing at #320 (contradiction 2) — depends on where
  sync tracking should live.
- Epic List: add tracker cross-references (E1↔#420, E2/E4↔#416, E3/E9↔#417,
  E5/E10↔#418, E6↔#419, E11↔#356 (+#470), and #398 as a named E5-family
  sub-epic) per the structural proposal in §2.
- Epic List E5/E12–E16 cells: optionally mirror sprint-status "done" the way
  E17/E18 now do (their cells today carry only priority words, so nothing
  false stands there).
- E11 row: annotate that #336/#337/#339/#319 are closed and the open E11 set
  is #356 + #412/#414 (+ the §2 attachments if accepted).
