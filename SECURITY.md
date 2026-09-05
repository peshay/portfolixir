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

## Perimeter

Since the E21 hardening batch (ADR-0045, 2026-09): production binds loopback
unless `PHX_BIND_ALL` is set; requests under a `Host` outside `PHX_HOST`,
`localhost`, `127.0.0.1` and `PORTFOLIXIR_ALLOWED_HOSTS` are refused; the web
UI is locked by `PORTFOLIXIR_UI_PASSWORD` when set; the bearer tokens must be
at least 32 bytes and are throttled per source after repeated failures; every
server-side fetch of a caller- or provider-supplied URL passes a
deny-by-default policy (https only, public addresses only, provider hosts
only); and the documented deployment is a production release with no secret
defaults. What the instance still expects of the operator: a reverse proxy
that terminates TLS and forwards `X-Forwarded-Proto`, and backups.

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
