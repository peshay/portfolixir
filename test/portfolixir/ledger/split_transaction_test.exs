defmodule Portfolixir.Ledger.SplitTransactionTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.WorldFixtures

  # User story (ADR-0028 §1/§3, issue #589 slice 1):
  # As a local portfolio maintainer whose security had a stock split,
  # I want to book the split as a first-class ledger event (ratio + effective
  # date, one row per holding portfolio),
  # so that holdings, cost basis, FIFO lots and the performance walk all
  # reflect the split from immutable, auditable inputs — without rewriting
  # any stored transaction or quote.
  #
  # Acceptance criteria:
  # - A split stores security, date and a positive integer ratio pair,
  #   normalized to lowest terms at write time (10:5 is stored as 2:1).
  # - A 1:1 ratio is rejected as meaningless; cash/price/quantity fields are
  #   forbidden on a split.
  # - A second same-day split for the same (portfolio, security) is rejected
  #   by a partial unique index (write idempotency for retried timeouts).
  # - Positions/holdings: quantity multiplies by the ratio, the total cost
  #   basis is unchanged, the per-share average cost divides — exact Decimal.
  # - FIFO open lots scale the same way: lot quantity multiplies, per-share
  #   buy_price divides, the lot's total cost is invariant.
  # - The scaled quantity quantizes once at volume scale 6, so a broker-stated
  #   sell of 3.333333 after 10 × 1:3 zeroes the position exactly (dust test).
  # - A split row in portfolio A scales only portfolio A's positions.
  # - The split applies first within its day, so a same-day buy books in
  #   post-split units and every quantity fold agrees.
  # - TTWROR shows no jump on the effective date (`external: false`).
  # - Split writes are journaled through the existing Ledger journal path.

  defp setup_world do
    world = base_world(name: "Split World", cash_name: "Split Cash", depot_name: "Split Depot")
    security = create_security!(name: "Split Co", ticker: "SPL", asset_class: "equity")
    Map.put(world, :security, security)
  end

  defp split_attrs(world, security, opts) do
    %{
      portfolio_id: world.portfolio.id,
      security_id: WorldFixtures.security_id_for(security),
      type: "split",
      date: Keyword.get(opts, :date, ~D[2026-03-01]),
      currency_code: "EUR",
      split_ratio_numerator: Keyword.get(opts, :numerator, 2),
      split_ratio_denominator: Keyword.get(opts, :denominator, 1)
    }
    |> Map.merge(Keyword.get(opts, :extra, %{}))
  end

  defp split!(world, security, opts) do
    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), split_attrs(world, security, opts))
    tx
  end

  defp buy!(world, opts) do
    WorldFixtures.buy!(world, world.security, opts)
  end

  defp position(world) do
    world.portfolio.id
    |> Ledger.positions_for_portfolio()
    |> Map.get({world.depot.id, world.security.id})
  end

  describe "changeset (§1: ratio pair, normalized, no cash leg)" do
    test "stores a split and normalizes the ratio to lowest terms (10:5 -> 2:1)" do
      world = setup_world()

      tx = split!(world, world.security, numerator: 10, denominator: 5)

      assert tx.type == "split"
      assert tx.split_ratio_numerator == 2
      assert tx.split_ratio_denominator == 1
      assert tx.quantity == nil
      assert tx.price == nil
      assert tx.gross_amount == nil
      assert tx.cash_account_id == nil
      assert tx.securities_account_id == nil
    end

    test "rejects a 1:1 ratio as meaningless, also in unreduced form (5:5)" do
      world = setup_world()

      for {p, q} <- [{1, 1}, {5, 5}] do
        assert {:error, changeset} =
                 Ledger.create_transaction(
                   Actor.owner_ui(),
                   split_attrs(world, world.security, numerator: p, denominator: q)
                 )

        assert %{split_ratio_numerator: [message]} = errors_on(changeset)
        assert message =~ "share count"
      end
    end

    test "requires security and positive integer ratio parts" do
      world = setup_world()

      assert {:error, changeset} =
               Ledger.create_transaction(
                 Actor.owner_ui(),
                 world |> split_attrs(world.security, []) |> Map.delete(:security_id)
               )

      assert %{security_id: _} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.create_transaction(
                 Actor.owner_ui(),
                 split_attrs(world, world.security, numerator: 0)
               )

      assert %{split_ratio_numerator: _} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.create_transaction(
                 Actor.owner_ui(),
                 split_attrs(world, world.security, denominator: -3)
               )

      assert %{split_ratio_denominator: _} = errors_on(changeset)
    end

    test "forbids cash, price and quantity fields on a split (no cash leg, no price)" do
      world = setup_world()

      forbidden = %{
        quantity: Decimal.new("10"),
        price: Decimal.new("100"),
        gross_amount: Decimal.new("1000"),
        cash_account_id: world.cash.id,
        securities_account_id: world.depot.id
      }

      for {field, value} <- forbidden do
        assert {:error, changeset} =
                 Ledger.create_transaction(
                   Actor.owner_ui(),
                   split_attrs(world, world.security, extra: %{field => value})
                 )

        assert %{^field => [message]} = errors_on(changeset)
        assert message =~ "blank"
      end
    end

    # Defense in depth (#589): the DB CHECK mirrors the changeset's
    # forbidden-field set exactly, so a split row written OUTSIDE the changeset
    # (raw SQL) still cannot carry a counter/settlement field that would let
    # Projection.account_portfolios mis-scope the multiplicative leg.
    test "the DB CHECK rejects a forbidden counter field on a split written outside the changeset" do
      world = setup_world()
      tx = split!(world, world.security, numerator: 2, denominator: 1)

      assert_raise Postgrex.Error, ~r/transactions_split_required_fields_check/, fn ->
        Repo.transaction(fn ->
          # Arm the transaction-local journal actor so the write clears the
          # journal-actor guard and reaches the field CHECK we are exercising.
          Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system', true)")

          Repo.query!(
            "UPDATE transactions SET counter_securities_account_id = $1 WHERE id = $2",
            [world.depot.id, tx.id]
          )
        end)
      end
    end

    test "rejects ratio fields on a non-split kind" do
      world = setup_world()

      assert {:error, changeset} =
               Ledger.create_transaction(Actor.owner_ui(), %{
                 portfolio_id: world.portfolio.id,
                 securities_account_id: world.depot.id,
                 cash_account_id: world.cash.id,
                 security_id: world.security.id,
                 type: "buy",
                 date: ~D[2026-03-01],
                 quantity: "10",
                 price: "100",
                 currency_code: "EUR",
                 split_ratio_numerator: 2,
                 split_ratio_denominator: 1
               })

      assert %{split_ratio_numerator: _} = errors_on(changeset)
    end
  end

  describe "write idempotency (§1: one split per portfolio, security and day)" do
    test "rejects a second same-day split for the same portfolio and security" do
      world = setup_world()
      split!(world, world.security, date: ~D[2026-03-01])

      assert {:error, changeset} =
               Ledger.create_transaction(
                 Actor.owner_ui(),
                 split_attrs(world, world.security, date: ~D[2026-03-01], numerator: 3)
               )

      assert %{date: [message]} = errors_on(changeset)
      assert message =~ "already"

      # A different day, or another portfolio on the same day, stays bookable.
      assert %Transaction{} = split!(world, world.security, date: ~D[2026-03-02])

      other = base_world(name: "Other World", cash_name: "OW Cash", depot_name: "OW Depot")

      assert %Transaction{} =
               split!(Map.put(other, :security, world.security), world.security,
                 date: ~D[2026-03-01]
               )
    end
  end

  describe "journaling (ADR-0017)" do
    test "split create and delete flow through the existing Ledger journal path" do
      # No split-specific journal code exists or is needed: create/delete_transaction
      # journal every kind via the same guard-armed Multi (verified here for `split`).
      world = setup_world()
      tx = split!(world, world.security, numerator: 10, denominator: 5)

      assert [entry] = Journal.list_entries(resource_type: "transaction", operation: :create)
      assert entry.resource_id == to_string(tx.id)
      assert entry.after["type"] == "split"
      assert entry.after["split_ratio_numerator"] == 2
      assert entry.after["split_ratio_denominator"] == 1

      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), tx)

      assert [delete_entry] =
               Journal.list_entries(resource_type: "transaction", operation: :delete)

      assert delete_entry.before["type"] == "split"
      assert delete_entry.before["split_ratio_numerator"] == 2
    end
  end

  describe "quantity, cost basis and FIFO lots (§3: quantity multiplies, cost invariant)" do
    test "a 10:1 split multiplies the quantity by 10, keeps the total cost basis and divides the per-share cost" do
      world = setup_world()
      buy!(world, quantity: "10", price: "100", date: ~D[2026-01-02])
      split!(world, world.security, numerator: 10, denominator: 1, date: ~D[2026-02-02])

      assert Decimal.equal?(position(world), Decimal.new("100"))

      assert [holding] = Ledger.holdings_for_portfolio(world.portfolio.id)
      assert Decimal.equal?(holding.quantity, Decimal.new("100"))
      assert Decimal.equal?(holding.cost_basis, Decimal.new("1000"))
      assert Decimal.equal?(holding.avg_cost, Decimal.new("10"))

      trades = Ledger.list_trades_for_security(world.security.id)
      assert [lot] = trades.open_lots
      assert Decimal.equal?(lot.quantity, Decimal.new("100"))
      assert Decimal.equal?(lot.buy_price, Decimal.new("10"))
      # Lot cost invariant: quantity x per-share buy price is unchanged.
      assert Decimal.equal?(Decimal.mult(lot.quantity, lot.buy_price), Decimal.new("1000"))
    end

    test "a 1:3 reverse split quantizes the quantity at volume scale 6, so the broker-stated sell zeroes the position (dust test)" do
      world = setup_world()
      buy!(world, quantity: "10", price: "30", date: ~D[2026-01-02])
      split!(world, world.security, numerator: 1, denominator: 3, date: ~D[2026-02-02])

      assert Decimal.equal?(position(world), Decimal.new("3.333333"))

      WorldFixtures.sell!(world, world.security,
        quantity: "3.333333",
        price: "90",
        date: ~D[2026-02-10]
      )

      assert Ledger.positions_for_portfolio(world.portfolio.id) == %{}
      assert Ledger.holdings_for_portfolio(world.portfolio.id) == []

      trades = Ledger.list_trades_for_security(world.security.id)
      assert trades.open_lots == []
      assert trades.orphan_sells == []
      assert [closed] = trades.closed_trades
      assert Decimal.equal?(closed.quantity, Decimal.new("3.333333"))
    end

    test "a split row in portfolio A does not scale portfolio B's position" do
      world_a = setup_world()
      world_b = base_world(name: "World B", cash_name: "B Cash", depot_name: "B Depot")
      world_b = Map.put(world_b, :security, world_a.security)

      buy!(world_a, quantity: "10", price: "100", date: ~D[2026-01-02])

      WorldFixtures.buy!(world_b, world_a.security,
        quantity: "10",
        price: "100",
        date: ~D[2026-01-02]
      )

      split!(world_a, world_a.security, numerator: 2, denominator: 1, date: ~D[2026-02-02])

      assert Decimal.equal?(position(world_a), Decimal.new("20"))
      assert Decimal.equal?(position(world_b), Decimal.new("10"))

      # The cross-portfolio holdings view scopes the scale the same way.
      rows = Ledger.holdings_for_security(world_a.security.id)
      by_portfolio = Map.new(rows, &{&1.portfolio.id, &1})

      scaled = Map.fetch!(by_portfolio, world_a.portfolio.id)
      untouched = Map.fetch!(by_portfolio, world_b.portfolio.id)

      assert Decimal.equal?(scaled.quantity, Decimal.new("20"))
      assert Decimal.equal?(scaled.cost_basis, Decimal.new("1000"))
      assert Decimal.equal?(scaled.avg_cost, Decimal.new("50"))
      assert Decimal.equal?(untouched.quantity, Decimal.new("10"))
      assert Decimal.equal?(untouched.avg_cost, Decimal.new("100"))

      # FIFO lots scale per portfolio too.
      trades = Ledger.list_trades_for_security(world_a.security.id)
      quantities = trades.open_lots |> Enum.map(& &1.quantity) |> Enum.sort(Decimal)
      assert [ten, twenty] = quantities
      assert Decimal.equal?(ten, Decimal.new("10"))
      assert Decimal.equal?(twenty, Decimal.new("20"))
    end
  end

  describe "intra-day ordering (§3: split first, all folds agree)" do
    test "a same-day buy books in post-split units across positions, holdings, FIFO and the performance walk" do
      world = setup_world()
      deposit!(world, "1250", ~D[2026-01-02])
      buy!(world, quantity: "10", price: "100", date: ~D[2026-01-02])
      put_quote!(world.security, ~D[2026-01-02], "100")

      # The buy is booked BEFORE the split (lower id), on the split's day —
      # the split still applies first (start-of-day), so the buy is post-split.
      buy!(world, quantity: "5", price: "50", date: ~D[2026-01-05])
      split!(world, world.security, numerator: 2, denominator: 1, date: ~D[2026-01-05])
      put_quote!(world.security, ~D[2026-01-05], "50")

      # positions: 10 x 2 + 5 = 25
      assert Decimal.equal?(position(world), Decimal.new("25"))

      # holdings: cost 1000 (invariant) + 250 = 1250, avg 50
      assert [holding] = Ledger.holdings_for_portfolio(world.portfolio.id)
      assert Decimal.equal?(holding.quantity, Decimal.new("25"))
      assert Decimal.equal?(holding.cost_basis, Decimal.new("1250"))
      assert Decimal.equal?(holding.avg_cost, Decimal.new("50"))

      # FIFO: the pre-split lot scaled to 20 @ 50, the same-day buy stays 5 @ 50
      trades = Ledger.list_trades_for_security(world.security.id)
      assert [first, second] = trades.open_lots
      assert Decimal.equal?(first.quantity, Decimal.new("20"))
      assert Decimal.equal?(first.buy_price, Decimal.new("50"))
      assert Decimal.equal?(second.quantity, Decimal.new("5"))
      assert Decimal.equal?(second.buy_price, Decimal.new("50"))

      # performance walk: 25 shares x 50 = 1250, cash 0 — and no jump anywhere
      {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])
      assert Decimal.equal?(result.end_value, Decimal.new("1250"))
      assert Decimal.equal?(result.ttwror, Decimal.new("0"))

      for point <- result.series do
        assert Decimal.equal?(point.value, Decimal.new("1250"))
      end
    end
  end

  describe "TTWROR continuity (§5: no jump on the effective date)" do
    test "replays a synthetic 10:1 split without a jump in the daily series" do
      world = setup_world()
      deposit!(world, "1000", ~D[2026-01-05])
      buy!(world, quantity: "10", price: "100", date: ~D[2026-01-05])
      put_quote!(world.security, ~D[2026-01-05], "100")
      put_quote!(world.security, ~D[2026-01-06], "100")

      split!(world, world.security, numerator: 10, denominator: 1, date: ~D[2026-01-07])
      # A quote dated ON the effective date is post-split basis (ADR-0028 §2).
      put_quote!(world.security, ~D[2026-01-07], "10")
      put_quote!(world.security, ~D[2026-01-08], "10.5")

      {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-08])

      values = Enum.map(result.series, & &1.value)
      expected = ~w(1000 1000 1000 1050)

      for {value, expected_value} <- Enum.zip(values, expected) do
        assert Decimal.equal?(value, Decimal.new(expected_value))
      end

      # No jump on the effective date: its cumulative return equals the day
      # before's, and the whole-period TTWROR is exactly the price move.
      [_d5, d6, d7, _d8] = result.series
      assert Decimal.equal?(d6.cumulative_ttwror, d7.cumulative_ttwror)
      assert Decimal.equal?(result.ttwror, Decimal.new("0.05"))
      assert Decimal.equal?(result.net_external_flows, Decimal.new("1000"))
    end
  end
end
