defmodule PortfolixirWeb.LiveViewScope do
  @moduledoc """
  Reads the persisted active bucket **view** into every LiveView (issue #446).

  Mirrors `PortfolixirWeb.LiveLocale`: the `on_mount` hook lifts the active view
  id stored by `PortfolixirWeb.ViewScope` out of the session and assigns it as
  `:active_view_id` (an integer, or `nil` for **Total** — the unscoped default).
  It also assigns `:active_view`, the resolved `Portfolixir.Buckets.View` struct
  (or `nil`), and `:views`, the full list for the switcher control. A stored id
  that no longer names a view degrades gracefully to Total.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Portfolixir.Buckets

  def on_mount(:default, _params, session, socket) do
    views = Buckets.list_views()
    active_view = resolve_active_view(session, views)

    {:cont,
     socket
     |> assign(:views, views)
     |> assign(:active_view, active_view)
     |> assign(:active_view_id, active_view && active_view.id)}
  end

  defp resolve_active_view(session, views) do
    case Map.get(session, PortfolixirWeb.ViewScope.session_key()) do
      id when is_integer(id) -> Enum.find(views, &(&1.id == id))
      _ -> nil
    end
  end
end
