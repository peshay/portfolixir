defmodule Portfolixir.Portfolios.Performance.WalkPayloadPinTest do
  # K08 (security review 2026-10-12): the walk loads each security's closes
  # only while they can matter, and a contribution window's walk starts at
  # the window. Neither may move a figure. This file pins every performance
  # read over a ledger of the review seed's shapes, captured before the
  # loading change, to the last Decimal digit.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Contribution

  @moduletag timeout: 300_000

  @today ~D[2025-06-30]

  @periods [
    "ytd",
    "1y",
    "3y",
    "5y",
    "max",
    {:year, 2023},
    {:year, 2024},
    {:range, ~D[2023-07-01], ~D[2023-12-31]},
    {:range, ~D[2024-06-01], ~D[2024-06-30]},
    {:range, ~D[2023-01-02], ~D[2023-01-31]},
    {:range, ~D[2020-01-01], ~D[2022-12-31]}
  ]

  # Weekly closes from `from` to `to`, a gentle synthetic wave.
  defp weekly!(security, from, to, base, source \\ "manual") do
    from
    |> Stream.iterate(&Date.add(&1, 7))
    |> Enum.take_while(&(Date.compare(&1, to) != :gt))
    |> Enum.with_index()
    |> Enum.each(fn {date, i} ->
      close = Decimal.add(Decimal.new(base), Decimal.div(Decimal.new(rem(i * 7, 23)), 4))
      insert_quote!(security, date, close, source)
    end)
  end

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: close,
        source: source
      })
      |> Repo.insert()
  end

  defp weekly_rates!(currency, from, to, base) do
    rows =
      from
      |> Stream.iterate(&Date.add(&1, 7))
      |> Enum.take_while(&(Date.compare(&1, to) != :gt))
      |> Enum.with_index()
      |> Enum.map(fn {date, i} ->
        %{
          base_currency: "EUR",
          quote_currency: currency,
          date: date,
          rate: Decimal.add(Decimal.new(base), Decimal.div(Decimal.new(rem(i * 3, 11)), 100)),
          source: "manual"
        }
      end)

    {:ok, _} = Fx.upsert_many(rows)
  end

  defp book!(world, attrs) do
    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(
          %{portfolio_id: world.portfolio.id, currency_code: "EUR"},
          attrs
        )
      )

    tx
  end

  # The review seed's shapes on fixed dates: a position quoted long before
  # its first booking, one sold out while its closes go on (and a dividend
  # after the sale), one sold and bought again, a retired one whose only
  # later close comes after its sale, one never quoted before its sale and
  # quoted after it, one priced by its trade until its first close, a split,
  # a dollar position, a delivery without a price, a booking before 1970, and
  # a second portfolio that starts later.
  defp seed_ledger! do
    world = base_world(name: "Pin Depot", cash_name: "Pin Cash", depot_name: "Pin Depot")
    later = base_world(name: "Pin Later", cash_name: "Later Cash", depot_name: "Later Depot")

    usd =
      add_depot(world.portfolio,
        cash_name: "Pin USD",
        depot_name: "Pin USD Depot",
        currency: "USD"
      )

    usd_world = %{portfolio: world.portfolio, cash: usd.cash, depot: usd.depot}

    weekly_rates!("USD", ~D[2022-06-06], @today, "1.05")

    deposit!(world, "250", ~D[1960-05-02])
    deposit!(world, "100000", ~D[2023-01-02])
    deposit!(usd_world, "5000", ~D[2023-01-02], currency: "USD")

    alpha = create_security!(name: "Pin Alpha", ticker: nil)
    weekly!(alpha, ~D[2022-06-06], @today, "50")
    buy!(world, alpha, quantity: "10", price: "50", date: ~D[2023-03-01], fees: "1.50")
    buy!(world, alpha, quantity: "5", price: "52.25", date: ~D[2024-02-01])

    beta = create_security!(name: "Pin Beta", ticker: nil)
    weekly!(beta, ~D[2022-06-06], @today, "30")
    buy!(world, beta, quantity: "20", price: "30", date: ~D[2023-02-01])
    sell!(world, beta, quantity: "20", price: "33.10", date: ~D[2023-09-15], taxes: "2.40")

    book!(world, %{
      cash_account_id: world.cash.id,
      security_id: beta.id,
      type: "dividend",
      date: ~D[2023-10-02],
      gross_amount: "12.80"
    })

    gamma = create_security!(name: "Pin Gamma", ticker: nil)
    weekly!(gamma, ~D[2022-06-06], @today, "80")
    buy!(world, gamma, quantity: "8", price: "80", date: ~D[2023-04-03])
    sell!(world, gamma, quantity: "8", price: "81.75", date: ~D[2023-07-03])
    buy!(world, gamma, quantity: "4", price: "82", date: ~D[2024-05-02])

    delta = create_security!(name: "Pin Delta", ticker: nil)
    weekly!(delta, ~D[2022-06-06], ~D[2023-05-29], "60")
    insert_quote!(delta, ~D[2024-09-02], Decimal.new("41.5"), "manual")
    buy!(world, delta, quantity: "6", price: "60", date: ~D[2023-02-15])
    buy!(world, delta, quantity: "1", price: "70", date: ~D[2023-08-01])
    sell!(world, delta, quantity: "7", price: "55", date: ~D[2024-01-10])
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), delta, %{is_retired: true})

    epsilon = create_security!(name: "Pin Epsilon", ticker: nil)
    buy!(world, epsilon, quantity: "3", price: "40", date: ~D[2023-05-02])
    sell!(world, epsilon, quantity: "3", price: "45", date: ~D[2023-11-01])
    weekly!(epsilon, ~D[2024-03-04], @today, "47")

    zeta = create_security!(name: "Pin Zeta", ticker: nil)
    buy!(world, zeta, quantity: "10", price: "20", date: ~D[2023-06-01])
    weekly!(zeta, ~D[2023-08-07], @today, "22")

    eta = create_security!(name: "Pin Eta", ticker: nil)
    weekly!(eta, ~D[2022-06-06], ~D[2024-04-08], "10")
    weekly!(eta, ~D[2024-04-15], @today, "5")
    buy!(world, eta, quantity: "100", price: "10", date: ~D[2023-03-15])

    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: eta.id,
        date: ~D[2024-04-15],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    theta = create_security!(name: "Pin Theta", ticker: nil, currency: "USD")
    weekly!(theta, ~D[2022-06-06], @today, "120")

    cross_trade!(world, theta,
      quantity: "4",
      price: "120",
      settled: "457.14",
      gross: "458.14",
      fees: "1",
      date: ~D[2023-05-15]
    )

    iota = create_security!(name: "Pin Iota", ticker: nil)
    weekly!(iota, ~D[2022-06-06], @today, "15")

    book!(world, %{
      securities_account_id: world.depot.id,
      security_id: iota.id,
      type: "inbound_delivery",
      date: ~D[2023-10-10],
      quantity: "5"
    })

    # Every other leg kind the walk reduces: a cash transfer between two
    # accounts, a depot transfer, a stated balance, a standalone fee (one
    # naming a security), a tax, interest in both currencies, a removal, and
    # outbound deliveries with and without a price.
    reserve =
      add_depot(world.portfolio, cash_name: "Pin Reserve", depot_name: "Pin Reserve Depot")

    book!(world, %{
      cash_account_id: world.cash.id,
      counter_cash_account_id: reserve.cash.id,
      type: "cash_transfer",
      date: ~D[2023-06-15],
      gross_amount: "2000"
    })

    book!(world, %{
      securities_account_id: world.depot.id,
      counter_securities_account_id: reserve.depot.id,
      security_id: alpha.id,
      type: "security_transfer",
      date: ~D[2024-03-15],
      quantity: "4"
    })

    {:ok, _} =
      Ledger.set_cash_balance(
        Actor.owner_ui(),
        Portfolios.get_cash_account(reserve.cash.id),
        %{"date" => "2024-08-30", "amount" => "2100.55"}
      )

    for {type, amount, date, extra} <- [
          {"fee", "7.25", ~D[2023-09-01], %{}},
          {"fee", "3.10", ~D[2024-07-01], %{security_id: alpha.id}},
          {"tax", "15.40", ~D[2024-02-20], %{}},
          {"interest", "3.10", ~D[2023-12-29], %{}},
          {"removal", "500", ~D[2024-10-01], %{}}
        ] do
      book!(
        world,
        Map.merge(
          %{cash_account_id: world.cash.id, type: type, date: date, gross_amount: amount},
          extra
        )
      )
    end

    book!(world, %{
      cash_account_id: usd.cash.id,
      type: "interest",
      date: ~D[2024-06-28],
      gross_amount: "1.25",
      currency_code: "USD"
    })

    book!(world, %{
      securities_account_id: world.depot.id,
      security_id: iota.id,
      type: "outbound_delivery",
      date: ~D[2025-02-03],
      quantity: "2"
    })

    book!(world, %{
      securities_account_id: world.depot.id,
      security_id: zeta.id,
      type: "outbound_delivery",
      date: ~D[2025-03-03],
      quantity: "2",
      price: "0"
    })

    deposit!(later, "3000", ~D[2024-01-03])
    buy!(later, alpha, quantity: "7", price: "51", date: ~D[2024-01-04])
    buy!(later, beta, quantity: "3", price: "31", date: ~D[2024-03-01])

    {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Pin Core"})

    for depot <- [world.depot, later.depot],
        do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [core.id])

    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [core.id])

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Pin Core", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [core.id], [])

    %{world: world, later: later, view: view}
  end

  # The figures, never the instant they were computed at, and every row id
  # as the name it was created under, so the digest does not depend on the
  # sequences.
  defp canonical(%Decimal{} = decimal, _ids), do: decimal
  defp canonical(%Date{} = date, _ids), do: date
  defp canonical(%DateTime{}, _ids), do: :instant

  defp canonical(map, ids) when is_map(map) do
    map
    |> Map.drop([:as_of, :computed_at, :stale])
    |> Map.new(fn {key, value} -> {key, canonical_field(key, value, ids)} end)
  end

  defp canonical(list, ids) when is_list(list), do: Enum.map(list, &canonical(&1, ids))

  defp canonical(tuple, ids) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> canonical(ids) |> List.to_tuple()

  defp canonical(other, _ids), do: other

  defp canonical_field(key, id, ids)
       when key in [:security_id, :portfolio_id, :cash_account_id, :view_id] and is_integer(id),
       do: Map.fetch!(ids, {key, id})

  defp canonical_field(key, by_account, ids)
       when key in [:unvalued_cash, :cash_labels] and is_map(by_account),
       do:
         Map.new(by_account, fn {account_id, value} ->
           {Map.fetch!(ids, {:cash_account_id, account_id}), canonical(value, ids)}
         end)

  defp canonical_field(_key, value, ids), do: canonical(value, ids)

  defp ids do
    securities =
      for s <- Repo.all(Portfolixir.Catalog.Security),
          into: %{},
          do: {{:security_id, s.id}, s.name}

    portfolios =
      for p <- Repo.all(Portfolixir.Portfolios.Portfolio),
          into: %{},
          do: {{:portfolio_id, p.id}, p.name}

    accounts =
      for a <- Repo.all(Portfolixir.Portfolios.CashAccount),
          into: %{},
          do: {{:cash_account_id, a.id}, a.name}

    views =
      for v <- Repo.all(Portfolixir.Buckets.View), into: %{}, do: {{:view_id, v.id}, v.name}

    securities |> Map.merge(portfolios) |> Map.merge(accounts) |> Map.merge(views)
  end

  defp digest(term, ids) do
    term
    |> canonical(ids)
    |> inspect(limit: :infinity, printable_limit: :infinity, custom_options: [sort_maps: true])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp label({:year, year}), do: "year #{year}"
  defp label({:range, from, to}), do: "range #{from}..#{to}"
  defp label(period), do: period

  defp reads(%{world: world, later: later, view: view}) do
    walks = [
      {"analysis pin", Performance.analysis(world.portfolio.id, today: @today)},
      {"analysis later", Performance.analysis(later.portfolio.id, today: @today)},
      {"view analysis", Performance.view_analysis(nil, today: @today)},
      {"analysis pin core",
       Performance.analysis(world.portfolio.id, view: view.id, today: @today)},
      {"view analysis core", Performance.view_analysis(view.id, today: @today)}
    ]

    per_period =
      for period <- @periods,
          {name, read} <- [
            {"performance pin",
             fn ->
               Performance.for_portfolio(world.portfolio.id, period: period, today: @today)
             end},
            {"performance later",
             fn ->
               Performance.for_portfolio(later.portfolio.id, period: period, today: @today)
             end},
            {"performance view",
             fn -> Performance.for_view(nil, period: period, today: @today) end},
            {"contribution pin",
             fn ->
               Contribution.for_portfolio(world.portfolio.id, period: period, today: @today)
             end},
            {"contribution later",
             fn ->
               Contribution.for_portfolio(later.portfolio.id, period: period, today: @today)
             end},
            {"contribution view",
             fn -> Contribution.for_view(nil, period: period, today: @today) end},
            {"performance pin core",
             fn ->
               Performance.for_portfolio(world.portfolio.id,
                 view: view.id,
                 period: period,
                 today: @today
               )
             end},
            {"performance core",
             fn -> Performance.for_view(view.id, period: period, today: @today) end},
            {"contribution pin core",
             fn ->
               Contribution.for_portfolio(world.portfolio.id,
                 view: view.id,
                 period: period,
                 today: @today
               )
             end},
            {"contribution core",
             fn -> Contribution.for_view(view.id, period: period, today: @today) end}
          ] do
        {"#{name} #{label(period)}", read.() |> without_valued_days()}
      end

    walks ++ per_period
  end

  # Sprint 30 T1 (ADR-0061 §4) added each contribution row's `valued_days`,
  # a count of days, not a figure; the pins hold the figures captured
  # before it, so the count is set aside here and pinned by the
  # contribution tests.
  defp without_valued_days({:ok, %{positions: positions} = read}),
    do: {:ok, %{read | positions: Enum.map(positions, &Map.delete(&1, :valued_days))}}

  defp without_valued_days(read), do: read

  defp headline(reads) do
    {:ok, max} = reads["performance pin max"]
    {:ok, half} = reads["contribution pin range 2023-07-01..2023-12-31"]
    {:ok, view} = reads["contribution view year 2024"]

    %{
      max: Map.take(max, [:ttwror, :irr, :start_value, :end_value, :net_external_flows]),
      half: {half.totals, length(half.positions)},
      view: {view.totals, length(view.positions)}
    }
  end

  # Captured on the base commit, from the walk as it loaded every close
  # from the first booking on. Every "contribution …" digest was re-taken
  # once, for #928 (ADR-0051's amendment of 2026-10-09): its basis's
  # assumptions name the new income term and the narrower interest line. The
  # figures did not move: the walk's new interest clause under the old basis
  # text reproduced every digest before they were re-taken (this ledger's
  # interest bookings name no security). Every "performance …" and
  # "contribution …" digest was re-taken a second time for #1473 (ADR-0051's
  # amendment of 2026-11-21, Sprint 31 Z1): each basis's gaps text says a
  # stored close of 0 or below is not a price. The figures did not move:
  # with that clause removed from every string, each payload's digest was
  # the one pinned before, and the five walk digests, which carry no basis,
  # are unchanged.
  @pinned %{
    "analysis later" => "e62134dd762e2fbf",
    "analysis pin" => "60c06f98a124bcaf",
    "analysis pin core" => "95fb7ae18a87f890",
    "contribution core 1y" => "9a811135c651a995",
    "contribution core 3y" => "fed41b76ef069e40",
    "contribution core 5y" => "514003816114f6e7",
    "contribution core max" => "b4080e83b8933b0d",
    "contribution core range 2020-01-01..2022-12-31" => "993ebc4d812fa2cd",
    "contribution core range 2023-01-02..2023-01-31" => "49fc5e2e860f2c4c",
    "contribution core range 2023-07-01..2023-12-31" => "e51d831f3e0a1c65",
    "contribution core range 2024-06-01..2024-06-30" => "86e8d3ad29ebfba6",
    "contribution core year 2023" => "cb91e4bd7baa32b5",
    "contribution core year 2024" => "1b11cee274f0f098",
    "contribution core ytd" => "4e1c29d365124e4d",
    "contribution later 1y" => "8ac7bf270faf4c07",
    "contribution later 3y" => "88e17f50d8d2e7d9",
    "contribution later 5y" => "e6fdd316a122d51d",
    "contribution later max" => "b830f6abfe376fba",
    "contribution later range 2020-01-01..2022-12-31" => "bfdcfdacd13de93c",
    "contribution later range 2023-01-02..2023-01-31" => "e0b119e46f17086e",
    "contribution later range 2023-07-01..2023-12-31" => "b18501474075cebc",
    "contribution later range 2024-06-01..2024-06-30" => "9aea8c72e3aba7fa",
    "contribution later year 2023" => "ddb6aa9390d201ce",
    "contribution later year 2024" => "235e8b237899e03b",
    "contribution later ytd" => "c564d6e9a9d3b315",
    "contribution pin 1y" => "5ce75e9b06d4490c",
    "contribution pin 3y" => "796af6ccec1b3d61",
    "contribution pin 5y" => "250bcd3f1243d2a7",
    "contribution pin core 1y" => "d7cdecd9f50a3f51",
    "contribution pin core 3y" => "4d2929ada0a177c7",
    "contribution pin core 5y" => "95e5afb0cd52f51b",
    "contribution pin core max" => "7630d93cb7d4e79b",
    "contribution pin core range 2020-01-01..2022-12-31" => "abd6918a0dcfb21d",
    "contribution pin core range 2023-01-02..2023-01-31" => "2414dce0866bc414",
    "contribution pin core range 2023-07-01..2023-12-31" => "64ebc8a0b42d4e50",
    "contribution pin core range 2024-06-01..2024-06-30" => "a30e77a5f772f781",
    "contribution pin core year 2023" => "9d1e01b8a822d02d",
    "contribution pin core year 2024" => "d004d359f0eadc24",
    "contribution pin core ytd" => "c4fd9574daa90e36",
    "contribution pin max" => "54232d5eb4743fbe",
    "contribution pin range 2020-01-01..2022-12-31" => "6aff3ce074f48f41",
    "contribution pin range 2023-01-02..2023-01-31" => "55401d9817a7f405",
    "contribution pin range 2023-07-01..2023-12-31" => "52a05e547f54dda6",
    "contribution pin range 2024-06-01..2024-06-30" => "268cf4b8d1522528",
    "contribution pin year 2023" => "2b025ec1f40f42f1",
    "contribution pin year 2024" => "e2258cf7975544d1",
    "contribution pin ytd" => "51cb866a4cdbdd38",
    "contribution view 1y" => "561623994dcf839d",
    "contribution view 3y" => "cb81fa6e9945c767",
    "contribution view 5y" => "765298ffb33113ef",
    "contribution view max" => "92b8946d8935a25e",
    "contribution view range 2020-01-01..2022-12-31" => "c73db15e21869289",
    "contribution view range 2023-01-02..2023-01-31" => "2f187a3588fdf319",
    "contribution view range 2023-07-01..2023-12-31" => "c58089d358296bc5",
    "contribution view range 2024-06-01..2024-06-30" => "4948535addb59216",
    "contribution view year 2023" => "0fd266c2fba163a6",
    "contribution view year 2024" => "78ae14261d597468",
    "contribution view ytd" => "588e3bf7109b8f41",
    "performance core 1y" => "ba1ac873dd61e4fa",
    "performance core 3y" => "b3908dac3dfbe802",
    "performance core 5y" => "3271ae20c005b3f1",
    "performance core max" => "ba06bd52f3d301e6",
    "performance core range 2020-01-01..2022-12-31" => "300c72b824aa6ea2",
    "performance core range 2023-01-02..2023-01-31" => "3f9ab830ad3d49f2",
    "performance core range 2023-07-01..2023-12-31" => "18217a607e4c2160",
    "performance core range 2024-06-01..2024-06-30" => "263c23d0734904cf",
    "performance core year 2023" => "8ece8acec46547dd",
    "performance core year 2024" => "2e23f04db0869f1d",
    "performance core ytd" => "c294d083d0197244",
    "performance later 1y" => "4f3617731076a541",
    "performance later 3y" => "59415ca43f9f5ee9",
    "performance later 5y" => "c7bedfabdc314113",
    "performance later max" => "abac876a8a39aaa8",
    "performance later range 2020-01-01..2022-12-31" => "3c597fd3ed786c31",
    "performance later range 2023-01-02..2023-01-31" => "40ae7896b9f53bcd",
    "performance later range 2023-07-01..2023-12-31" => "312235c2780ca776",
    "performance later range 2024-06-01..2024-06-30" => "68a5323c4afedfab",
    "performance later year 2023" => "e8ec2a690cc929f3",
    "performance later year 2024" => "296c0a3dec9a6811",
    "performance later ytd" => "72a0ee8cdf364fd5",
    "performance pin 1y" => "c85a2396e09fba18",
    "performance pin 3y" => "0cb260be3f0c8b68",
    "performance pin 5y" => "e93d97b50177b2a1",
    "performance pin core 1y" => "69ba48a09efdfda9",
    "performance pin core 3y" => "93e7056bdb011c0e",
    "performance pin core 5y" => "8492e6bf47236031",
    "performance pin core max" => "31d0947e2c16d98d",
    "performance pin core range 2020-01-01..2022-12-31" => "bcd53c53ac44382f",
    "performance pin core range 2023-01-02..2023-01-31" => "15be116d8cdbcf2d",
    "performance pin core range 2023-07-01..2023-12-31" => "abadc4a6d05b832f",
    "performance pin core range 2024-06-01..2024-06-30" => "3a35a9e6f146a0a2",
    "performance pin core year 2023" => "e1fdc03246a5c4bc",
    "performance pin core year 2024" => "efb698b592fee92d",
    "performance pin core ytd" => "7b00807213a69d1d",
    "performance pin max" => "3ab5f8d594c46b94",
    "performance pin range 2020-01-01..2022-12-31" => "bcd53c53ac44382f",
    "performance pin range 2023-01-02..2023-01-31" => "1e6fd7e099390a91",
    "performance pin range 2023-07-01..2023-12-31" => "085db2573c3e9295",
    "performance pin range 2024-06-01..2024-06-30" => "a5f3849ce82d8321",
    "performance pin year 2023" => "fec7b65e894fab08",
    "performance pin year 2024" => "400236d65879ba0a",
    "performance pin ytd" => "ae1d9dad9de5de9a",
    "performance view 1y" => "06a3d0d35d9e7a77",
    "performance view 3y" => "8bad8172e6b2c83c",
    "performance view 5y" => "5aa3735ba6c56430",
    "performance view max" => "216af00e5026648b",
    "performance view range 2020-01-01..2022-12-31" => "d6a70955528e289a",
    "performance view range 2023-01-02..2023-01-31" => "2aedebf1ae035c19",
    "performance view range 2023-07-01..2023-12-31" => "18a543c62c3e6a24",
    "performance view range 2024-06-01..2024-06-30" => "b05e8e1a835da703",
    "performance view year 2023" => "259fbb0cf88b5e5b",
    "performance view year 2024" => "512a019ae8e473cf",
    "performance view ytd" => "550d74e621eeb4d9",
    "view analysis" => "92e0bed4fa9d7010",
    "view analysis core" => "2571ee5b8b796e4e"
  }

  # User story (security review 2026-10-12, K08):
  # As the operator and the agent reading performance figures,
  # I want the walk to load only the closes that can move a figure, and a
  # contribution window to be walked from the window,
  # so that the figures I read stay exactly what they were.
  #
  # Acceptance criteria:
  # - Every performance read over the pinned ledger (each portfolio's walk
  #   and the Everything view's, each period's performance and contribution
  #   read, custom ranges included) is the payload captured before the
  #   change, Decimal for Decimal, to the representation.
  # - The headline figures read as captured.
  test "every performance read over the review seed's shapes keeps its pinned payload" do
    assert_pinned!(seed_ledger!())
  end

  # User story (#1473, ADR-0051's amendment of 2026-11-21):
  # As the operator and the agent reading performance figures on an
  # instance whose older release stored a close of 0 or below,
  # I want the walk to read such a close as no price, as every other price
  # read does,
  # so that a feed's placeholder never reads as a total loss and back.
  #
  # Acceptance criteria:
  # - The pinned ledger with legacy closes of 0 and below added between its
  #   positive closes (on window baseline days, on a window's last day, on
  #   the day a carried seed is read, before a first booking, while a
  #   position is priced by its trade, in USD, before a split, and in the
  #   second portfolio) reads every pinned payload, Decimal for Decimal:
  #   the same seed without those rows.
  test "legacy closes of 0 and below leave every pinned payload as it is" do
    ledger = seed_ledger!()
    legacy_closes!()
    assert_pinned!(ledger)
  end

  # Rows a release before the plausibility bounds could store, written past
  # the changeset as they sit in such a table, each on a day without a close
  # of the seed's (its closes are weekly, on Mondays).
  defp legacy_closes! do
    by_name = Map.new(Repo.all(Portfolixir.Catalog.Security), &{&1.name, &1.id})
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      for {name, date, close} <- [
            # The day before Alpha's first buy: the lead close of its load.
            {"Pin Alpha", ~D[2023-02-28], "0"},
            # The baseline day of the range from 2023-07-01.
            {"Pin Alpha", ~D[2023-06-30], "0"},
            # The last day of 2023 and of the second half's range, and the
            # baseline day of 2024.
            {"Pin Alpha", ~D[2023-12-31], "-3"},
            # The seed day of a walk from the baseline of the June 2024 range.
            {"Pin Alpha", ~D[2024-05-30], "0"},
            # The June 2024 range's last day.
            {"Pin Alpha", ~D[2024-06-30], "0"},
            # Zeta, priced by its buy until its first close on 2023-08-07.
            {"Pin Zeta", ~D[2023-07-03], "0"},
            # Epsilon, never quoted while held.
            {"Pin Epsilon", ~D[2023-08-01], "0"},
            # Eta, the day before its 2:1 split.
            {"Pin Eta", ~D[2024-04-14], "0"},
            # Theta, a dollar position.
            {"Pin Theta", ~D[2023-08-15], "-0.01"},
            # Iota, delivered without a price.
            {"Pin Iota", ~D[2024-01-03], "0"},
            # Beta in the later portfolio.
            {"Pin Beta", ~D[2024-03-05], "0"}
          ] do
        %{
          security_id: Map.fetch!(by_name, name),
          date: date,
          close: Decimal.new(close),
          source: "manual",
          inserted_at: now,
          updated_at: now
        }
      end

    {11, _rows} = Repo.insert_all(SecurityQuote, rows)
    :ok
  end

  defp assert_pinned!(ledger) do
    reads = reads(ledger)
    ids = ids()
    actual = Map.new(reads, fn {name, payload} -> {name, digest(payload, ids)} end)

    changed = for {name, digest} <- @pinned, actual[name] != digest, do: name
    assert changed == [], "payloads moved: #{inspect(Enum.sort(changed))}"
    assert map_size(actual) == map_size(@pinned)

    assert headline(Map.new(reads)) == %{
             max: %{
               ttwror: Decimal.new("0.000316937586158318989571939930244"),
               irr: Decimal.new("0.000210"),
               start_value: Decimal.new("0"),
               end_value: Decimal.new("104628.6689285714285714285714285714"),
               net_external_flows: Decimal.new("104573.6971962616822429906542056075")
             },
             half:
               {%{
                  result: Decimal.new("-51.0258310871518418688230008985"),
                  positions: Decimal.new("-1.9522012578616352201257861635220"),
                  remainder: Decimal.new("-49.073629829290206648697214734950")
                }, 9},
             view:
               {%{
                  result: Decimal.new("-353.1829848716641169471358150603"),
                  positions: Decimal.new("-123.3324834268230494645588985211627"),
                  remainder: Decimal.new("-229.8505014448410674825769165391801")
                }, 8}
           }
  end

  # A window from the first booking, windows that start later, and one
  # before the history: the walk is seeded only where the window starts after
  # the first booking.
  @seeded_periods [
    "max",
    "ytd",
    {:year, 2023},
    {:range, ~D[2023-07-01], ~D[2023-12-31]},
    {:range, ~D[2024-06-01], ~D[2024-06-30]},
    {:range, ~D[2020-01-01], ~D[2022-12-31]}
  ]

  # The kept figures and their window, without the flag that chose the walk.
  defp kept(nil), do: nil
  defp kept(kept), do: Map.update!(kept, :window, &Map.take(&1, [:start, :end]))

  # User story (security review 2026-10-12, K08; ADR-0051 I9):
  # As the reviewer holding the contribution walk to ADR-0051's I9,
  # I want the walk a contribution read runs from its window's baseline day
  # to answer what the full walk answers on every day it walks,
  # so that starting at the window saves the days before it and nothing
  # else.
  #
  # Acceptance criteria:
  # - For each portfolio, a view-narrowed portfolio, a view across
  #   portfolios and the Everything view, and each period, the walk
  #   from the baseline day keeps the full walk's first date, and its days
  #   from the baseline day on are the full walk's: identical, but for the
  #   baseline day's basis step, which no window reads; a portfolio's walk
  #   starts on the baseline day, and a view's merged series walks no
  #   earlier day of a seeded portfolio.
  # - The period's summary and the kept per-position figures are identical
  #   to the full contribution walk's.
  test "a contribution walk from the window's baseline day answers what the full walk answers" do
    %{world: world, later: later, view: view} = seed_ledger!()
    pin = world.portfolio.id

    walks =
      for id <- [world.portfolio.id, later.portfolio.id] do
        {"portfolio #{id}", fn -> Performance.analysis(id, today: @today) end,
         fn period, opts ->
           Performance.contribution_analysis(id, :unscoped, period, [today: @today] ++ opts)
         end}
      end ++
        [
          {"Everything view", fn -> Performance.view_analysis(nil, today: @today) end,
           fn period, opts ->
             Performance.view_contribution_analysis(
               nil,
               :unscoped,
               period,
               [today: @today] ++ opts
             )
           end},
          {"portfolio narrowed by a view",
           fn -> Performance.analysis(pin, view: view.id, today: @today) end,
           fn period, opts ->
             Performance.contribution_analysis(
               pin,
               Buckets.load_scope(pin, view.id),
               period,
               [today: @today] ++ opts
             )
           end},
          {"view across portfolios", fn -> Performance.view_analysis(view.id, today: @today) end,
           fn period, opts ->
             Performance.view_contribution_analysis(
               view.id,
               Buckets.load_global_scope(view.id),
               period,
               [today: @today] ++ opts
             )
           end}
        ]

    for {scope, plain_walk, kept_walk} <- walks,
        plain = plain_walk.(),
        period <- @seeded_periods do
      label = "#{scope} #{label(period)}"
      full = kept_walk.(period, [])
      seeded = kept_walk.(period, from_baseline: true)

      assert seeded.first_date == plain.first_date, label

      {:ok, plain_summary} = Performance.summarise(plain, period)
      {:ok, seeded_summary} = Performance.summarise(seeded, period)

      baseline = plain_summary.start_date && Date.add(plain_summary.start_date, -1)

      if baseline && Date.compare(baseline, plain.first_date) == :gt do
        walked = &Enum.drop_while(&1, fn point -> Date.compare(point.date, baseline) == :lt end)
        [first | rest] = walked.(seeded.daily)
        [plain_first | plain_rest] = walked.(plain.daily)

        assert first.date == baseline, label
        assert Map.delete(first, :basis) == Map.delete(plain_first, :basis), label
        skipped = Enum.take_while(seeded.daily, &(Date.compare(&1.date, baseline) == :lt))

        if scope in ["Everything view", "view across portfolios"] do
          # The merged series counts zero on the days no seeded walk walked.
          assert Enum.all?(skipped, &Decimal.equal?(&1.value, 0)), label
        else
          # The walk itself starts on the baseline day.
          assert hd(seeded.daily).date == baseline and skipped == [], label
        end

        assert rest == plain_rest, label
      else
        # A window from the first booking on has no earlier day to skip.
        assert seeded.daily == plain.daily, label
      end

      assert Map.drop(seeded_summary, [:as_of, :stale]) ==
               Map.drop(plain_summary, [:as_of, :stale]),
             label

      assert kept(seeded.contribution) == kept(full.contribution), label
    end
  end
end
