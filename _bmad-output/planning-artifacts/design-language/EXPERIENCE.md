---
title: Portfolixir EXPERIENCE.md
status: draft
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

## Foundation

Responsive web, three target surfaces: desktop browser (primary analysis seat), iPad, iPhone. One operator (**Andi**, PRD §2) running several **scopes** in one instance, separated by views rather than by separate installations (ADR-0024) — one persona, many view scopes, single-user self-hosted instance. The LLM agent is the second first-class user, but it consumes the JSON API/MCP, not this surface.

**No UI system.** Server-rendered Phoenix LiveView with hand-written CSS in `priv/static/app.css` — no Tailwind, no JS bundler, no CoreComponents; two function-component modules exist (`app_shell`, `security_chart`), plus a handful of small hand-written LiveView hooks (chart crosshair, drag-and-drop, menu positioning, toast auto-dismiss). `DESIGN.md` is the visual identity reference; every visual value in this spine is a `{path.to.token}` reference into it.

Dark/light/system theme and the three logo-derived accent variants ({colors.accent-violet} / {colors.accent-teal} / {colors.accent-coral}) are shipped, owner-loved, and preserved as the identity anchor.

**Coherence posture (2026-08-05 critique).** The system is coherent at token level and incoherent at component level: eleven recurring UI jobs have two to five independent solutions each. The spec's job from here is not new visual language but **one named solution per job**, with the deviating call sites recorded and aligned through dedicated stories — never opportunistically.

## Information Architecture

IA covers **every built route** — eleven surfaces across the fourteen `live/3` declarations in `router.ex`. The 2026-06-13 scope ("IST only — the current seven surfaces") is retired: three of the four surfaces it omitted are exactly what the 2026-08-05 feedback triage reports as broken, and a design critic cannot hold work against a spec that does not know the surface exists.

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

→ Composition references: [mockups/key-dashboard.html](mockups/key-dashboard.html) and [mockups/key-classifications.html](mockups/key-classifications.html). **The spines win on conflict** — mocks illustrate, they do not specify. Both mocks predate the 2026-08-05 decisions and are stale where they disagree.

**Navigation model (binding: keep current behavior on all form factors).** Desktop: fixed left sidebar ({spacing.sidebar-width}) with grouped, labeled links; a toggle collapses it to an icon rail ({spacing.sidebar-rail}). Below 900px the same sidebar becomes an off-canvas overlay slid in over a backdrop via the top-bar burger; no bottom tab bar is introduced. The sticky top bar carries page title/subtitle, theme menu, accent menu, and the EN/DE locale switcher on every form factor.

**Progressive-disclosure principle (the core decluttering move).** Reading is the default posture of every surface; creating and editing are one intent away, never zero. Creation and edit forms move out of the primary sightline into modals, popovers, or collapsed sections opened by an explicit affordance (`+`, "Edit", kebab). Summary first, drill-down second, filters and forms third. Analytics density is wanted — decluttering happens through hierarchy and disclosure, not through hiding numbers.

**Classifications remains the exemplar.** The tree itself is the surface: search stays (it serves reading), the New-category form collapses behind the `+` affordance, the multiselect toolbar appears only when a selection exists, edit/recolor/delete live on the node. The same treatment generalizes to every surface that still holds an `.inline-form` in primary sightline.

[ASSUMPTION] Owner desire, tentative: the Overview's metric cards become self-configurable. This spine keeps the layout future-friendly — cards are a flat, reorderable collection, no card depends on a sibling — and specifies **no** configuration mechanics.

## Voice and Tone

Microcopy is **explanatory** (binding): the UI translates domain terms instead of assuming them. de/en via the existing gettext infrastructure; both locales ship together.

