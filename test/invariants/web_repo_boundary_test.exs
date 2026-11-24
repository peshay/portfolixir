defmodule Portfolixir.Invariants.WebRepoBoundaryTest do
  use ExUnit.Case, async: true

  alias Portfolixir.SourceAliases

  # User story:
  # As a maintainer keeping the web layer a thin shell over the contexts,
  # I want a meta-test that fails when any module under lib/portfolixir_web/
  # calls the Repo directly,
  # so that the context boundary cannot be regressed by a LiveView,
  # controller, or plug reaching the database instead of going through a
  # domain context (Catalog, Portfolios, Ledger).
  #
  # Acceptance criteria:
  # - No source file under lib/portfolixir_web/ contains a direct `Repo.` call,
  #   and none names `Portfolixir.Repo` at all: not as a call's target, not
  #   under another name, not as a value handed to a function that queries
  #   with it (N-82).
  # - The scan is AST-based so the literal text "Repo." inside a comment,
  #   doc string, or string literal never counts as an offender, and it
  #   resolves the file's alias directives in every form they take
  #   (Portfolixir.SourceAliases).
  #
  # Design note (meta-test vs. the `boundary` library): the `boundary` hex
  # package was considered and rejected. It would add a compile-time
  # dependency and per-module `use Boundary` annotations across every context
  # and web module to express the same single rule. This focused AST scan
  # encodes exactly the invariant we care about — the web layer never touches
  # the Repo — with no new dependency and no production-code churn.

  @web_sources Path.wildcard("lib/portfolixir_web/**/*.ex")

  @repo [:Portfolixir, :Repo]

  test "no module under lib/portfolixir_web/ calls the Repo directly" do
    offenders =
      for path <- @web_sources,
          source = File.read!(path),
          reference <- repo_references(source) do
        "#{path}: #{reference}"
      end

    assert offenders == [],
           "Web modules must go through a context, not the Repo directly:\n" <>
             Enum.join(offenders, "\n")
  end

  # User story (security review 2026-11, N-82):
  # As the maintainer who trusts this gate instead of reading every diff,
  # I want the scan to find the Repo however a web module names it,
  # so that the way a file spells an alias cannot decide whether the web
  # layer stays off the database.
  #
  # Acceptance criteria:
  # - The scan reports the Repo as a call's target under its own name, under
  #   an `as:` name, from a brace alias, through a `require`, by its full
  #   name, and as a value handed on.
  # - It reads synthetic sources here, so a tree with no offender does not
  #   pass for want of a scan.
  describe "the scan finds the Repo in every form a module can name it" do
    @forms [
      {"an alias and a call", ["alias Portfolixir.Repo", "def rows(q), do: Repo.all(q)"]},
      {"the full name", ["def rows(q), do: Portfolixir.Repo.all(q)"]},
      {"an alias under another name",
       ["alias Portfolixir.Repo, as: Store", "def rows(q), do: Store.all(q)"]},
      {"an alias in braces",
       ["alias Portfolixir.{Catalog, Repo}", "def rows(q), do: {Catalog, Repo.all(q)}"]},
      {"a require under another name",
       ["require Portfolixir.Repo, as: Store", "def rows(q), do: Store.all(q)"]},
      {"an alias built on an alias",
       [
         "alias Portfolixir, as: App",
         "alias App.Repo, as: Store",
         "def rows(q), do: Store.all(q)"
       ]},
      {"an alias inside a function",
       ["def rows(q) do", "  alias Portfolixir.Repo, as: Store", "  Store.all(q)", "end"]},
      {"a value handed on",
       [~s|def raw, do: Ecto.Adapters.SQL.query!(Portfolixir.Repo, "select 1", [])|]},
      {"a value handed on under another name",
       ["alias Portfolixir.Repo, as: Store", "def raw, do: Ecto.Multi.to_list(Store)"]},
      {"a captured function", ["def reader, do: &Portfolixir.Repo.all/1"]},
      {"a quoted atom", [~s|def rows(q), do: :"Elixir.Portfolixir.Repo".all(q)|]},
      {"another module that ends in Repo", ["def rows(q), do: Reporting.Repo.all(q)"]}
    ]

    for {form, body} <- @forms do
      test form do
        assert unquote(body) |> synthetic() |> repo_references() != []
      end
    end

    test "a module that goes through a context names no Repo" do
      source =
        synthetic([
          "alias Portfolixir.{Catalog, Portfolios}",
          "alias Portfolixir.Portfolios.Report, as: Repo",
          "# Portfolixir.Repo.all/1 in a comment, and Repo. in a string below.",
          ~s|def rows(id), do: {Catalog.get(id), Portfolios, "Repo.all", Repo}|
        ])

      assert repo_references(source) == []
    end
  end

  defp synthetic(body) do
    "defmodule PortfolixirWeb.Synthetic do\n  " <> Enum.join(body, "\n  ") <> "\nend\n"
  end

  # What in a source reaches the Repo: every remote call whose target is
  # written with a last segment `Repo` (`Repo.x`, `Portfolixir.Repo.x`,
  # `Any.Repo.x`), and every mention of `Portfolixir.Repo` once the file's
  # aliases are resolved, as a call's target or as a value. Reading the AST
  # (not raw text) means "Repo." appearing only in a comment or string never
  # registers.
  defp repo_references(source) do
    calls =
      source
      |> Code.string_to_quoted!()
      |> collect(fn
        {{:., _dot_meta, [target, fun]}, _meta, _args} when is_atom(fun) ->
          if repo_target?(target), do: ["direct Repo.#{fun} call"], else: []

        _other ->
          []
      end)

    named =
      for path <- SourceAliases.references(source), List.starts_with?(path, @repo) do
        "names #{Enum.join(path, ".")}"
      end

    calls ++ named
  end

  # The call target is written as a Repo when its last alias segment is
  # `Repo`, covering `Repo.x`, `Portfolixir.Repo.x` and any other module of
  # that name.
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
