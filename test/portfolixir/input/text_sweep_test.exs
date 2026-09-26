defmodule Portfolixir.Input.TextSweepTest do
  # E25 S4, G17 and G24 (#889): the Sprint 15 lesson — an invariant added to a
  # write path is swept over every writer of the table. Every varchar column a
  # schema casts from outside meets the shared text rule, or is a closed set
  # the changeset checks by membership; a column added later without either
  # fails here by name.
  use Portfolixir.DataCase, async: true

  # Written only by the application itself, never from a caller's text.
  @internal_schemas [
    Portfolixir.Journal.Entry,
    Portfolixir.Lifecycle.MergeRecord,
    Portfolixir.Lifecycle.RetiredImportHash,
    Portfolixir.Derived.Value
  ]

  @not_free_text %{
    {Portfolixir.Ledger.Transaction, :import_hash} => "the importer's SHA-256 digest",
    {Portfolixir.Classifications.Classification, :key} => "set only for built-in trees",
    {Portfolixir.Classifications.Category, :key} => "set only for built-in categories",
    {Portfolixir.Classifications.Category, :color} => "a #rrggbb format check",
    {Portfolixir.Buckets.Bucket, :color} => "a #RRGGBB format check",
    {Portfolixir.Fx.ExchangeRate, :base_currency} => "a supported-currency check",
    {Portfolixir.Fx.ExchangeRate, :quote_currency} => "a supported-currency check",
    {Portfolixir.Catalog.Security, :feed} => "a supported-feed check",
    {Portfolixir.Catalog.Security, :latest_feed} => "a supported-feed check"
  }

  # Structured fields whose text never comes from a caller as such.
  @not_free_structure %{
    {Portfolixir.Portfolios.CashAccount, :former_names} =>
      "the account's own previous names, each already met the text rule",
    {Portfolixir.Portfolios.SecuritiesAccount, :former_names} =>
      "the account's own previous names, each already met the text rule",
    {Portfolixir.Tax.Parameters, :church_tax_rates} => "a list of decimals"
  }

  defp varchar_columns do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name, column_name
      FROM information_schema.columns
      WHERE table_schema = 'public' AND data_type IN ('character varying', 'text')
      """)

    MapSet.new(rows, fn [table, column] -> {table, column} end)
  end

  defp schemas do
    {:ok, modules} = :application.get_key(:portfolixir, :modules)

    Enum.filter(modules, fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
        is_binary(module.__schema__(:source)) and module not in @internal_schemas
    end)
  end

  test "every text column a schema casts meets the text rule or a closed set" do
    varchar = varchar_columns()

    swept =
      for module <- schemas(),
          field <- module.__schema__(:fields),
          module.__schema__(:type, field) == :string,
          column = Atom.to_string(module.__schema__(:field_source, field)),
          MapSet.member?(varchar, {module.__schema__(:source), column}),
          not Map.has_key?(@not_free_text, {module, field}) do
        source = module.__info__(:compile)[:source] |> List.to_string() |> File.read!()

        bounded =
          Regex.match?(~r/Text\.validate\(\s*\[?[^\)]*:#{field}\b/, source) or
            Regex.match?(~r/validate_inclusion\(:#{field}\b/, source)

        assert bounded,
               "#{inspect(module)}.#{field} is a text column its changeset neither bounds " <>
                 "with Portfolixir.Input.Text.validate/3 nor checks against a closed set"

        {module, field}
      end

    for named <- [
          {Portfolixir.Portfolios.Portfolio, :name},
          {Portfolixir.Portfolios.CashAccount, :name},
          {Portfolixir.Portfolios.SecuritiesAccount, :name},
          {Portfolixir.Catalog.Security, :name},
          {Portfolixir.Classifications.Classification, :name},
          {Portfolixir.Buckets.View, :name},
          {Portfolixir.Ledger.Transaction, :notes},
          {Portfolixir.Knowledge.SecurityNote, :body}
        ] do
      assert named in swept
    end
  end

  # The S3/S4 review round (G24): a jsonb column refuses a NUL in a key or a
  # value as the text columns do, so a free-form map a schema casts meets the
  # text rule at any depth, and one added later without it fails here by name.
  test "every free-form map or list a schema casts meets the text rule at any depth" do
    swept =
      for module <- schemas(),
          field <- module.__schema__(:fields),
          structured?(module.__schema__(:type, field)),
          not Map.has_key?(@not_free_structure, {module, field}) do
        source = module.__info__(:compile)[:source] |> List.to_string() |> File.read!()

        assert Regex.match?(~r/Text\.validate_map\(\s*:#{field}\b/, source),
               "#{inspect(module)}.#{field} is a free-form field its changeset does not bound " <>
                 "with Portfolixir.Input.Text.validate_map/3"

        {module, field}
      end

    assert {Portfolixir.Catalog.Security, :attributes} in swept
  end

  defp structured?(:map), do: true
  defp structured?({:map, _inner}), do: true
  defp structured?({:array, _inner}), do: true
  defp structured?(_type), do: false
end
