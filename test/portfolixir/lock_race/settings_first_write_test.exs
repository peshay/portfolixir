defmodule Portfolixir.LockRace.SettingsFirstWriteTest do
  # The journaled setting writes besides the crash benchmark (#1356, Sprint
  # 29's edge/order lens on #1458): the default view and the news
  # clustering's two settings, raced on two real connections by the
  # lock-order harness (#996). With no setting stored, the prior read's FOR
  # UPDATE locks no row, so two first writes both read "none", the later one
  # replaces the first's value and its journal entry still says there was
  # nothing before. Each write now takes the transaction advisory lock on
  # the setting's key that `set_crash_benchmark` took in Sprint 29, before
  # the prior read, so the second waits for the first's commit and its
  # entry's before is the first's after.
  #
  # `Portfolixir.LockTable` row 27 registers the lock: one key per setting,
  # taken before any row lock.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and figure is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.LockRace
  alias Portfolixir.Repo
  alias Portfolixir.Settings

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp entries(key) do
    Journal.list_entries(resource_type: "setting")
    |> Enum.filter(&(&1.after["key"] == key))
  end

  defp assert_chained(key, first_value, second_value) do
    [later, earlier] = entries(key)

    assert earlier.before == nil
    assert earlier.after["value"] == first_value
    assert later.before["value"] == first_value
    assert later.after["value"] == second_value
  end

  # User story (#1356; ADR-0054 §3, every write journaled):
  # As the operator reading the journal,
  # I want two writes of the default view or of a news clustering setting,
  # even the first two at once, to chain: the later one's before is the
  # earlier one's after,
  # so that the journal never claims a value replaced nothing.
  #
  # Acceptance criteria:
  # - With no setting stored, a second writer waits for the first, for the
  #   default view and for both news settings.
  # - The stored value is the second's; the second's entry names the
  #   first's value as its before.
  test "two first default-view writes wait for each other and chain in the journal",
       %{db: db} do
    {:ok, :ok} =
      LockRace.race!(
        db,
        {fn -> Settings.set_default_view(Actor.owner_ui(), 11) end,
         LockRace.query?("FOR UPDATE")},
        fn -> Settings.set_default_view(Actor.api_token_rw("mcp"), 12) end
      )

    assert_chained("default_view_id", "11", "12")
  end

  test "two first writes of each news setting wait for each other and chain in the journal",
       %{db: db} do
    {:ok, :ok} =
      LockRace.race!(
        db,
        {fn -> Settings.set_news_cluster_window_hours(Actor.owner_ui(), 24) end,
         LockRace.query?("FOR UPDATE")},
        fn -> Settings.set_news_cluster_window_hours(Actor.api_token_rw("mcp"), 48) end
      )

    assert Settings.news_cluster_window_hours() == 48
    assert_chained("news_cluster_window_hours", "24", "48")

    {:ok, :ok} =
      LockRace.race!(
        db,
        {fn -> Settings.set_news_cluster_similarity(Actor.owner_ui(), Decimal.new("0.5")) end,
         LockRace.query?("FOR UPDATE")},
        fn ->
          Settings.set_news_cluster_similarity(Actor.api_token_rw("mcp"), Decimal.new("0.75"))
        end
      )

    assert_chained("news_cluster_similarity", "0.5", "0.75")
  end
end
