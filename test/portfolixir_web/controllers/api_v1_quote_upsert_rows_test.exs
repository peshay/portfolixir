defmodule PortfolixirWeb.ApiV1QuoteUpsertRowsTest do
  # E25 S4, F13 (#889): a quote upsert with two rows for one date, or a row
  # that is not an object, raised in the database layer and answered 500.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Repo

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, security: create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")}
  end

  defp row(date, close), do: %{"date" => date, "close" => close, "source" => "manual"}

  # User story:
  # As the operator's agent writing a quote history,
  # I want a batch that names one date twice, or carries a row that is not a
  # quote object, refused as a whole with the reason,
  # so that I fix the batch instead of meeting a server error.
  #
  # Acceptance criteria:
  # - Two rows for one date answer 422 with an error on date naming that
  #   date, and store nothing.
  # - A row that is not an object answers 422 on quotes and stores nothing.
  test "a repeated date or a non-object row answers 422 and stores nothing",
       %{conn: conn, security: security} do
    path = "/api/v1/securities/#{security.id}/quotes"

    body =
      conn
      |> put(path, %{
        "quotes" => [row("2026-01-02", "10"), row("2026-01-05", "11"), row("2026-01-02", "12")]
      })
      |> json_response(422)

    assert [message] = body["errors"]["date"]
    assert message =~ "2026-01-02"

    for not_a_row <- ["2026-01-02", 10, nil, ["2026-01-02", "10"]] do
      body =
        conn
        |> put(path, %{"quotes" => [row("2026-01-06", "10"), not_a_row]})
        |> json_response(422)

      assert Map.has_key?(body["errors"], "quotes"), inspect(not_a_row)
    end

    assert Repo.aggregate(Quote, :count) == 0

    assert %{"data" => %{"upserted" => 2}} =
             conn
             |> put(path, %{"quotes" => [row("2026-01-02", "10"), row("2026-01-05", "11")]})
             |> json_response(200)
  end
end
