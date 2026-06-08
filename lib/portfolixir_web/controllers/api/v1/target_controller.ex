defmodule PortfolixirWeb.Api.V1.TargetController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid) do
      targets = Targets.list_targets(pid, list_opts(params))
      json(conn, %{data: %{targets: Enum.map(targets, &JSON.target/1)}})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  def set(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid) do
      set_for_portfolio(conn, pid, params)
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  def delete(conn, %{"portfolio_id" => portfolio_id, "category_id" => category_id}) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, cid} <- parse_id(category_id) do
      {:ok, count} = Targets.delete_target(pid, cid)
      json(conn, %{data: %{deleted: count}})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  defp set_for_portfolio(conn, pid, params) do
    with {:ok, cid} <- parse_id(Map.get(params, "classification_id")),
         entries when is_list(entries) <- Map.get(params, "targets") do
      case Targets.set_targets(pid, cid, entries) do
        {:ok, targets} ->
          json(conn, %{data: %{targets: Enum.map(targets, &JSON.target/1)}})

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      :error -> unprocessable(conn, %{classification_id: ["is required"]})
      _ -> unprocessable(conn, %{targets: ["must be a list"]})
    end
  end

  defp list_opts(params) do
    case parse_id(Map.get(params, "classification_id")) do
      {:ok, cid} -> [classification_id: cid]
      :error -> []
    end
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset),
    do: unprocessable(conn, JSON.errors(changeset))

  defp render_error(conn, :not_found), do: not_found(conn)

  defp render_error(conn, :category_mismatch),
    do: unprocessable(conn, %{detail: "category does not belong to the classification"})

  defp render_error(conn, :invalid_entry),
    do:
      unprocessable(conn, %{targets: ["must be a list of {category_id, target_weight} objects"]})

  defp parse_id(value) when is_integer(value), do: {:ok, value}

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
