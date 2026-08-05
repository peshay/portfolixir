---
title: Portfolixir DESIGN.md
status: draft
created: 2026-06-12
updated: 2026-08-05
name: Portfolixir
description: Self-hosted portfolio tracker. Dense, calm, data-first LiveView surface with one accent at a time — violet, teal, or coral, all derived from the logo.
colors:
  # Logo-derived brand gradient stops (used together only in the .stat top bar)
  brand-violet-1: '#a78bfa'
  brand-violet-2: '#7c3aed'
  brand-teal-1: '#2dd4bf'
  brand-teal-2: '#0f766e'
  brand-coral-1: '#fdba74'
  brand-coral-2: '#e11d48'
  # The three switchable accent variants (one active at a time via [data-accent]).
  # -soft-dark values keep rgb()-with-alpha notation deliberately (translucency is essential) — a known deviation from the hex-only spec.
  accent-violet: '#7c3aed'
  accent-violet-soft: '#ede9fe'
  accent-violet-dark: '#a78bfa'
  accent-violet-soft-dark: 'rgb(167 139 250 / 0.16)'
  accent-teal: '#0f766e'
  accent-teal-soft: '#ccfbf1'
  accent-teal-dark: '#2dd4bf'
  accent-teal-soft-dark: 'rgb(45 212 191 / 0.16)'
  accent-coral: '#e11d48'
  accent-coral-soft: '#ffe4e6'
  accent-coral-dark: '#fb7185'
  accent-coral-soft-dark: 'rgb(225 29 72 / 0.16)'
  # Semantic
  positive: '#047857'
  positive-dark: '#34d399'
  danger: '#dc2626'
  danger-dark: '#fb7185'
  warning: '#b45309'
  warning-dark: '#fbbf24'
  # Tint behind warning notes. Light-only in app.css today — see Colors (defect).
  warning-soft: '#fffbeb'
  warning-soft-dark: '[OPEN] undefined in app.css'
  # buy marker reuses positive-green in light mode (meets 3:1 on chart surface); dark keeps the brighter pair
  tx-buy: '#047857'
  tx-buy-dark: '#10b981'
  tx-sell: '#ef4444'
  tx-sell-dark: '#ef4444'
  # Constant-white by design (issue 449): text on an accent fill, and the plate
  # behind real image logos, stay white in every theme.
  on-accent: '#ffffff'
  logo-plate: '#ffffff'
  # Surfaces — light
  bg: '#f6f7fa'
  bg-elevated: '#ffffff'
  bg-muted: '#eef1f6'
  sidebar: '#fbfaff'
  sidebar-sheen: 'rgb(255 255 255 / 0.68)'
  chart-surface: '#ffffff'
  border: '#e4e8ef'
  border-strong: '#cdd4df'
  hover: '#f0f3f8'
  # alias of the ACTIVE accent-*-soft — violet default shown; re-keys with [data-accent]
  selected: '#ede9fe'
  text: '#0e141b'
  text-muted: '#5a6577'
  text-soft: '#8b7f9f'
  text-subtle: '#94a0b4'
  # Surfaces — dark
  bg-dark: '#0b0f14'
  bg-elevated-dark: '#131a23'
  bg-muted-dark: '#1a2230'
  sidebar-dark: '#0e141b'
  sidebar-sheen-dark: 'rgb(167 139 250 / 0.06)'
  chart-surface-dark: '#131a23'
  border-dark: '#222b38'
  border-strong-dark: '#2d3848'
  hover-dark: '#1b2533'
  selected-dark: '#1f2c42'
  text-dark: '#e6eaf1'
  text-muted-dark: '#8b97a8'
  text-soft-dark: '#c4b5fd'
  text-subtle-dark: '#5c667a'
typography:
  body:
    fontFamily: 'Inter, ui-sans-serif, system-ui'
    fontSize: 13px
    lineHeight: '1.4'
  page-title:
    fontFamily: 'Inter'
    fontSize: 'clamp(28px, 4vw, 42px)'
    fontWeight: '780'
    lineHeight: '1.15'
  section-title:
    fontFamily: 'Inter'
    fontSize: 20px
    fontWeight: '700'
    lineHeight: '1.15'
  subsection-title:
    fontFamily: 'Inter'
    fontSize: 16px
    fontWeight: '680'
    lineHeight: '1.15'
  topbar-title:
    fontFamily: 'Inter'
    fontSize: 15px
    fontWeight: '760'
    lineHeight: '1.15'
  stat-value:
    fontFamily: 'Inter'
    fontSize: 30px
    fontWeight: '700'
    lineHeight: '1'
    letterSpacing: -0.01em
  stat-label:
    fontFamily: 'Inter'
    fontSize: 12px
    fontWeight: '650'
    letterSpacing: 0.04em
  nav-label:
    fontFamily: 'Inter'
    fontSize: 12.5px
  nav-group-head:
    fontFamily: 'Inter'
    fontSize: 10.5px
    fontWeight: '700'
    letterSpacing: 0.08em
  table-cell:
    fontFamily: 'Inter'
    fontSize: 13px
  table-head:
    fontFamily: 'Inter'
    fontSize: 12px
    fontWeight: '740'
  control-label:
    fontFamily: 'Inter'
    fontSize: 12px
    fontWeight: '500'
    letterSpacing: 0.04em
  mono-data:
    fontFamily: '"JetBrains Mono", "SF Mono", ui-monospace'
    fontSize: 12px
  chart-axis:
    fontFamily: '"JetBrains Mono", ui-monospace'
    fontSize: 9px
rounded:
  sm: 6px
  md: 8px
  lg: 12px
  full: 9999px
