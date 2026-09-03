defmodule PortfolixirWeb.Api.V1.DriftParam do
  @moduledoc """
  The one spelling of the `min_drift=` threshold (FR-37, #665; #740).

  A non-negative Decimal string on `|drift_weight|` — parsed exactly, no float
  detour; anything that is not a full clean Decimal is `{:error, :min_drift}`
  and the caller answers `422`. Both the allocation read and the
  position-target listing parse the parameter here, so "the rows that
  deviate" is asked the same way one level up and one level down, and the
  predicate that answers it is `Portfolixir.Portfolios.Allocation.drift_at_least?/2`.
  """

  @spec parse(map()) :: {:ok, Decimal.t() | nil} | {:error, :min_drift}
  def parse(params) when is_map(params) do
    case Map.get(params, "min_drift") do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      value when is_binary(value) ->
        case Decimal.parse(value) do
          {%Decimal{} = threshold, ""} ->
            if Decimal.compare(threshold, 0) == :lt do
              {:error, :min_drift}
            else
              {:ok, threshold}
            end

          _other ->
            {:error, :min_drift}
        end

      _other ->
        {:error, :min_drift}
    end
  end
end
