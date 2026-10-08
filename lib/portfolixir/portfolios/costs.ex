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

  Each cost is read in its **cash account's currency**, the currency of the
  cash leg it is part of (the ADR-0015 amendment of 2026-10-07, #1107): on a
  cross-currency trade that is not the booking's currency, which is the
  security's. It converts into the base currency through the **EUR hub** at
  the rate stored on its own booking date; a cost with no
  stored rate for that day is **excluded from the totals and named** by that
  currency — the same excluded-and-named rule as the sibling facets.
  """

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount

  @zero Decimal.new("0")
  @months 1..12

  @doc """
  Builds the costs report across all portfolios.

  Options: `:base_currency`; `:limit` keeps the newest `limit` years of the
  annual matrix (#776), `computation_basis.window` naming the cut.
  """
  def report(opts \\ []) do
    base = Keyword.get_lazy(opts, :base_currency, &default_base/0)
    limit = Keyword.get(opts, :limit)

    {converted, excluded} =
      Ledger.list_transactions()
      |> Enum.flat_map(&cost_legs/1)
      |> Enum.map(&convert_cost(&1, base))
      |> Enum.split_with(&match?({:ok, _}, &1))

    converted = Enum.map(converted, fn {:ok, cost} -> cost end)
    excluded = Enum.map(excluded, fn {:excluded, cost} -> cost end)

    full = annual_matrix(converted)
    annual = newest_years(full, limit)

    %{
      base_currency: base,
      annual: annual,
      limit: limit,
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
        # The ADR-0015 amendment of 2026-10-07 (#1107).
        currency:
          "each cost is read in its cash account's currency, the currency of the cash leg " <>
            "it is part of, and converted from that currency at the EUR hub rate stored on " <>
            "its booking date: a cross-currency trade's fees and taxes (ADR-0015) are never " <>
            "read in the security's currency; a booking without a cash account is read in " <>
            "its own currency; an excluded cost is named by the currency it was read in",
        window: window(full, annual, "grouped by booking date"),
        reference: "EUR hub rates on each booking date itself",
        gaps: "a cost with no stored booking-date rate is excluded from the totals and named"
      }
    }
  end

  # #776: a limit keeps the newest years of the matrix (sorted newest first);
  # the window names the cut when one happened, so a shorter answer never
  # reads as a shorter history.
  defp newest_years(annual, nil), do: annual
  defp newest_years(annual, n) when is_integer(n) and n > 0, do: Enum.take(annual, n)

  defp window(full, kept, grouping) when length(kept) < length(full),
    do: "the newest #{length(kept)} years of the full ledger history, #{grouping}"

  defp window(_full, _kept, grouping), do: "full ledger history, #{grouping}"

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
    %{date: tx.date, series: series, currency_code: cost_currency(tx), amount: amount}
  end

  # The ADR-0015 amendment of 2026-10-07 (#1107): a booking's fees and taxes,
  # and a standalone cost's cash, are in its CASH ACCOUNT's currency, the
  # currency of the cash leg they are part of (`Ledger.SettlementGuard`). On a
  # cross-currency trade that is not the booking's currency, which is the
  # security's. This is the walk's reading since #1051
  # (`Performance.trade_cost/2`), and like the walk it falls back to the
  # booking's currency only where the booking has no cash account.
  defp cost_currency(%{cash_account: %CashAccount{currency_code: currency}})
       when is_binary(currency),
       do: currency

  defp cost_currency(tx), do: tx.currency_code

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
