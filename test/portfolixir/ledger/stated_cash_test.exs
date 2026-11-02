defmodule Portfolixir.Ledger.StatedCashTest do
  # ADR-0053, amendment of 2026-11-02 (#1371). Risk tier (how a stored
  # booking is corrected, ADR-0036): every figure is an exact Decimal.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @required "is required when quantity, price, fees or taxes change on a booking that stores its cash"

  # Synthetic figures only: an imported buy, 10 at 80.00 EUR, fees 5.00,
  # taxes 1.00, its cash 806.00 as the file stated it.
  setup do
    world = base_world(name: "Stated Cash", cash_name: "SC Cash", depot_name: "SC Depot")
    security = create_security!(name: "Stated Cash Co", ticker: "SCC", currency: "EUR")

    {:ok, buy} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        trade_attrs(world, security, %{
          type: "buy",
          quantity: "10",
          price: "80.00",
          fees: "5.00",
          taxes: "1.00",
          gross_amount: "806.00"
        }),
        import_hash: String.duplicate("b", 64)
      )

    %{world: world, security: security, buy: buy}
  end

  defp trade_attrs(world, security, figures) do
    Map.merge(
      %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        date: ~D[2026-03-02],
        currency_code: "EUR"
      },
      figures
    )
  end

  defp edit(row, attrs), do: Ledger.update_transaction(Actor.owner_ui(), row, attrs)

  defp messages(changeset, field) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key)) |> to_string()
      end)
    end)
    |> Map.get(field, [])
  end

  # User story (#1371):
  # As the operator correcting an imported buy whose cash is the broker's
  # figure,
  # I want an edit of its quantity, price, fees or taxes to state the cash
  # too, checked to the cent against the new figures,
  # so that the cash balance and the lot never read two costs for one
  # booking, and the broker's figure is never overwritten by a guess.
  #
  # Acceptance criteria (ADR-0053, amendment of 2026-11-02, point 1):
  # - A change of quantity, price, fees or taxes without gross_amount is
  #   refused on gross_amount, and the row is unchanged.
  # - Stated gross_amount within a cent of quantity × price + fees + taxes
  #   (a buy), plus the price's own rounding (quantity × half a unit of its
  #   last digit, at two places at least), is stored with the new figures;
  #   beyond that it is refused,
  #   the message naming the expected figure.
  # - An update that changes none of the four (a note, a date) keeps the
  #   stored cash without stating it, even on a row whose cash already
  #   misses its figures.
  describe "a buy that stores its cash" do
    test "a price edit without gross_amount is refused and changes nothing", %{buy: buy} do
      assert {:error, changeset} = edit(buy, %{"price" => "81.00"})
      assert messages(changeset, :gross_amount) == [@required]

      stored = Repo.get!(Transaction, buy.id)
      assert Decimal.equal?(stored.price, Decimal.new("80.00"))
      assert Decimal.equal?(stored.gross_amount, Decimal.new("806.00"))
    end

    test "each of quantity, fees and taxes triggers the rule", %{buy: buy} do
      for attrs <- [%{"quantity" => "11"}, %{"fees" => "6.00"}, %{"taxes" => "0"}] do
        assert {:error, changeset} = edit(buy, attrs)
        assert messages(changeset, :gross_amount) == [@required]
      end
    end

    test "a stated blank cash is not a cash", %{buy: buy} do
      assert {:error, changeset} = edit(buy, %{"price" => "81.00", "gross_amount" => nil})
      assert messages(changeset, :gross_amount) == [@required]
    end

    test "a price edit stating the cash the new figures give is stored", %{buy: buy} do
      assert {:ok, updated} = edit(buy, %{"price" => "81.00", "gross_amount" => "816.00"})
      assert Decimal.equal?(updated.price, Decimal.new("81.00"))
      assert Decimal.equal?(updated.gross_amount, Decimal.new("816.00"))
    end

    test "a stated cash within a cent is stored as stated", %{buy: buy} do
      assert {:ok, updated} = edit(buy, %{"price" => "81.00", "gross_amount" => "816.01"})
      assert Decimal.equal?(updated.gross_amount, Decimal.new("816.01"))
    end

    test "a stated cash beyond its tolerance is refused naming the expected figure",
         %{buy: buy} do
      assert {:error, changeset} = edit(buy, %{"price" => "81.00", "gross_amount" => "806.00"})

      assert messages(changeset, :gross_amount) == [
               "does not match quantity × price, fees and taxes — expected 816.00"
             ]

      # 10 at 81.00: a cent plus the price's own rounding, 10 × 0.005.
      assert {:ok, _} = edit(buy, %{"price" => "81.00", "gross_amount" => "816.06"})
      assert {:ok, _} = edit(buy, %{"price" => "80.00", "gross_amount" => "806.00"})
      assert {:error, _} = edit(buy, %{"price" => "81.00", "gross_amount" => "816.07"})
      assert Decimal.equal?(Repo.get!(Transaction, buy.id).gross_amount, Decimal.new("806.00"))
    end

    test "a note or a date edit keeps the cash without stating it", %{buy: buy} do
      assert {:ok, noted} = edit(buy, %{"notes" => "checked", "date" => "2026-03-03"})
      assert Decimal.equal?(noted.gross_amount, Decimal.new("806.00"))
      assert noted.date == ~D[2026-03-03]
    end

    test "an unchanged figure sent again does not trigger the rule", %{buy: buy} do
      assert {:ok, same} = edit(buy, %{"price" => "80", "fees" => "5", "notes" => "same"})
      assert Decimal.equal?(same.gross_amount, Decimal.new("806.00"))
    end
  end

  # Acceptance criteria (a sell, whose cash is net of fees and taxes):
  # - The relation is quantity × price − fees − taxes.
  test "a sell states the cash net of its fees and taxes", %{world: world, security: security} do
    {:ok, sell} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        trade_attrs(world, security, %{
          type: "sell",
          date: ~D[2026-03-09],
          quantity: "4",
          price: "90.00",
          fees: "3.00",
          taxes: "2.50",
          gross_amount: "354.50"
        })
      )

    assert {:error, changeset} = edit(sell, %{"price" => "91.00"})
    assert messages(changeset, :gross_amount) == [@required]

    assert {:error, changeset} = edit(sell, %{"price" => "91.00", "gross_amount" => "369.50"})

    assert messages(changeset, :gross_amount) == [
             "does not match quantity × price, fees and taxes — expected 358.50"
           ]

    assert {:ok, updated} = edit(sell, %{"price" => "91.00", "gross_amount" => "358.50"})
    assert Decimal.equal?(updated.gross_amount, Decimal.new("358.50"))
  end

  # Acceptance criteria (the amendment's point 1, "on every write"):
  # - Turning the buy into a sell flips the relation's sign, so it states
  #   the cash too: alone it is refused on gross_amount; with the buy's
  #   806.00 it is refused naming 794.00 (10 × 80.00 − 5.00 − 1.00); with
  #   794.00 it is stored.
  test "a buy turned into a sell states its cash", %{buy: buy} do
    assert {:error, changeset} = edit(buy, %{"type" => "sell"})
    assert messages(changeset, :gross_amount) == [@required]

    assert {:error, changeset} = edit(buy, %{"type" => "sell", "gross_amount" => "806.00"})

    assert messages(changeset, :gross_amount) == [
             "does not match quantity × price, fees and taxes — expected 794.00"
           ]

    assert Repo.get!(Transaction, buy.id).type == "buy"

    assert {:ok, sell} = edit(buy, %{"type" => "sell", "gross_amount" => "794.00"})
    assert sell.type == "sell"
    assert Decimal.equal?(sell.gross_amount, Decimal.new("794.00"))
  end

  # Acceptance criteria (what the rule leaves alone):
  # - A trade without a stored cash amount still follows its figures.
  test "a trade without a stored cash amount takes a price edit alone",
       %{world: world, security: security} do
    {:ok, plain} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        trade_attrs(world, security, %{type: "buy", quantity: "2", price: "50"})
      )

    assert {:ok, updated} = edit(plain, %{"price" => "51"})
    assert is_nil(updated.gross_amount)
  end
end
