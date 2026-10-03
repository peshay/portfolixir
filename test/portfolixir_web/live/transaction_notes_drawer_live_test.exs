defmodule PortfolixirWeb.TransactionNotesDrawerLiveTest do
  # Sprint 18 U1 (#912), pick H2b = A (board
  # `ux-design-2026-10-02/02-booking-delete`, last section): "Edit" on every
  # kind except buy, sell and split opened the buy/sell drawer with no type
  # that fits, and saving could only refuse ("Security can't be blank, …").
  # Those rows now open the split's notes-only state (G12.3-A), generalised:
  # the booking's facts read-only, the note editable, and "Delete…" as the
  # correction path the screen has.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  setup do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    security = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    deposit = deposit!(world, "1500", ~D[2026-09-03])
    %{world: world, security: security, deposit: deposit}
  end

  defp book!(attrs) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), Map.put_new(attrs, :currency_code, "EUR"))

    tx
  end

  defp open_edit(conn, tx) do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-edit-#{tx.id}") |> render_click()
    view
  end

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.replace(~r/\s+/, " ")

  # User story (U1, #912; H2b-A):
  # As the operator opening "Edit" on a deposit,
  # I want to see the booking's own facts, fixed, and change only its note,
  # with the way to correct it named where I tried,
  # so that the drawer never offers a form that can only refuse.
  #
  # Acceptance criteria:
  # - The drawer is the notes-only state: no booking form; the sub line says
  #   the screen does not book this kind and only the note changes, and that
  #   the journal records the change (the closing act, R10a and R10d: no
  #   "a “Deposit”", no "journaled").
  # - Type, date, cash account and amount show as disabled fields.
  # - The help line states the limit and both correction paths — for a
  #   booking that came over the API, booking it again there, never
  #   "imported again" (R10e) — with "Delete…" as a link-button.
  # - "Save note" stores the note alone and closes the drawer with "Note
  #   saved"; the deposit's facts are unchanged.
  test "a deposit's edit shows its facts fixed and saves only the note",
       %{conn: conn, deposit: deposit} do
    view = open_edit(conn, deposit)

    assert has_element?(view, "dialog#booking-drawer #note-form")
    refute has_element?(view, "#transaction-form")

    drawer = view |> element("#booking-drawer") |> render() |> text()

    assert drawer =~
             "The screen does not book the kind “Deposit”; only the note changes here, and the journal records the change."

    assert has_element?(view, "#booking-facts select[name='note[type]'][disabled]")

    assert has_element?(
             view,
             "#booking-facts input[name='note[date]'][disabled][value='2026-09-03']"
           )

    assert view |> element("#booking-facts") |> render() |> text() =~ "Girokonto"

    assert has_element?(
             view,
             "#booking-facts input[name='note[gross_amount]'][disabled][value='1,500.00']"
           )

    refute has_element?(view, "#booking-facts [name='note[security_id]']")

    help = view |> element("#booking-edit-help") |> render() |> text()
    assert help =~ "corrected over the API or MCP, or it is deleted and booked again there"
    refute help =~ "imported"
    assert has_element?(view, "#booking-edit-help button.link-button[phx-click='ask_delete']")

    view
    |> form("#note-form", %{"note" => %{"notes" => "per the bank statement"}})
    |> render_submit()

    refute has_element?(view, "#booking-drawer")
    assert view |> element(".alert-success") |> render() =~ "Note saved"
    stored = Ledger.get_transaction(deposit.id)
    assert stored.notes == "per the bank statement"
    assert stored.type == "deposit"
    assert Decimal.equal?(stored.gross_amount, Decimal.new("1500"))
  end

  # User story (U1, #912; H2b-A, pin 4):
  # As the operator checking a booking the history shows only in part,
  # I want the drawer to show the fields that kind stores,
  # so that I can read the whole booking without deleting it.
  #
  # Acceptance criteria:
  # - A dividend shows its security, cash account, amount and taxes; a cash
  #   transfer both accounts; an inbound delivery its depot, quantity and
  #   price; a security transfer both depots and the quantity.
  # - A set balance shows its account and the balance, and its help line
  #   names setting it again under Accounts & depots.
  test "each kind shows the facts it stores", %{conn: conn, world: world, security: security} do
    savings = add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")
    buy!(world, security, quantity: "30", price: "40", date: ~D[2026-09-05])

    dividend =
      book!(%{
        type: "dividend",
        portfolio_id: world.portfolio.id,
        security_id: security.id,
        cash_account_id: world.cash.id,
        gross_amount: "48.75",
        taxes: "8.61",
        date: ~D[2026-09-26]
      })

    transfer =
      book!(%{
        type: "cash_transfer",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        counter_cash_account_id: savings.cash.id,
        gross_amount: "200",
        date: ~D[2026-09-10]
      })

    delivery =
      book!(%{
        type: "inbound_delivery",
        portfolio_id: world.portfolio.id,
        security_id: security.id,
        securities_account_id: world.depot.id,
        quantity: "5",
        price: "41",
        date: ~D[2026-09-11]
      })

    moved =
      book!(%{
        type: "security_transfer",
        portfolio_id: world.portfolio.id,
        security_id: security.id,
        securities_account_id: world.depot.id,
        counter_securities_account_id: savings.depot.id,
        quantity: "3",
        date: ~D[2026-09-12]
      })

    {:ok, anchor} =
      Ledger.set_cash_balance(Actor.owner_ui(), world.cash, %{date: ~D[2026-09-30], amount: "900"})

    facts = fn tx ->
      view = open_edit(conn, tx)
      {view, view |> element("#booking-facts") |> render() |> text()}
    end

    {_view, text} = facts.(dividend)
    assert text =~ "Nordwind Industrie AG"
    assert text =~ "Girokonto"

    {view, _text} = facts.(dividend)
    assert has_element?(view, "#booking-facts input[name='note[gross_amount]'][value='48.75']")
    assert has_element?(view, "#booking-facts input[name='note[taxes]'][value='8.61']")

    {_view, text} = facts.(transfer)
    assert text =~ "Girokonto"
    assert text =~ "Tagesgeld"

    {view, text} = facts.(delivery)
    assert text =~ "Depot 1"
    assert has_element?(view, "#booking-facts input[name='note[quantity]'][value='5']")
    assert has_element?(view, "#booking-facts input[name='note[price]'][value='41.00']")

    {view, text} = facts.(moved)
    assert text =~ "Depot 1"
    assert text =~ "Depot 2"
    assert has_element?(view, "#booking-facts input[name='note[quantity]'][value='3']")

    {view, text} = facts.(anchor)
    assert text =~ "Girokonto"
    assert has_element?(view, "#booking-facts input[name='note[gross_amount]'][value='900.00']")

    assert view |> element("#booking-edit-help") |> render() |> text() =~
             "deleted and set again under Accounts & depots"
  end

  # User story (U1, #912; H2b-A; the closing act, R10d and R10e):
  # As the operator opening Edit on a dividend an import brought in, and on
  # a split,
  # I want the help line to name the import as the way back only for an
  # imported booking, and every sub line in plain words,
  # so that the drawer tells me what actually corrects this booking.
  #
  # Acceptance criteria:
  # - An imported dividend's help line names deleting and importing again.
  # - The German sub lines say "das Journal hält die Änderung fest" — a
  #   kind, a split and a set balance alike — never "journalisiert".
  test "the help line names the import only for an imported booking",
       %{conn: conn, world: world, security: security} do
    {:ok, dividend} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          type: "dividend",
          portfolio_id: world.portfolio.id,
          security_id: security.id,
          cash_account_id: world.cash.id,
          gross_amount: "48.75",
          currency_code: "EUR",
          date: ~D[2026-09-26]
        },
        import_hash: String.duplicate("b2", 32)
      )

    view = open_edit(conn, dividend)

    assert view |> element("#booking-edit-help") |> render() |> text() =~
             "corrected over the API or MCP, or it is deleted and imported again"

    {:ok, anchor} =
      Ledger.set_cash_balance(Actor.owner_ui(), world.cash, %{date: ~D[2026-09-30], amount: "900"})

    german = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

    for {tx, sub} <- [
          {dividend, "Die Art „Dividende“ bucht die Oberfläche nicht;"},
          {anchor, "Ein Saldo wird unter Konten & Depots gesetzt;"}
        ] do
      drawer = german |> open_edit(tx) |> element(".detail-pane-sub") |> render() |> text()
      assert drawer =~ sub
      assert drawer =~ "hier ändert sich nur die Notiz, und das Journal hält die Änderung fest."
      refute drawer =~ "journalisiert"
    end
  end

  # User story (U1, #912; H2b-A, pin 5):
  # As the operator who decides a booking the screen cannot correct must go,
  # I want the help line's "Delete…" to lead to the same confirmation as the
  # row menu,
  # so that the correction path is one step away and never a dialog opened
  # from a dialog.
  #
  # Acceptance criteria:
  # - "Delete…" closes the drawer and opens the booking's delete dialog.
  test "the help line's Delete… opens the booking's delete dialog", %{
    conn: conn,
    deposit: deposit
  } do
    view = open_edit(conn, deposit)

    view |> element("#booking-edit-help button.link-button") |> render_click()

    refute has_element?(view, "#booking-drawer")
    assert has_element?(view, "dialog#booking-delete-dialog")

    assert view |> element("#booking-delete-subject") |> render() |> text() =~
             "2026-09-03 · Deposit"
  end

  # User story (U1, #912; H2b-A):
  # As the operator of a page whose notes-only drawer has no booking form,
  # I want a booking save pushed at it refused,
  # so that the drawer cannot change a booking's kind or figures behind the
  # form it shows.
  #
  # Acceptance criteria:
  # - A save_transaction event while the notes-only drawer is open changes
  #   nothing; the drawer stays.
  test "a forged booking save on the notes-only drawer changes nothing",
       %{conn: conn, world: world, security: security, deposit: deposit} do
    view = open_edit(conn, deposit)

    render_submit(view, "save_transaction", %{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-09-03",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "10",
        "price" => "1"
      }
    })

    assert has_element?(view, "#note-form")
    stored = Ledger.get_transaction(deposit.id)
    assert stored.type == "deposit"
    assert stored.security_id == nil
  end
end
