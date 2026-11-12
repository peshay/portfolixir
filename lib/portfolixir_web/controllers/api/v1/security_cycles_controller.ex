defmodule PortfolixirWeb.Api.V1.SecurityCyclesController do
  @moduledoc """
  The halving cycles read (FR-58,
  [ADR-0060](../../../../../docs/decisions/0060-halving-cycles-tops-and-lows-by-drawdown-projected-as-a-band.md)
  §11): `GET /api/v1/securities/:security_id/cycles`, mirrored by
  `portfolixir.securities.cycles`.

  The halvings, the windows with their tops and lows, the six intervals with
  n, minimum and maximum, the projection (`kind: analog_band`,
  `not_a_forecast: true`, the next low's and the next top's band with their
  parts, `agree` and states), `chain_source` and `computation_basis`, as
  `Portfolixir.Catalog.SecurityCycles.for_security/2` computes them at every
  read. `include=aligned` adds each window's closes indexed to its halving
  day's close. Decimals are strings, dates ISO 8601.

  **No `as_of`**: an unknown parameter, `as_of` included, is refused with
  422 naming it (ADR-0060 §8, a past cycle's band is level (d)). A
  merged-away id answers 404 with `errors.merged_into` (ADR-0050 §12).

  The payload carries no signal, rating or action: the band is not a
  forecast, and `test/invariants/metrics_carry_no_verdict_test.exs` walks
  this rendering's keys.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog.SecurityCycles
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.MergedAway

  def show(conn, %{"security_id" => security_id}) do
    case SecurityCycles.for_security(security_id, conn.query_params) do
      {:ok, payload} ->
        json(conn, %{data: JSON.security_cycles(payload)})

      {:error, :not_found} ->
        MergedAway.not_found(conn, :security, security_id)

      {:error, {:invalid_params, errors}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
    end
  end
end
