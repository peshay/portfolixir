defmodule Portfolixir.Imports.ImportHashTest do
  # E25 S5, F36 (risk-tier: idempotency, ADR-0036). The content hash is the
  # re-import contract's first check (ADR-0050 §3): it must keep every hash
  # the database already holds, and it must never give two different rows
  # one hash.
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.ImportHash

  # Digests computed with the formula the applier used up to Sprint 15
  # (Applier.compute_hash/2 at d7d4851), for portfolio id 42.
  @buy_hash_sprint15 "6cada709e867e4f6b6b20203c6dd67240e64cc7ce1a5d2f341e51ccd22fcadc8"
  @deposit_hash_sprint15 "fea5b86a06abb29c36bb97181a8e79da75253b357dfa6cbd2f7f6740a310fe87"

  defp buy do
    %Entry{
      source_row: 1,
      kind: "buy",
      date: ~D[2024-01-15],
      time: ~T[10:01:00],
      currency_code: "EUR",
      security: %{
        isin: "DE000ACME008",
        wkn: nil,
        ticker: nil,
        name: "Synthetic AG",
        currency: "EUR"
      },
      quantity: Decimal.new("10"),
      price: Decimal.new("150.25"),
      gross_amount: Decimal.new("1502.50"),
      fees: Decimal.new("2.50"),
      taxes: Decimal.new("0"),
      pp_portfolio_name: "Test-Depot",
      pp_account_name: "Test-Cash"
    }
  end

  defp deposit(account) do
    %Entry{
      source_row: 2,
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
  defp buy_in(depot, cash), do: %{buy() | pp_portfolio_name: depot, pp_account_name: cash}

  # User story (E25 S5, F36):
  # As the operator who re-imports the same Portfolio Performance export,
  # I want every row the database holds to keep the hash it was stored under,
  # and two different rows never to share one,
  # so that a re-import books nothing twice and skips nothing new.
  #
  # Acceptance criteria:
  # - A row with no separator in any field hashes exactly as the Sprint 15
  #   formula did, and has no second hash to consult.
  # - Rows whose fields joined to one string under that formula hash apart.
  # - A row with the separator in a field names the hash the Sprint 15 formula
  #   gave it, so a row stored before the change is still recognised.
  test "a row without the separator keeps the hash the Sprint 15 formula gave it" do
    assert ImportHash.compute(buy(), 42) == @buy_hash_sprint15
    assert ImportHash.legacy(buy(), 42) == nil
  end

  test "rows that joined to one string under the Sprint 15 formula hash apart" do
    a = buy_in("Depot|A", "Cash")
    b = buy_in("Depot", "A|Cash")

    assert ImportHash.legacy(a, 42) == ImportHash.legacy(b, 42)
    refute ImportHash.compute(a, 42) == ImportHash.compute(b, 42)
    refute ImportHash.compute(a, 42) == ImportHash.legacy(a, 42)
  end

  test "a row with the separator in a name names its Sprint 15 hash as its legacy hash" do
    entry = deposit("Cash | EUR")

    assert ImportHash.legacy(entry, 42) == @deposit_hash_sprint15
    refute ImportHash.compute(entry, 42) == @deposit_hash_sprint15
  end
end
