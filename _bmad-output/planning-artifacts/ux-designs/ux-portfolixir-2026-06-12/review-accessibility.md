> **Superseded for the contrast table (2026-08-05).** The "Computed contrast
> table" below has been carried verbatim into
> `../../design-language/DESIGN.md` → Colors, which is now the copy of record
> and is kept in step when a token moves. Three pairings measured later —
> `on-accent` on the three accent fills, `warning` on `warning-soft`, and the
> `warning-soft-dark` composite — exist only there. Read the table there; this
> file stays as the 2026-06-13 session archive, findings included.

# Accessibility Review — UX Spine (DESIGN.md + EXPERIENCE.md)

Reviewed: 2026-06-13 · Benchmark: WCAG 2.2 AA, applied pragmatically for a solo self-hosted tool · Scope: spine documents only, not the codebase. Severity = downstream implementation impact.

## Verdict

The spine is unusually accessibility-literate for a planning artifact — reduced-motion gating, 44px coarse-pointer targets, drag-with-fallback, Esc/focus-return rules, and semantic landmarks are all stated as binding. The two systemic gaps are (1) a contrast hole in the light-mode text ramp and the coral accent/tx-buy tokens, and (2) the absence of any non-color-channel requirement for the app's most important semantics (gain/loss, drift, buy/sell, staleness) in a finance tool whose entire point is signed numbers. Both are cheap to fix at spec level and expensive to retrofit later; several accessibility-floor items are also [ASSUMPTION]-tagged and must be promoted to binding before implementation treats them as optional.

## Findings

