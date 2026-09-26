defmodule Portfolixir.Input.TextTest do
  # E25 S4, G24 and G17 (#889): text the changesets accepted but PostgreSQL
  # refuses (a NUL character, a name longer than its column counted in code
  # points rather than graphemes) raised in the database instead of answering
  # a field error. One text rule is shared by every writer and mirrored in the
  # import parsers.
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias Portfolixir.Input.Text

  defp changeset(attrs, opts) do
    {%{}, %{name: :string}}
    |> cast(attrs, [:name])
    |> Text.validate(:name, opts)
  end

  # User story:
  # As an operator or agent naming a record,
  # I want a name the database cannot store to be refused with a field error,
  # so that a stray control character or an over-long pasted name never ends
  # the request with a server error.
  #
  # Acceptance criteria:
  # - A single-line value refuses NUL, every other C0 and C1 control
  #   character and DEL; a multi-line value keeps tab, line feed and carriage
  #   return.
  # - The length bound counts code points, the unit of a varchar column, so a
  #   name of many combining marks is measured the way the database does.
  # - A value that is not valid UTF-8 is refused.
  test "control characters and invalid UTF-8 are refused, line breaks only where text is multi-line" do
    assert changeset(%{"name" => "Café Growth ETF"}, max: 255).valid?

    for refused <- ["a\u0000b", "a\u0007b", "a\nb", "a\tb", "a\u007Fb", "a\u0085b", <<0xFF>>] do
      refute changeset(%{"name" => refused}, max: 255).valid?, "accepted #{inspect(refused)}"
    end

    assert changeset(%{"name" => "line one\nline two\r\n\tindented"}, multiline: true).valid?
    refute changeset(%{"name" => "a\u0000b"}, multiline: true).valid?
    refute changeset(%{"name" => "a\u001Bb"}, multiline: true).valid?
  end

  test "the length bound counts code points, not graphemes" do
    # One grapheme, three code points.
    combined = "é́"
    assert String.length(combined) == 1

    assert changeset(%{"name" => String.duplicate("a", 255)}, max: 255).valid?
    refute changeset(%{"name" => String.duplicate("a", 256)}, max: 255).valid?
    refute changeset(%{"name" => String.duplicate(combined, 100)}, max: 255).valid?
  end

  test "check/2 returns the same verdict for a value outside a changeset" do
    assert Text.check("Depot A", max: 255) == :ok
    assert Text.check("Depot\u0000A", max: 255) == {:error, :control_characters}
    assert Text.check(String.duplicate("a", 256), max: 255) == {:error, :too_long}
    assert Text.check(<<0xFF>>, max: 255) == {:error, :invalid_encoding}
  end

  test "check_map/2 judges every key and text value of a free-form map at any depth" do
    assert Text.check_map(%{"sector" => "Tech", "rank" => 3, "listed" => true, "gone" => nil}) ==
             :ok

    assert Text.check_map(%{"summary" => "line one\nline two\ttab"}) == :ok
    assert Text.check_map(%{"a" => %{"b" => ["ok", 1]}}) == :ok

    assert Text.check_map(%{"sector" => "Tech\u0000"}) == {:error, :control_characters}
    assert Text.check_map(%{"a\u0000b" => "Tech"}) == {:error, :control_characters}
    assert Text.check_map(%{"line\nbreak" => "Tech"}) == {:error, :control_characters}

    assert Text.check_map(%{"a" => %{"b" => ["ok", "bad\u0000"]}}) ==
             {:error, :control_characters}

    assert Text.check_map(%{String.duplicate("k", 256) => "v"}) == {:error, :too_long}
    assert Text.check_map(%{1 => "v"}) == {:error, :invalid_key}
  end

  # One character by its code point: the source file carries no invisible
  # character itself (the repository's pre-commit hook refuses them).
  defp c(code_point), do: <<code_point::utf8>>

  # User story (E25 S7, G20):
  # As an operator whose agent reads what is stored — research entries,
  # rule and event notes, names, imported rows —
  # I want text that carries characters I cannot see refused where it is
  # written,
  # so that no hidden instruction survives my review of an append-only
  # record because it renders as nothing on my screen.
  #
  # Acceptance criteria:
  # - Refused, with a field error naming the characters by code point: the
  #   Unicode tag characters (U+E0000-U+E007F), the bidirectional controls
  #   (U+061C, U+200E, U+200F, U+202A-U+202E, U+2066-U+2069), the other
  #   invisible format characters (the soft hyphen U+00AD, U+180E,
  #   U+200B-U+200D, U+2060-U+2065, U+206A-U+206F, U+FEFF, U+FFF9-U+FFFB,
  #   U+1BCA0-U+1BCA3, U+1D173-U+1D17A) and a run of two or more variation
  #   selectors.
  # - A single variation selector (an emoji's presentation) passes, and so
  #   does visible text in any script.
  # - The rule is part of the one text rule every writer meets: check/2,
  #   validate/3 and the free-form map check all refuse it.
  test "invisible characters are refused, named by code point; one variation selector passes" do
    refused = [
      "zero" <> c(0x200B) <> "width",
      "soft" <> c(0x00AD) <> "hyphen",
      "joined" <> c(0x200D) <> "word",
      "non" <> c(0x200C) <> "joiner",
      "word" <> c(0x2060) <> "joiner",
      c(0xFEFF) <> "bom",
      "arabic " <> c(0x061C) <> " mark",
      "rtl" <> c(0x200F) <> "mark",
      "embed" <> c(0x202E) <> "txet",
      "isolate" <> c(0x2066) <> "x" <> c(0x2069),
      "mongolian" <> c(0x180E) <> "vowel",
      "annot" <> c(0xFFF9) <> "ation",
      "tag " <> c(0xE0001) <> c(0xE0041) <> c(0xE007F),
      "shorthand" <> c(0x1BCA0),
      "music" <> c(0x1D173),
      "selectors" <> c(0xFE00) <> c(0xFE01),
      "supplement" <> c(0xE0100) <> c(0xE0101) <> c(0xE0102)
    ]

    for text <- refused do
      assert Text.check(text, multiline: true) == {:error, :invisible_characters},
             "accepted #{inspect(text, binaries: :as_binaries)}"

      refute changeset(%{"name" => text}, max: 255).valid?
    end

    visible = [
      "heart " <> c(0x2764) <> c(0xFE0F),
      "Gr" <> c(0xFC) <> c(0xDF) <> "e, " <> c(0x682A) <> c(0x5F0F) <> ", " <> c(0x05E2),
      "tab\tand\nline"
    ]

    for text <- visible do
      assert Text.check(text, multiline: true) == :ok, inspect(text)
    end

    text = "a" <> c(0x200B) <> "b" <> c(0x200B) <> "c" <> c(0x00AD) <> "d"
    assert %{errors: [name: {message, keys}]} = changeset(%{"name" => text}, max: 255)

    assert message ==
             "must not contain invisible characters (%{characters}); retype the text without them"

    assert keys[:characters] == "U+200B, U+00AD"
    assert keys[:validation] == :text

    assert Text.check_map(%{"sector" => "Tech" <> c(0x200B)}) == {:error, :invisible_characters}

    assert Text.check_map(%{("k" <> c(0x200B) <> "ey") => "Tech"}) ==
             {:error, :invisible_characters}
  end

  # User story (E25 S7 review round, S7E-3):
  # As an operator who writes an emoji into a note or a name,
  # I want an emoji built from several pictographs joined by a zero-width
  # joiner — a person at a laptop, a family, the rainbow flag — to be stored,
  # so that the refusal of invisible characters takes only what renders as
  # nothing, not a joiner I see as one glyph.
  #
  # Acceptance criteria:
  # - U+200D passes where it joins two pictographs: the character before it is
  #   a pictograph (a skin tone included) or a VS16 right after one, and the
  #   character after it is a pictograph. Anywhere else it is refused.
  # - The tag characters stay refused, so the three subdivision flags
  #   (England, Scotland, Wales) are refused with them; so is the zero-width
  #   non-joiner U+200C, a Persian word's included.
  # - The count and the escape agree with the rule (shared fixture).
  test "a zero-width joiner between two pictographs is an emoji, and passes" do
    passing = [
      c(0x1F469) <> c(0x200D) <> c(0x1F4BB),
      c(0x1F468) <> c(0x200D) <> c(0x1F469) <> c(0x200D) <> c(0x1F467),
      c(0x1F3F3) <> c(0xFE0F) <> c(0x200D) <> c(0x1F308),
      c(0x1F469) <> c(0x1F3FD) <> c(0x200D) <> c(0x1F4BB),
      c(0x2764) <> c(0xFE0F) <> c(0x200D) <> c(0x1F525),
      c(0x1F937) <> c(0x200D) <> c(0x2640) <> c(0xFE0F)
    ]

    for text <- passing do
      assert Text.check("Note " <> text, multiline: true) == :ok, inspect(text)
      assert Text.invisible_count(text) == 0
      assert Text.escape_invisible(text) == text
      assert changeset(%{"name" => text}, max: 255).valid?
    end

    refused = [
      {"a" <> c(0x200D) <> "b", 1},
      {c(0x1F468) <> c(0x200D) <> "x", 1},
      {"x" <> c(0x200D) <> c(0x1F468), 1},
      {c(0x200D) <> c(0x1F468), 1},
      {c(0x1F468) <> c(0x200D), 1},
      {c(0x1F468) <> c(0x200D) <> c(0x200D) <> c(0x1F4BB), 2},
      {"x" <> c(0xFE0F) <> c(0x200D) <> c(0x1F468), 1},
      {c(0x1F3F4) <>
         c(0xE0067) <>
         c(0xE0062) <>
         c(0xE0073) <>
         c(0xE0063) <>
         c(0xE0074) <>
         c(0xE007F), 6},
      {c(0x0645) <> c(0x06CC) <> c(0x200C) <> c(0x062E) <> c(0x0648), 1}
    ]

    for {text, count} <- refused do
      assert Text.check(text, multiline: true) == {:error, :invisible_characters},
             "accepted #{inspect(text, binaries: :as_binaries)}"

      assert Text.invisible_count(text) == count, inspect(text)
    end
  end

  # User story (E25 S7, G20; pick G12.2 = B, board 12-e25-new-marks):
  # As the operator reading a record stored before the refusal existed,
  # I want the characters I cannot see counted and spelled out,
  # so that the screen can say how many there are and show where, the way the
  # MCP companion spells them for the agent.
  #
  # Acceptance criteria:
  # - invisible_count/1 counts every refused code point (each selector of a
  #   run, never a single one).
  # - escape_invisible/1 replaces each by "[U+XXXX]" (upper-case hex, at
  #   least four digits) and leaves every other character as it is.
  # - Both agree with the shared cases the companion's escape is pinned to
  #   (mcp-server/test/fixtures/invisible-text.json).
  test "invisible characters are counted and escaped the way the companion escapes them" do
    assert Text.invisible_count("clean text") == 0
    assert Text.invisible_count("a" <> c(0x200B) <> "b" <> c(0x200B)) == 2
    assert Text.invisible_count("heart " <> c(0x2764) <> c(0xFE0F)) == 0
    assert Text.invisible_count("x" <> c(0xFE00) <> c(0xFE01) <> c(0xFE02)) == 3
    assert Text.invisible_count(nil) == 0

    assert Text.escape_invisible("tag " <> c(0xE0041)) == "tag [U+E0041]"

    cases =
      "mcp-server/test/fixtures/invisible-text.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")

    assert length(cases) >= 10

    for %{"input" => input, "escaped" => escaped, "count" => count} <- cases do
      assert Text.escape_invisible(input) == escaped, inspect(input)
      assert Text.invisible_count(input) == count, inspect(input)

      assert Text.check(input, multiline: true) ==
               if(count == 0, do: :ok, else: {:error, :invisible_characters})
    end
  end
end
