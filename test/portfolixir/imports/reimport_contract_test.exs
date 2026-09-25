defmodule Portfolixir.Imports.ReimportContractTest do
  # ADR-0050 §2–§6 and the §16 invariants of its importer half (L2, #884;
  # risk-tier: import idempotency, ADR-0036). Each describe block names the
  # invariant it pins. Written before the applier changed, so each shows red
  # against the resolve-then-hash order, the up-front account creation, the
  # whole-import rollback on an internal transfer and the unscoped in-run key.
  #
  # The exports are synthetic Portfolio Performance JSON; every name, amount
  # and identifier is invented.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios

  @fund %{
    "name" => "Example Fund",
    "isin" => "DE000EXMPL01",
    "wkn" => "EXF001",
    "currency" => "EUR"
  }

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  describe "a held or retired hash triggers no resolution, creation or insert (§3, §16 inv 2 and 3)" do
    # User story:
    # As the operator re-importing an export I already imported,
    # I want every row the database already holds to be recognised before
    # anything is resolved or created,
    # so that a re-import after a rename, a deleted account or a changed
    # security creates nothing and books nothing.
    #
    # Acceptance criteria:
    # - A byte-identical re-import whose mapping says "create" for every
    #   account creates no cash account, no depot, no security and no
    #   transaction; every row is reported as a duplicate with layer `hash`.
    # - The result counts the already-imported rows per layer.
    # - A bucket tag given with such an import creates no bucket.
    test "a byte-identical re-import creates nothing, even where the mapping says create" do
      preview = parse!(household())

      assert {:ok, %Result{created_transactions: 4}} =
               Imports.apply(preview, create_everything(preview))

      counts = counts()

      assert {:ok, %Result{} = again} =
               Imports.apply(parse!(household()), create_everything(preview, "PP Import"))

      assert again.created_transactions == 0
      assert again.created_cash_accounts == 0
      assert again.created_securities_accounts == 0
      assert again.created_securities == 0
      assert again.created_cash_account_ids == []
      assert again.created_securities_account_ids == []
      assert counts() == counts
      assert Buckets.list_buckets() == []

      assert again.already_imported == %{hash: 4, retired: 0, economics: 0}

      assert Enum.map(again.duplicate_entries, &{&1.row, &1.layer}) ==
               Enum.map(1..4, &{&1, :hash})
    end

    # User story:
    # As the operator whose export names a security the catalog can no
    # longer resolve on its own,
    # I want the rows I already imported to be skipped before the identity
    # ladder runs,
    # so that an ambiguity or a changed identity that arose since the first
    # import neither blocks the re-import nor creates a duplicate security.
    #
    # Acceptance criteria:
    # - With the security's identifiers changed so that the ladder would create
    #   a new one, a re-import creates no security.
    # - With two other securities sharing the file's WKN, a re-import reports
    #   no unresolved entry and no divergence from an empty approved baseline.
    test "a hash hit never reaches the security ladder" do
      ref = Map.delete(@fund, "isin")
      rows = [purchase(1, security: ref)]
      preview = parse!(rows)

      assert {:ok, %Result{created_transactions: 1, created_securities: 1}} =
               Imports.apply(preview, create_everything(preview))

      [imported] = Catalog.list_securities()

      {:ok, _} =
        Catalog.update_security(Actor.owner_ui(), imported, %{name: "Renamed", wkn: "EXF999"})

      assert {:ok, %Result{} = changed} = Imports.apply(parse!(rows), prefilled_mapping(preview))

      assert changed.created_securities == 0
      assert changed.created_transactions == 0
      assert changed.resolved_security_ids == []
      assert [%{row: 1, layer: :hash}] = changed.duplicate_entries
      assert Catalog.count_securities() == 1

      _twin_a = security!(%{name: "Twin A", wkn: "EXF001"})
      _twin_b = security!(%{name: "Twin B", wkn: "EXF001"})

      assert {:ok, %Result{} = ambiguous} =
               Imports.apply(
                 parse!(rows),
                 Map.put(prefilled_mapping(preview), :approved_resolutions, %{})
               )

      assert ambiguous.unresolved_entries == []
      assert ambiguous.created_securities == 0
      assert [%{row: 1, layer: :hash}] = ambiguous.duplicate_entries
      assert Catalog.count_securities() == 3
    end

    # User story:
    # As the operator who merged an obsolete account into its successor,
    # I want a row the merge removed to be recognised by its retired hash,
    # so that re-importing the export that still names the obsolete account
    # neither re-creates that account nor books the row, and never fails.
    #
    # Acceptance criteria:
    # - A re-import whose only row carries a retired hash reports it as a
    #   duplicate with layer `retired`, and creates no account for its names.
    # - The result counts it under `retired`.
    test "a retired hash is a reported skip that creates no zombie account", %{
      portfolio: portfolio
    } do
      rows = [transfer(1, "Savings (old)", "Savings", "250.00")]
      preview = parse!(rows)

      assert {:ok, %Result{created_transactions: 1}} =
               Imports.apply(preview, create_everything(preview))

      # What a merge of "Savings (old)" into "Savings" leaves behind (§5, §7
      # step 2, §11): the internal transfer deleted with its hash retired, and
      # the emptied source deleted.
      [transfer] = Repo.all(from(t in Transaction, where: t.type == "cash_transfer"))
      old = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Savings (old)"))
      retire_as_merge!(portfolio, transfer, old.id)
      {:ok, _} = Portfolios.delete_cash_account(Actor.owner_ui(), old)

      preview = parse!(rows)
      assert {:ok, %Result{} = result} = Imports.apply(preview, prefilled_mapping(preview))

      assert result.created_transactions == 0
      assert result.created_cash_accounts == 0
      assert [%{row: 1, layer: :retired}] = result.duplicate_entries
      assert result.already_imported == %{hash: 0, retired: 1, economics: 0}
      assert Enum.map(Portfolios.list_cash_accounts(), & &1.name) == ["Savings"]
      refute Repo.exists?(from(t in Transaction, where: t.import_hash == ^transfer.import_hash))
    end
  end

  describe "preview decisions run from the mapping at apply start (§3, §16 inv 2)" do
    # User story:
    # As the operator who remaps a security in the preview and records the
    # file's ISIN as an ISIN change,
    # I want that decision to take effect even when every row of that
    # security is already imported,
    # so that the change I confirmed is not silently dropped by the
    # duplicate check.
    #
    # Acceptance criteria:
    # - A re-import whose rows are all hash hits still records the ISIN change
    #   the mapping asks for, and reports the override.
    test "an ISIN-change override takes effect when all its rows are hash hits" do
      existing = security!(%{name: "Example Fund", isin: "DE000OLD0001"})
      new_identity = Map.put(@fund, "isin", "DE000NEW0001")

      rows = [
        purchase(1, security: new_identity),
        purchase(2, security: new_identity, date: "2025-01-17")
      ]

      preview = parse!(rows)
      key = security_key(preview)

      # The first import remapped the rows without recording the change.
      assert {:ok, %Result{created_transactions: 2}} =
               Imports.apply(
                 preview,
                 preview
                 |> create_everything()
                 |> Map.put(:security_mappings, %{key => {:existing, existing.id}})
               )

      assert {:ok, %Result{} = result} =
               Imports.apply(
                 parse!(rows),
                 preview
                 |> prefilled_mapping()
                 |> Map.put(:security_mappings, %{
                   key => {:existing, existing.id, :record_isin_change}
                 })
               )

      assert result.created_transactions == 0
      assert result.already_imported == %{hash: 2, retired: 0, economics: 0}

      assert [%{security_id: id, recorded_isin_change: true}] = result.security_overrides
      assert id == existing.id

      updated = Catalog.get_security!(existing.id)
      assert updated.isin == "DE000NEW0001"
      assert [%{former_isin: "DE000OLD0001"}] = Catalog.list_identifier_aliases(updated)
    end
  end

  describe "accounts are created with their first inserted row (§4, §16 inv 3)" do
    # User story:
    # As the operator importing a file that names a new account beside ones I
    # already imported,
    # I want exactly the accounts that receive a new booking to be created and
    # tagged,
    # so that a "create" choice whose rows are all skipped leaves no empty
    # account and no stray tag behind.
    #
    # Acceptance criteria:
    # - Of three create-mapped names, only the one with a new row is created,
    #   once, and only it carries the import's bucket tag.
    # - A create-mapped account or depot whose rows are all skipped (already
    #   imported, unimportable, or an internal transfer) is not created.
    test "only the account with a new row is created, and only it is tagged" do
      preview = parse!(household())
      assert {:ok, _} = Imports.apply(preview, create_everything(preview))

      grown =
        parse!(
          household() ++
            [
              deposit(5, "Holiday", "300.00", "2025-04-01"),
              tax(6, "Ghost", "0.00"),
              transfer(7, "Echo", "Echo", "10.00")
            ]
        )

      assert {:ok, %Result{} = result} = Imports.apply(grown, create_everything(grown, "Tag"))

      assert result.created_transactions == 1
      assert result.created_cash_accounts == 1
      assert result.created_securities_accounts == 0

      names = Enum.map(Portfolios.list_cash_accounts(), & &1.name)
      assert Enum.sort(names) == ["Giro", "Holiday", "Savings"]
      assert Enum.map(Portfolios.list_securities_accounts(), & &1.name) == ["Depot"]

      [bucket] = Buckets.list_buckets()
      holiday = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Holiday"))
      assert result.created_cash_account_ids == [holiday.id]
      assert Buckets.cash_account_bucket_ids(holiday.id) == [bucket.id]

      for account <- Portfolios.list_cash_accounts(), account.id != holiday.id do
        assert Buckets.cash_account_bucket_ids(account.id) == []
      end

      for depot <- Portfolios.list_securities_accounts() do
        assert Buckets.depot_default_bucket_ids(depot.id) == []
      end
    end

    test "a create-mapped depot is created with its first inserted row, and its cash with it" do
      preview = parse!([purchase(1)])
      params = create_everything(preview, "Tag")

      assert {:ok, %Result{} = result} = Imports.apply(preview, params)

      assert result.created_cash_accounts == 1
      assert result.created_securities_accounts == 1

      assert [%{name: "Depot", cash_account: %{name: "Giro"}}] =
               Portfolios.list_securities_accounts()
    end
  end

  describe "an internal transfer is skipped and reported (§5, §16 inv 7)" do
    # User story:
    # As the operator whose two Portfolio Performance accounts both map onto
    # one Portfolixir account,
    # I want a transfer between them skipped and listed,
    # so that one void row never rolls back the whole import, today or at any
    # later re-import of the same export.
    #
    # Acceptance criteria:
    # - A cash transfer whose legs map to one account is not inserted and is
    #   listed in `internal_transfers` with its row, kind, date, amount and
    #   both file names; the other rows import.
    # - The same holds for a security transfer between two file depots mapped
    #   onto one depot.
    # - A re-import skips it again, still without an error.
    test "a cash transfer whose legs map to one account is listed, never booked", %{
      portfolio: portfolio
    } do
      main = cash!(portfolio, "Main account")

      rows = [
        deposit(1, "Giro", "100.00", "2025-01-02"),
        transfer(2, "Giro", "Tagesgeld", "40.00")
      ]

      params = %{
        cash_accounts: %{"Giro" => {:existing, main.id}, "Tagesgeld" => {:existing, main.id}},
        depots: %{}
      }

      assert {:ok, %Result{} = result} = Imports.apply(parse!(rows), params)

      assert result.created_transactions == 1
      assert result.skipped_duplicates == 0

      assert [
               %{
                 row: 2,
                 kind: "cash_transfer",
                 date: ~D[2025-02-01],
                 gross_amount: amount,
                 currency_code: "EUR",
                 pp_name: "Giro",
                 pp_counter_name: "Tagesgeld"
               }
             ] = result.internal_transfers

      assert Decimal.equal?(amount, Decimal.new("40.00"))
      refute Repo.exists?(from(t in Transaction, where: t.type == "cash_transfer"))

      assert {:ok, %Result{} = again} = Imports.apply(parse!(rows), params)
      assert again.created_transactions == 0
      assert [%{row: 2}] = again.internal_transfers
    end

    test "a security transfer between two file depots mapped onto one depot is listed", %{
      portfolio: portfolio
    } do
      main = cash!(portfolio, "Main account")

      {:ok, depot} =
        Portfolios.create_securities_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: main.id,
          name: "Broker depot"
        })

      rows = [
        purchase(1, account: "Giro", portfolio: "Depot 1"),
        security_transfer(2, "Depot 1", "Depot 2", "3")
      ]

      params = %{
        cash_accounts: %{"Giro" => {:existing, main.id}},
        depots: %{
          "Depot 1" => %{target: {:existing, depot.id}, cash: {:existing, main.id}},
          "Depot 2" => %{target: {:existing, depot.id}, cash: {:existing, main.id}}
        }
      }

      assert {:ok, %Result{} = result} = Imports.apply(parse!(rows), params)

      assert result.created_transactions == 1

      assert [
               %{
                 row: 2,
                 kind: "security_transfer",
                 quantity: quantity,
                 security_name: "Example Fund",
                 pp_name: "Depot 1",
                 pp_counter_name: "Depot 2"
               }
             ] = result.internal_transfers

      assert Decimal.equal?(quantity, Decimal.new("3"))
      refute Repo.exists?(from(t in Transaction, where: t.type == "security_transfer"))
    end

    test "on the name-matching path a transfer naming one account twice creates nothing", %{
      portfolio: portfolio
    } do
      rows = [transfer(1, "Echo", "Echo", "10.00"), deposit(2, "Giro", "5.00", "2025-01-03")]

      assert {:ok, %Result{} = result} =
               Imports.apply(parse!(rows), %{portfolio_id: portfolio.id})

      assert result.created_transactions == 1
      assert result.created_cash_accounts == 1
      assert [%{row: 1, pp_name: "Echo", pp_counter_name: "Echo"}] = result.internal_transfers
      assert Enum.map(Portfolios.list_cash_accounts(), & &1.name) == ["Giro"]
    end
  end

  describe "the in-run collapse key is scoped by the file's account names (§6, §16 inv 8)" do
    # User story:
    # As the operator whose two Portfolio Performance accounts map onto one
    # Portfolixir account,
    # I want two equal same-day bookings, one from each file account, both
    # imported,
    # so that twin fees or twin savings plans are never silently merged into
    # one, while one paper listed under its old and its new ISIN still
    # collapses.
    #
    # Acceptance criteria:
    # - Two fee rows with equal amount and date from different file accounts,
    #   mapped onto one account, are both inserted and neither is collapsed.
    # - Two rows of one booking under one file account, carrying the old and
    #   the new ISIN of one security, collapse to one insert, reported.
    test "twin rows from different file accounts are both inserted", %{portfolio: portfolio} do
      main = cash!(portfolio, "Main account")

      rows = [fee(1, "Broker A", "4.90"), fee(2, "Broker B", "4.90")]

      params = %{
        cash_accounts: %{"Broker A" => {:existing, main.id}, "Broker B" => {:existing, main.id}},
        depots: %{}
      }

      assert {:ok, %Result{} = result} = Imports.apply(parse!(rows), params)

      assert result.created_transactions == 2
      assert result.collapsed_duplicates == []
      assert Ledger.count_transactions() == 2
    end

    test "old and new ISIN of one booking under one account still collapse" do
      security = security!(%{name: "Example Fund", isin: "DE000000000A"})
      {:ok, _} = Catalog.record_isin_change(Actor.owner_ui(), security, "DE000000000B")

      rows = [
        purchase(1, security: Map.put(@fund, "isin", "DE000000000A")),
        purchase(2, security: Map.put(@fund, "isin", "DE000000000B"))
      ]

      preview = parse!(rows)
      assert {:ok, %Result{} = result} = Imports.apply(preview, create_everything(preview))

      assert result.created_transactions == 1
      assert [%{row: 2}] = result.collapsed_duplicates
    end
  end

  describe "the already-imported counts before the apply (§3)" do
    # User story:
    # As the operator reviewing a preview,
    # I want to know, per account and depot of the file, how many of its rows
    # are already imported and how many are new,
    # so that I can see before confirming that a "create" choice with no new
    # row will create nothing.
    #
    # Acceptance criteria:
    # - The read counts each row once in the total, by layer: `hash`,
    #   `retired`, `unimportable` or `new`.
    # - Per file account and depot name it counts every row naming it, on
    #   either leg.
    # - It writes nothing.
    test "counts the rows the database already holds, per layer and per name", %{
      portfolio: portfolio
    } do
      assert Imports.reimport_counts(parse!(household())).total ==
               %{hash: 0, retired: 0, unimportable: 0, new: 4}

      preview = parse!(household())
      assert {:ok, _} = Imports.apply(preview, create_everything(preview))

      [transfer] = Repo.all(from(t in Transaction, where: t.type == "cash_transfer"))
      retire_as_merge!(portfolio, transfer, transfer.counter_cash_account_id)

      grown =
        parse!(
          household() ++ [deposit(5, "Holiday", "300.00", "2025-04-01"), tax(6, "Giro", "0")]
        )

      before = counts()
      counts = Imports.reimport_counts(grown)
      assert counts() == before

      assert counts.total == %{hash: 3, retired: 1, unimportable: 1, new: 1}

      assert counts.cash_accounts == %{
               "Giro" => %{hash: 2, retired: 1, unimportable: 1, new: 0},
               "Savings" => %{hash: 1, retired: 1, unimportable: 0, new: 0},
               "Holiday" => %{hash: 0, retired: 0, unimportable: 0, new: 1}
             }

      assert counts.depots == %{"Depot" => %{hash: 1, retired: 0, unimportable: 0, new: 0}}
    end
  end

  describe "the import takes the account-identity lock before any row lock (§4, §10)" do
    # User story:
    # As the operator renaming an account while an import runs,
    # I want the import to take the account-identity lock before it books
    # onto an existing account,
    # so that the rename and the import queue in one order and neither ends
    # in a deadlock.
    #
    # Acceptance criteria:
    # - On both apply paths, the portfolio's account-identity lock is taken
    #   before the first transaction is inserted, also when the first row
    #   books onto an existing account and a later row creates one, and when
    #   nothing is remembered.
    test "on both apply paths the identity lock precedes the first booking", %{
      portfolio: portfolio
    } do
      giro = cash!(portfolio, "Giro")

      auto = [
        deposit(1, "Giro", "100.00", "2025-01-02"),
        deposit(2, "New", "50.00", "2025-01-03")
      ]

      queries =
        capture_queries(fn ->
          assert {:ok, %Result{created_transactions: 2}} =
                   Imports.apply(parse!(auto), %{portfolio_id: portfolio.id})
        end)

      assert_identity_lock_first(queries, portfolio.id)

      mapped = [
        deposit(1, "Giro", "300.00", "2025-02-02"),
        deposit(2, "Other", "70.00", "2025-02-03")
      ]

      queries =
        capture_queries(fn ->
          assert {:ok, %Result{created_transactions: 2}} =
                   Imports.apply(parse!(mapped), %{
                     portfolio: {:existing, portfolio.id},
                     cash_accounts: %{
                       "Giro" => {:existing, giro.id},
                       "Other" => {:create, "Other"}
                     },
                     depots: %{},
                     remember: %{cash_accounts: %{"Giro" => false}}
                   })
        end)

      assert_identity_lock_first(queries, portfolio.id)
    end
  end

  defp assert_identity_lock_first(queries, portfolio_id) do
    lock_params = [Lifecycle.AccountNames.lock_key(), portfolio_id]

    lock =
      Enum.find_index(queries, fn {query, params} ->
        query =~ "pg_advisory_xact_lock" and params == lock_params
      end)

    insert =
      Enum.find_index(queries, fn {query, _} -> query =~ ~s(INSERT INTO "transactions") end)

    assert lock, "the import never took the account-identity lock"
    assert insert, "the import inserted no transaction"

    assert lock < insert,
           "the identity lock came after the first booking (query #{lock} > #{insert})"
  end

  defp capture_queries(fun) do
    test_pid = self()
    handler = "reimport-identity-lock-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query, params: params}, _config ->
          if self() == test_pid, do: send(test_pid, {:query, query, params})
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
      {:query, query, params} -> collect_queries([{query, params} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # --- the synthetic export ---------------------------------------------------

  defp household do
    [
      deposit(1, "Giro", "1000.00", "2025-01-02"),
      purchase(2),
      transfer(3, "Giro", "Savings", "200.00"),
      %{
        "type" => "INTEREST",
        "account" => "Savings",
        "date" => "2025-03-31",
        "currency" => "EUR",
        "amount" => num("1.25"),
        "row" => 4
      }
    ]
  end

  defp deposit(row, account, amount, date) do
    %{
      "type" => "DEPOSIT",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount),
      "row" => row
    }
  end

  defp tax(row, account, amount) do
    %{
      "type" => "TAX",
      "account" => account,
      "date" => "2025-05-02",
      "currency" => "EUR",
      "amount" => num(amount),
      "row" => row
    }
  end

  defp fee(row, account, amount) do
    %{
      "type" => "FEE",
      "account" => account,
      "date" => "2025-06-30",
      "currency" => "EUR",
      "amount" => num(amount),
      "row" => row
    }
  end

  defp transfer(row, from, to, amount) do
    %{
      "type" => "CASH_TRANSFER",
      "account" => from,
      "otherAccount" => to,
      "date" => "2025-02-01",
      "currency" => "EUR",
      "amount" => num(amount),
      "row" => row
    }
  end

  defp purchase(row, opts \\ []) do
    %{
      "type" => "PURCHASE",
      "account" => Keyword.get(opts, :account, "Giro"),
      "portfolio" => Keyword.get(opts, :portfolio, "Depot"),
      "date" => Keyword.get(opts, :date, "2025-01-10"),
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => num("500.00"),
      "shares" => num("5"),
      "security" => Keyword.get(opts, :security, @fund),
      "row" => row
    }
  end

  defp security_transfer(row, from, to, shares) do
    %{
      "type" => "SECURITY_TRANSFER",
      "portfolio" => from,
      "otherPortfolio" => to,
      "date" => "2025-02-15",
      "currency" => "EUR",
      "amount" => num("300.00"),
      "shares" => num(shares),
      "security" => @fund,
      "row" => row
    }
  end

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  # The parser numbers rows by their position in the file; the "row" key only
  # documents the intended position and is dropped before encoding.
  defp parse!(rows) do
    body =
      Jason.encode!(%{"version" => 1, "transactions" => Enum.map(rows, &Map.delete(&1, "row"))})

    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # --- mappings ----------------------------------------------------------------

  # Every file name mapped to "+ Create new", as the preview prefills a name
  # the database does not carry (for example after a rename).
  defp create_everything(preview, bucket_tag \\ nil) do
    cash_names = Mapping.unique_cash_pp_names(preview)

    %{
      cash_accounts: Map.new(cash_names, &{&1, {:create, &1}}),
      depots:
        Map.new(Mapping.unique_depot_pp_names(preview), fn name ->
          {name, %{target: {:create, name}, cash: default_cash(preview, name, cash_names)}}
        end),
      bucket_tag: bucket_tag
    }
  end

  # The preview's prefill (`ImportsLive`): the shared resolution
  # (`Imports.resolve_accounts/2`, ADR-0050 §4) maps an exact live name, then
  # a former name, to its account, and any other name to "+ Create new".
  defp prefilled_mapping(preview) do
    %{cash_accounts: cash, depots: depots} = Imports.resolve_accounts(preview)
    cash_names = Mapping.unique_cash_pp_names(preview)

    %{
      cash_accounts: Map.new(cash, fn {name, resolution} -> {name, choice(resolution, name)} end),
      depots:
        Map.new(depots, fn {name, resolution} ->
          {name,
           %{target: choice(resolution, name), cash: default_cash(preview, name, cash_names)}}
        end)
    }
  end

  defp choice({:ok, id, _tier}, _name), do: {:existing, id}
  defp choice(:none, name), do: {:create, name}

  defp default_cash(preview, depot_name, cash_names) do
    cash = Mapping.default_cash_for_depot(preview, depot_name)
    if cash in cash_names, do: cash, else: nil
  end

  defp security_key(preview) do
    [key] = Enum.map(Imports.resolve_securities(preview).resolutions, & &1.key)
    key
  end

  # --- world ------------------------------------------------------------------

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), Map.merge(%{currency_code: "EUR"}, attrs))

    security
  end

  # Deletes the transfer, journaled, and retires its hash under a merge record:
  # the two writes a merge makes for an internal transfer (§5, §7 step 2).
  defp retire_as_merge!(portfolio, transfer, source_id) do
    {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), transfer)

    {:ok, record} =
      Lifecycle.record_merge(Actor.owner_ui(), %{
        kind: "cash_account",
        source_id: source_id,
        target_id: source_id + 1_000_000,
        portfolio_id: portfolio.id,
        source_snapshot: %{"name" => "merged away"},
        manifest: %{},
        plan_digest: "sha256:synthetic-plan"
      })

    {:ok, _} =
      Lifecycle.retire_import_hash(Actor.owner_ui(), %{
        import_hash: transfer.import_hash,
        former_transaction_id: transfer.id,
        merge_record_id: record.id,
        reason: "internal_transfer"
      })

    record
  end

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: length(Portfolios.list_securities_accounts()),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end
end
