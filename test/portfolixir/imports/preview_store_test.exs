defmodule Portfolixir.Imports.PreviewStoreTest do
  # async: false — all tests share the single named ETS table
  # (:Portfolixir.Imports.PreviewStore) started by the application supervisor.
  # Running concurrently would cause key collisions between tests.
  use ExUnit.Case, async: false

  alias Portfolixir.Imports.PreviewStore

  # Use per-test unique tokens to prevent cross-test interference on the
  # shared ETS table.
  defp token(label \\ "default"),
    do: "test-token-#{label}-#{System.unique_integer([:positive])}"

  # User story:
  # As a local portfolio maintainer who switches the UI locale mid-upload,
  # I want the parsed preview and mapping to survive the LiveView remount,
  # so that I do not have to re-upload the file after changing language.
  #
  # Acceptance criteria:
  # - put/3 followed by get/1 returns the same preview and mapping.
  # - get/1 on an absent key returns nil.
  # - delete/1 removes the entry so subsequent get/1 returns nil.
  # - The periodic sweep prunes expired entries while retaining fresh ones.

  describe "put/3 + get/1 round-trip" do
    test "returns the stored preview and mapping" do
      tok = token("put-get")
      preview = %{format: :json, entries: []}
      mapping = %{portfolio_choice: "create"}

      assert :ok = PreviewStore.put(tok, preview, mapping)
      assert {^preview, ^mapping} = PreviewStore.get(tok)
    end

    test "a second put overwrites the first entry" do
      tok = token("overwrite")
      assert :ok = PreviewStore.put(tok, :v1, :m1)
      assert :ok = PreviewStore.put(tok, :v2, :m2)
      assert {:v2, :m2} = PreviewStore.get(tok)
    end
  end

  describe "get/1" do
    test "returns nil for a key that was never stored" do
      tok = token("miss")
      assert PreviewStore.get(tok) == nil
    end
  end

  describe "delete/1" do
    test "removes the entry so subsequent get returns nil" do
      tok = token("delete")
      assert :ok = PreviewStore.put(tok, :preview, :mapping)
      assert {:preview, :mapping} = PreviewStore.get(tok)

      assert :ok = PreviewStore.delete(tok)
      assert PreviewStore.get(tok) == nil
    end

    test "delete on a non-existent key is a no-op returning :ok" do
      tok = token("delete-miss")
      assert :ok = PreviewStore.delete(tok)
    end
  end

  describe "handle_info(:sweep, …) TTL expiry" do
    test "sweep prunes stale entries while retaining fresh ones" do
      fresh_tok = token("fresh")
      stale_tok = token("stale")

      # Insert a fresh entry via the public API.
      assert :ok = PreviewStore.put(fresh_tok, :fresh_preview, :fresh_mapping)

      # Directly inject a stale entry into the ETS table with a timestamp
      # far in the past (2 hours + 1 second beyond the TTL), bypassing
      # the public API so we can control the touched_at timestamp.
      table = Portfolixir.Imports.PreviewStore
      stale_time = System.os_time(:second) - (7_200 + 1)
      :ets.insert(table, {stale_tok, :stale_preview, :stale_mapping, stale_time})

      # Verify both are visible before the sweep.
      assert PreviewStore.get(fresh_tok) != nil
      assert :ets.lookup(table, stale_tok) != []

      # Send the sweep message directly to the GenServer and wait for it to
      # process, then assert the expected post-sweep state.
      send(Process.whereis(Portfolixir.Imports.PreviewStore), :sweep)

      # Allow the GenServer to process the message before asserting.
      # We give it up to 500 ms; in practice it is nearly instantaneous.
      assert wait_until(fn -> :ets.lookup(table, stale_tok) == [] end),
             "stale entry was not pruned by the sweep"

      # Fresh entry must still be present.
      assert PreviewStore.get(fresh_tok) != nil

      # Cleanup.
      PreviewStore.delete(fresh_tok)
    end
  end

  # Poll up to ~500 ms (50 × 10 ms) for a condition to become truthy.
  defp wait_until(fun, attempts \\ 50)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: false
end
