defmodule PortfolixirWeb.ViewScope do
  @moduledoc """
  Persists the active bucket **view** across pages (issue #446).

  Mirrors `PortfolixirWeb.Locale`: the active view is a cross-page UI preference,
  carried by a `?view=` query parameter on a full navigation, stored in the
  session (so the LiveView mount can read it) and in a long-lived cookie (so the
  choice survives a new session).

  `?view=total` stores the literal `"total"` — an **explicit** choice of the
  built-in Everything scope. It must stay distinguishable from "never chose
  anything", because with a user-settable default view (ADR-0024) the unset
  state falls back to the default while an explicit Everything must not. A
  malformed value clears the preference back to unset.

  The plug only validates the *shape* of the value (a positive integer id, or the
  literal `"total"`); whether an id still names a live view is decided where the
  scope is loaded, so a deleted view degrades gracefully.

  A choice arriving from another site (`Sec-Fetch-Site` other than
  `same-origin` or `none`) applies to that request only and leaves the cookie
  and the session as they were (`PortfolixirWeb.FetchSite`, E25 S7, F18 and
  the review round's S7E-4): the page it opens reads it from its own address
  (`PortfolixirWeb.LiveViewScope`), so a live navigation from that page shows
  the remembered view.
  """

  import Plug.Conn

  alias PortfolixirWeb.FetchSite

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

  @doc """
  The choice a raw `?view=` value names, in the shape the session holds: a
  positive integer id, `"total"` (an explicit Everything), or `nil` (unset,
  for a malformed value).
  """
  @spec choice(term()) :: pos_integer() | String.t() | nil
  def choice(raw), do: normalize(raw)

  # An explicit `?view=` was supplied. When the request may remember it
  # (`PortfolixirWeb.FetchSite`, E25 S7, F18), the (validated) choice goes
  # into the session for this request and into the cookie the next request
  # rebuilds the session from; a malformed value clears the choice back to
  # unset the same way. Otherwise the session keeps the remembered choice
  # (S7E-4) and the page reads its own from its address.
  defp apply_choice(conn, choice) do
    if FetchSite.remember?(conn) do
      conn
      |> put_session(@session_key, choice)
      |> remember(choice)
    else
      carry_cookie(conn)
    end
  end

  defp remember(conn, nil), do: delete_resp_cookie(conn, @cookie)

  defp remember(conn, "total"),
    do: put_resp_cookie(conn, @cookie, "total", max_age: @max_age, same_site: "Lax")

  defp remember(conn, view_id) when is_integer(view_id) do
    put_resp_cookie(conn, @cookie, Integer.to_string(view_id),
      max_age: @max_age,
      same_site: "Lax"
    )
  end

  defp carry_cookie(conn) do
    case normalize(conn.cookies[@cookie]) do
      nil -> put_session(conn, @session_key, nil)
      choice -> put_session(conn, @session_key, choice)
    end
  end

  # A positive integer id, the literal "total" (explicit Everything), or nil
  # (unset — the default-view fallback applies at mount).
  defp normalize("total"), do: "total"

  defp normalize(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp normalize(_value), do: nil
end
