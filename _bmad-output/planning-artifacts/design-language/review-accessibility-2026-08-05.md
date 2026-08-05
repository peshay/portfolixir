# Accessibility Review — Refreshed Design-Language Spec

Reviewed: 2026-08-05 · Benchmark: WCAG 2.2 AA, applied pragmatically for a solo
self-hosted tool · Scope: `DESIGN.md` + `EXPERIENCE.md` as refreshed 2026-08-05,
checked against the built surface (`priv/static/app.css`,
`lib/portfolixir_web/**`) · Predecessor: `../ux-designs/ux-portfolixir-2026-06-12/review-accessibility.md`
(2026-06-13)

Every finding is tagged **[SPEC GAP]** (the document fails to require something),
**[BUILD DEFECT]** (the document is right, the code is wrong), or **[BOTH]** —
they route to different work. A third pattern appears often enough this round to
name it: a document section labelled *as built* that describes behavior the build
does not have. Those are filed as [BOTH], because the wrong sentence is what
keeps the missing behavior off the backlog.

Out of scope this session (a parallel pass owns them): the contrast-table
carry-over, `warning-soft-dark`, the two unmeasured colour pairings, the three
severity icon glyphs, the data-note disclosure wording, the period-control token
subsets, the DR4 reachability pass, the bilingual-label ruling, the
quote-freshness source.

---

## Carry-forward from the 2026-06-13 review

| 2026-06-13 finding | Status | Note |
|---|---|---|
| critical — `text-subtle` used for content | **fixed (spec)** | DESIGN Colors now restricts it to "disabled states and pure decoration only", with the 2.47:1 figure inline. Build uses it for nav icons and the splitter handle — decoration, acceptable. |
| high — no non-colour channel for gain/loss, drift, buy/sell, staleness | **fixed (spec), one channel still missing in build** | DR7 is binding and enumerated. But buy/sell markers are still hue-only in the build — see H6 — and DR7's enumeration was **not** extended to the refresh's new pending/settling vocabulary — see C1. |
| high — `tx-buy` #10b981 at 2.54:1 on light chart surface | **fixed** | Markers resolve `--color-positive` (#047857) in both themes (`app.css:3126`). Frontmatter token divergence noted as L3. |
| high — modal spec had no focus trap / `aria-modal` | **fixed (spec), regressed (doc accuracy)** | DR9 states it. DESIGN's *as built* inventory now claims native `<dialog>`, focus-trapped — the build has neither. See H7. |
| high — chart-as-table and `lang` were `[ASSUMPTION]` | **fixed** | Both binding. `lang={@locale}` shipped (`layout_view.ex:11`). Chart-as-table still absent on two surfaces, which the spec records — but see C2 for why the sunburst gap is now load-bearing. |
| medium — coral as normal-size text | **fixed** | Binding large-text-only rule in DESIGN Colors. |
| medium — reduced-motion over-rotated on spinners | **fixed** | Accessibility Floor carries the explicit "loading indication is information" exception. |
| medium — CSS-only sidebar toggle / `aria-expanded` | **fixed (spec + build)** | Real `<input type="checkbox">` with a state-neutral name (`app_shell.ex:15`). Residual semantic problem in L4; the off-canvas `Esc`-close is still unbuilt (L2). |
| medium — `<details>` menus: no `role="menu"`, Esc, mutual exclusivity | **partly fixed** | Rule stated; mutual exclusivity built (`layout_view.ex:1044-1080`). Esc unbuilt (L2). The rule's `<details>` scoping now misses the one place `role="menu"` actually ships — M4. |
| medium — ⓘ tooltip keyboard/touch behaviour | **fixed (spec), built as `<details>`** | Focusable summary, opens on tap. Esc-dismiss claimed but unbuilt (L2). |
| medium — form error association | **fixed** | State Patterns requires `aria-describedby` / `aria-invalid` / `role="alert"`; built on snapshots and transactions. |
| medium — focus indicator too faint | **fixed (spec), unfixed and under-counted (build)** | The 2px-solid commitment is now explicit and correct. The build still uses the 18% ring as the indicator on inputs, and the document's tally of suppressions is wrong — M5. |
| medium — keyboard multi-select in Classifications | **fixed (spec), unbuilt** | EXPERIENCE specifies checkbox + `Space`. Build is click-only, JS-held, no ARIA (M1). |
| medium — 9.5px locale pill | **fixed** | `.locale-link` is 12px, pinned by the spacing-scale test. |
| low — `aria-live` politeness | **fixed** | `aria-live="polite"` on the top-bar title region. |
| low — chart toggles lacked pressed semantics | **fixed** | `aria-pressed` throughout the toolbars. |
| low — scope label prominence | **fixed** | Basis-line rule in Voice and Tone plus Flow 3. |
| low — `text-soft` never body copy | **fixed** | Hard rule in DESIGN Colors. |

