defmodule Portfolixir.News.ParserAttackTest do
  # The news feed parser's attack cases (ADR-0056 A1), written before the
  # parser (Sprint 26 carry-forward 6). A feed is XML from a host the
  # operator registered and does not control, so every case here is a
  # document an attacker could serve. Each must be refused with a reason
  # from the parser's fixed set, and refused where it breaches a bound:
  # `Parser.scan/1` reports how far the parse got (the start tags it saw,
  # the deepest level, the items, and the bytes it left unread), so a
  # refusal that read the whole document first fails here.
  #
  # Synthetic fixtures only (test/support/fixtures/news); the large ones are
  # built below. Nothing touches the network or the file system beyond the
  # fixtures. `async: false`: the atom-count case reads a VM-wide counter.
  use ExUnit.Case, async: false

  alias Portfolixir.News.Parser

  @fixtures "test/support/fixtures/news"

  @rss_open ~s(<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0"><channel>) <>
              "<title>Synthetic feed</title><link>https://feed.example/</link>" <>
              "<description>Synthetic</description>"
  @rss_close "</channel></rss>\n"

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp item(n),
    do:
      "<item><title>Synthetic item #{n}</title>" <>
        "<link>https://feed.example/items/#{n}</link><guid>synthetic-#{n}</guid></item>"

  defp feed(items), do: @rss_open <> Enum.map_join(items, &item/1) <> @rss_close

  # The bytes of `body` a scan consumed before it stopped.
  defp consumed(body, stats), do: byte_size(body) - stats.unread

  # A refusal before the XML parser saw a single byte: the reason, no start
  # tag seen, the whole body unread.
  defp assert_refused_unread(body, reason) do
    assert Parser.parse(body) == {:error, {:parse_refused, reason}}
    assert {:refused, ^reason, stats} = Parser.scan(body)
    assert stats.elements == 0, "the parser read #{stats.elements} start tags before refusing"
    assert stats.unread == byte_size(body)
  end

  # User story:
  # As the operator who registers a news feed from a host I do not control,
  # I want a feed carrying a document type declaration refused before it is
  # parsed,
  # so that no entity is ever expanded, no local file is ever read and no
  # URL is ever fetched because a feed asked for it.
  #
  # Acceptance criteria:
  # - An entity-expansion bomb, an external entity naming a local file and
  #   one naming a URL are each refused as `:dtd`, with no start tag read.
  # - Any document type declaration is refused, the empty one included, and
  #   one placed after a comment or a processing instruction too.
  # - An entity reference the document never declared is kept as the text
  #   it is, never resolved.
  describe "a document type declaration" do
    test "an entity-expansion bomb is refused before anything is expanded" do
      assert_refused_unread(fixture("billion_laughs.xml"), :dtd)
    end

    test "an external entity naming a local file is refused before the file is opened" do
      assert_refused_unread(fixture("xxe_file.xml"), :dtd)
    end

    test "an external entity naming a URL is refused before it is fetched" do
      assert_refused_unread(fixture("xxe_url.xml"), :dtd)
    end

    test "any declaration is refused, wherever the prolog places it" do
      for prolog <- [
            "<!DOCTYPE rss>",
            ~s(<?xml version="1.0"?>\n<!DOCTYPE rss SYSTEM "file:///etc/passwd">),
            ~s(\uFEFF<?xml version="1.0"?><!-- a comment --><?pi data?>\n<!DOCTYPE rss []>),
            "<!doctype rss>",
            ~s(<!ENTITY x "y">)
          ] do
        assert_refused_unread(prolog <> feed([1]), :dtd)
      end
    end

    test "a declaration inside the document is refused too" do
      body =
        ~s(<rss version="2.0"><!DOCTYPE rss [<!ENTITY x "y">]><channel>) <>
          item(1) <> @rss_close

      assert {:error, {:parse_refused, reason}} = Parser.parse(body)
      assert reason in Parser.refusal_reasons()
    end

    test "an undeclared entity reference stays the text it is" do
      body = String.replace(feed([1]), "Synthetic item 1", "&xxe;")

      assert {:ok, %{items: [item]}} = Parser.parse(body)
      assert item.title == "&xxe;"
    end
  end

  # User story:
  # As the operator,
  # I want a feed nested deeper than 64 levels refused at the 65th,
  # so that a document 10,000 levels deep costs the parser 65 start tags,
  # not the whole document.
  #
  # Acceptance criteria:
  # - 10,000 levels are refused as `:too_deep`, the parse stopped right
  #   after the 65th start tag with the rest of the document unread.
  # - 64 levels are accepted (the bound is inclusive).
  describe "nesting" do
    test "a document 10,000 levels deep is refused at level 65" do
      levels = 10_000
      opening = ~s(<rss version="2.0"><channel>)

      body =
        opening <>
          String.duplicate("<x>", levels - 2) <>
          String.duplicate("</x>", levels - 2) <> "</channel></rss>"

      assert Parser.parse(body) == {:error, {:parse_refused, :too_deep}}
      assert {:refused, :too_deep, stats} = Parser.scan(body)

      assert stats.depth == Parser.max_depth() + 1
      assert stats.elements == Parser.max_depth() + 1

      assert consumed(body, stats) ==
               byte_size(opening <> String.duplicate("<x>", Parser.max_depth() - 1))
    end

    test "a document exactly 64 levels deep is read" do
      body =
        @rss_open <>
          "<item><title>Deep</title>" <>
          String.duplicate("<x>", Parser.max_depth() - 3) <>
          String.duplicate("</x>", Parser.max_depth() - 3) <> "</item>" <> @rss_close

      assert {:ok, %{items: [%{title: "Deep"}]}} = Parser.parse(body)
      assert {:ok, _feed, stats} = Parser.scan(body)
      assert stats.depth == Parser.max_depth()
    end
  end

  # User story:
  # As the operator,
  # I want a feed answer of more than 5,000 items, or of more bytes than the
  # bounded client fetches, refused,
  # so that one feed cannot fill the store or the memory of the parse.
  #
  # Acceptance criteria:
  # - 5,001 items are refused as `:too_many_items` at the 5,001st item's
  #   start tag, the rest unread; 5,000 are read.
  # - A body one byte over the cap is refused as `:too_large` before the
  #   XML parser sees it; a body exactly at the cap is read.
  describe "size" do
    test "5,001 items are refused at the 5,001st" do
      max = Parser.max_items()
      body = feed(1..(max + 1))

      assert Parser.parse(body) == {:error, {:parse_refused, :too_many_items}}
      assert {:refused, :too_many_items, stats} = Parser.scan(body)

      assert stats.items == max + 1

      assert consumed(body, stats) ==
               byte_size(@rss_open <> Enum.map_join(1..max, &item/1) <> "<item>")
    end

    test "5,000 items are read" do
      max = Parser.max_items()

      assert {:ok, %{items: items}} = Parser.parse(feed(1..max))
      assert length(items) == max
    end

    test "a body one byte over the cap is refused unread" do
      base = feed([1])
      body = base <> String.duplicate(" ", Parser.max_bytes() + 1 - byte_size(base))

      assert byte_size(body) == Parser.max_bytes() + 1
      assert_refused_unread(body, :too_large)
    end

    test "a body exactly at the cap is read" do
      base = feed([1])
      body = base <> String.duplicate(" ", Parser.max_bytes() - byte_size(base))

      assert byte_size(body) == Parser.max_bytes()
      assert {:ok, %{items: [_item]}} = Parser.parse(body)
    end
  end

  # User story:
  # As the operator whose feed answer was cut off in transfer,
  # I want the broken document refused as malformed,
  # so that a half feed is never read as if it were the whole one
  # (Sprint 26 carry-forward 3: a gate's self-test includes a broken input).
  #
  # Acceptance criteria:
  # - A document truncated inside an item, inside a tag, and an empty body
  #   are each refused as `:malformed`.
  # - A document that is XML but not RSS 2.0 or Atom 1.0 is refused as
  #   `:not_a_feed` at its root element.
  # - A parse past its wall-clock bound is refused as `:timeout`.
  describe "broken and foreign documents" do
    test "a truncated document is refused as malformed" do
      assert Parser.parse(fixture("truncated.xml")) == {:error, {:parse_refused, :malformed}}
    end

    test "a document cut inside a tag, and an empty body, are refused as malformed" do
      for body <- [~s(<rss version="2.0"><channel><item><tit), "", "   ", "not xml at all"] do
        assert Parser.parse(body) == {:error, {:parse_refused, :malformed}}, inspect(body)
      end
    end

    test "a declared encoding other than UTF-8 is refused" do
      body = String.replace(feed([1]), ~s(encoding="UTF-8"), ~s(encoding="ISO-8859-1"))

      assert Parser.parse(body) == {:error, {:parse_refused, :unsupported_encoding}}
    end

    test "XML that is not RSS 2.0 or Atom 1.0 is refused at its root" do
      for body <- [
            "<html><body><p>Not a feed</p></body></html>",
            ~s(<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><item/></rdf:RDF>),
            ~s(<rss version="0.91"><channel/></rss>),
            "<feed><entry><title>No namespace</title></entry></feed>"
          ] do
        assert Parser.parse(body) == {:error, {:parse_refused, :not_a_feed}}, body
        assert {:refused, :not_a_feed, stats} = Parser.scan(body)
        assert stats.elements == 1, body
      end
    end

    test "a parse past its wall-clock bound is refused as a timeout" do
      body = feed(1..Parser.max_items())

      assert Parser.parse(body, timeout_ms: 1) == {:error, {:parse_refused, :timeout}}
    end
  end

  # User story:
  # As the operator whose server runs for months,
  # I want a feed's element and attribute names never to become atoms,
  # so that a feed full of invented names cannot fill the VM's atom table
  # and stop the server (AGENTS.md; ADR-0056 A1).
  #
  # Acceptance criteria:
  # - Parsing 1,000 distinct element names and 1,000 distinct attribute
  #   names, none of which exists as an atom, leaves the VM's atom count
  #   unchanged.
  # - The measurement is not vacuous: `xmerl`, which ADR-0056 A1 declines
  #   because it makes atoms from names, moves the count by at least 1,000
  #   on the same kind of document.
  describe "names" do
    defp names_feed(prefix) do
      names =
        Enum.map_join(1..1_000, fn n ->
          ~s(<#{prefix}e#{n} #{prefix}a#{n}="v">text</#{prefix}e#{n}>)
        end)

      @rss_open <> "<item><title>Names</title>" <> names <> "</item>" <> @rss_close
    end

    defp fresh_prefix, do: "zq#{System.unique_integer([:positive])}x"

    test "1,000 distinct element and attribute names leave the atom count unchanged" do
      # Warm up: load every module the parse touches, with other names.
      assert {:ok, _feed} = Parser.parse(names_feed(fresh_prefix()))

      body = names_feed(fresh_prefix())
      before = :erlang.system_info(:atom_count)
      assert {:ok, %{items: [%{title: "Names"}]}} = Parser.parse(body)
      after_parse = :erlang.system_info(:atom_count)

      assert after_parse == before, "parsing made #{after_parse - before} atoms"
    end

    test "the count would see a parser that makes atoms from names" do
      body =
        fresh_prefix()
        |> names_feed()
        |> String.replace(~s(<?xml version="1.0" encoding="UTF-8"?>\n), "")

      before = :erlang.system_info(:atom_count)
      {_document, _rest} = :xmerl_scan.string(String.to_charlist(body), quiet: true)
      assert :erlang.system_info(:atom_count) - before >= 1_000
    end
  end

  test "every refusal names a reason from the fixed set" do
    assert Parser.refusal_reasons() == [
             :too_large,
             :dtd,
             :too_deep,
             :too_many_items,
             :malformed,
             :unsupported_encoding,
             :not_a_feed,
             :timeout,
             :failed
           ]
  end
end
