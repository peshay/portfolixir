defmodule Portfolixir.Derived.RebuildTaskTest do
  use Portfolixir.DataCase, async: false

  alias Mix.Tasks.Portfolixir.Derived.Rebuild
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Value
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance

  # User story (ADR-0039 §6, C5):
  # As the operator of a self-hosted instance,
  # I want drop-and-rebuild as a single command that reports its own runtime,
  # so that the emergency procedure is one step with a known cost, not a
  # procedure with an unknown one.
  #
  # Acceptance criteria:
  # - One command: every stored derived value is dropped and the operative
  #   scopes recomputed through the same request path a page uses.
  # - The command reports how many values it dropped and its own runtime.
  # - The rebuilt store serves values again (rebuildable from transactions
  #   alone — the equality proof lives in the I6 invariant test).

  setup do
    Memo.reset()

    DerivedConfig.enable!(lifetimes: [performance_analysis: :durable])

    Mix.shell(Mix.Shell.Process)

    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    :ok
  end

  test "mix portfolixir.derived.rebuild drops, rebuilds and reports its runtime" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Rebuild",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Rebuild Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Rebuild Depot"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Rebuild AG", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: Date.add(Date.utc_today(), -30),
        quantity: Decimal.new("10"),
        price: Decimal.new("100"),
        gross_amount: Decimal.new("1000"),
        currency_code: "EUR"
      })

    # Materialize one durable value so the drop has something to drop.
    Performance.analysis(portfolio.id)
    assert Repo.aggregate(Value, :count) >= 1

    Rebuild.run([])

    assert_received {:mix_shell, :info, [report]}
    assert report =~ "dropped 1"
    assert report =~ ~r/in \d+ ms/

    # The operative scope was re-materialized through the warm-up path.
    assert Repo.aggregate(Value, :count) >= 1
  end
end