**Nothing from 2026-06-13 regressed in behavior.** Two regressed in *description*:
the modal inventory line and the buy/sell marker inventory line now assert
compliance the build does not have, which is worse than the 2026-06-13 silence
because it removes the item from view.

---

## Critical

### C1 — [SPEC GAP] The pending state asserts a real, current-looking number to assistive technology

**Location:** `DESIGN.md` frontmatter `{components.value-slot}.pending` and
`.pending-fallback`; DESIGN "Value slot" §, the paragraph beginning "**Pending —
last known value, dimmed**"; `EXPERIENCE.md` State Patterns, Pending row.

The refresh replaces a bare `…` with the last known value. Everything that marks
that value as stale is either colour or unspecified: the digits move to
`{colors.text-muted}`, and the slot gains "a recomputing cue and its as-of date"
— but the spec never says what channel the cue uses, whether the as-of date is
DOM text or a `title=`, or whether anything about the state is programmatically
determinable. A screen-reader user, a braille reader, a forced-colors user and
anyone with reduced colour discrimination all receive a plain, authoritative
number that is not the current number.

This is a *regression in honesty* relative to the build it replaces:
`portfolio_live.ex:715-780` renders `…`, which is uninformative but at least is
not a false figure. The refresh's own framing — "A magnitude is visible while the
server works, instead of a void" — is exactly the property that makes the failure
mode expensive on a money surface.

Note also that DR7's colour-independence enumeration (gain/loss, drift, buy/sell,
staleness, data-note severity) was **not** extended to cover pending/settling,
even though those two states are now distinguished from `final` primarily by a
colour step.

**WCAG:** 1.4.1 Use of Color (A), 1.3.1 Info and Relationships (A), 4.1.2
Name/Role/Value (A).

**Fix (spec):** bind three requirements into `{components.value-slot}` and add
pending/settling to DR7's list:

1. the slot carries `aria-busy="true"` for the whole pending state;
2. the recomputing cue is **rendered text inside the slot's accessible unit**
   (`.visually-hidden` where the visual design shows only a glyph), stating state
   and basis — e.g. "recomputing; last computed 2026-08-04";
3. the as-of date is DOM text, never a `title` attribute or a tooltip-only string.

---

### C2 — [SPEC GAP] The sequential chart sweep streams partial values into a proportional chart, and its stated mitigation does not exist on the surface it applies to

**Location:** `DESIGN.md` "Value slot" §, the paragraph beginning "**Progressive
chart fill — sequential sweep**"; `EXPERIENCE.md` State Patterns, "Progressive
chart fill" bullet, and DR20's closing treatment paragraph. Target surface:
`lib/portfolixir_web/live/portfolio_live.ex:1790-1820` (`allocation_sunburst/1`).

Three problems compound:

