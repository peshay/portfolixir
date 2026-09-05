# Security Review Triage — 2026-09-05

Source: an architecture-and-code security review of the whole system, run on
2026-09-03 against `6de32ff` (the Sprint 9 head, now `main`). It covered the
Phoenix application (endpoint, router, plugs, every LiveView, the JSON API,
the contexts, the migrations), the MCP companion, the Docker and Compose
files, the CI workflows and the dependency trees; it ran Sobelow, `hex.audit`,
`deps.audit` and `npm audit` locally. **The full report is held privately by
the owner and is not committed** — `SECURITY.md` asks for private reporting,
and a public repository does not publish its own unfixed weaknesses. This
document names each item by its *class* and its *fix*, which is what the work
ledger needs; it carries no reproduction steps. The review's identifiers
(H1–H4, M1–M6, L1–L11) are kept so the private report and this plan can be
read side by side.

This is the PM triage per ADR-0038: dedup against the pipeline, the decisions
the owner has to make, a batch, and the issues to file once it is adopted.

**Status: ADOPTED 2026-09-05** — owner sign-off on PR #756 ("mach es so"),
which per this document's own terms signs **ADR-0045** (D-1 and D-2) and
accepts **D-3** and **D-4** as recommended. The tracker and the issues in
Part 4 were filed the same day: **#757** (E21 tracker) and **#758–#772**.

---

## Part 0 — The finding that governs the rest

**NFR-4 records a decision the code does not help the operator honour.**

The inventory says: *web UI unauthenticated by design (trusted network /
reverse-proxy; optional built-in auth OQ-8)*. README and the docs index repeat
it. The review does not dispute the decision; it found that the delivered
system contradicts its own premise in three places, and the four high findings
are those three contradictions plus one consequence of them:

1. **Production binds every interface, unconditionally.** `config/dev.exs`
   has the `PHX_BIND_ALL` switch and defaults to loopback; `config/runtime.exs`
   has no switch and always binds `0.0.0.0`. The safe default exists only for
   developers.
2. **The documented home deployment is the development configuration.**
   `docs/home-deployment.md` says `docker compose up`; the Compose file runs
   `MIX_ENV=dev` with debug error pages, the code reloader, origin checks off,
   the public-repository session secret, the database port published on every
   interface with its default password, and a fallback value for both bearer
   tokens. "Trusted network" is doing all the work, and the file makes the
   network larger than the operator thinks.
3. **Nothing validates the request's Host.** The origin check protects the
   WebSocket only. A page rendered over plain HTTP is readable by any site the
   operator's browser visits, through the standard rebinding trick every
   unauthenticated home-network service is subject to. The trust boundary is
   not the network; it is the operator's browser, and that is on the internet.
4. **Given 1–3, a server-side fetch of an operator-supplied URL is a way into
   the home network**, and the logo path accepts one from the API and from the
   UI without a scheme, host or address check and follows redirects.

The consequence for planning: **OQ-8 is due now, not at Phase 3.** The PRD
(§1, revised 2026-08-12) made built-in auth a precondition for parking live
broker credentials on the box. The review shows the precondition is earlier
than that — an adopter following the documentation today gets a tool for no
network, not a tool for a trusted one. Everything else in the review is
ordinary hardening that rides a batch under ADR-0036.

The second thing the review established is worth stating because it is the
reason the batch is small: **inside the trust boundary the system is sound.**
No SQL-injection surface (every fragment literal, every parameter bound), no
atom creation from input, the audit journal and the research log append-only
at the database, no float column for money, Decimal parsing guarded at every
entry, the bearer token compared in constant time and never logged, every
provider host a constant, TLS verified, Sobelow and both audits in CI with
written skips. The batch changes the perimeter and closes a few provenance
seams; it does not touch the ledger's arithmetic.

---

## Part 1 — Dedup: what the pipeline already holds

