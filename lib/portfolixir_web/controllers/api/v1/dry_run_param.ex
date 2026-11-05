defmodule PortfolixirWeb.Api.V1.DryRunParam do
  @moduledoc """
  The `dry_run` query parameter of the three cascading deletes (Sprint 25
  X1, #894; the plan's D-4): `DELETE /api/v1/classifications/:id`,
  `DELETE /api/v1/classifications/:classification_id/categories/:id` and
  `DELETE /api/v1/views/:id`.

  `dry_run=true` runs the real delete in a transaction that always rolls
  back (`Portfolixir.DryRun`) and answers 200 with what it would remove, per
  kind; a delete the server refuses is refused by its dry run with the same
  status and body. Absent, empty or `false` is the delete itself; any other
  value answers 422 `errors.dry_run ["is invalid"]`, as the API's other
  boolean query parameters do, so a typo never turns a question into a
  delete.
  """

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @doc "Reads `dry_run` from the request's params: `{:ok, boolean}` or `{:error, :dry_run}`."
  @spec parse(map()) :: {:ok, boolean()} | {:error, :dry_run}
  def parse(params) when is_map(params) do
    case Map.get(params, "dry_run") do
      value when value in [nil, "", "false", false] -> {:ok, false}
      value when value in ["true", true] -> {:ok, true}
      _other -> {:error, :dry_run}
    end
  end

  @doc """
  The dry run's answer: `{"data": {"dry_run": true, "would_remove": {kind:
  {"count": n, "ids": [...]}}}}`, every kind the delete reaches listed, a
  count of 0 where none would go.
  """
  @spec answer(Plug.Conn.t(), Portfolixir.DryRun.removed()) :: Plug.Conn.t()
  def answer(conn, removed) when is_map(removed),
    do: json(conn, %{data: %{dry_run: true, would_remove: removed}})

  @doc "The 422 a `dry_run` that is not a boolean answers."
  @spec invalid(Plug.Conn.t()) :: Plug.Conn.t()
  def invalid(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{dry_run: ["is invalid"]}})
  end
end
