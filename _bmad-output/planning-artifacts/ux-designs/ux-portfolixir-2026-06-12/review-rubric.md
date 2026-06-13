# Spine Pair Review — portfolixir

Reviewed: DESIGN.md + EXPERIENCE.md (draft, 2026-06-13) against design-md-spec.md, the three DESIGN examples, the two EXPERIENCE examples, .decision-log.md, and PRD §3 user journeys. Scope context honored: IA is IST-only by owner decision; UJ-3/4/5 exclusions were checked for *statement*, not coverage.

## Overall verdict

A disciplined, extraction-grounded spine pair: every token reference in both files resolves, flow names mirror the PRD verbatim, scope exclusions are stated where a consumer will look, and the decision log's binding choices (paradigm, motion, touch targets, hidden "Soon" items, €/% hero toggle) are all committed in the spine. Two gaps would actually block a downstream consumer: the Hero — the centerpiece of the redesigned dashboard — has a behavioral contract but no visual spec in DESIGN.md.Components, and no contrast targets are stated anywhere despite EXPERIENCE explicitly delegating contrast to DESIGN.md. Everything else is name-drift and small state holes that a careful implementer could survive but shouldn't have to guess through.

## 1. Flow coverage — strong

Extracted PRD journeys UJ-1 through UJ-6 and matched against EXPERIENCE.md Key Flows. UJ-1 → Flow 1 (5 steps, climax at step 5, failure path), UJ-2 → Flow 2 (6 steps, climax at step 6, failure path), UJ-6 → Flow 3 (5 steps, climax at step 5, failure path). All three name protagonist Alex (fictional persona), mirror PRD journey titles verbatim, and carry an explicit **Climax** beat. Exclusions are stated in the spine itself (Key Flows preamble): UJ-4/UJ-5 named as future-phase analytics deliberately absent; UJ-3 named as agent-side with its UI counterpart identified as the same drift table Flow 1 reads. The blanket [ASSUMPTION] on step detail is the documented Fast-path consequence (decision log) and is honestly labeled.

### Findings

- **low** UJ-3's "same drift table as Flow 1" disposition lives only in the preamble paragraph; a consumer scanning flow headings sees three flows and must read prose to learn UJ-3 is intentionally folded in (EXPERIENCE.md, Key Flows preamble). *Fix:* none required; optionally add a one-line "UJ-3 — covered by Flow 1 step 4" stub heading so the mapping is scannable.
- **low** Flow 1's climax ("the number the agent spoke and the number on the screen are the same number, with the same basis date") depends on the UI and MCP sharing one basis-date source (FR-13); the spine asserts it but no surface states where "as of" originates. Same open question already flagged in State Patterns (stale-data row). *Fix:* keep the existing open-question note; architecture must close it.

## 2. Token completeness — adequate

Extracted all `{path.to.token}` references from both files (DESIGN prose: ~35 distinct; DESIGN components frontmatter: ~20; EXPERIENCE prose: 8) and resolved each against DESIGN.md frontmatter. **All references resolve** — no broken paths in either file, including `{components.input.focus}` and `{typography.mono-data}`. All color tokens carry concrete values; light/dark pairs exist for accents, semantics, surfaces, and the full text ramp. What's missing is the contrast layer and two internal contradictions.

### Findings

