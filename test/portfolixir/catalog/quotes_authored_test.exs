defmodule Portfolixir.Catalog.QuotesAuthoredTest do
  # E25 S6 (#891), G27 and F20 under decision T-9: every authored quote write
  # is journaled with the rows it replaced as its before-image, an authored
  # row is always stored as manual, and a manual pin has a journaled way back
  # to provider data. Only the sync writers stay outside the journal.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.QuoteSync.Fake
  alias Portfolixir.Journal

  setup do
    Fake.clear_responses()

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Northwind Harbour Holdings",
        currency_code: "EUR",
        ticker_symbol: "NWH",
        provider: "coingecko",
        online_id: "northwind-harbour"
      })

    %{security: security, actor: Actor.api_token_rw("agent")}
  end

  defp stored(security) do
    Quote
    |> where([q], q.security_id == ^security.id)
    |> order_by([q], asc: q.date)
    |> Repo.all()
    |> Enum.map(&{&1.date, normal(&1.close), &1.source})
  end

  # A close is stored at its column's scale; the tests compare its value.
  defp normal(%Decimal{} = close), do: close |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp normal(close) when is_binary(close), do: close |> Decimal.new() |> normal()

  defp rows_of(image) do
    Enum.map(image["quotes"], fn row ->
      %{"date" => row["date"], "close" => normal(row["close"]), "source" => row["source"]}
    end)
  end

  defp quote_entries(security) do
    Journal.list_entries(
      resource_type: "security_quotes",
      resource_id: Integer.to_string(security.id)
    )
  end

  defp sync(security, points) do
    Fake.put_response(security.id, {:ok, points})
    QuoteSync.sync_security(security, adapter_for: %{"coingecko" => Fake})
  end

  # User story:
  # As the operator auditing the price history the valuations stand on,
  # I want every quote an agent or a person writes to leave a journal entry
  # holding the closes it replaced,
  # so that an overwritten provider close is never lost without a trace.
  #
  # Acceptance criteria:
  # - An authored upsert over a provider row stores the row as manual and
  #   journals one `upsert` entry under the actor, with the provider's prior
  #   close and source as its before-image and the written row as its after.
  # - The answer names the replaced dates; a new date is not one of them.
  # - A caller naming a provider source still stores a manual row.
  test "an authored upsert over a provider row journals its prior close",
       %{security: security, actor: actor} do
    assert %{status: :ok} = sync(security, [%{date: ~D[2026-03-02], close: Decimal.new("41.10")}])
    assert stored(security) == [{~D[2026-03-02], "41.1", "coingecko"}]
    assert quote_entries(security) == []

    assert {:ok, %{upserted: 2, replaced: [~D[2026-03-02]]}} =
             Catalog.upsert_quotes(actor, security.id, [
               %{"date" => "2026-03-02", "close" => "42.50", "source" => "coingecko"},
               %{"date" => "2026-03-03", "close" => "42.75"}
             ])

    assert stored(security) == [
             {~D[2026-03-02], "42.5", "manual"},
             {~D[2026-03-03], "42.75", "manual"}
           ]

    assert [entry] = quote_entries(security)
    assert entry.operation == :upsert
    assert entry.actor_type == :api_token_rw
    assert entry.actor_label == "agent"

    assert entry.before["security_id"] == security.id

    assert rows_of(entry.before) == [
             %{"date" => "2026-03-02", "close" => "41.1", "source" => "coingecko"}
           ]

    assert rows_of(entry.after) == [
             %{"date" => "2026-03-02", "close" => "42.5", "source" => "manual"},
             %{"date" => "2026-03-03", "close" => "42.75", "source" => "manual"}
           ]
  end

  # User story:
  # As the operator's agent that pinned a close by hand,
  # I want to release the manual rows of a date range back to provider data,
  # journaled,
  # so that the next sync can store the provider's close again.
  #
  # Acceptance criteria:
  # - A release removes only the manual rows inside the range, journals one
  #   `delete` entry holding them as its before-image, and names the dates.
  # - A provider row inside the range and a manual row outside it stay.
  # - After the release, a stubbed sync restores the provider close.
  test "after a release a stubbed sync restores the provider close",
       %{security: security, actor: actor} do
    assert %{status: :ok} =
             sync(security, [
               %{date: ~D[2026-03-02], close: Decimal.new("41.10")},
               %{date: ~D[2026-03-04], close: Decimal.new("40.90")}
             ])

    assert {:ok, %{replaced: [~D[2026-03-02]]}} =
             Catalog.upsert_quotes(actor, security.id, [
               %{"date" => "2026-03-02", "close" => "42.50"},
               %{"date" => "2026-03-09", "close" => "43.00"}
             ])

    # Manual wins (ADR-0028): the sync leaves the pinned row alone.
    assert %{status: :ok, skipped_manual: 1} =
             sync(security, [%{date: ~D[2026-03-02], close: Decimal.new("41.20")}])

    assert {~D[2026-03-02], "42.5", "manual"} in stored(security)

    assert {:ok, %{released: [~D[2026-03-02]]}} =
             Catalog.release_manual_quotes(actor, security.id, ~D[2026-03-01], ~D[2026-03-05])

    assert stored(security) == [
             {~D[2026-03-04], "40.9", "coingecko"},
             {~D[2026-03-09], "43", "manual"}
           ]

    assert [release, _upsert] = quote_entries(security)
    assert release.operation == :delete

    assert rows_of(release.before) == [
             %{"date" => "2026-03-02", "close" => "42.5", "source" => "manual"}
           ]

    assert rows_of(release.after) == []

    assert %{status: :ok, skipped_manual: 0} =
             sync(security, [%{date: ~D[2026-03-02], close: Decimal.new("41.20")}])

    assert {~D[2026-03-02], "41.2", "coingecko"} in stored(security)
  end

  # User story:
  # As the operator reading the journal,
  # I want a quote write or a release that changes nothing to leave no entry,
  # so that the journal records changes rather than requests.
  #
  # Acceptance criteria:
  # - Re-sending a manual row with its stored close writes no entry and
  #   names no replaced date.
  # - A release over a range without manual rows writes no entry.
  test "a quote write or a release that changes nothing leaves no entry",
       %{security: security, actor: actor} do
    rows = [%{"date" => "2026-03-02", "close" => "42.50"}]

    assert {:ok, %{upserted: 1, replaced: []}} = Catalog.upsert_quotes(actor, security.id, rows)
    assert length(quote_entries(security)) == 1

    assert {:ok, %{upserted: 1, replaced: []}} = Catalog.upsert_quotes(actor, security.id, rows)

    assert {:ok, %{released: []}} =
             Catalog.release_manual_quotes(actor, security.id, ~D[2026-04-01], ~D[2026-04-30])

    assert length(quote_entries(security)) == 1
  end

  # User story:
  # As a maintainer keeping ADR-0017's exemption narrow,
  # I want the unjournaled quote writer called only by the sync,
  # so that no authored path can write a quote outside the journal.
  #
  # Acceptance criteria:
  # - Outside the quote module itself, only the sync writer calls
  #   `Quotes.upsert_many`, in lib/ and in the demo seeds.
  test "only the sync writer calls the unjournaled quote upsert" do
    callers =
      ["lib/**/*.ex", "priv/**/*.exs"]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.reject(&(&1 == "lib/portfolixir/catalog/quotes.ex"))
      |> Enum.filter(&(File.read!(&1) =~ ~r/Quotes\.upsert_many\(/))
      |> Enum.sort()

    assert callers == ["lib/portfolixir/catalog/quote_sync.ex"]
    assert function_exported?(Quotes, :upsert_many, 3)
  end
end