spacing:
  # 4px scale, as built (app.css:51-58). Pinned by
  # test/invariants/css_spacing_scale_test.exs — tokens AND adoption.
  # Every margin, padding and gap uses a step; no ad-hoc px, no rem drift.
  '1': 4px
  '2': 8px
  '3': 12px
  '4': 16px
  '5': 20px
  '6': 24px
  '7': 32px
  '8': 48px
  # Structural constants that are not on the scale by design.
  sidebar-width: 220px
  sidebar-rail: 72px
  topbar-height: 52px
  section-pad-block: 'clamp(18px, 2.4vw, 28px)'
  section-pad-inline: 'clamp(14px, 2.4vw, 28px)'
  panel-pad: 'clamp(18px, 3vw, 26px)'
components:
  stat-card:
    background: 'color-mix(in srgb, {colors.bg-elevated} 94%, transparent)'
    border: '1px solid {colors.border}'
    radius: '{rounded.lg}'
    shadow: 'shadow-panel'
    top-bar: 'linear-gradient(90deg, {colors.brand-violet-1}, {colors.brand-teal-1} 55%, {colors.brand-coral-1})'
    value: '{typography.stat-value}'
    value-color: 'accent (active variant) — EXCEPT signed money, which takes {colors.positive}/{colors.danger}'
    label: '{typography.stat-label}'
    min-height: 120px
  hero:
    composition: 'headline value + as-of basis line above the curve; €/% series toggle and period control on the chart toolbar row'
    value: '{typography.stat-value}'
    basis-line: '{typography.stat-label}'
    toggle: 'reuses {components.selected-segment}; aria-pressed state'
    curve: '{components.chart-frame}'
    period: '{components.period-control}'
  panel:
    background: 'color-mix(in srgb, {colors.bg-elevated} 94%, transparent)'
    border: '1px solid {colors.border}'
    radius: '{rounded.lg}'
    padding: '{spacing.panel-pad}'
  selected-nav:
    scope: 'sidebar navigation and first/second-level tabs'
    sidebar-active: 'accent-soft→transparent 80% gradient wash, 1px border at accent 26%, 6px filled accent marker dot with 3px halo'
    tab-active: 'label in {colors.accent}, 2px {colors.accent} bottom border, weight 600'
    tab-rest: '{typography.control-label} in {colors.text-muted}, 2px transparent bottom border'
    icons: 'first-level tabs carry an icon + label; second-level tabs are the same control, smaller and iconless'
    width-reserved: 'required — see {components.width-reserve}'
  selected-segment:
    scope: 'toggles, filters, period selection — anything picking one of N adjacent options'
    group: 'inline-flex, 1px solid {colors.border}, radius {rounded.md}, background {colors.bg}, overflow hidden'
    option: 'min-height 30px, padding 4px 9px, {typography.control-label} in {colors.text-muted}, 1px {colors.border} divider, no radius, no shadow'
    option-hover: 'background {colors.hover}, text {colors.text}'
    option-active: 'filled {colors.accent}, text {colors.on-accent}'
    width-reserved: 'required — see {components.width-reserve}'
  selected-row:
    scope: 'selection inside lists, tables and trees'
    background: '{colors.selected}'
    edge: 'inset 3px 0 0 {colors.accent} on the leading edge (LTR: left)'
    text: 'unchanged; the row label may take {colors.accent} but must not change weight'
    width-reserved: 'required — see {components.width-reserve}'
  data-note:
    scope: 'anything the app tells the operator about their data'
    severities: 'note · attention · problem — exactly three, never a fourth'
    encoding: 'colour AND icon AND word, never colour alone (UX-DR7/UX-DR17)'
    note: 'border 1px {colors.border}, background {colors.bg-muted}, text {colors.text-muted}'
    attention: 'border 1px {colors.warning}, background {colors.warning-soft}, text {colors.warning}'
    problem: 'border 1px {colors.danger}, background {colors.danger} at soft tint, text {colors.danger}'
    radius: '{rounded.md}'
    padding: '{spacing.2} {spacing.3}'
    icon: '[OPEN] one glyph per severity, from the shared icon vocabulary — set undecided'
  period-control:
    appearance: '{components.selected-segment}'
    tokens: '1M 3M 6M YTD 1Y 3Y 5Y Max — one vocabulary app-wide; each surface declares the subset it offers'
    custom-range: 'behind a disclosure ({components.disclosure}), never permanent chrome'
    date-fields: '{components.native-control} — ISO in the input, not only in the display'
  disclosure:
    scope: 'data-as-table under every chart; custom range; entry forms out of the reading sightline'
    control: 'quiet text summary — {typography.control-label} in {colors.text-muted}, pointer cursor'
    marker: 'defined chevron, never the raw browser triangle'
    purpose-line: 'one short line stating why the disclosure exists'
    label: '[OPEN] one wording app-wide; copy belongs to EXPERIENCE.md Voice and Tone'
    body: '{components.data-table} for the data-as-table case'
  value-slot:
    scope: 'every rendered money, percentage or quantity that can be absent'
    metrics: 'the slot reserves its final footprint in all four states; no state may reflow its neighbours'
    numerals: 'tabular-nums in every state, including mid-count'
    final: '{typography.stat-value} or {typography.table-cell}, full colour'
    pending: 'last known value at {colors.text-muted} with a recomputing cue and its as-of date; where no prior value exists, a shimmer sized to the value footprint (never a generic block)'
    pending-fallback: 'skeleton gradient reuses .section-skeleton stops at text size — gated behind prefers-reduced-motion: no-preference, unlike the shipped block skeleton'
    settling: 'digits at {colors.text-muted}, a 2px accent bar beneath growing 0 to full width over the count; on settle digits snap to full colour and the bar fades'
    not-computable: 'em dash, {colors.text-muted}, NOT at value weight — the state a stable input can rest in, so it must not look like a state in flight'
  width-reserve:
    rule: 'a control whose active state changes weight, adds an icon or adds an ornament reserves that space in its rest state'
    techniques: 'invisible bold shadow text, fixed track widths, or a permanently reserved ornament slot'
    tolerance: '0px — no measurable shift when selection moves'
  native-control:
    scope: 'date inputs, selects, <details> summaries, checkboxes, radios'
    container: 'inherits {components.input}'
    indicator: 'defined appearance — select chevron, disclosure chevron, checkbox mark — never the browser default'
    dates: 'ISO (YYYY-MM-DD) in input and display alike'
    checkbox: '14px box, accent-color {colors.accent}, label on the same line as the box'
  button:
    background: '{colors.bg-elevated}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    min-height: 34px
  input:
    background: '{colors.bg-elevated}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    min-height: 34px
    focus: 'solid 2px accent outline (the indicator) + optional 3px accent ring at 18% (decoration only)'
  data-table:
    head: '{typography.table-head} on {colors.bg-muted}'
    cell: '{typography.table-cell}, tabular numerals in numeric columns, numeric columns right-aligned'
    hover: 'accent-soft wash at 42%'
    selected: '{components.selected-row}'
    scroller: 'own overflow-x container — required, see Layout & Spacing'
  chart-frame:
    background: '{colors.chart-surface}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    aspect-ratio: '3 / 1'
    line: 'accent, 1.6px stroke'
    area-fill: 'accent at 14% opacity'
    data-as-table: '{components.disclosure} — mandatory on every chart surface'
  chart-tooltip:
    font: '{typography.mono-data}'
    background: '{colors.bg}'
    border: '1px solid {colors.border}'
    radius: '{rounded.sm}'
  pill:
    radius: '{rounded.full}'
    font: '9.5px, weight 700, uppercase, 0.06em tracking'
