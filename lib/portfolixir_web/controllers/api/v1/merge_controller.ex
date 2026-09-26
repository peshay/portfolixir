defmodule PortfolixirWeb.Api.V1.MergeController do
  @moduledoc """
  The lifecycle merges over the API (ADR-0050 §7, §8, §9, §10, §12; #328,
  #608): a cash account into another, a depot into another, and a security
  into another.

  `GET /api/v1/cash_accounts/:id/merge_preview?target_id=`, `GET
  /api/v1/securities_accounts/:id/merge_preview?target_id=` and `GET
  /api/v1/securities/:id/merge_preview?target_id=` are reads: the preview of
  merging the account, depot or security into `target_id`, every figure for
  both values of `collapse_key_equal` (for a security also the identifiers
  after each value of `identity_choice`), and the `plan_digest` the apply
  takes.

  `POST /api/v1/cash_accounts/:id/merge`, `POST
  /api/v1/securities_accounts/:id/merge` and `POST
  /api/v1/securities/:id/merge` with `{"target_id", "plan_digest",
  "collapse_key_equal"}` — for a security also `"identity_choice"` and
  `"isin_changed_on"` — merge under the token: **201** with the merge
  record; **200** with the original record for a retry of a completed merge
  of the same pair (`already_applied: true`, nothing journaled). A refusal
  writes nothing and names its code in `errors.code`:

    * **409** — a guard (for a cash account `same_account`, `not_live`,
      `portfolio_mismatch`, `currency_mismatch`, `liquidity_role_mismatch`,
      `buckets_mismatch`, `legacy_hashed_anchor`; for a depot `same_account`,
      `not_live`, `portfolio_mismatch`, `buckets_mismatch`,
      `position_buckets_mismatch`; for a security `same_security`,
      `not_live`, `currency_mismatch`, `benchmark_mismatch`,
      `retired_target`, `quote_basis_mismatch`, `research_notes`,
      `policy_rules` (with `errors.policy_rules`),
      `position_buckets_mismatch`, `split_ratio_mismatch`,
      `split_event_mismatch`, `split_linearity`, `identity_unresolvable`
      (with `errors.unresolvable`) — each with `errors.guards`),
      `plan_changed` (with the fresh preview in `errors.preview`),
      `already_merged` (with `errors.merged_into`), `identity_check_failed`,
      `identity_unresolvable` found after the writes, `write_refused`;
    * **422** — `plan_digest` missing, `collapse_key_equal` missing where the
      preview lists key-equal pairs or not a boolean, `identity_choice`
      missing where both securities carry an ISIN or not one of
      `keep_target_isin` and `adopt_source_isin`, `isin_changed_on` not a
      date, `target_id` missing or malformed;
    * **404** — an unknown source.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Lifecycle
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.MergeJSON

  def cash_account_preview(conn, params), do: preview(conn, :cash_account, params)
  def cash_account_merge(conn, params), do: merge(conn, :cash_account, params)
  def securities_account_preview(conn, params), do: preview(conn, :securities_account, params)
  def securities_account_merge(conn, params), do: merge(conn, :securities_account, params)
  def security_preview(conn, params), do: preview(conn, :security, params)
  def security_merge(conn, params), do: merge(conn, :security, params)

  defp preview(conn, kind, %{"id" => id} = params) do
    with {:ok, source_id} <- IdParam.parse(id),
         {:ok, target_id} <- target_param(params) do
      case preview_of(kind, source_id, target_id) do
        {:ok, preview} -> json(conn, %{data: preview_json(kind, preview)})
        {:error, refusal} -> refuse(conn, kind, refusal, source_id)
      end
    else
      :error -> not_found(conn)
      {:invalid, field, message} -> unprocessable(conn, %{field => [message]})
    end
  end

  defp merge(conn, kind, %{"id" => id} = params) do
    with {:ok, source_id} <- IdParam.parse(id),
         {:ok, target_id} <- target_param(params) do
      choices =
        %{
          plan_digest: Map.get(params, "plan_digest"),
          collapse_key_equal: Map.get(params, "collapse_key_equal")
        }
        |> put_identity(kind, params)

      case apply_merge(kind, conn.assigns.actor, source_id, target_id, choices) do
        {:ok, record, :applied} ->
          conn
          |> put_status(:created)
          |> json(%{data: MergeJSON.record(record), already_applied: false})

        {:ok, record, :already_applied} ->
          json(conn, %{data: MergeJSON.record(record), already_applied: true})

        {:error, refusal} ->
          refuse(conn, kind, refusal, source_id)
      end
    else
      :error -> not_found(conn)
      {:invalid, field, message} -> unprocessable(conn, %{field => [message]})
    end
  end

  defp preview_of(:cash_account, source_id, target_id),
    do: Lifecycle.preview_cash_merge(source_id, target_id)

  defp preview_of(:securities_account, source_id, target_id),
    do: Lifecycle.preview_depot_merge(source_id, target_id)

  defp preview_of(:security, source_id, target_id),
    do: Lifecycle.preview_security_merge(source_id, target_id)

  defp apply_merge(:cash_account, actor, source_id, target_id, choices),
    do: Lifecycle.merge_cash_account(actor, source_id, target_id, choices)

  defp apply_merge(:securities_account, actor, source_id, target_id, choices),
    do: Lifecycle.merge_depot(actor, source_id, target_id, choices)

  defp apply_merge(:security, actor, source_id, target_id, choices),
    do: Lifecycle.merge_security(actor, source_id, target_id, choices)

  # §9: the security merge's identity choice and the date of the ISIN
  # change, as sent; the merge judges them (a name the context does not know
  # is a 422, never a new atom).
  defp put_identity(choices, :security, params) do
    Map.merge(choices, %{
      identity_choice: Map.get(params, "identity_choice"),
      isin_changed_on: Map.get(params, "isin_changed_on")
    })
  end

  defp put_identity(choices, _kind, _params), do: choices

  defp preview_json(:cash_account, preview), do: MergeJSON.cash_preview(preview)
  defp preview_json(:securities_account, preview), do: MergeJSON.depot_preview(preview)
  defp preview_json(:security, preview), do: MergeJSON.security_preview(preview)

  defp noun(:cash_account), do: "cash account"
  defp noun(:securities_account), do: "securities account"
  defp noun(:security), do: "security"

  defp either(:cash_account), do: "either account"
  defp either(:securities_account), do: "either depot"
  defp either(:security), do: "either security"

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

  defp refuse(conn, _kind, :not_found, _source_id), do: not_found(conn)

  defp refuse(conn, _kind, {:refused, guards}, _source_id) do
    %{code: code, detail: detail} = failed = Enum.find(guards, &(not &1.passed))

    conflict(
      conn,
      code,
      detail,
      Map.merge(MergeJSON.guard_facts(failed), %{guards: Enum.map(guards, &MergeJSON.guard/1)})
    )
  end

  defp refuse(conn, kind, {:plan_changed, preview}, _source_id) do
    conflict(
      conn,
      :plan_changed,
      "a booking, a figure or a guard of #{either(kind)} changed since the preview: nothing " <>
        "was written. errors.preview is the fresh preview; merge under its plan_digest once " <>
        "it is approved",
      %{preview: preview_json(kind, preview)}
    )
  end

  defp refuse(conn, kind, {:already_merged, record}, source_id) do
    survivor = Lifecycle.merged_into(kind, source_id) || record.target_id

    conflict(
      conn,
      :already_merged,
      "#{noun(kind)} ##{source_id} was merged into #{noun(kind)} ##{record.target_id} " <>
        "(merge record ##{record.id}) and no longer exists; its bookings live on " <>
        "#{noun(kind)} ##{survivor}",
      %{merged_into: %{kind: Atom.to_string(kind), id: survivor}, merge_record_id: record.id}
    )
  end

  defp refuse(conn, _kind, {:choice_required, :collapse_key_equal, pairs}, _source_id) do
    unprocessable(conn, %{
      collapse_key_equal: [
        "is required: the preview lists #{pairs} key-equal pairs — true deletes each paired " <>
          "booking of the source (its content hash retired), false keeps both on the target"
      ]
    })
  end

  defp refuse(conn, _kind, {:choice_required, :identity_choice, isins}, _source_id) do
    unprocessable(conn, %{
      identity_choice: [
        "is required: both securities carry an ISIN (the source #{isins.source_isin}, the " <>
          "target #{isins.target_isin}) — keep_target_isin keeps #{isins.target_isin} and " <>
          "records #{isins.source_isin} as a former ISIN of the target; adopt_source_isin gives " <>
          "the target #{isins.source_isin} and records #{isins.target_isin} as its former ISIN"
      ]
    })
  end

  defp refuse(conn, _kind, {:invalid, field, message}, _source_id),
    do: unprocessable(conn, %{field => [message]})

  defp refuse(conn, _kind, {:identity_unresolvable, failures}, _source_id) do
    conflict(
      conn,
      :identity_unresolvable,
      "after the writes, an identity of the two securities no longer resolved to the target " <>
        "(#{length(failures)} named in errors.unresolvable): the merge was rolled back and " <>
        "nothing was written",
      %{unresolvable: Enum.map(failures, &MergeJSON.unresolvable/1)}
    )
  end

  defp refuse(conn, kind, {:identity_check_failed, facts}, _source_id) do
    conflict(
      conn,
      :identity_check_failed,
      "#{identity(kind)} (#{describe(facts)}): the merge was rolled back and nothing was written",
      %{identity: jsonable(facts)}
    )
  end

  defp refuse(conn, _kind, {:write_refused, resource, id, changeset}, _source_id) do
    conflict(
      conn,
      :write_refused,
      "the database refused the merge's write of #{resource} ##{id}: the merge was rolled " <>
        "back and nothing was written",
      %{write_errors: JSON.errors(changeset)}
    )
  end

  defp identity(:cash_account),
    do: "the merged balance would not equal the sum of both accounts' balances"

  defp identity(:securities_account),
    do: "the merged quantity would not equal the fold of both depots' bookings as one depot"

  defp identity(:security),
    do: "the merged quantity would not equal the fold of both securities' bookings as one"

  defp describe(%{date: date, security_id: security_id, expected: expected, actual: actual}),
    do:
      "on #{date} for security ##{security_id}: #{JSON.decimal(expected)} expected, " <>
        "#{JSON.decimal(actual)} found"

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
