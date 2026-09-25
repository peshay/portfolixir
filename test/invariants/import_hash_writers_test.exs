defmodule Portfolixir.Invariants.ImportHashWritersTest do
  # ADR-0050 §1, §3 and §16 invariant 4, its database half (risk-tier:
  # idempotency, ADR-0036). A merge removes rows; each removed row's content
  # hash is retired so that no re-import can book the row again (O1). The
  # database refuses a retired hash beside the unique index, and this test
  # sweeps that refusal over EVERY writer of `import_hash` — the Sprint 15
  # lesson: an invariant is swept over every writer of the table, not shown
  # on one path. The static half enumerates the writers from the source, so a
  # third writer fails here until it joins the dynamic half.
  #
  # It also pins §1's premise: a balance anchor or a split never carries an
  # import hash, so the rows a declared restatement removes (§7's folded
  # anchors, §9's collapsed splits) have no hash to retire.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.WorldFixtures

  @lib_sources Path.wildcard("lib/**/*.ex")

  # Every function that can put an `import_hash` on a row, with the table it
  # writes. The transactions writers are the two ADR-0050 §3 names: the
  # importer's applier and `Ledger.create_transaction/3`'s `import_hash:`
  # option, both through the one changeset that casts the field.
  @expected_writers MapSet.new([
                      {"lib/portfolixir/ledger/transaction.ex", :import_changeset, :casts},
                      {"lib/portfolixir/ledger.ex", :transaction_changeset, :import_changeset},
                      {"lib/portfolixir/imports/applier.ex", :insert_new_transaction,
                       :import_changeset},
                      # The retired-hash table itself, written by merges only.
                      {"lib/portfolixir/lifecycle/retired_import_hash.ex", :changeset, :casts}
                    ])

  @changeset_writes ~w(put_change force_change change)a
  @bulk_writes ~w(insert_all update_all)a

  # User story:
  # As the maintainer of the post-merge re-import contract,
  # I want every code path that can put an import hash on a row to be known
  # by name,
  # so that the database refusal of a retired hash is shown on each of them
  # and a new writer cannot appear unswept.
  #
  # Acceptance criteria:
  # - The functions that cast `:import_hash`, or call
  #   `Transaction.import_changeset/2`, are exactly the expected set.
  # - No code writes `import_hash` through put_change/force_change/change,
  #   an insert_all/update_all, or a raw SQL INSERT or UPDATE.
  test "the writers of import_hash are exactly the two ADR-0050 §3 names and the retired table" do
    found = @lib_sources |> Enum.flat_map(&writers_in/1) |> MapSet.new()

    unexpected = found |> MapSet.difference(@expected_writers) |> Enum.sort()
    gone = @expected_writers |> MapSet.difference(found) |> Enum.sort()

    assert unexpected == [],
           "new writers of import_hash — add each to the dynamic sweep below and to " <>
             "@expected_writers (ADR-0050 §3):\n" <> Enum.map_join(unexpected, "\n", &inspect/1)

    assert gone == [],
           "expected writers no longer found — did they move?\n" <>
             Enum.map_join(gone, "\n", &inspect/1)
  end

  test "no code writes import_hash around the changeset" do
    offenders = Enum.flat_map(@lib_sources, &side_writes_in/1)

    assert offenders == [],
           "import_hash written outside Transaction.import_changeset/2:\n" <>
             Enum.join(offenders, "\n")
  end

  # The sweep must not pass vacuously: it finds a writer in a sample source.
  test "the source sweep finds a writer and a side write in a sample" do
    sample = """
    defmodule Sample do
      @fields [:name, :import_hash]
      def a(tx), do: Transaction.import_changeset(tx, %{})
      def b(cs), do: put_change(cs, :import_hash, "x")
      def c, do: Repo.query!("UPDATE transactions SET import_hash = $1", ["x"])
      def d(row, attrs), do: row |> cast(attrs, @fields)
    end
    """

    assert [{"sample.ex", :a, :import_changeset}, {"sample.ex", :d, :casts}] =
             "sample.ex" |> writers_in_source(sample) |> Enum.sort()

    assert [_put_change, _raw_sql] = side_writes_in_source("sample.ex", sample)
  end

  describe "a retired hash is refused at the database, on both writers (§16 invariant 4)" do
    # User story:
    # As the operator who merged an obsolete account into its successor,
    # I want an internal transfer the merge removed to stay removed,
    # so that re-importing the export that still carries it never books it
    # again, whichever writer tries.
    #
    # Acceptance criteria:
    # - A raw insert of a transaction carrying a retired hash is refused by
    #   the database (the backstop beside the unique index); so is an update
    #   that would put a retired hash on an existing row.
    # - `Ledger.create_transaction/3` with a retired `import_hash:` answers a
    #   changeset error on `import_hash` and books nothing.
    # - The applier never books the retired hash: a re-import of the export
    #   whose row was retired inserts no row carrying it.
    setup do
      world = WorldFixtures.base_world(cash_name: "Savings")
      {:ok, record} = Lifecycle.record_merge(Actor.owner_ui(), merge_attrs(world))
      %{world: world, record: record}
    end

    test "a raw insert or update carrying a retired hash is refused", %{
      world: world,
      record: record
    } do
      retire!(record, "synthetic-retired-raw")

      assert_raise Postgrex.Error, ~r/retired by a merge/, fn ->
        with_actor(fn ->
          Repo.query!(
            """
            INSERT INTO transactions
              (portfolio_id, cash_account_id, type, date, currency_code, gross_amount,
               fees, taxes, import_hash, inserted_at, updated_at)
            VALUES ($1, $2, 'deposit', '2026-01-05', 'EUR', 10, 0, 0, $3, now(), now())
            """,
            [world.portfolio.id, world.cash.id, "synthetic-retired-raw"]
          )
        end)
      end

      live = deposit!(world, "2026-01-06")

      assert_raise Postgrex.Error, ~r/retired by a merge/, fn ->
        with_actor(fn ->
          Repo.query!("UPDATE transactions SET import_hash = $1 WHERE id = $2", [
            "synthetic-retired-raw",
            live.id
          ])
        end)
      end

      refute Repo.exists?(from(t in Transaction, where: t.import_hash == "synthetic-retired-raw"))
    end

    test "Ledger.create_transaction/3 answers a changeset error for a retired hash", %{
      world: world,
      record: record
    } do
      retire!(record, "synthetic-retired-ledger")

      assert {:error, changeset} =
               Ledger.create_transaction(
                 Actor.import_session(),
                 deposit_attrs(world, "2026-01-07"),
                 import_hash: "synthetic-retired-ledger"
               )

      assert %{import_hash: ["was retired by a merge and cannot be booked again"]} =
               errors_on(changeset)

      refute Repo.exists?(
               from(t in Transaction, where: t.import_hash == "synthetic-retired-ledger")
             )
    end

    test "the applier never books a retired hash on a re-import", %{world: world} do
      # A Portfolio Performance export with one internal transfer, the
      # ADR-0050 Context's "obsolete account" example.
      preview = parse!(transfer_export())

      assert {:ok, %{created_transactions: 1}} =
               Imports.apply(preview, %{portfolio_id: world.portfolio.id})

      [transfer] =
        Repo.all(
          from(t in Transaction,
            where: t.portfolio_id == ^world.portfolio.id and t.type == "cash_transfer"
          )
        )

      # What a merge of "Savings (old)" into "Savings" does with it (§5, §7
      # step 2): the transfer is deleted, journaled, and its hash retired.
      {:ok, _deleted} = Ledger.delete_transaction(Actor.owner_ui(), transfer)

      {:ok, record} =
        Lifecycle.record_merge(
          Actor.owner_ui(),
          merge_attrs(world, %{source_id: transfer.cash_account_id})
        )

      {:ok, _retired} =
        Lifecycle.retire_import_hash(Actor.owner_ui(), %{
          import_hash: transfer.import_hash,
          former_transaction_id: transfer.id,
          merge_record_id: record.id,
          reason: "internal_transfer"
        })

      # Re-importing the same export: the retired hash never lands. The
      # hash-first applier (§3) recognises it before anything resolves and
      # reports the row as a skip with layer `retired`, never an error; the
      # database refusal above stays the backstop.
      assert {:ok, result} =
               Imports.apply(parse!(transfer_export()), %{portfolio_id: world.portfolio.id})

      assert result.created_transactions == 0
      assert [%{row: 1, layer: :retired}] = result.duplicate_entries

      refute Repo.exists?(from(t in Transaction, where: t.import_hash == ^transfer.import_hash))
    end
  end

  describe "a balance anchor or a split never carries an import hash (§1, §3)" do
    # User story:
    # As the maintainer of the post-merge re-import contract,
    # I want no balance anchor and no split to hold an import hash,
    # so that the rows a merge removes by declared restatement (§7's folded
    # anchors, §9's collapsed splits) leave no hash that would have to be
    # retired.
    #
    # Acceptance criteria:
    # - `Ledger.create_transaction/3` with `import_hash:` refuses a
    #   `balance_adjustment` and a `split` with a changeset error.
    # - The database refuses either kind with a hash from any writer.
    # - The applier builds a row only for the importable kinds: an entry of
    #   either kind never lands as a hashed row.
    setup do
      world = WorldFixtures.base_world()
      security = WorldFixtures.create_security!(name: "Split Co.", ticker: "SPLT")
      %{world: world, security: security}
    end

    test "Ledger.create_transaction/3 refuses a hash on an anchor or a split", %{
      world: world,
      security: security
    } do
      for attrs <- [anchor_attrs(world), split_attrs(world, security)] do
        assert {:error, changeset} =
                 Ledger.create_transaction(Actor.import_session(), attrs,
                   import_hash: "synthetic-#{attrs.type}"
                 )

        assert %{import_hash: ["is never set on a balance anchor or a split"]} =
                 errors_on(changeset)
      end

      refute Repo.exists?(from(t in Transaction, where: not is_nil(t.import_hash)))
    end

    # User story:
    # As an agent editing a booking over the API,
    # I want a re-type of an imported row into an anchor or a split refused on
    # the field I sent,
    # so that the answer names the type I asked for, not an import hash I
    # never set, and no hashed anchor or split appears through an edit.
    #
    # Acceptance criteria:
    # - `Ledger.update_transaction/3` refuses a hashed row's change of type to
    #   `balance_adjustment` or `split` with an error on `type`.
    # - The row keeps its type and its hash.
    test "an imported row is never re-typed into an anchor or a split", %{world: world} do
      {:ok, deposit} =
        Ledger.create_transaction(Actor.import_session(), deposit_attrs(world, "2026-01-05"),
          import_hash: "synthetic-imported-deposit"
        )

      for type <- ~w(balance_adjustment split) do
        assert {:error, changeset} =
                 Ledger.update_transaction(Actor.api_token_rw("synthetic-agent"), deposit, %{
                   "type" => type
                 })

        assert "cannot become a balance anchor or a split: the row was imported" in errors_on(
                 changeset
               ).type
      end

      stored = Repo.get!(Transaction, deposit.id)
      assert stored.type == "deposit"
      assert stored.import_hash == "synthetic-imported-deposit"
    end

    test "the database refuses a hash on an anchor or a split from any writer", %{
      world: world,
      security: security
    } do
      assert_raise Postgrex.Error, ~r/transactions_import_hash_kind_check/, fn ->
        with_actor(fn ->
          Repo.query!(
            """
            INSERT INTO transactions
              (portfolio_id, cash_account_id, type, date, currency_code, gross_amount,
               fees, taxes, import_hash, inserted_at, updated_at)
            VALUES ($1, $2, 'balance_adjustment', '2026-01-08', 'EUR', 100, 0, 0,
                    'synthetic-anchor', now(), now())
            """,
            [world.portfolio.id, world.cash.id]
          )
        end)
      end

      assert_raise Postgrex.Error, ~r/transactions_import_hash_kind_check/, fn ->
        with_actor(fn ->
          Repo.query!(
            """
            INSERT INTO transactions
              (portfolio_id, security_id, type, date, currency_code, fees, taxes,
               split_ratio_numerator, split_ratio_denominator, import_hash,
               inserted_at, updated_at)
            VALUES ($1, $2, 'split', '2026-01-09', 'EUR', 0, 0, 2, 1, 'synthetic-split',
                    now(), now())
            """,
            [world.portfolio.id, security.id]
          )
        end)
      end
    end

    test "the applier never lands an anchor or a split as a hashed row", %{world: world} do
      for kind <- ~w(balance_adjustment split) do
        entry = %Imports.Entry{
          source_row: 1,
          kind: kind,
          date: ~D[2026-01-10],
          currency_code: "EUR",
          gross_amount: Decimal.new("100"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          pp_account_name: "Local Cash"
        }

        preview = %Imports.Preview{format: :json, entries: [entry], errors: []}

        # Whatever the applier answers for a kind no export carries, it must
        # not commit a row of that kind.
        outcome =
          try do
            Imports.apply(preview, %{portfolio_id: world.portfolio.id})
          rescue
            error -> {:raised, error}
          end

        refute match?({:ok, %{created_transactions: created}} when created > 0, outcome)
        refute Repo.exists?(from(t in Transaction, where: t.type == ^kind))
      end
    end
  end

  # --- helpers ---------------------------------------------------------------

  defp merge_attrs(world, overrides \\ %{}) do
    Map.merge(
      %{
        kind: "cash_account",
        source_id: world.cash.id + 1_000_000,
        target_id: world.cash.id,
        portfolio_id: world.portfolio.id,
        source_snapshot: %{"name" => "Savings (old)"},
        manifest: %{},
        plan_digest: "sha256:synthetic-plan"
      },
      overrides
    )
  end

  defp retire!(record, hash) do
    {:ok, retired} =
      Lifecycle.retire_import_hash(Actor.owner_ui(), %{
        import_hash: hash,
        former_transaction_id: 9_000_001,
        merge_record_id: record.id,
        reason: "internal_transfer"
      })

    retired
  end

  defp deposit_attrs(world, date) do
    %{
      type: "deposit",
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      currency_code: "EUR",
      date: Date.from_iso8601!(date),
      gross_amount: Decimal.new("10")
    }
  end

  defp deposit!(world, date) do
    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), deposit_attrs(world, date))
    tx
  end

  defp anchor_attrs(world) do
    %{
      type: "balance_adjustment",
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      currency_code: "EUR",
      date: ~D[2026-01-08],
      gross_amount: Decimal.new("100")
    }
  end

  defp split_attrs(world, security) do
    %{
      type: "split",
      portfolio_id: world.portfolio.id,
      security_id: security.id,
      currency_code: "EUR",
      date: ~D[2026-01-09],
      split_ratio_numerator: 2,
      split_ratio_denominator: 1
    }
  end

  defp with_actor(fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'import_session', true)")
      fun.()
    end)
  end

  defp transfer_export do
    Jason.encode!(%{
      "version" => 1,
      "transactions" => [
        %{
          "type" => "CASH_TRANSFER",
          "account" => "Savings (old)",
          "otherAccount" => "Savings",
          "date" => "2024-05-02",
          "currency" => "EUR",
          "amount" => 250.00
        }
      ]
    })
  end

  defp parse!(body) do
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end

  # --- the source sweep -------------------------------------------------------

  defp writers_in(path), do: writers_in_source(path, File.read!(path))

  defp writers_in_source(path, source) do
    ast = Code.string_to_quoted!(source)
    attributes = module_attributes(ast)

    ast
    |> defs()
    |> Enum.flat_map(fn {name, body} ->
      calls = if calls_import_changeset?(body), do: [{path, name, :import_changeset}], else: []
      casts = if casts_import_hash?(body, attributes), do: [{path, name, :casts}], else: []
      calls ++ casts
    end)
    |> Enum.uniq()
  end

  # `@fields [...]` definitions, so a cast through a module attribute is read
  # as the list it names.
  defp module_attributes(ast) do
    {_ast, attributes} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [value]}]} = node, acc when is_atom(name) ->
          {node, Map.put(acc, name, value)}

        node, acc ->
          {node, acc}
      end)

    attributes
  end

  defp side_writes_in(path), do: side_writes_in_source(path, File.read!(path))

  defp side_writes_in_source(path, source) do
    {_ast, offenders} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {fun, meta, args} = node, acc when fun in @changeset_writes and is_list(args) ->
          {node, maybe_offender(acc, mentions_import_hash?(args), path, meta, fun)}

        {{:., _, [_mod, fun]}, meta, args} = node, acc
        when fun in @changeset_writes or fun in @bulk_writes ->
          {node, maybe_offender(acc, mentions_import_hash?(args), path, meta, fun)}

        {fun, meta, args} = node, acc when fun in @bulk_writes and is_list(args) ->
          {node, maybe_offender(acc, mentions_import_hash?(args), path, meta, fun)}

        binary = node, acc when is_binary(binary) ->
          {node, maybe_offender(acc, raw_sql_write?(binary), path, [], :raw_sql)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(offenders)
  end

  defp maybe_offender(acc, false, _path, _meta, _what), do: acc

  defp maybe_offender(acc, true, path, meta, what),
    do: ["#{path}:#{Keyword.get(meta, :line, "?")} #{what}" | acc]

  # SQL syntax, not prose: a moduledoc may say "UPDATE" and "import_hash" in
  # one paragraph without writing anything.
  defp raw_sql_write?(string) do
    string =~ ~r/\bINSERT\s+INTO\s+\w+[^;]*\bimport_hash\b/ or
      string =~ ~r/\bUPDATE\s+\w+\s+SET\b[^;]*\bimport_hash\b/
  end

  defp defs(ast) do
    {_ast, defs} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body]} = node, acc when kind in [:def, :defp] ->
          {node, [{def_name(head), body} | acc]}

        node, acc ->
          {node, acc}
      end)

    defs
  end

  defp def_name({:when, _meta, [head | _guards]}), do: def_name(head)
  defp def_name({name, _meta, _args}) when is_atom(name), do: name

  defp calls_import_changeset?(body) do
    found?(body, fn
      {{:., _, [{:__aliases__, _, segments}, :import_changeset]}, _, _args} ->
        List.last(segments) == :Transaction

      _other ->
        false
    end)
  end

  defp casts_import_hash?(body, attributes) do
    found?(body, fn
      {:cast, _, [_data, _params, fields | _]} -> cast_fields_mention?(fields, attributes)
      {:cast, _, [_params, fields | _]} -> cast_fields_mention?(fields, attributes)
      {{:., _, [_changeset, :cast]}, _, args} -> cast_fields_mention?(args, attributes)
      _other -> false
    end)
  end

  defp cast_fields_mention?(fields, attributes) do
    found?(fields, fn
      :import_hash -> true
      {:@, _, [{name, _, context}]} when is_atom(context) -> attribute_mentions?(attributes, name)
      _other -> false
    end)
  end

  defp attribute_mentions?(attributes, name) do
    case Map.fetch(attributes, name) do
      {:ok, value} -> mentions_import_hash?(value)
      :error -> false
    end
  end

  defp mentions_import_hash?(ast), do: found?(ast, &(&1 == :import_hash))

  defp found?(ast, predicate) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, true -> {node, true}
        node, false -> {node, predicate.(node)}
      end)

    found
  end
end
