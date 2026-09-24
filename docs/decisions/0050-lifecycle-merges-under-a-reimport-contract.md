---
layout: docs
title: "ADR-0050: lifecycle merges — rename, merge and delete for cash accounts and depots, and merge for duplicate securities, under a post-merge re-import contract"
description: "Decision for #328 and #608, taken together because they are one operation over two reference graphs and one risk. A merge relabels every reference to a source onto a target of the same kind, removes only rows that are provably void, provably duplicate, or made redundant by a declared restatement, retires the import hash of every row it removes, and records the source's identity as a remembered identity of the target, so a re-import of the same or a later Portfolio Performance export creates nothing that was merged away and lands new rows on the target. A rename is the degenerate merge. The importer checks the content hash before it resolves or creates anything, and creates accounts lazily. What a merge cannot keep exact (research notes, rule versions, differing currencies, differing view membership, an identity the ladder could no longer find) is refused with a named reason, never guessed."
---

# ADR-0050: lifecycle merges under a post-merge re-import contract

- **Status:** Accepted (design gate for #328 and #608 per
  [ADR-0026](0026-epic-batch-workflow.html), risk-tier under
  [ADR-0036](0036-risk-tier-rides-the-batch.html) on three counts:
  reassignment, import idempotency, and money and quantity identities). The
  owner signs it by merging the Sprint 16 planning PR (step 1 as amended on
  PR #780: the merge is the signature).
- **Date:** 2026-09-24
- **Answers:** #328 and #608. §15 lists the asks it answers and the ones it
  defers, per [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html).
- **Amends:** [ADR-0029](0029-stable-identities-and-reimport-survival.html)
  (§13 below says where). [ADR-0017](0017-append-only-audit-journal.html) gains two
  resource codes, and its quote exemption names the merge writer (§13). [ADR-0044](0044-security-knowledge-as-an-append-only-log.html),
  [ADR-0049](0049-policy-rules-as-first-class-objects.html) and
  [ADR-0028](0028-corporate-actions-as-ledger-events.html) are **unchanged**:
  the refusals in §9 exist so that they can stay unchanged.
- **Opens nothing else.** No scope gate is touched. Cross-portfolio moves,
  unmerge and merger/spin-off stay out (§14).

## Context

The 2026-09-23 backlog triage set Sprint 16's runway, and it names the
lifecycle merges as the last operator-facing gap with a spec: "#328 + #608
under **one** ADR (risk-tier: reassignment and import idempotency)". ADR-0029
§3 already names "a journaled security merge" as the follow-up to its manual
repair (delete the duplicated bookings, delete the row, record the alias,
re-import).

**One hazard is live today, with no merge involved.** `PATCH
/api/v1/cash_accounts/:id`, `PATCH /api/v1/securities_accounts/:id` and the
matching MCP `*.update` tools rename an account. The importer matches accounts
by exact name and remembers nothing between imports, and it creates every
`create`-mapped account **before** it looks at a single row. So the next
import of an export that still carries the old name creates an empty
"zombie" account under that name. If the export drifted (a changed decimal
precision, an edit inside Portfolio Performance), the rows miss the content
hash, resolve to the zombie, miss the economic dedup key of #533 (which is
built from resolved ids) and **book the history a second time**. ADR-0029's
sentence that account renames "are covered by the existing user-driven mapping
step" holds only while the operator remaps by hand on every import.

The situations the design must handle, as synthetic examples:

1. **An obsolete account.** A EUR cash account "Savings (old)" was emptied long
   ago but carries years of history. The operator wants the history under
   "Savings" (EUR) and the old account gone. Portfolio Performance still has
   both.
2. **A rename zombie.** An agent renamed "Giro" to "Main account" over the API.
   The next import created an empty "Giro", or, with a drifted export, a
   "Giro" with a second copy of the history.
3. **A wrong-order ISIN duplicate** (ADR-0029 §3). "Fund X" was imported under
   its old ISIN. An export carrying the new ISIN was imported before the change
   was recorded, and created a second "Fund X" with a full second copy of the
   history. Holdings, cost and income are doubled, and recording the alias
   collides with the duplicate's live ISIN.
4. **Two depots at one broker**, with transfers between them, that should
   become one.
5. **A hand-made duplicate security**: an agent created it over MCP, and the
   next import created the same instrument again.
6. **A foreign-currency account** that must never be merged into a EUR one.

What exists: rename paths for all three entities (the cash-account and security
paths today also accept a new `currency_code` on booked records; a depot
carries no currency), delete paths that refuse referenced
rows (the account deletes refuse only in a pre-check, which a race turns into a 500), silent
database cascades on bucket links, position overrides and category
assignments (which contradict ADR-0017 and ADR-0024 point 4), **no merge
anywhere**, and no account rename or delete control in the UI.

## Decision

### 1. One mechanism for three entities

