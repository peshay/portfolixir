defmodule Portfolixir.Tax.AllowanceOrdersTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax

  # User story (2026-07-25, ADR-0031, story 19.2):
  # As a local portfolio maintainer,
  # I want the Freistellungsauftrag I instructed per institution and year to be
  # recorded data,
  # so that what the bank actually applied can be compared against what I asked
  # for.
  #
  # Acceptance criteria:
  # - AC-5: one order per (holder, institution, tax_year), amount >= 0.
  # - AC-6: every order write is journaled.
  # - §5a: "comdirect" and "Comdirect" are the SAME order — a case split would
  #   make story 19.4 report a missing instruction that is not missing.

  test "records, lists and deletes an allowance order" do
    {:ok, order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Example Bank",
        tax_year: 2026,
        amount_granted: Decimal.new("1000.00")
      })

    assert order.holder == "Owner"
    assert order.institution == "Example Bank"
    assert Decimal.equal?(order.amount_granted, Decimal.new("1000.00"))

    assert Enum.map(Tax.list_allowance_orders(holder: "Owner"), & &1.id) == [order.id]
    assert Tax.list_allowance_orders(tax_year: 2025) == []

    {:ok, _} = Tax.delete_allowance_order(Actor.owner_ui(), order)
    assert Tax.list_allowance_orders() == []
  end

  # §5a: the binding identity rule stories 19.3-19.5 inherit.
  test "an institution typed in another case updates the same order" do
    {:ok, first} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "comdirect",
        tax_year: 2026,
        amount_granted: Decimal.new("801.00")
      })

    {:ok, second} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "OWNER",
        institution: "Comdirect",
        tax_year: 2026,
        amount_granted: Decimal.new("1000.00")
      })

    assert second.id == first.id
    assert Decimal.equal?(second.amount_granted, Decimal.new("1000.00"))
    assert length(Tax.list_allowance_orders()) == 1

    # The operator's capitalisation is theirs — matching folds case, storage
    # does not.
    assert second.institution == "Comdirect"
    assert Enum.map(Tax.list_allowance_orders(institution: "COMDIRECT"), & &1.id) == [first.id]
  end

  test "internal whitespace is collapsed and an empty institution is rejected" do
    {:ok, order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: " Owner ",
        institution: "Example   Bank  AG",
        tax_year: 2026,
        amount_granted: Decimal.new("500.00")
      })

    assert order.holder == "Owner"
    assert order.institution == "Example Bank AG"

    assert {:error, changeset} =
             Tax.put_allowance_order(Actor.owner_ui(), %{
               holder: "Owner",
               institution: "  ",
               tax_year: 2026,
               amount_granted: Decimal.new("500.00")
             })

    assert %{institution: [_ | _]} = errors_on(changeset)
  end

  test "an order can be deleted by id, and an unknown id is not found" do
    {:ok, order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Example Bank",
        tax_year: 2026,
        amount_granted: Decimal.new("100.00")
      })

    assert {:ok, deleted} = Tax.delete_allowance_order(Actor.owner_ui(), order.id)
    assert deleted.id == order.id
    assert Tax.delete_allowance_order(Actor.owner_ui(), order.id) == {:error, :not_found}
  end

  test "a negative granted amount is rejected" do
    assert {:error, changeset} =
             Tax.put_allowance_order(Actor.owner_ui(), %{
               holder: "Owner",
               institution: "Example Bank",
               tax_year: 2026,
               amount_granted: Decimal.new("-1.00")
             })

    assert %{amount_granted: [_ | _]} = errors_on(changeset)
  end

  test "orders for different years and institutions coexist" do
    for {institution, year} <- [{"Bank A", 2025}, {"Bank A", 2026}, {"Bank B", 2026}] do
      {:ok, _} =
        Tax.put_allowance_order(Actor.owner_ui(), %{
          holder: "Owner",
          institution: institution,
          tax_year: year,
          amount_granted: Decimal.new("300.00")
        })
    end

    assert length(Tax.list_allowance_orders(holder: "Owner")) == 3
    assert length(Tax.list_allowance_orders(holder: "Owner", tax_year: 2026)) == 2
    assert length(Tax.list_allowance_orders(institution: "bank a")) == 2
  end

  test "create, update and delete are journaled" do
    {:ok, order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Example Bank",
        tax_year: 2026,
        amount_granted: Decimal.new("801.00")
      })

    {:ok, _} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Example Bank",
        tax_year: 2026,
        amount_granted: Decimal.new("1000.00")
      })

    {:ok, _} = Tax.delete_allowance_order(Actor.owner_ui(), order)

    operations =
      Journal.list_entries(resource_type: "allowance_order")
      |> Enum.map(& &1.operation)
      |> Enum.sort()

    assert operations == [:create, :delete, :update]
  end

  test "a write that bypasses the journal raises" do
    assert_raise Postgrex.Error, ~r/requires a journal actor/, fn ->
      Repo.insert!(%Tax.AllowanceOrder{
        holder: "Owner",
        institution: "Example Bank",
        tax_year: 2026,
        amount_granted: Decimal.new("1.00")
      })
    end
  end
end
