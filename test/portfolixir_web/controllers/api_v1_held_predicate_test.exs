defmodule PortfolixirWeb.ApiV1HeldPredicateTest do
  @moduledoc """
  #839 over the JSON API: the reads an agent uses to ask "is it held?" answer
  a depot transferred in the way the ledger's positions do.
  """
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp deliver!(world, security, type) do
    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: type,
        date: ~D[2026-01-05],
        quantity: "5",
        currency_code: "EUR"
      })
  end

  # User story (#839):
  # As the operator's agent reading a portfolio that arrived by depot
  # transfer,
  # I want the held filters of the securities list and the research log to
  # count what was delivered in,
  # so that a transferred-in position is reviewed and listed like a bought one.
  #
  # Acceptance criteria:
  # - GET /securities?holding_status=held lists a security received only by
  #   an inbound delivery, and not one delivered out in full;
  #   holding_status=not_held is the complement.
  # - GET /notes/unreviewed lists the delivered-in security and not the
  #   emptied one, and its basis names the quantity-moving kinds.
  test "a transferred-in position is held on every held filter", %{conn: conn} do
    world = base_world()
    delivered = create_security!(name: "Delivered Co", ticker: "DLV")
    emptied = create_security!(name: "Emptied Co", ticker: "EMP")

    deliver!(world, delivered, "inbound_delivery")
    deliver!(world, emptied, "inbound_delivery")
    deliver!(world, emptied, "outbound_delivery")

    held_ids = fn status ->
      conn
      |> get("/api/v1/securities?holding_status=#{status}")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["id"])
    end

    assert held_ids.("held") == [delivered.id]
    assert held_ids.("not_held") == [emptied.id]

    unreviewed =
      conn |> get("/api/v1/notes/unreviewed") |> json_response(200) |> Map.fetch!("data")

    assert Enum.map(unreviewed["positions"], & &1["security_id"]) == [delivered.id]
    assert unreviewed["basis"] =~ "inbound_delivery"
    refute unreviewed["basis"] =~ "buy/sell"
  end
end
