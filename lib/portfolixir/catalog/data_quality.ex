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
  | `missing_logo` | no stored logo and not deliberately locked to "no logo", or a stored logo whose file is gone, whatever its lock (#933) |
  | `missing_fx` | priced, but no stored rate from its currency to the base (EUR hub) |
  | `two_scales` | a bond priced on two scales, in either direction: its latest stored quote is #{20} to #{500} times a booked price per unit, or 1/#{500} to 1/#{20} of one (`Portfolixir.Portfolios.Bonds`) |
  | `implausible_quote` | held, and a booking's quote — on its date, or the latest within #{7} days before — is below half or above twice its price per unit, unless `two_scales` names it (`Portfolixir.Portfolios.QuotePlausibility`) |

  `missing_quote` is a subset of `stale_quote`, and that is deliberate rather
  than an oversight: the dashboard's finding has always read "without a quote
  in 7 days" and has always counted the never-priced rows in it, because a
  security nobody has ever priced is not in better shape than one priced a
  month ago. The narrower set exists so the two can be told apart when working
  them.

  The first three are catalog hygiene, and two kinds of security are left out
  of all three. A benchmark is a reference, not a holding (ADR-0046 §1). A
  retired security's stopped feed and missing logo are expected (PR #1102,
  which replaced the rule that kept a never-priced retired security under
  `missing_quote`). Retiring is how the operator takes a sold-out or delisted
  security out of these checks; it is the remedy the Wealth stale-quote
  finding names for a holding whose listing ended, and the one the securities
  delete names when research notes or policy-rule versions reference a
  security, which a merge cannot carry. So it must clear the Overview's
  findings and the lists they link to. `missing_fx` keeps both, because a
  missing rate path breaks a valuation whatever the security.

  `two_scales` (#1068, Sprint 19 plan D-15) is not catalog hygiene either:
  it is every security the bond two-scales guard flags, catalog-wide, which
  is `Portfolixir.Portfolios.Bonds.two_scales_among/1` over the rows — a
  bond class, or no stored class and a maturity date or coupon, with a
  stored quote and a booked price per unit (a buy or a priced inbound
  delivery) on the other scale. A retired or benchmark bond on two scales
  has figures as wrong as before, so it stays in the set, and the Overview
  counts it through `count/2`, as it counts the others.

  `implausible_quote` (#1101, Sprint 20 plan D-7) is its general case, and
  not catalog hygiene either: every **held** security whose stored quotes
  contradict its own bookings — for a buy, a sell or a priced inbound
  delivery, the quote of the booking's date (or the latest within 7 days
  before it) below half or above twice the booking's price per unit, in
  the security's currency and on one split basis — which is
  `Portfolixir.Portfolios.QuotePlausibility.findings_among/1` over the held
  rows. A security `two_scales` names is not counted again. Held is
  `Portfolixir.Ledger.HeldSecurities`' answer, in the query and in memory
  alike; a retired or benchmark security that is held stays in the set, as
  its value is as wrong as before.

  ## Two halves, and why a caller must apply both

  A predicate narrows in the query where it can (`missing_logo` is a JSONB
  condition on the row; the benchmark and retired exclusions are columns, so
  they run there for all three, before any LIMIT/OFFSET) and in memory where
  it cannot (stale/missing quote are derived from the enriched metrics).
  `list_opts/1` is the first half and `refine/3` is the second; `list/2`
  applies both and is what a caller should reach for unless it is already
  holding rows. It also pages after the second half: a caller's `:limit` and
  `:offset` cut the matching rows, not the catalog the rule then filters
  (#1113), except for `missing_logo`, which is all query.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.Portfolios.Bonds
  alias Portfolixir.Portfolios.QuotePlausibility

  @stale_days 7
  @ids ~w(stale_quote missing_quote missing_logo missing_fx two_scales implausible_quote)

  @doc "Every predicate id."
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc "How old a quote may be before `stale_quote` matches. Stated once."
  @spec stale_days() :: pos_integer()
  def stale_days, do: @stale_days

  @doc """
  Whether a price from `date` is stale as of `today`: older than
  `stale_days/0`. This is the threshold `stale_quote` applies to one date, so
  a marker under a price (issue 789), the filter chip and the Wealth finding
  can never disagree. `nil` — never priced — is not stale: there is no price
  to mark (the never-priced case is `missing_quote`'s).

  `today` is required rather than defaulted: "is this price old by now?" is a
  local-calendar question, so the caller passes `Portfolixir.Clock.today/0`
  (see that module on why `Date.utc_today/0` is the wrong day east of UTC).
  A default here would answer it in UTC and read the host clock from inside
  the domain, which is also what makes a caller untestable against a frozen
  date.
  """
  @spec stale_quote?(Date.t() | nil, Date.t()) :: boolean()
  def stale_quote?(nil, _today), do: false

  def stale_quote?(%Date{} = date, %Date{} = today),
    do: Date.diff(today, date) > @stale_days

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
  query: the logo condition, and for the three catalog-hygiene checks the
  benchmark and retired exclusions. The quote conditions themselves are
  metric-derived, cannot be expressed in SQL over the quote history, and are
  `refine/3`'s; so is the two-scales guard, which reads quotes and bookings.
  `implausible_quote` pushes its held filter here and its guard to
  `refine/3`.
  """
  @spec list_opts(String.t()) :: keyword()
  # ADR-0046 §1: a benchmark security is a reference, not a holding, so the
  # catalog-hygiene checks leave it alone; a retired security likewise (PR
  # #1102). The FX check keeps both — a missing rate path breaks the very
  # comparison the benchmark exists for, and a valuation whatever the
  # security. The two-scales check keeps both too (#1068): a bond's figures
  # on two scales are wrong whatever its flags.
  def list_opts("missing_logo"),
    do: [logo_status: :missing, is_benchmark: false, is_retired: false]

  def list_opts("missing_fx"), do: []
  def list_opts("two_scales"), do: []
  # #1101 (D-7): the held securities, whatever their flags, as two_scales
  # keeps its rows.
  def list_opts("implausible_quote"), do: [holding_status: :held]
  def list_opts(id) when id in @ids, do: [is_benchmark: false, is_retired: false]

  @doc """
  The rows matching `id`, applying both halves of the predicate.

  `opts` are the caller's own `Catalog.list_securities_with_metrics/1` options
  and narrow the set further. A caller's narrowing that contradicts the
  predicate's own (`is_retired: true` beside a catalog-hygiene set, which
  leaves retired securities out) matches nothing, as two narrowings do: the
  predicate is never widened, and the caller's narrowing never dropped
  (#1103).
  """
  @spec list(String.t(), keyword()) :: [SecurityWithMetrics.t()]
  def list(id, opts \\ []) when is_binary(id) do
    if contradicts?(opts, id) do
      []
    else
      {page, opts} = page_opts(id, opts)

      opts
      |> Keyword.merge(list_opts(id))
      |> Catalog.list_securities_with_metrics()
      |> refine(id)
      |> apply_page(page)
    end
  end

  # #1113: a predicate with an in-memory half pages AFTER that half, or a
  # page is cut from the whole catalog before the rule runs and comes back
  # short or empty while later pages hold matches. `missing_logo` is all
  # query, so its LIMIT/OFFSET stay in the query (PR #1102).
  defp page_opts("missing_logo", opts), do: {[], opts}

  defp page_opts(_id, opts), do: Keyword.split(opts, [:limit, :offset])

  defp apply_page(rows, page) do
    rows = Enum.drop(rows, page[:offset] || 0)

    case page[:limit] do
      nil -> rows
      limit -> Enum.take(rows, limit)
    end
  end

  # A caller's value for a key the predicate also narrows, set and different
  # from the predicate's (compared as strings: the API passes the logo
  # status as a string, the predicate as an atom).
  defp contradicts?(opts, id) do
    Enum.any?(list_opts(id), fn {key, value} ->
      case Keyword.get(opts, key) do
        nil -> false
        given -> to_string(given) != to_string(value)
      end
    end)
  end

  @doc """
  How many rows match `id`.

  Defined as the length of `list/2` rather than as a count over rows a caller
  happens to hold. That is the whole point of this module: "a count of N links
  to a list of N" is then true by construction, and cannot drift the way it
  could while the dashboard counted with one copy of the rule and the list
  filtered with another. `two_scales` counts the same rows under the same
  rule without loading their quote metrics, which its rule does not read.
  """
  @spec count(String.t(), keyword()) :: non_neg_integer()
  def count(id, opts \\ [])

  # #1068: the two-scales guard reads no quote metric, so its count skips
  # the metrics pass the list's rows carry. The rows (`list_securities/1`
  # under the same options, which `list_securities_with_metrics/1` wraps)
  # and the rule (`Bonds.two_scales_among/1`) are the list's own, so the
  # count is still the list's length — the Overview pays for no metrics.
  def count("two_scales", opts) do
    opts
    |> Keyword.merge(list_opts("two_scales"))
    |> Catalog.list_securities()
    |> Bonds.two_scales_among()
    |> length()
  end

  # #1101: the same for implausible_quote, whose guard reads bookings and
  # quotes, not the metrics.
  def count("implausible_quote", opts) do
    opts
    |> Keyword.merge(list_opts("implausible_quote"))
    |> Catalog.list_securities()
    |> QuotePlausibility.findings_among()
    |> length()
  end

  def count(id, opts) when is_binary(id), do: length(list(id, opts))

  @doc """
  Narrows rows **that were already loaded with `list_opts/1`** to those
  matching the in-memory half of `id`: the quote conditions, the FX check
  and the two-scales guard. The quote conditions also leave a retired row
  out, so rows loaded without the query half cannot bring one back. `nil` is
  the no-op, so a surface can pass its optional filter straight through.

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

  # #1068 (D-15): the guard's own rule over the rows' securities, so the
  # set is exactly what Wealth names, catalog-wide. A row without a security
  # is no finding.
  def refine(rows, "two_scales", _today) do
    flagged =
      rows
      |> Enum.flat_map(&security_list/1)
      |> Bonds.two_scales_among()
      |> MapSet.new(& &1.security_id)

    Enum.filter(rows, fn row ->
      Enum.any?(security_list(row), &MapSet.member?(flagged, &1.id))
    end)
  end

  # #1101 (D-7): the guard over the rows' held securities. The held filter
  # is applied here too, so rows loaded without the query half cannot bring
  # a sold-out security back; a row without a security is no finding.
  def refine(rows, "implausible_quote", _today) do
    held = MapSet.new(HeldSecurities.held_ids())

    named =
      rows
      |> Enum.flat_map(&security_list/1)
      |> Enum.filter(&MapSet.member?(held, &1.id))
      |> QuotePlausibility.findings_among()
      |> MapSet.new(& &1.security_id)

    Enum.filter(rows, fn row ->
      Enum.any?(security_list(row), &MapSet.member?(named, &1.id))
    end)
  end

  def refine(rows, id, today) when id in @ids do
    today = today || Clock.today()
    Enum.filter(rows, &(not retired?(&1) and matches?(&1, id, today)))
  end

  defp matches?(row, "stale_quote", today) do
    case latest_price_date(row) do
      %Date{} = date -> stale_quote?(date, today)
      _never_priced -> true
    end
  end

  defp matches?(row, "missing_quote", _today), do: is_nil(latest_price_date(row))

  # A retired security's stopped feed is expected (PR #1102). The query half
  # already leaves it out; this keeps it out of the metric-derived sets on
  # rows a caller loaded without `list_opts/1`.
  defp retired?(%{security: %{is_retired: true}}), do: true
  defp retired?(_row), do: false

  defp latest_price_date(%{metrics: %{latest_price_date: date}}), do: date
  defp latest_price_date(_row), do: nil

  defp security_list(%{security: %Security{} = security}), do: [security]
  defp security_list(_row), do: []

  defp currency_of(%{security: %{currency_code: currency}}), do: currency
  defp currency_of(%{currency_code: currency}), do: currency
  defp currency_of(_row), do: nil
end
