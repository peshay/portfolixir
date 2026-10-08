defmodule Portfolixir.Fx.HistoryGaps do
  @moduledoc """
  Which currencies the stored exchange rates do not reach back far enough
  for (#1120, D-5 of the Sprint 20 plan), and which of them a completed
  history backfill has not sought yet.

  **The condition.** A currency is *open* when a booking in it is dated
  before its earliest stored EUR-hub rate, or when it has no stored rate at
  all. A booking is "in" a currency when the currency is the booking's own
  (`currency_code`, a trade's price currency), the currency of the cash
  account it settles through (a cross-currency trade's cash leg, ADR-0015),
  or its portfolio's base currency, which every day of the walk converts
  into. EUR is the hub and is never open; GBX is read as GBP, the stored
  rate it derives from (`Portfolixir.Fx`). The date is the currency's
  earliest booking date.

  **The guard ("once").** A completed backfill fetches the provider's whole
  series, so after one a currency can stay open only where no fetch can
  close it: the provider does not publish it, or the booking predates the
  series (the ECB's begins in 1999). A currency a completed run sought is
  therefore recorded (`record_sought/1`, kept in `Portfolixir.Settings`, so
  it survives a restart) and is no longer *due*, though it stays open: the
  performance walk still counts such a balance zero and names it
  (ADR-0051 §10). A run that failed records nothing, so the next trigger
  tries again.

  Read-only except `record_sought/1`; three grouped queries and one
  settings read, issued by the background trigger, never by a read path.
  """

  import Ecto.Query

  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Repo
  alias Portfolixir.Settings

  @hub "EUR"

  @doc """
  Every open currency with its earliest booking date: a booking in it
  predates its earliest stored rate, or it has none. `%{}` when every
  booking has a rate path from its first day.
  """
  @spec open() :: %{String.t() => Date.t()}
  def open do
    first_rates = earliest_rates()

    earliest_bookings()
    |> Enum.filter(fn {currency, booked} ->
      case Map.get(first_rates, currency) do
        nil -> true
        %Date{} = first_rate -> Date.compare(booked, first_rate) == :lt
      end
    end)
    |> Map.new()
  end

  @doc """
  The open currencies a completed backfill has not sought yet: what the
  automatic backfill fetches for. `%{}` when nothing is due.
  """
  @spec due() :: %{String.t() => Date.t()}
  def due, do: Map.drop(open(), sought())

  @doc "The currencies a completed backfill already sought, sorted."
  @spec sought() :: [String.t()]
  def sought, do: Settings.fx_history_sought()

  @doc "Records that a completed backfill sought `currencies` (cumulative)."
  @spec record_sought([String.t()]) :: :ok
  def record_sought(currencies) when is_list(currencies),
    do: Settings.add_fx_history_sought(currencies)

  # `%{currency => earliest booking date}` over the three ways a booking is
  # in a currency, GBX read as GBP and the hub left out.
  defp earliest_bookings do
    own =
      from(t in Transaction,
        where: not is_nil(t.currency_code),
        group_by: t.currency_code,
        select: %{currency: t.currency_code, date: min(t.date)}
      )

    settling =
      from(t in Transaction,
        join: c in CashAccount,
        on: c.id == t.cash_account_id,
        group_by: c.currency_code,
        select: %{currency: c.currency_code, date: min(t.date)}
      )

    base =
      from(t in Transaction,
        join: p in Portfolio,
        on: p.id == t.portfolio_id,
        group_by: p.base_currency_code,
        select: %{currency: p.base_currency_code, date: min(t.date)}
      )

    own
    |> union_all(^settling)
    |> union_all(^base)
    |> Repo.all()
    |> Enum.reduce(%{}, fn %{currency: currency, date: date}, acc ->
      case stored_currency(currency) do
        nil -> acc
        code -> Map.update(acc, code, date, &Enum.min([&1, date], Date))
      end
    end)
  end

  defp earliest_rates do
    from(r in ExchangeRate,
      where: r.base_currency == ^@hub,
      group_by: r.quote_currency,
      select: {r.quote_currency, min(r.date)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp stored_currency(nil), do: nil
  defp stored_currency(@hub), do: nil
  defp stored_currency("GBX"), do: "GBP"
  defp stored_currency(code) when is_binary(code), do: code
end
