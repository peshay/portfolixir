# Security Review Triage — 2026-10-12

Source: a whole-system security review run from 2026-10-12 to 2026-10-27
against `2171847` (the Sprint 21 planning head, `main`). It covered the
Phoenix application (endpoint, router, plugs, every LiveView, the JSON API,
the contexts, the migrations), the MCP companion, the Docker and Compose
files, the CI workflows, the dependency trees, the committed documents for the
privacy rule, and, new in this round, the changes since the previous review
(871 commits, 318 code and infrastructure files) and a regression audit of
every guarantee `SECURITY.md`, ADR-0045, ADR-0054 and the 2026-09-24 triage
state. It ran Sobelow, `hex.audit`, `deps.audit` and `npm audit` locally:
Sobelow and both npm gates are clean; `hex.audit` is red (S8): on 2026-10-13
on one transitive dependency advisory with no reachable call site, and by
2026-10-27 on fourteen more, published after the scan, thirteen of them
against the HTTP server library and one against the cookie-signing library,
every one fixed in a release the lock admits (T-11). **The full report, which
carries reproduction tests, is held privately by the owner and is not
committed.** `SECURITY.md` asks for private reporting, and a public repository
does not publish reproductions of its own unfixed weaknesses. This document
names each item by its **class** and its **fix**, which is what the work
ledger needs, and carries no reproduction steps. The review's identifiers are
kept so the private report and this plan can be read side by side: `H01`–`H72`
for the first round and `K01`–`K19` for the completeness round (twelve of them
merged into siblings that describe the same weakness).

This is the PM triage per ADR-0038: what the review covered, what it found
sound, the dedup against the pipeline, the decisions the owner has to make,
the groups, and the issues to file once it is adopted.

