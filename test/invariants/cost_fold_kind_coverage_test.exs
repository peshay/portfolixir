defmodule Portfolixir.Invariants.CostFoldKindCoverageTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Ledger.Transaction

  # User story (ADR-0028 §3):
  # As a maintainer extending the ledger with a new booking kind,
  # I want a meta-test that fails when the moving-average cost fold does not
  # name the kind explicitly,
  # so that the fold's former silent catch-all can never absorb a kind with
  # cost semantics (the AR-7 loud-failure gate only covers folds dispatching
  # through Projection.effects/1 — the cost fold does not, so this test is
  # its gate).
  #
  # Acceptance criteria:
  # - Every apply_cost_effect clause narrows the transaction kind: a literal
  #   `%{type: "..."}` pattern, or a `type in [...]` / `type in @attr` guard.
  # - No clause is a catch-all over kinds.
  # - The union of narrowed kinds equals Transaction.kinds/0 exactly: each
  #   kind is either explicitly handled or explicitly listed as cost-neutral.

  @ledger_source "lib/portfolixir/ledger.ex"

  test "apply_cost_effect names every transaction kind explicitly, with no catch-all" do
    ast = @ledger_source |> File.read!() |> Code.string_to_quoted!()
    attributes = list_attributes(ast)
    clauses = cost_effect_clauses(ast)

    assert clauses != [],
           "Could not find any apply_cost_effect clause in #{@ledger_source}"

    {covered, offenders} =
      Enum.reduce(clauses, {[], []}, fn {arg, guard}, {covered, offenders} ->
        case narrowed_kinds(arg, guard, attributes) do
          {:ok, kinds} -> {kinds ++ covered, offenders}
          :catch_all -> {covered, [Macro.to_string(arg) | offenders]}
        end
      end)

    assert offenders == [],
           "apply_cost_effect must not have a catch-all over kinds (ADR-0028 §3); " <>
             "every kind is explicitly handled or explicitly cost-neutral. " <>
             "Offending argument patterns: #{inspect(offenders)}"

    assert Enum.sort(Enum.uniq(covered)) == Enum.sort(Transaction.kinds()),
           "apply_cost_effect kind coverage must equal Transaction.kinds/0. " <>
             "Missing: #{inspect(Transaction.kinds() -- covered)}, " <>
             "unknown: #{inspect(Enum.uniq(covered) -- Transaction.kinds())}"
  end

  # Return `{first_arg_ast, guard_ast | nil}` for every apply_cost_effect
  # def/defp clause in the source.
  defp cost_effect_clauses(ast) do
    collect(ast, fn
      {def_kind, _meta, [head | _body]} when def_kind in [:def, :defp] ->
        case clause_head(head) do
          {[first_arg | _rest], guard} -> [{first_arg, guard}]
          _other -> []
        end

      _other ->
        []
    end)
  end

  defp clause_head({:when, _meta, [call, guard]}) do
    case clause_head(call) do
      {args, nil} -> {args, guard}
      other -> other
    end
  end

  defp clause_head({:apply_cost_effect, _meta, args}) when is_list(args), do: {args, nil}
  defp clause_head(_other), do: :not_cost_effect

  # `%{name => [strings]}` for every module attribute holding a string list.
  defp list_attributes(ast) do
    ast
    |> collect(fn
      {:@, _meta, [{name, _name_meta, [value]}]} when is_list(value) ->
        if Enum.all?(value, &is_binary/1), do: [{name, value}], else: []

      _other ->
        []
    end)
    |> Map.new()
  end

  # The kinds a clause narrows to: a literal `%{type: "..."}` pattern, or a
  # `%{type: var}` pattern whose guard constrains `var in <literal list or
  # string-list attribute>`. Anything else is a catch-all over kinds.
  defp narrowed_kinds(arg, guard, attributes) do
    case type_pattern(arg) do
      kind when is_binary(kind) -> {:ok, [kind]}
      {:var, name} -> guard_kinds(name, guard, attributes)
      :none -> :catch_all
    end
  end

  # Unwrap `pattern = var` / `var = pattern` and read the `:type` key.
  defp type_pattern({:=, _meta, [left, right]}) do
    case type_pattern(left) do
      :none -> type_pattern(right)
      found -> found
    end
  end

  defp type_pattern({:%{}, _meta, pairs}) when is_list(pairs) do
    case List.keyfind(pairs, :type, 0) do
      {:type, value} when is_binary(value) -> value
      {:type, {name, _meta, context}} when is_atom(name) and is_atom(context) -> {:var, name}
      _other -> :none
    end
  end

  defp type_pattern(_other), do: :none

  # Find `var in <list>` inside the guard and resolve the list.
  defp guard_kinds(_var, nil, _attributes), do: :catch_all

  defp guard_kinds(var, guard, attributes) do
    guard
    |> collect(fn
      {:in, _meta, [{^var, _var_meta, context}, list]} when is_atom(context) -> [list]
      _other -> []
    end)
    |> Enum.find_value(:catch_all, fn
      list when is_list(list) ->
        if Enum.all?(list, &is_binary/1), do: {:ok, list}, else: nil

      {:@, _meta, [{name, _name_meta, nil}]} ->
        case Map.fetch(attributes, name) do
          {:ok, kinds} -> {:ok, kinds}
          :error -> nil
        end

      _other ->
        nil
    end)
  end

  # Walk an AST, applying `matcher` to every node and concatenating its lists.
  defp collect(ast, matcher) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        {node, matcher.(node) ++ acc}
      end)

    acc
  end
end
