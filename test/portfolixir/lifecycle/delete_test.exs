defmodule Portfolixir.Lifecycle.DeleteTest do
  # ADR-0050 §11 and §16 invariant 11 (risk-tier: audit, ADR-0036): the three
  # existing delete paths — a cash account, a depot, a security — hardened.
  # A row is deleted only when nothing references it; its memberships (bucket
  # links, position overrides, category assignments) are removed through their
  # journaled writers before it, never by a database cascade; the row is
  # locked FOR UPDATE before the check, and the delete declares every foreign
  # key onto its table, so a reference that appears after the check is a
  # refusal, never a crash.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Lifecycle.ForeignKeys
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.WorldFixtures

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp cash_account!(world, name) do
    {:ok, account} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    account
  end

  defp depot!(world, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        name: name
      })

    depot
  end

  defp tag_bucket!(name) do
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: name, dimension: "tag"})
    bucket
  end

  defp cash_transfer!(world, from, to, amount) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: from.id,
        counter_cash_account_id: to.id,
        type: "cash_transfer",
        date: ~D[2026-02-02],
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp security_transfer!(world, from, to, security, quantity) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: from.id,
        counter_securities_account_id: to.id,
        security_id: security.id,
        type: "security_transfer",
        date: ~D[2026-02-02],
        quantity: quantity,
        currency_code: "EUR"
      })

    tx
  end

  defp custom_category!(classification_name, category_name) do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: classification_name})

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: category_name
      })

    {classification, category}
  end

  defp entries(resource_type, fun) do
    [resource_type: resource_type]
    |> Journal.list_entries()
    |> Enum.filter(fun)
  end

  defp deleted_entries(resource_type, id) do
    entries(resource_type, &(&1.operation == :delete and &1.resource_id == to_string(id)))
  end

  describe "a referenced row is not deleted (§11)" do
    # User story:
    # As the operator (or the agent) tidying up accounts,
    # I want deleting a cash account that still carries history to be refused
    # with what references it, counted,
    # so that I know a merge, not a delete, is what I am after — and the
    # history is never lost.
    #
    # Acceptance criteria:
    # - A cash account referenced by a transaction through either leg, or by a
    #   depot linked to it, is not deleted.
    # - The answer counts the referencing transactions (each once, whichever
    #   leg references it) and the linked depots.
    # - Nothing is written: the account survives and no delete is journaled.
    test "a cash account referenced through either leg or by a depot answers what, counted" do
      world = WorldFixtures.base_world(cash_name: "Giro")
      spare = cash_account!(world, "Spare")

      WorldFixtures.deposit!(world, "100", ~D[2026-01-02])
      cash_transfer!(world, world.cash, spare, "40")

      assert Portfolios.delete_cash_account(agent(), world.cash) ==
               {:error, {:referenced, %{"transactions" => 2, "securities_accounts" => 1}}}

      # Referenced only as the transfer's counter leg.
      assert Portfolios.delete_cash_account(agent(), spare) ==
               {:error, {:referenced, %{"transactions" => 1}}}

      assert Portfolios.get_cash_account(world.cash.id)
      assert Portfolios.get_cash_account(spare.id)
      assert deleted_entries("cash_account", world.cash.id) == []
      assert deleted_entries("cash_account", spare.id) == []
    end

    # User story:
    # As the operator tidying up depots,
    # I want deleting a depot that still carries bookings to be refused with
    # what references it, counted,
    # so that two depots at one broker are merged, not one of them emptied.
    #
    # Acceptance criteria:
    # - A depot referenced by a transaction through either leg is not deleted.
    # - The answer counts the referencing transactions.
    test "a depot referenced through either leg answers what, counted" do
      world = WorldFixtures.base_world()
      second = depot!(world, "Second Depot")
      security = WorldFixtures.create_security!(name: "Transfer ETF", ticker: "TRF")

      WorldFixtures.buy!(world, security, quantity: "5")
      security_transfer!(world, world.depot, second, security, "2")

      assert Portfolios.delete_securities_account(agent(), world.depot) ==
               {:error, {:referenced, %{"transactions" => 2}}}

      # Referenced only as the transfer's counter leg.
      assert Portfolios.delete_securities_account(agent(), second) ==
               {:error, {:referenced, %{"transactions" => 1}}}

      assert Portfolios.get_securities_account(world.depot.id)
      assert Portfolios.get_securities_account(second.id)
      assert deleted_entries("securities_account", second.id) == []
    end

    # User story:
    # As the operator removing a duplicate security,
    # I want a refused delete to say what references the security, counted,
    # and whether merging it away could carry those references,
    # so that the remedy I am pointed at is one that can work.
    #
    # Acceptance criteria:
    # - Bookings, quotes and security events are counted per table.
    # - A merge carries all three, so the remedy is a merge.
    # - A research note can neither move nor vanish (ADR-0044 §3, ADR-0050 §9),
    #   so a security carrying one names retirement as its remedy instead.
    test "a security answers every reference, counted, and a remedy a merge could honour" do
      world = WorldFixtures.base_world()
      booked = WorldFixtures.create_security!(name: "Booked ETF", ticker: "BKD")

      WorldFixtures.buy!(world, booked)
      WorldFixtures.put_quotes!(booked, [{~D[2026-01-02], "100"}, {~D[2026-01-05], "101"}])

      {:ok, _event} =
        Events.create_event(Actor.owner_ui(), %{
          security_id: booked.id,
          kind: "earnings",
          date: ~D[2026-11-04],
          timing: "exact",
          source_quality: "primary"
        })

      booked_refs = %{"transactions" => 1, "security_quotes" => 2, "security_events" => 1}
      assert Catalog.delete_security(agent(), booked) == {:error, {:referenced, booked_refs}}
      assert Delete.remedy(booked, booked_refs) == :merge

      noted = WorldFixtures.create_security!(name: "Noted ETF", ticker: "NTD")

      {:ok, _note} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: noted.id,
          author: "agent",
          kind: "evidence",
          body: "a dated finding",
          source_quality: "primary",
          as_of: ~D[2026-08-01]
        })

      noted_refs = %{"security_notes" => 1}
      assert Catalog.delete_security(agent(), noted) == {:error, {:referenced, noted_refs}}
      assert Delete.remedy(noted, noted_refs) == :retire

      assert Catalog.get_security(booked.id)
      assert Catalog.get_security(noted.id)
      assert deleted_entries("security", booked.id) == []
    end

    test "an account or depot is always pointed at a merge" do
      world = WorldFixtures.base_world()

      assert Delete.remedy(world.cash, %{"transactions" => 1}) == :merge
      assert Delete.remedy(world.depot, %{"transactions" => 1}) == :merge
    end
  end

  describe "memberships are removed through their journaled writers (§11)" do
    # User story:
    # As the operator reading the audit journal after a delete,
    # I want every view membership the deleted account carried to leave its
    # own journal entry, written by the same writer that set it,
    # so that no bucket link vanishes behind the database's back (ADR-0017,
    # ADR-0024 point 4: view membership is retroactive).
    #
    # Acceptance criteria:
    # - The bucket links of a deleted cash account are removed with one
    #   aggregate cash_account_bucket_assignment entry, before the account's
    #   own delete entry, under the deleting actor.
    # - An account with no links leaves no such entry (a write that changes
    #   nothing is not journaled).
    # - The buckets themselves survive.
    test "a cash account's bucket links leave one aggregate entry, before the row's" do
      world = WorldFixtures.base_world()
      family = tag_bucket!("Family")
      guest = tag_bucket!("Guest")
      tagged = cash_account!(world, "Tagged")
      plain = cash_account!(world, "Plain")

      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), tagged, [family.id, guest.id])

      assert {:ok, _} = Portfolios.delete_cash_account(agent(), tagged)
      assert {:ok, _} = Portfolios.delete_cash_account(agent(), plain)

      assert Buckets.cash_account_bucket_ids(tagged.id) == []

      assert [removal] =
               entries(
                 "cash_account_bucket_assignment",
                 &(&1.after["cash_account_id"] == tagged.id)
               )
               |> Enum.filter(&(&1.actor_type == :api_token_rw))

      assert removal.after["bucket_ids"] == []
      assert [row_delete] = deleted_entries("cash_account", tagged.id)
      assert row_delete.actor_type == :api_token_rw
      assert removal.id < row_delete.id

      assert entries(
               "cash_account_bucket_assignment",
               &(&1.after["cash_account_id"] == plain.id)
             ) == []

      assert Buckets.get_bucket(family.id)
      assert Buckets.get_bucket(guest.id)
    end

    # User story:
    # As the operator deleting an empty depot,
    # I want its default buckets and every per-position override to be
    # removed journaled, one entry for the depot and one per position,
    # so that the journal shows which positions were viewed where.
    #
    # Acceptance criteria:
    # - One depot_bucket_assignment entry for the default set.
    # - One position_bucket_override delete per position, an explicit-empty
    #   override included.
    # - No override row survives.
    test "a depot's default buckets and overrides leave one entry per depot and per position" do
      world = WorldFixtures.base_world()
      family = tag_bucket!("Family")
      depot = depot!(world, "Spare Depot")
      alpha = WorldFixtures.create_security!(name: "Alpha ETF", ticker: "ALP")
      beta = WorldFixtures.create_security!(name: "Beta ETF", ticker: "BET")

      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [family.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, alpha, [family.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, beta, [])

      assert {:ok, _} = Portfolios.delete_securities_account(agent(), depot)

      assert [default_removal] =
               entries(
                 "depot_bucket_assignment",
                 &(&1.after["securities_account_id"] == depot.id and
                     &1.actor_type == :api_token_rw)
               )

      assert default_removal.after["bucket_ids"] == []

      override_removals =
        entries(
          "position_bucket_override",
          &(&1.operation == :delete and &1.after["securities_account_id"] == depot.id)
        )

      assert override_removals |> Enum.map(& &1.after["security_id"]) |> Enum.sort() ==
               Enum.sort([alpha.id, beta.id])

      assert Enum.all?(override_removals, &(&1.actor_type == :api_token_rw))
      assert Buckets.position_override(depot.id, alpha.id) == :inherit
      assert Buckets.position_override(depot.id, beta.id) == :inherit
      assert [_] = deleted_entries("securities_account", depot.id)
    end

    # User story:
    # As the operator deleting a security I created by mistake,
    # I want its category assignments and its position overrides to be removed
    # through their journaled writers,
    # so that a classification or a view never loses a member silently.
    #
    # Acceptance criteria:
    # - One security_category_assignment delete per assignment, with the
    #   assignment as its before-image.
    # - One position_bucket_override delete per depot the security was
    #   overridden in.
    # - Both land before the security's own delete entry.
    test "a security's category assignments and overrides are removed journaled" do
      world = WorldFixtures.base_world()
      family = tag_bucket!("Family")
      security = WorldFixtures.create_security!(name: "Mistake ETF", ticker: "MST")
      {strategy, core} = custom_category!("Strategy", "Core")
      {region, europe} = custom_category!("Region", "Europe")

      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, strategy.id, core.id)

      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, region.id, europe.id)

      :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, security, [family.id])

      assert {:ok, _} = Catalog.delete_security(agent(), security)

      assignment_removals =
        entries(
          "security_category_assignment",
          &(&1.operation == :delete and &1.before["security_id"] == security.id)
        )

      assert assignment_removals |> Enum.map(& &1.before["classification_id"]) |> Enum.sort() ==
               Enum.sort([strategy.id, region.id])

      assert [override_removal] =
               entries(
                 "position_bucket_override",
                 &(&1.operation == :delete and &1.after["security_id"] == security.id)
               )

      assert override_removal.after["securities_account_id"] == world.depot.id
      assert [row_delete] = deleted_entries("security", security.id)

      for entry <- [override_removal | assignment_removals] do
        assert entry.actor_type == :api_token_rw
        assert entry.id < row_delete.id
      end

      assert Classifications.get_assignment(security.id, strategy.id) == nil
      assert Buckets.position_override(world.depot.id, security.id) == :inherit
    end
  end

  describe "no cascade removes a membership (§16 invariant 11)" do
    # User story:
    # As the maintainer of the audit trail,
    # I want the database itself to refuse deleting an account, a depot or a
    # security that still carries a membership,
    # so that a future delete path that forgets the journaled removal fails
    # loudly instead of losing the membership silently.
    #
    # Acceptance criteria:
    # - A raw delete (journal actor set, so the guard is not what refuses it)
    #   of a row that still has a bucket link, an override or a category
    #   assignment is refused with the membership's foreign key.
    test "a raw delete of a row that still carries a membership is refused by the database" do
      world = WorldFixtures.base_world()
      family = tag_bucket!("Family")
      tagged = cash_account!(world, "Tagged")
      depot = depot!(world, "Overridden Depot")
      overridden = WorldFixtures.create_security!(name: "Override ETF", ticker: "OVR")
      security = WorldFixtures.create_security!(name: "Member ETF", ticker: "MBR")
      {strategy, core} = custom_category!("Strategy", "Core")

      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), tagged, [family.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, overridden, [family.id])

      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, strategy.id, core.id)

      for {table, id, constraint} <- [
            {"cash_accounts", tagged.id, "cash_account_buckets_cash_account_id_fkey"},
            {"securities_accounts", depot.id,
             "position_bucket_overrides_securities_account_id_fkey"},
            {"securities", security.id, "security_category_assignments_security_id_fkey"}
          ] do
        error =
          assert_raise Postgrex.Error, fn ->
            Repo.transaction(fn ->
              Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
              Repo.query!("DELETE FROM #{table} WHERE id = $1", [id])
            end)
          end

        assert %{postgres: %{code: :foreign_key_violation, constraint: ^constraint}} = error
      end

      assert Buckets.cash_account_bucket_ids(tagged.id) == [family.id]
      assert Classifications.get_assignment(security.id, strategy.id)
    end
  end

  describe "a race answers a refusal, never a crash (§11)" do
    # User story:
    # As the agent deleting an account while the operator books onto it,
    # I want a reference that appears after the check to refuse the delete
    # the way the check would have,
    # so that the race ends in a 409, never a 500, and nothing is half-done.
    #
    # Acceptance criteria:
    # - The removal step, reached with a reference the check did not see (it
    #   is called here directly, past the check), answers the referenced
    #   refusal with the references counted.
    # - The membership removals it had already made are rolled back with it,
    #   and nothing of it is journaled.
    test "a reference the check did not see is refused by a declared constraint" do
      world = WorldFixtures.base_world()
      family = tag_bucket!("Family")
      raced = cash_account!(world, "Raced")
      raced_depot = depot!(world, "Raced Depot")
      security = WorldFixtures.create_security!(name: "Raced ETF", ticker: "RCD")

      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), raced, [family.id])
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), raced_depot, [family.id])

      {:ok, _} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: raced.id,
          type: "deposit",
          date: ~D[2026-03-02],
          gross_amount: "10",
          currency_code: "EUR"
        })

      WorldFixtures.buy!(%{world | depot: raced_depot}, security)
      WorldFixtures.put_quote!(security, ~D[2026-03-02], "12")

      assert Delete.remove(agent(), raced) == {:error, {:referenced, %{"transactions" => 1}}}

      assert Delete.remove(agent(), raced_depot) ==
               {:error, {:referenced, %{"transactions" => 1}}}

      assert Delete.remove(agent(), security) ==
               {:error, {:referenced, %{"transactions" => 1, "security_quotes" => 1}}}

      assert Portfolios.get_cash_account(raced.id)
      assert Portfolios.get_securities_account(raced_depot.id)
      assert Catalog.get_security(security.id)
      assert Buckets.cash_account_bucket_ids(raced.id) == [family.id]
      assert Buckets.depot_default_bucket_ids(raced_depot.id) == [family.id]

      assert entries("cash_account_bucket_assignment", &(&1.actor_type == :api_token_rw)) == []
      assert entries("depot_bucket_assignment", &(&1.actor_type == :api_token_rw)) == []
    end

    # User story:
    # As the maintainer of the delete path,
    # I want the row locked FOR UPDATE before the reference check,
    # so that a booking onto it waits for the delete instead of slipping in
    # between the check and the delete.
    #
    # Acceptance criteria:
    # - Each of the three deletes reads its row FOR UPDATE before it deletes.
    test "each delete locks its row FOR UPDATE before it deletes it" do
      world = WorldFixtures.base_world()
      spare = cash_account!(world, "Lock Cash")
      depot = depot!(world, "Lock Depot")
      security = WorldFixtures.create_security!(name: "Lock ETF", ticker: "LCK")

      queries =
        capture_queries(fn ->
          assert {:ok, _} = Portfolios.delete_cash_account(agent(), spare)
          assert {:ok, _} = Portfolios.delete_securities_account(agent(), depot)
          assert {:ok, _} = Catalog.delete_security(agent(), security)
        end)

      for table <- ~w(cash_accounts securities_accounts securities) do
        lock = Enum.find_index(queries, &(&1 =~ ~r/FROM "#{table}".*FOR UPDATE/s))
        delete = Enum.find_index(queries, &(&1 =~ ~r/^DELETE FROM "#{table}"/))

        assert lock, "no FOR UPDATE read of #{table}"
        assert delete, "no delete of #{table}"
        assert lock < delete
      end
    end

    # User story:
    # As the operator deleting a security while an agent edits its
    # classification, targets or aliases,
    # I want the delete to hold the rows it removes before it removes them,
    # so that a concurrent removal of one of them waits instead of turning
    # the delete into a crash (a stale per-row delete).
    #
    # Acceptance criteria:
    # - Each membership table a security delete removes rows from per row
    #   (category assignments, position targets, identifier aliases) is read
    #   FOR UPDATE before its first row is deleted.
    test "each per-row membership is locked FOR UPDATE before it is removed" do
      world = WorldFixtures.base_world()

      security =
        WorldFixtures.create_security!(name: "Race ETF", ticker: "RCE", isin: "XS0000000011")

      {strategy, core} = custom_category!("Strategy", "Core")

      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, strategy.id, core.id)

      {:ok, _} =
        Targets.set_targets(
          Actor.owner_ui(),
          world.portfolio.id,
          strategy.id,
          [
            %{category_id: core.id, target_weight: "0.3"},
            %{category_id: core.id, security_id: security.id, target_weight: "0.1"}
          ]
        )

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "XS0000000029")

      queries =
        capture_queries(fn -> assert {:ok, _} = Catalog.delete_security(agent(), security) end)

      for table <- ~w(security_category_assignments portfolio_targets security_identifier_aliases) do
        lock = Enum.find_index(queries, &(&1 =~ ~r/FROM "#{table}".*FOR UPDATE/s))
        delete = Enum.find_index(queries, &(&1 =~ ~r/^DELETE FROM "#{table}"/))

        assert delete, "no row of #{table} was deleted"
        assert lock, "no FOR UPDATE read of #{table}"
        assert lock < delete
      end
    end

    # User story:
    # As the agent deleting a row the operator deleted a moment earlier,
    # I want the answer to be "it is gone", not a crash.
    #
    # Acceptance criteria:
    # - A delete of a row that has vanished answers :not_found and journals
    #   nothing.
    test "a row that has vanished answers not found" do
      world = WorldFixtures.base_world()
      spare = cash_account!(world, "Gone Cash")
      depot = depot!(world, "Gone Depot")
      security = WorldFixtures.create_security!(name: "Gone ETF", ticker: "GON")

      assert {:ok, _} = Portfolios.delete_cash_account(agent(), spare)
      assert {:ok, _} = Portfolios.delete_securities_account(agent(), depot)
      assert {:ok, _} = Catalog.delete_security(agent(), security)

      assert Portfolios.delete_cash_account(agent(), spare) == {:error, :not_found}
      assert Portfolios.delete_securities_account(agent(), depot) == {:error, :not_found}
      assert Catalog.delete_security(agent(), security) == {:error, :not_found}

      assert [_] = deleted_entries("cash_account", spare.id)
      assert [_] = deleted_entries("securities_account", depot.id)
      assert [_] = deleted_entries("security", security.id)
    end
  end

  describe "the delete path follows the disposition map (§14)" do
    # The removal writers and the declared constraints are read from
    # Portfolixir.Lifecycle.ForeignKeys, so a foreign key added to the map is
    # covered by the delete path, or this fails naming it.
    test "every :remove_journaled foreign key has a journaled remover" do
      declared =
        for %{delete: :remove_journaled, constraint: name} <- ForeignKeys.dispositions(),
            do: name

      assert Enum.sort(Delete.removers()) == Enum.sort(declared)
    end

    test "each delete declares every foreign key onto its table" do
      world = WorldFixtures.base_world()
      security = WorldFixtures.create_security!(name: "Declared ETF", ticker: "DCL")

      for {record, table} <- [
            {world.cash, "cash_accounts"},
            {world.depot, "securities_accounts"},
            {security, "securities"}
          ] do
        expected =
          for %{references: ^table, constraint: name} <- ForeignKeys.dispositions(), do: name

        declared =
          record
          |> Delete.delete_changeset()
          |> Map.fetch!(:constraints)
          |> Enum.map(& &1.constraint)

        assert Enum.sort(declared) == Enum.sort(expected), "#{table}"
      end
    end
  end

  defp capture_queries(fun) do
    test_pid = self()
    handler = "lifecycle-delete-lock-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid, do: send(test_pid, {:query, query})
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(acc) do
    receive do
      {:query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