A **merge** of a source S into a target T of the same kind is a relabelling:
every reference to S is re-pointed to T, or resolved by a declared rule that
the preview shows. Only three kinds of ledger row are removed:

- rows that are **provably void**: a transfer whose two legs become one
  account;
- rows that are **provably duplicate**: a source row whose #533 key, rewritten
  onto T, equals a target row's key, and only when the operator explicitly
  chooses to collapse them (§8);
- rows **made redundant by a declared restatement**, each listed in the
  preview: on a day where both accounts carry balance anchors, every anchor of
  that day except the target's last, which absorbs them (§7); and in a security
  merge, the source's split where the target carries the same split on the same
  day in the same portfolio (§9).

Every removed row's `import_hash` is **retired** (§3). Rows of the third kind
hold none, because anchors and splits are never imported, and the §3 writer
sweep asserts that no `balance_adjustment` or `split` row carries one. S's import identity
becomes a remembered identity of T: a former name for an account, an ISIN
alias or an adopted identifier for a security. S is then deleted through the
hardened delete path (§11), and one append-only merge record is written
(§12).

A **rename** is the degenerate merge: nothing moves, and the old name becomes a
former name of the same account. A **delete** stays "only when unreferenced".

*Reason.* #328 and #608 are one operation over two reference graphs. One model
gives one idempotency argument instead of three, and rename and merge share the
identity writer the importer reads.

### 2. The post-merge re-import contract

An import inserts a file row only if (1) its content hash is held neither by a
live transaction nor by a retired hash, (2) it resolves without a decision the
preview surfaced, (3) its resolved #533 key is not in the portfolio's
pre-import key set, (4) it is not an internal transfer (§5), and (5) it is not
collapsed inside the run (§6).

Every merge discharges three obligations:

- **O1, hash retention.** The set of hashes held by transactions or retired
  hashes only grows. Moved rows keep their `import_hash`. Every removed row
  leaves its hash retired.
- **O2, resolution relabelling.** Every identifier through which S resolved
  before the merge resolves to T after it, and nothing else changes
  resolution.
- **O3, key relabelling.** For every existing importable key, its rewrite onto
  T is still in the key set, or it has become an internal transfer.

From these it follows that **a file already applied is a no-op after any
sequence of renames and merges** (zero transactions, zero accounts, zero
depots, zero securities), and that **rows of a later file that name S's
identity are inserted on T**. These two sentences are #328's acceptance
criterion, and the tests in §16 pin them.

Three limits are stated, not hidden:

- **Identities the database never saw** fall outside O2. Account names are
  hash inputs (§3), so a Portfolio Performance-side rename makes every row that
  names the account a hash miss, drifted or not. To a name the database never
  saw, the preview prefills `create`, and the account's **whole** history would
  duplicate under that name; that much is pre-existing and independent of
  merges. To a name that is live or former on a *different* account, the
  prefill names that account, looks legitimate, and the history would land
  there a second time; the former-name half of that case arrives with §4. The
  remedy is remapping onto the right account in the preview, remembered (§4)
  where the guard allows it. A name renamed before the accounts' journal was
  armed, and so absent from §4's backfill, is in the same position. A probe
  that fails closed is deferred (§15).
- **The pre-import economic layer keeps set semantics.** After an account
  merge, a hash-miss row from S whose key equals an existing T row's key is
  absorbed at the economic layer. It is **reported** in the result's duplicate
  list with the layer `economics`, never silent. Making that layer one-to-one
  touches the most sensitive part of #533 and is deferred with its evidence
  (§15).
- **A restated anchor absorbs later backdated rows.** A row of a later file
  that lands on T dated on or before an anchor a merge restated (§7) is
  inserted, but that anchor absorbs its amount. It is **reported** in a
  `behind_restated_anchor` list that names the anchor, never silent.

### 3. The importer checks the hash first, and retired hashes count

- The content-hash check moves **ahead of all resolution**. A row whose hash is
  held by a transaction or a retired hash is reported as a duplicate (layer
  `hash` or `retired`) and triggers no security, cash or depot resolution, no
  creation and no insert. The hash covers only file-side fields plus the
  portfolio, so it can be computed before anything resolves.
- Decisions the operator made in the preview (an ISIN-change override, a
  remembered remap) are executed **from the mapping at apply start**, not from
  the first row that reaches them, so they still take effect when every row of
  their key is a hash hit.
- A new table `retired_import_hashes` holds `import_hash` (unique),
  `former_transaction_id`, `merge_record_id`, `reason`
  (`internal_transfer` or `collapsed_duplicate`),
  `superseded_by_transaction_id` and `inserted_at`. It is **append-only**
  (triggers refuse UPDATE, DELETE and TRUNCATE), journal-armed, and written by
  merges only.
