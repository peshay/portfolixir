defmodule Portfolixir.Lifecycle.CashMergeReimportTest do
  # ADR-0050 §2's post-merge re-import contract for the cash merge (L3a,
  # #328; risk-tier: import idempotency, ADR-0036), its §16 invariants
  # written before the merge existed: 1 (re-applying an applied export
  # creates nothing after a cash merge, with and without collapse, every row
  # reported with its layer), 5 (a drifted re-import creates nothing), 6 (a
  # newer file naming the source's name inserts its new rows once, on the
  # target).
  #
  # The exports are synthetic Portfolio Performance JSON; every name, amount
  # and identifier is invented.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
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

    assert {:ok, %Result{created_transactions: 6}} =
             Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})

    %{
      portfolio: portfolio,
      source: named!(CashAccount, "Savings (old)"),
      target: named!(CashAccount, "Savings")
    }
  end

  for collapse? <- [false, true] do
    describe "after a cash merge with collapse_key_equal #{collapse?}" do
      # User story:
      # As the operator who merged "Savings (old)" into "Savings",
      # I want the next import of the same export, byte-identical or drifted,
      # to create nothing,
      # so that the merge never books the history a second time.
      #
      # Acceptance criteria:
      # - A byte-identical re-import, auto-resolved or through the preview's
      #   prefill, creates zero transactions, cash accounts, depots and
      #   securities; each row is reported as a duplicate with the layer that
      #   caught it: `hash` for a row that moved or stayed, `retired` for the
      #   internal transfer and a collapsed row.
      # - A drifted re-import (other decimal precision, so no content hash
      #   matches) creates nothing either: the old account's name resolves to
      #   the survivor as a former name, its rows are caught by the economic
      #   layer, and the transfer between the two is a reported internal
      #   transfer.
      @tag collapse: collapse?
      test "a byte-identical and a drifted re-import create nothing", ctx do
        merge!(ctx, ctx.collapse)

        assert Portfolios.get_cash_account(ctx.target.id).former_names == ["Savings (old)"]
        before = counts()

        exact = parse!(household())

        for params <- [prefilled(exact), %{portfolio_id: ctx.portfolio.id}] do
          assert {:ok, %Result{} = result} = Imports.apply(exact, params)
          assert_created_nothing(result)
          assert counts() == before

          # Rows: 1 deposit (source), 2 deposit (target), 3 the transfer,
          # 4 and 5 the key-equal interest pair, 6 the purchase.
          interest = if ctx.collapse, do: :retired, else: :hash

          assert Enum.map(result.duplicate_entries, &{&1.row, &1.layer}) ==
                   [{1, :hash}, {2, :hash}, {3, :retired}, {4, interest}, {5, :hash}, {6, :hash}]
        end

        drifted = parse!(household(:drifted))

        assert Imports.resolve_accounts(drifted).cash_accounts == %{
                 "Savings (old)" => {:ok, ctx.target.id, :former},
                 "Savings" => {:ok, ctx.target.id, :live}
               }

        for params <- [prefilled(drifted), %{portfolio_id: ctx.portfolio.id}] do
          assert {:ok, %Result{} = result} = Imports.apply(drifted, params)
          assert_created_nothing(result)
          assert counts() == before
          assert [%{row: 3}] = result.internal_transfers

          assert Enum.map(result.duplicate_entries, &{&1.row, &1.layer}) ==
                   [
                     {1, :economics},
                     {2, :economics},
                     {4, :economics},
                     {5, :economics},
                     {6, :economics}
                   ]
        end
      end

      # User story:
      # As the operator importing a later export that still names the
      # merged-away account,
      # I want its new rows booked once, on the survivor,
      # so that the history stays in one place.
      #
      # Acceptance criteria:
      # - The newer file's new row naming "Savings (old)" is inserted on
      #   "Savings"; nothing is created, and the rows of the older file are
      #   duplicates.
      # - Applying the newer file again creates nothing.
      @tag collapse: collapse?
      test "a newer file naming the old name lands once on the survivor", ctx do
        merge!(ctx, ctx.collapse)
        newer = parse!(household() ++ [deposit("Savings (old)", "300.00", "2025-06-01")])

        assert {:ok, %Result{} = result} = Imports.apply(newer, prefilled(newer))
        assert result.created_transactions == 1
        assert result.created_cash_accounts == 0
        assert result.created_securities_accounts == 0

        assert [%Transaction{cash_account_id: target_id}] =
                 Repo.all(from(t in Transaction, where: t.date == ^~D[2025-06-01]))

        assert target_id == ctx.target.id

        before = counts()
        assert {:ok, %Result{created_transactions: 0}} = Imports.apply(newer, prefilled(newer))
        assert counts() == before
      end
    end
  end

  # --- the synthetic export ---------------------------------------------------

  # Two savings accounts in one Portfolio Performance file: a deposit each, a
  # transfer from the old to the new one, one interest booking each on the
  # same day with the same amount (the key-equal pair a merge asks about),
  # and a purchase paid from the old one. The drifted variant writes every
  # number with another precision, as a re-export after an edit inside
  # Portfolio Performance would.
  defp household(variant \\ :exact) do
    digits =
      case variant do
        :exact ->
          %{
            old: "1000.00",
            new: "500.00",
            transfer: "200.00",
            interest: "12.40",
            buy: "500.00",
            shares: "5"
          }

        :drifted ->
          %{
            old: "1000.0",
            new: "500.000",
            transfer: "200.0",
            interest: "12.400",
            buy: "500.0",
            shares: "5.0"
          }
      end

    [
      deposit("Savings (old)", digits.old, "2025-01-02"),
      deposit("Savings", digits.new, "2025-01-03"),
      %{
        "type" => "CASH_TRANSFER",
        "account" => "Savings (old)",
        "otherAccount" => "Savings",
        "date" => "2025-02-01",
        "currency" => "EUR",
        "amount" => num(digits.transfer)
      },
      interest("Savings (old)", digits.interest),
      interest("Savings", digits.interest),
      %{
        "type" => "PURCHASE",
        "account" => "Savings (old)",
        "portfolio" => "Depot",
        "date" => "2025-01-10",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num(digits.buy),
        "shares" => num(digits.shares),
        "security" => @fund
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

  defp interest(account, amount) do
    %{
      "type" => "INTEREST",
      "account" => account,
      "date" => "2025-03-31",
      "currency" => "EUR",
      "amount" => num(amount)
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

  defp merge!(ctx, collapse?) do
    {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
    assert [_pair] = preview.key_equal_pairs

    {:ok, _record, :applied} =
      Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: collapse?
      })

    assert Repo.get!(SecuritiesAccount, named!(SecuritiesAccount, "Depot").id).cash_account_id ==
             ctx.target.id

    :ok
  end

  defp named!(schema, name), do: Repo.one!(from(a in schema, where: a.name == ^name))

  defp assert_created_nothing(%Result{} = result) do
    assert result.created_transactions == 0
    assert result.created_cash_accounts == 0
    assert result.created_securities_accounts == 0
    assert result.created_securities == 0
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