**Status: PROPOSED** — adopted by the merge of this planning PR (ADR-0026 step
1 as amended on PR #780: the merge is the signature). A decision in Part 4
that the owner rejects is changed on the PR before the merge.

---

## Part 0 — What governs the rest

**1. Nothing critical or high, and the trust boundary E21 and E25 built is
standing.** Every finding verified in this round is medium or below. Every
guarantee `SECURITY.md` lists was re-checked against the code by its own
regression finder and holds, except the ones Part 3 names as `docs-vs-code`:
the loopback bind, the Host guard, the per-source throttles, the constant-time
comparisons, the signed and bound session, the CSP with its nonce, the
outbound policy with its redirect re-check and byte caps, the invisible-text
refusal on every writer, and the named principals. The 103 items the
2026-09-24 triage records as shipped were re-read one by one: every fix is
present at HEAD and its test still passes; three have a sibling path the fix
did not cover (H41 and K02, the preference writes on plain HTTP and the
unsigned preference cookies; H61, the writes the journal attributes to a
system job), and all three are in Part 3.

**2. The four medium findings share one class: what the listener accepts
before any credential is checked.** An unauthenticated client can make the
server write multipart bodies to disk for the life of a keep-alive connection
(H01), decode deeply nested JSON over the LiveView socket in a process the
heap cap never reaches (H02), and, through a published advisory in the locked
Bandit release, keep HTTP/2 response streams alive indefinitely on the
cleartext listener (H27; fixed upstream on 2026-10-15, two days after the
scan, and followed by twelve further Bandit advisories by 2026-10-26, so the
lock move of T-11 is now H27's first fix and the listener bounds its second).
The fourth (H58) is the operator's own export file: on the pinned OTP the heap
cap counts the whole upload once per text cell, so ordinary 0.3–2 MB exports
kill the Imports page. The fixes are configuration and bounds, not
architecture: drop the multipart parser no route reads, bound the socket's
frame size, turn cleartext HTTP/2 off and set the listener's connection and
header deadlines, and detach the parser's strings from the upload body. They
are S2 and S4, and they ship first.

**3. One gate is red on `main` today and it is not this review's doing.** `mix
hex.audit` reports advisories the lock admits a fix for: on 2026-10-13 one, on
`decimal` 3.1.1, a transitive dependency no call site in the application can
reach (H28); by 2026-10-27 fifteen, after thirteen Bandit advisories (ten of
them high, all on what the listener accepts before any credential: HTTP/2 flow
control and settings, chunked bodies, header parsing, WebSocket fragments) and
one on `plug_crypto` (the secret key base written to a stack trace on a
wrongly typed argument) were published between 2026-10-15 and 2026-10-26.
Bandit 1.14.0, `plug_crypto` 2.2.1 and `decimal` 3.1.2 fix all fifteen.
Because the quality job runs the live-feed audits ahead of Sobelow, Credo,
Dialyzer and the companion's tests, a new advisory turns all of them silent
(H63). T-11 ships the three lock moves as a hotfix ahead of the batch, as T-1
did for the runtime in September.

**4. What the agent surface still cannot say.** Three low findings sit on
ADR-0054's promise that stored text reaches the agent as data and that every
write is attributed: merge refusals quote stored identifiers inside the app's
own sentences (H11), the invisible-character rule misses the default-ignorable
code points outside its written-out list (H12), and logo and default-view
writes over the API are journaled as a system job or not at all (H61). Each
has a small, local fix.

**5. Where the money is.** Two races and one booking gap touch the ledger: a
security merge and a split booking can interleave so the split commits for the
pre-merge portfolios only (H60); on a fresh instance the first import creates
the default portfolio inside its long transaction, so a concurrent first
import books the file twice (H54); and a cross-currency trade sent with only a
settlement rate books the security currency's units as the account's cash
(H35). H35 changes how stored money is booked and is the owner's decision
(T-19); the two races are lock-order fixes under ADR-0036's risk-tier rule.

**6. What the completeness round added.** A critic read every finder's
coverage record and named eight areas no finder owned; the targeted finders
found nineteen more items, eighteen of which stand, none above low. Four
matter beyond their row. The F18 guard on remembered preferences has a second
bypass: the three preference cookies are unsigned, so any page on a same-site
origin (another port of the same host name, a sibling subdomain) can plant the
view, benchmark or language the operator sees (K02; it joins H41 under T-15).
The run-from-source route the README documents runs the development
configuration, whose LiveView socket accepts any Origin and whose signing keys
are committed, so a DNS-rebound page in the operator's browser can drive every
page and its bookings (K18; the known limit that the development stack is not
a deployment no longer covers a route the docs offer to run the instance). The
pooled FIFO queue (one per security across portfolios, ADR-0015) has two edges
its own decision did not name: a split scales only the lots of the portfolios
it was booked for, while a sale consumes the oldest lot of any portfolio (K09,
T-21), and a security merge pools two queues and restates realized gains with
no preview saying so (K11). And a `since=` delta read whose change set exceeds
the default list limit drops the oldest rows while advancing the cursor past
them, so the agent's next poll never sees them (K17). The rest are bounds,
labels and documentation drift.

---

## Part 1 — Method and coverage

- **Round 1, twenty-four finders in fifteen dimensions:** perimeter,
  authentication, sessions and throttling; the JSON API's input and error
  contract (two finders); every LiveView (three finders); the MCP companion;
  outbound requests and provider data; imports and parsers, once by reading
  and once by property-based fuzzing; the database, the audit trail, integrity
  and races; supply chain, build, deployment and CI; secrets, logging, error
  output and repository privacy; resource exhaustion and storage growth; the
  agent surface and prompt injection; the delta since the 2026-09-24 review
  (three finders over the web layer, the domain contexts, and migrations,
  configuration, infrastructure and the companion); a regression audit of
  `SECURITY.md`, of ADR-0045 and ADR-0054, and of every shipped row of the
  2026-09-24 triage (two finders, S0–S4 and S5–S8); client-side JavaScript and
  the Content-Security-Policy; and dependency and runtime advisories. Every
  finder worked from a shared surface map and a list of the known limits and
  accepted decisions it was not to re-report.
- **Verification, tiered by severity (owner's decision D-9):** every finding
  rated medium, or low with a hostile reach, was checked by three independent
  verifiers with different lenses — a code trace from entry point to sink that
  also wrote and ran a reproduction test offline, a threat-model and severity
  review, and a skeptic told to refute it; a finding counts with at least two
  non-refuting verdicts, its **final severity is the median** and its reach
  the majority. The other low findings had the trace-and-reproduce lens and
  the skeptic, both of which had to stand; the informational findings had the
  skeptic alone. The trace lens's reproduction tests are the red-first tests
  the fix batch starts from.
- **Round 2 (completeness):** a critic read every finder's coverage record
  (the files each read, what it could not finish, the guarantees it checked)
  and named eight areas no finder owned: upgrade and restore paths, the
  remembered preferences, the FIFO queue under splits and merges, the
  derived-value and release tooling, the tax page, the companion's
  environment, the delta reads and the API reference. Eight targeted finders
  ran on them; their nineteen findings were verified the same way.
- **In numbers:** 96 raw findings from the finders, 79 after the merge of
  siblings; 153 verifier verdicts over them (25 findings at three lenses, 24
  at two, 30 at one); 52 reproduction test files written, and for 49 findings
  the test reproduces the weakness offline on the pinned test stack; 75
  findings count (4 medium, 43 low, 28 informational), 4 refuted.
- **Scanners, run locally on 2026-10-13 and again on 2026-10-27:** `mix
  sobelow --skip --exit` clean; without its skip list Sobelow reports eleven
  low-confidence items, each with a written skip the review re-read and agrees
  with; `mix deps.audit` and `npm audit` report nothing; `mix hex.audit`
  reported one advisory on 2026-10-13 (`decimal`, S8, H28) and fifteen on
  2026-10-27, the fourteen new ones published after the first scan against
  Bandit and `plug_crypto` and all fixed upstream (Part 0, point 3; T-11).
- **Known limits honoured:** the limits `SECURITY.md` records (the URL policy
  resolving a name twice, the WebSocket handshake ahead of the Host guard,
  inline style attributes under the CSP, the import preview budget, the MCP
  token's full authority, named tokens that attribute but never restrict, the
  database superuser role, the copied cookie, the development stack) and the
  accepted decisions T-1 to T-10 were re-verified and are not re-reported;
  where a documented reason no longer holds or a consequence is wider than
  recorded, the row says so.
- **Refuted:** H24, H29, H48, K15; a finding its verifiers refuted is dropped
  and listed in the private report with the guard that stops it, and in Part 5
  with its ruling.

---

## Part 2 — Dedup: what the pipeline already holds

| Review item | Already in the pipeline | Ruling |
|---|---|---|
| H27, H28, H63 (the advisories and the gate order) | the `hex.audit` red on `main`: on `decimal` since 2026-10-10, on Bandit and `plug_crypto` since their advisories of 2026-10-15 to 2026-10-26 | the three lock moves ship as a hotfix ahead of the batch (T-11); the gate order is a one-line CI change in S8 |
| H60 (merge and split interleaving) | **#1214** (a booking edit deadlocks with a merge) | sibling of the same lock-order class; one commit group takes both (S6) |
| H20 (the token floor is a length check) | **#1202** (the floor checks length only) | #1202 is the open decision; H20 adds the verified consequence and closes with it (S1) |
| H49, H03 (throttle tables without an entry cap) | — | companion and application share one fix shape (S1) |
| H48 (503 and 500 reach the agent as plain failures) | **#899** (Idempotency-Key, unbuilt) | the key is the full answer; H48 ships the warning alone (S7) |
| H13 (add_version hinted non-destructive) | **#951** (MCP maxLength on free text) and the profile work of Sprint 17 | not a duplicate: a hint and a profile set, not a length (S7) |
| H29, H66 (release and advisory gates) | **#1189** (release paths leave out .dockerignore), **#1218** (CI pulls Docker Hub unauthenticated) | same workflow files; one commit group in S8 |
| H53, H54, H07, H08 (import preview cost and locks) | **#971** (profile the apply's per-row cost), **#925** (bulk-preload import hashes), **#1203** (preview resolves a security differently) | the cost issues stay open as performance work; H53 and H54 are correctness and ship in S5 |
| H61, H14 (writes the journal cannot attribute to the token) | ADR-0054 §3 (named principals) | residuals of #967 on paths it did not name (S6) |
| K09, K11 (one FIFO queue per security across portfolios: split rows scale only their own portfolio's lots; a security merge pools two queues and restates realized gains) | **#1198** (the pooled queue mixes price currencies), ADR-0015 amendment of 2026-10-09, **#957** (list the flow effects of collapses in the merge preview) | the same pooled-queue design as #1198, a different mechanism: K09 is a correctness fix in the matcher (scale every lot the sale can consume), K11 adds the restatement to the merge preview and rides #957's row (S6) |
| K08 (the daily performance walk is unbounded in one process; the warm-up and refresher walks run outside the heap cap) | **#1204** (a capped async load takes the page down), G05 (the heap cap's scope) | not a duplicate: #1204 is what happens when the cap fires, K08 is a walk the cap never sees; one issue in S4 names the bound and the memoised range |
| K17 (a `since=` delta read past the default limit drops the oldest rows and advances `as_of` past them) | G06 (delta reads missing rows from long transactions, fixed by DeltaCursor), F72 (the capped-and-echoed list contract) | the same contract, a different cause: the cursor ships in S6 with K17's ordering fix |
| K10 (the booking drawer books a generic split row through the create path) | G07 (split facts frozen on update), G12 (cumulative factor bound), H60 | residual of G07 on the create path (S6) |
| K12 (a tax statement an agent records reads "recorded manually") | T-8 / G30 (author mark on rule versions), H14 | the same residual class as H14 and T-16: attribution on paths #967 did not name (S7) |
| K13 (NUL in a LiveView field reaches an account or bucket query) | H36 (the API side, S4), G24 (the text rule) | sibling of H36; one fix shape (validate before any query) covers the page side (S4) |
| K02 (unsigned preference cookies planted from a same-site origin) | F18 (FetchSite), H41 (plain-HTTP bypass), W-6 | a second bypass of F18's guard: the fix signs or re-validates the remembered values rather than widening the header check (S1) |
| K18 (the run-from-source route's socket accepts any Origin and signs with committed keys) | `SECURITY.md` known limit 10 (the development stack is not a deployment), H18 (the same route's public database login) | the limit's reason no longer holds for the run-from-source route the README now documents; one change to the development configuration (S1) |
| K16 (Node's opt-in environment proxy tunnels the companion's token through an HTTP proxy) | M-4 (plain-HTTP base URL), known limit 6 | a documented consequence of the plain-HTTP base, not a new mechanism; a sentence in the companion guide (S2) |
| K01 (the tax identity backfill bounds in graphemes but writes code points; a legacy value past 255 code points stops the upgrade migration) | G21 (the backfill, shipped in E25) | residual of G21 on an upgrade or restore path (S2) |
| K06 (a non-positive exchange rate stored before 2026.10.1 is never value-checked on read) | F26 (the writer-side bound) | residual of F26 on the read side; the read treats such a rate as missing and no stored row is changed (S4) |
| K03, K04, K05, K14, K07, K19 | — | nothing in the pipeline |

Nothing else in the review duplicates an open issue.

---

## Part 3 — The groups

Each row: the review identifier, the final severity and reach after
verification, the weakness as a class, the fix, and the test that pins it. No
reproduction, payload or request sequence.

### S1 — Credentials, sessions and the perimeter

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H03 | low | hostile | resource exhaustion | Bound the table: key IPv6 sources by their /64 (one `:inet.ntoa` of the masked address), cap the row count (for example 50 000; past it, stop recording new sources and answer 401 without a row, or evict the oldest), and give :api a scope-wide ceiling on first failures from previously unseen sources. Keep the sweep. | reproduction test on file (private report); promoted red-first in the batch |
| H04 | low | config | hardening gap | In `parse_cidr/1` refuse (or at least warn at boot through `unreadable_proxies_warning`-style wiring in Application.warn_if_exposed/0) a prefix shorter than, say, 8 bits for IPv4 and 32 for IPv6, naming the entry and the consequence; the Compose example and .env.example keep the single-address form. | reproduction test on file (private report); promoted red-first in the batch |
| H18 | low | config | docs-vs-code | Ship the Compose example with an empty database password so Compose refuses it, and refuse at boot in a release an empty, placeholder or short database password, naming the variable and never the value; give SECURITY.md one sentence on the source route's posture (T-14). | reproduction test on file (private report); promoted red-first in the batch |
| H22 | low | config | secret handling | In named_principal!/1 never echo a name that fails the rule unless it is itself name-shaped (e.g. <= 32 bytes of [A-Za-z0-9_-]); otherwise report only the entry position, the length and a hint ('if this entry is a bare token, write name=<token>'). Do the same in default_name!/2 for PORTFOLIXIR_API_PRINCIPAL. | reproduction test on file (private report); promoted red-first in the batch |
| H41 | low | config | csrf | Read an absent Sec-Fetch-Site as same-origin only where browsers send one; on plain HTTP off loopback remember a choice only when the Referer names the request's own origin, else apply it to that request alone; or move remembering to an explicit same-origin action; state the remaining limit in SECURITY.md (T-15). | reproduction test on file (private report); promoted red-first in the batch |
| H19 | info | config | docs-vs-code | Warn at boot when the login lifetime is not a whole number of days (or accept fractions), re-check a mounted page's session at its expiry, and say in SECURITY.md that the lifetime is checked per request and per mount. | written red-first in the batch |
| H20 | info | config | docs-vs-code | Keep the length floor, warn at boot on a token with few distinct characters (application and companion alike), and reword SECURITY.md: the lock labels wrong tokens and slows nothing; a token generated as documented, not the floor, makes guessing infeasible (T-17). | written red-first in the batch |
| H49 | info | config | resource exhaustion | Cap the map (e.g. 10,000 records): when full, evict the record with the oldest lastFailure that is not locked, or stop recording new unlocked sources; optionally key IPv6 sources by /64 as F04 proposed for the application's throttle; keep the time-based prune. | written red-first in the batch |
| K02 | low | hostile | session | Never take a preference the server did not write: sign the three cookies and drop a choice when the Cookie header carries the name twice, or keep the remembered choice only in the signed session; on HTTPS use the __Host- prefix so no Domain or Path variant can be planted; note in the deployment guide that the instance wants a host name of its own (T-15). | reproduction test on file (private report); promoted red-first in the batch |
| K18 | low | config | csrf | Build the development configuration's socket origin list from the same hosts as its Host guard instead of accepting any origin, derive its LiveView salt from the secret as the release does, state the run-from-source posture in SECURITY.md, and have the README require the UI password on that route. | reproduction test on file (private report); promoted red-first in the batch |

### S2 — Deployment, listener and logging

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H27 | medium | hostile | supply chain | Move the lock to Bandit 1.14.0 (T-11), which fixes this advisory (in 1.13.0) and the twelve published after it; then turn cleartext HTTP/2 off and bound the listener (T-12) as defence in depth. Run the full check list on the bump: 1.14.0 tightens the HTTP/1 request line and changes the HTTP/2 defaults. | reproduction test on file (private report); promoted red-first in the batch |
| H09 | low | hostile | resource exhaustion | Set the listener's bounds in the endpoint's http options: a connection cap, acceptor count and header read timeout sized for one operator plus the companion; cleartext HTTP/2 off; the container's file-descriptor limit above the connection cap; and a deployment-guide sentence that the port is meant to sit behind an L7 proxy with header timeouts (T-12). | reproduction test on file (private report); promoted red-first in the batch |
| H69 | low | hostile | injection | Escape control characters on their way to the console through a logger filter for prod and dev; turn cleartext HTTP/2 off so no line feed can arrive inside a path; optionally answer 400 to a request path carrying a control byte ahead of the telemetry plug. | reproduction test on file (private report); promoted red-first in the batch |
| H70 | low | hostile | resource exhaustion | Give every service in docker-compose.yml (and docker-compose.dev.yml) a rotating driver, logging: {driver: local} or json-file with max-size and max-file, and name log rotation in the deployment guide for runs outside Compose. | reproduction test on file (private report); promoted red-first in the batch |
| H71 | info | user | info leak | In prod, add a :logger primary filter (installed from Application.start, or through the :default_handler filters config) that rewrites gen_server terminate reports whose last_message is a %Phoenix.Socket.Message{} or a {Phoenix.Channel, _, _, %Phoenix.Socket{}} join to the topic and event name only. | written red-first in the batch |
| H06 | info | config | docs-vs-code | Accept on/off and yes/no uniformly through one `switch/2` helper that returns `{:ok, bool}` or `{:error, value}`, and have warn_if_exposed/0 name any unrecognised value for the protective switches (or refuse at boot for PHX_FORCE_SSL and DATABASE_SSL, which only a release reads). | written red-first in the batch |
| H72 | info | config | secret handling | Check DATABASE_URL at boot in RuntimeConfig (it parses, has a host and a single /database path) and raise naming the variable without its value, as validate_secret_key_base!/1 does; or let Compose pass the password in its own variable beside a URL without credentials, so no character can break it. | written red-first in the batch |
| K01 | low | hostile | lockout/dos | Bound the backfill's normalised value in code points, the count the writers and the column use, so an over-long legacy value is reported and kept as the module promises; rescue a per-row database error into a refusal naming table and id so no single row can stop an upgrade. | reproduction test on file (private report); promoted red-first in the batch |
| K03 | info | config | hardening gap | Parse the database URL's query at boot: map the libpq TLS modes to TLS with verification, refuse the permissive modes and unknown keys naming the variable, refuse a URL switch that contradicts DATABASE_SSL, add a CA-file option over Postgrex's secure defaults, and document both in the settings section of both languages. | written red-first in the batch |
| K04 | info | hygiene | integrity | Refuse to seed when the database already holds a portfolio unless an explicit flag (e.g. --write-synthetic) is given, name the writes in the shortdoc, and attribute them to Actor.system_job("derived_measure") so the journal tells them apart. | written red-first in the batch |
| K05 | info | hygiene | docs-vs-code | In rebuild_derived/0 put server: false into the Endpoint's configuration (and keep the schedulers' boot ticks and after_start out) before starting, or start only the Repo, the memo and the refresher it needs; alternatively document stopping the app and using docker compose run. | written red-first in the batch |
| K16 | info | config | secret handling | Keep the companion's API client off any proxy: when Node's environment proxy is in effect, exclude the API host from it at start-up or refuse to start naming the variable; state in the companion guide and the run-from-source block that a proxy-enabled environment needs the API host excluded. | written red-first in the batch |

### S3 — Outbound requests and provider data

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H38 | low | hostile | ssrf | Make the manual logo a browser-side upload: allow_upload in the logo dialog and LogoStore.store_manual_bytes/4 (already written, unused), and remove the URL form from the UI. | reproduction test on file (private report); promoted red-first in the batch |
| H50 | low | hostile | resource exhaustion | Make every provider parse linear in the body: split the ECB feed into dated blocks before the regex or use a streaming parser with entity expansion off, search only a bounded prefix of a logo page with a non-backtracking pattern, bound text fields before any regex, and run each parse under the wall-clock guard the HTTP client uses so a slow parse fails alone. | reproduction test on file (private report); promoted red-first in the batch |
| H39 | low | config | resource exhaustion | Refuse the sync and retry events server-side while a run is in flight, give the quote sync a catalog-wide single-flight key (also closing the overlapping scheduled ticks), and make the logo retry a no-op while a drain is pending. | reproduction test on file (private report); promoted red-first in the batch |
| H51 | info | hygiene | hardening gap | Judge IPv4 shorthand the way the connect path parses it: when the strict parser refuses a host, try the lenient parser and judge its result as a literal under both resolve settings, or refuse any host that is neither a strict literal nor a DNS-shaped name; add the shorthand forms to the policy test's literal table. | written red-first in the batch |
| H52 | info | hygiene | hardening gap | Call delete_existing_logo_file(security, storage_dir) before the write in download_and_store/4 and store_manual_bytes/4 (or remove the other extensions after a successful write and attribute update), as remove_logo/2 already does; optionally have the reconciliation remove files that no logo_path names. | written red-first in the batch |

### S4 — Input bounds and cost

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H01 | medium | hostile | resource exhaustion | Drop `:multipart` from the endpoint's Plug.Parsers (no route reads a multipart body; the Imports upload is a LiveView socket upload), so no request can make the server write a file before authentication. | reproduction test on file (private report); promoted red-first in the batch |
| H02 | medium | hostile | resource exhaustion | Bound what the LiveView transport decodes: a frame-size cap on the socket (and a serializer or handle_in guard before decoding as defence in depth), a lower body length for the JSON and urlencoded parsers sized to the largest documented API body, and a JSON depth bound. | reproduction test on file (private report); promoted red-first in the batch |
| H58 | medium | user | lockout/dos | Detach every string an Entry keeps from the upload body, for example `:binary.copy(trimmed)` in present_string in both parsers (names, ISIN, WKN, ticker, currency, account and depot names, note), or one pass over the preview before it is assigned, parked or handed to a task. | reproduction test on file (private report); promoted red-first in the batch |
| H26 | low | hostile | open redirect | Never build links from the request URI's raw path. In ClassificationsLive.handle_params derive current_path from the route ("/classifications", "/classifications/new", "/classifications/#{id}") or normalise it ("/" <> Enum.join(String.split(path, "/", trim: true), "/")). | reproduction test on file (private report); promoted red-first in the batch |
| H37 | low | hostile | hardening gap | Type the registry's attribute-backed numeric fields at write (coerce or refuse with 422) and make the sort total with a numeric-pattern guard before the cast, so a stray stored value can never raise; optionally a journaled migration that nulls existing non-numeric values. | reproduction test on file (private report); promoted red-first in the batch |
| H45 | low | hostile | resource exhaustion | Render the catalog options once (a shared datalist or a searchable picker loaded on demand) instead of a full select per row; keep 'create' as the per-row default and open the remap control only when the operator asks for it. | reproduction test on file (private report); promoted red-first in the batch |
| H59 | low | hostile | resource exhaustion | Bound size before materializing. (1) CSV: count line breaks with a scan that stops at max_rows + 2, or feed NimbleCSV.parse_stream through Stream.take(max_rows + 2), before building rows. | reproduction test on file (private report); promoted red-first in the batch |
| H08 | low | user | lockout/dos | Park what the remount needs instead of recomputing it (the resolutions, counts and corrections computed on upload, or a compact summary), or verify at park time that the remount path completes (run it once in a capped task and refuse to park, with a message, when it does not). | reproduction test on file (private report); promoted red-first in the batch |
| H16 | low | user | hardening gap | Flatten the carried parameters the way portfolio_live.ex's kept_param/1 does (keep binary values, expand a list into `key[]` pairs of binaries, drop anything else) and share that one helper between the two merged-away redirects; or encode with Plug.Conn.Query.encode/1, which handles nested lists and maps. | reproduction test on file (private report); promoted red-first in the batch |
| H30 | low | user | hardening gap | Make the API error renderer total: interpolate only the keys a message carries and render each value through a safe helper, so a cast error on an array-typed field answers 422 instead of 500; optionally refuse a non-list value with a field error before the cast. | reproduction test on file (private report); promoted red-first in the batch |
| H31 | low | user | hardening gap | validate_number(:position, greater_than_or_equal_to: -2_147_483_648, less_than_or_equal_to: 2_147_483_647) (or a shared int4 validator reused by Splits) in Classification.changeset, Classification.builtin_changeset, Category.changeset and Category.builtin_changeset; add minimum/maximum to the four MCP zod schemas. | reproduction test on file (private report); promoted red-first in the batch |
| H36 | low | user | hardening gap | Never query with a field of an invalid changeset: the tax parameter upsert takes its fetch branch only for a valid changeset, and the statement changeset checks the holder's text rule before the profile lookup, the guard the allowance-order path already carries. | reproduction test on file (private report); promoted red-first in the batch |
| H07 | low | config | resource exhaustion | Give PreviewStore a byte budget (measure :erts_debug.flat_size at put; refuse or evict past a total such as 256 MiB, and refuse to park a single preview above a per-entry share), or park the raw upload bytes under that budget and re-parse only on a connected mount. | reproduction test on file (private report); promoted red-first in the batch |
| H55 | info | hostile | resource exhaustion | Bound before scanning in Text.check: answer :too_long at once when byte_size(value) > 4 * max (UTF-8's widest code point), and count code points with a non-allocating walk (a binary-matching reduce, or :unicode.characters_to_list avoided) instead of String.codepoints/1; check the length before the two regex passes. | written red-first in the batch |
| K06 | info | hostile | lockout/dos | Treat a non-positive stored rate as no rate in every rate lookup, so the existing excluded-and-named and missing-rate paths apply instead of a crash, and report any such legacy row at boot; no stored row is deleted or changed; correct the market-data-bounds sentence. | reproduction test on file (private report); promoted red-first in the batch |
| K08 | low | user | resource exhaustion | Load each security's quotes from its own first booking through the day its position returns to zero, seed a custom-range walk at its window start instead of the first booking, run the warm-up and refresher walks under the heap cap in a supervised task that fails alone, and name the background walks in the deployment guide. | reproduction test on file (private report); promoted red-first in the batch |
| K13 | info | user | hardening gap | Refuse before binding: the tag-bucket and account-name helpers run the text rule first and answer a field error or a named refusal instead of querying; add a NUL-bearing string to the LiveView event payload sweep so the class is covered on every page. | written red-first in the batch |

### S5 — Import robustness

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H53 | low | user | lockout/dos | Make the preview's refinement lock-free: a try-lock with a short lock timeout in the dry run, simulated creation in the in-memory index instead of inserts, the outcome cached per parked preview rather than recomputed per mount; key the ISIN write lock per normalized ISIN; record the remaining blocking in ADR-0050's dry-run amendment. | reproduction test on file (private report); promoted red-first in the batch |
| H54 | low | user | race | Resolve the default portfolio under its own short advisory lock and commit it before the import opens its long transaction; optionally a unique partial index on a singleton marker as the database backstop (T-20). | reproduction test on file (private report); promoted red-first in the batch |
| H56 | info | hostile | hardening gap | Name the version only when it is a string or an integer (parse_error_message({:unsupported_version, v}) when is_binary(v) or is_integer(v)); answer every other value with the generic 'could not be read as a Portfolio Performance export' message, or map a non-scalar version to :malformed_payload in JsonParser.parse/2. | written red-first in the batch |
| H57 | info | user | hardening gap | Expose the catalog's ticker rule (a Security.ticker_valid?/1 beside identifier_valid?/2) and apply it in PortfolioPerformance.row_error as a named row error, or drop an unusable ticker with a row warning so the security is still created by ISIN or name. | written red-first in the batch |

### S6 — The audit trail and integrity

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H61 | low | hostile | integrity | Make the logo override, removal and rediscovery actor-first and thread the request's actor from the controller and the page; keep the system job for the discovery worker and the boot reconciliation; record the override's source host in the journaled attributes; add the three functions to the write-actor gate (T-16). | reproduction test on file (private report); promoted red-first in the batch |
| H35 | low | user | integrity | In the settlement guard treat a cross-currency trade with a rate but neither amount as guarded: refuse it until it carries the settled cash, or derive the settlement amount from the rate (T-19); list stored rate-only rows among the violations; keep the documented 422 promise true. | reproduction test on file (private report); promoted red-first in the batch |
| H44 | low | user | integrity | One context function that sets include_all and both bucket sets in a single locked, journaled transaction (set_view_buckets taking include_all), called by the picker; the refusal then changes nothing. | reproduction test on file (private report); promoted red-first in the batch |
| H60 | low | user | race | In the split booking and deletion, lock the security row in share mode right after the split-event advisory lock and before the per-portfolio fan-out, so a merge in flight blocks the split and a split in flight makes the merge recompute; the lock order (depots before securities) is kept; add the pair to the lock-race tests (T-20). | reproduction test on file (private report); promoted red-first in the batch |
| H17 | info | user | hardening gap | Render the confirmation on the Delete item regardless of the menu's snapshot, or refuse the delete when the menu was opened with references and ask once more; add the control to the destructive-confirmations invariant. | written red-first in the batch |
| H10 | info | hygiene | resource exhaustion | Compact on a schedule: have PostCommit's 5-second tick (or a daily job) delete every event of a basis below its newest non-pending id, which leaves every current version unchanged (the same rule compact/1 applies), keeping pending rows untouched. | written red-first in the batch |
| H62 | info | hygiene | docs-vs-code | Give both functions an Actor first argument, pass Actor.owner_ui() from the LiveView, and extend the write-actor gate (test/portfolixir/write_actor_test.exs) to list them; drop the transitional comment. | written red-first in the batch |
| K07 | low | user | integrity | Keep a booking without a rate path out of the income's base-currency totals and name it (count and currencies), or, if parity stays by decision, state it where the figure is read: a computation basis on the income payload, in the conversion note, the MCP description and on the page. | reproduction test on file (private report); promoted red-first in the batch |
| K09 | low | user | integrity | T-21: scale every open lot of the security's queue when the split's date passes, whatever portfolio label it carries, so the pool and the scaling agree; the sell preview, the trades and the realized gains then follow the shares actually held. | reproduction test on file (private report); promoted red-first in the batch |
| K11 | low | user | integrity | State the figure the merge changes: compute the FIFO closed trades over each security before and over the combined rows after, put the realized total per close year and the open lots' cost for source, target and result into the preview, its digest and the dialog; in the depot preview say FIFO gains are unchanged and name the moving-average figure for what it is; extend the merge invariant test to compare the preview's after-figure with the report. | reproduction test on file (private report); promoted red-first in the batch |
| K17 | low | user | integrity | Make a capped delta read a page instead of a silent cut: order delta reads by their stamp ascending and, when the page is full, answer the cursor at the last delivered row with a has-more flag; at the least echo the applied limit and a truncation flag on every list read and say so in the delta note and the MCP descriptions. | reproduction test on file (private report); promoted red-first in the batch |
| K10 | info | hygiene | hardening gap | Refuse a split-typed booking on the ledger's generic create path unless the split flow calls it, as the update path already does, and offer only buy and sell in the booking drawer. | written red-first in the batch |
| K14 | info | user | integrity | Run the dialog's writes in one Repo.transaction (tag, cash account, depot, bucket sets), rolling back on any refusal; or validate the depot's full changeset (trimmed name, text rule, name guard) before the cash account is written and create the tag last. | written red-first in the batch |

### S7 — Browser and agent surface

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H11 | low | hostile | injection | Apply #965's rule to identifiers: merge guards and refusals name the identity by kind and carry the stored values as data fields, never inside the sentence; a meta-test asserts that no merge refusal message contains a stored identifier value. | reproduction test on file (private report); promoted red-first in the batch |
| H12 | low | hostile | hardening gap | Extend the invisible-character sets and the shared fixture to Unicode's default-ignorable ranges, refuse a variation selector with no base it can vary, and make the stripping and skeleton helpers drop every default-ignorable code point, not only the format class. | reproduction test on file (private report); promoted red-first in the batch |
| H13 | low | hostile | hardening gap | Give add_version destructive hints and admin placement, or refuse under the book profile any version that would drop a scheduled version or close one in force; correct the hints table and the append-only sentence in the integration guide. | reproduction test on file (private report); promoted red-first in the batch |
| H14 | info | hostile | integrity | Record who last named the rule (name_author set from the actor in create_rule and rename_rule, serialized in rules and findings, an Agent mark beside the name on the Risk page), or show the rename's actor from the journal; state in POLICY_RULE_AUTHOR that author covers the version, not the name. | reproduction test on file (private report); promoted red-first in the batch |
| H21 | info | hygiene | docs-vs-code | No code change: three tests pin the guarantees (the companion keeps failure counts for an hour, existing sessions keep working while the login ceiling is tripped, and the exposure and short-password warnings are wired at boot). | written red-first in the batch |
| H25 | info | hygiene | hardening gap | Pin the claims with tests (the derived LiveView salt, the password absent from debug logs, the API refusing a UI session cookie without a bearer token) and align the ADR wording where it is wider than the code. | written red-first in the batch |
| K12 | low | hostile | integrity | Record an actor-derived author on statement snapshots and allowance orders at create and on every update, as rule versions do; serialise it in the tax reads; mark a row the agent recorded or corrected on the Tax page and in the budget's basis line; keep the source system-set but stop presenting a token's write as a manual transcription (T-16). | reproduction test on file (private report); promoted red-first in the batch |
| K19 | info | hygiene | docs-vs-code | Reword the research-log field list in both languages (author is derived from the credential, the machine-generated flag is reserved; both are ignored or refused in a body), give the German events section the bounds the English one has, and correct the securities list's limit and default in the English reference. | written red-first in the batch |

### S8 — CI and supply chain

| Id | Severity | Reach | Class | Fix | Pinning test |
|---|---|---|---|---|---|
| H64 | low | hostile | ci trust | In the invisible-Unicode gate skip only files an explicit binary allow-list or .gitattributes names, and report every other file that holds a NUL or does not decode as UTF-8 as a violation; run the gate's own unit tests in the pre-commit job. | reproduction test on file (private report); promoted red-first in the batch |
| H65 | low | hostile | supply chain | Stop resolving packages at hook-install time: install the hook packages from the hashed requirements file through system hooks, or reimplement the four hooks as local scripts that need no third-party package; correct the CI comment either way. | reproduction test on file (private report); promoted red-first in the batch |
| H28 | low | hygiene | supply chain | Declare `decimal` in mix.exs and move the lock to 3.1.2 in the T-11 hotfix, together with `plug_crypto` 2.2.1 (the secret key base in a stack trace on a wrongly typed argument, published 2026-10-23); take decimal 3.2 as its own reviewed bump, because it changes division and rounding results. | reproduction test on file (private report); promoted red-first in the batch |
| H63 | low | hygiene | ci trust | Move the three live-feed audits into a job of their own so a new advisory turns one check red while Credo, Sobelow, Dialyzer and the companion gates keep running, or let every deterministic step run when an earlier one fails; optionally run the advisories job on a weekly schedule. | reproduction test on file (private report); promoted red-first in the batch |
| H66 | info | hygiene | docs-vs-code | Cut the calendar release only from a CI run that passed on main (a workflow_run trigger that checks out nothing from the triggering run, or a check-run query), have the tag job verify the tag is reachable from main and green, or reword the guide from 'known-good' to 'a merged point'. | written red-first in the batch |
| H68 | info | hygiene | hardening gap | Add ci_test assertions: every workflow declares workflow-level permissions, ci.yml and commit-authorship.yml exactly `contents: read`, release.yml exactly `contents: write`; no workflow uses pull_request_target, workflow_run or issue_comment. | written red-first in the batch |

---

## Part 4 — Decisions for the owner (T-11 … T-21)

### T-11 — Three lock moves ship as a hotfix ahead of the batch: Bandit 1.14.0, `plug_crypto` 2.2.1, `decimal` 3.1.2. **Recommend: yes, now**

The red gate hides every later check (H63), and Dependabot cannot propose the
`decimal` move because the package is not declared (H28). The Bandit
advisories are the part that cannot wait: ten high-severity items on the
unauthenticated listener, H27 among them, all fixed in 1.14.0 (released
2026-10-26) and 1.13.0 before it. The hotfix declares `decimal`, moves the
three locks, and adds nothing else; it runs the full required check list,
because Bandit 1.14.0 tightens the HTTP/1 request line and changes the HTTP/2
defaults (the Compose smoke test and the socket tests are where a regression
would show). The gate order change rides the batch.

### T-12 — Cleartext HTTP/2 off, and the listener bounded, as defence in depth behind the Bandit move. **Recommend: yes**

No browser speaks HTTP/2 without TLS, the documented reverse proxies talk
HTTP/1.1 to the application, and the companion uses HTTP/1.1. The lock move of
T-11 closes H27 and its twelve siblings; turning the cleartext HTTP/2 listener
off removes the code path a future advisory of that class would need, and the
connection cap and header deadline (H09) cost nothing an operator will notice.
The deployment guide names both.

### T-13 — The multipart parser leaves the endpoint. **Recommend: yes**

No route reads a multipart body: the Imports upload travels over the LiveView
socket. Dropping `:multipart` from `Plug.Parsers` closes H01 without touching
any page. A future upload endpoint adds the parser to its own pipeline, behind
authentication.

### T-14 — The public database password: refuse at boot in a release, keep the development default. **Recommend: as stated**

`.env.example` ships a placeholder that passes every boot check (H18), against
`SECURITY.md`'s "no secret defaults". The release refuses an empty or
placeholder database password the way it refuses one for `SECRET_KEY_BASE`;
the development stack keeps `postgres/postgres`, which `SECURITY.md` already
confines to synthetic data.

### T-15 — Preference writes on plain HTTP: tighten, do not document. **Recommend: tighten**

F18's guard rests on `Sec-Fetch-Site`, which browsers omit on plain-HTTP
non-loopback URLs, so a LAN instance without TLS is where the guard is void
(H41). The fix reads an absent header as same-origin only where browsers send
one, and falls back to the Referer's origin elsewhere.

### T-16 — Writes the journal cannot attribute: actor-first everywhere. **Recommend: yes**

Logo override, removal and rediscovery over the API are journaled as the logo
system job, and the default-view setting is not journaled at all (H61); a rule
rename by a token keeps the operator's author mark (H14); a tax statement a
token records or corrects reads as recorded manually and moves the trim budget
with no mark (K12). ADR-0054 §3 promised attribution; these are its residuals
on paths #967 did not name. The fix threads the request's actor into the three
context functions, journals the setting, and gives tax statements and
allowance orders the author mark rule versions already carry.

### T-17 — The token floor stays a length check, with a boot warning. **Recommend: warn**

H20 and the open #1202 agree: the 32-byte floor is a length check, and under
compare-first the lock no longer slows guessing. An entropy floor would refuse
tokens that work today, against ADR-0045's upgrade promise, so the boot warns
on a token with few distinct characters and `SECURITY.md` stops crediting the
floor with infeasibility.

### T-18 — The import preview's cost: bounds now, a design issue filed. **Recommend: as stated**

Seven findings share the import page's memory and lock shape (H58, H59, H07,
H08, H45, H53, H54). The bounds (detached strings, a byte budget on the
parking store, a size check before materialising, a lock-free dry run, a
single datalist for the catalog) ship in S4 and S5; moving the parse off the
page process is a design change and is filed, not improvised.

### T-19 — A cross-currency trade with only a settlement rate. **Recommend: refuse, and ask**

H35 books the security currency's units as the account's cash when a
cross-currency trade carries a settlement rate but no gross or settlement
amount. The guard can refuse such a trade until it carries an amount, or
derive the settlement amount from the rate. Either changes what a stored
booking means; the owner picks. The review recommends refusing, which loses
nothing already stored.

### T-20 — The lock-order races ride the batch as risk-tier work. **Recommend: yes**

H60 (merge versus split) and H54 (first import versus a concurrent create or
import) are fixed by taking the security row's share lock before the split's
fan-out and by resolving the default portfolio under its own short advisory
lock. Both get their own commit group, a dedicated verification pass with the
interleaving tests the review wrote, and the callout ADR-0036 asks for.
#1214 (a booking edit deadlocks with a merge) is the same class and closes
with them.

### T-21 — A split scales every open lot of the security's FIFO queue. **Recommend: the matcher, not new bookings**

ADR-0015's amendment of 2026-10-09 made the FIFO queue one per security across
portfolios. A split is booked per portfolio that held a position on its date,
so a lot the queue moved to another portfolio's sale is never scaled, and the
trades, realized gains and sell preview of that security are wrong from the
split on (K09). Two fixes are possible: scale every open lot of the security
when the split's date passes, whatever portfolio label it carries (a matcher
change, no new rows), or book a split row for every portfolio with an open lot
in the queue, flat ones included (new bookings in portfolios that hold
nothing). The review recommends the matcher: it changes no stored booking and
follows the amendment's own rule that the queue is the security's. #1198
(mixed price currencies in the same queue) is the sibling decision and stays
open as filed. The finder's other options, FIFO per portfolio or marking such
trades unavailable, either revisit the amendment or hide a figure the matcher
can compute.

---

## Part 5 — The work ledger (filed after adoption)

One tracker issue per group, thin pointers to this document's rows, filed at
branch opening of the fix batch; the hotfix (T-11) is filed on adoption:

- S1 credentials, sessions and the perimeter: H03, H04, H18, H22, H41, H19,
  H20, H49, K02, K18 — one issue, with #1202 folded in.
- S2 deployment, listener and logging: H27, H09, H69, H70, H71, H06, H72, K01,
  K03, K04, K05, K16 — one issue; the deployment guide, the companion guide
  and their German mirrors change with it.
- S3 outbound and provider data: H38, H50, H39, H51, H52 — one issue.
- S4 input bounds and cost: H01, H02, H58, H26, H37, H45, H59, H08, H16, H30,
  H31, H36, H07, H55, K06, K08, K13 — two issues (the listener, parser and
  walk bounds; the 500-instead-of-422 family).
- S5 import robustness: H53, H54, H56, H57 — one issue, with the design issue
  of T-18 beside it.
- S6 the audit trail and integrity: H61, H35, H44, H60, H17, H10, H62, K07,
  K09, K10, K11, K14, K17 — one issue, #1214 folded in; H35 waits for T-19 and
  K09 for T-21.
- S7 browser and agent surface: H11, H12, H13, H14, H21, H25, K12, K19 — one
  issue.
- S8 CI and supply chain: H64, H65, H28, H63, H66, H68 — one issue, with #1189
  and #1218 folded in.
- Refuted, no action: H24 (the architecture document's route-scope pattern is
  superseded by ADR-0054; a one-line doc correction rides the batch), H29
  (what the advisory gates cannot see is the recorded S0 lesson, already owned
  by the version report), H48 (the companion's 503 handling, decided in
  #1045), K15 (a malformed holder in a Tax page link answers 400 through the
  Ecto exception mapping, not 500; nothing is stored, shown or logged at error
  level).

---

## Part 6 — Disclosure handling

The full report stays private. This document and the issues name classes and
fixes, not exploits, and give no payload, threshold or request sequence. The
batch PR's briefing is written the same way. The closing act's evidence that
would show a weakness lives in the test suite as a regression test written red
first, not in PR text. After the merge, the close-out adds one line to
`SECURITY.md` naming this batch as the third hardening baseline, and the
private report can be filed as an internal note or discarded. Two corrections
to public documents ride the batch rather than this PR, because each changes
what an operator is told to do and should land with the code that makes it
true: the listener and log-rotation paragraphs of `docs/home-deployment.md`
(S2) and the token sentences of `SECURITY.md` (S1).

---

## Part 7 — Where each item landed

Filled at the closing act of the fix batch, in the form of the 2026-09-24
review's Part 7: every identifier in order, its status (shipped, partial,
deferred, refuted, no action, repaired on the planning PR) and the commit that
carries its fix, named by subject. Empty until then.
