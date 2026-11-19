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

    # What the operator types is kept in the page's assigns, which every
    # handler receives (Sprint 30 closing act, security lens, finding 1).
    def handle_event("validate", %{"note" => note}, socket),
      do: {:noreply, Phoenix.Component.assign(socket, :typed, note)}

    # A match that fails on what the page sends: the MatchError carries the
    # value it could not match.
    def handle_event("check", params, socket) do
      %{"kind" => "known"} = params
      {:noreply, socket}
    end

    # Work started from an event, in a task of its own, on what was typed.
    def handle_event("work", _params, socket) do
      typed = socket.assigns[:typed]
      {:noreply, start_async(socket, :work, fn -> classify(typed) end)}
    end

    # A handler with no clause for what the page sends: the runtime's
    # FunctionClauseError carries the handler's arguments in its stack frame.
    def handle_event("pick", %{"kind" => "known"}, socket), do: {:noreply, socket}

    # A page with no clause for a message it is sent: the stack frame
    # carries the message and the socket, the page's assigns among them.
    @impl true
    def handle_info(:known, socket), do: {:noreply, socket}

    @impl true
    def handle_async(:work, _result, socket), do: {:noreply, socket}

    defp classify("known"), do: :known
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

  # User story (#1256, the Shell polish list #1357; Sprint 30 plan, F2):
  # As the operator whose deployment guide says form values stay out of the log,
  # I want a page whose handler has no matching clause logged without the
  # handler's arguments,
  # so that the values I typed do not reach the log through the stack frame.
  #
  # Acceptance criteria:
  # - A page crashing with a FunctionClauseError in an event is logged as
  #   that crash, naming the handler, without the event's values or the
  #   page's assigns.
  test "a page whose handler has no matching clause is logged without the handler's arguments",
       %{conn: conn} do
    secret = "synthetic-field-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, view, _html} = live_isolated(conn, CrashingLive)
    monitor = Process.monitor(view.pid)

    log =
      capture_log(fn ->
        catch_exit(render_click(view, "pick", %{"kind" => "other", "note" => secret}))
        assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 5_000
        Process.sleep(100)
      end)

    assert log =~ "FunctionClauseError"
    assert log =~ "handle_event/3"
    assert log =~ ~r/Last message: \[topic: "lv:[\w-]+", event: "event"\]\n/
    refute log =~ secret
    refute log =~ "Phoenix.LiveView.Socket"
  end

  # User story (Sprint 30 closing act, security lens, finding 1; #1256):
  # As the operator whose deployment guide says form values stay out of the log,
  # I want a page that crashes outside a page event, or on a failed match,
  # logged without the values its handler held,
  # so that what I typed does not reach the log through a crash the filter
  # did not expect.
  #
  # Acceptance criteria:
  # - A page with no clause for a message it is sent is logged as that
  #   FunctionClauseError, naming handle_info/2, without the page's assigns.
  # - A page whose event handler fails a match is logged as that MatchError
  #   without the event's values.
  # - A page whose async task fails a clause is logged as that crash without
  #   the value the task was given.
  test "a page crashing in handle_info is logged without the page's assigns", %{conn: conn} do
    secret = "synthetic-typed-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, view, _html} = live_isolated(conn, CrashingLive)
    render_change(view, "validate", %{"note" => secret})
    monitor = Process.monitor(view.pid)

    log =
      capture_log(fn ->
        send(view.pid, :unexpected)
        assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 5_000
        Process.sleep(100)
      end)

    assert log =~ "FunctionClauseError"
    assert log =~ "handle_info/2"
    refute log =~ secret
    refute log =~ "Phoenix.LiveView.Socket"
  end

  test "a page whose event handler fails a match is logged without the event's values",
       %{conn: conn} do
    secret = "synthetic-field-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, view, _html} = live_isolated(conn, CrashingLive)
    monitor = Process.monitor(view.pid)

    log =
      capture_log(fn ->
        catch_exit(render_click(view, "check", %{"kind" => "other", "note" => secret}))
        assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 5_000
        Process.sleep(100)
      end)

    assert log =~ "MatchError"
    assert log =~ ~r/Last message: \[topic: "lv:[\w-]+", event: "event"\]\n/
    refute log =~ secret
  end

  test "a page whose async task fails a clause is logged without the task's values",
       %{conn: conn} do
    secret = "synthetic-async-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, view, _html} = live_isolated(conn, CrashingLive)
    render_change(view, "validate", %{"note" => secret})

    log =
      capture_log(fn ->
        render_click(view, "work", %{})
        Process.sleep(300)
      end)

    assert log =~ "FunctionClauseError"
    assert log =~ "classify/1"
    refute log =~ secret
  end

  test "the filter replaces a failed match's value in every clause error it names" do
    report = fn reason ->
      %{
        level: :error,
        meta: %{},
        msg:
          {:report, %{label: {:gen_server, :terminate}, last_message: :synthetic, reason: reason}}
      }
    end

    for error <- [
          %MatchError{term: "synthetic-value"},
          %CaseClauseError{term: "synthetic-value"},
          %WithClauseError{term: "synthetic-value"},
          %KeyError{key: "kind", term: %{"note" => "synthetic-value"}},
          # As the runtime raises them, before Elixir names them.
          {:badmatch, "synthetic-value"},
          {:case_clause, "synthetic-value"},
          {:badkey, "kind", %{"note" => "synthetic-value"}}
        ] do
      assert %{msg: {:report, %{reason: {redacted, []}, last_message: :synthetic}}} =
               SocketCrashReport.filter(report.({error, []}), [])

      normalized = Exception.normalize(:error, redacted, [])
      assert normalized.__struct__ == Exception.normalize(:error, error, []).__struct__
      refute Exception.message(normalized) =~ "synthetic-value"
      assert Exception.message(normalized) =~ "#Withheld<not logged>"
    end
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

  test "the filter keeps a bare reason and a frame that already names its arity" do
    report = fn reason ->
      %{
        level: :error,
        meta: %{},
        msg:
          {:report,
           %{
             label: {:gen_server, :terminate},
             last_message: %Phoenix.Socket.Message{topic: "lv:synthetic", event: "event"},
             reason: reason
           }}
      }
    end

    frame = {CrashingLive, :render, 1, [file: ~c"synthetic.ex", line: 1]}

    assert %{msg: {:report, %{reason: :synthetic_exit}}} =
             SocketCrashReport.filter(report.(:synthetic_exit), [])

    assert %{msg: {:report, %{reason: {:synthetic_exit, [^frame]}}}} =
             SocketCrashReport.filter(report.({:synthetic_exit, [frame]}), [])
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
