defmodule PortfolixirWeb.DashboardKpiStripTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  # User story (#798, review C2 — variant B, picked 2026-09-14; UX-DR2 as
  # amended 2026-09-14):
  # As a local portfolio maintainer opening the Overview in the morning,
  # I want a four-cell key-figure strip under the value card — the 1Y TTWROR
  # with its money-weighted companion, the cash quote with its amount, the
  # last booking with its date and kind, the quote freshness with the stale
  # count — each cell stating its basis and linking to the surface that owns
  # the figure,
  # so that the four questions of the morning are answered on one line
  # without the Wealth band being repeated.
  #
  # Acceptance criteria:
  # - #dashboard-kpi-strip carries four cells: kpi-ttwror (→ /portfolio),
  #   kpi-cash-quote (→ /portfolio), kpi-last-booking (→ /transactions),
  #   kpi-freshness (→ the securities list pre-filtered to stale quotes).
  # - The last-booking cell shows the newest booking's date, its kind as the
  #   localized label (never the raw enum) and its subject.
  # - The freshness cell shows the newest quote date across held positions
  #   and carries "n stale" only when n > 0 — with n = 0 the date alone.
  # - A basis line under the strip names the view, the period and the
  #   currency; the value card's sub-line keeps the YTD change and drops the
  #   cash quote.

  # Securities 10 × 120 = 1,200, cash 2,000 − 1,000 = 1,000: cash quote
  # 45.5 %; TTWROR 2,000 → 2,200 = +10.0 %. The buy is the newest booking.
  defp world do
    Classifications.ensure_builtins()
    world = WorldFixtures.base_world(name: "Strip", cash_name: "Giro", depot_name: "Depot")
    acme = WorldFixtures.create_security!(name: "ACME", ticker: "ACM", asset_class: "equity")

    WorldFixtures.deposit!(world, "2000", ~D[2026-01-05])
    WorldFixtures.buy!(world, acme, quantity: "10", price: "100", date: ~D[2026-01-10])
    # Quoted at the buy too: the walk books the step from a trade price to
    # the first quote as a return-base step, not as performance.
    WorldFixtures.put_quotes!(acme, [{~D[2026-01-10], "100"}, {Date.utc_today(), "120"}])
    %{world: world, acme: acme}
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp cell(doc, role) do
    case Floki.find(doc, ~s(#dashboard-kpi-strip [data-role="#{role}"])) do
      [cell] -> cell
      other -> flunk("expected one #{role} cell, got #{inspect(other)}")
    end
  end

  test "the strip answers return, cash quote, last booking and freshness", %{conn: conn} do
    world()
    today = Date.utc_today()

    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    doc = document(view)

    assert [strip] = Floki.find(doc, "#dashboard-kpi-strip")
    assert length(Floki.find(strip, "a[data-role^='kpi-']")) == 4

    ttwror = cell(doc, "kpi-ttwror")
    assert Floki.attribute(ttwror, "href") == ["/portfolio"]
    assert text(ttwror) =~ "TTWROR 1Y"
    assert text(Floki.find(ttwror, "strong")) == "+10.0%"
    assert text(Floki.find(ttwror, ".kpi-strip__sub")) =~ ~r/^(IRR|MWR) [+-]?\d/

    cash = cell(doc, "kpi-cash-quote")
    assert Floki.attribute(cash, "href") == ["/portfolio"]
    assert text(Floki.find(cash, "strong")) == "45.5%"
    assert text(Floki.find(cash, ".kpi-strip__sub")) == "1,000.00 EUR cash"

    booking = cell(doc, "kpi-last-booking")
    assert Floki.attribute(booking, "href") == ["/transactions"]
    assert text(Floki.find(booking, "strong")) == "2026-01-10"
    assert text(Floki.find(booking, ".kpi-strip__sub")) == "Buy · ACME"

    freshness = cell(doc, "kpi-freshness")
    assert Floki.attribute(freshness, "href") == ["/securities?dq=stale_quote"]
    assert text(Floki.find(freshness, "strong")) == Date.to_iso8601(today)
    refute text(freshness) =~ "stale"

    basis = text(Floki.find(doc, ~s([data-role="kpi-strip-basis"])))
    assert basis =~ "Everything"
    assert basis =~ "1Y"
    assert basis =~ "EUR"

    # The value card keeps its YTD change and drops the cash quote.
    card = text(Floki.find(doc, ~s([data-role="card-ttwror"])))
    assert card =~ "YTD"
    refute card =~ "Cash"
  end

  test "the freshness cell counts stale quotes only when there are any", %{conn: conn} do
    %{world: world} = world()
    today = Date.utc_today()
    old = WorldFixtures.create_security!(name: "Old Co", ticker: "OLD", asset_class: "equity")
    WorldFixtures.put_quote!(old, Date.add(today, -(DataQuality.stale_days() + 5)), "9")
    WorldFixtures.buy!(world, old, quantity: "1", price: "10", date: ~D[2026-02-01])

    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    doc = document(view)

    freshness = cell(doc, "kpi-freshness")
    # The newest quote across the held positions is still today's.
    assert text(Floki.find(freshness, "strong")) == Date.to_iso8601(today)
    assert text(Floki.find(freshness, ".kpi-strip__sub")) == "1 stale"

    # The last booking follows the ledger, not the quote.
    assert text(Floki.find(cell(doc, "kpi-last-booking"), ".kpi-strip__sub")) == "Buy · Old Co"
  end

  test "the strip is German where the page is — labels at render time", %{conn: conn} do
    world()

    {:ok, view, _html} = live(conn, "/?locale=de")
    render_async(view)
    doc = document(view)

    booking = cell(doc, "kpi-last-booking")
    assert text(booking) =~ "Letzte Buchung"
    assert text(Floki.find(booking, "strong")) == "10.01.2026"
    assert text(Floki.find(booking, ".kpi-strip__sub")) == "Kauf · ACME"
    assert text(cell(doc, "kpi-ttwror")) =~ "TTWROR 1J"
    assert text(cell(doc, "kpi-freshness")) =~ "Kurse"
    assert text(Floki.find(doc, ~s([data-role="kpi-strip-basis"]))) =~ "Alles"
  end
end
