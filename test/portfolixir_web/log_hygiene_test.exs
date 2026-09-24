defmodule PortfolixirWeb.LogHygieneTest do
  # E25 S2, F66 (review round): what the production log level, info, still
  # writes must carry no session-bound secret. Not async: it lowers the global
  # Logger level for the duration of each test.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ChannelTest

  @endpoint PortfolixirWeb.Endpoint

  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  # User story (E25 S2, F66, review round):
  # As an operator reading my container's log at the production level,
  # I want a live page's socket connect logged without its CSRF token,
  # so that the log carries no token bound to my session.
  #
  # Acceptance criteria:
  # - At info level the LiveView socket's connect line is written, with its
  #   parameters.
  # - The `_csrf_token` parameter is shown filtered, and its value is absent.
  test "the live socket's connect line leaves the CSRF token out" do
    token = "csrf-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

    log =
      capture_log([level: :info], fn ->
        assert {:ok, _socket} =
                 connect(Phoenix.LiveView.Socket, %{"_csrf_token" => token, "_mounts" => "0"})
      end)

    assert log =~ "CONNECTED TO Phoenix.LiveView.Socket"
    assert log =~ ~s("_csrf_token" => "[FILTERED]")
    refute log =~ token
  end
end
