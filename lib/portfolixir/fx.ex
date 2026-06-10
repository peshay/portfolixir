defmodule Portfolixir.Fx do
  @moduledoc """
  Foreign-exchange rates and currency conversion.

  Rates are stored as a dated upsert log (`exchange_rates`) against a single hub
  currency, **EUR**, matching the ECB reference rates (`1 EUR = rate quote`).
  Any pair is converted by triangulation through EUR; same-currency conversion
  is the identity. The `GBX` (pence) pseudo-currency is handled as `GBP × 100`,
  so it falls out of the same arithmetic with no special case in the conversion
  path.

  All arithmetic stays at full `Decimal` precision — never floats, never an
  intermediate round (see ADR-0003, ADR-0007). Rounding is a display concern.
  """

  import Ecto.Query

  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Repo

  @hub "EUR"
  @gbx_per_gbp Decimal.new(100)
  @one Decimal.new(1)

  @doc """
  Bulk upsert of EUR-hub rates keyed by `(base_currency, quote_currency, date)`.

  Validates each row through the schema changeset first; if any row fails we
  return `{:error, changeset}` and write nothing. Returns `{:ok, count}`.
  """
  def upsert_many(rows) when is_list(rows) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    case prepare_rows(rows, now) do
      {:ok, []} ->
        {:ok, 0}

      {:ok, prepared} ->
        {count, _} =
          Repo.insert_all(ExchangeRate, prepared,
            on_conflict: {:replace, [:rate, :source, :updated_at]},
            conflict_target: [:base_currency, :quote_currency, :date]
          )

        {:ok, count}

      {:error, _} = err ->
        err
    end
  end

  @doc "Most recent rate for `base/quote` on or before `date`, or nil."
  def at_or_before(base, quote, %Date{} = date) do
    base_quote(base, quote)
    |> where([r], r.date <= ^date)
    |> order_by([r], desc: r.date)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Most recent stored rate for `base/quote`, or nil."
  def latest(base, quote) do
    base_quote(base, quote)
    |> order_by([r], desc: r.date)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  All EUR-hub rates for `quote_currency` from `from` onward, ascending by date.

  Used by read-time engines (e.g. the daily performance walk) to preload a
  currency's whole rate series once and convert in memory instead of issuing
  one lookup query per day.
  """
  def series(quote_currency, %Date{} = from) do
    base_quote(@hub, quote_currency)
    |> where([r], r.date >= ^from)
    |> order_by([r], asc: r.date)
    |> Repo.all()
  end

  @doc "Most recent EUR-hub rate for `quote_currency` on or before `date`, or nil."
  def hub_rate_before(quote_currency, %Date{} = date) do
    at_or_before(@hub, quote_currency, date)
  end

  @doc "All stored rates, most recent first."
  def list_rates do
    Repo.all(
      from(r in ExchangeRate,
        order_by: [desc: r.date, asc: r.base_currency, asc: r.quote_currency]
      )
    )
  end

  @doc """
  Converts `amount` from one currency to another.

  Pass a `%Date{}` as the third argument to value as of that date (most recent
  rate on or before it); omit it to use the latest known rate. Returns
  `{:ok, Decimal}` or `{:error, :no_rate}` when no rate path exists.
  """
  def convert(amount, from, to, date \\ nil)

  def convert(%Decimal{} = amount, from, to, _date) when from == to, do: {:ok, amount}

  def convert(%Decimal{} = amount, from, to, date) do
    with {:ok, rate} <- rate(from, to, date) do
      {:ok, Decimal.mult(amount, rate)}
    end
  end

  @doc """
  Returns the rate to convert one unit of `from` into `to` (`to` per 1 `from`).

  Triangulates through EUR. Returns `{:ok, Decimal}` or `{:error, :no_rate}`.
  """
  def rate(from, to, date \\ nil)

  def rate(from, to, _date) when from == to, do: {:ok, @one}

  def rate(from, to, date) do
    with {:ok, from_rate} <- eur_rate(from, date),
         {:ok, to_rate} <- eur_rate(to, date) do
      {:ok, Decimal.div(to_rate, from_rate)}
    end
  end

  # Units of `ccy` per 1 EUR, the hub-relative rate everything triangulates on.
  defp eur_rate(@hub, _date), do: {:ok, @one}

  defp eur_rate("GBX", date) do
    with {:ok, gbp} <- eur_rate("GBP", date) do
      {:ok, Decimal.mult(gbp, @gbx_per_gbp)}
    end
  end

  defp eur_rate(ccy, date) do
    case lookup(ccy, date) do
      %ExchangeRate{rate: rate} -> {:ok, rate}
      nil -> {:error, :no_rate}
    end
  end

  defp lookup(ccy, nil), do: latest(@hub, ccy)
  defp lookup(ccy, %Date{} = date), do: at_or_before(@hub, ccy, date)

  defp base_quote(base, quote) do
    from(r in ExchangeRate, where: r.base_currency == ^base and r.quote_currency == ^quote)
  end

  defp prepare_rows(rows, now) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case ExchangeRate.changeset(%ExchangeRate{}, row) do
        %{valid?: true} = changeset ->
          entry =
            changeset.changes
            |> Map.take([:base_currency, :quote_currency, :date, :rate, :source])
            |> Map.put(:inserted_at, now)
            |> Map.put(:updated_at, now)

          {:cont, {:ok, [entry | acc]}}

        invalid ->
          {:halt, {:error, invalid}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      {:error, _} = err -> err
    end
  end
end