- Domain metrics carry a focusable ⓘ definition: TTWROR, IRR, SOLL/IST drift, cash quote. One sentence, plain language, method named.
- Numbers state their basis where it is cheap: as-of date, currency, gross/net, and — for scoped figures — the view. The agent gets this via self-describing MCP responses (FR-13); the human gets the same honesty inline.
- **Impersonal voice (owner rule 2026-07-23, binding).** UI and doc text states the fact, the state, and the consequence without addressing the reader — "Mapping required", not "you must map". Where address is genuinely unavoidable: du, never Sie. Imperative labels without personal pronouns are fine. Warnings are a statement of fact plus the remedy. Second-person address and tutorial filler in user-facing strings are review-blocking findings.
- **Prose is not the fallback for what the design did not solve (2026-08-05 finding, binding).** Six free-standing explanatory paragraphs sit across six screens. The worst case: the TTWROR explanation exists **simultaneously** as an ⓘ tooltip and as a permanent paragraph on the same screen. `tax_live.ex`'s own moduledoc claims the tooltip rule while the template violates it five times. UX-DR11 is not occasionally missed — prose is the habit. Every candidate paragraph resolves to exactly one of: a tooltip (a definition), a data note (a fact about this data — see UX-DR17), a basis line (where a number comes from), or deletion. A paragraph that is none of these is a design gap wearing text.

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
| Tab system | Wealth, Transactions, Securities detail pane | **One icon vocabulary, shared with the navigation; two idioms.** The sidebar answers "where am I" and keeps pill plus marker dot. Tabs answer "which facet": icon + label + underline. **Second-level tabs** (inside Cash flow) use the same tabs **smaller and without icons**, so nesting is legible without a third idiom. [ASSUMPTION] The securities detail pane's tabs are second-level by the same logic and adopt the same treatment; the decision log names only Cash flow. Tabs are plain links so switching works without JS. Three tab languages exist today (sidebar pills, `.area-tab` links, `.detail-pane-tab` buttons) — two of them are drift and align to this pattern. |
| Period control | Every time-series surface | **One token vocabulary, one appearance:** `1M 3M 6M YTD 1Y 3Y 5Y Max`. Each surface **declares which tokens it offers**; a surface never invents a token outside the set and never reorders it. "Custom range…" is a **disclosure**, not permanent chrome, and its two date fields follow UX-DR19 (ISO, styled). Selected state is the segmented-group class of UX-DR16. Retires the four current patterns, the two divergent range-token sets, and the four bare `type="date"` inputs. Per-surface subsets are declared below the table (decided 2026-08-05). |
| Data note | Anywhere the UI says something about the data | **One component, three severities: note / attention / problem** — distinguished by **colour AND icon AND word**, never colour alone (UX-DR7). Severity is a property of the finding, not of the surface: "valued at last trade price" is a *note*; "impossible negative holding quantity" is a *problem*; a stale allowance-order budget is *attention*. Replaces the four competing treatments in use (plain bullet list, amber inline highlight, unstyled grey prose, accent bordered banner). Placement is adjacent to the data it describes — a remedy button ~1100px below the bullet naming the problem is a violation. |
| Stat / metric card | Overview, Wealth KPI band | `.stat` anatomy: uppercase label, big value, optional ⓘ. Click/tap navigates to the owning surface. Negative amounts follow money semantics ({colors.danger} + explicit sign), never the accent — the built Wealth KPI cards violate this today. Absence and pending are distinct (see State Patterns). |
| "Needs attention" card | Overview | States its **basis** in a line under the heading: which view and which plan the count is computed from. Where an allocation carries several plans, the card says so explicitly rather than silently picking one. Works without active-plan semantics (gated at E16/ADR-0027) and improves silently once they exist. |
| Chart | Wealth, Securities detail, Snapshots, Cash flow | The shared `security_chart` component is the only chart implementation; the three hand-rolled SVGs are drift and migrate to it. Server-rendered SVG; LiveView re-renders on range/log/percent toggle — toggles show a busy state and expose state via `aria-pressed`. Crosshair + mono tooltip on pointer; touch keeps pan-y and taps the nearest point. Build-in animation plays once per data change, never on crosshair moves. Empty states are gettext'd (`SecurityChart`'s hard-coded English empty state is a defect). |
| Chart data table | Under every chart | **One uniform disclosure: one control, one label, one styling, plus a stated purpose.** Rendered as a quiet text control, not the raw browser triangle. The purpose line makes visible why it exists — it is the accessibility fallback UX-DR10 depends on and what makes 9px axis type and a single `aria-label` acceptable. Three different summary labels exist today and two chart surfaces (sunburst, securities detail chart) have none; both are drift. |
| Allocation visuals | Wealth — Allocation & targets | Donut/sunburst segments and legends are read-only in this run; the drift table follows the Tables row. Over/underweight carries sign or arrow, never hue alone. |
| Tables | Transactions, Securities, drift, holdings, income matrix | Read-first: rows are targets (click → detail/select), hover wash, kebab menu for row actions (bottom sheet < 720px). Sort/filter/column controls live in popovers off the toolbar, never inline. Row selection uses the tinted-row class of UX-DR16. Every table establishes its own horizontal scroller (UX-DR15). Column widths do not change with selection (UX-DR18). |
| Cash accounts | Accounts & depots | **Setting a balance lives in the account row.** The global balance form is retired; each row carries its own "set balance" action opening a small dialog with the account already chosen. Reading is the default posture; editing is one intent away, and the account is never re-picked in a form when the row already knows it. |
| Snapshots comparison | Wealth — Snapshots | **The comparison is the surface.** Plan against reality over time is the purpose, so the comparison goes primary and large, the snapshot list secondary beneath it, the create form behind a disclosure. Rendered with the shared chart component — inheriting its axes, crosshair and data-table disclosure, but **not** a period control: the domain is fixed by the snapshot's own as-of date (see the subset table above) — replacing the hand-rolled two-polyline SVG. The v1 gross/price-return-only limitation is stated as a data note, and excluded securities are listed as gaps. |
| Tax surface | Wealth — Tax | **A budget dashboard plus a check list.** Top: allowance-order utilization per institution as a visual fill level with the remaining amount and its as-of date. Below: the recorded statements as a list, each carrying its consistency finding as a **data note** at the right severity. Entry forms move behind a disclosure. The five permanent prose paragraphs become ⓘ tooltips. Pots render with the statement's printed sign (ADR-0031 §2); nothing here is derived from holdings and nothing here is tax advice. **MCP/LLM is the primary write path**; the UI is a visual review surface. Document intake stays rejected. |
| Forms behind disclosure | All create/edit | Default closed. Opened by explicit affordance (`+`, "Edit", kebab). One disclosure level at a time; `Esc`/cancel closes and returns focus to the trigger. Modals are real dialogs: native `<dialog>`/`showModal()` preferred (focus trap + `Esc` for free, fits the no-bundler constraint), else `role="dialog" aria-modal="true"` with a small focus-trap hook; focus moves to the first field or the dialog heading on open. Destructive actions confirm once, never twice. |
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

