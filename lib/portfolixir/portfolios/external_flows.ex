defmodule Portfolixir.Portfolios.ExternalFlows do
  @moduledoc """
  Read-time deposits-and-withdrawals report (issue #725): the booked external
  **cash** flows — `deposit` and `removal` transactions — aggregated per
  period. The owner's "Ersparnis": what was put in and taken out, separate
  from what the portfolio earned.

  ## Relation to invested capital (#568)

  The performance walk's `invested_capital` counts every external flow the
  projection marks (`Ledger.Projection.effects/1`): the booked cash flows
  **plus** securities delivered in or out at market value and the residual
  jump of a balance snapshot. This facet deliberately counts only the booked
  cash flows — a delivery is not money the operator paid in that period, and
  a snapshot residual has no booking the operator chose. The difference is
  stated in the payload (`computation_basis.excludes`) so the two figures can
  disagree without either lying.

  ## FX basis

  Each flow converts into the base currency through the **EUR hub** at the
  rate stored on its own booking date; a flow with no
  stored rate at that date is **excluded from the totals and named** by its
  cash account — the same excluded-and-named rule as the Realized-gains
  facet (D-1's shape, applied uniformly across the Cash-flow facets).
  """

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")
  @months 1..12

  @doc "Builds the deposits-and-withdrawals report across all portfolios."
  def report(opts \\ []) do
    base = Keyword.get_lazy(opts, :base_currency, &default_base/0)
    accounts = Map.new(Portfolios.list_cash_accounts(), &{&1.id, &1.name})

    {converted, excluded} =
      Ledger.list_transactions()
      |> Enum.filter(&(&1.type in ["deposit", "removal"]))
      |> Enum.map(&convert_flow(&1, base, accounts))
      |> Enum.split_with(&match?({:ok, _}, &1))

    converted = Enum.map(converted, fn {:ok, flow} -> flow end)
    excluded = Enum.map(excluded, fn {:excluded, flow} -> flow end)

    %{
      base_currency: base,
      annual: annual_matrix(converted),
      excluded: %{
        count: length(excluded),
        accounts: excluded |> Enum.map(& &1.account_name) |> Enum.uniq() |> Enum.sort()
      },
      conversion_note:
        "Each flow converted to #{base} via the EUR hub at the rate stored on its " <>
          "own booking date; a flow with no stored rate for " <>
          "that date is excluded from the totals and named by its cash account.",
      computation_basis: %{
        series: "gross_amount of booked deposit and removal transactions",
        window: "full ledger history, grouped by booking date",
        reference: "EUR hub rates on each booking date itself",
        gaps: "a flow with no stored booking-date rate is excluded from the totals and named",
        excludes:
          "securities delivered in or out and balance-snapshot residuals — the " <>
            "performance's invested-capital figure counts them, which is why the " <>
            "two can differ"
      }
    }
  end

  defp default_base do
    case Portfolios.first_portfolio() do
      %{base_currency_code: base} when is_binary(base) -> base
      _none -> "EUR"
    end
  end

  defp convert_flow(tx, base, accounts) do
    flow = %{
      date: tx.date,
      kind: tx.type,
      account_name: Map.get(accounts, tx.cash_account_id, "?"),
      amount: tx.gross_amount
    }

    case Fx.convert_on(tx.gross_amount, tx.currency_code, base, tx.date) do
      {:ok, converted} -> {:ok, Map.put(flow, :amount_base, converted)}
      {:error, :no_rate} -> {:excluded, flow}
    end
  end

  defp annual_matrix(flows) do
    flows
    |> Enum.group_by(& &1.date.year)
    |> Enum.sort_by(fn {year, _} -> year end, :desc)
    |> Enum.map(fn {year, year_flows} ->
      months =
        Map.new(@months, fn month ->
          in_month = Enum.filter(year_flows, &(&1.date.month == month))

          {month,
           %{deposits: sum_kind(in_month, "deposit"), withdrawals: sum_kind(in_month, "removal")}}
        end)

      deposits_total = months |> Map.values() |> Enum.reduce(@zero, &Decimal.add(&2, &1.deposits))

      withdrawals_total =
        months |> Map.values() |> Enum.reduce(@zero, &Decimal.add(&2, &1.withdrawals))

      %{
        year: year,
        months: months,
        deposits_total: deposits_total,
        withdrawals_total: withdrawals_total,
        net_total: Decimal.sub(deposits_total, withdrawals_total)
      }
    end)
  end

  defp sum_kind(flows, kind) do
    flows
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.reduce(@zero, &Decimal.add(&2, &1.amount_base))
  end
end
