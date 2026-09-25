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
end
