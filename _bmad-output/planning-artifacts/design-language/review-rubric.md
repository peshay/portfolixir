# Spine Pair Review — Portfolixir

Rubric-walker lens (`.claude/skills/bmad-ux/references/validate.md`), run 2026-08-05
against `DESIGN.md` + `EXPERIENCE.md` as refreshed this session, with claims
spot-checked against `priv/static/app.css`, `lib/portfolixir_web/live/`,
`lib/portfolixir_web/components/` and `lib/portfolixir_web/router.ex`.

Scope note: the nine `[OPEN]` items a parallel pass is closing (contrast table
carry-over, `warning-soft-dark`, the two unmeasured pairings, the three severity
glyphs, the data-note label wording, the period-control subsets, the DR4
reachability pass, the bilingual domain-label ruling, the quote-freshness source)
are excluded and are not reported below.

## Overall verdict

This is a strong, unusually honest spec that has outgrown its own machinery. The
decisions are real, the drift analysis is specific, and the DESIGN/EXPERIENCE
split is declared and mostly held — but the connective tissue that makes it
*holdable* is broken in three places at once: the most-referenced colour token in
the document (`{colors.accent}`) does not exist in the frontmatter, the rule
identifiers were silently renamed from `UX-DRn` to `DRn` while 36 repo files
still cite the old form, and the DR index promises definitions that are not there
(DR13) or point at a document that does not acknowledge them (DR14/16/18/19). A
reviewer given this spec and a diff can reach a verdict on maybe two thirds of it;
the rest resolves to a pointer that dead-ends. Cuttability is weaker still: no
rule partitions its deviating call sites into story boundaries, so a thin issue
pointing at DR16 inherits "every selectable control in the app". Six factual
claims about the build are wrong in ways that would send a story to the wrong
file — most importantly the cash-balance form's location and the chart-as-table
census, which omits the very surface Lane B is fixing.

## Category verdicts

| Category | Verdict |
|---|---|
| 1. Flow coverage | thin |
| 2. Token completeness | thin |
| 3. Component coverage | thin |
| 4. State coverage | thin |
| 5. Visual reference coverage | thin |
| 6. Bloat & overspecification | adequate |
| 7. Inheritance discipline | thin |
| 8. Shape fit | adequate |

**Counts: 2 critical · 13 high · 23 medium · 9 low (47 findings).**

---

## 1. Flow coverage — thin

Checked: `sources` frontmatter resolves to the PRD, `epics.md`, four ADRs,
`app.css`, `router.ex` and two component modules. PRD §3 defines UJ-1..UJ-6.
EXPERIENCE.md carries three Key Flows, names them verbatim from the PRD, uses the
PRD's protagonist (Andi), and each has numbered steps, a labelled climax beat and
a failure path. Mechanically the required shape is present.

### Findings

- **medium** No flow exercises any surface this refresh decided. Cash flow's four
  tabs, the Tax budget dashboard, the Snapshots comparison-as-surface and the
  account-row balance dialog are the batch's actual new work and none of them
  appears in a flow (EXPERIENCE.md §Key Flows, lines 336–377). *Fix:* add Flow 4
  "Where did the money come from" walking the four Cash-flow tabs and Flow 5
  "Reconcile a tax statement" over the Tax surface, each with a failure path; or
  state explicitly that unbuilt surfaces inherit Flow 2's shape until built.
- **medium** All three flows are blanket-tagged `[ASSUMPTION]` and line 342 says a
  UAT walkthrough "should overwrite" the step detail — while ADR-0038 makes this
  document the thing UAT is held *against*. A spec that pre-concedes its own
  flows cannot produce a verdict on them. *Fix:* promote the steps to binding
  (they are now checkable against built routes) or move them to a clearly
  non-binding appendix so a reviewer does not weigh them.
- **low** UJ-3 ("Cash decision, both directions") is mapped to "Flow 1 step 4",
  but that step never shows the inverted read the journey is about — which
  overweights can release cash with least strategic damage (EXPERIENCE.md line
  340). *Fix:* one sentence in Flow 1 step 4, or a mapping note that UJ-3 is
  agent-side only and has no UI counterpart.

---

## 2. Token completeness — thin

Extracted every frontmatter key and every `{path.to.token}` in both files. All
twelve EXPERIENCE.md references resolve to real DESIGN.md keys, including
`{components.hero}` (deliberately retained as a record). DESIGN.md's own
references are where it breaks.

### Findings

