defmodule PortfolixirWeb.LiveSocket do
  @moduledoc """
  The LiveView socket behind `/live`: `Phoenix.LiveView.Socket`, bounded
  before it decodes (security review 2026-10-12, H02).

  Phoenix dispatches the socket ahead of every plug of the endpoint, so its
  transport process meets neither `PortfolixirWeb.HeapCap` nor the body
  parser's bounds, and it decodes each message before any session or
  credential is looked at. Three bounds close that:

  - the socket line's `max_frame_size`, `max_message_bytes/0`, under which
    Bandit refuses a larger frame before it reads it whole, and the
    listener's `max_fragmented_message_size` (config/config.exs), the same
    figure for a message sent in fragments;
  - `handle_in/2` refuses a message past that size, or a text message nested
    past `PortfolixirWeb.JsonDepth.max_depth/0`, before the serializer
    decodes it, and closes the socket;
  - `init/1` puts the transport process under the heap cap, as the plug does
    for every request process.

  The bound is 512 KiB. A LiveView event carries a form's values url-encoded:
  the longest text field, a research-log entry of 20,000 code points, is at
  most about 240 KB that way. An Imports upload travels in chunks of 64 KB,
  LiveView's default.
  """

  @behaviour Phoenix.Socket.Transport

  alias Phoenix.LiveView.Socket
  alias PortfolixirWeb.HeapCap
  alias PortfolixirWeb.JsonDepth

  @max_message_bytes 524_288

  @doc "The largest frame or message the socket accepts, in bytes."
  @spec max_message_bytes() :: pos_integer()
  def max_message_bytes, do: @max_message_bytes

  @impl Phoenix.Socket.Transport
  defdelegate child_spec(opts), to: Socket

  @impl Phoenix.Socket.Transport
  defdelegate drainer_spec(opts), to: Socket

  @impl Phoenix.Socket.Transport
  defdelegate connect(transport_info), to: Socket

  @impl Phoenix.Socket.Transport
  def init(state) do
    HeapCap.cap!()
    Socket.init(state)
  end

  @impl Phoenix.Socket.Transport
  def handle_in({payload, opts} = message, state) do
    if acceptable?(payload, Keyword.get(opts, :opcode)) do
      Socket.handle_in(message, state)
    else
      {:stop, {:shutdown, :message_refused}, state}
    end
  end

  @impl Phoenix.Socket.Transport
  defdelegate handle_info(message, state), to: Socket

  @impl Phoenix.Socket.Transport
  defdelegate terminate(reason, state), to: Socket

  defp acceptable?(payload, _opcode) when byte_size(payload) > @max_message_bytes, do: false
  defp acceptable?(payload, :text), do: JsonDepth.within_bound?(payload)
  defp acceptable?(_payload, _opcode), do: true
end
