# Foundation API Decisions

## Scope

This foundation slice adds domain behavior for account relationships, transaction recording, derived cash balances and derived security positions. It does not add public API endpoints.

## Decision

Public API endpoints are deferred for this slice.

The domain model is now more useful, but the API boundary should wait until the read models and security assumptions are stable enough to expose intentionally.

## Reasons for deferral

- The authentication and authorization model is not final.
- Transaction write APIs for financial data need explicit security review.
- Read models should stabilize after derived balances and positions have been exercised in the UI/domain layer.
- API response conventions still need to be defined before exposing portfolio data.

## Future read API candidates

- `GET /api/v1/portfolios`
- `GET /api/v1/portfolios/:id/accounts`
- `GET /api/v1/portfolios/:id/transactions`
- `GET /api/v1/portfolios/:id/positions`
- `GET /api/v1/portfolios/:id/cash_balances`

## Write boundary

No write API for financial data should be added until a security policy exists.

Portfolixir must not add AI or MCP write tools for financial data in the MVP.
