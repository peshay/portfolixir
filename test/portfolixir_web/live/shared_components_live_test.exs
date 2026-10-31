defmodule PortfolixirWeb.SharedComponentsLiveTest do
  # Sprint 21 γ8, board ux-design-2026-10-09/08-shared-copy: the shared
  # components and copy, as the pages render them. The stylesheet rules these
  # structures carry are pinned in
  # `test/invariants/css_shared_components_test.exs`.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.WorldFixtures

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        provider: "manual",
        asset_class: "equity"
      })

    security
  end

  # User story (#1138, Sprint 21 γ8; board 08, "#1138"):
  # As the operator closing the Manage-logo dialog with the keyboard,
  # I want its last button to stand inside the dialog's padding,
  # so that "Logo entfernen" does not touch the dialog's edge and its focus
  # ring is not cut by the dialog's overflow.
  #
  # Acceptance criteria:
  # - The logo dialog's footer is the dialog's own child, not a band: the
  #   structure the rule `.modal > .modal-footer:not(.modal-footer--band)`
  #   pads, with "Remove logo" its last button.
  test "the logo dialog's footer is the dialog's own child, the rule's structure", %{conn: conn} do
    security = security!("Wrenfield Gardens AG")
    {:ok, view, _html} = live(conn, "/securities")
    render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(security.id)})

    assert has_element?(view, "dialog#logo-override-dialog.modal > .modal-footer")
    refute has_element?(view, "dialog#logo-override-dialog .modal-footer--band")

    assert has_element?(
             view,
             "dialog#logo-override-dialog > .modal-footer > button:last-child[phx-click='remove_logo_override']"
           )
  end

  # User story (#1160, Sprint 21 γ8; board 08, "#1160"):
  # As the operator opening Accounts, Securities or Snapshots,
  # I want the result slot to take no room before any action,
  # so that the block below it starts where the page draws it.
  #
  # Acceptance criteria:
  # - Each slot is an inline result whose regions hold no element at rest.
  # - Accounts' slot is a direct child of its section's grid, the structure
  #   whose empty slot the stylesheet takes out of the flow.
  test "the remaining result slots are empty at rest", %{conn: conn} do
    {:ok, accounts, _html} = live(conn, "/portfolios")

    assert has_element?(
             accounts,
             "#accounts-panel.workspace-section > #accounts-result.inline-result"
           )

    refute has_element?(accounts, "#accounts-result .inline-result__region > *")

    {:ok, securities, _html} = live(conn, "/securities")
    assert has_element?(securities, "#securities-action-result.inline-result")
    refute has_element?(securities, "#securities-action-result .inline-result__region > *")

    WorldFixtures.base_world(name: "Shared", currency: "EUR")
    {:ok, snapshots, _html} = live(conn, "/snapshots")
    assert has_element?(snapshots, "#snapshots-action-result.inline-result")
    refute has_element?(snapshots, "#snapshots-action-result .inline-result__region > *")
  end
end
