defmodule Portfolixir.LogEscape do
  @moduledoc """
  A filter on the console handler that writes every control character of a
  log entry as a visible escape (security review 2026-10-12, H69): `\\x1B`
  for ESC, `\\x0D` for a carriage return, `\\x7F` for DEL. Line feeds and
  tabs stay, so a stack trace keeps its lines.

  Request bytes reach the log (a request line, a refused WebSocket Origin,
  an exception's message), and a control character among them could forge a
  log line or send the terminal that reads the log an escape sequence. The
  filter runs on the console handler, after Elixir's translator has turned
  reports into text, so it sees what the console prints.

  `config/config.exs` installs it on the `:default` handler for every
  environment, beside the remote group-leader filter that handler carries by
  default.
  """

  @control ~r/[\x00-\x08\x0B-\x1F\x7F]/

  @doc "A `:logger` handler filter: the event with its message's control characters escaped."
  @spec filter(:logger.log_event(), term()) :: :logger.log_event()
  def filter(%{msg: {:string, chardata}} = event, _extra) do
    %{event | msg: {:string, escape(chardata)}}
  end

  def filter(%{msg: {format, args}} = event, _extra) when is_list(args) do
    %{event | msg: {:string, escape(:io_lib.format(format, args))}}
  rescue
    _malformed -> event
  end

  def filter(event, _extra), do: event

  @doc "Chardata with every control character but line feed and tab escaped."
  @spec escape(IO.chardata()) :: IO.chardata()
  def escape(binary) when is_binary(binary), do: Regex.replace(@control, binary, &hex/1)
  def escape([head | tail]), do: [escape(head) | escape(tail)]
  def escape([]), do: []

  def escape(char) when is_integer(char) and (char in 0x00..0x08 or char in 0x0B..0x1F),
    do: hex(<<char>>)

  def escape(0x7F), do: hex(<<0x7F>>)
  def escape(char) when is_integer(char), do: char

  defp hex(<<byte>>),
    do: "\\x" <> String.pad_leading(Integer.to_string(byte, 16), 2, "0")
end
