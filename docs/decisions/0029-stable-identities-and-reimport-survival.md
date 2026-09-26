---
layout: docs
title: "ADR-0029: stable identities and re-import survival — an identity ladder with ISIN-change aliases"
description: Decision that strategy configuration survives a PP re-import through deterministic import-time matching on a stable-identity ladder (ISIN incl. journaled ISIN-change aliases, then WKN, ticker+currency, name+currency, each tier only when unambiguous), with unmatched leftovers surfaced in the preview — and that the FR-35 read-only holdings reconcile is built as a small endpoint rather than closed as a documented procedure.
---

# ADR-0029: stable identities and re-import survival — an identity ladder with ISIN-change aliases

- **Status:** Accepted (owner sign-off 2026-07-22, following the three-method
  adversarial review round; [ADR-0026](0026-epic-batch-workflow.html)
  decision gate passed); **amended by
  [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html)**
  (2026-09-24, signed by the merge of the Sprint 16 planning PR): the Context
  sentence on account renames no longer holds; the content-hash check runs
  ahead of all resolution and consults retired hashes; the in-run collapse key
  is scoped by the file's account names; account resolution gains a
  former-name tier; and §3's manual repair points at the security merge.
  **Amended by the security pass E25 S5** (2026-09-25, Sprint 16, adopted
  with its triage): the content hash and the reference key are injective
  with every stored hash still valid, and a split-off tax refund books with
  its row (see the amendment below).
- **Date:** 2026-07-19

## Context

A fresh Portfolio Performance import that fails to recognise an existing
security creates a duplicate row with a new internal id — and every piece of
strategy configuration keyed to the old row silently stops describing the
portfolio the owner actually holds. That configuration is the accumulated
E13/E15/E16 investment (FR-34, E18): classification trees with category
assignments, named target-plan versions with per-category weights, and
per-view cash targets.

What the import actually does today (verified in
`Portfolixir.Imports.Applier`):

- Securities resolve **by ISIN when present**, else by `(name, currency)`;
  a miss creates a new security. Cash accounts and depots resolve by name
  within the portfolio, with a user-driven mapping step in the LiveView
  path; **user-driven security match overrides are a named but unbuilt
  follow-up** in the applier's own moduledoc.
