defmodule PortfolixirWeb.SocketCrashReport do
  @moduledoc """
  A `:logger` primary filter that logs a crashing live page by its topic and
  event name only (security review 2026-10-12, H71).

  When a page's process crashes, the runtime's report names the last message
  the process received, and the info level keeps that line: for a page event
  the `Phoenix.Socket.Message` with the form's values, for a mount the join
  with the decoded session and the signed session token. The deployment guide
  says form values and session contents stay out of the log, so the filter
  rewrites that last message to `[topic: ..., event: ...]` before the report
  is turned into text. A handler without a matching clause (a
  `FunctionClauseError`) prints its arguments in the stack's top frame, the
  event's values and the page's assigns among them, so every frame's
  arguments are cut to their arity too (#1256). The crash, its reason and its
  stack stay in the log.

  The release installs it at boot (`:redact_socket_crash_reports` in
  `config/prod.exs`, `Portfolixir.Application.after_start/0`); development
  and the test suite keep the full report.
  """

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
  topic and event, and its stack frames' arguments, cut to their arity.
  """
  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(
        %{msg: {:report, %{label: {:gen_server, :terminate}, last_message: last} = report}} =
          event,
        _extra
      ) do
    case redact(last) do
      {:ok, redacted} ->
        report = %{report | last_message: redacted} |> Map.update(:reason, nil, &without_args/1)
        %{event | msg: {:report, report}}

      :keep ->
        :ignore
    end
  end

  def filter(_event, _extra), do: :ignore

  # A FunctionClauseError (and an error raised inside a BIF) carries the
  # call's arguments in its top stack frame instead of the arity: for a page
  # that is the event's values and the socket's assigns (#1256). The frame
  # keeps its module, function, arity and location.
  defp without_args({%FunctionClauseError{} = error, stack}) when is_list(stack),
    do: {%{error | args: nil}, frames_without_args(stack)}

  defp without_args({reason, stack}) when is_list(stack),
    do: {reason, frames_without_args(stack)}

  defp without_args(reason), do: reason

  defp frames_without_args(stack) do
    Enum.map(stack, fn
      {module, function, args, location} when is_list(args) ->
        {module, function, length(args), location}

      frame ->
        frame
    end)
  end

  defp redact(%Phoenix.Socket.Message{topic: topic, event: event}),
    do: {:ok, [topic: topic, event: event]}

  defp redact({Phoenix.Channel, _payload, _from, %Phoenix.Socket{topic: topic}}),
    do: {:ok, [topic: topic, event: "phx_join"]}

  defp redact(_message), do: :keep
end
