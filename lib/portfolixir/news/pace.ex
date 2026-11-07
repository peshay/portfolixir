defmodule Portfolixir.News.Pace do
  @moduledoc """
  The per-host request pace of the news fetcher (ADR-0056 §5): `sec.gov`
  asks for at most 10 requests per second, so its requests are handed out
  at least 100 ms apart, whichever feed's task asks. One process for the
  node keeps the next free slot per host; `reserve/3` books a slot and
  answers how long the caller waits for it. The caller waits, never this
  process, so a slow host holds up no one but the feeds that queue for it.
  """

  use GenServer

  @spacing_ms 100

  @doc "The least time between two requests to one paced host."
  @spec spacing_ms() :: pos_integer()
  def spacing_ms, do: @spacing_ms

  @doc "Starts the pace; `name: nil` starts an unnamed one (for a test)."
  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, :ok)
      name -> GenServer.start_link(__MODULE__, :ok, name: name)
    end
  end

  @doc "Books the next slot for `key` now on the node's pace; see `reserve/3`."
  @spec reserve(String.t()) :: non_neg_integer()
  def reserve(key), do: reserve(__MODULE__, key, System.monotonic_time(:millisecond))

  @doc """
  Books the next slot for `key` at the monotonic time `now_ms` and returns
  the milliseconds until it: 0 when the host is free.
  """
  @spec reserve(GenServer.server(), String.t(), integer()) :: non_neg_integer()
  def reserve(server, key, now_ms) when is_binary(key) and is_integer(now_ms),
    do: GenServer.call(server, {:reserve, key, now_ms})

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:reserve, key, now_ms}, _from, next_free) do
    slot = max(now_ms, Map.get(next_free, key, now_ms))
    {:reply, slot - now_ms, Map.put(next_free, key, slot + @spacing_ms)}
  end
end
