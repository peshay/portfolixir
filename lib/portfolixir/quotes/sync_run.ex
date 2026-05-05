defmodule Portfolixir.Quotes.SyncRun do
  @moduledoc "Read-only quote sync that persists provider quotes via Catalog upserts."

  alias Portfolixir.Catalog
  alias Portfolixir.Quotes

  @spec sync_security(module(), integer(), map()) :: {:ok, map()} | {:error, :security_not_found}
  def sync_security(provider_module, security_id, opts \\ %{})

  def sync_security(provider_module, security_id, opts)
      when is_atom(provider_module) and is_integer(security_id) and is_map(opts) do
    case Catalog.get_security(security_id) do
      nil ->
        {:error, :security_not_found}

      security ->
        config = Map.get(opts, :config, %{})
        summary = base_summary(security.id)

        summary =
          summary
          |> sync_historical(provider_module, security, config)
          |> maybe_sync_latest(provider_module, security, config, opts)

        {:ok, summary}
    end
  end

  def sync_security(_provider_module, _security_id, _opts), do: {:error, :security_not_found}

  @spec sync_all(module(), map()) :: {:ok, [map()]}
  def sync_all(provider_module, opts \\ %{}) when is_atom(provider_module) and is_map(opts) do
    summaries =
      Catalog.list_securities()
      |> Enum.map(fn security ->
        case sync_security(provider_module, security.id, opts) do
          {:ok, summary} -> summary
          {:error, :security_not_found} -> base_summary(security.id)
        end
      end)

    {:ok, summaries}
  end

  defp sync_historical(summary, provider_module, security, config) do
    security_ref = security_ref(security)

    case Quotes.historical_quotes(provider_module, config, security_ref) do
      {:ok, quotes} when is_list(quotes) ->
        Enum.reduce(quotes, summary, fn quote, acc ->
          upsert_quote(acc, security.id, quote)
        end)

      {:error, reason} ->
        summary
        |> inc(:failed)
        |> add_warning("historical_quotes failed: #{inspect(reason)}")
    end
  end

  defp maybe_sync_latest(summary, provider_module, security, config, opts) do
    if Map.get(opts, :sync_latest, true) do
      case Quotes.latest_quote(provider_module, config, security_ref(security)) do
        {:ok, nil} ->
          summary

        {:ok, quote} ->
          upsert_quote(summary, security.id, quote)

        {:error, reason} ->
          summary
          |> inc(:failed)
          |> add_warning("latest_quote failed: #{inspect(reason)}")
      end
    else
      summary
    end
  end

  defp upsert_quote(summary, security_id, quote) when is_map(quote) do
    attrs =
      quote
      |> Map.take([
        :date,
        :source,
        :currency_code,
        :open,
        :high,
        :low,
        :close,
        :volume,
        :metadata
      ])
      |> Map.put(:security_id, security_id)
      |> Map.put_new(:source, "provider")
      |> Map.put_new(:metadata, %{})

    existing =
      Catalog.list_security_quotes(security_id)
      |> Enum.find(fn existing_quote ->
        existing_quote.date == attrs.date and existing_quote.source == attrs.source
      end)

    case Catalog.upsert_security_quote(attrs) do
      {:ok, _quote} ->
        classify_upsert(summary, existing, attrs)

      {:error, reason} ->
        summary
        |> inc(:failed)
        |> add_warning("upsert failed for #{attrs.source} #{attrs.date}: #{inspect(reason)}")
    end
  end

  defp classify_upsert(summary, nil, _attrs), do: inc(summary, :created)

  defp classify_upsert(summary, existing, attrs) do
    if quote_changed?(existing, attrs) do
      inc(summary, :updated)
    else
      inc(summary, :skipped)
    end
  end

  defp quote_changed?(existing, attrs) do
    decimal_changed?(existing.open, attrs[:open]) or
      decimal_changed?(existing.high, attrs[:high]) or
      decimal_changed?(existing.low, attrs[:low]) or
      decimal_changed?(existing.close, attrs[:close]) or
      decimal_changed?(existing.volume, attrs[:volume]) or
      existing.currency_code != attrs[:currency_code] or
      (existing.metadata || %{}) != attrs[:metadata]
  end

  defp decimal_changed?(left, right) do
    normalize_decimal(left) != normalize_decimal(right)
  end

  defp normalize_decimal(nil), do: nil
  defp normalize_decimal(%Decimal{} = value), do: Decimal.normalize(value)

  defp normalize_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> Decimal.normalize(decimal)
      _ -> value
    end
  end

  defp normalize_decimal(value) when is_integer(value),
    do: Decimal.new(value) |> Decimal.normalize()

  defp normalize_decimal(value) when is_float(value),
    do: Decimal.from_float(value) |> Decimal.normalize()

  defp normalize_decimal(value), do: value

  defp security_ref(security) do
    %{symbol: security.provider_symbol || security.symbol}
  end

  defp base_summary(security_id) do
    %{security_id: security_id, created: 0, updated: 0, skipped: 0, failed: 0, warnings: []}
  end

  defp inc(summary, key), do: Map.update!(summary, key, &(&1 + 1))
  defp add_warning(summary, warning), do: Map.update!(summary, :warnings, &(&1 ++ [warning]))
end
