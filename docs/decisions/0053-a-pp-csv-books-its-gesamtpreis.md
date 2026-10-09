---
layout: docs
title: "ADR-0053: a Portfolio Performance CSV books its Gesamtpreis — read as PP writes it, hashed as before, corrected by a separate confirm"
description: "Design gate for #1076, risk-tier (money and import idempotency), signed by the merge of the Sprint 19 planning PR. In Portfolio Performance's CSV export, Betrag is the gross value and Gesamtpreis the cash amount; the importer has booked Betrag as the cash. From now on a row with a Gesamtpreis books it, checked to the cent against Betrag, Gebühren and Steuern, and a row without one (a converter-written file) books its Betrag as before. The import hash keeps reading Betrag, so every stored hash stays valid and a re-drop books nothing. Bookings already made under the old reading are corrected by a separate, journaled confirm that a re-dropped PP CSV feeds."
---

# ADR-0053: a Portfolio Performance CSV books its Gesamtpreis — read as PP writes it, hashed as before, corrected by a separate confirm

- **Status:** Accepted. Owner sign-off is the merge of the Sprint 19 planning
  PR (ADR-0026 step 1, as amended on PR #780: the merge is the signature).
- **Date:** 2026-10-04
- **Amended:**
  - 2026-10-07: the JSON path's negative tax, a converter file's negative
    Steuern, and a credit row that nets to nothing (#1098, #1118; see
    "Amendment (2026-10-07)" below). Adopted by the merge of the Sprint 20
    planning PR.
  - 2026-10-09: a refund no cash leg of its row can carry, a negative fee
    unit, and what the correction lists (#1188, #1177 in part, #1193,
    #1194, #1205; see "Amendment (2026-10-09)" below). Adopted by the merge
    of the Sprint 21 planning PR.
- **Answers:** #1076, filed by Sprint 18's PR δ while it checked the
  synthetic CSV sample against Portfolio Performance's source (#1024).
- **Risk tier** ([ADR-0036](0036-risk-tier-rides-the-batch.html)): money
  (the cash every balance, valuation and return reads) and import
  idempotency (the content hash and the re-import contract of
  [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html) §2).
  Semantics-changing risk-tier work needs its record signed before the batch
  starts; this is that record. Following
  [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), the closing table
  lists each ask as answered or deferred.

## Context

**What Portfolio Performance writes.** PP's CSV export of its transactions
view is a table dump: `TableViewerCSVExporter` writes each visible column's
header and cell text. The columns come from `TransactionsViewer`, read on
PP's `master` branch on 2026-10-04 (no test reads it; tests make no network
call):

- **Kurs** is `getGrossPricePerShare()`, **Betrag** is `getGrossValue()`,
  **Gebühren** and **Steuern** are the transaction's fee and tax units (blank
  when zero), and **Gesamtpreis** is `getMonetaryAmount()`, the cash that
  moved. German labels: `ColumnAmount = Betrag`, `ColumnNetValue =
  Gesamtpreis` (`messages_de.properties`).
- The gross value is the cash with the units taken out. For a purchase it
  is `amount − fees − taxes`, for a sale `amount + fees + taxes`
  (`PortfolioTransaction.getGrossValueAmount`). For an account transaction
  it is `amount + units` for a credit and `amount − units` for a debit
  (`AccountTransaction.getGrossValueAmount`).
- Every money cell is printed to two places, so
  **Gesamtpreis = Betrag ∓ (Gebühren + Steuern) holds exactly to the cent.**
  PP always writes the Gesamtpreis cell and always writes a time of day in
  Datum.

**What Portfolixir reads.** The CSV parser
(`Imports.PortfolioPerformance.CsvParser`) reads Datum, Stück, Kurs,
**Betrag**, Gebühren and Steuern, and books Betrag as the entry's
`gross_amount`. It never reads Gesamtpreis, which is not a required column.
A negative Steuern is split into a `tax_refund` companion (ADR-0029, the
2026-09-25 amendment).

**What `gross_amount` means downstream.** It is the cash leg, not a gross
value. The projection debits a buy's `gross_amount` as it is and credits a
sale's as it is. Fees and taxes are added or subtracted only when no amount
was recorded (`Ledger.Projection`: "a buy's `gross_amount` is inclusive of
fees/taxes; a sell's is already net"). A dividend's `gross_amount` is its net
credit (the API reference; the income report rebuilds the gross as net plus
tax).

**So on a real PP CSV export, every cash row with fees or taxes books the
wrong cash, by exactly those units, always in the same direction:**

- a buy debits too little;
- a sale, a dividend or an interest payment credits too much;
- an account booking with units (rare) is off by them;
- rows without units are right.

The error reaches every figure built on cash:

- cash balances, the valuation's cash and the total;
- the TTWROR, because a dividend is not an external flow;
- the income report, which then counts a CSV dividend's tax twice;
- the settlement legs of a cross-currency CSV trade, which are derived from
  the same amount.

The JSON v1 path is right. It books PP's `amount`, which is the cash.

**Why the tests stayed green.** The synthetic `sample.csv` takes its Betrag
values from `sample.json`'s cash amounts. Its Kauf row (Kurs 150,25, Betrag
1.502,50, Gebühren 2,50, Gesamtpreis 1.502,50) matches neither reading. The
golden master's CSV-equals-JSON parity (Test-Cash 4017.68) therefore holds
for a file PP would never write.

