defmodule PortfolixirWeb.ServerWrittenPreferencesTest do
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.Socket.Transport
  alias Plug.Conn.Cookies
  alias Plug.Session.Store
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias Portfolixir.Settings
  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.ViewScope

  @view_cookie "portfolixir_view"
  @session_cookie "_portfolixir_key"

  setup do
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

    {:ok, own} = Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic Own"})
    {:ok, planted} = Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic Planted"})
    %{own: own, planted: planted}
  end

  # "name=value; name=value" for every cookie a response wrote, as the
  # browser would send them back (all of them host-only, path=/).
  defp own_cookie_header(response) do
    response.resp_cookies
    |> Enum.filter(fn {_name, cookie} -> is_binary(Map.get(cookie, :value)) end)
    |> Enum.map_join("; ", fn {name, cookie} -> name <> "=" <> cookie.value end)
  end

  defp session_options_for_socket do
    # What the endpoint hands the /live socket (connect_info session).
    opts = PortfolixirWeb.Endpoint.session_options()
    store = Store.get(Keyword.fetch!(opts, :store))

    {Keyword.fetch!(opts, :key), store,
     {"_csrf_token", store.init(Keyword.drop(opts, [:store, :key]))}}
  end

  defp socket_session(cookie_header, csrf_token) do
    conn =
      Phoenix.ConnTest.build_conn(
        :get,
        "/live/websocket?" <> URI.encode_query(%{"_csrf_token" => csrf_token, "vsn" => "2.0.0"})
      )
      |> put_req_header("cookie", cookie_header)
      |> Plug.Conn.fetch_query_params()

    Transport.connect_info(conn, PortfolixirWeb.Endpoint, [
      {:session, session_options_for_socket()}
    ]).session
  end

  defp dead_render_with_csrf do
    page = build_conn() |> put_req_header("sec-fetch-site", "none") |> get("/")
    html = html_response(page, 200)
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html)
    %{page: page, csrf: csrf, session_cookie: page.resp_cookies[@session_cookie].value}
  end

  defp with_ui_password do
    previous = Application.get_env(:portfolixir, :ui_password)
    Application.put_env(:portfolixir, :ui_password, "synthetic-ui-password-for-k02")
    on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)
  end

  defp logged_in_session do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> PortfolixirWeb.UiAuth.put_authenticated()
    |> get_session()
  end

  # User story (security review 2026-10-12, K02):
  # As an operator who runs other web apps beside my instance on the same
  # host name, or behind the same parent domain,
  # I want the view, benchmark and language my instance remembers to be only
  # the ones my instance itself wrote,
  # so that no other origin that shares the host name can choose what my
  # pages show.
  #
  # Acceptance criteria:
  # - A preference cookie the server did not sign is not taken as the
  #   operator's choice: the page falls back to the default view, no
  #   benchmark and the browser's language.
  # - When the Cookie header carries a preference cookie's name twice, the
  #   choice is dropped rather than resolved in favour of the first.
  # - The Wealth page opens on the operator's default view, with or without
  #   a UI password.
  # - On HTTPS a choice is remembered under the __Host- prefix, so no Domain
  #   or Path variant can stand for it, and a cookie without the prefix is
  #   not read there.
  # - A choice the server wrote itself still persists across requests.
  describe "preference cookies the server did not write" do
    test "are not taken as the operator's remembered view, benchmark and language",
         %{planted: planted} do
      response =
        build_conn()
        |> put_req_header(
          "cookie",
          "#{@view_cookie}=#{planted.id}; portfolixir_benchmarks=rate:9.5; portfolixir_locale=de"
        )
        |> put_req_header("sec-fetch-site", "none")
        |> get("/")

      observed = %{
        view: get_session(response, ViewScope.session_key()),
        benchmarks: get_session(response, BenchmarkScope.session_key()),
        locale: get_session(response, "locale")
      }

      adopted =
        Enum.filter(
          [view: planted.id, benchmarks: ["rate:9.5"], locale: "de"],
          fn {key, planted_value} -> Map.fetch!(observed, key) == planted_value end
        )

      assert adopted == [],
             "values no response of this server ever wrote were adopted into the signed " <>
               "session as the operator's choice: #{inspect(adopted)} (observed #{inspect(observed)})"
    end

    test "a longer-path twin does not outrank the choice the operator made in the app",
         %{planted: planted} do
      chosen =
        build_conn()
        |> put_req_header("sec-fetch-site", "same-origin")
        |> get("/?view=total")

      assert get_session(chosen, ViewScope.session_key()) == "total"
      own = own_cookie_header(chosen)

      response =
        build_conn()
        |> put_req_header("cookie", "#{@view_cookie}=#{planted.id}; " <> own)
        |> put_req_header("sec-fetch-site", "same-origin")
        |> get("/portfolio")

      refute get_session(response, ViewScope.session_key()) == planted.id,
             "the planted twin (view #{planted.id}) displaced the operator's own " <>
               "choice \"total\" for /portfolio"
    end

    test "on HTTPS a choice is remembered under the __Host- prefix only", %{planted: planted} do
      https = "https://www.example.com"

      chosen =
        build_conn()
        |> put_req_header("sec-fetch-site", "same-origin")
        |> get(https <> "/?view=total&locale=de&benchmark_rate=2")

      for name <- ~w(portfolixir_view portfolixir_locale portfolixir_benchmarks) do
        cookie = chosen.resp_cookies["__Host-" <> name]
        assert %{secure: true} = cookie, name
        refute Map.has_key?(cookie, :domain), name
        assert Map.get(cookie, :path, "/") == "/", name
        refute Map.has_key?(chosen.resp_cookies, name), name
      end

      response =
        build_conn()
        |> put_req_header(
          "cookie",
          "#{@view_cookie}=#{planted.id}; " <> own_cookie_header(chosen)
        )
        |> put_req_header("sec-fetch-site", "same-origin")
        |> get(https <> "/portfolio")

      assert get_session(response, ViewScope.session_key()) == "total"

      unprefixed =
        build_conn()
        |> put_req_header("cookie", "#{@view_cookie}=#{planted.id}")
        |> put_req_header("sec-fetch-site", "none")
        |> get(https <> "/")

      assert get_session(unprefixed, ViewScope.session_key()) == nil
    end

    test "the Wealth page opens on the operator's default view, not on a planted one",
         %{own: own, planted: planted} do
      :ok = Settings.set_default_view(own.id)

      conn =
        build_conn()
        |> put_req_header("cookie", "#{@view_cookie}=#{planted.id}")
        |> put_req_header("sec-fetch-site", "none")

      {:ok, page, _html} = live(conn, "/portfolio")

      active = page |> element("[data-role='active-view']") |> render()

      assert active =~ "Synthetic Own",
             "the connected Wealth page is scoped by the planted cookie: #{active}"
    end

    test "with a UI password, the logged-in operator's Wealth page is not scoped by a planted cookie",
         %{own: own, planted: planted} do
      with_ui_password()
      :ok = Settings.set_default_view(own.id)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(logged_in_session())
        |> put_req_header("cookie", "#{@view_cookie}=#{planted.id}")
        |> put_req_header("sec-fetch-site", "none")

      {:ok, page, _html} = live(conn, "/portfolio")
      active = page |> element("[data-role='active-view']") |> render()

      assert active =~ "Synthetic Own",
             "behind the UI login the page is scoped by the planted cookie: #{active}"
    end
  end

  # User story (security review 2026-10-12, K02):
  # As an operator who locks the UI with a password,
  # I want a preference cookie written only for a request the login lets in,
  # so that whoever reaches the instance without the password cannot obtain a
  # value it signed and plant it in my browser.
  #
  # Acceptance criteria:
  # - With a password set, a request without the login carrying a view,
  #   language or benchmark choice is sent to the login and gets no
  #   preference cookie.
  # - With the login, the same request still remembers all three.
  # - With no password set, the open instance remembers them as before.
  describe "a preference choice and the UI login" do
    @choice "/?view=total&locale=de&benchmark_rate=2"
    @preference_cookies ~w(portfolixir_view portfolixir_locale portfolixir_benchmarks)

    defp preference_cookies_written(response) do
      for {name, _cookie} <- response.resp_cookies,
          String.replace_prefix(name, "__Host-", "") in @preference_cookies,
          do: name
    end

    test "is not remembered for a request the login does not allow" do
      with_ui_password()

      for site <- ["none", "same-origin"] do
        response = build_conn() |> put_req_header("sec-fetch-site", site) |> get(@choice)

        assert redirected_to(response) == "/login?to=%2F", "#{site}: the login redirect"
        assert preference_cookies_written(response) == [], "#{site}: a preference cookie"
      end
    end

    test "is remembered for a request the login allows" do
      with_ui_password()

      response =
        build_conn()
        |> Plug.Test.init_test_session(logged_in_session())
        |> put_req_header("sec-fetch-site", "same-origin")
        |> get(@choice)

      assert html_response(response, 200)

      assert Enum.sort(preference_cookies_written(response)) ==
               Enum.sort(@preference_cookies)
    end

    test "is remembered on an instance without a UI password" do
      previous = Application.get_env(:portfolixir, :ui_password)
      Application.delete_env(:portfolixir, :ui_password)
      on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)

      response = build_conn() |> put_req_header("sec-fetch-site", "none") |> get(@choice)

      assert html_response(response, 200)

      assert Enum.sort(preference_cookies_written(response)) ==
               Enum.sort(@preference_cookies)
    end
  end

  # User story (security review 2026-10-12, K02):
  # As an operator whose browser also holds cookies another origin of the
  # same host name set,
  # I want my live pages to find the session my instance signed,
  # so that a cookie of the same name set elsewhere cannot keep every live
  # page from connecting.
  #
  # Acceptance criteria:
  # - When the session cookie's name appears twice and the first value does
  #   not verify, the socket reads the one the server signed.
  # - The socket still reads the operator's session from its own cookie.
  describe "the live socket's session" do
    test "is found when a twin the server did not sign is listed first" do
      %{csrf: csrf, session_cookie: legit} = dead_render_with_csrf()

      session = socket_session("#{@session_cookie}=x; #{@session_cookie}=#{legit}", csrf)

      assert is_map(session),
             "connect_info session is #{inspect(session)}: the LiveView join answers " <>
               "\"stale\" and every live page reloads"
    end

    test "is found from the operator's own cookie" do
      %{csrf: csrf, session_cookie: legit} = dead_render_with_csrf()
      session = socket_session("#{@session_cookie}=#{legit}", csrf)
      assert is_map(session)
      assert is_binary(session["_csrf_token"])
    end
  end

  describe "a choice the server wrote" do
    test "still persists across requests", %{own: own} do
      chosen =
        build_conn()
        |> put_req_header("sec-fetch-site", "same-origin")
        |> get("/?view=#{own.id}&locale=de&benchmark_rate=2")

      next =
        build_conn()
        |> put_req_header("cookie", own_cookie_header(chosen))
        |> put_req_header("sec-fetch-site", "same-origin")
        |> get("/")

      assert get_session(next, ViewScope.session_key()) == own.id
      assert get_session(next, BenchmarkScope.session_key()) == ["rate:0.02"]
      assert get_session(next, "locale") == "de"
    end

    test "with a UI password, the logged-in operator's Wealth page opens on the default view",
         %{own: own} do
      with_ui_password()
      :ok = Settings.set_default_view(own.id)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(logged_in_session())
        |> put_req_header("sec-fetch-site", "none")

      {:ok, page, _html} = live(conn, "/portfolio")
      assert page |> element("[data-role='active-view']") |> render() =~ "Synthetic Own"

      assert {:error, {:redirect, %{to: "/login" <> _}}} =
               live(build_conn() |> put_req_header("sec-fetch-site", "none"), "/portfolio")
    end

    # Why a twin must be refused rather than resolved: Plug keeps the first.
    test "Plug keeps the first of a duplicated cookie name" do
      assert Cookies.decode("#{@view_cookie}=7; #{@view_cookie}=total") ==
               %{@view_cookie => "7"}
    end
  end
end
