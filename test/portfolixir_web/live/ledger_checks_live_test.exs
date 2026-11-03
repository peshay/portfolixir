defmodule PortfolixirWeb.LedgerChecksLiveTest do
  # Sprint 23 V1 (R6 of Sprint 22, #1292 and #1290; R2's check, #1371): the
  # three ledger checks the agent reads over the API get their human view.
  # Board ux-design-2026-11-02-sprint23/01 ①a, picks Q1 = A (the Overview's
  # data-quality line) and Q2 = problem: each check above zero is one
  # finding on the line, its link opens the history filtered to exactly the
  # read's rows (`/transactions?dq=…`), and a clamped problem note above
  # them carries the read's note and remedy in the operator's words.
  #
  # The agent's lens (plan, "What done means"): each count equals its
  # read's row count, and each filter shows the read's own ids.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  defp german(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp roles(view) do
    view
    |> element("#dashboard-dq-line")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("[data-role]", "data-role")
  end

  defp read_rows(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> get_in(["data", "rows"])
  end

  defp history_ids(view) do
    view
    |> element("#transaction-list")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("tr[data-transaction]", "data-transaction")
    |> Enum.map(&String.to_integer/1)
    |> Enum.sort()
  end

  defp overview(conn) do
    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    view
  end

  # A buy stored before ADR-0053's amendment of 2026-11-02 (an old edit),
  # inserted below the ledger as R2's own tests store one: #1371's example,
  # 10 × 81.00 + 5.00 + 1.00 = 816.00 against a stored cash of 806.00.
  defp insert_edited_trade!(world, security, date, gross_amount) do
    insert_below_ledger!(%Transaction{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      cash_account_id: world.cash.id,
      security_id: security.id,
      type: "buy",
      date: date,
      quantity: Decimal.new("10"),
      price: Decimal.new("81.00"),
      fees: Decimal.new("5.00"),
      taxes: Decimal.new("1.00"),
      currency_code: "EUR",
      gross_amount: Decimal.new(gross_amount)
    })
  end

  # A USD buy on a EUR account with its rate and neither amount, the shape
  # H35 refuses on a new write: 10 × 200.00 × 0.93 + 4.90 = 1,864.90 EUR.
  defp insert_rate_only!(world, security, date) do
    insert_below_ledger!(%Transaction{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      cash_account_id: world.cash.id,
      security_id: security.id,
      type: "buy",
      date: date,
      quantity: Decimal.new("10"),
      price: Decimal.new("200.00"),
      fees: Decimal.new("4.90"),
      taxes: Decimal.new("0"),
      currency_code: "USD",
      settlement_fx_rate: Decimal.new("0.93")
    })
  end

  defp insert_below_ledger!(row) do
    {:ok, row} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])
        Repo.insert!(row)
      end)

    row
  end

  # Two portfolios hold "Wexmoor Instruments AG"; the split books only the
  # first, so "Family Depot" (12 shares) is missing (the board's example).
  defp incomplete_split! do
    security = create_security!(name: "Wexmoor Instruments AG", ticker: "WXM", currency: "EUR")
    a = base_world(name: "Main Depot", cash_name: "Main Cash", depot_name: "Main Securities")

    b =
      base_world(name: "Family Depot", cash_name: "Family Cash", depot_name: "Family Securities")

    buy!(a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(b, security, quantity: "12", price: "100", date: ~D[2026-01-02])

    {:ok, split} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          portfolio_id: a.portfolio.id,
          security_id: security.id,
          type: "split",
          date: ~D[2026-04-16],
          currency_code: "EUR",
          split_ratio_numerator: 2,
          split_ratio_denominator: 1
        },
        split_flow: true
      )

    {security, split}
  end

  # User story (Sprint 23 V1; #1371, ADR-0053 amendment of 2026-11-02):
  # As the operator reading the Overview,
  # I want the buys and sells whose stored cash misses their figures named on
  # the data-quality line, with a link to exactly those bookings,
  # so that a cash balance and a cost that read two amounts are visible
  # without the agent's read, and the booking form's Edit is one click away.
  #
  # Acceptance criteria:
  # - Above zero the line names "eine Buchung, deren Betrag nicht zu Menge ×
  #   Preis, Gebühren und Steuern passt" with its effect "— Kontostand und
  #   Einstand lesen daher verschiedene Beträge", linking to
  #   /transactions?dq=cash_mismatch; the count equals the read's rows.
  # - The line takes the problem severity, before the stale quote's
  #   attention.
  # - The filtered history shows exactly the read's ids, a clamped problem
  #   note with the read's note and remedy and „Alle Buchungen zeigen“, and
  #   the row's second line „aus den Zahlen: 816,00“.
  test "a cash mismatch is a problem finding that opens the history on exactly its rows",
       %{conn: conn} do
    world = base_world(name: "Cash World", cash_name: "Round Trip Cash", depot_name: "CW Depot")
    arbolia = create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "EUR")
    edited = insert_edited_trade!(world, arbolia, ~D[2026-04-16], "806.00")
    _within = insert_edited_trade!(world, arbolia, ~D[2026-04-17], "816.01")
    other = buy!(world, arbolia, quantity: "1", price: "80", date: ~D[2026-04-18])

    rows = read_rows(conn, "/api/v1/transactions/cash_mismatch")
    assert Enum.map(rows, & &1["id"]) == [edited.id]

    view = overview(german(conn))

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-cash-mismatch"][href="/transactions?dq=cash_mismatch"])
           )

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-cash-mismatch"])) ==
             "eine Buchung, deren Betrag nicht zu Menge × Preis, Gebühren und Steuern passt"

    assert text(view, ~s(#dashboard-dq-line [data-effect-of="dq-cash-mismatch"])) ==
             "— Kontostand und Einstand lesen daher verschiedene Beträge"

    # The stale quote (attention) stands on the line too; the problem wins.
    assert "dq-quotes" in roles(view)
    assert has_element?(view, "#dashboard-data-quality .data-note--problem")
    refute has_element?(view, "#dashboard-data-quality .data-note--attention")

    {:ok, history, _html} = live(german(conn), "/transactions?dq=cash_mismatch")

    assert history_ids(history) == Enum.map(rows, & &1["id"])
    refute has_element?(history, ~s(tr[data-transaction="#{other.id}"]))

    assert has_element?(history, "#transaction-dq-note.data-note--problem.data-note--clamped")

    assert text(history, "#transaction-dq-note-text") ==
             "Gefiltert: 1 Kauf oder Verkauf, dessen Betrag nicht zu Menge × Preis, Gebühren " <>
               "und Steuern passt — Kontostand und Einstand lesen daher verschiedene Beträge. " <>
               "Den Betrag im Buchungsformular angeben (Bearbeiten): den abgerechneten, oder " <>
               "den, den die Zahlen ergeben. Nichts wird automatisch geändert."

    assert has_element?(
             history,
             ~s(#transaction-dq-note .data-note__actions a[href="/transactions"]),
             "Alle Buchungen zeigen"
           )

    assert text(history, ~s(tr[data-transaction="#{edited.id}"] [data-role="dq-figure"])) ==
             "aus den Zahlen: 816,00"

    assert text(history, ~s(li[data-transaction="#{edited.id}"] [data-role="dq-figure"])) ==
             "aus den Zahlen: 816,00"

    {:ok, history, _html} = live(conn, "/transactions?dq=cash_mismatch")

    assert text(history, "#transaction-dq-note-text") =~
             "Filtered: 1 buy or sell whose cash misses its quantity × price, fees and taxes — " <>
               "so the cash balance and the cost read different amounts. State the cash in " <>
               "the booking form (Edit)"

    assert text(history, ~s(tr[data-transaction="#{edited.id}"] [data-role="dq-figure"])) ==
             "from its figures: 816.00"
  end

  # User story (Sprint 23 V1; #1290, H35, T-19):
  # As the operator reading the Overview,
  # I want the cross-currency buys and sells with a rate and no cash named
  # on the data-quality line, with a link to exactly those bookings,
  # so that a trade whose quantity × price lands unconverted on the account
  # is seen and corrected with the amount settled.
  #
  # Acceptance criteria:
  # - Above zero the line names "ein Kauf oder Verkauf in Fremdwährung mit
  #   Wechselkurs, aber ohne Betrag" with "— er bucht Menge × Preis ohne
  #   Umrechnung aufs Konto", linking to /transactions?dq=rate_only, at
  #   problem severity; two read in the plural; the count equals the read's.
  # - The filtered history shows exactly the read's ids, the note in the
  #   operator's words, and the row's second line „Abrechnungsbetrag zum
  #   eigenen Kurs 0,93: 1.860,00 EUR“ (quantity × price at its own rate, in
  #   the account's currency: the figure the drawer's settlement field takes,
  #   which with the 4,90 fees books the read's expected_cash, 1.864,90).
  test "a rate-only trade is a problem finding that opens the history on exactly its rows",
       %{conn: conn} do
    world = base_world(name: "Rate World", cash_name: "Demo Cash", depot_name: "Rate Depot")
    larkspur = create_security!(name: "Larkspur Robotics Inc", ticker: "LRK", currency: "USD")
    first = insert_rate_only!(world, larkspur, ~D[2026-06-05])
    eur = create_security!(name: "Plain Euro Co", ticker: "PEC", currency: "EUR")
    other = buy!(world, eur, quantity: "1", price: "50", date: ~D[2026-06-06])

    rows = read_rows(conn, "/api/v1/transactions/rate_only")
    assert Enum.map(rows, & &1["id"]) == [first.id]
    assert hd(rows)["expected_cash"] == "1864.9"

    view = overview(german(conn))

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-rate-only"][href="/transactions?dq=rate_only"]),
             "ein Kauf oder Verkauf in Fremdwährung mit Wechselkurs, aber ohne Betrag"
           )

    assert text(view, ~s(#dashboard-dq-line [data-effect-of="dq-rate-only"])) ==
             "— er bucht Menge × Preis ohne Umrechnung aufs Konto"

    assert has_element?(view, "#dashboard-data-quality .data-note--problem")

    {:ok, history, _html} = live(german(conn), "/transactions?dq=rate_only")

    assert history_ids(history) == [first.id]
    refute has_element?(history, ~s(tr[data-transaction="#{other.id}"]))

    assert text(history, "#transaction-dq-note-text") ==
             "Gefiltert: 1 Kauf oder Verkauf in Fremdwährung mit Wechselkurs, aber ohne Betrag " <>
               "— das Hauptbuch bucht Menge × Preis mit Gebühren und Steuern in der Währung des " <>
               "Wertpapiers als Bargeld des Kontos und wendet den Kurs nie an. Den " <>
               "Abrechnungsbetrag im Buchungsformular eintragen (Bearbeiten): den Betrag vor " <>
               "Gebühren und Steuern, aus dem das Formular das Bargeld bucht; das Nachladen der " <>
               "Wechselkurse ändert diese Buchungen nicht. Nichts wird automatisch geändert."

    assert text(history, ~s(tr[data-transaction="#{first.id}"] [data-role="dq-figure"])) ==
             "Abrechnungsbetrag zum eigenen Kurs 0,93: 1.860,00 EUR"

    # A second one: the count and the plural follow the read.
    second = insert_rate_only!(world, larkspur, ~D[2026-06-07])
    rows = read_rows(conn, "/api/v1/transactions/rate_only")
    assert length(rows) == 2

    view = overview(german(conn))

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-rate-only"])) ==
             "2 Käufe oder Verkäufe in Fremdwährung mit Wechselkurs, aber ohne Betrag"

    assert text(view, ~s(#dashboard-dq-line [data-effect-of="dq-rate-only"])) ==
             "— sie buchen Menge × Preis ohne Umrechnung aufs Konto"

    {:ok, history, _html} = live(conn, "/transactions?dq=rate_only")
    assert history_ids(history) == Enum.sort([first.id, second.id])

    assert text(history, "#transaction-dq-note-text") =~
             "Filtered: 2 cross-currency buys or sells"

    assert text(history, ~s(tr[data-transaction="#{second.id}"] [data-role="dq-figure"])) ==
             "settlement amount at its own rate 0.93: 1,860.00 EUR"
  end

  # User story (Sprint 23 V1, #1290; stacked PR closing act, S1):
  # As the operator repairing a rate-only trade from the filtered history,
  # I want the row's second line to give the figure for the field the
  # booking drawer offers, under that field's name,
  # so that following the screen books what the agent's documented PATCH
  # books, and the check then reads clean.
  #
  # Acceptance criteria:
  # - The second line reads „Abrechnungsbetrag zum eigenen Kurs 0,93:
  #   1.860,00 EUR“ — quantity × price at the row's own rate, before the
  #   4,90 fees — and the note's remedy names „Abrechnungsbetrag“.
  # - The drawer opens with the stored rate in its Kurs field (0,93) and
  #   offers „Abrechnungsbetrag (EUR)“; the shown figure typed there and
  #   saved stores a cash of exactly 1864.90 at the rate 0.93 — what
  #   `PATCH gross_amount "1864.9"` (the read's expected_cash) stores on a
  #   twin row — and the rate_only read is then empty.
  test "following the rate-only hint in the drawer books what the agent's PATCH books",
       %{conn: conn} do
    world = base_world(name: "Rate World", cash_name: "Demo Cash", depot_name: "Rate Depot")
    larkspur = create_security!(name: "Larkspur Robotics Inc", ticker: "LRK", currency: "USD")
    operators = insert_rate_only!(world, larkspur, ~D[2026-06-05])
    agents = insert_rate_only!(world, larkspur, ~D[2026-06-06])

    # The agent's route: the documented amount, the read's expected_cash.
    [_, agent_row] = read_rows(conn, "/api/v1/transactions/rate_only")
    assert agent_row["id"] == agents.id

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> patch(
      "/api/v1/transactions/#{agents.id}",
      Jason.encode!(%{"transaction" => %{"gross_amount" => agent_row["expected_cash"]}})
    )
    |> json_response(200)

    # The operator's route: the screen, read literally.
    {:ok, history, _html} = live(german(conn), "/transactions?dq=rate_only")
    line = text(history, ~s(tr[data-transaction="#{operators.id}"] [data-role="dq-figure"]))
    assert line == "Abrechnungsbetrag zum eigenen Kurs 0,93: 1.860,00 EUR"
    assert text(history, "#transaction-dq-note-text") =~ "Den Abrechnungsbetrag"

    [_, field, shown] = Regex.run(~r/^(\S+) zum eigenen Kurs [\d,]+: ([\d.,]+) EUR$/u, line)

    render_click(history, "edit_transaction", %{"id" => to_string(operators.id)})
    assert has_element?(history, "#settlement-fieldset label span", field <> " (EUR)")

    assert history
           |> element(~s(#settlement-fieldset input[name="transaction[settlement_fx_rate]"]))
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.attribute("value") == ["0,93"]

    # The drawer's decimal fields take no thousands separator (#869), so
    # the figure goes in as the field reads it: 1860,00.
    typed = String.replace(shown, ".", "")

    history
    |> form("#transaction-form", transaction: %{settlement_amount: typed})
    |> render_change(%{"_target" => ["transaction", "settlement_amount"]})

    history |> form("#transaction-form") |> render_submit()

    operator_booking = Repo.get!(Transaction, operators.id)
    agent_booking = Repo.get!(Transaction, agents.id)

    assert Decimal.equal?(agent_booking.gross_amount, Decimal.new("1864.90"))
    assert Decimal.equal?(operator_booking.gross_amount, agent_booking.gross_amount)
    assert Decimal.equal?(operator_booking.settlement_fx_rate, Decimal.new("0.93"))
    assert Decimal.equal?(agent_booking.settlement_fx_rate, Decimal.new("0.93"))
    assert read_rows(conn, "/api/v1/transactions/rate_only") == []
  end

  # User story (Sprint 23 V1; #1292):
  # As the operator reading the Overview,
  # I want the split events missing a portfolio that held the security named
  # on the data-quality line, with a link to exactly the event's rows,
  # so that lots split while the holding is not are seen, with the way to
  # repair them.
  #
  # Acceptance criteria:
  # - Above zero the line names "ein Split, dem ein Portfolio fehlt, das das
  #   Wertpapier hielt" with "— dort sind die Lots geteilt, der Bestand
  #   nicht", linking to /transactions?dq=incomplete_split, at problem
  #   severity; the count equals the read's rows (events).
  # - The filtered history shows exactly the read's transaction_ids, and
  #   the note names the security, ratio, date, the missing portfolio and
  #   its shares before, with „Split erfassen“ on the security beside „Alle
  #   Buchungen zeigen“.
  test "an incomplete split is a problem finding that opens the history on its rows",
       %{conn: conn} do
    {security, split} = incomplete_split!()

    rows = read_rows(conn, "/api/v1/splits/incomplete")
    assert length(rows) == 1
    ids = rows |> Enum.flat_map(& &1["transaction_ids"]) |> Enum.sort()
    assert ids == [split.id]

    view = overview(german(conn))

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-incomplete-split"][href="/transactions?dq=incomplete_split"]),
             "ein Split, dem ein Portfolio fehlt, das das Wertpapier hielt"
           )

    assert text(view, ~s(#dashboard-dq-line [data-effect-of="dq-incomplete-split"])) ==
             "— dort sind die Lots geteilt, der Bestand nicht"

    assert has_element?(view, "#dashboard-data-quality .data-note--problem")

    {:ok, history, _html} = live(german(conn), "/transactions?dq=incomplete_split")

    assert history_ids(history) == ids

    assert text(history, "#transaction-dq-note-text") ==
             "Gefiltert: 1 Split, dem ein Portfolio fehlt — Wexmoor Instruments AG · 2:1 · " <>
               "16.04.2026: es fehlt „Family Depot“, das vorher 12 Stück hielt. Dort sind die " <>
               "FIFO-Lots geteilt, der Bestand nicht. Den Split mit demselben Datum und " <>
               "Verhältnis erneut erfassen („Split erfassen“ beim Wertpapier): Er ergänzt nur " <>
               "die fehlenden Zeilen. Ist der Split falsch, den ganzen Split löschen. Nichts " <>
               "wird automatisch geändert."

    assert has_element?(
             history,
             ~s(#transaction-dq-note .data-note__actions a[href="/securities/#{security.id}"]),
             "Split erfassen"
           )

    assert has_element?(
             history,
             ~s(#transaction-dq-note .data-note__actions a[href="/transactions"]),
             "Alle Buchungen zeigen"
           )

    {:ok, history, _html} = live(conn, "/transactions?dq=incomplete_split")

    assert text(history, "#transaction-dq-note-text") =~
             "Filtered: 1 split missing a portfolio — Wexmoor Instruments AG · 2:1 · " <>
               "2026-04-16: “Family Depot”, which held 12 shares before, is missing."
  end

  # Acceptance criteria (Sprint 23 V1, at zero):
  # - With none of the three checks above zero, none of their findings is on
  #   the line, and each read is empty.
  # - An unknown dq value is ignored: the whole history, no note.
  # - A known dq value whose check finds nothing shows no problem note.
  test "at zero the findings are absent and an unknown dq value filters nothing",
       %{conn: conn} do
    world = base_world(name: "Clean World")
    security = create_security!(name: "Clean Co", ticker: "CLN", currency: "EUR")
    clean = buy!(world, security, quantity: "2", price: "10", date: ~D[2026-03-02])

    for path <- [
          "/api/v1/transactions/cash_mismatch",
          "/api/v1/transactions/rate_only",
          "/api/v1/splits/incomplete"
        ] do
      assert read_rows(conn, path) == []
    end

    view = overview(conn)

    for role <- ["dq-cash-mismatch", "dq-rate-only", "dq-incomplete-split"] do
      refute has_element?(view, ~s(#dashboard-dq-line [data-role="#{role}"]))
      refute has_element?(view, ~s(#dashboard-dq-line [data-effect-of="#{role}"]))
    end

    {:ok, history, _html} = live(conn, "/transactions?dq=no_such_check")
    assert history_ids(history) == [clean.id]
    refute has_element?(history, "#transaction-dq-note")

    {:ok, history, _html} = live(conn, "/transactions?dq=cash_mismatch")
    refute has_element?(history, "#transaction-dq-note.data-note--problem")
    refute has_element?(history, ~s(tr[data-transaction="#{clean.id}"]))
  end
end
