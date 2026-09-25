defmodule Portfolixir.Tax.IdentityBackfill do
  @moduledoc """
  The one-time normalisation of the holder and institution values stored
  before `Portfolixir.Tax.Identity.normalize/1` composed to NFC, removed
  format characters and collapsed every Unicode space (E25 S6, G21, review
  round), run by the migration `normalize_tax_identities`.

  The lookups normalise the value they are given and fold both sides with
  the database's `lower()`, so a value stored under a no-break space, a
  zero-width character or a decomposed letter was out of reach of every
  filter, and a new write under the clean spelling sat beside it as a second
  identity. Every stored `holder` and `institution` of `tax_profiles`,
  `allowance_orders` and `tax_statement_snapshots` is therefore normalised
  the way a write normalises it, each changed row journaled under the
  caller's actor with its before and after.

  A row is **reported, never written** when its normalised spelling another
  row of its table already holds under the table's unique key (which row
  stays is the operator's choice, never the backfill's), when normalising
  leaves it blank, or when it would outgrow its column. The row keeps its
  stored spelling; the migration logs each refusal and the upgrade goes on.

  Idempotent: a second run finds nothing to normalise and journals nothing.
  It reads and writes the tables schemaless, naming only the columns they
  have at this migration, so the immutable migration keeps running when a
  later one adds a column. `run/1` is referenced from that migration — keep
  its signature stable.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Repo
  alias Portfolixir.Tax.Identity

  # {table, journal resource type, identity columns, the rest of the unique
  # key with its types, the columns at this migration}
  @tables [
    {"tax_profiles", "tax_profile", [:holder], [valid_from: :date],
     ~w(id holder valid_from jurisdiction church_tax_liable church_tax_rate assessment_type
        note inserted_at updated_at)a},
    {"allowance_orders", "allowance_order", [:holder, :institution], [tax_year: :integer],
     ~w(id holder institution tax_year amount_granted note inserted_at updated_at)a},
    {"tax_statement_snapshots", "tax_statement_snapshot", [:holder, :institution],
     [tax_year: :integer, as_of: :date],
     ~w(id institution holder tax_year as_of source church_tax_rate note taxable_income
        allowance_granted allowance_used loss_pot_equities loss_pot_other
        loss_carryforward_prior_years withholding_tax_pot withholding_tax_credited
        capital_gains_tax_withheld solidarity_surcharge_withheld church_tax_withheld
        inserted_at updated_at)a}
  ]

  # The identity columns are varchar(255).
  @max_length 255

  @type refusal :: %{
          table: String.t(),
          id: integer(),
          reason: :identity_of_another_row | :blank | :too_long,
          holder_id: integer() | nil
        }

  @type report :: %{
          written: [%{table: String.t(), id: integer()}],
          refused: [refusal()]
        }

  @doc """
  Normalises every stored holder and institution on behalf of `actor`, in
  one transaction. Returns the rows it wrote and the rows it refused.
  """
  @spec run(Actor.t()) :: {:ok, report()}
  def run(%Actor{} = actor) do
    Repo.transaction(fn ->
      Enum.reduce(@tables, %{written: [], refused: []}, fn table, acc ->
        {written, refused} = backfill(actor, table)
        %{written: acc.written ++ written, refused: acc.refused ++ refused}
      end)
    end)
  end

  @doc "One refusal as the sentence the migration logs; it names ids only."
  @spec describe(refusal()) :: String.t()
  def describe(%{table: table, id: id, reason: reason, holder_id: holder}) do
    "#{table} ##{id} keeps its stored holder or institution spelling: " <>
      case reason do
        :identity_of_another_row ->
          "normalised, it is the identity #{table} ##{holder} already holds for the same " <>
            "key; the two rows are one taxpayer or bank, so correct or remove one of them on " <>
            "the Tax page"

        :blank ->
          "normalised, nothing is left of it; correct it on the Tax page"

        :too_long ->
          "normalised, it would outgrow its column; correct it on the Tax page"
      end
  end

  defp backfill(actor, {table, resource_type, identity, key, columns}) do
    from(r in table, order_by: r.id, select: map(r, ^columns))
    |> Repo.all()
    |> Enum.reduce({[], []}, fn row, {written, refused} ->
      changes =
        for field <- identity,
            normalized = Identity.normalize(Map.fetch!(row, field)),
            normalized != Map.fetch!(row, field),
            do: {field, normalized}

      case refusal(table, identity, key, row, changes) do
        _none when changes == [] ->
          {written, refused}

        nil ->
          :ok = write_row(actor, {table, resource_type, columns}, row.id, changes)
          {[%{table: table, id: row.id} | written], refused}

        refusal ->
          {written, [refusal | refused]}
      end
    end)
    |> then(fn {written, refused} -> {Enum.reverse(written), Enum.reverse(refused)} end)
  end

  defp refusal(_table, _identity, _key, _row, []), do: nil

  defp refusal(table, identity, key, row, changes) do
    values = Map.merge(Map.take(row, identity), Map.new(changes))

    cond do
      Enum.any?(changes, fn {_field, value} -> value == "" end) ->
        %{table: table, id: row.id, reason: :blank, holder_id: nil}

      Enum.any?(changes, fn {_field, value} -> String.length(value) > @max_length end) ->
        %{table: table, id: row.id, reason: :too_long, holder_id: nil}

      holder = holder_of(table, values, key, row) ->
        %{table: table, id: row.id, reason: :identity_of_another_row, holder_id: holder}

      true ->
        nil
    end
  end

  # Another row of the table holding the normalised identity under the unique
  # key, folded with the index's own lower().
  defp holder_of(table, values, key, row) do
    base = from(r in table, where: r.id != ^row.id, select: r.id, order_by: r.id, limit: 1)

    query =
      Enum.reduce(values, base, fn {field, value}, query ->
        where(
          query,
          [r],
          fragment("lower(?)", field(r, ^field)) == fragment("lower(?)", type(^value, :string))
        )
      end)

    key
    |> Enum.reduce(query, fn
      {field, :date}, query ->
        where(query, [r], field(r, ^field) == type(^Map.fetch!(row, field), :date))

      {field, :integer}, query ->
        where(query, [r], field(r, ^field) == type(^Map.fetch!(row, field), :integer))
    end)
    |> Repo.one()
  end

  defp write_row(actor, {table, resource_type, columns}, id, changes) do
    row = from(r in table, where: r.id == ^id, select: map(r, ^columns))
    before = row |> lock("FOR UPDATE") |> Repo.one!()
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Multi.new()
    |> Multi.run(:row, fn repo, _changes ->
      {1, [written]} = repo.update_all(row, set: changes ++ [updated_at: now])
      {:ok, written}
    end)
    |> Journal.record(actor,
      resource_type: resource_type,
      operation: :update,
      source: :row,
      before: before
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
    end
  end
end
