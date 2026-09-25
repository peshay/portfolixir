defmodule PortfolixirWeb.TransactionSplitEditLiveTest do
  # E25 S6 (#891), G07, pick G12.3 = A (board 12, `12-e25-new-marks`): the
  # history's "Edit" on a booked split row used to open the full booking
  # drawer — "Buy", an empty quantity and price, a depot the row does not
  # have — and a save there went past the split flow's checks. The drawer
  # now shows the split's facts fixed and only its note editable, with one
  # help line naming how a wrong split is corrected, and no link.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  setup do
    world = base_world(name: "Split Edit World", cash_name: "SE Cash", depot_name: "SE Depot")
    security = create_security!(name: "Nordic Split Timber", ticker: "NST")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    {:ok, [split]} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-02-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    %{world: world, security: security, split: split}
  end

  defp open_split_edit(conn, split) do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{split.id}") |> render_click()
    view |> element("#tx-edit-#{split.id}") |> render_click()
    view
  end

  # User story:
  # As the operator opening "Edit" on a booked split,
  # I want to see the split's own facts, fixed, and to change only its note,
  # so that a split never moves past the checks that booked it, and I read
  # how a wrong one is corrected where I tried to correct it.
  #
  # Acceptance criteria:
  # - The drawer shows type Split, the effective date, the security and the
  #   ratio as disabled fields, and no depot, quantity or price.
  # - One help line states the limit and names API and MCP, with no link.
  # - "Save note" stores the note, journaled, and leaves the facts unchanged.
  test "a split row's edit shows its facts fixed and saves only the note",
       %{conn: conn, security: security, split: split} do
    view = open_split_edit(conn, split)

    assert has_element?(view, "dialog#booking-drawer #split-note-form")
    refute has_element?(view, "#transaction-form")

    drawer = view |> element("#booking-drawer") |> render()
    assert drawer =~ "only the note changes here"

    assert has_element?(view, "#split-facts select[name='split[type]'][disabled]")

    assert has_element?(
             view,
             "#split-facts input[name='split[date]'][disabled][value='2026-02-01']"
           )

    assert has_element?(view, "#split-facts select[name='split[security_id]'][disabled]")
    assert has_element?(view, "#split-facts input[name='split[ratio]'][disabled][value='2:1']")
    assert drawer =~ security.name
    refute drawer =~ "Books to depot"
    refute has_element?(view, "#booking-drawer input[name='split[quantity]']")

    assert view |> element("#split-edit-help") |> render() =~ "API or MCP"
    refute has_element?(view, "#split-edit-help a")

    view
    |> form("#split-note-form", %{"split" => %{"notes" => "per the broker statement"}})
    |> render_submit()

    refute has_element?(view, "#booking-drawer")
    stored = Ledger.get_transaction(split.id)
    assert stored.notes == "per the broker statement"
    assert stored.date == ~D[2026-02-01]
    assert {stored.split_ratio_numerator, stored.split_ratio_denominator} == {2, 1}
  end

  # Acceptance criteria:
  # - A booking save pushed at an open split edit — the fields the drawer no
  #   longer offers — is refused by the ledger: the drawer stays, a failure
  #   is shown, and the split keeps its date.
  test "a forged booking save on a split row is refused and changes nothing",
       %{conn: conn, world: world, security: security, split: split} do
    view = open_split_edit(conn, split)

    render_submit(view, "save_transaction", %{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-01-20",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "10",
        "price" => "1"
      }
    })

    assert has_element?(view, "#booking-drawer")
    stored = Ledger.get_transaction(split.id)
    assert stored.type == "split"
    assert stored.date == ~D[2026-02-01]
  end
end
