defmodule PortfolixirWeb.Api.V1.MergeController do
  @moduledoc """
  The lifecycle merges over the API (ADR-0050 §7, §8, §10, §12; #328).

  `GET /api/v1/cash_accounts/:id/merge_preview?target_id=` is a read: the
  preview of merging the account into `target_id`, every figure for both
  values of `collapse_key_equal`, and the `plan_digest` the apply takes.

  `POST /api/v1/cash_accounts/:id/merge` with `{"target_id", "plan_digest",
  "collapse_key_equal"}` merges under the token: **201** with the merge
  record; **200** with the original record for a retry of a completed merge
  of the same pair (`already_applied: true`, nothing journaled). A refusal
  writes nothing and names its code in `errors.code`:

    * **409** — a guard (`same_account`, `not_live`, `portfolio_mismatch`,
      `currency_mismatch`, `liquidity_role_mismatch`, `buckets_mismatch`,
      `legacy_hashed_anchor`, with `errors.guards`), `plan_changed` (with the
      fresh preview in `errors.preview`), `already_merged` (with
      `errors.merged_into`), `identity_check_failed`, `write_refused`;
    * **422** — `plan_digest` missing, `collapse_key_equal` missing where the
      preview lists key-equal pairs or not a boolean, `target_id` missing or
      malformed;
    * **404** — an unknown source.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Lifecycle
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.MergeJSON

  def cash_account_preview(conn, %{"id" => id} = params) do
    with {:ok, source_id} <- IdParam.parse(id),
         {:ok, target_id} <- target_param(params) do
      case Lifecycle.preview_cash_merge(source_id, target_id) do
        {:ok, preview} -> json(conn, %{data: MergeJSON.cash_preview(preview)})
        {:error, refusal} -> refuse(conn, refusal, source_id)
      end
    else
      :error -> not_found(conn)
      {:invalid, field, message} -> unprocessable(conn, %{field => [message]})
    end
  end

  def cash_account_merge(conn, %{"id" => id} = params) do
    with {:ok, source_id} <- IdParam.parse(id),
         {:ok, target_id} <- target_param(params) do
      choices = %{
        plan_digest: Map.get(params, "plan_digest"),
        collapse_key_equal: Map.get(params, "collapse_key_equal")
      }

      case Lifecycle.merge_cash_account(conn.assigns.actor, source_id, target_id, choices) do
        {:ok, record, :applied} ->
          conn
          |> put_status(:created)
          |> json(%{data: MergeJSON.record(record), already_applied: false})

        {:ok, record, :already_applied} ->
          json(conn, %{data: MergeJSON.record(record), already_applied: true})

        {:error, refusal} ->
          refuse(conn, refusal, source_id)
      end
    else
      :error -> not_found(conn)
      {:invalid, field, message} -> unprocessable(conn, %{field => [message]})
    end
  end

  defp target_param(params) do
    case Map.get(params, "target_id") do
      value when value in [nil, ""] ->
        {:invalid, "target_id", "can't be blank"}

      value ->
        case IdParam.parse(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:invalid, "target_id", "is invalid"}
        end
    end
  end

  # --- refusals ------------------------------------------------------------------

  defp refuse(conn, :not_found, _source_id), do: not_found(conn)

  defp refuse(conn, {:refused, guards}, _source_id) do
    %{code: code, detail: detail} = Enum.find(guards, &(not &1.passed))

    conflict(conn, code, detail, %{guards: Enum.map(guards, &MergeJSON.guard/1)})
  end

  defp refuse(conn, {:plan_changed, preview}, _source_id) do
    conflict(
      conn,
      :plan_changed,
      "a booking, a figure or a guard of either account changed since the preview: nothing " <>
        "was written. errors.preview is the fresh preview; merge under its plan_digest once " <>
        "it is approved",
      %{preview: MergeJSON.cash_preview(preview)}
    )
  end

  defp refuse(conn, {:already_merged, record}, source_id) do
    survivor = Lifecycle.merged_into(:cash_account, source_id) || record.target_id

    conflict(
      conn,
      :already_merged,
      "cash account ##{source_id} was merged into cash account ##{record.target_id} " <>
        "(merge record ##{record.id}) and no longer exists; its bookings live on cash account " <>
        "##{survivor}",
      %{merged_into: %{kind: "cash_account", id: survivor}, merge_record_id: record.id}
    )
  end

  defp refuse(conn, {:choice_required, :collapse_key_equal, pairs}, _source_id) do
    unprocessable(conn, %{
      collapse_key_equal: [
        "is required: the preview lists #{pairs} key-equal pairs — true deletes each paired " <>
          "booking of the source (its content hash retired), false keeps both on the target"
      ]
    })
  end

  defp refuse(conn, {:invalid, field, message}, _source_id),
    do: unprocessable(conn, %{field => [message]})

  defp refuse(conn, {:identity_check_failed, facts}, _source_id) do
    conflict(
      conn,
      :identity_check_failed,
      "the merged balance would not equal the sum of both accounts' balances " <>
        "(#{describe(facts)}): the merge was rolled back and nothing was written",
      %{identity: jsonable(facts)}
    )
  end

  defp refuse(conn, {:write_refused, resource, id, changeset}, _source_id) do
    conflict(
      conn,
      :write_refused,
      "the database refused the merge's write of #{resource} ##{id}: the merge was rolled " <>
        "back and nothing was written",
      %{write_errors: JSON.errors(changeset)}
    )
  end

  defp describe(%{date: date, expected: expected, actual: actual}),
    do: "on #{date}: #{JSON.decimal(expected)} expected, #{JSON.decimal(actual)} found"

  defp describe(%{transaction_id: id, reason: reason}), do: "transaction ##{id}: #{reason}"

  defp jsonable(facts) do
    Map.new(facts, fn
      {key, %Decimal{} = value} -> {key, JSON.decimal(value)}
      {key, %Date{} = value} -> {key, JSON.date(value)}
      {key, value} -> {key, value}
    end)
  end

  defp conflict(conn, code, detail, extra) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: Map.merge(%{code: Atom.to_string(code), detail: detail}, extra)})
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
