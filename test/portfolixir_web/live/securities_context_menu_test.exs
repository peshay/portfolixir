defmodule PortfolixirWeb.SecuritiesContextMenuTest do
  # User story:
  # As a local portfolio maintainer,
  # I want a context menu on every security row (right-click or kebab on
  # desktop, kebab on mobile) so I can run the standard per-security actions
  # without jumping between toolbar, detail pane and dialog.
  #
  # Acceptance criteria exercised by this test module:
  # - Each row exposes a kebab button that opens the menu.
  # - Right-click (`phx-contextmenu`) opens the same menu.
  # - The menu offers Edit, Sync, Retire/Reactivate, Open detail, Copy ISIN,
  #   Copy ticker, Delete.
  # - Edit dispatches the form dialog directly into the confirm step with the
  #   editing security assigned.
  # - Retire toggles the `is_retired` flag.
  # - Copy emits a `push_event("copy-to-clipboard", %{text: ...})`.
  # - Delete on a security without transactions removes it.
  # - Delete on a security referenced by transactions surfaces a blocked
  #   confirmation modal rather than erroring out.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  defp create_security!(overrides \\ %{}) do
    base = %{
      name: "Apple Inc.",
      ticker_symbol: "AAPL",
      isin: "US0378331005",
      currency_code: "USD",
      asset_class: "equity",
      provider: "manual"
    }

    {:ok, sec} = Catalog.create_security(Map.merge(base, overrides))
    sec
  end

  defp add_transaction!(security) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Test Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-05-15],
        quantity: Decimal.new("1"),
        price: Decimal.new("100"),
        fees: Decimal.new("0"),
        taxes: Decimal.new("0"),
        currency_code: "EUR"
      })

    tx
  end

  test "every row renders a kebab button", %{conn: conn} do
    sec = create_security!()
    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, ~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
  end

  test "clicking the kebab opens the row context menu with the expected actions",
       %{conn: conn} do
    sec = create_security!()
    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    html = render(view)

    assert html =~ ~s(class="row-context-menu)
    assert html =~ ~s(phx-value-action="edit")
    assert html =~ ~s(phx-value-action="sync")
    assert html =~ ~s(phx-value-action="retire")
    assert html =~ ~s(phx-value-action="open")
    assert html =~ ~s(phx-value-action="copy_isin")
    assert html =~ ~s(phx-value-action="copy_ticker")
    assert html =~ ~s(phx-value-action="update_logo")
    assert html =~ ~s(phx-value-action="delete")
  end

  test "right-click on a row opens the same menu", %{conn: conn} do
    sec = create_security!()
    {:ok, view, _html} = live(conn, "/securities")

    # phx-contextmenu fires the same event name as the kebab; the server
    # cannot distinguish the trigger so the same menu is rendered.
    render_hook(view, "open_row_menu", %{"id" => Integer.to_string(sec.id)})

    assert has_element?(view, ".row-context-menu")
  end

  test "Edit action opens the form dialog directly at the confirm step",
       %{conn: conn} do
    sec = create_security!()
    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-value-action="edit"][phx-value-id="#{sec.id}"]))
    |> render_click()

    html = render(view)

    assert html =~ ~s(id="security-form-dialog")
    assert html =~ ~s(value="Apple Inc.")
    assert html =~ ~s(value="AAPL")
  end

  test "Retire action toggles is_retired", %{conn: conn} do
    sec = create_security!()
    refute Repo.get!(Security, sec.id).is_retired

    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-value-action="retire"][phx-value-id="#{sec.id}"]))
    |> render_click()

    assert Repo.get!(Security, sec.id).is_retired

    # Calling it again reactivates.
    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-value-action="retire"][phx-value-id="#{sec.id}"]))
    |> render_click()

    refute Repo.get!(Security, sec.id).is_retired
  end

  test "Copy ISIN emits a copy-to-clipboard event with the ISIN", %{conn: conn} do
    sec = create_security!(%{isin: "US0378331005"})
    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-value-action="copy_isin"][phx-value-id="#{sec.id}"]))
    |> render_click()

    assert_push_event(view, "copy-to-clipboard", %{text: "US0378331005"})
  end

  test "Copy ticker emits a copy-to-clipboard event with the ticker", %{conn: conn} do
    sec = create_security!(%{ticker_symbol: "AAPL"})
    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-value-action="copy_ticker"][phx-value-id="#{sec.id}"]))
    |> render_click()

    assert_push_event(view, "copy-to-clipboard", %{text: "AAPL"})
  end

  test "Delete without transactions removes the security", %{conn: conn} do
    sec = create_security!()
    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-value-action="delete"][phx-value-id="#{sec.id}"]))
    |> render_click()

    assert is_nil(Repo.get(Security, sec.id))
  end

  test "Delete with transactions surfaces the blocked dialog instead of erroring",
       %{conn: conn} do
    sec = create_security!()
    _tx = add_transaction!(sec)

    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    view
    |> element(~s(button[phx-value-action="delete"][phx-value-id="#{sec.id}"]))
    |> render_click()

    html = render(view)

    # The security must still exist
    assert Repo.get(Security, sec.id)

    # A blocked dialog explains why and offers retire as an alternative
    assert html =~ ~s(class="confirm-delete-blocked) or
             html =~ "referenced" or
             html =~ "referenz"

    assert html =~ ~s(phx-value-action="retire")
  end

  test "Close menu event clears the open menu state", %{conn: conn} do
    sec = create_security!()
    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(~s(button[phx-click="open_row_menu"][phx-value-id="#{sec.id}"]))
    |> render_click()

    assert has_element?(view, ".row-context-menu")

    render_hook(view, "close_row_menu", %{})

    refute has_element?(view, ".row-context-menu")
  end
end
