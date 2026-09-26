defmodule Portfolixir.ClockTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Clock

  # User story (2026-07-29, issue #609):
  # As a maintainer running Portfolixir east of UTC,
  # I want "today" to mean the day it is on the host,
  # so that a split effective today is bookable between local midnight and UTC
  # midnight instead of being rejected as a future date.
  #
  # Acceptance criteria:
  # - Clock.today/0 is the host's local calendar date, not the UTC one.
  # - It never drifts more than a day from UTC, which is what makes it a
  #   boundary fix rather than a new time model.

  test "today is the host's local calendar date" do
    {{year, month, day}, _time} = :calendar.local_time()

    assert Clock.today() == Date.new!(year, month, day)
  end

  test "the local date stays within a day of UTC" do
    assert abs(Date.diff(Clock.today(), Date.utc_today())) <= 1
  end

  # User story (ADR-0050 §12, L5a):
  # As the operator reading when an account was merged,
  # I want a stored UTC timestamp read as the day it was where the instance
  # runs,
  # so that a merge made just after local midnight is dated that day.
  #
  # Acceptance criteria:
  # - Clock.local_date/1 is the host's calendar date at the given instant:
  #   now reads as today, and any instant is within a day of its UTC date.
  test "a stored UTC instant reads as the host's calendar date" do
    assert Clock.local_date(DateTime.utc_now()) == Clock.today()

    instant = ~U[2026-09-24 23:30:00Z]

    {{year, month, day}, _time} =
      :calendar.universal_time_to_local_time({{2026, 9, 24}, {23, 30, 0}})

    assert Clock.local_date(instant) == Date.new!(year, month, day)
    assert abs(Date.diff(Clock.local_date(instant), ~D[2026-09-24])) <= 1
  end
end
