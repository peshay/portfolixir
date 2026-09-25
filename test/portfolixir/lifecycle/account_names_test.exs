defmodule Portfolixir.Lifecycle.AccountNamesTest do
  # ADR-0050 §4 (L2, #884; risk-tier: import idempotency, ADR-0036): the
  # identity of a cash account or a depot by name. One resolution (exact live
  # name, then former name, an ambiguous tier resolving to nothing), one name
  # guard on every writer under one advisory lock, and the writers of former
  # names: the rename rule, the remembered remap and the removal. The importer
  # half is pinned in test/portfolixir/imports/former_names_reimport_test.exs.
  # The accounts and every name are synthetic.
  use Portfolixir.DataCase, async: true

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Household",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  describe "the rename rule (§4, writers of former names)" do
    # User story:
    # As the operator renaming an imported cash account or depot,
    # I want the old name remembered on the renamed account,
    # so that an import that still names it books there instead of on a new
    # account under the old name.
    #
    # Acceptance criteria:
    # - A rename appends the previous name to former_names, journaled with its
    #   before and after in the rename's own journal entry.
    # - Renaming back to a former name consumes it.
    # - The same holds for a depot.
    test "a rename keeps the previous name; renaming back consumes it", %{portfolio: portfolio} do
      giro = cash!(portfolio, "Giro")

      {:ok, main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})
      assert main.former_names == ["Giro"]

      [entry | _] = Journal.list_entries(resource_type: "cash_account", resource_id: "#{giro.id}")
      assert entry.operation == :update
      assert entry.before["name"] == "Giro"
      assert entry.after["name"] == "Main account"
      assert entry.after["former_names"] == ["Giro"]

      {:ok, household} = Portfolios.update_cash_account(agent(), main, %{name: "Household"})
      assert household.former_names == ["Giro", "Main account"]

      {:ok, back} = Portfolios.update_cash_account(agent(), household, %{name: "Giro"})
      assert back.former_names == ["Main account", "Household"]

      depot = depot!(portfolio, "Depot", giro)
      {:ok, depot} = Portfolios.update_securities_account(agent(), depot, %{name: "Broker depot"})
      assert depot.former_names == ["Depot"]

      {:ok, depot} = Portfolios.update_securities_account(agent(), depot, %{notes: "one broker"})
      assert depot.former_names == ["Depot"]
    end

    # User story:
    # As the operator with two accounts of one name from before the guard,
    # I want renaming one of them to leave the name with the other,
    # so that the rename ends the ambiguity instead of moving it.
    #
    # Acceptance criteria:
    # - The previous name is not recorded while another account of the kind
    #   in the portfolio still carries it as its live name.
    test "a previous name another live account carries is not kept", %{portfolio: portfolio} do
      a = legacy_cash!(portfolio, "Giro")
      b = legacy_cash!(portfolio, "Giro")

      {:ok, renamed} = Portfolios.update_cash_account(agent(), a, %{name: "Main account"})
      assert renamed.former_names == []
      assert reload(b).name == "Giro"
    end
  end

  describe "the name guard (§4)" do
    # User story:
    # As the operator whose imports route by name,
    # I want no writer to give an account a name that already routes an
    # import elsewhere,
    # so that a new account can never re-route an old export and double its
    # history.
    #
    # Acceptance criteria:
    # - A create whose name is another account's live name, or a former name,
    #   of the same kind in the portfolio answers a field error on name and
    #   writes nothing.
    # - A rename to another account's live or former name answers the same.
    # - Another portfolio and the other kind are not checked against.
    test "a new live name may equal neither a live nor a former name of the kind", %{
      portfolio: portfolio
    } do
      giro = cash!(portfolio, "Giro")
      savings = cash!(portfolio, "Savings")

      assert {:error, changeset} = create_cash(portfolio, "Giro")

      assert %{name: ["is already the name of cash account ##{giro.id} in this portfolio"]} ==
               errors_on(changeset)

      {:ok, main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})

      assert {:error, changeset} = create_cash(portfolio, "Giro")

      assert %{name: [message]} = errors_on(changeset)
      assert message =~ "is a former name of cash account ##{main.id} (\"Main account\")"
      assert message =~ "an import naming it books there"

      assert {:error, changeset} =
               Portfolios.update_cash_account(agent(), savings, %{name: "Giro"})

      assert %{name: [_former]} = errors_on(changeset)

      assert {:error, changeset} =
               Portfolios.update_cash_account(agent(), savings, %{name: "Main account"})

      assert %{name: ["is already the name of cash account #" <> _]} = errors_on(changeset)

      assert reload(savings).name == "Savings"
      assert Portfolios.count_cash_accounts() == 2

      # Taking back its own former name is a rename back, not a conflict.
      assert {:ok, %{name: "Giro", former_names: ["Main account"]}} =
               Portfolios.update_cash_account(agent(), main, %{name: "Giro"})

      # The other kind and another portfolio are other scopes.
      assert {:ok, _depot} = create_depot(portfolio, "Savings", savings)

      {:ok, other} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Other", base_currency_code: "EUR"})

      assert {:ok, _cash} = create_cash(other, "Savings")
    end

    test "the guard holds for depots too", %{portfolio: portfolio} do
      cash = cash!(portfolio, "Giro")
      depot = depot!(portfolio, "Depot", cash)
      other = depot!(portfolio, "Second depot", cash)

      assert {:error, changeset} = create_depot(portfolio, "Depot", cash)

      assert %{name: ["is already the name of securities account ##{depot.id} in this portfolio"]} ==
               errors_on(changeset)

      {:ok, _renamed} = Portfolios.update_securities_account(agent(), depot, %{name: "Broker"})

      assert {:error, changeset} =
               Portfolios.update_securities_account(agent(), other, %{name: "Depot"})

      assert %{name: [message]} = errors_on(changeset)
      assert message =~ "is a former name of securities account ##{depot.id} (\"Broker\")"
    end

    # User story:
    # As the maintainer moving an unreferenced account to another portfolio,
    # I want its live and former names held against that portfolio's
    # accounts,
    # so that a move cannot carry a name into a portfolio where it already
    # routes an import elsewhere.
    #
    # Acceptance criteria:
    # - A live name another account of the kind carries there refuses on name.
    # - A former name another account carries there, live or former, refuses
    #   on former_names.
    test "a move to another portfolio is held against that portfolio's names", %{
      portfolio: portfolio
    } do
      {:ok, other} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Other", base_currency_code: "EUR"})

      _there = cash!(other, "Giro")
      _also_there = cash!(other, "Savings")

      mover = cash!(portfolio, "Savings")

      assert {:error, changeset} =
               Portfolios.update_cash_account(agent(), mover, %{portfolio_id: other.id})

      assert %{name: ["is already the name of cash account #" <> _]} = errors_on(changeset)

      giro = cash!(portfolio, "Giro")
      {:ok, renamed} = Portfolios.update_cash_account(agent(), giro, %{name: "Household"})

      assert {:error, changeset} =
               Portfolios.update_cash_account(agent(), renamed, %{portfolio_id: other.id})

      assert %{former_names: [message]} = errors_on(changeset)
      assert message =~ ~s(include "Giro", the name of cash account #)
    end

    # User story:
    # As the operator with duplicate names from before the guard,
    # I want those accounts to stay editable,
    # so that the guard refuses new duplicates without locking old ones.
    #
    # Acceptance criteria:
    # - An update that leaves the name alone is not checked.
    test "an existing duplicate is not migrated, and stays editable", %{portfolio: portfolio} do
      a = legacy_cash!(portfolio, "Giro")
      _b = legacy_cash!(portfolio, "Giro")

      assert {:ok, %{notes: "kept"}} =
               Portfolios.update_cash_account(agent(), a, %{notes: "kept"})
    end

    test "the guard runs under the portfolio's account-identity advisory lock", %{
      portfolio: portfolio
    } do
      Repo.transaction(fn ->
        {:ok, _cash} = create_cash(portfolio, "Giro")

        # pg_advisory_xact_lock(int, int) shows as classid, objid, objsubid 2.
        assert Repo.one(
                 from(l in "pg_locks",
                   where:
                     l.locktype == "advisory" and l.pid == fragment("pg_backend_pid()") and
                       fragment("?::bigint", l.classid) == ^AccountNames.lock_key() and
                       fragment("?::bigint", l.objid) ==
                         ^AccountNames.lock_portfolio_key(portfolio.id) and
                       l.objsubid == 2,
                   select: count()
                 )
               ) == 1
      end)
    end
  end

  describe "resolution: exact live name, then former name (§4)" do
    # User story:
    # As the importer resolving a Portfolio Performance account name,
    # I want one resolution for the preview's prefill and the apply,
    # so that the two never disagree, and an ambiguous name resolves to
    # nothing instead of the last account read.
    #
    # Acceptance criteria:
    # - An exact live name resolves to its account (tier live), then a former
    #   name (tier former), otherwise to none.
    # - Two live accounts of one name resolve ambiguous, naming both.
    # - The resolution is scoped to the kind and the portfolio.
    test "live first, then former, and an ambiguous tier resolves to nothing", %{
      portfolio: portfolio
    } do
      giro = cash!(portfolio, "Giro")
      {:ok, main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})
      a = legacy_cash!(portfolio, "Shared")
      b = legacy_cash!(portfolio, "Shared")
      depot = depot!(portfolio, "Depot", main)

      index = AccountNames.index(CashAccount, portfolio.id)

      assert AccountNames.resolve(index, "Main account") == {:ok, main.id, :live}
      assert AccountNames.resolve(index, "Giro") == {:ok, main.id, :former}
      assert AccountNames.resolve(index, "Unknown") == :none
      assert AccountNames.resolve(index, "Shared") == {:ambiguous, :live, Enum.sort([a.id, b.id])}
      assert AccountNames.resolve(index, "Depot") == :none

      depots = AccountNames.index(SecuritiesAccount, portfolio.id)
      assert AccountNames.resolve(depots, "Depot") == {:ok, depot.id, :live}
      assert AccountNames.resolve(depots, "Giro") == :none

      assert AccountNames.resolve(AccountNames.index(CashAccount, nil), "Giro") == :none
    end
  end

  describe "the remembered remap (§4)" do
    # User story:
    # As the operator mapping a Portfolio Performance name onto an account of
    # another name in the import preview,
    # I want the mapping remembered as a former name of that account,
    # so that the next import resolves the name by itself.
    #
    # Acceptance criteria:
    # - The name is appended to the account's former names, journaled under
    #   the importing actor.
    # - A name the account already carries, live or former, writes nothing.
    # - A former name of another account moves: removed there, appended here,
    #   each journaled; the outcome names the account it left.
    # - A live name of another account is not remembered and writes nothing;
    #   the outcome names that account.
    test "appends, moves, or is not offered", %{portfolio: portfolio} do
      import_actor = Actor.import_session()
      broker = cash!(portfolio, "Broker USD")
      giro = cash!(portfolio, "Giro")
      {:ok, main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})
      household = cash!(portfolio, "Household")

      assert AccountNames.remember_outcome(CashAccount, broker.id, "Cash USD") == :append

      assert {:ok, :appended} =
               AccountNames.remember(import_actor, CashAccount, broker.id, "Cash USD")

      assert reload(broker).former_names == ["Cash USD"]

      [entry | _] =
        Journal.list_entries(resource_type: "cash_account", resource_id: "#{broker.id}")

      assert entry.actor_type == :import_session
      assert entry.after["former_names"] == ["Cash USD"]

      assert {:ok, :already} =
               AccountNames.remember(import_actor, CashAccount, broker.id, "Cash USD")

      assert {:ok, :same_name} =
               AccountNames.remember(import_actor, CashAccount, broker.id, "Broker USD")

      assert AccountNames.remember_outcome(CashAccount, household.id, "Giro") == {:move, main.id}

      assert {:ok, {:moved, from}} =
               AccountNames.remember(import_actor, CashAccount, household.id, "Giro")

      assert from == main.id
      assert reload(main).former_names == []
      assert reload(household).former_names == ["Giro"]

      assert AccountNames.remember_outcome(CashAccount, household.id, "Broker USD") ==
               {:not_offered, broker.id}

      before = journal_count()

      assert {:ok, {:not_offered, holder}} =
               AccountNames.remember(import_actor, CashAccount, household.id, "Broker USD")

      assert holder == broker.id
      assert reload(household).former_names == ["Giro"]
      assert journal_count() == before
    end
  end

  describe "removing a former name (§4)" do
    # User story:
    # As the operator who no longer wants an old name routed to an account,
    # I want to remove it from the account's former names,
    # so that an import naming it creates a new account again.
    #
    # Acceptance criteria:
    # - The name leaves former_names, journaled with before and after.
    # - A name the account does not carry answers :not_a_former_name.
    test "removes one former name, journaled", %{portfolio: portfolio} do
      giro = cash!(portfolio, "Giro")
      {:ok, main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})

      assert {:ok, %CashAccount{former_names: []}} =
               Portfolios.remove_cash_account_former_name(agent(), main, "Giro")

      [entry | _] = Journal.list_entries(resource_type: "cash_account", resource_id: "#{main.id}")
      assert entry.before["former_names"] == ["Giro"]
      assert entry.after["former_names"] == []
      assert entry.actor_type == :api_token_rw

      assert {:error, :not_a_former_name} =
               Portfolios.remove_cash_account_former_name(agent(), main, "Giro")

      depot = depot!(portfolio, "Depot", main)
      {:ok, depot} = Portfolios.update_securities_account(agent(), depot, %{name: "Broker"})

      assert {:ok, %SecuritiesAccount{former_names: []}} =
               Portfolios.remove_securities_account_former_name(agent(), depot, "Depot")
    end
  end

  # --- helpers -------------------------------------------------------------

  defp create_cash(portfolio, name) do
    Portfolios.create_cash_account(agent(), %{
      portfolio_id: portfolio.id,
      name: name,
      currency_code: "EUR"
    })
  end

  defp cash!(portfolio, name) do
    {:ok, cash} = create_cash(portfolio, name)
    cash
  end

  defp create_depot(portfolio, name, cash) do
    Portfolios.create_securities_account(agent(), %{
      portfolio_id: portfolio.id,
      cash_account_id: cash.id,
      name: name
    })
  end

  defp depot!(portfolio, name, cash) do
    {:ok, depot} = create_depot(portfolio, name, cash)
    depot
  end

  # A duplicate name from before the guard: inserted the way the old writer
  # did, journaled, without the changeset's guard.
  defp legacy_cash!(portfolio, name) do
    {:ok, %{account: account}} =
      Multi.new()
      |> Multi.insert(
        :account,
        Ecto.Changeset.change(%CashAccount{}, %{
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        })
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "cash_account",
        operation: :create,
        source: :account
      )
      |> Repo.transaction()

    account
  end

  defp reload(%schema{id: id}), do: Repo.get!(schema, id)

  defp journal_count, do: Repo.aggregate(Portfolixir.Journal.Entry, :count, :id)
end
