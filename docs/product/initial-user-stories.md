# Initial User Stories

These stories are ordered for a small-model coding agent. Do not skip ahead.

## PFX-000 — Bootstrap Phoenix app

**As a maintainer**, I want a clean Phoenix app skeleton so that Portfolixir has a testable foundation.

### Acceptance criteria

- Phoenix app is created with OTP app `:portfolixir`.
- Root module is `Portfolixir`.
- Web module is `PortfolixirWeb`.
- PostgreSQL/Ecto is configured.
- `mix test` runs successfully.
- No product feature is implemented yet.

### Tests

- Default Phoenix tests pass.
- Add one simple smoke test if needed.

---

## PFX-001 — Health endpoint

**As an operator**, I want a health endpoint so that Docker and future orchestration can verify the app is running.

### Acceptance criteria

- `GET /health` returns HTTP 200.
- Response JSON is exactly or semantically equivalent to:

```json
{"status":"ok"}
```

- Endpoint does not require authentication in dev/test.
- Controller test exists.

### Tests first

- Add `PortfolixirWeb.HealthControllerTest`.
- Test status code and JSON body.

---

## PFX-002 — Currency catalogue

**As an investor**, I want currencies to be represented explicitly so that portfolios, securities and transactions can use correct currencies.

### Acceptance criteria

- A currency schema exists with:
  - `code`
  - `name`
  - `minor_units`
- Codes are uppercase strings such as `EUR`, `USD`, `CHF`, `GBP`, `SEK`, `NOK`, `DKK`, `JPY`.
- Duplicate currency codes are rejected.
- Currency code validation exists.
- Seed or helper can create the MVP currencies in dev/test.

### Tests first

- Creating `EUR` succeeds.
- Creating duplicate `EUR` fails.
- Lowercase `eur` is normalized or rejected; choose one and document it.
- Invalid code length fails.

---

## PFX-003 — Portfolio with base currency

**As an investor**, I want to create a portfolio with a base currency so that valuations can be reported consistently.

### Acceptance criteria

- Portfolio schema exists with:
  - `name`
  - `description`
  - `base_currency_code`
- Portfolio requires a valid existing currency.
- Portfolio names are required.
- Basic context functions exist:
  - `list_portfolios/0`
  - `get_portfolio!/1`
  - `create_portfolio/1`
  - `update_portfolio/2`
  - `delete_portfolio/1`

### Tests first

- Create portfolio with base currency `EUR`.
- Creating without name fails.
- Creating with unknown currency fails.

---

## PFX-004 — Category taxonomies and category descriptions

**As an investor**, I want to create custom categories with descriptions so that I can document how my depot is structured.

### Acceptance criteria

- Taxonomy schema exists with:
  - `name`
  - `description`
- Category schema exists with:
  - `taxonomy_id`
  - optional `parent_id`
  - `name`
  - `description`
  - optional `color`
  - optional `sort_order`
- Category descriptions support normal text and are persisted.
- Categories can be nested one level or more through `parent_id`.
- A category belongs to exactly one taxonomy.
- Context functions exist:
  - `create_taxonomy/1`
  - `list_taxonomies/0`
  - `create_category/1`
  - `list_categories/1`
  - `update_category/2`
  - `delete_category/1`

### Tests first

- Create taxonomy `Custom Depot Categories`.
- Create category `Core ETF` with a description.
- Read category and assert description is persisted.
- Create child category under `Core ETF`.
- Creating category without taxonomy fails.
- Creating category without name fails.

---

## PFX-005 — Category management UI

**As an investor**, I want a simple UI for category management so that I can maintain my depot categories in the browser.

### Acceptance criteria

- A LiveView route exists for category/taxonomy management.
- User can list taxonomies and categories.
- User can create a category with description.
- User can edit a category description.
- User can delete a category if it has no assignments.
- UI tests cover create and edit flow.

### Tests first

- LiveView test creates a category with description.
- LiveView test edits the description.

---

## PFX-006 — Securities with symbol and currency

**As an investor**, I want to create securities with symbol and currency so that I can track holdings.

### Acceptance criteria

- Security schema exists with:
  - `name`
  - `symbol`
  - optional `exchange_code`
  - optional `provider_symbol`
  - optional `isin`
  - `currency_code`
  - optional `notes`
- Security requires name, symbol and valid currency.
- Duplicate provider symbol + exchange combination is rejected when present.
- Context functions exist:
  - `create_security/1`
  - `list_securities/0`
  - `get_security!/1`
  - `update_security/2`
  - `delete_security/1`

### Tests first

- Create Apple security with `AAPL`, currency `USD`.
- Create Apple Frankfurt security with `AAPL.F`, currency `EUR`.
- Creating without currency fails.
- Creating with unknown currency fails.

