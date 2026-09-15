defmodule PortfolixirWeb.BookingDrawerLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # User story (#803, review C6 — variant C, picked 2026-09-14):
  # As a local portfolio maintainer opening the Transactions page,
  # I want the history to fill the page and the booking form to slide in as
  # a side drawer — the securities detail pane's shape, a bottom sheet on the
  # phone — with every field and validation it has today,
  # so that reading is the default posture and recording is one intent away,
  # never zero; and the holdings table, which duplicated Wealth → Holdings,
  # leaves the route.
  #
  # Acceptance criteria:
  # - The page opens on the history: no form in the DOM, a "Record
  #   transaction" control in the history's section head, no holdings panel.
  # - The control opens a native dialog (the ModalDialog hook; a sheet under
  #   720 px by its data attribute) headed "Record transaction", carrying
  #   every field of the form, the depot select labelled "Books to depot",
  #   costs and note behind one disclosure, the sell-lot preview inside.
  # - A valid submit records the booking, closes the drawer and shows the
  #   result; an invalid one keeps the drawer open with its field errors;
  #   Cancel and the hook's close event close it and discard the draft.
  # - Without a bookable depot the control is absent and the setup note
  #   shows.

  defp world do
    world = WorldFixtures.base_world(name: "Drawer", depot_name: "Main", cash_name: "Cash")
    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB")
    %{world: world, security: security}
  end

  defp open(view), do: view |> element("#open-booking") |> render_click()

  defp submit(view, world, security, overrides) do
    params =
      Map.merge(
        %{
          "type" => "buy",
          "date" => "2026-02-01",
          "securities_account_id" => to_string(world.depot.id),
          "security_id" => to_string(security.id),
          "quantity" => "2",
          "price" => "50"
        },
        overrides
      )

    view |> element("#transaction-form") |> render_submit(%{"transaction" => params})
  end

  test "the page opens on the history and the control opens the drawer", %{conn: conn} do
    %{world: world, security: security} = world()

    {:ok, view, html} = live(conn, "/transactions")

    refute has_element?(view, "#transaction-form")
    refute has_element?(view, "#holdings-panel")
    refute html =~ "Current holdings"

    control = view |> element("#open-booking") |> render()
    assert control =~ ~s(aria-haspopup="dialog")
    assert control =~ ~s(aria-expanded="false")
    assert control =~ "Record transaction"
    assert has_element?(view, "#transaction-list-panel .section-head #open-booking")

    open(view)

    assert has_element?(
             view,
             ~s(dialog#booking-drawer.detail-pane[phx-hook="ModalDialog"][data-close-event="close_booking"][data-sheet-below="720"])
           )

    assert has_element?(view, "#booking-drawer h2#booking-drawer-title", "Record transaction")
    assert view |> element("#open-booking") |> render() =~ ~s(aria-expanded="true")

    for field <- ~w(type date securities_account_id security_id quantity price fees taxes notes) do
      assert has_element?(
               view,
               "#booking-drawer #transaction-form [name='transaction[#{field}]']"
             ),
             "field #{field} missing from the drawer"
    end

    assert has_element?(view, "#booking-drawer label", "Books to depot")

    assert has_element?(
             view,
             "#booking-drawer details#transaction-costs summary",
             "Costs and note"
           )

    assert has_element?(
             view,
             "#booking-drawer details#transaction-costs textarea[name='transaction[notes]']"
           )

    assert has_element?(view, "#booking-drawer [data-role='derived-currency']")
    assert has_element?(view, "#booking-drawer #booking-cancel", "Cancel")

    # A valid submit records, closes the drawer and shows the result.
    submit(view, world, security, %{})

    assert [_] = Ledger.list_transactions_for_portfolio(world.portfolio.id)
    refute has_element?(view, "#booking-drawer")
    assert has_element?(view, "[role='status']", "Transaction recorded")
    assert has_element?(view, "#transaction-list tbody tr td", "Buy")
    assert view |> element("#open-booking") |> render() =~ ~s(aria-expanded="false")
  end

  test "an invalid submit keeps the drawer open with its field errors", %{conn: conn} do
    %{world: world, security: security} = world()

    {:ok, view, _html} = live(conn, "/transactions")
    open(view)
    submit(view, world, security, %{"quantity" => ""})

    assert has_element?(view, "#booking-drawer")

    assert has_element?(
             view,
             "#booking-drawer input[name='transaction[quantity]'][aria-invalid='true']"
           )

    assert has_element?(view, "#booking-drawer #tx-error-quantity")
    assert Ledger.list_transactions_for_portfolio(world.portfolio.id) == []
  end

  test "the sell-lot preview renders inside the drawer", %{conn: conn} do
    %{world: world, security: security} = world()
    WorldFixtures.deposit!(world, "5000", ~D[2026-01-02])
    WorldFixtures.buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])

    {:ok, view, _html} = live(conn, "/transactions")
    open(view)

    view
    |> element("#transaction-form")
    |> render_change(%{
      "transaction" => %{
        "type" => "sell",
        "date" => "2026-06-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "5",
        "price" => "150",
        "fees" => "0",
        "taxes" => "0",
        "notes" => ""
      }
    })

    assert has_element?(view, "#booking-drawer #sell-lot-preview")
    assert has_element?(view, "#booking-drawer [data-role='preview-total']", "+250.00")
  end

  test "cancel and the hook's close event close the drawer and discard the draft", %{
    conn: conn
  } do
    %{world: world} = world()

    {:ok, view, _html} = live(conn, "/transactions")
    open(view)

    view
    |> element("#transaction-form")
    |> render_change(%{
      "transaction" => %{"securities_account_id" => to_string(world.depot.id), "quantity" => "7"}
    })

    assert has_element?(view, "#booking-drawer input[name='transaction[quantity]'][value='7']")

    view |> element("#booking-cancel") |> render_click()
    refute has_element?(view, "#booking-drawer")

    # Reopened: the draft is gone.
    open(view)
    refute has_element?(view, "#booking-drawer input[name='transaction[quantity]'][value='7']")

    # Esc in the dialog pushes the close event named on it.
    render_hook(view, "close_booking", %{})
    refute has_element?(view, "#booking-drawer")
    assert view |> element("#open-booking") |> render() =~ ~s(aria-expanded="false")
  end

  test "without a bookable depot the control is absent and the setup note shows", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions")

    refute has_element?(view, "#open-booking")
    refute has_element?(view, "#booking-drawer")
    assert has_element?(view, "#transaction-setup-empty a[href='/portfolios']")
  end

  test "the drawer is German where the page is", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    open(view)

    assert has_element?(view, "#booking-drawer h2", "Transaktion erfassen")
    assert has_element?(view, "#booking-drawer label", "Bucht auf Depot")

    assert has_element?(
             view,
             "#booking-drawer details#transaction-costs summary",
             "Kosten und Notiz"
           )

    assert has_element?(view, "#booking-drawer #booking-cancel", "Abbrechen")
  end
end
