defmodule PortfolixirWeb.CssUnusedBareClassTest do
  # #1302 (the Shell polish list #1357; Sprint 30 plan, F2): `app.css` kept a
  # `.chart` family (`.chart rect` among it) that no template rendered. A
  # one-word class such as `chart` hides from a plain search, since the word
  # also stands in tab lists and string comparisons, so this check reads only
  # where a class is set: a `class` attribute, a `class:` option, and the
  # scripts' `className` and `classList` calls.
  use ExUnit.Case, async: true

  @css "priv/static/app.css"
  @sources ["lib/**/*.ex", "lib/**/*.heex", "priv/static/**/*.js"]

  # User story (#1302):
  # As the maintainer reading the stylesheet,
  # I want no rule for a one-word class that nothing renders,
  # so that a rule in app.css names something a page can show.
  #
  # Acceptance criteria:
  # - Every one-word class selector in app.css (no "-" or "_") is set by some
  #   template or script.
  test "every one-word class selector in app.css is set by a template or a script" do
    set = classes_set()
    bare = bare_class_selectors()

    # Not vacuous: the stylesheet has one-word classes the pages do set.
    assert "badge" in bare and MapSet.member?(set, "badge")

    unused = Enum.reject(bare, &MapSet.member?(set, &1))

    assert unused == [],
           "app.css styles one-word classes nothing sets: " <> Enum.join(unused, ", ")
  end

  defp bare_class_selectors do
    css = @css |> File.read!() |> String.replace(~r{/\*.*?\*/}s, "")

    ~r/([^{}]+)\{/
    |> Regex.scan(css, capture: :all_but_first)
    |> Enum.flat_map(fn [selector] ->
      Regex.scan(~r/\.(-?[A-Za-z_][\w-]*)/, selector, capture: :all_but_first)
    end)
    |> List.flatten()
    |> Enum.reject(&String.contains?(&1, ["-", "_"]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp classes_set do
    @sources
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.flat_map(fn path ->
      Regex.scan(
        ~r/class(?:Name|List\.\w+\()?\s*[=:(]\s*["'{\[](.*?)["'}\]]/s,
        File.read!(path),
        capture: :all_but_first
      )
    end)
    |> Enum.flat_map(fn [value] -> Regex.scan(~r/[\w-]+/, value) end)
    |> List.flatten()
    |> MapSet.new()
  end
end
