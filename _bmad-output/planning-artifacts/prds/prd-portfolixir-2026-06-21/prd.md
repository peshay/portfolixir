---
title: "PRD — Data Import & Sync"
project: portfolixir
status: draft
created: 2026-06-21
updated: 2026-07-25
owner: Andi
mode: fast-path
---

# PRD — Data Import & Sync

> Focused PRD for the intake domain. Capabilities only; mechanism and tech
> notes live in `addendum.md`. `[ASSUMPTION]` marks inferred items still to be
> confirmed — every one of them is listed in §6 with what breaks if it is
> wrong.
>
> **Numbering.** Requirements here use the `FR-DI-n` prefix. The global
> `FR-n` sequence belongs to the authoritative corpus (the founding PRD plus
> `epics.md`, which is the live registry); an unprefixed `FR-7` in any ADR or
> issue means *that* FR, never one of these. Cross-references to global ids are
> written out in full.
>
> **Reference set.** ADR-0021 (broker-PDF exception), ADR-0026 (epic batches),
> ADR-0027 (snapshot markers), ADR-0028 (split kind), ADR-0029 (import identity
> ladder — binding on every path below), ADR-0030 (position targets), ADR-0031
> (tax parameters). Terms not defined here are in the founding PRD's glossary.

## 1. Problem & Goal

Portfolixir's value is an auditable local record of holdings derived from
transaction history. Today the only practical way to load real history is via
**Portfolio Performance (PP)** CSV/JSON v1 — Portfolixir rides on PP's export.
That makes PP a hard dependency.

**Goal:** make Portfolixir self-sufficient for getting transaction-grade data
in, so a user can adopt it without PP and eventually migrate off PP entirely —
while staying a local, auditable, decimal-correct tool.

## 2. Strategic context

- **PP is a migration bridge, not the destination.** Long-term we replace it.

- **Working hypothesis about German-bank source data, unverified (OD-2):**
  the only structured CSV export offered by a typical German bank is an
  **IST/holdings snapshot** (positions + current value), and transaction-grade
  data — purchase price, shares & date, fees, taxes on sale, dividends — is
  reachable only from PDFs (Wertpapierabrechnung, Steuerreport). If that holds,
  a generic CSV mapper cannot replace PP for such banks and only helps brokers
  that export structured trades (IBKR Flex, Trade Republic, Scalable).

  **This is a hypothesis, not an established fact, and it is load-bearing.**
  It is the sole justification offered for Feature D — and ADR-0021 was
  *accepted*, and AGENTS.md *amended*, before OD-2 was closed. Verifying it
  costs one export click and an afternoon. See the re-open trigger in §6.

- **Considered and not chosen: the official broker REST API.** The founding
  PRD's FR-17 already commits to "comdirect: depot positions **and
  transactions** via the official REST API" as an operator-stated must-have,
  gated behind the Phase 3 sync ADR. ADR-0021 weighed only in-app parsing (A)
  against out-of-app extraction and push (B); it did not weigh the API. The
  arguments for still doing PDF intake:
  - **History depth.** An API is unlikely to reach back far enough to
    reconstruct a full transaction history; PDFs of old statements do.
    `[ASSUMPTION]` — part of OD-2.
  - **Unattended operation.** PhotoTAN may force interactive sessions
    (founding PRD OQ-6), so an API path may not run unattended.
  - **Gate timing.** The API sits behind the Phase 3 hard gate, which also
    requires built-in web-UI auth (founding PRD OQ-8); PDF intake does not.

  These are arguments, not yet evidence. If OD-2 shows the CSV or the official
  API carries transaction substance, the cost/benefit that selected Option A
  inverts and the choice is re-litigated.

- **Owner decision, recorded:** in-app broker-PDF intake is **adopted**
  (ADR-0021, Accepted 2026-06-21, Option A), sandboxed / text-extraction-only /
  per-broker / preview-then-confirm. Feature D is decided, not a candidate.

## 3. Users & context

- **Primary:** the operator (Andi), a single self-hosting investor migrating an
  existing PP history and then maintaining it. Single-user tenancy is **not an
  assumption** — it is decided as NFR-6 in the founding PRD.
