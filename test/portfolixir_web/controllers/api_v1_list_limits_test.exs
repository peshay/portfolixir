defmodule PortfolixirWeb.ApiV1ListLimitsTest do
  # Issue #771: every list read has a default and a maximum row count, and
  # the quote upsert a row cap, so one authenticated call cannot ask the
  # instance to materialise an unbounded table.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Catalog.Quotes
  alias PortfolixirWeb.Api.V1.ListLimit

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story:
  # As the operator whose agent reads lists over the API,
  # I want a missing limit to mean a generous default and an oversized limit to be capped,
  # so that a routine read never changes and a hostile one is bounded.
  #
  # Acceptance criteria:
  # - Absent or blank: the default. An integer or numeric string: itself, capped at the maximum.
  # - Zero, negative, non-numeric: an error naming the field.
  test "parses, defaults and caps the limit parameter" do
    assert ListLimit.parse(%{}, 100, 1_000) == {:ok, 100}
    assert ListLimit.parse(%{"limit" => ""}, 100, 1_000) == {:ok, 100}
    assert ListLimit.parse(%{"limit" => "50"}, 100, 1_000) == {:ok, 50}
    assert ListLimit.parse(%{"limit" => 50}, 100, 1_000) == {:ok, 50}
    assert ListLimit.parse(%{"limit" => "999999"}, 100, 1_000) == {:ok, 1_000}
    assert ListLimit.parse(%{"limit" => "0"}, 100, 1_000) == {:error, :limit}
    assert ListLimit.parse(%{"limit" => "-5"}, 100, 1_000) == {:error, :limit}
    assert ListLimit.parse(%{"limit" => "abc"}, 100, 1_000) == {:error, :limit}
    assert ListLimit.parse(%{"limit" => [1]}, 100, 1_000) == {:error, :limit}
  end

  test "the four list reads refuse a malformed limit", %{conn: conn} do
    security = create_security!(name: "Limit Co", ticker: "LIM")

    for path <- [
          "/api/v1/transactions?limit=abc",
          "/api/v1/securities?limit=0",
          "/api/v1/exchange_rates?limit=-1",
          "/api/v1/securities/#{security.id}/quotes?limit=x"
        ] do
      response = conn |> get(path) |> json_response(422)
      assert %{"errors" => %{"limit" => [_ | _]}} = response, path
    end
  end

  test "a quote limit keeps the newest rows of the window, ascending", %{conn: conn} do
    security = create_security!(name: "Newest Co", ticker: "NEW")

    rows =
      for day <- 1..5,
          do: %{date: Date.new!(2026, 1, day), close: Decimal.new("1#{day}"), source: "manual"}

    assert {:ok, 5} = Quotes.upsert_many(security.id, rows)

    %{"data" => data} =
      conn |> get("/api/v1/securities/#{security.id}/quotes?limit=2") |> json_response(200)

    assert Enum.map(data, & &1["date"]) == ["2026-01-04", "2026-01-05"]
  end

  test "the four list reads accept a limit and answer as before", %{conn: conn} do
    security = create_security!(name: "Limit Co", ticker: "LIM")

    for path <- [
          "/api/v1/transactions?limit=10",
          "/api/v1/securities?limit=10",
          "/api/v1/exchange_rates?limit=10",
          "/api/v1/securities/#{security.id}/quotes?limit=10"
        ] do
      assert %{"data" => data} = conn |> get(path) |> json_response(200), path
      assert is_list(data)
    end
  end

  # User story:
  # As the operator,
  # I want a quote upsert refused past a row cap,
  # so that one request cannot carry an unbounded number of rows.
  #
  # Acceptance criteria:
  # - More rows than the cap answer 422 naming the cap; nothing is written.
  test "the quote upsert refuses more rows than the cap", %{conn: conn} do
    security = create_security!(name: "Cap Co", ticker: "CAP")
    cap = ListLimit.quote_upsert_max_rows()

    rows =
      for i <- 1..(cap + 1) do
        %{"date" => Date.to_iso8601(Date.add(~D[2000-01-01], i)), "close" => "1.00"}
      end

    response =
      conn
      |> put("/api/v1/securities/#{security.id}/quotes", %{"quotes" => rows})
      |> json_response(422)

    assert %{"errors" => %{"quotes" => [message]}} = response
    assert message =~ Integer.to_string(cap)
    assert Quotes.range(security.id, ~D[1990-01-01], ~D[2100-01-01]) == []
  end
end
