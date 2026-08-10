---
title: Portfolixir DESIGN.md
status: final
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
  # The active accent. This is the token every component references; it is an
  # ALIAS that [data-accent] re-points at one of the three variants below
  # (app.css:17-18, 166-167). Violet is the default shown here. Components must
  # reference {colors.accent} / {colors.accent-soft}, never a named variant —
  # referencing accent-violet directly is what hard-codes an accent.
  accent: '#7c3aed'
  accent-soft: '#ede9fe'
  accent-dark: '#a78bfa'
  accent-soft-dark: 'rgb(167 139 250 / 0.16)'
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
  # Darkened from #dc2626 on 2026-08-05 (designer, owner-delegated) to close the
  # danger-tint gate — the measurements, the consumer census and the cost are in
  # Colors → the danger-tint gate. Light mode only; danger-dark is untouched.
  danger: '#b91c1c'
  danger-dark: '#fb7185'
  warning: '#b45309'
  warning-dark: '#fbbf24'
  # Tint behind warning notes. Light-only in app.css today — see Colors (defect).
  warning-soft: '#fffbeb'
  # Decided 2026-08-05 by the designer (owner-delegated call), following the
  # -soft-dark idiom of the accent tokens: the dark hue at 0.16 translucency.
  # rgb(251 191 36) is {colors.warning-dark}. Not in app.css yet — see Colors.
  warning-soft-dark: 'rgb(251 191 36 / 0.16)'
  # Tint behind problem-severity notes. NOT a new hue: these are the values
  # `.alert-error` already renders (app.css:1167-1171), which borrows
  # --color-accent-coral-soft (app.css:16 / 81 / 142) for a semantic role.
  # Named here so {components.data-note}.problem stops referencing an
  # accent-variant token. The pairing failed at 4.02:1 while {colors.danger} was
  # #dc2626; with the darkened token it measures 5.39:1 — Colors → the
  # danger-tint gate. The 4.02:1 failure is still live in the build until the
  # token lands there.
  danger-soft: '#ffe4e6'
  danger-soft-dark: 'rgb(225 29 72 / 0.16)'
  # buy marker reuses positive-green in light mode (meets 3:1 on chart surface); dark keeps the brighter pair
  tx-buy: '#047857'
  tx-buy-dark: '#10b981'
  tx-sell: '#ef4444'
  tx-sell-dark: '#ef4444'
  # logo-plate stays constant white in every theme (issue 449). on-accent no
  # longer does: white on the dark accent fills measures 1.86–2.72:1 (Colors,
  # computed table). Decided 2026-08-05 — light #ffffff, dark #0b0f14.
  on-accent: '#ffffff'
  on-accent-dark: '#0b0f14'
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
  # INTENDED as an alias of the ACTIVE accent-*-soft. It is not one in the
  # build: --color-selected is a literal in :root (app.css:30), the dark media
  # query (93) and both [data-theme] blocks (124, 154), and never appears
  # inside a [data-accent] block (165-177), which set only --color-accent and
  # --color-accent-soft. Under teal or coral every selected row stays violet.
  # Filed as issue #644; listed under Colors → Violations. Violet default shown.
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
  # Breakpoints and target sizes, tokenised 2026-08-05 so both spines can
  # reference them instead of repeating literals. Values as built:
  # app.css:1200 (900), 2005/2175/2344 (720), 1271 (560), 4606-4613 (44px).
  # No --space-bp-* custom properties exist in app.css — media-query
  # conditions cannot read custom properties, so these are tokens of record
  # for the documents, and the stylesheet keeps the literals.
  bp-sidebar: 900px
  bp-dialog: 720px
  bp-density: 560px
  touch-target: 44px
  density-control: 34px
shadows:
  # As built (app.css:42-45 light; 99-101 dark media; 130-132 [data-theme=light];
  # 160-162 [data-theme=dark]). Dark swaps the slate tint for black at higher
  # opacity because tonal contrast carries less there.
  sm:
    light: '0 1px 2px rgb(15 23 42 / 0.05)'
    # Decided 2026-08-05 (designer, owner-delegated) by the idiom of the three
    # shipped dark values: black replaces the slate tint, the blur grows by the
    # same proportion md's does (22 → 28px, +27%; 2 → 3px rounded), and the
    # opacity takes md's 0.5 because sm and md are the two levels that land on
    # {colors.bg-elevated-dark} — panel and sidebar sit on the canvas. Not in
    # app.css yet; the light-only token is a live defect, see Violations.
    dark: '0 1px 3px rgb(0 0 0 / 0.5)'
  md:
    light: '0 10px 22px rgb(15 23 42 / 0.10)'
    dark: '0 10px 28px rgb(0 0 0 / 0.5)'
  panel:
    light: '0 18px 44px rgb(15 23 42 / 0.08)'
    dark: '0 18px 44px rgb(0 0 0 / 0.32)'
  sidebar:
    light: '0 20px 60px rgb(15 23 42 / 0.16)'
    dark: '0 20px 60px rgb(0 0 0 / 0.42)'
