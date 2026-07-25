# Validation Report — Portfolixir PRD (2026-06-12)

- **PRD:** `_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md`
- **Rubric:** not run (rubric walker deselected for this run)
- **Reviewers:** adversarial-general
- **Run at:** 2026-07-25T13:04:34Z
- **Grade:** Poor (derived from severity counts alone — no dimension verdicts were produced)

> **Resolved 2026-07-25.** All 20 findings were addressed in a fix round on the
> same day; see `.decision-log.md` for what was applied and for the three
> agent-made judgment calls flagged for owner review. The privacy finding
> (F-12) was **narrowed by owner decision**: naming the operator and naming
> brokers is acceptable; concrete financial values and household details are
> not. This report is the record of what was found, not a list of open items.

## Overall verdict

The document is well written and, in its June form, was an honest artifact. It is
no longer a usable contract, for two independent reasons. First, its authority
claim is false: the PRD says "the PRD is authoritative — issues track
implementation", but the authoritative requirement registry migrated to
`epics.md` six weeks ago. FR-30 through FR-36 were added and owner-confirmed
there and never appended here, despite the PRD's own rule that "new requirements
append, never renumber". FR-29 was rescoped by owner decision on 2026-07-22 —
the PP-compatible export was dropped — and the PRD still promises the dropped
capability in three places, including the safety argument that licenses its
headline success metric. ADR-0024 demoted the portfolio entity to an internal
compatibility record on 2026-07-12; FR-4 and UJ-6 still describe portfolios as
the user-facing grouping. A reader who takes this file at its word will build the
wrong product.

Second, the "all criticals and highs fixed" claim in the decision log does not
survive inspection: of the prior review's two criticals and seven highs, four
were genuinely resolved, one has since regressed, one was addressed only
cosmetically, and three were never touched. The June review also missed a
standing scope-lock violation that is still open, and the metrics section remains
the weakest part — not one of the three success metrics can be measured from
anything the product stores.

## Dimension verdicts

Not assessed — the rubric walker was deselected for this run. Only the
adversarial reviewer ran, so this report carries findings and a claimed-fix
audit, not per-dimension judgments.

## Findings by severity

### Critical (2)

**[Adversarial]** — The PRD claims authority it no longer has; the live FR registry is elsewhere (§5 preamble; frontmatter)
`epics.md` carries FR-30..FR-36, all owner-confirmed, several shipped, one with its own accepted ADR — and has quietly amended the authority claim to "The PRD/epics are authoritative". An agent handed `prd.md` as the requirement source treats FR-30..36 as out of scope. A requirements document that is `final` while its requirement set grows elsewhere is a decoy, not a contract.
Fix: Either append FR-30..FR-36 and re-date, or demote the PRD explicitly ("the epics document is the live FR registry; this PRD records the founding intent as of 2026-06-12") with `status: superseded-in-part`. One of the two documents must stop claiming authority.

