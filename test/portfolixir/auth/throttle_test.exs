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
end
