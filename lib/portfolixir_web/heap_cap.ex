defmodule PortfolixirWeb.HeapCap do
  @moduledoc """
  A heap cap on every HTTP request process and every LiveView process
  (E25 S4, G05): past it the process is killed and fails alone, instead of
  growing until the node runs out of memory and takes every other request
  with it.

  Defence in depth, not the bound itself: the inputs, lists, memo and walks
  are bounded where they arrive. The cap counts the off-heap binaries the
  process references (`include_shared_binaries`), so a large body or upload
  held by one process counts against it too.

  The size is `max_heap_bytes` under this module's configuration
  (512 MiB by default), far above any legitimate read or write of a
  self-hosted instance. A killed process is logged by the runtime.

  Used as a plug at the top of the endpoint, so it covers every request
  process, and as an `on_mount` hook of the LiveView session.
  """

  @behaviour Plug

  @default_max_heap_bytes 512 * 1024 * 1024

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    cap!()
    conn
  end

  @doc false
  def on_mount(:default, _params, _session, socket) do
    cap!()
    {:cont, socket}
  end

  @doc "The cap in machine words, as `:max_heap_size` takes it."
  @spec max_heap_words() :: pos_integer()
  def max_heap_words do
    bytes =
      :portfolixir
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:max_heap_bytes, @default_max_heap_bytes)

    div(bytes, :erlang.system_info(:wordsize))
  end

  defp cap! do
    Process.flag(:max_heap_size, %{
      size: max_heap_words(),
      kill: true,
      error_logger: true,
      include_shared_binaries: true
    })

    :ok
  end
end
