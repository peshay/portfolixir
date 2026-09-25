defmodule PortfolixirWeb.Api.V1.PolicyFindingController do
  @moduledoc """
  The findings read (ADR-0049 §5, FR-43): the operator's policy rules in force
  today for one evaluation context, evaluated at read over the figures the
  product already serves.

  One finding per rule in force, sorted breached, undetermined, ok.
  `status=breached` is the **retrievable alarm list** — the pull half of B3.7;
  nothing is pushed anywhere. `view=` selects the evaluation context (absent:
  the portfolio-wide one). An `undetermined` finding is never filtered out by
  default and never counted as ok.

  The payload states its computation basis (the AGENTS.md metric rule applies
  to findings as it applies to metrics), and carries no action (§6,
  `findings_carry_no_action_test.exs`). `since=` deliberately does not apply:
  findings are a derived projection, not rows (#849). Mirrored by
  `portfolixir.portfolios.policy_findings`.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyFindings
  alias Portfolixir.Portfolios.Portfolio
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PolicyJSON
  alias PortfolixirWeb.Api.V1.ViewParam

  @findings_note "A finding is a stored rule applied to a figure the product already " <>
                   "serves, evaluated today: breached (strictly beyond the line), ok, or " <>
                   "undetermined (the figure could not be read — never a pass). It names the " <>
                   "rule, the measured value and the signed distance to the line, and carries " <>
                   "no action: nothing here proposes, sizes or places a trade."

  @computation_basis %{
    input_series:
      "each finding reads ONE figure an existing read already serves, named in the finding's " <>
        "own computation_basis.source: the risk lens (single-name weight, HHI), the " <>
        "allocation breakdown (category and cash weight, drift of the active plan), the " <>
        "valuation (a view's share of the context's basis), or ADR-0047's portfolio metrics " <>
        "(volatility, max_drawdown); the rules compute no figure of their own",
    window:
      "evaluated today (as_of) against the rule versions in force today; volatility and " <>
        "max_drawdown read the ADR-0047 window the rule names (30d, 90d or 365d); no rule is " <>
        "evaluated over a date before its version's valid_from",
    reference:
      "the rule's own threshold (cap, floor) or [lower, upper] (band), on the measure's " <>
        "scale: weight percent 0-100, drift percentage points, HHI 0-10000, volatility and " <>
        "max_drawdown percent (the metric's ratio × 100); a cap is breached strictly above, a " <>
        "floor strictly below, a band strictly outside",
    gaps:
      "a figure that cannot be read makes the finding undetermined with its reason, never ok: " <>
        "insufficient_data (a refused metric, with its required and observations), undefined, " <>
        "no_active_plan and no_target (a drift with nothing to drift from), empty_basis (a " <>
        "weight of nothing), unvalued (the subject is held but its position cannot be valued, " <>
        "e.g. no exchange rate), subject_not_found, not_measured. A security that is not held " <>
        "has a weight of 0, which is a reading"
  }

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- IdParam.parse(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, status} <- status_param(params) do
      opts = [status: status] ++ ViewParam.opts(view)

      case PolicyFindings.for_portfolio(pid, opts) do
        {:error, :view_not_found} ->
          not_found(conn)

        result ->
          data =
            %{
              portfolio_id: pid,
              as_of: JSON.date(result.as_of),
              status: status && Enum.map(status, &Atom.to_string/1),
              summary: result.summary,
              findings: Enum.map(result.findings, &PolicyJSON.finding/1),
              computation_basis: @computation_basis,
              findings_note: @findings_note
            }
            |> ViewParam.put_active(view)

          json(conn, %{data: data})
      end
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
      :view_not_found -> not_found(conn)
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  # A comma-separated set of the three states; an unknown one is a 422, never
  # a silently empty list.
  defp status_param(params) do
    case Map.get(params, "status") do
      value when value in [nil, ""] ->
        {:ok, nil}

      value when is_binary(value) ->
        allowed = Enum.map(PolicyFindings.states(), &Atom.to_string/1)
        requested = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

        if requested != [] and Enum.all?(requested, &(&1 in allowed)),
          do: {:ok, requested |> Enum.uniq() |> Enum.map(&String.to_existing_atom/1)},
          else: {:error, :status}

      _other ->
        {:error, :status}
    end
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