**Treatment (decided 2026-08-05, from `.working/loading-affordances.html`).**

- **Pending → last known value, dimmed.** The previous value stays on screen in muted colour with a recomputing cue and its as-of date, so a magnitude is visible instead of a void. Where no prior value exists — first load, a new account — the slot falls back to a **typographic skeleton** sized to the value's own footprint, never a generic block. Carries an implementation consequence: a stored previous value is needed per card, and today only TTWROR has one (`@stale_ttwror`).
- **Settling → accent bar under the number.** Digits render muted while a 2px accent bar grows beneath them to full width; on settle the digits snap to full colour and the bar fades out. Progress is made explicit rather than implied. Depends on the approved count-up hook — without a driver the bar could only claim to track the count.
- **Progressive chart fill → sequential sweep.** Segments appear clockwise as their values arrive. Known cost, accepted by the owner: the shape moves during the build, so the chart briefly shows proportions it does not have. The build is short and one-shot, and the legend must not settle before the geometry does.

Visual anatomy for all three lives in `DESIGN.md`. Under `prefers-reduced-motion` each collapses to the finished state with no animation, while the pending cue **remains** as a non-animated indication — loading indication is information, not polish.

**Defect this must fix (verified, `portfolio_live.ex:715-780`).** Today `…` means pending and `—` means not-computable; both render bold at value size on the same KPI row and are visually near-identical. "Still loading" and "cannot be computed" are therefore indistinguishable on the app's densest metric band. Three absence renderings coexist across the app (blank cell, bold em-dash, explanatory prose); one wins.

