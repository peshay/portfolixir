defmodule PortfolixirWeb.SecuritiesSplitDeleteLiveTest do
  # Sprint 18 U1 (#912), pick H2 = A, state A8 (board
  # `ux-design-2026-10-02/02-booking-delete`): "Record split" refused a
  # different ratio on a day that already carries a split and said to delete
  # the existing event first — with no way to do it. Its warning now names
  # the booked ratio and carries "Delete the booked split…", which closes
  # the wizard and opens the split's delete dialog on the same page, so the
  # delete and the rebooking happen in one place.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger.Splits

  setup do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS", asset_class: "equity")
    buy!(world, security, quantity: "10", price: "80", date: Date.add(Date.utc_today(), -40))
    date = Date.add(Date.utc_today(), -10)

    {:ok, [row]} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    %{security: security, date: date, row: row}
  end

  defp open_wizard(conn, security) do
    {:ok, view, _html} = live(conn, "/securities/#{security.id}")
    view |> element("#detail-record-split") |> render_click()
    view
  end

  defp fill(view, numerator, denominator, date) do
    view
    |> form("#split-wizard-form", %{
      "split" => %{
        "ratio_numerator" => numerator,
        "ratio_denominator" => denominator,
        "date" => Date.to_iso8601(date)
      }
    })
  end

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.replace(~r/\s+/, " ")

  # User story (U1, #912; H2-A, A8):
  # As the operator whose corrected split ratio "Record split" refuses
  # because the wrong one is booked on that day,
  # I want the refusal to name the booked ratio and lead to deleting it,
  # so that I correct the split where I noticed it, without the agent.
  #
  # Acceptance criteria:
  # - The conflicting-ratio warning names the booked ratio, says the booking
  #   is refused while it stands, and carries "Delete the booked split…".
  # - That link closes the wizard and opens the split's delete dialog on the
  #   security's page; its confirm deletes the split whole and says so in
  #   the page's result, and "Record split" then books the corrected ratio.
  test "Record split's conflict leads to the booked split's delete",
       %{conn: conn, security: security, date: date, row: row} do
    view = open_wizard(conn, security)
    view |> fill("3", "1", date) |> render_change()

    warning =
      view
      |> element("#split-wizard-warnings [data-warning='conflicting_split_ratio']")
      |> render()

    assert text(warning) =~ "already booked for this security on this date (2:1)"
    assert text(warning) =~ "refused while it stands"

    view
    |> element("#split-wizard-warnings button.link-button", "Delete the booked split…")
    |> render_click()

    refute has_element?(view, "#split-wizard-dialog")
    assert has_element?(view, "dialog#booking-delete-dialog")

    assert has_element?(
             view,
             "dialog#booking-delete-dialog[data-focus-fallback='#detail-record-split']"
           )

    assert view |> element("#booking-delete-dialog") |> render() |> text() =~ "Delete split"

    view |> element("#booking-delete-confirm") |> render_click()

    refute has_element?(view, "#booking-delete-dialog")
    assert Splits.booked_on(security.id, date) == []

    assert view |> element("#securities-action-result") |> render() |> text() =~
             "Split deleted: Kestrel Robotik SE · 2:1 · #{Date.to_iso8601(date)}, 1 row."

    view = open_wizard(conn, security)
    view |> fill("3", "1", date) |> render_submit()
    assert [%{id: id, split_ratio_numerator: 3}] = Splits.booked_on(security.id, date)
    assert id != row.id
  end

  # User story (U1, #912; H2-A, A4 and A8; the closing act, R5):
  # As the operator deleting the booked split from "Record split" while the
  # agent extends it to another portfolio,
  # I want the confirm to delete nothing and show the split as it now is,
  # so that I never delete more than the dialog listed.
  #
  # Acceptance criteria:
  # - A row added meanwhile keeps the dialog open on the security's page
  #   with the changed-split note and the new row count; nothing is deleted.
  test "a split extended while its dialog was open is shown anew", %{
    conn: conn,
    security: security,
    date: date
  } do
    view = open_wizard(conn, security)
    view |> fill("3", "1", date) |> render_change()

    view
    |> element("#split-wizard-warnings button.link-button", "Delete the booked split…")
    |> render_click()

    other = base_world(name: "Sparplan-Portfolio", cash_name: "Tagesgeld", depot_name: "Depot 2")
    buy!(other, security, quantity: "4", price: "80", date: Date.add(date, -20))

    {:ok, [_added]} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    view |> element("#booking-delete-confirm") |> render_click()

    assert has_element?(view, "dialog#booking-delete-dialog [data-role='booking-delete-changed']")
    assert view |> element("#booking-delete-subject") |> render() |> text() =~ "2 rows"
    assert length(Splits.booked_on(security.id, date)) == 2
  end

  # User story (U1, #912; H2-A, A8, the booking refusal):
  # As the operator whose booking was refused as conflicting,
  # I want the refusal to carry the same way out,
  # so that the sentence "delete that event first" is never a dead end.
  #
  # Acceptance criteria:
  # - The refusal of a conflicting or an already booked split carries
  #   "Delete the booked split…", opening the same dialog.
  test "the booking refusal carries the same way out", %{
    conn: conn,
    security: security,
    date: date
  } do
    view = open_wizard(conn, security)
    view |> fill("2", "1", date) |> render_submit()

    assert view |> element("#split-wizard-error") |> render() |> text() =~ "already booked"

    view
    |> element("#split-wizard-error button.link-button", "Delete the booked split…")
    |> render_click()

    assert has_element?(view, "dialog#booking-delete-dialog")
  end
end