- A `BEFORE INSERT` trigger on `transactions` refuses a retired hash, as the
  database backstop beside the existing unique index. Both writers of
  `import_hash` (the applier and `Ledger.create_transaction`'s option) are
  swept by a test, which also asserts that neither writer puts a hash on a
  `balance_adjustment` or `split` row.

*Reason.* This is O1. Without it, deleting an internal transfer deletes its
hash, and a later import either re-inserts it against a zombie or builds a
transfer with equal legs that fails its CHECK and rolls back every future import
of that export.

### 4. Accounts are created lazily, and remember their former names

- A `create`-mapped (or unmatched) cash account or depot is materialized on
  the **first row actually inserted**, never up front. A choice whose rows are
  all skipped creates nothing, and the import's bucket tag touches exactly the
  accounts created. For a rename made before this record, a byte-identical
  re-import now creates nothing; newer and drifted exports are covered by the
  backfill below.
- `cash_accounts` and `securities_accounts` gain `former_names text[] NOT NULL
  DEFAULT '{}'`. Both tables are already journal-armed, so every change is
  journaled with its before and after.
- **Renames made before this record are backfilled.** The migration that adds
  `former_names` replays every journaled update of a cash account or depot
  whose name changed, in journal order, through the writer rules below, so
  renaming back consumes a name and a name another live account carries is not
  recorded. A name the guard would refuse is reported by the migration and not
  written; typically it is refused because a zombie already carries it as its
  live name, and that zombie is repaired by merging it into the renamed account
  with collapse (§8). A rename older than the accounts' journal arming leaves no
  trace to replay; that limit is stated in §2.
- **Writers of former names:** every rename appends the previous name
  (renaming back consumes it), except when another account of the kind in the
  portfolio still carries that name as its live name: then nothing is
  recorded, because that name already resolves to the other account. This is
  what makes renaming one of two same-named accounts the remedy for an
  ambiguous name; a merge appends S's name and S's former names to T,
  skipping T's own live name, so merging two same-named accounts records
  nothing and ends their ambiguity; and a **remembered remap** appends a
  Portfolio Performance name X to account Y when the operator maps X onto a
  differently named Y in the import preview with "remember" set, which is **on
  by default**. When X is already a former name of another account,
  remembering **moves** it to Y (the guard below forbids one former name on two
  accounts), and the preview says so before the import is applied. When X is
  still the live name of another account, "remember" is not offered for that
  name, and the preview says why and names the remedy (merge or rename that
  account), so the default never makes an apply fail.
- **Resolution** is one function used by the preview's prefill and by the
  applier: exact live name first, then former name. An ambiguous tier yields
  **no prefill**, and apply refuses the name unmapped. That fails closed and
  replaces today's last-wins map.
- **A name guard on every writer** (API, MCP and UI create, the importer's lazy
  creation, seeds, rename, merge, remembered remap): a live name may equal
  neither another live name nor a former name of the same kind in the
  portfolio, and a former name may equal neither a live name nor another
  account's former name. The guard runs under a transaction-scoped advisory
  lock for account identity. There is **no unique index**: existing duplicate
  names would have to be migrated before one could exist, and a former name
  sits in an array that no plain unique index keeps distinct across rows or
  from another account's live name. So the guard is the single enforcement
  point, every writer passes through it, and the lock serializes it. Existing
  duplicate names are not migrated; the guard refuses new ones, and resolution
  treats old ones as ambiguous.
- Former names are listed and removable, journaled, on UI, API and MCP. The
  removal confirmation says what it costs: "An import that still names
  '<name>' will then create a new account." The rename confirmation, and the
  MCP rename tool's description, say which case applies: the previous name
  stays a former name of this account, or, while another account of the kind
  still has it as its live name, it is not kept, and an import naming it books
  to that other account.

*Reason.* This is O2 for accounts and the "remembered mapping" #328 asks for.
Storing names on already-armed rows needs no new table. The guard on **create**
closes the hole where a new account under a former name would re-route an old
export and double its history.

### 5. Internal transfers are void

- **Import:** a `cash_transfer` or `security_transfer` whose two legs resolve
  to one account is skipped **unconditionally** and reported in a new
  `internal_transfers` result list. It never aborts the import.
- **Merge:** transfers between S and T are deleted per row, journaled, with
  their hashes retired as `internal_transfer`.

*Reason.* Such a row can never be inserted (its CHECK rejects equal legs), so
the rule turns a guaranteed whole-import rollback into a reported skip. It
cannot drop an insertable row, so no dedup layer is weakened. The rows are
economically void.

### 6. The in-run collapse key is scoped by the file's account names

The in-run key becomes `{dedup_key, time, pp_portfolio_name,
pp_account_name, pp_counter_portfolio_name, pp_counter_account_name}`. The
pre-import economic layer is unchanged. ADR-0029 §2's N:1 collapse (old and new
ISIN of one booking under one account) keeps collapsing. Two rows from
different Portfolio Performance accounts that resolve to one account are never
collapsed.