| State | Surface | Treatment |
|---|---|---|
| Cold load | Overview, Wealth | Server-rendered first paint: layout arrives complete. `.section-skeleton` ships on both surfaces and stays — the 2026-06-13 claim that LiveView's initial render needs no skeletons is falsified. **Defect:** `.section-skeleton` animates `1.6s … infinite` with no `prefers-reduced-motion` gate (`app.css:4437`), violating both the reduced-motion rule and the no-looping-ambience rule. |
| Pending | Any computed value | Last known value dimmed, with a recomputing cue and its as-of date; typographic skeleton where no prior value exists. Applies uniformly: six different loading verb strings and bare `…` in five KPI cards are drift. Income, Tax and Snapshots load synchronously in `mount/3` and have no pending state at all; when they move to async they inherit this pattern rather than inventing one. |
| Settling | Any computed value | ~600ms count-up to the known final value; visually evident as not-final until it lands. Gated behind `prefers-reduced-motion: no-preference` — under `reduce` the final value appears immediately. |
| Not computable | KPI cards, tables | A **note**-severity data note stating why, in one clause. Never the pending glyph. |
| LiveView action pending | Chart toggles, tabs, form submits | Busy state on the triggering control; the surface stays interactive. Inline busy/result states, not toasts, are the target for action feedback. |
| Data note — note | Anywhere | Neutral tone, note icon, the word. Statement of a modelling fact ("valued at last trade price"). [ASSUMPTION] Neutral = {colors.text-muted} on {colors.bg-muted}; the log does not fix the note-level tone. |
| Data note — attention | Anywhere | {colors.warning} tone, attention icon, the word. Something is stale, ambiguous, or incomplete but the figure stands. |
| Data note — problem | Anywhere | {colors.danger} tone, problem icon, the word. The data contradicts itself ("impossible negative holding quantity"); the figure cannot be trusted. Carries its remedy adjacent. |
| Empty — no data at all | Overview | Dashed `.empty-state` well replacing the hero: "Nothing here yet — import a PP export or record a transaction," linking to Import and Transactions. |
| Empty — per surface | Tables, trees | One sentence + one action ("No categories yet." + `+`). Never an unexplained blank region. |
| Error — validation | Forms | Inline `.field-error` at the field, form-level alert above; the form stays open with input retained. Error text linked via `aria-describedby`, field gets `aria-invalid="true"`; on failed submit focus moves to the first invalid field; the form-level alert is `role="alert"`. |
| Filter/search — no matches | Tables, trees, search fields | Controls stay visible; "No matches for 'X'." — never the empty-surface message, never an unexplained blank region. |
| Error — action failed | Any | Alert banner at the top of the workspace page, plain sentence, no codes. |
| Stale data / freshness | Wealth, Securities detail, Tax budget | Quotes, valuations and the tax trim budget show their basis date. When the newest input is older than the previous trading day, the timestamp becomes an **attention** data note — {colors.warning} tone **and** clock glyph **and** the word "stale", never hue alone. **Source confirmed 2026-08-05:** `security_quotes.updated_at` — `Catalog.Quote` declares `timestamps()` (`quote.ex:18-25`) and the upsert refreshes it on every write, including a no-change rewrite (`Quotes.on_conflict/1` replaces `[:close, :source, :updated_at]`, `quotes.ex:256-269`). Because the Yahoo adapter re-fetches full history each run (`period1=0`, `yahoo.ex:7-14, 50`), a successful sync touches every row, so `max(updated_at)` per security is the last successful sync for that security. Two limits the UI must respect rather than paper over: a **failed or skipped** sync (`missing_ticker`, `no_provider_adapter`) writes nothing and is indistinguishable from "never attempted", and a security whose rows are all `source = "manual"` never advances under the manual-protecting upsert. The tax budget's as-of date is real (ADR-0031 §5). Remaining work is implementation, not design: no read function exposes this — `Catalog.Quotes` has no `last_synced_at/1` — and neither the JSON API nor MCP serialises it, so the freshness story carries a thin context function plus its API/MCP field. |
| Not found | `/securities/:id`, `/classifications/:id`, and any future parameterized route | Error line inside the shell — never a bare error page; navigation stays available. |

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

- **Reduced motion:** every polish animation — chart build, count-up, stagger, skeleton shimmer — sits behind `@media (prefers-reduced-motion: no-preference)`. Reduced-motion users get the complete final frame immediately. **Exception:** loading indication is information, not polish — under `reduce` an animated indicator is replaced by a non-animated cue, never removed.
- **Keyboard:** all disclosures, menus, and forms operable by keyboard; the shell uses semantic landmarks (`aside`/`nav`/`main`, `aria-label`s, `aria-current="page"`); visible focus is a **solid 2px accent outline** (+ optional soft halo) on every interactive element — the 18%-opacity soft ring is decoration on top, never the indicator itself. `Esc` always closes the topmost layer.
- **Colour independence (binding):** gain/loss, SOLL/IST over/underweight, buy/sell, data-note severity, and staleness are never conveyed by hue alone — signed values render an explicit "+/−" (or ▲/▼), buy/sell chart markers differ in shape (▲ buy / ▼ sell), stale timestamps carry the clock glyph + text, data notes carry icon + word. {colors.positive}/{colors.danger}/{colors.warning} reinforce meaning, never carry it solo.
- **Screen reader:** page changes announce via the existing `aria-live="polite"` top-bar title region; icons stay `aria-hidden` with text labels or `.visually-hidden` companions. Every scoped surface states its active view in its subtitle or basis line; scope changes announce through the same live region — under reduced motion the label is the only change cue.
- **Touch targets:** interactive controls grow to ≥ 44px effective target via `@media (pointer: coarse)`, not a width breakpoint, so iPad in landscape is covered; desktop keeps the dense 32–34px controls.
- **Charts (binding):** SVG carries `role="img"` + `aria-label`; the data behind any chart is always also reachable as a table on the same surface, through the one uniform disclosure. This rule is what makes the single-`aria-label` chart strategy and the 9px axis type acceptable — a chart shipped without its table is a review reject.
- **Plurals:** counts use `ngettext`, never `gettext` with a `%{count}` interpolation. Four occurrences of the wrong form exist (`portfolio_live.ex:1607, 1612, 1619, 1641`), producing "1 held positions have…".
- **Language (binding):** `lang` follows the active locale so screen readers pronounce German strings correctly. No user-facing string bypasses gettext.

