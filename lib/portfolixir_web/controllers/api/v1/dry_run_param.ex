defmodule PortfolixirWeb.Api.V1.DryRunParam do
  @moduledoc """
  The `dry_run` query parameter of the three cascading deletes (Sprint 25
  X1, #894; the plan's D-4): `DELETE /api/v1/classifications/:id`,
  `DELETE /api/v1/classifications/:classification_id/categories/:id` and
  `DELETE /api/v1/views/:id`.

  `dry_run=true` runs the real delete in a transaction that always rolls
  back (`Portfolixir.DryRun`) and answers 200 with what it would remove, per
  kind; a delete the server refuses is refused by its dry run with the same
  status and body, and a dry run a concurrent change intervened in answers
  409 `errors.code "concurrent_change"`, nothing deleted, to retry. Absent or `false` is the delete itself; any other value,
  an empty `dry_run=` included, answers 422 `errors.dry_run ["is invalid"]`,
  as the API's other boolean query parameters do, and any other parameter
  (`dryRun`, `dry-run`, `dryrun`, ...) answers 422 naming it, so a typo never
  turns a question into a delete (Sprint 25 closing act: before, a
  misspelled key was dropped and an empty value read as false, and both ran
  the real delete).
  """

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @unknown "is unknown: this delete takes only dry_run"

  @doc """
  Reads `dry_run` from the request: `{:ok, boolean}`, or
  `{:error, {:dry_run_param, errors}}` for a `dry_run` that is not a boolean
  or for any other query (or body) parameter, which `invalid/2` answers.
  The route's path parameters are not looked at.
  """
  @spec parse(Plug.Conn.t()) :: {:ok, boolean()} | {:error, {:dry_run_param, map()}}
  def parse(%Plug.Conn{} = conn) do
    case unknown_keys(conn) do
      [] -> parse_value(conn.params)
      keys -> {:error, {:dry_run_param, Map.new(keys, &{&1, [@unknown]})}}
    end
  end

  defp unknown_keys(conn) do
    [conn.query_params, conn.body_params]
    |> Enum.flat_map(fn
      params when is_map(params) -> Map.keys(params)
      _unfetched -> []
    end)
    |> Enum.reject(&(&1 == "dry_run"))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_value(params) do
    case Map.fetch(params, "dry_run") do
      :error -> {:ok, false}
      {:ok, value} when value in ["false", false] -> {:ok, false}
      {:ok, value} when value in ["true", true] -> {:ok, true}
      {:ok, _other} -> {:error, {:dry_run_param, %{dry_run: ["is invalid"]}}}
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

  @doc """
  The 409 a dry run answers when a concurrent transaction changed a row the
  delete reached while it ran (`Portfolixir.DryRun`, REPEATABLE READ):
  nothing was deleted, and a retry decides.
  """
  @spec concurrent_change(Plug.Conn.t()) :: Plug.Conn.t()
  def concurrent_change(conn) do
    conn
    |> put_status(:conflict)
    |> json(%{
      errors: %{
        code: "concurrent_change",
        detail:
          "a concurrent change intervened while the dry run read what the delete would " <>
            "remove, and nothing was deleted: retry the dry run"
      }
    })
  end

  @doc "The 422 a `dry_run` that is not a boolean, or another parameter, answers."
  @spec invalid(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def invalid(conn, errors) when is_map(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end
end
