---
layout: docs
title: "ADR-0045: optional built-in authentication for the web UI, and the deployment contract that goes with it"
description: The web UI stays unauthenticated by default and becomes authenticated by one environment variable - a single operator password enforced on every browser route and on the LiveView socket mount. Production binds loopback unless told otherwise, validates the request's Host, and the documented deployment is a production configuration rather than the development one. Answers OQ-8; not a user model, not roles, no change to the bearer tokens.
---

# ADR-0045: optional built-in authentication for the web UI, and the deployment contract that goes with it

- **Status:** Accepted (owner sign-off 2026-09-05 on PR #756, decision gate
  per [ADR-0026](0026-epic-batch-workflow.html) step 1)
- **Date:** 2026-09-05 (signed the same day)
- **Answers:** OQ-8 (built-in auth as a deployment assumption, open since the
  2026-06-12 PRD) and D-1/D-2 of the 2026-09-05 security review triage
  (`_bmad-output/planning-artifacts/security-review-triage-2026-09-05.md`).

## Context

NFR-4 says the web UI is *unauthenticated by design: trusted network or
reverse-proxy authentication; optional built-in auth is OQ-8*. The PRD made
OQ-8 a precondition for Phase 3, on the reasoning that live broker
credentials must not sit on a box whose UI anyone on the network can open.

A whole-system security review on 2026-09-03 found that the precondition is
earlier than Phase 3, for three reasons that are about the delivered system
rather than the decision:

1. The production configuration binds every network interface with no
   switch; only the development configuration has the loopback default.
2. The documented home deployment is the development Compose file: debug
   error pages, origin checks off, the repository's public session secret,
   the database published on every interface with its default password, and
   a fallback value for both bearer tokens.
3. No request is checked against its `Host` header. The origin check guards
   the WebSocket only; a server-rendered page is readable by any site the
   operator's browser visits, through DNS rebinding. The trust boundary of
   an unauthenticated home-network service is therefore not the network but
   the operator's browser, which is on the internet.

Every write the product has is reachable from the UI, so the bearer token on
the API protects nothing an attacker on the same network wants. The identity
gate (2026-08-12) settled that self-hosting by others is the deployment
model; what an adopter following the documentation gets today is not a tool
for a trusted network but a tool for no network.

## Decision

### 1. One password, opt-in, enforced on every browser route and the socket

- A single operator password is read from `PORTFOLIXIR_UI_PASSWORD` at
  runtime. **Unset means today's behaviour**, so no existing instance changes
  on upgrade.
- When set, a plug on the browser pipeline requires an authenticated session:
  an unauthenticated request is redirected to a minimal login page (password
  only, no username, no registration, no recovery); a correct password stores
  a flag in the signed session cookie; a logout control clears it.
- The browser `live_session` gains an `on_mount` that refuses to mount a
  socket whose session lacks the flag, so the LiveView transport cannot be
  used to bypass the plug.
- The password is compared in constant time and never logged. Failed
  attempts are throttled per source address with an exponential back-off.
- The `/api/v1` routes are untouched: the bearer tokens remain the agent's
  credential, and the UI password is never accepted there.

### 2. The deployment contract

- **Production binds loopback by default.** `config/runtime.exs` gains the
  `PHX_BIND_ALL` switch `config/dev.exs` already has. Binding beyond
  loopback with no UI password set logs a warning at startup naming this
  ADR.
- **The request's Host is validated** by a plug ahead of the router: the
  configured `PHX_HOST`, `localhost` and `127.0.0.1`, extendable by an
  environment variable for a reverse-proxy host. Anything else is answered
  421.
- **The session cookie** carries `SameSite=Lax`, `HttpOnly` and, behind a
  proxy that sets `x-forwarded-proto`, `Secure`; the signing salts are
  derived from `SECRET_KEY_BASE` rather than the two literals in the
  repository. HSTS with `force_ssl` is available as an opt-in variable for an
  instance that terminates TLS itself.
- **The documented deployment is a production configuration**: a release
  build, every secret required with no fallback, the database port not
  published, the application port published on loopback for the operator's
  reverse proxy, non-root users and digest-pinned images. The current Compose
  file is kept as the development configuration under its own name.

### 3. What this is not

- Not a user model, not roles, not per-portfolio permissions; NFR-6 (one
  operator) is unchanged.
- Not a replacement for reverse-proxy authentication; an operator who has
  one keeps it. The two compose.
- Not a change to how agents authenticate; ADR-0017's actor taxonomy and
  the token surfaces are unchanged.
- Not a claim of production readiness (`AGENTS.md`), and not the Phase 3
  gate: it answers OQ-8, which Phase 3 lists as one of three preconditions.

## Consequences

- NFR-4 reads *unauthenticated by default, authenticated by one variable;
  loopback by default; Host-validated*. README and `docs/index.md` change
  their sentence accordingly.
- An adopter following `docs/home-deployment.md` gets an instance that is
  reachable only from the machine it runs on until they choose otherwise,
  and a one-variable way to open it to a network safely.
- The login page is a new user-visible surface: it follows `DESIGN.md`,
  carries the DE/EN strings through gettext, and is covered by the closing
  act's browser conditions.
- The API/MCP coverage rule does not apply to the password itself (it is a
  browser credential by construction); the reviewer briefing states this.
- One new test family in the invariant suite: the Host guard, the cookie
  attributes, and the socket mount refusing an unauthenticated session.

## The asks this ADR answers ([ADR-0043](0043-a-gate-closing-adr-names-its-asks.html))

| Ask | Answer |
|---|---|
| OQ-8 — should the app carry built-in authentication? | **Answered:** yes, optional, one password, opt-in by variable (§1). |
| D-2 — should the documented deployment be a production configuration? | **Answered:** yes (§2). |
| Should authentication cover the API too? | **Answered, no:** the bearer tokens stay the agent's credential (§3). |
| Multi-user, roles, per-portfolio access? | **Deferred, with reason:** NFR-6 says one operator; the parking lot (#340) holds multi-user as a vision item, and nothing in this review needs it. |
| Should the UI password gate Phase 3 credential storage? | **Deferred to the Phase 3 ADR:** this ADR discharges the precondition; how Phase 3 uses it is that ADR's to say. |
