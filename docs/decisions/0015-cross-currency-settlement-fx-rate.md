---
layout: docs
title: "ADR-0015: Cross-currency transaction settlement with a stored FX rate"
description: Decision to allow booking a security in its own currency while settling cash in a different account currency, persisting the settlement FX rate so per-position P&L is FX-honest.
---

# ADR-0015: Cross-currency transaction settlement with a stored FX rate

- **Status:** Accepted
- **Date:** 2026-06-14
- **Amended:** 2026-10-07: a cross-currency booking's fees and taxes are in
  its cash account's currency, and a security-currency figure converts them
  at the trade's own rate (#1108, #1107; see "Amendment (2026-10-07)"
  below). Adopted by the merge of the Sprint 20 planning PR.
- **Amended:** 2026-10-09: a closed trade is in its sell's currency,
  whatever booked its lots, each lot converted through its own stored legs
  or the trade named unavailable; a new buy or sell priced in a third
  currency is refused; and a history backfill that stores rates derives the
  settlement legs they make derivable (#1198, #1199, #1196; see "Amendment
  (2026-10-09)" below). Adopted by the merge of the Sprint 21 planning PR.

## Context

Retail brokers such as comdirect display and settle everything in the account's
base currency. Buying a USD-denominated security through a EUR account produces a
EUR cash debit computed at **the broker's own FX rate**, while the security itself
is priced in USD. The broker confirmation shows both figures: the USD trade amount
*and* the EUR amount debited.

Two earlier decisions collide with this reality:

- Issue #343 (closed) chose to **reject** any transaction whose currency does not
  match its linked cash account, and explicitly put *"automatic FX conversion of
  stored amounts"* out of scope. That reject policy blocks the ordinary comdirect
  flow above.
- Holdings P&L is computed per security in the security's own currency
  ([ADR-0004](0004-holdings-derived-from-transactions.html)). But when a foreign
  trade is forced into the account currency, the stored `avg_cost` is EUR while the
  latest price is USD, so per-position P&L is off by the FX spread — a live case
  showed **+15.4% on day one with zero real movement** ("phantom P&L").

The alternative that would avoid any FX machinery — holding a native-currency cash
account per security currency — is not available at brokers that settle everything
in the base currency, so it cannot be required of users.

Constraints that apply:

- Money and rates are `Decimal`, never floats
  ([ADR-0003](0003-decimal-for-money.html)); decimal money/quote columns use
  precision/scale `20,6`.
- FX always triangulates through the EUR hub
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)); no direct cross
  rates are stored or computed.
- Derived figures stay reproducible from stored data
  ([ADR-0004](0004-holdings-derived-from-transactions.html)); the ledger projection
  reducer is pure ([ADR-0011](0011-unified-ledger-projection.html)).
- A written rounding policy for FX conversion is still pending (#344).

## Decision

Allow a transaction whose **security currency differs from its cash account's
settlement currency**, by storing a **settlement FX rate** on the transaction
instead of rejecting the mismatch.

- **Persist three linked figures:** the trade amount in the security's own currency,
  the cash amount in the settlement (account) currency, and the settlement FX rate
  relating them, all `Decimal` (rate stored at scale `6`, consistent with the
  existing money/quote columns).
- **Source of the rate:** the broker's actual rate, derived as
  `settlement_amount / security_amount` when both legs are known (the comdirect
  case). When only one side is known, fall back to the EUR-hub rate for the date
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)). The rate is never
  a direct cross rate.
- **Honest per-position P&L:** cost basis and P&L are computed in the security's own
  currency from the security-currency amount; the cash leg moves the settlement
  currency. The day-one foreign position reads ~0% on zero real movement.
- **Mismatch now requires a rate, not a rejection** (supersedes the #343 reject
  policy). If no usable rate exists for the pair, the position is marked
  unpriceable via the existing `valued`/`price_source` idiom — never reported with a
  wrong number.
- **EUR-hub valuation is unchanged.** This decision concerns transaction settlement
  and native cost basis only; base-currency totals still come from
  [ADR-0007](0007-currency-conversion-with-exchange-rates.html).

This supersedes the currency-mismatch **reject** policy shipped under issue #343
(which was an issue decision, not an ADR). Implementation is tracked by #388.

## Consequences

