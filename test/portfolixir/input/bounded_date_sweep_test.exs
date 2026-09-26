defmodule Portfolixir.Input.BoundedDateSweepTest do
  # E25 S4, F70 (#889): the Sprint 15 lesson — an invariant added to a write
  # path is swept over every writer of the table. Every date column a schema
  # casts meets the shared bounded date, so a date field added later without
  # it fails here by name.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.MarketDataBounds
  alias Portfolixir.Input.BoundedDate

  # Date fields no changeset casts, each with the writer that sets it.
  @not_cast %{
    # Set only by the context closing a version, from a date it computed or
    # a retirement date parsed through BoundedDate.parse/1.
    {Portfolixir.Portfolios.PolicyRuleVersion, :valid_until} => "set by the context"
  }

  defp schemas do
    {:ok, modules} = :application.get_key(:portfolixir, :modules)

    Enum.filter(modules, fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
        not is_nil(module.__schema__(:source))
    end)
  end

  defp date_fields(module) do
    for field <- module.__schema__(:fields),
        module.__schema__(:type, field) == :date,
        not Map.has_key?(@not_cast, {module, field}),
        do: field
  end

  # Whether the module's code (its AST: never a comment or a doc string that
  # merely names the call) calls BoundedDate.validate/2 with a field list
  # holding `field`, or MarketDataBounds.validate with `field`.
  defp bounded_in_code?(source, field) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, _, aliases}, :validate]}, _, args} = node, found? ->
          hit? =
            case List.last(aliases) do
              :BoundedDate -> Enum.any?(args, &(is_list(&1) and field in &1))
              :MarketDataBounds -> field in args
              _other -> false
            end

          {node, found? or hit?}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  test "the sweep reads the code, never a comment that names the call" do
    refute bounded_in_code?(
             """
             defmodule Probe do
               # BoundedDate.validate([:time_stop]) is not called here
               @doc "BoundedDate.validate([:time_stop])"
               def changeset(cs), do: BoundedDate.validate(cs, [:as_of])
             end
             """,
             :time_stop
           )

    assert bounded_in_code?(
             "def changeset(cs), do: cs |> BoundedDate.validate([:as_of, :time_stop])",
             :time_stop
           )

    assert bounded_in_code?(
             "def c(cs), do: cs |> MarketDataBounds.validate(:date, :close, 1)",
             :date
           )
  end

  test "every cast date field of every schema meets the bounded date" do
    swept =
      for module <- schemas(), field <- date_fields(module) do
        source = module.__info__(:compile)[:source] |> List.to_string() |> File.read!()

        assert bounded_in_code?(source, field),
               "#{inspect(module)}.#{field} is a date column its changeset does not bound " <>
                 "with Portfolixir.Input.BoundedDate.validate/2"

        {module, field}
      end

    # The sweep saw the tables the finding named.
    assert {Portfolixir.Ledger.Transaction, :date} in swept
    assert {Portfolixir.Portfolios.PolicyRuleVersion, :valid_from} in swept
    assert {Portfolixir.Portfolios.Snapshot, :as_of} in swept
    assert {Portfolixir.Tax.StatementSnapshot, :as_of} in swept
  end

  test "the market-data bound includes the bounded date" do
    changeset =
      {%{}, %{date: :date, close: :decimal}}
      |> Ecto.Changeset.cast(%{"date" => "1899-12-31", "close" => "1"}, [:date, :close])
      |> MarketDataBounds.validate(:date, :close, MarketDataBounds.close_column())

    assert [date: {message, _}] = changeset.errors
    assert message == BoundedDate.message()
    refute MarketDataBounds.plausible?(~D[1899-12-31], "1", MarketDataBounds.close_column())
  end
end
