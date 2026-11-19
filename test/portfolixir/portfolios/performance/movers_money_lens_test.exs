defmodule Portfolixir.Portfolios.Performance.MoversMoneyLensTest do
  # Sprint 30 closing act, the money lens: every expected figure below was
  # recomputed in Python's `decimal` at 34 digits, half-up, by a script of
  # the lens's own, never copied from the read.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, deliver_untraded!: 4, deposit!: 3, put_quotes!: 2, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.Performance.Movers
  alias PortfolixirWeb.Api.V1.MoversJSON

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{currency_code: "EUR", asset_class: "fund"}, attrs)
      )

    security
  end

  defp rate!(currency, date, rate) do
    {:ok, 1} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp view!(depots, cash_accounts) do
    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "ML #{System.unique_integer([:positive])}"})

    for depot <- depots,
        do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

    for cash <- cash_accounts,
        do: :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "ML #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    view
  end

  defp world!(name) do
    world = base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")
    {world, view!([world.depot], [world.cash])}
  end

  defp by_name(entries, name), do: Enum.find(entries, &(&1["security"]["name"] == name))

  test "USD, GBX and EUR over a week: read and JSON against Python" do
    {world, view} = world!("FX")
    usd = security!(%{name: "Uniform USD", currency_code: "USD"})
    gbx = security!(%{name: "Golf GBX", currency_code: "GBX"})
    eur = security!(%{name: "Echo EUR"})

    for {s, q} <- [{usd, "3"}, {gbx, "7"}, {eur, "2"}],
        do: deliver_untraded!(world, s, q, date: ~D[2026-10-01])

    rate!("USD", ~D[2026-10-01], "1.05")
    rate!("GBP", ~D[2026-10-01], "0.84")
    rate!("USD", ~D[2026-11-06], "1.07")
    rate!("USD", ~D[2026-11-12], "1.13")
    rate!("GBP", ~D[2026-11-06], "0.85")
    rate!("GBP", ~D[2026-11-12], "0.86")
    put_quotes!(usd, [{~D[2026-11-06], "123"}, {~D[2026-11-12], "135.3"}])
    put_quotes!(gbx, [{~D[2026-11-06], "5000"}, {~D[2026-11-12], "5210"}])
    put_quotes!(eur, [{~D[2026-11-06], "50"}, {~D[2026-11-12], "49"}])

    {:ok, read} = Movers.read(view.id, "week", today: ~D[2026-11-12])
    json = read |> MoversJSON.movers() |> Jason.encode!() |> Jason.decode!()

    price = json["price_return"]
    assert Enum.map(price["highest"], & &1["security"]["name"]) == ["Uniform USD", "Golf GBX"]
    assert Enum.map(price["lowest"], & &1["security"]["name"]) == ["Echo EUR"]

    assert by_name(price["highest"], "Uniform USD")["return"] ==
             "0.041592920353982300884955752212389"

    assert by_name(price["highest"], "Golf GBX")["return"] == "0.02988372093023255813953488372093"
    assert by_name(price["lowest"], "Echo EUR")["return"] == "-0.02"

    money = json["contribution"]
    all = money["highest"] ++ money["lowest"]
    assert by_name(all, "Uniform USD")["contribution"] == "14.3437267388967000248118435199735"
    assert by_name(all, "Golf GBX")["contribution"] == "12.3050615595075239398084815321475"
    assert by_name(all, "Echo EUR")["contribution"] == "-2"
    assert by_name(all, "Uniform USD")["start_value"] == "344.8598130841121495327102803738318"
    assert by_name(all, "Golf GBX")["end_value"] == "424.0697674418604651162790697674417"

    # No float, no exponent anywhere in the payload.
    walk = fn walk, value ->
      case value do
        v when is_float(v) -> flunk("float #{v}")
        v when is_binary(v) -> refute v =~ ~r/^-?\d+(\.\d+)?[eE][+-]?\d+$/, "exponent #{v}"
        v when is_map(v) -> Enum.each(v, fn {_k, x} -> walk.(walk, x) end)
        v when is_list(v) -> Enum.each(v, &walk.(walk, &1))
        _ -> :ok
      end
    end

    walk.(walk, json)
  end

  # A round number with trailing zeros in its coefficient: 100 x 10 = 1000,
  # a contribution "1E+3" after Decimal.normalize/1 in scientific notation.
  test "a whole-number figure renders without an exponent" do
    {world, view} = world!("Round")
    s = security!(%{name: "Round Fund"})
    deliver_untraded!(world, s, "100", date: ~D[2026-10-01])
    put_quotes!(s, [{~D[2026-11-06], "10"}, {~D[2026-11-12], "20"}])
    {:ok, read} = Movers.read(view.id, "week", today: ~D[2026-11-12])
    json = read |> MoversJSON.movers() |> Jason.encode!() |> Jason.decode!()
    [row] = json["contribution"]["highest"]
    assert row["contribution"] == "1000"
    [p] = json["price_return"]["highest"]
    assert p["return"] == "1"
  end

  # A position held at the baseline unvalued and sold on the window's first
  # day without a close ever: start 0, end 0, net_flows -proceeds, so the
  # proceeds read as a contribution. It is never valued on a window day.
  test "unvalued at the baseline, sold on the first window day" do
    {world, view} = world!("Gone")
    s = security!(%{name: "Gone Fund"})
    other = security!(%{name: "Other Fund"})
    deposit!(world, "100", ~D[2026-10-01])
    deliver_untraded!(world, s, "4", date: ~D[2026-10-01])
    buy!(world, other, quantity: "1", price: "10", date: ~D[2026-10-02])
    put_quotes!(other, [{~D[2026-11-06], "10"}, {~D[2026-11-12], "11"}])
    sell!(world, s, quantity: "4", price: "25", date: ~D[2026-11-09])

    {:ok, read} =
      Movers.read(view.id, "week", today: ~D[2026-11-12], include_unanswered: true)

    assert read.contribution.unanswered == %{no_valuation: 1, zero_contribution: 0}

    assert [%{reason: "no_valuation", security: %{name: "Gone Fund"}}] =
             read.contribution.unanswered_entries
  end

  # A legacy zero close (stored by a release before the plausibility bounds)
  # is no price for the price side (WindowReturn, ADR-0046), but the walk
  # reads it as a price of 0: on day D = 12 November the baseline (the 11th)
  # values Nova at 0, so its whole value, 1 x 11 - 1 x 0 = 11, reads as its
  # day's money move where its move is 1 x (11 - 10) = 1. The walk's figure
  # stays (which closes it reads is its own decision); the count names the
  # baseline day as no price, so the row is ranked marked, as #1472's is
  # (Sprint 30 closing act, money lens, finding 1; ADR-0051 §10 as amended
  # 2026-11-19).
  test "a legacy zero close on the baseline day: the money side is marked" do
    {world, view} = world!("Nova")
    nova = security!(%{name: "Nova Zero Between"})
    deliver_untraded!(world, nova, "1", date: ~D[2026-10-20])
    put_quotes!(nova, [{~D[2026-11-10], "10"}, {~D[2026-11-12], "11"}])
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, _} =
      Portfolixir.Repo.insert_all(Portfolixir.Catalog.Quote, [
        %{
          security_id: nova.id,
          date: ~D[2026-11-11],
          close: Decimal.new("0"),
          source: "manual",
          inserted_at: now,
          updated_at: now
        }
      ])

    {:ok, read} = Movers.read(view.id, "day", today: ~D[2026-11-12])
    [price] = read.price_return.highest
    assert Decimal.equal?(price.return, Decimal.new("0.1"))
    [money] = read.contribution.highest
    assert Decimal.equal?(money.contribution, Decimal.new("11"))
    assert Decimal.equal?(money.start_value, Decimal.new("0"))
    assert money.held_at_start and money.held_at_end
    assert {money.unvalued_days, money.unvalued_reason, money.valued_days} == {1, :no_price, 1}
    assert read.contribution.unanswered == %{no_valuation: 0, zero_contribution: 0}

    # Wealth's table for the same day reads the same row.
    {:ok, wealth} =
      Contribution.for_view(view.id,
        period: {:range, ~D[2026-11-12], ~D[2026-11-12]},
        base_currency: "EUR",
        today: ~D[2026-11-12]
      )

    row = Enum.find(wealth.positions, &(&1.security_id == nova.id))
    assert Decimal.equal?(row.contribution, Decimal.new("11"))
    assert {row.unvalued_days, row.unvalued_reason} == {1, :no_price}
  end

  # ADR-0061 §6 item 7, as corrected (Sprint 30 closing act, money lens,
  # finding 2): the two sides read one sign for a position held over the
  # whole window without flows only when each close is dated on the day it
  # stands for, or no rate is stored after it up to that day. A USD fund
  # held all week, its last close on
  # Monday (E, within 7 days of Thursday T), a USD rate stored on Thursday:
  # the price side converts E at Monday's rate, the money side values the
  # same close at Thursday's, each day at that day's rate. Python decimal,
  # 34 digits: price 100.5 x 1.10 / (100 x 1.10) - 1 = 0.005; money
  # 100.5 x (1 / 1.12) - 100 x (1 / 1.10) = -1.17694805194805194805194805194805.
  test "held all week without flows: the two sides disagree on the sign" do
    {world, view} = world!("Sign")
    usd = security!(%{name: "Sign USD", currency_code: "USD"})
    deliver_untraded!(world, usd, "1", date: ~D[2026-10-01])
    rate!("USD", ~D[2026-10-01], "1.10")
    rate!("USD", ~D[2026-11-09], "1.10")
    rate!("USD", ~D[2026-11-12], "1.12")
    put_quotes!(usd, [{~D[2026-11-06], "100"}, {~D[2026-11-09], "100.5"}])

    {:ok, read} = Movers.read(view.id, "week", today: ~D[2026-11-12])
    [price] = read.price_return.highest
    [money] = read.contribution.highest
    assert Decimal.equal?(price.return, Decimal.new("0.005"))
    assert money.held_at_start and money.held_at_end
    assert Decimal.equal?(money.net_flows, 0)
    assert Decimal.equal?(money.contribution, Decimal.new("-1.17694805194805194805194805194805"))
    # The disagreement §6 item 7 names: a rise in USD, a loss in EUR.
    assert {Decimal.compare(price.return, 0), Decimal.compare(money.contribution, 0)} ==
             {:gt, :lt}

    assert read.contribution.computation_basis.figure =~
             "each day's value converts at that day's stored EUR-hub rate"
  end
end
