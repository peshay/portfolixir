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

  What counts as a control character is what the application's own text
  rule counts (`Portfolixir.Input.Text`; N-31): the C0 controls and DEL, the
  C1 controls U+0080 to U+009F, written `\\u009B`, and Unicode's line and
  paragraph separators, written `\\u2028` and `\\u2029`. A byte that is no
  UTF-8 is written as its own escape, `\\x9B`, so an entry is always text
  the console can print. Every other character above ASCII is left as it is.

  `config/config.exs` installs it on the `:default` handler for every
  environment, beside the remote group-leader filter that handler carries by
  default.
  """

  # Bytes that need a look: a C0 control or DEL, or anything above ASCII. An
  # entry without one, the common case, is returned as it came.
  @suspect ~r/[\x00-\x08\x0B-\x1F\x7F-\xFF]/

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
  def escape(binary) when is_binary(binary) do
    if Regex.match?(@suspect, binary), do: escape_binary(binary, []), else: binary
  end

  def escape([head | tail]), do: [escape(head) | escape(tail)]
  def escape([]), do: []
  def escape(char) when is_integer(char), do: escape_char(char)

  # A binary is read as UTF-8, one character at a time; a byte that starts
  # no valid character is escaped by itself.
  defp escape_binary(<<char::utf8, rest::binary>>, acc),
    do: escape_binary(rest, [acc, escape_utf8(char)])

  defp escape_binary(<<byte, rest::binary>>, acc), do: escape_binary(rest, [acc, hex(byte)])
  defp escape_binary(<<>>, acc), do: IO.iodata_to_binary(acc)

  defp escape_utf8(char) do
    case escape_char(char) do
      ^char -> <<char::utf8>>
      escaped -> escaped
    end
  end

  # A character of chardata, as an integer: itself, or its escape.
  defp escape_char(char) when char in 0x00..0x08 or char in 0x0B..0x1F or char == 0x7F,
    do: hex(char)

  defp escape_char(char) when char in 0x80..0x9F or char in 0x2028..0x2029,
    do: "\\u" <> String.pad_leading(Integer.to_string(char, 16), 4, "0")

  defp escape_char(char), do: char

  defp hex(byte), do: "\\x" <> String.pad_leading(Integer.to_string(byte, 16), 2, "0")
end
