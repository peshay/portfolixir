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

  defp insert_below_ledger!(row) do
    {:ok, row} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])
        Repo.insert!(row)
      end)

    row
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
