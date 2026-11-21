defmodule Portfolixir.Portfolios.Performance.NonPositiveCloseTest do
  # #1473, ADR-0051's amendment of 2026-11-21 (Sprint 31 Z1): the walk reads
  # a stored close of 0 or below as no price, as it reads a day without a
  # close. Every expected figure below was recomputed in Python's `decimal`
  # with `getcontext().prec = 34`, never copied from a read:
  #
  #   1 * 12 - 1 * 10 = 2          (a 0 on the window's last day)
  #   1 * 11 - 1 * 10 = 1          (a negative close; a 0 on the seed day)
  #   4 * 5.5 - 2 * 10 = 2.0       (a 0 on the split day; 10 / 2 = 5 carries)
  #   0                            (a position whose only close is 0)
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.Performance.Contribution

  @today ~D[2026-11-12]

  # A close a release before the plausibility bounds could store, written
  # past the changeset as such a legacy row sits in the table.
  defp legacy_close!(security, date, close) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, _rows} =
      Repo.insert_all(SecurityQuote, [
        %{
          security_id: security.id,
          date: date,
          close: Decimal.new(close),
          source: "manual",
          inserted_at: now,
          updated_at: now
        }
      ])

    :ok
  end

  defp held!(name, quantity, opts \\ []) do
    world = base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")

    security =
      create_security!(
        name: "#{name} Fund",
        ticker: nil,
        currency: Keyword.get(opts, :currency, "EUR")
      )

    deliver_untraded!(world, security, quantity, date: ~D[2026-10-01])
    {world, security}
  end

  # Every read the walk feeds over the portfolio, for each period, without
  # the instant it was computed at.
  defp reads(portfolio_id, periods) do
    walk = Performance.analysis(portfolio_id, today: @today)

    per_period =
      for period <- periods do
        opts = [period: period, today: @today]

        {Performance.for_portfolio(portfolio_id, opts),
         Contribution.for_portfolio(portfolio_id, opts),
         Bands.for_portfolio(portfolio_id, [level: :security] ++ opts)}
      end

    {walk, per_period}
    |> canonical()
    |> inspect(limit: :infinity, printable_limit: :infinity, custom_options: [sort_maps: true])
  end

  defp canonical(%Decimal{} = decimal), do: decimal
  defp canonical(%Date{} = date), do: date
  defp canonical(%DateTime{}), do: :instant

  defp canonical(map) when is_map(map),
    do:
      map
      |> Map.drop([:as_of, :computed_at, :stale])
      |> Map.new(fn {k, v} -> {k, canonical(v)} end)

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)

  defp canonical(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> canonical() |> List.to_tuple()

  defp canonical(other), do: other

  # The same ledger read before and after the legacy rows land: every figure
  # of every read the walk feeds, to the last digit.
  defp assert_unmoved!(portfolio_id, periods, legacy) do
    before = reads(portfolio_id, periods)
    legacy.()
    assert reads(portfolio_id, periods) == before
  end

  defp row!(portfolio_id, security, period) do
    {:ok, read} = Contribution.for_portfolio(portfolio_id, period: period, today: @today)
    Enum.find(read.positions, &(&1.security_id == security.id))
  end

  defp assert_row(row, contribution, start_value, end_value) do
    assert Decimal.equal?(row.contribution, Decimal.new(contribution))
    assert Decimal.equal?(row.start_value, Decimal.new(start_value))
    assert Decimal.equal?(row.end_value, Decimal.new(end_value))
  end

  @range {:range, ~D[2026-11-11], ~D[2026-11-12]}
  @periods [@range, {:range, ~D[2026-11-12], ~D[2026-11-12]}, "max"]

  # User story (#1473, ADR-0051's amendment of 2026-11-21):
  # As the operator reading a contribution row,
  # I want a stored close of 0 on the window's last day read as no price,
  # so that a feed's placeholder never reads as a total loss.
  #
  # Acceptance criteria:
  # - The last positive close carries over the 0: the end value is 1 x 12,
  #   the contribution 2, no day unvalued, both window days valued.
  # - Every read the walk feeds is what it was before the row landed.
  test "a 0 on the window's last day: the last positive close carries" do
    {world, fund} = held!("Last", "1")
    put_quotes!(fund, [{~D[2026-11-10], "10"}, {~D[2026-11-11], "12"}])

    assert_unmoved!(world.portfolio.id, @periods, fn ->
      legacy_close!(fund, ~D[2026-11-12], "0")
    end)

    row = row!(world.portfolio.id, fund, @range)
    assert_row(row, "2", "10", "12")
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {0, nil, 2}
  end

  test "a negative close between two positive ones is no price" do
    {world, fund} = held!("Negative", "1")
    put_quotes!(fund, [{~D[2026-11-10], "10"}, {~D[2026-11-12], "11"}])

    assert_unmoved!(world.portfolio.id, @periods, fn ->
      legacy_close!(fund, ~D[2026-11-11], "-5")
    end)

    row = row!(world.portfolio.id, fund, @range)
    assert_row(row, "1", "10", "11")
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {0, nil, 2}
  end

  # The carried seed: a walk from the window's baseline day (11 November for
  # the 12th) starts from the last close before it, read on the 10th.
  test "a 0 on the carried seed's day: the close before it carries in" do
    {world, fund} = held!("Seed", "1")
    put_quotes!(fund, [{~D[2026-11-08], "10"}, {~D[2026-11-12], "11"}])
    day = {:range, ~D[2026-11-12], ~D[2026-11-12]}

    assert_unmoved!(world.portfolio.id, [day, "max"], fn ->
      legacy_close!(fund, ~D[2026-11-10], "0")
    end)

    row = row!(world.portfolio.id, fund, day)
    assert_row(row, "1", "10", "11")
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {0, nil, 1}
  end

  # 2:1 on 11 November, a 0 stored for that day: the 10th's 10 carries,
  # rebased to 5, so four units read 20 on the split day and 22 on the 12th.
  test "a 0 on a split day: the close before it carries, rebased" do
    {world, fund} = held!("Split", "2")
    put_quotes!(fund, [{~D[2026-11-10], "10"}, {~D[2026-11-12], "5.5"}])

    {:ok, _splits} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: fund.id,
        date: ~D[2026-11-11],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    assert_unmoved!(world.portfolio.id, @periods, fn ->
      legacy_close!(fund, ~D[2026-11-11], "0")
    end)

    row = row!(world.portfolio.id, fund, @range)
    assert_row(row, "2", "20", "22")
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {0, nil, 2}
  end

  # A retired security's carried close is no measurement while no newer
  # close is stored (#610); a legacy 0 after its sale is no newer close.
  test "a 0 after a retired security's sale is no close beyond it" do
    world = base_world(name: "Retired", cash_name: "Retired Cash", depot_name: "Retired Depot")
    fund = create_security!(name: "Retired Fund", ticker: nil)
    deposit!(world, "100", ~D[2026-10-01])
    buy!(world, fund, quantity: "2", price: "10", date: ~D[2026-10-02])
    put_quotes!(fund, [{~D[2026-10-05], "11"}])
    # A buy after the feed stopped: its price replaces the carried close,
    # which is no measurement for a retired security (#610).
    buy!(world, fund, quantity: "1", price: "15", date: ~D[2026-11-03])
    sell!(world, fund, quantity: "3", price: "14", date: ~D[2026-11-05])

    {:ok, _retired} =
      Portfolixir.Catalog.update_security(Actor.owner_ui(), fund, %{is_retired: true})

    assert_unmoved!(world.portfolio.id, ["max", {:range, ~D[2026-11-01], ~D[2026-11-12]}], fn ->
      legacy_close!(fund, ~D[2026-11-10], "0")
    end)
  end

  # User story (#1473, ADR-0051 §10):
  # As the operator reading a contribution row,
  # I want a position whose only stored close is 0 counted zero and named,
  # so that a position the walk cannot value is never read as valued.
  #
  # Acceptance criteria:
  # - It contributes 0, is unvalued on the baseline day and both window
  #   days with `no_price`, and valued on none.
  # - The same holds in a currency without a stored rate: no price comes
  #   before no rate (§10's order).
  test "a position whose only close is 0 counts zero with no_price" do
    for {name, currency} <- [{"Only", "EUR"}, {"Rateless", "USD"}] do
      {world, fund} = held!(name, "1", currency: currency)
      legacy_close!(fund, ~D[2026-11-11], "0")

      row = row!(world.portfolio.id, fund, @range)
      assert_row(row, "0", "0", "0")
      assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {3, :no_price, 0}

      walk = Performance.analysis(world.portfolio.id, today: @today)
      assert Enum.all?(walk.daily, &Decimal.equal?(&1.value, 0)), name
    end
  end
end
