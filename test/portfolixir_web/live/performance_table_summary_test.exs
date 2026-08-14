defmodule PortfolixirWeb.PerformanceTableSummaryTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.WorldFixtures

  # User story (#564):
  # As a local portfolio maintainer opening the chart's data table,
  # I want insight-level summary rows — per year, or per month for short
  # periods — with start/end value, the slice's TTWROR and net flows,
  # so that the table is an information display instead of a downsampled
  # daily dump of hundreds of rows nobody reads.
  #
  # Acceptance criteria:
  # - The disclosure keeps the accessible table (UX-DR10) under the "Data as
  #   table" wording of record, with a stated purpose line.
  # - Rows are one per month for short periods (per year beyond a year),
  #   carrying start value, end value, slice TTWROR and net external flows.
  # - No daily dump: the table has no per-day rows.
  test "the chart data table shows per-slice summaries, not a daily dump", %{conn: conn} do
    Portfolixir.Classifications.ensure_builtins()
    world = WorldFixtures.base_world(name: "Perf", currency: "EUR")
    sec = WorldFixtures.create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")

    WorldFixtures.deposit!(world, "10000", ~D[2026-01-02], [])
    WorldFixtures.buy!(world, sec, quantity: "5", price: "100", date: ~D[2026-01-05])
    WorldFixtures.put_quote!(sec, ~D[2026-02-14], "110")
    WorldFixtures.put_quote!(sec, ~D[2026-03-10], "120")

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    disclosure = view |> element(".perf-table-disclosure") |> render()

    # The one uniform disclosure (UX-DR10): quiet summary, wording of record,
    # stated purpose.
    assert disclosure =~ "Data as table"
    assert disclosure =~ "disclosure-summary"
    assert disclosure =~ ~s(data-role="perf-table-purpose")

    table = view |> element(~s([data-role="perf-summary-table"])) |> render()

    # Monthly slices for a sub-year period, with the summary columns.
    assert table =~ "2026-01"
    assert table =~ "Start value"
    assert table =~ "End value"
    assert table =~ "TTWROR"
    assert table =~ "Net flows"

    # The deposit is January's net external flow.
    assert table =~ "10,000.00"

    # No per-day rows: a daily dump would carry full ISO dates in the body.
    refute table =~ "2026-01-05"
  end
end
