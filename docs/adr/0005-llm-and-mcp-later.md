# ADR 0005: LLM and MCP Are Later Features

## Status

Accepted for MVP.

## Decision

LLM and MCP integration are not part of the initial functional milestone.

## Rationale

The first priority is a correct, testable portfolio data model:

- categories
- currencies
- securities
- buy history
- positions
- quote lookup
- valuation

LLM/MCP integration is only useful once the underlying data is trustworthy.

## Future direction

When added, MCP must be read-only first:

```text
portfolio.get_categories
portfolio.get_positions
portfolio.get_valuation
portfolio.get_symbol_candidates
portfolio.explain_portfolio_delta
```

No write-capable tools without explicit human approval and audit logs.