1. **It contradicts DR20 in the same document.** DR20 states "**real partial
   values are never streamed**" and DESIGN's Motion section states "motion is
   polish only — it never encodes information". A sunburst shows *shares*: until
   the last value lands, every segment's rendered angle is wrong, so each
   intermediate frame is a false statement about every category, not just the
   missing ones. The spec acknowledges this ("the chart briefly shows proportions
   it does not have") and pre-closes the debate ("stated so nobody re-litigates
   it later"). It needs litigating: the exception is granted to the one chart
   whose semantics make it least defensible.
2. **Its duration is unbounded.** "Segments appear clockwise as their values
   arrive" ties the animation to server latency, not to the ~600ms–1.5s motion
   budget the same section sets for build-in. "The build is short" is an
   assumption about the backend, not a constraint the design can enforce.
3. **The fallback that would rescue it is missing on this exact surface.** DR10
   makes chart-as-table the mitigation for everything charts cannot convey. The
   sunburst has `role="img" aria-label="Allocation"` and **no data table at all**
   — the spec records this as drift elsewhere, but the sweep decision now depends
   on it. A user who cannot perceive the animation completing — screen reader,
   reduced motion, a glance away, a slow paint — has no second channel and no
   cue that the frame is not final.

**WCAG:** 4.1.3 Status Messages (AA) for the missing "building" state; 1.3.1 for
the missing programmatic completion signal. No SC forbids displaying incorrect
data, which is precisely why the prohibition has to come from DR20 and be
enforced here.

**Fix (spec):**

- Reverse the mechanism: compute the full allocation, then reveal the **final**
  geometry clockwise. Segments appear in sequence; no segment's angle ever
  changes. The aesthetic survives, the false-proportion window disappears, and
  the sweep becomes genuine polish, which is the only category DESIGN Motion
  permits.
- Gate the reveal behind `prefers-reduced-motion: no-preference`.
- Mark the chart `aria-busy="true"` while values are outstanding, and require the
  chart's `aria-label` **and** its data table to carry final values only — never
  populated progressively. The existing "the legend must not settle before the
  geometry does" constraint currently governs only the visible legend.
- Make the sunburst's chart-as-table disclosure a **precondition for shipping the
  sweep**, stated in the sweep paragraph itself.

---

## High

### H1 — [SPEC GAP] `DESIGN.md` and `EXPERIENCE.md` contradict each other on settling under reduced motion

**Location:** `DESIGN.md` "Value slot" §, closing sentence of the settling
paragraph — "Under `prefers-reduced-motion` the animation drops but the
*indication* remains — dimmed digits and a static bar at rest, never a silently
final-looking value" — versus `EXPERIENCE.md` State Patterns, Settling row —
"under `reduce` the final value appears immediately" — and the paragraph above the
table, "each collapses to the finished state with no animation".

`EXPERIENCE.md` is right and `DESIGN.md` is harmful. Settling is by definition a
state in which the final value is **already known**; the count-up is cosmetic.
Preserving "dimmed digits and a static bar" under `reduce` therefore paints a
permanent not-yet-final indication onto a value that is final — reduced-motion
users would be told, indefinitely, not to trust a correct number. The correct
carve-out ("loading indication is information, not polish") belongs to *pending*,
which has a genuinely unknown value; it does not transfer to settling.

**WCAG:** 1.3.1, and the Accessibility Floor's own reduced-motion rule.

**Fix (spec):** `DESIGN.md` defers to `EXPERIENCE.md` — under `reduce`, the
settling state does not exist: digits render at full colour, no bar. Only pending
keeps a non-animated cue.

### H2 — [SPEC GAP] The reduced-motion form of the no-prior-value pending slot is undefined, and as written the indication vanishes

**Location:** `DESIGN.md` frontmatter `{components.value-slot}.pending-fallback`
— "skeleton gradient reuses .section-skeleton stops at text size — gated behind
prefers-reduced-motion: no-preference".

Follow the gate: under `reduce`, the shimmer does not render. There is no prior
value to dim, because that is the branch's precondition. The spec therefore
specifies *no appearance at all* for first load under reduced motion — an empty
slot that is indistinguishable from "not computable", which is the exact
confusion the whole value-slot work exists to end. It also directly contradicts
the Accessibility Floor: "under `reduce` an animated indicator is replaced by a
non-animated cue, **never removed**".

**WCAG:** 4.1.3 (AA), 1.3.1 (A).

**Fix (spec):** split the fallback into substance and dressing. Substance (always
rendered): a static muted placeholder occupying the value's footprint, plus
`aria-busy="true"` and a `.visually-hidden` "computing" string. Dressing (gated
behind `no-preference`): the shimmer animating over that placeholder.

### H3 — [SPEC GAP] No announcement policy for pending → settled, and the count-up is a live-region hazard

**Location:** `EXPERIENCE.md` Accessibility Floor, "Screen reader" bullet (covers
page-title and scope changes only); `DESIGN.md` Motion, the count-up hook
paragraph.

The approved hook drives `requestAnimationFrame` + `Intl.NumberFormat`, rewriting
each slot's text roughly 60 times per second, across a KPI band of five cards
(`portfolio_live.ex:715-780`). Nothing in either document says whether the
transition from pending to settled is announced, and nothing warns implementers
off the obvious wrong answer. Wrapping each card in `aria-live="polite"` — the
default instinct for "the value changed" — produces hundreds of queued
announcements per band per recompute and renders the surface unusable with a
screen reader on.

The opposite failure is equally live: with no announcement at all, a screen-reader
user who read the pending value never learns the real one arrived.

**WCAG:** 4.1.3 Status Messages (AA).

**Fix (spec):** state the policy explicitly in the Accessibility Floor, including
the negative half so it is not re-derived per surface:

- value slots are **never** inside an `aria-live` region;
- each slot carries `aria-busy` `true` → `false` across pending and settling;
- the counting digits are `aria-hidden="true"` for the duration of the count, and
  the final value is exposed on settle;
- **one** polite live region per KPI band announces once, when the last slot
  settles ("Key figures updated, as of …") — one utterance for five cards.

### H4 — [SPEC GAP] Data-note severity has no assistive-technology contract

**Location:** `DESIGN.md` `{components.data-note}` and the severity table in
"Data note — three severities, one component"; `EXPERIENCE.md` DR17 and the three
State Patterns rows.

"Colour AND icon AND word" is the right redundancy, and it is stated three times.
But nothing binds the parts to the accessibility tree:

- the **word** is never required to be DOM text. A compliant reading renders the
  severity as `title="Problem"` or as an icon whose meaning lives in the visual
  legend, and severity then reaches nobody using assistive technology;
- the **icon** is never required to be `aria-hidden`, so a decorated note can
  announce its glyph twice or announce an unlabelled `<svg>`;
- **no role is specified for any severity.** The question of `role="status"`
  versus `role="alert"` is not answered, or asked, anywhere in either document.

The role question is not academic: data notes appear *after* asynchronous
computation, without a focus change (a stale-quote note materialises when the
recompute lands; import findings appear when the preview resolves). That is a
status message. And the naive answer — `role="alert"` for `problem` — is wrong at
page scale: a data-quality section arriving with a dozen problems would fire a
dozen assertive interruptions and drown the surface.

**WCAG:** 4.1.3 Status Messages (AA), 1.3.1 (A), 1.4.1 (A) for the colour-only
degradation when the word is not text.

**Fix (spec):** add a semantics row to `{components.data-note}`:

- the severity word is always in the DOM as text (`.visually-hidden` where the
  visual design shows only the icon); the icon is `aria-hidden="true"`;
- `note` and `attention` → `role="status"` (polite);
- `problem` → `role="alert"` **only** when the note appears in direct response to
  a user action; a note present on load or arriving with a batch is `role="status"`;
- the remedy control is inside the note element, so it is adjacent in reading
  order and not only in visual position (DR17 currently states adjacency in
  pixels, not in the DOM).

### H5 — [BOTH] Second-level tabs: two nav landmarks with one name, two "current page" markers, and a level distinction only sighted users receive

**Location:** `DESIGN.md` `{components.selected-nav}.icons` and the "Selected
state" §, item 1; `EXPERIENCE.md` Component Patterns, Tab system row. Build:
`lib/portfolixir_web/components/app_shell.ex:189-202`.

`area_tabs/1` renders `<nav class="area-tabs" aria-label="Section tabs">` with
`aria-current="page"` on the active link. Reusing it for Cash flow's second level
— which is what "the same control, smaller and iconless" means — produces:

- **two navigation landmarks with the identical accessible name** on one page, so
  the landmark list reads "Section tabs / Section tabs";
- **two elements marked `aria-current="page"`**, since the parent facet and the
  exact destination are both active; a screen reader announces "current page"
  twice with nothing to distinguish parent from child;
- **a level distinction carried entirely by an `aria-hidden` icon.** Icons are
  `aria-hidden="true"` throughout `app_shell.ex`, so "first level has icons,
  second level does not" is invisible to assistive technology — and at 14px it is
  a weak signal for low-vision users too. The refresh's only stated mechanism for
  making nesting legible does not survive contact with either audience.

There is no heading between the two rows either, so nothing in the document
structure says the second row is subordinate.

**WCAG:** 1.3.1 Info and Relationships (A); landmark-naming practice for the
duplicate-name half.

**Fix (spec, then build):**

- the second-level row takes its own accessible name naming the parent facet
  (`aria-label="Cash flow sections"`), never the generic one;
- exactly one `aria-current="page"` per page: the exact destination. The ancestor
  first-level tab takes `aria-current="true"`;
- the second-level `<nav>` is nested inside the first level's section and sits
  under that section's heading, so the level is structural, not glyph-borne;
- state a minimum size for "smaller" — see H8.

### H6 — [BOTH] Buy/sell chart markers are the same shape and differ only in hue — and the document lists the shape-coding as built

**Location:** build — `lib/portfolixir_web/components/security_chart.ex:129-136`
renders `<circle class={"tx-marker tx-#{marker.type}"}>` for both types;
`priv/static/app.css:3126-3132` changes only `fill`. Spec — `DESIGN.md`
"Inventory (**as built**)", Charts bullet: "buy/sell markers shape-coded not
hue-coded (▲ buy {colors.tx-buy}, ▼ sell {colors.tx-sell})".

Buy/sell is the first example DR7 gives, in both documents, of a distinction that
must never be hue-only. It is hue-only in the build. And because the claim sits
in the section headed *as built* — rather than in "Violations in the built UI",
where the five other colour defects are correctly filed — the gap is invisible to
anyone triaging from the document. The `<title>` children inside the markers are
also unreachable: the SVG carries `role="img"`, which collapses its subtree.

**WCAG:** 1.4.1 Use of Color (A).

**Fix:** render ▲ / ▼ paths instead of `<circle>`; until that ships, move the line
out of the inventory and into "Violations in the built UI" so it is on the same
list as the accent-coloured negatives.

### H7 — [BOTH] No modal is a real dialog: no native `<dialog>`, no focus trap, no inert background — and `aria-modal="true"` is asserted anyway

**Location:** build — `securities/security_form_dialog.ex:73`,
`securities/split_wizard_dialog.ex:37`, `securities/logo_override_dialog.ex:25`,
`securities/row_context_menu.ex:160`, `portfolio_accounts/account_form_dialog.ex:50`,
`buckets_live.ex:381` all render `<div class="modal" role="dialog"
aria-modal="true">`; `securities_live.ex:415-419` toggles `aria-modal` on an
`<aside class="detail-pane">` that is not a dialog at all. None of the eight
LiveView hooks is a focus trap (`AutoDismissToast`, `ChartCrosshair`,
`ClassificationDnD`, `ColumnPrefs`, `PPImportDrop`, `PositionedMenu`,
`SecuritySplitPane`, `SunburstTooltip`). Spec — `DESIGN.md` "Inventory (**as
built**)", Overlays bullet: "`.modal` + backdrop (native `<dialog>`,
focus-trapped)". DR9 states the requirement correctly.

