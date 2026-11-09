defmodule Portfolixir.News.ReadsWidthTest do
  # Sprint 28, N1 attack AT1: the widths the news reads cut to are counted
  # as the companion counts, in code points (ADR-0056 amendment of
  # 2026-11-08, C5). Pure functions; no database.
  use ExUnit.Case, async: true

  alias Portfolixir.News.Reads

  @combining "́"

  defp width(text), do: text |> String.codepoints() |> length()

  # User story (ADR-0056 §9; the amendment of 2026-11-08, C5; N1 attack AT1):
  # As the operator whose agent pays for every token it reads,
  # I want a name, a title or a clause made of combining marks cut by the
  # characters the companion sends, not by the graphemes a screen draws,
  # so that a name of one letter and 254 accents cannot cost ten times its
  # share of a read's budget.
  #
  # Acceptance criteria:
  # - `short_name/1` of one letter and 254 combining marks: at most 20 code
  #   points, ending in an ellipsis; a name that fits is kept as it is.
  # - `clip_spelled/2` of a 300-code-point run of combining marks at 160:
  #   at most 160 code points.
  test "names and titles of combining marks are cut by code points" do
    name = Reads.short_name("A" <> String.duplicate(@combining, 254))
    assert width(name) <= 20 and String.ends_with?(name, "…"), "#{width(name)} code points"
    assert Reads.short_name("Northwind AG") == "Northwind AG"

    title = Reads.clip_spelled("T" <> String.duplicate(@combining, 299), 160)
    assert width(title) <= 160, "#{width(title)} code points"
  end
end
