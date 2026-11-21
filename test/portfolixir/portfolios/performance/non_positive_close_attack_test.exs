defmodule Portfolixir.Portfolios.Performance.NonPositiveCloseAttackTest do
  # The attack lens on Sprint 31's Lane Z (#1473, ADR-0051's amendment of
  # 2026-11-21), written by a session that did not build it. Each case pins a
  # corner the build's own tests leave open. Every expected figure was
  # recomputed in Python's `decimal` with `getcontext().prec = 34`, never
  # copied from a read:
  #
  #   1 * 11 - 1 * 10 = 1             (a 0 on the window's baseline day)
  #   11 - 0 = 11                     (a 0 as the only close before the window:
  #                                    the start value counts zero, marked
  #                                    no_price on the baseline day, §10)
  #   4 * 5.5 - 2 * 10 = 2.0          (a 0 on the baseline day of a split day,
  #                                    manual and provider-mirror closes alike;
  #                                    the mirror's 5 reads 5 * 2 = 10 raw)
  #   0 - 10 - (-0) = -10, -10 / 10 = -1   (a removal booked at 0)
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.Performance.Contribution

  @today ~D[2026-11-12]

  defp legacy_close!(security, date, close, source \\ "manual") do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, _rows} =
      Repo.insert_all(SecurityQuote, [
        %{
          security_id: security.id,
          date: date,
          close: Decimal.new(close),
          source: source,
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
    assert Decimal.equal?(row.contribution, Decimal.new(contribution)),
           "contribution #{inspect(row.contribution)}"

    assert Decimal.equal?(row.start_value, Decimal.new(start_value)),
           "start #{inspect(row.start_value)}"

    assert Decimal.equal?(row.end_value, Decimal.new(end_value)), "end #{inspect(row.end_value)}"
  end

  defp delivery!(world, security, type, quantity, date, price) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: type,
        date: date,
        quantity: quantity,
        price: price,
        currency_code: "EUR"
      })

    tx
  end

  @day {:range, ~D[2026-11-12], ~D[2026-11-12]}
  @two {:range, ~D[2026-11-11], ~D[2026-11-12]}

  test "a 0 on the window's baseline day: the close before it is the start value" do
    {world, fund} = held!("Baseline", "1")
    put_quotes!(fund, [{~D[2026-11-10], "10"}, {~D[2026-11-12], "11"}])

    assert_unmoved!(world.portfolio.id, [@day, @two, "max"], fn ->
      legacy_close!(fund, ~D[2026-11-11], "0")
    end)

    row = row!(world.portfolio.id, fund, @day)
    assert_row(row, "1", "10", "11")
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {0, nil, 1}
  end

  # The removed seed: before Lane Z the 0 seeded the price and the baseline
  # day read as valued at 0, so the row's contribution of 11 went unmarked.
  # Now nothing seeds it: the baseline day is unvalued with no_price
  # (ADR-0051 §10 as amended 2026-11-19), exactly as with no 0 stored.
  test "a 0 as the only close before the window: no seed, the baseline day is no_price" do
    {world, fund} = held!("Seedless", "1")
    put_quotes!(fund, [{~D[2026-11-11], "10"}, {~D[2026-11-12], "11"}])

    assert_unmoved!(world.portfolio.id, [@two, @day, "max"], fn ->
      legacy_close!(fund, ~D[2026-11-05], "0")
    end)

    row = row!(world.portfolio.id, fund, @two)
    assert_row(row, "11", "0", "11")
    # The baseline day (10 November) has no positive close: no_price there.
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {1, :no_price, 2}
  end

  for source <- ["manual", "auto"] do
    test "a 0 on the baseline day before a split (#{source} closes): the seed rebases" do
      source = unquote(source)
      {world, fund} = held!("Split #{source}", "2")

      # A provider mirror stores the display basis (5 for a raw 10 before a
      # 2:1); a manual close is as-traded.
      before_split = if source == "manual", do: "10", else: "5"
      legacy_close!(fund, ~D[2026-11-09], before_split, source)
      legacy_close!(fund, ~D[2026-11-12], "5.5", source)

      {:ok, _splits} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: fund.id,
          date: ~D[2026-11-12],
          ratio_numerator: 2,
          ratio_denominator: 1
        })

      assert_unmoved!(world.portfolio.id, [@day, @two, "max"], fn ->
        legacy_close!(fund, ~D[2026-11-11], "0", source)
      end)

      row = row!(world.portfolio.id, fund, @day)
      assert_row(row, "2", "20", "22")
      assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {0, nil, 1}
    end
  end

  # §10's order once the count follows the walk: a carried positive close
  # without a rate path is no_rate (before Lane Z the special case named it
  # no_price, because the 0 was the day's price); only a security with no
  # positive close at all is no_price. The view's contribution agrees.
  test "a 0 after a positive close in a currency without a rate reads no_rate, not no_price" do
    {world, fund} = held!("Rateless", "1", currency: "USD")
    put_quotes!(fund, [{~D[2026-11-09], "10"}])
    legacy_close!(fund, ~D[2026-11-11], "0")

    row = row!(world.portfolio.id, fund, @two)
    assert_row(row, "0", "0", "0")
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {3, :no_rate, 0}

    {:ok, view} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Rateless", include_all: true})

    {:ok, read} = Contribution.for_view(view.id, period: @two, today: @today)
    view_row = Enum.find(read.positions, &(&1.security_id == fund.id))
    assert {view_row.unvalued_days, view_row.unvalued_reason} == {3, :no_rate}
  end

  test "a rate arriving after a 0: the carried positive close is converted" do
    {world, fund} = held!("Late rate", "1", currency: "USD")
    put_quotes!(fund, [{~D[2026-11-09], "10"}])
    legacy_close!(fund, ~D[2026-11-11], "0")

    {:ok, 1} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-11-12],
          rate: "2",
          source: "manual"
        }
      ])

    # 10 USD / 2 = 5 EUR on the 12th; the 11th has no rate: no_rate, never
    # no_price, and never 0 USD converted.
    row = row!(world.portfolio.id, fund, @two)
    assert Decimal.equal?(row.end_value, Decimal.new(5))
    assert {row.unvalued_days, row.unvalued_reason, row.valued_days} == {2, :no_rate, 1}
  end

  # ADR-0010, "a delivery carrying a booked price is valued at that price",
  # and the amendment: the total loss is the booking that removes a holding
  # at 0, never a quote. A removal at 0 stays -100 %.
  test "a removal booked at 0 is a total loss of the day's value" do
    {world, fund} = held!("Removal", "1")
    put_quotes!(fund, [{~D[2026-11-10], "10"}, {~D[2026-11-11], "10"}])
    delivery!(world, fund, "outbound_delivery", "1", ~D[2026-11-12], "0")

    row = row!(world.portfolio.id, fund, @day)
    assert_row(row, "-10", "10", "0")

    {:ok, performance} =
      Performance.for_portfolio(world.portfolio.id, period: @day, today: @today)

    assert Decimal.equal?(performance.ttwror, Decimal.new(-1))
  end

  # The read option itself: a Decimal comparison in SQL, so the smallest
  # positive close at the column's scale is a price and the smallest negative
  # one is not; a limit keeps the newest positive rows, not the newest rows.
  test "Quotes' positive reads compare the stored Decimal and limit after the filter" do
    fund = create_security!(name: "Edge Fund", ticker: nil)
    legacy_close!(fund, ~D[2026-11-08], "0.000001")
    legacy_close!(fund, ~D[2026-11-09], "-0.000001")
    legacy_close!(fund, ~D[2026-11-10], "0.000000")
    legacy_close!(fund, ~D[2026-11-11], "0")

    assert %{date: ~D[2026-11-08]} =
             Quotes.at_or_before(fund.id, ~D[2026-11-12], positive: true)

    assert %{date: ~D[2026-11-11]} = Quotes.at_or_before(fund.id, ~D[2026-11-12])

    assert [%{date: ~D[2026-11-08]}] =
             Quotes.range(fund.id, ~D[2026-11-01], ~D[2026-11-12], limit: 1, positive: true)

    assert Enum.map(
             Quotes.range(fund.id, ~D[2026-11-01], ~D[2026-11-12], positive: true),
             & &1.date
           ) ==
             [~D[2026-11-08]]

    assert length(Quotes.range(fund.id, ~D[2026-11-01], ~D[2026-11-12])) == 4
  end
end
