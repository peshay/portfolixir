defmodule Portfolixir.Ledger.LedgerDataQualityReadsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # Risk-tier (ADR-0036): both reads look at ledger derivation. They are
  # reads only (Sprint 22 plan, R6): no stored row changes, no automatic
  # repair. Every fixture is an exact Decimal.

  defp split_row!(world, security, date, {p, q}) do
    {:ok, row} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          security_id: security.id,
          type: "split",
          date: date,
          currency_code: security.currency_code,
          split_ratio_numerator: p,
          split_ratio_denominator: q
        },
        split_flow: true
      )

    row
  end

  defp transaction_count, do: Repo.aggregate(Transaction, :count)

  # User story (#1292):
  # As the operator whose ledger may hold a split booked for one portfolio
  # only, before the split flow closed that path, or through an import,
  # I want a read-only check that lists every stored split event missing a
  # portfolio that held the security entering the effective date,
  # so that I see where a portfolio's FIFO lots are scaled while its holding
  # is not, and know to book the missing row through the split flow.
  #
  # Acceptance criteria:
  # - An event (security, date, normalized ratio) whose rows miss a portfolio
  #   positioned entering the date is listed with the security, the date,
  #   the ratio, the booked rows' portfolios and transaction ids, and each
  #   missing portfolio with its exact quantity entering the date.
  # - A complete event, and a portfolio positioned only after the date, are
  #   not listed.
  # - The report carries as_of, a note and a remedy sentence naming the
  #   split flow; reading it writes nothing.
  # - Re-booking the identical split through the split flow, the remedy,
  #   adds the missing row, and the event leaves the list.
  describe "split events missing a positioned portfolio (#1292)" do
    setup do
      security = create_security!(name: "Split Gap Co", ticker: "SGC", asset_class: "equity")
      complete = create_security!(name: "Split Whole Co", ticker: "SWC", asset_class: "equity")
      a = base_world(name: "Portfolio A", cash_name: "A Cash", depot_name: "A Depot")
      b = base_world(name: "Portfolio B", cash_name: "B Cash", depot_name: "B Depot")
      late = base_world(name: "Portfolio Late", cash_name: "L Cash", depot_name: "L Depot")

      buy!(a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
      buy!(b, security, quantity: "7.5", price: "100", date: ~D[2026-01-02])
      buy!(late, security, quantity: "3", price: "100", date: ~D[2026-03-01])
      split_a = split_row!(a, security, ~D[2026-02-02], {2, 1})

      buy!(a, complete, quantity: "4", price: "50", date: ~D[2026-01-02])
      split_row!(a, complete, ~D[2026-02-02], {3, 1})

      %{security: security, a: a, b: b, split_a: split_a}
    end

    test "lists the event with the missing portfolio and its quantity entering the date",
         %{security: security, a: a, b: b, split_a: split_a} do
      before = transaction_count()

      report = Splits.incomplete_events_report()

      assert report.as_of == Clock.today()
      assert report.note =~ "split"
      assert report.remedy =~ "split flow"

      assert [event] = report.rows
      assert event.security_id == security.id
      assert event.security_name == "Split Gap Co"
      assert event.date == ~D[2026-02-02]
      assert event.ratio_numerator == 2
      assert event.ratio_denominator == 1
      assert event.booked_portfolio_ids == [a.portfolio.id]
      assert event.transaction_ids == [split_a.id]

      assert [missing] = event.missing_portfolios
      assert missing.portfolio_id == b.portfolio.id
      assert missing.portfolio_name == "Portfolio B"
      assert Decimal.equal?(missing.quantity_before, Decimal.new("7.5"))

      assert transaction_count() == before
    end

    test "re-booking the identical split through the split flow clears the finding",
         %{security: security, b: b} do
      assert {:ok, [added]} =
               Splits.book_split(Actor.owner_ui(), %{
                 security_id: security.id,
                 date: ~D[2026-02-02],
                 ratio_numerator: 2,
                 ratio_denominator: 1
               })

      assert added.portfolio_id == b.portfolio.id
      assert Splits.incomplete_events_report().rows == []
    end
  end

  # User story (#1290):
  # As the operator whose ledger may hold cross-currency trades stored with a
  # settlement rate and neither a cash amount nor a settlement amount (T-19's
  # rows, stored before the guard refused them),
  # I want a read that lists every such trade, whatever the size of the gap,
  # so that I can see them without a console and record the cash the broker
  # settled.
  #
  # Acceptance criteria:
  # - A stored buy or sell booked in another currency than its cash account's,
  #   with a settlement_fx_rate and neither gross_amount nor
  #   settlement_amount, is listed with its figures, the cash booked
  #   (quantity × price with fees and taxes), the cash its own rate implies
  #   and the difference, all exact.
  # - A row whose difference is under a cent is listed too (violations/0
  #   leaves it out).
  # - A trade with its cash amount, and a same-currency trade with a rate,
  #   are not listed.
  # - The report carries as_of, a note and a remedy sentence naming the cash
  #   amount; reading it writes nothing.
  # - Recording gross_amount through the ledger's update, the remedy, takes
  #   the row off the list.
  describe "stored rate-only cross-currency trades (#1290)" do
    setup do
      world = base_world(name: "Rate World", cash_name: "EUR Cash", depot_name: "Rate Depot")
      usd = create_security!(name: "US Rate Co", ticker: "URC", currency: "USD")

      wide = insert_rate_only!(world, usd, ~D[2026-04-01], "0.90909")
      narrow = insert_rate_only!(world, usd, ~D[2026-04-02], "1.000004")

      {:ok, _with_cash} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: usd.id,
          type: "buy",
          date: ~D[2026-04-03],
          quantity: "10",
          price: "200.00",
          fees: "4.90",
          taxes: "0",
          currency_code: "USD",
          gross_amount: "1823.08",
          settlement_fx_rate: "0.90909"
        })

      eur = create_security!(name: "EUR Rate Co", ticker: "ERC", currency: "EUR")

      {:ok, _same_currency} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: eur.id,
          type: "buy",
          date: ~D[2026-04-03],
          quantity: "1",
          price: "10",
          currency_code: "EUR",
          settlement_fx_rate: "1.1"
        })

      %{world: world, usd: usd, wide: wide, narrow: narrow}
    end

    test "lists each such trade with the cash booked and the cash its rate implies",
         %{world: world, usd: usd, wide: wide, narrow: narrow} do
      before = transaction_count()

      report = SettlementGuard.rate_only_report()

      assert report.as_of == Clock.today()
      assert report.note =~ "rate"
      assert report.remedy =~ "gross_amount"

      assert [first, second] = report.rows
      assert first.id == wide.id
      assert first.portfolio_id == world.portfolio.id
      assert first.security_id == usd.id
      assert first.security_name == "US Rate Co"
      assert first.cash_account_id == world.cash.id
      assert first.cash_account_currency_code == "EUR"
      assert first.currency_code == "USD"
      assert first.type == "buy"
      assert first.date == ~D[2026-04-01]
      assert Decimal.equal?(first.settlement_fx_rate, Decimal.new("0.90909"))
      assert Decimal.equal?(first.booked_cash, Decimal.new("2004.90"))
      assert Decimal.equal?(first.expected_cash, Decimal.new("1823.0800"))
      assert Decimal.equal?(first.difference, Decimal.new("181.8200"))

      assert second.id == narrow.id
      assert Decimal.equal?(second.booked_cash, Decimal.new("2004.90"))
      assert Decimal.equal?(second.expected_cash, Decimal.new("2004.908"))
      assert Decimal.equal?(second.difference, Decimal.new("-0.008"))

      # The guard's own listing keeps its cent filter and leaves the narrow
      # row out; this read lists it.
      refute Enum.any?(SettlementGuard.violations(), &(&1.id == narrow.id))

      assert transaction_count() == before
    end

    test "recording the cash the broker settled takes the row off the list",
         %{wide: wide, narrow: narrow} do
      assert {:ok, _} =
               Ledger.update_transaction(Actor.owner_ui(), wide, %{gross_amount: "1823.08"})

      assert [%{id: id}] = SettlementGuard.rate_only_report().rows
      assert id == narrow.id
    end
  end

  # A row stored before the guard refused the shape (H35), inserted below
  # the ledger the way the guard's own test stores one.
  defp insert_rate_only!(world, security, date, rate) do
    {:ok, row} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Repo.insert!(%Transaction{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: security.id,
          type: "buy",
          date: date,
          quantity: Decimal.new("10"),
          price: Decimal.new("200.00"),
          fees: Decimal.new("4.90"),
          taxes: Decimal.new("0"),
          currency_code: "USD",
          settlement_fx_rate: Decimal.new(rate)
        })
      end)

    row
  end
end
