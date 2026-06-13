---
title: Portfolixir DESIGN.md
status: final
created: 2026-06-12
updated: 2026-06-13
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
  # buy marker reuses positive-green in light mode (meets 3:1 on chart surface); dark keeps the brighter pair
  tx-buy: '#047857'
  tx-buy-dark: '#10b981'
  tx-sell: '#ef4444'
  tx-sell-dark: '#ef4444'
  # Surfaces — light
  bg: '#f6f7fa'
  bg-elevated: '#ffffff'
  bg-muted: '#eef1f6'
  sidebar: '#fbfaff'
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
  # No formal scale exists in app.css today — see Layout & Spacing (open question).
  sidebar-width: 220px
  sidebar-rail: 72px
  topbar-height: 52px
  section-pad: 'clamp(18px, 2.4vw, 28px)'
  panel-pad: 'clamp(18px, 3vw, 26px)'
components:
  stat-card:
    background: 'color-mix(in srgb, {colors.bg-elevated} 94%, transparent)'
    border: '1px solid {colors.border}'
    radius: '{rounded.lg}'
    shadow: 'shadow-panel'
    top-bar: 'linear-gradient(90deg, {colors.brand-violet-1}, {colors.brand-teal-1} 55%, {colors.brand-coral-1})'
    value: '{typography.stat-value}'
    value-color: 'accent (active variant)'
    label: '{typography.stat-label}'
  hero:
    composition: 'headline value + as-of basis line above the curve; €/% series toggle and period pills on the chart toolbar row'
    value: '{typography.stat-value}'
    basis-line: '{typography.stat-label}'
    toggle: 'reuses .chart-toggle anatomy; aria-pressed state'
    curve: '{components.chart-frame}'
    pills: '.period-buttons .button-mini'
  panel:
    background: 'color-mix(in srgb, {colors.bg-elevated} 94%, transparent)'
    border: '1px solid {colors.border}'
    radius: '{rounded.lg}'
    padding: '{spacing.panel-pad}'
  nav-link-active:
    background: 'linear-gradient(90deg, accent-soft, transparent 80%)'
    border: '1px solid accent at 26% opacity'
    marker: '6px filled accent dot with 3px soft halo'
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
    focus: 'accent border + 3px accent ring at 18% opacity'
  chart-frame:
    background: '{colors.chart-surface}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    aspect-ratio: '3 / 1'
    line: 'accent, 1.6px stroke'
    area-fill: 'accent at 14% opacity'
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

> Extracted from `priv/static/app.css` (the only stylesheet; hand-written, no Tailwind, no bundler) and the two existing function components (`app_shell.ex`, `security_chart.ex`). This document describes what exists; deltas for the decluttering run are marked.

## Brand & Style

Portfolixir is a self-hosted instrument for one operator. The surface reads like a quiet professional terminal: a 13px information-dense base, tabular numerals for money, monospace for chart data, soft elevated panels on a faintly accent-tinted canvas. It is unmistakably a tool — but a warm one: the body background carries a radial accent glow in the top-left corner, the sidebar has a subtle sheen, and the brand expresses itself through **one switchable accent color at a time**, derived from the three-color logo gradient (violet → teal → coral).

The accent system is the identity anchor (owner-loved, binding): the operator picks violet, teal, or coral in the top bar, and the entire surface — active nav, chart lines, focus rings, stat values, selected rows — re-keys to that choice. Dark and light mode both exist and stay; dark is not an afterthought but a full token set.

The decluttering direction (this run) changes hierarchy and disclosure, not this visual language. [ASSUMPTION] The existing token set is treated as final for the redesign; no new hues are introduced beyond the tokens above.

## Colors

