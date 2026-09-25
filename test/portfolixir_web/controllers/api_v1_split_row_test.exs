defmodule PortfolixirWeb.ApiV1SplitRowTest do
  # E25 S6 (#891), G07: PATCH /api/v1/transactions/:id (and the MCP tool
  # that calls it) changes only the note of a stored split row; its date,
  # security, portfolio, type and ratio are refused with a 422 naming the
  # field and delete-and-rebook.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  setup %{conn: conn} do
    world = base_world(name: "API Split Row World")
    security = create_security!(name: "API Split Row Co", ticker: "ASR")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    {:ok, [split]} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-02-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, split: split}
  end

  defp patch_split(conn, split, attrs) do
    patch(conn, "/api/v1/transactions/#{split.id}", Jason.encode!(%{"transaction" => attrs}))
  end

  # User story:
  # As the agent correcting a booked split over the API,
  # I want a change to its date or ratio refused with the way to correct it,
  # so that I delete and rebook it through the split flow instead of moving
  # it past the checks that booked it.
  #
  # Acceptance criteria:
  # - A PATCH of the date or the ratio answers 422 naming the field and
  #   stores nothing; a PATCH of the notes answers 200.
  test "a split row's date and ratio answer 422, its note updates", %{conn: conn, split: split} do
    errors =
      conn
      |> patch_split(split, %{"date" => "2026-01-20"})
      |> json_response(422)
      |> Map.fetch!("errors")

    assert [message] = errors["date"]
    assert message =~ "POST /api/v1/splits"

    errors =
      conn
      |> patch_split(split, %{"split_ratio_numerator" => 3})
      |> json_response(422)
      |> Map.fetch!("errors")

    assert [_message] = errors["split_ratio_numerator"]
    assert Ledger.get_transaction(split.id).date == ~D[2026-02-01]

    assert %{"data" => %{"notes" => "per the statement"}} =
             conn
             |> patch_split(split, %{"notes" => "per the statement"})
             |> json_response(200)
  end
end
