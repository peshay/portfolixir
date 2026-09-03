---
layout: docs
title: Product Documentation
description: Portfolixir app handbook for current local portfolio tracking behavior.
lang: en
lang_en: /product-documentation.html
lang_de: /de/product-documentation.html
---

# Product Documentation

## Overview

Portfolixir is a self-hosted, local-first Phoenix application for managing a
single portfolio workflow. It is intentionally narrow:

- Manual creation of securities, portfolio, accounts, and transactions.
- Bulk import of Portfolio Performance CSV/JSON v1 transaction exports through
  a preview-and-apply workflow.
- Holdings are derived from transaction history, with cost basis and unrealized
  profit/loss.
- Classification trees organise securities; per-category target weights drive a
  target/actual allocation breakdown with drift.
- Multi-currency portfolios are valued through stored exchange rates.
- Security prices are stored as quote history and shown in a security detail chart.
- Supported functions are available through the UI, JSON API, and MCP companion.
- No broker sync, bank sync, trading engine, payment flow, order flow, rebalancing,
  document ingestion, or AI-assisted behavior.

## Product Modules

The codebase is split into local domain modules plus the web layer:

- `Portfolixir.Catalog`
  - Securities and quote entities
  - Security metadata and quote records
- `Portfolixir.Portfolios`
  - Portfolios
  - Cash accounts
  - Depots
  - Target weights and target/actual allocation
- `Portfolixir.Ledger`
  - Manual buy/sell transactions
  - Holdings calculation from immutable history
- `Portfolixir.Classifications`
  - Custom and built-in classification trees and assignments
- `Portfolixir.Fx`
  - Exchange rates and multi-currency conversion
- `PortfolixirWeb`
  - Routes, pages, LiveViews, and JSON API
- `mcp-server/`
  - TypeScript MCP companion that wraps the JSON API

Integration details for `/api/v1` and `mcp-server/` are documented separately in
[API and MCP](integration/api-and-mcp.html).

## Core Workflow

1. Create one or more securities with basic identifying data.
2. Create one cash account and one depot, and link them (no portfolio
   decision anywhere — see below).
3. Record manual buy and sell transactions with Decimal-based quantity and price values.
4. Optionally import a Portfolio Performance transaction export through
   Imports, review the preview, map missing accounts, then apply atomically.
5. Open the holdings view to verify current position per security.
6. Record security quotes over time and keep history for reproducible charts.
7. Review current holdings and quote chart behavior directly in the app.

## Securities

Each security is a first-class object with stable identity fields and market metadata.
They are the basis for all transaction and holdings calculations.

### Asset class inference

Every security carries an **asset class** field. Its value is determined at
read time by `Security.effective_asset_class/1`: if the stored value is
non-nil it is returned as-is; otherwise the name, ISIN, and ticker are
inspected in priority order:

1. **government_bond** — ISIN country-code prefix in the two-letter list of known
   government-bond issuers (DE, US, GB, FR, IT, ES, JP, …).
2. **etf** — name contains `ETF`, `UCITS ETF`, or an exact ISIN starting with
   `IE00` combined with a known fund-issuer prefix.
3. **crypto** — name matches a known coin name (Bitcoin, Ethereum, Ripple, Cardano,
   Solana, Dogecoin, Avalanche, Tron, …) or ticker matches a known crypto symbol
   (BTC, ETH, XRP, ADA, SOL, DOGE, AVAX, TRX, …).
4. **commodity** — name is an exact bare metal name: Gold, Silber, Silver, Platin,
   Platinum. (Compound names like "Barrick Gold Corp" are not matched here and
   pass through to equity.)
5. **derivative** — name contains `Knock-Out`, `Zertifikat`, or `Turbo` (including
   single-letter suffixes such as TurboP, TurboC, TurboA).
6. **knock_out** — name contains `Turbo` (any single-letter suffix), `Knockout`,
   or `KO` pattern. In practice the Turbo check is shared with the derivative
   branch; the `knock_out` class is stored explicitly when the user corrects the
   inference.
7. **equity** — name contains a legal-form suffix (Corporation, Company, Co.,
   Aktiengesellschaft, AG, S.A., S.p.A., A/S, ASA, KGaA, Azioni, Acciones,
   Aktier, Ltd., PLC, Inc., GmbH, NV, SA) or a depositary-receipt marker
   (ADR, GDR, Sp.ADR, Depos. Receipts, INH.ON, Registered Part. Shares).
8. **fund** — name starts with or contains a known fund-issuer prefix (iShares,
   Vanguard, Lyxor, Amundi, AIS-AM, Xtrackers, SPDR, Invesco, WisdomTree,
   VanEck, Fidelity, Deka) but did not match the ETF pattern above.
9. **nil** — no heuristic fired; the security is considered unclassified.

Because inference runs at read time, improving a heuristic in the code
retroactively reclassifies all matching securities without a data migration.

#### Finding and fixing unclassified securities

A search or filter combination that matches nothing shows a *no matches*
state naming the query or the active filters, with the controls still
visible; the "no securities yet" onboarding hint appears only when the
database holds no securities at all.

The securities list accepts an **"is unclassified"** filter on the asset-class
column (`operator: :is_nil`). It returns all rows where the stored value is nil
and `effective_asset_class` also returned nil — i.e. the heuristics have no
confident match. For each such row the asset-class cell shows an inline
**quick-assign** dropdown, so the class can be set directly from the list
without opening the security detail page.

A stored class is a permanent override: once set it is returned by
`effective_asset_class` regardless of what the heuristics would produce, so the
quick-assign choice survives any future heuristic changes.

### Deep-linkable filters

The securities list's filter state lives in the URL, so any filtered view can
be bookmarked or linked to:

- `?q=…` — the search query.
- `?holding=held|not_held` — the holding status (the *Held* / *Not held*
  chips).
- `?filter[]=column:operator[:value]` — one or more column filters, e.g.
  `?filter[]=asset_class:is_nil` (unclassified securities) or
  `?filter[]=currency_code:eq:USD`. Operators match the filter popover's
  set; unknown columns or operators are dropped.
- `?cur[]=EUR&cur[]=USD` — the currency chips; several compose as
  either/or.
- `?class[]=etf` — the asset-class chips, keyed on the **effective** class
  (stored or inferred), so they select what the list displays.
- `?since=<ISO8601>` — the **Changed since** cut (see below); the *Today /
  7 days / 30 days* chips write a concrete ISO date here, so the link keeps
  meaning what it meant when it was shared.
- `?dq=stale_quote|missing_quote|missing_logo|missing_fx` — the data-quality
  shortcut filters: no quote in the last 7 days (including none at all), no
  quote at all, no stored logo, and — issue #717 — *Missing FX*: priced, but
  with no stored rate from its currency to the base currency, so storing the
  rate empties the set. The same conditions can be picked in the filter
  control under **Data quality** — the dashboard link is a shortcut to them,
  not the only way in. The agent asks for the identical sets over
  `GET /api/v1/securities?data_quality=…` and the `portfolixir.securities.list`
  tool; all of them are one definition, so a count of N always addresses a list
  of N.