- **critical** — `text-subtle` fails contrast in light mode (2.47:1 on `bg`, 2.64:1 on `bg-elevated`; dark `bg-elevated` only 3.03:1). DESIGN.md "Colors" labels it "tertiary/disabled" — "tertiary" is a license to use it for real content (as-of dates, hints, table meta), where it fails both 4.5:1 and even the 3:1 large-text bar. *Fix:* in DESIGN.md, restrict `text-subtle` to disabled states and pure decoration explicitly ("never for conveying content"), and either darken the light value (~#6e7a8e reaches ≈4.5:1) or route all readable tertiary content to `text-muted` (5.50:1, passes).
- **high** — No non-color channel is required for gain/loss, SOLL/IST drift over/underweight, buy/sell chart markers, or the stale-quote warning (WCAG 1.4.1). EXPERIENCE Flow 1 step 4 ("overweights and underweights in {colors.positive}/{colors.danger}"), State Patterns ("timestamp shifts to {colors.warning} tone"), and DESIGN's buy/sell circles ({colors.tx-buy}/{colors.tx-sell}, identical shape) all encode meaning in hue alone. *Fix:* add a binding line to the Accessibility Floor: signed values always render an explicit "+/−" (or ▲/▼), buy/sell markers differ in shape (e.g. ▲ buy / ▼ sell) not just fill, and the stale state carries a text/icon cue ("stale" / clock glyph) alongside the warning tone.
- **high** — `tx-buy` (#10b981) on the light chart surface (#ffffff) is 2.54:1 — below the 3:1 minimum for meaningful graphics (WCAG 1.4.11); the white stroke ring doesn't rescue the fill. *Fix:* darken light-mode buy markers (e.g. reuse `positive` #047857, 5.48:1) or give markers a `border-strong`-level outline plus the shape channel above. (`tx-sell` 3.76:1 passes; both pass in dark mode.)
- **high** — Modal behavior spec has no focus-trap / `aria-modal` / inert-background requirement. EXPERIENCE specifies Esc-close and focus-return-to-trigger (good, concrete) but says nothing about keeping focus inside `.modal` or marking the page inert — without a bundler this must be planned as a deliberate small hook, or it won't happen. *Fix:* add to Component Patterns "Forms behind disclosure": modal opens → focus moves to first field / dialog heading, `role="dialog" aria-modal="true"`, focus trapped (hand-written hook or native `<dialog>` with `showModal()`, which gives trap + Esc for free and fits the no-bundler constraint).
- **high** — Two accessibility-floor guarantees are [ASSUMPTION]-tagged: "data behind any chart is always also reachable as a table" and "`lang` follows the active locale." These are the load-bearing mitigations for the 9px chart axis and for de/en screen-reader pronunciation; as assumptions, implementers may drop them. *Fix:* promote both to binding in EXPERIENCE Accessibility Floor (the chart-table rule is also the only thing that makes `role="img"` + single `aria-label` an acceptable chart strategy).
- **medium** — Coral accent fails as normal-size text in light mode: `accent-coral` 4.38:1 on `bg`, 3.91:1 on its own `-soft` (relevant because `.alert-success` uses accent-soft and active-nav washes carry accent-tinted content). 30px stat values are large text (3:1 bar) and pass; body-size accent text does not. *Fix:* DESIGN rule: accent may color text only at large size (≥ 24px / 19px bold) or non-text indicators; any body-size accent text in light mode needs a darkened text-grade coral (e.g. #be123c ≈ 5.2:1) — violet (5.32) and teal (5.11) already pass.
- **medium** — Reduced-motion gating over-rotates on spinners: EXPERIENCE puts "every animation — … spinners" behind `no-preference`, but the busy spinner IS information (pending state), contradicting "no information exists only in motion." Hiding it leaves reduced-motion users with no feedback during chart-toggle loads. *Fix:* exempt loading indication — under `reduce`, swap the spinner for a non-animated cue (static glyph, "Loading…" text, or opacity change on the control); keep `phx-click-loading` visible either way.
- **medium** — CSS-only sidebar toggle cannot update `aria-expanded`. EXPERIENCE: "Sidebar state … is a pure CSS toggle." A checkbox-hack control can be focusable with a visible ring (claimed shipped) but its expanded/collapsed state and the accessible name can't change without JS. *Fix:* specify either (a) a real `<input type="checkbox">` with a state-neutral name ("Navigation sidebar", checked = expanded — acceptable), or (b) a 5-line hook toggling `aria-expanded` on a `<button>`. Same applies to the off-canvas (<900px) variant, which additionally needs Esc-close and focus handling spelled out — currently unspecified.
- **medium** — `<details>` theme/accent menus: Esc-close and "one open disclosure at a time per region" both require JS coordination that the spine asserts but doesn't assign a mechanism (no bundler; "small hooks" exist). Also unstated: these are disclosure widgets, not ARIA menus — fine, but say so, so nobody adds `role="menu"` without arrow-key support. *Fix:* one sentence in Interaction Primitives: "implemented as native `<details>` disclosure semantics (no `role=menu`); a shared hand-written hook provides Esc-close and mutual exclusivity."
- **medium** — ⓘ metric tooltips (TTWROR etc.) have no keyboard/touch access spec and no WCAG 1.4.13 behavior (dismissible, hoverable, persistent). "Hover-only affordances on touch surfaces" are banned in Interaction Primitives, but the Voice-and-Tone examples only say "tooltip/hover definition." *Fix:* require the ⓘ to be a focusable element (`<button>`/`<summary>`) whose definition appears on focus and tap, dismisses on Esc, and doesn't vanish while hovered.
- **medium** — Form error association is visual-only: ".field-error at the field" with no `aria-describedby`/`aria-invalid`/error-summary-focus requirement. *Fix:* add to State Patterns: each error text is programmatically linked via `aria-describedby`, the field gets `aria-invalid="true"`, and on failed submit focus moves to the first invalid field or the `.alert-error` (which should be `role="alert"` or in an `aria-live` region).
- **medium** — Focus indicator may be too faint: `{components.input.focus}` = "accent border + 3px accent ring at 18% opacity," and the Accessibility Floor reuses "the accent ring" for visible focus generally. An 18%-opacity ring composites to well under 3:1 against adjacent colors (WCAG 2.4.13 / 1.4.11); on inputs the full-accent border carries it, but on nav links/rows/buttons the soft ring alone won't. *Fix:* specify a solid 2px full-accent outline (+ optional soft halo) as the universal focus style; note coral's solid value passes 3:1 as a non-text indicator (4.38–4.70 on light surfaces).
- **medium** — Keyboard path for multi-select + drag in Classifications is incomplete. Drag has a non-drag equivalent (move-to-category select — good), but how rows enter multi-selection without a pointer is unspecified, and HTML5/pointer drag generally won't fire on touch, making the toolbar the de-facto iPad/iPhone path. *Fix:* specify checkbox-based (or Space-toggles) row selection that feeds the same toolbar, and state explicitly that on coarse pointers the select+toolbar flow is the primary mechanism, drag desktop-only.
- **medium** — Tiny load-bearing type: 9px chart-axis mono and 9.5px pills. Axis labels are real data (mitigated only by the chart-table rule — see the [ASSUMPTION] finding); the EN/DE locale switcher renders as 9.5px-uppercase pills, i.e. an always-used interactive control at the smallest type in the system. 10.5px nav-group heads and 12px labels are structural/short and acceptable. *Fix:* bump locale-switcher text to ≥ 11px (or keep pill styling with larger glyphs); keep 9px axes only on condition the table equivalent is binding; confirm both scale under 200% zoom (px values do — no fix needed there, just don't cap zoom).
- **low** — `aria-live` page-title region: politeness level unspecified. *Fix:* state `aria-live="polite"` (assertive would interrupt on every patch) and that only the title text node changes, so navigation announces exactly once.
- **low** — Chart toggles and period pills lack pressed-state semantics. *Fix:* one line: `.chart-toggle` uses `aria-pressed`, period pills use `aria-pressed` or radio-group semantics, so state isn't conveyed by accent color alone (ties into the color-independence finding).
- **low** — Scope switch (Flow 3) leans on the rebuild animation as a change cue; the spine itself notes "the scope label, not the motion, carries the meaning" — correct, but the scope label's placement/prominence is unspecified and under `prefers-reduced-motion` it is the *only* cue. *Fix:* require the scope name in the page subtitle or hero basis line on every portfolio-bearing surface, and announce scope changes via the existing live region.
- **low** — `text-soft` (3.48:1 light) is already flagged as "decorative-tertiary, not semantic" via [ASSUMPTION]. Promote that to a hard rule ("never body copy") so the 3.48 ratio never meets real text; dark-mode value (10.41) is fine.

## Computed contrast table

**Superseded 2026-08-05 — the copy of record is `design-language/DESIGN.md` → Colors.** Kept here unchanged as the session archive; do not edit this copy.

Thresholds: normal text 4.5:1 · large text (≥24px / 18.7px bold) and UI components/graphics 3:1. "Large-only" = passes 3:1 but not 4.5:1.

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
| danger #dc2626 / bg | 4.51 | pass (barely) | losses, destructive |
| danger / bg-elevated | 4.83 | pass | losses in tables |
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
