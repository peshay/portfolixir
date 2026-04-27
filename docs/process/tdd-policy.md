# TDD Policy

Portfolixir is built with strict TDD.

## Loop

```text
1. Select one user story.
2. Translate acceptance criteria into tests.
3. Run tests and confirm failure.
4. Implement the smallest code change.
5. Run tests and confirm success.
6. Refactor within scope.
7. Record follow-up work if needed.
```

## Red/green requirement

Every story summary must include:

- test file names
- initial failing test summary
- final passing test summary
- commands run

## Test data

Use synthetic data only.

Good:

```text
AAPL, Apple Inc., synthetic quantity 10, synthetic price 100.00
Test ETF, TEST.DE, synthetic quantity 5
```

Bad:

```text
real broker statements
real account numbers
real personal position sizes
real wallet addresses linked to the user
```

## No live network tests

Market-data tests must use fake providers or Mox.

## Decimal expectations

Financial tests should assert exact Decimal values when possible:

```elixir
assert Decimal.equal?(position.quantity, Decimal.new("10"))
assert Decimal.equal?(valuation.market_value, Decimal.new("1000.00"))
```
