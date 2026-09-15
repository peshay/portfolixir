defmodule PortfolixirWeb.ApiV1BenchmarkFlagTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp create!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{currency_code: "EUR", asset_class: "etf"}, attrs)
      )

    security
  end

  # User story (#572, ADR-0046 §4 — the agent's half of the flag):
  # As the operating agent,
  # I want to list benchmark securities through the existing securities read
  # with an is_benchmark filter, read the flag in the full projection and set
  # it on create and update,
  # so that a benchmark is discoverable and manageable without a new resource.
  #
  # Acceptance criteria:
  # - is_benchmark=true lists only flagged securities, is_benchmark=false
  #   excludes them, a malformed value is a 422 naming the field.
  # - The flag is a field of the full projection and of fields=.
  # - POST and PATCH accept the flag.
  test "the securities read filters by the flag and the writes set it", %{conn: conn} do
    bench = create!(%{name: "World Index ETF", ticker_symbol: "WRLD", is_benchmark: true})
    plain = create!(%{name: "Plain Co", ticker_symbol: "PLN"})

    %{"data" => only} = conn |> get("/api/v1/securities?is_benchmark=true") |> json_response(200)
    assert Enum.map(only, & &1["id"]) == [bench.id]

    %{"data" => rest} = conn |> get("/api/v1/securities?is_benchmark=false") |> json_response(200)
    assert plain.id in Enum.map(rest, & &1["id"])
    refute bench.id in Enum.map(rest, & &1["id"])

    # A blank filter is no filter: both are listed.
    %{"data" => all} = conn |> get("/api/v1/securities?is_benchmark=") |> json_response(200)
    assert bench.id in Enum.map(all, & &1["id"])
    assert plain.id in Enum.map(all, & &1["id"])

    assert %{"errors" => %{"is_benchmark" => [_ | _]}} =
             conn |> get("/api/v1/securities?is_benchmark=maybe") |> json_response(422)

    %{"data" => [sparse]} =
      conn
      |> get("/api/v1/securities?is_benchmark=true&fields=id,is_benchmark")
      |> json_response(200)

    assert sparse == %{"id" => bench.id, "is_benchmark" => true}

    %{"data" => full} = conn |> get("/api/v1/securities/#{bench.id}") |> json_response(200)
    assert full["is_benchmark"] == true

    %{"data" => created} =
      conn
      |> post("/api/v1/securities", %{
        "security" => %{
          "name" => "Bond Index ETF",
          "ticker_symbol" => "BNDX",
          "currency_code" => "EUR",
          "asset_class" => "etf",
          "is_benchmark" => true
        }
      })
      |> json_response(201)

    assert created["is_benchmark"] == true

    %{"data" => updated} =
      conn
      |> patch("/api/v1/securities/#{created["id"]}", %{"security" => %{"is_benchmark" => false}})
      |> json_response(200)

    assert updated["is_benchmark"] == false
  end
end
