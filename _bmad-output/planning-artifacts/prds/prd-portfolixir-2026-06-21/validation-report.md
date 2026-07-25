# Validation Report — PRD Data Import & Sync (2026-06-21)

- **PRD:** `_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-21/prd.md`
- **Rubric:** not run (rubric walker deselected for this run)
- **Reviewers:** adversarial-general
- **Run at:** 2026-07-25T13:04:34Z
- **Grade:** Poor (derived from severity counts alone — no dimension verdicts were produced)

> **Format note.** An HTML twin of this report was generated and removed again on
> 2026-07-25: the two reports shared ~309 identical lines of inline CSS and
> boilerplate, which tripped SonarCloud's new-code duplication gate. This
> markdown file is the canonical form and carries the same content.

> **Resolved 2026-07-25.** All 20 findings were addressed in a fix round on the
> same day; see `.decision-log.md` for what was applied and for the two
> agent-made judgment calls flagged for owner review (FR-DI-n prefixing,
> Feature B reframed to reconciliation). The privacy finding was **narrowed by
> owner decision**: naming the operator and comdirect is acceptable, so only
> OD-2's missing file-handling rule was fixed. This report is the record of
> what was found, not a list of open items.

## Overall verdict

This PRD is a strategy memo wearing a requirements document's clothes. Its
central factual claim — that transaction-grade German-bank data is "locked in
PDFs" — is stated in §2 as "The hard truth about source data" and then
contradicted 100 lines later by its own OD-2, which asks someone to go "verify
empirically what comdirect actually exports as CSV" and tags the whole question
`[ASSUMPTION]`. That unverified premise is the sole justification offered for
ADR-0021, which has already been **Accepted** and has already amended AGENTS.md
to punch a hole in a hard rule. The PRD also never mentions that the
authoritative PRD's own FR-17 documents "comdirect: depot positions *and
transactions* via the official REST API" — the option that would make Feature D
unnecessary is not rejected, it is simply absent from the analysis.

Below the strategy layer the requirements do not survive contact with the
codebase. Feature B has no legal home in this system: holdings are never stored
(ADR-0004), the kind set is closed and contains no positions-snapshot kind, and
FR-6 forbids the one remaining implementation — three doors, all locked, and the
PRD notices none of them. Feature A specifies mapping at *column* level only, so
it cannot map a broker's free-text "Wertpapierkauf" onto a closed kind set, and
says nothing about decimal commas, `;` delimiters, `DD.MM.YYYY` dates or CP1252
encoding. FR-4's idempotency claim is false for the ordinary re-import cases.
There are zero acceptance criteria, so the document cannot pass the ADR-0026
decision gate it needs to start an epic batch, and the `addendum.md` its header
promises does not exist. Finally it is a month stale: FR-14's export was
cancelled 2026-07-22, and ADR-0029 has since made an identity ladder,
preview→apply revalidation and config-at-risk warnings binding on every import
path this PRD describes.

## Dimension verdicts

Not assessed — the rubric walker was deselected for this run. Only the
adversarial reviewer ran, so this report carries findings and an assumption
audit, not per-dimension judgments.

## Findings by severity

### Critical (6)

**[Adversarial]** — The founding premise is asserted as fact and admitted as unverified in the same document (§2 / §6 OD-2)
§2 uses the rhetoric of settled fact for a proposition §6 explicitly parks as unverified. That proposition is the entire load-bearing argument for Feature D, which has already become ADR-0021 (Accepted) and already amended AGENTS.md. The project now carries a permanently widened document-intake surface, a per-broker maintenance obligation and a pending new dependency — all justified by a premise nobody has checked, where checking costs one afternoon and one export click.
Fix: Demote §2 to "Working hypothesis, unverified (OD-2)" and state that ADR-0021 was accepted before OD-2 closed. Add a re-open trigger: if OD-2 shows transaction substance via CSV or the official API, ADR-0021's Option A/B choice is re-litigated before the first Feature D story. Move OD-2 to step 1 of §9.

