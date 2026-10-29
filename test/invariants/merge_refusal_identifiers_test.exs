defmodule Portfolixir.Invariants.MergeRefusalIdentifiersTest do
  @moduledoc """
  ADR-0054 §4 and #965's rule, applied to identifiers (security review
  2026-10-12, H11): a sentence a merge guard or a merge refusal writes names
  a record by its kind and id, and an identity by its kind. A stored ISIN,
  WKN or ticker is text a file, a provider or an earlier session wrote, so
  it travels as a data field beside the sentence, never inside it.

  This is the meta-test the row asks for. It reads the sentence writers'
  source, because a refusal the suite never triggers still reaches an agent
  the day it fires: no string the merge contexts or the merge controller
  build interpolates an identifier.
  """
  use ExUnit.Case, async: true

  @writers [
    "lib/portfolixir/lifecycle/*.ex",
    "lib/portfolixir_web/controllers/api/v1/merge_controller.ex"
  ]

  # An interpolation whose expression reads an identifier field or a value
  # named after one.
  @identifier ~r/#\{[^}]*\b(isins?|source_isin|target_isin|former_isins?|wkn|ticker|ticker_symbol)\b[^}]*\}/

  defp writers do
    @writers
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.sort()
  end

  # User story (security review 2026-10-12, H11):
  # As the maintainer keeping stored text out of the app's own sentences,
  # I want the build to refuse a merge sentence that interpolates an
  # identifier,
  # so that a refusal no test triggers still names an identity by its kind.
  #
  # Acceptance criteria:
  # - The merge contexts and the merge controller exist where this test
  #   reads them.
  # - No line of them interpolates an ISIN, a WKN or a ticker into a string.
  test "no merge guard or merge refusal interpolates a stored identifier" do
    files = writers()
    assert "lib/portfolixir/lifecycle/security_merge.ex" in files
    assert "lib/portfolixir_web/controllers/api/v1/merge_controller.ex" in files

    offenders =
      for path <- files,
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(@identifier, line),
          do: "#{path}:#{number}: #{String.trim(line)}"

    assert offenders == [],
           "a merge sentence interpolates a stored identifier; name it by its kind and " <>
             "carry the value as a data field:\n" <> Enum.join(offenders, "\n")
  end
end
