defmodule PortfolixirWeb.Portfolio.StackedChart do
  @moduledoc """
  The stacked value chart on Wealth → Holdings → Performance (I23, FR-53;
  idea board `ux-design-2026-11-06-ideas-i23-i24/01-stacked-chart`, variant
  A; Sprint 27 plan D-4, D-5), with the filter of FR-56 (Sprint 28 S2,
  board `ux-design-2026-11-08-sprint28/02-stack-filter`).

  The anatomy (DESIGN.md → Amendment 2026-11-07 → the stacked chart):

    * **the bar** (`bar/1`) above the chart, in both series (FR-57): the
      breadcrumb on a line of its own, the filter's path through its tree,
      then the controls from the bar's left edge: the level (Total ·
      Categories · Securities), the classification and the sort (Size ·
      Change). At Total, where there is no path, there is no breadcrumb, and
      a switch of the level leaves its control where it was (the owner's
      report of 2026-11-11). Every choice is a link that patches the address,
      so a link handed over reopens the same stack; a level keeps the
      filter. At the level Total without a filter the bar holds the level
      alone, and the chart under it is today's value chart, unchanged. The
      bar is the first user of "labelled controls start on one edge"
      (DESIGN.md, amendment of 2026-11-08), built as the shared
      `PortfolixirWeb.ControlBar.bar/1` (issue 1435): a container query
      turns it into a label column at 760 px of its width, or labels above
      their controls at 330 px;
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

  **The TTWROR series** (`lines/1`; FR-57, Sprint 28 S4, board
  `ux-design-2026-11-08-sprint28/03-ttwror-levels`): the same bar, level and
  filter, the bands drawn as one line each, their own TTWROR, the view's or
  the filter's line bold and first in a legend of percentages only; a band
  whose line starts inside the window starts with a dot. No amount, so the
  privacy mode leaves it as it is.

  **The privacy mode** (I22; #1433, plan amendment D-A2, board 06): the
  stack keeps its shape, the same picture as without the mode, and only
  its labels change: each axis tick reads in percent of the bands' total
  on the window's first day (100 %), the filtered stack's total under a
  filter, as Sprint 26's rule reads every axis in a currency. Where that
  total is not above zero (a buy booked before its money), the axis indexes
  to the first day it is, and says so behind the ⓘ; where no day is, the
  ticks carry no label. The axis reads round steps in its own unit (an
  amount, or a whole percent in the mode), 0 among them whenever the stack
  reaches below zero (the closing act's design critic, D2); the plot's
  range is the data's in either mode. The legend keeps share (the API's net share) and
  change and drops the value, the bands' tooltips name no amount, and no
  attribute carries one. Sprint 27's 100 % stack retired with D-A2.

  The geometry is computed here on the server from the `Decimal` values;
  floats exist only as coordinates and are never stored.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.ControlBar
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
    <ControlBar.bar data-role="stack-bar">
      <:head :if={@crumbs != []}>
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
      </:head>
      <:group label={gettext("Level")} label_id="stack-level-label">
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
      </:group>
      <:group
        :if={@stack.level == :category or (@stack.level == :security and not is_nil(@stack.category))}
        label={gettext("Classification")}
        for="stack-classification"
        form={[id: "stack-classification-form", "phx-change": "select_stack_classification"]}
      >
        <select id="stack-classification" name="tree">
          <option
            :for={classification <- @classifications}
            value={classification.id}
            selected={classification.id == @classification_id}
          >
            <%= ClassificationName.display(classification) %>
          </option>
        </select>
      </:group>
      <:group :if={@stack.level != :total} label={gettext("Sort")} label_id="stack-sort-label">
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
      </:group>
    </ControlBar.bar>
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
    index = if privacy?, do: index_basis(assigns.result)
    geometry = geometry(assigns.result, index)
    bands = assigns.result.bands

    assigns =
      assign(assigns,
        privacy?: privacy?,
        index: index,
        geometry: geometry,
        legend: legend(bands, geometry),
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
                  :for={{value, y} <- @geometry.ticks}
                  :if={not @privacy? or @index != :none}
                  class={["chart-axis-y", y - @geometry.plot_top < 12 && "is-top"]}
                  x={@plot_left - 6}
                  y={coord(y)}
                  text-anchor="end"
                  dominant-baseline="central"
                >
                  <%= tick_label(value, @index, @geometry.places) %>
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
                  <%= legend_head(@result) %>
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

  # --- Sprint 28 S4 begin ---
  # -- the TTWROR lines (FR-57) ------------------------------------------------------

  attr(:result, :map, required: true)
  attr(:colors, :map, required: true)
  attr(:drill_paths, :map, required: true)
  attr(:benchmark_note, :string, default: nil)

  @doc """
  The TTWROR series at a level or under a filter (FR-57, I28; board
  `ux-design-2026-11-08-sprint28/03-ttwror-levels`): one line per band, each
  band's own TTWROR (`Bands`' `scale: :ttwror`), not stacked, since returns
  do not add up; the parent's line (the view's own, or the filter's) bold,
  drawn last so it lies on top. A band whose line starts after the window's
  first day starts at 0 % with a dot. The legend lists the bold line first,
  then the lines in the answer's order, each with its TTWROR only: no
  amount, so the privacy mode changes nothing here. A category's line and
  legend row set the filter on a click and keep the level, as the bands do.
  """
  def lines(assigns) do
    result = assigns.result
    parent = result.parent
    others = Enum.reject(result.bands, &(parent && &1.key == parent.key))
    legend = if parent, do: [parent | others], else: others
    geometry = lines_geometry(result.dates, legend)

    assigns =
      assign(assigns,
        parent: parent,
        legend: legend,
        # The thin lines first, the bold one last, on top.
        drawn: Enum.reverse(legend),
        geometry: geometry,
        width: @width,
        height: @height,
        plot_left: @padding_left,
        plot_right: @width - @padding_right
      )

    ~H"""
    <figure
      id="performance-figure-lines"
      class="perf-figure stack-figure lines-figure"
      data-level={@result.level}
      data-scale="ttwror"
    >
      <%= if @legend == [] do %>
        <p class="hint" data-role="stack-empty"><%= gettext("No values in this period.") %></p>
      <% else %>
        <div class="stack-figure__body">
          <div class="stack-figure__chart" id="lines-figure-chart" phx-hook="ChartScale">
            <svg
              class="stack-chart lines-chart"
              role="img"
              aria-label={lines_aria_label(@result)}
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
              <line
                class="chart-zeroline"
                x1={@plot_left}
                y1={coord(@geometry.zero_y)}
                x2={@plot_right}
                y2={coord(@geometry.zero_y)}
              />
              <g
                :for={line <- @drawn}
                class={[
                  "stack-line",
                  "stack-line--#{kind_class(line.kind)}",
                  bold?(line, @parent) && "stack-line--bold"
                ]}
                data-band={line.key}
                phx-click={if Map.has_key?(@drill_paths, line.key), do: "drill_stack"}
                phx-value-category={if Map.has_key?(@drill_paths, line.key), do: filter_value(line)}
              >
                <title><%= line_title(line, @parent, @geometry.starts) %></title>
                <path class="stack-line__hit" d={Map.fetch!(@geometry.paths, line.key)} fill="none" />
                <path
                  class="stack-line__stroke"
                  d={Map.fetch!(@geometry.paths, line.key)}
                  fill="none"
                  stroke={line_stroke(line, @parent, @colors)}
                />
              </g>
              <%= for line <- @drawn, start = Map.get(@geometry.starts, line.key) do %>
                <circle
                  class="stack-line-start"
                  data-band={line.key}
                  cx={coord(start.x)}
                  cy={coord(start.y)}
                  r={if bold?(line, @parent), do: "4", else: "3.2"}
                  fill={line_stroke(line, @parent, @colors)}
                />
              <% end %>
              <g class="chart-axis-labels">
                <text
                  :for={{{value, y}, index} <- Enum.with_index(@geometry.ticks)}
                  class={["chart-axis-y", index == length(@geometry.ticks) - 1 && "is-top"]}
                  x={@plot_left - 6}
                  y={coord(y)}
                  text-anchor="end"
                  dominant-baseline="central"
                >
                  <%= percent_tick(value, @geometry.places) %>
                </text>
                <text class="chart-axis-x" x={@plot_left} y={@height - 6} text-anchor="start">
                  <%= Format.date(List.first(@result.dates)) %>
                </text>
                <text class="chart-axis-x" x={@plot_right} y={@height - 6} text-anchor="end">
                  <%= Format.date(List.last(@result.dates)) %>
                </text>
              </g>
            </svg>
          </div>
          <table
            id="lines-legend"
            class="stack-legend lines-legend"
            data-role="lines-legend"
            data-date={Date.to_iso8601(@result.end_date)}
          >
            <caption class="sr-only">
              <%= gettext("Each line's TTWROR on %{date}, the bold line first",
                date: Format.date(@result.end_date)
              ) %>
            </caption>
            <thead>
              <tr>
                <th scope="col">
                  <%= legend_head(@result) %>
                </th>
                <th scope="col" class="num"><%= gettext("TTWROR") %></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={line <- @legend}
                data-band={line.key}
                class={bold?(line, @parent) && "lines-legend__parent"}
              >
                <td class="stack-legend__name lines-legend__name">
                  <span
                    class={["stack-swatch", bold?(line, @parent) && "lines-swatch--bold"]}
                    style={"background: #{line_stroke(line, @parent, @colors)}"}
                    aria-hidden="true"
                  >
                  </span>
                  <%= cond do %>
                    <% bold?(line, @parent) -> %>
                      <%= gettext("%{name} (bold)", name: line_name(line)) %>
                    <% path = Map.get(@drill_paths, line.key) -> %>
                      <.link patch={path} class="stack-legend__drill"><%= line_name(line) %></.link>
                    <% true -> %>
                      <%= line_name(line) %>
                  <% end %>
                  <%!-- A late band's first day, the dot's date (board 03 ②). --%>
                  <%= if start = Map.get(@geometry.starts, line.key) do %>
                    <span class="lines-legend__since">(<%= gettext("from %{date}", date: Format.date(start.date)) %>)</span>
                  <% end %>
                  <span
                    :if={not bold?(line, @parent) and Map.has_key?(@drill_paths, line.key)}
                    class="stack-legend__chevron"
                    aria-hidden="true"
                  >›</span>
                </td>
                <td class={["num", sign_class(line.ttwror)]} data-role="line-ttwror">
                  <%= change(line.ttwror) %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <%!-- I1 (#1351; #1366, amendment D-A4): one line, what the lines
             show, the window and when they were computed; the method in
             the ⓘ at its end. --%>
        <div class="hint stack-basis" data-role="stack-basis">
          <span data-role="stack-basis-line">
            <%= lines_shows(@result) %> · <%= Format.date(@result.start_date) %> – <%= Format.date(@result.end_date) %><%= if @result.as_of do %> · <%= gettext("computed %{at}", at: Format.utc_instant(@result.as_of)) %><% end %>
          </span>
          <AppShell.section_info>
            <:line :for={line <- lines_method(@result, @drill_paths != %{})}><%= line %></:line>
            <:line :if={@benchmark_note}><span data-role="benchmark-lines-hint"><%= @benchmark_note %></span></:line>
          </AppShell.section_info>
        </div>
      <% end %>
    </figure>
    """
  end

  defp bold?(line, parent), do: parent != nil and line.key == parent.key

  # The view's own line is named for the view; every other one as its band.
  defp line_name(%{kind: :total}), do: gettext("View")
  defp line_name(line), do: band_name(line)

  # The bold line in the text colour, every other in its band's colour.
  defp line_stroke(line, parent, colors) do
    if bold?(line, parent), do: "currentColor", else: Map.get(colors, line.key) || "currentColor"
  end

  # The tooltip: the name and the TTWROR, and where a line starts late, its
  # first day. A percentage, never an amount.
  defp line_title(line, parent, starts) do
    name =
      if bold?(line, parent),
        do: gettext("%{name} (bold)", name: line_name(line)),
        else: line_name(line)

    since =
      case Map.get(starts, line.key) do
        %{date: date} -> " · " <> gettext("from %{date}", date: Format.date(date))
        nil -> ""
      end

    "#{name} · #{change(line.ttwror)}#{since}"
  end

  defp lines_aria_label(%{level: :security}), do: gettext("TTWROR per security over time")
  defp lines_aria_label(_result), do: gettext("TTWROR per category over time")

  # The visible half of the basis: what the lines show, the filter named.
  defp lines_shows(%{category_id: :unclassified} = result),
    do: gettext("TTWROR of what “%{tree}” files nowhere", tree: tree_name(result.classification))

  defp lines_shows(%{level: :security, category: %{name: name}}),
    do: gettext("TTWROR per security of “%{category}”", category: name)

  defp lines_shows(%{level: :category, category: %{name: name}} = result) do
    if divided?(result),
      do: gettext("TTWROR of “%{category}” by sub-category", category: name),
      else: gettext("TTWROR of “%{category}”", category: name)
  end

  defp lines_shows(%{category: %{name: name}}),
    do: gettext("TTWROR of “%{category}”", category: name)

  defp lines_shows(%{level: :category} = result),
    do: gettext("TTWROR per category of “%{tree}”", tree: tree_name(result.classification))

  defp lines_shows(_result), do: gettext("TTWROR per security")

  # The method behind the ⓘ, one short sentence per line (I1): what a line
  # is, its flows, what it leaves out, the start rule, the selection, the
  # order, the bold line and what a click does.
  defp lines_method(result, filter_links?) do
    [
      gettext(
        "Each band's own time-weighted return over the window (TTWROR), not stacked: returns do not add up."
      ),
      gettext(
        "A band's flows are its buys, sells and deliveries: an inflow at the day's start, an outflow at its end."
      ),
      gettext(
        "Dividends and interest are no flow and in no line: they go to the cash, so a line is the return of the band's market value."
      ),
      gettext(
        "A band that gains its first value inside the window starts at 0 % on that day, at a dot."
      ),
      gettext(
        "A day on which a band opens at or below zero, a short, adds no return: its line waits until the band is above zero again."
      ),
      lines_selection(result),
      lines_order(result.sort),
      lines_bold(result),
      lines_view_flows(result),
      filter_links? &&
        gettext(
          "A click on a category filters the lines to it and keeps the level; the path above leads back."
        )
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp lines_selection(%{category_id: nil}),
    do:
      gettext(
        "At most eight lines, the largest by value at the window's end; none for the cash or the unassigned rest."
      )

  defp lines_selection(_filtered),
    do: gettext("At most eight lines, the largest by value at the window's end.")

  defp lines_order(:change),
    do: gettext("The legend lists the bold line first, then the lines by TTWROR, largest first.")

  defp lines_order(_size),
    do:
      gettext(
        "The legend lists the bold line first, then the lines by value at the window's end."
      )

  # The view's line is the walk's, which counts every flow at the day's
  # start; a band's counts an outflow at its end (the closing act's money
  # lens, ML2: the walk stays as it is, ADR-0010/0051).
  defp lines_view_flows(%{parent: %{kind: :total}}),
    do:
      gettext(
        "The view's line counts every flow at the day's start; the bands count an outflow at the day's end, so a band that holds the whole view can differ from it on a day with a sale."
      )

  defp lines_view_flows(_result), do: nil

  defp lines_bold(%{parent: nil}), do: nil

  defp lines_bold(%{parent: %{kind: :total}}),
    do: gettext("The bold line is the view's own TTWROR.")

  defp lines_bold(%{parent: parent}),
    do: gettext("The bold line is “%{name}”, the filter's.", name: band_name(parent))

  # A tick in percent: the sign, the step's places and „%“.
  defp percent_tick(value, places),
    do: Format.plain_signed_decimal(Decimal.from_float(value * 1.0), places) <> "%"

  # The lines' geometry: a percent axis with round steps that holds every
  # point and 0 %; per line its path, broken where it has no point (before
  # a late start, after a sale), through the sampled days and each run's
  # first and last day, so a start and the window's last point are always
  # drawn; and the start of each line that begins after the window's first
  # day, a dot at 0 %.
  defp lines_geometry(dates, lines) do
    count = length(dates)
    sampled = count |> sample() |> MapSet.new()

    runs =
      Map.new(lines, fn line ->
        {line.key, line.returns |> runs() |> Enum.map(&thin(&1, sampled))}
      end)

    values = for {_key, rs} <- runs, run <- rs, {_i, v} <- run, do: v
    {lo, hi, step} = percent_axis([0.0 | values])

    plot_top = @padding_top * 1.0
    plot_bottom = (@height - @padding_bottom) * 1.0
    plot_left = @padding_left * 1.0
    plot_right = (@width - @padding_right) * 1.0

    x = fn i ->
      if count <= 1, do: plot_left, else: plot_left + (plot_right - plot_left) * i / (count - 1)
    end

    y = fn v -> plot_bottom - (plot_bottom - plot_top) * (v - lo) / (hi - lo) end

    paths =
      Map.new(runs, fn {key, rs} ->
        {key,
         Enum.map_join(rs, " ", fn [{i, v} | rest] ->
           IO.iodata_to_binary([
             "M",
             coord(x.(i)),
             ",",
             coord(y.(v)),
             Enum.map(rest, fn {j, w} -> [" L", coord(x.(j)), ",", coord(y.(w))] end)
           ])
         end)}
      end)

    starts =
      for line <- lines,
          index = Enum.find_index(line.returns, &(not is_nil(&1))),
          index != nil and index > 0,
          into: %{} do
        value = line.returns |> Enum.at(index) |> Decimal.mult(100) |> Decimal.to_float()
        {line.key, %{date: Enum.at(dates, index), x: x.(index), y: y.(value)}}
      end

    ticks =
      Stream.iterate(lo, &(&1 + step))
      |> Enum.take_while(&(&1 <= hi + step / 1000))
      |> Enum.map(&{&1, y.(&1)})

    %{
      points: MapSet.size(sampled),
      plot_top: plot_top,
      paths: paths,
      starts: starts,
      zero_y: y.(0.0),
      ticks: ticks,
      places: places(step)
    }
  end

  # The runs of consecutive days on which a line has a point, each a list
  # of `{index, percent}`.
  defp runs(returns) do
    returns
    |> Enum.with_index()
    |> Enum.chunk_by(fn {value, _i} -> is_nil(value) end)
    |> Enum.reject(fn [{value, _i} | _rest] -> is_nil(value) end)
    |> Enum.map(fn run ->
      Enum.map(run, fn {value, i} -> {i, value |> Decimal.mult(100) |> Decimal.to_float()} end)
    end)
  end

  # A run through the sampled days, its first and last day kept.
  defp thin(run, sampled) do
    {first, _} = List.first(run)
    {last, _} = List.last(run)
    Enum.filter(run, fn {i, _v} -> i == first or i == last or MapSet.member?(sampled, i) end)
  end

  # The axis: a round step (1, 2, 2.5 or 5 times a power of ten) giving
  # about five intervals, its ends on whole steps around every value.
  defp percent_axis(values) do
    lo = Enum.min(values)
    hi = Enum.max(values)
    span = if hi - lo < 1.0e-9, do: 1.0, else: hi - lo
    step = round_step(span / 5)
    bottom = Float.floor(lo / step) * step
    top = Float.ceil(hi / step) * step
    top = if top - bottom < step / 2, do: bottom + step, else: top
    {bottom, top, step}
  end

  # The smallest round step, 1, 2, 2.5 or 5 times a power of ten, at
  # least `raw`: the lines' axis and the stack's (the closing act's design
  # critic, D2) read in the same steps.
  defp round_step(raw) do
    magnitude = :math.pow(10, Float.floor(:math.log10(raw)))
    Enum.find([1, 2, 2.5, 5, 10], &(&1 * magnitude >= raw)) * magnitude
  end

  defp places(step) do
    cond do
      step >= 1 and Float.round(step * 1.0) == step -> 0
      Float.round(step * 10.0) == step * 10 -> 1
      true -> 2
    end
  end

  # --- Sprint 28 S4 end ---

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

  # The legend's head (D3; boards 02 ② and 03 ②): under a category filter
  # at „Kategorien“ its rows are the category's sub-categories (and its
  # direct band), unless the category holds none and its own band is the
  # only row.
  defp legend_head(%{level: :security}), do: gettext("Security")

  defp legend_head(%{level: :category, category: %{id: id}, bands: bands})
       when bands != [] do
    if Enum.all?(bands, &(&1.key == "category:#{id}")),
      do: gettext("Category"),
      else: gettext("Subcategory")
  end

  defp legend_head(_result), do: gettext("Category")

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
  defp tick_label(value, {_date, total, _first?}, _places) do
    percent = round(value / Decimal.to_float(total) * 100)
    Format.plain_decimal(Decimal.new(percent), 0) <> "%"
  end

  defp tick_label(value, nil, _places) when value == 0, do: Format.decimal(Decimal.new(0), 0)

  defp tick_label(value, nil, places),
    do: Format.decimal(Decimal.from_float(value * 1.0), places)

  # -- geometry ---------------------------------------------------------------------

  # The drawn days (at most @max_points, the window's last day always among
  # them), each band's areas, and the axis. A band draws one area above the
  # zero line and, when it is negative on a day, a second one below it, so
  # the two never cross the bands between (#1426); a band that changes sign
  # inside the window is drawn first, next to the zero line, and its two
  # areas meet there. „Other“ stays on top whatever its sign (D4).
  defp geometry(%{bands: []}, _index), do: nil

  defp geometry(result, index) do
    indices = sample(length(result.dates))
    dates = Enum.map(indices, &Enum.at(result.dates, &1))

    series =
      Enum.map(result.bands, fn band ->
        values = List.to_tuple(band.values)
        {band.key, Enum.map(indices, &to_float(elem(values, &1)))}
      end)

    kinds = Map.new(result.bands, &{&1.key, &1.kind})
    drawn = zero_first(series, kinds)
    stacked = stack(drawn)

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

    {ticks, step} = round_ticks(lo, hi, unit(index, lo, hi))
    ticks = Enum.map(ticks, &{&1, y.(&1)})

    %{
      points: n,
      plot_top: plot_top,
      order: Enum.map(drawn, &elem(&1, 0)),
      parts: parts,
      zero_y: if(lo < 0, do: y.(0.0)),
      ticks: ticks,
      places: places(step),
      first_date: List.first(dates),
      last_date: List.last(dates)
    }
  end

  # The axis in round steps (D2): the ticks are the multiples of a round
  # step in the axis's own unit that lie in the plot, 0 among them whenever
  # the plot reaches below zero, so the zero line is labelled; the plot's
  # range stays the data's, so the picture is the same in either mode. The
  # unit is one currency unit, or in the privacy mode one percent of the
  # index's total (whole percents only), or one percent of the range when
  # no total is above zero (no label is drawn then, and no tick sits on a
  # round amount). `{tick values, step in the unit}`.
  defp round_ticks(lo, hi, {unit, min_step}) do
    step = max(round_step((hi - lo) / unit / 5), min_step)
    first = Float.ceil(lo / unit / step - 1.0e-9)
    last = Float.floor(hi / unit / step + 1.0e-9)
    ticks = for k <- trunc(first)..trunc(last)//1, do: k * step * unit
    {ticks, step}
  end

  defp unit(nil, _lo, _hi), do: {1.0, 0.0}
  defp unit({_date, total, _first?}, _lo, _hi), do: {Decimal.to_float(total) / 100, 1.0}
  defp unit(:none, lo, hi), do: {(hi - lo) / 100, 1.0}

  # The legend reads like the stack, the top band first: the drawn order
  # reversed, so a band that changes sign, drawn first at the zero line, is
  # its last row (the closing act's design critic, D1).
  defp legend(_bands, nil), do: []

  defp legend(bands, %{order: order}) do
    by_key = Map.new(bands, &{&1.key, &1})
    order |> Enum.reverse() |> Enum.map(&Map.fetch!(by_key, &1))
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
