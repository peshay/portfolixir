defmodule Portfolixir.LockRace.CrashBenchmarkTest do
  # The crash benchmark's write (ADR-0058 §1; Sprint 29, the closing act of
  # #1421), raced on two real connections by the lock-order harness (#996).
  # Two first choices of the crash benchmark, with no setting stored yet:
  # the prior read's FOR UPDATE then locks no row, so both writers read
  # "none", the later one replaces the first's value and its journal entry
  # still says there was nothing before. The write now takes a transaction
  # advisory lock on the setting's key before the prior read, so the second
  # waits for the first's commit and its entry's before is the first's
  # after.
  #
  # The lock meets no row of `Portfolixir.LockTable`: it is one key per
  # setting, taken by this write alone, before any row lock.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and figure is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
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

  defp index!(name, ticker) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "etf",
        ticker_symbol: ticker
      })

    {:ok, _count} =
      Quotes.upsert_many(security.id, [%{date: ~D[2020-02-19], close: "100", source: "manual"}])

    security
  end

  # User story (ADR-0058 §1; ADR-0054 §3, every write journaled):
  # As the operator reading the journal,
  # I want two writes of the crash benchmark, even the first two at once,
  # to chain: the later one's before is the earlier one's after,
  # so that the journal never claims a value replaced nothing.
  #
  # Acceptance criteria:
  # - With no setting stored, a second writer waits for the first.
  # - The stored value is the second's; the second's entry names the
  #   first's value as its before.
  test "two first crash-benchmark writes wait for each other and chain in the journal",
       %{db: db} do
    first_index = index!("Synthetic Race Index A", "SRA")
    second_index = index!("Synthetic Race Index B", "SRB")

    {{:ok, _first}, {:ok, _second}} =
      LockRace.race!(
        db,
        {fn -> Settings.set_crash_benchmark(Actor.owner_ui(), first_index.id) end,
         LockRace.query?("FOR UPDATE")},
        fn -> Settings.set_crash_benchmark(Actor.api_token_rw("mcp"), second_index.id) end
      )

    assert Settings.crash_benchmark_security_id() == second_index.id

    [later, earlier] =
      Journal.list_entries(resource_type: "setting")
      |> Enum.filter(&(&1.after["key"] == "crash_benchmark_security_id"))

    assert earlier.before == nil
    assert earlier.after["value"] == Integer.to_string(first_index.id)
    assert later.before["value"] == Integer.to_string(first_index.id)
    assert later.after["value"] == Integer.to_string(second_index.id)
  end
end
