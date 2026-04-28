# Ledger Workspace API Decision

This PR adds web UI for the ledger workspace.

No public API endpoints are added in this PR.

## Reason

- The UI is validating the domain workflow first.
- API conventions and authentication should be defined in a dedicated API slice.
- Read endpoints are the next logical slice once the UI flow is accepted.

## Proposed Next API Endpoints

- `GET /api/v1/portfolios`
- `GET /api/v1/portfolios/:id/accounts`
- `GET /api/v1/portfolios/:id/transactions`
- `GET /api/v1/portfolios/:id/cash_balances`
- `GET /api/v1/portfolios/:id/positions`

No write API should be added until a security policy exists.
