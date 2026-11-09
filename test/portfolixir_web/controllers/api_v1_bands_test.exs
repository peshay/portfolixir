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

  # User story (FR-56, Sprint 28 S1; plan D-6):
  # As the operator's agent reading a category the way the chart filters it,
  # I want category_id to be a filter at every level, the unclassified
  # remainder included, in all three forms,
  # so that I read the same parts of a category the operator sees, and they
  # add up to its band.
  #
  # Acceptance criteria:
  # - `level=category&category_id=` of a category with a sub-category and
  #   securities of its own answers one band per direct sub-category and one
  #   band of kind `direct` (key `direct:<id>`, the category's own name, no
  #   colour), no cash, no unclassified; on every date they sum to the
  #   category's band of the read without category_id, exactly.
  # - `level=total&category_id=` is one band, the category's, equal to that
  #   band; `category_id=unclassified` at every level answers the remainder,
  #   one band `unclassified` above the securities level.
  # - The answer echoes `category_id` (the id, `unclassified` or null) and
  #   `computation_basis.filter`; the view and view-less forms answer the
  #   same bands.
  test "category_id filters every level, the unclassified remainder included", %{conn: conn} do
    w = world()
    year = w.year

    {:ok, large} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: w.tree.id,
        name: "Large Caps",
        parent_id: w.growth.id
      })

    gamma = create_security!(name: "Gamma Corp", ticker: "GMC")
    buy!(w, gamma, quantity: "2", price: "50", date: Date.new!(year, 6, 1))
    put_quotes!(gamma, [{Date.new!(year, 6, 1), "50"}, {Date.new!(year, 12, 31), "60"}])
    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), gamma.id, w.tree.id, large.id)

    for path <- [
          "/api/v1/portfolios/#{w.portfolio.id}/performance/bands",
          "/api/v1/views/#{w.view.id}/performance/bands",
          "/api/v1/performance/bands"
        ] do
      query = "?year=#{year}&classification_id=#{w.tree.id}"
      top = get_json(conn, path <> query)["data"]
      assert top["category_id"] == nil
      growth = Enum.find(top["bands"], &(&1["key"] == "category:#{w.growth.id}"))
      unclassified = Enum.find(top["bands"], &(&1["key"] == "unclassified"))

      filtered =
        get_json(conn, path <> query <> "&level=category&category_id=#{w.growth.id}")["data"]

      assert filtered["category_id"] == w.growth.id
      assert filtered["level"] == "category"
      assert filtered["computation_basis"]["filter"] =~ ~s("Growth" \(id #{w.growth.id}\))
      assert filtered["computation_basis"]["level"] =~ "kind direct"

      assert Enum.map(filtered["bands"], &Map.take(&1, ["key", "kind", "id", "name", "color"])) ==
               [
                 %{
                   "key" => "direct:#{w.growth.id}",
                   "kind" => "direct",
                   "id" => w.growth.id,
                   "name" => "Growth",
                   "color" => nil
                 },
                 %{
                   "key" => "category:#{large.id}",
                   "kind" => "category",
                   "id" => large.id,
                   "name" => "Large Caps",
                   "color" => nil
                 }
               ]

      for {value, index} <- Enum.with_index(growth["values"]) do
        day = decimal_sum(Enum.map(filtered["bands"], &Enum.at(&1["values"], index)))
        assert Decimal.equal?(day, Decimal.new(value)), "#{path} day #{index}"
      end

      # Alpha 10 at 130 and Gamma 2 at 60 on the last day.
      assert Enum.map(filtered["bands"], & &1["end_value"]) == ["1300", "120"]

      [line] =
        get_json(conn, path <> query <> "&level=total&category_id=#{w.growth.id}")["data"][
          "bands"
        ]

      assert Map.take(line, ["key", "values"]) == Map.take(growth, ["key", "values"])

      for level <- ["total", "category"] do
        [rest] =
          get_json(conn, path <> query <> "&level=#{level}&category_id=unclassified")["data"][
            "bands"
          ]

        assert Map.take(rest, ["key", "values"]) == Map.take(unclassified, ["key", "values"])
      end

      loose = get_json(conn, path <> query <> "&level=security&category_id=unclassified")["data"]
      assert loose["category_id"] == "unclassified"
      assert loose["category"] == nil
      assert Enum.map(loose["bands"], & &1["key"]) == ["security:#{w.beta.id}"]
      assert loose["computation_basis"]["filter"] =~ "unclassified"
    end
  end

  # User story (FR-56; Sprint 28 plan D-6: "an agent's call without `level`
  # answers as before"):
  # As the operator's agent that reads the bands without naming a level,
  # I want the answer unchanged by the screen's new default,
  # so that the contract does not move under me.
  #
  # Acceptance criteria:
  # - A call without `level` answers `level: "category"`, the root
  #   categories with cash and unclassified, exactly as `level=category`
  #   answers, in all three forms; only the screen's default changes.
  test "a call without level answers as before", %{conn: conn} do
    w = world()

    for path <- [
          "/api/v1/portfolios/#{w.portfolio.id}/performance/bands",
          "/api/v1/views/#{w.view.id}/performance/bands",
          "/api/v1/performance/bands"
        ] do
      query = "?year=#{w.year}&classification_id=#{w.tree.id}"
      plain = get_json(conn, path <> query)["data"]
      named = get_json(conn, path <> query <> "&level=category")["data"]

      assert plain["level"] == "category"
      assert Map.delete(plain, "as_of") == Map.delete(named, "as_of")

      assert Enum.map(plain["bands"], & &1["key"]) ==
               ["cash", "category:#{w.growth.id}", "unclassified"]
    end
  end

  # --- Sprint 28 S3 begin ---
  # User story (FR-57, I28; coverage rule):
  # As the operator's agent comparing how the parts of a view did,
  # I want the bands read to answer each band's own TTWROR as a line, with
  # the line one level up and its basis,
  # so that I tell the operator what the TTWROR mode shows, from the same
  # figures.
  #
  # Acceptance criteria:
  # - `scale=ttwror` in all three forms answers `scale: "ttwror"`, one line
  #   per band with `returns` aligned with `dates` (Decimal strings, null
  #   before a band's first point) and `ttwror`, its last point: Alpha Fund
  #   starts at 0 % on 01-02, the window's first day (the walk starts
  #   there, so there is no baseline value; V 1000) and ends at 1300 / 1000 − 1 = 0.3; Beta Share,
  #   bought on 03-02 and priced by its trade, is null before and 0 from
  #   03-02 on.
  # - No line for cash; at the category level none for unclassified.
  # - `parent` is the view's own line: its returns are the performance
  #   read's `cumulative_ttwror` series, exactly.
  # - The basis names the flows, the start rule, the selection rule and
  #   the gaps; `scale=value` answers what a call without scale answers.
  test "scale=ttwror answers each band's own TTWROR as a line", %{conn: conn} do
    w = world()
    year = w.year
    # The window starts on the first walked day, 01-02.
    first = Date.new!(year, 1, 2)

    for path <- [
          "/api/v1/portfolios/#{w.portfolio.id}/performance/bands",
          "/api/v1/views/#{w.view.id}/performance/bands",
          "/api/v1/performance/bands"
        ] do
      query = "?year=#{year}&classification_id=#{w.tree.id}"
      data = get_json(conn, path <> query <> "&level=security&scale=ttwror")["data"]
      assert data["scale"] == "ttwror", path
      assert data["dates"] |> hd() == Date.to_iso8601(first), path

      [alpha, beta] = data["bands"]
      assert alpha["key"] == "security:#{w.alpha.id}"
      assert alpha["end_value"] == "1300"
      assert alpha["ttwror"] == "0.3"
      assert hd(alpha["returns"]) == "0"
      assert List.last(alpha["returns"]) == "0.3"

      march = Enum.find_index(data["dates"], &(&1 == Date.to_iso8601(Date.new!(year, 3, 2))))
      assert beta["key"] == "security:#{w.beta.id}"
      assert Enum.all?(Enum.take(beta["returns"], march), &is_nil/1)
      assert Enum.all?(Enum.drop(beta["returns"], march), &(&1 == "0"))
      refute Map.has_key?(alpha, "values")

      performance_path = String.replace(path, "/bands", "")

      series =
        get_json(conn, performance_path <> "?year=#{year}&series=true")["data"]["series"]

      assert data["parent"]["returns"] == Enum.map(series, & &1["cumulative_ttwror"]), path

      categories = get_json(conn, path <> query <> "&level=category&scale=ttwror")["data"]
      assert Enum.map(categories["bands"], & &1["key"]) == ["category:#{w.growth.id}"], path

      basis = data["computation_basis"]

      for key <- ["flows", "start_rule", "selection_rule", "gaps", "reference"] do
        assert is_binary(basis[key]), "#{path} #{key}"
      end

      refute Map.has_key?(basis, "merge_rule")

      plain = get_json(conn, path <> query)["data"]
      assert plain["scale"] == "value"
      assert plain["parent"] == nil

      assert Map.delete(plain, "as_of") ==
               Map.delete(get_json(conn, path <> query <> "&scale=value")["data"], "as_of")
    end
  end

  # --- Sprint 28 S3 end ---

  # User story (I23, FR-53):
  # As the operator's agent,
  # I want a wrong parameter refused by name,
  # so that I never read a stack I did not ask for.
  #
  # Acceptance criteria:
  # - An unknown level, sort or scale, a malformed or unknown classification_id or
  #   category_id (anything but an id or `unclassified`, exactly), and a
  #   category of another tree at any level each answer 422 naming the
  #   parameter; a bad period answers the family's 422; an unknown portfolio
  #   or view a 404.
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
          {"level=total&category_id=#{w.growth.id}&classification_id=#{other.id}", "category_id"},
          {"category_id=none", "category_id"},
          {"category_id=Unclassified", "category_id"},
          # --- Sprint 28 S3 begin ---
          {"scale=percent", "scale"},
          {"scale=TTWROR", "scale"},
          # --- Sprint 28 S3 end ---
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

    assert get_json(conn, "#{base}?scale=percent", 422)["errors"]["scale"] == [
             "is invalid: must be one of value, ttwror"
           ]

    assert get_json(conn, "#{base}?category_id=none", 422)["errors"]["category_id"] == [
             "is invalid: must be a category id or unclassified"
           ]

    get_json(conn, "/api/v1/portfolios/999999999/performance/bands", 404)
    get_json(conn, "/api/v1/views/999999999/performance/bands", 404)
    get_json(conn, "#{base}?view=abc", 422)
  end
end