`aria-modal="true"` without containment is worse than omitting it: the screen
reader confines its virtual cursor to the dialog while `Tab` continues to walk
the page behind it, so keyboard focus and reading position separate silently and
the user is stranded with no announced context.

**WCAG:** 2.4.3 Focus Order (A); 4.1.2 (A) for the false modality claim.

**Fix:** adopt `<dialog>` + `showModal()`, which DR9 already names as preferred
and which supplies trap, `Esc` and inertness with no bundler. Immediately, and
independently of that work: correct the inventory line to name the violation, and
remove `aria-modal` from the securities detail pane.

### H8 — [BOTH] The 44px coarse-pointer floor misses the controls the refresh consolidates, and `selected-segment` writes a 30px target into its own definition

**Location:** spec — `DESIGN.md` frontmatter
`{components.selected-segment}.option: 'min-height 30px'` with no coarse-pointer
clause; `{components.selected-nav}` specifies second-level tabs as "smaller" with
no floor; DR6 / Accessibility Floor state the ≥44px commitment. Build — the five
`@media (pointer: coarse)` blocks (`app.css:4589`, `4887`, `4998`, `5330`,
`5521`) cover the metric tooltip, security rows, detail-pane tabs, the positions
toggle, view chips, bucket checkboxes, `.icon-mini`, SOLL inputs, the button
family, summaries and selects.

