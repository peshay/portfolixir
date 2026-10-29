defmodule Portfolixir.Auth.ThrottleTest do
  # Issue #771 (and ADR-0045 §1): failed credential checks are counted per
  # source and locked out with an exponential back-off, without a dependency.
  use ExUnit.Case, async: true

  alias Portfolixir.Auth.Throttle

  defp key(label), do: "#{label}-#{System.unique_integer([:positive])}"

  # User story:
  # As the operator,
  # I want repeated wrong tokens or passwords from one source locked out for a growing interval,
  # so that online guessing is bounded by the back-off, not by network speed.
  #
  # Acceptance criteria:
  # - Below the failure threshold the source is allowed.
  # - At the threshold the source is locked for the base interval; each further
  #   failure doubles it, up to the cap.
  # - A success clears the count; the lock expires by itself.
  test "locks after the threshold and doubles the interval" do
    scope = :api
    source = key("lock")
    now = 1_000

    for _ <- 1..(Throttle.max_failures() - 1) do
      Throttle.failure(scope, source, now: now)
      assert Throttle.check(scope, source, now: now) == :ok
    end

    Throttle.failure(scope, source, now: now)
    assert {:locked, base} = Throttle.check(scope, source, now: now)
    assert base == Throttle.base_lock_seconds()

    assert Throttle.check(scope, source, now: now + base) == :ok

    Throttle.failure(scope, source, now: now + base)
    assert {:locked, doubled} = Throttle.check(scope, source, now: now + base)
    assert doubled == base * 2
  end

  test "the lock never exceeds the cap" do
    source = key("cap")

    Enum.each(1..40, fn i -> Throttle.failure(:api, source, now: i * 100_000) end)

    assert {:locked, seconds} = Throttle.check(:api, source, now: 40 * 100_000)
    assert seconds == Throttle.max_lock_seconds()
  end

  test "a success clears the count and scopes are independent" do
    source = key("reset")

    Enum.each(1..Throttle.max_failures(), fn _ -> Throttle.failure(:api, source, now: 5) end)
    assert {:locked, _} = Throttle.check(:api, source, now: 5)
    assert Throttle.check(:ui, source, now: 5) == :ok

    Throttle.success(:api, source)
    assert Throttle.check(:api, source, now: 5) == :ok
  end

  # User story:
  # As the operator,
  # I want the throttle table to forget sources that have been quiet for well
  # past the longest lock, and nothing else,
  # so that memory stays bounded without handing a slow guesser fresh attempts.
  #
  # Acceptance criteria:
  # - A source whose last failure is older than the retention is dropped by the sweep.
  # - A source that failed recently keeps its count, locked or not.
  # - A non-address source key is still a string.
  test "the sweep forgets only sources quiet for longer than the retention" do
    assert Throttle.source_key({127, 0, 0, 1}) == "127.0.0.1"
    assert Throttle.source_key(:unknown) == ":unknown"

    stale = key("stale")
    recent = key("recent")
    now = System.os_time(:second)

    Enum.each(1..Throttle.max_failures(), fn _ ->
      Throttle.failure(:api, stale, now: now - Throttle.retention_seconds() - 60)
    end)

    Enum.each(1..(Throttle.max_failures() - 1), fn _ ->
      Throttle.failure(:api, recent, now: now)
    end)

    send(Process.whereis(Throttle), :sweep)
    :sys.get_state(Throttle)

    assert :ets.lookup(Throttle, {:api, stale}) == []
    assert [{_, count, 0, _}] = :ets.lookup(Throttle, {:api, recent})
    assert count == Throttle.max_failures() - 1

    Throttle.failure(:api, recent, now: now)
    assert {:locked, _} = Throttle.check(:api, recent, now: now)
  end

  # User story (E25 S1, F04):
  # As the operator,
  # I want a locked-out source to stay escalated after its lock runs out and
  # the table is swept,
  # so that waiting for the sweep does not hand a guesser a fresh set of attempts.
  #
  # Acceptance criteria:
  # - The retention is well past the longest lock.
  # - A source escalated to a long lock, quiet for longer than the longest lock
  #   but inside the retention, keeps its count through a sweep: its next
  #   failure locks it again at once, for the longest lock.
  test "escalation survives a sweep" do
    assert Throttle.retention_seconds() >= 10 * Throttle.max_lock_seconds()

    source = key("escalated")
    now = System.os_time(:second)
    earlier = now - 2 * Throttle.max_lock_seconds()

    Enum.each(1..(Throttle.max_failures() + 10), fn _ ->
      Throttle.failure(:api, source, now: earlier)
    end)

    assert Throttle.check(:api, source, now: now) == :ok

    send(Process.whereis(Throttle), :sweep)
    :sys.get_state(Throttle)

    Throttle.failure(:api, source, now: now)
    assert {:locked, seconds} = Throttle.check(:api, source, now: now)
    assert seconds == Throttle.max_lock_seconds()
  end

  # User story (E25 S1, F04):
  # As an operator with a UI password,
  # I want failed logins counted across all sources as well as per source,
  # so that spreading guesses over many addresses does not multiply them.
  #
  # Acceptance criteria:
  # - The UI scope has a rolling ceiling; the API scope has none.
  # - Failures spread over rotating sources, each below its own threshold,
  #   trip the scope-wide ceiling: every source is then told to wait,
  #   including one that never failed.
  # - The lock lasts until enough failures have aged out of the rolling window,
  #   and not longer than the window.
  test "failures spread over rotating sources trip the scope-wide ceiling" do
    assert {ceiling, window} = Throttle.scope_ceiling(:ui)
    assert Throttle.scope_ceiling(:api) == nil
    assert ceiling > Throttle.max_failures()

    # A fixed clock long past, so no test on the real clock shares the window.
    now = 1_000 * window

    Enum.each(1..(ceiling - 1), fn i ->
      Throttle.failure(:ui, key("rotating-#{i}"), now: now)
    end)

    assert Throttle.check(:ui, key("bystander"), now: now) == :ok

    Throttle.failure(:ui, key("rotating-last"), now: now + 30)

    assert {:locked, seconds} = Throttle.check(:ui, key("bystander"), now: now + 30)
    assert seconds > 0 and seconds <= window
    assert {:locked, _} = Throttle.check(:ui, key("bystander"), now: now + window - 60)
    assert Throttle.check(:ui, key("bystander"), now: now + window + 60) == :ok

    # The API scope is not affected by the UI's ceiling.
    assert Throttle.check(:api, key("bystander"), now: now + 30) == :ok
  end

  # User story (security review 2026-10-12, H03):
  # As the operator,
  # I want the API scope to stop taking first failures from sources it does
  # not remember once a rolling ceiling is reached,
  # so that failures spread over many prefixes cannot grow the table without
  # bound or hand an unrecorded source unlimited attempts.
  #
  # Acceptance criteria:
  # - The API scope has a first-failure ceiling; the UI scope, whose
  #   failures the scope-wide ceiling already bounds, has none.
  # - Past it, a source the scope does not remember is told to wait and its
  #   failure is not recorded; a source it remembers keeps its own count.
  # - The ceiling lasts no longer than its window.
  test "past the first-failure ceiling an unknown source waits and is not recorded" do
    assert {ceiling, window} = Throttle.new_source_ceiling(:api)
    assert Throttle.new_source_ceiling(:ui) == nil
    assert ceiling * 10 <= Throttle.max_rows()

    # A fixed clock long past, so no test on the real clock shares the window.
    now = 2_000 * window
    known = key("known")
    Throttle.failure(:api, known, now: now)

    Enum.each(2..ceiling, fn i -> Throttle.failure(:api, key("first-#{i}"), now: now) end)

    stranger = key("stranger")
    assert {:locked, seconds} = Throttle.check(:api, stranger, now: now + 30)
    assert seconds > 0 and seconds <= window
    Throttle.failure(:api, stranger, now: now + 30)
    assert :ets.lookup(Throttle, {:api, stranger}) == []

    assert Throttle.check(:api, known, now: now + 30) == :ok
    Throttle.failure(:api, known, now: now + 30)
    assert [{_, 2, _, _}] = :ets.lookup(Throttle, {:api, known})

    assert Throttle.check(:api, stranger, now: now + window + 60) == :ok
  end

  # User story (security review 2026-10-12, H03):
  # As the operator,
  # I want first failures from unseen sources counted toward the API scope's
  # ceiling even once the table holds its cap,
  # so that a full table cannot switch the ceiling off.
  #
  # Acceptance criteria:
  # - With the table full, an unseen source's failure adds no row, and below
  #   the ceiling an unseen source is not told to wait.
  # - Unseen sources still reach the ceiling: past it, an unseen source is
  #   told to wait.
  test "a full table still counts unseen sources toward the first-failure ceiling" do
    {ceiling, window} = Throttle.new_source_ceiling(:api)
    # A fixed clock long past, so no test on the real clock shares the window.
    now = 3_000 * window

    try do
      fill = Throttle.max_rows() - :ets.info(Throttle, :size)
      Enum.each(1..max(fill, 1), fn i -> Throttle.failure(:full_fill, "fill-#{i}", now: now) end)
      assert :ets.info(Throttle, :size) >= Throttle.max_rows()

      first = key("unseen-first")
      Throttle.failure(:api, first, now: now)
      assert :ets.lookup(Throttle, {:api, first}) == []
      assert Throttle.check(:api, key("probe"), now: now) == :ok

      Enum.each(2..ceiling, fn i -> Throttle.failure(:api, key("unseen-#{i}"), now: now) end)

      assert {:locked, seconds} = Throttle.check(:api, key("stranger"), now: now + 30)
      assert seconds > 0 and seconds <= window
    after
      :ets.select_delete(Throttle, [{{{:full_fill, :_}, :_, :_, :_}, [], [true]}])
      :ets.delete(Throttle, {:api, {:new_sources, div(now, 60)}})
    end
  end

  test "concurrent failures are all counted" do
    source = key("concurrent")

    1..50
    |> Task.async_stream(fn _ -> Throttle.failure(:api, source, now: 7) end, max_concurrency: 50)
    |> Stream.run()

    assert [{_, 50, _, _}] = :ets.lookup(Throttle, {:api, source})
  end
end