*Reason.* After a merge, S and T often both still exist in Portfolio
Performance. Two new same-day rows with the same economics, one from each
(identical monthly fees, twin savings plans), would otherwise collapse into one
insert: a silent under-import that breaks #328's forward-routing criterion.

### 7. Cash-account and depot merge

**Cash guards** (each answers 409 and writes nothing): same portfolio (the
composite foreign keys require it), same `currency_code`, same
`liquidity_role`, equal view-bucket sets, not the same account, both live.

**Cash steps**, in one database transaction under the account-identity lock and
`FOR UPDATE` on S and T in id order:

1. recompute the plan and compare its digest (§10);
2. delete the S↔T transfers and retire their hashes;
3. handle **key-equal pairs** (§8). A `balance_adjustment` never enters a pair,
   because step 4 folds anchors;
4. **restate balance anchors**: every `balance_adjustment` of one side becomes
   its stated amount plus the other side's end-of-day balance on that date,
   computed from the Ledger projection over the other side's **kept rows** (its
   pre-merge rows less the source rows step 3 collapsed; never from derived
   values, ADR-0039 I7). Anchors replay last within their day, so the merged
   running balance and each anchor's external-flow residual stay exact **at
   the merge**. On a day where both sides carry anchors, the target's last
   anchor becomes the sum of both sides' last anchors, and the others of that
   day are deleted, journaled. The Portfolio Performance importer never
   produces anchors, so restatement touches no hash and no key. A restated
   anchor turns a balance that was partly derived into a stated one, so a row
   inserted on T later and dated on or before it is absorbed by it (ADR-0009):
   the preview lists every restated anchor with its date, and an import reports
   such a row in `behind_restated_anchor` (§2);
5. re-point every row, S's linked depots included, per row and journaled;
6. run the **linearity check**: T's balance equals the fold of S's kept rows
   plus the fold of T's kept rows, each under its own pre-merge anchors, at
   every date either side has a row and today, `Decimal`-exact. Otherwise roll
   back with `identity_check_failed`. This is a bug catcher, never an expected
   answer;
7. remove S's bucket links journaled, delete S (§11), then append S's names to
   T's former names (skipping T's own live name, and checked by the guard after
   S is gone, so S's own names never count against it), and write the merge
   record.

**Depot guards:** same portfolio, not self, both live, equal default
view-bucket sets, and **unchanged effective view membership** for every
position: for each security, wherever T holds rows of it, S's effective set
must equal T's, and S's override, now redundant, is dropped; where T holds no
rows of it, S's effective set is carried onto T (S's override moves). Any other
difference refuses, naming the positions, because moving an override onto a
position T already holds would re-view T's own history. **Depot steps** mirror
the cash steps with `security_transfer`, and T keeps its own linked cash
account. The depot linearity check: at every date, T's quantity per security
equals the fold of both depots' pre-merge rows, less collapsed rows, in which
each split scales the combined position once. Before the first split that is
the sum of both quantities; from a split on, ADR-0028 §3 rounds the combined
position once, and the result can differ from the sum of the two separately
rounded positions by one unit of the volume scale per split. That difference is
expected, not a check failure, and the preview lists it per position and split
date. The preview also shows each affected position's quantity, moving-average
cost and realized result before and after; cost basis is legitimately
restated, because lots combine.

*Reason.* #328's criteria: the same-currency guard, affected counts, balances
of both accounts before and after, and the affected positions. It keeps the
UAT identity "sum of both balances equals the merged balance, total value
unchanged" for a merge without collapse; with collapse, the only difference is
the collapsed rows, and the preview lists them. Moving `{:set}` anchors unchanged would erase T's history. View
membership is retroactive (ADR-0024 point 4), so a merge must never move history
between views behind the operator's back.

### 8. Key-equal pairs are collapsed only by explicit choice

A source row other than a balance anchor or a split whose #533 key, rewritten
onto the target, equals a target row's key is paired with it one-to-one, lowest
id first. When pairs exist, apply
**requires** an explicit `collapse_key_equal` choice (the API answers 422
without it, and the UI radio is not preselected). `true` deletes each paired
source row, journaled, and retires its hash with reason `collapsed_duplicate`
and `superseded_by_transaction_id` set to its paired target row; `false` moves
them. For the rename zombie and the wrong-order ISIN duplicate, the pairs are
the whole copy, and collapsing them is the repair.

*Reason.* Collapse deletes bookings, so nothing is assumed.

### 9. Security merge

