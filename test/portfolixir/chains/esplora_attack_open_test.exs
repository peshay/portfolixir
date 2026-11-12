defmodule Portfolixir.Chains.EsploraAttackOpenTest do
  # Sprint 29, H2, attack lens: the cases the lens found open, held since
  # (ADR-0059 §7, the checks the attack lens added). The pins at the end
  # name each refusal's code and the bounds' exact edges.
  use ExUnit.Case, async: true

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Chains.Esplora

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000

  defp period(tip), do: [tip, tip - 2016]

  defp requested do
    receive do
      {:esplora, host, path} -> [{host, suffix(path)} | requested()]
    after
      0 -> []
    end
  end

  # F1: a hostile tip below 2,016 on a first run (no last_tip) makes the
  # caller's ordinary heights negative; the adapter raises instead of failing
  # the source, so the honest fallback is never asked.
  test "a tip too small for the run's heights fails the source, not the run" do
    serve(%{
      "mempool.space" => {:chain, @tip, %{"blocks/tip/height" => {200, "5"}}},
      "blockstream.info" => {:chain, @tip}
    })

    assert {:ok, %{source: :blockstream}} = Esplora.read(&period/1, now: @now)
  end

  # F2: the blocks of one run are not checked against each other: the tip's
  # block may be older than the block 2,016 below it (H3's mean block time
  # would be negative).
  test "a tip block older than the block 2,016 below it is refused" do
    early = Map.put(block(@tip), "timestamp", timestamp(@tip - 2016) - 600)

    serve(%{
      "mempool.space" => {:chain, @tip, %{"block/#{hash(@tip)}" => {200, Jason.encode!(early)}}},
      "blockstream.info" => {:chain, @tip}
    })

    assert {:ok, %{source: :blockstream}} = Esplora.read(&period/1, now: @now)
  end

  # F3: no upper bound on the tip: a source answering a tip past the next
  # halving in 2026, with blocks fabricated to echo, hands on block 1,050,000
  # as read (H3 would confirm a halving that has not happened).
  test "a tip far ahead of what the clock allows is refused" do
    tip = 1_050_010
    ts = DateTime.to_unix(@now) - 60

    liar = fn conn ->
      case suffix(conn.request_path) do
        "blocks/tip/height" ->
          Plug.Conn.send_resp(conn, 200, Integer.to_string(tip))

        "block-height/" <> h ->
          Plug.Conn.send_resp(conn, 200, hash(String.to_integer(h)))

        "block/" <> hash ->
          h = Enum.find([0, tip, 1_050_000], &(hash(&1) == hash))
          json(conn, %{"id" => hash, "height" => h, "timestamp" => ts - (tip - h) * 600})
      end
    end

    serve(%{"mempool.space" => liar, "blockstream.info" => {:chain, @tip}})

    # The caller asks the halving only at or below the tip it is handed, as
    # a real caller does; a height above an honest fallback's tip would
    # fail that source too (`heights_out_of_range`).
    assert {:ok, %{source: :blockstream, attempts: [%{source: :mempool, error: "tip_ahead"}]}} =
             Esplora.read(fn t -> Enum.filter([t, 1_050_000], &(&1 <= t)) end, now: @now)
  end

  # F4: a last_tip that is not an integer silently turns tip_behind off.
  test "a last_tip that is not an integer is refused, not ignored" do
    serve(%{"mempool.space" => {:chain, @tip - 100}, "blockstream.info" => {:chain, @tip}})

    result =
      try do
        Esplora.read(&period/1, now: @now, last_tip: Integer.to_string(@tip))
      rescue
        ArgumentError -> :raised
      end

    assert result == :raised or match?({:ok, %{source: :blockstream}}, result)
  end

  # The pins: each refusal's code, and the bounds' edges (ADR-0059 §7).
  describe "the bounds' codes and edges" do
    defp no_genesis, do: [now: @now, genesis_due?: fn _ -> false end]

    defp primary_code(reading) do
      assert %{source: :blockstream, attempts: [%{source: :mempool, error: code}]} = reading
      code
    end

    test "a tip below the fourth halving is tip_too_low; the halving itself passes" do
      serve(%{"mempool.space" => {:chain, 839_999}, "blockstream.info" => {:chain, @tip}})
      assert {:ok, reading} = Esplora.read(&[&1], no_genesis())
      assert primary_code(reading) == "tip_too_low"

      serve(%{"mempool.space" => {:chain, 840_000}})
      assert {:ok, %{source: :mempool, tip: 840_000}} = Esplora.read(&[&1], no_genesis())
    end

    test "a tip of 5 asks no block of the source that answered it" do
      serve(%{
        "mempool.space" => {:chain, @tip, %{"blocks/tip/height" => {200, "5"}}},
        "blockstream.info" => {:chain, @tip}
      })

      assert {:ok, reading} = Esplora.read(&period/1, now: @now)
      assert primary_code(reading) == "tip_too_low"
      assert for({"mempool.space", path} <- requested(), do: path) == ["blocks/tip/height"]
    end

    # The ceiling at 2026-11-12 12:00 UTC: (now − genesis time) / 600 × 1.1,
    # rounded down: 563,478,295 s / 600 × 1.1 = 1,033,043.5.
    test "the tip's ceiling is the clock's ten-minute height times 1.1" do
      serve(%{"mempool.space" => {:chain, 1_033_043}})

      assert {:ok, %{source: :mempool, tip: 1_033_043}} =
               Esplora.read(fn _ -> [] end, no_genesis())

      serve(%{"mempool.space" => {:chain, 1_033_044}, "blockstream.info" => {:chain, @tip}})
      assert {:ok, reading} = Esplora.read(fn _ -> [] end, no_genesis())
      assert primary_code(reading) == "tip_ahead"
    end

    test "a tip block no later than the block 2,016 below it is blocks_out_of_order" do
      for delta <- [0, -600] do
        same = Map.put(block(@tip), "timestamp", timestamp(@tip - 2016) + delta)

        serve(%{
          "mempool.space" =>
            {:chain, @tip, %{"block/#{hash(@tip)}" => {200, Jason.encode!(same)}}},
          "blockstream.info" => {:chain, @tip}
        })

        assert {:ok, reading} = Esplora.read(&period/1, no_genesis())
        assert primary_code(reading) == "blocks_out_of_order"
      end
    end

    test "a last_tip that is not a non-negative integer raises before any request" do
      serve(%{"mempool.space" => {:chain, @tip}})

      for last_tip <- ["870000", 870_000.0, -1, :tip] do
        assert_raise ArgumentError, fn ->
          Esplora.read(&period/1, now: @now, last_tip: last_tip)
        end
      end

      assert requested() == []
    end
  end