---

# Portfolixir — DESIGN.md

> The living visual spec (ADR-0038). Tokens are extracted from `priv/static/app.css` — the only stylesheet; hand-written, no Tailwind, no bundler. This document says how Portfolixir looks; `EXPERIENCE.md` says how it works. Where a rule in this file and the built UI disagree, the file is the target and the build carries the defect; every such disagreement is named below rather than quietly absorbed.
>
> Refreshed 2026-08-05 against the live-surface survey and the design critique of the 2026-08-01 UAT screenshots (`.decision-log.md`, session 2026-08-05).

## Brand & Style

Portfolixir is a self-hosted instrument for one operator. The surface reads like a quiet professional terminal: a 13px information-dense base, tabular numerals for money, monospace for chart data, soft elevated panels on a faintly accent-tinted canvas. It is unmistakably a tool — but a warm one: the body background carries a radial accent glow in the top-left corner, the sidebar has a subtle sheen, and the brand expresses itself through **one switchable accent color at a time**, derived from the three-color logo gradient (violet → teal → coral).

The accent system is the identity anchor (owner-loved, binding): the operator picks violet, teal, or coral in the top bar, and the entire surface — active nav, chart lines, focus rings, stat values, selected rows — re-keys to that choice. Dark and light mode both exist and stay; dark is not an afterthought but a full token set.

**The posture this refresh adds: one job, one solution.** The system is coherent at token level and incoherent at component level — the critique found every recurring UI job solved two to five times independently (five ways to say "selected", four ways to say something about the data, three ways to show a metric, three ways to render an empty value). Token fidelity is not design coherence. From here, a recurring job gets exactly one named component in this document, and a second treatment for the same job is a review reject, not a variant.

[ASSUMPTION] The existing token set is treated as closed; no new hues are introduced beyond the tokens above. Drift is corrected toward the tokens, never by adding one.

## Colors

- **The three accent variants** — {colors.accent-violet} / {colors.accent-teal} / {colors.accent-coral} (light), {colors.accent-violet-dark} / {colors.accent-teal-dark} / {colors.accent-coral-dark} (dark) — are mutually exclusive. `--color-accent` resolves to exactly one of them via `[data-accent]`; violet is the default. Each has a `-soft` companion used for selected rows, active-nav washes, and notes. The accent means "interactive / current / yours" — it colors the chart line, the active nav marker, focus outlines, and unsigned stat numbers.
- **The brand gradient stops** ({colors.brand-violet-1} → {colors.brand-teal-1} → {colors.brand-coral-1}) appear *together* in exactly one place: the 3px top bar of `.stat` cards. They are the only moment all three logo colors coexist; keep it that rare.
- **Semantic colors** are accent-independent: {colors.positive} for gains, {colors.danger} for losses and destructive actions, {colors.warning} for caution states, {colors.tx-buy} / {colors.tx-sell} for transaction markers on charts. **Gain/loss color never re-keys with the accent — money semantics outrank brand.**
- **Semantic color applies wherever a sign exists**, at every level of a table — data rows, subtotals and totals alike. A negative row and a negative total are the same fact at different granularity and must look like it.
- **{colors.on-accent} and {colors.logo-plate} are constant white in every theme** by design (issue 449): text sitting on an accent fill, and the plate behind real image logos, do not follow the theme.
- **Surfaces** layer tonally: {colors.bg} canvas → {colors.bg-elevated} panels/inputs → {colors.bg-muted} table heads and wells. The sidebar has its own near-white violet-tinted surface ({colors.sidebar}) with a gradient sheen. Dark mode mirrors the whole stack on a blue-black ramp ({colors.bg-dark} → {colors.bg-elevated-dark} → {colors.bg-muted-dark}).
- **Text** has four steps, two of which may carry content: {colors.text} (primary) and {colors.text-muted} (secondary — the floor for anything readable). {colors.text-subtle} is for **disabled states and pure decoration only** — at 2.47:1 in light mode it must never convey content; readable tertiary content uses {colors.text-muted}. {colors.text-soft} is a violet-leaning decorative step, never body copy (3.48:1 light).

