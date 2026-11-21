defmodule PortfolixirWeb.Dashboard.Widget do
  @moduledoc """
  The widget's frame and the dashboard's grid (ADR-0062 §1, §4, §6; idea
  board `ux-design-2026-11-21-idea-i56` 01, 03 and 06; planning board
  `ux-design-2026-11-21-sprint31/01` ①; Sprint 31 D3).

  A widget is drawn in five parts (board 01): the **head** — its title, its
  ⓘ with the source's computation basis and the ⋯ menu (a placeholder in
  this slice: the pin is D5's, the edit actions D6's) —, the **controls**
  the kind keeps of its own, the **body** in two forms, and the **footer**
  with its scope and the way into the full view or the source screen.

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

  The frame draws no figure of its own: every figure is in the kind's body,
  from the kind's source read.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.AppShell

  @doc """
  The items of a layout in reading order (row, then col; ADR-0062 §4), each
  with its grid span, an id suffix that keeps the ids of a second item of
  the same kind apart (`""` for the first, `"-2"` for the second, …) and
  its scope: for a kind that takes a view, the item's `settings.view_id`
  where it names one of `views`, else the dashboard's scope `scope_id`,
  marked `dangling` when the item named a view that no longer exists (§2).
  An item of a kind the registry no longer holds is left out.
  """
  @spec items([map()], integer() | nil, [map()]) :: [map()]
  def items(layout, scope_id, views) when is_list(layout) do
    view_ids = MapSet.new(views, & &1.id)

    layout
    |> Enum.flat_map(&registered/1)
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

  defp registered(%{"kind" => kind, "size" => size, "col" => col, "row" => row} = item) do
    with {:ok, registered} <- Widgets.fetch(kind),
         {:ok, {w, h}} <- Widgets.dimensions(size) do
      [
        %{
          kind: kind,
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

  defp registered(_item), do: []

  defp scope_of(%{takes_view: false}, _scope_id, _view_ids), do: %{scope: nil, dangling: false}

  defp scope_of(%{settings: %{"view_id" => id}}, scope_id, view_ids) when is_integer(id) do
    if MapSet.member?(view_ids, id),
      do: %{scope: id, dangling: false},
      else: %{scope: scope_id, dangling: true}
  end

  defp scope_of(_item, scope_id, _view_ids), do: %{scope: scope_id, dangling: false}

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
    assigns = assign(assigns, :title_id, assigns.title_id || assigns.id <> "-title")

    ~H"""
    <section
      id={@id}
      class={["dashboard-widget", "widget--" <> String.downcase(@item.size), @class]}
      data-widget-kind={@item.kind}
      data-size={@item.size}
      data-col={@item.col}
      data-row={@item.row}
      style={"--widget-col: #{@item.col}; --widget-row: #{@item.row}; --widget-w: #{@item.w}; --widget-h: #{@item.h};"}
      aria-labelledby={@title_id}
      {@rest}
    >
      <div class="section-head widget__head">
        <div class="section-title">
          <h2 id={@title_id}><%= @title %></h2>
          <AppShell.section_info :if={@info != []} label={@info_label}>
            <:line :for={line <- @info}><%= render_slot(line) %></:line>
          </AppShell.section_info>
        </div>
        <%!-- ADR-0062 §5, §7: the ⋯ menu holds the pin (D5) and the edit
             actions (D6); in this slice it is drawn and offers nothing. --%>
        <button
          type="button"
          class="widget__menu"
          data-role="widget-menu"
          aria-label={gettext("Widget menu")}
          title={gettext("Widget menu")}
          disabled
        >
          <span aria-hidden="true">⋯</span>
        </button>
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
    </section>
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
