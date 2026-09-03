defmodule PortfolixirWeb.Api.V1.TargetController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.Api.V1.DriftParam
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
      {:ok, count} = Targets.delete_target(conn.assigns.actor, pid, cid, ViewParam.opts(view))
      json(conn, %{data: %{deleted: count}})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> invalid_view(conn)
      :view_not_found -> not_found(conn)
    end
  end

  # Position-level SOLL (ADR-0030, #481): the position rows (a target per
  # security under a category) plus each affected category's effective roll-up
  # (explicit-or-sum, with the conflict flag). Position targets are written
  # through the same `set` endpoint by adding a `security_id` to a target entry.
  #
  # FR-37 reaching the position level (#740): `min_drift=` (the allocation
  # read's spelling, one parser) keeps only the position rows whose
  # |drift_weight| meets the threshold, where drift is the security's actual
  # weight minus its position SOLL exactly as the allocation computes it —
  # one predicate (`Allocation.drift_at_least?/2`), two surfaces. Kept rows
  # carry `drift_weight`; the response states the applied `min_drift`,
  # `position_targets_total` (the pre-filter count) and the drift basis.
  def index_positions(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, min_drift} <- DriftParam.parse(params) do
      opts = list_opts(params, view)
      rows = Targets.list_position_targets(pid, opts)

      json(conn, %{
        data: %{
          position_targets: position_rows(rows, pid, view, min_drift),
          position_targets_total: length(rows),
          min_drift: JSON.decimal(min_drift),
          drift_basis: drift_basis(min_drift),
          effective_targets:
            Enum.map(Targets.effective_targets(pid, opts), &JSON.effective_target/1)
        }
      })
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> invalid_view(conn)
      {:error, :min_drift} -> unprocessable(conn, %{min_drift: ["is invalid"]})
      :view_not_found -> not_found(conn)
    end
  end

  defp position_rows(rows, _pid, _view, nil), do: Enum.map(rows, &JSON.position_target/1)

  defp position_rows(rows, pid, view, %Decimal{} = min_drift) do
    drifts = position_drifts(rows, pid, view)

    rows
    |> Enum.map(&{&1, Map.get(drifts, {&1.classification_id, &1.security_id})})
    |> Enum.filter(fn {_row, drift} ->
      Allocation.drift_at_least?(%{drift_weight: drift}, min_drift)
    end)
    |> Enum.map(fn {row, drift} -> JSON.position_target(row, drift) end)
  end

  # The allocation's own position rows, per classification the listing spans,
  # keyed by `{classification_id, security_id}` — categories and the
  # unassigned pot alike, so a stale row (filed under a category its security
  # left) still finds its drift where the allocation counts it.
  defp position_drifts(rows, pid, view) do
    rows
    |> Enum.map(& &1.classification_id)
    |> Enum.uniq()
    |> Enum.flat_map(fn cid ->
      case Allocation.for_portfolio(pid, cid, ViewParam.opts(view)) do
        {:ok, breakdown} -> allocation_position_drifts(breakdown, cid)
        _other -> []
      end
    end)
    |> Map.new()
  end

  defp allocation_position_drifts(breakdown, cid) do
    category_positions = Enum.flat_map(breakdown.categories, &(&1.positions || []))
    unassigned_positions = (breakdown.unassigned && breakdown.unassigned.positions) || []

    for position <- category_positions ++ unassigned_positions,
        not is_nil(position.drift_weight) do
      {{cid, position.security_id}, position.drift_weight}
    end
  end

  defp drift_basis(nil), do: nil

  defp drift_basis(%Decimal{}),
    do:
      "drift_weight = actual weight of the security in the steering basis (securities + counting cash, " <>
        "view-scoped) minus its position target, as the allocation read computes it; rows without a " <>
        "drift (no allocation row for the security) are filtered out; the comparison is on |drift_weight|, inclusive"

  def delete_position(
        conn,
        %{
          "portfolio_id" => portfolio_id,
          "category_id" => category_id,
          "security_id" => security_id
        } =
          params
      ) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, cid} <- parse_id(category_id),
         {:ok, sid} <- parse_id(security_id) do
      {:ok, count} =
        Targets.delete_position_target(conn.assigns.actor, pid, cid, sid, ViewParam.opts(view))

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

      case Targets.set_cash_target(conn.assigns.actor, pid, weight, ViewParam.opts(view)) do
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
      case Targets.set_targets(conn.assigns.actor, pid, cid, entries, ViewParam.opts(view)) do
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

  # UAT polish round: name both ids so the operator can act on the 422 without
  # re-deriving which entry of the batch was rejected.
  defp render_error(conn, {:security_category_mismatch, security_id, category_id}),
    do:
      unprocessable(conn, %{
        detail:
          "security #{security_id} is not under category #{category_id} in this " <>
            "classification — assign it there (or a descendant) first, or file the " <>
            "target under its current category"
      })

  defp render_error(conn, :invalid_entry),
    do:
      unprocessable(conn, %{targets: ["must be a list of {category_id, target_weight} objects"]})

  # #481 fix round: a present-but-garbage security_id is rejected instead of
  # being silently coerced into a category write.
  defp render_error(conn, :invalid_security_id),
    do: unprocessable(conn, %{targets: ["security_id must be a positive integer or null"]})

  defp render_error(conn, {:duplicate_position, security_id}),
    do:
      unprocessable(conn, %{
        detail:
          "a plan carries one position row per security: security #{security_id} already has " <>
            "a position target under a different category, or appears more than once in this batch"
      })

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
