defmodule PortfolixirWeb.Dashboard.Widget do
  @moduledoc """
  The widget's frame and the dashboard's grid (ADR-0062 §1, §4, §6; idea
  board `ux-design-2026-11-21-idea-i56` 01, 03 and 06; planning board
  `ux-design-2026-11-21-sprint31/01` ①; Sprint 31 D3).

  A widget is drawn in five parts (board 01): the **head** — its title, its
  ⓘ with the source's computation basis, its period tag and the ⋯ menu
  (the pin, Sprint 31 D5; the edit actions are D6's) —, the **controls**
  the kind keeps of its own, the **body** in two forms, and the **footer**
  with its scope and the way into the full view or the source screen.
  In the edit mode (ADR-0062 §7; Sprint 31 D6) the ⋯ menu gives way to the
  widget's edit controls: the handle, ×, „nach oben“ and „nach unten“ for
  the compact class, and the size switch at its foot
  (`PortfolixirWeb.Dashboard.Edit` holds the edit).

  The two forms are the wide form, drawn at the item's size on the
  12-column grid, and the compact form, the kind's own narrow layout at
  phone type (§1, §6; board 06), which the medium and compact classes draw.
  Which one shows is CSS's choice, by the window's width and height
  (`.dashboard-grid` in `app.css`), never the device's: nothing of the
  device is read, which an invariant under `test/invariants/` holds. A
  part the two
  forms share — a note, a status region, a control — stands outside both,
  so no id is drawn twice.

  The grid places each item at its `col` and `row` with its size's span
  (`Portfolixir.Dashboards.Widgets.dimensions/1`); the page draws the items
  in reading order (row, then col, §4), which is the order the medium and
  compact classes and a screen reader meet them.

  **The period** (ADR-0062 §5; idea board 05, A; Sprint 31 D5): one
  period above every dashboard, which a widget follows until its ⋯ menu
  pins its own (`settings.period`). The page hands each item its period
  (`with_period/3`), and the frame's head says it quietly: „folgt · 3M“,
  „📌 eigener: Max“ in the accent, „folgt · 3M → Quartal“ where the kind
  reads its nearest window instead (the registry's rule, `translated`),
  „ohne Zeitraum“ for a kind that takes none. The menu offers „Zeitraum
  festlegen“ with the kind's periods on a stored dashboard, and
  „Anpassen“ on a template, which is read-only.

  The frame draws no figure of its own: every figure is in the kind's body,
  from the kind's source read.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Dashboard.MoversCard

  @doc """
  The items of a layout in reading order (row, then col; ADR-0062 §4), each
  with its grid span, an id suffix that keeps the ids of a second item of
  the same kind apart (`""` for the first, `"-2"` for the second, …) and
  its scope: for a kind that takes a view, the item's `settings.view_id`
  where it names one of `views`, else the dashboard's scope `scope_id`,
  marked `dangling` when the item named a view that no longer exists (§2).
  An item of a kind the registry no longer holds is left out. Each keeps
  its `index`, its place in the stored layout, which a write to it (the
  pin) names.
  """
  @spec items([map()], integer() | nil, [map()]) :: [map()]
  def items(layout, scope_id, views) when is_list(layout) do
    view_ids = MapSet.new(views, & &1.id)

    layout
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> registered(item, index) end)
    |> Enum.sort_by(&{&1.row, &1.col})
    |> Enum.map_reduce(%{}, fn item, seen ->
      n = Map.get(seen, item.kind, 0) + 1
      suffix = if n == 1, do: "", else: "-#{n}"

      item =
        item
        |> Map.put(:uid, suffix)
        |> Map.merge(scope_of(item, scope_id, view_ids))

      {item, Map.put(seen, item.kind, n)}
    end)
    |> elem(0)
  end

  defp registered(%{"kind" => kind, "size" => size, "col" => col, "row" => row} = item, index) do
    with {:ok, registered} <- Widgets.fetch(kind),
         {:ok, {w, h}} <- Widgets.dimensions(size) do
      [
        %{
          kind: kind,
          index: index,
          size: size,
          col: col,
          row: row,
          w: w,
          h: h,
          takes_view: registered.scope == :view,
          settings: Map.get(item, "settings") || %{}
        }
      ]
    else
      _unknown -> []
    end
  end

  defp registered(_item, _index), do: []

  defp scope_of(%{takes_view: false}, _scope_id, _view_ids), do: %{scope: nil, dangling: false}

  defp scope_of(%{settings: %{"view_id" => id}}, scope_id, view_ids) when is_integer(id) do
    if MapSet.member?(view_ids, id),
      do: %{scope: id, dangling: false},
      else: %{scope: scope_id, dangling: true}
  end

  defp scope_of(_item, scope_id, _view_ids), do: %{scope: scope_id, dangling: false}

  @doc """
  The item with its period (ADR-0062 §5): `period`, the period its figures
  are for — its pin where it holds one the kind takes, else the
  dashboard's `dashboard_period` —, `nil` for a kind that takes none;
  `period_state`, `:follows`, `:pinned` or `:none`; `periods`, the
  dashboard periods the kind answers (its menu's choices); and
  `pinnable`, whether its menu may pin (a stored dashboard, not a
  template).
  """
  @spec with_period(map(), String.t(), boolean()) :: map()
  def with_period(%{kind: kind} = item, dashboard_period, pinnable) do
    periods =
      case Widgets.fetch(kind) do
        {:ok, %{period: %{periods: periods}}} -> periods
        _none -> []
      end

    pin = Map.get(Map.get(item, :settings, %{}), "period")

    {period, state} =
      cond do
        periods == [] -> {nil, :none}
        is_binary(pin) and pin in periods -> {pin, :pinned}
        true -> {dashboard_period, :follows}
      end

    Map.merge(item, %{
      period: period,
      period_state: state,
      dashboard_period: dashboard_period,
      periods: periods,
      pinnable: pinnable
    })
  end

  @doc "A dashboard period's short label: 1T, 1W, 1M, 3M, YTD, 1J, 3J, Max."
  @spec period_label(String.t()) :: String.t()
  def period_label("1d"), do: gettext("1D")
  def period_label("1w"), do: gettext("1W")
  def period_label("1m"), do: gettext("1M")
  def period_label("3m"), do: gettext("3M")
  def period_label("ytd"), do: gettext("YTD")
  def period_label("1y"), do: gettext("1Y")
  def period_label("3y"), do: gettext("3Y")
  def period_label("max"), do: gettext("Max")

  @doc """
  The period tag's words for an item `with_period/3` gave its period:
  „folgt · 3M“, „📌 eigener: Max“, „ohne Zeitraum“, each followed by
  „→ Quartal“ where the kind reads its nearest window instead (its
  registry rule's `translated`); `nil` for an item without its period.
  """
  @spec period_tag(map()) :: String.t() | nil
  def period_tag(%{period_state: :none}), do: gettext("no period")

  def period_tag(%{period_state: :follows, period: period} = item),
    do: gettext("follows · %{period}", period: period_label(period)) <> translated(item)

  def period_tag(%{period_state: :pinned, period: period} = item),
    do: gettext("own: %{period}", period: period_label(period)) <> translated(item)

  def period_tag(_item), do: nil

  # „ → Quartal“ where the kind answers the period with another span, by
  # its registry rule; nothing where it answers the period itself.
  defp translated(%{kind: kind, period: period}) do
    with {:ok, %{period: %{translated: translated, values: values}}} <- Widgets.fetch(kind),
         true <- period in translated,
         {:ok, value} <- Map.fetch(values, period),
         label when is_binary(label) <- source_label(kind, value) do
      " → " <> label
    else
      _itself -> ""
    end
  end

  # The name of a kind's own window, as the kind names it.
  defp source_label("movers", window), do: MoversCard.window_label(window)
  defp source_label(_kind, _value), do: nil

  attr(:id, :string, required: true)
  attr(:item, :map, required: true)
  attr(:title, :string, required: true)
  attr(:title_id, :string, default: nil)

  attr(:scope_label, :string,
    default: nil,
    doc: "the footer's scope: the view the widget reads, or nil"
  )

  attr(:full_href, :string, default: nil, doc: "the full view or the source screen")
  attr(:full_label, :string, default: nil)
  attr(:full_role, :string, default: nil)
  attr(:info_label, :string, default: nil)
  attr(:class, :string, default: nil)
  attr(:rest, :global)

  slot(:info, doc: "the ⓘ's lines: the source's computation basis")
  slot(:controls, doc: "a control the kind keeps of its own, shared by both forms")
  slot(:shared, doc: "a note or status region both forms show")
  slot(:inner_block, required: true, doc: "the wide form")
  slot(:compact, doc: "the compact form")

  @doc "The frame of one widget on the dashboard (board 01's five parts)."
  def frame(assigns) do
    assigns =
      assigns
      |> assign(:title_id, assigns.title_id || assigns.id <> "-title")
      # The ⓘ names its widget (Sprint 31 closing act, the a11y lens):
      # „Zu „Wertentwicklung““, not one more „Zu diesem Abschnitt“.
      |> assign(
        :info_label,
        assigns.info_label || gettext("About “%{widget}”", widget: assigns.title)
      )

    ~H"""
    <section
      id={@id}
      class={[
        "dashboard-widget",
        "widget--" <> String.downcase(@item.size),
        editing?(@item) && "is-editing",
        Map.get(@item, :moved) && "is-moved",
        @class
      ]}
      data-widget-kind={@item.kind}
      data-moved={if Map.get(@item, :moved), do: "true"}
      data-size={@item.size}
      data-col={@item.col}
      data-row={@item.row}
      style={"--widget-col: #{@item.col}; --widget-row: #{@item.row}; --widget-w: #{@item.w}; --widget-h: #{@item.h};"}
      aria-labelledby={@title_id}
      {@rest}
    >
      <.edit_bar :if={editing?(@item)} item={@item} title={@title} />
      <div class="section-head widget__head">
        <div class="section-title">
          <h2 id={@title_id}><%= @title %></h2>
          <AppShell.section_info :if={@info != []} label={@info_label}>
            <:line :for={line <- @info}><%= render_slot(line) %></:line>
          </AppShell.section_info>
          <%!-- The period tag (ADR-0062 §5): under the title in the wide
               form, at its end in the compact one. „ohne Zeitraum“ only in
               the edit mode, where it helps placing; on the grid the ⋯ menu
               says it (Sprint 31 closing act, DS3; board 02 ①). --%>
          <span
            :if={period_tag(@item) && (@item.period_state != :none or editing?(@item))}
            class={["widget__period", "widget__period--#{@item.period_state}"]}
            data-role="widget-period"
            data-period-state={@item.period_state}
          ><span :if={@item.period_state == :pinned} aria-hidden="true">📌 </span><%= period_tag(@item) %></span>
        </div>
        <%!-- ADR-0062 §5: the ⋯ menu holds the pin (D5); in the edit
             mode (§7, D6) it gives way to the widget's edit controls. --%>
        <.menu :if={not editing?(@item)} item={@item} title={@title} />
      </div>
      <%= render_slot(@controls) %>
      <%= render_slot(@shared) %>
      <div class="widget__wide" data-form="wide">
        <%= render_slot(@inner_block) %>
      </div>
      <div :if={@compact != []} class="widget__compact" data-form="compact">
        <%= render_slot(@compact) %>
      </div>
      <footer
        :if={@scope_label || @full_href}
        class="widget__foot"
        data-role="widget-foot"
      >
        <span data-role="widget-scope"><%= @scope_label %></span>
        <a :if={@full_href} href={@full_href} data-role={@full_role}><%= @full_label %></a>
      </footer>
      <.size_switch :if={editing?(@item)} item={@item} title={@title} />
      <.edit_note :if={editing?(@item)} item={@item} />
    </section>
    """
  end

  defp editing?(item), do: Map.get(item, :editing, false)

  attr(:item, :map, required: true)
  attr(:title, :string, required: true)

  # The edit mode's controls at the widget's top (ADR-0062 §7; board 03):
  # the handle, which a pointer drags on the wide grid (the DashboardEdit
  # hook) and on which the arrow keys move the widget one grid step and
  # Delete removes it (`edit_key`); in the compact class, where no grid is
  # shown, „nach oben“ and „nach unten“ in its place (CSS's choice); and ×.
  # Each names its widget, so a screen reader hears whose control it is,
  # and has an id by the item's key, so the focus can come back to it after
  # a step redraws the grid (`PortfolixirWeb.DashboardLive`, Sprint 31
  # closing act, Y1).
  defp edit_bar(assigns) do
    ~H"""
    <div class="widget__edit" data-role="widget-edit">
      <span class="widget__reorder">
        <button
          type="button"
          id={"dashboard-edit-up-#{@item.edit_key}"}
          class="widget__edit-button"
          phx-click="edit_reorder"
          phx-value-item={@item.edit_key}
          phx-value-direction="up"
          aria-label={gettext("Move %{widget} up", widget: @title)}
          title={gettext("Move %{widget} up", widget: @title)}
          data-role="edit-up"
        ><span aria-hidden="true">↑</span></button>
        <button
          type="button"
          id={"dashboard-edit-down-#{@item.edit_key}"}
          class="widget__edit-button"
          phx-click="edit_reorder"
          phx-value-item={@item.edit_key}
          phx-value-direction="down"
          aria-label={gettext("Move %{widget} down", widget: @title)}
          title={gettext("Move %{widget} down", widget: @title)}
          data-role="edit-down"
        ><span aria-hidden="true">↓</span></button>
      </span>
      <button
        type="button"
        id={"dashboard-edit-handle-#{@item.edit_key}"}
        class="widget__handle"
        phx-keydown="edit_key"
        phx-value-item={@item.edit_key}
        aria-label={gettext("Move %{widget}", widget: @title)}
        aria-describedby={"dashboard-edit-hint dashboard-edit-note-#{@item.edit_key}"}
        title={gettext("Move %{widget}", widget: @title)}
        data-role="edit-handle"
        data-item={@item.edit_key}
      ></button>
      <button
        type="button"
        id={"dashboard-edit-remove-#{@item.edit_key}"}
        class="widget__edit-button widget__remove"
        phx-click="edit_remove"
        phx-value-item={@item.edit_key}
        aria-label={gettext("Remove %{widget}", widget: @title)}
        title={gettext("Remove %{widget}", widget: @title)}
        data-role="edit-remove"
      ><span aria-hidden="true">×</span></button>
    </div>
    """
  end

  attr(:item, :map, required: true)

  # The feedback of the last step, at the widget it acted on (Sprint 32
  # E2; board ux-design-2026-11-25-sprint32/01 ③): a polite live region on
  # every widget in the edit mode, so the region exists before the step
  # it says (the handle names it in its description), and beside it
  # „Rückgängig“ while that step can be taken back. It stands under the
  # widget, over what follows, until the next step.
  defp edit_note(assigns) do
    assigns = assign(assigns, :note, Map.get(assigns.item, :edit_note))

    ~H"""
    <div class={["widget__note", @note && "is-shown"]} data-role="edit-note-box">
      <p
        id={"dashboard-edit-note-#{@item.edit_key}"}
        class="widget__note-text"
        role="status"
        aria-live="polite"
        data-role="edit-note"
      ><%= @note && @note.say %></p>
      <button
        :if={@note && @note.undo}
        type="button"
        class="widget__undo"
        phx-click="edit_undo"
        data-role="edit-undo"
      ><%= gettext("Undo") %></button>
    </div>
    """
  end

  attr(:item, :map, required: true)
  attr(:title, :string, required: true)

  # The size switch (board 03, at the widget's foot): the grid sizes its
  # kind takes, its own pressed; none where the kind takes one size.
  defp size_switch(assigns) do
    ~H"""
    <div
      :if={length(@item.edit_sizes) > 1}
      class="widget__sizes"
      role="group"
      aria-label={gettext("Size of %{widget}", widget: @title)}
    >
      <button
        :for={size <- @item.edit_sizes}
        type="button"
        id={"dashboard-edit-size-#{@item.edit_key}-#{size}"}
        class={["widget__size", size == @item.size && "is-active"]}
        phx-click="edit_resize"
        phx-value-item={@item.edit_key}
        phx-value-size={size}
        aria-pressed={to_string(size == @item.size)}
        data-role="edit-size"
        data-size={size}
      ><%= size %></button>
    </div>
    """
  end

  attr(:item, :map, required: true)
  attr(:title, :string, required: true)

  # The ⋯ menu (board 05 A): whether the widget follows the dashboard, and
  # „Zeitraum festlegen“ with the kind's periods, each a pin stored in the
  # item's settings; on a template, which is read-only, „Anpassen“ in their
  # place; a kind without a period says so. Its choices are buttons the
  # page answers (`pin_period`, `unpin_period`, `customize`); the menu is a
  # disclosure the browser holds.
  defp menu(assigns) do
    ~H"""
    <details class="widget__menu" data-role="widget-menu">
      <summary
        aria-label={gettext("Menu for “%{widget}”", widget: @title)}
        title={gettext("Menu for “%{widget}”", widget: @title)}
      >
        <span aria-hidden="true">⋯</span>
      </summary>
      <div class="widget__menu-panel">
        <%= cond do %>
          <% Map.get(@item, :period_state) in [nil, :none] -> %>
            <p class="widget__menu-note"><%= gettext("This widget has no period.") %></p>
          <% not @item.pinnable -> %>
            <p class="widget__menu-note">
              <%= gettext("Follows the dashboard (%{period})",
                period: period_label(@item.dashboard_period)
              ) %>
            </p>
            <button
              type="button"
              class="widget__menu-option"
              phx-click="customize"
              data-role="menu-customize"
            >
              <%= gettext("Customize") %>
            </button>
            <p class="widget__menu-note">
              <%= gettext("A template is read-only; only its copy takes a period of its own per widget.") %>
            </p>
          <% true -> %>
            <button
              type="button"
              class={["widget__menu-option", @item.period_state == :follows && "is-active"]}
              phx-click="unpin_period"
              phx-value-index={@item.index}
              aria-pressed={to_string(@item.period_state == :follows)}
              data-role="unpin-period"
            >
              <%= gettext("Follows the dashboard (%{period})",
                period: period_label(@item.dashboard_period)
              ) %>
            </button>
            <p class="widget__menu-head" id={"widget-pin-#{@item.kind}#{@item.uid}"}>
              <%= gettext("Set period") %>
            </p>
            <div
              class="widget__menu-periods"
              role="group"
              aria-labelledby={"widget-pin-#{@item.kind}#{@item.uid}"}
            >
              <button
                :for={period <- @item.periods}
                type="button"
                class={[
                  "widget__menu-period",
                  @item.period_state == :pinned and @item.period == period && "is-active"
                ]}
                phx-click="pin_period"
                phx-value-index={@item.index}
                phx-value-period={period}
                aria-pressed={to_string(@item.period_state == :pinned and @item.period == period)}
                data-role="pin-period"
                data-period={period}
              >
                <%= period_label(period) %>
              </button>
            </div>
        <% end %>
      </div>
    </details>
    """
  end

  attr(:href, :string, default: nil)
  attr(:role, :string, default: nil)
  attr(:rest, :global)
  slot(:name, required: true)
  slot(:sub)
  slot(:figure)
  slot(:figure_sub)

  @doc """
  One row of a compact form (board 06): one name and one figure on the
  line, a second line under each, the row at least 44 px tall. A link when
  it has an `href`.
  """
  def row(assigns) do
    ~H"""
    <%= if @href do %>
      <a class="widget-row" href={@href} data-role={@role} {@rest}>
        <.row_parts name={@name} sub={@sub} figure={@figure} figure_sub={@figure_sub} />
      </a>
    <% else %>
      <div class="widget-row" data-role={@role} {@rest}>
        <.row_parts name={@name} sub={@sub} figure={@figure} figure_sub={@figure_sub} />
      </div>
    <% end %>
    """
  end

  attr(:name, :list, required: true)
  attr(:sub, :list, required: true)
  attr(:figure, :list, required: true)
  attr(:figure_sub, :list, required: true)

  defp row_parts(assigns) do
    ~H"""
    <span class="widget-row__name">
      <%= render_slot(@name) %>
      <small :if={@sub != []} class="widget-row__sub"><%= render_slot(@sub) %></small>
    </span>
    <span :if={@figure != []} class="widget-row__figure num">
      <%= render_slot(@figure) %>
      <small :if={@figure_sub != []} class="widget-row__sub"><%= render_slot(@figure_sub) %></small>
    </span>
    """
  end
end
