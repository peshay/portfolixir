defmodule PortfolixirWeb.AccountsDeleteConfirmTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.WorldFixtures

  defp owner, do: Actor.owner_ui()

  defp delete_item(view, "cash", id),
    do: element(view, "#cash-row-menu-#{id} [data-role='menu-delete']")

  defp delete_item(view, "depot", id),
    do: element(view, "#account-row-menu-#{id} [data-role='menu-delete']")

  # User story (security review 2026-10-12, H17):
  # As the operator deleting an account from its row menu,
  # I want Delete to ask once whatever the menu saw when it opened,
  # so that an account whose bookings went away while the menu was open is
  # never deleted without the question every destructive click asks.
  #
  # Acceptance criteria:
  # - A menu opened while the account had bookings still asks before Delete,
  #   and its question does not claim the account is free: it says a
  #   referenced account's delete is refused and nothing changes.
  # - When the bookings are gone by the click, the account is deleted after
  #   that question and the page says so.
  test "Delete asks even when the menu opened on a referenced account", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Delete Asks", depot_name: "Depot Muster")

    {:ok, tagesgeld} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: world.portfolio.id,
        name: "Tagesgeld",
        currency_code: "EUR"
      })

    booking =
      WorldFixtures.deposit!(
        %{portfolio: world.portfolio, cash: tagesgeld},
        "100.00",
        ~D[2025-01-02]
      )

    {:ok, view, _html} = live(conn, "/portfolios")
    view |> element("#cash-kebab-#{tagesgeld.id}") |> render_click()

    assert render(delete_item(view, "cash", tagesgeld.id)) =~
             "data-confirm=\"Delete “Tagesgeld”? If the account still has bookings or a linked depot, the deletion is refused and nothing changes.\""

    # The booking goes while the menu is open (another tab, or the agent).
    {:ok, _} = Ledger.delete_transaction(owner(), booking)

    render_click(delete_item(view, "cash", tagesgeld.id))

    refute Portfolios.get_cash_account(tagesgeld.id)
    refute has_element?(view, "#delete-blocked-dialog")

    result =
      view
      |> element("#accounts-result")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()

    assert result =~ "“Tagesgeld” deleted."
  end

  test "a depot's Delete asks with the depot's sentence and still refuses while it has bookings",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Delete Depot", depot_name: "Depot Muster")
    security = WorldFixtures.create_security!(name: "Muster Synthetic AG")
    WorldFixtures.deposit!(world, "1000.00", ~D[2025-01-02])
    WorldFixtures.buy!(world, security, quantity: "1", price: "100", date: ~D[2025-01-03])

    {:ok, view, _html} = live(conn, "/portfolios")
    view |> element("#account-kebab-#{world.depot.id}") |> render_click()

    assert render(delete_item(view, "depot", world.depot.id)) =~
             "data-confirm=\"Delete “Depot Muster”? If the depot still has bookings, the deletion is refused and nothing changes.\""

    render_click(delete_item(view, "depot", world.depot.id))

    assert has_element?(view, "#delete-blocked-dialog")
    assert Portfolios.get_securities_account(world.depot.id)
  end
end