## Responsive & Platform

One IA, three surfaces; pixel values live in `DESIGN.md` Layout & Spacing.

| Trigger | Behavior |
|---|---|
| Desktop (≥ 900px) | Fixed sidebar ({spacing.sidebar-width}) or icon rail ({spacing.sidebar-rail}); dense 32–34px controls; hover affordances allowed (always with focus/tap equivalents). |
| < 900px | Sidebar becomes the off-canvas overlay over a backdrop (top-bar burger); content full-width. |
| < 720px | Dialogs and menus go single-column; row kebab menus become bottom sheets (44px+ rows). |
| < 560px | Base type bumps to 14px; page subtitles hide; a generic `table` rule makes tables scroll. |
| `pointer: coarse` (any width — covers iPad landscape) | Interactive targets ≥ 44px; drag-and-drop yields to select+toolbar; tooltips open on tap. |
| `prefers-reduced-motion: reduce` | Polish motion off, finished frames immediately; loading cues stay, non-animated. |
| `prefers-color-scheme` | System theme as default; explicit `[data-theme]` overrides. |
| **Any width, any block wider than the viewport** | The block owns its own `overflow-x` scroller (UX-DR15). `.workspace-page { overflow-x: clip }` (`app.css:3934`) **clips** deliberately, so a wide child is silently truncated rather than scrolled. Snapshots wraps its tables in `.table-scroll`, Securities in `.data-table-wrapper`, Income in nothing — its 15-column matrix and flex label row also lack `min-width: 0`. Between 560px and desktop (iPhone landscape, iPad) nothing rescues it. Root cause of #560; treated as a missing system rule, not a per-view bug. |

## Design Rules

The numbered UX design rules **live here** (ADR-0038 designates this spec the authority; the 2026-08-05 session moved them in). `epics.md` keeps the tracker row and **links here rather than defining them** — 33 files cite these numbers, including `app.css`, eight LiveViews, ADR-0027/0028/0038, and `test/invariants/css_spacing_scale_test.exs`, which pins UX-DR14. Where `epics.md`'s old summary text and this section disagree, this section wins.

Rules whose nature is **visual** are defined in `DESIGN.md` and only summarised here. Everything else is defined here in full.

| Rule | One line | Defined in |
|---|---|---|
| UX-DR1 | Decluttered Classifications — the tree IS the surface | here |
| UX-DR2 | Analysis-dashboard home: value, needs-attention, data quality | here — **rewritten** |
| UX-DR3 | Progressive-disclosure pass across all surfaces | here |
| UX-DR4 | Every shipped surface has a stated path, and its area lights up | here — **rewritten** |
| UX-DR5 | Chart build-in motion: one-shot, polish only, reduced-motion gated | `DESIGN.md` Motion |
| UX-DR6 | Touch targets ≥ 44px under `pointer: coarse` | here |
| UX-DR7 | Colour independence — never hue alone | here |
| UX-DR8 | Contrast commitments per surface, both themes | `DESIGN.md` Colors |
| UX-DR9 | Modal accessibility — real dialogs, focus trap, `Esc`, focus return | here |
| UX-DR10 | Chart-as-table, one uniform disclosure with a stated purpose | here — **amended** |
| UX-DR11 | Explanatory microcopy, impersonal voice, prose is not the fallback | here — **amended** |
| UX-DR12 | Responsive breakpoints; same IA across surfaces; see UX-DR15 | here — **amended** |
| UX-DR13 | State patterns: no-match, error association, freshness basis | here |
| UX-DR14 | Spacing scale, heading ramp, locale-pill ≥ 11px | `DESIGN.md` Typography + Layout |
| UX-DR15 | Every wide content block owns its scroller | here — **new** |
| UX-DR16 | Three selected-state classes; one icon vocabulary | `DESIGN.md` (appearance) — mapping here — **new** |
| UX-DR17 | Data notes carry one of three severities in one component | here — **new** |
| UX-DR18 | Active states are width-reserved | `DESIGN.md` — **new** |
| UX-DR19 | Native controls inherit the design language; ISO dates | `DESIGN.md` — **new** |
| UX-DR20 | Pending and settling are different states | here — **new** |

