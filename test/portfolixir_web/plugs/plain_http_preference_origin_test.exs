defmodule PortfolixirWeb.PlainHttpPreferenceOriginTest do
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.ViewScope

  @view_cookie "portfolixir_view"
  @benchmark_cookie "portfolixir_benchmarks"
  @locale_cookie "portfolixir_locale"
  @preference_cookies [@view_cookie, @benchmark_cookie, @locale_cookie]

  # Stand-in for a LAN address the operator named in PORTFOLIXIR_ALLOWED_HOSTS
  # (RFC 5737 documentation range); plain HTTP, no TLS, port 4000.
  @lan "192.0.2.10"
  @attack_query "/?view=7&benchmark[]=security:9&locale=de"

  setup do
    previous = Application.get_env(:portfolixir, PortfolixirWeb.HostGuard)
    hosts = Keyword.get(previous || [], :hosts, [])
    Application.put_env(:portfolixir, PortfolixirWeb.HostGuard, hosts: hosts ++ [@lan])
    on_exit(fn -> Application.put_env(:portfolixir, PortfolixirWeb.HostGuard, previous) end)
    :ok
  end

  # The operator's browser, which already remembers its own choices, talking
  # to the instance at its plain-HTTP LAN address.
  defp operator_browser(conn) do
    %{conn | host: @lan, port: 4000, scheme: :http}
    |> put_preference_cookie(@view_cookie, "total")
    |> put_preference_cookie(@benchmark_cookie, "rate:0.02")
    |> put_preference_cookie(@locale_cookie, "en")
  end

  defp written(response) do
    @preference_cookies
    |> Enum.filter(&Map.has_key?(response.resp_cookies, &1))
    |> Map.new(fn name -> {name, remembered(response, name)} end)
  end

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

  # User story (security review 2026-10-12, H41):
  # As an operator who reaches my instance over plain HTTP at a LAN address,
  # I want a view, benchmark or language in a link from another site to apply
  # to the page it opens only,
  # so that no other site can rewrite what my instance remembers for me where
  # the browser does not say where a request came from.
  #
  # Acceptance criteria:
  # - On plain HTTP off loopback, a request without Sec-Fetch-Site remembers
  #   a choice only when its Referer names the instance's own origin; with
  #   another site's Referer or none, the choice applies to that request
  #   only and the cookies and the session keep the stored choice.
  # - The next page, a LiveView mounted afterwards and the redirect to the
  #   login show or write nothing of the other site's choice.
  # - A request the browser labels cross-site is still applied to its page
  #   only; a request on loopback without the header still remembers.
  describe "a link from another site to the plain-HTTP LAN instance (no Sec-Fetch-Site)" do
    test "with the other site's Referer: nothing is remembered", %{conn: conn} do
      response =
        conn
        |> operator_browser()
        |> put_req_header("referer", "http://attacker.example/")
        |> get(@attack_query)

      assert html_response(response, 200) =~ ~s(lang="de")

      assert written(response) == %{},
             "a cross-site link wrote one-year preference cookies: #{inspect(Map.take(response.resp_cookies, @preference_cookies))}"

      assert get_session(response, ViewScope.session_key()) == "total"
      assert get_session(response, BenchmarkScope.session_key()) == ["rate:0.02"]
      assert get_session(response, "locale") == "en"
    end

    test "with no Referer (https page -> http instance, or referrerpolicy=no-referrer): nothing is remembered",
         %{conn: conn} do
      response = conn |> operator_browser() |> get(@attack_query)

      assert html_response(response, 200) =~ ~s(lang="de")
      assert written(response) == %{}
      assert get_session(response, ViewScope.session_key()) == "total"
    end

    test "with a Referer that only resembles the instance: nothing is remembered",
         %{conn: conn} do
      for referer <- [
            "http://#{@lan}.attacker.example:4000/",
            "http://#{@lan}:4001/portfolio",
            "http://attacker.example/http://#{@lan}:4000/",
            "not a url"
          ] do
        response =
          conn
          |> operator_browser()
          |> put_req_header("referer", referer)
          |> get(@attack_query)

        assert written(response) == %{}, referer
        assert get_session(response, ViewScope.session_key()) == "total", referer
      end
    end

    test "the next page the operator opens still shows the operator's own choice",
         %{conn: conn} do
      attacked =
        conn
        |> operator_browser()
        |> put_req_header("referer", "http://attacker.example/")
        |> get(@attack_query)

      # The browser carries whatever the response set into its next request.
      next = attacked |> recycle() |> get("/")

      assert get_session(next, ViewScope.session_key()) == "total"
      assert get_session(next, BenchmarkScope.session_key()) == ["rate:0.02"]
      assert html_response(next, 200) =~ ~s(lang="en")
    end

    test "the Wealth page opened afterwards is not scoped to the other site's view",
         %{conn: conn} do
      view = wealth_world()

      attacked =
        conn
        |> operator_browser()
        |> get("/?view=#{view.id}&locale=de")

      {:ok, page, html} = attacked |> recycle() |> live("/portfolio")
      render_async(page)

      refute has_element?(page, "[data-role='active-view']"),
             "the Wealth page opened on the view another site chose"

      assert has_element?(page, "#view-switch-total.is-active")
      assert html =~ ~s(aria-label="Language")
    end

    test "with a UI password and no login: the redirect to /login writes nothing",
         %{conn: conn} do
      previous = Application.get_env(:portfolixir, :ui_password)
      Application.put_env(:portfolixir, :ui_password, "correct-horse-battery-staple")
      on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)

      response =
        conn
        |> operator_browser()
        |> put_req_header("referer", "http://attacker.example/")
        |> get("/portfolio?view=7&locale=de")

      assert redirected_to(response) == "/login?to=%2Fportfolio"
      assert written(response) == %{}
    end
  end

  describe "the same request labelled by the browser, or from the instance itself" do
    # What a browser sends to an https or loopback origin: the F18 guard holds.
    test "Sec-Fetch-Site: cross-site is applied to the page only", %{conn: conn} do
      response =
        conn
        |> operator_browser()
        |> put_req_header("sec-fetch-site", "cross-site")
        |> get(@attack_query)

      assert html_response(response, 200) =~ ~s(lang="de")
      assert written(response) == %{}
      assert get_session(response, ViewScope.session_key()) == "total"
    end

    # The in-app switcher on the LAN instance: no Sec-Fetch-Site either, but
    # the Referer names the instance itself.
    test "an unlabelled request whose Referer is the instance itself is remembered",
         %{conn: conn} do
      response =
        conn
        |> operator_browser()
        |> put_req_header("referer", "http://#{@lan}:4000/portfolio")
        |> get(@attack_query)

      assert %{@view_cookie => "7", @benchmark_cookie => "security:9", @locale_cookie => "de"} =
               written(response)
    end

    # On loopback a browser labels every request, so an unlabelled one is an
    # older browser or a script on the machine, as before.
    test "an unlabelled request on loopback is remembered", %{conn: conn} do
      response =
        %{conn | host: "localhost", port: 4000, scheme: :http}
        |> get(@attack_query)

      assert %{@view_cookie => "7", @benchmark_cookie => "security:9", @locale_cookie => "de"} =
               written(response)
    end
  end
end
