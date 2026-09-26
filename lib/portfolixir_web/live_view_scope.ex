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

  A `?view=` in the page's own address wins over the session (E25 S7 review
  round, S7E-4): a choice that arrived from another site is kept out of the
  session (`PortfolixirWeb.FetchSite`), so the page it opened reads it from
  its address on both renders, while a live navigation to a page without one
  reads the remembered choice. A remembered choice is in the session too, so
  for it both sources agree.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Portfolixir.Buckets
  alias Portfolixir.Settings

  def on_mount(:default, params, session, socket) do
    views = Buckets.list_views()
    default_view_id = Settings.default_view_id()
    active_view = resolve_active_view(choice(params, session), views, default_view_id)

    {:cont,
     socket
     |> assign(:views, views)
     |> assign(:active_view, active_view)
     |> assign(:active_view_id, active_view && active_view.id)
     |> assign(:default_view_id, default_view_id)}
  end

  defp choice(%{"view" => raw}, _session), do: PortfolixirWeb.ViewScope.choice(raw)
  defp choice(_params, session), do: Map.get(session, PortfolixirWeb.ViewScope.session_key())

  defp resolve_active_view(choice, views, default_view_id) do
    case choice do
      id when is_integer(id) -> Enum.find(views, &(&1.id == id))
      "total" -> nil
      _unset -> default_view_id && Enum.find(views, &(&1.id == default_view_id))
    end
  end
end
