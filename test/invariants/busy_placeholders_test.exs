defmodule Portfolixir.Invariants.BusyPlaceholdersTest do
  use ExUnit.Case, async: true

  # The Sprint 28 closing act (browser job): a page shows a placeholder where
  # a figure will land while its load runs, a block skeleton
  # (`.section-skeleton`) or a pending value slot (`.value-slot-pending`).
  # Assistive technology learns that the region is still loading only from
  # `aria-busy`, and so does every browser walk (test/browser/settle.js,
  # `settle`; the privacy walk first), which reads a page and leaves it only
  # once nothing on it is busy. Wealth's stacked chart and its performance chart showed their
  # skeletons without the mark, so the walk read them before their loads
  # landed and left while the bands' task was mid-query, which took the
  # test's shared database connection with it on CI. The placeholders are
  # markup, so the templates are what this test reads.

  @placeholder ~r/\b(section-skeleton|value-slot-pending)\b/

  # User story (the Sprint 28 closing act, browser job):
  # As the operator on a screen reader, and as the owner who trusts the
  # privacy walk,
  # I want every placeholder a page shows while a load runs to say it is
  # busy,
  # so that neither I nor the walk take a region for loaded before its
  # figures have landed.
  #
  # Acceptance criteria:
  # - Every element of the web layer's templates whose class names
  #   `section-skeleton` or `value-slot-pending` carries `aria-busy`.
  test "every loading placeholder marks itself busy" do
    files = Path.wildcard("lib/portfolixir_web/**/*.{ex,heex}")

    unmarked =
      for file <- files,
          source = File.read!(file),
          tag <- placeholder_tags(source),
          not (tag =~ ~r/\saria-busy=/),
          do: "#{file}: #{tag |> String.replace(~r/\s+/, " ") |> String.slice(0, 160)}"

    assert unmarked == [],
           "a loading placeholder without aria-busy:\n" <> Enum.join(unmarked, "\n")
  end

  # The opening tags whose class attribute names a placeholder. Every
  # mention of a placeholder class in a class attribute must belong to one
  # tag read here, so a tag this reading cannot parse fails the test rather
  # than being skipped.
  defp placeholder_tags(source) do
    tags =
      ~r/<[a-z][\w.-]*\s[^<>]*class="[^"]*"[^<>]*>/s
      |> Regex.scan(source)
      |> Enum.map(&hd/1)
      |> Enum.filter(&(class_attribute(&1) =~ @placeholder))

    mentions =
      length(Regex.scan(~r/class="[^"]*\b(section-skeleton|value-slot-pending)\b/, source))

    assert length(tags) == mentions, "a placeholder tag this test cannot read"
    tags
  end

  defp class_attribute(tag) do
    case Regex.run(~r/\sclass="([^"]*)"/, tag) do
      [_, class] -> class
      nil -> ""
    end
  end
end