> Note on the `DESIGN.md` pointers: UX-DR5 and UX-DR8 are already carried there. UX-DR14, UX-DR16, UX-DR18 and UX-DR19 are **new to `DESIGN.md` as of this session's refresh** — UX-DR14 exists there today only as a flagged gap. Until `DESIGN.md` carries them, the summaries below are the interim statement; once it does, `DESIGN.md` wins on their visual definition.

### UX-DR1 — Decluttered Classifications

The tree is the surface. The New-category form sits behind the `+` affordance; the multiselect toolbar appears only with an active selection; edit/recolor/delete are disclosed per node; search stays permanent because it serves reading. The worst-rated screen of 2026-06-12 and the exemplar every other `.inline-form` removal is measured against.

### UX-DR2 — Analysis-dashboard home *(rewritten 2026-08-05)*

The Overview is an analysis home, not a landing page: the total wealth value with its change, a **"Needs attention"** card listing target deviations, and a **data-quality** section. Each block navigates to the surface that owns it. Density is deliberate — multiple figures at a glance beat one number and a curve.

The "Needs attention" card **states its basis**: a line under the heading names the view and the plan the deviations are computed against, and where an allocation carries several plans the card says so rather than silently picking one. Data quality follows UX-DR17 severities instead of rendering four qualitatively different conditions as identical bullets.

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

### UX-DR6 — Touch targets

Interactive controls reach ≥ 44px effective target under `@media (pointer: coarse)` — a pointer query, not a width breakpoint, so iPad in landscape is covered. Desktop keeps 32–34px density. Mechanism (padding vs. min-height per control class) is the implementation's call.

### UX-DR7 — Colour independence (binding)

Gain/loss, SOLL/IST over/underweight, buy/sell, staleness, and data-note severity are never conveyed by hue alone. Signed values carry an explicit `+`/`−` (or ▲/▼); buy/sell chart markers differ in shape; stale timestamps carry a glyph and the word; data notes carry an icon and the word. Semantic colour reinforces meaning, never carries it. **Violated today** on the Wealth KPI cards, where negatives render in the accent colour with no sign emphasis — which breaks `DESIGN.md`'s "money semantics outrank brand" at the same time.

### UX-DR9 — Modal accessibility

Native `<dialog>`/`showModal()` preferred (focus trap and `Esc` for free, and it fits the no-bundler constraint), else `role="dialog" aria-modal="true"` plus a focus-trap hook. Focus moves to the first field or the dialog heading on open; `Esc` closes; focus returns to the trigger. Never modal-on-modal.

### UX-DR10 — Chart-as-table *(amended)*

The data behind every chart is always also reachable as a table, through **one uniform disclosure: one control, one label, one styling, and a stated purpose.** Rendered as a quiet text control rather than the raw browser triangle. Charts carry `role="img"` + `aria-label`. This rule is what makes the single-`aria-label` strategy and 9px axis type acceptable. Amendment (2026-08-05): three different summary labels are in use and two chart surfaces — the sunburst and the securities detail chart — have no table at all; both must gain it. The purpose line answers "I see no point in this" without removing the accessibility fallback.

### UX-DR11 — Explanatory microcopy *(amended)*

Domain terms (TTWROR, IRR, SOLL/IST drift, cash quote, Freistellungsauftrag, Verlustverrechnungstopf) carry focusable ⓘ tooltips — focus and tap, `Esc`-dismiss, hoverable per WCAG 1.4.13. Numbers state their basis: as-of date, currency, gross/net, view. de/en via gettext; `lang` follows the active locale.

Amendments (2026-08-05):

1. **Impersonal voice is part of the rule**, not just prose in this document's body — see Voice and Tone. Second-person address is a review-blocking finding.
2. **Prose is not the fallback for anything the design did not solve.** Every explanatory paragraph resolves to a tooltip, a data note, a basis line, or deletion. The same explanation never exists twice in two forms on one screen.

### UX-DR12 — Responsive behavior *(amended)*

Breakpoints 900 (off-canvas sidebar) / 720 (single-column dialogs, bottom-sheet kebab) / 560 (14px base, hidden subtitles, table scroll); `pointer: coarse` for touch sizing; same IA on all three surfaces. Amendment: **cross-references UX-DR15** — width handling above 560px is not a breakpoint concern but a per-block scroller concern, and treating it as a breakpoint concern is what produced #560.

### UX-DR15 — Every wide content block owns its scroller *(new)*

