defmodule Portfolixir.EsploraFixtures do
  @moduledoc """
  A synthetic Bitcoin chain answered as an Esplora host would answer it, for
  the chain source's tests (ADR-0059 §10: the suite registers a fake source
  and never touches the network). Heights and timestamps are synthetic; the
  genesis hash is the real, public one, and the testnet genesis hash is
  there for the wrong-chain case.

  `serve/1` answers the adapter's requests for this test with a plug built
  from one spec per host and sends `{:esplora, host, path}` to the test for
  every request, so a test can see which hosts were asked and which were
  not. A host without a spec answers as a refused connection.
  """

  @genesis "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
  @testnet_genesis "000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943"
  @genesis_time 1_231_006_505

  @doc "Bitcoin's genesis block hash (height 0)."
  def genesis_hash, do: @genesis

  @doc "Testnet3's genesis block hash: an answer from the wrong chain."
  def testnet_genesis_hash, do: @testnet_genesis

  @doc "The genesis block's timestamp, 2009-01-03 18:15:05 UTC."
  def genesis_time, do: @genesis_time

  @doc "The synthetic block hash at `height`; the real one at height 0."
  def hash(0), do: @genesis

  def hash(height) when is_integer(height),
    do: :sha256 |> :crypto.hash("synthetic-block-#{height}") |> Base.encode16(case: :lower)

  @doc "The synthetic timestamp of the block at `height`: ten minutes a block."
  def timestamp(height) when is_integer(height), do: @genesis_time + height * 600

  @doc """
  Answers the adapter's requests for this test. `specs` maps a host to:

    * `{:chain, tip}` or `{:chain, tip, overrides}`: a valid chain with that
      tip; `overrides` maps a path suffix (`"blocks/tip/height"`,
      `"block-height/840000"`, `"block/<hash>"`) to `{status, body}`,
      `{:redirect, status, location}` or `:timeout`;
    * `{:status, status}`: every request answers that status;
    * a function of the conn.
  """
  def serve(specs) when is_map(specs) do
    test_pid = self()

    Req.Test.stub(Portfolixir.Chains.Esplora, fn conn ->
      send(test_pid, {:esplora, conn.host, conn.request_path})

      case Map.fetch(specs, conn.host) do
        {:ok, spec} -> answer(conn, spec)
        :error -> Req.Test.transport_error(conn, :econnrefused)
      end
    end)
  end

  defp answer(conn, fun) when is_function(fun, 1), do: fun.(conn)
  defp answer(conn, {:status, status}), do: Plug.Conn.send_resp(conn, status, "")
  defp answer(conn, {:chain, tip}), do: answer(conn, {:chain, tip, %{}})

  defp answer(conn, {:chain, tip, overrides}) do
    suffix = suffix(conn.request_path)

    case Map.fetch(overrides, suffix) do
      {:ok, override} -> override(conn, override)
      :error -> chain_answer(conn, tip, suffix)
    end
  end

  defp override(conn, :timeout), do: Req.Test.transport_error(conn, :timeout)

  defp override(conn, {:redirect, status, location}) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(status, "")
  end

  defp override(conn, {status, body}), do: Plug.Conn.send_resp(conn, status, body)

  defp chain_answer(conn, tip, "blocks/tip/height"),
    do: Plug.Conn.send_resp(conn, 200, Integer.to_string(tip))

  defp chain_answer(conn, tip, "block-height/" <> height) do
    case Integer.parse(height) do
      {h, ""} when h >= 0 and h <= tip -> Plug.Conn.send_resp(conn, 200, hash(h))
      _ -> Plug.Conn.send_resp(conn, 404, "Block not found")
    end
  end

  defp chain_answer(conn, tip, "block/" <> hash) do
    case Enum.find(heights_for(tip), &(hash(&1) == hash)) do
      nil -> Plug.Conn.send_resp(conn, 404, "Block not found")
      height -> json(conn, block(height))
    end
  end

  defp chain_answer(conn, _tip, _suffix), do: Plug.Conn.send_resp(conn, 404, "Not found")

  @doc "The JSON an Esplora host answers for the block at `height` (the fields read, and more)."
  def block(height) do
    %{
      "id" => hash(height),
      "height" => height,
      "version" => 536_870_912,
      "timestamp" => timestamp(height),
      "tx_count" => 1,
      "size" => 285,
      "weight" => 1140,
      "merkle_root" => String.duplicate("ab", 32),
      "previousblockhash" => if(height > 0, do: hash(height - 1)),
      "mediantime" => timestamp(height) - 3_000,
      "nonce" => 1,
      "bits" => 386_089_497,
      "difficulty" => 1
    }
  end

  @doc "Sends `body` as JSON."
  def json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  # The heights a synthetic chain's block lookup searches: the tip, the
  # difficulty period before it, the halvings and the genesis block.
  defp heights_for(tip) do
    halvings = for k <- 1..div(tip, 210_000)//1, do: k * 210_000
    Enum.uniq([0, tip, tip - 2016] ++ halvings ++ Enum.to_list(max(tip - 20, 0)..tip))
  end

  @doc "The path after the base: `blocks/tip/height`, `block-height/<h>` or `block/<hash>`."
  def suffix(path) do
    case String.split(path, "/", trim: true) |> Enum.reverse() do
      ["height", "tip", "blocks" | _] -> "blocks/tip/height"
      [height, "block-height" | _] -> "block-height/" <> height
      [hash, "block" | _] -> "block/" <> hash
      _ -> path
    end
  end
end

defmodule Portfolixir.Chains.NoNetwork do
  @moduledoc """
  The chain source's adapter in the test configuration, the one plug the
  adapter merges: a test answers with `Portfolixir.EsploraFixtures.serve/1`,
  a `Req.Test` stub owned by the test and seen by the tasks it starts; every
  request no test stubbed answers as a refused connection, through Req's
  plug path, so no read in the suite opens a socket (ADR-0059 §10).
  """
  @behaviour Plug

  @stub Portfolixir.Chains.Esplora

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case stub() do
      nil -> Req.Test.transport_error(conn, :econnrefused)
      fun when is_function(fun, 1) -> fun.(conn)
      fun when is_function(fun, 2) -> fun.(conn, [])
      module when is_atom(module) -> module.call(conn, module.init([]))
      {module, opts} -> module.call(conn, module.init(opts))
    end
  end

  defp stub do
    Req.Test.__fetch_plug__(@stub)
  rescue
    RuntimeError -> nil
  end
end
