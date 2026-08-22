defmodule Portfolixir.Portfolios.RealizedGains do
  @moduledoc """
  Read-time realized-gains report across **all** securities (issue #724): the
  FIFO-matched closed round-trips the ledger already derives per security
  (`Ledger.list_trades_for_security/2`), collected into one cash-flow-shaped
  aggregate — realized P&L per period, by each trade's **close date**.

  ## FX basis (D-1, signed 2026-08-20)

  Each sale converts into the base currency through the **EUR hub**
  (`Portfolixir.Fx`) at the most recent stored rate **on or before its close
  date** — the same basis the Income facet uses, because the realized figure
  is a historical fact tied to its date. A sale whose close-date rate is not
  stored is **excluded from the converted totals and named** (count plus
  security names) — never converted at a neighbouring date's rate, never
  silently dropped. This is deliberately stricter than Income's
  parity-with-counter behaviour: a realized figure is a headline number, and
  a guessed rate would be a guessed gain.

  The basis travels in the payload (`computation_basis`, `conversion_note`)
  per the AGENTS.md metric rule.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")
  @months 1..12

  @doc """
  Builds the realized-gains report across all securities and portfolios.

  Options:

    * `:base_currency` — overrides the default (the first portfolio's base
      currency, `"EUR"` when none exists).
  """
  def report(opts \\ []) do
    base = Keyword.get_lazy(opts, :base_currency, &default_base/0)

    {converted, excluded} =
      traded_securities()
      |> Enum.flat_map(&closed_trades/1)
      |> Enum.map(&convert_trade(&1, base))
      |> Enum.split_with(&match?({:ok, _}, &1))

    converted = Enum.map(converted, fn {:ok, trade} -> trade end)
    excluded = Enum.map(excluded, fn {:excluded, trade} -> trade end)

    %{
      base_currency: base,
      annual: annual_matrix(converted),
      excluded: %{
        count: length(excluded),
        securities: excluded |> Enum.map(& &1.security_name) |> Enum.uniq() |> Enum.sort()
      },
      conversion_note:
        "Each sale converted to #{base} via the EUR hub at the most recent stored " <>
          "rate on or before its close date; a sale with no stored rate path at " <>
          "that date is excluded from the totals and named, never converted at a " <>
          "neighbouring date's rate.",
      computation_basis: %{
        series:
          "realized_pnl_abs per FIFO-matched closed trade (proceeds net of sell fees and taxes, minus consumed basis)",
        window: "full ledger history, grouped by each trade's close date",
        reference: "EUR hub rates at or before each close date (D-1, issue #724)",
        gaps:
          "a sale with no stored close-date rate is excluded from the converted totals and named in excluded"
      }
    }
  end

  defp default_base do
    case Portfolios.first_portfolio() do
      %{base_currency_code: base} when is_binary(base) -> base
      _none -> "EUR"
    end
  end

  # The securities that can carry closed trades: every security with a sell
  # booked. Read once from the ledger; the local dataset is bounded.
  defp traded_securities do
    sold_ids =
      Ledger.list_transactions()
      |> Enum.filter(&(&1.type == "sell"))
      |> Enum.map(& &1.security_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    for id <- sold_ids, security = Catalog.get_security(id), not is_nil(security) do
      security
    end
  end

  defp closed_trades(security) do
    security.id
    |> Ledger.list_trades_for_security()
    |> Map.get(:closed_trades, [])
    |> Enum.map(fn trade ->
      %{
        security_name: security.name,
        close_date: trade.close_date,
        currency_code: trade.currency_code || security.currency_code,
        realized_pnl_abs: trade.realized_pnl_abs
      }
    end)
  end

  defp convert_trade(trade, base) do
    case Fx.convert(trade.realized_pnl_abs, trade.currency_code, base, trade.close_date) do
      {:ok, converted} -> {:ok, Map.put(trade, :realized_base, converted)}
      {:error, :no_rate} -> {:excluded, trade}
    end
  end

  defp annual_matrix(trades) do
    trades
    |> Enum.group_by(& &1.close_date.year)
    |> Enum.sort_by(fn {year, _} -> year end, :desc)
    |> Enum.map(fn {year, year_trades} ->
      months =
        Map.new(@months, fn month ->
          total =
            year_trades
            |> Enum.filter(&(&1.close_date.month == month))
            |> Enum.reduce(@zero, &Decimal.add(&2, &1.realized_base))

          {month, total}
        end)

      %{
        year: year,
        months: months,
        total: Enum.reduce(Map.values(months), @zero, &Decimal.add/2)
      }
    end)
  end
end