**Easier.** Real comdirect-style trades (USD security, EUR settlement) become
bookable; per-position P&L is FX-honest, removing phantom P&L; for the common case
the rate needs no manual entry because it is derivable from the two amounts the
broker already provides, and it is the broker's *actual* rate, the most accurate
available.

**Harder / accepted trade-offs.** New fields land on `Ledger.Transaction`, enlarging
the invariant surface of the auditability core — they must be written only through
`Ledger`/`Imports` public functions. The Portfolio Performance import path must map
PP's cross-currency representation (shares + exchange rate + account-currency amount)
onto the stored settlement FX, preserving import idempotency. Correctness depends on
the pending rounding policy (#344): until it is decided, the stored rate scale (6) is
the working rule and small residual rounding differences are possible.

**Off-limits.** Storing or computing direct cross rates (EUR-hub triangulation
stays authoritative); persisting an FX-distorted `avg_cost`; reintroducing the silent
EUR cost-basis comparison that produced phantom P&L.

## Amendment (2026-10-07): fees and taxes are in the cash account's currency, and a security-currency figure converts them at the trade's own rate

**Status:** adopted by the merge of the Sprint 20 planning PR; risk-tier
(money), so it is signed before the batch that builds it.

### Why

This record stores three linked figures for a cross-currency trade (the
security amount, the settlement amount and the rate) and says nothing about
the currency of its fees and taxes. The ledger has always read them in the
cash account's currency:

- the settlement guard (`Ledger.SettlementGuard`): a purchase's cash is
  settlement + fees + taxes, a sale's settlement − fees − taxes, "read in the
  account currency, the currency of the cash leg they are part of";
- the performance walk, since #1051 (`Performance.trade_cost/2`).

Three readers do not:

- **The trade matcher** (#1108). `Ledger.transaction_for_matcher/2` hands
  the matcher the raw fees and taxes, and `TradeMatcher` adds them to
  quantity × price in the security's currency. A closed trade's basis,
  proceeds and realized result therefore mix two currencies. It reaches the
  security's Trades tab, Income's realized list, the Overview's closed-trades
  card, the trades and realized-gains reads, and `TradeReturn`.
- **The Costs report** (#1107). `Portfolios.Costs` converts fees and taxes
  from the booking's currency, which on a manual cross-currency trade is the
  security's, and a missing rate names the wrong currency.
- **The income report**, found while triaging #1107. `Income` converts a
  booking's cash and taxes from the booking's currency, so a dividend of a
  foreign security credited to an account in another currency is converted
  from the wrong one. The building story proves it with a red test before it
  changes anything.

### What changes

1. **A booking's fees and taxes are in its cash account's currency**, as its
   cash leg is. Every reader converts them, and a cross-currency booking's
   cash, from that currency, never from the booking's or the security's.
2. **A figure kept in the security's currency converts them at the trade's
   own stored `settlement_fx_rate`** (fee ÷ rate): a FIFO lot's basis, and a
   closed trade's proceeds and realized result. That rate is the broker's
   rate for that cash leg, which this record already makes the trade's rate.
   It is transaction data, so the matcher stays pure (ADR-0033's fold rule:
   rates enter as transaction data, never as reducer lookups). A row without
   a stored rate is a same-currency row and is not converted.
3. **A figure in the base currency** (the Costs report, the income report)
   converts them from the account's currency at the hub rate of the
   booking's date, as the walk has done since #1051.
4. **The figures that change move their computation version**, the payloads'
   basis says so, and the API contract gains an entry.

   *Note (2026-10-09, #1108, the Sprint 20 β closing act):* no computation
   version moves, because none of the readers whose figures change carries
   one. The trades and realized-gains reads and the Costs, income and
   deposits-and-withdrawals reports are no registered derived analytic
   (ADR-0039), so no stored value serves their old figures, and the
   performance walk's analytics keep their versions, the walk having read
   the account's currency since #1051. The payloads' basis states the rule
   (`computation_basis.fees_and_taxes`, `computation_basis.currency`), and
   the API contract's entry 16 records the change and says that no
   computation version moves.

**Why the trade's own rate, not a hub rate.** The hub rate of the trade date
is a second, different conversion of cash that was converted once already,
at the broker's rate. Only the trade's own rate makes a closed trade's
realized result in the base currency equal the cash it moved when broker
and hub agree (identity 1). The hub-rate alternative differs from it
whenever they do not (identity 3 tells the two apart).

### The identities the building batch pins

With 1 EUR = 1.25 USD on every date and the rate stored as EUR per USD:

1. **A closed trade, broker rate equal to the hub's.** Buy 10 at 100 USD,
   settled 800.00 EUR, fees 5.00 and taxes 1.00 EUR (cash 806.00). Sell 10
   at 120 USD, settled 960.00 EUR, fees 3.00 EUR (cash 957.00). Basis
   **1,007.50 USD**, proceeds **1,196.25 USD**, realized **188.75 USD =
   151.00 EUR = 957.00 − 806.00**. Today: 1,006, 1,197 and 191 USD, 152.80
   EUR.
2. **The Costs report.** Buy 10 at 100 USD settled 790.00 EUR, fees 5.00 and
   taxes 1.00 EUR: the month reads fees **5.00**, taxes **1.00**, total
   **6.00 EUR** (today 4.00, 0.80 and 4.80). The total equals the walk's
   trade costs for that day and the cash minus the settlement (796.00 −
   790.00).
3. **Broker rate unequal to the hub's.** Buy 10 at 100 USD settled 750.00
   EUR, fees 6.00 and taxes 1.50 EUR; sell as in identity 1 with fees 4.00
   EUR. Basis **1,010.00 USD**, realized **185.00 USD**, 148.00 EUR at the
   sale date's hub rate. The hub-rate alternative gives 148.50; today gives
   150.80. Mutation check: converting the fees at the hub rate turns this
   identity red.
4. **A same-currency trade** reads byte-identical figures before and after.

### Consequences of the amendment

- **Risk-tier attention:** one commit group per reader (the matcher, the
  Costs report, the income report), each starting from its red test; the
  verification pass takes identities 1 and 3 first.
- **ADR-0033 is unchanged.** Its fold already reads the rate as transaction
  data; this amendment only says which currency the fees enter that fold in.
- Nothing here creates, stores or transmits an order, and nothing calls out.

## Amendment (2026-10-09): a closed trade is in one currency, whatever booked its lots

**Status:** adopted by the merge of the Sprint 21 planning PR; risk-tier
(money: closed-trade figures, and settlement legs written to stored
bookings), so it is signed before the batch that builds it.

### Why

The amendment of 2026-10-07 put a trade's fees and taxes in the currency of
its price. The price itself is in the currency the trade is booked in, and
this record and ADR-0033 let a cross-currency trade be booked in either of
two:

- the booking form books it in the security's currency, its cash leg beside
  it (this record's Decision);
- a Portfolio Performance import books it in its cash account's currency,
  the security-currency leg derived beside it from the hub rate stored for
  its date (ADR-0033; `Imports.Applier.derived_settlement_legs/4`);
- the API takes either form.

`TradeMatcher` keeps one FIFO queue per security across every depot and
portfolio (`Ledger.list_transactions_for_security/1`), adds each lot's
quantity × price as booked, and gives a closed trade its sell's
`currency_code`; `RealizedGains` converts the result from that currency at
the hub rate of the close date. Where a sell closes a lot booked in another
currency, the basis adds two currencies under one code (#1198). One such
lot is enough: an imported purchase sold through the booking form, the
reverse pair, or two imports of one security into depots whose cash
accounts are in different currencies. ADR-0033's requirement 5 says that no
mixed-currency cost figure can exist; the holdings fold meets it, the
matcher's closed trades do not. The wrong figure reaches the security's
Trades tab, Income's realized list, the Overview's closed-trades card, the
trades and realized-gains reads and their tools, `TradeReturn`, the
realized total, the hit rate and the annual matrix.
`Ledger.trade_fees_basis/0` names the case as an open decision.

Two neighbours decide what a fix can rest on:

- **A third currency (#1199).**
  `Ledger.Transaction.validate_cash_account_currency/2` compares a
  booking's currency with its cash account's only, so a buy or sell priced
  in neither its security's currency nor its account's is accepted once it
  carries a rate. No reader handles one, and no stored leg converts it: the
  2026-10-07 amendment leaves its fees as recorded rather than convert them
  wrongly. The importer's copy of the check takes the same row: for an
  entry priced in a third currency into an existing account, the import
  stores legs from that currency to the security's where the hub rate is
  stored, and the account check then finds a rate.
- **A first import's legs (#1196).** The import derives a trade's legs
  from the hub rate stored when it applies. On a fresh instance there is
  none yet: the history backfill (`Fx.RateSync.backfill_when_needed/1`, the
  Sprint 20 plan's D-5) runs after the import commits, and the legs wait
  for `mix portfolixir.backfill_settlement_legs`. A lot without its legs
  cannot be converted, so without #1196 the fallback below (point 3) would
  be what a first import's closed trades read.

### What changes

1. **A new buy or sell is priced in its security's currency or its cash
   account's (#1199).** One whose `currency_code` is neither is refused
   with an error on `currency_code` that names both (for a USD security
   through a EUR account: USD or EUR), on every write path, the API and
   MCP included; the importer's copy of the check refuses the row the same
   way and names it. The check runs where `Ledger.SettlementGuard` runs its
   own (the Sprint 15 plan's D-5): on insert, and on an update that changes
   a field it reads, the currency, the security, the cash account or the
   type. A stored row is never revalidated behind the operator's back: a
   notes-only edit of a stored row priced in a third currency passes, and
   the row keeps its figures. Its closed trades read as point 3 says.
2. **A closed trade is in its sell's currency, whatever booked its lots
   (#1198).** It keeps its sell's `currency_code`, as now, and every lot it
   closes enters in that currency through the lot's own stored legs, never
   through a rate looked up:
   - a lot booked in the sell's currency enters as booked, its fees and
     taxes as the amendment of 2026-10-07 has them;
   - a lot booked in its cash account's currency, closed by a sell in the
     security's currency, enters at its native leg, `security_amount` ÷
     quantity a share (the `buy_price_native` its open lot is valued at),
     and its fees and taxes ÷ its own `settlement_fx_rate`;
   - a lot booked in the security's currency, closed by a sell in the
     currency of the lot's cash account, enters at its settlement leg,
     `settlement_amount` ÷ quantity a share (the leg an open lot's
     `base_cost` reads), and its fees and taxes as recorded, which are in
     that currency already.

   Every figure the trade derives from its lots follows: `avg_buy_price`,
   `buy_fees`, `buy_taxes`, `basis`, each consumed lot's `cost`,
   `realized_pnl_abs` and `realized_pnl_pct`, `annualized_return`, and,
   through the close date's hub rate, `realized_base` and every total over
   it. The legs reach the matcher as transaction data from
   `Ledger.transaction_for_matcher/2`, as the rate did in 2026-10-07, so the
   matcher stays pure (ADR-0033's fold rule). Full precision, nothing
   rounded (ADR-0016).
3. **A lot without the leg it needs makes its closed trade unavailable**,
   the fallback. A lot lacks it when its sell is in the security's currency
   and the lot was imported before a rate was stored (no native leg), when
   its sell is in its account's currency and the lot was booked in the
   security's without a `settlement_amount`, or when no leg of it reaches
   the sell's currency at all: a lot or a sell priced in a third currency,
   or a lot booked in the currency of another account than the sell's.
   Such a trade is never summed. The trades read keeps it with its sell's
   own figures (quantity, dates, `avg_sell_price`, the sell's fees and
   taxes, `proceeds`), null for every figure point 2 lists, and its reason
   (`missing_settlement_leg`) with the open date and booking currency of
   each lot that lacks its leg. The realized-gains report, the Overview
   card and Income name it in `excluded`, told apart from a sale excluded
   for a missing close-date rate because its remedy differs, and leave it
   out of `trades`, the matrix and the three figures. The Trades tab names
   it unavailable with its remedy: the lot's legs (point 6), or a rate for
   the lot's date.
4. **A closed trade whose sell and every lot it closes are booked in one
   currency reads byte-identical figures**, the import form's included: the
   conversion runs only where a sell closes a lot booked in another
   currency.
5. **The basis says so.** `Ledger.trade_fees_basis/0`, which the trades and
   realized-gains payloads carry as `computation_basis.fees_and_taxes`,
   drops its "#1198, an open decision" clause and states points 2 to 4, and
   that an imported lot's legs come from the hub rate stored for its
   booking date (ADR-0033), not from a broker's: where the broker settled
   at another rate that day, the lot enters at the hub's conversion of the
   cash it moved. `Ledger.realized_pnl_pct_basis/0`'s "in the trade's
   currency_code" becomes true of every trade. The tools' descriptions say
   so.
6. **A history backfill that stores rates derives the settlement legs they
   make derivable (#1196).** `Fx.RateSync.backfill/1` and
   `backfill_when_needed/1`, once their upsert has stored rates, run
   `Ledger.SettlementBackfill.run/1` before they release the `:fx_backfill`
   single-flight key, under `Actor.system_job("settlement_backfill")`, the
   actor the mix task journals under. Each derived row is a
   `Ledger.update_transaction/3`, journaled with its pre-image and bumping
   the data version like any edit. Its values are the ones the import would
   have stored had the rate been there when it applied: the settlement
   amount read off the cash (`SettlementGuard.trade_amount/4`, else
   quantity × price), that amount through `Fx.convert/4` at the booking
   date, and their ratio at six places, the arithmetic of
   `Imports.Applier.derived_settlement_legs/4`.

   Nothing else is rewritten. The candidates are the buys and sells booked
   in their cash account's currency, not their security's, with none of
   this record's three fields stored. `SettlementBackfill`'s query reads
   `security_amount` and the security's currency only, so today it would
   also rewrite a stored third-currency row's rate; the narrower set binds
   the mix task too. A row whose date still has no rate keeps no legs and
   is counted, as by the task. The manual backfill's answer
   (`POST /api/v1/exchange_rates/sync` with `scope=history`,
   `portfolixir.exchange_rates.sync`) carries both counts. A row the ledger
   refuses stops the derivation as it stops the task: the rates stay
   stored, and the failure is logged and, on a manual run, answered. Import
   idempotency is untouched: neither the content hash
   (`Imports.ImportHash`) nor the economic key (`Imports.DedupKey`) reads a
   leg.

   *Limit:* an import whose apply overlaps the run's upsert reads no rate
   when it applies and commits after the run read its candidates. Its rows
   keep no legs until the next manual backfill or the task, and their
   closed trades read unavailable (point 3) meanwhile, never wrong.

**Why the sell's currency, through each lot's own legs.** The closed trade
already takes its sell's currency, and `RealizedGains` converts its result
from it at the close date (D-1 of #724): the sale is the event the result
is realized at. Converting the lots, not the sell, leaves every trade whose
lots match its sell as it is (point 4). A lot's own legs are the cash it
moved and the one rate that converted it, the broker's for a trade booked
through the form and the hub's of its date for an import. A rate looked up
at the sale would convert that cash a second time, and would be the reducer
lookup ADR-0033's fold rule forbids. Where broker and hub agree, a closed
trade's realized result in the base currency is then the cash its bookings
moved, whichever way each was booked (identities 1 and 2b).

**Not taken.**

- **(a) Every import-form row into the security's currency.** It moves
  every import-only trade, those right today among them: identity 4's
  imported round trip would read 188.75 USD instead of 151.00 EUR, and
  wherever the hub rate moved between purchase and sale, its result in the
  base currency would stop being the cash the round trip moved.
- **(b) Every booking-form row into the account's currency.** It
  contradicts this record and the 2026-10-07 amendment's identity 1.
- **(c) alone.** It fails closed where the lot's legs make the conversion
  exact. It stays the fallback (point 3).
- **One FIFO queue per currency.** It breaks FIFO order and leaves orphan
  sells. FIFO closes the security's oldest shares across every depot (the
  trades read states `method: "fifo"`, FR-13); a queue per booking currency
  would close the oldest of the sell's currency instead. And a sale would
  find only the shares bought in its currency: in identity 2a's shape the
  sale of 20 in USD closes the 10 in the USD queue (realized 200 USD),
  leaves an orphan sell of 10, and keeps the 10 bought through the import
  open for ever in a position that is zero.

### The identities the building batch pins

With 1 EUR = 1.25 USD on every date and the rate stored as EUR per USD, as
in the amendment of 2026-10-07:

1. **Imported, then sold through the booking form.** A Portfolio
   Performance export books a buy of 10 at 80.00 EUR into a EUR account:
   cash 806.00 EUR, fees 5.00 and taxes 1.00 EUR. With the rate stored, the
   import stores its legs: 800.00 EUR, 1,000.00 USD, rate 0.800000. The
   booking form sells the 10 at 120 USD, settled 960.00 EUR, fees 3.00 EUR
   (cash 957.00). The lot enters at 100 USD a share, its fees and taxes at
   6.25 and 1.25 USD, the sale's fees at 3.75: basis **1,007.50 USD**,
   proceeds **1,196.25 USD**, realized **188.75 USD = 151.00 EUR = 957.00 −
   806.00**, the 2026-10-07 amendment's identity 1 whichever way the lot
   was booked. Today: basis 806.00, realized 390.25 under USD, read as
   312.20 EUR. Pinned in `Ledger.ClosedTradeCurrencyTest` on the trades
   read, the realized-gains report and the Overview card's newest trades,
   and end to end on a fresh instance (the file imported with no rate
   stored, the history backfill through the fake provider, then the sale),
   which passes only with point 6. Mutation check: entering the lot at its
   booked price with its fees converted (basis 807.50) turns it red.
2. **The shapes #1198 records.**
   - **a.** A booking-form buy of 10 at 100 USD settled 800.00 EUR, an
     imported buy of 10 at 80.00 EUR (legs 800.00 EUR, 1,000.00 USD,
     0.800000) and a booking-form sale of 20 at 120 USD settled 1,920.00
     EUR, no fees: basis **2,000 USD**, realized **400 USD = 320.00 EUR =
     1,920.00 − 800.00 − 800.00**, `realized_pnl_pct` **0.2**. Today 1,800
     and 600 under USD, read as 480.00 EUR, and 0.3333….
   - **b.** The reverse pair (#1198's comment): the 2026-10-07 amendment's
     booking-form buy (10 at 100 USD, settled 800.00 EUR, fees 5.00 and
     taxes 1.00 EUR, cash 806.00) and an imported sale of 10 at 96.00 EUR
     (cash 957.00 EUR, fees 3.00 EUR; legs 960.00 EUR, 1,200.00 USD,
     0.800000). The trade is in EUR; the lot enters at 80.00 EUR a share,
     its fees and taxes as recorded: basis **806.00 EUR**, proceeds
     **957.00 EUR**, realized **151.00 EUR = 957.00 − 806.00**. Today basis
     1,007.50 and realized **−50.50** under EUR: a gain reads as a loss.

   Pinned in `Ledger.ClosedTradeCurrencyTest` and over the API
   (`PortfolixirWeb.ApiV1CrossCurrencyTradesTest`). Mutation check:
   dividing the lot's fees by its rate when it enters its account's
   currency (basis 807.50 EUR) turns 2b red.
3. **A lot without its leg.** Identity 1's purchase, imported while no rate
   was stored and so without legs, and sold as there once the rates are
   stored without a history backfill; beside it a EUR security bought 10
   at 50.00 EUR, fees 1.00 (cash 501.00), and sold 10 at 60.00 EUR, fees
   1.00 (cash 599.00): realized 98.00 EUR. The USD trade is
   unavailable: the trades read shows its proceeds, 1,196.25 USD, null for
   its basis and result, and names the lot (its open date, EUR) and the
   missing native leg; the realized-gains report names it in `excluded`
   and reads `realized_total` **98.00 EUR** over `trade_count` **1**,
   `hit_rate` **1.0000**. Today: 410.20 EUR over two trades, 390.25 under
   USD read as 312.20 EUR. Once its legs are derived (identity 6), the
   trade reads identity 1 and `realized_total` 249.00 EUR. Pinned in
   `Ledger.ClosedTradeCurrencyTest` and `Portfolios.RealizedGainsTest`.
   Mutation checks: entering the lot as booked when its leg is missing
   turns it red, and so does leaving the trade out without naming it.
4. **One currency, byte-identical**, compared as the payload's digits
   before and after: the 2026-10-07 amendment's identity 1 (1,007.50,
   1,196.25 and 188.75 USD), identity 3's EUR trade (501.00, 599.00 and
   98.00 EUR), and an import-only round trip, identity 1's imported buy
   sold through an import as in 2b: **806.00, 957.00 and 151.00 EUR**.
   Option (a) would read the last as 1,007.50, 1,196.25 and 188.75 USD.
   Pinned by `Ledger.ClosedTradeCurrencyTest`'s existing same-currency and
   account-currency tests, kept unchanged, and the import-only round trip
   beside them. Mutation check: converting a lot already in its sell's
   currency through its legs, option (a), turns the account-currency test
   red.
5. **A third currency is refused.** Through a EUR account, a new buy of a
   USD security priced in CHF, with a settlement rate, answers 422 on
   `currency_code`, naming USD and EUR; nothing is stored or journaled
   (today: 201). A stored buy priced in CHF, written as it was before the
   check, takes a notes-only edit: 200, journaled, every figure unchanged.
   An import entry priced in CHF into the existing EUR account is refused
   and named by its row. Pinned in the ledger's, the API's and the
   importer's tests (`Ledger.CrossCurrencySettlementTest`,
   `PortfolixirWeb.ApiV1Test`, `Imports.ApplierSettlementTest`). Mutation
   checks: running the check on every update fails the notes-only edit;
   skipping it on insert stores the buy. `Ledger.ClosedTradeCurrencyTest`'s
   third-currency test books its row through `Ledger.create_transaction/3`,
   which now refuses it: it writes the row as stored before the check, and
   its expectation stands.
6. **The legs after a history backfill.** On a fresh instance, identity 1's
   file is imported with no rate stored, so the buy keeps no legs; a
   booking-form sale with its legs sits beside it. The history backfill
   stores 1 EUR = 1.25 USD and, in the same single-flight run, derives the
   buy's legs under the system actor: **800.00 EUR, 1,000.00 USD,
   0.800000**, field for field what the same file stores when the rate is
   there before the import. The file also carries a buy whose price
   Portfolio Performance rounded, 7 at 114.29 EUR with cash 806.00 EUR,
   fees 5.00 and taxes 1.00 EUR: both paths read its settlement off the
   cash, **800.00 EUR** (1,000.00 USD, 0.800000), where quantity × price
   would give 800.03. The booking-form sale, a row that got its legs when
   it was imported, and a stored third-currency row with a rate and no
   `security_amount` are not touched: no journal entry, no field changed.
   Pinned in `Fx.HistoryBackfillTest` (its round trip of a dollar share
   bought from a euro account gains the legs) and
   `Ledger.SettlementBackfillTest`. Mutation checks: dropping the
   legs-missing condition journals the sale; reading quantity × price
   parts the two paths on the rounded row.

### Consequences of the amendment

- **Risk-tier attention:** three commit groups, each starting from its red
  test, in this order: #1199 (the ledger's and the importer's check;
  identity 5), #1196 (the derivation in the backfill run; identity 6),
  #1198 (the matcher, the unavailable path, the basis and what the screens
  name; identities 1 to 4). #1199 comes first, so the matcher meets a third
  currency only in stored rows, which point 3 covers. #1196 comes before
  #1198 because identity 1 passes end to end on a fresh instance only with
  it: without it the lot keeps no legs and the trade reads as identity 3.
  The verification pass takes identities 1 and 2b first (the base-currency
  result is the cash the bookings moved), then 3 (named, excluded, the
  totals unchanged by it), then 4 as a diff of every closed-trade payload
  the suite's fixtures produce before and after, then 6.
- **No computation version moves.** No registered derived analytic reads a
  closed trade or a settlement leg (`Derived.Registry`: the two walks, the
  two contribution analyses, the benchmark comparison, the security and
  portfolio metrics, the policy findings). The trades and realized-gains
  reads, the Overview card and the Trades tab are computed on every read,
  so no stored value serves an old figure. The legs #1196 derives are
  data, which the data-version counter covers as it covers every ledger
  write.
- **The reads whose figures change:** the trades read
  (`portfolixir.trades.list`), the realized-gains read
  (`portfolixir.cashflow.realized_gains`: trades, summary, matrix,
  `excluded`), the Overview card, the Trades tab and Income's realized
  list, for a closed trade that closes a lot booked in another currency
  than its sell, and for nothing else. The transaction writes
  (`portfolixir.transactions.create`, `.update`) gain the refusal, and the
  history backfill's answer its counts. Open lots, holdings, the sale
  preview, the walk and the Costs and income reports keep their rules; the
  legs #1196 derives make an imported position's decomposition available
  where it read unavailable, as the mix task always has. The API
  contract's entry 18 records each change and says that no computation
  version moves.
- **ADR-0033 is unchanged.** Legs enter as transaction data, never as
  reducer lookups, and its requirement 5 now holds for closed trades too.
  Its "one-time auditable backfill" of imported rows also runs as the last
  step of every history backfill that stores rates; this record says so
  because the settlement fields are its.
- A merge preview opened before a derivation answers `plan_changed` with a
  fresh preview, as after any edit of a booking it covers
  (`Lifecycle.PlanDigest` reads the legs).
- Nothing here creates, stores or transmits an order. Nothing new calls
  out: the derivation reads the rates the backfill has just stored.
