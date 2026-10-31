defmodule PortfolixirWeb.UiAuthBoundariesTest do
  # Two claims of ADR-0045 §1 pinned (security review 2026-10-12, H25): the
  # UI password never reaches the log, even at debug level, and the JSON API
  # never accepts the UI's login, neither its session cookie nor the
  # password as a bearer token. The password is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Auth.Throttle

  setup %{conn: conn} do
    password = "boundary-" <> Integer.to_string(System.unique_integer([:positive]))
    previous = Application.get_env(:portfolixir, :ui_password)
    Application.put_env(:portfolixir, :ui_password, password)

    on_exit(fn ->
      Application.put_env(:portfolixir, :ui_password, previous)
      # The refused bearer tokens below count against this source.
      Throttle.success(:api, Throttle.source_key(conn.remote_ip))
    end)

    Throttle.success(:ui, Throttle.source_key(conn.remote_ip))
    %{password: password}
  end

  # User story (security review 2026-10-12, H25):
  # As the operator who set a UI password,
  # I want neither a right nor a wrong login to write the password to the
  # log, at any level,
  # so that a debug log handed to someone never carries it.
  #
  # Acceptance criteria:
  # - At :debug, a wrong and a right login leave the log without the
  #   password, while the log holds the login's request lines.
  test "a login leaves the password out of the log at debug level",
       %{conn: conn, password: password} do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    log =
      capture_log([level: :debug], fn ->
        assert post(conn, "/login", %{"session" => %{"password" => password <> "x"}}).status ==
                 401

        assert redirected_to(post(conn, "/login", %{"session" => %{"password" => password}})) ==
                 "/"
      end)

    assert log =~ "POST /login"
    refute log =~ password
  end

  # User story (security review 2026-10-12, H25):
  # As the operator whose browser holds a logged-in session,
  # I want the JSON API to answer only its bearer token,
  # so that a page I visit cannot reach the API through my session, and the
  # UI password never works as an API credential.
  #
  # Acceptance criteria:
  # - A request carrying a logged-in session and no bearer token answers 401.
  # - A request carrying the UI password as its bearer token answers 401.
  # - The API token still answers 200 (the control).
  test "the API refuses a UI session and the UI password",
       %{conn: conn, password: password} do
    logged_in = post(conn, "/login", %{"session" => %{"password" => password}})
    assert redirected_to(logged_in) == "/"

    session =
      conn
      |> Phoenix.ConnTest.recycle()
      |> Plug.Test.init_test_session(Plug.Conn.get_session(logged_in))
      |> put_req_header("accept", "application/json")

    assert session |> get("/api/v1/portfolios") |> json_response(401)

    assert build_conn()
           |> put_req_header("accept", "application/json")
           |> put_req_header("authorization", "Bearer " <> password)
           |> get("/api/v1/portfolios")
           |> json_response(401)

    assert build_conn()
           |> put_req_header("accept", "application/json")
           |> put_req_header("authorization", "Bearer test-api-token")
           |> get("/api/v1/portfolios")
           |> json_response(200)
  end
end
