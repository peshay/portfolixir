defmodule Portfolixir.Chains.ReaderTest do
  # ADR-0059 §5, §6, §7, §8, §9, §10 (Sprint 29, H3, FR-58): the run that
  # stores what the Esplora adapter read. Every answer is synthetic
  # (Portfolixir.EsploraFixtures: ten minutes a block from the real genesis
  # time); no test touches the network. The run's lock is scoped to the
  # test's connection (DataCase), so the module runs async.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog
  import Portfolixir.EsploraFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Chains.Reader
  alias Portfolixir.Journal.Entry, as: JournalEntry
  alias Portfolixir.Knowledge.SecurityEvent

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000
  @past [210_000, 420_000, 630_000, 840_000]

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp security!(chain \\ :bitcoin) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Coin #{System.unique_integer([:positive])}",
        currency_code: "USD",
        asset_class: "crypto"
      })

    if chain do
      {:ok, bound} = Catalog.update_security(agent(), security, %{halving_chain: chain})
      bound
    else
      security
    end
  end

  defp run(opts \\ []), do: Reader.run(:bitcoin, Keyword.put_new(opts, :now, @now))

  defp halvings(security) do
    Repo.all(
      from(e in SecurityEvent,
        where: e.security_id == ^security.id and e.kind == :halving,
        order_by: e.chain_height
      )
    )
  end

  defp halving(security, height),
    do: Repo.get_by(SecurityEvent, security_id: security.id, chain_height: height)

  defp journal_mark, do: Repo.one(from(e in JournalEntry, select: max(e.id))) || 0

  defp entries_since(mark),
    do: Repo.all(from(e in JournalEntry, where: e.id > ^mark, order_by: e.id))

  defp requested do
    receive do
      {:esplora, host, path} -> [{host, suffix(path)} | requested()]
    after
      0 -> []
    end
  end

  defp date_of(unix), do: unix |> DateTime.from_unix!() |> DateTime.to_date()

  # A block answer of the synthetic chain with another timestamp.
  defp retimed(height, unix),
    do: {"block/#{hash(height)}", {200, Jason.encode!(%{block(height) | "timestamp" => unix})}}

  # User story:
  # As the operator who bound a security to Bitcoin,
  # I want the run to store each past halving as the chain states it,
  # so that Bitcoin's chart aligns on facts read from the chain itself and
  # nobody types a halving date.
  #
  # Acceptance criteria (ADR-0059 §5):
  # - Each halving k × 210,000 at or below tip − 5 lands as a `halving` event
  #   with `timing: exact`, `confirmed: true`, `source_quality: primary`,
  #   `machine_generated: false`, the UTC date of the block's timestamp, the
  #   source's `{base}/block/{hash}` and `checked_at` the day it was read.
  # - Each write is journaled under the system job `chain_read`.
  describe "past halvings" do
    test "land confirmed, primary, dated by the block's UTC timestamp" do
      security = security!()
      serve(%{"mempool.space" => {:chain, @tip}})
      mark = journal_mark()

      assert {:ok, %{host: "mempool.space", tip: @tip}} = run()

      past = Enum.filter(halvings(security), & &1.confirmed)
      assert Enum.map(past, & &1.chain_height) == @past

      for event <- past do
        assert event.timing == :exact
        assert event.source_quality == :primary
        assert event.machine_generated == false
        assert event.date == date_of(timestamp(event.chain_height))
        assert event.date_end == nil
        assert event.checked_at == ~D[2026-11-12]

        assert event.source_url ==
                 "https://mempool.space/api/block/" <> hash(event.chain_height)
      end

      assert halving(security, 210_000).date == ~D[2013-01-01]

      written = entries_since(mark)
      assert length(written) == 5
      assert Enum.all?(written, &(&1.actor_type == :system_job))
      assert Enum.all?(written, &(&1.actor_label == "chain_read"))
      assert Enum.all?(written, &(&1.resource_type == "security_event"))
    end

    test "the date is the UTC date, as the block of 2024 was mined at 00:09 UTC" do
      security = security!()

      serve(%{
        "mempool.space" => {:chain, @tip, Map.new([retimed(840_000, 1_713_571_767)])}
      })

      assert {:ok, _summary} = run()
      assert halving(security, 840_000).date == ~D[2024-04-20]
    end

    test "a confirmed halving is never read again" do
      security = security!()
      serve(%{"mempool.space" => {:chain, @tip}})
      assert {:ok, _summary} = run()
      _ = requested()
      stored = Map.new(halvings(security), &{&1.chain_height, &1})

      assert {:ok, _summary} = run(now: ~U[2026-11-13 12:00:00Z])

      asked = for {"mempool.space", path} <- requested(), do: path
      refute Enum.any?(@past, &("block-height/#{&1}" in asked))

      for height <- @past do
        assert halving(security, height) == stored[height]
      end
    end

    test "a halving with fewer than six confirmations stays unconfirmed, then is confirmed" do
      now = ~U[2029-01-01 12:00:00Z]
      security = security!()

      serve(%{"mempool.space" => {:chain, 1_050_004}})
      assert {:ok, _summary} = run(now: now)

      pending = halving(security, 1_050_000)
      assert pending.confirmed == false
      assert pending.timing == :exact
      assert pending.source_quality == :unverified
      assert pending.date == date_of(timestamp(1_050_000))
      assert halving(security, 1_260_000).timing == :window

      serve(%{"mempool.space" => {:chain, 1_050_005}})
      assert {:ok, _summary} = run(now: DateTime.add(now, 3600))

      confirmed = halving(security, 1_050_000)
      assert confirmed.id == pending.id
      assert confirmed.confirmed == true
      assert confirmed.source_quality == :primary
    end

    test "the next halving's estimate becomes the block's date when the tip reaches it" do
      now = ~U[2029-01-01 12:00:00Z]
      security = security!()

      serve(%{"mempool.space" => {:chain, 1_049_990}})
      assert {:ok, _summary} = run(now: now)
      estimate = halving(security, 1_050_000)
      assert estimate.timing == :window

      serve(%{"mempool.space" => {:chain, 1_050_010}})
      assert {:ok, _summary} = run(now: DateTime.add(now, 3600))

      fact = halving(security, 1_050_000)
      assert fact.id == estimate.id
      assert fact.timing == :exact
      assert fact.date_end == nil
      assert fact.confirmed == true

      assert [%SecurityEvent{chain_height: 1_260_000}] =
               Enum.reject(halvings(security), & &1.confirmed)
    end
  end

  # User story:
  # As the operator reading the next halving on the chart,
  # I want it stored as a window between the recent block time and the
  # protocol's target, refreshed at most once a day,
  # so that the estimate states how well it is known and stays current
  # within a day.
  #
  # Acceptance criteria (ADR-0059 §6):
  # - One unconfirmed event for the first k × 210,000 above the tip, `timing:
  #   window`, `source_quality: unverified`: one end at the tip's timestamp +
  #   the remaining blocks × the mean block time of the last 2,016 blocks,
  #   the other at the ten-minute target; `date` the earlier, `date_end` the
  #   later of the two UTC dates.
  # - Its note names the tip, both timestamps, the mean and both ends.
  # - A second run the same day writes nothing; the next day's run writes it.
  describe "the next halving" do
    test "is a window from the recent mean block time to the target" do
      security = security!()
      tip_at = timestamp(@tip)

      serve(%{
        "mempool.space" => {:chain, @tip, Map.new([retimed(@tip - 2016, tip_at - 2016 * 540)])}
      })

      assert {:ok, _summary} = run()

      estimate = halving(security, 1_050_000)
      assert estimate.timing == :window
      assert estimate.confirmed == false
      assert estimate.source_quality == :unverified
      assert estimate.machine_generated == false
      assert estimate.date == ~D[2028-08-18]
      assert estimate.date_end == ~D[2028-12-21]
      assert estimate.checked_at == ~D[2026-11-12]
      assert estimate.source_url == "https://mempool.space/api/block/" <> hash(@tip)

      assert estimate.note =~ "870000"
      assert estimate.note =~ "540"
      assert estimate.note =~ "2028-08-18"
      assert estimate.note =~ "2028-12-21"
      refute estimate.note =~ "\n"
    end

    test "blocks slower than the target put the target first" do
      security = security!()
      tip_at = timestamp(@tip)

      serve(%{
        "mempool.space" => {:chain, @tip, Map.new([retimed(@tip - 2016, tip_at - 2016 * 660)])}
      })

      assert {:ok, _summary} = run()

      estimate = halving(security, 1_050_000)
      assert estimate.date == ~D[2028-12-21]
      assert estimate.date_end == ~D[2029-04-25]
    end

    test "is written at most once a day" do
      security = security!()
      serve(%{"mempool.space" => {:chain, @tip}})
      assert {:ok, _summary} = run()
      first = halving(security, 1_050_000)

      tip_at = timestamp(@tip + 100)

      serve(%{
        "mempool.space" =>
          {:chain, @tip + 100, Map.new([retimed(@tip + 100 - 2016, tip_at - 2016 * 540)])}
      })

      mark = journal_mark()
      assert {:ok, _summary} = run(now: ~U[2026-11-12 18:00:00Z])
      assert halving(security, 1_050_000) == first
      assert entries_since(mark) == []

      assert {:ok, _summary} = run(now: ~U[2026-11-13 12:00:00Z])
      next = halving(security, 1_050_000)
      assert next.checked_at == ~D[2026-11-13]
      assert next.date == ~D[2028-08-18]
      assert next.date_end == ~D[2028-12-21]
      assert [%JournalEntry{operation: :update}] = entries_since(mark)
    end
  end

  # User story:
  # As the operator with several securities, some bound and some not,
  # I want every security bound to Bitcoin to get its own halvings and no
  # other security any,
  # so that a binding is the only opt-in and each security carries the
  # facts about itself.
  #
  # Acceptance criteria (ADR-0059 §4, §10):
  # - Each security bound to Bitcoin gets the halvings and the estimate.
  # - An unbound security and one bound to a chain without a source get none.
  # - With no security bound to Bitcoin the run makes no request and stores
  #   no state.
  # - A security bound later gets its past halvings on the next run; the
  #   rows of the first are not written again.
  describe "the bound securities" do
    test "each security bound to Bitcoin gets its halvings, no other does" do
      first = security!()
      second = security!()
      unbound = security!(nil)
      litecoin = security!(:litecoin)
      serve(%{"mempool.space" => {:chain, @tip}})

      assert {:ok, _summary} = run()

      assert length(halvings(first)) == 5
      assert length(halvings(second)) == 5
      assert halvings(unbound) == []
      assert halvings(litecoin) == []
    end

    test "with no security bound to Bitcoin the run asks no host" do
      security!(nil)
      security!(:litecoin)
      serve(%{"mempool.space" => {:chain, @tip}})

      assert {:ok, :unbound} = run()
      assert requested() == []
      assert Repo.get_by(ChainRead, chain: "bitcoin") == nil
    end

    test "a security bound later gets its past halvings; the first's rows stay" do
      first = security!()
      serve(%{"mempool.space" => {:chain, @tip}})
      assert {:ok, _summary} = run()
      stored = halvings(first)

      second = security!()
      _ = requested()
      mark = journal_mark()
      assert {:ok, _summary} = run(now: ~U[2026-11-12 18:00:00Z])

      assert "block-height/210000" in for({"mempool.space", path} <- requested(), do: path)
      assert length(halvings(second)) == 5
      assert halvings(first) == stored

      written = entries_since(mark)
      assert length(written) == 5
      assert Enum.all?(written, &(&1.after["security_id"] == second.id))
    end

    test "a chain without a source is refused" do
      assert {:error, :no_source} = Reader.run(:litecoin, now: @now)
    end
  end

  # User story:
  # As the operator whose chain source fails,
  # I want a failed run to change nothing stored but its health,
  # so that the last estimate stands with its date and a dead source shows.
  #
  # Acceptance criteria (ADR-0059 §7, §8, §9):
  # - Both sources failing: no event written, the state row's `last_error`
  #   names each source's failure, `last_tried_at` moves, `last_ok_at` stays.
  # - A successful run records the host, the tip, the timestamps of the tip
  #   and of tip − 2,016, `last_ok_at`, and clears `last_error`.
  # - The stored tip is handed to the adapter, so a source more than 6
  #   behind it is refused and the fallback answers.
  # - The genesis check runs once a day per source.
  describe "the state row" do
    test "both sources failing change nothing but the state's error" do
      security = security!()
      serve(%{"mempool.space" => {:chain, @tip}})
      assert {:ok, _summary} = run()
      before = halvings(security)
      ok_at = Repo.get_by!(ChainRead, chain: "bitcoin").last_ok_at

      serve(%{"mempool.space" => {:status, 503}, "blockstream.info" => {:status, 503}})
      mark = journal_mark()
      later = ~U[2026-11-13 12:00:00Z]

      {result, log} = with_log(fn -> run(now: later) end)
      assert {:error, failures} = result
      assert length(failures) == 2
      assert log =~ "chain read bitcoin: mempool.space: http_503"

      assert halvings(security) == before
      assert entries_since(mark) == []

      state = Repo.get_by!(ChainRead, chain: "bitcoin")
      assert state.last_ok_at == ok_at
      assert state.last_tried_at == later
      assert state.last_error == "mempool.space: http_503; blockstream.info: http_503"
      assert state.tip_height == @tip
    end

    test "a successful run records the host, the tip and its inputs" do
      security!()
      serve(%{"mempool.space" => {:chain, @tip}})

      assert {:ok, _summary} = run()

      state = Repo.get_by!(ChainRead, chain: "bitcoin")
      assert state.source_host == "mempool.space"
      assert state.tip_height == @tip
      assert state.tip_at == DateTime.from_unix!(timestamp(@tip))
      assert state.tip_2016_at == DateTime.from_unix!(timestamp(@tip - 2016))
      assert state.last_ok_at == @now
      assert state.last_tried_at == @now
      assert state.last_error == nil
      assert state.genesis_checked_on == ~D[2026-11-12]
      assert state.genesis_checked_host == "mempool.space"
    end

    test "the stored tip is handed on: a source far behind it is refused" do
      security!()
      serve(%{"mempool.space" => {:chain, @tip}})
      assert {:ok, _summary} = run()

      serve(%{"mempool.space" => {:chain, @tip - 7}, "blockstream.info" => {:chain, @tip + 1}})
      assert {:ok, %{host: "blockstream.info"}} = run(now: ~U[2026-11-12 18:00:00Z])
      assert Repo.get_by!(ChainRead, chain: "bitcoin").source_host == "blockstream.info"
    end

    test "the genesis check runs once a day per source" do
      security!()
      serve(%{"mempool.space" => {:chain, @tip}, "blockstream.info" => {:chain, @tip}})

      assert {:ok, _summary} = run()
      assert {"mempool.space", "block-height/0"} in requested()

      assert {:ok, _summary} = run(now: ~U[2026-11-12 18:00:00Z])
      refute {"mempool.space", "block-height/0"} in requested()

      assert {:ok, _summary} = run(now: ~U[2026-11-13 12:00:00Z])
      assert {"mempool.space", "block-height/0"} in requested()
    end
  end

  # User story:
  # As the operator whose instance must never hold half a run,
  # I want a write the events refuse to roll back every write of the run,
  # and a run that raises to stay its chain's,
  # so that the halvings are either all of one reading or none of it.
  #
  # Acceptance criteria (ADR-0059 §7):
  # - A refused write (here a source link that is not http(s)) writes no
  #   event and records `write_failed` in the state row.
  # - `run_all/1` answers `{:error, :crashed}` for a run that raised and
  #   logs it.
  describe "a run that cannot finish" do
    test "a refused write rolls the run back and is recorded" do
      security = security!()

      read = fn heights_for, _opts ->
        heights = heights_for.(@tip)

        {:ok,
         %{
           source: :mempool,
           host: "mempool.space",
           base: "ftp://mempool.space/api",
           tip: @tip,
           blocks:
             Map.new(heights, &{&1, %{height: &1, hash: hash(&1), timestamp: timestamp(&1)}}),
           genesis_checked: true,
           attempts: []
         }}
      end

      {result, log} = with_log(fn -> run(read: read) end)

      assert {:error, {:write_failed, {:invalid, [:source_url]}}} = result
      assert log =~ "write_failed"
      assert halvings(security) == []

      state = Repo.get_by!(ChainRead, chain: "bitcoin")
      assert state.last_error =~ "write_failed"
      assert state.last_ok_at == nil
    end

    # The closing act's re-check: the error was cut by graphemes, so 600
    # × (e + U+0301) kept some 1,000 code points, the state row's changeset
    # refused them and recording the failure raised.
    test "an error of combining characters is cut to the column by code points" do
      security!()
      error = String.duplicate("e\u0301", 600)

      read = fn _heights_for, _opts ->
        {:error, [%{source: :mempool, host: "h", error: error}]}
      end

      {result, _log} = with_log(fn -> run(read: read) end)
      assert {:error, [_failure]} = result

      stored = Repo.get_by!(ChainRead, chain: "bitcoin").last_error
      assert String.starts_with?(stored, "h: e\u0301")
      assert length(String.codepoints(stored)) <= 512
      assert String.valid?(stored)
    end

    test "a run that raises stays its chain's" do
      security!()
      read = fn _heights_for, _opts -> raise "synthetic adapter bug" end

      {results, log} = with_log(fn -> Reader.run_all(read: read, now: @now) end)

      assert results == [bitcoin: {:error, :crashed}]
      assert log =~ "synthetic adapter bug"
    end
  end

  # User story:
  # As the operator looking at the chart's cycle bar,
  # I want a chain without a successful run for 24 hours to read as stale,
  # so that a dead collector is visibly dead within a day.
  #
  # Acceptance criteria (ADR-0059 §8):
  # - Stale when `last_ok_at` lies 24 hours or more before `now`; a chain
  #   that never answered counts from its first try.
  # - A chain never tried is not stale.
  describe "stale?/2" do
    test "flips at exactly 24 hours without a successful run" do
      ok_at = ~U[2026-11-11 12:00:00Z]
      state = %ChainRead{last_ok_at: ok_at, inserted_at: ~U[2026-11-01 00:00:00Z]}

      refute Reader.stale?(state, DateTime.add(ok_at, 24 * 3600 - 1))
      assert Reader.stale?(state, DateTime.add(ok_at, 24 * 3600))
    end

    test "a chain that never answered counts from its first try" do
      tried = ~U[2026-11-12 00:00:00Z]
      state = %ChainRead{last_ok_at: nil, inserted_at: tried}

      refute Reader.stale?(state, DateTime.add(tried, 3600))
      assert Reader.stale?(state, DateTime.add(tried, 24 * 3600))
    end

    test "a chain never tried is not stale" do
      refute Reader.stale?(nil, @now)
    end
  end
end
