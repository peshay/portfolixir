# PRD Quality Review — Portfolixir

## Overall verdict

This is a genuinely good PRD: it has a real thesis ("Is my investing actually worth it?" plus the cornerstone "LLMs call Portfolixir, never the reverse"), the phasing follows that thesis, and the scope-lock machinery (Phase 3 ADR gate, parked list) is honest rather than decorative. What's at risk is done-ness at the far end of the roadmap — the pension/retirement FRs (FR-24–FR-26) that back Success Metric 3 have no testable consequence and no issue anchor — and the absence of a Glossary in a chain-top PRD whose downstream consumers are coding agents working in German financial domain vocabulary. Both are repairable without restructuring anything.

## Decision-readiness — strong

Decisions are stated as decisions, with the discarded alternative named. The Cornerstone principle (§1) is an architectural commitment, not a consideration. Phase 3 (§4) names its own blocker — "AGENTS.md currently forbids broker/bank sync; entering Phase 3 requires an ADR plus AGENTS.md amendment" — and the aggregator rejection comes with a reason ("free tiers collapsing, 2025") rather than a preference. The Positioning section even concedes its own weakest point: "Target-weight rebalancing alone is the weakest moat — PP itself covers it." Open Questions are actually open: OQ-4 demands a spike before FR-19 is committed, OQ-5 declines to scope tax-awareness rather than hand-waving it. Nothing here is smoothed to neutral.

## Substance over theater — strong

