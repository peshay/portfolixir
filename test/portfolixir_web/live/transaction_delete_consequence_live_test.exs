defmodule PortfolixirWeb.TransactionDeleteConsequenceLiveTest do
  # Sprint 18 U1 (#912), pick H2 = A, state A2 (board
  # `ux-design-2026-10-02/02-booking-delete`), and the closing act's repairs
  # (board `ux-review-2026-10-03/02-delete-dialog-repairs`): the delete
  # dialog's sentence "Afterwards …" says what changes, concretely. These
  # cases pin what it says where a later booking shapes the answer — a split
  # after the booking, a balance set after it — and for the kinds whose
  # legs read differently.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  setup do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    deposit!(world, "5000", ~D[2026-08-03])
    %{world: world, security: security}
  end

  defp split!(security, numerator, denominator, date) do
    {:ok, rows} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: numerator,
        ratio_denominator: denominator
      })

    rows
  end

  defp consequence(conn, tx) do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-delete-#{tx.id}") |> render_click()
    view |> element("[data-role='booking-delete-consequence']") |> render() |> text()
  end

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.replace(~r/\s+/, " ")

  # User story (U1, #912; H2-A, A2; the closing act, R1):
  # As the operator deleting a buy that a later split scaled,
  # I want the dialog to say how many units the depot holds less today,
  # so that the sentence matches what the holdings show after the delete.
  #
  # Acceptance criteria:
  # - A buy of 10 before a 2:1 split says the depot holds 20 fewer units.
  # - A sell of 4 before a 2:1 split says the depot holds 8 more units.
  # - The cash leg keeps the cash the booking moved.
  test "a booking before a split states the quantity at today's count",
       %{conn: conn, world: world, security: security} do
    buy = buy!(world, security, quantity: "10", price: "80", date: ~D[2026-09-01])
    sell = sell!(world, security, quantity: "4", price: "90", date: ~D[2026-09-05])
    split!(security, 2, 1, ~D[2026-09-15])

    assert consequence(conn, buy) =~
             "Afterwards Depot 1 holds 20 fewer units of Kestrel Robotik SE, and Girokonto has 800.00 EUR more."

    assert consequence(conn, sell) =~
             "Afterwards Depot 1 holds 8 more units of Kestrel Robotik SE, and Girokonto has 360.00 EUR less."
  end

  # User story (U1, #912; H2-A, A2; the closing act, R1):
  # As the operator deleting a transfer between my own depots before a
  # split,
  # I want each depot's change stated at today's count,
  # so that both sides of the move read as the holdings will show them.
  #
  # Acceptance criteria:
  # - A transfer of 3 from Depot 1 to Depot 2 before a 2:1 split says Depot 1
  #   holds 6 more units and Depot 2 holds 6 fewer.
  test "a security transfer before a split states both depots at today's count",
       %{conn: conn, world: world, security: security} do
    savings = add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")
    buy!(world, security, quantity: "10", price: "80", date: ~D[2026-09-01])

    {:ok, moved} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        type: "security_transfer",
        portfolio_id: world.portfolio.id,
        security_id: security.id,
        securities_account_id: world.depot.id,
        counter_securities_account_id: savings.depot.id,
        quantity: "3",
        currency_code: "EUR",
        date: ~D[2026-09-05]
      })

    split!(security, 2, 1, ~D[2026-09-15])

    assert consequence(conn, moved) =~
             "Afterwards Depot 1 holds 6 more units of Kestrel Robotik SE, and Depot 2 holds 6 fewer units of Kestrel Robotik SE."
  end

  # User story (U1, #912; H2-A, A2; the closing act, R1):
  # As the operator deleting a buy that a later reverse split shrank,
  # I want the dialog not to overstate what the depot loses,
  # so that I can trust the figure before I confirm.
  #
  # Acceptance criteria:
  # - A buy of 10 before a 1:2 reverse split says 5 fewer units.
  test "a booking before a reverse split states the quantity at today's count",
       %{conn: conn, world: world, security: security} do
    buy = buy!(world, security, quantity: "10", price: "80", date: ~D[2026-09-01])
    split!(security, 1, 2, ~D[2026-09-15])

    assert consequence(conn, buy) =~
             "Afterwards Depot 1 holds 5 fewer units of Kestrel Robotik SE, and Girokonto has 800.00 EUR more."
  end
end