- **high** No contrast targets stated anywhere for load-bearing combinations — 13px {colors.text-muted} on {colors.bg}, accent stat values on {colors.bg-elevated}, {colors.warning} stale timestamps, 9px chart-axis mono — yet EXPERIENCE.md Accessibility Floor says "contrast and color rules live in `DESIGN.md`" (EXPERIENCE.md §Accessibility Floor; DESIGN.md has no contrast statement in Colors or Do's and Don'ts). The delegation chain dead-ends; an implementer or auditor has no AA/AAA commitment to verify against. *Fix:* add a short contrast block to DESIGN.md Colors (e.g. "body text ≥ 4.5:1 on all surfaces in both modes; accent-on-elevated verified per variant; chart-axis exempt as decorative? — decide and state it").
- **medium** `selected: '#ede9fe'` is a fixed violet hex, but Brand & Style and Colors prose say selected rows re-key with the active accent's `-soft` companion (DESIGN.md frontmatter line 47 vs. §Brand & Style "selected rows … re-keys to that choice" and §Colors "Each has a `-soft` companion used for selected rows"). A consumer flattening tokens ships violet selected-rows under the teal accent. *Fix:* either document `selected` as an alias of the active `accent-*-soft` (value = violet default) or remove the literal and reference the accent indirection.
- **medium** `chart-surface` / `chart-surface-dark` (`#ffffff` / `#131a23`) are defined but never referenced; `components.chart-frame.background` uses `{colors.bg}` (`#f6f7fa`) instead — two different answers for the chart background (DESIGN.md frontmatter lines 43/57 vs. line 156). *Fix:* point chart-frame at `{colors.chart-surface}` or delete the unused pair.
- **low** `tx-buy` / `tx-sell` have no `-dark` pairs, breaking the otherwise-complete "dark is a full token set" convention (DESIGN.md frontmatter lines 36–37). The white marker stroke probably saves them, but say so. *Fix:* add dark pairs or a one-line "same value both modes; white stroke carries separation" note.
- **low** The four `accent-*-soft-dark` values use `rgb(… / 0.16)` functional notation; the spec says hex strings (design-md-spec.md, colors row). Resolvable by any consumer, but a strict parser keying on `'#'` will choke. *Fix:* keep if alpha is essential, but note the deviation deliberately.
- **low** Several component-token values are prose, not references: `value-color: 'accent (active variant)'`, `shadow: 'shadow-panel'`, nav-link-active's `'accent-soft'` (DESIGN.md frontmatter lines 130–154). The `--color-accent` indirection *is* explained in Colors prose, and shadows have no frontmatter home in the spec — defensible, but these cells don't machine-resolve. *Fix:* acceptable as-is; consider a `# resolves via [data-accent]` comment so the non-resolvability reads as intent.

## 3. Component coverage — adequate

Cross-referenced every component named in EXPERIENCE.md Component Patterns (8 rows) and flows against DESIGN.md Components (12 inventory entries), and vice versa. Strong overlap with real rules on both sides — behavioral rows are genuinely behavioral (debounce values, focus-return, toggle busy states), visual entries are genuinely anatomical. Two asymmetric holes.

### Findings

- **high** **Hero (total value + curve)** — the "one fixed element of the home," carrying the owner-decided €/% toggle — has a full behavioral row in EXPERIENCE.md Component Patterns but **no entry in DESIGN.md Components** and no frontmatter component tokens. Which typography role is the headline number ({typography.stat-value} at 30px? {typography.page-title}?), what the €/% toggle looks like (reuse `.chart-toggle`?), and how hero + curve + period pills compose are all unspecified (EXPERIENCE.md Component Patterns "Hero" row; DESIGN.md §Components has no hero entry). This is the highest-traffic new surface of the run; a story-dev invents the dashboard centerpiece. *Fix:* add a `hero` entry to DESIGN.md Components (and frontmatter `components.hero`) naming the headline type role, toggle anatomy, and curve frame relationship.
- **medium** **Allocation visuals** (donut, sunburst, drift table) have visual identity in DESIGN.md but no behavioral row in EXPERIENCE.md Component Patterns — yet Flow 1's climax walks through them. Do sunburst segments respond to hover/tap? Does the legend filter? Is the drift table sortable? (DESIGN.md §Components "Allocation visuals"; EXPERIENCE.md Component Patterns lacks the row.) *Fix:* add one behavioral row, even if it's "read-only visuals, no segment interaction; drift table follows the Tables row."
- **low** The Flow 3 scope switcher has neither visual nor behavioral spec; honestly tagged [ASSUMPTION] with #327 named as in-flight (EXPERIENCE.md Flow 3 step 1). Downstream is blocked on UJ-6 until #327 lands — acceptable, but the dependency should be visible to sprint planning. *Fix:* none in this run; carry as an open question.
- **low** Classification tree node anatomy (category swatch, count, pinned Unsorted bucket styling) is behavioral in EXPERIENCE but only glancingly visual in DESIGN ("drift tables with category swatches"; dnd-row chips) (DESIGN.md §Components "Drag-and-drop rows"). *Fix:* one sentence on node anatomy in the DESIGN inventory.

## 4. State coverage — adequate

Walked all seven IA surfaces against the State Patterns table. Covered: cold load (server-rendered, no-skeleton rationale stated), action-pending busy states, empty-no-data (Dashboard, with the Workflow-path retirement decision), per-surface empties with the one-sentence-plus-action rule, validation and action-failure errors, stale-data treatment with its open question honestly flagged, and not-found inside the shell. Focus states live in Accessibility Floor. The generic rows ("Tables, trees", "Any") legitimately blanket Portfolios, Transactions, and Securities lists.