**The common filters are one-tap chips** (issue #717): a fixed, named row
above the table — *Held · Not held · Unclassified · Stale quote · No price ·
Missing FX*, then one chip per currency and per asset class in use. Chips
are toggles; different families combine as AND, several chips within the
currency or class family combine as either/or. Two of them encode a
deliberate distinction: **Unclassified** is keyed on the *stored* class (a
row whose class is merely inferred still counts as unclassified, because an
inference is a guess, not a stated fact), while the **asset-class chips**
are keyed on the *effective* class, so they select exactly what the list
displays. The generic column/operator/value builder is demoted behind
**More filters** at the end of the row; it still expresses everything it
could before, and it carries a count whenever it holds conditions the chips
cannot express — a demoted control never hides active state.

Searching, toggling a chip, or applying a filter updates the URL in place,
and selecting a security keeps the active filters. The Overview data-quality
line links here with the matching filter pre-applied.

**Changed since** (issue #731) answers "what moved lately?" from the same cut
the agent polls with: the chips narrow the list to securities created or
changed strictly after the cut, judged by the record's change instant. The
page states the property that makes such a delta honest — **deletions are not
shown**; clear the filter for the complete list. The URL parameter is the
API's `?since=` with the same accepted forms, so an agent's link opens
exactly the slice it read; an unparseable value degrades to the unfiltered
list rather than silently narrowing it.

### Classification columns

Next to the attribute and price columns, the securities list's column picker
offers one entry per classification tree **and level** — custom trees and the
built-in asset-class and currency trees alike, matching Portfolio
Performance's classification columns. An enabled column shows each security's
assigned category on that level: a security assigned to a deeper category
shows its ancestor on the chosen level, one assigned above the level (or not
assigned at all) stays blank. Classification columns sort like any other
column, with unassigned securities always last, and persist in the browser
together with the rest of the column choice. They are display columns only —
filters stay on the attribute columns.

#### Letter-spaced names from Portfolio Performance

Portfolio Performance sometimes exports names with a space between every
character — e.g. `I b e r d r o l a S . A . A c c i o n e s`. The JSON
parser detects this pattern (majority of whitespace-separated tokens are
single characters, minimum four tokens) and collapses the tokens before
heuristics run, so legal-form suffixes are reliably detected even from such
exports.

### ISIN changes (former-ISIN aliases)

When a corporate action gives a security a new ISIN (a merger rename, a
re-domiciliation), record the change instead of editing the ISIN in place:
`POST /api/v1/securities/:security_id/isin-change` (or the
`portfolixir.securities.isin_change` MCP tool) moves the current ISIN into a
journaled **former-ISIN alias** and writes the new ISIN onto the same
security. Imports then keep matching in both directions: an old export still
carrying the former ISIN resolves through the alias, and a new export with
the new ISIN resolves through the current ISIN — no duplicate security, no
duplicate bookings (the import marks such rows as "matched via former ISIN").
Aliases are correctable: they are listed on the security detail
(`GET /api/v1/securities/:id`) and can be deleted (journaled) when recorded
by mistake. A plain rename needs no ISIN change — it is just a name edit.

### Research tab (the security research log)

The detail pane's **Research** tab is the human view of the security
research log (ADR-0044): what the operator or the agent knows about a
security, as dated, sourced entries that are **never edited and never
removed**. The tab shows the derived **thesis state** on top — status
(*None*, *Intact*, *Retracted*), the current thesis text, conviction tier,
invalidation condition, time stop, when it was last reviewed and by whom, and
the entry it derives from — then the timeline **newest first**. Every entry
shows its kind (thesis, evidence, invalidation check, event result, risk,
retraction, decision), its source quality (primary source, several secondary
sources, awareness, unverified), its as-of date and its author (operator,
agent or local model; a machine-generated proposal is marked as such).

A wrong finding is withdrawn by appending a **retraction** that supersedes
it: the retraction reads "Retracts #n" with the reason, the superseded entry
stays in the list marked "Superseded by #n", and a retracted thesis is called
out above the timeline with the retraction's reason. Nothing on the surface
edits or deletes an entry, by design — the record of having been wrong is the
point of the log.

The **Append an entry** form writes an entry as the operator: choose the
kind, state the source quality (it is set, never guessed), give the as-of
date (the statement's cut-off, not today's date, when they differ), and
optionally the source link, a *valid until* date for a dated block, and the
entry it supersedes. Choosing the *Thesis* kind reveals the thesis fields
(conviction, invalidation condition, time stop). The same log is readable and
writable over the API and MCP (`/api/v1/securities/:id/notes` and the
`portfolixir.notes.*` tools), including the three hygiene reads — held
positions with no entry for N days, entries that still need corroboration,
and dated blocks expiring within N days.

## Accounts and Depots

The bookkeeping entities are cash accounts and depots:

- cash account: tracks available liquidity context
- depot/account: stores security positions linked to that cash account

The **Accounts & depots** page (Administration area) shows both in **one
table, one entity per row**: each depot renders as a row with its linked
cash account indented directly beneath it, carrying the account currency and
the labeled per-account **liquidity role** selector (free cash, credit line,
reserve); a cash account no depot links to gets its own row. A cash account
shared by several depots carries its controls under its first depot only —
later rows read *shared — managed above*.

**Bucket chips (#559).** Each row shows its bucket memberships as chips —
the exclusive **scope** bucket as a filled chip, free **tags** as outline
chips, tinted with the bucket's color when one is set. When a depot and its
cash account carry the same buckets, the pair shows **one merged chip group
marked "Both"** spanning both rows; the **Tag separately** link next to it
splits the group so each side can be tagged on its own (differing sets always
render split). At most four chips are shown per group — further chips
collapse into a **+N** chip, and the picker carries the full set. Long names
(for example date-stamped import tags) are truncated; hovering a chip reveals
the full name. The chips are the grouping UI: the **+** affordance opens a
small picker popover with the remaining buckets plus an inline **New tag**
field that creates and assigns a tag in one step, and the **×** on a chip
removes that membership. Edits on a merged group apply to the depot and the
cash account together. Every change is written through the audit-journaled
bucket context; trying to add a second scope bucket is rejected with an
inline message, because the scope dimension stays exclusive (ADR-0024).

**One creation dialog (#491).** The **Add depot & account** button opens a
modal that creates a depot together with its linked cash account in one flow
— or a cash account alone, or a depot linked to an existing account. The
dialog optionally applies **initial buckets**: check existing buckets and/or
type one new tag, and every record the dialog creates starts out with that
membership.

**No portfolio decision is required anywhere** (ADR-0024): grouping happens
exclusively through buckets and views. When a depot or cash account is
created — in the dialog or over the API/MCP — its internal binding resolves
to one deterministic default portfolio (the earliest record, or a freshly
created "Default"), without asking.

For worked examples — a household split, strategy views with their own target
plans, translating Portfolio Performance habits, and excluding a position from
steering — see the [Buckets & Views Guide](guides/buckets-and-views.html).

### Portfolio records (compatibility)

Portfolios remain in the schema, the JSON API, and the import path as
**internal compatibility records** only. The **Accounts & depots** page in the
Administration area carries a collapsed, read-only **Portfolio records
(compatibility)** panel listing every record — name, base currency, creation
date, source (UI, API, Import, or Seeded, derived from the audit journal) and
the count of bound depots and cash accounts — so records created over the
API/MCP can never become invisible. There is no create or edit UI; the API
write endpoints are deprecated (see
[API and MCP](integration/api-and-mcp.html)) and a follow-up story merges the
records into buckets and views after two releases without external portfolio
writes.

## Transactions and Holdings

### Manual Transactions

Transactions are explicit and auditable. A transaction defines:

- date
- security
- direction (buy/sell)
- quantity (Decimal)
- unit price (Decimal)
- optional taxes, fees, and notes

A transaction is booked in the currency of its linked cash account. Its
currency must match that cash account's currency (and, for a cash transfer,
the counter cash account's currency too); a mismatched booking is rejected
rather than silently converted. Record the booking against a cash account in
the same currency, or add one. No exchange-rate conversion of stored amounts
happens here — exchange rates are only applied when valuing a portfolio in its
base currency.

While entering a **sell**, the form previews which FIFO purchase tranches
(lots) the sale would consume and the resulting **gross gain** per tranche
and in total — sale proceeds minus the FIFO purchase cost of the consumed
lots, before fees, priced at the entered price (or the latest stored price
until one is typed). The figure is indicative and not a net figure; booking
the sale changes nothing about how the cost basis is stored (holdings keep
their moving-average basis, the trades tab keeps the FIFO matching). Lots
are matched first-in, first-out across all depots, split-scaled like the
trades view, and cross-currency tranches carry the same price/currency
decomposition as the holdings — or an honest dash when it cannot be derived.
An entered quantity larger than the open lots is flagged with the uncovered
shortfall.

### Reading the History

The transaction history is filtered with **chips** above the table: one per
cash account, and one per transaction kind actually present. Chips are
toggles. Two chips of the same family mean "either of these" — two accounts
show both accounts' bookings; a chip from each family narrows to their
overlap. The less common conditions — security, date range, free-text search —
live behind **More filters**, which carries a count whenever it holds an active
condition, so a demoted control never hides what is filtering the list.

Narrowing to **exactly one account** adds a **Balance** column: the balance
that account stood at after each booking, in the account's own currency. Two
properties of that column are worth knowing:

- it is the same arithmetic as the account balance itself, so the most recent
  row equals what the accounts page shows;
- it is computed over the account's **whole** history, not over the rows on
  screen. Narrowing the dates changes which rows you see, never what the
  balance was.

A row that does not move the selected account — a delivery, a split — shows a
dash rather than repeating the previous row's figure.

The rows are sectioned by month, and both the month subtotals and the summary
above the table state **one total per currency**. Amounts are the gross booked
amounts and are never converted or added across currencies; converting them
would make them a different figure needing its own rate basis.

Beside the account and type chips sit the **Changed since** chips (*Today /
7 days / 30 days*, issue #731): they narrow the history to transactions
created or changed strictly after the cut — **by record change, not booking
date**, so an edited old booking shows up while an untouched recent one drops
out. The note under the chips states the cut and the property that makes a
delta honest: **deletions are not shown**. The cut rides the URL as
`?since=<ISO8601>` — the same parameter, forms and semantics as the API's
delta read, so a link the agent hands over opens exactly the slice it read; a
garbled value degrades to the full history. The Balance column is unaffected
by this filter, like by every other: it is always computed over the account's
whole history.

**Columns** (issue #732) opens the history's column picker — the human half
of the API's `fields=` sparse fieldset. Beyond the default set (date, type,
security, quantity, price, currency) it offers the fields every booking
already carries but the table never showed: gross amount, fees, taxes and
notes. The choice is stored in the browser and survives a reload. The
Balance column is deliberately not in the picker: it stays governed by its
own rule — it appears exactly when the chips narrow to one account — because
a picker that could summon it outside that narrowing would show a
meaningless figure. The **Current holdings** panel beside the history has
the same picker: its default Depot / Security / Quantity view expands to the
valuation columns the agent reads over the holdings API — ISIN, WKN,
currency, average cost, latest price, market value and unrealized P&L — and
the figures are that projection's own numbers, not a second calculation.

### Holdings Calculation

Current holdings are not entered manually. They are derived from all
transactions over time, so the state is reproducible and traceable. Held
quantities move with buys and sells, with inbound/outbound **deliveries**
(shares entering or leaving without a cash leg, e.g. a depot transfer from
another bank), and with **security transfers** between own depots. Each
holding also carries a moving-average cost basis and the unrealized
profit/loss (absolute and percentage) against the latest stored price, in the
security's own currency. The cost basis follows the shares: buys (and inbound
deliveries recorded with a price) add cost, sells and outbound deliveries take
it out at the running average, and a security transfer carries the cost of the
moved shares into the receiving depot. A delivery recorded without a price
moves quantity at zero cost, since no own purchase cost is known for it.

For a security quoted in another currency than the money that paid for it,
each holding additionally splits its base-currency gain or loss into two
named parts (ADR-0033): the **price return** — the change of the security's
own price, converted at today's rate — and the **currency return** — the
effect of the exchange rate on the amount originally invested. Together they
equal the position's total gain or loss in the base currency, exactly. For
positions in the base currency the currency return is exactly zero. A
position whose split cannot be derived from the recorded bookings (for
example an imported cross-currency trade with no stored rate at its booking
date) shows a dash instead of a guessed number; the
`mix portfolixir.backfill_settlement_legs` task derives the missing legs
for historic imports once rates for the booking dates are stored.

## Classifications, Targets, and Allocation

Securities can be organised into **classification trees**. Custom trees are
free-form folders with colours; built-in trees for **asset class** and
**currency** are derived from each security and always present. Built-in
tree names display through the locale (issue #729 — DE *Anlageklasse* /
*Währung*), keyed on the tree's stable key; your own trees keep the name you
gave them in every language. The asset-class
tree is an editable taxonomy: a security's class is seeded from an inferred
default and corrected by dragging it between categories.

Each portfolio can store a **target weight** per category (a fraction of the
portfolio, for example 25%). The **allocation** breakdown then compares, per
category, the actual weight (its share of the valued positions) against the
stored target and reports the **drift** — actual minus target (positive =
overweight, negative = underweight; ADR-0023), both as a weight and as a
base-currency amount, i.e. how much to sell (positive) or buy (negative) to
reach the target. Securities held but not
assigned in the chosen tree are summed into an unassigned bucket. Only the
targets are stored; the actual side is derived from the live valuation on read.

A plan does **not** have to add up to 100%. Leaving it short on purpose — say,
because one satellite category is deliberately not fully used — is a legitimate
plan, and the gap is shown as an **unallocated remainder**: a named part of the
plan meaning "this share is deliberately not steered", not a mistake. Drift is
then measured against the portion you actually steer, so the unallocated share
is not spread across the categories that do carry a target as deviations you
cannot act on. A warning is reserved for the two states that really are wrong:
a plan summing to **more** than 100%, and a position-vs-category conflict.

Each category on the **Classifications** page also states what it **cost**, what
it is **worth** now and what it has **made** — in euro and as a percentage. The
percentage is money-weighted: the sum of the results divided by the sum
invested, never the average of the members' own percentages, which would let a
tiny position at +300 % dominate a category that is flat in money.

Read the basis, stated once above the tree: these figures cover **the positions
filed in the category today**. They are a statement about the current
composition, not a period return — moving a security between categories moves
its whole result with it. A position whose result cannot be derived (no usable
price, or no exchange rate to your base currency) is left out of **both** sides
of the sum and counted in the "covered of total" marker, rather than counted as
zero, which would quietly understate the category.

> **Per-position targets (ADR-0030, #481).** Target weights can now be set down
> to an **individual position** (a security under a category), not just per
> category. Positions are the source of truth: a category's *effective* target
> rolls up from its positions (their sum), and if a category also carries its own
> explicit weight the mismatch is surfaced rather than silently dropped. This
> first slice ships the data model and the **API/MCP** surface — set a
> position target by adding a `security_id` to a target entry, read the position
> rows and category roll-up via the position-targets endpoint/tool (see the
> integration guide). If a security is later reclassified or unassigned, its
> position target keeps counting under the category it was filed under and is
> flagged as *stale* in the position-targets read — re-file it to move the
> weight. Since slice 2a the **allocation view displays** position SOLL/drift —
> including positions not yet held (IST 0, *not held* marker) — and the
> category rows steer by the effective roll-up. The editor UI for per-position
> entry and even-split auto-distribution are coming in later slices.

### Editing a target plan on the Classifications page

Target weights are not global: a **target plan belongs to a view** (see ADR-0020).
A plan is edited on the **Classifications page**, in the **Target plan**
section of a custom tree's detail pane. At the top of that section a **view
selector** ("Target plan for view: [Gesamt ▾]" / German *Soll-Plan für Sicht*)
chooses the plan being edited; the default **Gesamt** is the portfolio-wide
plan that behaves like a single global target set. Switching the selector loads
that `(view, classification)` plan's stored weights and cash target — Gesamt and
each named view carry **independent** plans, so the same tree can hold a
different 100% plan per view, or none.

The states are:

- **No plan yet.** The section shows an empty state with **Create plan**
  (*Plan anlegen*) and, when another view already has a plan for this tree, an
  **Copy from another view…** (*Aus anderer Sicht übernehmen…*) picker that
  prefills the editor from that source plan. Nothing is written until the
  plan is saved.
- **A plan exists.** Each category gets a **Target %** input and there is a
  **Cash** target input below them; **Save plan** writes the whole
  `(view, classification)` plan at once. A live **Σ** footer sums the category
  weights plus the cash target and shows a ✓ at exactly 100% or a ✗ with the
  yellow mismatch cue otherwise, updating on input.
- **Delete plan** (*Plan löschen*) removes the view's plan; the Wealth page
  then falls back to **actual-only** (no target, no drift) for that view.

Weights are entered and shown as **percentages** (e.g. `60`), stored as
fractions in `[0, 1]`. Inputs are labelled and keyboard-focusable, and the same
plan is equally reachable over the API/MCP target endpoints with a `view`
parameter.

### Plan versions: duplicate, draft, activate

Since ADR-0027 a plan is a **named version** with a status — *active*, *draft*
or *archived* — and a scope carries at most one active plan. This is how a
strategy is restructured without losing the old plan:

- **Duplicate plan** (*Plan duplizieren*) copies the current plan (category
  weights and cash target) into a **draft**; the editor switches to it and a
  **plan version picker** appears next to the view selector once a scope has
  more than one version.
- Editing and saving a **draft** never touches the active plan — the Wealth
  page keeps following the active plan, and a hint in the editor says so. The
  **cash target** row shows the active steering value (counted into the Σ
  check) but is locked while a version is edited, with a visible note: the
  cash quote stays with the active steering until the switch (v1).
- **Activate this plan** (*Diesen Plan aktivieren*) swaps the draft in; the
  previously active plan is archived in the same transaction, so old and new
  plan stay side by side for reference.
- **Rename** (*Umbenennen*) renames the selected version — e.g. to drop a
  "(Entwurf)" suffix after activation.
- **Delete plan** on a draft or archived version removes just that version;
  on the active plan it keeps its ADR-0020 meaning (the scope falls back to
  actual-only).

Every plan write is recorded in the audit journal.

> **Migration note (ADR-0020).** The move to per-view plans is **loss-free**:
> any pre-existing target weights and the former portfolio-wide cash target
> become the **Gesamt** plan (`view = null`). Nothing changes in behaviour —
> the existing setup simply appears under *Gesamt*, and the Wealth page reads
> it under the **Total** view exactly as before. Named views start with **no
> plan** until one is created or copied.

To keep a position **out of the allocation steering basis** while it still counts
toward total wealth — for example a Bitcoin held as a long-term store of
value rather than part of the steered mix — tag the security with a **bucket** and
**exclude that bucket from the strategy view**, then read allocation under
that view. The position then falls outside the view's scope: it disappears from
the 100% and the drift table, raising every other category's actual percentage
consistently, while total value, holdings, and performance (read without the
view) are unchanged. (This replaces the former per-security "excluded from
allocation targets" flag; see ADR-0013/ADR-0018.)

Classification trees are **hierarchical**, and the allocation rolls them up: a
position assigned to a sub-category counts toward that sub-category **and every
parent above it**. So if *Growth* holds a 50% target and holdings are assigned
only to its sub-categories (*Tech*, *Emerging*, …), *Growth*'s actual
weight is their sum — not 0% — and its drift is measured against that sum. The
drift table lists categories in tree order with sub-categories indented under
their parent; because each parent already includes its children, the displayed
actual percentages add up to 100% only across the leaves (plus unassigned),
not across every level.

Targets stay **loose on purpose**: a weight can be set at the top level and at
sub-levels without the app forcing them to add up. To keep that freedom while
making divergence visible, the Wealth page shows two **advisory consistency
hints** — read-only, never blocking a save:

- A subtle line under each parent that has child targets reads
  *subcategories: X% of Y%*, where X is the sum of the direct children's
  targets and Y is the parent's own target. It turns **yellow** when X and Y
  differ.
- The allocation header shows *Σ target top level: Z%* — the sum of the
  top-level categories' targets **plus the cash target** — highlighted when Z is
  not 100%.

Equality is checked exactly (to the stored weight precision), so a hint only
highlights when the numbers genuinely differ. The hints are guidance only; the
target save path is unchanged and never rejects freely chosen weights.

**Cash is part of the allocation.** A portfolio can store a **cash target**
(`cash_target_weight`, e.g. 5%) — the target share of cash inside the same 100%
basis as the categories. With a cash target set, the allocation's 100% basis is
**securities (within the active view) + the deployable cash** (free-cash accounts
with a non-negative balance). The drift table then shows
a dedicated **Cash** row in its own neutral colour with the cash actual, target
and drift, the sunburst gains a cash segment, and every category percentage
shrinks accordingly once cash joins the basis. Set the cash target in the plan
editor's **Cash** input on the Classifications page (per view), or over the API
(`PATCH /api/v1/portfolios/:id`) or MCP (`portfolixir.portfolios.set_cash_target`),
or clear it with `null` to stop steering a cash quote.

**Currency allocation: cash by currency.** When the active classification is
the built-in **Currency** tree, each cash account's balance is attributed to its
own currency bucket instead of appearing as a separate "Cash" lump: EUR cash
flows into the EUR category, USD cash into USD, and so on. Foreign-currency
balances are converted to the base currency via the EUR hub before being added,
so the percentages stay in the portfolio base currency. The total basis
(securities + deployable cash) is unchanged — only the *attribution* of cash to
a currency category changes. This gives a complete view of currency exposure
including cash without a separate row. The asset-class view is unaffected:
it keeps cash as its own **Cash** steering row.

## Exchange Rates and Valuation

Portfolios can hold securities and cash in several currencies. Exchange rates are
stored against a EUR hub (with European Central Bank sync), and other pairs are
triangulated through it. The live portfolio valuation converts each position's
market value and each cash balance into the portfolio base currency.

A security without any quote yet is priced at the **latest own trade price
across all portfolios** — a buy or sell is a price observation, exactly how
Portfolio Performance seeds prices from bookings — so a freshly imported
portfolio is not valued at zero while quotes are still being fetched. The
fallback is deliberately global: the portfolio totals and the security detail
resolve prices with the same semantics, so the two screens can never disagree
about whether a price exists. Such positions carry `price_source: "trade"` in
the API and are counted in `trade_priced_count`; the Wealth page flags them
as a data-quality hint and the security detail states the trade price it is
valued at.

A position with neither a quote nor a trade price, or with no rate path to
the base currency, is reported as unvalued, so a missing price or rate never
silently distorts the total or the weights. The two cases are reported
honestly and separately (`unvalued_reason` in the API): **no price at all**
(nothing resolves — no quote and no own trade), or **price known but no
exchange rate stored** — the native price is still shown with its currency,
and syncing exchange rates brings the position into the totals. A position
with a price but no exchange rate counts as *not valued* in base-currency
totals. The security detail shows the matching status line ("Not counted in
the portfolio totals — …"), so both surfaces explain a missing value the
same way.

## Cash and cash quote

Cash is part of the portfolio, not an afterthought. Each portfolio has one or
more cash accounts, and the live valuation reports the **total cash**, the
**total including cash**, and the **cash quote** — cash as a share of the whole
portfolio — liquidity and dry powder at a glance, converted
into the portfolio base currency.

A depot's settlement cash stays up to date on its own: buys, sells, dividends,
interest, fees and taxes move it as those transactions are recorded, so the
cash that belongs to investing needs no separate upkeep.

For external accounts (a current account, savings, a business account), the goal
is visibility without bookkeeping. Instead of mirroring every booking, an
account's **balance is set directly** — the figure the banking app shows,
entered as a dated **snapshot** (the per-row **Set balance** dialog on
Accounts & depots, `POST /api/v1/cash_accounts/:id/balance`, or the
`cash_accounts.set_balance` MCP tool). The balance then anchors to that amount,
and only bookings dated strictly after the snapshot change it; so moving money
between own accounts needs no transfer entry — each balance is simply restated
now and then. The amount may be negative (an overdraft), and the same
snapshot can later be filled automatically over the API (a script or a read-only
bank export) — without turning Portfolixir into a banking app. This follows the
design recorded in
[ADR-0009](decisions/0009-cash-as-balance-snapshots.html).

Each cash account carries a **liquidity role** (the selector sits next to the
account on the Accounts & depots page; the API/MCP field is `liquidity_role`). It is
one of three values: **free cash** (the default — genuine deployable cash),
**credit line** (an overdraft or Lombard facility, whose negative balance is a
liability and whose unused headroom is never liquidity), or **reserve** (a
visible but excluded bucket, e.g. a business account). Only free-cash accounts
with a non-negative balance count as deployable cash and enter the cash quote;
a credit line never counts (even when its balance is positive — type beats
sign), and a reserve is always excluded. Every account still shows in the total
cash, so a drawn credit line correctly reduces net worth, but the quote is
computed over deployable cash only and never reports fake liquidity. The
Wealth page mutes non-deployable rows and labels them with their role.

## Overview Page

The **Overview** entry (the start page) answers "did anything change, does
anything need me?" (ADR-0022). With an empty database it is the onboarding
wizard (the ordered workflow path plus entity counts). Once transactions
exist it shows one **value card scoped to the default view** — **Everything**
when none is set (ADR-0024: views, not portfolios, are what the dashboard
aggregates over) — with the total incl. cash, the **YTD TTWROR** as the
change signal and the cash quote, an **Off target** list (issue #718 — the
card is named for what it contains, per UX-DR21) — every targeted category whose
allocation drift exceeds **±5 percentage points** (ADR-0023 sign: positive =
overweight), worst first, each linking into the Wealth area's Allocation &
targets tab, under a basis line naming the view, classification tree and
active plan the drift steers against (or that several plans are active, or
none) — and the **data-quality line**: one note listing the securities
without a recent quote, asset class, or logo, each count linking to the
securities list pre-filtered to exactly that set. The line renders only when
at least one count is non-zero; a clean catalog shows nothing (no all-clear
badge). There is deliberately no activity feed: the audit journal owns the
forensic detail.

## Wealth Page

The **Wealth** entry in the navigation opens the wealth overview, organised
into tabs (ADR-0022): **Holdings** (value, performance, data quality, cash),
**Allocation & targets** (the sunburst and drift table), and **Cash flow**
(the received dividends and interest report). The Holdings tab shows the
total value including cash, the cash quote, the TTWROR and the
money-weighted **IRR** for a selectable period (year-to-date, one/three/five
years, or since the first transaction; one year is the default) with the
cumulative performance chart. Beside them sit the **invested capital** —
always two labeled numbers, the value at the period start and the net
external flows (deposits minus withdrawals, deliveries at transaction
value), never one merged figure — and the **wealth multiple**: end value ÷
invested capital, the honest "what the money put in has become". When net
invested capital is zero or negative the multiple reads `n/a` — never a
negative multiple. For windows shorter than a year the money-weighted KPI
is labeled **MWR** and shows the period figure instead of an annualized
one, which would explode a short window (ADR-0034). Beside the fixed buttons, a year dropdown
chains any single calendar year with data, and a from/to date range chains a
custom span — both are pure re-chains of the already-computed series, clamped
honestly to the available history (a backwards range is refused with a short
note). On the **Allocation & targets** tab, the **allocation sunburst**
shows the classification as concentric rings — the inner ring is the top-level
categories, each outer ring breaks one level down with sub-category arcs nested
inside their parent, and the **outermost ring shows the individual positions**
as shaded arcs of their category's colour (the Portfolio Performance style) —
with a grey slice for unassigned holdings. Categories without a chosen
colour are assigned distinct palette colours automatically, so an unstyled
tree stays readable. Like PP the slices carry no
in-chart text: hovering a slice shows its name, share and value in an
**instant custom tooltip** that follows the pointer (no browser hover delay),
and a slice can be **tapped** to echo the same below the chart (the mobile
substitute for hover). With JavaScript disabled the slices fall back to the
native browser tooltip. The chart scales to the available width. Pick any
classification tree from the selector. The drift table beneath it lists every category in tree
order with **sub-categories indented** under their parent, comparing the
rolled-up actual weight against the stored target and restating the drift in
the base currency. The tree starts collapsed at the
top level; every row with children carries a **toggle (▸)** — the whole
category-name cell is clickable — that reveals its direct children —
subcategories and positions alike (the grey *Unassigned* bucket expands the
same way into its member securities) — and a single **Expand all / Collapse
all** toggle above the table opens or folds the whole tree down to the single
position. Beside it sit the **drift-threshold chips** — *Deviating by ≥ 1 pp
/ ≥ 2 pp / ≥ 5 pp*: picking one narrows the table to the categories that
actually deviate by at least that much, in either direction, and clicking the
active chip clears it again. Three things are worth knowing. The 5 pp step is
the same threshold the dashboard's attention list uses, so the alerts and this
table agree on what needs attention. A filtered table is **flat** — a kept
category shows even when its parent is under the threshold and therefore gone
— and it always keeps the *Cash* and *Unassigned* rows, which the line above
the table states along with how many of how many categories are showing.
Finally, the threshold rides the URL (`?drift=5`), so a bookmarked or shared
link reopens the same filtered view; it is the same filter the API and MCP
offer as `min_drift=` (a weight fraction there: 5 pp is `min_drift=0.05`).

What the pp is measured against matters when a plan deliberately does not sum
to 100 %: the chips use the **same drift** as the Drift column and the
dashboard's attention list, which under ADR-0040 is measured against the plan
renormalised to the allocated portion — not against the raw Target column. So
with a plan summing to 83 %, a category at 21.2 % actual against a stored 55 %
target is 45 pp off, not 34, and the chips, the Drift column, the dashboard
and `min_drift=` all agree on that number.
A **Tree | Positions** switch swaps the hierarchy for a flat
rebalancing worklist: one row per security (cash included) with its category
as context, sorted by signed drift by default (most overweight first, most
underweight last) and re-sortable via the column heads (value, drift, or
category). A category with directly assigned securities expands into its member securities, each with its value,
weight, its share of the category drift, and a display-only **rebalancing
hint**: the indicative number of units to sell (positive drift) or buy
(negative) at the valuation's price to close the gap (ADR-0023). The hint
models no fees or taxes, and there is deliberately no order button behind it —
acting on it stays entirely manual.

**Position targets show in the plan (ADR-0030 slice 2a).** When the active
plan carries per-position SOLL weights, each such position row shows its own
target and its own drift (actual weight minus its target), and a position with
a SOLL set but **no holdings yet** still appears — with IST 0, a *not
held* marker (inside a named view it reads *not held in this view*, since the
view says nothing about the whole depot), the full underweight drift, and a
buy hint priced at the latest stored quote — the hint's tooltip names the
quote date it is priced at. Without any quote a *no quote* chip explains the
missing unit hint (add a price to get one). "Held" means the position is held
at all: a held security whose price cannot be determined keeps its
data-quality hints and is never re-labelled *not held*. A position row is
hidden only when its SOLL is 0 or absent **and** its holdings are zero. The
category's Target column then shows the **effective** target — the sum of its
position targets (positions are the source of truth); if the stored category
weight disagrees, or a position target has gone stale (its security was moved
or unassigned), a **data note above the table** states it and names the
categories (issue #719 — findings render as notes, never as pills inside
data cells; a conflict at problem severity, a stale target at attention),
and the affected position row itself carries a *stale target* chip. A
held-but-unassigned security with a (stale) position target shows that target
on its row in the *Unassigned* bucket too. When no top-level category carries
a target but deeper categories do, the Σ header adds the deeper targets'
sum ("targets deeper in the tree") instead of showing a bare 0%. The cash
section lists each account's balance read-only and links to **Accounts &
depots**, where each cash-account row shows its balance with the as-of date
and opens a small **Set balance** dialog with the account already chosen:
enter the balance the bank shows and the snapshot is recorded without
booking individual transactions.

**The page scopes to a view (ADR-0024).** The header totals and the cash
section follow the **active view across all portfolios** — **Everything**
(German *Alles*) is the built-in default and shows every holding, each account
counted exactly once. Pick a view in the **view switcher** at the top of the
page — its **Views** link (issue #720: renamed from "Manage…", ellipsis
dropped because it navigates rather than opening a dialog) opens the Views
page where views and their
buckets are edited; **Set as default** (*Als Standard festlegen*) remembers the choice
server-side, so the Wealth page and the Overview page open on that view
whenever no other view has been explicitly picked (an explicit pick — including
Everything — always wins). When the active view's buckets share an account, a
badge next to the total — *Overlapping buckets — accounts counted once* —
states that per-bucket figures overlap and must not be summed; the total
itself is already deduplicated. View-scoped performance series carry the label
*Composition as of today* (*Zusammensetzung per heute*): the view's current
bucket membership applies retroactively to the whole history, and bucket
changes are recorded in the audit journal. After the one-time ADR-0024
migration that turned each portfolio into a bucket and a view of the same
name, the page shows a **dismissible notice** listing the seeded views; the
dismissal is remembered. (Migrated an empty database and restored data
afterwards? Run `mix portfolixir.seed_scope_buckets` once to seed the
missing bucket/view pairs — it is idempotent.) The default view is also readable and settable over
the API (`GET`/`PUT /api/v1/settings/default_view`) and the MCP tools
`portfolixir.settings.get_default_view` / `set_default_view`. Worked
click-by-click setups (household split, strategy views, PP-migration habits)
are in the [Buckets & Views Guide](guides/buckets-and-views.html).

**The target side follows the active view (ADR-0020).** The drift table's
Target, Drift and *Σ target top level* columns reflect the **active view's plan**
for the selected classification — actual and target always move together. Switch the
**view switcher** at the top of the page and both sides swap to that view's plan
at once, so two plans are never mixed into a >100% Σ or a ghost row. The
built-in **Everything** view (formerly labelled *Total*) reads the
portfolio-wide **Gesamt** plan. A subtle dot on
a view-switcher chip marks the views that already carry a plan for the current
classification, so steered views and actual-only ones are distinguishable at a
glance.

**No plan for the active view?** When the active view has no plan for the
selected classification, the allocation stays **actual-only**: the sunburst and the
Value/Actual columns still show the actual allocation, but there are no Target,
Drift or Σ columns. In their place a hint — *No target plan for this view*
(German *Kein Soll-Plan für diese Sicht*) — explains the empty target side and
**deep-links into the Classifications plan editor with that view and
classification already selected**, so the plan can be created without re-picking
either. The cash row's target likewise comes from the active view's plan cash
target (or shows a dash when none is set).

The page paints immediately and computes its figures **asynchronously**; each
section fills in when its data is ready. The expensive daily performance walk
runs once and is cached on the page — switching the period re-chains the
cached series, so the period control responds instantly. The period tokens
(YTD, 1Y, 3Y, 5Y, Max) and the %/value series toggle render as segmented
controls; a previous-year pick and a from/to custom range (ISO dates,
`YYYY-MM-DD`) sit behind the **Custom range…** disclosure next to them. The
range pair is labelled and validates as a range (issue #721): a backwards or
unparsable entry is refused with the message on the field that can fix it,
and an applied custom range shows itself as an active chip carrying the
resolved dates in the period control — the control always answers "what am
I looking at". The security detail chart's custom range behaves the same
way.
The chart is
downsampled to a bounded number of points, so a decade of daily history stays
light in the browser. The chart's **Data as table** disclosure holds
insight-level summary rows — one per year, or per month for periods up to a
year — with the start and end value, the slice's own TTWROR and its net
external flows, instead of a daily dump. Money and percentages follow the chosen language
(German `1.234.567,89`, English `1,234,567.89`; money always with two
decimals).

A **data-quality panel** appears above the chart when something would
otherwise silently skew the figures: positions valued at their last trade
price because no quote exists yet, positions with no price at all (excluded
from the totals, listed by name), positions whose price is known but that
lack an exchange rate to the base currency (excluded from the totals; listed
with their native price, showing what a rate sync would bring in),
securities whose derived holding quantity is **negative** — impossible for a
real holding, usually import debris from an unmodeled corporate action —
listed per depot with the security's total across all depots and linked to
the security's transactions so the history can be repaired (nothing is
repaired automatically; the split wizard remains the only guided repair),
and bookings with implausible dates (before 1970) that were applied on the
first plausible day instead. Negative-quantity positions are also marked
with a "negative quantity" chip wherever they appear: in the allocation
table, in the classification tree and on the security's holdings tab.

## Performance (TTWROR)

Portfolixir reports the **true time-weighted rate of return** the way Portfolio
Performance does: the portfolio is valued every day from the first transaction
onward, money put in or taken out (deposits, removals, deliveries, and
balance-snapshot jumps) is neutralised, and the daily returns are chained. The
result measures how well the **investments** performed, regardless of when cash
moved — dividends, interest, fees and taxes count as part of the return.

**Holdings without quote history** are valued at their own last trade price
(the same fallback the data-quality panel lists). Such a position sits flat
between trades, and the day a new trade sets a different price the whole
previously-held quantity would re-price in one step. That step is a change of
valuation basis, not a market move, so it is neutralised the same way a deposit
is and does not enter the return — otherwise those steps compound into a
percentage no market ever produced. What still counts: **selling**. A sale turns
the position into real cash, so its gain against the price the position was
carried at stays in the return and is never swallowed. Everything else the day
re-prices — the quantity still held, the quantity bought, the quantity delivered
out — is basis. This applies to a position with **no quote at all**. Once a
quote has landed the position is measured: later gaps in the feed are just gaps,
and the trades filling them count as return again. The **first** quote for a
previously unquoted position is itself a basis step, not a one-day jump —
loading history that only covers recent dates would otherwise report years of
accumulated drift as a single day of return. Value, net external flows and the €
gain beside the percentage are unaffected — they keep reporting the money as
booked, so a trade-price-valued portfolio can show a substantial € gain next to
a near-zero TTWROR.

Next to it Portfolixir shows the **money-weighted return (IRR)** — the single
annualised rate that discounts the period's dated deposits, withdrawals and the
terminal value back to zero, the figure Portfolio Performance shows beside
TTWROR. Where TTWROR ignores the timing of cash flows, the IRR reflects it, so
the two read differently when money moved at good or bad moments. The IRR shows
`—` when there is no rate to compute (no flows of both signs, or the solver does
not converge).

Because a max-period TTWROR in the thousands is *not* a wealth multiple (it
says what one unit from day one would have become, not what the actual money
did), the same summary also carries the money-weighted companions
([ADR-0034](decisions/0034-money-weighted-metrics.html)): **invested
capital** (period opening value plus net external flows), the **wealth
multiple** (end value ÷ invested capital; `n/a` at zero or negative net
invested — never a negative multiple) and the **period MWR**, the
non-annualized form of the IRR that short windows display. Exactly four
transaction kinds count as external flows — deposit, removal, inbound and
outbound delivery (at full transaction value) — plus the balance
adjustment's jump; everything else (dividends, interest, fees, taxes,
buys/sells, internal transfers) is performance, not flow. Multi-currency
flows convert at the flow date's stored rate through the EUR hub, so the
result is the EUR-investor's return including currency effects. The API
response and both performance MCP tools expose `invested_capital`,
`wealth_multiple` and `mwr` as Decimal strings alongside `ttwror` and
`irr`.

Performance is shown on the Wealth page and available per period —
year-to-date, one, three, or five years, since the first transaction, a
single calendar year (`year=YYYY`), or a custom `from`/`to` date range —
over the API
(`GET /api/v1/portfolios/:id/performance`) and the
`portfolixir.portfolios.performance` MCP tool, optionally with the full daily
valuation series for charting. The method and its trade-offs are recorded in
[ADR-0010](decisions/0010-ttwror-performance-series.html).

### While a series recomputes

The daily performance series is remembered between page loads and recomputed
when data changes (a booking, a quote, an exchange rate). While that
recomputation runs, the page shows the **last computed series** instead of a
loading skeleton — always labelled with exactly what it contains: how many
bookings, through which date, computed when, as of which day. The label is the
contract: a superseded number never appears without it, the swap to the fresh
series happens in one update, and if the recomputation fails the label becomes
an error instead of letting the old number stand. The overview page's wealth
card serves its last known YTD figure the same way. (ADR-0032.)

## Cash flow

The **Cash flow** area (`/cashflow`) is where money movements are read
retrospectively. It exists as an area rather than a single "income" page
because three of the analyses that belong here are not income at all —
realized gains from sales, deposits and withdrawals, and costs — and putting
them under one label reproduces exactly the ambiguity this app was built to
avoid. Each analysis is its own named facet, and a facet appears only once its
data exists; nothing renders as an empty shell. **Income** is the default
facet, and `/income` still resolves — it redirects here, so older links
and bookmarks keep working. Since issue #724 the area carries a second-level
facet switcher.

**Realized gains** (`/cashflow?tab=realized`, issue #724) answers "what did
selling actually make": FIFO-matched realized P&L across all securities,
grouped by each sale's **close date** into a year × month matrix. The FX
basis is stated on the surface and travels in the API payload (decision D-1):
each sale converts through the EUR hub at the rate stored on **its own close
date**, because a realized figure is a historical fact tied to its date. A
sale with **no** stored rate for that day is **excluded from every total and
named** in an attention note (count and securities) — never converted at a
neighbouring date's rate, never silently dropped. The daily rate sync fetches
*current* rates and cannot fill a past date, so the note carries the remedy
that can: **Backfill historical rates** fetches the historical ECB series
once, stores every published day, and re-reads the facet — the excluded sale
converts at its own close-date rate the moment that date has one (issue
#737). The limit that remains is stated next to the control: a day the ECB
did not publish (a weekend, a currency it does not list) stays excluded and
named. The same backfill is `scope=history` on the exchange-rate sync
endpoint and MCP tool; the deposits-and-withdrawals and costs facets carry
the same control in their exclusion notes.

**Deposits & withdrawals** (`/cashflow?tab=flows`, issue #725) is the
owner's "Ersparnis": what was put in and taken out, per period, as two
series with a yearly net — separate from what the portfolio earned. It
counts the **booked** deposits and removals only, and says so: securities
delivered in or out and balance-snapshot jumps are not in this number, while
the performance's invested-capital figure does count them — the surface
states that difference instead of leaving two disagreeing figures to be
discovered. Same FX basis and the same excluded-and-named rule as the
sibling facets, with unconvertible flows named by their cash account.

**Costs** (`/cashflow?tab=costs`, issue #726) is what the portfolio cost to
run: fees and taxes per period, as two series with a yearly total — at
**overview level only**, deliberately not a per-transaction cost ledger. It
sums the fee and tax **legs** riding any transaction plus the standalone fee
and tax bookings, and nets tax refunds against taxes; it never sums gross
amounts, whose fee-inclusiveness differs between buys (inclusive) and sells
(net) — the surface states that rule in its composition line. Same FX basis
and the same excluded-and-named rule as the sibling facets, with
unconvertible costs named by their currency.

Every figure on the area says what it contains: the Income facet states that it
covers *dividends and interest* and that it **excludes** realized gains,
deposits and withdrawals, and costs. That is not decoration — those omissions
are the reason the other facets exist, and a reader who does not know them
reads the page as "all the money that came in".

### Income (dividends and interest)

The **Income** facet is the retrospective income report: the dividends and
interest already booked in the ledger, with no external data or forecast. It
shows an **annual overview** — a year × month matrix split into a *Dividends* and
an *Interest* series, each year with a totals column — and a **per-position
table** with, for each security, the gross paid, the withheld tax, the net, the
number of payments and the date of the last one. A dividend's **gross** is the
net cash credited plus the withheld tax recorded on the transaction; interest
(Portfolio Performance INTEREST: account interest or bond coupons) carries no
withholding and is tracked as its own series next to dividends. Clicking a year
opens the per-transaction detail for that year.

The year bars above the matrix are **stacked**, not summed: dividends and
interest are two segments, so the chart and the table can never disagree about
what the number is. Drilling a year adds an **accumulated** series across its
months — the running total, so a quiet month reads as a plateau rather than as
a gap, and the shape answers "where did the year stand by April" instead of
"what came in in April".

Amounts are reported in the portfolio's base currency; the original currency
stays visible on each row. The conversion methodology (EUR hub at each booking
date's stored rate — the same conversion the valuation uses) sits behind the
ⓘ affordance next to the currency line. The report is also
available over the API (`GET /api/v1/portfolios/:id/income`) and the
`portfolixir.portfolios.income` MCP tool.

## Snapshots (what if I had kept it?)

The **Snapshots** tab of the Wealth area freezes "the holdings I have right
now" as a named marker and later answers: **would I have done better keeping
exactly those holdings?** Create a snapshot before restructuring a strategy,
trade on, and come back to compare.

A snapshot is a pure **ledger marker** — a name, a scope (a bucket view or
*Everything*) and an as-of date. It copies **no** transactions, quantities or
prices: the state it represents is derived from the transaction ledger on
demand, so a snapshot can never drift from the data, and deleting one never
touches a transaction. Names are unique per scope and the as-of date cannot
lie in the future.

**Compare** shows the counterfactual:

- **Frozen value then / today** — the snapshot's position set valued at the
  as-of date and valued today, buy-and-hold over the real stored quote history
  (daily closes, EUR-hub exchange rates of each day).
- **Snapshot return (price)** vs. **Real TTWROR since** — the frozen set's
  price return against the real time-weighted performance since the as-of
  date. TTWROR neutralises deposits and withdrawals, so fresh money does not
  distort the comparison.
- A chart with both series **indexed to 100%** on the as-of date (solid =
  snapshot, dashed = real), and the same data as a table.

**The two sides are not measured on one basis, and the page says so.** The
frozen side takes no trades and no flows: it pays nothing, ever. The real side
is TTWROR, which treats fees and taxes as part of the return — so every trading
cost since the as-of date depresses it, and the frozen side wins by default for
as long as those costs are unrecovered. That is precisely the window in which
this comparison is usually read.

So when trades actually cost something, three more figures appear together:

- **Real TTWROR before transaction costs** — the same daily walk with the
  window's trade fees and taxes reclassified as money leaving rather than as a
  loss;
- **Transaction costs** — their total, in the base currency;
- **Earned back?** — *yes* when the real return is already ahead of the frozen
  one; *not yet*, with the remaining gap, when it is ahead before costs but not
  after; and *behind even before costs* when the costs are not the reason and
  the changes have not paid off on their own merits.

They are always shown together and never the pre-cost figure alone — on its own
it is a number that flatters. **Transaction costs** means the fees and taxes
booked *on a trade*. Standalone fee and tax bookings stay inside the return on
both sides, because a custody charge is not caused by a trade and the frozen
holder would have paid it too; dividend withholding stays in as well, since it
belongs to the dividend gap below rather than to this one.

The **comparison is the surface**: once selected it renders first and large,
with the snapshot list beneath it and the create form behind the **New
snapshot** disclosure. The comparison is **gross and price-return only** in
v1 — dividends the frozen positions would have paid are not yet included; the
page states this as a note beside the figures. Securities without a usable
quote or exchange rate at the as-of date are **excluded and listed** in an
attention note rather than silently valued at zero. The same comparison is
available over the [API and MCP](integration/api-and-mcp.html).

## Tax (recorded broker statements)

The **Tax** tab of the Wealth area records the tax block of a broker statement
— the `Verlustverrechnungstöpfe` / `Freistellungsauftrag` section of an annual
`Steuerreport` or `Erträgnisaufstellung` — and reads the **tax-free trim
budget** off it: how much realised equity gain is still free of
Kapitalertragsteuer at that institution.

**These numbers are recorded, never derived.** Portfolixir cannot compute the
German tax pots from the ledger, and does not try — but not for the obvious
reason. Portfolixir *does* match lots **FIFO**, the method German
capital-gains taxation mandates: the [trade
list](integration/api-and-mcp.html) reports which stock each sale consumed and
at what cost. (Holdings valuation separately uses a running average, because
"what did my position cost on average" is a different question; ADR-0004 /
ADR-0011.)

What FIFO yields is a **gross gain** — and a gross gain is not a tax pot.
Four things stand between them, and none is in the transaction data:
Teilfreistellung (the partial exemption by fund type), Vorabpauschale, the
chronological order in which the allowance was consumed across *all* income at
that bank, and certified loss carry-forward from years before the first
recorded booking. On top of that, the pots are kept by the bank per
**tax-reporting institution**, and Portfolixir models depots, not institutions.
A derived pot would therefore be wrong, and invisibly so — so the statement is
transcribed instead. **The recorded statement remains the authority, and none
of this is tax advice.**

What is recorded, per institution, taxpayer, tax year and statement date: the
taxable investment income, the allowance granted and used, the equity and other
loss pots, the certified loss carry-forward, the foreign-withholding pot and
the amount credited, and the withheld Kapitalertragsteuer, Solidaritätszuschlag
and Kirchensteuer.

**Enter every amount without its sign.** A loss pot is stored as the *volume of
loss available for offsetting*, not as the negative number the statement
prints. A negative input is rejected with a message saying so rather than
silently flipped — silent sign normalisation is how a transcription error
becomes a permanently wrong number. The list view then renders the pots with
the statement's printed sign, so a recorded row stays visually comparable to
the paper.

**The trim budget** is the equity loss pot plus the remaining allowance
(`granted − used`). It is always shown **with its as-of date** and warns
**stale** only when the staleness is substantiated: when tax-relevant
bookings dated after the statement consume pots or allowance, or when the
statement is more than 90 days old. The badge names its reason — a quiet
ledger keeps an older statement usable instead of permanently flagged.
Across institutions it rolls up per taxpayer and year — always naming which
institutions it covers, quoting the as-of of its **oldest** component, and
marking itself **incomplete** when an institution has a configured
Freistellungsauftrag but no recorded statement for the year. It is a **decision
input, never an instruction**: Portfolixir does not place, store or transmit
orders.

**Self-checking transcription.** Withholding follows the closed formula of
§ 32d Abs. 1 EStG, so a recorded statement can check its own arithmetic. Two
contradictions **block the save**: allowance used above allowance granted, and
church tax withheld while the church-tax rate is zero. Everything else is an
**advisory** that never blocks anything — the withheld tax, surcharge and
church tax reconstructed from the statement, year-to-date figures that fall
between two statements of the same year, a recorded allowance that disagrees
with the configured Freistellungsauftrag, and configured orders exceeding the
year's statutory ceiling. An advisory names the two numbers and the gap; it
never proposes a "corrected" value. A tolerance band of `max(1.00, 0.05 %)`
absorbs the cents that legitimately accumulate from per-settlement rounding.

**Configuration behind it.** The statutory rates and Sparer-Pauschbetrag
ceilings are **year-scoped data**, seeded for 2009–2026 — the allowance changed
from 801/1.602 € to 1.000/2.000 € in 2023, so an older statement is checked
against the law that actually applied to it. A year with no data is reported as
missing rather than approximated from a neighbouring year. The personal
situation is an **effective-dated profile** per taxpayer: church-tax liability (defaulting
to *not liable*) and single or joint assessment. A snapshot freezes the
church-tax rate in force at its statement date, so editing the profile later
changes future entries and never rewrites a recorded one.

Everything on this page is available over the
[API and MCP](integration/api-and-mcp.html).

## Imports

The Imports page accepts Portfolio Performance transaction exports in CSV or
JSON v1 format. Files are parsed into a preview before any records are saved.
The preview shows translated transaction-kind labels, the records that would be
created, and account/depot mappings for missing targets.

Instead of asking for a target portfolio, the preview offers an editable
**bucket tag** for the accounts the import will create, pre-filled with a
date-stamped default such as `PP Import 2026-07-12`. Rename it, enter the name
of an existing bucket to reuse it, or pick *no tag* to leave the new accounts
untagged (a blank field behaves the same). Accounts mapped to existing records
keep their current tags, and an import that creates no new accounts creates no
bucket. The internal portfolio binding happens automatically and never needs a
choice (see the Portfolios section).

The parsed preview and account mapping are preserved in memory across language
switches. Switching the UI language while reviewing an import returns to the
confirmation step with the mapping intact — no re-upload required.

Parser warnings appear in a scrollable box with a copy button. The copied text
uses stable `Row N: message` lines so the diagnostics can be kept with the
source export. Applying the import is atomic and uses content hashes to skip
duplicates on re-run.

### What a re-import preserves

Re-applying the **same** Portfolio Performance export is a **content-hash
no-op**: every transaction row that already exists is skipped as a duplicate,
no security is created twice, and nothing that was maintained in Portfolixir
after the first import is touched. Verified on synthetic fixtures and pinned
as a permanent regression test, the following survive a re-import unchanged,
with the same ids and exact values:

- classification assignments (custom trees and the categories a security sits
  in);
- every target plan version with its category and position target weights,
  and the cash target;
- each security's note and its attributes, including custom attribute keys;
- the security research log (the Research tab's entries and the thesis state
  derived from them);
- security ids and their `updated_at` — nothing is silently rewritten.

A **mutated** re-import (a renamed security, a recorded ISIN change) keeps the
same guarantee for the matched securities; the one genuinely new booking
lands, nothing else changes. The one thing this guarantee does **not** cover
is a booking that changed in the source: an edited transaction hashes
differently and is imported as a new row next to the old one — remove or
correct the old booking by hand. The same statement lives in the
[API and MCP](integration/api-and-mcp.html) reference so an agent reads it
where it reads the endpoints.

### Security matching and the mapping step

Securities in the file resolve against existing records through a
deterministic **stable-identity ladder** (ADR-0029): ISIN first — current
ISINs, then recorded former-ISIN aliases —, then WKN, then ticker+currency,
then name+currency. Each tier only applies when the identifier is present on
both sides, and only when it selects exactly one candidate. Matching never
changes the matched security's master data: a rename in the export updates
nothing implicitly.

The preview's **Securities from the export** panel shows the outcome:

- **Matches** are summarized in a collapsible list, each labeled with the
  tier that matched it (for example *matched via former ISIN* after a
  recorded ISIN change).
- **Plain new securities** stay collapsed as a summary; expand the list to
  remap any of them onto an existing security instead.
- **Decisions** are surfaced prominently and block the import until
  resolved: an ambiguous identifier (two securities share a WKN or a
  name+currency), or a candidate that contradicts a stronger identifier —
  the typical shape of an ISIN change that has not been recorded yet. The
  import never picks silently in these cases.
- **Configuration-at-risk warnings**: when a to-be-created security
  near-matches an existing one that carries category assignments or position
  targets, the row requires its own explicit confirmation — a duplicate
  would strand that configuration on a position-less row.

When an entry is remapped and its ISIN differs from the chosen security's
current ISIN, the preview offers to **record the difference as an ISIN
change** in the same step, so the decision persists for future imports
instead of being repeated every time.

A second panel lists every **configured security the import does not
touch**: securities carrying assignments or position targets that match no
entry in the file — likely a rename or ISIN change in Portfolio
Performance. Remedy: record the ISIN change on the security (or, without an
ISIN, rename it in-app to match, or remap it in the preview), then re-run
the import.

Two more safeguards run at apply time: the matching is **re-checked inside
the import transaction** and the apply aborts back to the preview if
anything resolved differently than the approved set (previews can sit open
for a while); and rows that resolve to the **same booking on the same
security** — an export listing one paper under both its old and its new
ISIN — are collapsed to a single transaction and reported, never
double-imported.

Inbound and outbound **delivery** rows keep their parsed per-share price (the
CSV `Kurs` column), so a priced inbound delivery enters the holdings cost
basis with its real cost. A delivery row without a price still imports and
moves quantity at zero cost, as described under Holdings Calculation.

Rows with **implausible dates** (before 1900, e.g. a `0217-12-05` typo for
2017) are rejected per row with a clear message instead of poisoning every
derived metric — fix the booking in the source and re-import; the content
hashes keep the re-run free of duplicates. After an import, quote and logo
enrichment for the created securities runs as one throttled background job,
so the app stays responsive while hundreds of securities are synced.

## Quotes and Charts

### Quote History

Each quote entry captures a date and a Decimal close. Price history is
persisted so security detail charts are built from local records.

Two ways quotes enter the system:

- **Automatic sync**: a background scheduler ticks every six hours
  (configurable in `config :portfolixir, Portfolixir.Catalog.QuoteSync`)
  and pulls daily closes from each security's configured provider.
- **Sync now**: the toolbar's *Sync prices* button (and the per-security
  button on the detail page) triggers an immediate sync without waiting
  for the next tick.

Quote sources in this iteration:

- Search step (which catalog the security came from) uses Portfolio
  Performance for stocks/ETFs/funds and CoinGecko for crypto. The creation
  dialog also offers **Manual entry** (also linked from the search step) for
  instruments no provider knows — straight to the details form, saved with
  the `manual` provider marker. When a found security trades on several
  markets, the **recommended market** (XETR, else the first EUR market) is
  offered first by its human exchange name; the remaining markets sit behind
  a *More markets* disclosure.
- New securities start background quote/logo enrichment when configured.
  Logo discovery runs through a single background queue, scans missing
  logo candidates on startup, is also triggered after imports, and runs a
  periodic rescan, so large imports fill in over time. The queue is throttled
  (one request every few hundred ms) to stay under the upstream rate limits
  instead of firing a burst that mostly fails. Per security, sources are tried in order: CoinGecko
  (crypto), Wikipedia/Wikidata (equities/ETFs/funds), then companieslogo.com
  as a fallback.
  ETF logo discovery tries known issuer names before the individual fund name
  (for example iShares, Vanguard, Lyxor, Amundi, Xtrackers, SPDR, Invesco).
  Structured/leverage products (warrants, knock-outs, certificates) carry no
  own logo but show their issuer's logo (BNP Paribas, Morgan Stanley, Société
  Générale, …) when the issuer is recognizable. A manual override (image URL)
  always wins and locks the security against background discovery.
  Government bonds use the `government_bond` asset class for ISIN country flag fallbacks.
- Quote-history fetch uses Yahoo Finance for both. Two reasons:
  - PP's own API exposes only search, no price history.
  - CoinGecko's free public API caps history at 365 days
    (`error_code 10012`); Yahoo returns the full daily series for
    crypto via the `<TICKER>-<CURRENCY>` symbol form (e.g. `BTC-USD`).
- Portfolio Performance search can provide symbols for some bonds and leveraged products.
  Yahoo remains usable when a suitable symbol exists and is stored on the
  security.
- Ariva is not used as a quote adapter. Its historical endpoint for leveraged
  products is currently blocked for this local default use case.
- Bundesbank is relevant for German federal securities and yield data, not a general ISIN quote provider.
- No API-key-based providers and no unofficial scraping dependency are used as
  default quote sources.
- No new bond or leveraged-product quote adapter is implemented in this batch.

Yahoo is queried with `period1=0` and `period2=<now>` so it returns the
full available daily history — `range=max` silently downsamples to
monthly for long-history tickers.

Securities whose provider has no quote adapter, or whose adapter cannot run
because required fields such as ticker are missing, are reported as skipped
with a reason. Failed adapter calls are reported separately from successful
syncs.

Hand-entered quotes win over synced ones: the sync never overwrites a stored
row whose source is `manual`, even when the provider history covers the same
date. Each sync reports how many manual rows it left untouched and logs a
warning when that count is above zero. Editing a quote by hand still
overwrites whatever is stored, including previously synced values.

### Security Detail Chart

With no selected security, the securities list fills the page workspace.
Clicking a row opens `/securities/:id` in a vertical split workspace: the list
stays in the upper scrollable pane and the selected detail pane opens below it.
The horizontal separator can be dragged or adjusted with the keyboard on
desktop; mobile uses a stacked layout.

The detail pane shows a server-rendered SVG price chart with:

- Time-range buttons (1M / 3M / 6M / YTD / 1Y / 3Y / 5Y / MAX).
- A *Log scale* toggle (logarithmic Y-axis).
- A *Show transactions* toggle that overlays buy/sell markers from the
  ledger — shape-coded triangles (▲ buy, ▼ sell), so the direction is
  readable without colour.
- A *Sync prices for this security* button.

**Stock splits and the price basis (ADR-0028).** After a split is booked, the
chart and the Quotes tab show a **split-adjusted** series derived at read
time: manually entered (raw, as-traded) closes from before the effective date
are divided by the cumulative ratio of all later splits, while provider-synced
rows — already back-adjusted by the provider — pass through unchanged, so
nothing is ever adjusted twice. The basis in effect ("split-adjusted",
"provider-adjusted", or mixed) is stated under the chart and on the Quotes
tab, whose table keeps a *Stored* column with the unmodified values — stored
quote history is never mutated, and deleting a mistakenly booked split
restores every chart and figure exactly. Holdings, valuations, performance
series, snapshot comparisons and the securities-list metrics all price
through the same basis-aware engine, so a stale pre-split close (or the
latest-own-trade-price fallback) never values a post-split position at the
unsplit price. For providers that never back-adjust their history, the
security's Overview tab offers a **Treat synced quotes as raw** toggle that
forces the raw basis for its synced rows.

**Recording a split.** The detail pane's **Record split** button opens a
guided wizard: enter the ratio as new:old shares (2:1 doubles the share
count, 1:10 is a reverse split) and the effective date, and the dialog
previews the effect live — quantity before and after the effective date plus
the resulting current position, one row per affected portfolio — together
with every warning before anything is written: an effective date that
predates the imported history (the quantities may already be post-split), and
the quote-basis check on the stored closes around the effective date
(contradiction or too few quotes to verify). Confirming books the same
first-class split ledger event the API and MCP tools create — one journaled
transaction per positioned portfolio, atomically — and the chart, holdings
and transactions refresh immediately. Invalid input (a 1:1 ratio, a future
date, no held position, or a second split on the same day, which is rejected
naming the already-booked event) stays inline in the dialog.

## Interface behavior

- The active page title and short context line live in the top bar. Page content
  starts directly with a full-width workspace, so every active menu route uses
  the available space without a repeated page-level heading or outer page
  gutters.
- The securities list uses a full-width workspace instead of generic panel
  chrome; the toolbar remains pinned to the workspace top and the table uses
  the full horizontal width below it.
- Action feedback is **inline, not a floating toast**: while a background
  action runs (price sync, logo lookup) the triggering control shows a busy
  state, and the result appears in the page flow near the controls — success
  as a note, a failure as a problem note with the reason. A result stays
  visible until the next action, a navigation, or its explicit dismiss
  control; nothing disappears on a timer.
- In a classification tree, categories are collapsed by default (click a
  category to expand it); searching expands the matching categories. Long
  security names are truncated to one line with the full name on hover, and the
  ticker is shown next to the name.
- Each assigned security shows its **current quantity** (summed across every
  securities account of every portfolio) and its **current market value** in
  the EUR hub, valued from the latest quote (falling back to the latest own
  trade price, like the portfolio valuation). Holdings and values are loaded
  **once** for the whole tree after the page connects, so a large tree never
  triggers a query per row.
- A **Current positions only** toggle is on by default. It hides securities no
  longer held (zero current quantity) so legacy or fully sold assignments do
  not clutter the tree. Nothing is silently dropped: each category shows a
  **+N without holdings** counter for the hidden securities, and turning the
  toggle off reveals them again.
- Each category row aggregates the **value** and the **position count** of the
  securities currently visible in it and its sub-categories, so the totals
  follow the toggle.
- The sidebar is organised into task-oriented areas (ADR-0022): **Overview**,
  **Wealth**, **Securities**, and **Transactions** at the top level, plus an
  **Administration** group with **Accounts & depots**, **Views**, and
  **Classifications**. It lists only routes that exist — no disabled roadmap
  placeholders. Cash flow is a tab of the Wealth area and Import a tab of the
  Transactions area, not separate menu entries. Buckets have no sidebar entry
  of their own (ADR-0024): they are managed as chips on the Accounts & depots
  rows and on the Views page, which the view switcher's **Views** link
  opens.
- Theme: system, light, and dark modes are supported.
- Accent: violet, teal, and coral logo accent choices are supported.
- Language: first load follows the browser language when it is English or
  German. Explicit EN/DE links override the browser language and persist that
  choice.
- Theme, accent, and language are user preferences and do not affect stored
  financial values.
- Date fields accept and display ISO dates (`YYYY-MM-DD`) — the same format
  every displayed date uses; the browser's locale date picker is not used.
- While values compute, the affected slot shows a placeholder plus a
  "computing" cue instead of a loading message; headline values settle with
  a brief count-up. Under a reduced-motion system preference all decorative
  motion is off and final values render immediately.
- Expensive figures are recomputed by the write that invalidated them, not by
  the next page you open: after a booking, an import or a quote update they
  are refreshed in the background, so the cue above is normally something you
  see once rather than after every change. A burst of writes — an import of a
  whole export — costs one refresh, not one per row. Until the refresh lands,
  the previous value is shown, labelled with the time it was computed.
- Signed key figures (TTWROR, IRR/MWR, net flows, the Overview change
  signal) carry an explicit sign and gain/loss colour at every level;
  unsigned magnitudes keep the accent colour.

## Audit Journal

Every change to financial data is recorded in an append-only audit journal in the
same database transaction as the change itself, so any create, edit, or deletion
stays attributable (who and when) and reversible by inspection (before/after
values) — the safety net for letting an agent write data through the API/MCP.
Market-data sync (quotes and exchange rates) is operational and is not journaled.
The journal is queryable through `GET /api/v1/journal` and the matching
`portfolixir.journal.list` MCP tool (see
[API and MCP](integration/api-and-mcp.html)). It currently covers security
master-data writes; the remaining write areas are covered in sequence. A
dedicated in-app viewer is a planned follow-up.

## Non-goals today

- No automatic trading or order execution.
- No bank, broker, or wallet integrations.
- No payment scheduling or settlement workflows.
- No broker PDFs, binary Portfolio Performance workspaces, bank sync, broker
  sync, or document intake beyond the Portfolio Performance CSV/JSON v1
  transaction export workflow.

Savings plans are deliberately not supported. A savings plan only describes an
*intended* recurring contribution, and its target values inevitably diverge from
the real executions a broker performs — typically by cent-level differences in
price, fee, and quantity. Portfolixir treats the imported, real transactions as
the single source of truth for holdings and performance, so modelling separate
savings-plan targets would add a parallel set of numbers that never quite
matches reality. Recurring contributions are therefore captured simply as the
transactions they actually produced.