**[Adversarial]** — The option that would make Feature D unnecessary is documented in the main PRD and never mentioned here (§2 / Feature D / §4)
The authoritative PRD's FR-17 documents the official REST API for depot positions *and transactions*, as an operator-stated must-have. This PRD neither cites nor rejects it; §4 disposes of it as "unchanged policy". ADR-0021's options analysis inherits the blind spot, weighing only in-app parsing against out-of-app push. The project may be about to build and perpetually maintain a hostile-input PDF parser to recover data an authenticated REST endpoint returns as structured JSON.
Fix: Add a "Considered and rejected" subsection covering the REST API with the real reason — most plausibly history depth and the PhotoTAN/unattended problem already logged as main-PRD OQ-6. Reconcile §4's wording. Fold the result back into ADR-0021 as a third rejected option.

**[Adversarial]** — Feature B has no legal representation in the ledger and contradicts itself (Feature B / FR-5, FR-6, FR-7)
Three ways to implement FR-5, all closed: storing positions is forbidden (ADR-0004); synthesizing deliveries is forbidden by FR-6's own clause; adding a ledger kind is unmentioned and would be an ADR-grade change to a closed 15-kind set where unknown kinds raise by design. `balance_adjustment` is cash-only. FR-6 and FR-7 then presuppose the impossible thing happened. The path of least resistance for an implementing agent is exactly the forbidden holdings table.
Fix: Decide the representation in this PRD. Invariant-safe options: (a) a transient, never-persisted reconcile input — which ADR-0029 §6 has since built, making FR-7 largely redundant; or (b) explicit user-confirmed conversion to `inbound_delivery` with no cost basis, which requires deleting FR-6's clause and stating the cost-basis consequence. Pick one.

**[Adversarial]** — FR ids collide head-on with the authoritative PRD's stable global numbering (§5 / §8)
The main PRD's rule is "IDs are stable and globally numbered; new requirements append, never renumber". This PRD restarts at FR-1 and collides across the whole range. Not cosmetic: "FR-7" is cited across the live corpus in its main-PRD meaning (ADR-0029 uses it repeatedly), and §8 demonstrates the confusion by using FR-14 in both senses within four lines.
Fix: Renumber into the global sequence or prefix unambiguously (`FR-DI-1` …). Fix §8's and FR-8's cross-references to name the main-PRD id explicitly. Add a line to §5 stating which numbering authority governs.

**[Adversarial]** — Feature A maps columns but never maps values — it cannot produce a transaction kind (Feature A / FR-1)
The type column holds free text in the broker's vocabulary and must land on one of exactly 15 closed kinds where an unrecognised value raises by design. Feature A gives the user no way to express "the string `Wertpapierkauf` means `buy`", so it cannot import a single row of any real broker CSV. Same gap for "account" (a buy touches depot *and* cash account) and for security resolution.
Fix: Split FR-1 into column mapping and **value mapping**: a per-source dictionary from distinct source values to kinds, with unmapped values blocking apply and surfaced in preview, never defaulted. Require account mapping to resolve depot and cash account separately, and security resolution to run the ADR-0029 §2 ladder.

