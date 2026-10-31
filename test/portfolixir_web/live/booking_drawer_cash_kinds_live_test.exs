defmodule PortfolixirWeb.BookingDrawerCashKindsLiveTest do
  # Sprint 21 α6 (#1052, #1206; the plan's D-6; board 03
  # `ux-design-2026-10-09/03-history-drawer`, pick N12 = A). Risk tier
  # (ADR-0036, money): every figure is an exact Decimal, and every identity
  # the drawer writes is pinned against the API's answer for the same write,
  # because the drawer reaches the same two ledger functions the API uses
  # (`Ledger.create_transaction/3`, `Ledger.update_transaction/3`) and must
  # bring no money semantics of its own.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction

  setup do
    world =
      base_world(name: "Drawer Cash World", cash_name: "Test-Cash", depot_name: "Depot Muster")

    security = create_security!(name: "Arbolia Inc.", ticker: "ARBO")
    deposit!(world, "1000.00", ~D[2026-10-01])
    %{world: world, security: security}
  end

  defp d(value), do: Decimal.new(value)

  defp balance(world),
    do:
      world.portfolio.id
      |> then(&Ledger.cash_balances(portfolio_id: &1))
      |> Map.fetch!(world.cash.id)

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.replace(~r/\s+/, " ")

  defp api_conn do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp post_json(path, attrs),
    do: api_conn() |> post(path, Jason.encode!(%{"transaction" => attrs}))

  defp patch_json(path, attrs),
    do: api_conn() |> patch(path, Jason.encode!(%{"transaction" => attrs}))

  # The drawer opened for a new booking, its kind chosen as the select's
  # change event sends it.
  defp open_kind(conn, kind, extra) do
    {:ok, view, _html} = live(conn, "/transactions")
    render_click(view, "open_booking", %{})

    render_change(view, "form_changed", %{
      "_target" => ["transaction", "type"],
      "transaction" => Map.merge(%{"type" => kind, "date" => "2026-10-08"}, extra)
    })

    view
  end

  defp open_edit(conn, tx) do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-edit-#{tx.id}") |> render_click()
    view
  end

  # The fields a booking stores that the API and the drawer both write.
  @compared [
    :type,
    :date,
    :portfolio_id,
    :cash_account_id,
    :security_id,
    :gross_amount,
    :taxes,
    :fees,
    :currency_code,
    :securities_account_id,
    :quantity,
    :price,
    :settlement_fx_rate,
    :settlement_amount,
    :security_amount,
    :import_hash
  ]

  defp stored_fields(%Transaction{} = tx), do: Map.take(tx, @compared)

  defp newest_entry(id, operation),
    do:
      [resource_type: "transaction", resource_id: to_string(id), operation: operation]
      |> Journal.list_entries()
      |> List.first()

  # User story (#1206, Sprint 21 α6; board 03, N12 A):
  # As the operator whose import refused a sale and named "book the tax
  # refund by hand" as the remedy,
  # I want to book a tax refund in the drawer, the kind first, then the
  # date, the cash account and the amount,
  # so that the import's remedy is finished on a screen, not over the API.
  #
  # Acceptance criteria:
  # - Choosing "Tax refund" turns the form into the cash form: a cash
  #   account select, an optional security ("No security"), the amount
  #   labelled with the chosen account's currency, and one direction line
  #   ("Credited to Test-Cash."); no depot, quantity or price.
  # - Saving books the refund on Test-Cash in its currency, 1,000.00 →
  #   1,012.40, journaled as a create under the operator's actor.
  # - The API's answer for the same write stores the same fields and moves
  #   the balance by the same 12.40 (1,012.40 → 1,024.80).
  test "a tax refund books through the drawer as the API books it",
       %{conn: conn, world: world} do
    view = open_kind(conn, "tax_refund", %{"cash_account_id" => to_string(world.cash.id)})

    assert has_element?(view, "#transaction-form select[name='transaction[cash_account_id]']")
    assert has_element?(view, "#transaction-form input[name='transaction[gross_amount]']")
    refute has_element?(view, "#transaction-form [name='transaction[securities_account_id]']")
    refute has_element?(view, "#transaction-form [name='transaction[quantity]']")
    refute has_element?(view, "#transaction-form [name='transaction[price]']")
    refute has_element?(view, "#transaction-form [name='transaction[taxes]']")

    assert has_element?(
             view,
             "#transaction-form select[name='transaction[security_id]'] option[value='']",
             "No security"
           )

    form = view |> element("#transaction-form") |> render() |> text()
    assert form =~ "Amount (EUR)"

    assert view |> element("[data-role='cash-direction']") |> render() |> text() =~
             "Credited to Test-Cash."

    assert view |> element("#booking-drawer .detail-pane-sub") |> render() |> text() =~
             "Books to the chosen cash account, in its currency."

    view
    |> form("#transaction-form", %{
      "transaction" => %{
        "type" => "tax_refund",
        "date" => "2026-10-08",
        "cash_account_id" => to_string(world.cash.id),
        "security_id" => "",
        "gross_amount" => "12.40",
        "notes" => "remedy of the refused sale"
      }
    })
    |> render_submit()

    refute has_element?(view, "#booking-drawer")
    assert view |> element("#transactions-result") |> render() =~ "Transaction recorded"

    [drawer_row] = Enum.filter(Ledger.list_transactions(), &(&1.type == "tax_refund"))
    assert Decimal.equal?(drawer_row.gross_amount, d("12.40"))
    assert drawer_row.currency_code == "EUR"
    assert drawer_row.cash_account_id == world.cash.id
    assert drawer_row.portfolio_id == world.portfolio.id
    assert drawer_row.security_id == nil
    assert drawer_row.notes == "remedy of the refused sale"
    assert Decimal.equal?(balance(world), d("1012.40"))

    entry = newest_entry(drawer_row.id, :create)
    assert entry.actor_type == :owner_ui

    api =
      post_json("/api/v1/transactions", %{
        "type" => "tax_refund",
        "date" => "2026-10-08",
        "portfolio_id" => world.portfolio.id,
        "cash_account_id" => world.cash.id,
        "gross_amount" => "12.40",
        "currency_code" => "EUR"
      })

    assert %{"data" => %{"id" => api_id}} = json_response(api, 201)
    api_row = Ledger.get_transaction(api_id)
    assert stored_fields(api_row) == stored_fields(Ledger.get_transaction(drawer_row.id))
    assert Decimal.equal?(balance(world), d("1024.80"))
  end

  # User story (#1052, #1206, Sprint 21 α6; board 03, N12 A):
  # As the operator booking any one-amount cash kind,
  # I want the kind to give the direction and the fields,
  # so that I never type a sign and never meet a field the kind does not
  # store.
  #
  # Acceptance criteria:
  # - The seven kinds book 10.00 each on Test-Cash: dividend, interest,
  #   deposit and tax refund credit it, removal, fee and tax debit it; the
  #   balance reads 1,000.00 + 4 × 10.00 − 3 × 10.00 = 1,010.00.
  # - A dividend requires a security (its select has no "No security");
  #   interest, fee, tax and tax refund offer "No security"; a deposit and a
  #   removal show no security field. Taxes are a field of a dividend and
  #   of interest only.
  test "each cash kind books its direction and shows its own fields",
       %{conn: conn, world: world, security: security} do
    kinds = [
      {"dividend", "Credited to Test-Cash.", :required, true},
      {"interest", "Credited to Test-Cash.", :optional, true},
      {"deposit", "Credited to Test-Cash.", :none, false},
      {"removal", "Debited from Test-Cash.", :none, false},
      {"fee", "Debited from Test-Cash.", :optional, false},
      {"tax", "Debited from Test-Cash.", :optional, false},
      {"tax_refund", "Credited to Test-Cash.", :optional, false}
    ]

    for {kind, direction, security_field, taxes?} <- kinds do
      view = open_kind(conn, kind, %{"cash_account_id" => to_string(world.cash.id)})

      assert view |> element("[data-role='cash-direction']") |> render() |> text() =~ direction

      select = "#transaction-form select[name='transaction[security_id]']"

      case security_field do
        :none ->
          refute has_element?(view, select)

        :optional ->
          assert has_element?(view, "#{select} option[value='']", "No security")

        :required ->
          assert has_element?(view, select)
          refute has_element?(view, "#{select} option[value='']", "No security")
      end

      assert has_element?(view, "#transaction-form input[name='transaction[taxes]']") == taxes?

      fields =
        %{
          "type" => kind,
          "date" => "2026-10-08",
          "cash_account_id" => to_string(world.cash.id),
          "gross_amount" => "10.00"
        }
        |> then(&if(security_field == :none, do: &1, else: Map.put(&1, "security_id", "")))
        |> then(
          &if(kind == "dividend",
            do: Map.put(&1, "security_id", to_string(security.id)),
            else: &1
          )
        )

      view |> form("#transaction-form", %{"transaction" => fields}) |> render_submit()
      refute has_element?(view, "#booking-drawer"), "#{kind} was not booked"
    end

    assert Decimal.equal?(balance(world), d("1010.00"))
  end

  # User story (#1052, #1206, Sprint 21 α6; board 03, N12 A: "the account
  # fixes the currency", as the depot does for a trade, #473):
  # As the operator booking a fee on an account kept in US dollars,
  # I want the booking in that account's currency, whatever the form held,
  # so that the drawer never books a cross-currency cash kind without its
  # rate.
  #
  # Acceptance criteria:
  # - The amount reads "Amount (USD)" once USD-Konto is chosen.
  # - A fee of 4.90 to USD-Konto is stored in USD, in USD-Konto's
  #   portfolio, and moves its balance from 0 to −4.90.
  test "a cash booking takes the chosen account's currency", %{conn: conn, world: world} do
    usd =
      add_depot(world.portfolio, cash_name: "USD-Konto", depot_name: "Depot USD", currency: "USD")

    view = open_kind(conn, "fee", %{"cash_account_id" => to_string(usd.cash.id)})

    assert view |> element("#transaction-form") |> render() |> text() =~ "Amount (USD)"

    view
    |> form("#transaction-form", %{
      "transaction" => %{
        "type" => "fee",
        "date" => "2026-10-08",
        "cash_account_id" => to_string(usd.cash.id),
        "security_id" => "",
        "gross_amount" => "4.90"
      }
    })
    |> render_submit()

    [fee] = Enum.filter(Ledger.list_transactions(), &(&1.type == "fee"))
    assert fee.currency_code == "USD"
    assert fee.portfolio_id == usd.cash.portfolio_id

    assert Decimal.equal?(
             Map.fetch!(Ledger.cash_balances(portfolio_id: world.portfolio.id), usd.cash.id),
             d("-4.90")
           )
  end

  # User story (#1052, Sprint 21 α6; board 03, N12 A, "abgelehnt"):
  # As the operator who typed a fee with a minus,
  # I want the refusal under the amount and on the page, with what I typed
  # kept,
  # so that I correct one figure instead of typing the booking again.
  #
  # Acceptance criteria:
  # - A fee of -9.90 stores nothing; the balance stays 1,000.00.
  # - The amount carries `aria-invalid` and the field error "must be greater
  #   than 0"; the page's result reads "Amount must be greater than 0"; the
  #   input still holds -9.90 and the drawer stays open.
  test "a refused amount keeps the drawer and names the field", %{conn: conn, world: world} do
    view = open_kind(conn, "fee", %{"cash_account_id" => to_string(world.cash.id)})
    before = Ledger.count_transactions()

    view
    |> form("#transaction-form", %{
      "transaction" => %{
        "type" => "fee",
        "date" => "2026-10-08",
        "cash_account_id" => to_string(world.cash.id),
        "security_id" => "",
        "gross_amount" => "-9.90"
      }
    })
    |> render_submit()

    assert Ledger.count_transactions() == before
    assert Decimal.equal?(balance(world), d("1000.00"))
    assert has_element?(view, "#booking-drawer")

    assert has_element?(
             view,
             "input[name='transaction[gross_amount]'][aria-invalid='true'][value='-9.90']"
           )

    assert view |> element("#tx-error-gross_amount") |> render() =~ "must be greater than 0"

    assert view |> element("#transactions-result") |> render() |> text() =~
             "Amount must be greater than 0"
  end

  # User story (#1052, Sprint 21 α6; the plan's round trip 5; board 03,
  # N12 A, "Bearbeiten"):
  # As the operator whose dividend was booked with the wrong amount,
  # I want to correct its amount in the drawer,
  # so that the screen corrects what the API corrects, the balance moves by
  # the difference, and the journal records the edit.
  #
  # Acceptance criteria:
  # - Edit opens the same cash form, prefilled: 48.75 and taxes 8.61; the
  #   kind and the cash account are disabled, and the help line states that
  #   limit with "Delete…" as its remedy.
  # - Saving 50.00 with taxes 8.75 corrects the row in place (no second
  #   row): Test-Cash 1,048.75 → 1,050.00, by the difference 1.25.
  # - The journal holds one update under the operator's actor, its
  #   before-image 48.75 and its after-image 50.00.
  # - The API's PATCH of the same change to a twin dividend stores the same
  #   figures and moves the balance by the same 1.25 (1,098.75 → 1,100.00).
  test "a dividend corrected in the drawer moves the balance by the difference",
       %{conn: conn, world: world, security: security} do
    dividend = fn ->
      {:ok, tx} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          type: "dividend",
          portfolio_id: world.portfolio.id,
          security_id: security.id,
          cash_account_id: world.cash.id,
          gross_amount: "48.75",
          taxes: "8.61",
          currency_code: "EUR",
          date: ~D[2026-10-05]
        })

      tx
    end

    tx = dividend.()
    assert Decimal.equal?(balance(world), d("1048.75"))
    count = Ledger.count_transactions()

    view = open_edit(conn, tx)

    refute has_element?(view, "#note-form")
    assert has_element?(view, "#transaction-form select[name='transaction[type]'][disabled]")

    assert has_element?(
             view,
             "#transaction-form select[name='transaction[cash_account_id]'][disabled]"
           )

    assert has_element?(view, "input[name='transaction[gross_amount]'][value='48.75']")
    assert has_element?(view, "input[name='transaction[taxes]'][value='8.61']")

    help = view |> element("#booking-edit-help") |> render() |> text()

    assert help =~
             "The kind and the cash account of a booked transaction are fixed; a booking of the wrong kind or on the wrong account is deleted and recorded again."

    assert has_element?(view, "#booking-edit-help button.link-button[phx-click='ask_delete']")
    refute has_element?(view, "[data-role='booking-imported']")

    view
    |> form("#transaction-form", %{
      "transaction" => %{
        "date" => "2026-10-05",
        "security_id" => to_string(security.id),
        "gross_amount" => "50.00",
        "taxes" => "8.75"
      }
    })
    |> render_submit()

    refute has_element?(view, "#booking-drawer")
    assert view |> element("#transactions-result") |> render() =~ "Transaction updated"
    assert Ledger.count_transactions() == count

    stored = Ledger.get_transaction(tx.id)
    assert stored.type == "dividend"
    assert stored.cash_account_id == world.cash.id
    assert Decimal.equal?(stored.gross_amount, d("50.00"))
    assert Decimal.equal?(stored.taxes, d("8.75"))
    assert Decimal.equal?(balance(world), d("1050.00"))

    entry = newest_entry(tx.id, :update)
    assert entry.actor_type == :owner_ui
    assert Decimal.equal?(d(entry.before["gross_amount"]), d("48.75"))
    assert Decimal.equal?(d(entry.after["gross_amount"]), d("50.00"))

    twin = dividend.()
    assert Decimal.equal?(balance(world), d("1098.75"))

    api =
      patch_json("/api/v1/transactions/#{twin.id}", %{
        "date" => "2026-10-05",
        "security_id" => security.id,
        "gross_amount" => "50.00",
        "taxes" => "8.75"
      })

    assert json_response(api, 200)
    assert Decimal.equal?(balance(world), d("1100.00"))

    assert Map.delete(stored_fields(Ledger.get_transaction(twin.id)), :import_hash) ==
             Map.delete(stored_fields(Ledger.get_transaction(tx.id)), :import_hash)
  end

  # User story (#1052, Sprint 21 α6; board 03, N12 A; the account fixes the
  # amount's currency):
  # As the operator correcting an imported dividend,
  # I want its kind and its cash account kept whatever the save carries,
  # and to be told what the next import does with my correction,
  # so that a correction never re-denominates a booking or changes what it
  # is.
  #
  # Acceptance criteria:
  # - An imported booking's edit carries one attention note: "This booking
  #   came from an import. Corrected here, it stays so: …".
  # - A save that carries another kind and another cash account changes
  #   the amount alone: the row stays a dividend on Test-Cash, its import
  #   hash kept, and Tagesgeld is untouched.
  test "an edit keeps the kind, the cash account and the import hash",
       %{conn: conn, world: world, security: security} do
    savings = add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")
    hash = String.duplicate("c3", 32)

    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          type: "dividend",
          portfolio_id: world.portfolio.id,
          security_id: security.id,
          cash_account_id: world.cash.id,
          gross_amount: "80.00",
          taxes: "12.00",
          currency_code: "EUR",
          date: ~D[2026-10-05]
        },
        import_hash: hash
      )

    view = open_edit(conn, tx)

    assert view |> element("[data-role='booking-imported']") |> render() |> text() =~
             "This booking came from an import. Corrected here, it stays so: a re-import of the same file does not book it again, and once its amount or taxes are changed, the import's correction names it as edited by hand."

    render_submit(view, "save_transaction", %{
      "transaction" => %{
        "type" => "fee",
        "cash_account_id" => to_string(savings.cash.id),
        "date" => "2026-10-05",
        "security_id" => to_string(security.id),
        "gross_amount" => "80.10",
        "taxes" => "12.00"
      }
    })

    stored = Ledger.get_transaction(tx.id)
    assert stored.type == "dividend"
    assert stored.cash_account_id == world.cash.id
    assert stored.import_hash == hash
    assert Decimal.equal?(stored.gross_amount, d("80.10"))

    balances = Ledger.cash_balances(portfolio_id: world.portfolio.id)
    assert Decimal.equal?(Map.fetch!(balances, world.cash.id), d("1080.10"))
    assert Map.get(balances, savings.cash.id) in [nil, d("0")]
  end

  # User story (#1052, Sprint 21 α6; board 03, found while drawing 3, and
  # the plan's D-6: transfers, deliveries and balance snapshots keep
  # delete-and-re-import):
  # As the operator opening Edit on a booking the cash form cannot carry,
  # I want the notes-only drawer, with a help line that names what the
  # screen books,
  # so that a corrected amount never sits beside a stale rate, and a
  # two-legged booking is never half-corrected.
  #
  # Acceptance criteria:
  # - A dividend booked in USD on the EUR account Test-Cash, with its rate
  #   stored, opens notes-only.
  # - A cash transfer opens notes-only, and its help line reads "the screen
  #   books buys, sells and cash bookings, not this kind".
  test "a booking in another currency than its account, and a transfer, stay notes-only",
       %{conn: conn, world: world} do
    usd = create_security!(name: "Wrenfield Gardens Corp", ticker: "WGC", currency: "USD")
    savings = add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")

    {:ok, foreign} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        type: "dividend",
        portfolio_id: world.portfolio.id,
        security_id: usd.id,
        cash_account_id: world.cash.id,
        gross_amount: "80.00",
        currency_code: "USD",
        settlement_fx_rate: "0.8",
        settlement_amount: "64.00",
        date: ~D[2026-10-05]
      })

    {:ok, transfer} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        type: "cash_transfer",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        counter_cash_account_id: savings.cash.id,
        gross_amount: "200.00",
        currency_code: "EUR",
        date: ~D[2026-10-06]
      })

    view = open_edit(conn, foreign)
    assert has_element?(view, "#note-form")
    refute has_element?(view, "#transaction-form")

    view = open_edit(conn, transfer)
    assert has_element?(view, "#note-form")

    assert view |> element("#booking-edit-help") |> render() |> text() =~
             "The date, amounts and accounts of this booking are fixed here; the screen books buys, sells and cash bookings, not this kind. The booking is corrected over the API or MCP, or it is deleted and booked again there."
  end

  # User story (#1052, Sprint 21 α6; board 03, N12 A, the German strings):
  # As the operator reading the page in German,
  # I want the cash form's direction and its sub line in German,
  # so that the new form reads like the rest of the drawer.
  #
  # Acceptance criteria:
  # - A tax refund to Test-Cash reads "Wird Test-Cash gutgeschrieben.", a
  #   fee "Wird von Test-Cash abgebucht.", and the amount "Betrag (EUR)".
  test "the cash form reads German", %{conn: conn, world: world} do
    german =
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

    view = open_kind(german, "tax_refund", %{"cash_account_id" => to_string(world.cash.id)})
    form = view |> element("#transaction-form") |> render() |> text()
    assert form =~ "Wird Test-Cash gutgeschrieben."
    assert form =~ "Betrag (EUR)"
    assert form =~ "Kein Wertpapier"

    assert view |> element("#booking-drawer .detail-pane-sub") |> render() |> text() =~
             "Bucht auf das gewählte Verrechnungskonto, in dessen Währung."

    view = open_kind(german, "fee", %{"cash_account_id" => to_string(world.cash.id)})

    assert view |> element("[data-role='cash-direction']") |> render() |> text() =~
             "Wird von Test-Cash abgebucht."
  end
end
