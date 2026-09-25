defmodule Portfolixir.Input.BoundedDecimalSweepTest do
  # E25 S4, G16 and G17 (#889), with F26 (#888): the Sprint 15 lesson — an
  # invariant added to a write path is swept over every writer of the table.
  # Every `numeric(precision, scale)` column a schema casts is rounded to its
  # column's scale before it is validated (ADR-0016 §2), and a magnitude past
  # its precision is a field error, never a failed write. The columns are read
  # from the database itself, so a numeric column added later without a
  # changeset below fails here by name.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Tax.AllowanceOrder
  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.Profile
  alias Portfolixir.Tax.StatementSnapshot

  @today ~D[2026-01-15]

  # The public changeset of every schema that casts a bounded numeric column.
  defp builders do
    %{
      Quote => &Quote.changeset(%Quote{}, &1),
      ExchangeRate => &ExchangeRate.changeset(%ExchangeRate{}, &1),
      Transaction => &Transaction.changeset(%Transaction{}, &1),
      AllowanceOrder => &AllowanceOrder.changeset(%AllowanceOrder{}, &1),
      Parameters => &Parameters.changeset(%Parameters{}, &1),
      Profile => &Profile.changeset(%Profile{}, &1),
      StatementSnapshot => &StatementSnapshot.changeset(%StatementSnapshot{}, &1, @today)
    }
  end

  defp bounded_numeric_columns do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name, column_name, numeric_precision, numeric_scale
      FROM information_schema.columns
      WHERE table_schema = 'public' AND data_type = 'numeric'
        AND numeric_precision IS NOT NULL
      ORDER BY table_name, column_name
      """)

    Enum.map(rows, fn [table, column, precision, scale] -> {table, column, precision, scale} end)
  end

  defp schema_field!(table, column) do
    {:ok, modules} = :application.get_key(:portfolixir, :modules)

    found =
      for module <- modules,
          Code.ensure_loaded?(module),
          function_exported?(module, :__schema__, 1),
          module.__schema__(:source) == table,
          field <- module.__schema__(:fields),
          Atom.to_string(module.__schema__(:field_source, field)) == column,
          do: {module, field}

    case found do
      [pair | _] -> pair
      [] -> flunk("#{table}.#{column} is a numeric column no schema casts")
    end
  end

  # 10^(precision - scale): the smallest magnitude the column cannot hold.
  defp overflowing(precision, scale), do: "1" <> String.duplicate("0", precision - scale)

  # A value one digit finer than the column keeps, and what it rounds to.
  defp finer(scale) do
    {"0." <> String.duplicate("1", scale) <> "6",
     Decimal.new("0." <> String.duplicate("1", scale - 1) <> "2")}
  end

  test "every bounded numeric column is rounded to its scale and bounded by its precision" do
    swept =
      for {table, column, precision, scale} <- bounded_numeric_columns() do
        {module, field} = schema_field!(table, column)

        build =
          Map.get(builders(), module) ||
            flunk(
              "#{inspect(module)}.#{field} is a numeric(#{precision},#{scale}) column " <>
                "this sweep has no changeset for"
            )

        key = Atom.to_string(field)

        refused = build.(%{key => overflowing(precision, scale)})

        assert Keyword.has_key?(refused.errors, field),
               "#{inspect(module)}.#{field} accepts a magnitude its numeric(#{precision},#{scale}) " <>
                 "column cannot hold"

        {given, rounded} = finer(scale)
        quantised = Ecto.Changeset.get_change(build.(%{key => given}), field)

        assert Decimal.equal?(quantised, rounded) and quantised.exp >= -scale,
               "#{inspect(module)}.#{field} is not rounded to its column's scale #{scale} " <>
                 "before it is validated: #{inspect(quantised)}"

        {module, field}
      end

    # The sweep saw the columns the findings named.
    assert {Quote, :close} in swept
    assert {ExchangeRate, :rate} in swept
    assert {StatementSnapshot, :taxable_income} in swept
    assert {AllowanceOrder, :amount_granted} in swept
    assert {Transaction, :gross_amount} in swept
  end
end