**Guards** (each answers 409 and writes nothing): not self, both live, same
`currency_code`, equal `is_benchmark`, the target not retired while the source
is live, equal `treat_quotes_as_raw` whenever the source has quotes,
unchanged effective view membership, **no policy rule version naming the
source** (answered in ADR-0049 §8's shape, naming the rules), and **no
research notes on the source** (ADR-0044 §3: notes can neither move nor
vanish).

**Rows:** key-equal pairs as §8, **splits excepted**. The #533 key carries no
split ratio, and a portfolio holds at most one split per security and day (a
unique index), so a split can never be moved onto a target's split and never
enters §8's pairing or its choice. A same-day, same-ratio split in the same
portfolio always collapses, journaled and listed in the preview, whatever
`collapse_key_equal` says; a different ratio refuses before anything is
paired. A **linearity check** per portfolio, depot and date: the merged
quantity equals the fold of the target's pre-merge rows plus the fold of the
source's kept rows, each under its own pre-merge split set, except that a
collapsed split scales the combined position once (the rounding difference of
§7's depot check applies and is listed); any other difference refuses, naming
the split date. This catches a target-side split that would rescale moved rows
(ADR-0028 §1).

**Split events.** ADR-0028 §2 derives one split-event set per security from its
split rows in every portfolio, and every raw close, the trade-price fallback
and the valuation walk rebase on that set. The merged set is the union of both
sides' sets, so the merge refuses when the union carries an event that one side
lacks while that side has a transaction or a quote dated before it. The refusal
names the event and the side that lacks it; the remedy is to book the split on
that side first (ADR-0028 §1) or to delete the wrong row. The same rule refuses
one split booked on two dates and two ratios on one day in different
portfolios. The per-portfolio linearity check cannot see this, because the
moved quantities stay exact while the prices change.

**Quotes (gap-fill):** the source's quotes on dates the target lacks move,
each keeping its `source` and therefore its ADR-0028 §2 basis. On a collision
date the target wins; the source's date, close and source are recorded in the
merge manifest, and colliding **manual** quotes are listed in the preview.
Both securities' quote invalidation runs.

**Configuration** (every change journaled and listed, across active, draft
and archived plans): category assignments move where the target has none in
that classification, otherwise the target's wins; position targets are then
evaluated against the target's resulting category (moved, or deleted and
listed where they would collide or go stale); position bucket overrides follow
§7's membership rule per depot, with the target security's position in that
depot read as T's and the source's as S's; security events move and same-kind, same-date pairs are
listed as possible duplicates; identifier aliases are reassigned.

**Identifiers**, under the existing ISIN lock: the source's ISIN is cleared
first, then written according to the operator's **identity choice** when both
carry one. That choice is **required and never preselected**, exactly like
§8's collapse choice (the API answers 422 without it): `keep_target_isin` (the
source's ISIN becomes an alias of the target) or `adopt_source_isin` (the
ADR-0029 §3 wrong-order repair: the target takes the new ISIN and its old one
becomes the alias). The alias's `changed_on` is the operator's date for the
ISIN change when they give one, and the merge date otherwise. WKN, ticker and feed are
adopted onto the target only where it lacks them. Name, asset class and logo
follow the target, and every difference is listed.

**Resolvability precondition**, run by the preview and again before commit:
the identity ladder over the post-merge catalog must resolve to the target,
for **both** pre-merge securities, the stored identity **and the as-imported
identity** (the name, ISIN, WKN, ticker and currency the importer's journaled
create recorded, plus every former ISIN). A file resolves on the identity it
carries, not on identifiers added since, so a ticker the operator added after a
name-only import cannot vouch for rows whose file lacks it. A security with no
importer create entry is checked on its stored identity. Otherwise the merge
rolls back with `identity_unresolvable`, naming the identifier. So a merge of two
ISIN-less securities whose identifiers cannot be kept resolvable is **refused in
v1**; generalized WKN, ticker and name aliases are deferred (§15).

**The reverse direction.** A refusal whose cause sits on one side only (notes or
rules on the source) is often lifted by merging the other way. The preview
therefore also evaluates the reverse direction's guards and reports whether it
is mergeable, so a refusal can name "merge the other way" as its remedy only
when that remedy is real.

*Reason.* #608's scope sketch and ADR-0029 §3's follow-up. Refusing notes and
rules keeps two append-only or immutable records intact without amending them.
The resolvability check is what makes "no duplicates on re-import" hold for
every accepted security merge without a new alias kind.

### 10. Consent, locking and staleness

- The **preview is a read** and returns a `plan_digest`: a hash over both ids
  and their `updated_at`, the sorted row ids per action with each row's
  `updated_at` (the key-equal pairs of §8 as a set of their own), every figure
  the preview shows, and the guard results. The operator's choices (§8's
  `collapse_key_equal`, §9's identity choice) are **neither preview inputs nor
  part of the digest**: the preview states the outcome of each value of each
  choice (the balances or positions after either collapse value, the
  identifiers after either identity choice), so one pair has one digest. Apply
  takes the digest and the choices and answers 422 when either is missing. It
  then takes its locks in a fixed order, recomputes the plan, and answers 409
  `plan_changed` with the fresh preview on a mismatch, so an edit to a booking
  of either side between preview and apply is a mismatch, not a silent
  restatement. Only after the digest matches does it apply the choices.
