defmodule Portfolixir.Catalog.DataQuality do
  @moduledoc """
  The data-quality predicates over the securities catalog, defined **once**
  (issue #705).

  Before this they existed three times: the dashboard counted them, the
  securities LiveView filtered by them behind `?dq=`, and the API and MCP could
  not express them at all — so the human surface could ask "which securities
  have no quote in 7 days" and the agent could not. Three copies of a rule with
  the seven-day threshold written out twice is a count that can drift away from
  the list it links to, which is exactly what "a count of N links to a list of
  N" is supposed to guarantee.

  ## The predicates

  | id | means |
  |---|---|
  | `stale_quote` | no quote newer than #{7} days — **including no quote at all** |
  | `missing_quote` | no quote at all |
  | `missing_logo` | no stored logo, and not deliberately locked to "no logo" |
  | `missing_fx` | priced, but no stored rate from its currency to the base (EUR hub) |

  `missing_quote` is a strict subset of `stale_quote`, and that is deliberate
  rather than an oversight: the dashboard's finding has always read "without a
  quote in 7 days" and has always counted the never-priced rows in it, because
  a security nobody has ever priced is not in better shape than one priced a
  month ago. The narrower set exists so the two can be told apart when working
  them.

  ## Two halves, and why a caller must apply both

  A predicate narrows in the query where it can (`missing_logo` is a JSONB
  condition on the row) and in memory where it cannot (stale/missing quote are
  derived from the enriched metrics). `list_opts/1` is the first half and
  `filter/2` is the second; `list/2` applies both and is what a caller should
  reach for unless it is already holding rows.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Fx

  @stale_days 7
  @ids ~w(stale_quote missing_quote missing_logo missing_fx)

  @doc "Every predicate id."
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc "How old a quote may be before `stale_quote` matches. Stated once."
  @spec stale_days() :: pos_integer()
  def stale_days, do: @stale_days

  @doc """
  Whether `id` names a predicate.

  String-keyed on purpose: these ids arrive from query strings and MCP
  arguments, and `String.to_atom/1` on external input is forbidden.
  """
  @spec valid?(term()) :: boolean()
  def valid?(id) when is_binary(id), do: id in @ids
  def valid?(_id), do: false

  @doc """
  The `Catalog.list_securities/1` options this predicate can push into the
  query. Empty for the metric-derived ones, which cannot be expressed in SQL
  over the quote history the way `filter/3` expresses them.
  """
  @spec list_opts(String.t()) :: keyword()
  def list_opts("missing_logo"), do: [logo_status: :missing]
  def list_opts(id) when id in @ids, do: []

  @doc """
  The rows matching `id`, applying both halves of the predicate.

  `opts` are the caller's own `Catalog.list_securities_with_metrics/1` options
  and are merged under the predicate's, so a predicate can never be widened by
  a caller passing a conflicting narrowing.
  """
  @spec list(String.t(), keyword()) :: [SecurityWithMetrics.t()]
  def list(id, opts \\ []) when is_binary(id) do
    opts
    |> Keyword.merge(list_opts(id))
    |> Catalog.list_securities_with_metrics()
    |> refine(id)
  end

  @doc """
  How many rows match `id`.

  Defined as the length of `list/2` rather than as a count over rows a caller
  happens to hold. That is the whole point of this module: "a count of N links
  to a list of N" is then true by construction, and cannot drift the way it
  could while the dashboard counted with one copy of the rule and the list
  filtered with another.
  """
  @spec count(String.t(), keyword()) :: non_neg_integer()
  def count(id, opts \\ []) when is_binary(id), do: length(list(id, opts))

  @doc """
  Narrows rows **that were already loaded with `list_opts/1`** to those
  matching the in-memory half of `id`. `nil` is the no-op, so a surface can
  pass its optional filter straight through.

  This is for a surface that has loaded its rows with its own filters and
  cannot call `list/2`. Anything else should use `list/2` or `count/2`, which
  apply both halves and cannot be got wrong.
  """
  @spec refine([SecurityWithMetrics.t()], String.t() | nil, Date.t() | nil) :: [
          SecurityWithMetrics.t()
        ]
  def refine(rows, id, today \\ nil)
  def refine(rows, nil, _today), do: rows

  # The logo condition is expressed entirely in the query (`list_opts/1`), and
  # is deliberately NOT mirrored here: a second copy in Elixir is the drift
  # this module exists to remove.
  def refine(rows, "missing_logo", _today), do: rows

  # #717: "Missing FX" is about the RATE, not the currency — a priced row
  # whose currency has no stored path to the EUR hub. The rated set is loaded
  # once per call; `Fx.hub_rates/1` answers the hub itself with 1, so EUR
  # rows are never in this set.
  def refine(rows, "missing_fx", _today) do
    rated =
      rows
      |> Enum.map(&currency_of/1)
      |> Enum.uniq()
      |> Fx.hub_rates()

    Enum.filter(rows, fn row ->
      not is_nil(latest_price_date(row)) and not Map.has_key?(rated, currency_of(row))
    end)
  end

  def refine(rows, id, today) when id in @ids do
    today = today || Date.utc_today()
    Enum.filter(rows, &matches?(&1, id, today))
  end

  defp matches?(row, "stale_quote", today) do
    case latest_price_date(row) do
      %Date{} = date -> Date.diff(today, date) > @stale_days
      _never_priced -> true
    end
  end

  defp matches?(row, "missing_quote", _today), do: is_nil(latest_price_date(row))

  defp latest_price_date(%{metrics: %{latest_price_date: date}}), do: date
  defp latest_price_date(_row), do: nil

  defp currency_of(%{security: %{currency_code: currency}}), do: currency
  defp currency_of(%{currency_code: currency}), do: currency
  defp currency_of(_row), do: nil
end