Not covered anywhere: `.area-tab` (~32px, `app.css:4331`),
`.segmented-control__option` (30px, 1409), `.range-button` (32px, 2881),
`.chart-toggle` (32px, 2973), `.period-buttons .button-mini` (3973),
`.locale-link` (30×26px, 743), `.icon-button` (30×30px, 1438), `.theme-choice` /
`.accent-choice` (28×28px, 664), `.row-actions__kebab` (2110). Worse,
`app.css:5330-5339` sets `.bucket-chip-add` to 32px and `.bucket-chip__remove` to
24px **inside** a coarse-pointer block — sub-44px targets written deliberately
into the branch that exists to prevent them.

Two of these are permanent chrome on every screen and every form factor (the
theme/accent menus at 28px, the locale switcher at 30×26px). And the first-level
area tabs fail the floor while the second-level detail-pane tabs meet it — the
refresh now makes "smaller" the defining property of second-level tabs without
saying how small is too small.

**WCAG:** 2.5.5 Target Size (AAA — but binding here by DR6). 2.5.8 Target Size
(Minimum) (AA, 24×24) is met by these controls in isolation; the project's own
commitment is the stricter one and is what the spec must enforce.

**Fix:** give `{components.selected-segment}` and `{components.selected-nav}` an
explicit coarse-pointer clause (44px min-height, 12px label unchanged); state the
44px floor as the hard limit on "smaller" second-level tabs; add the listed
classes to one shared coarse block; delete the 32px/24px overrides.

---

## Medium

### M1 — [SPEC GAP] The three selected-state classes specify appearance only; not one names a programmatic state

**Location:** `DESIGN.md` `{components.selected-nav}`, `{components.selected-segment}`,
`{components.selected-row}` and the "Selected state — three classes, and only
three" §; `EXPERIENCE.md` DR16.

DR16 is the refresh's flagship consolidation, and it is defined entirely in
pixels: wash, border, marker dot, fill, tinted row, inset edge. No class states
`aria-current`, `aria-pressed`, `aria-selected`, or row-selection semantics. The
scattered coverage that does exist lives in other sections (Interaction
Primitives for period selection, the Chart row for toggles), so an implementer
following DR16 for a *new* control has nothing to follow.

`selected-segment` carries a second, subtler problem: it absorbs `.segmented-control`,
`.range-buttons`, `.chart-toggles`, `.period-buttons` **and** `.view-switcher` —
which mixes independent toggles (log scale, show transactions) with one-of-N
choices (range, period, active view). Those need different semantics. One
appearance over two semantics invites `aria-pressed` on mutually exclusive
options, which announces "pressed / not pressed" N times and destroys the "3 of
8" position information a radio group would carry.

Build evidence in both directions: toggles do carry `aria-pressed`
(`securities_live.ex:557-597`, `portfolio_live.ex:802-962`) — that half is
healthy. Selection does not: `securities_live.ex:301-311` renders the selected
row as `<tr class="… is-selected" role="link">` with no `aria-selected` and no
`aria-current`, and `role="link"` on a `<tr>` additionally strips row/column
context from the table. The classification tree is worse: `.dnd-row.is-selected`
(`app.css:3654`) is applied by JS (`layout_view.ex:691-825`) to `<li>` elements
with no `tabindex`, no checkbox, no ARIA — so selection there is pointer-only and
invisible to assistive technology, and `EXPERIENCE.md`'s "each row carries a
checkbox (`Space` toggles)" is unbuilt.