---

## PFX-006A — Security management UI

**As an investor**, I want to manage securities in the browser so that I can add and inspect stocks/assets without using the console.

### Acceptance criteria

- A LiveView route exists for securities.
- User can list securities.
- User can create a security with:
  - `name`
  - `symbol`
  - `currency_code`
  - optional `isin`
  - optional `wkn`
  - optional `exchange_code`
  - optional `provider_symbol`
  - optional `notes`
- Validation errors are shown.
- Existing securities are shown in deterministic order.
- UI tests cover create and validation flow.

---

## PFX-007 — Assign categories to securities

**As an investor**, I want to assign my custom categories to securities so that my depot structure can be analyzed.

### Acceptance criteria

- Category assignment schema exists.
- MVP supports assigning categories to securities.
- Assignment is unique per security/category.
- Optional weight field may exist but defaults to `1.0` or nil; choose and document.
- Context functions exist:
  - `assign_category_to_security/2`
  - `list_security_categories/1`
  - `remove_category_assignment/2`

### Tests first

- Assign `Core ETF` to a test ETF.
- Duplicate assignment is rejected or idempotent; choose and document.
- Listing categories for security returns assigned category with description.

---

## PFX-008 — Symbol search provider behaviour

**As an investor**, I want to enter a base symbol and see possible exchange-specific symbols so that I can select the right listing.

### Acceptance criteria

- `Portfolixir.MarketData.Provider` behaviour exists.
- Behaviour supports `search_symbols/1`.
- Fake provider exists for tests.
- Searching `AAPL` returns candidates:
  - `AAPL` / NASDAQ / USD
  - `AAPL.F` / Frankfurt / EUR
  - `AAPL.SG` / Stuttgart / EUR
- No real HTTP request is made in tests.
- User input does not create atoms.

### Tests first

- Fake provider returns three candidates for `AAPL`.
- Search is case-insensitive or normalized; choose and document.
- Unknown symbol returns empty list or provider error; choose and document.

---

## PFX-009 — Store symbol candidates

**As an investor**, I want symbol candidates to be stored so that I can review and select a listing later.

### Acceptance criteria

- `symbol_candidates` schema exists.
- Candidate stores:
  - `search_symbol`
  - `provider`
  - `provider_symbol`
  - `name`
  - `exchange_code`
  - `currency_code`
  - `raw` JSON map
- Candidate storage is idempotent for provider + provider_symbol + search_symbol.

### Tests first

- Store fake AAPL candidates.
- Running the same search twice does not duplicate rows.

---

## PFX-010 — Latest quote provider behaviour

**As an investor**, I want to fetch a simple latest quote by symbol so that portfolio value can be calculated.

### Acceptance criteria

- Market-data provider behaviour supports `latest_quote/1`.
- Fake provider returns price, currency and timestamp for `AAPL`.
- Quote data uses Decimal for price.
- No real HTTP request is made in tests.

### Tests first

- Fake provider returns `AAPL` quote price `100.00`, currency `USD`.
- Invalid symbol returns explicit error or not-found result; choose and document.

---

## PFX-011 — Store latest quotes

**As an investor**, I want fetched quotes to be stored so that valuations can use them.

### Acceptance criteria

- `price_quotes` schema exists.
- Quote stores:
  - security_id
  - provider
  - provider_symbol
  - quoted_at
  - price
  - currency_code
  - raw JSON
- Latest quote lookup for a security returns most recent quote.

### Tests first

- Store quote for AAPL.
- Store newer quote for AAPL.
- Latest quote returns newer quote.

---

## Roadmap placeholders (post PFX-011)

### PFX-012 — Yahoo Finance quote provider adapter

**As an investor**, I want to use Yahoo Finance as a first market-data provider so that I can fetch simple current and historical quotes.

### Acceptance criteria

- Yahoo Finance is implemented behind the existing MarketData provider behaviour.
- Tests use a fake HTTP adapter or fixtures.
- No real HTTP calls in tests.
- Provider instability and terms-of-service caveat are documented.
- Provider can be disabled/configured.

---

### PFX-013 — Manual quote sync for one security

**As an investor**, I want a button to sync the latest quote for one security so that I can refresh a single asset on demand.

### Acceptance criteria

- Security detail or list has a sync action.
- Sync uses provider behaviour.
- Latest quote is stored.
- Errors are displayed without crashing the UI.
- Tests use fake provider only.

---

### PFX-014 — Historical quote storage

**As an investor**, I want historical quotes stored so that charts and performance calculations can use price history.

### Acceptance criteria

