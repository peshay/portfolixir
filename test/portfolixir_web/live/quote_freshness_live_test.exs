defmodule PortfolixirWeb.QuoteFreshnessLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures
  alias PortfolixirWeb.AppShell

  # User story (#789):
  # As a local portfolio maintainer reading a price,
  # I want a quote older than the data-quality threshold to be marked where
  # the price is read — the list row, the detail header and the Wealth
  # positions — so that a five-week-old close never reads like today's.
  #
  # Acceptance criteria:
  # - The list row carries the marker on the line under the price: attention
  #   tone, the glyph `aria-hidden`, the word "stale" and the quote date as
  #   real text ("veraltet · 2026-08-08" in German); the day-change cell reads
  #   "—" instead of a change computed from the stale close.
  # - The detail header carries the same marker on the latest price (the date
  #   is not doubled) and "—" for the day change.
  # - The Wealth flat positions row carries the marker beside the value.
  # - A fresh quote carries no marker; a retired security's stopped feed is
  #   expected and carries none.
  # - The threshold is `DataQuality.stale_days/0`, the one the filter chip
  #   and the Wealth finding use.

  defp world do
    Classifications.ensure_builtins()
    world = WorldFixtures.base_world(name: "Freshness", cash_name: "Giro", depot_name: "Depot")
    today = Date.utc_today()
    old = Date.add(today, -(DataQuality.stale_days() + 28))

    stale = WorldFixtures.create_security!(name: "Stale AG", ticker: "STL")
    # Two closes, so a day change (+2.03 %) WOULD compute from the stale close
    # if the marker did not replace it.
    WorldFixtures.put_quote!(stale, Date.add(old, -1), "41.79")
    WorldFixtures.put_quote!(stale, old, "42.64")
    WorldFixtures.buy!(world, stale, quantity: "10", price: "40", date: ~D[2026-01-05])

    fresh = WorldFixtures.create_security!(name: "Fresh AG", ticker: "FRS")
    WorldFixtures.put_quote!(fresh, Date.add(today, -2), "99")
    WorldFixtures.put_quote!(fresh, Date.add(today, -1), "100")
    WorldFixtures.buy!(world, fresh, quantity: "10", price: "90", date: ~D[2026-01-05])

    retired = WorldFixtures.create_security!(name: "Retired AG", ticker: "RTD")
    WorldFixtures.put_quote!(retired, old, "10")
    WorldFixtures.buy!(world, retired, quantity: "10", price: "10", date: ~D[2026-01-05])
    {:ok, retired} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})

    %{world: world, stale: stale, fresh: fresh, retired: retired, old: old}
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp row_for(doc, selector, name) do
    doc
    |> Floki.find(selector)
    |> Enum.find(&(text(&1) =~ name)) ||
      flunk("no row for #{name}")
  end

  defp metric(doc, label) do
    doc
    |> Floki.find(".overview-metric")
    |> Enum.find(&(text(Floki.find(&1, "dt")) == label)) ||
      flunk("no metric #{label}")
  end

  test "the list row marks a stale quote under the price and blanks the day change", %{
    conn: conn
  } do
    %{old: old} = world()
    iso = Date.to_iso8601(old)

    {:ok, view, _html} = live(conn, "/securities")
    doc = view |> render() |> Floki.parse_document!()

    stale_row = row_for(doc, "#securities-table tbody tr", "Stale AG")
    marker = Floki.find(stale_row, ~s([data-role="quote-stale"]))
    assert text(marker) == "stale · #{iso}"
    assert [_glyph] = Floki.find(marker, ~s(svg[aria-hidden="true"]))
    assert text(stale_row) =~ "42.64"
    refute text(stale_row) =~ "2.03"
    assert text(stale_row) =~ "—"

    fresh_row = row_for(doc, "#securities-table tbody tr", "Fresh AG")
    assert Floki.find(fresh_row, ~s([data-role="quote-stale"])) == []
    assert text(fresh_row) =~ "+1.01"
  end

  # A retired security carries no stale marker — its stopped feed is expected —
  # but its old close is still no basis for a day change, which is the figure
  # the marker exists to suppress.
  test "a retired security shows no marker and no day change from its old close",
       %{conn: conn} do
    %{old: old} = world()

    # Two closes, so a day change is computable — and both of them old.
    stopped = WorldFixtures.create_security!(name: "Stopped AG", ticker: "STOP")
    WorldFixtures.put_quotes!(stopped, [{Date.add(old, -1), "50"}, {old, "52"}])

    {:ok, _} =
      Catalog.update_security(Actor.owner_ui(), stopped, %{is_retired: true})

    {:ok, view, _html} = live(conn, "/securities")
    doc = view |> render() |> Floki.parse_document!()

    row = row_for(doc, "#securities-table tbody tr", "Stopped AG")

    assert Floki.find(row, ~s([data-role="quote-stale"])) == []
    assert text(row) =~ "52.00"
    assert text(row) =~ "—"
    refute text(row) =~ "+4.00"
  end

  test "the marker is German where the page is", %{conn: conn} do
    %{old: old} = world()

    {:ok, view, _html} = live(conn, "/securities?locale=de")
    doc = view |> render() |> Floki.parse_document!()

    stale_row = row_for(doc, "#securities-table tbody tr", "Stale AG")

    # The date reads under the locale too (the marker is prose, not an input
    # value): German renders 11.08.2026, not the ISO form.
    assert text(Floki.find(stale_row, ~s([data-role="quote-stale"]))) ==
             "veraltet · #{Calendar.strftime(old, "%d.%m.%Y")}"
  end

  test "the detail header marks the latest price and blanks the day change", %{conn: conn} do
    %{stale: stale, retired: retired, old: old} = world()
    iso = Date.to_iso8601(old)

    {:ok, view, _html} = live(conn, "/securities/#{stale.id}")
    doc = view |> render() |> Floki.parse_document!()

    latest = metric(doc, "Latest price")
    assert text(Floki.find(latest, ~s([data-role="quote-stale"]))) == "stale · #{iso}"
    # The marker carries the date; the parenthesised sub-line does not double it.
    refute text(latest) =~ "(#{iso})"
    assert text(Floki.find(metric(doc, "Day change"), "dd")) == "—"

    # A retired security's stopped feed is expected: no marker, the date stays.
    {:ok, view, _html} = live(conn, "/securities/#{retired.id}")
    doc = view |> render() |> Floki.parse_document!()
    latest = metric(doc, "Latest price")
    assert Floki.find(latest, ~s([data-role="quote-stale"])) == []
    assert text(latest) =~ "(#{iso})"
  end

  test "the Wealth positions row marks a stale valuation beside its value", %{conn: conn} do
    %{old: old} = world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)
    view |> element(~s([data-role="allocation-mode-flat"])) |> render_click()

    doc =
      view
      |> element(~s([data-role="flat-positions"]))
      |> render()
      |> Floki.parse_document!()

    stale_row = row_for(doc, ~s(tr[data-role="flat-position"]), "Stale AG")

    assert text(Floki.find(stale_row, ~s([data-role="quote-stale"]))) ==
             "stale · #{Date.to_iso8601(old)}"

    fresh_row = row_for(doc, ~s(tr[data-role="flat-position"]), "Fresh AG")
    assert Floki.find(fresh_row, ~s([data-role="quote-stale"])) == []

    retired_row = row_for(doc, ~s(tr[data-role="flat-position"]), "Retired AG")
    assert Floki.find(retired_row, ~s([data-role="quote-stale"])) == []
  end

  test "the clock glyph joins the icon set for the freshness note" do
    html = render_component(&AppShell.icon/1, name: :clock, size: 12)
    # The dial and the hands — not the fallback dot an unknown name renders.
    assert html =~ ~s(<circle cx="12" cy="12" r="9"/>)
    assert html =~ ~s(<path d="M12 7v5l3 2"/>)
    assert html =~ ~s(aria-hidden="true")
  end
end
