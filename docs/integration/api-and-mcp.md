---
layout: docs
title: API and MCP
description: Portfolixir JSON API and MCP companion reference.
lang: en
lang_en: /integration/api-and-mcp.html
lang_de: /de/integration/api-and-mcp.html
---

# API and MCP

Portfolixir exposes the supported local workflow through the JSON API under
`/api/v1`. The MCP companion in `mcp-server/` is intentionally thin: MCP tools
call the JSON API only and do not access the database directly.

## Authentication

API requests require a local bearer token:

```text
Authorization: Bearer <PORTFOLIXIR_API_TOKEN>
```

The MCP companion uses `PORTFOLIXIR_API_TOKEN` to call Portfolixir.
`PORTFOLIXIR_MCP_TOKEN` is required for HTTP transport so local HTTP clients can
authenticate to the companion.

## Data Rules

All responses use JSON envelopes with either `data` or `errors`. Financial
decimals are serialized as strings, including quantities, prices, fees, taxes,
quote closes, and monetary totals. Request payloads for those values should also
send strings.

`DELETE /api/v1/securities/:id` is the success exception: it returns
`204 No Content` with an empty body. Clients should not parse a JSON body for
that successful delete response.

**Delta reads (FR-38).** The two recurring-sync reads — `GET
/api/v1/transactions` and `GET /api/v1/securities` — accept
`?since=<ISO8601>` (a datetime with offset, a naive UTC datetime, or a plain
date meaning start of that day, UTC) and then return only the rows created or
updated strictly after that instant, judged by `updated_at`. The response
echoes `since`, carries `as_of` (the read instant — use it as the next
`since`) and a `delta_note` stating the semantics. **Deletions are not
represented** in a delta read; a caller that must detect deletions performs a
full read. An invalid `since` is a `422`. Delta reads are **pull-only**: push
delivery (webhooks to a user-configured endpoint) is a separate, still-gated
decision (B3.7) and deliberately not part of this surface.

## Securities

The `data_quality` predicates are the **same rule** the dashboard counts and
the securities page links to (issue #705): they are defined once in
`Portfolixir.Catalog.DataQuality`, so a count of N always addresses a list of
N, and an agent asking "which securities have a stale quote" gets exactly the
set a person sees. Combine them with `query`, `holding_status` and the other
narrowings; an unknown value is a `422` naming `data_quality`, never a silent
full list.

- `GET /api/v1/securities` lists securities. Rows default to a slim
  projection — the fixed whitelist `id`, `name`, `ticker_symbol`, `isin`,
  `wkn`, `currency_code`, `asset_class` — so routine listings stay small;
  `projection=full` returns the complete record (notes, feed config, attributes,
  timestamps). Optional query params: `query`, `sort`, `direction`,
  holding_status (`all`, `held`, or `not_held`), `logo_status` (`missing` or
  `present` — `missing` powers the "securities without a logo" overview and
  excludes rows explicitly set to no logo), `data_quality`
  (`stale_quote` — no quote newer than 7 days, **including** securities never
  priced at all; `missing_quote` — no quote at all, the narrower set inside it;
  `missing_logo`), `projection` (`slim`/`full`), and
  `limit`/`offset` for pagination (both non-negative integers). Use these to
  page large catalogs instead of fetching the whole table at once.
- `POST /api/v1/securities` creates a security with a `security` object.
  `asset_class` is a stable string code: `equity`, `etf`, `fund`,
  `government_bond`, `bond`, `crypto`, `commodity`, `index`, `other`, plus the
  certificate/leverage codes `warrant`, `knock_out`, `factor_certificate`,
  `discount_certificate`, `bonus_certificate`, `express_certificate`,
  `reverse_convertible`. Leave it empty to let the class be inferred from the
  name/ISIN/ticker on read. To keep a position out of the allocation steering
  basis (the 100%) and the drift table while leaving it in the valuation totals
  and performance — e.g. a Bitcoin held as a store of value — tag it with a
  bucket and exclude that bucket from a view, then read allocation under that
  view.
- `GET /api/v1/securities/:id` returns one security, including its
  `identifier_aliases` — the former ISINs recorded via the ISIN-change
  endpoint below (each with `id`, `former_isin`, `changed_on`, `note`).
- `PATCH /api/v1/securities/:id` updates a security with a `security` object.
  The boolean `treat_quotes_as_raw` (default `false`) is the ADR-0028 escape
  hatch for providers that never back-adjust their history after a stock
  split: with the flag set, the security's provider-synced quote rows are
  treated as raw (as-traded), so the split-adjustment factors apply to them
  too.
- `DELETE /api/v1/securities/:id` deletes a security when no dependent
  transactions or quote history reference it; referenced securities return
  `409 Conflict`.
- `GET /api/v1/securities/search` searches configured online security providers.
  Query params: `query`; optional `type` with `security` or `crypto`.

### ISIN changes (identifier aliases)

When a corporate action gives an existing security a new ISIN, record the
change instead of editing the ISIN in place: the former ISIN becomes a
journaled alias, and the import's ISIN matching consults current ISINs first,
then the aliases — so re-imports of old exports (former ISIN) and new exports
(new ISIN) both keep matching the same security instead of duplicating it
(ADR-0029). A plain rename needs no ISIN change — it is just a name edit.

- `POST /api/v1/securities/:security_id/isin-change` records the change with an
  `isin_change` object: required `new_isin` (normalized to trimmed uppercase),
  optional `changed_on` (ISO date, defaults to today) and `note`. Returns the
  updated security including its `identifier_aliases`. Guarded with `422` and a
  named conflict when `new_isin` equals the current ISIN, is live on another
  security, or is recorded as another security's former ISIN; recording a
  change back to one of the same security's own former ISINs consumes that
  alias (a revert). Every security-ISIN write path — create, update, and the
  import's create path — symmetrically rejects an ISIN that exists as an
  alias, naming the aliased security.
- `DELETE /api/v1/securities/:security_id/identifier_aliases/:id` deletes one
  recorded alias (journaled) when an ISIN change was recorded by mistake;
  returns `204 No Content`, or `404` when the alias does not belong to the
  security.

Example ISIN-change payload:

```json
{
  "isin_change": {
    "new_isin": "IE000XZSV718",
    "changed_on": "2026-07-01",
    "note": "merger rename"
  }
}
```

### Logos

Each security can carry a logo, resolved automatically (CoinGecko for crypto,
Wikipedia for equities/ETFs/funds) or set manually. A manual logo, or an
explicit "no logo", *locks* the security so background discovery never
overwrites the choice.

- `GET /api/v1/securities/:security_id/logo` returns the logo status:
  `{ "data": { "security_id", "path", "source", "has_logo", "locked" } }`.
  `source` is one of `coingecko`, `wikipedia`, or `manual`.
- `PUT /api/v1/securities/:security_id/logo` sets a manual logo from an image
  URL (`{ "logo": { "url": "https://…" } }` or `{ "url": "https://…" }`). The
  image is downloaded once, validated (png/jpg/jpeg/webp, max 256 KiB) and
  stored locally; the security is locked to the manual choice. A missing URL
  returns `422`.
- `DELETE /api/v1/securities/:security_id/logo` removes the logo and records an
  explicit "no logo" decision (the row falls back to its initials/flag), also
  locking it against discovery.
- `POST /api/v1/securities/:security_id/logo/discover` re-runs automatic
  discovery ("search again"). The response includes a `result` of `updated`,
  `no_source`, or `failed`. Locked securities are left untouched.

Example create payload:

```json
{
  "security": {
    "name": "Example ETF",
    "ticker_symbol": "EXM",
    "currency_code": "EUR"
  }
}
```

## Quotes

- `GET /api/v1/securities/:security_id/quotes` lists quote history for one
  security. Optional query params: `from` and `to`, formatted as ISO dates.
  Invalid date filters return `422 Unprocessable Entity` with field errors.
  Each row is self-describing about stock splits (ADR-0028): `close` is the
  **stored** value (never mutated), `adjusted_close` the split-adjusted
  display value, `basis` the row's storage basis (`raw` for as-traded manual
  rows, `provider_mirror` for back-adjusted sync rows) and `adjusted`
  whether a split factor applied. Chart or value with `adjusted_close`;
  audit against `close`. A security whose provider never back-adjusts can be
  flagged with `treat_quotes_as_raw` (see Securities), which forces the raw
  basis for its synced rows.
- `PUT /api/v1/securities/:security_id/quotes` upserts manual quote rows.
- `POST /api/v1/securities/:security_id/sync_quotes` triggers quote sync for
  one security. The response includes `status` (`ok`, `skipped`, or `error`);
  skipped and error responses may include a `reason` such as
  `missing_ticker` or `no_provider_adapter`.

Example quote upsert payload:

```json
{
  "quotes": [
    {
      "date": "2026-05-15",
      "close": "123.45",
      "source": "manual"
    }
  ]
}
```

Example quote sync response:

```json
{
  "data": {
    "status": "skipped",
    "reason": "missing_ticker"
  }
}
```

## Portfolios and Accounts

