defmodule PortfolixirWeb.SecuritiesRangeLabelsTest do
  # Sprint 18 plan U5, H7.3 (board ux-design-2026-10-02/07-phone-390): the
  # security detail's range tokens in the reader's language, from one label
  # function for the Chart tab's buttons and the Quotes tab's basis line.
  # Every name, close and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Repo

  setup do
    security =
      create_security!(name: "Nordwind Industrie AG", ticker: "NWI", currency_code: "EUR")

    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: Date.add(Date.utc_today(), -2),
        close: Decimal.new("112.40"),
        source: "manual"
      })
      |> Repo.insert()

    %{security: security}
  end

  defp buttons(view) do
    view
    |> element("#detail-tab-panel-chart .range-buttons")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("button.range-button")
    |> Enum.map(fn button ->
      {button |> Floki.attribute("phx-value-range") |> List.first(),
       button |> Floki.text() |> String.trim()}
    end)
  end

  defp basis(view) do
    view
    |> element("#detail-tab-panel-quotes [data-role='quotes-range-basis']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.split()
    |> Enum.join(" ")
  end

  # User story (#1033; board 07, H7.3, before/after):
  # As the operator reading a security in German,
  # I want the Chart tab's range buttons and the Quotes tab's basis line to
  # name the range in German — "1J", as the Overview's KPI strip and Wealth
  # already say,
  # so that "Zeitraum 1Y · wie im Diagramm" does not stand on every first
  # visit to the tab, and the line and the button it points to agree.
  #
  # Acceptance criteria:
  # - One label for the detail's eight tokens serves the buttons and the
  #   basis line: German "1M 3M 6M YTD 1J 3J 5J Max", English
  #   "1M 3M 6M YTD 1Y 3Y 5Y Max" — "MAX" becomes "Max" in both, the one
  #   casing EXPERIENCE.md → Period control changes.
  # - The URL and event value (`phx-value-range`) stay the codes.
  # - The basis line names the default range "1J" in German.
  test "the range buttons and the basis line name the range in the reader's language",
       %{conn: conn, security: security} do
    codes = ~w(1M 3M 6M YTD 1Y 3Y 5Y MAX)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart&locale=de")

    assert buttons(view) == Enum.zip(codes, ~w(1M 3M 6M YTD 1J 3J 5J Max))
    assert has_element?(view, "button.range-button.is-active[phx-value-range='1Y']", "1J")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes&locale=de")
    assert basis(view) == "Zeitraum 1J · wie im Diagramm"

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart&locale=en")
    assert buttons(view) == Enum.zip(codes, ~w(1M 3M 6M YTD 1Y 3Y 5Y Max))

    view
    |> element("button[phx-click='set_detail_range'][phx-value-range='MAX']")
    |> render_click()

    view |> element("#detail-tab-quotes") |> render_click()
    assert basis(view) == "Range Max · as on the Chart tab"
  end

  # User story (the closing act's finding on H7.3; board
  # ux-review-2026-10-03/03-gamma-surface-repairs, G3):
  # As the operator reading a security's Overview in German,
  # I want the one-year figure labelled "1J", as the chart's button and the
  # Quotes tab's basis line label the same year,
  # so that the Overview does not keep the one English token H7.3 left.
  #
  # Acceptance criteria:
  # - The Overview's one-year figure is labelled through the detail's range
  #   label function: "1J" in German, "1Y" in English.
  test "the Overview's one-year figure is labelled in the reader's language",
       %{conn: conn, security: security} do
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=overview&locale=de")
    assert view |> element("[data-role='overview-1y'] dt") |> render() =~ ~r{<dt>\s*1J\s*</dt>}

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=overview&locale=en")
    assert view |> element("[data-role='overview-1y'] dt") |> render() =~ ~r{<dt>\s*1Y\s*</dt>}
  end
end
