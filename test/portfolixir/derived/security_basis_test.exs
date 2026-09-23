defmodule Portfolixir.Derived.SecurityBasisTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story (2026-09-23, issue #825, ADR-0047 §8, ADR-0039 §2 / C3):
  # As the maintainer of the derived-value layer,
  # I want a per-security data-version basis that every write feeding one
  # security's own series bumps,
  # so that a memo of a security's metrics could be invalidated even for a
  # security no portfolio has ever held (a benchmark, a watch-only candidate).
  #
  # Acceptance criteria:
  # - `DataVersion.security_basis/1` names one security's basis.
  # - A quote write for a security nobody ever transacted bumps its basis.
  # - A quote write for security A does not bump security B's basis.
  # - The portfolio bases (and the global basis) still bump as before.
  # - A split booked for the security, and an edit of the security itself,
  #   bump its basis; a write that feeds no security's own data does not.
  # - A security write the resolver cannot resolve widens to every security.

  defp world(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name <> " Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name <> " Depot"
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp buy!(world, security) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2024-01-02],
        quantity: Decimal.new("1"),
        price: Decimal.new("10"),
        gross_amount: Decimal.new("10"),
        currency_code: "EUR"
      })

    tx
  end

  defp quote!(security, date, close) do
    {:ok, 1} =
      Quotes.upsert_many(security.id, [%{date: date, close: Decimal.new(close), source: "manual"}])
  end

  defp version(security), do: DataVersion.current(DataVersion.security_basis(security.id))

  test "security_basis/1 names one security's basis" do
    assert DataVersion.security_basis(42) == "security:42"
    refute DataVersion.security_basis(42) == DataVersion.portfolio_basis(42)
  end

  test "a quote write for a security no portfolio ever held bumps its basis" do
    benchmark = security!("Benchmark Index Fund")
    assert BlastRadius.for_quote(benchmark.id) == []

    before = version(benchmark)
    quote!(benchmark, ~D[2024-03-01], "101.5")

    assert version(benchmark) > before
  end

  test "a quote write for security A does not bump security B's basis" do
    a = security!("Watch A")
    b = security!("Watch B")

    b_before = version(b)
    quote!(a, ~D[2024-03-01], "10")

    assert version(b) == b_before
  end

  test "a quote write still bumps every holder's portfolio basis and the global basis" do
    holder = world("Security Basis Holder")
    bystander = world("Security Basis Bystander")
    held = security!("Held AG")
    buy!(holder, held)

    holder_basis = DataVersion.portfolio_basis(holder.portfolio.id)
    bystander_basis = DataVersion.portfolio_basis(bystander.portfolio.id)
    holder_before = DataVersion.current(holder_basis)
    bystander_before = DataVersion.current(bystander_basis)
    global_before = DataVersion.current(DataVersion.global_basis())
    security_before = version(held)

    quote!(held, ~D[2024-03-01], "11")

    assert DataVersion.current(holder_basis) > holder_before
    assert DataVersion.current(bystander_basis) == bystander_before
    assert DataVersion.current(DataVersion.global_basis()) > global_before
    assert version(held) > security_before
  end

  test "a split booked for the security bumps its basis, and only its basis" do
    holder = world("Split Basis Holder")
    split = security!("Split Co")
    other = security!("Unsplit Co")
    buy!(holder, split)

    split_before = version(split)
    other_before = version(other)

    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: holder.portfolio.id,
        security_id: split.id,
        type: "split",
        date: ~D[2024-02-02],
        currency_code: "EUR",
        split_ratio_numerator: 2,
        split_ratio_denominator: 1
      })

    assert version(split) > split_before
    assert version(other) == other_before
  end

  test "an edit of the security itself bumps its basis" do
    security = security!("Edited AG")
    before = version(security)

    {:ok, _updated} =
      Catalog.update_security(Actor.owner_ui(), security, %{currency_code: "USD"})

    assert version(security) > before
  end

  test "a write that feeds no security's own data leaves every security basis alone" do
    security = security!("Untouched AG")
    before = version(security)

    _world = world("Unrelated Portfolio")

    assert version(security) == before
  end

  describe "BlastRadius.securities_for_write/2" do
    test "a transaction resolves to its own security" do
      holder = world("Radius Holder")
      security = security!("Radius AG")
      tx = buy!(holder, security)

      assert BlastRadius.securities_for_write("transaction", tx) == [security.id]
    end

    test "a bulk security write resolves to the ids it carries" do
      assert BlastRadius.securities_for_write("security", %{id: nil, security_ids: [3, 1, 3]}) ==
               [1, 3]
    end

    test "an unresolvable security or transaction record widens to :all" do
      assert BlastRadius.securities_for_write("security", %{id: nil}) == :all
      assert BlastRadius.securities_for_write("transaction", %{id: nil}) == :all
    end

    test "an unclassified resource type widens to :all, a classified one answers []" do
      assert BlastRadius.securities_for_write("a_write_kind_nobody_classified", %{id: 1}) == :all
      assert BlastRadius.securities_for_write("portfolio", %{id: 1}) == []
    end

    test "a cash-only transaction names no security" do
      holder = world("Radius Cash")

      {:ok, deposit} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: holder.portfolio.id,
          cash_account_id: holder.cash.id,
          type: "deposit",
          date: ~D[2024-01-02],
          gross_amount: Decimal.new("100"),
          currency_code: "EUR"
        })

      assert BlastRadius.securities_for_write("transaction", deposit) == []
    end

    test "a quote resolves to its own security" do
      assert BlastRadius.securities_for_quote(7) == [7]
      assert BlastRadius.securities_for_quote(nil) == :all
    end
  end
end