**WCAG:** 1.3.1 (A), 4.1.2 (A), 2.1.1 Keyboard (A) for the tree.

**Fix (spec):** add a state line to each class — nav/tabs → `aria-current`
(`"page"` for the exact destination, `"true"` for an active ancestor); segment →
`aria-pressed` for independent toggles, `role="radiogroup"` + `aria-checked` (or
links with `aria-current`) for one-of-N, chosen by the control's nature not its
looks; rows → `aria-selected` under a `grid`-shaped table, or the checkbox model
DR1 already specifies. Add one sentence requiring focus and selection to remain
independently visible: a focused-unselected row and a selected-unfocused row must
be distinguishable, and both must be distinguishable from hover.

### M2 — [SPEC GAP] The settling bar is not covered by any contrast commitment, and its minimum rendered size is undefined

**Location:** `DESIGN.md` Colors, "Contrast commitments (binding)" — the
meaningful-graphics bullet names chart lines and buy/sell markers only —
versus `{components.value-slot}.settling`.

The 2px accent bar is the sole visual carrier of "this number is not final", so
it is a graphical object required to understand content, not decoration. Against
the 2026-06-13 measurements the accent-on-elevated pairs clear the bar (violet
5.70, teal 5.47, coral 4.70), so this is a documentation hole rather than a
colour failure — but nothing pins it, and the next token move breaks it silently.
Separately, a 2px bar that begins at zero width has no stated minimum: the first
frames of the indication are imperceptible exactly when the user most needs to
know a count has started.

**WCAG:** 1.4.11 Non-text Contrast (AA).

**Fix (spec):** add the settling bar to the meaningful-graphics bullet with the
≥3:1 requirement against `{colors.bg-elevated}` in both themes, and state a
minimum rendered length at count start (e.g. never less than 10% of the slot
width).

### M3 — [SPEC GAP] The `problem` severity's background is prose, not a token

**Location:** `DESIGN.md` `{components.data-note}.problem`: "border 1px
{colors.danger}, background {colors.danger} at soft tint, text {colors.danger}".

There is no `danger-soft` (or `danger-soft-dark`) in the frontmatter. "At soft
tint" is an instruction to the implementer to invent a colour, which means the
highest-severity note in the system has a background that cannot be measured,
cannot be pinned by a test, and has no dark-mode value — reproducing, in a
brand-new component, the precise defect `warning-soft` already demonstrates two
sections earlier in the same document.

This is distinct from the two unmeasured pairings the parallel pass owns: those
have colours awaiting measurement, this one has no colour at all.

**Fix (spec):** define `danger-soft` / `danger-soft-dark` tokens alongside the
warning pair, and state the `{colors.danger}`-on-`danger-soft` pairing so it
enters the contrast table when that lands.

### M4 — [BOTH] `role="menu"` ships without arrow-key support — the exact failure the spec forbids, in the one place the rule does not reach

**Location:** build — `lib/portfolixir_web/live/securities/row_context_menu.ex:23-139`
renders `role="menu"` with nine `role="menuitem"` buttons; the `PositionedMenu`
hook (`layout_view.ex`, ~line 255-270) binds `resize` and `scroll` only — no
`keydown`, no roving `tabindex`, no focus move on open, no focus return on close.
Spec — `EXPERIENCE.md` Interaction Primitives: "Menus built on `<details>` keep
native disclosure semantics (no `role="menu"` — that would demand arrow-key
support)".

The reasoning is exactly right and the scoping is exactly wrong: the rule is
attached to `<details>` menus, so it does not bind the one menu in the app that
actually claims the role. Announced as a menu, the control invites arrow keys
that do nothing. `securities_live.ex:318-320` also advertises
`aria-haspopup="menu"` on the kebab trigger, which commits to the same pattern.

**WCAG:** 4.1.2 (A), 2.1.1 (A); ARIA Authoring Practices menu pattern.

**Fix:** widen the rule to "no `role="menu"` anywhere unless the full keyboard
pattern ships", then either drop the roles here (buttons in a labelled group,
which is what the control actually is) or implement roving focus + `Esc` + focus
return. Reconcile `aria-haspopup` with whichever is chosen.

### M5 — [BUILD DEFECT] Eight focus suppressions, not five — and the segmented family has no focus rule at all

**Location:** `DESIGN.md` Do's and Don'ts, the note beginning "Note on the last
two rows" — "five `:focus-visible` rules set `outline: none`".

