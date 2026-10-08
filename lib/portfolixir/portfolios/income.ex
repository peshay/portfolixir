defmodule Portfolixir.Portfolios.Income do
  @moduledoc """
  Read-time income report for one portfolio: the dividends and interest already
  booked in the ledger, seen retrospectively (issue #331).

  This is a pure aggregation of existing `dividend` and `interest` transactions
  — no external data, no forecast (the dividend calendar is issue #320). It
  reports three views from one read:

    * an **annual matrix** (`year → month → {dividends, interest}`) with a
      yearly total per series, so the page can render a year × month grid;
    * a **per-position** table (security, gross, withheld tax, net, number of
      payments, last payment), so a maintainer sees which holding paid what;
    * the **per-transaction** detail, so a year can be drilled into.

  ## Gross / withheld tax / net

  Portfolio Performance books a `dividend` with the **net** cash credited to the
  account in `gross_amount` and the withheld tax in the transaction's `taxes`
  field (the dividend's TAX units, see the import parsers). The income report
  therefore reads `net = gross_amount`, `withheld tax = taxes`, and
  `gross = net + withheld tax`. Interest carries no withholding here, so its
  gross equals its amount.

  ## Currency

  A booking's cash and withheld tax are read in its **cash account's
  currency**, the currency the account was credited in (the ADR-0015
  amendment of 2026-10-07): a dividend of a foreign security credited to an
  account in another currency is read in the account's, never in the
  security's. Amounts are converted into the portfolio's `base_currency_code`
  through the
  **EUR hub** (`Portfolixir.Fx`), at the most recent stored rate **on or before
  the booking date** — the same mechanics `Portfolixir.Portfolios.Valuation`
  uses, reused rather than reimplemented. Each per-transaction detail names
  the currency its native amounts are in (`currency`, the account's); each
  per-position row keeps the booking's currency (`security_currency`). A booking with
  no rate path to the base currency is converted at parity and surfaces in
  `unconverted_count` so a missing rate never silently distorts a total. The
  chosen basis is described in `base_currency` and `conversion_note`
  (FR-13).
  """

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount

  @zero Decimal.new("0")
  @months 1..12

  @doc """
  Builds the income report for `portfolio_id`.

  Options (for tests):

    * `:base_currency` — overrides the portfolio's base currency.
  """
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    base_currency =
      Keyword.get_lazy(opts, :base_currency, fn -> base_currency_for(portfolio_id) end)

    entries =
      [portfolio_id: portfolio_id]
      |> Ledger.list_transactions()
      |> Enum.filter(&(&1.type in ["dividend", "interest"]))
      |> Enum.map(&entry(&1, base_currency))

    %{
      portfolio_id: portfolio_id,
      base_currency: base_currency,
      conversion_note: conversion_note(base_currency),
      unconverted_count: Enum.count(entries, &(not &1.converted)),
      annual: annual(entries),
      positions: positions(entries),
      transactions: Enum.map(entries, &detail/1)
    }
  end

  # One normalised income entry, with both native and base-currency amounts. The
  # base-currency amounts feed the matrix and totals; the native gross/tax/net
  # and `currency` keep the original visible.
  defp entry(tx, base_currency) do
    native_net = tx.gross_amount || @zero
    native_tax = if tx.type == "dividend", do: tx.taxes || @zero, else: @zero
    native_gross = Decimal.add(native_net, native_tax)
    cash_currency = cash_currency(tx)

    {gross, converted?} = convert(native_gross, cash_currency, base_currency, tx.date)
    {tax, _} = convert(native_tax, cash_currency, base_currency, tx.date)
    net = Decimal.sub(gross, tax)

    %{
      kind: tx.type,
      date: tx.date,
      year: tx.date.year,
      month: tx.date.month,
      security_id: tx.security_id,
      security_name: security_name(tx),
      # The currency the native amounts are in, the cash account's; the
      # per-position table keeps grouping by the booking's currency.
      currency: cash_currency,
      booking_currency: tx.currency_code,
      native_gross: native_gross,
      native_tax: native_tax,
      native_net: native_net,
      gross: gross,
      tax: tax,
      net: net,
      converted: converted?
    }
  end

  defp annual(entries) do
    entries
    |> Enum.group_by(& &1.year)
    |> Enum.map(fn {year, year_entries} -> year_row(year, year_entries) end)
    |> Enum.sort_by(& &1.year, :desc)
  end

  defp year_row(year, year_entries) do
    months =
      Map.new(@months, fn month ->
        month_entries = Enum.filter(year_entries, &(&1.month == month))

        {month,
         %{
           dividends: sum_gross(month_entries, "dividend"),
           interest: sum_gross(month_entries, "interest")
         }}
      end)

    dividends_total = sum_gross(year_entries, "dividend")
    interest_total = sum_gross(year_entries, "interest")

    %{
      year: year,
      months: months,
      dividends_total: dividends_total,
      interest_total: interest_total,
      total: Decimal.add(dividends_total, interest_total)
    }
  end

  defp positions(entries) do
    entries
    |> Enum.group_by(&{&1.security_id, &1.booking_currency})
    |> Enum.map(fn {{security_id, currency}, group} ->
      position_row(security_id, currency, group)
    end)
    |> Enum.sort_by(& &1.gross, {:desc, Decimal})
  end

  defp position_row(security_id, currency, group) do
    gross = sum(group, & &1.gross)
    tax = sum(group, & &1.tax)
    sample = hd(group)

    %{
      security_id: security_id,
      security_name: sample.security_name,
      security_currency: currency,
      gross: gross,
      tax: tax,
      net: Decimal.sub(gross, tax),
      payment_count: length(group),
      last_payment: group |> Enum.map(& &1.date) |> Enum.max(Date)
    }
  end

  defp detail(entry) do
    %{
      kind: entry.kind,
      date: entry.date,
      year: entry.year,
      security_id: entry.security_id,
      security_name: entry.security_name,
      currency: entry.currency,
      native_gross: entry.native_gross,
      native_tax: entry.native_tax,
      native_net: entry.native_net,
      gross: entry.gross,
      tax: entry.tax,
      net: entry.net,
      converted: entry.converted
    }
  end

  defp sum_gross(entries, kind) do
    entries
    |> Enum.filter(&(&1.kind == kind))
    |> sum(& &1.gross)
  end

  defp sum(entries, fun) do
    Enum.reduce(entries, @zero, fn entry, acc -> Decimal.add(acc, fun.(entry)) end)
  end

  # Reuses the EUR-hub conversion (see `Portfolixir.Fx`) at the booking date's
  # rate, mirroring `Portfolixir.Portfolios.Valuation`. A missing rate path
  # falls back to parity and flags the entry as unconverted, so a total is never
  # silently dropped.
  defp convert(%Decimal{} = amount, from, base, %Date{} = date)
       when is_binary(from) and is_binary(base) do
    case Fx.convert(amount, from, base, date) do
      {:ok, converted} -> {converted, true}
      {:error, _reason} -> {amount, false}
    end
  end

  defp convert(%Decimal{} = amount, _from, _base, _date), do: {amount, true}

  # The ADR-0015 amendment of 2026-10-07 (the income report's sibling of
  # #1107): a booking's cash and taxes are in its CASH ACCOUNT's currency, the
  # currency the projection credits them in. A dividend booked in a foreign
  # security's currency and credited to an account in another (ADR-0015, with
  # its stored settlement rate) is therefore read in the account's currency,
  # as the performance walk reads its cash. A booking without a cash account
  # is read in its own currency.
  defp cash_currency(%{cash_account: %CashAccount{currency_code: currency}})
       when is_binary(currency),
       do: currency

  defp cash_currency(tx), do: tx.currency_code

  defp security_name(%{security: %{name: name}}) when is_binary(name), do: name
  defp security_name(_tx), do: nil

  defp base_currency_for(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %{base_currency_code: code} -> code
      _ -> nil
    end
  end

  defp conversion_note(base_currency) do
    "Amounts converted to #{base_currency} via the EUR hub at each booking " <>
      "date's stored rate; original currency retained. A booking's cash and " <>
      "withheld tax are read in its cash account's currency, the currency they " <>
      "were credited in."
  end
end