- **The three accent variants** — {colors.accent-violet} / {colors.accent-teal} / {colors.accent-coral} (light), {colors.accent-violet-dark} / {colors.accent-teal-dark} / {colors.accent-coral-dark} (dark) — are mutually exclusive. `--color-accent` resolves to exactly one of them via `[data-accent]`; violet is the default. Each has a `-soft` companion used for selected rows, active-nav washes, and success alerts. The accent means "interactive / current / yours" — it colors the chart line, the active nav marker, focus outlines, and the big stat numbers.
- **The brand gradient stops** ({colors.brand-violet-1} → {colors.brand-teal-1} → {colors.brand-coral-1}) appear *together* in exactly one place today: the 3px top bar of `.stat` cards. They are the only moment all three logo colors coexist; keep it that rare.
- **Semantic colors** are accent-independent: {colors.positive} for gains, {colors.danger} for losses and destructive actions, {colors.warning} for caution states, {colors.tx-buy} / {colors.tx-sell} for transaction markers on charts. Gain/loss color never re-keys with the accent — money semantics outrank brand.
- **Surfaces** layer tonally: {colors.bg} canvas → {colors.bg-elevated} panels/inputs → {colors.bg-muted} table heads and wells. The sidebar has its own near-white violet-tinted surface ({colors.sidebar}) with a gradient sheen. Dark mode mirrors the whole stack on a blue-black ramp ({colors.bg-dark} → {colors.bg-elevated-dark} → {colors.bg-muted-dark}).
- **Text** has four steps, two of which may carry content: {colors.text} (primary) and {colors.text-muted} (secondary — the floor for anything readable). {colors.text-subtle} is for **disabled states and pure decoration only** — at 2.47:1 in light mode it must never convey content; readable tertiary content uses {colors.text-muted}. {colors.text-soft} is a violet-leaning decorative step, never body copy (3.48:1 light).

**Theme mechanism (as built):** `prefers-color-scheme` media queries provide system-follow defaults; explicit `[data-theme="light"|"dark"]` attributes override them. The top bar exposes a three-state theme menu (system / light / dark) and the accent menu (violet / teal / coral). Both are progressive-enhancement controls (CSS `<details>` + small hooks), no bundler involved.

**Contrast commitments (binding; full computed table in `review-accessibility.md`):**

- Normal-size text ≥ 4.5:1 on its surface in both modes — satisfied by {colors.text} and {colors.text-muted} only; the other text steps are barred from content (above).
- Accent as text: violet and teal pass at body size in both modes; **coral passes only as large text** (≥ 24px, or 19px bold — the 30px stat values qualify). Body-size coral text in light mode is barred (4.38:1).
- Semantic colors ({colors.positive} / {colors.danger} / {colors.warning}) pass ≥ 4.5:1 on all standard surfaces in both modes.
- Meaningful graphics (chart lines, buy/sell markers) ≥ 3:1 against {colors.chart-surface}.
- Focus indicator: solid 2px accent outline ≥ 3:1 against adjacent colors; the 18%-opacity soft ring is decoration, never the indicator (see EXPERIENCE Accessibility Floor).
- 9px chart-axis type is tolerated only because every chart's data is also reachable as a table (EXPERIENCE Accessibility Floor, binding).

Avoid: introducing a fourth accent, using accent colors for gain/loss, gradients on content surfaces (gradients live only in the body backdrop, sidebar sheen, stat top bar, and active-nav wash).

## Typography

Two families, both already shipped: **Inter** ({typography.body.fontFamily}) for everything human-readable, **JetBrains Mono** for machine-flavored data — chart axes, tooltips, code-like identifiers. Money values use `font-variant-numeric: tabular-nums` so columns align.

The ramp is density-first:

- {typography.body} — 13px/1.4 is the base (14px under 560px). This is a deliberate terminal density; do not inflate it.
- {typography.stat-value} — 30px/700, tabular, accent-colored: the "big number" voice for metric cards.
- {typography.page-title} — clamp(28px→42px)/780 exists for hero headers but is barely used on workspace pages today.
- {typography.topbar-title} — 15px/760: the page identity in the sticky top bar.
- {typography.nav-group-head} and {typography.stat-label} — small uppercase tracked labels; the only all-caps voices.
- {typography.chart-axis} — 9px mono inside SVG.

Inter is used at variable-font weights (540, 650, 680, 700, 740, 760, 780) — fine-grained weight is the primary hierarchy device, not size.

**Gap (open question):** there is no defined heading ramp between 15px (top bar) and 28px+ (page-header); `.workspace-section h2/h3` have no explicit size and fall back to browser defaults. The redesign should fix this with two named roles rather than inventing values here.

## Layout & Spacing

