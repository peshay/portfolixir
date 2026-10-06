defmodule Portfolixir.Buckets.ScopeSeed do
  @moduledoc """
  The ADR-0024 portfolio migration (epic story 2, modifications 2 and 6), as
  the migration `20260712130000_seed_portfolio_scope_buckets` seeds it through
  `Portfolixir.Buckets.seed_portfolio_scope_buckets/1` and removes it through
  `Portfolixir.Buckets.rollback_portfolio_scope_seed/1`: per portfolio one
  exclusive-dimension ("scope") bucket and one view including exactly that
  bucket, both carrying the portfolio id in `source_portfolio_id`, and every
  depot and cash account of the portfolio tagged with the bucket.

  **Frozen to that migration's version (#1042, Sprint 19 B1),** as
  `Portfolixir.Tax.BuiltinSeed` is to its own (#1015). Applied migrations are
  immutable (CI rejects any change to one), so the code they call is what has
  to stay put. Up to Sprint 18 the seed read depots and cash accounts through
  today's schemas, and an upgrade from `20260712120000` or earlier over an
  instance holding either stopped here on `former_names`, a column a later
  migration adds. This module names nothing that changes with the schema: the
  columns of `portfolios`, `securities_accounts`, `cash_accounts`, `buckets`,
  `views`, `view_include_buckets`, the two assignment tables and
  `audit_journal` as they stand at that version, the actor setting the
  `buckets` guard reads, the journal's snapshot shape
  (`Portfolixir.Journal.Serializer`: every column of the row, timestamps in
  ISO 8601) and the name bound, counted in code points the way
  `Portfolixir.Input.Text` counts it, all written out here as plain SQL. Change
  nothing here for a later schema; a later migration that needs these tables
  writes its own SQL.

  Two things the context's writers do are left out on purpose, because
  nothing they serve exists at that version:

    * **the derived-data invalidation** (`derived_values` arrives with
      `20260814120000`). A seed at head is run by the
      `portfolixir.seed_scope_buckets` task, which invalidates after it;
    * **the journaled rewrites of a bucket's memberships before its delete,**
      and the protection of a view a policy rule reads. The rollback deletes
      the seeded views and buckets and lets the foreign keys of that version
      take their links, as they did then. Only the `settings` notice key is
      cleared beyond that version's tables, and only where the table exists.

  The whole seed, and the whole rollback, is one transaction.

  - **Idempotent:** a portfolio that already has its seeded bucket and view is
    not seeded again, and an account already carrying its bucket is skipped,
    so a re-run writes nothing and journals nothing.
  - **The operator's scope wins:** an account that already carries a
    different scope bucket is skipped and counted in
    `skipped_existing_scope`; its other tags are kept.
  - **Reversible:** the rollback deletes only records carrying the seed
    marker; buckets, views and assignments the operator made survive.
  """

  alias Portfolixir.Actor

  @actor_setting "portfolixir.journal_actor"

  # The dashboard notice the rollback forgets (`Portfolixir.Settings`), so a
  # later re-seed is announced again. The `settings` table arrives with the
  # next migration, so this is the one write past the seed's version.
  @notice_key "portfolio_migration_notice_dismissed"

  @scope_dimension "scope"
  @fallback_suffix " (Portfolio)"
  @name_max_length 100

  @bucket_columns ~w(id name color dimension source_portfolio_id inserted_at updated_at)

  # The assignment table of each account kind, its owner column and the
  # resource type its journal entries are filed under.
  @owners [
    {"securities_accounts", "securities_account_buckets", "securities_account_id",
     "depot_bucket_assignment"},
    {"cash_accounts", "cash_account_buckets", "cash_account_id", "cash_account_bucket_assignment"}
  ]

  @empty %{buckets_created: 0, views_created: 0, accounts_tagged: 0, skipped_existing_scope: 0}

  @type summary :: %{
          buckets_created: non_neg_integer(),
          views_created: non_neg_integer(),
          accounts_tagged: non_neg_integer(),
          skipped_existing_scope: non_neg_integer()
        }

  @type failure :: %{portfolio_id: integer(), portfolio_name: String.t(), reason: term()}

  @doc """
  Seeds every portfolio's scope bucket and view and tags its accounts, under
  `actor`. Returns the summary, or the portfolio the seed stopped at, with
  nothing written.
  """
  @spec seed(module(), Actor.t()) :: {:ok, summary()} | {:error, failure()}
  def seed(repo, %Actor{} = actor) do
    journaled(repo, actor, fn ->
      %{rows: portfolios} = repo.query!("SELECT id, name FROM portfolios ORDER BY id")

      Enum.reduce_while(portfolios, @empty, fn [id, name], acc ->
        case seed_portfolio(repo, actor, %{id: id, name: name}, acc) do
          {:ok, acc} ->
            {:cont, acc}

          {:error, reason} ->
            repo.rollback(%{portfolio_id: id, portfolio_name: name, reason: reason})
        end
      end)
    end)
  end

  @doc """
  Deletes the seeded buckets, each journaled under `actor`, and the seeded
  views, and forgets the dismissed migration notice. Nothing the operator made
  is touched.
  """
  @spec rollback(module(), Actor.t()) :: :ok
  def rollback(repo, %Actor{} = actor) do
    {:ok, :ok} =
      journaled(repo, actor, fn ->
        %{columns: columns, rows: rows} =
          repo.query!(
            "SELECT #{Enum.join(@bucket_columns, ", ")} FROM buckets " <>
              "WHERE source_portfolio_id IS NOT NULL ORDER BY id FOR UPDATE"
          )

        Enum.each(rows, fn values ->
          bucket = columns |> Enum.zip(values) |> Map.new()
          repo.query!("DELETE FROM buckets WHERE id = $1", [bucket["id"]])
          # The journal files a deletion with the deleted row on both sides.
          journal!(
            repo,
            actor,
            {"delete", "bucket", bucket["id"]},
            snapshot(bucket),
            snapshot(bucket)
          )
        end)

        repo.query!("DELETE FROM views WHERE source_portfolio_id IS NOT NULL")
        forget_notice(repo)
        :ok
      end)

    :ok
  end

  # A statement the database refuses stops the seed at its portfolio, in the
  # shape the context's writers answered a refused write with.
  defp seed_portfolio(repo, actor, portfolio, acc) do
    {bucket, acc} = ensure_bucket(repo, actor, portfolio, acc)
    acc = ensure_view(repo, portfolio, bucket, acc)
    tag_accounts(repo, actor, portfolio, bucket, acc)
  rescue
    error in Postgrex.Error -> {:error, error}
  end

  defp ensure_bucket(repo, actor, portfolio, acc) do
    case repo.query!(
           "SELECT id, name FROM buckets WHERE source_portfolio_id = $1 ORDER BY id LIMIT 1",
           [portfolio.id]
         ).rows do
      [[id, name]] ->
        {%{id: id, name: name}, acc}

      [] ->
        {create_bucket(repo, actor, portfolio), Map.update!(acc, :buckets_created, &(&1 + 1))}
    end
  end

  # The bucket's name must be free among buckets AND views, so the view
  # created right after it can carry the same name.
  defp create_bucket(repo, actor, portfolio) do
    name =
      available_name(repo, portfolio.name, """
      SELECT NOT EXISTS (SELECT 1 FROM buckets WHERE name = $1)
         AND NOT EXISTS (SELECT 1 FROM views WHERE name = $1)
      """)

    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    %{rows: [[id]]} =
      repo.query!(
        """
        INSERT INTO buckets (name, dimension, source_portfolio_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $4)
        RETURNING id
        """,
        [name, @scope_dimension, portfolio.id, now]
      )

    bucket = %{
      "id" => id,
      "name" => name,
      "color" => nil,
      "dimension" => @scope_dimension,
      "source_portfolio_id" => portfolio.id,
      "inserted_at" => now,
      "updated_at" => now
    }

    journal!(repo, actor, {"create", "bucket", id}, nil, snapshot(bucket))
    %{id: id, name: name}
  end

  # The view and its single include link. Views are not journaled (ADR-0018
  # §5). The view prefers the bucket's exact name, so the pair reads as one
  # unit; only a view-name collision falls to the numbered variants.
  defp ensure_view(repo, portfolio, bucket, acc) do
    case repo.query!("SELECT 1 FROM views WHERE source_portfolio_id = $1 LIMIT 1", [
           portfolio.id
         ]).rows do
      [_seeded] ->
        acc

      [] ->
        name =
          available_name(
            repo,
            bucket.name,
            "SELECT NOT EXISTS (SELECT 1 FROM views WHERE name = $1)"
          )

        now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

        %{rows: [[view_id]]} =
          repo.query!(
            """
            INSERT INTO views (name, include_all, source_portfolio_id, inserted_at, updated_at)
            VALUES ($1, false, $2, $3, $3)
            RETURNING id
            """,
            [name, portfolio.id, now]
          )

        repo.query!("INSERT INTO view_include_buckets (view_id, bucket_id) VALUES ($1, $2)", [
          view_id,
          bucket.id
        ])

        Map.update!(acc, :views_created, &(&1 + 1))
    end
  end

  # The depots first, then the cash accounts, each in id order.
  defp tag_accounts(repo, actor, portfolio, bucket, acc) do
    @owners
    |> Enum.flat_map(fn {table, _links, _column, _resource_type} = owner ->
      %{rows: rows} =
        repo.query!("SELECT id FROM #{table} WHERE portfolio_id = $1 ORDER BY id", [
          portfolio.id
        ])

      Enum.map(rows, fn [id] -> {owner, id} end)
    end)
    |> Enum.reduce_while({:ok, acc}, fn {owner, id}, {:ok, acc} ->
      case tag_account(repo, actor, owner, id, bucket.id) do
        {:ok, :tagged} ->
          {:cont, {:ok, Map.update!(acc, :accounts_tagged, &(&1 + 1))}}

        {:ok, :skipped_existing_scope} ->
          {:cont, {:ok, Map.update!(acc, :skipped_existing_scope, &(&1 + 1))}}

        {:ok, :already_tagged} ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Adds the seeded bucket to the account's set, under the lock every
  # assignment writer takes on the account (FOR NO KEY UPDATE, which a
  # booking's foreign-key check does not wait on). The set's buckets are read
  # FOR SHARE: each must exist, and at most one may be a scope bucket
  # (ADR-0024), so an account that already carries another scope bucket is
  # skipped, not crashed on.
  defp tag_account(repo, actor, {table, links, column, _resource_type} = owner, id, bucket_id) do
    case repo.query!("SELECT id FROM #{table} WHERE id = $1 FOR NO KEY UPDATE", [id]).rows do
      [] ->
        {:error, :not_found}

      [[^id]] ->
        %{rows: rows} =
          repo.query!(
            "SELECT bucket_id FROM #{links} WHERE #{column} = $1 ORDER BY bucket_id",
            [id]
          )

        current = Enum.map(rows, fn [current_id] -> current_id end)

        if bucket_id in current,
          do: {:ok, :already_tagged},
          else: add_bucket(repo, actor, owner, id, {current, bucket_id})
    end
  end

  # The new set is the account's set, ascending, then the seeded bucket: the
  # order the assignment writers journaled it in.
  defp add_bucket(repo, actor, {_table, links, column, resource_type}, id, {current, bucket_id}) do
    bucket_ids = current ++ [bucket_id]

    %{rows: dimensions} =
      repo.query!(
        "SELECT dimension FROM buckets WHERE id = ANY($1) ORDER BY id FOR SHARE",
        [bucket_ids]
      )

    cond do
      length(dimensions) < length(bucket_ids) ->
        {:error, :bucket_ids}

      Enum.count(dimensions, &(&1 == [@scope_dimension])) > 1 ->
        {:ok, :skipped_existing_scope}

      true ->
        repo.query!("INSERT INTO #{links} (#{column}, bucket_id) VALUES ($1, $2)", [
          id,
          bucket_id
        ])

        # The assignment writers journal the account's whole new set as one
        # aggregate, with no id of its own and no before-image.
        journal!(
          repo,
          actor,
          {"update", resource_type, nil},
          nil,
          %{"id" => nil, column => id, "bucket_ids" => bucket_ids}
        )

        {:ok, :tagged}
    end
  end

  # Collision-safe naming: the name itself, then "<name> (Portfolio)", then
  # "<name> (Portfolio 2)", "<name> (Portfolio 3)", … — each with the base
  # cut so the whole candidate fits the 100-code-point name bound. The
  # numbered tail is unbounded, so a free name always exists. `free_sql`
  # answers whether its `$1` is free.
  defp available_name(repo, base, free_sql) do
    base = String.trim(base)

    [fit_name(base, ""), fit_name(base, @fallback_suffix)]
    |> Stream.concat(
      Stream.map(Stream.iterate(2, &(&1 + 1)), &fit_name(base, " (Portfolio #{&1})"))
    )
    |> Enum.find(fn candidate ->
      %{rows: [[free?]]} = repo.query!(free_sql, [candidate])
      free?
    end)
  end

  # The name as the context's changesets stored it: trimmed after the cut.
  defp fit_name(base, suffix) do
    String.trim(truncate(base, max(@name_max_length - codepoint_length(suffix), 1)) <> suffix)
  end

  # Cuts `text` to at most `max` code points without splitting a grapheme,
  # the bound counted the way the database counts a column's width.
  defp truncate(text, max) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {kept, count} ->
      count = count + codepoint_length(grapheme)
      if count <= max, do: {:cont, {[grapheme | kept], count}}, else: {:halt, {kept, count}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end

  defp codepoint_length(text), do: text |> String.codepoints() |> length()

  defp forget_notice(repo) do
    case repo.query!("SELECT to_regclass('public.settings')").rows do
      [[nil]] -> :ok
      [[_settings]] -> repo.query!("DELETE FROM settings WHERE key = $1", [@notice_key])
    end
  end

  # The guard (`portfolixir_require_journal_actor`) reads the actor from a
  # transaction-local setting; it is cleared again before the transaction
  # hands back, as `Portfolixir.Journal` clears it.
  defp journaled(repo, actor, fun) do
    repo.transaction(fn ->
      repo.query!("SELECT set_config($1, $2, true)", [@actor_setting, actor_setting(actor)])

      result = fun.()
      repo.query!("SELECT set_config($1, NULL, true)", [@actor_setting])
      result
    end)
  end

  # The journal's actor columns and setting, as `Portfolixir.Actor` wrote them
  # at this version: the type's name and the label, joined by a colon.
  defp actor_setting(%Actor{type: type, label: nil}), do: Atom.to_string(type)
  defp actor_setting(%Actor{type: type, label: label}), do: "#{type}:#{label}"

  defp journal!(
         repo,
         %Actor{type: type, label: label},
         {operation, resource_type, id},
         before,
         after_image
       ) do
    repo.query!(
      """
      INSERT INTO audit_journal
        (actor_type, actor_label, operation, resource_type, resource_id, before, after,
         scenario_id, inserted_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, NULL, $8)
      """,
      [
        Atom.to_string(type),
        label,
        operation,
        resource_type,
        id && Integer.to_string(id),
        before,
        after_image,
        NaiveDateTime.utc_now()
      ]
    )
  end

  # A bucket's row as the journal's serializer writes it: every column, the
  # timestamps in ISO 8601 at the second precision `timestamps()` stores.
  defp snapshot(bucket) do
    Map.new(@bucket_columns, fn column -> {column, encode(Map.fetch!(bucket, column))} end)
  end

  defp encode(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp encode(value), do: value
end
