defmodule PortfolixirWeb.Api.V1.ViewValuationController do
  @moduledoc """
  JSON API for the cross-portfolio view valuation (ADR-0024): one view's total
  wealth across all portfolios, with each account counted once regardless of
  how many of the view's included buckets it carries. The response includes
  account-level `overlap` data for UI badges and echoes the active view
  (FR-13). Financial decimals are serialized as strings.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  def show(conn, %{"view_id" => view_id} = params) do
    with {:ok, vid} <- parse_id(view_id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, include_positions} <- include_positions_param(params),
         # The view can vanish between the lookup and the valuation read (fix
         # round TOCTOU): `for_view/2` degrades to a not-found error, so the
         # endpoint still answers a plain 404, never a 500.
         %{} = valuation <- Valuation.for_view(view.id) do
      data =
        valuation
        |> JSON.view_valuation(include_positions: include_positions)
        |> ViewParam.put_active(view)

      json(conn, %{data: data})
    else
      {:error, :include_positions} -> unprocessable(conn, %{include_positions: ["is invalid"]})
      _ -> not_found(conn)
    end
  end

  # FR-37 (#665) reaching the view scope (#740): `include_positions=false` for
  # a roll-up-only read, the same spelling as the portfolio valuation.
  defp include_positions_param(params) do
    case Map.get(params, "include_positions", "true") do
      value when value in ["true", ""] -> {:ok, true}
      "false" -> {:ok, false}
      _other -> {:error, :include_positions}
    end
  end

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
