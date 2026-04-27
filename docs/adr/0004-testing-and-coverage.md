# ADR 0004: Testing and Coverage

## Status

Accepted for MVP.

## Decision

Portfolixir is developed with TDD.

The long-term goal is 100% meaningful coverage for:

- domain logic
- market-data provider boundaries
- importers
- portfolio calculations
- valuation calculations
- security-sensitive code paths

Generated Phoenix boilerplate may be excluded when documented.

## Required test categories

- Unit tests for pure functions
- Context tests for database-backed domain operations
- Controller/API tests for endpoints
- LiveView tests for UI interactions
- Property-based tests for calculation invariants when useful
- Provider tests with mocks/fakes, never live network calls

## Quality gate

```bash
mix format --check-formatted
mix test
mix coveralls
mix credo --strict
mix dialyzer
mix sobelow
mix deps.audit
```

Not every tool must be configured in Story 000. The gate becomes stricter as tooling is added.