`.workspace-page { overflow-x: clip }` clips rather than scrolls, deliberately. Therefore any block that can exceed the viewport — tables, chart label rows, legends, matrices — **must establish its own `overflow-x` container and set `min-width: 0` on flex children**. This is the system rule behind #560; without it the same defect recurs on the next wide table. A wide block without its own scroller is a review reject regardless of whether it currently overflows.

### UX-DR16 — Three selected-state classes; one icon vocabulary *(new)*

Five idioms for "this control is selected" exist today. Reduced to three, and **every control in the app maps to exactly one**:

1. **Navigation and tabs** — accent underline plus marker. Sidebar keeps pill + marker dot; tabs use icon + label + underline; second-level tabs are the same, smaller and iconless.
2. **Toggles, filters, period selection** — segmented group with filled accent.
3. **Selection in lists and tables** — tinted row with a left accent edge.

Three, not one, because a selected table row and an active tab are genuinely different things; five is drift, one would be dogma. **One icon set app-wide** — a glyph may not carry a second meaning. The funnel collision is resolved (2026-08-05, designer): `:filter` keeps "filter" in the securities toolbar, and the sidebar's Views entry takes `:bookmark`, an existing unused glyph that means "a saved, named selection". Appearance of each class is defined in `DESIGN.md`.

### UX-DR17 — Data notes carry one of three severities *(new)*

One component, three severities — **note / attention / problem** — distinguished by **colour AND icon AND word** (UX-DR7). Severity describes the finding, not the surface. Replaces the four competing treatments (plain bullets, amber inline highlight, unstyled grey prose, accent bordered banner). Consequence for the data-quality list: "valued at last trade price" is a *note* and "impossible negative holding quantity" is a *problem*; today they render identically, which is why the app's most important warning surface has the lowest visual weight on its page. The remedy sits adjacent to the note that names the problem.

