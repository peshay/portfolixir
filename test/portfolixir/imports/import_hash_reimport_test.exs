defmodule Portfolixir.Imports.ImportHashReimportTest do
  # E25 S5, F36 (risk-tier: idempotency, ADR-0036): the idempotency property
  # over the two identity keys whose parts used to be joined with an
  # unescaped separator — the content hash and the security reference key.
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.ImportHash
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp deposit(account) do
    %Entry{
      source_row: 1,
      kind: "deposit",
      date: ~D[2024-01-10],
      currency_code: "EUR",
      gross_amount: Decimal.new("5000"),
      fees: Decimal.new("0"),
      taxes: Decimal.new("0"),
      pp_account_name: account
    }
  end

  # A depot name and a cash-account name are neighbours in the Sprint 15
  # formula's parts, so a separator can move from one to the other.
  defp buy_in(row, depot, cash) do
    security = %{
      isin: "DE000ACME008",
      wkn: nil,
      ticker: nil,
      name: "Synthetic AG",
      currency: "EUR"
    }

    %{buy(row, security) | pp_portfolio_name: depot, pp_account_name: cash}
  end

  defp buy(row, security) do
    %Entry{
      source_row: row,
      kind: "buy",
      date: ~D[2024-04-01],
      currency_code: "EUR",
      gross_amount: Decimal.new("150"),
      fees: Decimal.new("0"),
      taxes: Decimal.new("0"),
      quantity: Decimal.new("1"),
      price: Decimal.new("150"),
      security: security,
      pp_portfolio_name: "Depot",
      pp_account_name: "Cash"
    }
  end

  defp count(portfolio),
    do: Repo.aggregate(from(t in Transaction, where: t.portfolio_id == ^portfolio.id), :count)

  # User story (E25 S5, F36):
  # As the operator re-importing an export I imported before this change,
  # I want every row the database holds recognised by the hash it was stored
  # under, a name carrying the separator included,
  # so that nothing books twice.
  #
  # Acceptance criteria:
  # - A row stored under the Sprint 15 formula is a hash duplicate on
  #   re-import, and the preview counts it as already imported.
  # - A row without the separator is stored under the same hash as before.
  test "a re-import still hits a hash stored under the Sprint 15 formula" do
    portfolio = portfolio!()
    entry = deposit("Cash | EUR")
    preview = %Preview{entries: [entry]}

    assert {:ok, %{created_transactions: 1}} =
             Imports.apply(preview, %{portfolio_id: portfolio.id})

    # The row as an import before this change stored it.
    legacy = ImportHash.legacy(entry, portfolio.id)
    assert is_binary(legacy)

    # The row as an import before this change stored it (a test actor for the
    # journal guard; nothing but the hash changes).
    {:ok, {1, _}} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        from(t in Transaction, where: t.portfolio_id == ^portfolio.id)
        |> Repo.update_all(set: [import_hash: legacy])
      end)

    assert %{total: %{hash: 1, new: 0}} =
             Imports.reimport_counts(preview, portfolio_id: portfolio.id)

    assert {:ok, result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert result.created_transactions == 0
    assert [%{row: 1, layer: :hash}] = result.duplicate_entries
    assert count(portfolio) == 1

    plain = deposit("Cash EUR")

    assert {:ok, %{created_transactions: 1}} =
             Imports.apply(%Preview{entries: [plain]}, %{portfolio_id: portfolio.id})

    assert Repo.exists?(
             from(t in Transaction,
               where: t.import_hash == ^ImportHash.compute(plain, portfolio.id)
             )
           )

    assert ImportHash.legacy(plain, portfolio.id) == nil
  end

  # User story (E25 S5, F36):
  # As an operator whose export carries the separator in account names,
  # I want two different rows to book as two rows,
  # so that one is never skipped as already imported because of the other.
  #
  # Acceptance criteria:
  # - Two bookings whose fields joined to one string under the Sprint 15
  #   formula both book, and a re-import of the file books nothing.
  test "two rows that joined to one string under the Sprint 15 formula both book" do
    portfolio = portfolio!()
    first = buy_in(1, "Depot|A", "Cash")
    second = buy_in(2, "Depot", "A|Cash")
    assert ImportHash.legacy(first, portfolio.id) == ImportHash.legacy(second, portfolio.id)
    preview = %Preview{entries: [first, second]}

    assert {:ok, result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert result.created_transactions == 2
    assert result.duplicate_entries == []

    assert {:ok, again} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert again.created_transactions == 0
    assert length(again.duplicate_entries) == 2
    assert count(portfolio) == 2
  end

  # User story (E25 S5, F36):
  # As an operator deciding each security of an export in the preview,
  # I want two different references to be two decisions,
  # so that a decision for one never applies to the other.
  #
  # Acceptance criteria:
  # - Two references whose fields joined to one string get distinct keys.
  # - At apply, a remap of one does not move the other: the second resolves
  #   on its own (here: created).
  test "distinct references containing the separator get distinct keys and resolve separately" do
    portfolio = portfolio!()

    {:ok, existing} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Remap Target", currency_code: "EUR"})

    first = %{isin: nil, wkn: nil, ticker: "A|B", name: "C", currency: "EUR"}
    second = %{isin: nil, wkn: nil, ticker: "A", name: "B|C", currency: "EUR"}
    entries = [buy(1, first), buy(2, second)]

    first_key = SecurityResolver.key(SecurityResolver.effective_ref(Enum.at(entries, 0)))
    second_key = SecurityResolver.key(SecurityResolver.effective_ref(Enum.at(entries, 1)))
    refute first_key == second_key

    assert {:ok, result} =
             Imports.apply(%Preview{entries: entries}, %{
               portfolio_id: portfolio.id,
               security_mappings: %{first_key => {:existing, existing.id}}
             })

    assert result.created_transactions == 2
    assert result.created_securities == 1

    security_ids =
      from(t in Transaction, where: t.portfolio_id == ^portfolio.id, select: t.security_id)
      |> Repo.all()
      |> MapSet.new()

    assert MapSet.member?(security_ids, existing.id)
    assert MapSet.size(security_ids) == 2
  end

  # User story (E25 S5, F36):
  # As the operator,
  # I want the import refused when one key would stand for two references,
  # so that a decision can never silently apply to a security I did not
  # decide.
  #
  # Acceptance criteria:
  # - unique_keys/2 answers the colliding key when a key function maps two
  #   distinct references to one key, and the keyed references otherwise.
  # - The preview marks both references as a decision nobody can make.
  test "one key for two references fails closed" do
    refs = [
      %{isin: nil, wkn: nil, ticker: "A", name: "One", currency: "EUR"},
      %{isin: nil, wkn: nil, ticker: "B", name: "Two", currency: "EUR"}
    ]

    assert {:ok, keyed} = SecurityResolver.unique_keys(refs)
    assert length(keyed) == 2

    constant = fn _ref -> "0000" end

    assert {:error, {:security_key_collision, "0000"}} =
             SecurityResolver.unique_keys(refs, constant)

    preview = %Preview{entries: [buy(1, Enum.at(refs, 0)), buy(2, Enum.at(refs, 1))]}

    plan = SecurityResolver.resolution_plan(preview, SecurityResolver.load_index(), constant)

    assert [
             %{status: :needs_decision, conflict: %{type: :key_collision}},
             %{status: :needs_decision, conflict: %{type: :key_collision}}
           ] = plan
  end

  # User story (E25 S5 review round, F36):
  # As the operator,
  # I want an apply refused as a whole when one key would stand for two
  # references,
  # so that no decision lands on a security I did not decide and nothing of
  # the file is written.
  #
  # Acceptance criteria:
  # - The apply answers the named collision and rolls back: no transaction,
  #   no security, no account is written.
  test "an apply whose key stands for two references is refused and writes nothing" do
    portfolio = portfolio!()

    refs = [
      %{isin: nil, wkn: nil, ticker: "A", name: "One", currency: "EUR"},
      %{isin: nil, wkn: nil, ticker: "B", name: "Two", currency: "EUR"}
    ]

    preview = %Preview{entries: [buy(1, Enum.at(refs, 0)), buy(2, Enum.at(refs, 1))]}
    securities = Repo.aggregate(Portfolixir.Catalog.Security, :count)

    assert {:error, {:security_key_collision, "0000"}} =
             Imports.apply(preview, %{
               portfolio_id: portfolio.id,
               security_key: fn _ref -> "0000" end
             })

    assert Repo.aggregate(Transaction, :count) == 0
    assert Repo.aggregate(Portfolixir.Catalog.Security, :count) == securities

    assert Repo.aggregate(
             from(c in Portfolixir.Portfolios.CashAccount, where: c.portfolio_id == ^portfolio.id),
             :count
           ) == 0
  end
end
