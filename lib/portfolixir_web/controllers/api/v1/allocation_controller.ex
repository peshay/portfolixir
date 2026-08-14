defmodule PortfolixirWeb.Api.V1.AllocationController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Portfolio
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, cid} <- classification_id(Map.get(params, "classification_id")),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, include_positions} <- include_positions_param(params),
         {:ok, min_drift} <- min_drift_param(params) do
      case Allocation.for_portfolio(pid, cid, ViewParam.opts(view)) do
        {:ok, allocation} ->
          data =
            allocation
            |> JSON.allocation(include_positions: include_positions, min_drift: min_drift)
            |> ViewParam.put_active(view)

          json(conn, %{data: data})

        {:error, :not_found} ->
          not_found(conn)

        # The view vanished between resolve and read (fix round TOCTOU):
        # still a plain 404, never a 500.
        {:error, :view_not_found} ->
          not_found(conn)
      end
    else
      :missing -> unprocessable(conn, %{classification_id: ["is required"]})
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      {:error, :include_positions} -> unprocessable(conn, %{include_positions: ["is invalid"]})
      {:error, :min_drift} -> unprocessable(conn, %{min_drift: ["is invalid"]})
      :view_not_found -> not_found(conn)
    end
  end

  defp classification_id(nil), do: :missing
  defp classification_id(value), do: parse_id(value)

  # FR-37 (#665): `include_positions=false` for a roll-up-only read.
  defp include_positions_param(params) do
    case Map.get(params, "include_positions", "true") do
      value when value in ["true", ""] -> {:ok, true}
      "false" -> {:ok, false}
      _other -> {:error, :include_positions}
    end
  end

  # FR-37 (#665): `min_drift` is a non-negative Decimal-string threshold on
  # |drift_weight|; parsing is exact (no float detour) and anything that is
  # not a full clean Decimal is a 422.
  defp min_drift_param(params) do
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
