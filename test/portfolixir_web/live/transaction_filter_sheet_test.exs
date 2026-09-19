defmodule PortfolixirWeb.TransactionFilterSheetTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  # User story (#816; the reason of #800's review pick C4-B, applied to the
  # surface that has the same chip row):
  # As a local portfolio maintainer reading the transaction history on a
  # 390 px phone,
  # I want the account, type and changed-since families behind one "Filter (n)"
  # control that opens a bottom sheet,
  # so that the first booking is above the fold instead of below eight lines
  # of chips.
  #
  # Acceptance criteria:
  # - A Filter control with aria-haspopup="dialog" opens a native dialog (the
  #   ModalDialog hook: showModal, Esc, focus return) carrying the three
  #   families and the "More filters" form; the desktop chip row keeps its id
  #   and its behaviour.
  # - A chip in the sheet applies at once and the control counts the active
  #   chips; Reset clears every family; Done closes the sheet.
  # - Above 560 px the control is hidden and the chip row is unchanged
  #   (pinned in css_layout_sweep_test.exs).

  setup do
    world = base_world(name: "Filter World", cash_name: "FW Cash", depot_name: "FW Depot")
    security = create_security!(name: "Filter Co", ticker: "FLT")
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "1", price: "100", date: ~D[2026-01-05])

    %{world: world, security: security}
  end

  test "the chip families sit behind a Filter control that opens a dialog", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions")

    toggle = view |> element("#transaction-filter-sheet-toggle") |> render()
    assert toggle =~ ~s(aria-haspopup="dialog")
    assert toggle =~ ~s(aria-expanded="false")
    refute toggle =~ "filter-sheet-count"
    refute has_element?(view, "#transaction-filter-sheet")

    view |> element("#transaction-filter-sheet-toggle") |> render_click()

    assert has_element?(
             view,
             ~s(dialog#transaction-filter-sheet[phx-hook="ModalDialog"][data-close-event="close_filter_sheet"])
           )

    sheet = view |> element("#transaction-filter-sheet") |> render()

    for family <- ["Account", "Type", "Changed since", "More filters"] do
      assert sheet =~ family, "family #{family} missing from the sheet"
    end

    assert has_element?(view, "#transaction-filter-sheet #sheet-chip-type-buy")
    assert has_element?(view, "#transaction-filter-sheet #sheet-changed-since-chips-today")

    assert view |> element("#transaction-filter-sheet-toggle") |> render() =~
             ~s(aria-expanded="true")

    # The desktop row is unchanged and keeps its own ids.
    assert has_element?(view, "#transaction-chips #tx-chip-type-buy")

    # A chip in the sheet applies at once; the control counts it.
    view |> element("#sheet-chip-type-buy") |> render_click()
    assert has_element?(view, "#transaction-filter-sheet")
    assert view |> element("#sheet-chip-type-buy") |> render() =~ ~s(aria-pressed="true")

    assert has_element?(
             view,
             "#transaction-filter-sheet-toggle [data-role='filter-sheet-count']",
             "1"
           )

    # Reset clears every family.
    view |> element("#transaction-filter-sheet-reset") |> render_click()
    refute has_element?(view, "[data-role='filter-sheet-count']")
    assert view |> element("#sheet-chip-type-buy") |> render() =~ ~s(aria-pressed="false")

    # Done closes the sheet.
    view |> element("#transaction-filter-sheet-done") |> render_click()
    refute has_element?(view, "#transaction-filter-sheet")

    assert view |> element("#transaction-filter-sheet-toggle") |> render() =~
             ~s(aria-expanded="false")
  end

  test "the hook's close event closes the sheet", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions")

    view |> element("#transaction-filter-sheet-toggle") |> render_click()
    render_hook(view, "close_filter_sheet", %{})
    refute has_element?(view, "#transaction-filter-sheet")
  end

  test "the sheet is German where the page is", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    view |> element("#transaction-filter-sheet-toggle") |> render_click()
    sheet = view |> element("#transaction-filter-sheet") |> render()

    for family <- ["Konto", "Typ", "Geändert seit"] do
      assert sheet =~ family, "family #{family} missing from the German sheet"
    end

    assert has_element?(view, "#transaction-filter-sheet-reset", "Zurücksetzen")
    assert has_element?(view, "#transaction-filter-sheet-done", "Fertig")
  end
end
