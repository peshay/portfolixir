defmodule Portfolixir.Invariants.IsoDateInputTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer of a product whose every display date is ISO,
  # I want date entry to accept and display ISO too,
  # so that entering and reading a date never use two formats on the same
  # screen (UX-DR19, issue 641 — native type="date" renders the browser
  # locale's format, e.g. MM/DD/YYYY, and cannot be told otherwise).
  #
  # Acceptance criteria:
  # - No `type="date"` input ships in the web layer; date fields are ISO
  #   text inputs with the YYYY-MM-DD pattern.

  test "no native type=\"date\" inputs remain in the web layer" do
    offenders =
      "lib/portfolixir_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> String.contains?(line, ~s(type="date")) end)
        |> Enum.map(fn {_, lineno} -> "#{path}:#{lineno}" end)
      end)

    assert offenders == [], """
    Native date inputs render the browser locale's format and break the
    ISO-everywhere rule (UX-DR19). Use the ISO text-input pattern instead
    (type="text" placeholder="YYYY-MM-DD"
    pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}" maxlength="10" — no numeric
    inputmode: the iOS digits keypad has no dash):
    #{Enum.join(offenders, "\n")}
    """
  end
end
