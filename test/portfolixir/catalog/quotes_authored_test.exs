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
  # I want the unjournaled quote writer called only by the sync, and no
  # other module writing the quote table at all,
  # so that no authored path can write a quote outside the journal.
  #
  # Acceptance criteria:
  # - In the compiled call graph, only the sync writer (besides the quote
  #   module itself) calls `Quotes.upsert_many/3`, however it is aliased or
  #   imported; the demo seeds, which are not compiled, never name it.
  # - No file in lib/ or the seeds other than the quote module writes the
  #   quote schema or the security_quotes table — by insert_all, delete_all,
  #   update_all, a changeset write or raw SQL — under any alias
  #   (E25 S6 review round, M1).
  test "only the sync writer calls the unjournaled quote upsert" do
    callers =
      xref_callers({Quotes, :upsert_many, 3})
      |> Enum.reject(&(&1 == Quotes))
      |> Enum.sort()

    assert callers == [QuoteSync]

    seeds =
      Enum.filter(seed_files(), &(File.read!(&1) =~ ~r/(Quotes|Catalog\.Quotes)\.upsert_many\b/))

    assert seeds == []
    assert function_exported?(Code.ensure_loaded!(Quotes), :upsert_many, 3)

    writers =
      (Path.wildcard("lib/**/*.ex") ++ seed_files())
      |> Enum.reject(&(&1 == "lib/portfolixir/catalog/quotes.ex"))
      |> Enum.filter(&writes_quotes?(File.read!(&1)))

    assert writers == []
  end

  test "the quote-writer scan catches an aliased, a changeset and a raw-SQL write" do
    for source <- [
          "alias Portfolixir.Catalog.Quote, as: Q\nRepo.insert_all(Q, rows)",
          "alias Portfolixir.Catalog.Quote\nRepo.delete_all(from q in Quote)",
          "alias Portfolixir.Catalog.{Quote, Security}\nRepo.update_all(Quote, set: [])",
          "%Portfolixir.Catalog.Quote{} |> Portfolixir.Catalog.Quote.changeset(a) |> Repo.insert()",
          ~s|Repo.query!("DELETE FROM security_quotes WHERE id = $1", [id])|,
          ~s|Repo.query!("insert into \\"security_quotes\\" (close) values (1)")|
        ] do
      assert writes_quotes?(source), "missed: #{source}"
    end

    refute writes_quotes?(
             "alias Portfolixir.Catalog.Quote, as: SecurityQuote\n%SecurityQuote{} = q"
           )

    refute writes_quotes?(~s|constraint: "security_quotes_security_id_fkey"|)
  end

  # The scripts under priv/ the app runs but does not compile (the demo
  # seeds); a migration writes the schema, not quotes.
  defp seed_files do
    "priv/**/*.exs"
    |> Path.wildcard()
    |> Enum.reject(&String.starts_with?(&1, "priv/repo/migrations/"))
  end

  # Every module of the app that calls `mfa`, from the compiled call graph:
  # an alias or an import resolves at compile time, so none hides a call.
  defp xref_callers({module, function, arity}) do
    {:ok, xref} = :xref.start([])

    try do
      :ok = :xref.set_default(xref, warnings: false, verbose: false)

      {:ok, _modules} =
        :xref.add_directory(xref, to_charlist(Application.app_dir(:portfolixir, "ebin")))

      query = ~c"E || '#{module}':#{function}/#{arity}"
      {:ok, edges} = :xref.q(xref, query)

      edges |> Enum.map(fn {{caller, _f, _a}, _callee} -> caller end) |> Enum.uniq()
    after
      :xref.stop(xref)
    end
  end

  @write_calls ~w(insert_all delete_all update_all insert insert! update update! delete delete!
                  insert_or_update insert_or_update!)

  # A file writes the quote schema when it hands the schema — by its full
  # name or any alias the file gives it — to a Repo write, builds its
  # changeset, or names the table in a writing SQL statement.
  defp writes_quotes?(source) do
    names =
      ["Portfolixir.Catalog.Quote" | quote_aliases(source)]
      |> Enum.map_join("|", &Regex.escape/1)

    calls = Enum.map_join(@write_calls, "|", &Regex.escape/1)

    Regex.match?(~r/\b(#{calls})\(\s*(from\(?\s*\w+\s+in\s+)?(#{names})\b/, source) or
      Regex.match?(~r/\b(#{names})\.changeset\(/, source) or
      Regex.match?(
        ~r/\b(insert\s+into|update|delete\s+from|truncate(\s+table)?)\s+\\?"?security_quotes\b/i,
        source
      )
  end

  defp quote_aliases(source) do
    as =
      Regex.scan(~r/alias Portfolixir\.Catalog\.Quote,\s*as:\s*(\w+)/, source)
      |> Enum.map(fn [_, name] -> name end)

    plain = if source =~ ~r/alias Portfolixir\.Catalog\.Quote\s*$/m, do: ["Quote"], else: []

    grouped =
      if source =~ ~r/alias Portfolixir\.Catalog\.\{[^}]*\bQuote\b[^}]*\}/,
        do: ["Quote"],
        else: []

    as ++ plain ++ grouped
  end
end
