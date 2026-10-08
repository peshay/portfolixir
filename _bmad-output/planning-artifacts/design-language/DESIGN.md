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
  # Darkened from #e11d48 on 2026-10-03 (Sprint 18 pick H5, issue 908): the
  # same hue one step darker, the smallest step that clears 4.5:1 as body
  # text on every light surface — Colors, the computed contrast table.
  # brand-coral-2 above keeps #e11d48 for the logo gradient.
  accent-coral: '#ce1b42'
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
  section-pad-inline: 'clamp(16px, 2.4vw, 28px)'
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
    variants: 'lead (.stat--lead, 132px min, sub-line) and compact (.stat--compact, 96px min, 22px value) on the Wealth band since issue 797 — Components → KPI band'
    value-suffix: '<small class="value-suffix"> after the digits, {typography.stat-label} size, {colors.text-muted}, 4px gap; digits never wrap'
    sub-line: '.stat__sub — 12px/500 {colors.text-muted}, its figures 650 {colors.text}, signed ones in their sign colour'
  kpi-strip:
    frame: '1px solid {colors.border}, {rounded.lg}, {shadows.panel}; cells divided by 1px {colors.border}; two by two under 560px'
    cell: 'a link, 84px min, 14/16px padding; label {typography.stat-label}; value 20px/700 {colors.text} (signed: {colors.positive}/{colors.danger}); sub-line 12px {colors.text-muted}'
    stale-sub-line: '{colors.warning}, weight 600, :alert_triangle at 12px before the count; rendered only when the count is > 0'
    basis-line: 'view · period to date · currency · what the quotes cell measures'
    pending: 'label stays, value skeleton at the value footprint, aria-busy; the strip is absent in the empty state'
  phone-row:
    grid: 'auto minmax(0, 1fr) auto auto — logo, body, figures, kebab; 10px column gap; 10px block padding; 1px {colors.border} between rows'
    name: '{typography.table-cell} weight 600, wraps'
    identifiers: '12px {colors.text-muted}: ticker · ISIN · class badge (or the quick-assign control); date · kind over the subject on the history'
    figures: 'right-aligned tabular; the first at 14px/600, the second at 12px muted (the change, the stale marker, quantity × price)'
    states: 'is-selected paints {colors.selected}; is-retired dims like the table row; "no price" and "—" as words'
    shown: 'under 560px only — the table wrapper is display none there, the rows display none above'
  filter-sheet:
    control: '.filter-sheet-toggle — a pill (1px {colors.border}, 999px) with the filter glyph, the word Filter and the active-chip count as a badge; inline-flex under 560px, display none above'
    sheet: 'native <dialog> at the viewport bottom (the row menu mechanism): full width, 85vh max, 12/16px padding plus the safe-area inset, top corners {rounded.md}, the modal backdrop tints'
    families: 'stacked blocks headed by their names ({typography.stat-label} voice), chips wrapping; the builder in flow; Reset and Done at the foot'
    focus: 'the ModalDialog hook — showModal on open, Esc closes, focus returns to the control'
    surfaces: 'both list surfaces that carry a chip row — the securities toolbar (issue 800) and the transaction history (issue 816). The history sheet stacks the account, type and changed-since families and takes the demoted "More filters" conditions in with them, so the phone has ONE filter entry point; above 560px each page renders its own unchanged chip row and the control is hidden'
  bucket-list:
    scope: 'the index of a thing you own several of and open one of: the Views and Buckets lists, and the Classifications index (issue 808). Not a data table — a table is for comparing columns, a bucket-list is for choosing a row'
    row: 'a link element, not a row with a link in it: `__main` carrying `__name`, then `__rule` or `__usage` in {typography.control-label} voice at {colors.text-muted} under it, `__figures` in the trailing slot, and the kebab of the Tables pattern as the trailing action. The whole row is the target; the kebab is the only thing inside it that is not'
    figures: 'SHORT and tabular — the slot is `white-space: nowrap` and right-aligned. A user-supplied name never goes in it; a name belongs in `__main`, where it can wrap'
    empty: 'the .empty-state sentence, never a bare `<ul>` — a list that renders nothing looks broken rather than empty, and every other new list in the batch carries one'
  bucket-cell:
    chips: 'the assigned buckets as {components.chip}, the + control after them, a +N overflow chip past four; an empty set reads as the word "no bucket" in muted italic, never as a blank cell'
    overflow: 'a real <button> disclosure that expands the cell in place (issue 842, Sprint 14 pick E2-A, 2026-09-23; board ux-design-2026-09-20/02-bucket-overflow-chip). Two states: collapsed it reads "+N more" (DE "+N anzeigen") over the first four chips; expanded every assigned chip renders and it reads "Show fewer ▲" (DE "weniger"), the caret aria-hidden. aria-expanded as a string, the 2px accent focus ring, the 44px floor under pointer: coarse. It never opens the picker — the + control does. No meaning in the cell lives only in a title attribute: the overflow carries none, the scope sub-line replaced the "Both" micro-label, and a chip title only repeats that chip own visible name past its truncation'
    scope: 'a sub-line under the chips saying what the set applies to — depot and cash account, the depot, or the cash account — readable without interacting; it replaces the "Both" micro-label whose meaning lived in a title attribute (issue 806, variant A)'
    actions: 'row actions behind the kebab of the Tables pattern, never as a fourth control in the cell: "Tag separately" sits there'
    role: 'the Liquidity role select carries its label visually-hidden above 640 px — the column head states it once for the whole table; under 640 px the head is hidden too, so the label shows beside the select (`.liquidity-role-field__label`, {typography.control-label} size at 11px, weight 600, {colors.text-muted}) with the role''s ⓘ beside the word (amended 2026-10-07, issue 1085, board ux-design-2026-10-04/07-floor rule ⑦)'
    target-size: 'under @media (pointer: coarse) the chip''s × and + are {spacing.touch-target} squares, and a chip holding a × gives up its block and right padding so the × fills its end (46px on touch), its corners the pill''s end (0 left, {rounded.full} right) and no shadow at any width; the role select and "Set balance" take {spacing.touch-target} min-height, and the role field keeps {spacing.3} between label, ⓘ and select so the ⓘ''s touch ring stays off the select. On the desktop the + is the 22px circle it declares (`min-height: 0`). Added 2026-10-07, issue 1085, rule ⑧, and the review of U5'
  security-metric-grid:
    placement: 'under the price chart on the securities detail chart tab, never on a tab of its own — a moving average means its distance to the price and its crossing with the other average, and separating the figures from the series makes both unreadable (issue 824, pick D1-A)'
    cells: 'the .overview-metrics grid of issue 804, reused rather than reinvented: a `<dl>` of `auto-fit` cells (two per row under 720px), each a {typography.stat-label} term over a {typography.stat-value} value, the distance or unit in the {components.value-slot} suffix, and the window plus the observation count as a {typography.control-label} sub-line at {colors.text-muted}. Six cells: SMA-50, SMA-200, volatility, maximum drawdown, momentum, the 52-week range. A signed value carries the sign colour the same grid carries on the Overview tab — two tabs of one pane may not disagree'
    series: 'SMA-50 and SMA-200 draw as the chart second and third series by default, their toggles unchanged so a reader can turn them off. Because they are on by default the chart carries a LEGEND naming every active overlay, each swatch drawn with that series own stroke class — the toggle pill tint is colour only and disappears under forced-colors, so it is not a mapping from a dashed line to a name'
    period: 'ONE control: the chart own range buttons. The engine windows are fixed (30/90/365 days and 3/6/12 months), so a range snaps to the nearest at or below it and the cell NAMES that window in words — "90 days", "12 months" — beside the span it measured. A date range alone is not the disclosure: a reader who picked 6M would have to subtract two ISO dates to learn the figure is a 90-day one'
    refusal: 'a metric below its minimum reads "not computable" and still shows its observation count — the reader learns how far short the series falls, not that the figure is zero'
    basis: 'one line under the grid: the series, the currency, the gap rule, the annualization, and that the block reports rather than evaluates'
  security-events-tab:
    placement: 'the ninth tab of the detail pane — "Dates", de "Termine" (issue 828, pick D2-B); the Research tab keeps exactly what it has. The label follows the bilingual rule: the source string is English, the German translation is German, and a German word in the English UI needs the term-of-art carve-out, which a calendar tab does not have'
    rows: 'the .research-timeline shape of ADR-0044 reused, not a second list: an ordered list, newest relevant first, each entry a head / body / meta stack. The head carries the kind as a badge, the date said the way it is known (a day, a range, a month), the timing qualifier and the ADR-0044 source quality as words; the body is the note; the meta line is the source link and the last-checked day. The timing qualifier and the confirmed marker are two different facts and neither label may contain the other — "Announced" is the date being set, "Took place" is it having happened (Sprint 13 closing act)'
  due-card:
    placement: 'the Overview attention column beside Off target and data quality (issue 828, pick D3-A) — no route, no sidebar entry, per ADR-0024'
    scope: 'the WHOLE CATALOG by default; a security with no position carries a "no position" badge and is kept, because filtering it away is the defect the object exists to prevent'
    rows: 'security, kind, the date and its timing qualifier, each row linking to that security Termine tab; absent entirely when nothing is due, never an empty card'
  booking-drawer:
    shape: '{components.panel} in the detail pane\'s dress (.detail-pane): 1px {colors.border}, {rounded.lg}, {shadows.md}, {spacing.3} padding; a head with the title and a close control'
    placement: 'a native <dialog> opened non-modally beside the history (grid minmax(0,1fr) minmax(320px, 380px)), sticky under the top bar; under 720px a modal bottom sheet (fixed, full width, 88vh max, the modal backdrop tints)'
    fields: 'stacked {components.native-control}s — type, date, the depot it books to, security — then quantity and price paired; costs and note behind one disclosure; the sell-lot preview beneath'
    foot: 'Record transaction as {components.button}.primary, Cancel as the ghost button'
    focus: 'the ModalDialog hook with data-sheet-below="720": show() or showModal() by width, Esc closes both, focus returns to the control'
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
    group: 'inline-flex, 1px solid {colors.border}, radius {rounded.md}, background {colors.bg}. No overflow hidden (#875 review round, 2026-09-25): the clip cut the options'' outset focus ring off at the track''s edge, so an option next to the filled one showed no focus at all; the outer options round their own outer corners ({rounded.md} less the 1px border) and the active fill follows the track without it'
    option: 'min-height 30px, padding 4px 9px, {typography.control-label} in {colors.text-muted}, 1px {colors.border} divider, no radius except the outer corners of the first and last option, no shadow. The 30px is the DESKTOP density only; it is a third desktop step alongside {spacing.density-control} (34px) and is left unreconciled here — recorded as a follow-up, not solved opportunistically.'
    target-size: 'under @media (pointer: coarse) the option takes {spacing.touch-target} min-height with the label unchanged at 12px (UX-DR6, added 2026-08-05 — the definition previously wrote a 30px target and named no floor, which is what let the whole segmented family ship uncovered). This clause binds every call site the class absorbs: .segmented-control__option, .range-button, .chart-toggle, .period-buttons .button-mini, .view-chip. Only .view-chip has the clause today (app.css:4888-4891). Amended 2026-10-07 (issue 1062, board ux-design-2026-10-04/07-floor rule ② and found while drawing): .segmented-control__option, .range-button (44 × 44) and .chart-toggle carry it; .period-buttons .button-mini does not yet.'
    option-hover: 'background {colors.hover}, text {colors.text}'
    option-active: 'filled {colors.accent}, text {colors.on-accent}'
    option-focus: 'the solid 2px {colors.accent} outline at a 2px offset, clear of the option''s own fill; the focused option paints above its neighbours (position relative, z-index 1), and the track never clips the ring'
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
    custom-range: 'behind a disclosure ({components.disclosure}), never permanent chrome; its body is a popover on the trigger (issue 801, C5-A) — the heading and the chart do not move when it opens'
    date-fields: '{components.native-control} — ISO in the input; the applied range chip reads Format.date (amended 2026-10-07, Sprint 19 U3; it said "not only in the display")'
  disclosure:
    scope: 'data-as-table under every chart; custom range; entry forms out of the reading sightline'
    rule: 'UX-DR10 (defined in EXPERIENCE.md), UX-DR19 for the marker'
    control: 'quiet text summary — {typography.control-label} in {colors.text-muted}, pointer cursor'
    marker: 'defined chevron, never the raw browser triangle'
    action-summary: 'a disclosure that opens an action rather than data keeps the accent colour (the plan editor''s "Rename" and "Positions (n)", issue 873 and F2-A); the marker and the size are the class''s'
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
    dates: 'ISO (YYYY-MM-DD) in the input; a displayed date follows the page language through Format.date — DD.MM.YYYY in German, ISO in English (UX-DR19 as amended 2026-10-03; amended here 2026-10-07, Sprint 19 U3)'
    checkbox: '14px box, accent-color {colors.accent}, label on the same line as the box'
  button:
    background: '{colors.bg-elevated}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    min-height: 34px
    focus: 'the solid 2px {colors.accent} outline at a 2px offset on :focus-visible, one rule for .button, .button-primary, .button-ghost, .button-danger and .button-secondary; the ring sits outside the fill, and hover stays the fill change (2026-10-07, issue 1062, board ux-design-2026-10-04/07-floor rule ③)'
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
    focus: 'the row (`.attention-item`) draws the shared 2px {colors.accent} outline at a 2px offset with {rounded.sm} corners under :focus-visible, never the browser ring; hover stays the underlined name. The same rule serves "Abgeschlossene Trades" and "Fällig" (Sprint 18 U4, H6.3, issue 1033).'
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
    page-slot: 'a page that answers an action at its top — the transaction history, Accounts & depots, Buckets, Classifications, and Risk''s rule section — answers through this component, never through `.alert-success` / `.alert-error`: a success is a note, a refusal a problem (2026-10-07, issue 1064, pick J7 = A of board ux-design-2026-10-04/07-floor). Under coral in the dark theme the two alerts were pixel-identical and carried no word. The slot takes `.inline-result--page`, which keeps the alert''s footprint: the side gutter, 12px above a result, nothing at rest'
    dismiss: 'the × (`.inline-result__dismiss`) sits on the sentence line: 1.4rem wide, 1rem high, no 34px button floor, so a one-line result is one line (36px) with its severity word beside the sentence; under `pointer: coarse` 44 × 44 with 14px block padding given back as a negative block margin, so the target is 44px and the line stays 18px (Sprint 18 U4, H6.4, issue 1033)'
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
- Accent as text: **all three accents pass at body size in both modes**, on every surface a link or an accent word sits on — the canvas, panels, muted wells, the accent's own tint and the attention and problem notes (computed table below). Until Sprint 18 coral passed only as large text in light mode (`#e11d48`, 4.38:1 on the canvas) while the build used it as body-size link text everywhere; issue 908 (pick H5) moved {colors.accent-coral} to `#ce1b42`, and the closest row is now coral on its own tint and on {colors.danger-soft} at 4.53:1.
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

**Recomputed 2026-10-03 (Sprint 18 pick H5, issue 908): the coral rows, after {colors.accent-coral} was darkened from `#e11d48` to `#ce1b42` in light mode.** Every other figure in the table was re-checked to two decimals and is correct. One verdict was inverted and is corrected ("accent-coral / bg-elevated 4.70 — fail normal text": 4.70 passed). New rows give every accent on the surfaces where a remedy link actually sits — {colors.bg-muted} (note-severity data note), {colors.warning-soft} (attention) and {colors.danger-soft} (problem). The "selected" rows are re-keyed to the accent tints: since issue 644 `--color-selected` is `var(--color-accent-soft)`, so `#ede9fe` was only the violet case, and `selected-dark #1f2c42` cited a colour `app.css` no longer has. **The thinnest margins are stated, not absorbed:** coral on coral-soft and on danger-soft (the same `#ffe4e6`) clears the bar by 0.03, teal on danger-soft by 0.06; lightening either tint later reopens those rows.

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
| accent-coral #ce1b42 / bg | 5.08 | pass (was 4.38 at `#e11d48`, fail) | coral accent text, link text |
| accent-coral / bg-elevated | 5.44 | pass (was 4.70 at `#e11d48` — a pass the table had marked "fail") | coral stat values, links in panels and tables |
| accent-violet / violet-soft #ede9fe | 4.80 | pass | active nav, alert-success |
| accent-teal / teal-soft #ccfbf1 | 4.86 | pass | active nav, alert-success |
| accent-coral / coral-soft #ffe4e6 | 4.53 | pass, 0.03 of headroom (was 3.91, fail) | active nav wash, alert-success |
| accent-violet / bg-muted #eef1f6 | 5.03 | pass | a remedy link in a note-severity data note |
| accent-teal / bg-muted | 4.83 | pass | same |
| accent-coral / bg-muted | 4.81 | pass (was 4.15, fail) | same |
| accent-violet / warning-soft #fffbeb | 5.50 | pass | a remedy link in an attention data note |
| accent-teal / warning-soft | 5.28 | pass | same |
| accent-coral / warning-soft | 5.25 | pass (was 4.53) | same |
| accent-violet / danger-soft #ffe4e6 | 4.75 | pass | a remedy link in a problem data note |
| accent-teal / danger-soft | 4.56 | pass, 0.06 of headroom | same |
| accent-coral / danger-soft | 4.53 | pass, 0.03 of headroom (was 3.91, fail) | same |
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
| text / accent-soft (selected): violet #ede9fe · teal #ccfbf1 · coral #ffe4e6 | 15.59 · 16.43 · 15.42 | pass | selected-row content |
| text-muted / accent-soft (selected): violet · teal · coral | 4.96 · 5.23 · 4.91 | pass | selected-row meta |
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
| accent-teal-dark / teal-soft-dark composite (#17383c over bg-elevated-dark) | 6.77 | pass | active nav text in wash, teal |
| accent-coral-dark / coral-soft-dark composite (#341a29 over bg-elevated-dark) | 5.89 | pass | active nav text in wash, coral |
| text-dark / accent-soft-dark composites over bg-elevated-dark (selected): violet #2b2c45 · teal #17383c · coral #341a29 | 11.24 · 10.44 · 13.13 | pass | selected-row content |
| text-muted-dark / the same composites (selected): violet · teal · coral | 4.58 · **4.25** · 5.35 | pass · **fail normal text** · pass | selected-row meta — the teal case is a recorded defect, not repaired by pick H5 (the Sprint 18 design pass, Part 9, lists it for filing) |

Reference (non-normative, decorative): light `border` 1.23:1 and `border-strong` 1.39:1 vs surfaces — fine as decoration since "surface tone first, border second" means borders never solely delineate interactive components; if a control's boundary relies on border alone (quiet buttons do: bg-elevated on bg is near-1:1), the 3:1 UI-component rule technically applies — covered by the focus-indicator finding for the interactive states that matter.

**Added 2026-08-05 (designer): the pairings the 2026-06-13 table never measured.** Computed from the hex values in `app.css` with the same method as the table above (WCAG 2.x relative luminance; translucent tokens composited over their stated base in sRGB, which reproduces the archived `#242339` composite exactly).

| Pair | Ratio | Verdict | Where used |
|---|---|---|---|
| **on-accent on the accent fills — light** | | | |
| on-accent #ffffff / accent-violet #7c3aed | 5.70 | pass | active segmented option, `.button-primary`, active view chip |
| on-accent #ffffff / accent-teal #0f766e | 5.47 | pass | same |
| on-accent #ffffff / accent-coral #ce1b42 | 5.44 | pass (4.70 at `#e11d48`) | same |
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
- {typography.chart-axis} — 9px mono inside SVG, 9 CSS px at every chart width (amended 2026-10-07, pick J5 A: the chart hook's `--chart-upx` undoes the viewBox's scaling; on a chart at most 760 px wide, or when a value is wider than the gutter, the values sit inside the plot on their grid lines).

Inter is used at variable-font weights (500, 540, 600, 650, 680, 700, 740, 760, 780) — fine-grained weight is the primary hierarchy device, not size. **Weight changes on state must be width-reserved** ({components.width-reserve}).

**Closed since 2026-06-13:** the heading ramp gap. `--text-h1/h2/h3` size and weight tokens exist (app.css:60-65) and are pinned by `test/invariants/css_spacing_scale_test.exs`.

**Residual gaps:**

- The ramp is adopted on `.page-header h1`, `.panel h2/h3` and `.workspace-section h2/h3` only. Section headings written as anything else — `.detail-section-title` renders 13px/600 uppercase muted (app.css:2727) — sit off the ramp. Every heading resolves to h1, h2 or h3; there is no fourth step and no bespoke heading.
- 53 of 158 `font-size` declarations in app.css are in `rem`/`em`, the rest in `px`. Mixed units make the ramp unenforceable by inspection. **[ASSUMPTION]** px is the unit of record, matching the token definitions; closes when a lint rule or a review convention is agreed.

## Layout & Spacing *(carries the spacing-scale half of UX-DR14, and UX-DR15 in full — every wide block owns its scroller)*

The shell is a fixed left sidebar ({spacing.sidebar-width}) plus a sticky, blur-backed top bar ({spacing.topbar-height}). On desktop the sidebar collapses to an icon rail ({spacing.sidebar-rail}) via the toggle; content reflows. Workspace pages are full-bleed vertical stacks of `.workspace-section` bands separated by 1px borders, padded {spacing.section-pad-block} block / {spacing.section-pad-inline} inline; card grids use `repeat(auto-fit, minmax(220px, 1fr))` with {spacing.4} gaps. **A page whose blocks are not all bands gives the others the band's gutter** — {spacing.section-pad-inline} inline, the heading {spacing.section-pad-block} above and the last block as much below — so nothing starts at the screen's or the sidebar's edge (issue 873: the classification detail, whose only band is the plan editor; the floor is the 16 px issue 790 built).

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
- **Eight small inline hooks, all eight defined in `layout_view.ex`** — `ColumnPrefs`, `SecuritySplitPane`, `PositionedMenu`, `ChartCrosshair`, `SunburstTooltip`, `PPImportDrop`, `ClassificationDnD`, `AutoDismissToast`. `security_chart.ex` *consumes* `ChartCrosshair` via `phx-hook`; it defines none. The count-up hook approved 2026-08-05 (Motion) is the ninth and lands in the same file. *Recount 2026-09-23 (Sprint 14):* `ModalDialog` and `PopoverDisclosure` have since joined, `AutoDismissToast` has left (issue #566), and `DetailTabs` (issue 837 — the detail pane tab row's arrow-key half; Tab row overflow → keyboard contract) is the newest, all still in `layout_view.ex`.

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

**The remedy's touch target** *(Sprint 18 U4, issue 1013, board `ux-design-2026-10-02/06-touch-focus` H6.1, pick A)*: a `.link-button` remedy stays inside its sentence, and under `pointer: coarse` its hit area is 44 px tall — `padding-block: 13px` grows the box, `margin-block: -13px` gives the 18 px line back, so no note changes height. The box reaches into the neighbouring lines, which hold only text, and on a note's first or last line about 4 px past its border. Desktop is unchanged.

### Data quality — two surfaces, two components

The phrase "data quality" names two different blocks and they are not the same component.

**Overview → data quality is one line: {components.data-quality-line}.** This carries the decision taken in the 2026-07-12 design session and recorded nowhere until now — the decision log names its loss as "precisely the failure mode ADR-0038 exists to stop", so it lands here rather than staying a log entry:

> Data quality on the dashboard is **ONE line**, rendered **only when N > 0**, with **no green all-clear badge**, linking to a **pre-filtered** securities list.

**Adopted 2026-08-05, unchanged; built state re-verified 2026-09-15 (issue 798).** `dashboard_live.ex` renders the line as specified: one `{components.data-note}` (`data-role="data-quality-line"`) at the highest severity present, only when a count is non-zero, each count linking to the pre-filtered list — the URL-addressable `dq` and filter params landed with issues 651 and 688 on 2026-08-14. The Overview's KPI strip (Components → Overview KPI strip) carries the freshness *fact* in its quotes cell; this line stays the *finding*.

**Retired securities (PR #1102, 2026-10-05):** a hygiene finding's count and the list its link opens both leave retired securities out. The asset-class finding is a column filter, not a `dq` predicate, so its link carries `filter[]=is_retired:is_false`, which the list shows as a removable chip. Board: [mockups/retire-fix-2026-10-05/01-class-link.html](mockups/retire-fix-2026-10-05/01-class-link.html).

**The quote finding says its scope, and the line's first finding its noun** *(2026-10-06, issue 1081, Sprint 19 PR α M6; board `mockups/ux-design-2026-10-04/01-overview-total`, pick J1.2 A and "found while drawing" 3)*: the quote finding — the one the strip's basis line about held positions would otherwise contradict — reads "25 Wertpapiere im Katalog ohne Kurs seit 7 Tagen", the catalog-wide count its link opens, as the strip's cell now says too; the class and logo findings say no scope word. **The line's first finding always carries its noun:** when no quote finding opens it, the class or logo finding that does reads "4 Wertpapiere ohne Anlageklasse" / "6 Wertpapiere ohne Logo"; a later finding keeps its short form ("· 4 ohne Anlageklasse"). The line counts nothing it did not count before: what the total leaves out is the value card's note (Components → The Overview's value card), not a count on this line (J1 B was not built). A count of N opens a list of N: `?dq=stale_quote` and `?dq=missing_logo` leave out benchmarks and retired securities as their counts do, and the asset-class count and its filtered list leave out retired securities and keep benchmarks (PR #1102); a test follows each of the three counts to its list.

**The line counts the bonds priced on two scales** *(2026-10-06, issue 1068, Sprint 19 PR α M7, plan D-15; board `mockups/ux-design-2026-10-04/01-overview-total`, pin 5)*: a fourth finding closes the line, "eine Anleihe auf zwei Skalen bepreist" / "2 Anleihen auf zwei Skalen bepreist" (`data-role="dq-two-scales"`; English "one bond priced on two scales"), the singular in words as the line's other findings write it, always with its noun, linking to `/securities?dq=two_scales` — a `Catalog.DataQuality` predicate, so the count is the length of the list it opens (issue 705). It counts both directions and is **catalog-wide on purpose**, keeping sold-out, retired and benchmark bonds, as `missing_fx` keeps its rows: what such a bond inflates or deflates a hundredfold is not only today's total but its booked history — its past values and its realized result — which stays wrong until its bookings or quotes are corrected. While it is non-zero the note takes **problem**, the highest severity present (UX-DR17), above a stale quote's attention. This amends the sentence under "Settled here" (Securities detail → bond master data) that the line does not count the finding. On the securities page the condition is a removable chip, "Auf zwei Skalen bepreist", as `missing_logo`'s is; it has no one-tap chip.

**The line counts the held securities whose quotes do not match their own bookings** *(2026-10-09, issue 1101, Sprint 20 β B4, plan D-7; board `mockups/ux-design-2026-10-07/02-money-findings`, pick L2 A)*: a fifth finding, after two scales, "2 gehaltene Wertpapiere, deren Kurse nicht zu ihren Buchungen passen" / "ein gehaltenes Wertpapier, dessen Kurse nicht zu seinen Buchungen passen" (`data-role="dq-implausible-quote"`; English "2 held securities whose quotes do not match their bookings" / "one held security whose quotes do not match its bookings"), linking to `/securities?dq=implausible_quote` — a `Catalog.DataQuality` predicate, so the count is the length of the list it opens (issue 705). **It carries its scope word**, "gehaltene", because the line otherwise counts the catalog (J1.2): the set is the held securities, retired and benchmark ones kept, for which a buy, a sell or a priced inbound delivery has a stored quote, on its day or the latest within 7 days before it, below half or above twice the booked price per unit; a security on two scales is left to that finding. It always carries its noun, as two scales does. While it is non-zero the note takes **problem**, the highest severity present (UX-DR17): the finding is a contradiction between two stored facts about one day, so a value or a cost in the totals is wrong — "the data contradicts itself; the figure cannot be trusted", not attention's "the figure stands". A tenfold error is not quieter than two scales' hundredfold one because another rule caught it. On the securities page the condition is a removable chip, "Kurs passt nicht zu Buchungen" / "Quote does not match bookings", as `two_scales`' "Auf zwei Skalen bepreist" is; it has no one-tap chip. The Overview's value card says nothing about it: a wrongly valued row is not left out of the total, so J1 A's note does not name it, and this line is the alarm (board 02, found while drawing 12).

**Wealth → data quality is a list of {components.data-note} rows**, one per finding, at the finding's own severity (`portfolio_live.ex`, `#portfolio-data-quality`). Since issue 792 each finding is one `AppShell.data_note`, glyph and word included, with its remedy inside, all in one status region `[data-role="dq-notes"]` under the section's `<h2>`: trade-priced positions (a note), positions valued at a stale quote, positions with no price, positions with no FX rate, pre-1970 booking dates and cash accounts with no FX rate (attention), impossible negative holdings, bonds priced on two scales, in each direction, and positions whose quotes do not match their own bookings (problem). Severity assignment is in EXPERIENCE.md → Alignment inventory → UX-DR17. **The notes keep a gap** *(2026-10-05, #1055; board `mockups/ux-design-2026-10-04/02-money-notes`, found while drawing)*: the status region is a flex column with the `--space-2` gap, the comparison's `.comparison-notes` precedent, so two stacked notes never touch.

**Wealth's eighth note, `dq-implausible-quote`** *(2026-10-09, issue 1101, Sprint 20 β B4, plan D-7; board `mockups/ux-design-2026-10-07/02-money-findings`, pick L2 A)*: a **problem** note after the other problem notes, naming the positions of the page's scope valued at quotes that contradict their own bookings (a security on two scales is left to its own note). Its sentence states the rule, the consequence and the remedy in that order, and links to `/securities?dq=implausible_quote`, as the stale-quote note's does: "2 gehaltene Positionen werden mit Kursen bewertet, die nicht zu ihren eigenen Buchungen passen (am Buchungstag unter der Hälfte oder über dem Doppelten des Preises je Stück); ihr Wert oder ihr Einstand ist daher falsch. Ihre Kursquellen prüfen (Ticker, Börse), dann die Buchungen:" (singular "Eine gehaltene Position wird … Ihre Kursquelle prüfen (Ticker, Börse), dann die Buchung:"; English "One held position is valued at quotes that do not match its own bookings (on a booking's day, below half or above twice the price per unit), so its value or its cost is wrong. Check its quote source (ticker, exchange), then the booking:"). The remedy puts the mapping first, then the booking: a mis-mapped ticker or a currency unit is the common cause, a mistyped price or a bond booked per piece the other. **Each entry names one booking**, the latest whose quote is outside the band, in `.dq-negative-entry`, the two-scales entries' inline block, one space between entries: the name, linking to the security's **Quotes** tab, then "(Verkauf 03.04.2026 zu 61,4 USD · Kurs 02.04.2026: 618,9 USD, das 10,08-Fache)" — kind ("Kauf" / "Verkauf" / "Einlieferung"; "buy" / "sell" / "inbound delivery"), date, booked price and currency, the quote's own date (the day before when none is stored on the booking's), the close, and the ratio with two places. The figures are `Format.exact`, as in the two-scales entries; the link holds the name alone.

**The unvalued-cash note prints each account's native balance** *(2026-10-05, #1055, Sprint 19 PR α M3; the same board's before/after)*: "2 Verrechnungskonten zählen nicht in die Summen, weil kein Wechselkurs zu EUR vorliegt: USD Settlement (1.850,00 USD), US Broker (60,00 USD)." — the balance in at least two decimals, with every further digit it carries (a balance below a cent reads "0,004 USD", never "0,00"), and the account's currency code: the shape the missing-FX note prints a native price in, nothing converted (UX-DR25 clause 2). It used to print "USD Settlement (USD)", the name and the code with no amount, in the note that says the total leaves the money out. It names only accounts that hold money: an empty account leaves nothing out of the total, as the performance walk counts it. The note stays a statement about today; what a balance did before its first rate is the contribution note's sentence (Wealth → Holdings → Performance, pick J2 A), which has a period.

**The icon vocabulary, enumerated (app.css has none of it — the set is `app_shell.ex` `icon_paths/1`, lines 428-535).** 36 named glyphs, all 24×24, `fill="none"`, `stroke="currentColor"`, `stroke-width="1.6"`, round caps and joins, plus a fallback clause that renders a bare `circle r="5"` for any unknown name: `dashboard · layers · bookmark · briefcase · folder · calc · bars · pie · chart_line · chart_bar · coins · tag · globe · building · compass · settings · monitor · sun · moon · plus · upload · filter · columns · search · trash · x · chevron_right · refresh_cw · ellipsis_vertical · copy · edit · archive · external_link · maximize · minimize · image`.

**The three severity glyphs — decided 2026-08-05 (designer's call, owner-delegated). The set does not contain a usable candidate; all three are additions.** Not a preference: no glyph in the list above carries a severity reading, and pressing an unrelated one into service (`x` means dismiss, `bars` means Transactions, the fallback circle means "unknown icon name") would create exactly the second-meaning collision this section forbids. Described in the house idiom so the paths can be drawn to spec; no path data is invented here.

| Severity | Glyph name | Description | Why |
|---|---|---|---|
| Note | `:asterisk` | Three strokes crossing at 12,12 — vertical plus two at ±60°, ~7px arms. | The typographic footnote mark: "a remark attaches to this figure". Reads at 14px with no interior detail, and cannot be confused with the ⓘ affordance. |
| Attention | `:alert_triangle` | Rounded-corner equilateral triangle, apex up, plus a centred vertical stroke and a dot below it. | Universal caution. The silhouette alone separates it from note and problem, so the shape channel survives at nav-icon size. |
| Problem | `:alert_octagon` | Regular octagon, flat side up, with the same interior stroke-and-dot. | Reads as "stop". Distinct outline from the triangle at 14px (flat top vs. point), and unlike a circle-with-X it does not collide with `:x`. |

**Why note is not an info circle:** ⓘ (the literal character, in use at eight call sites — `portfolio_live.ex:751/762/776/1077`, `securities_live.ex:993/1147`, `tax_live.ex:369`, `transaction_management_live.ex:199`, `view_switcher.ex:121`) is the metric-**definition** affordance. A note-severity data note states a fact about *this data*, which UX-DR11 explicitly separates from a definition. One mark for both jobs is the funnel problem again.

**Also missing, flagged not solved here:** the stale-data rule (EXPERIENCE State Patterns) requires a clock glyph, and the set has none. It rides the same icon-set story. *(Closed 2026-09-15 by #789: `:clock` — a circle with hour and minute strokes — is in `icon_paths/1`; the value-cell marker uses `:alert_triangle` per the 2026-09-12 amendment.)*

**Naming collision resolved (2026-08-05, designer): the funnel keeps "filter"; "Views" takes `:bookmark`.** `:filter` is the funnel (`app_shell.ex:488-489`), used for the sidebar "Views" entry (`nav_groups/0`) and for the securities toolbar filter. A funnel means "narrow this list down" to essentially every user, and the toolbar is the literal case, so it keeps the glyph. The sidebar's Views entry takes `:bookmark` — an existing, otherwise unused glyph whose meaning ("a saved, named selection") is what a view is. No addition needed for this half.

### Period control *(appearance of UX-DR16 class 2; the vocabulary and per-surface subsets are in EXPERIENCE.md)*

{components.period-control}. One appearance — the segmented group — and one token vocabulary app-wide: **1M · 3M · 6M · YTD · 1Y · 3Y · 5Y · Max**. Each surface declares which subset it offers; no surface invents a token outside the set. "Custom range…" is a disclosure, not permanent chrome, and its date fields are {components.native-control}. This retires four patterns, two divergent token sets (`Performance.periods()` = `ytd 1y 3y 5y max`; `securities_live.ex:35` `@ranges` = `1M 3M 6M YTD 1Y 3Y 5Y MAX`) and the four bare `type="date"` inputs that sit *inside period controls* (`portfolio_live.ex:853`/`:860`, `securities_live.ex:534`/`:541`). The other seven date inputs in the app are UX-DR19 work, not period-control work.

**The labels are the vocabulary in the reader's language** *(Sprint 18 U5, issue 1033, H7.3)*: a token's label is its gettext — German "1M 3M 6M YTD 1J 3J 5J Max", English "1M 3M 6M YTD 1Y 3Y 5Y Max" — while the URL and the event value stay the code. On the security detail one label function (`range_label/1`) serves the Chart tab's buttons and the Quotes tab's basis line that points at them ("Zeitraum 1J · wie im Diagramm"), so the line and the button never disagree.

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

Precisely: app.css already styles the *container* — `input, select, textarea` share {components.input} — but not the *internals*. The select keeps the native chevron and native option list; `<details>` keeps the native triangle wherever the summary has no class; the checkbox has an accent colour but no defined mark. And `<input type="date">` renders `MM/DD/YYYY` ~~in an otherwise fully ISO product. **Dates render ISO in inputs as well as in displays.**~~ beside ISO date fields. *Amended 2026-10-07 (Sprint 19 PR γ U3; UX-DR19 as amended 2026-10-03):* **dates render ISO in inputs; a date the page only shows follows its language** (`Format.date`: DD.MM.YYYY in German, ISO in English) — Amendment 2026-10-07 → Displayed dates and the chart axes.

**Resolved 2026-08-10 (issue 641, Sprint 5):** no browser renders ISO in `type="date"`, so the date input is the one native control that is *replaced* rather than styled — an ISO text input (`YYYY-MM-DD` placeholder, pattern, maxlength 10; no `inputmode="numeric"`, whose iOS keypad has no dash) with live `:invalid` marking. The wire format is unchanged. The native calendar picker is given up for format consistency — a deliberate trade, pinned by `test/invariants/iso_date_input_test.exs`. Selects, `<details>` and checkboxes stay native-styled work.

The checkbox is one control: box and label sit on one line, the label is the hit target, and the pair is spaced on the scale. The classification form's broken checkbox stack — a bare box alone on a line with its label underneath, running into the next field's label — is the failure this rule prevents.

### Numeric inputs — one rule for every decimal field *(issue 869, Sprint 16; board `ux-design-2026-09-24/05-numeric-inputs`, before/after)*

Every text input with `inputmode="decimal"` shows and reads its figure through
**one helper**, `PortfolixirWeb.DecimalInput`, and carries `class="num"`. Twelve
places in five surfaces use it: the booking drawer (quantity, price, fees,
taxes), its settlement block (amount, rate), the rule dialog (line, from, to),
Tax (the statement's figures, the amount of a Freistellungsauftrag) and the
set-balance dialog on Accounts & depots.

- **Shown in the page's locale, never grouped.** A German page shows a decimal
  comma (`1664,40`), an English page a point. The helper swaps the separator and
  nothing else: the caller owns the digits — a derived settlement amount keeps two
  places, a derived rate is rounded to six and trimmed, and a stored figure opens
  with its trailing zeros dropped (`45,6`, `12000`) and every other digit as
  stored. **Money fields are not padded** (the board's open point, decided here):
  a field is for editing, and a trailing zero carries nothing. **One exception,
  so a field never changes its form mid-edit: a field the drawer derives opens
  in the form its derivation writes.** The settlement amount opens at two places
  (`1664,40`, as a typed rate derives it), padded but never rounded — a stored
  `1664,4035` keeps its places; the rate needs nothing, since its derivation
  trims too (review round, 2026-09-25). What the operator typed renders back
  exactly as typed — a refusal never rewrites `2,5` into `2.5`.
- **No thousands separator in a field, ever.** Tables and running text keep
  grouping (`Format.decimal/3`, `1.664,40`): a figure there is read, not edited
  and read back. A field's value *is* read back, and a grouped `1.664` would
  return as 1.664.
- **Read strictly, never guessed.** The page's own separator is always the
  decimal separator. The other language's separator is one too — a German page
  accepts a typed `45.60`, an English page a pasted `45,60` — **unless the figure
  has the shape of a thousands group** (`1.664` on a German page, `1,664` on an
  English one): that figure reads two ways and is refused on its field with
  "is ambiguous: enter it without a thousands separator" /
  "ist mehrdeutig: ohne Tausendertrennzeichen eingeben". A figure with two
  separators (`1.664,40`) is refused the same way, and so is one grouped in
  threes with a space, a no-break, narrow no-break or thin space, or an
  apostrophe (`1 664,40`, `1'664.40` — the way a bank page or a PDF prints
  it), so the field names the fix rather than a bare "is invalid" (review
  round, 2026-09-25). An exponent, `NaN`, any other inner space or a trailing
  separator is invalid. A refused figure saves nothing.
- **A refusal does not reshape its row.** A label stacks its caption and
  control from the top (`label { align-content: start }`), so the error under
  one field of a paired row (quantity · price) leaves the other field at its
  own height; the grid row still grows, the neighbour's control does not
  (review round, 2026-09-25).
- **`input.num` joins the generic `.num` rule** — right-aligned, tabular
  numerals — which sits last in `app.css`, so it outranks the bare `input` rule by
  specificity and any scoped `… input` rule of equal specificity by source order.
  A more specific rule still wins (`.soll-table input[type="number"]`); none sets
  the alignment or the numerals against it today. An amount and a rate typed one
  under the other end on one edge, as they will in their column.
- **Out of the rule: browser number inputs** (`type="number"`: the plan editor's
  weights, the fixed-rate benchmark, the tax year, the split ratio, and the
  securities filter popover's value field, whose type follows the filtered
  field — `number` for a decimal or integer field; none of those is filterable
  today, so the popover renders none yet). Their
  `value` must carry a point whatever the page's language, and the browser draws
  their digits; the plan editor's are already right-aligned
  (`.soll-table input[type="number"]`).
- **Dates are not part of it.** A date field is the ISO text input of UX-DR19
  above (`YYYY-MM-DD` in every locale), and the date in the settlement
  block's source hint is fixed by the Amendment 2026-09-24 below (in the
  page's language since 2026-10-07); #869's two date bullets close as
  spec-conformant.

Pinned by `decimal_input_test.exs` (the rule, both locales, the ambiguous
shapes), `test/invariants/decimal_input_test.exs` (every decimal text input
carries `num`; no second comma rule in the web layer) and
`design_conformance_css_test.exs` (`input.num`).

### Inventory (as built)

- **App shell** (`.app-shell`) — fixed sidebar with grouped nav (`.nav-group`, uppercase group heads, icon + label rows), active link per {components.selected-nav}. The Classifications group is **one static entry** (`nav_groups/0`, `app_shell.ex:266-294`); the per-tree list and its `+` affordance live on `/classifications` itself — corrected 2026-08-05 against the build, per ADR-0024 (a tree is an entity, not a task). The sidebar background is viewport-height rather than page-height, leaving a cut edge on long pages — a defect. Nav entries follow ADR-0024: navigation reflects user tasks, not the storage model; a new entity does not get a sidebar entry by default.
- **Top bar** (`.topbar`) — burger toggle, brand, page title + subtitle, then theme menu, accent menu, EN/DE locale switcher (pill text ≥ 11px, pinned by the spacing-scale test).
- **Area tabs** (`.area-tabs`, `.detail-pane-tabs`) — the Wealth areas are Holdings · Allocation & targets · Cash flow · Snapshots · Tax; Cash flow's second level is Income · Realized gains · Deposits & withdrawals · Costs. Both levels per {components.selected-nav}.
- **Stat card** (`.stat`) — {components.stat-card}: three-color gradient hairline, uppercase label, 30px value. Signed values take semantic colour, not the accent (see Colors). Two tiers on the Wealth band since issue 797 — `.stat--lead` and `.stat--compact`, the currency as `.value-suffix`, a card's second figure as `.stat__sub` (Components → KPI band — two tiers).
- **Hero** — **retired 2026-08-05.** {components.hero} was specified for the four-metric-card Overview of the superseded UX-DR2. That rule now follows the build (EXPERIENCE.md UX-DR2): the Overview is value + change, "Off target" (UX-DR21), and data quality — plus the four-cell KPI strip since UX-DR2's 2026-09-14 amendment — and no hero component was ever built. The anatomy stays in the frontmatter as a record, unreferenced by any surface. [mockups/key-dashboard.html](mockups/key-dashboard.html) is downstream of the superseded rule and is **stale** — it illustrates a composition this document no longer specifies. Re-render or retire it before the mock is used as a reference again. (The spines-win-on-conflict clause is stated once, in EXPERIENCE.md → IA; it is not repeated here.)
- **"Needs attention" card** (`#dashboard-attention`) — {components.needs-attention-card}: heading, basis line, up to five drift rows, each a link into Wealth → Allocation & targets. The basis line ships in full (`data-role="attention-basis"` names the view, the plan and the tree beside the threshold clause, issue 673); since issue 798 each row also carries the decorative `.drift-bar` (Components → Drift bars). The empty case is a plain muted line (`data-role="all-clear"`), which is correct and stays.
- **Overview data quality** (`#dashboard-data-quality`) — {components.data-quality-line}: one line, only when N > 0, no all-clear badge, remedy link pre-filtered. Built as specified since issue 688 (re-verified 2026-09-15, issue 798); see Components → Data quality.
- **Wealth data quality** (`#portfolio-data-quality`) — one `AppShell.data_note` per finding at its own severity, in one status region `[data-role="dq-notes"]` that stacks them `--space-2` apart (issue 792; the gap since #1055); the unvalued-cash note names each account with its native balance (Components → Data quality).
- **Inline results** — {components.inline-result}: in-flow feedback beside its trigger, reusing the data-note severities, no timer. Replaces `.status-toast` and the `AutoDismissToast` hook (issue #566).
- **Connection state** — {components.connection-state}: one band under the top bar for a lost or reconnecting LiveView socket. Nothing is built and nothing is styled; LiveView 1.2.8 already applies the classes.
- **Tax budget meter** — {components.budget-meter}: track, accent fill, remaining amount, as-of basis line. Explicitly no threshold colouring.
- **Panel** (`.panel`) — generic elevated container, {components.panel}.
- **Data tables** (`.data-table`, `.detail-*-table`, `.drift-table`, `.cash-table`, `.soll-table`) — {components.data-table}. One header treatment: {typography.table-head} on {colors.bg-muted}; the sentence-case-no-rules variant is retired. Numeric columns are right-aligned with tabular numerals. *Shipped 2026-09-23 (Sprint 14, issue 833, board `ux-design-2026-09-20/04-num-and-focus`):* one generic rule — `th.num, td.num, .data-table thead th.num` — backs `class="num"` in every table, so income's money cells and the two Sprint 13 tables no longer carry the class with nothing behind it. It sits last in `app.css` on purpose: several tables reset `th, td` to `text-align: left` at the specificity of `th.num`, and only source order wins that tie; the third selector lifts the header over `.data-table thead th`. The per-table `.num` rules predate it and agree with it. Pinned by `design_conformance_css_test.exs`.
- **Charts** — one shared component (`security_chart.ex`, ADR-0022) used at two call sites (`portfolio_live.ex:1700`, `securities_live.ex:630`), plus **four** hand-rolled implementations still in the build: the allocation sunburst (`portfolio_live.ex:1790`), the snapshot two-polyline comparison (`snapshots_live.ex:440`), and the Income surface's **two** separate bar charts (`income_live.ex:108` annual, `:203` per-month). {components.chart-frame}: accent quote line (1.6px) over the 0.14-opacity accent fill, moving-average overlays, cost-basis line, **buy/sell markers that must be shape-coded and are not** (▲ buy {colors.tx-buy}, ▼ sell {colors.tx-sell} is the requirement; `security_chart.ex:129-136` renders one `<circle r="4">` for both types and `app.css:3126-3132` changes only `fill`, so the built markers are hue-only — issue #645, filed under Colors → Violations), mono axis text, crosshair + {components.chart-tooltip} via the `ChartCrosshair` hook. New chart work uses the shared component; the snapshot comparison inherits its axes, crosshair and data-as-table disclosure when it moves over — but not a period control, whose domain is fixed by the snapshot's as-of date.
- **Allocation visuals** — donut and sunburst SVGs with legends (`.donut`, `.sunburst-seg`), drift tables with category swatches, display-only rebalancing hints (`.rebalance-hint`, ADR-0023 — an annotation, never an action).
- **Tax budget** (`.tax-budget`) — {components.budget-meter}: allowance-order utilization per institution as a fill level with the remaining amount and its as-of date, **no threshold colouring**; recorded statements below as a list, each carrying its consistency finding as a {components.data-note} severity. Entry forms behind a disclosure; the permanent prose paragraphs become ⓘ tooltips (enumerated in EXPERIENCE.md → Alignment inventory → UX-DR11).
- **Forms** — stacked label-over-input grids ({components.input}); buttons are quiet elevated rectangles ({components.button}) with `.button-primary` / `.button-danger` variants. **One primary action treatment:** solid filled button; the outline button is the secondary; invisible grey inline text is not an action treatment. Forms sit behind disclosure, not in the primary sightline. Per-account actions live in their row: **the global cash-balance form is `form.inline-form.balance-form` on Wealth — Holdings (`portfolio_live.ex:1509-1531`), not on Accounts & depots** — see EXPERIENCE.md → Component Patterns → Cash accounts for what moves where.
- **Feedback** — {components.data-note} replaces `.alert-error` / `.alert-success` / `.alert-warning` / `.alert-info` / `.hint` / the dq chips. `.empty-state` wells stay. {components.inline-result} replaces toasts (`.status-toast` and the `AutoDismissToast` hook, issue #566).
- **Overlays** — `.modal` + backdrop, `.popover` for column pickers and filters, `.row-context-menu` (kebab menu, bottom sheet under 720px). **The requirement is a native `<dialog>` opened with `showModal()`, focus-trapped and inert-backed (UX-DR9).** *Built, and this bullet is the record of it (corrected 2026-09-15, Sprint 12):* `lib/portfolixir_web/` now contains **nine** `<dialog>` elements and **zero** `aria-modal` attributes. Every modal runs on the `ModalDialog` hook, so the focus trap, the inert backdrop and Esc come from the platform; the securities detail `<aside class="detail-pane">` carries no modality attribute at all (issue #646), which is what the original correction asked for. The two bottom sheets issues 800 and 803 added — the securities filter sheet and the booking drawer — are the same `<dialog>`, the drawer opened non-modally above 720 px through `data-sheet-below` so the history behind it stays readable. The reason the original diagnosis gave still binds: `aria-modal="true"` without containment is worse than omitting it, because the screen reader confines its virtual cursor to the dialog while `Tab` keeps walking the page behind it.
  **Column pickers take `.popover`, at every level (decided 2026-09-23, Sprint 14 plan D-4, pick E3; board `ux-design-2026-09-20/03-column-picker`; issue #835).** The treatment is the one `PortfolixirWeb.Securities.ColumnPicker` implements: `.popover.column-picker` with `role="dialog"` and an `aria-label`, a `.popover-head` heading, and the columns grouped in `<fieldset>`/`<legend>` — at fourteen columns a flat list is a search task, and the grouping is the difference that matters. There is **no** section-level/toolbar-level split: a picker is a popover whether it sits on a toolbar or at the head of a section. The two `<details>` pickers with a flat checkbox list — the transaction history's `#tx-column-picker` and Wealth Positions' `#holdings-column-picker` — are the **non-conforming side**, recorded here as drift rather than as a second sanctioned treatment; the spec was deliberately not amended to match them, because under ADR-0038 the spec is what the design-critic review holds work against, and amending it because two surfaces diverged would invert that. Their convergence is filed as its own issue and built later: it needs the component moved out of the `Securities` namespace into a shared one first, and two surfaces rebuilt on it. Until it lands, a new column picker is built on `.popover`, never on `<details>`. **Built (issue 850, Sprint 15):** `PortfolixirWeb.ColumnPicker` is the one component — `picker/1` renders the popover from `[{legend, [{value, label}]}]` groups, `toggle/1` the labelled trigger (columns glyph plus the word, `aria-expanded`; open, it carries the board's accent state — accent border and text, bold — as `.is-active`); the popover closes from its × and on Escape, and closing returns the focus to the toggle. All three pickers render it: securities (icon trigger on its toolbar), the transaction history (a toggle bar right-aligned above the table, groups Booking · Amounts · Other) and Wealth Positions (the toggle in the section head, which the `<details>` could not use because opening it re-centred the heading; groups Position · Identifiers · Valuation). A test fails the build on a `<details>` column picker anywhere in the web layer.
- **Import surfaces** — drop zone, progress, stat cards, notes.
- **Drag-and-drop rows** (`.dnd-row`, `.dnd-dropzone`, classifications tree) — selection per {components.selected-row}.
- **Chips** — one chip: {components.chip}, a filled tag. The outline chip and the grey initial-avatar square are separate things wearing the chip's clothes; the avatar is a logo placeholder (`.security-logo--initial`) and reads as one.
- **Chart tooltip** ({components.chart-tooltip}) — the crosshair readout, mono type on {colors.bg} in a {rounded.sm} bordered box, positioned by the `ChartCrosshair` hook. One tooltip for every chart surface; a chart that invents its own readout is drift.
- **ⓘ tooltips** (`details.metric-tooltip`) — a native `<details>` whose `summary` is the ⓘ and whose `p[role="tooltip"]` holds the explanation (UX-DR11); pinned to a stat card's corner by default, in the text flow as `.metric-tooltip--inline`. The summary is a 1.25 rem circle, 1.75 rem under `pointer: coarse`. **The labelled pill** (`.metric-tooltip--labelled`, issue 790): a summary that carries a label beside the ⓘ — "ⓘ Kurs- & Währungsbeitrag" on the security's Trades and Holdings tabs, "ⓘ Bruttogewinn" over the sell form's FIFO lot preview ("Lots consumed by this sale") — grows with its text into a {rounded.full} pill (`width: auto`, `white-space: nowrap`). *Amended 2026-10-07 (issue 1059, Sprint 19 PR γ U2; board `mockups/ux-design-2026-10-04/04-trades`, rule ④):* all three pills keep that size under a coarse pointer too — `width: auto; height: auto` with the coarse circle's 1.75 rem as its minimum height, in the coarse block right after the circle's rule, which has the same specificity. Before, the circle rule won on a touch screen: the 189 px label overflowed a 28 px circle on both sides, and at the pane's left edge its first ~50 px fell off the screen. The coarse circle's 28 px stays below UX-DR6's 44 px floor; that is the floor's own repair, not this one. *Amended 2026-10-07 (Sprint 19 PR γ U5; board `mockups/ux-design-2026-10-04/04-trades`, found while drawing 3):* that repair is made — under `pointer: coarse` every ⓘ summary, circle and pill alike, carries a transparent ring (`::before`, `inset: -9px`, placed from the 26 px padding box inside the 1 px border), so its target is 44 px (26 + 2 × 9) while its picture stays the 28 px circle or the pill (Amendment 2026-10-07 — The touch, focus and colour floor, second pass).
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
| Render dates ISO in inputs, and a shown date in the page's language through `Format.date` (amended 2026-10-07) | Let the browser locale decide the input format, or print `Date.to_iso8601` where a date is only shown |
| Give every wide block its own `overflow-x` container and `min-width: 0` | Rely on the page to scroll — `.workspace-page` clips |
| Make pending, settling, final and not-computable four distinct appearances | Render "loading" and "cannot be computed" as two similar glyphs |
| Keep the 13px density base and weight-driven hierarchy | Inflate font sizes to fake hierarchy |
| Resolve every heading to h1/h2/h3 on the ramp | Write a bespoke heading size |
| Use the spacing scale for every margin, padding and gap | Reintroduce ad-hoc px or rem spacing |
| Tabular numerals + mono for data, Inter for prose — including mid-count-up | Proportional digits in money columns |
| Soft, large-blur shadows ({components.panel}) for elevation | Hard drop shadows, or any shadow inside a table |
| Define every new token in both themes | Light-only tokens ({colors.warning-soft} is the live example) |
| Give every control a visible 2px focus outline | `outline: none` with a background change as the substitute |
| Name every row kebab for its row — "Actions for Nordic Timber Holdings AB", a booking by kind, subject and date — through the one trigger, `AppShell.row_kebab/1` (issue 870) | Give every kebab on a page the same name, or draw a kebab of a surface's own |
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
| app.css:2122-2127 | `.row-actions__kebab` | **shipped 2026-09-23** (Sprint 14, issue 834): the 2px accent outline at a 2px offset on `:focus-visible`, hover keeps the background |
| app.css:2160-2164 | `.row-context-menu__item` | **shipped 2026-09-23** (Sprint 14, issue 834): the 2px accent outline at a 2px offset on `:focus-visible`, hover keeps the background |

**Not one of the eight is justified in place.** A hover background is a hover treatment; reusing it for focus means focus and hover are indistinguishable and neither is guaranteed 3:1 against its container. The correction is one shared `:focus-visible` rule carrying the 2px accent outline, not eight reinstatements — and it must land with a `outline-offset` of at least 2px wherever the focused element's own fill is the accent ({components.selected-segment}`.option-active`, the active tab underline), or the outline abuts its own colour at 1:1.

**Two further rules set `outline: none` unconditionally, not only on `:focus-visible`** — strictly worse, because the control then has no focus indicator in any state:

- `.search-field input` (app.css:1389-1397);
- `.securities-detail-splitter` (app.css:2050-2058) — which carries `tabindex="0"` and `role="separator"` (`securities_live.ex:348-356`), so it is a keyboard-operable control with no visible focus at all, and whose only focus signal today is its handle turning accent-coloured, which is colour-only and fails UX-DR7 as well.

**And four controls have no `:focus-visible` rule whatsoever** — `.segmented-control__option`, `.range-button`, `.chart-toggle`, `.period-buttons .button-mini` — falling back to the UA ring. Those four are exactly the classes {components.selected-segment} consolidates, so the aligned component arrives carrying the focus rule or the alignment story has silently made focus worse. *Amended 2026-10-07 (Sprint 19 PR γ U5, board `mockups/ux-design-2026-10-04/07-floor`):* `.range-button` draws the ring inset (`outline-offset: -2px`, its group clips) and `.chart-toggle` at the 2 px offset; so do the button family and `.icon-button` (Amendment 2026-10-07 — The touch, focus and colour floor, second pass). `.period-buttons .button-mini` still has none. `.area-tab` (app.css:4347-4350) and `.positions-toggle` (4376-4379) indicate focus by a text-colour change only, which is the same colour-only failure as the splitter.

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

## Amendment 2026-08-18 — appearance for the #707 engagement

The rules, the reasoning and the two new rule numbers (UX-DR21, UX-DR22) are in
`EXPERIENCE.md` → **Amendment 2026-08-18**. This section carries only what a
thing looks like, on the same split every component here follows.

### Filter chips — `{components.filter-chip}` *(D2)*

The common filters become one-tap chips above the securities table; the
Column/Operator/Value builder is demoted behind a **"More filters"** control.

**Inheritance, deliberately total: the chip IS `{components.selected-segment}`
with one changed affordance.** The view switcher's `.view-chip` already
establishes the pill in this language — radius `999px`, `{typography.control-label}`,
`{colors.bg-muted}` at rest, `{colors.accent-soft}` with `{colors.accent}` text
when active. A filter chip reuses all of it and changes exactly one thing: it is
a **toggle**, so it carries `aria-pressed` rather than `aria-current`, and its
active state must survive `forced-colors: active` on the border channel rather
than on the tint (UX-DR7). No new colour, no new radius, no new type size.

- **Rest:** `{colors.bg-muted}` fill, `{colors.text-muted}` label, 1px
  `{colors.border}`.
- **Active:** `{colors.accent-soft}` fill, `{colors.accent}` label, 1px
  `{colors.accent}` border. The border is what carries the state under forced
  colors; the tint is reinforcement.
- **Family chips** (Currency, Asset class) render their value in the label —
  "EUR", "Aktie" — never a bare family name with a hidden selection.
- **Touch:** `{spacing.touch-target}` floor under `pointer: coarse` (UX-DR6),
  like every other chip family.
- **The row owns its scroller** (UX-DR15): horizontal overflow, scroll-snap, edge
  fade — the same mechanism as the tab row below, and for the same reason.
- **"More filters"** is a quiet text control at the end of the row, not a chip:
  it opens the existing builder popover and must not read as a tenth filter.
  It carries the funnel `:filter` glyph, which by the 2026-08-05 naming decision
  belongs to exactly this control.
- **Count:** when the builder holds conditions the chips cannot express, "More
  filters" carries a count badge, so demoting the builder never hides active
  state. A demoted control that hides state is a worse defect than the one this
  replaces.

### Plan sum: the remainder row and the retired pill *(D3)*

- **The `Σ-Konflikt` `<summary>` pill inside the category-name cell is retired.**
  A finding rendered inside a data cell is a category error: findings are
  `{components.data-note}` rows at one of three severities (UX-DR17). Over-100 %
  sums and position-vs-category conflicts render as a data note **above** the
  table, at `attention` and `problem` respectively.
- **The unallocated remainder is a table row**, not a warning: same row rhythm as
  a category row, label in `{colors.text-muted}` to mark it as derived rather
  than stated, its percentage in the same tabular-numeral slot as every other
  weight. It is the last row, and it is not selectable or editable — it is
  arithmetic.
- Under-100 % therefore has **no warning colour anywhere on the surface.** That
  is the visible half of ADR-0040: a deliberate choice must not render like a
  mistake.

*Built for the allocation's basis line and its Positions list by issue 875
(Sprint 16, board `ux-design-2026-09-24/09-allocation-positions`,
before/after):*

- **The Σ in the basis line** carries the warning colour only **above** 100 %
  (ADR-0040 §3, the overshoot the data note above the table names). A plan that
  allocates less gains the clause **"— drift against the allocated portion"**
  (de "— Abweichung gegen den verteilten Anteil") exactly when the payload's
  `drift_basis` is `allocated_portion` (ADR-0040 §2): the Σ in front of it *is*
  that portion, so the number is not repeated. A plan at 0 % on top with targets
  deeper in the tree keeps its own clause and no colour.
- **A rebalancing hint that rounds to nothing is not shown** — "Sell ≈ 0.00
  units" asks for nothing. The worklist's Drift cell shows the drift alone
  (since issue 911 the hint sits in that cell, under the figure) and the tree
  shows no hint; the drift stays, and the API keeps the unrounded quantity.
- **The hint's verb track is `max-content`** (`.rebalance-hint`), so "Verkauf"
  fits; the ≈, quantity and unit tracks keep their widths, the grid packs to the
  end, and the ≈ stays on one vertical line.
- **The cash row's category reads "—"**, never "Unassigned": cash has its own
  target and drift, and "Unassigned" names the tree's other row. A held security
  filed nowhere keeps the word.
- **Tree / Positions is the segmented group** (`.segmented-control`, UX-DR16
  class 2): the active option filled, the pair a real toggle to the eye and not
  only to `aria-pressed`.

### View switcher: prefix removed, manage control named *(D4)*

- The visible `View:` / `Ansicht:` prefix is **removed**. The group keeps its
  `aria-label`, so the accessible name is unchanged; the row's leading element
  becomes the first chip.
- `Manage…` / `Verwalten…` becomes **`Views`** with the `:settings` glyph, styled
  as a quiet link at the end of the row — not a button, because it navigates.
  **The ellipsis goes**: in this app's own convention a trailing ellipsis means
  "opens a dialog for further input", and this is a navigation to `/buckets`.

### Custom range: the disclosure keeps its shape, its contents change *(D5)*

`{components.period-control}`'s "Custom range" stays a disclosure. Inside it:

- a **labelled from/to pair** as `{components.native-control}`, ISO-formatted
  (UX-DR19), each with a real `<label>` — not two anonymous fields sharing one
  caption;
- **validation on the range itself** (`from` ≤ `to`), reported against the field
  that can fix it (UX-DR13), never as a silently empty chart;
- when applied, the segmented group gains a **custom chip** carrying the resolved
  dates in `{typography.control-label}`, in the same active treatment as a
  preset token. Today a custom range leaves the group with nothing selected, so
  the control cannot answer the only question it exists to answer.

*Amended by issue 801 (C5-A, 2026-09-15):* the disclosure keeps its shape and
its contents, but its body no longer sits in the flow — it is a popover on the
trigger (see "Custom range popover" below), so opening it moves neither the
section heading nor the chart.

### Tab row overflow — the shipped form is the specification *(D6, UX-DR22)*

Shipped as #702; recorded here so every tab row is held to it.

- `overflow-x: auto`, `overflow-y: hidden`; tabs keep their intrinsic width
  (`flex: none`) so overflow is real overflow rather than compressed labels;
- `scroll-snap-type: x proximity` with `scroll-snap-align: start` on each tab, so
  a tab never comes to rest half-cut — being half-cut is what made the fourth
  Wealth tab read as the last one;
- a **right-edge fade** as the affordance, one-sided on purpose: a symmetric fade
  dims the first tab at desktop width, where there is no overflow to signal;
- **the active tab is in view on arrival** *(issue 857, board 04 of the
  2026-09-23 pass)*: the `AreaTabs` hook scrolls the `aria-current` tab into the
  row's view on mount — the row, never the page; no animation under
  `prefers-reduced-motion` — and marks the edges the row rests on
  (`data-scroll-start`, `data-scroll-end`). **The fades follow the edges, not a
  fixed side:** away from the start a 24 px left fade says tabs lie before;
  at the end the right fade goes, because on Risk the last tab *is* the active
  one and a fixed right fade would cover it; a row resting on both edges (no
  overflow, desktop) carries no mask. Without script the row keeps the
  one-sided right fade above. **The detail pane's row is held to the same
  clause** *(Sprint 18 U5, issue 1033, board `ux-design-2026-10-02/07-phone-390`
  H7.2)*: its `DetailTabs` hook carries the same mount half for the
  `aria-selected` tab, `.detail-pane-tabs` joins the three edge rules, and the
  server renders the row with `data-scroll-start`, so its first paint, before
  the hook runs, carries only the right fade;
- **the row's end is a tab boundary** *(issue 876, pick G10 = A of board
  `ux-design-2026-09-24/10-area-tab-end`)*: when the row overflows, the
  `AreaTabs` hook gives it a trailing inset (`padding-inline-end` from
  `--area-tabs-tail`, 0 by default on `.area-tabs`) as wide as the distance
  from its maximum scroll to the next tab start, and brings the active tab to
  rest on the last tab start at or before its centring target at which it is
  whole (else the first after); a row that does not overflow gets no inset. The
  browser clamps a target past the maximum scroll, and the maximum scroll lay
  mid-tab, which is how Tax and Risk rested with a fragment of "Cashflow" under
  the left fade. The inset is re-measured on resize and restored after a patch,
  like the edge marks; its cost is a little empty space after the last tab at
  the row's end. Measured in Chromium at 390 px: every Wealth page rests with a
  whole tab at the left, on arrival and when swiped to the end. The detail
  pane's row takes the same inset from `--detail-tabs-tail` (Sprint 18, H7.2);
- **the row's container has a zero floor** *(2026-10-07, issue 1063, Sprint
  19 PR γ U4; board `mockups/ux-design-2026-10-04/06-phone-wealth`, rule
  ⑤)*: a row scrolls inside itself only if no ancestor grows to its
  min-content. The securities split workspace
  (`.securities-workspace--split`) is a grid whose one column was an
  implicit `auto`, so the detail pane's min-content — its nine `flex: none`
  tabs, about 760 px — set the column's floor, and with the pane open at
  768 px the page measured 785 px, a 17 px sideways scroll. The column is
  now `grid-template-columns: minmax(0, 1fr)`: the page is the window, and
  the tab row scrolls inside itself with its fade. A grid or flex ancestor
  of a tab row gives it the same zero floor. *Amended 2026-10-07 (issue
  1063 on the chart tab, the U3 review; board
  `mockups/ux-design-2026-10-04/06b-chart-toggles-768`, before / after):*
  the chart tab's toggle row (`.chart-toggles`) wraps at every width, not
  only in the 720 px phone block — its ten German toggles kept one line
  wider than the pane and the page scrolled 239 px sideways at 768 px, 203
  at 1024 and 27 at 1200. *Amended 2026-10-07 (issue 1063 in the detail
  head, the closing act's edge-case finding 6):* a stored name with no
  break opportunity was the detail head's min-content, so the page scrolled
  sideways and the pane's Edit, Split, fullscreen and close buttons went
  off the screen — a 74-letter synthetic name measured 629 px of sideways
  scroll at 390, 253 at 768 and 217 at 1024. The head's `h2` takes
  `overflow-wrap: anywhere`: the name breaks mid-word only when nothing
  else fits, and its min-content drops with it (`break-word` would not).
  The title block keeps its min-content floor — a `min-width: 0` there was
  measured and left out, because it let the ISIN line run past its column
  toward the buttons. After: no sideways scroll at 320, 390, 768, 1024 and
  1200, every button on the screen, and a name that breaks at spaces wraps
  exactly as before;
- **no scrollbar** — a phone renders none anyway, and the fade plus snap carry
  it; keyboard users reach off-screen tabs by tabbing, which scrolls them in;
- **the baseline is an inset box-shadow, not `border-bottom`.** This is the
  non-obvious constraint and it is recorded so a later refactor does not undo it:
  `overflow-x: auto` computes `overflow-y` to `auto`, and the active tab's
  `margin-bottom: -1px` — which exists so its 2px underline paints over the 1px
  baseline — then either raises a vertical scrollbar or, under
  `overflow-y: hidden`, is clipped at the padding box so the underline renders
  1px thin with grey beneath it. An inset shadow paints on the padding box below
  the children, so the overlap survives and nothing overflows vertically.
- **No tab row wraps, and none collapses into the burger** (UX-DR22).

**Which tab row is a tab widget, and its keyboard contract** *(issue 837,
Sprint 14 plan D-3, pick E4-A, 2026-09-23; board
`ux-design-2026-09-20/05-detail-tablist`).* The two tab rows are different
objects and are marked differently on purpose. `.area-tabs` is navigation —
`<a href>` inside a `<nav>` with `aria-current="page"` — and carries **no**
`tablist` role. `.detail-pane-tabs` switches panels inside one pane and
changes no route, so it **is** a tab widget and carries the full pattern:

- `role="tablist"` on the row, `role="tab"` on each `<button>`, and
  `aria-selected` as the strings `"true"`/`"false"`;
- a **roving tabindex** — `tabindex="0"` on the selected tab, `"-1"` on the
  rest — so the row is one tab stop, not nine;
- **Arrow Left/Right** move to the previous/next tab and wrap at the ends,
  **Home/End** jump to the first/last (the `DetailTabs` hook in
  `layout_view.ex`); activation is automatic — the focused tab is selected,
  so the stop and the selection never disagree after the server patch;
- **`aria-controls` only on the selected tab**, because a panel is in the DOM
  only while its tab is active and an `aria-controls` naming an absent id is
  invalid markup;
- the 2px accent focus ring, inset (`outline-offset: -6px`) because the row
  clips vertically, which also keeps a 2px gap above the active tab's own
  accent underline.

A new row that switches panels without changing the route takes this
contract; a row of links takes `aria-current` and no role. Dropping the role
(variant B) was rejected: it would announce nine unrelated buttons and make
the app's two tab rows disagree about what a tab row is.

**The rule: a new tab row is added to the sweep in the same commit that adds
it.** The five declarations above are what a reader has to be told; what a
diff has to be held to is that no tab row exists outside
`css_layout_sweep_test.exs`, which today enumerates `.area-tabs` and
`.detail-pane-tabs` by name and will enumerate the next one only if someone
puts it there. `.detail-pane-tabs` is why the rule is written this way: it
carried `overflow-x: auto` and the forbidden `border-bottom` and none of the
rest until issue 817, and it is the row *most* likely to overflow — the
primary navigation of a reading surface in a pane whose default width is
roughly 360 px. The sweep now asserts the five declarations and the absence
of the `border-bottom` on it as well as the fade on `.area-tabs`, so a later
refactor cannot quietly undo the non-obvious clause.

### Transactions — the target vocabulary *(Part 4)*

`transaction_management_live.ex` predates this language. It adopts, with no new
components invented for it:

- the **workspace layout** (`workspace-section` blocks, top-bar title, no nested
  panel chrome) that every other area already uses;
- the booking form as **one `{components.panel}`**, its fields as
  `{components.native-control}` — since issue 803 that panel is the
  **booking drawer** (Components → Booking drawer): opened from the history's
  head, a bottom sheet under 720 px;
- the history as a **data table** with the D2 chip row above it — the same chips,
  so the filter vocabulary is learned once and applies in two places;
- **no view switcher** (see EXPERIENCE.md for why); the depot select is the
  control that determines where a booking lands, and it is labelled as such.

**The history's heads, columns and figures** *(2026-10-07, issues 1083, 1084,
1073 and 1090's history item, Sprint 19 PR γ U1; board
`mockups/ux-design-2026-10-04/03-history`, picks J3 A and J3.2 A; plan D-4)*:

- **The subtitle names the scope** (EXPERIENCE.md: a surface states its scope
  in its subtitle or basis line): "Alle Buchungen über alle Konten und
  Depots" (English "Every booking across accounts and depots"). "Manuelles
  Kauf- und Verkaufsjournal" stood over a history of every kind. Under 560 px
  the subtitle is hidden, as every page's is.
- **A month head carries the count alone**: the month, then "6
  Transaktionen" (`.tx-group-month`, `.tx-group-subtotal`), in the table's
  `tr.tx-group-head` and the phone list's `li.phone-rows__group` alike. It
  used to add every row's gross amount per currency, unsigned and whatever
  its kind — buys the rows show as "-", deposits, sales and a "Saldo
  gesetzt" level — into a figure that was neither a cash flow nor a turnover.
  The sums per kind and currency are the filter summary's, directly above,
  under its basis line; a signed net head (J3 B) waits for correct row signs
  and sign colour on every row (`:518`, `:706`), and turnover by kind (J3 C)
  would repeat the summary without its basis. H2's "the month subtotal
  follows" a deleted row stays true: the count follows.
- **The default columns are Datum · Typ · Wertpapier · Konto · Stückzahl ·
  Preis · Betrag.** "Konto" (msgid "Account", the chip family's word) is the
  `account` key, in the picker's "Buchung" group; like every picker column it
  is the human half of API fields (issue 732): `cash_account_id`, a
  transfer's `counter_cash_account_id`, else `securities_account_id` and a
  security transfer's `counter_securities_account_id`. The cell names the
  cash account the Betrag moved through — the Betrag is that account's
  view; a cash transfer reads "Demo Cash → Tagesgeld", sender first; a
  security transfer names both of its depots the same way, "Depot 1 →
  Depot 2", as the delete dialog's box does; a booking with no cash account
  (a delivery) names its depot; a split names none and the cell stays
  empty, as Wertpapier does for a booking with no security. A receiving
  account or depot the page's lists do not carry is left out, never named
  by id. Plain text like Wertpapier, each stored name in its own `<bdi>`
  (H8.8), the " → " outside them. A reader with a stored column choice
  (ColumnPrefs) keeps it — a choice without `account` renders without
  Konto — and finds "Konto" unticked in the picker. The phone row stays the
  table condensed (UX-DR27), its subject the security, else the Konto
  cell's names: the cash account, a cash transfer's both ("Demo Cash →
  Tagesgeld", each in its own `<bdi>`, the line one inline span), else the
  depot — so a transfer that reads as arriving in the receiver's view still
  names where the money came from (the story's review). One deliberate
  difference: the delete dialog's box names a buy's depot (R10f, the
  account its sentence names); the column names the account the money
  moved through.
- **The table fits its wrapper** (the story's review): a reading table, not
  a matrix — the Risk tables' fit pattern (`.risk-fit-table`) at every
  width. `.data-table-wrapper > #transaction-list { min-width: 0; width:
  100% }` opts out of the scroller's `min-width: max-content`; the
  Wertpapier and Konto cells (`.cell-name`) wrap between words, at least
  12ch wide, `overflow-wrap: break-word` with `hyphens: auto` — the
  contribution table's name rule (R4), never `anywhere`; the date
  (`.cell-date`) and the kind (`.cell-kind`) stay on one line; the figures
  keep `.num`'s `nowrap` and alignment. Before it, the default Konto column
  took the table past its wrapper at 1200 px (1092 px of table in a 922 px
  scroller on the demo seed; 1223 px with a 60-character name and a
  transfer), Preis and Betrag out of view with no cue; after it, 922/922
  with every column in view. UX-DR15's scroller stays the fallback where
  the eight columns' floor is wider than the wrapper (about 780 px: 1024 px
  with the sidebar open, 768 px).
- **A transfer's sign is the account in view's.** With the account chips
  selecting a transfer's receiving account and not its sender, the row reads
  the money arriving ("200,00", as the running balance beside it rises by
  200), on the phone row and in the delete dialog's box too; otherwise it
  reads from the sender ("-200,00"), the account the Konto cell names first.
  Positive amounts still carry no "+" and history rows no sign colour; that
  gap against the Accessibility Floor is its own story.
- **The price keeps its stored digits**: the Price column and the phone
  row's size ("12 × 41,1234") print a price as the notes drawer prints a
  stored figure (R10c) — every stored digit, trailing zeros trimmed, at
  least two places: 41,1234 and 93,1046 as stored, 24 as 24,00. They used to
  round to two places; the delete dialog's box reads the same size.
  *Amended 2026-10-07 (the PR γ closing act, edge-case hunter #2):* every
  stored digit **up to four decimal places**. The PP JSON importer derives a
  price as amount ÷ shares at the column's scale 6, so 1.234,56 EUR for 17
  shares was stored as 72,621176 and printed six digits of rounding residue
  beside the "72,62" of the security's Transaktionen tab. It now reads
  72,6212 in the history, the phone row ("17 × 72,6212") and the delete
  dialog's box, and the Transaktionen tab's Preis column follows the same
  rule, so one booking reads the same on both surfaces. 41,1234, 93,1046 and
  24,00 are unchanged. *Amended again 2026-10-07 (the closing act's cascade,
  layer 2):* the four-place cap printed a price under 0,00005 as zero — a
  stored 0,000045 read "0,0000", in the history, the phone row
  ("1.000.000 × 0,0000") and on the Transaktionen tab — and cut any price
  under 1 to fewer digits than it carries (0,001234 read "0,0012"). **A
  price under 1 keeps at least three significant digits:** its stored
  digits up to two places past its first non-zero one, and never fewer than
  four places, so 0,000045 reads 0,000045 and 0,001234 reads 0,00123. A
  price of 1 or more keeps the four-place cap. No non-zero price prints as
  zero.
- **`.phone-row__ids` breaks anywhere** (`overflow-wrap: anywhere`): a stored
  name with no break opportunity wraps inside its phone row instead of
  running over the figures and off a 390 px screen. Its text is the flex
  container's anonymous item, whose min-content width then shrinks to a
  glyph — the delete dialog's R8 fix, on the class. The rule is on the
  class, so it holds for **every phone list** that carries the line, not
  only Transactions: the securities list, a security's Trades and Quotes
  tabs, Realized trades on Income, the contribution rows, the merge records
  on Accounts & depots, and the delete dialog's box (which keeps its own
  rule on its one inner span as well).

## Amendment 2026-08-22 — the computing cue marks the seconds class (#723)

The #711 activation measurement (recorded in ADR-0039's 2026-08-18 amendment)
split the "computing cues across the app" report into two causes: the daily
performance walks cost **seconds** (~9.5 s at 200 securities / 4,000
bookings), while everything else a surface waits on is **20–400 ms** — those
figures showed a cue not because they are slow but because `start_async`
renders a placeholder while they load. The cue was the loading pattern, not
the cost.

**Decided (designer): the spinner-and-"computing" cue is reserved for work in
the seconds class — today, only the walks.** A sub-second figure still loads
asynchronously (the first frame must never block on a read), but its
placeholder is the **silent block or value skeleton** (UX-DR20) with
`aria-busy` and no cue: at that latency the cue cannot be read before it is
replaced, so it only registers as flicker.

Concretely, per surface:

- **Wealth header** — the valuation slots (total, cash quote) wait silently
  (`data-waits="valuation"`); the TTWROR/period slots keep the cue
  (`data-waits="performance"`).
- **Wealth performance chart** — keeps the cue (it waits on the walk).
- **Wealth allocation table and cash section** — silent skeletons.
- **Dashboard "Off target" card** — silent skeleton. (Its report is
  allocation-class; that its arrival can today be delayed by sharing one
  async task with the walk-backed value card is a loading-architecture
  observation, not a cue question — noted, not reshaped here.)
- **ADR-0032 §6 stale-serve labels** ("recomputing" beside a served stale
  figure) are untouched: they label a VISIBLE value's freshness, which is a
  different statement than a placeholder.

Pinned by `portfolio_live_test.exs` ("the computing cue marks the seconds
class only") over the deterministic dead render.

## Amendment 2026-08-22 — the facet family and its two notices (issues 724, 725, 726)

The Cash-flow area went from one facet to four in one batch. Two of the
shapes that came out of it are area-agnostic and belong here rather than in
one LiveView; the third is a note about which component the facets use.

### Facet navigation uses the segmented control, not a second tab level

A facet is a **`?tab=` URL** (`/cashflow?tab=realized`), rendered as `patch`
links inside a `segmented-control` marked `data-role="cashflow-facets"`, with
`aria-current` on the active one. Links, not client state: a facet a reader
can send to someone, bookmark and reload is worth more than one that
animates.

The segmented control rather than a second tab row, because the four facets
are **four framings of one area's data**, which is what UX-DR16 class 2
already describes — the same relationship the period control has to a chart.
A second tab *level* would claim these are sub-destinations of the Cash-flow
page; they are alternative readings of it. `/portfolio?tab=allocation` uses
first-level area tabs for a genuinely different information architecture and
is not the precedent here.

**A row of one facet does not render.** A single option answers no question
and reads as a promise of siblings that may never arrive.

### UX-DR25 (new) — an excluded row is named where the total is read

When an aggregate cannot include a row, the surface states **how many** and
**which** — beside the figure, not in a tooltip and not only in the payload.
This generalises the excluded-and-named shape of ADR-0041 into an appearance
rule, because Sprint 8 built it three times: a sale with no rate for its
close date, a flow with none for its booking date, a cost with none for its.
The component is the `attention` data note (UX-DR17), so the severity says
"your figure is incomplete", not "something is broken".

Three clauses:

1. **The count and the identifying names both render.** A count alone tells a
   reader something is missing without saying what; names alone hide the size
   of the gap.
2. **The excluded row keeps its native figure and never shows a converted
   one.** Printing the native number in a base-currency column is the
   currency-mixing the exclusion exists to prevent.
3. **No call to action that cannot act.** The realized-gains note carries no
   link. Rate sync fetches the ECB *daily* feed, so it cannot fill a past
   booking date, and there is no path today for entering a historical rate by
   hand (issue #737) — so the note says that instead. A control that would
   not help converts a stated limit into a failed attempt, which is worse
   than no control. The note said "Store the missing exchange rates." and
   pointed at a page with no rate control at all until this batch removed it.

### UX-DR26 (new) — a deliberate limit is stated on the surface that lacks it

Where a surface stops short **by decision**, it says so where a reader would
otherwise look for the missing part. The Costs facet's composition line ends
with the sentence that it stays at overview level on purpose, with no
per-security or per-transaction breakdown (issue #726's requirement, where
the "only" *is* the requirement). Without it the facet reads as unfinished,
and the next reader — human or agent — offers to finish it.

The same clause covers a **stated difference** between two figures a reader
could otherwise reconcile by subtracting.

**Built state.** Both rules ship across the three new facets. The rules are
written to be surface-agnostic; nothing outside the Cash-flow area has been
audited against them yet, which is a named remainder rather than a claim of
completeness.

## Amendment 2026-08-22 — the subject column stays reachable (#730)

The Sprint 7 walkthrough at 390 px found both wide tables putting the figure
the operator just asked for at the far right of their own scroller: narrowing
to one account summons the history's **Saldo** column as the seventh of
seven; picking a drift chip narrows rows by **Drift**, the last column.
Containment was correct (each table owns its scroller, UX-DR15); priority
was not.

**Decided (designer): a surface's SUBJECT column — the one the surface's
interaction is about — pins to the right edge of its own scroller**
(`.col-subject`: `position: sticky; right: 0`, opaque background, a border
for the seam). The middle columns scroll beneath it, so the summoned figure
is on screen at the moment it is asked for, at every width — sticky is inert
while the table fits, which is why the rule needs no media query. *(Built
as stated only since Sprint 18, issue 1009: the table, not
`.data-table-wrapper`, was the sticky container, and the seam is now an
inset shadow — see Amendment 2026-10-03.)*

The issue's draft wording ("the subject column *sorts before* its context
columns under narrow width") was deliberately not taken: CSS cannot reorder
table columns, so a sort-order fix would mean markup that reshuffles when a
chip toggles — a jumping table — or a second, narrow-width column set that
hides data. Pinning keeps one column order and hides nothing.

Applied to: the transaction history's Balance column (when summoned) and the
allocation drift table's Drift column (header, category, position, cash and
unassigned cells). The flat positions table's subject is its Drift **with the
hint beneath it in the same cell** — one pinned column, the anatomy of the
tree's position rows (issue 911, pick H4 variant A, Amendment 2026-10-03);
there is no separate Hint column.

## Amendment 2026-09-12 — appearance decisions from the whole-surface UX review

Rules are in `EXPERIENCE.md` → Amendment 2026-09-12; the evidence and the
variants in `../ux-review-2026-09-12.md`. Appearance decided here:

- **Top bar title:** `.topbar-page h1` takes `line-height: 1.3` and loses
  `overflow: hidden`; the ellipsis clip moves to the `.topbar-page` container
  as `overflow-x: clip`. The line box must clear a capital umlaut at 1× DPR —
  "Übersicht" rendered as "Ubersicht" on every Overview shot since the top bar
  was built, including the committed docs screenshots.
  *Amended 2026-10-07 (issue 1086, Sprint 19 PR γ U4; board
  `mockups/ux-design-2026-10-04/06-phone-wealth`, rule ③):* the heading is
  a grid item and takes `min-width: 0`. At `min-width: auto` it stayed as
  wide as its text (144 px of "Konten & Depots" in a 124 px box at 390 px),
  so it never overflowed itself, its own `text-overflow: ellipsis` never
  drew, and the container's clip cut the title mid-glyph ("Konten & Depc").
  With the zero floor the heading shrinks to its box and ends in the
  ellipsis, "Konten & De…". The container's `overflow-x: clip` and the
  heading's ellipsis and `nowrap` stay as they are.
- **Value suffix:** inside {components.value-slot} the currency renders as a
  `<small>` at {typography.stat-label} size and {colors.text-muted}, 4 px
  after the digits. The digits keep tabular numerals and never wrap.
- **Matrix zero:** "–" (en dash) centred, {colors.text-subtle}, in the cell
  where a sum is 0,00.
- **Stale marker in a value cell:** the `:alert_triangle` glyph at 12 px in
  {colors.warning}, the word "veraltet" and the quote date in
  {typography.table-cell}, on the line under the price. A clock glyph
  (`:clock`, 24×24 house idiom: a circle with hour and minute strokes) is
  added to the icon set for the State Patterns freshness note; the list row
  uses the triangle because it is the attention severity's glyph and the row
  has no room for a second one.
- **Two-line phone rows (UX-DR27):** `grid-template-columns: auto 1fr auto`,
  10 px column gap, 10 px block padding, 1 px {colors.border} between rows;
  name at {typography.table-cell} weight 600, the identifier line at 12 px
  {colors.text-muted}, the figures right-aligned with tabular numerals and
  the second figure (change, quantity) as a 12 px line under the first.
- **Sunburst centre:** three lines — the category in {typography.stat-label},
  the value at 20 px weight 700, the actual/target pair at 11 px muted; the
  centre never paints a colour of its own.
- **Facet control and view switcher:** placed inside `.workspace-section`, so
  they take its padding; no negative margins.
- **Picked variants (owner, 2026-09-14):** C1 **A** (two tiers), C2 **B**
  (a four-cell KPI strip under the value card; the rule is UX-DR2 as amended
  2026-09-14), C3 **A** (two-line rows), C4 **B** (chips behind "Filter (n)"
  as a bottom sheet), C5 **A** (popover on the trigger), C6 **C** (a side
  drawer, a bottom sheet on the phone), C7 **A** (reading overview), C8 **A**
  (column head), C9 **A** (chips with a scope line). The anatomy of each is
  written into Components by the story that builds it (D-2 of the Sprint 12
  plan); until then the mockup named in the review's Part 3 illustrates the
  pick, and the spines specify.
- The mockups under `mockups/ux-review-2026-09-12/` are rendered from
  `priv/static/app.css` itself (linked relatively) with a thin `mock.css`
  frame, so every proposal already uses the shipped tokens and components.
  They illustrate; the spines specify (the clause in `EXPERIENCE.md` → Visual
  references holds).

### KPI band — two tiers *(C1-A, issue 797)*

`{components.stat-card}` in two variants on the Wealth Holdings tab; one
band per area, so the Allocation & targets tab carries the summary line
below instead of the band (EXPERIENCE.md → Amendment 2026-09-12 → Stat card,
extended).

- **Lead card** (`.stat--lead`): the stat anatomy at full size — label, 30 px
  value, a sub-line (`.stat__sub`) at {typography.stat-label} size in
  {colors.text-muted} with its figures at weight 650 in {colors.text}. Three
  in one row (`.kpi-band__lead`, three equal columns; one column under
  720 px): the total incl. cash with its securities/cash composition, the
  TTWROR with the period's absolute result, the IRR/MWR with its basis
  ("annualized · as of …", "not annualized · as of …").
- **Compact card** (`.stat--compact`): the same anatomy at half height —
  96 px minimum, 22 px value, 14/16 px padding. Four in one row
  (`.kpi-band__support`, four equal columns; two under 720 px): securities,
  cash quote with the cash amount, opening value with the net flows, wealth
  multiple.
- **Value suffix** in both: the currency as `<small class="value-suffix">`
  after the digits (the Value suffix rule above). The digits keep
  `white-space: nowrap`; the suffix may drop to its own line on a narrow
  card, the digits never break. **Amended 2026-10-07 (issue 1086, Sprint
  19 PR γ U4; board `mockups/ux-design-2026-10-04/06-phone-wealth`, rule ④;
  the design pass's spec conflict, resolved for EXPERIENCE.md → Value slot
  on the phone only):** under 560 px a compact card of Wealth's band
  (`#portfolio-kpis`) steps its value down from 22 px to 16 px,
  {typography.subsection-title}, the ramp's next step that fits, so the
  value and its suffix share one line there: at 22 px a six-figure amount
  ("182.450,30 EUR") dropped "EUR" under its digits on a half-width card,
  and 18 px still drops it. That one line under 560 px is all the amendment
  builds. Above 560 px nothing changed — the value stays 22 px — and a
  wider compact card may still wrap its suffix under the digits: measured,
  a five-figure amount drops "EUR" in bands between 721 and 880 px and
  again around 1024 px, where four cards share the row. A seven-figure
  amount on a phone may drop it as well. The digits never break. The step is scoped to Wealth's band: Risk's metric cards are
  compact cards too, and there a computed value would read at the 16 px of
  the "not computable" sentence (`.stat-empty`).
- **The opening-value label** *(2026-10-07, issue 1086, the same board's
  "after")*: "Anfangswert · Nettoflüsse (1J)" binds its "·" to the word
  before it with a no-break space, written in the template between the two
  msgids rather than in either msgid. On a half-width card the label breaks
  after the separator, so "·" ends the first line instead of opening the
  second; the space after it stays breakable.
- **Label row** (`.stat__head`): the label and its ⓘ side by side, the
  tooltip in its inline variant (`.metric-tooltip--inline`), so it reads
  with the label instead of pinning to the corner where the sub-line now
  sits.
- **States:** the value-slot rules are unchanged — the skeleton at the
  value's footprint with `aria-busy` while pending, the cue on the
  seconds-class figures, the count-up bar while settling — and the tiers
  reserve their height (132 px / 96 px) so nothing reflows when a value
  lands. Signed values take semantic colour; the sub-line's signed figure
  too.
- **Summary line** (`.kpi-summary`, the Allocation & targets tab): one 13 px
  line in {colors.text-muted} — "Total incl. cash", "Cash quote", "TTWROR
  1Y", each figure at weight 700 in {colors.text} (signed ones in their sign
  colour) — with the "All key figures → Holdings" link in the accent at the
  right end, keeping the picked view. `aria-busy` while either figure
  computes; a failed walk shows "—".

### The Overview's value card: what the total leaves out *(2026-10-06, issue 1081, Sprint 19 PR α M6; board `mockups/ux-design-2026-10-04/01-overview-total`, pick J1 A; plan D-3)*

The "Alles" card prints `total_with_cash`, which counts only what the
valuation can value. UX-DR25 is the rule for exactly this aggregate, so the
card's section names what the total leaves out, beside the figure. #703's
routing (the Overview keeps the count as the alarm, Wealth names) was written
for a condition *in* the total; this one is rows *out* of it.

- **The note:** one `attention` {components.data-note}
  (`data-role="wealth-card-excluded"`) under the card, inside the card's
  `<section>` (the placement rule). Its body reads, on board 01's data:
  "Nicht in der Summe: 2 Verrechnungskonten ohne Wechselkurs zu EUR — USD
  Settlement (1.850,00 USD), US Broker (60,00 USD) · 1 gehaltene Position
  ohne Preis — Placeholder Anleihe 2031 3,25%. Details in Vermögen →". The
  English source says the same ("Not in the total: … Details in Wealth →").
- **The groups, in this order**, separated by " · ", each with its count
  (`ngettext`) and its names after an em dash:
  1. the cash accounts with no rate path to the valuation's base currency
     and a non-zero balance, each with its native balance as the Wealth
     unvalued-cash note prints it, "USD Settlement (1.850,00 USD)" (UX-DR25
     clause 2; an empty account leaves nothing out and is not named);
  2. the held positions with no price (`unvalued_reason: :no_price`), by
     name;
  3. the held positions with a price but no rate path (`:missing_fx`),
     "… ohne Wechselkurs zu EUR — Harborline Freight (Kurs 12,40 USD)"
     ("(price 12.40 USD)" in English), the native price as Wealth's
     missing-FX note prints it, **labelled as the price** (closing act of
     PR α, UAT): under "Nicht in der Summe" a bare bracket reads as the
     amount left out, which a cash account's bracket in group 1 is and a
     position's price per unit is not.

  A group with no member is absent; **with no group there is no note**
  (UX-DR2: no all-clear). A security held in several depots counts once;
  two securities that share a name count twice.
- **"+N":** each group lists at most six names, then "+N" — Wealth's rule,
  the count taken before shortening so it stays true.
- **One set of helpers for both screens:** the note reads only the
  valuation the card already reads (`cash_balances[].valued`,
  `positions[].unvalued_reason`; no new query), and its names and its
  shortening come from the helpers Wealth's notes use, moved into
  `PortfolixirWeb.ValuationNotes`. Wealth's notes render as they did; the
  "Kurs" label of group 3 is the Overview's own, since Wealth's missing-FX
  sentence already says the position "hat einen Preis" and keeps "Harborline
  Freight (12,40 USD)". **One further difference is deliberate:** a retired security still held with no
  price is named here, because the total under which the note sits leaves
  it out; Wealth's no-price note leaves it out (PR #1102), because that note
  links to `?dq=missing_quote`, a list without retired securities, and its
  count must equal that list.
- **The link, and no control** (UX-DR25 clause 3): "Details in Vermögen →"
  links to `/portfolio`, as the card does — the session's view, with no
  `?view=` and no stored choice. The rate sync and a price are fixed on
  Wealth, so the note carries no button that cannot act from here. **The
  consequence:** the note follows the card's scope, the default view, while
  Wealth opens on the session's view, so where the two differ Wealth's
  data-quality notes may name other rows than the note did; adding
  `?view=` would also store that choice (`ViewScope`), which a link from
  the Overview must not do.
- **The section is not a `.grid`.** It holds one card in every state (the
  card, the stale-value article, the skeleton). As a second `.grid` item the
  note became a second column and the card shrank to 457 px at 980 px; with
  `grid-column: 1 / -1` auto-fit stopped collapsing the empty tracks and the
  card shrank to 221 px (both measured on the board). `.workspace-section`
  is already a one-column grid with the 16 px gap, so without `grid` the
  card keeps its full width at 980 and 390 px and the note takes its own
  row under it.
- **One status region:** the section carries one `role="status"` wrapper
  (`#dashboard-wealth-card-status`) that exists before the async read lands,
  as the data-quality line's does, so the note arriving with the card is
  announced once (UX-DR17). Empty, it takes no room in the section's gap
  (`.wealth-card-status:empty { display: none }`, the merge dialogs'
  precedent).
- **The Overview now carries two UX-DR25 notes**, each beside its own
  figure: this one under the total, and the trades card's under its head.

### Overview KPI strip *(C2-B, issue 798; the rule is UX-DR2 as amended 2026-09-14)*

`{components.kpi-strip}`: four fixed cells of the stat anatomy in one framed
row under the value card — TTWROR 1Y with the IRR/MWR sub-line, the cash
quote with the cash amount, the last booking with its kind label and
subject, the quotes with the newest stored quote date and the "n stale"
sub-line only when n > 0.

- **Frame** (`.kpi-strip__cells`): one {colors.border} frame with
  {rounded.lg} and {shadows.panel}, the cells divided by 1 px
  {colors.border}; two by two under 560 px (the third cell loses its left
  border, the second row gains a top border).
- **Cell** (`.kpi-strip__cell`): a link, 84 px minimum, 14/16 px padding;
  {typography.stat-label} label, 20 px weight-700 value in {colors.text}
  (signed values in their sign colour, a not-computable value as a muted
  "—"), 12 px muted sub-line. Hover paints {colors.hover}; focus is the 2 px
  accent ring inside the cell.
- **Stale sub-line** (`.kpi-strip__sub--attention`): {colors.warning},
  weight 600, the `:alert_triangle` glyph at 12 px before the count — the
  attention severity's glyph, as on the list row's stale marker.
  *Amended 2026-10-06 (issue 1081, pick J1.2 A):* the count keeps its
  catalog scope — the `stale_quote` predicate its link opens, benchmarks and
  retired securities left out of both — and says so: "25 veraltet im
  Katalog" (English "25 stale in the catalog"). Beside a basis line that
  speaks of held positions, the difference is then stated (UX-DR26) instead
  of a silent contradiction; a held-only count (J1.2 B) is not built. In the
  178 px phone cell the sub-line wraps to two lines, and the glyph stays on
  the first: `align-items: flex-start`, the glyph `flex: none` with a 2 px
  top margin (board rule ②).
- **Basis line** under the strip (`.summary-basis`): the view, the period to
  its date, the currency, and what the quotes cell measures.
- **Pending:** each cell keeps its label and shows the value skeleton with
  `aria-busy` at the value's footprint; the strip is absent in the empty
  state, where the Overview is the wizard.

### Drift bars in the off-target rows *(issue 798)*

`.drift-bar`: a 6 px track in {colors.bg-muted} with {rounded.full} and a
1 px {colors.border} zero line at its centre; the fill grows right of the
zero line in {colors.positive} when over target and left in {colors.danger}
when under, the worst drift listed filling 45 % of the track so the rows
read against each other. Decorative and `aria-hidden`: the row's text keeps
the sign, the colour and the direction word (UX-DR7). Hidden under 560 px,
where the row is its text.

### Phone lists — two-line rows *(UX-DR27, issue 799; C3-A)*

`{components.phone-row}`: under 560 px the securities list and the
transactions history render as rows beside their tables (the table wrapper
is `display: none` there, the rows `display: none` above), a fixed
composition per surface that the column picker does not touch.

- **Securities:** logo, the name (600, wrapping) over ticker · ISIN · the
  class badge — the derived badge with the quick-assign control, or the
  control alone, where the class is not stated — the currency where the
  security carries no identifier; on the right the latest price (14 px/600)
  over the day change (12 px, signed colour), the stale marker under the
  price instead of a change computed from a stale close, "no price" over
  "—" where nothing prices the row; the kebab at the row's end. Selection
  paints {colors.selected}; a retired row dims like the table row.
- **Transactions:** the month group heads stay (bg-muted band, the
  count ~~and the per-currency totals~~); each row is the date · kind label
  over the subject (security, else cash account, else depot), the signed
  amount with its currency over the size — quantity × price, the quantity
  alone, a split's ratio — and the running balance beneath while the chips
  narrow to one account; the row's kebab at its end, in a third track
  (Sprint 18 U5, H7.6). *Amended 2026-10-07 (issues 1083 and 1073, pick J3
  A):* the head carries the count alone, one line at 390 px — the sums per
  kind and currency are the filter summary's, under its basis line; the
  size prints the price with its stored digits ("12 × 41,1234"); a cash
  transfer's subject names both of its accounts, "Demo Cash → Tagesgeld",
  as the desktop Konto cell does; the subject line breaks anywhere, as it
  does in every phone list (Transactions — the target vocabulary).
- **A security's quotes** *(Sprint 18 U5, issue 1012, pick H7.1 = A)*: the
  date (`Format.date` since 2026-10-07, ISO only in English; Sprint 19 U3)
  over the source badge; on the right the close with the
  security's currency, over "stored <value>" only where a split adjusted the
  close. Two children, no kebab (Amendment 2026-10-03, the phone at 390 px).
- **Wealth's Positions** *(2026-10-07, issue 1065, Sprint 19 PR γ U4; board
  `mockups/ux-design-2026-10-04/06-phone-wealth`, pick J6 A, rule ①)*:
  `ul#holdings-phone-rows.phone-rows` (labelled "Positions") beside the
  table, one row per holding row in the table's order (depot, then name):
  the security's name (600, wrapping) over the depot's name; on the right
  the quantity with its unit word, "18 Stück" / "18 units" ("1 unit" for
  one), in the table's own digits (`Format.exact`: every stored digit, the
  reader's separators). These are the projection's default columns — Depot ·
  Security · Quantity — as a fixed composition: the column picker does not
  touch the rows, so under 560 px `#holdings-positions-wrapper` joins the
  hidden wrappers, and `#holdings-column-toggle` and its panel
  `#holdings-column-picker` join the pickers that hide (a panel opened on a
  wider window would otherwise stay open across a resize).
  Two tracks, `minmax(0, 1fr) auto`, as the trades and quotes rows: no logo,
  no kebab. A row is 59 px (79 px when the name wraps) against the table's
  32; the table it replaces was 445 px wide in a 356 px scroller, with
  "Stückzahl" starting off-screen and a swipe cutting the depot. A name two
  securities share anywhere in the table carries its identifier (Twin
  names, below).
  The pinned-name alternative (J6 B) is not built.
- **Rules kept:** nothing scrolls sideways; matrices and dialog tables keep
  UX-DR15's scroller; the desktop tables are unchanged.

### Twin names — an identifier where two rows read the same *(2026-10-07, issue 1057; Sprint 19 PR γ U4, board `mockups/ux-design-2026-10-04/06-phone-wealth`, pick J6.2 A, rule ②)*

Two securities stored under one name — a duplicate awaiting a merge, or two
share classes the provider named alike — used to read as one row printed
twice. Where two rows of one table would read the same, each carries a
short identifier after its name; a unique name stays bare.

- **The collision key is the displayed name, over the whole table.** A
  twin is a row whose name reads the same as another row's for a different
  security; one security on several rows is never its own twin. Both tables
  decide over every row of their payload: in the contribution table a twin
  among the ten rows shown keeps its identifier while its sibling is among
  the hidden ones. The Positions table has one row per depot and security,
  but the depot is no tie-breaker: two depots' names may read the same (two
  names that differ only by a doubled space are two names to the account
  guard and one to a reader), and the Depot column can be switched off in
  the picker. So one name held by two securities in two depots is a
  collision there too, and one security held in two depots is not — its
  rows carry no identifier.
- **"Reads the same" is the name as a cell shows it:** Unicode NFC, and
  every run of whitespace one space with the edges trimmed, so a decomposed
  "Müller AG" and a doubled space collide with the plain name
  (`SecurityNames.display_key/1`). *Amended 2026-10-07 (the PR γ closing
  act, edge-case hunter #3):* a no-break space (U+00A0), a figure space
  (U+2007) and a narrow no-break space (U+202F) count as a space, because a
  cell prints them as one and `String.split/1` keeps them inside a word: a
  name pasted from a web page or a PDF, "Lumen Werke AG" with a no-break
  space, rendered as the twin of the plain name with no identifier on
  either row. Nothing more is folded: the import's
  `SecurityResolver.skeleton/1` also lowercases, applies NFKC and folds
  Cyrillic and Greek lookalikes, which is "looks alike" for its at-risk
  check rather than "prints the same"; here case stays significant.
- **The chain is ISIN, else WKN, else the number.** Within a colliding name
  the identifier is the first of ISIN and WKN that every twin carries and no
  two twins share (an empty value counts as absent); failing both, each twin
  takes "Nr. <id>" / "no. <id>", the precedent of the security merge
  preview's "Split am … · Nr." and the pickers' own last step. One twin
  with only an ISIN and another with only a WKN therefore both take their
  number. The depot cannot be the last step: depot names may read the same,
  the Depot column can be hidden, and the contribution table has one row
  per security. *Amended 2026-10-08 (issue 1154):* the engine's contribution
  row carries the WKN, so the contribution table runs the same chain; the
  API's contribution payload does not carry it.
- **Anatomy** (`.twin-id`, rendered by
  `PortfolixirWeb.SecurityNames.twin_id/1`): after the name, a word space
  and a ~~6 px~~ 2 px margin from it, inside the name's own cell or
  `.phone-row__name`; {colors.text-muted},
  `--font-mono`, 12 px, weight 400, `white-space: nowrap` — the identifier
  voice of the securities list's row, quieter than the name, so it reads as
  a tag on the name and not as a second name. A visually hidden "ISIN" /
  "WKN" before the value tells a screen reader which identifier it is. The
  separating spaces are real spaces in the normal flow, never inside the
  hidden span, whose absolute position collapses the spaces at its edges:
  one before `.twin-id`, so the name may wrap before the identifier and the
  text never runs together, and one between the hidden label and the value,
  so the row's text reads "Juniper Rail AG ISIN XS…". On the screen the
  second space collapses into the first, so a word space and the ~~6 px~~
  2 px margin separate the identifier from the name. A number names itself
  and has no hidden label. Both tables, at both widths. *Amended 2026-10-07
  (the PR γ closing act, design critic #2):* the board draws a 6 px gap
  between the name and the identifier, and the word space is part of it.
  A 6 px margin on top of the space measured 9.8 px on the desktop and
  10.9 px on the phone, and an identifier wrapped onto a line of its own
  hung 6 px in. With the space kept and a 2 px margin the gap measures
  5.8 px at 1200 px and 6.9 px at 390 px, and a wrapped identifier hangs
  2 px in.
- **One rule, one module.** `SecurityNames.put_twin_ids/2` decides it for
  both tables, beside the pickers' `SecurityNames.tags/1`, whose own chain
  (ISIN, ticker, number) is unchanged: a picker lists the catalog, a table
  reads its payload.
- **Not here:** the ISIN on every row (J6.2 B) — twelve mono characters on
  each row, nothing for twins without an ISIN, and a copy of the picker's
  ISIN column. The surfaces the pass did not name — the contribution's
  unvalued note, the allocation tree and its flat positions, the history,
  the trades, the Overview, Risk — print the name alone until a story names
  them.

### Phone filter sheet *(C4-B, issue 800)*

`{components.filter-sheet}`: under 560 px the D2 chip row is hidden and one
**Filter (n)** pill in the toolbar carries the count of active chips; it
opens a native `<dialog>` at the viewport bottom — the row menu's
bottom-sheet mechanism — with the families stacked under their names
(Holding, Data quality, Currency, Asset class, Changed since), the
More-filters builder in flow, and **Reset** / **Done** at the foot. The
chips are the row's own markup rendered a second time, so a chip in the
sheet applies at once and the count follows; the ModalDialog hook moves
focus in, closes on Esc and returns focus to the control. Above 560 px the
control is absent and the row is unchanged.

### Booking drawer *(C6-C, issue 803)*

`{components.booking-drawer}`: the Transactions page opens on the history;
**Record transaction** in the history's section head opens the booking form
as a side drawer in the securities detail pane's shape — `.detail-pane`'s
panel with a head (title, one-line basis, close control) — placed beside the
history as the second column of a `minmax(0, 1fr) minmax(320px, 380px)`
grid, sticky under the top bar, opened non-modally so the history stays
readable and scrollable. Under 720 px the same dialog opens modally as a
bottom sheet (full width, 88 vh maximum, the modal backdrop tints). The
fields stack — type, date, the depot the booking books to, security — with
quantity and price paired on one row, costs and note behind one disclosure,
the sell-lot preview beneath. The disclosure opens itself when a fee or a tax
is refused, and it stays open, by whoever opened it, while the operator types:
LiveView drops an `open` the server did not render on the next patch, so the
`DisclosureState` hook remembers the toggle and restores it (#869 review
round). The foot carries **Record transaction**
(primary) and **Cancel** (ghost). Recording closes the drawer; Cancel and
Esc discard the draft; focus returns to the control. Built for creating a
booking and shaped — one panel, stacked, pre-fillable fields — for the edit
view (#809) to reuse. The holdings table left the route: it duplicated
Wealth → Holdings.

### Securities detail overview — a reading surface *(C7-A / A8, issue 804)*

The detail pane's first tab reads. Its main column carries the six figures in
a `{components.stat-card}`-quiet grid of three by two — two per row under
720 px, the grid's own phone rule, which the reading surface's three-column
rule outranked until Sprint 18 (U5, issue 1050) — (latest price with its
date or the stale marker, day change, the one-year price return, then the
held quantity with its depot, the position's value and the unrealised result
with its percentage), the neighbouring tab's price chart at 200 px without
its toolbar, and a `.summary-basis` line naming the quote feed, the asset
class, the assigned category of a custom tree and the WKN and exchange the
pane's header does not carry — every one of them a word, never a stored
constant (#785). Beside it, two `{components.panel}` cards: the thesis state
derived from the research log (ADR-0044 §7) with its status badge and a
control that opens the Research tab, and the personal note, which shows a
field only after **Add** or **Edit**. Under 900 px the cards fall under the
main column. **The tab renders no input element until an edit affordance is
used** — the progressive-disclosure rule stated as a testable property. The
master data moved whole into the existing security dialog, opened by an
**Edit** control in the pane's header (which wraps rather than overflowing on
a phone), so creating and editing a security are one form in one place.

### Custom range popover *(C5-A, issue 801)*

`{components.period-control}`'s "Custom range…" stays the D5 disclosure —
same summary, same chevron, same labelled ISO pair, same validation — but
its body is a popover anchored to the trigger (`.period-popover`: absolutely
positioned below the summary, right-aligned to it, 300 px,
{colors.bg-elevated} on a 1 px {colors.border} with {shadows.md}; under
720 px it left-aligns to the trigger). Inside: the
from/to pair on one row with an en dash between the fields, the walked
calendar years as `{components.filter-chip}` chips (one per year with data;
a chip applies on click), then a foot with **Cancel** (ghost) and **Apply**
(primary). Opening it changes nothing in the flow: the section heading, the
period tokens and the chart keep their bounding boxes. Esc and Cancel close
it and return focus to the summary; an applied range or year closes it and
echoes into the segmented group as the D5 custom chip (a year reads as its
number); a refused range keeps it open with the violation on its field. The
securities detail chart's custom range takes the same treatment.

### Classification tree rows — columns *(C8-A, issue 805)*

One head above the tree (`.tree-head`: {colors.bg-muted} band, 11 px
weight-650 uppercase in {colors.text-muted}) names the figure columns —
Category · Positions · Value · Cost · Result — and every category row
(`.cat-summary`) is the same grid: the disclosure marker, the name cell
(swatch, name, description, and the "+N without holdings" count as a muted
0.72 rem suffix), then four right-aligned tabular columns of 4.5 / 7 / 7 /
7 rem and the actions. The name column absorbs the indent of nested
categories, so the figures line up at any depth. ~~An empty category prints
"—" in each figure column;~~ the result cell stacks the signed amount over
its signed percentage, in the sign colours. *Amended 2026-10-07 (the closing
act of Sprint 19 PR γ, the design critic's fifth and the edge-case hunter's
eighth finding):* "Positionen" prints its count, 0 included, because a count
is always computable — under a view that holds none of a category the whole
row used to turn to dashes; "Wert", "Einstand" and "Ergebnis" print
{components.value-slot}`.not-computable`'s dash (`.cat-na`: {colors.text-muted},
weight 400), which stood at the figures' 500 and 600 in the text colour, as
do Unsorted's "Einstand" and "Ergebnis". The percentage is the house form,
the sign and "%" glued on ("+13,7%", γ n12; it was the spaced "+13,7 %"),
and the cell's sign colour is the displayed figure's (`Format.displayed_sign/2`,
U2's rule): a result that reads 0,00 is unsigned and `is-flat`, never in the
gain colour. Under 560 px the row keeps the
name, the value and the result; positions and cost stay in the cells' titles
and on the desktop. **Under 560 px the row lies on two lines** *(issue 873,
pick G8 = A of board `ux-design-2026-09-24/08-classification-detail`)*: the
marker, the swatch (which never shrinks), the name — allowed to wrap — and its
"+N without holdings" on the first, the actions at its end; the value and the
result on the second, in their own columns under the head. With the page's
16 px gutter, one line left the name some 70 px and cut it to a few letters;
two lines give it the row's width, which is UX-DR27's phone row applied to the
tree. On the desktop the row is one line as before. The unassigned notice is the attention data note it
became with issue 791; the result's basis is a `.summary-basis` line with
the full ADR-0041 sentence behind its ⓘ.

*Amended 2026-10-06 (#1048, Sprint 19 PR α M5; board
`mockups/ux-design-2026-10-04/10-category-results`, pick J10.2 A).* Every
scope of the category result, "Alles" included, is in EUR. A member whose
cost was not paid in EUR is left out of "Einstand" and "Ergebnis". It is
never converted through the hub, which would state a cost nobody paid.

- **The basis line names the currency first**: "in EUR · Ergebnis: heutige
  Zusammensetzung, keine Periodenrendite". The currency is the result's
  `base_currency`, never assumed. The view's name that J10 puts before it
  ("Ansicht Langfrist · in EUR · …") belongs to PR γ U7 and is not built
  with this record. *Built 2026-10-07 (U7, the amendment below).*
- **The note on left-out members.** One `attention` {components.data-note}
  (`data-role="category-result-excluded"`) stands between the basis line and
  the tree head, 0.5 rem below the line (board rule ②). Its `role="status"`
  region renders whenever the result has loaded, empty when nothing is left
  out, so a note that arrives in it is announced. For one member it is one
  sentence: "1 Position ist in
  „Einstand“ und „Ergebnis“ nicht enthalten, weil ihr Einstand nicht in EUR
  bezahlt wurde: Harborline Freight Inc (Plattformen), Einstand 1.500,00
  USD. Im „Wert“ ist sie enthalten."
  - The name is in `<bdi>`, and the category is the one the member is filed
    under, as the tree on screen names it.
  - The native cost goes through `Format` as money: two decimals in German
    form, the code after the amount, never converted (UX-DR25 clause 2). A
    security held in a EUR and a non-EUR portfolio leaves whole (ADR-0041
    §4) and lists one amount per currency, EUR first: "Einstand 1.000,00 EUR
    + 1.500,00 USD". Its sentence then says the cost "nicht nur in EUR"
    was paid.
  - Every excluded member is named, whatever its reason. A member with no
    usable price, no cost derivable from its bookings, no cost in its
    portfolio's base currency or no stored exchange rate gets its reason in
    words instead of a cost ("Dark AG (Kern), kein brauchbarer Kurs.").
  - "Im „Wert“ ist sie enthalten" (plural "sind sie enthalten") is said of a
    member exactly when the valuation the "Wert" column reads gives it a
    value, whatever its reason (UX-DR26). A USD member with no stored rate,
    whose row prints "—", is never said to be in it; a member with no quote,
    which "Wert" reads at its trade price, is.
  - No button, because there is nothing to fix here (clause 3). Nothing
    excluded, no note: UX-DR2 has no all-clear.
- **Past one member the note becomes a count and a disclosure.** It states
  the count ("3 Positionen sind in „Einstand“ und „Ergebnis“ nicht
  enthalten."), with the currency's reason when it is every member's. Then
  it says how many of them "Wert" holds: "Im „Wert“ sind sie enthalten."
  for all of them, "1 davon ist im „Wert“ enthalten." for some, nothing for
  none. The members follow in a
  `details.perf-table-disclosure` ("Die 3 Positionen") as the trades facet's
  unmatched-sells `.excluded-list`: name · category · native cost (`.num`)
  or reason, sorted by name. **Under the count without a reason** (the
  members are out for different reasons), a cost line carries its own, as
  a reason line does *(closing act of PR α, UAT)*: "Einstand 1.500,00 USD,
  nicht in EUR bezahlt", and "Einstand 1.000,00 EUR + 1.500,00 USD, nicht
  nur in EUR bezahlt" for a member whose costs include EUR — the
  one-member sentence's distinction. Only each amount of such a line is
  `.num`, which keeps it unbroken; the rest of the line wraps, so it reads
  whole inside the note at 390 px instead of running past its edge
  *(closing act's screenshots)*. Under the count that names the currency
  for every member, the line keeps the cost alone, one `.num` cell, unless
  it is a cost in two currencies, which wraps between its amounts the same
  way; the one-member sentence is unchanged.
- **`.cat-result-partial`**, the row's "1/2", has its rule (board rule ③):
  the percentage's size (0.72 rem), weight 500, {colors.text-muted}. It used
  to print as a bare third line in the result cell's own size and colour.
  Its reason stays in the title. Board ③'s comment also asked for words
  beside the count on the desktop; they are not built, and the count stays a
  bare sub-figure, because the note above now names each left-out member
  with its reason.

*Amended 2026-10-07 (#1091's screen half, Sprint 19 PR γ U7; board
`mockups/ux-design-2026-10-04/10-category-results`, pick J10 A).* The
screen's one scope is the active view, and every figure, the plan editor and
the basis line read it.

- **The controls row.** Under the detail head, before the plan editor, a
  `.workspace-section--controls` row (issue 790's row) holds
  `PortfolixirWeb.ViewSwitcher`, unchanged from Wealth: the chips with no
  prefix, "Ansichten" as a quiet link (D4), the plan dot, the active-view
  line and its ⓘ. The default-view control stays Wealth's. **The dot means
  something narrower here** *(review round)*: a view in which this tree has
  a plan — the plan the editor below shows, active or draft
  (`Targets.plan_views/2`); a portfolio-wide cash target alone is not one,
  so the dot and the editor never contradict each other, and the chip's
  title ("Hat einen Soll-Plan für die aktuelle Klassifizierung") reads true.
  Wealth's dot keeps the allocation engine's definition. The row shows on
  every tree, built-in ones included, which have no editor. A chip is a
  navigation through `ViewScope`, so a view picked here is the active view on
  Wealth too, and the other way round. Wealth's no-plan hint deep-links with
  `?view=`; the screen reads no `?soll_view=`.
- **Every figure of a row follows the view.** "Positionen", "Wert" and the
  security rows read the view's positions the way the view valuation narrows
  them (ADR-0018), in EUR; "Einstand" and "Ergebnis" read the view's category
  result (`CategoryResult.for_view/3`), the read `GET
  /api/v1/views/:view_id/category-results` serves. Under "Alles" the row reads
  every portfolio, as before (`for_all_portfolios/2`, `GET
  /api/v1/category-results`). Scoping only the result would put two scopes
  in one row.
- **The editor's scope text.** The plan editor's select goes. Its head is
  "Soll-Plan" with, at its end, `.soll-editor__scope` "für Ansicht
  Langfrist" (board rule ①: 0.9 em, {colors.text-muted}, the picker label's
  voice) — "für Ansicht Alles" with no view — and it edits that view's plan.
  The copy picker lists the no-view plan as "Alles". The editor speaks the
  switcher's words, "Ansicht" and "Alles", never "Sicht" and "Gesamt", and
  Wealth's no-plan hint now does too ("Kein Soll-Plan für diese Ansicht").
- **The basis line names the view, then the currency**: "Ansicht Langfrist ·
  in EUR · Ergebnis: heutige Zusammensetzung, keine Periodenrendite"
  ("Ansicht Alles · …" with no view). The view's name is stored text, in
  `<bdi>` (H8.8). The sentence is one span, so the line's flex row wraps it
  as text, and a no-break space before each " · " holds the "·" to the word
  before it: no line starts with one, however long the view's name
  *(review round)*.
- **A view that matches no account** says so under the controls row, in
  Wealth's hint and words (`data-role="view-matches-nothing"`), instead of
  leaving every row at "—" without a reason *(review round)*.
- **The note on left-out members** (M5's, above) follows the view with its
  result: one sentence for one member, the count and a disclosure past one.
  It names only what the view's figures leave out.
- **"+N nicht in der Ansicht".** Under a view, the `.cat-without-holdings`
  slot counts the members the view holds none of — held in an account
  outside it, or no longer held at all — as "+2 nicht in der Ansicht"
  (title "Zugeordnete Wertpapiere ohne Position in dieser Ansicht, vom Filter
  ausgeblendet"), hidden under "Nur aktuelle Positionen" as "ohne Bestand"
  rows are. Under "Alles" the slot reads "+N ohne Bestand" as before. One
  slot, not two: both kinds are not in the view, and a second suffix would
  crowd the name on the phone's first line. **The name cell wraps at every
  width** *(review round)*: `.cat-summary .cat-name` takes `flex-wrap: wrap;
  row-gap: 0`, and the swatch `flex: none`, outside the 560 px block too, so
  the suffix stands beside the name and drops under it when both do not fit.
  It used to cut the name to "Sta…" at 768 and 1024 px and collapse the
  swatch at 768 px. **"Nicht zugeordnet" follows the view the same way**: it
  counts and values the unsorted positions the view holds and puts the rest
  in the same slot; ~~under "Alles" it is what it was, every unsorted security
  whatever the toggle~~. *Amended 2026-10-07 (the closing act of PR γ, the
  edge-case hunter's seventh finding; the coordinator's decision):* it
  honours "Nur aktuelle Positionen" in every scope, as the categories do.
  Under "Alles" with the toggle on, the unsorted securities no longer held
  drop into the same slot, "+12 ohne Bestand", and the count and the value
  are the held ones' — one data set read "+12 nicht in der Ansicht · 27"
  under a view that includes every account and "39" under "Alles", and now
  reads "+12 ohne Bestand · 27" there. With the toggle off both list every
  unsorted security, with no slot. *Amended 2026-10-07 (cascade layer 2 of
  the closing act):* the slot's title is Unsorted's own, "Nicht zugeordnete
  Wertpapiere ohne Bestand, vom Filter ausgeblendet" ("Nicht zugeordnete
  Wertpapiere ohne Position in dieser Ansicht, …" under a view); it carried
  the categories' "Zugeordnete, nicht mehr gehaltene Wertpapiere", wrong
  twice, because these securities are unassigned and some were never held.
  The assignment nudge still counts every unsorted security, which is what
  the row it links to shows: its visible securities plus its slot (21 + 12 =
  33 on the demo).
- **`.cat-result-partial`** keeps M5's rule above, unchanged.
- **A view deleted while the page reads it** degrades the screen to "Alles"
  with Wealth's notice ("Die gewählte Ansicht existiert nicht mehr — es wird
  Alles angezeigt."), never an error. A view deleted after the page loaded
  is noticed before a plan write: "Plan anlegen", "Plan speichern" and "Plan
  löschen" degrade the screen the same way and write nothing *(review
  round)*. *Amended 2026-10-07 (the closing act of PR γ, the edge-case
  hunter's fourth finding):* the write answers with a refusal, the page's
  result, beside the notice — "Die Ansicht „Langfrist“ wurde inzwischen
  gelöscht; es wurde nichts gespeichert." ("… kein Plan angelegt.",
  "… nichts gelöscht.") — because the typed weights gave way to the plan of
  "Alles", and the muted notice alone did not say they were not saved.

## Amendment 2026-09-23 — Wealth → Risk, the surface ADR-0047 §9 assumed *(Sprint 14 D-2, pick E1-A)*

Board: `mockups/ux-design-2026-09-20/01-wealth-risk-surface` (variant A, the
recommendation, adopted by the planning PR's merge without a comment changing
it). Built by Sprint 14 Lane A4 as `PortfolixirWeb.RiskLive` at `/risk`.

### Placement

A **sixth Wealth area tab**, "Risk" / "Risiko", after Tax, with its own glyph
(`:shield`, not used elsewhere, so no glyph carries a second meaning). The tab
row's shipped overflow form (D6 above: scroll-snap, the right-edge mask,
`flex: none` on the tab) carries it; nothing in `.area-tabs` changed. The
sidebar keeps Wealth current on `/risk`.

### Anatomy, top to bottom

1. **Portfolio metrics** — four `.stat.stat--compact` cards in the KPI band's
   supporting grid (`.kpi-band__support`: four columns, pairs under 720 px):
   volatility (annualized, one year), maximum drawdown (the peak → trough dates
   and the recovery date or "not recovered" as the sub-line; the value in the
   danger colour when negative), risk-adjusted return (the risk-free rate and
   "return per unit of risk" as the sub-line), correlations (the highest
   computed pair and how many pairs computed). The page reads the **365-day**
   window; the API carries all three.
2. **The refused state** is the Value slot's not-computable form
   (`strong.stat-empty`): "not computable" with **"n of required
   observations"** as the sub-line (#838), never a dash and never a number. A
   risk-adjusted return over a volatility of exactly 0 is "undefined —
   volatility is 0", which is a different statement from "short of data".
3. **Basis line** (`.summary-basis`) under the cards: the flow-adjusted TTWROR
   factors, the base currency, `√365`, the gap rule, the conversion of the
   matrix (UX-DR26: the limit is stated on the surface), and how many of the
   largest names the correlations run over — the number the answer carries
   (`correlations.leading_names`), never a constant of the page, because the
   matrix is bounded below the list's maximum length (E25 S4, board
   `ux-design-2026-09-24/11-security-visible-states`, part 3).
4. **Largest single names** — a `.data-table`: security, asset class, value
   and weight as `.num` columns, and a **threshold** badge that names the
   threshold rather than pronouncing on it: "above 10 %" (`.badge--danger`,
   the stock hard line), "above 7 %" / "above 25 %" (`.badge-warning`),
   "below 7 %" / "below 25 %" (`.badge--neutral`).
5. **Concentration (HHI)** — one `.stat--compact` card: the value with its
   band as the value suffix, a decorative `0–10000` track tinted at the band
   cutoffs (`.risk-hhi__track`, `aria-hidden`) with a marker at the value, and
   the cutoffs spelled out as the sub-line.
6. **Asset-class caps** — the violations, or the empty-state sentence "No cap
   configured — there is nothing to exceed", which also says caps are set per
   request over the API (the surface does not configure them).
7. **Correlations** behind the chart-as-table disclosure
   (`details.perf-table-disclosure`, **closed by default** — #807's
   precedent): pair, correlation, observations `n / 60`, and the names left
   out for want of a rate path.

### What the surface does not carry

No recommendation, rating, signal or action — ADR-0047 §7; the threshold
badge is the lens's own arithmetic. No rebalancing hint (ADR-0023 permits one;
this surface does not build it). No cap editor.

### Checked at 390 px

The four cards pair up (two columns) rather than stacking, as the KPI band's
support tier does; the longest refused sub-line ("6 of 20 observations") fits
the half-width card. This is the one thing the board could not settle, and the
design critic checks it on a real render.

## Amendment 2026-09-24 — Wealth → Risk: the operator's own rules *(Sprint 15 pick F1-A, ADR-0049 §9)*

Board: `mockups/ux-design-2026-09-23/01-policy-rules-surface` (variant A, the
recommendation, adopted by the planning PR's merge without a comment changing
it). Built by Sprint 15 Lane A4 in `PortfolixirWeb.RiskLive` and
`PortfolixirWeb.Risk.PolicyRuleDialog`.

### Placement

A section **"Own rules" / "Eigene Regeln" at the top of Wealth → Risk**, above
the portfolio metrics. A finding is most legible next to the figures it
judges, and the question a rule answers — "am I inside my limits?" — is the
question the tab exists for. No seventh area tab, no Overview card (variants
B and C of the board).

### Anatomy, top to bottom

1. **Section head**: the title with a muted count per state
   (`.section-head__meta`: "1 breached · 1 undetermined · 3 met") and a
   secondary "New rule" button.
2. **Findings table** (`.data-table.policy-findings-table`), sorted breached,
   then undetermined, then met; hard before warning within a state. Columns:
   - **Rule**: the name as a **link at rest** (`.policy-rule__name` on
     `.link-button`: accent colour and underline without hovering, bold, the
     focus ring; `.link-button` carries none of the base button's shadow,
     radius or 34 px floor, only the 44 px under a coarse pointer) that opens
     the edit dialog — *amended 2026-09-25 by pick G7-A, below; it was a quiet
     button in text colour, underlined on hover only* — and under it the rule's
     **words** (`.policy-rule__words`: measure and window · subject · kind ·
     severity). A built-in tree's category reads in the page's language
     (`ClassificationName.category/2`), never its stored English name;
   - **Measured** and **Line** as `.num` columns, on the measure's own scale:
     weight and volatility `12.4 %`, drawdown `-12.0 %`, drift `-1.2 pp`, HHI
     `6,800`; a band's line reads `lower … upper`. Negative figures carry the
     hyphen-minus every other figure in the app carries (the board drew U+2212;
     the spec follows the app, closing act F30). A value and its unit are
     joined by a non-breaking space, so a narrow cell breaks a band only at
     `…`. **Below 720 px** the Line column steps aside and the line rides
     under the measured value (`.policy-rule__line-sub`, "Line 30.0 %");
   - **State**: a badge — breached `.badge--danger` (hard) or `.badge-warning`
     (warning) carrying the signed distance ("breached · +2.4 pp"), met
     `.badge--neutral`, undetermined **`.badge--undetermined`** (transparent,
     muted text, a dashed strong border) with the reason under it
     (`.policy-rule__reason`): for a refused metric "n of required
     observations", else the reason in words ("no active plan", "no target in
     the plan", "nothing to weigh", …).
3. **Basis line** (`.summary-basis`): evaluated on read, the date, the view's
   steerable basis; undetermined is never met; a finding does not say what to
   do (UX-DR26).
4. **Retired rules** behind a closed chart-as-table disclosure
   (`details.perf-table-disclosure#policy-rules-retired`): each name opens the
   same dialog, with its period and last line beside it.

The lens's **Top-N** section below is retitled "Largest single names ·
generic thresholds, not policy rules", and its column "Generic threshold", so
a weight that carries both an operator's breached rule and the lens's "above
10 %" reads as two statements — never as one mechanism (ADR-0049 §7).

### The dialog

A native `<dialog>` (UX-DR9), one component for create and edit:

- **Fields** in `.form-grid`: name (on create and on edit — *amended
  2026-09-25, G7-A:* the context view is the rule's identity, the name is its
  label), measure, subject, the plan's classification
  (only for the drift of a security), window (only for volatility and
  drawdown), kind, the line (or "From"/"To" for a band) with the measure's
  unit in its label, severity, "In force from" (the ISO text input, UX-DR19),
  a note across the full width (`.form-grid__wide`). The **subject control
  follows the measure**: its options are exactly the ADR-0049 §2 matrix, so
  the form cannot submit a pair the record refuses.
- **Editing is a new version, said before saving**: "Saving creates version
  N. Version M (10.0 %) is in force since … and stays readable." The version
  list (`ol.policy-rule-versions`) is open under it.
- **Footer**: a spacer (`.modal-footer__spacer`) separates the confirmed
  destructive action on the left — "Retire rule", or "Delete rule" for a rule
  none of whose versions has been in force — from Cancel and the primary
  "Save new version" / "Save rule". Below 480 px the destructive action takes
  a row of its own at the start and the pair wraps under it, so no label
  breaks over two lines (board 07); without it the footer stays one row.
- A version that only started today ends **tonight** when retired; the
  confirmation and the version note say so rather than pretending it is gone.

### What the surface does not carry

No action, quantity or suggestion on a finding (ADR-0049 §6; the API payload
is walked for it by a meta-test). No push, no digest. The lens's per-request
caps are not configured here, and the two mechanisms do not read each other.

## Amendment 2026-09-24 — The booking drawer's cross-currency settlement *(Sprint 15 pick F3-A, issue 395)*

Board `ux-design-2026-09-23/03-settlement-inputs`, variant A, as built.

- **Shown only when it is required.** The block appears in the booking drawer
  when a buy or sell's security currency differs from the chosen depot's cash
  account, directly under the quantity/price row, and nowhere else. A booking
  in one currency carries no empty settlement fields (variant B's cost).
- **Anatomy.** A `fieldset.settlement-fieldset`: accent border, the
  `--color-accent-soft` tint, `--radius-md`. Its legend is the block's heading
  *inside* the box (floated, so it does not straddle the border): "Settlement in
  EUR" in the accent at 600, then "· security in CHF, account in EUR" at 400.
  Two fields in `.form-grid` — the settlement amount in the account currency and
  the rate "EUR per CHF" — then one `.form-help` paragraph without the help
  box's padding, carrying where the suggestion came from ("suggested from the
  stored exchange rates on or before 2026‑09‑13", or "no stored exchange rate …
  enter the settlement amount from the broker statement") and the guard in one
  sentence, so its 422 never surprises. ~~The ISO date in running text uses
  non-breaking hyphens.~~ *Amended 2026-10-07 (Sprint 19 U3):* the day reads
  the page's language once the field reads as a date ("am oder vor dem
  13.09.2026"); an English ISO date keeps its non-breaking hyphens.
- **Around it.** The price label names the security's currency ("Price (CHF)")
  and the derived-currency line reads "Price in CHF · cash in EUR".
- **Behaviour.** Amount and rate derive each other from whichever was typed; a
  changed quantity or price re-derives the amount from the rate; a changed
  security, depot, date or kind re-prefills a *suggested* rate but never one
  the operator typed. A missing amount on save is named on its own field.

## Amendment 2026-09-24 — Position targets in the plan editor *(Sprint 15 pick F2-A, issue 481)*

Board `ux-design-2026-09-23/02-position-soll-entry`, variant A, as built.

- **One table, one form.** A category with assigned securities carries a
  text-style disclosure control beside its name — the chevron plus
  "Positions (n)" in the accent, no button chrome (`.soll-positions-toggle` on
  `.disclosure-button`, `aria-expanded`/`aria-controls`), with the 2 px accent
  focus outline every control carries (board 07). Its position rows
  follow directly under the category in the same `<table>`, indented one level
  deeper, on `--color-bg-muted`, each with its own target input. One save, one
  live Σ. A category whose positions carry a target opens by default.
- **Closed is hidden, never removed.** Collapsed rows carry `hidden` and keep
  their inputs in the form, so closing a category can never read as clearing
  its targets.
- **The category follows its positions.** Once a position carries a target,
  the category's input is replaced by `output.soll-position-sum`: the sum, in a
  dashed `--color-border-strong` box at the input's width, muted, right-aligned,
  with the line "Sum of the position targets — the category follows it" under
  the name. Shown, not entered (ADR-0030 §2).
- **Empty is not zero.** An empty position input is no target; the copy and
  the save both honour it.
- **Fits at 390 px.** The plan table opts out of the scroller's
  `min-width: max-content` (the Risk tables' fit pattern) and position names
  wrap anywhere, so every input stays on screen.
- **The children Σ is live** *(issue 874, board
  `ux-design-2026-09-24/08-classification-detail`, before/after)*. A parent's
  "children Σ n%" hint (#467, `.hint.target-consistency`, the mismatch colour
  when it disagrees with the parent's own weight, never blocking a save) is
  recomputed on every input, exactly as the Σ footer is, and on load by the
  same computation: each child counts with the weight it steers by, so a child
  that follows its positions counts with their sum. Its form and colour are
  unchanged; it simply no longer vanishes between the first keystroke and the
  save — it is the only place a parent at 65 % over children adding up to 60 %
  shows, because the Σ footer counts the parent alone.

## Amendment 2026-09-25 — Wealth → Risk: the rule's name as a link, and the rename *(Sprint 16 pick G7-A, issue 872)*

Board `mockups/ux-design-2026-09-24/07-rule-name-affordance`, variant A (the
owner's pick, plan D-5), with Part 1 of the same board for the rename (plan
D-6, ADR-0049 §4 as amended). Built by Sprint 16 Lane D in
`PortfolixirWeb.RiskLive` and `PortfolixirWeb.Risk.PolicyRuleDialog`.

- **The name is the one way into the rule, and it looks like it.** In the
  findings table the rule's name carries the link treatment **at rest**:
  `.link-button`'s accent colour and underline, bold because it heads its row.
  `.policy-rule__name` no longer overrides the colour or the underline, and
  its `:hover` rule is gone; the focus ring and the 44 px under a coarse
  pointer stay. One treatment for "open this rule" across the section: the
  scheduled and retired names below the table already carried it. No kebab
  and no standing "Edit" button (variants B and C): at 390 px the table keeps
  its three columns. Colour and underline are two cues, so the control does
  not rest on colour alone, `forced-colors` included. The coral accent's
  light-mode contrast for body-size link text is the token question every
  `.link-button` already has, not a property of this pick. *(Closed by issue
  908, Sprint 18 pick H5: {colors.accent-coral} is `#ce1b42` in light mode,
  5.44:1 on a panel.)*
- **The dialog names the rule on edit too.** The name field is the first
  field of `.form-grid` on create **and** on edit (`maxlength` 255). The
  heading keeps the stored name until the rename is saved.
- **What saving does is said before it happens.** With only the name changed,
  the hint under the fields reads "Only the name changes: saving creates no
  new version …" in place of the version note, and the primary button reads
  **"Save name"**; the "In force from" date plays no part. With the name and
  any field of the predicate changed, the version note stays and gains a
  second line (`.hint__line`): "The new name applies to the rule with all its
  versions."; the button stays "Save new version", and one save writes both
  or neither. A blank name is the field's own error, as on create.
- **A retired rule** opens the same dialog from the retired list and is
  renamed the same way; a rename there creates no version either.
- **The German button reads "Namen speichern"** (the accusative the verb
  takes), where the board drew „Name speichern“; the build reuses the
  catalogue's existing entry for "Save name" rather than adding a second
  spelling of one action. Recorded by the Sprint 16 S3/S4/D review round
  (LD-5), so the board and the spec agree.
- **The dialog keeps the rule's own subject** among its choices even when
  that security is retired (the remedy ADR-0049 §8 gives), so a rename of
  such a rule stays a rename and never moves it to another security (review
  round, LD-1). A new rule is still not offered a retired security.

## Amendment 2026-09-25 — A refusal that names rules makes each one reachable *(Sprint 16 pick G6-A, issue 871)*

Board `mockups/ux-design-2026-09-24/06-view-rule-reach`, variant A (the
owner's pick, plan D-5). Built by Sprint 16 Lane D in
`PortfolixirWeb.PolicyRuleReferences`, used by `BucketsLive`,
`ClassificationsLive` and the securities delete-blocked dialog.

- **The form stays.** A delete of a view, a category or a classification that
  rules read is refused in the page's existing message band, as Sprint 15's
  board `06-rule-reference-409` fixed; a security keeps its "Cannot delete"
  dialog. No new element. The refusal dialog for view deletes (variant C) is
  declined: it would reopen that pick for one of three kinds of delete, and a
  view has no second way out to offer.
- **Each rule is a link to where it lives.** A rule belongs to the view it
  applies in (its context, ADR-0049 §1), and Risk shows only the active
  view's rules. So each rule reads `“name” (status, view “View”)` —
  `„Name“ (gilt, Ansicht „Alles“)` in German — and **only the name** is the
  link, to `/risk?view=<its context>` (`view=total` for a portfolio-wide
  rule). The parenthesis names the view **before** the click, because the
  link changes the active view on every Wealth tab, as a view chip does. The
  band's second sentence is unchanged.
- **A plain `href`, never `navigate`**: a full navigation, so the view scope
  takes the choice and Risk's header names the view on arrival (UX-DR26).
  Arrival is the page as it is; no jump to the row and no highlight. A retired
  rule is behind the page's "retired rules" disclosure, which the "(retired)"
  in the band points to.
- **Link style**: the band's own colour, underlined at a 2 px offset —
  `.alert-error a` and `.confirm-delete-blocked .modal-body a` share the rule
  `.data-note__body a` carries, so the links survive the band's move into a
  data note unchanged. In running text the links take the inline exception of
  the target-size rule (WCAG 2.5.8), as a data note's remedy link does.
- **The rules arrive as data**, never as a finished sentence: the translated
  templates are split around their placeholders before any stored name is
  put in, so a rule's or a view's name is only ever text.
- **Known limit: the link carries the view, not the portfolio.** A rule's
  context is its portfolio and its view, and Risk shows the first portfolio
  only, so a rule of another portfolio (one created over the API, say) is
  named in the refusal but its link opens Risk without it. The limit is
  Risk's, inherited rather than introduced by this pick; a per-portfolio Risk
  is its own follow-up (recorded by the Sprint 16 S3/S4/D review round, LD-4).

## Amendment 2026-09-25 — The booking drawer's split state *(Sprint 16 pick G12.3-A, E25 S6, G07)*

Board `mockups/ux-design-2026-09-24/12-e25-new-marks`, G12.3 variant A (the
owner's pick, plan D-5), as built in `TransactionManagementLive`.

- **When.** **Edit** on a history row whose type is split opens this state of
  the booking drawer instead of the booking form. A split is a fact about the
  security, booked through **Record split** on it; the ledger refuses every
  change to a split row but its note, on the API and MCP as here.
- **Anatomy.** The same `dialog.detail-pane.booking-drawer`, titled "Edit
  transaction". The sub line says what the drawer does before anything is
  tried: a split is a fact about the security, only the note changes here,
  and the change is journaled. Then a `.form-grid` of four **disabled**
  fields with the words of **Record split**: Type ("Split"), Effective date
  (ISO), Security (name and ticker) and "Ratio (new:old shares)" as "2:1",
  the form the history shows. No depot (the row has none), no quantity or
  price, no settlement block and no costs disclosure: a split carries none of
  them. One `.form-help` line states the limit where the correction is tried
  — the effective date, ratio and security are fixed; a wrong split is
  deleted over the API or MCP and recorded again with **Record split** —
  **without a link** (UX-DR26), because no screen deletes a booking yet; the
  link arrives with a "Delete split" action (Part 13, item 5 of the design
  pass). The **Notes** textarea stands open under it, and the foot carries
  **Save note** (primary) and **Cancel** (ghost).
- **Behaviour.** Saving sends the note only and closes the drawer with
  ~~"Note saved"~~ "Booking note saved"; a refused write keeps the drawer
  open with the page's error band. *Amended 2026-10-07 (the PR γ closing
  act, design critic's judgement (c)):* since the page's result is an
  inline result (issue 1064), a note carries its word, and the English
  result read "Note Note saved"; the message now names what was saved.
  German keeps "Notiz gespeichert" after "Hinweis".

## Amendment 2026-09-26 — Accounts & depots: lifecycle controls *(Sprint 16 pick G1-A, issue 328, ADR-0050 §4, §11, §12; board 13 pick G13.1-A)*

Board `mockups/ux-design-2026-09-24/01-accounts-lifecycle`, variant A (the
owner's pick, plan D-5), and board `13-l5a-merged-from`, variant A (drawn in
the batch; silence adopts it). Built by Sprint 16 Lane L5a in
`PortfolixirWeb.PortfolioAccountsLive` and
`PortfolixirWeb.PortfolioAccounts.RenameDialog`.

- **Every entity row carries its own kebab** — the depot row, the cash row
  of a pair and a lone cash account; the repeated row of a shared account
  carries none. Each is named for its row through the shared
  `AppShell.row_kebab` (issue 870): "Actions for Tagesgeld (alt)". A split
  pair's depot row keeps its kebab.
- **The menu is ordered by consequence:** Rename (the edit glyph) · Tag
  separately (the depot row of a pair tagged together only) · Merge into…
  (the new `:merge` glyph, two lines joining into one arrow — no existing
  glyph carried the meaning, UX-DR16) · Delete, last, in
  `.row-context-menu__item--danger`. Merge into… is not danger-coloured: it
  opens a preview, and only the preview's confirm writes.
- **Under 720 px the menu is the existing bottom sheet and names its row**:
  `AppShell.row_menu` takes an optional `caption_name` / `caption_kind` and
  renders `.row-context-menu__caption` ("**Tagesgeld (alt)** · Cash
  account"), shown under 720 px only, where the sheet no longer hangs at its
  row. **Under 640 px** each band's rows become a two-column grid, so every
  kebab sits at the end of its own name line; the hover tint covers the
  whole line.
- **Two sub-lines under the name**, both `.account-sub` at 12 px as their own
  lines (`.account-sub--merged`, `.account-sub--former`), readable without a
  click: "merged from <source> · <date>" (the newest merge, then "+N"), and
  "former: <newest former name>" (then "+N"). A merged source's name is said
  once, on the first line; its own earlier names stay in the second, because
  they were renames. The date of the newest merge is a link
  (`.merge-date-link`, the accent, underlined at rest) to that merge's
  entry in the merge records at the end of the page:
  `/portfolios?merge=<record id>#merge-records`, which opens the section and
  that entry's result server-side (Sprint 17 V1, G2-A below).
- **Rename** opens a native `<dialog class="modal rename-dialog">` titled
  "Rename — <name>": one field (only the name is editable; currency and
  portfolio freeze once referenced, §11; role, balance and buckets stay in
  the row), then a `.hint` that states the rename rule's case before
  anything is written — "The current name “X” stays a former name: an import
  that still names it keeps booking to this account (depot)", or, while
  another account of the kind carries X live, "…so the current name is not
  kept: an import that names it books to that account. Merge or rename that
  account to change this." A name another account answers to is refused
  **at the field** (`.field-error`, `aria-invalid`), naming the holder and
  the way out — a former name names the account it belongs to and says to
  remove it there; a live name says "Choose another name, or merge or rename
  that account" (board 14 ⑤); nothing is written. Saving closes the dialog; the row
  changing in place is the confirmation — no banner.
- **Former names** are the dialog's open `.perf-table-disclosure` "Former
  names" with a bordered `.former-names` list: each name, a muted
  `.former-names__origin` line ("merged on <date>") when it arrived by a
  merge, and a ghost **Remove** whose native confirmation says what it costs:
  "Remove “X” as a former name? An import that still names 'X' will then
  create a new account." (a new depot for a depot). Removing acts at once;
  the dialog stays open and a typed name stays typed. No list, no
  disclosure, when there are no former names.
- **Delete asks only when it can succeed.** The page reads what references
  the account as the menu opens. Referenced: Delete opens "Cannot delete"
  directly (the securities page's `.confirm-delete-blocked` dialog) —
  "“X” still has 151 bookings and 1 linked depot (Depot 2) — merge it
  first.", a muted line saying what a merge moves, and **Merge into…** as
  the primary way out, which opens the merge's step 1 for that account.
  Free: one native confirmation naming the account ("…has no bookings and
  no linked depot."), plus "Its bucket assignments are removed with it."
  when it carries any; the row disappearing is the confirmation.

## Amendment 2026-09-26 — Lifecycle merge — preview and confirm *(Sprint 16 pick G2-B, issue 328, ADR-0050 §7, §8, §10)*

Board `mockups/ux-design-2026-09-24/02-merge-preview`, variant B (the
owner's pick, plan D-5), with the three lines board `13-l5a-merged-from`
adds. Built by Sprint 16 Lane L5a in
`PortfolixirWeb.PortfolioAccounts.MergeDialog` (the state) and
`PortfolixirWeb.PortfolioAccounts.MergePreview` (step 2).

- **Placement.** Opened from a row's "Merge into…" or from "Cannot delete".
  One native `<dialog class="modal merge-dialog">` in two steps; the head
  names the source ("Merge Tagesgeld (alt)") with the step under it
  (`.modal-head__step`, "Step 1 of 2 · Target"). The body scrolls; the foot
  is a fixed band (`.modal-footer.modal-footer--band`, the one class board 02
  adds: a top rule, the elevated background, the body's padding). Under
  720 px the same dialog is a bottom sheet in the booking drawer's shape
  (full width, at most 88 % high); its foot stacks — the reason a confirm
  waits (`.merge-footer__why`, with "↓ "), the confirm on a line of its own,
  then Back or Cancel — so no account name breaks inside a button.
- **Step 1 — the target.** `.merge-route` names the source with its currency,
  role, buckets, bookings and balance (a depot: buckets and bookings). Every
  other account of the kind is a `.merge-target` radio row (44 px minimum)
  with its name, a muted meta line and its balance. The legal ones come
  first under "Target — receives every booking"; the rest follow under the
  `.merge-sub-caps` "Not selectable (N)", disabled on `--color-bg-muted`,
  each naming every reason as text ("different currency, different
  buckets"). The only legal target is chosen; the chosen row takes UX-DR16
  class 3 (tint plus a 3 px leading edge). A basis line states the rule
  ("Selectable: same currency, same liquidity role, same buckets." — "same
  default buckets" for a depot). With no legal target the step says "No
  account meets the conditions." and the foot offers only Close. An account
  whose name another account of its kind carries — the twins a merge exists
  for — is named, on the source line and on its target row, the way the
  import preview's options name it (F1 below): "Verrechnungskonto · at
  Depot 1", a depot "Sparplan · with Giro" (the closing act, #328).
- **Step 2 — the preview of exactly that pair, cash.** `.merge-route`
  "Source → Target" with the target's currency and role; the balances as a
  sum in `.merge-identity` (source + target = target after, the result
  marked by the accent edge) with the balance if the equal bookings are
  removed under it; a basis line (as of today, computed from the bookings,
  checked before saving); `.merge-counts` (bookings that move, transfers
  dropped, set balances adjusted and dropped, equal bookings, and — board 13
  — the linked depots that move); the restated set balances as a table
  (Date · Account · Set · + other account · After), each only where the
  merge changes it; the equal bookings as `fieldset.merge-choice` with its
  table and two `.merge-option` radios, **neither checked**, each stating
  the balance it leads to — "remove as duplicates" also naming, in a muted
  line, what it changes outside the two accounts (board 13); then a note
  (the former names the target gains) and an attention note (the source is
  deleted; cannot be undone; journaled). The figures that depend on the
  choice follow it, and read "keep both" until one is made.
- **Under 720 px the two tables become two-line rows** (`.merge-lines`):
  "date · account" over "set + other = **after**", and "date · kind" over
  the amount and where it stands. Exactly one of the two forms is displayed
  (`.merge-wide` / `.merge-narrow`).
- **The depot variant** has no balances: its route names the target's
  buckets, its counts the bookings that move, the security transfers
  dropped and the equal bookings; "Affected positions" is a table with, per
  position the source holds, the quantity as "source + target →" over the
  after figure, and the average cost and the realized result as
  "source · target →" over theirs ("—" where the target holds none); a basis
  line; and — board 13 — one line per split whose combined rounding differs
  from the two rounded apart, with its date and ratio. Its note adds that
  the target keeps its cash account.
- **The confirm** is `.button-danger` "Merge into <target>" at the band's
  end. While the equal bookings' choice is missing it is disabled —
  `.button-danger:disabled` at 45 % opacity with the not-allowed cursor,
  never merely pale: its reason stands beside it as text ("Choice for 2
  equal bookings missing"). Confirming applies the plan the preview's digest
  covers, closes the dialog and reports the result inline above the table
  (`AppShell.inline_result`, a note: "Merged X into Y: 3 bookings moved, 3
  removed."), until the next action or its dismiss.
- **A changed plan** re-renders step 2 with the fresh preview under an
  attention note — "The accounts changed while the preview was open.
  Nothing was merged; the preview now shows the new state." — and a line
  naming what changed ("balance of Tagesgeld 8,400.00 → 8,450.00 EUR").
  **A choice made before does not survive** (decided here, design pass
  Part 2's open point): a changed plan is a new question, so the confirm
  waits again.
- **A refusal the preview finds** (a position whose buckets differ between
  two depots, say) is a problem note in step 2 — the reason in the
  operator's words, each refused position with both bucket sets, the remedy,
  and **Check again** — and the foot offers Back and Close, never a confirm.
  A refusal that means particular bookings names each on a
  `.merge-refusal__position` line, the account bold, the date and the number
  last (board 14, L3–L5 review round): "Set balance of **Tagesgeld (alt)** on
  2025-06-30 · no. 4711" for a set balance that still carries an import hash
  or whose adjusted amount the amount column cannot hold, and "Buy (Sell)
  without an amount in **<account>** on <date> · no. <id>" for the booking
  that makes it so, whose remedy is to record that booking's amount.
- **Live regions:** one `role="status"` region for the changed-plan note and
  one `role="alert"` region for a refusal of the confirm just pressed, both
  present before any note (UX-DR17: politeness per region, never per note).
- **A link to a merged-away security** lands on the survivor with board 03's
  note at the top of its detail ("The link led to a security that was merged
  into this one on <date>."), and a benchmark naming one redirects the
  Wealth page to the survivor with the same note under the performance head
  (board 13); both dismissible, both gone with the next navigation, both
  shown only when the merge records say so.
- **Dialog count:** the lifecycle adds three native dialogs (rename, merge,
  and Accounts & depots' "Cannot delete"), all on the `ModalDialog` hook,
  none with `aria-modal`. The Overlays bullet's record of nine (2026-09-15)
  now reads fifteen `<dialog>` elements in `lib/portfolixir_web/`, still
  with zero `aria-modal`.

## Amendment 2026-09-26 — Security merge — target, identity, preview *(Sprint 16 pick G3-A, issue 608, ADR-0050 §8, §9, §10, §12)*

Board `mockups/ux-design-2026-09-24/03-security-merge`, variant A (the
owner's pick, plan D-5). Built by Sprint 16 Lane L5b in
`PortfolixirWeb.Securities.MergeDialog` (the state and step 1) and
`PortfolixirWeb.Securities.MergePreview` (step 2). The flow is G2-B's
anatomy — the same `<dialog class="modal merge-dialog">`, band foot, bottom
sheet under 720 px, live regions and changed-plan rule — and this amendment
records only what the security adds.

- **Entry.** The row menu's "Merge into…" (the `:merge` glyph) sits after
  "Mark as benchmark" and before Delete, not danger-coloured. "Cannot
  delete" offers it too, as a ghost button under a muted line saying what a
  merge moves, where bookings or quotes are what block the delete; where a
  policy rule or a research entry blocks it, a merge would be refused as
  well, and the dialog stays as it was.
- **Step 1 — the target is searched, not listed.** The securities list is
  too long for G2's radio list, so `.merge-route` names the source (ISIN,
  currency, bookings, created date) above a `.search-field` ("Name, ISIN,
  WKN or ticker", at most 100 characters); the matches (at most 25, the
  source left out) are G2's `.merge-target` rows, each with its bookings
  count and a meta line (ISIN · currency · asset class, plus "Benchmark" or
  "Retired"). The legal ones come first under "Target — receives bookings,
  quotes and settings"; the rest under "Not selectable (N)", disabled, each
  naming its reasons as text ("different currency", "only one of the two is
  a benchmark", "retired", "other quote basis"). A single legal match is
  chosen; nothing else is. The basis line states the rule: "Selectable: the
  same currency, both or neither a benchmark, the target not retired; with
  quotes also the same “treat synced quotes as raw”. The preview checks
  everything else."
- **Step 2 — two cards, because the names can be equal.** `.merge-pair`
  sets the source and the target side by side (a 1fr · arrow · 1fr grid,
  stacked with a ↓ under 720 px), each card a role line in 10.5 px caps —
  "Source · deleted" in `--color-danger` (`.merge-pair__role--gone`),
  "Target · stays" muted — then the name, the ISIN in mono, and "N bookings ·
  created <date>". Nothing else tells two equal names apart.
- **The ISIN choice (G3-A)** is `fieldset.merge-choice` "ISIN afterwards"
  with two `.merge-option` cards, **neither checked**: "Keep <target ISIN>"
  tagged "the target's ISIN" ("<source ISIN> becomes a former ISIN of this
  security."), and "Adopt <source ISIN>" tagged "the source's ISIN"
  ("<target ISIN> becomes a former ISIN; the target carries <source ISIN>
  afterwards."). The tag is `.merge-option__tag` (11 px, muted, after the
  title). Only when Adopt is chosen does `.merge-option-field` follow that
  card — "ISIN change on", an ISO date field in mono, today by default,
  with its `.field-error` at the field. The fieldset is absent when the
  engine says no choice is required (the two share an ISIN, or one has
  none).
- **Everything that follows the choice is one form** (board 03, why A): the
  holdings as G2's `.merge-identity` sum in shares — "Source + Target =
  Holdings afterwards" (the sides carry their own gettext context, "merge
  side", because a bare "Target" is the allocation column's "Soll") — with
  the figure if the equal bookings go under it; a basis line (every depot,
  as of today, from the bookings; the sum holds per depot on every day and
  is checked before saving); `.merge-counts` (bookings that move, equal
  bookings "— choice below", days with quotes in both "— the target's
  applies" and how many of them manual, the source's settings that move and
  are dropped, the events that move); the equal bookings as G2's
  `fieldset.merge-choice`, its table cut to three rows with "Show the other
  N pairs" (`.merge-more`) and the two unpreselected options.
- **Four tables, each only when it has rows** (`.merge-table`, a cell's
  reason muted under its value): the colliding **manual** quotes ("Date ·
  Target · applies · Source · dropped", the source's struck through in
  `.merge-table__drop`; the synced collisions are only counted, the rest go
  to the manifest); the source's settings in active, draft and archived
  plans (category per tree, position targets, position buckets), each with
  "moves" or "is dropped" and why; the events that stand the same in the
  target ("both stay", with where a duplicate is deleted afterwards); and
  the master data that differ ("Field · Source · Target · Afterwards", with
  "adopted: the target had none." where the target takes a value). Then a
  note (an import that names the source books to the target) and the
  deletion warning.
- **The confirm** is "Merge into <target>" (`.button-danger`), disabled with
  its reasons beside it while the ISIN or the duplicates' choice is missing
  ("Choice for the ISIN missing · Choice for the equal booking missing"). It
  applies `plan_digest` with both choices and `isin_changed_on` (sent only
  for Adopt), closes the dialog, opens the survivor's detail and reports the
  result inline (`AppShell.inline_result`, a note: "Merged X into Y: …"),
  kept through that one navigation. A write the database refuses (an ISIN
  whose check digit is wrong, say) is a problem in the `role="alert"` region
  quoting the refused field; nothing is merged.
- **A refusal** is one problem note that names **every** failed guard: the
  first as "Merging is not possible: …", the rest as "Also: …" — the
  currency pair, the research entries with their count and newest date, the
  policy rules as a list of links (`.merge-refusal__rules`, each rule by name
  with its state and view, G6-A's reference) plus "A rule that has been in
  force keeps its subject as part of its history.", a split one side lacks
  with its date, ratio and the side's earlier booking or quote, a split that
  would restate a depot it did not restate before. Where the reverse merge
  passes, the remedy says so ("merge the other way — <ISIN> into this
  security") and **Merge the other way** opens that pair's preview; where it
  is refused too, "The other way is refused too: …" and "No direction is
  possible; both securities stay unchanged.", with no remedy the version
  does not have. A split mismatch offers **Check again** after its remedy;
  two ratios on one day say to delete the split with the wrong ratio in the
  Transactions tab (board 03, board 14 ④), and that remedy speaks alone. A
  source split that still carries an import hash is named "Split on <date>
  · no. <id>" with its remedy (change its kind back, or delete it) and
  **Check again** (board 14 ③).
  The foot offers Back and Close, never a confirm.
- **The survivor names its history** on its detail overview's basis line,
  after the asset class: "former ISIN <ISIN> (until <date>)" and "merged on
  <date> from “<name>” (then <ISIN>)" — one clause per merge record, readable
  without a click. The clause's date links that merge's entry in the merge
  records on Accounts & depots, as the account sub-line's does (Sprint 17
  V1, G2-A ⑤).
- **Dialog count:** one more native dialog; the lifecycle's record above now
  reads sixteen `<dialog>` elements in `lib/portfolixir_web/`, still with
  zero `aria-modal`.

## Amendment 2026-09-26 — Import preview after ADR-0050 — what each row will do *(Sprint 16 picks G4-A and G4b-A, issue 884, ADR-0050 §2–§5)*

Board `mockups/ux-design-2026-09-24/04-import-memory`, variant A (the
owner's pick, plan D-5), and board `04b-import-memory-ambiguity` (drawn in
the batch before the code: F1 as a before/after, G4b variant A recommended
and built, open to a comment naming B or C). Built by Sprint 16 Lane L5b in
`PortfolixirWeb.ImportsLive`.

- **A mapping row reads left to right as source, count, choice.** Each cash
  and depot row of the mapping step is a `.mapping-row` (grid, aligned to
  the top): the file's name, then `.mapping-count` — "N already imported ·
  K internal transfers dropped · **M new**", or "**nothing to create**" when
  none of the row's bookings is new — then `.mapping-target`, the select with
  its notes under it. Each segment shows only when its count is above zero;
  board 04 draws the transfer segment ("2 interne Umbuchungen entfallen"),
  added by the L3–L5 review round (F2). The count is the apply's own run
  under the prefill, rolled back: "already imported" is every layer that
  skips a booking (content hash, a merge's retired hash, an equal booking by
  its economics), so a file saved again after a merge reads "nothing to
  create". Under
  720 px a row is one column (source, count, choice, notes; a depot's cash
  select last).
- **Notes under the select say only what is not obvious** (`.mapping-basis`,
  12 px muted): "matched by a former name — <account>, formerly “<name>”"
  when a former name did the prefill; "no account under this name; it is
  created only with its first new booking" when "+ Create new" has nothing
  new to create (since 2026-10-08 only where such a row still shows its
  select, see below). A file with nothing new at all says once, at the head
  of the preview, how many entries are already imported and how many
  internal transfers are dropped, then: "The import creates nothing: no
  booking, no account, no depot, no security."
- **A re-drop with nothing new leads with that note and asks for no mapping
  it does not need** *(2026-10-08; issue 1168, Sprint 20 PR α A5; board
  `mockups/ux-design-2026-10-07/01-import-preview` ②, before/after)*.
  - **The note leads.** The nothing-to-import `note` data note
    (`data-role="nothing-to-import"`) stands under the format line and
    before the cards, outside the apply form, said once; nothing repeats it
    above the confirm. It shows when no booking of the file is new and the
    import recognises something (a hit on any layer, or a dropped transfer).
  - **A mapping row with no new booking shows no select**, in any file, the
    rule being per row. Its count keeps "N bookings already imported ·
    **nothing to create**"; in the select's place `.mapping-target` holds one
    `.mapping-basis` line (`data-role="mapping-nothing-new"`), the #923
    security row's anatomy: "No mapping needed: the import books nothing
    under this name." / "Keine Zuordnung nötig: Der Import bucht unter diesem
    Namen nichts." The notes under a select (a former-name match, "+ Create
    new" creating nothing, the remember box) give way with it. A depot row
    loses its cash select too, and above 720 px takes the cash rows' two
    columns (`.mapping-row.depot:has(> .mapping-target:last-child)`, under
    `min-width: 721px` so it cannot override the 720 px one-column block).
  - **Two rows keep their selects whatever their count:** a name the stored
    history never saw (its note and its choice stay, as above: it is counted
    missing until chosen), and a cash row that a depot row still showing its
    selects names as its cash account (`"pp:<name>"`), because that depot's
    link reads it. The exception follows the depot's current choice: once
    the depot settles against an existing account instead, the cash row
    shows the line.
  - **What Apply sends is unchanged.** A row with no select carries its
    choice as hidden inputs under the select's names — `cash[<key>]`,
    `depot[<key>][target]`, `depot[<key>][cash]` — so the mapping, the
    still-to-map hint and the apply's parameters read what they read before.
    One case could not be confirmed before and can now: a depot row with no
    new booking whose file names no cash account for it (a depot that only
    ever received deliveries) is not asked for one and is passed to the apply
    as an undecided row with nothing new, which resolves the name itself and
    holds it (ADR-0050 §3, §4). "Confirm import" stays enabled; it writes
    nothing and reports every duplicate with its layer.
  - **No bucket tag on a file that creates nothing** (board 01, found while
    drawing 3). When no booking of the file is new, no account is created,
    so the "Bucket tag for new accounts" panel is not shown; the absent
    field leaves the mapping's value as it was, and the apply tags nothing.
- **The bucket tag starts empty** *(2026-10-08; issue 1174, Sprint 20 PR α
  A5; board `mockups/ux-design-2026-10-07/01-import-preview` ⑦ and its
  found-while-drawing item 5)*. The panel `#import-bucket-tag` ("Bucket tag
  for new accounts" / "Bucket-Tag für neue Konten") offers the tag rather
  than promising it: the sentence over the field reads "Optional: a bucket
  tag for the accounts this import creates." / "Optional: ein Bucket-Tag für
  die Konten, die dieser Import anlegt."; the field starts empty and shows
  its placeholder, "e.g. PP Import" / "z. B. PP Import"; the closing line
  about reusing a bucket and the tags of mapped accounts is unchanged. The
  "No tag — leave the new accounts untagged" checkbox is gone: the empty
  field is no tag, as it always was. An import therefore creates no bucket
  unless the operator names one, and never labels a converted bank file a
  Portfolio Performance import. What Apply sends is unchanged: an empty or
  blank field reaches the apply as no tag.
- **The counts by kind add up to "Entries"** *(2026-10-08; board
  `mockups/ux-design-2026-10-07/01-import-preview`, found while drawing 2)*.
  A refund a row splits off counts under its own kind
  (`Preview.counts_by_kind/1` reads the companions), as the "Entries" card
  always counted it: a file whose dividend splits off a refund reads
  "Einträge 3" over "Einlage 1 · Dividende 1 · Steuererstattung 1".
- **A fresh instance's portfolio record is named** *(2026-10-08; issue 1173,
  Sprint 20 PR α A5; board `mockups/ux-design-2026-10-07/01-import-preview`
  ⑥)*. The page passes no portfolio; on an instance with none, the apply
  creates the internal default one (`Portfolios.default_portfolio/1`,
  ADR-0024) and binds everything to it. Only then, a second muted line
  stands under the format line (`<p class="muted"
  data-role="import-portfolio">`, no CSS of its own): "No portfolio record
  yet: the import creates “Default” (EUR) and books into it." / "Noch kein
  Portfoliodatensatz: Der Import legt „Default“ (EUR) an und bucht darin."
  "Portfolio record" / "Portfoliodatensatz" is the word of the admin list
  "Portfolio records (compatibility)" under Accounts & depots, where the
  record shows again. The name and the currency are placeholders filled from
  what `default_portfolio/1` creates (`Portfolios.default_portfolio_attrs/0`):
  stored data, like a bucket name, and not translated. With a record there
  is nothing to say (UX-DR2), and the line is absent. The companion's
  `first_setup` prompt says the same: accounts and imports bind to the
  earliest record, which the first import or account creates as "Default"
  (EUR).
- **A row none of whose bookings is new needs no decision** — the account
  rows' rule (board 04, note 4: an ambiguous cash or depot name with nothing
  new is left undecided and blocks nothing), and since 2026-10-06 the
  security rows' too *(issue 923, Sprint 19 PR β B4; board
  `mockups/ux-design-2026-10-04/09-import-correction` ③, before/after)*.
  When every booking of a security the preview asks a decision for (an
  ambiguous or vetoed match, identifiers pointing at different securities,
  or a creation that would strand configuration) is one the apply skips
  before it resolves a security — already imported by its content hash, a
  merge's retired hash or an earlier row of the same file under the same
  security, or an unimportable line such as a zero amount — the row takes
  the account rows' anatomy: `.mapping-count` under the file's name with the
  account rows' own strings ("6 Buchungen bereits importiert · **nichts
  anzulegen**"), then `.mapping-target` with the select and one
  `.mapping-basis` line: "Keine Entscheidung nötig: Der Import bucht für
  dieses Wertpapier nichts. Ein hier erfasster ISIN-Wechsel wird trotzdem
  wirksam." The decision paragraph, the candidate list and the
  configuration acknowledgment give way. The select stays, with its
  ISIN-change box when the chosen security offers one, because a recorded
  ISIN change still runs at the start of the apply (ADR-0050 §3); left as it
  is, the row passes nothing to the apply. It no longer disables Confirm, is
  not named in the still-to-map hint, and the plain creations' summary
  ("N neue Wertpapiere werden angelegt") does not count such a security
  either. Only those layers count here — an equal booking found by its
  economics, or an internal transfer, is judged on resolved ids after the
  decision, and a layer added later fails closed — so a security with one
  new booking keeps its decision. A key-collision row keeps its text and its
  block whatever its bookings: the apply refuses that file (no CSS of its
  own; the rules of `.mapping-row` apply). *The basis line deviates from
  board 09*, which reads "Eine gewählte Zuordnung, etwa ein ISIN-Wechsel,
  wird trotzdem ausgeführt.": on such a row a remap books nothing and
  "+ Neu anlegen" creates nothing, so the line promises only what still
  takes effect, a recorded ISIN change (the #923 review round).
- **"Remember this mapping" (G4-A)** is `.mapping-remember`, a checkbox in
  the row, **ticked by default**, shown only where the operator changed a
  prefill onto a differently named account and remembering is possible. Its
  line (12 px muted, indented under the label, the box's
  `aria-describedby`) says what happens: "“<name>” becomes a former name of
  <account>; once a booking under the name has been imported, a future
  import maps the name by itself." *(amended 2026-10-08, the α closing act's
  EC-F2: a name no booking was imported under is asked again until one
  is)*, or, where the name
  is another account's former name, "…and is then no longer a former name of
  <other>." (the move ADR-0050 §4 added). Unticked: "Holds for this import
  only. A future import suggests “<prefill>” again." Where the name is
  another account's live name, no box: a muted line says the choice holds
  for this import only and links Accounts & depots, where a merge or a
  rename changes it. The box posts through the existing
  `remember[<group>][<opaque row key>]` path.
- **Same-named accounts are told apart in the options (F1).** An option
  whose name another option of the same list carries adds, after a middle
  dot, what differs: a cash account its linked depots ("at Depot 1", "no
  depot"), else its currency, else "created <date>"; a depot its cash
  account ("with Giro"), else its created date; "no. <id>" only when nothing
  else differs. Unique names are unchanged. An ambiguous row gets no prefill
  ("Decide…") and an attention note naming the candidates by the same labels,
  saying the choice holds for this import and cannot be remembered while
  more than one account carries the name, with the Accounts & depots link.
- **A name the stored history never saw gets no prefill** *(2026-10-08;
  issue 904, Sprint 20 PR α A3; board
  `mockups/ux-design-2026-10-07/01-import-preview` ①, pick L1 = A; ADR-0050
  §2 as amended on 2026-10-07)*. **The signal:** a file cash-account or
  depot name none of whose rows has a content hash held by a live
  transaction or a retired hash, while another name of the same file, in
  the same portfolio, has such a row (`Imports.reimport_counts/2`'s
  `unseen_names`) — typically an account or a depot renamed in Portfolio
  Performance, whose rows all miss because names are hash inputs. A repeat
  inside the file and an equal booking found by its economics do not count;
  names compare exactly. **The row:** no prefill, whatever resolution would
  give — "+ Create new", or the account a live or a former name of another
  account leads to — so the select stays on its empty state, "Decide…" /
  "Entscheiden…" (the ambiguous row's msgid). Under the select, in the place
  the ambiguous note takes, ONE `attention` data note
  (`data-role="mapping-unseen-name"`): "No booking under this name has been
  imported yet, though the file's other names have. If the account was
  renamed in Portfolio Performance, choose the existing account here;
  otherwise “+ Create new”." / "Unter diesem Namen ist noch keine Buchung
  importiert, unter den anderen Namen dieser Datei schon. Wurde das Konto in
  Portfolio Performance umbenannt, hier das bestehende Konto wählen, sonst
  „+ Neu anlegen“."; a depot row says "depot" / "Depot" in both places.
  **Counted missing**, even when none of its bookings is new (unlike an
  ambiguous row, whose hash hits resolve nothing — here there are none): the
  row is named in the still-to-map hint
  (`#import-missing-hint`, "cash account: <name>" / "target depot: <name>"),
  which describes the disabled confirm (`aria-describedby`); the confirm
  unlocks once a choice is made. **The note stays after a choice**, so the
  row does not reflow; a choice of a differently named account shows the
  "remember" box, ticked (G4-A), and no "matched by a former name" line, as
  the row was not matched. An ambiguous row that is also unknown carries
  both notes, this one first. **Unaffected:** a first import, a file in
  which no name has a hit, and a file whose every name has one are
  prefilled as before. **Under 560 px** this note and the ambiguous note
  (board 01's found-while-drawing item 8) join the correction note's
  selector list: the body wraps under the glyph and the word and takes the
  note's full width; neither has a rule of its own.
- **Same-named securities are told apart the same way (the closing act,
  UAT-13).** Wherever the operator picks or names a security — the Risk rule
  dialog's subject list, the booking drawer's security list, the row menus
  of Securities and of Transactions — a security whose name another security
  of the same list carries adds, after a middle dot, its ISIN, else its
  ticker, else "no. <id>": the first feature present and different on every
  twin. Unique names are unchanged. Twins are exactly the case a security
  merge exists for, so the dialog that ends them is not the only place they
  can be told apart.
- **"+ Create new" for a name the guard refuses (G4b-A)** stays in the list,
  **disabled**, its own label saying why: "+ Create new: <name> — not
  possible: an account already has this name" / "a former name of
  <account>" / "the name of N accounts". Only a row with new bookings shows
  it so; a stored choice that points at a name taken since counts as not
  made. Nothing the list offers can fail the import at the end.
- **The result adds three lists in `.import-skipped`'s existing form** (a
  muted sentence, then the rows): "Remembered for future imports:" with one
  line per name ("“X” is now a former name of Y.", "…and no longer of Z." for
  a move, or "was not remembered: it is the name of …"); the rows booked on
  or before a set balance a merge adjusted, each "Row N: <what> — set
  balance of <account> on <date>"; and the internal transfers skipped, each
  "Row N: <kind> <date> · <from> → <to>".
- **The skipped duplicates are grouped by the layer that caught them**
  (`.dup-group`, a `<details>` per layer with the count in bold tabular
  figures and the reason): identical rows of a re-import — the expected
  mass — stay **closed**; a retired hash and the economic layer stand open.
  Each row reads "Row N: <kind, date, security, amount, accounts>".
- **Every list of the done page names a row as the file shows it, in the
  page's words** *(2026-10-08; Sprint 20 PR α A5; board
  `mockups/ux-design-2026-10-07/01-import-preview`, found while drawing 1)*.
  A refund split off a row is named by that row and its kind — "Row 7 (Tax
  refund)" / "Zeile 7 (Steuererstattung)" — never by its internal id
  ("7.tax_refund.1"), and among the records already booked it is described
  like any row ("Steuererstattung 16.03.2026 · Synthetic AG · 1,00 EUR ·
  Test-Cash"), not as "a row of the file". The unimportable records head
  with a real plural, "Skipped one unimportable record:" / "Skipped
  %{count} unimportable records:" ("Ein nicht importierbarer Datensatz
  übersprungen:" / "%{count} nicht importierbare Datensätze übersprungen:"),
  and each reason is the page's, read off the entry
  (`Imports.unimportable_reason/1`), never the applier's English with a
  ledger field: "<Kind> without an amount — nothing to book" / "<Art> ohne
  Betrag — nichts zu buchen", "<Kind> is never imported" / "<Art> wird nie
  importiert", and for a refund whose row was not imported "the row itself
  was not imported" / "die Zeile selbst wurde nicht importiert".
  **The records no security resolves for** head with a real plural too,
  "One record could not be resolved to a security and was not imported:" /
  "%{count} records could not …" ("Ein Datensatz konnte keinem Wertpapier
  zugeordnet werden und wurde nicht importiert:" / "%{count} Datensätze
  konnten … wurden nicht importiert:"), and say why in the page's words
  *(amended 2026-10-08, the α closing act; read off the result's `cause`,
  the result's English `reason` unchanged)*, naming securities by name in
  the page's quotes, never by record number or ADR: "a likely match,
  “Foo AG”, differs on a stronger identifier — possibly an ISIN change not
  recorded yet" / "ein wahrscheinlicher Treffer, „Foo AG“, weicht bei einem
  stärkeren Identifikator ab — möglicherweise ein noch nicht erfasster
  ISIN-Wechsel"; "different identifiers point at different existing
  securities: “A” and “B”" / "verschiedene Identifikatoren zeigen auf
  verschiedene bestehende Wertpapiere: …"; "2 existing securities share
  this identifier: WKN" (or "ticker and currency", "name and currency") /
  "2 bestehende Wertpapiere teilen diesen Identifikator: WKN" ("Ticker und
  Währung", "Name und Währung"); and "creating it would leave strategy
  configuration (category assignments or position targets) stranded on: …"
  / "das Anlegen würde Strategie-Konfiguration (Kategorie-Zuordnungen oder
  Positionsziele) stranden lassen auf: …".

## Amendment 2026-09-26 — The author of a policy rule *(Sprint 16 pick G12.1-A, E25 S7, G30)*

Board `mockups/ux-design-2026-09-24/12-e25-new-marks`, G12.1 variant A (the
owner's pick, plan D-5), as built in `PortfolixirWeb.RiskLive` and
`PortfolixirWeb.Risk.PolicyRuleDialog`. Every rule version stores its author,
derived from the write's actor: the Risk page writes as the operator, an API
or MCP token as the agent (decision T-8).

- **The word, only at the exception.** A finding whose version in force the
  agent wrote ends its words line (`.policy-rule__words`) with "· Agent", the
  research log's word for the same fact ("#16 · 22.09.2026 · Agent"). A
  hidden lead (`.visually-hidden`: "Version in force by:" / "Version in Kraft
  von:") tells a reader what the word is. The operator's own rules carry no
  word, so a portfolio without the agent's rules reads exactly as before.
- **Scheduled and retired rules alike.** The muted line of a scheduled rule
  (its coming version) and of a retired rule (its last version) ends with the
  same "· Agent", hidden lead "Version by:" / "Version von:".
- **No badge, no colour.** Every pill in the findings table is taken:
  `.badge--neutral` is "met", dashed means undetermined, accent means "yours"
  and warning is a severity. The word stays in the muted line, survives
  forced colours as text and wraps with its line at 390 px.
- **The dialog.** Every entry of the version list names its author after the
  severity: "· Operator" or "· Agent". A version stored before authors
  existed and without a journaled creation names none.
- **A rename is no version** (D-6) and moves no mark: the word follows the
  line, not the name; the journal names who renamed.
- **The title stays "Own rules".** It sets the portfolio's rules apart from
  the lens's generic thresholds (ADR-0049 §7), not from the agent.

## Amendment 2026-09-26 — Stored text with invisible characters *(Sprint 16 pick G12.2-B, E25 S7, G20)*

Board `mockups/ux-design-2026-09-24/12-e25-new-marks`, G12.2 variant B (the
owner's pick, plan D-5), as built in `AppShell.invisible_text_note/1`. Every
writer now refuses the characters an operator cannot see (tag characters,
bidirectional controls, the other invisible format characters, runs of
variation selectors); the note marks a row stored before that rule.

- **One note, whatever the count.** An `attention` data note
  (`AppShell.data_note`, glyph, word and colour) where the stored text
  renders: "The text contains 2 invisible characters." or, for a name, "The
  name contains 1 invisible character." It carries no live-region role; a
  list of entries is one region, as rule 4 of the data note says.
- **The remedy is a child of the note.** A research entry or the thesis:
  "The log only appends: an entry that supersedes this one carries the text
  without them." and the link-button "Append an entry that supersedes #n",
  which preselects the entry in the append form's "Supersedes". A security's
  name: "Typed in anew, it is clean." and "Edit master data", the head's own
  action once more. Where the text is edited in place (a booking's notes, a
  rule's name and note, a view's, a bucket's and a category's name) the
  sentence alone; an appointment's note says it is corrected over the API or
  MCP, since the page has no appointment edit.
- **The text behind a disclosure.** `details.perf-table-disclosure`, "Text
  with the characters made visible" / "Name with …", closed by default,
  holding each affected text as a `p.mono` with every such character spelled
  `[U+XXXX]` — the spelling the MCP companion hands the agent. **The one
  `app.css` rule of the pick:** `.data-note__body .mono { margin:
  var(--space-1) 0 0; white-space: pre-wrap; overflow-wrap: anywhere; }`, the
  wrap `.research-entry__body` has, so line breaks stay and a run of escapes
  cannot overflow the note at 390 px.
- **Where it stands.** In the research entry under its body (body and
  invalidation condition counted together) and under the thesis text; in an
  appointment under its note; under the security detail pane's head; in the
  booking drawer above "Costs and note", which then stands open, and in its
  split state (G12.3-A), which has no such disclosure, above the open Notes
  field (the Sprint 16 closing act); in the rule
  dialog under its first hint (the name and the version's note, each its own
  note); after the inline rename form of a view, a bucket and a category;
  in the rename dialog of a cash account or a depot (Lane L5a, G1-A above)
  after its form, following the field, and — the one list that is marked —
  inside its open "Former names" disclosure, above the list, when a former
  name carries such characters (Sprint 18 H8.5 = A, issue 966; see that
  amendment). Other lists, selects, headings and the history's "Notes"
  column stay unmarked.
- **Stored text inside running text is isolated in `<bdi>`**: the stored
  subject of a rule's words line, a retraction's reason in the thesis card,
  and in the rule dialog the rule's name in its heading and the view's name
  in its first hint (the S7 review round), so a direction control reorders
  at most the stored text. The translated sentence is split around its
  placeholder before the stored text is put in. No picture changes by it.
  Since Sprint 18 (H8.8, issue 968) the results and dialog headings that
  name a stored name are isolated too, through one shared helper
  (`PortfolixirWeb.StoredText`); see that amendment.

## Amendment 2026-09-26 — The error page follows the theme *(the Sprint 16 closing act; board 11 part 4, E25 S2, F68)*

Board `mockups/ux-design-2026-09-24/11-security-visible-states`, part 4,
draws the error page as `PortfolixirWeb.ErrorView`'s one status line
("403 · Zugriff verweigert") in the browser's default rendering: no
stylesheet, so a white page in a dark app. The closing act's screenshot pass
found the dark capture identical to the light one. The conformance repair
keeps the board's content and changes only what every page owes the theme:

- **A document, not bare text:** `<html lang>` in the page's language, both
  colour schemes declared (`color-scheme: light dark`), `app.css` for the
  tokens `body` already sets (background, text colour, font), and the root
  layout's theme script for the stored light, dark and accent choice. An
  error page may carry the static policy, which admits no inline script, so
  the script is served as `/theme-boot.js`, the very code the layout runs
  inline under its nonce (a test holds the two equal).
- **The line alone, on the side gutter:** `main.error-page` (`margin: 0;
  padding: var(--space-4)`) holds the status line and nothing else. A
  designed error page (a layout, a remedy sentence, a way back) stays the
  separate decision the board names.

## Amendment 2026-10-01 — Trades: the facet, the p. a. column, the unmatched sells and the Overview card *(Sprint 17 pick G1-A, issue 984)*

Board `mockups/ux-design-2026-10-01/01-trades-reach`, variant A (the plan's
D-9 pick, adopted by the planning PR's merge), as built in
`PortfolixirWeb.IncomeLive` (the facet) and `PortfolixirWeb.DashboardLive`
(the card). The rules ① to ⑥ of the board's `#proposal` are in `app.css`
under "Trades: reach, the p. a. column and the unmatched sells".

### The facet is "Trades"

- **The switch reads "Trades"**; the URL stays `/cashflow?tab=realized`, so
  links and bookmarks hold. The subtitle names the facet (UX-DR21):
  "Abgeschlossene Trades und ihr realisiertes Ergebnis".
- **The matcher's scope is stated once**, in the facet's opening basis line:
  "Beträge in EUR · FIFO je Wertpapier · alle Depots". The list's own basis
  line (below) does not repeat FIFO or the scope — the board found the two
  lines saying it twice.
- **The top bar reads "Trades" while the facet is open** *(2026-10-07, issue
  1082, Sprint 19 PR γ U2; board `mockups/ux-design-2026-10-04/04-trades`,
  pick J4 A; plan D-4)*. The page title (`#app-topbar-title`, the `h1` of the
  top bar's `aria-live` region) follows the facet, so switching to it
  announces "Trades", and at 390 px, where the subtitle is hidden, the page
  still carries its name. The other three facets keep "Cashflow": titling
  "Erträge" over the "Cashflow" tab would reopen the ambiguity the
  information architecture closed. Nothing else moves: the sidebar marks
  "Vermögen", the area tab reads "Cashflow", the switch reads "Trades" and
  the route stays `/cashflow?tab=realized`. A sidebar entry with its own
  route (J4 C, Sprint 17's G1-B) stays a later option, its costs listed on
  the board. The precedent is the classification page, titled with its
  tree's name.
- **"Realisiert gesamt" is signed** *(2026-10-07, board 04, found while
  drawing 1)*: the lead figure prints with its sign ("-728,00", "+60,00") in
  its gain/loss colour (`.stat .is-positive` / `.is-negative`, issue 637's
  rule); a total that reads "0,00" has no sign and stays in body ink
  (`.is-flat`) — never the accent `.stat strong` gives an unsigned
  magnitude. The sign and the colour are decided on the figure as
  displayed, rounded to its two places (`Format.displayed_sign/2`), so a
  total of 0,004 reads "0,00" in body ink, never in the gain colour. Hit
  rate and holding period are magnitudes and keep the accent.
- **The currency note names the exchange rate** *(2026-10-07, board 04,
  found while drawing 2)*: "1 Verkauf konnte nicht konvertiert werden — kein
  gespeicherter Wechselkurs an seinem Schlussdatum — …", and the facet's ⓘ
  says "Wechselkurs" too, as the Overview card that sends readers here does
  ("Kurs" is a quote). The other two facets' notes are not changed here.

### The p. a. column

- **Position:** directly left of Result, a `.num` column headed "p. a.". No
  ⓘ in the header: `.data-table-wrapper` is its own scroller and would clip
  it.
- **The figure:** the trade's annualized return (`annualized_return`, the
  money-weighted return per year of the trade's own flows, in the trade's
  currency, like the percent under the result it annualizes) as
  ~~`Format.percent` with one decimal and the percent sign~~, in its sign
  colour (`td.trade-pa.is-positive` / `.is-negative`). **Amended 2026-10-07
  (issue 1089, Sprint 19 PR γ U2; board `mockups/ux-design-2026-10-04/04-trades`,
  before/after):** `Format.signed_percent` with one decimal and the percent
  sign glued on — "+17,8%", "-20,0%", the Overview card's form. The
  Accessibility Floor's explicit sign (UX-DR7) outranks the H1 line that kept
  these cells unsigned; the merge of the Sprint 19 plan adopted the reversal.
- **Every figure of the row is signed** *(2026-10-07, issue 1089)*: the
  Result cell prints the result in the base currency through
  `Format.signed_decimal` ("+420,00 EUR") and its percent through
  `Format.signed_percent` ("+42,0%"); a loss keeps its "-". Cost and
  proceeds are magnitudes and stay unsigned.
- **A figure's sign and its colour are decided on the figure as displayed**
  *(2026-10-07, the Sprint 19 PR γ U2 review)*: the value rounded to the
  places it is printed at — two for money (`Format.displayed_sign/2`), one
  for a percent (`Format.displayed_percent_sign/1`). A figure that reads
  zero is directionless: no sign from either side ("0,00", "0,0%", never
  "+0,0" or "-0,00") and `is-flat` instead of a gain or loss colour, in the
  table cells, the phone row's figures and the KPI alike — a break-even
  trade, and a result of a fraction of a cent, read the same. `is-flat`
  carries no colour rule of its own here; the cell keeps its ink.
- **The threshold** is the trade's own holding period, the "Haltedauer"
  cell of the same row: from 365 days the figure, below it the dash. The two
  can never disagree.
- **The dash** (`.trade-pa--na`, rule ①): a muted "—", `aria-hidden`, with
  `cursor: help`; the reason rides the cell's `title` ("Unter einem Jahr
  Haltedauer nicht annualisiert") and a `.visually-hidden` sentence ("nicht
  annualisiert, unter einem Jahr Haltedauer"). A trade held long enough
  whose flows no rate solves (a total loss) carries the same dash with its
  own reason ("Keine annualisierte Rendite: kein Zinssatz löst die
  Zahlungen dieses Trades").
- **Sign colour in this table** (rule ⑥): `#realized-trades-table
  td.is-positive / td.is-negative` restored the colour that `.data-table
  tbody td { color }` took from the bare classes, for p. a. and Result alike;
  `#realized-trades-table td.trade-pa--na` does the same for the muted dash,
  which printed in the text colour (closing act γ D4). *Since Sprint 18
  (issue 1010, pick H4) the sign half is the general `.data-table
  td.is-positive / .is-negative` and the scoped copy is gone; the dash line
  stays — see Amendment 2026-10-03.* *Amended 2026-10-08 (issue 1142):* the
  dash line is the general `.data-table td.trade-pa--na` too, and a trade on
  no cost basis carries the dash in its Result sub-line and p. a. cell — see
  Amendment 2026-10-08 — A return on no cost basis.
- **A reading table** (rule ⑦, settled by the story as board 01 left it,
  closing act γ D9): `.data-table-wrapper > #realized-trades-table {
  min-width: 0 }`, the `.num` cells `nowrap`, the security cell at least 12ch
  and `overflow-wrap: anywhere` — it fits its wrapper and the name and the
  dates wrap, so Result stays in view at 1280 px with the sidebar open
  (before: 1159 px of table in a 1002 px scroller, Result out of view with
  no cue). UX-DR15's scroller stays the fallback, as for the merge records.
  The header "p. a." prints "P. A." under the thead's uppercase, like every
  header of the app's tables; kept.

### The list's basis line

`p.summary-basis[data-role="trades-basis"]` directly under the list (rule
②: 12 px, muted, no margin — `.summary-basis` had no context-free rule, so
the rule is scoped to `#realized-trades > .summary-basis` and the card;
since Sprint 18 the context-free rule exists, issue 1011, and the scoped one
repeats it):
"Einlieferungen eröffnen keinen Lot · Gebühren und Steuern in Einstand und
Erlös · Erträge während der Haltedauer nicht enthalten · p. a. erst ab 365
Tagen Haltedauer". It renders whenever the list or the unmatched-sells note
does, because it is the limit that note points to (UX-DR26).

*Amended 2026-10-07 (issue 1089, Sprint 19 PR γ U2; board
`mockups/ux-design-2026-10-04/04-trades`).* The line names **both** limits of
p. a., because a trade held long enough whose flows no rate solves (a total
loss) has none either: "… · p. a. erst ab 365 Tagen Haltedauer und nur, wo ein
Zinssatz die Zahlungen löst" (English "… · p. a. only from 365 days of holding
and only where a rate solves the flows"). The phone row's "gesamt" points
here for both reasons.

### The unmatched-sells note

- **What:** the sells the FIFO matcher could not pair with a buy, wholly or
  in part — shares that arrived by an inbound delivery open no lot — whose
  unmatched quantity is in no figure; a matched part of the same sell is a
  trade row like any other (closing act γ).
- **Where:** an `attention` data note (UX-DR17) leading `#realized-trades`,
  after the currency-exclusion note when both appear, before the three
  figures (UX-DR25: named where the total is read).
- **Words:** "2 Verkäufe haben für ihre ganze Stückzahl oder einen Teil
  davon keinen zugeordneten Kauf (z. B. aus Einlieferungen): Diese Stückzahl
  ist in keiner der drei Kennzahlen, keiner Zeile und nicht in der Matrix
  enthalten."
- **The disclosure:** `details.perf-table-disclosure`, closed by default,
  summary "Die 2 Verkäufe" ("Der Verkauf" for one), holding `.excluded-list`
  (rule ⑤): a grid of three aligned columns — security, date
  (`Format.date`), quantity ("15,0000 Stück"), the last two right-aligned in
  tabular figures. **Under 560 px** the security takes its own line and the
  date and quantity sit beneath it — the board drew the note at desktop width
  only, and at 390 px the two unwrapping figures squeezed a long name into a
  four-line column. *Amended 2026-10-07 (issue 1074, Sprint 19 PR γ U2):*
  the quantity's word follows U1's count rule through `ngettext` — one unit
  is a unit, any other quantity, a fraction included, is units — so English
  reads "1.0000 unit" and "15.0000 units"; German keeps "Stück" in both
  forms. The count is the quantity as displayed, rounded to its four places:
  a quantity of 0.99996 reads "1.0000 unit", as its digits say.
- **No remedy control** (UX-DR25 clause 3): nothing on the page can supply
  the missing buy.

### The trades phone row *(UX-DR27)*

Under 560 px `#realized-trades-table-wrapper` is `display: none` (the phone
lists' 560 px block) and `#realized-trades-phone-rows` shows: the
transactions shape, two children (rule ③), no logo, no kebab. The body is
the name (600, wrapping) linking to the security's Trades tab over "gekauft
→ verkauft · N Tage"; the figures are the result in the base currency (14
px/600, sign colour) over the period return and, from 365 days, " · x,x %
p. a." (12 px muted, each signed number in its colour). ~~A shorter trade
shows no dash on the phone; the basis line under the rows says why.~~

*Amended 2026-10-07 (issue 1089, Sprint 19 PR γ U2; board
`mockups/ux-design-2026-10-04/04-trades`, before/after).* Every figure
carries its sign: "+420,00 EUR" over "+42,0% · +17,8% p. a.". A trade without
p. a. — under 365 days of holding, or one no rate solves — shows no dash on
the phone; its period return ends in the Overview card's word, "-38,9%
gesamt" / "-100,0% gesamt" (English "total"), the word outside the coloured
figure, and the basis line under the rows names both reasons.
*Amended 2026-10-07 (the PR γ closing act, first-look persona; issue 1089's
"says why at every width"):* such a row also carries the table dash's own
reason as a visually hidden sentence after its figures
(`span.visually-hidden[data-role="pa-absent"]`: "nicht annualisiert, unter
einem Jahr Haltedauer", or "keine annualisierte Rendite, kein Zinssatz löst
die Zahlungen dieses Trades"), so a screen reader at 390 px hears why this
trade has no p. a., as it does on the table row at 1200 px. No rendered
difference: measured at 390 px, Tamarisk's row is 59 px tall and
pixel-identical before and after; the visible "why" stays the basis line.

### The Overview card "Abgeschlossene Trades"

- **Placement:** under the KPI strip, before "Ziel-Abweichungen" — the
  fifth block of UX-DR2 (amended 2026-10-01). It lists **results, not
  activity**: ADR-0022 §7 dropped the raw recent-activity feed, and a sale
  appears here for what it realised, never as a booking.
- **Head:** the `h2` and, in the same `.section-head` row, the
  `.kpi-summary__link` "Alle Trades →" to `/cashflow?tab=realized` (the
  pattern of "Alle Kennzahlen → Bestände"); at 390 px the link wraps under
  the heading, right-aligned, as the board drew. The head has no bottom
  margin (rule ④).
- **Basis line** (rule ②): "Die 5 zuletzt abgeschlossenen · Ergebnis in
  EUR · FIFO über alle Depots, unabhängig von der Ansicht · p. a. erst ab
  365 Tagen Haltedauer" — counting the rows the card shows ("Der zuletzt
  abgeschlossene · …" for one; closing act γ n3). The card covers every depot while the rest of the
  Overview follows the selected view, and the line says so.
- **Rows:** at most five, newest close first, the `.attention-list` of "Off
  target" and "Due": each `a.attention-item[data-role="closed-trade"]` to
  the security's Trades tab, the name over "verkauft 22.09.2026 · 568 Tage";
  the figure slot right-aligned on two lines (rule ④) — the signed result
  with its currency suffix, in its sign colour, over "+10,0% p. a." where
  the trade has an annualized return, else "+8,0% gesamt" (the period
  return) — under 365 days of holding, and where no rate solves the flows (a
  total loss reads "−100,0% gesamt"; the reason rides the facet's dash, not
  the card). The percent is the app's `Format.percent` with the sign glued
  on, no space before "%", as everywhere else (γ n12). The slot
  does not wrap at 390 px; the name may.
- **States:** *pending* — the head and the block skeleton
  (`.section-skeleton`, `aria-busy`, no cue: a sub-second read, UX-DR20),
  only where a sell is booked; *a sale the rates cannot convert* — an
  `attention` note under the head naming it ("1 Verkauf ohne gespeicherten
  Wechselkurs an seinem Schlussdatum fehlt bei den Trades: …" — an exchange
  rate, not a price, γ n4), pointing to the
  backfill under "Alle Trades", where the control is; *absent* — no closed
  trade and no such sale, like "Fällig" without a date, and from the first
  paint when no sell is booked; *failed* — a `problem` note in the card.
- **What it does not carry:** the unmatched-sells note. A sell with no
  matched buy is no trade, so it is not missing from the five; the facet
  names it where the totals are read.

### The security's Trades tab: the closed trades *(Sprint 18 pick H1, issue 1029)*

Board `mockups/ux-design-2026-10-02/01-trades-tab-pa`, "after" (before/after,
no variant), as built in `PortfolixirWeb.SecuritiesLive`
(`trades_tab_panel/1`). Every row of the facet and of the card links here,
and since Sprint 18 the figure they show is on the page they land on — the
human view of `GET /api/v1/securities/:id/trades`'s `annualized_return`. The
board's rules ① to ④ are in `app.css` under "The security's Trades tab".
The open-lots table above is unchanged.

- **Section order:** the heading "Abgeschlossene Trades (FIFO)", the
  unmatched-sells note when there is one, the table
  (`#detail-closed-trades-table-wrap > #detail-closed-trades-table`), the
  phone rows, the basis line. The heading renders whenever there is a closed
  trade or an unmatched sell.
- **Columns:** Eröffnet · Geschlossen · Stückzahl · Ø Kauf · Ø Verkauf ·
  Tage · **p. a.** · Realisierter G/V · %. "p. a." is a `.num` column
  directly left of the result, with "Tage", the threshold it is judged by,
  directly left of it — the facet's placement. No ⓘ in the header: the
  wrapper is its own scroller.
- **"p. a." is one word:** on this tab the header, the phone row's
  "· +10,7% p. a." and the basis line set the abbreviation with a no-break
  space (U+00A0, in the gettext msgids and the German msgstrs), so it never
  breaks between "p." and "a." — the basis line did at 1280 px on the German
  page (repair R6, board
  `mockups/ux-review-2026-10-03/01-contribution-repairs`). The facet and
  the Overview card share the plain "p. a." message and are outside that
  repair.
- **The figure:** `annualized_return`, in the trade's currency like the "%"
  beside it, **signed** with one decimal and the percent sign glued on
  ("+10,7%", "-3,6%"), in its sign colour (`td.trade-pa.is-positive` /
  `.is-negative`). Signed because every figure of this table is signed and
  the Overview card signs the same figure; ~~the facet's p. a. cells stay
  unsigned, the board's stated doubt settled for this table only~~.
  **Amended 2026-10-07 (issue 1089, Sprint 19 PR γ U2; board
  `mockups/ux-design-2026-10-04/04-trades`):** the facet's p. a. cells are
  signed too — the Accessibility Floor's explicit sign outranks this line,
  and the merge of the Sprint 19 plan adopted the reversal. One formatter,
  `Format.signed_percent`, signs the figure on the tab, the facet and in
  `signed_pa/1`.
- **The dash:** the facet's (`.trade-pa--na`, muted, `aria-hidden`,
  `cursor: help`), with the same two reasons in the `title` and the same
  `.visually-hidden` sentences — under 365 days of holding, and "Keine
  annualisierte Rendite: kein Zinssatz löst die Zahlungen dieses Trades"
  for a trade held long enough whose flows no rate solves (a total loss).
- **Sign colour** (rule ①): `#detail-closed-trades-table td.trade-pa--na`
  restores the muted dash that `.data-table tbody td { color }` takes from
  the bare class. *(Amended 2026-10-08, issue 1142: the general
  `.data-table td.trade-pa--na` replaced this scoped copy.)* The sign colour of p. a., the result and "%" — and of the
  open lots above — is the general `.data-table td.is-positive /
  .is-negative` of issue 1010 (pick H4, Amendment 2026-10-03), which made
  this rule's two sign lines redundant; they are gone. *Amended 2026-10-07
  (the Sprint 19 PR γ U2 review):* every signed cell of the tab — the open
  lots' four amounts and their "%", the closed trades' p. a., result and
  "%", the phone row's figures — takes its class from the figure it shows,
  rounded to its places, as on the facet; a figure that reads zero is
  unsigned and `is-flat`, and the "%" columns take their colour from the
  percent itself, no longer from the amount beside it.
- **The unmatched-sells note** (rule ②, UX-DR25): the facet's `attention`
  data note (`#detail-closed-trades-note`, `data-role="trades-unmatched"`),
  leading the section where the quantity is missing, in the facet's words
  adapted to the tab: "2 Verkäufe haben für ihre ganze Stückzahl oder einen
  Teil davon keinen zugeordneten Kauf (z. B. aus Einlieferungen): Diese
  Stückzahl ist in keinem abgeschlossenen Trade enthalten." ("1 Verkauf hat
  … (z. B. aus einer Einlieferung) …" for one). Its closed disclosure "Die 2
  Verkäufe" ("Der Verkauf") lists each sell, newest first, as date ·
  quantity ("12,0000 Stück") in `.excluded-list` — **two columns at every
  width**, because the security is the page's own. No remedy control. It
  replaces `.detail-tab-warning` ("möglicherweise fehlen Daten"), whose rule
  is gone with its last user.
- **The basis line** (rule ③, UX-DR26): `p#detail-closed-trades-basis`, the
  pane's own `.detail-tab-hint` voice with a top margin: "Über alle Depots ·
  Einlieferungen eröffnen keinen Lot · Gebühren und Steuern im G/V, nicht in
  Ø Kauf und Ø Verkauf · Erträge während der Haltedauer nicht enthalten ·
  p. a. erst ab 365 Tagen Haltedauer". It differs from the facet's line in
  one link: this table shows gross average prices, not cost and proceeds. It
  renders whenever the table or the note does. *Amended 2026-10-07 (issue
  1089, the Sprint 19 PR γ U2 review):* the line names both limits of p. a.,
  as the facet's does — "… · p. a. erst ab 365 Tagen Haltedauer und nur, wo
  ein Zinssatz die Zahlungen löst" (English "… · p. a. only from 365 days of
  holding and only where a rate solves the flows"), "p. a." with its
  no-break space — because the phone row of a long trade no rate solves (a
  total loss) shows its period return alone and points here.
- **Only delivered-in shares sold** (state N1): the heading, the note and
  the basis line, no table. The empty sentence ("erfasse zuerst Käufe und
  Verkäufe") is kept only for a security with no trade, no open lot and no
  unmatched sell.
- **Under 560 px** (rule ④, UX-DR27): the wrapper is hidden by the phone
  lists' 560 px block and `ul#detail-closed-trades-phone-rows` shows the
  facet's trades row **without the name**, which the page already says —
  two children, no logo, no kebab: "06.02.2023 → 18.06.2025" over
  "30,0000 Stück · 863 Tage"; on the right the result with the trade's
  currency ("+502,20 EUR", 14 px/600, sign colour) over "+27,1% · +10,7%
  p. a." (one decimal, signed, each number in its colour). Under 365 days, or
  with no rate, only the period return; no dash on the phone, the basis line
  says why. Ø Kauf and Ø Verkauf are not on the phone, as cost and proceeds
  are not on the facet's. *(Board 04 drew the tab's row without the facet's
  "gesamt"; the tab keeps it so.)* The quantity follows U1's count rule
  through `ngettext` (issue 1074), counted on the quantity as displayed:
  English "1.0000 unit", "10.0000 units". *Amended 2026-10-07 (the PR γ
  closing act, first-look persona):* a row without p. a. carries the table
  dash's reason as a visually hidden sentence after its figures, as the
  facet's row does (`data-role="pa-absent"`), so a screen reader hears why
  at 390 px as at 1200 px; the row is pixel-identical (58 px), and the
  visible "why" stays the basis line.
- ~~**Kept as built:** the tab's dates stay ISO (`Date.to_iso8601`), the note's
  list and the phone rows included, and the table's "%" column keeps its two
  decimals and its spaced sign ("+27,07 %"), so the same return reads
  "+27,1%" in the phone row. Aligning both with `Format.date` and
  `Format.percent` is a follow-up outside this pick.~~ **Amended 2026-10-07
  (issue 1060, Sprint 19 PR γ U2; board `mockups/ux-design-2026-10-04/04-trades`,
  before/after):** that follow-up is built. Every date of the tab goes
  through `Format.date` — the open lots' "Eröffnungsdatum", the closed
  trades' two dates, the note's list and the phone rows ("14.03.2024";
  English keeps ISO) — so an ISO date no longer breaks at its hyphen on the
  phone. Both "%" columns, the open lots' and the closed trades', print one
  decimal with the sign glued on ("+18,7%", "+27,1%", "-5,1%") through
  `signed_pa/1`, the form of the p. a. column beside them, so the spaced
  "%" no longer wraps onto its own line in the narrow column. The pane's
  head ("Letzter 61,85 (2026-10-01)") is not part of the tab and not part of
  this repair.

## Amendment 2026-10-01 — Accounts & depots: the merge records *(Sprint 17 pick G2-A, Lane V1, ADR-0050 §12)*

Board `mockups/ux-design-2026-10-01/02-merge-records`, variant A (plan D-9,
silence adopts it). Built in `PortfolixirWeb.PortfolioAccounts.MergeRecords`
and placed by `PortfolixirWeb.PortfolioAccountsLive`. It is the operator's
view of `GET /api/v1/merges` and reads the same figures
(`Portfolixir.Lifecycle.manifest_summary/1`): what only the view knew would
be the two-way gap in the other direction.

- **Placement.** A section of its own after "Depots and cash accounts" and
  before the compatibility records, which stay the page's last block: an h2
  ("Merges") and Cash flow's `.section-disclosure` with its chevron,
  **collapsed**. The summary names what opens: "5 entries · latest
  30.09.2026"; at the API's default page it reads "the newest 100 · latest …"
  (UX-DR26). Under it the hint "What each merge moved, the newest first."
  One list for all three kinds, in the API's order and size
  (`inserted_at:desc,id:desc`, 100).
- **The row** (`.data-table.merge-records-table`, a reading table: it fits
  its wrapper, its cells wrap, UX-DR15's scroller stays the fallback): Date
  (the host's calendar date, `Format.date`) · Kind (cash account, depot,
  security) · Source → target · Result · By. The source is muted, **never
  struck** — the row is gone, its name lives on as a former name of the
  target (§4). The target carries the link treatment at rest (G7-A): an
  account or a depot jumps to its band on this page, a security opens its
  page. A reader hears "into" for the arrow (`.merge-route`'s rule). A target
  a later merge took away is its recorded name, muted, over "now in <live
  end>" (a link, `target.merged_into`, the name read from the page's own
  rows); a target deleted since is "a depot (cash account, security) deleted
  since", italic, no link; a target merged on into a row deleted since reads
  its name over "now in a depot deleted since". By is "Operator" or "Agent",
  G12.1-A's words (a token writes as the agent); `actor_label` stays unshown
  until tokens carry names people chose (FU-6).
- **The result** is a `<details class="merge-manifest">` whose summary is the
  confirmation's own phrase: for an account or a depot "142 bookings moved,
  6 removed", for a security "21 bookings moved, 1 duplicate removed, 1
  split collapsed, 380 quotes added, 2 settings dropped" (the collapsed
  split since Sprint 18 H8.7, issue 1032). A part that is zero is left out,
  the moved bookings never. Opened, a `<dl class="merge-manifest__counts">` names
  one line per table with a figure other than zero, then the choice and the
  check, and the basis line "Counted from the merge's record; every single
  row is in the audit journal." Every manifest key has a fixed label; a raw
  key never reaches the screen, and a meta-test fails a key the three merge
  writers emit without one (`MergeRecords.labelled_paths/0`):

  | Line (de) | Reads `manifest_summary` | Value (de) |
  |---|---|---|
  | Buchungen | `transactions.moved`, `.deleted`, `.deleted_by_reason.*` | "N verschoben", then per reason "N Duplikat(e) entfernt", "N interne Umbuchung(en) entfallen", "N gesetzte(r) Salden/Saldo desselben Tages entfallen", "N Split(s) zusammengelegt" |
  | Gesetzte Salden | `transactions.restated`, `restated_anchors` | "N angepasst · N gelten jetzt für beide Konten" |
  | Verknüpfte Depots | `securities_accounts.repointed` | "N zum Ziel verschoben" |
  | Kurse | `quotes.moved`, `.dropped` | "N ergänzt · N verworfen, das Ziel hatte an diesen Tagen einen" |
  | Klassifizierungen | `category_assignments.moved`, `.dropped` | "N Zuordnungen verschoben · N entfallen" |
  | Positionsziele | `position_targets.moved`, `.deleted` | "N verschoben · N entfallen" |
  | Termine | `security_events.moved`, `.possible_duplicates` | "N verschoben · N jetzt möglicherweise doppelt" |
  | Splits | `split_events.source`, `.target` | "N der Quelle · N des Ziels" |
  | Buckets der Position | `position_bucket_overrides.carried`, `.dropped`, `.cleared` | "N übernommen · N entfallen · N beim Ziel geleert" |
  | Bucket-Zuordnungen | `cash_account_buckets.removed`, `securities_account_buckets.removed` | "N entfernt" |
  | Frühere Namen | `former_names.appended`, `.not_kept` | "N übernommen · N nicht übernommen" |
  | Frühere ISINs | `identifier_aliases.reassigned` | "N übernommen" |
  | Stammdaten | `identifiers.adopted`, `.differences` | "N Felder übernommen, das Ziel hatte keine · N abweichend, die des Ziels gelten" |
  | Rundung beim Split | `rounding_differences` | "N Abweichung(en)" |
  | ISIN | `choices.identity_choice`, `.isin_changed_on`, `identifiers.source_isin`, `.target_isin`, `identifier_aliases.created` | "<ISIN> bleibt; <ISIN> ist jetzt frühere ISIN", or "<ISIN> übernommen; <ISIN> ist jetzt frühere ISIN · Änderung vom <date>", or "<ISIN> von der Quelle übernommen"; *amended 2026-10-07 (issue 1067):* keyed on the stored ISINs, not the given choice — with an ISIN on both sides the choice's sentence, on the source only "… von der Quelle übernommen", on the target only or on neither no line |
  | Wahl | `choices.collapse_key_equal` | "gleiche Buchungen: als Duplikate entfernt" / "… beide behalten"; absent when there was nothing to choose |
  | Prüfung | `linearity.*` | "Saldo an N Tagen bestätigt" (cash), "Stückzahl an N Tagen für N Wertpapiere bestätigt" (depot), "Stückzahl an N Tagen in N Depots bestätigt" (security) |

  The removed bookings are named per reason because the payload now counts
  them so (`transactions.deleted_by_reason`, beside the unchanged
  `transactions.deleted`), so the agent and the operator read the same
  split.
- **The way in (⑤).** The date in a survivor's "merged from … · <date>"
  line (G13.1 above) and in a security's "merged on <date> from …" basis
  clause (G3-A above) links `/portfolios?merge=<id>#merge-records`. The
  query opens the section and that entry's result **server-side**, because a
  fragment does not reliably open a `<details>`. *Deviation from the board,
  stated:* the board's fragment names the row (`#merge-record-<id>`); the
  build's names the section, because each entry renders twice (the table row
  and the phone row, one of them always `display: none`) and a fragment that
  points at the hidden copy scrolls nowhere. The opened result marks the
  entry; the list is dozens of rows, not thousands. **Closing act γ:** the
  section and every entry carry `scroll-margin-top` (the top bar's height
  plus `--space-3`), so the fragment does not land under the sticky bar, and
  the `MergeFocus` hook focuses the opened entry's visible result summary
  once per opened id, which brings it into view (D8). A link naming a merge
  a cut list does not carry — older than the newest 100 — opens the section
  with a `.hint` under its hint, "The merge the link names is not among the
  newest 100 listed here." (board 02, A8); in a whole list an unknown id
  names no merge and nothing is said. In a security's basis line the clauses
  sit in one inline `span.summary-basis__text`, because that line is a flex
  row and the date link split the sentence into flex items (D5).
- **Under 560 px** the table gives way to `.phone-row`s (UX-DR27):
  "source → target" (600, wrapping) over "date · kind · by" — the phone row
  has no figure for its right edge, because a merge carries no amount, so the
  date moves into the identifier line — and the same result disclosure full
  width beneath. Nothing scrolls sideways.
- **Empty:** the section stays, with one `.empty-state` sentence naming where
  a merge starts — "No merge yet — “Merge into…” is in the row menu of every
  account, depot and security." — and no action, because the list creates
  nothing (the precedent is Realized's "no closed sales" sentence).
- **Read-only.** No kebab, no selection, no button, no form in the section,
  and no wording that suggests a merge can be taken back: there is no unmerge
  (§12), and the confirmation said so before the merge wrote.
- **The `app.css` rules of the pick** (one block after `.merge-stale__changes`):
  ① `.merge-records-table` at `min-width: 0` with nowrap date, kind and
  actor cells; ② `.merge-record__source` muted, `__arrow` ~~subtle~~ muted
  (amended 2026-10-07, issue 1085: it carries the direction) with 3 px
  padding, `__target` accent 600 underlined, `__target--gone` muted 400 not
  underlined, `__target--deleted` italic, `__later` a 12 px muted line whose
  link is the accent; ③ `.merge-manifest` summary at 12 px/500 with the
  chevron top-aligned, `__counts` a two-column grid indented 16 px,
  `__basis` 11.5 px muted; ④ `.merge-records__rows .phone-row` one column and
  the table hidden under 560 px; ⑤ `.merge-date-link`.
- **Stated, not settled here:** security merges appear on a page titled for
  accounts and depots; the board's "Gegen A" accepts that cost, and the
  subtitle is unchanged.

## Amendment 2026-10-01 — Securities detail: releasing manual quotes *(Sprint 17 pick G3-A, Lane V2, T-9)*

Board `mockups/ux-design-2026-10-01/03-quote-release`, variant A (plan D-9,
silence adopts it). Built in `PortfolixirWeb.Securities.ManualQuotes` (the
note and the result's words), `PortfolixirWeb.Securities.QuoteReleaseDialog`
(the dialog) and the Quotes tab of `PortfolixirWeb.SecuritiesLive`. The page's
first quote write; the write is `Quotes.release_manual/4`, unchanged (one
transaction that locks the security, one journal entry whose before-image is
the released rows), run as the operator.

- **The note.** At the head of the Quotes tab, above the range's basis line,
  a `note`-severity data note (UX-DR17: context, nothing is wrong): "7 manual
  quotes in the stored history, from 2026-06-30 to 2026-09-16." — counted over
  the **whole stored history**, not the chart's range (the basis line under it
  says the table is the range), from `Quotes.manual_summary/2`. Where every
  stored quote is manual (a demo dataset, a security without a provider) it
  reads "…; every stored quote is manual."; one manual quote reads "One manual
  quote in the stored history, on <date>." Then "A manual quote has
  precedence: the quote sync leaves it standing until it is released." and
  the remedy, a child of the note: the `.link-button` **Release…** (a word,
  no glyph: none means "release", and lending one a second meaning breaks
  UX-DR16). No manual quote: no note and no control (A7) — an all-clear is
  not a finding. The dates are `<time datetime>` elements (rule ③).
- **The dialog** is a native `<dialog class="modal quote-release-dialog">`
  (the `ModalDialog` hook, no `aria-modal`), titled "Release manual quotes —
  <name>". Top to bottom: the attention note when the quote sync cannot fetch
  the security — no adapter for its provider, or one that cannot ask for it,
  Yahoo without a ticker (`QuoteSync.adapter?/2`, closing act γ D7) — "The
  quote sync fetches no quotes for this security: the released days stay
  without a quote." (A3); the custom range's ISO pair (`.period-range__pair`, From/To,
  prefilled with the first and last manual date, both inclusive, UX-DR19);
  the field error under the pair when one is shown; the chip row
  (`.period-years` with `.filter-chip`, the Wealth popover's year chips):
  "All · N" and one chip per **stretch** — a run of manual quotes with no
  quote of another source between them — "<from> – <to> · n" (a one-day
  stretch "<date> · 1"), the five newest, ascending, a stretch spanning every
  manual quote left to "All" so no range has two pressed chips; a chip fills
  the pair, and the chip equal to the pair is pressed (`aria-pressed`); more
  than five stretches add a `.hint` under the row, "The 5 newest of 7
  stretches; “All” covers every one." (UX-DR26: a cut list says so; γ D3,
  n7); then one `.hint` sentence in the code's words:
  "The manual closes in the range are removed and kept in the journal with
  their values; the provider's quotes in the range stay as they are." plus,
  only where an adapter exists, "The next quote sync stores the provider's
  close for the released days; until then they have no quote."
- **The band foot** (`.modal-footer--band`): Cancel (ghost), the spacer, then
  the confirm, `.button-danger` — danger, because nothing in the UI restores
  a release even though the journal keeps it — naming the count of the
  range: "Release 7 manual quotes", following the pair on every change. One
  confirmation, never a second `data-confirm` — and **only the confirm
  writes** (closing act γ D1): it is a `type="button"` outside the form,
  carrying the pair and the count it shows; Enter in a field submits the
  form, which re-counts and checks the pair (the field errors below) and
  writes nothing. The close button keeps its 30 px beside a title that
  wraps, 44 px under a coarse pointer (UX-DR6, γ D6) — since Sprint 18 the
  rule of every `.icon-button`, not of this dialog (Amendment 2026-10-03,
  the icon button).
- **States.** A valid range with no manual quote: the confirm reads "Release",
  disabled, its reason beside it as text — `.merge-footer__why` "No manual
  quote in the range.", the merge dialog's rule (disabled, never merely
  pale), reused as it stands (A4). A "To" before its "From": on confirm, "The
  end date is before the start date." at the field (`.field-error`,
  `aria-invalid` on To), nothing written, the dialog stays; a field that is
  no date: "Not a date — use YYYY-MM-DD." at that field — the custom range's
  own words (D5, A6). The confirm is not disabled for an unreadable pair:
  the refusal lands on the field that can fix it. **Recounted (A8, γ
  CR-2):** where the range holds another count than the confirm showed — a
  manual close written or released since — nothing is written, the
  `.field-error` slot under the pair (no field marked) says "The range now
  holds 5 manual quotes — check and confirm again.", and the confirm names
  the new count.
- **The result (A5)** is panel-local, beside its trigger rather than in the
  page-level slot: `AppShell.inline_result` `#quotes-release-result` at the
  head of the tab, its regions present before the action, a note: "4 manual
  quotes released, from 2026-06-30 to 2026-07-03." — the count and dates of
  the write's answer (`released`), not of the dialog — then "The next quote
  sync stores the provider's close for these days." ("for this day" for one)
  with **Sync prices** as its follow-up — the Chart tab's words, but since
  Sprint 18 (U5, H7.4, issue 1033) syncing this security only
  (`sync_quotes_released`, `QuoteSync.sync_security/2`), where it once ran the
  catalog's `sync_now` — or, where the sync cannot fetch the security, "The quote sync
  fetches no quotes for this security: these days stay without a quote." and
  no button (γ D7, n6). Where the release took the last manual quote, and with
  it the note's **Release…** that opened the dialog, the focus goes to the
  result's dismiss (`data-focus-fallback` on the dialog, read by the
  `ModalDialog` hook; WCAG 2.4.3, γ D2). It stays until dismissed (its own `dismiss_release_result`), the
  next action on it (Sync prices), or a navigation. Manual quotes left over
  keep the note under it, with the new count. `inline_result` gained an
  optional `follow_up` slot and `dismiss_event` for this; the message may be
  safe markup (the `<time>` dates).
- **The sync's own result** *(Sprint 18 U5, issue 1012, H7.1b)*: where the
  sync kept manual quotes against a provider close for the same day, its
  result adds "3 manual quotes were left standing where the provider
  returned a close." (German "3 manuelle Kurse blieben stehen, wo der
  Anbieter einen Schlusskurs lieferte."; "One manual quote was left
  standing …" for one) — Amendment 2026-10-03, the sync's count.
- **Under 720 px** the dialog is the merge dialog's bottom sheet:
  `.quote-release-dialog` joins the selector lists of the `.merge-dialog`
  phone rules (full width, at most 88 % high, the foot stacked — the reason
  with "↓ ", the confirm on a line of its own, then Cancel — 44 px buttons).
- **The `app.css` rules of the pick:** ① `.quote-release-dialog { max-width:
  460px }` and `.quote-release-form` a grid with `--space-2` gaps; ② the
  phone sheet by joining the merge dialog's 720 px selector lists; ③
  `.data-note__body time { white-space: nowrap }`, so a 390 px line never
  breaks a date inside it. *Amended 2026-10-07 (Sprint 19 U3):* the note's
  dates read `Format.date` — a German one has no hyphen to break at; the
  rule keeps an English ISO date whole.
- **Stated, not settled here:** the remedy link-button is below the 44 px
  coarse-pointer floor, as every `.link-button` remedy in a note is (the
  board's Part 4 finding, filed rather than fixed here; settled by Sprint 18
  U4, Data note → the remedy's touch target). The dialog's title
  interpolates the stored name without `<bdi>` isolation, as the merge
  dialog's does (G12.2-B's named follow-up). Dialog count: one more native

  board's Part 4 finding, filed rather than fixed here). The dialog's title
  isolates the stored name in `<bdi>` since Sprint 18 (H8.8, issue 968), as
  the merge dialogs' do. Dialog count: one more native
  dialog; the lifecycle's record above now reads seventeen `<dialog>`
  elements in `lib/portfolixir_web/`, still with zero `aria-modal`.

## Amendment 2026-10-03 — Wealth → Holdings → Performance: the contribution table *(Sprint 18 PR β F3, ADR-0051 §12 pick A, FR-41)*

Board `mockups/fr41-2026-09-25/01-contribution-surface`, variant A (signed
with ADR-0051 by the merge of the Sprint 17 planning PR; B and C not built).
Built in `PortfolixirWeb.Portfolio.ContributionTable`, placed by
`PortfolixirWeb.PortfolioLive`; the rules are in `app.css` under "The
contribution table under the Wealth performance chart". It is the human view
of the contribution read (`Performance.Contribution.for_view/2`), and it is
**never in the classifications tree** (ADR-0051 §8).

### Placement and scope

- **Inside `#portfolio-performance`, directly under the chart** and its basis
  lines (the date range with "computed", the view's composition label), so
  the badge, the chart and the table share one section head: the series
  toggle, the period control and the custom-range disclosure.
- **The scope is the walk's own:** the page's view across all portfolios
  (Everything when none is picked), the period the control shows, the
  portfolio's base currency. The sum row is therefore the money figure of
  the badge, "+x EUR in the period" (ADR-0051 §3, I1), printed by the
  badge's own rule (a plus before a positive amount, two decimals), so the
  two read the same characters. LiveView tests pin the equality on seven
  worlds: remainder lines and a sold position, more than ten positions, an
  unvalued position, a view, before and after a period change, a booking
  behind the open page, and a view deleted behind it.
- **The two read the same colour, too** (repair R1, board
  `mockups/ux-review-2026-10-03/01-contribution-repairs`): the badge's money
  span carries the sign class of the money figure, not the TTWROR's, so a
  deposit before a fall — a positive return beside a money loss — prints the
  loss in {colors.danger} above the sum row's red, and a zero takes the
  badge's flat {colors.text-muted} (`.perf-badge .is-flat`). The `<p>` keeps
  the TTWROR's class for the percentage.
- **It loads on its own.** The badge re-chains the cached walk; the table
  runs a windowed walk per period (ADR-0051 §5), async, with the block
  skeleton and the "computing" cue (UX-DR20) while it does — a
  `role="status"` region with `aria-busy="true"` (repair R7b). While the badge
  shows a superseded series (ADR-0032 §6) the table keeps its skeleton, so
  its sum never answers a figure the badge no longer shows; a failed walk is
  a `problem` note, "Computation failed. Reload retries.". Holdings only:
  the Allocation tab never computes it.
- **Both answer from one data state.** Each read notes its view, its day
  and the global data version before and after it ran. Once both have
  landed, the one that read older data is read again — a superseded badge
  becomes the labelled stale series, so the table waits on its skeleton —
  and a read a write landed in the middle of is read again too. A booking
  behind the open page, a view deleted in another tab or midnight passing
  therefore never leaves the sum and the badge on two different figures.

### Anatomy, top to bottom

- **The head** (`.contribution__head`): the section's `h3` "Beitrag je
  Position" and, right-aligned on the same row, the scope line in the basis
  voice (12 px, muted): "1J · Ansicht Alles · sortiert nach Beitrag" — the
  page's period label and its existing "Ansicht %{name}" words. Over the
  empty state the line ends after the view: nothing is listed to be sorted
  (repair R7a, board `mockups/ux-review-2026-10-03/01-contribution-repairs`).
- **The table** (`#contribution-table-wrap > table#contribution-table.data-table`,
  labelled by the `h3`): Wertpapier · Anfangswert · Zu-/Abflüsse · Erträge ·
  Kosten · Endwert · Beitrag, the six figures `.num`. A reading table, not a
  matrix (`min-width: 0` on the wrapper's table, the figures `nowrap`, the
  name at least 14ch and wrapping), with UX-DR15's scroller as the fallback.
  The name and its sub-line wrap between words — `overflow-wrap: break-word`
  with `hyphens: auto`, so a browser with the page language's dictionary
  breaks a German compound at a syllable with a hyphen, and one without
  keeps the word whole and widens the column to it. Never `anywhere`, which
  split "Fremdwährungsko|nten" at 561–1024 px (repair R4, board
  `mockups/ux-review-2026-10-03/01-contribution-repairs`).
- **A position row**, largest contribution first (the payload's order): the
  name; under it, in 12 px muted, the payload's two flags in words where a
  position was not held at both ends — "zu Beginn nicht im Bestand", "am
  Ende nicht mehr im Bestand", "weder zu Beginn noch am Ende im Bestand" (a
  position sold inside the period is a row; so is one with income held at
  neither end). Anfangswert, Kosten and Endwert unsigned; Zu-/Abflüsse and
  Erträge signed and **uncoloured** — a flow's sign is a direction, not a
  gain. The Beitrag signed in its sign colour (`span.is-positive` /
  `.is-negative`, zero uncoloured), with the **drift bar under it**:
  `.drift-bar` at 110 px, block, right-aligned under the figure (`margin: 5px
  0 0 auto`), the fill right of the zero line in {colors.positive} for a
  gain and left in {colors.danger} for a loss, scaled so the largest
  absolute contribution fills 45 % of the track (Drift bars, issue 798). A
  zero contribution keeps the track with no fill. Decorative and
  `aria-hidden`: the figure carries sign and colour (UX-DR7).
- **The unvalued marker** (UX-DR25): a row that counted zero on some days
  carries `.contribution-unvalued-mark` after its name — "240 Tage null", 11
  px/600 in {colors.warning} inside a dashed {colors.warning} pill. The word
  is the channel; the colour is the third. *Since #1055 (Sprint 19 PR α M3,
  board `mockups/ux-design-2026-10-04/02-money-notes`, pick J2 A):* the
  "Währungseffekt auf Bargeld" line carries the same marker, as built, once
  per cash account that counted zero in the period, with the account's name
  before its days — "Tagesgeld CHF: 18 Tage null" — because the line holds
  the jump the account's first rate brings, and the line itself is not the
  account. The other two lines never carry one.
- **More than ten positions:** the ten largest **by absolute amount**, in
  the table's order, then a row (`td[colspan=7]`, muted) "20 kleinere
  Positionen sind ausgeblendet; die Summe enthält sie." and the
  `.link-button` "Alle 30 anzeigen" (`aria-expanded`), which opens every row
  and then reads "Nur die zehn größten anzeigen". Pure presentation — nothing
  recomputes — and the choice survives a period switch. The sum row always
  covers every position.
- **The remainder** under its own head row, "Keiner Position zugeordnet" (11
  px/700 uppercase, letter-spaced, muted, on {colors.bg-muted}); its three
  lines on the same band, each with a 12 px muted sub-line and "—" in the
  five position columns, the figure signed in its colour. The band is one
  rule over the four rows that outranks the zebra stripe and the row hover
  (0,3,3 against 0,2,3), so it stays solid however many positions sit above
  it (repair R2, board `mockups/ux-review-2026-10-03/01-contribution-repairs`):
  - **Zinsen** — "Konto und Kupons; eine Zinsbuchung trägt kein Wertpapier";
  - **Einzelne Gebühren und Steuern** — "Ohne Handelsbezug, auch mit
    Wertpapier";
  - **Währungseffekt auf Bargeld** — "Fremdwährungskonten und
    Abrechnungsdifferenzen von Käufen und Verkäufen": the engine puts a
    trade's settlement difference between its cash and its security leg in
    this line (ADR-0051 §3), and the sub-line says so rather than leaving
    "Bargeld" to suggest balances only.

  English: "Not attributed to a position"; "Interest" — "Account interest
  and coupons; an interest booking carries no security"; "Standalone fees
  and taxes" — "Not part of a trade, even when one names a security";
  "Currency effect on cash" — "Foreign-currency balances and the settlement
  differences of buys and sells". All three lines always render, a zero
  included: the anatomy does not change with the data.
- **The sum row** "Summe = Ergebnis im Zeitraum", 700 under a 2 px
  {colors.border-strong} rule: Anfangswert, Zu-/Abflüsse, Erträge, Kosten
  and Endwert summed over **all** positions; the Beitrag is the period's
  result (`totals.result`, the figure the badge's walk computes), which the
  positions and the three lines add up to (I1), signed in its colour with
  the currency as `.value-suffix`.
- **The basis line** (`p.summary-basis`, 12 px muted, UX-DR11), the board's
  four sentences in the house's dot-separated basis voice: "Beitrag =
  Endwert − Anfangswert − Zu-/Abflüsse + Erträge − Kosten · je Position in
  EUR, einschließlich der Währungsbewegung · Anfangswert: der Schluss des
  Vortags · Positionen und Restposten ergeben genau das Ergebnis im
  Zeitraum; Einzahlungen und Entnahmen sind kein Ergebnis".
- **The unvalued note** (UX-DR25 clauses 1 and 3), last: one `attention`
  data note with the count and every name in bold, each with its days and
  reason — "3 Positionen zählten an einigen Tagen des Zeitraums null:
  **Saltmarsh Logistics SE** (240 Tage, kein Kurs gespeichert), … Sie bleiben
  in der Summe, so wie im Ergebnis darüber." No remedy control: nothing here
  can supply a past price or rate.
- **The account sentence** *(#1055, pick J2 A)*: a cash account in a foreign
  currency that held money and counted zero on some days of the period, for
  want of a rate, is named in the same note, after the positions and in
  their shape — "Ein Verrechnungskonto zählte an einigen Tagen des
  Zeitraums null: **Tagesgeld CHF** (2.000,00 CHF, 18 Tage, kein
  Wechselkurs gespeichert)." The balance is the account's own, in its
  currency (UX-DR25 clause 2), never a converted one: there was no rate to
  convert with; it prints at least two decimals and every further digit it
  carries. The days include the day before the period, whose close is the
  start value: a period that opens on the first rate's day holds the whole
  jump, so it names the account. When the currency's first exchange rate
  arrived inside the period while the account still held money at zero, a
  second sentence says where the balance went: "Mit dem ersten Wechselkurs
  am 01.08.2026 kam sein ganzer Saldo in den „Währungseffekt auf Bargeld“ —
  das ist kein Währungsgewinn." — "kein Währungsverlust" for an overdraft,
  "weder ein Währungsgewinn noch ein Währungsverlust" for balances of both
  signs. "Wechselkurs", never "Kurs", which the screen keeps for a
  security's price. An account emptied before its rate came gets the first
  sentence only: nothing entered the line. An account still at zero on the
  period's last day reads "Ein Verrechnungskonto zählt bis zum Ende des
  Zeitraums null: **…** (…)." (board J2 A, pin a2), after the others.
  Several accounts take the plural ("2 Verrechnungskonten zählten …", "…
  zählen bis zum Ende des Zeitraums null"), and the second sentence names
  each account whose rate came, with its date ("Mit ihren ersten
  Wechselkursen kamen die ganzen Salden von Tagesgeld CHF (01.08.2026), …
  in den „Währungseffekt auf Bargeld“ — …"). One finding, one note
  (UX-DR17): with no position at zero the note carries the accounts alone,
  and an empty window that still held such an account shows the note under
  the empty-state sentence. The note follows the period: switch to a period
  after the first rate and the account leaves it with the jump. No sync
  control (clause 3): a rate synced today cannot value a past day.
- **The empty window** (ADR-0051 §4): no walked day in the period, or nothing
  held and no remainder line moved — the `.empty-state` sentence "In diesem
  Zeitraum gibt es nichts aufzuschlüsseln: Keine Position war im Bestand, und
  weder Zinsen noch Gebühren noch Währungseffekte fielen an." No table, no
  sum row, never a table of zeros.

### Under 560 px *(UX-DR27)*

`#contribution-table-wrap` joins the phone lists' 560 px block and
`ul#contribution-phone-rows.phone-rows` shows: the transactions shape, two
children (body and figures), no logo, no kebab, no bar.

- **A position:** the name (600, wrapping) over "Anfang → Ende" — or, not
  held at both ends, the held words — then "Zufluss x" / "Abfluss x" and
  "Erträge x" where not zero and the "N Tage null" marker; on the right the
  Beitrag (14 px/600, sign colour).
- **"N kleinere Positionen …"** and the same control, as a row of its own.
- **The remainder** as one row on the {colors.bg-muted} band: "Keiner
  Position zugeordnet" over "Zinsen +x · Gebühren/Steuern −y · Währung +z",
  then "· Tagesgeld CHF: 18 Tage null" per account that counted zero
  (#1055), as a position row carries its "N Tage null", the remainder's
  total on the right. The band bleeds `--space-2` into the
  list's gutter on both sides (`margin-inline: calc(-1 * var(--space-2))`)
  and is padded by the same amount, so its name starts and its figure ends
  on the same edges as every other row's and the figures stay one
  right-aligned column (repair R5, board
  `mockups/ux-review-2026-10-03/01-contribution-repairs`; padded inside the
  list, it had moved both 8 px in).
- **The sum** under the 2 px rule: "Summe = Ergebnis im Zeitraum" (700) over
  "Positionen und Restposten", the total with its currency suffix (700).
- The head, the basis line and the note stay as they are, wrapping.

### Kept apart from the board, and why

- **Held words, not "verkauft 2026-04-17" / "gekauft 2026-01-12".** The
  payload carries `held_at_start` and `held_at_end`, not the dates, and a
  position can arrive by delivery or leave by transfer: the words stay true
  for every way in and out.
- **The basis line** keeps the board's content in the basis voice instead of
  four sentences (UX-DR11), and the scope line reuses the page's existing
  "Ansicht %{name}" words (no colon).
- **The phone rows** carry no avatar: the board's initials were the mock
  frame's stand-in for the securities list's logo, and the remainder and sum
  rows would need glyph avatars of their own. The rows follow the trades
  rows instead. The sum row's second line names what it adds up rather than
  "= Abzeichen oben".
- **The unvalued note** names each position with its own days and reason,
  because several positions can count zero for different reasons; the board
  drew one.
- **Signs** are the house formats (`Format`): a hyphen-minus, not the
  board's typographic minus, as the badge prints them.
- **The "show all" control**, which the board named but did not draw, is a
  table row between the positions and the remainder, where the hidden rows
  would appear.

### Stated, not settled here

- The show-all control is a standalone `.link-button` and takes the
  treatment a rule's name on Risk has (`.policy-rule__name`), through its
  own class `.contribution-show-all`: 44 px high under a coarse pointer
  (UX-DR6) and the 2 px {colors.accent} ring at a 2 px offset on
  `:focus-visible`, in the table's row and in the phone row alike (repair
  R3, board `mockups/ux-review-2026-10-03/01-contribution-repairs`). Scoped
  to this control: a remedy link inside a note's sentence keeps its own
  finding and its own remedy, because growing its line would reflow the
  sentence.
- ~~A security stored twice under one name (a duplicate awaiting a merge)
  reads as two rows with the same name; the ISIN is in the payload but not
  on the row.~~ **Settled 2026-10-07 (issue 1057, Sprint 19 PR γ U4, pick
  J6.2 A):** each twin carries the identifier that tells it apart, the ISIN
  else the number, after its name in the table and in the phone row — see
  Components → Twin names.

## Amendment 2026-10-03 — Tables: five conformance repairs *(Sprint 18 pick H4; issues 1009, 1010, 913, 911, 1011)*

Board `mockups/ux-design-2026-10-02/04-tables-conformance`, "after", and
**A** for the positions worklist (plan D-8, adopted by the planning PR's
merge). The spec already fixed every answer but one; this records how each
repair is built, so the next reader holds the screen against words that
match it.

### The subject column sticks to its scroller *(issue 1009, rule ①)*

- **The scroller is the sticky container.** `.data-table-wrapper > table`
  sets `overflow: visible`, beside its `min-width: max-content`: the global
  `table { overflow: hidden }` (and, under 560 px, `overflow-x: auto`) made
  every table its own scroll container, and a table exactly as wide as its
  content never moves, so `.col-subject` stuck nowhere. A bare table outside
  a wrapper keeps the global fallback. Measured on the board: the
  realized matrix's "Gesamt" ended 87 px outside its scroller at 1200 px and
  677 px outside at 390 px; after, it stands flush with the scroller's edge
  and the months scroll beneath it.
- **Three companion rules ship with it**, because a column that really
  sticks shows what an inert one hid:
  - **①b the seam is an inset shadow** (`.col-subject { border-left: 0;
    box-shadow: inset 1px 0 0 {colors.border} }`): a collapsed table (the
    drift tables) paints a cell's border itself and leaves it behind when
    the cell sticks;
  - **①c the pinned head cell keeps the head row's grey** (`thead
    .col-subject { background: {colors.bg-muted} }`); `.data-table thead
    th` outranks it and keeps its own head colour;
  - **①d the pinned cell is opaque on striped and hovered rows**: the
    stripe is 24 % {colors.bg-muted} over transparent, so on
    `.data-table` an even row's pinned cell takes the same 24 % over
    {colors.bg-elevated}, and the hover rule comes after it.
- **①d reaches the history** (the closing act's finding; board
  `mockups/ux-review-2026-10-03/03-gamma-surface-repairs`, G5), which the
  board's stated doubts had first left: `#transaction-list` is no
  `.data-table`, its hover is the global `tbody tr:hover` wash on the `tr`
  (42 % {colors.accent-soft} over transparent), and the wash stopped at the
  opaque pinned Balance of an account-filtered history.
  `#transaction-list tbody tr:hover td.col-subject` gives the cell the same
  42 % over {colors.bg-elevated}: it follows the wash and stays opaque.
  Under 560 px the history is two-line rows with no pinned column.
- **Kept, as the board's stated doubts left them:** the wrapper, not the
  table, now clips a header popover; the tree's Drift ⓘ opens over the rows
  as before.

### Sign colour holds in every data table *(issue 1010, rule ②)*

- **One general rule:** `.data-table td.is-positive` / `.is-negative`
  (specificity 0,2,1) outrank `.data-table tbody td { color }` (0,1,2), so
  every signed cell of a data table carries its sign colour — the
  security's open lots, closed trades and holdings, the Cash-flow trades.
  The colour rule of Colors ("wherever a sign exists, at every level of a
  table") is now true of the build.
- **A muted drift row keeps a red loss:** `.drift-table tr.is-muted
  td.is-negative` (0,3,2) outranks the row's grey, so a position row's
  negative drift is red while its name stays muted.
- **The table-scoped copies are gone, pixel-identical:** Sprint 17's
  `#realized-trades-table td.is-positive / .is-negative` (board 01 rule ⑥)
  and pick H1's `#detail-closed-trades-table` pair. Their muted-dash lines
  stay: a muted class in a cell is outranked the same way, but it is not a
  sign, and a general muted rule is outside this issue. *Amended 2026-10-08
  (issue 1142, Sprint 20 board 02 rule ②):* that general rule exists now,
  `.data-table td.trade-pa--na`, and the two muted-dash lines are gone with
  it.
- A `<span>` carrying a sign class inside a cell was never affected.

### The split ratio and the Balance join the `.num` family *(issue 913, rule ③)*

- **Markup only, no CSS:** the history's split-ratio cell
  (`td[data-role="split-ratio"]`) carries `num`, which `#transaction-list
  td.num` already right-aligns in tabular figures, so "2:1" stands in the
  Quantity column's alignment instead of at its left edge.
- **The Balance column, found while drawing:** its header carried only
  `col-subject` and its cells `numeric`, a class no rule backs, so header
  and figures sat left. Both now carry `num col-subject`.
- **Under 560 px nothing changes:** the table gives way to the two-line
  phone rows (UX-DR27), where the ratio and the balance already sit right in
  the figures column.

### One basis voice, one disclosure summary *(issue 1011, rule ⑤)*

Three halves, and all three change the picture:

- **⑤a the basis voice has a context-free rule:** `.summary-basis { margin:
  0; font-size: 12px; color: {colors.text-muted} }`, placed before every
  scoped basis rule. Nineteen basis lines rendered as body text (13 px, text
  colour, a paragraph's margins) — the four Cash-flow facets, Risk ×2, Tax
  ×3, Views and Buckets ×3, Snapshots, the Quotes tab, the KPI strip,
  Classifications, the allocation (issue 911's basis line) and the two
  "since" notes. The scoped rules with their own layout keep it:
  `.detail-tab-panel--overview .summary-basis` stays a flex row, and the
  later single-class `.kpi-strip__basis` and `.tree-basis` keep their own
  margins by source order — they gain the 12 px muted voice for the first
  time.
- **⑤b one `.disclosure-summary`, at the spec's control label:** the class
  was defined twice, and the second definition (0.85rem / 600) won, so every
  quiet disclosure summary read at 13.6 px / 600 instead of
  {typography.control-label} (12 px / 500 / 0.04em). The second definition
  is gone and the first carries weight 500 — **not** pixel-identical,
  because the identical picture would have kept the violation. Every
  summary of the class changes, 26 in 16 modules counted with ⑤c's: "Daten
  als Tabelle", the Cash-flow matrices, the merge records, the import, Tax,
  Risk, the dialogs. `.merge-manifest > .disclosure-summary` loses its now redundant
  local 12 px / 500; `.dup-group`'s local 12.5 px stays its own decision.
  **"Neuer Snapshot" joined them at the closing act** (board
  `mockups/ux-review-2026-10-03/03-gamma-surface-repairs`, G4): its summary
  carried the class and the chevron, but `.snapshot-create > summary`
  (0,1,1: accent colour, weight 600) outranked `.disclosure-summary`
  (0,1,0), so it read 12 px / 600 in the accent and never took the hover's
  text colour. The local rule is gone, and with it the summary's entry in
  the ADR-0027 coarse-pointer list, which the class's own 44 px floor
  covers; `.snapshot-create` keeps only its margin.
- **⑤c the compatibility records' summary is a `.disclosure-summary`** with
  the 12 px chevron (Accounts & depots, "Portfoliodatensätze
  (Kompatibilität)"), where it was a bare `<summary>` with the browser's
  triangle (UX-DR19); `details[open] > .disclosure-summary
  .disclosure-chevron` turns it.

### Allocation → Positions *(issue 911, section ④; pick **A**)*

- **(a) The hint moves into the Drift cell** (variant A, recommended and
  adopted): the worklist's subject spans what were two columns, Drift and
  Hint, and `right: 0` can hold only one. The Drift head now carries
  `col-subject`; each Drift cell shows the figure with the hint beneath it
  (`.rebalance-hint`, unchanged), which is the anatomy the tree's position
  rows already have. The "Hinweis" head and the "—" of a row without a hint
  are gone; sorting is still by Drift. Rows get taller by the hint's line.
  Measured on the board at 390 px: 186 px stay for the name, more than the
  144 px name column. Variant B (pin both columns with a coupled
  `right: 10.5rem`) was not taken: a wider quantity widens the Hint column
  and the Drift cell then covers it.
- **(b) The basis line** (`p.summary-basis.allocation-basis`) takes the
  basis voice through the context-free rule of ⑤a: 12 px, muted, no
  paragraph margins.
- **(c) The tree's Drift ⓘ names the portion.** While the payload's
  `drift_basis` is `allocated_portion` (ADR-0040 §2), the ⓘ's sentence gains
  a second one (`data-role="drift-basis-tip"`), the board's draft: "Der Plan
  verteilt 85,0%: Jedes Soll wird vor dem Vergleich auf diesen Anteil
  hochgerechnet, 34,0% zählen als 40,0%. Der unverteilte Rest erscheint
  nicht als Abweichung."
  The worked figure is the first top-level category the plan steers, its
  target divided by the allocated sum — the same division the drift takes;
  a plan with no such category gets the sentence without the figure. A full
  plan, or one over 100 %, measures against the full plan and shows no
  second sentence. Percentages glue their sign, as everywhere in the app.
- **(c′) The ⓘ wraps at phone width** (issue 1053, the closing act's
  finding; board `mockups/ux-review-2026-10-03/03-gamma-surface-repairs`,
  G2). Under 560 px the phone block's `table { white-space: nowrap }` was
  inherited by the ⓘ in the table's head, so its sentence ran on one line
  out of its 18 rem box (measured `scrollWidth` 2196 px in a 288 px box with
  (c)'s second sentence). `.metric-tooltip p` now sets `white-space:
  normal` itself — on the class, at every width, so any ⓘ inside a table
  cell is a wrapping paragraph; where nothing set `nowrap` the picture is
  identical. Seen while drawing and left for its own change: inside a
  numeric head cell (`th.num`) the paragraph also inherits `text-align:
  right`, at every width.

## Amendment 2026-10-03 — Coral passes light-mode contrast *(Sprint 18 pick H5, issue 908)*

Board `mockups/ux-design-2026-10-02/05-light-contrast`, "after" (before/after,
no variant). Link text is the accent colour at body size, at rest, plus an
underline (G7-A): `.link-button` (and `.policy-rule__name`),
`.merge-date-link`, `.merge-record__target`, `.kpi-summary__link`; accent
text on the accent tint is the same case (`.alert-success`, the active
navigation). Violet and teal cleared 4.5:1 on every light surface; **coral
did not** — 4.38 on the canvas, 4.15 in a note's muted well, 3.91 on its own
tint and in a problem note — so with the coral accent picked, every link
was body-size text the spec itself barred.

- **One token, two lines:** `--color-accent-coral` goes from `#e11d48` to
  `#ce1b42` in `:root` and in `[data-theme="light"]`, the two places light
  mode sets it. Same hue (HSL 347°, saturation 77 %), lightness 49.8 % →
  45.7 %: the smallest step that clears 4.5:1 on all six light surfaces; the
  binding one is coral-soft, which is also {colors.danger-soft}, at 4.53. The
  dark blocks keep `#fb7185` and measure as before. `--brand-coral-2` (the
  logo gradient) keeps `#e11d48`. The documentation site's stylesheet
  (`docs/styles.css`) shares the accent palette and takes the same light
  value.
- **What moves with it:** the coral fills (`.button-primary`, the active
  segment; white labels on them 4.70 → 5.44), the accent picker's coral
  swatch, the accent dot, the SMA-200 line and the second benchmark
  overlay — all slightly darker, all with more contrast. The operator sees
  this.
- **Not taken:** `#be123c` (rose-700, the step teal uses) leaves more margin
  (5.24 on coral-soft) but changes the look more; a separate `--color-link`
  token would leave the fills and chart lines alone but needs a token in
  five blocks and a sweep of every rule that colours text with the accent,
  and would still miss `.alert-success` and the active navigation.
- **Pinned by tests:** `CssAccentContrastTest` computes every accent's
  ratio from the token values in `app.css` (WCAG 2.x relative luminance,
  translucent tints composited in sRGB over the panel colour) on the six
  light surfaces and the white label, and on the three dark surfaces and the
  accent's own dark tint, and fails below 4.5:1; the decided value itself is
  pinned beside the other decided tokens in `CssThemeTokenParityTest`.

## Amendment 2026-10-03 — Touch targets and focus *(Sprint 18 pick H6, U4; issues 1013 and 1033)*

Board `mockups/ux-design-2026-10-02/06-touch-focus`, "after" and pick
H6.1 = A (plan D-8, silence adopts the recommendations). Each rule is in
`app.css` beside the class it repairs; `test/invariants/css_touch_and_focus_test.exs`
pins them.

### The icon button *(H6.2 and H6.2b, rule ②, on the class)*

`.icon-button` is the 30 × 30 square it declares at every call site: the
class sets `min-height: 0`, because the base `button { min-height: 34px }`
made every `<button>` of the class 30 × 34 while every `<a>` of it stayed
30 × 30 (the detail head showed both side by side). It is `flex: none`, so
a close button beside a title that wraps keeps its width. Under
`pointer: coarse` the class takes `min-width: 44px; min-height: 44px` —
**on the class, not per dialog**, as the Sprint 18 plan decided (U4):
UX-DR6's call-site table lists `.icon-button` itself as uncovered, and its
amendment 1 binds the floor to every call site of a class. So the floor
reaches every dialog's ×, the filter sheets, the booking drawer, and every
toolbar icon: Securities' New, Sync prices and Columns, the detail head's
Maximize and Close, Classifications' New, the import's "copy warnings" and
the column picker's ×. On touch a toolbar grows by 8 px (44 against the
search field's 36); board 06 H6.2b draws it. `.modal-head` and
`.filter-sheet__head` carry `gap: {spacing.2}` between the title and the ×.
The release dialog's three head rules (closing act γ D6) and the detail
head's ID rule for its two buttons are gone: the class covers them.

### The remedy inside a data note *(H6.1, pick A, rule ①; issue 1013)*

Under `pointer: coarse`, `.data-note__body .link-button` takes
`padding-block: 13px; margin-block: -13px` — (44 − 18) / 2 — so its hit
area is 44 px tall while its line stays the note's 18 px and no note
reflows; picture at rest identical (Components → Data note). It grows in the
block direction only, so beside the inline result's dismiss, the other
44 px target in the release result, the two never overlap. Eight call
sites in five kinds of note take it: the manual-quotes note's "Release…",
the release result's "Sync prices", the invisible-characters notes' remedies
(the head's "Edit master data", the research log's two "Append an entry
that supersedes #n"), and the three Tax notes. One remedy outside a note
takes it as a second selector, scoped to itself: the bond block's "Enter
bond data…" (`.bond-strip .detail-tab-empty .link-button`), which stands in
its sentence the same way on a 13 px line of the same 18 px (closing act on
U7, finding 5; board `ux-review-2026-10-03/04-bond-repairs` B4, measured
18.2 px before and 44.2 px after). Not covered, and left as a
follow-up: a remedy written as an `<a>` inside a note (the Overview's
data-quality links) — issue 1013 names the button. Under a coarse pointer
the keyboard focus ring of a remedy wraps the 44 px box; `.link-button` has
no `:focus-visible` rule of its own (the pass's Scope Lock). The delete's
remedies join the rule (U1's closing act R9, Amendment "Deleting a
booking" below): `.form-help .link-button` (the notes-only drawer's
"Löschen…") and `.alert-warning .link-button` / `.alert-error .link-button`
(Record split's "Gebuchten Split löschen…") take the same coarse padding
and, those three, the 2 px accent `:focus-visible` ring.

### The attention row's focus ring *(H6.3, rule ③; issue 1033)*

`.attention-item:focus-visible` draws `outline: 2px solid {colors.accent};
outline-offset: 2px` with `{rounded.sm}` corners — the ring the KPI strip
directly above already draws, where Chromium's 1 px `outline: auto` was
nearly invisible in the dark theme. One rule for the three Overview cards
that share the class ("Abgeschlossene Trades", "Ziel-Abweichungen",
"Fällig"); the list's 6 px row gap keeps the ring clear of the next row.
Front matter: `needs-attention-card.focus`.

### The inline result's dismiss *(H6.4, rule ④; issue 1033)*

The cause was the base button's 34 px floor, not the 1.4rem the issue
named: `.inline-result__dismiss` declared `height: 1.4rem`, `button
{ min-height: 34px }` won, and the × became a 22 × 34 box middle-aligned on
its line, so a one-line result ("Kurse aktualisiert.") measured 52 px
instead of 36 and its severity word sat 8 px above the sentence. The dismiss
now sets `min-height: 0; height: 1rem` (width, margin and hover unchanged).
Under `pointer: coarse` it is `width: 44px; height: 44px; padding-block:
14px; margin-block: -14px` — a 44 px target whose line stays 18 px; without
that half the floor's removal would have shrunk the touch target to 16 px.
In the release result it stands beside the remedy "Sync prices", both 44 px
tall and grown only vertically, so they do not overlap. Front matter:
`inline-result.dismiss`.

## Amendment 2026-10-03 — The phone at 390 px *(Sprint 18 pick H7, U5; issues 1012, 1033, 909 and 1050)*

Board `mockups/ux-design-2026-10-02/07-phone-390`, "after" and picks
H7.1 = A and H7.5 = A (plan D-8, silence adopts the recommendations); the
security Overview's figures are board `03-bond-master-data`'s rule ④. The
CSS rules are pinned in `test/invariants/css_layout_sweep_test.exs`.

### The quote phone row *(H7.1, pick A, rule ①; issue 1012)*

Under 560 px the Quotes tab's table wrapper (`#quotes-table-wrapper`) joins
the phone lists' hidden wrappers and `ul#quote-phone-rows.phone-rows`
(labelled "Quotes") shows one two-line row per quote of the range, in the
table's order: the date (`Format.date` since 2026-10-07, Sprint 19 U3;
ISO only in English; `.phone-row__name`) over the source badge
(`.phone-row__ids .badge.quote-source`) — the only per-row mark of a manual
close, which sat off-screen in the table's own scroller — and on the right
the close with the security's currency (`.phone-row__figure`), over
"stored <value>" (`.phone-row__figure2`) only where a split adjusted the
close, because elsewhere it would repeat the same number. Two tracks,
`minmax(0, 1fr) auto`, as the trades rows: no logo, no kebab. A row is
61 px against the table's 34. **No cap** on the rows (the board's stated
doubt, UX-DR26): the rows are the table rendered a second time, as every
phone list is, and the table itself carries the whole range; capping the
phone alone would make it say less than the desktop without a stated reason
of its own. "Max" on a long history renders accordingly.

**The basis line follows the layout** (the closing act's finding; board
`mockups/ux-review-2026-10-03/03-gamma-surface-repairs`, G6). The price-basis
line (`data-role="quotes-basis"`) said "Die Spalte Gespeichert zeigt die
unveränderten Werte." above rows that have no such column. It now carries
two spans: `.quotes-basis__table`, the table's sentence, and
`.quotes-basis__rows`, the rows' — "Kursbasis: … Wo ein Split einen Kurs
angepasst hat, zeigt „gespeichert“ darunter den unveränderten Wert." The
rows' span is out of the layout above 560 px; the phone lists' 560 px block
swaps the two as it swaps the table for the rows, so a screen reader reads
the one on screen.

### The sync's count of the manual quotes that stayed *(H7.1b; issue 1012)*

The quote sync keeps a manual quote wherever the provider returns a close
for the same day (`Quotes.upsert_many(…, protect_manual: true)`) and counts
it per security as `skipped_manual`. The page-level result
(`#securities-action-result`) now says so after either form of its first
sentence ("Kurse aktualisiert." or "Kurssync abgeschlossen: …"), summed over
every security the sync touched, through `ngettext`: "2 manuelle Kurse
blieben stehen, wo der Anbieter einen Schlusskurs lieferte." / "Ein
manueller Kurs blieb stehen, …". The verb repeats the Quotes tab's note
("lässt ihn stehen"); "übersprungen" stays reserved for a security the sync
does not query at all; the clause names what is counted — collisions, not
every manual quote, which the note counts. With none the result is the
first sentence alone. The OS notification carries the same text. Naming the
securities that kept them is possible from the per-security results and not
proposed.

### The release result's sync, and the single sync's reasons *(H7.4, code only; issue 1033)*

The release result's **Sync prices** (`data-role="release-sync"`) sends
`sync_quotes_released`: it syncs the selected security with
`QuoteSync.sync_security/2`, the row menu's path, where it ran the whole
catalog through `sync_now`. It clears the release result, as its next
action, and its own answer lands in the page-level `#securities-action-result`
— "Kurse aktualisiert." about this one security, with H7.1b's count of the
manual quotes that stayed. The toolbar's and the Chart tab's sync keep
`sync_now`: they mean every security. The single path's answer no longer
prints an atom where it skipped the security: "Kurssync übersprungen: Für
dieses Wertpapier gibt es keinen Kursanbieter." (`:no_provider_adapter`),
"… Der Kursanbieter braucht den Ticker des Wertpapiers."
(`:missing_ticker`), "… Das Wertpapier hat keine Währung."
(`:missing_currency`), "… Eine Kursaktualisierung dieses Wertpapiers läuft
bereits." (`:sync_in_progress`, the single-flight lock). A provider's own
error is printed as it answered. Whether the follow-up's result belongs in
the tab, beside its trigger, stays open; it lands where every sync result
lands.

### The detail's range labels *(H7.3; issue 1033)*

The Chart tab's range buttons printed the raw codes ("1M 3M 6M YTD 1Y 3Y 5Y
MAX") and the Quotes tab's basis line interpolated the same code, so a German
reader saw "Zeitraum 1Y" on every first visit while Wealth and the Overview's
KPI strip said "1J". One label function now serves both — German
"1M 3M 6M YTD 1J 3J 5J Max", English "…1Y 3Y 5Y Max"; "MAX" becomes "Max"
in both languages, the one casing EXPERIENCE.md → Period control changes.
`phx-value-range` and the URL keep the code; "1M", "3M" and "6M" are new
msgids that read the same in German; the fallback "Standard" stays. The
Overview's one-year figure label, a literal "1Y" in the template that this
part first left, goes through the same function since the closing act
(board `mockups/ux-review-2026-10-03/03-gamma-surface-repairs`, G3): "1J"
on the German Overview, as on the chart and the Quotes tab.

### The selected detail tab is in view on arrival *(H7.2, rule ②; issue 1033)*

The detail pane's nine tabs (about 760 px) overflow a phone's row, and the
selected tab is in the URL, so a reload, back or forward, a shared link,
the trades links (`?tab=trades`), Wealth (`?tab=transactions`) or the
Overview's "Fällig" rows (`?tab=events`) arrived on a row resting at
`scrollLeft: 0`: "Kurse" half under the right fade, "Termine" wholly outside.
No variant: D6 says the active tab is in view on arrival, and UX-DR22
rejects a wrapping row and an overflow menu. `DetailTabs` (the keyboard half
since #837) gains `AreaTabs`' mount half, copied rather than shared so that
hook keeps its tested form: on mount it scrolls the `aria-selected` tab into
the row's view with `scrollTo` on the row (never `scrollIntoView`, so the
page does not move), without animation under `prefers-reduced-motion`, to
the last tab start at or before its centring target at which the tab is
whole; it writes the trailing inset `--detail-tabs-tail` so the row's end is
a tab boundary; it marks `data-scroll-start` / `data-scroll-end` and the
fades follow (`.detail-pane-tabs` joins the three `.area-tabs` edge rules).
After a patch it restores the inset, the rest and the marks, and reveals a
selection the server changed; a tapped tab is already in view and scrolls
nothing. The server renders the row with `data-scroll-start`. Measured in
Chromium at 390 px on the seeded demo: "Kurse" rests with "Transaktionen"
first under a left fade; "Termine" rests at the end with no right fade.
At 1200 px with the sidebar the nine tabs fit and the row carries no mask.

### A long label inside an import summary card *(H7.5, pick A, rule ③; issue 909)*

`.import-stat-card .label` (13.6 px, uppercase, 0.04 em tracking) is a grid
item with `min-width: auto`, so "VERRECHNUNGSKONTEN" (about 180 px) could
neither wrap nor shrink: it ran 12 px past its card on the desktop and 23 px
past it — and past the screen — at 390 px. Pick A: the German label carries
a soft hyphen (U+00AD) at the compound joint, "Verrechnungs|konten" (the bar
marks it), so a card too narrow for the word breaks it there as
"VERRECHNUNGS-" / "KONTEN" in every browser, and a wide card shows nothing;
the rule `min-width: 0; overflow-wrap: anywhere` is the floor for any other
unbreakable word in any locale (it breaks without a hyphen, never past the
card). The soft hyphen lives in a card-scoped msgid,
`pgettext("import summary", "Cash accounts")`, used by the preview's and the
result's cards only, so the five other "Cash accounts" keep a plain msgstr.
The invisible-Unicode gate refuses a raw U+00AD; its own mechanism admits it,
an entry in `.unicode-allowlist.txt` with a written reason, and because that
entry can only name a file and a code point,
`test/invariants/soft_hyphen_scope_test.exs` holds it to the one msgstr.
Copying the label may carry the U+00AD in some browsers. The label's size
(13.6 px where the spec's `stat-label` is 12 px) is unchanged here.

### The history's phone row keeps its kebab at its end *(H7.6, rule ④; no issue)*

The history's two-line row has had three children since its row menu
reached the phone — the body, the figures and the kebab
(`#tx-phone-kebab-…`) — while `#transaction-phone-rows .phone-row` still
declared two tracks and a comment saying the row had no kebab. Grid
auto-placement put the kebab on a line of its own under the date, at the
left: every booking grew by the kebab's height (44 px on touch), and the
kebab read as the next row's. The rule now declares `minmax(0, 1fr) auto
auto`, its comment says why, and `.phone-row .row-actions__kebab
{ align-self: center }` keeps the kebab centred when the running balance
adds a third line on the right. The trades rows have no kebab and keep two
tracks.

### The security Overview's figures at phone width *(board 03, rule ④, a conformance repair; issue 1050)*

`.overview-metrics` is two per row under 720 px (this document, and the
`.overview-metrics` rule of `app.css`'s 720 px block), but the reading
surface's `.overview-reading .overview-metrics { repeat(3, minmax(0, 1fr)) }`
(issue 804) outranked it by specificity, so at 390 px the Overview's six
figures stood in three columns of about 105 px: "TAGESÄNDERUNG" ran into
"1Y" and "Durchschnittseinstand" spilled out of its cell. A 720 px block
restates the two columns at the reading surface's specificity,
`.overview-reading .overview-metrics { grid-template-columns: repeat(2,
minmax(0, 1fr)) }`. Board `03-bond-master-data` draws the before (its
phone-only frame) and the after; the bond strip U7 adds is the same grid in
the same column and inherits the rule. Filed at PR γ's opening as issue
1050, under Scope Lock.

## Amendment 2026-10-03 — Dialogs and messages *(Sprint 18 pick H8, Lane U6)*

Board `mockups/ux-design-2026-10-02/08-dialogs-copy` (plan D-8: the after
states, and **A** for the four picks H8.2, H8.4, H8.5 and H8.6; silence
adopted them). Eight repairs of words and small anatomy in dialogs, rows and
messages; each part names what was built.

### The rule dialog's version list *(H8.1, issue 910)*

- **One numbering, the label.** Each entry of "Versions" starts with
  "Version n", the label the version note above the list ("Saving creates
  version 4. Version 3 (7.5 %) is in force since …") and the retire
  confirmation name. The `<ol>` keeps its order but loses the browser's marker and indent:
  `.policy-rule-versions { list-style: none; padding-left: 0 }`, the one
  `app.css` rule of the part. Keeping "1." and dropping the label would have
  left the note's "Version 3" without a counterpart in the list.
- **`role="list"` on the `<ol>`**, because Safari drops the list semantics of
  a list without markers. The author of G12.1-A ("· Operator", "· Agent")
  stays the last word of each entry.

### Deleting a security: the confirmation and "Cannot delete" *(H8.2 = A, issue 918)*

Both texts now say what actually blocks a security's delete (ADR-0044, the
`:restrict` keys of `Lifecycle.ForeignKeys`); the delete path, the API and
MCP are unchanged. Built in `securities/row_context_menu.ex`.

- **The confirmation** (`data-confirm`, before any check, so in general
  terms): "Delete this security? Bookings, quotes, events, research entries
  and policy rules block the deletion. Removed with it: its
  classifications, position targets, bucket assignments and former ISINs,
  ~~each journaled~~ each recorded in the journal, and its logo." (de
  "Dieses Wertpapier löschen? Buchungen, Kurse, Termine, Research-Einträge
  und eigene Regeln blockieren das Löschen. Mit entfernt werden seine
  Klassifizierungen, Positionsziele, Bucket-Zuordnungen und früheren ISINs,
  ~~jede im Journal~~ jeweils im Journal festgehalten, und das Logo.")
  It no longer says research notes are lost: they block. (Amended
  2026-10-07, Sprint 19 PR γ U6's review: "journaled" is R10d's banned
  word in English as "journalisiert" is in German.)
- **"Cannot delete" names what blocks, counted** from the refusal's
  `{:referenced, counts}` (`PortfolixirWeb.ReferenceCounts`, the accounts
  page's "still has" as the precedent): "“Nordwind Industrie AG” still has
  12 bookings, 840 quotes and 3 research entries." (de "„…“ hat noch …"),
  the name in `<bdi>`, the parts in a fixed order (bookings, quotes,
  events, research entries, rule versions), joined "a, b and c" (de "und").
- **The second line, `p.muted`, gives the reason for the way out**, keyed
  on `Delete.remedy/2`:
  - research entries block it: "Research entries are never removed, and no
    merge carries them. Retiring hides the security from the active list;
    everything is kept." — footer Cancel, **Retire instead**;
  - only what a merge carries blocks it: "If it is a duplicate, “Merge
    into…” moves its bookings, quotes and events into the other security.
    Retiring hides it from the active list; everything is kept." — footer
    Cancel, **Merge into…**, **Retire instead** (events move in a merge,
    `merge: :repoint`, so the sentence names them);
  - a rule version without a research entry (rules are refused before the
    count, so only a race reaches it): "A rule version keeps the security
    as part of its rule's history, and no merge carries it. …"
- **Without counts** (a refusal that carried none) one sentence in general
  terms, variant B's: "“…” has bookings, quotes, events or research entries
  and cannot be deleted. Retiring hides the security from the active list;
  everything is kept." The policy-rule state (the rule list) is unchanged
  but for its name, now in `<bdi>`.
- **Words:** "events" / "Termine" for security events, as the merge record
  says; "research entries" / "Research-Einträge"; "policy rules" / "eigene
  Regeln" in the confirmation. At 390 px the three-button footer still
  wraps two labels (the design pass's Scope Lock note, a follow-up).

### Field errors in the security and account dialogs *(H8.3, issue 921)*

German at the field (EXPERIENCE.md, "Language (binding)"); the API and MCP
keep the English messages the domain builds. The mechanism is the dialog's:
it maps by the error's `validation:` key, as the rename dialog already did,
and the domain is unchanged.

- **A plain changeset message goes through the `errors` domain**, as on the
  transaction, rule and research surfaces: "can't be blank" reads "darf
  nicht leer sein", the ISIN check its German sentence.
- **The name guard** (`validation: :name_taken`) reads the rename dialog's
  words, now shared by both dialogs (`PortfolioAccounts.NameConflict`):
  "„Depot 1“ heißt bereits ein anderes Depot. Einen anderen Namen wählen
  oder jenes Depot zusammenführen oder umbenennen." — and for a former name
  "„Depot 2“ ist ein früherer Name von „Depot Süd“ — ein Import unter diesem
  Namen bucht dorthin. Einen anderen Namen wählen oder ihn bei „Depot Süd“
  entfernen." The holder is named by its name, never by its internal number.
- **The two taken-name sentences address no one.** They were the only
  `msgstr`s in `default.po` that said "Sie" ("Wählen Sie …, oder führen Sie
  … zusammen"); EXPERIENCE.md's impersonal voice binds, so they now read as
  above, in the rename dialog too.
- **The currency freeze** (`validation: :frozen`) has words of its own,
  with the page's nouns and counts (`PortfolixirWeb.ReferenceCounts`): "is
  frozen once referenced (2 bookings, 1 quote)" / "steht fest, sobald etwas
  darauf verweist (2 Buchungen, 1 Kurs)". The counts are read when the
  error is shown, as the domain read them when it refused.
- **Not covered here, named:** the security merge dialog's refusal line,
  the tax statement form and the snapshot form also interpolate changeset
  messages by hand, and they print the raw field key in front of each
  ("name can't be blank"). Translating the message alone would leave a
  half-German line, so they wait for a story that gives their fields labels
  too.

### The plan editor's Σ under 100 % *(H8.4 = A, issue 969)*

D3 above fixed the remainder row; this is the editor's half of it, built in
`classifications_live.ex` `soll_editor/1` and `put_sum/1`.

- **✓ means exactly 100 %, ✗ means above it.** The Σ row's cell reads
  "100% ✓" at exactly 100 %, and "104% ✗" with `is-target-mismatch` (the
  warning colour) above it, unchanged. **Under 100 % the Σ carries no glyph
  and no colour** ("92%"): next to 92 % a ✓ would contradict the row below
  it, and a ✓ that means "complete" in one state and "not wrong" in another
  means two things.
- **The remainder row** `tr.soll-row--remainder` is the `<tfoot>`'s last
  row, under the Σ, only while the Σ is under 100 % (no row reads "0 %"):
  "Not allocated" (de "Nicht verteilt" — not "Nicht zugeordnet", which is
  Allocation's Unassigned bucket; it matches the basis line's "allocated
  portion") and 100 − Σ in the page's number format, in the Σ's tabular
  slot (`data-role="soll-remainder"`). No input, not selectable. The `app.css`
  rule of the part: the row at ordinary weight, no border of its own, no top
  padding, the label in `{colors.text-muted}`.
- **One formula.** The remainder is 100 − the live Σ, cash target included,
  as `Allocation.unallocated_remainder/1` reads it from a top-level sum that
  includes cash — except on the built-in currency tree, where Allocation
  distributes cash into the currency categories and leaves the cash target
  out of its sum while the editor still counts it. That divergence predates
  this part and is recorded as a follow-up, not settled here.
- **The finding surface moves above 100 %.** The review rubric's walkthrough
  alarm is "a plan above 100 %", and `priv/demo/finding_surfaces_seed.exs`
  seeds one (a 20 % cash target on the demo's 85 % categories).

### The accounts rename dialog: the invisible-character notes *(H8.5 = A, issue 966)*

The G20 note (`AppShell.invisible_text_note/1`) in the rename dialog of
Accounts & depots, `portfolio_accounts/rename_dialog.ex`.

- **The current name** (A and B alike): one `attention` note after the form,
  before the former-name hint, `subject: :name`, following the field
  (`texts={[@name]}`) as in the rule dialog: "The name contains 1 invisible
  character. Typed in anew, it is clean." (de "Der Name enthält 1
  unsichtbares Zeichen. Neu eingegeben ist er sauber."), the name spelled
  `[U+XXXX]` behind "Name with the characters made visible". Typed in anew,
  it goes.
- **Former names are marked too (A).** Retyping is the remedy, and it turns
  the old spelling into a former name (former names are written without the
  text check), so after it the list shows "Depot Nord" under an account
  named "Depot Nord". When any former name carries such characters, a
  second note sits inside the open "Former names", above the list: "A
  former name contains 1 invisible character. An import that writes it
  exactly so keeps booking to this depot." (de "Ein früherer Name enthält 1
  unsichtbares Zeichen. Ein Import, der ihn genau so schreibt, bucht weiter
  auf dieses Depot."; "… to this account." / "… dieses Konto." for a cash
  account). Several marked: "Former names contain 3 invisible characters. An
  import that writes one of them exactly so …". Its disclosure "Names with
  the characters made visible" (de "Namen mit sichtbar gemachten Zeichen")
  spells each affected former name, those that arrived by a merge included.
  The list row carries no mark: the disclosure says which name it is.
- **The third subject of the note**, `:former_name`, with its sentence,
  plural and summary; the remedy sentence is the dialog's, per kind. The
  `app.css` rule of the part: `.rename-dialog details > .data-note {
  margin-top: var(--space-1) }`, one step below the summary, as the list.
- **Why A:** the former-name list is the one list in this dialog that can be
  edited, and whether that entry is removed decides whether an import still
  finds the account; the MCP companion already gives the agent the escaped
  spelling.

### The securities list when a row action finds its security gone *(H8.6 = A, issue 920)*

Built in `securities_live.ex` (`vanished/2`); the API and MCP are unchanged.

- **Reload, with one note.** A row action whose security was deleted or
  merged away since the list loaded (the API, MCP, another tab) no longer
  just closes the menu: the list reloads, and the page's inline result slot
  carries a `note` (UX-DR17: context, nothing is wrong): "“Meridian Global
  Equity ETF · XS0000000025” was merged into Meridian Global Equity ETF ·
  XS0000000017 meanwhile; the list is reloaded." (de "„…“ wurde inzwischen
  in … zusammengeführt; die Liste ist neu geladen."), or "“Helios Solar
  Systems SE” was deleted meanwhile; the list is reloaded." (de "„…“ wurde
  inzwischen gelöscht; die Liste ist neu geladen."). The delete's own "not
  found" branch says the same.
- **The names are the stale list's**, twins told apart as its rows were
  (`SecurityNames.label/2`); each sits in `<bdi>` (H8.8). A merge links the
  survivor, the end of `Lifecycle.merge_chain_end/2`'s chain, to its detail
  with the list's filters; a chain that ends at a deleted row reads as
  deleted.
- **What pointed at the security goes with the row:** a detail pane on it
  closes (the URL drops its id; the note stays across that patch), and an
  open edit dialog, "Cannot delete", the logo dialog or a merge's first step
  on it close too.
- **Why not silent (variant B):** for a delete the row going is what was
  asked for; for Edit, Retire or Merge into… it is not, and a row vanishing
  without a word reads as a lost click.
- **The note is brought to the operator, and takes the focus** (the
  closing act's finding; board
  `mockups/ux-review-2026-10-03/03-gamma-surface-repairs`, G1). The slot
  sits above the filters, so the note landed far above the window (measured
  −1142 px at 1280, −2611 px at 390) while the focus fell to `<body>` with
  the menu item. As H2's A6 does for a booking gone meanwhile: the slot
  carries `tabindex="-1"` (`AppShell.inline_result`'s `focusable`), and on
  this path only the page pushes `focus-into-view` with the slot's id; the
  layout's listener scrolls it to the top of the window — below the sticky
  top bar, by `#securities-action-result { scroll-margin-top }` — and
  focuses it without a second scroll. A keyboard user sees the house ring
  (`:focus-visible`, 2 px accent, offset 2 px); the next Tab reaches the
  survivor's link and the dismiss. Ordinary results land where they always
  did and move no focus: their control is still on the page. Never `<body>`
  (WCAG 2.4.3).

### Merge records: the result phrase and empty merges *(H8.7, issue 1032, the UI half)*

Built in `portfolio_accounts/merge_records.ex` and
`securities/merge_preview.ex`; the merge record's payload and
`GET /api/v1/merges` are unchanged.

- **The security phrase counts every removal**: "142 bookings moved, 2
  duplicates removed, **1 split collapsed**, 30 quotes added" (de "… 2
  Duplikate entfernt, 1 Split zusammengelegt, 30 Kurse ergänzt"), in the
  merge record list and in the result right after the merge ("Merged into
  …: …"). It uses the open line's own msgid (`pngettext("merge record",
  "%{count} split collapsed", …)`), after the duplicates. No total ("3
  removed") as an account merge reads: it would mix the operator's choice
  (duplicates) with an automatic step (a same-day split).
- **An empty merge reads "nothing to check" for every kind** (de "nichts zu
  prüfen"). The rule is in the words: the check line keys on the source
  having moved nothing — no booking moved, none removed. The cash writer
  checks today and the target's own booking dates, so its day count alone
  read "Balance confirmed on 3 days" for an empty source merged into an
  account with history; a payload change (the writer counting nothing when
  nothing moves) would have needed a contract entry and was not taken.
- **The liveness half changes no picture** and is not built here: the page
  already resolves a later-merged or deleted target from its own rows.

### Stored names in results and headings *(H8.8, issue 968)*

The `<bdi>` bullet of the G20 amendment above, carried to the results and
headings it named as a follow-up. One helper, `PortfolixirWeb.StoredText`,
replaces the rule dialog's own `frame/1` and `isolated/1`: the caller
translates with `StoredText.slot(:name)` in place of each stored value, and
`StoredText.isolate/2` escapes the translation and sets each stored value in
its own `<bdi>`. An inline result's message may be that markup (it was
`:any` already).

- **Results:** the securities row actions ("Retired %{name}", "Reactivated
  …", "Marked … as benchmark", "… is no longer a benchmark", "Deleted …",
  "Created …", "Updated …", the raced delete), the security merge's "Merged
  into %{target}: …", the account merge's "Merged %{source} into %{target}:
  …", the account page's raced delete, and the import's remembered-name
  lines (each of their names).
- **Headings:** "Rename — %{name}", "Merge %{name}" (accounts and
  securities), "Set balance — %{name}", "Release manual quotes — %{name}",
  "Buckets for %{name}", "Comparison against “%{name}”", and the rule
  dialog's "Change rule — “%{name}”" as before. A heading that ends with the
  name renders the same either way and is isolated anyway, so the rule has
  no exceptions.
- **The picture changes only for such a name**: a stored U+202E with no
  U+202C after it reverses up to the end of the `<bdi>`, so "Nordwind
  Industrie AG stillgelegt" keeps "stillgelegt", and "Depot Nord
  zusammenführen" keeps "zusammenführen"; the name itself still reads oddly,
  and the G20 note marks it where it is renamed. No `app.css` rule:
  `<bdi>` isolates by itself.
- **Not covered, stated:** attribute strings — `aria-label`, `title`,
  `data-confirm` — cannot hold `<bdi>`; they keep the plain name. Running
  text inside a dialog's body that names a stored name (the merge previews'
  sentences, the plan editor's labels) is not a result or a heading and is
  left as it is.
- **One body sentence joined, for its punctuation:** the split wizard's
  first sentence ended with the security's name and added its own full stop,
  so a name ending in an abbreviation read "… Namens-Aktien o.N..". It now
  quotes the name, in `<bdi>`, and goes on after it with a comma — "Stock
  split for “%{security}”, the ratio as new:old shares — …" (de "Aktiensplit
  für „…“, das Verhältnis als neue:alte Aktien — …") — so no name's last
  character meets a full stop of the app's (the closing act's finding;
  board `mockups/ux-review-2026-10-03/03-gamma-surface-repairs`, G7).

## Amendment 2026-10-03 — Deleting a booking, and Edit on the kinds the drawer does not book *(Sprint 18 picks H2 = A and H2b = A, U1; issue 912)*

Board `mockups/ux-design-2026-10-02/02-booking-delete`, variant A of both
questions (plan D-8; silence adopted them). The closing act's repairs —
R1–R10, cited below where they change the anatomy — are boarded before and
after in `mockups/ux-review-2026-10-03/02-delete-dialog-repairs`. The missing human view of the
API's and MCP's delete (plan D-6): the screen now deletes every kind of
booking, a split as the one fact it was booked as. Built in
`PortfolixirWeb.Transactions.BookingDeleteDialog` (the dialog, its words and
its write), `TransactionManagementLive` (the row menu, the notes-only
drawer) and, for the link from **Record split**, `SplitWizardDialog` and
`SecuritiesLive`. The writes are the API's: `Ledger.delete_transaction/2`
for a booking, `Splits.delete_split/2` for a split — every row of the event,
in every portfolio, in one journaled step (its API and MCP twins are
`DELETE /api/v1/splits/:transaction_id` and `portfolixir.splits.delete`, an
admin tool).

### The row menu *(A1)*

- **Edit · Delete…** on every history row of every kind, Delete last, in
  `.row-context-menu__item--danger` with the trash glyph: the order by
  consequence of the accounts and securities menus. The ellipsis says a
  dialog follows, as in "Merge into…".
- **The phone sheet names its row**: the menu passes `caption_name`, the
  `row_name/2` the kebab's label already composes, and `caption_kind`
  "Transaction" — "Kauf, Global Aktien ETF, 22.09.2026 · Transaktion". The
  sheet said nothing about its row before. The kind is one span
  (`.row-context-menu__kind`, `white-space: nowrap`) glued to the name's
  last word by a no-break space, so a long name — a twin's — wraps inside
  itself and "22.09.2026 · Transaktion" moves as one piece: no line starts
  with "·" or holds the kind alone (closing act R10g; `AppShell.row_menu`,
  so the accounts' sheet too).

### The dialog *(A2–A6)*

- **Shape.** A native `<dialog class="modal booking-delete-dialog">` on the
  `ModalDialog` hook, titled "Delete transaction" ("Transaktion löschen"),
  the quote release's narrow destructive modal: `.booking-delete-dialog`
  joins the `.quote-release-dialog` selector lists (460 px; under 720 px the
  merge dialog's bottom sheet, the confirm on its own line above Cancel,
  44 px buttons) — rule ①, a list membership, not a copy.
- **The booking, said back** (rule ②): `.booking-delete__subject`, a
  bordered box (`--color-border`, `--radius-md`, `--color-bg`, padding
  `--space-2` `--space-3`) holding the history's own phone-row parts at every
  width — "22.09.2026 · Kauf" over "Global Aktien ETF · Depot 1" (a transfer
  "Girokonto → Tagesgeld"), and on the right the signed amount the history
  shows over its size ("40 × 62,50"; one unit "1 Stück", English "1 unit").
  The menu no longer hangs at its row once the dialog is open; the box says
  which row was meant. It is built from the row **as stored now** (R6): the
  booking is read again when "Löschen…" is chosen, as Edit reads it, and a
  row gone since answers A6 at once.
  - **A twin security** (a name another security carries) is named as the
    row's kebab names it, with its ISIN — else its ticker, else "Nr. …":
    "Global Aktien ETF · DE000SYN0A17 · Depot 1", for a booking and a split
    alike, and so is the result (R4).
  - **The account it names** is the one the sentence names: a booking that
    moves shares names its depot, one that moves only cash its cash account,
    even when it carries a depot (an imported dividend; R10f).
  - **Each stored name sits in its own `<bdi>`** (H8.8), the " · " and
    " → " outside (R7); the subject line is one inner span, the single flex
    item of `.phone-row__ids`.
  - **A long unbroken name wraps inside the dialog**: `.booking-delete-dialog
    .hint` and `.booking-delete__subject .phone-row__ids > span` take
    `overflow-wrap: anywhere; min-width: 0`, so at 390 px nothing widens the
    sheet (R8; the closing act measured 28 px over).
- **What changes, concretely** — one `.hint` sentence built from
  `Projection.effects/1`, the one reducer per kind, read in reverse, so no
  sentence is written per kind: the quantity legs first, then the cash legs,
  "Danach hält Depot 1 40 Stück Global Aktien ETF weniger, und Girokonto hat
  2.504,90 EUR mehr." (the cash leg is the cash the booking moved, fees
  included). **A quantity is stated at today's count** (R1): each depot's
  position today with and without the booking, the holdings' own fold, so a
  buy of 10 before a 2:1 split reads "20 Stück weniger" (a 1:2 reverse
  split "5"), for sells, deliveries and transfers alike; the box keeps the
  booking's own figures. A set balance has its own sentence ("Danach trägt
  Girokonto keinen am 30.09.2026 gesetzten Saldo mehr; sein Stand folgt
  wieder den Buchungen."). **Where a later set balance anchors an account
  the booking moves** (ADR-0009), that account's clause carries its bound
  and the next sentence says from when nothing changes (R2): "… und
  Girokonto hat bis zum 30.09.2026 2.504,90 EUR mehr. Ab dem am 01.10.2026
  gesetzten Saldo bleibt der Stand von Girokonto unverändert." — each
  account bounded by its own first set balance on or after the booking's
  day. A balance set on the booking's own day applies after it, so the
  account changes on no day and the clause names no amount: "… und der
  Stand von Girokonto bleibt, wie er am 22.09.2026 gesetzt wurde." Then the
  general sentence: "Bestände, Kontostände, Rendite und Trades werden ohne
  diese Buchung neu berechnet." Stored names sit in `<bdi>` (H8.8).
- **The journal, honestly:** ~~"Das Journal behält die Buchung mit allen
  Werten; zurückholen kann die Oberfläche sie nicht."~~ **Amended 2026-10-07
  (issue 1090, Sprint 19 PR γ U6; board
  `mockups/ux-design-2026-10-04/08-copy-dialogs` ⑥):** "Das Audit-Journal
  hält die Löschung mit allen Werten fest; wiederherstellen lässt sich die
  Buchung nicht." (English "The audit journal records the deletion with
  every value; the booking cannot be restored.") — what the journal keeps
  is a record of the deletion, not the booking, which the first-look
  persona read as both kept and gone. Hence danger, not primary, as in the
  quote release.
- **An imported booking (A3)**: one `attention` data note — "Diese Buchung
  stammt aus einem Import. Gelöscht, kennt der Import sie nicht mehr: Ein
  erneuter Import derselben Datei bucht sie wieder." (plain words, R10d; it
  said "Inhalts-Hash" before). The behaviour is unchanged (plan D-6); the
  note says it.
- **The band foot**: Cancel (ghost, `autofocus`, so the dialog opens on it),
  the spacer, then `.button-danger` naming the act. **One confirmation**:
  no `data-confirm` after it. The issue-765 rule ("every destructive control
  carries data-confirm") keeps its exception where a destructive dialog is
  itself the confirmation — the quote release, this delete — and the
  `layout_view.ex` note says so.
- **After (A5)**: the page's own ~~`.alert-success`~~ result slot, "Transaktion
  gelöscht: Kauf · Global Aktien ETF · 22.09.2026."; the row is gone and the
  month subtotal follows (since 2026-10-07 the head's count, issue 1083).
  **Gone meanwhile (A6)**: ~~`.alert-error`~~ "Diese
  Transaktion existiert nicht mehr.", the history reloaded — the one refusal
  the API states. *Amended 2026-10-07 (issue 1064, pick J7 = A):* the slot is
  `AppShell.inline_result` (`#transactions-result`): A5 is a note
  ("Hinweis", the asterisk), A6 a problem ("Problem", the octagon), each with
  its dismiss; under coral in the dark theme the two alerts were
  pixel-identical and said no word. The dialog warns about nothing the API does not check (no
  dependency check: a later sale may lose its purchase).
- **Focus** (R3, WCAG 2.4.3). The dialog's opener, the menu item, is gone
  when it opens, and after a delete so is the row. The `ModalDialog` hook
  takes the opener while it is on the page; else the first visible of
  `data-focus-return` — the row's kebabs, `#tx-kebab-<id>` and
  `#tx-phone-kebab-<id>`, whichever this width shows — so Abbrechen, Esc
  and × leave the page where it was with the ring on the row's kebab; only
  when the row is gone (a confirmed delete, A6) does `data-focus-fallback`
  take it: the history's heading (`#transaction-history-heading`,
  `tabindex="-1"`), or **Record split** on the security's page. The focus
  moves only when it went with the dialog. A result the close shows
  (`data-focus-result`, the page's ~~`[data-role="page-result"]`~~ shown
  note, `#transactions-result .data-note` since 2026-10-07) comes into
  view first, then the target takes the focus without scrolling and is
  brought into view only when it is out of it; the result, the heading and
  the kebabs land below the sticky top bar (`scroll-margin-top:
  calc(var(--topbar-height) + var(--space-3))`). The Edit drawer, buy/sell
  and notes-only, returns the focus the same way on every exit — it fell to
  `<body>` before — and "Notiz gespeichert" is in view when it shows.

### A split, deleted whole *(A4, A7, A8)*

- **"Delete…" on any split row** opens the same dialog titled "Split
  löschen": the box reads "15.09.2026 · Split" over the security, "2:1" over
  "2 Zeilen"; "Der Split ist in 2 Portfolios gebucht, Hauptportfolio und
  Sparplan-Portfolio; beide Zeilen werden in einem Schritt gelöscht.";
  "Danach zählen die Bestände von Kestrel Robotik SE ab dem 15.09.2026
  wieder ohne den Split, und das Diagramm rechnet seine Kursreihe ohne ihn;
  gespeicherte Kurse bleiben, wie sie sind."; "Das Audit-Journal hält die
  Löschung beider Zeilen fest." (amended 2026-10-07, issue 1090: the
  delete dialog's verb, where it said "the journal keeps both rows").
  The confirm reads "Split löschen (2 Zeilen)". The result: "Split
  gelöscht: Kestrel Robotik SE · 2:1 · 15.09.2026, 2 Zeilen." **A split in
  one portfolio names no row** (R10d): the box shows the ratio alone, "Der
  Split ist nur in Hauptportfolio gebucht.", "Das Audit-Journal hält die
  Löschung des Splits fest." (amended 2026-10-07, issue 1090; it said "Das
  Journal behält den Split."; three rows and more: "… die Löschung aller 3
  Zeilen fest"), the confirm "Split löschen", the result "Split gelöscht:
  Kestrel Robotik SE · 2:1 · 15.09.2026."
- **The confirm keeps to the rows the dialog listed** (R5). The dialog
  carries the event — security, date, normalized ratio — and the ids it
  listed; the confirm reads the event's rows again, anchors the delete on
  any of them still stored, and holds it to the listed ones under the
  event's lock (`Splits.delete_split/3`, `only:`). The row it was opened
  from deleted alone meanwhile: the rest are deleted as promised. A row the
  dialog did not list (a re-book in another portfolio): nothing is deleted
  and the dialog shows the new state with the merge dialogs' changed-plan
  note, an `attention` data note in a `role="status"` region at the head of
  the body (`.booking-delete__region`, which takes no room while empty):
  "Der Split hat sich geändert, während dieser Dialog offen war. Nichts
  wurde gelöscht; der Dialog zeigt jetzt den neuen Stand." — confirmed
  again, it deletes what it now lists. No row left: A6.
- **A7, the split drawer's help line gets its way**: "Stichtag, Verhältnis
  und Wertpapier eines gebuchten Splits stehen fest. Ein falscher Split wird
  gelöscht und danach am Wertpapier mit „Split erfassen“ neu erfasst." and
  the `.link-button` **Split löschen…**, which closes the drawer and opens
  the dialog — never a dialog from a dialog (UX-DR9). This supersedes the
  "without a link" of the G12.3 amendment. Under `pointer: coarse` the
  remedy is a 44 px target — `.form-help .link-button` joins the coarse
  rule of `.data-note__body .link-button` (H6.1: 13 px block padding given
  back as a negative margin, so the line keeps its height) — and on
  keyboard focus it draws the 2 px accent ring (R9).
- **A8, "Record split" links to it.** The conflicting-ratio warning names
  the booked ratio — "Für dieses Wertpapier ist an diesem Datum bereits ein
  Split mit anderem Verhältnis gebucht (2:1). Die Buchung wird abgelehnt,
  solange er steht, und die Vorschau zeigt keine Stückzahl danach." (the
  second clause amended 2026-10-07, pick J8 = A: Components → Amendment
  2026-10-07 → The split wizard under a conflicting ratio) — and carries
  **Gebuchten Split löschen…**; the booking
  refusal (a conflicting or an already booked split) carries the same link.
  It closes the wizard and opens the dialog on the security's page, so the
  delete and the rebooking happen in one place. `.alert-warning
  .link-button` and `.alert-error .link-button` take the same 44 px coarse
  floor and accent `:focus-visible` ring as the drawer's remedy (R9). The board's fallback (a link
  to the history) was not needed: the dialog is one function component
  with one handler per page.

### Edit on the kinds the drawer does not book *(H2b = A)*

- **The notes-only drawer** is the G12.3-A split state, generalised to
  every kind outside buy and sell (the drawer books only those, AGENTS.md
  goal 4). The same `dialog.detail-pane.booking-drawer`, titled "Edit
  transaction"; the sub line says the limit before anything is tried — "Die
  Art „Dividende“ bucht die Oberfläche nicht; hier ändert sich nur die
  Notiz, und das Journal hält die Änderung fest." (a set balance: "Ein Saldo
  wird unter Konten & Depots gesetzt; …"; a split keeps its own). English
  names the kind as a kind — "The screen does not book the kind
  “Interest”; …" — never with an article that fits no label (R10a), and all
  three say "the journal records the change", never "journaled" (R10d).
- **The facts, disabled**, with the words the history and the drawer
  already use, the fields following the kind's stored fields: Typ and Datum
  (a split: Stichtag), then the security where the booking has one, and per
  kind — a cash kind its Verrechnungskonto, "Betrag (EUR)" and, for a
  dividend or interest, Steuern; a cash transfer "Von Konto" and "An Konto"
  and its amount; a delivery its Depot, Stückzahl and Preis; a security
  transfer "Von Depot", "An Depot" and Stückzahl; a set balance its account
  and "Saldo (EUR)"; a split its ratio. Ids are general now: `#note-form`,
  `#booking-facts`, `#booking-edit-help`, the fields `note[…]`. A figure
  reads with the digits it was stored with, trailing zeros trimmed and at
  least two places — a price of 41,1234 stays 41,1234, an amount of 1500
  reads 1.500,00 (R10c; it was rounded to two before). *Amended 2026-10-07
  (the Sprint 19 PR γ closing act):* every stored digit up to four decimal
  places, so a price the PP JSON importer derived at scale 6 (72,621176)
  reads 72,6212 — the history's Price column, which shares the rule, says
  why (Transactions — the target vocabulary). *Amended again the same day
  (the closing act's cascade, layer 2):* a figure under 1 keeps at least
  three significant digits (0,000045 stays 0,000045, 0,001234 reads
  0,00123), so no non-zero figure reads as zero.
- **The help line** states the limit and both correction paths where the
  correction is tried (UX-DR26): "Datum, Beträge und Konten dieser Buchung
  stehen hier fest; die Oberfläche bucht nur Käufe und Verkäufe. Korrigiert
  wird die Buchung über API oder MCP, oder sie wird gelöscht und neu
  importiert." — for a booking an import brought in (`import_hash` set);
  any other came over the API or MCP and reads "…, oder sie wird gelöscht
  und dort neu gebucht." (R10e); a set balance "…oder er wird gelöscht und
  unter Konten & Depots neu gesetzt" — and carries **Löschen…**, opening
  the delete dialog.
  The Notes field stands open under it, with **Notiz speichern** and
  **Abbrechen**; a booking save pushed at this drawer changes nothing.
- **Stated, not settled here:** the API's and MCP's update corrects every
  field of these kinds in place; the screen changes only the note. That
  two-way gap is outside this pick (the design pass's Scope Lock) and the
  help line is its stated limit until it is built. Dialog count: one more
  native dialog — eighteen `<dialog>` elements in `lib/portfolixir_web/`,
  still with zero `aria-modal`.

## Amendment 2026-10-03 — Securities detail: bond master data and key metrics *(Sprint 18 pick H3 = A, U7; issue 330)*

Board `mockups/ux-design-2026-10-02/03-bond-master-data`, variant A (plan
D-8; silence adopted it): the bond's data in the Overview, not a tab of its
own. Built in `PortfolixirWeb.Securities.BondStrip` (the block and the
two-scales note), `SecurityFormDialog` (the bond section) and
`PortfolioLive.data_quality/1` (the Wealth finding), over
`Portfolixir.Portfolios.Bonds.reading/2` — the reading the API's
`GET /api/v1/securities/:id` serves as `bond`, so the screen and the agent
read one set of figures (ADR-0052). Nothing renders for any asset class
but `bond` and `government_bond`, read as the effective class.

### The bond block *(A1, rule ①)*

- **Placement.** One more block in the Overview's main column, directly
  under the six figures and above the chart: `section.bond-strip`
  (`data-role="bond-strip"`). Its heading "Anleihe" is an `h3` in the
  overview-card head voice — `.bond-strip__head h3` joins the
  `.overview-card__head h3` rule — because it is the one thing that tells
  the two grids apart. The grid **is** `.overview-metrics`, three by two,
  two per row under 720 px (rule ④, which issue 1050 carried); the basis
  line **is** `.detail-tab-hint`, as under the ADR-0047 grid.
- **First row, what was entered:** *Fälligkeit* (the date through
  `Format.date`, "15.06.2031" — ISO until 2026-10-07, Sprint 19 U3; sub-line
  "Emission <date>" when an issue date is set), *Kupon* ("2,5 %" with the
  unit "p. a."; sub-line *jährlich* or *halbjährlich*, or *keine
  Zinszahlung* for a zero coupon), *Nominal im Bestand* ("10.000,00" with
  the face value's currency; sub-line "100 Stück × 100 EUR · Stückelung
  1.000 EUR" — the hundredth convention as a sum, the denomination beside it
  so "Stück" and "Stückelung" are not read as one unit; "—" while nothing is
  held).
- **Second row, what follows, each under its input:** *Restlaufzeit* ("4 J.
  8 M."; sub-line "4,70 Jahre ab <today>"), *Laufende Rendite* ("2,57 %";
  sub-line "2,5 ÷ 97,25 (<quote date>)", or "2,5 ÷ 98,5, letzter eigener
  Handelspreis" while the valuation prices by the own trade, board A4),
  *Rendite bis Fälligkeit* ("≈ 3,17 %"; sub-line *linear angenähert*).
  What is computed — the yields and the years — at two places; what is
  stored — the coupon, the price in the ratio line, the quantity and the
  denomination — as stored, trailing zeros trimmed (`Format.exact`): a
  coupon of 4,125 % reads "4,125 %" and its ratio "4,125 ÷ 97,125", never
  "4,13 ÷ 97,13" beside a yield computed from 4,125 (closing act on U7,
  finding 2; board `ux-review-2026-10-03/04-bond-repairs` B1).
- **The basis line** (`data-role="bond-basis"`) says once what the figures
  are, how they are made and what they leave out: coupon and price in
  percent of face, one unit a hundredth of the nominal, so the price is also
  the price per unit; current yield = coupon ÷ price; the remaining term in
  calendar days from today, a year of 365 days; the yield to maturity
  linearly approximated, (Kupon + (100 − Kurs) ÷ Restlaufzeit in Jahren) ÷
  Kurs, without compounding; without accrued interest, fees and taxes;
  reported, not evaluated.
- **One deliberate departure from the board:** the coupon's sub-line names
  the frequency, not a payment day ("am 15.06."). The master data carries no
  coupon date, and taking it from the maturity is an assumption the screen
  does not make.

### Its states *(A2–A4)*

- **Nothing entered** (no coupon, no maturity, no denomination — a fresh
  import): one sentence instead of six dashes, "Kupon, Fälligkeit und
  Stückelung sind nicht erfasst; ohne sie gibt es keine Restlaufzeit und
  keine Rendite.", whose remedy **Anleihedaten erfassen…** is a
  `.link-button` opening the same dialog as *Edit* (UX-DR17: the remedy is
  a child of its sentence). Under a coarse pointer it is a 44 px target in
  place, by the H6.1 rule (*The remedy inside a data note*), of which it is
  the second selector. The nominal stands under it as a hint, with the
  convention, since it needs no master data.
- **Partly entered:** the grid; a cell whose input is missing reads *nicht
  erfasst*.
- **Not computable:** *nicht berechenbar*, the reason in the sub-line —
  *fällig*, *kein Kupon erfasst*, *keine Fälligkeit erfasst*, *kein Kurs*,
  or "Handelspreis 0,984 je Stück, keine Prozentnotiz" when the yields
  would fall back to an own trade price of at most 5 (the two-scales band's
  mirror, 100 ÷ 20; closing act on U7, finding 3, board
  `ux-review-2026-10-03/04-bond-repairs` B2). No percent figure stands in
  either cell then: "254,07 %" from 2,5 ÷ 0,984 is a booking of the
  nominal, not a yield. The guard is silent without a quote, so the reason
  is the only place the unit scale shows before one is stored.
- **Matured** (on and after the maturity date): the term reads *fällig*,
  sub-line "seit <date>", and both yields *nicht berechenbar · fällig*. No
  redemption amount is computed; a redemption is a booking.
- `.overview-metric__sub time` and `.overview-metric__sub .nowrap` keep a
  date and a figure with its unit whole at 390 px (rule ③).

### The dialog's bond section *(F1, F2, rule ②)*

- `fieldset.bond-fieldset` (`data-role="bond-fields"`), legend
  "Anleihedaten", between the master data grid and the raw-quotes toggle,
  present while the asset-class select reads *Anleihe* or *Staatsanleihe* —
  on create (search, manual) and on edit alike; the dialog's `form_change`
  re-renders it as the select changes. Since 2026-10-06 (issue 1068, D-15)
  it is also present while the select reads blank on the edit of a security
  that stores a maturity date or a coupon — the data that makes it a bond —
  so that data can be seen and cleared where it was entered (same anatomy,
  no new board). `.bond-fieldset` **joins the
  `.settlement-fieldset` selector lists**: the same block shown only when it
  applies, not a copy.
- Fields: *Kupon p. a. (%)* and *Stückelung (Nennwert)* follow the
  numeric-input rule (`inputmode="decimal"`, `class="num"`, read by
  `DecimalInput` in the page's locale — "2,5", not "0,025"); *Zinszahlung*
  a select of two words, *jährlich* and *halbjährlich*, never the stored
  value; *Fälligkeit* and *Emissionstag (optional)* ISO text fields
  (UX-DR19); *Währung des Nennwerts* a currency select that starts on the
  security's currency and is written only beside a *Stückelung*: a save
  that sets no denomination stores no currency, so the preset is never
  written behind the operator's back (closing act on U7, finding 8; the
  select's picture is unchanged). One `.form-help` line states the convention ("Im
  Bestand ist ein Stück ein Hundertstel des Nominals: 100 Stück sind 10.000
  Nominal. …").
- **Errors on their field**, in the page's language (F2): the ambiguity
  message of `DecimalInput` under a grouped figure, "muss nach dem
  Emissionstag liegen" under a maturity on or before the issue date, the
  bounded-date and range messages likewise. Nothing is stored on a refusal.
  **One round:** a figure `DecimalInput` refuses stops the write, but the
  rest of the form is still checked by the security's changeset, writing
  nothing, so "1.000" as the coupon and a maturity before the issue date
  show both errors after one save, as board 03 draws them (closing act on
  U7, finding 7; board `ux-review-2026-10-03/04-bond-repairs` B5).
- **Nothing is required**; while editing, an emptied field clears its
  value; the values are kept when the class changes away from a bond, and
  the screen then hides them.
- **Only an edit clears** *(closing act on U7, finding 1)*. The section
  starts on the stored values only while editing. On create and on the two
  conflict paths — "Vorhandenes aktualisieren" and "Online-Felder
  übernehmen", whose section starts blank over a security that may already
  carry master data — a blank field is no change, so resolving a duplicate
  never wipes a bond's coupon, maturity or denomination.

### The two-scales note *(W1 and W2)*

- **On the Overview** (W1): a **problem** data note at the top of the
  Overview panel, above the figures it concerns (`data-role=
  "two-scales-note"`): "**Auf zwei Skalen bepreist:** Kurse um 100 (zuletzt
  97,25 am <date>), gebuchter Preis je Stück um 1 (1 Buchung: 0,985 am
  <date>).
  Dann ist das Nominal als Stückzahl gebucht, und Wert, Gewinn und Gewicht
  sind hundertfach zu hoch; die Rendite (TTWROR) zeigt es nicht. Stückzahl
  gegen das Nominal der Abrechnung prüfen: Transaktionen" — the last word a
  link to the security's Transactions tab. With several such bookings: "(3
  Buchungen, zuletzt 0,985 am …)" — a booking is a buy or a priced inbound
  delivery (closing act on U7, finding 4, board
  `ux-review-2026-10-03/04-bond-repairs` B3). The figures stay as stored and
  the block
  shows the consequence (1.000.000,00 nominal for a purchase of 9.850,00);
  nothing is converted and no rescale is offered.
- **Where the total is read** (W2, UX-DR25): the seventh condition of Wealth
  → Holdings → *Datenqualität*, a problem note after the negative holdings
  (`data-role="dq-two-scales"`), naming each bond the valuation holds with
  "(Kurs 97,25 · Preis je Stück 0,985)" and linking each name to its
  Transactions tab, as the negative-holdings note does; the sentence asks
  for "Stückzahl ihrer Buchungen". The link's text is the name alone, so
  its underline ends at the name, and one space stands between two entries
  — "… 0,985) Ostsee …" — outside them, since an entry is an inline block
  whose own edge whitespace does not render *(closing act of PR α, UAT;
  both two-scales notes)*.
- **The reverse case** *(2026-10-06, issue 1068, plan D-15; board
  `mockups/ux-design-2026-10-04/02-money-notes`, pin 4)*: a problem note of
  its own right after it (`data-role="dq-two-scales-reverse"`): "Eine
  Anleihe ist auf zwei Skalen bepreist (Kurse um 1, gebuchter Preis je Stück
  um 100) und zählt hundertfach zu niedrig in den Summen. Ihre gespeicherten
  Kurse prüfen — ein Kurs um 1 ist kein Prozent vom Nennwert:", in the
  plural "2 Anleihen sind … und zählen …" as the forward note's. Each name
  links to its security's **Quotes** tab, with "(Kurs 0,981 · Preis je Stück
  98,4)" — the figures as `Format.exact` writes them, as in the forward
  note. Separate because both the consequence and the remedy point the
  other way: the quotes are on the wrong scale, not the booked quantity
  (one finding per note, UX-DR17). The rule: the latest stored quote is
  1/500 to 1/20 of a booked price per unit, the forward band inverted, and
  itself at most 5 (100 ÷ 20), so a percent quote beside a denomination
  booked per piece is not called "Kurse um 1". The security's own Overview
  note (W1) states the forward direction only; a reverse finding renders
  nothing there yet (issue 1112, needs a board).
- **The "ohne Anlageklasse" badge** *(2026-10-06, issue 1068, board 02,
  pin 3)*: a named bond that shows no asset class — none stored, none
  inferred, as the list and the dialog show it — carries `badge
  badge--neutral` "ohne Anlageklasse" after its name, before the figures,
  in either note — the Overview's "ohne Bestand" anatomy — so the reader
  sees why a security the catalog does not call a bond is named. Every
  other word of the forward note is unchanged.
- **Silent** without a quote, when the scales agree, for an unclassed
  security with no bond master data, for a name the inference reads as a
  structured product, and for every security shown under another class,
  stored or inferred. A security is read as a bond when its effective class
  is `bond` or `government_bond`, or when it shows no class (none stored,
  none inferred) and carries a maturity date or a coupon (D-15). The rule: the latest stored quote is 20
  to 500 times a booked price per unit, a buy's or a priced inbound
  delivery's (ADR-0052 §4), or 1/500 to 1/20 of one (the reverse case).

### Settled here, from the board's stated doubts

- The linear approximation is (C + (100 − P) ÷ n) ÷ P, named in the basis
  line and the payload; the other common form is not shown.
- A trade-priced bond's yields use the valuation's price, the last own trade
  price, and say so; the guard compares the latest quote with each booked
  price per unit, so a mixed history is named by the bookings on the unit
  scale.
- ~~The reverse case (quotes near 1, bookings near 100) is not named; the
  guard keys on the effective asset class, so a bond the inference does not
  recognise escapes it (ADR-0052, Consequences).~~ **Amended 2026-10-06
  (issue 1068, plan D-15, ADR-0052's dated note):** the reverse case is
  named, in Wealth's `dq-two-scales-reverse` note; and the guard reads a
  security as a bond by its class **or**, while it shows no class (none
  stored, none inferred), by its maturity date or coupon, a bond named that
  way carrying the neutral "ohne Anlageklasse" badge. It still does not read
  an unclassed security with no master data, nor a certificate.
- ~~The dashboard's data-quality line does not count the finding: that line
  counts the catalog's hygiene sets, and the two scales are read where the
  total they inflate is read.~~ **Amended 2026-10-06 (issue 1068, plan
  D-15):** the line counts the bonds priced on two scales, both directions,
  at problem severity, linking to `/securities?dq=two_scales` (Components →
  Data quality). The count is catalog-wide on purpose: a sold-out, retired
  or benchmark bond's booked history — its past values and realized result
  — is as far off as a held one's total, and that is the alarm the line
  exists for.
- The six figures' cells stay as they are: "Bestand 100 Stück" and "Letzter
  Kurs 97,25 EUR" are not relabelled; the block and its basis line carry the
  convention.

## Amendment 2026-10-06 — Import preview: rows that fail alone, and the parser warnings as an attention note *(Sprint 19 board 09's conformance repairs, PR β B4; issues 1044 and 948)*

Board `mockups/ux-design-2026-10-04/09-import-correction`, part ②, a
before/after with nothing to pick, and its "Found while drawing" list for
the Imports page. Built in `PortfolixirWeb.ImportsLive`, the two parsers and
`Imports.PortfolioPerformance.row_error/1`.

- **New row-error reasons.** Each joins the parser warnings in the existing
  shape, "Row N: <reason> — row not imported", is counted in the "Warnings"
  card, and leaves the rest of the file to preview and import; the confirm
  never starts on the row. The "Row N" prefix is unchanged; **a CSV row is
  numbered as a spreadsheet shows it, the header being row 1** *(2026-10-08;
  issue 1128, Sprint 20 PR α A5; board
  `mockups/ux-design-2026-10-07/01-import-preview` ⑤)*, so the first booking
  is row 2. The number moves everywhere a CSV row is named — the parser
  warnings, the receiving side's "booked once, from that row", every list
  on the done page, the correction section and a split-off refund's note —
  and the anatomy nowhere. No content hash reads it. A JSON row's number is
  untouched (its own issue).
  - **A row with no account to book on.** A CSV transfer row, a cash or a
    security transfer, the sending or the receiving side, with a blank
    `Gegenkonto`: "transfer without a counter account — row not imported" /
    "Umbuchung ohne Gegenkonto — Zeile nicht übernommen"; with a blank
    `Konto`: "transfer without an account — …" / "Umbuchung ohne Konto — …".
    One name in both is no row error: the apply skips that transfer and lists
    it under the internal transfers (ADR-0050 §5). A CSV *Kauf* or *Verkauf*
    with a blank `Gegenkonto`: "buy without a counter account — …" / "Kauf
    ohne Gegenkonto — …" (and "sell …" / "Verkauf …"). A JSON `CASH_TRANSFER`
    without `otherAccount`, or `SECURITY_TRANSFER` without `otherPortfolio`,
    takes the first sentence. Each names the file's column, which is what the
    operator finds in Portfolio Performance, never a ledger field; a
    receiving row gets the same sentence.
  - **A JSON row whose currency the catalog does not list**
    (`Catalog.Currencies.supported?/1`): "currency “EURO” is not supported —
    row not imported" / "Währung „EURO“ wird nicht unterstützt — Zeile nicht
    übernommen" for the booking's currency, and "security currency “XEU” is
    not supported — row not imported" / "Wertpapierwährung „XEU“ wird nicht
    unterstützt — Zeile nicht übernommen" on every row that names such a
    security. The value is quoted as the file wrote it, upper-cased; a value
    that is not a string is named as written ("42", "1.50", compact JSON for
    a nested one). It is cut at 40 characters, the cut marked "…", and a
    character the operator cannot see or that would break the line is
    spelled `[U+XXXX]`. An absent or blank currency keeps the import's
    default. A CSV row books in EUR and never meets this reason. The
    handbook names the list the reason refers to: the currencies the
    security dialog offers.
  - **A credit row whose own booking would be 0 or less (ADR-0053 A5,
    #1118)** *(2026-10-09; the α closing act, UAT persona and design critic;
    board `mockups/ux-design-2026-10-07/01-import-preview` ③)*: a credit
    whose cash, less the tax refund split off it, is 0 or less, which the
    apply would otherwise skip silently. The sentence is the board's: the
    kind and its cash cell with the figures, then what would remain, then
    "— row not imported", then the remedy as a sentence of its own. A sale
    reads "sell"/"Verkauf"; every other credit kind (a dividend, interest, a
    deposit, a tax refund, a received transfer) reads "booking"/"Buchung",
    so none is called a sale (the board's open point, "one sentence per
    kind or the sale only", answered as "transfer" serves both transfer
    kinds above; it flips by comment to a sentence per kind). The cash cell is named as the file names it
    (a CSV row's Gesamtpreis, a converter row's Betrag) and a JSON row's
    `amount` as the board names it, "Gesamtpreis". A CSV row's figures are
    quoted in the file's notation, its cash cell as written; a JSON row's
    are written to the cent in the reader's notation ("20.10" / "20,10"),
    the locale the sentence is translated in. "Steuererstattung" is the
    kind's name in the app, never PP's "Steuerrückerstattung".
    - Fresh, with a refund: "sell with Gesamtpreis 20,10 and a tax refund
      of 25,00: -4,90 would remain for the sale — row not imported. Book
      the sale by hand, and the refund as a tax refund of its own." /
      "Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem
      Verkauf blieben -4,90 — Zeile nicht übernommen. Den Verkauf von Hand
      buchen, die Erstattung als eigene Steuererstattung."; for another
      credit: "booking with Betrag 1,00 and a tax refund of 1,00: 0,00 would
      remain for the booking — row not imported. Enter the booking by hand,
      and the refund as a tax refund of its own." / "Buchung mit Betrag
      1,00 und Steuererstattung 1,00: Der Buchung blieben 0,00 — Zeile
      nicht übernommen. Die Buchung von Hand erfassen, die Erstattung als
      eigene Steuererstattung."
    - Fresh, without a refund: "sell with Gesamtpreis -4,90: nothing would
      remain for the sale — row not imported. Book the sale by hand." /
      "Verkauf mit Gesamtpreis -4,90: Dem Verkauf bliebe nichts — Zeile
      nicht übernommen. Den Verkauf von Hand buchen."; for another credit:
      "booking with Gesamtpreis 0,00: nothing would remain for the booking —
      row not imported. Enter the booking by hand." / "Buchung mit
      Gesamtpreis 0,00: Der Buchung bliebe nichts — Zeile nicht übernommen.
      Die Buchung von Hand erfassen."
    - Already imported (the stored history holds the row's content hash, a
      live booking or one a merge retired; how such a booking is corrected
      is #1193), with a refund: "sell with Gesamtpreis 20,10 and a tax
      refund of 25,00: -4,90 would remain for the sale — already imported,
      and it cannot be corrected here. Do not book the sale again; see “A
      negative tax inside a row” in the product documentation." /
      "Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem
      Verkauf blieben -4,90 — bereits importiert und hier nicht zu
      korrigieren. Den Verkauf nicht noch einmal buchen; siehe „Eine
      negative Steuer in einer Zeile“ in der Produktdokumentation."; for
      another credit: "booking with Betrag 1,00 and a tax refund of 1,00:
      0,00 would remain for the booking — already imported, and it cannot
      be corrected here. Do not enter the booking again; see “A negative
      tax inside a row” in the product documentation." / "Buchung mit
      Betrag 1,00 und Steuererstattung 1,00: Der Buchung blieben 0,00 —
      bereits importiert und hier nicht zu korrigieren. Die Buchung nicht
      noch einmal erfassen; siehe „Eine negative Steuer in einer Zeile“ in
      der Produktdokumentation."
    - Already imported, without a refund: "sell with Gesamtpreis -4,90:
      nothing would remain for the sale — already imported, and it cannot
      be corrected here. Do not book the sale again; see “A negative tax
      inside a row” in the product documentation." / "Verkauf mit
      Gesamtpreis -4,90: Dem Verkauf bliebe nichts — bereits importiert und
      hier nicht zu korrigieren. Den Verkauf nicht noch einmal buchen;
      siehe „Eine negative Steuer in einer Zeile“ in der
      Produktdokumentation."; for another credit: "booking with Gesamtpreis
      0,00: nothing would remain for the booking — already imported, and it
      cannot be corrected here. Do not enter the booking again; see “A
      negative tax inside a row” in the product documentation." / "Buchung
      mit Gesamtpreis 0,00: Der Buchung bliebe nichts — bereits importiert
      und hier nicht zu korrigieren. Die Buchung nicht noch einmal erfassen;
      siehe „Eine negative Steuer in einer Zeile“ in der
      Produktdokumentation."
- **The parser warnings are ONE `attention` data note** (UX-DR17), no longer
  the accent banner UX-DR17 retired. It keeps `#parser-warnings-box`, sits
  where the box sat (after the counts by kind, before the mapping form), and
  takes its severity word and glyph from `AppShell.data_note`. Its body is
  the head line — the `<h3>` "Parser warnings" with the copy button
  `#copy-parser-warnings` at its end — and the rows as a `<pre>` that keeps
  its own scroller (12rem, UX-DR15), in the note's colour, the
  `.data-note__body .mono` precedent. The note is a region labelled by its
  heading and carries no live-region role (Components → data-note,
  announcement); its `<pre>` takes `tabindex="0"` and the shared focus ring,
  so a keyboard reaches the scroller. The "Warnings" stat card is unchanged.
  **Under 560 px the note wraps** *(2026-10-08; issue 1140, Sprint 20 PR α
  A5; board `mockups/ux-design-2026-10-07/01-import-preview` ④, rule ①)*:
  the glyph and the word form a heading row, and the body — the head line
  with its copy button, then the rows — takes the note's full width (at
  390 px the row list grows from about 243 to 332 px, and three warnings fit
  the 12rem scroller). Above 560 px nothing changes. **A data note that
  carries a list or a remedy wraps the same way on a phone, through ONE
  selector list** in `app.css`'s 560 px block, never a copy per note:
  `[data-role="parser-warnings"]`, `#import-correction .data-note`,
  `[data-role="mapping-unseen-name"]` and `[data-role="mapping-ambiguous"]`
  get `flex-wrap: wrap`, and their `.data-note__body` gets
  `flex-basis: 100%`. A further note of that kind joins the list.
- **The German preview heading reads "Vorschau".** "Übersicht" is the
  Overview's name.
- **An insert rejection names the field's label, never its key**, with the
  message in the page's language through the `errors` domain: "Creating the
  security failed: ISIN has already been taken", "Row 3: Exchange rate is
  required for a cross-currency settlement". The labels are one map,
  `PortfolixirWeb.FieldLabel`, shared with the booking drawer, covering every
  field of the schemas the apply writes (the counter fields read "Counter
  account" / "Gegenkonto" and "Counter depot" / "Gegendepot"); an unknown key
  falls back to the key. Both pages state a refused changeset one way,
  `FieldLabel.changeset_message/1`: "<label> <message>" per field, the
  messages of one field joined by ", ", the fields by "; ". The ledger's
  refusals an import can reach carry German in the `errors` domain, and one
  that names another field ("must differ from …") names it by its label.
- **Drift recorded, not repaired here (issue 1130):**
  `#import-unmatched-config` (the leftover-configuration list) still wears
  `.import-warning-box`, the same retired accent banner. The class stays for
  it alone; its sub-rules for the head line and the `<pre>` went with the
  parser warnings.

## Amendment 2026-10-06 — The logo dialog for a logo whose file is gone *(Sprint 19 PR β, B2, issue 933; board `mockups/ux-design-2026-10-04/07b-logo-dialog-missing-file`, before / after)*

A stored logo whose file the start-up check found gone is marked
(`logo_file_missing`), never cleared; its row draws the monogram or the flag
`security_logo/1` draws for a security with no logo (board 07.6). The
Manage-logo dialog (`securities/logo_override_dialog.ex`) the row menu opens
had no words for that state. Built as drawn; no `app.css` rule changes.

- **A status sentence of its own**, first in the dialog's `cond`, whatever
  the lock: "The stored logo file is missing. Set it again from an image URL,
  or remove the logo." (de "Die gespeicherte Logodatei fehlt. Über eine
  Bild-URL erneut setzen oder das Logo entfernen."). A statement of fact plus
  the remedy, naming the dialog's own controls (Voice and Tone). It is
  neither "A manual logo is set …", which the stored path alone used to
  answer, nor "This security is set to have no logo.", the operator's
  deliberate choice, nor "No logo found yet.", which reads as never having
  had one.
- **"Remove logo" stays enabled** for a marked row, locked or not: removing
  turns a lost logo into the deliberate "no logo" choice without an upload
  first, behind the confirmation it always had. It is disabled only on that
  choice itself (no path, locked), where nothing is left to remove.
- **The image-URL field is never prefilled.** A stored logo's path is local
  (`/security_logos/<id>.<ext>`), never the URL the image came from, and the
  field's `type="url"` refuses it on save; the field starts empty in every
  state, its placeholder showing the shape it takes.

## Amendment 2026-10-07 — Copy and dialog states *(Sprint 19 pick J8 = A, PR γ U6; issues 1090, 1074, 1066, 1072, 944, 945)*

Board `mockups/ux-design-2026-10-04/08-copy-dialogs` (the design pass's
Part 8): before/after for the copy, one pick, J8, taken as recommended (A).
Each part names what was built. The history subtitle (board 03) and "1
units" (board 04) are other stories'.

### The words a newcomer misread *(issue 1090, and issue 1074's drawer half)*

- **The Positions basis line is about the rows** (①): "Eine Zeile je Depot
  und Wertpapier, bewertet zum zuletzt gespeicherten Kurs." (English "One
  row per depot and security, valued at the latest stored price.";
  `data-role="positions-basis"`). It used to explain the API's holdings
  projection, which a newcomer read as a sentence about the table. That
  the table is the API's own projection stays true and is said where it
  helps: the API guide and the column picker's grouping.
- **The theme menu is "Erscheinungsbild"** in German (②): its summary's
  `title`, its hidden label and its group's `aria-label`; English keeps
  "Theme". The msgid stays "Theme".
- **The wealth card says the period in words** (③): "+4,2 % seit
  Jahresbeginn" (English "year to date"), under a msgid of its own. The card
  is one link and cannot hold an ⓘ, so the label has to carry the meaning.
  "YTD" stays the period token of the range controls (Period control above).
  The card's pending state with a prior value (`data-role="overview-stale"`)
  follows it: its label and its "Letzter Stand: … % seit Jahresbeginn — …"
  sentence.
- **"Liquiditätsrolle" and "Buckets" are defined where they head their
  columns** (④). Each head on Accounts & depots carries an inline ⓘ
  (`.metric-tooltip--inline`, a `<details>` whose summary is labelled
  "Zur Liquiditätsrolle" / "Zu den Buckets") with one sentence each:
  "Liquiditätsrolle — wie ein Verrechnungskonto zählt: Verfügbares Cash
  geht in die Cashquote ein, Reserve und Kreditlinie nicht." and "Buckets —
  Tags für Depots und Verrechnungskonten. Eine Ansicht wählt Buckets aus
  und grenzt jede Kennzahl auf deren Konten ein; ein Konto kann mehreren
  angehören." The head keeps its ⓘ beside the word (`th.accounts-term-head`,
  `white-space: nowrap`); the panel opens upward over the page head, and
  the Buckets panel, right of centre, grows leftward
  (`.metric-tooltip--end`) so it stays inside a 768 px page. **Under 640 px**
  the head is hidden, so the same ⓘ rides in the rows
  (`.accounts-term-info--phone`, hidden above 640 px): the role's beside
  each cash account's role control, the Buckets' after each chip group's
  scope line, which became a `<div>` to hold it. There the panel is
  anchored to its cell and takes the card's width: an ⓘ two thirds across
  a 390 px card had no room for an 18rem panel on either side. The head's
  own two ⓘ take `display: none` there: the head is only visually hidden,
  and they stayed in the tab order as two stops nobody could see (the
  review of U5); the rows' copies serve the phone.
- **The contribution phone row names the side of the flow** (⑤): "Abfluss
  aus der Position 1.420,00" / "Zufluss in die Position 2.000,00" (English
  "outflow from the position …" / "inflow into the position …"). The flow
  is the position's own, the formula's "Zu-/Abflüsse"; said bare,
  "Abfluss" beside a gain read as money leaving the portfolio. Board 02's
  phone rows take the same words.
- **The delete dialog's journal sentence** (⑥): "Das Audit-Journal hält
  die Löschung mit allen Werten fest; wiederherstellen lässt sich die
  Buchung nicht.", and the split's four sentences take the same verb ("…
  hält die Löschung des Splits / beider Zeilen / seiner Zeile / aller n
  Zeilen fest"); amended in place above (Deleting a booking → The dialog;
  A split, deleted whole).
- **The buy/sell drawer's sub line** (⑦, issue 1074): "Korrigiert die
  Buchung an Ort und Stelle; die abgeleiteten Bestände folgen, und das
  Journal hält die Änderung fest." — the H2b rule ("the journal records the
  change", never "journalisiert", R10d), which the notes-only drawer has
  followed since Sprint 18. **Found while drawing, fixed with it:** the
  rule rename note ("… das Journal hält die Änderung fest, und der
  bisherige Name bleibt dort lesbar.") and the two merge confirmations
  ("… das Journal hält jede geänderte Buchung / Zeile fest.") say it the
  same way. No German string says "journalisiert" any more, and no English
  one says "journaled": the security delete confirmation, the last that
  did, says "each recorded in the journal" (de "jeweils im Journal
  festgehalten"; amended in place under Deleting a security). The
  microcopy-voice invariant reads both.
- **Found while drawing, fixed here:** the German strings that addressed
  the reader as "du" in the middle of a sentence ("— wähle einen",
  "Aktualisiere die Seite und versuche es erneut", "korrigiere die Buchung
  in der Quelle und importiere erneut", "gib den Text ohne sie neu ein",
  and the rest) take the house infinitive ("— einen wählen", "Die Seite neu
  laden und erneut versuchen", "den Text ohne sie neu eingeben"); the
  microcopy-voice invariant now reads the whole sentence, not its first
  word, and both catalogs. The row menu's German "Logo verwalten…" keeps
  the ellipsis of "Manage logo…": the item opens a dialog.

### The split wizard under a conflicting ratio *(J8 = A, issue 1066)*

- **When.** "Record split" with a different ratio already booked for the
  security on the same day: the warning `conflicting_split_ratio` stands,
  and booking is refused while it does (A8 above).
- **The two "after" cells are the not-computable dash.** "Stückzahl danach
  (zum Stichtag)" and "Resultierende Position (heute)" read "—" in the muted
  voice
  (`#split-wizard-preview td.split-na`, {colors.text-muted}, still `.num`),
  the value slot's dash with its reason (UX-DR7): they would print the
  refused ratio alone beside the refused ratio stacked on the booked one —
  two worlds the refusal never lets happen (a booked 1:2 and a previewed
  4:1 read 120 beside 60, where what stands is 15). "Stückzahl vorher"
  keeps its figure; `Splits.preview_split/1` is unchanged, the screen only
  stops printing what it computed.
- **The reason sits outside the table**, because on a phone the table
  scrolls sideways: the warning gains "…, und die Vorschau zeigt keine
  Stückzahl danach." (English "…, and the preview shows no quantity after
  it."), and the fallback sentence, for a booked split the wizard cannot
  name, says the same.
- **A screen reader reads the reason, not the dash** (UX-DR7; the review
  of U6): the dash is `aria-hidden`, and beside it a `.visually-hidden`
  sentence reads "keine Stückzahl danach: an diesem Tag ist ein anderes
  Verhältnis gebucht" (English "no quantity after: a different ratio is
  booked on this day") — the shape of the trades table's p.a. cell. The
  picture is unchanged.
- **Not built (J8 B):** the figures with a "würde abgelehnt" badge. The
  contradicting numbers would have stayed on screen.

### The security dialog's vanished conflict row *(issue 1072, H8.6)*

- **When.** The new-security dialog found a listing that matches an
  existing security ("This security already exists"), and that security
  was deleted or merged away (the API, MCP, another tab) before **Merge
  online fields** or **Update existing** was pressed.
- **Both buttons answer it with H8.6**: the dialog closes, the list
  reloads, and the page's result slot carries the note, focused and
  brought into view — "„Arbolia Inc.“ wurde inzwischen gelöscht; die Liste
  ist neu geladen." or "„Arbolia Inc.“ wurde inzwischen in Arbolia Holdings
  Inc. zusammengeführt; die Liste ist neu geladen.", the survivor a link in
  `<bdi>`. The name is the stale list's; a match created after the list
  loaded is named by the dialog's own record, so the closed dialog is never
  silent.
- **What it replaces.** "Merge online fields" put the bare `:not_found`
  into the dialog's errors, the render read it as a map, and the LiveView
  crashed and remounted silently, losing the search; "Update existing"
  answered with the edit dialog's in-dialog alert. The **edit** dialog's own
  alert for a record deleted meanwhile (E25 S6, F49) stays: there the
  operator is editing that record, not choosing between two.

### Retired subjects in the Risk findings *(issue 944)*

The findings' name map covers every security subject of a rule in force,
read from the stored rows: a rule on a security retired since reads its
name — "Gewicht · <bdi>Nordwind Industrie AG</bdi> · Obergrenze · Warnung"
— where its words fell back to "Wertpapier". The name sits in `<bdi>` like
every stored name in the words; a retired security that shares its name
with an active one is told apart by its ISIN, as everywhere else
(`SecurityNames`), and so is the active twin in its own rules' words: every
label comes from one set of tags over the active securities and the
retired subjects together, never the choices' labels, which count the
active ones alone (the review of U6). The new-rule choices still leave
retired securities out.
A subject deleted since still falls back to the type word. The API and MCP
findings carry `security_id`, which resolves a retired security as any
other; they are unchanged.

### Plan refusals name their row *(issue 945)*

- **The row first, then the rule.** The plan editor's precision and 0–100 %
  refusals name the refused input in the editor's own words: "Soll von
  „Aktien Welt“: höchstens vier Nachkommastellen in Prozent", "Positionsziel
  von „Nordwind Industrie AG“ unter „Aktien Europa“: …", "Cash-Ziel: …";
  the range refusal ends "…: muss zwischen 0 und 100 % liegen". English:
  "Target of “…”: at most four decimal places in percent", "Position target
  of “…” under “…”: …", "Cash target: …", "…: must lie between 0 and 100 %".
  Stored names sit in `<bdi>` (H8.8). The row is read off the refused
  changeset; position rows are written before the category rows that
  follow their sum, so a refused position names itself rather than its
  category's sum. Nothing is written, not even a valid row saved in the
  same batch.
- **The inputs take `step="any"` and carry no `min` or `max`** (found while
  drawing; the range half from the review of U6): with `step="0.1"` the
  browser refused "8,12" before it was ever sent, so two-decimal targets,
  which the store keeps, could not be typed, and with `max="100"` it
  answered "150" with its own "Value must be less than or equal to 100."
  (and `min="0"` a negative the same way) — in both cases the server's
  refusal naming the row was the one the operator never met. The store
  decides: 0–100 %, four decimal places in percent.
- **The answer comes to the operator** *(amended 2026-10-07, the closing act
  of PR γ, the design critic's first finding; made with the floor's second
  pass, which gave the page its result slot)*: the refusal lands in the
  page's result slot (`#classifications-result`, the inline result of issue
  1064) at the top of the page, and with `step="any"` the browser's own
  bubble beside the input was gone, so after "Plan speichern" the refusal
  stood some 500 px above the window (−499 px at 1200 × 800, −556 px at
  390), the focus stayed on the button and no input said it was refused.
  The slot is now `focusable`, and ~~every plan write that answers — "Plan
  anlegen", "Plan speichern", "Plan löschen", a refusal or a success, the
  refusal of a write under a view deleted meanwhile included —~~ a plan
  write's refusal ("Plan anlegen", "Plan speichern", "Plan löschen", a write
  under a view deleted meanwhile included) asks the page to bring it into
  view and focus it (`focus-into-view`, Securities' issue 920 path): it stops
  below the sticky top bar
  (`scroll-margin-top`) and draws the accent ring under the keyboard. The
  input the refusal names (a category, a position or the cash target)
  carries `aria-invalid="true"` and `aria-describedby` the slot's problem
  region, so it takes the invalid border and a screen reader reads the
  refusal on returning to it; the next answer clears the mark. A form
  submit's reply gives the focus back to the submit button after its
  events, so the page's listener moves it in the next task. *Amended
  2026-10-07 (cascade layer 2 of the closing act):* a success no longer
  moves the page — a valid save threw the operator to the top (scrolled
  505 → 0 px at 390 px, 515 → 0 at 1200 px); "Plan gespeichert" shows in the
  slot's status region, which announces it, and the page and the focus stay
  where they are. Switching the plan version or copying another view's plan
  in clears the refused mark, which had stayed on the other version's valid
  input. Dismissing a result gives the focus back where the operator was
  editing — the input the refusal named, else the plan editor's heading
  (`#soll-editor-heading`), else, on a tree with no editor, the tree's own
  (`#classification-heading`); both headings take `tabindex="-1"`, stop below
  the sticky top bar and draw the house ring. Before, the dismissed note
  took the focus with it to `<body>`; that case on every other page stays
  issue 1166.
- The API and MCP writes are out of scope (issue 945's statement): their
  422 still names the field, not the row.

## Amendment 2026-10-07 — Displayed dates and the chart axes *(Sprint 19 pick J5 = A, PR γ U3; issues 1061, 1087's Wealth half, 1088)*

Board `mockups/ux-design-2026-10-04/05-dates-charts` (the design pass's
Part 5): three before/after repairs and one pick, J5, taken as recommended
(A). UX-DR19 as amended on 2026-10-03 already said it; this amendment
records it as built and rewrites the sentences of this file that still
prescribed ISO for a date the page only shows (found while drawing 2).

### Every displayed date goes through `Format` *(issues 1061, 1087; found while drawing 3 and 4)*

- **The rule.** A date the page shows reads the page's language through
  `Format.date/2`: DD.MM.YYYY in German, ISO in English. **ISO stays where a
  date is entered or exchanged:** `<time datetime>`, input values and form
  parameters (the custom range's pair, the ISIN-change field, the release
  range, the booking drawer's date and its disabled fact), `phx-value-*` and
  `data-*` attributes, the chart hook's JSON, URL parameters (`since=`), the
  API, MCP, a name the app stores ("PP Import 2026-10-07") and files.
- **Two forms join it.** `Format.month/2` is the month of a date known only
  to its month: "10.2026" in German, "2026-10" in English — the Termine
  tab's month events and the per-month rows of Wealth's performance table.
  `Format.utc_instant/2` is a compute instant to the minute: "04.10.2026
  00:09 UTC" / "2026-10-04 00:09 UTC" — the basis line under Wealth's chart
  ("04.10.2025 – 04.10.2026 · berechnet 04.10.2026 00:09 UTC") and the
  superseded-series sentence, which had mixed `Format.date` with ISO.
- **A custom range is named one way wherever the period is** (the U3
  review): the range's chip, the KPI heads, the badge over the chart and
  the contribution table's scope read "<from> – <to>" through one helper.
- **The changed-since note says a day in the page's language** ("Geändert
  seit 30.09.2026 (UTC)" on Transactions and Securities, from a chip or a
  `?since=<day>` link); a full instant an agent's link carries is said as
  given.
- **Where it was ISO before.** The security detail: the head ("Letzter
  112,40 (30.09.2026)"), the Overview's latest price, its lineage clauses
  (the former ISIN's "bis …" and the merge link), the valuation status, the
  Transactions tab, the Quotes table and its phone rows, the manual-quotes
  note, the custom-range chip, every metric cell's window, the Termine tab
  (a day, a window, a month, "Zuletzt geprüft …"), the bond strip (maturity,
  issue, "fällig seit …", "Jahre ab …", the yield's quote day) and its
  two-scales note. The securities list's date column. Both merge previews:
  "angelegt …", the basis sentence, the pair tables and their phone lines,
  the quote collisions, the event twins, the restated set balances and
  every refusal and remedy sentence. The release dialog's chips. Wealth:
  the stale-quote and suspect-dates notes, the basis line, the custom range's
  chip, the per-month table rows, a benchmark's covered window ("ab …") and
  the unit hint's "zum Kurs vom …". The import result lists (a skipped row's
  description, an internal transfer, a booking behind a restated set
  balance), the same-named accounts' "angelegt …" tag, the sell form's lot
  preview, the settlement hint, the income year's payments table and the
  snapshot list and comparison table.
- **A date in running text no longer breaks at a hyphen in German**, which
  has none (found while drawing 4). English keeps ISO: inside a note the
  `<time>` stays whole (`.data-note__body time { white-space: nowrap }`) and
  the settlement hint keeps its non-breaking hyphens.
- **A test keeps it swept.** `test/invariants/displayed_dates_test.exs`
  reads the web layer's source (the API directory left out): a template
  that renders `Date.to_iso8601`, `DateTime.to_iso8601`,
  `NaiveDateTime.to_iso8601`, `Date.to_string` or a `Calendar.strftime` with
  an ISO date format outside a `datetime`, `value`, `href`, `navigate`,
  `patch`, `phx-value-*` or `data-*` attribute fails, and so does a function
  that builds one unless it is on the test's allow-list, each entry with its
  reason; the allow-listed functions are one-line helpers that only build
  a machine's value. A date interpolated raw (`<%= row.date %>`) the scan
  cannot see, so one LiveView test reads the main German pages in their
  event states — a custom range on Wealth, a since chip, every detail tab,
  the accounts merge previews — and finds no `YYYY-MM-DD` in their visible
  text.
- **One known exception:** the chart's hover tooltip still shows the ISO
  date and a raw price; it is the hook's own rendering and is filed.

### The chart axes *(issue 1088; pick J5 A)*

- **The labels read the page's language.** The two dates through
  `Format.date`; the values through `Format.decimal`, grouped, with the
  places of before (none from 1 000, two from 1, four below): "12.500",
  "112,40"; a percent axis as the house's signed percent, the sign and "%"
  glued on: "+10,4%", "-0,8%", and "0,0%" for a tick that reads zero. A
  marker's title names its date the same way.
- **{typography.chart-axis} is 9 CSS px at every chart width** (rule ②).
  The labels sit in the 960-unit viewBox that scales to its frame, so the
  9 units rendered 3.2 px on a 390 px phone and 10.7 px on a 1440 desktop.
  The `ChartCrosshair` hook measures the viewBox units per CSS pixel on the
  svg — the larger of the two ratios, as the `meet` viewBox scales by the
  narrower fit — and writes it to `--chart-upx` on `.chart-frame`, kept
  current by a ResizeObserver and put back after every patch;
  `.security-chart .chart-axis-labels text` multiplies 9 px by it, from
  `--chart-upx: 1` declared on the frame. Without script there is no
  measure and no flag (next point): the label renders as it did before this
  story, 9 viewBox units in the gutter — 3.2 px on a 390 px phone.
  **The cost, stated on the plan:** a 1440 desktop's labels go from 10.7 to
  9 px ("J5 A with a floor" was not asked for).
- **The values sit inside the plot on a narrow chart, or when a value is
  wider than the gutter** (rule ③; settled by the U3 review). The hook
  decides, after it writes the scale: it flags the frame
  `data-axis-inside` when the chart is at most 760 px wide, or when the
  widest value is wider than its gutter — the value's x (50 viewBox units)
  over `--chart-upx`, in CSS pixels — and removes the flag otherwise. A
  fixed width alone was not enough: at 9 px a value of seven digits
  ("1.544.042") or a four-digit percent ("+1.234,5%") is wider than the
  gutter of a 906 px chart and lost its first digits or its sign at the
  svg's edge. The hook measures the chart, so the rule follows the chart's
  width — the detail pane, the fullscreen detail and Wealth differ at one
  window width — not the window's. Under the flag the five values
  (`.chart-axis-y`) are start-anchored inside the plot, sitting 3 px above
  their grid line, the top one (`.is-top`) centred on it, over a halo in
  `--color-bg` (`paint-order: stroke`, a 3 px stroke), because
  the 56-unit gutter is 20 px at 390 and "+10,4%" is about 32. The two
  dates (`.chart-axis-x`) stay under the plot. The label group follows the
  area, the line and the markers in the markup, so the halo paints over
  them; in the gutter the order changes nothing.
  *Amended 2026-10-07 (the closing act's design critic, judgement (b)):*
  the halo was `--color-chart-surface`, as board 05's frame A drew it, and
  this sentence deviates from the board on purpose. A halo should be the
  colour it sits on: `.chart-frame` is painted `--color-bg`, so a
  chart-surface halo drew a rim of its own around every value — white on
  the light frame, a lighter one on the dark — where it should only
  have cut the line and the fill away. The buy/sell markers' halo (issue
  645, `.tx-marker`) had the same mismatch and takes the same token.
  `css_chart_axis_test.exs` holds both halos to the frame's background.
- **The export keeps them** *(added 2026-10-07, the closing act's edge-case
  finding 1)*. The SVG and PNG export bakes the computed styles into the
  file, and its list (`_CHART_EXPORT_PROPS`) had none of rule ③'s
  `paint-order`, `text-anchor`, `dominant-baseline` and `transform`: from a
  chart with the values inside the plot the halo painted over the glyphs
  and the values fell back to end-anchoring in the gutter, off the file's
  edge — at 390 and 768 px none of the five survived. The four are on the
  list now, and while the styles are baked in the frame carries the
  export's own `--chart-upx`, measured as the hook measures it for the
  file's width and height, then gets its own back: exported from 390 px, a
  label was 24.7 viewBox units, 16.5 px in the 640 px file; now it is 9 px.
  The file is
  painted the frame's colour, the ground the halos match; the body's colour
  it named was transparent under the page's gradient. Measured in Chromium
  at 390, 768 and 1200 px, light and dark: all five values in the file,
  inked, inside its edges.
- **The empty chart's sentence follows rule ②** *(added 2026-10-07, the
  closing act's edge-case finding 5)*: "Noch keine Kurshistorie." is
  `calc(13px * var(--chart-upx, 1))`, 13 CSS px at every chart width; it
  was 13 viewBox units, about 5 px tall at 390. The hook writes the scale
  for an empty chart too.
- "Daten als Tabelle" stays the fallback that lets 9 px stand
  (Accessibility Floor → Charts).

### Found while drawing

1. **Filed, not here:** the phone chart rule (16:9 under 720 px) is
   overridden by the later global `.chart-frame` (3:1), so phone charts are
   about 113 px tall; fixing the order needs its own board.
2. **Fixed:** of the eight sentences of this file that prescribed ISO for
   display, seven are rewritten in place, each with this date — the
   native-control token, Native controls, the Do's and Don'ts row, the
   quote phone row (twice), the data note's `<time>` rule and the bond
   strip's maturity; the eighth, the Trades tab's "Kept as built", U2
   struck with issue 1060. Two sentences the Part did not list are amended
   too: the settlement hint's ISO date in running text, and the custom
   range's `date-fields` token.
3. **Fixed** by the sweep above: the ISO displays outside both issues'
   lists.
4. **Fixed** by the same sweep: a German date has no hyphen to break at.

## Amendment 2026-10-07 — The touch, focus and colour floor, second pass *(Sprint 19 picks J7 = A and J7.2 = A, PR γ U5; issues 1062, 1064, 1069, 1071, 1085, 1067)*

Board `mockups/ux-design-2026-10-04/07-floor` (the design pass's Part 7):
before/after with two picks, both taken as recommended (A). Built under the
real `@media (pointer: coarse)`, which the board's `.as-coarse` frames could
only simulate, and measured in Chromium with touch emulation at 390, 768 and
1200 px. `test/invariants/css_floor_second_pass_test.exs` pins the rules;
`test/portfolixir_web/live/floor_second_pass_live_test.exs` the markup.
Issue 933, on the same board, shipped with PR β (Amendment 2026-10-06 — The
logo dialog for a logo whose file is gone; the last part below).

### Row menus and range buttons *(issue 1062, rules ① and ②)*

- **A row-menu item is a 44 px target under a coarse pointer.** Above
  720 px the menu stays a popover, and a tablet met the base button's 34 px
  items; `.row-context-menu__item` takes `min-height: 44px` there. Under
  720 px the sheet's items are 50 px already; with a mouse nothing changes.
  The class serves every row menu, so all of them take it. Measured on the
  securities row menu: 34.2 → 44 px per item, the menu 386 → 494 px tall.
- **The menu stays within the viewport** (the review of U5): on a phone in
  landscape the 494 px menu ran off the screen. It is at most the viewport
  less 16 px tall (`max-height: calc(100dvh - 16px)`, with a `100vh`
  fallback) and scrolls inside (`overflow-y: auto`; its 4 px padding still
  holds the items' focus ring, and the items keep their 44 px,
  `flex-shrink: 0`). The positioning hook opens it below its kebab when it
  fits there, above when it fits there, and otherwise on the roomier side
  with its height capped to that room, so it never covers the kebab that
  opened it (before, it clamped to the viewport's top over the kebab).
  Measured under touch: at 915 × 412 and 844 × 390 the menu stands above
  its kebab from 8 px and scrolls to "Löschen"; at 1024 × 768 it opens
  below and scrolls, or above, whole, for a kebab low on the screen.
- **A range button is 44 × 44 under a coarse pointer** (40 × 32 before),
  and gives up its inline padding, so the 44 px minimum is every button's
  width, "YTD" and "Max" included: the group is 8 × 44 + 2 = 354 px. It is
  one row from a **376 px** viewport up (the toolbar is the viewport less
  22 px); at 360, 340 and 320 px (toolbars of 338, 318 and 298 px) eight
  44 px buttons do not fit, so the group wraps there, seven and one, and
  the floor stays. The chart toggles in the same toolbar take 44 px too
  (found while drawing): 32 → 44 px at 390 px; at 768 and 1200 px their
  two-line labels already made them 43.6 px. Their words sit in the middle
  of the box (`align-items: center`; measured 0.4 px off centre).
- **Why real sizes, not H6's padding and negative margin** (Amendment
  2026-10-03 — Touch targets and focus): the menu items stack, so boxes
  grown into their neighbours would overlap and make every boundary
  ambiguous; `.range-buttons` clips with `overflow: hidden`, so a hit area
  grown past the group would be clipped from hit testing too.

### The focus ring of the button family, the icon button and the chart toolbar *(issue 1062, rule ③; found while drawing)*

`:is(.button, .button-primary, .button-ghost, .button-danger,
.button-secondary):focus-visible` draws `outline: 2px solid
{colors.accent}; outline-offset: 2px`, the ring every other control draws
(Colors → Focus indicator). Measured on the delete dialog's "Abbrechen":
Chromium's `auto 1px` ring in the system colour before, the 2 px accent at
2 px after. The ring sits outside the fill, so the primary's accent fill
and the ring never merge; hover stays the fill change. **Found while
drawing, the same ring:** `.icon-button:focus-visible` changed colours only,
so the browser's ring still drew; it now draws the accent ring too.
`.chart-toggle` draws it at the 2 px offset, and `.range-button` draws it
**inset** (`outline-offset: -2px`), because its group clips an outset ring;
the KPI strip's cells take the same -2 px. *Amended 2026-10-07 (the PR γ
closing act, design critic 6 and 7):* the bucket chip's **+**
(`.bucket-chip-add`) draws the ring at 2 px, as the "+N" chip beside it
does, and its **×** (`.bucket-chip__remove`) draws it inset at -2 px,
because the × fills the pill's end and an outset ring would run over the
pill's edge; both drew Chromium's `auto 1px` black ring before. The
history's heading (`#transaction-history-heading`), which takes the focus
when a closing dialog's own write took its row (issue 912's fallback),
draws the ring at 2 px with {rounded.sm} corners, as the securities page's
result slot does when it takes the focus the same way; it too drew the
browser's ring. *Amended 2026-10-07 (the closing
act of PR γ, the design critic's third finding; issue 1164):* the view
switcher's quiet controls — "Ansichten", the active view's ⓘ and Wealth's
"Als Standard festlegen" — drew Chromium's `auto 1px` ring beside the chips'
accent one; they are named in the button family's rule and draw the 2 px
accent at 2 px (see "The view switcher's quiet controls" below).

### A page's result is an inline result *(issue 1064, pick J7 = A)*

- **The slots.** The transaction history (`#transactions-result`), Buckets
  (`#buckets-result`), Classifications (`#classifications-result`, on a
  tree and on the "new classification" page) and Risk's rule section
  (`#policy-rules-result`) answer an action through `AppShell.inline_result`
  instead of `.alert-success` / `.alert-error`: a success reads as a note
  ("Hinweis", the asterisk), a refusal as a problem ("Problem", the
  octagon), each with its dismiss and the two live regions that exist
  before any action. Front matter: `inline-result.page-slot`.
- **Accounts & depots has one slot.** It rendered the two-class alert a few
  lines from its own inline result; the alert's answers (a changed role, a
  created account, their refusals) now land in `#accounts-result`, beside
  the merge's and the delete's.
- **Why.** Under coral in the dark theme `.alert-success` and `.alert-error`
  were pixel-identical (the danger and coral inks are one value on one
  tint) and neither carried a word: the delete's "Transaktion gelöscht: …"
  and the raced "Diese Transaktion existiert nicht mehr." read the same
  (UX-DR7). The words are the data note's own (Voice and Tone: one word
  per severity), not "Erledigt" / "Fehler", which would be a fourth and a
  fifth.
- **Kept.** A refusal that names policy rules keeps its links (issue 871):
  the problem's body is `PolicyRuleReferences.message`, and
  `.data-note__body a` underlines them in the note's colour. The history's
  closing dialogs bring the shown note into view
  (`data-focus-result="#transactions-result .data-note"`), below the sticky
  top bar as the alert was.
- **The alert's footprint** (`.inline-result--page`, a class the component
  now takes): the band's side gutter (`margin-inline: clamp(16px, 2.4vw,
  28px)`) where the slot is a direct child of `.workspace-page`, 12 px
  above a result, and **nothing at rest**, so every page looks as it did
  until an action answers. The component's regions always hold whitespace,
  so its `:not(:empty)` margin never lifted and an empty slot was 8 px
  tall; the page slot asks `:has(> *)` instead. In a section's grid (Risk)
  the empty slot leaves the flow (`position: absolute`, still a live region
  in the accessibility tree), so the grid adds no gap for it; measured at
  rest, the gap above the next block is unchanged on all five pages
  (Risk's 28 px would have become 52). The other inline results (Accounts'
  own, Snapshots, Securities) keep their footprint.
- **Not changed.** In-dialog refusals and the Imports page keep their
  alerts (they are not page result slots), and "Classification not found"
  is a page's state, not an action's answer.
- **Not built (J7 B):** a glyph inside the old alert with the word only
  visually hidden. In the dark the outcome would have ridden on a 14 px
  shape alone, and it kept a component the inventory retires.

### Flush tables and the tooltip's alignment *(issues 1069 and 1071, rules ⑤ and ⑥)*

- **`.drift-table, .cash-table` carry no top margin.** All five call sites
  (the allocation tree, the flat positions, the Holdings cash table and
  the two snapshot tables) sit in a bordered `.data-table-wrapper`, so the
  1rem was a 17 px band inside the border. The head row now sits on the
  wrapper's top border (measured 17 → 1 px, the border, at every width).
- **A tooltip is a paragraph wherever it sits:** `.metric-tooltip p` sets
  `text-align: start` on the class, H4 (c′)'s reasoning carried one
  property further. In a `th.num`, the Drift ⓘ, it inherited the right
  alignment and read ragged on the left (measured `right` → `start`).

### Accounts & depots *(issue 1085, pick J7.2 = A, rules ⑦, ⑧ and ⑨)*

- **The balance's date says what it is:** "letzte Buchung 31.03.2026"
  (English "last booking …"), the KPI strip's own word for the same kind
  of date, under a msgid of its own; "as of %{date}" ("Stand …") stays at
  its three real as-of call sites. The date is the newest booking that
  moved the balance (`Ledger.cash_activity_dates/1`); a set balance is a
  booking too. "Stand 31.03.2026" read as a six-month-old balance when it
  was today's. **Not built (J7.2 B):** "unverändert seit …", which invites
  the same worry in a new word. **One line from 1200 px**, as the board
  draws it (`white-space: nowrap`; the review of U5): the longer words
  wrapped at 1200 px and made every cash row 15 px taller. German on the
  demo seed fits unwrapped from 1140 px without the table scrolling, and
  1200 leaves room for longer names. Narrower, the accounts table's own
  width decides (issue 1145) and the line wraps, as "Stand …" did at 768
  and 1024 px.
- **The role label's breakpoint** (⑦): the select's label renders as
  `.liquidity-role-field__label` (11 px, 600, {colors.text-muted}) and is
  visually hidden only above 640 px (`@media (width > 640px)`, the exact
  complement of the card layout's `max-width: 640px`; `min-width: 641px`
  left fractional widths between them with neither), where the column head
  states it. At 640 px and below the head is hidden too, so the card now
  reads "Liquiditätsrolle ⓘ
  [Verfügbares Cash]": the role's ⓘ (issue 1090) stands beside its word
  instead of opening the row alone (measured at 390 px: the label 94 × 15,
  the ⓘ moved from x 30 to x 130). Under a coarse pointer the field keeps
  {spacing.3} between the label, the ⓘ and the select: the ⓘ's touch ring
  reaches 8 px past its circle, and with the 6 px gap it covered the
  select's left edge, where a tap opened the definition (measured after:
  the ring ends 4 px before the select). Front matter: `bucket-cell.role`.
  The Buckets ⓘ keeps its place after the scope line, as board 08 draws it.
- **The chips' 44 px** (⑧): under a coarse pointer the chip's × and + are
  44 × 44 (they were 24 × 24 and 32 × 34, the two sub-floor values UX-DR6's
  amendment 2 rejects), and a chip holding a × gives up its block and right
  padding, so the × fills its end and the chip is 46 px tall; the ×'s
  corners are the pill's end (`border-radius: 0 999px 999px 0`), and it
  carries no shadow at any width (the base button's shadow and 8 px corners
  drew a box inside the pill, most visibly in the dark). Not H6's
  negative margin: the chips wrap onto lines 5 px apart. **Found while
  drawing, fixed with it:** the + is the 22 × 22 it declares on the desktop
  (`min-height: 0`; the base button's floor made it 22 × 34, the H6.2
  class), and under a coarse pointer the card's role select (24 px) and
  "Saldo setzen" (34 px) take 44 px. Front matter: `bucket-cell.target-size`.
- **The muted arrow** (⑨): `.merge-record__arrow` takes {colors.text-muted},
  the source's own colour ("muted source, muted arrow, accent target"),
  because it carries the direction (the hidden "in" serves a screen reader
  only) and {colors.text-subtle} is barred from content (2.64:1 light,
  3.03:1 dark before; 5.89:1 and 5.91:1 after). The merge preview's
  `.merge-route__arrow` already takes text-muted. Amended in place under
  Accounts & depots: the merge records.

### The merge record's ISIN line *(issue 1067)*

The line keys on the ISINs the record holds, not on the choice it was
given: with an ISIN on **both** sides it reads the choice the merge required
("<ISIN> bleibt; <ISIN> ist jetzt frühere ISIN", or "… übernommen; …"); on
the **source only** "<ISIN> von der Quelle übernommen"; on the **target
only** or on **neither**, nothing changed and there is no line: the record
lists only lines with something to say. An API or MCP merge records a
choice as given even when none was required, so two ISIN-less securities
printed "bleibt; ist jetzt frühere ISIN" with both slots empty, and a
one-sided pair one slot empty. The payload is unchanged; the agent reads
the choice verbatim.

### The coarse ⓘ *(board `mockups/ux-design-2026-10-04/04-trades`, found while drawing 3)*

Under a coarse pointer every ⓘ summary, the 28 px circle and the labelled
pill alike, carries a transparent ring: `::before` with `inset: -9px`,
placed from the 26 px padding box inside its 1 px border, so its target is
44 × 44 while its picture is unchanged (28 × 28 before and after; the target
measured 28 → 44 on the stat cards, the Drift head, the Views ⓘ and both
phone ⓘ of Accounts). The ring is drawn in no colour. A table clips its
cells (`table { overflow: hidden }`), so a drift head holding an ⓘ takes
9 px of block padding under a coarse pointer and the ring fits inside the
table (it measured 44 × 43 without). UX-DR6 asks for an effective target,
and this is the first one built without a visible box: the circle at 44 px
would have doubled every stat card's corner and grown every line the ⓘ
stands in. EXPERIENCE.md's UX-DR6 inventory gains the class, which its
2026-08-05 count read as covered. *Amended 2026-10-07 (the closing act of
PR γ, the design critic's third finding; issue 1164):* "every ⓘ summary"
had missed the view switcher's, a bare glyph outside `.metric-tooltip`
(14 × 20 px under touch, 13 × 18 at 1024 px). It is named in the ring's
rule and takes the 26 px box the ring is placed from, so it measures
44 × 44 as well (next part).

### The view switcher's quiet controls *(added 2026-10-07; issue 1164; the closing act of PR γ, the design critic's third finding)*

U7 put `PortfolixirWeb.ViewSwitcher` on the classification screen, where its
chips met the floor (`.view-chip`, 44 px under a coarse pointer since issue
446's block) and its quiet controls did not. The component's anatomy and
markup are unchanged; this is CSS conformance under board 07's rules.

- **"Ansichten"** (`.view-switcher__manage`) is a real 44 px box under a
  coarse pointer: `display: inline-flex`, `min-height: 44px`, its icon and
  word 4 px apart as before (`gap: var(--space-1)`, measured 4.3 → 4.0 px).
  Measured 85 × 19 → 84 × 44 on the classification screen and on Wealth, at
  390 and 1024 px. With a mouse it is unchanged.
- **Wealth's "Als Standard festlegen"** (`.view-switcher .button-mini`)
  takes `min-height: 44px` under a coarse pointer: 34 → 44 px.
- **The active view's ⓘ** (`.view-switcher__help summary`) keeps its glyph in
  a 26 × 26 box (`inline-flex`, centred, `position: relative`) and carries
  the coarse ⓘ ring, so its target is 44 × 44 (14 × 20 before); a tap 21 px
  from its centre on each side lands on it. The ring reaches 9 px past the
  box, so under a coarse pointer the switcher's items stand 12 px apart
  (`column-gap: var(--space-3)`, 8 px before): at 8 px the ring reached 1 px
  into "Ansichten", at 12 it ends 3 px before it, as the role field's
  12 px keeps its ⓘ's ring off the select.
- **Real sizes in a row of 44 px chips**, not H6's padding: the row is 44 px
  tall already, so on the desktop's one line nothing moves; on a phone the
  line that holds "Ansichten" grows to 44 px (the switcher 72 → 96 px tall
  under "Alles" at 390 px, 99 → 130 with a view active).
- **The focus ring:** all three draw the 2 px accent at a 2 px offset, from
  the button family's rule (above), where Chromium drew `auto 1px`.

### A missing logo file counts as a missing logo *(issue 933, PR β B2)*

Recorded here because Part 7 of the design pass lists it: a security whose
logo file is gone (`logo_file_missing`) renders the monogram or the flag,
counts in the Overview's existing "ohne Logo" finding, and is listed by
`?dq=missing_logo`, the same set; the logo dialog's sentence for it is the
2026-10-06 amendment above.

## Amendment 2026-10-08 — Import preview: bookings already imported with a different amount *(Sprint 19 pick J9 = A, board `mockups/ux-design-2026-10-04/09-import-correction`; Sprint 20 board `mockups/ux-design-2026-10-07/01-import-preview` ⑧; ADR-0053 §6 and A6, Sprint 20 PR α A2)*

A re-dropped Portfolio Performance export whose rows hit stored content
hashes, and whose stored cash differs from what the rows book today, shows
the bookings it corrects in a section of its own with its own confirm. Built
in `PortfolixirWeb.ImportsLive` on `Imports.cash_corrections/2` and
`Imports.correct_cash/3`.

- **Its place.** A `.panel.inner` (`#import-correction`) of its own,
  **outside** the apply form `#pp-import-apply`, after the counts by kind and
  the parser warnings and before the mapping: it needs no mapping, and its
  button is a different act from "Confirm import", which still inserts and
  changes nothing on a hash hit (ADR-0050 §3, K8).
- **Its wording.** Heading "Already imported, with a different amount" /
  "Bereits importiert, mit anderem Betrag": the page's own "already
  imported" plus what differs, never "wrong" (the operator did nothing
  wrong) and never "hash". The finding is ONE `attention` data note
  (UX-DR17, `data-role="import-correction"`) whose body holds, in order, the
  sentence, the list, the total and the remedy (rule 3: the remedy is a
  child of the note). **The sentence names the Portfolio Performance file,
  not a column of one format (board 01 ⑧)**, plural-aware, **and is true
  for both readings the correction meets** *(amended 2026-10-08, board
  `mockups/ux-design-2026-10-07/03-correction-sentence` ①, the α closing
  act's CH3 = EC-F4)*: "%{count} bookings already imported differ from
  this file: they were booked as an earlier version of the import read
  their rows — a CSV row's gross value, or a cash amount that also held
  the tax refund booked beside it. The Portfolio Performance file states
  what the account moved; the difference is the row's fees and taxes, or
  that refund." / "5 bereits importierte Buchungen weichen von dieser
  Datei ab: Gebucht ist, wie eine frühere Version des Imports ihre Zeilen
  las — der Bruttowert einer CSV-Zeile oder ein Geldbetrag, der auch die
  daneben gebuchte Steuererstattung enthielt. Was das Konto bewegt, nennt
  die Portfolio-Performance-Datei; die Differenz sind die Gebühren und
  Steuern der Zeile oder diese Erstattung." (singular "One booking …: it
  was booked as an earlier version of the import read its row …" / "Eine
  bereits importierte Buchung weicht … ihre Zeile las …"). The sentence
  of board 01 ⑧, "what was booked is the gross value … The difference is
  the row's fees and taxes.", is retired: since A6 the section also lists
  a JSON or converter row whose refund was counted twice (A1), where
  nothing booked is a gross value and the difference is that refund.
  Board 09's "(Spalte „Betrag“) … als „Gesamtpreis“" is retired too: a JSON
  v1 file has neither column.
- **Its columns.** Row · Date · Booking · Booked · Corrected · Difference
  (Zeile · Datum · Buchung · Gebucht · Korrigiert · Differenz) in a
  `.data-table` (`#import-correction-table`) *(amended 2026-10-09, board
  `mockups/ux-design-2026-10-07/03-correction-sentence` ④, the α closing
  act's second fix round, UAT-4: board 09's middle column "Per the file" /
  "Laut Datei" shows what the correction writes — for a refund counted
  twice (A1) the file's cash less that refund, +95,00 where the file states
  120,00 — so it is named "Corrected" / "Korrigiert"; decided by the fix
  round's orchestrator, it flips by the owner's comment)*; a split-off tax
  refund (listed when its cash was changed by hand) is named by its row and
  kind, "4 (Tax refund)" / "4 (Steuererstattung)", here, in its phone row and in the
  dialog's subject, as the done page names it *(amended 2026-10-08, the α
  closing act's EC-F7)*; the booking is "kind · security
  · account" in one cell, each stored name in `<bdi>`, as the history's phone
  row reads; the three figures are signed cash effects on the booking's own
  account (a debit negative), each in its sign colour (`is-positive` /
  `is-negative` from the displayed sign; "semantic colour wherever a sign
  exists").
- **What changes with the cash** stands under the booking in the basis voice
  (`.import-correction__legs`, 12 px muted, one line per `<span>`):
  - a cross-currency trade's settlement, "Settlement booked: 125.00 EUR =
    156.25 USD" / "Settlement per the file: 100.00 EUR = 125.00 USD"
    (ADR-0015: the legs change in the same write, so the settlement guard
    holds);
  - a JSON purchase's or sale's price, "Price booked: 12.50 EUR" / "Price
    per the file: 10.00 EUR" (A2, A6). **Added to board 09**, which drew a
    CSV file, where no price changes: a write the dialog performs is said
    before it.
- **Phone rows under 560 px** (UX-DR27): the table hides and
  `#import-correction-phone-rows` shows two-line rows — the security, or the
  account for a row without one, over "Row N · date · kind · account"; the
  difference over "booked → corrected" (no column word, so board 03 ④
  changes nothing here); the legs and the price under the subject. Under 560 px the note's body takes the note's full width, under
  the glyph and the word.
- **The total per account** (`.import-correction__total`, the body's colour,
  tabular figures): "Together **-25.51 EUR**: Girokonto -24.31 EUR,
  Tagesgeld -1.20 EUR." / "Zusammen … ", the total bold in its sign colour.
  Accounts of different currencies have no common total: the line then
  reads "Per account: …" / "Je Konto: …".
- **The remedy** (`.import-correction__foot`): "Correct N bookings…" /
  "N Buchungen korrigieren…" (`.button`, an ellipsis because a dialog
  follows; singular "Correct one booking…" / "Eine Buchung korrigieren…"),
  beside the basis line "a step of its own, apart from “Confirm import”" /
  "ein eigener Schritt, unabhängig von „Import bestätigen“".
- **The confirm dialog** (`#import-correction-dialog`, `.modal
  .import-correction-dialog` on the `ModalDialog` hook) **joins the narrow
  destructive modal's selector lists** beside `.quote-release-dialog` and
  `.booking-delete-dialog` (460 px; the bottom sheet under 720 px, the
  confirm on its own first line, Cancel on the next) and reuses
  `.booking-delete__subject`: title "Correct booked amounts" / "Gebuchte
  Beträge korrigieren"; the subject box "5 bookings · Rows 2, 5, 8, 11, 13 ·
  Girokonto, Tagesgeld" over the total and "Difference" / "Differenz", the
  table's column word *(amended 2026-10-08, board
  `mockups/ux-design-2026-10-07/03-correction-sentence` ②; board 09's
  "Fees and taxes" is false for a refund counted twice)*, both only when
  the accounts share a currency: without a common total the box shows
  neither figure nor caption *(board 03 ③)*; the consequence,
  "Afterwards Girokonto has 24.31 EUR less and Tagesgeld has 1.20 EUR less."
  / "Danach hat Girokonto 24,31 EUR weniger und Tagesgeld 1,20 EUR
  weniger.", one sentence per trade whose settlement or price changes ("Beim
  Kauf von … am … ändert sich die Abrechnung mit: 1.500,00 EUR = 1.633,50
  USD." / "… ändert sich der Kurs mit: …"), and "Balances, valuation, return
  and income are recalculated."; then the journal sentence, "Each change is
  kept in the journal with the previous amount; the import hashes stay as
  they are, so importing the same file again books nothing." / "Jede
  Änderung wird mit dem bisherigen Betrag im Journal festgehalten; die
  Import-Hashes bleiben, wie sie sind, also bucht ein erneuter Import
  derselben Datei nichts." Cancel is focused first.
- **Its confirm is primary, not danger** ("Correct 5 bookings" / "5
  Buchungen korrigieren", `.button-primary`): nothing is lost — every
  replaced value stays in the journal with its before-image and is readable
  in the file. Danger marks a loss the screen cannot take back (delete,
  merge, release).
- **The result line stands where the section stood**: the page's inline
  result slot (`#import-correction-result`, `.inline-result--page`, no
  footprint at rest) shows "Correcting…" while the write runs and then the
  note "5 bookings corrected: Girokonto -24.31 EUR, Tagesgeld -1.20 EUR. The
  journal keeps the previous amounts." / "5 Buchungen korrigiert: … Das
  Journal hält die bisherigen Beträge.", until it is dismissed or the next
  action. The section is read again after the write, so a corrected file
  shows none; the dialog returns the focus to the result slot. A refused
  write is a `problem` result naming the row and the reason, and nothing is
  corrected.
- **Nothing differs: no section and no all-clear** (UX-DR2) — no "the
  amounts agree" badge. A file whose rows are all hash hits says only what
  the 2026-09-26 amendment's nothing-to-import note says.
- **The import confirmed first** leaves the listed bookings as they were
  (K8); the done page says so in `.import-skipped`'s form
  (`data-role="correction-not-applied"`): "5 bookings already imported with
  a different amount from the file are not corrected. Drop the same file
  again to correct them." / "5 bereits importierte Buchungen mit anderem
  Betrag als in der Datei sind nicht korrigiert. Dieselbe Datei erneut
  ablegen, um sie zu korrigieren."
- **Superseded on board 09:** its "a file with no Gesamtpreis (a converter
  file) never shows it" — since A6 a converter file whose negative Steuern
  was counted twice shows the section too. The new row-error reasons of
  Part 9's list are recorded in the 2026-10-06 amendment above.

## Amendment 2026-10-08 — A return on no cost basis, and the percent cells it changes *(Sprint 20 board `mockups/ux-design-2026-10-07/02-money-findings`, before/after; issue 1142, PR β B3; the board's found-while-drawing 4, 9, 10 and 11)*

Two percent cells the board found in the old form are repaired in the cells
issue 1142 changes (plan D-14):

- **Wealth → Holdings → Positions, "P&L %" / "G&V %"** (found while drawing
  4). The optional column printed the projection's raw fraction, every
  digit of it ("0,1871401151631477927063339731" under a "%" header). It now
  prints the house percent: `Format.signed_percent`, one decimal, the sign
  and "%" glued on ("+18,7%", "-5,1%", "0,0%" unsigned), in its sign colour
  decided on the percent as shown (`is-positive` / `is-negative` /
  `is-flat`, issue 1010's rule that every signed cell of a data table
  carries its colour). The table's money columns keep the projection's
  unrounded digits; a percentage is not one of them.
- **The security's Holdings tab, "%"** (found while drawing 11). It kept the
  form #1060 retired on the Trades tab: two decimals and a breaking space
  ("+18,71 %"), so "0,00 %" wrapped onto two lines in its 60 px cell at
  980 px, and its colour was taken from the amount beside it
  (`pnl_class(h.unrealized_pnl_abs)`), so a percent that reads "0,0" printed
  in the gain colour of a gain of 4,00. It is now the Trades tab's "%"
  (`signed_pa/1`: "+18,7%"), coloured by the percent as shown
  (`shown_percent_class/1`), as the Trades tab's "%" columns are since the
  Sprint 19 U2 review. The other figures of the tab are unchanged.

**A return on no cost basis is the reason dash** (issue 1142, plan D-6).
A closed trade whose basis is zero (a buy booked at 0,00 with no fees or
taxes: bonus shares) and a position or open lot whose cost is zero (shares
delivered in at no cost: a spin-off) have no percentage return. "0,0%" read
as a flat trade; a share that cost nothing rose by an undefined percentage,
not by none. The precedent is the category result ("a category with no cost
has no result to state, and a zero would claim it is flat").

- **Where:** the Trades facet's Result cell (its sub-line under the amount)
  and phone row; the security's Trades tab, both "%" columns (open lots and
  closed trades) and its phone row; the security's Holdings tab "%"; and
  Wealth's "P&L %". Each is the existing muted dash with #1089's reason
  anatomy (Sprint 19's pick J4): `aria-hidden` "—", the reason in the
  `title` ("Keine Rendite: keine Kostenbasis" / "No return: no cost
  basis") and in a `.visually-hidden` sentence ("keine Rendite, keine
  Kostenbasis" / "no return, no cost basis"). The figure beside it keeps
  its amount: the facet's Result still reads "+330,00 EUR", the open lot
  "+167,20", the holding "+336,00", in their sign colours. The dash takes
  the dash's colour, never the amount's.
- **The p. a. cell's reason comes first:** a trade on no cost carries the
  p. a. dash with "Keine annualisierte Rendite: keine Kostenbasis" /
  "keine annualisierte Rendite, keine Kostenbasis", before the 365-day rule
  and the solver's reason. With no cost there is nothing to annualize,
  however long the trade was held (the API's `annualized_return_reason`
  `no_cost_basis`).
- **At 390 px the reason is on the row, in words:** the phone rows of the
  facet and of the Trades tab read "— keine Kostenbasis" / "— no cost basis"
  (`span[data-role="return-absent"]`, the dash `aria-hidden`) where
  "0,0% gesamt" (facet) or "0,0%" (tab) stood. No "gesamt": there is no
  total return to qualify. The row's hidden `pa-absent` sentence reads "keine
  Rendite, keine Kostenbasis". Measured on the board: the line is 118 px wide
  on one 15 px line, and the rows keep their heights (59/60 px). The basis
  line is not the place: a zero basis is a fact about one booking that the
  phone row does not show, and a touch screen has no `title`.
- **The Overview card "Abgeschlossene Trades"** (found while drawing 9): a
  trade on no cost reads "— keine Kostenbasis" under its result, as the
  phone rows do, where it read "0,0% gesamt".
- **Not the plain dash:** a position or lot with no price, or with no
  derivable native cost, keeps the plain "—" with no reason. Its percentage
  is missing for want of a price, not of a cost. The cell knows which by the
  amount beside it: a gain or loss with no percentage is one on no cost.
- **One general muted-dash rule** (board rule ②): `.data-table
  td.trade-pa--na { color: var(--color-text-muted) }` (0,2,1) outranks
  `.data-table tbody td { color }` (0,1,2) in every data table. It replaces
  the two scoped copies (`#realized-trades-table td.trade-pa--na`,
  `#detail-closed-trades-table td.trade-pa--na`), as issue 1010 did for the
  sign colours, because the open lots' table has no id and the Holdings
  tab's and Wealth's cells carry the dash too.

## Amendment 2026-10-08 — A category below level 32 is refused *(Sprint 20 PR γ, C3; issue 940; board `mockups/ux-design-2026-10-07/02-money-findings`, before / after)*

- **The refusal.** "Hinzufügen" with a parent on level 32 creates nothing
  and answers in the page's result slot (`#classifications-result`, the
  inline result of issue 1064) as a problem: "Nicht angelegt: Unter
  „Stufe 32“ läge die neue Kategorie auf Ebene 33 — eine Klassifizierung hat
  höchstens 32 Ebenen. Bei „Übergeordnet“ eine Kategorie weiter oben
  wählen." English: "Not added: under “…” the new category would sit on
  level 33 — a classification has at most 32 levels. Under “Parent”, pick a
  category higher up." The parent's stored name sits in `<bdi>` (H8.8);
  "Übergeordnet" / "Parent" is the select's own label. The sentence is its
  own message, not `changeset_error/1`'s field-prefixed one.
- **It comes to the operator** (found while drawing, 5): a refusal of
  "Hinzufügen" is brought into view and focused (`focus-into-view`), as a
  plan write's is, because the form sits 570 px below the slot at 980 px.
  The form keeps what was typed.
- **A move** has no control on this screen. The API refuses it with the
  changeset's message on `parent_id`, naming the level the moved subtree's
  deepest category would take.
- **The parent field's other refusals read German** (found while drawing,
  6; fixed on the branch under the plan's D-14, which the board document
  sanctions: "fix in the story, on the message path it touches"). The page's
  field-prefixed changeset message labelled `parent_id` through
  `Phoenix.Naming.humanize/1`, in English, so the cycle refusal read
  "Parent würde die Kategorie zu ihrer eigenen Oberkategorie machen". The
  field now has its own label: "Übergeordnete Kategorie würde die Kategorie
  zu ihrer eigenen Oberkategorie machen" (English: "Parent category would
  make the category its own ancestor"), and the same label opens "… muss
  zur selben Klassifikation gehören". Only the label changes: the slot, the
  severity and the sentence after the label stay as they were.