- Retrying a completed merge of the same pair returns the original merge record
  (200) and journals nothing. A source already merged into another target
  answers 409 `already_merged`.
- An import whose mapping names an id that has since been merged away aborts
  at apply start with `resolution_diverged` and the survivor's id. An import
  that races a merge fails its first insert on a declared foreign-key
  constraint, rolls back whole and asks for a fresh preview.

*Reason.* ADR-0029 §2's preview-to-apply revalidation, applied to merges:
every race ends in a clean 409, never a 500, and the counts and figures applied
are the ones approved.

### 11. Rename is name-only, identity fields freeze, deletes stop cascading

- At changeset level, so **every writer** is covered (API, MCP and UI edits,
  including the search dialog's "merge into existing", which can write a
  listing's currency onto an existing security; the importer's creates;
  seeds): a cash account's `currency_code`
  freezes once any transaction or linked depot references it; an account's or
  depot's `portfolio_id` freezes once it is referenced; a security's
  `currency_code` freezes once it has a transaction or a quote. Each answers
  422.
- **Delete:** an account or depot is deletable only when no transaction
  references it through either leg and no depot links to it; otherwise 409 with
  `referenced_by`, `remedy: "merge"` and the preview route. Before any row is
  deleted, its bucket links, position overrides and (for a security) category
  assignments are removed through their **journaled** context functions. No
  cascade removes a membership silently. The row is locked `FOR UPDATE`, and
  the delete declares its foreign-key constraints, so a race answers 409.

*Reason.* Today's "rename" can silently re-denominate booked history, and a
currency flip would bypass the merge's same-currency guard. The Sprint 15
lesson applies: an invariant is swept over every writer of the table.

### 12. The merge record, and what a merged-away id answers