**Who writes the other kind of CSV.** The companion's `import_converter`
prompt (Sprint 17, #983) tells an agent to write Betrag as the cash effect
and to leave Gesamtpreis empty. Every converter-written file books correctly
today and must keep doing so. An empty Gesamtpreis is the decisive
difference: PP never leaves it empty.

**What the content hash reads.** `ImportHash.parts/2` hashes the entry's
`gross_amount` as a parsed `Decimal`, together with the kind, the date and
time, the security key, the quantity, the price, the fees, the taxes, the
four PP names and the portfolio id. The economic #533 key
(`Imports.DedupKey`) includes `gross_amount` too. Nothing of the file
survives the preview: the ETS preview lives two hours, and no format,
filename or batch is stored on a transaction.

**What a naive fix would do.** If `gross_amount` simply became the
Gesamtpreis, every row with fees or taxes would get a new hash and a new
economic key. The next re-import of the same file would book each of those
rows a second time. That breaks ADR-0050 §2 ("a file already applied is a
no-op") and its obligation O1.

## Decision

### 1. A row with a Gesamtpreis books it; a row without one books its Betrag

The cash effect of a PP CSV row is its **Gesamtpreis** when the cell is not
empty. When it is empty, it is the **Betrag**, as today. That is the shape
the converter prompt writes and the handbook's hand-made files follow.
Nothing else in the row changes meaning:

- Kurs stays the price per share;
- Gebühren and Steuern stay the stored fees and taxes;
- the kinds without cash (deliveries, the security transfer) ignore every
  money cell, as today.

The converter prompt's contract is unchanged. It gains one sentence saying
why Gesamtpreis stays empty.

### 2. Both readings must agree, to the cent, or the row is refused

A row that carries both cells is checked. **U** is Gebühren + Steuern as
written, a negative Steuern included with its sign.

- **Debit kinds** (Kauf, Entnahme, Gebühren, Steuern, Umbuchung (Ausgang)):
  Gesamtpreis = Betrag + U.
- **Credit kinds** (Verkauf, Dividende, Zinsen, Einlage,
  Steuerrückerstattung, Umbuchung (Eingang)): Gesamtpreis = Betrag − U.

A row that fails the check is a **row error** that names both readings (for
example "Gesamtpreis 1.505,00 passt nicht zu Betrag 1.502,50 und Gebühren
2,50"). The rest of the file previews. The importer fails closed: it does
not guess which cell is wrong.

**Note (2026-10-06).** U reads Gebühren as the fee the row books, that is
its magnitude: a Gebühren cell written negative ("-2,50") counts as 2,50,
the fee the ledger stores for it. Steuern keeps its sign, since a negative
Steuern is a refund (§5). Found by PR α's closing act; no decision changes.

### 3. The content hash keeps reading Betrag

The parser carries the file's Betrag on the entry as the **hash's amount
input**, separate from the booked cash. `ImportHash.parts/2` reads that
input instead of `gross_amount`. For a JSON entry the input stays `amount`,
which is also its booked cash.

**Every hash stored before this record stays byte-identical**, so a re-drop
of a PP CSV that was imported under the old reading is all hash hits and
books nothing. ADR-0050 §2 and O1 hold unchanged. No legacy lookup is added,
because no stored hash changes.

The `ImportHash` moduledoc says so, and ADR-0029 gains a note pointing here.

### 4. The economic key is checked under both readings

A CSV row's #533 key is computed with the booked cash and again with the
Betrag reading. A row is a duplicate if either key is already in the
portfolio's pre-import set. This closes the drifted re-import: a booking
stored under the old reading, whose hash no longer matches (for example
because a time of day changed in a re-export), is still recognised and is
not booked twice. The check errs towards "already booked", as ADR-0029's
legacy hash lookup does, and the result names the row it skipped.

### 5. A negative tax split into a companion: the row still sums to its Gesamtpreis

When a row's negative Steuern becomes a `tax_refund` companion (ADR-0029,
the 2026-09-25 amendment), the parent books **Gesamtpreis minus the
refund**. The row's bookings together then equal its Gesamtpreis. The
companion's hash and its judgement with its parent are unchanged.

**Note (2026-10-05).** "Gesamtpreis minus the refund" is meant in signed
cash. On a credit row the parent is credited the Gesamtpreis minus the
refund (G − r); on a debit row the parent is debited the Gesamtpreis plus
the refund (G + r), since the refund credited beside it brings the row's
net debit back to G. Either way parent and companion net to the row's
Gesamtpreis, which is what K6 requires. No decision changes.

### 6. Bookings made under the old reading are corrected by a separate confirm

No stored row records which file format it came from, so an instance cannot
find its wrong cash rows from the database alone:

- a trade can be suspected by arithmetic (its cash is close to quantity ×
  price);
- a dividend or an interest payment cannot.

**The correction is therefore fed by a PP CSV**, the original file or a
fresh re-export from Portfolio Performance, and it works like this:

- **When it appears.** A dropped file may hold rows that carry a
  Gesamtpreis, whose hash matches a stored transaction, and whose stored
  cash differs from what §1 and §5 now book. If it does, the preview lists
  those rows **in a section of their own**, apart from the rows the
  ordinary apply would insert. Each line shows the booking, the stored cash,
  the cash the file states, and the difference.
- **Its confirm.** The section has its own confirm, separate from the
  apply. The ordinary apply is unchanged: **a hash hit still inserts and
  changes nothing** (ADR-0050 §3).
- **What the confirm writes.** For each listed booking it rewrites the cash
  (`gross_amount`). For a cross-currency trade it also rewrites the
  settlement amount, the security amount and the rate in the same write, so
  the settlement guard holds. It never touches the import hash, the
  transaction's id, its fees, its taxes or its price.
- **Journaling and locking.** Each change is journaled as a correction under
  the operator's actor. The confirm holds the same locks as the apply.
- **Idempotent.** A second drop of the same file finds nothing to correct.
- **When nothing differs**, there is no section. There is no all-clear
  badge either (UX-DR2).
- **Not on the API.** It gets no `/api/v1` route and no MCP tool, because
  the import is an operator action
  ([ADR-0029](0029-stable-identities-and-reimport-survival.html), the
  Sprint 18 plan). Every corrected value is visible through every existing
  read, and the agent's view is the corrected ledger.

The screen is drawn on the Sprint 19 board `09-import-correction` (pick J9)
before it is built.

### 7. The fixture becomes a faithful PP export, and the parity stays

`sample.csv` is rewritten to the shape PP writes for `sample.json`'s
history:

| Row | Kurs | Betrag | Gesamtpreis |
|---|---|---|---|
| Kauf | 150,00 | 1.500,00 | 1.502,50 |
| Verkauf | 181,45 | 1.814,50 | 1.800,00 |
| Dividende | — | 11,54 | 9,13 |
| Zinsen | — | 5,75 | 4,55 |

The golden master keeps its CSV-equals-JSON parity at **4017.68**. On
today's code the rewritten fixture gives **4038.29**, and that is the red
test the story starts from. The other test rows that carry the impossible
Kauf shape are corrected in the same commit. The converter's worked example
(5895.56) stays green unchanged.

**Carried forward from the Sprint 18 retrospective:** a fixture that encodes
an external format is checked against that format's source before it is
written or "corrected". The story records the PP source paths it read in
its commit message.

### 8. The handbook says what the columns mean

The English and German import handbooks state that Betrag is PP's gross
value and Gesamtpreis the cash, that Portfolixir books the Gesamtpreis and
checks it, and that a file without a Gesamtpreis is read as a converter
file. Two code comments that call Betrag "the exact cash the broker
settled" are corrected (`Applier`, `applier_settlement_test.exs`).

## What this record does not do

- **No change to the JSON v1 path.** It already books the cash.
- **No heuristic suspect list without a file.** It would be exact for no
  dividend and approximate for trades, and a list that is sometimes wrong
  about money is worse than none. Deferred with that reason and filed at the
  signature.
- **No decision on the JSON path's negative tax.** Whether PP's JSON
  `amount` already includes a refund the parser then splits off again
  (which would make it a double count) is a separate question. It is filed
  at the signature, not decided here. *(Decided by the amendment of
  2026-10-07: it does, and the JSON path is corrected.)*
- **No foreign-currency PP CSV.** The CSV path books EUR, and a cell with a
  currency prefix fails parsing. That is a refused row today, not a wrong
  figure, and it stays as it is.
- **No stored file, no format column, no import route.**

## The identities the building batch pins

| | Identity |
|---|---|
| K1 | For a PP-faithful file, every account's cash after a CSV import equals its cash after the JSON import of the same history, exact in `Decimal` (Test-Cash 4017.68). |
| K2 | Every content hash the parser computes for a CSV row is byte-identical before and after the change. Pinned by a digest list taken from today's code before the first change. |
| K3 | A PP CSV applied under the old reading and then dropped again under the new one inserts nothing: zero transactions, accounts, depots and securities (ADR-0050 §2). |
| K4 | A converter-written file (empty Gesamtpreis) books exactly as before. The worked example's 5895.56 does not move. |
| K5 | A row whose Gesamtpreis contradicts Betrag ∓ (Gebühren + Steuern) is a row error naming both readings, and the file's other rows preview. |
| K6 | A row whose negative Steuern is split off books parent plus companion equal to its Gesamtpreis. |
| K7 | The correction changes only the listed bookings' cash (and a cross-currency trade's settlement legs), keeps every hash and id, journals every change, and a second run finds nothing to correct. |
| K8 | The ordinary apply of a file whose rows are all hash hits changes no stored value, whether or not the correction section is shown. |

## The asks, answered and deferred (ADR-0043)

**Where the asks come from:** #1076's body, its "why it needs a decision"
list, and the Sprint 18 close-out's launch-readiness summary.

| Ask | Source | Verdict |
|---|---|---|
| Which cell is a PP CSV row's cash | #1076 | **Answered.** §1: Gesamtpreis, Betrag only when it is empty |
| A corrected reading must not make imported rows look new | #1076 | **Answered.** §3 and §4: the hash keeps reading Betrag; the economic key is checked under both readings |
| Converter-written files must keep working | #1076 | **Answered.** §1: an empty Gesamtpreis keeps today's reading; K4 pins it |
| The fixture and its golden master | #1076, #1024's second ask | **Answered.** §7: rewritten to PP's shape, parity kept at 4017.68 |
| What an instance that already imported a PP CSV does | the launch-readiness summary | **Answered.** §6: a separate, journaled correction fed by the file |
| Finding affected bookings without the file | follows from §6 | **Deferred, with a reason.** No stored field tells the formats apart, and a list that is sometimes wrong about money is worse than none. Filed at the signature |
| A negative tax under the PP reading | found while writing §5 | **Answered for the CSV path.** §5. **The JSON path's question is deferred**, filed at the signature |
| Whether the owner's own instance is affected | the launch-readiness summary | **Not this record's to answer.** It is the owner's check on the live instance. The Sprint 19 plan asks it, and §6 is the remedy |

## Consequences

- **Risk-tier attention.** The change ships in its own commit group, TDD
  first, with exact `Decimal` fixtures:
  - K2's digest list is the first commit, taken while the code is still
    unchanged;
  - the rewritten fixture's red test comes next;
  - the reading, the check, the keys and the correction follow, each in its
    own commit.

  The verification pass takes K1 to K8 one at a time, K2 and K3 first,
  because they protect every instance that has already imported. The
  reviewer briefing calls them out.
- **ADR-0029** gains a dated note: the hash's amount input for a CSV row is
  the file's Betrag (§3 here). **ADR-0050 §2 and §3 are unchanged**, and
  this record depends on them.
- **The owner's own instance.** If its Portfolio Performance history came in
  as a CSV, its cash balances are off by every fee and tax of those rows
  until §6's correction runs with a re-export. If it came in as JSON,
  nothing is affected. *(Corrected by the amendment of 2026-10-07: a JSON
  history is off on every row that carries a negative tax unit, by that
  unit.)*
- **Registry.** #1076 closes by the keyword of the PR that builds it. The two
  deferred asks are filed under E26's tracker at the signature.
- Nothing here creates, stores or transmits an order. Nothing acquires data
  the instance does not already hold, and nothing calls out.

## Amendment (2026-10-07): the JSON path's negative tax, a converter file's negative Steuern, and a credit row that nets to nothing

**Status:** adopted by the merge of the Sprint 20 planning PR; risk-tier
(money and import idempotency), so it is signed before the batch that builds
it. It answers the JSON question this record deferred (#1098) and #1118.

### Why

**PP's JSON `amount` already holds the refund.** Read on Portfolio
Performance's `master` on 2026-10-07 (no test reads it):

- `JTransaction.from` writes `amount` as the transaction's `getAmount()`,
  the stored cash, and `JTransactionUnit.from` writes each unit's amount
  with its sign.
- A PP account's balance is the signed sum of `getAmount()` alone
  (`Account.getCurrentAmount`). Units never enter it.
- The gross value is derived from the cash: `amount` plus or minus the unit
  sum (`AccountTransaction.getGrossValueAmount`,
  `PortfolioTransaction.getGrossValueAmount`).

So a negative TAX unit −r is already inside `amount`. `JsonParser` books
`amount` as the parent's cash and splits r off as a `tax_refund` companion
beside it, so **every such row books r too much**:

- on a credit the account gains `amount + r`;
- on a debit (a purchase with a negative tax) the parent debits `amount` and
  the companion credits r, so the account again ends r too high.

The repository's own fixture shows it. `sample_with_negative_tax.json` is a
dividend with `amount` 181.49 and tax units 27.00 and −0.01. It books 181.50.
PP's balance is 181.49, and PP's CSV of the same transaction (Steuern 26,99,
nothing split off) books 181.49 under §1. K1 therefore fails by r for every
history with a negative tax unit.

**The derived price carries it too.** `derive_price` adds back the fees and
the positive taxes only:

- a JSON sale's price × shares is `amount + fees + positive taxes`, which
  holds r; the trade matcher's proceeds (q × price − fees − taxes) then equal
  `amount`, and the realized result is r too high;
- a JSON purchase with a negative tax is priced r ÷ shares too low.

**A converter-written CSV does the same.** With an empty Gesamtpreis the
parser books Betrag (§1) and still splits a negative Steuern off. The
`import_converter` prompt defines Betrag as the cash after fees and taxes, so
a converter that writes Steuern −r counts r twice.

**§5 has a hole (#1118).** When a credit row's Gesamtpreis minus its refund
is 0 or less, the applier skips the parent and its companion, because only
positive cash is importable. The sale is never booked, the position stays
held, and the preview showed no error.

**The owner's instance.** This record's Consequences said that a history
imported as JSON was not affected. That is corrected: it is affected on
every row that carries a negative tax unit, by that unit.

### What changes

**A1. One rule for a row with a split-off refund, whatever the format.** A
row's **cash cell** is:

- for a PP CSV, its Gesamtpreis (§1);
- for a converter CSV, its Betrag (§1);
- for JSON, its `amount`.

When a negative tax r is split off into a companion, the parent books the
cash cell minus r on a credit and plus r on a debit, so parent and companion
net to the cash cell. §5 (as noted on 2026-10-05) applied to the Gesamtpreis
only; it now applies to the cash cell of every format.

**A2. A JSON price is derived from the gross value, as PP derives it.**
`derive_price` reads the taxes with their sign:

- a sale is priced `(amount + fees + signed taxes) ÷ shares`;
- a purchase is priced `(amount − fees − signed taxes) ÷ shares`.

The stored `taxes` (the positive units) and the companion are unchanged. A
sale's proceeds then equal its parent's cash, and the realized result leaves
the refund out. The refund is income of its own, the companion.

**A3. The hash keeps reading what it read.** The entry carries the file's
`amount` as the hash's amount input, as today. For a JSON purchase or sale
with a negative tax unit it also carries the price derived the old way as
the hash's **price** input, separate from the booked price, and
`ImportHash.parts/2` reads that input when it is present. **Every stored
JSON hash stays byte-identical.** A converter CSV's hash already reads Betrag
(§3), and its price is Kurs from the file, so nothing changes there.

**A4. The economic key is checked under both readings**, as §4 does: the
booked cash and price, and the old reading (the cash cell as cash, and for
JSON the old derived price). A drifted re-export of a row booked under the
old reading is still recognised and not booked twice.

**A5. A credit row whose parent would book 0 or less is a row error**, in
both parsers, whether or not a refund was split off. The message names the
row and the remedy: book the sale by hand, and the refund as a tax refund of
its own. The rest of the file previews. It fails closed as §2 does, and no
hash changes. The alternative #1118 names, a fee companion that books the
sale at its Betrag, is not taken: the parent's fees would have to stay out of
the costs while the hash keeps reading them, which needs its own record.

**A6. §6's correction is fed by a JSON file and a converter file too, and
it is built.**

- **What it lists.** A re-dropped file whose rows hit stored hashes, and
  whose stored cash differs from what A1 books, is listed in §6's section.
  The condition "rows that carry a Gesamtpreis" becomes "rows whose cash
  under this record differs from the stored cash".
- **What it writes.** For a JSON purchase or sale the confirm rewrites the
  price together with the cash, because a JSON price is derived from the
  cash (A2). A CSV row's price is Kurs from the file and is never touched.
- **Everything else in §6 holds:** a separate confirm, journaled under the
  operator's actor, the apply's locks, idempotent, no API route.
- **Its wording** names the Portfolio Performance file, not its format.

*(Widened by the amendment of 2026-10-09: A10 lists a stored booking whose
row is now refused, A11 names a booking edited since its import and lists a
JSON trade on its price too, and A12 lists a row matched by its figures.)*

**A7. The converter prompt** gains one sentence: a refund of tax is its own
Steuerrückerstattung row, and Steuern is never negative in a converter file.
A1 books a negative Steuern correctly anyway; the sentence keeps new files
simple.

**What does not change:** §1–§4 for a PP CSV row without a negative Steuern;
K1–K8; the converter's worked example (5895.56); the hash of every row; no
format column, no stored file, no import route.

### The identities the building batch pins

| | Identity |
|---|---|
| K9 | For a history with a negative tax unit, every account's cash after the JSON import equals PP's balance and the cash after the PP CSV import of the same history, exact in `Decimal`. `sample_with_negative_tax.json` books **181.49** (today 181.50). A synthetic JSON sale (`amount` 120.00, 10 shares, FEE 5.00, TAX −25.00) into an account holding 1,000.00 leaves **1,120.00** (today 1,145.00): parent 95.00, companion 25.00. Its PP CSV (Betrag 100,00; Gebühren 5,00; Steuern −25,00; Gesamtpreis 120,00) books the same. |
| K10 | Every JSON content hash computed today is byte-identical after the change. Pinned by the digest list `csv_hash_pin_test.exs` already holds for `sample_with_negative_tax.json`, extended by the sale's digest before the first change. |
| K11 | A JSON file applied under the old reading and dropped again inserts nothing (zero transactions, accounts, depots and securities). A drifted re-export of it, with a time of day changed, inserts nothing either. |
| K12 | A JSON sale's realized result leaves the refund out: the synthetic sale is priced **10.00** (today 12.50), and its proceeds equal its parent's cash, 95.00. |
| K13 | A converter CSV row with a negative Steuern books parent plus companion equal to its Betrag. A converter file without one books exactly as before (K4). |
| K14 | A credit row whose parent would book 0 or less is a row error in both parsers. The file's other rows preview, and no hash changes. |
| K15 | The correction, fed by a JSON or a converter file, changes only the listed bookings' cash (and a JSON trade's price, and a cross-currency trade's settlement legs), keeps every hash and id, journals every change, and a second run finds nothing to correct. |

### The asks, answered and deferred (ADR-0043)

| Ask | Source | Verdict |
|---|---|---|
| Does the JSON path count a split-off negative tax twice | this record's deferral, #1098 | **Answered: yes.** A1–A4 |
| Does a JSON sale's realized result carry the refund | found while answering #1098 | **Answered: yes.** A2, K12 |
| A converter file's negative Steuern | found while answering #1098 | **Answered.** A1, A7, K13 |
| A credit row that nets to nothing | #1118 | **Answered.** A5: refused in the preview, with the remedy |
| What an instance that imported JSON does | the owner's D-2 answer of 2026-10-04 | **Answered.** A6: the correction, fed by a re-export. The Sprint 20 plan asks the owner to count the affected rows first |
| PP JSON's `INTEREST_CHARGE` and `FEE_REFUND` types, and a negative FEE unit | found while answering #1098 | **Deferred, with a reason.** The two types are refused rows today, named in the preview. A negative FEE unit is stored as its magnitude, which skews a JSON trade's derived price and the costs; it needs a fee-refund companion of its own, as ADR-0029 made for taxes. Filed at the signature *(The negative FEE unit is answered by the amendment of 2026-10-09, A9: a row error until a fee-refund kind exists. The two types stay deferred, #1177.)* |

### Consequences of the amendment

- **Risk-tier attention.** K10's digest list is the first commit, taken while
  the code is unchanged; K9's red tests come next; the reading, the price,
  the keys, the refusal and the correction follow, each in its own commit.
  The verification pass takes K9–K15 one at a time, K10 and K11 first.
- **ADR-0029** gains a dated note: a JSON trade's hash may carry a price
  input separate from its booked price (A3).
- **The handbooks** (EN, DE) say that a negative tax inside a PP row books as
  a tax refund beside its booking, and that a history imported before the
  release that builds this amendment is corrected by dropping a fresh export
  and confirming the correction section.

## Amendment (2026-10-09): a refund no cash leg can carry, a negative fee unit, and what the correction lists

**Status:** adopted by the merge of the Sprint 21 planning PR; risk-tier
(money and import idempotency), so it is signed before the batch that builds
it. It answers #1188, #1193, #1194 and #1205, and #1177's negative FEE unit.
#1177's two Portfolio Performance types stay deferred. No stored hash
changes.

### Why

**A refund split off a row with no cash leg of its own (#1188).** Both
parsers split a negative tax unit into a `tax_refund` companion for every
kind (`JsonParser`'s units fold, `CsvParser.normalize_fees_taxes/2`), and
the companion books on the row's own cash account. Three kinds have none
that can carry it:

- **A delivery or a security transfer** names no cash account (#1188; the
  CSV parser's account mapping gives these kinds none). The `tax_refund`
  changeset requires one (`Ledger.Transaction`). The apply therefore
  answers `insert_failed` on the companion and rolls back **the whole
  file**, and the same file without the unit imports. Sprint 20's build
  probed the JSON path; the code reads the same for the CSV path.
- **A cash transfer** moves its cash between two accounts.
  `PortfolioPerformance.direction/2` reads a JSON transfer and a CSV sending
  row as a debit. So A1 books the transfer at its cash cell plus r, and the
  refund r on the sender: the sender ends right, and **the receiver ends r
  too high** (synthetic: 105.00 against Portfolio Performance's 100.00).
  Before A1, a JSON transfer booked its `amount` with the refund beside it,
  so the sender ended r too high instead.

Portfolio Performance moves no cash for a delivery. For a transfer it moves
the amount between the two accounts and nothing else
(`Account.getCurrentAmount` sums `getAmount()` alone, as A1's reading
found). A refund booked beside either is a figure PP never shows.

**A negative FEE unit is stored as a positive fee (#1177).** `JsonParser`'s
units fold adds the magnitude of every FEE unit:

- a purchase with FEE 5.00 and FEE −2.00 stores fees 7.00, where PP nets
  3.00;
- A2 then prices it from the cash less 7.00.

The cash is right (the `amount`), but the costs and the price are not, and
no preview line says so. The ledger stores no fee below zero
(`Ledger.Transaction`) and has no fee-refund kind, so an honest booking
needs a kind of its own.

The CSV path differs in both of its cases:

- **A PP CSV's Gebühren** is the sum of the fee units, so it falls below
  zero only when they net below zero. §2's check already refuses such a
  row: PP's Gesamtpreis carries the fee's sign, U reads its magnitude (the
  note of 2026-10-06), and the two never agree.
- **A converter's negative Gebühren** is its fee written with a minus, and
  that note reads it as the fee (`csv_parser_test.exs`, "counts a negative
  Gebühren as the fee it books").

**The correction trusts the hash alone, and the cash alone.**
`Imports.Correction.detect/3`, built in Sprint 20 from §6 and A6, has four
gaps:

- **It lists a row only on a hash hit** (`Applier.row_hashes/2`). A
  re-export can drift in a hashed field: a time of day moves, an ISIN is
  added, an account is renamed. A4's old-reading key then skips the row (the
  applier's `booked_before?` and `old_reading`), so nothing books twice.
  But the booking stored under the old reading is not listed, and it stays
  wrong without a word (#1205). In Sprint 20's UAT a sale's time moved from
  15:30 to 15:31: the stored 120.00 stayed, and the done page described the
  row at 95.00.
- **It decides on the cash alone** (`changes/3`). A JSON trade's price is
  compared only after its cash differs (`put_price`), so a trade whose cash
  agrees keeps its old price. #1194's second case is such a sale:
  - its cash was set to 95.00 by hand;
  - its price is still 12.50;
  - its realized result reads +20.00, where K12 wants −5.00.
- **It reads no history of the booking.** A dividend imported at 9.13 and
  set to 9.20 by hand is listed 9.20 → 9.13, and the confirm rewrites it.
  Only the journal keeps 9.20 (#1194's first case).
- **It never sees a row that A5 refuses.** Such a row is a preview error,
  not an entry. A booking stored under the old reading with its refund
  counted twice therefore keeps its cash r too high.
  `Correction.stored_refusals/2` only changes the row's message to "already
  imported, and it cannot be corrected here", so the operator does not book
  it twice (#1193).

### What changes

**A8. A refund is split off only where the row's own cash leg can carry
it.** A negative tax unit (a JSON TAX unit or a CSV Steuern below zero)
becomes a `tax_refund` companion only on a kind whose own booking moves cash
on one account:

- buy and sell;
- dividend and interest;
- deposit and removal;
- fee, tax and tax refund.

On a **delivery** (inbound or outbound), a **security transfer** or a **cash
transfer** it is a **row error, in both parsers**, named with its remedy.
The rest of the file previews.

- **The message** names the row and its remedy in the shape of A5's
  messages: a CSV row's figures in the file's notation, a JSON row's in the
  reader's.
  - A delivery or a security transfer: "inbound delivery with a tax refund
    of 0,40: a delivery moves no cash to carry it — row not imported. Book
    the delivery by hand without it, and the refund as a tax refund of its
    own if money moved."
  - A cash transfer: "transfer with Gesamtpreis 100,00 and a tax refund of
    5,00: a refund beside a transfer would book on one of its accounts only
    — row not imported. Book the transfer by hand at 100,00, and the refund
    as a tax refund of its own if money moved."

  The board on the Sprint 21 planning PR draws the final text.
- **Its place among the checks** is after `PortfolioPerformance.row_error/1`
  and, on a CSV row, after §2's check, so a value no column holds is still
  named first. It comes before A5, so a receiving transfer row is not
  called a credit that nets to nothing.
- **It fails closed** per row instead of per file, books no cash PP never
  moved, and **changes no hash**. The refused row's would-be entry is built
  exactly as today, with its split-off refund. The preview keeps that entry
  as it keeps a credit that A5 refuses (`refused_credits`), for A10 to read.
- **Not taken:** storing a delivery's taxes with their sign and splitting
  nothing. That changes the delivery's cost basis and needs its own record
  (#1188). It is reopened by a real PP export whose delivery carries a tax
  refund the operator needs in its cost.

**A9. A negative FEE unit is a row error until a fee-refund kind exists.** A
JSON row with a FEE unit below zero is a row error, named with its remedy.
The rest of the file previews.

- **The message:** "buy with a fee refund of 2.00: a refunded fee cannot be
  booked yet — row not imported. Book the buy by hand at the cash Portfolio
  Performance shows, Gesamtpreis 1,003.00." The JSON `amount` is named
  "Gesamtpreis", as the board of 2026-10-07 names it (A5).
- **Its place** is after `row_error/1` and before A8 and A5, so a row with
  a fee refund is named for that first.
- **The hash keeps reading what it read**, as A3 keeps a JSON trade's old
  price. The units fold does not change, so the would-be entry carries the
  fee every stored row was hashed with: the magnitudes summed, 7.00 for
  FEE 5.00 and FEE −2.00. The preview keeps that entry as A8 keeps its
  rows. No row is booked with a fee other than the one its hash reads.
- **Not taken: a signed fold.** It would book a net fee of zero or more
  (3.00 above). But that stored fee would differ from the hash's fee input
  and need an input of its own, and neither the price nor the costs could
  show a refund. That belongs to the fee-refund record, with its kind
  (#1177).
- **The CSV path keeps §2 and the note of 2026-10-06** (see Why). A PP
  CSV's fee units netting below zero already fail §2's check, and a
  converter's negative Gebühren is read as its fee.

**A10. A stored booking whose row is now refused is listed, without a
confirm (#1193).** A row that A5 or A8 refuses may have a would-be booking
that a live transaction holds by its content hash (the lookup
`Correction.stored_refusals/2` makes today). The correction section then
lists that booking in a state of its own: **not correctable here**.

- **What the line shows:**
  - each cash account the row moves, as stored and as the file states it.
    "As stored" is the booking and the refund stored beside it, found by
    the refund's hash with its row. "As the file states it" is the row's
    cash cell, which in Portfolio Performance is all the row moves;
  - their difference;
  - the refusal's remedy, for the stored booking: replace it by hand.
    - A5's sale: delete the stored sale and the refund beside it, then book
      the sale by hand and the refund as a tax refund of its own.
    - A8's transfer: set the transfer's cash to the file's figure, and
      delete the refund beside it unless money moved.
- **No confirm.** The ledger refuses a cash of zero or less, so no
  automatic write exists for A5's booking. A8's transfer could take its
  cash, but the refund beside it would stay. The correction never deletes a
  booking: it writes a cash, a JSON trade's price and a trade's settlement
  legs, and nothing else (§6, A6).
- **The row error keeps saying that the row is already imported**, for A8's
  rows as for A5's (`Imports.row_errors/2`), so no remedy books it twice.
- **A9's rows.** A stored booking with a negative FEE unit holds the cash
  the file states (its `amount`). Its row error says it is already imported
  and names its fee as stored. It is listed here only when a cash account's
  stored figure differs, which takes a negative tax unit on the same row.
  Its fee stays as stored until the fee-refund record (#1177).
- **A hash a merge retired** has no live booking to list. Its row error
  says the row is already imported, as today.

**A11. A booking edited since its import is named, not rewritten; a JSON
trade is listed on its cash or its price (#1194).**

- **The journal decides** (ADR-0017). A booking counts as edited since its
  import when its journal (the `Journal.Entry` rows for the transaction)
  holds an update by an actor other than these two:
  - the importer (`actor_type` `import_session`);
  - the correction (`owner_ui` labelled "import correction",
    `Imports.correction_actor/0`).

  The update counts only when its `before` and `after` differ in a figure
  of the row: the cash, the price, the quantity, the fees or the taxes.
  These updates are not edits of the row's figures:
  - a merge's re-pointing (`Lifecycle.MergeWriter.reassign_transaction/3`);
  - the settlement legs a backfill writes under a system actor
    (`Ledger.SettlementBackfill`);
  - a note.
- **Such a booking is listed in a state of its own: edited since its
  import.** The line shows the booking's stored figures and the file's, and
  carries no confirm. The confirm leaves the booking as the operator made
  it, and the journal keeps both.
- **#1194's two cases:**
  - the dividend set to 9.20 by hand is named with 9.20 and 9.13, and stays
    9.20;
  - the sale whose cash was set to 95.00 by hand is named with its price,
    12.50 stored and 10.00 per the file. The operator sets the price by
    hand.
- **A JSON purchase or sale is listed when its cash or its price differs**
  from what the file books today, each compared at its column's scale. A
  line whose cash agrees shows a difference of 0.00 and its price lines,
  and the confirm writes the price alone. A CSV row's price is Kurs from the
  file, and it is still never compared or written (A6).
- **Not taken:** a per-line choice that lets the file win over a hand edit.
  It is reopened by an operator who asks for one.

**A12. A row matched by its figures is listed too, and has a confirm only
without a twin (#1205).**

- **When:** no stored transaction holds the row's content hash, and the
  economic layer matches the row under A4's old reading. That reading is
  the key of `old_reading`: the hash's amount as the cash and, on a JSON
  trade, the hash's price as the price. The stored booking is listed with
  the line "matched by its figures, not by its import hash". A row that the
  booked reading's key matches is booked as the file reads it, and it is
  not listed.
- **How it is judged:** as the apply's dry run judges it
  (`Applier.reimport_counts/3`, under the preview's prefill, ADR-0050 §4).
  The row's accounts and security are resolved, and a row whose account or
  security does not exist yet matches nothing.
- **Its confirm, only without a twin.** The line carries a confirm only
  when both of these hold:
  - exactly one stored booking of the portfolio holds that key. The
    pre-import set counts its bookings per key, where today
    `load_existing_dedup_keys` keeps a set;
  - no other row of the file claims that booking. A row with a hash hit
    claims the booking it hits, and a row without one claims every booking
    that either of its readings' keys matches.

  Otherwise the line is listed without a confirm and says why: "two stored
  bookings match these figures", or "row N claims this booking". The
  economic key cannot tell two genuine twins on one date apart, and
  correcting the wrong one is worse than correcting none.
- **What its confirm writes** is what §6 and A6 write for a hash hit: the
  cash, a JSON trade's price, and a trade's settlement legs.
  - A11 holds for it.
  - A6's rule on a split-off refund holds too: the refund must be stored
    beside the booking. Here it is found by its own hash or its economic
    key, as the apply finds it (ADR-0029, the 2026-09-25 amendment).
  - The confirm judges each row again under the apply's account-identity
    lock and the bookings' row locks, so it corrects what is stored when it
    runs.

**Everything else in §6 and A6 holds:**

- a separate confirm, which writes only the lines that carry one;
- each change journaled under the operator's actor labelled as the import
  correction, with its before-image;
- the apply's locks;
- a second drop of the same file finds nothing more to correct;
- no `/api/v1` route and no MCP tool;
- a hash hit still inserts and changes nothing (K8);
- no all-clear badge.

**What does not change:**

- the content hash of every row, stored or new;
- §1–§5 and A1–A7, except that A8 narrows A1's split to the kinds it
  names;
- K1–K15, and the converter's worked example (5895.56);
- no format column, no stored file, no import route.

### The identities the building batch pins

Every figure is synthetic, in EUR, on 2026 dates. The names are the cash
accounts Test-Cash and Test-Savings, the depot Test-Depot and the security
Arbolia Inc. (ISIN USEXMPL10014, the fixtures' own). Every figure is exact
in `Decimal`. "The old reading" is what the importer booked before A1: the
cash cell whole, a JSON trade priced the old way, the refund beside it.

| | Identity |
|---|---|
| K16 | A JSON file has three rows: a deposit of 1,000.00 (2026-02-02); an inbound delivery of 10 Arbolia Inc. with a TAX unit of −0.40 (2026-02-03); and a purchase of 5 shares (`amount` 501.00, FEE 1.00, priced 100.00; 2026-02-04). It previews with **one row error**, the delivery's. The other two rows preview and book: Test-Cash **499.00**, and Test-Depot holds 5 shares. Today the apply answers `insert_failed` on the split-off refund and stores nothing. The same history as a PP CSV previews and books the same: an Einlieferung with Steuern −0,40, and the Kauf with Betrag 500,00, Gebühren 1,00 and Gesamtpreis 501,00. Pinned by `json_parser_test.exs` and `csv_parser_test.exs` (the row error; the rest previews) and `negative_tax_booking_test.exs` (the balances). Mutation: drop the deliveries from A8's kinds, and the apply rolls the file back again. |
| K17 | A JSON cash transfer of 100.00 from Test-Cash to Test-Savings with a TAX unit of −5.00 (2026-02-10), after a deposit of 1,000.00, is a row error, and the deposit books: Test-Cash **1,000.00**, and nothing books on Test-Savings. Today the transfer books at 105.00 with the refund on Test-Cash: Test-Cash 900.00 and Test-Savings **105.00**, where PP shows 900.00 and 100.00. Its PP CSV (Umbuchung (Ausgang), Betrag 105,00, Steuern −5,00, Gesamtpreis 100,00) is the same row error; today it books the same 105.00. Pinned by the two parser tests and `negative_tax_booking_test.exs`. Mutation: let A8 split a cash transfer's refund, and Test-Savings reads 105.00. |
| K18 | A JSON purchase of 10 Arbolia Inc. with `amount` 1,003.00 and FEE units 5.00 and −2.00 (2026-03-03), after a deposit of 2,000.00, is a row error, and the deposit books: Test-Cash **2,000.00**. Today the purchase books its cash right, 1,003.00 (Test-Cash 997.00). But it books fees **7.00**, where PP nets 3.00, and a price of **99.60**, where PP's is 100.00. A converter CSV's Gebühren written −2,50 still books a fee of 2,50 (the note of 2026-10-06). Pinned by `json_parser_test.exs`, `negative_tax_booking_test.exs`, and `csv_parser_test.exs`'s "counts a negative Gebühren as the fee it books", unchanged. Mutation: drop A9's check, and the purchase books fees 7.00. |
| K19 | The history: a deposit of 1,000.00 (2026-04-01), a purchase of 10 Arbolia Inc. for 100.00 (2026-04-02), and #1118's sale (`amount` 20.10, 10 shares, FEE 5.00, TAX −25.00; 2026-04-15). It is stored under the old reading: the sale at 20.10, priced 2.51, with the refund 25.00 beside it. Test-Cash reads **945.10**, where PP shows 920.10. A re-drop lists the sale **without a confirm**: Test-Cash +45.10 as stored and +20.10 as the file states, a difference of −25.00, with A5's remedy. Its row error says it is already imported. Nothing writes it: Test-Cash stays 945.10 until the operator replaces the sale by hand. Pinned by `cash_correction_test.exs` and `negative_tax_reimport_test.exs`. Mutation: give the line a confirm, and the test's "nothing to confirm" fails (the ledger would refuse the −4.90 the confirm writes). |
| K20 | K17's JSON file is imported under Sprint 20's reading (release 2026.10.13): its transfer at 105.00, the refund 5.00 on Test-Cash. Dropped again, the transfer is listed **without a confirm**. Test-Cash reads −100.00 both as stored and as the file states. Test-Savings reads **+105.00** as stored and +100.00 as the file states. The same file stored under the old reading (the transfer at 100.00, with the refund beside it) lists Test-Cash −95.00 as stored against −100.00, and Test-Savings +100.00 on both sides. Nothing is written, and the row error says the row is already imported. Pinned by `cash_correction_test.exs`. Mutation: let the confirm correct the transfer's cash, and Test-Cash ends 905.00 with the refund still beside it. |
| K21 | The history: a deposit of 1,100.00 (2026-03-02), a purchase of 10 Arbolia Inc. for 100.00 (2026-03-03), a dividend of 9.13 (2026-05-15), and a sale of K9's shape (`amount` 120.00, 10 shares, FEE 5.00, TAX −25.00; 2026-06-15, 15:30). It is stored under the old reading: Test-Cash 1,154.13. The dividend is then set to 9.20 by hand (`owner_ui`): Test-Cash 1,154.20. A re-drop lists the sale with a confirm (120.00 → 95.00, price 12.50 → 10.00). It names the dividend as edited since its import (9.20 stored, 9.13 per the file), without a confirm. After the confirm, Test-Cash reads **1,129.20**: PP's 1,129.13, plus the operator's 0.07, kept. Today the confirm rewrites the dividend too, to 1,129.13. A cross-currency sale whose only update since its import is the backfill's legs (`system_job`, "settlement_backfill") is still listed with its confirm. Pinned by `cash_correction_test.exs`. Mutations: ignore the journal, and the dividend reads 9.13; count the backfill's update as an edit, and the cross-currency sale is not corrected. |
| K22 | K21's sale is stored with its import hash at the cash 95.00 and the price 12.50, and its journal holds no other actor's edit (the test stores it so). Today it is not listed, and its realized result reads **+20.00**. After the change it is listed with a confirm: its cash 95.00 on both sides (a difference of 0.00) and its price 12.50 → 10.00. The confirm writes the price alone, and the realized result reads **−5.00**: proceeds of 95.00 against a cost of 100.00, as K12 has it. Pinned by `cash_correction_test.exs`, beside "a JSON sale whose price agrees lists its cash alone". Mutation: compare the price only after the cash (today's `changes/3`), and nothing is listed. |
| K23 | The history: a deposit of 1,100.00, a purchase of 10 Arbolia Inc. for 100.00, and K21's sale. It is stored under the old reading: Test-Cash **1,145.00**. A re-export with the sale's time moved from 15:30 to 15:31 books nothing (K11). It lists the sale as "matched by its figures", with a confirm: 120.00 → 95.00, price 12.50 → 10.00. After the confirm, Test-Cash reads **1,120.00**, PP's balance. Today nothing is listed, and Test-Cash stays 1,145.00. Pinned by `cash_correction_test.exs` and `negative_tax_reimport_test.exs`. Mutation: list hash hits only (today's `detect/3`), and nothing is listed. |
| K24 | Twins. The history: a deposit of 1,100.00, a purchase of 20 Arbolia Inc. for 200.00, and two equal sales on 2026-06-15, A at 15:30 and B at 16:10, each of K21's shape. Both are stored under the old reading: Test-Cash **1,190.00**, where PP shows 1,140.00. (i) A re-export that moves both times by a minute lists both sales without a confirm ("two stored bookings match these figures"), and the section offers no confirm. (ii) A re-export that moves only B's time lists A with a confirm (its hash hit) and B without one (two bookings match B's figures). The confirm corrects A: Test-Cash **1,165.00**. A second drop of that file lists B with a confirm (its twin corrected, so one booking matches), and that confirm brings Test-Cash to **1,140.00**. Pinned by `cash_correction_test.exs`. Mutation: test the key's membership instead of counting its bookings, and (i) offers a confirm. |
| K25 | A digest list is taken on unchanged code (`main` at 6f9d7d1) before the first change. It covers every row of the K16–K24 files and every refund split off them. Each digest comes from the row's entry or, for a row the code already refuses (K19's sale, under A5), from the would-be entry the preview keeps. After every commit each row hashes byte-identically, including a row that A8 or A9 now refuses. K2's and K10's lists stay as they are. Pinned by `csv_hash_pin_test.exs`. Mutation: fold the FEE units with their sign in the would-be entry, and K18's purchase hashes over fees 3.00 instead of 7.00 and fails its digest. |
| K26 | Every confirm journals one update per booking it writes, under `owner_ui` labelled "import correction", with its before-image. It writes no line that carries no confirm, and it keeps every `import_hash` and id. A second drop of K21's file after its confirm lists the dividend alone, still edited since its import, and offers no confirm. A second drop of K23's file lists nothing. The ordinary apply of every file above changes no stored value (K8). Pinned by `cash_correction_test.exs` and `imports_correction_live_test.exs` (the section's states, and no confirm button when no line carries one). Mutation: let the confirm write every listed line, and K19's ledger refusal rolls the whole confirm back. |

### The asks, answered and deferred (ADR-0043)

**Where the asks come from:** the bodies and comments of #1188, #1193,
#1194, #1205 and #1177, and the asks table of the amendment of 2026-10-07.

| Ask | Source | Verdict |
|---|---|---|
| A delivery or a security transfer with a negative tax unit rolls back the whole file | #1188 | **Answered.** A8: a row error with its remedy, in both parsers; the rest previews |
| A cash transfer with a negative tax unit books its receiver r too high | #1188, the comment of 2026-10-08 | **Answered.** A8, and A10 for a transfer already stored |
| A negative FEE unit is stored as a positive fee | #1177; the amendment of 2026-10-07, deferred | **Answered for now.** A9: a row error until a fee-refund kind exists. No hash changes |
| PP JSON's `INTEREST_CHARGE` and `FEE_REFUND` types, and how a fee refund books | #1177 | **Deferred, with a reason.** They need two new ledger kinds, `interest_charge` (cash out, a cost) and `fee_refund` (cash in, a negative cost). Those change the data model and the Costs report, so they need an ADR-0028 amendment of their own. Until then the two types are named, refused rows, and A9 refuses a negative FEE unit. #1177 stays open, `needs-decision` |
| How the correction treats a stored booking whose row A5 now refuses | #1193 | **Answered.** A10: listed with its figures and its remedy, without a confirm |
| A booking edited by hand since its import | #1194, the first case | **Answered.** A11: named from the journal, never rewritten |
| A JSON trade whose cash agrees while its price does not | #1194, the second case | **Answered.** A11: listed on its cash or its price |
| A drifted re-export leaves a booking stored under the old reading wrong without a word | #1205 | **Answered.** A12, with the twin rule |
| A refused row whose re-export drifted | found while writing A10 | **Deferred, with a reason.** A refused row is a preview error, and the dry run does not resolve it, so it has no economic key. A10 therefore finds its stored booking by its hash alone, and its row error gives the refusal's remedy, which would book it a second time. The case needs a refused row (rare) whose re-export also drifted (rare), and fixing it means resolving refused rows outside the apply's run. Filed at the signature |
| A ledger form for a sale whose proceeds are negative | #1193, what would reopen it | **Not taken.** A5 stands: it needs a fee companion that the hash would not read |
| A per-line choice that lets the file win over a hand edit | #1194, what would reopen it | **Not taken.** Reopened by an operator who asks for it |

### Consequences of the amendment

- **Risk-tier attention.** The parsers (A8, A9) and the correction
  (A10–A12) each ship as their own commit group, TDD first, with exact
  `Decimal` fixtures, in this order:
  1. K25's digest list is the first commit, taken while the code is still
     unchanged, with the K16–K24 files as its fixtures;
  2. the red tests come next: K16–K18 at the parsers and the apply, then
     K19–K24 at the correction, each failing for the reason this record
     names;
  3. the parsers come before the correction, because A10 reads the would-be
     entries that A8 and A9 keep: A8 first, then A9;
  4. the correction follows, each step in its own commit: A10; A11 (the
     journal, then the price); A12 (the economic match, then the twin
     rule);
  5. the section's states are built last, against the board.

  The verification pass takes K16–K26 one at a time:
  - K25 and K26 first, because they protect every instance that has
    already imported and every write the confirm makes;
  - then K19, K20, K21 and K24, the four that keep a write from happening;
  - then the rest.

  Each mutation check runs once and is reverted. The reviewer briefing
  calls out each of them.
- **The board.** The Sprint 21 planning PR's board draws these items
  before anything is built:
  - the correction section's three new line states: not correctable here
    (A10); edited since its import (A11); matched by its figures, with a
    confirm and without one (A12);
  - the text of A8's and A9's row errors;
  - the price-only line (A11);
  - the section's heading and finding sentence, which now cover lines
    without a confirm;
  - its confirm, which counts and totals only the lines it writes and is
    absent when no line carries one;
  - its state while the dry run that A12 reads has not answered.
- **Coverage, both ways.** The correction keeps no `/api/v1` route and no
  MCP tool, and the refusals are preview rows, because the import is an
  operator action (ADR-0029; §6). Every corrected value is read through the
  existing reads. The PR says so.
- **ADR-0029 gains no note,** because no hash input changes. ADR-0017's
  journal is read, not changed. The two deferred types wait for their
  ADR-0028 amendment.
- **The handbooks** (EN, DE) gain three things in "A negative tax inside a
  row": a delivery or a transfer with a tax refund, a fee refund, and the
  correction's three new line states.
- **The owner's instance.** Until the release that builds this amendment,
  a correction confirmed on the live instance rewrites a booking edited by
  hand since its import, and misses a drifted row. The Sprint 21 plan asks
  the owner to hold that confirm until then.
- **Registry.** #1188, #1193, #1194 and #1205 close by the keyword of the
  PR that builds this amendment. #1177 stays open for its two types,
  relabelled `needs-decision`. The refused row whose re-export drifted is
  filed at the signature under #416.
- Nothing here creates, stores or transmits an order. Nothing acquires data
  the instance does not already hold, and nothing calls out.

## References

- [ADR-0029](0029-stable-identities-and-reimport-survival.html): the identity ladder, the content hash and its 2026-09-25 amendment
- [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html): §2, the post-merge re-import contract; §3, hash first
- [ADR-0036](0036-risk-tier-rides-the-batch.html): risk-tier attention
- [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html): the asks table
- Portfolio Performance source (`master`, read 2026-10-04): `name.abuchen.portfolio.ui/.../views/TransactionsViewer.java`, `.../views/AllTransactionsView.java`, `.../util/TableViewerCSVExporter.java`, `.../messages_de.properties`; `name.abuchen.portfolio/.../model/PortfolioTransaction.java`, `.../model/AccountTransaction.java`, `.../json/JTransaction.java`, `.../money/Values.java`
- [ADR-0017](0017-append-only-audit-journal.html): the journal that the amendment of 2026-10-09 reads (A11)
- `Portfolixir.Imports.PortfolioPerformance.CsvParser`, `Portfolixir.Imports.ImportHash`, `Portfolixir.Imports.DedupKey`, `Portfolixir.Ledger.Projection`
- `Portfolixir.Imports.PortfolioPerformance.JsonParser`, `Portfolixir.Imports.Correction`, `Portfolixir.Imports.Applier` (`booked_before?`, `old_reading`, `reimport_counts/3`), `Portfolixir.Journal.Entry`, `Portfolixir.Ledger.SettlementBackfill`, `Portfolixir.Lifecycle.MergeWriter`
- `_bmad-output/implementation-artifacts/sprint-plan-2026-10-04-sprint19.md`, the plan that signs this record
- `_bmad-output/implementation-artifacts/sprint-plan-2026-10-09-sprint21.md`, the plan that signs the amendment of 2026-10-09
