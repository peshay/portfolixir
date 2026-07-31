defmodule Portfolixir.Invariants.BlastRadiusWideningTest do
  use ExUnit.Case, async: true

  # User story (2026-07-29, ADR-0032 §3.3):
  # As a maintainer who accepted targeted cache invalidation,
  # I want a mechanical gate that fails if the blast-radius resolver ever gains
  # a default clause that answers NARROWLY,
  # so that a write kind nobody wired up degrades to "recompute everything" and
  # never to "recompute nothing".
  #
  # Acceptance criteria:
  # - Every clause group that resolves a radius ends in a catch-all returning
  #   `:all`.
  # - The check is AST-based, so a comment promising the same thing cannot pass
  #   for the guarantee.
  #
  # This mirrors the meta-test that keeps `Ledger.Projection.effects/1` free of
  # a defensive fallback — same technique, opposite direction: there the danger
  # is a fallback that swallows, here it is a fallback that narrows.

  @source File.read!("lib/portfolixir/portfolios/performance/blast_radius.ex")

  # Every function in the module that returns a radius. Arity-0 entry points are
  # excluded: with no arguments there is no clause to fall through.
  @resolvers [:for_write, :for_quote, :transaction_radius]

  test "every radius resolver ends in a catch-all that widens to :all" do
    clauses = clauses_by_name(@source)

    for name <- @resolvers do
      group = Map.get(clauses, name, [])

      assert group != [], "expected #{name} to exist in BlastRadius — did it get renamed?"

      {args, body} = List.last(group)

      assert Enum.all?(args, &wildcard?/1),
             "the last clause of #{name}/#{length(args)} must be a catch-all, " <>
               "otherwise an unhandled write kind raises instead of widening"

      assert body == :all,
             "the last clause of #{name}/#{length(args)} must return :all. " <>
               "A narrowing default is how targeted invalidation becomes a wrong number " <>
               "(ADR-0032 §3.3)."
    end
  end

  test "no resolver clause returns an empty list as a default" do
    # `[]` is a legitimate ANSWER (nobody ever transacted this security), but
    # never a default: it would mean "this write affects nothing", which is the
    # exact failure the widening rule exists to prevent.
    clauses = clauses_by_name(@source)

    for name <- @resolvers, {args, body} <- Map.get(clauses, name, []) do
      refute Enum.all?(args, &wildcard?/1) and body == [],
             "#{name} has a catch-all clause returning [] — see ADR-0032 §3.3"
    end
  end

  defp clauses_by_name(source) do
    source
    |> Code.string_to_quoted!()
    |> collect_clauses()
    |> Enum.reverse()
    |> Enum.group_by(fn {name, _args, _body} -> name end, fn {_name, args, body} ->
      {args, body}
    end)
  end

  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body]} = node, acc when kind in [:def, :defp] ->
          case clause(head, body) do
            nil -> {node, acc}
            entry -> {node, [entry | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    clauses
  end

  # `def name(args) when guard, do: body` — unwrap the guard to reach the head.
  defp clause({:when, _meta, [head | _guards]}, body), do: clause(head, body)

  defp clause({name, _meta, args}, body) when is_atom(name) and is_list(args) do
    {name, args, body_value(body)}
  end

  defp clause(_head, _body), do: nil

  defp body_value([{:do, value}]), do: value
  defp body_value(value), do: value

  defp wildcard?({name, _meta, context}) when is_atom(name) and is_atom(context) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp wildcard?(_arg), do: false
end
