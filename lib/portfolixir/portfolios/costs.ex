defmodule Portfolixir.Portfolios.Costs do
  @moduledoc """
  Read-time costs report at **overview level only** (issue #726): what the
  portfolio cost to run — fees and taxes per period. The "only" is the
  requirement: no per-instrument or per-transaction cost table without a new
  decision.

  ## The series

  The facet sums the **fee and tax legs** riding any transaction (`fees`,
  `taxes`) plus the **standalone** `fee` and `tax` bookings
  (`gross_amount`), and nets `tax_refund` bookings against taxes. It never
  touches gross amounts: a `buy`'s gross is **inclusive** of its legs while
  a `sell`'s is **net** of them (`Ledger.Projection`), so a sum over gross
  amounts would describe something else entirely — summing the legs is the
  one series that means "costs" for every kind.

  ## FX basis

  Each cost converts into the base currency through the **EUR hub** at the
  rate stored on its own booking date; a cost with no
  stored rate for that day is **excluded from the totals and named** by its
  currency — the same excluded-and-named rule as the sibling facets.
  """

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")
  @months 1..12

  @doc "Builds the costs report across all portfolios."
  def report(opts \\ []) do
    base = Keyword.get_lazy(opts, :base_currency, &default_base/0)

    {converted, excluded} =
      Ledger.list_transactions()
      |> Enum.flat_map(&cost_legs/1)
      |> Enum.map(&convert_cost(&1, base))
      |> Enum.split_with(&match?({:ok, _}, &1))

    converted = Enum.map(converted, fn {:ok, cost} -> cost end)
    excluded = Enum.map(excluded, fn {:excluded, cost} -> cost end)

    %{
      base_currency: base,
      annual: annual_matrix(converted),
      excluded: %{
        count: length(excluded),
        currencies: excluded |> Enum.map(& &1.currency_code) |> Enum.uniq() |> Enum.sort()
      },
      conversion_note:
        "Each cost converted to #{base} via the EUR hub at the rate stored on its " <>
          "own booking date; a cost with no stored rate for " <>
          "that date is excluded from the totals and named by its currency.",
      computation_basis: %{
        series:
          "fee and tax legs riding any transaction plus standalone fee/tax bookings, " <>
            "with tax_refund netted against taxes; gross amounts are never summed " <>
            "(a buy's gross includes its legs, a sell's is net of them)",
        window: "full ledger history, grouped by booking date",
        reference: "EUR hub rates on each booking date itself",
        gaps: "a cost with no stored booking-date rate is excluded from the totals and named"
      }
    }
  end

  defp default_base do
    case Portfolios.first_portfolio() do
      %{base_currency_code: base} when is_binary(base) -> base
      _none -> "EUR"
    end
  end

  # One cost entry per non-zero leg. Standalone kinds carry their amount in
  # gross_amount; every other kind contributes its fee/tax legs.
  defp cost_legs(%{type: "fee"} = tx), do: [cost(tx, :fees, tx.gross_amount)]
  defp cost_legs(%{type: "tax"} = tx), do: [cost(tx, :taxes, tx.gross_amount)]

  defp cost_legs(%{type: "tax_refund"} = tx),
    do: [cost(tx, :taxes, tx.gross_amount && Decimal.negate(tx.gross_amount))]

  defp cost_legs(tx) do
    [cost(tx, :fees, tx.fees), cost(tx, :taxes, tx.taxes)]
  end

  defp cost(tx, series, amount) do
    %{date: tx.date, series: series, currency_code: tx.currency_code, amount: amount}
  end

  defp convert_cost(%{amount: nil}, _base), do: {:ok, nil}

  defp convert_cost(cost, base) do
    if Decimal.equal?(cost.amount, @zero) do
      {:ok, nil}
    else
      case Fx.convert_on(cost.amount, cost.currency_code, base, cost.date) do
        {:ok, converted} -> {:ok, Map.put(cost, :amount_base, converted)}
        {:error, :no_rate} -> {:excluded, cost}
      end
    end
  end

  defp annual_matrix(costs) do
    costs
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(& &1.date.year)
    |> Enum.sort_by(fn {year, _} -> year end, :desc)
    |> Enum.map(fn {year, year_costs} ->
      months =
        Map.new(@months, fn month ->
          in_month = Enum.filter(year_costs, &(&1.date.month == month))
          {month, %{fees: sum_series(in_month, :fees), taxes: sum_series(in_month, :taxes)}}
        end)

      fees_total = months |> Map.values() |> Enum.reduce(@zero, &Decimal.add(&2, &1.fees))
      taxes_total = months |> Map.values() |> Enum.reduce(@zero, &Decimal.add(&2, &1.taxes))

      %{
        year: year,
        months: months,
        fees_total: fees_total,
        taxes_total: taxes_total,
        total: Decimal.add(fees_total, taxes_total)
      }
    end)
  end

  defp sum_series(costs, series) do
    costs
    |> Enum.filter(&(&1.series == series))
    |> Enum.reduce(@zero, &Decimal.add(&2, &1.amount_base))
  end
end
