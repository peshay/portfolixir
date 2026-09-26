defmodule Portfolixir.Lifecycle.DepotMergeReimportTest do
  # ADR-0050 §2's post-merge re-import contract for the depot merge (L3b,
  # #328; risk-tier: import idempotency, ADR-0036), its §16 invariants
  # written before the depot merge existed: 1 (re-applying an applied export
  # creates nothing after a depot merge, with and without collapse, every row
  # reported with its layer), 5 (a drifted re-import creates nothing) and 6's
  # depot half (a newer file naming the merged-away depot inserts its new
  # rows once, on the survivor).
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
  alias Portfolixir.Portfolios.SecuritiesAccount

  @fund %{"name" => "Example Depot Fund", "isin" => "DE000EXDPT10", "currency" => "EUR"}

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Depot import target",
        base_currency_code: "EUR"
      })

    assert {:ok, %Result{created_transactions: 7, created_securities_accounts: 2}} =
             Imports.apply(parse!(household()), %{portfolio_id: portfolio.id})

    %{
      portfolio: portfolio,
      source: named!(SecuritiesAccount, "Depot 2"),
      target: named!(SecuritiesAccount, "Depot 1")
    }
  end

  for collapse? <- [false, true] do
    describe "after a depot merge with collapse_key_equal #{collapse?}" do
      # User story:
      # As the operator who merged "Depot 2" into "Depot 1",
      # I want the next import of the same export, byte-identical or drifted,
      # to create nothing,
      # so that the merge never books the history a second time.
      #
      # Acceptance criteria:
      # - A byte-identical re-import, auto-resolved or through the preview's
      #   prefill, creates zero transactions, cash accounts, depots and
      #   securities; each row is reported as a duplicate with the layer that
      #   caught it: `hash` for a row that moved or stayed, `retired` for the
      #   security transfer between the two depots and a collapsed row.
      # - A drifted re-import (other decimal precision, so no content hash
      #   matches) creates nothing either: "Depot 2" resolves to the survivor
      #   as a former name, its rows are caught by the economic layer, and
      #   the transfer between the two is a reported internal transfer.
      @tag collapse: collapse?
      test "a byte-identical and a drifted re-import create nothing", ctx do
        merge!(ctx, ctx.collapse)

        assert Portfolios.get_securities_account(ctx.target.id).former_names == ["Depot 2"]
        before = counts()

        exact = parse!(household())

        for params <- [prefilled(exact), %{portfolio_id: ctx.portfolio.id}] do
          assert {:ok, %Result{} = result} = Imports.apply(exact, params)
          assert_created_nothing(result)
          assert counts() == before

          # Rows: 1 and 2 the deposits, 3 the target's purchase, 4 the
          # source's, 5 the transfer, 6 and 7 the key-equal purchase pair.
          pair = if ctx.collapse, do: :retired, else: :hash

          assert Enum.map(result.duplicate_entries, &{&1.row, &1.layer}) ==
                   [
                     {1, :hash},
                     {2, :hash},
                     {3, :hash},
                     {4, :hash},
                     {5, :retired},
                     {6, pair},
                     {7, :hash}
                   ]
        end

        drifted = parse!(household(:drifted))

        assert Imports.resolve_accounts(drifted).depots == %{
                 "Depot 2" => {:ok, ctx.target.id, :former},
                 "Depot 1" => {:ok, ctx.target.id, :live}
               }

        for params <- [prefilled(drifted), %{portfolio_id: ctx.portfolio.id}] do
          assert {:ok, %Result{} = result} = Imports.apply(drifted, params)
          assert_created_nothing(result)
          assert counts() == before
          assert [%{row: 5}] = result.internal_transfers

          assert Enum.map(result.duplicate_entries, &{&1.row, &1.layer}) ==
                   [
                     {1, :economics},
                     {2, :economics},
                     {3, :economics},
                     {4, :economics},
                     {6, :economics},
                     {7, :economics}
                   ]
        end
      end

      # User story:
      # As the operator importing a later export that still names the
      # merged-away depot,
      # I want its new rows booked once, on the survivor,
      # so that the history stays in one depot.
      #
      # Acceptance criteria:
      # - The newer file's new purchase naming "Depot 2" is inserted on
      #   "Depot 1"; nothing is created, and the older rows are duplicates.
      # - Applying the newer file again creates nothing.
      @tag collapse: collapse?
      test "a newer file naming the old depot lands once on the survivor", ctx do
        merge!(ctx, ctx.collapse)
        newer = parse!(household() ++ [purchase("Giro", "Depot 2", "1", "110.00", "2025-06-01")])

        assert {:ok, %Result{} = result} = Imports.apply(newer, prefilled(newer))
        assert result.created_transactions == 1
        assert result.created_cash_accounts == 0
        assert result.created_securities_accounts == 0

        assert [%Transaction{securities_account_id: depot_id}] =
                 Repo.all(from(t in Transaction, where: t.date == ^~D[2025-06-01]))

        assert depot_id == ctx.target.id

        before = counts()
        assert {:ok, %Result{created_transactions: 0}} = Imports.apply(newer, prefilled(newer))
        assert counts() == before
      end
    end
  end

  # --- the synthetic export ---------------------------------------------------

  # Two depots at one broker in one Portfolio Performance file: a deposit on
  # each cash account, a purchase into each depot, a security transfer from
  # "Depot 2" to "Depot 1", and one purchase on the same day with the same
  # amount into each depot, paid from "Giro" (the key-equal pair a merge asks
  # about). The drifted variant writes every number with another precision,
  # as a re-export after an edit inside Portfolio Performance would.
  defp household(variant \\ :exact) do
    d =
      case variant do
        :exact ->
          %{
            giro: "10000.00",
            giro2: "5000.00",
            first: {"5", "500.00"},
            second: {"3", "330.00"},
            moved: "1",
            pair: {"2", "200.00"}
          }

        :drifted ->
          %{
            giro: "10000.0",
            giro2: "5000.000",
            first: {"5.0", "500.0"},
            second: {"3.00", "330.0"},
            moved: "1.0",
            pair: {"2.0", "200.000"}
          }
      end

    [
      deposit("Giro", d.giro, "2025-01-02"),
      deposit("Giro 2", d.giro2, "2025-01-03"),
      purchase("Giro", "Depot 1", elem(d.first, 0), elem(d.first, 1), "2025-01-10"),
      purchase("Giro 2", "Depot 2", elem(d.second, 0), elem(d.second, 1), "2025-01-20"),
      %{
        "type" => "SECURITY_TRANSFER",
        "portfolio" => "Depot 2",
        "otherPortfolio" => "Depot 1",
        "date" => "2025-02-15",
        "currency" => "EUR",
        "shares" => num(d.moved),
        "security" => @fund
      },
      purchase("Giro", "Depot 2", elem(d.pair, 0), elem(d.pair, 1), "2025-03-01"),
      purchase("Giro", "Depot 1", elem(d.pair, 0), elem(d.pair, 1), "2025-03-01")
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

  defp purchase(account, depot, shares, amount, date) do
    %{
      "type" => "PURCHASE",
      "account" => account,
      "portfolio" => depot,
      "date" => date,
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => num(amount),
      "shares" => num(shares),
      "security" => @fund
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
    {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)
    assert [_pair] = preview.key_equal_pairs
    assert [_transfer] = preview.internal_transfers

    {:ok, _record, :applied} =
      Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: collapse?
      })

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