Actual count in `priv/static/app.css`: **eight** — 402 `.nav-link`, 627
`.theme-menu-trigger` / `.accent-menu-trigger`, 680 `.theme-choice` /
`.accent-choice`, 758 `.locale-link`, 1393 `.search-field input`, 2057
`.securities-detail-splitter`, 2126 `.row-actions__kebab`, 2163
`.row-context-menu__item`. Three are not on the document's list: the theme and
accent menu triggers, **every item in every row-actions menu**, and the securities
search field. A fix story scoped to the documented five leaves those suppressed.

Beyond the suppressions: `.area-tab` (4346) and `.positions-toggle` (4377)
indicate focus by a text-colour change only; `.segmented-control__option`,
`.range-button`, `.chart-toggle` and `.period-buttons .button-mini` have **no**
`:focus-visible` rule whatsoever, falling back to the UA ring — and those four are
precisely the classes DR16 consolidates into `selected-segment`, so the aligned
component must arrive carrying the rule. `.securities-detail-splitter` signals
focus only by turning its handle accent-coloured, which is colour-only. And
`input:focus` (1050-1055) still uses the 18% ring *as* the indicator, which the
Colors commitment explicitly forbids — correctly identified in the document, still
unfixed.

**WCAG:** 2.4.7 Focus Visible (AA), 1.4.11 Non-text Contrast (AA), 1.4.1 for the
splitter.

**Fix:** correct the tally, and implement the 2px accent outline as one shared
`:focus-visible` rule rather than reinstating it class by class.

### M6 — [SPEC GAP] A 2px accent outline is invisible where the adjacent colour is the accent

**Location:** `DESIGN.md` Colors, "Contrast commitments": "Focus indicator: solid
2px accent outline ≥ 3:1 against adjacent colors."

The refresh makes the active segmented option a **filled accent**
(`{components.selected-segment}.option-active`) and the active tab an **accent
underline**. Focus the active option and the specified indicator abuts its own
colour at 1:1. The build's only mitigation is `outline-offset: 2px` where it
happens to be written (`app.css:942`, `2285`, `4481`, `4778`); the offset is
nowhere stated as required, and four of the affected controls have no focus rule
at all (M5).

**WCAG:** 1.4.11 (AA), 2.4.7 (AA).

**Fix (spec):** state that the focus outline always renders with ≥2px offset over
the container surface — or takes a contrasting second colour — whenever the
focused element's own fill is the accent.

### M7 — [BOTH] Reduced motion is implemented in the opt-out form everywhere, while the spec binds the opt-in form and then praises the build

**Location:** `DESIGN.md` Motion: "gate ALL animation behind `@media
(prefers-reduced-motion: no-preference)` — the opt-in form", followed by "Four
other animations … **do** carry a `reduce` fallback — the skeleton is the
outlier, not the norm".

`priv/static/app.css` contains **zero** occurrences of `no-preference`. All
handling is `@media (prefers-reduced-motion: reduce)` (2522, 3017, 4649, 4724),
plus the ungated `.section-skeleton` (4436) the document already flags. The two
forms are not equivalent: where the media feature is unsupported or unreported,
`reduce` fails open (the animation runs) and `no-preference` fails safe (it does
not). The document binds the safe form and then describes the unsafe form as
compliance, which guarantees the gap survives review.

The refresh makes this newly urgent: the count-up is a **JS** hook, so no CSS
gate covers it. Nothing in either document requires the hook to consult
`matchMedia("(prefers-reduced-motion: reduce)")` and to re-check on change.

**Fix:** pick one form and make the document and build agree; add an explicit
line requiring the count-up hook to read the preference at start and on change,
skipping straight to the final value under `reduce`.

### M8 — [SPEC GAP] No forced-colors story, and the new loading vocabulary is entirely colour-step based

**Location:** neither document mentions forced colors / high-contrast mode;
`priv/static/app.css` contains zero `forced-colors` rules.

Under Windows High Contrast (and equivalents), author colours are replaced by a
small system palette: `{colors.text-muted}` and `{colors.text}` collapse to the
same value, tinted backgrounds are dropped, and thin decorative bars may not
render. The consequence for the refresh's new vocabulary is direct — **pending,
settling and final become pixel-identical** — which is C1 and H1 arriving through
a second door, for a user population that overlaps heavily with low vision.

The data note survives this test well, because icon + word are independent of
colour: that is the redundancy paying off, and it is the argument for extending
the same discipline to the value slot.

**WCAG:** 1.4.1 (A) in effect.

**Fix (spec):** one binding line in the Accessibility Floor — every state
distinction must survive `forced-colors: active`, carried by text, glyph or
border, never by a colour step alone — plus a `forced-colors` block for the
indicators the design depends on.

---

## Low

### L1 — [BUILD DEFECT] Interactive SVG children inside `role="img"`

`portfolio_live.ex:1802-1818` (sunburst paths) and `income_live.ex:116-128`
(income bars) attach `phx-click` to elements inside an SVG carrying
`role="img"`, which collapses the subtree for assistive technology; the `<title>`
children are unreachable and the shapes are not focusable. Income provides an
equivalent keyboard path (the `.income-bar-label` buttons with `aria-pressed`,
`income_live.ex:132-145`) — the sunburst does not: `select_segment` is
pointer-only. **WCAG 2.1.1 (A), 4.1.2 (A).** *Fix:* keep `role="img"` and give
the sunburst a real control path — the mandated data table's rows are the natural
selection targets, which is another reason C2's table precondition pays twice.

### L2 — [BUILD DEFECT] `Esc` closes nothing

`EXPERIENCE.md` states "`Esc` always closes the topmost modal/popover/menu",
`Esc`-dismiss for ⓘ tooltips, and `Esc`-close for the off-canvas sidebar.
`layout_view.ex` contains no `Escape` handling anywhere; only outside-click
mutual exclusivity for the theme/accent menus (1044-1080). Not a strict AA
failure for the ⓘ — WCAG 1.4.13 governs hover/focus-triggered content, and these
are click disclosures — but three documented behaviours do not exist.

### L3 — [SPEC GAP] `tx-buy` / `tx-sell` tokens do not exist in the build

`DESIGN.md` declares four `tx-*` tokens; `app.css:3126-3132` resolves
`--color-positive` / `--color-danger` directly and defines no `--color-tx-*`.
Values agree today, so this is harmless — but the frontmatter implies a knob that
cannot be turned. *Fix:* define the tokens, or record the aliasing in the Colors
section.

### L4 — [SPEC GAP] The sidebar checkbox's `checked` state means opposite things at different breakpoints

`app_shell.ex:15-20`: one `<input type="checkbox" aria-label="Toggle
navigation">`. Above 900px, checked collapses the sidebar to the rail; below
900px, checked opens the off-canvas overlay. A screen-reader user hears "checked"
for both "hidden" and "shown". The state-neutral name satisfies the 2026-06-13
finding; the inverted semantics were not considered. *Fix:* state in
`EXPERIENCE.md` which meaning `checked` carries, and either split the control per
breakpoint or choose a name that survives both.