**Glyphs and words decided 2026-08-05 (designer's call, owner-delegated):** note → `:asterisk` (the footnote mark), attention → `:alert_triangle`, problem → `:alert_octagon`; labels "Note" · "Attention" · "Problem" (de: "Hinweis" · "Achtung" · "Problem", Voice and Tone). **All three glyphs are additions** — the 36-glyph set in `app_shell.ex` `icon_paths/1` contains no severity mark, and pressing an unrelated glyph into service would create the second-meaning collision UX-DR16 forbids. Note is deliberately *not* an info circle: ⓘ is the metric-definition affordance at eight call sites, and a definition is not a fact about this data. `DESIGN.md` → Data note carries the descriptions, the reasoning, and the funnel-collision ruling; the stale-data clock glyph of State Patterns is also absent and rides the same icon-set story.

### UX-DR18 — Active states are width-reserved *(new)*

Bold-on-active must reserve its metrics so rows and columns do not shift when selection changes. Measured on the live surface: securities columns shift 14–21px depending on the selected row, the Wealth tab row shifts 10–11px depending on the active tab, the detail-pane tab row moves ~4px with the selected security's subtitle length. Not a preference — a measured defect on three surfaces. Mechanism defined in `DESIGN.md`.

### UX-DR19 — Native controls inherit the design language *(new)*

Date inputs, selects, `<details>` disclosures and checkboxes get defined appearances instead of browser defaults — one date input, three selects, three `<details>` and one checkbox currently render in browser default beside carefully styled pills and segmented controls, and this is where the "unfinished" impression concentrates. **Dates render ISO in input as well as in display**; the built date input shows `MM/DD/YYYY` in a product whose every display date is ISO. Appearance defined in `DESIGN.md`.

### UX-DR20 — Pending and settling are different states *(new)*

Settled: the two states are distinct and get distinct treatments; the count-up is cosmetic and animates to the already-known final value; **real partial values are never streamed**; "not computable" is a third, unrelated state and is a data note, not a loading state. See State Patterns for the full behavior.

Treatment decided 2026-08-05: pending shows the **last known value dimmed** with a recomputing cue and its as-of date, falling back to a **typographic skeleton** where no prior value exists; settling shows an **accent bar growing under the number**; progressive chart fill is a **sequential clockwise sweep**. Anatomy in `DESIGN.md`.

Two consequences the implementation stories carry:

- Pending needs a stored previous value per card. Today only TTWROR has one (`@stale_ttwror`), so this is state work, not a stylesheet change.
- The settling bar depends on the count-up hook approved 2026-08-05 (`requestAnimationFrame` + `Intl.NumberFormat`, a ninth inline LiveView hook). Pure CSS `@property` counters cannot render `250.000,00` — they render `250000` — so a CSS-only count-up and locale-formatted money are mutually exclusive. Without the hook the bar would have no driver and could only claim to track the count.

## Key Flows

Protagonist: **Andi**, the operator-investor (PRD §2). *Correction (2026-08-05):* earlier versions of this document invented a persona called "Alex" and labelled it a privacy measure. The owner's standing ruling is that naming the operator is acceptable — what stays out permanently is concrete financial values and anything about family or household. The pseudonym was the dishonest part, not the content, so the flows use the PRD's name. A third name, "Steve", appears in the 2026-07-12 session notes and is not a persona at all but an in-repo reviewer skill.

Flow names mirror the PRD user journeys. Mapping: UJ-1 → Flow 1 · UJ-2 → Flow 2 · UJ-3 → covered by Flow 1 step 4 (agent-side journey, same drift table) · UJ-4/UJ-5 → future phase, deliberately absent · UJ-6 → Flow 3.

**These flows are drafted, not narrated from a real session.** No live walkthrough was recorded; the journey *intent* is PRD-canonical, the *step detail* is [ASSUMPTION] throughout and is the first thing a UAT persona walkthrough should overwrite.

### Flow 1 — UJ-1 — Morning briefing (agent journey), the UI counterpart [ASSUMPTION]

1. Andi has asked his MCP agent where new cash should go; the agent answered from precomputed MCP values. He opens Portfolixir on the iPad to *see* it.
2. Overview loads server-rendered: layout arrives complete, values are **pending** briefly, then **settle** with the count-up. The as-of basis sits under the total.
3. "Needs attention" states its basis — which view, which plan — and names the top drift. He taps it.
4. Wealth → Allocation & targets opens: sunburst, SOLL/IST drift table with category swatches, over- and underweights carrying sign as well as colour, per-position indicative corrective quantities beside the drift (display only, ADR-0023).
5. **Climax:** the number the agent spoke and the number on the screen are the same number, with the same basis stated. Agent and UI are two views of one analytics engine and nothing was recomputed by hand.

Failure: quotes are stale → the basis line becomes an **attention** data note (tone + glyph + word); the chart still builds, the numbers still state their older basis. No blocking, no modal.

### Flow 2 — UJ-2 — Data maintenance without spreadsheets [ASSUMPTION]

1. A broker statement arrived; Andi exports from PP and opens Transactions → Import at his desk.
2. He drops the file. Preview renders: "42 transactions would be created, 2 securities unknown." Nothing has been written.
3. He applies. The import runs idempotently and atomically; the done summary flags the two unclassified securities as data notes — surfaced, not silently defaulted.
4. He follows the flag to his "Asset classes" tree. The tree opens *as a tree*: categories with swatches and counts, search on top, the two new securities in the pinned Unsorted bucket. No form occupies the sightline.
5. He multi-selects both rows and drags them onto a category; the count ticks up, the toolbar disappears with the selection.
6. **Climax:** he hits `+`, a compact disclosed form opens, he adds one category, and the form closes back to nothing — the screen that used to greet him with a wall of inputs now only shows them for the seconds he wants them.

Failure: re-dropping the same file → preview reports the content-hash match and applying changes nothing, and says so.

### Flow 3 — UJ-6 — Switching scope [ASSUMPTION]

*Rewritten 2026-08-05.* The previous version of this flow ("the family view") depended on issue #327 — moving depots between portfolios — which ADR-0024 supersedes: **moving becomes a tag edit**, and views, not portfolios, are the user-facing grouping.

1. Andi wants to look at a narrower slice than "Everything". He opens **Views** (Administration) and confirms the view he wants exists — a set of buckets included, another excluded.
2. Buckets are attributes, not destinations: he assigns the missing depot its bucket tag from the chip on its row in **Accounts & depots**. No entity is moved; a tag changes.
3. Back on **Wealth**, he switches the active view. Holdings, allocation, performance and the KPI band all re-scope; the basis line names the active view alongside the as-of date and currency.
4. Values go **pending**, then **settle**. The count-up is the "different data now" texture; the scope label, not the motion, carries the meaning — under reduced motion the label is the only cue and it is enough.
5. Where the view's buckets overlap, the surface says so rather than hiding it: each account is counted exactly once in the total, so per-bucket figures may overlap and must not be summed. This is a **note**, adjacent to the total.
6. **Climax:** one instance, one operator, several scopes, zero bookkeeping about which data is on screen — because every scoped surface states its scope.

Failure: a validation error while recording a transaction in the new scope → inline field error, the form stays open with the input intact, nothing half-writes (ledger atomicity, FR-2).
