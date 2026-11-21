defmodule Portfolixir.LockTable do
  @moduledoc """
  The lock-order table: every writer of `cash_accounts` and `transactions`
  rows, since Sprint 28 news.assign against the security merge, and since
  Sprint 29 a news rating against a fetch, a promotion and an assignment, and
  the chain reader against itself and a rebinding, since Sprint 30 a news
  fetch, a feed's write and the news matcher against the security merge
  (the matcher against a security's delete too) and a setting's write
  against another of the same setting, since Sprint 31 a recluster of a
  scope's stories against the security merge, with
  the locks it takes in the order it takes them (Sprint 21's D-7;
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
  | 13 | **Security merge** (`Lifecycle.SecurityMerge.apply/4`, under `Lifecycle.MergeFlow.transaction/2`) | `adv(account identity, every portfolio)` → `adv(ISIN writes, both securities' ISINs)`, ascending key order → the depots either security names `NKU`, id order → both securities `U`, id order → their bookings `U` → its writes on rows it holds (a collapsed row deleted with its hash retired: `adv(import hash)` `X`, held to commit; a news identity change of the target re-matches under `adv(matcher)`; `News.reassign_security/3`: the source's feeds `NKU`, its news items and those ambiguous between the two `U` by UPDATE, its stories, then `adv(story scope)` of the target per language). Locks no cash. |
  | 14 | **Split booking** (`Ledger.Splits.book_split/2`) | `adv(split event, security)` → the security `KS` (H60) → the fan-out read (plain reads) → INSERT one booking per portfolio (`FK` on portfolio; the security's `KS` already held). |
  | 15 | **Split delete** (`Ledger.Splits.delete_split/3`) | the anchor read → `adv(split event, security)` → the security `KS` (H60); a security merged away meanwhile: the anchor read again by id, then `adv(split event, its new security)` → that security `KS`, once → the event's rows `U`, id order → DELETE each (row 4, held). |
  | 16 | **The booking drawer** (`PortfolixirWeb.TransactionManagementLive`) | A booking is row 2. An edit is row 3: it sends no cash account (a buy or a sell keeps the stored one), a notes-only edit sends the note alone. A delete is row 4, a split's row 15. An edit answered `:raced` keeps the drawer open and says to try again. |
  | 17 | **Settlement backfill** (`Ledger.SettlementBackfill`) | row 3 per booking (`Ledger.derive_settlement_legs/3`, which re-checks under the row's lock that no leg is stored and that the inputs of the legs, read lock-free with the candidates, are unchanged: the cash, fees, taxes, quantity, price, type, date, currency and security; otherwise it writes nothing and the run counts the booking in `skipped_changed`, #1196); it changes settlement legs only and so takes no cash lock. A booking answered `:raced` stops the run as `{:error, {id, :raced}}`, and the mix task says to re-run it. Also reached from `Fx.RateSync.backfill/1` and `backfill_when_needed/1` after their rate upsert, under the in-VM `:fx_backfill` `SingleFlight` key (a Registry entry, not a database lock), where `:raced` answers `settlement_legs.status` `stopped`; the locks are unchanged. |
  | 18 | **Depot create and relink** (`Portfolios.create_securities_account/2`, `update_securities_account/3`) | A create: `adv(account identity, portfolio)` (the name guard) → INSERT (`FK` on the portfolio and on the linked cash: cash `KS`). A relink to another cash account: depot `NKU` (the journal's lock step) → UPDATE (`FK`: the new cash `KS`); with a rename, `adv(account identity, portfolio)` → depot `U` first (`Lifecycle.AccountNames.with_stored/3`). Locks no booking. |
  | 19 | **Former-names backfill** (`Lifecycle.FormerNamesBackfill`, run by a migration) | per account, in id order: cash (or depot) `U` → UPDATE of its former names, journaled. Locks no booking. |
  | 20 | **The import preview's dry run** (`Imports.Applier.reimport_counts/3`, run by the Imports page, and `Imports.Applier.economic_keys/2`, the same simulation, run by the import correction) | None: a read-only transaction that writes nothing (security review 2026-10-12, H53). It takes neither the account-identity lock (a holder of it stops the dry run at once) nor an ISIN write lock, inserts nothing, and reads the cash currencies without `KS`; a read that would wait for a lock stops it after a short wait. Locks no row. |
  | 21 | **news.assign** (`News.assign_item/4`: API, MCP; closing act, AT4) | every security it may touch `KS`, id order, off an unlocked read of the item: its own, its candidates, and the target or, for `null`, the securities the matcher names then → `adv(matcher)` (ORD5) → `adv(story scope)` of the item's security (`Stories.lock/2`) → the item `U` → the target's `adv(story scope)` → its UPDATE and the reclusters (the stories of both scopes, under the scope locks it holds). Should the item, read again under its lock, or the matcher's answer then name a security the first step did not hold, the transaction rolls back, releasing all of it, and runs again (at most three times, then `422` on `news_id`): no security is locked out of order. |
  | 22 | **A news rating** (`News.Sources.put_source/4` → `News.Retier.run/3`: API, MCP, a seed; ADR-0056 E1, S29 N1) | the source row `U` (or its INSERT, `ON CONFLICT DO NOTHING`) → `adv(news tier)` of its domain `X` and of each parent domain of two labels or more `S`, ascending key → when the write changes the tier and an unpromoted item it decides changes with it: the securities those items name (their own and an ambiguous one's candidates) `KS`, id order (off an unlocked read of the items, under the tier lock, so their set cannot grow) → `adv(matcher)` → `adv(story scope)` of each item's scope and language, in order → the items `U`, id order → their UPDATE, or for a block `Stories.remove/5` (it takes again the scope lock the rating holds) and the DELETE of the unassigned ones → the full reclusters of the scopes (under the scope locks held). An item that moved into a scope whose lock it does not hold rolls the whole write back, releasing all of it, and runs again (at most three times, then `422` on `domain`). |
  | 23 | **A news fetch** (`News.Ingest.ingest/3`; ADR-0056 E1, S29 N1, S30 K1) | the feed's parent, its security or its category, `KS`, off the caller's read of the feed (#1457) → the feed `U`, read again under it (a feed whose parent changed in between rolls the attempt back, releasing both, and runs again on the parent it names now, at most three times) → `adv(news tier)` of every suffix of its items' domains `S`, ascending key, held to its commit → the tier read and the INSERTs (`FK` on the feed, held `U`, and on the parent, held `KS`) → after the commit, in transactions of their own, the matcher (row 26) and the reclusters (row 28). |
  | 24 | **A chain read's writes** (`Chains.Reader.run/2`: the scheduled run and the on-demand refresh; ADR-0059 §5, §6, S29 H3) | an on-demand refresh first claims its try: one conditional upsert of the state row (`chain_reads`, its row lock for that one statement, no transaction; the closing act) → the network reads, outside any transaction → `adv(chain read, chain)` → every security bound to the chain `S`, id order, the binding read again under it → per halving `Events.put_chain_halving/6`: the security `S` again (held), the event `NKU` (the journal's lock step) or its INSERT (`FK` on the security, `KS`) → the state row's upsert (`chain_reads`, unjournaled). Locks no booking. |
  | 25 | **A feed's write** (`News.put_feed/3` on a stored feed: API, MCP; S30 K2) | the feed's security as the caller read it and the security the write binds it to `KS`, id order, or the category the write binds it to `KS` (#1457; never the old category, the closing act's order lens, finding 1) → the feed `NKU` (the journal's lock step), read again under it (a feed whose parent changed in between rolls the attempt back, releasing all of it, and runs again on the feed as it is now, at most three times, then `422` on its binding) → the COR1 check (plain reads of its items) → UPDATE (`FK` on a changed security or category, held `KS`). A create is an INSERT (`FK` on its parent). Locks no item. |
  | 26 | **The news matcher** (`News.assign_aggregator_items/2`: a fetch's match after its commit, row 23; `News.rematch_recent/1`, run by `Catalog`'s news identity change, after its commit or inside a caller's transaction, a merge's included; S30 K2) | an unlocked read of the open aggregator items and of the universe → the securities they match `KS`, id order (#1457) → in a savepoint: `adv(matcher)` (ORD5) → the items `U`, id order → the universe compiled again (ORD5) → when it names a security the first step did not hold (an alias committed in between), a rollback to the savepoint, releasing every lock the attempt took, and a run again holding that one too (at most three times, then it raises, writing nothing) → the items' UPDATE (`FK` on an assigned security, held `KS`) → after the commit, the reclusters (row 28). Inside a caller's transaction that already holds `adv(matcher)`, the rollback to the savepoint keeps that lock. |
  | 27 | **A setting's write** (`Settings.set_default_view/2`, `set_news_cluster_window_hours/2`, `set_news_cluster_similarity/2`, `set_crash_benchmark/2`: API, MCP, the view switcher, the news settings; S29 C1, S30 A3) | `adv(setting key)` of the one setting it writes → the setting row `U`, read again under it (none while unset) → the crash benchmark only: its security read (plain reads, `BenchmarkSecurity.resolve/1`) → the upsert or DELETE of the setting row. Locks no other row. Without the advisory lock two first writes both read "none" and the later one's journal entry named no before (#1421, #1356). |
  | 28 | **A recluster** (`News.Stories.recluster/4`: a fetch's after its commit, row 23, the matcher's, row 26, a merge's of its target, row 13, an assignment's, row 21, a rating's, row 22, a security delete's of the securities its items fall to (`News.forget_security/2`); `Stories.remove/5`: retention and a rating's block; `Stories.lock/2`: an assignment, a rating, a promotion; ADR-0056 B3, S31 K1) | the scope's parent, its security or its category, `KS` (#1470; none when it no longer exists) → `adv(story scope)` of the scope and language → `remove/5` only: the doomed items `U`, then their `cluster_id` cleared, emptied stories deleted (`U`) and the others' representatives rewritten, the items deleted → the plain reads of the scope's items and stories → each story's UPDATE (the row `NKU`; a changed representative `FK`: the item `KS`) or INSERT (`FK` on the parent, held `KS`, and on the representative item, `KS`) → the items moved into the stories, UPDATE (`NKU`; `FK` on the story `KS`) → the merged stories' DELETE (`U`). A caller that already holds the parent (rows 13, 21, 22, a promotion) takes it again at no wait. Locks no booking. |

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
    * Row 21 against row 13: the security merge holds both securities `U`
      and then writes the source's news items, and may re-match under
      `adv(matcher)` (`Catalog`'s identity change inside its transaction);
      news.assign takes its securities `KS` before `adv(matcher)` and any
      news row, so whichever reaches the securities first goes through and
      the other waits there holding nothing the first asks for (S28 N3/N4
      attack, AT4: before, the assignment held the item and then asked the
      target, and both orders deadlocked).
    * Row 13 against a promotion (`News.Promotion.append_note/4`; the
      closing act's order lens, finding 2): the merge holds both securities
      `U` and then UPDATEs the source's items and stories; the promotion
      takes its story's security `KS` before `adv(story scope)` and its
      members `U`, so whichever reaches the security first goes through and
      the other waits there holding nothing the first asks for. A merge
      released by a committed promotion finds the note on its source and
      refuses on its `research_notes` guard; a promotion released by a
      merge finds the story moved to the target and refuses it, naming
      `cluster_id`. Before, the promotion held the members and then the
      note's `FK` asked the security, and both orders deadlocked.
    * Row 28 against row 13 (#1470, S31 K1): the merge holds both
      securities `U` and then UPDATEs the source's items (`scope_at`), its
      stories (`security_id`, a column of a unique index, so each story
      `U`, its items following by the cascade) and its items again; a
      recluster of the source's scope (a fetch's after its commit, the
      matcher's, an assignment's) takes the security `KS` before its
      advisory lock and any story or item, so whichever reaches the
      security first goes through and the other waits there holding
      nothing the first asks for. A recluster that waited on the merge
      reads the source's scope empty and writes nothing; the merge's own
      full recluster of the target has folded its items in. Before, the
      recluster held a story it had written and then asked the items it
      moved into it, while the merge held those items and then asked the
      story, and both orders deadlocked; the fetch's recluster, lost that
      way, was only logged. Retention (`remove/5`) takes the same parent
      first, before its items `U`, whose story INSERT would otherwise have
      asked the security after them.
    * Row 28 against a label write, a promotion, a feed's write (row 25)
      and a category's delete: the label write holds its suggested
      security `KS` and its story `KS`, which a recluster's `KS` and a
      story's UPDATE (`NKU`) do not conflict with; a recluster deleting
      that story waits for the label, which asks nothing the recluster
      holds. A promotion takes its story's security `KS` before the same
      advisory lock, as row 28 does. A feed's write locks no story or
      item. A category's delete holds the category `U` and then checks the
      rows that name it `KS`: a recluster of the category's scope meets it
      at the category, before any story or item.
    * Row 13 against a label write (`News.Labels.put/2`, `news.label`; the
      closing act's order lens, finding 3): `adv(news label, story, model,
      prompt version)` → the suggested security `KS` → the story `KS` → the
      label's INSERT or UPDATE. The merge holds both securities `U` and then
      UPDATEs the source's stories' `security_id`, a column of a unique
      index, so it asks each story `U`; the label write takes its suggested
      security before its story, so whichever reaches the security first
      goes through and the other waits there holding nothing the first
      asks for (the merge takes no label key): a write released by a
      merge finds the source gone and refuses naming
      `suggested_security_id`. A write that suggests no
      security, or another one, holds only its story, asks nothing the
      merge holds, and the merge waits for it. Before, the write held the
      story and then asked the security, and both orders deadlocked.
    * Row 21 against row 26 and retention (`Stories.remove/5`:
      `adv(story scope)` → items): `KS` does not conflict with `KS`, and
      all three take their advisory lock before any news row; rows 21 and
      26 take their securities before it.
    * Row 26 against row 13 and a security's delete (#1457, S30 K2): the
      merge holds both securities `U` and then UPDATEs the items ambiguous
      between them; the delete (`Lifecycle.Delete`) holds its security `U`
      and then UPDATEs the items that list it (`News.forget_security/2`).
      The matcher takes the securities it matches `KS` before
      `adv(matcher)` and the items, so whichever reaches a security first
      goes through and the other waits there holding nothing the first
      asks for; a matcher that waited reads the items as the merge or the
      delete left them (one it assigned is no longer open and is skipped)
      and a security deleted meanwhile is not held, so no item is assigned
      to, or listed with, it. An item whose current match names neither
      security takes no lock either holds: the matcher holds it and asks
      nothing more of them. A merge that re-matches inside its transaction
      takes `adv(matcher)` after its securities and before its item
      UPDATEs, as row 26 does. Before, the matcher held the items and then
      asked the securities, and both orders deadlocked; a re-match after
      an identity change's commit lost that way was only logged, its
      items left unmatched.
    * Row 23 against row 13 (#1457, S30 K1): the merge holds both
      securities `U` and then asks the source's feeds `NKU`
      (`News.reassign_security/3`); the fetch takes the feed's security
      `KS` before the feed, so whichever reaches the security first goes
      through and the other waits there holding nothing the first asks for.
      A fetch that waited on a merge of the feed's security finds the feed
      moved to the target under its lock, runs again on the target and
      stores its items there. Before, the fetch held the feed and then its
      items' `FK` asked the security, and both orders deadlocked. A
      category's delete (`Classifications.delete_category/2`: the category
      `U`, then the restrict check of the feeds that name it, `KS` on them)
      meets a thematic fetch the same way, at the category.
    * Row 25 against row 13 (#1457, S30 K2): the merge holds both
      securities `U` and then asks the source's feeds `NKU`; a feed's write
      takes the feed's old and new security `KS` before the feed, so
      whichever reaches a security first goes through and the other waits
      there holding nothing the first asks for. A re-binding that waited on
      a merge of its feed's security finds the feed on the target under its
      lock, runs again on it and writes the binding asked onto the feed as
      the merge left it. Before, the write held the feed and then its
      UPDATE's `FK` asked the new security: a merge holding it deadlocked
      with it, and one asking the feed after the write held it deadlocked
      too. The old parent's `KS` also keeps a merge's move of the source's
      feeds from overwriting a re-binding committed between its read of
      those feeds and its lock on them.
    * Row 25 against a category's delete (`Classifications.delete_category/2`:
      the subtree's categories leaves first, each DELETE taking the row `U`,
      then its restrict check's `KS` on the feeds that name it; the closing
      act's order lens, finding 1): the write takes only the category it
      binds the feed to `KS`, before the feed, so they meet at that one
      category: a delete holding it makes the write wait, which then finds
      it gone; a write holding it makes the delete wait, which then refuses
      on the feed that names it. Its `KS` on the feed does not conflict with
      the write's `NKU`. No category merge moves feeds, so the old category
      guards nothing; taking it too, in id order, held a parent and asked
      its child, while the delete held the child and asked the parent, and
      both orders deadlocked.
    * Row 25 against row 23: both take the feed's parent `KS` (which does
      not conflict with `KS`) before the feed, so they meet at the feed: a
      fetch holding it `U` makes the write wait, and the write's COR1 check
      then sees the items the fetch stored; a write holding it `NKU` makes
      the fetch wait, which then reads the feed as written and runs again
      on its new parent (row 23).
    * Row 22 against row 23: a rating holds its domain's tier key `X`, a
      fetch the key of every suffix of its items' domains `S`, so they meet
      exactly when the rating's row could decide one of the fetch's items:
      a fetch holding its keys makes the rating wait until its items are
      committed, and the rating then re-rates them; a rating holding its key
      makes the fetch wait before its tier read, which then reads the row
      as written. Neither waits on anything else the other holds: the
      rating takes no feed, and a fetch's uncommitted items are invisible
      to it. Every holder takes its tier keys in ascending order, so no
      cycle forms among them.
    * Row 22 against row 22: two ratings of one domain meet at its row;
      two of which one domain is a parent of the other meet at the
      parent's tier key (`X` against `S`), so the later reads the earlier's
      row and each re-rates only what its own row decides; two of
      unrelated domains do not wait for each other (both may take a common
      parent's key `S`).
    * Row 22 against rows 13, 21 and 26: the rating takes the
      securities `KS` before `adv(matcher)` and any news row, as row 21
      does, so it meets a merge (or a delete) holding a security `U` there,
      and an assignment or a match at `adv(matcher)`, holding nothing the
      other asks for.
    * Row 22 against a promotion (`News.Promotion.append_note/4`: the
      story's security `KS` → `adv(story scope)` → members `U` → the note's
      INSERT, `FK` on the security, held `KS`) and retention (`Stories.remove/5`): both take the scope
      lock before any item; the rating takes its scope locks before its
      items, so whichever holds the scope first commits wholly first (E1:
      a member promoted first keeps its tier, one re-rated first is
      promoted at its new tier).
    * Rows 14 and 15 against row 12: the depot merge takes the securities'
      split rows `U` after its depots and bookings and the security only
      `KS`; the split's `KS` does not conflict with it.
    * Row 27 against row 27: two writes of one setting meet at its key
      before any row, so the later reads the row the earlier committed and
      journals it as its before; writes of different settings take
      different keys and never wait for each other. Row 27 against every
      other row: none takes a setting's key or its row, and row 27 takes no
      other row, so it closes no cycle.
    * Row 24 against row 24: two runs of one chain meet at `adv(chain
      read)` before any row; the later reads what the earlier committed, a
      confirmed halving it skips and the day's estimate it leaves, so each
      halving is written once (S29 H3).
    * Row 24 against a rebinding (`Catalog.update_security/4` changing
      `halving_chain`: the security `NKU`, the journal's lock step → UPDATE
      → its halving events `U`, id order → DELETE each): both take the
      security before any event. A run holding it `S` makes the rebinding
      wait, which then deletes the halvings the run wrote; a rebinding
      holding it makes the run wait, which then reads the security unbound
      and leaves it out. Row 13 meets row 24 the same way: the merge takes
      both securities `U` before their events.
  """
end
