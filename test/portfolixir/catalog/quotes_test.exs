defmodule Portfolixir.Catalog.QuotesTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes

  # User story:
  # As a local portfolio maintainer,
  # I want quote upserts to be idempotent per (security, date),
  # so that repeated background syncs never duplicate or corrupt the history.
  #
  # Acceptance criteria:
  # - `upsert_many/2` inserts new rows and overwrites the close of existing
  #   rows for the same `(security_id, date)`.
  # - Subsequent syncs from a different source overwrite the previous value
  #   and update `source`.

  defp security_fixture(attrs \\ %{}) do
    base =
      Enum.into(attrs, %{name: "Test Security", currency_code: "USD"})

    {:ok, security} = Catalog.create_security(base)
    security
  end

  defp insert_quote(security, date, close, source \\ "auto") do
    %SecurityQuote{}
    |> SecurityQuote.changeset(%{
      security_id: security.id,
      date: date,
      close: close,
      source: source
    })
    |> Repo.insert!()
  end

  describe "latest/1" do
    test "returns the most recent quote by date" do
      sec = security_fixture()
      insert_quote(sec, ~D[2026-05-01], "100.00")
      latest = insert_quote(sec, ~D[2026-05-15], "120.00")
      insert_quote(sec, ~D[2026-04-01], "80.00")

      assert %SecurityQuote{id: id} = Quotes.latest(sec.id)
      assert id == latest.id
    end

    test "returns nil when no quotes exist" do
      sec = security_fixture()
      assert Quotes.latest(sec.id) == nil
    end
  end

  describe "latest_two/1" do
    test "returns the two most recent quotes in descending date order" do
      sec = security_fixture()
      insert_quote(sec, ~D[2026-05-13], "100")
      insert_quote(sec, ~D[2026-05-14], "110")
      insert_quote(sec, ~D[2026-05-15], "120")

      assert [%SecurityQuote{date: ~D[2026-05-15]}, %SecurityQuote{date: ~D[2026-05-14]}] =
               Quotes.latest_two(sec.id)
    end

    test "returns a single-element list when only one quote exists" do
      sec = security_fixture()
      insert_quote(sec, ~D[2026-05-15], "120")
      assert [%SecurityQuote{date: ~D[2026-05-15]}] = Quotes.latest_two(sec.id)
    end
  end

  describe "at_or_before/2" do
    test "returns the closest quote on or before the requested date" do
      sec = security_fixture()
      insert_quote(sec, ~D[2026-05-01], "100")
      insert_quote(sec, ~D[2026-05-10], "110")

      assert %SecurityQuote{date: ~D[2026-05-10]} =
               Quotes.at_or_before(sec.id, ~D[2026-05-12])

      assert %SecurityQuote{date: ~D[2026-05-01]} =
               Quotes.at_or_before(sec.id, ~D[2026-05-05])
    end

    test "returns nil when no quote precedes the requested date" do
      sec = security_fixture()
      insert_quote(sec, ~D[2026-05-10], "110")
      assert Quotes.at_or_before(sec.id, ~D[2026-04-01]) == nil
    end
  end

  describe "range/3" do
    test "returns quotes within [from, to] in ascending date order" do
      sec = security_fixture()
      insert_quote(sec, ~D[2026-04-01], "80")
      insert_quote(sec, ~D[2026-05-01], "100")
      insert_quote(sec, ~D[2026-05-15], "120")
      insert_quote(sec, ~D[2026-06-01], "130")

      dates =
        Quotes.range(sec.id, ~D[2026-05-01], ~D[2026-05-31])
        |> Enum.map(& &1.date)

      assert dates == [~D[2026-05-01], ~D[2026-05-15]]
    end
  end

  describe "upsert_many/2" do
    test "inserts new quotes and is idempotent for repeated runs" do
      sec = security_fixture()

      rows = [
        %{date: ~D[2026-05-15], close: Decimal.new("123.45"), source: "coingecko"},
        %{date: ~D[2026-05-14], close: Decimal.new("120.10"), source: "coingecko"}
      ]

      assert {:ok, 2} = Quotes.upsert_many(sec.id, rows)
      assert {:ok, 2} = Quotes.upsert_many(sec.id, rows)

      assert length(Quotes.range(sec.id, ~D[2020-01-01], ~D[2030-01-01])) == 2
    end

    test "overwrites the close and source on conflict" do
      sec = security_fixture()
      insert_quote(sec, ~D[2026-05-15], "100", "manual")

      {:ok, 1} =
        Quotes.upsert_many(sec.id, [
          %{date: ~D[2026-05-15], close: Decimal.new("125"), source: "coingecko"}
        ])

      latest = Quotes.latest(sec.id)
      assert Decimal.equal?(latest.close, Decimal.new("125"))
      assert latest.source == "coingecko"
    end

    test "rejects rows with invalid sources" do
      sec = security_fixture()

      assert {:error, _} =
               Quotes.upsert_many(sec.id, [
                 %{date: ~D[2026-05-15], close: Decimal.new("100"), source: "rumour"}
               ])
    end
  end

  describe "performance/2" do
    test "returns the close-vs-baseline ratio as a Decimal" do
      sec = security_fixture()
      insert_quote(sec, Date.add(Date.utc_today(), -30), "100")
      insert_quote(sec, Date.utc_today(), "110")

      # +10 % over the past 30 days → returns Decimal "0.10"
      result = Quotes.performance(sec.id, 30)
      assert Decimal.equal?(Decimal.round(result, 4), Decimal.new("0.1000"))
    end

    test "returns nil when no baseline exists" do
      sec = security_fixture()
      insert_quote(sec, Date.utc_today(), "110")
      assert Quotes.performance(sec.id, 30) == nil
    end
  end
end
