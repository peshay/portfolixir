defmodule Portfolixir.Tax.BuiltinSeed do
  @moduledoc """
  The built-in German statutory tax history (ADR-0031 §3, story 19.2), as the
  migration `20260725140000_seed_tax_parameters` seeds it through
  `Portfolixir.Tax.seed_builtin_parameters/1` and removes it through
  `Portfolixir.Tax.rollback_builtin_parameters/1`.

  **Frozen to that migration's version (#1015, Sprint 18 C3).** Applied
  migrations are immutable (CI rejects any change to one), so the code they
  call is what has to stay put. Up to Sprint 17 the seed wrote through
  today's `Parameters` and journal `Entry` schemas, and a column a later
  migration adds to either table would have stopped every fresh install, and
  every upgrade from before that version, at the seed. This module names
  nothing that changes with the schema: the statutory data, the ten columns
  `tax_parameters` has, the nine columns `audit_journal` has, the actor
  setting the guard reads, and the journal's snapshot shape
  (`Portfolixir.Journal.Serializer`: every column of the row, decimals as
  strings, timestamps in ISO 8601) are all written out here, as plain SQL.
  The journal's derived-data invalidation is left out on purpose: no derived
  value exists at that version (`derived_values` arrives with
  `20260814120000`). Change nothing here for a later schema; a later
  migration that needs the tax tables writes its own SQL.

  - **Idempotent:** an existing `(jurisdiction, tax_year)` row is skipped
    entirely, so a re-run inserts nothing, writes no journal entry and never
    overwrites a value the operator edited.
  - **Reversible:** the rollback deletes only rows carrying `built_in = true`;
    parameters the operator added survive.
  """

  alias Portfolixir.Actor

  @jurisdiction "DE"

  # German history. Starts at the introduction of the Abgeltungsteuer and
  # stops at the current year: inventing a ceiling for a year whose law is not
  # written is the same class of fabrication ADR-0031 exists to avoid --
  # `Portfolixir.Tax.fetch_parameters/2` makes the gap explicit instead.
  @first_year 2009
  @last_year 2026
  @allowance_change_year 2023

  # The 2021 partial Soli abolition did not touch the Abgeltungsteuer, so these
  # hold for every seeded year. String literals: `Decimal.new/1` raises on a
  # float.
  @capital_gains_tax_rate "0.25"
  @solidarity_surcharge_rate "0.055"
  @church_tax_rates ["0.08", "0.09"]

  @actor_setting "portfolixir.journal_actor"

  @columns ~w(id jurisdiction tax_year capital_gains_tax_rate solidarity_surcharge_rate
              saver_allowance_single saver_allowance_joint church_tax_rates built_in
              inserted_at updated_at)

  @doc """
  Inserts every year of the statutory history that has no row yet, each with
  its journal entry under `actor`. Returns `{:ok, %{inserted: n, skipped: n}}`.
  """
  @spec seed(module(), Actor.t()) :: {:ok, %{inserted: integer(), skipped: integer()}}
  def seed(repo, %Actor{} = actor) do
    journaled(repo, actor, fn ->
      Enum.reduce(@first_year..@last_year, %{inserted: 0, skipped: 0}, fn year, acc ->
        case insert_year(repo, year) do
          {:inserted, row} ->
            journal!(repo, actor, "create", row["id"], nil, snapshot(row))
            Map.update!(acc, :inserted, &(&1 + 1))

          :skipped ->
            Map.update!(acc, :skipped, &(&1 + 1))
        end
      end)
    end)
  end

  @doc "Deletes the built-in rows, and only those, each with its journal entry under `actor`."
  @spec rollback(module(), Actor.t()) :: :ok
  def rollback(repo, %Actor{} = actor) do
    {:ok, _deleted} =
      journaled(repo, actor, fn ->
        %{columns: columns, rows: rows} =
          repo.query!(
            "SELECT #{Enum.join(@columns, ", ")} FROM tax_parameters " <>
              "WHERE built_in ORDER BY id FOR UPDATE"
          )

        Enum.each(rows, fn values ->
          row = columns |> Enum.zip(values) |> Map.new()
          repo.query!("DELETE FROM tax_parameters WHERE id = $1", [row["id"]])
          # The journal files a deletion with the deleted row on both sides.
          journal!(repo, actor, "delete", row["id"], snapshot(row), snapshot(row))
        end)
      end)

    :ok
  end

  defp insert_year(repo, year) do
    {single, joint} = allowances(year)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    %{columns: columns, rows: rows} =
      repo.query!(
        """
        INSERT INTO tax_parameters
          (jurisdiction, tax_year, capital_gains_tax_rate, solidarity_surcharge_rate,
           saver_allowance_single, saver_allowance_joint, church_tax_rates, built_in,
           inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, true, $8, $8)
        ON CONFLICT (jurisdiction, tax_year) DO NOTHING
        RETURNING id
        """,
        [
          @jurisdiction,
          year,
          Decimal.new(@capital_gains_tax_rate),
          Decimal.new(@solidarity_surcharge_rate),
          single,
          joint,
          Enum.map(@church_tax_rates, &Decimal.new/1),
          now
        ]
      )

    case rows do
      [[id]] ->
        # The journal's after-image is the row as written, the way the
        # context's insert returned it: the values given, not the stored scale.
        {:inserted,
         columns
         |> Enum.zip([id])
         |> Map.new()
         |> Map.merge(%{
           "jurisdiction" => @jurisdiction,
           "tax_year" => year,
           "capital_gains_tax_rate" => Decimal.new(@capital_gains_tax_rate),
           "solidarity_surcharge_rate" => Decimal.new(@solidarity_surcharge_rate),
           "saver_allowance_single" => single,
           "saver_allowance_joint" => joint,
           "church_tax_rates" => Enum.map(@church_tax_rates, &Decimal.new/1),
           "built_in" => true,
           "inserted_at" => now,
           "updated_at" => now
         })}

      [] ->
        :skipped
    end
  end

  defp allowances(year) when year >= @allowance_change_year,
    do: {Decimal.new("1000.00"), Decimal.new("2000.00")}

  defp allowances(_year), do: {Decimal.new("801.00"), Decimal.new("1602.00")}

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

  defp journal!(repo, %Actor{type: type, label: label}, operation, id, before, after_image) do
    repo.query!(
      """
      INSERT INTO audit_journal
        (actor_type, actor_label, operation, resource_type, resource_id, before, after,
         scenario_id, inserted_at)
      VALUES ($1, $2, $3, 'tax_parameters', $4, $5, $6, NULL, $7)
      """,
      [
        Atom.to_string(type),
        label,
        operation,
        Integer.to_string(id),
        before,
        after_image,
        NaiveDateTime.utc_now()
      ]
    )
  end

  defp snapshot(row) do
    Map.new(@columns, fn column -> {column, encode(Map.fetch!(row, column))} end)
  end

  defp encode(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp encode(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp encode(values) when is_list(values), do: Enum.map(values, &encode/1)
  defp encode(value), do: value
end
