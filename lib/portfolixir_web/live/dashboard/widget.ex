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
  (`with_period/3`), and the frame's head says it quietly, as a small
  mark on the title's line (Sprint 32 L1): „3M“, „📌 Max“ in the accent,
  „3M → Quartal“ where the kind reads its nearest window instead (the
  registry's rule, `translated`), the words „folgt ·“ and „eigener:“ for
  a screen reader and in its tooltip; no mark for a kind that takes none.

  **The anatomy** (Sprint 32 L1; board ux-design-2026-11-25-sprint32/07
  ②; DESIGN.md → "The widget anatomy and the one surface"): the frame's
  head on one line in the wide grid (`:switch` holds the widget's own
  switch), its footer one line with a warning as one line above it
  (`:warning`, `warning/1`); in the body the headline figure
  (`figure/1`), the list row (`row/1`) and the bar under comparable
  figures (`bar/1`). The dashboard is one surface, its widgets on
  hairlines (`app.css`). The menu offers „Zeitraum
  festpinnen …“ on a stored dashboard, which opens the top bar's period
  menu for the widget (Sprint 32 T5; an own period pinned by reference,
  `saved:<id>`, a deleted one said in the footer), and „Anpassen“ on a
  template, which is read-only.

  The frame draws no figure of its own: every figure is in the kind's body,
  from the kind's source read.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Clock
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Periods
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Dashboard.MoversCard
  alias PortfolixirWeb.Format

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
  The grid's row template where a „Zeile“ item stands on it (ADR-0062's
  amendment of 2026-11-25, point 3; Sprint 32 S2): `--dashboard-rows`,
  every row of the layout 7rem and the row of each `row` item `auto`, so
  that item is as tall as its content and every row after it starts below
  it (the wide class reads it, `app.css`); `nil` for a layout without one,
  whose rows are the grid's fixed 7rem.
  """
  @spec grid_rows([map()]) :: String.t() | nil
  def grid_rows(items) do
    case for(%{size: "row", row: row} <- items, do: row) do
      [] ->
        nil

      content_rows ->
        last = items |> Enum.map(&(&1.row + &1.h - 1)) |> Enum.max()

        tracks =
          Enum.map_join(1..last, " ", fn row ->
            if row in content_rows, do: "auto", else: "7rem"
          end)

        "--dashboard-rows: #{tracks};"
    end
  end

  @doc """
  A size's short label: the families as they are named (S, M, L, XL), `row`
  as „Zeile“ (Sprint 32 S2), `full` as „Ganz“.
  """
  @spec size_label(String.t()) :: String.t()
  def size_label("row"), do: pgettext("widget size", "Row")
  def size_label("full"), do: pgettext("widget size", "Full")
  def size_label(size), do: size

  @doc """
  The item with its period (ADR-0062 §5): `period`, the period its figures
  are for — its pin where it holds one the kind takes, else the
  dashboard's `dashboard_period` —, `nil` for a kind that takes none;
  `period_state`, `:follows`, `:pinned` or `:none`; `period_label`, its
  label (an own period by its name, looked up in `saved`); `periods`, the
  dashboard periods the kind answers; and `pinnable`, whether its menu may
  pin (a stored dashboard, not a template).

  A pin that no longer resolves dangles (Sprint 32 T5; ADR-0062's
  amendment of 2026-11-25, point 6): an own period since deleted, or a
  quarter or a year not yet begun. The widget then follows the dashboard's
  period and `pin_note` says why, for its footer („eigener Zeitraum
  gelöscht · folgt 1J“); the stored pin is left as it is, and the next save
  drops a deleted period's (`Portfolixir.Dashboards.Layout`).
  """
  @spec with_period(map(), String.t(), boolean(), :stored | [Periods.SavedPeriod.t()]) :: map()
  def with_period(%{kind: kind} = item, dashboard_period, pinnable, saved \\ :stored) do
    periods =
      case Widgets.fetch(kind) do
        {:ok, %{period: %{periods: periods}}} -> periods
        _none -> []
      end

    pin = Map.get(Map.get(item, :settings, %{}), "period")

    {period, state, why} =
      cond do
        periods == [] -> {nil, :none, nil}
        not Widgets.takes_period?(kind, pin) -> {dashboard_period, :follows, nil}
        true -> pin_state(pin, dashboard_period, saved)
      end

    Map.merge(item, %{
      period: period,
      period_state: state,
      period_label: period && period_label(period, saved),
      dashboard_period: dashboard_period,
      dashboard_period_label: period_label(dashboard_period, saved),
      pin_note: pin_note(why, period_label(dashboard_period, saved)),
      periods: periods,
      pinnable: pinnable
    })
  end

  # A pin that resolves today is the widget's period; one that does not
  # dangles, and the widget follows the dashboard's.
  defp pin_state(pin, dashboard_period, saved) do
    case Periods.resolve(pin, Clock.today(), saved) do
      {:ok, _term} -> {pin, :pinned, nil}
      {:error, :not_found} -> {dashboard_period, :follows, :deleted}
      {:error, _not_begun} -> {dashboard_period, :follows, :not_begun}
    end
  end

  defp pin_note(nil, _label), do: nil

  defp pin_note(:deleted, label),
    do: gettext("own period deleted · follows %{period}", period: label)

  defp pin_note(:not_begun, label),
    do: gettext("pinned period not yet begun · follows %{period}", period: label)

  @doc """
  A dashboard period's short label: 1T, 1W, 1M, 3M, 6M, YTD, 1J, 3J, 5J,
  Max; „lfd. Monat“, „Vormonat“, „lfd. Quartal“, „Vorquartal“, „Q1 26“ to
  „Q4 26“ (the current year), „Vorjahr“; a keyed year as its number.
  """
  @spec period_label(String.t()) :: String.t()
  def period_label("1d"), do: gettext("1D")
  def period_label("1w"), do: gettext("1W")
  def period_label("1m"), do: gettext("1M")
  def period_label("3m"), do: gettext("3M")
  def period_label("6m"), do: gettext("6M")
  def period_label("ytd"), do: gettext("YTD")
  def period_label("1y"), do: gettext("1Y")
  def period_label("3y"), do: gettext("3Y")
  def period_label("5y"), do: gettext("5Y")
  def period_label("max"), do: gettext("Max")
  def period_label("mtd"), do: pgettext("period", "This month")
  def period_label("prev_month"), do: pgettext("period", "Last month")
  def period_label("qtd"), do: pgettext("period", "This quarter")
  def period_label("prev_quarter"), do: pgettext("period", "Last quarter")
  def period_label("prev_year"), do: pgettext("period", "Last year")

  def period_label("q" <> n) when n in ~w(1 2 3 4) do
    year = Clock.today().year |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    pgettext("period", "Q%{quarter} %{year}", quarter: n, year: year)
  end

  def period_label("year:" <> year), do: year

  # An own period (Sprint 32 T2) is named by its name; one no longer
  # stored by what it was.
  def period_label("saved:" <> _id = key), do: period_label(key, :stored)

  @doc """
  The label of `key` where an own period (`saved:<id>`) is looked up in
  `saved` (the page's list of `Portfolixir.Periods.SavedPeriod`, or
  `:stored` to read it): its name, „eigener Zeitraum gelöscht“ for one no
  longer there; every other key as `period_label/1` names it.
  """
  @spec period_label(String.t(), :stored | [Periods.SavedPeriod.t()]) :: String.t()
  def period_label("saved:" <> _id = key, saved) do
    with {:ok, id} <- Periods.saved_id(key),
         %{name: name} <- saved_period(id, saved) do
      name
    else
      _gone -> pgettext("period", "Own period deleted")
    end
  end

  def period_label(key, _saved), do: period_label(key)

  defp saved_period(id, :stored), do: Periods.get_saved(id)
  defp saved_period(id, saved) when is_list(saved), do: Enum.find(saved, &(&1.id == id))

  @doc """
  The period tag's words for an item `with_period/3` gave its period:
  „folgt · 3M“, „📌 eigener: Max“, „ohne Zeitraum“, each followed by
  „→ Quartal“ where the kind reads its nearest window instead (its
  registry rule's `translated`); `nil` for an item without its period.
  """
  @spec period_tag(map()) :: String.t() | nil
  def period_tag(%{period_state: :none}), do: gettext("no period")

  def period_tag(%{period_state: :follows} = item),
    do: gettext("follows · %{period}", period: item_label(item)) <> translated(item)

  def period_tag(%{period_state: :pinned} = item),
    do: gettext("own: %{period}", period: item_label(item)) <> translated(item)

  def period_tag(_item), do: nil

  # The period mark (Sprint 32 L1; board 07 ②, 1): the period alone where
  # the eye reads it, the tag's words before it for a screen reader, so
  # the mark's text is the tag's („follows · 1Y“, „📌 own: Max“).
  attr(:item, :map, required: true)

  defp period_mark(assigns) do
    assigns =
      assign(assigns,
        words: period_words_before(assigns.item),
        mark: item_label(assigns.item) <> translated(assigns.item)
      )

    ~H|<span class="visually-hidden"><%= @words %> </span><%= @mark %>|
  end

  defp period_words_before(%{period_state: :follows}), do: pgettext("period mark", "follows ·")
  defp period_words_before(%{period_state: :pinned}), do: pgettext("period mark", "own:")

  # The mark's tooltip: the tag in its words.
  defp period_words(item), do: period_tag(item)

  defp item_label(%{period_label: label}) when is_binary(label), do: label
  defp item_label(%{period: period}), do: period_label(period)

  # „ → Quartal“ where the kind answers the period with another span, by
  # its registry rule; nothing where it answers the period itself.
  defp translated(%{kind: kind, period: period}) do
    with true <- Widgets.translated?(kind, period),
         {:ok, params} <- Widgets.source_params(kind, period, Clock.today()),
         {:ok, %{param: param}} <- Widgets.fetch(kind) |> period_rule(),
         label when is_binary(label) <- source_label(kind, Map.get(params, param)) do
      " → " <> label
    else
      _itself -> ""
    end
  end

  defp period_rule({:ok, %{period: %{} = rule}}), do: {:ok, rule}
  defp period_rule(_none), do: :error

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

  slot(:switch,
    doc: "the widget's own switch, on the head's line before ⋯ (board 07 ②, 1)"
  )

  slot(:warning, doc: "the warning line in the footer (board 07 ②, 6)") do
    attr(:href, :string)
    attr(:link, :string)
    attr(:role, :string)
  end

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
      style={"--widget-col: #{@item.col}; --widget-row: #{@item.row}; --widget-w: #{@item.w}; --widget-h: #{@item.h};" <> edit_sizes_style(@item)}
      aria-labelledby={@title_id}
      {@rest}
    >
      <.edit_bar :if={editing?(@item)} item={@item} title={@title} />
      <%!-- The head on one line (Sprint 32 L1; board
           ux-design-2026-11-25-sprint32/07 ②, 1): the title, cut with an
           ellipsis where its tile is too narrow and whole in its tooltip;
           its ⓘ; the period as a small mark; the widget's own switch; ⋯. --%>
      <div class="section-head widget__head">
        <div class="section-title">
          <h2 id={@title_id} title={@title}><%= @title %></h2>
          <AppShell.section_info :if={@info != []} label={@info_label}>
            <:line :for={line <- @info}><%= render_slot(line) %></:line>
          </AppShell.section_info>
          <%!-- The period mark (ADR-0062 §5; L1): „1J“, „📌 Max“, the
               words „folgt ·“ and „eigener:“ kept for a screen reader and
               in the tooltip. A kind without a period draws none, in the
               edit mode too (board 07 ②, 1: „ohne Zeitraum“ entfällt,
               replacing the Sprint 31 closing act's DS3); its ⋯ menu
               says it. --%>
          <span
            :if={period_tag(@item) && @item.period_state != :none}
            class={["widget__period", "widget__period--#{@item.period_state}"]}
            title={period_words(@item)}
            data-role="widget-period"
            data-period-state={@item.period_state}
          ><span :if={@item.period_state == :pinned} aria-hidden="true">📌 </span><.period_mark item={@item} /></span>
        </div>
        <div :if={@switch != []} class="widget__switch" data-anatomy="switch">
          <%= render_slot(@switch) %>
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
      <%!-- The footer on one line (L1; board 07 ②, 7): the scope at the
           left, one link named for its target at the right; a warning
           as one line above them (②, 6), never a box. --%>
      <footer
        :if={@scope_label || @full_href || Map.get(@item, :pin_note) || @warning != []}
        class="widget__foot"
        data-role="widget-foot"
      >
        <.warning :for={line <- @warning} href={line[:href]} link={line[:link]} role={line[:role]}><%= render_slot(line) %></.warning>
        <span data-role="widget-scope"><%= @scope_label %></span>
        <%!-- Sprint 32 T5: a pin that dangles says why the widget follows. --%>
        <span :if={Map.get(@item, :pin_note)} data-role="widget-pin-dangling"><%= @item.pin_note %></span>
        <a :if={@full_href} href={@full_href} data-role={@full_role}><%= @full_label %></a>
      </footer>
      <.size_switch :if={editing?(@item)} item={@item} title={@title} />
      <.edit_note :if={editing?(@item)} item={@item} />
    </section>
    """
  end

  defp editing?(item), do: Map.get(item, :editing, false)

  # In the edit mode, how many sizes the switch over the footer shows, so
  # the footer keeps room for it (the S32 closing act; board 01 ③).
  defp edit_sizes_style(item) do
    case editing?(item) && Map.get(item, :edit_sizes, []) do
      [_one, _two | _more] = sizes -> " --edit-sizes: #{length(sizes)};"
      _none -> ""
    end
  end

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
      ><%= for part <- say_parts(@note) do %><%= if is_tuple(part) do %><span class="visually-hidden"><%= elem(part, 1) %></span><% else %><%= part %><% end %><% end %></p>
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

  # The note's sentence in its parts (`PortfolixirWeb.Dashboard.Edit`'s
  # `t:say/0`): `{:hidden, text}` for a screen reader only.
  defp say_parts(nil), do: []
  defp say_parts(%{say: say}), do: List.wrap(say)

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
      ><%= size_label(size) %></button>
    </div>
    """
  end

  attr(:item, :map, required: true)
  attr(:title, :string, required: true)

  # The ⋯ menu (board 05 A; Sprint 32 T5, board 04 ③): whether the widget
  # follows the dashboard, and „Zeitraum festpinnen …“, which opens the top
  # bar's period menu for this widget, a pick there stored in the item's
  # settings; on a template, which is read-only, „Anpassen“ in their place;
  # a kind without a period says so. Its choices are buttons the page
  # answers (`pin_menu`, `unpin_period`, `customize`); the menu is a
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
                period: Map.get(@item, :dashboard_period_label) || period_label(@item.dashboard_period)
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
                period: Map.get(@item, :dashboard_period_label) || period_label(@item.dashboard_period)
              ) %>
            </button>
            <%!-- Sprint 32 T5 (board 04 ③): „Zeitraum festpinnen“ opens
                 the top bar's period menu for this widget; a pick there
                 is the pin. --%>
            <button
              type="button"
              id={"widget-pin-open-#{@item.kind}#{@item.uid}"}
              class={["widget__menu-option", @item.period_state == :pinned && "is-active"]}
              phx-click="pin_menu"
              phx-value-index={@item.index}
              aria-pressed={to_string(@item.period_state == :pinned)}
              aria-controls="dashboard-period-menu"
              data-role="pin-menu"
            >
              <%= if @item.period_state == :pinned,
                do: gettext("Pinned: %{period} — change …", period: @item.period_label),
                else: gettext("Pin a period …") %>
            </button>
        <% end %>
      </div>
    </details>
    """
  end

  attr(:href, :string, default: nil)
  attr(:role, :string, default: nil)
  attr(:title, :string, default: nil, doc: "the full name, the label's tooltip")
  attr(:bar_value, :any, default: nil, doc: "the row's figure as a Decimal, for the bar under it")
  attr(:bar_largest, :any, default: nil, doc: "the largest figure listed, which fills 45 %")
  attr(:rest, :global)
  slot(:name, required: true)
  slot(:sub)
  slot(:figure)
  slot(:figure_sub)

  @doc """
  One list row of the anatomy (Sprint 32 L1; board
  ux-design-2026-11-25-sprint32/07 ②, 3 and 4), as the sales review draws
  it: the name at the left on one line — cut with an ellipsis where it
  must, whole in its tooltip (`title`; a row without one, a sentence such
  as a data-quality finding, wraps instead, so nothing of it is lost) —,
  the figure at the right, never
  cut, a muted second line under each where the kind has one; where the
  list's figures are of one kind, the bar under the row (`bar_value`
  against the list's `bar_largest`, `bar/1`). At least 44 px tall in the
  compact forms (board 06). A link when it has an `href`.
  """
  def row(assigns) do
    ~H"""
    <%= if @href do %>
      <a class="widget-row" href={@href} data-role={@role} {@rest}>
        <.row_parts {row_part_assigns(assigns)} />
      </a>
    <% else %>
      <div class="widget-row" data-role={@role} {@rest}>
        <.row_parts {row_part_assigns(assigns)} />
      </div>
    <% end %>
    """
  end

  defp row_part_assigns(assigns),
    do: Map.take(assigns, [:name, :sub, :figure, :figure_sub, :title, :bar_value, :bar_largest])

  attr(:name, :list, required: true)
  attr(:sub, :list, required: true)
  attr(:figure, :list, required: true)
  attr(:figure_sub, :list, required: true)
  attr(:title, :string, required: true)
  attr(:bar_value, :any, required: true)
  attr(:bar_largest, :any, required: true)

  defp row_parts(assigns) do
    ~H"""
    <span class="widget-row__name">
      <span class={["widget-row__label", @title && "is-one-line"]} title={@title}><%= render_slot(@name) %></span>
      <small :if={@sub != []} class="widget-row__sub"><%= render_slot(@sub) %></small>
    </span>
    <span :if={@figure != []} class="widget-row__figure num">
      <%= render_slot(@figure) %>
      <small :if={@figure_sub != []} class="widget-row__sub"><%= render_slot(@figure_sub) %></small>
    </span>
    <.bar :if={@bar_value} value={@bar_value} largest={@bar_largest} class="widget-row__bar" />
    """
  end

  # The share of the track the largest figure listed fills (the
  # contribution table's `@bar_reach`).
  @bar_reach Decimal.new(45)

  attr(:value, :any, required: true, doc: "the figure, a Decimal")
  attr(:largest, :any, required: true, doc: "the largest absolute figure listed")
  attr(:places, :integer, default: 2, doc: "the places the figure is displayed at")
  attr(:class, :string, default: nil)

  @doc """
  The bar under a row of comparable figures (Sprint 32 L1; board 07 ②, 4):
  the contribution table's — the track's centre is 0, a plus grows to the
  right in the gain colour, a minus to the left in the loss colour, and
  the largest figure listed fills 45 % of the track. Decorative
  (aria-hidden): the figure beside it carries the sign and the colour
  (UX-DR7). A figure that reads zero at its places, or a list whose
  largest is zero, draws the track alone. Unlike `.drift-bar`, it is
  kept in the compact forms.
  """
  def bar(assigns) do
    assigns =
      assign(assigns,
        side: bar_side(assigns.value, assigns.places),
        width: bar_width(assigns.value, assigns.largest)
      )

    ~H"""
    <span class={["widget-bar", @class]} aria-hidden="true" data-anatomy="bar"><span
        :if={@side && @width}
        class={["widget-bar__fill", @side]}
        style={"width: #{@width}%"}
      ></span></span>
    """
  end

  defp bar_side(%Decimal{} = value, places) do
    case Format.displayed_sign(value, places) do
      :negative -> "is-under"
      :positive -> "is-over"
      _zero -> nil
    end
  end

  defp bar_side(_value, _places), do: nil

  defp bar_width(%Decimal{} = value, %Decimal{} = largest) do
    if Decimal.eq?(largest, 0) do
      nil
    else
      value
      |> Decimal.abs()
      |> Decimal.div(Decimal.abs(largest))
      |> Decimal.mult(@bar_reach)
      |> Decimal.round(1)
      |> Decimal.to_string(:normal)
    end
  end

  defp bar_width(_value, _largest), do: nil

  attr(:label, :string, default: nil)
  attr(:size, :atom, values: [:s, :m, :secondary], default: :s)
  attr(:sign, :any, default: nil, doc: "a Decimal, :positive or :negative: the figure's sign")
  attr(:role, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true, doc: "the figure")
  slot(:unit, doc: "its currency or unit, smaller after it")
  slot(:sub, doc: "a short muted line under it")

  @doc """
  The headline figure of the anatomy (Sprint 32 L1; board
  ux-design-2026-11-25-sprint32/07 ②, 2): a small label over the figure,
  the figure in one of three sizes — `:s` 28 px, `:m` 34 px as the hero of
  M and up, `:secondary` 24 px —, a short muted line under it. The figure
  is coloured only by its sign (`sign`): a gain or a loss, never to set
  it apart. It never breaks over two lines and is never cut: a tile too
  narrow for it shows less, not a part of it.
  """
  def figure(assigns) do
    assigns = assign(assigns, :sign_class, sign_class(assigns.sign))

    ~H"""
    <div class={["widget-figure", "widget-figure--#{@size}"]} data-anatomy="figure" data-role={@role} {@rest}>
      <span :if={@label} class="widget-figure__label"><%= @label %></span>
      <span class={["widget-figure__value", "num", @sign_class]}><%= render_slot(@inner_block) %><small
          :if={@unit != []}
          class="widget-figure__unit"
        ><%= render_slot(@unit) %></small></span>
      <span :if={@sub != []} class="widget-figure__sub"><%= render_slot(@sub) %></span>
    </div>
    """
  end

  defp sign_class(%Decimal{} = value) do
    cond do
      Decimal.gt?(value, 0) -> "is-positive"
      Decimal.lt?(value, 0) -> "is-negative"
      true -> nil
    end
  end

  defp sign_class(:positive), do: "is-positive"
  defp sign_class(:negative), do: "is-negative"
  defp sign_class(_none), do: nil

  attr(:href, :string, default: nil)
  attr(:link, :string, default: nil, doc: "the link's words, named for its target")
  attr(:role, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  @doc """
  The warning line of the anatomy (Sprint 32 L1; board
  ux-design-2026-11-25-sprint32/07 ②, 6): in a widget a warning is one
  line — „⚠ 3 nicht in der Summe“ and a link to where it is explained —,
  never a box; the box belongs to the data notes and the full view. The
  glyph is aria-hidden, the words carry it. The frame draws it in its
  footer (its `:warning` slot).
  """
  def warning(assigns) do
    ~H"""
    <%!-- Each space is its part's own, so a parser that drops
         whitespace-only text between two elements keeps it. --%>
    <p class="widget-warning" data-anatomy="warning" data-role={@role} {@rest}><span
        class="widget-warning__glyph"
        aria-hidden="true"
      >⚠ </span><span class="widget-warning__text"><%= render_slot(@inner_block) %> </span><a
        :if={@href}
        href={@href}
      ><%= @link %></a></p>
    """
  end
end
