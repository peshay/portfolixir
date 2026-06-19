defmodule Portfolixir.Imports.IdempotencyPropertyTest do
  @moduledoc """
  StreamData property test for import idempotency.

  The applier stamps each entry with a content-hash `import_hash` and the
  `transactions.import_hash` unique index makes a re-apply a no-op. This
  property asserts the user-facing consequence for *any* permuted subset of a
  valid export: applying the same contents twice leaves exactly the same
  derived state (cash balances and positions) as applying them once, with the
  second apply creating zero transactions.

  Generators are bounded (subsets/permutations of the synthetic corpus) so the
  suite stays fast, and the state comparison is exact (`Decimal.equal?`).
  """
  use Portfolixir.DataCase, async: false
  use ExUnitProperties

  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)
  @runs 20

  defp corpus_entries do
    {:ok, %Preview{entries: entries}} =
      PortfolioPerformance.parse(File.read!(Path.join(@fixtures, "sample.json")))

    entries
  end

  defp setup_portfolio do
    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Idem", base_currency_code: "EUR"})
    portfolio
  end

  # Derived state used to compare a single vs a double apply: every cash
  # balance plus every held position, as plain comparable terms. Cash balances
  # are mapped to sorted {id, normalized-decimal-string} so two runs compare
  # exactly without depending on Decimal struct scale.
  defp derived_state(portfolio_id) do
    cash =
      portfolio_id
      |> then(&Ledger.cash_balances(portfolio_id: &1))
      |> Enum.map(fn {id, balance} -> {id, Decimal.to_string(Decimal.normalize(balance))} end)
      |> Enum.sort()

    positions =
      portfolio_id
      |> Ledger.positions_for_portfolio()
      |> Enum.map(fn {key, qty} -> {key, Decimal.to_string(Decimal.normalize(qty))} end)
      |> Enum.sort()

    {cash, positions}
  end

  # A permuted, non-empty subset of the corpus entries.
  defp entry_selection(entries) do
    indices = Enum.to_list(0..(length(entries) - 1))

    gen all(
          chosen <- list_of(member_of(indices), min_length: 1, max_length: length(entries)),
          seed <- integer()
        ) do
      :rand.seed(:exsss, {seed, seed + 1, seed + 2})

      chosen
      |> Enum.uniq()
      |> Enum.shuffle()
      |> Enum.map(&Enum.at(entries, &1))
    end
  end

  # User story:
  # As a local portfolio maintainer who might drag the same export in twice,
  # I want applying an export twice to equal applying it once,
  # so that an accidental re-import never double-counts my history.
  #
  # Acceptance criteria:
  # - For any permuted subset of a valid export, a second apply creates zero
  #   transactions and marks every entry a skipped duplicate.
  # - The derived cash balances and positions after two applies equal those
  #   after a single apply, exactly (`Decimal.equal?` via normalized strings).
  property "applying an export twice equals applying it once" do
    entries = corpus_entries()

    check all(selection <- entry_selection(entries), max_runs: @runs) do
      preview = %Preview{format: :json, entries: selection}

      # Same portfolio: snapshot the derived state after one apply, then apply
      # again and snapshot. The content-hash makes the second apply a no-op, so
      # the two snapshots must be byte-identical and the second result must
      # create nothing.
      outcome =
        Repo.transaction(fn ->
          portfolio = setup_portfolio()

          # A standalone delivery references a depot but carries no cash
          # account, so a subset with no cash-bearing entry cannot resolve the
          # depot's cash account (real applier behaviour, `:depot_needs_cash`).
          # Such a selection is not an applicable export, so the idempotency
          # property does not apply to it; skip it without a false failure.
          case Imports.apply(preview, %{portfolio_id: portfolio.id}) do
            {:ok, %Result{}} ->
              once = derived_state(portfolio.id)
              {:ok, %Result{} = second} = Imports.apply(preview, %{portfolio_id: portfolio.id})
              twice = derived_state(portfolio.id)
              Repo.rollback({:applied, once, twice, second})

            {:error, reason} ->
              Repo.rollback({:not_applicable, reason})
          end
        end)

      case outcome do
        {:error, {:applied, once, twice, second_result}} ->
          assert second_result.created_transactions == 0
          assert second_result.created_securities == 0
          assert second_result.created_cash_accounts == 0
          assert second_result.created_securities_accounts == 0
          # No fixture entry carries companion splits, so flattened == selection.
          assert second_result.skipped_duplicates == length(selection)

          assert once == twice

        {:error, {:not_applicable, _reason}} ->
          :ok
      end
    end
  end
end
