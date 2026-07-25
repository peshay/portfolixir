# PRD Addendum — Data Import & Sync (2026-06-21, written 2026-07-25)

Mechanism and technology depth that informs architecture and epics but does not
belong in the PRD narrative. The PRD header has pointed here since 2026-06-21;
the file was missing until the 2026-07-25 revision.

**Privacy scope (owner decision, 2026-07-25).** Public repo. The operator is
named openly and named brokers stay — a deliberate, recorded choice. Out,
permanently: **concrete financial values** of any kind, and **anything about
the operator's family or household**. The OD-2 verification file is inspected
locally and never committed; only a synthetic fixture derived from its
*structure* enters the repo.

## Why idempotency is two-layered

`lib/portfolixir/imports/applier.ex` implements two mechanisms and ADR-0029 §5
calls the pair load-bearing:

1. **`import_hash`** — per record, derived from its stable identity. Catches a
   byte-identical re-import of the same export.
2. **`dedup_key/1`** — formatting-tolerant, computed over the **resolved**
   database identity: `portfolio_id`, `type`, `date`, `security_id`,
   `securities_account_id`, `cash_account_id`, normalized Decimals. Catches
   the same economic record arriving in a different textual shape.

The consequence that drives FR-DI-6: because layer two keys on *resolved* ids,
anything that changes resolution — a corrected mapping, a new ISIN alias, a
merged security — changes the key. Re-import then looks like new data. This is
not a defect in the mechanism; it is why the PRD requires the preview to name
rows that would newly insert *because resolution changed*.

For PDF intake the hash must cover extracted economic records rather than file
bytes: re-downloading the same statement commonly yields different bytes
(timestamps, generation metadata) with identical economics.

## Why a positions snapshot has no ledger representation

Three candidate representations, all closed:

| Option | Status |
|---|---|
| Store positions in a holdings table | Forbidden — holdings are always derived (ADR-0004); no holdings table exists |
| Synthesize `inbound_delivery` transactions | Fabricates unconfirmed history; also moves quantity without cost basis, which silently distorts cost-basis views |
| Add a positions-snapshot ledger kind | ADR-grade change to a closed 15-kind set (`Transaction.kinds/0`); unknown kinds raise by design (ADR-0011), and a catch-all clause would convert crash-by-design into silent corruption |

Adjacent concepts that do **not** solve it: `balance_adjustment` (ADR-0009)
anchors **cash** balances only and cannot carry a security quantity;
ADR-0027's `snapshot` is a **ledger marker** that copies no transactions,
quantities or prices — the opposite of a positions copy.

What remains is the transient reconcile input ADR-0029 §6 already built
(`POST /api/v1/holdings/reconcile`, list never persisted). Feature B is
therefore a UI and a CSV intake path over an existing endpoint.

## German broker CSV — the properties that actually appear

Driving FR-DI-3. Every item below is routine in German bank exports and each
one silently corrupts data if unhandled:

- **Decimal comma and dot thousands separator** (`1.234,56`). `Decimal.new/1`
  raises on that string, and `Decimal.from_float/1` must never touch a
  persisted value.
- **`;` as delimiter**, precisely because the comma is the decimal mark.
- **`DD.MM.YYYY` dates.**
- **CP1252 / ISO-8859-1 encoding.** Mis-decoding corrupts security names —
  which are a matching tier in ADR-0029's ladder, so an encoding error becomes
  a resolution error.
- **Preamble/junk lines** before the header row.
- **Quoted fields containing the delimiter.**
- **Signed amounts.** Storage requires positive magnitudes with the sign
  carried by the kind; PP's importer already normalizes this and Feature A
  needs the same rule.

Note why the API's escape hatch is unavailable here: ADR-0029 §6 could declare
canonical dot-decimal Decimal strings and make locale parsing the client's
job, because an API has a client. A file upload has none — the app parses the
locale format or Feature A imports nothing.

## PDF parsing — dependency and isolation

- `mix.exs` carries **no PDF dependency** today; no candidate has been named.
- Realistic Elixir options: a pure library, or a wrapper shelling out to
  `pdftotext`/poppler. The latter is an **external binary invocation** — a
  materially different security posture that moves the isolation question from
  the BEAM to the container/OS layer.
- The BEAM offers **no process sandbox**, so "sandboxed" must name an OS-level
  boundary to mean anything: separate OS process, no network namespace, memory
  and wall-clock rlimits, hard page cap.
- Threat classes that matter for PDFs and are not covered by "no script
  execution": decompression bombs, XRef and object-reference cycles, recursion
  depth, malformed length fields, memory exhaustion.
- Sobelow is a Phoenix-focused static analyzer; nominating it as the control
  for a binary-format parser is a category error. ADR-0021's per-change manual
  security review is the actual control.
- Agents must not add dependencies inside a story (project-context.md), so the
  choice lands as its own reviewed dependency PR.

## Write-path risk, stated plainly

Feature C is the highest-risk path in the PRD: an LLM posting many financial
rows at once, derived from PDF text extraction of unknown fidelity.

- Authorization today: a single shared bearer token via `ApiAuthPlug`, no
  scopes, no per-actor identity — and the web UI itself is unauthenticated by
  design (founding PRD NFR-4). Anyone reaching the port, or holding the one
  token, has full ledger write. Recorded as OD-4.
- The audit journal (ADR-0017) makes damage **legible afterwards**; it
  prevents none of it. Prevention is idempotency keys, dry-run, fail-closed
  resolution and all-or-nothing batches.
- `epics.md` sequences the journal (#353) before MCP writes (#355) for this
  reason.

## Numbering

This PRD uses `FR-DI-n`. The global `FR-n` sequence belongs to the founding PRD
plus `epics.md`; the earlier draft restarted at FR-1 and collided across at
least eight identifiers, which mattered because ADRs cite global ids in prose
(ADR-0029 references FR-7 repeatedly in its main-PRD meaning). Prefixing was
chosen over renumbering into the global sequence so that these requirements can
be reordered or dropped without consuming global ids.
