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

  # Filled from the walk as it loaded every close from the first booking on.
  @pinned %{
    "analysis later" => "e62134dd762e2fbf",
    "analysis pin" => "41a8eafbd5032fd1",
    "analysis pin core" => "4ad5e08d63b968eb",
    "contribution core 1y" => "7ba6fa25cf47c301",
    "contribution core 3y" => "afebf77667ef29ef",
    "contribution core 5y" => "c0bcd4dc8505f7bf",
    "contribution core max" => "a24dcc5389bfc89f",
    "contribution core range 2020-01-01..2022-12-31" => "96535950dd57aafe",
    "contribution core range 2023-01-02..2023-01-31" => "2de44539de471b2a",
    "contribution core range 2023-07-01..2023-12-31" => "6c3880bbbd9c55df",
    "contribution core range 2024-06-01..2024-06-30" => "94257b4672dcedbe",
    "contribution core year 2023" => "6e1421d7fea3174d",
    "contribution core year 2024" => "c08bdaeeed7dd82e",
    "contribution core ytd" => "a02786d398319343",
    "contribution later 1y" => "5809ed1c25542616",
    "contribution later 3y" => "100e4aeb97ce9777",
    "contribution later 5y" => "673671a03d87423e",
    "contribution later max" => "bd802a171df0df0b",
    "contribution later range 2020-01-01..2022-12-31" => "bb02398d2f769ebb",
    "contribution later range 2023-01-02..2023-01-31" => "ce0bc731474a679a",
    "contribution later range 2023-07-01..2023-12-31" => "7fdb4c778f54b15e",
    "contribution later range 2024-06-01..2024-06-30" => "1cb98a0d912a37db",
    "contribution later year 2023" => "c78ed6cd4fc1e777",
    "contribution later year 2024" => "f6ee57195adb5617",
    "contribution later ytd" => "267a62edc55131dd",
    "contribution pin 1y" => "292b259c82e9162c",
    "contribution pin 3y" => "de9b56590ab8b30f",
    "contribution pin 5y" => "b1bd46656d9e436a",
    "contribution pin core 1y" => "35a95c93b55d097b",
    "contribution pin core 3y" => "a54be9c6864936cb",
    "contribution pin core 5y" => "348090367252de03",
    "contribution pin core max" => "c0eadfe9b85d557e",
    "contribution pin core range 2020-01-01..2022-12-31" => "fc1949219b9dc6c8",
    "contribution pin core range 2023-01-02..2023-01-31" => "89647ac96b06f37b",
    "contribution pin core range 2023-07-01..2023-12-31" => "502a0c5b4ef97f1d",
    "contribution pin core range 2024-06-01..2024-06-30" => "4c7f7207df7c143b",
    "contribution pin core year 2023" => "3074ef8f59016340",
    "contribution pin core year 2024" => "7aae6de56d16e6e2",
    "contribution pin core ytd" => "beb47cbc4de36b87",
    "contribution pin max" => "ead070f14230c366",
    "contribution pin range 2020-01-01..2022-12-31" => "4b038bee3207e821",
    "contribution pin range 2023-01-02..2023-01-31" => "3926cb5187817fbf",
    "contribution pin range 2023-07-01..2023-12-31" => "e4321679d4ac8f81",
    "contribution pin range 2024-06-01..2024-06-30" => "32b9a0dce3e0b3e1",
    "contribution pin year 2023" => "f4c1df33bfa128fc",
    "contribution pin year 2024" => "dc4b4f471dec7ef8",
    "contribution pin ytd" => "8fbcd8003de9a926",
    "contribution view 1y" => "ea27849b63289d1a",
    "contribution view 3y" => "de86f6741371d556",
    "contribution view 5y" => "1ca1e3a36ee18908",
    "contribution view max" => "c5c6c74d74f55e48",
    "contribution view range 2020-01-01..2022-12-31" => "6fe5a86c1da9c816",
    "contribution view range 2023-01-02..2023-01-31" => "b711e1bde51a9afd",
    "contribution view range 2023-07-01..2023-12-31" => "b903c1c5d6db9c8b",
    "contribution view range 2024-06-01..2024-06-30" => "a20e399d61b2fd3c",
    "contribution view year 2023" => "19f4ab1ffb68cbe6",
    "contribution view year 2024" => "e6a9b252bdc979af",
    "contribution view ytd" => "38f195241404dba3",
    "performance core 1y" => "4e7576c9bf9f3d52",
    "performance core 3y" => "372259ac6fd6c8e8",
    "performance core 5y" => "6c0ce8ce827f14d5",
    "performance core max" => "354a99cd767dc38f",
    "performance core range 2020-01-01..2022-12-31" => "bc7dea730174e871",
    "performance core range 2023-01-02..2023-01-31" => "39f3d92a78058070",
    "performance core range 2023-07-01..2023-12-31" => "a03feca51b6813d3",
    "performance core range 2024-06-01..2024-06-30" => "803af4426676c871",
    "performance core year 2023" => "be9dbd444f5d6e55",
    "performance core year 2024" => "fe989c50f48a04b6",
    "performance core ytd" => "2f9d1792e98ae2b6",
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
    "performance pin 1y" => "4bf2b0140624af91",
    "performance pin 3y" => "48656d909b940bd0",
    "performance pin 5y" => "d5bf268bd90ffcba",
    "performance pin core 1y" => "511a655565edcc0d",
    "performance pin core 3y" => "bad1a3160b53e94d",
    "performance pin core 5y" => "a1a4e3424daba2eb",
    "performance pin core max" => "21e9dbf112562ca5",
    "performance pin core range 2020-01-01..2022-12-31" => "7ecdb190dbba6050",
    "performance pin core range 2023-01-02..2023-01-31" => "ad7345a2d7b8f229",
    "performance pin core range 2023-07-01..2023-12-31" => "b83a94de5f7d4814",
    "performance pin core range 2024-06-01..2024-06-30" => "422ae62bcd51bd7c",
    "performance pin core year 2023" => "a94d666bad2383d5",
    "performance pin core year 2024" => "fbc117a1999f9e9b",
    "performance pin core ytd" => "aac7cdce9ae0550a",
    "performance pin max" => "0e6cf680b4564228",
    "performance pin range 2020-01-01..2022-12-31" => "7ecdb190dbba6050",
    "performance pin range 2023-01-02..2023-01-31" => "7c6fe8e1009b9d8a",
    "performance pin range 2023-07-01..2023-12-31" => "148797368e189b88",
    "performance pin range 2024-06-01..2024-06-30" => "57b89201866d4b46",
    "performance pin year 2023" => "48e2c7ae5a77002d",
    "performance pin year 2024" => "0cce71c252ea972f",
    "performance pin ytd" => "b8753ec81f40d64b",
    "performance view 1y" => "5d51d28ef6d5c047",
    "performance view 3y" => "a08b207f16a2f761",
    "performance view 5y" => "a425d4054754fed3",
    "performance view max" => "0666100f7aa266b3",
    "performance view range 2020-01-01..2022-12-31" => "ff8c055cc1ce4615",
    "performance view range 2023-01-02..2023-01-31" => "f737ea2d6804d06c",
    "performance view range 2023-07-01..2023-12-31" => "30fd3b34a9ca7b8d",
    "performance view range 2024-06-01..2024-06-30" => "1180782713345b72",
    "performance view year 2023" => "b30962972ea80517",
    "performance view year 2024" => "0ab29fec98008f91",
    "performance view ytd" => "c4ef36dc9932d3f3",
    "view analysis" => "fbae09e2ebc2da04",
    "view analysis core" => "549ee3dc78dc4f16"
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
               ttwror: Decimal.new("0.001017611684111213014319390084350"),
               irr: Decimal.new("0.000483"),
               start_value: Decimal.new("0"),
               end_value: Decimal.new("105133.1528571428571428571428571428"),
               net_external_flows: Decimal.new("105006.6471962616822429906542056075")
             },
             half:
               {%{
                  result: Decimal.new("-46.8758310871518418688230008985"),
                  positions: Decimal.new("-1.9522012578616352201257861635220"),
                  remainder: Decimal.new("-44.923629829290206648697214734950")
                }, 9},
             view:
               {%{
                  result: Decimal.new("-335.8091109977902430732619411865"),
                  positions: Decimal.new("-123.3324834268230494645588985211627"),
                  remainder: Decimal.new("-212.476627570967193608703042665307")
                }, 8}
           }
  end

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
  #   baseline day's basis step, which no window reads.
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

    for {scope, plain_walk, kept_walk} <- walks, period <- @periods do
      label = "#{scope} #{label(period)}"
      plain = plain_walk.()
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
