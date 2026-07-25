# Adversarial Review — PRD Data Import & Sync (2026-06-21)

> Cynical review performed 2026-07-25 against `prd.md` (status: draft, mode:
> fast-path, unchanged since 2026-06-21). Reference set: `AGENTS.md`,
> `_bmad-output/project-context.md`, ADR-0021, ADR-0026, ADR-0027, ADR-0028,
> ADR-0029, ADR-0030, `_bmad-output/planning-artifacts/epics.md`, the
> authoritative PRD `prd-portfolixir-2026-06-12/prd.md`, and the current
> implementation (`lib/portfolixir/imports/applier.ex`,
> `lib/portfolixir/ledger/transaction.ex`, `lib/portfolixir_web/router.ex`,
> `mix.exs`). The document's own decision log was read as context only.

## Verdict

This PRD is a strategy memo wearing a requirements document's clothes. Its
central factual claim — that transaction-grade German-bank data is "locked in
PDFs" — is stated in §2 as "**The hard truth about source data**" and then
contradicted 100 lines later by its own OD-2, which asks someone to go
"**Verify empirically what comdirect actually exports as CSV**" and tags the
whole question `[ASSUMPTION]`. That unverified premise is not decoration: it is
the sole justification offered for ADR-0021, which has already been **Accepted**
and has already amended AGENTS.md to punch a hole in a hard rule. A PRD that
asserts as established fact the very thing its open-decisions section admits is
unverified has not done the cheapest, highest-leverage piece of work in the
document, and it shipped a permanent policy change on the strength of it. Worse,
the PRD never mentions that the authoritative PRD's own FR-17 already documents
"comdirect: depot positions **and transactions** via the official REST API" —
the option that would make Feature D unnecessary is not rejected, it is simply
absent from the analysis.

Below the strategy layer the requirements do not survive contact with the
codebase. Feature B (snapshot import) has no legal home in this system: holdings
are never stored (ADR-0004, project-context Don't-Miss rule #1), the kind set in
`Transaction.kinds/0` is closed and contains no positions-snapshot kind, and the
PRD's own FR-6 forbids the one remaining implementation (synthesized
deliveries) — three doors, all locked, and the PRD notices none of them while
FR-6 and FR-7 casually presuppose that snapshots persist. Feature A specifies
mapping at *column* level only, which cannot map a German broker's free-text
"Wertpapierkauf" onto a closed 15-kind set, and says nothing whatsoever about
decimal commas, thousands separators, `DD.MM.YYYY` dates, `;` delimiters, or
CP1252 encoding — i.e. every single property that a real German broker CSV is
guaranteed to have. FR-4 claims content-hash idempotency makes "re-import = no
dupes" while the actual `dedup_key/1` is computed over **resolved** entity ids,
so a corrected mapping silently duplicates the entire file. There are zero
acceptance criteria in the document, which means it cannot pass the ADR-0026
decision gate it would need to start an epic batch, and the `addendum.md` the
header promises as the home for all mechanism detail **does not exist**. Finally,
the document is a month stale: FR-14's PP-compatible export was killed by owner
decision on 2026-07-22, and ADR-0029 has since made an identity ladder,
preview→apply revalidation, and config-at-risk warnings binding on every import
path this PRD describes.

## Findings

### The PRD's founding premise is asserted as fact and admitted as unverified in the same document

**Severity:** critical
**Location:** § 2 Strategic context / § 6 OD-2

> "**The hard truth about source data (German banks, e.g. comdirect):** the only
> structured CSV export is an **IST/holdings snapshot** … Transaction-grade data
> … is **locked in PDFs**"

versus, in the same document:

> "**OD-2:** Verify empirically what comdirect actually exports as CSV (snapshot
> vs. any transaction substance) using a real, anonymized file … `[ASSUMPTION]`"

