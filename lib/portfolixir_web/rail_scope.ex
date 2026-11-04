defmodule PortfolixirWeb.RailScope do
  @moduledoc """
  Remembers whether the operator collapsed the sidebar to its rail
  (Sprint 24 P2, #1357's rail line), so a full page load opens with the
  rail as it was left.

  Mirrors `PortfolixirWeb.BenchmarkScope`: the choice arrives as
  `?rail=collapsed` or `?rail=expanded` on a plain GET — the rail's toggle
  sends it to `GET /preferences/rail` (`PortfolixirWeb.PreferenceController`)
  — and is kept in a long-lived cookie; the root layout reads the
  `:rail_collapsed` assign this plug sets and renders
  `<html data-rail="collapsed">` before any script runs, so the page never
  shows the expanded sidebar first. Only the exact value `collapsed`
  collapses the rail; any other value of `?rail=` forgets the choice, and a
  remembered cookie is read as collapsed only when it holds exactly that
  word. Nothing of the request's value reaches the page: the layout gets a
  boolean.

  A choice arriving from another site (`Sec-Fetch-Site` other than
  `same-origin` or `none`) is not remembered (`PortfolixirWeb.FetchSite`).
  The cookie is signed, read only when its name appears once, named with the
  `__Host-` prefix over HTTPS and written only past the UI login
  (`PortfolixirWeb.PreferenceCookie`, K02). The rail is chrome, not a
  choice a LiveView reads, so nothing goes into the session: the root
  layout survives a live redirect, and the client keeps the rail there.
  """

  import Plug.Conn

  alias PortfolixirWeb.FetchSite
  alias PortfolixirWeb.PreferenceCookie

  @cookie "portfolixir_rail"
  @collapsed "collapsed"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    case conn.query_params["rail"] do
      nil -> carry_cookie(conn)
      raw -> apply_choice(conn, raw === @collapsed)
    end
  end

  @doc "The cookie name the rail's state is persisted under (over plain HTTP)."
  def cookie_name, do: @cookie

  @doc "Whether the request's page renders the rail collapsed."
  @spec collapsed?(Plug.Conn.t()) :: boolean()
  def collapsed?(%Plug.Conn{assigns: %{rail_collapsed: true}}), do: true
  def collapsed?(_conn), do: false

  defp apply_choice(conn, collapsed) do
    if FetchSite.remember?(conn) do
      conn
      |> assign(:rail_collapsed, collapsed)
      |> remember(collapsed)
    else
      carry_cookie(conn)
    end
  end

  defp remember(conn, true), do: PreferenceCookie.put(conn, @cookie, @collapsed)
  defp remember(conn, false), do: PreferenceCookie.delete(conn, @cookie)

  # Only a value this server signed, and only one of its name, is read
  # (`PortfolixirWeb.PreferenceCookie`, K02).
  defp carry_cookie(conn),
    do: assign(conn, :rail_collapsed, PreferenceCookie.read(conn, @cookie) === @collapsed)
end