- Historical quote schema exists.
- Stores security_id, provider, quoted_at/date, price, currency_code, raw payload.
- Duplicate quote for same security/provider/date is idempotent.
- Uses Decimal for prices.

---

### PFX-015 — Historical quote backfill for one security

**As an investor**, I want to backfill historical quotes for one security so that charts can be populated.

### Acceptance criteria

- Backfill action exists at context/service level.
- Uses provider behaviour.
- Stores historical quotes idempotently.
- No real HTTP calls in tests.

---

### PFX-016 — Watchlists

**As an investor**, I want watchlists so that I can group assets I track without necessarily owning them.

### Acceptance criteria

- Watchlist schema exists.
- Securities can be added to and removed from watchlists.
- Duplicate watchlist entries are rejected or idempotent.
- Context tests exist.

---

### PFX-017 — Asset logo metadata

**As an investor**, I want assets to have optional logos so that the UI is easier to scan.

### Acceptance criteria

- Security can store optional logo metadata.
- Logo source, URL/path and attribution/license fields are modeled.
- No external logo fetching is implemented yet.
- Legal/licensing caveat is documented.

---

### PFX-018 — Themeable app shell

**As a user**, I want a themeable app shell so that Portfolixir has a polished UI and supports different visual themes.

### Acceptance criteria

- Shared app layout/navigation exists.
- User can switch between at least light and dark theme.
- Theme choice is persisted in local storage or a simple setting.
- Existing `/taxonomies` and `/securities` pages use the shared shell.
- UI remains simple and testable.

---

### PFX-019 — Minimal portfolio dashboard

**As an investor**, I want a minimal dashboard so that I can see my portfolio overview.

### Acceptance criteria

- Dashboard LiveView exists.
- Shows portfolio name/base currency.
- Shows securities/positions once position calculation exists.
- Shows empty states before transactions exist.
- Does not fake valuation data.

---

## PFX-012 — Record buy transactions

**As an investor**, I want to record buy transactions so that my purchase history can drive positions.

### Acceptance criteria

- Transaction schema exists with:
  - portfolio_id
  - security_id
  - type = `buy`
  - trade_date
  - optional settlement_date
  - quantity
  - gross_amount
  - fees_amount
  - taxes_amount
  - currency_code
  - optional fx_rate_to_portfolio
  - notes
- Quantity and amounts use Decimal.
- Buy transaction requires positive quantity.
- Buy transaction requires valid portfolio, security and currency.

### Tests first

- Record buy: 10 AAPL for 1000.00 USD.
- Buy with zero quantity fails.
- Buy with negative amount fails.
- Buy with unknown currency fails.

---

## PFX-013 — Position calculation from buy history

**As an investor**, I want my position quantity to be calculated from buy history so that holdings are derived from transactions.

### Acceptance criteria

- Position calculation returns quantity per security for a portfolio.
- MVP only needs buy transactions.
- Position for 10 AAPL buy returns 10 AAPL.
- Two buys aggregate correctly.

### Tests first

- One buy of 10 AAPL -> position quantity 10.
- Two buys of 10 and 5 -> position quantity 15.
- Position calculation for empty portfolio returns empty list.

---

## PFX-014 — Portfolio valuation from latest quotes

**As an investor**, I want portfolio value to be calculated from positions and latest quotes so that I know the current depot value.

### Acceptance criteria

- Valuation service calculates market value per position.
- MVP supports same-currency valuation first.
- Example: 10 AAPL * 100.00 USD = 1000.00 USD.
- If portfolio base currency differs and no FX rate exists, return explicit missing FX result.

### Tests first

- 10 AAPL at 100.00 USD in USD portfolio -> 1000.00 USD.
- EUR portfolio with USD security and no FX -> missing FX error.

---

## PFX-015 — FX rates for portfolio base currency

**As an investor**, I want FX rates so that securities in foreign currencies can be valued in my portfolio base currency.

### Acceptance criteria

- FX rate schema exists.
- Store base currency, quote currency, rate and timestamp.
- Valuation converts security currency into portfolio base currency.
- Example: 1000.00 USD with USD/EUR rate 0.90 -> 900.00 EUR.

### Tests first

- USD security in EUR portfolio with FX rate converts correctly.
- Latest FX rate is used.
- Missing FX rate returns explicit error.

---

## PFX-016 — Minimal portfolio dashboard

**As an investor**, I want a minimal dashboard so that I can see categories, positions and depot value.

### Acceptance criteria

- Dashboard LiveView exists.
- Shows portfolio name/base currency.
- Shows position list with quantity and latest value.
- Shows total portfolio value.
- Shows assigned categories for securities.

### Tests first

- LiveView renders a portfolio with one AAPL position.
- LiveView shows total value.
- LiveView shows category description or category name.
