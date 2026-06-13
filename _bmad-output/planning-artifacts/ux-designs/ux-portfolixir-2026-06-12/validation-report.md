# Validation Report — portfolixir

- **DESIGN.md:** `{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-portfolixir-2026-06-12/DESIGN.md`
- **EXPERIENCE.md:** `{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-portfolixir-2026-06-12/EXPERIENCE.md`
- **Run at:** 2026-06-13

## Overall verdict

A disciplined, extraction-grounded spine pair: every token reference in both files resolves, flow names mirror the PRD verbatim, scope exclusions are stated where a consumer will look, and the decision log's binding choices (paradigm, motion, touch targets, hidden "Soon" items, €/% hero toggle) are all committed in the spine. Two gaps would actually block a downstream consumer: the Hero — the centerpiece of the redesigned dashboard — has a behavioral contract but no visual spec in DESIGN.md.Components, and no contrast targets are stated anywhere despite EXPERIENCE explicitly delegating contrast to DESIGN.md. Everything else is name-drift and small state holes that a careful implementer could survive but shouldn't have to guess through.

The accessibility lens shifts that picture: the spine is unusually accessibility-literate for a planning artifact — reduced-motion gating, 44px coarse-pointer targets, drag-with-fallback, Esc/focus-return rules, and semantic landmarks all stated as binding — but it carries two systemic gaps the rubric's contrast finding only hinted at. First, a contrast hole in the light-mode text ramp and the coral accent/tx-buy tokens (text-subtle at 2.47:1 fails every use; buy markers at 2.54:1 fail the 3:1 graphics bar). Second, the absence of any non-color-channel requirement for the app's most important semantics — gain/loss, drift, buy/sell, staleness — in a finance tool whose entire point is signed numbers. Both were cheap to fix at spec level and would have been expensive to retrofit.

Disposition (reviewer gate, 2026-06-13): all critical, high, and medium findings were fixed in both spines; trivial lows applied; three lows accepted as-is per reviewer; two items deferred — basis-date source to architecture, scope switcher to #327.

## Category verdicts

- Flow coverage — strong
- Token completeness — adequate
- Component coverage — adequate
- State coverage — adequate
- Visual reference coverage — strong (expected-empty, consistent)
- Bloat & overspecification — strong
- Inheritance discipline — strong
- Shape fit — adequate

## Findings by severity

### Critical (1)

