defmodule Portfolixir.Catalog.SecurityWithMetrics do
  @moduledoc """
  A `%Security{}` decorated with derived price metrics. Used by the
  securities list when one of the `:kurse` columns is visible.

  The metrics map is always present; individual values are nil when the
  underlying quote history is insufficient (no latest quote → all nil; only
  one quote → day-change nil; quote younger than 30/365 days → 1M/1Y nil).
  """

  defstruct security: nil, metrics: %{}

  @type metrics :: %{
          latest_price: Decimal.t() | nil,
          latest_price_date: Date.t() | nil,
          day_change_abs: Decimal.t() | nil,
          day_change_pct: Decimal.t() | nil,
          performance_1m: Decimal.t() | nil,
          performance_1y: Decimal.t() | nil
        }

  @type t :: %__MODULE__{
          security: Portfolixir.Catalog.Security.t(),
          metrics: metrics()
        }

  def empty_metrics do
    %{
      latest_price: nil,
      latest_price_date: nil,
      day_change_abs: nil,
      day_change_pct: nil,
      performance_1m: nil,
      performance_1y: nil
    }
  end
end
