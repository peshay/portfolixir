---
layout: docs
title: "ADR-0037: Phoenix 1.8 and LiveView 1.x — taken as a security upgrade, verified in a real browser"
description: Phoenix 1.7.22 carries a HIGH advisory (unlimited channel joins per connection, process-exhaustion DoS) with no fix in the 1.7 line. The upgrade to Phoenix 1.8.9 and phoenix_live_view 1.2.8 is therefore taken as a security upgrade rather than a feature migration - the framework is moved, the application's own patterns are not modernised in the same step. Because the suite never exercises the browser, the LiveView client/server handshake was verified with a real Chromium session rather than assumed.
---

# ADR-0037: Phoenix 1.8 and LiveView 1.x — taken as a security upgrade, verified in a real browser

- **Status:** Accepted (owner decision 2026-08-04 — the upgrade was scoped into
  the Sprint 3 batch on the owner's instruction; decision gate per
  [ADR-0026](0026-epic-batch-workflow.html) as amended by
  [ADR-0036](0036-risk-tier-rides-the-batch.html))
- **Date:** 2026-08-04

## Context

`mix hex.audit` on an advisory-aware Hex reported **phoenix 1.7.22 —
`EEF-CVE-2026-56811` (HIGH)**: Phoenix transports do not limit channel joins
per connection, which allows process-exhaustion denial of service. A second,
MEDIUM advisory (`EEF-CVE-2026-56812`) affects the JavaScript presence client.

**There is no fix in the 1.7 line.** That line ends at 1.7.22; the fix ships
in 1.8.x, and Phoenix 1.8 in turn requires `phoenix_live_view` 1.x. So the
choice was not "upgrade or patch" but "upgrade or carry a HIGH advisory
indefinitely".

Exposure, stated honestly: the attack needs to reach the socket. For a
self-hosted single-user instance behind no public route that is low; for an
instance exposed to a network it is not, and the project cannot assume which
one a user runs.

The dependency update that preceded this one in the same batch closed 11 of
15 advisories found on `main`. This was the remaining HIGH.

## Decision

**Upgrade to `phoenix ~> 1.8.9` and `phoenix_live_view ~> 1.2`, and treat it
strictly as a security upgrade.**

The framework moves; the application's own idioms do not move with it in the
same step. Phoenix 1.8 ships new conventions (scopes, the `Layouts.app`
function-component layout pattern, `daisyUI`-flavoured generators) that are
*offered*, not required. Adopting them here would mix an unavoidable security
change with a discretionary restyling and make the result unreviewable. Any
such adoption is a separate decision with its own gate.

### What the upgrade actually cost

Recorded because the expectation was much worse, and a future reader deserves
the real number rather than the fear:

- **No application code changed.** The codebase already used the modern
  idioms LiveView 1.x requires — no `live_redirect`/`live_patch`,
  no `push_redirect`, no `phx-feedback-for`, no `live_title_tag`, no `~L`
  sigil, no `Phoenix.LiveView.Helpers`, no `form_for`/`inputs_for`, no
  `Routes.*` helpers. `mix compile --warnings-as-errors` was clean on the
  first attempt.
- **One test dependency:** LiveView 1.x parses the test DOM with `lazy_html`
  instead of Floki, so `{:lazy_html, ">= 0.1.0", only: :test}` was added.
  Without it every LiveView test raises; with it the whole suite passes
  unchanged.
- **One lockfile hygiene step:** `castore` became an orphan and was unlocked
  (`mix deps.unlock --unused`), which the CI's unused-dependency gate
  requires.

That is the entire migration. **1714 tests, 6 properties, 0 failures**, with
no test rewritten to accommodate the new versions.

### Why a browser session was part of the acceptance

The suite reaches `ConnTest` and `Phoenix.LiveViewTest`, both of which bypass
the HTTP server and never execute JavaScript. Two things therefore sat
outside every gate:

1. the real server boot (`config/test.exs` only starts the endpoint when
   `PHX_SERVER` is set, which CI never sets), and
2. the LiveView **client**, which this app serves straight from the
   dependency (`plug Plug.Static, at: "/vendor", from: {:phoenix_live_view,
   "priv/static"}`) and wires up with a hand-written `LiveSocket` setup and
   custom hooks in `layout_view.ex`.

A client/server version mismatch or a changed JS global would have broken
every page in the browser while the suite stayed green — exactly the failure
mode a major version bump invites. So the upgrade was accepted only after a
real Chromium session against a booted instance confirmed, on `/`,
`/portfolio`, `/securities` and `/transactions`: `window.liveSocket` present,
`isConnected()` true, the `data-phx-main` root rendered, and **no console or
page errors**. Serving the client from the dependency's own `priv/static` is
what makes this safe by construction — the JS cannot drift from the server
version, because there is no vendored copy to forget.

## Consequences

- `phoenix 1.7.22 → 1.8.9`, `phoenix_live_view 0.20.17 → 1.2.8`,
  `websock_adapter 0.5.9 → 0.6.0`; `lazy_html` added as a test dependency;
  `castore` unlocked.
- **Both phoenix advisories are gone.** What remains in the whole tree is
  cowlib `EEF-CVE-2026-43969` (LOW) and `-43966` (MEDIUM) — no fixed release
  exists upstream, and `ci.yml` already documents them as deliberately
  tolerated. The tree is down from 15 advisories with 5 HIGH on `main` to
  **2, none HIGH**.
- **The advisory-gate follow-up ADR-0036 owes is still not payable, and for a
  different reason than assumed.** ADR-0036 recorded that closing the gap was
  blocked by the phoenix HIGH; with that gone, the blocker is now purely the
  tooling: `mix hex.audit` on Hex 2.5+ sees advisories but offers **no ignore
  mechanism**, so arming it would hard-fail on the two unfixable cowlib
  entries, while `mix deps.audit` has the ignore list but its database does
  not carry these advisories. Until one of the two grows the missing half, an
  advisory-aware step can be *visible* but not *blocking*. That choice is the
  owner's.
- Phoenix 1.8's new conventions are explicitly **not** adopted; the codebase
  keeps its current layout and routing idioms.
- The browser check is currently a manual acceptance step, not a gate. Making
  it one (a smoke test that boots the endpoint and asserts the LiveView
  connects) would close the boot/JS blind spot the reviewer flagged for
  cowboy as well — a candidate follow-up, not done here.

## References

- `EEF-CVE-2026-56811` / `GHSA-6983-jfq8-485w` (HIGH) and
  `EEF-CVE-2026-56812` — the advisories that forced this
- [ADR-0036](0036-risk-tier-rides-the-batch.html) — risk-tier work rides the
  batch; this upgrade is delivered under it, and its advisory-gate follow-up
  is re-stated above
- [ADR-0026](0026-epic-batch-workflow.html) — the decision gate this record
  satisfies