The shell is a fixed left sidebar ({spacing.sidebar-width}) plus a sticky, blur-backed top bar ({spacing.topbar-height}). On desktop the sidebar collapses to an icon rail ({spacing.sidebar-rail}) via the toggle; content reflows. Workspace pages are full-bleed vertical stacks of `.workspace-section` bands separated by 1px borders, each padded with {spacing.section-pad}; card grids use `repeat(auto-fit, minmax(220px, 1fr))` with 16px gaps.

Breakpoints (as built): **900px** — sidebar leaves the flow and becomes an off-canvas overlay; **720px** — dialogs/menus go single-column, row context menus become bottom sheets; **560px** — base font bumps to 14px, page subtitles hide, tables scroll horizontally.

**Gap (open question):** app.css has **no spacing scale**. Gaps and paddings are ad-hoc (2, 4, 5, 6, 7, 8, 10, 12, 14, 16, 18, 22 px plus `clamp()` expressions), and later sections drift into rem units (0.4rem, 0.6rem…). The frontmatter intentionally lists only the structural constants that genuinely exist. Defining a 4px-based scale is a redesign task, not an extraction result.

## Elevation & Depth

Elevation is tonal-plus-soft-shadow, never harsh:

- `--shadow-sm` (0 1px 2px @ 5%) — buttons.
- `--shadow-md` (0 10px 22px @ 10%) — popovers, context menus.
- `--shadow-panel` (0 18px 44px @ 8%) — panels and stat cards: large blur, very low opacity, "soft glow" rather than drop shadow.
- `--shadow-sidebar` (0 20px 60px @ 16%) — the sidebar's separation from content.

Dark mode swaps the slate-tinted shadows for deeper black ones (up to 50% opacity) because tonal contrast carries less there. The sticky top bar adds depth via translucency: 88% elevated-surface color with `backdrop-filter: blur(18px)`.

Hierarchy device of record: surface tone first, border second, shadow third. Tables and tree nodes use borders only.

## Shapes

Three radii: {rounded.sm} (6px) for tooltips, small chips, kebab buttons; {rounded.md} (8px) for buttons, inputs, nav links, chart frames, alerts, menus; {rounded.lg} (12px) for panels and stat cards. Pills ({rounded.full}) are reserved for tiny status markers: the "Soon" nav pill, locale pills, nav marker dots, splitter handles. Nothing is sharp-cornered; nothing larger than 12px. The feel is "crisp tool with softened edges."

## Components

All components are hand-written CSS classes consumed by LiveView templates — there is no component library and no CoreComponents. The named inventory that exists today:

- **App shell** (`.app-shell`) — fixed sidebar with grouped nav (`.nav-group`, uppercase group heads, icon + label rows). Active link: accent-soft gradient wash, accent-tinted border, filled accent marker dot with halo. Disabled future items render with a "Soon" pill. The Classifications group is dynamic — one nav entry per classification plus a `+` affordance.
- **Top bar** (`.topbar`) — burger toggle, brand (shown when sidebar is hidden/collapsed), page title + subtitle, then the control cluster: theme menu, accent menu, EN/DE locale switcher. Delta: locale-switcher pill text renders ≥ 11px (9.5px uppercase is below the readable floor for an always-used control).
- **Stat card** (`.stat`) — see {components.stat-card}: the three-color gradient hairline on top, uppercase label, 30px accent value. Currently shows entity counts; the redesigned dashboard reuses this anatomy for the owner-confirmed metric set (cash quote, TTWROR, top drift, transaction recency — see EXPERIENCE.md Component Patterns).
- **Hero** (dashboard centerpiece, new this run) — see {components.hero}: headline total in {typography.stat-value}, the as-of basis line in {typography.stat-label} beneath it, the performance curve in a {components.chart-frame} below, the €/% series toggle reusing `.chart-toggle` anatomy (with `aria-pressed`), period pills attached to the frame. [ASSUMPTION] The composition (value above curve, toggle on the frame's toolbar row) is drafted, not owner-confirmed — [mockups/key-dashboard.html](mockups/key-dashboard.html) is the composition reference; spine wins on conflict.
- **Panel** (`.panel`) — generic elevated container, {components.panel}.
- **Data tables** (`.data-table`, `.detail-*-table`, `.drift-table`, `.cash-table`) — 13px rows, muted 12px heads on {colors.bg-muted}, hover wash of accent-soft at 42%, selected rows on {colors.selected}. Numeric cells use tabular numerals.
- **Security chart** (`.chart-frame` + `.security-chart`) — server-rendered SVG (960×320 viewBox, 3:1 frame): accent quote line (1.6px) over a 14%-opacity accent area fill, optional moving-average overlays (`.chart-ma-30/50/200`), cost-basis line, buy/sell markers — shape-coded, never hue alone: ▲ buy in {colors.tx-buy}, ▼ sell in {colors.tx-sell}, white stroke (delta: today's identical circles fail color-independence; the light-mode buy fill is darkened to meet 3:1), mono axis text. Crosshair + mono tooltip provided by a small hand-written hook. Toggle buttons (`.chart-toggle`) and period pills (`.period-buttons .button-mini`) accompany it.
- **Allocation visuals** — donut and sunburst SVGs with legends (`.donut`, `.sunburst-seg`), drift tables with category swatches.
- **Forms** — stacked label-over-input grids ({components.input}); buttons are quiet elevated rectangles ({components.button}) with `.button-primary` / `.button-danger` variants; inline forms (`.inline-form`) sit directly in page flow today — this is the pattern the decluttering run pushes behind disclosure.
- **Feedback** — `.alert-error` (coral-soft), `.alert-success` (accent-soft), `.alert-warning`, dashed-border `.empty-state` wells, `.hint` text.
- **Overlays** — `.modal` + backdrop, `.popover` for column pickers and filters, `.row-context-menu` (kebab menu that becomes a bottom sheet under 720px).
- **Import surfaces** — drop zone, progress, stat cards, warning boxes.
- **Drag-and-drop rows** (`.dnd-row`, `.dnd-dropzone`, classifications tree) — draggable security rows with chips and dropzones.

## Do's and Don'ts

| Do | Don't |
|---|---|
| Let exactly one accent variant be active; re-key everything interactive to it | Mix two accent variants on one surface (the stat hairline is the sole sanctioned exception) |
| Keep gain/loss in {colors.positive}/{colors.danger}, independent of accent | Color money semantics with the brand accent |
| Keep the 13px density base and weight-driven hierarchy | Inflate font sizes to fake hierarchy |
| Tabular numerals + mono for data, Inter for prose | Proportional digits in money columns |
| Soft, large-blur shadows ({components.panel}) for elevation | Hard drop shadows or border-heavy boxes |
| Preserve dark + light parity for every new token | Light-only features that break in dark mode |
| Put forms behind disclosure (modal, popover, collapsed section) | Inline always-open forms in the primary sightline (current Classifications anti-pattern) |
| Grow interactive targets to ≥44px under `@media (pointer: coarse)` | Ship the 32–34px desktop density untouched to iPhone/iPad |
| Pair every semantic hue with a sign or shape (+/−, ▲/▼, glyph) | Encode gain/loss, buy/sell, or staleness in hue alone |

### Motion

Motion is **polish only** — it decorates state arrival, it never encodes information (binding decision).

- **Chart build-in:** one-shot on load/data-change, ~600ms–1.5s, ease-out. Perceived behavior: the performance line draws in from left to right, area fill fades up, bars grow from the baseline, headline numbers count up. Staggering (e.g. bars left→right) is allowed for texture but carries no meaning. Never looping, never replaying on scroll.
- **Mechanism lane (architecture owns the final call; no JS bundler exists):** CSS `stroke-dasharray`/`stroke-dashoffset` line draw-in, `transform: scaleY()` bar growth from `transform-origin: bottom`, CSS `@property` count-up for numerals. [ASSUMPTION] Count-up degrades to a static number in browsers without `@property` support.
- **Micro-motion (as built, keep):** 140–180ms ease transitions on nav hover, sidebar collapse, and color shifts; a 0.7s spinner on loading tabs.
- **Reduced motion:** gate ALL animation behind `@media (prefers-reduced-motion: no-preference)` — the opt-in form, so reduced-motion users get the finished frame instantly. (Today only the tab spinner has a `reduce` fallback; the redesign makes the gate global.)
- **Never:** looping ambience, parallax, motion on every LiveView patch, animated layout shifts in tables.