> **Portfolio writes are deprecated (ADR-0024) — compatibility only; use
> buckets/views for grouping.** Portfolios were demoted to internal
> compatibility records: the UI groups exclusively through buckets and views,
> and depots/cash accounts no longer need a `portfolio_id` (a deterministic
> internal default is bound automatically). `POST /api/v1/portfolios` and
> `PATCH /api/v1/portfolios/:portfolio_id` keep working but answer with a
> `Deprecation: true` response header. Sunset note: after two releases without
> external portfolio writes, a follow-up story merges the records into
> buckets and views (the ADR's exit criterion) — plan migrations to
> `POST /api/v1/buckets` and `POST /api/v1/views` now. Every record written
> here stays visible in the UI's read-only "Portfolio records (compatibility)"
> admin list, so nothing becomes invisible.

- `GET /api/v1/portfolios` lists portfolios (compatibility records).
- `POST /api/v1/portfolios` creates a portfolio with a `portfolio` object.
  **Deprecated** — answers with `Deprecation: true`; prefer buckets/views.
- `GET /api/v1/cash_accounts` lists cash accounts. Each carries a `balance`
  (decimal string, in the account's own currency) derived on read from the
  ledger: amounts are stored as positive magnitudes and the transaction `type`
  implies the direction (deposits, dividends, interest, tax refunds and sells
  add cash; removals, fees, taxes and buys remove it; a cash transfer debits its
  account and credits the counter account). A `balance_adjustment` snapshot (see
  below) anchors the balance to a stated absolute amount as of its date, after
  which only later bookings adjust it.
- `POST /api/v1/cash_accounts/:id/balance` records an absolute **balance
  snapshot** for one account (ADR-0009): the current balance as of a date,
  instead of mirroring every booking. Body `{"date": "2026-06-01", "amount":
  "4250.00"}` (`notes` optional); `amount` is a decimal string and may be
  negative (an overdraft). It stores a `balance_adjustment` transaction and
  returns it. The balance then anchors to that amount and only bookings dated
  strictly after the snapshot change it, so moving money between own
  accounts needs no transfer entry. Unknown accounts return `404 Not Found`.
- `POST /api/v1/cash_accounts` creates a cash account with a `cash_account`
  object. `portfolio_id` is optional (ADR-0024): when omitted, the account is
  bound to the deterministic internal default portfolio; an explicit id keeps
  winning for compatibility clients. The optional `liquidity_role` (default `free_cash`) classifies the
  account: `free_cash` is genuine deployable cash; `credit_line` is an
  overdraft/Lombard facility whose negative balance is a liability and whose
  unused headroom is never liquidity (it never enters deployable cash, even
  with a positive balance — type beats sign); `reserve` is a visible-but-
  excluded bucket (e.g. a business account). Only `free_cash` accounts with a
  non-negative balance contribute to the valuation's deployable cash and its
  `cash_quote`. An unknown value is rejected with `422 Unprocessable Entity`.
- `GET /api/v1/cash_accounts/:id` returns one cash account.
- `PATCH /api/v1/cash_accounts/:id` updates a cash account (`name`,
  `currency_code`, `notes`, `liquidity_role`); `portfolio_id` cannot
  be changed.
- `DELETE /api/v1/cash_accounts/:id` deletes a cash account, or returns
  `409 Conflict` when a transaction or securities account still references it.
- `GET /api/v1/securities_accounts` lists depots/securities accounts.
- `POST /api/v1/securities_accounts` creates a depot/securities account with a
  `securities_account` object. `portfolio_id` is optional (ADR-0024): when
  omitted, the depot is bound to the deterministic internal default portfolio.
- `GET /api/v1/securities_accounts/:id` returns one securities account.
- `PATCH /api/v1/securities_accounts/:id` updates a securities account
  (`name`, `notes`, `cash_account_id`); `portfolio_id` cannot be changed.
- `DELETE /api/v1/securities_accounts/:id` deletes a securities account, or
  returns `409 Conflict` when a transaction still references it.

Example account payloads:

```json
{
  "portfolio": {
    "name": "Household Portfolio",
    "base_currency_code": "EUR"
  }
}
```

```json
{
  "cash_account": {
    "portfolio_id": 1,
    "name": "Settlement EUR",
    "currency_code": "EUR"
  }
}
```

```json
{
  "securities_account": {
    "portfolio_id": 1,
    "cash_account_id": 1,
    "name": "Main Depot"
  }
}
```

## Transactions and Holdings

- `GET /api/v1/transactions` lists transactions. Optional filters: `from`/`to`
  (ISO dates, inclusive), `portfolio_id`, `security_id`, `securities_account_id`.
  Invalid filters return `422 Unprocessable Entity` with the offending field.
  An optional `fields=` (FR-37, comma-separated) selects a sparse fieldset:
  each row then carries exactly the requested fields. The names are validated
  against the serializer's own field list — an unknown name is a `422`, never
  a silent fallback.
- `POST /api/v1/transactions` creates a transaction of any bookable kind with a
  `transaction` object (per-kind required fields are validated server-side).
  The bookable `type` values are `buy`, `sell`, `dividend`, `interest`,
  `deposit`, `removal`, `fee`, `tax`, `tax_refund`, `cash_transfer`,
  `inbound_delivery`, `outbound_delivery` and `security_transfer`
  (`balance_adjustment` is written through the dedicated balance-snapshot
  endpoint, `split` through the split routes below).
  Booking semantics worth knowing before the first write: a dividend's
  `gross_amount` is the NET cash credited to the account — withheld taxes ride
  in `taxes`, and the income report reconstructs gross as net plus withheld
  tax. An inbound delivery recorded without a
  `price` enters the cost basis at zero — supply the acquisition price when it
  is known; an outbound delivery removes cost at the position's running
  average, so its price is informational only. When reconciling a difference, prefer booking the missing transaction
  of the correct kind — balance snapshots and unpriced inbound deliveries are last
  resorts that make numbers look right while distorting cost basis. Amounts
  are positive magnitudes — the kind implies the direction; only
  `balance_adjustment` may carry a negative (absolute) amount. A **tax
  refund** — for example the tax credited back when a sale realises a loss —
  is therefore never a negative `taxes` value on the sell: book the sell with
  the taxes actually withheld (or `0`), plus a separate `tax_refund`
  transaction whose positive `gross_amount` is the cash credited to the
  account (`cash_account_id` and `gross_amount` are its required fields; the
  changeset rejects a negative `taxes` with exactly this guidance). A security
  settled through a different-currency cash
  account (for example a USD security bought through a EUR account) is booked in
  the security's own currency and carries the cross-currency settlement fields
  `security_amount` (trade amount in the security currency), `settlement_amount`
  (cash amount debited or credited in the account currency) and
  `settlement_fx_rate` (account-currency units per one unit of the security
  currency). When the rate is omitted but both amounts are supplied it is derived
  as `settlement_amount / security_amount` (the broker's actual rate); a currency
  mismatch with no rate and no amounts to derive one is rejected. Cost basis stays
  in the security currency so per-position P&L is FX-honest. All three are Decimal
  strings and `null` for same-currency bookings.
- `GET /api/v1/transactions/:id` returns one transaction.
- `PATCH /api/v1/transactions/:id` updates a transaction (e.g. to fix a
  mis-imported booking); the per-kind validation still applies.
- `DELETE /api/v1/transactions/:id` deletes a transaction. Because trades and
  holdings are derived, correcting or removing the transaction fixes them too.
- `POST /api/v1/splits/preview` previews a stock split booking (ADR-0028)
  without writing anything. The request carries `security_id`, the effective
  `date` (ISO, not in the future) and the ratio as a pair of positive
  integers `ratio_numerator`/`ratio_denominator` (`10:1` forward, `1:10`
  reverse; normalized to lowest terms, so `10:5` previews and books as
  `2:1`). The response shows, per portfolio holding the security, the
  quantity immediately before and after the effective date and the resulting
  current position (all Decimal strings; the ratio parts stay integers),
  plus `warnings`: `effective_date_before_history` means the effective date
  predates the security's earliest recorded transaction — the stored
  quantities may already be post-split (Portfolio Performance's split wizard
  rewrites history destructively), so booking would double-adjust. Check the
  preview before booking. The preview also renders the stored closes around
  the effective date (`quotes_around`) and a `quote_basis_check`
  (misclassification guard, ADR-0028 §2): a visible jump indicates a raw
  series, continuity an already-adjusted one; when that contradicts the
  per-row `source` classification the preview warns with
  `quote_basis_contradiction` (for synced series that never back-adjust, set
  the security's `treat_quotes_as_raw` flag instead of booking blindly), and
  with too few closes on either side it reports
  `insufficient_quotes_to_verify_basis` instead of implying a clean check.
- `POST /api/v1/splits` books the split: **one** call fans the event out
  across all portfolios holding a position in the security at the effective
  date — one journaled `split` row per portfolio, inserted atomically — and
  returns the created transactions (`201`, regular transaction shape). A
  portfolio with zero position at the effective date gets no row. A second
  same-day split for the same security is rejected with `422` naming the
  existing event (a retried timeout cannot compound the multiplicative
  event); a future-dated effective date and a security nobody held at the
  effective date are rejected with `422` too. The generic
  `POST /api/v1/transactions` endpoint rejects the `split` kind — these two
  routes are the only split write path.
- `GET /api/v1/portfolios/:portfolio_id/holdings` lists derived holdings for a
  portfolio, one row per (depot, security). Each row carries `quantity`, a
  moving-average `avg_cost` and `cost_basis` (price-based, so fees and taxes are
  not folded into the unit cost), the `latest_price`, `market_value`, and
  `unrealized_pnl_abs`/`unrealized_pnl_pct` against that price, plus
  `security_name` and `currency_code`. Those figures are in the security's
  **own** currency — enforced by the cost pair the ledger fold carries
  (ADR-0033), no longer an assumption; a holding whose security has no quote
  returns `null` price, market value and P&L. Each row additionally carries
  the ADR-0033 base-currency P&L decomposition: `base_cost` (the
  settlement-leg amount actually paid, with its `base_currency`),
  `price_return_abs`/`price_return_pct` (the security's own price move,
  converted at today's rate), `currency_return_abs`/`currency_return_pct`
  (the FX effect on the amount originally invested) and
  `total_return_base_abs`/`total_return_base_pct` — with
  `total = price + currency` holding Decimal-exactly. A row whose
  decomposition is not derivable reports `decomposed: false` with an
  `undecomposed_reason` (`"missing_native_cost"` — no security-currency leg
  in the recorded booking, in which case `cost_basis`/`avg_cost`/P&L are
  `null` too; `"missing_base_cost"` — the settlement leg is not in the base
  currency; `"missing_fx"` — no stored current rate; `"no_price"`), never a
  guessed number. The response is self-describing (FR-13): it carries
  `currency_basis: "security_currency"` plus a `currency_basis_note` naming
  which field is in which currency, and an `as_of` date. Holdings are derived
  on read with no stored snapshot, so `as_of` is the read date. Unknown
  portfolios return `404 Not Found`. Optional filters: `security_id`,
  `securities_account_id`. An optional `fields=` (FR-37, comma-separated)
  selects a sparse fieldset per row, validated against the serializer's own
  field list; an unknown name is a `422`.
- `GET /api/v1/holdings/by_security` returns the **global per-security
  valuation** across **all** portfolios: one `holdings` row per currently held
  security with its `security_id` (an integer), total `quantity`, and current
  `market_value` converted to the **EUR hub**, plus a `valued` flag. `valued`
  is `false` (and `market_value` is `null`) when the security has neither a
  quote nor a trade price, or no exchange-rate path to EUR, so a missing quote
  or rate never silently distorts a value. Each row also carries the resolved
  native `latest_price` with `price_currency` and `price_source`, and an
  `unvalued_reason` that says *why* a row is unvalued: `"no_price"` (nothing
  resolves at all) or `"missing_fx"` (the price is known but no stored rate
  path reaches EUR); `null` when valued. Rows are sorted by `security_id`.
  The response is self-describing: a top-level `currency` of `"EUR"`, an
  `as_of` read date (the report is derived on read, so `as_of` is today's date,
  not a stored snapshot), and a `note` describing the hub conversion. This is
  the cross-portfolio, base-currency counterpart to the per-portfolio holdings
  list (which stays in each security's own currency with no FX); for one
  portfolio's totals and weights use the valuation endpoint instead.
- `GET /api/v1/holdings/negative` returns the **negative-holdings
  data-quality report**: every (depot, security) position whose derived
  quantity is below zero — import debris from unmodeled corporate actions —
  as `rows` (with `depot_name`, `security_name`, `isin`, `portfolio_id` and
  the negative `quantity` as a Decimal string) plus `totals` with each listed
  security's total quantity across **all** depots, so transfer debris
  (negative in one depot, positive in another) is distinguishable from a
  truly negative total. Self-describing with an `as_of` read date and a
  `note`. Nothing is repaired automatically; fix the security's transaction
  history.
- `POST /api/v1/holdings/reconcile` compares a **user-supplied external
  position list** (a broker statement or depot overview, parsed client-side
  into rows) against the ledger-derived holdings — **strictly read-only**:
  the list arrives only in the request body, is never persisted or logged,
  and no data is fetched from anywhere (ADR-0029 §6, FR-35). Each row is
  `{identifier, quantity}` with optional `currency` and an optional pinning
  `security_id`; `quantity` must be a **canonical dot-decimal string**
  (anything else — comma decimals, thousands separators, exponents — is a
  `422` naming the row; locale parsing is the client's job), and an empty
  `rows` list is a `422`. Identifiers match through the same stable-identity
  ladder the import uses: an ISIN-shaped string (format and check digit)
  matches via the ISIN tier only (current ISINs first, then recorded former
  ISINs — `matched_via: "former_isin"`); any other string is tried against
  WKN, ticker+currency and name+currency with the exactly-one rule applied
  across the union of those tiers — a string matching one security's WKN and
  another's ticker lands under `ambiguous` with the candidate securities,
  never a silent pick, and a currency-less row cannot match by ticker or name
  (`unmatched` with reason `currency_required`). The response is
  self-describing (`basis` with `as_of`, `scope`, and a delta note) and
  reports: `matched` rows (one per security — rows resolving to the same
  security are aggregated with their external quantities summed and the
  contributing rows listed), ordered by the **lowest input row index** each
  match aggregates so a finding maps back to the submitted line, each embedding
  the security's identity only (`id`, `name`, `ticker_symbol`, `isin`, `wkn`,
  `currency_code`), with the `matched_via` tier (`isin`,
  `former_isin`, `wkn`, `ticker`, `name`, or `pinned`), `ledger_quantity`,
  `external_quantity` and `delta` (`external - ledger`) as exact Decimal
  strings — ticker/name matches carry `weak_match: true` and the caveat
  "confirm the security before booking" —, `ambiguous` and `unmatched` rows,
  and `missing_from_list` (held ledger positions the external list does not
  cover). The embedded `guidance` is part of the contract: resolve a
  difference by booking the missing transaction of the correct kind; balance
  snapshots and unpriced deliveries are last resorts that distort cost basis.
  Optional scope: `portfolio_id` or `view` (a view id; mutually exclusive —
  both at once is a `422`), default the whole instance; an unknown portfolio
  or view is a `404`.
- `GET /api/v1/portfolios/:portfolio_id/valuation` returns a live valuation of a
  portfolio: each held position priced from its latest quote close, a
  `total_value`, and each valued position's `weight` (its share of the total).
  Each position's market value is converted into the portfolio
  `base_currency` (top-level field) from stored exchange rates; per-position
  `security_currency` shows the native currency. A security without any quote
  is priced at the latest own trade price (`price_source: "trade"`, counted in
  the top-level `trade_priced_count`); a quoted position carries
  `price_source: "quote"`. A position with neither price **or** no
  exchange-rate path to the base currency is returned with `valued: false`,
  `price_source: null` and `null` market value and weight, so a missing price
  or rate never distorts the total. Unknown portfolios return `404 Not Found`.
  Weights are raw shares (`market_value / total_value`) emitted at full Decimal
  precision; because they are normalized ratios they need not sum to exactly
  `1` (round for display). Market values and `total_value` are exact.
  The valuation also carries cash: `cash_balances` lists each cash account
  (`balance` in its own currency, plus `base_value`/`valued` after converting to
  the base currency, its `liquidity_role`, and a `deployable` flag), `total_cash`
  is the base-currency sum of the valued cash accounts (so a drawn credit line's
  negative balance still reduces it), and `total_with_cash` is
  `total_value + total_cash`. `cash_quote` is the deployable-cash share of the
  portfolio: deployable cash is the sum of `free_cash` accounts with a
  non-negative balance (`deployable: true`), and the quote is computed as if the
  other accounts did not exist (`counting_cash / (total_value + counting_cash)`,
  `0` when there is nothing to value yet) — so a reserve account or a credit line
  stays listed and inside `total_cash` without ever reporting fake liquidity. The
  response also emits `counting_cash` (Decimal string) — the deployable cash that
  enters the quote — so a consumer can reconstruct `cash_quote` itself. An
  account whose currency has no rate path to the base is reported
  `valued: false` and excluded from `total_cash`, mirroring how unpriceable
  positions are handled.
  The response is self-describing (FR-13): it carries an `as_of` date (the read
  date — the valuation is computed live with no stored snapshot) and a
  `valuation_note` stating that totals are in `base_currency` via the EUR hub and
  that the per-position `price_source` and `valued` fields indicate price
  staleness. An optional `include_positions=false` (FR-37) returns the
  roll-up only — totals, cash balances and cash quote without the
  per-position rows; the response states which shape was returned via
  `positions_included`.
- `GET /api/v1/portfolios/:portfolio_id/performance` returns the portfolio's
  **true time-weighted rate of return (TTWROR)**, computed the Portfolio
  Performance way: the portfolio is valued daily (quotes on or before each day,
  converted at that day's rates, plus cash), external flows — deposits,
  removals, deliveries, and balance-snapshot jumps — are neutralised, and daily
  returns chain geometrically (see ADR-0010). Optional query params: `period`
  (`ytd`, `1y`, `3y`, `5y`, `max` — default `max`; an unknown period returns
  `422 Unprocessable Entity`), `year=YYYY` for one calendar year, `from=`/`to=`
  (ISO dates, both required, `from <= to`) for a custom range — both clamped
  honestly to the available history, with a backwards or malformed range
  returning `422` — and `series=true` to include the daily points
  (`date`, `value`, `flow`, `cumulative_ttwror`). The response carries
  `ttwror`, `start_date`/`end_date`, `start_value`/`end_value`,
  `net_external_flows` as Decimal strings, and `suspect_dates` — dates of
  bookings older than 1970 (import typos) whose effects were applied on the
  first plausible day. Alongside `ttwror` the response also carries the
  **money-weighted return** `irr` — the single annualised rate that discounts
  the period's dated external flows and terminal value back to zero
  (`NPV(r) = Σ cf/(1+r)^(days/365) = 0`), the figure Portfolio Performance
  shows next to TTWROR. It is a Decimal string, or `null` when no rate exists
  (fewer than two flows, all flows the same sign, or the solver does not
  converge). Securities without quotes are priced at the latest own trade
  price (see the valuation endpoint). Unknown portfolios return
  `404 Not Found`. Since the daily walk may be served from a durable derived
  value (ADR-0039), the response is **never silent about freshness**: `as_of`
  (ISO-8601 datetime) is the instant the walk was computed — possibly older
  than the request when the underlying data has not changed since — and
  `stale` (boolean) marks a superseded value served while a fresh one
  computes; a stored value is invalidated by every write that can affect it,
  so `stale: false` means current against the ledger. The response also
  states the metric's **computation basis** (`computation_basis`): the input
  series, the effective window, the reference series (`null` — TTWROR/IRR
  have none) and the treatment of gaps.
- `GET /api/v1/portfolios/:portfolio_id/income` returns the **retrospective
  income report**: the dividends and interest already booked in the ledger,
  aggregated three ways (no forecast — the dividend calendar is a separate
  feature). `annual` is a list of years (newest first), each with `months` (a
  map keyed by month number `"1"`–`"12"`, each carrying `dividends` and
  `interest`), and per-year `dividends_total`, `interest_total` and `total`.
  `positions` is the per-position table: `security_id`, `security_name`,
  `security_currency` (the original booking currency), `gross`, `tax` (the
  withheld tax, from the dividend's TAX units stored on the transaction), `net`
  (`gross - tax`), `payment_count` and `last_payment`. `transactions` is the
  per-transaction detail for a year drilldown (`kind`, `date`, `year`,
  `security_id`/`security_name`, `currency`, the native `native_gross`/
  `native_tax`/`native_net`, the base-currency `gross`/`tax`/`net`, and
  `converted`). A dividend's gross is its net cash (`gross_amount`) plus the
  withheld tax; interest carries no withholding. All amounts are Decimal strings
  in the portfolio's `base_currency`, converted via the EUR hub at each
  booking date's stored rate (the same mechanics as the valuation endpoint), with
  the original currency retained; `unconverted_count` counts bookings with no
  rate path (converted at parity), and `conversion_note` states the basis.
  Unknown portfolios return `404 Not Found`.
  Since ADR-0020 a target plan **belongs to a view**: the target read/write
  endpoints accept an optional `view` (a view id). Omitting it (or sending
  `null`) addresses the portfolio-wide **Gesamt** plan — the behaviour before
  views existed. A view carries its own plan, so the same classification can hold
  a different plan per view without the plans summing across each other. A
  malformed `view` returns `422 Unprocessable Entity` (`{"view": ["is
  invalid"]}`) and an unknown view id returns `404 Not Found`, the same
  structured contract the analytics endpoints use.
- `GET /api/v1/portfolios/:portfolio_id/targets` lists a portfolio's stored
  target weights (the target side of the allocation). Optional `classification_id`
  scopes the list to one tree; optional `view` selects the plan (omitted =
  Gesamt). Unknown portfolios return `404 Not Found`.
- `PUT /api/v1/portfolios/:portfolio_id/targets` upserts target weights for one
  classification. The body is `{"classification_id": id, "targets": [{"category_id":
  id, "target_weight": "0.25"}]}` and may carry an optional `"view": id` to write
  that view's plan (omitted = Gesamt). Each `target_weight` is a string fraction
  in `[0, 1]`; targets need not sum to `1`. Only the supplied categories are
  changed. A category from another tree returns `422 Unprocessable Entity`, and an
  unknown classification returns `404 Not Found`. **Position-level SOLL
  (ADR-0030):** a target entry that also carries a `"security_id"` sets a weight
  on that individual position under the category (the security must sit under it,
  else `422`); a category entry (no `security_id`) and its position entries are
  stored side by side. A present `security_id` must be a positive integer or
  `null` (`null` = category row) — anything else (a non-numeric string, a float)
  returns `422` instead of being coerced into a category write. A plan carries
  at most **one position row per security**: filing a security under a second
  category, or naming the same `(category, security)` twice in one batch,
  returns `422`. Each serialized target carries `security_id` (`null` for a
  category row).
- `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` removes a
  portfolio's **category** target for one category and returns `{deleted}` (the
  number of rows removed). Position rows for the category are left in place.
  Optional `view` selects the plan (omitted = Gesamt).
- `GET /api/v1/portfolios/:portfolio_id/position_targets` lists a portfolio's
  **position-level** SOLL targets (ADR-0030): `{"position_targets": [...],
  "effective_targets": [...]}`. Each `position_targets` row is a target on a
  security under a category (with `security_id` and `security_name`); each
  `effective_targets` entry
  is a category's roll-up — `explicit` (the category-row weight or `null`),
  `position_sum` (the sum of the position rows filed directly under it —
  descendants' rows roll up to their own category), `effective` (the resolved steering
  weight — the position sum wins) and `conflict` (`true` when explicit and
  position sum disagree, surfacing the mismatch). Each position row also carries
  `stale` (`true` when its security no longer sits under the stored category —
  reclassified or unassigned; the row still counts where it was filed, re-filing
  is the remedy) and each roll-up `has_stale`. Weights are Decimal strings.
  Optional `classification_id` / `view` scope as above.
- `DELETE /api/v1/portfolios/:portfolio_id/position_targets/:category_id/:security_id`
  removes one position target and returns `{deleted}`. The category row and the
  category's other positions are untouched. Optional `view` selects the plan.
- `GET /api/v1/portfolios/:portfolio_id/plans` lists a portfolio's SOLL **plan
  versions** (ADR-0027): active first, then drafts and archived plans, each with
  `name`, `status` (`active` / `draft` / `archived`), its scope (`view_id`,
  `classification_id`) and `cash_target_weight` as a Decimal string. Optional
  `classification_id` scopes to one tree. Only the **active** plan of a scope
  steers the allocation.
- `POST /api/v1/plans/:id/duplicate` copies a plan version (category targets and
  cash target) into a new **draft** of the same scope and returns it with
  `201 Created`. Optional body `{"name": "Plan 2027"}` names the copy (default:
  `"<source name> (copy)"`).
- `POST /api/v1/plans/:id/activate` makes a draft or archived version the active
  plan of its scope, archiving the previously active plan in the same
  transaction. Activating the already-active plan is a no-op.
- `PATCH /api/v1/plans/:id` renames a plan version (`{"name": "..."}`).
- `DELETE /api/v1/plans/:id` deletes one plan version (any status) including its
  category targets. Deleting the active plan leaves the scope without a plan
  (the allocation falls back to actual-only).
- `GET /api/v1/snapshots` lists depot **snapshot markers** (ADR-0027): each is a
  `name`, a scope (`view_id`, `null` = everything) and an `as_of` date. A
  snapshot copies no financial data — the holdings it represents derive from
  the transaction ledger on demand.
- `POST /api/v1/snapshots` creates a marker
  (`{"name": "...", "as_of": "2026-02-15", "view_id": 3}`; `view_id` optional).
  A future `as_of` or a duplicate name within the scope returns
  `422 Unprocessable Entity`.
- `DELETE /api/v1/snapshots/:id` deletes one marker; no transactions or
  holdings are affected.

### Recorded tax statements (ADR-0031)

**These pots are recorded, not derived** — and the reason is *not* a missing
FIFO. Portfolixir matches lots FIFO already (`GET
/api/v1/securities/:id/trades`), and that gives a **gross gain**. A gross gain
is not a tax pot: Teilfreistellung, Vorabpauschale, chronological allowance
consumption and certified prior-year carry-forward are not in the transaction
data at all, and the pots are kept per tax-reporting institution, which
Portfolixir does not model. A derived pot would be wrong, and invisibly so — so
these endpoints transcribe a broker statement, they never compute one from
holdings. Every money value is a
**positive magnitude** Decimal string: a loss pot is the volume of loss
available for offsetting, not the negative number the statement prints, and a
negative input is rejected rather than silently flipped. Nothing here is tax
advice, and the recorded statement remains the authority. (A tax actually
credited back to a cash account — for example after a loss sale — is a ledger
event, not a pot: book it as a separate `tax_refund` transaction as described
under "Transactions and Holdings" above.)

- `GET /api/v1/tax/parameters` lists the year-scoped statutory parameters
  (optional `jurisdiction`, currently only `DE`): `capital_gains_tax_rate`,
  `solidarity_surcharge_rate` and the `saver_allowance_single` /
  `saver_allowance_joint` ceilings. Rates are Decimal string **fractions**
  (`"0.25"`, never `"25"`). Seeded 2009–2026; a year with no row is simply
  absent — the API never substitutes a neighbouring year's ceiling.
- `PUT /api/v1/tax/parameters` inserts or replaces one year's parameters
  (`{"parameters": {"tax_year": 2027, ...}}`).
- `GET /api/v1/tax/profiles` lists a holder's effective-dated tax profiles
  (required `holder`; a missing one returns `422 Unprocessable Entity`), newest
  `valid_from` first. The profile in force for a date is the row with the
  greatest `valid_from` at or before it — never an exact match. Church-tax
  liability defaults to **not liable** with rate `0`.
- `POST /api/v1/tax/profiles` records a profile from a date
  (`{"profile": {"holder": "...", "valid_from": "2024-01-01"}}`). A non-zero
  `church_tax_rate` on a not-liable profile is rejected.
- `PATCH /api/v1/tax/profiles/:id` corrects one profile row. To record a
  *change* in the situation, create a new row with a later `valid_from` —
  editing rewrites history, adding does not.
- `DELETE /api/v1/tax/profiles/:id` deletes one profile row. Snapshots already
  recorded keep their frozen church-tax rate and are unaffected.
- `GET /api/v1/tax/allowance_orders` lists the Freistellungsaufträge the
  taxpayer **instructed** (optional `holder`, `institution`, `tax_year`;
  free-text filters fold case, so `comdirect` and `Comdirect` are one
  institution).
- `PUT /api/v1/tax/allowance_orders` records or replaces the instructed amount
  for one `(holder, institution, tax_year)`
  (`{"allowance_order": {...}}`).
- `DELETE /api/v1/tax/allowance_orders/:id` deletes one configured order.
- `GET /api/v1/tax/statement_snapshots` lists recorded statements (optional
  `holder`, `institution`, `tax_year`), newest `as_of` first. Each row carries
  the eleven recorded figures plus `allowance_remaining`,
  `tax_free_trim_budget`, `expected_capital_gains_tax`, the `as_of` they rest
  on, a `stale` flag, and the advisory `findings`. Each row also carries the
  activity-aware `staleness` assessment (#667): staleness as a function of
  activity, not only of the calendar. It states its own computation basis —
  `age_days` against `age_threshold_days` (90), `activity_since_count` (the
  ledger transactions of `activity_kinds` — `sell`, `dividend`, `interest`,
  `tax`, `tax_refund` — dated strictly after `as_of`), the two component
  warnings and the combined `warning`, plus a `basis` note recording that
  bookings are not attributed to an institution or tax year. `warning` is the
  signal to act on; the bare `stale` flag flips the day after any `as_of` and
  is kept for compatibility.
- `POST /api/v1/tax/statement_snapshots` records a statement
  (`{"statement_snapshot": {"institution": "...", "holder": "...",
  "tax_year": 2025, "as_of": "2025-12-31", ...}}`). `as_of` must not lie in the
  future. Omit `church_tax_rate` to take the holder's profile in force at
  `as_of`; the resolved rate is then frozen on the row, so a later profile edit
  never rewrites a recorded transcription. Re-recording the same
  `(institution, holder, tax_year, as_of)` is a `422`, not a silent duplicate.
- `GET /api/v1/tax/trim_budget` rolls the latest statement per institution up
  to one holder and year (required `holder` and `tax_year`). It reports which
  `institutions` it covers, the `as_of` of its **oldest** component, and
  `complete: false` with `missing_institutions` when a configured allowance
  order has no recorded statement for the year — the total is then a partial
  picture and says so. The response carries the same `staleness` assessment,
  computed against the roll-up's (oldest) `as_of`.
- `GET /api/v1/tax/statement_snapshots/:id` reads one recorded statement.
- `PATCH /api/v1/tax/statement_snapshots/:id` corrects one recorded statement
  in place — the re-issued-statement case.
- `DELETE /api/v1/tax/statement_snapshots/:id` deletes one recorded statement.

Consistency findings are advisory and computed at read time. A finding names
the `recorded` and the `expected` number and the `gap`; it never proposes a
corrected value and never blocks a write. Two rules are hard instead, and come
back as `422` changeset errors: allowance used above allowance granted, and
church tax withheld at a zero church-tax rate.
- `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison` answers
  "would I have done better keeping what I had?": the snapshot's frozen
  holdings valued **buy-and-hold** over the stored quote history (daily, EUR-hub
  FX) against the scope's real TTWROR since the as-of date. The response
  carries `as_of_value`, `current_value`, `snapshot_return`, `real_ttwror`, a
  daily `series` (`snapshot_value`, `snapshot_indexed`, `real_indexed`), a
  `gaps` list of securities excluded for missing quotes or FX at the as-of
  date, and a self-describing `basis` (gross, price-return only in v1). All
  financial values are Decimal strings.
- `GET /api/v1/portfolios/:portfolio_id/category-results?classification_id=<id>` —
  per-category **result** (ADR-0041 slice one, #712): `invested` (the sum of the
  members' base-currency cost), `current_value`, `result_abs` and `result_pct`
  per category, plus the member `positions` that produced it and the `excluded`
  rows it could not cover.

  **Read the basis before the numbers.** The payload states it in one line
  (`basis: "current_composition"`, with a `basis_note` spelling it out): this is
  a figure about the positions filed under each category **today**, so there is
  no period, no membership variant and no as-of — and it is not a time-weighted
  return series.

  `result_pct` is `Σ result ÷ Σ invested`, **never** a mean of the members'
  percentages: averaging lets a tiny position at +300 % dominate a category that
  is flat in money. A member whose result is not derivable — no usable price, or
  no base-currency decomposition (ADR-0033) — is excluded from **both** sides of
  the sum and listed under `excluded` with its `reason`; it is never counted as
  zero, which would quietly understate the category. `covered_count` and
  `member_count` state how much of the category the figure covers. A category
  with nothing invested reports `result_pct: null` rather than `"0"`, because
  having nothing to measure is a different claim from being flat. MCP:
  `portfolixir.portfolios.category_results`.

- `GET /api/v1/portfolios/:portfolio_id/allocation` returns the target/actual
  breakdown for one classification (required `classification_id` query param; a
  missing one returns `422 Unprocessable Entity`). For each category it reports
  `parent_id` and `depth` (the categories form a tree), `color`,
  `own_market_value` (positions assigned directly to it), `market_value` (its
  whole subtree rolled up), `actual_weight` (the rolled-up share of
  `total_value`), `target_weight`, `drift_weight`
  (`actual_weight - target_weight`: positive = overweight, negative =
  underweight; ADR-0023), and `drift_value` (the drift restated in
  the base currency — how much to sell (positive) or buy (negative) to reach
  the target). Each row also carries `child_target_sum` (Decimal string):
  the advisory sum of its **direct** children's targets, or `null` when no direct
  child carries a target — a target-consistency hint the UI can flag against the
  row's own `target_weight`. A position assigned to a child counts toward that child
  **and every ancestor**, so a parent category with a target is compared
  against its subtree rather than showing 0%; the rows come back in tree order
  (parent before its children). Because parents aggregate their children, the
  per-category `actual_weight` values intentionally do not sum to 1 across
  levels — only the leaves plus `unassigned` do. Each category (and
  `unassigned`) also carries `positions`: the per-security breakdown of its
  **own** (directly assigned) value — `security_id`, `security_name`,
  `quantity`, `market_value`, `weight`, plus the display-only rebalancing
  hints (ADR-0023): `drift_value` (the position's proportional share of the
  category drift) and `rebalance_quantity` (indicative units to sell
  (positive) or buy (negative) at the valuation's implied base-currency unit
  price; no fee/tax modelling, never an order). Both hints are `null` without
  a plan and for `unassigned` positions without their own position SOLL.
  Entries come largest first,
  securities merged across depots;
  this is what the sunburst's outermost ring renders. **Position-level SOLL
  (ADR-0030 slice 2a):** a category's `positions` are the union of its held
  positions and the active plan's position-target rows, matched by security.
  Each entry additionally carries `target_weight` (its position SOLL, `null`
  when none), `drift_weight` (`actual weight − target weight`, ADR-0023 sign)
  and `held`. An entry with its own SOLL derives `drift_value` and
  `rebalance_quantity` from that own drift instead of the category share. A
  position with SOLL > 0 that is not yet held appears with IST 0 (`held:
  false`, quantity/value/weight `"0"`) and full underweight drift — "this
  needs buying" — with its indicative quantity priced at the **latest stored
  quote** (`null` when no price exists; none is invented); `quote_date` names
  that quote's date (`null` when the hint is not quote-based). `held` means
  holdings presence: a held security whose price cannot be determined is never
  reported as unheld (it stays on the unvalued surfaces instead). Each entry
  also carries `stale` (`true` when its attached position-target row no longer
  matches the security's current category). A position is
  hidden only when its SOLL is 0/absent **and** its holdings are zero. Each
  category row also carries `conflict` (its explicit weight and position sum
  disagree — the sum steers) and `has_stale` (a position row filed under it is
  stale), and the breakdown carries `deep_target_sum` — the effective targets'
  sum at the topmost targeted level per subtree, which explains a `0`
  `top_level_target_sum` over a plan steered deeper in the tree.
  Securities held but not
  assigned in the tree are summed into `unassigned`; unassigned entries attach
  their position SOLL too. Weights are shares of the
  **steering basis**: the valued positions' total (scoped by the active `view`
  when one is passed), **plus the deployable cash** (`free_cash`
  accounts with a non-negative balance). `total_value`
  here is that steering basis (not the full valuation). The response carries a
  `cash` object — `market_value` (the counting cash), `actual_weight` (its share
  of `total_value`), `target_weight` (the active view's plan cash target, or `0`
  when unset; see the cash-target endpoints below), `drift_weight`
  (`actual_weight - target_weight`, ADR-0023),
  `drift_value` (restated in the base currency), and `distributed` (boolean) —
  so cash is steered in the same drift logic as the categories. When the active
  classification is the built-in **currency** tree, each cash account's
  deployable balance is attributed to its own currency-code category instead of
  appearing as a separate cash row: EUR cash flows into the EUR category, USD
  cash into USD, and so on. In that case `cash.distributed` is `true` and
  consumers should omit the separate cash row; for all other classifications
  `distributed` is `false` and the cash row behaves as before. Because cash is
  part of the 100% basis, the category percentages shrink accordingly once cash
  is present. The `top_level_target_sum` is the sum of the root categories'
  targets **plus the cash target** (except for the currency classification where
  cash is distributed into categories), compared against `1`. A plan may
  deliberately allocate **less** than 100%: `unallocated_remainder` states that
  gap (`1 − top_level_target_sum`, `"0"` when the plan is full) and
  `drift_basis` names what the drift figures were measured against —
  `"allocated_portion"` when each target was renormalised to the allocated share
  first, so the unsteered remainder is not reported as phantom overweight, and
  `"full_plan"` when the plan sums to 100% and drift is the plain
  `actual − target`. The remainder is computed on read, never stored (ADR-0040). To keep a holding
  out of the steering basis while it still counts toward total wealth, tag it
  with a bucket and exclude that bucket from the `view` the allocation is read
  under — it then falls outside the scoped positions. Since ADR-0020 the **target**
  side reflects the **active view's plan**: passing `view=<id>` reports that
  view's target weights, cash target and `top_level_target_sum` (omitting it uses
  the Gesamt plan), so the drift table steers against one coherent 100% plan per
  view. Category `target_weight` values are the **effective** targets
  (ADR-0030): the sum of a category's position rows when any exist (positions
  are the source of truth), else its explicit category weight — the Σ figures
  consume the same effective values. For the raw position-target rows and
  per-category roll-up (the maintenance view) use the `position_targets`
  endpoint above. Unknown portfolios or
  classifications return `404 Not Found`. Read ergonomics (FR-37):
  `include_positions=false` omits the per-category (and `unassigned`)
  position rows for a roll-up-only read, and `min_drift=<decimal>` (an
  absolute drift-weight threshold, e.g. `0.02`) returns only the category
  rows whose `|drift_weight|` meets it — targetless categories carry no
  drift and are filtered out with it, and kept rows come back flat (an
  ancestor under the threshold is absent). The response states its own
  basis: `positions_included`, the applied `min_drift` and
  `categories_total` (the pre-filter category count). Invalid values are a
  `422`. `tax_context=true` (#667) additionally attaches the current-year
  tax-free trim budgets — one entry per holder with recorded statements,
  each with its activity-aware `staleness` — so the tax headroom is
  readable where the trim decision is made; the block states that it rolls
  up per `(holder, tax_year)` across institutions and is never scoped to
  the portfolio or view.
- `GET /api/v1/portfolios/:portfolio_id/risk` returns a **risk/concentration
  lens** for one portfolio over the **steerable basis** (the valued positions,
  scoped by the active `view`, the same
  basis the allocation drift uses). A security held across several depots is
  merged into one single-name exposure. Weights, caps and the HHI are all on a
  **0-100 percentage scale** (Decimal strings, full precision, no rounding):
  - `steerable_basis` is the basis the weights are a share of, and
    `base_currency` the portfolio's base currency.
  - `top_holdings` is the largest single-name exposures, largest first, default
    **N = 10** (override with the `top_n` query param). Each entry carries
    `security_id`, `security_name`, `asset_class`, `market_value`, `weight` and a
    `severity` (`ok`/`warn`/`hard`). The severity is **instrument-type aware**: a
    single stock warns above `7` and goes hard above `10`; an **ETF** (the `etf`
    asset class) warns above `25` and never goes hard. Override the defaults with
    the `stock_thresholds[warn]`/`stock_thresholds[hard]` and
    `etf_thresholds[warn]` query params.
  - `hhi` carries the Herfindahl-Hirschman Index of the single-name weights
    (`value` = the sum of the squared percentage weights, on the `0-10000`
    scale) plus a `band`: `low` (`< 1500`), `moderate` (`[1500, 2500]`) or
    `concentrated` (`> 2500`). Override the cutoffs with the `hhi_bands[low]` and
    `hhi_bands[high]` query params.
  - `asset_class_violations` are **opt-in** asset-class cap violations: there are
    no shipped defaults, so caps are configured per call with the
    `asset_class_caps[<asset_class>]` query param (a percentage, e.g.
    `asset_class_caps[equity]=50`). Only classes whose current percentage weight
    exceeds the cap come back, each with `asset_class`, `current_weight`, `cap`
    and `overage` (current − cap, in percentage points).

  The lens is a pure read-time derivation of the live valuation and the
  securities' asset classification — nothing is stored, so it is deterministic on
  read. A malformed override (e.g. a non-positive `top_n`) returns `422
  Unprocessable Entity`; unknown portfolios return `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/cash_target` reads a plan's cash target,
  the target cash share of the allocation's 100% basis (securities + counting
  cash). The response is `{"cash_target_weight": "0.05"}` (a string fraction in
  `[0, 1]`, or `null` when none is steered). Optional `view` selects the plan
  (omitted = the Gesamt plan). Unknown portfolios return `404 Not Found`, a
  malformed `view` returns `422`, and an unknown view id returns `404`.
- `PUT /api/v1/portfolios/:portfolio_id/cash_target` sets (or clears with
  `null`) a plan's cash target. The body is `{"cash_target_weight": "0.05"}` and
  may carry an optional `"view": id` (omitted = Gesamt). It echoes the stored
  value back. Out-of-range weights return `422 Unprocessable Entity`. The cash
  target feeds the allocation's `cash` row and the `top_level_target_sum` for the
  addressed view.
- `PATCH /api/v1/portfolios/:portfolio_id` patches a portfolio's master data.
  **Deprecated (ADR-0024)** — answers with `Deprecation: true`; compatibility
  only, use buckets/views for grouping. The body is `{"portfolio": {...}}`. **Cash target move (ADR-0020):** the cash
  target moved off the portfolio object onto the per-view target plan, served by
  the two `cash_target` endpoints above. For **back-compatibility** the portfolio
  object still exposes `cash_target_weight` — a string fraction in `[0, 1]` (e.g.
  `"0.05"` for 5%), or `null` to stop steering a cash quote — and patching it
  reads/writes the **Gesamt** plan's cash target (`view` omitted). So a client
  that only knows the old field keeps working unchanged; use `PUT
  /cash_target?view=<id>` to steer a per-view cash target. Out-of-range weights
  return `422 Unprocessable Entity`; unknown portfolios return `404 Not Found`.
  The `cash_target_weight` is also included in the portfolio objects returned by
  `GET`/`POST /api/v1/portfolios` (the Gesamt cash target).
- `GET /api/v1/securities/:security_id/trades` returns FIFO-matched trades for
  one security: open lots, closed round-trips (with realised P&L and holding
  period in days) and any orphan sells. Each open lot carries `buy_price` (as
  recorded, transaction currency) plus `buy_price_native` — the
  security-currency basis its `unrealized_pnl_*` is computed against
  (ADR-0033) — and the same base-currency decomposition fields as the
  holdings rows (`base_cost`, `price_return_*`, `currency_return_*`,
  `total_return_base_*`, `decomposed`/`undecomposed_reason`, against the EUR
  hub, since FIFO lots are matched per security across portfolios). A lot
  with no derivable native leg reports `null` P&L instead of a blind
  cross-currency figure. The response is self-describing (FR-13):
  it carries `method: "fifo"`, so a client never has to assume how lots were
  paired against sells. Optional `from`/`to` (ISO dates) filter each leg by its
  own date: open lots by open date, closed round-trips by close date, orphan
  sells by sell date.

## Exchange Rates

- `GET /api/v1/exchange_rates` lists stored exchange rates. Rates are kept
  against the EUR hub (`1 base_currency = rate quote_currency`); other pairs are
  derived by triangulation, and `GBX` (pence) is handled as `GBP × 100`.
- `POST /api/v1/exchange_rates/sync` fetches the latest rates from the configured
  provider (ECB daily reference rates by default) and returns `{provider,
  status, upserted}`. A provider failure returns `502 Bad Gateway`.

## Classifications

Classification trees organise securities like folders. Built-in trees
(`asset_class`, `currency`) are derived automatically and their structure is
locked; editing the structure of a built-in tree returns `422 Unprocessable
Entity`. The **asset-class** tree's membership, however, is just a view of each
security's `asset_class` field: in the UI a security is dragged between its
categories (which sets that field), and the same effect is achieved over the API
with `PATCH /api/v1/securities/:id` (`{"security": {"asset_class": "etf"}}`) or
the `securities.update` MCP tool. Set it to empty/`null` for "automatic", which
re-infers the class from the security's name/ISIN/ticker on read. The currency
tree stays intrinsic and cannot be reassigned.

- `GET /api/v1/classifications` lists every classification as a tree with its
  `categories` and `assignments` (`{security_id, category_id}`). Built-in trees
  carry `built_in: true` and a `key`.
- `POST /api/v1/classifications` creates a custom classification from a
  `classification` object (`name`, optional `position`, `description`).
- `PATCH /api/v1/classifications/:id` updates a custom classification's
  `classification` object (`name`, `position`, `description` — all optional).
- `DELETE /api/v1/classifications/:id` deletes a custom classification and
  cascades its categories and assignments.
- `POST /api/v1/classifications/:classification_id/categories` adds a `category`
  (`name`, optional `color`, `description`, `parent_id`, `position`) to a custom
  classification.
- `PATCH /api/v1/classifications/:classification_id/categories/:id` patches a
  `category` (`name`, `color`, `description`, `parent_id`, `position` — all
  optional). The category's `classification_id` cannot be changed this way.
- `DELETE /api/v1/classifications/:classification_id/categories/:id` deletes a
  category and cascades its child categories and assignments.
- `PUT /api/v1/classifications/:classification_id/assignments` assigns a security
  to a category (`security_id`, `category_id`), replacing any existing assignment
  for that security in the classification. The response carries a `status` of
  `created`, `moved`, or `unchanged` plus `previous_category_id`.
- `PUT /api/v1/classifications/:classification_id/assignments/bulk` assigns many
  securities to one category in a single call (`category_id`, `security_ids`),
  returning `{assigned, category_id, security_ids}`.
- `DELETE /api/v1/classifications/:classification_id/assignments/:security_id`
  removes a security's assignment from the classification.

Example transaction payload:

```json
{
  "transaction": {
    "portfolio_id": 1,
    "securities_account_id": 1,
    "security_id": 1,
    "type": "buy",
    "date": "2026-05-15",
    "quantity": "10.00000000",
    "price": "123.45",
    "fees": "1.50",
    "taxes": "0",
    "currency_code": "EUR"
  }
}
```

## Buckets and Views

Buckets are overlapping tags applied to holdings (depots, cash accounts and
individual security positions) for tag-based wealth scoping. Views are named,
global filters over those buckets: a holding matches when it is included
(always under `include_all`, otherwise when it carries one of the view's include
buckets) and carries none of the view's exclude buckets — exclude always wins.
Bucket-definition and assignment writes are journaled (ADR-0017); view-definition
writes are deliberately not journaled (ADR-0018 §5).

- `GET /api/v1/buckets` lists buckets (`id`, `name`, `color`, `dimension`).
  `dimension` is `"tag"` (a free overlapping tag) or `"scope"` — the exclusive
  dimension: a depot or cash account carries **at most one** scope bucket, so
  scope-scoped totals always add up (ADR-0024).
- `POST /api/v1/buckets` creates a bucket from a `bucket` object (`name`
  required, optional `color`, optional `dimension` defaulting to `"tag"`).
  A blank or duplicate name, or an unknown dimension, returns `422`.
- `GET /api/v1/buckets/:id` returns one bucket; unknown ids return `404`.
- `PATCH /api/v1/buckets/:id` patches a bucket's `name`/`color`. The
  `dimension` is fixed at creation; attempts to change it return `422`.
- `DELETE /api/v1/buckets/:id` deletes a bucket and cascades it out of every
  assignment and view set, returning `204 No Content`.
- `GET /api/v1/views` lists views. Each view carries `include_all`, the resolved
  `include` set (the literal `"all"` under `include_all`, otherwise a list of
  bucket ids) and the `exclude` list of bucket ids.
- `POST /api/v1/views` creates a view from a `view` object (`name` required,
  optional `include_all` defaulting to `true`).
- `GET /api/v1/views/:id` returns one view with its resolved filter.
- `PATCH /api/v1/views/:id` patches a view's `name`/`include_all`.
- `DELETE /api/v1/views/:id` deletes a view and its bucket sets (`204`).
- `PUT /api/v1/views/:id/buckets` replaces a view's include/exclude bucket sets.
  Body: `{"include": [..], "exclude": [..]}` (both optional, default `[]`,
  arrays of bucket ids). A malformed id list returns `422`.
- `GET /api/v1/views/:view_id/valuation` returns the live valuation of a view
  **across all portfolios** (ADR-0024): the deduplicated union of every depot,
  position and cash account matching the view — an account tagged into several
  included buckets counts exactly once. The shape mirrors the portfolio
  valuation (totals, positions with weights and `price_source`/`valued` flags,
  `cash_balances`, `cash_quote`, `as_of`, a `valuation_note`) with `view_id` in
  place of `portfolio_id`; totals are in EUR, converted via the EUR hub, and
  all financial values are Decimal strings. An `overlap` object reports the
  account-level bucket overlap for UI badges (`overlapping`, plus the
  `securities_account_ids`/`cash_account_ids` carrying more than one included
  bucket — the totals are already deduplicated). The active view is echoed as
  `view: {id, name}`. Unknown and malformed view ids return `404`.
- `GET /api/v1/views/:view_id/performance` returns the view's TTWROR and
  money-weighted IRR **across all portfolios**: exactly the deduplicated
  account scope the view valuation covers, so the total and the return always
  speak about the same accounts. Money crossing the view boundary counts as an
  external flow (ADR-0019); money moving between two in-scope accounts nets
  out. `?period=` (`ytd|1y|3y|5y|max`, default `max`), `?year=YYYY`,
  `?from=`/`?to=` (custom range) and `?series=true` behave like the portfolio
  performance endpoint; the shape mirrors it with `view_id` in place of
  `portfolio_id`, and all financial values are Decimal strings. Unknown and
  malformed view ids return `404`; a bad period `422`.
- `PUT /api/v1/securities_accounts/:id/buckets` replaces a depot's default
  bucket set (the buckets each position inherits unless overridden). Body:
  `{"bucket_ids": [..]}`. At most one of the ids may be a scope-dimension
  bucket; a violating set returns `422` without writing anything.
- `PUT /api/v1/cash_accounts/:id/buckets` replaces a cash account's bucket set.
  Body: `{"bucket_ids": [..]}`. The same at-most-one-scope-bucket rule applies.
- `PUT /api/v1/securities_accounts/:id/positions/:security_id/buckets` sets the
  per-position override for one security in one depot. An empty `bucket_ids`
  records the **explicit-empty** state (deliberately no buckets), distinct from
  inheriting the depot default; the override always wins over the depot default.
  The response reports the resolved `override` (`inherit`, `explicit_empty` or
  `explicit`) and the `effective_bucket_ids`.
- `DELETE /api/v1/securities_accounts/:id/positions/:security_id/buckets` clears
  the override, returning the position to inherit the depot default.

The analytics endpoints accept an optional `view` query param (a view id) to
scope the result to the holdings matching that view:

- `GET /api/v1/portfolios/:portfolio_id/valuation?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/allocation?classification_id=<id>&view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/performance?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/risk?view=<id>`

When a `view` is supplied, the response echoes the active view as
`view: {id, name}` (FR-13); the unscoped/default call is unchanged and carries
no `view` field. A malformed view id returns `422`; an unknown view id returns
`404`. The same `view` scope (and the same `422`/`404` contract) applies to the
target endpoints — `GET`/`PUT
/api/v1/portfolios/:portfolio_id/targets`, `DELETE
/api/v1/portfolios/:portfolio_id/targets/:category_id` and the cash-target
endpoints `GET`/`PUT /api/v1/portfolios/:portfolio_id/cash_target` — where a
view selects the target plan (omitted = the Gesamt plan). The holdings endpoint
(`GET /api/v1/portfolios/:portfolio_id/holdings`) is **not** view-scoped: it
returns the raw per-(depot, security) rows in each security's own currency, so a
client can apply the buckets/views model itself using each row's
`securities_account_id` and `security_id`.

## Settings

A minimal keyed preference store backs the user-facing defaults (ADR-0024).
Today it carries one preference: the **default view** the Wealth page and
dashboard open on when no explicit view was chosen in the UI. No financial
decimals are involved.

- `GET /api/v1/settings/default_view` returns the current default:
  `{"data": {"view_id": null, "view": null}}` when unset (the built-in
  Everything scope), otherwise the id plus a `view: {id, name}` echo.
- `PUT /api/v1/settings/default_view` sets it. Body: `{"view_id": <id>}` with a
  live view id, or `{"view_id": null}` to clear back to Everything. An unknown
  view id returns `404` (nothing is written); a malformed `view_id` returns
  `422`. The response mirrors the `GET` shape.

## Audit Journal

Every financial write (create, update, delete) is recorded in an append-only
audit journal in the same database transaction as the write itself, so any
change — including deletions — stays attributable and reversible by inspection.
Market-data ingestion (quote and exchange-rate sync) is operational data and is
deliberately **not** journaled.

- `GET /api/v1/journal` lists journal entries, newest first. Each entry carries
  `actor_type` (`owner_ui`, `api_token_rw`, `api_token_ro`, `import_session`,
  `system_job`) and an optional `actor_label`, the `operation`
  (`create`, `update`, `delete`, `upsert`), the `resource_type`/`resource_id`
  it touched, and the `before`/`after` snapshots (Decimal values are strings).
  Optional filters: `resource_type`, `resource_id`, `actor_type`, `operation`,
  `limit` (default 100, max 1000) and `include_scenarios` (`true` to include
  persisted what-if writes; real writes only by default). The response is
  self-describing: a `meta` object echoes the `as_of` instant, the `order`
  (`inserted_at:desc,id:desc`), the `count` and the `filters` applied.
  SOLL target writes (category and position rows alike) are journaled under
  `resource_type=target`; plan-version writes under `resource_type=target_plan`.

The journal currently covers the Catalog/Fx contexts (security master-data
writes); the remaining write contexts are armed in sequence.

## MCP Tools

The MCP companion exposes the same local contract as tool calls. Decimal inputs
in MCP schemas are strings.

- `portfolixir.securities.list`
- `portfolixir.securities.get` — one security's full record including its
  `identifier_aliases` (recorded former ISINs).
- `portfolixir.securities.create`
- `portfolixir.securities.update`
- `portfolixir.securities.delete`
- `portfolixir.securities.isin_change` — records a corporate-action ISIN
  change so imports keep matching via the former ISIN (ADR-0029).
- `portfolixir.securities.delete_isin_alias` — journaled delete of one
  recorded former-ISIN alias.
- `portfolixir.securities.search_online`
- `portfolixir.quotes.sync`
- `portfolixir.quotes.list`
- `portfolixir.quotes.upsert`
- `portfolixir.portfolios.list` — deprecated (ADR-0024): steers to
  buckets/views in its description.
- `portfolixir.portfolios.create` — deprecated (ADR-0024): compatibility only;
  prefer `portfolixir.buckets.create` / `portfolixir.views.create`.
- `portfolixir.cash_accounts.list`
- `portfolixir.cash_accounts.create`
- `portfolixir.cash_accounts.update`
- `portfolixir.cash_accounts.delete`
- `portfolixir.cash_accounts.set_balance`
- `portfolixir.securities_accounts.list`
- `portfolixir.securities_accounts.create`
- `portfolixir.securities_accounts.update`
- `portfolixir.securities_accounts.delete`
- `portfolixir.transactions.list`
- `portfolixir.transactions.create`
- `portfolixir.transactions.update`
- `portfolixir.transactions.delete`
- `portfolixir.splits.preview`
- `portfolixir.splits.create`
- `portfolixir.holdings.list`
- `portfolixir.holdings.by_security`
- `portfolixir.holdings.negative`
- `portfolixir.holdings.reconcile` — read-only compare of a pasted external
  position list against the ledger; its description steers the agent toward
  booking the missing transaction of the correct kind instead of balance
  snapshots or unpriced deliveries.
- `portfolixir.portfolios.valuation`
- `portfolixir.exchange_rates.list`
- `portfolixir.exchange_rates.sync`
- `portfolixir.classifications.list`
- `portfolixir.classifications.create`
- `portfolixir.classifications.categories.create`
- `portfolixir.classifications.update`
- `portfolixir.classifications.delete`
- `portfolixir.classifications.categories.update`
- `portfolixir.classifications.categories.delete`
- `portfolixir.classifications.assign`
- `portfolixir.classifications.assign_bulk`
- `portfolixir.classifications.unassign`
- `portfolixir.trades.list`
- `portfolixir.targets.list`
- `portfolixir.targets.set`
- `portfolixir.targets.delete`
- `portfolixir.targets.list_positions`
- `portfolixir.targets.delete_position`
- `portfolixir.portfolios.allocation`
- `portfolixir.portfolios.risk`
- `portfolixir.portfolios.cash_target`
- `portfolixir.portfolios.set_cash_target`
- `portfolixir.portfolios.income`
- `portfolixir.portfolios.performance`
- `portfolixir.journal.list`
- `portfolixir.buckets.list`
- `portfolixir.buckets.get`
- `portfolixir.buckets.create`
- `portfolixir.buckets.update`
- `portfolixir.buckets.delete`
- `portfolixir.views.list`
- `portfolixir.views.get`
- `portfolixir.views.create`
- `portfolixir.views.update`
- `portfolixir.views.delete`
- `portfolixir.views.set_buckets`
- `portfolixir.views.valuation`
- `portfolixir.views.performance`
- `portfolixir.securities_accounts.set_buckets`
- `portfolixir.cash_accounts.set_buckets`
- `portfolixir.securities_accounts.set_position_buckets`
- `portfolixir.securities_accounts.clear_position_buckets`
- `portfolixir.settings.get_default_view`
- `portfolixir.settings.set_default_view`
- `portfolixir.plans.list`
- `portfolixir.plans.duplicate`
- `portfolixir.plans.activate`
- `portfolixir.plans.rename`
- `portfolixir.plans.delete`
- `portfolixir.snapshots.list`
- `portfolixir.snapshots.create`
- `portfolixir.snapshots.delete`
- `portfolixir.snapshots.comparison`
- `portfolixir.tax_parameters.list`
- `portfolixir.tax_parameters.upsert`
- `portfolixir.tax_profiles.list`
- `portfolixir.tax_profiles.create`
- `portfolixir.tax_profiles.update`
- `portfolixir.tax_profiles.delete`
- `portfolixir.allowance_orders.list`
- `portfolixir.allowance_orders.put`
- `portfolixir.allowance_orders.delete`
- `portfolixir.tax_snapshots.list`
- `portfolixir.tax_snapshots.get`
- `portfolixir.tax_snapshots.create`
- `portfolixir.tax_snapshots.update`
- `portfolixir.tax_snapshots.delete`
- `portfolixir.tax_snapshots.trim_budget`

The `portfolixir.portfolios.valuation`, `portfolixir.portfolios.allocation`,
`portfolixir.portfolios.performance` and `portfolixir.portfolios.risk` tools
accept an optional `view` (a view id) that scopes the result to the holdings
matching that bucket view; the response then echoes the active view.
`portfolixir.views.valuation` values a view **across all portfolios** in one
call (each matching account counted once, EUR totals, `overlap` badge data) —
use it instead of summing per-portfolio valuations client-side.
`portfolixir.views.performance` computes the matching cross-portfolio
TTWROR/IRR for the same account scope, with boundary-crossing money treated
as an external flow (ADR-0019).
`portfolixir.settings.get_default_view` / `portfolixir.settings.set_default_view`
read and set the default-view preference (ADR-0024): pass a `view_id` to pin a
view, or `null`/omit it to clear back to the built-in Everything scope.

Since ADR-0020 the target tools (`portfolixir.targets.list`,
`portfolixir.targets.set`, `portfolixir.targets.delete`) and the cash-target
tools (`portfolixir.portfolios.cash_target` to read,
`portfolixir.portfolios.set_cash_target` to set or clear) also accept an optional
`view` (a view id) that selects the target plan; omitting it addresses the
portfolio-wide Gesamt plan. The cash target moved off the portfolio object onto
the plan, but `portfolixir.portfolios.set_cash_target` without a `view` still
steers the Gesamt cash target, so it keeps the same effect as the legacy
portfolio `cash_target_weight` field. All cash targets and target weights are
exposed and accepted as Decimal strings.

Since ADR-0030 (#481) the same tools carry **position-level** SOLL: a
`portfolixir.targets.set` entry that adds a `security_id` sets a weight on that
individual position under its category, `portfolixir.targets.list_positions`
reads the position rows plus each category's effective roll-up (explicit,
position sum, effective steering weight, and a `conflict` flag surfacing an
explicit/position mismatch — plus per-row `stale` and per-category `has_stale`
flags marking rows whose security no longer sits under the stored category),
and `portfolixir.targets.delete_position` removes one position target.
Category-only calls are unchanged.

Since ADR-0027 the plan tools (`portfolixir.plans.list`,
`portfolixir.plans.duplicate`, `portfolixir.plans.activate`,
`portfolixir.plans.rename`, `portfolixir.plans.delete`) manage named plan
**versions**: duplicate the active plan into a draft, edit the draft through the
target tools (the drafts are addressed by the plan endpoints; view-addressed
target writes keep editing the active plan), then activate it. The snapshot
tools (`portfolixir.snapshots.list`, `portfolixir.snapshots.create`,
`portfolixir.snapshots.delete`, `portfolixir.snapshots.comparison`) freeze a
depot state as a marker and read the counterfactual comparison; every financial
value in the comparison is a Decimal string and the response labels its basis
(gross, price-return only).
