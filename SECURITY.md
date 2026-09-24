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
UI is locked by `PORTFOLIXIR_UI_PASSWORD` when set (its sessions are described
below); `SECRET_KEY_BASE` must be at least 64 bytes and neither a placeholder
nor a value committed in this repository, and a UI password shorter than 12
characters on an instance bound beyond loopback is named in a startup warning;
both bearer tokens, the API's and the MCP companion's, must be at least 32
bytes and not a placeholder, and, like the UI password, are throttled per
source after repeated failures, with the escalation kept well past the longest
lock; failed UI logins also meet a rolling ceiling across all sources, which
asks everyone to wait, the operator included, while existing sessions keep
working; every server-side fetch of a caller- or provider-supplied URL passes a
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
reverse proxy that terminates TLS, passes `Host` through, sets
`X-Forwarded-Proto` itself, appends the connecting address to `X-Forwarded-For`
or overwrites it, never passes a value the client sent through, and injects
nothing into the pages; the proxy's exact address named in
`PORTFOLIXIR_TRUSTED_PROXIES`, not a block that also covers other hosts
(without it the throttle counts the proxy as the one source, and a guesser
behind it locks everyone behind it out, and `X-Forwarded-Proto` is believed
from loopback only); and backups.

Sessions: a UI login lasts `PORTFOLIXIR_SESSION_DAYS` days (default 30),
renewed while the instance is used, enforced on the server rather than trusted
to the cookie's expiry, and bound to the password it was issued under. What
ends one is narrower than "log out" suggests: a logout clears the login in that
browser only and closes its live pages, while a copy of the session cookie
taken earlier stays valid on the same terms as the original.
`PORTFOLIXIR_SESSION_DAYS=0` turns the server-side expiry off rather than
tightening it: the browser forgets the login when it closes, but a copy never
expires. Two levers end every session: changing `PORTFOLIXIR_UI_PASSWORD` ends
every session issued under the old one, and rotating `SECRET_KEY_BASE` ends
every session everywhere. Either is the one to reach for when a device or a
cookie may be in someone else's hands (ADR-0045).

The development stack, `docker-compose.dev.yml`, is not a deployment. It runs
on public development secrets: the database password `postgres` and the
`SECRET_KEY_BASE` committed in `config/dev.exs`, with debug pages and origin
checks off. Anyone who reaches its ports can read and change its data, so both
its ports, the application's and the database's, are published on loopback
only (E25), and it holds synthetic data, never an operator's real records. An
instance still running the development stack as its deployment, as the
documentation described it before the production release (#760), moves off it
by a backup and a restore (`docs/home-deployment.md`, "Development stack").

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
