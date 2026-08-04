defmodule PortfolixirWeb.Api.V1.PeriodParam do
  @moduledoc """
  Shared parsing for the performance period parameters (#563).

  Besides the fixed `period` strings (`ytd|1y|3y|5y|max`), a request may ask
  for one calendar year (`?year=YYYY`) or a custom date range
  (`?from=&to=`, ISO dates, both required). The parsed term goes straight to
  `Portfolixir.Portfolios.Performance.summarise/2`, which owns the range
  validation (`from <= to`) and the honest clamping to the available history.

  Returns `{:ok, period_term}` or `{:error, :invalid_period}` for a malformed
  year, a half-given or unparsable range. Precedence: an explicit range wins
  over `year`, which wins over `period`.
  """

  @spec resolve(map()) :: {:ok, term()} | {:error, :invalid_period}
  def resolve(params) do
    cond do
      Map.has_key?(params, "from") or Map.has_key?(params, "to") ->
        range(Map.get(params, "from"), Map.get(params, "to"))

      Map.has_key?(params, "year") ->
        year(Map.get(params, "year"))

      true ->
        {:ok, Map.get(params, "period", "max")}
    end
  end

  defp range(from, to) when is_binary(from) and is_binary(to) do
    with {:ok, from_date} <- Date.from_iso8601(from),
         {:ok, to_date} <- Date.from_iso8601(to) do
      {:ok, {:range, from_date, to_date}}
    else
      _invalid -> {:error, :invalid_period}
    end
  end

  defp range(_from, _to), do: {:error, :invalid_period}

  defp year(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {year, ""} -> {:ok, {:year, year}}
      _invalid -> {:error, :invalid_period}
    end
  end

  defp year(_raw), do: {:error, :invalid_period}
end
