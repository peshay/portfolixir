defmodule PortfolixirWeb.Api.V1.TaxSnapshotController do
  @moduledoc """
  Recorded tax-statement snapshots and the derived trim budget over the JSON
  API (ADR-0031, AR-11).

  **These pots are recorded, not derived** — and not because FIFO is missing:
  `Ledger.TradeMatcher` matches lots FIFO and its gross gain is available at
  `/api/v1/securities/:id/trades`. A gross gain is not a tax pot.
  Teilfreistellung, Vorabpauschale, chronological allowance consumption and
  certified prior-year carry-forward are not in the transaction data at all,
  and the pots are kept per tax-reporting institution, which Portfolixir does
  not model — so a derived pot would be wrong, and invisibly so. Do not attempt
  to compute these numbers from holdings; transcribe the statement.

  Every financial decimal serializes as a string. Each snapshot travels with
  `allowance_remaining`, `tax_free_trim_budget`, the `as_of` they rest on, a
  `stale` flag, and the advisory consistency findings. Findings state which two
  numbers disagree and by how much; they never propose a corrected value and
  never block a write.
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Tax
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, params) do
    snapshots =
      Tax.list_snapshots(
        holder: params["holder"],
        institution: params["institution"],
        tax_year: parse_year(params["tax_year"])
      )

    json(conn, %{data: Enum.map(snapshots, &serialize/1)})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, snapshot_id} <- parse_id(id),
         {:ok, snapshot} <- Tax.fetch_snapshot(snapshot_id) do
      json(conn, %{data: serialize(snapshot)})
    else
      _otherwise -> not_found(conn)
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "statement_snapshot", %{})

    case Tax.create_snapshot(conn.assigns.actor, attrs) do
      {:ok, snapshot} -> conn |> put_status(201) |> json(%{data: serialize(snapshot)})
      {:error, changeset} -> unprocessable(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "statement_snapshot", %{})

    with {:ok, snapshot_id} <- parse_id(id),
         {:ok, snapshot} <- Tax.fetch_snapshot(snapshot_id) do
      case Tax.update_snapshot(conn.assigns.actor, snapshot, attrs) do
        {:ok, updated} -> json(conn, %{data: serialize(updated)})
        {:error, changeset} -> unprocessable(conn, changeset)
      end
    else
      _otherwise -> not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, snapshot_id} <- parse_id(id),
         {:ok, snapshot} <- Tax.delete_snapshot(conn.assigns.actor, snapshot_id) do
      json(conn, %{data: serialize(snapshot)})
    else
      _otherwise -> not_found(conn)
    end
  end

  @doc """
  The per-holder roll-up for a tax year (ADR-0031 §5): the latest statement per
  institution, summed, with the institutions it covers and whether the picture
  is complete.
  """
  def trim_budget(conn, %{"holder" => holder} = params) do
    case parse_year(params["tax_year"]) do
      nil -> missing_param(conn, "tax_year")
      year -> json(conn, %{data: JSON.tax_trim_budget(Tax.holder_summary(holder, year))})
    end
  end

  def trim_budget(conn, _params), do: missing_param(conn, "holder")

  defp serialize(snapshot) do
    JSON.tax_statement_snapshot(snapshot, findings: Tax.findings_for(snapshot))
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp parse_year(nil), do: nil

  defp parse_year(value) when is_binary(value) do
    case Integer.parse(value) do
      {year, ""} -> year
      _other -> nil
    end
  end

  defp parse_year(value) when is_integer(value), do: value

  defp missing_param(conn, param) do
    conn |> put_status(422) |> json(%{errors: %{param => ["is required"]}})
  end

  defp unprocessable(conn, changeset) do
    conn |> put_status(422) |> json(%{errors: JSON.errors(changeset)})
  end

  defp not_found(conn) do
    conn |> put_status(404) |> json(%{errors: %{detail: "Not found"}})
  end
end
