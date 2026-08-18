defmodule Portfolixir.Invariants.DerivedNeverAWriteSourceTest do
  use ExUnit.Case, async: true

  # User story (ADR-0039 §5 I7):
  # As a maintainer trusting every financial write to be derived from the
  # ledger alone,
  # I want a mechanical gate that fails when any module outside the derived
  # layer's few named collaborators references Portfolixir.Derived,
  # so that no booking, import decision or consistency finding can ever read
  # the materialized layer instead of the ledger — statically checkable, the
  # same construction as web_repo_boundary_test.exs.
  #
  # Acceptance criteria:
  # - No source file under lib/portfolixir/ or lib/portfolixir_web/ references
  #   the derived layer, except:
  #   * the derived layer itself (lib/portfolixir/derived/**),
  #   * the registered readers (the performance walk and its warm-up),
  #   * the write seams, which may reference ONLY the Invalidation announcer —
  #     writes announce, they never read.
  # - The scan is AST-based and resolves aliases, so "Derived" in a comment or
  #   string never counts, and an aliased `Invalidation.after_write` does.

  @sources Path.wildcard("lib/portfolixir/**/*.ex") ++
             Path.wildcard("lib/portfolixir_web/**/*.ex")

  # File => module paths under Portfolixir.Derived it may reference.
  @allowed %{
    "lib/portfolixir/portfolios/performance.ex" => [[:Portfolixir, :Derived]],
    "lib/portfolixir/portfolios/performance/warmup.ex" => [[:Portfolixir, :Derived]],
    "lib/portfolixir/journal.ex" => [[:Portfolixir, :Derived, :Invalidation]],
    "lib/portfolixir/fx.ex" => [[:Portfolixir, :Derived, :Invalidation]],
    "lib/portfolixir/catalog/quotes.ex" => [[:Portfolixir, :Derived, :Invalidation]],
    # Supervision only: the memo table's owner and the background refresher
    # start with the app, and the refresher is handed the warm-up it must call.
    # Starting a process is not reading a derived value.
    "lib/portfolixir/application.ex" => [
      [:Portfolixir, :Derived, :Memo],
      [:Portfolixir, :Derived, :Refresher]
    ]
  }

  # The derived layer itself: its facade and its internals.
  defp derived_layer?(path) do
    path == "lib/portfolixir/derived.ex" or String.starts_with?(path, "lib/portfolixir/derived/")
  end

  test "no module outside the allowlist references the derived layer" do
    offenders =
      for path <- @sources,
          not derived_layer?(path),
          reference <- derived_references(File.read!(path)),
          reference not in Map.get(@allowed, path, []) do
        "#{path}: references #{Enum.join(reference, ".")}"
      end

    assert offenders == [],
           "Only the ledger is authoritative: write paths and surfaces must not " <>
             "read the derived layer (ADR-0039 I7). Offenders:\n" <>
             Enum.join(Enum.uniq(offenders), "\n")
  end

  test "the write seams reference the announcer only, never the reading API" do
    for {path, allowed} <- @allowed,
        allowed == [[:Portfolixir, :Derived, :Invalidation]] do
      references = derived_references(File.read!(path))

      assert Enum.all?(references, &(&1 == [:Portfolixir, :Derived, :Invalidation])),
             "#{path} may only announce writes via Derived.Invalidation, " <>
               "found: #{inspect(references)}"
    end
  end

  # Every module path under Portfolixir.Derived a source references, resolved
  # through its alias directives, deduplicated.
  defp derived_references(source) do
    ast = Code.string_to_quoted!(source)
    aliases = alias_map(ast)

    ast
    |> referenced_paths(aliases)
    |> Enum.filter(&List.starts_with?(&1, [:Portfolixir, :Derived]))
    |> Enum.uniq()
  end

  # `alias Portfolixir.Derived.Invalidation` (optionally `as:`) — the short
  # name maps to the full path.
  defp alias_map(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, segments}]} = node, acc ->
          {node, Map.put(acc, List.last(segments), segments)}

        {:alias, _, [{:__aliases__, _, segments}, [as: {:__aliases__, _, [as_name]}]]} = node,
        acc ->
          {node, Map.put(acc, as_name, segments)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # Every alias usage in the AST (call targets and bare module references),
  # expanded through the alias map.
  defp referenced_paths(ast, aliases) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, _, [first | rest] = segments} = node, acc when is_atom(first) ->
          expanded =
            case Map.fetch(aliases, first) do
              {:ok, full} -> full ++ rest
              :error -> segments
            end

          {node, [expanded | acc]}

        node, acc ->
          {node, acc}
      end)

    acc
  end
end
