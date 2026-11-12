defmodule Portfolixir.LockRace.ChainReadTest do
  # ADR-0059 §5, §6, §10 (Sprint 29, H3; the closing act's order lens on Lane
  # H): two runs of the chain reader racing (a scheduled run and an
  # on-demand refresh), and a rebinding during a run, on two real
  # connections by the lock-order harness (#996). A deadlock, a writer that
  # never waits and a writer that raises each fail the race. The lock is
  # row 24 of `Portfolixir.LockTable`.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits; the scratch database keeps each case's rows, so every assertion
  # is about the case's own security. The readings are canned (no request is made: the writers run
  # outside the test's stubs), from the synthetic chain of
  # Portfolixir.EsploraFixtures; every name is synthetic.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Chains.Reader
  alias Portfolixir.EsploraFixtures
  alias Portfolixir.Journal.Entry, as: JournalEntry
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.LockRace
  alias Portfolixir.Repo

  @moduletag :lock_race

  @tip 870_000

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp security!(chain) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Coin #{System.unique_integer([:positive])}",
        currency_code: "USD",
        asset_class: "crypto"
      })

    {:ok, bound} = Catalog.update_security(agent(), security, %{halving_chain: chain})
    bound
  end

  # A reading as the adapter hands it on, for the heights the run asks.
  defp canned(heights_for, _opts) do
    heights = heights_for.(@tip)

    {:ok,
     %{
       source: :mempool,
       host: "mempool.space",
       base: "https://mempool.space/api",
       tip: @tip,
       blocks:
         Map.new(heights, fn height ->
           {height,
            %{
              height: height,
              hash: EsploraFixtures.hash(height),
              timestamp: EsploraFixtures.timestamp(height)
            }}
         end),
       genesis_checked: true,
       attempts: []
     }}
  end

  defp run, do: Reader.run(:bitcoin, read: &canned/2, now: ~U[2026-11-12 12:00:00Z])

  defp halving_entries(security) do
    Repo.all(
      from(e in JournalEntry,
        where: e.resource_type == "security_event" and e.actor_label == "chain_read",
        where: fragment("(?->>'security_id')::bigint", e.after) == ^security.id,
        select: e.id
      )
    )
  end

  defp chain_lock?(%{query: query}) when is_binary(query), do: query =~ "chain read"
  defp chain_lock?(_metadata), do: false

  defp security_share?(%{query: query}) when is_binary(query),
    do: query =~ ~s(FROM "securities") and query =~ "FOR SHARE"

  defp security_share?(_metadata), do: false

  # User story (ADR-0059 §10, the order lens: "two runs racing"):
  # As the operator who presses „Jetzt lesen“ while the scheduled run is
  # going,
  # I want the two runs to write each halving once,
  # so that the journal and the events hold no double.
  #
  # Acceptance criteria:
  # - The second run waits at the chain's lock until the first commits.
  # - It then finds the halvings confirmed and the day's estimate written,
  #   and writes nothing: five journal entries for the security, not ten.
  test "two runs racing write each halving once", %{db: db} do
    security = security!(:bitcoin)

    {first, second} = LockRace.race!(db, {&run/0, &chain_lock?/1}, &run/0)

    assert {:ok, %{host: "mempool.space"}} = first
    assert {:ok, %{host: "mempool.space"}} = second
    assert Events.count_halvings(security.id) == 5
    assert length(halving_entries(security)) == 5
  end

  # User story (ADR-0059 §4, the order lens: "a rebinding during a run"):
  # As the operator who unbinds a security while the chain is being read,
  # I want the unbinding to leave the security without halvings whichever
  # write commits first,
  # so that no halving survives on a security no longer bound to the chain.
  #
  # Acceptance criteria:
  # - A run holding the bound security: the unbinding waits, then deletes
  #   the halvings the run wrote, and counts them.
  # - An unbinding holding the security: the run waits, then leaves the
  #   security out and writes nothing for it.
  describe "a rebinding during a run" do
    test "a run holding the security: the unbinding waits, then deletes its halvings",
         %{db: db} do
      security = security!(:bitcoin)

      {ran, unbound} =
        LockRace.race!(
          db,
          {&run/0, &security_share?/1},
          fn ->
            Catalog.update_security(agent(), security, %{halving_chain: nil}, report: true)
          end
        )

      assert {:ok, %{host: "mempool.space"}} = ran
      assert {:ok, %{halving_chain: nil}, %{halving_events_deleted: 5}} = unbound
      assert Events.count_halvings(security.id) == 0
    end

    test "an unbinding holding the security: the run waits, then writes nothing for it",
         %{db: db} do
      security = security!(:bitcoin)

      {unbound, ran} =
        LockRace.race!(
          db,
          {fn ->
             Catalog.update_security(agent(), security, %{halving_chain: nil}, report: true)
           end, &LockRace.lock?/1},
          &run/0
        )

      assert {:ok, %{halving_chain: nil}, %{halving_events_deleted: 0}} = unbound
      assert {:ok, %{host: "mempool.space"}} = ran
      assert Events.count_halvings(security.id) == 0
      assert halving_entries(security) == []
    end
  end
end