**Theme mechanism (as built):** `prefers-color-scheme` media queries provide system-follow defaults; explicit `[data-theme="light"|"dark"]` attributes override them, and must win in both directions. The top bar exposes a three-state theme menu (system / light / dark) and the accent menu (violet / teal / coral). Both are progressive-enhancement controls (CSS `<details>` + small hooks), no bundler involved.

**Contrast commitments (binding):**

- Normal-size text ≥ 4.5:1 on its surface in both modes — satisfied by {colors.text} and {colors.text-muted} only; the other text steps are barred from content (above).
- Accent as text: violet and teal pass at body size in both modes; **coral passes only as large text** (≥ 24px, or 19px bold — the 30px stat values qualify). Body-size coral text in light mode is barred (4.38:1).
- Semantic colors ({colors.positive} / {colors.danger} / {colors.warning}) pass ≥ 4.5:1 on all standard surfaces in both modes.
- Meaningful graphics (chart lines, buy/sell markers) ≥ 3:1 against {colors.chart-surface}.
- Focus indicator: solid 2px accent outline ≥ 3:1 against adjacent colors; the 18%-opacity soft ring is decoration, never the indicator (see EXPERIENCE Accessibility Floor).
- 9px chart-axis type is tolerated only because every chart's data is also reachable as a table (EXPERIENCE Accessibility Floor, binding).

**[OPEN] The computed contrast table lives outside this document** — `../ux-designs/ux-portfolixir-2026-06-12/review-accessibility.md`, inside an archived review folder for a closed session. A binding table in an archived artifact is fragile: nothing updates it when a token moves, and nothing points a reviewer at it. The table must be carried into this section, per-pair, before this document leaves `draft`. It is not reproduced here from memory — the numbers are transcribed from the source or they are not written at all. Closes when: the table is copied in verbatim and the archive copy is marked superseded.

**[OPEN] Two pairings are not in the table at all** and must be measured when it is carried over: {colors.on-accent} on each of the three accent fills (the `selected-segment` active option, light and dark), and {colors.warning} on {colors.warning-soft}.

### Violations in the built UI (targets for correction, not licence)

- **Negative amounts render in the accent colour on the Wealth KPI cards.** `.stat strong { color: var(--color-accent) }` (app.css:983-990) colours every KPI value, sign-blind. This contradicts the rule two paragraphs up — gain/loss colour never re-keys with the accent — and, because there is no sign emphasis either, it also fails the colour-independence rule (UX-DR7) on the same element. Correction: signed values inside a stat card take {colors.positive}/{colors.danger} plus a sign, and only unsigned values take the accent.
- **Semantic colour is applied only at total rows.** Row-level negatives render in body ink while the total renders red — the reader is shown that the sum is negative but not which rows made it so. Correction: the rule above ("wherever a sign exists, at every level").
- **{colors.warning-soft} is light-only.** `--color-warning-soft: #fffbeb` is declared in `:root` (app.css:41) and never overridden for dark, so dark-mode warning notes put {colors.warning-dark} amber on a near-white cream ground. This breaks the dark/light parity rule under Do's and Don'ts. **[OPEN]** the dark value — a token must be chosen, not guessed here.
- **Three tokens are referenced but never defined:** `--color-border-subtle` (app.css:3649, 4285, 4337), `--color-surface-hover` (3652), `--color-surface` (2135). Each falls back to a hard-coded translucent grey that follows neither theme. The tab underline rule and the drift-table header therefore sit outside the token system entirely. Correction: replace with {colors.border} / {colors.hover} / {colors.bg-elevated}.
- **The accent is hard-coded to violet in six places** (app.css:2936, 3440, 3561, 3656, 3982-3983): the 30-day moving average, two drop-target borders, the selected-row edge, and the period buttons' active fill stay violet when the operator picks teal or coral. Correction: `var(--color-accent)`.

Avoid: introducing a fourth accent, using accent colors for gain/loss, gradients on content surfaces (gradients live only in the body backdrop, sidebar sheen, stat top bar, and active-nav wash).

## Typography

Two families, both already shipped: **Inter** ({typography.body.fontFamily}) for everything human-readable, **JetBrains Mono** for machine-flavored data — chart axes, tooltips, code-like identifiers. Money values use `font-variant-numeric: tabular-nums` so columns align — in every state, including mid-count-up, where proportional figures produce a visible wobble at constant digit count.

The ramp is density-first:

- {typography.body} — 13px/1.4 is the base (14px under 560px). This is a deliberate terminal density; do not inflate it.
- {typography.stat-value} — 30px/700, tabular: the "big number" voice for metric cards.
- {typography.page-title} — clamp(28px→42px)/780, the page identity on `.page-header h1`.
- {typography.section-title} — 20px/700 for `h2` inside a panel or workspace section.
- {typography.subsection-title} — 16px/680 for `h3`.
- {typography.topbar-title} — 15px/760: the page identity in the sticky top bar.
- {typography.control-label} — 12px/500, 0.04em: the shared voice of segmented options, tabs, period tokens and quiet disclosure summaries. One size for one class of control.
- {typography.nav-group-head} and {typography.stat-label} — small uppercase tracked labels; the only all-caps voices.
- {typography.chart-axis} — 9px mono inside SVG.

Inter is used at variable-font weights (500, 540, 600, 650, 680, 700, 740, 760, 780) — fine-grained weight is the primary hierarchy device, not size. **Weight changes on state must be width-reserved** ({components.width-reserve}).

