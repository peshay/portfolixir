defmodule Portfolixir.Chains.EsploraAttackTest do
  # Sprint 29, H2, the closing act's security lens (D-8 item 5): a hostile
  # or lying Esplora answer, attacked by an agent that did not build the
  # adapter. Each case here was seen held: the answer is refused with its
  # reason, the fallback reads everything again, and nothing of the liar's
  # reaches the reading. Every answer is synthetic; no test opens a socket.
  use ExUnit.Case, async: true

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Chains.Esplora

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000
  @regtest_genesis "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"
  @signet_genesis "00000008819873e925422c1ff0f99f7cc9bbb232af63a077a480a3633bee1ef6"

  defp period(tip), do: [tip, tip - 2016]

  defp read(opts \\ []), do: Esplora.read(&period/1, Keyword.put_new(opts, :now, @now))

  defp requested do
    receive do
      {:esplora, host, path} -> [{host, suffix(path)} | requested()]
    after
      0 -> []
    end
  end

  # The primary answers `overrides` on top of a valid chain; the fallback is
  # honest at a tip of its own, so a reading that mixed sources would show.
  defp primary_lies(overrides) do
    serve(%{
      "mempool.space" => {:chain, @tip, overrides},
      "blockstream.info" => {:chain, @tip + 3}
    })
  end

  defp assert_fallback_only(reading, error) do
    assert reading.source == :blockstream
    assert reading.tip == @tip + 3
    assert Enum.sort(Map.keys(reading.blocks)) == [@tip + 3 - 2016, @tip + 3]

    for {height, block} <- reading.blocks do
      assert block == %{height: height, hash: hash(height), timestamp: timestamp(height)}
    end

    assert reading.attempts == [%{source: :mempool, host: "mempool.space", error: error}]
  end

  # User story:
  # As the operator whose halvings land as primary-quality facts,
  # I want a hostile tip body refused before any block is asked,
  # so that no shape of answer turns into a height the run trusts.
  #
  # Acceptance criteria:
  # - A tip that is quoted JSON, signed, padded with non-ASCII digits, a
  #   JSON object, a float or a bignum is `invalid_tip`; the fallback's
  #   reading is the whole answer.
  # - Surrounding whitespace is no attack: the trimmed tip is read.
  describe "a hostile tip body" do
    for {label, body} <- [
          {"a number as a JSON string", ~s("870000")},
          {"signed", "+870000"},
          {"fullwidth digits", "８７００００"},
          {"a JSON object", ~s({"height": 870000})},
          {"a float", "870000.0"},
          {"a hex number", "0xD4630"},
          {"two numbers", "870000 870001"},
          {"a number with a NUL", "870000\0"},
          {"overflowing", String.duplicate("9", 40)}
        ] do
      test "#{label} is invalid_tip" do
        primary_lies(%{"blocks/tip/height" => {200, unquote(body)}})

        assert {:ok, reading} = read()
        assert_fallback_only(reading, "invalid_tip")
      end
    end

    test "a tip with surrounding whitespace is read trimmed" do
      serve(%{"mempool.space" => {:chain, @tip, %{"blocks/tip/height" => {200, " #{@tip}\r\n"}}}})

      assert {:ok, %{source: :mempool, tip: @tip}} = read()
    end
  end

  # User story:
  # As the operator,
  # I want a hash answer that is anything but one 64-hex segment refused,
  # so that no answer can steer the next request's path.
  #
  # Acceptance criteria:
  # - A hash with a slash, a query, a dot segment, an encoded slash, inner
  #   whitespace, a JSON string or a 64-character non-hex body is
  #   `invalid_hash`, and no `/block/` request follows it.
  # - An uppercase hash is read lowercased and asked lowercased.
  describe "a hostile hash answer" do
    for {label, body} <- [
          {"with a query", String.duplicate("a", 60) <> "?x=1"},
          {"with an encoded slash", String.duplicate("a", 58) <> "%2F..%2F"},
          {"with a dot segment", "../" <> String.duplicate("a", 61)},
          {"with inner whitespace",
           String.duplicate("a", 32) <> " " <> String.duplicate("a", 31)},
          {"as a JSON string", ~s(") <> String.duplicate("a", 62) <> ~s(")},
          {"with a newline inside",
           String.duplicate("a", 32) <> "\n" <> String.duplicate("a", 32)},
          {"of 64 non-hex letters", String.duplicate("z", 64)}
        ] do
      test "a hash #{label} is invalid_hash and no block is asked" do
        primary_lies(%{"block-height/#{@tip}" => {200, unquote(body)}})

        assert {:ok, reading} = read()
        assert_fallback_only(reading, "invalid_hash")

        refute Enum.any?(requested(), fn {host, path} ->
                 host == "mempool.space" and String.starts_with?(path, "block/")
               end)
      end
    end

    test "an uppercase hash is asked lowercased and read lowercased" do
      serve(%{
        "mempool.space" =>
          {:chain, @tip, %{"block-height/#{@tip}" => {200, String.upcase(hash(@tip)) <> "\n"}}}
      })

      assert {:ok, %{source: :mempool} = reading} = read()
      assert reading.blocks[@tip].hash == hash(@tip)
      assert {"mempool.space", "block/#{hash(@tip)}"} in requested()
    end
  end

  # User story:
  # As the operator,
  # I want a block body that lies about itself, or is shaped to hurt the
  # decoder, refused without a crash,
  # so that a lying answer is a failure with a reason and the fallback reads.
  #
  # Acceptance criteria:
  # - A block that claims the hash of another height, a height that is a
  #   float, negative or a bignum, an id that is a number, or a body nested
  #   thirty thousand levels deep is refused (`invalid_block` or
  #   `block_mismatch`).
  # - A body with duplicate keys is read as one value, and that value is the
  #   one checked: what is handed on echoes what was asked.
  describe "a hostile block body" do
    for {label, change} <- [
          {"claims the hash of another height", %{"id" => :other_hash}},
          {"claims the next height", %{"height" => @tip + 1}},
          {"has a float height", %{"height" => @tip * 1.0}},
          {"has a negative height", %{"height" => -@tip}},
          {"has a bignum height", %{"height" => 10 ** 40 + @tip}},
          {"has a number as its id", %{"id" => 12_345}},
          {"has a null timestamp", %{"timestamp" => nil}},
          {"has a list as its timestamp", %{"timestamp" => [1]}}
        ] do
      test "a block that #{label} is refused" do
        change =
          Map.new(unquote(Macro.escape(change)), fn
            {"id", :other_hash} -> {"id", hash(@tip - 1)}
            pair -> pair
          end)

        body = Jason.encode!(Map.merge(block(@tip), change))
        primary_lies(%{"block/#{hash(@tip)}" => {200, body}})

        assert {:ok, reading} = read()
        assert [%{source: :mempool, error: error}] = reading.attempts
        assert error in ["invalid_block", "block_mismatch"]
        assert reading.source == :blockstream
      end
    end

    test "a body nested thirty thousand levels deep is refused without a crash" do
      nested = String.duplicate("[", 30_000) <> String.duplicate("]", 30_000)

      body =
        String.replace(Jason.encode!(block(@tip)), ~s("tx_count":1), ~s("tx_count":#{nested}))

      assert byte_size(body) < 64 * 1024

      primary_lies(%{"block/#{hash(@tip)}" => {200, body}})

      # Decoding it is no attack; the block it carries is the one asked.
      assert {:ok, reading} = read()
      assert reading.source in [:mempool, :blockstream]
      assert reading.blocks[reading.tip].hash == hash(reading.tip)
    end

    test "a body nested past the cap is refused as body_too_large" do
      body = String.duplicate("[", 40_000) <> String.duplicate("]", 40_000)
      primary_lies(%{"block/#{hash(@tip)}" => {200, body}})

      assert {:ok, reading} = read()
      assert_fallback_only(reading, "body_too_large")
    end

    test "a JSON number past a float's range is invalid_block" do
      body =
        block(@tip)
        |> Jason.encode!()
        |> String.replace(~s("timestamp":#{timestamp(@tip)}), ~s("timestamp":1e999))

      primary_lies(%{"block/#{hash(@tip)}" => {200, body}})

      assert {:ok, reading} = read()
      assert_fallback_only(reading, "invalid_block")
    end

    for {label, first, second} <- [
          {"the lie first", @tip - 1, @tip},
          {"the lie second", @tip, @tip - 1}
        ] do
      test "a body with duplicate height keys, #{label}, hands on only what it checked" do
        json = Jason.encode!(Map.delete(block(@tip), "height"))

        body =
          String.replace(
            json,
            "{",
            ~s({"height":#{unquote(first)},"height":#{unquote(second)},),
            global: false
          )

        primary_lies(%{"block/#{hash(@tip)}" => {200, body}})

        case read() do
          {:ok, %{source: :mempool} = reading} ->
            assert reading.blocks[@tip] == %{
                     height: @tip,
                     hash: hash(@tip),
                     timestamp: timestamp(@tip)
                   }

          {:ok, reading} ->
            assert_fallback_only(reading, "block_mismatch")
        end
      end
    end
  end

  # User story:
  # As the operator,
  # I want a block's timestamp outside what the chain allows refused,
  # so that no date from before Bitcoin or from tomorrow lands.
  #
  # Acceptance criteria:
  # - A timestamp of zero, a negative one, one a second before genesis, one
  #   a day ahead of the clock and a bignum are `timestamp_out_of_bounds`.
  # - The genesis block's own timestamp is the lower bound and passes.
  describe "a hostile timestamp" do
    for {label, timestamp} <- [
          {"zero", 0},
          {"negative", -1},
          {"a second before genesis", 1_231_006_504},
          {"a day ahead of the clock", DateTime.to_unix(@now) + 86_400},
          {"a bignum", 10 ** 30}
        ] do
      test "a timestamp that is #{label} is refused" do
        body = Jason.encode!(Map.put(block(@tip), "timestamp", unquote(timestamp)))
        primary_lies(%{"block/#{hash(@tip)}" => {200, body}})

        assert {:ok, reading} = read()
        assert_fallback_only(reading, "timestamp_out_of_bounds")
      end
    end

    test "the genesis block's own timestamp is the lower bound and passes" do
      body = Jason.encode!(Map.put(block(@tip), "timestamp", genesis_time()))
      serve(%{"mempool.space" => {:chain, @tip, %{"block/#{hash(@tip)}" => {200, body}}}})

      assert {:ok, %{source: :mempool} = reading} = read()
      assert reading.blocks[@tip].timestamp == genesis_time()
    end
  end

  # User story:
  # As the operator,
  # I want a source on any chain but Bitcoin's refused when the day's check
  # is due, and a tip that runs backwards refused against the last stored tip,
  # so that no other chain's heights and no lagging source land.
  #
  # Acceptance criteria:
  # - Regtest's and signet's genesis hashes, an uppercase wrong genesis and
  #   a non-hex genesis are refused (`wrong_chain` or `invalid_hash`).
  # - Bitcoin's genesis hash in uppercase passes.
  # - A tip far behind the last stored tip, and a tip of zero after one, are
  #   `tip_behind`, and nothing past the tip is asked.
  describe "another chain, and a tip that runs backwards" do
    for {label, body, code} <- [
          {"regtest", @regtest_genesis, "wrong_chain"},
          {"signet", @signet_genesis, "wrong_chain"},
          {"testnet in uppercase", String.upcase(testnet_genesis_hash()), "wrong_chain"},
          {"a genesis of zeros", String.duplicate("0", 64), "wrong_chain"},
          {"an empty genesis", "", "invalid_hash"}
        ] do
      test "a #{label} genesis is refused as #{code}" do
        primary_lies(%{"block-height/0" => {200, unquote(body)}})

        assert {:ok, reading} = read()
        assert_fallback_only(reading, unquote(code))
      end
    end

    test "Bitcoin's genesis hash in uppercase passes" do
      serve(%{
        "mempool.space" =>
          {:chain, @tip, %{"block-height/0" => {200, String.upcase(genesis_hash())}}}
      })

      assert {:ok, %{source: :mempool, genesis_checked: true}} = read()
    end

    for {label, tip} <- [{"far behind", @tip - 210_000}, {"zero", 0}] do
      test "a tip #{label} the last stored tip is tip_behind" do
        primary_lies(%{"blocks/tip/height" => {200, Integer.to_string(unquote(tip))}})

        assert {:ok, reading} = read(last_tip: @tip)
        assert_fallback_only(reading, "tip_behind")
        assert for({"mempool.space", path} <- requested(), do: path) == ["blocks/tip/height"]
      end
    end
  end

  # User story:
  # As the operator,
  # I want a run's reading to be one source's from tip to last block,
  # so that a liar that answers most things right cannot leave half an answer.
  #
  # Acceptance criteria:
  # - A primary that answers the tip, the genesis and the first block right
  #   and lies at the second block gives a reading that is the fallback's
  #   alone, at the fallback's tip.
  # - Two lying sources hand nothing on: each failure carries its source,
  #   host and code, and no part of any answer.
  describe "no mix of sources" do
    test "a primary that lies only at its last block leaves nothing of its own" do
      lying = Map.put(block(@tip - 2016), "height", @tip - 2015)
      primary_lies(%{"block/#{hash(@tip - 2016)}" => {200, Jason.encode!(lying)}})

      assert {:ok, reading} = read()
      assert_fallback_only(reading, "block_mismatch")

      assert {"mempool.space", "block/#{hash(@tip)}"} in requested()
    end

    test "two lying sources hand nothing on and keep no answer" do
      serve(%{
        "mempool.space" => {:chain, @tip, %{"block-height/0" => {200, @signet_genesis}}},
        "blockstream.info" =>
          {:chain, @tip, %{"blocks/tip/height" => {200, "<html>870000</html>"}}}
      })

      assert {:error, failures} = read()

      assert failures == [
               %{source: :mempool, host: "mempool.space", error: "wrong_chain"},
               %{source: :blockstream, host: "blockstream.info", error: "invalid_tip"}
             ]
    end
  end

  # User story:
  # As the operator,
  # I want a redirect never followed, whatever its status and target,
  # so that no answer can send the run to a host, a scheme or a file.
  #
  # Acceptance criteria:
  # - 301, 303, 307 and 308 to another host, and a 302 to `file:`, `data:`,
  #   a private address or a protocol-relative URL, are `redirect_refused`
  #   and their target is never asked.
  # - A redirect status without a Location, and a 300 or 304, are the
  #   statuses they are (`http_<status>`), not a hop.
  describe "a redirect" do
    for {status, location} <- [
          {301, "https://elsewhere.example.com/api/blocks/tip/height"},
          {303, "https://elsewhere.example.com/api/blocks/tip/height"},
          {307, "https://elsewhere.example.com/api/blocks/tip/height"},
          {308, "https://elsewhere.example.com/api/blocks/tip/height"},
          {302, "file:///etc/passwd"},
          {302, "data:text/plain,870000"},
          {302, "https://10.0.0.1/api/blocks/tip/height"},
          {302, "//elsewhere.example.com/api/blocks/tip/height"}
        ] do
      test "a #{status} to #{location} is never followed" do
        primary_lies(%{"blocks/tip/height" => {:redirect, unquote(status), unquote(location)}})

        assert {:ok, reading} = read()
        assert_fallback_only(reading, "redirect_refused")
        refute Enum.any?(requested(), &match?({"elsewhere.example.com", _}, &1))
      end
    end

    for status <- [300, 302, 304] do
      test "a #{status} without a Location is the status it is" do
        primary_lies(%{"blocks/tip/height" => {unquote(status), ""}})

        assert {:ok, reading} = read()
        assert_fallback_only(reading, "http_#{unquote(status)}")
      end
    end
  end

  # User story:
  # As the operator,
  # I want the caller's heights to reach a request only as integers within
  # the tip,
  # so that no caller can put a path, a negative height or one above the tip
  # into a request.
  #
  # Acceptance criteria:
  # - `heights_for` returning a path, a negative height, one above the tip,
  #   a float or no list raises before any `/block-height/` request.
  # - A height asked twice is read once.
  # - An option the adapter does not know (a URL, a host, a plug) raises.
  describe "the caller's heights and options" do
    for {label, heights} <- [
          {"a path", ["1/../../x"]},
          {"a negative height", [-1]},
          {"a height above the tip", [:above]},
          {"a float", [1.0]},
          {"no list", :not_a_list}
        ] do
      test "heights_for returning #{label} raises before any block is asked" do
        serve(%{"mempool.space" => {:chain, @tip}})

        heights_for = fn tip ->
          case unquote(Macro.escape(heights)) do
            [:above] -> [tip + 1]
            other -> other
          end
        end

        assert_raise ArgumentError, fn ->
          Esplora.read(heights_for, now: @now, genesis_due?: fn _ -> false end)
        end

        refute Enum.any?(requested(), fn {_host, path} ->
                 String.starts_with?(path, "block-height/")
               end)
      end
    end

    test "a height asked twice is read once" do
      serve(%{"mempool.space" => {:chain, @tip}})

      assert {:ok, _reading} =
               Esplora.read(fn tip -> [tip, tip, tip] end,
                 now: @now,
                 genesis_due?: fn _ -> false end
               )

      assert Enum.count(requested(), &(&1 == {"mempool.space", "block-height/#{@tip}"})) == 1
    end

    for option <- [:url, :base, :host, :plug, :allowed_hosts, :max_redirects] do
      test "the option #{option} raises" do
        assert_raise ArgumentError, fn ->
          Esplora.read(&period/1, [{unquote(option), "https://elsewhere.example.com"}])
        end
      end
    end
  end

  # User story:
  # As the operator,
  # I want a source that drips its answer slowly cut at the deadline,
  # so that a slow-loris host costs one request's ten seconds and the
  # fallback still reads.
  #
  # Acceptance criteria:
  # - A tip that answers after more than 10 seconds is `timeout`, and the
  #   fallback's reading is the whole answer.
  describe "a slow source" do
    @tag timeout: 30_000
    test "a tip slower than the deadline is a timeout and the fallback reads" do
      serve(%{
        "mempool.space" => fn conn ->
          Process.sleep(10_500)
          Plug.Conn.send_resp(conn, 200, Integer.to_string(@tip))
        end,
        "blockstream.info" => {:chain, @tip + 3}
      })

      assert {:ok, reading} = read()
      assert_fallback_only(reading, "timeout")
    end
  end
end