- **critical** `{colors.accent}` is referenced throughout DESIGN.md prose and
  inside five component definitions — `selected-nav.tab-active`,
  `selected-segment.option-active`, `selected-row.edge`,
  `native-control.checkbox`, `input.focus` — and **is not a key in the `colors`
  frontmatter**. `accent-soft` is used the same way in prose
  (`selected-nav.sidebar-active`, `data-table.hover`) and is likewise absent.
  `app.css:17-18` defines `--color-accent` and `--color-accent-soft` as real
  tokens, so this is a spec omission, not a modelling choice. Frontmatter
  extraction — the whole point of the machine-readable half — yields nothing for
  the single most-referenced token in the system. *Fix:* add `accent`,
  `accent-soft`, `accent-dark`, `accent-soft-dark` to `colors` carrying the
  violet default value, with the same "re-keys with `[data-accent]`" comment
  already used on `selected`.
- **high** Shadows have no tokens at all. `components.stat-card.shadow:
  'shadow-panel'` is a bare string that resolves to nothing; `--shadow-sm/md/
  panel/sidebar` appear only as raw values in Elevation & Depth prose, and the
  dark-mode set is given as "deeper black ones (up to 50% opacity)" — a range,
  not a value. *Fix:* add a `shadows:` frontmatter block with light and dark
  values per level, and change `stat-card.shadow` to `{shadows.panel}`.
- **high** `data-note.problem` has no background token. Frontmatter says
  "background {colors.danger} at soft tint"; the Colors table says "on a danger
  tint". There is no `danger-soft` token and no percentage anywhere. One third of
  the flagship new component of this refresh cannot be built or reviewed.
  *Fix:* define `danger-soft` / `danger-soft-dark` alongside `warning-soft` (whose
  dark value the parallel pass is already adding) and reference it by name.
