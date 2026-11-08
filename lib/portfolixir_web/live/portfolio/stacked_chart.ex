defmodule PortfolixirWeb.Portfolio.StackedChart do
  @moduledoc """
  The stacked value chart on Wealth → Holdings → Performance (I23, FR-53;
  idea board `ux-design-2026-11-06-ideas-i23-i24/01-stacked-chart`, variant
  A; Sprint 27 plan D-4, D-5).

  The anatomy (DESIGN.md → Amendment 2026-11-07 → the stacked chart):

    * **the bar** (`bar/1`) above the chart, in the value series only: the
      breadcrumb on the left, then the level (Total · Categories ·
      Securities), the classification and the sort (Size · Change). Every
      choice is a link that patches the address, so a link handed over
      reopens the same stack. At the level Total the bar holds the level
      alone, and the chart under it is today's value chart, unchanged;
    * **the bands** (`figure/1`): `Portfolixir.Portfolios.Performance.Bands`'
      daily values, the first band of its order at the bottom, the largest
      by the chosen sort. Values below zero (an overdrawn cash account)
      stack downwards from the zero line, so the bands still add up to the
      day's value. A category's band patches to its securities on a click;
    * **the legend as a table**, reading like the stack, the top band first:
      the swatch and the name (a category's name is the drill link), the
      value on the window's last day, its share and its change without
      flows;
    * **the basis line**: what a band is, the order, the merge into "Other"
      when it happened; the window is the section's basis line under it.

  **The privacy mode** (I22): the stack is drawn as a 100 % stack by itself,
  each day's bands over the sum of that day's positive bands, so the axis
  reads 0 % to 100 %; the legend keeps share and change and drops the
  value, the bands' tooltips name no amount, and no attribute carries one.
  The legend's share is taken on the picture's own basis, the last day's
  value over that day's positive bands, so a band that fills the stack
  reads 100 % beside it where the API's net share reads more when a band is
  negative (the closing act's money lens, M3).

  The geometry is computed here on the server from the `Decimal` values;
  floats exist only as coordinates and are never stored.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

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
  breadcrumb as `{label, path | nil}`, the last one the place shown.
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
          :if={@stack.level == :category or not is_nil(@stack.category)}
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

  @doc """
  The stacked bands and their legend. `result` is a `Bands` answer,
  `colors` each band's colour by key (`:other` for the neutral token), and
  `drill_paths` the address a category's band opens, by key.
  """
  def figure(assigns) do
    privacy? = PrivacyMode.on?()
    geometry = geometry(assigns.result, privacy?)
    bands = shown_shares(assigns.result.bands, privacy?)

    assigns =
      assign(assigns,
        privacy?: privacy?,
        geometry: geometry,
        legend: Enum.reverse(bands),
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
                :for={band <- Enum.reverse(@legend)}
                class={["stack-band", band_class(band), Map.get(@colors, band.key) == :other && "stack-band--other"]}
                d={Map.fetch!(@geometry.paths, band.key)}
                fill={fill(Map.get(@colors, band.key))}
                data-band={band.key}
                phx-click={if Map.has_key?(@drill_paths, band.key), do: "drill_stack"}
                phx-value-category={if Map.has_key?(@drill_paths, band.key), do: band.id}
              >
                <title><%= band_title(band, @privacy?) %></title>
              </path>
              <g class="chart-axis-labels">
                <text
                  :for={{{value, y}, index} <- Enum.with_index(@geometry.ticks)}
                  class={["chart-axis-y", index == length(@geometry.ticks) - 1 && "is-top"]}
                  x={@plot_left - 6}
                  y={coord(y)}
                  text-anchor="end"
                  dominant-baseline="central"
                >
                  <%= tick_label(value, @privacy?) %>
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
                  <%= if @result.level == :category, do: gettext("Category"), else: gettext("Security") %>
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
        <p class="hint" data-role="stack-basis">
          <%= basis(@result, @privacy?) %>
          <%= gettext("Change without deposits and withdrawals.") %>
          <%= order_text(@result.sort) %>
          <%= if @other?,
            do:
              gettext(
                "Above eight bands the smallest merge into “Other”, which always sits on top."
              ) %>
        </p>
      <% end %>
    </figure>
    """
  end

  # -- names, figures and words ----------------------------------------------------

  # The share the legend shows: the API's net share, or in the privacy mode
  # the share the 100 % stack draws, the last day's value over that day's
  # positive bands (M3), so legend and picture agree when a band is negative.
  defp shown_shares(bands, false), do: bands

  defp shown_shares(bands, true) do
    positive =
      bands
      |> Enum.map(& &1.end_value)
      |> Enum.filter(&Decimal.gt?(&1, 0))
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    Enum.map(bands, fn band ->
      share = if Decimal.gt?(positive, 0), do: Decimal.div(band.end_value, positive)
      %{band | share: share}
    end)
  end

  @doc "A band's name in the page's language: the fixed bands translated."
  def band_name(%{kind: :cash}), do: gettext("Cash")
  def band_name(%{kind: :unclassified}), do: gettext("Unassigned")
  def band_name(%{kind: :other}), do: pgettext("stack band", "Other")
  def band_name(%{kind: :total}), do: gettext("Total")
  def band_name(%{name: name}), do: name

  defp band_class(%{kind: kind}), do: "stack-band--#{kind_class(kind)}"

  defp kind_class(:category), do: "category"
  defp kind_class(:security), do: "security"
  defp kind_class(:cash), do: "cash"
  defp kind_class(:unclassified), do: "unclassified"
  defp kind_class(:other), do: "other"
  defp kind_class(:total), do: "total"

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

  defp aria_label(%{level: :category}), do: gettext("Value by category over time")
  defp aria_label(_result), do: gettext("Value by security over time")

  defp basis(%{level: :category} = result, privacy?) do
    tree = tree_name(result.classification)

    if privacy?,
      do:
        gettext(
          "Each category's share of the day's value, classification “%{tree}”; cash and the unclassified rest are bands of their own.",
          tree: tree
        ),
      else:
        gettext(
          "Market value per category of “%{tree}” at each day's close, in %{currency}; cash and the unclassified rest are bands of their own.",
          tree: tree,
          currency: result.base_currency
        )
  end

  defp basis(%{category: %{name: name}} = result, privacy?) do
    if privacy?,
      do: gettext("Each security's share of the value of “%{category}” per day.", category: name),
      else:
        gettext(
          "Market value per security of “%{category}” at each day's close, in %{currency}; the share is of the category.",
          category: name,
          currency: result.base_currency
        )
  end

  defp basis(result, privacy?) do
    if privacy?,
      do: gettext("Each security's share of the day's value, and the cash's."),
      else:
        gettext("Market value per security at each day's close, in %{currency}, and the cash.",
          currency: result.base_currency
        )
  end

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

  # A tick of the 100 % stack reads as a whole percent; a tick in money as
  # the shared chart's axis prints it.
  defp tick_label(value, true), do: "#{round(value * 100)}%"

  defp tick_label(value, false) when value == 0, do: Format.decimal(Decimal.new(0), 0)

  defp tick_label(value, false) do
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
  # them), each band's area as one path, and the axis.
  defp geometry(%{bands: []}, _privacy?), do: nil

  defp geometry(result, privacy?) do
    indices = sample(length(result.dates))
    dates = Enum.map(indices, &Enum.at(result.dates, &1))

    series =
      Enum.map(result.bands, fn band ->
        values = List.to_tuple(band.values)
        {band.key, Enum.map(indices, &to_float(elem(values, &1)))}
      end)

    series = if privacy?, do: shares(series), else: series
    stacked = stack(series)

    {lo, hi} = range(stacked, privacy?)
    plot_top = @padding_top * 1.0
    plot_bottom = (@height - @padding_bottom) * 1.0
    plot_left = @padding_left * 1.0
    plot_right = (@width - @padding_right) * 1.0
    n = length(indices)

    x = fn i ->
      if n == 1, do: plot_left, else: plot_left + (plot_right - plot_left) * i / (n - 1)
    end

    y = fn v -> plot_bottom - (plot_bottom - plot_top) * (v - lo) / (hi - lo) end

    paths =
      Map.new(stacked, fn {key, edges} ->
        upper = edges |> Enum.with_index() |> Enum.map(fn {{_l, u}, i} -> {x.(i), y.(u)} end)

        lower =
          edges
          |> Enum.with_index()
          |> Enum.map(fn {{l, _u}, i} -> {x.(i), y.(l)} end)
          |> Enum.reverse()

        {key, path(upper ++ lower)}
      end)

    ticks =
      for i <- 0..4 do
        value = lo + (hi - lo) * i / 4
        {value, y.(value)}
      end

    %{
      points: n,
      plot_top: plot_top,
      paths: paths,
      ticks: ticks,
      first_date: List.first(dates),
      last_date: List.last(dates)
    }
  end

  defp sample(count) when count <= @max_points, do: Enum.to_list(0..(count - 1)//1)

  defp sample(count) do
    step = count |> Kernel./(@max_points) |> Float.ceil() |> trunc()
    sampled = Enum.take_every(0..(count - 1), step)
    if List.last(sampled) == count - 1, do: sampled, else: sampled ++ [count - 1]
  end

  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)

  # The 100 % stack: each day's value over the sum of that day's positive
  # values, so the positive bands fill 0 to 1.
  defp shares(series) do
    totals =
      series
      |> Enum.map(fn {_key, values} -> values end)
      |> Enum.zip_with(fn day -> day |> Enum.filter(&(&1 > 0)) |> Enum.sum() end)

    Enum.map(series, fn {key, values} ->
      {key,
       Enum.zip_with(values, totals, fn value, total ->
         if total > 0, do: value / total, else: 0.0
       end)}
    end)
  end

  # Each band's lower and upper edge per day, the first band at the bottom:
  # a positive value stacks up from the positives below it, a negative one
  # down from the negatives (a diverging stack), so each day's bands still
  # add up to its value.
  defp stack(series) do
    days = series |> hd() |> elem(1) |> length()
    start = List.duplicate({0.0, 0.0}, days)

    {stacked, _acc} =
      Enum.map_reduce(series, start, fn {key, values}, acc ->
        {edges, acc} =
          values
          |> Enum.zip(acc)
          |> Enum.map(fn
            {value, {pos, neg}} when value >= 0 -> {{pos, pos + value}, {pos + value, neg}}
            {value, {pos, neg}} -> {{neg + value, neg}, {pos, neg + value}}
          end)
          |> Enum.unzip()

        {{key, edges}, acc}
      end)

    stacked
  end

  defp range(stacked, privacy?) do
    edges = Enum.flat_map(stacked, fn {_key, edges} -> edges end)
    lo = edges |> Enum.map(&elem(&1, 0)) |> Enum.min(fn -> 0.0 end) |> min(0.0)
    top = edges |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0.0 end) |> max(0.0)

    hi =
      cond do
        privacy? -> 1.0
        top == lo -> lo + 1.0
        true -> top + (top - lo) * 0.05
      end

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
