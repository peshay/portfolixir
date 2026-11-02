defmodule PortfolixirWeb.MergeFlowsCase do
  @moduledoc """
  The flow section both merge previews share (Sprint 23 V2, #957; board
  `ux-design-2026-11-02-sprint23/01` ①b), read the way the operator reads
  it, and its parity with the API's `flow_changes` for the same pair: one
  row per entry, in the API's order, with its kind, date, collapsed booking,
  quantity and amount. Used by the depot and the security merge LiveView
  tests; every figure in them is synthetic.
  """
  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn

  @endpoint PortfolixirWeb.Endpoint

  @method_lines [
    "Removed: a collapsed inbound or outbound delivery, an external flow of its portfolio on its date. Quantity: the change in the units of that flow; the amount at the booked price, without a price at the day's price.",
    "View boundary: a transfer, buy or sell with exactly one leg in the view, a flow across its boundary and none of the portfolio's; one entry per view.",
    "Set balance: the cash of a removed booking that its account's next set balance absorbs as its residual.",
    "Each listed day's flow changes by these entries alone; the return from that day on also reads the removed units no longer held. The preview therefore lists the flows, not a recomputed return.",
    "View membership is read as it stands; the merge does not change it."
  ]

  @basis "One entry per flow of the time-weighted return that removing the duplicates drops or moves · amounts in the account's currency"

  @doc "The \"true\" outcome's `flow_changes` the API answers at `path`."
  def api_flow_changes(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> get_in(["data", "outcome_by_collapse_key_equal", "true", "flow_changes"])
  end

  @doc "Each wide row's cells as visible text, top to bottom."
  def cells(view, dialog) do
    for row <- find(view, dialog, "table.merge-flows-table tr[data-role='merge-flow']") do
      row |> Floki.find("td") |> Enum.map(&text/1)
    end
  end

  @doc """
  The section lists exactly the API's entries, in order, in both forms:
  the wide table and the two-line rows under 720 px.
  """
  def assert_parity(view, dialog, api) do
    rows = find(view, dialog, "table.merge-flows-table tr[data-role='merge-flow']")
    lines = find(view, dialog, "ul.merge-lines li[data-role='merge-flow-line']")

    assert length(rows) == length(api)
    assert length(lines) == length(api)

    for {{row, line}, entry} <- Enum.zip(Enum.zip(rows, lines), api) do
      for node <- [row, line] do
        assert attr(node, "data-kind") == entry["kind"]
        assert attr(node, "data-date") == entry["date"]
        assert attr(node, "data-transaction-id") == to_string(entry["collapsed_transaction_id"])
      end

      [date, _effect, _booking, quantity, flow] = row |> Floki.find("td") |> Enum.map(&text/1)
      assert date == entry["date"]
      assert quantity == quantity_text(entry["quantity"])
      assert String.starts_with?(flow, amount_text(entry))

      line_text = text(line)
      assert line_text =~ amount_text(entry)

      if entry["quantity"],
        do: assert(line_text =~ "#{quantity_text(entry["quantity"])} shares")
    end
  end

  @doc """
  The section's anatomy: its heading with the qualifier and the ⓘ holding
  the five method sentences, the table for wide screens, the two-line rows
  under 720 px, and the short basis visible.
  """
  def assert_section(view, dialog) do
    section = "#{dialog} section.merge-flows[data-role='merge-flows']"

    assert has_element?(
             view,
             "#{section} .section-title h3.merge-block-head",
             "External flows"
           )

    assert has_element?(view, "#{section} h3 small", "with “remove as duplicates”")
    assert has_element?(view, "#{section} .data-table-wrapper.merge-wide table.merge-flows-table")
    assert has_element?(view, "#{section} ul.merge-lines.merge-narrow")

    [tooltip] =
      find(view, section, ".section-title details[data-role='section-info'] p[role='tooltip']")

    assert tooltip
           |> Floki.children()
           |> Enum.reject(&match?({"br", _, _}, &1))
           |> Enum.map(&text/1) ==
             @method_lines

    [basis] = find(view, section, "p.merge-basis")
    assert text(basis) == @basis
    refute has_element?(view, "#{dialog} [data-role='merge-flows-none']")
  end

  @doc "No entry: the single basis line and no section."
  def assert_empty(view, dialog) do
    assert has_element?(
             view,
             "#{dialog} p.merge-basis[data-role='merge-flows-none']",
             "External flows: none is removed or moved; the return reads the same flows."
           )

    refute has_element?(view, "#{dialog} [data-role='merge-flows']")
  end

  defp quantity_text(nil), do: "—"
  defp quantity_text(quantity), do: PortfolixirWeb.Format.exact(Decimal.new(quantity), "en")

  defp amount_text(%{"change" => nil}), do: "—"

  defp amount_text(%{"change" => change, "currency_code" => currency}),
    do: "#{PortfolixirWeb.Format.money(Decimal.new(change), "en")} #{currency}"

  defp find(view, scope, selector) do
    view
    |> element(scope)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
  end

  defp attr(node, name), do: node |> Floki.attribute(name) |> List.first()

  defp text(node) do
    [node]
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
