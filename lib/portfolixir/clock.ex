defmodule Portfolixir.Clock do
  @moduledoc """
  The host's calendar date.

  Portfolixir's domain data is day-granular and self-hosted: "today" means the
  day it is where the instance runs, not the day it is in UTC. East of UTC the
  two differ between local midnight and UTC midnight, and a UTC-based check
  rejects an event dated today as lying in the future (issue #609).

  This is deliberately **not** a time model. There is no timezone
  configuration, no DateTime in domain data, and no attempt to reason about
  instants — only the boundary question "which calendar day is it here?",
  answered from the host clock through `:calendar.local_time/0`.

  `Date.utc_today/0` stays correct wherever the question really is about UTC.
  """

  @doc "The host's local calendar date."
  @spec today() :: Date.t()
  def today do
    {{year, month, day}, _time} = :calendar.local_time()

    Date.new!(year, month, day)
  end
end
