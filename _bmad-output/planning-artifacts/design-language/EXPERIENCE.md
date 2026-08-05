---
title: Portfolixir EXPERIENCE.md
status: final
created: 2026-06-12
updated: 2026-08-05
name: Portfolixir
sources:
  - _bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md
  - _bmad-output/planning-artifacts/design-language/.decision-log.md
  - _bmad-output/planning-artifacts/epics.md
  - docs/decisions/0022-task-oriented-information-architecture.md
  - docs/decisions/0024-buckets-and-views-replace-portfolios-in-the-ui.md
  - docs/decisions/0038-continuous-feedback-and-design-authority.md
  - priv/static/app.css
  - lib/portfolixir_web/router.ex
  - lib/portfolixir_web/components/app_shell.ex
  - lib/portfolixir_web/components/security_chart.ex
---

# Portfolixir — Experience Spine

> Paradigm (binding): **classic but decluttered.** Managing data stays a first-class UI task; clutter is fought with progressive disclosure, not by hiding the work. The visualization-only vision was considered and rejected. No agent-oversight UI: MCP writes are the operator's own commands executed faster.

> **Authority (ADR-0038).** This document plus `DESIGN.md` is the living design-language spec. Design work and the design-critic review of the agentic review closing act are held against it. It wins over mockups, over `epics.md`'s UX-DR summaries, and over anything built. Where the built UI contradicts it, that is a finding, not a precedent.
>
> **Closing pass, 2026-08-05.** The open items below are closed. The owner delegated these calls to the designer, so each is marked **decided 2026-08-05 (designer)** where it lands, and each records the evidence — a route table, a context function, a `periods/0` list — rather than a preference:
>
> - **UX-DR4** — closed: route-by-route reachability pass done against `router.ex` and `app_shell.ex`; the rule is rewritten to the question it should have asked, and the Cash-flow parent gets `/cashflow` as a Wealth tab.
> - **UX-DR17** — closed: `:asterisk` / `:alert_triangle` / `:alert_octagon`, all three additions to the icon set (`DESIGN.md` → Data note, with the reasoning and the funnel-collision ruling).
> - **Period control** — closed: per-surface subsets declared below, each derived from the granularity the surface's own read produces.
> - **Voice and Tone** — closed: locale-pure per locale, with a narrow term-of-art carve-out; two shipped strings change.
> - **State Patterns → stale data** — closed: the backend field exists. `security_quotes.updated_at` (`Catalog.Quote`, `timestamps()`) is refreshed on every sync write; what is missing is a named read function, which is implementation, not an open design question.
>
> **Completion pass, 2026-08-05 (same session, after the rubric review).** Written here for the first time: UX-DR13 (indexed with no section behind it), the recomputing cue (named five times, defined nowhere), the LiveView connection states, the 2026-07-12 one-line data-quality decision, the per-surface state matrix, the Inspiration record, and the **Alignment inventory** — the deviating call sites per drift family, which is what lets a thin issue point at a rule and inherit a bounded work list. Six factual claims about the build were corrected against a direct count: the chart-as-table census, the cash-balance form's surface, the native-control counts, the loading-string count, the plural-bug call sites, and the component/hook census. `DESIGN.md` now names every rule number it carries, so the index's pointers resolve in both directions.
>
> **Accessibility pass, 2026-08-05 (same session, after `review-accessibility-2026-08-05.md`).** The refresh specified its new loading vocabulary in visual terms only — pending, settling, the sweep and the three severities had appearance and no programmatic contract. Closed here: the pending state's staleness contract (`aria-busy`, a real-text marker before the digits, and survival under forced colors), the reduced-motion behaviour of settling — where the two spines contradicted each other and this file was right — the reduced-motion form of the no-prior-value fallback, the data note's role policy, the coarse-pointer floor on the ten control classes that had none, and **UX-DR7 extended to the vocabulary the refresh added**, which is the structural cause of the critical finding. The danger-tint gate is decided in `DESIGN.md` and leaves this list.
>
> **Status: final (2026-08-05).** Every design question this session opened is decided. Two items below are **downstream work with owners, not open design decisions**; a design-critic review holds work to everything else in this file and treats those two as out of scope until their own work lands. `DESIGN.md` carries the visual half of the same statement.
>
> Two items that had been parked here are **decided rather than carried forward**, because both were designer calls rather than owner calls:
>
> - **The securities detail pane's tabs are second-level.** Same treatment as the Cash-flow facets: the tab control, smaller and iconless. The pane's tabs sit inside a surface the first-level tabs already reached, which is the definition of second-level here; leaving it "by analogy" would have invited a fourth tab idiom on the one surface that already has three.
> - **Note-level tone is {colors.text-muted} on {colors.bg-muted}.** The quietest pairing the palette offers that still reads as a deliberate surface rather than as body text. A note states a modelling fact, so it must be legible without competing with the figure it qualifies.
>
> | Remaining follow-up | Where | Who closes it |
> |---|---|---|
> | Categorical colour is unreconciled — a closed token set, free-form per-category hex, and accent tints for stacked segments cannot all be true | IA → Per-instrument income; `DESIGN.md` → Category and series colour | Its own decision gate; it touches user-set data, not styling. Blocks the per-instrument income story and nothing else. |
> | The Overview data-quality line has no pre-filtered URL to link to — `securities_live.ex` `handle_params/3` reads only `tab` and `id` | UX-DR2 | URL-addressable filter params on `/securities` (issue #651). The line ships without the link until then; it states the count, which is the part that carries the information. |

## Foundation

Responsive web, three target surfaces: desktop browser (primary analysis seat), iPad, iPhone. One operator (**Andi**, PRD §2) running several **scopes** in one instance, separated by views rather than by separate installations (ADR-0024) — one persona, many view scopes, single-user self-hosted instance. The LLM agent is the second first-class user, but it consumes the JSON API/MCP, not this surface.

**No UI system.** Server-rendered Phoenix LiveView (1.2.8) with hand-written CSS in `priv/static/app.css` — no Tailwind, no JS bundler, no CoreComponents. Five function-component modules ship (`components/app_shell`, `components/security_chart`, `components/view_switcher`, plus `live/securities/logo_override_dialog` and `live/securities/row_context_menu`), five LiveComponents (`column_picker`, `filter_popover`, `security_form_dialog`, `split_wizard_dialog`, `account_form_dialog`), and eight small hand-written LiveView hooks, all eight defined in `layout_view.ex`. The full census is in `DESIGN.md` → Components.

`DESIGN.md` is the visual identity reference. **Colours, type roles, radii, spacing steps, breakpoints, target sizes and shadows in this spine are `{path.to.token}` references into it**; durations, debounce intervals and counts are stated here as literals because `DESIGN.md` does not tokenise time or cardinality. A colour or pixel literal in this file is drift.

**States that do not apply, ruled rather than omitted.** Portfolixir is a single-user, self-hosted instance with no accounts and no roles, so **permission-denied** is not a state this spec carries. It runs against a local server over a persistent socket, so **offline** is not modelled as a client-side condition either — the equivalent failure is a dropped LiveView socket, which *is* specified (State Patterns → connection). Their absence elsewhere is a ruling, not an oversight.

Dark/light/system theme and the three logo-derived accent variants ({colors.accent-violet} / {colors.accent-teal} / {colors.accent-coral}) are shipped, owner-loved, and preserved as the identity anchor.

**Coherence posture (2026-08-05 critique).** The system is coherent at token level and incoherent at component level: eleven recurring UI jobs have two to five independent solutions each. The spec's job from here is not new visual language but **one named solution per job**, with the deviating call sites recorded and aligned through dedicated stories — never opportunistically. The call sites are recorded in **Design Rules → Alignment inventory**; a story that cannot point at a row there is not an alignment story.

## Information Architecture

IA covers **every built route**. The unit matters, because three different numbers for this one fact were in circulation across three artifacts of one session; counted against `router.ex` on 2026-08-05: **14 `live/3` declarations**, resolving to **11 LiveView modules**, which this table cuts into **12 built surfaces** (a module with a tab query parameter yields more than one surface, and `/classifications`, `/classifications/new` and `/classifications/:id` are one). Four further rows are **specified, unbuilt** — 16 rows in total. The 2026-06-13 scope ("IST only — the current seven surfaces") is retired: three of the four surfaces it omitted are exactly what the 2026-08-05 feedback triage reports as broken, and a design critic cannot hold work against a spec that does not know the surface exists.

**Governing IA rule (ADR-0024, binding).** Navigation reflects **user tasks, not the storage model** — *sidebar = tasks, entities = attributes*. New entities do not get sidebar entries by default. Buckets are attributes on account rows; views are the task of scoping analytics; portfolios are an internal compatibility record and are not a navigation concept.

| Surface | Route | Reached from | Purpose | Status |
|---|---|---|---|---|
| Overview | `/` | App open, brand link | Analysis home: total value + change, "Needs attention", data quality | built |
| Wealth — Holdings | `/portfolio` | Sidebar "Wealth", tab | KPI band (total incl. cash, securities, cash + cash quote, TTWROR, IRR), performance chart, data quality, cash accounts | built |
| Wealth — Allocation & targets | `/portfolio?tab=allocation` | Wealth tab | Sunburst, SOLL/IST drift table, per-position drift with display-only corrective hints (ADR-0023) | built |
| Wealth — Cash flow | `/cashflow` *(decided 2026-08-05, unbuilt)* | Wealth tab | Parent of the four cash-flow facets below | **specified, unbuilt** |
| Cash flow — Income | `/cashflow` (default facet) | Cash flow tab | Dividends and interest already booked: year × month matrix, per-position table, per-year detail | built at `/income` today, which becomes a redirect |
| Cash flow — Realized gains | `/cashflow?tab=realized` | Cash flow tab | Closed trades | **specified, unbuilt** |
| Cash flow — Deposits & withdrawals | `/cashflow?tab=flows` | Cash flow tab | External flows in and out | **specified, unbuilt** |
| Cash flow — Costs | `/cashflow?tab=costs` | Cash flow tab | Fees and taxes, overview level only | **specified, unbuilt** |
| Wealth — Snapshots | `/snapshots` | Wealth tab | Frozen depot markers and the ADR-0027 counterfactual comparison | built |
| Wealth — Tax | `/tax` | Wealth tab | Recorded tax-statement snapshots, allowance-order budget, consistency findings (ADR-0031) | built |
| Securities | `/securities`, `/securities/:id` | Sidebar, table rows | Security list + split detail pane: price chart, trades, quotes, classification tabs | built |
| Transactions — History | `/transactions` | Sidebar, tab | Full ledger: record, review, filter | built |
| Transactions — Import | `/imports` | Transactions tab | PP export intake: drop zone → preview → idempotent apply | built |
| Accounts & depots | `/portfolios` | Sidebar (Administration) | Depots and cash accounts, bucket chips, balances | built |
| Views | `/buckets` | Sidebar (Administration) | Views (include/exclude filters over buckets), bucket CRUD, default assignment | built |
| Classifications | `/classifications`, `/classifications/new`, `/classifications/:id` | Sidebar (Administration, **one static entry**); per-tree links and `+` on the index | Allocation trees: categories, target weights, drag-and-drop assignment | built |

**Wealth tab set (decided 2026-08-05, replaces the built set).**

`Holdings · Allocation & targets · Cash flow · Snapshots · Tax`

The built set is `Holdings · Allocation & targets · Income · Snapshots · Tax` (`app_shell.ex` `wealth_tabs/1`). "Income" is promoted to **Cash flow** at `/cashflow` (route decided 2026-08-05, UX-DR4) and gains second-level tabs:

`Income · Realized gains · Deposits & withdrawals · Costs`

Rationale: three of the five owner-scoped analyses are not income at all — realized gains, external flows, and costs. Lumping them under one "Erträge" label reproduces exactly the Portfolio Performance ambiguity the owner complained about. The terminology problem is therefore answered by **structure**, not by a better label, which is also what the ADR-0024 rule demands.

**What has a read today** (corrected 2026-08-05 after the design-critic pass — an earlier draft of this section claimed only Income did, and that was wrong):

| Facet | Read | State |
|---|---|---|
| Income | `Portfolios.Income.for_portfolio/1` — filters to `dividend` and `interest` (`income.ex`) | shipped, has its own surface |
| Realized gains | `Ledger.TradeMatcher` already returns `:closed_trades` — realised round-trips with `realized_pnl_abs` / `realized_pnl_pct` per sell (`trade_matcher.ex:9, 48, 68, 229-258`) | **computed and exposed** via `/api/v1` (`trade_controller.ex`) and the Securities detail Trades tab; it has no cash-flow surface |
| Deposits & withdrawals | none — external flows are derivable from the ledger's deposit/removal kinds but no read exists | unbuilt |
| Costs | none — fee and tax legs exist per transaction; no aggregate read | unbuilt |

This matters for sizing: **Realized gains is a presentation story, not a computation story.** The matcher, the API and the MCP tool already ship; what is missing is a cash-flow-shaped view over an existing read. Deposits & withdrawals and Costs are genuinely new reads, and Deposits & withdrawals overlaps #568's net invested capital — it belongs to the same story family rather than being built twice.

No facet ships as an empty shell: a second-level tab appears when its read exists.

**Every aggregate names what it aggregates (binding, 2026-08-05).** The structural fix above renames the *area*; it does not by itself tell a reader what any one number contains, and "income" is the word the owner named as ambiguous in the first place. So:

1. **Every Cash-flow facet states its own composition once, in its subtitle or basis line, in the operator's terms** — for Income: *dividends and interest*, the two kinds `Portfolios.Income` actually filters to (`income.ex`). Not "all payouts", not "Erträge", not left to the tab label.
2. **Every aggregated figure inside a facet repeats the composition where it could be read alone** — a chart's `aria-label`, a total column header, a contributor list heading. "Total income per year" (`income_live.ex:114`) does not say what income is and is read in isolation by exactly the users who cannot see the subtitle; "Dividends and interest per year" does.
3. **Two kinds in one bar is a stack, not a sum, wherever both are non-zero.** The year × month matrix already splits dividends from interest into two rows; the chart above it silently sums them (`income_bars/1`, `month_bars/2`). Either the bars carry the same split, or the label states that they are the sum — the table and the chart must not disagree about what the number is.
4. **What is *not* in the aggregate is stated where the omission could mislead.** Income excludes realised gains, deposits and costs — which is the whole reason those are separate facets — and the Income surface says so once rather than letting the reader infer it from the tab row.

This is the missing half of the Cash-flow decision: structure answers "which analysis am I looking at", labelling answers "what is in this number".

Scope carried in from the owner's PP walkthrough (2026-08-05): bars per month/quarter/year and an accumulated-per-month series belong to Income; closed trades to Realized gains; external flows to Deposits & withdrawals; taxes and fees to Costs **at overview level only** — no per-transaction cost ledger.

### Per-instrument income (decided 2026-08-05, owner: stacked bars with an aggregated remainder)

The Income facet's period bars may be **segmented by instrument**: the largest contributors individually, everything else aggregated into one remainder segment. It answers "who contributes how much, over time", which the flat top-contributors list cannot.

**Segment count is capped at three plus the remainder, not six** — a designer's correction to the owner's pick, made because the pick as stated is not buildable under this spec's own rules, and flagged here rather than silently applied:

- The project renders **one accent at a time**, and using the three brand accents together outside the `.stat` top bar is forbidden. Seven segments would therefore have to come from tints of a single accent, which puts roughly 1.3:1 between neighbouring segments — below the 3:1 non-text floor, so adjacent contributors would be indistinguishable.
- UX-DR7 forbids hue as the sole channel regardless. Segments must be separable without colour, which means **direct labelling on the segment where it fits and in the legend where it does not** — and direct labels only fit at low segment counts.

So: **three named contributors plus "Sonstige"**, each directly labelled, with the full per-instrument breakdown in the table beneath (UX-DR10). If the owner wants six named contributors, the honest route is small multiples — one small chart per instrument — not more segments in one bar.

**Unresolved tension this exposes, recorded not resolved.** Three positions on categorical colour coexist in the project and contradict each other:

1. `DESIGN.md` describes a closed token set with one accent active at a time.
2. The build lets a user pick **any** hex per category (`category.ex:15`, `~r/^#[0-9a-fA-F]{6}$/`) and renders it straight into the sunburst (`portfolio_live.ex:1804`).
3. This session decided accent tints for stacked segments.

These cannot all be true. Reconciling them is a decision gate of its own — it touches user-set data, not just styling — and is explicitly **not** settled here.

**Seams in the built IA (recorded, not endorsed):**

- `/buckets` is labelled **"Views"** in the sidebar. This is deliberate (ADR-0024 modification 6 — the task is view scoping; buckets are attributes reached from account chips and the view editor), but route and label diverge. Anyone reading the router will not find the surface by its label.
- `nav_current?/2` in `app_shell.ex` covers `/income` and `/tax` under the Wealth section but **omits `/snapshots`** — on the Snapshots surface no sidebar item is marked current and no `aria-current="page"` is emitted. This is a **defect**, not a design choice; it ships as a fix, not as a spec change.
- The funnel icon means "Views" in the sidebar and "filter" in the securities toolbar. One glyph, two meanings — **resolved 2026-08-05 (designer):** the funnel keeps "filter"; the Views entry takes `:bookmark` (UX-DR16, anatomy in `DESIGN.md`).
- **The Classifications nav group is one static entry, not one per tree** (`app_shell.ex:266-294`). Earlier drafts of this table and of `DESIGN.md`'s inventory claimed a dynamic per-tree group; the build is the honest reading of ADR-0024 (a tree is an entity, not a task), so the documents follow the build. The per-tree list is on `/classifications`.

### Visual references

Two locations, one rule. **The spines win on conflict** — everything below illustrates, none of it specifies. This clause is stated here and nowhere else.

`mockups/` holds composition references rendered on 2026-06-13:

| File | What it illustrates | Standing |
|---|---|---|
| [mockups/key-dashboard.html](mockups/key-dashboard.html) | The Overview as the superseded UX-DR2 specified it: hero + four fixed metric cards + decluttered sidebar | **Stale.** UX-DR2 now follows the build and `{components.hero}` is retired. Re-render or retire before reuse. |
| [mockups/key-classifications.html](mockups/key-classifications.html) | The Classifications tree as the surface: category rows with swatches and counts, permanent search, the New-category form collapsed behind `+` | **Stale in part.** Its subject — the tree-as-surface and the disclosed form — still stands and is UX-DR1's exemplar. It predates UX-DR16 (selected-row), UX-DR18 (width-reserved rows) and UX-DR19 (`<details>` nodes, the checkbox that feeds the multiselect toolbar), all of which land on exactly this surface, so its *control* rendering is superseded and its *composition* is not. |

`.working/` holds decision playgrounds — rendered to choose between options, kept as the provenance of the choice, never a build target:

| File | What it illustrates | Outcome |
|---|---|---|
| [.working/loading-affordances.html](.working/loading-affordances.html) | Pending P1 (typographic skeleton) / **P2** (last known dimmed) / P3 (progressive reveal); settling **S1** (underline bar) / S2 (shimmer) / S3 (marker); sunburst fill **F1** (sequential) / F2 (rings inward-out) / F3 (fade-in-place) | Owner picked **P2 + S1 + F1**. A first typed pick of P1 + S3 + F3 was corrected in session; recorded so the superseded combination is not later mistaken for a parallel option. P2's cue markup is the provenance of `{components.recomputing-cue}`. |
| [.working/income-per-instrument.html](.working/income-per-instrument.html) | I1 sparkline column / **I2** stacked segments / I3 instrument filter / I4 keep top-contributors only | Owner picked **I2**. Segment count corrected from six to three plus a remainder — see Per-instrument income below. |

**Navigation model (binding: keep current behavior on all form factors).** Desktop: fixed left sidebar ({spacing.sidebar-width}) with grouped, labeled links; a toggle collapses it to an icon rail ({spacing.sidebar-rail}). Below 900px the same sidebar becomes an off-canvas overlay slid in over a backdrop via the top-bar burger; no bottom tab bar is introduced. The sticky top bar carries page title/subtitle, theme menu, accent menu, and the EN/DE locale switcher on every form factor.

**Progressive-disclosure principle (the core decluttering move).** Reading is the default posture of every surface; creating and editing are one intent away, never zero. Creation and edit forms move out of the primary sightline into modals, popovers, or collapsed sections opened by an explicit affordance (`+`, "Edit", kebab). Summary first, drill-down second, filters and forms third. Analytics density is wanted — decluttering happens through hierarchy and disclosure, not through hiding numbers.

**Classifications remains the exemplar.** The tree itself is the surface: search stays (it serves reading), the New-category form collapses behind the `+` affordance, the multiselect toolbar appears only when a selection exists, edit/recolor/delete live on the node. The same treatment generalizes to every surface that still holds an `.inline-form` in primary sightline.

[ASSUMPTION] Owner desire, tentative: the Overview's metric cards become self-configurable. This spine keeps the layout future-friendly — cards are a flat, reorderable collection, no card depends on a sibling — and specifies **no** configuration mechanics.

## Voice and Tone

Microcopy is **explanatory** (binding): the UI translates domain terms instead of assuming them. de/en via the existing gettext infrastructure; both locales ship together.

- Domain metrics carry a focusable ⓘ definition: TTWROR, IRR, SOLL/IST drift, cash quote. One sentence, plain language, method named.
- Numbers state their basis where it is cheap: as-of date, currency, gross/net, and — for scoped figures — the view. The agent gets this via self-describing MCP responses (FR-13); the human gets the same honesty inline.
- **An aggregate names what it aggregates.** A label that is a category word — "income", "costs", "flows" — carries its composition on first use per surface and in any string read in isolation (a chart `aria-label`, a total header). The full rule, with the Income instances, is in IA → *Every aggregate names what it aggregates*.
- **Impersonal voice (owner rule 2026-07-23, binding).** UI and doc text states the fact, the state, and the consequence without addressing the reader — "Mapping required", not "you must map". Where address is genuinely unavoidable: du, never Sie. Imperative labels without personal pronouns are fine. Warnings are a statement of fact plus the remedy. Second-person address and tutorial filler in user-facing strings are review-blocking findings.
- **Prose is not the fallback for what the design did not solve (2026-08-05 finding, binding).** Free-standing explanatory paragraphs sit across six screens; **twelve are enumerated** in the Alignment inventory → UX-DR11, each with its file, region and resolved outcome. The worst case: the TTWROR explanation exists **simultaneously** as an ⓘ tooltip (`portfolio_live.ex:762`) and as a permanent paragraph (`:912-919`) on the same screen. `tax_live.ex`'s own moduledoc claims the tooltip rule while the template breaks it four times. UX-DR11 is not occasionally missed — prose is the habit. Every candidate paragraph resolves to exactly one of: a tooltip (a definition), a data note (a fact about this data — see UX-DR17), a basis line (where a number comes from), or deletion. A paragraph that is none of these is a design gap wearing text.

| Do | Don't |
|---|---|
| "TTWROR (time-weighted return) — ⓘ" | Bare acronyms with no help |
| "As of 12 Jun 2026, EUR, view: Everything" | Numbers with unstated basis |
| "Import previewed: 42 transactions would be created." | "Import successful!" before anything happened |
| "Nothing here yet — import a PP export or record a transaction." | "No data." |
| One explanation, in one place, in one form | The same explanation as tooltip *and* paragraph |
| Calm, complete sentences; no exclamation marks | Coaching, gamification, celebration |

**Bilingual domain labels — decided 2026-08-05 (designer's call, owner-delegated): locale-pure per locale, with one carve-out.**

`classifications_live.ex:514` and `:1196` render the gettext'd msgid **"Gesamt (total)"** — a deliberate bilingual domain label, not an untranslated leak (verified; an earlier critique misreported it as a bug). The rule that resolves it and its relatives:

1. **A source string is English; its German translation is German.** No string carries both languages. gettext already does per-locale wording, so a bilingual msgid duplicates the mechanism and, worse, makes the German UI say "Gesamt (total)" — glossing a term the German reader is fluent in. The gloss lands in the locale that needs it, or nowhere.
2. **Carve-out — a German legal or tax term of art with no English equivalent stays German in both locales.** Freistellungsauftrag and Verlustverrechnungstopf name specific constructs of German tax law; translating them invents terminology the operator will never see on a broker statement. In the German string it stands alone; in the English string it may carry a one-time parenthetical gloss on first use per surface — *English gloss for a German term*, never the reverse.
3. **A domain abbreviation whose expansion is plain (SOLL/IST) is translated, not kept.** English "Target"/"Actual", German "SOLL"/"IST".

This is the majority practice already, which is the main argument for it: the drift table renders `gettext("Target")` / `gettext("Actual")` / `gettext("Drift")` (`portfolio_live.ex:1071-1079`), and the loss pots are msgid "Loss pot, equities" / "Loss pot, other" with German "Verlustverrechnungstopf Aktien" / "…Sonstige" (`tax_live.ex:217-218`). SOLL and IST appear nowhere in a user-facing string — only in moduledocs and code comments, where they stay.

**Strings that change** (the two outliers, both verified):

| Where | Today | Becomes |
|---|---|---|
| `classifications_live.ex:514`, `:1196` | msgid `"Gesamt (total)"`, de `"Gesamt"` | msgid `"Total"`, de `"Gesamt"` |
| `tax_live.ex:497` | msgid `"Configured Freistellungsaufträge"`, de `"Hinterlegte Freistellungsaufträge"` | msgid `"Configured allowance orders"`, de unchanged — matching the already-English `tax_live.ex:264` string, and carrying the German term where it belongs |

**Data-note labels — decided 2026-08-05 (designer). One word per severity, app-wide:** source `"Note"` · `"Attention"` · `"Problem"`, German `"Hinweis"` · `"Achtung"` · `"Problem"`. Nouns, not instructions: the word labels the finding, and the remedy is the control next to it, so the label never has to address the reader. They are the severity names of UX-DR17 verbatim, so spec, code and UI use one vocabulary. ("Achtung" over an imperative "Prüfen" is a judgement call — it states a condition, matching the impersonal rule.)

**The chart data-as-table disclosure — decided 2026-08-05 (designer): "Data as table"** (de: "Daten als Tabelle"), one wording under every chart. It names the thing instead of instructing ("Show data as table", `portfolio_live.ex:1709`, changes; `snapshots_live.ex:489` already reads this way). The purpose line beneath it carries the why.

## Component Patterns

Behavioral. Visual anatomy lives in `DESIGN.md.Components`.

| Component | Use | Behavioral rules |
|---|---|---|
| App shell | Every surface | Sidebar state (expanded/rail/off-canvas) is a pure CSS toggle; survives navigation. The toggle is a real `<input type="checkbox">` with a state-neutral accessible name; the off-canvas variant closes on `Esc` and backdrop tap, returning focus to the burger. Active link tracks `current_path` per section prefix — **every built route must map to exactly one section** (see the `/snapshots` defect, and UX-DR4 for the full reachability pass). The Classifications entry is one static link; the tree list lives on its index. |
| Tab system | Wealth, Transactions, Securities detail pane | **One icon vocabulary, shared with the navigation; two idioms.** The sidebar answers "where am I" and keeps pill plus marker dot. Tabs answer "which facet": icon + label + underline. **Second-level tabs** (inside Cash flow) use the same tabs **smaller and without icons**, so nesting is legible without a third idiom — but "smaller" is bounded: the label stays at {typography.control-label} and both levels take {spacing.touch-target} under `pointer: coarse` (UX-DR6). Note for the story that builds it: icons are `aria-hidden` throughout `app_shell.ex`, so "first level has icons, second level does not" is a *sighted-only* level cue and the nesting needs a structural carrier as well. That is a separate finding (H5 of the 2026-08-05 accessibility review) and is left to its own pass rather than solved here. [ASSUMPTION] The securities detail pane's tabs are second-level by the same logic and adopt the same treatment; the decision log names only Cash flow. Tabs are plain links so switching works without JS. Three tab languages exist today (sidebar pills, `.area-tab` links, `.detail-pane-tab` buttons) — two of them are drift and align to this pattern. |
| Period control | Every time-series surface | **One token vocabulary, one appearance:** `1M 3M 6M YTD 1Y 3Y 5Y Max`. Each surface **declares which tokens it offers**; a surface never invents a token outside the set and never reorders it. "Custom range…" is a **disclosure**, not permanent chrome, and its two date fields follow UX-DR19 (ISO, styled). Selected state is the segmented-group class of UX-DR16. Retires the four current patterns, the two divergent range-token sets (`Performance.periods()` = `ytd 1y 3y 5y max`; `securities_live.ex:35` `@ranges` = `1M 3M 6M YTD 1Y 3Y 5Y MAX` — only the `MAX` casing changes), and the four bare `type="date"` inputs **inside period controls** (`portfolio_live.ex:853`/`:860`, `securities_live.ex:534`/`:541`). The app has eleven date inputs in total; the other seven are UX-DR19 work. Per-surface subsets are declared below the table (decided 2026-08-05). |
| Data note | Anywhere the UI says something about the data | **One component, three severities: note / attention / problem** — distinguished by **colour AND icon AND word**, never colour alone (UX-DR7). The word is DOM text and the icon is `aria-hidden`; politeness is per region, not per note, and `role="alert"` is reserved for a note that answers an action just taken — full contract in UX-DR17. Severity is a property of the finding, not of the surface: "valued at last trade price" is a *note*; "impossible negative holding quantity" is a *problem*; a stale allowance-order budget is *attention*. Replaces the four competing treatments in use (plain bullet list, amber inline highlight, unstyled grey prose, accent bordered banner). Placement is adjacent to the data it describes — a remedy button ~1100px below the bullet naming the problem is a violation. |
| Stat / metric card | Overview, Wealth KPI band | `.stat` anatomy: uppercase label, big value, optional ⓘ. Click/tap navigates to the owning surface. Negative amounts follow money semantics ({colors.danger} + explicit sign), never the accent — the built Wealth KPI cards violate this today. Absence and pending are distinct (see State Patterns). |
| "Needs attention" card | Overview | Anatomy: `{components.needs-attention-card}`. States its **basis** in a line under the heading: which view, which plan, and the drift threshold the count is computed from. Where an allocation carries several plans, the card says so explicitly rather than silently picking one. Works without active-plan semantics (gated at E16/ADR-0027) and improves silently once they exist. At most five rows, worst drift first, each row a link into Wealth — Allocation & targets. Rows carry the direction word as well as the sign and the colour (UX-DR7). The empty case is one muted line, no badge — an all-clear is not a finding. **Built state:** the threshold clause of the basis line ships (`dashboard_live.ex`, `data-role="attention-explainer"`); the view and the plan do not. |
| Data quality — Overview | Overview | Anatomy: `{components.data-quality-line}`. **One line, rendered only when N > 0, no green all-clear badge, linking to a pre-filtered securities list** — the 2026-07-12 decision, adopted unchanged 2026-08-05 (see UX-DR2). The line is a `{components.data-note}` at the highest severity present. **Built state contradicts every clause:** three `.stat` cards in a grid, rendered unconditionally, all three linking to an unfiltered `/securities`. **One clause is blocked, not merely unbuilt:** `securities_live.ex` `handle_params/3` reads only `tab` and `id`, so there is no URL-addressable filter to link to; the implementing story carries filter params or states the shortfall. |
| Data quality — Wealth | Wealth — Holdings | One `{components.data-note}` per finding at the finding's own severity, each with its remedy inside the note. Six conditions render there today as identical `<li>` bullets under a bare `<h2>` (`portfolio_live.ex`, `#portfolio-data-quality`); severity per condition is in the Alignment inventory → UX-DR17. This is a different component from the Overview line above and the two do not converge. |
| Value slot | Every rendered money, percentage or quantity | Anatomy: `{components.value-slot}`. Four states, four appearances, one reserved footprint (UX-DR20) — and, for pending, one **programmatic** state and one **textual** staleness marker, because a dimmed number that reads as current is worse than the `…` it replaces (State Patterns → the staleness contract). Behaviour is in State Patterns; the point of the row is that the slot is a component and not a formatting convention — a surface that renders an absent value its own way is drift, and three such renderings coexist today. |
| Native controls | Every date input, select, `<details>`, checkbox | Anatomy: `{components.native-control}`. Behaviour: the label is the hit target and sits on the same line as its control; `<details>` keeps native disclosure semantics and never gains `role="menu"`; a date input accepts and displays ISO. UX-DR19 carries the rule and the Alignment inventory carries the 78 call sites. |
| Inline result | Every action with feedback | Anatomy: `{components.inline-result}`. Renders next to its trigger, inside the same `<section>`, reusing the data-note severities. **Persists until the next action on that control, a navigation, or an explicit dismiss — never a timer.** The 4.5-second `AutoDismissToast` is the behaviour issue #566 retires, not a pattern to reimplement inline. Announced `role="status"` for note and attention, `role="alert"` for problem, from a region that exists before the action runs. |
| Chart | Wealth, Securities detail, Snapshots, Cash flow | The shared `security_chart` component is the only chart implementation; the **four** hand-rolled SVGs are drift and migrate to it — the allocation sunburst, the snapshot two-polyline comparison, and the Income surface's *two* bar charts (annual and per-month), which are separate implementations of the same idiom. Server-rendered SVG; LiveView re-renders on range/log/percent toggle — toggles show a busy state and expose state via `aria-pressed`. Crosshair + mono tooltip on pointer; touch keeps pan-y and taps the nearest point. Build-in animation plays once per data change, never on crosshair moves. Empty states are gettext'd (`SecurityChart`'s hard-coded English empty state is a defect). |
| Chart data table | Under every chart **rendering**, not every surface | **One uniform disclosure: one control, one label, one styling, plus a stated purpose of at most one sentence.** Rendered as a quiet text control, not the raw browser triangle. The purpose line makes visible why it exists — it is the accessibility fallback UX-DR10 depends on and what makes 9px axis type and a single `aria-label` acceptable. **Census corrected 2026-08-05 (see UX-DR10):** six chart renderings across five surfaces; **two** disclosures and therefore **two** labels, not three; **four** renderings carry none — the sunburst, the securities detail chart, and both income bar charts. The unit is the rendering: the income surface needs two, one per chart. |
| Allocation visuals | Wealth — Allocation & targets | Donut/sunburst segments and legends are read-only in this run; the drift table follows the Tables row. Over/underweight carries sign or arrow, never hue alone. |
| Tables | Transactions, Securities, drift, holdings, income matrix | Read-first: rows are targets (click → detail/select), hover wash, kebab menu for row actions (bottom sheet < 720px). Sort/filter/column controls live in popovers off the toolbar, never inline. Row selection uses the tinted-row class of UX-DR16. Every table establishes its own horizontal scroller (UX-DR15). Column widths do not change with selection (UX-DR18). |
| Cash accounts | **From** Wealth — Holdings **to** Accounts & depots | **Setting a balance moves into the account row.** The form being retired is `form.inline-form.balance-form` on **Wealth — Holdings** (`portfolio_live.ex:1509-1531`) — a `<select>` re-picking the account (`:1513`), a bare `type="date"` (`:1521`, one of the eleven UX-DR19 date inputs), an amount field, and a `.hint` paragraph beneath it (`:1531`). The surface that gains the action is **Accounts & depots** (`portfolio_accounts_live.ex`), where each row opens a small dialog with the account already chosen. This is **not a relocation**: `portfolio_accounts_live.ex` has no balance concept at all today — it renders one accounts table (`:82`) with no balance column and loads no valuation — so the story adds read surface (a balance per row, and its as-of date) as well as write surface. Wealth — Holdings keeps its read-only `.cash-table` (`portfolio_live.ex:1488`) and loses only the form. Reading is the default posture; editing is one intent away, and the account is never re-picked in a form when the row already knows it. |
| Snapshots comparison | Wealth — Snapshots | **The comparison is the surface.** Plan against reality over time is the purpose, so the comparison goes primary and large, the snapshot list secondary beneath it, the create form behind a disclosure. Rendered with the shared chart component — inheriting its axes, crosshair and data-table disclosure, but **not** a period control: the domain is fixed by the snapshot's own as-of date (see the subset table above) — replacing the hand-rolled two-polyline SVG. The v1 gross/price-return-only limitation is stated as a data note, and excluded securities are listed as gaps. |
| Tax surface | Wealth — Tax | **A budget dashboard plus a check list.** Top: allowance-order utilization per institution as a visual fill level with the remaining amount and its as-of date. Below: the recorded statements as a list, each carrying its consistency finding as a **data note** at the right severity. Entry forms move behind a disclosure. The permanent prose paragraphs become ⓘ tooltips, basis lines or field help — **four**, enumerated with their outcomes in the Alignment inventory → UX-DR11 (`tax_live.ex:343`, `:355`, `:389`, `:502`). The surface already carries one correct ⓘ disclosure (`:368`), which is the pattern the four converge on. Pots render with the statement's printed sign (ADR-0031 §2); nothing here is derived from holdings and nothing here is tax advice. **MCP/LLM is the primary write path**; the UI is a visual review surface. Document intake stays rejected. |
| Forms behind disclosure | All create/edit | Default closed. Opened by explicit affordance (`+`, "Edit", kebab). One disclosure level at a time; `Esc`/cancel closes and returns focus to the trigger. Modals are real dialogs: native `<dialog>`/`showModal()` preferred (focus trap + `Esc` for free, fits the no-bundler constraint), else `role="dialog" aria-modal="true"` with a small focus-trap hook; focus moves to the first field or the dialog heading on open. **Neither branch is built** — see UX-DR9 (issue #646). Destructive actions confirm once, never twice. |
| Classification tree | Classifications | `<details>` nodes; drag-and-drop assignment with multi-select; toolbar appears only with an active selection. Row selection works without a pointer: each row carries a checkbox (`Space` toggles) feeding the same toolbar; on coarse pointers select+toolbar is the primary mechanism — drag is a desktop-only accelerator. Search filters live (150ms debounce) and auto-expands matches. Unsorted bucket pinned at the end. |
| Import pipeline | Transactions — Import | Drop zone → preview ("what would be created") → apply (idempotent, atomic) → done summary with gap flags (unclassified securities, missing logos, unknown kinds). Never silently defaults. Parse/validation failure ends at the preview stage; nothing is applied. |

### Period control — per-surface token subsets *(decided 2026-08-05, designer)*

One vocabulary, `1M 3M 6M YTD 1Y 3Y 5Y Max`, never reordered. Each surface offers the subset its own read can answer honestly; the subsets are derived from what the backing function produces, not from taste.

| Surface | Tokens offered | Grounded in |
|---|---|---|
| Wealth — Holdings | `YTD 1Y 3Y 5Y Max` | `Portfolios.Performance` `@periods ~w(ytd 1y 3y 5y max)` (`performance.ex:80`) — the shipped set, kept. The control does not only frame the chart: it re-keys the TTWROR and IRR values in the KPI band, and that IRR is **annualized** (`portfolio_live.ex:778`). Annualizing a 30- or 90-day window turns ordinary noise into a headline percentage, so no sub-YTD token is offered even though the underlying series is daily. The previous-year select and the custom range (#563, `{:year, y}` and `{:range, from, to}` in `period_start/2`) stay as the disclosure, which is where a genuinely short window belongs. |
| Securities — detail chart | `1M 3M 6M YTD 1Y 3Y 5Y Max` | The full vocabulary, and the only surface that gets it. `securities_live.ex:35` already ships `@ranges ~w(1M 3M 6M YTD 1Y 3Y 5Y MAX)`; the read is one end-of-day close per `(security_id, date)` (`Catalog.Quote`), so a one-month window is ~21 real points, and the surface asserts a price, not an annualized return. Only the `MAX` casing changes, to `Max`. |
| Wealth — Cash flow (all four facets) | `YTD 1Y 3Y 5Y Max` | The smallest bucket any cash-flow read produces is a **calendar month**: `Portfolios.Income` groups booked transactions into `year → month → {dividends, interest}` (`income.ex:10-11, 88-127`). `1M` would resolve to a single bar, `3M`/`6M` to three and six with no comparable prior period — a period control whose narrow end shows one bucket misrepresents a total as a series. `YTD` is also the horizon the tax and statement year is read in. One control on the parent, shared by all four facets, so switching facet keeps the period. |
| Wealth — Snapshots | none — fixed domain | The comparison's x-domain is not a user choice: `SnapshotComparison.for_snapshot/3` walks **every day from the snapshot's as-of date to today** (`snapshot_comparison.ex:9-19`). Every token except `Max` would truncate from the left, hiding the divergence's origin — which is the entire point of the surface. The chart states its domain in the basis line ("since <as-of date>") instead. This refines the Snapshots row above: the surface inherits the shared chart's axes, crosshair and data-table disclosure, but the period control is not applicable to it. |

## State Patterns

**Pending and settling are different states (UX-DR20, binding).**

- **Pending** — the server is still computing; the final value is unknown. Lasts seconds. The user must be able to tell that the app is working and that no number is being asserted.
- **Settling** — the final value is known and being animated into place by the ~600ms count-up. The count-up is **cosmetic**: it animates toward the already-known final value. **Real partial values are never streamed** — a number on screen during settling is never a truthful intermediate result, and must be visually evident as not-yet-final.
- **Not computable** — a third, unrelated state: the computation finished and produced no value (IRR without a solvable cashflow series, a metric with no data in range). This is a data note (UX-DR17), not a loading state.

**Treatment (decided 2026-08-05, from [.working/loading-affordances.html](.working/loading-affordances.html) — options P2 + S1 + F1).**

- **Pending → last known value, dimmed.** The previous value stays on screen in muted colour with the **recomputing cue** and its as-of date, so a magnitude is visible instead of a void. Where no prior value exists — first load, a new account — the slot falls back to a **typographic skeleton** sized to the value's own footprint, never a generic block — whose *substance* is always rendered and whose shimmer alone is motion-gated (clause 4 below). Carries an implementation consequence: a stored previous value is needed per card, and today only TTWROR has one (`@stale_ttwror`).

  **The staleness contract (binding, added 2026-08-05).** The dim is the weakest of the state's channels and is the only one some readers never receive — a screen-reader user, a braille reader, a forced-colors user and anyone with reduced colour discrimination all get the number and none of the marking. A last-known number shown without the other two is *worse* than the bare `…` it replaces: `…` cannot be mistaken for data, an authoritative-looking figure can. So, in every pending render, on every surface:

  1. **`aria-busy="true"` on the slot** for the whole pending state, flipping to `false` when the final value is assigned. The slot is never inside an `aria-live` region (item 4 below).
  2. **A real-text staleness marker inside the slot, before the digits in document order** — source shape "Last known value —", `.visually-hidden` where the visible design already carries the cue beneath. Never a `::before` string, never a `title` attribute, never colour. A linear read must reach the qualifier before the number.
  3. **The distinction survives `forced-colors: active`**, where {colors.text-muted} and {colors.text} collapse to one system colour and the dim ceases to exist. Pending must survive; settling need not — see the Accessibility Floor.
  4. **The fallback's substance is never gated.** Under `prefers-reduced-motion: reduce` the shimmer is absent and the static placeholder, the `aria-busy` and the cue all remain. Gating the whole fallback would leave first load under `reduce` with no appearance at all — an empty slot indistinguishable from "not computable" — and would break the Accessibility Floor's own "replaced by a non-animated cue, **never removed**".

  Anatomy for all four: `{components.value-slot}` `.state-exposure`, `.stale-marker`, `.forced-colors`, `.pending-fallback`.

  **The recomputing cue — behaviour.** Anatomy is `{components.recomputing-cue}` in `DESIGN.md`; what it must *do*:

  1. It appears **only** while a value is genuinely being recomputed, and disappears the instant the new value is assigned — never on a timer, never as decoration on a stale figure the server is not currently refreshing. A dimmed value with no cue is a specification error, not a variant: dimming without the cue is indistinguishable from a disabled figure.
  2. It carries the as-of date of the value **currently shown**, not of the computation in flight.
  3. **It replaces the surface's loading verb string; it does not accompany one.** No surface keeps a free-standing "Loading…" / "Calculating…" heading beside a cue. The nine strings in the build are enumerated in the Alignment inventory → UX-DR20.
  4. **Announcement is per surface, not per slot.** The pending region sets `aria-busy="true"`; the cue text is real text and is read when the region is reached. Only one `role="status"` region per surface announces the transition — five KPI cards must not produce five announcements, which is what the current per-card `role="status"` skeletons do.
  5. Under `prefers-reduced-motion: reduce` the cue **stays**, as a static ring plus the word. Loading indication is information, not polish.
  6. It is never the ⓘ character and never the `:refresh_cw` glyph; both already mean something else.
- **Settling → accent bar under the number.** Digits render muted while a 2px accent bar grows beneath them to full width; on settle the digits snap to full colour and the bar fades out. Progress is made explicit rather than implied. Depends on the approved count-up hook — without a driver the bar could only claim to track the count.

  **Under `prefers-reduced-motion: reduce` the settling state does not occur: the final value renders at full colour immediately, with no bar and no dimming. Only pending keeps a non-animated cue, because only pending has a value that is genuinely unknown.** Stated verbatim in `DESIGN.md` → Value slot; the two spines contradicted each other here until 2026-08-05, and the reading this file carried is the one that survives — settling is by definition a state whose value is *already known*, so a resting "not final" cue would tell reduced-motion users indefinitely not to trust a correct number. The count-up hook is JS and no CSS gate reaches it: it reads `matchMedia("(prefers-reduced-motion: reduce)")` before the first frame, subscribes to its `change` event, and under `reduce` assigns the final value directly.
- **Progressive chart fill → sequential sweep, over final geometry.** **Corrected 2026-08-05 (design-critic pass), and this file carried the superseded wording until the accessibility pass:** the segments do not arrive separately. Allocation is computed in a single `start_async(:allocation)` and lands as one result, so every segment's value is known before the first frame draws. The final geometry is therefore computed before the sweep starts, every segment occupies its final angle from the start, and the sweep animates **opacity or saturation only, never the arc** — a chart never renders a proportion it does not have, which is UX-DR20's "real partial values are never streamed" applied to geometry. The legend does not settle before the geometry does. Under `prefers-reduced-motion` the finished chart appears at once with no cue, because the sweep carries no information to preserve. Full reasoning in `DESIGN.md` → Value slot → Progressive chart fill.

Visual anatomy for all three lives in `DESIGN.md`. Under `prefers-reduced-motion` settling and the sweep collapse to the finished state with no animation and no residual cue, while the **pending** cue remains as a non-animated indication — loading indication is information, not polish, and pending is the only one of the three with something to indicate.

**Defect this must fix (verified, `portfolio_live.ex:715-780`).** Today `…` means pending and `—` means not-computable; both render bold at value size on the same KPI row and are visually near-identical. "Still loading" and "cannot be computed" are therefore indistinguishable on the app's densest metric band. Three absence renderings coexist across the app (blank cell, bold em-dash, explanatory prose); one wins.

| State | Surface | Treatment |
|---|---|---|
| Cold load | Overview, Wealth | Server-rendered first paint: layout arrives complete. `.section-skeleton` ships on both surfaces and stays — the 2026-06-13 claim that LiveView's initial render needs no skeletons is falsified. **Defect:** `.section-skeleton` animates `skeleton-shimmer 1.6s ease-in-out infinite` with no `prefers-reduced-motion` gate, violating both the reduced-motion rule and the no-looping-ambience rule. The four animations that *do* carry a `reduce` fallback are not the compliant norm either — the stylesheet has zero `no-preference` queries, so the whole file is on the opt-out form (Accessibility Floor, clause (a)). Correct for `.spinner`, which must survive `reduce` as a static ring; a gap for the rest. |
| Pending | Any computed value | Last known value dimmed, with `{components.recomputing-cue}` and its as-of date, **plus `aria-busy="true"` on the slot and a real-text staleness marker before the digits** — the dim alone is not the marking (staleness contract above). Typographic skeleton where no prior value exists, its substance ungated under `reduce`. Applies uniformly: **nine** distinct loading verb strings and bare `…` in five KPI cards are drift (enumerated in the Alignment inventory → UX-DR20; the "six" in earlier drafts was an undercount). Income, Tax and Snapshots load synchronously in `mount/3` and have no pending state at all; when they move to async they inherit this pattern rather than inventing one. |
| Settling | Any computed value | ~600ms count-up to the known final value; visually evident as not-final until it lands. Gated behind `prefers-reduced-motion: no-preference` — under `reduce` **the state does not occur at all**: the final value appears immediately at full colour, no bar, no dimming. |
| Not computable | KPI cards, tables | A **note**-severity data note stating why, in one clause. Never the pending glyph. |
| LiveView action pending | Chart toggles, tabs, form submits | Busy state on the triggering control; the surface stays interactive. Inline busy/result states, not toasts, are the target for action feedback. |
| Data note — note | Anywhere | Neutral tone, note icon, the word. Statement of a modelling fact ("valued at last trade price"). The word is DOM text, the icon is `aria-hidden="true"`. Announced `role="status"` — **on the region, not the note** (policy in UX-DR17). [ASSUMPTION] Neutral = {colors.text-muted} on {colors.bg-muted}; the log does not fix the note-level tone. |
| Data note — attention | Anywhere | {colors.warning} tone, attention icon, the word. Something is stale, ambiguous, or incomplete but the figure stands. Same semantics as note: DOM-text word, `aria-hidden` icon, `role="status"` on the region. |
| Data note — problem | Anywhere | {colors.danger} tone, problem icon, the word. The data contradicts itself ("impossible negative holding quantity"); the figure cannot be trusted. Carries its remedy adjacent — inside the note element, so it is adjacent in reading order and not only in pixels. `role="alert"` **only** where the note answers an action the operator just took; a problem present on load or arriving with a batch takes `role="status"` like the rest of its region. |
| Empty — no data at all | Overview | Dashed `.empty-state` well **replacing the total-value block** — the hero was retired by this session (UX-DR2) and cannot be what an empty state replaces. "Nothing here yet — import a PP export or record a transaction," linking to Import and Transactions. |
| Connection — reconnecting | Any surface | `{components.connection-state}` at attention severity, one band under the top bar. Page content keeps its last render **at full colour** — dimming means pending, and a dropped socket is not a computation in flight. Controls stay enabled; a click that cannot reach the server simply does nothing, and disabling them would be a second way of saying "unavailable". Announced once, `role="status"`. |
| Connection — lost | Any surface | The same band escalated to problem severity once the client stops retrying, carrying a reload control inside the note. `role="alert"`. |
| Connection — restored | Any surface | The band is removed. **No success confirmation** — a restored connection is the normal state, and inline results are for actions, not conditions. Values that were pending when the socket dropped return to the pending treatment with their cue. |
| Empty — per surface | Tables, trees | One sentence + one action ("No categories yet." + `+`). Never an unexplained blank region. |
| Error — validation | Forms | Inline `.field-error` at the field, form-level alert above; the form stays open with input retained. Error text linked via `aria-describedby`, field gets `aria-invalid="true"`; on failed submit focus moves to the first invalid field; the form-level alert is `role="alert"`. |
| Filter/search — no matches | Tables, trees, search fields | Controls stay visible; "No matches for 'X'." — never the empty-surface message, never an unexplained blank region. |
| Error — action failed | Any | Alert banner at the top of the workspace page, plain sentence, no codes. |
| Stale data / freshness | Wealth, Securities detail, Tax budget | Quotes, valuations and the tax trim budget show their basis date. When the newest input is older than the previous trading day, the timestamp becomes an **attention** data note — {colors.warning} tone **and** clock glyph **and** the word "stale", never hue alone. **Source confirmed 2026-08-05:** `security_quotes.updated_at` — `Catalog.Quote` declares `timestamps()` (`quote.ex:18-25`) and the upsert refreshes it on every write, including a no-change rewrite (`Quotes.on_conflict/1` replaces `[:close, :source, :updated_at]`, `quotes.ex:256-269`). Because the Yahoo adapter re-fetches full history each run (`period1=0`, `yahoo.ex:7-14, 50`), a successful sync touches every row, so `max(updated_at)` per security is the last successful sync for that security. Two limits the UI must respect rather than paper over: a **failed or skipped** sync (`missing_ticker`, `no_provider_adapter`) writes nothing and is indistinguishable from "never attempted", and a security whose rows are all `source = "manual"` never advances under the manual-protecting upsert. The tax budget's as-of date is real (ADR-0031 §5). Remaining work is implementation, not design: no read function exposes this — `Catalog.Quotes` has no `last_synced_at/1` — and neither the JSON API nor MCP serialises it, so the freshness story carries a thin context function plus its API/MCP field. |
| Not found | `/securities/:id`, `/classifications/:id`, and any future parameterized route | Error line inside the shell — never a bare error page; navigation stays available. |

**Connection state is entirely unbuilt, and nothing is styled for it.** `app.css` contains no `.phx-loading`, `.phx-error`, `.phx-client-error` or `.phx-server-error` rule, and `layout_view.ex` renders no `#client-error` / `#server-error` element. LiveView 1.2.8 already applies those classes to the LiveView root, so the work is one band plus a stylesheet, not a mechanism. This is a live gap, not a solved problem the spec was silent about — and it interacts badly with the pending treatment, which is why the table above says explicitly that a dropped socket dims nothing.

### Per-surface state coverage

The table above is organised by state, which cannot be walked per surface. This matrix is the same rules seen from the IA side, so a reviewer holding one screen against the spec has one row to read. `—` means the state cannot occur on that surface.

| Surface | Cold load | Pending | Empty | Filter no-match | Error |
|---|---|---|---|---|---|
| Overview | `.section-skeleton`, ships and stays | per-slot cue; wealth card, attention list and data quality land from one `start_async(:overview)` | `.empty-state` well replacing the total-value block | — | async exit → one page-level note |
| Wealth — Holdings | `.section-skeleton` (`data-role="performance-skeleton"`) | per-slot cue on all five KPI values | onboarding wizard on the Overview owns the zero-data case; here, a data note | — | range error inline at the control (`data-role="range-error"`) |
| Wealth — Allocation & targets | `.section-skeleton--allocation` | sunburst and drift table land together from `start_async(:allocation)` | "no plan" note (`data-role="no-plan-hint"`) — a note, not an empty state: the surface has data, the *plan* is missing | — | page-level note |
| Wealth — Cash flow (parent) | inherits Holdings | inherits Holdings | — | — | page-level note |
| Cash flow — Income | **none today** — synchronous `mount/3`; inherits the pending pattern when it moves to async | as above | one sentence per section ("No dividends or interest booked yet.") | — | page-level note |
| Cash flow — Realized gains / Deposits & withdrawals / Costs | *n/a* | *n/a* | *n/a* | *n/a* | *n/a* — **specified, unbuilt.** A facet ships only when its read exists, so none of them ever renders an empty shell; until then their state set is *not applicable*, not *undefined*, because there is no surface to hold a state. On build they inherit the Income row. |
| Wealth — Snapshots | **none today** — synchronous `mount/3` | as above | "No snapshots yet."; comparison empty (`data-role="comparison-empty"`) | — | comparison gaps note (`data-role="comparison-gaps"`) |
| Wealth — Tax | **none today** — synchronous `mount/3` | as above | "No statement recorded for this taxpayer and year." | — | form error `role="alert"`; consistency findings as data notes |
| Securities | server-rendered list | detail pane loads with the row | "No securities yet — click + to add one." (`securities_live.ex:288-294`) | **UX-DR13 violation:** the same empty-surface string is shown for a filtered no-match, telling the operator they have no data when they have a filter. Needs its own "No matches for 'X'." line, with the search field and filters left standing. | detail-pane error line |
| Transactions — History | server-rendered | form submit busy on the trigger | `#no-transactions`, `#no-holdings`, `#transaction-setup-empty` | `#transaction-no-match` | inline field errors + form-level `role="alert"` |
| Transactions — Import | server-rendered | `Importing…` on the trigger → becomes the busy state of `{components.inline-result}` | drop zone is the empty state | — | parse failure ends at preview; nothing is applied |
| Accounts & depots | server-rendered | dialog submit busy on the trigger | `data-role="accounts-empty"` | — | inline field errors |
| Views | server-rendered | — | "No views yet." / "No buckets yet." | — | inline field errors |
| Classifications | server-rendered | — | "No categories yet." | "No securities match the search." | inline field errors |

Every surface additionally inherits the three connection rows and the not-found row above; they are not repeated per surface.

## Interaction Primitives

- **Click/tap to act** — rows navigate or select; cards navigate; charts respond to hover/touch with the crosshair.
- **Disclosure affordances** — `+` for create, kebab (`⋮`) for row actions, `<details>` summaries for tree nodes, menus, and the chart data table. One open disclosure at a time per region. Menus built on `<details>` keep native disclosure semantics (no `role="menu"` — that would demand arrow-key support); a shared hand-written hook provides `Esc`-close and mutual exclusivity.
- **Metric tooltips (ⓘ)** are focusable elements (`<button>`/`<summary>`): the definition appears on focus and on tap, stays visible while hovered, dismisses with `Esc` (WCAG 1.4.13) — never hover-only. One ⓘ variant app-wide; two exist today.
- **Period selection** — the single period control (see Component Patterns). One-tap tokens plus a "Custom range…" disclosure. State exposed via `aria-pressed` or radio-group semantics, never accent colour alone.
- **Drag-and-drop** — Classifications only. Always has a non-drag equivalent (select + toolbar); drag is an accelerator, never the only path.
- **`Esc`** closes the topmost modal/popover/menu and cancels inline edits.
- **Locale and theme switching** are always-available top-bar primitives, never buried in settings.
- **Banned:** infinite scroll (paging/filtering instead), hover-only affordances on touch surfaces, modal-on-modal stacks, drag as sole mechanism, motion that carries meaning, looping ambience, a second icon meaning for a glyph already in the vocabulary.

## Accessibility Floor

Behavioral floor; contrast and colour rules live in `DESIGN.md`.

- **Reduced motion:** every polish animation — chart build, count-up, stagger, skeleton shimmer — sits behind `@media (prefers-reduced-motion: no-preference)`. Reduced-motion users get the complete final frame immediately. **Exception:** loading indication is information, not polish — under `reduce` an animated indicator is replaced by a non-animated cue, never removed. Two clauses added 2026-08-05: **(a)** the build implements the opt-out form everywhere — `app.css` contains **zero** `no-preference` queries and four `reduce` blocks (2522, 3017, 4649, 4724) plus the ungated `.section-skeleton` — and the two forms are not equivalent, because `reduce` fails open where the feature is unsupported or unreported and `no-preference` fails safe; this is a gap, not compliance. **(b)** the count-up is a JS hook, so no CSS gate reaches it: it reads `matchMedia("(prefers-reduced-motion: reduce)")` before the first frame, re-checks on `change`, and under `reduce` assigns the final value directly — the settling state does not occur.
- **Keyboard:** all disclosures, menus, and forms operable by keyboard; the shell uses semantic landmarks (`aside`/`nav`/`main`, `aria-label`s, `aria-current="page"`); visible focus is a **solid 2px accent outline** (+ optional soft halo) on every interactive element — the 18%-opacity soft ring is decoration on top, never the indicator itself. `Esc` always closes the topmost layer.
- **Colour independence (binding):** gain/loss, SOLL/IST over/underweight, buy/sell, data-note severity, staleness, **and value-slot state (pending / settling / final / not-computable)** are never conveyed by hue alone — signed values render an explicit "+/−" (or ▲/▼), buy/sell chart markers differ in shape (▲ buy / ▼ sell), stale timestamps carry the clock glyph + text, data notes carry icon + word, a pending value carries `{components.recomputing-cue}` and a real-text staleness marker. {colors.positive}/{colors.danger}/{colors.warning} reinforce meaning, never carry it solo. The full enumeration and its carriers are UX-DR7; the value-slot half was added 2026-08-05 and is the reason it was possible to specify a whole loading vocabulary in colour steps without tripping the rule.
- **Forced colors (binding, added 2026-08-05):** every state distinction survives `forced-colors: active`, carried by text, glyph or border — never by a colour step alone. Under forced colors {colors.text-muted} and {colors.text} collapse to one system colour, tints are dropped, and a bar drawn as a background disappears into the canvas, so pending, settling and final would otherwise render identically. **Pending must survive; settling need not** — a settling value is already the final value, so losing its distinction costs a reader nothing, while losing pending's asserts a stale number as current. `priv/static/app.css` contains zero `forced-colors` rules today, so this is a gap, not a description.
- **Screen reader:** page changes announce via the existing `aria-live="polite"` top-bar title region; icons stay `aria-hidden` with text labels or `.visually-hidden` companions. Every scoped surface states its active view in its subtitle or basis line; scope changes announce through the same live region — under reduced motion the label is the only change cue.
- **Touch targets:** interactive controls grow to ≥ {spacing.touch-target} effective target via `@media (pointer: coarse)`, not a width breakpoint, so iPad in landscape is covered; desktop keeps the dense 32–34px controls. **The floor is a floor, including inside a coarse block:** two rules today set 32px and 24px targets *within* `@media (pointer: coarse)`, which is the branch that exists to prevent them. Ten control classes have no coarse clause at all — enumerated in the Alignment inventory → UX-DR6 (added 2026-08-05).
- **Charts (binding):** SVG carries `role="img"` + `aria-label`; the data behind any chart is always also reachable as a table on the same surface, through the one uniform disclosure. This rule is what makes the single-`aria-label` chart strategy and the 9px axis type acceptable — a chart shipped without its table is a review reject.
- **Plurals:** counts use `ngettext`, never `gettext` with a `%{count}` interpolation, producing "1 held positions have…". **Recounted 2026-08-05 — eight occurrences, not four, and the earlier line numbers were off by one.** `portfolio_live.ex` `gettext(` calls at **1606, 1612, 1618, 1632, 1640** (the Wealth data-quality list), **2322** (`"%{count} rates updated"`, the FX-sync result) and **2852** (`"%{count} bookings through …"`, the basis line); `dashboard_live.ex:216` (the stale-TTWROR line, same basis sentence). `portfolio_live.ex` uses `ngettext` zero times. Line 1632 is the one the earlier count missed entirely and is the worst of them — it works around the plural with a manual `"(s)"` in the msgid. `ngettext` is used correctly elsewhere (`classifications_live.ex`, `imports_live.ex`, `securities_live.ex`, `transaction_management_live.ex`), so this is per-call-site drift, not a missing convention.
- **Language (binding):** `lang` follows the active locale so screen readers pronounce German strings correctly. No user-facing string bypasses gettext.

## Responsive & Platform

One IA, three surfaces. Breakpoints and target sizes are tokens in `DESIGN.md` Layout & Spacing and are referenced here rather than restated; media-query conditions cannot read custom properties, so `app.css` necessarily keeps the literals and the tokens are the documents' source of record.

| Trigger | Behavior |
|---|---|
| Desktop (≥ {spacing.bp-sidebar}) | Fixed sidebar ({spacing.sidebar-width}) or icon rail ({spacing.sidebar-rail}); dense {spacing.density-control} controls; hover affordances allowed (always with focus/tap equivalents). |
| < {spacing.bp-sidebar} | Sidebar becomes the off-canvas overlay over a backdrop (top-bar burger); content full-width. |
| < {spacing.bp-dialog} | Dialogs and menus go single-column; row kebab menus become bottom sheets ({spacing.touch-target} rows). |
| < {spacing.bp-density} | Base type bumps to 14px; page subtitles hide; a generic `table` rule makes tables scroll. |
| `pointer: coarse` (any width — covers iPad landscape) | Interactive targets ≥ {spacing.touch-target}; drag-and-drop yields to select+toolbar; tooltips open on tap. |
| `prefers-reduced-motion: reduce` | Polish motion off, finished frames immediately. The **pending** cue stays, non-animated (a static ring plus its word and date, and the fallback placeholder without its shimmer); **settling** does not occur at all and the final value renders at full colour; the sunburst sweep shows the finished chart with no cue. |
| `prefers-color-scheme` | System theme as default; explicit `[data-theme]` overrides. |
| **Any width, any block wider than the viewport** | The block owns its own `overflow-x` scroller (UX-DR15). `.workspace-page { overflow-x: clip }` (`app.css:3935`) **clips** deliberately, so a wide child is silently truncated rather than scrolled. Four of 23 tables sit in a scroller today; Income's 15-column matrix and its flex label row have neither a scroller nor `min-width: 0`. Between {spacing.bp-density} and desktop (iPhone landscape, iPad) nothing rescues it. Root cause of #560; treated as a missing system rule, not a per-view bug. Full census in the Alignment inventory → UX-DR15. |

## Design Rules

The numbered UX design rules **live here** (ADR-0038 designates this spec the authority; the 2026-08-05 session moved them in). `epics.md` keeps the tracker row and **links here rather than defining them** — verified 2026-08-05: `epics.md` carries nine `UX-DR` references, all in `UX-DR` form, all citations, and two of them state explicitly that "rules are defined in `design-language/EXPERIENCE.md` and `DESIGN.md`, not in this document". The conversion has happened; the claim is not aspirational.

**Counted 2026-08-05: 32 files outside this folder cite these numbers** — `app.css`, seven LiveViews, one context module (`catalog/quote_adjustment.ex`), twelve test files including `test/invariants/css_spacing_scale_test.exs` (which pins UX-DR14), ADR-0027/0028/0038, `epics.md`, `project-context.md`, three implementation artifacts, one planning artifact, and two skill files. (38 including this folder's own spines and reviews. Earlier drafts said 33 and the rubric review said 36; both were wrong.) The identifier is `UX-DRn` everywhere, which is why it is `UX-DRn` here.

Where `epics.md`'s old summary text and this section disagree, this section wins.

Rules whose nature is **visual** are defined in `DESIGN.md` and only summarised here. Everything else is defined here in full. **The pointers are bidirectional:** every `DESIGN.md` target below carries the rule number in its own heading or component definition, so a reader arriving from this index lands on a section that names the rule it is looking for.

| Rule | One line | Defined in |
|---|---|---|
| UX-DR1 | Decluttered Classifications — the tree IS the surface | here |
| UX-DR2 | Analysis-dashboard home: value, needs-attention, data quality | here — **rewritten** |
| UX-DR3 | Progressive-disclosure pass across all surfaces | here |
| UX-DR4 | Every shipped surface has a stated path, and its area lights up | here — **rewritten** |
| UX-DR5 | Chart build-in motion: one-shot, polish only, reduced-motion gated | `DESIGN.md` → **`## Motion`** |
| UX-DR6 | Touch targets ≥ {spacing.touch-target} under `pointer: coarse` | here — **amended**; the ten uncovered classes are in the Alignment inventory |
| UX-DR7 | Colour independence — never hue alone | here — **enumeration extended** to the value-slot states |
| UX-DR8 | Contrast commitments per surface, both themes | `DESIGN.md` → **`## Colors`** |
| UX-DR9 | Modal accessibility — real dialogs, focus trap, `Esc`, focus return | here |
| UX-DR10 | Chart-as-table, one uniform disclosure with a stated purpose | here — **amended**; appearance in `DESIGN.md` → **Components → Data as table** and `{components.disclosure}` |
| UX-DR11 | Explanatory microcopy, impersonal voice, prose is not the fallback | here — **amended** |
| UX-DR12 | Responsive breakpoints; same IA across surfaces; see UX-DR15 | here — **amended** |
| UX-DR13 | State patterns: no-match, error association, freshness basis | here — **section written 2026-08-05**; it was indexed as defined here with no section behind it |
| UX-DR14 | Spacing scale, heading ramp, locale-pill ≥ 11px | `DESIGN.md` → **`## Typography`** (heading ramp) + **`## Layout & Spacing`** (spacing scale) + **Inventory → Top bar** (locale pill) |
| UX-DR15 | Every wide content block owns its scroller | here — **new**; visual half in `DESIGN.md` → **Layout & Spacing → Every wide block owns its scroller** |
| UX-DR16 | Three selected-state classes; one icon vocabulary | mapping here — **new**; appearance in `DESIGN.md` → **Components → Selected state** and `{components.selected-nav}` / `{components.selected-segment}` / `{components.selected-row}` |
| UX-DR17 | Data notes carry one of three severities in one component | here — **new**; appearance in `DESIGN.md` → **Components → Data note** and `{components.data-note}` |
| UX-DR18 | Active states are width-reserved | `DESIGN.md` → **`{components.width-reserve}`**, one mechanism per selected-state class — **new** |
| UX-DR19 | Native controls inherit the design language; ISO dates | `DESIGN.md` → **Components → Native controls** and `{components.native-control}` — **new** |
| UX-DR20 | Pending and settling are different states | here — **new**; appearance in `DESIGN.md` → **Components → Value slot**, `{components.value-slot}` and `{components.recomputing-cue}` |

### UX-DR1 — Decluttered Classifications

The tree is the surface. The New-category form sits behind the `+` affordance; the multiselect toolbar appears only with an active selection; edit/recolor/delete are disclosed per node; search stays permanent because it serves reading. The worst-rated screen of 2026-06-12 and the exemplar every other `.inline-form` removal is measured against.

### UX-DR2 — Analysis-dashboard home *(rewritten 2026-08-05)*

The Overview is an analysis home, not a landing page: the total wealth value with its change, a **"Needs attention"** card listing target deviations, and a **data-quality** section. Each block navigates to the surface that owns it. Density is deliberate — multiple figures at a glance beat one number and a curve.

The "Needs attention" card **states its basis**: a line under the heading names the view, the plan and the drift threshold the deviations are computed against, and where an allocation carries several plans the card says so rather than silently picking one. Visual anatomy: `{components.needs-attention-card}`.

**Data quality on the Overview is ONE line, rendered only when N > 0, with no green all-clear badge, linking to a pre-filtered securities list.** This was decided in the 2026-07-12 design session, never recorded and never built; the decision log names its loss as "precisely the failure mode ADR-0038 exists to stop". **Adopted unchanged, 2026-08-05** — the decision is good and nothing has happened since that argues against it. Visual anatomy: `{components.data-quality-line}`.

The built form contradicts every clause of it: `dashboard_live.ex` renders three `.stat` cards in a `.grid` (`data-role="dq-quotes"` / `dq-class"` / `dq-logo`), renders them whether or not any count is non-zero, and points all three at an unfiltered `/securities`. The build carries the defect.

One clause cannot be closed by design alone and the implementing story must carry it: **there is no pre-filtered securities URL to link to.** `securities_live.ex` `handle_params/3` reads only `tab` and `id`, and the filter state lives inside a LiveComponent popover, so filters are not addressable. Either the story adds URL-addressable filter params, or the link degrades to the unfiltered index and the shortfall is stated in the issue rather than shipped silently.

The Wealth data-quality section is a different block: one `{components.data-note}` per finding at its own severity, not one line. Severity per condition is in the Alignment inventory → UX-DR17.

*Superseded original (2026-06-13):* a hero of total value plus performance curve with a €/% toggle, and four fixed metric cards — cash quote, TTWROR vs. period, top drift, transactions recency. Confirmed by the owner then, never built, and contradicted by the shipped Overview since June. Ruled 2026-08-05: **the rule follows the build.** Consequences: `DESIGN.md`'s `{components.hero}` anatomy and the `key-dashboard.html` mock are downstream of the superseded rule and are stale; Component Patterns carries no Hero row.

### UX-DR3 — Progressive disclosure

Creation and edit forms leave the primary sightline into modals, popovers, or collapsed sections opened by an explicit affordance. Reading is the default posture of every surface. Generalizes the `.inline-form` removal beyond Classifications; the cash-balance form moving into the account row is the current instance.

### UX-DR4 — Every shipped surface has a stated path *(rewritten 2026-08-05, designer)*

The 2026-06-13 rule ("disabled *Soon* entries are hidden; an entry returns when its surface ships") is satisfied by construction — `nav_groups/0` renders no "Soon" pill at all — and answers a question nobody is asking any more. The question that matters now: **which shipped surfaces are reachable only by a path the sidebar does not show?** The rule is restated as: *every built route is reachable from the shell, and the sidebar marks the area that owns it as current. A surface reached only by typing its URL, and an area whose sidebar entry goes unlit while the user stands on it, are both defects.*

**Reachability pass, 2026-08-05** — all fourteen `live/3` declarations in `router.ex:29-42` against `app_shell.ex` `nav_groups/0`, `wealth_tabs/1`, `transactions_tabs/1` and `nav_current?/2`.

| Route | How it is reached | Sidebar marks current? |
|---|---|---|
| `/` | Sidebar `nav-dashboard`; both brand links | yes |
| `/portfolio` | Sidebar `nav-portfolio`; Wealth tab "Holdings"; Overview wealth card (`dashboard_live.ex:233`) | yes |
| `/portfolio?tab=allocation` | Wealth tab; Overview drift alert (`dashboard_live.ex:274`) | yes |
| `/securities` | Sidebar `nav-securities`; four Overview cards | yes |
| `/securities/:id` | Row click in the securities table (detail pane) | yes (prefix match) |
| `/portfolios` | Sidebar `nav-portfolios`; three Overview links | yes |
| `/transactions` | Sidebar `nav-transactions`; Transactions tab "History"; two Overview links | yes |
| `/imports` | **Transactions tab "Import" only** | yes (`:transactions` claims `/imports`) |
| `/income` | **Wealth tab "Income" only** | yes (`:portfolio` claims `/income`) |
| `/tax` | **Wealth tab "Tax" only** | yes (`:portfolio` claims `/tax`) |
| `/snapshots` | **Wealth tab "Snapshots" only** | **no — the recorded `nav_current?/2` defect** |
| `/buckets` | Sidebar "Views" (label ≠ route) | yes |
| `/classifications` | Sidebar `nav-classifications` | yes |
| `/classifications/new` | `+`-style link on the Classifications index (`classifications_live.ex:335`) | yes (prefix match) |
| `/classifications/:id` | Row link on the Classifications index (`classifications_live.ex:329`) | yes (prefix match) |

**Verdict.** No orphans: every built route has a path. Tab-only reachability (`/income`, `/tax`, `/snapshots`, `/imports`) is correct by ADR-0022 — the sidebar carries areas, tabs carry facets — **on the condition that the parent area lights up**, which is exactly why the `/snapshots` omission is a defect and not a variant. Index→detail reachability (`/securities/:id`, `/classifications/:id|new`) needs nothing further. Two records, neither a rule change:

- **`/buckets` is labelled "Views".** Deliberate (ADR-0024 modification 6) and kept; recorded in the IA seams so a router reader is not left hunting.
- **Spec-vs-build divergence, found in this pass:** `DESIGN.md`'s inventory and this document's IA table both describe the Classifications nav group as dynamic, "one entry per tree". `nav_groups/0` (`app_shell.ex:266-294`) renders **one static entry**; the per-tree list lives on `/classifications` itself. The build is the honest reading of ADR-0024 (a tree is an entity, not a task), so the documents follow the build — corrected in the IA table.

**Cash-flow parent — decided 2026-08-05 (designer's call, owner-delegated).** It stays a **Wealth tab**, third in the set, and gets the route **`/cashflow`** (one word, matching `/portfolios`, `/transactions`, `/snapshots`; no hyphens exist in the route table). Its four facets are second-level tabs on query state, mirroring the one nesting idiom already shipped on `/portfolio?tab=allocation`: `/cashflow` (Income, the default facet) · `/cashflow?tab=realized` · `/cashflow?tab=flows` · `/cashflow?tab=costs`. It does **not** become a sidebar entry: ADR-0024 puts tasks in the sidebar, and "Wealth" is already that task — a second entry would make Cash flow compete with its own parent. Two consequences the implementation story carries: `/income` becomes a permanent redirect to `/cashflow` so existing links survive, and `nav_current?/2` must claim `/cashflow` and `/snapshots` under `:portfolio`. Facets ship as they gain a read — a second-level tab appears when its data exists, never as an empty shell.

### UX-DR6 — Touch targets *(amended 2026-08-05)*

Interactive controls reach ≥ {spacing.touch-target} effective target under `@media (pointer: coarse)` — a pointer query, not a width breakpoint, so iPad in landscape is covered. Desktop keeps 32–34px density. Mechanism (padding vs. min-height per control class) is the implementation's call.

**Amendments (2026-08-05), all three because the rule was stated app-wide and enforced nowhere in particular:**

1. **A component definition may not write a sub-floor target into itself.** `{components.selected-segment}`'s `option` specified `min-height 30px` with no coarse clause, and `{components.selected-nav}` specified second-level tabs as "smaller" with no bound at all — so the two families this refresh *consolidates* both carried the defect in their own anatomy. Both now carry an explicit `target-size` clause in `DESIGN.md`, and it binds every call site the class absorbs.
2. **A sub-floor override inside a `pointer: coarse` block is a review reject.** `app.css:5331-5334` sets `.bucket-chip-add` to 32×32px and `:5336-5339` sets `.bucket-chip__remove` to a 24px minimum, both *inside* a coarse-pointer block. Deliberate sub-44px targets in the branch that exists to prevent them.
3. **"Smaller" has a floor.** Second-level tabs drop the icon and tighten the padding; the label stays at {typography.control-label} and both tab levels take {spacing.touch-target} under `pointer: coarse`.

WCAG 2.5.8 Target Size (Minimum) (AA, 24×24) is met by these controls in isolation; the project's own commitment is the stricter 2.5.5 figure and is what this rule enforces.

**Call sites:** Alignment inventory → UX-DR6 — ten uncovered classes plus the two sub-floor overrides, cut as one story.

### UX-DR7 — Colour independence (binding) *(enumeration extended 2026-08-05)*

**The list is the rule.** A distinction that is not on it gets specified in colour steps and nobody notices — which is exactly what happened to the loading vocabulary this refresh introduced, and is the structural cause of the pending state's critical finding. The list is therefore extended whenever a new distinction is added, in the same edit that adds it.

| Distinction | Non-colour carrier |
|---|---|
| Gain / loss | explicit `+` / `−` sign on the value |
| SOLL/IST over- / underweight | sign or ▲/▼, plus the direction word in the "Needs attention" rows |
| Buy / sell chart markers | **shape** — ▲ buy, ▼ sell. Hue-only in the build (issue #645); the `<title>` children cannot rescue it, because the enclosing SVG's `role="img"` collapses the subtree |
| Staleness of a basis date | clock glyph **and** the word "stale" |
| Data-note severity | glyph **and** the severity word, both required, the word always DOM text |
| **Value slot — pending** *(added 2026-08-05)* | `{components.recomputing-cue}`'s ring and word, **and** a real-text staleness marker before the digits, **and** `aria-busy` |
| **Value slot — settling** *(added 2026-08-05)* | the accent bar while it runs; under `reduce` the state does not occur, and under forced colors its loss is accepted — the value is already final |
| **Value slot — not-computable** *(added 2026-08-05)* | the em dash **and** its note-severity data note stating why |
| **Data-quality severities on one surface** *(added 2026-08-05)* | see data-note severity — the three severities must be separable from each other, not merely from the surrounding text |

Semantic colour reinforces meaning, never carries it. **Violated today** on the Wealth KPI cards, where negatives render in the accent colour with no sign emphasis — which breaks `DESIGN.md`'s "money semantics outrank brand" at the same time — and on the buy/sell markers, which are the rule's own first example.

### UX-DR9 — Modal accessibility

Native `<dialog>`/`showModal()` preferred (focus trap and `Esc` for free, and it fits the no-bundler constraint), else `role="dialog" aria-modal="true"` plus a focus-trap hook. Focus moves to the first field or the dialog heading on open; `Esc` closes; focus returns to the trigger. Never modal-on-modal.

**Wholly unbuilt, and `DESIGN.md`'s inventory described it as shipped until 2026-08-05 (issue #646).** `lib/portfolixir_web/` contains zero `<dialog>` elements and seven `aria-modal` attributes; none of the eight LiveView hooks is a focus trap. The `else` branch of this rule is what six modals claim and none implements — and `aria-modal="true"` without containment is worse than omitting it, because the screen reader confines its virtual cursor while `Tab` keeps walking the page behind. One of the seven is not a dialog at all: `securities_live.ex:418` toggles `aria-modal` on the securities detail `<aside>`, which is corrected by deleting the attribute, independently of the `<dialog>` adoption.

### UX-DR10 — Chart-as-table *(amended)*

The data behind every chart is always also reachable as a table, through **one uniform disclosure: one control, one label, one styling, and a stated purpose.** Rendered as a quiet text control rather than the raw browser triangle. Charts carry `role="img"` + `aria-label`. This rule is what makes the single-`aria-label` strategy and 9px axis type acceptable. The purpose line answers "I see no point in this" without removing the accessibility fallback; it is at most one sentence, ≤ 90 characters in the English msgid — the bound is what makes the rule checkable on a diff rather than a matter of taste.

**Amendment (2026-08-05), corrected against a direct count of `lib/portfolixir_web/live/`.** An earlier version of this rule said "three surfaces carry it with three different labels, two carry none". All three numbers were wrong; the error came from the decision log's unverified survey row and was inherited into three places across these documents. What is there:

- **Six chart renderings across five surfaces**, because the Income surface renders two independent charts.
- **Two disclosures, therefore two labels:** `portfolio_live.ex:1709` "Show data as table" (**changes** to "Data as table") and `snapshots_live.ex:489` "Data as table" (the wording of record).
- **Four renderings carry none and must gain one:** the allocation sunburst (`portfolio_live.ex:1790`), the securities detail chart (`securities_live.ex:630`), the Income annual bars (`income_live.ex:108`) and the Income per-month bars (`income_live.ex:203`).

The omission that mattered is **Income** — the surface Lane B is fixing this sprint, absent from the rule that says "a chart shipped without its table is a review reject". `income_live.ex` contains no `<summary>` element at all. Its two `data-table` blocks (`:148`, `:230`) sit adjacent to their charts and the module comments claim UX-DR10 compliance by that adjacency. **Adjacency is not the disclosure**: an unmarked sibling table gives the reader nothing that says "this is the chart's data". The existing tables become the disclosure bodies; nothing is deleted.

Full census with per-rendering line references: `DESIGN.md` → Components → Data as table.

### UX-DR11 — Explanatory microcopy *(amended)*

Domain terms (TTWROR, IRR, SOLL/IST drift, cash quote, Freistellungsauftrag, Verlustverrechnungstopf) carry focusable ⓘ tooltips — focus and tap, `Esc`-dismiss, hoverable per WCAG 1.4.13. Numbers state their basis: as-of date, currency, gross/net, view. de/en via gettext; `lang` follows the active locale.

Amendments (2026-08-05):

1. **Impersonal voice is part of the rule**, not just prose in this document's body — see Voice and Tone. Second-person address is a review-blocking finding.
2. **Prose is not the fallback for anything the design did not solve.** Every explanatory paragraph resolves to a tooltip, a data note, a basis line, or deletion. The same explanation never exists twice in two forms on one screen.
3. **The paragraphs are enumerated, not counted.** "Six paragraphs across six screens" was a count with no list behind it, so no issue could be cut from it and no reviewer could tell when it was done. The list, with each paragraph's file, region and resolved outcome, is the Alignment inventory → UX-DR11 below. It is the acceptance criteria a thin issue points at.

### UX-DR12 — Responsive behavior *(amended)*

Breakpoints {spacing.bp-sidebar} (off-canvas sidebar) / {spacing.bp-dialog} (single-column dialogs, bottom-sheet kebab) / {spacing.bp-density} (14px base, hidden subtitles, table scroll); `pointer: coarse` for touch sizing; same IA on all three surfaces. Amendment: **cross-references UX-DR15** — width handling above {spacing.bp-density} is not a breakpoint concern but a per-block scroller concern, and treating it as a breakpoint concern is what produced #560.

### UX-DR13 — State patterns *(section written 2026-08-05)*

The index has claimed since the rules moved in that UX-DR13 is defined here. It was not: its content sat unmarked across three State Patterns rows, so nothing could be held against it. Written out now, unchanged in substance.

Three obligations, each pinned to a State Patterns row:

1. **A filtered view with no matches is not an empty surface.** When a filter, search or column predicate excludes everything, the controls stay visible, the message names the query — "No matches for 'X'." — and the surface never falls back to its own empty-state copy, which would tell the operator they have no data when they have a filter. State Patterns → *Filter/search — no matches*. Built correctly at `transaction_management_live.ex` (`#transaction-no-match`) and `classifications_live.ex` ("No securities match the search."). **Violated on the securities list:** `securities_live.ex:288-294` renders "No securities yet — click + to add one." whenever `@securities == []`, whether that is because none exist or because the search and column filters excluded them all — the exact failure the rule names.
2. **Every error is programmatically associated with the thing it is about.** A field error is linked by `aria-describedby` and the field carries `aria-invalid="true"`; a failed submit moves focus to the first invalid field; the form-level alert is `role="alert"`. An error rendered *near* a field but not associated *with* it is a violation, because a screen reader reaches the field without it. State Patterns → *Error — validation*.
3. **Every derived number states the basis it was computed from, and says when that basis is stale.** As-of date, currency, gross/net, and — for scoped figures — the view. When the newest input is older than the previous trading day the basis line becomes an **attention** data note carrying tone *and* clock glyph *and* the word (UX-DR7). State Patterns → *Stale data / freshness*, which also records the two honest limits of the freshness source: a failed or skipped sync writes nothing and is indistinguishable from "never attempted", and an all-manual security never advances.

UX-DR13 is not a fourth state class. It is the set of obligations that apply *across* states, which is why it reads as three rows rather than one treatment.

### UX-DR15 — Every wide content block owns its scroller *(new)*

`.workspace-page { overflow-x: clip }` clips rather than scrolls, deliberately. Therefore any block that can exceed the viewport — tables, chart label rows, legends, matrices — **must establish its own `overflow-x` container and set `min-width: 0` on flex children**. This is the system rule behind #560; without it the same defect recurs on the next wide table. A wide block without its own scroller is a review reject regardless of whether it currently overflows.

**Call sites:** Alignment inventory → UX-DR15 — 19 of 23 tables plus one flex label row, cut as two stories.

### UX-DR16 — Three selected-state classes; one icon vocabulary *(new)*

Five idioms for "this control is selected" exist today. Reduced to three, and **every control in the app maps to exactly one**:

1. **Navigation and tabs** — accent underline plus marker. Sidebar keeps pill + marker dot; tabs use icon + label + underline; second-level tabs are the same, smaller and iconless.
2. **Toggles, filters, period selection** — segmented group with filled accent.
3. **Selection in lists and tables** — tinted row with a left accent edge.

Three, not one, because a selected table row and an active tab are genuinely different things; five is drift, one would be dogma. **One icon set app-wide** — a glyph may not carry a second meaning. The funnel collision is resolved (2026-08-05, designer): `:filter` keeps "filter" in the securities toolbar, and the sidebar's Views entry takes `:bookmark`, an existing unused glyph that means "a saved, named selection". Appearance of each class is defined in `DESIGN.md` → Components → Selected state.

**Call sites:** Alignment inventory → UX-DR16 — 19 rows, cut as three stories, one per class.

### UX-DR17 — Data notes carry one of three severities *(new)*

One component, three severities — **note / attention / problem** — distinguished by **colour AND icon AND word** (UX-DR7). Severity describes the finding, not the surface. Replaces the four competing treatments (plain bullets, amber inline highlight, unstyled grey prose, accent bordered banner). Consequence for the data-quality list: "valued at last trade price" is a *note* and "impossible negative holding quantity" is a *problem*; today they render identically, which is why the app's most important warning surface has the lowest visual weight on its page. The remedy sits adjacent to the note that names the problem — testably: **inside the same `<section>` element**, as a child of the note. A reviewer checks the element boundary, not the pixel distance.

**Assistive-technology contract (added 2026-08-05).** "Colour AND icon AND word" was stated three times and bound to the accessibility tree nowhere, so a compliant reading could render the severity as `title="Problem"` or as an icon whose meaning lives in a visual legend — and severity would then reach nobody using assistive technology.

1. **The severity word is always in the DOM as text**, `.visually-hidden` where the visual design shows only the glyph. Not a `title`, not a `::before`, not a legend entry.
2. **The glyph is `aria-hidden="true"`**, so a decorated note never announces its mark twice or announces an unlabelled `<svg>`.
3. **The remedy control is a child of the note element**, so it is adjacent in reading order and not only in visual position. UX-DR17 already stated adjacency in pixels; this is the testable half.
4. **Politeness is per region, never per note.** Data notes appear *after* asynchronous computation and without a focus change — a stale-quote note materialising when the recompute lands, import findings appearing when the preview resolves — which makes them status messages. `note` and `attention` are `role="status"`. `problem` is `role="alert"` **only** where the note answers an action the operator just took; that is the `{components.inline-result}` case, which is why that component already says so. A problem present on first render, or arriving with a batch, is `role="status"` like the rest of its region. The naive answer — `role="alert"` on every problem — is wrong at page scale: the Wealth data-quality section can render six findings at once and an import preview more, and a dozen assertive interruptions on load drowns the surface. **A section that can render more than one note exposes one live region around the list, not one per note.**

**Call sites:** Alignment inventory → UX-DR17 — the six Wealth data-quality conditions with their severities, plus the alert-class sweep. The Wealth list is the worked example of the per-region rule: six notes, one `role="status"` region.

**Glyphs and words decided 2026-08-05 (designer's call, owner-delegated):** note → `:asterisk` (the footnote mark), attention → `:alert_triangle`, problem → `:alert_octagon`; labels "Note" · "Attention" · "Problem" (de: "Hinweis" · "Achtung" · "Problem", Voice and Tone). **All three glyphs are additions** — the 36-glyph set in `app_shell.ex` `icon_paths/1` contains no severity mark, and pressing an unrelated glyph into service would create the second-meaning collision UX-DR16 forbids. Note is deliberately *not* an info circle: ⓘ is the metric-definition affordance at eight call sites, and a definition is not a fact about this data. `DESIGN.md` → Data note carries the descriptions, the reasoning, and the funnel-collision ruling; the stale-data clock glyph of State Patterns is also absent and rides the same icon-set story.

### UX-DR18 — Active states are width-reserved *(new)*

Bold-on-active must reserve its metrics so rows and columns do not shift when selection changes. Measured on the live surface: securities columns shift 14–21px depending on the selected row, the Wealth tab row shifts 10–11px depending on the active tab, the detail-pane tab row moves ~4px with the selected security's subtitle length. Not a preference — a measured defect on three surfaces. **One mechanism per selected-state class, not a menu** — `{components.width-reserve}` fixes which technique belongs to which class, so three stories cannot pick three mechanisms for the same control.

**Call sites:** Alignment inventory → UX-DR18 — three surfaces, one story.

### UX-DR19 — Native controls inherit the design language *(new)*

Date inputs, selects, `<details>` disclosures and checkboxes get defined appearances instead of browser defaults, and this is where the "unfinished" impression concentrates. **Dates render ISO in input as well as in display**; the built date input shows `MM/DD/YYYY` in a product whose every display date is ISO. Appearance defined in `DESIGN.md` → Components → Native controls.

**Scope warning.** "One date input, three selects, three `<details>`, one checkbox" describes the six 2026-08-01 UAT screenshots, not the codebase. App-wide there are **11 date inputs, 29 selects, 25 `<details>` and 13 checkboxes** — 78 call sites. A story cut from the screenshot numbers under-scopes by an order of magnitude. Per-file line numbers in the Alignment inventory → UX-DR19.

### UX-DR20 — Pending and settling are different states *(new)*

Settled: the two states are distinct and get distinct treatments; the count-up is cosmetic and animates to the already-known final value; **real partial values are never streamed**; "not computable" is a third, unrelated state and is a data note, not a loading state. See State Patterns for the full behavior.

Treatment decided 2026-08-05: pending shows the **last known value dimmed** with a recomputing cue and its as-of date, falling back to a **typographic skeleton** where no prior value exists; settling shows an **accent bar growing under the number**; progressive chart fill is a **sequential clockwise sweep**. Anatomy in `DESIGN.md` → Components → Value slot, including `{components.recomputing-cue}`, which this rule depends on and which had no definition until 2026-08-05.

**Call sites:** Alignment inventory → UX-DR20 — nine loading verb strings and six glyph placeholders, cut as two stories along the value-pending / action-busy split.

**The states are not distinguishable by appearance alone, and must not be specified as if they were (added 2026-08-05).** Pending is the state that can lie: it shows a real number that is not the current number, so its non-visual carriers are part of the rule rather than an implementation detail — `aria-busy` on the slot, a real-text staleness marker before the digits, `{components.recomputing-cue}` as DOM text, and survival under `forced-colors: active`. Settling and the sweep carry no such risk, because both animate toward or reveal a value that is already known; under `reduce` settling does not occur at all and the sweep shows the finished frame. UX-DR7's enumeration now covers all four slot states — that omission is what let this vocabulary be specified in colour steps in the first place. Full contract in State Patterns → the staleness contract; anatomy in `{components.value-slot}`.

Two consequences the implementation stories carry:

- Pending needs a stored previous value per card. Today only TTWROR has one (`@stale_ttwror`), so this is state work, not a stylesheet change.
- The settling bar depends on the count-up hook approved 2026-08-05 (`requestAnimationFrame` + `Intl.NumberFormat`, a ninth inline LiveView hook). Pure CSS `@property` counters cannot render `250.000,00` — they render `250000` — so a CSS-only count-up and locale-formatted money are mutually exclusive. Without the hook the bar would have no driver and could only claim to track the count.

### Alignment inventory — deviating call sites per family

**Why this exists.** The spec names one canonical pattern per drift family and says alignment "is cut as Sprint 5 stories, never done opportunistically". Under the repo's issue convention an issue is a pointer and the spec carries the criteria — so without the call sites, an issue pointing at UX-DR16 inherits "every selectable control in the app" and cannot be sized, reviewed or closed. Each subsection below is a work list a thin issue can point at and a reviewer can check off.

**Counted directly in `lib/portfolixir_web/` and `priv/static/app.css` on 2026-08-05, not taken from the decision log.** Where these numbers disagree with an earlier draft or with `.decision-log.md`, these are the ones that were verified. Line numbers drift with every edit; where a stable handle exists — a selector, a `data-role`, a function name, an element id — it is given and is the thing to grep for.

#### UX-DR16 — selected state → three classes

| Deviating call site | Idiom today | Maps to |
|---|---|---|
| `view_switcher.ex:49`, `:67` — `.view-chip.is-active` | solid accent pill | class 2, segmented group |
| `securities_live.ex:146` — `.segmented-control__option.is-active` | tint + accent text | class 2 (nearest to canonical already) |
| `securities_live.ex:518` — `.range-button.is-active` | tint + accent text | class 2 |
| `securities_live.ex:556`, `:566`, `:575`, `:586`, `:596` — `.chart-toggle.is-active` | tint + accent text | class 2 |
| `securities_live.ex:184`, `:197` — `.icon-button.is-active` (filter, columns popovers) | tint + accent text | class 2 |
| `portfolio_live.ex:799`, `:808` — `.button-mini.is-active` (€/% chart mode) | solid fill in a bordered container | class 2 |
| `portfolio_live.ex:820` — `.button-mini.is-active` inside `.period-buttons` | solid fill in a bordered container | class 2 |
| `portfolio_live.ex:949`, `:959` — `.button-mini.is-active` (tree/flat allocation mode) | solid fill in a bordered container | class 2 |
| `income_live.ex:136` — `.income-bar-label.is-active` (year drill) | ad-hoc | class 2 |
| `app_shell.ex:41` — `.nav-link.is-active` | gradient wash + marker dot | class 1, **canonical, unchanged** |
| `app_shell.ex:195` — `.area-tab.is-active` | underline | class 1, gains icon + label |
| `securities_live.ex:493-495` — `.detail-pane-tab.is-active` / `aria-selected` | button-styled tab | class 1, second-level (smaller, iconless) |
| `app_shell.ex:113` — `.theme-choice.is-active` | solid accent fill (menu item) | class 2 |
| `app_shell.ex:144` — `.accent-choice.is-active` | tint + accent text (menu item) | class 2 |
| `app_shell.ex:161` — `.locale-link.is-active` | solid accent fill | class 2 |
| `securities_live.ex:305` — `.security-row.is-selected` | tinted row, no edge | class 3, gains the leading edge |
| `snapshots_live.ex:344` — `tr.is-selected` (`data-role="snapshot-row"`) | tinted row, no edge | class 3 |
| `layout_view.ex:717-718` — `.dnd-row.is-selected`, toggled client-side by the `ClassificationDnD` hook | tinted row, no edge | class 3; the hook writes the class, so the story touches JS as well as CSS |
| `layout_view.ex:1027`, `:1039` — `is-active` toggled client-side for theme and accent controls | as above | class 2; same note |

**Story boundaries.** Three, one per class, cut along the class rather than along the file — a file-shaped story would touch all three classes in `securities_live.ex` and settle none of them. Class 2 is the largest (14 call sites) and is the one the design critic ranked first. The two client-side toggles ride whichever class they belong to and are called out because they are the only ones a CSS-only diff would miss.

#### UX-DR6 — coarse-pointer target floor *(added 2026-08-05)*

Five `@media (pointer: coarse)` blocks ship (app.css:4589, 4887, 4998, 5330, 5521). Between them they cover the metric tooltip summary, security-row padding, the detail-pane tabs and their two buttons, the positions toggle, view chips, bucket checkboxes, `.bucket-list__actions .icon-mini`, the SOLL number inputs, the button family, two `<summary>` classes and one select. **Ten interactive classes are covered nowhere**, read directly from `app.css` on 2026-08-05:

| Class | Desktop metric today | Where |
|---|---|---|
| `.area-tab` | **no `min-height`** — height is padding-derived (`0.45rem` block padding on a 13px/1.4 line) | app.css:4340-4346 |
| `.segmented-control__option` | `min-height: 30px` | app.css:1409-1421 |
| `.range-button` | `min-height: 32px` | app.css:2881-2896 |
| `.chart-toggle` | `min-height: 32px` | app.css:2973-2986 |
| `.period-buttons .button-mini` | **no `min-height`** — `padding: 0.25rem 0.6rem` | app.css:3973-3980 |
| `.locale-link` | `min-width: 30px`, `min-height: 26px` | app.css:743-750 |
| `.icon-button` | `30 × 30px` | app.css:1438-1445 |
| `.theme-choice` / `.accent-choice` | `width: 28px`, `min-height: 28px` | app.css:656-671 |
| `.row-actions__kebab` | **no `min-height`** — `padding: {spacing.1}` | app.css:2110-2117 |
| `.icon-mini` outside `.bucket-list__actions` | **no `min-height`** — `padding: 0.12rem 0.3rem` | app.css:3873-3879 |

Plus **two sub-floor overrides written inside a coarse block**, which are worse than an omission because they are deliberate: `.bucket-chip-add` at `32 × 32px` (app.css:5331-5334) and `.bucket-chip__remove` at a `24px` minimum (5336-5339). Both are raised or deleted.

Two of the ten are **permanent chrome on every screen and every form factor** — the theme and accent menus at 28px and the locale switcher at 30×26px — so they are the first cut, not the tail. And the first-level `.area-tab` fails the floor while the second-level `.detail-pane-tab` meets it (app.css:4603-4608): the inversion is why `{components.selected-nav}` now bounds what "smaller" may mean.

**Story boundary.** One. Six of the ten classes belong to the families UX-DR16 consolidates (`.segmented-control__option`, `.range-button`, `.chart-toggle`, `.period-buttons .button-mini`, `.icon-button`, `.area-tab`), so the clause lands in the consolidated component rather than as six overrides — but the story is separate from the UX-DR16 alignment stories, because the floor must not wait on the consolidation.

#### UX-DR17 — data notes → three severities

Severity assignment for the Wealth data-quality list (`portfolio_live.ex`, `#portfolio-data-quality`), which today renders all six as identical `<li>` bullets:

| Condition | `data-role` / guard | Severity | Why |
|---|---|---|---|
| Positions valued at last trade price | `@trade_priced > 0` | **note** | A modelling fact. The figure stands. |
| Positions with no price at all, missing from the totals | `dq-no-price` | **attention** | The total is incomplete and says so; the figure stands for what it covers. |
| Positions with a price but no FX rate to the base currency | `dq-missing-fx` | **attention** | Same shape, and the remedy ("Sync exchange rates") is already in the string — it becomes the note's control. |
| Bookings dated before 1970 | `@suspect_dates != []` | **attention** | Applied on the first plausible day; a stated approximation, not a contradiction. |
| Cash accounts with no FX rate | `@unvalued_cash != []` | **attention** | As above. Also the manual-`"(s)"` plural workaround — see the plurals rule. |
| Impossible negative holding quantity | `dq-negative-holdings` | **problem** | The data contradicts itself; the figure cannot be trusted. |

Other treatments that collapse into `{components.data-note}`: `.alert-error` / `.alert-success` / `.alert-warning` / `.alert-info` (app.css:1127-1200, 1935-1945), `.hint` used as a message rather than as a form label, and the ad-hoc chips `.not-held-chip` / `.stale-chip` / `.no-quote-chip` / `.negative-holding-chip`.

**Story boundary.** Two: the Wealth list (six rows, one surface, self-contained) and the alert-class sweep (many surfaces, mechanical). Both are blocked on the icon-set story for the three glyphs. The Wealth list's *problem* row is **no longer blocked** — the danger-tint gate is decided (`DESIGN.md` → Colors, 2026-08-05): {colors.danger} darkens to `#b91c1c` in light mode and problem-severity body text measures 5.39:1 on its tint. The token move rides this story or precedes it; it is two declarations (`app.css:20`, `:114`) and it also closes the live `.alert-error` defect.

#### UX-DR18 — width-reserved active states

Measured shifts, and the mechanism each takes (`{components.width-reserve}` fixes one mechanism per class, so these are not open choices):

| Surface | Measured shift | Control | Mechanism |
|---|---|---|---|
| Securities list columns | 14–21px by selected row | `.security-row.is-selected` (`securities_live.ex:305`) | reserved 3px leading gutter on every row |
| Wealth tab row | 10–11px by active tab | `.area-tab.is-active` (`app_shell.ex:195`) | invisible bold shadow text on the label |
| Securities detail-pane tab row | ~4px by the selected security's subtitle length | `.detail-pane-tab` (`securities_live.ex:493-495`) | invisible bold shadow text; the subtitle is a separate width problem and needs a fixed track |

**Story boundary.** One, three surfaces. Tolerance is 0px and is measurable, so this is the most testable rule in the set.

#### UX-DR19 — native controls

78 call sites. `type="date"` (11), `<select>` (29), `<details>` (25), `type="checkbox"` (13):

| Module | `type="date"` | `<select>` | `<details>` | `type="checkbox"` |
|---|---|---|---|---|
| `app_shell.ex` | — | — | 83, 127 | 18 |
| `view_switcher.ex` | — | — | 120 | — |
| `buckets_live.ex` | — | — | 247, 278 | 342, 407, 417, 434 |
| `classifications_live.ex` | — | 211, 237, 512, 535, 686, 709, 1476 | 276, 385, 552 | 192 |
| `imports_live.ex` | — | 240, 266, 276, 876 | 305, 331 | 216, 375, 905 |
| `income_live.ex` | — | — | — | — |
| `portfolio_accounts_live.ex` | — | 265 | 204 | — |
| `portfolio_live.ex` | 853, 860, 1521 | 833, 971, 1513 | 750, 761, 775, 1076, 1144, 1708 | — |
| `securities_live.ex` | 534, 541 | 807, 1357, 1908 | 992, 1146, 1266 | 822, 1312 |
| `snapshots_live.ex` | 305 | 315 | 288, 488 | — |
| `tax_live.ex` | 410 | — | 368 | — |
| `transaction_management_live.ex` | 73, 351, 355 | 62, 84, 116, 331, 342 | 165, 198 | — |
| `securities/split_wizard_dialog.ex` | 83 | — | — | — |
| `securities/security_form_dialog.ex` | — | 389 | — | — |
| `securities/filter_popover.ex` | — | 44, 56, 69 | — | — |
| `securities/column_picker.ex` | — | — | — | 24 |
| `portfolio_accounts/account_form_dialog.ex` | — | 127 | 168 | 168 |

Not all 78 are equal. Three subsets carry the visible defects and are the honest first cut:

- **Date inputs (11)** — the whole `MM/DD/YYYY` problem. One CSS rule plus an ISO display convention fixes all eleven; the four inside period controls (`portfolio_live.ex:853/860`, `securities_live.ex:534/541`) additionally move behind the "Custom range…" disclosure, which is a UX-DR16 story, not this one.
- **`<details>` summaries (25)** — split in two: 8 are already-styled ⓘ tooltips or menus (`app_shell.ex:83/127`, `view_switcher.ex:120`, `portfolio_live.ex:750/761/775/1076`, `tax_live.ex:368`, `securities_live.ex:992/1146`, `transaction_management_live.ex:198`) and 3 are the classification tree's `.cat-summary` nodes; the rest render the raw browser triangle.
- **The checkbox stack (1, and it is a bug)** — `classifications_live.ex:192`, the broken box-above-label rendering the critique flagged. Ships as a defect fix, not as design debt.

**Story boundaries.** Four: date inputs, selects, `<details>` markers, checkboxes. Each is one CSS block plus a sweep, and each is independently verifiable.

#### UX-DR15 — every wide block owns its scroller

23 `<table>` elements. **Four sit in a scroller** — `securities_live.ex:265` and `portfolio_accounts_live.ex:82` (`.data-table-wrapper`), `snapshots_live.ex:333` and `:491` (`.table-scroll`). The other 19, with the column count each can reach:

| Table | Columns | Note |
|---|---|---|
| `income_live.ex:148` (year × month matrix) | **15** | the #560 case; its sibling `.income-bar-labels` flex row also lacks `min-width: 0` (app.css:4113-4119) |
| `securities_live.ex:917` (detail transactions) | 9 | |
| `securities_live.ex:1001`, `:1067` (detail trades) | 9, 8 | |
| `securities_live.ex:1155` (detail holdings) | 9 | |
| `income_live.ex:230` (year detail payments) | 7 | |
| `income_live.ex:283` (per position) | 7 | |
| `transaction_management_live.ex:215` (sell-lot preview) | 7 | |
| `portfolio_live.ex:1369` (`data-role="flat-positions"`) | 6 | |
| `portfolio_accounts_live.ex:213` (`data-role="portfolio-admin-table"`) | 6 | |
| `transaction_management_live.ex:388` (`#transaction-list`) | 6 | |
| `portfolio_live.ex:1066` (drift table) | 5 | |
| `securities_live.ex:1442` (detail quotes) | 4 | |
| `securities/split_wizard_dialog.ex:137` | 4 | inside a dialog |
| `portfolio_live.ex:1710` (`.perf-data-table`) | 3 | inside the data-as-table disclosure |
| `securities/split_wizard_dialog.ex:177` | 3 | inside a dialog |
| `transaction_management_live.ex:300` (`#holdings-table`) | 3 | |
| `classifications_live.ex:581` (`.soll-table`) | 2 | |
| `portfolio_live.ex:1488` (`.cash-table`) | 2 | |

**Story boundaries.** Two. First, the system rule: a shared wrapper plus `min-width: 0` on the flex/grid parents, applied to the ≥6-column tables (10 of them) and to `.income-bar-labels`, which is where truncation is reachable at iPad and iPhone-landscape widths. Second, the tail — the ≤5-column tables get the wrapper for uniformity, which is cheap and prevents the next wide column from reintroducing the defect. A wide block without its own scroller is a review reject regardless of whether it currently overflows.

#### UX-DR20 — loading verb strings

The pending treatment replaces **nine** distinct strings (the "six" in earlier drafts was an undercount). Each row states what it becomes: `{components.recomputing-cue}` when a *value* is recomputing, or the busy state on the *trigger* when an action is running.

| String | Call sites | Kind | Becomes |
|---|---|---|---|
| "Loading…" | `dashboard_live.ex:214`, `:230`, `:264`, `:293` | value pending | the cue; the stale-TTWROR line at `:216` already ends "Recomputing." and is the closest thing in the build to the target |
| "Calculating…" | `portfolio_live.ex:930` and `:1477` (skeleton `aria-label`), `:1567` (visible `.loading-hint`) | value pending | the cue |
| "Syncing…" | `portfolio_live.ex:1540` (`phx-disable-with`), `:1544` (visible, with `.spinner`) | action busy | busy state on the sync trigger |
| "Syncing exchange rates…" | `portfolio_live.ex:1552` (`data-role="fx-sync-status"`) | action busy | busy state on the same trigger; the second, longer string goes |
| "Updating…" | `portfolio_live.ex:1527` (`phx-disable-with`, the balance form) | action busy | busy state; the form itself moves to Accounts & depots |
| "Importing…" | `imports_live.ex:437` (`phx-disable-with`), `:443` (visible) | action busy | busy state on the import trigger |
| "Booking…" | `securities/split_wizard_dialog.ex:112` (`phx-disable-with`) | action busy | busy state |
| "Searching…" | `securities/security_form_dialog.ex:158` | action busy | busy state on the search field |
| "Looking up logo…" | `securities_live.ex:2602` (flash message) | action busy | `{components.inline-result}` busy state; the flash goes with the toast (issue #566) |

Plus the bare glyph placeholders: `…` at `portfolio_live.ex:721`, `:741`, `:749`, `:760`, `:773` (five KPI cards) and `—` at `:774`, both bold at value size, both replaced by the four distinct `{components.value-slot}` appearances.

Skeletons: `.section-skeleton` at `dashboard_live.ex:210`, `:227`, `:263`, `:292` and `portfolio_live.ex:927`, `:1474`. They stay as block skeletons where a whole section is absent, and are **not** what a value slot uses — the slot's fallback is sized to the value's footprint.

Surfaces with no pending state at all, because they load synchronously in `mount/3`: Income, Tax, Snapshots. They inherit this pattern when they move to async; they must not invent one.

**Story boundaries.** Two, along the kind column: the value-pending story (seven call sites, needs the stored-previous-value work and the count-up hook) and the action-busy story (six call sites, needs `{components.inline-result}` and rides #566).

#### UX-DR11 — explanatory prose → tooltip / data note / basis line / deletion

The paragraphs the rule is about. "Free-standing explanatory paragraph" means prose that explains rather than labels; empty-state sentences, field help attached to an input, and error text are not in scope.

| Paragraph | Where | Resolves to |
|---|---|---|
| TTWROR definition + the chart's date range, in one paragraph | `portfolio_live.ex:912-919` (`.hint` under the performance chart) | **split, then delete half.** The definition already exists as an ⓘ tooltip at `:762` — this is the duplicate the rule names. The date range becomes a **basis line** on the chart. |
| "Composition as of today — the view's current bucket membership is applied to the whole history." | `portfolio_live.ex:921-924` (`data-role="composition-label"`) | **basis line** — it states where the number comes from |
| "State the balance the bank shows; only later bookings adjust it." | `portfolio_live.ex:1531` (`.hint` under the balance form) | **deletion** — it moves into the account-row dialog as field help, which is not free-standing prose |
| EUR-hub conversion note | `income_live.ex:91-97` (`p.muted` at the top of the surface) | **basis line** on the income figures, plus an ⓘ on the currency term. Named in the Lane A mandate. |
| "Equity loss pot … plus remaining allowance … Statutory ceiling for this year: …" | `tax_live.ex:343-353` (`p.muted`) | **basis line** under the budget meter |
| "Covers: <institutions>." | `tax_live.ex:355-359` (`p.muted`) | **basis line** — it scopes the figure above it |
| "Enter every amount without its sign. A loss pot is the volume of loss available for offsetting." | `tax_live.ex:389-393` (`p.muted` above the form) | **split** — the instruction is field help on the amount inputs; "a loss pot is…" is an ⓘ on the term |
| "What was instructed per institution, for comparison against what the bank applied." | `tax_live.ex:502-506` (`p.muted`) | **purpose line** on the disclosure the orders list sits behind |
| "Price basis: <basis>. Stored quotes are never modified (see the Quotes tab)." | `securities_live.ex:648-655` (`.detail-tab-hint`, `data-role="chart-basis"`) | **basis line** — already almost one; it loses the parenthetical |
| Four further `.detail-tab-hint` paragraphs | `securities_live.ex:1341`, `:1392`, `:1428`, `:1434` | **triage required.** Each is one of the four outcomes; which one depends on what it says, and that call belongs to the story, not to this table. Named here so none is missed. |
| "Categories drifting more than ±N pp from their target weight." | `dashboard_live.ex:257-261` (`data-role="attention-explainer"`) | **basis line** — it is already the right thing wearing the wrong class, and it is half of what `{components.needs-attention-card}` requires |
| `div.hint[data-role="how-it-works"]` | `buckets_live.ex:59` | **triage required** — a multi-paragraph explainer block, the largest single instance |

The already-correct ⓘ tooltips, for contrast — eight call sites, and the vocabulary everything above converges on: `portfolio_live.ex:751`, `:762`, `:776`, `:1077`; `securities_live.ex:993`, `:1147`; `tax_live.ex:369`; `transaction_management_live.ex:199`; `view_switcher.ex:121`. Two ⓘ variants exist among them and one wins (Interaction Primitives).

**Story boundaries.** Three, by surface: Wealth (three paragraphs, includes the TTWROR duplicate — the highest-value one), Tax (four, and `tax_live.ex`'s own moduledoc already claims the rule its template breaks), Securities + Income + Overview + Views (the remainder, mostly triage).

#### Chart-as-table (UX-DR10) and period control (UX-DR16 class 2)

Call sites for both are in `DESIGN.md` → Components → Data as table (six chart renderings, two disclosures) and in Component Patterns → Period control above (two divergent token sets: `Performance.periods()` = `ytd 1y 3y 5y max`, `securities_live.ex:35` `@ranges` = `1M 3M 6M YTD 1Y 3Y 5Y MAX`, of which only the `MAX` casing changes).

## Inspiration

Recorded because the rejects are load-bearing: three of them were live options this session and one of them was typed before being corrected, and a reject with no record is a proposal waiting to be made again.

**Reference products, and what was taken from each:**

- **Portfolio Performance** — the heritage the product both inherits from and reacts against. Taken: the transaction vocabulary, the year × month income matrix, the target/actual discipline. Rejected: the terminology ambiguity of one "Erträge" bucket covering income, realised gains and flows — which is why Cash flow has four named facets instead of one better label.
- **Kubera ("Works for your AI")** — the agent-first precedent from the 2026-06-12 research digest. Taken: the posture that an agent is a first-class consumer with its own interface. Rejected: making the human UI a thin visualization over it.
- **The research digest's dashboard patterns** (`.working/research-ux-best-practices.md`, 2026-06-12) — one-number-one-curve minimalism. Rejected in favour of analysis density, deliberately and by the owner: multiple figures at a glance beat one number and a curve, and decluttering happens through hierarchy and disclosure rather than by hiding analytics.

**Directions rejected, one line each:**

- **The visualization-only paradigm** (2026-06-12) — the LLM owns configuration and data maintenance via MCP and the human UI becomes a dashboard. Rejected: managing data stays a first-class UI task. This is the single decision the whole spec rests on.
- **An agent-oversight UI** — diff/confirm, a review feed for MCP writes. Rejected: MCP writes are the operator's own commands executed faster, not a third party's proposals.
- **Loading combination P1 + S3 + F3** — typographic skeleton, marker, fade-in-place. Typed as a first pick and corrected in session to **P2 + S1 + F1**. Recorded so the superseded combination is not later mistaken for a parallel option.
- **Income treatments I1, I3, I4** — a sparkline column per instrument, an instrument filter control, and keeping the flat top-contributors list. Rejected in favour of **I2**, stacked segments, because only I2 answers "who contributes how much, *over time*".
- **The four fixed metric cards** of the 2026-06-13 UX-DR2 — cash quote, TTWROR vs. period, top drift, transactions recency. Confirmed by the owner then, never built, contradicted by the shipped Overview since June. Ruled 2026-08-05: the rule follows the build.
- **A bottom tab bar on mobile** — rejected 2026-06-12 by the owner ("keep current behavior"); the off-canvas sidebar is the same navigation on every form factor.

## Key Flows

Protagonist: **Andi**, per PRD §2. (The naming history is in `.decision-log.md` and does not need restating here.)

Flow names mirror the PRD user journeys. Mapping:

- UJ-1 → Flow 1 · UJ-2 → Flow 2 · UJ-6 → Flow 3.
- **UJ-3 ("cash decision, both directions")** → **agent-side only; it has no UI counterpart and is not expected to grow one.** It was previously mapped to Flow 1 step 4, which does not show the inverted read the journey is about — which overweights can release cash with the least strategic damage. That read is a ranking over the same drift table, and the drift table is on screen; the *ranking* is what the MCP response carries and the UI does not. Recorded as a deliberate absence so a reviewer does not go looking for it.
- UJ-4 / UJ-5 → future phase, deliberately absent.

**Binding, not pre-conceded.** The flows below were drafted rather than narrated from a live session, but every step is now checkable against a built route, a named component and a named state, so they are **held against like the rest of this document**. The 2026-06-12 `[ASSUMPTION]` tags are removed. Where a UAT walkthrough finds a step wrong, that is a finding against the spec and lands here as an edit — the same path as any other finding. A spec that pre-concedes its own flows cannot produce a verdict on them, and ADR-0038 makes this document the thing UAT is held against.

**Coverage, stated honestly.** The three flows cover the built surfaces the PRD journeys run through. The surfaces this refresh decided — the four Cash-flow facets, the Tax budget dashboard, the Snapshots comparison-as-surface, the account-row balance dialog — have **no flow of their own**, and that is a scope decision, not an omission: three of the four Cash-flow facets are unbuilt, and a flow narrated over an unbuilt surface is fiction. Until they are built they **inherit Flow 2's shape** — read first, act through a disclosure, the result surfaced as a data note rather than defaulted silently. Their states are specified per surface (State Patterns → Per-surface state coverage) and their reads and gaps in the IA table; a design critic holds them against those, not against a narrative.

### Flow 1 — UJ-1 — Morning briefing (agent journey), the UI counterpart

1. Andi has asked his MCP agent where new cash should go; the agent answered from precomputed MCP values. He opens Portfolixir on the iPad to *see* it.
2. Overview loads server-rendered: layout arrives complete, values are **pending** briefly, then **settle** with the count-up. The as-of basis sits under the total.
3. "Needs attention" states its basis — which view, which plan — and names the top drift. He taps it.
4. Wealth → Allocation & targets opens: sunburst, SOLL/IST drift table with category swatches, over- and underweights carrying sign as well as colour, per-position indicative corrective quantities beside the drift (display only, ADR-0023).
5. **Climax:** the number the agent spoke and the number on the screen are the same number, with the same basis stated. Agent and UI are two views of one analytics engine and nothing was recomputed by hand.

Failure: quotes are stale → the basis line becomes an **attention** data note (tone + glyph + word); the chart still builds, the numbers still state their older basis. No blocking, no modal.

### Flow 2 — UJ-2 — Data maintenance without spreadsheets

1. A broker statement arrived; Andi exports from PP and opens Transactions → Import at his desk.
2. He drops the file. Preview renders: "42 transactions would be created, 2 securities unknown." Nothing has been written.
3. He applies. The import runs idempotently and atomically; the done summary flags the two unclassified securities as data notes — surfaced, not silently defaulted.
4. He follows the flag to his "Asset classes" tree. The tree opens *as a tree*: categories with swatches and counts, search on top, the two new securities in the pinned Unsorted bucket. No form occupies the sightline.
5. He multi-selects both rows and drags them onto a category; the count ticks up, the toolbar disappears with the selection.
6. **Climax:** he hits `+`, a compact disclosed form opens, he adds one category, and the form closes back to nothing — the screen that used to greet him with a wall of inputs now only shows them for the seconds he wants them.

Failure: re-dropping the same file → preview reports the content-hash match and applying changes nothing, and says so.

### Flow 3 — UJ-6 — Switching scope

*Rewritten 2026-08-05.* The previous version of this flow ("the family view") depended on issue #327 — moving depots between portfolios — which ADR-0024 supersedes: **moving becomes a tag edit**, and views, not portfolios, are the user-facing grouping.

1. Andi wants to look at a narrower slice than "Everything". He opens **Views** (Administration) and confirms the view he wants exists — a set of buckets included, another excluded.
2. Buckets are attributes, not destinations: he assigns the missing depot its bucket tag from the chip on its row in **Accounts & depots**. No entity is moved; a tag changes.
3. Back on **Wealth**, he switches the active view. Holdings, allocation, performance and the KPI band all re-scope; the basis line names the active view alongside the as-of date and currency.
4. Values go **pending**, then **settle**. The count-up is the "different data now" texture; the scope label, not the motion, carries the meaning — under reduced motion the label is the only cue and it is enough.
5. Where the view's buckets overlap, the surface says so rather than hiding it: each account is counted exactly once in the total, so per-bucket figures may overlap and must not be summed. This is a **note**, adjacent to the total.
6. **Climax:** one instance, one operator, several scopes, zero bookkeeping about which data is on screen — because every scoped surface states its scope.

Failure: a validation error while recording a transaction in the new scope → inline field error, the form stays open with the input intact, nothing half-writes (ledger atomicity, FR-2).
