defmodule PortfolixirWeb.DashboardTwinNotesTest do
  # #1320 (the Overview's polish list #1358; Sprint 31 D3): the notes the
  # Overview's widgets show name the securities they leave out by name, and
  # two securities of one name read as one. Each note now tells twins apart
  # by what the house's twin rule gives them (`PortfolixirWeb.SecurityNames`,
  # ISIN, else WKN, else the number), from ids the payloads the notes read
  # carry. Synthetic names and identifiers only.
  # group: :dashboards -- the note test stores „Überblick“ at M (Sprint 31
  # D4: at S the total's note is one line of counts), and a create takes
  # the advisory lock that counts the dashboards (`Portfolixir.LockTable`
  # row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Clock

  defp text(nodes),
    do: nodes |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  defp loaded(conn) do
    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    view |> render() |> Floki.parse_document!()
  end

  # User story (#1320):
  # As the operator reading the note under „Verkaufsrückblick“,
  # I want two left-out sales of securities with one name told apart,
  # so that the note does not name one security for two sales.
  #
  # Acceptance criteria:
  # - Two GBP sales with no stored rate, of two securities named „Twin
  #   Pound plc“, are named once each, each with its ISIN, in the order of
  #   their ids.
  test "the sale review's note tells twins apart", %{conn: conn} do
    world = base_world()

    gbp =
      Map.merge(
        world,
        add_depot(world.portfolio, currency: "GBP", cash_name: "GBP Cash", depot_name: "GBP")
      )

    for isin <- ~w(GB0000000102 GB0000000101) do
      twin = create_security!(name: "Twin Pound plc", ticker: nil, currency: "GBP", isin: isin)
      buy!(gbp, twin, quantity: "2", price: "10", date: ~D[2026-01-09], currency: "GBP")
      sell!(gbp, twin, quantity: "2", price: "30", date: ~D[2026-04-20], currency: "GBP")
    end

    note = conn |> loaded() |> Floki.find("[data-role='trades-card-excluded-no-rate']")

    assert text(note) ==
             "2 sales with no stored rate on their close dates are left out of the trades: " <>
               "Twin Pound plc · ISIN GB0000000102, Twin Pound plc · ISIN GB0000000101. " <>
               "The rate backfill is under “All trades”."
  end

  # User story (#1320):
  # As the operator reading the note under „Gesamtwert“,
  # I want two held positions with no price and one name told apart,
  # so that the note does not name one position for two.
  #
  # Acceptance criteria:
  # - Two held securities named „Twin Fonds“ with no price are named once
  #   each in the note, each with its ISIN.
  test "the total's note tells twins apart", %{conn: conn} do
    world = base_world()
    priced = create_security!(name: "Priced Co")
    buy!(world, priced, quantity: "1", price: "10")
    put_quote!(priced, Clock.today(), "10")

    # Delivered in, with no booked price and no quote: no price at all.
    for isin <- ~w(DE0000000201 DE0000000202) do
      twin = create_security!(name: "Twin Fonds", ticker: nil, isin: isin)
      deliver_untraded!(world, twin, "1", date: Date.add(Clock.today(), -5))
    end

    Portfolixir.DashboardFixtures.overview_at_m!()
    note = conn |> loaded() |> Floki.find("[data-role='wealth-card-excluded']")

    assert text(note) =~
             "2 held positions with no price — Twin Fonds · ISIN DE0000000201, " <>
               "Twin Fonds · ISIN DE0000000202."
  end
end