§2 uses the rhetoric of settled fact ("the hard truth") for a proposition that
§6 explicitly parks as unverified and tags `[ASSUMPTION]`. This is not a
harmless inconsistency of tone. This proposition is the *entire* load-bearing
argument for Feature D, and Feature D has already been converted into
**ADR-0021 (Accepted)**, which "**supersedes the AGENTS 'no broker PDF intake'
rule**" and has already amended `AGENTS.md`. The project therefore now carries a
permanently widened document-intake surface, a per-broker maintenance
obligation, and a pending new dependency, all justified by a premise nobody has
checked — where checking it costs one afternoon and one export click. If OD-2
comes back saying the CSV carries transaction substance (or that the broker's
API does, see the next finding), Feature D's cost/benefit inverts and ADR-0021
should have been Option B. §9 even ranks this verification as step 2 ("cheap,
decides A's reach") while the irreversible decision built on it was taken at
step 0.

**Fix:** Demote §2 from assertion to hypothesis — rewrite as "Working
hypothesis, unverified (OD-2): …" — and state plainly that ADR-0021 was accepted
before OD-2 was closed. Add an explicit re-open trigger to §6: "If OD-2 shows
comdirect exports transaction substance via CSV or its official API, ADR-0021's
Option A/B choice is re-litigated before the first Feature D story." Move OD-2
to step 1 of §9 and gate every Feature D story on it.

### The option that would make Feature D unnecessary is documented in the main PRD and never mentioned here

**Severity:** critical
**Location:** § 2 Strategic context / Feature D / § 4 Scope

> "Transaction-grade data — purchase price, shares & date, fees, taxes on sale,
> dividends — is **locked in PDFs**"

The authoritative PRD (`prd-portfolixir-2026-06-12`, status **final**) says
otherwise at FR-17: "**comdirect: depot positions and transactions via the
official REST API**; reconciliation against the existing ledger with preview
before apply." It is listed under Phase 3, which that PRD calls an
"**Operator-stated must-have** — the scope gate below governs *when and how*,
not *whether*."

So a documented, owner-committed path to exactly the data this PRD calls
PDF-locked already exists in the requirement corpus, and this PRD neither cites
it nor rejects it. Instead §4 disposes of it in a parenthetical — "**Out of
scope (unchanged policy unless noted):** live broker/bank sync" — describing as
"unchanged policy" something the authoritative PRD holds open as a committed
must-have behind an ADR gate. ADR-0021's options analysis inherits the blind
spot: it weighs only "A — In-app PDF parser" against "B — Out-of-app extraction
+ structured push", never "C — the official broker API the operator already
called a must-have". Consequence: the project may be about to build and
perpetually maintain a hostile-input PDF parser to recover data that an
authenticated REST endpoint returns as structured JSON. Note the two are not
equivalent for *historical* data (an API may not reach back far enough) — but
that is an argument the PRD has to *make*, not skip.

**Fix:** Add an explicit "Considered and rejected" subsection to §2 covering the
comdirect REST API (main-PRD FR-17), with the real reason — most plausibly
history depth and the PhotoTAN/unattended-session problem already logged as
main-PRD OQ-6. Reconcile §4's "unchanged policy" wording with the main PRD's
must-have framing, or state that this PRD is proposing to demote Phase 3. Fold
the result back into ADR-0021 as a third rejected option.

### Feature B has no legal representation in the ledger and contradicts itself

**Severity:** critical
**Location:** Feature B / FR-5, FR-6, FR-7

> "**FR-5** Import a positions snapshot (security + quantity, optional current
> value) into a portfolio/depot."
> "**FR-6** The UI clearly labels snapshot-sourced positions as **no cost basis /
> no P&L** and never silently fabricates transactions."
> "**FR-7** Snapshot can be used to **reconcile** against derived holdings…"

There are exactly three ways to implement FR-5, and this PRD forbids or ignores
all three:

1. **Store the positions.** Forbidden. Project-context Don't-Miss rule #1:
   "**Holdings are never stored** — derived from transactions (ADR-0004; no
   holdings table exists)."
2. **Synthesize `inbound_delivery` transactions.** Forbidden by FR-6's own
   "never silently fabricates transactions".
3. **Add a new ledger kind.** Unmentioned. `Transaction.kinds/0` is a closed
   15-element list (verified: 13 PP kinds + `balance_adjustment` + `split`) with
   no positions-snapshot member, and per ADR-0011 / project-context rule #2
   "Unknown kinds raise BY DESIGN". Adding one is an ADR-grade change to the
   projection reducer that this PRD does not request, scope, or acknowledge.

The one snapshot concept that exists is `balance_adjustment`, which ADR-0009
defines for **cash** balances only — it cannot carry a security quantity. The
adjacent `snapshot` term in ADR-0027 is a "**ledger marker, not a copy**" that
"copies **no** transactions, quantities, or prices" — the opposite of what FR-5
describes.

FR-6 and FR-7 then quietly assume the impossible thing happened: "snapshot-
sourced positions" presupposes a persisted position row carrying a provenance
attribute, and "reconcile against derived holdings … (expected vs. snapshot)"
presupposes the snapshot is durable enough to compare against later. Downstream,
an epic written from Feature B will discover on day one that its first story has
no data model, and the path of least resistance for an implementing agent is
exactly the forbidden holdings table.

