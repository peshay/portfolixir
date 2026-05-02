defmodule Portfolixir.CatalogTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Taxonomies

  setup do
    :ok = Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "creating a currency succeeds" do
    assert {:ok, currency} =
             Catalog.create_currency(%{code: "ABC", name: "Synthetic", minor_units: 2})

    assert currency.code == "ABC"
    assert currency.name == "Synthetic"
    assert currency.minor_units == 2
  end

  test "ensure_mvp_currencies!/0 creates first-run reference currencies idempotently" do
    assert :ok = Catalog.ensure_mvp_currencies!()

    currency_codes = Catalog.list_currencies() |> Enum.map(& &1.code)

    assert "EUR" in currency_codes
    assert "USD" in currency_codes
    assert "GBP" in currency_codes
    assert "CHF" in currency_codes
    assert "SEK" in currency_codes

    count_after_first_run = Repo.aggregate(Currency, :count)

    assert :ok = Catalog.ensure_mvp_currencies!()
    assert Repo.aggregate(Currency, :count) == count_after_first_run
  end

  test "creating duplicate EUR fails" do
    assert :ok = Catalog.ensure_mvp_currencies!()

    assert {:error, changeset} =
             Catalog.create_currency(%{code: "EUR", name: "Euro duplicate", minor_units: 2})

    assert %{code: ["has already been taken"]} = errors_on(changeset)
  end

  test "lowercase currency code is rejected" do
    assert {:error, changeset} =
             Catalog.create_currency(%{code: "eur", name: "Euro", minor_units: 2})

    assert %{code: [error_message]} = errors_on(changeset)
    assert error_message in ["has invalid format", "is invalid"]
  end

  test "invalid code length fails" do
    assert {:error, changeset} =
             Catalog.create_currency(%{code: "EURO", name: "Euro", minor_units: 2})

    assert %{code: ["has invalid format", "should be 3 character(s)"]} = errors_on(changeset)
  end

  test "creating Apple security with USD" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    assert security.name == "Apple Inc."
    assert security.symbol == "AAPL"
    assert security.currency_code == "USD"
  end

  test "creating Apple Frankfurt security with EUR" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL.F",
               exchange_code: "Frankfurt",
               provider_symbol: "AAPL.F",
               currency_code: "EUR"
             })

    assert security.name == "Apple Inc."
    assert security.symbol == "AAPL.F"
    assert security.exchange_code == "Frankfurt"
    assert security.provider_symbol == "AAPL.F"
    assert security.currency_code == "EUR"
  end

  test "creating a security without currency fails" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:error, changeset} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL"})

    assert %{currency_code: ["can't be blank"]} = errors_on(changeset)
  end

  test "creating a security with unknown currency fails" do
    assert {:error, changeset} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "UNKNOWN"
             })

    assert %{currency: ["does not exist"]} = errors_on(changeset)
  end

  test "creating a security without name fails" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:error, changeset} =
             Catalog.create_security(%{symbol: "AAPL", currency_code: "USD"})

    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "creating a security without symbol fails" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:error, changeset} =
             Catalog.create_security(%{name: "Apple Inc.", currency_code: "USD"})

    assert %{symbol: ["can't be blank"]} = errors_on(changeset)
  end

  test "duplicate provider symbol and exchange combination is rejected when both are present" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL.F",
               exchange_code: "Frankfurt",
               provider_symbol: "AAPL.F",
               currency_code: "EUR"
             })

    assert {:error, changeset} =
             Catalog.create_security(%{
               name: "Apple Holding",
               symbol: "AAPL.H",
               exchange_code: "Frankfurt",
               provider_symbol: "AAPL.F",
               currency_code: "EUR"
             })

    assert %{provider_symbol: ["has already been taken"]} = errors_on(changeset)
  end

  test "same provider symbol is allowed when exchange_code is nil" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple US",
               symbol: "AAPL",
               provider_symbol: "AAPL",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple US Class C",
               symbol: "AAPL.CL",
               provider_symbol: "AAPL",
               currency_code: "USD"
             })
  end

  test "same exchange code is allowed when provider_symbol is nil" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple DE",
               symbol: "AAPL.DE",
               exchange_code: "Frankfurt",
               currency_code: "EUR"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple Alternate",
               symbol: "AAPL.H",
               exchange_code: "Frankfurt",
               currency_code: "EUR"
             })
  end

  test "creating a security defaults to active" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert security.active == true
  end

  test "create_security_quote/1 creates a quote for a security" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, quote} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("152.34")
             })

    assert quote.security_id == security.id
    assert quote.date == ~D[2026-05-01]
    assert quote.source == "manual"
    assert quote.currency_code == "USD"
    assert quote.close == Decimal.new("152.34")
  end

  test "create_security_quote/1 accepts open, high, low, close, and volume" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, quote} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "provider",
               currency_code: "USD",
               open: Decimal.new("150.00"),
               high: Decimal.new("153.00"),
               low: Decimal.new("149.00"),
               close: Decimal.new("152.00"),
               volume: Decimal.new("123456.00"),
               metadata: %{"provider" => "test"}
             })

    assert quote.open == Decimal.new("150.00")
    assert quote.high == Decimal.new("153.00")
    assert quote.low == Decimal.new("149.00")
    assert quote.close == Decimal.new("152.00")
    assert quote.volume == Decimal.new("123456.00")
    assert quote.metadata == %{"provider" => "test"}
  end

  test "create_security_quote/1 requires required fields" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:error, changeset} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               source: "manual",
               currency_code: "USD"
             })

    assert %{date: ["can't be blank"], close: ["can't be blank"]} = errors_on(changeset)
  end

  test "create_security_quote/1 rejects negative close" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:error, changeset} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("-10.00")
             })

    assert %{close: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "create_security_quote/1 rejects negative optional price fields" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:error, changeset} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               open: Decimal.new("-1.00"),
               high: Decimal.new("10.00"),
               low: Decimal.new("9.00"),
               close: Decimal.new("10.00"),
               volume: Decimal.new("-2.00")
             })

    assert %{
             open: ["must be greater than or equal to 0"],
             volume: ["must be greater than or equal to 0"]
           } = errors_on(changeset)
  end

  test "create_security_quote/1 rejects duplicate security id, source, and date" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, _} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("10.00")
             })

    assert {:error, changeset} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("11.00")
             })

    assert %{security_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "create_security_quote/1 allows same security id and date with different source" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, _} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("10.00")
             })

    assert {:ok, second_quote} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "provider",
               currency_code: "USD",
               close: Decimal.new("10.50")
             })

    assert second_quote.source == "provider"
    assert second_quote.security_id == security.id
    assert second_quote.id != nil
  end

  test "create_security_quote/1 allows same date and source for different securities" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, apple} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, microsoft} =
             Catalog.create_security(%{name: "Microsoft", symbol: "MSFT", currency_code: "USD"})

    assert {:ok, _} =
             Catalog.create_security_quote(%{
               security_id: apple.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("10.00")
             })

    assert {:ok, second_quote} =
             Catalog.create_security_quote(%{
               security_id: microsoft.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("11.00")
             })

    assert second_quote.security_id == microsoft.id
  end

  test "list_security_quotes/1 returns quotes ordered by date ascending" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    {:ok, oldest_quote} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-01],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("10.00")
      })

    {:ok, newest_quote} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-03],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("12.00")
      })

    {:ok, middle_quote} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-02],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("11.00")
      })

    assert [first, second, third] = Catalog.list_security_quotes(security.id)
    assert first.id == oldest_quote.id
    assert second.id == middle_quote.id
    assert third.id == newest_quote.id
  end

  test "list_security_quotes/2 supports date range filters" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-01],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("10.00")
      })

    {:ok, middle_quote} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-02],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("11.00")
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-03],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("12.00")
      })

    assert [result] =
             Catalog.list_security_quotes(security.id, from: ~D[2026-05-02], to: ~D[2026-05-02])

    assert result.id == middle_quote.id
  end

  test "get_latest_security_quote/1 returns newest quote for a security" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    {:ok, _older_quote} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-01],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("10.00")
      })

    {:ok, newest_quote} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-05-02],
        source: "manual",
        currency_code: "USD",
        close: Decimal.new("11.00")
      })

    assert Catalog.get_latest_security_quote(security.id).id == newest_quote.id
  end

  test "upsert_security_quote/1 updates quote for same security, source, and date" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, original_quote} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("10.00")
             })

    assert {:ok, upserted_quote} =
             Catalog.upsert_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("11.00")
             })

    assert upserted_quote.id == original_quote.id
    assert upserted_quote.close == Decimal.new("11.00")
  end

  test "creating a quote does not create ledger transactions or fund allocations" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    initial_transaction_count = Repo.aggregate(Portfolixir.Ledger.Transaction, :count, :id)

    initial_fund_allocation_count =
      Repo.aggregate(Portfolixir.Catalog.FundAllocation, :count, :id)

    assert {:ok, _} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "USD",
               close: Decimal.new("10.00")
             })

    assert Repo.aggregate(Portfolixir.Ledger.Transaction, :count, :id) ==
             initial_transaction_count

    assert Repo.aggregate(Portfolixir.Catalog.FundAllocation, :count, :id) ==
             initial_fund_allocation_count
  end

  test "creating a security can be inactive" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD",
               active: false
             })

    assert security.active == false
  end

  test "creating a security with WKN persists" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD",
               isin: "US0378331005",
               wkn: "865985"
             })

    assert security.isin == "US0378331005"
    assert security.wkn == "865985"
  end

  test "list_securities returns securities in deterministic order" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Zebra Holdings",
               symbol: "ZB",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, _} =
             Catalog.create_security(%{name: "Apex Fund", symbol: "AXP", currency_code: "USD"})

    securities = Catalog.list_securities()
    assert Enum.map(securities, & &1.name) == ["Apex Fund", "Apple Inc.", "Zebra Holdings"]
  end

  test "list_securities lists active-only by default" do
    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, active_security} =
      Catalog.create_security(%{
        name: "Apple Active",
        symbol: "AAA",
        currency_code: "USD",
        active: true
      })

    {:ok, _inactive_security} =
      Catalog.create_security(%{
        name: "Apple Inactive",
        symbol: "AII",
        currency_code: "USD",
        active: false
      })

    securities = Catalog.list_securities()
    assert Enum.map(securities, & &1.id) == [active_security.id]
  end

  test "list_securities can include inactive securities" do
    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, active_security} =
      Catalog.create_security(%{
        name: "Apple Active",
        symbol: "AAA",
        currency_code: "USD",
        active: true
      })

    {:ok, inactive_security} =
      Catalog.create_security(%{
        name: "Apple Inactive",
        symbol: "AII",
        currency_code: "USD",
        active: false
      })

    securities = Catalog.list_securities(:inactive)
    assert Enum.map(securities, & &1.id) == [inactive_security.id]

    all_securities = Catalog.list_securities(:all)

    assert Enum.map(all_securities, & &1.id) |> Enum.sort() ==
             [active_security.id, inactive_security.id] |> Enum.sort()
  end

  test "migration-style insert defaults to active for existing rows" do
    :ok = Catalog.ensure_mvp_currencies!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{rows: [[_id, active]]} =
      Repo.query!(
        "INSERT INTO securities (name, symbol, currency_code, notes, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, active",
        ["Legacy Security", "LEG", "USD", nil, now, now]
      )

    assert active == true
  end

  test "update_security can mark a security inactive" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    assert {:ok, updated_security} = Catalog.update_security(security, %{active: false})
    assert updated_security.active == false
  end

  test "archive_security marks an active security inactive" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Archive Security",
               symbol: "ARS",
               currency_code: "USD",
               active: true
             })

    assert {:ok, archived_security} = Catalog.archive_security(security)
    assert archived_security.active == false
  end

  test "update_security/2 can update notes or name" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD",
               notes: "original note"
             })

    assert {:ok, updated_security} =
             Catalog.update_security(security, %{
               name: "Apple Corporation",
               notes: "updated note"
             })

    assert updated_security.name == "Apple Corporation"
    assert updated_security.notes == "updated note"
  end

  test "delete_security/1 removes the security" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Apple Inc.", symbol: "AAPL", currency_code: "USD"})

    assert {:ok, _deleted_security} = Catalog.delete_security(security)
    assert_raise Ecto.NoResultsError, fn -> Catalog.get_security!(security.id) end
  end

  test "assigns a category to a security" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    assert {:ok, category} =
             Taxonomies.create_category(%{
               taxonomy_id: taxonomy.id,
               name: "Core ETF",
               description: "Core ETF holdings with broad market exposure"
             })

    assert {:ok, assignment} = Catalog.assign_category_to_security(security.id, category.id)
    assert assignment.security_id == security.id
    assert assignment.category_id == category.id
    assert assignment.weight == Decimal.new("1.0")
  end

  test "duplicate security/category assignment is rejected" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    assert {:ok, category} =
             Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)

    assert {:error, changeset} = Catalog.assign_category_to_security(security.id, category.id)
    assert %{security_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "list_security_categories returns assigned categories with description" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    {:ok, category} =
      Taxonomies.create_category(%{
        taxonomy_id: taxonomy.id,
        name: "Core ETF",
        description: "Core ETF holdings with broad market exposure"
      })

    assert {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)

    assert [listed_category] = Catalog.list_security_categories(security.id)
    assert listed_category.id == category.id
    assert listed_category.name == "Core ETF"
    assert listed_category.description == "Core ETF holdings with broad market exposure"
  end

  test "remove_category_assignment/2 removes a category assignment from security" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    {:ok, category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)
    assert {:ok, _} = Catalog.remove_category_assignment(security.id, category.id)
    assert Catalog.list_security_categories(security.id) == []
  end

  test "remove_category_assignment/2 is no-op and returns clear error when missing" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    {:ok, category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:error, :not_found} = Catalog.remove_category_assignment(security.id, category.id)
  end

  test "assigning category to unknown security fails" do
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Portfolio structure"})

    assert {:ok, category} =
             Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:error, changeset} = Catalog.assign_category_to_security(999_999, category.id)
    assert %{security: ["does not exist"]} = errors_on(changeset)
  end

  test "assigning unknown category to security fails" do
    :ok = Catalog.ensure_mvp_currencies!()

    assert {:ok, security} =
             Catalog.create_security(%{name: "Test ETF", symbol: "TETF", currency_code: "USD"})

    assert {:error, changeset} = Catalog.assign_category_to_security(security.id, 999_999)
    assert %{category: ["does not exist"]} = errors_on(changeset)
  end
end
