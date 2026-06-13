---
title: Portfolixir EXPERIENCE.md
status: final
created: 2026-06-12
updated: 2026-06-13
name: Portfolixir
sources:
  - _bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md
  - _bmad-output/planning-artifacts/ux-designs/ux-portfolixir-2026-06-12/.decision-log.md
  - priv/static/app.css
  - lib/portfolixir_web/components/app_shell.ex
  - lib/portfolixir_web/components/security_chart.ex
---

# Portfolixir — Experience Spine

> Paradigm (binding): **classic but decluttered.** Managing data stays a first-class UI task; clutter is fought with progressive disclosure, not by hiding the work. The visualization-only vision was considered and rejected. No agent-oversight UI: MCP writes are the owner's own commands executed faster.

## Foundation

Responsive web, three target surfaces: desktop browser (primary analysis seat), iPad, iPhone. One operator; a second household portfolio is a filtered view the same operator manages — single persona, two portfolio scopes. Single-user instance, self-hosted.

**No UI system.** Server-rendered Phoenix LiveView with hand-written CSS in `priv/static/app.css` — no Tailwind, no JS bundler, no CoreComponents; only two function components exist (`app_shell`, `security_chart`), plus a handful of small hand-written LiveView hooks (chart crosshair, drag-and-drop, menu positioning). `DESIGN.md` is the visual identity reference; every visual value in this spine is a `{path.to.token}` reference into it.

Dark/light/system theme and the three logo-derived accent variants ({colors.accent-violet} / {colors.accent-teal} / {colors.accent-coral}) are shipped, owner-loved, and preserved as the identity anchor.

## Information Architecture

