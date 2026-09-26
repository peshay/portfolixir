defmodule PortfolixirWeb.PreferencePersistenceTest do
  # E25 S7, F18: the view, benchmark and locale choices arrive as query
  # parameters on a plain GET, so any site could link the operator's browser
  # to `/?view=…` and rewrite the stored UI scope. A choice is remembered only
  # when the browser says the request came from this origin, from the address
  # bar or a bookmark, or does not say (an older browser, a script).
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.LiveBenchmarkScope
  alias PortfolixirWeb.LiveLocale
  alias PortfolixirWeb.LiveViewScope
  alias PortfolixirWeb.UiAuth
  alias PortfolixirWeb.ViewScope

  @view_cookie "portfolixir_view"
  @benchmark_cookie "portfolixir_benchmarks"
  @locale_cookie "portfolixir_locale"

  defp from(conn, site), do: put_req_header(conn, "sec-fetch-site", site)

  # The Wealth page with its view switcher needs an account to render.
  defp wealth_world do
    Portfolixir.Classifications.ensure_builtins()

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, _depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Retirement"})
    view
  end

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
  # - It is not written into the session either (E25 S7 review round,
  #   S7E-4): the session keeps the stored choice, which every later mount
  #   reads.
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

      # The request itself is answered in the choice it carried; the session
      # keeps the stored one.
      assert html_response(response, 200) =~ ~s(lang="de")
      assert get_session(response, ViewScope.session_key()) == "total"
      assert get_session(response, BenchmarkScope.session_key()) == ["rate:0.02"]
      assert get_session(response, "locale") == "en"
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
    assert get_session(response, ViewScope.session_key()) == 5
    assert get_session(response, BenchmarkScope.session_key()) == ["security:3"]
  end

  # User story (E25 S7 review round, S7E-4):
  # As an operator who opened a Wealth page from another site's link,
  # I want the view and language that link carried to stay on that page,
  # so that the next page I open inside the app — by a live navigation too —
  # shows the view and language I chose myself.
  #
  # Acceptance criteria:
  # - The page the link opened shows the carried view and language on its
  #   first render and once its socket is connected: a LiveView reads a
  #   choice its own address carries before the session's.
  # - A live navigation from that page mounts with the session, so it shows
  #   the remembered view and language.
  test "a cross-site choice stays on its page, and a live navigation reads the stored one",
       %{conn: conn} do
    view = wealth_world()

    stored =
      conn
      |> put_req_cookie(@view_cookie, "total")
      |> put_req_cookie(@locale_cookie, "en")
      |> from("cross-site")

    {:ok, page, html} = live(stored, "/portfolio?view=#{view.id}&locale=de")
    assert has_element?(page, "[data-role='active-view']", "Retirement")
    assert html =~ ~s(aria-label="Sprache")
    render_async(page)

    {:ok, next, html} = live_redirect(page, to: "/portfolio")
    refute has_element?(next, "[data-role='active-view']")
    assert has_element?(next, "#view-switch-total.is-active")
    assert html =~ ~s(aria-label="Language")
    render_async(next)
  end

  # The three hooks read a choice the page's own address carries first, in
  # the shape the plugs accept, and the session's otherwise (S7E-4).
  test "the LiveView hooks prefer the address's choice to the session's" do
    socket = %Phoenix.LiveView.Socket{}

    view = wealth_world()
    stored = %{ViewScope.session_key() => "total"}

    assert {:cont, %{assigns: %{active_view_id: id}}} =
             LiveViewScope.on_mount(:default, %{"view" => to_string(view.id)}, stored, socket)

    assert id == view.id

    assert {:cont, %{assigns: %{active_view_id: nil}}} =
             LiveViewScope.on_mount(:default, %{}, stored, socket)

    assert {:cont, %{assigns: %{active_view_id: nil}}} =
             LiveViewScope.on_mount(:default, :not_mounted_at_router, stored, socket)

    stored_benchmarks = %{BenchmarkScope.session_key() => ["rate:0.02"]}

    assert {:cont, %{assigns: %{active_benchmark_selectors: ["security:9", "rate:0.03"]}}} =
             LiveBenchmarkScope.on_mount(
               :default,
               %{"benchmark" => ["security:9"], "benchmark_rate" => "3"},
               stored_benchmarks,
               socket
             )

    assert {:cont, %{assigns: %{active_benchmark_selectors: ["rate:0.02"]}}} =
             LiveBenchmarkScope.on_mount(
               :default,
               %{"tab" => "allocation"},
               stored_benchmarks,
               socket
             )

    assert {:cont, %{assigns: %{locale: "de"}}} =
             LiveLocale.on_mount(:default, %{"locale" => "DE-de"}, %{"locale" => "en"}, socket)

    assert {:cont, %{assigns: %{locale: "en"}}} =
             LiveLocale.on_mount(:default, %{"locale" => "fr"}, %{"locale" => "en"}, socket)
  after
    Gettext.put_locale(PortfolixirWeb.Gettext, "en")
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

  # User story (E25 S7 review round, S7E-2):
  # As an operator with a UI password whose login has expired,
  # I want a link from another site that sends me through the login to lose
  # its view, benchmark and language on the way,
  # so that logging in never turns another site's choice into my remembered
  # one.
  #
  # Acceptance criteria:
  # - The path the login returns to carries no view, locale, benchmark or
  #   benchmark_rate parameter, whether the login page was reached through the
  #   redirect or by a link naming the path itself; every other parameter is
  #   kept.
  # - A choice made on the instance and redirected to the login is remembered
  #   by that request already, so the login loses nothing by dropping it.
  describe "the login's return path" do
    setup do
      previous = Application.get_env(:portfolixir, :ui_password)
      Application.put_env(:portfolixir, :ui_password, "correct-horse-battery-staple")
      on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)
    end

    test "drops the preference parameters and keeps the rest", %{conn: conn} do
      redirected =
        conn
        |> from("cross-site")
        |> get(
          "/portfolio?tab=allocation&view=7&locale=de&benchmark[]=security:9&benchmark_rate=2"
        )

      refute Map.has_key?(redirected.resp_cookies, @view_cookie)
      assert redirected_to(redirected) == "/login?to=%2Fportfolio%3Ftab%3Dallocation"

      logged_in =
        post(conn, "/login?to=%2Fportfolio%3Ftab%3Dallocation%26view%3D7%26locale%3Dde", %{
          "session" => %{"password" => "correct-horse-battery-staple"}
        })

      assert redirected_to(logged_in) == "/portfolio?tab=allocation"

      html =
        conn
        |> get("/login?to=" <> URI.encode_www_form("/portfolio?view=7&benchmark%5B%5D=x"))
        |> html_response(200)

      assert html =~ ~s(action="/login?to=%2Fportfolio")
    end

    test "a same-origin choice is remembered before the login", %{conn: conn} do
      redirected = conn |> from("same-origin") |> get("/portfolio?view=7&locale=de")

      assert %{value: "7"} = redirected.resp_cookies[@view_cookie]
      assert %{value: "de"} = redirected.resp_cookies[@locale_cookie]
      assert redirected_to(redirected) == "/login?to=%2Fportfolio"
    end

    test "is cleaned in one place" do
      assert UiAuth.safe_return_path("/portfolio?view=7") == "/portfolio"
      assert UiAuth.safe_return_path("/risk?view=total&x=1") == "/risk?x=1"

      assert UiAuth.safe_return_path("/portfolio?benchmark%5B%5D=security%3A9&tab=allocation") ==
               "/portfolio?tab=allocation"

      assert UiAuth.safe_return_path("/?locale=de&benchmark_rate=2&view[]=1") == "/"

      assert UiAuth.safe_return_path("/cashflow?year=2025&views=1") ==
               "/cashflow?year=2025&views=1"

      assert UiAuth.safe_return_path("//evil.example/?view=1") == "/"
    end
  end

  # User story (E25 S7 review round, S7E-2):
  # As an operator who opened a Wealth page from another site's link,
  # I want the page's own links — the language switcher, the tabs, the way
  # back to Holdings — not to carry that link's view along,
  # so that my next click, a request from the instance itself, does not make
  # the foreign view my remembered one.
  #
  # Acceptance criteria:
  # - On a page whose ?view= came from another site, the links derived from
  #   the page's path carry no ?view=, on the Holdings and the Allocation tab.
  # - On a page whose ?view= is the remembered choice, they still carry it
  #   (ADR-0024).
  test "the page's links carry only a remembered view", %{conn: conn} do
    view = wealth_world()
    stored = conn |> put_req_cookie(@view_cookie, "total") |> from("cross-site")

    for path <- ["/portfolio", "/portfolio?tab=allocation"] do
      separator = if path =~ "?", do: "&", else: "?"
      {:ok, page, _html} = live(stored, path <> separator <> "view=#{view.id}")
      render_async(page)

      assert has_element?(page, "[data-role='active-view']", "Retirement")
      refute page |> element("#locale-de") |> render() =~ "view=", path
    end

    {:ok, page, _html} = conn |> from("same-origin") |> live("/portfolio?view=#{view.id}")
    render_async(page)
    assert page |> element("#locale-de") |> render() =~ "view=#{view.id}"
  end
end