- Idempotency is two-layered (#533): a content `import_hash` skips exact
  re-inserts, and a formatting-tolerant dedup key over the *resolved* DB
  identity (portfolio, security/account ids, normalized Decimals) skips
  re-imports whose only difference is PP-export drift.

> **Amended by [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html)
> §4 (2026-09-24):** cash accounts and depots resolve by the exact live name
> first, then by a **former name** — a name the account was renamed from, a
> merged-away account's name, or a remembered remap — through one function
> the preview's prefill and the apply share; an ambiguous tier prefills
> nothing and the apply refuses the name unmapped.
>
> **Amended by ADR-0050 §3 (2026-09-24):** the content-hash check runs
> **ahead of all resolution**, and a hash a merge retired
> (`retired_import_hashes`) counts like a live one: a row whose hash is held
> or retired triggers no security, cash or depot resolution, no creation and
> no insert, and is reported with its layer (`hash` or `retired`).

So the golden path — re-import a mutated export into a **live** database —
already mostly works for ISIN-bearing securities. What is actually at risk,
verified against the schemas:

1. **Two strategy-data classes are keyed to a security** (both FK
   `on_delete: :delete_all`): stored category assignments
   (`security_category_assignments.security_id`) and position-level SOLL
   targets (`portfolio_targets.security_id`,
   [ADR-0030](0030-position-level-soll-targets.html)) — a duplicated
   security strands both alike *(the position-target class was added by the
   2026-07-22 review round; the original draft missed it)*. Built-in trees
   (`asset_class`, `currency`) are derived on read
   ([ADR-0006](0006-classifications-with-target-weights.html)) and cannot
   orphan. Plans, category-level targets, and cash targets hang off
   `(portfolio, view, classification, category)` — a re-import never touches
   them. The *unmapped* survival problem is therefore the **security
   identity** problem; bucket/view membership keys to depots/cash accounts,
   whose renames are covered by the existing user-driven mapping step (which
   any future non-interactive path must mirror, see §2).

   > **Amended by [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html)
   > (2026-09-24):** this sentence held only while the operator remapped by
   > hand on every import. A rename over the API created an empty account
   > under the old name on the next import, and with a drifted export booked
   > the history a second time. Accounts now remember their former names
   > (§4 there), are created only with their first new booking (§4), and a
   > merge of two accounts leaves the source's name as a former name of the
   > target (§7).
2. **ISIN-less securities** (crypto, watch-only, some certificates): `isin`
   is nullable and only unique-when-present. The `(name, currency)` fallback
   breaks on any rename in PP — the import then creates a duplicate and the
   assignments stay on the old, now position-less row. ISIN-only matching
   would orphan exactly these positions; this ADR must decide the fallback.
3. **A changed ISIN** (corporate action rename/ISIN change): the old ISIN no
   longer appears in the export, the ISIN tier misses, and a duplicate is
   created. [ADR-0028](0028-corporate-actions-as-ledger-events.html) §4
   explicitly deferred this slice to this record.

Out of scope here: restoring strategy configuration into a **fresh**
database. Since the FR-29 rescope (owner decision 2026-07-22, #354) that is
an operational concern, not a matching concern: the documented `pg_dump`
backup/restore carries the whole database — strategy configuration
included, internal ids intact — and needs no identity matching at all. The
former plan to serialize strategy config keyed by stable identities is
dropped together with the PP-compatible export; data egress for external
consumers is the JSON API. Follow-up note, not FR-34 scope.

Dependencies, verified in code on 2026-07-19:

- **E16's Targets/Plans journal arming has landed**: `Portfolios.Targets`
  ("Every write is journaled … the tables are guard-armed") and
  `Portfolios.TargetPlan` state and implement journaled, guard-armed writes
  ([ADR-0017](0017-append-only-audit-journal.html)); `Classifications` and
  `Catalog` security writes are likewise journaled. The named E18
  precondition is satisfied.
- **FR-30 has shipped**: holdings payloads (JSON API and MCP) carry
  `isin`/`wkn` (verified in `Api.V1.JSON`), which the FR-35 section below
  must weigh.

## Decision

### 1. FR-34 mechanism: import-time stable matching, not a config export format

**Recommended: harden the existing import-time matching into a
deterministic stable-identity ladder (§2).** The strategy configuration
itself is never exported, re-imported, or re-attached — it simply keeps
pointing at security rows that the import reliably recognises instead of
duplicating. This directly serves the golden path (re-import a mutated
export into a live database), builds on matching logic and two-layer
idempotency that already exist and are tested, and adds no new file format.

**Rejected: strategy-config export/import** as the FR-34 mechanism. It does
not fix the golden path (nothing was exported before the re-import that
orphans the config); it introduces a second serialization format to
version and round-trip-test; and it cannot dodge the identity question —
re-attaching an exported assignment still requires deciding *which*
security "the BTC position" now is, i.e. it presupposes the ladder anyway.
Its one real strength, fresh-database restore, is already covered by
FR-29's documented `pg_dump` backup (rescoped 2026-07-22, see Context) —
which removes the last argument for a config-export format.

### 2. The identity ladder, and the fallback for ISIN-less securities

A security in the import stream resolves against existing securities by
descending a fixed ladder; each tier applies only when the field is present
on **both** sides, and only when it selects **exactly one** candidate
(neither `wkn` nor `ticker_symbol` is unique in the schema — verified):

1. **ISIN** — current ISINs first, then the alias table of §3.
2. **WKN.**
3. **`(ticker_symbol, currency)`.**
4. **`(name, currency)`** — today's fallback, kept as the last tier.

Determinism rules, all binding:

- A tier that matches **ambiguously** (two candidates share the WKN) does
  not fall through to a weaker tier and does not silently pick: the entry
  is surfaced in the import preview for an explicit user decision.
- The preview grows the **user-driven security match override** already
  named as a follow-up in the applier (mirroring the existing cash/depot
  mapping step): every to-be-created security is listed with its ladder
  result, and can be remapped to an existing security instead.
- **Config-at-risk warning (FR-7):** when a to-be-created security
  near-matches an existing one (same name in a different currency, same
  ticker, matching alias candidates) **and** that existing security carries
  stored category assignments, the preview flags it — creation still
  requires the user to pass a visible warning, never a silent duplicate
  that strands configuration.
- Matching never mutates the matched security's master data; a rename in
  the export updates nothing implicitly (the owner edits, journaled, when
  intended).

Hardened by the 2026-07-22 adversarial-review round, equally binding:

- **Stronger-identifier veto:** a weaker-tier match is accepted silently
  only when no stronger identifier is present on both sides with
  *differing* values. A contradicted match (entry ISIN ≠ candidate ISIN,
  or entry WKN ≠ candidate WKN) and any cross-tier disagreement (WKN
  selects security A, ticker+currency selects B) are surfaced as conflicts
  — with the offer to record a §3 ISIN change where that is the likely
  cause — never accepted silently. Without this veto the ladder would
  convert today's safe duplicate into a silent wrong merge (the
  same-name/same-currency share-class case). A tier with zero candidates
  falls through to the next tier.
- **Normalization:** all tier comparisons and alias values use the catalog
  normal form (trimmed, uppercased ISIN/WKN/ticker; trimmed name), applied
  identically to import entries and §6 reconcile identifiers. An entry
  without a currency does not enter the currency-qualified tiers 3–4.
- **Config-at-risk trigger and shape:** the warning covers stored category
  assignments **and position targets (ADR-0030)**; config-at-risk rows
  require a per-row explicit acknowledgment (not just the global apply),
  while plain unambiguous creations are collapsed/summarized so the
  warning rows are the only thing demanding attention.
- **Pre-apply inverse check:** the preview also lists every existing
  config-bearing security (assignments or position targets) that matches
  *zero* entries in the import — a rename that changes ISIN, name, and WKN
  at once fires no similarity warning, but it always leaves such an
  untouched row behind. The panel's instruction: "if one of these was
  renamed/ISIN-changed in PP, abort, record the ISIN change (§3), re-run
  the preview." Leftover surfacing is scoped to securities affected by the
  import, so standing watch-only assignments do not drown the signal.
- **Preview→apply revalidation:** apply re-runs the ladder inside the
  import transaction and aborts back to the preview whenever any entry's
  resolution (or an override's target) differs from what was approved —
  previews live for up to two hours; consent must not go stale.
- **Override durability:** a preview remap whose entry ISIN differs from
  the matched security's current ISIN offers to record it as a §3 ISIN
  change in the same flow, so the decision persists for future imports
  instead of being repeated every time.
- **N:1 resolution:** several file rows may resolve to one security (an
  old and a new ISIN of the same paper in one file); the preview shows one
  merged target, and within one apply run rows collapsing to an identical
  resolved dedup key are deduplicated and surfaced in the result, not
  double-inserted.

  > **Amended by [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html)
  > §6 (2026-09-24):** the in-run key is scoped by the file's account names,
  > `{dedup_key, time, pp_portfolio_name, pp_account_name,
  > pp_counter_portfolio_name, pp_counter_account_name}`. Old and new ISIN of
  > one booking under one account still collapse; two equal rows from
  > different file accounts that resolve to one account (twin fees after a
  > merge) are both inserted.
- **Non-interactive paths fail closed:** no API/MCP import path exists
  today (the applier's "JSON-API entry point" auto-resolve is a stale
  premise — there is no `/api/v1` imports route); if one ships, entries
  the ladder cannot resolve silently (ambiguity, veto conflict,
  config-at-risk) are reported as unresolved (FR-7) and are resolvable
  only via explicit per-entry mappings in the request — never
  auto-created, never auto-matched (AR-11 parity).
- **Implementation note:** lookup structures must be multi-valued
  (grouped); the applier's current single-valued `Map.new` pattern
  silently keeps the last row and cannot express ambiguity.

This answers the mandatory ISIN-less question: crypto and watch-only
positions ride tiers 2–4, and where those are absent or ambiguous the
outcome is a *surfaced decision*, not a silent orphan.

**Rejected:** ISIN-only matching (orphans exactly the ISIN-less positions);
fuzzy/normalized name matching (non-deterministic, and a wrong silent match
is worse than a surfaced miss); introducing a synthetic Portfolixir UUID
that PP exports could never carry (dead weight on the import path).

### 3. ISIN change and rename: a journaled catalog alias, not a ledger kind

This decides the rename/ISIN-change slice deferred by
[ADR-0028](0028-corporate-actions-as-ledger-events.html) §4.

**Recommended: a journaled identifier-alias record in the Catalog
context.** Recording an ISIN change (via UI, API, and MCP — AR-11 parity)
moves the security's current ISIN into a `security_identifier_aliases` row
(`security_id`, `former_isin`, `changed_on`, optional note) and writes the
new ISIN onto the same security row, both in one journaled transaction
([ADR-0017](0017-append-only-audit-journal.html)). The §2 ladder's ISIN
tier consults current ISINs first, then aliases; an alias hit is labeled in
the preview ("matched via former ISIN"). A plain rename needs no alias at
all — it is a journaled edit of `name`, and matching does not depend on the
name when a stronger tier holds.

Guards, made precise by the 2026-07-22 review round:

- **Uniqueness, both directions:** `former_isin` carries a unique index; an
  alias value that collides with any live ISIN (including the owning
  security's own — recording A→A is rejected) or another alias is
  rejected. Symmetrically, **every security-ISIN write path — including the
  import's create path — rejects an ISIN that exists in the alias table**,
  naming the aliased security in the error. The cross-table invariant
  cannot live in one index; it is held as a serialized check inside the
  same journaled transaction as the write. Together this preserves the
  unique-when-present property across current ISINs and aliases, and makes
  "current ISINs first, then aliases" provably unambiguous.
- **Chains and reverts:** a security may carry multiple aliases (A→B→C).
  Recording a change whose new ISIN equals one of the same security's own
  aliases consumes (deletes, journaled) that alias row in the same
  transaction — so a B→A revert works instead of deadlocking on the guard.
- **Correctability:** aliases are not write-once — a journaled alias
  delete/reassign exists at UI/API/MCP parity (AR-11); already-applied
  imports are not retroactively rewired (cleanup is surfaced by the §2
  inverse check). Alias rows ride the security's existing delete guard: a
  security holding transactions or quotes cannot be deleted anyway; where
  deletion is allowed, its alias rows delete with it, journaled.
- **Ordering and repair:** §3 assumes the change is recorded *before* the
  re-import. The wrong order — importing an export that already carries
  the new identity — is defended by the §2 veto and the pre-apply inverse
  check; if a duplicate is created regardless, the repair is: delete the
  duplicated transactions and the duplicate security row, record the
  alias, re-import (the alias-write collision error names the duplicate so
  the repair is discoverable; a journaled security merge stays a named
  follow-up — the securities analogue of #328 — per scope lock). The §4
  round-trip test gains a wrong-ordering variant asserting the conflict is
  surfaced, not silently merged.

  > **Amended by [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html)
  > §9 (2026-09-24):** the journaled security merge named here as a
  > follow-up is decided there. For the wrong-order case, merging the
  > duplicate into the original with the identity choice
  > `adopt_source_isin` (the original takes the new ISIN, its old one becomes
  > the alias) and `collapse_key_equal: true` (the duplicated bookings are
  > deleted with their content hashes retired) is the repair; the manual
  > steps above stand only until that merge ships. It shipped in Sprint 16
  > over the API and MCP (`POST /api/v1/securities/:id/merge`,
  > `portfolixir.securities.merge`); the operator's dialog follows in the
  > same batch.

**Rejected: a first-class ledger kind** (`isin_change`). Unlike a split it
has **no projection effect** — no quantity leg, no cash leg, no external
flow, nothing for any fold to do — so a ledger kind would force every
`effects/1` consumer (AR-7 no-catch-all) to learn a no-op. It is master
data about the security, and the audit journal already gives it the
required traceability. Because the security row itself persists, quote
history, category assignments, and all derived charts continue
uninterrupted — the continuity problem ADR-0028 had to solve for splits
does not arise here. Merger/spin-off (a different security row genuinely
appears) remains the E17 follow-on slice; the alias table is deliberately
shaped so a merger slice can reuse it.

### 4. What "survives" means — the survival contract

Binding enumeration of what a re-import must leave intact, given the
security rows resolve per §2/§3:

- **Classifications:** custom trees, categories, and stored category
  assignments — unchanged rows, same ids. Built-in trees survive trivially
  (derived on read).
- **Target plans:** **all versions** — active, draft, and archived
  ([ADR-0027](0027-plan-versions-and-depot-snapshots.html)), with their
  per-category target weights, names, and statuses. Restricting survival to
  the active plan is rejected: plan history is the point of versioning.
- **Per-view cash targets:** every plan's `cash_target_weight`, including
  the portfolio-wide cash-only plan
  ([ADR-0020](0020-view-bound-soll-plans.html)).
- **Position-level SOLL targets
  ([ADR-0030](0030-position-level-soll-targets.html)):** every position
  row's `(plan, category, security)` and weight — unchanged rows, same
  ids, exactly like category assignments.
- **Leftovers are surfaced, never dropped (FR-7):** a security that ends up
  with stored assignments but no position after the re-import, and every
  entry the ladder could not resolve unambiguously, appear in the import
  result/preview. No automatic deletion, no automatic reassignment.

**Epic acceptance criterion — the golden-path round-trip test:** a
`DataCase` test imports a synthetic fixture, attaches a custom
classification with assignments, a multi-version target plan, a cash
target, and position targets (ADR-0030) on both the to-be-renamed
ISIN-less security and the to-be-ISIN-changed security, then re-imports a
**mutated** fixture (renamed ISIN-less security, one changed ISIN routed
through a §3 alias, drifted decimal formatting) and asserts the surviving
strategy configuration matches **exactly** — Decimal values compared with
`Decimal.eq?`-exactness, ids unchanged, plan versions and statuses intact —
plus the surfaced-leftover assertions above. Companion fixtures required by
the review round: two securities sharing a WKN and two sharing
`(name, currency)` (both surfaced as decisions, neither matched nor created
silently), the wrong-ordering variant from §3, and the §2 preview→apply
divergence abort.

### 5. Sequencing and risk tier

- The named E16 dependency is **satisfied**: Targets/Plans (and
  Classifications, and Catalog securities) journal arming is verified
  landed (see Context). E18 write paths (§3 alias writes, §2 override
  choices that create records) inherit journaled writes from day one.
- Everything touching the applier's matching and idempotency is
  **risk-tier**: dedicated small PRs with real human review (AGENTS.md
  risk-tier exception), not epic-batch content. *(Delivery clause superseded
  2026-08-04 by [ADR-0036](0036-risk-tier-rides-the-batch.html) — risk-tier
  work rides the batch; the idempotency verification below is unchanged and,
  under ADR-0036, becomes the mandatory dedicated review pass.)* The two-layer
  idempotency
  is load-bearing here and must be re-asserted in tests, **in both
  directions** (the review round caught the original sentence describing
  the wrong tier): (a) change recorded, then a *new* export re-imported —
  the new ISIN resolves via the **current-ISIN** tier; content hashes
  drift, the resolved dedup key (#533) keeps it a no-op; (b) change
  recorded, then an *old* export re-imported — the former ISIN resolves
  via the **alias** tier, dedup likewise holds. Both tests assert
  `skipped_duplicates` and zero created securities; the unrecorded-change
  wrong ordering is covered by the §3/§4 variant.
- Order inside E18: the §3 alias slice ships first — **in the same
  risk-tier PR as the ladder's alias-consulting ISIN tier and the
  bidirectional guard** (the alias table must never exist without the tier
  that reads it and the guard that protects it, or a stale export can mint
  a duplicate carrying a retired ISIN in the window) — then the full
  ladder + preview overrides, then the §4 round-trip test closes the epic.

### 6. FR-35 verdict: build the read-only reconcile endpoint

**Recommended: build it** (Story 18.3 proceeds), exactly inside the
boundary pinned in FR-35: the external position list arrives **only** as
user-supplied paste/file content, no network acquisition, no credential
storage, the list is **never persisted**, and the response **embeds the
resolution guidance** ("resolve a difference by booking the missing
transaction of the correct kind; balance snapshots and unpriced deliveries
are last resorts that distort cost basis").

The close-as-documented-procedure outcome was evaluated honestly, as the
epic requires. Its case is real: FR-30 has shipped (verified — holdings
payloads carry ISIN/WKN), so the operating agent can fetch holdings and
compare against a pasted list with no join, and closing costs zero code.
It is **rejected** for three reasons:

1. **The diff is Decimal arithmetic, and NFR-1 says a token predictor does
   not do the ledger's arithmetic.** Per-position quantity deltas computed
   "in the head" of an LLM are exactly the class of silent numeric error
   this project's correctness culture exists to exclude; a pure read-only
   engine computes them exactly.
2. **The guidance must live at the moment of temptation.** FR-35's steering
   text works because it arrives *in the response the agent is looking at*
   when it sees a discrepancy; a procedure document read once (or never) at
   session start does not. FR-32 extends the same warning into the
   `set_balance`/delivery tool descriptions — the reconcile response is the
   third leg of that same defense.
3. **It is the first non-import consumer of the §2 ladder.** External lists
   carry the same messy identities (ISIN-less crypto lines, stale ISINs);
   matching them through the identical ladder — alias hits included —
   dogfoods FR-34's mechanism and keeps one identity semantics, not two.

Shape (binding for Story 18.3, hardened 2026-07-22):
`POST /api/v1/holdings/reconcile` plus an MCP tool at AR-11 parity.

- **Request:** rows of `identifier` + `quantity` (optional `currency`,
  optional explicit `security_id` to pin a match); quantities are
  canonical dot-decimal Decimal strings (any other format is a 422 —
  locale parsing is the client's job); an empty row list is a 422; an
  optional portfolio/view scope parameter bounds the compare (default: the
  whole instance, stated in the response basis).
- **Identifier typing:** a string that validates as an ISIN enters tier 1
  only; anything else is tried per tier in ladder order with the §2
  exactly-one rule applied **across the union of the remaining tiers** — a
  string matching one security's WKN and another's ticker is ambiguous,
  never a pick; a currency-less row cannot enter tiers 3–4 and is reported
  unmatched rather than guessed.
- **Response per row:** the ladder-matched security, the **matched tier**
  (`matched_via`: `isin` | `former_isin` | `wkn` | `ticker` | `name`),
  ledger quantity, external quantity, and delta as Decimal **strings**;
  tier-3/4 matches carry an explicit weak-match caveat inside the guidance
  ("confirm the security before booking"); ambiguous rows carry an
  `ambiguous` status with the candidate securities. Rows resolving to the
  same security are aggregated (external quantities summed, noted in the
  response) so an agent never sees two contradictory deltas for one
  position.
- Unmatched external rows and ledger positions absent from the list are
  both surfaced, per FR-7, alongside the embedded guidance block.
  Read-only, gap-marker contract (AR-4), synthetic fixtures only.

## Consequences

- Positive: strategy configuration stops being disposable — the golden-path
  re-import preserves it by construction, with every unresolvable case
  surfaced instead of silently duplicated; the alias record closes
  ADR-0028's rename/ISIN slice without touching projection semantics; the
  reconcile endpoint turns discrepancy handling into exact, guided,
  bookable facts for the MCP-first operator.
- Negative / accepted: the ladder adds matching complexity and a new
  master-data concept (aliases) to the Catalog; tiers 2–4 remain weaker
  identities and an ISIN-less security renamed *and* re-tickered in PP will
  still surface as "decide me" in the preview — deliberate, since the
  silent alternative is worse. The preview grows a security-mapping step
  (more UI surface, mirroring the existing account mapping), plus the
  per-row config-at-risk acknowledgment and the untouched-config inverse
  check added by the review round.
- Fresh-database restore of strategy configuration is explicitly **not**
  solved here — and no longer needs to be: FR-29 as rescoped (owner
  decision 2026-07-22, #354) covers it with the documented `pg_dump`
  backup/restore, ids preserved verbatim, no identity mapping involved.
  Data egress for external consumers is the JSON API.
- Import-idempotency and matcher changes are risk-tier throughout (§5);
  weakening either dedup layer to make a batch pass is a review reject.
- **Review status:** the three-method adversarial review round (red team
  vs. blue team, pre-mortem, edge-case walk; ADR-0028 precedent) ran on
  2026-07-22. All six decisions survived as decisions; the confirmed
  findings — ADR-0030 position targets in the survival contract, the
  stronger-identifier veto, the bidirectional alias guard with
  same-PR-as-tier sequencing, the wrong-ordering repair path, the
  pre-apply inverse check, preview→apply revalidation, the hardened
  reconcile request/response contract, identifier normalization, and the
  FR-29 rescope wording — are applied to the sections above. The draft is
  review-hardened and ready for owner sign-off.

## Amendment: injective identity keys, and a refund books with its row (2026-09-25, E25 S5)

Two identity keys of this record joined their fields with an unescaped `|`:
the content `import_hash` (#533) and the preview's security reference key
(§2). A separator moved from one field into its neighbour gave two different
rows one hash, so the second was skipped as already imported, and two
different references one key, so one preview decision applied to both
(security triage 2026-09-24, F36; risk-tier: idempotency, ADR-0036).

- **The content hash stays byte-identical for every row without the
  separator in a field** — such a join has one reading — so every hash
  stored for such a row stays valid. A row with the separator in a field is
  hashed over its length-prefixed fields behind a leading byte no joined form
  begins with (`Portfolixir.Imports.ImportHash`), and also consults the hash
  the joined formula gave it, so a row stored before the change is still
  recognised. That lookup is ambiguous by construction; it errs towards
  "already booked" (nothing books twice), matches only rows stored before
  the change, and the result lists the row it skipped.
- **The reference key is length-prefixed per field**, an absent field marked
  as such. It lives only as long as a preview, so no stored value depends on
  its form. One key standing for two references **fails closed**: both are
  a decision no choice settles, and the apply is refused.
- Pinned by `import_hash_test.exs` (a digest computed with the Sprint 15
  formula) and `import_hash_reimport_test.exs` (a re-import of a row stored
  under that formula books nothing; two rows that joined to one string both
  book; two references that joined to one string resolve separately).

**A split-off tax refund books with its row** (F37; risk-tier: idempotency).
The parsers split a negative tax of a row into a `tax_refund` companion
entry. It used to be hashed as a row of its own, so two different rows with
equal refunds (one date, account, security and amount) gave their refunds one
hash, and the second refund was skipped as already imported.

- A companion's hash folds in its parent's hash and its position among the
  parent's companions (`ImportHash.companion/4`), so equal refunds of
  different rows hash apart.
- A companion is **judged by its own identity, with its parent** (amended
  by the S5 review round, 2026-09-25). The parent's hash and economic key
  leave the split-off refund out — the parsers move the negative tax off the
  row — so the parent's outcome cannot say whether the refund is booked.
  Once its parent was imported or found already booked, a companion is
  skipped when a transaction or a merge holds its own hash or the hash the
  Sprint 15 formula gave it as a row of its own, or when a booking stored
  before the run has its economic key; it collapses onto an earlier
  companion of the file only when its parent collapsed onto that
  companion's parent (the in-run key alone would take two equal refunds of
  two different rows for one); otherwise it books. A companion of a row
  that is not imported (unimportable, an internal transfer, an undecided
  security) is skipped with it and names that row. The preview counts a
  companion by the same hashes.
- So a re-import books nothing twice — a refund stored under either formula
  is found by its own hash, and a drifted export's refund by its economic
  key — a row deleted by hand books again without its refund, and a refund
  added in Portfolio Performance to a row already imported books on the next
  import.
- What this does not repair, the closed direction: a refund the Sprint 15
  formula skipped wrongly is not booked by a re-import, because its twin
  holds the hash that formula gives both; a standalone refund row with the
  same fields holds that hash too; and a corrected refund amount on a row
  already imported books as a new refund beside the old one.

**Within-file duplicates collapse, and this is deliberate.** A row that
repeats an earlier row of the same file exactly holds the same content hash:
the first copy books, and the repeat is reported as already booked (layer
`hash`) with its companions. Rows that differ in the file but resolve to one
booking (§2's N:1 case) collapse on the in-run key of ADR-0050 §6, scoped by
the file's account names and the time of day. Two genuinely separate
bookings that a Portfolio Performance export renders identically — the same
kind, date, time, security, amounts and accounts — therefore book once; the
result names the collapsed row, so the operator can book the second by hand.
Pinned by `companion_hash_test.exs` (two different parents with equal refunds
book both; a companion stored under the Sprint 15 formula is recognised on
re-import; a companion is skipped with a parent that is not imported; a sale
deleted by hand books again alone, its refund stored under either formula; a
refund added to a sale already imported books on the next import; a
re-export whose sale drifted books no refund twice; a collapsed row's refund
collapses with its twin's, and books when its twin has none).

## References

- [ADR-0006](0006-classifications-with-target-weights.html) — built-in trees derived on read; custom assignments stored
- [ADR-0017](0017-append-only-audit-journal.html) — journaled writes the alias record and overrides ride on
- [ADR-0020](0020-view-bound-soll-plans.html) — view-bound plans and the cash target that must survive
- [ADR-0026](0026-epic-batch-workflow.html) — decision-gate workflow this ADR follows
- [ADR-0027](0027-plan-versions-and-depot-snapshots.html) — plan versions (all of which survive per §4); E16 journal arming verified landed
- [ADR-0028](0028-corporate-actions-as-ledger-events.html) — §4 defers the rename/ISIN-change slice decided in §3 here
- [ADR-0030](0030-position-level-soll-targets.html) — position-level SOLL targets keyed to securities; part of the §4 survival contract
- FR-34/FR-35 — section H in `_bmad-output/planning-artifacts/epics.md`; FR-29 — rescoped 2026-07-22 to documented `pg_dump` backup/restore, PP export dropped (#354); FR-30 — shipped ISIN/WKN holdings payloads (#582); FR-7 — surfaced import gaps
- `Portfolixir.Imports.Applier` — current matching and the two-layer idempotency (#533) this decision hardens
- Epic tracking: E18 in the Tracker Index of `_bmad-output/planning-artifacts/epics.md` (the Epic Detail sections it formerly pointed at were removed by ADR-0042; this ADR is the spec). Section H of the Requirements Inventory is unaffected and still carries FR-34/FR-35
