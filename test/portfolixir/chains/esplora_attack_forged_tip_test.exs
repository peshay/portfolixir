defmodule Portfolixir.Chains.EsploraAttackForgedTipTest do
  # Sprint 29, the closing act's security lens on Lane H (finding 1, S1): a
  # lying Esplora source answers a tip far AHEAD of the stored one, below
  # the genesis ceiling of ADR-0059 §7, with blocks that echo their heights
  # and timestamps inside the bounds. Before the fix the forged tip was
  # stored: every honest source then read as `tip_behind` for about two
  # years, and from late February 2027 a forged tip confirmed the fifth
  # halving. The tip is now bounded from above by the stored one as well
  # (ADR-0059 §7, precision of 2026-11-13). Every answer is synthetic; no
  # test opens a socket.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog
  import Portfolixir.EsploraFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Chains
  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Chains.Esplora
  alias Portfolixir.Knowledge.SecurityEvent

  @genesis_time 1_231_006_505
  @honest 925_000

  defp bound! do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Coin #{System.unique_integer([:positive])}",
        currency_code: "USD",
        asset_class: "crypto"
      })

    {:ok, bound} =
      Catalog.update_security(Actor.api_token_rw("synthetic-agent"), security, %{
        halving_chain: :bitcoin
      })

    bound
  end

  # The genesis ceiling of ADR-0059 §7 at `now`.
  defp genesis_ceiling(now),
    do: div((DateTime.to_unix(now) - @genesis_time) * 11, 600 * 10)

  # A forged chain: tip `tip`, every block echoes its height and hash, the
  # tip's time is `now - 60`, tip - 2016 two weeks earlier, everything in
  # bounds and in order; the real genesis hash at 0, synthetic halvings.
  defp forged(tip, now) do
    t_tip = DateTime.to_unix(now) - 60

    fn conn ->
      case suffix(conn.request_path) do
        "blocks/tip/height" ->
          Plug.Conn.send_resp(conn, 200, Integer.to_string(tip))

        "block-height/" <> height ->
          Plug.Conn.send_resp(conn, 200, hash(String.to_integer(height)))

        "block/" <> asked ->
          height =
            Enum.find(
              [tip, tip - 2016, 210_000, 420_000, 630_000, 840_000, 1_050_000],
              &(hash(&1) == asked)
            )

          ts =
            cond do
              height == tip -> t_tip
              height == tip - 2016 -> t_tip - 2016 * 600
              height == 1_050_000 -> t_tip - 600 * (tip - 1_050_000)
              true -> timestamp(height)
            end

          json(conn, %{block(height) | "timestamp" => ts})
      end
    end
  end

  defp halving(security, height) do
    Repo.one!(
      from(e in SecurityEvent,
        where: e.security_id == ^security.id and e.chain_height == ^height
      )
    )
  end

  # User story (ADR-0059 §7):
  # As the operator whose halvings land as primary-quality facts,
  # I want a tip far ahead of the stored one refused, even below the
  # genesis ceiling,
  # so that one lying answer neither locks the honest sources out nor
  # confirms a halving that has not happened.
  #
  # Acceptance criteria:
  # - After an honest run at 925,000, a fallback that answers a tip just
  #   below the genesis ceiling ten minutes later fails with `tip_ahead`;
  #   the stored tip and the next halving's estimate stay as they were.
  # - The honest sources, back at the real tip, are read again: no
  #   `tip_behind`.
  # - In March 2027, a forged tip of 1,050,010 (below the genesis ceiling
  #   by then) is refused, and the fifth halving stays an unconfirmed
  #   estimate.
  test "a forged tip ahead of the stored one is refused and locks nobody out" do
    security = bound!()
    now = ~U[2026-11-13 12:00:00Z]

    serve(%{"mempool.space" => {:chain, @honest}})
    assert {:ok, %{run: %{status: :ok, tip: @honest}}} = Chains.refresh("bitcoin", now: now)
    estimate = halving(security, 1_050_000)

    forged_tip = genesis_ceiling(now) - 10
    later = DateTime.add(now, 600)

    serve(%{
      "mempool.space" => {:status, 503},
      "blockstream.info" => forged(forged_tip, later)
    })

    {result, _log} = with_log(fn -> Chains.refresh("bitcoin", now: later) end)
    assert {:ok, %{run: %{status: :failed, error: error}}} = result
    assert error == "mempool.space: http_503; blockstream.info: tip_ahead"

    assert Repo.get_by!(ChainRead, chain: "bitcoin").tip_height == @honest
    assert halving(security, 1_050_000) == estimate

    at = DateTime.add(later, 6 * 3600)
    serve(%{"mempool.space" => {:chain, @honest + 1}})
    assert {:ok, %{run: %{status: :ok, tip: tip}}} = Chains.refresh("bitcoin", now: at)
    assert tip == @honest + 1
  end

  test "a forged tip in March 2027 does not confirm the fifth halving" do
    security = bound!()
    serve(%{"mempool.space" => {:chain, @honest}})
    assert {:ok, _entry} = Chains.refresh("bitcoin", now: ~U[2026-11-13 12:00:00Z])

    at = ~U[2027-03-15 12:00:00Z]
    forged_tip = 1_050_010
    assert forged_tip <= genesis_ceiling(at)
    serve(%{"mempool.space" => forged(forged_tip, at), "blockstream.info" => {:status, 503}})

    {result, _log} = with_log(fn -> Chains.refresh("bitcoin", now: at) end)
    assert {:ok, %{run: %{status: :failed, error: error}}} = result
    assert error == "mempool.space: tip_ahead; blockstream.info: http_503"

    fifth = halving(security, 1_050_000)
    assert fifth.confirmed == false
    assert fifth.timing == :window
    assert fifth.source_quality == :unverified
  end

  # User story (ADR-0059 §7):
  # As the adapter's caller,
  # I want the tip bounded by the stored tip, its block's time and the
  # clock, with the genesis ceiling kept for a first run,
  # so that the bound holds from the first answer on.
  #
  # Acceptance criteria:
  # - With the last tip and its block's time: at most the last tip + the
  #   elapsed seconds / 600 × 1.1 (rounded down) + 36; one more is
  #   `tip_ahead`.
  # - A stored tip's time after the clock counts no elapsed time: the
  #   bound is the last tip + 36.
  # - Without a last tip the genesis ceiling alone bounds the tip.
  # - A last tip's time that is not a `DateTime` raises.
  describe "the bound from the stored tip" do
    @now ~U[2026-11-12 12:00:00Z]
    @tip 870_000

    defp read_at(tip, opts) do
      serve(%{"mempool.space" => {:chain, tip}})
      Esplora.read(fn t -> [t, t - 2016] end, Keyword.put(opts, :now, @now))
    end

    test "the last tip + elapsed / 600 × 1.1 + 36 passes, one more is refused" do
      last_at = DateTime.add(@now, -3600)
      bound = @tip + 6 + 36

      assert {:ok, %{tip: ^bound}} = read_at(bound, last_tip: @tip, last_tip_at: last_at)

      assert {:error, [%{source: :mempool, error: "tip_ahead"} | _]} =
               read_at(bound + 1, last_tip: @tip, last_tip_at: last_at)
    end

    test "a stored tip's time after the clock counts no elapsed time" do
      last_at = DateTime.add(@now, 7200)

      assert {:ok, %{tip: tip}} = read_at(@tip + 36, last_tip: @tip, last_tip_at: last_at)
      assert tip == @tip + 36

      assert {:error, [%{error: "tip_ahead"} | _]} =
               read_at(@tip + 37, last_tip: @tip, last_tip_at: last_at)
    end

    test "without a last tip the genesis ceiling alone bounds the tip" do
      ceiling = genesis_ceiling(@now)
      serve(%{"mempool.space" => forged(ceiling, @now)})

      assert {:ok, %{tip: ^ceiling}} =
               Esplora.read(fn t -> [t, t - 2016] end, now: @now)

      serve(%{"mempool.space" => forged(ceiling + 1, @now)})

      assert {:error, [%{error: "tip_ahead"} | _]} =
               Esplora.read(fn t -> [t, t - 2016] end, now: @now)
    end

    test "a last tip's time of another type raises" do
      assert_raise ArgumentError, fn ->
        Esplora.read(fn t -> [t] end, last_tip: @tip, last_tip_at: "2026-11-12", now: @now)
      end
    end
  end
end