### L5 — [SPEC GAP] Nothing says what a braille display sees during the count-up

Sixty text rewrites per second per slot will re-render a braille line
continuously and may re-announce under some screen-reader cursor modes even with
no live region. Covered by H3's `aria-hidden`-during-count rule; called out
separately so the braille case is not lost when H3 is implemented as "don't add
`aria-live`".

---

## Verdict

The refreshed spec is stronger than its predecessor on every axis the 2026-06-13
review measured: colour independence is binding and enumerated, the focus
commitment is correct and specific, `lang` and chart-as-table are promoted out of
`[ASSUMPTION]`, the coral and `text-subtle` holes are closed at rule level, and
the reduced-motion carve-out for loading indication is exactly right. Nothing
regressed in behaviour. The consolidation posture — one job, one component — is
itself an accessibility win, because five idioms for "selected" are five chances
to get the semantics wrong.

The new surface area is where it is weak, and it is weak in one specific way:
**the refresh specifies the new loading vocabulary entirely in visual terms.**
Pending, settling, the sweep and the three severities are described in colour
steps, bar widths, sweep directions and glyph counts, and none of them is given a
programmatic contract — no `aria-busy`, no role, no announcement policy, no rule
that the severity word is text. The consequence is sharpest at C1: replacing `…`
with a real, dimmed, last-known number is a genuine improvement for sighted users
and a genuine regression for everyone else, because the app moves from saying
nothing to asserting something false, with the correction carried only in a
colour step. C2 is the same failure in the geometry domain — the sweep displays
proportions the data does not have, its acceptance rests on a chart-as-table
fallback that does not exist on the one chart it applies to, and it contradicts
DR20's own "real partial values are never streamed" three sections after that
rule is written. Both are cheap now and expensive after the count-up hook ships.

The build's own gaps cluster around the commitments the documents restate most
confidently. The 2px focus outline is correct in the spec, suppressed in eight
places in the build and mis-counted as five in the document. The modal rule is
correct in DR9 and contradicted by the inventory line that claims native
`<dialog>` and a focus trap that no hook implements. The buy/sell shape-coding is
the first example DR7 gives and is not built, while the inventory records it as
built. Those three sentences — each sitting in a section headed *as built* — are
the highest-leverage edits in this review, because a wrong description is what
keeps a defect off the backlog.

Nothing here blocks cutting implementation stories; C1, C2, H1 and H2 should be
resolved in the document before the value-slot and sweep stories are written,
since all four change what those stories must build rather than how.

**Counts:** 23 findings — **2 critical, 8 high, 8 medium, 5 low**. By route:
**14 spec gaps** (C1, C2, H1–H4, M1–M3, M6, M8, L3–L5), **3 build defects** (M5,
L1, L2), **6 both** (H5–H8, M4, M7) — three of which (H6, H7, M7) are sentences
in *as-built* sections describing behaviour the build does not have.