- A new table `merge_records` holds `kind`, `source_id` and `target_id` (no
  foreign key: ids are never reused, and a target can later be merged away
  itself), `portfolio_id` (null for securities), a `source_snapshot`, a
  `manifest` (per table, every row moved, restated, deleted, collapsed,
  re-pointed or dropped, the values of dropped colliding quotes, and the
  operator's choices), the `plan_digest`, the actor and `inserted_at`.
  `UNIQUE (kind, source_id)`, append-only by trigger, journal-armed.
- `GET /api/v1/merges` and its MCP tool list the records. #328 puts "undo or
  history for the merge" out of scope; this read is not that feature but the
  audit read of a destructive write (ADR-0017), and the record exists anyway
  for §10's retry and the `merged_into` answer below. The read ships
  agent-first: the operator sees a merge on the survivor ("merged from …") and
  as a former name on Accounts & depots, and a list view lands **no later than
  Sprint 17** under the two-way deadline, which the close-out records. A read
  of a merged-away id answers **404** with `merged_into {kind, id}`, following
  the chain to its live end.
  `/securities/:id` and a benchmark parameter naming a merged-away security
  redirect to the survivor with a notice.
- There is **no unmerge**. The manifest plus the journal's before-images make
  every merge reconstructable by inspection.

### 13. Journal, derived values, and the records this amends

- One database transaction per merge, and one `Journal.record` per moved,
  restated or deleted row of a journaled table. No `update_all`. Two families
  follow their existing records instead: quotes are written by the merge
  writer, which ADR-0017's quote exemption names beside the sync writers once
  the 2026-09-24 security triage's T-9 narrows that exemption. Each moved or
  dropped quote is written row by row without a journal entry and appears in
  the merge manifest (§12); the manifest is its audit record, and the values
  of dropped colliding quotes are its before-image. Each is invalidated
  explicitly;
  bucket links and position overrides go through their context functions,
  which journal one aggregate entry per account or position. A new `reassign_changeset` casts
  only the foreign-key columns (plus the anchor amount), declares the
  composite-key and CHECK constraints, and does **not** re-run the public
  changeset's validators, which is safe only because the same-portfolio and
  same-currency guards leave every validator's inputs unchanged. The merge
  writer still asserts distinct legs, one portfolio and one currency on the
  columns it writes.
- ADR-0017 gains the resource codes `merge_record` and `retired_import_hash`;
  its operations stay `create`, `update`, `delete`, `upsert`. A moved row bumps
  the union of its before- and after-radius (#851), quotes are invalidated
  explicitly, and the merge module joins ADR-0039 I7's meta-test scope.
- **ADR-0029 is amended** in five places: its Context sentence on account
  renames; the hash check moves ahead of resolution and consults retired
  hashes; the in-run key is scoped (§6); account resolution gains the
  former-name tier (§4); and §3's manual repair now points at the merge
  (`adopt_source_isin`).

### 14. Foreign-key completeness, and what stays out

**A backstop.** An invariant test enumerates, from `pg_constraint`, every
foreign key whose target is `securities`, `cash_accounts` or
`securities_accounts`, composite ones included (22 today), and asserts each
appears in the lifecycle module's declared disposition map **once for merge
and once for delete**. An unlisted foreign key fails the build. A future table
keyed on a security would otherwise break every merge (RESTRICT) or lose data
silently (CASCADE).

**Out of scope, each with its reason:**

- **Unmerge.** #328 excludes it; an automated unmerge would have to re-split
  duplicates and anchors, and deserves its own decision.
- **Cross-portfolio merges and moving accounts between portfolios.** The
  composite keys pin rows to their portfolio, and ADR-0024 made portfolios
  internal.
- **Cross-currency merges** and any conversion of stored amounts.
- **Merge suggestions** and automatic consolidation (#328 excludes them).
- **Merger and spin-off**: corporate actions that create a new instrument
  (ADR-0028 §4), not an identity repair.
- **Merging portfolios, views, buckets, categories or classifications**, and
  multi-source merges in one call.
- **An `/api/v1` import route.** If one ships, it inherits ADR-0029 §2's
  fail-closed contract.

### 15. The asks, answered and deferred (ADR-0043)

Sources: the #328 body and its 2026-07-12 comment, the #608 body, ADR-0029
§3's named follow-up, and the 2026-09-23 triage's Sprint 16 row.

| Ask | Source | Verdict |
|---|---|---|
| Rename a cash account and a depot on UI, API and MCP | #328 | **Answered**: §4, §11 |
| Merge cash account into cash account; all bookings reassigned; source deleted | #328 | **Answered**: §7, refined: internal transfers removed with their hashes retired, anchors restated and same-day anchors folded into the target's last, key-equal pairs by explicit choice |
| Guard: same currency only | #328 | **Answered**: §7, plus same portfolio, liquidity role and view membership |
| Preview: affected bookings, balances of both accounts before and after | #328 | **Answered**: §7, §10 |
| Merge depot into depot; preview shows affected positions | #328 | **Answered**: §7 |
| Delete only when unreferenced, otherwise a "merge first" hint | #328 | **Answered**: §11 |
| The merge is atomic | #328 | **Answered**: §7, §10, §13 |
| A re-import after a merge creates no duplicates, and new rows under the old name reach the target (a remembered mapping or a documented limit) | #328 | **Answered with a remembered mapping**: §2–§6, **with three documented limits** (§2): a Portfolio Performance-side rename to a name the database never saw, or to a live or former name of a different account, falls outside O2 and is remapped in the preview; a new row under S's name whose #533 key equals an existing T row's is absorbed at the pre-import economic layer and reported, not inserted; and a row dated on or before a restated anchor is inserted but absorbed by that anchor, and reported. **Deferred**: the fail-closed probe for never-seen identities, and one-to-one matching on the pre-import layer (both filed as the batch opens). |
| User-story tests including the multi-currency guard; API, MCP, docs | #328 | **Answered**: §16 and the surfaces in the plan |
| UAT on real data (the five-step plan) | #328 | **Deferred, with reason**: an owner action under `needs-uat`. The batch runs the same five steps on the synthetic seed, and the issue stays open until the owner has run them. |
| Portfolio reassignment | #328 comment | **Out of scope**: §14 |
| A journaled merge of security B into A | #608 | **Answered**: §9, §13 |
| Reassign transactions, quotes, category assignments, position targets, aliases | #608 | **Answered**: §9 (quotes gap-filled, the target wins on collision with values recorded) |
| Source deleted | #608 | **Answered**, except a source with research notes or rule versions naming it: **refused**. The tombstone that would allow it is **deferred**, filed as the batch opens. |
| Preview shows affected counts and identifier collisions | #608 | **Answered**: §9, §10 |
| Guards for conflicting master data | #608 | **Answered**: currency, benchmark, retired target and quote basis refuse; the rest follows the target and is listed |
| Idempotency after a merge reasoned explicitly | #608 | **Answered** for ISIN-bearing and identifier-compatible merges (§2, §9). **Deferred**: ISIN-less merges with incompatible identifiers are refused pending generalized aliases (filed as the batch opens). |
| Risk-tier: dedicated small PRs with real human review | #608 | **Superseded** by ADR-0036: own commit groups, a verification pass, a briefing callout |
| ADR-0029 §3's wrong-order repair | ADR-0029 | **Answered**: `adopt_source_isin` plus collapse |
| The corporate-actions gap | ADR-0028 via #608 | **Deferred, with reason**: merger and spin-off are ledger events with a ratio, not an identity repair. They move to a follow-on of ADR-0028 §4 under FR-23, filed as the batch opens, because the tracker that held them is closed. |
| Lifecycle merges under one ADR, risk-tier | triage | **Answered**: this record |

**Filed in the same pass as the batch opens** (so each deferral stays visible):
a security tombstone for a source with notes or rules; generalized identifier
aliases with remembered security remaps; the probe for never-seen identities;
one-to-one matching on the pre-import #533 layer, with its twin-loss evidence;
unmerge; and merger and spin-off, as ADR-0028 §4's follow-on under FR-23.

### 16. The invariants written first

Each is written before the code, and each is **mutation-verified** in the
closing act (shown red against a deliberately broken implementation) and
**re-run after the fix rounds**:

1. Re-applying an applied synthetic export creates zero transactions, cash
   accounts, depots and securities after a rename, a cash merge (with and
   without collapse), a depot merge, and a security merge under both identity
   choices; every row is reported with its layer.
2. A row whose hash is held or retired triggers no resolution, creation or
   insert; a preview decision still takes effect when all its rows are hits.
3. A create-mapped account is created only when one of its rows inserts.
4. After any merge, the held-or-retired hash set is a superset of the one
   before; inserting a retired hash fails at the database on both writers.
5. A drifted re-import after each merge kind creates nothing; for the
   security merge, in **both** ADR-0029 §5 directions.
6. A newer file naming a former name or a merged-away ISIN inserts its new rows
   once, on the target.
7. An internal transfer is skipped and reported, never inserted, never a
   rollback.
8. Two rows from different file accounts with equal resolved key and time are
   both inserted; old and new ISIN under one account still collapse.
9. **Cash identity**: after a merge, the merged balance equals the fold of S's
   kept rows plus the fold of T's kept rows at every date and today, with
   anchors on either side, on both sides on one day, two anchors on one day,
   and a collapse with an anchor of either side dated after a collapsed source
   row. Without collapse, external flows per date and total value are
   unchanged; with collapse, they change by the collapsed rows alone, and the
   preview lists every flow a collapse removes or moves. A row imported after
   the merge and dated before a restated anchor is inserted and reported in
   `behind_restated_anchor` with that anchor.
10. **Depot and security linearity**, including the split refusal, the
    split-event-set refusal, and a split where rounding the combined position
    once differs from the sum of the two separately rounded positions.
11. Every moved, restated or deleted row of a journaled table has exactly one
    journal entry; every bucket-link or override change has its one aggregate
    entry per account or position; every moved or dropped quote appears in the
    manifest; no lifecycle path removes a row by cascade; notes, in-force rule
    versions, the journal, merge records and retired hashes are never updated
    or deleted.
12. The preview's after-figures equal the API reads right after the apply.
13. Each refusal answers its code and leaves every table unchanged; a stale
    digest answers 409 and writes nothing.
14. After a security merge, both pre-merge identities, stored and as-imported,
    resolve to the target; a source created by a name-only import and given a
    ticker afterwards is refused when its imported name would no longer
    resolve.
15. The identity-field freezes hold on the context, API, MCP and UI paths,
    including a search-result merge into an existing security from a listing
    in another currency (the importer never changes matched master data, so it
    has no freeze case to show red).
16. The foreign-key disposition meta-test of §14.

## Consequences

- **The live rename hazard closes** with the importer half alone (§3, §4),
  before any merge endpoint exists: for every rename from this record on, for
  every earlier rename the journal holds (§4's backfill), and for a
  byte-identical re-import of any rename. Two cases stay outside O2 until the
  operator remaps the name once in the preview: a drifted re-import under a
  name renamed before the accounts' journal was armed, and a name that has
  since become another account's live name (a zombie, which the merge
  repairs). That half is sequenced first, and no merge endpoint lands on a
  commit before it (ADR-0029 §5's precedent: the alias table never existed
  without the tier that reads it).
- **The importer's behaviour changes in three visible ways**: a byte-identical
  re-import no longer creates anything; an internal transfer is a reported skip
  rather than a rollback; and a manual remap is remembered unless the operator
  unticks it. The integration docs, the import preview and the MCP tool
  descriptions say so (the #831 lesson: agents read descriptions, not docs).
- **The operator gains the lifecycle surface** on Accounts & depots and on the
  security row menu, preview-then-confirm, on the boards of the Sprint 16
  design pass; the agent gains the same over API and MCP in the same batch.
- **Some merges are refused**, each with a named reason and a remedy. That is
  the price of never guessing.
- **Cost:** about half of a sprint at the current cadence, in four risk-tier
  commit groups plus a surfaces group. The Sprint 16 plan names the order and
  the shrink order.

## References

- #328, #608, and the 2026-09-23 backlog triage (Part 1, Sprint 16 row).
- [ADR-0017](0017-append-only-audit-journal.html), [ADR-0024](0024-buckets-and-views-replace-portfolios-in-the-ui.html),
  [ADR-0028](0028-corporate-actions-as-ledger-events.html),
  [ADR-0029](0029-stable-identities-and-reimport-survival.html),
  [ADR-0036](0036-risk-tier-rides-the-batch.html),
  [ADR-0039](0039-durable-derived-values.html),
  [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html),
  [ADR-0044](0044-security-knowledge-as-an-append-only-log.html),
  [ADR-0049](0049-policy-rules-as-first-class-objects.html).