IA scope is **IST only** — the current seven surfaces, no reserved future analytics surfaces (matches roadmap #321: UI deprioritized).

| Surface | Route | Reached from | Purpose |
|---|---|---|---|
| Dashboard | `/` | App open, brand link | Dense analysis home: hero (total value + performance curve) top-left, metric cards beside/below |
| Portfolio | `/portfolio` | Sidebar | Portfolio overview: performance, allocation donut/sunburst, drift table, cash |
| Securities | `/securities`, `/securities/:id` | Sidebar, table rows | Security list + split detail pane with price chart, trades, quotes, classification tabs |
| Portfolios (accounts) | `/portfolios` | Sidebar ("Master data") | Portfolios, depots, cash accounts — structure management |
| Transactions | `/transactions` | Sidebar ("Master data") | Full ledger: record, review, filter transactions |
| Imports | `/imports` | Sidebar ("Tools") | PP export intake: drop zone → preview → idempotent apply |
| Classifications | `/classifications`, `/new`, `/:id` | Sidebar (dynamic group, one entry per tree) | Allocation trees: categories, target weights, drag-and-drop security assignment |

→ Composition references: [mockups/key-dashboard.html](mockups/key-dashboard.html) (analysis-dashboard home: hero, card set, decluttered sidebar) and [mockups/key-classifications.html](mockups/key-classifications.html) (decluttered tree + disclosed New-category form). **The spines win on conflict** — mocks illustrate, they do not specify.

**Navigation model (binding: keep current behavior on all form factors).** Desktop: fixed left sidebar ({spacing.sidebar-width}) with grouped, labeled links; a toggle collapses it to an icon rail ({spacing.sidebar-rail}). Below 900px the same sidebar becomes an off-canvas overlay slid in over a backdrop via the top-bar burger; no bottom tab bar is introduced. The sticky top bar carries page title/subtitle, theme menu, accent menu, and the EN/DE locale switcher on every form factor.

**Progressive-disclosure principle (the core decluttering move).** Reading is the default posture of every surface; creating and editing are one intent away, never zero. Concretely: creation/edit forms move out of the primary sightline into modals, popovers, or collapsed sections opened by an explicit affordance (`+`, "Edit", kebab menu). Summary first, drill-down second, filters and forms third. Analytics density is wanted (power-user home) — decluttering happens through hierarchy and disclosure, not through hiding numbers.

**Classifications is the exemplar.** Today the worst-rated screen: the tree detail stacks an always-open "New category" form (name, parent, color, description), a search field, a multiselect toolbar, and a hint paragraph *above* the actual tree. Target shape: the tree itself is the surface — search stays (it serves reading), the New-category form collapses behind the existing `+` affordance, the multiselect toolbar appears only when a selection exists (already built that way — keep), and edit/recolor/delete live on the node, disclosed per node. The same treatment generalizes to every surface with an `.inline-form` in primary sightline.

The disabled "Soon" nav items (Watchlist, Reports group, Grouped accounts, Savings plans, Currencies, Settings) are **hidden** (owner decision): the decluttered sidebar shows only what works. An entry returns when its surface actually ships.

[ASSUMPTION] Owner desire, tentative ("vielleicht"): the dashboard's metric cards become self-configurable (choose which cards, maybe order). This spine keeps the dashboard layout future-friendly — cards are a flat, reorderable collection, no card depends on a sibling — but specifies **no** configuration mechanics (no edit mode, no drag handles) in this run.

## Voice and Tone

Microcopy is **explanatory** (binding): the UI translates domain terms instead of assuming them. de/en via the existing gettext infrastructure; German is the owner's daily locale, so every string ships in both.

- Domain metrics carry a tooltip/hover definition: TTWROR, IRR, SOLL/IST drift, cash quote. One sentence, plain language, method named. Example: "TTWROR — time-weighted return; ignores when money was added, measures only how investments performed."
- Numbers state their basis where it is cheap: as-of date, currency, gross/net. The agent gets this via self-describing MCP responses (FR-13); the human gets the same honesty inline.

| Do | Don't |
|---|---|
| "TTWROR (time-weighted return) — ⓘ" | Bare acronyms with no help |
| "As of 12 Jun 2026, EUR" | Numbers with unstated basis |
| "Import previewed: 42 transactions would be created." | "Import successful!" before anything happened |
| "Nothing here yet — import a PP export or record a transaction." | "No data." |
| Calm, complete sentences; no exclamation marks | Coaching, gamification, celebration |

## Component Patterns

Behavioral. Visual anatomy lives in `DESIGN.md.Components`.

| Component | Use | Behavioral rules |
|---|---|---|
| App shell | Every surface | Sidebar state (expanded/rail/off-canvas) is a pure CSS toggle; survives navigation. The toggle is a real `<input type="checkbox">` with a state-neutral accessible name ("Navigation sidebar") — or a `<button>` plus a small `aria-expanded` hook; the off-canvas variant closes on `Esc` and backdrop tap, returning focus to the burger. Active link tracks `current_path` per section prefix. Classifications nav group reflects the live list of trees. |
| Hero (total value + curve) | Dashboard top-left | The one fixed element of the home. Total portfolio value as headline number, the curve beside/below it, period pills attached. The curve is **switchable between absolute value (€) and TTWROR performance (%)** via a €/% toggle on the hero (owner decision) — value and performance share the hero slot; the headline number follows the active series' basis statement. One-shot build animation on load and on series switch (see DESIGN.md Motion). [ASSUMPTION] Period pill set mirrors the existing `.period-buttons` component. |
| Metric cards (DESIGN: Stat card) | Dashboard | `.stat` anatomy: uppercase label, big accent number. Click/tap navigates to the owning surface (e.g. drift card → Portfolio). Card set (owner-confirmed): cash quote, TTWROR vs. period, top drift category, transactions recency. |
| Security chart | Securities detail, Portfolio | Server-rendered SVG; LiveView re-renders on range/log/percent toggle — toggles show a busy state while loading and expose state via `aria-pressed`. Crosshair + mono tooltip on pointer; touch: pan-y preserved, tap shows nearest point. Build-in animation plays once per data change, never on crosshair moves. |
| Allocation visuals | Portfolio | Read-only visuals in this run: donut/sunburst segments have no click or hover behavior, legends are static; the drift table follows the Tables row. |
| Tables (DESIGN: Data tables) | Transactions, Securities, drift, holdings | Read-first: rows are targets (click → detail/select), hover wash, kebab menu for row actions (becomes bottom sheet < 720px). Sort/filter/column controls live in popovers off the toolbar, not inline. |
| Forms behind disclosure | All create/edit | Default closed. Opened by explicit affordance (`+`, "Edit", kebab). One disclosure level at a time; `Esc`/cancel closes and returns focus to the trigger. Modals are real dialogs: native `<dialog>`/`showModal()` preferred (focus trap + `Esc` for free, fits the no-bundler constraint), else `role="dialog" aria-modal="true"` with a small focus-trap hook; focus moves to the first field or the dialog heading on open. Destructive actions confirm (`data-confirm`), never more than once. |
| Classification tree (DESIGN: Drag-and-drop rows) | Classifications | `<details>` nodes; drag-and-drop assignment with multi-select; toolbar appears only with an active selection. Row selection works without a pointer: each row carries a checkbox (`Space` toggles) feeding the same toolbar; on coarse pointers select+toolbar is the primary mechanism — drag is a desktop-only accelerator. Search filters the tree live (150ms debounce) and auto-expands matches. Unsorted bucket pinned at the end. |
| Import pipeline (DESIGN: Import surfaces) | Imports | Drop zone → preview ("what would be created") → apply (idempotent, atomic) → done summary with gap flags (unclassified securities, missing logos, unknown kinds — FR-6/FR-7). Never silently defaults. Parse/validation failure ends at the preview stage with `.alert-error`; nothing is applied. |

## State Patterns

| State | Surface | Treatment |
|---|---|---|
| Cold load | Dashboard, Portfolio | Server-rendered first paint: layout arrives complete; charts and count-up numbers play their one-shot build as the data is already there (no client fetch). No skeletons needed for LiveView's initial render. [ASSUMPTION] |
| LiveView action pending | Chart toggles, tabs | Busy state on the triggering control (existing `.is-busy` / `phx-click-loading` spinner); surface stays interactive. |
| Empty — no data at all | Dashboard | Dashed `.empty-state` well replacing the hero: "Nothing here yet — import a PP export or record a transaction," linking to Imports and Transactions. Replaces today's permanent "Workflow path" checklist, which retires once data exists. [ASSUMPTION] |
| Empty — per surface | Tables, trees | One sentence + one action ("No categories yet." + `+`). Never an unexplained blank region. |
| Error — validation | Forms | Inline `.field-error` at the field, `.alert-error` for form-level; form stays open with input retained. Each error text is linked via `aria-describedby`, the field gets `aria-invalid="true"`; on failed submit, focus moves to the first invalid field; the form-level alert is `role="alert"`. |
| Filter/search — no matches | Tables, trees, search fields | Controls stay visible; "No matches for 'X'." — never the empty-surface message, never an unexplained blank region. |
| Error — action failed | Any | `.alert-error` banner at the top of the workspace page, plain sentence, no codes. |
| Stale data / freshness | Dashboard hero, Portfolio, security detail | Quotes and valuations show their basis date ("As of 12 Jun 2026"). When the newest quote is older than the previous trading day, the timestamp shifts to {colors.warning} tone **and** carries a clock glyph + "stale" text — never hue alone. [ASSUMPTION] No backend freshness field is confirmed; pattern follows the research precedent (Parqet's prominent last-sync) — open question: data source for "last quote sync". |
| Not found | `/securities/:id`, `/classifications/:id` (and any future parameterized route) | `.alert-error` line inside the shell — never a bare error page; navigation stays available. |

## Interaction Primitives

- **Click/tap to act** — rows navigate or select; cards navigate; charts respond to hover/touch with the crosshair.
- **Disclosure affordances** — `+` for create, kebab (`⋮`) for row actions, `<details>` summaries for tree nodes and menus. One open disclosure at a time per region. Menus built on `<details>` keep native disclosure semantics (no `role="menu"` — that would demand arrow-key support); a shared hand-written hook provides `Esc`-close and mutual exclusivity.
- **Metric tooltips (ⓘ)** are focusable elements (`<button>`/`<summary>`): the definition appears on focus and on tap, stays visible while hovered, dismisses with `Esc` (WCAG 1.4.13) — never hover-only.
- **Drag-and-drop** — Classifications only: drag securities between categories; multi-select then drag or use the toolbar. Always has a non-drag equivalent (the move-to-category select) — drag is an accelerator, never the only path.
- **`Esc`** closes the topmost modal/popover/menu and cancels inline edits.
- **Period pills** on every time-series: 1M/3M/YTD/1Y/Max-style one-tap ranges plus a custom date range. Pills and chart toggles expose their state via `aria-pressed` (or radio-group semantics) — never via accent color alone. [ASSUMPTION] Exact pill set mirrors what `PortfolioLive` ships today.
- **Locale and theme switching** are always-available top-bar primitives, never buried in settings.
- **Banned:** infinite scroll (paging/filtering instead), hover-only affordances on touch surfaces, modal-on-modal stacks, drag as sole mechanism, motion that carries meaning.

## Accessibility Floor

Behavioral floor; contrast and color rules live in `DESIGN.md`.

- **Reduced motion:** every polish animation — chart build, count-up, stagger — sits behind `@media (prefers-reduced-motion: no-preference)`. Reduced-motion users get the complete final frame immediately; no information exists only in motion (motion is polish only, so nothing is lost). **Exception:** loading indication is information, not polish — under `reduce`, the spinner is replaced by a non-animated cue (static glyph or "Loading…" text), never removed.
- **Keyboard:** all disclosures, menus, and forms operable by keyboard; the shell already uses semantic landmarks (`aside`/`nav`/`main`, `aria-label`s, `aria-current="page"`); visible focus is a **solid 2px accent outline** (+ optional soft halo) on every interactive element — the 18%-opacity soft ring is decoration on top, never the indicator itself (inputs keep {components.input.focus} as the layered variant). The sidebar toggle is focusable and shows a focus outline (shipped). `Esc` always closes the topmost layer.
- **Color independence (binding):** gain/loss, SOLL/IST over/underweight, and buy/sell are never conveyed by hue alone — signed values render an explicit "+/−" (or ▲/▼), buy/sell chart markers differ in shape (▲ buy / ▼ sell), stale timestamps carry the clock glyph + text. {colors.positive}/{colors.danger} reinforce meaning, they never carry it solo.
- **Screen reader:** page changes announce via the existing `aria-live` top-bar title region (`aria-live="polite"`; only the title text node changes, so navigation announces exactly once); icons stay `aria-hidden` with text labels or `.visually-hidden` companions (shipped pattern — keep). Every portfolio-bearing surface states the active scope (active portfolio) in its subtitle or basis line; scope changes announce via the same live region — under reduced motion the label is the only change cue.
- **Touch targets (owner decision):** interactive controls grow to ≥ 44px effective target on touch devices — via `@media (pointer: coarse)`, not a width breakpoint, so iPad in landscape is covered; desktop keeps the dense 32–34px controls. Bottom-sheet menu rows already comply. Mechanism (padding vs. min-height per control class) is the implementation's call.
- **Charts (binding):** SVG carries `role="img"` + `aria-label` (shipped); the data behind any chart is always also reachable as a table on the same or a linked surface — this rule is what makes the single-`aria-label` chart strategy and the 9px axis type acceptable.
- **Language (binding):** `lang` follows the active locale so screen readers pronounce German strings correctly.

## Responsive & Platform

One IA, three surfaces; pixel values live in DESIGN.md Layout & Spacing. Consolidated trigger → behavior map:

| Trigger | Behavior |
|---|---|
| Desktop (≥ 900px) | Fixed sidebar ({spacing.sidebar-width}) or icon rail ({spacing.sidebar-rail}); dense 32–34px controls; hover affordances allowed (always with focus/tap equivalents). |
| < 900px | Sidebar becomes the off-canvas overlay over a backdrop (top-bar burger); content full-width. |
| < 720px | Dialogs and menus go single-column; row kebab menus become bottom sheets (44px+ rows). |
| < 560px | Base type bumps to 14px; page subtitles hide; tables scroll horizontally. |
| `pointer: coarse` (any width — covers iPad landscape) | Interactive targets ≥ 44px; drag-and-drop yields to select+toolbar; tooltips open on tap. |
| `prefers-reduced-motion: reduce` | Polish motion off, finished frames immediately; loading cues stay, non-animated. |
| `prefers-color-scheme` | System theme as default; explicit `[data-theme]` overrides. |

## Key Flows

Protagonist: **Alex** (fictional persona name), the operator-investor (PRD §2). Flow names mirror the PRD user journeys verbatim. Scannable mapping: UJ-1 → Flow 1 · UJ-2 → Flow 2 · UJ-3 → covered by Flow 1 step 4 (agent-side journey; same drift table) · UJ-4/UJ-5 → future phase, deliberately absent · UJ-6 → Flow 3. No real session was narrated (Fast path) — **every flow below is [ASSUMPTION]** in its step detail; the journey intent is PRD-canonical. UJ-4 (The retirement session) and UJ-5 (The podcast test) are future-phase analytics and deliberately absent from this IST-scope spine; UJ-3 (Cash decision, both directions) is an agent-side journey whose UI counterpart is the same drift table as Flow 1 reads.

### Flow 1 — UJ-1 — Morning briefing (agent journey) — the UI counterpart [ASSUMPTION]

1. Alex has just asked his MCP agent where the new 5k in cash should go; the agent answered from MCP precomputed values. He opens Portfolixir on the iPad to *see* it.
2. Dashboard loads server-rendered: the hero top-left builds once — total value counts up, the performance curve draws in left to right (~1s, ease-out), metric cards settle. "As of" date sits under the total.
3. The drift metric card shows the same top-drift category the agent named. He taps it.
4. Portfolio opens: allocation sunburst, SOLL/IST drift table with category swatches, the overweights and underweights in {colors.positive}/{colors.danger}.
5. **Climax:** the number the agent spoke and the number on the screen are the same number, with the same basis date stated — agent and UI are two views of one analytics engine, and Alex never recomputed anything. He hovers "SOLL/IST drift ⓘ" once, smiles at the tooltip he no longer needs, and closes the iPad.

Failure: quotes are stale → the as-of timestamp renders in {colors.warning} tone; the curve still builds, the numbers still state their (older) basis. No blocking, no modal.

### Flow 2 — UJ-2 — Data maintenance without spreadsheets [ASSUMPTION]

1. A broker statement arrived; Alex exports from PP and opens Imports at his desk.
2. He drops the file on the drop zone. Preview renders: "42 transactions would be created, 2 securities unknown." Nothing has been written yet.
3. He applies. The import runs idempotently and atomically; the done summary shows stat cards and flags the two unclassified securities — surfaced, not silently defaulted.
4. He follows the flag link to his "Asset classes" classification. The tree opens *as a tree*: categories with swatches and counts, search on top, the two new securities in the pinned Unsorted bucket. No form occupies the sightline.
5. He multi-selects both rows and drags them onto "Aktien Welt"; the count ticks up, the toolbar disappears with the selection.
6. **Climax:** he hits the `+` in the Classifications nav head, a compact disclosed form slides open, he adds a "Crypto ETPs" category, and the form closes back to nothing — the screen that used to greet him with a wall of inputs now only ever shows them for the three seconds he wants them. The spreadsheet and PP reconciliation stay retired.

Failure: re-dropping the same file → preview reports "already imported — re-import is a no-op" (content-hash); applying changes nothing and says so.

### Flow 3 — UJ-6 — The family view [ASSUMPTION]

1. Sunday evening; Alex reviews the second household portfolio. He switches scope to it. [ASSUMPTION] The switcher mechanism (#327) is in flight; this spine assumes a scope control on the portfolio-bearing surfaces, not a second navigation.
2. Portfolio, holdings, performance — every view now filters to that scope (FR-4); the as-of basis and currency stay stated.
3. The hero rebuilds once for the new scope: its total counts up, its curve draws in — the one-shot build doubles as the "you are now looking at different data" cue, though the scope label, not the motion, carries the meaning.
4. He checks that portfolio's drift table, records one buy in Transactions through the disclosed form, confirms it appears in the ledger.
5. **Climax:** switching back to his own scope, the dashboard rebuilds to his numbers — two portfolios, one instance, one operator, zero mental bookkeeping about whose data he is looking at, because every surface states its scope.

Failure: a validation error on the transaction form → inline field error, form stays open with the input intact; nothing half-writes (ledger atomicity, FR-2).
