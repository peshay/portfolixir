defmodule Portfolixir.Portfolios.Performance.WalkMemoryBoundTest do
  # K08 (security review 2026-10-12): the daily walk holds a security's
  # closes only while they can move a figure, and a contribution window's
  # walk starts at the window, so its memory follows held security-days.
  # Synthetic data only; no network.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog
  import Portfolixir.WorldFixtures

  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Contribution
  alias PortfolixirWeb.HeapCap

  @moduletag timeout: 300_000

  defp securities!(n, tag) do
    for i <- 1..n, do: create_security!(name: "Walk #{tag} #{i}", ticker: nil)
  end

  # Synthetic daily closes for every security from `from` to `to`, as a
  # provider sync stores them (source "auto"). `security_quotes` carries no
  # trigger, so a bulk insert stores exactly the rows `Quotes.upsert_many/2`
  # would.
  defp seed_daily_closes!(securities, from, to) do
    ids = Enum.map(securities, & &1.id)

    %{num_rows: n} =
      Repo.query!(
        """
        INSERT INTO security_quotes (security_id, date, close, source, inserted_at, updated_at)
        SELECT s.id, d::date, 50 + (s.id % 50) + ((d::date - $2::date) % 17), 'auto',
               now()::timestamp(0), now()::timestamp(0)
        FROM unnest($1::bigint[]) AS s(id),
             generate_series($2::date, $3::date, interval '1 day') AS d
        """,
        [ids, from, to],
        timeout: :infinity
      )

    n
  end

  @doc false
  def count_rows(
        _event,
        _measurements,
        %{source: "security_quotes", result: {:ok, %{num_rows: n}}},
        counter
      )
      when is_integer(n),
      do: :counters.add(counter, 1, n)

  def count_rows(_event, _measurements, _metadata, _counter), do: :ok

  # Runs `fun` in a fresh process (capped like a request process when `cap?`),
  # tracing its garbage collections. Returns the outcome, the peak heap block
  # (young + old + heap fragments, bytes), the closes its queries returned
  # and the elapsed time.
  defp measure(fun, cap?) do
    counter = :counters.new(1, [])
    handler = "walk-rows-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(handler, [:portfolixir, :repo, :query], &__MODULE__.count_rows/4, counter)

    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        receive do
          :go -> :ok
        end

        if cap?, do: HeapCap.cap!()
        result = fun.()
        send(parent, {:walk_done, self(), shape(result)})
      end)

    1 = :erlang.trace(pid, true, [:garbage_collection, {:tracer, self()}])
    started = System.monotonic_time(:millisecond)
    send(pid, :go)
    {outcome, peak_words} = collect(pid, ref, :running, 0)
    elapsed = System.monotonic_time(:millisecond) - started
    :telemetry.detach(handler)

    %{
      outcome: outcome,
      peak_bytes: peak_words * :erlang.system_info(:wordsize),
      quote_rows: :counters.get(counter, 1),
      elapsed_ms: elapsed
    }
  end

  defp shape({:ok, %{positions: positions}}), do: {:contribution_rows, length(positions)}
  defp shape(%{daily: daily}), do: {:walked_days, length(daily)}
  defp shape(other), do: {:other, other |> inspect() |> String.slice(0, 80)}

  defp collect(pid, ref, outcome, peak) do
    receive do
      {:trace, ^pid, kind, info}
      when kind in [:gc_minor_start, :gc_minor_end, :gc_major_start, :gc_major_end] ->
        size =
          Keyword.get(info, :heap_block_size, 0) + Keyword.get(info, :old_heap_block_size, 0) +
            Keyword.get(info, :mbuf_size, 0)

        collect(pid, ref, outcome, max(peak, size))

      {:walk_done, ^pid, summary} ->
        collect(pid, ref, {:completed, summary}, peak)

      {:DOWN, ^ref, :process, ^pid, reason} ->
        outcome = if outcome == :running, do: {:died, reason}, else: outcome
        {outcome, drain_gc(pid, peak)}
    after
      240_000 -> {:timeout, peak}
    end
  end

  defp drain_gc(pid, peak) do
    receive do
      {:trace, ^pid, _kind, info} when is_list(info) ->
        size =
          Keyword.get(info, :heap_block_size, 0) + Keyword.get(info, :old_heap_block_size, 0) +
            Keyword.get(info, :mbuf_size, 0)

        drain_gc(pid, max(peak, size))
    after
      100 -> peak
    end
  end

  defp mb(bytes), do: Float.round(bytes / 1_048_576, 1)

  # User story (security review 2026-10-12, K08):
  # As the operator whose ledger holds one booking far older than any
  # position,
  # I want the walk to load each security's closes from its own first
  # booking on,
  # so that an old cash booking does not make every read hold decades of
  # closes no position was held for.
  #
  # Acceptance criteria:
  # - A cash booking dated 1970, before every security's first booking,
  #   leaves the closes the walk loads within 1.2 times, and its peak heap
  #   within 3 times, of the walk without it: the walk's own per-day state
  #   grows with the days it walks (about 20,700 against 3,650), the loaded
  #   closes do not, and a walk that loaded the 56 years of closes would
  #   grow by the rows' factor, above 5. CI's runner measured 1.72 where a
  #   quieter machine measured less; the bound is the insecure behaviour's,
  #   not a GC timing's.
  test "one booking dated 1970 leaves the closes a walk loads, and its heap, within a small factor" do
    today = Clock.today()
    first = Date.add(today, -3652)
    world = base_world()
    deposit!(world, "100000", first)
    secs = securities!(20, "A")
    Enum.each(secs, &buy!(world, &1, date: first, quantity: "1", price: "60"))
    seeded = seed_daily_closes!(secs, ~D[1970-01-02], today)

    plain = measure(fn -> Performance.analysis(world.portfolio.id, today: today) end, false)

    # One cash booking dated 1970, before any security was held.
    deposit!(world, "1", ~D[1970-01-02])
    stretched = measure(fn -> Performance.analysis(world.portfolio.id, today: today) end, false)

    report =
      "seeded=#{seeded} closes for 20 securities since 1970-01-02, every buy on #{first}\n" <>
        "first booking #{first}: #{inspect(plain.outcome)} quote_rows=#{plain.quote_rows} " <>
        "peak=#{mb(plain.peak_bytes)} MB elapsed=#{plain.elapsed_ms} ms\n" <>
        "plus one 1970-01-02 deposit: #{inspect(stretched.outcome)} quote_rows=#{stretched.quote_rows} " <>
        "peak=#{mb(stretched.peak_bytes)} MB elapsed=#{stretched.elapsed_ms} ms\n" <>
        "rows x#{Float.round(stretched.quote_rows / max(plain.quote_rows, 1), 2)}, " <>
        "peak x#{Float.round(stretched.peak_bytes / max(plain.peak_bytes, 1), 2)}, " <>
        "bytes per loaded close (stretched) #{div(stretched.peak_bytes, max(stretched.quote_rows, 1))}"

    assert match?({:completed, _}, plain.outcome) and match?({:completed, _}, stretched.outcome),
           report

    # Secure behaviour: no security was held before its own first booking, so
    # a cash booking in 1970 must not make the walk load (and hold) 56 years
    # of every security's closes.
    assert stretched.quote_rows <= plain.quote_rows * 1.2 and
             stretched.peak_bytes <= plain.peak_bytes * 3,
           "the 1970 booking stretched every security's loaded closes:\n" <> report
  end

  # User story (security review 2026-10-12, K08):
  # As the operator with a large but ordinary history,
  # I want a contribution read over a short window to walk that window,
  # so that it answers under the heap cap a request runs under instead of
  # being killed every time.
  #
  # Acceptance criteria:
  # - A 30-day contribution range over 300 securities with ten years of
  #   daily closes completes in a process under the request heap cap.
  test "a 30-day contribution range over 300 securities x 10 years completes under the request heap cap" do
    today = Clock.today()
    first = Date.add(today, -3652)
    world = base_world()
    deposit!(world, "1000000", first)
    secs = securities!(300, "B")
    Enum.each(secs, &buy!(world, &1, date: first, quantity: "1", price: "60"))
    seeded = seed_daily_closes!(secs, first, today)
    window = {:range, Date.add(today, -29), today}

    {result, log} =
      with_log(fn ->
        measured =
          measure(
            fn ->
              Contribution.for_portfolio(world.portfolio.id, period: window, today: today)
            end,
            true
          )

        # The heap-kill report and the connection's "client exited" are
        # logged by other processes after the kill: wait for them inside the
        # capture.
        Process.sleep(1_500)
        measured
      end)

    report =
      "seeded=#{seeded} closes (300 securities x #{Date.diff(today, first) + 1} days), " <>
        "window #{inspect(window)}, cap #{HeapCap.max_heap_words()} words\n" <>
        "Contribution.for_portfolio under HeapCap.cap!(): #{inspect(result.outcome)} " <>
        "quote_rows_loaded=#{result.quote_rows} peak=#{mb(result.peak_bytes)} MB " <>
        "elapsed=#{result.elapsed_ms} ms\n" <>
        "log: " <>
        (log
         |> String.split("\n", trim: true)
         |> Enum.filter(
           &(&1 =~ ~r/maximum heap size|Total Heap Size|Max Heap Size|client .* exited/)
         )
         |> Enum.map_join(" | ", &String.trim/1))

    assert match?({:completed, _}, result.outcome),
           "the request-path contribution walk did not complete under the heap cap:\n" <> report
  end
end