### Findings

- **medium** No "search/filter returned nothing" state, distinct from empty: Classifications live search "auto-expands matches" but its zero-match rendering is unstated, and Transactions is described as "record, review, filter" with no filtered-to-nothing treatment (EXPERIENCE.md Component Patterns "Classification tree"; State Patterns table). Both Quill and Drift examples carry this state explicitly. *Fix:* one State Patterns row: "Filter/search no matches — keep controls visible, 'No matches for X.', never the empty-surface message."
- **low** Imports failure states beyond the duplicate-file no-op (Flow 2 failure) are unspecified — unparseable file, rejected preview. The generic `.alert-error` banner row presumably catches them, but the import pipeline is the surface where errors matter most (EXPERIENCE.md Component Patterns "Import pipeline"). *Fix:* extend the pipeline row: "parse/validation failure ends at preview with `.alert-error`; nothing applied."
- **low** Not-found row enumerates only `/classifications/:id etc.` — `/securities/:id` and `/portfolios` children are inside "etc." (EXPERIENCE.md State Patterns "Not found"). *Fix:* spell out the two parameterized routes; "etc." invites drift.

## 5. Visual reference coverage — expected-empty, consistent

Directory listing: `imports/` exists and is empty; `mockups/` and `wireframes/` do not exist; `.working/` contains only `research-ux-best-practices.md` (research, correctly hidden from the deliverable set). Both example spines carry "→ Composition reference: mockups/….html. Spine wins on conflict." pointers; this pair has none — correct, since mocks come later in this run, and no dangling links were planted speculatively (good discipline: zero broken file references).

### Findings

- **low** When mockups land, the IA section should gain the composition-reference pointer with the "spine wins on conflict" clause per the example pattern (EXPERIENCE.md §Information Architecture, after the nav-model paragraph). *Fix:* deferred to the mockup step; noting the expected insertion point.

## 6. Bloat & overspecification — strong

Both files are tight. DESIGN.md is extraction-honest: it lists only spacing constants that actually exist and explicitly refuses to invent a spacing scale or heading ramp ("Gap (open question)" callouts in Typography and Layout & Spacing) — that is the correct altitude, pushing invention to the redesign stories rather than fabricating tokens. EXPERIENCE.md's [ASSUMPTION] tags (13) are the documented Fast-path posture, not hedging. No section pads, no restated PRD content, no speculative component inventory. The one near-overspecification — Motion's mechanism lane (stroke-dasharray, `@property`) — explicitly cedes the final call to architecture, which keeps it on the right side of the line.

### Findings

- **low** DESIGN.md §Components doubles as a CSS-class concordance (`.stat`, `.dnd-row`, `.detail-*-table`). For a brownfield extraction this is value, not bloat — it's the map from spec to existing code — but entries like "Import surfaces — drop zone, progress, stat cards, warning boxes" are inventory lines, not specs. *Fix:* none; flag so nobody mistakes inventory-grade entries for full visual specs.

## 7. Inheritance discipline — strong

EXPERIENCE.md `sources` frontmatter: all five paths verified on disk (prd.md, .decision-log.md, priv/static/app.css, lib/portfolixir_web/components/app_shell.ex, lib/portfolixir_web/components/security_chart.ex). UJ names verbatim from PRD §3 (checked character-for-character on all three flow titles). All eight EXPERIENCE token references resolve to DESIGN frontmatter by exact name. FR references (FR-2, FR-4, FR-6/7, FR-13, FR-28) all exist in the PRD. Decision-log decisions all landed in the spine: paradigm blockquote, motion-as-polish, hidden Soon items, ≥44px coarse-pointer targets, €/% hero toggle, confirmed card set, IST-only IA with #321 cited.

### Findings

- **low** Component naming drifts between the files: EXPERIENCE "Metric cards" ↔ DESIGN "Stat card"; "Tables" ↔ "Data tables"; "Import pipeline" ↔ "Import surfaces"; "Classification tree" ↔ "Drag-and-drop rows … classifications tree" (EXPERIENCE.md Component Patterns vs. DESIGN.md §Components). Each pair is cross-linked in prose (e.g. Metric cards names `.stat` anatomy; DESIGN stat-card points back to "EXPERIENCE.md Component Patterns"), so a human resolves it — but mechanical source-extraction keyed on names produces four misses. *Fix:* align names, or add the counterpart name in parentheses on each side.

