defmodule Portfolixir.Invariants.SweepTagTest do
  use ExUnit.Case, async: true

  # User story (Sprint 30 plan M2, Sprint 29 retrospective carry-forward 1):
  # As the orchestrating session that integrates parallel stories,
  # I want every test module that walks the whole application (every route,
  # every template, every schema, every `lib/**` file) to carry
  # `@moduletag :sweep`,
  # so that a story agent runs them all with `mix test --only sweep` beside
  # `mix test test/invariants`, and a sweep added later cannot drop out of
  # that run by being left untagged.
  #
  # Acceptance criteria:
  # - A test module outside `test/invariants` (run as a directory anyway)
  #   and `test/browser` (run by its own job) that calls
  #   `Path.wildcard("lib/**…")` or `Path.wildcard("lib/portfolixir_web/**…")`,
  #   or holds such a file glob (`"lib/**/…"`) in any form that reaches it —
  #   piped, captured, in a module attribute or a list (Sprint 30 closing
  #   act, correctness lens, finding 1) —, reads the router's routes (`Router.__routes__/0`,
  #   `Phoenix.Router.routes/1`) or lists every compiled module
  #   (`:application.get_key(:portfolixir, :modules)`) carries
  #   `@moduletag :sweep`.
  # - No module tagged `:browser` carries the tag: an `--include` beats the
  #   helper's `exclude: [:browser]`, so `mix test --only sweep` would start
  #   Chromium.
  # - An untagged copy of a sweep, a tag only in a comment and a test-level
  #   `@tag :sweep` are refused; the scan sees the sweeps it polices.

  @skipped_dirs ["test/invariants/", "test/browser/"]

  test "every test module that walks the whole application carries @moduletag :sweep" do
    files =
      for path <- Path.wildcard("test/**/*_test.exs"),
          not String.starts_with?(path, @skipped_dirs),
          do: {path, File.read!(path)}

    walkers = for {path, source} <- files, walks_application?(source), do: path
    untagged = for {path, source} <- files, path in walkers, not sweep_tagged?(source), do: path

    assert untagged == [],
           "test modules that walk every route, template, schema or lib/** file " <>
             "without @moduletag :sweep, so `mix test --only sweep` misses them:\n" <>
             Enum.join(untagged, "\n")

    # The scan sees what it polices: the routes, the lib/** walks and the
    # module listings each have more than one sweep today.
    assert length(walkers) >= 15, "the scan saw only #{length(walkers)} sweeps"
    assert "test/portfolixir/localization_test.exs" in walkers

    # Sprint 30 closing act, correctness lens, finding 1: F2's check walks
    # every lib/** file through a module attribute and `&Path.wildcard/1`;
    # the scan must see it.
    assert "test/portfolixir_web/css_unused_bare_class_test.exs" in walkers
  end

  # Sprint 30 closing act, correctness lens, finding 1: the piped and the
  # captured forms of the same walk, both idioms the suite already uses
  # (localization_test.exs, css_unused_bare_class_test.exs), are sweeps too.
  test "a piped or captured walk of lib/** is a sweep" do
    for body <- [
          ~s{"lib/**/*.ex" |> Path.wildcard()},
          ~s{Enum.flat_map(["lib/**/*.ex"], &Path.wildcard/1)}
        ] do
      assert walks_application?(synthetic(body, "")), body
    end
  end

  test "the four sweeps the story workflow named carry the tag" do
    for path <- [
          "test/portfolixir/localization_test.exs",
          "test/portfolixir/input/text_sweep_test.exs",
          "test/portfolixir/input/bounded_date_sweep_test.exs",
          "test/portfolixir_web/field_label_test.exs"
        ] do
      assert sweep_tagged?(File.read!(path)), "#{path} lacks @moduletag :sweep"
    end
  end

  test "no browser walk carries the sweep tag" do
    tagged =
      for path <- Path.wildcard("test/browser/**/*_test.exs"),
          sweep_tagged?(File.read!(path)),
          do: path

    assert tagged == [], "browser walks tagged :sweep:\n" <> Enum.join(tagged, "\n")
  end

  describe "the checker (attack cases)" do
    test "an untagged copy of each walk is refused and the tagged one passes" do
      for body <- [
            ~s|Path.wildcard("lib/**/*.ex")|,
            ~s|Path.wildcard("lib/portfolixir_web/**/*.ex")|,
            "PortfolixirWeb.Router.__routes__()",
            "PortfolixirWeb.Router |> Phoenix.Router.routes()",
            "Phoenix.Router.routes(PortfolixirWeb.Router)",
            ":application.get_key(:portfolixir, :modules)"
          ] do
        untagged = synthetic(body, "")
        tagged = synthetic(body, "@moduletag :sweep")

        assert walks_application?(untagged), body
        refute sweep_tagged?(untagged), body
        assert walks_application?(tagged), body
        assert sweep_tagged?(tagged), body
      end
    end

    test "a tag in a comment, a test-level tag or another moduletag is refused" do
      for tag <- ["# @moduletag :sweep", "@tag :sweep", "@moduletag :slow", "@describetag :sweep"] do
        refute sweep_tagged?(synthetic(~s|Path.wildcard("lib/**/*.ex")|, tag)), tag
      end

      assert sweep_tagged?(synthetic(~s|Path.wildcard("lib/**/*.ex")|, "@moduletag [:sweep]"))
    end

    test "a walk of one context, of docs, a walk named in a comment or a path filter is no sweep" do
      for body <- [
            ~s|Path.wildcard("lib/portfolixir/news/**/*.ex")|,
            ~s|Path.wildcard("docs/**/*.md")|,
            ~s|:application.get_key(:portfolixir, :vsn)|,
            ~s|:ok # Path.wildcard("lib/**/*.ex")|,
            ~s|for filter <- ["lib/**", "priv/**"], do: filter|
          ] do
        refute walks_application?(synthetic(body, "")), body
      end
    end
  end

  defp synthetic(body, tag) do
    """
    defmodule SyntheticSweepTest do
      use ExUnit.Case, async: true
      #{tag}

      test "walks" do
        #{body}
      end
    end
    """
  end

  # True when the source calls one of the walks over the whole application.
  defp walks_application?(source) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(false, fn node, found -> {node, found or walk?(node)} end)

    found
  end

  defp walk?({{:., _, [{:__aliases__, _, [:Path]}, :wildcard]}, _, [pattern | _]})
       when is_binary(pattern),
       do: String.starts_with?(pattern, ["lib/**", "lib/portfolixir_web/**"])

  # Any string in the module that globs files under all of lib/** is a walk,
  # whatever reaches Path.wildcard with it: a pipe, a capture, a module
  # attribute or a list (Sprint 30 closing act, correctness lens, finding 1).
  # A comment is not in the AST; a bare "lib/**", a workflow's path filter,
  # names no file.
  defp walk?(literal) when is_binary(literal),
    do: String.starts_with?(literal, ["lib/**/", "lib/portfolixir_web/**/"])

  defp walk?({{:., _, [{:__aliases__, _, aliases}, :__routes__]}, _, []}),
    do: List.last(aliases) == :Router

  defp walk?({{:., _, [{:__aliases__, _, [:Phoenix, :Router]}, :routes]}, _, _}), do: true
  defp walk?({{:., _, [:application, :get_key]}, _, [:portfolixir, :modules]}), do: true
  defp walk?(_node), do: false

  # True when the module body sets `@moduletag :sweep` (alone or in a list).
  defp sweep_tagged?(source) do
    {_ast, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(false, fn
        {:@, _, [{:moduletag, _, [tags]}]} = node, found ->
          {node, found or :sweep in List.wrap(tags)}

        node, found ->
          {node, found}
      end)

    found
  end
end