**Closed since 2026-06-13:** the heading ramp gap. `--text-h1/h2/h3` size and weight tokens exist (app.css:60-65) and are pinned by `test/invariants/css_spacing_scale_test.exs`.

**Residual gaps:**

- The ramp is adopted on `.page-header h1`, `.panel h2/h3` and `.workspace-section h2/h3` only. Section headings written as anything else — `.detail-section-title` renders 13px/600 uppercase muted (app.css:2727) — sit off the ramp. Every heading resolves to h1, h2 or h3; there is no fourth step and no bespoke heading.
- 53 of 158 `font-size` declarations in app.css are in `rem`/`em`, the rest in `px`. Mixed units make the ramp unenforceable by inspection. **[ASSUMPTION]** px is the unit of record, matching the token definitions; closes when a lint rule or a review convention is agreed.

## Layout & Spacing

The shell is a fixed left sidebar ({spacing.sidebar-width}) plus a sticky, blur-backed top bar ({spacing.topbar-height}). On desktop the sidebar collapses to an icon rail ({spacing.sidebar-rail}) via the toggle; content reflows. Workspace pages are full-bleed vertical stacks of `.workspace-section` bands separated by 1px borders, padded {spacing.section-pad-block} block / {spacing.section-pad-inline} inline; card grids use `repeat(auto-fit, minmax(220px, 1fr))` with {spacing.4} gaps.

**The spacing scale exists and is binding.** Eight steps on a 4px base ({spacing.1} … {spacing.8}, app.css:51-58), covering every margin, padding and gap. `test/invariants/css_spacing_scale_test.exs` enforces both that the tokens are defined and that they are actually adopted — the scale cannot be defined and then ignored. Values off the scale are permitted only for the structural constants listed in the frontmatter and for `clamp()` expressions that interpolate between two of them; anything else is drift.

Breakpoints (as built): **900px** — sidebar leaves the flow and becomes an off-canvas overlay; **720px** — dialogs/menus go single-column, row context menus become bottom sheets; **560px** — base font bumps to 14px, page subtitles hide, tables scroll horizontally.

### Every wide block owns its scroller

`.workspace-page { overflow-x: clip }` (app.css:3934) is deliberate: `clip` does not create a scroll container, so the sticky select-toolbar keeps working and no stray over-wide child can scroll the whole page sideways. The consequence is equally deliberate and must be designed for — **a child wider than the viewport is truncated, not scrolled.** There is no page-level rescue.

Therefore, visually:

- Any block that can exceed the viewport width — data tables, chart label rows, legends, wide matrices — establishes its own `overflow-x: auto` container (`.data-table-wrapper`, `.table-scroll`).
- Every flex or grid child that contains such a block sets `min-width: 0`, or the container never shrinks and the scroller never engages.
- The scroller is visible as an affordance: the scrolled block sits in a bordered, radiused container so its edge reads as an edge, not as a cut.

This is the visual half of the rule EXPERIENCE.md carries as UX-DR15. Today it holds on snapshots (`.table-scroll`) and securities (`.data-table-wrapper`) and fails on income, whose 15-column matrix and flex label row have neither a scroller nor `min-width: 0` — the observed truncation of #560. Treated as a missing system rule; the next wide table reproduces it otherwise.

## Elevation & Depth

Elevation is tonal-plus-soft-shadow, never harsh:

- `--shadow-sm` (0 1px 2px @ 5%) — buttons.
- `--shadow-md` (0 10px 22px @ 10%) — popovers, context menus.
- `--shadow-panel` (0 18px 44px @ 8%) — panels and stat cards: large blur, very low opacity, "soft glow" rather than drop shadow.
- `--shadow-sidebar` (0 20px 60px @ 16%) — the sidebar's separation from content.

Dark mode swaps the slate-tinted shadows for deeper black ones (up to 50% opacity) because tonal contrast carries less there. The sticky top bar adds depth via translucency: 88% elevated-surface color with `backdrop-filter: blur(18px)`.

Hierarchy device of record: surface tone first, border second, shadow third. Tables and tree nodes use borders only. **Nothing inside a table gets a shadow** — the allocation table header currently renders two of four headers as white bordered boxes with shadow that overflow the header band, reading as stray buttons dropped into a header row. A cell is not a card.

Elevation encodes layer, never state. Selection, activity and severity are carried by the components below, not by lifting an element off the page.

## Shapes

Three radii: {rounded.sm} (6px) for tooltips, small chips, kebab buttons; {rounded.md} (8px) for buttons, inputs, nav links, chart frames, notes, menus; {rounded.lg} (12px) for panels and stat cards. Pills ({rounded.full}) are reserved for tiny status markers: locale pills, nav marker dots, splitter handles. Nothing is sharp-cornered; nothing larger than 12px. The feel is "crisp tool with softened edges."

Full-round is a *marker* shape, not a *control* shape. A pill-shaped interactive control reads as a badge and competes with the real badges; picking one of N options uses the segmented group ({components.selected-segment}), never a row of pills.

## Components

All components are hand-written CSS classes consumed by LiveView templates — no component library, no CoreComponents. Two function components exist (`app_shell.ex`, `security_chart.ex`) plus eight small inline hooks (`layout_view.ex`, `security_chart.ex`).

### Selected state — three classes, and only three

Five idioms are in the build today: solid accent pill (`.view-chip.is-active`), tint-plus-accent-text (`.segmented-control__option.is-active`, `.range-button.is-active`, `.chart-toggle.is-active`, `.icon-button.is-active`), solid fill inside a bordered container (`.period-buttons .button-mini.is-active`), gradient wash plus marker (`.nav-link.is-active`), underline (`.area-tab.is-active`, `.detail-pane-tab.is-active`), and tinted row (`.security-row.is-selected`, `.dnd-row.is-selected`). Several appear on the same screen. That is the drift being retired.

