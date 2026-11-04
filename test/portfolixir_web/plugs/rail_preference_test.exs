defmodule PortfolixirWeb.RailPreferenceTest do
  # Sprint 24 P2 (#1357's rail line): the sidebar's collapsed rail is
  # remembered in a preference cookie, written and read the way the
  # benchmark selection's is (`PortfolixirWeb.BenchmarkScope`,
  # `PortfolixirWeb.PreferenceCookie`), and the root layout renders it, so a
  # full page load opens with the rail as the operator left it. The client
  # half (the toggle that asks for the cookie, a live redirect) runs in
  # test/browser/rail_persists_test.exs.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.UiAuth

  @cookie "portfolixir_rail"

  defp from(conn, site), do: put_req_header(conn, "sec-fetch-site", site)

  # The `<html>` start tag of a page, where the remembered rail is rendered.
  defp html_tag(html) do
    [tag] = Regex.run(~r/<html[^>]*>/, html)
    tag
  end

  # The signed cookie a same-origin toggle writes, as the browser sends it
  # back.
  defp remembered_collapsed do
    response = build_conn() |> from("same-origin") |> get("/preferences/rail?rail=collapsed")
    assert response.status == 204
    %{value: value} = Map.fetch!(response.resp_cookies, @cookie)
    @cookie <> "=" <> value
  end

  # User story (Sprint 24 P2, #1357's rail line):
  # As the operator who collapsed the sidebar to its rail,
  # I want the rail to stay collapsed when a link loads a new page,
  # so that the navigation does not open again under my thumb on every page
  # I go to.
  #
  # Acceptance criteria:
  # - The toggle's request (`GET /preferences/rail?rail=collapsed`, same
  #   origin) answers 204 and writes the signed `portfolixir_rail` cookie,
  #   `SameSite=Lax`, `Path=/`, for a year; `?rail=expanded` deletes it.
  # - A page requested with that cookie renders `<html data-rail="collapsed">`
  #   at its first render, before any script runs; without it, no
  #   `data-rail`.
  # - Only the value this server signed, exactly `collapsed`, collapses the
  #   rail: an unsigned cookie, or any other value, renders it expanded, and
  #   the cookie's content is never written into the page.
  # - A cross-site toggle request writes no cookie (`PortfolixirWeb.FetchSite`).
  test "a page requested with the rail cookie renders the rail collapsed, and without it expanded" do
    response = build_conn() |> from("same-origin") |> get("/preferences/rail?rail=collapsed")
    assert response.status == 204

    cookie = Map.fetch!(response.resp_cookies, @cookie)
    assert cookie.same_site == "Lax"
    assert cookie.path == "/"
    assert cookie.max_age == 60 * 60 * 24 * 365
    # Signed: the browser holds a token, not the bare word.
    refute cookie.value == "collapsed"

    {:ok, _view, html} =
      build_conn() |> put_req_header("cookie", remembered_collapsed()) |> live("/")

    assert html_tag(html) =~ ~s(data-rail="collapsed")

    dead = build_conn() |> put_req_header("cookie", remembered_collapsed()) |> get("/securities")
    assert html_tag(html_response(dead, 200)) =~ ~s(data-rail="collapsed")

    {:ok, _view, html} = build_conn() |> live("/")
    refute html_tag(html) =~ "data-rail"

    # A cookie this server did not sign, under the right name and value.
    {:ok, _view, html} =
      build_conn() |> put_req_header("cookie", @cookie <> "=collapsed") |> live("/")

    refute html_tag(html) =~ "data-rail"

    # Expanding again forgets it.
    forgotten = build_conn() |> from("same-origin") |> get("/preferences/rail?rail=expanded")
    assert forgotten.status == 204
    assert %{max_age: 0} = Map.fetch!(forgotten.resp_cookies, @cookie)

    # Another site cannot set it.
    planted = build_conn() |> from("cross-site") |> get("/preferences/rail?rail=collapsed")
    assert planted.status == 204
    refute Map.has_key?(planted.resp_cookies, @cookie)
  end

  test "a value other than collapsed, signed or asked for, leaves the rail expanded" do
    for value <- ["Collapsed", "collapsed ", "1", "true", "<script>", ""] do
      response =
        build_conn()
        |> from("same-origin")
        |> get("/preferences/rail?" <> URI.encode_query(%{"rail" => value}))

      assert response.status == 204
      written = Map.get(response.resp_cookies, @cookie)

      assert written == nil or written.max_age == 0,
             "?rail=#{inspect(value)} wrote #{inspect(written)}"
    end

    # A signed cookie of another value: the layout renders no rail and none
    # of the value.
    secret = PortfolixirWeb.Endpoint.config(:secret_key_base)
    signed = Plug.Crypto.sign(secret, @cookie <> "_cookie", "<b>planted</b>", keys: Plug.Keys)

    {:ok, _view, html} =
      build_conn() |> put_req_header("cookie", @cookie <> "=" <> signed) |> live("/")

    refute html_tag(html) =~ "data-rail"
    refute html =~ "planted"
  end

  test "the rail choice does not ride through the login's return path" do
    assert UiAuth.safe_return_path("/securities?rail=collapsed&tab=quotes") ==
             "/securities?tab=quotes"
  end
end
