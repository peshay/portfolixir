defmodule Portfolixir.Imports.FormerNamesReimportTest do
  # ADR-0050 §4 and §10 third bullet, the second half of the re-import
  # contract (L2, #884; risk-tier: import idempotency, ADR-0036): accounts
  # resolve by exact live name, then by former name, through one function the
  # preview's prefill and the apply share; an ambiguous name fails closed; a
  # remap in the preview is remembered from the mapping at apply start; and a
  # mapping that names an account merged away since aborts before anything is
  # written. §16 invariants pinned here: the drifted-rename half of 1 and 5,
  # and the former-name case of 6.
  #
  # The exports are synthetic Portfolio Performance JSON; every name, amount
  # and identifier is invented.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.FormerNamesBackfill
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  describe "a drifted re-import after a rename creates nothing (§16 inv 1 and 5, the rename half)" do
    # User story:
    # As the operator whose agent renamed an imported cash account and depot,
    # I want the next import of a re-export that changed inside Portfolio
    # Performance to find the renamed accounts by their former names,
    # so that the rename never books the history a second time.
    #
    # Acceptance criteria:
    # - After "Giro" is renamed "Main account" and "Depot" "Broker depot", the
    #   preview resolves both old names to the renamed rows, tier former.
    # - Applying a drifted export (other decimal precision, so no content
    #   hash matches) with that prefill, or without any mapping, creates zero
    #   transactions, cash accounts, depots and securities; every row is
    #   reported with the layer that caught it.
    test "the old names resolve to the renamed rows, and nothing is created", %{
      portfolio: portfolio
    } do
      assert {:ok, %Result{created_transactions: 3}} =
               Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})

      giro = named!(CashAccount, "Giro")
      depot = named!(SecuritiesAccount, "Depot")
      {:ok, main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})

      {:ok, broker} =
        Portfolios.update_securities_account(agent(), depot, %{name: "Broker depot"})

      drifted = parse!(household(:drifted))

      assert Imports.resolve_accounts(drifted) == %{
               cash_accounts: %{"Giro" => {:ok, main.id, :former}},
               depots: %{"Depot" => {:ok, broker.id, :former}}
             }

      before = counts()

      for params <- [prefilled(drifted), %{portfolio_id: portfolio.id}] do
        assert {:ok, %Result{} = result} = Imports.apply(drifted, params)

        assert counts() == before
        assert result.created_transactions == 0
        assert result.created_cash_accounts == 0
        assert result.created_securities_accounts == 0
        assert result.created_securities == 0
        assert result.already_imported == %{hash: 0, retired: 0, economics: 3}

        assert Enum.map(result.duplicate_entries, & &1.layer) == [
                 :economics,
                 :economics,
                 :economics
               ]
      end
    end
  end

  describe "a newer file naming a former name lands on the renamed account (§16 inv 6)" do
    # User story:
    # As the operator importing a later export that still names the old
    # account,
    # I want its new rows booked once, on the renamed account,
    # so that the history stays in one place and nothing is doubled.
    #
    # Acceptance criteria:
    # - The newer file's two new rows are inserted on "Main account" and
    #   "Broker depot"; no account is created.
    # - Applying the newer file again creates nothing.
    test "its new rows are inserted once, on the renamed rows", %{portfolio: portfolio} do
      {:ok, _} = Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})

      {:ok, main} =
        Portfolios.update_cash_account(agent(), named!(CashAccount, "Giro"), %{
          name: "Main account"
        })

      {:ok, broker} =
        Portfolios.update_securities_account(agent(), named!(SecuritiesAccount, "Depot"), %{
          name: "Broker depot"
        })

      newer =
        parse!(
          household() ++
            [
              deposit("Giro", "250.00", "2025-04-01"),
              purchase(date: "2025-04-02", amount: "250.00")
            ]
        )

      assert {:ok, %Result{} = result} = Imports.apply(newer, prefilled(newer))
      assert result.created_transactions == 2
      assert result.created_cash_accounts == 0
      assert result.created_securities_accounts == 0

      new_rows = Repo.all(from(t in Transaction, where: t.date >= ^~D[2025-04-01]))
      assert Enum.all?(new_rows, &(&1.cash_account_id == main.id))

      assert [%{securities_account_id: depot_id}] = Enum.filter(new_rows, &(&1.type == "buy"))
      assert depot_id == broker.id

      before = counts()
      assert {:ok, %Result{created_transactions: 0}} = Imports.apply(newer, prefilled(newer))
      assert counts() == before
    end
  end

  describe "an ambiguous name fails closed (§4 resolution)" do
    # User story:
    # As the operator with two accounts of one name from before the guard,
    # I want the import to prefill nothing for that name and refuse to guess,
    # so that a row never books onto whichever account was read last.
    #
    # Acceptance criteria:
    # - The preview's resolution is ambiguous and names both accounts.
    # - An apply that leaves the name unmapped refuses with the name and both
    #   ids when a row needs it, and writes nothing.
    # - The name mapped explicitly books onto the chosen account.
    # - A re-import whose rows naming it are all hash hits needs no decision.
    test "no prefill, a refusal when a row needs the name, and the explicit choice wins", %{
      portfolio: portfolio
    } do
      {:ok, _} = Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})

      giro = named!(CashAccount, "Giro")
      twin = legacy_cash!(portfolio, "Giro")
      ids = Enum.sort([giro.id, twin.id])

      # Every row a hash hit: nothing to resolve, nothing to refuse.
      assert {:ok, %Result{created_transactions: 0}} =
               Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})

      newer = parse!([deposit("Giro", "250.00", "2025-04-01")])

      assert %{cash_accounts: %{"Giro" => {:ambiguous, :live, ^ids}}} =
               Imports.resolve_accounts(newer)

      before = counts()

      assert {:error, {:ambiguous_account_name, :cash_account, "Giro", ^ids}} =
               Imports.apply(newer, %{portfolio_id: portfolio.id})

      assert {:error, {:ambiguous_account_name, :cash_account, "Giro", ^ids}} =
               Imports.apply(newer, %{cash_accounts: %{}, depots: %{}})

      assert counts() == before

      assert {:ok, %Result{created_transactions: 1}} =
               Imports.apply(newer, %{
                 cash_accounts: %{"Giro" => {:existing, twin.id}},
                 depots: %{}
               })

      assert [%{cash_account_id: twin_id}] =
               Repo.all(from(t in Transaction, where: t.date == ^~D[2025-04-01]))

      assert twin_id == twin.id
    end
  end

  describe "the importer's lazy creation passes the name guard (§4)" do
    # User story:
    # As the operator who keeps "+ Create new" for a name another account
    # already answers to,
    # I want the import to refuse instead of creating a second account under
    # that name,
    # so that an old export can never be re-routed onto a new account.
    #
    # Acceptance criteria:
    # - A create choice whose name is another account's former name fails at
    #   the first row that inserts, naming the guard's reason, and writes
    #   nothing.
    test "a create choice under a former name is refused", %{portfolio: portfolio} do
      giro = cash!(portfolio, "Giro")
      {:ok, _main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})
      file = parse!([deposit("Giro", "10.00", "2025-05-01")])
      before = counts()

      assert {:error, {:cash_create_failed, "Giro", changeset}} =
               Imports.apply(file, %{cash_accounts: %{"Giro" => {:create, "Giro"}}, depots: %{}})

      assert %{name: [message]} = errors_on(changeset)
      assert message =~ "is a former name of cash account ##{giro.id}"
      assert counts() == before
    end
  end

  describe "a remembered remap (§4 writers of former names)" do
    # User story:
    # As the operator who maps a Portfolio Performance name onto an account
    # of another name in the preview,
    # I want the mapping remembered by default,
    # so that the next import resolves the name by itself — and I want to be
    # able to leave a one-off remap unremembered.
    #
    # Acceptance criteria:
    # - "remember" is on by default: the file name becomes a former name of
    #   the chosen account, journaled under the import actor, and the result
    #   reports it.
    # - It runs from the mapping at apply start, so it takes effect when every
    #   row of the name is a hash hit.
    # - remember: false writes nothing.
    test "is on by default, runs at apply start, and can be switched off", %{
      portfolio: portfolio
    } do
      broker = cash!(portfolio, "Broker USD")
      file = parse!([deposit("Cash USD", "100.00", "2025-01-02")])

      one_off = %{
        cash_accounts: %{"Cash USD" => {:existing, broker.id}},
        depots: %{},
        remember: %{cash_accounts: %{"Cash USD" => false}}
      }

      assert {:ok, %Result{created_transactions: 1, remembered_names: []}} =
               Imports.apply(file, one_off)

      assert reload(broker).former_names == []

      remembered = Map.delete(one_off, :remember)

      assert {:ok, %Result{} = result} = Imports.apply(file, remembered)
      assert result.created_transactions == 0
      assert result.already_imported.hash == 1

      assert result.remembered_names == [
               %{kind: :cash_account, name: "Cash USD", account_id: broker.id, outcome: :appended}
             ]

      assert reload(broker).former_names == ["Cash USD"]

      [entry | _] =
        Journal.list_entries(resource_type: "cash_account", resource_id: "#{broker.id}")

      assert entry.actor_type == :import_session
      assert entry.after["former_names"] == ["Cash USD"]

      assert Imports.resolve_accounts(file) == %{
               cash_accounts: %{"Cash USD" => {:ok, broker.id, :former}},
               depots: %{}
             }
    end

    # User story:
    # As the operator remapping a name another account already answers to,
    # I want the preview to tell me what remembering does before I apply,
    # so that remembering never fails an import and never moves a name
    # silently.
    #
    # Acceptance criteria:
    # - A former name of another account moves to the chosen account; the
    #   preview's outcome and the result name the account it left.
    # - A live name of another account is not remembered; the outcome names
    #   that account, the import applies, and nothing is written.
    # - The same holds for a depot.
    test "moves another account's former name, and leaves another's live name alone", %{
      portfolio: portfolio
    } do
      giro = cash!(portfolio, "Giro")
      {:ok, main} = Portfolios.update_cash_account(agent(), giro, %{name: "Main account"})
      household = cash!(portfolio, "Household")
      savings = cash!(portfolio, "Savings")

      file =
        parse!([
          deposit("Giro", "10.00", "2025-05-01"),
          deposit("Savings", "20.00", "2025-05-02")
        ])

      assert Imports.remember_outcome(:cash_account, "Giro", household.id) == {:move, main.id}

      assert Imports.remember_outcome(:cash_account, "Savings", household.id) ==
               {:not_offered, savings.id}

      mapping = %{
        cash_accounts: %{
          "Giro" => {:existing, household.id},
          "Savings" => {:existing, household.id}
        },
        depots: %{}
      }

      assert {:ok, %Result{created_transactions: 2} = result} = Imports.apply(file, mapping)

      assert Enum.sort_by(result.remembered_names, & &1.name) == [
               %{
                 kind: :cash_account,
                 name: "Giro",
                 account_id: household.id,
                 outcome: {:moved, main.id}
               },
               %{
                 kind: :cash_account,
                 name: "Savings",
                 account_id: household.id,
                 outcome: {:not_offered, savings.id}
               }
             ]

      assert reload(main).former_names == []
      assert reload(household).former_names == ["Giro"]
      assert reload(savings).former_names == []

      depot = depot!(portfolio, "Depot", household)
      second = depot!(portfolio, "Second depot", household)
      depots = parse!([purchase(portfolio: "Old depot", account: "Household")])

      assert {:ok, %Result{created_transactions: 1} = result} =
               Imports.apply(depots, %{
                 cash_accounts: %{"Household" => {:existing, household.id}},
                 depots: %{"Old depot" => %{target: {:existing, second.id}, cash: "Household"}}
               })

      assert result.remembered_names == [
               %{
                 kind: :securities_account,
                 name: "Old depot",
                 account_id: second.id,
                 outcome: :appended
               }
             ]

      assert reload(second).former_names == ["Old depot"]
      assert reload(depot).former_names == []
    end
  end

  describe "a mapping that names an account merged away since aborts at apply start (§10)" do
    # User story:
    # As the operator whose preview sat open while an account was merged,
    # I want the apply to stop before it writes anything and name the
    # account that survived,
    # so that a stale mapping never books onto an account that is gone.
    #
    # Acceptance criteria:
    # - A cash account, a depot or a security remap merged away since the
    #   preview aborts with resolution_diverged, the kind, the file name, the
    #   stale id and the survivor at the live end of the merge chain.
    # - A mapped account deleted without a merge answers the same, with no
    #   survivor.
    # - It aborts even when every row is a hash hit, and writes nothing.
    test "resolution_diverged names the survivor, or none", %{portfolio: portfolio} do
      {:ok, _} = Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})
      giro = named!(CashAccount, "Giro")
      depot = named!(SecuritiesAccount, "Depot")

      old = cash!(portfolio, "Savings (old)")
      middle = cash!(portfolio, "Savings")
      merge_away!(:cash_account, old, middle.id, portfolio.id)
      merge_away!(:cash_account, middle, giro.id, portfolio.id)

      gone = cash!(portfolio, "Gone")
      {:ok, _} = Portfolios.delete_cash_account(agent(), gone)

      old_depot = depot!(portfolio, "Old depot", giro)
      merge_away!(:securities_account, old_depot, depot.id, portfolio.id)

      preview = parse!(household())
      before = counts()

      stale_cash = %{
        cash_accounts: %{"Giro" => {:existing, old.id}},
        depots: %{"Depot" => %{target: {:existing, depot.id}, cash: "Giro"}}
      }

      assert Imports.apply(preview, stale_cash) ==
               {:error,
                {:resolution_diverged,
                 %{kind: :cash_account, name: "Giro", id: old.id, merged_into: giro.id}}}

      deleted = put_in(stale_cash, [:cash_accounts, "Giro"], {:existing, gone.id})

      assert Imports.apply(preview, deleted) ==
               {:error,
                {:resolution_diverged,
                 %{kind: :cash_account, name: "Giro", id: gone.id, merged_into: nil}}}

      stale_depot = %{
        cash_accounts: %{"Giro" => {:existing, giro.id}},
        depots: %{"Depot" => %{target: {:existing, old_depot.id}, cash: "Giro"}}
      }

      assert Imports.apply(preview, stale_depot) ==
               {:error,
                {:resolution_diverged,
                 %{
                   kind: :securities_account,
                   name: "Depot",
                   id: old_depot.id,
                   merged_into: depot.id
                 }}}

      assert counts() == before
    end

    test "a security remap merged away since names the survivor", %{portfolio: portfolio} do
      {:ok, survivor} =
        Catalog.create_security(Actor.owner_ui(), %{name: "Example Fund", currency_code: "EUR"})

      {:ok, merged} =
        Catalog.create_security(Actor.owner_ui(), %{name: "Example Fund B", currency_code: "EUR"})

      {:ok, _} = Catalog.delete_security(Actor.owner_ui(), merged)

      {:ok, _} =
        Lifecycle.record_merge(agent(), %{
          kind: "security",
          source_id: merged.id,
          target_id: survivor.id,
          source_snapshot: %{"name" => "Example Fund B"},
          manifest: %{},
          plan_digest: "sha256:synthetic-plan"
        })

      preview = parse!([purchase(security: Map.delete(@fund, "isin"))])
      [key] = Enum.map(Imports.resolve_securities(preview).resolutions, & &1.key)

      assert Imports.apply(preview, %{
               portfolio_id: portfolio.id,
               security_mappings: %{key => {:existing, merged.id}}
             }) ==
               {:error,
                {:resolution_diverged,
                 %{kind: :security, key: key, id: merged.id, merged_into: survivor.id}}}
    end
  end

  describe "the backfill routes a drifted export to the renamed account (plan done-criterion 4)" do
    # User story:
    # As the operator who renamed an imported account before former names
    # existed,
    # I want the upgrade's backfill to make the next drifted export find the
    # renamed account,
    # so that the rename made before the upgrade is as safe as one made after
    # it.
    #
    # Acceptance criteria:
    # - A rename journaled the way the old writer made it (no former name)
    #   leaves the old name unresolvable before the backfill.
    # - After the backfill, the drifted export resolves the old names to the
    #   renamed rows and creates nothing.
    test "a journaled rename from before the migration routes a drifted export", %{
      portfolio: portfolio
    } do
      {:ok, _} = Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})

      main = old_rename!(named!(CashAccount, "Giro"), "Main account")
      broker = old_rename!(named!(SecuritiesAccount, "Depot"), "Broker depot")

      drifted = parse!(household(:drifted))

      assert Imports.resolve_accounts(drifted) == %{
               cash_accounts: %{"Giro" => :none},
               depots: %{"Depot" => :none}
             }

      {:ok, _report} = FormerNamesBackfill.run(Actor.system_job("former_names_backfill"))

      assert Imports.resolve_accounts(drifted) == %{
               cash_accounts: %{"Giro" => {:ok, main.id, :former}},
               depots: %{"Depot" => {:ok, broker.id, :former}}
             }

      before = counts()
      assert {:ok, %Result{} = result} = Imports.apply(drifted, prefilled(drifted))

      assert counts() == before
      assert result.created_cash_accounts == 0
      assert result.created_securities_accounts == 0
      assert result.already_imported == %{hash: 0, retired: 0, economics: 3}
    end
  end

  # --- the synthetic export ---------------------------------------------------

  # A deposit, a purchase and an interest row on "Giro" and "Depot". The
  # drifted variant writes every number with another precision, as a
  # re-export after an edit inside Portfolio Performance would.
  defp household(variant \\ :exact) do
    digits =
      case variant do
        :exact -> %{deposit: "1000.00", buy: "500.00", shares: "5", interest: "1.25"}
        :drifted -> %{deposit: "1000.0", buy: "500.000", shares: "5.0", interest: "1.250"}
      end

    [
      deposit("Giro", digits.deposit, "2025-01-02"),
      purchase(amount: digits.buy, shares: digits.shares),
      %{
        "type" => "INTEREST",
        "account" => "Giro",
        "date" => "2025-03-31",
        "currency" => "EUR",
        "amount" => num(digits.interest)
      }
    ]
  end

  defp deposit(account, amount, date) do
    %{
      "type" => "DEPOSIT",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  defp purchase(opts) do
    %{
      "type" => "PURCHASE",
      "account" => Keyword.get(opts, :account, "Giro"),
      "portfolio" => Keyword.get(opts, :portfolio, "Depot"),
      "date" => Keyword.get(opts, :date, "2025-01-10"),
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => num(Keyword.get(opts, :amount, "500.00")),
      "shares" => num(Keyword.get(opts, :shares, "5")),
      "security" => Keyword.get(opts, :security, @fund)
    }
  end

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # The preview's prefill (`ImportsLive`): the shared resolution, an exact
  # live or a former name mapped to its account, an unknown name to
  # "+ Create new".
  defp prefilled(preview) do
    %{cash_accounts: cash, depots: depots} = Imports.resolve_accounts(preview)
    cash_names = Mapping.unique_cash_pp_names(preview)

    %{
      cash_accounts: Map.new(cash, fn {name, resolution} -> {name, choice(resolution, name)} end),
      depots:
        Map.new(depots, fn {name, resolution} ->
          default_cash = Mapping.default_cash_for_depot(preview, name)

          {name,
           %{
             target: choice(resolution, name),
             cash: if(default_cash in cash_names, do: default_cash)
           }}
        end)
    }
  end

  defp choice({:ok, id, _tier}, _name), do: {:existing, id}
  defp choice(:none, name), do: {:create, name}

  # --- world ------------------------------------------------------------------

  defp named!(schema, name), do: Repo.one!(from(a in schema, where: a.name == ^name))

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(agent(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp depot!(portfolio, name, cash) do
    {:ok, depot} =
      Portfolios.create_securities_account(agent(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  # A duplicate name from before the guard, inserted the way the old writer
  # did.
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

  # The writer before ADR-0050 §4: the name changes, the change is journaled,
  # nothing is remembered.
  defp old_rename!(%schema{} = account, name) do
    resource_type = if schema == CashAccount, do: "cash_account", else: "securities_account"

    {:ok, %{account: renamed}} =
      Multi.new()
      |> Multi.update(:account, Ecto.Changeset.change(account, name: name))
      |> Journal.record(agent(),
        resource_type: resource_type,
        operation: :update,
        source: :account,
        before: account
      )
      |> Repo.transaction()

    renamed
  end

  # What a merge leaves of its source: a merge record naming the target, and
  # the source deleted through the hardened delete (ADR-0050 §7 step 7).
  defp merge_away!(kind, source, target_id, portfolio_id) do
    {:ok, _} =
      Lifecycle.record_merge(agent(), %{
        kind: kind,
        source_id: source.id,
        target_id: target_id,
        portfolio_id: portfolio_id,
        source_snapshot: %{"name" => source.name},
        manifest: %{},
        plan_digest: "sha256:synthetic-plan"
      })

    {:ok, _} =
      case kind do
        :cash_account -> Portfolios.delete_cash_account(agent(), source)
        :securities_account -> Portfolios.delete_securities_account(agent(), source)
      end
  end

  defp reload(%schema{id: id}), do: Repo.get!(schema, id)

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: Portfolios.count_securities_accounts(),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end
end
