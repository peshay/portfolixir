---
layout: docs
title: "ADR-0053: a Portfolio Performance CSV books its Gesamtpreis — read as PP writes it, hashed as before, corrected by a separate confirm"
description: "Design gate for #1076, risk-tier (money and import idempotency), signed by the merge of the Sprint 19 planning PR. In Portfolio Performance's CSV export, Betrag is the gross value and Gesamtpreis the cash amount; the importer has booked Betrag as the cash. From now on a row with a Gesamtpreis books it, checked to the cent against Betrag, Gebühren and Steuern, and a row without one (a converter-written file) books its Betrag as before. The import hash keeps reading Betrag, so every stored hash stays valid and a re-drop books nothing. Bookings already made under the old reading are corrected by a separate, journaled confirm that a re-dropped PP CSV feeds."
---

# ADR-0053: a Portfolio Performance CSV books its Gesamtpreis — read as PP writes it, hashed as before, corrected by a separate confirm

- **Status:** Accepted. Owner sign-off is the merge of the Sprint 19 planning
  PR (ADR-0026 step 1, as amended on PR #780: the merge is the signature).
- **Date:** 2026-10-04
- **Amended:** 2026-10-07: the JSON path's negative tax, a converter file's
  negative Steuern, and a credit row that nets to nothing (#1098, #1118; see
  "Amendment (2026-10-07)" below). Adopted by the merge of the Sprint 20
  planning PR.
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
| PP JSON's `INTEREST_CHARGE` and `FEE_REFUND` types, and a negative FEE unit | found while answering #1098 | **Deferred, with a reason.** The two types are refused rows today, named in the preview. A negative FEE unit is stored as its magnitude, which skews a JSON trade's derived price and the costs; it needs a fee-refund companion of its own, as ADR-0029 made for taxes. Filed at the signature |

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

## References

- [ADR-0029](0029-stable-identities-and-reimport-survival.html): the identity ladder, the content hash and its 2026-09-25 amendment
- [ADR-0050](0050-lifecycle-merges-under-a-reimport-contract.html): §2, the post-merge re-import contract; §3, hash first
- [ADR-0036](0036-risk-tier-rides-the-batch.html): risk-tier attention
- [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html): the asks table
- Portfolio Performance source (`master`, read 2026-10-04): `name.abuchen.portfolio.ui/.../views/TransactionsViewer.java`, `.../views/AllTransactionsView.java`, `.../util/TableViewerCSVExporter.java`, `.../messages_de.properties`; `name.abuchen.portfolio/.../model/PortfolioTransaction.java`, `.../model/AccountTransaction.java`, `.../json/JTransaction.java`, `.../money/Values.java`
- `Portfolixir.Imports.PortfolioPerformance.CsvParser`, `Portfolixir.Imports.ImportHash`, `Portfolixir.Imports.DedupKey`, `Portfolixir.Ledger.Projection`
- `_bmad-output/implementation-artifacts/sprint-plan-2026-10-04-sprint19.md`, the plan that signs this record
