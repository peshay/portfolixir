# Security Review Triage — 2026-09-24

Source: a whole-system security review run on 2026-09-24 against `44fb82a9`
(the Sprint 15 close-out, `main`). It covered the Phoenix application
(endpoint, router, plugs, every LiveView, the JSON API, the contexts, the
migrations), the MCP companion, the Docker and Compose files, the CI workflows,
the dependency trees, and the committed documents for the privacy rule. It ran
Sobelow, `hex.audit`, `deps.audit` and `npm audit` locally, and all four are
clean. **The full report, which carries reproduction sketches, is held
privately by the owner and is not committed.** `SECURITY.md` asks for private
reporting, and a public repository does not publish reproductions of its own
unfixed weaknesses. This document names each item by its **class** and its **fix**,
which is what the work ledger needs, and carries no reproduction steps. The
review's identifiers are kept so the private report and this plan can be read
side by side: `F01`–`F77` for the first round, `G01`–`G31` for the
completeness round.

This is the PM triage per ADR-0038: what the review covered, what it found
sound, the dedup against the pipeline, the decisions the owner has to make, the
groups, and the issues to file once it is adopted.

**Status: ADOPTED by the merge of the Sprint 16 planning PR** (ADR-0026 step 1
as amended on PR #780: the merge is the signature). The plan that schedules it
is `implementation-artifacts/sprint-plan-2026-09-24-sprint16.md`, Lane H and
Lane S. A decision in Part 4 that the owner rejects is changed on the PR before
the merge.

---

## Part 0 — What governs the rest

**1. One finding sits outside every gate, and it is shipping today.** The
release image builds on an Elixir base tag that Docker Hub stopped rebuilding
in May 2025. `mix release` bundles that image's Erlang/OTP, so every instance
built from the documented deployment runs an OTP patch level with published
TLS-client advisories: two certificate-verification bypasses and one
denial-of-service. CI installs a current OTP for the same major version, so the
test suite never runs on the runtime that ships, and none of the four audit
gates reads the runtime. The fix is a patch move within the pinned Elixir minor
and OTP major, and it goes out **before** the batch as a hotfix (plan D-2,
T-1 below). The class lesson is recorded with it: a version report that checks
an image *tag* cannot see what the tag contains.

**2. The trust boundary E21 built is standing.** Every guarantee
`SECURITY.md` lists was re-checked against the code by its own review
dimension, and the ones that do not hold are listed in Part 3 as findings, not
glossed over. What holds, with the file that proves it in the private report:

- production binds loopback unless told otherwise; the Host guard runs ahead of
  the router and static files and fails closed; the WebSocket's origin check is
  built from the same allow-list;
- every LiveView sits in one `live_session` with the login gate first; the
  login compares in constant time, is throttled before comparing, renews the
  session and has an open-redirect-safe return path; logout is a
  CSRF-protected POST;
- the session cookie is `HttpOnly`, `SameSite=Lax` and `Secure` behind the
  proxy; both signing salts derive from `SECRET_KEY_BASE`; the session lifetime
  is enforced from a server-side stamp;
- the Content-Security-Policy with its per-request nonce is on every browser
  page; no template uses `raw` on user data; client JavaScript builds tooltips
  with `textContent`; every `href` and `src` sink is scheme-checked;
- no SQL is interpolated; no atom is created from input; closed sets resolve
  only after a membership check; `Decimal`'s parse limits and Jason's integer
  limit neutralise large-number inputs on every string and JSON path;
- the audit journal and the research log are append-only at the database; every
  table added since the last review is journal-armed from its creating
  migration; in-force policy-rule versions are immutable at the database;
- every outbound request goes through one bounded client (byte cap while
  streaming, connect and whole-request deadlines, no decompression, verified
  TLS), and the logo path's URL policy re-checks every redirect;
- the MCP companion validates every tool argument before it builds a path,
  types every financial decimal as a string, reaches only the JSON API, and
  compares its token in constant time;
- every GitHub Action is pinned to a verified commit SHA; the workflows run
  with read-only default permissions; there is no `pull_request_target`.

**3. The rest is hardening with reach labels, and most of it needs a crafted
input, a non-default deployment or the full-authority token.** After
verification, 107 findings survive across both rounds: one high (the runtime),
six medium, sixty-seven low, thirty-two informational and one that needs no
action. Forty-two are reachable in normal use (most of those by the operator or
the agent with its own token, where the harm is a crash, a stale figure or an
audit gap, not an intrusion); thirty-eight need a hostile input, a hostile
provider or a position on the network; twenty-two need a particular deployment
setting; five are hygiene with no path an attacker controls. The Sprint 15 rule applies (D-9 of that plan):
hostile-input findings get fixed, each fix removes a class, and they do not set
a sprint's theme on their own. This sprint's theme is the owner's ask, a
security pass, and the plan puts it first.

**4. Three classes recur, and each deserves one fix rather than one per
instance.**

- **Bounds at the boundary.** Dates without a sane year, list sizes, name
  lengths, selector precision and per-request cost appear across the API, the
  LiveViews and the importer. Several findings (a date that wraps on its way
  into the database, a Top-N with no cap, a name longer than its column) are the
  same missing idea: one bounded type or validator per kind of input, used by
  every writer. S4 and S5 build those once.
- **The audit trail's silent paths.** Cascading deletes that remove journaled
  rows, definitions that rules depend on but that change without a journal
  entry, and before-images read outside the writing transaction. The Sprint 15
  lesson ("an invariant added to a write path is swept over every writer of
  that table") has a twin here: an audit guarantee has to hold on every path
  that removes or changes a row, including the database's own. S6 covers these,
  and ADR-0050 §11 covers the account, depot and security share of the
  cascades. The completeness round added the same class's growth side: the
  append-only tables accept unbounded text, and a write that changes nothing
  still journals the whole row twice.
- **The agent's reach.** The second round found that the companion hands every
  session every tool, publishes no read-only or destructive hints, and
  describes an agent-written rule as the operator's standard. None of this is
  a hole in the boundary (the agent is a first-class user holding a token), but
  it makes a prompt-injected agent's mistakes larger and harder to see. S7
  narrows it (T-8).

---

## Part 1 — Method and coverage

- **Round 1, eleven dimensions:** perimeter and authentication; JSON API input
  and the error contract; LiveViews and client JavaScript; the MCP companion;
  outbound requests and provider integrations; imports and parsers; the
  database, the audit trail and integrity invariants; supply chain, build,
  deployment and CI; secrets, logging, error output and repository privacy;
  the surface added since the 2026-09-03 review (E22, E23, E24, the benchmark,
  the settlement guard, the position targets, the id and integer guards); and
  a regression audit of every guarantee `SECURITY.md`, ADR-0045 and the
  2026-09-05 triage state.
- **Verification:** every finding was checked by three independent reviewers
  with different lenses: a code trace from entry point to sink, a threat-model
  and severity review, and a skeptic told to refute it. A finding counts with at
  least two non-refuting verdicts. The **final severity is the median** of the
  three, which lowered most first-round ratings; the final reach is the
  majority of the non-refuting verdicts.
- **Round 2:** a completeness critic read the coverage notes and named the
  areas no dimension had owned (resource exhaustion and storage growth, date and
  time semantics, controllers no round-1 finder had named, invisible Unicode in
  stored text, the MCP agent's blast radius). Targeted finders ran on them;
  their 35 findings were deduplicated against round 1 (four were variants of
  F70) and the remaining 31 verified the same way. All 31 survived, one of them
  medium.
- **Scanners, run locally the same day:** `mix sobelow --skip --exit` clean.
  Without its skip list, Sobelow reports twelve low-confidence items; each has a
  written skip next to it, and the review re-read every one and agrees with it.
  `mix hex.audit`, `mix deps.audit` and `npm audit` report nothing.
- **Refuted:** one first-round finding (F14) did not survive. The input it
  needed is rejected by the JSON parser before any controller runs.
- **Known limits honoured:** the three limits `SECURITY.md` records (the URL
  policy resolving a name twice, the WebSocket handshake ahead of the Host
  guard, inline style attributes under the CSP) were not re-reported. The open
  issue #868 was found again and is folded into S4.

---

## Part 2 — Dedup: what the pipeline already holds

| Review item | Already in the pipeline | Ruling |
|---|---|---|
| F16 (the LiveView id-range guard's gaps) | **#868** (LiveView integer params past int4) | #868 is folded into S4 and closes with it; F16 widens it to path ids and every id-valued parameter |
| F43 (silent cascades) | **ADR-0050 §11** (delete hardening for accounts, depots, securities) | split: ADR-0050's Lane L1 takes the three entity tables; S6 takes classifications, categories, plans, views and snapshots |
| F27 (provider redirects) | **NFR-9 B2** (the outbound chokepoint backstop) | S3 changes `Net.Http`'s redirect handling first; B2 then pins the chokepoint, and its sequencing says so |
| F01 (MCP token hygiene) | **#761** (E21, bearer-token hygiene) | a regression of #761's claim, not of its code: the policy was only ever applied to the API token. Fixed in S1 and the documents corrected |
| F02, F05 (sessions) | **#764**, **#777** (the login and its lifetime) | ADR-0045's revocation decision is kept (T-4); F02 adds one binding, F05 corrects the wording |
| F15, F20 (provenance) | **#766** (D-4 of 2026-09-05, provenance is system-set) | residuals of #766 on paths it did not name: the LiveView research form, quote and tax-snapshot sources. S6 |
| F77 (the runtime) | **#727** (the Elixir and OTP moves, blocked upstream) | not #727's move: a patch inside the pinned minor and major, which none of #727's blockers touches. Lane H |
| G19, G29 (bucket deletes) | F43, F45 (this review) | folded: one journaled cascade in the bucket delete covers both |
| G25, G26 (MCP annotations, one token) | F24 (this review); architecture FU-6 (named principals) | folded into S7 with T-8; FU-6 ships with it |
| G27 (quote overwrite) | F20 (this review) | one commit group: the journaled authored write ships with the forced manual source (T-9) |
| G03, G04, G09 | F06, F28, F44 (this review) | each shares its fix with the F row and ships in the same commit |
| F64, F69 (privacy) | — | repaired on this planning PR, each repair as its own commit (plan D-11) |
| G31 (retry duplicates) | architecture D11/P8, AR-5 (the Idempotency-Key, unbuilt) | S7 ships the outcome-unknown error only; the key is filed at branch opening for Sprint 17 |

Nothing else in the review duplicates an open issue.

---

## Part 3 — The groups

Each row: the review identifier, the **final** severity and reach after verification, the weakness as a class, the fix, and the test that pins it. Severity is the median of the three verifiers; reach is `user` (normal use), `hostile` (a crafted input, a hostile provider or a network position), `config` (a particular deployment setting) or `hygiene` (no path an attacker controls).

### S0 — The runtime toolchain (Lane H, the hotfix)

One item, and the reason the plan ships a hotfix before the batch (T-1).

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F77 | high · hostile | Release and dev images bundle an Erlang/OTP patch level with published TLS-client advisories, older than the patch CI tests against. | Move both images (pinned by tag and digest), CI (its Elixir and OTP inputs and its PLT key) and the agent install script to one exact toolchain on the current OTP patch; have the version report print the OTP inside the base image; keep Dependabot docker bumps flowing; document rebuilding with --pull for operators. | Invariant test: CI's Elixir and OTP inputs, both Dockerfile FROM lines and the agent install script name one Elixir and one OTP. |

### S1 — Credentials and sessions

The perimeter first, because every other finding's severity depends on who can reach the port. The two documents this group corrects (`SECURITY.md`'s token and revocation sentences, the reverse-proxy contract) change in the same commits as the code.

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F01 | medium · config | The MCP companion only checks that its bearer token is present: no strength floor, no placeholder refusal, no failure throttle, unlike the API token. | In requireMcpToken, refuse tokens below the API token's length floor or matching its placeholder list, naming the variable; add a per-source failure lockout or document its absence; align .env.example and SECURITY.md. | Companion start refuses short or placeholder tokens; repeated failures from one source are answered 429. |
| F02 | low · config | Sessions are not bound to the UI password, so changing the password leaves every existing session valid. | At login store a keyed HMAC fingerprint of the password in the session; require it on every request and mount; treat sessions without it as logged out; note it in SECURITY.md and ADR-0045. | After the configured password changes, an existing session is sent to login and LiveView mount halts. |
| F03 | low · config | The trusted-proxy plug parses only the first X-Forwarded-For header line, so behind some proxies a client can choose its own throttle key. | In TrustedProxy, join every X-Forwarded-For line in order (RFC 9110 field combining) before the existing right-to-left walk. | A trusted-proxy request with two forwarding header lines resolves to the last appended hop. |
| F04 | low · config | Login throttling forgets its escalation after the sweep, keys only on exact source addresses, and has no instance-wide ceiling on failed UI logins. | Retain failure counts well past the maximum lock; add a scope-wide rolling failure ceiling for UI logins; optionally key IPv6 sources by /64. The password floor ships with F67. | Escalation survives a sweep; failures spread over rotating sources trip the scope-wide ceiling. |
| F05 | low · config | Logout only removes the cookie from that browser; an earlier copy stays valid, and a zero session lifetime drops server-side expiry, while SECURITY.md claims more. | Correct SECURITY.md, .env.example and both deployment pages to state what logout and a zero session lifetime actually do; server-side revocation or an absolute cap needs an ADR-0045 amendment first. | Doc-invariant test pins the corrected revocation and lifetime wording in SECURITY.md and both language pages. |
| F57 | low · config | The reverse-proxy contract says to forward X-Forwarded-For unchanged and suggests trusting a broad private range, either of which can hand the throttle key to clients. | Reword EN, DE and SECURITY.md: the proxy sets or appends the connecting address and never passes the client's value through; give nginx and HAProxy directives; recommend the exact gateway address. | Docs test pins the append-or-overwrite wording and the single-address trusted-proxy example. |
| F67 | low · config | SECRET_KEY_BASE gets no boot-time validation, so a short, placeholder or publicly known value is accepted; the UI password has no strength floor. | Add validate_secret_key_base! at boot (length floor, placeholder prefixes, the committed dev and test literals), mirroring validate_api_token!; warn on a short UI password beyond loopback, since refusal needs an ADR-0045 decision. | runtime_config_test cases mirroring the API-token table refuse short, placeholder and committed secrets. |
| F09 | info · config | X-Forwarded-Proto is honoured from any peer, unlike X-Forwarded-For, which only a trusted proxy may set. | Honour X-Forwarded-Proto inside TrustedProxy only from loopback or trusted-proxy peers, checked before the address rewrite; or record in the proxy contract that the proxy must overwrite it. | An untrusted peer's forwarded-proto header leaves the scheme http; a loopback proxy still gets Secure cookies. |
| F10 | info · config | The CSRF token, and the Imports preview key derived from it, survive a successful login: the session is renewed but the token is not rotated. | In the login success branch call Plug.CSRFProtection.delete_csrf_token() before renewing the session, keeping the preference keys. | The CSRF token differs after login, and a pre-login token is rejected on logout. |

### S2 — Deployment and logging

The documented deployment is what adopters run, so its defaults are security decisions. The production log level is the item with the widest reach in this group: it writes financial figures and session contents to the container log.

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F08 | medium · config | The dev Compose file publishes the dev app and its database, with development defaults, on every host interface instead of loopback. | Bind both dev port mappings to 127.0.0.1 like the mcp service; record the dev-mode public secrets in SECURITY.md; add a migration note off the pre-#760 dev stack. | ci_test asserts every ports entry in both Compose files is loopback-prefixed. |
| F19 | low · config | The MCP HTTP transport parses request bodies before authentication and lacks a terminal error handler, so malformed requests can return stack traces with local paths. | Register the origin and bearer middleware before express.json; add a terminal error handler returning a generic JSON error; set the Express env to production as a backstop. | Unauthenticated malformed body gets 401; authenticated malformed body gets 400 JSON without stack frames. |
| F25 | low · hostile | Container images are pinned by tag, not digest, and the documented upgrade never re-pulls them, so OS and database fixes never arrive. | Pin every FROM and Compose image by digest, as ADR-0045 §2 already requires (Lane H pins the Dockerfile FROM lines it moves), tracked by Dependabot's docker and docker-compose ecosystems; add pull and build --pull to the upgrade steps. | ci_test asserts every FROM and Compose image line carries a sha256 digest. |
| F50 | low · hygiene | The app connects as the database bootstrap superuser and table owner, so the append-only triggers bind the application code, not the credential. | Document a non-superuser owner role and a runtime role without TRUNCATE as the recommended setup, with the SQL in the deployment guide; no Compose migration this sprint (T-6). | Docs test pins the role guidance in both languages. |
| F54 | low · user | The documented restore is not atomic, so a failed restore can leave the database without its append-only and journal triggers while the app still boots. | Use pg_restore with --single-transaction and --exit-on-error in EN and DE; start the app only after a successful restore; add a trigger-count check to the restore verification. | Docs test asserts --single-transaction in the restore step of both language versions. |
| F59 | low · user | The release tree, code included, is writable by the runtime user because logos live inside it; logos are also lost on rebuild and unbacked. | Make the logo directory configurable and mount a named volume owned by the runtime user; keep the release root-owned and read-only; list the volume in the backup docs. | ci_test asserts no --chown on the release COPY and a logo volume mounted in Compose. |
| F66 | low · user | Production runs at debug log level, so SQL parameters, request and LiveView event params and session contents are written to the logs. | Set config :logger, level: :info in config/prod.exs (optionally a LOG_LEVEL from a fixed allow-list); log rotation in Compose is separate hygiene. | Reading config/prod.exs directly yields logger level info. |
| F68 | low · hostile | The error view handles only 404 and 500, so any other error status crashes rendering: a bodyless 500, with the original error lost. | Add one catch-all render clause per format built on status_message_from_template, matching the API error shape; delete the dead template_not_found. | assert_error_sent for 400, 403, 406 and 413 yields proper bodies, with no secrets in the log. |
| F76 | low · config | The production Compose deployment binds all container interfaces, so the exposure warning cannot tell real exposure apart, and the docs overstate loopback-only reach. | Keep the warning; document the minimum Docker Engine version and why; qualify the loopback-only claim in ADR-0045 and the docs; recommend a UI password for Compose installs. | Doc-invariant test pins the engine prerequisite and the qualified reach wording in EN and DE. |
| F56 | info · config | The deployment secrets file and full-data backup dumps are created with default, world-readable permissions, and the docs give no permission guidance. | Document install -m 600 for .env, backups under umask 077 outside the checkout, encryption at rest, and keeping the token out of argv; ignore dump files in git. | Docs test asserts the restrictive-permission commands in both language versions; .gitignore covers dumps. |
| F62 | info · config | The release starts Erlang distribution by default, listening on container interfaces reachable from the sibling containers. | Set RELEASE_DISTRIBUTION=none in the runtime stage of Dockerfile.release; as a follow-up, split Compose networks so mcp cannot reach db. | ci_test asserts Dockerfile.release sets RELEASE_DISTRIBUTION=none. |
| F65 | info · config | .dockerignore does not mirror .gitignore's personal-state and operator-data entries, so built images can contain agent memory, local settings and stored logos. | Mirror the privacy-relevant and generated .gitignore entries into .dockerignore, and add a check that keeps the two files aligned. | Every privacy-relevant .gitignore entry also appears in .dockerignore. |

### S3 — Outbound requests and provider data

Provider data feeds every valuation, allocation and policy finding, so a hostile or impersonated provider is an integrity threat, not only an availability one. The redirect fix lands before NFR-9's outbound backstop, which pins it.

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F26 | medium · hostile | Provider quote and FX rows are stored without plausibility bounds on date or value, so one implausible row can become the valuation price, masking staleness. | Bound date and positive value in the Quote and ExchangeRate changesets; adapters drop bad points instead of failing the batch; cap latest-quote and latest-rate reads at today. | Stubbed provider points that are future-dated or non-positive store nothing; the latest quote and stale signal hold. |
| F27 | low · hostile | Provider HTTP clients follow redirects to any scheme, host or address without re-checking the URL policy, and can carry an API-key header across hosts. | Guard every redirect hop in Net.Http: re-check the URL policy against a per-client host allow-list, refuse https-to-http, cap hops, drop credential headers on a host change. | Per adapter, a redirect to a disallowed address makes no second request; credentials never cross hosts. |
| F28 | low · user | Long quote or FX histories exceed the database bind-parameter limit in a single insert, and the raise aborts the whole sync run. | Chunk both upserts below the bind limit inside one transaction, summing counts; rescue persistence per security so one failure is a per-row error; map a failed backfill to 502. | Synthetic histories above the bind limit upsert fully; one failing security does not stop the rest. |
| F29 | low · hostile | Search-provider payload fields reach security attributes and API/MCP responses without type or size bounds, including an echo of the raw provider entry. | Pass provider-derived attributes through the scalar-and-length rule Properties uses; drop or allow-list the raw echo; validate name and feed-URL length; make attribute display total. | Stubbed search entries with non-scalar or oversized fields yield bounded attributes and no raw echo. |
| F73 | low · hostile | A correlation step converts a product of spreads to float, which raises outside the double range, so implausible stored rates can break the risk read. | Make square_root total: scale the Decimal into float range around the single float step (or use Decimal.sqrt), report an uncomputable figure as undefined; bound FX rates at write with F26. | Correlation and deviation over extreme synthetic returns yield a figure or null, never raise. |
| G04 | low · user | Each API-created security starts its own unbounded provider backfill task, and sync, FX-history, search and logo endpoints call providers synchronously without single-flight. | Route per-create enrichment through the single serial deduplicating worker the import path uses, or a bounded supervisor that drops when full; single-flight per-security sync and FX backfill, answering 409 while one runs. | Concurrent creates keep at most one enrichment in flight; a concurrent second sync or backfill answers 409. |
| F30 | info · hostile | The Wikipedia logo adapter trusts response shapes and candidate-list length, so malformed upstream JSON raises and one lookup can fan out. | Cap candidates at the requested page size; type-match every field before use; one rescue in LogoLookup.run returning a malformed-upstream error for all callers. | Type-confused stubbed responses return not-found without raising and within the lookup cap. |
| F31 | info · hostile | Path-segment encoding lets relative-path segments through, so a stored identifier can move a provider request to another path on the same host. | One shared path-segment helper that refuses empty or dot-only values (not re-encoded), used by every adapter, which then makes no request; tighten ticker and coin-id validation. | The helper refuses relative-path segments and each adapter makes no request for them. |
| F32 | info · config | The outbound URL policy classifies some special-purpose IPv6 ranges as public, weakening its private-address check. | Make the IPv6 check deny-by-default: only global unicast is public, known embedded-IPv4 forms are judged by their IPv4, and every special-purpose range is refused. | url_policy table test covers each IANA special-purpose IPv6 block as non-public. |

### S4 — Input bounds and cost

One bounded type or validator per kind of input, used by every writer, rather than one fix per instance (Part 0, point 4): dates, decimals and their scale, text length and characters the database refuses, list sizes, and the cost of one request (the risk read, the derived-value memo, the policy findings). #868 is folded in and closes with this group.

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F11 | medium · user | Category parents can form a cycle, and one ancestor walk has no visited-set or depth bound, so an allocation read can recurse without end. | Bound ancestors_of with a visited set or the maximum tree depth; reject a parent that would form a cycle or cross classifications in create and update. | Cycle and self-parent fixtures: every category-result read returns; the cycle-forming write is refused. |
| F06 | low · hostile | A benchmark rate selector from the URL is normalised without a length or precision bound before it is remembered. | Bound the rate in rate_fraction: accept only fractions exact at the engine's scale and cap the normalised length; query, form and cookie-carry paths share it, so a stored selector is re-validated on every read. | An out-of-bound rate selector is not stored, and a previously stored one is dropped on the next request. |
| F12 | low · user | Setting a view's buckets with repeated ids is not de-duplicated, so an otherwise valid request answers 500. | Apply Enum.uniq to include and exclude ids inside Buckets.set_view_buckets, like the sibling writers, covering API, MCP and LiveView at once. | Repeated bucket ids are de-duplicated; context and controller succeed instead of raising. |
| F13 | low · user | A quote upsert with two rows for one date, or a non-object row, raises in the database layer and answers 500. | In prepare_rows reject non-map rows and repeated dates with a changeset error, so the controller answers 422 naming the date. | Upsert with a repeated date or a non-object row answers 422 and stores nothing. |
| F16 | low · hostile | The LiveView id-range guard infers where an id came from instead of checking it, and some id-valued params bypass it, so out-of-range ids reach queries. | Check path params from the router match, parse the remaining id-valued params through IdParam, and fold this into the open #868 sweep. | Out-of-range path ids redirect to the parent regardless of query keys; every id param is guarded. |
| F70 | low · user | Cast date fields accept years far outside a sane range, and such a value can reach storage altered, letting a policy-rule version evade no-backdating. | One shared date type or validator accepting only ISO strings or Date values with a bounded year, applied to every cast date field; journal the stored row; see F51 for the database backstop. | Out-of-range dates answer 422 on policy-rule, transaction and snapshot writes and store nothing. |
| F72 | low · user | The risk read's correlation work grows quadratically with an unbounded top_n, so one API or MCP call can pin a CPU core for minutes. | Cap top_n with the list-limit capped-and-echoed contract and schema maximums; correlate only a fixed number of leading names, stated in the computation basis. | An oversized top_n is echoed at the cap; correlation pair count stays within the fixed bound. |
| G03 | low · user | The derived-values memo has no size bound and its keys embed caller-chosen continuous parameters, so repeated reads can grow memory until the node dies. | Cap the memo by entry count or bytes, flushing the non-authoritative table when exceeded; memoise only fixed periods and quantised rates; move the walk version out of the entry key. | Past the cap a put leaves the table within budget; distinct custom-rate reads add no memo entries. |
| G11 | low · hostile | The target-set endpoint accepts an unbounded array and repeated category rows, so one request runs an unbounded number of journaled upserts in one transaction. | In Targets.set_targets reject repeated category rows as positions already are; cap the batch at the classification's categories plus assigned securities with a 422; mirror a maximum in the MCP schema. | An over-cap batch and a batch with a repeated category row both answer 422 and write nothing. |
| G12 | low · hostile | The cumulative split factor per security is unbounded, so the IRR solver's float conversion can raise on every later performance read. | Make IRR numeric_points return nil with a stated reason for out-of-range amounts; bound the cumulative split factor in Splits.book_split; LiveViews fall back to the failed-performance state instead of matching. | IRR over an out-of-range synthetic amount returns nil with a reason; a factor-exceeding split booking is refused. |
| G14 | low · hostile | Target weights accept arbitrarily fine precision, so renormalisation can overflow drift figures to non-finite values or raise on allocation reads. | Refuse target and cash-target weights beyond a small decimal scale in both changesets, with a migration CHECK after verifying stored rows; skip category-share hints for zero-value positions (board 12, before/after). | An over-precise weight answers 422; an allocation with a tiny top-level sum emits no non-finite field. |
| G15 | low · user | The drift-threshold query parser compares a parsed non-finite decimal without checking it, so the request answers 500 instead of 422. | In DriftParam.parse refuse non-finite decimals before the compare, as the risk controller does; optionally share one finite-decimal helper across the query parsers. | Non-finite min_drift values answer 422 on both the allocation and position-target endpoints. |
| G16 | low · user | Ledger amounts with more decimals than the column scale are rounded by PostgreSQL after validation, so row, response and journal disagree and zero amounts pass. | Quantise money fields and quantity to their column scales in Transaction.validate_changeset before the sign checks, per ADR-0016 §2, so validated, stored, returned and journaled values match; optional positive-amount CHECKs. | An over-scale amount is stored, returned and journaled identically; a positive amount rounding to zero answers 422. |
| G17 | low · user | Over-long names and identifiers and out-of-range transaction amounts pass the changesets and fail in the database with a 500 instead of a field error. | Add codepoint length bounds to every varchar column the API and UI write, a length-and-shape check on the new ISIN, and one range bound matching column precision in Transaction.validate_changeset. | Each over-long or over-range value answers 422 with a field error on API and MCP. |
| G24 | low · user | Text that changesets accept but PostgreSQL refuses, such as control characters or grapheme-counted names over the column width, raises instead of answering 422. | One shared text validator: codepoint length bounds on every varchar column and rejection of NUL and other control characters, mirrored as named row errors in the import parsers; ErrorView catch-all per F68. | A control-character or over-width name answers 422 with a field error; the import preview names the row. |
| F17 | info · user | Several LiveView event handlers assume well-formed payloads and crash the process on unexpected values. | Parse ids with Integer.parse or IdParam and no-op on failure; add catch-all clauses; guard policy-dialog actions on a loaded rule; accept imports mapping params only as maps. | render_hook with malformed payloads leaves each view alive; /imports remounts cleanly afterwards. |
| F74 | info · hostile | Policy-findings cost grows with the number of distinct rule subjects, each needing up to two full valuations, with no cap on rules per portfolio. | Load the context valuation once and derive totals and membership from it; push list_rules filtering and limit into SQL; a per-portfolio rule cap is a product decision. | Findings over many subjects run one context valuation plus one per subject. |
| G05 | info · hostile | No per-process heap limit contains an oversized read or write, so one runaway request process can take down the whole node instead of failing alone. | Fix the unbounded sources first (G01, G02); as defence in depth, set max_heap_size counting shared binaries in each API request and LiveView process; optionally a container memory limit. | API request and LiveView processes each run under a heap cap that counts shared binaries. |

### S5 — Import robustness

The importer is the one path that reads third-party files. Every item here is a crafted file, and every fix is a named file or row error instead of a crash, a stall or a silent collision. The applier's reordering by ADR-0050 (Lane L2) lands first; this group then touches the parsers, the preview, and in the applier only the content hash, the companion-with-parent rule and the result recorders (F36, F37, F40). F36 and F37 are risk-tier: idempotency (ADR-0036).

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F35 | medium · hostile | The Imports preview nests file-derived name lists inside each other, so render size grows quadratically with the distinct names in one uploaded file. | Cap distinct depot, cash and security names at parse with a named file error; bound name length; render the cash choice once, not per depot; compute default cash in one pass. | The parser refuses files past the distinct-name cap; rendered preview size stays bounded at the cap. |
| F33 | low · hostile | A security reference without name or ISIN crashes the Imports preview render, and the parked preview repeats the crash on every remount. | Derive the securities count from the resolution plan (or make security_key total); drop blank references at parse; park a preview only after its first successful render. | Blank or partial security references preview, remount and discard without crashing. |
| F34 | low · hostile | Invalid UTF-8 in a CSV cell passes parsing, then makes the LiveView diff unserialisable, and the parked preview crashes on every remount. | Reject a non-UTF-8 body in PortfolioPerformance.parse with a named file error before anything is parked; optionally refuse invalid names on restore. | The parser returns an encoding error for invalid bytes in any cell; the page stays interactive. |
| F36 | low · hostile | Two import identity keys join fields with an unescaped separator, so distinct security references can collide and share one preview decision. | Make SecurityResolver.key injective (hash a structured term or length-prefix parts); escape separators in compute_hash so stored hashes stay valid; fail closed when one key maps to two references. | Distinct references containing the separator get distinct keys and resolve separately at apply. |
| F37 | low · user | Auto-split tax-refund companions are hashed without their parent row, so a distinct refund can be skipped as already imported. | Fold the parent's hash and companion index into the companion's hash; skip or insert companions together with their parent; document within-file duplicate collapse in ADR-0029. | Two different parents with equal refunds book both; re-importing the same file books nothing, including a companion stored under today's formula. |
| F38 | low · hostile | The JSON row cap counts transactions, not the entries they expand into, so one transaction can yield an unbounded number of derived entries. | Count flattened entries, parents plus companions, against max_rows before building any entry; optionally refuse an oversized units list as a row error. | A file whose expanded entry count exceeds max_rows is refused with a named error. |
| F42 | low · hostile | File-derived account and depot names are interpolated raw into form field names, so a crafted name can nest into another row's parameters. | Address cash and depot rows by an opaque hashed key with a server-side key-to-name map; ignore unknown keys and non-map params in mapping_from_params. | Bracket-bearing names neither change sibling rows nor crash the view; the operator's pick applies. |
| G23 | low · hostile | Security identifiers and names match by exact code points without shape checks, so invisible or lookalike variants evade import matching and the configuration-at-risk warning. | One catalog ISIN predicate with check digit, WKN shape and printable-ASCII tickers, on changed identifiers only; malformed import ISINs become row warnings; strip format characters from names; skeleton-compare names in the warning. | A lookalike ISIN change answers 422; a name differing only by invisible characters still raises the warning. |
| F39 | info · hostile | Parser arithmetic can overflow to non-finite values, and amounts and names are unbounded, so the whole apply fails without naming the row. | One bounds pass after parsing: finite decimals within column precision, names within column width, failures named by row; mirror bounds in changesets; bound integer digits in Decimals.parse. | Overflowing, oversized or overlong values become named row errors, never a failed apply. |
| F40 | info · user | The import applier appends result rows one at a time, which is quadratic inside the database transaction on large re-imports. | Prepend result items in the six recorders and reverse each list once in enrich_after_commit. | Result row order is unchanged; a large synthetic duplicate re-import applies in linear time. |
| F41 | info · config | The preview store budgets entries rather than bytes, and each eviction copies every stored preview into the caller's heap. | Evict by selecting only keys and timestamps; optionally record byte size at put for a byte budget; state the UI-password or loopback guard in SECURITY.md. | Eviction removes the oldest keys without reading any preview payload. |

### S6 — The audit trail and integrity

An audit guarantee has to hold on every path that removes or changes a row, including the database's own cascades (Part 0, point 4). The cascades on accounts, depots and securities are ADR-0050 §11's and are built in Lane L1. The completeness round adds the growth side (unbounded text in append-only tables, no-op writes journaled twice), races on the assignment and target writers, a delta cursor that can miss slow commits, and the quote overwrite of T-9.

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| G27 | medium · hostile | The quote upsert can overwrite stored closes of any source with no before-image, and pinned rows have no journaled way back to provider data. | Journal each authored upsert with the replaced rows as before-image in one transaction, scoping ADR-0017's exemption to the sync writers and ADR-0050 §13's merge writer; add a journaled release of manual rows alongside F20 (API and MCP, agent-first, T-9); return the replaced dates in the upsert response. | An upsert over a provider row journals its prior close; after release a stubbed sync restores the provider close. |
| F20 | low · hostile | Quote source and tax-snapshot source are caller-settable through API and MCP, so any token holder can claim a reserved provenance value. | Require or force manual source on API quote upserts; stop casting source in the public tax-snapshot changeset; narrow the MCP schemas; update the contract manifest. | API and MCP writes naming a reserved source are refused or stored as manual. |
| F43 | low · user | Database cascades silently delete journaled child rows beyond accounts, depots and securities, while the journal records only the parent. | Delete children through their journaled context functions before the parent (the #481 pattern), keeping cascades as backstop; journal each security's prior asset class in bulk updates. | Meta-test: every cascading foreign key into an armed table is listed as removed per-row by its context. |
| F44 | low · user | The append-only research log accepts future-dated entries, which cannot be deleted and can suppress the review-hygiene read indefinitely. | Refuse a future as_of in SecurityNote.changeset with today injected from append_note; mirror it in the MCP schema; clamp stored entries' review date to their insertion date on read. | A future as_of is refused on API, MCP and LiveView; stored ones cannot hide unreviewed positions. |
| F45 | low · user | In-force policy rules are evaluated against view definitions that change without a journal entry, so a rule's finding can shift with no audit trace. | Journal view-definition writes (update and bucket set) with before and after include/exclude sets inside the existing Multi; amend ADR-0018 section 5 and ADR-0049. | update_view and set_view_buckets each leave a journal entry with the prior and new sets. |
| F46 | low · user | The portfolio-metrics memo key omits the version of the walk it was computed from, so stale volatility and drawdown can be served as fresh. | Read the basis data version before the walk and put it in the metrics entry key; never memoize a result built from a stale walk. | A write injected between walk and metrics forces recomputation on the next read. |
| F47 | low · user | Data versions are not commit-ordered, and some quote, FX and view invalidations run outside the writing transaction, so a stale value can stay current. | Run quote, FX and view writes with their bump in one transaction, and add a post-commit bump so the version advances after every commit. | Two connections interleaved so the lower id commits last never leave a stale value served. |
| F49 | low · user | Journal before-images are read outside the writing transaction without a lock, so concurrent writers produce a wrong change history. | Re-read the row FOR UPDATE inside the Multi and use it as changeset base and before-image (or optimistic locking with 409); a concurrent delete answers 404 or 409. | Two updates from one stale read conflict, or their journal before-images chain correctly. |
| F71 | low · user | The settlement guard skips cross-currency buys and sells without a gross amount, so cash can be booked in the wrong currency's units. | Compare the settlement with the cash the projection will actually book (gross, else the quantity-times-price fallback); put the error on gross_amount; list such rows in violations; update the MCP text. | A cross-currency trade lacking gross answers 422; backfilled legacy rows still pass the guard. |
| G01 | low · user | Research-log bodies and policy-rule and event notes have no length bound on append-only storage, and every thesis read reloads all stored bodies. | Add codepoint length caps to note body, invalidation condition, rule-version and event notes, with NOT VALID CHECKs mapped to 422 and MCP schema maxima; thesis_state loads bodies only for the current thesis. | Over-cap bodies and notes answer 422 on API, MCP and LiveView; a thesis read loads no superseded bodies. |
| G02 | low · user | Every journaled update, including one that changes nothing, copies the whole row twice into the append-only journal, and free-text and attribute fields are unbounded. | Skip the write and journal entry when a valid changeset has no changes; bound every free-text column with NOT VALID CHECKs; bound the merged attributes map; keep ADR-0017 full snapshots. | An empty update writes no journal entry; over-cap free text and oversized merged attributes answer 422. |
| G06 | low · user | Delta reads with since= can permanently miss rows from long transactions, because stamps are taken before commit and the cursor margin assumes quick commits. | Compute as_of in the database, no later than the oldest in-flight writing transaction's start, then apply the existing margin; correct the since_param comment and tool text; commit-ordered cursors are the long-term design. | A row stamped before a poll but committed after it is delivered by the next poll from the returned as_of. |
| G07 | low · user | The generic transaction update can re-date, re-rate or re-target a stored split row without the split flow's checks, rescaling other portfolios. | In Ledger.update_transaction refuse changes to a stored split row's date, security, portfolio, type and ratio, allowing notes only; direct corrections to delete-and-rebook through Splits.book_split; restrict the LiveView edit (board 12, pick G12.3). | Changing a split row's date, ratio or security answers 422 on API, MCP and LiveView; notes still update. |
| G10 | low · hostile | Bucket-assignment writes delete then insert without a lock, so concurrent writes merge sets and a mixed override breaks every view-scoped read. | Lock the owning depot or cash-account row FOR UPDATE as the first Multi step of all four assignment writers; make override classification log and fail closed instead of raising. | Two concurrent override or depot-scope writes leave exactly one request's set; view-scoped reads never raise. |
| G13 | low · user | The one-position-per-security-per-plan rule is checked with an unlocked read, so concurrent target writes can file one security under two categories. | Add a partial unique index on plan and security where security is set, failing loudly on existing duplicates, declared as a unique_constraint mapped to the existing duplicate-position 422. | Two concurrent writes filing one security under different categories leave one row; the loser answers 422. |
| G21 | low · user | Tax holder and institution matching folds case differently in Elixir and PostgreSQL and skips Unicode normalisation, so one identity can miss rows or double count. | Fold both sides in the database and group roll-ups by a database-computed key; harden Identity.normalize with NFC, Unicode-space splitting, format-character removal and refusal of values left empty. | Case, space-variant and decomposed spellings of one holder or institution match their rows and roll up once. |
| G22 | low · user | Trim-budget roll-ups and the tax holder picker iterate raw holder spellings, so case variants of one taxpayer yield duplicate budgets and picker entries. | Enumerate folded identities in SQL with the same lower() the lookups use, choosing one display spelling per identity; dedupe the Tax page holder list by that identity. | Snapshots under two case spellings of one holder yield one trim budget and one picker entry. |
| G29 | low · user | Deleting a bucket silently removes it from every view that includes or excludes it, redefining views that in-force policy rules read, without journaling the cascade. | Fold into F45: in delete_bucket's Multi, journal the cascaded view memberships and assignment rows as the before-image; no new 409 guard; extend F45's invariant test to bucket deletes. | Deleting a bucket in a rule-referenced view's include set leaves a journal entry holding the view's prior sets. |
| F15 | info · user | Provenance and re-assignment guards sit only in API controllers; the context casts the machine-generated flag, and the LiveView research path passes it through. | Allow-list research-entry form keys in the LiveView; strip the flag and security_id in the context write functions, setting provenance only via an explicit option; split event create and update changesets. | LiveView and context writes carrying the flag or a new security_id store neither. |
| F48 | info · user | Policy-rule writes lock only the version rows, not the parent rule, so a concurrent version add can survive a retirement. | Lock the parent policy_rules row FOR UPDATE in its own statement before reading versions in add_version, retire_rule and delete_rule. | Concurrent retire and add_version end with no version starting after the retirement. |
| F51 | info · hygiene | The policy-rule database backstop is narrower than documented: some identity, start-date and truncation changes are not refused by the database. | New migration: refuse updates to version identity, predicate or start date; add TRUNCATE triggers on both tables and a rule identity guard; decide the insert-backdating backstop with F70. | Raw SQL update of guarded fields, truncation and rule re-parenting each raise restrict_violation. |
| F52 | info · hygiene | Guard-coverage meta-tests never assert that every table is classified, so a new unarmed table would pass unnoticed. | Assert that database tables, minus migrations and the journal, equal the disjoint union of the armed, unarmed-scope, non-journaled and derived sets, naming any unclassified table. | A table missing from every classification list fails the meta-test by name. |
| F53 | info · hostile | Journaled writes that change no figures still invalidate every portfolio basis, so frequent small writes keep the refresher recomputing everything. | Add struct-matched BlastRadius clauses returning no bases for notes and events, following the policy-rule precedent and keeping the no-catch-all invariant. | Note and event writes leave other portfolios' basis versions unchanged. |
| G08 | info · config | Domain date checks use three unpinned clocks, UTC, the BEAM's local zone and the database session zone, so 'today' can differ between checks. | Route domain 'today' defaults through Clock.today; set the database session zone to the BEAM's in after_connect; document TZ for app and database; keep trigger slack. | A meta-test forbids Date.utc_today in domain code outside an allow-list; snapshot writers honour an injected today. |
| G09 | info · user | A security event's last-checked date accepts any future date, which hides the event from the stale-calendar read until that date. | Refuse a checked_at later than Clock.today plus one day of zone slack in SecurityEvent.changeset; optionally treat stored future values as stale in Events.stale. | A checked_at beyond the slack answers 422 on create and update; today is accepted. |
| G18 | info · user | The deprecated portfolio update rewrites the cash target from a value read before the write, outside the portfolio transaction, losing concurrent changes. | Write the cash target only when the request carries it, as a step in the same transaction that returns an error instead of matching, so a failure rolls back the rename. | A rename without a cash target leaves target and journal untouched; a failed write-through rolls the rename back. |
| G19 | info · user | Deleting a bucket cascades position-override rows away unjournaled, turning an explicit override that loses its last bucket into inheritance. | Fold into F43: inside delete_bucket's Multi, rewrite affected overrides and default sets through the journaled setters, an emptied override becoming explicit-empty; state it in the confirm text (board 12, before/after) and tool description. | An override losing its last bucket stays explicit-empty, and each affected owner gets a journal entry. |

### S7 — Browser and agent-surface hygiene

Real, cheap and low in reach. The agent-surface items make the companion say what it already does, in the places an agent reads (the published tool schemas, the server instructions and the tool hints), and narrow what a prompt-injected agent can do by mistake (T-8).

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F07 | low · hostile | Stored logos and static assets are served without Cross-Origin-Resource-Policy, so other sites can embed or probe them when the UI is open. | Add cross-origin-resource-policy: same-origin to the router's secure browser headers and the Plug.Static header lists; optionally answer cross-site logo fetches uniformly. | Logo and static asset responses carry cross-origin-resource-policy: same-origin. |
| F18 | low · hostile | Preference plugs persist view, benchmark and locale choices from any top-level GET, so another site can rewrite the operator's stored UI scope. | In ViewScope, BenchmarkScope and Locale persist only when Sec-Fetch-Site is same-origin, none or absent; otherwise apply the value to that request only. | A cross-site GET sets no cookie and leaves the stored scope; a same-origin GET still persists. |
| F23 | low · config | With forced TLS on, the app redirects the internal companion's plain-HTTP calls, and the companion follows redirects, possibly resending bodies elsewhere. | Exclude internal hosts from force_ssl through a dedicated variable Compose sets to the service name; make the companion's API client refuse redirects with a named error; document it. | Internal host passes while the public host redirects; the api-client rejects any 3xx by name. |
| G20 | low · hostile | Invisible Unicode in stored free text renders as nothing for the operator but reaches the agent intact, so hidden text survives review in append-only records. | One shared validator refusing tag characters, variation-selector runs, bidi controls and invisible format characters on agent-read fields and in import parsers; show a visible marker for stored rows (board 12, pick G12.2); escape at the MCP boundary. | A body with invisible format characters answers 422; stored ones render a visible marker and reach MCP escaped. |
| G26 | low · config | The companion has no read-only mode or tool allow-list, and every write shares one token journaled under an anonymous actor label. | Ship named principals (overdue FU-6): tokens as name-token pairs, actor label from the matching entry; an opt-in read-only switch (T-8); state the full-authority token as a known limit in SECURITY.md. | A write under a second named token journals that name; if adopted, read-only mode lists and calls no write tool. |
| G30 | low · hostile | Policy-rule tools describe every stored rule as the operator's own standard, although the agent's credential writes rules and payloads carry no author. | Reword the rule tool descriptions and list note neutrally, pointing to the journal; store an actor-derived author on each version, serialize it in rules and findings, and mark agent rules on the Risk page (board 12, pick G12.1). | A rule created over the API reads author agent; one saved in the Risk dialog reads operator. |
| F21 | info · hygiene | MCP security tests assert the hand-written inputSchema, but clients receive the zod-derived schema, so the pinned properties are not what ships. | Point the schema tests at a real tools/list over an in-memory transport; delete the hand-written schema or pin it deep-equal to the published one. | Published tool schemas type decimals as strings and omit author and provenance fields on note append. |
| F22 | info · config | The MCP transport's DNS-rebinding Host allow-list relies on deprecated SDK options and has no end-to-end test. | Validate Host exactly, name and port, in our own Express middleware ahead of the Origin and bearer checks; keep the SDK option as a second layer. | In-process listener: foreign Host 403, foreign Origin 403, missing bearer 401. |
| F24 | info · hostile | MCP tool results pass stored third-party text to the agent verbatim, and nothing marks it as data rather than instructions. | Set server-level MCP instructions stating that names, notes, bodies and search results are data; register read-only and destructive tool annotations so hosts can require confirmation. | tools/list exposes the server instructions, and every tool carries a read-only or destructive annotation. |
| F75 | info · hostile | A benchmark computation_basis interpolates stored free text, and newer agent-read free-text fields have no length bound. | Reference the benchmark by id and currency in computation_basis; add length validation to policy-version and event notes, matching the research-log body cap. | computation_basis contains no stored name; overlong notes are refused with 422. |
| G25 | info · config | No MCP tool publishes annotations, so hosts cannot tell reads from deletes and irreversible writes when deciding what to confirm. | Fold into F24: derive read-only, destructive and open-world hints from each tool's routed HTTP method with named exceptions; keep append-only tools non-destructive, stating permanence in text; document auto-approvable reads. | tools/list: GET-routed tools read-only, DELETE-routed tools destructive, and no tool leaves a hint unset. |
| G28 | info · user | Descriptions of cascading deletes and permanent writes understate what one call removes or makes permanent, and no cascading delete offers a preview. | Name the cascades in classification, category and view delete descriptions, saying the journal keeps only the parent until F43 lands; state policy-rule permanence once in force; dry-run deletes become a separate story. | A description test pins the cascade and permanence wording on the named delete and create tools. |
| G31 | info · user | The companion abandons API calls the server may still commit, and irreversible writes take no idempotency key, so a retry can leave a permanent duplicate. | Turn a timed-out non-GET call into a distinct outcome-unknown error telling the agent to re-read before retrying, stated in irreversible-write descriptions. The architecture's planned Idempotency-Key (D11, P8, AR-5) is not built here: it is filed at branch opening as its own issue for Sprint 17. | A stubbed aborting write yields the outcome-unknown error, and every irreversible-write tool description states it. |

### S8 — CI supply chain

Hygiene on the gates themselves, and the first group cut inside Lane S once the informational items have gone.

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F58 | low · hostile | The MCP image build and the documented standalone install run dependency lifecycle scripts that CI deliberately blocks. | Use npm ci --ignore-scripts in mcp-server/Dockerfile and the install docs (or an .npmrc ignore-scripts setting); optionally a multi-stage image with only dist and production modules. | ci_test asserts the MCP Dockerfile installs with lifecycle scripts disabled. |
| F60 | low · hostile | CI and dev tooling are fetched unpinned or by mutable tags, and toolchain downloads are not checksum-verified. | Hash-pin pre-commit through a requirements file; freeze hook revisions to commit SHAs; pin OTP exactly and service images by digest; verify toolchain downloads against hard-coded SHA-256 values. | ci_test requires 40-hex hook revisions and a hash-pinned pre-commit install. |
| F55 | info · hostile | The migration-immutability CI gate's diff filter misses some change types, so an applied migration can be altered without the gate failing. | Diff with rename detection off and allow only pure additions, or compare base and head path-to-blob maps; pin the flags with a ci_test assertion. | ci_test asserts the gate disables rename detection and permits only added migration files. |
| F61 | info · hygiene | A workflow interpolates a ref name directly into a run script, and checkouts persist the job token for later steps. | Diff against the immutable base SHA passed through env (or an env-quoted ref); set persist-credentials: false on checkouts that never push. | ci_test asserts no github context expressions inside run scripts and persist-credentials false on checkouts. |

### P — Privacy (repaired on this planning PR)

Both items are repaired by this PR, each repair as its own commit, without restating what they contained (T-7).

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F64 | low · user | A stray screenshot of unknown provenance was tracked in the repository under a directory created by an unset path variable. | Removed on this planning PR; /undefined/ added to .gitignore so a stray path cannot be committed again; any history rewrite is the owner's call. | .gitignore carries /undefined/; no tracked top-level undefined or null directory. |
| F69 | low · user | Committed ADR and planning artifacts, and one test fixture, contained passages or values in private-data classes that the repository's privacy rule forbids. | Scrubbed to qualitative wording and synthetic examples, and the fixture given invented values, on this planning PR; history rewrite is the owner's call; no public word list, which would itself disclose. | Optional local, gitignored deny-list pre-commit hook; no committed term list. |

### N — No action

Recorded so the reason is on file.

| Id | Severity · reach | Class | Fix | Pinned by |
|---|---|---|---|---|
| F63 | none · hostile | The commit-authorship gate reads its allowlist and script from the pull request it checks. | No action: the gate is a hygiene lint on self-asserted metadata and every merge is the maintainer's; real attribution would need signed commits. | n/a |

---

## Part 4 — Decisions for the owner

Ten, each with a recommendation. The recommendation is the default; a
comment on the planning PR naming the decision changes it.

### T-1 — The runtime fix ships as a hotfix before the batch. **Recommend: yes** (plan D-2)

Two critical certificate-verification bypasses in the TLS client of every
shipped instance are not batch work. The hotfix moves the images (pinned by
tag and digest), CI, the PLT key and the agent install script to one exact toolchain on the fixed OTP patch
(Elixir 1.18.5 on OTP 27.3.4.18), adds a parity invariant so the four places
cannot drift apart again, makes the version report print the OTP inside the
image, and tells operators to rebuild with `--pull`. Tagged `0.15.1`. The one
real choice inside it, the image source (the Hex team's `hexpm/elixir` images,
because the official library has no 1.18.5 image), is argued in the plan.

### T-2 — A UI password floor: warn, do not refuse. **Recommend: warn at boot**

The API token is refused at boot when it is short or a placeholder; the UI
password has no floor at all (F04, F67). Refusing a short password at boot
would break ADR-0045's promise that an upgrade changes nothing for an instance
that already runs, and a password is the operator's own choice in a way a
machine token is not. So S1 adds a boot **warning** when the password is short
and the instance is bound beyond loopback, next to the exposure warning that
already exists, plus the throttle's scope-wide ceiling that makes a weak
password slower to guess. **To flip:** "refuse" makes the floor a boot error,
recorded as an ADR-0045 amendment.

### T-3 — Backdating a rule version: bound the input, extend the database's update guard, no insert trigger. **Recommend: as stated**

F70 is a date that changes on its way into the database, which lets a new rule
version start in the past although the context refuses that. The class fix is
S4's bounded date type on every writer. F51 adds that the database's own guard
covers updates but not inserts. An insert trigger would be a true backstop, but
the test suite inserts historical versions directly in about fourteen places,
and the only way to keep them is a test-only escape inside a database trigger,
which is a bypass by another name. So: the bounded date (S4), the update guard
extended to identity and start date (S6), and **no insert trigger**; the
context's refusal plus the bounded input are the two layers. **To flip:**
"insert trigger" adds it and rewrites those fixtures to go through the context.

### T-4 — Revocation stays as ADR-0045 decided; the documents are corrected. **Recommend: documents only**

ADR-0045 decided that a logout removes the cookie from that browser and that
rotating `SECRET_KEY_BASE` ends every session everywhere. F05 finds that
`SECURITY.md` and the deployment guide say more than that, and that a session
lifetime of zero turns off the server-side expiry rather than tightening it.
The documents are corrected (S1). A server-side session list, a "log out
everywhere" action or an absolute cap for the zero setting would each change
ADR-0045's decision and need their own amendment; none is recommended now,
because F02's password binding gives the operator a second, cheaper lever. **To
flip:** name the one you want, and it is drafted as an ADR-0045 amendment for
the next planning round.

### T-5 — Provenance: the form's keys are allow-listed now; the context-level rule waits for its reason. **Recommend: as stated**

F15 finds that the research form passes the `machine_generated` flag through to
the context, which casts it. The minimal fix is an allow-list of the form's keys
in the LiveView, so no browser can set a provenance field (S6). Moving the rule
into the context itself, so that only an explicit system option may set
provenance, is the stronger shape, but it is also the design the future local
model path (ADR-0021, NFR-10) will need to decide, and it breaks two existing
context tests that set the flag on purpose. **To flip:** "context now" does both
in S6.

### T-6 — The database role: documented, not migrated. **Recommend: documentation**

F50: the application connects as the database's bootstrap superuser and table
owner, so the append-only and immutability triggers bind the application's
code, not its credential. A dedicated owner role and a runtime role without
`TRUNCATE` are the right shape, but changing the role of an existing
deployment's database is a migration of the operator's own instance, which
Compose's init scripts do not run on an existing volume. S2 documents the roles
and the SQL for a new install, and the plan names a real migration as a later
decision. **To flip:** "migrate" schedules a one-shot role-migration service
with its own restore check.

### T-7 — The privacy repairs, and the history. **Recommend: no history rewrite** (plan D-11)

Five committed records described real data rather than synthetic cases, one
real booking was reused as a test fixture, and an unreferenced screenshot with
no provenance was tracked; the planning PR repairs all three, each repair as
its own commit, and adds the stray directory to `.gitignore`. The same classes
found outside the committed files are listed for the owner privately. The
passages stay in the git history, and the repair commits' own diffs show what
they removed: a named broker attached to the maintainer's private tooling with
an outline of its authentication setup, one real holding, and a few dataset
figures (a count, a span, one booking), but no balance, quantity, net-worth or
performance figure. A rewrite invalidates every clone and fork and cannot
reach copies already fetched. **To flip:** "rewrite" schedules a `git filter-repo` pass as an owner action with
its own instructions.

### T-8 — The agent's reach: hints, one opt-in switch, and an author on rule versions. **Recommend: all three**

The completeness round found that the companion hands every session every
tool, that no tool tells its host which calls read and which delete (G25), that
every write shares one token under one actor label (G26), and that the rule
tools describe every stored rule as the operator's standard although the
agent's own credential can write rules (G30). S7 therefore:

- publishes read-only, destructive and open-world hints on every tool, derived
  from the HTTP method each tool routes to, so a host can auto-approve reads
  and ask before deletes;
- adds **one opt-in read-only switch** to the companion (the default is
  unchanged), enforced both in the tool list and again before each call;
- ships the overdue named principals of the architecture's FU-6, so the
  journal names which token wrote;
- stores an actor-derived **author on each rule version**, shown in the rules
  and findings reads and on the Risk page (board 12, pick G12.1), and words
  the rule tools neutrally.

ADR-0049 gains the author as an amendment note in the batch. **Not
recommended:** holding agent-written rules back until the operator adopts them;
the author and the neutral wording make the difference visible without changing
when a rule is in force. **To flip:** name the part to drop.

### T-9 — Stored quotes: "manual wins" stays, and every authored write is journaled. **Recommend: as stated**

G27: the quote upsert can overwrite stored closes of any source, with no
before-image, because quotes are on ADR-0017's non-journaled list for the sync
path's sake. The fix keeps ADR-0028's rule that a manual quote wins, journals
every **authored** quote write (API and MCP; the UI has no quote writer today)
with the replaced rows as its before-image, returns the replaced dates in the
upsert response, and adds a journaled way to release a manual row back to
provider data (a route under `/api/v1/securities/:security_id/quotes`, scoped
to manual rows and a date range, with its MCP tool), shipping with F20's forced
manual source. The release ships **agent-first**: quotes have no human write
surface today, so a release control would be the page's first quote write; its
control on the security's quotes is boarded on Sprint 17's planning PR and
lands no later than Sprint 17 under the two-way deadline. ADR-0017's exemption
is narrowed to the sync writers and ADR-0050 §13's merge writer, whose moved
and dropped quotes are recorded in the append-only merge manifest instead,
recorded as an amendment in the batch. **To flip:** "refuse by default" makes an authored
write that would replace a provider row a 409 unless the caller asks to
replace, which changes ADR-0028.

### T-10 — Deleting a bucket: journaled, and an emptied override stays explicit. **Recommend: as stated**

G19 and G29: deleting a bucket cascades its override and view rows away
without a journal entry, and an explicit position override that loses its last
bucket silently becomes "inherit". The fix rewrites the affected overrides,
default sets and view memberships through their journaled setters inside the
delete, keeps an emptied override **explicit-empty**, and says so in the
confirm text (board 12) and the tool description. No new 409 is added: a bucket delete
stays possible, and it stays visible. **To flip:** "refuse" answers 409 when
the bucket is still in a view an in-force rule reads.

---

## Part 5 — The work ledger (filed at branch opening)

A tracker plus thin pointers, filed together the day the batch branch opens.
The issues add nothing this document does not already carry, so when they are
filed does not decide the public window: this triage names every item by
class, fix and pinning test from the moment the planning branch is pushed. The
window runs from that push through the owner's review, the merge, the hotfix
and the batch, and closes when the batch merges: one planning round plus one
batch, not a backlog age (plan D-4, the 2026-09-05 precedent). Each body is one
paragraph and a link to its group in Part 3; none carries a reproduction.

- **E25 tracker — Epic — Security hardening, second pass (tracking).**
- **The hotfix issue** (S0), filed with the hotfix PR right after this merge.
- **S1** credentials and sessions · **S2** deployment and logging · **S3**
  outbound requests and provider data · **S4** input bounds and cost (folds in
  #868) · **S5** import robustness · **S6** the audit trail and integrity ·
  **S7** browser and agent-surface hygiene · **S8** CI supply chain.
- **Follow-ups named in the rows, not in scope:** dry-run deletes (G28), a
  Compose network split (F62), a per-portfolio rule cap (F74), commit-ordered
  delta cursors (G06), the database-role migration (T-6) and the
  architecture's Idempotency-Key (G31), filed as thin pointers under E25 and
  listed on its Tracker Index line.

All `agentic`. None `needs-uat`: the closing act's browser conditions (plan
D-10) cover the groups with visible surface. Lane Z adds the E25 Tracker Index
line's issue numbers the same day.

---

## Part 6 — Disclosure handling

The full report stays private. This document and the issues name classes and
fixes, not exploits, and give no payload, threshold or request sequence. The
batch PR's briefing is written the same way. The closing act's evidence that
would show a weakness lives in the test suite as a regression test written red
first, not in PR text. After the merge, the close-out adds one line to
`SECURITY.md` naming E25 as the second hardening baseline, and the private
report can be filed as an internal note or discarded.

Two corrections to public documents ride the batch rather than this PR, because
each changes what an operator is told to do and should land with the code that
makes it true: `SECURITY.md`'s token and revocation sentences (S1) and the
reverse-proxy contract (S1).
