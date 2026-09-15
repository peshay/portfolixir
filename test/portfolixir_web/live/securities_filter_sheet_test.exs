defmodule PortfolixirWeb.SecuritiesFilterSheetTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

  # User story (#800, review C4 — variant B, picked 2026-09-14):
  # As a local portfolio maintainer filtering the securities list on the
  # phone,
  # I want the chip families behind one "Filter (n)" control that opens a
  # bottom sheet — the families stacked, the control carrying the count of
  # active chips, focus moved into the sheet and returned —
  # so that the list starts right under the search and every chip stays
  # reachable by keyboard.
  #
  # Acceptance criteria:
  # - A Filter control with aria-haspopup="dialog" opens a native dialog
  #   (the ModalDialog hook: showModal, Esc, focus return) carrying the
  #   holding, data-quality, asset-class and changed-since families and the
  #   builder toggle; the desktop chip row keeps its ids and behaviour.
  # - A chip in the sheet applies at once (the URL patch the row chips make)
  #   and the control counts the active chips; Reset clears every family;
  #   Done closes the sheet.
  # - Above 560 px the sheet control is hidden and the D2 chip row is
  #   unchanged (pinned in css_layout_sweep_test.exs).

  setup do
    {:ok, _} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Apple Inc.",
        ticker_symbol: "AAPL",
        currency_code: "USD",
        asset_class: "equity"
      })

    {:ok, _} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Bitcoin",
        ticker_symbol: "BTC",
        currency_code: "EUR",
        asset_class: "crypto"
      })

    :ok
  end

  test "the chip families sit behind a Filter control that opens a dialog", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    toggle = view |> element("#filter-sheet-toggle") |> render()
    assert toggle =~ ~s(aria-haspopup="dialog")
    assert toggle =~ ~s(aria-expanded="false")
    refute toggle =~ "filter-sheet-count"
    refute has_element?(view, "#securities-filter-sheet")

    view |> element("#filter-sheet-toggle") |> render_click()

    assert has_element?(
             view,
             ~s(dialog#securities-filter-sheet[phx-hook="ModalDialog"][data-close-event="close_filter_sheet"])
           )

    sheet = view |> element("#securities-filter-sheet") |> render()

    for family <- ["Holding", "Data quality", "Currency", "Asset class", "Changed since"] do
      assert sheet =~ family, "family #{family} missing from the sheet"
    end

    assert has_element?(view, "#securities-filter-sheet #sheet-chip-held")
    assert has_element?(view, "#securities-filter-sheet #sheet-chip-unclassified")
    assert has_element?(view, "#securities-filter-sheet #sheet-chip-stale_quote")
    assert has_element?(view, "#securities-filter-sheet #sheet-chip-cur-USD")
    assert has_element?(view, "#securities-filter-sheet #sheet-chip-class-crypto")
    assert has_element?(view, "#securities-filter-sheet #sheet-changed-since-chips-today")
    assert has_element?(view, "#securities-filter-sheet #sheet-more-filters-toggle")
    assert view |> element("#filter-sheet-toggle") |> render() =~ ~s(aria-expanded="true")

    # The desktop row is unchanged.
    assert has_element?(view, "#securities-filter-chips #sec-chip-held")
    assert has_element?(view, "#securities-filter-chips #more-filters-toggle")

    # A chip in the sheet applies at once; the control counts it.
    view |> element("#sheet-chip-held") |> render_click()
    assert_patch(view, "/securities?holding=held")
    assert has_element?(view, "#securities-filter-sheet")
    assert view |> element("#sheet-chip-held") |> render() =~ ~s(aria-pressed="true")
    assert has_element?(view, "#filter-sheet-toggle [data-role='filter-sheet-count']", "1")

    view |> element("#sheet-chip-class-crypto") |> render_click()
    assert has_element?(view, "#filter-sheet-toggle [data-role='filter-sheet-count']", "2")

    # Reset clears every family.
    view |> element("#filter-sheet-reset") |> render_click()
    assert_patch(view, "/securities")
    refute has_element?(view, "[data-role='filter-sheet-count']")
    assert view |> element("#sheet-chip-held") |> render() =~ ~s(aria-pressed="false")

    # Done closes the sheet.
    view |> element("#filter-sheet-done") |> render_click()
    refute has_element?(view, "#securities-filter-sheet")
    assert view |> element("#filter-sheet-toggle") |> render() =~ ~s(aria-expanded="false")
  end

  test "the builder opens inside the sheet, and the hook's close event closes it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities")

    view |> element("#filter-sheet-toggle") |> render_click()
    view |> element("#sheet-more-filters-toggle") |> render_click()
    assert has_element?(view, "#securities-filter-sheet #filter-popover")
    # One builder instance: the desktop container does not render it too.
    refute has_element?(view, "#securities-panel > .popover-container #filter-popover")

    # Esc in the dialog pushes the close event named on the dialog.
    render_hook(view, "close_filter_sheet", %{})
    refute has_element?(view, "#securities-filter-sheet")
  end

  test "the sheet is German where the page is", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities?locale=de")

    view |> element("#filter-sheet-toggle") |> render_click()
    sheet = view |> element("#securities-filter-sheet") |> render()

    for family <- ["Bestand", "Datenqualität", "Währung", "Anlageklasse", "Geändert seit"] do
      assert sheet =~ family, "family #{family} missing from the German sheet"
    end

    assert has_element?(view, "#filter-sheet-reset", "Zurücksetzen")
    assert has_element?(view, "#filter-sheet-done", "Fertig")
  end
end
