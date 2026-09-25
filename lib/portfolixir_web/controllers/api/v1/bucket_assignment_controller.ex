defmodule PortfolixirWeb.Api.V1.BucketAssignmentController do
  @moduledoc """
  JSON API for bucket assignments (ADR-0018): the depot default set, the
  cash-account set, and the per-position override (with an explicit-empty state
  distinct from inheriting the depot default).

  Every write is actor-first and routed through `Portfolixir.Buckets`, which
  journals each assignment as one aggregate entry (ADR-0017). The controller
  never touches the Repo.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias PortfolixirWeb.Api.V1.IdParam

  @doc "Replaces a depot's default bucket set (`PUT /securities_accounts/:id/buckets`)."
  def set_depot_buckets(conn, %{"id" => id} = params) do
    with {:ok, sid} <- IdParam.parse(id),
         %SecuritiesAccount{} = depot <- Portfolios.get_securities_account(sid),
         {:ok, bucket_ids} <- bucket_ids(params),
         :ok <- Buckets.set_depot_default_buckets(conn.assigns.actor, depot, bucket_ids) do
      json(conn, %{
        data: %{
          securities_account_id: depot.id,
          bucket_ids: Buckets.depot_default_bucket_ids(depot.id)
        }
      })
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      # The account was deleted before the write took its lock (E25 S6, G10).
      {:error, :not_found} -> not_found(conn)
      {:error, :bucket_ids} -> unprocessable(conn, %{bucket_ids: ["is invalid"]})
      {:error, :exclusive_bucket_conflict} -> exclusive_conflict(conn)
      {:error, _reason} -> unprocessable(conn, %{detail: ["could not assign buckets"]})
    end
  end

  @doc "Replaces a cash account's bucket set (`PUT /cash_accounts/:id/buckets`)."
  def set_cash_account_buckets(conn, %{"id" => id} = params) do
    with {:ok, cid} <- IdParam.parse(id),
         %CashAccount{} = cash <- Portfolios.get_cash_account(cid),
         {:ok, bucket_ids} <- bucket_ids(params),
         :ok <- Buckets.set_cash_account_buckets(conn.assigns.actor, cash, bucket_ids) do
      json(conn, %{
        data: %{cash_account_id: cash.id, bucket_ids: Buckets.cash_account_bucket_ids(cash.id)}
      })
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      # The account was deleted before the write took its lock (E25 S6, G10).
      {:error, :not_found} -> not_found(conn)
      {:error, :bucket_ids} -> unprocessable(conn, %{bucket_ids: ["is invalid"]})
      {:error, :exclusive_bucket_conflict} -> exclusive_conflict(conn)
      {:error, _reason} -> unprocessable(conn, %{detail: ["could not assign buckets"]})
    end
  end

  @doc """
  Sets the per-position override
  (`PUT /securities_accounts/:id/positions/:security_id/buckets`). An empty
  `bucket_ids` records the explicit-empty state (deliberately no buckets),
  distinct from inheriting the depot default.
  """
  def set_position_override(conn, %{"id" => id, "security_id" => security_id} = params) do
    with {:ok, sid} <- IdParam.parse(id),
         {:ok, sec_id} <- IdParam.parse(security_id),
         %SecuritiesAccount{} = depot <- Portfolios.get_securities_account(sid),
         %Security{} = security <- Catalog.get_security(sec_id),
         {:ok, bucket_ids} <- bucket_ids(params),
         :ok <-
           Buckets.set_position_override(conn.assigns.actor, depot, security, bucket_ids) do
      json(conn, %{data: position_state(depot.id, security.id)})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      # The account was deleted before the write took its lock (E25 S6, G10).
      {:error, :not_found} -> not_found(conn)
      {:error, :bucket_ids} -> unprocessable(conn, %{bucket_ids: ["is invalid"]})
      # The exclusive dimension holds for overrides too (fix round): at most
      # one scope bucket per position, same 422 as the account endpoints.
      {:error, :exclusive_bucket_conflict} -> exclusive_conflict(conn)
      {:error, _reason} -> unprocessable(conn, %{detail: ["could not set override"]})
    end
  end

  @doc """
  Clears the per-position override, returning the position to inherit the depot
  default (`DELETE /securities_accounts/:id/positions/:security_id/buckets`).
  """
  def clear_position_override(conn, %{"id" => id, "security_id" => security_id}) do
    with {:ok, sid} <- IdParam.parse(id),
         {:ok, sec_id} <- IdParam.parse(security_id),
         %SecuritiesAccount{} = depot <- Portfolios.get_securities_account(sid),
         %Security{} = security <- Catalog.get_security(sec_id),
         :ok <- Buckets.clear_position_override(conn.assigns.actor, depot, security) do
      json(conn, %{data: position_state(depot.id, security.id)})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      # The account was deleted before the write took its lock (E25 S6, G10).
      {:error, :not_found} -> not_found(conn)
      {:error, _reason} -> unprocessable(conn, %{detail: ["could not clear override"]})
    end
  end

  # Reports the resolved per-position state: the override classification plus the
  # effective bucket ids (override wins over the depot default).
  defp position_state(sa_id, sec_id) do
    %{
      securities_account_id: sa_id,
      security_id: sec_id,
      override: override_label(Buckets.position_override(sa_id, sec_id)),
      effective_bucket_ids: Buckets.effective_position_buckets(sa_id, sec_id)
    }
  end

  defp override_label(:inherit), do: "inherit"
  defp override_label(:explicit_empty), do: "explicit_empty"
  defp override_label({:explicit, _ids}), do: "explicit"

  # Parses the `bucket_ids` list from the body. Absent -> []. Any non-positive or
  # non-integer entry returns `{:error, :bucket_ids}` for a 422.
  defp bucket_ids(params) do
    case Map.get(params, "bucket_ids") do
      nil -> {:ok, []}
      list when is_list(list) -> list |> IdParam.parse_list() |> bucket_ids_result()
      _ -> {:error, :bucket_ids}
    end
  end

  defp bucket_ids_result({:ok, ids}), do: {:ok, ids}
  defp bucket_ids_result(:error), do: {:error, :bucket_ids}

  # ADR-0024: an account carries at most one bucket of the exclusive "scope"
  # dimension; a violating set is rejected before anything is written.
  defp exclusive_conflict(conn) do
    unprocessable(conn, %{
      bucket_ids: ["carries more than one scope-dimension bucket (at most one per account)"]
    })
  end

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
