defmodule PortfolixirWeb.Api.V1.MoversJSON do
  @moduledoc """
  The tops and flops' API payload (FR-59, ADR-0061 §4, §5, §9; Sprint 30,
  T2), rendered from `Portfolixir.Portfolios.Performance.Movers.read/3`'s
  answer as it is: every `Decimal` a string
  (`PortfolixirWeb.Api.V1.JSON.decimal/1`), every date ISO 8601, every atom
  value its name (an unanswered reason, an unvalued reason), never a JSON
  number for a figure. The read's keys pass through unchanged, so the
  payload carries `view_id`, `window`, `start_on`, `end_on`, `limit`, and
  the two rankings `price_return` and `contribution`, each with `highest`,
  `lowest`, `answered`, `unanswered` (a count per reason), its
  `computation_basis` and, with `include_unanswered`, `unanswered_entries`.

  No key here is a verdict: the rankings order figures and say nothing
  about what to buy or sell (ADR-0061 §7;
  `test/invariants/metrics_carry_no_verdict_test.exs` walks this payload).
  """

  alias PortfolixirWeb.Api.V1.JSON

  @doc "`GET /api/v1/views/:view_id/movers` and `GET /api/v1/movers`."
  @spec movers(map()) :: map()
  def movers(result) when is_map(result), do: plain(result)

  # Decimals as strings, dates and times ISO 8601, atoms by name; maps and
  # lists walked.
  defp plain(%Decimal{} = decimal), do: JSON.decimal(decimal)
  defp plain(%Date{} = date), do: JSON.date(date)
  defp plain(%DateTime{} = datetime), do: JSON.datetime(datetime)
  defp plain(%NaiveDateTime{} = timestamp), do: JSON.timestamp(timestamp)
  defp plain(value) when is_boolean(value) or is_nil(value), do: value
  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)

  defp plain(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, plain(value)} end)

  defp plain(value), do: value
end
