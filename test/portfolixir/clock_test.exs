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
end
