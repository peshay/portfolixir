defmodule PortfolixirWeb.ApiV1DataQualityTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3, sell!: 3]

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Journal

  @auth {"authorization", "Bearer test-api-token"}

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get(path)
  end

  defp names(response),
    do: response |> Map.fetch!("data") |> Enum.map(& &1["name"]) |> Enum.sort()

  defp seed do
    today = Date.utc_today()

    fresh = create_security!(name: "Fresh AG", ticker: "FRS")
    put_quote!(fresh, Date.add(today, -1), "100")

    stale = create_security!(name: "Stale AG", ticker: "STL")
    put_quote!(stale, Date.add(today, -30), "100")

    _unpriced = create_security!(name: "Unpriced AG", ticker: "UNP")

    {:ok, _} = Catalog.put_logo_attributes(fresh, %{"logo_path" => "/logos/frs.png"})

    :ok
  end

  # User story (#705, FR two-way coverage):
  # As the LLM agent maintaining this catalog,
  # I want to ask the API for the securities with a stale quote, no quote or no
  # logo,
  # so that I can work the same sets the dashboard counts and links to, instead
  # of only being told how many there are.
  #
  # Acceptance criteria:
  # - `?data_quality=` accepts each predicate and returns exactly that set.
  # - The result is the SAME set the shared predicate defines, so the agent and
  #   the human surface can never disagree about what "stale" means.
  # - An unknown value is a field-specific 422, never a silent full list.
  test "the securities listing narrows to each data-quality predicate", %{conn: conn} do
    seed()

    assert names(
             get_json(conn, "/api/v1/securities?data_quality=stale_quote")
             |> json_response(200)
           ) ==
             ["Stale AG", "Unpriced AG"]

    assert names(
             get_json(conn, "/api/v1/securities?data_quality=missing_quote")
             |> json_response(200)
           ) == ["Unpriced AG"]

    assert names(
             get_json(conn, "/api/v1/securities?data_quality=missing_logo")
             |> json_response(200)
           ) == ["Stale AG", "Unpriced AG"]
  end

  test "the API set is the shared predicate's set, not a second rule", %{conn: conn} do
    seed()

    for id <- DataQuality.ids() do
      from_api =
        get_json(conn, "/api/v1/securities?data_quality=#{id}") |> json_response(200) |> names()

      from_engine = DataQuality.list(id) |> Enum.map(& &1.security.name) |> Enum.sort()

      assert from_api == from_engine, "API and engine disagree for #{id}"
    end
  end

  test "an unknown predicate is a field-specific 422, never a silent full list", %{conn: conn} do
    seed()

    assert get_json(conn, "/api/v1/securities?data_quality=__bad__") |> json_response(422) ==
             %{"errors" => %{"data_quality" => ["is invalid"]}}

    # Blank counts as absent, like every other param on this route.
    assert get_json(conn, "/api/v1/securities?data_quality=") |> json_response(200) |> names() ==
             ["Fresh AG", "Stale AG", "Unpriced AG"]
  end

  # User story (#1068, D-15; contract entry 14):
  # As the LLM agent the operator runs,
  # I want to ask for the bonds priced on two scales by name,
  # so that I can work the set the Overview counts and the securities page
  # lists, in either direction.
  #
  # Acceptance criteria:
  # - data_quality=two_scales answers a classed bond quoted 97.25 beside a
  #   buy at 0.985, a classed bond quoted 0.981 beside a buy at 98.40, and an
  #   unclassed security with a coupon on the first pair's scales.
  # - It leaves out an unclassed security with no master data quoted 25
  #   times its buy price, and every security of the seed.
  test "data_quality=two_scales lists the bonds the guard flags, either way", %{conn: conn} do
    seed()
    world = base_world([])

    for {name, attrs, price, close} <- [
          {"Kestrel Anleihe 2030 2,75%", %{asset_class: "bond"}, "0.985", "97.25"},
          {"Birkenhain Wasser Anleihe 2029 1,50%", %{asset_class: "bond"}, "98.40", "0.981"},
          {"Ostsee Logistik 4,10% 2028/2033", %{coupon_rate: "4.1"}, "0.985", "97.25"},
          {"Ostsee Holz", %{}, "4", "100"}
        ] do
      {:ok, security} =
        Catalog.create_security(
          Portfolixir.Actor.owner_ui(),
          Map.merge(%{name: name, currency_code: "EUR"}, attrs)
        )

      buy!(world, security, quantity: "100", price: price, date: ~D[2026-03-12])
      put_quote!(security, ~D[2026-09-30], close)
    end

    assert get_json(conn, "/api/v1/securities?data_quality=two_scales")
           |> json_response(200)
           |> names() == [
             "Birkenhain Wasser Anleihe 2029 1,50%",
             "Kestrel Anleihe 2030 2,75%",
             "Ostsee Logistik 4,10% 2028/2033"
           ]
  end

  # User story (#1101, Sprint 20 plan D-7; contract entry 16; widened by
  # #1414, Sprint 29 D1, contract entry 29):
  # As the LLM agent the operator runs,
  # I want to ask for every security whose quotes contradict its own
  # bookings, held or not, with the booking each one contradicts, whether
  # it is held, and the rule,
  # so that I can work the set the Overview counts and Wealth names, and
  # check each finding without a second read.
  #
  # Acceptance criteria:
  # - data_quality=implausible_quote answers the held "Wrenfield Gardens
  #   AG" (bought 48.20, quoted 4.87 that day) and the sold-out "Arbolia
  #   Inc." (sold 61.40 beside 618.90 the day before), and nothing of the
  #   seed; holding_status=held narrows it to Wrenfield, not_held to
  #   Arbolia.
  # - The envelope's findings name each booking exactly: security_id, kind,
  #   date, price, currency_code, quote_date, close, ratio (close / price
  #   at scale 6, half up), bookings_outside and held (true for Wrenfield,
  #   false for Arbolia).
  # - The envelope's computation_basis states input_series, reference,
  #   window, gaps, threshold and assumptions (the AGENTS.md metric rule),
  #   its assumptions what the set covers: every security with a priced
  #   booking, held or not, benchmarks left out and a retired one unless
  #   held; another data_quality carries neither key.
  test "data_quality=implausible_quote lists the set, held or not, with its findings and basis",
       %{conn: conn} do
    seed()
    world = base_world([])
    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    buy!(world, wrenfield, quantity: "120", price: "48.20", date: ~D[2026-05-12])
    put_quote!(wrenfield, ~D[2026-05-12], "4.87")

    arbolia = create_security!(name: "Arbolia Inc.", ticker: "ARBL")
    buy!(world, arbolia, quantity: "10", price: "58.20", date: ~D[2025-11-03])
    sell!(world, arbolia, quantity: "10", price: "61.40", date: ~D[2026-04-03])
    put_quote!(arbolia, ~D[2026-04-02], "618.90")

    response =
      get_json(conn, "/api/v1/securities?data_quality=implausible_quote") |> json_response(200)

    assert names(response) == ["Arbolia Inc.", "Wrenfield Gardens AG"]

    assert response["findings"] == [
             %{
               "security_id" => arbolia.id,
               "kind" => "sell",
               "date" => "2026-04-03",
               "price" => "61.4",
               "currency_code" => "EUR",
               "quote_date" => "2026-04-02",
               "close" => "618.9",
               "ratio" => "10.079805",
               "bookings_outside" => 1,
               "held" => false
             },
             %{
               "security_id" => wrenfield.id,
               "kind" => "buy",
               "date" => "2026-05-12",
               "price" => "48.2",
               "currency_code" => "EUR",
               "quote_date" => "2026-05-12",
               "close" => "4.87",
               "ratio" => "0.101037",
               "bookings_outside" => 1,
               "held" => true
             }
           ]

    basis = response["computation_basis"]

    assert Map.keys(basis) |> Enum.sort() ==
             ~w(assumptions gaps input_series reference threshold window)

    assert basis["window"] =~ "within 7 days before the booking date"
    assert basis["threshold"] =~ "below 1/2 or above 2"
    assert basis["assumptions"] =~ "every security with a priced booking, held or not"
    assert basis["assumptions"] =~ "benchmark securities are left out"
    assert basis["assumptions"] =~ "a retired security unless it is held"

    held =
      get_json(conn, "/api/v1/securities?data_quality=implausible_quote&holding_status=held")
      |> json_response(200)

    assert names(held) == ["Wrenfield Gardens AG"]
    assert [%{"held" => true}] = held["findings"]

    not_held =
      get_json(conn, "/api/v1/securities?data_quality=implausible_quote&holding_status=not_held")
      |> json_response(200)

    assert names(not_held) == ["Arbolia Inc."]
    assert [%{"held" => false}] = not_held["findings"]

    other = get_json(conn, "/api/v1/securities?data_quality=stale_quote") |> json_response(200)
    refute Map.has_key?(other, "findings")
    refute Map.has_key?(other, "computation_basis")
  end

  test "it composes with the listing's other narrowings", %{conn: conn} do
    seed()

    assert names(
             get_json(conn, "/api/v1/securities?data_quality=stale_quote&query=Unpriced")
             |> json_response(200)
           ) == ["Unpriced AG"]
  end

  # User story (PR #1102):
  # As the operator's agent tidying sold-out and delisted securities the
  # catalog keeps for their bookings,
  # I want PATCH is_retired -- what portfolixir.securities.update sends -- to
  # take the security out of the three catalog-hygiene sets, journaled under
  # my token,
  # so that tidying sold-out securities clears the lists I work and the audit
  # trail says which credential did it.
  #
  # Acceptance criteria:
  # - PATCH {is_retired: true} answers 200, the detail read shows it, and the
  #   journal holds the update under the token's actor type and name.
  # - With every not-held member of stale_quote retired, stale_quote lists
  #   only the held one, and missing_quote and missing_logo no longer list
  #   the retired ones.
  # - PATCH {is_retired: false} puts a security back in the sets it matches.
  test "retiring the not-held securities over the API leaves only the held one in the sets",
       %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    agent_token = String.duplicate("a", 40)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    today = Date.utc_today()
    world = base_world(name: "Retire Book", cash_name: "Retire Cash", depot_name: "Retire Depot")
    deposit!(world, "1000", Date.add(today, -60))

    held = create_security!(name: "Held Stale AG", ticker: "HST")
    buy!(world, held, quantity: "2", price: "100", date: Date.add(today, -50))
    put_quote!(held, Date.add(today, -30), "101")

    # Sold out, with a quote after its last trade.
    sold = create_security!(name: "Sold Out AG", ticker: "SLD")
    buy!(world, sold, quantity: "1", price: "50", date: Date.add(today, -50))
    sell!(world, sold, quantity: "1", price: "60", date: Date.add(today, -40))
    put_quote!(sold, Date.add(today, -35), "61")

    never = create_security!(name: "Never Priced AG", ticker: "NVP")

    agent = fn ->
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> agent_token)
    end

    set = fn id ->
      agent.()
      |> get("/api/v1/securities?data_quality=#{id}")
      |> json_response(200)
      |> names()
    end

    patch_retired = fn security, retired? ->
      agent.()
      |> patch(
        "/api/v1/securities/#{security.id}",
        Jason.encode!(%{security: %{is_retired: retired?}})
      )
      |> json_response(200)
    end

    assert set.("stale_quote") == ["Held Stale AG", "Never Priced AG", "Sold Out AG"]
    assert set.("missing_quote") == ["Never Priced AG"]
    assert set.("missing_logo") == ["Held Stale AG", "Never Priced AG", "Sold Out AG"]

    assert %{"data" => %{"is_retired" => true}} = patch_retired.(sold, true)
    assert %{"data" => %{"is_retired" => true}} = patch_retired.(never, true)

    assert %{"data" => %{"is_retired" => true}} =
             agent.() |> get("/api/v1/securities/#{sold.id}") |> json_response(200)

    assert [entry | _] =
             Journal.list_entries(
               resource_type: "security",
               operation: :update,
               resource_id: to_string(sold.id)
             )

    assert entry.actor_type == :api_token_rw
    assert entry.actor_label == "mcp"
    assert entry.before["is_retired"] == false
    assert entry.after["is_retired"] == true

    assert set.("stale_quote") == ["Held Stale AG"]
    assert set.("missing_quote") == []
    assert set.("missing_logo") == ["Held Stale AG"]

    assert %{"data" => %{"is_retired" => false}} = patch_retired.(never, false)

    assert set.("stale_quote") == ["Held Stale AG", "Never Priced AG"]
    assert set.("missing_quote") == ["Never Priced AG"]
    assert set.("missing_logo") == ["Held Stale AG", "Never Priced AG"]
  end

  # User story (PR #1102, review finding 2):
  # As the operator's agent paging through a catalog-hygiene set,
  # I want every page but the last to be full,
  # so that a short page means the set has ended, not that retired rows were
  # dropped after the page was cut.
  #
  # Acceptance criteria:
  # - With retired rows sorting first, data_quality=missing_logo&limit=2
  #   answers two active securities, and offset=2 the third.
  test "a paged missing_logo read with retired rows returns full pages", %{conn: conn} do
    for {name, ticker, retired?} <- [
          {"A Retired AG", "ARA", true},
          {"B Retired AG", "BRA", true},
          {"C Active AG", "CAA", false},
          {"D Active AG", "DAA", false},
          {"E Active AG", "EAA", false}
        ] do
      security = create_security!(name: name, ticker: ticker)

      {:ok, _} =
        Catalog.update_security(Portfolixir.Actor.owner_ui(), security, %{is_retired: retired?})
    end

    page = fn query ->
      conn
      |> recycle()
      |> get_json("/api/v1/securities?data_quality=missing_logo&" <> query)
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["name"])
    end

    assert page.("limit=2") == ["C Active AG", "D Active AG"]
    assert page.("limit=2&offset=2") == ["E Active AG"]
  end

  # User story (#1186, Sprint 21 β3):
  # As the operator's agent listing the catalog by a quote metric,
  # I want a metric sort to sort the whole set and the page to be cut after it,
  # so that the first page holds the highest (or lowest) figures, not a name
  # page reordered or name order under a sort I asked for.
  #
  # Acceptance criteria:
  # - The plain list with sort=latest_price&direction=desc&limit=2 answers
  #   the two highest closes (40, 30), offset=2 the next two (20, 10) and
  #   offset=4 the security with no quote, which sorts last either way; asc
  #   walks the closes up (10, 20, then 30, 40, then the unpriced one).
  # - data_quality=missing_logo, a set paged in its query, walks the same
  #   pages: it, too, pages after the metric sort.
  # - A delta read (since=) under the same metric sort keeps its change order
  #   (oldest change first) and its page, on both: limit=2&offset=2 answers
  #   the third and fourth created (C, D), not the metric's (D, B) nor the
  #   first page again (A, B), which a page dropped before the read would.
  test "a metric sort sorts the whole set and pages after it", %{conn: conn} do
    today = Date.utc_today()

    for {name, ticker, close} <- [
          {"A Alpha AG", "AAL", "30"},
          {"B Beta AG", "BBE", "10"},
          {"C Gamma AG", "CGA", "40"},
          {"D Delta AG", "DDE", "20"}
        ] do
      security = create_security!(name: name, ticker: ticker)
      put_quote!(security, Date.add(today, -1), close)
    end

    _unpriced = create_security!(name: "E Unpriced AG", ticker: "EUN")

    page = fn query ->
      conn
      |> recycle()
      |> get_json("/api/v1/securities?" <> query)
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["name"])
    end

    for set <- ["", "data_quality=missing_logo&"] do
      desc = set <> "sort=latest_price&direction=desc&limit=2"
      asc = set <> "sort=latest_price&direction=asc&limit=2"

      assert page.(desc) == ["C Gamma AG", "A Alpha AG"], desc
      assert page.(desc <> "&offset=2") == ["D Delta AG", "B Beta AG"], desc
      assert page.(desc <> "&offset=4") == ["E Unpriced AG"], desc

      assert page.(asc) == ["B Beta AG", "D Delta AG"], asc
      assert page.(asc <> "&offset=2") == ["A Alpha AG", "C Gamma AG"], asc
      assert page.(asc <> "&offset=4") == ["E Unpriced AG"], asc

      delta = set <> "since=2000-01-01T00:00:00Z&sort=latest_price&direction=desc"
      assert page.(delta <> "&limit=2&offset=2") == ["C Gamma AG", "D Delta AG"], delta
    end
  end

  # User story (#1113):
  # As the operator's agent paging through a data-quality set whose rule is
  # read off the quotes,
  # I want every page but the last to be full,
  # so that a short or empty page means the set has ended, not that the page
  # was cut from the whole catalog before the rule ran.
  #
  # Acceptance criteria:
  # - With fresh securities sorting first, data_quality=stale_quote&limit=2
  #   answers the first two stale ones, offset=2 the third, offset=3 none.
  # - missing_quote and missing_fx page the same way, after their rule.
  test "a paged data-quality read filters before it pages", %{conn: conn} do
    today = Date.utc_today()

    for {name, ticker} <- [{"A Fresh AG", "AFR"}, {"B Fresh AG", "BFR"}, {"C Fresh AG", "CFR"}] do
      security = create_security!(name: name, ticker: ticker)
      put_quote!(security, Date.add(today, -1), "10")
    end

    for {name, ticker} <- [{"D Stale AG", "DST"}, {"E Stale AG", "EST"}] do
      security = create_security!(name: name, ticker: ticker)
      put_quote!(security, Date.add(today, -30), "10")
    end

    _f = create_security!(name: "F Unpriced AG", ticker: "FUN")

    for {name, ticker} <- [{"G Rateless Inc", "GRL"}, {"H Rateless Inc", "HRL"}] do
      security = create_security!(name: name, ticker: ticker, currency: "ZAR")
      put_quote!(security, Date.add(today, -1), "10")
    end

    page = fn query ->
      conn
      |> recycle()
      |> get_json("/api/v1/securities?" <> query)
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["name"])
    end

    assert page.("data_quality=stale_quote&limit=2") == ["D Stale AG", "E Stale AG"]
    assert page.("data_quality=stale_quote&limit=2&offset=2") == ["F Unpriced AG"]
    assert page.("data_quality=stale_quote&limit=2&offset=3") == []
    assert page.("data_quality=missing_quote&limit=1") == ["F Unpriced AG"]
    assert page.("data_quality=missing_fx&limit=1") == ["G Rateless Inc"]
    assert page.("data_quality=missing_fx&limit=1&offset=1") == ["H Rateless Inc"]
  end

  # User story (#1103, answered by the Sprint 20 decision pass):
  # As the operator's agent that retired securities in bulk,
  # I want to list the retired ones, or leave them out, as I can the
  # benchmarks,
  # so that I find a security I retired to restore it without reading the
  # whole catalog and filtering it myself.
  #
  # Acceptance criteria:
  # - is_retired=true lists only the retired securities, false only the
  #   others; blank counts as absent; any other value is a 422 naming it.
  # - It composes with is_benchmark, query and paging.
  # - A catalog-hygiene data_quality set still leaves a retired security
  #   out: beside is_retired=true it matches nothing, as two narrowings do,
  #   where the predicate's own exclusion used to replace the caller's (the
  #   same holds for is_benchmark=true). The predicate is never widened.
  test "the securities listing filters on is_retired", %{conn: conn} do
    for {name, ticker, retired?, benchmark?} <- [
          {"Retired Alpha AG", "RAA", true, false},
          {"Retired Beta AG", "RBA", true, false},
          {"Retired Index", "RIX", true, true},
          {"Active Gamma AG", "AGA", false, false}
        ] do
      security = create_security!(name: name, ticker: ticker)

      {:ok, _} =
        Catalog.update_security(Portfolixir.Actor.owner_ui(), security, %{
          is_retired: retired?,
          is_benchmark: benchmark?
        })
    end

    list = fn query ->
      conn
      |> recycle()
      |> get_json("/api/v1/securities?" <> query)
      |> json_response(200)
      |> names()
    end

    assert list.("is_retired=true") == ["Retired Alpha AG", "Retired Beta AG", "Retired Index"]
    assert list.("is_retired=false") == ["Active Gamma AG"]

    assert list.("is_retired=") ==
             ["Active Gamma AG", "Retired Alpha AG", "Retired Beta AG", "Retired Index"]

    assert list.("is_retired=true&is_benchmark=false") == ["Retired Alpha AG", "Retired Beta AG"]
    assert list.("is_retired=true&query=Beta") == ["Retired Beta AG"]
    assert list.("is_retired=true&limit=1&offset=1") == ["Retired Beta AG"]

    # missing_logo leaves a retired security out in the query; asking for
    # the retired ones does not widen it.
    assert list.("data_quality=missing_logo&is_retired=true") == []
    assert list.("data_quality=missing_logo&is_retired=false") == ["Active Gamma AG"]
    assert list.("data_quality=missing_logo&is_benchmark=true") == []
    assert list.("data_quality=stale_quote&is_retired=true") == []

    for value <- ["yes", "1", "TRUE"] do
      assert conn
             |> recycle()
             |> get_json("/api/v1/securities?is_retired=#{value}")
             |> json_response(422) == %{"errors" => %{"is_retired" => ["is invalid"]}}
    end
  end

  # --- Sprint 28 Q3 begin ---
  # User story (#1415, Sprint 28 Q3; the AGENTS.md metric rule):
  # As the agent working the catalog,
  # I want `data_quality=currency_mismatch` to list the securities whose
  # provider stated another currency, each with what was stated and when,
  # and the rule beside them,
  # so that I read the same set the Overview counts and can check it.
  #
  # Acceptance criteria:
  # - The listing holds the security whose stored provider currency differs
  #   from its own, not the one whose provider stated its own currency.
  # - The envelope adds findings (security_id, currency_code,
  #   provider_currency, provider_currency_at as ISO 8601 UTC) and
  #   computation_basis naming provider_currency and provider_currency_at.
  test "data_quality=currency_mismatch lists the set with its findings and basis",
       %{conn: conn} do
    read_at = ~U[2026-11-09 08:15:00Z]
    dollar = create_security!(name: "Dollar Line", ticker: "DLN")
    own = create_security!(name: "Own Line", ticker: "OWN")

    {:ok, _} =
      Catalog.put_provider_currency(
        Portfolixir.Actor.system_job("quote_sync"),
        dollar,
        "USD",
        read_at
      )

    {:ok, _} =
      Catalog.put_provider_currency(
        Portfolixir.Actor.system_job("quote_sync"),
        own,
        own.currency_code,
        read_at
      )

    response =
      get_json(conn, "/api/v1/securities?data_quality=currency_mismatch") |> json_response(200)

    assert names(response) == ["Dollar Line"]

    assert response["findings"] == [
             %{
               "security_id" => dollar.id,
               "currency_code" => dollar.currency_code,
               "provider_currency" => "USD",
               "provider_currency_at" => "2026-11-09T08:15:00Z"
             }
           ]

    basis = response["computation_basis"]
    assert basis["input_series"] =~ "provider_currency_at"
    assert basis["reference"] =~ "currency_code"
    assert basis["gaps"] =~ "not yet known"

    assert Map.keys(basis) |> Enum.sort() ==
             ~w(assumptions gaps input_series reference threshold window)
  end

  # --- Sprint 28 Q3 end ---
end
