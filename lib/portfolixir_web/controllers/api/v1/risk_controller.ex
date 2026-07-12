defmodule PortfolixirWeb.Api.V1.RiskController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.Risk
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  @zero Decimal.new("0")

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, opts} <- risk_opts(params) do
      # The view can vanish between resolve and read (fix round TOCTOU):
      # still a plain 404, never a 500.
      case Risk.for_portfolio(pid, Keyword.merge(opts, ViewParam.opts(view))) do
        {:error, :view_not_found} ->
          not_found(conn)

        risk ->
          data = risk |> JSON.risk() |> ViewParam.put_active(view)
          json(conn, %{data: data})
      end
    else
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
      :view_not_found -> not_found(conn)
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  # Builds the option list for `Risk.for_portfolio/2` from the query params. All
  # overrides are optional (the lens ships sane FR10 defaults); each carries a
  # validation so a malformed override returns 422 rather than crashing.
  defp risk_opts(params) do
    with {:ok, top_n} <- top_n_param(params),
         {:ok, caps} <- caps_param(params),
         {:ok, bands} <- bands_param(params),
         {:ok, stock} <- stock_thresholds_param(params),
         {:ok, etf} <- etf_thresholds_param(params) do
      opts =
        []
        |> put_opt(:top_n, top_n)
        |> put_opt(:asset_class_caps, caps)
        |> put_opt(:hhi_bands, bands)
        |> put_opt(:stock_thresholds, stock)
        |> put_opt(:etf_thresholds, etf)

      {:ok, opts}
    end
  end

  defp top_n_param(%{"top_n" => value}) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :top_n}
    end
  end

  defp top_n_param(%{"top_n" => n}) when is_integer(n) and n > 0, do: {:ok, n}
  defp top_n_param(%{"top_n" => _}), do: {:error, :top_n}
  defp top_n_param(_params), do: {:ok, nil}

  defp caps_param(%{"asset_class_caps" => caps}) when is_map(caps) do
    parse_decimal_map(caps, :asset_class_caps)
  end

  defp caps_param(%{"asset_class_caps" => _}), do: {:error, :asset_class_caps}
  defp caps_param(_params), do: {:ok, nil}

  defp bands_param(%{"hhi_bands" => bands}) when is_map(bands) do
    with {:ok, low} <- optional_decimal(bands, "low", :hhi_bands),
         {:ok, high} <- optional_decimal(bands, "high", :hhi_bands) do
      band_map =
        %{}
        |> put_present(:low, low)
        |> put_present(:high, high)

      if band_map == %{}, do: {:ok, nil}, else: {:ok, band_map}
    end
  end

  defp bands_param(%{"hhi_bands" => _}), do: {:error, :hhi_bands}
  defp bands_param(_params), do: {:ok, nil}

  defp stock_thresholds_param(%{"stock_thresholds" => map}) when is_map(map) do
    optional_warn_hard(map, :stock_thresholds)
  end

  defp stock_thresholds_param(%{"stock_thresholds" => _}), do: {:error, :stock_thresholds}
  defp stock_thresholds_param(_params), do: {:ok, nil}

  defp etf_thresholds_param(%{"etf_thresholds" => map}) when is_map(map) do
    case optional_decimal(map, "warn", :etf_thresholds) do
      {:ok, nil} -> {:ok, nil}
      {:ok, warn} -> {:ok, %{warn: warn}}
      error -> error
    end
  end

  defp etf_thresholds_param(%{"etf_thresholds" => _}), do: {:error, :etf_thresholds}
  defp etf_thresholds_param(_params), do: {:ok, nil}

  defp optional_warn_hard(map, field) do
    with {:ok, warn} <- optional_decimal(map, "warn", field),
         {:ok, hard} <- optional_decimal(map, "hard", field) do
      result =
        %{}
        |> put_present(:warn, warn)
        |> put_present(:hard, hard)

      if result == %{}, do: {:ok, nil}, else: {:ok, result}
    end
  end

  # Parses every value of a string-keyed map into a non-negative Decimal,
  # returning `{:error, field}` on the first malformed entry.
  defp parse_decimal_map(map, field) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case to_decimal(value) do
        {:ok, decimal} -> {:cont, {:ok, Map.put(acc, key, decimal)}}
        :error -> {:halt, {:error, field}}
      end
    end)
  end

  defp optional_decimal(map, key, field) do
    case Map.get(map, key) do
      nil ->
        {:ok, nil}

      value ->
        case to_decimal(value) do
          {:ok, decimal} -> {:ok, decimal}
          :error -> {:error, field}
        end
    end
  end

  defp to_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} ->
        if Decimal.compare(decimal, @zero) == :lt, do: :error, else: {:ok, decimal}

      _ ->
        :error
    end
  end

  defp to_decimal(_value), do: :error

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  # Keyword-list variant for the `Risk.for_portfolio/2` option list (the lens
  # consumes a keyword list, not a map). Absent (`nil`) overrides are dropped.
  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