Three classes replace them. Every selectable control in the app maps to exactly one; a selected table row and an active tab are genuinely different things, which is why one idiom would be dogma and five is drift.

1. **Navigation and tabs → accent underline plus marker** ({components.selected-nav}). The sidebar keeps its established idiom — accent-soft gradient wash, accent-tinted border, 6px filled accent marker dot with halo — because it answers "where am I". Tabs get icon plus label plus a 2px accent underline, because they answer "which facet". Second-level tabs (inside Cash flow) are the same control, smaller and iconless. **One icon vocabulary app-wide:** a tab icon and the sidebar icon for the same destination are the same glyph, and no glyph carries two meanings — the funnel currently means "Views" in the sidebar and "filter" in the securities toolbar.
2. **Toggles, filters and period selection → segmented group with filled accent** ({components.selected-segment}). One bordered track, dividers between options, the active option filled {colors.accent} with {colors.on-accent} text. This absorbs `.segmented-control`, `.range-buttons`, `.chart-toggles`, `.period-buttons` and `.view-switcher`.
3. **Selection in lists and tables → tinted row with a left accent edge** ({components.selected-row}). {colors.selected} background plus a 3px inset accent edge on the leading side. The edge is what distinguishes selection from hover, which is a wash without an edge.

All three are width-reserved ({components.width-reserve}).

### Data note — three severities, one component

{components.data-note} replaces four competing treatments (plain bullet list, amber inline highlight, unstyled grey prose, accent-bordered banner) and the ad-hoc chips (`.not-held-chip`, `.stale-chip`, `.no-quote-chip`, `.negative-holding-chip`).

| Severity | Meaning | Colour | Required companions |
|---|---|---|---|
| Note | Context the operator may want | {colors.text-muted} on {colors.bg-muted} | icon + the word |
| Attention | Something to look at, nothing is wrong | {colors.warning} on {colors.warning-soft} | icon + the word |
| Problem | Something is wrong and needs action | {colors.danger} on a danger tint | icon + the word |

Colour is never the only channel (UX-DR7/UX-DR17). Consequence for the data-quality list: "valued at last trade price" is a **note**, "impossible negative holding quantity" is a **problem** — today they render identically, and the app's most important warning surface has the lowest visual weight on its page (a bare `<h2>` with default disc bullets, its actionable link styled like the surrounding prose). A data note carries its remedy control inside the note, not 1100px further down the page.

**[OPEN]** the three icon glyphs. They come from the one shared icon vocabulary; that set is not yet enumerated. Closes when the icon inventory is written down (same task as the tab/sidebar vocabulary above).

### Period control

{components.period-control}. One appearance — the segmented group — and one token vocabulary app-wide: **1M · 3M · 6M · YTD · 1Y · 3Y · 5Y · Max**. Each surface declares which subset it offers; no surface invents a token outside the set. "Custom range…" is a disclosure, not permanent chrome, and its date fields are {components.native-control}. This retires four patterns, two divergent token sets and four bare `type="date"` inputs.

### Data as table — one disclosure

{components.disclosure}, mandatory under every chart surface (UX-DR10), same control, same label, same styling — rendered as a quiet text control rather than the raw browser triangle, with a short purpose line so it is visible why it exists. Today three chart surfaces carry it with three different summary labels and two (the sunburst, the securities detail chart) carry none. De-emphasised, not deleted: it is the accessibility fallback that lets the 9px chart axis stand.

### Value slot

{components.value-slot}. Four states, four appearances:

| State | Meaning | Rule |
|---|---|---|
| Pending | value unknown, query in flight, lasts seconds | must not look like not-computable |
| Settling | value known, ~600ms count-up running | must be visibly not-yet-final |
| Final | value is the value | the reference appearance |
| Not-computable | there is no value to show | quiet, muted, not at value weight |

Today `…` (pending) and `—` (not-computable) are both bold at value size on the same KPI row (`portfolio_live.ex:715-780`) — "still loading" and "cannot be computed" are indistinguishable, and both are also indistinguishable from an error. Separating them is the point of the loading-affordance work.

The slot reserves its final footprint in every state, so nothing reflows when a value lands, and uses tabular numerals throughout including mid-count.

**Pending — last known value, dimmed** (owner pick 2026-08-05). The previous value stays in place at {colors.text-muted}, accompanied by a recomputing cue and the date it was computed. A magnitude is visible while the server works, instead of a void. Where no prior value exists — first load, a newly created account — the slot falls back to a shimmer sized to the value's own footprint, never the shipped 220px block. That fallback is the *only* skeleton this document specifies, and it is gated behind `prefers-reduced-motion: no-preference` (the shipped `.section-skeleton` is not — see Motion).

**Settling — accent bar under the number** (owner pick 2026-08-05). Digits render at {colors.text-muted} while a 2px bar in the active accent grows beneath them from zero to the slot's full width over the count. On settle the digits snap to full colour and the bar fades out. Progress is stated rather than implied, and the ornament sits outside the digits so no glyph is ever repainted — the failure mode is a missing bar, never an unreadable number.

Both states are non-decorative: they carry information about whether a number can be trusted yet. Under `prefers-reduced-motion` the animation drops but the *indication* remains — dimmed digits and a static bar at rest, never a silently final-looking value.

**Progressive chart fill — sequential sweep** (owner pick 2026-08-05). The allocation sunburst is a third case: many values landing over time rather than one. Segments appear clockwise as their values arrive. Accepted cost, stated so nobody re-litigates it later: the shape moves during the build, so the chart briefly shows proportions it does not have. Two constraints keep that honest — the build is short and one-shot, and **the legend must not settle before the geometry does**, so no label ever names a segment whose share is still changing.

