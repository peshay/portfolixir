defmodule Portfolixir.Invariants.WebRepoBoundaryTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer keeping the web layer a thin shell over the contexts,
  # I want a meta-test that fails when any module under lib/portfolixir_web/
  # calls the Repo directly,
  # so that the context boundary cannot be regressed by a LiveView,
  # controller, or plug reaching the database instead of going through a
  # domain context (Catalog, Portfolios, Ledger).
  #
  # Acceptance criteria:
  # - No source file under lib/portfolixir_web/ contains a direct `Repo.` call.
  # - The scan is AST-based so the literal text "Repo." inside a comment,
  #   doc string, or string literal never counts as an offender.
  #
  # Design note (meta-test vs. the `boundary` library): the `boundary` hex
  # package was considered and rejected. It would add a compile-time
  # dependency and per-module `use Boundary` annotations across every context
  # and web module to express the same single rule. This focused AST scan
  # encodes exactly the invariant we care about — the web layer never touches
  # the Repo — with no new dependency and no production-code churn.

  @web_sources Path.wildcard("lib/portfolixir_web/**/*.ex")

  test "no module under lib/portfolixir_web/ calls the Repo directly" do
    offenders =
      for path <- @web_sources,
          source = File.read!(path),
          reference <- repo_references(source) do
        "#{path}: direct #{reference} call"
      end

    assert offenders == [],
           "Web modules must go through a context, not the Repo directly:\n" <>
             Enum.join(offenders, "\n")
  end

  # Collect any `Repo.fun(...)` or aliased `*.Repo.fun(...)` remote calls in
  # the AST. Matching the AST (not raw text) means "Repo." appearing only in a
  # comment or string never registers as a call.
  defp repo_references(source) do
    source
    |> Code.string_to_quoted!()
    |> collect(fn
      {{:., _dot_meta, [target, fun]}, _meta, _args} when is_atom(fun) ->
        if repo_target?(target), do: ["Repo.#{fun}"], else: []

      _other ->
        []
    end)
  end

  # The call target is the Repo when its last alias segment is `Repo`, covering
  # both `Repo.x` and fully qualified `Portfolixir.Repo.x` forms.
  defp repo_target?({:__aliases__, _meta, segments}), do: List.last(segments) == :Repo
  defp repo_target?(_target), do: false

  # Walk an AST, applying `matcher` to every node and concatenating its lists.
  defp collect(ast, matcher) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        {node, matcher.(node) ++ acc}
      end)

    acc
  end
end
