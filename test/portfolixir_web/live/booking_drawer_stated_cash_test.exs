defmodule PortfolixirWeb.BookingDrawerStatedCashTest do
  # ADR-0053, amendment of 2026-11-02 (#1371; board
  # ux-design-2026-11-02-sprint23/02 ①a): the booking drawer shows the cash
  # of a buy or sell that stores it and has no settlement legs, prefills it
  # with what changed figures derive, and saves what the field states. Risk
  # tier (ADR-0036): every stored figure is pinned with an exact Decimal.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @note "Menge, Preis, Gebühren, Steuern oder Kauf/Verkauf geändert: Der Betrag folgt nicht von selbst. " <>
          "Vorgeschlagen sind 816,00 = 10 × 81,00 + 5,00 + 1,00. Speichern übernimmt, was im " <>
          "Feld steht — den abgerechneten Betrag eintragen, wenn er abweicht."

  # Synthetic figures only (#1371's example): an imported buy, 10 at 80.00
  # EUR, fees 5.00, taxes 1.00, its cash 806.00 as the file stated it.
  setup do
    world = base_world(name: "Drawer Cash", cash_name: "DC Cash", depot_name: "DC Depot")
    security = create_security!(name: "Drawer Cash Co", ticker: "DCC", currency: "EUR")

    {:ok, buy} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-04-15],
          quantity: "10",
          price: "80.00",
          fees: "5.00",
          taxes: "1.00",
          currency_code: "EUR",
          gross_amount: "806.00"
        },
        import_hash: String.duplicate("d", 64)
      )

    %{world: world, security: security, buy: buy}
  end

  defp open_edit(conn, id) do
    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    render_click(view, "edit_transaction", %{"id" => to_string(id)})
    view
  end

  defp form_inputs(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#transaction-form input")
    |> Map.new(fn input ->
      {input |> Floki.attribute("name") |> List.first(),
       input |> Floki.attribute("value") |> List.first()}
    end)
  end

  # The fields the browser sends: the form's inputs (the cash field among
  # them), the selects as stored, overlaid with what the operator typed.
  defp params(view, world, security, overrides) do
    view
    |> form_inputs()
    |> Enum.flat_map(fn
      {"transaction[" <> rest, value} -> [{String.trim_trailing(rest, "]"), value}]
      _other -> []
    end)
    |> Map.new()
    |> Map.merge(%{
      "type" => "buy",
      "date" => "2026-04-15",
      "securities_account_id" => to_string(world.depot.id),
      "security_id" => to_string(security.id),
      "notes" => ""
    })
    |> Map.merge(overrides)
  end

  defp change(view, world, security, field, value) do
    render_change(view, "form_changed", %{
      "_target" => ["transaction", field],
      "transaction" => params(view, world, security, %{field => value})
    })
  end

  defp submit(view, world, security, overrides \\ %{}) do
    view
    |> element("#transaction-form")
    |> render_submit(%{"transaction" => params(view, world, security, overrides)})
  end

  defp stored(id), do: Repo.get!(Transaction, id)

  defp text(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Floki.text()
    |> String.split()
    |> Enum.join(" ")
  end

  # User story (#1371):
  # As the operator correcting the price of an imported buy in the drawer,
  # I want to see the cash it stores, prefilled with what the new figures
  # give and saved as the field states,
  # so that a typo fix never leaves the cash and the lot reading two costs,
  # and the amount the broker settled can still be entered.
  #
  # Acceptance criteria (board 02 ①a, ADR-0053 amendment of 2026-11-02):
  # - The drawer shows "Betrag (EUR)" holding the stored 806, with the help
  #   "Das Geld, das das Konto bewegt. Gespeichert: 806,00 (wie importiert)."
  #   and no attention note.
  # - A price edit to 81 prefills the field with 816,00 and shows the
  #   attention note naming the sum.
  # - Saving without touching the field stores price 81.00 and cash 816.00.
  test "the same edit in the drawer saves 816.00 unless the operator changes the field",
       %{conn: conn, world: w, security: s, buy: buy} do
    view = open_edit(conn, buy.id)

    assert has_element?(view, "#transaction-form label span", "Betrag (EUR)")
    assert form_inputs(view)["transaction[gross_amount]"] == "806"

    assert text(view, ~s([data-role="stored-cash-help"])) ==
             "Das Geld, das das Konto bewegt. Gespeichert: 806,00 (wie importiert)."

    refute has_element?(view, ~s([data-role="cash-restate"]))

    change(view, w, s, "price", "81")

    assert form_inputs(view)["transaction[gross_amount]"] == "816,00"
    assert text(view, ~s([data-role="cash-restate"])) =~ @note

    submit(view, w, s)

    row = stored(buy.id)
    assert Decimal.equal?(row.price, Decimal.new("81.00"))
    assert Decimal.equal?(row.gross_amount, Decimal.new("816.00"))
  end

  # Acceptance criteria:
  # - The field the operator overwrites with the amount settled within a
  #   cent is stored as typed.
  # - A figure off by more than its tolerance (a cent: the price the edit
  #   sets is exact) is refused with the field's own
  #   error, the expected figure in German notation, and nothing moves.
  test "the field states the cash: within its tolerance saved, beyond it refused",
       %{conn: conn, world: w, security: s, buy: buy} do
    view = open_edit(conn, buy.id)
    change(view, w, s, "price", "81")
    submit(view, w, s, %{"gross_amount" => "806,00"})

    assert text(view, "#tx-error-gross_amount") ==
             "passt nicht zu Menge × Preis, Gebühren und Steuern — erwartet 816,00"

    assert Decimal.equal?(stored(buy.id).gross_amount, Decimal.new("806.00"))
    assert Decimal.equal?(stored(buy.id).price, Decimal.new("80.00"))

    # A blank field states no cash: the ledger's first refusal, which
    # names buy/sell among the changes that need it.
    submit(view, w, s, %{"gross_amount" => ""})

    assert text(view, "#tx-error-gross_amount") ==
             "ist anzugeben, wenn sich Menge, Preis, Gebühren, Steuern oder Kauf/Verkauf " <>
               "einer Buchung ändern, die ihren Betrag speichert"

    submit(view, w, s, %{"gross_amount" => "816,01"})
    assert Decimal.equal?(stored(buy.id).gross_amount, Decimal.new("816.01"))
  end

  # Acceptance criteria (the amendment's point 1, "on every write"; the
  # sprint PR's closing act):
  # - A cash typed alone is checked against the stored figures: 5000,00 is
  #   refused with the field's error naming 806,00 and nothing moves;
  #   806,04, within the stored price's rounding, is stored.
  test "a cash typed alone is checked against the stored figures",
       %{conn: conn, world: w, security: s, buy: buy} do
    view = open_edit(conn, buy.id)
    submit(view, w, s, %{"gross_amount" => "5000,00"})

    assert text(view, "#tx-error-gross_amount") ==
             "passt nicht zu Menge × Preis, Gebühren und Steuern — erwartet 806,00"

    assert Decimal.equal?(stored(buy.id).gross_amount, Decimal.new("806.00"))

    submit(view, w, s, %{"gross_amount" => "806,04"})
    assert Decimal.equal?(stored(buy.id).gross_amount, Decimal.new("806.04"))
  end

  # Acceptance criteria:
  # - A note edit keeps the stored cash: the field sends it unchanged.
  # - A booking without a stored cash shows no cash field; its price edit
  #   saves as before.
  test "a note edit keeps the cash; a booking without one shows no field",
       %{conn: conn, world: w, security: s, buy: buy} do
    view = open_edit(conn, buy.id)
    submit(view, w, s, %{"notes" => "checked against the statement"})

    assert stored(buy.id).notes == "checked against the statement"
    assert Decimal.equal?(stored(buy.id).gross_amount, Decimal.new("806.00"))

    plain = buy!(w, s, quantity: "2", price: "50", date: ~D[2026-04-16])
    view = open_edit(conn, plain.id)

    refute Map.has_key?(form_inputs(view), "transaction[gross_amount]")
    refute has_element?(view, ~s([data-role="stored-cash-help"]))

    submit(view, w, s, %{"price" => "51", "date" => "2026-04-16"})
    assert Decimal.equal?(stored(plain.id).price, Decimal.new("51"))
    assert is_nil(stored(plain.id).gross_amount)
  end

  # Acceptance criteria (ADR-0053's amendment, point 1, "on every write"):
  # - Turning the buy into a sell prefills the cash the sale's figures give,
  #   10 × 80,00 − 5,00 − 1,00 = 794,00, shows the attention note with the
  #   sale's sum (the closing act: a type change is noted as a figure change
  #   is), and the save stores it.
  test "a buy turned into a sell prefills and saves the sale's cash",
       %{conn: conn, world: w, security: s, buy: buy} do
    view = open_edit(conn, buy.id)
    change(view, w, s, "type", "sell")

    assert form_inputs(view)["transaction[gross_amount]"] == "794,00"
    assert text(view, ~s([data-role="cash-restate"])) =~ "794,00 = 10 × 80,00 − 5,00 − 1,00"

    submit(view, w, s, %{"type" => "sell"})

    row = stored(buy.id)
    assert row.type == "sell"
    assert Decimal.equal?(row.gross_amount, Decimal.new("794.00"))
  end

  # Acceptance criteria (the sprint PR's closing act, #1371):
  # - A figure typed and changed back to the stored one puts the stored cash
  #   back in the field (an imported buy, 7 at 14,29 for a cash of 100,00,
  #   whose figures derive 100,03): no note, and a date-only save keeps
  #   100.00, the broker's figure, never the derived one.
  test "a figure changed and changed back puts the stored cash back",
       %{conn: conn, world: w, security: s} do
    {:ok, row} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          portfolio_id: w.portfolio.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          security_id: s.id,
          type: "buy",
          date: ~D[2026-04-20],
          quantity: "7",
          price: "14.29",
          currency_code: "EUR",
          gross_amount: "100.00"
        },
        import_hash: String.duplicate("e", 64)
      )

    view = open_edit(conn, row.id)
    change(view, w, s, "price", "14,3")
    assert form_inputs(view)["transaction[gross_amount]"] == "100,10"

    change(view, w, s, "price", "14,29")

    assert form_inputs(view)["transaction[gross_amount]"] == "100,00"
    refute has_element?(view, ~s([data-role="cash-restate"]))

    submit(view, w, s, %{"date" => "2026-04-21"})

    stored = stored(row.id)
    assert stored.date == ~D[2026-04-21]
    assert Decimal.equal?(stored.price, Decimal.new("14.29"))
    assert Decimal.equal?(stored.gross_amount, Decimal.new("100.00"))
  end

  # Acceptance criteria (a sell's cash is net of fees and taxes):
  # - Its note names the sum with minus signs and the prefilled figure is
  #   4 × 91,00 − 3,00 − 2,50 = 358,50.
  test "a sell's suggestion subtracts its fees and taxes",
       %{conn: conn, world: w, security: s} do
    {:ok, sell} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: s.id,
        type: "sell",
        date: ~D[2026-05-04],
        quantity: "4",
        price: "90.00",
        fees: "3.00",
        taxes: "2.50",
        currency_code: "EUR",
        gross_amount: "354.50"
      })

    view = open_edit(conn, sell.id)

    assert text(view, ~s([data-role="stored-cash-help"])) ==
             "Das Geld, das das Konto bewegt. Gespeichert: 354,50."

    render_change(view, "form_changed", %{
      "_target" => ["transaction", "price"],
      "transaction" =>
        view
        |> params(w, s, %{"price" => "91"})
        |> Map.merge(%{"type" => "sell", "date" => "2026-05-04"})
    })

    assert form_inputs(view)["transaction[gross_amount]"] == "358,50"
    assert text(view, ~s([data-role="cash-restate"])) =~ "358,50 = 4 × 91,00 − 3,00 − 2,50"
  end
end
