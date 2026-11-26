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

  „Crashes im Vergleich“ (`crashes`, L) stays its compact relative: the
  windows side by side, one figure each.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Risk.CrashSection

  attr(:item, :map, required: true)
  attr(:portfolio, :any, required: true, doc: "the first portfolio, or nil without one")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Crashes“: the tab's section, embedded."
  def widget(assigns) do
    assigns = assign(assigns, :id, "dashboard-crash-section" <> assigns.item.uid)

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
      <:shared>
        <.live_component
          module={CrashSection}
          id={@id <> "-section"}
          params={if @item.scope, do: %{"view" => Integer.to_string(@item.scope)}, else: %{}}
          view_id={@item.scope}
          base_currency={@portfolio && @portfolio.base_currency_code}
          catalogue_only={is_nil(@portfolio)}
          embedded={true}
        />
      </:shared>
    </Widget.frame>
    """
  end
end
