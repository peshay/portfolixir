defmodule PortfolixirWeb.ViewSwitcher do
  @moduledoc """
  The active-view switcher shown on the analytics surfaces (issue #446).

  A bucket **view** narrows every figure on the page to the holdings it matches.
  "Total" (no view) is the default and shows everything. The control is a set of
  plain links — like the locale switcher — so picking a view is a full
  navigation that runs `PortfolixirWeb.ViewScope`, persisting the choice in the
  session and a cookie; the LiveView then mounts with that scope. Because it is a
  cross-page preference, the same choice is in force on the next surface too.

  Per-bucket figures are **overlapping facets**, never a partition: a holding can
  carry several buckets, so two buckets' values can both include it and must not
  be read as a sum. The helper copy states that rule wherever the switcher
  appears.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:current_path, :string, required: true)
  attr(:views, :list, required: true)
  attr(:active_view, :any, default: nil)

  def view_switcher(assigns) do
    ~H"""
    <div class="view-switcher" role="group" aria-label={gettext("Active view")}>
      <span class="view-switcher__label" id="view-switcher-label">
        <%= gettext("View:") %>
      </span>
      <nav class="view-switcher__options" aria-labelledby="view-switcher-label">
        <a
          id="view-switch-total"
          class={["view-chip", is_nil(@active_view) && "is-active"]}
          href={view_href(@current_path, "total")}
          aria-current={if is_nil(@active_view), do: "true", else: nil}
        >
          <%= gettext("Total") %>
        </a>
        <%= for view <- @views do %>
          <a
            id={"view-switch-#{view.id}"}
            class={[
              "view-chip",
              @active_view && @active_view.id == view.id && "is-active"
            ]}
            href={view_href(@current_path, view.id)}
            aria-current={if @active_view && @active_view.id == view.id, do: "true", else: nil}
          >
            <%= view.name %>
          </a>
        <% end %>
      </nav>
      <%= if @views == [] do %>
        <p class="view-switcher__empty" data-role="no-views">
          <%= gettext("No views yet —") %>
          <a href="/buckets"><%= gettext("create one") %></a>
          <%= gettext("to filter this page.") %>
        </p>
      <% end %>
      <%= if @active_view do %>
        <p class="view-switcher__active" data-role="active-view" role="status">
          <%= gettext("Scoped to view: %{name}", name: @active_view.name) %>
        </p>
      <% end %>
      <details class="view-switcher__help">
        <summary aria-label={gettext("About views")}>ⓘ</summary>
        <p role="tooltip">
          <%= gettext(
            "A view narrows every figure on this page to the holdings it matches. Per-bucket figures are overlapping facets, not a partition — a holding can carry several buckets, so their values may overlap and must not be read as a sum."
          ) %>
        </p>
      </details>
    </div>
    """
  end

  defp view_href(path, view) do
    "#{path}?view=#{view}"
  end
end
