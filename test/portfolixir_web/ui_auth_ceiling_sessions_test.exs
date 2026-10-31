defmodule PortfolixirWeb.UiAuthCeilingSessionsTest do
  # The UI login's scope-wide ceiling and the sessions already open
  # (security review 2026-10-12, H21): SECURITY.md promises that a tripped
  # ceiling holds back logins only, while existing sessions keep working. The
  # login reads the real clock, so this module trips the ceiling on it and
  # runs alone (async: false), clearing every UI throttle entry afterwards
  # so no other login test meets the lock.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Auth.Throttle

  @password "correct-horse-battery-staple"

  setup do
    previous = Application.get_env(:portfolixir, :ui_password)
    Application.put_env(:portfolixir, :ui_password, @password)

    clear = fn -> :ets.match_delete(Throttle, {{:ui, :_}, :_, :_, :_}) end
    clear.()

    on_exit(fn ->
      clear.()
      Application.put_env(:portfolixir, :ui_password, previous)
    end)

    :ok
  end

  # User story (security review 2026-10-12, H21):
  # As the operator logged in while someone guesses my password from many
  # addresses,
  # I want my open session to keep working once the login ceiling is
  # tripped,
  # so that the defence against guessing never locks me out of a session I
  # already hold.
  #
  # Acceptance criteria:
  # - With the UI ceiling tripped, a login from a source that never failed
  #   answers 429.
  # - The session opened before keeps loading pages and mounting the
  #   LiveView socket.
  test "a tripped login ceiling leaves open sessions working", %{conn: conn} do
    logged_in = post(conn, "/login", %{"session" => %{"password" => @password}})
    assert redirected_to(logged_in) == "/"
    session = recycle_session(conn, logged_in)

    {ceiling, _window} = Throttle.scope_ceiling(:ui)

    for i <- 1..ceiling do
      Throttle.failure(:ui, "ceiling-source-#{i}")
    end

    bystander = %{build_conn() | remote_ip: {10, 77, 0, 1}}
    locked = post(bystander, "/login", %{"session" => %{"password" => @password}})
    assert locked.status == 429

    assert session |> get("/portfolio") |> html_response(200)
    assert {:ok, _view, _html} = live(session, "/portfolio")
  end

  # The browser's next request: the session the login wrote.
  defp recycle_session(conn, response) do
    conn
    |> Phoenix.ConnTest.recycle()
    |> Map.put(:remote_ip, conn.remote_ip)
    |> Plug.Test.init_test_session(Plug.Conn.get_session(response))
  end
end
