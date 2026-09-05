defmodule PortfolixirWeb.UiAuthTest do
  # Issue #764 (ADR-0045 §1): optional single-password authentication for the
  # web UI. Unset means today's behaviour; set, every browser route and the
  # LiveView socket mount require an authenticated session.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Auth.Throttle

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

      for evil <- ["https://evil.test/", "//evil.test", "javascript:alert(1)"] do
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

      for _ <- 1..Throttle.max_failures() do
        refused = login(conn, "wrong")
        assert refused.status == 401
        assert html_response(refused, 401) =~ "Wrong password"
      end

      locked = login(conn, @password)
      assert locked.status == 429
      assert [_retry] = get_resp_header(locked, "retry-after")
    end

    test "logout clears the session", %{conn: conn} do
      Throttle.success(:ui, Throttle.source_key(conn.remote_ip))
      conn = recycle_session(conn, login(conn, @password))
      assert conn |> get("/") |> html_response(200) =~ "Log out"

      logged_out = post(conn, "/logout")
      assert redirected_to(logged_out) == "/login"
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

  defp recycle_session(conn, response) do
    conn
    |> Phoenix.ConnTest.recycle()
    |> Map.put(:remote_ip, conn.remote_ip)
    |> Plug.Test.init_test_session(Plug.Conn.get_session(response))
  end
end
