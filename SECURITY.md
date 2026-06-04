# Security Policy

Portfolixir handles sensitive financial data. Treat it as a private finance system by default.

## Security rules

- Do not store real financial fixtures in the repository.
- Do not store secrets in source code.
- Do not write `.env` from the web UI.
- Do not make external LLM calls from the application.
- Do not call real market-data providers in tests.
- Do not implement trading, broker order placement, wallet signing or bank payment flows.
- Do not use `String.to_atom/1` on external input.

## Sensitive data examples

Never commit:

- real Portfolio Performance files
- broker statements
- bank transactions
- wallet addresses if they identify the user
- API keys
- account numbers
- private notes about holdings

## Reporting issues

Please do not open public issues for security vulnerabilities. Report them
privately by email to security@ahu.services.
