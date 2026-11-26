defmodule Portfolixir.Dashboards.Starters do
  @moduledoc """
  The starter dashboards, stored once (ADR-0062's amendment of 2026-11-25,
  point 5; I57; Sprint 32 S3; planning board
  `ux-design-2026-11-25-sprint32/02` A).

  Each template marked as a starter (`Portfolixir.Dashboards.Templates.starters/0`)
  is stored once, on the first start of the release that brings it, by
  `seed_on_boot/0`, a step of `Portfolixir.Application.after_start/0`:
  copied as a dashboard (`Portfolixir.Dashboards.copy_template/3`, its
  `template_key` recorded) under the system actor
  `Actor.system_job("dashboard_starters")`, journaled, and recorded in the
  seed table by its key (`Portfolixir.Dashboards.Seed`, journaled too). A
  starter recorded is never stored again, so one the operator deleted
  stays deleted; from its first save on it is a dashboard like any other.

  **An instance that already stores a dashboard counts „Überblick“ as
  seeded**: it is recorded, not stored, so an upgrade never adds it beside
  dashboards the operator made. The check reads the dashboards once, before
  the run stores anything.

  **The starters follow „Überblick“** (Sprint 32 W5; board 02 ①): a
  starter other than „Überblick“ is stored at the position of the stored
  copy of „Überblick“, so the menu, which reads by position and then id,
  lists the starters right after it and before the dashboards the
  operator made; without such a copy, last.

  **A read never writes**: only this step stores a starter; the page and
  the API still offer the templates while no dashboard is stored.

  **Concurrency** (`Portfolixir.LockTable` row 32): the run is one
  transaction that first takes a transaction advisory lock on the
  starters, then reads the seed table and the dashboards, then creates
  under row 30's count lock. Two runs at once (two starts on one database)
  queue on it, and the second finds the first's records; an operator's
  create takes only the count lock, so it never waits for the run, and a
  create that commits before the run reads the dashboards makes it count
  „Überblick“ (`test/portfolixir/lock_race/dashboard_starters_race_test.exs`).
  A starter the limit of `Portfolixir.Dashboards.max_dashboards/0` leaves
  no room for is neither stored nor recorded, and the next start tries
  again.

  Names: a starter is stored under its template's title in the locale the
  run reads, the release's default (English); the operator renames it like
  any dashboard. While it is unrenamed — its `template_key` set and its
  stored name that template's untranslated source title — every screen
  shows the template's title in the page's language instead
  (`Portfolixir.Dashboards.display_name/1`: „Überblick“ on a German
  page; the S32 closing act). The stored name and the API, which is
  locale-free, stay as stored („Overview“).
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Seed
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  # The transaction advisory lock a run takes first (`Portfolixir.LockTable`
  # row 32).
  @lock "dashboards|starters"
  # The one starter an instance that already stores a dashboard counts as
  # seeded (the amendment's point 5).
  @counted_when_stored "overview"

  @typedoc "What a run did: the starters it stored, and the ones it recorded without storing."
  @type report :: %{stored: [String.t()], counted: [String.t()]}

  @doc """
  Stores each starter not yet recorded and records it, in one transaction
  under the starters' lock, on behalf of `actor` (the system actor by
  default). `{:ok, report}`, or `{:error, reason}` when a write is refused,
  with nothing written.
  """
  @spec seed(Actor.t()) :: {:ok, report()} | {:error, term()}
  def seed(%Actor{} = actor \\ Actor.system_job("dashboard_starters")) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [@lock])

      recorded = MapSet.new(Repo.all(from(s in Seed, select: s.template_key)))
      stored_any? = Repo.exists?(Dashboard)

      Templates.starters()
      |> Enum.reject(&MapSet.member?(recorded, &1.key))
      |> Enum.reduce(%{stored: [], counted: []}, &seed_one(&1, &2, actor, stored_any?))
      |> Map.new(fn {key, keys} -> {key, Enum.reverse(keys)} end)
    end)
  end

  defp seed_one(%{key: @counted_when_stored = key}, report, actor, true) do
    record!(actor, key)
    Map.update!(report, :counted, &[key | &1])
  end

  defp seed_one(%{key: key}, report, actor, _stored_any?) do
    if Repo.aggregate(Dashboard, :count) >= Dashboards.max_dashboards() do
      Logger.warning("starter dashboard #{key} not stored: the instance holds the most it keeps")
      report
    else
      case Dashboards.copy_template(actor, key, %{}, position: position(key)) do
        {:ok, _dashboard} ->
          record!(actor, key)
          Map.update!(report, :stored, &[key | &1])

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end
  end

  # Sprint 32 W5 (plan W5; board ux-design-2026-11-25-sprint32/02 ①): the
  # starters of a screen follow „Überblick“ in the menu, before the
  # dashboards the operator made: each takes the position of the stored
  # copy of „Überblick“ and, with a higher id, reads right after it and
  # after the starters stored before it. Without one, last, as any copy.
  defp position(@counted_when_stored), do: :last

  defp position(_key) do
    case Repo.one(
           from(d in Dashboard,
             where: d.template_key == @counted_when_stored,
             order_by: [asc: d.position, asc: d.id],
             limit: 1,
             select: d.position
           )
         ) do
      nil -> :last
      position -> position
    end
  end

  defp record!(actor, key) do
    Multi.new()
    |> Multi.insert(:seed, Seed.changeset(key, DateTime.utc_now()))
    |> Journal.record(actor,
      resource_type: "dashboard_seed",
      operation: :create,
      source: :seed,
      resource_id: key
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, _step, reason, _changes} -> Repo.rollback(reason)
    end
  end

  @doc """
  The boot step (`Portfolixir.Application.after_start/0`): `seed/1` unless
  `:seed_starters_on_boot` is false (off in the test environment, where
  each test seeds in its own sandbox, and in the rebuild's standalone
  start). A refusal or an error is logged, never raised: a start is never
  stopped by a starter. Always `:ok`.
  """
  @spec seed_on_boot() :: :ok
  def seed_on_boot do
    if Application.get_env(:portfolixir, :seed_starters_on_boot, true) do
      case seed() do
        {:ok, %{stored: [], counted: []}} ->
          :ok

        {:ok, report} ->
          Logger.info(
            "starter dashboards: stored #{inspect(report.stored)}, " <>
              "counted #{inspect(report.counted)}"
          )

        {:error, reason} ->
          Logger.warning("starter dashboards not seeded: #{inspect(reason)}")
      end
    end

    :ok
  rescue
    error ->
      Logger.warning("starter dashboards not seeded: #{Exception.message(error)}")
      :ok
  end
end