- **medium** Unquantified percentages sit inside component definitions where a
  reviewer needs a number and cannot infer one: `selected-nav.sidebar-active`
  ("accent-soft→transparent 80% gradient wash, 1px border at accent 26%, 6px
  filled accent marker dot with 3px halo"), `data-table.hover` ("accent-soft wash
  at 42%"), `chart-frame.area-fill` ("accent at 14% opacity"), `input.focus`
  ("3px accent ring at 18%"). 80% / 26% / 42% of *what* — opacity, `color-mix`
  ratio, gradient stop position? *Fix:* express each as the CSS it means, e.g.
  `color-mix(in srgb, {colors.accent-soft} 42%, transparent)`.
- **medium** Breakpoints and the touch-target floor are raw literals duplicated
  across both files with no token: 900 / 720 / 560 appear in DESIGN.md Layout &
  Spacing, EXPERIENCE.md Responsive & Platform, and DR12; 44px appears in
  DESIGN.md Do's, EXPERIENCE.md Accessibility Floor, DR6 and the Responsive
  table; 32–34px in three places. EXPERIENCE.md's Foundation claims "every visual
  value in this spine is a `{path.to.token}` reference into it" and its Responsive
  section claims "pixel values live in `DESIGN.md`" — both false as written.
  *Fix:* add `spacing.bp-sidebar: 900px`, `bp-dialog: 720px`, `bp-density: 560px`,
  `touch-target: 44px`, `density-control: 34px` and reference them from both files.
- **medium** Category and series colours are outside the token system entirely and
  the spec does not acknowledge them. Classification categories carry a
  user-chosen `color` rendered as an inline style (`classifications_live.ex:387`,
  `portfolio_live.ex:1027`) and feed `.cat-swatch`, `.sunburst-seg`,
  `.legend-swatch` and the drift-table swatches. DESIGN.md Colors states
  "[ASSUMPTION] The existing token set is treated as closed; no new hues are
  introduced" and never mentions user-chosen hues, their contrast obligation, or
  how they coexist with one-accent-at-a-time. *Fix:* add a "Category and series
  colour" subsection under Colors ruling on the permitted palette, the ≥3:1 floor
  against `{colors.chart-surface}` that the meaningful-graphics commitment
  already implies, and whether the operator may pick freely.
- **low** `components.pill` is defined in frontmatter and referenced nowhere in
  either document; `chart-tooltip`, `button` and `input` are frontmatter-only with
  no prose story of their own. *Fix:* reference them from the relevant section or
  drop them.

---

## 3. Component coverage — thin

Extracted every component name used anywhere in either file and checked for a row
in DESIGN.md.Components (visual) *and* EXPERIENCE.md.Component Patterns
(behavioral). The eighteen frontmatter components are real specs, not one-word
descriptions — that part is genuinely good. The gaps are components that exist in
one file only, or in neither.

### Findings

- **high** The **"Needs attention" card** has a behavioral row in Component
  Patterns and a dedicated paragraph in DR2, and **no visual spec anywhere in
  DESIGN.md** — not in `components`, not in prose, not in the Inventory. It sits
  on the Overview, it is the block DR2 is built around, and it is a named Lane A
  deliverable. A story cut from DR2 has no anatomy to build; a design critic has
  nothing to hold a diff against. *Fix:* add `components.needs-attention-card`
  (basis-line typography, item-row anatomy, how severity maps onto
  `{components.data-note}`, empty state) plus an Inventory entry.
- **high** The **data-quality section** has no component in either file, although
  DR2 and DR17 both make it load-bearing and DESIGN.md calls it "the app's most
  important warning surface". Worse, `.decision-log.md` records a 2026-07-12
  decision about exactly this block — data quality as ONE line, only when N > 0,
  no green all-clear badge, linking to a *pre-filtered* securities list — and
  flags that it was never recorded and never built, calling it "precisely the
  failure mode ADR-0038 exists to stop". The refresh neither adopts it nor
  overrules it, so the failure repeats inside the document meant to end it.
  *Fix:* rule on it in DR2 (adopt the one-line form, or record that the built
  three-card form wins and why), and give the section a component: container,
  severity ordering, and the remedy-adjacency rule.
- **high** **Inline busy/result states have no specification.** DESIGN.md
  Feedback: "Inline busy and result states replace toasts (`.status-toast`, issue
  #566)". EXPERIENCE.md State Patterns: "Inline busy/result states, not toasts,
  are the target for action feedback." Neither says what a result state looks
  like, where it renders relative to its trigger, how long it persists, or how it
  is announced — while the thing being replaced has a full anatomy today. #566 is
  on the decision log's list of "open E11 issues this spec must speak to".
  *Fix:* add `components.inline-result` (placement, reuse of
  `{components.data-note}` severities, dismissal rule, `aria-live` behaviour) and
  a Component Patterns row.
- **medium** The **tax allowance "fill level"** is named in both files ("a visual
  fill level with the remaining amount") and specified in neither: no anatomy, no
  colour, no threshold semantics. If the fill turns `{colors.warning}` near the
  limit it needs a DR7 companion; the spec does not say whether it does.
  *Fix:* add `components.budget-meter` with track/fill/label anatomy and the
  threshold rule, or state that it is a plain bar with no threshold colouring.
- **medium** `value-slot` and `native-control` have DESIGN.md anatomies but **no
  Component Patterns row**; their behaviour is scattered into State Patterns,
  DR19 and Interaction Primitives. The declared split ("visual anatomy lives in
  `DESIGN.md.Components`") implies every component has both halves. *Fix:* add
  two Component Patterns rows pointing at the existing text rather than restating
  it.
- **low** `.empty-state`, `.rebalance-hint` and the chip family appear in
  DESIGN.md's Inventory as names plus a clause. Inventory-grade entries were
  accepted by the 2026-06-13 review and that still stands — but the chips line
  states a rule ("one chip: filled tag") with no anatomy behind it, so the rule
  cannot be enforced. *Fix:* give the filled tag a `components.chip` entry.

---

## 4. State coverage — thin

Walked the sixteen IA rows against the State Patterns table. Pending / settling /
not-computable are now genuinely well separated and the treatments are decided —
the strongest part of this refresh. What is missing is a whole state class and
the definition of the cue the chosen treatment depends on.

### Findings

- **high** **No LiveView disconnect / reconnect state, anywhere in either
  document.** Foundation declares server-rendered Phoenix LiveView as the
  architecture; a dropped socket is that architecture's characteristic
  degradation. Verified: the codebase has no `.phx-disconnected`, `#client-error`
  or `#server-error` styling either, so the spec is silent about a live gap
  rather than about a solved problem. This interacts badly with the new pending
  treatment: under "last known value dimmed", a dropped socket is visually
  identical to a value that is permanently recomputing. *Fix:* add State Patterns
  rows for disconnected, reconnecting and reconnect-failed — what shows, whether
  controls disable, and how it is distinguished from pending.
- **high** **The "recomputing cue" is never defined.** It is the operative element
  of the chosen pending treatment ("last known value at {colors.text-muted} with
  a recomputing cue and its as-of date") and appears five times across both files
  without ever being specified as a glyph, a word, a spinner or a bar. It must
  survive `prefers-reduced-motion` (the spec says loading indication is
  information, not polish) and it must satisfy DR7, so it cannot be motion or
  colour alone — which leaves exactly one design space the spec declines to
  enter. This is also the Lane A deliverable "replacement of 'Lädt …' text and
  bare dot placeholders". *Fix:* pick the cue inside `components.value-slot`
  (word + glyph), and state whether it replaces or accompanies the six existing
  loading verb strings the spec names as drift.
- **medium** State coverage is organised by state, not by surface, so the rubric's
  per-surface walk cannot be performed against it. Eleven of the sixteen IA rows
  are never named in the table: Imports, Views, Classifications, Accounts &
  depots, Securities, Transactions and the four Cash-flow tabs. The four
  "specified, unbuilt" Cash-flow surfaces receive the strongest instruction in the
  document — "they must not ship as empty shells without their read" — and no
  empty, cold-load or error state to ship instead. *Fix:* add a surface column to
  the table, or a compact per-surface state matrix under IA.
- **medium** "Empty — no data at all | Overview | Dashed `.empty-state` well
  **replacing the hero**" (EXPERIENCE.md State Patterns). The hero was retired by
  this same session (DR2; DESIGN.md Inventory marks it "retired 2026-08-05"). The
  empty state replaces a component the spec says does not exist. *Fix:* restate
  as replacing the total-value block.
- **low** Offline and permission-denied are correctly not applicable to a
  single-user self-hosted instance, but neither file says so, so their absence
  reads as an oversight rather than a ruling. *Fix:* one line in Foundation.

---

## 5. Visual reference coverage — thin

Files present: `mockups/key-dashboard.html`, `mockups/key-classifications.html`,
`.working/loading-affordances.html`, `.working/income-per-instrument.html`. No
`wireframes/`, no `imports/`. Spines-win-on-conflict is stated once, correctly, in
EXPERIENCE.md IA. `key-dashboard.html` is properly marked stale in two places —
that is the model the others should follow.

### Findings

- **high** `.working/income-per-instrument.html` is an orphan carrying a **decided
  outcome that never reached either spine**. `.decision-log.md` records the
  owner's pick — "I2, stacked bars with an aggregated remainder: largest six
  instruments individually, everything else as one 'Sonstige' segment" — together
  with an explicit instruction that the readability constraint ("seven
  distinguishable segments must be built from tints and shades of the active
  accent plus a neutral … whether it holds at the readability limit is a
  **DESIGN.md question, flagged not assumed**") be answered. Verified: neither
  file contains "per-instrument", "stacked" or "Sonstige", and DESIGN.md never
  discusses multi-series colour. A decided design living only in the log and a
  working file is the exact drift ADR-0038 exists to stop. *Fix:* carry I2 into
  EXPERIENCE.md's Income row, and answer the tint-ramp question in DESIGN.md
  Colors — or record that it is unresolved and blocks the Income story.
- **medium** `.working/loading-affordances.html` is cited once, in prose, as the
  provenance of the loading decision and is never linked; `.working/` is never
  declared as a location. The option labels the decision log uses (P1/P2, S1/S3,
  F1/F3) appear nowhere in the spines, so a reader cannot trace a rule back to the
  option it came from or see what was rejected. *Fix:* link both `.working/` files
  inline at the decision they support, with one line on what each illustrates and
  the spines-win clause.
- **medium** `mockups/key-classifications.html` is linked from IA but never named
  for what it illustrates and never assessed for staleness, while its sibling is
  explicitly marked stale twice. It predates DR16 (selected-row), DR19 (native
  `<details>`, checkbox) and the checkbox-stack defect — all of which land on the
  tree surface it depicts. *Fix:* state what it illustrates and whether it
  survived this session's decisions.
- **low** DESIGN.md repeats a scoped spines-win clause in the Hero inventory line
  ("mocks illustrate, they do not specify" is already stated once in
  EXPERIENCE.md IA). Harmless, but the rubric asks for it once. *Fix:* trim to a
  pointer.

---

## 6. Bloat & overspecification — adequate

DESIGN.md's editorial voice is appropriate and earns its place — "token fidelity
is not design coherence" and "a cell is not a card" are the kind of line a
reviewer actually remembers. Prose is used where prose belongs; tables are used
where tables belong. The overspecification risk here is not pixel-level, it is
temporal: a large fraction of both documents is a snapshot of the build's current
defects, and snapshots rot.

### Findings

- **medium** The per-line defect register lives inside the standing spec:
  DESIGN.md's "Violations in the built UI", the Motion live-defect note, the
  Typography residual gaps, EXPERIENCE.md's IA seams, and the inline defect notes
  in State Patterns and Responsive. The spec's own model is right — "the file is
  the target and the build carries the defect" — but the defect half is the
  volatile half and every fix that lands makes the authority document
  fractionally wrong. It already has (see Mechanical notes). *Fix:* keep the
  *rules* here and move the register to a dated companion
  (`drift-register-2026-08-05.md`) that alignment stories close out; the spec then
  cites the register rather than line numbers.
- **medium** EXPERIENCE.md carries editorial voice the rubric reserves for
  DESIGN.md — "prose is the habit", "five is drift, one would be dogma", "a design
  gap wearing text". Mostly harmless and mostly load-bearing, but the Key Flows
  persona correction (line 338: six lines on why "Alex" was invented, why the
  pseudonym was "the dishonest part", and that "Steve" is a reviewer skill) is
  session bookkeeping that `.decision-log.md` already records. *Fix:* cut to
  "Protagonist: Andi, per PRD §2" and leave the history in the log.
- **low** The three loading treatments are stated in full three times — DR20's
  body, State Patterns, and DESIGN.md `value-slot` prose. The third copy is where
  drift will enter. *Fix:* State Patterns carries behaviour, DESIGN.md carries
  anatomy, DR20 carries a two-line summary with pointers — the pattern the index
  already uses for DR5 and DR8.

---

## 7. Inheritance discipline — thin

`sources` resolves; UJ names are verbatim; glossary terms (view, bucket, depot,
SOLL/IST, TTWROR) are used consistently with the PRD and ADR-0024; component names
are identical across sections within each file. The failures are all at the
seam between the two documents and between the spec and the repo that cites it.

### Findings

- **critical** **The rule identifiers were silently renamed.** DESIGN.md cites
  `UX-DR7`, `UX-DR10`, `UX-DR11`, `UX-DR15`, `UX-DR17`, `UX-DR2`; EXPERIENCE.md's
  index and every section heading use bare `DR1`..`DR20`; the rest of the
  repository uses `UX-DR` — verified, 36 files including `app.css`, eight
  LiveViews, ADR-0027/0028/0038, `epics.md` (nine references) and
  `test/invariants/css_spacing_scale_test.exs`, which pins UX-DR14. The document
  ADR-0038 designates as the authority is unfindable by the identifier every
  consumer greps for, and its own peer file disagrees with it in the same
  sentence-space. *Fix:* standardise on `UX-DRn` — the established form; renaming
  36 files is not free — in both spines' headings, index and prose.
- **high** **DR13 is indexed as defined "here" and has no definition.** The index
  row reads "DR13 | State patterns: no-match, error association, freshness basis |
  here", and there is no `### DR13` section (verified: sections exist for DR1, 2,
  3, 4, 6, 7, 9, 10, 11, 12, 15, 16, 17, 18, 19, 20). Its content is scattered
  across three State Patterns rows with no marker tying them to DR13. *Fix:* add
  the section, or change the cell to "State Patterns" and name the rows.
- **high** **The index's DESIGN.md pointers are one-directional.** DESIGN.md never
  contains the strings `DR14`, `DR16`, `DR18` or `DR19`, so a reader following
  "DR18 → `DESIGN.md`" lands in a document that does not acknowledge DR18 and must
  guess that `{components.width-reserve}` is the target. Line 244 concedes this
  and adds an interim rule ("until `DESIGN.md` carries them, the summaries below
  are the interim statement; once it does, `DESIGN.md` wins") — which makes the
  authoritative source of four rules depend on a future edit that nothing tracks.
  A reviewer cannot know which half is currently binding. *Fix:* add the rule tag
  to each DESIGN.md section that carries it (one parenthetical: "Typography
  ramp *(UX-DR14)*", "width-reserve *(UX-DR18)*", …) and delete the interim note.
- **medium** The claim that "`epics.md` keeps the tracker row and **links here
  rather than defining them**" is stated as accomplished fact; `epics.md` still
  carries nine `UX-DR` references whose form has not been verified against that
  claim. *Fix:* verify, and if the conversion has not happened, state it as a
  pending action rather than as fact — a false authority claim is worse than an
  open item.
- **medium** **The surface count contradicts its own table.** EXPERIENCE.md IA
  opens "eleven surfaces across the fourteen `live/3` declarations"; the table
  below has **twelve** rows marked `built` plus four `specified, unbuilt` =
  sixteen; `.decision-log.md` says "IA covers all **13** built routes". Three
  numbers for one fact across three artifacts of one session. Router verified: 14
  `live/3` calls, 11 LiveView modules, 12 built surfaces as the table cuts them.
  *Fix:* state the number the table shows and name the unit being counted.
- **low** DESIGN.md: "eight small inline hooks (`layout_view.ex`,
  `security_chart.ex`)". All eight are defined in `layout_view.ex`;
  `security_chart.ex` only consumes `ChartCrosshair` via `phx-hook`. *Fix:* drop
  the second file or say "consumed in".

---

## 8. Shape fit — adequate

DESIGN.md's sections are in canonical order and complete: Brand & Style → Colors →
Typography → Layout & Spacing → Elevation & Depth → Shapes → Components → Do's and
Don'ts. EXPERIENCE.md carries all eight required defaults, plus Responsive &
Platform (correctly triggered by three target surfaces) and an invented Design
Rules section that clearly earns its place. Invented subsections (Violations,
Every wide block owns its scroller, Inventory) all sit under a plausible parent.

### Findings

- **medium** **No Inspiration section**, though both triggers fire. The sources and
  log name reference products (the research digest, Kubera's "Works for your AI",
  Portfolio Performance as the heritage the product both inherits from and reacts
  against) and four explicit rejects: the visualization-only paradigm, the
  P1+S3+F3 loading combination, the I1/I3/I4 income treatments, and the "four
  fixed metric cards" DR2. The log itself worries about exactly this ("recorded so
  the superseded combination is not mistaken for a parallel option later") — and
  then leaves the record in the log. *Fix:* add a short Inspiration section to
  EXPERIENCE.md: reference products, what was taken from each, and the rejected
  directions with one line each on why.
- **medium** **Motion is buried.** It is a `###` subsection of Do's and Don'ts, yet
  it now carries DR5, the count-up mechanism ruling, the ninth-hook architecture
  decision, the reduced-motion contract and half the settling anatomy — material
  two of this session's three loading decisions rest on. A consumer reading
  DESIGN.md for pending/settling anatomy will look under Components and find a
  cross-reference chain. The 2026-06-13 review accepted this placement when Motion
  was four bullets; it is now the longest subsection in the file. *Fix:* promote
  to a trailing `## Motion` after Do's and Don'ts (legal — it is not one of the
  eight order-locked sections) and cross-link from `components.value-slot`.
- **low** EXPERIENCE.md has an explicit `status: draft` gate listing five open
  items and what closes each — genuinely good practice. DESIGN.md carries four
  `[OPEN]` markers and two `[ASSUMPTION]`s with no equivalent gate list and no
  statement of what `draft` means for it or who lifts it. *Fix:* mirror the gate
  list, or state that DESIGN.md's gate is EXPERIENCE.md's.

---

## 9. Holdability and cuttability

Not a rubric category, but the two properties this spec exists to have (ADR-0038:
the design-critic review holds every user-visible batch against it; E14/E11
stories are cut from it). Reported separately because the failures are systemic
rather than per-section.

### Findings

- **medium** **Rules stated without a verdict criterion.** A reviewer given the
  diff cannot decide these:
  - `width-reserve.techniques` lists three mechanisms ("invisible bold shadow
    text, fixed track widths, or a permanently reserved ornament slot") without
    saying which applies to which of the three selected-state classes — three
    stories will pick three mechanisms and all three will pass. (The `0px`
    tolerance itself *is* testable — that part is right.)
  - DESIGN.md Motion: chart build-in "~600ms–1.5s" with no rule for which
    duration applies where.
  - `disclosure.purpose-line`: "one short line stating why the disclosure exists"
    — "short" is unbounded, and combined with the `[OPEN]` label, DR10's "one
    control, one label, one styling" is unverifiable this sprint.
  - Data-note placement: "adjacent to the data it describes — a remedy button
    ~1100px below the bullet is a violation" gives a failing example and no
    passing threshold.
  - `data-table.hover` vs `selected-row`: "the edge is what distinguishes
    selection from hover" is a good rule, but hover is "accent-soft wash at 42%"
    and selection is `{colors.selected}` — two different tints whose relationship
    is unstated, so a diff using one for the other cannot be faulted.
  *Fix:* attach a criterion to each — a mechanism per class, a duration per
  surface, a sentence template or max length for the purpose line, "inside the
  same `<section>` element" for note adjacency, and a stated tint relationship
  between hover and selected.
- **medium** **No alignment inventory, so no issue can inherit a bounded scope.**
  The spec says alignment "is cut as Sprint 5 stories, never done
  opportunistically" and names the deviating classes for selected-state (nine of
  them) and the drift families in the log — but nowhere partitions call sites into
  story boundaries. Under the repo's issue convention (issues are pointers; the
  spec carries the criteria), an issue pointing at DR16 inherits "every selectable
  control in the app" and an issue pointing at DR19 inherits "one date input,
  three selects, three `<details>`, one checkbox" without knowing which files.
  *Fix:* add a per-family alignment table — canonical component | deviating call
  sites (by selector and module) | suggested story boundary. This is the single
  highest-leverage change for cuttability in the whole document.
- **medium** **The six explanatory paragraphs are counted but never enumerated.**
  Both files state that six free-standing paragraphs sit across six screens and
  that DR11 resolves each to one of four outcomes (tooltip / data note / basis
  line / deletion). Neither lists them. The Lane A mandate names four of them
  specifically — the performance-chart footnotes (TTWROR explanation, date range,
  composition-as-of-today) and the income EUR-hub note. Without the enumeration,
  no issue can be cut, no reviewer can verify completion, and the one concrete
  case the spec does name (TTWROR existing as both tooltip and paragraph) is the
  only one anyone will fix. *Fix:* add a table — paragraph | file:region | DR11
  outcome — as the acceptance criteria a thin issue points at.

---

## 10. Sprint 4 Lane A mandate coverage

The mandate (`implementation-artifacts/sprint-plan-2026-08-05.md`, "Lane A") says
"covering at minimum". Checked item by item.

| Mandate item | Status |
|---|---|
| Loading: skeleton states | **covered** — typographic skeleton, the `.section-skeleton` reduced-motion defect, and the gating rule |
| Loading: count-up pattern with visible "still counting" | **covered, well** — DR20 + settling anatomy + the hook ruling |
| Loading: progressive sunburst fill | **covered** — sequential clockwise sweep, with its cost stated and the legend constraint |
| Loading: replace "Lädt …" text and bare dot placeholders | **gap** — the bare `…` is retired; the six loading verb strings are named as drift with no replacement, and the "recomputing cue" that would replace them is undefined (§4) |
| Nav/controls: assets-view tabs sharing the icon-menu language | **covered** — DR16 two-idiom ruling (the icon inventory itself is a known `[OPEN]`) |
| Nav/controls: period selector | **covered** — one vocabulary, one appearance (subsets are a known `[OPEN]`) |
| Nav/controls: date picker | **covered** — DR19 + `components.native-control`, ISO in input |
| Hint prose → ⓘ tooltips (chart footnotes, income EUR-hub note) | **gap** — the rule is strong, the instances are not enumerated (§9) |
| "Chart as table": keep, de-emphasize, make purpose evident | **covered as a rule, unverifiable as a criterion** — "quiet text control" plus an `[OPEN]` label plus an unbounded purpose line |
| Contra-account value-setting UI | **covered but mis-sited** — the rule points at the wrong surface (Mechanical notes) |
| Snapshots makeover | **covered, well** — comparison-as-surface, shared chart component, list secondary, form disclosed |
| Income: bars per month/quarter/year | **thin** — one clause in an IA prose paragraph; no Component Patterns row, no DESIGN.md anatomy |
| Income: accumulated-per-month series | **thin** — same clause, no spec |
| Income: closed trades / deposits & withdrawals / costs | **thin** — named as tabs with a purpose sentence, no read, no states, no chart spec, and the strongest instruction in the document ("must not ship as empty shells") has nothing to ship instead |
| Income: per-instrument breakdown (open design question) | **gap** — decided (I2, stacked bars + "Sonstige"), absent from both spines (§5) |
| Income: explicit labeling of what "income" aggregates | **gap** — the spec records that the engine filters to `dividend` and `interest`, but no rule requires the *surface* to state its aggregate. The mandate asks for the label, not the fact |
| Tax view as MCP-first review surface, no document intake | **covered, well** |
| Overview "needs attention" card naming view + plan | **behaviorally covered, visually unspecified** (§3) |

Net: four outright gaps (loading-text replacement, hint-prose enumeration,
per-instrument income, income aggregate labelling), one mis-sited item, and the
Cash-flow tab set specified at a depth well below the rest of the document.

---

## Mechanical notes

Claims spot-checked against the build. **Verified accurate:** `.stat strong {
color: var(--color-accent) }` sign-blind at `app.css:983-990`; `--color-warning-soft`
declared only in `:root` (41) and never for dark; the 4px scale at 51-58 and the
heading ramp at 60-65; `.detail-section-title` off-ramp at 2727 (13px/600
uppercase); `nav_current?/2` omitting `/snapshots`; `.section-skeleton` at
4426-4437 animating `1.6s … infinite` with no reduced-motion gate while four other
animations carry one; income's three `<table>`s with no scroller wrapper and no
`min-width: 0`; no generic `.num` rule while `income_live.ex` uses `class="num"`
20 times; five `…` and one `—` bold at value size on the KPI row (721, 741, 749,
760, 773, 774); six illegitimate `--color-accent-violet` uses at the five cited
lines (line 720 is the accent-picker swatch and is correctly excluded);
`wealth_tabs/1`'s built set; eight hooks; two function components. The survey work
behind this refresh was real.

Contradicted by the build:

- **high — `--color-selected` does not re-key with the accent, and the frontmatter
  says it does.** The comment reads "alias of the ACTIVE accent-*-soft — violet
  default shown; re-keys with `[data-accent]`". In the build it is a literal
  `#ede9fe` declared in `:root` (30), the dark media query (93) and both
  `[data-theme]` blocks (124, 154), and **never inside a `[data-accent]` block** —
  those set only `--color-accent` and `--color-accent-soft` (165-177). Eight call
  sites consume it, including the selected-row treatment `{components.selected-row}`
  mandates. Under teal or coral, every selected row in the app stays violet. This
  is a seventh hard-coded-violet violation, structurally worse than the six listed,
  and the Violations section misses it while the frontmatter asserts the opposite.
  *Fix:* correct the comment to describe the token as built; add it to the
  Violations list with the correction (`--color-selected: var(--color-accent-soft)`
  inside each `[data-accent]` block, or drop the token for `{colors.accent-soft}`
  at the call sites); re-check `selected-dark` the same way.
- **high — the chart-as-table census is wrong, and the amendment that follows omits
  a surface.** Both files state "three chart surfaces carry it with three different
  summary labels and two (the sunburst, the securities detail chart) carry none".
  Verified: exactly **two** disclosures exist — `portfolio_live.ex:1709` ("Show
  data as table") and `snapshots_live.ex:489` ("Data as table") — so **two**
  labels; and **three** chart surfaces lack one: the sunburst, the securities
  detail chart, **and the income bar chart** (`income_live.ex` contains no
  `<summary>` at all). DR10 says "a chart shipped without its table is a review
  reject" and names which surfaces must gain it — omitting the one surface Lane B
  is fixing this sprint. The error originates in `.decision-log.md`'s survey table
  ("on 3 of 5 chart surfaces, 3 different summary labels") and was inherited
  unverified into three places. *Fix:* correct the count in DESIGN.md "Data as
  table — one disclosure", the Chart-data-table row, and DR10; add income.
- **medium — the cash-balance rule is attached to the wrong surface.** Component
  Patterns: "Cash accounts | **Accounts & depots** | Setting a balance lives in the
  account row. The global balance form is retired". DESIGN.md Forms repeats it. The
  form being retired is on **Wealth — Holdings** (`portfolio_live.ex:1510`,
  `.inline-form.balance-form`, with a bare `type="date"` at 1521, i.e. one of the
  four DR19 counts); `portfolio_accounts_live.ex` — the Accounts & depots surface —
  has no balance concept at all, so "each row carries its own set-balance action"
  there is new read *and* write surface, not a relocation. The Lane A mandate names
  this item precisely ("the contra-account value-setting UI **under the chart**").
  A story cut from this row edits the wrong LiveView. *Fix:* name the current
  location, the surface that loses it, the surface that gains it, and the balance
  data Accounts & depots does not currently load.
- **medium — undefined-token claim is undercounted and half false.** DESIGN.md:
  "Three tokens are referenced but never defined: `--color-border-subtle` (3649,
  4285, 4337), `--color-surface-hover` (3652), `--color-surface` (2135). **Each
  falls back to a hard-coded translucent grey that follows neither theme.**"
  Verified: `--color-surface` is referenced at **2135, 2208, 3066, 3396, 3681** and
  falls back to `var(--color-bg)` — a real theme token, so the clause is false for
  it; `--color-surface-hover` at **3652, 3884, 4174, 4183** with three *different*
  grey values (0.08 / 0.14 / 0.12), a separate inconsistency the spec does not
  name. *Fix:* correct the citation lists and split the claim in two.
- **medium — line-number citations have already drifted.** `.workspace-page {
  overflow-x: clip }` is at **3935**, cited as 3934 in both files. The plural bug is
  cited as `portfolio_live.ex:1607, 1612, 1619, 1641` (four); the actual `gettext`
  + `%{count}` calls are at **1608, 1613, 1620, 1634, 1642** — five, every cited
  line off by one, and 1634 (`"%{count} cash account(s)"`, the manual "(s)"
  workaround) uncounted. `ngettext` appears zero times in the file. In a document
  that will be cited for months, every line number is a reviewer instruction that
  goes silently wrong on the next edit. *Fix:* cite by selector, function name or
  `data-role` (`.workspace-page`, `nav_current?/2`, `data-role="dq-negative-holdings"`)
  and keep line numbers only in the dated drift register proposed in §6.
- **low — the focus-outline census is wrong in both directions.** DESIGN.md: "five
  `:focus-visible` rules set `outline: none`" naming `.nav-link`, `.accent-choice`,
  `.locale-link`, `.row-actions__kebab`, `.theme-choice`. Verified: **six** do —
  `.nav-link` (402), `.accent-menu-trigger` (627), `.accent-choice` (680),
  `.locale-link` (758), `.row-actions__kebab` (2126), `.row-context-menu__item`
  (2163) — so `.accent-menu-trigger` and `.row-context-menu__item` are missed and
  `.theme-choice` is named but does not (673-674 sets no outline). Two further
  `outline: none` rules apply *unconditionally*, not only on `:focus-visible`:
  `.search-field input` (1393) and `.securities-detail-splitter` (2057) — strictly
  worse, and the splitter is keyboard-operable. *Fix:* correct the list and add the
  two unconditional cases as their own violation line.

Frontmatter completeness: `name`, `description`, `colors`, `typography`,
`rounded`, `spacing`, `components` all present and well-formed; the
`rgb()`-with-alpha deviation is declared, which is the right handling. No Mermaid
diagrams in either file. EXPERIENCE.md's `sources` list resolves — all ten paths
exist.