### Native controls

{components.native-control}. Date inputs, selects, `<details>` summaries and checkboxes get defined appearances instead of browser defaults. This is where the "unfinished" impression concentrates: on the surveyed screens one date input, three selects, three `<details>` and one checkbox render in browser default beside carefully styled pills and segmented controls.

Precisely: app.css already styles the *container* — `input, select, textarea` share {components.input} — but not the *internals*. The select keeps the native chevron and native option list; `<details>` keeps the native triangle wherever the summary has no class; the checkbox has an accent colour but no defined mark. And `<input type="date">` renders `MM/DD/YYYY` in an otherwise fully ISO product. **Dates render ISO in inputs as well as in displays.**

The checkbox is one control: box and label sit on one line, the label is the hit target, and the pair is spaced on the scale. The classification form's broken checkbox stack — a bare box alone on a line with its label underneath, running into the next field's label — is the failure this rule prevents.

### Inventory (as built)

- **App shell** (`.app-shell`) — fixed sidebar with grouped nav (`.nav-group`, uppercase group heads, icon + label rows), active link per {components.selected-nav}. The Classifications group is dynamic — one nav entry per classification plus a `+` affordance. The sidebar background is viewport-height rather than page-height, leaving a cut edge on long pages — a defect. Nav entries follow ADR-0024: navigation reflects user tasks, not the storage model; a new entity does not get a sidebar entry by default.
- **Top bar** (`.topbar`) — burger toggle, brand, page title + subtitle, then theme menu, accent menu, EN/DE locale switcher (pill text ≥ 11px, pinned by the spacing-scale test).
- **Area tabs** (`.area-tabs`, `.detail-pane-tabs`) — the Wealth areas are Holdings · Allocation & targets · Cash flow · Snapshots · Tax; Cash flow's second level is Income · Realized gains · Deposits & withdrawals · Costs. Both levels per {components.selected-nav}.
- **Stat card** (`.stat`) — {components.stat-card}: three-color gradient hairline, uppercase label, 30px value. Signed values take semantic colour, not the accent (see Colors).
- **Hero** — **retired 2026-08-05.** {components.hero} was specified for the four-metric-card Overview of the superseded UX-DR2. That rule now follows the build (EXPERIENCE.md DR2): the Overview is value + change, "Needs attention", and data quality, and no hero component was ever built. The anatomy stays in the frontmatter as a record, unreferenced by any surface. [mockups/key-dashboard.html](mockups/key-dashboard.html) is downstream of the superseded rule and is **stale** — it illustrates a composition this document no longer specifies. Re-render or retire it before the mock is used as a reference again.
- **Panel** (`.panel`) — generic elevated container, {components.panel}.
- **Data tables** (`.data-table`, `.detail-*-table`, `.drift-table`, `.cash-table`, `.soll-table`) — {components.data-table}. One header treatment: {typography.table-head} on {colors.bg-muted}; the sentence-case-no-rules variant is retired. Numeric columns are right-aligned — app.css has per-table `.num` rules but no generic one, so income's money cells carry `class="num"` with nothing behind it.
- **Charts** — one shared component (`security_chart.ex`, ADR-0022) plus three hand-rolled implementations still in the build (income bars, snapshot two-polyline, sunburst). {components.chart-frame}: accent quote line (1.6px) over a 14%-opacity accent fill, moving-average overlays, cost-basis line, buy/sell markers shape-coded not hue-coded (▲ buy {colors.tx-buy}, ▼ sell {colors.tx-sell}), mono axis text, crosshair + mono tooltip via a small hook. New chart work uses the shared component; the snapshot comparison inherits its axes, crosshair and period control when it moves over.
- **Allocation visuals** — donut and sunburst SVGs with legends (`.donut`, `.sunburst-seg`), drift tables with category swatches, display-only rebalancing hints (`.rebalance-hint`, ADR-0023 — an annotation, never an action).
- **Tax budget** (`.tax-budget`) — allowance-order utilization per institution as a visual fill level with the remaining amount; recorded statements below as a list, each carrying its consistency finding as a {components.data-note} severity. Entry forms behind a disclosure; the five permanent prose paragraphs become ⓘ tooltips.
- **Forms** — stacked label-over-input grids ({components.input}); buttons are quiet elevated rectangles ({components.button}) with `.button-primary` / `.button-danger` variants. **One primary action treatment:** solid filled button; the outline button is the secondary; invisible grey inline text is not an action treatment. Forms sit behind disclosure, not in the primary sightline. Per-account actions live in their row (a cash balance is set from the account row, not from a global form).
- **Feedback** — {components.data-note} replaces `.alert-error` / `.alert-success` / `.alert-warning` / `.alert-info` / `.hint` / the dq chips. `.empty-state` wells stay. Inline busy and result states replace toasts (`.status-toast`, issue #566).
- **Overlays** — `.modal` + backdrop (native `<dialog>`, focus-trapped), `.popover` for column pickers and filters, `.row-context-menu` (kebab menu, bottom sheet under 720px).
- **Import surfaces** — drop zone, progress, stat cards, notes.
- **Drag-and-drop rows** (`.dnd-row`, `.dnd-dropzone`, classifications tree) — selection per {components.selected-row}.
- **Chips** — one chip: filled tag. The outline chip and the grey initial-avatar square are separate things wearing the chip's clothes; the avatar is a logo placeholder (`.security-logo--initial`) and reads as one.

## Do's and Don'ts

| Do | Don't |
|---|---|
| Solve each recurring job once, with the component named in this file | Invent a second treatment for a job this file already solves |
| Let exactly one accent variant be active; re-key everything interactive to it | Mix two accent variants on one surface (the stat hairline is the sole sanctioned exception) |
| Resolve the accent through `var(--color-accent)` | Hard-code `--color-accent-violet` in a rule that is not the violet definition |
| Keep gain/loss in {colors.positive}/{colors.danger}, independent of accent, at every row level | Colour money semantics with the brand accent, or colour only the total |
| Use one of the three selected-state classes | Add a sixth way to say "this is selected" |
| Reserve the metrics of any state that changes weight or adds an ornament | Bold on active and let the row shift 10–21px |
| Give every data message a severity, an icon and a word | Encode severity in colour alone, or in a bullet list |
| Style native controls — date, select, `<details>`, checkbox — to the language | Ship browser defaults beside custom controls |
| Render dates ISO in inputs as well as displays | Let the browser locale decide the input format |
| Give every wide block its own `overflow-x` container and `min-width: 0` | Rely on the page to scroll — `.workspace-page` clips |
| Make pending, settling, final and not-computable four distinct appearances | Render "loading" and "cannot be computed" as two similar glyphs |
| Keep the 13px density base and weight-driven hierarchy | Inflate font sizes to fake hierarchy |
| Resolve every heading to h1/h2/h3 on the ramp | Write a bespoke heading size |
| Use the spacing scale for every margin, padding and gap | Reintroduce ad-hoc px or rem spacing |
| Tabular numerals + mono for data, Inter for prose — including mid-count-up | Proportional digits in money columns |
| Soft, large-blur shadows ({components.panel}) for elevation | Hard drop shadows, or any shadow inside a table |
| Define every new token in both themes | Light-only tokens ({colors.warning-soft} is the live example) |
| Give every control a visible 2px focus outline | `outline: none` with a background change as the substitute |
| Grow interactive targets to ≥44px under `@media (pointer: coarse)` | Ship the 32–34px desktop density untouched to iPhone/iPad |
| Pair every semantic hue with a sign or shape (+/−, ▲/▼, glyph) | Encode gain/loss, buy/sell, or staleness in hue alone |
| Solve a design problem with a component | Fall back to a paragraph of prose (UX-DR11) |

Note on the last two rows, both measured in the build: five `:focus-visible` rules set `outline: none` and substitute a hover background (`.nav-link` app.css:399-403, `.accent-choice` 676-681, `.locale-link` 756-759, `.row-actions__kebab` 2123-2127, `.theme-choice`), and `input:focus` uses the 18%-opacity ring *as* the indicator rather than as decoration on top of a solid 2px outline — the commitment under Colors says the reverse. And prose is the default fallback for anything the design did not solve: six free-standing explanatory paragraphs across six screens, with the TTWROR explanation existing simultaneously as an ⓘ tooltip and as a paragraph on the same screen. UX-DR11 is not occasionally missed; prose is the habit.

### Motion

Motion is **polish only** — it decorates state arrival, it never encodes information (binding decision).

- **Chart build-in:** one-shot on load/data-change, ~600ms–1.5s, ease-out. Perceived behavior: the performance line draws in from left to right, area fill fades up, bars grow from the baseline, headline numbers count up. Staggering (e.g. bars left→right) is allowed for texture but carries no meaning. Never looping, never replaying on scroll.
- **Count-up is visibly not-final.** The 2026-08-05 owner ruling: a cosmetic count-up to the final value is wanted *provided it is evident the number is still counting*. That is the `settling` state of {components.value-slot} — no real partial values are ever streamed; the count starts only once the final value is known.
- **Mechanism lane, line drawing and bars:** CSS `stroke-dasharray`/`stroke-dashoffset` for the line draw-in, `transform: scaleY()` from `transform-origin: bottom` for bar growth. No JS involved, no bundler required.
- **Mechanism lane, count-up — the CSS `@property` assumption is falsified.** The previous draft specified a pure-CSS counter. It cannot work: `counter()` renders an integer with no separators — `250000`, never `250.000,00`. Pure-CSS count-up and locale-formatted money are mutually exclusive, and money is always locale-formatted here. There is no CSS-only path to a counting money value.
  **Resolved 2026-08-05 (owner):** a ninth hand-written inline LiveView hook — `requestAnimationFrame` driving the count, `Intl.NumberFormat` formatting each frame. The repo already carries eight (`AutoDismissToast`, `ChartCrosshair`, `ClassificationDnD`, `ColumnPrefs`, `PPImportDrop`, `PositionedMenu`, `SecuritySplitPane`, `SunburstTooltip`), so this is existing practice: no bundler, no dependency, no architecture change. The hook also drives the settling accent bar, which is why the bar can state real progress rather than merely claim it. The alternative — dropping count-up on money — was considered and declined.
- **Micro-motion (as built, keep):** 140–180ms ease transitions on nav hover, sidebar collapse, and color shifts; a 0.7s spinner on loading tabs.
- **Reduced motion:** gate ALL animation behind `@media (prefers-reduced-motion: no-preference)` — the opt-in form, so reduced-motion users get the finished frame instantly.
  **Live defect:** `.section-skeleton` animates `skeleton-shimmer 1.6s ease-in-out infinite` with no `prefers-reduced-motion` gate (app.css:4426-4437), on the dashboard and portfolio surfaces. It violates the reduced-motion rule and the no-looping-ambience rule below, simultaneously and in the build. Four other animations (`.detail-pane-tab` spinner, `.icon-button.is-busy`, `.status-toast`, `.spinner`) do carry a `reduce` fallback — the skeleton is the outlier, not the norm.
- **Never:** looping ambience, parallax, motion on every LiveView patch, animated layout shifts in tables.