**[Accessibility]** — `text-subtle` fails contrast in light mode (DESIGN.md §Colors)
2.47:1 on `bg`, 2.64:1 on `bg-elevated`; dark `bg-elevated` only 3.03:1. DESIGN.md labels it "tertiary/disabled" — "tertiary" is a license to use it for real content (as-of dates, hints, table meta), where it fails both 4.5:1 and even the 3:1 large-text bar.
Fix: Restrict `text-subtle` to disabled states and pure decoration explicitly ("never for conveying content"), and either darken the light value (~#6e7a8e reaches ≈4.5:1) or route all readable tertiary content to `text-muted` (5.50:1, passes).
Disposition: **Fixed in spine, 2026-06-13.**

### High (6)

**[Token completeness]** — No contrast targets stated for load-bearing combinations (EXPERIENCE.md §Accessibility Floor; DESIGN.md §Colors / Do's and Don'ts)
13px {colors.text-muted} on {colors.bg}, accent stat values on {colors.bg-elevated}, {colors.warning} stale timestamps, 9px chart-axis mono — yet EXPERIENCE.md says "contrast and color rules live in DESIGN.md". The delegation chain dead-ends; no AA/AAA commitment to verify against.
Fix: Add a short contrast block to DESIGN.md Colors (body text ≥ 4.5:1 on all surfaces in both modes; accent-on-elevated verified per variant; decide and state whether chart-axis is exempt as decorative).
Disposition: **Fixed in spine, 2026-06-13.**

**[Component coverage]** — Hero (total value + curve) has a behavioral row but no visual spec (EXPERIENCE.md Component Patterns "Hero"; DESIGN.md §Components)
The "one fixed element of the home," carrying the owner-decided €/% toggle, has no entry in DESIGN.md Components and no frontmatter component tokens. Headline typography role, toggle anatomy, and hero + curve + period-pill composition are all unspecified — a story-dev invents the dashboard centerpiece.
Fix: Add a `hero` entry to DESIGN.md Components (and frontmatter `components.hero`) naming the headline type role, toggle anatomy, and curve frame relationship.
Disposition: **Fixed in spine, 2026-06-13.**

**[Accessibility]** — No non-color channel for gain/loss, drift, buy/sell, or staleness (EXPERIENCE.md Flow 1 step 4 / State Patterns; DESIGN.md buy/sell markers; WCAG 1.4.1)
Overweights/underweights in {colors.positive}/{colors.danger}, the stale timestamp's {colors.warning} tone shift, and identically-shaped buy/sell circles all encode meaning in hue alone.
Fix: Binding Accessibility Floor line: signed values always render an explicit "+/−" (or ▲/▼), buy/sell markers differ in shape (▲ buy / ▼ sell) not just fill, stale state carries a text/icon cue alongside the warning tone.
Disposition: **Fixed in spine, 2026-06-13.**

**[Accessibility]** — `tx-buy` on the light chart surface is 2.54:1, below the 3:1 graphics minimum (DESIGN.md tx-buy #10b981 / chart-surface #ffffff; WCAG 1.4.11)
The white stroke ring doesn't rescue the fill. (`tx-sell` 3.76:1 passes; both pass in dark mode.)
Fix: Darken light-mode buy markers (e.g. reuse `positive` #047857, 5.48:1) or give markers a `border-strong`-level outline plus the shape channel.
Disposition: **Fixed in spine, 2026-06-13.**

**[Accessibility]** — Modal spec has no focus-trap / `aria-modal` / inert-background requirement (EXPERIENCE.md Component Patterns "Forms behind disclosure")
Esc-close and focus-return-to-trigger are specified, but nothing keeps focus inside `.modal` or marks the page inert — without a bundler this must be planned as a deliberate small hook, or it won't happen.
Fix: Modal opens → focus moves to first field / dialog heading, `role="dialog" aria-modal="true"`, focus trapped (hand-written hook or native `<dialog>` with `showModal()`).
Disposition: **Fixed in spine, 2026-06-13.**

**[Accessibility]** — Two accessibility-floor guarantees are [ASSUMPTION]-tagged (EXPERIENCE.md §Accessibility Floor)
"Data behind any chart is always also reachable as a table" and "`lang` follows the active locale" are the load-bearing mitigations for the 9px chart axis and de/en screen-reader pronunciation; as assumptions, implementers may drop them.
Fix: Promote both to binding (the chart-table rule is also the only thing that makes `role="img"` + single `aria-label` an acceptable chart strategy).
Disposition: **Fixed in spine, 2026-06-13.**

### Medium (14)

**[Token completeness]** — `selected` is a fixed violet hex but prose says selected rows re-key with the active accent (DESIGN.md frontmatter line 47 vs. §Brand & Style / §Colors)
A consumer flattening tokens ships violet selected-rows under the teal accent.
Fix: Document `selected` as an alias of the active `accent-*-soft` (value = violet default) or remove the literal and reference the accent indirection.
Disposition: Fixed in spine, 2026-06-13.

**[Token completeness]** — Two different answers for the chart background (DESIGN.md frontmatter lines 43/57 vs. line 156)
`chart-surface` / `chart-surface-dark` defined but never referenced; `components.chart-frame.background` uses `{colors.bg}` instead.
Fix: Point chart-frame at `{colors.chart-surface}` or delete the unused pair.
Disposition: Fixed in spine, 2026-06-13.

**[Component coverage]** — Allocation visuals have visual identity but no behavioral row (DESIGN.md §Components "Allocation visuals"; EXPERIENCE.md Component Patterns)
Flow 1's climax walks through donut, sunburst, drift table; hover/tap, legend filtering, and sortability are unspecified.
Fix: Add one behavioral row, even if it's "read-only visuals, no segment interaction; drift table follows the Tables row."
Disposition: Fixed in spine, 2026-06-13.

**[State coverage]** — No "search/filter returned nothing" state distinct from empty (EXPERIENCE.md Component Patterns "Classification tree"; State Patterns)
Classifications live search zero-match rendering unstated; Transactions has no filtered-to-nothing treatment.
Fix: One State Patterns row: "Filter/search no matches — keep controls visible, 'No matches for X.', never the empty-surface message."
Disposition: Fixed in spine, 2026-06-13.

**[Shape fit]** — Responsive behavior scattered across four sections in two files (DESIGN.md §Layout & Spacing; EXPERIENCE.md IA / Component Patterns / Accessibility Floor)
Breakpoint table (900/720/560) lives only in DESIGN.md while the behaviors it triggers are experience facts; a story-dev implementing the 720px bottom-sheet conversion must collate three places.
Fix: Add a compact Responsive & Platform section to EXPERIENCE.md consolidating breakpoint → behavior, pointing to DESIGN for pixel values.
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — Coral accent fails as normal-size text in light mode (accent-coral 4.38:1 on bg, 3.91:1 on coral-soft)
30px stat values are large text and pass; body-size accent text does not. Violet (5.32) and teal (5.11) already pass.
Fix: Accent may color text only at large size (≥ 24px / 19px bold) or non-text indicators; body-size accent text in light mode needs a darkened text-grade coral (e.g. #be123c ≈ 5.2:1).
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — Reduced-motion gating over-rotates on spinners (EXPERIENCE.md motion rules)
The busy spinner IS information; hiding it behind `no-preference` leaves reduced-motion users with no feedback during chart-toggle loads.
Fix: Exempt loading indication — under `reduce`, swap the spinner for a non-animated cue; keep `phx-click-loading` visible either way.
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — CSS-only sidebar toggle cannot update `aria-expanded` (EXPERIENCE.md "Sidebar state … is a pure CSS toggle")
Expanded/collapsed state and accessible name can't change without JS; the off-canvas (<900px) variant additionally needs Esc-close and focus handling, currently unspecified.
Fix: Real `<input type="checkbox">` with a state-neutral name, or a 5-line hook toggling `aria-expanded` on a `<button>`; spell out off-canvas Esc/focus behavior.
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — `<details>` theme/accent menus assert JS coordination without assigning a mechanism (EXPERIENCE.md Interaction Primitives)
Esc-close and mutual exclusivity require JS the spine doesn't assign; also unstated that these are disclosure widgets, not ARIA menus.
Fix: One sentence: "implemented as native `<details>` disclosure semantics (no role=menu); a shared hand-written hook provides Esc-close and mutual exclusivity."
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — ⓘ metric tooltips have no keyboard/touch access spec (EXPERIENCE.md Voice and Tone examples; WCAG 1.4.13)
"Hover-only affordances on touch surfaces" are banned in Interaction Primitives, but the examples only say "tooltip/hover definition."
Fix: Require the ⓘ to be a focusable element whose definition appears on focus and tap, dismisses on Esc, and doesn't vanish while hovered.
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — Form error association is visual-only (EXPERIENCE.md State Patterns ".field-error at the field")
No `aria-describedby`/`aria-invalid`/error-summary-focus requirement.
Fix: Error text linked via `aria-describedby`, field gets `aria-invalid="true"`, on failed submit focus moves to first invalid field or the `.alert-error` (`role="alert"`/`aria-live`).
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — Focus indicator may be too faint (DESIGN.md {components.input.focus}; WCAG 2.4.13 / 1.4.11)
An 18%-opacity accent ring composites to well under 3:1; on nav links/rows/buttons the soft ring alone won't carry.
Fix: Solid 2px full-accent outline (+ optional soft halo) as the universal focus style.
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — Keyboard path for multi-select + drag in Classifications is incomplete (EXPERIENCE.md Component Patterns "Classification tree")
How rows enter multi-selection without a pointer is unspecified; HTML5/pointer drag generally won't fire on touch, making the toolbar the de-facto iPad/iPhone path.
Fix: Checkbox-based (or Space-toggles) row selection feeding the same toolbar; on coarse pointers select+toolbar is primary, drag desktop-only.
Disposition: Fixed in spine, 2026-06-13.

**[Accessibility]** — Tiny load-bearing type: 9px chart axis and 9.5px locale pills (DESIGN.md typography; EXPERIENCE.md locale switcher)
Axis labels are real data (mitigated only by the chart-table rule); the EN/DE switcher is an always-used interactive control at the smallest type in the system.
Fix: Bump locale-switcher text to ≥ 11px; keep 9px axes only on condition the table equivalent is binding; don't cap zoom.
Disposition: Fixed in spine, 2026-06-13.

### Low (17)

**[Flow coverage]** — UJ-3 disposition lives only in the preamble paragraph (EXPERIENCE.md, Key Flows preamble)
A consumer scanning flow headings must read prose to learn UJ-3 is intentionally folded into Flow 1's drift table.
Fix: Optionally add a one-line "UJ-3 — covered by Flow 1 step 4" stub heading.
Disposition: Applied, 2026-06-13.

**[Flow coverage]** — Flow 1 climax depends on a single basis-date source no surface states (EXPERIENCE.md Flow 1 / State Patterns stale-data row)
The spine asserts UI and MCP share one basis-date source (FR-13) but no surface states where "as of" originates.
Fix: Keep the existing open-question note; architecture must close it.
Disposition: Deferred to architecture, 2026-06-13.

**[Token completeness]** — `tx-buy` / `tx-sell` have no `-dark` pairs (DESIGN.md frontmatter lines 36–37)
Breaks the otherwise-complete "dark is a full token set" convention.
Fix: Add dark pairs or a "same value both modes; white stroke carries separation" note.
Disposition: Applied, 2026-06-13 (dark pairs added alongside the tx-buy contrast fix).

**[Token completeness]** — `accent-*-soft-dark` values use rgb() functional notation; spec says hex strings (DESIGN.md frontmatter; design-md-spec.md colors row)
A strict parser keying on '#' will choke.
Fix: Keep if alpha is essential, but note the deviation deliberately.
Disposition: Applied, 2026-06-13 (notation comment).

**[Token completeness]** — Several component-token values are prose, not references (DESIGN.md frontmatter lines 130–154)
`value-color: 'accent (active variant)'`, `shadow: 'shadow-panel'`, nav-link-active's `'accent-soft'` don't machine-resolve; the indirection is explained in prose.
Fix: Acceptable as-is; consider a `# resolves via [data-accent]` comment.
Disposition: Accepted as-is, 2026-06-13.

**[Component coverage]** — Flow 3 scope switcher has neither visual nor behavioral spec (EXPERIENCE.md Flow 3 step 1)
Honestly tagged [ASSUMPTION] with #327 named as in-flight; downstream blocked on UJ-6 until #327 lands.
Fix: None in this run; carry as an open question.
Disposition: Deferred — #327 dependency, 2026-06-13.

**[Component coverage]** — Classification tree node anatomy only glancingly visual in DESIGN (DESIGN.md §Components "Drag-and-drop rows")
Category swatch, count, pinned Unsorted bucket styling are behavioral in EXPERIENCE but barely visual in DESIGN.
Fix: One sentence on node anatomy in the DESIGN inventory.

**[State coverage]** — Import failure states beyond the duplicate-file no-op are unspecified (EXPERIENCE.md Component Patterns "Import pipeline")
Unparseable file and rejected preview presumably fall to the generic `.alert-error` row, but the import pipeline is where errors matter most.
Fix: Extend the pipeline row: "parse/validation failure ends at preview with `.alert-error`; nothing applied."
Disposition: Applied, 2026-06-13.

**[State coverage]** — Not-found row hides parameterized routes behind "etc." (EXPERIENCE.md State Patterns "Not found")
`/securities/:id` and `/portfolios` children are inside "etc.", which invites drift.
Fix: Spell out the two parameterized routes.
Disposition: Applied, 2026-06-13.

**[Visual reference coverage]** — IA section will need the composition-reference pointer when mockups land (EXPERIENCE.md §Information Architecture, after the nav-model paragraph)
Pointer with the "spine wins on conflict" clause per the example pattern.
Fix: Deferred to the mockup step; expected insertion point noted.

**[Bloat & overspecification]** — DESIGN.md §Components doubles as a CSS-class concordance (DESIGN.md §Components)
For a brownfield extraction this is value, not bloat — but entries like "Import surfaces" are inventory lines, not specs.
Fix: None; flagged so nobody mistakes inventory-grade entries for full visual specs.
Disposition: Accepted as-is, 2026-06-13.

**[Inheritance discipline]** — Component naming drifts between the files (EXPERIENCE.md Component Patterns vs. DESIGN.md §Components)
Metric cards/Stat card, Tables/Data tables, Import pipeline/Import surfaces, Classification tree/Drag-and-drop rows. Cross-linked in prose, but mechanical extraction keyed on names produces four misses.
Fix: Align names, or add the counterpart name in parentheses on each side.

**[Shape fit]** — Motion rides as a subsection under Do's and Don'ts (DESIGN.md end; design-md-spec.md body list)
Outside the eight canonical sections; the pair's own visual/behavioral division of labor is inverted here, but the cross-reference resolves.
Fix: Acceptable as-is; if touched again, move perceived motion behavior into EXPERIENCE.
Disposition: Accepted as-is, 2026-06-13.

**[Accessibility]** — `aria-live` page-title region: politeness level unspecified (EXPERIENCE.md Accessibility Floor)
Assertive would interrupt on every patch.
Fix: State `aria-live="polite"` and that only the title text node changes.
Disposition: Applied, 2026-06-13.

**[Accessibility]** — Chart toggles and period pills lack pressed-state semantics (EXPERIENCE.md / DESIGN.md .chart-toggle)
State conveyed by accent color alone; ties into the color-independence finding.
Fix: `.chart-toggle` uses `aria-pressed`; period pills use `aria-pressed` or radio-group semantics.
Disposition: Applied, 2026-06-13.

**[Accessibility]** — Scope switch leans on the rebuild animation as a change cue (EXPERIENCE.md Flow 3)
Under `prefers-reduced-motion` the scope label is the only cue, and its placement/prominence is unspecified.
Fix: Require the scope name in the page subtitle or hero basis line on every portfolio-bearing surface; announce scope changes via the existing live region.
Disposition: Applied, 2026-06-13 (scope-label rule).

**[Accessibility]** — `text-soft` (3.48:1 light) only [ASSUMPTION]-flagged as decorative (DESIGN.md §Colors)
Dark-mode value (10.41) is fine.
Fix: Promote to a hard rule ("never body copy") so the 3.48 ratio never meets real text.

## Reviewer files

- `review-rubric.md`
- `review-accessibility.md`
