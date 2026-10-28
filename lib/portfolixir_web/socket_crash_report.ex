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
  is turned into text. The crash, its reason and its stack stay in the log.

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

  @doc "The filter: a GenServer terminate report's last socket message, cut to its topic and event."
  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(
        %{msg: {:report, %{label: {:gen_server, :terminate}, last_message: last} = report}} =
          event,
        _extra
      ) do
    case redact(last) do
      {:ok, redacted} -> %{event | msg: {:report, %{report | last_message: redacted}}}
      :keep -> :ignore
    end
  end

  def filter(_event, _extra), do: :ignore

  defp redact(%Phoenix.Socket.Message{topic: topic, event: event}),
    do: {:ok, [topic: topic, event: event]}

  defp redact({Phoenix.Channel, _payload, _from, %Phoenix.Socket{topic: topic}}),
    do: {:ok, [topic: topic, event: "phx_join"]}

  defp redact(_message), do: :keep
end
