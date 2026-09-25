defmodule PortfolixirWeb.ApiV1IdentifierShapeTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Repo

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Example AG", currency_code: "EUR", isin: "DE000ACME008"}, attrs)
      )

    security
  end

  # User story (E25 S5, G23):
  # As the operator whose imports match securities by ISIN, WKN and ticker,
  # I want a changed identifier checked against the catalog's rules,
  # so that a lookalike can never replace the identifier my exports carry.
  #
  # Acceptance criteria:
  # - POST /api/v1/securities/:id/isin-change answers 422 on new_isin for a
  #   wrong check digit or a letter from another script, and writes nothing.
  # - PATCH /api/v1/securities/:id answers 422 naming the field for an ISIN
  #   that fails the predicate, a WKN that is not six letters or digits, and
  #   a ticker that is not printable ASCII, and writes nothing.
  # - Resending the stored identifier is no change and is not checked.
  test "a lookalike ISIN change answers 422 and writes nothing", %{conn: conn} do
    security = security!(%{})

    for new_isin <- ["DE000ACME009", "DE000ACM\u0415115", "D\u0415000ACME115"] do
      response =
        conn
        |> api_conn()
        |> post(
          "/api/v1/securities/#{security.id}/isin-change",
          Jason.encode!(%{"isin_change" => %{"new_isin" => new_isin}})
        )
        |> json_response(422)

      assert %{"new_isin" => [_ | _]} = response["errors"], new_isin
    end

    assert Repo.get!(Security, security.id).isin == "DE000ACME008"
  end

  test "a changed identifier that fails the catalog's shape answers 422", %{conn: conn} do
    security = security!(%{wkn: "ACM008", ticker_symbol: "ACME"})

    for {field, value} <- [
          {"isin", "DE000ACME009"},
          {"isin", "D\u0415000ACME008"},
          {"wkn", "ACM08"},
          {"wkn", "ACM\u04150"},
          {"ticker_symbol", "\u0410CME"},
          {"ticker_symbol", "AC\u00A0ME"}
        ] do
      response =
        conn
        |> api_conn()
        |> patch(
          "/api/v1/securities/#{security.id}",
          Jason.encode!(%{"security" => %{field => value}})
        )
        |> json_response(422)

      assert Map.has_key?(response["errors"], field), "#{field} #{value}"
    end

    stored = Repo.get!(Security, security.id)
    assert {stored.isin, stored.wkn, stored.ticker_symbol} == {"DE000ACME008", "ACM008", "ACME"}

    resent =
      conn
      |> api_conn()
      |> patch(
        "/api/v1/securities/#{security.id}",
        Jason.encode!(%{"security" => %{"isin" => "DE000ACME008", "name" => "Renamed AG"}})
      )
      |> json_response(200)

    assert resent["data"]["name"] == "Renamed AG"
  end

  test "a security's name is stored without format characters", %{conn: conn} do
    response =
      conn
      |> api_conn()
      |> post(
        "/api/v1/securities",
        Jason.encode!(%{
          "security" => %{"name" => "Acme\u200B AG\u2060", "currency_code" => "EUR"}
        })
      )
      |> json_response(201)

    assert response["data"]["name"] == "Acme AG"
  end
end
