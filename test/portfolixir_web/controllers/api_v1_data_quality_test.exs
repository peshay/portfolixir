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

  # User story (#1101, Sprint 20 plan D-7; contract entry 16):
  # As the LLM agent the operator runs,
  # I want to ask for the held securities whose quotes contradict their own
  # bookings, with the booking each one contradicts and the rule,
  # so that I can work the set the Overview counts and Wealth names, and
  # check each finding without a second read.
  #
  # Acceptance criteria:
  # - data_quality=implausible_quote answers the held "Wrenfield Gardens
  #   AG" (bought 48.20, quoted 4.87 that day) and nothing of the seed.
  # - The envelope's findings name its booking exactly: security_id, kind
  #   "buy", date "2026-05-12", price "48.2", currency_code "EUR",
  #   quote_date "2026-05-12", close "4.87", ratio "0.101037" (4.87 / 48.20
  #   at scale 6, half up), bookings_outside 1.
  # - The envelope's computation_basis states input_series, reference,
  #   window, gaps and threshold (the AGENTS.md metric rule); another
  #   data_quality carries neither key.
  test "data_quality=implausible_quote lists the held set with its findings and basis",
       %{conn: conn} do
    seed()
    world = base_world([])
    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    buy!(world, wrenfield, quantity: "120", price: "48.20", date: ~D[2026-05-12])
    put_quote!(wrenfield, ~D[2026-05-12], "4.87")

    response =
      get_json(conn, "/api/v1/securities?data_quality=implausible_quote") |> json_response(200)

    assert names(response) == ["Wrenfield Gardens AG"]

    assert response["findings"] == [
             %{
               "security_id" => wrenfield.id,
               "kind" => "buy",
               "date" => "2026-05-12",
               "price" => "48.2",
               "currency_code" => "EUR",
               "quote_date" => "2026-05-12",
               "close" => "4.87",
               "ratio" => "0.101037",
               "bookings_outside" => 1
             }
           ]

    basis = response["computation_basis"]

    assert Map.keys(basis) |> Enum.sort() ==
             ~w(assumptions gaps input_series reference threshold window)

    assert basis["window"] =~ "within 7 days before the booking date"
    assert basis["threshold"] =~ "below 1/2 or above 2"

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
end
