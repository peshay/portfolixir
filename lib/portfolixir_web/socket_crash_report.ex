defmodule PortfolixirWeb.SocketCrashReport do
  @moduledoc """
  A `:logger` primary filter that logs a crashing live page by its topic and
  event name only (security review 2026-10-12, H71), and without the values
  its handler held.

  When a page's process crashes, the runtime's report names the last message
  the process received, and the info level keeps that line: for a page event
  the `Phoenix.Socket.Message` with the form's values, for a mount the join
  with the decoded session and the signed session token. The deployment guide
  says form values and session contents stay out of the log, so the filter
  rewrites that last message to `[topic: ..., event: ...]` before the report
  is turned into text. Any other last message (one a page's `handle_info/2`
  or `handle_async/3` was handling) stays as it is.

  The crash's reason is rewritten whatever the last message was (#1256;
  Sprint 30 closing act, security lens, finding 1): a handler without a
  matching clause (a `FunctionClauseError`) prints its arguments in the
  stack's top frame, the event's values and the page's assigns among them, so
  every frame's arguments are cut to their arity; and a failed match (a
  `MatchError`, `CaseClauseError`, `WithClauseError`, `TryClauseError`,
  `KeyError`, `BadMapError`, `BadBooleanError`, `BadStructError` or
  `BadFunctionError`) prints the value it could not match, so that value is
  replaced by `#Withheld<not logged>`. The same holds for every GenServer's
  crash report, a page's or not, and for a task's (a page's `start_async/3`),
  whose arguments are withheld too. The crash, its exception and its stack
  stay in the log.

  The release installs it at boot (`:redact_socket_crash_reports` in
  `config/prod.exs`, `Portfolixir.Application.after_start/0`); development
  and the test suite keep the full report.
  """

  defmodule Withheld do
    @moduledoc false
    # What a crash report shows in place of a value the filter keeps out of
    # the log: `nil` would read as the value itself.
    defstruct []

    defimpl Inspect do
      def inspect(_withheld, _opts), do: "#Withheld<not logged>"
    end
  end

  # The runtime's errors that carry the value they failed on in `term`.
  @with_term [
    MatchError,
    CaseClauseError,
    WithClauseError,
    TryClauseError,
    KeyError,
    BadMapError,
    BadBooleanError,
    BadStructError,
    BadFunctionError
  ]

  @doc "Installs the filter when `:redact_socket_crash_reports` is set; idempotent."
  @spec install_on_boot() :: :ok
  def install_on_boot do
    if Application.get_env(:portfolixir, :redact_socket_crash_reports, false) do
      case :logger.add_primary_filter(__MODULE__, {&__MODULE__.filter/2, []}) do
        :ok -> :ok
        {:error, {:already_exist, __MODULE__}} -> :ok
      end
    else
      :ok
    end
  end

  @doc """
  The filter: a GenServer terminate report's last socket message, cut to its
  topic and event; its reason's stack frames' arguments, cut to their arity,
  and a failed match's value, withheld; and a task's crash report's reason and
  arguments the same way.
  """
  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(
        %{msg: {:report, %{label: {:gen_server, :terminate}, last_message: last} = report}} =
          event,
        _extra
      ) do
    report =
      case redact(last) do
        {:ok, redacted} -> %{report | last_message: redacted}
        :keep -> report
      end

    %{event | msg: {:report, Map.update(report, :reason, nil, &without_values/1)}}
  end

  def filter(
        %{msg: {:report, %{label: {Task.Supervisor, :terminating}, report: task} = report}} =
          event,
        _extra
      )
      when is_map(task) do
    task =
      task
      |> Map.update(:reason, nil, &without_values/1)
      |> Map.update(:args, [], &withheld_args/1)

    %{event | msg: {:report, %{report | report: task}}}
  end

  def filter(_event, _extra), do: :ignore

  # A FunctionClauseError (and an error raised inside a BIF) carries the
  # call's arguments in its top stack frame instead of the arity: for a page
  # that is the event's values and the socket's assigns (#1256). The frame
  # keeps its module, function, arity and location. A failed match carries
  # the value it failed on.
  defp without_values({%FunctionClauseError{} = error, stack}) when is_list(stack),
    do: {%{error | args: nil}, frames_without_args(stack)}

  defp without_values({%module{term: _} = error, stack})
       when module in @with_term and is_list(stack),
       do: {%{error | term: %Withheld{}}, frames_without_args(stack)}

  # The same failures as the runtime raises them, before Elixir names them:
  # the form a process's crash report carries.
  defp without_values({{tag, _value}, stack})
       when tag in [:badmatch, :case_clause, :try_clause, :badmap, :badfun] and is_list(stack),
       do: {{tag, %Withheld{}}, frames_without_args(stack)}

  defp without_values({{:badkey, key, _map}, stack}) when is_list(stack),
    do: {{:badkey, key, %Withheld{}}, frames_without_args(stack)}

  defp without_values({reason, stack}) when is_list(stack),
    do: {reason, frames_without_args(stack)}

  defp without_values(reason), do: reason

  defp frames_without_args(stack) do
    Enum.map(stack, fn
      {module, function, args, location} when is_list(args) ->
        {module, function, length(args), location}

      frame ->
        frame
    end)
  end

  defp withheld_args(args) when is_list(args), do: Enum.map(args, fn _arg -> %Withheld{} end)
  defp withheld_args(args), do: args

  defp redact(%Phoenix.Socket.Message{topic: topic, event: event}),
    do: {:ok, [topic: topic, event: event]}

  defp redact({Phoenix.Channel, _payload, _from, %Phoenix.Socket{topic: topic}}),
    do: {:ok, [topic: topic, event: "phx_join"]}

  defp redact(_message), do: :keep
end
