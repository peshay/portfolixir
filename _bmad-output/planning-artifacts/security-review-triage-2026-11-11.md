# Security Review Triage — 2026-11-11

Source: a second whole-system security review (idea row I40), run on
2026-11-10 and 2026-11-11 against `e014f284`, the head of `main`. It covered
the Phoenix application (endpoint, router, plugs, every LiveView's handlers,
the JSON API, the contexts' write paths, the migrations), the MCP companion,
the Docker and Compose files, the CI workflows and the dependency trees, with
priority on surface the review of 2026-09-05 never saw: the news layer
(ADR-0056), logo discovery, the agents surface and named principals
(ADR-0054) and lifecycle merges (ADR-0050). PDF intake (ADR-0021) is not built
and was confirmed absent. The review ran Sobelow, `hex.audit`, `deps.audit`
and both `npm audit` runs locally; all were clean.

**The full report is held privately by the owner and is not committed.**
`SECURITY.md` asks for private reporting, and a public repository does not
publish its own unfixed weaknesses. This document names each item by its
*class* and its *fix*, which is what the work ledger needs; it carries no
reproduction steps. Twenty-four items are held back further: this file is
the repository version of the triage, published before the fixes exist, and
it names those twenty-four by ID, severity and lane only (see "Disclosure
handling"). The complete triage stays with the private report. The review's
identifiers (N-01 to N-93) are kept so the private report and this plan can
be read side by side. Severities are the closing act's (S1 to S3,
`docs/development/sprint-workflow.md`).

Every S1 and S2 below was reproduced by a run before it counted and then read
a second time by a reviewer whose job was to refute it; an S3 was confirmed by
a run or by a traced code path. 93 findings
stand: **4 S1, 27 S2, 62 S3**. Of these, 1 S1, 12 S2 and 11 S3 are held. Five
candidates were refuted and 217 leads were not verified; neither group is in
this document.

This is the PM triage per ADR-0038: what still holds, dedup against the
pipeline, the decisions the owner has to make, three batches, and what to file
once it is adopted.

**Status: PROPOSED** — adopted by the merge of this planning PR (ADR-0026 step
1 as amended on PR #780: the merge is the signature). A decision in Part 2
that the owner rejects is changed on the PR before the merge. The audit was
read-only by its brief: nothing is filed until then.

On 2026-11-24 the four S1 were run again on `a1e54b18`, the head of `main` on
2026-11-23, 393 commits after the audited commit, and all four still stand.
The S2 and S3 were not checked again on that commit, and code added since the
audit (the chain source of ADR-0059, the dashboards and widgets of ADR-0062,
the crash lists, the halving cycles of ADR-0060, the tops and flops of
ADR-0061) was not read by this review.

One thing is known to have moved for the public rows. Between 2026-11-19 and
2026-11-21 `main` changed the lock order of five news writers that can meet a
security merge (`0e8f749b`, `65240537`, `f87db54e`, `336c3893`, `c929c520`).
That is the subject of N-20 and N-21. The review did not run those two again;
the first test of their lane decides whether anything is left of them.

---

## Part 0 — The finding that governs the rest

**A rule that lives in one place only.**

Part of the picture is held. Twenty-four of the 93 findings, one of the four
S1 among them, are named in this file by ID, severity and lane only (see
"Disclosure handling"). This part describes the other 69. The held rows
are not described in this part.

The perimeter is not where this review found its weight. Every fix of the
three earlier reviews that was checked still holds, one of them in part
(Part 1); N-59 is narrower than the class it closed.

What the 69 show instead is one shape, in two places:

1. **A money rule that holds on one write path and not on its neighbour.**
   Portfolixir has two first-class users, and the agent and the importer do
   not book through the operator's forms. Those forms refuse what the API
   accepts (N-05, N-32, N-33). The form reader refuses an ambiguous figure
   that the CSV reader guesses (N-03); on the agent's path the only guard is a
   sentence in a prompt. An escape written for trades applies to a cash
   transfer it was never meant for (N-02). A create replaces an explicit
   church-tax rate of zero that an update stores (N-04). A bulk move skips the
   check the per-row writer makes (N-06). None of these needs an attacker.
   Each stores a figure the documentation says is refused or kept.
2. **A guard pinned by a test narrower than the guard, or by none.** Five
   rows are of this kind (N-85 to N-89): the tests would stay green if the
   guard were removed.

The consequence for planning: **the next batch is about the second user, not
about the network.** The rules belong in the context, where the drawer, the
API, the companion and the importer all pass.

---

## Part 1 — What still holds, and what the pipeline already has

### Still fixed

**The 2026-09-05 review (H1 to H4, M1 to M6, L1 to L11): 20 of 21 still
fixed, one partly, none regressed.** Each item was taken one by one: the
promised fix, the guard at head, the tests that pin it, and siblings added
since.

- M1 is partly fixed by a later decision: since F09 the session cookie's
  `Secure` attribute depends on a named trusted proxy, and the Compose default
  leaves it off with no start-up signal (N-64).
- Three clauses were replaced by later decisions and are not regressions: the
  logo path's "no redirects" became policy-checked redirects (F27), the
  Content-Security-Policy shipped as a per-request nonce instead of a static
  file, and the token lockout's semantics changed with #974 (the token is
  compared before the source's lock).
- Three uncovered siblings were found on the way and are findings of their
  own: N-64, N-77, N-88.

**The 2026-09-24 and 2026-10-12 triages: 16 of 16 spot checks hold.** Both
were read as the record of what is already decided (T-1 to T-21, the accepted
risks, the no-action items), so that a decided matter is not reported again.
Eight fixes of each were checked at head.

### Dedup against the pipeline

As the planning files at the audited commit record it; the tracker itself was
not read (the audit's only network use was image, package and advisory
registries).

- **N-75** (a boot refusal that quotes one shape of swapped token entry) is
  **#1262**, on the polish list at S3. Nothing new to file.
- **N-51**: the bond half is **#1070**, open, classed as a feature by the
  Sprint 22 severity pass (idea F29). The remainder is new (D-6).
- **N-16** is the class of **K17** (the 2026-10-12 triage; shipped in #1296);
  Sprint 28's closing act recorded "the cursor loses nothing" as passed.
- **N-57** is not **#1264**, which is a different residual of the same fix
  (the lifetime does not slide over the socket).
- **#950** (changesets still cast `machine_generated`, T-5) is untouched and
  still open; the newer writers follow the rule.

---

## Part 2 — Decisions for the owner

Seven decisions, D-1 to D-7. D-2, D-3, D-6 and D-7 are the owner's because
they change what the product promises, how stored money data is booked, or
the text of a signed ADR; why D-1, D-4 and D-5 are the owner's is in the
private report. D-1 to D-4 gate Batch 1. Everything else is decided in
Part 5.

Three of the seven (D-1, D-4 and D-5) concern held rows only. Each is named
below by its number and its rows; what it decides about them is in the
private report.

### D-1 — Held (N-01).

Decided by the owner from the private report; stated here when its fix has
merged.

### D-2 — A cash transfer across two currencies stays refused. **Recommend: yes; a currency exchange is its own idea.**

The handbook and the validator's own contract already say so; the code lets
one through (N-02). The fix is the refusal plus a read-only listing of stored
transfers whose two accounts differ in currency. Whether such rows exist on
the owner's instance only the owner can see, and correcting them is the
owner's act. A booking that states both amounts of a real exchange would be a
new transaction shape and goes to the idea list, not into this batch.

### D-3 — The CSV reader refuses a number that is not German notation. **Recommend: yes, with a release note.**

Today it guesses (N-03). The form reader refuses an ambiguous figure and the
import ADR says the import "does not guess"; the CSV path should hold the same
line. Every CSV fixture in the repository already fits the strict pattern. A
file that imported "successfully" before will now show row errors, which is
the point, and the release note must say so. One remainder cannot be settled
by notation (a cell that is valid in both notations with different values);
the second line of defence in this batch is to show amounts on the preview. A
warning when quantity times price is far from the amount goes to the idea
list.

### D-4 — Held (N-07, N-08).

Decided by the owner from the private report; stated here when its fix has
merged.

### D-5 — Held (N-18, N-19).

Decided by the owner from the private report; stated here when its fix has
merged.

### D-6 — What a merge drops is stated, and every security column has a merge disposition. **Recommend: yes; the bond carry stays #1070.**

A cash or depot merge removes a transfer whose fees and taxes the cost report
counts, and says so nowhere (N-29). The remedy the owner chose for K11 fits:
state it, in the preview and in the record. For the security merge (N-51): a
disposition per column and a backstop test that fails when a new column has
none. That does not reopen #1070's classification; it stops the next column
from being dropped unlisted.

### D-7 — Five small choices, each with a default that stands unless flipped.

- **N-37**: the calibration figures mark the calls that rest on a manual
  close and give the score without them. Default: yes. T-9 and ADR-0055 §3
  stay as decided; this adds the marker those decisions imply.
- **N-33**: a cash account's currency is held to the curated list in the
  changeset. Default: yes. The alternative is to document that any code is
  accepted over the API.
- **N-43**: a manual logo's redirects are confined to the named host. Default:
  record the last hop's host instead, because confining refuses image hosts
  that redirect to a CDN under another name.
- **N-77**: registering a feed keeps naming why a host was refused. Default:
  fold the resolver-dependent reasons into one, as the logo endpoint does.
- **N-58** touches design pick J10 A (a deep link that names a view).
  Default: keep the link where the view is the remembered one, drop the
  view from it where the view arrived by address alone.

---

## Part 3 — The batches

Three batches, each one sprint under ADR-0026. Sizes are rough agent-days.
S1 and S2 items become issues; S3 items become lines on their screen's polish
list, as the "Stay in scope" rule orders it. The held rows named under
"Disclosure handling" are the exception: they are filed with their fix. Every
S3 is placed in a lane; Lanes G, N and D hold S3 rows only and are among the
first cuts in the shrink order.

### Batch 1 — money rules first (about 5.5 days, Lane R not counted)

#### Lane L — ledger, import and tax rules (risk tier; D-2, D-3) — ~2.5 days

Its own commit group and its own verification pass: these are money rules,
and N-22 decides whether an import's bookings land.

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-02 | S1 | A cash transfer between accounts of two currencies is accepted when it carries a settlement rate. The cross-currency escape was written for trades; on a transfer one amount then moves in both currencies, and the valuation and the contribution read change with no external flow. | Refuse it in the pure validator, which the importer shares: a field error on the source account, no rate escape. A read-only listing of stored transfers whose accounts differ in currency. |
| N-03 | S1 | The CSV number reader deletes every dot and reads every comma as the decimal sign, wherever they stand. A cell in another notation is booked at a multiple or a fraction of its value with no row error, and the preview shows counts and no figure. | Refuse a cell that is not German notation as the existing row error. Show amounts on the preview. Change the converter prompt and its pin from "is read as" to "is refused". |
| N-04 | S1 | On a new tax statement snapshot an explicit church-tax rate of zero equals the schema default and is taken for "not supplied": the holder's profile rate is stored and journaled in its place under the caller's credential, and the refusal that depends on the sent rate does not fire. | Decide "supplied" from the caller's attributes, not from the changeset's changes. Tests for the explicit zero and for the rule with a liable profile. |
| N-05 | S2 | The stated-cash rule for a same-currency trade is scoped by a field the caller sets, so an update over the API or the companion can pass it where the drawer refuses; the ledger checks do not list the result. | Scope the rule by the three currencies, not by the presence of a leg. Extend the detection read to rows stored before the fix. |
| N-06 | S2 | Moving a security onto a group node of the built-in asset-class tree writes the group's key into the security's asset class through a bulk update that skips the per-row validation. | Refuse a category that is not a class, with a named error and its sentence on the page; guard the setter; list stored rows outside the set. |
| N-22 | S2 | On the Imports page "Discard" pressed while an import runs neither stops it nor waits for it. The import commits, and the page's double-submit guard is lifted with it. | Ignore the discard and disable its button while an apply is under way. |
| N-32 | S3 | The booking drawer keeps an importer's account-currency row out of the settlement path by a hidden form field alone. | Hold the mode on the socket, computed from the stored row; build the trade's attributes from named fields. |
| N-33 | S3 | A cash account accepts any three-character currency code; the curated list is enforced by the dialog and the import only. | Validate inclusion in the changeset for a new or changed code (D-7). |
| N-34 | S3 | The record of currencies a history backfill already sought is one joined setting; its encoding and its size let the once-guard be defeated. | Hold currency codes to their shape on every record; store the sought list one row per code. |
| N-72 | S3 | One pair of money fields is read outside the bounded decimal reader; a malformed value there raises before the changeset. | Parse through the bounded decimal reader, as the sibling fields do. |

#### Lane R — held rows

Both rows are held (N-01, N-31). D-1 belongs to N-01. The lane's size is in
the private report.

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-01 | S1 | Held. | Filed with the merge that fixes it. |
| N-31 | S2 | Held. | Filed with the merge that fixes it. |

#### Lane C — seven rows, four held — ~1.5 days

Four of the seven rows are held (N-07 to N-10). D-4 belongs to N-07 and
N-08.

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-07 | S2 | Held. | Filed with the merge that fixes it. |
| N-08 | S2 | Held. | Filed with the merge that fixes it. |
| N-09 | S2 | Held. | Filed with the merge that fixes it. |
| N-10 | S2 | Held. | Filed with the merge that fixes it. |
| N-37 | S3 | A prediction's resolution reads whatever close is stored now, and a token may write that close (both decided: T-9, ADR-0055 §3). The calibration figures carry no marker for calls resting on a manual close. | Count such calls per calibration block and give the score without them; show each close's source on the pages (D-7). |
| N-38 | S3 | The tool that registers a news feed is published as not reaching outside the instance, though the host is resolved in the call and the feed is fetched on schedule. | Add it to the open-world list, its test and the reference sentence. |
| N-39 | S3 | Three general texts say a read-only tool changes nothing, while the news digest keeps a named reader's bookmark (decided in ADR-0056 D3). | Name the exception where the general promise is made. |

#### Lane G — thirteen S3 rows, eight held — ~1.5 days

Eight of the thirteen rows are held (N-78 to N-84, N-90). Of the five public
rows, N-88 changes one start-up warning; the other four are each fixed by a
test that fails when its guard is removed.

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-78 | S3 | Held. | Filed with the merge that fixes it. |
| N-79 | S3 | Held. | Filed with the merge that fixes it. |
| N-80 | S3 | Held. | Filed with the merge that fixes it. |
| N-81 | S3 | Held. | Filed with the merge that fixes it. |
| N-82 | S3 | Held. | Filed with the merge that fixes it. |
| N-83 | S3 | Held. | Filed with the merge that fixes it. |
| N-84 | S3 | Held. | Filed with the merge that fixes it. |
| N-85 | S3 | No test pins the chart payload's script-closing guard, which sits behind a waived Sobelow check. | Two cases asserting on the raw page text; name the pin in the waiver. |
| N-86 | S3 | Two source-pinned invariant tests (tooltip construction, inline handlers) are narrower than the guard they name. | Widen the patterns to every HTML-parsing sink and every static script. |
| N-87 | S3 | "Non-root users" and "database port not published" hold, and nothing pins either. | Two assertions over the Dockerfiles and the Compose file. |
| N-88 | S3 | The release's loopback default is pinned at the function, not at the line that applies it; the boot warning's input fails open. | Evaluate the runtime configuration with and without the switch; read a missing address as beyond loopback. |
| N-89 | S3 | The actor-first gate keeps a hand-written list of contexts and does not read the News context. | Add it; a completeness test over every module that reaches the journal or a write. |
| N-90 | S3 | Held. | Filed with the merge that fixes it. |

### Batch 2 — the news layer (about 5.5 days)

#### Lane B — held rows — ~1.5 days

All three rows are held (N-11 to N-13).

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-11 | S2 | Held. | Filed with the merge that fixes it. |
| N-12 | S2 | Held. | Filed with the merge that fixes it. |
| N-13 | S2 | Held. | Filed with the merge that fixes it. |

#### Lane I — seven rows, four held — ~2 days

Four of the seven rows are held (N-14, N-15, N-18, N-19). D-5 belongs to
N-18 and N-19.

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-14 | S2 | Held. | Filed with the merge that fixes it. |
| N-15 | S2 | Held. | Filed with the merge that fixes it. |
| N-16 | S2 | A consumer's paged digest reads live rows: a row that moves between two pages is dropped, and the last page's cursor confirms past it. The class of K17. | A continued page also answers the rows a write after the first page touched. |
| N-17 | S2 | A fetch files its items under the binding its feed had before the request; a re-binding committed meanwhile leaves primary items on the old security. | Re-read the feed row under the lock; a database backstop for the binding. |
| N-18 | S2 | Held. | Filed with the merge that fixes it. |
| N-19 | S2 | Held. | Filed with the merge that fixes it. |
| N-40 | S3 | A refused digest page still creates the consumer it names, so refused requests fill the consumer cap. | Look the consumer up without creating it when a page is asked for. |

#### Lane K — lock order — ~1.5 days

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-20 | S2 | A story's promotion to a note locks the story before the security; a security merge takes them in the opposite order. The promotion's side of the deadlock is an error with the note unwritten. | The order AT4 gave the assignment: the security first, then the story. A lock-table row and a race test in both orders. |
| N-21 | S2 | Four more news writers (the matcher, an issuer feed's ingest, a plain recluster, the label write) take news locks before the security. | One order for every news writer that can meet a merge; a lock-table row for each. |

#### Lane N — news hygiene — ~0.5 day

One of the four rows is held (N-74).

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-67 | S3 | One class of malformed cursor is answered with a server error where every other is a 422. | Refuse it in the cursor decoder, as the sibling parameter does. |
| N-71 | S3 | A feed URL bounded in characters can exceed the unique index's byte limit: a server error, nothing written. | Bound it in bytes in the changeset and in the column's check. |
| N-74 | S3 | Held. | Filed with the merge that fixes it. |
| N-77 | S3 | Registering a feed tells the caller how a host name resolved, where the logo endpoint answers one fixed sentence. | Fold the resolver-dependent reasons into one, or record the named code as decided (D-7). |

### Batch 3 — journal, bounds, merges, browser surface (about 7.5 days)

If it must be split, Lane W's S3 rows go to the polish lists first.

#### Lane J — journal and attribution — ~1.5 days

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-23 | S2 | A logo store whose bookkeeping does not change replaces the stored image and leaves no journal entry; the journal keeps naming the earlier actor. | Add a content digest to the bookkeeping, so other bytes are a real change. |
| N-24 | S2 | A manual-logo fetch that stores nothing is not journaled, and the release log keeps only the request line: an outbound request to a caller-chosen host leaves no record of host or credential. | Record the attempt before the request leaves: who asked, and the host. |
| N-25 | S2 | Two simultaneous first assignments of one security to one classification: the later replaces the earlier and is journaled as a second create with no before-image. | Decide the operation and the before-image inside the transaction from the locked row, in the shape #1424 gave the news sources. |
| N-42 | S3 | A quote sync asked for over the API journals its write to the security as the system job, not as the token that asked (the class of H61). | Thread the requester into the sync. |
| N-43 | S3 | The journal names the host the URL named; a redirect may take the stored image from another public host. | Record the last hop's host, or confine redirects to the named host (D-7). |

#### Lane U — resource bounds — ~1.5 days

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-26 | S2 | The journal's list read is bounded by entries, not bytes: a few dozen large journaled writes stop the default journal page and the default API read at the heap cap. | Bound the list read in bytes in the one query both surfaces share; answer an oversized entry with a marker and its sizes. |
| N-27 | S2 | One stored decimal list on the tax parameters record is bounded neither in length nor in scale, and its journal image multiplies it. | Bound length and scale as the scalar rates are. |
| N-28 | S2 | The predictions page resolves every stored prediction several times per load, synchronously and without a limit; the API's limit does not bound the work; predictions are permanent. | Resolve once per load; page the list; load through the capped asynchronous path. |
| N-44 | S3 | A write that can move no figure still supersedes the stored cross-portfolio walk. | Bump nothing when the write names no portfolio and no security; extend the F53 test. |
| N-45 | S3 | Every origin the bounded client talks to keeps a connection pool for the life of the VM, and the URL policy has no port rule. | An idle time for pools; a port rule for redirects. |
| N-46 | S3 | A provider's JSON body is decoded at any nesting depth in a helper process without a heap cap; one client decodes a format it never reads. | Turn decoding off where it is unused; bound nesting before the decode. |
| N-47 | S3 | One provider's row mapping runs after the request's deadline with no bound of its own. | Wrap it in the parse guard, or cap the pair count. |
| N-48 | S3 | The online search forwards its query to both providers without the text rule its sibling read applies, and without a concurrency bound. | Apply the text rule; a matching length in the companion's schema. |
| N-49 | S3 | The Wealth page's rate sync starts one provider fetch per event; the in-flight refusal the Securities page has is absent. | The same clause; a single-flight key shared with the scheduler and the API. |
| N-50 | S3 | The Imports page never cancels a dry run; each discarded file leaves one more simulation running. | Start one at a time, or cancel on reset. |

#### Lane M — merges (risk tier; D-6) — ~1.5 days

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-29 | S2 | A cash or depot merge deletes a transfer between the two accounts as void although the cost report counts its fees and taxes; neither the preview nor the merge record states the cost that leaves the report. | State it: each dropped transfer carries its fees and taxes in the preview and the manifest, and the digest covers the shown figures. |
| N-51 | S3 | A security merge drops the source's bond terms and news identity without listing them; the record's snapshot omits them; no test fails when a security column has no merge disposition. | A disposition per column; the whole stored row in the snapshot; a backstop test over the schema's columns. The bond carry itself stays #1070. |
| N-52 | S3 | The merge preview adopts a legacy ticker the catalog refuses at apply. | Let the write rule decide adoption. |
| N-53 | S3 | The feeds a security merge re-binds are in neither the preview nor the plan digest. | List them in the preview and add them to the digest. |
| N-54 | S3 | A booking with a stray counter leg passes the merge preview and makes the apply fail its own assertion every time. | Refuse a counter leg on kinds that have none; a guard in the merge's build for rows already stored. |
| N-55 | S3 | A confirm repeated after a changed plan applies the fresh plan with no separate act in between. | A changed plan needs one distinct acknowledgement before a confirm counts. |
| N-56 | S3 | A merge's landing reads the dialog's current state, not the state it was started with. | Keep what the apply was started with; ignore dialog events while it runs. |

#### Lane W — browser surface, crashes and small leftovers — ~2 days

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-30 | S2 | The split wizard's preview prints quantities as digits while the privacy mode is on. | Use the masking formatter; add the wizard to the privacy open-state tests. |
| N-41 | S3 | A mapping change in one tab overwrites the mapping another tab of the same session parked for another file. | Write only what this page parked. |
| N-57 | S3 | Events addressed to a LiveComponent skip the per-event session re-check that page events have. | Make the re-check part of the guard every component already attaches. |
| N-58 | S3 | One link on the Allocation tab carries a view that arrived from another site's link. | Build the link by the page's own rule (D-7). |
| N-59 | S3 | The K02 fix for a duplicate session cookie covers one kind of duplicate only; another kind still keeps live pages from connecting. | The host-only cookie prefix over HTTPS; among duplicates prefer the one the request can use. |
| N-60 | S3 | A stored source link is drawn as an anchor whatever its target; one kind of target lets a click change remembered preferences. | Draw own-origin links as text, or remember a preference only through the instance's own controls. |
| N-61 | S3 | A malformed privacy parameter is answered with a redirect to itself, without end. | Normalise the parameter before comparing; treat anything else as no choice. |
| N-62 | S3 | One section builds its links from the raw request address. | Build through the shared page-address helper. |
| N-63 | S3 | A Compose install admits the internal service name as Host on every browser route and the socket, though only the companion's API calls need it. | A second list, consulted for the API and the health route only. |
| N-64 | S3 | With the Compose defaults a TLS proxy on the bridge is not believed until it is named, so the session cookie carries no `Secure`, and nothing at start-up says so. | A start-up warning for that state, and a dated note on ADR-0045. |
| N-65 | S3 | A bucket colour stored before the format rule would still reach a style attribute on one page. | A render-time guard as the sibling view has; a migration that clears non-matching values. |
| N-66 | S3 | One request shape passes the body guard and crashes the write instead of being refused. | Refuse it at the guard. |
| N-68 | S3 | Two pushed events crash the sender's own securities page. | Read the payload through the form helper; wait for the upload to finish. |
| N-69 | S3 | A provider search hit whose identifier carries a control character crashes the page when picked. | Apply the shared text rule to identifiers. |
| N-70 | S3 | Two crafted events crash the sender's own Classifications page, one after its write committed. | Require the loaded tree and membership; match the state first and refuse. |
| N-73 | S3 | The bounded client's own first check judges a URL the HTTP library has already rewritten, not the URL as given. | Judge the URL as given, before the library rewrites it. |
| N-75 | S3 | A boot refusal quotes one shape of swapped token entry (#1262). | Close the one-character gap between the two rules. |
| N-76 | S3 | An import row message carries a file's invisible characters as they are. | Build the message through the guard its siblings use. |

#### Lane D — deployment and documents — ~1 day

Two of the five rows are held (N-35, N-93).

| ID | Sev | Class | Fix |
|---|---|---|---|
| N-35 | S3 | Held. | Filed with the merge that fixes it. |
| N-36 | S3 | The demo seeds write synthetic records beside existing ones with no guard, under the UI owner's identity, and ship inert in the release image (the K04 class). | Refuse a database that holds other records unless a flag says otherwise; write as a system job; keep the demo directory out of the image. |
| N-91 | S3 | The production Compose services set no container hardening beyond a non-root user and a descriptor limit. | Read-only root, dropped capabilities, no new privileges, process and memory limits; the Compose smoke job proves the stack still boots. |
| N-92 | S3 | The operator guides lag the served Content-Security-Policy. | Document what is served, or narrow the style directive to what the guides say. |
| N-93 | S3 | Held. | Filed with the merge that fixes it. |

### Sequencing

```
Batch 1  Lane L: N-02 validator ──▶ N-05 scope by currency ──▶ N-03 reader + preview ──▶ N-04 ──▶ listings
         Lane R: N-01 outside the sprint PR (gated by D-1)
         Lane C: its held rows in the order the private report gives; the public rows any time
         Lane G: independent, any time
Batch 2  Lane B and Lane I: order in the private report; N-18, N-19 wait on D-5
         Lane K: lock-table rows first, then the writers
Batch 3  Lane U's N-26 before Lane J (the journal page must survive what Lane J adds)
         Lane M after Lane K (both touch the merge's lock order)
```

N-01 does not ride the sprint PR; how it lands is in the private report.
That is an exception to "one sprint, one PR", adopted with this plan.

D-1 to D-4 gate Batch 1: D-2 and D-3 are signed with the plan, D-1 and D-4
from the private report. If all four are decided when the plan merges, no
lane waits.

### Shrink order (cut from the bottom, name the cut in the briefing)

1. Batch 3, Lane W's S3 rows: to the polish lists.
2. Batch 3, Lane D.
3. Batch 2, Lane N.
4. Batch 1, Lane G: its cut order is in the private report.

Lane L and Lane R never shrink: they are the four S1 findings. How Lane C
shrinks is in the private report.

### What "done" means

The lists below state what done means for the public rows. The items that
concern held rows only are not in this file: they are in the complete triage,
and each is added here with the merge that fixes its rows.

Batch 1:

1. A cash transfer whose two accounts differ in currency is refused on create,
   on update and in the import, whatever else it carries; a read lists stored
   rows of that shape.
2. A CSV cell that is not German notation is a row error on the preview, and
   the preview shows the amounts it will book.
3. An explicit zero rate on a tax snapshot is stored as zero and the
   consistency rule runs against it.
4. A same-currency trade cannot be updated past the stated-cash rule by any
   combination of fields, and the ledger check lists rows stored before.
5. Each guard named in N-85 to N-89 has a test that fails when the guard is
   removed.
6. The closing act holds a dedicated verification pass on Lane L and on N-01,
   and the briefing lists what changes for an operator and for an agent.

Batch 2:

1. Every news writer that can meet a merge is a row of the lock table, raced
   against the merge in both orders.
2. A paged digest loses no story under a concurrent write.

Batch 3:

1. The journal page and the journal read answer whatever a single entry
   holds.
2. A logo write that changes the stored bytes is journaled under its actor,
   and a manual fetch leaves a record whether or not it stores.
3. A merge's preview and record state every figure and every value the merge
   removes.
4. The privacy mode masks the split wizard.
5. The closing act holds a dedicated verification pass on Lane M: a merge
   deletes bookings.

### Disclosure handling

The private report stays private. Its reproductions are not published. What a
fix's test shows becomes public with the merge of that fix, which is why a
fix and its test land in one merge and never the test first. This document
and the issues name fixes, not exploits, and each batch PR's briefing is
written the same way; closing-act evidence that would show a weakness lives
in the test suite, not in the PR text, as the 2026-09-05 triage decided.

**This file is the repository version of the triage.** It is published with
the planning PR, before the fixes exist. The complete triage, which states
class and fix for every row and the three held decisions in full, stays with
the private report. A class sentence and its fix together tell a careful
reader where to look, so the conservative point for any row is after its
lane has merged. The 69 rows this file states by class and fix are the ones
judged low risk before that.

**Held rows.** Twenty-four rows are not low risk before their fix, and a
public issue, a tracker entry or a planning PR is publication:

- S1: N-01 (Lane R);
- S2: N-31 (Lane R); N-07, N-08, N-09 and N-10 (Lane C); N-11, N-12 and N-13
  (Lane B); N-14, N-15, N-18 and N-19 (Lane I);
- S3: N-78 to N-84 and N-90 (Lane G); N-74 (Lane N); N-35 and N-93 (Lane D).

The held decisions are D-1 (N-01), D-4 (N-07, N-08) and D-5 (N-18, N-19).

A held row gets its issue or its polish-list line with the merge that fixes
it. Until then it lives in the private report or in a private security
advisory, and this file, the trackers and the planning PR name it by ID,
severity and lane only. Nothing that describes a held row is published before
the merge that fixes it; for a held S1 or S2 row, not before the release that
merge makes (every push to `main` that touches shipped code gets one, by the
sprint workflow). A merged fix does not help an instance that still runs
older code, so the merge of N-01 carries a release note.

---

## Part 4 — The work ledger (to file on adoption)

Nothing is filed. On adoption (an entry that belongs to a held row is made
with the merge that fixes it):

- One tracker per batch, naming held rows by ID, severity and lane only.
- One issue per S1 and S2 finding, as thin pointers by class and fix: 31 in
  all (Batch 1: 12, Batch 2: 11, Batch 3: 8). Thirteen of them are held rows
  (Lane R: N-01, N-31; Lane C: N-07 to N-10; Lane B: N-11 to N-13; Lane I:
  N-14, N-15, N-18, N-19) and are filed with their fix, so adoption files 18
  (Batch 1: 6, Batch 2: 4, Batch 3: 8).
- The 62 S3 findings as lines on the polish lists (a row with no screen of its
  own under "Shell+global"), not as issues. Eleven are held rows (Lane G: N-78
  to N-84, N-90; Lane N: N-74; Lane D: N-35, N-93) and are added with their
  fix, which leaves 51; N-75 is already there as #1262 and N-41 as #1266, so
  adoption adds 49.
- ADR amendments: ADR-0050 for D-6; ADR-0045 for the note under N-64.
- Two ideas for the idea list, not for a batch: a booking that states both
  sides of a currency exchange (from D-2), and a warning when an import row's
  quantity times price is far from its amount (from D-3).

---

## Part 5 — Decided here, and what is not mine to decide

**Decided — the ordering.** Money rules first, because a wrong stored figure
is the one damage this system cannot undo by restarting, and the held S1
(N-01) with them; Lane C in the same batch, for the reason the private report
gives. News second. The rest third.

**Decided — severities.** The verifiers' severities stand, except five S2
that a second reader argued down to S3 and the audit lead agreed with (N-37,
N-44, N-51, N-57, N-58). No finding was raised.

**Decided — no exploit detail in public artifacts.** The rule follows from
`SECURITY.md` and needs no new decision.

**Decided — hardening is not new scope.** Every public row fixes behaviour the
requirements, an ADR or the handbook already promise. Under ADR-0036 it rides
a batch as risk-tier work and needs no scope gate; what it needs is the
closing act's dedicated verification pass, named above for Lane L, N-01 and
Lane M.

**Decided — one lock order.** News writers take the security before any news
lock, as AT4 already decided for the assignment. Lane K applies it; it is a
precision of an existing decision.

**Not mine: D-1, D-4 and D-5.** Held. Why each is the owner's is in the
private report.

**Not mine: D-2 and D-3.** How money data is booked, refused and corrected is
the owner's by AGENTS.md, and so is every correction of a row already stored
on the owner's instance. The review cannot see that instance and did not try.

**Not mine, but small: D-6 and D-7.** Each narrows or amends a signed ADR's
text, or picks between two reasonable defaults.
