defmodule Portfolixir.LockTable do
  @moduledoc """
  The lock-order table: every writer of `cash_accounts` and `transactions`
  rows, with the locks it takes in the order it takes them (Sprint 21's D-7;
  Sprint 20's retrospective). The lock-race harness (`Portfolixir.LockRace`)
  pins the pairs that meet; this table is what a new lock is checked
  against. **A new lock is reviewed against every row here that locks the
  same rows in another order, not only against the race it closes**, and the
  row it changes is updated in the same commit.

  ## How two locks meet

  The modes, weakest first, and the stronger ones each conflicts with
  (PostgreSQL's row-lock table):

    * `KS`, `FOR KEY SHARE`: a foreign-key check takes it on the parent row.
      Conflicts with `U` only.
    * `S`, `FOR SHARE`. Conflicts with `NKU` and `U`.
    * `NKU`, `FOR NO KEY UPDATE`: the journal's lock step for an update
      (`Portfolixir.Journal.record/3`), and an UPDATE that changes no key.
      Conflicts with `S`, `NKU` and `U`.
    * `U`, `FOR UPDATE`: the journal's lock step for a delete, the merges,
      the identity-field freeze, the hardened delete. Conflicts with all.
    * `adv(name)`: a transaction-scoped advisory lock; it meets only writers
      that take the same key. `adv(import hash)` is one key for the whole
      database (#917, migration `20261006120000`), taken by a trigger, not
      by the application: shared (`S`) by a booking INSERT that carries an
      import hash, exclusive (`X`) by a retirement of a hash; shared holders
      never wait for each other.

  A cycle needs two writers that each hold one lock the other then asks for
  in a conflicting mode. Plain reads take no lock and wait on none.

  ## The rule the table keeps

  **A writer that holds both a cash account and a booking takes the account
  first.** More generally the advisory locks come before every row lock, a
  parent row (a cash account, a depot, a security) before the bookings that
  name it, and depots before securities (ADR-0050 §10); a writer that takes
  several rows of one table takes them in id order.

  ## The writers

  `cash` is a `cash_accounts` row; `booking` is a `transactions` row; `FK`
  is the `KS` lock an INSERT or an UPDATE of a foreign-key column takes on
  the parent it names (an UPDATE only on the columns it changes).

  | # | Writer | Its locks, in order |
  |---|---|---|
  | 1 | **Cash merge** (`Lifecycle.CashMerge.apply/4`, under `Lifecycle.MergeFlow.transaction/2`) | `adv(account identity, portfolio)` → both cash `U`, id order → every booking of either `U`, id order → the depots linked to the source `U` → its writes on rows it holds: rows deleted with their hashes retired (each retirement `adv(import hash)` `X`, the trigger on `retired_import_hashes`, held to commit), anchors restated, rows and depots re-pointed (`FK` on the target, held), the source deleted through `Lifecycle.Delete.remove/2` (bucket links: cash `NKU`, held; buckets `S`), the target's former names. A 40P01 or a lock timeout answers `:raced`, then a fresh preview. |
  | 2 | **Booking create** (`Ledger.create_transaction/3`: API, MCP, the drawer, `Ledger.set_cash_balance/3`) | cash it names `KS`, id order (`Ledger.locked_cash_account_currencies/1`) → INSERT (`FK` on portfolio, depots, security; the cash `KS` already held). Locks no other booking. |
  | 3 | **Booking update** (`Ledger.update_transaction/3`: API, MCP, the drawer, the import correction, the settlement backfill) | cash it moves the booking onto `KS`, id order, read off the caller's copy of the row (#1214) → booking `NKU` (the journal's lock step) → cash the stored row newly points to `KS` again (held; one a stale copy missed is taken here) → UPDATE (`FK` on each changed reference). Cash its stored row already references takes no lock: that row, held, freezes it (ADR-0050 §11). A 40P01 or a lock timeout answers `:raced`, or is raised on inside a caller's transaction. |
  | 4 | **Booking delete** (`Ledger.delete_transaction/2`: API, MCP, the drawer's delete dialog, the merges' row deletes) | booking `U` (the journal's lock step) → DELETE. Locks no parent. |
  | 5 | **Currency change and identity freeze** (`Portfolios.update_cash_account/3` → `Lifecycle.Freeze.validate/1`) | Without a rename: cash `NKU` (the journal's lock step) → cash `U` (the freeze, `prepare_changes`) → reference count (plain reads) → UPDATE. With a rename or a portfolio move (`Lifecycle.AccountNames.with_stored/3`): `adv(account identity, old and new portfolio)` → cash `U` → the same. Locks no booking. |
  | 6 | **Cash account create** (`Portfolios.create_cash_account/2`) | `adv(account identity, portfolio)` (the name guard) → INSERT (`FK` on the portfolio). |
  | 7 | **Former names** (`Lifecycle.AccountNames.remember/4`, `remove_former_name/3`) | `adv(account identity, portfolio)` → cash `NKU` → UPDATE. Locks no booking. |
  | 8 | **Hardened delete** (`Portfolios.delete_cash_account/2` → `Lifecycle.Delete.delete/2`) | cash `U` → reference count (plain reads) → bucket links (cash `NKU`, held; buckets `S`) → DELETE. Locks no booking. |
  | 9 | **Importer** (`Imports.Applier.apply/2`, both paths, one transaction of up to ten minutes) | Mapped path without a portfolio: the default portfolio is resolved first, before the transaction opens, in a short one of its own that commits it (`Portfolios.default_portfolio/1`: `adv(default portfolio)`, then the record read again and created when none exists; H54). Then, in the import's transaction, `adv(account identity, portfolio)` → `adv(ISIN writes)` of the whole file, once (#1287): the key of each security whose ISIN change the mapping records, ascending id, then every ISIN the file's security references carry, ascending key order (`IdentifierAliases.lock_security_isin_writes/3`) → remembered names (row 7: cash `NKU`) → per row: a security it creates with an ISIN (`Catalog.create_security/2` → `IdentifierAliases.guard_isin_not_aliased/2`), and an ISIN change it records, take their ISIN locks again, which the transaction already holds → an account it creates (INSERT, `FK`) → cash the row names `KS`, id order (`Ledger.locked_cash_account_currencies/1`) → INSERT booking (`FK`; a booking with an import hash also `adv(import hash)` `S`, the trigger on `transactions`, taken at the first such INSERT and held to commit) → the bucket tag (row 11). Locks no stored booking. |
  | 10 | **Import correction** (`Imports.Correction.apply/3`, and `apply_listed/4` for the page's confirm) | One transaction: `adv(account identity, portfolio)` → when a row without a hash hit reads otherwise under A4's old reading, the economic keys from the apply's simulated run, made inside this transaction under the lock it holds (`Applier.economic_keys_in_transaction/2`: row 20's reads and in-memory creations, with no lock of its own and no write) → the bookings holding the file's hashes `NKU` (`detect(lock: true)`) → when a row without a hash hit has keys, every booking of the portfolio `NKU` → each refused row's hash rows `NKU` (the portfolio's own bookings, already held when the scan ran) → per confirmable booking, row 3 (amounts only, no cash lock; its booking already held). Several rows are taken by id. The page's listing before the confirm takes no lock: its keys come from row 20's run. |
  | 11 | **Bucket writers** (`Buckets.set_cash_account_buckets/3`, `set_depot_default_buckets/3`, `set_position_override/4`, `delete_bucket/2`) | the owner (depot or cash) `NKU` → an override's security `KS` → buckets `S`, id order. `delete_bucket/2`: views, depots, cash `NKU`, each in id order → the bucket `U`. Locks no booking. |
  | 12 | **Depot merge** (`Lifecycle.DepotMerge.apply/4`, under `Lifecycle.MergeFlow.transaction/2`) | `adv(account identity, portfolio)` → both depots `U`, id order → every booking either names `U`, id order → the portfolio's split rows of their securities `U` → its writes on rows it holds (rows deleted with their hashes retired: `adv(import hash)` `X`, held to commit; override writes: security `KS`, buckets `S`; the source deleted; the target `U` for its names). Locks no cash: a moved booking keeps its cash account. |
  | 13 | **Security merge** (`Lifecycle.SecurityMerge.apply/4`, under `Lifecycle.MergeFlow.transaction/2`) | `adv(account identity, every portfolio)` → `adv(ISIN writes, both securities' ISINs)`, ascending key order → the depots either security names `NKU`, id order → both securities `U`, id order → their bookings `U` → its writes on rows it holds (a collapsed row deleted with its hash retired: `adv(import hash)` `X`, held to commit). Locks no cash. |
  | 14 | **Split booking** (`Ledger.Splits.book_split/2`) | `adv(split event, security)` → the security `KS` (H60) → the fan-out read (plain reads) → INSERT one booking per portfolio (`FK` on portfolio; the security's `KS` already held). |
  | 15 | **Split delete** (`Ledger.Splits.delete_split/3`) | the anchor read → `adv(split event, security)` → the security `KS` (H60); a security merged away meanwhile: the anchor read again by id, then `adv(split event, its new security)` → that security `KS`, once → the event's rows `U`, id order → DELETE each (row 4, held). |
  | 16 | **The booking drawer** (`PortfolixirWeb.TransactionManagementLive`) | A booking is row 2. An edit is row 3: it sends no cash account (a buy or a sell keeps the stored one), a notes-only edit sends the note alone. A delete is row 4, a split's row 15. An edit answered `:raced` keeps the drawer open and says to try again. |
  | 17 | **Settlement backfill** (`Ledger.SettlementBackfill`) | row 3 per booking (`Ledger.derive_settlement_legs/3`, which re-checks under the row's lock that no leg is stored and that the inputs of the legs, read lock-free with the candidates, are unchanged: the cash, fees, taxes, quantity, price, type, date, currency and security; otherwise it writes nothing and the run counts the booking in `skipped_changed`, #1196); it changes settlement legs only and so takes no cash lock. A booking answered `:raced` stops the run as `{:error, {id, :raced}}`, and the mix task says to re-run it. Also reached from `Fx.RateSync.backfill/1` and `backfill_when_needed/1` after their rate upsert, under the in-VM `:fx_backfill` `SingleFlight` key (a Registry entry, not a database lock), where `:raced` answers `settlement_legs.status` `stopped`; the locks are unchanged. |
  | 18 | **Depot create and relink** (`Portfolios.create_securities_account/2`, `update_securities_account/3`) | A create: `adv(account identity, portfolio)` (the name guard) → INSERT (`FK` on the portfolio and on the linked cash: cash `KS`). A relink to another cash account: depot `NKU` (the journal's lock step) → UPDATE (`FK`: the new cash `KS`); with a rename, `adv(account identity, portfolio)` → depot `U` first (`Lifecycle.AccountNames.with_stored/3`). Locks no booking. |
  | 19 | **Former-names backfill** (`Lifecycle.FormerNamesBackfill`, run by a migration) | per account, in id order: cash (or depot) `U` → UPDATE of its former names, journaled. Locks no booking. |
  | 20 | **The import preview's dry run** (`Imports.Applier.reimport_counts/3`, run by the Imports page, and `Imports.Applier.economic_keys/2`, the same simulation, run by the import correction) | None: a read-only transaction that writes nothing (security review 2026-10-12, H53). It takes neither the account-identity lock (a holder of it stops the dry run at once) nor an ISIN write lock, inserts nothing, and reads the cash currencies without `KS`; a read that would wait for a lock stops it after a short wait. Locks no row. |

  ## Where two rows meet

    * Row 1 against rows 2 and 9: both take the cash before any booking, and
      a create holds no booking, so it waits at the cash or the merge waits
      for it.
    * Row 1 against row 3: a note edit holds its booking and asks no cash
      (#922's closing act); a move takes the new cash before its booking,
      as the merge does (#1214). Only an edit built on a stale copy of its
      row still asks a cash after its booking; the side PostgreSQL aborts
      then answers `:raced`, the edit a 409 and the merge a fresh preview.
    * Row 1 against rows 5, 7, 8 and 11: none of them locks a booking, so
      they queue at the cash row.
    * Rows 9 and 10 against row 1: all three take the portfolio's
      account-identity lock first, so they serialize on it before any row
      lock.
    * Row 10 against rows 3, 4, 15 and 17: no cycle. Rows 1, 9, 12 and 13
      take the account-identity lock first, so row 10 meets them there.
      Row 15 holds one booking per portfolio, and row 10 asks only for the
      bookings of its own portfolio, so it never holds one row 15 waits for
      while waiting for another row 15 holds. Rows 3, 4 and 17 hold one
      booking and ask for nothing row 10 holds (row 3's cash `KS` is a lock
      row 10 never takes): row 10 waits for that booking, or the writer
      waits for row 10's.
    * Row 17 against rows 3 and 10: row 17 derives a booking's legs from
      its lock-free candidate read, so an edit (row 3) or a confirm (row
      10) that commits a new cash while row 17 waits on that booking leaves
      the derivation stale. No cycle: each holds one booking at a time, as
      above. The re-check under the booking's lock compares the inputs of
      the legs with that read and leaves a changed booking for a re-run, so
      no leg is stored off a cash the booking no longer carries and the
      settlement guard never stops the run on it (#1196).
    * Row 9 against rows 1, 12 and 13 at `adv(import hash)`, one key for
      the whole database: an import holds it shared from its first booking
      with a hash to its commit (up to ten minutes), and a merge that
      retires a hash asks for it exclusive after its row locks, so a merge
      in any portfolio waits for every import in flight, and an import's
      first hashed booking waits for a merge's retirement in flight
      (ADR-0050's note on H53 accepts the wait). No cycle: a merge books no
      hash, so it never holds the shared lock while it asks for the
      exclusive one, and the import waits on nothing the merge holds: a
      merge in the import's portfolio, and every security merge, meets it
      at the account-identity lock first, and a cash or depot merge of
      another portfolio holds only that portfolio's rows, which the import
      never locks (a security both name, each takes in `KS` at most).
    * Row 9 against another import and against the ISIN writers of the
      catalog (an ISIN change, an ISIN edit, row 13): each takes its ISIN
      write locks before any row lock, a writer of a stored security's ISIN
      the security's own key first, then the ISINs in ascending key order,
      so two of them queue on the first key both want (#1287).
    * Row 9's default-portfolio lock (H54) is taken first by whoever holds
      it: the import resolves the default in a short transaction of its own
      before it opens its long one, and the API's account creates outside
      any transaction. The screen's account dialog resolves it inside its
      own all-or-nothing transaction (`Portfolios.all_or_nothing/1`), after
      at most the insert of a new tag bucket and before its
      account-identity lock and its cash and depot inserts, and holds it
      to its commit. No holder waits there on a lock a writer queued on the
      default-portfolio lock holds, so it closes no cycle.
    * Row 1 against row 12: the cash merge locks the depots linked to its
      source after the bookings, the depot merge its depots before theirs.
      Two merges whose rows overlap can close a cycle; both run under
      `Lifecycle.MergeFlow.transaction/2`, so the side PostgreSQL aborts
      answers a fresh preview and writes nothing.
    * Rows 12 and 13 lock no cash: they meet row 1 only through bookings,
      which all three take `U` in id order.
    * Rows 14 and 15 meet row 13 at the security, which the split holds in
      `KS` before it reads its fan-out and the merge holds `U` before it
      reads the bookings (H60): either the split reads the merged bookings
      or the merge reads the split's rows. Neither holds a lock the other
      takes before that one: the split flow locks no depot and no booking
      before the security.
    * Rows 14 and 15 against row 12: the depot merge takes the securities'
      split rows `U` after its depots and bookings and the security only
      `KS`; the split's `KS` does not conflict with it.
  """
end
