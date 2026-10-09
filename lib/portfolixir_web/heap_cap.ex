defmodule PortfolixirWeb.HeapCap do
  @moduledoc """
  A heap cap on every HTTP request process and every LiveView process
  (E25 S4, G05), instead of one growing until the node runs out of memory
  and takes every other request with it: a request's process or a page's
  own process past it is killed and fails alone. A page's `start_async`
  load runs in a task linked to the page, so the cap's kill takes the page
  down with it, and the page reconnects (#1204 holds whether it should fail
  alone); a task the page starts apart from itself (`CappedAsync.start/1`,
  `start_child/2`) fails alone.

  Defence in depth, not the bound itself: the inputs, lists, memo and walks
  are bounded where they arrive. The cap counts the off-heap binaries the
  process references (`include_shared_binaries`), so a large body or upload
  held by one process counts against it too.

  The size is `max_heap_bytes` under this module's configuration
  (512 MiB by default), far above any legitimate read or write of a
  self-hosted instance. A killed process is logged by the runtime.

  Used as a plug at the top of the endpoint, so it covers every request
  process, and as an `on_mount` hook of the LiveView session. A process flag
  is not inherited, so every task a page starts caps itself the same way, as
  its first act, through `PortfolixirWeb.CappedAsync` (#941).
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

  @doc "Caps the calling process's heap: the first act of every task a page starts (#941)."
  @spec cap!() :: :ok
  def cap! do
    Process.flag(:max_heap_size, %{
      size: max_heap_words(),
      kill: true,
      error_logger: true,
      include_shared_binaries: true
    })

    :ok
  end
end
