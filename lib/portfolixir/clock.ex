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

  **One clock** (E25 S6, G08): every "today" the domain decides with reads
  `today/0`; a meta-test keeps `Date.utc_today/0` out of `lib/` except where
  the question really is about UTC (the "changed since" presets, which are
  compared with UTC timestamps). The database session is set to the host
  clock's zone on every connection (`Portfolixir.Repo.SessionZone`, reading
  `zone/0`), so a trigger's `CURRENT_DATE` is the same day. The zone is the
  process's `TZ`, or the system's zone file where `TZ` is unset.
  """

  # A zone name as the tz database spells one: letters, digits, `_`, `+`,
  # `-` and `/` separators ("Europe/Berlin", "Etc/GMT+2", "UTC").
  @zone_name ~r{\A[A-Za-z0-9_+\-]+(/[A-Za-z0-9_+\-]+)*\z}

  @doc "The host's local calendar date."
  @spec today() :: Date.t()
  def today do
    {{year, month, day}, _time} = :calendar.local_time()

    Date.new!(year, month, day)
  end

  @doc """
  The host's calendar date at the UTC instant `datetime` — the day a stored
  timestamp fell on where the instance runs, the same answer `today/0`
  gives for now.
  """
  @spec local_date(DateTime.t()) :: Date.t()
  def local_date(%DateTime{} = datetime) do
    {{year, month, day}, _time} =
      datetime
      |> DateTime.shift_zone!("Etc/UTC")
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()
      |> :calendar.universal_time_to_local_time()

    Date.new!(year, month, day)
  end

  @doc """
  The name of the zone the host clock runs in: `TZ` when it names a zone
  (as `Europe/Berlin`, `:Europe/Berlin` or a `zoneinfo` path), otherwise the
  zone `/etc/localtime` links to, or `/etc/timezone` names. `nil` when none
  of them names a zone — a POSIX rule string in `TZ` included.
  """
  @spec zone() :: String.t() | nil
  def zone do
    case System.get_env("TZ") do
      tz when is_binary(tz) and tz != "" -> zone_name(tz)
      _unset -> system_zone()
    end
  end

  defp system_zone do
    with {:error, _} <- zone_from_link("/etc/localtime"),
         {:ok, content} <- File.read("/etc/timezone") do
      zone_name(content)
    else
      {:ok, zone} -> zone
      {:error, _no_file} -> nil
    end
  end

  defp zone_from_link(path) do
    case File.read_link(path) do
      {:ok, target} ->
        case zone_name(target) do
          nil -> {:error, :not_a_zone}
          zone -> {:ok, zone}
        end

      error ->
        error
    end
  end

  defp zone_name(value) do
    name =
      value
      |> String.trim()
      |> String.trim_leading(":")
      |> String.split("zoneinfo/")
      |> List.last()

    if name =~ @zone_name, do: name
  end
end