end

defmodule Portfolixir.Chains.EsploraAttackOpenConfigTest do
  # F5: the adapter narrows `:any` to the base's host for every source key,
  # not only `:own`, so a config source with `:any` reaches its base's host.
  use ExUnit.Case, async: false

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Chains.Esplora

  test "only the own URL may carry :any; another source with :any reaches nothing" do
    saved = Application.get_env(:portfolixir, Esplora)
    on_exit(fn -> Application.put_env(:portfolixir, Esplora, saved) end)

    Application.put_env(
      :portfolixir,
      Esplora,
      Keyword.merge(saved,
        sources: [extra: "https://api.llm-vendor.example/v1"],
        allowed_hosts: Map.put(saved[:allowed_hosts], :extra, :any)
      )
    )

    serve(%{"api.llm-vendor.example" => {:chain, 870_000}})

    assert {:error, [%{source: :extra, error: "url_not_allowed:host_not_allowed"}]} =
             Esplora.read(&[&1], now: ~U[2026-11-12 12:00:00Z])
  end

  test "a config source named :own raises: the own source is the environment's URL alone" do
    saved = Application.get_env(:portfolixir, Esplora)
    on_exit(fn -> Application.put_env(:portfolixir, Esplora, saved) end)

    Application.put_env(
      :portfolixir,
      Esplora,
      Keyword.put(saved, :sources, own: "https://api.llm-vendor.example/v1")
    )

    serve(%{"api.llm-vendor.example" => {:chain, 870_000}})

    assert_raise ArgumentError, fn -> Esplora.read(&[&1], now: ~U[2026-11-12 12:00:00Z]) end
    refute_received {:esplora, _, _}
  end
end
