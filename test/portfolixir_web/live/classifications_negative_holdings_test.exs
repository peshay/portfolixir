defmodule PortfolixirWeb.ClassificationsNegativeHoldingsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # Mounts the LiveView and drains its async holdings load before returning
  # (issue #334 — a test exiting mid-task races the sandbox teardown).
  defp live_drained(conn, path) do
    {:ok, view, html} = live(conn, path)
    render_async(view)
    {:ok, view, html}
  end

  # User story (#570):
  # As a local portfolio maintainer,
  # I want negative-quantity holdings visibly marked in the classification
  # tree instead of blending in,
  # so that import debris from unmodeled corporate actions is recognisable
  # while I sort securities into categories.
  #
  # Acceptance criteria:
  # - The security row in the tree carries a text marker (no colour-only
  #   signal, UX-DR7) when the derived global quantity is negative.
  # - A normally held security carries no marker.
  test "marks securities with a negative derived quantity in the tree", %{conn: conn} do
    world = WorldFixtures.base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    doomed = WorldFixtures.create_security!(name: "Doomed Co.", ticker: "DOOM")
    fine = WorldFixtures.create_security!(name: "Fine Co.", ticker: "FINE")

    WorldFixtures.buy!(world, fine, quantity: "10", price: "5")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: doomed.id,
        type: "outbound_delivery",
        date: ~D[2026-02-02],
        quantity: "500",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    doomed_row = view |> element(~s([data-security-id="#{doomed.id}"])) |> render()
    assert doomed_row =~ ~s(data-role="negative-holding")
    assert doomed_row =~ "negative quantity"

    fine_row = view |> element(~s([data-security-id="#{fine.id}"])) |> render()
    refute fine_row =~ ~s(data-role="negative-holding")
  end
end
