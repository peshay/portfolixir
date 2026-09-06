# Sprint 10 (E21) — closing-act walkthrough (2026-09-05)

Design-critic and UAT persona pass of the agentic review closing act
(ADR-0026 step 3), run under section G's conditions of
`docs/development/pr-review-checklist.md`, on the synthetic demo dataset
(`priv/demo/`, no real data), against a development server started with
`PORTFOLIXIR_UI_PASSWORD` set. The shots in this directory are the retakes
after the fix round; the findings below say what the first takes showed.

## Conditions the walkthrough ran under (stated so the claim is checkable)

- **DE locale**: every touched screen was rendered in DE (`?locale=de`, the
  session then carries it); the EN desktop shots are the comparison, not
  the pass.
- **390 px**: one full pass of the login page (empty, wrong password, locked
  out), the logout page, the dashboard with the sidebar opened, and the
  imports result stage at 390 × 844, taken at true CSS pixels through the
  DevTools protocol (`Emulation.setDeviceMetricsOverride`, not a window
  resize, which headless Chrome floors at 500 px).
- **Seed data that fires the alarm surfaces**: the touched screens of this
  batch are the session pages (no data), the imports result stage and the
  destructive controls. The imports alarm surface — a file whose every row
  is already booked (#769) — was fired by importing
  `portfolio_performance_demo.json` a second time through the page's own
  file input. The three surfaces section G names (an unclassified security,
  a stale quote, a plan off 100 %) are not on this batch's screens; the
  dashboard shots show the demo plan's drift because the seed carries it,
  not because this batch changed that screen.
- **Live perimeter checks** ran with `curl` against the same server and are
  listed under "What was checked live".

## What was looked at

| Shot | Screen | What it shows |
| --- | --- | --- |
| `login-de-390.png` | `/login`, DE, 390 px | the one-field form, the h2-scale heading, the locale switcher in the card |
| `login-error-de-390.png` | same, after a wrong password | the field-level error under the field, `aria-invalid` on the field |
| `login-throttled-de-390.png` | same, after ten wrong attempts | the lockout as a form-level alert above the form, with the seconds left; the field is not marked invalid |
| `logout-de-390.png` | `/logout`, DE, 390 px | the one-button confirmation page; only its POST changes state |
| `sidebar-de-390-logged-in.png` | `/`, DE, 390 px, sidebar opened | "Abmelden" at the sidebar foot, the page title no longer truncated by a top-bar link |
| `dashboard-de-390-logged-in.png` | `/`, DE, 390 px | the dashboard behind the login |
| `imports-result-de-390.png` | `/imports` result stage, DE, 390 px | twelve skipped rows, each with a German reason (#769) |
| `login-en-desktop.png` | `/login`, EN, 1280 px | the card centred at 360 px |
| `dashboard-en-desktop-logged-in.png` | `/`, EN, 1280 px | the sidebar with "Log out" at its foot |

## What was checked live

Against the development server with a UI password set, from the host:

- `GET /health` with `Host: evil.example` → 421, before the router.
- `GET /portfolio` without a session → 302 to `/login?to=%2Fportfolio`.
- `POST /login` with the password → 302 to `/`, `Set-Cookie` carries
  `HttpOnly; SameSite=Lax` (no `Secure`: plain HTTP on loopback), the
  response carries `x-content-type-options: nosniff`.
- `GET /api/v1/portfolios` without a token → 401; with only the UI session
  cookie → 401 (the API never accepts the UI session).
- `GET /logout` → 200, the page; `POST /logout` → 302 to `/login` with the
  cookie expired.
- Ten wrong passwords → 401 each; the eleventh → 429 with `Retry-After`,
  the lock doubling per further failure after expiry (2, 4, 8, 16, 32 s).
- `GET /app.css` → `x-content-type-options: nosniff` on the static file.

## Findings and what was done

The four review roles (correctness hunter, edge-case hunter, design critic,
risk-tier verification pass) reported together thirty-odd confirmed items;
every one that was in the batch's scope was fixed on the branch in the
review-round commits. The ones a reviewer should know about:

1. **Fixed (blocking, correctness hunter):** inside Compose the MCP companion
   reaches the app as `http://app:4000`, a Host the new guard refused with
   421. Both Compose files now add `app` to the allow-list, and the socket
   handshake's `check_origin` is built from the same list instead of
   `PHX_HOST` alone. A CI test pins the Compose contract.
2. **Fixed (blocking, design critic):** `data-confirm` on a `phx-click`
   button did nothing — the page loads no `phoenix_html.js`, so the
   attribute was decoration on every site but the one with a hand-written
   hook. The root layout now carries one capture-phase click listener that
   asks before any `[data-confirm]` and cancels the click on "cancel"; the
   hook's own prompt is gone so nothing asks twice. The invariant test pins
   the mechanism, not only the attribute.
3. **Fixed (should-fix, both hunters):** the release image's static manifest
   path was absolute, which Phoenix joins onto the app directory; and
   `POSTGRES_PASSWORD` from `openssl rand -base64 48` breaks the database
   URL it is spliced into more often than not. The manifest path is
   relative; the docs and `.env.example` say `openssl rand -hex 32` for that
   one secret.
4. **Fixed (should-fix, three reviewers):** behind the documented reverse
   proxy every client shares the proxy's address, so the throttle would lock
   the operator out together with a guesser. `PORTFOLIXIR_TRUSTED_PROXIES`
   names the proxy (address or CIDR block); only then is its
   `X-Forwarded-For` believed, right to left, skipping trusted hops.
   Unset, the header is never a source. Documented with the Docker bridge
   note; `SECURITY.md` names the limit for an instance that leaves it unset.
5. **Fixed (should-fix, risk-tier pass and both hunters):** stored logos
   were static files ahead of the router, readable without the UI password
   and named by security id. They are now served by a route in the browser
   pipeline, behind the login, with the same nosniff header.
6. **Fixed (should-fix):** `safe_return_path/1` let through `/\evil`,
   `/%09…` and control characters that Phoenix's redirect then refused with
   a 500 after a *correct* password; a login body that is not the form's
   shape crashed instead of counting as a wrong password; logout dropped
   the cookie but left open LiveViews connected. All three are pinned in
   `ui_auth_test.exs`; the login now stores a socket id and the logout
   broadcasts the disconnect.
7. **Fixed (should-fix, correctness hunter):** `PATCH /securities/:id` with
   `attributes: null` wiped the logo bookkeeping the #766 protection keeps
   for a map. A nil is now an empty map for that purpose.
8. **Fixed (design critic, DE, 390 px):** the top-bar logout link truncated
   the page title to two characters at 390 px; it is now the last entry of
   the sidebar, with an icon. Two German import error strings had been
   fuzzy-merged from the security string and named the wrong entity; the
   duplicate-row reasons were English inside the German page; "record(s)"
   and "%{seconds} seconds" were manual plurals; the lockout was rendered as
   a field error with `aria-invalid`; the login card restyled the input and
   the heading off the tokens; the session pages had no locale switch;
   touch targets for the ghost button and the input sat under 44 px on a
   coarse pointer. All fixed; the retaken shots are the ones here.
9. **Fixed (small):** the throttle's sweep had keyed on the lock expiry and
   handed a source below the threshold its attempts back every ten minutes;
   the failure count is now bumped atomically; `settings` was missing from
   the closed list of unarmed scope tables; a version-1 JSON export whose
   `transactions` is not a list is a malformed payload rather than an
   unsupported version; a UTF-8 BOM ahead of `Datum` no longer reads as a
   missing column; a quote `limit` keeps the newest rows of the window like
   the other two lists; `PHX_HOST=example.com:8443` and `PHX_HOST=::1` now
   match the Host the request carries; the URL policy judges NAT64, 6to4
   and IPv4-compatible IPv6 forms by the embedded address and refuses
   `192.0.0.0/24` and `198.18.0.0/15`.
10. **Recorded, not changed:** the URL policy resolves a name for the check
    and the client resolves it again to connect (DNS rebinding with a short
    TTL can pass; the byte cap, the deadline and the redirect re-check bound
    it) — in the policy's moduledoc and `SECURITY.md`. The WebSocket
    handshake is dispatched ahead of the Host guard and rests on
    `check_origin` — in the guard's moduledoc and `SECURITY.md`. Provider
    clients on fixed hosts keep Req's redirect following; only the logo
    store, which takes arbitrary URLs, re-checks every hop. A truncated
    list read carries no marker in the API envelope (observation for the
    next requirements edition, not a defect of this batch).
11. **Not exercised live:** the browser `confirm()` dialog cannot be
    captured through a screenshot; the design critic's probe on a connected
    LiveView (stubbed `window.confirm`, injected `phx-click` button) is what
    showed the first take inert, and the same probe passes with the
    listener. The release image was not built in this session (no Docker
    daemon); the manifest-path finding was verified with `Path.join/2`
    against Phoenix's resolution, and `Portfolixir.Release.migrate/0` and
    `rebuild_derived/0` run in the test suite.
