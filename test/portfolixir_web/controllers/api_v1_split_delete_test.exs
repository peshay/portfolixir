defmodule PortfolixirWeb.ApiV1SplitDeleteTest do
  # Sprint 18 U1 (#912), ADR-0028 §1: DELETE /api/v1/splits/:transaction_id
  # deletes the split event a row belongs to — every portfolio's row in one
  # journaled step — the API half of the write the screen's "Split löschen"
  # runs (risk-tier, ADR-0036; the invariant is pinned in
  # test/portfolixir/ledger/split_delete_test.exs). The MCP tool is
  # portfolixir.splits.delete, in the admin profile.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  setup %{conn: conn} do
    world_a = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")

    world_b =
      base_world(name: "Sparplan-Portfolio", cash_name: "Tagesgeld", depot_name: "Depot 2")

    security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world_a, security, quantity: "40", price: "62.50", date: ~D[2026-09-01])
    buy!(world_b, security, quantity: "12", price: "60", date: ~D[2026-09-02])

    {:ok, rows} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-09-15],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, rows: rows, security: security, buy_world: world_a}
  end

  # User story (U1, #912; ADR-0028 §1):
  # As the agent correcting a split booked with the wrong ratio,
  # I want one call that deletes the split as the one fact it is, from any
  # of its rows,
  # so that I never leave the ledger with the event half deleted between
  # calls, and can book the corrected ratio right after.
  #
  # Acceptance criteria:
  # - DELETE /api/v1/splits/:transaction_id answers 200 with every removed
  #   row in the transaction shape, ordered by portfolio; the ratio parts are
  #   integers and the decimals strings.
  # - No split row of the event remains, each removal is journaled under the
  #   token, and POST /api/v1/splits then books the corrected ratio.
  test "deletes every row of the split a row belongs to", %{conn: conn, rows: rows} do
    [row_a, row_b] = rows

    body = conn |> delete("/api/v1/splits/#{row_b.id}") |> json_response(200)

    assert [first, second] = body["data"]["transactions"]
    assert {first["id"], second["id"]} == {row_a.id, row_b.id}

    for row <- [first, second] do
      assert row["type"] == "split"
      assert row["split_ratio_numerator"] == 2
      assert row["split_ratio_denominator"] == 1
      assert row["fees"] == "0"
    end

    assert Ledger.get_transaction(row_a.id) == nil
    assert Ledger.get_transaction(row_b.id) == nil

    entries = Journal.list_entries(resource_type: "transaction", operation: :delete)
    assert length(entries) == 2
    assert Enum.all?(entries, &(&1.actor_type == :api_token_rw))

    assert %{"data" => %{"transactions" => [_, _]}} =
             conn
             |> post(
               "/api/v1/splits",
               Jason.encode!(%{
                 security_id: row_a.security_id,
                 date: "2026-09-15",
                 ratio_numerator: 3,
                 ratio_denominator: 1
               })
             )
             |> json_response(201)
  end

  # User story (U1, #912; the refusals the confirmation states):
  # As the agent deleting a split by one of its rows,
  # I want an unknown or already deleted row answered 404 and a booking of
  # another kind answered 422 naming the delete that fits it,
  # so that a wrong id never removes another booking.
  #
  # Acceptance criteria:
  # - An id that is unknown, gone or no id answers 404 and deletes nothing.
  # - A booking that is no split answers 422 on transaction_id naming
  #   DELETE /api/v1/transactions/:id, and stays.
  test "answers 404 for a row that is gone and 422 for a booking that is no split", %{
    conn: conn,
    rows: [row_a, row_b],
    security: security,
    buy_world: world
  } do
    assert conn |> delete("/api/v1/splits/999999999") |> json_response(404)
    assert conn |> delete("/api/v1/splits/abc") |> json_response(404)

    {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), row_a)
    assert conn |> delete("/api/v1/splits/#{row_a.id}") |> json_response(404)
    assert Ledger.get_transaction(row_b.id)

    buy = buy!(world, security, quantity: "1", price: "70", date: ~D[2026-09-20])

    assert %{"errors" => %{"transaction_id" => [message]}} =
             conn |> delete("/api/v1/splits/#{buy.id}") |> json_response(422)

    assert message =~ "DELETE /api/v1/transactions/:id"
    assert Ledger.get_transaction(buy.id)
  end

  # User story (U1, #912):
  # As the agent told a split row only changes its note,
  # I want the refusal to name the call that deletes the split whole,
  # so that I do not delete it row by row.
  #
  # Acceptance criteria:
  # - A PATCH of a split row's date answers 422 naming
  #   DELETE /api/v1/splits/:transaction_id and POST /api/v1/splits.
  test "a refused split PATCH names the whole-split delete", %{conn: conn, rows: [row | _]} do
    assert %{"errors" => %{"date" => [message]}} =
             conn
             |> patch(
               "/api/v1/transactions/#{row.id}",
               Jason.encode!(%{"transaction" => %{"date" => "2026-09-10"}})
             )
             |> json_response(422)

    assert message =~ "DELETE /api/v1/splits/:transaction_id"
    assert message =~ "POST /api/v1/splits"
  end
end
