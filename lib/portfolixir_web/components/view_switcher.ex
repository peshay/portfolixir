defmodule PortfolixirWeb.ViewSwitcher do
  @moduledoc """
  The active-view switcher shown on the analytics surfaces (issue #446).

  A bucket **view** narrows every figure on the page to the holdings it matches.
  "Everything" (no view) is the built-in default and shows all holdings
  (ADR-0024). The control is a set of plain links — like the locale switcher —
  so picking a view is a full navigation that runs `PortfolixirWeb.ViewScope`,
  persisting the choice in the session and a cookie; the LiveView then mounts
  with that scope. Because it is a cross-page preference, the same choice is in
  force on the next surface too.

  With `show_default_control` the switcher also renders the "set as default"
  affordance (ADR-0024 user-settable default view): a `set_default_view` click
  event for the hosting LiveView when the active selection is not the default,
  or a "Default view" marker when it is.

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

  # The view ids that carry a SOLL plan for the page's active classification
  # (ADR-0020, #468). `nil` in this list marks the Total/Gesamt chip. Optional so
  # surfaces without a classification context render the switcher unchanged.
  attr(:planned_view_ids, :list, default: [])

  # The default-view affordance (ADR-0024): opt-in per surface so pages whose
  # LiveView does not handle `set_default_view` render the switcher unchanged.
  attr(:show_default_control, :boolean, default: false)
  attr(:default_view_id, :any, default: nil)

  def view_switcher(assigns) do
    ~H"""
    <div class="view-switcher" role="group" aria-label={gettext("Active view")}>
      <%!-- #720 (D4): no visible "View:" prefix — the group's aria-label
           keeps the accessible name, and the active chip is what tells a
           sighted reader what the row is for. --%>
      <nav class="view-switcher__options" aria-label={gettext("Active view")}>
        <a
          id="view-switch-total"
          class={["view-chip", is_nil(@active_view) && "is-active"]}
          href={view_href(@current_path, "total")}
          aria-current={if is_nil(@active_view), do: "true", else: nil}
          aria-label={gettext("Everything")}
          data-has-plan={if nil in @planned_view_ids, do: "", else: nil}
          title={plan_marker_title(nil in @planned_view_ids)}
        >
          <%= gettext("Everything") %><span
            :if={nil in @planned_view_ids}
            class="view-chip__plan-dot"
            aria-hidden="true"
          >•</span>
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
            aria-label={view.name}
            data-has-plan={if view.id in @planned_view_ids, do: "", else: nil}
            title={plan_marker_title(view.id in @planned_view_ids)}
          >
            <%= view.name %><span
              :if={view.id in @planned_view_ids}
              class="view-chip__plan-dot"
              aria-hidden="true"
            >•</span>
          </a>
        <% end %>
      </nav>
      <%!-- #720 (D4): a navigation named for its destination, as a quiet
           link — no trailing ellipsis, because in this app's convention an
           ellipsis means "opens a dialog for further input" and this
           navigates to /buckets. --%>
      <a
        class="view-switcher__manage"
        data-role="manage-views"
        href="/buckets"
        title={gettext("Create, rename, and edit views and their buckets")}
      >
        <PortfolixirWeb.AppShell.icon name={:settings} size={13} />
        <%= gettext("Views") %>
      </a>
      <%= if @show_default_control do %>
        <%= if (@active_view && @active_view.id) == @default_view_id do %>
          <span class="hint" data-role="default-view-marker">
            <%= gettext("Default view") %>
          </span>
        <% else %>
          <button
            type="button"
            class="button-mini"
            data-role="set-default-view"
            phx-click="set_default_view"
            title={gettext("Open the Wealth page and dashboard on this view by default")}
          >
            <%= gettext("Set as default") %>
          </button>
        <% end %>
      <% end %>
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

  # Merges `view` into the path's existing query (rather than appending a
  # second `?`), so surface state such as the Wealth tab (ADR-0022) survives
  # a view switch.
  defp view_href(path, view) do
    uri = URI.parse(path)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("view", to_string(view))
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end

  # The accessible name of each chip is pinned to the view name via aria-label
  # (fix round): without it, the plan-dot `title` tooltip could win the
  # accessible-name computation in some AT and announce "Has a target plan…"
  # instead of the view.
  # The `title` below is the plan marker's hover tooltip only (the `•` is
  # aria-hidden).
  defp plan_marker_title(true), do: gettext("Has a target plan for the current classification")
  defp plan_marker_title(false), do: nil
end
