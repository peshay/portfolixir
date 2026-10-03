defmodule PortfolixirWeb.Portfolio.ContributionTableComponentTest do
  # FR-41, ADR-0051 §12: the contribution table's states and words, rendered
  # from engine-shaped results the walk produces only on worlds a page test
  # would have to contort (a failed walk, a nameless security, a tie at the
  # tenth place). Invented figures only.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Portfolio.ContributionTable

  defp d(value), do: Decimal.new(value)

  defp position(id, contribution, overrides \\ %{}) do
    Map.merge(
      %{
        security_id: id,
        name: "Position #{id}",
        isin: nil,
        start_value: d("100"),
        net_flows: d("0"),
        income: d("0"),
        costs: d("0"),
        end_value: Decimal.add(d("100"), d(contribution)),
        contribution: d(contribution),
        held_at_start: true,
        held_at_end: true,
        unvalued_days: 0,
        unvalued_reason: nil
      },
      overrides
    )
  end

  defp result(positions) do
    total = Enum.reduce(positions, d("0"), &Decimal.add(&1.contribution, &2))

    %{
      start_date: ~D[2026-01-01],
      end_date: ~D[2026-06-30],
      base_currency: "EUR",
      positions: positions,
      remainder: %{
        interest: d("0"),
        standalone_fees_and_taxes: d("0"),
        cash_currency_effect: d("0")
      },
      totals: %{result: total, positions: total, remainder: d("0")}
    }
  end

  defp render_table(contribution, opts \\ []) do
    render_component(&ContributionTable.table/1,
      contribution: contribution,
      failed?: Keyword.get(opts, :failed?, false),
      show_all?: false,
      period_label: "YTD",
      view_name: "Everything"
    )
  end

  defp text(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Floki.text(sep: " ")
    |> String.split()
    |> Enum.join(" ")
  end

  # User story (FR-41, ADR-0051 §12, board pick A):
  # As a local portfolio maintainer whose contribution walk failed,
  # I want the table to say so instead of computing forever,
  # so that I know a reload is the remedy.
  #
  # Acceptance criteria:
  # - A failed walk renders the problem note "Computation failed. Reload
  #   retries." and no table, whatever result the page still holds.
  test "a failed walk is the problem note, never a table" do
    html = render_table(result([position(1, "5")]), failed?: true)

    assert text(html, "[data-role='contribution-failed']") =~
             "Computation failed. Reload retries."

    assert Floki.find(Floki.parse_fragment!(html), "#contribution-table") == []
  end

  # User story (FR-41, ADR-0051 §10 and §12):
  # As a local portfolio maintainer reading the table's rows,
  # I want every row named and every unvalued reason in words,
  # so that a security stored without a name, a position sold out inside the
  # period and a missing exchange rate each read for what they are.
  #
  # Acceptance criteria:
  # - A position without a name reads as its ISIN; without either, as "—".
  # - A position held at the start but not at the end says "no longer held
  #   at the end" under its name.
  # - A position that counted zero for lack of a rate is named in the note
  #   with "no exchange rate stored".
  test "rows name a nameless security, a sold-out position and a missing rate" do
    positions = [
      position(1, "30", %{name: nil, isin: "XSEXMPL40031"}),
      position(2, "20", %{name: nil}),
      position(3, "-10", %{held_at_end: false, end_value: d("0")}),
      position(4, "-15", %{unvalued_days: 12, unvalued_reason: :no_rate})
    ]

    html = render_table(result(positions))

    assert text(html, "#contribution-table tr[data-security-id='1'] td:first-child") ==
             "XSEXMPL40031"

    assert text(html, "#contribution-table tr[data-security-id='2'] td:first-child") == "—"

    assert text(html, "#contribution-table tr[data-security-id='3'] td:first-child") ==
             "Position 3 no longer held at the end"

    assert text(html, "[data-role='contribution-unvalued']") =~
             "Position 4 (12 days, no exchange rate stored)"
  end

  # User story (FR-41, board pick A):
  # As a local portfolio maintainer with more than ten positions,
  # I want the ten largest by absolute amount, ties kept in the table's
  # order,
  # so that the shown rows do not change between two renders of one result.
  #
  # Acceptance criteria:
  # - Two positions of equal absolute contribution at the tenth place: the
  #   one earlier in the table's order is shown, the later one hidden.
  test "a tie at the tenth place keeps the table's order" do
    # Nine clear leaders, then +5 (id 10) and -5 (id 11) tie on amount, then
    # a smaller one (id 12).
    leaders = for id <- 1..9, do: position(id, Integer.to_string(100 - id))
    positions = leaders ++ [position(10, "5"), position(12, "1"), position(11, "-5")]

    shown = ContributionTable.shown_positions(positions, false)

    assert Enum.map(shown, & &1.security_id) == Enum.to_list(1..10)
  end
end
