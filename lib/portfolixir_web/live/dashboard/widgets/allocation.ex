defmodule PortfolixirWeb.Dashboard.Widgets.Allocation do
  @moduledoc """
  The section widget „Allokation“ `allocation` (I57; Sprint 32 W2;
  ADR-0062's amendment of 2026-11-25, points 3 and 7; planning board
  `ux-design-2026-11-25-sprint32/02` ②): Wealth's section „Allocation“ of
  the tab „Allokation & Ziele“, moved here so that one code path draws it
  on Wealth (`controls/1` in the section's head and `body/1` under it,
  which `PortfolixirWeb.PortfolioLive` renders) and on a dashboard
  (`widget/1`).

  Every figure is `Portfolixir.Portfolios.Allocation.for_portfolio/3` for
  the first portfolio, the tree picked (the default steering tree,
  `Portfolixir.Classifications.default_classification/1`, until one is
  picked) and the scope, the read `GET
  /api/v1/portfolios/:portfolio_id/allocation?classification_id=&view=`
  answers (`allocation_for/3`, which Wealth's read calls too):

    * **tree or positions** — the tree's sunburst with its legend and the
      drift table (the sunburst as rows: value, actual, target, drift, a
      category opening its securities), or the flat worklist of every
      position by its drift;
    * the **display-only rebalancing hints** of ADR-0023 („Verkauf ≈ …
      Stück“): arithmetic beside a drift, never an order, nothing stored;
    * the **drift chips**, the human half of the API's `min_drift=`, and
      the **classification choice**.

  The section's controls keep their state where the page keeps it: Wealth
  on its address, as before; a dashboard per widget, for the page's life
  (`PortfolixirWeb.DashboardLive`), nothing stored. The state's changes
  are this module's (`toggle_category/2`, `toggle_all/2`,
  `select_segment/2`, `sort/2`), so both pages change it alike. The
  targets are edited on the Classifications page, linked from the plan
  line and the notes (ADR-0022's amendment of 2026-11-21, point 3).

  The ids of a section drawn on a dashboard carry the widget's prefix
  (`prefix`), so two widgets never share one; on Wealth the prefix is
  empty and the ids are the page's own. Its compact form is the section's
  own narrow layout: the same markup, drawn once, outside the frame's two
  forms (`widget--single-form`).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Classifications
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.ControlBar
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.Portfolio.CategoryColors
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.SecurityNames

  @unassigned_color CategoryColors.unassigned()
  @fallback_color "#6b7280"
  @cash_color CategoryColors.cash()
  @drift_steps ["1", "2", "5"]

  # -- the read -------------------------------------------------------------------

  @doc """
  The allocation of `portfolio_id` in the tree `classification_id`, with
  the read's options (`view:`, `pricing_context:`): `{:ok, nil}` without a
  tree (#1366: no classification, no allocation), else what
  `Allocation.for_portfolio/3` answers. Wealth's reads call it, and the
  widget's.
  """
  @spec allocation_for(integer(), integer() | nil, keyword()) ::
          {:ok, map() | nil} | {:error, term()}
  def allocation_for(_portfolio_id, nil, _opts), do: {:ok, nil}

  def allocation_for(portfolio_id, classification_id, opts),
    do: Allocation.for_portfolio(portfolio_id, classification_id, opts)

  @doc """
  A loaded allocation made ready to draw, Wealth's one landing spot: each
  category's display colour resolved, a twin's identifier on each
  position, and the two lookups the collapsible tree needs (each
  category's parent, and the categories with child categories). `nil`
  for no allocation.
  """
  @spec prepare(map() | nil) :: %{
          allocation: map() | nil,
          parent_map: map(),
          parents_with_children: MapSet.t()
        }
  def prepare(nil), do: %{allocation: nil, parent_map: %{}, parents_with_children: MapSet.new()}

  def prepare(allocation) do
    allocation = allocation |> with_display_colors() |> with_twin_ids()

    parents_with_children =
      allocation.categories
      |> Enum.map(& &1.parent_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %{
      allocation: allocation,
      parent_map: Map.new(allocation.categories, &{&1.category_id, &1.parent_id}),
      parents_with_children: parents_with_children
    }
  end

  @doc """
  The widget's read, in the dashboard's background task: the allocation
  of the first portfolio in the tree `classification_id` (the default
  steering tree when it is nil or no longer stored) for the scope
  `scope_id` (nil for Everything; a vanished view reads Everything),
  prepared to draw (`prepare/1`), with the trees to choose from, the tree
  read and the scope. `%{state: :no_portfolio}` without a portfolio.
  """
  @spec read(integer() | nil, integer() | nil) :: map()
  def read(scope_id, classification_id) do
    classifications = Classifications.list_classifications()
    tree_id = tree_id(classification_id, classifications)

    case Portfolios.first_portfolio() do
      nil ->
        %{state: :no_portfolio}

      portfolio ->
        view = scope_id && Buckets.get_view(scope_id)
        view_id = view && view.id

        case allocation_for(portfolio.id, tree_id, view: view_id) do
          {:ok, allocation} ->
            allocation
            |> prepare()
            |> Map.merge(%{
              state: :ok,
              classifications: classifications,
              classification_id: tree_id,
              view_id: view_id,
              view_name: view && view.name
            })

          {:error, :view_not_found} ->
            read(nil, classification_id)

          # The tree was deleted between the list and the read: the default.
          {:error, :not_found} when not is_nil(classification_id) ->
            read(scope_id, nil)

          {:error, _reason} ->
            %{state: :no_portfolio}
        end
    end
  end

  defp tree_id(id, classifications) when is_integer(id) do
    if Enum.any?(classifications, &(&1.id == id)),
      do: id,
      else: tree_id(nil, classifications)
  end

  defp tree_id(_id, classifications) do
    case Classifications.default_classification(classifications) do
      nil -> nil
      classification -> classification.id
    end
  end

  # -- the state of the section's controls -----------------------------------------

  @doc "The drift chips' steps, in percentage points."
  @spec drift_steps() :: [String.t()]
  def drift_steps, do: @drift_steps

  @doc """
  The mode a button's value names, matched against a whitelist (never an
  atom made from input, AGENTS.md): `{:ok, :tree | :flat}` or `:error`.
  """
  @spec mode(term()) :: {:ok, :tree | :flat} | :error
  def mode("tree"), do: {:ok, :tree}
  def mode("flat"), do: {:ok, :flat}
  def mode(_value), do: :error

  @doc """
  The expanded categories after a category's toggle (ADR-0023's
  drill-down): the category named by `raw_id` (a sent id, or
  `"unassigned"` for the unassigned bucket) opened or closed; `:error`
  for a value that names none. Pure display state; nothing is stored.
  """
  @spec toggle_category(MapSet.t(), term()) :: {:ok, MapSet.t()} | :error
  def toggle_category(expanded, "unassigned"), do: {:ok, flip(expanded, :unassigned)}

  def toggle_category(expanded, raw_id) do
    case LiveParam.fetch_id(raw_id) do
      {:ok, category_id} -> {:ok, flip(expanded, category_id)}
      :error -> :error
    end
  end

  defp flip(set, member) do
    if MapSet.member?(set, member), do: MapSet.delete(set, member), else: MapSet.put(set, member)
  end

  @doc """
  One toggle (UAT fix round): expand-all reveals every level down to the
  positions (unassigned included); once everything is open the same
  button collapses back to the top-level bird's view.
  """
  @spec toggle_all(map() | nil, MapSet.t()) :: MapSet.t()
  def toggle_all(allocation, expanded) do
    if all_categories_expanded?(allocation, expanded),
      do: MapSet.new(),
      else: all_expandable_ids(allocation)
  end

  @doc """
  The mobile substitute for hover: a tapped slice, echoed in the centre.
  Values are display strings straight from the section's own render; HEEx
  escapes them. #1366 line 1: a tap on the selected slice again brings
  the total back (`nil`).
  """
  @spec select_segment(map() | nil, map()) :: map() | nil
  def select_segment(selected, params) do
    segment = %{
      name: LiveParam.string(params["name"]) || "",
      percent: LiveParam.string(params["percent"]) || "",
      value: LiveParam.string(params["amount"]) || "",
      target: LiveParam.string(params["target"]) || "",
      color: safe_color(params["color"])
    }

    if segment == selected, do: nil, else: segment
  end

  @doc """
  The flat worklist's sort after a click on a column head: the active key
  flips its direction; a new numeric key starts desc (worklist semantics:
  biggest lever first), the category label starts asc (alphabetical
  reading order). `:error` for a key the list does not sort by.
  """
  @spec sort({atom(), :asc | :desc}, term()) :: {:ok, {atom(), :asc | :desc}} | :error
  def sort(current, key) when key in ["value", "drift", "weight", "category"] do
    key = String.to_existing_atom(key)

    case current do
      {^key, dir} -> {:ok, {key, flip_dir(dir)}}
      _other -> {:ok, {key, initial_dir(key)}}
    end
  end

  def sort(_current, _key), do: :error

  @doc "The flat worklist's first sort: the signed drift, overweight first."
  @spec default_sort() :: {:drift, :desc}
  def default_sort, do: {:drift, :desc}

  @doc """
  The section's state on a dashboard, per widget, before any click: the
  tree, the default tree, no category open, no slice picked, no drift
  chip, the drift sort.
  """
  @spec initial_state() :: map()
  def initial_state,
    do: %{
      mode: :tree,
      classification_id: nil,
      expanded: MapSet.new(),
      selected_segment: nil,
      min_drift_pp: nil,
      flat_sort: default_sort()
    }

  # -- the section ------------------------------------------------------------------

  attr(:prefix, :string,
    default: "",
    doc: "the ids' prefix: empty on Wealth, the widget's on a dashboard"
  )

  attr(:item, :string, default: nil, doc: "on a dashboard, the widget each event names")
  attr(:mode, :atom, required: true)
  attr(:classifications, :list, required: true)
  attr(:classification_id, :any, required: true)

  @doc "The section's controls, in its head: tree or positions, and the tree."
  def controls(assigns) do
    ~H"""
    <%!-- Tree answers "is my structure on plan?"; Positions is the
         flat rebalancing worklist - sorting belongs to a flat list,
         not to a hierarchy (owner request). --%>
    <%!-- #875: the segmented group ({components.selected-segment}),
         so the two states look different, not only sound different. --%>
    <div class="segmented-control" role="group" aria-label={gettext("Allocation view")}>
      <button
        type="button"
        data-role="allocation-mode-tree"
        class={["segmented-control__option", @mode == :tree && "is-active"]}
        phx-click="set_allocation_mode"
        phx-value-item={@item}
        phx-value-mode="tree"
        aria-pressed={to_string(@mode == :tree)}
      >
        <%= gettext("Tree") %>
      </button>
      <button
        type="button"
        data-role="allocation-mode-flat"
        class={["segmented-control__option", @mode == :flat && "is-active"]}
        phx-click="set_allocation_mode"
        phx-value-item={@item}
        phx-value-mode="flat"
        aria-pressed={to_string(@mode == :flat)}
      >
        <%= gettext("Positions") %>
      </button>
    </div>
    <form id={@prefix <> "allocation-classification-form"} phx-change="select_classification">
      <%!-- On a dashboard the widget it belongs to (Sprint 32 W2). --%>
      <input :if={@item} type="hidden" name="item" value={@item} />
      <label class="visually-hidden" for={@prefix <> "allocation-classification"}>
        <%= gettext("Classification") %>
      </label>
      <select id={@prefix <> "allocation-classification"} name="classification_id">
        <%= for classification <- @classifications do %>
          <option value={classification.id} selected={classification.id == @classification_id}>
            <%= ClassificationName.display(classification) %>
          </option>
        <% end %>
      </select>
    </form>
    """
  end

  attr(:prefix, :string,
    default: "",
    doc: "the ids' prefix: empty on Wealth, the widget's on a dashboard"
  )

  attr(:item, :string, default: nil, doc: "on a dashboard, the widget each event names")
  attr(:allocation, :any, required: true, doc: "nil while the read runs or without a tree")
  attr(:mode, :atom, required: true)
  attr(:classification_id, :any, required: true)
  attr(:selected_segment, :any, required: true)
  attr(:expanded, :any, required: true)
  attr(:parent_map, :map, required: true)
  attr(:parents_with_children, :any, required: true)
  attr(:min_drift_pp, :any, required: true)
  attr(:flat_sort, :any, required: true)
  attr(:currency, :string, default: nil, doc: "the drift's currency, nil while it is not known")
  attr(:view_id, :any, required: true)
  attr(:view_name, :string, default: nil, doc: "the view's name, nil for Everything")

  @doc """
  The section's body: the plan line, the sunburst and the drift table or
  the flat worklist; without a tree a line saying so, and while the read
  runs the skeleton.
  """
  def body(assigns) do
    ~H"""
    <%= if @allocation do %>
      <%!-- The SOLL side follows the active view's plan (ADR-0020). With a
           plan the Σ-vs-100% header shows; without one the allocation is
           IST-only and a hint deep-links into the per-view plan editor. --%>
      <%!-- The chart's basis line (issue 793, Part 4 rule 9): the plan
           with its top-level Σ — the sentence that floated above the
           chart, folded in — the view and the as-of date. A 0% top
           level over a plan steered deeper in the tree is explained,
           not left as a contradiction (fix round). --%>
      <p class="summary-basis allocation-basis" data-role="allocation-basis">
        <%= if @allocation.has_plan do %>
          <%= gettext("Plan on %{classification}",
            classification: allocation_tree_name(@allocation)
          ) %>
          <%!-- #875: the warning colour only above 100 % (ADR-0040 §3,
               DESIGN.md D3); a plan that allocates less says what its
               drift measures against (§2) — the Σ before it is that
               allocated portion. --%>
          · <span
            class={["target-sum", plan_overshoot(@allocation) && "is-target-mismatch"]}
            data-role="target-sum-top-level"
          >
            <%= gettext("Σ target top level:") %>
            <%= Format.percent(@allocation.top_level_target_sum) %>%
            <%= if deep_targets_below?(@allocation) do %>
              — <%= gettext("targets deeper in the tree:") %>
              <%= Format.percent(@allocation.deep_target_sum) %>%
            <% end %>
            <span
              :if={Map.get(@allocation, :drift_basis) == "allocated_portion"}
              data-role="drift-basis"
            >
              — <%= gettext("drift against the allocated portion") %>
            </span>
          </span>
        <% else %>
          <%= gettext("Actual allocation on %{classification}",
            classification: allocation_tree_name(@allocation)
          ) %>
        <% end %>
        · <%= gettext("View %{name}", name: view_name(@view_name)) %>
        · <%= gettext("as of %{date}", date: Format.date(Portfolixir.Clock.today())) %>
      </p>
      <%= if not @allocation.has_plan do %>
        <%!-- Scope-aware copy (fix round): only a named view may talk
             about "this view"; the Gesamt scope speaks plainly. --%>
        <p class="hint no-plan-hint" data-role="no-plan-hint" role="status">
          <%= if @view_id do %>
            <%= gettext("No target plan for this view — showing actual allocation only.") %>
          <% else %>
            <%= gettext("No target plan yet — showing actual allocation only.") %>
          <% end %>
          <.link navigate={plan_editor_path(@classification_id, @view_id)}>
            <%= if @view_id do %>
              <%= gettext("Create a plan for this view") %>
            <% else %>
              <%= gettext("Create a plan") %>
            <% end %>
          </.link>
        </p>
      <% end %>
      <%= if @mode == :tree do %>
      <div class="donut-wrap">
        <div class="sunburst-pane">
          <%!-- #1366 line 1: with a slice selected, a tap on the
               figure (the centre lets it through to the chart), a tap
               outside it and Escape bring the total back; a slice's
               own phx-click is nearer, so a tap on a slice selects
               it. Nothing listens while nothing is selected. --%>
          <div
            class="sunburst-figure"
            data-role="sunburst-figure"
            phx-click={@selected_segment && "clear_segment"}
            phx-value-item={@item}
            phx-click-away={@selected_segment && "clear_segment"}
            phx-window-keydown={@selected_segment && "clear_segment"}
            phx-key={@selected_segment && "Escape"}
          >
            <.allocation_sunburst segments={sunburst_segments(@allocation)} prefix={@prefix} item={@item} />
            <.sunburst_centre centre={sunburst_centre(@selected_segment, @allocation)} />
          </div>
        </div>
        <ul class="donut-legend">
          <%= for segment <- legend_segments(@allocation) do %>
            <li>
              <span class="cat-swatch" style={"background:#{segment.color}"} aria-hidden="true">
              </span>
              <span class="legend-name"><%= segment.name %></span>
              <span class="legend-value">
                <%= segment.percent %>%<%= if segment[:value], do: PrivacyMode.html(" · #{segment.value}") %>
              </span>
            </li>
          <% end %>
        </ul>
      </div>

      <%!-- #719 (D3): findings are {components.data-note} rows above
           the table, never pills inside data cells — over-100 % sums at
           attention, position-vs-category conflicts at problem, stale
           position targets at attention. One status region wraps the
           list (data-note aria rule). --%>
      <div
        :if={
          @allocation.has_plan and
            (conflicted_categories(@allocation) != [] or
               stale_categories(@allocation) != [] or plan_overshoot(@allocation))
        }
        role="status"
        class="allocation-findings"
      >
        <%!-- I1 (board ux-design-2026-11-03-sprint23-i1, Allokation ③
             ⑤; found while drawing 6): the problem leads, every
             finding clamps, and each remedy link leaves its sentence
             for the note's actions as a command of its own, visible
             under the clamp. --%>
        <AppShell.data_note
          :if={conflicted_categories(@allocation) != []}
          severity={:problem}
          id={@prefix <> "target-conflict-note"}
          data-role="target-conflict-note"
          clamp
        >
          <%= gettext(
            "The position targets steer in %{categories}: their sum overrides the stored category weight.",
            categories: Enum.join(conflicted_categories(@allocation), ", ")
          ) %>
          <:actions>
            <a href="/classifications">
              <%= gettext("Align the position targets and the category weight on the Classifications page") %>
            </a>
          </:actions>
        </AppShell.data_note>
        <AppShell.data_note
          :if={plan_overshoot(@allocation)}
          severity={:attention}
          id={@prefix <> "plan-overshoot-note"}
          data-role="plan-overshoot-note"
          clamp
        >
          <%= gettext(
            "The plan's top-level targets sum to %{sum} % — more than 100 %. Drift keeps steering against the stored weights.",
            sum: Format.percent(plan_overshoot(@allocation))
          ) %>
          <:actions>
            <a href="/classifications"><%= gettext("Trim the plan on the Classifications page") %></a>
          </:actions>
        </AppShell.data_note>
        <AppShell.data_note
          :if={stale_categories(@allocation) != []}
          severity={:attention}
          id={@prefix <> "stale-target-note"}
          data-role="stale-target-note"
          clamp
        >
          <%= gettext(
            "A position target filed in %{categories} is stale: its security was moved or unassigned. It keeps counting there until it is re-filed.",
            categories: Enum.join(stale_categories(@allocation), ", ")
          ) %>
          <:actions>
            <a href="/classifications"><%= gettext("Re-file it on the Classifications page") %></a>
          </:actions>
        </AppShell.data_note>
      </div>

      <%!-- One expand/collapse toggle directly above the table (UAT fix
           round): the label states the action it will perform next.
           Beside it the drift threshold — the human half of the API's
           `min_drift=`, same predicate, same rows. --%>
      <%!-- The one uniform chart-as-table disclosure (UX-DR10, issue
           793): the drift table beneath IS the sunburst's table and
           gains the disclosure head. --%>
      <%!-- #1339 (board ux-design-2026-11-03-sprint23-i1 ⑦): a patch
           strips the `open` the browser set, so a category toggled
           inside folded the table shut; the shell's
           `DisclosureState` hook puts it back. --%>
      <details
        id={@prefix <> "allocation-disclosure"}
        class="perf-table-disclosure"
        data-role="allocation-disclosure"
        phx-hook="DisclosureState"
      >
      <summary class="disclosure-summary">
        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= gettext("Data as table") %>
      </summary>
      <p class="hint" data-role="allocation-table-purpose">
        <%= gettext("Category, value, actual, target and drift — the sunburst as rows.") %>
      </p>
      <div class="drift-table-actions">
        <button
          type="button"
          data-role="toggle-all-categories"
          class="button-mini"
          phx-click="toggle_all_categories"
          phx-value-item={@item}
        >
          <%= if all_categories_expanded?(@allocation, @expanded) do %>
            <%= gettext("Collapse all") %>
          <% else %>
            <%= gettext("Expand all") %>
          <% end %>
        </button>
        <%!-- The same chip component the transaction history filters
             with: one interaction, one visual. Pressed state is border
             plus aria-pressed, not hue alone (UX-DR7). Issue 1435
             (Sprint 29 L2): one family in a bar of labelled controls,
             its chips wrapping beside „Abweichung ab“, never under
             it. --%>
        <ControlBar.bar
          :if={@allocation.has_plan}
          class="drift-filter"
          fold={:always}
          data-role="drift-filter"
        >
          <:group label={gettext("Deviating by")} label_id={@prefix <> "drift-filter-label"}>
            <span
              class="filter-chips"
              role="group"
              aria-labelledby={@prefix <> "drift-filter-label"}
            >
              <button
                :for={pp <- drift_steps()}
                type="button"
                data-role="drift-chip"
                phx-click="set_drift_threshold"
                phx-value-item={@item}
                phx-value-pp={pp}
                class={["filter-chip", @min_drift_pp == pp && "is-active"]}
                aria-pressed={to_string(@min_drift_pp == pp)}
              >
                <%= gettext("≥ %{pp} pp", pp: pp) %>
              </button>
            </span>
          </:group>
        </ControlBar.bar>
      </div>
      <%!-- A filtered table says what it is showing (UX-DR21), so a
           short list is never mistaken for a short plan. --%>
      <p class="drift-filter-summary" data-role="drift-filter-summary">
        <%= if @min_drift_pp do %>
          <%= gettext(
            "Showing %{shown} of %{total} categories, those deviating by at least %{pp} pp. Cash and unassigned always show.",
            shown: length(threshold_rows(@allocation.categories, @min_drift_pp)),
            total: length(@allocation.categories),
            pp: @min_drift_pp
          ) %>
        <% else %>
          <%= gettext("Showing all %{total} categories.",
            total: length(@allocation.categories)
          ) %>
        <% end %>
      </p>

      <div class="data-table-wrapper">
        <table class="drift-table" aria-describedby={@prefix <> "tip-soll-ist"}>
          <thead>
            <tr>
              <th><%= gettext("Category") %></th>
              <th class="num"><%= gettext("Value") %></th>
              <th class="num"><%= gettext("Actual") %></th>
              <%= if @allocation.has_plan do %>
                <th class="num"><%= gettext("Target") %></th>
                <th class="num col-subject">
                  <%= gettext("Drift") %>
                  <details class="metric-tooltip">
                    <summary aria-label={gettext("Target/actual drift info")}>ⓘ</summary>
                    <p id={@prefix <> "tip-soll-ist"} role="tooltip">
                      <%= gettext("Target vs. actual: drift is actual weight minus target weight. Positive = overweight (reduce to reach the target), negative = underweight (add to reach it).") %>
                      <%!-- #911 (c), ADR-0040 §2: a plan allocating
                           less than 100 % measures each target
                           against the allocated portion, while the
                           Target column shows the raw target; the ⓘ
                           says so, with one worked figure. --%>
                      <span
                        :if={Map.get(@allocation, :drift_basis) == "allocated_portion"}
                        data-role="drift-basis-tip"
                      >
                        <%= drift_basis_tip(@allocation) %>
                      </span>
                    </p>
                  </details>
                </th>
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= for row <- visible_category_rows(
                  @allocation.categories,
                  min_drift_decimal(@min_drift_pp),
                  @expanded,
                  @parent_map
                ) do %>
              <tr class={row.depth > 0 && "is-child"}>
                <%!-- The whole name cell toggles the subtree (UAT fix
                     round): the chevron alone is too small a target. --%>
                <td
                  style={"padding-left:#{0.75 + row.depth * 1.25}rem"}
                  class={has_subtree?(row, @parents_with_children) && "is-clickable"}
                  phx-value-item={@item}
                  phx-click={
                    has_subtree?(row, @parents_with_children) &&
                      "toggle_category_positions"
                  }
                  phx-value-category-id={row.category_id}
                >
                  <button
                    :if={has_subtree?(row, @parents_with_children)}
                    type="button"
                    class="positions-toggle"
                    data-role="toggle-positions"
                    phx-click="toggle_category_positions"
                    phx-value-item={@item}
                    phx-value-category-id={row.category_id}
                    aria-expanded={to_string(expanded?(@expanded, row))}
                    aria-label={gettext("Toggle the category's securities")}
                  >
                    <%= if expanded?(@expanded, row), do: "▾", else: "▸" %>
                  </button>
                  <span
                    :if={row.color}
                    class="cat-swatch"
                    style={"background:#{row.color}"}
                    aria-hidden="true"
                  >
                  </span>
                  <%= row.name %>
                  <%!-- A parent without an own weight gets an honest hint
                       (fix round): its children's Σ is stated without
                       the nonsensical "of 0.0%" comparison. --%>
                  <span
                    :if={@allocation.has_plan and row.child_target_sum}
                    class={["hint", "target-consistency", subcategory_mismatch?(row) && "is-target-mismatch"]}
                    data-role="target-consistency-hint"
                  >
                    <%= if Decimal.equal?(row.target_weight, 0) do %>
                      <%= gettext("subcategories Σ") %>
                      <%= Format.percent(row.child_target_sum) %>%
                      <%= gettext("(no own weight)") %>
                    <% else %>
                      <%= gettext("subcategories:") %>
                      <%= Format.percent(row.child_target_sum) %>% <%= gettext("of") %>
                      <%= Format.percent(row.target_weight) %>%
                    <% end %>
                  </span>
                  <%!-- #719 (D3): the category-cell pill is retired —
                       conflict and stale findings render as data notes
                       above the table (UX-DR17). --%>
                </td>
                <td class="num"><%= Format.money(row.market_value) %></td>
                <td class="num"><%= Format.percent(row.actual_weight) %>%</td>
                <%= if @allocation.has_plan do %>
                  <td class="num">
                    <%= if Decimal.equal?(row.target_weight, 0) do %>
                      —
                    <% else %>
                      <%= Format.percent(row.target_weight) %>%
                    <% end %>
                  </td>
                  <td class={[
                    "num",
                    "col-subject",
                    drift_negative_class(row.drift_value)
                  ]}>
                    <%= if Decimal.equal?(row.target_weight, 0) do %>
                      —
                    <% else %>
                      <%= Format.money(row.drift_value) %>
                      <%= @currency %>
                    <% end %>
                  </td>
                <% end %>
              </tr>
              <%!-- Drill-down (ADR-0023): the expanded category's member
                   securities, each with its share of the drift and a
                   display-only rebalancing hint. No order is created,
                   stored, or transmitted. --%>
              <%= if expanded?(@expanded, row) do %>
                <%= for position <- row.positions do %>
                  <tr class="is-position is-muted" data-role="allocation-position">
                    <td style={"padding-left:#{2.0 + row.depth * 1.25}rem"}>
                      <span data-role="position-name"><%= position.security_name %><SecurityNames.twin_id tag={Map.get(position, :twin_id)} /></span>
                      <%!-- ADR-0030 slice 2a: a SOLL-only row (IST 0) is
                           marked with text, never hue alone (UX-DR7);
                           scope-aware inside a view (fix round). --%>
                      <span :if={not position.held} class="not-held-chip" data-role="not-held">
                        <%= not_held_label(@view_id) %>
                      </span>
                      <.position_soll_chips position={position} />
                    </td>
                    <td class="num"><%= Format.money(position.market_value) %></td>
                    <td class="num"><%= Format.percent(position.weight) %>%</td>
                    <%= if @allocation.has_plan do %>
                      <td class="num">
                        <%!-- The position's own SOLL (ADR-0030 slice 2a);
                             blank without one, as before. --%>
                        <%= if position.target_weight do %>
                          <%= Format.percent(position.target_weight) %>%
                        <% end %>
                      </td>
                      <td class={[
                        "num",
                        "col-subject",
                        drift_negative_class(position.drift_value)
                      ]}>
                        <%= if position_drift_shown?(position, row) do %>
                          <%= Format.money(position.drift_value) %>
                          <%= @currency %>
                          <.rebalance_hint
                            quantity={position.rebalance_quantity}
                            quote_date={position.quote_date}
                          />
                        <% else %>
                          —
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              <% end %>
            <% end %>
            <%!-- In the currency classification cash is distributed into
                 currency buckets (issue #407), so the separate Cash row
                 is suppressed. All other classifications keep it. --%>
            <%= unless @allocation.cash.distributed do %>
              <tr id={@prefix <> "allocation-cash"} data-role="allocation-cash">
                <td>
                  <span
                    class="cat-swatch"
                    style={"background:#{cash_color()}"}
                    aria-hidden="true"
                  >
                  </span>
                  <%= gettext("Cash") %>
                </td>
                <td class="num"><%= Format.money(@allocation.cash.market_value) %></td>
                <td class="num"><%= Format.percent(@allocation.cash.actual_weight) %>%</td>
                <%= if @allocation.has_plan do %>
                  <td class="num">
                    <%= if Decimal.equal?(@allocation.cash.target_weight, 0) do %>
                      —
                    <% else %>
                      <%= Format.percent(@allocation.cash.target_weight) %>%
                    <% end %>
                  </td>
                  <td class={[
                    "num",
                    "col-subject",
                    drift_negative_class(@allocation.cash.drift_value)
                  ]}>
                    <%= if Decimal.equal?(@allocation.cash.target_weight, 0) do %>
                      —
                    <% else %>
                      <%= Format.money(@allocation.cash.drift_value) %>
                      <%= @currency %>
                    <% end %>
                  </td>
                <% end %>
              </tr>
            <% end %>
            <%= if @allocation.unassigned do %>
              <%!-- The unassigned bucket expands like a category row (UAT
                   fix round), keyed by the "unassigned" sentinel id. An
                   unassigned position can still carry a (stale) position
                   SOLL (fix round) — that SOLL steers its filed
                   category's Σ, so the row shows it instead of a dash. --%>
              <tr class="is-muted">
                <td
                  class="is-clickable"
                  phx-click="toggle_category_positions"
                  phx-value-item={@item}
                  phx-value-category-id="unassigned"
                >
                  <button
                    type="button"
                    class="positions-toggle"
                    data-role="toggle-positions"
                    phx-click="toggle_category_positions"
                    phx-value-item={@item}
                    phx-value-category-id="unassigned"
                    aria-expanded={to_string(MapSet.member?(@expanded, :unassigned))}
                    aria-label={gettext("Toggle the category's securities")}
                  >
                    <%= if MapSet.member?(@expanded, :unassigned), do: "▾", else: "▸" %>
                  </button>
                  <%= gettext("Unassigned") %>
                </td>
                <td class="num"><%= Format.money(@allocation.unassigned.market_value) %></td>
                <td class="num">
                  <%= Format.percent(@allocation.unassigned.actual_weight) %>%
                </td>
                <%= if @allocation.has_plan do %>
                  <td class="num">—</td>
                  <td class="num">—</td>
                <% end %>
              </tr>
              <%= if MapSet.member?(@expanded, :unassigned) do %>
                <%= for position <- @allocation.unassigned.positions do %>
                  <tr class="is-position is-muted" data-role="allocation-position">
                    <td style="padding-left:2.0rem">
                      <span data-role="position-name"><%= position.security_name %><SecurityNames.twin_id tag={Map.get(position, :twin_id)} /></span>
                      <.position_soll_chips position={position} />
                    </td>
                    <td class="num"><%= Format.money(position.market_value) %></td>
                    <td class="num"><%= Format.percent(position.weight) %>%</td>
                    <%= if @allocation.has_plan do %>
                      <td class="num">
                        <%= if position.target_weight do %>
                          <%= Format.percent(position.target_weight) %>%
                        <% else %>
                          —
                        <% end %>
                      </td>
                      <td class={[
                        "num",
                        "col-subject",
                        drift_negative_class(position.drift_value)
                      ]}>
                        <%= if position.drift_value do %>
                          <%= Format.money(position.drift_value) %>
                          <%= @currency %>
                          <.rebalance_hint
                            quantity={position.rebalance_quantity}
                            quote_date={position.quote_date}
                          />
                        <% else %>
                          —
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if @allocation.unassigned && Decimal.compare(@allocation.unassigned.actual_weight, 0) == :gt do %>
        <p class="hint" data-role="unassigned-hint">
          <%= gettext("%{pct}% of holdings aren't assigned to a category.",
            pct: Format.percent(@allocation.unassigned.actual_weight)
          ) %>
          <.link navigate={"/classifications/#{@classification_id}"}>
            <%= gettext("Assign them on the Classifications page") %>
          </.link>
        </p>
      <% end %>
      </details>
      <% end %>

      <%!-- The flat rebalancing worklist: one row per position, ranked
           by signed drift by default (overweight first, underweight
           last), re-sortable via the column heads. Cash joins as a row;
           unassigned positions carry no drift (nudging toward
           assignment). --%>
      <%= if @mode == :flat do %>
        <div class="data-table-wrapper">
          <table class="drift-table" data-role="flat-positions">
            <thead>
              <tr>
                <th><%= gettext("Security") %></th>
                <th>
                  <button
                    type="button"
                    class="table-sort"
                    data-role="flat-sort-category"
                    phx-click="sort_flat_positions"
                    phx-value-item={@item}
                    phx-value-key="category"
                  >
                    <%= gettext("Category") %><%= flat_sort_marker(@flat_sort, :category) %>
                  </button>
                </th>
                <th class="num">
                  <button
                    type="button"
                    class="table-sort"
                    data-role="flat-sort-value"
                    phx-click="sort_flat_positions"
                    phx-value-item={@item}
                    phx-value-key="value"
                  >
                    <%= gettext("Value") %><%= flat_sort_marker(@flat_sort, :value) %>
                  </button>
                </th>
                <th class="num"><%= gettext("Actual") %></th>
                <%!-- #911 (pick H4, variant A): the subject is the
                     drift with its hint beneath it — one pinned
                     column, the tree's position-row anatomy. --%>
                <%= if @allocation.has_plan do %>
                  <th class="num col-subject">
                    <button
                      type="button"
                      class="table-sort"
                      data-role="flat-sort-drift"
                      phx-click="sort_flat_positions"
                      phx-value-item={@item}
                      phx-value-key="drift"
                    >
                      <%= gettext("Drift") %><%= flat_sort_marker(@flat_sort, :drift) %>
                    </button>
                  </th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={entry <- flat_positions(@allocation, @flat_sort)}
                class={entry.cash? && "is-muted"}
                data-role={if entry.cash?, do: "flat-cash", else: "flat-position"}
              >
                <td>
                  <span data-role="position-name"><%= entry.security_name %><SecurityNames.twin_id tag={Map.get(entry, :twin_id)} /></span>
                  <%!-- ADR-0030 slice 2a: SOLL-only rows are marked with
                       text, never hue alone (UX-DR7); scope-aware inside
                       a view (fix round). --%>
                  <span :if={not entry.held} class="not-held-chip" data-role="not-held">
                    <%= not_held_label(@view_id) %>
                  </span>
                  <.position_soll_chips position={entry} />
                </td>
                <td>
                  <%!-- #875: cash is never "unassigned" — it has its own
                       target and its own drift; its cell is empty like any
                       cell without a value. --%>
                  <%= cond do %>
                    <% entry.cash? -> %>
                      —
                    <% entry.category_name -> %>
                      <span
                        :if={entry.category_color}
                        class="cat-swatch"
                        style={"background:#{entry.category_color}"}
                        aria-hidden="true"
                      >
                      </span>
                      <%= entry.category_name %>
                    <% true -> %>
                      <span class="hint"><%= gettext("Unassigned") %></span>
                  <% end %>
                </td>
                <td class="num">
                  <%= Format.money(entry.market_value) %>
                  <AppShell.quote_stale :if={stale_flat_entry?(entry)} date={entry.price_date} />
                </td>
                <td class="num"><%= Format.percent(entry.weight) %>%</td>
                <%= if @allocation.has_plan do %>
                  <td class={[
                    "num",
                    "col-subject",
                    drift_negative_class(entry.drift_value)
                  ]}>
                    <%= if entry.drift_value do %>
                      <%= Format.money(entry.drift_value) %>
                      <%= @currency %>
                    <% else %>
                      —
                    <% end %>
                    <.rebalance_hint
                      quantity={entry.rebalance_quantity}
                      quote_date={Map.get(entry, :quote_date)}
                    />
                  </td>
                <% end %>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    <% else %>
      <%!-- #1366: a database without any classification has no
           allocation to wait for: it says so instead of a skeleton
           that never fills. --%>
      <p :if={is_nil(@classification_id)} class="empty-state" data-role="allocation-no-tree">
        <%= gettext("No classification yet.") %>
        <.link navigate="/classifications"><%= gettext("Create one on the Classifications page") %></.link>
      </p>
      <%!-- #723: allocation is a sub-second figure — the block
           skeleton (UX-DR20) carries the wait without the cue. --%>
      <div
        :if={@classification_id}
        class="section-skeleton section-skeleton--allocation"
        data-role="allocation-skeleton"
        aria-busy="true"
      >
      </div>
    <% end %>
    """
  end

  # -- the widget ---------------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/2`'s answer")
  attr(:state, :map, required: true, doc: "the widget's controls (`initial_state/0`)")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Allokation“: Wealth's section in its frame."
  def widget(assigns) do
    assigns =
      assign(assigns,
        id: "dashboard-allocation" <> assigns.item.uid,
        prefix: "dashboard-allocation" <> assigns.item.uid <> "-"
      )

    ~H"""
    <Widget.frame
      id={@id}
      item={@item}
      title={Widgets.title("allocation")}
      class="widget--single-form"
      scope_label={@scope_label}
      full_href={full_href(@item.scope)}
      full_label={gettext("Full view →")}
      full_role="allocation-full-view"
    >
      <:info>
        <%= gettext(
          "The allocation read of the first portfolio in the tree picked, GET /api/v1/portfolios/:id/allocation with classification_id and view: each category's value and actual weight, its target and the drift against it (actual − target; for a plan below 100 % against the allocated portion). The hints beside a drift are arithmetic at the valuation's price, never an order."
        ) %>
      </:info>
      <:switch :if={match?(%{state: :ok, classification_id: id} when not is_nil(id), @card)}>
        <div class="widget-allocation-switch">
          <.controls
            prefix={@prefix}
            item={@item.uid}
            mode={@state.mode}
            classifications={@card.classifications}
            classification_id={@card.classification_id}
          />
        </div>
      </:switch>
      <:shared>
        <div :if={is_nil(@card)} class="section-skeleton section-skeleton--allocation" aria-busy="true" data-role="allocation-skeleton"></div>
        <p :if={@card in [:error, %{state: :no_portfolio}]} class="hint" data-role="allocation-failed">
          <%= gettext("Couldn't load the allocation.") %>
        </p>
        <.body
          :if={match?(%{state: :ok}, @card)}
          prefix={@prefix}
          item={@item.uid}
          allocation={@card.allocation}
          mode={@state.mode}
          classification_id={@card.classification_id}
          selected_segment={@state.selected_segment}
          expanded={@state.expanded}
          parent_map={@card.parent_map}
          parents_with_children={@card.parents_with_children}
          min_drift_pp={@state.min_drift_pp}
          flat_sort={@state.flat_sort}
          currency={@card.allocation && @card.allocation.base_currency}
          view_id={@card.view_id}
          view_name={@card.view_name}
        />
      </:shared>
    </Widget.frame>
    """
  end

  # Wealth's tab on the widget's scope.
  defp full_href(nil), do: "/portfolio?tab=allocation"

  defp full_href(view_id),
    do: "/portfolio?" <> URI.encode_query([{"tab", "allocation"}, {"view", view_id}])

  # -- helpers moved from Wealth (Sprint 32 W2) ---------------------------------------

  # The rows a threshold keeps, for the summary line's count. Same predicate
  # as the table itself, so the number can never disagree with the rows.
  defp threshold_rows(categories, pp),
    do: Enum.filter(categories, &Allocation.drift_at_least?(&1, min_drift_decimal(pp)))

  # The chips speak percentage points because that is how a plan is read
  # ("5 pp off target"); the predicate — and the API's `min_drift=` — speak the
  # weight fraction the drift itself is in. One conversion, here.
  #
  # Which drift: `drift_weight`, the one the Drift column and the dashboard's
  # attention list use. Under ADR-0040 that is measured against the plan
  # renormalised to the allocated portion, so on a plan summing to 83 % the pp
  # a chip filters by is NOT what subtracting the table's raw Target column
  # from its Actual column gives. Deliberate: one number across chips, column,
  # dashboard and API beats a chip that agrees with the columns and with
  # nothing else.
  defp min_drift_decimal(nil), do: nil

  defp min_drift_decimal(pp) when is_binary(pp),
    do: Decimal.div(Decimal.new(pp), 100)

  # The category rows the drift table renders. Without a threshold that is the
  # tree as expanded; with one it is the flat set of rows meeting it, using the
  # SAME predicate as the API's `min_drift=` filter so the two surfaces cannot
  # select different categories. A filtered row is shown regardless of its
  # ancestors' expansion — its parent may well be under the threshold and gone.
  defp visible_category_rows(categories, nil, expanded, parent_map),
    do: Enum.filter(categories, &branch_expanded?(&1.parent_id, expanded, parent_map))

  defp visible_category_rows(categories, %Decimal{} = min_drift, _expanded, _parent_map),
    do: Enum.filter(categories, &Allocation.drift_at_least?(&1, min_drift))

  # #1155 (board 08, N14 = A): a twin's identifier on each position of the
  # tree, the unassigned bucket and so the flat positions, decided over every
  # position of the allocation (the collision key over the whole payload).
  defp with_twin_ids(allocation) do
    unassigned =
      case Map.get(allocation, :unassigned) do
        %{positions: positions} -> positions
        _none -> []
      end

    ids =
      allocation.categories
      |> Enum.flat_map(& &1.positions)
      |> Kernel.++(unassigned)
      |> SecurityNames.put_catalog_twin_ids(& &1.security_name)
      |> Map.new(&{&1.security_id, &1.twin_id})

    put = fn positions ->
      Enum.map(positions, &Map.put(&1, :twin_id, Map.get(ids, &1.security_id)))
    end

    allocation =
      Map.update!(
        allocation,
        :categories,
        &Enum.map(&1, fn row -> Map.update!(row, :positions, put) end)
      )

    case Map.get(allocation, :unassigned) do
      %{positions: _} = bucket -> %{allocation | unassigned: Map.update!(bucket, :positions, put)}
      _none -> allocation
    end
  end

  # A row is visible when every ancestor on its parent chain is expanded -
  # collapsing a category folds away its whole subtree (owner request).
  defp branch_expanded?(nil, _expanded, _parents), do: true

  defp branch_expanded?(category_id, expanded, parents) do
    MapSet.member?(expanded, category_id) and
      branch_expanded?(Map.get(parents, category_id), expanded, parents)
  end

  # A chevron makes sense when the row has direct children to reveal:
  # subcategory rows and/or its own positions.
  defp has_subtree?(row, parents_with_children) do
    MapSet.member?(parents_with_children, row.category_id) or row.positions != []
  end

  # Resolves every category's display colour once: an explicitly chosen colour
  # wins, everything else cycles through the palette in tree order. Downstream
  # consumers (sunburst, legend, drift table) can then rely on `color` being
  # set.
  defp with_display_colors(allocation),
    do: %{allocation | categories: CategoryColors.resolve(allocation.categories)}

  # A drift prints through `Format.money`, so its loss tone is decided at two
  # places (#1149): a drift that reads "0,00" is not an underweight.
  defp drift_negative_class(value),
    do: if(Format.displayed_sign(value, 2) == :negative, do: "is-negative")

  # Concentric rings of annular-sector paths: the innermost ring is the
  # top-level categories, each further ring breaks one level down, the
  # outermost ring shows the individual positions (Portfolio Performance's
  # sunburst). Like PP the slices carry no in-chart text. Each slice exposes
  # data-label/data-value/data-percent that the SunburstTooltip JS hook reads
  # to show an instant custom tooltip on hover (the native <title> stays as a
  # no-JS fallback). Slices are also tappable — `select_segment` echoes the
  # slice below the chart, which is the mobile substitute for hover.
  defp allocation_sunburst(assigns) do
    ~H"""
    <svg
      id={@prefix <> "allocation-sunburst"}
      class="donut sunburst"
      viewBox="0 0 140 140"
      role="img"
      aria-label={gettext("Allocation")}
      phx-hook="SunburstTooltip"
    >
      <%!-- The click payload says `amount`, not `value`: LiveView's client
           overwrites a `phx-value-value` with the element's own DOM value, so
           the name is unusable on anything that has one. Kept uniform here
           even though an SVG path has no `value`, so the rule stays absolute
           and its meta-test needs no exception. --%>
      <%= for {segment, seg_index} <- Enum.with_index(@segments) do %>
        <path
          d={segment.path}
          fill={segment.color}
          fill-opacity={segment.opacity}
          class="sunburst-seg"
          style={"--seg-delay: #{seg_reveal_delay(seg_index, length(@segments))}ms"}
          data-label={segment.name}
          data-percent={segment.percent}
          data-value={text(segment.value)}
          data-target={segment.target}
          phx-click="select_segment"
          phx-value-item={@item}
          phx-value-name={segment.name}
          phx-value-percent={segment.percent}
          phx-value-amount={text(segment.value)}
          phx-value-target={segment.target}
          phx-value-color={segment.color}
        >
          <title><%= segment.name %> · <%= segment.percent %>%</title>
        </path>
      <% end %>
    </svg>
    """
  end

  # A figure written into an attribute for a hook: its text, which in the
  # privacy mode is the constant placeholder text, never the bar's markup
  # (Sprint 26 P1).
  defp text(nil), do: nil
  defp text(value), do: to_string(value)

  # The centre of the sunburst (issue 793, DESIGN.md → Sunburst centre): the
  # touched segment — name, value, actual against target — or, untouched,
  # the reference value the shares are of. A polite live region of real
  # text, so a tap reads out on a touch device where there is no hover; the
  # SunburstTooltip hook paints the hovered slice into it and restores the
  # server's text from the data attributes on leave.
  attr(:centre, :map, required: true)

  defp sunburst_centre(assigns) do
    ~H"""
    <div
      class="sunburst-centre"
      data-role="sunburst-centre"
      aria-live="polite"
      data-label={@centre.label}
      data-value={text(@centre.value)}
      data-sub={@centre.sub}
      data-currency={@centre.currency}
      data-target-word={gettext("target")}
    >
      <span class="sunburst-centre__label"><%= @centre.label %></span>
      <strong class="sunburst-centre__value"><%= PrivacyMode.html(@centre.value) %></strong>
      <span class="sunburst-centre__sub"><%= @centre.sub %></span>
    </div>
    """
  end

  defp sunburst_centre(nil, allocation) do
    %{
      label: gettext("Allocated"),
      value: "#{Format.money(allocation.total_value)} #{allocation.base_currency}",
      sub: "#{Format.percent(Decimal.new(1))} %",
      currency: allocation.base_currency
    }
  end

  defp sunburst_centre(segment, allocation) do
    target =
      case segment.target do
        "" -> ""
        target -> " · #{gettext("target")} #{target} %"
      end

    %{
      label: segment.name,
      value: "#{segment.value} #{allocation.base_currency}",
      sub: "#{segment.percent} %#{target}",
      currency: allocation.base_currency
    }
  end

  # The view the section reads, named on its basis line: its name, or
  # „Alles“ for Everything.
  defp view_name(nil), do: gettext("Everything")
  defp view_name(name) when is_binary(name), do: name

  # Progressive fill (owner pick F1, DESIGN.md → Motion): reveals spread
  # across 1.2s, so with each 0.3s fade the whole build lands at ~1.5s.
  # Opacity only — geometry is final from the first frame.
  defp seg_reveal_delay(_index, count) when count <= 1, do: 0
  defp seg_reveal_delay(index, count), do: div(index * 1200, count)

  defp flip_dir(:desc), do: :asc
  defp flip_dir(:asc), do: :desc

  defp initial_dir(:category), do: :asc
  defp initial_dir(_key), do: :desc

  defp expanded?(expanded_categories, row) do
    MapSet.member?(expanded_categories, row.category_id)
  end

  # Every id the toggle-all button can open: all categories plus the
  # unassigned bucket's sentinel when it exists.
  defp all_expandable_ids(nil), do: MapSet.new()

  defp all_expandable_ids(allocation) do
    ids = MapSet.new(allocation.categories, & &1.category_id)
    if allocation.unassigned, do: MapSet.put(ids, :unassigned), else: ids
  end

  # "Everything expanded" drives the toggle label: only true when there is
  # something to expand and none of it is still collapsed.
  defp all_categories_expanded?(allocation, expanded) do
    all = all_expandable_ids(allocation)
    MapSet.size(all) > 0 and MapSet.subset?(all, expanded)
  end

  # Display-only rebalancing hint (ADR-0023): positive drift = sell, negative
  # = buy, at the valuation's implied unit price. Indicative only — rounded at
  # display (ADR-0016), no fee/tax modelling, never turned into an order.
  # The flat worklist rows: every category's positions (each security is
  # directly assigned to exactly one category per tree, so each appears once),
  # unassigned positions without drift, and the cash row unless cash is
  # distributed into currency buckets. Positions in untargeted categories
  # carry no drift/hint, mirroring the tree's dashes.
  defp flat_positions(allocation, sort) do
    from_categories =
      Enum.flat_map(allocation.categories, fn row ->
        untargeted? = Decimal.equal?(row.target_weight, 0)

        Enum.map(row.positions, fn position ->
          # A position with its own SOLL (ADR-0030 slice 2a) keeps its own
          # drift/hint even in an untargeted category; only the SOLL-less
          # category-share figures are blanked as before.
          own_soll? = not is_nil(position.target_weight)

          Map.merge(position, %{
            category_name: row.name,
            category_color: row.color,
            cash?: false,
            drift_value: if(untargeted? and not own_soll?, do: nil, else: position.drift_value),
            rebalance_quantity:
              if(untargeted? and not own_soll?, do: nil, else: position.rebalance_quantity)
          })
        end)
      end)

    unassigned =
      case allocation.unassigned do
        nil ->
          []

        %{positions: entries} ->
          Enum.map(
            entries,
            &Map.merge(&1, %{category_name: nil, category_color: nil, cash?: false})
          )
      end

    sort_flat(from_categories ++ unassigned ++ flat_cash_entry(allocation), sort)
  end

  # A held entry valued at a stale close is marked beside its value (issue
  # 789) under the one threshold the data-quality finding uses; a retired
  # holding's stopped feed is expected. Trade-priced entries are the
  # finding's own note, not this marker.
  defp stale_flat_entry?(entry) do
    Map.get(entry, :price_source) == :quote and not Map.get(entry, :retired, false) and
      DataQuality.stale_quote?(Map.get(entry, :price_date), Portfolixir.Clock.today())
  end

  defp flat_cash_entry(%{cash: %{distributed: true}}), do: []

  defp flat_cash_entry(%{cash: cash} = allocation) do
    steered? = allocation.has_plan and not Decimal.equal?(cash.target_weight, 0)

    [
      %{
        security_id: :cash,
        security_name: gettext("Cash"),
        quantity: nil,
        market_value: cash.market_value,
        weight: cash.actual_weight,
        drift_value: if(steered?, do: cash.drift_value),
        rebalance_quantity: nil,
        category_name: nil,
        category_color: nil,
        cash?: true,
        held: true,
        stale: false,
        quote_date: nil
      }
    ]
  end

  # Rows without a sortable value (nil drift, no category) sink to the end
  # regardless of direction — the worklist ranks what is actionable.
  defp sort_flat(rows, {key, dir}) do
    {sortable, unsortable} = Enum.split_with(rows, &flat_sort_value(&1, key))
    Enum.sort_by(sortable, &flat_sort_value(&1, key), flat_sorter(key, dir)) ++ unsortable
  end

  # Signed drift (UAT fix round): most-overweight first, most-underweight
  # last — absolute ranking interleaved buys and sells.
  defp flat_sort_value(row, :drift), do: row.drift_value
  defp flat_sort_value(row, :value), do: row.market_value
  defp flat_sort_value(row, :weight), do: row.weight

  defp flat_sort_value(row, :category),
    do: row.category_name && String.downcase(row.category_name)

  # Numeric keys sort as Decimals; the category label is a plain string.
  defp flat_sorter(:category, dir), do: dir
  defp flat_sorter(_key, dir), do: {dir, Decimal}

  defp flat_sort_marker({key, :desc}, key), do: " ↓"
  defp flat_sort_marker({key, :asc}, key), do: " ↑"
  defp flat_sort_marker(_sort, _key), do: ""

  # #911 (c): the ⓘ sentence for a plan that allocates less than 100 %
  # (ADR-0040 §2). The worked figure is the first top-level category the plan
  # steers, its target divided by the allocated sum — the division the drift
  # takes (`Allocation.drift_target/2`); without such a category the sentence
  # names the portion alone.
  defp drift_basis_tip(allocation) do
    sum = allocation.top_level_target_sum

    example =
      Enum.find(allocation.categories, fn row ->
        row.depth == 0 and Map.get(row, :has_target, false) and
          Decimal.gt?(row.target_weight, 0)
      end)

    if example do
      gettext(
        "The plan allocates %{sum}%: each target is scaled up to that portion before the comparison, so %{target}% counts as %{scaled}%. The unallocated rest does not show as drift.",
        sum: Format.percent(sum),
        target: Format.percent(example.target_weight),
        scaled: Format.percent(Decimal.div(example.target_weight, sum))
      )
    else
      gettext(
        "The plan allocates %{sum}%: each target is scaled up to that portion before the comparison. The unallocated rest does not show as drift.",
        sum: Format.percent(sum)
      )
    end
  end

  # Display-only rebalancing hint (ADR-0023), rendered in aligned parts —
  # verb | ≈ | right-aligned quantity | unit — so the columns line up
  # vertically across rows (UAT fix round). An unheld row's hint is priced at
  # a stored quote, so it states that quote's date as its basis (fix round
  # F7/UX-DR11); held rows price at the live valuation and carry no date.
  defp rebalance_hint(assigns) do
    assigns =
      assigns
      |> assign(:parts, rebalance_hint_parts(assigns.quantity))
      |> assign_new(:quote_date, fn -> nil end)

    ~H"""
    <span
      :if={@parts}
      class="rebalance-hint"
      data-role="rebalance-hint"
      title={@quote_date && gettext("at quote from %{date}", date: Format.date(@quote_date))}
    >
      <span class="rebalance-verb"><%= @parts.verb %></span>
      <span class="rebalance-approx">≈</span>
      <span class="rebalance-qty"><%= @parts.quantity %></span>
      <span class="rebalance-unit"><%= gettext("units") %></span>
    </span>
    """
  end

  # Row-level position-SOLL markers (fix round): the stale chip names the row
  # whose SOLL row went stale (UAT — the category badge alone made the reader
  # hunt), the no-quote chip explains a missing unit hint on a SOLL-only row.
  # Text chips, never hue alone (UX-DR7).
  defp position_soll_chips(assigns) do
    ~H"""
    <span
      :if={Map.get(@position, :stale, false)}
      class="stale-chip"
      data-role="stale-target"
      title={
        gettext(
          "This position target is stale: the security was moved or unassigned. It keeps counting under the category it was filed under until re-filed on the Classifications page."
        )
      }
    >
      <%= gettext("stale target") %>
    </span>
    <span
      :if={no_quote?(@position)}
      class="no-quote-chip"
      data-role="no-quote"
      title={gettext("no quote — add a price to get a unit hint")}
    >
      <%= gettext("no quote") %>
    </span>
    <span
      :if={negative_quantity?(@position)}
      class="negative-holding-chip"
      data-role="negative-holding"
      title={
        gettext(
          "The derived holding quantity is negative — likely an unmodeled corporate action from an imported history. Repair the security's transaction history."
        )
      }
    >
      <%= gettext("negative quantity") %>
    </span>
    """
  end

  # Import debris marker (#570): a derived quantity below zero is impossible
  # for a real holding and must not blend into the allocation.
  defp negative_quantity?(%{quantity: %Decimal{} = quantity}),
    do: Decimal.compare(quantity, 0) == :lt

  defp negative_quantity?(_position), do: false

  # Scope-aware not-held chip (fix round): inside a named view "not held"
  # only means "not held in this view"; the plain label is reserved for the
  # Gesamt scope, where it really means not held at all.
  defp not_held_label(nil), do: gettext("not held")
  defp not_held_label(_view_id), do: gettext("not held in this view")

  # A SOLL-only row whose hint cell would stay blank because no quote exists
  # at all (fix round, UAT): quote_date nil distinguishes "no stored quote"
  # from "quote present but unconvertible" (no FX path — no chip, the missing
  # rate is a data-quality concern the FX surfaces own).
  defp no_quote?(position) do
    not position.held and is_nil(position.rebalance_quantity) and
      is_nil(Map.get(position, :quote_date))
  end

  # The Σ header explains a 0% top level that hides a deeper plan (fix round
  # F5): only when no top-level category carries an effective target while
  # deeper categories do.
  defp deep_targets_below?(allocation) do
    deep = Map.get(allocation, :deep_target_sum)

    Decimal.equal?(allocation.top_level_target_sum, 0) and
      not is_nil(deep) and Decimal.compare(deep, 0) == :gt
  end

  # The subcategory-Σ hint only flags a mismatch when the parent actually
  # carries an own weight to compare against (fix round): with no own
  # weight the hint states the children's Σ, and there is nothing to miss.
  defp subcategory_mismatch?(row) do
    not Decimal.equal?(row.target_weight, 0) and
      target_mismatch?(row.child_target_sum, row.target_weight)
  end

  # A position's drift cell renders when the position carries its OWN SOLL
  # (ADR-0030 slice 2a — its drift is actual weight − its target, meaningful
  # even in an otherwise untargeted category), or — for SOLL-less entries —
  # when the category is targeted and a category-share drift exists (the
  # pre-slice behaviour, unchanged).
  defp position_drift_shown?(%{target_weight: %Decimal{}}, _row), do: true

  defp position_drift_shown?(position, row) do
    not Decimal.equal?(row.target_weight, 0) and not is_nil(position.drift_value)
  end

  # The compact text label of the category's position-target badge (UX-DR7:
  # words, never hue alone). Both conditions can hold at once.
  # #719 (D3): the note helpers that replaced the category-cell pill. The
  # "Σ-Konflikt" label died with it — the notes state the consequence in a
  # sentence and name the categories.
  defp conflicted_categories(allocation),
    do: for(row <- allocation.categories, row.conflict, do: row.name)

  defp stale_categories(allocation),
    do: for(row <- allocation.categories, row.has_stale, do: row.name)

  defp plan_overshoot(%{has_plan: true, top_level_target_sum: %Decimal{} = sum}) do
    if Decimal.gt?(sum, 1), do: sum
  end

  defp plan_overshoot(_allocation), do: nil

  defp rebalance_hint_parts(nil), do: nil

  # A hint that rounds to nothing is no hint (#875): "Sell ≈ 0.00 units" asks
  # for an action that is nothing. The drift stays, and the API keeps the
  # unrounded quantity — the suppression is display only.
  defp rebalance_hint_parts(%Decimal{} = quantity) do
    shown = quantity |> Decimal.abs() |> Decimal.round(2)

    cond do
      Decimal.eq?(shown, 0) -> nil
      Decimal.gt?(quantity, 0) -> %{verb: gettext("Sell"), quantity: Format.decimal(shown, 2)}
      true -> %{verb: gettext("Buy"), quantity: Format.decimal(shown, 2)}
    end
  end

  # -- sunburst geometry -------------------------------------------------------

  # The hole is the centre's reading room (issue 793): wide enough for a
  # value at 16 px, so the rings start at 42 % of the outer radius.
  @sunburst_inner 28
  @sunburst_outer 66

  # One annular-sector path per node, ring radii derived from the actual tree
  # depth (categories per level, individual positions outermost) so any tree
  # fits the viewBox. Zero-size slices (a category kept only for its target)
  # render nothing.
  defp sunburst_segments(allocation) do
    nodes = sunburst_nodes(allocation)
    max_depth = nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)
    ring_width = (@sunburst_outer - @sunburst_inner) / (max_depth + 1)

    nodes
    |> Enum.reject(&(&1.fraction_end - &1.fraction_start < 0.0005))
    |> Enum.map(&sector_segment(&1, ring_width))
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
    cash_node = cash_node(allocation.cash, roots ++ unassigned_node)

    max_depth = category_nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)
    security_depth = max_depth + 1

    securities =
      security_nodes(category_nodes, security_depth) ++
        unassigned_security_nodes(allocation.unassigned, unassigned_node, security_depth)

    category_nodes ++ unassigned_node ++ cash_node ++ securities
  end

  # The cash segment: a top-level slice in its own neutral colour for the cash
  # that counts toward the basis (issue #335), placed after the categories and
  # the unassigned remainder. Rendered only when there is counting cash and the
  # cash has not already been distributed into currency buckets (issue #407).
  defp cash_node(%{market_value: value, actual_weight: weight, distributed: false}, preceding) do
    fraction = Decimal.to_float(weight)
    last_end = preceding |> Enum.map(& &1.fraction_end) |> Enum.max(fn -> 0.0 end)

    if fraction > 0.0 do
      [
        %{
          name: gettext("Cash"),
          color: @cash_color,
          percent: Format.percent(weight),
          value: Format.money(value),
          depth: 0,
          opacity: "1.0",
          positions: [],
          fraction_start: last_end,
          fraction_end: last_end + fraction
        }
      ]
    else
      []
    end
  end

  # Cash distributed into currency buckets — no separate sunburst node (issue #407).
  defp cash_node(%{distributed: true}, _preceding), do: []

  defp cash_node(_cash, _preceding), do: []

  defp unassigned_node(nil, _roots), do: []

  # A pot whose value is not positive (import debris, #570 review fix) has no
  # drawable angular span: skip the slice — and with it the outer ring and
  # legend entry — instead of laying its healthy members' arcs over the span
  # the Cash slice occupies.
  defp unassigned_node(%{market_value: value}, _roots)
       when not is_struct(value, Decimal),
       do: []

  defp unassigned_node(%{market_value: value} = unassigned, roots) do
    if Decimal.compare(value, 0) == :gt do
      positive_unassigned_node(unassigned, roots)
    else
      []
    end
  end

  defp positive_unassigned_node(%{actual_weight: weight, market_value: value}, roots) do
    fraction = Decimal.to_float(weight)
    last_root_end = roots |> Enum.map(& &1.fraction_end) |> Enum.max(fn -> 0.0 end)

    [
      %{
        name: gettext("Unassigned"),
        color: @unassigned_color,
        percent: Format.percent(weight),
        value: Format.money(value),
        depth: 0,
        opacity: "1.0",
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
          target: row.target_weight && Format.percent(row.target_weight),
          depth: depth,
          opacity: "1.0",
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

  # No slice was drawn for the pot (non-positive value, #570 review fix):
  # no outer ring either.
  defp unassigned_security_nodes(_unassigned, [], _depth), do: []

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
          opacity: Enum.at(["1.0", "0.72", "0.5"], rem(index, 3)),
          fraction_start: offset,
          fraction_end: offset + fraction
        }

        {node, offset + fraction}
      end)

    nodes
  end

  # Radial padding between rings, so the slices read as separated bands.
  @ring_gap 0.6

  defp sector_segment(node, ring_width) do
    r_in = @sunburst_inner + node.depth * ring_width + @ring_gap
    r_out = @sunburst_inner + (node.depth + 1) * ring_width - @ring_gap

    %{
      name: node.name,
      color: node.color,
      percent: node.percent,
      value: node.value,
      target: Map.get(node, :target),
      opacity: node.opacity,
      path: sector_path(r_in, r_out, node.fraction_start, node.fraction_end)
    }
  end

  # Annular sector: outer arc forward, line inward, inner arc back. A slice of
  # (almost) the full turn keeps a visible notch so the arc endpoints stay
  # distinct after rounding — equal endpoints make SVG drop the arc entirely.
  defp sector_path(r_in, r_out, f0, f1) do
    f1 = min(f1, f0 + 0.9985)
    large = if f1 - f0 > 0.5, do: 1, else: 0
    {x0o, y0o} = polar(r_out, f0)
    {x1o, y1o} = polar(r_out, f1)
    {x0i, y0i} = polar(r_in, f0)
    {x1i, y1i} = polar(r_in, f1)

    "M #{x0o} #{y0o} " <>
      "A #{r2(r_out)} #{r2(r_out)} 0 #{large} 1 #{x1o} #{y1o} " <>
      "L #{x1i} #{y1i} " <>
      "A #{r2(r_in)} #{r2(r_in)} 0 #{large} 0 #{x0i} #{y0i} Z"
  end

  # Fraction of the full turn (0 = twelve o'clock, clockwise) to a point.
  defp polar(radius, fraction) do
    theta = fraction * 2 * :math.pi() - :math.pi() / 2
    {r2(70 + radius * :math.cos(theta)), r2(70 + radius * :math.sin(theta))}
  end

  defp r2(value), do: Float.round(value * 1.0, 2)

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
          percent: Format.percent(row.actual_weight),
          value: Format.money(row.market_value)
        }
      end)

    with_unassigned =
      case allocation.unassigned do
        # No legend entry for a pot without a drawable slice (non-positive
        # value, #570 review fix) — the data-quality report carries it.
        %{actual_weight: weight, market_value: %Decimal{} = value} ->
          if Decimal.compare(value, 0) == :gt do
            roots ++
              [
                %{
                  name: gettext("Unassigned"),
                  color: @unassigned_color,
                  percent: Format.percent(weight),
                  value: Format.money(value)
                }
              ]
          else
            roots
          end

        _ ->
          roots
      end

    # Cash distributed into currency buckets (issue #407): no separate Cash
    # legend entry; the currency category slices already include the cash.
    case allocation.cash do
      %{actual_weight: weight, market_value: value, distributed: false} ->
        if Decimal.compare(weight, 0) == :gt do
          with_unassigned ++
            [
              %{
                name: gettext("Cash"),
                color: @cash_color,
                percent: Format.percent(weight),
                value: Format.money(value)
              }
            ]
        else
          with_unassigned
        end

      _ ->
        with_unassigned
    end
  end

  # Advisory target-consistency check: the children sum vs. the parent target,
  # or the top-level sum vs. 100% (`1`). Exact `Decimal.equal?/2` comparison —
  # a free-form weight is only flagged when it does not match to the stored
  # precision. Display-only; it never blocks saving targets.
  defp target_mismatch?(sum, %Decimal{} = expected) do
    not Decimal.equal?(sum, expected)
  end

  defp target_mismatch?(sum, expected) when is_integer(expected) do
    not Decimal.equal?(sum, Decimal.new(expected))
  end

  # The neutral cash colour, exposed for the template's cash row swatch.
  defp cash_color, do: @cash_color

  # Deep-link into the classifications SOLL editor with the view + classification
  # pre-selected (ADR-0020): the no-plan hint sends the maintainer straight to
  # the right `(view, classification)` plan rather than editing blind. `nil` =
  # the portfolio-wide Gesamt plan ("total"). The view rides along as the view
  # switcher's own `?view=`: since #1091 (pick J10 A) the classification
  # screen's one scope is the active view, and its editor edits that view's
  # plan.
  defp plan_editor_path(classification_id, view_id) do
    "/classifications/#{classification_id}?view=#{view_param(view_id)}"
  end

  defp view_param(nil), do: "total"
  defp view_param(id) when is_integer(id), do: Integer.to_string(id)

  # The basis line names the tree the way the picker above it does: a
  # built-in tree's stored name is English by design (#729), so it localizes
  # at render time rather than reaching the screen as data.
  defp allocation_tree_name(allocation) do
    ClassificationName.display(%{
      key: Map.get(allocation, :classification_key),
      name: allocation.classification_name
    })
  end

  # The colour lands in a style attribute, so only a literal hex colour from
  # our own render is accepted — anything else falls back to neutral grey.
  defp safe_color(value) when is_binary(value) do
    if value =~ ~r/^#[0-9a-fA-F]{6}$/, do: value, else: @fallback_color
  end

  defp safe_color(_value), do: @fallback_color
end
