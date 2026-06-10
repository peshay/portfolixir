defmodule PortfolixirWeb.PortfolioLive do
  @moduledoc """
  Portfolio overview: live value and cash quote, TTWROR over selectable
  periods, the value-weighted allocation donut with SOLL/IST drift, and a
  set-balance form for cash snapshots (ADR-0009/0010). All figures come from
  the same derived reads the API exposes.

  The heavy reads run as async assigns after the socket connects: the page
  paints immediately and each section fills in when its data arrives. The
  daily performance walk is computed once (`Performance.analysis/2`) and
  cached on the socket — switching periods is a pure re-chain of that series,
  so the buttons respond instantly. The chart is downsampled to a bounded
  number of points before it hits the DOM.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @unassigned_color "#9ca3af"
  @fallback_color "#6b7280"
  @chart_max_points 400
  @unpriced_names_shown 6

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, "/portfolio")
      |> assign(:error, nil)
      |> assign(:success, nil)

    case Portfolios.first_portfolio() do
      nil ->
        {:ok, assign(socket, :portfolio, nil)}

      portfolio ->
        Classifications.ensure_builtins()
        classifications = Classifications.list_classifications()

        socket =
          socket
          |> assign(:portfolio, portfolio)
          |> assign(:classifications, classifications)
          |> assign(:period, "max")
          |> assign(:classification_id, default_classification_id(classifications))
          |> assign(:valuation, nil)
          |> assign(:allocation, nil)
          |> assign(:analysis, nil)
          |> assign(:performance, nil)
          |> assign(:selected_segment, nil)
          |> start_loading()

        {:ok, socket}
    end
  end

  # The dead render ships skeletons only; the expensive reads start once the
  # socket is connected, so the page paints fast and is computed exactly once.
  defp start_loading(socket) do
    if connected?(socket) do
      socket
      |> load_overview()
      |> load_performance()
    else
      socket
    end
  end

  defp load_overview(socket) do
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id

    start_async(socket, :overview, fn ->
      valuation = Valuation.for_portfolio(portfolio_id)
      {:ok, allocation} = Allocation.for_portfolio(portfolio_id, classification_id)
      {valuation, allocation}
    end)
  end

  defp load_allocation(socket) do
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id

    start_async(socket, :allocation, fn ->
      {:ok, allocation} = Allocation.for_portfolio(portfolio_id, classification_id)
      allocation
    end)
  end

  defp load_performance(socket) do
    portfolio_id = socket.assigns.portfolio.id

    start_async(socket, :performance, fn ->
      Performance.analysis(portfolio_id)
    end)
  end

  @impl true
  def handle_async(:overview, {:ok, {valuation, allocation}}, socket) do
    {:noreply, assign(socket, valuation: valuation, allocation: allocation)}
  end

  def handle_async(:allocation, {:ok, allocation}, socket) do
    {:noreply, assign(socket, :allocation, allocation)}
  end

  def handle_async(:performance, {:ok, analysis}, socket) do
    {:ok, performance} = Performance.summarise(analysis, socket.assigns.period)
    {:noreply, assign(socket, analysis: analysis, performance: performance)}
  end

  def handle_async(_name, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :error, gettext("Couldn't load the portfolio figures."))}
  end

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Portfolio")}>
      <div class="workspace-page">
        <section class="workspace-section empty-state">
          <h2><%= gettext("Portfolio") %></h2>
          <p><%= gettext("Create one portfolio first to see value, performance and allocation.") %></p>
          <.link navigate="/portfolios" class="button"><%= gettext("Create one portfolio") %></.link>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={@portfolio.name}
      page_subtitle={gettext("Value, performance and allocation")}
    >
      <div id="portfolio-overview" class="workspace-page portfolio-overview">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <section class="workspace-section grid" aria-label={gettext("Portfolio key figures")}>
          <article id="kpi-total" class="stat">
            <span><%= gettext("Total incl. cash") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_with_cash) %> <%= @valuation.base_currency %>
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
          </article>
          <article id="kpi-securities" class="stat">
            <span><%= gettext("Securities") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_value) %> <%= @valuation.base_currency %>
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
          </article>
          <article id="kpi-cash" class="stat">
            <span><%= gettext("Cash") %> · <%= gettext("cash quote") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_cash) %> <%= @valuation.base_currency %>
              · <%= Format.percent(@valuation.cash_quote) %>%
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
          </article>
          <article id="kpi-ttwror" class="stat">
            <span><%= gettext("TTWROR") %> (<%= period_label(@period) %>)</span>
            <strong :if={@performance}><%= Format.percent(@performance.ttwror) %>%</strong>
            <strong :if={is_nil(@performance)}>…</strong>
          </article>
        </section>

        <.data_quality valuation={@valuation} analysis={@analysis} />

        <section id="portfolio-performance" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Performance") %></h2>
            <div class="period-buttons" role="group" aria-label={gettext("Period")}>
              <%= for period <- Performance.periods() do %>
                <button
                  type="button"
                  class={["button-mini", period == @period && "is-active"]}
                  phx-click="select_period"
                  phx-value-period={period}
                >
                  <%= period_label(period) %>
                </button>
              <% end %>
            </div>
          </header>
          <%= if @performance do %>
            <.performance_chart series={downsample(@performance.series)} />
            <p class="hint">
              <%= gettext("True time-weighted return; deposits and withdrawals are neutralised.") %>
              <%= if @performance.start_date do %>
                <%= @performance.start_date %> – <%= @performance.end_date %>
              <% end %>
            </p>
          <% else %>
            <p class="hint loading-hint" role="status"><%= gettext("Calculating…") %></p>
          <% end %>
        </section>

        <section id="portfolio-allocation" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Allocation") %></h2>
            <form phx-change="select_classification">
              <label class="visually-hidden" for="allocation-classification">
                <%= gettext("Classification") %>
              </label>
              <select id="allocation-classification" name="classification_id">
                <%= for classification <- @classifications do %>
                  <option value={classification.id} selected={classification.id == @classification_id}>
                    <%= classification.name %>
                  </option>
                <% end %>
              </select>
            </form>
          </header>

          <%= if @allocation do %>
            <div class="donut-wrap">
              <div class="sunburst-pane">
                <.allocation_sunburst rings={sunburst_rings(@allocation)} />
                <p :if={@selected_segment} class="sunburst-detail" role="status">
                  <span class="cat-swatch" style={"background:#{@selected_segment.color}"}></span>
                  <strong><%= @selected_segment.name %></strong>
                  · <%= @selected_segment.percent %>%
                  · <%= @selected_segment.value %>
                  <%= if @valuation, do: @valuation.base_currency %>
                </p>
                <p :if={is_nil(@selected_segment)} class="hint">
                  <%= gettext("Tap or hover a slice for details.") %>
                </p>
              </div>
              <ul class="donut-legend">
                <%= for segment <- legend_segments(@allocation) do %>
                  <li>
                    <span class="cat-swatch" style={"background:#{segment.color}"} aria-hidden="true">
                    </span>
                    <span class="legend-name"><%= segment.name %></span>
                    <span class="legend-value"><%= segment.percent %>%</span>
                  </li>
                <% end %>
              </ul>
            </div>

            <table class="drift-table">
              <thead>
                <tr>
                  <th><%= gettext("Category") %></th>
                  <th><%= gettext("Value") %></th>
                  <th><%= gettext("Actual") %></th>
                  <th><%= gettext("Target") %></th>
                  <th><%= gettext("Drift") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @allocation.categories do %>
                  <tr class={row.depth > 0 && "is-child"}>
                    <td style={"padding-left:#{0.75 + row.depth * 1.25}rem"}>
                      <span
                        :if={row.color}
                        class="cat-swatch"
                        style={"background:#{row.color}"}
                        aria-hidden="true"
                      >
                      </span>
                      <%= row.name %>
                    </td>
                    <td><%= Format.money(row.market_value) %></td>
                    <td><%= Format.percent(row.actual_weight) %>%</td>
                    <td>
                      <%= if Decimal.equal?(row.target_weight, 0) do %>
                        —
                      <% else %>
                        <%= Format.percent(row.target_weight) %>%
                      <% end %>
                    </td>
                    <td>
                      <%= if Decimal.equal?(row.target_weight, 0) do %>
                        —
                      <% else %>
                        <%= Format.money(row.drift_value) %>
                        <%= if @valuation, do: @valuation.base_currency %>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
                <%= if @allocation.unassigned do %>
                  <tr class="is-muted">
                    <td><%= gettext("Unassigned") %></td>
                    <td><%= Format.money(@allocation.unassigned.market_value) %></td>
                    <td><%= Format.percent(@allocation.unassigned.actual_weight) %>%</td>
                    <td>—</td>
                    <td>—</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% else %>
            <p class="hint loading-hint" role="status"><%= gettext("Calculating…") %></p>
          <% end %>
        </section>

        <section id="portfolio-cash" class="workspace-section">
          <h2><%= gettext("Cash accounts") %></h2>
          <%= if @valuation do %>
            <table class="cash-table">
              <thead>
                <tr>
                  <th><%= gettext("Account") %></th>
                  <th><%= gettext("Balance") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for cash <- @valuation.cash_balances do %>
                  <tr>
                    <td><%= cash.name %></td>
                    <td><%= Format.money(cash.balance) %> <%= cash.currency %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>

            <form phx-submit="set_balance" class="inline-form balance-form">
              <label>
                <span><%= gettext("Account") %></span>
                <select name="balance[cash_account_id]">
                  <%= for cash <- @valuation.cash_balances do %>
                    <option value={cash.cash_account_id}><%= cash.name %></option>
                  <% end %>
                </select>
              </label>
              <label>
                <span><%= gettext("Date") %></span>
                <input type="date" name="balance[date]" value={Date.to_iso8601(Date.utc_today())} />
              </label>
              <label>
                <span><%= gettext("Balance") %></span>
                <input name="balance[amount]" inputmode="decimal" required placeholder="4250.00" />
              </label>
              <button type="submit"><%= gettext("Set balance") %></button>
            </form>
            <p class="hint">
              <%= gettext("State the balance your bank shows; only later bookings adjust it.") %>
            </p>
          <% else %>
            <p class="hint loading-hint" role="status"><%= gettext("Calculating…") %></p>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  # -- components -------------------------------------------------------------

  # Surfaces why the totals can deviate from the user's expectation: positions
  # valued at a stale trade price, positions with no price at all, and
  # bookings whose dates are implausible (import typos like 0217-12-05).
  defp data_quality(assigns) do
    assigns =
      assigns
      |> assign(:unpriced, unpriced_names(assigns.valuation))
      |> assign(:trade_priced, trade_priced_count(assigns.valuation))
      |> assign(:suspect_dates, suspect_dates(assigns.analysis))

    ~H"""
    <section
      :if={@unpriced != [] or @trade_priced > 0 or @suspect_dates != []}
      id="portfolio-data-quality"
      class="workspace-section data-quality"
    >
      <h2><%= gettext("Data quality") %></h2>
      <ul>
        <li :if={@trade_priced > 0}>
          <%= gettext(
            "%{count} held positions have no current quote and are valued at their last trade price.",
            count: @trade_priced
          ) %>
        </li>
        <li :if={@unpriced != []}>
          <%= gettext("%{count} held positions have no price at all and are missing from the totals:",
            count: length(@unpriced)
          ) %>
          <%= Enum.join(@unpriced, ", ") %>
        </li>
        <li :if={@suspect_dates != []}>
          <%= gettext(
            "Bookings dated before 1970 (%{dates}) are applied on the first plausible day — fix those dates in the source and re-import.",
            dates: Enum.map_join(@suspect_dates, ", ", &Date.to_iso8601/1)
          ) %>
        </li>
      </ul>
    </section>
    """
  end

  defp performance_chart(assigns) do
    assigns = assign(assigns, :zero_y, chart_geometry(assigns.series).zero_y)

    ~H"""
    <svg
      class="perf-chart"
      viewBox="0 0 720 180"
      preserveAspectRatio="none"
      role="img"
      aria-label={gettext("Cumulative TTWROR over time")}
    >
      <line x1="0" y1={@zero_y} x2="720" y2={@zero_y} class="perf-zeroline" />
      <polyline class="perf-line" fill="none" points={performance_points(@series)} />
    </svg>
    """
  end

  # Concentric rings: the innermost is the top-level categories, each further
  # ring breaks one level down (Portfolio Performance's sunburst), with a child
  # arc nested inside its parent's angular span. Segments big enough to read
  # carry a tangential label; every segment shows a hover tooltip and is
  # tappable — `select_segment` echoes the slice below the chart, which is the
  # mobile substitute for hover.
  defp allocation_sunburst(assigns) do
    ~H"""
    <svg class="donut sunburst" viewBox="0 0 140 140" role="img" aria-label={gettext("Allocation")}>
      <g transform="rotate(-90 70 70)">
        <%= for ring <- @rings do %>
          <circle
            cx="70"
            cy="70"
            r={ring.radius}
            class="donut-track"
            stroke-width={ring.stroke}
            fill="none"
          />
          <%= for segment <- ring.segments do %>
            <circle
              cx="70"
              cy="70"
              r={ring.radius}
              fill="none"
              stroke={segment.color}
              stroke-opacity={segment.opacity}
              stroke-width={ring.stroke}
              stroke-dasharray={"#{segment.length} #{ring.circumference}"}
              stroke-dashoffset={-segment.offset}
              phx-click="select_segment"
              phx-value-name={segment.name}
              phx-value-percent={segment.percent}
              phx-value-value={segment.value}
              phx-value-color={segment.color}
            >
              <title><%= segment.name %> · <%= segment.percent %>%</title>
            </circle>
          <% end %>
        <% end %>
      </g>
      <%= for ring <- @rings, segment <- ring.segments, segment.label do %>
        <text
          x={segment.label_x}
          y={segment.label_y}
          transform={"rotate(#{segment.label_rotation} #{segment.label_x} #{segment.label_y})"}
          text-anchor="middle"
          dominant-baseline="middle"
          class="sunburst-label"
        >
          <%= segment.label %>
        </text>
      <% end %>
    </svg>
    """
  end

  # -- events -----------------------------------------------------------------

  @impl true
  def handle_event("select_period", %{"period" => period}, socket) do
    cond do
      period not in Performance.periods() ->
        {:noreply, socket}

      # The analysis is cached — re-chaining a period is pure and instant.
      socket.assigns.analysis ->
        {:ok, performance} = Performance.summarise(socket.assigns.analysis, period)
        {:noreply, assign(socket, period: period, performance: performance)}

      # Still computing; the async completion summarises the chosen period.
      true ->
        {:noreply, assign(socket, :period, period)}
    end
  end

  def handle_event("select_classification", %{"classification_id" => id}, socket) do
    case coerce_id(id) do
      {:ok, classification_id} ->
        {:noreply,
         socket
         |> assign(:classification_id, classification_id)
         |> assign(:selected_segment, nil)
         |> load_allocation()}

      :error ->
        {:noreply, socket}
    end
  end

  # The mobile substitute for hover: tapping a slice echoes it below the chart.
  # Values are display strings straight from our own render; HEEx escapes them.
  def handle_event("select_segment", params, socket) do
    segment = %{
      name: to_string(params["name"] || ""),
      percent: to_string(params["percent"] || ""),
      value: to_string(params["value"] || ""),
      color: safe_color(params["color"])
    }

    {:noreply, assign(socket, :selected_segment, segment)}
  end

  def handle_event("set_balance", %{"balance" => params}, socket) do
    with {:ok, account_id} <- coerce_id(params["cash_account_id"]),
         %{portfolio_id: pid} = account <- Portfolios.get_cash_account(account_id),
         true <- pid == socket.assigns.portfolio.id,
         {:ok, _tx} <- Ledger.set_cash_balance(account, params) do
      {:noreply,
       socket
       |> assign(success: gettext("Balance updated"), error: nil)
       |> assign(:analysis, nil)
       |> assign(:performance, nil)
       |> load_overview()
       |> load_performance()}
    else
      {:error, changeset} ->
        {:noreply, assign(socket, error: changeset_error(changeset), success: nil)}

      _other ->
        {:noreply, assign(socket, error: gettext("Account not found"), success: nil)}
    end
  end

  # -- data quality helpers ----------------------------------------------------

  defp unpriced_names(nil), do: []

  defp unpriced_names(valuation) do
    valuation.positions
    |> Enum.reject(& &1.valued)
    |> Enum.map(&(&1.security_name || gettext("Unsorted")))
    |> Enum.uniq()
    |> shorten_list()
  end

  defp shorten_list(names) when length(names) <= @unpriced_names_shown, do: names

  defp shorten_list(names) do
    {shown, rest} = Enum.split(names, @unpriced_names_shown)
    shown ++ ["+#{length(rest)}"]
  end

  defp trade_priced_count(nil), do: 0
  defp trade_priced_count(valuation), do: valuation.trade_priced_count

  defp suspect_dates(nil), do: []
  defp suspect_dates(analysis), do: analysis.suspect_dates

  # Prefer the first custom tree (the user's own strategy); otherwise fall back
  # to the built-in asset-class tree, which always exists after seeding.
  defp default_classification_id(classifications) do
    custom = Enum.find(classifications, &(not &1.built_in))
    asset_class = Enum.find(classifications, &(&1.key == "asset_class"))
    (custom || asset_class).id
  end

  # -- sunburst geometry -------------------------------------------------------

  @sunburst_inner 22
  @sunburst_outer 66

  # Builds one ring per tree depth plus one outermost ring with the individual
  # positions (the Portfolio Performance layout). The innermost ring is the
  # top-level categories; each deeper ring nests its children inside the
  # parent's angular span (value-weighted on the rolled-up subtree); securities
  # render as shades of their category's colour. Unassigned holdings get a grey
  # slice so it reads as a complete circle. Ring widths are derived from the
  # actual depth so any tree fits the viewBox.
  defp sunburst_rings(allocation) do
    nodes = sunburst_nodes(allocation)
    max_depth = nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)
    ring_width = (@sunburst_outer - @sunburst_inner) / (max_depth + 1)

    nodes
    |> Enum.group_by(& &1.depth)
    |> Enum.sort_by(fn {depth, _} -> depth end)
    |> Enum.map(fn {depth, ring_nodes} ->
      radius = @sunburst_inner + ring_width * (depth + 0.5)
      circumference = 2 * :math.pi() * radius

      %{
        radius: Float.round(radius, 2),
        stroke: Float.round(ring_width * 0.82, 2),
        circumference: Float.round(circumference, 2),
        segments: Enum.map(ring_nodes, &ring_segment(&1, radius, circumference))
      }
    end)
  end

  # Lays out each category's arc within its parent's start offset, recursing the
  # kept tree so children sit under their parent; the unassigned remainder is a
  # top-level grey node. A category's directly-held securities sit in the
  # trailing part of its span (children occupy the leading part), all on one
  # outermost ring. Offsets are kept as a fraction of the full turn so each
  # ring scales them to its own circumference.
  defp sunburst_nodes(allocation) do
    by_parent = Enum.group_by(allocation.categories, & &1.parent_id)
    roots = layout_level(Map.get(by_parent, nil, []), 0.0, 0)
    category_nodes = roots ++ layout_children(roots, by_parent)
    unassigned_node = unassigned_node(allocation.unassigned, roots)

    max_depth = category_nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)
    security_depth = max_depth + 1

    securities =
      security_nodes(category_nodes, security_depth) ++
        unassigned_security_nodes(allocation.unassigned, unassigned_node, security_depth)

    category_nodes ++ unassigned_node ++ securities
  end

  defp unassigned_node(nil, _roots), do: []

  defp unassigned_node(%{actual_weight: weight, market_value: value}, roots) do
    fraction = Decimal.to_float(weight)
    last_root_end = roots |> Enum.map(& &1.fraction_end) |> Enum.max(fn -> 0.0 end)

    [
      %{
        name: gettext("Unsorted"),
        color: @unassigned_color,
        percent: Format.percent(weight),
        value: Format.money(value),
        depth: 0,
        opacity: 1.0,
        positions: [],
        fraction_start: last_root_end,
        fraction_end: last_root_end + fraction
      }
    ]
  end

  defp layout_level(rows, start_fraction, depth) do
    {nodes, _} =
      Enum.map_reduce(rows, start_fraction, fn row, offset ->
        fraction = Decimal.to_float(row.actual_weight)

        node = %{
          name: row.name,
          color: row.color || @fallback_color,
          percent: Format.percent(row.actual_weight),
          value: Format.money(row.market_value),
          depth: depth,
          opacity: 1.0,
          category_id: row.category_id,
          positions: row.positions,
          fraction_start: offset,
          fraction_end: offset + fraction
        }

        {node, offset + fraction}
      end)

    nodes
  end

  defp layout_children(parent_nodes, by_parent) do
    Enum.flat_map(parent_nodes, fn parent ->
      children_rows = Map.get(by_parent, parent.category_id, [])
      child_nodes = layout_level(children_rows, parent.fraction_start, parent.depth + 1)
      child_nodes ++ layout_children(child_nodes, by_parent)
    end)
  end

  # The PP-style outermost ring: each category's direct positions, placed in
  # the trailing remainder of the category's span (its children occupy the
  # leading part), shaded by cycling opacity on the category colour.
  defp security_nodes(category_nodes, depth) do
    Enum.flat_map(category_nodes, fn node ->
      own_fraction = node.positions |> Enum.map(&Decimal.to_float(&1.weight)) |> Enum.sum()
      layout_positions(node.positions, node.fraction_end - own_fraction, node.color, depth)
    end)
  end

  defp unassigned_security_nodes(nil, _nodes, _depth), do: []

  defp unassigned_security_nodes(%{positions: positions}, [node], depth) do
    layout_positions(positions, node.fraction_start, @unassigned_color, depth)
  end

  defp layout_positions(positions, start_fraction, color, depth) do
    {nodes, _} =
      positions
      |> Enum.with_index()
      |> Enum.map_reduce(start_fraction, fn {position, index}, offset ->
        fraction = Decimal.to_float(position.weight)

        node = %{
          name: position.security_name || "?",
          color: color,
          percent: Format.percent(position.weight),
          value: Format.money(position.market_value),
          depth: depth,
          opacity: Enum.at([0.9, 0.6, 0.42], rem(index, 3)),
          fraction_start: offset,
          fraction_end: offset + fraction
        }

        {node, offset + fraction}
      end)

    nodes
  end

  # Arc length (in viewBox units) a segment needs before it gets an in-chart
  # label, and the average character width at the label font size — segments
  # too small for ~5 characters stay tooltip/tap-only, like PP.
  @label_min_arc 14.0
  @label_char_width 2.6

  defp ring_segment(node, radius, circumference) do
    length = (node.fraction_end - node.fraction_start) * circumference

    %{
      name: node.name,
      color: node.color,
      percent: node.percent,
      value: node.value,
      opacity: node.opacity,
      length: Float.round(max(length, 0.0), 2),
      offset: Float.round(node.fraction_start * circumference, 2)
    }
    |> put_label(node, radius, length)
  end

  # Tangential label at the segment's mid-angle, flipped on the left half so it
  # stays readable; truncated to what the arc can fit.
  defp put_label(segment, node, radius, arc_length) do
    if arc_length >= @label_min_arc do
      mid = (node.fraction_start + node.fraction_end) / 2
      theta = mid * 2 * :math.pi() - :math.pi() / 2
      rotation = mid * 360.0
      rotation = if rotation > 90.0 and rotation < 270.0, do: rotation - 180.0, else: rotation
      max_chars = trunc(arc_length / @label_char_width)

      Map.merge(segment, %{
        label: truncate_label(node.name, max_chars),
        label_x: Float.round(70 + radius * :math.cos(theta), 2),
        label_y: Float.round(70 + radius * :math.sin(theta), 2),
        label_rotation: Float.round(rotation, 1)
      })
    else
      Map.merge(segment, %{label: nil, label_x: nil, label_y: nil, label_rotation: nil})
    end
  end

  defp truncate_label(name, max_chars) do
    if String.length(name) <= max_chars do
      name
    else
      String.slice(name, 0, max(max_chars - 1, 1)) <> "…"
    end
  end

  # The legend lists the top-level categories (plus unassigned) only, so it
  # stays readable when a tree has many leaves.
  defp legend_segments(allocation) do
    roots =
      allocation.categories
      |> Enum.filter(&(&1.depth == 0 and Decimal.compare(&1.actual_weight, 0) == :gt))
      |> Enum.map(fn row ->
        %{
          name: row.name,
          color: row.color || @fallback_color,
          percent: Format.percent(row.actual_weight)
        }
      end)

    case allocation.unassigned do
      nil ->
        roots

      %{actual_weight: weight} ->
        roots ++
          [
            %{
              name: gettext("Unsorted"),
              color: @unassigned_color,
              percent: Format.percent(weight)
            }
          ]
    end
  end

  # -- performance chart geometry ----------------------------------------------

  # Long histories produce thousands of daily points; the polyline never needs
  # more than the chart can show, so sample evenly and always keep the last.
  defp downsample(series) when length(series) <= @chart_max_points, do: series

  defp downsample(series) do
    step = series |> length() |> Kernel./(@chart_max_points) |> Float.ceil() |> trunc()
    sampled = Enum.take_every(series, step)
    last = List.last(series)

    if List.last(sampled) == last, do: sampled, else: sampled ++ [last]
  end

  defp chart_geometry([]), do: %{min: -0.01, max: 0.01, zero_y: 90.0}

  defp chart_geometry(series) do
    values = Enum.map(series, &Decimal.to_float(&1.cumulative_ttwror))
    min = Enum.min([0.0 | values])
    max = Enum.max([0.0 | values])
    {min, max} = pad_flat(min, max)
    %{min: min, max: max, zero_y: y_for(0.0, min, max)}
  end

  defp pad_flat(min, max) when max - min < 1.0e-9, do: {min - 0.01, max + 0.01}
  defp pad_flat(min, max), do: {min, max}

  defp y_for(value, min, max), do: Float.round(170 - (value - min) / (max - min) * 160, 2)

  defp performance_points([]), do: ""

  defp performance_points(series) do
    %{min: min, max: max} = chart_geometry(series)
    last = max(length(series) - 1, 1)

    series
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {point, index} ->
      x = Float.round(index / last * 720, 2)
      y = y_for(Decimal.to_float(point.cumulative_ttwror), min, max)
      "#{x},#{y}"
    end)
  end

  # -- misc ---------------------------------------------------------------------

  defp period_label("ytd"), do: gettext("YTD")
  defp period_label("1y"), do: gettext("1Y")
  defp period_label("3y"), do: gettext("3Y")
  defp period_label("5y"), do: gettext("5Y")
  defp period_label("max"), do: gettext("Max")

  defp coerce_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp coerce_id(_value), do: :error

  # The colour lands in a style attribute, so only a literal hex colour from
  # our own render is accepted — anything else falls back to neutral grey.
  defp safe_color(value) when is_binary(value) do
    if value =~ ~r/^#[0-9a-fA-F]{6}$/, do: value, else: @fallback_color
  end

  defp safe_color(_value), do: @fallback_color

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
