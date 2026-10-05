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
  # - Rows whose fields joined to one string under that formula hash apart,
  #   also when their fields concatenate to one string with nothing between.
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

    # The separator moved across the boundary: the fields also concatenate
    # to one string ("Depot|A") without any separator between them, so only
    # the length prefixes tell the two rows apart.
    c = buy_in("Depot|", "A")
    d = buy_in("Depot", "|A")

    assert ImportHash.legacy(c, 42) == ImportHash.legacy(d, 42)
    refute ImportHash.compute(c, 42) == ImportHash.compute(d, 42)
  end

  test "a row with the separator in a name names its Sprint 15 hash as its legacy hash" do
    entry = deposit("Cash | EUR")

    assert ImportHash.legacy(entry, 42) == @deposit_hash_sprint15
    refute ImportHash.compute(entry, 42) == @deposit_hash_sprint15
  end

  # User story (ADR-0053 §3, K2; risk-tier: idempotency):
  # As the operator who imported a Portfolio Performance CSV before the
  # importer booked its Gesamtpreis,
  # I want the content hash to keep reading the amount it read then, the
  # file's Betrag, whatever cash the row now books,
  # so that dropping the same file again books nothing twice.
  #
  # Acceptance criteria:
  # - An entry carrying a hash amount is hashed over it, never over the cash
  #   it books: a buy booking 1505.00 whose Betrag was 1502.50 keeps the hash
  #   the Sprint 15 formula gave the row that booked 1502.50.
  # - An entry without a hash amount (a split-off refund, an entry built by
  #   hand) is hashed over its booked amount, as before.
  # - The legacy hash of a separator-bearing row reads the same input.
  test "the hash reads the entry's hash amount, and its booked amount when it has none" do
    rebooked = %{
      buy()
      | gross_amount: Decimal.new("1505.00"),
        hash_amount: Decimal.new("1502.50")
    }

    assert ImportHash.compute(rebooked, 42) == @buy_hash_sprint15
    assert ImportHash.compute(%{buy() | hash_amount: nil}, 42) == @buy_hash_sprint15

    refute ImportHash.compute(%{rebooked | hash_amount: nil}, 42) == @buy_hash_sprint15

    deposit = %{
      deposit("Cash | EUR")
      | gross_amount: Decimal.new("4990"),
        hash_amount: Decimal.new("5000")
    }

    assert ImportHash.legacy(deposit, 42) == @deposit_hash_sprint15
  end
end