| Review item | Already in the pipeline | Ruling |
|---|---|---|
| M2 (no CSP, three inline scripts, inline handlers), the HSTS half of M1 | **#382** — remove the Sobelow ignores for CSP and HTTPS | #382 absorbs both. Its first acceptance criterion (per-request nonces) is superseded by a simpler shape the review makes visible: the three inline scripts become one static file served by `Plug.Static` and the inline handlers become hooks, after which a strict `script-src 'self'` needs no nonce plumbing. No asset pipeline is introduced; it is a file move. The issue is amended, not replaced. |
| M6 (three open cowlib advisories behind the Hex pin) | The Sprint 9 Lane M re-check trigger ("a fixed cowlib ships") | The trigger has not fired and there is no sign it will. **D-3** below replaces waiting with a decision. |
| L11 (Actions pinned to major tags) | **#314** CI hardening; Dependabot for `github-actions` exists | Rides Lane M of the batch; #314 gains one line. |
| L10 (PDF intake requirements) | **ADR-0021**, Accepted, unimplemented | No issue. The review's sandbox requirements (argv-only invocation, private temp dir, byte and page limits, hard timeout that kills the process, no-network sandbox, output cap) are appended to the ADR as an implementation note when the batch opens, so they are read before the first line of that importer is written. |
| L7 (journal guard covers fewer tables than the code journals) | Sprint 9 plan, Lane A's verified correction of ADR-0044 §5 | Confirmed and sharpened: the view, bucket-assignment and snapshot tables are journaled in code and exempt from the guard by the creating migration's own comment. Arm or allowlist — Lane V. |
| L9 (silent economic dedup on import) | #533 (closed), which chose the behaviour | Not reopened. The batch adds the *report* of what was skipped, which #533 did not rule out. |
| Everything under ADR-0036 | Risk-tier rides the batch | Every item here is security-relevant, so every commit group carries the attention label: own commit, invariant verified in the closing act, callout in the briefing. |

Nothing else in the review duplicates an open issue. #354, #328, #330, #332,
#333 (`needs-uat`), #481, #572, #608, #610 are untouched.

---

## Part 2 — Decisions for the owner

