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
        {"#{name} #{label(period)}", read.()}
      end

    walks ++ per_period
  end

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
  # interest bookings name no security).
  @pinned %{
    "analysis later" => "e62134dd762e2fbf",
    "analysis pin" => "60c06f98a124bcaf",
    "analysis pin core" => "95fb7ae18a87f890",
    "contribution core 1y" => "22f3178f7658ef06",
    "contribution core 3y" => "e4a1f01f101c7614",
    "contribution core 5y" => "13e928ff66625850",
    "contribution core max" => "9531fea9665661a2",
    "contribution core range 2020-01-01..2022-12-31" => "2442e3c0cf01996c",
    "contribution core range 2023-01-02..2023-01-31" => "8306f5de64e16cc0",
    "contribution core range 2023-07-01..2023-12-31" => "0b1a696c549cdadc",
    "contribution core range 2024-06-01..2024-06-30" => "f6ce58dc95e79c56",
    "contribution core year 2023" => "9768e0f0c48f994a",
    "contribution core year 2024" => "47f56555d31057f2",
    "contribution core ytd" => "46588704d980d310",
    "contribution later 1y" => "ad126d20660650f3",
    "contribution later 3y" => "4a811b475e553197",
    "contribution later 5y" => "2851bca22e357bf7",
    "contribution later max" => "a7725366a161fd92",
    "contribution later range 2020-01-01..2022-12-31" => "77a21db5d1866d03",
    "contribution later range 2023-01-02..2023-01-31" => "9d4a382a874df264",
    "contribution later range 2023-07-01..2023-12-31" => "0213c371be1fd7b5",
    "contribution later range 2024-06-01..2024-06-30" => "ea23a005fdc720b5",
    "contribution later year 2023" => "d0b4e5f5947ad0d1",
    "contribution later year 2024" => "2d0e15a47aed9e35",
    "contribution later ytd" => "77d60dd14085b9b0",
    "contribution pin 1y" => "52d53df936810049",
    "contribution pin 3y" => "fcc700f8e8a0d74a",
    "contribution pin 5y" => "27f0e601359f7921",
    "contribution pin core 1y" => "ee7e239cd37be887",
    "contribution pin core 3y" => "9a619bb1c44894ae",
    "contribution pin core 5y" => "d240c114f7bc3593",
    "contribution pin core max" => "c4a651d5e244ac76",
    "contribution pin core range 2020-01-01..2022-12-31" => "4602cd48c5b4c0fb",
    "contribution pin core range 2023-01-02..2023-01-31" => "c2e027a82fe7b36b",
    "contribution pin core range 2023-07-01..2023-12-31" => "e35924506ef9a801",
    "contribution pin core range 2024-06-01..2024-06-30" => "7e285482b7d4d9e9",
    "contribution pin core year 2023" => "5a94935c34c22a86",
    "contribution pin core year 2024" => "8e085d895983a2e5",
    "contribution pin core ytd" => "0c34dc1ff0e7cf78",
    "contribution pin max" => "34afadae8db115d6",
    "contribution pin range 2020-01-01..2022-12-31" => "f4c27ec16249390d",
    "contribution pin range 2023-01-02..2023-01-31" => "f20e9c03386796ac",
    "contribution pin range 2023-07-01..2023-12-31" => "f58402b17b3416c1",
    "contribution pin range 2024-06-01..2024-06-30" => "8781c3aae44d314c",
    "contribution pin year 2023" => "f909f07a2a76cb87",
    "contribution pin year 2024" => "3d4627056e38ff1d",
    "contribution pin ytd" => "afdc9e8c6a5e1da8",
    "contribution view 1y" => "feec415894426bd6",
    "contribution view 3y" => "025e9efca2dc8bda",
    "contribution view 5y" => "b0a0343a138ef9bc",
    "contribution view max" => "54ed45f0ede1c83a",
    "contribution view range 2020-01-01..2022-12-31" => "ebfcbb54789833e2",
    "contribution view range 2023-01-02..2023-01-31" => "47e5eb9bbef6f943",
    "contribution view range 2023-07-01..2023-12-31" => "99d8243a6627e0d3",
    "contribution view range 2024-06-01..2024-06-30" => "a8728f7b0bb34ab2",
    "contribution view year 2023" => "a85a23413e17adfe",
    "contribution view year 2024" => "303a7e3886b57a8f",
    "contribution view ytd" => "27c8fc14ac0a32cb",
    "performance core 1y" => "145b4bd7e158b5dc",
    "performance core 3y" => "e6bc8b5462714cce",
    "performance core 5y" => "92c0d83179fd3cac",
    "performance core max" => "358304c7e174fb01",
    "performance core range 2020-01-01..2022-12-31" => "bc7dea730174e871",
    "performance core range 2023-01-02..2023-01-31" => "39f3d92a78058070",
    "performance core range 2023-07-01..2023-12-31" => "9fd9ffcda038ca86",
    "performance core range 2024-06-01..2024-06-30" => "3b874c692011b55b",
    "performance core year 2023" => "87f2f3e24646e7b1",
    "performance core year 2024" => "eb6253cfff52c5e6",
    "performance core ytd" => "8371e0147bfc7fb7",
    "performance later 1y" => "2730c9019658d05a",
    "performance later 3y" => "616d2f62d9777eea",
    "performance later 5y" => "6f3c9ce0bb5d061d",
    "performance later max" => "191822971c65a3ee",
    "performance later range 2020-01-01..2022-12-31" => "a686bc4d1abf9de5",
    "performance later range 2023-01-02..2023-01-31" => "3403c7333832fd5d",
    "performance later range 2023-07-01..2023-12-31" => "036813feb29a2dbe",
    "performance later range 2024-06-01..2024-06-30" => "f7ed58605122de12",
    "performance later year 2023" => "234faa31c1bccb8a",
    "performance later year 2024" => "d35d8773cb7af67b",
    "performance later ytd" => "f90249ae298e0e44",
    "performance pin 1y" => "1de582c262c323c1",
    "performance pin 3y" => "c752411685bc4f2b",
    "performance pin 5y" => "c44900a8edc1310e",
    "performance pin core 1y" => "d5971b093e56e61d",
    "performance pin core 3y" => "b2741d84d38f66d0",
    "performance pin core 5y" => "ec7f791cb64837a8",
    "performance pin core max" => "235a3e90b3b245be",
    "performance pin core range 2020-01-01..2022-12-31" => "7ecdb190dbba6050",
    "performance pin core range 2023-01-02..2023-01-31" => "ad7345a2d7b8f229",
    "performance pin core range 2023-07-01..2023-12-31" => "bd88d4dbfbde5933",
    "performance pin core range 2024-06-01..2024-06-30" => "4cb9fdc544d74c87",
    "performance pin core year 2023" => "2423778dbafec350",
    "performance pin core year 2024" => "4aa605dc2b2e2d2e",
    "performance pin core ytd" => "9b18d30f73f3b453",
    "performance pin max" => "bba2a19179e66534",
    "performance pin range 2020-01-01..2022-12-31" => "7ecdb190dbba6050",
    "performance pin range 2023-01-02..2023-01-31" => "7c6fe8e1009b9d8a",
    "performance pin range 2023-07-01..2023-12-31" => "5ae8b96455fc1f00",
    "performance pin range 2024-06-01..2024-06-30" => "50a05b22e902ee49",
    "performance pin year 2023" => "7387db515866e6bd",
    "performance pin year 2024" => "1695928a8e0ca810",
    "performance pin ytd" => "a4113434986839be",
    "performance view 1y" => "41a1483cc3b5744a",
    "performance view 3y" => "32bc4902466b8d7d",
    "performance view 5y" => "cffb9cb9970e69fc",
    "performance view max" => "a5b2db5acb8ed928",
    "performance view range 2020-01-01..2022-12-31" => "ff8c055cc1ce4615",
    "performance view range 2023-01-02..2023-01-31" => "f737ea2d6804d06c",
    "performance view range 2023-07-01..2023-12-31" => "163be9c2885f4bb0",
    "performance view range 2024-06-01..2024-06-30" => "a1dcd5365fcd1a2a",
    "performance view year 2023" => "98478a36b329a90f",
    "performance view year 2024" => "a0634d744ede85fa",
    "performance view ytd" => "a37bf3079cae7af0",
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
    ledger = seed_ledger!()
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
