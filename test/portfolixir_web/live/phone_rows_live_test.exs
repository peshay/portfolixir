defmodule PortfolixirWeb.PhoneRowsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # User story (#799, review C3 — variant A, picked 2026-09-14; UX-DR27):
  # As a local portfolio maintainer reading a list on the phone,
  # I want the securities list and the transactions history to render as
  # two-line rows under 560 px — the name over its identifiers, the figures
  # the row exists for right-aligned, the row's states as words in the row —
  # so that nothing scrolls sideways and the price, the change, the amount
  # and the size are read without a swipe.
  #
  # Acceptance criteria:
  # - The securities list carries a phone row per security: name, ticker ·
  #   ISIN · asset class (the quick-assign control where the class is
  #   missing, the currency where no identifier exists), the latest price
  #   with the stale marker under it, the day change ("no price" and "—"
  #   when unpriced). Selected and retired rows keep their states; the kebab
  #   opens the row menu; the name opens the detail.
  # - The transactions history carries its month group heads and a row per
  #   booking: date · kind label over the subject, the signed amount with its
  #   currency over the size (quantity × price, or the quantity alone).
  # - Above 560 px nothing changes: the tables stay, the phone rows are
  #   hidden by CSS (pinned in css_layout_sweep_test.exs).

  defp world do
    Classifications.ensure_builtins()
    world = WorldFixtures.base_world(name: "Phone", cash_name: "Giro", depot_name: "Depot")
    today = Date.utc_today()
    old = Date.add(today, -(DataQuality.stale_days() + 28))

    fresh =
      WorldFixtures.create_security!(
        name: "Fresh AG",
        ticker: "FRS",
        isin: "DE000FRESH019",
        asset_class: "equity"
      )

    WorldFixtures.put_quotes!(fresh, [{Date.add(today, -1), "99"}, {today, "100"}])

    stale = WorldFixtures.create_security!(name: "Stale AG", ticker: "STL", asset_class: "equity")
    WorldFixtures.put_quotes!(stale, [{Date.add(old, -1), "41.79"}, {old, "42.64"}])

    # No identifier, no quote, and a name no asset-class heuristic matches.
    {:ok, mystery} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Mystery Instrument",
        currency_code: "EUR"
      })

    retired = WorldFixtures.create_security!(name: "Retired AG", ticker: "RTD")
    {:ok, retired} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})

    WorldFixtures.buy!(world, fresh, quantity: "30", price: "42.10", date: ~D[2026-02-24])
    WorldFixtures.deposit!(world, "1500", ~D[2026-08-31])

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fresh.id,
        type: "dividend",
        date: ~D[2026-09-03],
        quantity: "50",
        gross_amount: "12.50",
        currency_code: "EUR"
      })

    %{world: world, fresh: fresh, stale: stale, mystery: mystery, retired: retired, old: old}
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp classes(node), do: node |> Floki.attribute("class") |> Enum.flat_map(&String.split/1)
  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp row_for(rows, needle) do
    Enum.find(rows, &(text(&1) =~ needle)) || flunk("no phone row for #{needle}")
  end

  test "the securities list renders two-line rows with the row's states as words", %{conn: conn} do
    %{fresh: fresh, old: old} = world()

    {:ok, view, _html} = live(conn, "/securities")
    doc = document(view)

    rows = Floki.find(doc, ~s(#securities-phone-rows li[data-role="phone-row"]))
    assert length(rows) == 4

    fresh_row = row_for(rows, "Fresh AG")
    assert text(Floki.find(fresh_row, ".phone-row__name")) == "Fresh AG"
    assert text(Floki.find(fresh_row, ".phone-row__ids")) == "FRS · DE000FRESH019 · Equity"
    assert text(Floki.find(fresh_row, ".phone-row__figure")) == "100.00"
    assert text(Floki.find(fresh_row, ".phone-row__figure2")) == "+1.01 %"
    assert [_logo] = Floki.find(fresh_row, ".security-logo")

    # A stale close is marked under the price; the change computed from it
    # is not shown.
    stale_row = row_for(rows, "Stale AG")
    assert text(Floki.find(stale_row, ".phone-row__figure")) == "42.64"

    assert text(Floki.find(stale_row, ~s([data-role="quote-stale"]))) ==
             "stale · #{Date.to_iso8601(old)}"

    refute text(stale_row) =~ "%"

    # Unpriced and unclassified: the words, and the remedy in the row.
    mystery_row = row_for(rows, "Mystery Instrument")
    assert text(Floki.find(mystery_row, ".phone-row__figure")) == "no price"
    assert text(Floki.find(mystery_row, ".phone-row__figure2")) == "—"
    assert [_select] = Floki.find(mystery_row, "select.quick-assign-select")
    assert text(Floki.find(mystery_row, ".phone-row__ids")) =~ "EUR"

    retired_row = row_for(rows, "Retired AG")
    assert "is-retired" in classes(retired_row)

    # The kebab opens the same row menu the table row opens.
    assert [_] = Floki.find(fresh_row, ~s(button.row-actions__kebab[phx-click="open_row_menu"]))
    view |> element("#phone-kebab-#{fresh.id}") |> render_click()
    assert has_element?(view, "#row-menu-#{fresh.id}")

    # The name opens the detail, and the row then reads as selected.
    view |> element("#security-phone-#{fresh.id} a.phone-row__target") |> render_click()
    assert assert_patch(view) =~ "/securities/#{fresh.id}"
    assert has_element?(view, "#security-phone-#{fresh.id}.is-selected")
  end

  test "the transactions history renders month heads and two-line booking rows", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/transactions")
    doc = document(view)

    groups = Floki.find(doc, "#transaction-phone-rows li.phone-rows__group")

    assert Enum.map(groups, &text(Floki.find(&1, ".tx-group-month"))) == [
             "September 2026",
             "August 2026",
             "February 2026"
           ]

    assert text(hd(groups)) =~ "1 transaction"
    assert text(hd(groups)) =~ "12.50 EUR"

    rows = Floki.find(doc, ~s(#transaction-phone-rows li[data-role="phone-row"]))
    assert length(rows) == 3

    buy = row_for(rows, "Buy")
    assert text(Floki.find(buy, ".phone-row__name")) == "2026-02-24 · Buy"
    assert text(Floki.find(buy, ".phone-row__ids")) == "Fresh AG"
    assert text(Floki.find(buy, ".phone-row__figure")) == "-1,263.00 EUR"
    assert text(Floki.find(buy, ".phone-row__figure2")) == "30 × 42.10"

    deposit = row_for(rows, "Deposit")
    assert text(Floki.find(deposit, ".phone-row__ids")) == "Giro"
    assert text(Floki.find(deposit, ".phone-row__figure")) == "1,500.00 EUR"
    assert Floki.find(deposit, ".phone-row__figure2") == []

    dividend = row_for(rows, "Dividend")
    assert text(Floki.find(dividend, ".phone-row__figure")) == "12.50 EUR"
    assert text(Floki.find(dividend, ".phone-row__figure2")) == "50 units"
  end

  test "the phone rows are German where the page is", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    doc = document(view)
    rows = Floki.find(doc, ~s(#transaction-phone-rows li[data-role="phone-row"]))

    buy = row_for(rows, "Kauf")
    assert text(Floki.find(buy, ".phone-row__name")) == "24.02.2026 · Kauf"
    assert text(Floki.find(buy, ".phone-row__figure")) == "-1.263,00 EUR"
    assert text(Floki.find(buy, ".phone-row__figure2")) == "30 × 42,10"
    assert text(Floki.find(row_for(rows, "Dividende"), ".phone-row__figure2")) == "50 Stück"

    {:ok, view, _html} = live(conn, "/securities?locale=de")
    doc = document(view)
    rows = Floki.find(doc, ~s(#securities-phone-rows li[data-role="phone-row"]))
    mystery_row = row_for(rows, "Mystery Instrument")
    assert text(Floki.find(mystery_row, ".phone-row__figure")) == "kein Kurs"
  end
end
