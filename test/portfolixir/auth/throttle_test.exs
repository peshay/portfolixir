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
  # I want the throttle table to forget sources that have been quiet for longer
  # than the longest lock, and nothing else,
  # so that memory stays bounded without handing a slow guesser fresh attempts.
  #
  # Acceptance criteria:
  # - A source whose last failure is older than the longest lock is dropped by the sweep.
  # - A source that failed recently keeps its count, locked or not.
  # - A non-address source key is still a string.
  test "the sweep forgets only sources quiet for longer than the longest lock" do
    assert Throttle.source_key({127, 0, 0, 1}) == "127.0.0.1"
    assert Throttle.source_key(:unknown) == ":unknown"

    stale = key("stale")
    recent = key("recent")
    now = System.os_time(:second)

    Enum.each(1..Throttle.max_failures(), fn _ ->
      Throttle.failure(:api, stale, now: now - 4 * Throttle.max_lock_seconds())
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
end
