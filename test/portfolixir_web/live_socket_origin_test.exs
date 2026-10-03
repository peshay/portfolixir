defmodule PortfolixirWeb.LiveSocketOriginTest do
  # async: false -- the release test sets environment variables the whole VM
  # reads.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  # What config/runtime.exs needs under :prod to evaluate at all, each a
  # synthetic value its own check accepts.
  @release_env %{
    "SECRET_KEY_BASE" => String.duplicate("k7Qm", 16),
    "PHX_HOST" => "portfolixir.example",
    "DATABASE_URL" => "ecto://portfolixir:synthetic@db.example/portfolixir_prod",
    "PORTFOLIXIR_API_TOKEN" => String.duplicate("t3Zx", 12),
    "PORTFOLIXIR_ALLOWED_HOSTS" => "nas.example"
  }

  # User story (#1006, Sprint 18 Lane M, the closing act's review round):
  # As an operator whose browser also has other sites open,
  # I want the LiveView socket to refuse a handshake from a foreign origin,
  # so that another page cannot open a socket under my session and read what
  # my screens show.
  #
  # Acceptance criteria:
  # - A websocket handshake whose Origin is not the instance's own is refused
  #   with 403. The socket inherits the endpoint's check_origin; an override
  #   on the socket line turns this red. sobelow's Config.CSWH check cannot
  #   see that override behind its fingerprint skip (.sobelow-skips).
  # - In a release, the endpoint's check_origin is the Host guard's
  #   allow-list: PHX_HOST, loopback and PORTFOLIXIR_ALLOWED_HOSTS, each as
  #   a scheme-less "//host" origin, and nothing broader.
  test "the LiveView socket refuses a handshake from a foreign origin", %{conn: conn} do
    log =
      capture_log(fn ->
        conn =
          conn
          |> put_req_header("origin", "https://foreign.example")
          |> get("/live/websocket")

        assert conn.status == 403
      end)

    assert log =~ "Could not check origin"
    assert log =~ "https://foreign.example"
  end

  test "a release checks the socket's origin against the Host allow-list" do
    origins =
      with_env(@release_env, fn ->
        "config/runtime.exs"
        |> Config.Reader.read!(env: :prod, target: :host)
        |> Keyword.fetch!(:portfolixir)
        |> Keyword.fetch!(PortfolixirWeb.Endpoint)
        |> Keyword.fetch!(:check_origin)
      end)

    assert "//portfolixir.example" in origins
    assert "//nas.example" in origins
    assert "//localhost" in origins

    for origin <- origins do
      assert origin =~ ~r{\A//[^*/\s]+\z}, inspect(origin)
    end
  end

  defp with_env(env, fun) do
    previous = Map.new(env, fn {name, _value} -> {name, System.get_env(name)} end)

    try do
      Enum.each(env, fn {name, value} -> System.put_env(name, value) end)
      fun.()
    after
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end
end
