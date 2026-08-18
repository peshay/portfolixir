defmodule PortfolixirWeb.ApiV1DataQualityTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality

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

    {:ok, _} =
      Catalog.update_security(Actor.owner_ui(), fresh, %{
        attributes: Map.put(fresh.attributes || %{}, "logo_path", "/logos/frs.png")
      })

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

  test "it composes with the listing's other narrowings", %{conn: conn} do
    seed()

    assert names(
             get_json(conn, "/api/v1/securities?data_quality=stale_quote&query=Unpriced")
             |> json_response(200)
           ) == ["Unpriced AG"]
  end
end
