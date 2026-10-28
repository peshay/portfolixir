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
      that take the same key.

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
  | 1 | **Cash merge** (`Lifecycle.CashMerge.apply/4`, under `Lifecycle.MergeFlow.transaction/2`) | `adv(account identity, portfolio)` → both cash `U`, id order → every booking of either `U`, id order → the depots linked to the source `U` → its writes on rows it holds: rows deleted, anchors restated, rows and depots re-pointed (`FK` on the target, held), the source deleted through `Lifecycle.Delete.remove/2` (bucket links: cash `NKU`, held; buckets `S`), the target's former names. A 40P01 or a lock timeout answers `:raced`, then a fresh preview. |
  | 2 | **Booking create** (`Ledger.create_transaction/3`: API, MCP, the drawer, `Ledger.set_cash_balance/3`) | cash it names `KS`, id order (`Ledger.locked_cash_account_currencies/1`) → INSERT (`FK` on portfolio, depots, security; the cash `KS` already held). Locks no other booking. |
  | 3 | **Booking update** (`Ledger.update_transaction/3`: API, MCP, the drawer, the import correction, the settlement backfill) | cash it moves the booking onto `KS`, id order, read off the caller's copy of the row (#1214) → booking `NKU` (the journal's lock step) → cash the stored row newly points to `KS` again (held; one a stale copy missed is taken here) → UPDATE (`FK` on each changed reference). Cash its stored row already references takes no lock: that row, held, freezes it (ADR-0050 §11). A 40P01 or a lock timeout answers `:raced`, or is raised on inside a caller's transaction. |
  | 4 | **Booking delete** (`Ledger.delete_transaction/2`: API, MCP, the drawer's delete dialog, the merges' row deletes) | booking `U` (the journal's lock step) → DELETE. Locks no parent. |
  | 5 | **Currency change and identity freeze** (`Portfolios.update_cash_account/3` → `Lifecycle.Freeze.validate/1`) | Without a rename: cash `NKU` (the journal's lock step) → cash `U` (the freeze, `prepare_changes`) → reference count (plain reads) → UPDATE. With a rename or a portfolio move (`Lifecycle.AccountNames.with_stored/3`): `adv(account identity, old and new portfolio)` → cash `U` → the same. Locks no booking. |
  | 6 | **Cash account create** (`Portfolios.create_cash_account/2`) | `adv(account identity, portfolio)` (the name guard) → INSERT (`FK` on the portfolio). |
  | 7 | **Former names** (`Lifecycle.AccountNames.remember/4`, `remove_former_name/3`) | `adv(account identity, portfolio)` → cash `NKU` → UPDATE. Locks no booking. |
  | 8 | **Hardened delete** (`Portfolios.delete_cash_account/2` → `Lifecycle.Delete.delete/2`) | cash `U` → reference count (plain reads) → bucket links (cash `NKU`, held; buckets `S`) → DELETE. Locks no booking. |
  | 9 | **Importer** (`Imports.Applier.apply/2`, both paths, one transaction of up to ten minutes) | Mapped path without a portfolio: the default portfolio is resolved first, inside the transaction (`Portfolios.default_portfolio/1`, no lock). Then `adv(account identity, portfolio)` → remembered names (row 7: cash `NKU`) → per row: an account it creates (INSERT, `FK`) → cash the row names `KS`, id order (`Ledger.locked_cash_account_currencies/1`) → INSERT booking (`FK`) → the bucket tag (row 11). Locks no stored booking. |
  | 10 | **Import correction** (`Imports.Correction.apply/3`) | `adv(account identity, portfolio)` → the listed bookings `NKU` (`detect(lock: true)`) → per booking row 3, which changes amounts only and so takes no cash lock. |
  | 11 | **Bucket writers** (`Buckets.set_cash_account_buckets/3`, `set_depot_default_buckets/3`, `set_position_override/4`, `delete_bucket/2`) | the owner (depot or cash) `NKU` → an override's security `KS` → buckets `S`, id order. `delete_bucket/2`: views, depots, cash `NKU`, each in id order → the bucket `U`. Locks no booking. |
  | 12 | **Depot merge** (`Lifecycle.DepotMerge.apply/4`, under `Lifecycle.MergeFlow.transaction/2`) | `adv(account identity, portfolio)` → both depots `U`, id order → every booking either names `U`, id order → the portfolio's split rows of their securities `U` → its writes on rows it holds (override writes: security `KS`, buckets `S`; the source deleted; the target `U` for its names). Locks no cash: a moved booking keeps its cash account. |
  | 13 | **Security merge** (`Lifecycle.SecurityMerge.apply/4`, under `Lifecycle.MergeFlow.transaction/2`) | `adv(account identity, every portfolio)` → `adv(ISIN writes)` → the depots either security names `NKU`, id order → both securities `U`, id order → their bookings `U` → its writes on rows it holds. Locks no cash. |
  | 14 | **Split booking** (`Ledger.Splits.book_split/2`) | `adv(split event, security)` → the fan-out read (plain reads) → INSERT one booking per portfolio (`FK` on portfolio and security). |
  | 15 | **Split delete** (`Ledger.Splits.delete_split/3`) | the anchor read → `adv(split event, security)` → the event's rows `U`, id order → DELETE each (row 4, held). |
  | 16 | **The booking drawer** (`PortfolixirWeb.TransactionManagementLive`) | A booking is row 2. An edit is row 3: it sends no cash account (a buy or a sell keeps the stored one), a notes-only edit sends the note alone. A delete is row 4, a split's row 15. An edit answered `:raced` keeps the drawer open and says to try again. |
  | 17 | **Settlement backfill** (`Ledger.SettlementBackfill`) | row 3 per booking; it changes settlement legs only and so takes no cash lock. |

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
    * Row 1 against row 12: the cash merge locks the depots linked to its
      source after the bookings, the depot merge its depots before theirs.
      Two merges whose rows overlap can close a cycle; both run under
      `Lifecycle.MergeFlow.transaction/2`, so the side PostgreSQL aborts
      answers a fresh preview and writes nothing.
    * Rows 12 and 13 lock no cash: they meet row 1 only through bookings,
      which all three take `U` in id order.
    * Row 14 meets row 13 at the security only through its INSERT's
      foreign-key check, after its fan-out was read; row 15 meets it only at
      the split rows both lock `U`.
  """
end
