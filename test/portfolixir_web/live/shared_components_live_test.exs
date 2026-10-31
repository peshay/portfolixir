defmodule PortfolixirWeb.SharedComponentsLiveTest do
  # Sprint 21 γ8, board ux-design-2026-10-09/08-shared-copy: the shared
  # components and copy, as the pages render them. The stylesheet rules these
  # structures carry are pinned in
  # `test/invariants/css_shared_components_test.exs`.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

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
end