components:
  stat-card:
    background: 'color-mix(in srgb, {colors.bg-elevated} 94%, transparent)'
    border: '1px solid {colors.border}'
    radius: '{rounded.lg}'
    shadow: '{shadows.panel}'
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
    rule: 'UX-DR16 (mapping in EXPERIENCE.md), UX-DR18 for the reserved metrics'
    sidebar-active: 'background linear-gradient(90deg, {colors.accent-soft}, transparent 80%) — 80% is the gradient STOP POSITION, not an opacity; border-color color-mix(in srgb, {colors.accent} 26%, transparent); 6px marker dot filled {colors.accent} with box-shadow 0 0 0 3px color-mix(in srgb, {colors.accent} 18%, transparent) (app.css:410-414, 443-454)'
    tab-active: 'label in {colors.accent}, 2px {colors.accent} bottom border, weight 600'
    tab-rest: '{typography.control-label} in {colors.text-muted}, 2px transparent bottom border'
    icons: 'first-level tabs carry an icon + label; second-level tabs are the same control, smaller and iconless'
    target-size: 'BOUNDS ON "SMALLER" (UX-DR6, added 2026-08-05). Second-level tabs drop the icon and tighten the padding — nothing else. The label stays at {typography.control-label} (12px), and under @media (pointer: coarse) BOTH levels take {spacing.touch-target} min-height. "Smaller" never means below the floor. Today neither level has a coarse-pointer clause: .area-tab (app.css:4340-4346) declares no min-height at all and is padding-derived, so the first level fails the floor while the second-level .detail-pane-tab meets it (app.css:4603-4608) — inverted, and enumerated in EXPERIENCE.md → Alignment inventory → UX-DR6.'
    width-reserved: 'required — {components.width-reserve}, technique: invisible bold shadow text on the label'
  selected-segment:
    scope: 'toggles, filters, period selection — anything picking one of N adjacent options'
    rule: 'UX-DR16 (mapping in EXPERIENCE.md), UX-DR18 for the reserved metrics'
    group: 'inline-flex, 1px solid {colors.border}, radius {rounded.md}, background {colors.bg}, overflow hidden'
    option: 'min-height 30px, padding 4px 9px, {typography.control-label} in {colors.text-muted}, 1px {colors.border} divider, no radius, no shadow. The 30px is the DESKTOP density only; it is a third desktop step alongside {spacing.density-control} (34px) and is left unreconciled here — recorded as a follow-up, not solved opportunistically.'
    target-size: 'under @media (pointer: coarse) the option takes {spacing.touch-target} min-height with the label unchanged at 12px (UX-DR6, added 2026-08-05 — the definition previously wrote a 30px target and named no floor, which is what let the whole segmented family ship uncovered). This clause binds every call site the class absorbs: .segmented-control__option, .range-button, .chart-toggle, .period-buttons .button-mini, .view-chip. Only .view-chip has the clause today (app.css:4888-4891).'
    option-hover: 'background {colors.hover}, text {colors.text}'
    option-active: 'filled {colors.accent}, text {colors.on-accent}'
    width-reserved: 'required — {components.width-reserve}, technique: fixed track width — the group sizes to its widest option in its active appearance and does not resize when the selection moves'
  selected-row:
    scope: 'selection inside lists, tables and trees'
    rule: 'UX-DR16 (mapping in EXPERIENCE.md), UX-DR18 for the reserved metrics'
    background: '{colors.selected}'
    edge: 'inset 3px 0 0 {colors.accent} on the leading edge (LTR: left)'
    text: 'unchanged; the row label may take {colors.accent} but must not change weight'
    vs-hover: 'hover is {components.data-table}.hover — the SAME accent family at a lower strength and with NO edge. Selection is strictly stronger: hover = color-mix(in srgb, {colors.accent-soft} 42%, transparent); selected = {colors.accent-soft} at full strength (that is what {colors.selected} aliases). A diff that renders selection at the hover strength, or hover with an edge, is a review reject.'
    width-reserved: 'required — {components.width-reserve}, technique: permanently reserved ornament slot — every row in the list carries the 3px leading gutter, transparent when unselected'
  data-note:
    scope: 'anything the app tells the operator about their data'
    rule: 'UX-DR17 (defined in EXPERIENCE.md), UX-DR7 for the encoding'
    severities: 'note · attention · problem — exactly three, never a fourth'
    encoding: 'colour AND icon AND word, never colour alone (UX-DR7/UX-DR17)'
    note: 'border 1px {colors.border}, background {colors.bg-muted}, text {colors.text-muted} (5.21:1)'
    attention: 'border 1px {colors.warning}, background {colors.warning-soft}, text {colors.warning} (4.84:1 light, 8.45:1 dark)'
    problem: 'border 1px {colors.danger}, background {colors.danger-soft}, text {colors.danger} (5.39:1 light with the token darkened 2026-08-05, 6.46:1 dark over {colors.bg-dark} / 5.89:1 over {colors.bg-elevated-dark}). CLOSED 2026-08-05 — the gate that blocked this line is decided under Colors → the danger-tint gate; symmetric with attention, whose body text is likewise its own semantic hue on its own tint.'
    radius: '{rounded.md}'
    padding: '{spacing.2} {spacing.3}'
    semantics: 'the severity WORD is always in the DOM as text (.visually-hidden where the visual design shows only the glyph); the glyph is aria-hidden="true", so it is never announced and never announced twice. Colour is the third channel and the only droppable one (UX-DR7).'
    announcement: 'PER REGION, NEVER PER NOTE. A section that can render more than one note exposes ONE live region around the list; N notes must never produce N announcements. Politeness by severity: note and attention are role="status"; problem is role="alert" ONLY where the note appears in direct response to an action the operator just took (which is the {components.inline-result} case, and is why that component already says so). A problem present on first render, or arriving with a batch — the Wealth data-quality list, an import preview — is role="status" like the rest of its region: a data-quality section arriving with a dozen problems would otherwise fire a dozen assertive interruptions and drown the surface.'
    placement: 'inside the same `<section>` element as the data it describes, and before that section closes. The remedy control is a child of the note. A note whose data is in a different `<section>` is a violation; the ~1100px gap on Wealth data quality is the failing case.'
    icon: 'note → :asterisk · attention → :alert_triangle · problem → :alert_octagon (decided 2026-08-05, designer). All three are ADDITIONS to the app_shell.ex icon set — see Components → Data note'
  period-control:
    appearance: '{components.selected-segment}'
    tokens: '1M 3M 6M YTD 1Y 3Y 5Y Max — one vocabulary app-wide; each surface declares the subset it offers'
    custom-range: 'behind a disclosure ({components.disclosure}), never permanent chrome'
    date-fields: '{components.native-control} — ISO in the input, not only in the display'
  disclosure:
    scope: 'data-as-table under every chart; custom range; entry forms out of the reading sightline'
    rule: 'UX-DR10 (defined in EXPERIENCE.md), UX-DR19 for the marker'
    control: 'quiet text summary — {typography.control-label} in {colors.text-muted}, pointer cursor'
    marker: 'defined chevron, never the raw browser triangle'
    purpose-line: 'exactly one sentence, ≤ 90 characters in the source (English) msgid, of the form "<what the table holds> — <why it is here>". Example shape: "Every plotted point as a row — the chart data without the chart." No second sentence, no link. Over 90 characters is a review reject; the bound is what makes UX-DR10 verifiable on a diff.'
    label: '"Data as table" — one wording app-wide (decided 2026-08-05, designer; de: "Daten als Tabelle"). Copy rule in EXPERIENCE.md Voice and Tone'
    body: '{components.data-table} for the data-as-table case'
  value-slot:
    scope: 'every rendered money, percentage or quantity that can be absent'
    rule: 'UX-DR20 (defined in EXPERIENCE.md)'
    metrics: 'the slot reserves its final footprint in all four states; no state may reflow its neighbours'
    numerals: 'tabular-nums in every state, including mid-count'
    final: '{typography.stat-value} or {typography.table-cell}, full colour'
    pending: 'last known value at {colors.text-muted} plus {components.recomputing-cue} on the line beneath it; where no prior value exists, {components.value-slot}.pending-fallback. The colour step is the WEAKEST of the three channels and never the only one — see .state-exposure and .stale-marker, which are binding (UX-DR7).'
    state-exposure: 'the slot element carries aria-busy="true" for the whole of pending AND settling and aria-busy="false" from the moment the final value is assigned. The slot is never inside an aria-live region and is never aria-hidden (announcement policy: EXPERIENCE.md → State Patterns, the recomputing cue, item 4).'
    stale-marker: 'REAL DOM TEXT inside the slot and BEFORE the digits in document order, so a linear read reaches the qualifier before the number — source shape "Last known value —", .visually-hidden (app.css:225-232) where the visual design already shows {components.recomputing-cue} beneath. Never a ::before content string, never a title attribute, never carried by the colour step. Without it a screen reader, a braille line and a forced-colors user all receive a plain authoritative number that is not the current one, which is worse than the bare … it replaces.'
    forced-colors: 'under forced-colors: active the {colors.text-muted} step collapses into {colors.text} and the state is carried entirely by .stale-marker and {components.recomputing-cue} (text plus a border-drawn ring). PENDING must survive; SETTLING need not — a settling value is already final, so losing its distinction costs nothing, while losing pending asserts a stale figure as current. Stated as a ruling so the two are not treated alike.'
    pending-fallback: 'substance and dressing, and the substance is never gated. SUBSTANCE (always rendered, in every motion preference): a static {colors.text-muted} placeholder occupying the value footprint, plus .state-exposure and {components.recomputing-cue} carrying the word "computing" and no as-of date, because there is none. DRESSING (gated behind prefers-reduced-motion: no-preference): the skeleton gradient reusing .section-skeleton stops at text size, shimmering over that placeholder. Under `reduce` the shimmer is absent and the placeholder plus the cue remain — an indicator is replaced under `reduce`, never removed (Accessibility Floor).'
    settling: 'digits at {colors.text-muted}, a 2px accent bar beneath growing 0 to full width over the count; on settle digits snap to full colour and the bar fades. Under prefers-reduced-motion: reduce the settling state does not occur at all — the final value renders at full colour immediately, with no bar and no dimming (stated identically in EXPERIENCE.md → State Patterns).'
    not-computable: 'em dash, {colors.text-muted}, NOT at value weight — the state a stable input can rest in, so it must not look like a state in flight'
  recomputing-cue:
    scope: 'the operative element of the pending state — the thing that says a shown value is not the current one'
    anatomy: 'one line directly under the value, inside the reserved slot footprint: a ring glyph, then the as-of basis, then the recomputing word. Source shape — "<ring> Last known <as-of date> · recomputing".'
    glyph: 'the shipped .spinner ring (app.css:4706-4716) — 0.8em square, 2px currentColor border, transparent top segment, margin-right 0.4em, vertical-align -0.1em. NOT a new icon-set entry, so this cue does not wait on the icon-set story that the three severity glyphs and the clock glyph ride.'
    typography: '{typography.stat-label} size on stat cards, {typography.table-cell} in tables; colour {colors.text-muted} in both'
    word: 'the word is mandatory and carries the meaning on its own — "recomputing" (de "wird neu berechnet"), or "computing" (de "wird berechnet") in {components.value-slot}.pending-fallback where no prior value exists. Glyph plus word plus muted colour is three channels; UX-DR7 is satisfied without the animation and without the colour.'
    semantics: 'the whole cue is real DOM text and is never aria-hidden — it is the sentence that makes the dimmed number honest. The ring glyph is drawn with a border, not a character, so it needs no aria-hidden and it survives forced-colors: active. The cue never announces on its own: the slot is outside every aria-live region, and one polite region per surface announces the transition (EXPERIENCE.md → State Patterns, item 4).'
    reduced-motion: 'under `reduce` the ring stops and renders as a complete ring at 0.5 opacity (app.css:4724-4730); the word and the as-of date are unchanged. Nothing is removed — loading indication is information, not polish.'
    not: 'never the ⓘ character — ⓘ is the metric-DEFINITION affordance at eight call sites (UX-DR11). Never :refresh_cw either: that glyph already means "sync prices now" at three call sites (securities_live.ex:178, row_context_menu.ex:52 and :102), and a second meaning is banned.'
    provenance: '.working/loading-affordances.html, option P2 — the cue is rendered there and was part of what the owner picked; it never reached the spines until now'
  width-reserve:
    rule: 'a control whose active state changes weight, adds an icon or adds an ornament reserves that space in its rest state. UX-DR18 (defined in EXPERIENCE.md).'
    technique-by-class: 'ONE mechanism per selected-state class, not a menu — {components.selected-nav} uses invisible bold shadow text on the label; {components.selected-segment} uses a fixed track width sized to the widest option in its active appearance; {components.selected-row} uses a permanently reserved 3px leading ornament gutter, transparent when unselected.'
    tolerance: '0px — no measurable shift when selection moves'
  native-control:
    scope: 'date inputs, selects, <details> summaries, checkboxes, radios'
    rule: 'UX-DR19 (defined in EXPERIENCE.md)'
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
    hover: 'background color-mix(in srgb, {colors.accent-soft} 42%, transparent) — as built, app.css:1112-1114. Strictly weaker than {components.selected-row} and never carries the leading edge.'
    selected: '{components.selected-row}'
    scroller: 'own overflow-x container — required, UX-DR15, see Layout & Spacing'
  chart-frame:
    background: '{colors.chart-surface}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    aspect-ratio: '3 / 1'
    line: 'accent, 1.6px stroke'
    area-fill: 'fill {colors.accent} with fill-opacity 0.14 (app.css:3115-3117)'
    data-as-table: '{components.disclosure} — mandatory on every chart surface (UX-DR10)'
  chart-tooltip:
    scope: 'the crosshair readout on every chart surface — one tooltip, driven by the ChartCrosshair hook'
    font: '{typography.mono-data}'
    background: '{colors.bg}'
    border: '1px solid {colors.border}'
    radius: '{rounded.sm}'
  needs-attention-card:
    scope: 'the Overview block that answers "does anything need me?" (UX-DR2)'
    container: '{components.panel} as a workspace section; heading on the {typography.section-title} step'
    basis-line: 'directly under the heading, {typography.stat-label} in {colors.text-muted}: the view, the plan, and the threshold the count is computed against. Where the allocation carries several plans the line names that fact instead of a plan. Built today as the threshold clause alone (dashboard_live.ex, data-role="attention-explainer") — view and plan are the missing half.'
    item-row: 'a full-width link row: category name at {typography.body} in {colors.text}, then the drift figure right-aligned in tabular numerals. The figure is signed money semantics — {colors.positive}/{colors.danger} plus the direction word, never the accent (UX-DR7).'
    severity: 'items do NOT each become a {components.data-note}. The card IS one attention-severity surface; its heading carries the severity, the rows carry the facts. A row that needs its own severity is a data-quality finding and belongs in the data-quality line instead.'
    cap: 'at most five rows (dashboard_live.ex @max_alerts); no "show all" affordance — the surface that owns the full list is Wealth → Allocation & targets, which every row links to'
    empty: 'one line at {typography.body} in {colors.text-muted} stating the condition is clear. No badge, no icon, no colour — an all-clear is not a finding.'
  data-quality-line:
    scope: 'the Overview data-quality block (UX-DR2, UX-DR17). Not the Wealth data-quality section, which is {components.data-note} rows.'
    form: 'ONE line, not a card grid. Rendered only when N > 0; absent entirely when N = 0, with no green all-clear badge. Decided 2026-07-12, recorded here 2026-08-05 — see Components → Data quality.'
    anatomy: 'a single {components.data-note} at the highest severity present, its word and glyph first, the count and the condition as the sentence, the remedy as a link inside the note'
    target: 'the link lands on the securities list ALREADY FILTERED to the offending set — not the unfiltered index. Blocked: securities_live.ex handle_params reads only `tab` and `id`, so no URL-addressable filter state exists yet.'
  inline-result:
    scope: 'feedback for an action the operator triggered — the replacement for .status-toast (issue #566)'
    placement: 'in the flow, immediately after the control that triggered the action, inside the same `<section>`. Never a floating overlay, never a corner. A result that has no trigger on screen is not an inline result — it is a page-level {components.data-note}.'
    appearance: 'reuses {components.data-note} severities verbatim: success reads as note, a recoverable failure as attention, a refused write as problem. No fourth appearance and no success-specific colour.'
    busy: 'while the action runs, the trigger carries the busy state and the slot reserves the result footprint, so nothing reflows when the result lands'
    persistence: 'persists until the next action on the same control, a navigation, or an explicit dismiss. It does NOT self-dismiss on a timer — the 4.5s auto-dismiss of .status-toast (AutoDismissToast hook) is exactly the behaviour #566 retires.'
    aria: 'the result region is `role="status"` (polite) for note and attention, `role="alert"` for problem; the region exists in the DOM before the action so the announcement is not lost'
  budget-meter:
    scope: 'the Tax allowance-order "fill level" — the only meter in the product'
    track: 'full-width bar, height {spacing.2}, radius {rounded.full}, background {colors.bg-muted}, 1px {colors.border}'
    fill: 'left-anchored, radius {rounded.full}, background {colors.accent} — the accent, because consumed allowance is neither gain nor loss'
    threshold: 'NONE. The fill does not change colour near the limit. Utilisation is not a severity: a fully used allowance is the normal end state of a tax year, not a warning. Anything genuinely wrong about the budget — a stale as-of date, a missing statement — is a {components.data-note} beside the meter, which is where the severity vocabulary already lives. This is a ruling, not an omission; it is why no UX-DR7 companion (a sign, a glyph, a word beside the colour) is needed here.'
    label: 'remaining amount at {typography.stat-value}, the as-of date on the basis line beneath at {typography.stat-label} in {colors.text-muted}'
    aria: 'role="meter" is not used — the pair renders as text plus a decorative bar, and the text is the accessible value'
  connection-state:
    scope: 'the LiveView socket — the characteristic degradation of a server-rendered architecture'
    placement: 'one band directly under the top bar, full workspace width, above the page content. Never a modal, never a toast: it is a persistent condition, not an event.'
    reconnecting: '{components.data-note} at attention severity, word plus glyph plus tone. The page keeps its last rendered content at full colour — NOT dimmed, because dimming means pending, and a dropped socket is not a computation in flight. Interactive controls stay enabled and simply do nothing; disabling them would be a second, competing way to say "unavailable".'
    disconnected: 'the same band escalated to problem severity once the client has stopped retrying, carrying a reload control inside the note'
    restored: 'the band is removed. No success confirmation — a restored connection is the normal state, and {components.inline-result} is for actions, not for conditions.'
    vs-pending: 'the distinction is load-bearing under the chosen pending treatment: pending dims the value and shows {components.recomputing-cue} per slot; a lost socket colours nothing and shows one band for the whole page. A reader must never have to infer which one they are looking at.'
    status: 'NOT BUILT and nothing is styled for it — app.css contains no .phx-loading, .phx-error, .phx-client-error or .phx-server-error rule, and layout_view.ex renders no #client-error / #server-error element. LiveView 1.2.8 already applies those classes to the LV root, so this is a stylesheet plus one band, not a mechanism.'
  chip:
    scope: 'the one chip — a filled tag naming a bucket, a status or a kind'
    shape: 'radius {rounded.sm}, padding {spacing.1} {spacing.2}, {typography.control-label}'
    fill: 'background {colors.bg-muted}, text {colors.text-muted}, no border. The accent-filled variant is reserved for {components.selected-segment}; a chip is never a control.'
    not: 'the outline chip and the grey initial-avatar square are not chips. The avatar is a logo placeholder (.security-logo--initial) and keeps its own name.'
  pill:
    scope: 'marker shapes only — locale pills, nav marker dots, splitter handles. Never an interactive control (see Shapes).'
    radius: '{rounded.full}'
    font: '9.5px, weight 700, uppercase, 0.06em tracking'
---

# Portfolixir — DESIGN.md

