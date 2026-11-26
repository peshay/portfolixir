defmodule PortfolixirWeb.Dashboard.Widgets.CrashWindows do
  @moduledoc """
  The section widget „Crashes“ `crash_section` (I57; Sprint 32 W4;
  ADR-0058 §9; ADR-0062's amendment of 2026-11-25, points 3 and 7;
  planning board `ux-design-2026-11-25-sprint32/02` ②): the Risk tab's
  whole section „Crashes“ in its frame. The section is one code path on
  both: `PortfolixirWeb.Risk.CrashSection`, the tab's component, drawn here
  embedded (its `embedded` mode): the window's select, the list (Verlierer,
  Gewinner, Erholer) and the universe (Im Depot, Ganzer Katalog), the
  window line and the ranked list as `Portfolixir.Crashes.rankings/3`
  answers them (`GET /api/v1/crashes/:key/rankings`), the choice kept in
  the widget for the page's life. The crash benchmark, the windows and
  their names are set on the tab, linked.

  **The head** (the S32 closing act, PR 2's design critic; board 07 ②
  1): „Liste“ (Verlierer, Gewinner, Erholer) and „Wertpapiere“ (Im Depot,
  Ganzer Katalog) are the frame's switch on the head's line, as the tab
  sets them on one line, and the section is drawn without the tab's
  `section.workspace-section`, so its padding, fill and hairline do not
  stand inside the widget. The dashboard keeps the choice per widget
  (`dom_id/1`) and hands it to the section as `choice`; the window's
  select stays in the body, the section's own.

  „Crashes im Vergleich“ (`crashes`, L) stays its compact relative: the
  windows side by side, one figure each.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Risk.CrashSection

  @keys ~w(crash_list crash_universe)

  @doc "The frame's id of the widget `item`, by which the dashboard keeps its choice."
  @spec dom_id(map()) :: String.t()
  def dom_id(item), do: "dashboard-crash-section" <> item.uid

  @doc "Whether `choice` is a list or a universe the section answers, under its `key`."
  @spec choice?(term(), term()) :: boolean()
  def choice?("crash_list", choice), do: choice in Enum.map(CrashSection.lists(), &elem(&1, 0))

  def choice?("crash_universe", choice),
    do: choice in Enum.map(CrashSection.universes(), &elem(&1, 0))

  def choice?(_key, _choice), do: false

  attr(:item, :map, required: true)
  attr(:portfolio, :any, required: true, doc: "the first portfolio, or nil without one")
  attr(:scope_label, :string, default: nil)

  attr(:choice, :map,
    default: %{},
    doc: "the list and the universe picked in the head, `crash_list` and `crash_universe`"
  )

  @doc "The widget „Crashes“: the tab's section, embedded, its list and universe in the head."
  def widget(assigns) do
    choice = Map.take(assigns.choice, @keys)
    catalogue_only = is_nil(assigns.portfolio)

    assigns =
      assign(assigns,
        id: dom_id(assigns.item),
        choice: choice,
        catalogue_only: catalogue_only,
        list: Map.get(choice, "crash_list", "losers"),
        # Without a portfolio the section reads the whole catalogue (#1366).
        universe:
          if(catalogue_only, do: "catalogue", else: Map.get(choice, "crash_universe", "depot"))
      )

    ~H"""
    <Widget.frame
      id={@id}
      item={@item}
      title={Widgets.title("crash_section")}
      class="widget--single-form"
      scope_label={@scope_label}
      full_href="/risk"
      full_label={gettext("Full view →")}
      full_role="crash-section-full-view"
    >
      <:info :for={line <- CrashSection.info_lines()}><%= line %></:info>
      <:switch>
        <div class="segmented-control widget-switch" role="group" aria-label={pgettext("crash", "List")} data-role="crash-list">
          <button
            :for={{list, label} <- CrashSection.lists()}
            type="button"
            class={["segmented-control__option", @list == list && "is-active"]}
            data-list={list}
            aria-pressed={to_string(@list == list)}
            phx-click="crash_section_pick"
            phx-value-widget={@id}
            phx-value-key="crash_list"
            phx-value-choice={list}
          ><%= label %></button>
        </div>
        <div
          :if={not @catalogue_only}
          class="segmented-control widget-switch"
          role="group"
          aria-label={gettext("Securities")}
          data-role="crash-universe"
        >
          <button
            :for={{universe, label} <- CrashSection.universes()}
            type="button"
            class={["segmented-control__option", @universe == universe && "is-active"]}
            data-universe={universe}
            aria-pressed={to_string(@universe == universe)}
            phx-click="crash_section_pick"
            phx-value-widget={@id}
            phx-value-key="crash_universe"
            phx-value-choice={universe}
          ><%= label %></button>
        </div>
      </:switch>
      <:shared>
        <.live_component
          module={CrashSection}
          id={@id <> "-section"}
          params={if @item.scope, do: %{"view" => Integer.to_string(@item.scope)}, else: %{}}
          view_id={@item.scope}
          base_currency={@portfolio && @portfolio.base_currency_code}
          catalogue_only={@catalogue_only}
          embedded={true}
          choice={@choice}
        />
      </:shared>
    </Widget.frame>
    """
  end
end
