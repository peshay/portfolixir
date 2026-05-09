# ADR 0002: Initial Domain Model

## Status

Accepted for MVP draft.

## Domain priorities

The first functional milestone supports:

1. User-defined portfolio categories with descriptions.
2. Securities with symbol, exchange and currency metadata.
3. Portfolios with base currency.
4. Buy transactions.
5. Positions derived from transactions.
6. Portfolio value derived from positions and latest quotes.

## Initial entities

```text
currencies
  code            # ISO 4217, e.g. EUR, USD, CHF
  name
  minor_units

portfolios
  id
  name
  base_currency_code
  description

securities
  id
  name
  symbol          # e.g. AAPL
  exchange_code   # optional, e.g. XNAS, XFRA, XSTU, or provider code
  provider_symbol # optional, e.g. AAPL, AAPL.F, AAPL.SG
  isin            # optional
  currency_code
  notes

taxonomies
  id
  name            # e.g. Asset Class, Region, Strategy
  description

categories
  id
  taxonomy_id
  parent_id       # optional, for hierarchy
  name
  description     # rich/free text
  color           # optional theme token or hex
  sort_order

category_assignments
  id
  category_id
  assignable_type # initially Security; later Position/Portfolio/Transaction
  assignable_id
  weight          # optional Decimal, useful for split assignments later

transactions
  id
  portfolio_id
  security_id
  type            # string enum for MVP: buy, sell later
  trade_date
  settlement_date
  quantity
  gross_amount
  fees_amount
  taxes_amount
  currency_code
  fx_rate_to_portfolio
  notes

symbol_candidates
  id
  search_symbol
  provider
  provider_symbol
  name
  exchange_code
  currency_code
  raw

price_quotes
  id
  security_id
  provider
  provider_symbol
  quoted_at
  price
  currency_code
  raw

fx_rates
  id
  base_currency_code
  quote_currency_code
  rate
  quoted_at
  provider
```

## Rules

- Use `Decimal` for financial values.
- Use string enums or explicit Ecto enums for external values.
- Do not create atoms from provider input.
- Persist raw provider responses only in safe JSON fields.
- Calculated positions and valuations may be materialized later, but must be derivable from the
  canonical ledger.
