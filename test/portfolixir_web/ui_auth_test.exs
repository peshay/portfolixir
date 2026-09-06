defmodule PortfolixirWeb.UiAuthTest do
  # Issue #764 (ADR-0045 §1): optional single-password authentication for the
  # web UI. Unset means today's behaviour; set, every browser route and the
  # LiveView socket mount require an authenticated session.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Auth.Throttle
  alias Portfolixir.Catalog.LogoStore
  alias PortfolixirWeb.UiAuth

  @password "correct-horse-battery-staple"

  defp with_password(_context) do
    previous = Application.get_env(:portfolixir, :ui_password)
    Application.put_env(:portfolixir, :ui_password, @password)
    on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)
    :ok
  end

  defp login(conn, password) do
    post(conn, "/login", %{"session" => %{"password" => password}})
  end

  # User story:
  # As an operator who has not set a UI password,
  # I want the instance to behave exactly as before,
  # so that an upgrade changes nothing until I choose to.
  #
  # Acceptance criteria:
  # - With no password configured every page and the socket mount are open,
  #   and the login page says so instead of offering a form.
  test "with no password configured nothing changes", %{conn: conn} do
    assert conn |> get("/") |> html_response(200)
    assert {:ok, _view, _html} = live(conn, "/portfolio")

    html = conn |> get("/login") |> html_response(200)
    refute html =~ ~s(name="session[password]")
    assert html =~ "PORTFOLIXIR_UI_PASSWORD"

    # With nothing configured no candidate is valid, and a session that is
    # not a map carries no flag.
    refute UiAuth.valid_password?("anything")
    refute UiAuth.valid_password?(nil)
    refute UiAuth.authenticated?(nil)
    assert UiAuth.safe_return_path(nil) == "/"

    # A stored logo is served without a login when none is configured.
    file = write_logo!()
    assert conn |> get("/security_logos/#{file}") |> response(200)

    assert conn |> get("/security_logos/#{file}") |> get_resp_header("x-content-type-options") ==
             ["nosniff"]

    assert conn |> get("/security_logos/999999999.png") |> response(404)
    assert conn |> get("/security_logos/..%2Fapp.css") |> response(404)
  end

  describe "with a password configured" do
    setup :with_password

    # User story:
    # As an operator who set PORTFOLIXIR_UI_PASSWORD,
    # I want every page to require the password once per browser session,
    # so that reaching the port is no longer enough to read or write my ledger.
    #
    # Acceptance criteria:
    # - An unauthenticated request to a page redirects to /login with the path to return to.
    # - The LiveView socket refuses to mount without the session flag.
    # - The right password redirects back and unlocks pages and the socket;
    #   the wrong one answers 401 with the form and counts against the source.
    # - The return path is never an absolute URL.
    # - Logout clears the session; the API stays on its bearer token.
    test "pages and the socket require the session flag", %{conn: conn} do
      redirected = get(conn, "/portfolio")
      assert redirected_to(redirected) == "/login?to=%2Fportfolio"

      assert {:error, {:redirect, %{to: "/login" <> _}}} = live(conn, "/portfolio")
    end

    test "the right password unlocks pages and the socket", %{conn: conn} do
      Throttle.success(:ui, Throttle.source_key(conn.remote_ip))

      logged_in = login(conn, @password)
      assert redirected_to(logged_in) == "/"

      conn = recycle_session(conn, logged_in)
      assert conn |> get("/portfolio") |> html_response(200)
      assert {:ok, _view, _html} = live(conn, "/portfolio")
    end

    test "the return path is honoured only when relative", %{conn: conn} do
      assert redirected_to(
               post(conn, "/login?to=%2Ftax", %{"session" => %{"password" => @password}})
             ) ==
               "/tax"

      # What Phoenix's redirect would refuse is "/" here, after a correct password.
      for evil <- [
            "https://evil.test/",
            "//evil.test",
            "javascript:alert(1)",
            "/\\evil.test",
            "/%09/evil.test",
            "/\t/evil.test",
            "/a%0Ab"
          ] do
        conn =
          post(conn, "/login?to=#{URI.encode_www_form(evil)}", %{
            "session" => %{"password" => @password}
          })

        assert redirected_to(conn) == "/", evil
      end
    end

    test "the wrong password is refused and throttled", %{conn: conn} do
      source = {10, 9, 8, 7}
      conn = %{conn | remote_ip: source}
      Throttle.success(:ui, Throttle.source_key(source))

      # A body that is not the form's shape is a wrong password, not a crash.
      malformed = post(conn, "/login", %{"session" => "abc"})
      assert malformed.status == 401

      for _ <- 1..(Throttle.max_failures() - 1) do
        refused = login(conn, "wrong")
        assert refused.status == 401
        assert html_response(refused, 401) =~ "Wrong password"
      end

      locked = login(conn, @password)
      assert locked.status == 429
      assert [_retry] = get_resp_header(locked, "retry-after")
      html = html_response(locked, 429)
      # The lockout is about the source, not the field: a form-level alert.
      assert html =~ ~s(id="login-lockout")
      refute html =~ ~s(aria-invalid)
    end

    test "the session pages carry the locale switcher", %{conn: conn} do
      html = conn |> get("/login?to=%2Ftax") |> html_response(200)
      assert html =~ ~s(href="/login?locale=de&amp;to=%2Ftax")
      assert conn |> get("/login?locale=de") |> html_response(200) =~ "Anmelden"
    end

    test "stored logos sit behind the login", %{conn: conn} do
      file = write_logo!()
      assert redirected_to(get(conn, "/security_logos/#{file}")) =~ "/login?to="

      Throttle.success(:ui, Throttle.source_key(conn.remote_ip))
      conn = recycle_session(conn, login(conn, @password))
      assert conn |> get("/security_logos/#{file}") |> response(200)
    end

    test "logout clears the session", %{conn: conn} do
      Throttle.success(:ui, Throttle.source_key(conn.remote_ip))
      conn = recycle_session(conn, login(conn, @password))
      assert conn |> get("/") |> html_response(200) =~ "Log out"

      # The link opens a one-button page; only the POST changes state.
      assert conn |> get("/logout") |> html_response(200) =~ ~s(action="/logout" method="post")
      assert conn |> get("/") |> html_response(200) =~ "Log out"

      # The login named a socket id; the logout tells every LiveView on it to go.
      live_socket_id = Plug.Conn.get_session(conn, "live_socket_id")
      assert "ui_sessions:" <> _ = live_socket_id
      PortfolixirWeb.Endpoint.subscribe(live_socket_id)

      logged_out = post(conn, "/logout")
      assert redirected_to(logged_out) == "/login"
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
      # The session is dropped at send time; a fresh browser carries nothing.
      assert Plug.Conn.get_session(logged_out) == %{} or
               logged_out.private[:plug_session_info] == :drop

      fresh = Phoenix.ConnTest.build_conn()
      assert redirected_to(get(fresh, "/")) == "/login?to=%2F"
    end

    test "the API stays on its bearer token", %{conn: conn} do
      assert conn
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer test-api-token")
             |> get("/api/v1/portfolios")
             |> json_response(200)
    end
  end

  describe "session lifetime (#777)" do
    setup :with_password

    # User story:
    # As the operator of a home instance,
    # I want my login to survive a browser restart and to be renewed while I keep
    # using the app,
    # so that I am asked for the password about once a month rather than every day.
    #
    # Acceptance criteria:
    # - The login cookie carries the configured lifetime as max_age (default 30 days).
    # - A session older than the lifetime is refused although its signature still
    #   verifies — the server decides, not the browser.
    # - A session with no timestamp at all (issued before this change) is refused.
    # - Using the app slides the window: a stamp older than the refresh interval is
    #   rewritten, a recent one is left alone so most requests write no cookie.
    # - PORTFOLIXIR_SESSION_DAYS=0 keeps the old behaviour: no max_age and no
    #   server-side expiry, so the login dies with the browser.
    test "the login cookie carries the configured lifetime", %{conn: conn} do
      Throttle.success(:ui, Throttle.source_key(conn.remote_ip))

      logged_in = login(conn, @password)

      assert %{max_age: max_age} = logged_in.resp_cookies["_portfolixir_key"]
      assert max_age == 30 * 24 * 60 * 60
    end

    test "a session past the lifetime is refused, a fresh one is not", %{conn: conn} do
      now = System.os_time(:second)

      stale = authenticated_at(conn, now - (30 * 24 * 60 * 60 + 60))
      assert redirected_to(get(stale, "/portfolio")) =~ "/login"
      assert {:error, {:redirect, %{to: "/login" <> _}}} = live(stale, "/portfolio")

      fresh = authenticated_at(conn, now - 60)
      assert fresh |> get("/portfolio") |> html_response(200)
    end

    test "a session issued before this change carries no timestamp and is refused",
         %{conn: conn} do
      unstamped = Plug.Test.init_test_session(conn, %{UiAuth.session_key() => true})

      assert redirected_to(get(unstamped, "/portfolio")) =~ "/login"
    end

    test "using the app slides the window, but not on every request", %{conn: conn} do
      now = System.os_time(:second)

      renewed = conn |> authenticated_at(now - 2 * 24 * 60 * 60) |> get("/")
      assert html_response(renewed, 200)
      assert Plug.Conn.get_session(renewed, UiAuth.stamp_key()) >= now

      recent = now - 60
      untouched = conn |> authenticated_at(recent) |> get("/")
      assert html_response(untouched, 200)
      assert Plug.Conn.get_session(untouched, UiAuth.stamp_key()) == recent
    end

    test "zero days keeps the browser-session behaviour", %{conn: conn} do
      Application.put_env(:portfolixir, :session_days, 0)
      on_exit(fn -> Application.delete_env(:portfolixir, :session_days) end)
      Throttle.success(:ui, Throttle.source_key(conn.remote_ip))

      logged_in = login(conn, @password)
      refute Map.has_key?(logged_in.resp_cookies["_portfolixir_key"], :max_age)

      # No server-side expiry either: an ancient session still passes, because the
      # browser is the one that forgets it.
      ancient = authenticated_at(conn, System.os_time(:second) - 3 * 365 * 24 * 60 * 60)
      assert ancient |> get("/portfolio") |> html_response(200)
    end

    defp authenticated_at(conn, stamp) do
      Plug.Test.init_test_session(conn, %{
        UiAuth.session_key() => true,
        UiAuth.stamp_key() => stamp
      })
    end
  end

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  defp write_logo! do
    dir = LogoStore.storage_dir()
    File.mkdir_p!(dir)
    file = "#{System.unique_integer([:positive])}.png"
    path = Path.join(dir, file)
    File.write!(path, @png)
    on_exit(fn -> File.rm(path) end)
    file
  end

  defp recycle_session(conn, response) do
    conn
    |> Phoenix.ConnTest.recycle()
    |> Map.put(:remote_ip, conn.remote_ip)
    |> Plug.Test.init_test_session(Plug.Conn.get_session(response))
  end
end
