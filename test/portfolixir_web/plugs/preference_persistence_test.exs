defmodule PortfolixirWeb.PreferencePersistenceTest do
  # E25 S7, F18: the view, benchmark and locale choices arrive as query
  # parameters on a plain GET, so any site could link the operator's browser
  # to `/?view=…` and rewrite the stored UI scope. A choice is remembered only
  # when the browser says the request came from this origin, from the address
  # bar or a bookmark, or does not say (an older browser, a script).
  use PortfolixirWeb.ConnCase

  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.ViewScope

  @view_cookie "portfolixir_view"
  @benchmark_cookie "portfolixir_benchmarks"
  @locale_cookie "portfolixir_locale"

  defp from(conn, site), do: put_req_header(conn, "sec-fetch-site", site)

  # User story:
  # As an operator whose browser also visits other sites,
  # I want a link on another site to change what my page shows at most for
  # the page it opens,
  # so that no other site can rewrite the view, benchmarks or language my
  # instance remembers for me.
  #
  # Acceptance criteria:
  # - A cross-site or same-site GET carrying ?view=, ?benchmark[]= /
  #   ?benchmark_rate= or ?locale= sets no preference cookie and deletes none;
  #   the value applies to that request only.
  # - The stored choice is what the next request without a parameter reads.
  # - A GET whose Sec-Fetch-Site is same-origin or none, or that carries none,
  #   still remembers the choice.
  test "a cross-site GET applies a view, benchmark and locale to itself only", %{conn: conn} do
    stored =
      conn
      |> put_req_cookie(@view_cookie, "total")
      |> put_req_cookie(@benchmark_cookie, "rate:0.02")
      |> put_req_cookie(@locale_cookie, "en")

    for site <- ["cross-site", "same-site"] do
      response =
        stored
        |> from(site)
        |> get("/?view=7&benchmark[]=security:9&locale=de")

      refute Map.has_key?(response.resp_cookies, @view_cookie), site
      refute Map.has_key?(response.resp_cookies, @benchmark_cookie), site
      refute Map.has_key?(response.resp_cookies, @locale_cookie), site

      # The request itself is answered in the choice it carried.
      assert html_response(response, 200) =~ ~s(lang="de")
      assert get_session(response, ViewScope.session_key()) == 7
      assert get_session(response, BenchmarkScope.session_key()) == ["security:9"]
    end

    # The next request without a parameter reads the stored choices.
    next = stored |> from("same-origin") |> get("/")
    assert get_session(next, ViewScope.session_key()) == "total"
    assert get_session(next, BenchmarkScope.session_key()) == ["rate:0.02"]
    assert html_response(next, 200) =~ ~s(lang="en")
  end

  test "a cross-site GET with a malformed or empty choice deletes no stored preference",
       %{conn: conn} do
    response =
      conn
      |> put_req_cookie(@view_cookie, "5")
      |> put_req_cookie(@benchmark_cookie, "security:3")
      |> from("cross-site")
      |> get("/?view=nope&benchmark_rate=")

    refute Map.has_key?(response.resp_cookies, @view_cookie)
    refute Map.has_key?(response.resp_cookies, @benchmark_cookie)
    assert get_session(response, ViewScope.session_key()) == nil
    assert get_session(response, BenchmarkScope.session_key()) == []
  end

  test "a same-origin, typed or unlabelled GET remembers the choice", %{conn: conn} do
    for site <- ["same-origin", "none", nil] do
      request = if site, do: from(conn, site), else: conn
      response = get(request, "/?view=7&benchmark[]=security:9&locale=de")

      assert %{value: "7"} = response.resp_cookies[@view_cookie], inspect(site)
      assert %{value: "security:9"} = response.resp_cookies[@benchmark_cookie], inspect(site)
      assert %{value: "de"} = response.resp_cookies[@locale_cookie], inspect(site)
    end
  end
end
