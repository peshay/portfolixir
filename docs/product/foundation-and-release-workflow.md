# Portfolixir Foundation and Release Workflow

## 1. Why this document exists

Portfolixir is moving from tiny starter stories into foundation-building work. The early story PRs
were useful for establishing the app shell, product structure and small domain surfaces, but the
next phase needs larger coherent slices so the core portfolio model can fit together cleanly.

The project should still use reviewable pull requests. We do not want one giant unreviewable "clone
Portfolio Performance" PR that mixes accounts, transactions, reports, API design, imports and market
data. We also do not want to over-fragment the foundation into UI or domain micro-stories that
cannot prove meaningful behavior on their own.

The preferred direction is coherent foundation slices: each PR should have one clear architectural
purpose, enough tests to prove the domain behavior, and a scope that can be reviewed in one sitting.

## 2. Foundation sprint plan

Recommended next sequence:

1. `PFX-FND-001: Account relationship foundation`
   - Link securities accounts to reference deposit accounts.
   - Keep balances transaction-derived.
   - No UI unless required.

2. `PFX-FND-002: Transaction core`
   - Add the basic transaction model.
   - Cover deposit, withdrawal, buy, sell and dividend.
   - Use `Decimal` for quantities and money.
   - No reports yet.

3. `PFX-FND-003: Derived balances and positions`
   - Calculate cash balances from transactions.
   - Calculate security positions from transactions.
   - Use deterministic tests only.

4. `PFX-FND-004: Minimal read API policy and first endpoints`
   - Define API response conventions first.
   - Add read endpoints only for stable resources.
   - No write API until security and authentication are decided.

5. `PFX-FND-005: Dashboard MVP`
   - Build a real dashboard only after balances and positions exist.
   - Use the external prototype and Portfolio Performance as inspiration only.

6. `PFX-FND-006: Import/market-data spikes`
   - Create a Portfolio Performance XML import spike with synthetic fixtures.
   - Add a market-data provider behaviour before any live provider.

## 3. API policy

Every new feature must consider whether an API surface is relevant. For each feature, the
implementation PR should choose one of these outcomes:

- Add an API endpoint now.
- Explicitly defer the API because the domain is unstable.
- Document why an API is not appropriate for the feature.

API endpoints should be added only when:

- The domain resource is stable enough to expose.
- The read model is clear.
- The JSON shape can be tested.
- Authentication and security assumptions are documented.

No write API for financial data should be added until the security model is explicit. Portfolixir
must also not expose AI or MCP write tools for financial data in the MVP.

## 4. PR size policy

Avoid giant PRs. Prefer coherent foundation slices.

A PR may touch multiple files or layers when those changes implement one coherent foundation slice.
For example, a domain migration, context functions and tests may belong together when they define
one account or transaction capability.

PRs should be reviewable in one sitting. They must not mix unrelated work such as UI redesign,
ledger schema, API endpoints and market-data provider changes in the same pull request.

## 5. Testing policy

TDD is preferred for domain logic. For foundation work, tests may be written around domain
invariants rather than UI user stories when the main value is the correctness of the model.

All financial quantities, money, prices and FX rates must use `Decimal`. Persisted financial values
must not use floats.

Tests must not make live network calls. Tests and fixtures must not contain real financial data,
real account numbers, wallet addresses, broker statements, customer names or private portfolio
files. Use synthetic fixtures only.

## 6. Git history and changelog policy

Use Conventional Commits for project history. Each PR should be cleaned before merge into one to
three meaningful commits.

Rebase merge is acceptable when the commits are meaningful. Squash merge is acceptable for
one-change PRs. Avoid noisy WIP commits on `main`.

Supported commit types:

- `feat`
- `fix`
- `docs`
- `test`
- `refactor`
- `chore`
- `ci`

The future changelog generator candidate is `git-cliff`. Changelog generation should be added in a
separate PR, without mixing it into domain work. Release notes should be generated from the
Conventional Commit history.

## 7. Recommended next implementation PR

Recommended next PR:

`PFX-FND-001: Link securities accounts to reference deposit accounts`

This completes the account foundation needed before transactions can affect the correct cash
account. It is still small and reviewable, but it connects the account model to the transaction work
that follows.
