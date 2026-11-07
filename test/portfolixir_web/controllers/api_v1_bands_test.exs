defmodule PortfolixirWeb.ApiV1BandsTest do
  # I23, FR-53 (Sprint 27 S2): the stacked chart's bands over the API, in the
  # performance family's three forms.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias PortfolixirWeb.Api.V1.JSON

  defp get_json(conn, path, status \\ 200) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(status)
  end

  # Invented figures only, all in EUR. The year before this one:
  #
  #   01-02  deposit 10000; buy Alpha Fund 10 @ 100 (closes 100, then 130 on
  #          12-31)
  #   03-02  buy Beta Share 5 @ 40 (never quoted: priced by its trade)
  #
  # The tree "Strategy" files Alpha under Growth (the operator's colour);
  # Beta is filed nowhere.
  defp world do
    year = Clock.today().year - 1
    on = fn month, day -> Date.new!(year, month, day) end

    world = base_world(name: "Bands", cash_name: "Cash", depot_name: "Depot")
    alpha = create_security!(name: "Alpha Fund", ticker: "ALF")
    beta = create_security!(name: "Beta Share", ticker: "BTS")

    deposit!(world, "10000", on.(1, 2))
    buy!(world, alpha, quantity: "10", price: "100", date: on.(1, 2))
    put_quotes!(alpha, [{on.(1, 2), "100"}, {on.(12, 31), "130"}])
    buy!(world, beta, quantity: "5", price: "40", date: on.(3, 2))

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Growth",
        color: "#112233"
      })

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), alpha.id, tree.id, growth.id)

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Bands bucket"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Bands", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    Map.merge(world, %{
      year: year,
      alpha: alpha,
      beta: beta,
      tree: tree,
      growth: growth,
      view: view
    })
  end

  defp decimal_sum(values),
    do: Enum.reduce(values, Decimal.new("0"), &Decimal.add(Decimal.new(&1), &2))

  # User story (I23, FR-53; coverage rule):
  # As the operator's agent reading what a scope's wealth is made of,
  # I want one read per scope that answers the value series split into
  # bands, each with its daily values, its share and its change,
  # so that I can tell the operator what the stacked chart shows, from the
  # same figures.
  #
  # Acceptance criteria:
  # - GET /api/v1/portfolios/:portfolio_id/performance/bands answers
  #   portfolio_id, view_id, period, base_currency, start_date, end_date,
  #   level, sort, classification {id, name, chosen_by}, category, dates,
  #   bands, as_of, stale and computation_basis; year=, period= and
  #   from=/to= are the performance read's.
  # - Each band carries key, kind, id, name, color (the category's own, else
  #   null), tree_index, values (decimal strings aligned with dates),
  #   start_value, end_value, net_flows, share, change and members.
  # - On every date the bands sum exactly to the performance read's series.
  # - The view form and the view-less form answer the same bands for a
  #   scope that holds the same accounts.
  test "answers the bands, each day summing to the series", %{conn: conn} do
    w = world()
    path = "/api/v1/portfolios/#{w.portfolio.id}/performance/bands?year=#{w.year}"
    data = get_json(conn, path <> "&classification_id=#{w.tree.id}")["data"]

    assert data["portfolio_id"] == w.portfolio.id
    assert data["view_id"] == nil
    assert data["period"] == Integer.to_string(w.year)
    assert data["base_currency"] == "EUR"
    assert data["start_date"] == "#{w.year}-01-02"
    assert data["end_date"] == "#{w.year}-12-31"
    assert data["level"] == "category"
    assert data["sort"] == "size"

    assert data["classification"] == %{
             "id" => w.tree.id,
             "name" => "Strategy",
             "chosen_by" => "requested"
           }

    assert data["category"] == nil
    assert data["stale"] == false
    assert hd(data["dates"]) == "#{w.year}-01-02"

    # Cash 8800, Growth 1300 (Alpha 10 at 130), Unclassified 200 (Beta 5 at
    # 40) on the last day: largest first.
    assert Enum.map(data["bands"], & &1["key"]) ==
             ["cash", "category:#{w.growth.id}", "unclassified"]

    [cash, growth, unclassified] = data["bands"]

    assert Map.delete(growth, "values") == %{
             "key" => "category:#{w.growth.id}",
             "kind" => "category",
             "id" => w.growth.id,
             "name" => "Growth",
             "color" => "#112233",
             "tree_index" => 0,
             "start_value" => "0",
             "end_value" => "1300",
             "net_flows" => "1000",
             "share" => JSON.decimal(Decimal.div(Decimal.new(1300), Decimal.new(10_300))),
             "change" => nil,
             "members" => []
           }

    assert cash["end_value"] == "8800"
    assert cash["color"] == nil
    assert unclassified["end_value"] == "200"
    assert length(growth["values"]) == length(data["dates"])
    assert Enum.all?(growth["values"], &is_binary/1)

    performance =
      get_json(
        conn,
        "/api/v1/portfolios/#{w.portfolio.id}/performance?year=#{w.year}&series=true"
      )[
        "data"
      ]

    assert data["dates"] == Enum.map(performance["series"], & &1["date"])

    for {point, index} <- Enum.with_index(performance["series"]) do
      day = decimal_sum(Enum.map(data["bands"], &Enum.at(&1["values"], index)))
      assert Decimal.equal?(day, Decimal.new(point["value"])), point["date"]
    end

    # The three forms: the view and the view-less read see the same accounts.
    view_data =
      get_json(
        conn,
        "/api/v1/views/#{w.view.id}/performance/bands?year=#{w.year}&classification_id=#{w.tree.id}"
      )["data"]

    total_data =
      get_json(
        conn,
        "/api/v1/performance/bands?year=#{w.year}&classification_id=#{w.tree.id}"
      )["data"]

    assert view_data["view_id"] == w.view.id
    assert view_data["portfolio_id"] == nil
    assert view_data["view"] == %{"id" => w.view.id, "name" => "Bands"}
    assert {total_data["view_id"], total_data["portfolio_id"]} == {nil, nil}
    assert total_data["computation_basis"]["input_series"] =~ "every account in every portfolio"

    for other <- [view_data, total_data] do
      assert Enum.map(other["bands"], &Map.take(&1, ["key", "values"])) ==
               Enum.map(data["bands"], &Map.take(&1, ["key", "values"]))
    end

    # level=total is one band, the series; level=security&category_id= drills.
    [total] = get_json(conn, path <> "&level=total")["data"]["bands"]
    assert total["values"] == Enum.map(performance["series"], & &1["value"])

    drilled =
      get_json(conn, path <> "&level=security&category_id=#{w.growth.id}&sort=change")["data"]

    assert drilled["category"] == %{"id" => w.growth.id, "name" => "Growth", "color" => "#112233"}
    assert drilled["classification"]["chosen_by"] == "category"
    assert drilled["sort"] == "change"
    assert [%{"key" => key, "share" => "1"}] = drilled["bands"]
    assert key == "security:#{w.alpha.id}"
  end

  # User story (I23, FR-53; AGENTS.md metric rule):
  # As the operator's agent reading the bands,
  # I want the payload to state how they were computed,
  # so that I know which series they split, how the tree was chosen, what
  # merges into other and what a gap or a category change does.
  #
  # Acceptance criteria:
  # - computation_basis carries input_series (the walk's value series),
  #   window, reference null, level, classification (with how it was
  #   chosen), merge_rule, gaps (unpriced days count zero), category_change
  #   (the category of today) and assumptions (the change and share).
  test "the payload states its computation basis", %{conn: conn} do
    w = world()

    basis =
      get_json(conn, "/api/v1/portfolios/#{w.portfolio.id}/performance/bands?year=#{w.year}")[
        "data"
      ]["computation_basis"]

    assert basis["input_series"] =~ "value series"

    assert basis["window"] == %{
             "start_date" => "#{w.year}-01-02",
             "end_date" => "#{w.year}-12-31"
           }

    assert basis["reference"] == nil
    assert basis["level"] =~ "category"
    assert basis["classification"] =~ "allocation targets"
    assert basis["classification"] =~ "default"
    assert basis["merge_rule"] =~ "never by id"
    assert basis["gaps"] =~ "counts zero"
    assert basis["category_change"] =~ "category of today"
    assert basis["assumptions"] =~ "change = (end_value − start_value − net_flows) / start_value"
  end

  # User story (I23, FR-53; the closing act's money lens, M1):
  # As the operator's agent reading the bands of a view whose screen is
  # computed in a base currency other than EUR,
  # I want to ask the view and the view-less bands read for that currency,
  # so that I read the figures the stacked chart shows for the same request.
  #
  # Acceptance criteria:
  # - `base_currency=` on the view and the view-less form takes a code the
  #   app supports, echoes it as `base_currency`, and converts every band's
  #   values through the stored EUR-hub rate: at EUR/USD 1.25 each value is
  #   exactly 1.25 times the EUR one.
  # - Without it both forms answer in EUR, as before; the basis names the
  #   currency answered and the parameter.
  # - A code outside the supported list (lower case included) answers 422
  #   on base_currency and creates no atom.
  test "the view forms answer in a requested base currency", %{conn: conn} do
    w = world()

    {:ok, _} =
      Portfolixir.Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: Date.new!(w.year, 1, 1),
          rate: "1.25",
          source: "manual"
        }
      ])

    for path <- [
          "/api/v1/views/#{w.view.id}/performance/bands",
          "/api/v1/performance/bands"
        ] do
      query = "?year=#{w.year}&classification_id=#{w.tree.id}"
      eur = get_json(conn, path <> query)["data"]
      usd = get_json(conn, path <> query <> "&base_currency=USD")["data"]

      assert eur["base_currency"] == "EUR"
      assert usd["base_currency"] == "USD"
      assert usd["computation_basis"]["input_series"] =~ "in USD"
      assert eur["computation_basis"]["input_series"] =~ "base_currency"
      assert Enum.map(usd["bands"], & &1["key"]) == Enum.map(eur["bands"], & &1["key"])

      for {e, u} <- Enum.zip(eur["bands"], usd["bands"]),
          {ev, uv} <- Enum.zip(e["values"], u["values"]) do
        assert Decimal.equal?(
                 Decimal.mult(Decimal.new(ev), Decimal.new("1.25")),
                 Decimal.new(uv)
               ),
               "#{path} #{e["key"]}"
      end

      for bad <- ["usd", "XYZ", "EURO", ""] do
        errors = get_json(conn, path <> query <> "&base_currency=#{bad}", 422)["errors"]
        assert Map.keys(errors) == ["base_currency"], "#{path} #{inspect(bad)}"
      end
    end
  end

  # User story (I23, FR-53):
  # As the operator's agent,
  # I want a wrong parameter refused by name,
  # so that I never read a stack I did not ask for.
  #
  # Acceptance criteria:
  # - An unknown level or sort, a malformed or unknown classification_id or
  #   category_id, a category of another tree, and a category_id without
  #   level=security each answer 422 naming the parameter; a bad period
  #   answers the family's 422; an unknown portfolio or view a 404.
  test "refuses a wrong parameter by name", %{conn: conn} do
    w = world()
    {:ok, other} = Classifications.create_classification(Actor.owner_ui(), %{name: "Other"})
    base = "/api/v1/portfolios/#{w.portfolio.id}/performance/bands"

    for {query, field} <- [
          {"level=sector", "level"},
          {"sort=name", "sort"},
          {"classification_id=abc", "classification_id"},
          {"classification_id=999999999", "classification_id"},
          {"level=security&category_id=abc", "category_id"},
          {"level=security&category_id=999999999", "category_id"},
          {"level=security&category_id=#{w.growth.id}&classification_id=#{other.id}",
           "category_id"},
          {"level=category&category_id=#{w.growth.id}", "category_id"},
          {"period=2y", "period"}
        ],
        path <- [
          base,
          "/api/v1/views/#{w.view.id}/performance/bands",
          "/api/v1/performance/bands"
        ] do
      errors = get_json(conn, "#{path}?#{query}", 422)["errors"]
      assert Map.keys(errors) == [field], "#{path}?#{query}"
    end

    assert get_json(conn, "#{base}?level=sector", 422)["errors"]["level"] == [
             "is invalid: must be one of total, category, security"
           ]

    get_json(conn, "/api/v1/portfolios/999999999/performance/bands", 404)
    get_json(conn, "/api/v1/views/999999999/performance/bands", 404)
    get_json(conn, "#{base}?view=abc", 422)
  end
end
