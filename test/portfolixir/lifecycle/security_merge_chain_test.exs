defmodule Portfolixir.Lifecycle.SecurityMergeChainTest do
  # ADR-0050 §2 (O2, "a file already applied is a no-op after any sequence
  # of renames and merges"), §9's resolvability precondition and §16
  # invariants 5 and 14 across a **chain** of security merges (the L3–L5
  # review round, finding F1; risk-tier: import idempotency, ADR-0036).
  #
  # A security created by a name-only import is merged into a survivor that
  # resolves its name; the survivor is later merged into a third security.
  # The first import's identity must still resolve to the live end of the
  # chain, or the second merge must be refused naming it: otherwise a
  # drifted re-import of the first export creates a new security and books
  # its history a second time. The exports are synthetic Portfolio
  # Performance JSON, run through the real importer; every name, amount and
  # identifier is invented.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios

  # Synthetic ISINs whose check digits agree (ISO 6166).
  @isin_t "XS00EXSRCE01"
  @isin_u "XS00EXTGTF03"

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Chain import target",
        base_currency_code: "EUR"
      })

    assert {:ok, %Result{created_securities: 1, created_transactions: 2}} =
             Imports.apply(parse!(export(:exact)), %{portfolio_id: portfolio.id})

    [imported] = Catalog.list_securities()

    {:ok, survivor} =
      Catalog.create_security(agent(), %{
        name: "Fund A",
        isin: @isin_t,
        currency_code: "EUR"
      })

    merge!(imported.id, survivor.id, nil)

    %{portfolio: portfolio, imported: imported, survivor: survivor}
  end

  # User story:
  # As the operator merging a survivor of an earlier merge away in turn,
  # I want the merge refused when a Portfolio Performance export that
  # created the first security would no longer find the history,
  # so that a later import never books that history a second time.
  #
  # Acceptance criteria:
  # - Merging the survivor ("Fund A", resolved by name) into a security named
  #   "Fund B" is refused with identity_unresolvable, on the preview and the
  #   apply, under either identity choice, naming the first security's
  #   identity as its import recorded it (merged_imported, name "Fund A").
  # - Nothing is written, and a drifted re-import of the first export still
  #   creates nothing.
  test "a chain that would strand an earlier import's identity is refused", ctx do
    {:ok, other} =
      Catalog.create_security(agent(), %{name: "Fund B", isin: @isin_u, currency_code: "EUR"})

    assert {:error, {:refused, guards}} =
             Lifecycle.preview_security_merge(ctx.survivor.id, other.id)

    assert %{passed: false, unresolvable: failures} =
             Enum.find(guards, &(&1.code == :identity_unresolvable))

    assert %{identity: :merged_imported, ref: %{name: "Fund A"}} =
             Enum.find(failures, &(&1.security_id == ctx.imported.id))

    assert Enum.sort(Enum.find(failures, &(&1.security_id == ctx.imported.id)).identity_choices) ==
             [:adopt_source_isin, :keep_target_isin]

    before = counts()

    for choice <- [:keep_target_isin, :adopt_source_isin] do
      assert {:error, {:refused, _guards}} =
               Lifecycle.merge_security(agent(), ctx.survivor.id, other.id, %{
                 plan_digest: "sha256:whatever",
                 collapse_key_equal: false,
                 identity_choice: choice
               })
    end

    assert counts() == before
    assert Catalog.get_security(ctx.survivor.id)

    assert {:ok, %Result{} = result} =
             Imports.apply(parse!(export(:drifted)), %{portfolio_id: ctx.portfolio.id})

    assert_created_nothing(result)
    assert counts() == before
  end

  # User story:
  # As the operator merging a survivor into a security that still answers to
  # the name the first import carried,
  # I want the merge to go through and every later import of the first
  # export, byte-identical or drifted, to create nothing,
  # so that a chain of merges keeps the re-import contract.
  #
  # Acceptance criteria:
  # - Merging the survivor into a security named "Fund A" with another ISIN
  #   applies under keep_target_isin.
  # - A byte-identical and a drifted re-import of the first export create
  #   zero transactions, accounts, depots and securities.
  test "a chain that keeps every earlier identity resolvable applies and re-imports as a no-op",
       ctx do
    {:ok, last} =
      Catalog.create_security(agent(), %{name: "Fund A", isin: @isin_u, currency_code: "EUR"})

    merge!(ctx.survivor.id, last.id, :keep_target_isin)
    before = counts()

    for variant <- [:exact, :drifted] do
      assert {:ok, %Result{} = result} =
               Imports.apply(parse!(export(variant)), %{portfolio_id: ctx.portfolio.id})

      assert_created_nothing(result)
      assert counts() == before
    end
  end

  # --- the synthetic export ------------------------------------------------------

  # A deposit and one purchase of a fund the file names only by its name and
  # currency; the drifted variant writes every number with another precision.
  defp export(variant) do
    {deposit, amount, shares} =
      case variant do
        :exact -> {"1000.00", "500.00", "5"}
        :drifted -> {"1000.0", "500.0", "5.0"}
      end

    [
      %{
        "type" => "DEPOSIT",
        "account" => "Giro",
        "date" => "2025-01-02",
        "currency" => "EUR",
        "amount" => num(deposit)
      },
      %{
        "type" => "PURCHASE",
        "account" => "Giro",
        "portfolio" => "Depot",
        "date" => "2025-01-10",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num(amount),
        "shares" => num(shares),
        "security" => %{"name" => "Fund A", "currency" => "EUR"}
      }
    ]
  end

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # --- world ------------------------------------------------------------------

  defp merge!(source_id, target_id, choice) do
    {:ok, preview} = Lifecycle.preview_security_merge(source_id, target_id)

    params =
      %{plan_digest: preview.plan_digest, collapse_key_equal: false}
      |> then(&if choice, do: Map.put(&1, :identity_choice, choice), else: &1)

    assert {:ok, _record, :applied} =
             Lifecycle.merge_security(agent(), source_id, target_id, params)
  end

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
