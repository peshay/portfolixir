# Definition of Done

A story is done when:

- acceptance criteria are covered by tests
- tests fail before implementation for the expected reason
- tests pass after implementation
- no real financial data was added
- no live network calls are used in tests
- financial values use Decimal
- code is formatted
- story scope was not exceeded
- follow-up work is documented

For domain stories, also require:

- validation tests
- happy-path tests
- at least one edge-case test

For market-data stories, also require:

- provider behaviour or fake provider
- no provider API keys
- no HTTP calls in unit tests