**[Adversarial]** — FR-29 was rescoped away, and the safety argument depending on it was never re-examined (FR-29, UJ-2, §7 Metric 1)
ADR-0029 records the rescope to `pg_dump` with the PP export dropped (#354). The PRD still says "retiring external copies is only safe because this exists" — but a dump is the same schema read by the same code: a projection bug, a mis-signed import or a hallucinated agent write is preserved faithfully. It is a disaster-recovery artifact, not a verification artifact. The June review's critical C-2, regressing.
Fix: Rewrite FR-29 to the shipped scope and remove the safety claim. Re-gate Metric 1 on something that detects wrong numbers — the FR-35 reconcile endpoint already exists — or state the risk as accepted and unmitigated.

### High (10)

**[Adversarial]** — Claimed fix H-6 did not land: FR-14 still specifies an LLM writer with no failure modes (FR-14)
Only the audit-journal clause was appended. All four of H-6's gaps survive: delete unlisted, no write idempotency (a client that times out and retries duplicates a financial record), no dry-run, no runaway bound. A journal makes damage legible afterwards; it prevents none of it. "An LLM can fully replace manual UI data entry" is untestable and silently false the day a new form ships without a tool.
Fix: Split into write coverage incl. delete; idempotency keys on every write; a dry-run mirroring import preview; machine-readable validation errors. Replace "fully replace" with "every write endpoint in `/api/v1` has a matching MCP tool".

**[Adversarial]** — Claimed fix H-2 did not land: the scope gates are paper (§1, NFR-3, Phase 3 gate)
The PRD declares mechanical guards "load-bearing product requirements, not process garnish", then enforces the boundary separating a portfolio tracker from something holding live bank credentials with a solo owner editing Markdown, as author, approver and enforcer. Nothing fails CI if an OAuth client or credentials table lands before the ADR.
Fix: Add an NFR backing the Phase-3/XML/rebalancing boundaries with meta-tests (dependency allowlist, no credential-bearing schema, no bank-domain HTTP config), removable only in the same PR as the ADR and AGENTS.md amendment.

**[Adversarial]** — Claimed fix H-7 did not land: FR-24/25 sell a moat that is an unbounded legal liability (§1, FR-24, FR-25, UJ-4)
No assumption block, no gross/net scoping, and no requirement for owning and dating the legal parameter tables. "What does one more point buy me?" has no correct answer without them, so FR-24 ships a confidently wrong number to an LLM that repeats it verbatim. FR-36/ADR-0031 later had to build exactly that machinery, stating derivation "is structurally impossible".
Fix: Add the assumption block: v1 = gross, current-law, parameter-table-driven, operator-maintained and effective-dated, surfaced with as-of dates per FR-13; taxes and KVdR out of scope v1. Align with FR-36's `tax_parameters` pattern.

**[Adversarial]** — Scope-lock violation: four FRs are "advanced reports", which AGENTS.md forbids (FR-9, FR-10, FR-26, FR-27)
AGENTS.md, unamended: "Do not add advanced reports or advanced classifications." The PRD gates the named forbidden classes meticulously and is silent on this one, yet benchmark comparison, income analytics, retirement projection and a what-if simulator are not plausibly anything else. Reproduces the defect H-3 identified for FR-5/FR-12; the fix applied there was never generalised.
Fix: Annotate FR-9/10/26/27 with the same scope-gate note, or fold the goal-list and hard-rule amendment into OQ-1's deliverable.

**[Adversarial]** — FR-12 and ADR-0023 draw the guidance-versus-action line in different places (FR-12 vs. ADR-0023)
FR-12 says the system never prepares or suggests executable orders. ADR-0023 permits showing "the quantity to buy or sell at the latest stored quote that would close the gap" — a concrete instrument, side and quantity, priced. Two governing documents define the safety-relevant boundary differently, and the narrower one claims to be authoritative.
Fix: Restate FR-12's boundary in ADR-0023's terms verbatim, and mark which half of FR-12 has shipped.

**[Adversarial]** — FR-4 and UJ-6 describe a grouping model the product deliberately abandoned (FR-4, UJ-6 vs. ADR-0024)
ADR-0024 demotes the portfolio entity to an internal compatibility record and makes buckets and views the only user-facing grouping, with SOLL plans bound to views. It names FR-4's own issues as existing "purely as maintenance cost of the container concept".
Fix: Rewrite FR-4 in bucket/view terms (what is scoped, what is instance-global, where SOLL plans bind, the additivity constraint as a requirement) and rewrite UJ-6 as a view switch.

**[Adversarial]** — Not one of the three success metrics is measurable from what the product stores (§7)
Metric 2's "without client-side computation" is unobservable by construction. Metric 1 is self-reported. Metric 3 is satisfied by any non-crashing output. Counter-metric 1 is worse: wrong numbers are only discovered by comparison against an independent source, which is exactly what Metric 1 defines success as eliminating — achieving Metric 1 drives Counter-metric 1 to zero by construction.
Fix: Give each metric an instrument. Metric 2: server-side count of MCP sessions terminating without a bulk pull. Metric 1: gate on FR-35's reconcile endpoint reporting zero unexplained differences over N months. Metric 3: name FR-26's acceptance criteria or drop it.

**[Adversarial]** — OQ-8 misroutes the web UI's no-auth posture as a community question when it is a Phase-3 blocker (NFR-4, OQ-8, FR-28)
Verified: the `:browser` pipeline has no auth plug. OQ-8's trigger omits the one that forces the decision — Phase 3 parks live bank and broker credentials behind that unauthenticated UI. An implementer can enter Phase 3 with OQ-8 open and be compliant with this PRD. FR-28's "attributable" also overclaims: `:owner_ui` is backed by no authentication.
Fix: Make OQ-8 a hard precondition of the Phase 3 scope gate with the credential-exposure rationale. Soften FR-28 to "attributable to actor class; UI writes carry no identity while the UI is unauthenticated (OQ-8)".

**[Adversarial]** — FR-9 is five capabilities in one requirement, and its method cannot answer the founding question (FR-9, §1, OQ-3, OQ-9)
One FR contains a fixed-rate baseline, an index/security-series baseline, two scenario shapes, an after-cost and an after-tax dimension spanning three German tax mechanics whose depth is itself open. Comparing a TTWROR series against a flat rate is apples-to-oranges, and capital-gains tax applies to realised money-weighted outcomes, not a time-weighted index — so "after-tax TTWROR vs. 2 %" is categorically ill-defined.
Fix: Split into at least three FRs. Specify the method in the FR: replay actual cash flows into the alternative and compare end wealth or IRR. If v1 ships the approximation, embed the caveat in the response per FR-13.

**[Adversarial]** — The persona is labelled fictional while carrying the maintainer's real broker, bank, strategy and pension profile (§2, UJ-2, FR-17/18/19, Metric 3, addendum)
The label is narrowly true (the name is invented) and broadly misleading. §1 says "the owner does not read code"; UJ-2 opens "A comdirect statement arrives"; the decision log records the sync providers as "operator-stated must-have"; Metric 3 says "real pension data". AGENTS.md forbids exactly this. The June 2026 redaction pass rewrote branch history to remove this class of content but retained the parts that, combined, still identify one person's broker, bank, crypto venue, risk posture, household structure and retirement plan. This is a public repository.
Fix: Make the persona genuinely fictional or drop the label. Rewrite UJ-2 to "A broker statement arrives" and §2 to a strategy-neutral operator description. Keep FR-17/18/19 as named integration targets but sever them from the operator's own accounts. Reword Metric 3.

### Medium (7)

**[Adversarial]** — The triage claim "no phase-blockers among OQ-1..8" is false for OQ-1 (OQ-1 vs. §4 Phase 1)
§4 schedules "PP XML full import (#333)" inside Phase 1 — now — and FR-5's gate says XML intake cannot begin without OQ-1's deliverable. Phase 1 reads as executable when part of it is not.
Fix: Split OQ-1 into its three halves, mark the XML half a Phase-1 blocker with a due-by, and record ADR-0023 as closing the FR-12 half.

**[Adversarial]** — NFR-2's "immutable inputs" is factually wrong, and it is the load-bearing word (NFR-2)
The sentence contradicts itself in eleven words, and the second half is the true one. `project-context.md`: "auditability = reproducibility from inputs, not append-only immutability — do not build soft-delete workarounds." The inputs are mutable; the journal of changes is what is immutable.
Fix: "Every number is reproducible from the ledger as it stands, and every change to the ledger is recorded in the append-only audit journal (FR-28). Ledger records are editable; edits are never hidden."

**[Adversarial]** — FR-27's flagship journey has an unfunded historical-quote dependency (FR-27, UJ-5, OQ-3)
Blind-follow backtesting needs price history from each tip date for securities never held — a different acquisition problem than maintaining quotes for the current portfolio, and one ADR-0005's provider split was not designed for. Raised in June as M-4; still unowned.
Fix: Add an OQ (source, depth, retention, licence, ADR-0005 fit) owned before the first FR-27 story. Same for FR-20's chain-data source.

**[Adversarial]** — Requirements whose acceptance is a matter of opinion (FR-13, FR-15, FR-16, NFR-1, NFR-8)
FR-13 quantifies over a set never enumerated. FR-15 is a taste statement. FR-16 mandates per-PR parity review — the one mechanism `project-context.md` lists under "deliberately NOT adopted". NFR-8's "p95 < 2 s" has no instrument. NFR-1 is a value statement.
Fix: FR-13 → a machine-readable analytics register the parity check runs against. FR-15 → a measurable property. FR-16 → move process to the workflow doc. NFR-8 → name the harness and dataset or mark aspirational.

**[Adversarial]** — The positioning moat rests on one uncited search, and reads the evidence backwards (§1 Positioning)
The only backing is a decision-log line naming a web subagent — no artifact, method, scope, or list of tools examined. An unfalsifiable negative justifying Phases 4 and 5. The German-pension datum is read as opportunity when the likelier reading is cost.
Fix: Attach the research artifact, or downgrade to "no comparable tool known to the maintainer as of 2026-06". Add the cost reading alongside the opportunity reading.

**[Adversarial]** — "Launch-grade" and "production-grade" collide with a hard rule the PRD never mentions (§1; addendum)
AGENTS.md: "Do not claim production readiness." The framing licenses Phase 3's credential storage, the self-hoster persona and the business-option posture — on a deployment with an unauthenticated web UI and no release, versioning or upgrade requirement anywhere.
Fix: Distinguish engineering discipline from production readiness in one sentence, citing the rule. Add the missing release/upgrade NFR or state the self-hoster persona is dormant.

**[Adversarial]** — "Drift" was left undefined in sign and unit, and it cost a breaking API change (FR-11, FR-12, §9 Glossary)
The implementation chose `target − actual`, the owner read it the other way, and ADR-0023 had to flip the convention across the Allocation module, UI, JSON API, MCP schemas and docs. The unit is still unspecified, and percentage-point versus absolute-currency ranking produce different orderings — while FR-12's ranking is the product's decision output.
Fix: Pin both in the glossary: drift = `actual_weight − target_weight` (positive = overweight, per ADR-0023), and state FR-12's ranking unit.

### Low (1)

**[Adversarial]** — No requirement addresses data freshness, so UJ-1's briefing can be confidently stale (FR-13, UJ-1, NFR-8)
Nothing requires a staleness flag, a newest-quote age, or a threshold beyond which a response self-marks stale. UJ-1's "seconds, zero exports" will happily report a valuation built on last week's prices. June's M-7, never fixed.
Fix: Extend FR-13: every valuation-bearing response carries the age of its newest input quote and FX rate, and self-marks stale beyond a configured threshold.

## Claimed-fix audit

The decision log states: "All criticals/highs and reconciliation gaps fixed in
one revision." Score: **4 of 9 genuinely resolved, 1 resolved-then-regressed,
1 cosmetic, 3 untouched.** Because the log is described as the canonical memory
and audit trail, the inaccuracy is load-bearing — it is what any future reviewer
will trust instead of re-reading.

| Old | Title | Status in current `prd.md` |
|---|---|---|
| C-1 | No audit trail for an LLM that edits financial records | **Resolved.** FR-28 added; ADR-0017 accepted, journal shipped. One residual overclaim (F-10). |
| C-2 | No backup/restore/export while retiring the redundant source of truth | **Regressed.** Rescoped 2026-07-22 to `pg_dump` only; PRD still promises the dropped capability (F-2). |
| H-1 | "Read-only sync" is a behavioural promise, not a security property | **Resolved.** FR-21 reworded honestly; OQ-6 added. |
| H-2 | The scope gate is self-amended paper with no mechanical backstop | **Not fixed.** No meta-test requirement added (F-4). |
| H-3 | FR-5 (XML) and FR-12 forbidden by AGENTS.md, no gate annotation | **Resolved for the two named FRs.** Not generalised (F-6); FR-12's boundary now diverges from its own ADR (F-7). |
| H-4 | Counter-metric violated by the repo's baseline on day zero | **Resolved.** Reworded to match `project-context.md`. |
| H-5 | Metric 1 dismantles the detection mechanism for Counter-metric 1 | **Not fixed.** The applied change addressed egress, not verification (F-9). |
| H-6 | FR-14 understates the live write surface, specifies no failure modes | **Cosmetic.** Only the audit-journal clause appended (F-3). |
| H-7 | German pension modelling sold as a moat without acknowledging legal churn | **Not fixed.** FR-36/ADR-0031 later built the machinery it asked for (F-5). |

## Mechanical notes

- `updated: 2026-06-12` is wrong on the document's own evidence; `status: final` has been wrong since 2026-07-12 at the latest.
- The decision log's last entry is 2026-06-13; the FR-29 rescope, ADR-0023, ADR-0024 and FR-30..36 are all absent, contradicting its claim to record "every decision, change, and override".
- §4's "story-sized increments per the roadmap (#321)" is superseded by ADR-0026 (epic batches).
- §5's "about two-thirds of FRs today" — the per-FR issue table was built in `epics.md`; the PRD keeps the vague fraction and no pointer.
- §4's "Phases are sequential priorities, not strict gates" — except Phase 3, FR-5(XML) and FR-12, which are strict gates.
- FR numbering interleaves by section, deliberate under append-never-renumber but unexplained.
- Glossary omits bucket, view, SOLL plan, and does not flag that ADR-0009's "snapshot" is spelled `balance_adjustment` in data.
- FR-11 marks SOLL/IST drift "(shipped)" without noting ADR-0023 shipped a breaking sign flip on that surface.
- UJ-1's "seconds" and NFR-8's "p95 < 2 s" are different claims; neither references the other.
- The addendum lists "Algotrading on top of the data backbone" with no scope-gate note, while §4 correctly marks it forbidden until a dedicated scope decision.
- Outside the PRD: `project-context.md` still requires a `Model:`/`Thinking level:` commit footer, which the current `AGENTS.md` and `CLAUDE.md` now forbid — worth a separate fix.

## Reviewer files

- `review-adversarial-general.md` (this run, 2026-07-25)
- `review-adversarial.md` (prior run, 2026-06-12 — audited above, not re-reported)
- `review-rubric.md` (prior run, 2026-06-12 — rubric walker not re-run this time)
