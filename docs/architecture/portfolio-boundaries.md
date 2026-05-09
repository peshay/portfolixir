# Portfolio boundaries and shared market data model (PFX-015C)

Portfolixir follows a Portfolio Performance-inspired model where one `.portfolio` file in Portfolio
Performance represents one self-contained portfolio workspace.

In Portfolixir, each `Portfolio` record is the tenant-like boundary. The portfolio determines where
user-owned domain data lives, while reference and quote data can be reused across portfolios where
that is safe.

## Boundary model

### Global / shared data

- **Scope:** shared across all portfolios.
- **Examples:** currencies (`EUR`, `USD`), securities/instruments,
  exchange definitions, provider symbol mappings, historical quotes, and FX
  rates.
- **Why:** these are catalog/market facts, not user strategy or ownership
  context. Sharing avoids duplication and keeps valuation logic deterministic
  across workspaces when the same instrument appears in multiple portfolios.

### Portfolio-scoped data

- **Scope:** owned inside one portfolio boundary.
- **Examples:** portfolio settings, account ownership, strategy categories and
  allocations, notes, and future transaction streams.
- **Why:** these represent user-owned business data. Isolation prevents leakage
  between independent investment workspaces and keeps account behavior stable for
  a given base currency and organization.

### Derived data

- **Scope:** calculated per portfolio.
- **Examples:** holdings, cash balances, portfolio valuation, allocation,
  gains/losses, alerts, and generated reports.
- **Why:** these derive from portfolio-scoped sources and must be computed within
  the same boundary.

## Why market data should be shared

- Market prices and FX rates are not tied to a user’s portfolio strategy; they are external facts
  about instruments and currencies.
- Reusing shared reference and market records keeps provider usage efficient and reduces
  inconsistent duplicate data.
- Shared storage allows multiple portfolios to be valued with the same market state when needed,
  which is expected for both planning and cross-checking.

## Why accounts, transactions, and reports stay portfolio-scoped

- Deposits, securities accounts, and future transactions should never mix across different user
  workspaces.
- Portfolio reports (valuation, allocation, holdings, cash impact checks, warnings) are only
  meaningful inside their own account universe.
- Even if multiple portfolios are configured later, each should feel like its own file-level
  workspace for edits, fixes, and auditability.

## Current code state (as-is)

- `Portfolio` records already exist and back a separate portfolio concept.
- `deposit_accounts` and `securities_accounts` already have `portfolio_id`, and account
  creation/listing is implemented against this relation.
- `catalog.securities` currently behaves globally today (no per-portfolio scoping).
- The accounts UI currently uses the first portfolio as the active context; there is no explicit
  user-selected current portfolio yet.

## Notes for follow-up implementation

Current story is architecture-only; no behavior changes are made yet.

- PFX-015D Add explicit current portfolio selection and current-portfolio context handling.
- PFX-015E Guard portfolio-scoped queries so all account/ledger reads consistently apply the current
  portfolio.
- PFX-016+ Ensure transactions are strictly portfolio-scoped in all creation and read paths.
- Market data provider stories should assume shared provider symbol lookup, quotes, and FX-rate
  storage.

This model enables future multi-portfolio UX without duplicating shared catalog data and without
leaking state across portfolio boundaries.
