defmodule Portfolixir.Invariants.ProjectionNoCatchAllTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer relying on crash-by-design for unknown booking kinds,
  # I want a meta-test that fails when Ledger.Projection.effects/1 gains a
  # catch-all clause,
  # so that ADR-0011 (a kind the projection has not been taught must raise,
  # not silently fold to a no-op) cannot be regressed by a future
  # `def effects(_), do: ...` clause.
  #
  # Acceptance criteria:
  # - effects/1 has at least one clause (the parse found the function).
  # - No effects/1 clause is a catch-all: a clause whose single argument is a
  #   bare variable or `_` with no guard would match any kind and is rejected.
  # - A guarded variable clause (e.g. `effects(%{type: type}) when ...`) is a
  #   map pattern, not a catch-all, and stays allowed.

  @projection_source "lib/portfolixir/ledger/projection.ex"

  test "effects/1 has no catch-all clause" do
    clauses = effects_clauses(File.read!(@projection_source))

    assert clauses != [],
           "Could not find any effects/1 clause in #{@projection_source}"

    offenders =
      for {arg, guard} <- clauses, catch_all?(arg, guard) do
        Macro.to_string(arg)
      end

    assert offenders == [],
           "Ledger.Projection.effects/1 must not have a catch-all clause; a " <>
             "kind it has not been taught must raise (ADR-0011). Offending " <>
             "argument patterns: #{inspect(offenders)}"
  end

  # Return `{first_arg_ast, guard_ast | nil}` for every `def effects/1` and
  # `defp effects/1` clause in the source.
  defp effects_clauses(source) do
    source
    |> Code.string_to_quoted!()
    |> collect(fn
      {def_kind, _meta, [head | _body]} when def_kind in [:def, :defp] ->
        case clause_head(head) do
          {[arg], guard} -> [{arg, guard}]
          _other -> []
        end

      _other ->
        []
    end)
  end

  # Split a clause head into `{args, guard_ast | nil}`, only for `effects`.
  defp clause_head({:when, _meta, [call, guard]}) do
    case clause_head(call) do
      {args, nil} -> {args, guard}
      other -> other
    end
  end

  defp clause_head({:effects, _meta, args}) when is_list(args), do: {args, nil}
  defp clause_head(_other), do: :not_effects

  # A clause matches every kind when its argument is an unguarded bare variable
  # or `_`. Any map/literal/struct pattern, or any guard, narrows it.
  defp catch_all?(_arg, guard) when guard != nil, do: false
  defp catch_all?({name, _meta, context}, nil) when is_atom(name) and is_atom(context), do: true
  defp catch_all?(_arg, nil), do: false

  # Walk an AST, applying `matcher` to every node and concatenating its lists.
  defp collect(ast, matcher) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        {node, matcher.(node) ++ acc}
      end)

    acc
  end
end