**Fix:** Decide the representation *in this PRD* and add it as an open decision
with a recommendation. The only invariant-safe options are (a) a transient,
never-persisted reconcile input — which is precisely what ADR-0029 §6 has since
built as `POST /api/v1/holdings/reconcile`, "the list is **never persisted**",
making FR-7 largely redundant; or (b) an explicit, user-confirmed conversion of
snapshot rows into `inbound_delivery` transactions with no cost basis, which
requires deleting FR-6's "never fabricates" clause and stating the cost-basis
consequence (project-context rule #4: deliveries move quantity, not cost basis).
Pick one. Do not ship FR-5 as written.

### FR ids collide head-on with the authoritative PRD's stable global numbering

**Severity:** critical
**Location:** § 5 (all FRs) / § 8 Related issues

> "**FR-14** PP-compatible export so data can round-trip out (relates to #354),
> plus a native Portfolixir export format."

and, four lines later:

> "#355 / FR-14 (MCP write tools — Feature C)"

The authoritative PRD states the governing rule: "IDs are stable and **globally
numbered**; new requirements append, never renumber." Its FR-14 is "MCP tools
cover data maintenance (create/update records)". This PRD restarts at FR-1 and
collides across the whole range: its FR-1 (CSV upload) vs. main FR-1 (all state
derives from the ledger); its FR-5 (snapshot import) vs. main FR-5 (PP exports
import losslessly); its FR-7 (snapshot reconcile) vs. main FR-7 (import gaps
surfaced); its FR-11/FR-12 (PDF parsing) vs. main FR-11/FR-12 (allocation,
rebalancing guidance); its FR-13/FR-14 (backup, PP export) vs. main FR-13/FR-14
(analytics exposure, MCP writes).

This is not cosmetic. "FR-7" is cited across the live corpus in its *main-PRD*
meaning — ADR-0029 uses it repeatedly ("Leftovers are surfaced, never dropped
(FR-7)", "**Config-at-risk warning (FR-7)**") and `epics.md` maps FR ids to
issues in a single global table. A traceability matrix built from both documents
is now ambiguous for at least eight identifiers, and §8 of this very document
demonstrates the confusion by using FR-14 in both senses within four lines.

**Fix:** Renumber every requirement in this PRD into the global sequence
(continuing past the main PRD's highest allocated id — currently past FR-35 per
ADR-0029), or prefix them unambiguously (`FR-DI-1` …). Then fix §8's "#355 /
FR-14" and FR-8's "(relates to #355 / FR-14)" to name the main-PRD id
explicitly. Add a line to §5 stating which numbering authority governs.

### Feature A maps columns but never maps values — it cannot produce a transaction kind

**Severity:** critical
**Location:** Feature A / FR-1

> "**FR-1** … lets the user map each Portfolixir field (date, **type**, ISIN/
> WKN/name, shares, price, amount, fees, taxes, currency, account) to a source
> column."

Mapping the *type* field to a source column is necessary and nowhere near
sufficient. That column contains free text in the broker's language and
vocabulary — "Kauf", "Wertpapierkauf", "Verkauf", "Dividendengutschrift",
"Ertragsgutschrift", "Vorabpauschale", "Depotübertrag Eingang" — and it must
land on one of exactly 15 closed kinds (verified in `Transaction.kinds/0`) where
an unrecognised value **raises by design** (ADR-0011). Feature A as specified
gives the user no way to express "the string `Wertpapierkauf` means `buy`".
Without a per-value mapping table the feature cannot import a single row of any
real broker CSV, which is its entire purpose.

The same gap repeats structurally elsewhere in FR-1: "account" must map to a
depot *and* a cash account (a buy touches both — see the applier's
`securities_account_id` + `cash_account_id`), and "ISIN/WKN/name" is a security
*resolution* problem now governed by ADR-0029's identity ladder, not a column
assignment.

**Fix:** Split FR-1 into column mapping and **value mapping**: require a
per-source dictionary from distinct source values in the type column to
Portfolixir kinds, with unmapped values blocking apply and surfaced in preview
(never defaulted). Add a requirement that account mapping resolves depot and
cash account separately. Add a requirement that security resolution runs the
ADR-0029 §2 ladder with its ambiguity, veto, and config-at-risk rules.

### FR-4's idempotency claim is false for the cases that actually occur

**Severity:** critical
**Location:** Feature A / FR-4 (and Feature D / FR-11, Feature F / FR-15)

> "**FR-4** Apply is atomic with content-hash idempotency (re-import = no
> dupes)."

One sentence, no failure modes, and it misstates how the mechanism works.
Verified in `lib/portfolixir/imports/applier.ex`, idempotency is **two-layered**
(#533): a per-record `import_hash` "derived from its stable identity", *plus* a
formatting-tolerant `dedup_key/1` computed over the **resolved** database
identity — `portfolio_id`, `type`, `date`, `security_id`,
`securities_account_id`, `cash_account_id`, normalized Decimals. ADR-0029 §5
calls this two-layer property "load-bearing".

Because layer two keys on *resolved* ids, the PRD's own Feature A breaks it in
the ordinary case: **a user who corrects a mapping and re-imports the same file
changes the resolved ids, changes both the hash and the dedup key, and silently
duplicates every row.** That is not an exotic edge case — it is the expected
second action of any user of a mapping UI, and FR-2's savable mappings make
re-import with an edited mapping the designed workflow. The PRD also never
addresses: a *partially overlapping* re-import (an export covering an
overlapping date range), a *corrected* export where the broker restated one
row's fee (old row stays, corrected row inserts — silent double-booking), or
what the hash covers for a PDF (FR-11) where re-downloading the same statement
yields different bytes but identical economics.

FR-15 compounds this: "**A single invalid record … never aborts the whole atomic
import**; invalid rows … can be skipped". A partial apply means the next import
of the same file legitimately must insert the previously-skipped rows — so
file-level "already imported" short-circuits are wrong, and the PRD says nothing
about how skip decisions are remembered or re-offered.

AGENTS.md classes exactly this as a risk tier: "anything touching import
idempotency or projection semantics" gets "dedicated small PRs with real human
review". A one-line parenthetical is not a specification for a risk-tier
invariant.

**Fix:** Replace FR-4 with explicit semantics: state that idempotency is
two-layered (content hash + resolved dedup key, #533), and add requirements for
(a) re-import after a mapping change — the preview must show which rows would
newly insert *because* resolution changed, and require explicit confirmation;
(b) partially overlapping re-import — only non-duplicate rows insert, duplicates
reported as `skipped_duplicates`; (c) corrected rows — a changed value produces
a *conflict* surfaced in preview, not a silent second booking; (d) PDF intake —
hash over extracted economic records, never over file bytes. Add ADR-0029's
preview→apply revalidation as a requirement.

### § 4's out-of-scope wording silently widens the document-intake exception to binary `.portfolio`

**Severity:** high
**Location:** § 4 Scope

> "**Out of scope (unchanged policy unless noted):** … `[ASSUMPTION]` multi-user
> and **non-PP non-PDF document formats** remain out for now."

Scope defined by complement, on an `[ASSUMPTION]` tag, against a hard rule. Read
literally: everything that *is* a PP format, and everything that *is* a PDF, is
in scope. That silently pulls in the two things both governing documents
explicitly keep out. ADR-0021: "**Binary `.portfolio` workspace intake remains
out of scope**; PP XML stays tracked separately (#333)." AGENTS.md: "binary
`.portfolio` intake stays out of scope", and its forbidden list still names "PP
XML" as document intake requiring a reviewed scope change.

The PRD then acts on its own widened reading at FR-16 — "`[ASSUMPTION]` Evaluate
PP XML full import (#333)" — placed inside Feature F with no mention that the
main PRD attaches a **scope gate** to exactly this ("XML intake requires the
AGENTS.md amendment + ADR (it is on the current forbidden list)"). An agent
reading this PRD alone would conclude PP XML and `.portfolio` intake are
permitted.

**Fix:** State scope positively, not by complement. List in-scope intake formats
explicitly (PP CSV/JSON v1; delimited broker CSV per Feature A; broker PDFs per
ADR-0021), and list out-of-scope ones explicitly (binary `.portfolio` — hard
out; PP XML — gated on ADR + AGENTS.md amendment, #333). Remove the
`[ASSUMPTION]` tag from a scope boundary; scope is decided or it is an open
decision, never an inference.

### Feature C opens an unauthenticated-by-design instance's bulk write path with no audit, authorization, or validation story

**Severity:** high
**Location:** Feature C / FR-8, FR-9, FR-10

> "**FR-10** Bulk/batch create endpoint so a parsed PDF's many rows post in one
> auditable call. `[ASSUMPTION]`"

"Auditable" is asserted and never specified. The word the PRD needs is the audit
journal — ADR-0017, main-PRD FR-28 — whose stated purpose is precisely this
threat: "so a **hallucinated or erroneous agent edit** is always detectable and
attributable." Feature C is the highest-risk write path in the document (an LLM,
posting hundreds of financial rows at once, from PDF text extraction of unknown
fidelity) and it never once names the journal. `epics.md` even fixes the
ordering — "Sequence #353 before #355 (MCP writes must be journaled)" — which
this PRD's §9 phasing ignores by putting Feature C at step 3 with no dependency
on #353.

Authorization is equally absent. Project-context: API routes sit "behind
`ApiAuthPlug` (bearer token from `:api_token` app env)" — a **single shared
token**, no scopes, no per-actor identity; and the main PRD's NFR-4 records that
"**The web UI itself is unauthenticated by design**". FR-8's "Every transaction
kind creatable in the UI is creatable via the JSON API" therefore grants any
holder of the one token — or anyone on the network — full ledger write. The PRD
does not say whether that is acceptable, whether writes need a distinct token,
or how the journal distinguishes actors.

Validation is asserted by omission: FR-8 says every kind is creatable but never
says API creation enforces the same changeset invariants as the UI (positive
magnitudes, ADR-0015 cross-currency `settlement_fx_rate`, currency consistency).

FR-9's "idempotency keys supported to make pushes safe to retry" introduces a
**second, incompatible idempotency mechanism** alongside the content-hash one,
with no statement of precedence, storage, TTL, or behaviour when the same key
arrives with a different body. Two idempotency systems that do not know about
each other is how double-booked ledgers happen.

**Fix:** Add explicit requirements to Feature C: (1) every API/MCP write is
journaled per ADR-0017 with actor recorded, and Feature C depends on #353;
(2) API writes run the identical changeset validations as the UI path — state
this as a testable requirement; (3) define the write authorization model, or
record it as an open decision referencing NFR-4/OQ-8; (4) specify how FR-9's
idempotency keys relate to content-hash idempotency (recommend: keys dedupe the
*request*, content hash dedupes the *records*, and both must hold); (5) specify
FR-10's partial-failure semantics (all-or-nothing, with per-row errors returned)
and adopt ADR-0029's rule that non-interactive paths **fail closed** —
unresolvable entries "are reported as unresolved (FR-7) and are resolvable only
via explicit per-entry mappings in the request — never auto-created, never
auto-matched".

### Feature A ignores every property a real German broker CSV actually has

**Severity:** high
**Location:** Feature A / FR-1, FR-3

> "**FR-1** User uploads **any delimited file**; the app previews detected
> columns/rows…"

"Any delimited file" is the whole specification of parsing. Absent: decimal
separator (`1.234,56` — and `Decimal.new/1` on that string raises, per
project-context), thousands separator, date format (`31.12.2025` vs ISO),
character encoding (German bank exports are routinely CP1252/ISO-8859-1, not
UTF-8 — mis-decoding silently corrupts security names, which are a matching tier
in ADR-0029), delimiter detection (`;` is the German default because the comma
is the decimal mark), preamble/junk lines before the header row, quoted fields
containing the delimiter, and negative-signed amounts.

That last one is a direct invariant collision. Project-context Don't-Miss rule
#3: "**Amounts are positive magnitudes — the sign comes from the kind**"
(enforced by `validate_number ... > 0`), and "PP exports with signed values are
**normalized at import**". Broker CSVs carry signed amounts. FR-1 offers a
column mapping and no normalization rule, so every sell/withdrawal row either
fails the changeset or is stored with a forbidden sign. The PRD never mentions
sign normalization for Feature A at all.

Note that the escape hatch used elsewhere is unavailable here: ADR-0029 §6 could
declare "canonical dot-decimal Decimal strings (any other format is a 422 —
**locale parsing is the client's job**)" because that is an API with a client.
For a *file upload* there is no client to delegate to; the app must parse the
locale format or Feature A imports nothing.

**Fix:** Add requirements for a per-source format profile — encoding, delimiter,
quote char, decimal and thousands separators, date format, header row offset —
detected with a preview and user-overridable, saved alongside the FR-2 mapping.
Add an explicit sign-normalization requirement mirroring the PP importer's.
Require the preview to show parsed Decimal values so a mis-detected separator is
visible before apply, and require ambiguous parses to block rather than guess.

### Feature D drops the binding constraints ADR-0021 imposed and calls an undefined thing "sandboxed"

**Severity:** high
**Location:** Feature D / FR-11, FR-12a, dependency note

> "**FR-12a** Parsing is sandboxed and text-only: no script/JS execution, no
> embedded-object evaluation, no content-triggered network; size/page/time
> limits; malformed/oversized input rejected safely."

Feature D correctly inherits ADR-0021's per-broker rule and preview-then-confirm
rule, so it does not *widen* the exception on those axes. It drops two others.
ADR-0021 requires parsed records to go through "an **atomic, content-hash-
idempotent** apply, **recorded in the audit journal (ADR-0017)**" — FR-11
mentions the preview but neither idempotency nor the journal. It also imposes an
ongoing obligation the PRD omits: "security review must cover the parser
(Sobelow/manual) on every change."

The security posture is asserted, not analysed. "Sandboxed" appears twice and is
never defined — same BEAM process, separate OS process, separate container, with
what privileges? Elixir provides no process sandbox, so this word is currently
doing work no mechanism backs. The named threats are the *easy* ones
(script/JS/embedded objects); the ones that actually kill PDF parsers are
missing: decompression bombs (a 2 KB stream inflating to gigabytes), XRef and
object-reference cycles, recursion depth, malformed length fields, and memory
exhaustion — "size/page/time limits" with no numbers covers none of these
testably. Sobelow is a Phoenix-focused static analyzer; nominating it as the
control for a binary-format parser is category error.

The dependency is hand-waved: "**a pure PDF text-extraction library** is a
reviewed dependency decision (no rendering/scripting)". Verified: `mix.exs`
contains no PDF dependency, and no candidate is named anywhere. In Elixir the
realistic options are a thin wrapper that shells out to `pdftotext`/poppler —
an **external binary invocation**, a materially different and worse security
posture than "a library", and one that makes "sandboxed" a container/OS
question rather than a BEAM question. Project-context also forbids the
implementation path the phasing implies: "Agents must **NOT** bump **or add**
dependencies while implementing a story", so Feature D needs a dedicated
dependency PR that §9 does not schedule.

**Fix:** Add to Feature D: (a) an explicit requirement that PDF-derived records
are journaled (ADR-0017) and idempotent over *extracted economic records*, not
file bytes; (b) a definition of "sandboxed" naming the actual isolation boundary
(recommend: separate OS process, no network namespace, memory and wall-clock
rlimits, hard page cap) with **numeric** limits so FR-12a is testable; (c) the
missing threat classes (decompression bomb, reference cycles, recursion depth,
memory exhaustion) as named rejection cases with malformed synthetic fixtures;
(d) the candidate library or binary named, with the shell-out case addressed;
(e) restate ADR-0021's per-change security-review obligation. Schedule the
dependency decision as its own PR in §9 before any Feature D story.

### FR-14 requires an export the owner cancelled a month ago

**Severity:** high
**Location:** Feature E / FR-14

> "**FR-14** PP-compatible export so data can round-trip out (relates to #354),
> plus a native Portfolixir export format. `[ASSUMPTION]`"

Superseded. `epics.md` records: "**Rescoped 2026-07-22 (owner decision):** the
PP-compatible export is **dropped** — Portfolixir is a one-way import
destination; backup/restore = documented `pg_dump` … data egress for external
consumers = the JSON API (#354)." ADR-0029 relies on that rescope structurally:
its whole rejection of a strategy-config export format rests on "FR-29's
documented `pg_dump` backup (rescoped 2026-07-22) — which removes the last
argument for a config-export format", and it notes "ADR-0029's former 'FR-29
native export' references were amended".

This PRD is still `status: draft`, still `updated: 2026-06-21`, and still
carries the cancelled requirement as its "true 'leave PP' milestone" (§9 step
6). Anyone building an epic from this document builds a dead feature. The same
staleness makes FR-13's "Full backup/restore of all financial data" wrong in
kind — the decided answer is a documented `pg_dump` procedure, not an
application feature.

**Fix:** Replace FR-13/FR-14 with the rescoped FR-29: documented `pg_dump`
backup/restore; PP-compatible export dropped; data egress via the JSON API.
Delete the "native Portfolixir export format" assumption or raise it as a fresh
open decision. Then re-examine §9 step 6 — with PP export dropped, the "leave
PP" milestone no longer exists as phrased.

### The PRD predates ADR-0029 and describes import paths that violate it

**Severity:** high
**Location:** Features A, B, C, D (all import paths)

ADR-0029 (Accepted, owner sign-off 2026-07-22) makes several rules binding on
**every** import path, none of which appear here:

- The security identity ladder (ISIN → alias → WKN → ticker+currency →
  name+currency), each tier applying "only when it selects **exactly one**
  candidate", with a stronger-identifier veto — "a contradicted match … [is]
  surfaced as conflicts … never accepted silently."
- "**Preview→apply revalidation:** apply re-runs the ladder inside the import
  transaction and aborts back to the preview whenever any entry's resolution …
  differs from what was approved — previews live for up to two hours; consent
  must not go stale."
- The **config-at-risk** warning and per-row acknowledgment protecting stored
  category assignments and ADR-0030 position targets.
- The **pre-apply inverse check** listing config-bearing securities matching
  zero entries.
- "**Non-interactive paths fail closed**" — directly governing this PRD's
  Feature C.

This PRD's FR-3 offers only "Preview shows the records that would be created and
flags rows that fail validation **before** any atomic apply", which is a strictly
weaker contract. A Feature A or Feature D importer built to FR-3 will silently
duplicate securities and strand the classification/target configuration that
ADR-0029 exists to protect. ADR-0029 also corrects a premise Feature C leans on:
"there is no `/api/v1` imports route" (verified — `router.ex` exposes only the
`ImportsLive` view).

**Fix:** Add a cross-cutting requirement — every intake path in this PRD
(Features A, B, C, D) resolves securities through the ADR-0029 §2 ladder and
inherits preview→apply revalidation, config-at-risk acknowledgment, the inverse
check, and fail-closed behaviour for non-interactive paths. Bump `updated:`,
and add ADR-0029/ADR-0030 to the reference list.

### The document has no acceptance criteria, so it cannot pass its own decision gate

**Severity:** high
**Location:** whole document / § 5

Seventeen FRs, not one acceptance criterion, not one number, not one testable
threshold. AGENTS.md's ADR-0026 epic-batch workflow opens with: "**Decision
gate:** an ADR or spec **with acceptance criteria**, signed off by the owner
before the batch starts." AGENTS.md's testing contract further requires each
user-visible story to carry a user-story comment plus explicit acceptance
criteria in the test file. §9 nonetheless lays out a seven-step build order as
if the document were ready to execute.

Compounding this, the header promises the missing detail lives elsewhere —
"Capabilities only; mechanism/tech notes live in `addendum.md`" — and
**`addendum.md` does not exist** in this folder (verified: the directory
contains only `prd.md` and `.decision-log.md`). Every mechanism question raised
in this review is routed to a file that was never written. The 2026-06-12 PRD
folder does have an `addendum.md`; this one does not.

**Fix:** Either write `addendum.md` and move the mechanism decisions there, or
delete the pointer and inline them. Add acceptance criteria to every FR intended
for the next batch — minimally FR-1..FR-4 and FR-11/12a — expressed as
observable outcomes on synthetic fixtures. Until then mark the document
explicitly "not decision-gate ready" so nobody starts an epic from it.

### The PRD reverts the main PRD's deliberate anonymization and asks for a real bank file

**Severity:** high
**Location:** frontmatter / § 3 Users / § 6 OD-2 / FR-11

> "**Primary:** a single self-hosting investor (**Andi**) migrating an existing
> PP history"

> "**OD-2:** … using a **real, anonymized file**"

This is a public repository. AGENTS.md forbids committing "**The maintainer's
personal banking relationships**: which banks/brokers hold their accounts" and
requires "generic placeholders … in examples and fixtures". The authoritative
PRD deliberately complies — its persona is "the operator-investor (**'Alex' —
fictional persona name**)". This PRD discards that: it names the real maintainer
in both the frontmatter (`owner: Andi`) and §3, names comdirect as the concrete
first broker in FR-11 and OD-2, and then asks for "a real, anonymized file" from
that broker. The chain "the primary user is Andi" + "verify what comdirect
exports using a real file" attaches a named banking relationship to an
identified person, which is exactly the rule's target. Naming comdirect
generically ("a comdirect CSV export looks like …") is fine; this is not
generic.

There is also an unguarded instruction. FR-12b correctly says "synthetic
fixtures only, **never real statements**", but OD-2 asks someone to obtain a
real export and gives no instruction on where it may live. That is an
invitation to commit a real bank file.

**Fix:** Replace `owner: Andi` and §3's name with the established fictional
persona ("Alex") or a role ("the operator-investor"), matching the main PRD.
Rewrite OD-2 to drop the identity link — "verify what a typical German-bank CSV
export contains" — and add an explicit handling rule: the verification file is
inspected locally, never committed, and only a synthetic fixture derived from
its *structure* enters the repository.

### Success metrics and the counter-metric are unmeasurable as written

**Severity:** medium
**Location:** § 7 Success metrics & counter-metrics

> "**Counter-metric CM-1** Imports that **silently** produce wrong/incomplete
> data … → must trend to zero"

A counter-metric that counts *silent* failures is unmeasurable by construction:
if the failure were observable it would not be silent, and there is no proposed
detector, sampling procedure, or reconciliation baseline. It cannot trend
anywhere because it cannot be read.

> "**SM-1** A new user can load a full transaction history and reach **correct**
> holdings … for at least one **real** broker."

No oracle for "correct" (correct against the broker's own statement? against a
PP import of the same period?), and "real broker" cannot be exercised in CI —
AGENTS.md mandates "synthetic fixtures only" and "no external network calls in
tests". So SM-1 is verifiable exactly once, manually, by the one person who has
the account.

> "**SM-2** Time-to-first-correct-portfolio for a new user (lower is better)."

No baseline, no target, no instrument, no definition of the start and stop
events — and with a stated user population of one, any measurement is a single
anecdote.

**Fix:** Give SM-1 an oracle: "a synthetic broker CSV/PDF fixture pair imports
to holdings matching a checked-in Decimal-exact expectation" — which is testable
in CI and mirrors the existing golden-master approach in the quality-gate
roadmap. Give SM-2 a baseline and target or cut it. Replace CM-1 with something
observable: e.g. "every import applies zero rows that failed validation", "each
confirmed wrong-number incident becomes an invariant test" (the main PRD's
formulation), and a reconciliation count from the ADR-0029 §6 endpoint.

### OD-1 exists in three contradictory states inside one document

**Severity:** medium
**Location:** § 2 / Feature D heading / § 6 OD-1 / § 9 step 4

> § 2: "the AGENTS 'no PDF intake' policy is **under review** — in-app PDF
> parsing is now a **candidate** capability"
> Feature D: "**(DECIDED — ADR-0021)** … **Decided** in ADR-0021 (Option A)"
> § 6: "**OD-1 — RESOLVED** (2026-06-21, ADR-0021) … Feature D is now decided,
> not a candidate."
> § 9: "4. **Resolve OD-1**, then either Feature D (in-app PDF) or double down
> on C."

Three states for one decision: under review, decided, and scheduled-to-be-
decided. §6 explicitly corrects §2 and §9 without editing them. The phasing
sketch — the section an epic planner reads — still branches on a resolved
decision, so a planner may legitimately schedule a decision meeting for
something already recorded in an Accepted ADR that has already amended
AGENTS.md.

**Fix:** Rewrite §2's third bullet to past tense pointing at ADR-0021, and
rewrite §9 step 4 as "Feature D (in-app PDF) per ADR-0021 — gated on OD-2".
Keep OD-1 in §6 as a resolved record.

### FR-12 is tagged as an unconfirmed assumption although ADR-0021 already decided it

**Severity:** medium
**Location:** Feature D / FR-12

> "**FR-12** `[ASSUMPTION]` Parse a dividend/tax statement into dividend + tax
> records."

ADR-0021 decided this: "Start with **one broker** (comdirect Wertpapierabrechnung
**+ Steuerreport**)". The Steuerreport is the tax statement, and it is inside
the first broker's committed scope. Marking it `[ASSUMPTION]` misrepresents a
recorded decision as an open question and invites an implementer to drop it — at
which point Feature D delivers trades only, and the dividends and taxes that §2
named as the PDF-locked data ("fees, taxes on sale, dividends") never arrive.
Feature D would then not solve the problem the PRD created it for.

**Fix:** Drop the `[ASSUMPTION]` tag, cite ADR-0021's first-broker scope, and
state which of the two document types ships first. If the intent is genuinely to
defer the tax statement, that is a *narrowing* of an accepted ADR and belongs in
§6 as an open decision with its consequence stated.

### FR-15's partial-apply requirement contradicts the atomicity it claims to preserve

**Severity:** medium
**Location:** Feature F / FR-15

> "**FR-15** A single invalid record (e.g. zero-amount tax/delivery) never
> aborts the whole **atomic** import; invalid rows are surfaced in preview with
> reasons and **can be skipped** (#482)."

"Atomic" and "some rows are skipped" are reconcilable — one transaction commits
the valid subset — but only if the PRD says so, and it does not. Nor does it say
what happens next: are skipped rows remembered? Does re-importing the same file
after fixing the source re-offer them, and how does that interact with FR-4's
"re-import = no dupes"? Is skipping a per-row user decision in the preview or an
automatic policy? Is a zero-amount tax record *invalid* at all, or is that a
validation bug to fix rather than a row to skip — the example given
("zero-amount tax/delivery") reads more like the latter.

**Fix:** State that apply commits the approved subset in one transaction and
that skipped rows are recorded in the import result. Specify that a later
re-import re-evaluates skipped rows against the dedup key (so corrected rows
insert, unchanged ones stay skipped). Separate "invalid data the user must fix"
from "records Portfolixir wrongly rejects" — the zero-amount case belongs in the
second bucket and is a validation fix, not a skip feature.

### The PRD has no non-functional requirements, though the decision log claims it does

**Severity:** medium
**Location:** whole document / § 5

The decision log states: "Constraints unchanged: no broker/bank live sync, no
external LLM calls from the app, Decimal for money. → PRD §4, **NFR-equivalent
notes**." There are no NFR-equivalent notes. §4 mentions two of the three
constraints in a parenthetical and never mentions Decimal at all — in a PRD
whose entire subject is getting numbers into a ledger, from sources that format
numbers differently, where project-context warns that `Decimal.new/1` raises on
floats and that comparisons must use `Decimal.compare/2`.

Also absent: any file-size or row-count limit for uploads, any statement of
where uploaded files are stored or whether they are deleted after apply (a
Wertpapierabrechnung is sensitive personal data sitting on disk), and any
performance expectation, despite main-PRD NFR-8's "p95 < 2 s … tens of thousands
of transactions" — which a preview rendering a full import would violate.

**Fix:** Add a short NFR section: Decimal-only parsing and persistence with no
float intermediate; upload size and row-count limits; retention and deletion
policy for uploaded source files; preview performance expectation (paginated
preview at realistic scale); and the security boundaries restated from
AGENTS.md.

### Feature G is a requirement that states it is not a requirement

**Severity:** low
**Location:** Feature G / FR-17

> "**FR-17** Quote sync (prices) and FX-rate sync run automatically; this PRD
> only notes robustness follow-ups (rate-limit/backoff, provider coverage),
> **not new scope**."

An FR id with no requirement, no acceptance criterion, and an explicit
disclaimer that nothing is being asked for. It consumes an identifier, appears
in traceability tooling as unimplemented, and hides two genuine questions
(backoff policy, provider coverage) behind a "not new scope" label instead of
listing them as follow-up notes per AGENTS.md's scope-lock instruction.

**Fix:** Delete FR-17 and move the two robustness items into a "Follow-up notes
(not in scope)" subsection, or promote them to real FRs with criteria. Do not
spend an FR id on a non-requirement.

## Assumption audit

| # | `[ASSUMPTION]` | Location | Load-bearing? | What breaks if false |
|---|---|---|---|---|
| 1 | "solo/local, no multi-user" | § 3 Users | **No** — mislabeled | Nothing: the main PRD already decides this as **NFR-6** ("Single-user tenancy: one instance, one operator"). Tagging a decided NFR as an unconfirmed assumption weakens a settled constraint and invites an implementer to design for multi-tenancy. |
| 2 | "multi-user and **non-PP non-PDF document formats** remain out for now" | § 4 Scope | **Yes** | Scope is defined by complement, so the assumption *is* the scope boundary. If read as written, binary `.portfolio` and PP XML intake become in-scope — contradicting ADR-0021 ("binary `.portfolio` workspace intake remains out of scope") and AGENTS.md's forbidden list. An agent building from this PRD alone would believe both are permitted. |
| 3 | "Mappings are reusable/savable per source" (FR-2) | Feature A | **Yes** | Saved mappings are the mechanism by which a corrected mapping gets re-applied to a previously imported file — the exact case that breaks the resolved-id dedup key and silently duplicates rows. If saved mappings are dropped (OD-3 says "MVP or later?"), Feature A requires full manual re-mapping on every import, which for an ongoing workflow is a usability failure that pushes the user back to PP. Either way the answer changes the data model *and* the idempotency contract. |
| 4 | "Snapshot can be used to **reconcile** against derived holdings and surface drift" (FR-7) | Feature B | **Yes** | This is Feature B's only stated *ongoing* value (FR-5/FR-6 alone give a one-time seed with no cost basis). It presupposes the snapshot persists, which collides with ADR-0004's never-store-holdings invariant. It has also been overtaken: ADR-0029 §6 built `POST /api/v1/holdings/reconcile` where the external list "is **never persisted**". If false or superseded, Feature B collapses to a one-shot seeding function of marginal value and should probably be cut. |
| 5 | "Bulk/batch create endpoint so a parsed PDF's many rows post in one auditable call" (FR-10) | Feature C | **Yes** | Feature C's stated purpose is "so that a PDF can be parsed *outside* the app and the result posted in". Without a batch endpoint, posting a 200-row statement is 200 unrelated calls with no shared transaction, no atomicity, and no single audit record — so a mid-sequence failure leaves a half-booked statement. FR-9's idempotency keys are the only stated recovery mechanism and they are themselves unspecified. |
| 6 | "Parse a dividend/tax statement into dividend + tax records" (FR-12) | Feature D | **Yes** | Already **decided** by ADR-0021 (first broker = "comdirect Wertpapierabrechnung + **Steuerreport**"), so the tag misrepresents a recorded decision. If an implementer honours the tag and defers it, Feature D delivers buy/sell only and never recovers the dividends and taxes that §2 names as the PDF-locked data — Feature D then fails to solve the problem that justified overriding a hard rule. |
| 7 | "plus a native Portfolixir export format" (FR-14) | Feature E | **Yes** | Already overtaken: owner decision 2026-07-22 (#354) dropped the PP-compatible export and set backup/restore to documented `pg_dump`, with "data egress for external consumers = the JSON API". ADR-0029 depends structurally on that rescope. If built as written, the team ships a second serialization format to version and round-trip-test that the owner has explicitly declined. |
| 8 | "Evaluate PP XML full import (#333)" (FR-16) | Feature F | **Yes (scope legality)** | PP XML intake is on AGENTS.md's forbidden document-intake list, and the main PRD attaches a scope gate: "XML intake **requires the AGENTS.md amendment + ADR**". Presenting it as an assumption inside a Feature rather than as a gated open decision means an agent could start implementation without the amendment — a hard-rule violation. |
| 9 | "Verify empirically what comdirect actually exports as CSV" (OD-2) | § 6 | **Yes — the critical one** | This is the evidence base for §2, for Feature A's reach, for Feature B's existence, and above all for **ADR-0021**, which has already been Accepted and has already amended AGENTS.md. If the CSV (or the official REST API the main PRD's FR-17 documents) carries transaction substance, the cost/benefit that selected Option A over Option B inverts, and the project has taken on a hostile-input parser, a new dependency, and per-broker maintenance for nothing. |

**Load-bearing and unconfirmed: 7 of 9** (#2, #3, #4, #5, #6, #7, #9), plus #8
load-bearing for scope legality. Two of the load-bearing set (#6, #7) are not
assumptions at all — they are decisions the PRD misreports, one understating a
commitment and one ignoring a cancellation.

## Mechanical notes

- **`addendum.md` does not exist.** The header states "mechanism/tech notes live
  in `addendum.md`"; the folder contains only `prd.md` and `.decision-log.md`.
  The 2026-06-12 PRD folder does have one — this pointer appears to be
  copy-paste from the template.
- **FR-14 is defined twice with different meanings** — Feature E's FR-14
  (PP-compatible export) and §8's "#355 / FR-14 (MCP write tools — Feature C)",
  four lines apart. FR-8's "(relates to #355 / FR-14)" has the same problem.
- **Frontmatter is stale:** `status: draft`, `updated: 2026-06-21`. At least five
  Accepted ADRs affecting this PRD's subject matter have landed since
  (ADR-0027, ADR-0028, ADR-0029, ADR-0030, ADR-0031), plus the 2026-07-22 FR-29
  rescope. Either update or mark superseded.
- **The kind set is 15, not 13.** The PRD inherits the "13 PP kinds" framing from
  older documents; `Transaction.kinds/0` now contains 15 (13 PP kinds +
  `balance_adjustment` + `split` per ADR-0028). Any mapping UI enumerating kinds
  must cover `split`, which has entirely different field semantics (ratio only,
  all cash/price/quantity fields blank).
- **§ 8 lists issues without stating their contribution** — "#416 (data epic),
  #419 (LLM/MCP epic)" are epic pointers with no indication of which FRs they
  carry. `epics.md` already holds an FR→issue table; reference it instead.
- **FR-3's "(ties to #482)" and FR-15's "(#482)"** point at the same issue for
  two different requirements without distinguishing them.
- **No glossary or reference section.** The document uses PP, IST, SOLL,
  Wertpapierabrechnung, Steuerreport, and WKN without definition, and cites
  ADR-0021 without a link; the main PRD carries a glossary that this one could
  reference in one line.
- **"already built" (Feature G)** is the only verified-true capability claim in
  the document (quote and FX sync exist, with fakes registered in
  `config/test.exs`) — and it is the one requirement that asks for nothing.
- **`priv/static` upload handling is unmentioned.** Feature A and Feature D both
  accept file uploads; project-context notes filesystem-state tests require
  `async: false`, which the test strategy for these features will need to
  account for.
