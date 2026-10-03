defmodule PortfolixirWeb.TransactionDeleteLiveTest do
  # Sprint 18 U1 (#912; plan D-6), pick H2 = A (board
  # `ux-design-2026-10-02/02-booking-delete`): no screen could delete a
  # booking — `Ledger.delete_transaction/2` was reachable only over the API
  # and MCP. Every history row's menu now carries "Delete…", last, in the
  # danger colour; it opens one narrow destructive dialog that names the
  # booking, says what changes, and confirms once. A split is deleted whole
  # (state A4), and the split drawer's help line links to it (A7).
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  setup do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    security = create_security!(name: "Global Aktien ETF", ticker: "GAE")
    deposit!(world, "5000", ~D[2026-09-03])

    buy =
      buy!(world, security, quantity: "40", price: "62.50", fees: "4.90", date: ~D[2026-09-22])

    %{world: world, security: security, buy: buy}
  end

  defp open_menu(view, tx) do
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view
  end

  defp ask_delete(view, tx) do
    view |> open_menu(tx) |> element("#tx-delete-#{tx.id}") |> render_click()
    view
  end

  defp split_in_two_portfolios(%{world: world}) do
    other = base_world(name: "Sparplan-Portfolio", cash_name: "Tagesgeld", depot_name: "Depot 2")
    security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world, security, quantity: "10", price: "80", date: ~D[2026-09-01])
    buy!(other, security, quantity: "6", price: "80", date: ~D[2026-09-02])

    {:ok, rows} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-09-15],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    %{split_security: security, split_rows: rows}
  end

  # User story (U1, #912; H2-A, A1 and A2):
  # As the operator who booked a transaction by mistake,
  # I want to delete it from its row in the history, after one confirmation
  # that names it and says what changes,
  # so that the correction the API and the agent could always make is mine
  # too, without a way to delete the wrong row by a slip.
  #
  # Acceptance criteria:
  # - The row menu carries Edit, then "Delete…" last, in the danger colour;
  #   the menu names its row for the phone sheet.
  # - "Delete…" opens one native dialog titled "Delete transaction": the
  #   booking as the history shows it (date · kind, subject · depot, the
  #   signed amount, the size), what changes for the depot and the cash
  #   account, the recompute sentence and the journal sentence; Cancel and a
  #   danger button naming the act, with no second confirmation.
  # - Cancel closes it and deletes nothing.
  # - The confirm deletes the booking through the journaled delete, closes
  #   the dialog, removes the row and says so in the page's result slot.
  test "the row menu's Delete… confirms once, naming the booking, and deletes it",
       %{conn: conn, buy: buy} do
    {:ok, view, _html} = live(conn, "/transactions")

    menu = view |> open_menu(buy) |> element("#tx-row-menu-#{buy.id}") |> render()
    assert menu =~ "Buy, Global Aktien ETF, 2026-09-22"
    assert [_, after_edit] = String.split(menu, "tx-edit-#{buy.id}", parts: 2)
    assert after_edit =~ "tx-delete-#{buy.id}"

    assert has_element?(
             view,
             "#tx-delete-#{buy.id}.row-context-menu__item--danger[phx-click='ask_delete']"
           )

    refute has_element?(view, "#tx-delete-#{buy.id}[data-confirm]")

    view |> element("#tx-delete-#{buy.id}") |> render_click()

    assert has_element?(view, "dialog#booking-delete-dialog.modal.booking-delete-dialog")
    refute has_element?(view, "#tx-row-menu-#{buy.id}")
    dialog = view |> element("#booking-delete-dialog") |> render()

    assert dialog =~ "Delete transaction"
    subject = view |> element("#booking-delete-subject") |> render()
    assert subject =~ "2026-09-22 · Buy"
    assert subject =~ "Global Aktien ETF"
    assert subject =~ "Depot 1"
    # The figure the history shows (quantity × price); the cash the
    # booking moved, fees included, is the consequence sentence's.
    assert subject =~ "-2,500.00 EUR"
    assert subject =~ "40 × 62.50"

    consequence =
      view |> element("[data-role='booking-delete-consequence']") |> render() |> text()

    assert consequence =~
             "Afterwards Depot 1 holds 40 fewer units of Global Aktien ETF, and Girokonto has 2,504.90 EUR more."

    assert consequence =~ "recomputed without this booking"
    assert dialog =~ "the screen cannot bring it back"
    refute has_element?(view, "[data-role='booking-delete-imported']")
    assert has_element?(view, "#booking-delete-confirm.button-danger")
    refute has_element?(view, "#booking-delete-confirm[data-confirm]")
    assert has_element?(view, "[data-role='booking-delete-cancel'][autofocus]")

    view |> element("[data-role='booking-delete-cancel']") |> render_click()
    refute has_element?(view, "#booking-delete-dialog")
    assert Ledger.get_transaction(buy.id)

    view |> ask_delete(buy) |> element("#booking-delete-confirm") |> render_click()

    refute has_element?(view, "#booking-delete-dialog")
    refute has_element?(view, "tr[data-transaction='#{buy.id}']")
    assert Ledger.get_transaction(buy.id) == nil

    assert view |> element(".alert-success") |> render() |> text() =~
             "Transaction deleted: Buy · Global Aktien ETF · 2026-09-22."

    assert [entry] = Journal.list_entries(resource_type: "transaction", operation: :delete)
    assert entry.actor_type == :owner_ui
    assert entry.resource_id == to_string(buy.id)
  end

  # User story (U1, #912; H2-A, A3; plan D-6):
  # As the operator deleting a booking an import brought in,
  # I want the confirmation to say that a re-import of the same file books
  # it again,
  # so that I am not surprised when it comes back.
  #
  # Acceptance criteria:
  # - A booking with an import hash shows one attention note saying its
  #   content hash goes with it and a re-import books it again; the
  #   consequence names the cash account's change.
  test "an imported booking's confirmation says a re-import books it again",
       %{conn: conn, world: world, security: security} do
    {:ok, dividend} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          type: "dividend",
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          security_id: security.id,
          date: ~D[2026-09-26],
          gross_amount: "48.75",
          taxes: "8.61",
          currency_code: "EUR"
        },
        import_hash: String.duplicate("a1", 32)
      )

    {:ok, view, _html} = live(conn, "/transactions")
    ask_delete(view, dividend)

    note = view |> element("[data-role='booking-delete-imported']") |> render() |> text()
    assert note =~ "Attention"
    assert note =~ "This booking came from an import."
    assert note =~ "a re-import of the same file books it again"

    assert view |> element("[data-role='booking-delete-consequence']") |> render() |> text() =~
             "Afterwards Girokonto has 48.75 EUR less."
  end

  # User story (U1, #912; H2-A, A4 and A5; ADR-0028 §1):
  # As the operator who booked a split with the wrong ratio,
  # I want "Delete…" on any of its rows to delete the split as the one fact
  # I booked, naming the portfolios whose rows go with it,
  # so that no portfolio keeps the event and the corrected ratio can be
  # recorded right after.
  #
  # Acceptance criteria:
  # - The dialog is titled "Delete split", names the ratio and the row count,
  #   the portfolios, what the holdings and the chart do afterwards, and its
  #   confirm reads "Delete split (2 rows)".
  # - The confirm deletes every row of the split in one step and says so.
  test "a split row's Delete… deletes the split whole", %{conn: conn} = ctx do
    %{split_security: security, split_rows: [row_a, row_b]} = split_in_two_portfolios(ctx)

    {:ok, view, _html} = live(conn, "/transactions")
    ask_delete(view, row_b)

    dialog = view |> element("#booking-delete-dialog") |> render() |> text()
    assert dialog =~ "Delete split"
    subject = view |> element("#booking-delete-subject") |> render() |> text()
    assert subject =~ "2026-09-15 · Split"
    assert subject =~ "Kestrel Robotik SE"
    assert subject =~ "2:1"
    assert subject =~ "2 rows"

    assert dialog =~
             "The split is booked in 2 portfolios, Hauptportfolio and Sparplan-Portfolio; both rows are deleted in one step."

    assert dialog =~ "count without the split from 2026-09-15"
    assert dialog =~ "stored quotes stay as they are"

    assert view |> element("#booking-delete-confirm") |> render() |> text() =~
             "Delete split (2 rows)"

    view |> element("#booking-delete-confirm") |> render_click()

    assert Ledger.get_transaction(row_a.id) == nil
    assert Ledger.get_transaction(row_b.id) == nil
    assert Splits.booked_on(security.id, ~D[2026-09-15]) == []

    assert view |> element(".alert-success") |> render() |> text() =~
             "Split deleted: Kestrel Robotik SE · 2:1 · 2026-09-15, 2 rows."
  end

  # User story (U1, #912; H2-A, A6):
  # As the operator confirming a delete in one tab while the agent (or
  # another tab) already deleted the booking,
  # I want the page to say the booking no longer exists,
  # so that nothing else is deleted and the history is current.
  #
  # Acceptance criteria:
  # - The confirm on a booking gone since the dialog opened closes the
  #   dialog, deletes nothing else and shows "That transaction no longer
  #   exists." with the history reloaded.
  test "a booking deleted meanwhile is answered, never a crash", %{conn: conn, buy: buy} do
    {:ok, view, _html} = live(conn, "/transactions")
    ask_delete(view, buy)

    {:ok, _} = Ledger.delete_transaction(Actor.api_token_rw("agent"), buy)
    view |> element("#booking-delete-confirm") |> render_click()

    refute has_element?(view, "#booking-delete-dialog")

    assert view |> element(".alert-error") |> render() |> text() =~
             "That transaction no longer exists."

    refute has_element?(view, "tr[data-transaction='#{buy.id}']")
    assert Ledger.count_transactions() == 1
  end

  # User story (U1, #912; H2-A, A7; G12.3-A):
  # As the operator reading in the split drawer that a wrong split is
  # deleted and recorded again,
  # I want the way to delete it right there,
  # so that the limit the drawer states comes with its remedy (UX-DR26).
  #
  # Acceptance criteria:
  # - The split drawer's help line names deleting and recording again with
  #   "Record split", and carries "Delete split…" as a link-button.
  # - It closes the drawer and opens the split's delete dialog — never a
  #   dialog from a dialog.
  test "the split drawer's help line opens the split's delete", %{conn: conn} = ctx do
    %{split_rows: [_row_a, row_b]} = split_in_two_portfolios(ctx)

    {:ok, view, _html} = live(conn, "/transactions")
    view |> open_menu(row_b) |> element("#tx-edit-#{row_b.id}") |> render_click()

    help = view |> element("#booking-edit-help") |> render()
    assert help =~ "A wrong split is deleted and then recorded again"
    refute help =~ "API or MCP"

    view |> element("#booking-edit-help button.link-button", "Delete split…") |> render_click()

    refute has_element?(view, "#booking-drawer")
    assert has_element?(view, "dialog#booking-delete-dialog")
    assert view |> element("#booking-delete-dialog") |> render() =~ "Delete split"
  end

  # User story (U1, #912; H2-A, the board's copy; EXPERIENCE.md, impersonal
  # German):
  # As a German-reading operator,
  # I want the menu, the dialog and the result in the board's words,
  # so that the delete reads the same as every other screen.
  #
  # Acceptance criteria:
  # - "Löschen…", "Transaktion löschen", the consequence sentence with the
  #   locale's figures, and "Transaktion gelöscht: …" with the German date.
  test "the dialog speaks the board's German", %{conn: conn, buy: buy} do
    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/transactions")

    assert view |> open_menu(buy) |> element("#tx-delete-#{buy.id}") |> render() =~ "Löschen…"
    view |> element("#tx-delete-#{buy.id}") |> render_click()

    dialog = view |> element("#booking-delete-dialog") |> render() |> text()
    assert dialog =~ "Transaktion löschen"
    assert dialog =~ "22.09.2026 · Kauf"

    assert dialog =~
             "Danach hält Depot 1 40 Stück Global Aktien ETF weniger, und Girokonto hat 2.504,90 EUR mehr."

    assert dialog =~
             "Bestände, Kontostände, Rendite und Trades werden ohne diese Buchung neu berechnet."

    assert dialog =~
             "Das Journal behält die Buchung mit allen Werten; zurückholen kann die Oberfläche sie nicht."

    view |> element("#booking-delete-confirm") |> render_click()

    assert view |> element(".alert-success") |> render() |> text() =~
             "Transaktion gelöscht: Kauf · Global Aktien ETF · 22.09.2026."
  end

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.replace(~r/\s+/, " ")
end
