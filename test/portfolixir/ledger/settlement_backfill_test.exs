defmodule Portfolixir.Ledger.SettlementBackfillTest do
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1]

  alias Mix.Tasks.Portfolixir.BackfillSettlementLegs
  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Interleave
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementBackfill
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # Synthetic ADR-0033 fixture figures only. The booking and rate day,
  # 2026-01-16, is this module's own: rates are unique per (base, quote,
  # date), and another async module storing the same day would wait on
  # this test's uncommitted row (#1018).

  defp world do
    world = base_world(name: "Backfill World", cash_name: "BF Cash", depot_name: "BF Depot")
    security = create_security!(name: "Backfill US Equity", ticker: "BUS", currency: "USD")
    Map.put(world, :security, security)
  end

  # An imported cross-currency row before ADR-0033: EUR-booked buy of the USD
  # security, no settlement fields.
  defp legacy_import_buy!(w, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: Keyword.get(opts, :type, "buy"),
        date: Keyword.get(opts, :date, ~D[2026-01-16]),
        quantity: Keyword.get(opts, :quantity, "10"),
        price: Keyword.get(opts, :price, "80.00"),
        currency_code: "EUR"
      })

    tx
  end

  defp seed_rate!(date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: rate, source: "manual"}
      ])
  end

  # User story (ADR-0033 / issue #569, one-time auditable backfill):
  # As a maintainer with existing imported cross-currency rows,
  # I want a one-time backfill that derives the ADR-0015 settlement fields
  # from the stored hub rate at each row's booking date, journaled per row,
  # so that historic imports gain an honest cost pair without any silent
  # data mutation.
  #
  # Acceptance criteria:
  # - A EUR-booked buy of a USD security at rate 1 EUR = 1.25 USD gains
  #   settlement_amount 800.00 EUR, security_amount 1000.00 USD and
  #   settlement_fx_rate 0.80.
  # - The update is journaled (auditable, ADR-0017).
  # - A second run changes nothing (idempotent).
  test "backfills derivable rows, journaled and idempotent" do
    w = world()
    tx = legacy_import_buy!(w)
    seed_rate!(~D[2026-01-16], "1.25")

    assert {:ok, summary} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert summary.updated == 1
    assert summary.skipped_no_rate == 0

    reloaded = Ledger.get_transaction(tx.id)
    assert Decimal.equal?(reloaded.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(reloaded.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(reloaded.settlement_fx_rate, Decimal.new("0.80"))

    # Journaled under the backfill actor (ADR-0017 — auditable).
    tx_id = to_string(tx.id)

    assert Repo.exists?(
             from(e in Journal.Entry,
               where:
                 e.resource_type == "transaction" and e.resource_id == ^tx_id and
                   e.operation == :update
             )
           )

    assert {:ok, second} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert second.updated == 0
    assert second.skipped_no_rate == 0
  end

  # Acceptance criteria (closing act, both hunters): a legacy row whose
  # cash amount is not exactly quantity × price (PP's rounded Kurs) is
  # backfilled on its cash amount net of fees, so the settlement guard the
  # update now meets holds — before, the backfill stopped on its first row.
  test "a legacy row is backfilled on its cash amount, and the guard holds" do
    w = world()

    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-16],
        quantity: "13",
        price: "61.54",
        fees: "4.95",
        gross_amount: "805.03",
        currency_code: "EUR"
      })

    seed_rate!(~D[2026-01-16], "1.25")

    assert {:ok, %{updated: 1}} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))

    reloaded = Ledger.get_transaction(tx.id)
    assert Decimal.equal?(reloaded.settlement_amount, Decimal.new("800.08"))
    assert Decimal.equal?(reloaded.security_amount, Decimal.new("1000.10"))
  end

  # User story (honesty over availability):
  # As a maintainer whose row's booking date has no stored rate,
  # I want the row skipped and reported, never guessed,
  # so that the backfill cannot invent a native leg.
  test "a row with no stored rate at its booking date is skipped" do
    w = world()
    tx = legacy_import_buy!(w)

    assert {:ok, summary} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert summary.updated == 0
    assert summary.skipped_no_rate == 1

    reloaded = Ledger.get_transaction(tx.id)
    assert is_nil(reloaded.security_amount)
    assert is_nil(reloaded.settlement_amount)
    assert is_nil(reloaded.settlement_fx_rate)
  end

  # User story (#1311, Sprint 22 R5):
  # As a maintainer whose import carries a free allotment, a buy booked at a
  # price of 0,
  # I want the backfill to count it apart from the rows still waiting for a
  # rate, and to name it,
  # so that its answer never asks for a rate that is already stored and that
  # no re-run can make useful.
  #
  # Acceptance criteria:
  # - With EUR→USD stored for 2026-01-16, a EUR-booked buy of 5 of the USD
  #   security at 0.00 (no cash) beside an ordinary buy of 10 at 80.00: the
  #   run derives the ordinary row (800.00 EUR, 1,000.00 USD, 0.800000),
  #   counts skipped_no_rate 0 with no row named, and skipped_zero_amount 1,
  #   naming the free allotment by its id and date. Before: skipped_no_rate
  #   1, the allotment named as having no rate.
  # - A free allotment dated before any rate is a zero amount too, not a
  #   missing rate: no rate could give it a leg.
  # - The allotment keeps no leg and no journal entry; a re-run counts it the
  #   same way and writes nothing.
  # - The task prints "skipped (zero amount): 1" and names the row.
  test "a zero-amount row is counted apart from a missing rate (#1311)" do
    w = world()
    seed_rate!(~D[2026-01-16], "1.25")
    ordinary = legacy_import_buy!(w)
    allotment = legacy_import_buy!(w, quantity: "5", price: "0")
    early = legacy_import_buy!(w, quantity: "2", price: "0", date: ~D[2025-11-03])

    assert {:ok, summary} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert summary.updated == 1
    assert summary.skipped_no_rate == 0
    assert summary.skipped_no_rate_rows == []
    assert summary.skipped_changed == 0
    assert summary.skipped_zero_amount == 2

    assert summary.skipped_zero_amount_rows == [
             %{transaction_id: early.id, date: ~D[2025-11-03]},
             %{transaction_id: allotment.id, date: ~D[2026-01-16]}
           ]

    derived = Ledger.get_transaction(ordinary.id)
    assert Decimal.equal?(derived.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(derived.security_amount, Decimal.new("1000.00"))
    assert Decimal.to_string(derived.settlement_fx_rate) == "0.800000"

    for row <- [allotment, early] do
      assert legs(Ledger.get_transaction(row.id)) == {nil, nil, nil}
    end

    assert backfill_updates([allotment.id, early.id]) == []

    assert {:ok, rerun} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert rerun.updated == 0
    assert rerun.skipped_no_rate == 0
    assert rerun.skipped_zero_amount == 2
    assert backfill_updates([allotment.id, early.id]) == []

    output = ExUnit.CaptureIO.capture_io(fn -> BackfillSettlementLegs.run([]) end)
    assert output =~ "skipped (no rate):     0\n"
    assert output =~ "skipped (zero amount): 2\n"

    assert output =~
             "skipped transaction ##{allotment.id} (2026-01-16): a zero amount, " <>
               "which no rate converts into a leg"
  end

  # User story (counter-metric):
  # As a maintainer with ordinary same-currency rows and already-settled
  # ADR-0015 rows,
  # I want the backfill to leave them untouched,
  # so that only the broken import form is repaired.
  test "same-currency and already-settled rows are not touched" do
    world = base_world(name: "BF Same", cash_name: "BFS Cash", depot_name: "BFS Depot")
    eur = create_security!(name: "Backfill EU Equity", ticker: "BEU", currency: "EUR")

    {:ok, same_ccy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: eur.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        currency_code: "EUR"
      })

    usd = create_security!(name: "Backfill US Settled", ticker: "BSS", currency: "USD")

    {:ok, settled} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-01-16],
        quantity: "10",
        price: "100.00",
        currency_code: "USD",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80",
        # The cash the broker settled: without it the ledger would book
        # quantity × price in the security's units (E25 S6, F71).
        gross_amount: "800.00"
      })

    assert {:ok, summary} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert summary.updated == 0
    assert summary.skipped_no_rate == 0

    assert is_nil(Ledger.get_transaction(same_ccy.id).security_amount)

    reloaded = Ledger.get_transaction(settled.id)
    assert Decimal.equal?(reloaded.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(reloaded.settlement_fx_rate, Decimal.new("0.80"))
  end

  # A row written past the ledger, with the journal actor set so the
  # journal guard does not refuse it: how a row stood before a later check.
  defp stored_before_the_check!(%Transaction{} = row) do
    {:ok, stored} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'legacy_row', true)")
        Repo.insert!(row)
      end)

    stored
  end

  defp journal_entries(transaction_ids) do
    ids = Enum.map(transaction_ids, &to_string/1)

    Repo.all(
      from(e in Journal.Entry,
        where: e.resource_type == "transaction" and e.resource_id in ^ids,
        order_by: [asc: e.id]
      )
    )
  end

  # The journal entries the backfill wrote for these rows: none for a row it
  # passed over.
  defp backfill_updates(transaction_ids) do
    transaction_ids
    |> journal_entries()
    |> Enum.filter(&(&1.operation == :update))
  end

  defp legs(%Transaction{} = transaction) do
    {transaction.settlement_amount, transaction.security_amount, transaction.settlement_fx_rate}
  end

  # User story (#1196, Sprint 21 α2; ADR-0015's amendment of 2026-10-09,
  # point 6 and identity 6):
  # As the operator whose fresh import booked a dollar share from a euro
  # account before any rate was stored,
  # I want the backfill to derive only the legs such a row is missing, read
  # off the cash it moved,
  # so that its legs equal what the import stores when the rate is there,
  # and no row that already carries a leg, or is priced in a third currency,
  # is rewritten.
  #
  # Acceptance criteria:
  # - The candidates are the buys and sells booked in their cash account's
  #   currency, not their security's, with none of the three legs stored.
  # - A buy whose price Portfolio Performance rounded, 7 at 114.29 EUR with
  #   cash 806.00 EUR, fees 5.00 and taxes 1.00 EUR, gains 800.00 EUR,
  #   1,000.00 USD and 0.800000 at 1 EUR = 1.25 USD, read off the cash
  #   (quantity x price would give 800.03), journaled under the system actor.
  # - A stored third-currency row (priced in CHF through a EUR account,
  #   with a rate and no security_amount, written as stored before #1199's
  #   check) is not touched although a CHF rate is stored: no journal entry,
  #   no field changed; nor is the same row stored with no leg at all, nor
  #   a EUR-booked buy carrying settlement_fx_rate 0.790000 alone or
  #   settlement_amount 800.00 alone. The mix task narrows with the same
  #   set.
  # - A booking-form row with its legs gets no journal entry.
  test "only rows booked in their account's currency with no leg stored are derived (identity 6)" do
    w = world()

    {:ok, rounded} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-16],
        quantity: "7",
        price: "114.29",
        fees: "5.00",
        taxes: "1.00",
        gross_amount: "806.00",
        currency_code: "EUR"
      })

    {:ok, booked_with_legs} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "sell",
        date: ~D[2026-01-16],
        quantity: "5",
        price: "120.00",
        currency_code: "USD",
        security_amount: "600.00",
        settlement_amount: "480.00",
        settlement_fx_rate: "0.800000",
        gross_amount: "480.00"
      })

    # Written as it was stored before #1199's check refused a third
    # currency: CHF-priced, through the EUR account, its rate and no
    # security_amount.
    %Transaction{} =
      third_currency =
      stored_before_the_check!(%Transaction{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-16],
        quantity: Decimal.new("10"),
        price: Decimal.new("90.00"),
        fees: Decimal.new("0"),
        taxes: Decimal.new("0"),
        gross_amount: Decimal.new("850.00"),
        currency_code: "CHF",
        settlement_fx_rate: Decimal.new("0.944444")
      })

    # EUR-booked buys of the USD security that carry one leg but no
    # security_amount, as the ledger accepts them: the legs-missing
    # condition keeps them out, each of its three parts (review round S2).
    one_leg = fn leg ->
      {:ok, row} =
        Ledger.create_transaction(
          Actor.owner_ui(),
          Map.merge(
            %{
              portfolio_id: w.portfolio.id,
              securities_account_id: w.depot.id,
              cash_account_id: w.cash.id,
              security_id: w.security.id,
              type: "buy",
              date: ~D[2026-01-16],
              quantity: "10",
              price: "80.00",
              fees: "5.00",
              taxes: "1.00",
              gross_amount: "806.00",
              currency_code: "EUR"
            },
            leg
          )
        )

      row
    end

    rate_only = one_leg.(%{settlement_fx_rate: "0.790000"})
    amount_only = one_leg.(%{settlement_amount: "800.00"})

    # The same, written with no leg at all: the account-currency condition,
    # not the legs-missing one, keeps it out.
    third_currency_bare =
      stored_before_the_check!(%Transaction{third_currency | id: nil, settlement_fx_rate: nil})

    seed_rate!(~D[2026-01-16], "1.25")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "CHF",
          date: ~D[2026-01-16],
          rate: "0.90",
          source: "manual"
        }
      ])

    untouched = [booked_with_legs, third_currency, third_currency_bare, rate_only, amount_only]
    before = Enum.map(untouched, &legs(Ledger.get_transaction(&1.id)))
    journaled_before = journal_entries(Enum.map(untouched, & &1.id))

    # None of the untouched rows is a candidate at all: the lock-time
    # re-check (skipped_changed) is not what keeps them out.
    assert {:ok, %{updated: 1, skipped_no_rate: 0, skipped_changed: 0}} =
             SettlementBackfill.run(Actor.system_job("settlement_backfill"))

    derived = Ledger.get_transaction(rounded.id)
    assert Decimal.equal?(derived.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(derived.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(derived.settlement_fx_rate, Decimal.new("0.800000"))

    assert [%{actor_type: :system_job, actor_label: "settlement_backfill", operation: :update}] =
             journal_entries([rounded.id]) |> Enum.filter(&(&1.operation == :update))

    assert Enum.map(untouched, &legs(Ledger.get_transaction(&1.id))) == before
    assert journal_entries(Enum.map(untouched, & &1.id)) == journaled_before

    # The mix task runs the same narrowed set: the third-currency row stays.
    assert ExUnit.CaptureIO.capture_io(fn -> BackfillSettlementLegs.run([]) end) =~
             "rows updated:          0"

    assert Enum.map(untouched, &legs(Ledger.get_transaction(&1.id))) == before
    assert journal_entries(Enum.map(untouched, & &1.id)) == journaled_before
  end

  # The backfill's candidate read: the one query on transactions that joins
  # the cash accounts and takes no lock.
  defp candidate_read?(%{source: "transactions", query: query}),
    do: query =~ "cash_accounts" and not (query =~ "FOR")

  defp candidate_read?(_metadata), do: false

  # User story (#1196, Sprint 21 α2; ADR-0015's amendment of 2026-10-09,
  # point 6, review round B1):
  # As the operator who enters the broker's legs on an imported booking
  # while a history backfill runs,
  # I want the backfill to leave a booking alone once it carries a leg,
  # even when it read the booking as legless a moment earlier,
  # so that the broker's rate I typed is never replaced by the hub's.
  #
  # Acceptance criteria:
  # - An owner edit storing 800.00 EUR, 1,012.66 USD and 0.790000 on the
  #   legless buy, committed right after the backfill read its candidates,
  #   keeps all three; the backfill derives nothing, counts the row in
  #   skipped_changed, and journals nothing under settlement_backfill.
  test "a leg stored after the candidate read is never overwritten" do
    w = world()

    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-16],
        quantity: "10",
        price: "80.00",
        fees: "5.00",
        taxes: "1.00",
        gross_amount: "806.00",
        currency_code: "EUR"
      })

    seed_rate!(~D[2026-01-16], "1.25")

    broker_legs = fn ->
      Ledger.update_transaction(Actor.owner_ui(), Ledger.get_transaction(tx.id), %{
        settlement_amount: "800.00",
        security_amount: "1012.66",
        settlement_fx_rate: "0.790000"
      })
    end

    {result, {:ok, _edited}} =
      Interleave.run(&candidate_read?/1, broker_legs, fn ->
        SettlementBackfill.run(Actor.system_job("settlement_backfill"))
      end)

    assert {:ok, %{updated: 0, skipped_no_rate: 0, skipped_changed: 1}} = result

    stored = Ledger.get_transaction(tx.id)
    assert Decimal.to_string(stored.settlement_amount) == "800.000000"
    assert Decimal.to_string(stored.security_amount) == "1012.660000"
    assert Decimal.to_string(stored.settlement_fx_rate) == "0.790000"

    assert [%{actor_label: nil}] =
             journal_entries([tx.id]) |> Enum.filter(&(&1.operation == :update))
  end

  # The cross-currency buy the cash-edit races start from: 806.00 EUR cash,
  # 5.00 fees and 1.00 taxes, so its settlement reads 800.00 EUR, no leg
  # stored, the hub rate 1.25 at its date.
  defp cash_buy!(w) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-16],
        quantity: "10",
        price: "80.00",
        fees: "5.00",
        taxes: "1.00",
        gross_amount: "806.00",
        currency_code: "EUR"
      })

    seed_rate!(~D[2026-01-16], "1.25")
    tx
  end

  # The backfill run with an owner edit of the buy's cash committed right
  # after its candidate read; `figures` are the edit's other fields (a cash
  # stated alone must agree with the stored figures, ADR-0053's amendment of
  # 2026-11-02).
  defp backfill_across_cash_edit(tx, gross_amount, figures \\ %{}) do
    cash_edit = fn ->
      Ledger.update_transaction(
        Actor.owner_ui(),
        Ledger.get_transaction(tx.id),
        Map.put(figures, :gross_amount, gross_amount)
      )
    end

    {result, {:ok, _edited}} =
      Interleave.run(&candidate_read?/1, cash_edit, fn ->
        SettlementBackfill.run(Actor.system_job("settlement_backfill"))
      end)

    result
  end

  defp stored_legs(%Transaction{} = transaction) do
    transaction |> legs() |> Tuple.to_list() |> Enum.map(&(&1 && Decimal.to_string(&1)))
  end

  defp backfill_journal(id) do
    [id] |> journal_entries() |> Enum.filter(&(&1.actor_label == "settlement_backfill"))
  end

  # User story (#1196, Sprint 21 α2; ADR-0015's amendment of 2026-10-09,
  # point 6; the lock table's row 17):
  # As the operator who corrects an imported booking's cash while a history
  # backfill runs,
  # I want the backfill to derive no leg from the cash it read before my
  # edit,
  # so that a correct edit never stops the run as a ledger refusal, and no
  # leg is stored off a cash the booking no longer carries.
  #
  # Acceptance criteria:
  # - The buy's cash set from 806.00 to 816.00 (its price corrected to 81.00
  #   with it) right after the backfill read its candidates: the run
  #   completes, derives nothing and counts the row in skipped_changed; the
  #   buy keeps 816.00 and no leg, and nothing is journaled under
  #   settlement_backfill.
  test "a cash edited after the candidate read derives no leg, and the run goes on" do
    w = world()
    tx = cash_buy!(w)

    assert {:ok, %{updated: 0, skipped_no_rate: 0, skipped_changed: 1}} =
             backfill_across_cash_edit(tx, "816.00", %{price: "81.00"})

    stored = Ledger.get_transaction(tx.id)
    assert Decimal.to_string(stored.gross_amount) == "816.000000"
    assert stored_legs(stored) == [nil, nil, nil]
    assert backfill_journal(tx.id) == []
  end

  # User story (#1196, Sprint 21 α2; ADR-0015's amendment of 2026-10-09,
  # point 6; the lock table's row 17):
  # As the operator who corrects an imported booking's cash by a cent while
  # a history backfill runs,
  # I want the backfill to leave that booking for a re-run,
  # so that no leg is stored a cent off the cash the booking carries, inside
  # the guard's tolerance where nothing would refuse it.
  #
  # Acceptance criteria:
  # - The buy's cash set from 806.00 to 806.01 right after the candidate
  #   read: the run derives nothing and counts the row in skipped_changed,
  #   never settlement 800.00 beside a cash that implies 800.01.
  # - A re-run derives the legs off the stored cash: settlement 800.01 EUR,
  #   security 1,000.0125 USD, rate 0.800000.
  test "a cent-level cash edit after the candidate read stores no leg off the old cash" do
    w = world()
    tx = cash_buy!(w)

    assert {:ok, %{updated: 0, skipped_no_rate: 0, skipped_changed: 1}} =
             backfill_across_cash_edit(tx, "806.01")

    assert stored_legs(Ledger.get_transaction(tx.id)) == [nil, nil, nil]
    assert backfill_journal(tx.id) == []

    assert {:ok, %{updated: 1, skipped_changed: 0}} =
             SettlementBackfill.run(Actor.system_job("settlement_backfill"))

    assert stored_legs(Ledger.get_transaction(tx.id)) ==
             ["800.010000", "1000.012500", "0.800000"]
  end

  # User story (#1196, review round: the task's summary):
  # As the maintainer running `mix portfolixir.backfill_settlement_legs`,
  # I want its summary to count the rows it passed over because they gained
  # a leg or were deleted after it read them,
  # so that a row the summary does not name as updated or skipped for a
  # missing rate is still accounted for.
  #
  # Acceptance criteria:
  # - With an owner edit storing the broker's legs right after the task
  #   read its candidates, the summary prints "rows updated: 0", "skipped
  #   (no rate): 0" and "skipped (changed): 1".
  test "the task prints the rows it passed over because they changed" do
    w = world()
    tx = legacy_import_buy!(w)
    seed_rate!(~D[2026-01-16], "1.25")

    broker_legs = fn ->
      Ledger.update_transaction(Actor.owner_ui(), Ledger.get_transaction(tx.id), %{
        settlement_amount: "800.00",
        security_amount: "1012.66",
        settlement_fx_rate: "0.790000"
      })
    end

    {output, {:ok, _edited}} =
      Interleave.run(&candidate_read?/1, broker_legs, fn ->
        ExUnit.CaptureIO.capture_io(fn -> BackfillSettlementLegs.run([]) end)
      end)

    assert output =~ "rows updated:          0\n"
    assert output =~ "skipped (no rate):     0\n"
    assert output =~ "skipped (changed):     1\n"
  end
end