- **Secondary:** an **LLM/automation agent** acting on the operator's behalf
  via the JSON API / MCP — a first-class intake actor, in line with the
  LLM-first direction, and the highest-risk write path in this document.

## 4. Scope

Scope is stated positively. Anything not listed as in scope is out.

**In scope — intake formats:**

- PP CSV/JSON v1 (shipped; the standing AGENTS.md exception)
- delimited broker CSV via user-defined mapping (Feature A)
- broker PDFs, per-broker, per ADR-0021 (Feature D)
- an external position list submitted for reconciliation, never stored
  (Feature B)

**In scope — other:** API/MCP write parity (Feature C), documented
backup/restore (Feature E), PP-import hardening (Feature F).

**Out of scope:**

- **binary `.portfolio` workspace intake — hard out**, permanently
  (ADR-0021, AGENTS.md)
- **PP XML — gated**, requires ADR + AGENTS.md amendment before any
  implementation work (#333; founding PRD OQ-1a)
- live broker/bank sync, trading, orders, payments (founding PRD Phase 3
  governs sync separately)
- external LLM calls *from the app*
- multi-user

## 5. Capabilities & Requirements

Every requirement carries acceptance criteria, expressed as observable
outcomes on synthetic fixtures. ADR-0026's decision gate requires them before
an epic batch can start.

### Cross-cutting — ADR-0029 conformance

- **FR-DI-19** Every intake path in this document (Features A, B, C, D)
  resolves securities through the **ADR-0029 §2 identity ladder** (ISIN →
  alias → WKN → ticker+currency → name+currency, each tier applying only when
  it selects exactly one candidate, with a stronger-identifier veto), and
  inherits: **preview→apply revalidation** (apply re-runs the ladder inside
  the import transaction and aborts back to preview whenever any entry's
  resolution differs from what was approved; previews expire after two hours),
  the **config-at-risk warning** with per-row acknowledgment protecting stored
  category assignments and ADR-0030 position targets, the **pre-apply inverse
  check** listing config-bearing securities that match zero entries, and
  **fail-closed behaviour on non-interactive paths** — unresolvable entries
  are reported, never auto-created and never auto-matched.

  *Acceptance:* a fixture whose security resolution changes between preview
  and apply aborts with the preview restored and nothing written; a fixture
  matching two candidates at one tier is reported as ambiguous, not resolved;
  a non-interactive bulk call containing an unresolvable entry returns the
  entry as unresolved and writes zero rows.

### Feature A — Generic mappable CSV import (structured brokers)

Import an arbitrary broker transaction CSV by mapping it to Portfolixir
fields, without per-broker code.

- **FR-DI-1 Column mapping.** The user uploads a delimited file; the app
  previews detected columns and rows and lets the user map each Portfolixir
  field (date, type, ISIN/WKN/name, shares, price, amount, fees, taxes,
  currency) to a source column. **Account mapping resolves the depot and the
  cash account separately** — a buy touches both.
  *Acceptance:* a fixture with an unmapped required field cannot reach apply;
  a buy row produces a transaction carrying both a securities-account and a
  cash-account reference.

- **FR-DI-2 Value mapping.** A per-source dictionary maps distinct values of
  the type column to Portfolixir kinds. The kind set is **closed** (currently
  15: 13 PP kinds + `balance_adjustment` + `split`) and an unrecognised kind
  raises by design (ADR-0011), so column mapping alone cannot produce a valid
  transaction. **Unmapped values block apply and are surfaced in preview; they
  are never defaulted or guessed.**
  *Acceptance:* a fixture containing `Wertpapierkauf`, `Dividendengutschrift`
  and an unknown string previews the first two as mapped kinds and blocks on
  the third with the offending value named.

- **FR-DI-3 Source format profile.** Each source carries a detected,
  user-overridable profile: character encoding, delimiter, quote character,
  decimal separator, thousands separator, date format, and header-row offset.
  The preview renders **parsed Decimal values**, so a mis-detected separator
  is visible before apply. Ambiguous parses block rather than guess.
  **Sign normalization** is explicit: source amounts may be signed, stored
  amounts are positive magnitudes whose sign comes from the kind (the single
  exception being `balance_adjustment`, which may be negative).
  *Acceptance:* a CP1252 fixture with `;` delimiters, `1.234,56` amounts,
  `31.12.2025` dates and negative sell amounts imports to the same ledger
  state as its UTF-8 dot-decimal ISO-date positive-magnitude twin; a fixture
  where `1.234` is ambiguous between thousands and decimal separator blocks
  with both readings shown.

- **FR-DI-4 Saved mappings.** Column mapping, value mapping and format profile
  are saved per source and reusable, so re-imports need no re-mapping.
  `[ASSUMPTION]` — MVP or later is OD-3, but the answer changes both the data
  model and FR-DI-6's contract, so it is decided before Feature A starts.
  *Acceptance:* a second import of a different file from the same source
  requires no mapping input.

- **FR-DI-5 Preview.** The preview shows the records that would be created,
  the rows that fail validation with reasons, and the FR-DI-19 resolution
  outcome per row, before any atomic apply (#482).
  *Acceptance:* no write occurs on any path that has not rendered a preview.

- **FR-DI-6 Idempotency and re-import.** Idempotency is **two-layered**
  (#533, ADR-0029): a per-record `import_hash` over stable identity, plus a
  formatting-tolerant dedup key over the **resolved** database identity
  (portfolio, type, date, security, securities account, cash account,
  normalized Decimals). Because layer two keys on *resolved* ids, the
  following cases are specified rather than assumed:
  - **Re-import after a mapping change** — the preview shows which rows would
    newly insert *because their resolution changed*, and apply requires
    explicit confirmation. This is the expected second action of any mapping
    UI, not an edge case.
  - **Partially overlapping re-import** — only non-duplicate rows insert;
    duplicates are reported as skipped duplicates.
  - **Corrected source row** — a row matching an existing record on identity
    but differing in value is surfaced as a **conflict** in preview, never
    booked as a second record.
  - **PDF intake** — the hash covers the *extracted economic records*, never
    the file bytes, so a re-downloaded statement with different bytes and
    identical economics is still a no-op.

  *Acceptance:* importing a fixture twice unchanged writes zero rows the
  second time; importing it again after changing the mapping surfaces every
  affected row for confirmation and, when declined, writes zero rows;
  importing a variant with one restated fee reports one conflict and zero
  silent inserts.

### Feature B — External position list for reconciliation (IST only)

Compare a bank's snapshot against derived holdings. **This is not an import.**

Three representations were considered for storing a snapshot and all are
closed: storing positions is forbidden (holdings are never stored, ADR-0004,
no holdings table exists); synthesizing `inbound_delivery` transactions would
fabricate history the user did not confirm; and adding a positions-snapshot
ledger kind is an ADR-grade change to a closed kind set where unknown kinds
raise by design. The remaining invariant-safe option is the one the project
has since built.

- **FR-DI-7 Reconcile, never persist.** An external position list (security +
  quantity, optional value) is submitted, compared against derived holdings,
  and the differences are reported. **The list is never persisted** — this is
  ADR-0029 §6's `POST /api/v1/holdings/reconcile`, already shipped as the
  founding PRD's FR-35. This PRD's contribution is a **UI** over that endpoint
  and a CSV intake path for the list, not new storage.
  *Acceptance:* a reconcile run leaves the database byte-identical apart from
  the audit journal entry; a position present in the list but absent from
  holdings, and vice versa, are both reported.

- **FR-DI-8 No fabricated history.** Reconciliation never creates
  transactions. If the operator wants a snapshot to *seed* a depot, that is a
  separate, explicitly confirmed conversion into `inbound_delivery`
  transactions with **no cost basis**, and the consequence is stated at
  confirmation time: deliveries move quantity, not cost basis, so cost-basis
  and P&L views will exclude them.
  `[ASSUMPTION]` Whether seeding is wanted at all is open — reconciliation may
  be the whole of Feature B's value.
  *Acceptance:* no path from a submitted position list to a written
  transaction exists without an explicit confirmation step naming the
  cost-basis consequence.

### Feature C — API / MCP write-parity (the push path)

Enable an LLM or script to push transaction-grade data programmatically, so a
PDF can be parsed *outside* the app and the result posted in. This is the
highest-risk write path in this document.

- **FR-DI-9 Write coverage.** Every transaction kind creatable in the UI is
  creatable via the JSON API, running the **identical changeset validations**
  as the UI path — positive magnitudes, ADR-0015 cross-currency
  `settlement_fx_rate`, currency consistency. (Relates to #355 and to the
  founding PRD's FR-14.)
  *Acceptance:* a property test asserts that for every kind, a payload
  rejected by the UI changeset is rejected by the API with an equivalent
  error, and vice versa.

- **FR-DI-10 MCP write tools.** Equivalent MCP tools expose the same
  operations with decimals as strings.
  *Acceptance:* every write endpoint under `/api/v1` has a matching MCP tool.

- **FR-DI-11 Bulk create.** A batch endpoint posts a parsed statement's many
  rows in one call. **All-or-nothing within the call**, with per-row errors
  returned; a mid-sequence failure leaves nothing written. Non-interactive
  paths **fail closed** per FR-DI-19.
  *Acceptance:* a 200-row batch containing one invalid row writes zero rows
  and returns the offending row index and reason.

- **FR-DI-12 Journaling and authorization.** Every API/MCP write is recorded
  in the audit journal (ADR-0017, founding PRD FR-28) with the actor recorded;
  **Feature C depends on that work landing first** (`epics.md` sequences
  #353 before #355). The write authorization model is an **open decision**
  (OD-4): today `/api/v1` sits behind a single shared bearer token with no
  scopes and no per-actor identity, on an instance whose web UI is
  unauthenticated by design (founding PRD NFR-4, OQ-8) — so any holder of that
  token has full ledger write.
  *Acceptance:* no write path exists that produces no journal entry.

- **FR-DI-13 Idempotency keys, and how they relate to content hashing.**
  Writes accept an idempotency key so pushes are safe to retry. The two
  mechanisms are distinct and **both hold**: the key dedupes the *request*
  (same key + same body = no-op; same key + different body = error), the
  FR-DI-6 content hash dedupes the *records*. Keys have a stated storage
  lifetime.
  *Acceptance:* a retried identical request writes nothing and returns the
  original result; the same key with an altered body is rejected; two
  different keys carrying the same record still produce one record.

### Feature D — In-app broker-PDF intake (decided, ADR-0021)

Parse broker PDFs (Wertpapierabrechnung, Steuerreport) into transactions
inside the app: sandboxed, text-extraction-only, per-broker,
preview-then-confirm.

- **FR-DI-14 Trade statement.** Parse a broker Wertpapierabrechnung into one
  or more proposed transactions (buy/sell with price, fees, taxes, date,
  shares), shown in the same validated preview as other imports before apply,
  never written silently. Records are **journaled** (ADR-0017) and idempotent
  over extracted economic records per FR-DI-6.
  *Acceptance:* a synthetic statement fixture previews the expected
  Decimal-exact records; applying it twice writes them once.

- **FR-DI-15 Tax statement.** Parse a dividend/tax statement into dividend +
  tax records. **Decided, not assumed:** ADR-0021 puts the Steuerreport inside
  the first broker's committed scope alongside the Wertpapierabrechnung. If
  the two ship in sequence, the PRD names which is first; deferring the tax
  statement entirely would be a *narrowing* of an accepted ADR and belongs in
  §6 as an open decision, because without it Feature D delivers trades only
  and never recovers the dividends and taxes that motivated it.
  *Acceptance:* a synthetic tax-statement fixture produces the expected
  dividend and tax records with gross/withheld amounts separated.

- **FR-DI-16 Sandboxing, with numbers.** Parsing is text-extraction-only: no
  script or JS execution, no embedded-object evaluation, no content-triggered
  network access. "Sandboxed" names a concrete isolation boundary — a
  **separate OS process, no network namespace, memory and wall-clock rlimits,
  and a hard page cap** — because the BEAM provides no process sandbox and the
  word otherwise backs no mechanism. Numeric limits are stated in the
  implementing story and are testable.
  Named rejection cases, beyond the easy ones: **decompression bombs** (a
  small stream inflating to gigabytes), **XRef and object-reference cycles**,
  **recursion depth**, **malformed length fields**, and **memory exhaustion**.
  *Acceptance:* a malformed synthetic fixture per named class is rejected
  safely within the stated limits, with no partial parse reaching preview.
  Sobelow is a Phoenix-oriented static analyzer and is **not** the control for
  this parser; ADR-0021's per-change manual security review of the parser is.

- **FR-DI-17 Per-broker parsers.** Each broker layout is an explicit, tested
  parser (**synthetic fixtures only, never real statements**); scope grows one
  broker at a time.
  *Acceptance:* adding a broker adds fixtures for its valid and its
  deliberately malformed layouts.

- **Dependency note.** No PDF dependency exists in `mix.exs` today and no
  candidate is named. The realistic Elixir options are a wrapper that shells
  out to an external binary (`pdftotext`/poppler) or a pure library; the
  former is an **external binary invocation** with a materially different
  security posture, which changes FR-DI-16's boundary from a BEAM question to
  a container/OS question. Agents must not add dependencies inside a story, so
  this lands as its **own reviewed dependency PR before any Feature D story**
  (see §9).

### Feature E — Backup and restore

- **FR-DI-18 Documented backup/restore.** A documented `pg_dump`-based backup
  and restore procedure with a verified restore path (#354).
  *Rescoped 2026-07-22 (owner decision):* the **PP-compatible export was
  dropped** — Portfolixir is a one-way import destination, and data egress for
  external consumers is the JSON API. The "native Portfolixir export format"
  assumption is dropped with it; reviving either is a fresh open decision, and
  ADR-0029 already depends structurally on the rescope.
  *Acceptance:* the documented procedure restores a seeded synthetic database
  to a byte-equivalent state in a clean environment.

### Feature F — PP import hardening (interim bridge)

- **FR-DI-20 Partial apply, explicitly.** A single invalid record (e.g. a
  zero-amount tax or delivery row) never aborts the whole import. Apply
  commits **the approved subset in one transaction**; skipped rows are
  recorded in the import result with reasons. A later re-import re-evaluates
  skipped rows against the FR-DI-6 dedup key, so a corrected row inserts and
  an unchanged one stays skipped. Skipping is a per-row decision in the
  preview, not an automatic policy (#482).
  Note the classification question the example raises: a zero-amount tax
  record is arguably **not invalid at all** — that is a validation bug to fix
  rather than a row to skip. This FR covers "data the user must fix"; records
  Portfolixir wrongly rejects are a separate correction.
  *Acceptance:* a fixture with one invalid row commits the remaining rows in
  one transaction and lists the skipped row with a reason; re-importing after
  correcting the source inserts exactly that row.

- **FR-DI-21 PP XML — gated.** `[ASSUMPTION]` Evaluate PP XML full import
  (#333) for richer master data, classifications and quote history.
  **Hard gate:** PP XML is on AGENTS.md's forbidden document-intake list and
  requires the ADR + AGENTS.md amendment (founding PRD OQ-1a) before any
  implementation work. Evaluation is allowed; building is not.

### Follow-up notes (not in scope, no requirement)

Market-data sync (quotes + FX) already runs automatically and this PRD asks
for nothing there. Two robustness items are noted for a future decision, not
requested here: **rate-limit/backoff policy** and **provider coverage**.
*(This replaces the former FR-17, which consumed a requirement id while
explicitly asking for nothing.)*

## 6. Open decisions and assumptions

- **OD-1 — RESOLVED (2026-06-21, ADR-0021).** In-app broker-PDF intake is
  adopted (Option A), sandboxed/text-only/per-broker, superseding the AGENTS.md
  no-broker-PDF rule. §2 and §9 are written in past tense against this; there
  is no decision left to schedule.

- **OD-2 — the critical one.** Verify empirically what a typical German bank
  exports as CSV (snapshot only, or any transaction substance), and whether
  its official API carries transaction history and how far back. This is the
  evidence base for §2, for Feature A's reach, for Feature B's existence, and
  above all for ADR-0021.
  **Re-open trigger:** if the CSV or the official API carries transaction
  substance, ADR-0021's Option A/B/API choice is re-litigated **before the
  first Feature D story**.
  **Handling rule for the verification file:** it is inspected **locally,
  never committed**. Only a **synthetic fixture derived from its structure**
  enters the repository — no real statement, in any form, at any time.

- **OD-3.** Is a saved mapping (FR-DI-4) MVP or later? The answer changes the
  data model and FR-DI-6's re-import contract, so it is decided before Feature
  A starts rather than during it.

- **OD-4.** Write authorization model for Feature C: does the shared bearer
  token stay sufficient, or do writes need a distinct token or scope? Bound to
  the founding PRD's NFR-4 and OQ-8.

**Assumption register.** Load-bearing means: if this is wrong, a feature
changes shape or disappears.

| `[ASSUMPTION]` | Where | Load-bearing | What breaks if false |
|---|---|---|---|
| German-bank CSV is snapshot-only; transactions are PDF-locked | §2, OD-2 | **Yes** | Feature D's justification, and with it ADR-0021's accepted option |
| Official broker API lacks history depth | §2 | **Yes** | Same as above — the API becomes the cheaper path |
| Saved mappings are wanted | FR-DI-4, OD-3 | **Yes** | Data model and re-import contract both change |
| Snapshot seeding is wanted at all | FR-DI-8 | Moderate | Feature B reduces to reconciliation only |
| PP XML is worth evaluating | FR-DI-21 | No | Evaluation is cheap; the gate blocks building either way |

## 7. Success metrics & counter-metrics

- **SM-1 — importable without PP.** A synthetic broker CSV/PDF fixture pair
  imports to holdings matching a **checked-in Decimal-exact expectation**.
  This is the oracle: "correct against a real broker" cannot run in CI
  (synthetic fixtures only, no network calls) and would otherwise be
  verifiable exactly once, manually. A real-broker run is a separate manual
  acceptance step, recorded but not a CI metric.
- **SM-2 — time to first correct portfolio.** Measured as: upload started →
  first apply committed with zero unresolved entries, on the SM-1 fixture set.
  Baseline is taken on the first Feature A implementation; the target is a
  reduction against that baseline. With a user population of one, this is a
  workflow smoke signal, not statistics.
- **CM-1 — wrong data must not get in.** Replaces the former "silently
  produce wrong data", which was unmeasurable by construction (a silent
  failure has no detector). Three observable stand-ins: **zero rows applied
  that failed validation**; **every confirmed wrong-number incident becomes
  an invariant test**; and **the ADR-0029 §6 reconcile endpoint reports zero
  unexplained differences** on a monthly check.

## 8. Related issues

| Issue | Carries |
|---|---|
| #482 | Import hardening — FR-DI-5, FR-DI-20 |
| #333 | PP XML — FR-DI-21 (gated) |
| #354 | Backup/restore — FR-DI-18 |
| #355 | MCP write tools — Feature C (the founding PRD's FR-14) |
| #353 | Audit journal — prerequisite of FR-DI-12 |
| #416 | Data epic |
| #419 | LLM/MCP epic |

`epics.md` holds the authoritative FR→issue table for the global sequence.

## 9. Phasing sketch (smallest validating first)

1. **Verify the source-data reality** (OD-2) — cheap, and it decides whether
   Feature D is justified at all. Moved to the front: everything downstream
   assumes its answer.
2. **Harden the PP bridge** (#482, FR-DI-20) — keep migration reliable.
3. **Audit journal** (#353) — prerequisite for any programmatic write.
4. **API/MCP write-parity** (Feature C) — unlocks the LLM push path.
5. **PDF dependency decision** — its own reviewed PR, before any Feature D
   story.
6. **Feature D** (in-app PDF) per ADR-0021, gated on OD-2's answer.
7. **Generic CSV import** (Feature A) for structured brokers, after OD-3.
8. **Backup/restore** (Feature E).
9. **Reconciliation UI** (Feature B) as a small, clearly-scoped add.

*(Step 6 in the earlier draft called Feature E "the true leave-PP milestone".
With the PP-compatible export dropped, that milestone no longer exists as
phrased — leaving PP is now achieved by Features A/C/D covering intake.)*
