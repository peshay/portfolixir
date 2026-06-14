# PRD Quality Review — Portfolixir (FX-Correct Settlement & Risk/Concentration Endpoint)

## Overall verdict

This is a tight, thesis-driven capability spec that knows exactly what it is: an internal correctness fix for an agent-consumed financial tool, not a UX product. The strategic spine — "Jordan stops producing confidently-wrong numbers" — is real, the three failure modes are concrete and evidenced (phantom +15.4% P&L, ~5.33% cash artefact, EM 59k cluster), and scope discipline is excellent. The one place to be unforgiving is Done-ness: most FRs are testable, but a few lean on under-specified terms ("Top-N" with N unstated, HHI bands unbounded, "real settlement balance" defined circularly) that an engineer would have to invent. Nothing here blocks a green-light for the FR-B Phase 1 + FR-D Slice A slice; the gaps are small enough to resolve in story creation.

## Decision-readiness — strong

A decision-maker can act on this. Decisions are stated as decisions, not buried: FR6 commits "type beats sign" for liquidity classification, FR7 rules unused credit headroom out of the cash quote with an explicit rationale ("Unused credit headroom is not liquidity"), and FR10 makes a genuine product call — ETFs are exempt from the single-name rule so "a World-core ETF at 20% reads as target, not risk." These are choices with a stated loser, not neutral hedging.

Trade-offs are named rather than smoothed. CM2 admits the FX fix could destabilize valuation and constrains it ("the FX fix is surgical and preserves the EUR-hub triangulation"); CM1 names the opposite failure to SM2 (chasing cash-truth must not understate deployable liquidity). The counter-metrics are the strongest evidence of honesty here — each SM has a named way it could go wrong. The addendum does the deferral reasoning out loud: every parked idea "fails on the same question — 'where does the data come from?'" with a concrete recommendation (one feasibility spike behind which all are gated).

The PRD does not over-use `[NOTE FOR PM]` / Open Questions theater — in fact it uses none, which for a slice this small and this well-resolved is appropriate rather than a gap (the open items were resolved in the addendum: OPEN-A deferred, OPEN-B resolved).

## Substance over theater — strong

Almost no furniture. The Vision statement could not swap into another PRD — "makes a covered, FX-honest, risk-aware call it can stand behind" and the Andi re-check loop are specific to this tool and this operator. There is no persona section to inflate (correct for an agent-consumed tool). The NFRs are not boilerplate: NFR2 ("Decimal, serialized as `:normal` strings end-to-end; no float P&L, no tolerance assertions") and NFR3 ("settlement rates are stored, never computed as direct cross rates") are product-specific thresholds tied to named ADRs, not "system must be scalable/secure." NFR4's determinism claim ("pure derivation from current valuation + classifications") is an earned constraint on the risk endpoint, not decoration.

### Findings
- **low** Differentiation claim unexamined (§ Vision) — The "describes → makes a call it can stand behind" framing is strong but is asserted, not contrasted against what Jordan does today beyond the three failure modes. This is fine for an internal tool; no fix needed unless this PRD is reused for external positioning.

## Strategic coherence — strong

The PRD has a clear thesis and bets on it: data correctness is the product, because the consumer is a deciding agent and "quality is measured by the correctness of the decisions the data enables, not by engagement or UX." Every feature serves that arc — FX-honest P&L (G1), truthful liquidity (G2), risk lens (G3) — and the goals map 1:1 to features and to success metrics. This is not a backlog with headings; it is three failure modes, three goals, three feature clusters, traced through.

