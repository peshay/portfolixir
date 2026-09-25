defmodule Portfolixir.ClockZoneTest do
  # E25 S6 (#891), G08: "today" was read from three clocks. The domain now
  # reads `Portfolixir.Clock.today/0` (the BEAM's local day), and every
  # database connection sets its session zone to the BEAM's on connect, so
  # `CURRENT_DATE` in a trigger is the same day as the code's. The snapshot
  # writers keep honouring an injected day.
  #
  # async: false — the zone test sets TZ for the BEAM process.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Repo.SessionZone
  alias Portfolixir.Tax

  # User story:
  # As the operator who sets TZ for the instance,
  # I want the product to know that zone by name,
  # so that the database can be told the same zone.
  #
  # Acceptance criteria:
  # - Clock.zone/0 reads TZ (a name, a ":name" or a zoneinfo path) and
  #   otherwise the system's zone file; anything that is not a zone name is
  #   no zone.
  test "the host clock's zone is read from TZ, else from the system's zone file" do
    original = System.get_env("TZ")

    try do
      System.put_env("TZ", "Europe/Berlin")
      assert Clock.zone() == "Europe/Berlin"

      System.put_env("TZ", ":America/New_York")
      assert Clock.zone() == "America/New_York"

      System.put_env("TZ", ":/usr/share/zoneinfo/Asia/Tokyo")
      assert Clock.zone() == "Asia/Tokyo"

      System.put_env("TZ", "not a zone; at all")
      assert Clock.zone() == nil

      System.delete_env("TZ")
      assert Clock.zone() == nil or is_binary(Clock.zone())
    after
      if original, do: System.put_env("TZ", original), else: System.delete_env("TZ")
    end
  end

  # User story:
  # As the operator of an instance whose database runs in another zone than
  # the application,
  # I want each database session to use the application's zone,
  # so that a trigger's CURRENT_DATE is the day the application checks with.
  #
  # Acceptance criteria:
  # - Aligning a connection sets its TimeZone to the given zone; a zone the
  #   database does not know leaves the session as it was and never fails
  #   the connection.
  # - The repository aligns every connection it opens, to Clock.zone/0.
  test "a database session takes the application's zone" do
    {:ok, conn} = Postgrex.start_link(connection_opts())

    try do
      assert SessionZone.align(conn, "America/New_York") == :ok
      assert show_zone(conn) == "America/New_York"

      assert SessionZone.align(conn, "Not/A_Zone") == :unknown
      assert show_zone(conn) == "America/New_York"
    after
      GenServer.stop(conn)
    end

    assert Repo.config()[:after_connect] == {SessionZone, :after_connect, []}

    case Clock.zone() do
      nil -> :ok
      zone -> assert %{rows: [[^zone]]} = Repo.query!("SHOW TimeZone")
    end
  end

  # User story:
  # As a test or a job that decides what "today" is,
  # I want the snapshot writers to use the day I inject,
  # so that their future-date check is decided against that day.
  #
  # Acceptance criteria:
  # - A depot snapshot and a tax statement snapshot dated after the real
  #   day are accepted with a later injected day, and refused with an
  #   injected day before them.
  test "the snapshot writers honour an injected today" do
    later = Date.add(Clock.today(), 10)
    as_of = Date.add(Clock.today(), 5)

    assert {:ok, _} =
             Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Injected", as_of: as_of},
               today: later
             )

    assert {:error, _} =
             Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Refused", as_of: as_of},
               today: Clock.today()
             )

    attrs = %{institution: "Clock Bank", holder: "Owner", tax_year: as_of.year, as_of: as_of}
    assert {:ok, snapshot} = Tax.create_snapshot(Actor.owner_ui(), attrs, today: later)
    assert {:error, _} = Tax.create_snapshot(Actor.owner_ui(), attrs, today: Clock.today())

    assert {:error, _} =
             Tax.update_snapshot(Actor.owner_ui(), snapshot, %{as_of: Date.add(later, 1)},
               today: later
             )
  end

  defp show_zone(conn) do
    %{rows: [[zone]]} = Postgrex.query!(conn, "SHOW TimeZone", [])
    zone
  end

  defp connection_opts do
    Repo.config()
    |> Keyword.take([:hostname, :port, :username, :password, :database, :socket_dir])
  end
end
