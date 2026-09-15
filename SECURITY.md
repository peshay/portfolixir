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
UI is locked by `PORTFOLIXIR_UI_PASSWORD` when set, for `PORTFOLIXIR_SESSION_DAYS`
days (default 30, renewed while the instance is used, and enforced on the server
rather than trusted to the cookie's expiry) — a logout ends that session and
rotating `SECRET_KEY_BASE` ends every session everywhere, which is the lever to
reach for when a device is lost; the bearer tokens must be
at least 32 bytes and are throttled per source after repeated failures; every
server-side fetch of a caller- or provider-supplied URL passes a
deny-by-default policy (https only, public addresses only, provider hosts
only); and the documented deployment is a production release with no secret
defaults. Since Sprint 11 (#382, #772): every browser page carries a
`Content-Security-Policy` — scripts only from the instance and from the root
layout's inline boot scripts through a per-request nonce, no inline event
handlers, no `eval`, no foreign origins — and the HTTP server is Bandit, which
took cowlib and its unfixed advisories out of the tree. The HTTPS posture is
the reverse-proxy contract in `docs/home-deployment.md`: TLS is terminated by
the proxy, the application never redirects on its own, and `PHX_FORCE_SSL` is
the opt-in for the redirect and HSTS once the proxy forwards
`X-Forwarded-Proto`. What the instance still expects of the operator: a
reverse proxy that terminates TLS and forwards `Host`, `X-Forwarded-Proto` and
`X-Forwarded-For` unchanged and injects nothing into the pages, the proxy's
address named in `PORTFOLIXIR_TRUSTED_PROXIES` (without it the throttle counts
the proxy as the one source, and a guesser behind it locks everyone behind it
out), and backups.

Known limits, recorded rather than hidden: the outbound URL policy resolves a
name once for the check and the client resolves it again to connect, so a name
whose answer changes in between can pass (the byte cap, the deadline and the
redirect re-check bound what such a fetch can do); and the WebSocket handshake
is dispatched ahead of the Host guard and rests on `check_origin`, built from
the same allow-list. The policy's `style-src` admits inline `style`
attributes (the data-driven colours and tree indents the pages render), so it
guards against script injection, not against CSS injection.

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