Success Metrics validate the thesis rather than measuring activity. SM1 is a hard pass/fail on phantom P&L deviation, SM3 is explicitly labelled a leading indicator, SM5 measures the actual outcome the thesis cares about (Andi's re-check rate trending to 0). No DAU/MAU tell. Counter-metrics are present and named (CM1–CM3), which most PRDs skip. MVP scope kind is coherently "problem-solving" and the scope logic matches — the slice is deliberately data-source-independent so it can ship before the gated future work.

## Done-ness clarity — adequate

This is the dimension to push on, and it is the weakest — though still serviceable. Most FRs carry a testable consequence. FR2 is exemplary: "The day-one foreign-currency position reads ~0% on zero real movement, not +15.4%" is directly verifiable, and SM1 bounds it ("more than 0.5pp from the FX-adjusted true P&L"). FR3 ("a settlement FX rate is required; the system validates the pair") and FR4 (unpriceable flag when no FX rate exists) have clear pass/fail behavior. FR6's "Today's ~5.33% cash artefact disappears" is testable. But several FRs leave "done" to engineer invention.

### Findings
- **high** "Top-N" N unspecified (§ FR8) — The concentration endpoint "returns ... single-name concentration **Top-N** and **HHI**" but never fixes N. An engineer cannot know whether done means Top-5, Top-10, or caller-configurable. *Fix:* state a default N and whether it is overridable per call (mirror FR10's "shipped defaults, overridable per call" pattern).
- **high** HHI has no interpretation bound or output contract (§ FR8) — HHI is named but there is no stated scale (0–1 vs 0–10000), no threshold that constitutes a "concentrated" verdict, and no statement of whether the endpoint returns the raw number, a band, or a flag. SM4 only requires "≥1 ... breach ... surfaced," which does not pin HHI's done-ness. *Fix:* specify HHI scale and whether/at what value it contributes to a surfaced breach.
- **medium** "Real settlement balance" / "real deployable depot liquidity" defined circularly (§ SM2, FR6, G2) — G2 says "reported deployable cash equals real settlement balance" and SM2 repeats it; "real settlement balance" is the thing being computed, so the acceptance test references its own output. The concrete anchor ("~5.33% cash artefact disappears") partly rescues this, but an engineer cannot derive the expected number for an arbitrary account set. *Fix:* give the computation rule explicitly (sum of `free_cash` accounts with balance ≥ 0) as the definition, and treat the 5.33% case as one worked example.
- **medium** FR9 cap-violation output contract unstated (§ FR9) — "reports asset-class cap violations against configurable caps" does not say what a violation record contains (asset class, current %, cap %, severity) or whether caps have shipped defaults like FR10's concentration thresholds. *Fix:* specify the violation payload shape and whether caps ship with defaults or are required config.
- **low** FR1 "records both legs honestly" lacks a field-level done test (§ FR1) — The intent is clear and FR3 covers the validation, but FR1 itself has no verifiable artifact (e.g., "stored rows expose security-currency amount, settlement-currency amount, and the stored FX rate"). *Fix:* name the persisted fields so a test can assert them.
- **low** FR10 ETF threshold stated as a range (§ FR10) — "its own high threshold ~25%+" uses "~" and "+", leaving the exact ETF WARN/HARD bound unfixed where the stock bounds are exact (WARN > 7% / HARD > 10%). Minor since it is overridable per call. *Fix:* pin the default ETF threshold value.

## Scope honesty — strong

Omissions are explicit and load-bearing, not inferred. Feature 3 carries an inline "Out of MVP (explicit)" block naming drawdown/volatility (→ FR-D Slice B), category/theme drift (→ FR-C), and correlation/look-through (future, data-source-gated). There is a top-level "Out of Scope (this PRD)" section and the addendum carries the full deferred-depth catalog with the unifying blocker stated ("all share one blocker: an external data source, free only"). The OPEN-A/OPEN-B items show de-scoping done openly, with reasons.

Open-items density is appropriately low for a green-light-to-build slice: zero live Open Questions, zero `[NOTE FOR PM]`, zero unresolved `[ASSUMPTION]` tags in the PRD body — the discovery questions were closed before this draft. For a small, well-scoped slice this is the right density, not a suspicious absence: the resolutions are visible in the addendum's "Resolved during discovery" section.

### Findings
- **low** Inferred decisions not tagged as assumptions (§ FR6, FR10) — Choices like `free_cash` as the default `liquidity_role` and "type beats sign" read as confirmed-with-Andi but are not marked, so a downstream reader cannot tell confirmed from inferred. Given the addendum confirms several were discussed with Andi, the risk is low. *Fix:* if any of these were PM inferences rather than Andi decisions, tag them `[ASSUMPTION: …]`.

## Downstream usability — adequate

This PRD feeds story creation directly, so traceability matters. IDs are clean: FR1–FR10 contiguous and unique, SM1–SM5, CM1–CM3, G1–G3, NFR1–NFR5, no gaps or duplicates. Cross-references to ADRs (0002, 0003, 0004, 0007) and to sibling features (FR-A/B/C/D, Slice A/B, Phase 1/2) resolve consistently, and the addendum cross-links cleanly. Goals→Metrics→Features form a navigable spine.

The gap is the absence of a Glossary, which for a tool this terminology-dense is a real downstream cost. Several domain nouns recur with slight variation and an extractor would have to reconcile them by hand.

### Findings
- **medium** No Glossary for a term-dense domain (§ whole doc) — "deployable cash," "deployable depot cash," "deployable depot liquidity," "free liquidity," "cash quote," and "real settlement balance" all appear and overlap without a single canonical definition; likewise "steerable basis," `excluded_from_allocation_targets`, and "liquidity_role" values. Story creation will have to infer which are synonyms. *Fix:* add a short Glossary fixing the canonical term for each concept (especially the deployable-cash family) and the three `liquidity_role` values.

## Shape fit — strong

The PRD is correctly shaped as a capability spec, not forced into consumer-product formalism. It explicitly disclaims the UX frame ("not by engagement or UX") and has no User Journeys or personas — the right call for a single-consumer agent tool where UJs would be pure overhead. Success Metrics are operational/correctness-oriented (SM1 deviation bound, SM3 coverage %) rather than user-facing engagement metrics, exactly as the rubric prescribes for an internal single-operator tool. Per the validation context, the User-Journey/persona expectations of dimensions 6–7 are correctly treated as n/a here; the PRD is neither over-formalized (no UJ density) nor under-formalized (the substance bar is met). No shape-fit findings.

## Mechanical notes

- **Glossary:** absent — see Downstream usability finding. The "deployable cash" family (≥3 surface forms) is the highest-value thing to canonicalize.
- **ID continuity:** clean. FR1–10, SM1–5, CM1–3, G1–3, NFR1–5 all contiguous and unique. No broken cross-refs; ADR and FR-x/Slice/Phase references resolve.
- **Assumptions Index roundtrip:** no inline `[ASSUMPTION]` tags and no index — acceptable for this slice, but see Scope-honesty low finding (a few inferred defaults could warrant tags).
- **UJ protagonist naming:** n/a (no UJs by design). "Jordan" (agent) and "Andi" (operator) are used consistently as the two actors.
- **Required sections:** Vision/Goals, Success + Counter-Metrics, Features/FRs, NFRs, Out of Scope, and addendum all present. Missing only a Glossary for the agreed stakes/type.
