defmodule Portfolixir.Invariants.DecimalPersistenceTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer protecting financial integrity,
  # I want a meta-test that fails when persisted data uses floats,
  # so that ADR-0003 (Decimal for all financial values) cannot be regressed
  # by a future schema field or migration column.
  #
  # Acceptance criteria:
  # - No Ecto schema declares a `:float` (or `:float`-typed array) field.
  # - No migration declares a `:float` column type.
  # - The scan is AST-based so display-layer float helpers (Decimal.to_float,
  #   Float.round, is_float) never count as offenders.

  @schema_sources Path.wildcard("lib/**/*.ex")
  @migration_sources Path.wildcard("priv/repo/migrations/*.exs")

  test "no Ecto schema field is typed :float" do
    offenders =
      for path <- @schema_sources,
          source = File.read!(path),
          uses_ecto_schema?(source),
          field <- float_fields(source) do
        "#{path}: field #{inspect(field)} typed :float"
      end

    assert offenders == [],
           "Persisted schema fields must use :decimal, not :float (ADR-0003):\n" <>
             Enum.join(offenders, "\n")
  end

  test "no migration column is typed :float" do
    offenders =
      for path <- @migration_sources,
          source = File.read!(path),
          column <- float_columns(source) do
        "#{path}: column #{inspect(column)} typed :float"
      end

    assert offenders == [],
           "Migration columns must use :decimal, not :float (ADR-0003):\n" <>
             Enum.join(offenders, "\n")
  end

  defp uses_ecto_schema?(source), do: source =~ "use Ecto.Schema"

  # Collect the names of any `field(name, :float, ...)` declarations, including
  # `{:array, :float}` element types.
  defp float_fields(source) do
    source
    |> Code.string_to_quoted!()
    |> collect(fn
      {:field, _meta, [name | type_and_opts]} ->
        if float_type?(type_and_opts), do: [name], else: []

      _other ->
        []
    end)
  end

  # Collect the names of any `add(name, :float, ...)` or
  # `modify(name, :float, ...)` migration columns, including arrays of float.
  defp float_columns(source) do
    source
    |> Code.string_to_quoted!()
    |> collect(fn
      {op, _meta, [name | type_and_opts]} when op in [:add, :modify] ->
        if float_type?(type_and_opts), do: [name], else: []

      _other ->
        []
    end)
  end

  defp float_type?([:float | _opts]), do: true
  defp float_type?([{:array, _meta, [:float]} | _opts]), do: true
  defp float_type?([{:{}, _meta, [:array, :float]} | _opts]), do: true
  defp float_type?(_type_and_opts), do: false

  # Walk an AST, applying `matcher` to every node and concatenating its lists.
  defp collect(ast, matcher) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        {node, matcher.(node) ++ acc}
      end)

    acc
  end
end
