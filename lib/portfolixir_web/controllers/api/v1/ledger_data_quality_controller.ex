defmodule PortfolixirWeb.Api.V1.LedgerDataQualityController do
  @moduledoc """
  The ledger's read-only data-quality checks over the JSON API, the
  siblings of `GET /api/v1/holdings/negative`: stored rows the guards refuse
  on a new write but an instance can still hold. Each read is
  self-describing (`as_of`, `note`, `remedy`) and writes nothing.

    * `GET /api/v1/splits/incomplete` — split events missing a portfolio
      that held the security entering the effective date (#1292);
    * `GET /api/v1/transactions/rate_only` — cross-currency trades with a
      settlement rate and neither amount (#1290; H35, T-19);
    * `GET /api/v1/transactions/cash_mismatch` — buys and sells whose stored
      cash misses quantity × price ± fees and taxes by more than a cent
      (#1371; ADR-0053, amendment of 2026-11-02, point 4).

  Financial decimals serialize as strings.
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.StatedCash
  alias PortfolixirWeb.Api.V1.JSON

  def incomplete_splits(conn, _params) do
    json(conn, %{data: JSON.incomplete_splits(Splits.incomplete_events_report())})
  end

  def rate_only_trades(conn, _params) do
    json(conn, %{data: JSON.rate_only_trades(SettlementGuard.rate_only_report())})
  end

  def cash_mismatch_trades(conn, _params) do
    json(conn, %{data: JSON.cash_mismatch_trades(StatedCash.report())})
  end
end
