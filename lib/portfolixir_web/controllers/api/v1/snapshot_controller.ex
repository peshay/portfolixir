defmodule PortfolixirWeb.Api.V1.SnapshotController do
  @moduledoc """
  Depot snapshots over the JSON API (ADR-0027, AR-11 parity with the Snapshots
  tab): list/create/delete the ledger markers, and read the counterfactual
  comparison (buy-and-hold of the frozen holdings vs. the scope's real TTWROR
  since the as-of date). Financial decimals serialize as strings; the
  comparison is self-describing (basis, base currency, gaps — AR-4).
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    snapshots = Snapshots.list_snapshots()
    json(conn, %{data: %{snapshots: Enum.map(snapshots, &JSON.snapshot/1)}})
  end

  def create(conn, params) do
    attrs = %{
      name: params["name"],
      as_of: params["as_of"],
      view_id: params["view_id"]
    }

    case Snapshots.create_snapshot(conn.assigns.actor, attrs) do
      {:ok, snapshot} ->
        conn |> put_status(201) |> json(%{data: JSON.snapshot(snapshot)})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, snapshot_id} <- parse_id(id),
         {:ok, snapshot} <- Snapshots.delete_snapshot(conn.assigns.actor, snapshot_id) do
      json(conn, %{data: JSON.snapshot(snapshot)})
    else
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
    end
  end

  def comparison(conn, %{"portfolio_id" => portfolio_id, "id" => id}) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, snapshot_id} <- parse_id(id),
         {:ok, comparison} <- SnapshotComparison.for_snapshot(snapshot_id, pid) do
      json(conn, %{data: JSON.snapshot_comparison(comparison)})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
      {:error, :view_not_found} -> not_found(conn)
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp unprocessable(conn, errors) do
    conn |> put_status(422) |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn |> put_status(404) |> json(%{errors: %{detail: "Not found"}})
  end
end
