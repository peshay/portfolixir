defmodule Portfolixir.ChainsTest do
  # ADR-0059 §8, §11 (Sprint 29, H6, FR-58): the chains read and the
  # on-demand refresh behind GET /api/v1/chains and
  # POST /api/v1/chains/:chain/refresh. Every answer is synthetic
  # (Portfolixir.EsploraFixtures: ten minutes a block from the real genesis
  # time); no test touches the network. The clock is injected (`now:`), so
  # the ten-minute throttle is read to the second.
  use Portfolixir.DataCase, async: true

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Chains
  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Chains.Reader

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000

  defp bound!(chain) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Chain Coin #{System.unique_integer([:positive])}",
        currency_code: "USD",
        asset_class: "crypto"
      })

    {:ok, bound} =
      Catalog.update_security(Actor.api_token_rw("synthetic-agent"), security, %{
        halving_chain: chain
      })

    bound
  end

  defp chain(list, name), do: Enum.find(list, &(&1.chain == name))

  # User story (ADR-0059 §8, §11):
  # As the operator's agent and the operator,
  # I want one read of the registered chains with their constants and, for a
  # chain with a source, its health and the inputs of the next halving's
  # estimate,
  # so that a quiet chain and a dead source look different.
  #
  # Acceptance criteria:
  # - The three registered chains in the registry's order, each with
  #   halving_interval, target_spacing_seconds, has_source and the number of
  #   securities bound to it.
  # - A chain without a source has no health, no inputs and no refresh.
  # - Before its first run, Bitcoin's health is all null and not stale, and
  #   its refresh is available now.
  # - After a run: the host, last_tried_at, last_ok_at, last_error, stale
  #   (24 hours without a successful run), the tip, its time, the time 2,016
  #   blocks below and their mean in seconds as a Decimal at scale 2, and the
  #   next refresh ten minutes after the last try.
  test "lists the registered chains with their constants and Bitcoin's health" do
    bound!(:bitcoin)
    bound!(:litecoin)

    before = Chains.list(@now)
    assert Enum.map(before, & &1.chain) == ["bitcoin", "bitcoin_cash", "litecoin"]

    litecoin = chain(before, "litecoin")

    assert Map.take(litecoin, [
             :halving_interval,
             :target_spacing_seconds,
             :has_source,
             :bound_securities,
             :health,
             :next_halving_inputs,
             :refresh
           ]) == %{
             halving_interval: 840_000,
             target_spacing_seconds: 150,
             has_source: false,
             bound_securities: 1,
             health: nil,
             next_halving_inputs: nil,
             refresh: nil
           }

    bitcoin = chain(before, "bitcoin")
    assert {bitcoin.has_source, bitcoin.bound_securities} == {true, 1}

    assert bitcoin.health == %{
             source_host: nil,
             last_tried_at: nil,
             last_ok_at: nil,
             last_error: nil,
             stale: false
           }

    assert bitcoin.next_halving_inputs == nil
    assert bitcoin.refresh == %{interval_seconds: 600, available_at: nil}

    serve(%{"mempool.space" => {:chain, @tip}})
    assert {:ok, _summary} = Reader.run(:bitcoin, now: @now)

    later = DateTime.add(@now, 25 * 3600)
    bitcoin = chain(Chains.list(later), "bitcoin")

    assert bitcoin.health == %{
             source_host: "mempool.space",
             last_tried_at: @now,
             last_ok_at: @now,
             last_error: nil,
             stale: true
           }

    assert bitcoin.next_halving_inputs == %{
             tip_height: @tip,
             tip_at: DateTime.from_unix!(timestamp(@tip)),
             tip_2016_at: DateTime.from_unix!(timestamp(@tip - 2016)),
             period_blocks: 2016,
             mean_block_seconds: Decimal.new("600.00")
           }

    assert bitcoin.refresh == %{interval_seconds: 600, available_at: DateTime.add(@now, 600)}
  end

  # User story (ADR-0059 §11):
  # As the operator pressing „Jetzt lesen“, or the agent asking for a fresh
  # read,
  # I want an on-demand run that answers with the health, at most once per
  # ten minutes per chain,
  # so that nobody can make the app hammer a public host.
  #
  # Acceptance criteria:
  # - A refresh runs the chain reader at once and answers the chain's entry
  #   with the run: status ok, the host, the tip and the securities written.
  # - A second refresh 4 minutes 20 seconds later is refused with
  #   {:too_soon, 340}, the seconds until ten minutes after the last try,
  #   and asks no host; at ten minutes it runs again.
  # - A scheduled run counts: a refresh within ten minutes of it is refused.
  # - A run that fails is a run: it answers status failed with the stored
  #   error, and it starts the ten minutes too.
  # - With no security bound the run asks no host (status unbound) and
  #   stores nothing, so it starts no wait.
  # - A chain without a source answers :no_source, an unregistered name
  #   :not_found, and neither asks a host.
  test "an on-demand run, once per ten minutes per chain" do
    assert {:ok, %{run: %{status: :unbound}} = unbound} = Chains.refresh("bitcoin", now: @now)
    assert unbound.health.last_tried_at == nil
    assert Reader.state(:bitcoin) == nil

    bound!(:bitcoin)
    serve(%{"mempool.space" => {:chain, @tip}})

    assert {:ok, entry} = Chains.refresh("bitcoin", now: @now)
    assert entry.chain == "bitcoin"
    assert entry.run == %{status: :ok, host: "mempool.space", tip: @tip, securities: 1}
    assert entry.health.last_ok_at == @now
    assert_received {:esplora, "mempool.space", _path}
    flush()

    soon = DateTime.add(@now, 260)
    assert Chains.refresh("bitcoin", now: soon) == {:error, {:too_soon, 340}}
    refute_received {:esplora, _host, _path}

    assert Chains.refresh(:bitcoin, now: DateTime.add(@now, 599)) == {:error, {:too_soon, 1}}

    ten = DateTime.add(@now, 600)
    assert {:ok, %{run: %{status: :ok}}} = Chains.refresh("bitcoin", now: ten)

    serve(%{"mempool.space" => {:status, 503}, "blockstream.info" => {:status, 503}})
    failed_at = DateTime.add(ten, 600)

    assert {:ok, %{run: %{status: :failed, error: error}} = failed} =
             ExUnit.CaptureLog.with_log(fn -> Chains.refresh("bitcoin", now: failed_at) end)
             |> elem(0)

    assert error =~ "mempool.space"
    assert failed.health.last_error == error
    assert failed.health.last_ok_at == ten

    assert Chains.refresh("bitcoin", now: DateTime.add(failed_at, 60)) ==
             {:error, {:too_soon, 540}}

    assert Chains.refresh("litecoin", now: @now) == {:error, :no_source}
    assert Chains.refresh("bitcoin_cash", now: @now) == {:error, :no_source}
    assert Chains.refresh("dogecoin", now: @now) == {:error, :not_found}
    assert Chains.refresh(nil, now: @now) == {:error, :not_found}
  end

  test "a scheduled run starts the ten minutes too" do
    bound!(:bitcoin)
    serve(%{"mempool.space" => {:chain, @tip}})
    assert {:ok, _summary} = Reader.run(:bitcoin, now: @now)

    assert Chains.refresh("bitcoin", now: DateTime.add(@now, 30)) == {:error, {:too_soon, 570}}
  end

  # The closing act's security lens on Lane H (finding 3): a last try
  # stamped after the clock (a clock set back, a restored backup) answered
  # {:too_soon, 600} at every later moment until the clock caught up, a
  # year if the stamp was a year ahead. A stamp after `now` is due; the run
  # stamps `now`, and the ten minutes count from there.
  test "a last try stamped after now is due, and the ten minutes count from the run" do
    bound!(:bitcoin)
    serve(%{"mempool.space" => {:chain, @tip}})

    Repo.insert!(%ChainRead{
      chain: "bitcoin",
      last_tried_at: DateTime.add(@now, 365 * 24 * 3600),
      inserted_at: @now,
      updated_at: @now
    })

    assert Chains.refresh_wait("bitcoin", @now) == 0
    assert {:ok, %{run: %{status: :ok}} = entry} = Chains.refresh("bitcoin", now: @now)
    assert entry.health.last_tried_at == @now
    assert Chains.refresh("bitcoin", now: DateTime.add(@now, 60)) == {:error, {:too_soon, 540}}
  end

  # The closing act's security and order lenses on Lane H: the throttle was
  # checked outside any lock, so refreshes sent together each passed it
  # and each asked the source. The try is now claimed in one conditional
  # write before the network read; the others answer too_soon.
  test "refreshes sent together: one claims the try and asks the source, the others wait" do
    bound!(:bitcoin)
    test_pid = self()

    read = fn heights_for, opts ->
      send(test_pid, :read)
      Process.sleep(50)
      serve_canned(heights_for, opts)
    end

    results =
      1..8
      |> Enum.map(fn _ ->
        Task.async(fn -> Chains.refresh("bitcoin", now: @now, read: read) end)
      end)
      |> Enum.map(&Task.await(&1, 20_000))

    assert Enum.count(results, &match?({:ok, %{run: %{status: :ok}}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, {:too_soon, 600}})) == 7
    assert_received :read
    refute_received :read
  end

  defp serve_canned(heights_for, _opts) do
    heights = heights_for.(@tip)

    {:ok,
     %{
       source: :mempool,
       host: "mempool.space",
       base: "https://mempool.space/api",
       tip: @tip,
       blocks: Map.new(heights, &{&1, %{height: &1, hash: hash(&1), timestamp: timestamp(&1)}}),
       genesis_checked: true,
       attempts: []
     }}
  end

  defp flush do
    receive do
      {:esplora, _host, _path} -> flush()
    after
      0 -> :ok
    end
  end
end
