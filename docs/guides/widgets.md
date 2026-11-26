---
layout: docs
title: Widget Catalogue
description: Every dashboard widget in every size it takes, light and dark, with what it draws and its source route.
lang: en
lang_en: /guides/widgets.html
lang_de: /de/guides/widgets.html
---

# Widget Catalogue

Every widget a dashboard can hold, in every size it takes on the grid —
Apple's families S, M, L and XL, and "Row" — as the app draws it on the
review seed's synthetic data, light and dark (the picture follows your
system's colour scheme). Each widget draws exactly the read its source
route answers, so your agent reads the same figures over the API and MCP
for the same view and period. How a dashboard is arranged, and how the
period and the view reach a widget, is in the
[handbook](/product-documentation.html#overview-page).

The pictures show the English interface at twice the screen's pixels,
each cut to its tile. After a change to a widget they are regenerated
(Sprint 32, plan D-13) with

```bash
mix test test/browser/widget_gallery_test.exs --only gallery
```

## Total value

`total_value` · sizes S, M, L

The total of the widget's view with its currency. **S** the total, its
change over the period (the period's TTWROR) and a value line; **M** the
total with the period's TTWROR and its result side by side; **L** the total,
its change and the value's course over the period. What the total leaves out
stands as one line in the footer.

**Source:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/performance`
- `GET /api/v1/views/:view_id/performance`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/total_value-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/total_value-s-light.png 2x" src="/assets/widgets/total_value-s-light.png" alt="Total value at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/total_value-m-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/total_value-m-light.png 2x" src="/assets/widgets/total_value-m-light.png" alt="Total value at M" loading="lazy">
</picture>
<figcaption>M</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/total_value-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/total_value-l-light.png 2x" src="/assets/widgets/total_value-l-light.png" alt="Total value at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Data quality

`data_quality` · sizes S, L

The data findings over the held securities and the ledger's checks. **S**
the three most severe as short counted lines and how many more; **L** every
finding as a row with its full sentence, what it does to the total under it,
and the severities in words in the head. Each count is the length of the
list its link opens.

**Source:**

- `GET /api/v1/securities`
- `GET /api/v1/transactions/cash_mismatch`
- `GET /api/v1/transactions/rate_only`
- `GET /api/v1/splits/incomplete`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/data_quality-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/data_quality-s-light.png 2x" src="/assets/widgets/data_quality-s-light.png" alt="Data quality at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/data_quality-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/data_quality-l-light.png 2x" src="/assets/widgets/data_quality-l-light.png" alt="Data quality at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Due

`due` · sizes S

The dated facts about any security in the catalogue, held or not, falling in
the next 30 days: the next two on a line each, the rest behind „+n more“.

**Source:**

- `GET /api/v1/events/upcoming`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/due-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/due-s-light.png 2x" src="/assets/widgets/due-s-light.png" alt="Due at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

## Off target

`off_target` · sizes S, L

The categories ±5 pp or more off their target weight, at every level of the
steering tree. **S** their count; **L** the list, each with its drift as a
bar and in money.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/allocation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/off_target-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/off_target-s-light.png 2x" src="/assets/widgets/off_target-s-light.png" alt="Off target at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/off_target-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/off_target-l-light.png 2x" src="/assets/widgets/off_target-l-light.png" alt="Off target at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Performance

`performance` · sizes S, L, XL, Row

The view's time-weighted return over the period. **S** („Return“) the TTWROR
and a line of the daily value; **L** the TTWROR and the value's course with
its lowest and highest value; **XL** Wealth's stacked chart by category with
its legend; **Row** Wealth's section (Sprint 32 W1): the % or value series,
the level (total, categories, securities), the benchmark picker, the
period's badge, the chart and "Data as table". The series and the level
are the page's, never stored; the benchmarks are the ones picked on Wealth.

**Source:**

- `GET /api/v1/performance`
- `GET /api/v1/views/:view_id/performance`
- `GET /api/v1/performance/bands`
- `GET /api/v1/performance/benchmark`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/performance-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/performance-s-light.png 2x" src="/assets/widgets/performance-s-light.png" alt="Performance at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/performance-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/performance-l-light.png 2x" src="/assets/widgets/performance-l-light.png" alt="Performance at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/performance-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/performance-xl-light.png 2x" src="/assets/widgets/performance-xl-light.png" alt="Performance at XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/performance-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/performance-row-light.png 2x" src="/assets/widgets/performance-row-light.png" alt="Performance at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Tops and flops

`movers` · sizes S, L

Which names moved the view in the period's window. **S** the two highest and
the two lowest price returns, each with its bar; **L** the highest and
lowest of the price return or the contribution (the switch in the head),
every row with its bar.

**Source:**

- `GET /api/v1/movers`
- `GET /api/v1/views/:view_id/movers`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/movers-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/movers-s-light.png 2x" src="/assets/widgets/movers-s-light.png" alt="Tops and flops at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/movers-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/movers-l-light.png 2x" src="/assets/widgets/movers-l-light.png" alt="Tops and flops at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Snapshots

`snapshots` · sizes S, M

The latest snapshot's date, how many there are and the real TTWROR since
then, with its daily line; **M** names the snapshot too.

**Source:**

- `GET /api/v1/snapshots`
- `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/snapshots-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/snapshots-s-light.png 2x" src="/assets/widgets/snapshots-s-light.png" alt="Snapshots at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/snapshots-m-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/snapshots-m-light.png 2x" src="/assets/widgets/snapshots-m-light.png" alt="Snapshots at M" loading="lazy">
</picture>
<figcaption>M</figcaption>
</figure>

## Allocation and drift

`allocation_drift` · sizes L

Each top-level category of the steering tree and cash: actual and target
weight, the drift with its bar, and in the column „≈ to target“ the amount
that would close a gap of ±5 pp or more — arithmetic for display, never an
order.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/allocation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/allocation_drift-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/allocation_drift-l-light.png 2x" src="/assets/widgets/allocation_drift-l-light.png" alt="Allocation and drift at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Crashes compared

`crashes` · sizes L

The crash benchmark's windows, newest first: each window's fall and the
lowest return over it among the securities held today or in the whole
catalogue (the switch in the head), and when it recovered.

**Source:**

- `GET /api/v1/crashes`
- `GET /api/v1/crashes/:key/rankings`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/crashes-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/crashes-l-light.png 2x" src="/assets/widgets/crashes-l-light.png" alt="Crashes compared at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Bitcoin cycle

`bitcoin_cycle` · sizes L, XL

The range the stored cycles give from the current anchors for each security
with the cycle view: the next low's and the next top's windows, price ranges
and states. **L** the card; **XL** the security's chart on the range „Cycle“
with its bands. Not a forecast.

**Source:**

- `GET /api/v1/securities/:security_id/cycles`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/bitcoin_cycle-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/bitcoin_cycle-l-light.png 2x" src="/assets/widgets/bitcoin_cycle-l-light.png" alt="Bitcoin cycle at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/bitcoin_cycle-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/bitcoin_cycle-xl-light.png 2x" src="/assets/widgets/bitcoin_cycle-xl-light.png" alt="Bitcoin cycle at XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

## Sale review

`sale_review` · sizes L, Row

The five most recently closed trades with their results, FIFO across every
depot, in EUR; what the list leaves out stands as one line in the footer.
**Row** draws the same list across the full width.

**Source:**

- `GET /api/v1/realized_gains`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/sale_review-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/sale_review-l-light.png 2x" src="/assets/widgets/sale_review-l-light.png" alt="Sale review at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/sale_review-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/sale_review-row-light.png 2x" src="/assets/widgets/sale_review-row-light.png" alt="Sale review at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Distance to high

`distance_to_high` · sizes L, XL

The held securities by their distance to their 52-week high, with the
largest drawdown; **XL** with more rows and the full names.

**Source:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/securities/:security_id/metrics`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/distance_to_high-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/distance_to_high-l-light.png 2x" src="/assets/widgets/distance_to_high-l-light.png" alt="Distance to high at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/distance_to_high-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/distance_to_high-xl-light.png 2x" src="/assets/widgets/distance_to_high-xl-light.png" alt="Distance to high at XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

## Crash chart

`crash_chart` · sizes L, XL

The crash benchmark's closes over the period with its crash windows shaded,
the running one stronger; the benchmark named under the title, its first,
lowest, highest and last close under the chart.

**Source:**

- `GET /api/v1/crashes`
- `GET /api/v1/securities/:security_id/quotes`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/crash_chart-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/crash_chart-l-light.png 2x" src="/assets/widgets/crash_chart-l-light.png" alt="Crash chart at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/crash_chart-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/crash_chart-xl-light.png 2x" src="/assets/widgets/crash_chart-xl-light.png" alt="Crash chart at XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

## Rebounders after crashes

`rebounders` · sizes L, XL

After each of the last crash windows whose fall has ended, the securities
that rose most from their own low within three months, each with its bar;
held today or the whole catalogue (the switch in the head). Not a forecast;
survivorship is named behind ⓘ.

**Source:**

- `GET /api/v1/crashes`
- `GET /api/v1/crashes/:key/rankings`
- `GET /api/v1/views/:view_id/valuation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/rebounders-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/rebounders-l-light.png 2x" src="/assets/widgets/rebounders-l-light.png" alt="Rebounders after crashes at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/rebounders-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/rebounders-xl-light.png 2x" src="/assets/widgets/rebounders-xl-light.png" alt="Rebounders after crashes at XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

<!-- S32 W2 begin -->

## Key figures line

`summary_line` · sizes Row

The line that heads Wealth's tab "Allocation & targets": the total incl.
cash, the cash quote and the period's TTWROR, and the way to all key
figures on Holdings. **Row** draws it across the full width, as the tab
does; on a phone it wraps. It follows the dashboard's period, or its pin.
Not "Key figures" (`wealth_key_figures`), the Holdings tab's band.

**Source:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/performance`
- `GET /api/v1/views/:view_id/performance`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/summary_line-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/summary_line-row-light.png 2x" src="/assets/widgets/summary_line-row-light.png" alt="Key figures line at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Allocation

`allocation` · sizes Row

Wealth's section "Allocation", as the tab draws it: tree or positions, the
sunburst with its legend, the drift table (each category's value, actual
and target weight and its drift, a category opening its securities), the
drift chips and the choice of the tree. The hints beside a drift ("Sell ≈
3.20 units") are arithmetic at the valuation's price, display only, never
an order (ADR-0023). The controls change only this widget, for as long as
the page is open; nothing is stored. The targets are edited on the
Classifications page, which the plan line links. **Row** draws the section
across the full width; on a phone it takes the section's own narrow
layout.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/allocation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/allocation-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/allocation-row-light.png 2x" src="/assets/widgets/allocation-row-light.png" alt="Allocation at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

<!-- S32 W2 end -->

<!-- S32 W3 begin -->

## Comparison against a snapshot

`snapshot_comparison` · sizes Row

Wealth's comparison on the tab "Snapshots" (ADR-0027): the real TTWROR
since the as-of date against the frozen holdings' buy-and-hold return,
the transaction costs since and whether they were earned back (only when
trades cost something), the positions left out, and both series as a
chart with its table. It compares the newest snapshot until a name in
"Snapshot list" picks another; the footer names the snapshot, its scope
and its date. **Row** draws the section across the full width; on a phone
it takes the section's own narrow layout.

**Source:**

- `GET /api/v1/snapshots`
- `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/snapshot_comparison-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/snapshot_comparison-row-light.png 2x" src="/assets/widgets/snapshot_comparison-row-light.png" alt="Comparison against a snapshot at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Snapshot list

`snapshot_list` · sizes Row

Every snapshot, newest as-of date first, with its scope and as-of date;
the one compared is marked "In comparison", and a name picks the one the
dashboard compares, while the page is open, nothing stored. A snapshot is
made and deleted on the Snapshots page: **New snapshot →** in the footer
leads there.

**Source:**

- `GET /api/v1/snapshots`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/snapshot_list-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/snapshot_list-row-light.png 2x" src="/assets/widgets/snapshot_list-row-light.png" alt="Snapshot list at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

<!-- S32 W3 end -->

<!-- S32 W4 begin -->

## Own rules

`own_rules` · sizes Row

Your own rules on the Risk tab and their findings for the widget's view:
breached and undetermined first, each with the rule's words beside the
measured value and its line; the counts head the widget; scheduled rules,
and the retired ones behind a disclosure. A finding says which side of the
line a figure is on, not what to do. Rules are made and changed in the
Risk tab's dialog: **Edit rules →** leads there.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/policy_findings`
- `GET /api/v1/portfolios/:portfolio_id/policy_rules`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/own_rules-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/own_rules-row-light.png 2x" src="/assets/widgets/own_rules-row-light.png" alt="Own rules at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Portfolio metrics

`key_figures` · sizes M, Row

The Risk tab's portfolio metrics over one year: the annualized
volatility, the maximum drawdown with its dates, the risk-adjusted return
and the highest correlation of the largest positions; below its minimum a
metric says what it had and needed, never a number. **M** the first three;
**Row** all four with the basis line.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/risk`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/key_figures-m-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/key_figures-m-light.png 2x" src="/assets/widgets/key_figures-m-light.png" alt="Portfolio metrics at M" loading="lazy">
</picture>
<figcaption>M</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/key_figures-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/key_figures-row-light.png 2x" src="/assets/widgets/key_figures-row-light.png" alt="Portfolio metrics at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Crashes

`crash_section` · sizes Row

The Risk tab's whole section "Crashes": the window (the newest until you
pick another), the list — losers, winners or rebounders — and the
securities, in the depot or the whole catalogue, the window line and the
ranked list, each as the rankings read answers it. Your choice stays in
the widget while the page is open. The crash benchmark and the windows
are set on the Risk tab, linked. "Crashes compared" (`crashes`) stays its
compact relative.

**Source:**

- `GET /api/v1/crashes`
- `GET /api/v1/crashes/:key/rankings`
- `GET /api/v1/views/:view_id/performance`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/crash_section-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/crash_section-row-light.png 2x" src="/assets/widgets/crash_section-row-light.png" alt="Crashes at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Largest single names

`top_holdings` · sizes Row

The lens's largest single names on the steerable basis: each with its
asset class, value and weight, and the generic threshold it is above or
below — generic thresholds, not your own rules.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/risk`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/top_holdings-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/top_holdings-row-light.png 2x" src="/assets/widgets/top_holdings-row-light.png" alt="Largest single names at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Concentration risk

`concentration` · sizes S, Row

The Herfindahl index of the single names' weights, 0 to 10,000, with its
band (low, moderate, concentrated) on its track. **S** the figure and the
track; **Row** with the scale line.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/risk`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/concentration-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/concentration-s-light.png 2x" src="/assets/widgets/concentration-s-light.png" alt="Concentration risk at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/concentration-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/concentration-row-light.png 2x" src="/assets/widgets/concentration-row-light.png" alt="Concentration risk at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Asset-class caps

`asset_class_limits` · sizes Row

The asset-class caps — the screen configures none, so there is nothing
to exceed (caps are set per request over the API) — and the correlations
of the largest positions behind a disclosure.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/risk`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/asset_class_limits-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/asset_class_limits-row-light.png 2x" src="/assets/widgets/asset_class_limits-row-light.png" alt="Asset-class caps at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

<!-- S32 W4 end -->

## Key figures

`wealth_key_figures` · sizes S, M, Row

Wealth's key figures as the owner picked them (board 06, variant A): the
total incl. cash with its split into securities and cash, the period's
result, TTWROR and IRR on one line, and under them the value bridge start
+ net flows + result = today with the multiple (for a period that has
ended, the bridge ends on its last day, "on <date>", and is not set
against today's total). The bridge is the performance read's own figures
at the cent; where the rounded cents do not
add up, the gap is shown, never moved into a figure. **S** draws the total
and its split, **M** the total and the three returns, **Row** all of it.

**Source:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/performance`
- `GET /api/v1/views/:view_id/performance`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/wealth_key_figures-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/wealth_key_figures-s-light.png 2x" src="/assets/widgets/wealth_key_figures-s-light.png" alt="Key figures at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/wealth_key_figures-m-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/wealth_key_figures-m-light.png 2x" src="/assets/widgets/wealth_key_figures-m-light.png" alt="Key figures at M" loading="lazy">
</picture>
<figcaption>M</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/wealth_key_figures-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/wealth_key_figures-row-light.png 2x" src="/assets/widgets/wealth_key_figures-row-light.png" alt="Key figures at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Data notes

`data_notes` · sizes Row

Wealth's data notes: why a total can differ from what is expected —
positions without a price or a rate, at a trade price or an old quote,
cash without a rate, negative holdings, bonds on two scales, quotes that
contradict their bookings, bookings dated before 1970. Drawn only while a
note exists; syncing exchange rates stays on Wealth, linked. **Row** only.

**Source:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/performance`
- `GET /api/v1/holdings/negative`
- `GET /api/v1/securities`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/data_notes-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/data_notes-row-light.png 2x" src="/assets/widgets/data_notes-row-light.png" alt="Data notes at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Contribution by position

`contribution` · sizes L, XL, Row

Which position made how much of the period's result (end value − start
value − flows + income − costs). **Row** is Wealth's table: the ten
largest, "Show all", the remainder not attributed to a position and the
sum row, which is the period's result. **L** lists the five largest
contributions with their bar, **XL** the eight largest in two columns,
with their start and end value.

**Source:**

- `GET /api/v1/performance/contribution`
- `GET /api/v1/views/:view_id/performance/contribution`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/contribution-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/contribution-l-light.png 2x" src="/assets/widgets/contribution-l-light.png" alt="Contribution by position at L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/contribution-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/contribution-xl-light.png 2x" src="/assets/widgets/contribution-xl-light.png" alt="Contribution by position at XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/contribution-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/contribution-row-light.png 2x" src="/assets/widgets/contribution-row-light.png" alt="Contribution by position at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Positions

`positions` · sizes Row

Wealth's position table: one row per depot and security, in the columns
picked with its column picker (the holdings projection's fields), the
market value in the base currency as the total sums it. The columns picked
once hold for Wealth and every dashboard. **Row** only.

**Source:**

- `GET /api/v1/portfolios/:portfolio_id/holdings`
- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/positions-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/positions-row-light.png 2x" src="/assets/widgets/positions-row-light.png" alt="Positions at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>

## Cash accounts

`cash_accounts` · sizes S, Row

Each cash account of the view with its balance in its own currency; a
reserve or a credit line muted, outside the cash quote. Setting a balance
stays on Accounts & depots, linked. **S** (headed "Cash") draws the
valuation's cash, every valued account with reserves and credit lines
included (the cash quote counts only the deployable share), and how many
valued accounts it sums; **Row** the table.

**Source:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/cash_accounts-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/cash_accounts-s-light.png 2x" src="/assets/widgets/cash_accounts-s-light.png" alt="Cash accounts at S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/cash_accounts-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/cash_accounts-row-light.png 2x" src="/assets/widgets/cash_accounts-row-light.png" alt="Cash accounts at Row" loading="lazy">
</picture>
<figcaption>Row</figcaption>
</figure>
