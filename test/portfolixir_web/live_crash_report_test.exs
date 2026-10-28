defmodule PortfolixirWeb.LiveCrashReportTest do
  # Not async: it adds a :logger primary filter and sets the flag that
  # installs it, both global to the VM.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias PortfolixirWeb.SocketCrashReport

  defmodule CrashingLive do
    @moduledoc false
    # A page that crashes where a page can crash: in mount, and in an event.
    use Phoenix.LiveView

    @impl true
    def mount(_params, session, socket) do
      # The connected mount, the one that runs in the page's own process.
      if connected?(socket) and session["crash_on_mount"], do: raise("synthetic mount crash")
      {:ok, socket}
    end

    @impl true
    def render(assigns), do: ~H"<p>synthetic</p>"

    @impl true
    def handle_event("save", _params, _socket), do: raise("synthetic event crash")
  end

  setup do
    previous = Application.get_env(:portfolixir, :redact_socket_crash_reports)
    Application.put_env(:portfolixir, :redact_socket_crash_reports, true)

    # after_start/0 also logs the startup warnings, which depend on how the
    # suite is configured: captured, not asserted.
    capture_log(fn -> assert Portfolixir.Application.after_start() == :ok end)

    on_exit(fn ->
      :logger.remove_primary_filter(SocketCrashReport)
      Application.put_env(:portfolixir, :redact_socket_crash_reports, previous)
    end)

    Process.flag(:trap_exit, true)
    :ok
  end

  # User story (security review 2026-10-12, H71):
  # As the operator whose deployment guide says form values and session
  # contents stay out of the log,
  # I want a crashing live page logged by its topic and event name only,
  # so that a crash does not write what I typed, or my session, to the log.
  #
  # Acceptance criteria:
  # - A page that crashes in an event is logged as a crash, naming the
  #   event, without the event's values.
  # - A page that crashes in mount is logged as a crash, naming the join,
  #   without the session's contents or the join's parameters.
  # - The release turns the filter on at boot; development and the test
  #   suite keep the full report.
  test "a page crashing in an event is logged without the event's values", %{conn: conn} do
    secret = "synthetic-note-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, view, _html} = live_isolated(conn, CrashingLive)
    monitor = Process.monitor(view.pid)

    log =
      capture_log(fn ->
        catch_exit(render_click(view, "save", %{"note" => secret}))
        assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 5_000
        Process.sleep(100)
      end)

    assert log =~ "synthetic event crash"
    assert log =~ ~r/Last message: \[topic: "lv:[\w-]+", event: "event"\]\n/
    refute log =~ secret
    refute log =~ "Phoenix.Socket.Message"
  end

  test "a page crashing in mount is logged without the session or the join's parameters",
       %{conn: conn} do
    secret = "synthetic-session-" <> Integer.to_string(System.unique_integer([:positive]))
    conn = Plug.Test.init_test_session(conn, %{"synthetic_marker" => secret})

    log =
      capture_log(fn ->
        catch_exit(live_isolated(conn, CrashingLive, session: %{"crash_on_mount" => true}))
        Process.sleep(200)
      end)

    assert log =~ "synthetic mount crash"
    assert log =~ ~r/Last message: \[topic: "lv:[\w-]+", event: "phx_join"\]\n/
    refute log =~ secret
    refute log =~ "connect_info"
    refute log =~ "session"
  end

  test "the release turns the filter on at boot, development and tests do not" do
    for {env, expected} <- [prod: true, dev: nil, test: nil] do
      config = Config.Reader.read!("config/#{env}.exs", env: env, target: :host)
      assert get_in(config, [:portfolixir, :redact_socket_crash_reports]) == expected, "#{env}"
    end

    ids = Enum.map(:logger.get_primary_config().filters, &elem(&1, 0))
    assert SocketCrashReport in ids
  end
end
