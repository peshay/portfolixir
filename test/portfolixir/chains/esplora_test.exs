defmodule Portfolixir.Chains.EsploraTest do
  # ADR-0059 §3, §7, §10 (Sprint 29, H2): the Esplora adapter. Every answer
  # is synthetic (Portfolixir.EsploraFixtures); no test touches the network.
  # The tests that set the operator's own URL change the application
  # environment and live in esplora_own_url_test.exs, which is not async.
  use ExUnit.Case, async: true

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Chains.Esplora

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000

  defp period(tip), do: [tip, tip - 2016]

  defp read(opts \\ []), do: Esplora.read(&period/1, Keyword.put_new(opts, :now, @now))

  defp requested do
    receive do
      {:esplora, host, path} -> [{host, suffix(path)} | requested()]
    after
      0 -> []
    end
  end

  # User story:
  # As the operator whose instance reads Bitcoin's halvings from the chain,
  # I want the chain source to ask one public Esplora host for the tip height
  # and the few blocks a run needs, and nothing else,
  # so that the app learns the two figures ADR-0059 opens and no host learns
  # more than that a block was read.
  #
  # Acceptance criteria:
  # - A run asks mempool.space for the tip, the hash at height 0 when the
  #   genesis check is due, and the hash and block of each height asked:
  #   only the three Esplora reads, six requests on an ordinary run.
  # - blockstream.info is not asked while mempool.space answers.
  # - The reading carries the source, its host and base, the tip, each
  #   block's height, hash and timestamp, and whether the genesis was checked.
  # - The genesis check runs only when the caller says it is due.
  describe "a run asks one source for what it needs" do
    test "mempool.space answers the tip, the genesis hash and the blocks asked" do
      serve(%{"mempool.space" => {:chain, @tip}, "blockstream.info" => {:chain, @tip}})

      assert {:ok, reading} = read()

      assert reading.source == :mempool
      assert reading.host == "mempool.space"
      assert reading.base == "https://mempool.space/api"
      assert reading.tip == @tip
      assert reading.genesis_checked

      assert reading.blocks == %{
               @tip => %{height: @tip, hash: hash(@tip), timestamp: timestamp(@tip)},
               (@tip - 2016) => %{
                 height: @tip - 2016,
                 hash: hash(@tip - 2016),
                 timestamp: timestamp(@tip - 2016)
               }
             }

      assert requested() == [
               {"mempool.space", "blocks/tip/height"},
               {"mempool.space", "block-height/0"},
               {"mempool.space", "block-height/#{@tip}"},
               {"mempool.space", "block/#{hash(@tip)}"},
               {"mempool.space", "block-height/#{@tip - 2016}"},
               {"mempool.space", "block/#{hash(@tip - 2016)}"}
             ]
    end

    test "the genesis check runs only when it is due" do
      serve(%{"mempool.space" => {:chain, @tip}})

      assert {:ok, reading} = read(genesis_due?: fn "mempool.space" -> false end)

      refute reading.genesis_checked
      refute {"mempool.space", "block-height/0"} in requested()
    end

    test "the heights asked are a function of the tip the source answered" do
      serve(%{"mempool.space" => {:chain, 840_005}})

      assert {:ok, reading} =
               Esplora.read(fn tip -> [tip, 840_000] end,
                 now: @now,
                 genesis_due?: fn _ -> false end
               )

      assert Map.keys(reading.blocks) |> Enum.sort() == [840_000, 840_005]
      assert reading.blocks[840_000].timestamp == timestamp(840_000)
    end
  end

  # User story:
  # As the operator whose halvings land as primary-quality facts,
  # I want every answer checked before the run hands it on,
  # so that a lagging source, a source on another chain or a lying answer
  # writes nothing, and the fallback is asked instead.
  #
  # Acceptance criteria (ADR-0059 §7), each refused with its reason:
  # - the tip is a decimal integer of at most 12 digits (`invalid_tip`) and
  #   not more than 6 below the last stored tip (`tip_behind`);
  # - a hash has exactly 64 hex characters (`invalid_hash`);
  # - a block's `id` and `height` echo the hash and height asked
  #   (`block_mismatch`), and its fields are there (`invalid_block`);
  # - a timestamp is an integer between the genesis block's time and the
  #   server's clock + 2 hours (`timestamp_out_of_bounds`);
  # - the hash at height 0 equals Bitcoin's genesis hash (`wrong_chain`).
  # - A refused primary is followed by the fallback, whose reading is the
  #   whole answer: nothing of the primary's is mixed in.
  describe "every answer is checked before it is handed on" do
    for {label, body} <- [
          {"not a number", "eight hundred"},
          {"negative", "-5"},
          {"a fraction", "870000.5"},
          {"thirteen digits", "1000000000000"},
          {"empty", ""},
          {"a JSON number in exponent form", "8.7e5"}
        ] do
      test "a tip that is #{label} is refused as invalid_tip" do
        serve(%{
          "mempool.space" => {:chain, @tip, %{"blocks/tip/height" => {200, unquote(body)}}},
          "blockstream.info" => {:chain, @tip + 1}
        })

        assert {:ok, reading} = read()
        assert reading.source == :blockstream
        assert reading.tip == @tip + 1

        assert attempts(reading) == [
                 %{source: :mempool, host: "mempool.space", error: "invalid_tip"}
               ]
      end
    end

    test "a tip more than 6 below the last stored tip is refused as tip_behind" do
      serve(%{"mempool.space" => {:chain, @tip - 7}, "blockstream.info" => {:chain, @tip - 6}})

      assert {:ok, reading} = read(last_tip: @tip)
      assert reading.source == :blockstream
      assert reading.tip == @tip - 6

      assert attempts(reading) == [
               %{source: :mempool, host: "mempool.space", error: "tip_behind"}
             ]

      # The primary was asked for nothing past its tip.
      assert for({"mempool.space", path} <- requested(), do: path) == ["blocks/tip/height"]
    end

    test "a tip that runs backwards on both sources is refused by both, and nothing is handed on" do
      serve(%{"mempool.space" => {:chain, @tip - 100}, "blockstream.info" => {:chain, @tip - 50}})

      assert {:error, failures} = read(last_tip: @tip)

      assert failures == [
               %{source: :mempool, host: "mempool.space", error: "tip_behind"},
               %{source: :blockstream, host: "blockstream.info", error: "tip_behind"}
             ]
    end

    test "a source on another chain is refused as wrong_chain" do
      serve(%{
        "mempool.space" => {:chain, @tip, %{"block-height/0" => {200, testnet_genesis_hash()}}},
        "blockstream.info" => {:chain, @tip}
      })

      assert {:ok, reading} = read()
      assert reading.source == :blockstream

      assert attempts(reading) == [
               %{source: :mempool, host: "mempool.space", error: "wrong_chain"}
             ]
    end

    for {label, body} <- [
          {"63 characters", String.duplicate("a", 63)},
          {"65 characters", String.duplicate("a", 65)},
          {"not hex", String.duplicate("g", 64)},
          {"a path", "../../blocks/tip/height" <> String.duplicate("a", 41)}
        ] do
      test "a hash of #{label} is refused as invalid_hash and never asked for" do
        body = unquote(body)

        serve(%{
          "mempool.space" => {:chain, @tip, %{"block-height/#{@tip}" => {200, body}}},
          "blockstream.info" => {:chain, @tip}
        })

        assert {:ok, reading} = read()
        assert reading.source == :blockstream

        assert attempts(reading) == [
                 %{source: :mempool, host: "mempool.space", error: "invalid_hash"}
               ]

        refute Enum.any?(requested(), fn {host, path} ->
                 host == "mempool.space" and String.starts_with?(path, "block/")
               end)
      end
    end

    test "a block that echoes another height is refused as block_mismatch" do
      other = Map.put(block(@tip), "height", @tip - 1)

      serve(%{
        "mempool.space" =>
          {:chain, @tip, %{"block/#{hash(@tip)}" => {200, Jason.encode!(other)}}},
        "blockstream.info" => {:chain, @tip}
      })

      assert {:ok, reading} = read()
      assert reading.source == :blockstream

      assert attempts(reading) == [
               %{source: :mempool, host: "mempool.space", error: "block_mismatch"}
             ]
    end

    test "a block that echoes another hash is refused as block_mismatch" do
      other = Map.put(block(@tip), "id", hash(@tip - 1))

      serve(%{
        "mempool.space" =>
          {:chain, @tip, %{"block/#{hash(@tip)}" => {200, Jason.encode!(other)}}},
        "blockstream.info" => {:status, 503}
      })

      assert {:error, failures} = read()

      assert failures == [
               %{source: :mempool, host: "mempool.space", error: "block_mismatch"},
               %{source: :blockstream, host: "blockstream.info", error: "http_503"}
             ]
    end

    for {label, body} <- [
          {"not JSON", "<html>block</html>"},
          {"a JSON list", "[1, 2]"},
          {"without a timestamp", Jason.encode!(%{"id" => "x", "height" => 1})},
          {"with a timestamp as text", :timestamp_text},
          {"with a fractional timestamp", :timestamp_float},
          {"with a height as text", :height_text}
        ] do
      test "a block #{label} is refused as invalid_block or block_mismatch" do
        body =
          case unquote(body) do
            :timestamp_text ->
              Jason.encode!(Map.put(block(@tip), "timestamp", "#{timestamp(@tip)}"))

            :timestamp_float ->
              Jason.encode!(Map.put(block(@tip), "timestamp", timestamp(@tip) + 0.5))

            :height_text ->
              Jason.encode!(Map.put(block(@tip), "height", "#{@tip}"))

            text ->
              text
          end

        serve(%{
          "mempool.space" => {:chain, @tip, %{"block/#{hash(@tip)}" => {200, body}}},
          "blockstream.info" => {:chain, @tip}
        })

        assert {:ok, reading} = read()
        assert reading.source == :blockstream
        assert [%{source: :mempool, error: error}] = attempts(reading)
        assert error in ["invalid_block", "block_mismatch"]
      end
    end

    test "a timestamp in the future beyond the clock's two hours is refused" do
      future = DateTime.to_unix(@now) + 7_201
      lying = Map.put(block(@tip), "timestamp", future)

      serve(%{
        "mempool.space" =>
          {:chain, @tip, %{"block/#{hash(@tip)}" => {200, Jason.encode!(lying)}}},
        "blockstream.info" => {:chain, @tip}
      })

      assert {:ok, reading} = read()
      assert reading.source == :blockstream

      assert attempts(reading) == [
               %{source: :mempool, host: "mempool.space", error: "timestamp_out_of_bounds"}
             ]
    end

    test "a timestamp exactly two hours ahead of the clock is accepted" do
      edge = DateTime.to_unix(@now) + 7_200
      ahead = Map.put(block(@tip), "timestamp", edge)

      serve(%{
        "mempool.space" => {:chain, @tip, %{"block/#{hash(@tip)}" => {200, Jason.encode!(ahead)}}}
      })

      assert {:ok, %{source: :mempool} = reading} = read()
      assert reading.blocks[@tip].timestamp == edge
    end

    test "a timestamp before the genesis block is refused" do
      early = Map.put(block(@tip), "timestamp", genesis_time() - 1)

      serve(%{
        "mempool.space" =>
          {:chain, @tip, %{"block/#{hash(@tip)}" => {200, Jason.encode!(early)}}},
        "blockstream.info" => {:chain, @tip}
      })

      assert {:ok, reading} = read()

      assert attempts(reading) == [
               %{source: :mempool, host: "mempool.space", error: "timestamp_out_of_bounds"}
             ]
    end

    test "a tip of exactly 6 below the last stored tip is accepted" do
      serve(%{"mempool.space" => {:chain, @tip - 6}})

      assert {:ok, %{source: :mempool, tip: tip}} = read(last_tip: @tip)
      assert tip == @tip - 6
    end
  end

  # User story:
  # As the operator whose chain source may fail,
  # I want a failing primary followed by the fallback in the same run, and a
  # run where both fail to hand nothing on,
  # so that one bad host never stops the halvings and never writes half an
  # answer (ADR-0059 §7).
  #
  # Acceptance criteria:
  # - A timeout, a 429, a 5xx, a 404, a refused connection or a body over
  #   the 64 KiB cap on the primary is followed by the fallback.
  # - A redirect is never followed, not even within the same host: the
  #   answer is refused as `redirect_refused` and its location is not asked.
  # - Both failing answer `{:error, failures}` with each source's reason.
  describe "failure behaviour" do
    for {label, spec, code} <- [
          {"a 503", {:status, 503}, "http_503"},
          {"a 429", {:status, 429}, "http_429"},
          {"a 404", {:status, 404}, "http_404"},
          {"a timeout", {:chain, 870_000, %{"blocks/tip/height" => :timeout}}, "timeout"}
        ] do
      test "#{label} on the primary is followed by the fallback" do
        serve(%{
          "mempool.space" => unquote(Macro.escape(spec)),
          "blockstream.info" => {:chain, @tip}
        })

        assert {:ok, reading} = read()
        assert reading.source == :blockstream
        assert reading.host == "blockstream.info"
        assert reading.base == "https://blockstream.info/api"

        assert attempts(reading) == [
                 %{source: :mempool, host: "mempool.space", error: unquote(code)}
               ]
      end
    end

    test "a refused connection on the primary is followed by the fallback" do
      serve(%{"blockstream.info" => {:chain, @tip}})

      assert {:ok, %{source: :blockstream} = reading} = read()
      assert [%{source: :mempool, error: "transport_error"}] = attempts(reading)
    end

    test "a body over the 64 KiB cap is refused" do
      big = String.duplicate("1", 64 * 1024 + 1)

      serve(%{
        "mempool.space" => {:chain, @tip, %{"blocks/tip/height" => {200, big}}},
        "blockstream.info" => {:chain, @tip}
      })

      assert {:ok, reading} = read()
      assert [%{source: :mempool, error: "body_too_large"}] = attempts(reading)
    end

    for {label, location} <- [
          {"to another host", "https://elsewhere.example.com/api/blocks/tip/height"},
          {"to the fallback's host", "https://blockstream.info/api/blocks/tip/height"},
          {"within its own host", "https://mempool.space/api/v2/blocks/tip/height"},
          {"to plain http", "http://mempool.space/api/blocks/tip/height"}
        ] do
      test "a redirect #{label} is never followed" do
        serve(%{
          "mempool.space" =>
            {:chain, @tip, %{"blocks/tip/height" => {:redirect, 302, unquote(location)}}},
          "elsewhere.example.com" => {:chain, @tip + 50},
          "blockstream.info" => {:status, 503}
        })

        assert {:error, failures} = read()

        assert failures == [
                 %{source: :mempool, host: "mempool.space", error: "redirect_refused"},
                 %{source: :blockstream, host: "blockstream.info", error: "http_503"}
               ]

        assert requested() == [
                 {"mempool.space", "blocks/tip/height"},
                 {"blockstream.info", "blocks/tip/height"}
               ]
      end
    end

    test "both sources failing hand nothing on, each with its reason" do
      serve(%{
        "mempool.space" => {:status, 502},
        "blockstream.info" => {:chain, @tip, %{"block-height/0" => {200, testnet_genesis_hash()}}}
      })

      assert {:error, failures} = read()

      assert failures == [
               %{source: :mempool, host: "mempool.space", error: "http_502"},
               %{source: :blockstream, host: "blockstream.info", error: "wrong_chain"}
             ]
    end
  end

  # User story:
  # As the operator who may point the chain source at an own instance,
  # I want the URL I set checked as every outbound URL is,
  # so that a plain-http or private address is refused with its reason
  # rather than reached (ADR-0059 §3, §14).
  #
  # Acceptance criteria:
  # - https, no userinfo, no query or fragment, a host resolving to public
  #   addresses only; each refusal names its reason.
  describe "the operator's own URL is checked" do
    test "a public https base passes" do
      assert Esplora.check_own_url("https://node.example.com/api") == :ok
    end

    for {url, reason} <- [
          {"http://node.example.com/api", :scheme},
          {"https://internal.test/api", :private_address},
          {"https://loopback.test/api", :private_address},
          {"https://127.0.0.1/api", :private_address},
          {"https://v6local.test/api", :private_address},
          {"https://mixed.test/api", :private_address},
          {"https://user:pass@node.example.com/api", :userinfo},
          {"https://node.example.com/api?x=1", :query},
          {"https://node.example.com/api#frag", :query},
          {"https://unresolvable.test/api", :unresolvable},
          {"node.example.com/api", :scheme}
        ] do
      test "#{url} is refused as #{reason}" do
        assert Esplora.check_own_url(unquote(url)) ==
                 {:error, {:url_not_allowed, unquote(reason)}}
      end
    end
  end

  defp attempts(%{attempts: attempts}), do: attempts
end
