defmodule Portfolixir.LazyLoad do
  @moduledoc """
  Unloads a module, so a test can check that a capability check loads the
  module before it asks (#936).

  `function_exported?/3` answers false for a module the code server has not
  loaded yet, and under interactive code loading (dev and test; a release
  preloads) a module loads on its first call. A check that asks without
  loading first therefore answers by test order. Unloading a module here
  puts it back in the "nothing has touched it yet" state on purpose.

  Only the modules below are unloaded, each by one test and referred to by
  nothing else, so unloading one cannot pull code out from under a
  concurrent test.
  """

  @unloadable [__MODULE__.HistoryProvider, __MODULE__.SnapshotRow, __MODULE__.LockedRow]

  @doc "Unloads `module` (one of this file's modules); it loads again on its next use."
  @spec unload!(module()) :: module()
  def unload!(module) when module in @unloadable do
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
    false = :code.is_loaded(module)
    module
  end
end

defmodule Portfolixir.LazyLoad.HistoryProvider do
  @moduledoc "An FX provider that publishes a (one-row) history; see `Portfolixir.LazyLoad`."
  @behaviour Portfolixir.Fx.RateSync.Provider

  @impl true
  def id, do: :lazy_history

  @impl true
  def fetch(_opts), do: {:ok, []}

  # A date no other test books a rate on: the rate table's unique key would
  # otherwise make two concurrent sandboxes wait on each other.
  @impl true
  def fetch_history(_opts) do
    {:ok,
     [
       %{
         base_currency: "EUR",
         quote_currency: "USD",
         date: ~D[2003-04-17],
         rate: "1.0500",
         source: "ecb"
       }
     ]}
  end
end

defmodule Portfolixir.LazyLoad.SnapshotRow do
  @moduledoc "A schema for the journal serializer's check; never persisted. See `Portfolixir.LazyLoad`."
  use Ecto.Schema

  schema "lazy_load_rows" do
    field(:name, :string)
  end
end

defmodule Portfolixir.LazyLoad.LockedRow do
  @moduledoc "A schema for the journal lock's check; never persisted. See `Portfolixir.LazyLoad`."
  use Ecto.Schema

  schema "lazy_load_rows" do
    field(:name, :string)
  end
end
