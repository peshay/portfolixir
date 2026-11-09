defmodule PortfolixirWeb.Portfolio.StackedChart do
  @moduledoc """
  The stacked value chart on Wealth → Holdings → Performance (I23, FR-53;
  idea board `ux-design-2026-11-06-ideas-i23-i24/01-stacked-chart`, variant
  A; Sprint 27 plan D-4, D-5), with the filter of FR-56 (Sprint 28 S2,
  board `ux-design-2026-11-08-sprint28/02-stack-filter`).

  The anatomy (DESIGN.md → Amendment 2026-11-07 → the stacked chart):

    * **the bar** (`bar/1`) above the chart, in the value series only: the
      breadcrumb on the left, the filter's path through its tree, then the
      level (Total · Categories · Securities), the classification and the
      sort (Size · Change). Every choice is a link that patches the address,
      so a link handed over reopens the same stack; a level keeps the
      filter. At the level Total without a filter the bar holds the level
      alone, and the chart under it is today's value chart, unchanged. The
      bar is the first user of "labelled controls start on one edge"
      (DESIGN.md, amendment of 2026-11-08): a container query turns it into
      a label column, or labels above their controls, when it wraps;
    * **the bands** (`figure/1`): `Portfolixir.Portfolios.Performance.Bands`'
      daily values, the first band of its order at the bottom, the largest
      by the chosen sort. A band's part below zero (an overdrawn cash
      account) is an area of its own under the zero line, a little lighter,
      and a band that changes sign inside the window is drawn next to the
      zero line, so no band crosses another (#1426). At the category level a
      category's band, and the unassigned rest's, sets the filter on a
      click and keeps the level;
    * **the legend as a table**, reading like the stack, the top band first:
      the swatch and the name (a filterable band's name is the link), the
      value on the window's last day, its share and its change without
      flows;
    * **the basis line**: one line, what the chart shows, the window and
      when it was computed, ending in the section's ⓘ that holds the method
      (I1; #1366).

  **The privacy mode** (I22; #1433, plan amendment D-A2, board 06): the
  stack keeps its shape, the same picture as without the mode, and only
  its labels change: each axis tick reads in percent of the bands' total
  on the window's first day (100 %), the filtered stack's total under a
  filter, as Sprint 26's rule reads every axis in a currency. Where that
  total is not above zero (a buy booked before its money), the axis indexes
  to the first day it is, and says so behind the ⓘ; where no day is, the
  ticks carry no label. The legend keeps share (the API's net share) and
  change and drops the value, the bands' tooltips name no amount, and no
  attribute carries one. Sprint 27's 100 % stack retired with D-A2.

  The geometry is computed here on the server from the `Decimal` values;
  floats exist only as coordinates and are never stored.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode

  @width 960
  @height 320
  @padding_top 16
  @padding_right 24
  @padding_bottom 28
  @padding_left 56
  @max_points 400

  # -- the bar ---------------------------------------------------------------------

  attr(:stack, :map, required: true)
  attr(:paths, :map, required: true)
  attr(:crumbs, :list, required: true)
  attr(:classifications, :list, required: true)
  attr(:classification_id, :any, default: nil)

  @doc """
  The bar above the value chart. `paths` holds the address of every choice:
  `:total`, `:category`, `:security`, `:size` and `:change`; `crumbs` is the
  breadcrumb as `{label, path | nil}`, each step up the filter's tree a
  link, the last one the place shown.
  """
  def bar(assigns) do
    ~H"""
    <div class="stack-bar" data-role="stack-bar">
      <nav class="stack-crumbs" data-role="stack-crumbs" aria-label={gettext("Stack")}>
        <%= for {{label, path}, index} <- Enum.with_index(@crumbs) do %>
          <span :if={index > 0} class="stack-crumbs__sep" aria-hidden="true">›</span>
          <%= if path do %>
            <.link patch={path}><%= label %></.link>
          <% else %>
            <span id="stack-crumbs-current" aria-current="location" tabindex="-1"><%= label %></span>
          <% end %>
        <% end %>
      </nav>
      <div class="stack-bar__controls">
        <span class="stack-bar__group">
        <span class="stack-bar__label" id="stack-level-label"><%= gettext("Level") %></span>
        <div
          class="segmented-control"
          data-role="stack-level"
          role="group"
          aria-labelledby="stack-level-label"
        >
          <.link
            :for={{level, label} <- level_options()}
            patch={Map.fetch!(@paths, level)}
            class={["segmented-control__option", @stack.level == level && "is-active"]}
            data-level={level}
            aria-current={if @stack.level == level, do: "true"}
          >
            <%= label %>
          </.link>
        </div>
        </span>
        <form
          :if={@stack.level == :category or (@stack.level == :security and not is_nil(@stack.category))}
          id="stack-classification-form"
          class="stack-bar__tree"
          phx-change="select_stack_classification"
        >
          <label for="stack-classification"><%= gettext("Classification") %></label>
          <select id="stack-classification" name="tree">
            <option
              :for={classification <- @classifications}
              value={classification.id}
              selected={classification.id == @classification_id}
            >
              <%= ClassificationName.display(classification) %>
            </option>
          </select>
        </form>
        <span :if={@stack.level != :total} class="stack-bar__group">
        <span class="stack-bar__label" id="stack-sort-label">
          <%= gettext("Sort") %>
        </span>
        <div
          class="segmented-control"
          data-role="stack-sort"
          role="group"
          aria-labelledby="stack-sort-label"
        >
          <.link
            :for={{sort, label} <- sort_options()}
            patch={Map.fetch!(@paths, sort)}
            class={["segmented-control__option", @stack.sort == sort && "is-active"]}
            data-sort={sort}
            aria-current={if @stack.sort == sort, do: "true"}
          >
            <%= label %>
          </.link>
        </div>
        </span>
      </div>
    </div>
    """
  end

  defp level_options,
    do: [
      total: gettext("Total"),
      category: gettext("Categories"),
      security: gettext("Securities")
    ]

  # "Veränderung" in German, as the board and the basis line say it, where
  # the shared "Change" reads "Änderung" (the closing act's design critic,
  # D3).
  defp sort_options, do: [size: gettext("Size"), change: pgettext("stack", "Change")]

  # -- the figure ------------------------------------------------------------------

  attr(:result, :map, required: true)
  attr(:colors, :map, required: true)
  attr(:drill_paths, :map, required: true)
  attr(:benchmark_note, :string, default: nil)

  @doc """
  The stacked bands and their legend. `result` is a `Bands` answer,
  `colors` each band's colour by key (`:other` for the neutral token),
  `drill_paths` the address a band's filter opens, by key (FR-56: a
  category, or the unassigned rest), and `benchmark_note` the sentence
  that the benchmarks are drawn in the TTWROR series only, when any is
  chosen; it joins the method behind the basis line's ⓘ.
  """
  def figure(assigns) do
    privacy? = PrivacyMode.on?()
    geometry = geometry(assigns.result)
    bands = assigns.result.bands

    assigns =
      assign(assigns,
        privacy?: privacy?,
        index: if(privacy?, do: index_basis(assigns.result)),
        geometry: geometry,
        legend: Enum.reverse(bands),
        by_key: Map.new(bands, &{&1.key, &1}),
        width: @width,
        height: @height,
        plot_left: @padding_left,
        plot_right: @width - @padding_right,
        other?: Enum.any?(assigns.result.bands, &(&1.kind == :other))
      )

    ~H"""
    <figure
      id="performance-figure-stack"
      class="perf-figure stack-figure"
      data-level={@result.level}
      data-scale={if @privacy?, do: "percent", else: "value"}
    >
      <%= if @result.bands == [] do %>
        <p class="hint" data-role="stack-empty"><%= gettext("No values in this period.") %></p>
      <% else %>
        <div class="stack-figure__body">
          <div class="stack-figure__chart" id="stack-figure-chart" phx-hook="ChartScale">
            <svg
              class="stack-chart"
              role="img"
              aria-label={aria_label(@result)}
              viewBox={"0 0 #{@width} #{@height}"}
              preserveAspectRatio="xMidYMid meet"
              width="100%"
              data-points={@geometry.points}
              data-plot-top={coord(@geometry.plot_top)}
            >
              <g class="chart-axes" stroke="currentColor" stroke-opacity="0.15">
                <line
                  :for={{_value, y} <- @geometry.ticks}
                  x1={@plot_left}
                  y1={coord(y)}
                  x2={@plot_right}
                  y2={coord(y)}
                />
              </g>
              <path
                :for={%{key: key, part: part, d: d} <- @geometry.parts}
                class={[
                  "stack-band",
                  band_class(Map.fetch!(@by_key, key)),
                  Map.get(@colors, key) == :other && "stack-band--other",
                  part == :negative && "stack-band--negative"
                ]}
                d={d}
                fill={fill(Map.get(@colors, key))}
                data-band={key}
                data-part={if part == :negative, do: "negative"}
                phx-click={if Map.has_key?(@drill_paths, key), do: "drill_stack"}
                phx-value-category={if Map.has_key?(@drill_paths, key), do: filter_value(Map.fetch!(@by_key, key))}
              >
                <title><%= band_title(Map.fetch!(@by_key, key), @privacy?) %></title>
              </path>
              <line
                :if={@geometry.zero_y}
                class="chart-zeroline"
                x1={@plot_left}
                y1={coord(@geometry.zero_y)}
                x2={@plot_right}
                y2={coord(@geometry.zero_y)}
              />
              <g class="chart-axis-labels">
                <text
                  :for={{{value, y}, index} <- Enum.with_index(@geometry.ticks)}
                  :if={not @privacy? or @index != :none}
                  class={["chart-axis-y", index == length(@geometry.ticks) - 1 && "is-top"]}
                  x={@plot_left - 6}
                  y={coord(y)}
                  text-anchor="end"
                  dominant-baseline="central"
                >
                  <%= tick_label(value, @index) %>
                </text>
                <text class="chart-axis-x" x={@plot_left} y={@height - 6} text-anchor="start">
                  <%= Format.date(@geometry.first_date) %>
                </text>
                <text class="chart-axis-x" x={@plot_right} y={@height - 6} text-anchor="end">
                  <%= Format.date(@geometry.last_date) %>
                </text>
              </g>
            </svg>
          </div>
          <table
            id="stack-legend"
            class="stack-legend"
            data-role="stack-legend"
            data-date={Date.to_iso8601(@result.end_date)}
          >
            <caption class="sr-only">
              <%= gettext("The bands on %{date}, the top band first", date: Format.date(@result.end_date)) %>
            </caption>
            <thead>
              <tr>
                <th scope="col">
                  <%= if @result.level == :security, do: gettext("Security"), else: gettext("Category") %>
                </th>
                <th :if={not @privacy?} scope="col" class="num"><%= gettext("Value") %></th>
                <th scope="col" class="num"><%= gettext("Share") %></th>
                <th scope="col" class="num"><%= pgettext("stack column", "Change") %></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={band <- @legend}
                data-band={band.key}
                data-end-value={Format.amount_attribute(Decimal.normalize(band.end_value))}
              >
                <td class="stack-legend__name">
                  <span
                    class={["stack-swatch", Map.get(@colors, band.key) == :other && "stack-swatch--other"]}
                    style={swatch_style(Map.get(@colors, band.key))}
                    aria-hidden="true"
                  >
                  </span>
                  <%= if path = Map.get(@drill_paths, band.key) do %>
                    <.link patch={path} class="stack-legend__drill"><%= band_name(band) %></.link>
                    <span class="stack-legend__chevron" aria-hidden="true">›</span>
                  <% else %>
                    <%= band_name(band) %>
                  <% end %>
                </td>
                <td :if={not @privacy?} class="num" data-role="stack-value"><%= Format.money(band.end_value) %></td>
                <td class="num" data-role="stack-share"><%= share(band.share) %></td>
                <td class={["num", sign_class(band.change)]} data-role="stack-change">
                  <%= change(band.change) %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <%!-- I1 (#1351; #1366, amendment D-A4, board 07 ② and ③): one
             line stays, what the chart shows, the window and when it was
             computed; the method sits in the ⓘ at its end. --%>
        <div class="hint stack-basis" data-role="stack-basis">
          <span data-role="stack-basis-line">
            <%= shows(@result) %> · <%= Format.date(@result.start_date) %> – <%= Format.date(@result.end_date) %><%= if @result.as_of do %> · <%= gettext("computed %{at}", at: Format.utc_instant(@result.as_of)) %><% end %>
          </span>
          <AppShell.section_info>
            <:line :for={line <- method(@result, @index, @drill_paths != %{}, @other?)}><%= line %></:line>
            <:line :if={@benchmark_note}><span data-role="benchmark-value-hint"><%= @benchmark_note %></span></:line>
          </AppShell.section_info>
        </div>
      <% end %>
    </figure>
    """
  end

  # -- names, figures and words ----------------------------------------------------

  # The privacy mode's 100 % (#1433, D-A2): the bands' total on the
  # window's first day, the filtered stack's under a filter, taken from the
  # `Decimal` values; when it is not above zero, the first day whose total
  # is. `{date, total, first?}`, or `:none` when no day's total is above
  # zero, so no tick can be read in percent of it.
  defp index_basis(%{dates: dates, bands: bands}) do
    columns = bands |> Enum.map(& &1.values) |> Enum.zip_with(& &1)

    dates
    |> Enum.zip(columns)
    |> Enum.with_index()
    |> Enum.find_value(:none, fn {{date, day}, i} ->
      total = Enum.reduce(day, Decimal.new(0), &Decimal.add/2)
      if Decimal.gt?(total, 0), do: {date, total, i == 0}
    end)
  end

  @doc "A band's name in the page's language: the fixed bands translated."
  def band_name(%{kind: :cash}), do: gettext("Cash")
  def band_name(%{kind: :unclassified}), do: gettext("Unassigned")
  def band_name(%{kind: :other}), do: pgettext("stack band", "Other")
  def band_name(%{kind: :total}), do: gettext("Total")
  # FR-56: the securities filed in a filtered category itself; the API
  # carries the category's plain name.
  def band_name(%{kind: :direct, name: name}), do: gettext("%{name} (direct)", name: name)
  def band_name(%{name: name}), do: name

  defp band_class(%{kind: kind}), do: "stack-band--#{kind_class(kind)}"

  defp kind_class(:category), do: "category"
  defp kind_class(:security), do: "security"
  defp kind_class(:cash), do: "cash"
  defp kind_class(:unclassified), do: "unclassified"
  defp kind_class(:other), do: "other"
  defp kind_class(:total), do: "total"
  defp kind_class(:direct), do: "direct"

  # The tooltip: the name and the share, and the value unless the privacy
  # mode is on (the figure's text would be the stand-in, never the bar).
  defp band_title(band, true), do: "#{band_name(band)} · #{share(band.share)}"

  defp band_title(band, false),
    do: "#{band_name(band)} · #{Format.money(band.end_value)} · #{share(band.share)}"

  defp share(%Decimal{} = share), do: Format.percent(share) <> "%"
  defp share(_none), do: "—"

  defp change(%Decimal{} = change), do: Format.signed_percent(change) <> "%"
  defp change(_none), do: "—"

  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      _other -> nil
    end
  end

  defp fill(color) when is_binary(color), do: color
  defp fill(_other), do: nil

  defp swatch_style(color) when is_binary(color), do: "background: #{color}"
  defp swatch_style(_other), do: nil

  defp aria_label(%{level: :security}), do: gettext("Value by security over time")
  defp aria_label(_result), do: gettext("Value by category over time")

  # The visible half of the basis: what the chart shows (I1's basis
  # clause), the filter named.
  defp shows(%{category_id: :unclassified} = result),
    do:
      gettext("Market value of what “%{tree}” files nowhere",
        tree: tree_name(result.classification)
      )

  defp shows(%{level: :security, category: %{name: name}}),
    do: gettext("Market value per security of “%{category}”", category: name)

  defp shows(%{level: :category, category: %{name: name}} = result) do
    if divided?(result),
      do: gettext("Market value of “%{category}” by sub-category", category: name),
      else: gettext("Market value of “%{category}”", category: name)
  end

  defp shows(%{category: %{name: name}}),
    do: gettext("Market value of “%{category}”", category: name)

  defp shows(%{level: :category} = result),
    do: gettext("Market value per category of “%{tree}”", tree: tree_name(result.classification))

  defp shows(_result), do: gettext("Market value per security and the cash")

  # The method behind the ⓘ, one sentence per line (I1): the currency and
  # what a band holds, the change, the order, the merge, the negative parts,
  # what a click does, and what the privacy mode's axis reads.
  defp method(result, index, filter_links?, other?) do
    [
      gettext("Market value at each day's close, in %{currency}.",
        currency: result.base_currency
      ),
      holds(result),
      gettext("Change without deposits and withdrawals."),
      order_text(result.sort),
      other? &&
        gettext("Above eight bands the smallest merge into “Other”, which always sits on top."),
      negative?(result) &&
        gettext(
          "Below zero a band is drawn lighter, under the zero line; a band that changes sign sits next to it."
        ),
      filter_links? &&
        gettext(
          "A click on a category filters the stack to it and keeps the level; the path above leads back."
        ),
      privacy_axis(index)
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp privacy_axis(nil), do: nil

  defp privacy_axis({_date, _total, true}),
    do:
      gettext(
        "In the privacy mode the axis reads in percent of the bands’ total on the window’s first day (100 %); the picture is the same."
      )

  defp privacy_axis({date, _total, false}),
    do:
      gettext(
        "In the privacy mode the axis reads in percent of the bands’ total on %{date}, the first day it is above zero (100 %); the picture is the same.",
        date: Format.date(date)
      )

  defp privacy_axis(:none),
    do:
      gettext(
        "In the privacy mode the axis has no labels: the bands’ total is above zero on no day of the window."
      )

  defp holds(%{category_id: nil, level: :category}),
    do: gettext("Cash and the unassigned rest are bands of their own.")

  defp holds(%{category_id: nil, level: :security}), do: gettext("Cash is a band of its own.")
  defp holds(%{category_id: nil}), do: nil

  defp holds(%{level: :category, bands: bands, category: %{name: name}} = result) do
    cond do
      Enum.any?(bands, &(&1.kind == :direct)) ->
        gettext(
          "Each sub-category over its whole subtree, “%{name} (direct)” the securities filed in “%{name}” itself; no cash, no unassigned rest.",
          name: name
        )

      divided?(result) ->
        gettext("Each sub-category over its whole subtree; no cash, no unassigned rest.")

      true ->
        holds(:filtered)
    end
  end

  defp holds(_filtered),
    do: gettext("Without cash and the unassigned rest; the bands add up to the filter's band.")

  # A filtered category drawn by its sub-categories, not as its own band.
  defp divided?(%{bands: bands, category: %{id: id}}),
    do: Enum.any?(bands, &(&1.kind == :direct or (&1.kind == :category and &1.id != id)))

  defp negative?(result),
    do: Enum.any?(result.bands, fn band -> Enum.any?(band.values, &Decimal.negative?/1) end)

  # The value a band's click sends: a category's id, or the unassigned
  # rest.
  defp filter_value(%{kind: :unclassified}), do: "unclassified"
  defp filter_value(%{id: id}), do: id

  defp tree_name(%{name: name}), do: name
  defp tree_name(_none), do: gettext("none")

  defp order_text(:change),
    do:
      gettext(
        "The band with the largest change at the bottom; the legend reads like the stack, top band first."
      )

  defp order_text(_size),
    do:
      gettext("The largest band at the bottom; the legend reads like the stack, top band first.")

  # A tick in the privacy mode reads as a whole percent of the index's
  # total (a ratio, so the plain form); a tick in money as the shared
  # chart's axis prints it.
  defp tick_label(value, {_date, total, _first?}) do
    percent = round(value / Decimal.to_float(total) * 100)
    Format.plain_decimal(Decimal.new(percent), 0) <> "%"
  end

  defp tick_label(value, nil) when value == 0, do: Format.decimal(Decimal.new(0), 0)

  defp tick_label(value, nil) do
    places =
      cond do
        abs(value) >= 1000 -> 0
        abs(value) >= 1 -> 2
        true -> 4
      end

    Format.decimal(Decimal.from_float(value * 1.0), places)
  end

  # -- geometry ---------------------------------------------------------------------

  # The drawn days (at most @max_points, the window's last day always among
  # them), each band's areas, and the axis. A band draws one area above the
  # zero line and, when it is negative on a day, a second one below it, so
  # the two never cross the bands between (#1426); a band that changes sign
  # inside the window is drawn first, next to the zero line, and its two
  # areas meet there. „Other“ stays on top whatever its sign (D4).
  defp geometry(%{bands: []}), do: nil

  defp geometry(result) do
    indices = sample(length(result.dates))
    dates = Enum.map(indices, &Enum.at(result.dates, &1))

    series =
      Enum.map(result.bands, fn band ->
        values = List.to_tuple(band.values)
        {band.key, Enum.map(indices, &to_float(elem(values, &1)))}
      end)

    kinds = Map.new(result.bands, &{&1.key, &1.kind})
    stacked = series |> zero_first(kinds) |> stack()

    {lo, hi} = range(stacked)
    plot_top = @padding_top * 1.0
    plot_bottom = (@height - @padding_bottom) * 1.0
    plot_left = @padding_left * 1.0
    plot_right = (@width - @padding_right) * 1.0
    n = length(indices)

    x = fn i ->
      if n == 1, do: plot_left, else: plot_left + (plot_right - plot_left) * i / (n - 1)
    end

    y = fn v -> plot_bottom - (plot_bottom - plot_top) * (v - lo) / (hi - lo) end

    parts =
      Enum.map(stacked, fn {key, part, edges} ->
        upper = edges |> Enum.with_index() |> Enum.map(fn {{_l, u}, i} -> {x.(i), y.(u)} end)

        lower =
          edges
          |> Enum.with_index()
          |> Enum.map(fn {{l, _u}, i} -> {x.(i), y.(l)} end)
          |> Enum.reverse()

        %{key: key, part: part, d: path(upper ++ lower)}
      end)

    ticks =
      for i <- 0..4 do
        value = lo + (hi - lo) * i / 4
        {value, y.(value)}
      end

    %{
      points: n,
      plot_top: plot_top,
      parts: parts,
      zero_y: if(lo < 0, do: y.(0.0)),
      ticks: ticks,
      first_date: List.first(dates),
      last_date: List.last(dates)
    }
  end

  # The bands that change sign inside the window first, in their order,
  # then the others: the first sit next to the zero line (#1426).
  defp zero_first(series, kinds) do
    {changing, steady} =
      Enum.split_with(series, fn {key, values} ->
        Map.get(kinds, key) != :other and Enum.any?(values, &(&1 > 0)) and
          Enum.any?(values, &(&1 < 0))
      end)

    changing ++ steady
  end

  defp sample(count) when count <= @max_points, do: Enum.to_list(0..(count - 1)//1)

  defp sample(count) do
    step = count |> Kernel./(@max_points) |> Float.ceil() |> trunc()
    sampled = Enum.take_every(0..(count - 1), step)
    if List.last(sampled) == count - 1, do: sampled, else: sampled ++ [count - 1]
  end

  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)

  # Each band's areas with their lower and upper edge per day, the first
  # band at the bottom: its positive part stacks up from the positives
  # below it, its negative part down from the negatives (a diverging stack),
  # so each day's bands still add up to its value. The positive area is
  # drawn unless the band is never above zero; the negative one only when
  # it is below zero on some day.
  defp stack(series) do
    days = series |> hd() |> elem(1) |> length()
    start = {List.duplicate(0.0, days), List.duplicate(0.0, days)}

    {stacked, _acc} =
      Enum.flat_map_reduce(series, start, fn {key, values}, {pos, neg} ->
        up = Enum.map(values, &max(&1, 0.0))
        down = Enum.map(values, &min(&1, 0.0))
        pos_after = Enum.zip_with(pos, up, &(&1 + &2))
        neg_after = Enum.zip_with(neg, down, &(&1 + &2))

        positive = {key, :positive, Enum.zip(pos, pos_after)}
        negative = {key, :negative, Enum.zip(neg_after, neg)}

        parts =
          cond do
            Enum.all?(values, &(&1 >= 0)) -> [positive]
            Enum.all?(values, &(&1 <= 0)) -> [negative]
            true -> [positive, negative]
          end

        {parts, {pos_after, neg_after}}
      end)

    stacked
  end

  defp range(stacked) do
    edges = Enum.flat_map(stacked, fn {_key, _part, edges} -> edges end)
    lo = edges |> Enum.map(&elem(&1, 0)) |> Enum.min(fn -> 0.0 end) |> min(0.0)
    top = edges |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0.0 end) |> max(0.0)

    hi = if top == lo, do: lo + 1.0, else: top + (top - lo) * 0.05

    {lo, hi}
  end

  defp path([{x, y} | rest]) do
    IO.iodata_to_binary([
      "M",
      coord(x),
      ",",
      coord(y),
      Enum.map(rest, fn {x, y} -> [" L", coord(x), ",", coord(y)] end),
      " Z"
    ])
  end

  defp coord(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)
end