## 8. Shape fit — adequate

DESIGN.md: all eight canonical body sections present in locked order (Brand & Style → Do's and Don'ts), frontmatter carries the required `name`/`description` plus colors/typography/rounded/spacing/components per spec. EXPERIENCE.md: all default sections present (Foundation, IA, Voice and Tone, Component Patterns, State Patterns, Interaction Primitives, Accessibility Floor, Key Flows); Inspiration & Anti-patterns omitted, defensible because the lifted/rejected decisions (visualization-only rejected, Parqet freshness precedent, no bottom tab bar) are recorded in the paradigm blockquote, State Patterns, and the decision log.

Responsive & Platform trigger check: Portfolixir is a three-surface product (desktop/iPad/iPhone) and the section is **absent** — but responsive content exists and is findable: the nav model per form factor in IA, breakpoints (900/720/560) in DESIGN Layout & Spacing, bottom-sheet conversion in the Tables row, coarse-pointer touch targets in Accessibility Floor, touch chart behavior in the Security chart row. Defensible, not ideal.

### Findings

- **medium** Responsive behavior is scattered across four sections in two files, with the breakpoint table living only in DESIGN.md (a visual-identity file) while the behaviors it triggers (off-canvas sidebar, bottom sheets, single-column dialogs) are experience facts (DESIGN.md §Layout & Spacing; EXPERIENCE.md IA/Component Patterns/Accessibility Floor). The Drift example shows the expected shape for a responsive product: one Responsive & Platform table. A story-dev implementing the 720px bottom-sheet conversion must collate three places. *Fix:* add a compact Responsive & Platform section (or table) to EXPERIENCE.md consolidating breakpoint → behavior, pointing to DESIGN for the pixel values.
- **low** `### Motion` rides as a subsection under Do's and Don'ts — outside the spec's eight canonical sections (design-md-spec.md body list; DESIGN.md end). The content fully earns its place (owner-binding decision, reduced-motion gate, mechanism lane), but the decision log itself assigned "perceived behavior" to the UX spine, and EXPERIENCE rows defer to "DESIGN.md Motion" — the pair's own division of labor (visual ↔ behavioral) is inverted here. It works because the cross-reference resolves. *Fix:* acceptable as-is; if touched again, move perceived motion behavior into EXPERIENCE (e.g. under Interaction Primitives) and leave only the mechanism/aesthetic constraints in DESIGN.

## Mechanical notes

- **All `{path.to.token}` references in both files resolve** against DESIGN.md frontmatter — zero broken token refs (verified individually, including nested `{components.input.focus}`, `{typography.body.fontFamily}`, `{spacing.panel-pad}`).
- **All five EXPERIENCE `sources` paths exist on disk.** DESIGN.md carries no `sources` block — consistent with the three DESIGN examples; the extraction provenance is stated in its opening blockquote instead.
- **Name inconsistencies** (cross-file component labels): Metric cards/Stat card, Tables/Data tables, Import pipeline/Import surfaces, Classification tree/Drag-and-drop rows. All human-resolvable via in-prose cross-links; see finding 7.
- **Internal token contradictions:** `selected` (fixed violet) vs. accent-soft re-keying prose; `chart-surface` defined-but-unused vs. `chart-frame.background: {colors.bg}`. See findings 2.
- **Unreferenced tokens** (defined, never cited in prose or components): `chart-surface`, `chart-surface-dark`, `border-strong`, `border-strong-dark`, `hover`, `hover-dark`, `bg-muted-dark` is cited; the border-strong/hover families are extraction-real CSS variables and harmless to keep.
- **Cross-document section references resolve:** EXPERIENCE → "DESIGN.md Motion" (exists), "DESIGN.md.Components" (exists), "EXPERIENCE.md Component Patterns" cited from DESIGN stat-card (exists). PRD references (UJ titles, §2 persona, FR-2/4/6/7/13) verified in prd.md.
- **Frontmatter completeness:** DESIGN has spec-required `name` + `description` plus the BMad wrapper keys (title/status/created/updated) — extra keys are additive, no conflict. Both files `status: draft`, consistent with the decision log's "pending owner review"; draft-review decisions of 2026-06-13 are already incorporated, so status could advance once this review is dispositioned.