Three users (§2), each load-bearing: the LLM agent persona directly drives FR-13–FR-16; the operator's German pension context drives FR-24–FR-26; "Future self-hosters" is explicitly demoted to "quality bar, not a commitment." NFRs are product-specific where boilerplate would be easy — "Decimal-only persistence," "invisible-Unicode/Trojan-Source rejection (#350)," "commodity home-server hardware" — and NFR-1 names the defining failure class ("silent financial corruption") instead of saying "reliable." The Vision could not be swapped into another portfolio tool's PRD; the founding question and "every flagship capability is this question in a different costume" are earned framing. The Positioning paragraph is dated (2026-06) and cites a market event (Maybe Finance's death) in support of a scoping decision, which is what differentiation sections are for.

### Findings
- **low** Unverifiable absolutes in Positioning (§1 Positioning) — "nobody else imports PP natively," "no open-source coverage at all" are stated as facts with no pointer to the market research that grounds them. Fine for a solo decision record, but if this PRD goes public-repo-visible, the claims age. *Fix:* one line citing the research artifact (date + source doc) the claims came from.

## Strategic coherence — strong

The thesis is explicit and the phasing derives from it: correctness first (Phase 1, because agents write the code and "silent financial corruption is the defining failure class"), LLM consumption second (Phase 2, because the agent is a first-class user), depth and simulation later. The Success Metrics (§7) validate the thesis rather than measure activity — "Spreadsheet retirement," "Agent autonomy" with three concrete questions the agent must answer "without any export, file handoff, or client-side computation," and "Retirement credibility." Counter-metrics are present and product-specific ("gates are never weakened to ship a feature — no threshold raises, no ignore files"). Dashboard v2 (#337) explicitly deprioritized behind the data/LLM tracks confirms prioritization follows the thesis, not what's visually gratifying.

## Done-ness clarity — adequate

Phases 1–2 are well-anchored: most FRs carry a testable consequence and a GitHub issue. FR-6 is exemplary ("content-hash; re-import is a no-op, and atomic"), as is FR-13 ("method, as-of date, currency, and conversion basis stated; financial values serialized as strings"). The deliberate FR→issue mapping means acceptance detail lives in #316–#350, which is a legitimate design for this repo. But the pattern breaks exactly where the issues run out: Phases 4–5.

### Findings
- **high** FR-24–FR-26 have no testable consequence and no issue anchor (§5.F, §5.G) — "Rentenpunkte as a tracked asset with projected payout," "payout options modeled," "wealth-at-age and sustainable-withdrawal curves… under named scenario parameter sets" name capabilities but give an engineer no verifiable condition: which payout formula or data source for Rentenpunkte projection, which scenario parameters are in the named sets, what "comparable against depot withdrawal" produces. These three FRs are the entire substance behind SM-3 ("Retirement credibility"), so a headline success metric currently rests on the vaguest requirements in the document. *Fix:* either add one testable consequence per FR (e.g. "projection reproduces the official Rentenwert formula for a given year's parameters") or explicitly mark F/G as discovery-pending with the same honesty Phase 3 gets.
- **medium** NFR-8 is an adjective, not a bound (§6) — "return in seconds on commodity home-server hardware" is the kind of phrase the rubric says to flag. The escape hatch "correctness always beats speed" makes it untestable. *Fix:* a number, even a generous one ("p95 < 3s for any MCP analytic on the reference deployment").
- **medium** FR-12's ranking criterion is unstated (§5.C) — "ranked 'where new cash goes'… derived from drift" doesn't say ranked by what: absolute drift, relative drift, drift × position size? UJ-3's "least strategic damage" is evocative but not computable. Since this is a flagship capability, the ranking definition is the feature. *Fix:* name the ranking function or add an OQ owning the decision.
- **low** FR-5 "losslessly" and FR-8 "selectable periods" underspecified (§5.B, §5.C) — lossless with respect to what (round-trip re-export fidelity? semantic equivalence?), and which periods are selectable (YTD/1Y/MAX/custom?). Issue #333/#316 may carry this; the PRD shouldn't assume the reader checked.

## Scope honesty — strong

Omissions are explicit at every level: a "Deprioritized / parked" list (§4) with algotrading "forbidden until a dedicated scope decision," the Phase 3 gate, FR-20's "private keys are out of scope by design, permanently," FR-12's "the system never places orders." The tax-awareness tension is handled exactly right — UJ-3 mentions "(and, later, the best tax outcome)," and OQ-5 owns it as "desirable but unscoped… needs its own discovery before any commitment." Four `[ASSUMPTION]` tags and five OQs is an appropriate open-items density for a solo-first PRD that green-lights Phases 1–2 while keeping 3–5 conditional. No `[NOTE FOR PM]` callouts exist, but with the operator and the PM-decision-owner being the same person, that's shape-appropriate rather than evasive.

## Downstream usability — adequate

IDs are clean (FR-1–27, NFR-1–8, UJ-1–6, OQ-1–5, all contiguous, verified), cross-references resolve (FR-21 → FR-2/FR-6, FR-12 → UJ-1/UJ-3), every UJ has a named protagonist, and all issue refs fall inside the stated #316–#350 range. Sections extract cleanly. Two structural gaps matter because the downstream consumers are architecture/epics workflows and coding agents, not humans who can ask.

### Findings
- **medium** No Glossary (whole document) — the PRD leans on German-financial and PP-specific vocabulary: "depot" vs. "portfolio" (FR-4 implies the relationship but never defines it), "SOLL/IST," "cash quote" (a Germanism — English readers expect "cash ratio/allocation"), "Rentenpunkte," "TTWROR," "13 PP kinds." A coding agent extracting FRs in isolation can plausibly conflate depot and portfolio, which FR-4's partition semantics make a correctness issue. *Fix:* a 10-line Glossary; the definitions already exist implicitly in FR-1/FR-4 and the addendum.
- **medium** FR↔issue authority is undeclared (§5 preamble) — acceptance detail is deliberately delegated to issues #316–#350, but the PRD never says which document wins on conflict, and issues mutate after the PRD freezes. For a workflow where agents consume both, a one-line precedence rule ("the PRD states the capability; the issue states acceptance; on conflict the PRD's FR text governs scope") prevents silent drift. *Fix:* add that line to the §5 preamble.
- **low** The addendum is never referenced from the PRD — addendum.md explicitly exists to inform "downstream documents (architecture, UX, epics)," but nothing in prd.md points to it, so a downstream workflow source-extracting from prd.md alone will miss it. *Fix:* one pointer in §1 or a References note.

## Shape fit — strong

The shape matches the product on every axis: solo-operator brownfield chain-top. UJs are few (six), short, and each one drives FRs rather than decorating them — UJ-1/UJ-3 → FR-12, UJ-4 → FR-24–26, UJ-6 → FR-4. The capability-spec tone of §5 is right for a single-operator tool; the PRD is not over-formalized. Brownfield discipline is observed: shipped functionality is consistently marked ("TTWROR (shipped)," "CSV/JSON v1 (shipped)," "SOLL/IST drift per category (shipped)"), so new vs. existing is never ambiguous. The unusual move of elevating development-process guards to product requirements (§1 "Stakes and quality bar," NFR-3) is justified by the stated reality that the owner doesn't read code — that's shape-fit done thoughtfully, not template residue.

## Mechanical notes

- **ID continuity:** FR-1–27 contiguous and unique; NFR-1–8, UJ-1–6, OQ-1–5 likewise. No duplicates, no gaps.
- **Issue refs:** all 22 distinct refs fall in #316–#350 (#346–#348 cited as a range, so #347 is implied, fine). Phase 3 FRs (FR-17–21) and pension FRs (FR-24–26) have no issue refs — consistent with the gate for Phase 3, a gap for Phase 4 (see done-ness finding).
- **Assumptions roundtrip:** four inline `[ASSUMPTION]` tags. UJ-4's and FR-9's are mirrored in OQ-2 and OQ-3, so Open Questions functions as a de-facto Assumptions Index — but it isn't labeled as one, and OQ-2/OQ-3 carry the `[ASSUMPTION]` tag themselves, which slightly blurs "open question" vs. "assumption made." Cosmetic.
- **Glossary drift:** "PP" used after first expansion consistently; "depot" (German usage) appears throughout including FR-titles — consistent internally, but see the Glossary finding. "Tagesgeld" (FR-9) and "fixed deposit" (addendum) name the same baseline concept with two terms.
- **Frontmatter:** `status: draft` — accurate for a PRD with one ungated phase decision (OQ-1) outstanding.
