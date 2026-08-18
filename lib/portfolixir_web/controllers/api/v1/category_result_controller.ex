defmodule PortfolixirWeb.Api.V1.CategoryResultController do
  @moduledoc """
  Per-category result (ADR-0041 slice one, issue #712): what each category of a
  classification tree cost, what it is worth now, and what it has made.

  Kept as its own endpoint rather than folded into the allocation read: the two
  answer different questions off different engines — allocation compares actual
  against target, this compares current value against cost — and merging them
  would couple `Allocation` to the cost side for no consumer that needs both in
  one call.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CategoryResult
  alias Portfolixir.Portfolios.Portfolio
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, cid} <- classification_id(Map.get(params, "classification_id")) do
      case CategoryResult.for_portfolio(pid, cid) do
        {:ok, result} -> json(conn, %{data: JSON.category_result(result)})
        {:error, :not_found} -> not_found(conn)
      end
    else
      :missing -> unprocessable(conn, %{classification_id: ["is required"]})
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  defp classification_id(nil), do: :missing
  defp classification_id(value), do: parse_id(value)

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
