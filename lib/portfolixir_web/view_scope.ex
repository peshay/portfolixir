defmodule PortfolixirWeb.ViewScope do
  @moduledoc """
  Persists the active bucket **view** across pages (issue #446).

  Mirrors `PortfolixirWeb.Locale`: the active view is a cross-page UI preference,
  carried by a `?view=` query parameter on a full navigation, stored in the
  session (so the LiveView mount can read it) and in a long-lived cookie (so the
  choice survives a new session). `?view=total` (or any unknown id) clears the
  preference back to **Total** — the unscoped default.

  The plug only validates the *shape* of the value (a positive integer id, or the
  literal `"total"`); whether the id still names a live view is decided where the
  scope is loaded, so a deleted view degrades gracefully to Total.
  """

  import Plug.Conn

  @cookie "portfolixir_view"
  @session_key "active_view_id"
  # 1 year, same horizon as the locale cookie.
  @max_age 60 * 60 * 24 * 365

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    case conn.query_params["view"] do
      nil ->
        # No explicit choice on this request: keep whatever the cookie holds so
        # the preference persists across navigations (the session is rebuilt
        # from the cookie on every request).
        carry_cookie(conn)

      raw ->
        apply_choice(conn, normalize(raw))
    end
  end

  @doc "The session key the LiveView on_mount reads the active view id from."
  def session_key, do: @session_key

  @doc "The cookie name the active view id is persisted under."
  def cookie_name, do: @cookie

  # An explicit `?view=` was supplied: store the (validated) choice in both the
  # session and the cookie. `nil` (Total) clears both.
  defp apply_choice(conn, nil) do
    conn
    |> put_session(@session_key, nil)
    |> delete_resp_cookie(@cookie)
  end

  defp apply_choice(conn, view_id) when is_integer(view_id) do
    conn
    |> put_session(@session_key, view_id)
    |> put_resp_cookie(@cookie, Integer.to_string(view_id),
      max_age: @max_age,
      same_site: "Lax"
    )
  end

  defp carry_cookie(conn) do
    case normalize(conn.cookies[@cookie]) do
      nil -> put_session(conn, @session_key, nil)
      view_id -> put_session(conn, @session_key, view_id)
    end
  end

  # "total" (and anything that is not a positive integer) means Total/unscoped.
  defp normalize(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp normalize(_value), do: nil
end