> The living visual spec (ADR-0038). Tokens are extracted from `priv/static/app.css` — the only stylesheet; hand-written, no Tailwind, no bundler. This document says how Portfolixir looks; `EXPERIENCE.md` says how it works. Where a rule in this file and the built UI disagree, the file is the target and the build carries the defect; every such disagreement is named below rather than quietly absorbed.
>
> Refreshed 2026-08-05 against the live-surface survey and the design critique of the 2026-08-01 UAT screenshots (`.decision-log.md`, session 2026-08-05).
>
> **Closing pass, 2026-08-05 (same session).** The owner delegated these calls to the designer, so each is marked **decided 2026-08-05 (designer)** where it lands, and each states the evidence it was derived from — measured ratio, token idiom, or code reference. Closed here: the computed contrast table (carried in verbatim), the two unmeasured pairings, `warning-soft-dark`, the three data-note glyphs, the funnel collision, and the disclosure label. Two of the closures are contrast **failures found while measuring** — white on the dark accent fills, and the missing dark warning tint — and are recorded as live defects under Violations, not as spec gaps.
>
> **Status: final (2026-08-05).** Every design question this session opened is decided. The three items below are **downstream work with owners, not open design decisions** — one is a decision gate of its own because it touches user-set data, two are implementation follow-ups. A design-critic review runs against this file as it stands and holds work to everything in it; the three below are out of scope for such a review until their own work lands.
>
> **Accessibility pass, 2026-08-05 (same day, after `review-accessibility-2026-08-05.md`).** The loading vocabulary this refresh introduced was specified in visual terms only, so pending, settling and the three severities had appearance and no programmatic contract. Closed here: the value slot's staleness contract ({components.value-slot}`.state-exposure` / `.stale-marker` / `.forced-colors`), the reduced-motion form of both the settling state and the no-prior-value fallback, the data note's assistive-technology contract, the coarse-pointer floor on the segmented and tab families, the recounted focus-suppression census, **and the danger-tint gate, which is decided rather than carried forward** — {colors.danger} is darkened to `#b91c1c` in light mode. Three sentences that described unbuilt behaviour as shipped are rewritten to state the requirement and name the gap (issues #645, #646, #647).
>
> | Open item | Where | What closes it |
> |---|---|---|
> | Category and series colour is unreconciled | Colors → Category and series colour | A ruling on the operator's palette freedom and on what the app does with a category colour below 3:1. Touches user-set data, so it is its own decision gate. |
> | The `px` / `rem` unit of record | Typography → Residual gaps | A lint rule or an agreed review convention. |
> | The icon-set additions are described, not drawn | Components → Data note | Path data for `:asterisk`, `:alert_triangle`, `:alert_octagon` and the stale-data clock, in `app_shell.ex` `icon_paths/1`. Does **not** block {components.recomputing-cue}, which deliberately adds no glyph. |
>
> Everything else in this file is binding, including the parts that describe defects: where the file and the build disagree, the build carries the defect.
>
> **Citation convention (2026-08-05).** Cite by the most stable handle available — a selector, a `data-role`, an element id, a function name — and add a line number only where nothing stabler exists. Line numbers drift with the next edit and turn a reviewer instruction silently wrong; several in the 2026-08-05 draft already had (`.workspace-page { overflow-x: clip }` was cited at 3934 and is at 3935; the plural-bug call sites were cited four lines off and one short). Existing line-number citations are kept where they are the only handle, and are re-verified when the section around them is edited.
>
> **On splitting the defect register out.** The rubric review proposed moving the per-line defect register — Violations, the Motion live-defect note, the Typography residual gaps, and the inline defect notes in EXPERIENCE.md — into a dated companion (`drift-register-2026-08-05.md`) that alignment stories close out. **Not done, and the reason is on the record rather than left implicit:** the register is what makes the rules holdable right now, and this session's evidence is that facts kept outside the two spines do not survive — the 2026-07-12 data-quality decision, the I2 income pick and the P2 cue anatomy all lived in a log or a working file and all three were lost. A third file is a third place to lose something. The register stays here; the citation convention above is the mitigation, and the Alignment inventory in EXPERIENCE.md is the part a story consumes. Revisit if the register outgrows the rules it serves.

## Brand & Style

Portfolixir is a self-hosted instrument for one operator. The surface reads like a quiet professional terminal: a 13px information-dense base, tabular numerals for money, monospace for chart data, soft elevated panels on a faintly accent-tinted canvas. It is unmistakably a tool — but a warm one: the body background carries a radial accent glow in the top-left corner, the sidebar has a subtle sheen, and the brand expresses itself through **one switchable accent color at a time**, derived from the three-color logo gradient (violet → teal → coral).

The accent system is the identity anchor (owner-loved, binding): the operator picks violet, teal, or coral in the top bar, and the entire surface — active nav, chart lines, focus rings, stat values, selected rows — re-keys to that choice. Dark and light mode both exist and stay; dark is not an afterthought but a full token set.

**The posture this refresh adds: one job, one solution.** The system is coherent at token level and incoherent at component level — the critique found every recurring UI job solved two to five times independently (five ways to say "selected", four ways to say something about the data, three ways to show a metric, three ways to render an empty value). Token fidelity is not design coherence. From here, a recurring job gets exactly one named component in this document, and a second treatment for the same job is a review reject, not a variant.

[ASSUMPTION] The existing token set is treated as closed; no new hues are introduced beyond the tokens above. Drift is corrected toward the tokens, never by adding one.

## Colors *(carries UX-DR8 — contrast commitments per surface, both themes; summarised in EXPERIENCE.md's rule index)*

- **The three accent variants** — {colors.accent-violet} / {colors.accent-teal} / {colors.accent-coral} (light), {colors.accent-violet-dark} / {colors.accent-teal-dark} / {colors.accent-coral-dark} (dark) — are mutually exclusive. `--color-accent` resolves to exactly one of them via `[data-accent]`; violet is the default. Each has a `-soft` companion used for selected rows, active-nav washes, and notes. The accent means "interactive / current / yours" — it colors the chart line, the active nav marker, focus outlines, and unsigned stat numbers.
- **The brand gradient stops** ({colors.brand-violet-1} → {colors.brand-teal-1} → {colors.brand-coral-1}) appear *together* in exactly one place: the 3px top bar of `.stat` cards. They are the only moment all three logo colors coexist; keep it that rare.
- **Semantic colors** are accent-independent: {colors.positive} for gains, {colors.danger} for losses and destructive actions, {colors.warning} for caution states, {colors.tx-buy} / {colors.tx-sell} for transaction markers on charts. **Gain/loss color never re-keys with the accent — money semantics outrank brand.**
- **Semantic color applies wherever a sign exists**, at every level of a table — data rows, subtotals and totals alike. A negative row and a negative total are the same fact at different granularity and must look like it.
- **{colors.logo-plate} is constant white in every theme** by design (issue 449): the plate behind real image logos does not follow the theme. **{colors.on-accent} no longer is** — amended 2026-08-05 (designer): white on the three dark accent fills measures 1.86–2.72:1, so the token is light `#ffffff` / dark {colors.on-accent-dark}. See the computed table below.
- **Surfaces** layer tonally: {colors.bg} canvas → {colors.bg-elevated} panels/inputs → {colors.bg-muted} table heads and wells. The sidebar has its own near-white violet-tinted surface ({colors.sidebar}) with a gradient sheen. Dark mode mirrors the whole stack on a blue-black ramp ({colors.bg-dark} → {colors.bg-elevated-dark} → {colors.bg-muted-dark}).
- **Text** has four steps, two of which may carry content: {colors.text} (primary) and {colors.text-muted} (secondary — the floor for anything readable). {colors.text-subtle} is for **disabled states and pure decoration only** — at 2.47:1 in light mode it must never convey content; readable tertiary content uses {colors.text-muted}. {colors.text-soft} is a violet-leaning decorative step, never body copy (3.48:1 light).

**Theme mechanism (as built):** `prefers-color-scheme` media queries provide system-follow defaults; explicit `[data-theme="light"|"dark"]` attributes override them, and must win in both directions. The top bar exposes a three-state theme menu (system / light / dark) and the accent menu (violet / teal / coral). Both are progressive-enhancement controls (CSS `<details>` + small hooks), no bundler involved.

**Contrast commitments (binding):**

- Normal-size text ≥ 4.5:1 on its surface in both modes — satisfied by {colors.text} and {colors.text-muted} only; the other text steps are barred from content (above).
- Accent as text: violet and teal pass at body size in both modes; **coral passes only as large text** (≥ 24px, or 19px bold — the 30px stat values qualify). Body-size coral text in light mode is barred (4.38:1).
- Semantic colors ({colors.positive} / {colors.danger} / {colors.warning}) pass ≥ 4.5:1 on all standard surfaces in both modes — including {colors.warning} on {colors.warning-soft} (4.84:1 light, 8.45:1 dark once the dark tint exists).
- **A label on an accent fill is normal text and takes the 4.5:1 bar** — it is not an "indicator" exempt at 3:1. This is why {colors.on-accent} is theme-dependent (added 2026-08-05).
- Meaningful graphics (chart lines, buy/sell markers) ≥ 3:1 against {colors.chart-surface}.
- **The settling bar is a meaningful graphic** and takes the same 3:1 floor, against {colors.bg-elevated} in both themes — it is the only carrier of "this number is still moving" for a user who cannot perceive the digit colour step. It also carries a **minimum rendered length of 8px**: a bar that starts at zero width is invisible for the first frames of a 600ms count, which is exactly when the not-final signal matters most. The bar grows from that minimum to full slot width, not from nothing (added 2026-08-05, closing the last accessibility finding).
- Focus indicator: solid 2px accent outline ≥ 3:1 against adjacent colors; the 18%-opacity soft ring is decoration, never the indicator (see EXPERIENCE Accessibility Floor).
- **A state distinction must survive `forced-colors: active` (binding, added 2026-08-05).** Under forced colors the author palette is replaced by a small system palette: {colors.text-muted} and {colors.text} collapse to one value, tints are dropped, and a thin bar drawn as a background disappears into the canvas. Any state whose only carrier is a colour step therefore ceases to exist for that reader — which is the pending state's failure arriving through a second door. Every distinction the design depends on is carried by text, a glyph, or a border, and the colour step is the reinforcement. `app.css` contains **zero** `forced-colors` rules today; the behavioural rule is in EXPERIENCE Accessibility Floor and the per-state carriers are in {components.value-slot} and {components.data-note}.
- 9px chart-axis type is tolerated only because every chart's data is also reachable as a table (EXPERIENCE Accessibility Floor, binding).

### Category and series colour

Two colour systems exist that the token set above does not cover, and pretending otherwise is what let them drift.

**Category colour is user-set and outside the token system.** A classification category carries a `color` the operator picks freely — the schema validates only `~r/^#[0-9a-fA-F]{6}$/` (`category.ex:15`) — and that hex is written as an inline style into the sunburst segments, the legend swatches, the drift-table swatches and the tree row swatches (`portfolio_live.ex:1027` and the `.sunburst-seg` fill, `classifications_live.ex:387`). No token mediates it, no contrast is checked, and the closed-token-set assumption above does not apply to it.

Three positions on this coexist in the project and **cannot all be true**: the closed token set stated here; the build's free-form per-category hex; and the 2026-08-05 decision that stacked income segments come from tints of the active accent. Reconciling them touches user-set data, not just styling, so it is **a decision gate of its own and is not settled here** (also recorded in EXPERIENCE.md → Per-instrument income). What would close it: a ruling on whether the operator picks freely from a constrained palette, and whether the app corrects, warns about, or ignores a category colour that fails contrast.

What binds today, regardless of that gate:

- A category swatch is a **meaningful graphic** and takes the 3:1 floor against {colors.chart-surface} — the same commitment the buy/sell markers take. A swatch below it must not be the only channel distinguishing two segments.
- Category colour never carries a fact colour already owns. Over/underweight, gain/loss and severity stay on {colors.positive} / {colors.danger} / {colors.warning}, on top of whatever hue the category has.
- **Series colour** (multi-series charts: the two snapshot polylines, stacked income segments) is not category colour. Series are separated by **direct labelling first**, and colour second — which is the constraint that caps stacked income segments at three plus a remainder (EXPERIENCE.md).

### The danger-tint gate *(found 2026-08-05 while closing the data-note component; **DECIDED 2026-08-05**, same day)*

{components.data-note}.problem is specified as {colors.danger} text on a danger tint. **It was not buildable at 4.5:1 with `#dc2626`, and the failure is live in the build today.**

`.alert-error` (app.css:1167-1171) renders `color: var(--color-danger)` on `background: var(--color-accent-coral-soft)` — the values now named {colors.danger-soft} / {colors.danger-soft-dark}. Measured with the same method as the tables above:

| Pair | Ratio | Verdict |
|---|---|---|
| danger #dc2626 / danger-soft #ffe4e6 | **4.02** | **fail normal text** (pass 3:1 as graphic) |
| danger #dc2626 / bg-elevated #ffffff | 4.83 | pass — but only 0.33 of headroom |
| danger #dc2626 / bg #f6f7fa | 4.51 | pass, at the threshold |
| danger #dc2626 / bg-muted #eef1f6 | **4.27** | **fail normal text** — measured 2026-08-05, previously unrecorded |
| text #0e141b / danger-soft #ffe4e6 | 15.42 | pass |
| text-muted #5a6577 / danger-soft #ffe4e6 | 4.91 | pass |
| danger-dark #fb7185 / danger-soft-dark composite #2d111c over bg-dark | 6.46 | pass |
| danger-dark #fb7185 / danger-soft-dark composite #341a29 over bg-elevated-dark | 5.89 | pass |

The dark half is fine. The light half is not, and no tint of the danger hue rescues it: {colors.danger} clears 4.5:1 on plain white by 0.33, so **any** tint that darkens the ground at all drops it below the bar — measured at 6%, 8%, 10%, 12% and 16% of {colors.danger} over {colors.bg-elevated}, the ratio runs 4.41 → 4.28 → 4.13 → 4.01 → 3.75.

Three resolutions existed and each cost something:

1. **Darken {colors.danger} for light mode.** Fixes it everywhere at once, and re-opens every row of the contrast table that cites `#dc2626`.
2. **Problem-severity body text becomes {colors.text} on {colors.danger-soft}** (15.42:1), with {colors.danger} carrying the border, the glyph and the severity word only — all of which are graphics or large enough to sit at 3:1, which 4.02 clears. Buildable today, adds no hue, but breaks the symmetry with attention, whose body text *is* {colors.warning}.
3. **Drop the tint for problem** — {colors.danger} border and glyph on {colors.bg-elevated} (4.83:1). Symmetric with nothing, and the most severe note becomes the least tinted.

**Decided 2026-08-05 (designer's call, owner-delegated): resolution 1 — {colors.danger} becomes `#b91c1c` in light mode.** `danger-dark` (`#fb7185`) is untouched; the dark half already passed.

**Why 1, and why the "closed token set" objection does not hold.** The closed-set rule bars *adding a hue*; this changes one token's value inside its own hue, which is the same kind of move as the {colors.on-accent} amendment made three sections above. What settles it is the consumer census rather than taste:

**Consumer census — all 21 `var(--color-danger)` rules in `app.css`, read 2026-08-05.** `color` at 1043, 1168, 1930, 2172, 2723, 2778, 3101, 3143, 3230, 3493, 3621, 4021, 4317, 4662, 5255, 5448; `border-color` at 1047, 3622; `color-mix(… 32%, transparent)` borders at 1170, 4664; `fill` at 3131 (the sell marker). **Not one of them uses the token as a background.** `.button-danger` (3609-3624) is an outline button — danger text and border on `transparent`. Every consumer therefore takes the token as ink or as an edge, and darkening ink on a light ground can only raise a ratio: there is no call site where the change trades one failure for another. Resolutions 2 and 3 buy the same one component and leave `.alert-error` and the other twenty consumers where they are.

**The chosen value, measured** (same method as the tables above; the method reproduces the archived `text-muted / danger-soft = 4.91` row exactly):

| Pair | `#dc2626` | `#b91c1c` | Verdict at `#b91c1c` |
|---|---|---|---|
| danger / danger-soft #ffe4e6 | **4.02** | **5.39** | pass normal text, with 0.89 of headroom |
| danger / bg-elevated #ffffff | 4.83 | **6.47** | pass |
| danger / bg #f6f7fa | 4.51 | **6.04** | pass |
| danger / bg-muted #eef1f6 | **4.27** | **5.71** | pass — a second failure closed on the way |

**The cost, stated rather than absorbed:**

- Four rows of the computed contrast table are recomputed (done below, in this same edit) and every future citation of `#dc2626` in this folder is wrong.
- Light-mode red is visibly darker — losses, destructive borders and the sell marker all shift one step toward maroon. Against {colors.positive} `#047857` (5.12:1 on canvas) the pair is now closer in weight, which reads as more consistent, not less.
- The declared {colors.tx-sell} token (`#ef4444`) diverges *further* from what the build actually renders for a sell marker, because `app.css:3131` resolves `--color-danger` and defines no `--color-tx-*` at all. The divergence is pre-existing — the frontmatter implies a knob that cannot be turned — and is now recorded in the note above the computed contrast table; darkening widens it and does not create it. What closes it: define the four `tx-*` tokens, or state the aliasing in this section.
- Two declarations move: `:root` (app.css:20) and `[data-theme="light"]` (app.css:114). The two dark declarations (83, 144) are untouched.

Until the token lands in `app.css`, `.alert-error`'s 4.02:1 stands as a live contrast defect (listed under Violations). The **spec** side of the gate is closed: {components.data-note}.problem is now buildable and no longer blocks the Wealth data-quality story.

### Computed contrast table (binding)

**Carried in 2026-08-05 (designer, owner-delegated).** Rows below are transcribed verbatim from `../ux-designs/ux-portfolixir-2026-06-12/review-accessibility.md` (2026-06-13), which is now marked superseded for this table: it sat in an archived review folder for a closed session, so nothing updated it when a token moved and nothing pointed a reviewer at it. This section is the copy of record. When a token value changes, the affected rows are recomputed here in the same commit.

Thresholds: normal text 4.5:1 · large text (≥24px / 18.7px bold) and UI components/graphics 3:1. "Large-only" = passes 3:1 but not 4.5:1.

**Recomputed 2026-08-05 (accessibility pass): the four `{colors.danger}` rows**, after the token was darkened from `#dc2626` to `#b91c1c` to close the danger-tint gate. The `#dc2626` figures are kept in the gate section above as the before/after evidence and are wrong everywhere else. The `{colors.tx-sell}` rows below still cite `#ef4444`, the declared token; the build resolves `--color-danger` for that marker and defines no `--color-tx-*` (Violations), so the shipped light-mode sell marker now measures 6.47:1 on {colors.chart-surface}, not the 3.76:1 this table records for the token.

| Pair | Ratio | Verdict | Where used |
|---|---|---|---|
| **Light mode** | | | |
| text #0e141b / bg #f6f7fa | 17.28 | pass | body copy on canvas |
| text / bg-elevated #ffffff | 18.51 | pass | panels, tables, inputs |
| text-muted #5a6577 / bg | 5.50 | pass | secondary text |
| text-muted / bg-elevated | 5.89 | pass | table meta, hints |
| text-muted / bg-muted #eef1f6 | 5.21 | pass | table heads |
| text-subtle #94a0b4 / bg | **2.47** | **fail (all uses)** | tertiary/disabled text |
| text-subtle / bg-elevated | **2.64** | **fail (all uses)** | tertiary in panels/tables |
| text-soft #8b7f9f / bg | **3.48** | **fail normal text** (3:1 large-only) | decorative-tertiary violet step |
| accent-violet #7c3aed / bg | 5.32 | pass | stat values, accent text |
| accent-violet / bg-elevated | 5.70 | pass | stat values on cards |
| accent-teal #0f766e / bg | 5.11 | pass | teal accent text |
| accent-teal / bg-elevated | 5.47 | pass | teal stat values |
| accent-coral #e11d48 / bg | **4.38** | **fail normal text** — pass large (30px stats OK) | coral accent text |
| accent-coral / bg-elevated | **4.70** | **fail normal text** — pass large | coral stat values OK |
| accent-violet / violet-soft #ede9fe | 4.80 | pass | active nav, alert-success |
| accent-teal / teal-soft #ccfbf1 | 4.86 | pass | active nav, alert-success |
| accent-coral / coral-soft #ffe4e6 | **3.91** | **fail normal text** — pass large/UI | active nav wash, alert-success |
| positive #047857 / bg | 5.12 | pass | gains on canvas |
| positive / bg-elevated | 5.48 | pass | gains in tables/cards |
| danger #b91c1c / bg | 6.04 | pass | losses, destructive |
| danger #b91c1c / bg-elevated | 6.47 | pass | losses in tables |
| danger #b91c1c / bg-muted #eef1f6 | 5.71 | pass | losses in table heads and wells |
| danger #b91c1c / danger-soft #ffe4e6 | 5.39 | pass | problem-severity data note |
| warning #b45309 / bg | 4.69 | pass | stale timestamps |
| warning / bg-elevated | 5.02 | pass | warning alerts |
| tx-buy #10b981 / chart-surface #ffffff | **2.54** | **fail 3:1 graphics** | buy markers on light charts |
| tx-sell #ef4444 / chart-surface | 3.76 | pass 3:1 graphics (fail as text) | sell markers |
| text / selected #ede9fe | 15.59 | pass | selected-row content |
| text-muted / selected | 4.96 | pass | selected-row meta |
| **Dark mode** | | | |
| text-dark #e6eaf1 / bg-dark #0b0f14 | 15.93 | pass | body copy |
| text-dark / bg-elevated-dark #131a23 | 14.51 | pass | panels |
| text-muted-dark #8b97a8 / bg-dark | 6.49 | pass | secondary |
| text-muted-dark / bg-elevated-dark | 5.91 | pass | table meta |
| text-subtle-dark #5c667a / bg-dark | **3.33** | **fail normal text** (3:1 large/UI only) | tertiary/disabled |
| text-subtle-dark / bg-elevated-dark | **3.03** | **fail normal text** (3:1 borderline) | tertiary in panels |
| text-soft-dark #c4b5fd / bg-dark | 10.41 | pass | decorative violet step |
| accent-violet-dark #a78bfa / bg-dark | 7.06 | pass | stat values, accent text |
| accent-violet-dark / bg-elevated-dark | 6.43 | pass | stat values on cards |
| accent-teal-dark #2dd4bf / bg-dark | 10.32 | pass | teal accent |
| accent-coral-dark #fb7185 / bg-dark | 7.14 | pass | coral accent |
| accent-violet-dark / violet-soft-dark composite (#242339 over bg-dark) | 5.61 | pass | active nav text in wash |
| positive-dark #34d399 / bg-dark | 10.00 | pass | gains |
| positive-dark / bg-elevated-dark | 9.11 | pass | gains in panels |
| danger-dark #fb7185 / bg-dark | 7.14 | pass | losses |
| danger-dark / bg-elevated-dark | 6.50 | pass | losses in panels |
| warning-dark #fbbf24 / bg-dark | 11.51 | pass | stale timestamps |
| tx-buy #10b981 / chart-surface-dark #131a23 | 6.90 | pass | buy markers (dark) |
| tx-sell #ef4444 / chart-surface-dark | 4.65 | pass | sell markers (dark) |
| text-dark / selected-dark #1f2c42 | 11.62 | pass | selected-row content |
| text-muted-dark / selected-dark | 4.74 | pass | selected-row meta |

Reference (non-normative, decorative): light `border` 1.23:1 and `border-strong` 1.39:1 vs surfaces — fine as decoration since "surface tone first, border second" means borders never solely delineate interactive components; if a control's boundary relies on border alone (quiet buttons do: bg-elevated on bg is near-1:1), the 3:1 UI-component rule technically applies — covered by the focus-indicator finding for the interactive states that matter.

**Added 2026-08-05 (designer): the pairings the 2026-06-13 table never measured.** Computed from the hex values in `app.css` with the same method as the table above (WCAG 2.x relative luminance; translucent tokens composited over their stated base in sRGB, which reproduces the archived `#242339` composite exactly).

| Pair | Ratio | Verdict | Where used |
|---|---|---|---|
| **on-accent on the accent fills — light** | | | |
| on-accent #ffffff / accent-violet #7c3aed | 5.70 | pass | active segmented option, `.button-primary`, active view chip |
| on-accent #ffffff / accent-teal #0f766e | 5.47 | pass | same |
| on-accent #ffffff / accent-coral #e11d48 | 4.70 | pass | same |
| **on-accent on the accent fills — dark** | | | |
| on-accent #ffffff / accent-violet-dark #a78bfa | **2.72** | **fail — all text sizes** | active segmented option, `.button-primary`, active view chip |
| on-accent #ffffff / accent-teal-dark #2dd4bf | **1.86** | **fail — all text sizes** | same |
| on-accent #ffffff / accent-coral-dark #fb7185 | **2.69** | **fail — all text sizes** | same |
| **the fix measured** | | | |
| bg-dark #0b0f14 / accent-violet-dark #a78bfa | 7.06 | pass | ink label on a dark-mode accent fill |
| bg-dark #0b0f14 / accent-teal-dark #2dd4bf | 10.32 | pass | same |
| bg-dark #0b0f14 / accent-coral-dark #fb7185 | 7.14 | pass | same |
| **warning on its tint** | | | |
| warning #b45309 / warning-soft #fffbeb | 4.84 | pass | attention data note, light |
| warning-dark #fbbf24 / warning-soft-dark composite #312b17 over bg-dark | 8.45 | pass | attention data note, dark |
| warning-dark #fbbf24 / warning-soft-dark composite #383423 over bg-elevated-dark | 7.47 | pass | attention data note inside a panel, dark |

Three of these fail, and the failure is live in the build, not hypothetical: **`.button-primary` (app.css:1587-1591) and `.view-chip.is-active` (4771-4775) set literal `white` on `var(--color-accent)`, and `--color-accent` resolves to the `-dark` variant under `prefers-color-scheme: dark` and `[data-theme="dark"]` (app.css:73-101, 135-163).** In dark mode the primary button's label sits at 1.86–2.72:1 on its own fill. `.theme-choice.is-active` (684) and `.locale-link.is-active` (762) use `var(--color-on-accent)` and inherit the same failure.

**Decided 2026-08-05 (designer's call, owner-delegated): {colors.on-accent} becomes theme-dependent — `#ffffff` in light, `{colors.bg-dark}` (`#0b0f14`) in dark.** That is the whole fix; the three ratios above land at 7.06 / 10.32 / 7.14. This narrows, but does not overturn, the issue-449 "constant white" ruling: {colors.logo-plate} — the plate behind real image logos, which is what issue 449 was actually protecting — stays constant white in every theme. Only the text-on-an-accent-fill half moves, because a mid-lightness fill cannot carry white text at any size. Literal `white` in the two rules above is drift regardless and resolves through the token.

### Violations in the built UI (targets for correction, not licence)

- **Negative amounts render in the accent colour on the Wealth KPI cards.** `.stat strong { color: var(--color-accent) }` (app.css:983-990) colours every KPI value, sign-blind. This contradicts the rule two paragraphs up — gain/loss colour never re-keys with the accent — and, because there is no sign emphasis either, it also fails the colour-independence rule (UX-DR7) on the same element. Correction: signed values inside a stat card take {colors.positive}/{colors.danger} plus a sign, and only unsigned values take the accent.
- **Semantic colour is applied only at total rows.** Row-level negatives render in body ink while the total renders red — the reader is shown that the sum is negative but not which rows made it so. Correction: the rule above ("wherever a sign exists, at every level").
- **{colors.warning-soft} is light-only — a live defect in the build, not a spec gap.** `--color-warning-soft: #fffbeb` is declared once in `:root` (app.css:41) and is overridden in neither the `prefers-color-scheme: dark` block (app.css:73-101) nor `[data-theme="dark"]` (app.css:135-163), while `--color-warning` *is* re-keyed to `#fbbf24` in both (app.css:84, 145). Every dark-mode surface that uses the pair therefore renders amber text on a near-white cream ground: `.alert-warning` (app.css:1935-1937) and two further rules at app.css:5589-5590 and 5685-5686. It breaks the dark/light parity rule under Do's and Don'ts today, on shipped screens.
  **Decided 2026-08-05 (designer's call, owner-delegated):** `--color-warning-soft: rgb(251 191 36 / 0.16)` in both dark blocks — the `-soft-dark` idiom of the accent tokens, i.e. the dark hue at 0.16 translucency, keeping `rgb()`-with-alpha notation for the same reason they do (the tint must composite over whatever surface it lands on). Measured: composited over {colors.bg-dark} it is `#312b17` and carries {colors.warning-dark} at **8.45:1**; over {colors.bg-elevated-dark} it is `#383423` at **7.47:1**. Both clear 4.5:1 with room, so the tint can also darken later without re-opening the ratio.
- **White text on the dark accent fills fails contrast, in the build.** `.button-primary` (app.css:1587-1591) and `.view-chip.is-active` (4771-4775) hard-code `white` on `var(--color-accent)`; `.theme-choice.is-active` (684) and `.locale-link.is-active` (762) use `var(--color-on-accent)`, which is `#ffffff` in every theme. In dark mode those labels measure 2.72 / 1.86 / 2.69:1 (see the computed table). Correction: the theme-dependent {colors.on-accent} decided above, resolved through the token — not through a literal `white`.
- **Two tokens are referenced but never defined, and fall back to hard-coded translucent grey** (recounted 2026-08-05; the earlier three-token claim was wrong in both directions):
  - `--color-border-subtle` — `.workspace-page`-adjacent rules at app.css:3649, 4285, 4337, all falling back to `rgba(127, 127, 127, 0.16)`. Correction: {colors.border}.
  - `--color-surface-hover` — app.css:3652, 3884, 4174, 4183, falling back to **three different greys**: `0.08`, `0.14`, `0.12`, `0.12`. A second inconsistency inside the first. Correction: {colors.hover}, one value.
  - `--color-surface` is **not** in this class: it is referenced at app.css:2135, 2208, 3066, 3396, 3681 and falls back to `var(--color-bg)` — a real theme token, so it follows the theme correctly. It is an undefined alias, not a theme hole; correction is cosmetic (reference {colors.bg} directly).
- **The accent is hard-coded to violet in six places** (app.css:2936, 3440, 3561, 3656, 3982-3983): the 30-day moving average, two drop-target borders, the selected-row edge, and the period buttons' active fill stay violet when the operator picks teal or coral. (app.css:720 is the accent-picker's own violet swatch and is correctly excluded.) Correction: `var(--color-accent)`.
- **`--color-selected` does not re-key with the accent, and it is a seventh, structurally worse case of the same defect (issue #644).** The token is a literal `#ede9fe` in `:root` (app.css:30), the `prefers-color-scheme: dark` block (93) and both `[data-theme]` blocks (124, 154), and appears in **no** `[data-accent]` block — those set only `--color-accent` and `--color-accent-soft` (app.css:165-177). Eight rules consume it (app.css:1433, 1460, 1638, 1854, 1894, 2081, 2908, 2994), including the selected-row treatment {components.selected-row} mandates, so under teal or coral **every selected row in the app stays violet**. Worse than the six above because it is a token-level break, not six rule-level ones. Correction: `--color-selected: var(--color-accent-soft)` inside each `[data-accent]` block, or drop the token and reference {colors.accent-soft} at the eight call sites. `--color-selected-dark` has the same shape and rides the same fix.
- **`--shadow-sm` is light-only.** Declared once in `:root` (app.css:43) and overridden in neither dark block (99-101, 160-162) nor `[data-theme="light"]` (130-132), all three of which do re-key `panel`, `md` and `sidebar`. Six rules consume it — `.accent-menu-trigger` (app.css:607), the base `button` rule (1082), `.data-table-wrapper` (1665), `.chart-tooltip` (3071), `.sunburst-tooltip` (4207) and `.bucket-picker` (5266), two of them with a hard-coded `rgba()` fallback that never fires because the token *is* defined — so every button and both chart tooltips carry a slate-tinted 5%-opacity shadow on the dark canvas, where a slate tint at 5% is invisible. **Same defect class as {colors.warning-soft}, and not previously named** — recorded 2026-08-05 because the shadow tokens are now in the frontmatter and the gap is legible from it.
  **Decided 2026-08-05 (designer's call, owner-delegated):** `--shadow-sm: 0 1px 3px rgb(0 0 0 / 0.5)` in both dark blocks, derived from the idiom the three shipped dark values already follow — black replaces the slate tint; the blur grows by the proportion `md` grows (22 → 28px, so 2 → 3px); the opacity takes `md`'s 0.5 because `sm` and `md` are the two levels that land on {colors.bg-elevated-dark}, while `panel` (0.08 → 0.32) and `sidebar` (0.16 → 0.42) sit on the canvas and need less. No measurement applies — a shadow is decoration and carries no contrast commitment; the idiom is the whole argument, which is why it is stated rather than implied.
- **`.alert-error` renders {colors.danger} at 4.02:1 on {colors.danger-soft}** (app.css:1167-1171), below the 4.5:1 text bar in light mode. **Correctable as of 2026-08-05:** the danger-tint gate is decided, so this closes by re-keying `--color-danger` to `#b91c1c` in `:root` (app.css:20) and `[data-theme="light"]` (114) — 5.39:1 — not by a call-site change.
- **Buy/sell chart markers are hue-only, and this file described the fix as shipped (issue #645).** `security_chart.ex:129-136` renders one `<circle class={"tx-marker tx-#{marker.type}"} r="4">` for both types and `app.css:3126-3132` changes only `fill`, so buy and sell differ in nothing but hue. That is the first example UX-DR7 gives, in both spines, of a distinction that must never be hue-only. The Inventory line claimed "shape-coded not hue-coded" as built; it is corrected there and the violation is filed here, on the same list as the accent-coloured negatives. Correction: render ▲ / ▼ paths instead of `<circle>`. The `<title>` children inside the markers are additionally unreachable, because the enclosing SVG carries `role="img"` and collapses its subtree — so the shape is the only channel that can carry this, which is why the requirement is not negotiable.

Avoid: introducing a fourth accent, using accent colors for gain/loss, gradients on content surfaces (gradients live only in the body backdrop, sidebar sheen, stat top bar, and active-nav wash).

## Typography *(carries the heading-ramp half of UX-DR14 — the spacing half is under Layout & Spacing, the locale-pill floor under Inventory → Top bar)*

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

## Layout & Spacing *(carries the spacing-scale half of UX-DR14, and UX-DR15 in full — every wide block owns its scroller)*

The shell is a fixed left sidebar ({spacing.sidebar-width}) plus a sticky, blur-backed top bar ({spacing.topbar-height}). On desktop the sidebar collapses to an icon rail ({spacing.sidebar-rail}) via the toggle; content reflows. Workspace pages are full-bleed vertical stacks of `.workspace-section` bands separated by 1px borders, padded {spacing.section-pad-block} block / {spacing.section-pad-inline} inline; card grids use `repeat(auto-fit, minmax(220px, 1fr))` with {spacing.4} gaps.

**The spacing scale exists and is binding.** Eight steps on a 4px base ({spacing.1} … {spacing.8}, app.css:51-58), covering every margin, padding and gap. `test/invariants/css_spacing_scale_test.exs` enforces both that the tokens are defined and that they are actually adopted — the scale cannot be defined and then ignored. Values off the scale are permitted only for the structural constants listed in the frontmatter and for `clamp()` expressions that interpolate between two of them; anything else is drift.

Breakpoints (as built, and tokenised in the frontmatter so both spines reference one source): {spacing.bp-sidebar} — sidebar leaves the flow and becomes an off-canvas overlay (app.css:1200); {spacing.bp-dialog} — dialogs/menus go single-column, row context menus become bottom sheets (app.css:2005, 2175, 2344); {spacing.bp-density} — base font bumps to 14px, page subtitles hide, tables scroll horizontally (app.css:1271). Touch sizing is a pointer query, not a breakpoint: {spacing.touch-target} under `@media (pointer: coarse)` (app.css:4589, 4887, 4998, 5330, 5521), against {spacing.density-control} on desktop.

Media-query conditions cannot read CSS custom properties, so app.css necessarily keeps these as literals. The tokens are the documents' source of record; a literal in either spine is drift.

### Every wide block owns its scroller *(UX-DR15)*

`.workspace-page { overflow-x: clip }` (app.css:3935) is deliberate: `clip` does not create a scroll container, so the sticky select-toolbar keeps working and no stray over-wide child can scroll the whole page sideways. The consequence is equally deliberate and must be designed for — **a child wider than the viewport is truncated, not scrolled.** There is no page-level rescue.

Therefore, visually:

- Any block that can exceed the viewport width — data tables, chart label rows, legends, wide matrices — establishes its own `overflow-x: auto` container (`.data-table-wrapper`, `.table-scroll`).
- Every flex or grid child that contains such a block sets `min-width: 0`, or the container never shrinks and the scroller never engages.
- The scroller is visible as an affordance: the scrolled block sits in a bordered, radiused container so its edge reads as an edge, not as a cut.

This is the visual half of the rule EXPERIENCE.md carries as UX-DR15. **Census, 2026-08-05:** 23 `<table>` elements ship; **four** sit in a scroller — `securities_live.ex:265` (`.data-table-wrapper`), `portfolio_accounts_live.ex:82` (`.data-table-wrapper`), `snapshots_live.ex:333` and `:491` (`.table-scroll`). The other 19 do not. The full list, with the columns each can reach, is the Alignment inventory in EXPERIENCE.md → UX-DR15. The worst case is income's year × month matrix (`income_live.ex:148`, 15 columns) plus its flex label row `.income-bar-labels` (app.css:4113-4119), which has neither a scroller nor `min-width: 0` — the observed truncation of #560. Treated as a missing system rule; the next wide table reproduces it otherwise.

## Elevation & Depth

Elevation is tonal-plus-soft-shadow, never harsh. Four levels, both themes, in the `shadows` frontmatter block:

- {shadows.sm} — buttons, table wrappers, both chart tooltips. **The dark value is decided (2026-08-05) and not yet in `app.css`; see Violations.**
- {shadows.md} — popovers, context menus.
- {shadows.panel} — panels and stat cards: large blur, very low opacity, "soft glow" rather than drop shadow.
- {shadows.sidebar} — the sidebar's separation from content.

Dark mode swaps the slate tint for black at higher opacity because tonal contrast carries less there; the values are per level in the frontmatter rather than as a range, so a diff can be checked against them. The sticky top bar adds depth via translucency: 88% elevated-surface color with `backdrop-filter: blur(18px)`.

Hierarchy device of record: surface tone first, border second, shadow third. Tables and tree nodes use borders only. **Nothing inside a table gets a shadow** — the allocation table header currently renders two of four headers as white bordered boxes with shadow that overflow the header band, reading as stray buttons dropped into a header row. A cell is not a card.

Elevation encodes layer, never state. Selection, activity and severity are carried by the components below, not by lifting an element off the page.

## Shapes

Three radii: {rounded.sm} (6px) for tooltips, small chips, kebab buttons; {rounded.md} (8px) for buttons, inputs, nav links, chart frames, notes, menus; {rounded.lg} (12px) for panels and stat cards. Pills ({rounded.full}) are reserved for tiny status markers: locale pills, nav marker dots, splitter handles. Nothing is sharp-cornered; nothing larger than 12px. The feel is "crisp tool with softened edges."

Full-round is a *marker* shape, not a *control* shape. A pill-shaped interactive control reads as a badge and competes with the real badges; picking one of N options uses the segmented group ({components.selected-segment}), never a row of pills.

## Components

All components are hand-written CSS classes consumed by LiveView templates — no component library, no CoreComponents.

**Component census (corrected 2026-08-05 against the build; the earlier "two function components" was wrong):**

- **Three function-component modules under `components/`**, carrying six public function components: `app_shell.ex` (`shell/1`, `area_tabs/1`, `status_toast/1`, `icon/1`), `security_chart.ex` (`chart/1`), `view_switcher.ex` (`view_switcher/1`).
- **Two further function-component modules** colocated with their surface: `live/securities/logo_override_dialog.ex`, `live/securities/row_context_menu.ex`.
- **Five LiveComponents** (stateful, so they are not in the list above): `live/securities/column_picker.ex`, `filter_popover.ex`, `security_form_dialog.ex`, `split_wizard_dialog.ex`, and `live/portfolio_accounts/account_form_dialog.ex`.
- **Eight small inline hooks, all eight defined in `layout_view.ex`** — `ColumnPrefs`, `SecuritySplitPane`, `PositionedMenu`, `ChartCrosshair`, `SunburstTooltip`, `PPImportDrop`, `ClassificationDnD`, `AutoDismissToast`. `security_chart.ex` *consumes* `ChartCrosshair` via `phx-hook`; it defines none. The count-up hook approved 2026-08-05 (Motion) is the ninth and lands in the same file.

### Selected state — three classes, and only three *(UX-DR16 appearance; mapping and the icon rule in EXPERIENCE.md. Reserved metrics: UX-DR18.)*

Five idioms are in the build today: solid accent pill (`.view-chip.is-active`), tint-plus-accent-text (`.segmented-control__option.is-active`, `.range-button.is-active`, `.chart-toggle.is-active`, `.icon-button.is-active`), solid fill inside a bordered container (`.period-buttons .button-mini.is-active`), gradient wash plus marker (`.nav-link.is-active`), underline (`.area-tab.is-active`, `.detail-pane-tab.is-active`), and tinted row (`.security-row.is-selected`, `.dnd-row.is-selected`). Several appear on the same screen. That is the drift being retired.

Three classes replace them. Every selectable control in the app maps to exactly one; a selected table row and an active tab are genuinely different things, which is why one idiom would be dogma and five is drift.

1. **Navigation and tabs → accent underline plus marker** ({components.selected-nav}). The sidebar keeps its established idiom — accent-soft gradient wash, accent-tinted border, 6px filled accent marker dot with halo — because it answers "where am I". Tabs get icon plus label plus a 2px accent underline, because they answer "which facet". Second-level tabs (inside Cash flow) are the same control, smaller and iconless. **One icon vocabulary app-wide:** a tab icon and the sidebar icon for the same destination are the same glyph, and no glyph carries two meanings. The funnel collision (`:filter` means "Views" in the sidebar and "filter" in the securities toolbar) is resolved below under Data note: the funnel keeps "filter", the Views entry takes `:bookmark`.
2. **Toggles, filters and period selection → segmented group with filled accent** ({components.selected-segment}). One bordered track, dividers between options, the active option filled {colors.accent} with {colors.on-accent} text. This absorbs `.segmented-control`, `.range-buttons`, `.chart-toggles`, `.period-buttons` and `.view-switcher`.
3. **Selection in lists and tables → tinted row with a left accent edge** ({components.selected-row}). {colors.selected} background plus a 3px inset accent edge on the leading side. The edge is what distinguishes selection from hover, which is a wash without an edge.

All three are width-reserved ({components.width-reserve}), **one mechanism per class, not a menu**: nav and tabs use invisible bold shadow text on the label; the segmented group uses a fixed track sized to its widest option in the active appearance; the row uses a permanently reserved 3px leading gutter. Three stories cannot pick three mechanisms for the same class.

Call sites that deviate today are enumerated in EXPERIENCE.md → Alignment inventory → UX-DR16.

### Data note — three severities, one component *(UX-DR17 appearance; rule defined in EXPERIENCE.md)*

{components.data-note} replaces four competing treatments (plain bullet list, amber inline highlight, unstyled grey prose, accent-bordered banner) and the ad-hoc chips (`.not-held-chip`, `.stale-chip`, `.no-quote-chip`, `.negative-holding-chip`).

| Severity | Meaning | Colour | Glyph | Word (source string) |
|---|---|---|---|---|
| Note | Context the operator may want | {colors.text-muted} on {colors.bg-muted} (5.21:1) | `:asterisk` | "Note" |
| Attention | Something to look at, nothing is wrong | {colors.warning} on {colors.warning-soft} (4.84:1 light, 8.45:1 dark) | `:alert_triangle` | "Attention" |
| Problem | Something is wrong and needs action | {colors.danger} on {colors.danger-soft} for border, glyph **and body text** (5.39:1 light, 5.89–6.46:1 dark) — the danger-tint gate is decided under Colors | `:alert_octagon` | "Problem" |

Glyphs and word decided 2026-08-05 (designer) — glyph rationale below, wording rule in EXPERIENCE.md Voice and Tone.

Colour is never the only channel (UX-DR7/UX-DR17). Consequence for the data-quality list: "valued at last trade price" is a **note**, "impossible negative holding quantity" is a **problem** — today they render identically, and the app's most important warning surface has the lowest visual weight on its page (a bare `<h2>` with default disc bullets, its actionable link styled like the surrounding prose).

**Placement is testable, not aspirational:** a data note lives **inside the same `<section>` element as the data it describes**, and its remedy control is a child of the note. The failing case is Wealth data quality, where the remedy button for one bullet sits ~1100px below it; a reviewer checks the element boundary, not the pixel distance.

### Data quality — two surfaces, two components

The phrase "data quality" names two different blocks and they are not the same component.

**Overview → data quality is one line: {components.data-quality-line}.** This carries the decision taken in the 2026-07-12 design session and recorded nowhere until now — the decision log names its loss as "precisely the failure mode ADR-0038 exists to stop", so it lands here rather than staying a log entry:

> Data quality on the dashboard is **ONE line**, rendered **only when N > 0**, with **no green all-clear badge**, linking to a **pre-filtered** securities list.

**Adopted 2026-08-05, unchanged.** The built form contradicts it on every clause: `dashboard_live.ex` renders a three-card `.grid` (`data-role="dq-quotes"`, `dq-class`, `dq-logo`), renders it whether or not any count is non-zero, and links all three cards to an unfiltered `/securities`. The build carries the defect; this file is the target.

One clause cannot be satisfied by a design change alone. **"Pre-filtered securities list" has no URL to link to**: `securities_live.ex` `handle_params/3` reads only `tab` and `id`, and the filter state lives in a LiveComponent popover, so there is no addressable filter. The story that implements the one-line form carries URL-addressable filter params, or the link degrades to the unfiltered index and the shortfall is stated in the issue rather than silently shipped.

**Wealth → data quality is a list of {components.data-note} rows**, one per finding, at the finding's own severity. Six conditions render there today, all as identical `<li>` bullets under a bare `<h2>` (`portfolio_live.ex`, `#portfolio-data-quality`): trade-priced positions, positions with no price, positions with no FX rate, pre-1970 booking dates, cash accounts with no FX rate, and impossible negative holdings. The first is a note; the last is a problem; today they are the same bullet. Severity assignment for all six is in EXPERIENCE.md → Alignment inventory → UX-DR17.

**The icon vocabulary, enumerated (app.css has none of it — the set is `app_shell.ex` `icon_paths/1`, lines 428-535).** 36 named glyphs, all 24×24, `fill="none"`, `stroke="currentColor"`, `stroke-width="1.6"`, round caps and joins, plus a fallback clause that renders a bare `circle r="5"` for any unknown name: `dashboard · layers · bookmark · briefcase · folder · calc · bars · pie · chart_line · chart_bar · coins · tag · globe · building · compass · settings · monitor · sun · moon · plus · upload · filter · columns · search · trash · x · chevron_right · refresh_cw · ellipsis_vertical · copy · edit · archive · external_link · maximize · minimize · image`.

**The three severity glyphs — decided 2026-08-05 (designer's call, owner-delegated). The set does not contain a usable candidate; all three are additions.** Not a preference: no glyph in the list above carries a severity reading, and pressing an unrelated one into service (`x` means dismiss, `bars` means Transactions, the fallback circle means "unknown icon name") would create exactly the second-meaning collision this section forbids. Described in the house idiom so the paths can be drawn to spec; no path data is invented here.

| Severity | Glyph name | Description | Why |
|---|---|---|---|
| Note | `:asterisk` | Three strokes crossing at 12,12 — vertical plus two at ±60°, ~7px arms. | The typographic footnote mark: "a remark attaches to this figure". Reads at 14px with no interior detail, and cannot be confused with the ⓘ affordance. |
| Attention | `:alert_triangle` | Rounded-corner equilateral triangle, apex up, plus a centred vertical stroke and a dot below it. | Universal caution. The silhouette alone separates it from note and problem, so the shape channel survives at nav-icon size. |
| Problem | `:alert_octagon` | Regular octagon, flat side up, with the same interior stroke-and-dot. | Reads as "stop". Distinct outline from the triangle at 14px (flat top vs. point), and unlike a circle-with-X it does not collide with `:x`. |

**Why note is not an info circle:** ⓘ (the literal character, in use at eight call sites — `portfolio_live.ex:751/762/776/1077`, `securities_live.ex:993/1147`, `tax_live.ex:369`, `transaction_management_live.ex:199`, `view_switcher.ex:121`) is the metric-**definition** affordance. A note-severity data note states a fact about *this data*, which UX-DR11 explicitly separates from a definition. One mark for both jobs is the funnel problem again.

**Also missing, flagged not solved here:** the stale-data rule (EXPERIENCE State Patterns) requires a clock glyph, and the set has none. It rides the same icon-set story.

**Naming collision resolved (2026-08-05, designer): the funnel keeps "filter"; "Views" takes `:bookmark`.** `:filter` is the funnel (`app_shell.ex:488-489`), used for the sidebar "Views" entry (`nav_groups/0`) and for the securities toolbar filter. A funnel means "narrow this list down" to essentially every user, and the toolbar is the literal case, so it keeps the glyph. The sidebar's Views entry takes `:bookmark` — an existing, otherwise unused glyph whose meaning ("a saved, named selection") is what a view is. No addition needed for this half.

### Period control *(appearance of UX-DR16 class 2; the vocabulary and per-surface subsets are in EXPERIENCE.md)*

{components.period-control}. One appearance — the segmented group — and one token vocabulary app-wide: **1M · 3M · 6M · YTD · 1Y · 3Y · 5Y · Max**. Each surface declares which subset it offers; no surface invents a token outside the set. "Custom range…" is a disclosure, not permanent chrome, and its date fields are {components.native-control}. This retires four patterns, two divergent token sets (`Performance.periods()` = `ytd 1y 3y 5y max`; `securities_live.ex:35` `@ranges` = `1M 3M 6M YTD 1Y 3Y 5Y MAX`) and the four bare `type="date"` inputs that sit *inside period controls* (`portfolio_live.ex:853`/`:860`, `securities_live.ex:534`/`:541`). The other seven date inputs in the app are UX-DR19 work, not period-control work.

### Data as table — one disclosure *(UX-DR10 appearance; rule defined in EXPERIENCE.md)*

{components.disclosure}, mandatory under every chart surface (UX-DR10), same control, same label — **"Data as table"**, decided 2026-08-05 (designer); it names the thing rather than instructing the reader — same styling — rendered as a quiet text control rather than the raw browser triangle, with a purpose line of at most one sentence so it is visible why it exists. De-emphasised, not deleted: it is the accessibility fallback that lets the 9px chart axis stand.

**Census, counted directly in `lib/portfolixir_web/live/` on 2026-08-05. The earlier "three surfaces carry it, three labels, two carry none" was wrong in all three numbers; it came from the decision log's unverified survey row ("on 3 of 5 chart surfaces, 3 different summary labels") and was inherited into three places in these documents.** What is actually there:

| Chart rendering | Where | Disclosure | Label |
|---|---|---|---|
| Wealth performance chart | `portfolio_live.ex:1700` (shared `SecurityChart.chart`) | yes, `:1709` | "Show data as table" — **changes** |
| Allocation sunburst | `portfolio_live.ex:1790-1819` | **none** | — |
| Securities detail price chart | `securities_live.ex:630` (shared `SecurityChart.chart`) | **none** | — |
| Snapshots comparison | `snapshots_live.ex:440-472` (hand-rolled two-polyline SVG) | yes, `:489` | "Data as table" — kept, and the wording of record |
| Income annual bars | `income_live.ex:108-146` (`#income-chart`) | **none** | — |
| Income per-month bars | `income_live.ex:203-228` (`#income-month-chart`) | **none** | — |

**Six chart renderings across five surfaces. Two disclosures, therefore two labels, not three. Four renderings carry none** — the sunburst, the securities detail chart, and *both* income bar charts. `income_live.ex` contains no `<summary>` element at all.

Two consequences the earlier count hid:

- **The income surface is in scope for UX-DR10 and was omitted** — the one surface Lane B is fixing this sprint. Its two `data-table` blocks (`income_live.ex:148`, `:230`) sit adjacent to the charts and the module comments claim they satisfy UX-DR10 by adjacency. Adjacency is not the disclosure: UX-DR10 requires *one uniform control with a stated purpose*, and an unmarked sibling table gives a reader no way to know it is the chart's data. The existing tables become the disclosure body; they are not deleted.
- **Both income charts need one**, not one between them. The per-month chart is a different dataset from the annual chart.

### Value slot *(UX-DR20 appearance; the state definitions are in EXPERIENCE.md)*

{components.value-slot}. Four states, four appearances:

| State | Meaning | Rule |
|---|---|---|
| Pending | value unknown, query in flight, lasts seconds | must not look like not-computable, and must not *read* as current — the number on screen is the last known one, not the answer |
| Settling | value known, ~600ms count-up running | must be visibly not-yet-final while it runs; under `reduce` it does not run and does not exist |
| Final | value is the value | the reference appearance |
| Not-computable | there is no value to show | quiet, muted, not at value weight |

Today `…` (pending) and `—` (not-computable) are both bold at value size on the same KPI row (`portfolio_live.ex:715-780`) — "still loading" and "cannot be computed" are indistinguishable, and both are also indistinguishable from an error. Separating them is the point of the loading-affordance work.

The slot reserves its final footprint in every state, so nothing reflows when a value lands, and uses tabular numerals throughout including mid-count.

**Pending — last known value, dimmed** (owner pick 2026-08-05, option P2 in [.working/loading-affordances.html](.working/loading-affordances.html)). The previous value stays in place at {colors.text-muted}, accompanied by the recomputing cue below and the date it was computed. A magnitude is visible while the server works, instead of a void.

**The pick is kept and made safe for readers who never receive the colour step (2026-08-05, accessibility pass — the one critical finding of that review).** P2 is better than a bare `…` for a sighted reader and strictly worse for everyone else if staleness rides on hue: a screen reader, a braille line and a forced-colors user would each be handed a plain, authoritative number that is **not the current number**, where `…` at least could not be mistaken for data. Replacing a void with a false figure is not an improvement on a money surface. Three bindings make the state carry itself, and all three are in {components.value-slot}:

1. **Programmatic** — the slot carries `aria-busy="true"` for the whole pending state and `false` from the moment the final value is assigned ({components.value-slot}`.state-exposure`). It is never wrapped in an `aria-live` region; announcement is one polite region per surface (EXPERIENCE.md → State Patterns).
2. **Textual** — a real-text staleness marker sits inside the slot **before the digits in document order**, so any linear read hits the qualifier before the number ({components.value-slot}`.stale-marker`). `.visually-hidden` is allowed; a `::before` content string, a `title` attribute and a tooltip are not — none of the three is text the accessibility tree can be relied on to expose, and the whole point is that this text is the load-bearing channel.
3. **Forced colors** — the distinction survives `forced-colors: active`, where the {colors.text-muted} step disappears entirely ({components.value-slot}`.forced-colors`). Pending must survive; settling need not, because a settling value is already the right value.

Where no prior value exists — first load, a newly created account — the slot falls back to {components.value-slot}`.pending-fallback`: a static muted placeholder at the value's own footprint, never the shipped 220px block, carrying the same `aria-busy` and the same cue with the word "computing". **The shimmer over it is dressing and is the only part gated behind `prefers-reduced-motion: no-preference`.** Gating the whole fallback — as the earlier draft did — left first load under `reduce` with no specified appearance at all, an empty slot indistinguishable from "not computable", and contradicted the Accessibility Floor's own "replaced by a non-animated cue, never removed". Substance is never gated; only dressing is.

#### The recomputing cue — anatomy *(specified 2026-08-05; it was named five times across both spines and defined in neither)*

{components.recomputing-cue} is the operative element of the pending treatment: without it, a dimmed number is just a dim number. One line, directly under the value, **inside the slot's reserved footprint** so nothing reflows when the real value lands:

```
⟳ Last known 2026-08-04 · recomputing
```

- **Glyph:** the shipped `.spinner` ring (app.css:4706-4716) — `0.8em` square, `2px solid currentColor` border with a transparent top segment, `border-radius: 999px`, `margin-right: 0.4em`, `vertical-align: -0.1em`. It is deliberately **not a new icon**: the three severity glyphs and the stale-data clock are additions that wait on an icon-set story, and the cue must not wait with them.
- **Word:** mandatory and load-bearing — "recomputing" (de: "wird neu berechnet"), or "computing" (de: "wird berechnet") in the no-prior-value fallback, where there is nothing to *re*-compute. The glyph may be missed; the word may not. Glyph + word + {colors.text-muted} is three channels, so UX-DR7 holds with both the animation and the colour removed — which is what makes the cue the carrier that survives `forced-colors: active`.
- **Basis:** the as-of date of the value being shown, in the same line, before the word. A dimmed number without its date asserts a magnitude with no vintage.
- **Semantics:** the whole cue is real DOM text and is never `aria-hidden` — it is the sentence that makes the dimmed number honest. The ring is drawn with a border rather than as a character, so it needs no `aria-hidden` and it survives forced colors. The cue never announces on its own: the slot sits outside every `aria-live` region and one polite region per surface announces the transition (EXPERIENCE.md → State Patterns, item 4).
- **Type and colour:** {typography.stat-label} on stat cards, {typography.table-cell} in tables; {colors.text-muted} in both. Never {colors.text-subtle} — the cue is content, and {colors.text-subtle} is barred from content.
- **Reduced motion:** the ring stops and renders as a *complete* ring at 0.5 opacity (`app.css:4724-4730`, already shipped for `.spinner`). Nothing is removed. This is the one place where the "gate all animation behind `no-preference`" form is deliberately not used: the ring must survive `reduce` as a static shape, so it animates by default and is cancelled under `reduce`. The outcome is the rule's outcome; the mechanism differs and that is intentional.
- **Never ⓘ.** ⓘ is the metric-**definition** affordance at eight call sites (`portfolio_live.ex:751/762/776/1077`, `securities_live.ex:993/1147`, `tax_live.ex:369`, `transaction_management_live.ex:199`, `view_switcher.ex:121`). Never `:refresh_cw` either — that glyph already means "sync prices now" (`securities_live.ex:178`, `row_context_menu.ex:52` and `:102`), and a second meaning for a glyph in the vocabulary is banned.

**Relation to the loading verb strings.** The cue **replaces** them; it does not accompany them. Every string enumerated in EXPERIENCE.md → Alignment inventory → UX-DR20 either becomes this cue (when a value is recomputing) or becomes the busy state on its own trigger (when an action is running) — no surface keeps a free-standing verb of its own. The one string the build already gets right is `dashboard_live.ex`'s stale-TTWROR line, which ends "Recomputing." beside a "Loading…" heading; the heading is what goes.

**Settling — accent bar under the number** (owner pick 2026-08-05, option S1 in [.working/loading-affordances.html](.working/loading-affordances.html); S2 "shimmer" and S3 "marker" were the rejected alternatives). Digits render at {colors.text-muted} while a 2px bar in the active accent grows beneath them from zero to the slot's full width over the count. On settle the digits snap to full colour and the bar fades out. Progress is stated rather than implied, and the ornament sits outside the digits so no glyph is ever repainted — the failure mode is a missing bar, never an unreadable number.

Both states carry information about whether a number can be trusted yet — but not the same amount of it, and the earlier blanket sentence ("the animation drops but the indication remains — dimmed digits and a static bar at rest") was **wrong for settling and is withdrawn**. The two spines contradicted each other on exactly this point; this is the reconciliation, and the same two sentences appear verbatim in EXPERIENCE.md → State Patterns:

> Under `prefers-reduced-motion: reduce` the **settling** state does not occur: the final value renders at full colour immediately, with no bar and no dimming. Only **pending** keeps a non-animated cue, because only pending has a value that is genuinely unknown.

The reason is not symmetry but honesty. Settling is by definition the state in which the final value is *already known* and the count-up is cosmetic; keeping dimmed digits and a resting bar under `reduce` would paint a permanent "not final" cue onto a number that is final, telling reduced-motion users indefinitely not to trust a correct figure. The Accessibility Floor's carve-out — "loading indication is information, not polish" — belongs to pending, which has nothing to show, and does not transfer.

**Progressive chart fill — sequential sweep** (owner pick 2026-08-05, option F1 in [.working/loading-affordances.html](.working/loading-affordances.html); F2 "rings resolve inward-out" and F3 "fade-in-place" were the rejected alternatives). Segments appear clockwise, one after another, as the chart builds.

**Corrected 2026-08-05 after the design-critic pass — this is decoration, not progress.** The pick was framed as segments appearing "as their values arrive". They do not arrive separately: allocation is computed in a single `start_async(:allocation)` and lands as one result, so every segment's value is known before the first frame draws. A sweep therefore reveals a finished dataset in an arbitrary order; it reports nothing.

That is allowed — Motion is polish, and polish may decorate the arrival of state. But it must not be *described* as progress, and it must not do what this document forbids the digits from doing:

- The final geometry is computed before the first frame. Every segment occupies its final angle from the start; the sweep animates **opacity or saturation only, never the arc**. A chart must never render a proportion it does not have, and unlike the settling digits — which count toward a value that is genuinely already known — a moving arc would assert a share that is simply false.
- The legend does not settle before the geometry does, so no label ever names a segment whose share is still changing.
- Under `prefers-reduced-motion` the finished chart appears at once, with no cue — there is no information to preserve, precisely because the sweep carries none.

If per-segment streaming is ever built, this entry is revisited: at that point the sweep would carry information and would inherit the pending/settling rules above rather than the polish rules.

### Native controls *(UX-DR19 appearance; rule defined in EXPERIENCE.md)*

{components.native-control}. Date inputs, selects, `<details>` summaries and checkboxes get defined appearances instead of browser defaults. This is where the "unfinished" impression concentrates: on the six UAT screens one date input, three selects, three `<details>` and one checkbox render in browser default beside carefully styled pills and segmented controls.

**Those four numbers describe the screenshots, not the codebase, and a story cut from them would under-scope by an order of magnitude.** Counted app-wide on 2026-08-05: **11** `type="date"` inputs, **29** `<select>` elements, **25** `<details>` elements and **13** `type="checkbox"` inputs. Per-file line numbers are in EXPERIENCE.md → Alignment inventory → UX-DR19.

Precisely: app.css already styles the *container* — `input, select, textarea` share {components.input} — but not the *internals*. The select keeps the native chevron and native option list; `<details>` keeps the native triangle wherever the summary has no class; the checkbox has an accent colour but no defined mark. And `<input type="date">` renders `MM/DD/YYYY` in an otherwise fully ISO product. **Dates render ISO in inputs as well as in displays.**

**Resolved 2026-08-10 (issue 641, Sprint 5):** no browser renders ISO in `type="date"`, so the date input is the one native control that is *replaced* rather than styled — an ISO text input (`YYYY-MM-DD` placeholder, pattern, maxlength 10; no `inputmode="numeric"`, whose iOS keypad has no dash) with live `:invalid` marking. The wire format is unchanged. The native calendar picker is given up for format consistency — a deliberate trade, pinned by `test/invariants/iso_date_input_test.exs`. Selects, `<details>` and checkboxes stay native-styled work.

The checkbox is one control: box and label sit on one line, the label is the hit target, and the pair is spaced on the scale. The classification form's broken checkbox stack — a bare box alone on a line with its label underneath, running into the next field's label — is the failure this rule prevents.

### Inventory (as built)

- **App shell** (`.app-shell`) — fixed sidebar with grouped nav (`.nav-group`, uppercase group heads, icon + label rows), active link per {components.selected-nav}. The Classifications group is **one static entry** (`nav_groups/0`, `app_shell.ex:266-294`); the per-tree list and its `+` affordance live on `/classifications` itself — corrected 2026-08-05 against the build, per ADR-0024 (a tree is an entity, not a task). The sidebar background is viewport-height rather than page-height, leaving a cut edge on long pages — a defect. Nav entries follow ADR-0024: navigation reflects user tasks, not the storage model; a new entity does not get a sidebar entry by default.
- **Top bar** (`.topbar`) — burger toggle, brand, page title + subtitle, then theme menu, accent menu, EN/DE locale switcher (pill text ≥ 11px, pinned by the spacing-scale test).
- **Area tabs** (`.area-tabs`, `.detail-pane-tabs`) — the Wealth areas are Holdings · Allocation & targets · Cash flow · Snapshots · Tax; Cash flow's second level is Income · Realized gains · Deposits & withdrawals · Costs. Both levels per {components.selected-nav}.
- **Stat card** (`.stat`) — {components.stat-card}: three-color gradient hairline, uppercase label, 30px value. Signed values take semantic colour, not the accent (see Colors).
- **Hero** — **retired 2026-08-05.** {components.hero} was specified for the four-metric-card Overview of the superseded UX-DR2. That rule now follows the build (EXPERIENCE.md UX-DR2): the Overview is value + change, "Needs attention", and data quality, and no hero component was ever built. The anatomy stays in the frontmatter as a record, unreferenced by any surface. [mockups/key-dashboard.html](mockups/key-dashboard.html) is downstream of the superseded rule and is **stale** — it illustrates a composition this document no longer specifies. Re-render or retire it before the mock is used as a reference again. (The spines-win-on-conflict clause is stated once, in EXPERIENCE.md → IA; it is not repeated here.)
- **"Needs attention" card** (`#dashboard-attention`) — {components.needs-attention-card}: heading, basis line, up to five drift rows, each a link into Wealth → Allocation & targets. The basis line is half-built today: the threshold clause ships (`data-role="attention-explainer"`), the view and the plan it is computed against do not. The empty case is a plain muted line (`data-role="all-clear"`), which is correct and stays.
- **Overview data quality** (`#dashboard-data-quality`) — {components.data-quality-line}: one line, only when N > 0, no all-clear badge, remedy link pre-filtered. Built as a three-card grid; see Components → Data quality.
- **Wealth data quality** (`#portfolio-data-quality`) — six findings as {components.data-note} rows at their own severities. Built as one bare `<h2>` plus six identical `<li>` bullets.
- **Inline results** — {components.inline-result}: in-flow feedback beside its trigger, reusing the data-note severities, no timer. Replaces `.status-toast` and the `AutoDismissToast` hook (issue #566).
- **Connection state** — {components.connection-state}: one band under the top bar for a lost or reconnecting LiveView socket. Nothing is built and nothing is styled; LiveView 1.2.8 already applies the classes.
- **Tax budget meter** — {components.budget-meter}: track, accent fill, remaining amount, as-of basis line. Explicitly no threshold colouring.
- **Panel** (`.panel`) — generic elevated container, {components.panel}.
- **Data tables** (`.data-table`, `.detail-*-table`, `.drift-table`, `.cash-table`, `.soll-table`) — {components.data-table}. One header treatment: {typography.table-head} on {colors.bg-muted}; the sentence-case-no-rules variant is retired. Numeric columns are right-aligned — app.css has per-table `.num` rules but no generic one, so income's money cells carry `class="num"` with nothing behind it.
- **Charts** — one shared component (`security_chart.ex`, ADR-0022) used at two call sites (`portfolio_live.ex:1700`, `securities_live.ex:630`), plus **four** hand-rolled implementations still in the build: the allocation sunburst (`portfolio_live.ex:1790`), the snapshot two-polyline comparison (`snapshots_live.ex:440`), and the Income surface's **two** separate bar charts (`income_live.ex:108` annual, `:203` per-month). {components.chart-frame}: accent quote line (1.6px) over the 0.14-opacity accent fill, moving-average overlays, cost-basis line, **buy/sell markers that must be shape-coded and are not** (▲ buy {colors.tx-buy}, ▼ sell {colors.tx-sell} is the requirement; `security_chart.ex:129-136` renders one `<circle r="4">` for both types and `app.css:3126-3132` changes only `fill`, so the built markers are hue-only — issue #645, filed under Colors → Violations), mono axis text, crosshair + {components.chart-tooltip} via the `ChartCrosshair` hook. New chart work uses the shared component; the snapshot comparison inherits its axes, crosshair and data-as-table disclosure when it moves over — but not a period control, whose domain is fixed by the snapshot's as-of date.
- **Allocation visuals** — donut and sunburst SVGs with legends (`.donut`, `.sunburst-seg`), drift tables with category swatches, display-only rebalancing hints (`.rebalance-hint`, ADR-0023 — an annotation, never an action).
- **Tax budget** (`.tax-budget`) — {components.budget-meter}: allowance-order utilization per institution as a fill level with the remaining amount and its as-of date, **no threshold colouring**; recorded statements below as a list, each carrying its consistency finding as a {components.data-note} severity. Entry forms behind a disclosure; the permanent prose paragraphs become ⓘ tooltips (enumerated in EXPERIENCE.md → Alignment inventory → UX-DR11).
- **Forms** — stacked label-over-input grids ({components.input}); buttons are quiet elevated rectangles ({components.button}) with `.button-primary` / `.button-danger` variants. **One primary action treatment:** solid filled button; the outline button is the secondary; invisible grey inline text is not an action treatment. Forms sit behind disclosure, not in the primary sightline. Per-account actions live in their row: **the global cash-balance form is `form.inline-form.balance-form` on Wealth — Holdings (`portfolio_live.ex:1509-1531`), not on Accounts & depots** — see EXPERIENCE.md → Component Patterns → Cash accounts for what moves where.
- **Feedback** — {components.data-note} replaces `.alert-error` / `.alert-success` / `.alert-warning` / `.alert-info` / `.hint` / the dq chips. `.empty-state` wells stay. {components.inline-result} replaces toasts (`.status-toast` and the `AutoDismissToast` hook, issue #566).
- **Overlays** — `.modal` + backdrop, `.popover` for column pickers and filters, `.row-context-menu` (kebab menu, bottom sheet under 720px). **The requirement is a native `<dialog>` opened with `showModal()`, focus-trapped and inert-backed (UX-DR9); no modal in the build is one (issue #646).** `lib/portfolixir_web/` contains **zero** `<dialog>` elements and **seven** `aria-modal` attributes — six on `<div class="modal" role="dialog">` (`securities/security_form_dialog.ex:73`, `securities/split_wizard_dialog.ex:37`, `securities/logo_override_dialog.ex:25`, `securities/row_context_menu.ex:160`, `portfolio_accounts/account_form_dialog.ex:50`, `buckets_live.ex:382`) and one toggled on the securities detail `<aside class="detail-pane">` (`securities_live.ex:418`), which is not a dialog at all. None of the eight LiveView hooks is a focus trap. `aria-modal="true"` without containment is worse than omitting it: the screen reader confines its virtual cursor to the dialog while `Tab` keeps walking the page behind it, so reading position and keyboard focus separate silently. Immediate correction, independent of adopting `<dialog>`: remove `aria-modal` from the detail pane.
- **Import surfaces** — drop zone, progress, stat cards, notes.
- **Drag-and-drop rows** (`.dnd-row`, `.dnd-dropzone`, classifications tree) — selection per {components.selected-row}.
- **Chips** — one chip: {components.chip}, a filled tag. The outline chip and the grey initial-avatar square are separate things wearing the chip's clothes; the avatar is a logo placeholder (`.security-logo--initial`) and reads as one.
- **Chart tooltip** ({components.chart-tooltip}) — the crosshair readout, mono type on {colors.bg} in a {rounded.sm} bordered box, positioned by the `ChartCrosshair` hook. One tooltip for every chart surface; a chart that invents its own readout is drift.
- **Buttons and inputs** ({components.button}, {components.input}) — the two base controls every other control inherits from: {colors.bg-elevated} on a 1px {colors.border}, {rounded.md}, {spacing.density-control} minimum height on desktop and {spacing.touch-target} under `pointer: coarse`. {components.native-control} inherits the input container; {components.selected-segment} inherits neither and is its own track.

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
| Pair every semantic hue with a sign or shape (+/−, ▲/▼, glyph) | Encode gain/loss, buy/sell, staleness, value-slot state or note severity in hue alone |
| Carry every state in text, glyph or border as well as colour, so it survives `forced-colors: active` | Let a colour step be the only difference between pending, settling and final |
| Mark a stale value stale — `aria-busy` on the slot plus real text before the digits | Dim a number and treat the dimming as the marking |
| Solve a design problem with a component | Fall back to a paragraph of prose (UX-DR11) |

Note on the last two rows, both measured in the build.

**Focus, recounted 2026-08-05 and corrected again in the accessibility pass the same day.** Eight `outline: none` declarations exist in `app.css` (402, 627, 680, 758, 1393, 2057, 2126, 2163). They split into two classes, and the split is what a fix story needs.

**Six `:focus-visible` rules substitute a hover background for the indicator, covering eight controls** — one more than the previous count, which read the 623-629 selector list as the accent trigger alone when it names both triggers:

| Rule | Controls | Status |
|---|---|---|
| app.css:398-403 | `.nav-link` | needs the shared outline |
| app.css:620-629 | `.theme-menu-trigger` **and** `.accent-menu-trigger` | needs the shared outline — **the previously missed one**; the earlier citation started at 623 and so read the selector list as the accent trigger alone |
| app.css:673-681 | `.theme-choice` **and** `.accent-choice` | needs the shared outline |
| app.css:755-759 | `.locale-link` | needs the shared outline |
| app.css:2122-2127 | `.row-actions__kebab` | needs the shared outline |
| app.css:2160-2164 | `.row-context-menu__item` | needs the shared outline |

**Not one of the eight is justified in place.** A hover background is a hover treatment; reusing it for focus means focus and hover are indistinguishable and neither is guaranteed 3:1 against its container. The correction is one shared `:focus-visible` rule carrying the 2px accent outline, not eight reinstatements — and it must land with a `outline-offset` of at least 2px wherever the focused element's own fill is the accent ({components.selected-segment}`.option-active`, the active tab underline), or the outline abuts its own colour at 1:1.

**Two further rules set `outline: none` unconditionally, not only on `:focus-visible`** — strictly worse, because the control then has no focus indicator in any state:

- `.search-field input` (app.css:1389-1397);
- `.securities-detail-splitter` (app.css:2050-2058) — which carries `tabindex="0"` and `role="separator"` (`securities_live.ex:348-356`), so it is a keyboard-operable control with no visible focus at all, and whose only focus signal today is its handle turning accent-coloured, which is colour-only and fails UX-DR7 as well.

**And four controls have no `:focus-visible` rule whatsoever** — `.segmented-control__option`, `.range-button`, `.chart-toggle`, `.period-buttons .button-mini` — falling back to the UA ring. Those four are exactly the classes {components.selected-segment} consolidates, so the aligned component arrives carrying the focus rule or the alignment story has silently made focus worse. `.area-tab` (app.css:4347-4350) and `.positions-toggle` (4376-4379) indicate focus by a text-colour change only, which is the same colour-only failure as the splitter.

And `input:focus` uses the 18%-opacity ring *as* the indicator rather than as decoration on top of a solid 2px outline — the commitment under Colors says the reverse.

**Prose is the default fallback for anything the design did not solve:** free-standing explanatory paragraphs across six screens, with the TTWROR explanation existing simultaneously as an ⓘ tooltip (`portfolio_live.ex:762`) and as a paragraph (`portfolio_live.ex:912-919`) on the same screen. UX-DR11 is not occasionally missed; prose is the habit. Each paragraph, with its file, region and the UX-DR11 outcome it resolves to, is enumerated in EXPERIENCE.md → Alignment inventory → UX-DR11.

## Motion *(UX-DR5 — defined here in full; summarised in EXPERIENCE.md's rule index)*

Promoted from a subsection of Do's and Don'ts on 2026-08-05: it now carries UX-DR5, the count-up mechanism ruling, the ninth-hook decision, the reduced-motion contract and half the settling anatomy — material two of the three loading decisions rest on, and a consumer looking for pending/settling anatomy should not have to find it under a Don't. The eight canonical sections above keep their order; this is a trailing section.

Motion is **polish only** — it decorates state arrival, it never encodes information (binding decision).

- **Chart build-in:** one-shot on load/data-change, ease-out. Perceived behavior: the performance line draws in from left to right, area fill fades up, bars grow from the baseline, headline numbers count up. Staggering (e.g. bars left→right) is allowed for texture but carries no meaning. Never looping, never replaying on scroll.
  **Duration per surface** (the earlier "~600ms–1.5s" was a range with no rule, so three surfaces would have picked three numbers): **600ms** for anything that animates alongside a settling value — the two `SecurityChart` surfaces and the income bars — so the chart and the count-up finish together and the surface settles once, not twice. **1.5s** only for the allocation sunburst's sequential sweep, which has no companion count-up and whose whole purpose is texture. No third duration.
- **Count-up is visibly not-final.** The 2026-08-05 owner ruling: a cosmetic count-up to the final value is wanted *provided it is evident the number is still counting*. That is the `settling` state of {components.value-slot} — no real partial values are ever streamed; the count starts only once the final value is known.
- **Mechanism lane, line drawing and bars:** CSS `stroke-dasharray`/`stroke-dashoffset` for the line draw-in, `transform: scaleY()` from `transform-origin: bottom` for bar growth. No JS involved, no bundler required.
- **Mechanism lane, count-up — the CSS `@property` assumption is falsified.** The previous draft specified a pure-CSS counter. It cannot work: `counter()` renders an integer with no separators — `250000`, never `250.000,00`. Pure-CSS count-up and locale-formatted money are mutually exclusive, and money is always locale-formatted here. There is no CSS-only path to a counting money value.
  **Resolved 2026-08-05 (owner):** a ninth hand-written inline LiveView hook — `requestAnimationFrame` driving the count, `Intl.NumberFormat` formatting each frame. The repo already carries eight (`AutoDismissToast`, `ChartCrosshair`, `ClassificationDnD`, `ColumnPrefs`, `PPImportDrop`, `PositionedMenu`, `SecuritySplitPane`, `SunburstTooltip`), so this is existing practice: no bundler, no dependency, no architecture change. The hook also drives the settling accent bar, which is why the bar can state real progress rather than merely claim it. The alternative — dropping count-up on money — was considered and declined.
- **Micro-motion (as built, keep):** 140–180ms ease transitions on nav hover, sidebar collapse, and color shifts; a 0.7s spinner on loading tabs.
- **Reduced motion:** gate ALL animation behind `@media (prefers-reduced-motion: no-preference)` — the opt-in form, so reduced-motion users get the finished frame instantly. **One sanctioned exception:** an indicator that must survive `reduce` as a static shape animates by default and is cancelled under `@media (prefers-reduced-motion: reduce)`, because the opt-in form would remove the shape along with the motion. `.spinner` (app.css:4706-4730) is the shipped instance and is the mechanism {components.recomputing-cue} inherits. The rule's outcome — no motion under `reduce`, no information lost — is unchanged; only the form differs, and only where a static remnant is required.
  **Live defect, restated 2026-08-05 (issue #647): the build implements the opt-out form everywhere, and the earlier "the skeleton is the outlier, not the norm" described a compliance the stylesheet does not have.** `app.css` contains **zero** occurrences of `no-preference`. Every gate in the file is `@media (prefers-reduced-motion: reduce)` — four blocks, at 2522, 3017, 4649 and 4724 — plus the ungated `.section-skeleton` (`skeleton-shimmer 1.6s ease-in-out infinite`, app.css:4426-4437, on the dashboard and portfolio surfaces), which violates the reduced-motion rule and the no-looping-ambience rule below at the same time. The two forms are **not** equivalent: where the media feature is unsupported or unreported, `reduce` fails open and the animation runs, while `no-preference` fails safe. So four animations having a `reduce` fallback is the *sanctioned-exception* form (below) applied by default rather than by decision — correct for `.spinner`, which must survive `reduce` as a static ring, and wrong for the other three. Correction: every animation except a must-survive indicator moves to the `no-preference` gate; `.section-skeleton` gains a gate either way.
  **The count-up hook is not covered by any CSS gate at all**, because it is JS. It reads `matchMedia("(prefers-reduced-motion: reduce)")` before the first frame and subscribes to its `change` event; under `reduce` it assigns the final value directly and never enters the settling state (see {components.value-slot}`.settling`).
- **Never:** looping ambience, parallax, motion on every LiveView patch, animated layout shifts in tables.
