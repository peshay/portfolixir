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

  # User story (#768):
  # As an operator whose instance is reachable by more than one browser,
  # I want the preview store bounded and keyed by a derived value,
  # so that parked previews cannot grow without limit and the raw session
  # secret never sits in a public table.
  #
  # Acceptance criteria:
  # - put/3 with a nil or empty key stores nothing.
  # - The store keeps at most `max_entries/0` previews; the oldest-touched
  #   entry is evicted when a new one arrives.
  # - put_mapping/2 replaces only the mapping of an existing entry and is a
  #   no-op for an absent key.
  # - key_for/1 derives a fixed-length key that is not the token itself.
  describe "budget and keying" do
    test "refuses empty keys" do
      assert :ignored = PreviewStore.put(nil, :preview, :mapping)
      assert :ignored = PreviewStore.put("", :preview, :mapping)
      assert PreviewStore.get("") == nil
    end

    test "evicts the oldest-touched entry past the budget" do
      PreviewStore.clear()
      keys = for i <- 1..(PreviewStore.max_entries() + 1), do: token("budget-#{i}")

      keys
      |> Enum.with_index()
      |> Enum.each(fn {key, index} ->
        assert :ok = PreviewStore.put(key, {:preview, index}, :mapping, touched_at: index)
      end)

      [oldest | rest] = keys
      assert PreviewStore.get(oldest) == nil
      assert Enum.all?(rest, &(PreviewStore.get(&1) != nil))
    end

    test "put_mapping/2 replaces only the mapping" do
      key = token("mapping")
      assert :ok = PreviewStore.put(key, :preview, :m1)
      assert :ok = PreviewStore.put_mapping(key, :m2)
      assert {:preview, :m2} = PreviewStore.get(key)

      assert :ignored = PreviewStore.put_mapping(token("absent"), :m3)
    end

    test "key_for/1 derives a fixed-length key that is not the token" do
      key = PreviewStore.key_for("csrf-secret")
      assert key != "csrf-secret"
      assert String.length(key) == 64
      assert key == PreviewStore.key_for("csrf-secret")
      assert PreviewStore.key_for(nil) == nil
      assert PreviewStore.key_for("") == nil
    end
  end
end
