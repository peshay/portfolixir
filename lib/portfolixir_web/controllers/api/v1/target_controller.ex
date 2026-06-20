defmodule PortfolixirWeb.Api.V1.TargetController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  # Since ADR-0020 a SOLL plan belongs to a view: the target read/write endpoints
  # accept an optional `view` query/body param (omitted/null = the Gesamt plan).
  # The view is resolved with the shared #445 helper so a bad or unknown view
  # fails with the same structured error contract as the analytics endpoints,
  # instead of crashing or silently steering Gesamt.
  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params) do
      targets = Targets.list_targets(pid, list_opts(params, view))
      json(conn, %{data: %{targets: Enum.map(targets, &JSON.target/1)}})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> invalid_view(conn)
      :view_not_found -> not_found(conn)
    end
  end

  def set(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params) do
      set_for_portfolio(conn, pid, params, view)
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> invalid_view(conn)
      :view_not_found -> not_found(conn)
    end
  end

  def delete(conn, %{"portfolio_id" => portfolio_id, "category_id" => category_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, cid} <- parse_id(category_id) do
      {:ok, count} = Targets.delete_target(pid, cid, ViewParam.opts(view))
      json(conn, %{data: %{deleted: count}})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> invalid_view(conn)
      :view_not_found -> not_found(conn)
    end
  end

  # The per-plan cash target moved out of the portfolio object (ADR-0020). It is
  # readable/writable here per view; `view` omitted reads/writes the Gesamt
  # cash plan, which is the same value the legacy portfolio `cash_target_weight`
  # field still reads and writes (back-compat).
  def show_cash_target(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params) do
      weight = Targets.get_cash_target(pid, ViewParam.opts(view))
      json(conn, %{data: JSON.cash_target(weight)})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> invalid_view(conn)
      :view_not_found -> not_found(conn)
    end
  end

  def set_cash_target(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params) do
      weight = Map.get(params, "cash_target_weight")

      case Targets.set_cash_target(pid, weight, ViewParam.opts(view)) do
        :ok -> json(conn, %{data: JSON.cash_target(weight)})
        {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> invalid_view(conn)
      :view_not_found -> not_found(conn)
    end
  end

  defp set_for_portfolio(conn, pid, params, view) do
    with {:ok, cid} <- parse_id(Map.get(params, "classification_id")),
         entries when is_list(entries) <- Map.get(params, "targets") do
      case Targets.set_targets(pid, cid, entries, ViewParam.opts(view)) do
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

  defp list_opts(params, view) do
    base = ViewParam.opts(view)

    case parse_id(Map.get(params, "classification_id")) do
      {:ok, cid} -> [{:classification_id, cid} | base]
      :error -> base
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

  defp invalid_view(conn), do: unprocessable(conn, %{view: ["is invalid"]})

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
