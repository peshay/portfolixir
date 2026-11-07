defmodule Portfolixir.News.TextTest do
  # A feed's titles and excerpts leave the parser as plain text (ADR-0056
  # §9, "Stored text is data"; Sprint 27 plan D-6). Synthetic strings only.
  # Invisible characters are written as escapes here, never literally, so the
  # repository's invisible-Unicode gate stays quiet.
  use ExUnit.Case, async: true

  alias Portfolixir.Input.Text, as: InputText
  alias Portfolixir.News.Text

  # User story:
  # As the operator and the agent who read a feed's headlines,
  # I want every title and excerpt stored as plain text, its HTML removed
  # and its entities decoded once,
  # so that nothing a feed sends is ever rendered as markup, and an escaped
  # tag stays the visible text it was meant to be.
  #
  # Acceptance criteria:
  # - Tags, comments and the content of script and style elements are
  #   removed by a single pass; a block tag leaves a space, an inline one
  #   nothing.
  # - A `<` that opens no tag is text; a quoted `>` inside a tag does not
  #   end it; an unclosed tag or comment swallows the rest.
  # - Entities are decoded once, after the tags are gone: `&lt;script&gt;`
  #   becomes the text `<script>`, and `&amp;lt;` becomes `&lt;`.
  describe "HTML" do
    test "tags are removed, their text kept" do
      assert Text.title(~s(<b>Bold</b> and <a href="https://x.example/">a link</a>)) ==
               "Bold and a link"
    end

    test "block tags leave a space, inline tags nothing" do
      assert Text.excerpt("<p>One</p><p>Two</p><br/>Three<li>Four</li>") == "One Two Three Four"
      assert Text.title("H<sub>2</sub>O and <EM>CO</EM><sub>2</sub>") == "H2O and CO2"
    end

    test "script and style content is removed with its tags, in any letter case" do
      assert Text.excerpt("<script>evil()</script>Text<STYLE>p { x: 1 }</STYLE> stays") ==
               "Text stays"

      assert Text.excerpt("<script>never closed") == nil
      assert Text.excerpt("<script>a</scriptx>b</script >after") == "after"
    end

    test "comments are removed, an unclosed one with the rest" do
      assert Text.title("<!-- hidden -->Visible<!-- x > y -->") == "Visible"
      assert Text.title("Visible<!-- never closed") == "Visible"
    end

    test "a title made of nested and unclosed tags keeps only its text" do
      assert Text.title("<b><i><u>Hello</b></i></u") == "Hello"
      assert Text.title("<div><span><a><b><i>Deep</i>er</b></a></span></div") == "Deeper"
      assert Text.title(~s(<a title="x>y" data-z='a>b'>Link</a>)) == "Link"
      assert Text.title("<b unclosed attr=\"oops") == nil
    end

    test "a less-than sign that opens no tag is text" do
      assert Text.title("a < b and c > d") == "a < b and c > d"
      assert Text.title("<<b>>x") == "<>x"
      assert Text.title("1 <2") == "1 <2"
    end

    test "entities are decoded once, after the tags are gone" do
      assert Text.title("&lt;script&gt;alert(1)&lt;/script&gt;") == "<script>alert(1)</script>"
      assert Text.title("&amp;lt;b&amp;gt;") == "&lt;b&gt;"
      assert Text.title("AT&amp;T &quot;quoted&quot; &apos;s") == ~s(AT&T "quoted" 's)
      assert Text.title("AT&T and &unknown; and &") == "AT&T and &unknown; and &"
    end

    test "numeric references are decoded, invalid ones left as written" do
      assert Text.title("&#65;&#x42;&#X43;") == "ABC"

      assert Text.title("&#xD800; &#x110000; &#99999999999;") ==
               "&#xD800; &#x110000; &#99999999999;"
    end

    test "the common named entities of a feed's HTML are decoded" do
      assert Text.title("caf&eacute; &ndash; M&uuml;ller &euro;5&nbsp;&hellip;") ==
               "café – Müller €5 …"
    end
  end

  # User story:
  # As the operator,
  # I want control characters removed and whitespace collapsed, and
  # invisible characters kept as the feed sent them,
  # so that the text reads as one line, and the evidence of a hidden
  # character is spelled by the companion and the screen, not erased
  # (ADR-0054 §4; D-6).
  #
  # Acceptance criteria:
  # - Tab, line feed and carriage return become a space; every other C0
  #   control, DEL and every C1 control is removed, whether sent raw or as a
  #   numeric reference.
  # - Runs of whitespace collapse to one space, the ends trimmed.
  # - Zero-width and bidirectional characters are kept as received.
  # - Text that is not valid UTF-8 has its broken bytes replaced, not passed on.
  describe "characters" do
    test "controls are removed, line breaks and tabs become spaces" do
      assert Text.title("a\u0000b\u0007c\u007Fd\u0085e\u009Ff") == "abcdef"
      assert Text.title("line\none\ttab\r\nend") == "line one tab end"
      assert Text.title("ref&#0;&#7;&#x9F;s") == "refs"
    end

    test "whitespace collapses and the ends are trimmed" do
      assert Text.excerpt("  a \n\n  b\u00A0\u00A0c\u3000d  ") == "a b c d"
      assert Text.title("   ") == nil
      assert Text.title("<b> </b>") == nil
    end

    test "invisible characters are kept as received" do
      raw = "a\u200Bb\u200Ec\u202Ed\u2066e\u2069f\uFEFFg"

      assert Text.title(raw) == raw
      assert InputText.invisible_count(Text.title(raw)) == 6
    end

    test "invalid UTF-8 is replaced, never passed on" do
      assert Text.title(<<"ok ", 0xFF, " end">>) == "ok \uFFFD end"
      assert String.valid?(Text.excerpt(<<0xC3, 0x28, "x">>))
    end

    test "nil and empty text stay nil" do
      assert Text.title(nil) == nil
      assert Text.excerpt("") == nil
    end
  end

  # User story:
  # As the operator,
  # I want a title capped at 160 and an excerpt at 600 characters, and the
  # cleaning linear in the text's length,
  # so that a feed cannot store an article, and a hostile excerpt cannot
  # make the parse slow.
  #
  # Acceptance criteria:
  # - A title keeps at most 160 code points, an excerpt 600, cut between
  #   graphemes (so at most as many graphemes as well), counted as
  #   PostgreSQL counts a text's length.
  # - A 1 MB excerpt of each pathological shape (open brackets, ampersands,
  #   unclosed comments, unclosed quotes, nested tags) is cleaned in well
  #   under a second.
  describe "caps and linearity" do
    test "a title keeps 160 code points, an excerpt 600" do
      assert Text.title(String.duplicate("a", 161)) == String.duplicate("a", 160)
      assert Text.excerpt(String.duplicate("b", 601)) == String.duplicate("b", 600)
      assert Text.title_max() == 160
      assert Text.excerpt_max() == 600
    end

    test "the cut never splits a grapheme" do
      combined = String.duplicate("e\u0301", 100)
      title = Text.title(combined)

      assert InputText.codepoint_length(title) == 160
      assert String.length(title) == 80
      assert title == String.duplicate("e\u0301", 80)

      odd = "x" <> combined
      assert InputText.codepoint_length(Text.title(odd)) == 159
    end

    test "the cap counts the text left after cleaning" do
      assert Text.title(String.duplicate("<b>a</b>", 200)) == String.duplicate("a", 160)
    end

    test "a 1 MB excerpt of every pathological shape is cleaned in linear time" do
      mb = 1_024 * 1_024

      shapes = [
        String.duplicate("<", mb),
        String.duplicate("&", mb),
        String.duplicate("&#", div(mb, 2)),
        String.duplicate("<!--", div(mb, 4)),
        "<a title=\"" <> String.duplicate("x", mb),
        String.duplicate("<b><i>", div(mb, 6)),
        "<script>" <> String.duplicate("</scrip", div(mb, 7)),
        String.duplicate("a \n", div(mb, 3))
      ]

      for shape <- shapes do
        {us, excerpt} = :timer.tc(fn -> Text.excerpt(shape) end)

        # A quadratic pass over 1 MB is about 10^12 steps, hours rather than
        # seconds; a linear one takes milliseconds. 10 s keeps that line
        # under a loaded suite, where 1 s was missed (1.8 s seen).
        assert us < 10_000_000, "#{binary_part(shape, 0, 12)}… took #{div(us, 1000)} ms"
        assert excerpt == nil or InputText.codepoint_length(excerpt) <= 600
      end
    end
  end
end
