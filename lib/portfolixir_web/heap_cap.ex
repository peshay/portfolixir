defmodule PortfolixirWeb.HeapCap do
  @moduledoc """
  A heap cap on every HTTP request process and every LiveView process
  (E25 S4, G05), instead of one growing until the node runs out of memory
  and takes every other request with it: a request's process or a page's
  own process past it is killed and fails alone. A page's `start_async`
  load runs in a worker its task watches, so the cap's kill reaches the
  page as a failed load, and the page shows its own failure state (#1204);
  a task the page starts apart from itself (`CappedAsync.start/1`,
  `start_child/2`) fails alone.

  Defence in depth, not the bound itself: the inputs, lists, memo and walks
  are bounded where they arrive. The cap counts the off-heap binaries the
  process references (`include_shared_binaries`), so a large body or upload
  held by one process counts against it too. A slice of such a body must
  therefore not cross into another capped process: copied there (a task's
  closure, an ETS read), each slice longer than 64 bytes references the whole
  body and is counted as the whole body, so what is kept from a large body is
  copied out of it first (security review 2026-10-12, H58).

  The size is `max_heap_bytes` under `Portfolixir.HeapCap`'s configuration
  (512 MiB by default), which owns the cap, so the domain's background walks
  run under the same one (K08). A killed process is logged by the runtime.

  Used as a plug at the top of the endpoint, so it covers every request
  process, and as an `on_mount` hook of the LiveView session. A process flag
  is not inherited, so every task a page starts caps itself the same way, as
  its first act, through `PortfolixirWeb.CappedAsync` (#941).
  """

  @behaviour Plug

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
  defdelegate max_heap_words(), to: Portfolixir.HeapCap

  @doc "Caps the calling process's heap: the first act of every task a page starts (#941)."
  defdelegate cap!(), to: Portfolixir.HeapCap
end
