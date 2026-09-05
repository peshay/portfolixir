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

  alias Portfolixir.Derived.Invalidation
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

        # Allowlisted out of the journal for the same reason as quotes, so the
        # invalidation is announced here (ADR-0032 §3.4).
        Invalidation.after_exchange_rate_write()

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

  @doc """
  The latest EUR-hub rate (units of the currency per 1 EUR) for each of
  `currencies`, in ONE query — the bulk form of the per-row lookup `rate/3`
  issues (ADR-0035).

  Returns `%{currency => Decimal}`. A currency with no stored rate path is
  **absent** from the map, which is what makes an absent key mean exactly
  `{:error, :no_rate}` for the callers below and nothing else. The hub itself
  resolves to `1` and `GBX` (pence) to `GBP × 100`, so the map answers the same
  questions `eur_rate/2` answers with `date: nil`.
  """
  def hub_rates(currencies) when is_list(currencies) do
    requested = currencies |> Enum.filter(&is_binary/1) |> Enum.uniq()

    stored =
      requested
      |> Enum.map(&hub_source_currency/1)
      |> Enum.reject(&(&1 == @hub))
      |> Enum.uniq()
      |> latest_hub_rates()

    Enum.reduce(requested, %{}, fn currency, acc ->
      case hub_rate_from(currency, stored) do
        {:ok, rate} -> Map.put(acc, currency, rate)
        {:error, :no_rate} -> acc
      end
    end)
  end

  @doc """
  `convert/4` (latest rates) resolved from a preloaded `hub_rates/1` map.

  Same arithmetic, same order, same short-circuit for a same-currency pair, so
  the result is Decimal-identical to `convert/3` — only the rate lookup moves
  from a query to memory.
  """
  def convert_with_hub_rates(%Decimal{} = amount, from, to, _hub_rates) when from == to,
    do: {:ok, amount}

  def convert_with_hub_rates(%Decimal{} = amount, from, to, hub_rates) when is_map(hub_rates) do
    with {:ok, rate} <- rate_from_hub_rates(from, to, hub_rates) do
      {:ok, Decimal.mult(amount, rate)}
    end
  end

  @doc """
  `rate/3` (latest rates) resolved from a preloaded `hub_rates/1` map.

  Triangulates through the hub exactly as `rate/3` does; a currency missing
  from the map yields `{:error, :no_rate}`, the same answer the query path
  gives for a currency with no stored rate.
  """
  def rate_from_hub_rates(from, to, _hub_rates) when from == to, do: {:ok, @one}

  def rate_from_hub_rates(from, to, hub_rates) when is_map(hub_rates) do
    with {:ok, from_rate} <- fetch_hub_rate(hub_rates, from),
         {:ok, to_rate} <- fetch_hub_rate(hub_rates, to) do
      {:ok, Decimal.div(to_rate, from_rate)}
    end
  end

  defp fetch_hub_rate(hub_rates, currency) do
    case Map.get(hub_rates, currency) do
      %Decimal{} = rate -> {:ok, rate}
      _missing -> {:error, :no_rate}
    end
  end

  # GBX is not stored; it is derived from GBP (see `eur_rate/2`).
  defp hub_source_currency("GBX"), do: "GBP"
  defp hub_source_currency(currency), do: currency

  defp hub_rate_from(@hub, _stored), do: {:ok, @one}

  defp hub_rate_from("GBX", stored) do
    with {:ok, gbp} <- hub_rate_from("GBP", stored) do
      {:ok, Decimal.mult(gbp, @gbx_per_gbp)}
    end
  end

  defp hub_rate_from(currency, stored) do
    case Map.get(stored, currency) do
      %Decimal{} = rate -> {:ok, rate}
      _missing -> {:error, :no_rate}
    end
  end

  # One `DISTINCT ON` per quote currency, ordered like `latest/2`: the row with
  # the greatest date wins, and `(base, quote, date)` is unique, so the pick is
  # the same row `latest/2` returns.
  defp latest_hub_rates([]), do: %{}

  defp latest_hub_rates(currencies) do
    Repo.all(
      from(r in ExchangeRate,
        where: r.base_currency == ^@hub and r.quote_currency in ^currencies,
        order_by: [asc: r.quote_currency, desc: r.date],
        distinct: r.quote_currency,
        select: {r.quote_currency, r.rate}
      )
    )
    |> Map.new()
  end

  @doc "Stored rates, most recent first; `limit:` bounds the read (#771)."
  def list_rates(opts \\ []) do
    query =
      from(r in ExchangeRate,
        order_by: [desc: r.date, asc: r.base_currency, asc: r.quote_currency]
      )

    query =
      case Keyword.get(opts, :limit) do
        n when is_integer(n) and n > 0 -> limit(query, ^n)
        _ -> query
      end

    Repo.all(query)
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

  @doc """
  Converts `amount` using the rate stored on **exactly** `date`.

  `convert/4` values at the most recent rate on or before the date, which is
  right for a valuation: yesterday's rate is the best estimate of today's when
  today has none. It is wrong for a figure that must be *auditable against its
  own booking date* — realized gains (#724, D-1): valuing a sale at a
  neighbouring date's rate produces a wrong number wearing the right units.
  A caller that must not do that asks for this one and handles `:no_rate` by
  excluding and naming the row.
  """
  @spec convert_on(Decimal.t(), String.t(), String.t(), Date.t()) ::
          {:ok, Decimal.t()} | {:error, :no_rate}
  def convert_on(%Decimal{} = amount, from, to, %Date{} = date) do
    with {:ok, rate} <- rate_on(from, to, date) do
      {:ok, Decimal.mult(amount, rate)}
    end
  end

  @doc """
  The rate on **exactly** `date`, triangulated through EUR. Never falls back
  to an earlier date; `{:error, :no_rate}` when either leg has no row for
  that day.
  """
  @spec rate_on(String.t(), String.t(), Date.t()) :: {:ok, Decimal.t()} | {:error, :no_rate}
  def rate_on(from, to, %Date{} = _date) when from == to, do: {:ok, @one}

  def rate_on(from, to, %Date{} = date) do
    with {:ok, from_rate} <- eur_rate_on(from, date),
         {:ok, to_rate} <- eur_rate_on(to, date) do
      {:ok, Decimal.div(to_rate, from_rate)}
    end
  end

  defp eur_rate_on(@hub, _date), do: {:ok, @one}

  defp eur_rate_on("GBX", date) do
    with {:ok, gbp} <- eur_rate_on("GBP", date) do
      {:ok, Decimal.mult(gbp, @gbx_per_gbp)}
    end
  end

  defp eur_rate_on(ccy, date) do
    case Repo.get_by(ExchangeRate, base_currency: @hub, quote_currency: ccy, date: date) do
      %ExchangeRate{rate: rate} -> {:ok, rate}
      nil -> {:error, :no_rate}
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
