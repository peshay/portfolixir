defmodule Portfolixir.Portfolios.Performance.Bands do
  @moduledoc """
  The stacked value chart's bands (I23, FR-53, scope-ladder level (b)): the
  performance walk's value series split into bands that add up to it, day
  by day, exactly in `Decimal`.

  The walk (`Portfolixir.Portfolios.Performance`, ADR-0010) values every held
  security every day and sums the values with the cash. With bands it keeps
  each window day's terms apart, as ADR-0051 §5 keeps each position's figures
  apart, and nothing else it computes moves. The bands group those terms:

    * `:total` — one band, the series itself (today's line);
    * `:category` — one band per root category of a classification tree,
      holding the securities filed under it or under any of its descendants,
      plus `cash` and `unclassified` (the securities the tree files nowhere);
    * `:security` — one band per security plus `cash`.

  **The filter** (FR-56, Sprint 28 S1): a `category_id` narrows every level
  to that category's subtree, without cash and without `unclassified`, so
  the bands add up to the category's band one level up:

    * `:total` — one band, the filtered category's line (its own key,
      `category:<id>`);
    * `:category` — one band per direct sub-category, each over its
      subtree, plus one band of kind `:direct` (key `direct:<id>`, the
      category's id and name) for the securities filed in the category
      itself, absent when it holds none; a category without sub-categories
      is one band, its own;
    * `:security` — one band per security of the subtree.

  `category_id: :unclassified` filters to the securities the tree files
  nowhere: one band per security at the security level, one band
  `unclassified` at the others. The `:direct` band carries the category's
  name, not a label: the screen names it „‹name› (direkt)“ in its own
  language, as it names cash, `unclassified` and `other`.

  **The classification** (Sprint 27 plan D-5): the one requested; else, at
  the category level, the tree of the allocation targets of the scope's
  active plan (the first such tree in tree order when targets sit in
  several); else the default steering tree, `Classifications.default_classification/1`
  (the first custom classification, else the built-in asset class tree).
  A classification is stored as it is today, without a history, so a
  security that moved between categories inside the window is drawn in its
  category of today on every day of it.

  **At most eight bands** (D-5), inside a filter too. `cash` and
  `unclassified` always keep their own band; with more than eight bands,
  the smallest of the others by value on the window's last day (ties by
  name, never by id) merge into `other`, so that eight remain. When the cut
  falls between two bands of equal value and equal name, both merge:
  nothing but an id would tell them apart. `other`
  is always the last band, on top of the stack, whatever the sort and its
  size (the closing act's design critic, D4).

  **Change without flows**, per band: `(end − start − net flows) / start`.
  A security's start value and net flows are ADR-0051's (§1, §5): its value
  at the close of the day before the window, and its buys, sells, deliveries
  and boundary flows inside it. A group's are its members' sums. The cash
  band's net flows are the scope's net external flows less every position's
  net flows, so the bands' money changes (`end − start − net flows`) add up
  exactly to the period's money result; the total band's are the net
  external flows. No change (`nil`) without a positive start value.

  **Share**: a band's value on the window's last day over the sum of the
  answered bands' values that day (the category's value when drilled into
  one), `nil` when that sum is zero. It is a net share: when a band is
  negative (an overdrawn cash account), a share can exceed 1 or be negative.
  The screen's legend shows this share in the privacy mode too (#1433,
  plan amendment D-A2, which retired the 100 % stack and its share on the
  positive bands, M3).

  **Exactness** (the closing act's money lens, M2): the security and total
  levels add up to the series exactly, every day. At the category level a
  band first sums its members, so the day's terms are added in another
  grouping than the walk adds them; when a conversion quotient does not
  terminate (a USD value over EUR/USD 1.0832), each partial sum rounds at
  Decimal's 34 significant digits, and the bands' sum may differ from the
  series by at most one unit in the 34th significant digit per day. When
  every quotient terminates, it is exact at every level. With a filter the
  bands add up to the filter's band one level up under the same rule, since
  that band, too, sums its members first.

  **The TTWROR scale** (FR-57, Sprint 28 S3, scope-ladder level (b)):
  `scale: :ttwror` answers each band as a line, its own time-weighted
  return over the window, not stacked, since returns do not add up. A
  band's flows are ADR-0051's net flows of its securities kept per day (a
  group's the sum); the day's net flow counts at the day's start when it is
  an inflow, `1 + r = V / (V_prev + F + B)`, and at its end when an
  outflow, `1 + r = (V − F) / (V_prev + B)`, `B` the day's trade-price
  basis step of its securities (#545) and a day without a positive base no
  return, as in the walk. A day whose opening value `V_prev + B` is not
  positive (a short, a band at zero) contributes no return either, so an
  inflow that nets against a negative opening value never chains a factor
  of 0: the line waits until the band opens above zero again (the closing
  act's money lens, ML1). A band with a value at the baseline's close
  chains from it; else its line starts at 0 % on its first day with a
  value. After its start a day on which it holds nothing and moved nothing
  has no point, so a band sold out inside the window ends at the sale day.
  At most eight lines, by value on the window's last day (ties by name,
  never by id), without cash and `unclassified` beside the categories and
  never merged into `other`; `parent` is the line one level up, the view's
  own TTWROR (the walk's series, exactly) or the filter's band. Dividends,
  interest and trade costs are no flow: they move cash, which has no line.

  Nothing is stored: each read runs its own walk from the window's baseline
  day (ADR-0051, note of 2026-10-28).
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Targets

  @zero Decimal.new("0")
  @hub "EUR"
  @levels [:total, :category, :security]
  @sorts [:size, :change]
  @scales [:value, :ttwror]
  @max_bands 8
  @one Decimal.new("1")
  @empty_day %{securities: %{}, cash: Decimal.new("0"), flows: %{}, basis: %{}}

  @doc "The levels a stack groups by."
  def levels, do: @levels

  @doc "The orders the bands are answered in."
  def sorts, do: @sorts

  @doc "The most bands one answer carries."
  def max_bands, do: @max_bands

  @doc "The scales a read answers in: the values, or each band's own TTWROR."
  def scales, do: @scales

  @doc """
  The bands of one portfolio over a period.

  Options: `:period` (`Performance.summarise/2`'s terms, default `"max"`),
  `:view` (a view id narrowing the portfolio), `:today`, `:level`
  (`#{inspect(@levels)}`, default `:category`), `:classification_id`,
  `:category_id` (a category's id or `:unclassified`, the filter, at every
  level), `:sort` (`#{inspect(@sorts)}`, default `:size`) and `:scale`
  (`#{inspect(@scales)}`, default `:value`; `:ttwror` answers each band's own
  return as a line, see the moduledoc).

  Returns `{:ok, result}` or `{:error, reason}`, the reason one of
  `:invalid_level`, `:invalid_sort`, `:invalid_scale`, `:invalid_period`, `:view_not_found`,
  `:classification_not_found`, `:category_not_found`, `:invalid_category`
  and `:category_outside_classification`.
  """
  @spec for_portfolio(integer(), keyword()) :: {:ok, map()} | {:error, atom()}
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    period = Keyword.get(opts, :period, "max")
    view = Keyword.get(opts, :view)
    today = Keyword.get(opts, :today, Clock.today())

    with {:ok, request} <- request(opts),
         :ok <- Performance.validate_period(period),
         {:ok, scope} <- loaded(Buckets.load_scope(portfolio_id, view)),
         {:ok, grouping} <-
           grouping(request, fn -> Targets.list_targets(portfolio_id, view: view) end) do
      portfolio_id
      |> Performance.contribution_analysis(scope, period,
        today: today,
        from_baseline: true,
        bands: true
      )
      |> build(period, request, grouping)
      |> Map.merge(%{portfolio_id: portfolio_id, view_id: view})
      |> then(&{:ok, &1})
    end
  end

  @doc """
  The bands of a bucket view across all portfolios (ADR-0024), the scope
  `Performance.for_view/2` walks; `view_id` nil is the Everything scope.
  Options as in `for_portfolio/2` without `:view`, plus `:base_currency`
  (default the EUR hub). The default classification reads the active plans
  of this view (the Gesamt plans for the Everything scope) in every
  portfolio.
  """
  @spec for_view(integer() | nil, keyword()) :: {:ok, map()} | {:error, atom()}
  def for_view(view_id, opts \\ []) when is_integer(view_id) or is_nil(view_id) do
    period = Keyword.get(opts, :period, "max")
    base = Keyword.get(opts, :base_currency, @hub)
    today = Keyword.get(opts, :today, Clock.today())

    targets = fn ->
      Enum.flat_map(Portfolios.list_portfolios(), &Targets.list_targets(&1.id, view: view_id))
    end

    with {:ok, request} <- request(opts),
         :ok <- Performance.validate_period(period),
         {:ok, scope} <- loaded(Buckets.load_global_scope(view_id)),
         {:ok, grouping} <- grouping(request, targets) do
      view_id
      |> Performance.view_contribution_analysis(scope, period,
        base_currency: base,
        today: today,
        from_baseline: true,
        bands: true
      )
      |> build(period, request, grouping)
      |> Map.merge(%{portfolio_id: nil, view_id: view_id})
      |> then(&{:ok, &1})
    end
  end

  defp loaded({:error, :view_not_found} = error), do: error
  defp loaded(scope), do: {:ok, scope}

  # -- the request -----------------------------------------------------------------

  defp request(opts) do
    level = Keyword.get(opts, :level, :category)
    sort = Keyword.get(opts, :sort, :size)
    scale = Keyword.get(opts, :scale, :value)
    category_id = Keyword.get(opts, :category_id)

    cond do
      level not in @levels ->
        {:error, :invalid_level}

      sort not in @sorts ->
        {:error, :invalid_sort}

      scale not in @scales ->
        {:error, :invalid_scale}

      not filter?(category_id) ->
        {:error, :invalid_category}

      true ->
        {:ok, %{level: level, sort: sort, scale: scale, category_id: category_id, opts: opts}}
    end
  end

  defp filter?(nil), do: true
  defp filter?(:unclassified), do: true
  defp filter?(id), do: is_integer(id)

  # What the bands group by: the classification (with how it was chosen),
  # the filter (a category, the unclassified remainder or none), and the
  # tree's filing of each security.
  defp grouping(request, targets) do
    with {:ok, requested} <- requested_classification(request.opts) do
      resolve(request, requested, targets)
    end
  end

  defp requested_classification(opts) do
    case Keyword.get(opts, :classification_id) do
      nil ->
        {:ok, nil}

      id ->
        case Classifications.get_classification(id) do
          nil -> {:error, :classification_not_found}
          classification -> {:ok, classification}
        end
    end
  end

  # A category filter stacks within the category's own tree, at any level.
  defp resolve(%{category_id: category_id}, requested, _targets)
       when is_integer(category_id) do
    with {:ok, category} <- fetch_category(category_id),
         :ok <- same_tree(category, requested) do
      classification = Classifications.get_classification(category.classification_id)
      {:ok, tree(classification, :category, {:category, category})}
    end
  end

  # The unclassified remainder is "filed nowhere" in the tree the category
  # level would stack by, so it chooses that tree, at any level.
  defp resolve(%{category_id: :unclassified}, requested, targets),
    do: chosen_tree(requested, targets, :unclassified)

  defp resolve(%{level: :category}, requested, targets),
    do: chosen_tree(requested, targets, nil)

  defp resolve(_request, _requested, _targets), do: {:ok, untreed(nil, nil)}

  defp chosen_tree(%{} = requested, _targets, filter),
    do: {:ok, tree(requested, :requested, filter)}

  defp chosen_tree(nil, targets, filter) do
    classifications = Classifications.list_classifications()
    targeted = MapSet.new(targets.(), & &1.classification_id)

    case Enum.find(classifications, &MapSet.member?(targeted, &1.id)) do
      nil ->
        case Classifications.default_classification(classifications) do
          nil -> {:ok, untreed(:default, filter)}
          classification -> {:ok, tree(classification, :default, filter)}
        end

      classification ->
        {:ok, tree(classification, :targets, filter)}
    end
  end

  defp fetch_category(id) do
    case Classifications.get_category(id) do
      nil -> {:error, :category_not_found}
      category -> {:ok, category}
    end
  end

  defp same_tree(_category, nil), do: :ok

  defp same_tree(category, classification) do
    if category.classification_id == classification.id,
      do: :ok,
      else: {:error, :category_outside_classification}
  end

  defp untreed(chosen_by, filter),
    do: %{
      classification: nil,
      chosen_by: chosen_by,
      filter: filter,
      category: nil,
      filing: %{},
      roots: %{},
      children: []
    }

  # The tree as stored today: each security's category with its ancestors,
  # each root category's position in tree order, and, under a category
  # filter, the category's direct sub-categories in tree order.
  defp tree(classification, chosen_by, filter) do
    categories = Classifications.list_categories(classification.id)
    by_id = Map.new(categories, &{&1.id, &1})
    {:ok, filing} = Classifications.security_category_map(classification.id)

    indexed =
      categories |> Enum.with_index() |> Enum.map(fn {c, i} -> Map.put(c, :tree_index, i) end)

    roots =
      for category <- indexed,
          category.parent_id == nil or not Map.has_key?(by_id, category.parent_id),
          into: %{},
          do: {category.id, category}

    filing =
      Map.new(filing, fn {security_id, category_id} ->
        {security_id, ancestry(category_id, by_id, [])}
      end)

    {filter, category, children} =
      case filter do
        {:category, category} ->
          category = Enum.find(indexed, &(&1.id == category.id))

          {{:category, category}, category,
           Enum.filter(indexed, &(&1.parent_id == category.id and &1.id != category.id))}

        other ->
          {other, nil, []}
      end

    %{
      classification: classification,
      chosen_by: chosen_by,
      filter: filter,
      category: category,
      filing: filing,
      roots: roots,
      children: children
    }
  end

  # A category and its ancestors, the category first and its root last; a
  # broken or cyclic parent chain stops where it breaks.
  defp ancestry(category_id, by_id, seen) do
    case Map.get(by_id, category_id) do
      nil ->
        Enum.reverse(seen)

      category ->
        seen = [category_id | seen]

        if category.parent_id == nil or category.parent_id in seen,
          do: Enum.reverse(seen),
          else: ancestry(category.parent_id, by_id, seen)
    end
  end

  # -- the bands -------------------------------------------------------------------

  defp build(analysis, period, request, grouping) do
    {:ok, summary} = Performance.summarise(analysis, period)

    {bands, parent} =
      case {analysis.contribution, request.scale} do
        {nil, _scale} -> {[], nil}
        {kept, :value} -> {bands(summary, kept, request, grouping), nil}
        {kept, :ttwror} -> lines(summary, kept, request, grouping)
      end

    # A window with no walked day is empty; a drilled category holding
    # nothing in scope keeps the window and its days, with no band (the
    # closing act's money lens, M4).
    walked? = analysis.contribution != nil and summary.series != []
    start_date = if walked?, do: summary.start_date

    %{
      period: summary.period,
      base_currency: summary.base_currency,
      start_date: start_date,
      end_date: summary.end_date,
      level: request.level,
      sort: request.sort,
      scale: request.scale,
      classification: classification_field(grouping),
      category_id: request.category_id,
      category: category_field(grouping.category),
      dates: if(walked?, do: Enum.map(summary.series, & &1.date), else: []),
      bands: bands,
      parent: parent,
      as_of: summary.as_of,
      stale: false,
      computation_basis:
        computation_basis(
          start_date,
          summary.end_date,
          request,
          grouping
        )
    }
  end

  defp classification_field(%{classification: nil}), do: nil

  defp classification_field(%{classification: classification, chosen_by: chosen_by}),
    do: %{id: classification.id, name: classification.name, chosen_by: chosen_by}

  defp category_field(nil), do: nil

  defp category_field(category),
    do: %{id: category.id, name: category.name, color: category.color}

  defp bands(summary, kept, request, grouping) do
    days = Enum.map(summary.series, &Map.get(kept.days, &1.date, @empty_day))

    case {request.level, grouping.filter} do
      {:total, nil} ->
        finish([total_band(summary)])

      {level, nil} ->
        level
        |> group(security_leaves(kept, days), cash_leaf(summary, kept, days), grouping)
        |> stack(request.sort)

      {level, filter} ->
        kept
        |> filter_leaves(days, filter, grouping)
        |> filtered(level, filter, grouping)
        |> stack(request.sort)
    end
  end

  defp filter_leaves(kept, days, filter, grouping) do
    kept
    |> security_leaves(days)
    |> Enum.filter(&in_filter?(&1.id, filter, grouping))
  end

  defp stack(bands, sort) do
    bands
    |> merge_small()
    |> finish()
    |> sort(sort)
    |> other_on_top()
  end

  # "Other" is the rest, never a peer of the bands it summarises: it is the
  # last band, on top of the stack, whatever the sort and its size (the
  # closing act's design critic, D4).
  defp other_on_top(bands) do
    {other, rest} = Enum.split_with(bands, &(&1.kind == :other))
    rest ++ other
  end

  # The series itself: its values, the period's start and end values and its
  # net external flows, exactly as the performance read chains them.
  defp total_band(summary) do
    %{
      key: "total",
      kind: :total,
      id: nil,
      name: "Total",
      color: nil,
      tree_index: nil,
      values: Enum.map(summary.series, & &1.value),
      start_value: summary.start_value,
      net_flows: summary.net_external_flows,
      members: []
    }
  end

  # One leaf per security the window touched: held on a window day, or
  # carrying a start value or a flow (ADR-0051's kept positions).
  defp security_leaves(kept, days) do
    ids =
      days
      |> Enum.flat_map(&Map.keys(&1.securities))
      |> Enum.concat(Map.keys(kept.positions))
      |> Enum.uniq()

    for id <- ids do
      position = Map.get(kept.positions, id, %{start_value: @zero, net_flows: @zero})
      label = Map.get(kept.securities, id, %{name: nil})

      %{
        key: "security:#{id}",
        kind: :security,
        id: id,
        name: label.name || "",
        color: nil,
        tree_index: nil,
        values: Enum.map(days, &Map.get(&1.securities, id, @zero)),
        start_value: position.start_value,
        net_flows: position.net_flows,
        # The per-band return's terms (FR-57): whether the security is held
        # at each day's close, and its flows and basis step of the day.
        held: Enum.map(days, &Map.has_key?(&1.securities, id)),
        flows: Enum.map(days, &Map.get(&1.flows, id, @zero)),
        basis: Enum.map(days, &Map.get(&1.basis, id, @zero)),
        members: []
      }
    end
  end

  # The cash: each day's balances in the base currency, the baseline day's
  # as its start value, and as its net flows the scope's net external flows
  # less every position's, so the bands' money changes add up to the
  # period's money result.
  defp cash_leaf(summary, kept, days) do
    position_flows = kept.positions |> Map.values() |> Enum.map(& &1.net_flows) |> sum()

    %{
      key: "cash",
      kind: :cash,
      id: nil,
      name: "Cash",
      color: nil,
      tree_index: nil,
      values: Enum.map(days, & &1.cash),
      start_value: kept.cash_start,
      net_flows: Decimal.sub(summary.net_external_flows, position_flows),
      members: []
    }
  end

  defp group(:security, securities, cash, _grouping), do: [cash | securities]

  defp group(:category, securities, cash, grouping) do
    {filed, unfiled} =
      Enum.split_with(securities, &(root_of(&1.id, grouping) != nil))

    categories =
      filed
      |> Enum.group_by(&root_of(&1.id, grouping))
      |> Enum.map(fn {root_id, members} ->
        category_band(members, Map.fetch!(grouping.roots, root_id))
      end)

    unclassified =
      case unfiled do
        [] -> []
        members -> [unclassified_band(members)]
      end

    [cash | unclassified] ++ categories
  end

  defp category_band(members, category) do
    members
    |> combine()
    |> Map.merge(%{
      key: "category:#{category.id}",
      kind: :category,
      id: category.id,
      name: category.name,
      color: category.color,
      tree_index: category.tree_index,
      members: []
    })
  end

  defp unclassified_band(members) do
    members
    |> combine()
    |> Map.merge(%{
      key: "unclassified",
      kind: :unclassified,
      id: nil,
      name: "Unclassified",
      color: nil,
      tree_index: nil,
      members: []
    })
  end

  # The securities a filter keeps: those filed under the category or any of
  # its descendants, or those the tree files nowhere.
  defp in_filter?(security_id, {:category, category}, %{filing: filing}),
    do: category.id in Map.get(filing, security_id, [])

  defp in_filter?(security_id, :unclassified, grouping),
    do: root_of(security_id, grouping) == nil

  # A filter's bands, no cash and no unclassified: its securities at the
  # security level; one band at the total level, and at the category level
  # for the unclassified remainder and a category without sub-categories;
  # else one band per direct sub-category over its subtree and one for the
  # securities filed in the category itself. Nothing in scope, no band.
  defp filtered([], _level, _filter, _grouping), do: []
  defp filtered(securities, :security, _filter, _grouping), do: securities
  defp filtered(securities, _level, :unclassified, _grouping), do: [unclassified_band(securities)]

  defp filtered(securities, :category, {:category, category}, %{children: [_ | _]} = grouping) do
    securities
    |> Enum.group_by(&branch_of(&1.id, category.id, grouping))
    |> Enum.map(fn
      {:direct, members} ->
        direct_band(members, category)

      {child_id, members} ->
        category_band(members, Enum.find(grouping.children, &(&1.id == child_id)))
    end)
  end

  defp filtered(securities, _level, {:category, category}, _grouping),
    do: [category_band(securities, category)]

  # Where under the filtered category a security sits: in the category
  # itself, or in the subtree of which direct sub-category. Its ancestry
  # lists its own category first, so the sub-category is the entry just
  # before the filtered one.
  defp branch_of(security_id, category_id, %{filing: filing}) do
    case Map.fetch!(filing, security_id) do
      [^category_id | _] ->
        :direct

      chain ->
        index = Enum.find_index(chain, &(&1 == category_id))
        Enum.at(chain, index - 1)
    end
  end

  defp direct_band(members, category) do
    members
    |> combine()
    |> Map.merge(%{
      key: "direct:#{category.id}",
      kind: :direct,
      id: category.id,
      name: category.name,
      color: nil,
      tree_index: nil,
      members: []
    })
  end

  defp root_of(security_id, %{filing: filing, roots: roots}) do
    case Map.get(filing, security_id) do
      nil -> nil
      [] -> nil
      chain -> if Map.has_key?(roots, List.last(chain)), do: List.last(chain), else: nil
    end
  end

  # Members' values add up day by day, and so do their start values and net
  # flows, and their day's flows and basis steps; a group is held on a day
  # when any member is.
  defp combine([first | rest]) do
    terms = [:values, :start_value, :net_flows, :held, :flows, :basis]

    Enum.reduce(rest, Map.take(first, terms), fn leaf, acc ->
      %{
        values: Enum.zip_with(acc.values, leaf.values, &Decimal.add/2),
        start_value: Decimal.add(acc.start_value, leaf.start_value),
        net_flows: Decimal.add(acc.net_flows, leaf.net_flows),
        held: Enum.zip_with(acc.held, leaf.held, &(&1 or &2)),
        flows: Enum.zip_with(acc.flows, leaf.flows, &Decimal.add/2),
        basis: Enum.zip_with(acc.basis, leaf.basis, &Decimal.add/2)
      }
    end)
  end

  # -- at most eight bands (D-5) ---------------------------------------------------

  defp merge_small(bands) when length(bands) <= @max_bands, do: bands

  defp merge_small(bands) do
    {fixed, mergeable} = Enum.split_with(bands, &(&1.kind in [:cash, :unclassified]))
    keep = @max_bands - 1 - length(fixed)
    {kept, rest} = mergeable |> Enum.sort(&larger?/2) |> Enum.split(keep)
    {kept, rest} = untie(kept, rest)
    fixed ++ kept ++ [other(rest)]
  end

  # The cut never falls inside a run of bands equal in value and name: such
  # bands differ by nothing but an id, so the whole run merges.
  defp untie([], rest), do: {[], rest}

  defp untie(kept, [first | _] = rest) do
    if same_rank?(List.last(kept), first),
      do: untie(Enum.drop(kept, -1), [List.last(kept) | rest]),
      else: {kept, rest}
  end

  defp same_rank?(a, b),
    do: Decimal.equal?(last_value(a), last_value(b)) and a.name == b.name

  # Larger value on the window's last day first; equal values by name.
  defp larger?(a, b) do
    case Decimal.compare(last_value(a), last_value(b)) do
      :gt -> true
      :lt -> false
      :eq -> name_key(a) <= name_key(b)
    end
  end

  defp other(members) do
    members
    |> combine()
    |> Map.merge(%{
      key: "other",
      kind: :other,
      id: nil,
      name: "Other",
      color: nil,
      tree_index: nil,
      members: Enum.map(members, &Map.take(&1, [:key, :kind, :id, :name]))
    })
  end

  # -- the per-band return (FR-57, Sprint 28 S3) ------------------------------------

  # The TTWROR scale: the same bands as the value scale, without cash and
  # unclassified beside the categories and without merging, at most eight
  # of them chosen by value on the window's last day; each band a line, its
  # own time-weighted return over the window. And the line one level up:
  # the view's own TTWROR, or the filter's band.
  defp lines(summary, kept, request, grouping) do
    days = Enum.map(summary.series, &Map.get(kept.days, &1.date, @empty_day))

    candidates =
      case {request.level, grouping.filter} do
        {:total, nil} ->
          [total_band(summary)]

        {level, nil} ->
          level
          |> group(security_leaves(kept, days), cash_leaf(summary, kept, days), grouping)
          |> Enum.reject(&(&1.kind in [:cash, :unclassified]))

        {level, filter} ->
          kept |> filter_leaves(days, filter, grouping) |> filtered(level, filter, grouping)
      end

    lines =
      candidates
      |> select_lines()
      |> Enum.map(&line(&1, summary))
      |> sort_lines(request.sort)

    {lines, parent_line(summary, kept, days, grouping)}
  end

  defp parent_line(summary, _kept, _days, %{filter: nil}), do: line(total_band(summary), summary)

  defp parent_line(summary, kept, days, %{filter: filter} = grouping) do
    case kept |> filter_leaves(days, filter, grouping) |> filtered(:total, filter, grouping) do
      [band] -> line(band, summary)
      [] -> nil
    end
  end

  # The eight largest by value on the window's last day, equal values by
  # name; a run equal in value and name at the cut is left out whole, as
  # the value scale merges it whole: nothing but an id would tell it apart.
  defp select_lines(bands) when length(bands) <= @max_bands, do: bands

  defp select_lines(bands) do
    {kept, rest} = bands |> Enum.sort(&larger?/2) |> Enum.split(@max_bands)
    {kept, _rest} = untie(kept, rest)
    kept
  end

  # The view's own line is the walk's TTWROR series itself, exactly the
  # performance read's; every other band chains its own days.
  defp line(%{kind: :total} = band, summary),
    do: line_of(band, Enum.map(summary.series, & &1.cumulative_ttwror))

  defp line(band, _summary), do: line_of(band, chain(band))

  defp line_of(band, returns) do
    band
    |> Map.take([:key, :kind, :id, :name, :color, :tree_index, :start_value, :net_flows])
    |> Map.merge(%{
      end_value: last_value(band),
      returns: returns,
      ttwror: returns |> Enum.reject(&is_nil/1) |> List.last()
    })
  end

  # A band with a value at the baseline's close chains from it, as the
  # view's line does; else it waits for its first day with a value, whose
  # close is its 0 %. Each later day's factor is chained; a day on which the
  # band holds nothing and moved nothing is no point.
  defp chain(band) do
    start =
      if Decimal.equal?(band.start_value, @zero), do: :waiting, else: {@one, band.start_value}

    [band.values, band.flows, band.basis, band.held]
    |> Enum.zip()
    |> Enum.map_reduce(start, &chain_day/2)
    |> elem(0)
  end

  defp chain_day({value, _flow, _basis, _held}, :waiting) do
    if Decimal.equal?(value, @zero), do: {nil, :waiting}, else: {@zero, {@one, value}}
  end

  defp chain_day({value, flow, basis, held}, {growth, prev}) do
    if not held and Decimal.equal?(value, @zero) and Decimal.equal?(flow, @zero) do
      {nil, {growth, value}}
    else
      growth = Decimal.mult(growth, day_factor(value, flow, basis, prev))
      {Decimal.sub(growth, @one), {growth, value}}
    end
  end

  # One day's factor 1 + r: the day's net flow at its start when it is an
  # inflow, `V / (V_prev + F + B)`, and at its end when an outflow,
  # `(V − F) / (V_prev + B)`, so a sale's proceeds are measured against the
  # value they left. `B` is the day's trade-price basis step (#545), as in
  # `Performance.day_factor/2`; a day whose base is not positive contributes
  # no return, the walk's rule. Nor does a day whose opening value
  # `V_prev + B` is not positive (ML1): a cover's inflow netting against a
  # short's negative value would make the base positive and the factor 0,
  # wiping out the band's whole chain.
  defp day_factor(value, flow, basis, prev) do
    {inflow, outflow} =
      if Decimal.negative?(flow), do: {@zero, Decimal.negate(flow)}, else: {flow, @zero}

    opening = Decimal.add(prev, basis)
    base = Decimal.add(opening, inflow)

    if Decimal.gt?(opening, @zero) and Decimal.gt?(base, @zero),
      do: Decimal.div(Decimal.add(value, outflow), base),
      else: @one
  end

  defp sort_lines(lines, :size), do: sort(lines, :size)
  defp sort_lines(lines, :change), do: by_figure(lines, & &1.ttwror)

  # -- figures and order -------------------------------------------------------------

  # Each band's end value, change without flows and share of the last day.
  defp finish(bands) do
    total = bands |> Enum.map(&last_value/1) |> sum()

    Enum.map(bands, fn band ->
      end_value = last_value(band)

      Map.merge(band, %{
        end_value: end_value,
        change: change(end_value, band.start_value, band.net_flows),
        share: if(Decimal.equal?(total, @zero), do: nil, else: Decimal.div(end_value, total))
      })
    end)
  end

  defp change(end_value, start_value, net_flows) do
    if Decimal.gt?(start_value, @zero) do
      end_value
      |> Decimal.sub(start_value)
      |> Decimal.sub(net_flows)
      |> Decimal.div(start_value)
    end
  end

  # Size: the largest band on the last day first. Change: the largest change
  # first, the bands without one last. Equal ones by name, then key.
  defp sort(bands, :size) do
    Enum.sort(bands, fn a, b ->
      case Decimal.compare(a.end_value, b.end_value) do
        :gt -> true
        :lt -> false
        :eq -> {name_key(a), a.key} <= {name_key(b), b.key}
      end
    end)
  end

  defp sort(bands, :change), do: by_figure(bands, & &1.change)

  # The largest figure first, the bands without one last.
  defp by_figure(bands, figure) do
    Enum.sort(bands, fn a, b ->
      case {figure.(a), figure.(b)} do
        {nil, nil} -> {name_key(a), a.key} <= {name_key(b), b.key}
        {nil, _} -> false
        {_, nil} -> true
        {x, y} -> by_change(Decimal.compare(x, y), a, b)
      end
    end)
  end

  defp by_change(:gt, _a, _b), do: true
  defp by_change(:lt, _a, _b), do: false
  defp by_change(:eq, a, b), do: {name_key(a), a.key} <= {name_key(b), b.key}

  defp last_value(%{values: []}), do: @zero
  defp last_value(%{values: values}), do: List.last(values)

  defp name_key(band), do: {String.downcase(band.name), band.name}

  defp sum(decimals), do: Enum.reduce(decimals, @zero, &Decimal.add(&2, &1))

  # -- the basis in the payload --------------------------------------------------------

  defp computation_basis(start_date, end_date, %{scale: :ttwror} = request, grouping) do
    %{
      input_series:
        "the daily valuation walk of ADR-0010 for this scope and period, as the value " <>
          "scale reads it: each window day's value of every held security, and each " <>
          "security's flows and trade-price basis step of the day, kept apart; a band's " <>
          "are its members' sums. scale=ttwror answers one line per band, its own " <>
          "time-weighted return over the window; returns[i] is the cumulative return " <>
          "through dates[i] (null: no point), ttwror the line's last point",
      window: %{start_date: start_date, end_date: end_date},
      reference: "parent: " <> parent_text(grouping),
      filter: filter_text(grouping),
      level: level_text(request.level, grouping),
      classification: classification_text(grouping),
      flows:
        "a band's flows are ADR-0051's net flows of its securities, per day: a buy + " <>
          "price × quantity and a sell − price × quantity at the booking day's rate, a " <>
          "delivery ± the value the walk's flow gives it (its booked price, else the " <>
          "day's price), a leg crossing a view's edge its boundary flow; a group's are " <>
          "its members' sums per day. The day's net flow counts at the day's start when " <>
          "an inflow, 1 + r = V / (V_prev + F + B), at its end when an outflow, 1 + r = " <>
          "(V − F) / (V_prev + B), so a sale's proceeds are measured against the value " <>
          "they left; B is the day's trade-price basis step of its securities (#545), as " <>
          "in the walk. Dividends, interest and trade fees and taxes are no flow and not " <>
          "in a line: they move cash, which has none, so a line is the return of the " <>
          "band's market value",
      start_rule:
        "a band holding a value at the close of the day before the window chains from " <>
          "that close, as the view's line does; else its line starts at 0 % on the first " <>
          "window day it holds a value (the move from that day's trade prices to its " <>
          "close is not in the line), the days before have no point. After its start a " <>
          "day on which it holds nothing and moved nothing has no point: a band sold out " <>
          "inside the window ends at the sale day, its ttwror the return through the " <>
          "sale; one that holds a value again later continues its chain from the first " <>
          "day it opens above zero (a day opening at or below zero adds no return)",
      selection_rule:
        "at most #{@max_bands} lines, none merged into other; without category_id no " <>
          "line for cash or unclassified (with it, the filter's own band stays): the " <>
          "#{@max_bands} largest bands by value on the window's last day, equal values " <>
          "by name and never by id; bands equal in value and name at the cut are both " <>
          "left out, since only an id would tell them apart. sort size orders the " <>
          "lines by that value, sort change by ttwror, largest first, null last; equal " <>
          "ones by name",
      gaps:
        "a day on which a held security has no price, or no rate path to the base " <>
          "currency, counts zero in its band, as it counts zero in the series; prices and " <>
          "rates carry the most recent stored point forward (ADR-0010), so a band counts " <>
          "zero only before its securities' first price or rate, and its line starts on " <>
          "its first day with a value; a security's first quote after trade prices is a " <>
          "basis step, not return. A day whose base (V_prev + inflow + B) is not " <>
          "positive contributes no return, the walk's rule; nor does a day whose opening " <>
          "value (V_prev + B) is not positive, so an inflow netting against a negative " <>
          "opening value (a short covered) is no return and the line waits until the band " <>
          "opens above zero again. A window holding no walked " <>
          "day is empty: start_date null, no dates, no lines and parent null",
      category_change:
        "a classification is stored as it is today, without a history: a security is " <>
          "drawn in its category of today on every day of the window (Sprint 27 plan D-5)",
      assumptions:
        "values are market values in the base currency at each day's close, at the " <>
          "day's rate; exact in Decimal whenever every quotient terminates, else each " <>
          "quotient rounds at Decimal's 34 significant digits. A line is not stacked: " <>
          "returns do not add up. No line is a rank, a signal or a recommendation"
    }
  end

  defp computation_basis(start_date, end_date, request, grouping) do
    %{
      input_series:
        "the daily valuation walk of ADR-0010, the value series the performance read of " <>
          "this scope and period answers: recorded transactions, stored quotes and stored " <>
          "EUR-hub exchange rates; each window day's terms kept apart, every held " <>
          "security's value and the cash, exactly the terms the day's value adds up, so " <>
          "the bands sum to the series on every day: exactly at the security and total " <>
          "levels; at the category level, the bands' sum may differ from the series by at " <>
          "most one unit in the 34th significant digit per day, and only when a conversion " <>
          "quotient does not terminate (a band sums its members first, and Decimal rounds " <>
          "each partial sum at 34 significant digits); with category_id, the bands sum to " <>
          "the filter's band one level up (that category's band, or unclassified, in the " <>
          "read of its parent category, or without category_id for a root category or " <>
          "unclassified) under the same rule: exactly when every conversion quotient " <>
          "terminates, else within one unit in the 34th significant digit per day",
      window: %{start_date: start_date, end_date: end_date},
      reference: nil,
      filter: filter_text(grouping),
      level: level_text(request.level, grouping),
      classification: classification_text(grouping),
      merge_rule:
        "at most #{@max_bands} bands, inside a filter too: cash and unclassified always " <>
          "keep their own band (a filter has neither beside its own bands); " <>
          "with more than #{@max_bands} bands, the smallest of the others by value on the " <>
          "window's last day, equal values by name and never by id, merge into other so " <>
          "that #{@max_bands} remain, and other lists its members; bands equal in value and " <>
          "name at the cut merge together; other is always the last band, on top of the " <>
          "stack, whatever the sort and its size",
      gaps:
        "a day on which a held security has no price, or no rate path to the base " <>
          "currency, counts zero in its band, as it counts zero in the series; prices and " <>
          "rates carry the most recent stored point on or before each day forward, and a " <>
          "security with no quote yet is priced by its own latest trade (ADR-0010); the " <>
          "contribution read of the same window names the affected positions and their " <>
          "days. A foreign-currency cash balance counts zero in the cash band on a day its " <>
          "currency has no rate path. A window holding no walked day is empty: start_date " <>
          "null, no dates and no bands; a drilled category holding nothing in the scope " <>
          "keeps the window's start_date and dates, with no bands",
      category_change:
        "a classification is stored as it is today, without a history: a security is " <>
          "drawn in its category of today on every day of the window, also when it was " <>
          "filed elsewhere earlier (Sprint 27 plan D-5)",
      assumptions:
        "values are market values in the base currency at each day's close; a buy or a " <>
          "sell shows as a step in its band. change = (end_value − start_value − " <>
          "net_flows) / start_value over the window, null when start_value is not " <>
          "positive: a security's start_value is its value at the close of the day before " <>
          "the window (0 when not held then, or when the walk starts inside the window) " <>
          "and its net_flows ADR-0051's (a buy + price × quantity and a sell − price × " <>
          "quantity at the booking day's rate, a delivery ± the value the walk's flow " <>
          "gives it, a leg crossing a view's edge its boundary flow); a group's are its " <>
          "members' sums; the cash band's net_flows are the scope's net external flows " <>
          "less every position's net flows, and the total band's the net external flows, " <>
          "so the bands' end_value − start_value − net_flows add up to the period's money " <>
          "result. share = the band's value on the window's last day over the sum of the " <>
          "answered bands' values that day, null when that sum is 0; a net share, so when " <>
          "a band is negative (an overdrawn cash account) a share can exceed 1 or be " <>
          "negative. Exact in Decimal " <>
          "whenever every conversion quotient terminates; otherwise the walk's sums round " <>
          "at Decimal's 34 significant digits. sort size orders by the last day's value, " <>
          "largest first; sort change by change, largest first, bands without one last; " <>
          "equal ones by name. No band is a rank, a signal or a recommendation"
    }
  end

  defp parent_text(%{filter: nil}),
    do:
      "the view's own TTWROR, exactly the performance read's cumulative series; the " <>
        "view's line counts every flow at the day's start, 1 + r = V / (V_prev + F + B); " <>
        "the bands count an outflow at the day's end, so a band that holds the whole " <>
        "view can differ from it on a day with a sale"

  defp parent_text(%{filter: :unclassified}),
    do: "the unclassified band's line, the filter's"

  defp parent_text(%{filter: {:category, category}}),
    do: "the line of the category #{inspect(category.name)}, the filter's band one level up"

  defp filter_text(%{filter: nil}),
    do: "none: the whole scope (category_id narrows every level to one category's subtree)"

  defp filter_text(%{filter: :unclassified}),
    do:
      "unclassified: the securities the classification files nowhere, no cash; they add " <>
        "up to the unclassified band of the read without category_id"

  defp filter_text(%{filter: {:category, category}}),
    do:
      "category #{inspect(category.name)} (id #{category.id}): the securities filed under " <>
        "it or any of its descendants, no cash and no unclassified; they add up to its " <>
        "band one level up"

  defp level_text(:total, %{filter: nil}), do: "total: one band, the series itself"

  defp level_text(:total, %{filter: :unclassified}),
    do: "total: one band, unclassified, the filter's line"

  defp level_text(:total, %{filter: {:category, category}}),
    do:
      "total: one band, the filtered category's line, keyed category:#{category.id} like " <>
        "its band one level up"

  defp level_text(:category, %{filter: nil}),
    do:
      "category: one band per root category of the classification, holding the " <>
        "securities filed under it or any of its descendants, plus cash and unclassified " <>
        "(the securities the classification files nowhere)"

  defp level_text(:category, %{filter: :unclassified}),
    do:
      "category: the unclassified remainder has no sub-categories, so one band, " <>
        "unclassified"

  defp level_text(:category, %{filter: {:category, category}, children: []}),
    do:
      "category: #{inspect(category.name)} has no sub-categories, so one band, its own, " <>
        "keyed category:#{category.id}"

  defp level_text(:category, %{filter: {:category, category}}),
    do:
      "category: one band per direct sub-category of #{inspect(category.name)} holding " <>
        "something in the scope, each over the securities filed under it or any of its " <>
        "descendants, plus one band of kind direct (key direct:#{category.id}, the " <>
        "category's id and name) for the securities filed in #{inspect(category.name)} " <>
        "itself, absent when it holds none; no cash, no unclassified; they add up to the " <>
        "category's band"

  defp level_text(:security, %{filter: nil}),
    do: "security: one band per security of the scope, plus cash"

  defp level_text(:security, %{filter: :unclassified}),
    do:
      "security: one band per security the classification files nowhere, no cash; they " <>
        "add up to the unclassified band"

  defp level_text(:security, %{filter: {:category, category}}),
    do:
      "security: one band per security filed under the category #{inspect(category.name)} " <>
        "or any of its descendants, no cash; they add up to that category's band"

  defp classification_text(grouping) do
    rule =
      "chosen as requested by classification_id; else, at the category level, the tree " <>
        "of the allocation targets of the scope's active plan (the first in tree order " <>
        "when targets sit in several trees), else the default steering tree: the first " <>
        "custom classification, else the built-in asset class tree, the same for the " <>
        "unclassified filter at every level; a category filter stacks within its own tree"

    case grouping do
      %{classification: nil, chosen_by: nil} ->
        "none: this level groups by no classification. Rule: " <> rule

      %{classification: nil} ->
        "none: no classification exists, so every security is unclassified. Rule: " <> rule

      %{classification: classification, chosen_by: chosen_by} ->
        "#{inspect(classification.name)} (#{chosen_text(chosen_by)}). Rule: " <> rule
    end
  end

  defp chosen_text(:requested), do: "requested by classification_id"
  defp chosen_text(:targets), do: "the tree of this scope's allocation targets"
  defp chosen_text(:default), do: "no allocation target in this scope: the default tree"
  defp chosen_text(:category), do: "the tree of the category named by category_id"
end
