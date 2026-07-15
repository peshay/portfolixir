defmodule PortfolixirWeb.LiveViewScope do
  @moduledoc """
  Reads the persisted active bucket **view** into every LiveView (issue #446).

  Mirrors `PortfolixirWeb.LiveLocale`: the `on_mount` hook lifts the active view
  choice stored by `PortfolixirWeb.ViewScope` out of the session and assigns it
  as `:active_view_id` (an integer, or `nil` for **Everything** — the unscoped
  built-in). It also assigns `:active_view`, the resolved
  `Portfolixir.Buckets.View` struct (or `nil`), `:views`, the full list for the
  switcher control, and `:default_view_id`, the user's persisted default view
  preference (ADR-0024).

  Resolution order (ADR-0024 user-settable default): an explicit choice — a
  stored view id or the literal `"total"` (Everything) — always wins; only when
  nothing was ever chosen does the persisted default view apply. A stored or
  default id that no longer names a view degrades gracefully to Everything.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Portfolixir.Buckets
  alias Portfolixir.Settings

  def on_mount(:default, _params, session, socket) do
    views = Buckets.list_views()
    default_view_id = Settings.default_view_id()
    active_view = resolve_active_view(session, views, default_view_id)

    {:cont,
     socket
     |> assign(:views, views)
     |> assign(:active_view, active_view)
     |> assign(:active_view_id, active_view && active_view.id)
     |> assign(:default_view_id, default_view_id)}
  end

  defp resolve_active_view(session, views, default_view_id) do
    case Map.get(session, PortfolixirWeb.ViewScope.session_key()) do
      id when is_integer(id) -> Enum.find(views, &(&1.id == id))
      "total" -> nil
      _unset -> default_view_id && Enum.find(views, &(&1.id == default_view_id))
    end
  end
end