Four, each with a recommendation. D-1 is a decision gate under ADR-0026 step 1
and is drafted as **ADR-0045** for signature; D-2 rides inside it as a
section, because it is the same conversation. D-3 and D-4 are recorded here
and are overrulable by one sentence on the PR. **All four signed 2026-09-05**
(owner, on PR #756); ADR-0045 is Accepted.

### D-1 — Optional built-in authentication for the web UI (OQ-8). **Recommend: yes, opt-in.**

One operator, one instance: a single password from the environment
(`PORTFOLIXIR_UI_PASSWORD`), enforced by a plug on the browser pipeline and by
an `on_mount` on the browser `live_session`, session-backed so the LiveView
socket inherits it. Unset means today's behaviour, plus a startup warning
when the server is bound beyond loopback. Not a user model, not roles, not a
change to the bearer tokens. The full shape, the deployment contract and the
asks it answers are in ADR-0045. NFR-4's wording changes from "unauthenticated
by design" to "unauthenticated by default, authenticated by one variable".

### D-2 — The documented deployment becomes a production configuration. **Recommend: yes.**

A second Compose file with a release build (`MIX_ENV=prod`, `mix release`),
required variables without fallbacks (`${VAR:?}`), the database port not
published, the application port published on loopback like the MCP port
already is, a non-root user in both images, and images pinned by digest. The
current file is kept as the development configuration under its own name.
`docs/home-deployment.md` documents the production file. Prod's bind address
gains the `PHX_BIND_ALL` switch dev already has, defaulting to loopback.
Recorded in ADR-0045 as its deployment section.

### D-3 — Bandit replaces Cowboy as the HTTP server. **Recommend: yes, as its own commit group with a browser-verified closing act, like ADR-0037.**

Phoenix 1.8's default server; removes `cowlib` and its three open advisories
from the tree, which lets the Hex pin in CI go and restores `hex.audit` to its
current version. A dependency change is a reviewed decision by the project
context, so it is asked here rather than taken in a lane. Risk: the WebSocket
and static-file paths change implementation; the closing act verifies both in
a real browser at the section-G conditions. If the owner declines, M6 stays as
a tracked exception with a named owner instead of an anonymous CI comment.

### D-4 — Provenance fields are set by the system, never by the caller. **Recommend: yes; a precision of ADR-0044 §4, not a reversal.**

Three fields are meant to say *where a record came from* and are today
accepted from the request body: the import content hash on a transaction, the
`author` and `machine_generated` marker on a research entry, and the logo
bookkeeping keys inside a security's free-form attributes. The fix derives
`author` from the authenticated actor (`owner_ui` → operator, `api_token_*` →
agent), reserves `machine_generated` for a future local-model path, moves the
import hash to a changeset only the import applier can reach, and strips the
logo keys from client writes. The visible surface change is that the MCP
`notes.append` tool loses its `author` argument — an agent can no longer
record an entry as the operator's. ADR-0044 §4 distinguishes the three
authors precisely so that the distinction can be trusted; a field the caller
chooses cannot be.

---

## Part 3 — The batch: E21, perimeter and provenance hardening

One epic branch, one PR, ADR-0026 unchanged. The lanes follow the review's
own order — the perimeter first, because every later item's severity depends
on it. Sizes are rough agent-days; the total is about seven, which is one
sprint with Lane C and Lane D deliberately pushed to the next.

### Lane P — the perimeter (no gate; H2, H3, M1, M5, L4, L8) — ~1.5 days — #758, #759, #760, #761

- **Host guard.** A plug before the router that accepts only the configured
  hosts (`PHX_HOST`, `localhost`, `127.0.0.1`, extendable by environment) and
  answers anything else with 421. Pinned by a `ConnCase` test that requests
  a page with a foreign `Host` and is refused, and one that shows the LiveView
  still mounts on an allowed host.
- **Loopback by default in prod**, `0.0.0.0` only with `PHX_BIND_ALL`,
  mirroring dev; a startup log warning when bound beyond loopback with no UI
  password set (the D-1 hook, harmless before D-1 lands).
- **Session cookie hardening.** `same_site: "Lax"`, `secure: true`,
  `http_only: true` on the session; `Plug.RewriteOn` for
  `x-forwarded-proto` ahead of the session so `secure` holds behind the
  operator's TLS proxy; both signing salts derived from `SECRET_KEY_BASE`
  instead of the two public literals; `force_ssl` with HSTS as an opt-in
  variable (the HTTPS half of #382, closed by this lane). Pinned by a test on
  the `Set-Cookie` attributes.
- **Production Compose and images** per D-2. The development file stays.
- **Token hygiene.** The API refuses to boot with a token shorter than 32
  bytes or equal to a known placeholder; the MCP server compares its token in
  constant time, refuses to start in HTTP mode without one, times out its
  upstream fetches, sets the SDK's host allow-list, and runs as a non-root
  user on a digest-pinned image. Existing `http.test.ts` extended.

**Risk-tier callout:** the Host guard and the cookie change are the two
places a wrong value locks the operator out. The briefing shows the exact
environment an operator behind a reverse proxy needs.

### Lane S — outbound requests (no gate; H4, L5) — ~1 day — #762, #763

- **URL validation in `LogoStore`**, where both the API and the UI paths
  meet: `https` only, no userinfo, the host resolved and every address checked
  against loopback, private, link-local and metadata ranges, no redirect
  following, a generic error to the caller. Pinned by unit tests over a table
  of rejected and accepted URLs and by a `ConnCase` test on the logo endpoint.
- **Discovery allow-list.** The image URL a provider hands back must be on
  that provider's own image host; the third provider's HTML scrape is bounded
  the same way.
- **Body and time bounds on every client:** `content-length` checked before
  the download, the body streamed and cut at the cap, a connect timeout, and
  the sync calls wrapped in a task with a deadline where they are not already.
- **Encoding and validation:** the quote adapter encodes the symbol as an
  unreserved path segment; `ticker_symbol` gains a format validation; the
  search provider's `properties` map is copied through a key allow-list and
  rejected when it is not a map.
- **Stored bytes:** PNG/JPEG/WebP magic bytes checked, and `Plug.Static`
  serves the logo directory with `nosniff`.

**Risk-tier callout:** the validator is deny-by-default; the test table is the
invariant.

### Lane A — optional UI authentication (ADR-0045 signed; H1) — ~1 day — #764, #765

- The plug, the `on_mount`, the login form, the logout, the session flag the
  socket inherits; `ConnCase` and `LiveViewTest` coverage for unset, wrong and
  right password, and for the WebSocket mount refusing an unauthenticated
  session.
- **Confirmation on the four destructive events** the review found bare:
  deleting a security from the row menu, deleting an allowance order,
  removing a logo override, bulk-unassigning classifications. `data-confirm`
  like the seven that already have it.
- Documentation: `docs/home-deployment.md` and the docs index sentence that
  today says "unauthenticated by design".

### Lane V — provenance (D-4 signed; M3, L7) — ~1 day — #766, #767

- `Transaction.import_changeset/2` for the applier; the public changeset
  drops `import_hash` and rejects it on update. Pinned by an API test that
  posts one and gets a validation error, and by the existing applier suite.
- `author` from the actor in `NoteController`; `machine_generated` internal;
  the MCP `notes.append` schema loses `author`; the manifest (#752's
  contract read) records the change.
- `logo_*` keys stripped from client-supplied `attributes`; the detail pane
  renders a logo only from the local logo path; `update_security` merges
  attributes instead of replacing them.
- The journal guard armed on the view, bucket-assignment and snapshot tables,
  or those tables added to `Journal.Allowlist` with the reason — one of the
  two, chosen in the lane and stated in the briefing. The allowlist meta-test
  covers whichever it is.

**Risk-tier callout:** import idempotency. The applier suite plus the new
rejection test are the invariant.

### Lane I — import robustness (no gate; M4, L9, the import half of L3) — ~1 day — #768, #769

- Non-finite decimals rejected in `Imports.Decimals`; catch-all clauses for
  the JSON parser's date, time, security and unit shapes; the parser
  entrypoint rescues into `{:error, :malformed_payload}` so no parser defect
  can take the LiveView down. Pinned by a table of crafted files (each one a
  synthetic two-row export) that must all preview as errors, never crash.
- A row cap in both parsers and a size budget on the preview store with
  oldest-first eviction; only the mapping is rewritten on a mapping change;
  the store keyed by a hash of the session token, never by the token and
  never by the empty string.
- Skipped rows reported with their source row and the layer that skipped
  them, next to `skipped_entries`.
- The two `inspect` fallbacks in the import view replaced by named messages.

### Lane W — web and API hygiene (no gate; L1, L2, L3, L6) — ~1 day — #770, #771

- Bucket colour validated like category colour.
- The chart tooltip built with `textContent`, the way the sunburst tooltip
  already is.
- `inspect(reason)` removed from the three API error paths.
- Default and maximum `limit` on the transaction, security, rate and quote
  reads, following the journal read's 100/1000; a row cap on the quote
  upsert; explicit `length:` on `Plug.Parsers`.
- A small per-IP failure counter in the API auth pipeline (ETS, exponential
  back-off), no new dependency.

### Lane C — content security policy (#382; M2) — ~1.5 days, **next batch**

The three inline scripts into one static file, inline handlers into hooks,
`script-src 'self'`, the Sobelow ignore removed. Pushed to the next batch
because it touches every page's boot path and deserves the closing act's
full browser conditions on its own, not at the tail of a perimeter batch.

### Lane D — dependencies (D-3 signed; M6, L11) — ~1 day, **next batch** — #772

Bandit for Cowboy as its own commit group with the browser-verified closing
act; the Hex pin and its CI comment removed; Actions pinned to SHAs with the
tag in a comment.

### Lane M — maintenance (always present)

The Dependabot state at batch start, the #727 triggers, the version report.
Lane D's SHA pinning can ride here if Lane D is cut.

### Lane Z — structural (small)

- E21 in the Tracker Index and `sprint-status.yaml` when the branch opens.
- NFR-4's sentence in `epics.md` rewritten per D-1; the FR Coverage Map row
  for NFR-4 gains the tracker.
- `SECURITY.md` gains one paragraph: what the perimeter guarantees after this
  batch and what it still expects of the operator.
- The ADR-0021 implementation note (Part 1).

### Sequencing

```
Lane P: Compose/prod ──▶ Host guard, loopback, cookies ──▶ token hygiene
Lane S: validator + tests ──▶ discovery allow-list ──▶ bounds, encoding, bytes
Lane A: #764 plug + on_mount ──▶ #765 confirmations, docs
Lane V: #766 import changeset ──▶ author from actor ──▶ attributes ──▶ #767 journal guard
Lane I, Lane W: independent, any time
Lane Z: registry row when the branch opens; NFR-4 wording after D-1
Next batch: Lane C (#382), Lane D (D-3)
```

No lane waits on a signature any more: D-1 to D-4 were signed on adoption,
so every lane can start the day the batch branch opens.

### Shrink order (cut from the bottom, name the cut in the briefing)

1. Lane W's rate limiter — the token is long by then and the API is
   loopback by default.
2. Lane I's skipped-row report — the cap and the crash fixes are the
   security part; the report is honesty.
3. Lane V's journal-guard item — it is a consistency gap, not an exposure.

Lanes P and S never shrink: they are the four high findings. Lane A shrinks
only by the owner declining D-1, in which case the startup warning and the
loopback default still land in Lane P.

### What "done" means

1. A `ConnCase` request with a foreign `Host` is refused, and the LiveView
   mounts on an allowed one.
2. The logo path refuses a table of private, loopback, link-local, metadata,
   `http` and redirecting URLs, and accepts a public `https` image; no
   discovery source can hand the store a URL off its own host.
3. Prod binds loopback unless told otherwise; the session cookie carries
   `SameSite`, `Secure` and `HttpOnly` behind a proxy that sets
   `x-forwarded-proto`; both tokens are refused when short or placeholder.
4. `docs/home-deployment.md` documents a production Compose file, and that
   file has no fallback for any secret and publishes no database port.
5. If D-1 is signed: an unset password behaves as today with a warning; a set
   password gates every browser route and the socket mount.
6. If D-4 is signed: an API caller cannot set the import hash, the author or
   the logo keys, pinned by tests on each.
7. Every crafted-file fixture in Lane I previews as an error, and the import
   view survives all of them.
8. The closing act (ADR-0026 step 3) includes a dedicated verification pass
   on each risk-tier callout above, and the briefing lists the environment
   variables an operator has to set or change, in one table.

### Disclosure handling

The private report stays private until the batch merges. This document and
the issues name fixes, not exploits. The batch PR's briefing is written the
same way; the closing-act evidence that would show a weakness (a request
that reaches an internal address, for instance) lives in the test suite as
fixtures, not in the PR text. After the merge, the close-out adds one line
to `SECURITY.md` naming the batch as the hardening baseline, and the private
report can be filed as an internal note or discarded.

---

## Part 4 — The work ledger (filed 2026-09-05 on adoption)

A tracker plus thin pointers, filed together on the day of adoption so the
public window between naming a weakness and fixing it is one batch, not a
backlog age. Each body is one paragraph and a link to its lane above.

- **#757 — Epic — Security hardening: perimeter, egress, provenance
  (tracking)**, E21's tracker.
- Lane P: **#758** Host header guard and loopback-by-default in production;
  **#759** session cookie attributes, derived salts, opt-in HSTS behind a
  proxy; **#760** production Compose file and image hardening; **#761**
  bearer-token hygiene on both surfaces.
- Lane S: **#762** validate operator-supplied and discovered logo URLs before
  fetching; **#763** bounds, encoding and byte checks on outbound clients.
- Lane A: **#764** optional single-password authentication for the web UI
  (ADR-0045); **#765** confirmations on the four bare destructive events.
- Lane V: **#766** provenance fields set by the system, never by the caller;
  **#767** journal guard coverage of the view, bucket-assignment and snapshot
  tables.
- Lane I: **#768** import parser robustness, row cap and preview-store
  budget; **#769** report skipped import rows with their reason.
- Lane W: **#770** bucket colour validation, tooltip construction, API error
  messages; **#771** default and maximum limits on list reads, the quote
  upsert and the API auth pipeline.
- Lane D (next batch): **#772** replace Cowboy with Bandit. #382 is amended
  in place with the Lane C shape, not refiled.

All `agentic`. None `needs-uat`: the closing act's browser conditions cover
the two lanes with visible surface (A and P's cookie change). Lane Z adds the
E21 Tracker Index line and the `epic-21` key when the batch branch opens.

---

## Part 5 — Decided here, and what is not mine to decide

**Decided — the ordering.** Perimeter before everything, because the
severity of every other finding is a function of who can reach the port. The
review's own three rounds map onto this batch's Lanes P/S (round 1), A/V/I/W
(round 2) and the next batch's C/D (round 3); the plan keeps that shape.

**Decided — no exploit detail in public artifacts.** The rule follows from
`SECURITY.md` and needs no new decision. Where a lane needs a concrete
example to be testable, the example is a fixture in the test suite.

**Decided — hardening is not new scope.** Every lane fixes behaviour the
requirements already promise (NFR-4, NFR-2, NFR-10, the API contract). Under
ADR-0036 it rides a batch as risk-tier work and needs no scope gate; what it
needs is the closing act's dedicated verification pass, which Part 3 names
per lane.

**Not mine: D-1 and D-2, together as ADR-0045.** Built-in authentication
changes what the product says about itself in README, docs and NFR-4, and it
is the answer to an open question the owner has kept open since June for a
reason. The deployment contract rides with it because the two are one
conversation: what an adopter gets, and what they have to do. **Signed
2026-09-05.**

**Not mine, but small: D-3 and D-4.** One is a dependency change, which the
project context makes a reviewed decision; the other narrows a signed ADR's
surface. **Both accepted as recommended, 2026-09-05.**