**[Adversarial]** — FR-4's idempotency claim is false for the cases that actually occur (FR-4, FR-11, FR-15)
Idempotency is two-layered (#533): a per-record `import_hash` plus a `dedup_key/1` computed over the **resolved** database identity. Because layer two keys on resolved ids, a user who corrects a mapping and re-imports the same file changes the resolved ids and silently duplicates every row — and FR-2's savable mappings make that the designed workflow. Also unaddressed: partially overlapping re-imports, corrected exports, and what the hash covers for a PDF whose bytes differ but economics do not. AGENTS.md classes import idempotency as a risk tier requiring dedicated PRs with real human review.
Fix: Replace FR-4 with explicit semantics — state the two layers, then add requirements for (a) re-import after a mapping change with explicit confirmation of newly inserting rows; (b) partial overlap; (c) corrected rows producing a *conflict* in preview, not a silent second booking; (d) PDF hashing over extracted economic records. Add ADR-0029's preview→apply revalidation.

### High (8)

**[Adversarial]** — §4's out-of-scope wording silently widens the document-intake exception to binary `.portfolio` (§4)
Scope defined by complement, on an `[ASSUMPTION]` tag, against a hard rule. Read literally, everything that *is* a PP format and everything that *is* a PDF is in scope. The PRD then acts on its own widened reading at FR-16, with no mention of the main PRD's scope gate.
Fix: State scope positively. List in-scope formats explicitly and out-of-scope ones explicitly (binary `.portfolio` — hard out; PP XML — gated on ADR + AGENTS.md amendment). Remove the `[ASSUMPTION]` tag from a scope boundary.

**[Adversarial]** — Feature C opens a bulk write path with no audit, authorization or validation story (FR-8, FR-9, FR-10)
"Auditable" is asserted and never specified — the audit journal, whose stated purpose is precisely this threat, is never named, and `epics.md`'s ordering constraint is ignored. Authorization is absent: a single shared bearer token, no scopes, no per-actor identity, on an instance whose web UI is unauthenticated by design. FR-9's idempotency keys introduce a second, incompatible idempotency mechanism with no statement of precedence.
Fix: Require journaling per ADR-0017 with actor recorded and make Feature C depend on it; state as a testable requirement that API writes run identical changeset validations; define the write authorization model or record it as an open decision; specify how idempotency keys relate to content-hash idempotency; specify partial-failure semantics and adopt ADR-0029's fail-closed rule.

**[Adversarial]** — Feature A ignores every property a real German broker CSV actually has (FR-1, FR-3)
Absent: decimal and thousands separators (`Decimal.new/1` raises on `1.234,56`), date format, encoding (CP1252 mis-decoding silently corrupts security names, a matching tier in ADR-0029), delimiter detection, preamble lines, quoted fields, and negative-signed amounts. That last is a direct invariant collision: amounts are positive magnitudes with sign from the kind, and broker CSVs carry signed amounts. The API escape hatch ("locale parsing is the client's job") is unavailable for a file upload.
Fix: Add a per-source format profile — encoding, delimiter, quote char, separators, date format, header row offset — detected with a preview, user-overridable, saved alongside the mapping. Add explicit sign normalization. Require the preview to show parsed Decimal values, and ambiguous parses to block rather than guess.

**[Adversarial]** — Feature D drops binding ADR-0021 constraints and calls an undefined thing "sandboxed" (FR-11, FR-12a)
ADR-0021 requires journaled, content-hash-idempotent apply and a per-change parser security review — FR-11 mentions neither. "Sandboxed" is never defined and Elixir provides no process sandbox. The threats that actually kill PDF parsers are missing: decompression bombs, reference cycles, recursion depth, memory exhaustion. Sobelow is a Phoenix static analyzer — a category error here. No PDF dependency exists in `mix.exs` and no candidate is named; the realistic Elixir option is shelling out to `pdftotext`, a materially worse posture than "a library".
Fix: Require journaling and idempotency over extracted economic records; define "sandboxed" by naming the isolation boundary with **numeric** limits so FR-12a is testable; add the missing threat classes as named rejection cases with malformed synthetic fixtures; name the candidate library or binary; restate the per-change security-review obligation; schedule the dependency decision as its own PR.

**[Adversarial]** — FR-14 requires an export the owner cancelled a month ago (FR-13, FR-14)
The PP-compatible export was dropped by owner decision 2026-07-22 (#354); backup/restore is a documented `pg_dump`, egress is the JSON API, and ADR-0029 relies on that rescope structurally. This PRD still carries the cancelled requirement as its "true 'leave PP' milestone". Anyone building an epic from this document builds a dead feature.
Fix: Replace FR-13/FR-14 with the rescoped FR-29. Delete the "native export format" assumption or raise it as a fresh open decision. Re-examine §9 step 6.

**[Adversarial]** — The PRD predates ADR-0029 and describes import paths that violate it (Features A, B, C, D)
ADR-0029 makes binding on every import path: the identity ladder with exactly-one-candidate tiers and a stronger-identifier veto; preview→apply revalidation; config-at-risk warnings with per-row acknowledgment; a pre-apply inverse check; fail-closed non-interactive paths. This PRD's FR-3 is a strictly weaker contract. An importer built to it will silently duplicate securities and strand the classification and target configuration ADR-0029 exists to protect.
Fix: Add a cross-cutting requirement that every intake path inherits the ADR-0029 rules. Bump `updated:` and add ADR-0029/ADR-0030 to the reference list.

**[Adversarial]** — The document has no acceptance criteria, so it cannot pass its own decision gate (whole document / §5)
Seventeen FRs, not one acceptance criterion — while ADR-0026's epic-batch workflow requires "an ADR or spec *with acceptance criteria*, signed off by the owner before the batch starts". §9 nonetheless lays out a seven-step build order. Compounding this, `addendum.md`, to which the header routes all mechanism detail, does not exist.
Fix: Write `addendum.md` or delete the pointer and inline the decisions. Add acceptance criteria to every FR intended for the next batch — minimally FR-1..FR-4 and FR-11/12a — as observable outcomes on synthetic fixtures. Until then mark the document "not decision-gate ready".

**[Adversarial]** — The PRD reverts the main PRD's deliberate anonymization and asks for a real bank file (frontmatter / §3 / OD-2 / FR-11)
This is a public repository. AGENTS.md forbids committing the maintainer's personal banking relationships and requires generic placeholders. This PRD names the real maintainer in the frontmatter and §3, names comdirect as the concrete first broker, and asks for "a real, anonymized file" from that broker — attaching a named banking relationship to an identified person. There is also an unguarded instruction: OD-2 asks someone to obtain a real export and says nothing about where it may live.
Fix: Replace the owner name with the established fictional persona or a role. Rewrite OD-2 to drop the identity link and add an explicit handling rule: the verification file is inspected locally, never committed, and only a synthetic fixture derived from its *structure* enters the repository.

### Medium (5)

**[Adversarial]** — Success metrics and the counter-metric are unmeasurable as written (§7)
CM-1 counts *silent* wrong-data incidents — unmeasurable by construction, with no detector or baseline proposed. SM-1 has no oracle for "correct" and cannot run in CI given synthetic-fixtures-only and no-network rules, so it is verifiable exactly once, manually. SM-2 has no baseline, target, instrument or start/stop events.
Fix: Give SM-1 an oracle ("a synthetic broker CSV/PDF fixture pair imports to holdings matching a checked-in Decimal-exact expectation"). Give SM-2 a baseline and target or cut it. Replace CM-1 with something observable.

**[Adversarial]** — OD-1 exists in three contradictory states inside one document (§2 / Feature D / §6 / §9)
Under review, decided, and scheduled-to-be-decided. §6 corrects §2 and §9 without editing them. The phasing sketch — what an epic planner reads — still branches on a resolved decision.
Fix: Rewrite §2's bullet in past tense pointing at ADR-0021, and §9 step 4 as "Feature D per ADR-0021 — gated on OD-2". Keep OD-1 in §6 as a resolved record.

**[Adversarial]** — FR-12 is tagged as an unconfirmed assumption although ADR-0021 already decided it (FR-12)
The first broker's committed scope includes the tax statement. Marking it `[ASSUMPTION]` invites an implementer to drop it — at which point Feature D delivers trades only, and the dividends and taxes §2 named as the PDF-locked data never arrive.
Fix: Drop the tag, cite ADR-0021's first-broker scope, and state which document type ships first. If deferral is intended, that is a narrowing of an accepted ADR and belongs in §6.

**[Adversarial]** — FR-15's partial-apply requirement contradicts the atomicity it claims to preserve (FR-15)
"Atomic" and "some rows are skipped" are reconcilable only if the PRD says so, and it does not. Nor does it say whether skipped rows are remembered, how re-import interacts with FR-4, or whether skipping is a user decision or a policy. The zero-amount example reads more like a validation bug than a row to skip.
Fix: State that apply commits the approved subset in one transaction and records skipped rows in the result. Specify that re-import re-evaluates skipped rows against the dedup key. Separate "invalid data the user must fix" from "records Portfolixir wrongly rejects".

**[Adversarial]** — The PRD has no non-functional requirements, though the decision log claims it does (whole document / §5)
There are no "NFR-equivalent notes". §4 mentions two of three constraints in a parenthetical and never mentions Decimal — in a PRD about getting numbers into a ledger from sources that format numbers differently. Also absent: upload size and row-count limits; where uploaded files are stored and whether they are deleted after apply; and any performance expectation.
Fix: Add a short NFR section: Decimal-only parsing and persistence; upload size and row-count limits; retention and deletion policy for uploaded source files; a paginated-preview performance expectation; security boundaries restated from AGENTS.md.

### Low (1)

**[Adversarial]** — Feature G is a requirement that states it is not a requirement (FR-17)
An FR id with no requirement, no acceptance criterion, and an explicit disclaimer that nothing is being asked for. It consumes an identifier, appears in traceability tooling as unimplemented, and hides two genuine questions behind a "not new scope" label.
Fix: Delete FR-17 and move the two robustness items into a "Follow-up notes (not in scope)" subsection, or promote them to real FRs with criteria.

## Assumption audit

**Load-bearing and unconfirmed: 7 of 9** (#2, #3, #4, #5, #6, #7, #9), plus #8
load-bearing for scope legality. Two of the load-bearing set (#6, #7) are not
assumptions at all — they are decisions the PRD misreports, one understating a
commitment and one ignoring a cancellation.

| # | `[ASSUMPTION]` | Location | Load-bearing? | What breaks if false |
|---|---|---|---|---|
| 1 | "solo/local, no multi-user" | §3 | **No** — mislabeled | Nothing: already decided as main-PRD NFR-6. Tagging a decided NFR as an assumption weakens a settled constraint. |
| 2 | "multi-user and non-PP non-PDF document formats remain out" | §4 | **Yes** | Scope is defined by complement, so the assumption *is* the boundary. Binary `.portfolio` and PP XML become in-scope, contradicting ADR-0021 and AGENTS.md. |
| 3 | "Mappings are reusable/savable per source" | FR-2 | **Yes** | Saved mappings are how a corrected mapping gets re-applied — the exact case that breaks the resolved-id dedup key. If dropped, every import needs full manual re-mapping. Either way it changes the data model *and* the idempotency contract. |
| 4 | "Snapshot can be used to reconcile against derived holdings" | FR-7 | **Yes** | Feature B's only ongoing value. Presupposes the snapshot persists, colliding with ADR-0004. Overtaken by ADR-0029 §6's never-persisted reconcile endpoint. |
| 5 | "Bulk/batch create endpoint" | FR-10 | **Yes** | Without it, a 200-row statement is 200 unrelated calls with no shared transaction, no atomicity and no single audit record. |
| 6 | "Parse a dividend/tax statement" | FR-12 | **Yes** | Already decided by ADR-0021. Honouring the tag means Feature D delivers buy/sell only and never recovers the data that justified overriding a hard rule. |
| 7 | "plus a native Portfolixir export format" | FR-14 | **Yes** | Overtaken by the 2026-07-22 owner decision. Building it ships a second serialization format the owner explicitly declined. |
| 8 | "Evaluate PP XML full import" | FR-16 | **Yes (scope legality)** | PP XML is on AGENTS.md's forbidden list with a scope gate. An agent could start implementation without the amendment — a hard-rule violation. |
| 9 | "Verify empirically what comdirect exports as CSV" | OD-2 | **Yes — the critical one** | The evidence base for §2, Feature A's reach, Feature B's existence, and above all ADR-0021. If the CSV or the official API carries transaction substance, the cost/benefit that selected Option A inverts. |

## Mechanical notes

- `addendum.md` does not exist, though the header routes all mechanism detail to it.
- FR-14 is defined twice with different meanings four lines apart; FR-8's cross-reference has the same problem.
- Frontmatter is stale (`status: draft`, `updated: 2026-06-21`) while at least five Accepted ADRs affecting this subject matter have landed since.
- The kind set is 15, not 13. Any mapping UI enumerating kinds must cover `split`, which has entirely different field semantics.
- §8 lists issues without stating their contribution; `epics.md` already holds an FR→issue table.
- FR-3 and FR-15 both point at the same issue for two different requirements without distinguishing them.
- No glossary or reference section: PP, IST, SOLL, Wertpapierabrechnung, Steuerreport and WKN are used undefined.
- "Already built" (Feature G) is the only verified-true capability claim in the document — and it asks for nothing.
- Upload handling is unmentioned; both Feature A and Feature D accept file uploads, and filesystem-state tests require `async: false`.

## Reviewer files

- `review-adversarial-general.md` (this run, 2026-07-25)
