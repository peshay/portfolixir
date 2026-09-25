defmodule Portfolixir.Repo.SessionZone do
  @moduledoc """
  Sets each database session's `TimeZone` to the host clock's zone
  (E25 S6, G08), as `Portfolixir.Repo`'s `after_connect`.

  The domain decides "today" with `Portfolixir.Clock.today/0`, the BEAM's
  local day, and the policy-rule guard trigger with `CURRENT_DATE`, the
  session's day. A database running in another zone than the application
  (a container without `TZ`, a server's `timezone` setting) put those two a
  day apart around midnight. The session now takes the application's zone
  whenever a connection opens.

  The zone is passed as a parameter, never spliced into SQL. A zone the
  database does not know is refused by `set_config/3` itself, which leaves
  the session as the server configured it; that, or no zone at all, is
  logged once and never fails the connection, so a mistyped `TZ` cannot
  keep the instance from starting. One statement per connection, no scan
  of the zone catalogue.
  """

  require Logger

  alias Portfolixir.Clock

  @align "SELECT set_config('TimeZone', $1, false)"

  @doc "The repository's `after_connect`: aligns `conn` to `Clock.zone/0`."
  @spec after_connect(DBConnection.conn()) :: :ok | :unknown
  def after_connect(conn), do: align(conn, Clock.zone())

  @doc """
  Sets the session `TimeZone` of `conn` to `zone` when the database knows
  it. Returns `:ok`, or `:unknown` when there is no zone or the database
  does not know it (the session is then left as it was).
  """
  @spec align(DBConnection.conn(), String.t() | nil) :: :ok | :unknown
  def align(_conn, nil) do
    warn_once(:no_zone, "the host clock's zone has no name (TZ unset or a rule string)")
    :unknown
  end

  def align(conn, zone) when is_binary(zone) do
    case Postgrex.query(conn, @align, [zone]) do
      {:ok, %Postgrex.Result{}} ->
        :ok

      _unknown_or_failed ->
        warn_once({:unknown, zone}, "the database knows no zone named #{inspect(zone)}")
        :unknown
    end
  end

  defp warn_once(key, reason) do
    key = {__MODULE__, key}

    unless :persistent_term.get(key, false) do
      :persistent_term.put(key, true)

      Logger.warning(
        "database session zone not aligned with the application (E25 S6, G08): #{reason}; " <>
          "set TZ to a zone name, e.g. TZ=Europe/Berlin, so both decide the same day"
      )
    end
  end
end
