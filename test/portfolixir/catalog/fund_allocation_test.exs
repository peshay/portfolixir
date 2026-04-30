defmodule Portfolixir.Catalog.FundAllocationTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  defp ensure_usd_currency! do
    case Repo.get_by(Currency, code: "USD") do
      nil ->
        {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})
        :ok

      %Currency{} ->
        :ok
    end
  end

  defp create_security(attrs \\ %{}) do
    ensure_usd_currency!()

    attrs = Map.put_new(attrs, :currency_code, "USD")

    {:ok, security} =
      Catalog.create_security(
        Map.merge(%{name: "Test Security", symbol: "TSF", currency_code: "USD"}, attrs)
      )

    security
  end

  defp create_allocation(%{security_id: _} = attrs) do
    Catalog.create_fund_allocation(
      Map.merge(%{source: "manual", allocation_type: "region"}, attrs)
    )
  end

  test "creates a region allocation for a security" do
    security = create_security()

    assert {:ok, allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "manual",
               allocation_type: "region"
             })

    assert allocation.security_id == security.id
    assert allocation.source == "manual"
    assert allocation.allocation_type == "region"
    assert allocation.status == "active"
  end

  test "creates country, sector, and asset_class allocations for a security" do
    security = create_security(%{symbol: "SEC-ABC"})

    assert {:ok, country_allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "factsheet",
               allocation_type: "country"
             })

    assert {:ok, sector_allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "factsheet",
               allocation_type: "sector"
             })

    assert {:ok, asset_class_allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "factsheet",
               allocation_type: "asset_class"
             })

    assert country_allocation.id
    assert sector_allocation.id
    assert asset_class_allocation.id
  end

  test "rejects invalid allocation types" do
    security = create_security(%{symbol: "SEC-INVALID"})

    assert {:error, changeset} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "manual",
               allocation_type: "regionally"
             })

    assert %{allocation_type: [_message]} = errors_on(changeset)
  end

  test "keeps source, status, and allocation_type as strings" do
    security = create_security(%{symbol: "SEC-STR"})

    assert {:ok, allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "provider",
               allocation_type: "country"
             })

    assert is_binary(allocation.source)
    assert is_binary(allocation.status)
    assert is_binary(allocation.allocation_type)
  end

  test "rejects duplicate allocations for same security, type, source, and as_of_date" do
    security = create_security(%{symbol: "SEC-DUP"})
    date = Date.utc_today()

    assert {:ok, _existing_allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "manual",
               allocation_type: "sector",
               as_of_date: date
             })

    assert {:error, changeset} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "manual",
               allocation_type: "sector",
               as_of_date: date
             })

    assert %{security_id: [_message]} = errors_on(changeset)
  end

  test "allows same allocation_type, source, and as_of_date for different securities" do
    security_one = create_security(%{symbol: "SEC-UNIQ-ONE"})
    security_two = create_security(%{symbol: "SEC-UNIQ-TWO"})
    date = Date.utc_today()

    assert {:ok, _allocation_one} =
             Catalog.create_fund_allocation(%{
               security_id: security_one.id,
               source: "manual",
               allocation_type: "region",
               as_of_date: date
             })

    assert {:ok, _allocation_two} =
             Catalog.create_fund_allocation(%{
               security_id: security_two.id,
               source: "manual",
               allocation_type: "region",
               as_of_date: date
             })
  end

  test "creates allocation items with decimal weights" do
    assert {:ok, allocation} = create_allocation(%{security_id: create_security().id})

    assert {:ok, item} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Global Equity",
               weight: Decimal.new("0.85")
             })

    assert Decimal.equal?(item.weight, Decimal.new("0.85"))
    assert is_binary(item.label)
  end

  test "rejects duplicate item labels within the same allocation" do
    assert {:ok, allocation} =
             create_allocation(%{security_id: create_security(%{symbol: "SEC-ITEM"}).id})

    assert {:ok, _} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Europe",
               weight: Decimal.new("0.30")
             })

    assert {:error, changeset} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Europe",
               weight: Decimal.new("0.20")
             })

    assert %{label: [_message]} = errors_on(changeset)
  end

  test "allows same item label in different allocations" do
    security = create_security(%{symbol: "SEC-LABEL"})

    assert {:ok, allocation_one} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "manual",
               allocation_type: "country"
             })

    assert {:ok, allocation_two} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "factsheet",
               allocation_type: "region"
             })

    assert {:ok, _item_one} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation_one.id,
               label: "Europe",
               weight: Decimal.new("0.20")
             })

    assert {:ok, _item_two} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation_two.id,
               label: "Europe",
               weight: Decimal.new("0.80")
             })
  end

  test "accepts confidence values between 0 and 1" do
    assert {:ok, allocation} =
             create_allocation(%{security_id: create_security(%{symbol: "SEC-CONF"}).id})

    assert {:ok, _} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Lower bound",
               weight: Decimal.new("0.10"),
               confidence: Decimal.new("0")
             })

    assert {:ok, _} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Upper bound",
               weight: Decimal.new("0.10"),
               confidence: Decimal.new("1")
             })
  end

  test "rejects confidence values above 1" do
    assert {:ok, allocation} =
             create_allocation(%{security_id: create_security(%{symbol: "SEC-CONF-2"}).id})

    assert {:error, changeset} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Too confident",
               weight: Decimal.new("0.10"),
               confidence: Decimal.new("1.01")
             })

    assert %{confidence: [_message]} = errors_on(changeset)
  end

  test "rejects negative weights" do
    assert {:ok, allocation} =
             create_allocation(%{security_id: create_security(%{symbol: "SEC-WEIGHT"}).id})

    assert {:error, changeset} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Negative",
               weight: Decimal.new("-0.10")
             })

    assert %{weight: [_message]} = errors_on(changeset)
  end

  test "lists only allocations for the requested security" do
    security_one = create_security(%{symbol: "SEC-LS1"})
    security_two = create_security(%{symbol: "SEC-LS2"})

    {:ok, allocation_one} =
      Catalog.create_fund_allocation(%{
        security_id: security_one.id,
        source: "manual",
        allocation_type: "region"
      })

    {:ok, allocation_two} =
      Catalog.create_fund_allocation(%{
        security_id: security_two.id,
        source: "manual",
        allocation_type: "country"
      })

    allocations = Catalog.list_fund_allocations_for_security(security_one.id)
    ids = Enum.map(allocations, & &1.id)

    assert ids == [allocation_one.id]
    assert allocation_two.id not in ids
  end

  test "lists only items for the requested allocation" do
    {:ok, allocation} =
      create_allocation(%{security_id: create_security(%{symbol: "SEC-LIST-ITEMS"}).id})

    {:ok, _item_for_target} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: allocation.id,
        label: "Target allocation",
        weight: Decimal.new("0.25")
      })

    other_allocation_security = create_security(%{symbol: "SEC-LIST-OTHER"})

    {:ok, other_allocation} =
      Catalog.create_fund_allocation(%{
        security_id: other_allocation_security.id,
        source: "manual",
        allocation_type: "sector"
      })

    {:ok, other_item} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: other_allocation.id,
        label: "Not for target",
        weight: Decimal.new("0.75")
      })

    items = Catalog.list_fund_allocation_items(allocation.id)
    assert [item] = items
    assert item.label == "Target allocation"
    assert item.id != other_item.id
  end

  test "creating allocations and items does not create ledger transactions" do
    security = create_security(%{symbol: "SEC-NOLG"})
    before_count = Repo.aggregate(Transaction, :count)

    assert {:ok, allocation} =
             Catalog.create_fund_allocation(%{
               security_id: security.id,
               source: "manual",
               allocation_type: "asset_class"
             })

    assert {:ok, _item} =
             Catalog.create_fund_allocation_item(%{
               fund_allocation_id: allocation.id,
               label: "Core",
               weight: Decimal.new("1.0")
             })

    assert before_count == Repo.aggregate(Transaction, :count)
  end
end
