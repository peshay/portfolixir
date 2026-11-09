defmodule Portfolixir.Catalog.ProviderCurrencyAttackTest do
  # Sprint 28 plan D-8, carry-forward 1 (Q3 attack, #1415): the lens that
  # attacks the provider-currency writer's two registrations — B5's
  # `{"Portfolixir.Catalog.QuoteSync", "quote_sync"}` and the identity-freeze
  # sweep's `:provider_currency_only` — with callers and fields they did not
  # name, before integration.
  #
  # A test tagged `:q_attack_red` shows a defect and fails until it is
  # fixed; every other test pins a hole found closed, so it stays closed.
  # Every name, amount and identifier is synthetic.
  #
  # group: :builtin_classifications -- the security merge below may seed the
  # built-in trees, whose classification key is unique (#1047).
  use Portfolixir.DataCase, async: true, group: :builtin_classifications

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios

  @read_at ~U[2026-11-09 08:15:00Z]
  @later ~U[2026-11-09 14:15:00Z]

  defp sync_actor, do: Actor.system_job("quote_sync")

  defp security!(name, currency, attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: name, currency_code: currency, provider: "manual"}, attrs)
      )

    security
  end

  defp stated!(security, currency, read_at \\ @read_at) do
    {:ok, security} = Catalog.put_provider_currency(sync_actor(), security, currency, read_at)
    security
  end

  defp stored(security), do: Catalog.get_security(security.id)

  defp mismatched_ids, do: "currency_mismatch" |> DataQuality.list() |> ids()

  defp ids(rows), do: rows |> Enum.map(& &1.security.id) |> Enum.sort()

  # --- writers the registrations did not name ---------------------------------

  # User story:
  # As the maintainer of the provider-currency column,
  # I want no catalog write but the quote sync's to set it,
  # so that the set's answer is always what a provider stated, never what a
  # caller, a form or an import typed.
  #
  # Acceptance criteria:
  # - `create_security/2` and `update_security/3` with `provider_currency`
  #   and `provider_currency_at` among their attributes leave both null; the
  #   other attributes of the same write land.
  test "create and update never write the provider currency from a caller's attributes" do
    created =
      security!("Typed Line", "EUR", %{
        provider_currency: "USD",
        provider_currency_at: @read_at
      })

    assert %{provider_currency: nil, provider_currency_at: nil} = stored(created)

    {:ok, _updated} =
      Catalog.update_security(Actor.owner_ui(), created, %{
        "name" => "Typed Line renamed",
        "provider_currency" => "GBp",
        "provider_currency_at" => DateTime.to_iso8601(@read_at)
      })

    assert %{name: "Typed Line renamed", provider_currency: nil, provider_currency_at: nil} =
             stored(created)

    refute created.id in mismatched_ids()
  end

  # User story:
  # As the maintainer of `:provider_currency_only`,
  # I want the writer to change the two columns and nothing else, whatever
  # struct its caller hands it,
  # so that the classification is true and not only a comment.
  #
  # Acceptance criteria:
  # - The changeset's changes are exactly `provider_currency` and
  #   `provider_currency_at`.
  # - A caller's struct with a dirty name and currency writes neither: the
  #   write builds on the row it locked.
  test "the writer changes the two columns alone, whatever struct it is handed" do
    security = security!("Pinned Line", "EUR")

    changeset = Security.provider_currency_changeset(security, "USD", @read_at)

    assert changeset.changes |> Map.keys() |> Enum.sort() ==
             [:provider_currency, :provider_currency_at]

    dirty = %{security | name: "Hijacked", currency_code: "USD", is_benchmark: true}
    {:ok, _written} = Catalog.put_provider_currency(sync_actor(), dirty, "USD", @read_at)

    assert %{
             name: "Pinned Line",
             currency_code: "EUR",
             is_benchmark: false,
             provider_currency: "USD"
           } = stored(security)

    [entry] =
      Journal.list_entries(
        resource_type: "security",
        resource_id: to_string(security.id),
        operation: :update
      )

    assert entry.actor_label == "quote_sync"
  end

  # User story:
  # As the maintainer of the two registrations,
  # I want every caller of `Catalog.put_provider_currency/4`, and every write
  # naming either column outside the schema, known by name,
  # so that a second writer — an API controller, an import, a merge — cannot
  # set the column under another actor without a reviewer reading it. B5
  # names a system_job label per module and the identity-freeze sweep a
  # changeset builder per function; neither names the callers of the context
  # function, and the freeze sweep's side-write scan looks for the frozen
  # fields only.
  #
  # Acceptance criteria:
  # - In lib/, the only caller of `put_provider_currency` outside its own
  #   module is `Portfolixir.Catalog.QuoteSync`.
  # - No module in lib/ but the schema names `provider_currency` or
  #   `provider_currency_at` inside a change, cast, bulk write or raw SQL
  #   UPDATE.
  # - Both scans find a synthetic second writer (self-test).
  test "the writer's callers and the column's writes are exactly the registered ones" do
    sources = Map.new(Path.wildcard("lib/**/*.ex"), &{&1, File.read!(&1)})

    callers =
      for {path, source} <- sources,
          path != "lib/portfolixir/catalog.ex",
          module <- put_callers(source),
          uniq: true,
          do: module

    assert callers == ["Portfolixir.Catalog.QuoteSync"]

    writes =
      for {path, source} <- sources,
          path != "lib/portfolixir/catalog/security.ex",
          hit <- column_writes(source),
          do: "#{path}:#{hit}"

    assert writes == [], Enum.join(writes, "\n")

    synthetic = """
    defmodule Portfolixir.SyntheticCurrencyWriter do
      alias Portfolixir.Catalog
      def a(actor, s), do: Catalog.put_provider_currency(actor, s, "USD", DateTime.utc_now())
      def b(s), do: s |> Ecto.Changeset.change(provider_currency: "USD") |> Repo.update()
      def c(id), do: from(s in Security, where: s.id == ^id) |> Repo.update_all(set: [provider_currency_at: nil])
      def d, do: Repo.query!("UPDATE securities SET provider_currency = 'USD'")
      def e(s, p), do: Ecto.Changeset.cast(s, p, [:name, :provider_currency])
    end
    """

    assert put_callers(synthetic) == ["Portfolixir.SyntheticCurrencyWriter"]
    assert length(column_writes(synthetic)) == 4
  end

  # --- hostile provider values -------------------------------------------------

  # User story:
  # As the operator whose provider's answer is foreign text,
  # I want only a three-letter code stored, kept as written,
  # so that the set and its clause never carry control characters, symbols
  # or an unbounded string, and a minor unit stays apart from its major.
  #
  # Acceptance criteria:
  # - A value with a space, a symbol, an invisible character, a newline, four
  #   letters or none is a changeset error; nothing is stored or journaled.
  # - `GBp` on a GBP security is stored and listed; `GBP` is not listed.
  # - A letter-case variant of the own code (`usd` on USD) is stored as
  #   written and listed: the set's stated threshold, "letter case included".
  test "a hostile provider value is refused; case is compared as written" do
    target = security!("Hostile Line", "USD")

    for hostile <- [
          "US D",
          "€€€",
          "US" <> <<0x200B::utf8>> <> "D",
          "USD\n",
          "USDX",
          "",
          "U$D",
          "ＵＳＤ"
        ] do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.put_provider_currency(sync_actor(), target, hostile, @read_at),
             "stored #{inspect(hostile)}"

      assert Keyword.has_key?(changeset.errors, :provider_currency)
    end

    assert %{provider_currency: nil} = stored(target)

    assert Journal.list_entries(resource_type: "security", resource_id: to_string(target.id))
           |> Enum.all?(&(&1.operation == :create))

    pence = stated!(security!("Pence Line", "GBP"), "GBp")
    pound = stated!(security!("Pound Line", "GBP"), "GBP")
    lower = stated!(target, "usd")

    assert lower.provider_currency == "usd"
    listed = mismatched_ids()
    assert pence.id in listed
    refute pound.id in listed
    assert target.id in listed
  end

  # User story:
  # As the operator reading the set,
  # I want a provider that now states something unstorable named per
  # security, and the set's basis to say what that leaves standing,
  # so that a sync refused for a malformed currency is not silent, and the
  # set's answer is read with its window.
  #
  # Acceptance criteria (closing act, QA3):
  # - A security whose provider stated its own currency, then a malformed
  #   one (`€€€`), is refused by the sync under `{:invalid_currency, _}`,
  #   and nothing is stored: the earlier read stands, so the security is not
  #   in the set.
  # - The set's computation basis states that an unstorable value leaves the
  #   earlier read standing.
  test "a malformed stated currency after an agreeing one is refused; the earlier read stands" do
    security = security!("Garbled Line", "EUR", %{ticker_symbol: "GRBL"})

    sync = fn currency ->
      ExUnit.CaptureLog.with_log(fn ->
        QuoteSync.sync_security(stored(security),
          adapter_for: %{"manual" => Yahoo},
          req: [plug: chart_plug(currency)]
        )
      end)
    end

    {_result, _log} = sync.("EUR")
    assert %{provider_currency: "EUR"} = stored(security)
    refute security.id in mismatched_ids()

    {result, log} = sync.("€€€")

    assert %{status: :error, reason: {:invalid_currency, _value}} = result
    assert log =~ "invalid_currency"
    assert %{provider_currency: "EUR", provider_currency_at: at} = stored(security)
    assert at
    refute security.id in mismatched_ids()

    assert DataQuality.computation_basis("currency_mismatch").window =~
             "earlier read standing"
  end

  # User story:
  # As the maintainer of the writer's doc ("written only when the currency
  # differs from the one stored under the row's lock"),
  # I want the comparison to be with the stored row, not the caller's struct,
  # so that a sync holding a struct loaded before another sync's write
  # still records what its provider stated.
  #
  # Acceptance criteria:
  # - With `GBp` stored after the caller loaded its struct (which read
  #   `USD`), a later read of `USD` replaces it and moves the time.
  # - A read equal to the stored row writes nothing and journals nothing,
  #   whatever the caller's struct holds (closing act, QA5).
  test "a stale struct equal to the read skips the write although the row differs" do
    security = security!("Stale Line", "GBP")
    loaded = stated!(security, "USD", @read_at)

    # Another sync (a single sync of this security) stores GBp meanwhile.
    _other = stated!(stored(security), "GBp", ~U[2026-11-09 10:00:00Z])

    assert {:ok, answered} = Catalog.put_provider_currency(sync_actor(), loaded, "USD", @later)

    assert answered.provider_currency == stored(security).provider_currency,
           "answered #{answered.provider_currency}, stored #{stored(security).provider_currency}"

    assert %{provider_currency: "USD", provider_currency_at: @later} = stored(security)

    journaled = fn ->
      Journal.list_entries(resource_type: "security", resource_id: to_string(security.id))
    end

    before = length(journaled.())
    stale = %{stored(security) | provider_currency: nil, provider_currency_at: nil}

    assert {:ok, %{provider_currency: "USD", provider_currency_at: @later}} =
             Catalog.put_provider_currency(sync_actor(), stale, "USD", ~U[2026-11-09 18:00:00Z])

    assert length(journaled.()) == before
    assert %{provider_currency: "USD", provider_currency_at: @later} = stored(security)
  end

  # --- the set after other writers' changes -----------------------------------

  # User story:
  # As the operator who corrects a security's currency to the provider's,
  # I want the set's answer to follow at once, and each finding to say when
  # the provider's currency was read,
  # so that the set never names a security whose currency now agrees.
  #
  # Acceptance criteria:
  # - A refused security (no quotes, no bookings, so its currency is not yet
  #   frozen) is listed; after the operator changes currency_code to the
  #   stated one it is not; the stored provider currency and its time stay.
  # - Its finding while listed carries provider_currency_at.
  test "a currency corrected to the provider's leaves the set; the finding is dated" do
    security = security!("Corrected Line", "EUR")
    stated!(security, "USD", @read_at)

    assert [%{provider_currency: "USD", provider_currency_at: @read_at}] =
             DataQuality.currency_mismatch_findings([stored(security)])

    assert security.id in mismatched_ids()

    {:ok, _} =
      Catalog.update_security(Actor.owner_ui(), stored(security), %{currency_code: "USD"})

    refute security.id in mismatched_ids()
    assert %{provider_currency: "USD", provider_currency_at: @read_at} = stored(security)
  end

  # User story:
  # As the operator whose held security was retired after its series was
  # stored in another currency,
  # I want it named while I still hold it, as `implausible_series` names a
  # held retired security ("its value is as wrong as before"),
  # so that the Overview's clause about the total is not silent on it.
  #
  # Acceptance criteria:
  # - A held, retired security with a mismatching provider currency is in
  #   the set, by list and by count (closing act, QA4); the basis says so.
  test "a held retired security with a mismatching provider currency stays in the set" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Main cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Broker A"
      })

    held = security!("Held Retired", "EUR")
    buy!(%{portfolio: portfolio, depot: depot, cash: cash}, held, ~D[2025-01-10])
    stated!(held, "USD")
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), stored(held), %{is_retired: true})

    assert held.id in mismatched_ids(),
           "a held retired security's value still enters the total the clause warns about"

    assert DataQuality.count("currency_mismatch") == length(mismatched_ids())
    assert DataQuality.computation_basis("currency_mismatch").assumptions =~ "unless it is held"
  end

  # User story:
  # As the operator merging a duplicate whose series the provider stated in
  # another currency,
  # I want the finding to follow the quotes the merge moves onto the kept
  # security, or the merge to say so first,
  # so that a wrong series does not vanish from the set by changing its
  # security id.
  #
  # Acceptance criteria:
  # - After merging a source whose provider stated USD (its own EUR) into a
  #   target no sync has read, the moved quotes stand on the target and the
  #   target is in the set — or the preview names the source's mismatch.
  @tag :q_attack_red
  test "a merge moves a mismatching source's quotes and drops its finding" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Main cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Broker A"
      })

    world = %{portfolio: portfolio, depot: depot, cash: cash}
    target = security!("Merge Fund", "EUR", %{asset_class: "etf"})
    source = security!("Merge Fund", "EUR", %{asset_class: "etf"})
    buy!(world, target, ~D[2025-01-10])
    buy!(world, source, ~D[2025-02-10])

    {:ok, _} =
      Quotes.upsert_many(source.id, [
        %{date: ~D[2025-03-05], close: "152.00", source: "auto"},
        %{date: ~D[2025-03-06], close: "153.25", source: "auto"}
      ])

    stated!(stored(source), "USD")
    assert source.id in mismatched_ids()

    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
    assert Enum.all?(preview.guards, & &1.passed)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.api_token_rw("synthetic-agent"), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    moved =
      Repo.all(
        from(q in SecurityQuote,
          where: q.security_id == ^target.id,
          select: q.date,
          order_by: q.date
        )
      )

    assert moved == [~D[2025-03-05], ~D[2025-03-06]]

    assert target.id in mismatched_ids() or
             inspect(preview) =~ "provider_currency",
           "the merged quotes the provider stated in USD are on the target, and neither " <>
             "the set nor the preview names them"
  end

  # --- helpers ---------------------------------------------------------------

  defp buy!(%{portfolio: portfolio, depot: depot, cash: cash}, security, date) do
    {:ok, tx} =
      Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: "4",
        price: "110.00",
        currency_code: "EUR"
      })

    tx
  end

  defp chart_plug(currency) do
    fn conn ->
      body = %{
        "chart" => %{
          "result" => [
            %{
              "meta" => %{"currency" => currency},
              "timestamp" => [1_715_001_600],
              "indicators" => %{"quote" => [%{"close" => [100.10]}]}
            }
          ]
        }
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end
  end

  # The modules whose code calls `put_provider_currency` on any alias.
  defp put_callers(source) do
    source
    |> module_hits(fn
      {{:., _, [_module, :put_provider_currency]}, _, _args} -> true
      {:put_provider_currency, _, args} when is_list(args) -> true
      _node -> false
    end)
    |> Enum.uniq()
  end

  @columns [:provider_currency, :provider_currency_at]
  @writes ~w(change put_change force_change cast cast_embed update_all insert_all)a

  # "line what" for each write naming either column, and each raw SQL UPDATE.
  defp column_writes(source) do
    ast = Code.string_to_quoted!(source)

    {_ast, hits} =
      Macro.prewalk(ast, [], fn
        {{:., _, [_module, fun]}, meta, args} = node, acc when fun in @writes ->
          {node, hit(acc, names_column?(args), meta, fun)}

        {fun, meta, args} = node, acc when fun in @writes and is_list(args) ->
          {node, hit(acc, names_column?(args), meta, fun)}

        binary, acc when is_binary(binary) ->
          sql? = binary =~ ~r/\bUPDATE\s+securities\s+SET\b[^;]*\bprovider_currency/i
          {binary, if(sql?, do: ["? raw_sql" | acc], else: acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(hits)
  end

  defp hit(acc, false, _meta, _fun), do: acc
  defp hit(acc, true, meta, fun), do: ["#{Keyword.get(meta, :line, "?")} #{fun}" | acc]

  defp names_column?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, true -> {node, true}
        atom, false when atom in @columns -> {atom, true}
        node, false -> {node, false}
      end)

    found
  end

  defp module_hits(source, matcher) do
    source
    |> Code.string_to_quoted!()
    |> walk([], matcher)
  end

  defp walk({:defmodule, _, [{:__aliases__, _, segments}, body]}, outer, matcher),
    do: walk(body, outer ++ segments, matcher)

  defp walk({form, _meta, args} = node, module, matcher) do
    own = if matcher.(node), do: [Enum.join(module, ".")], else: []
    own ++ walk(form, module, matcher) ++ walk(args, module, matcher)
  end

  defp walk({left, right}, module, matcher),
    do: walk(left, module, matcher) ++ walk(right, module, matcher)

  defp walk(list, module, matcher) when is_list(list),
    do: Enum.flat_map(list, &walk(&1, module, matcher))

  defp walk(_leaf, _module, _matcher), do: []
end
