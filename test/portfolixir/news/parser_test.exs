defmodule Portfolixir.News.ParserTest do
  # The news feed parser reads RSS 2.0 and Atom 1.0 into plain items
  # (ADR-0056 A1, Sprint 27 plan D-7). Its attack cases live in
  # parser_attack_test.exs; this file pins what a well-formed feed becomes.
  # Synthetic fixtures only (test/support/fixtures/news): invented issuers,
  # hosts under .example.
  use ExUnit.Case, async: true

  alias Portfolixir.News.Parser
  alias Portfolixir.News.Parser.Item

  @fixtures "test/support/fixtures/news"

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp rss_item(fields),
    do: ~s(<rss version="2.0"><channel><title>T</title><item>#{fields}</item></channel></rss>)

  defp atom_entry(fields),
    do:
      ~s(<feed xmlns="http://www.w3.org/2005/Atom"><title>T</title><entry>#{fields}</entry></feed>)

  defp only_item(body) do
    assert {:ok, %{items: [item]}} = Parser.parse(body)
    item
  end

  # User story:
  # As the operator who registers an RSS 2.0 feed,
  # I want each item read into a title, a link, a guid, a publication time,
  # an excerpt and the domain of its original source,
  # so that the news layer can store, match and deduplicate it without ever
  # handling the feed's XML again.
  #
  # Acceptance criteria:
  # - Items come out in the feed's order, as `%Item{}` structs.
  # - Title and excerpt are plain text (`News.Text`); the excerpt is the
  #   description, else `content:encoded`.
  # - The link is an absolute http or https URL or nil; a `javascript:` link
  #   is dropped.
  # - `published_at` is read from RFC 822 (`pubDate`), else `dc:date`, as a
  #   UTC `DateTime` to the second; an unreadable date is nil.
  # - `source_domain` is the host of `<source url=…>`.
  describe "RSS 2.0" do
    test "the sample feed's items, in order" do
      assert {:ok, %{format: :rss, items: [first, second, third]}} =
               Parser.parse(fixture("rss2_sample.xml"))

      assert first == %Item{
               title: "Example Industries & Partners report record quarter",
               link: "https://wire.example/news/1",
               guid: "wire-0001",
               published_at: ~U[2026-11-03 13:30:00Z],
               excerpt: "Revenue rose. Margins held & costs fell.",
               source_domain: "origin.example"
             }

      assert second == %Item{
               title: "Sample Corp names a new chair",
               link: "https://wire.example/news/2",
               guid: "https://wire.example/news/2",
               published_at: ~U[2026-11-04 08:00:00Z],
               excerpt: "The board met.",
               source_domain: nil
             }

      assert third == %Item{
               title: "An item with an unreadable date and a script link",
               link: nil,
               guid: nil,
               published_at: ~U[2026-11-05 09:15:00Z],
               excerpt: nil,
               source_domain: nil
             }
    end

    test "RFC 822 dates in their common spellings" do
      for {raw, expected} <- [
            {"Tue, 03 Nov 2026 14:30:00 GMT", ~U[2026-11-03 14:30:00Z]},
            {"03 Nov 2026 14:30:00 UT", ~U[2026-11-03 14:30:00Z]},
            {"Tue, 3 Nov 2026 14:30:00 Z", ~U[2026-11-03 14:30:00Z]},
            {"Tue, 03 Nov 2026 14:30:00 EST", ~U[2026-11-03 19:30:00Z]},
            {"Tue, 03 Nov 2026 14:30:00 PDT", ~U[2026-11-03 21:30:00Z]},
            {"Tue, 03 Nov 2026 14:30:00 -0230", ~U[2026-11-03 17:00:00Z]},
            {"tue, 03 nov 2026 14:30 +0000", ~U[2026-11-03 14:30:00Z]},
            {"  Tue,  03 Nov 2026 14:30:00 +0100  ", ~U[2026-11-03 13:30:00Z]},
            {"Tue, 31 Feb 2026 10:00:00 GMT", nil},
            {"Tue, 03 Nov 2026 25:00:00 GMT", nil},
            {"Tue, 03 Foo 2026 10:00:00 GMT", nil},
            {"Tue, 03 Nov 2026 10:00:00 XYZ", nil},
            {"2026-11-03T14:30:00Z", nil},
            {String.duplicate("1", 200), nil}
          ] do
        item = only_item(rss_item("<title>D</title><pubDate>#{raw}</pubDate>"))
        assert item.published_at == expected, inspect(raw)
      end
    end

    test "a link is kept only when it is an absolute http or https URL" do
      for {raw, expected} <- [
            {"https://wire.example/a?b=1&amp;c=2", "https://wire.example/a?b=1&c=2"},
            {"HTTP://Wire.Example/a", "HTTP://Wire.Example/a"},
            {"/relative/path", nil},
            {"javascript:alert(1)", nil},
            {"data:text/html,x", nil},
            {"https://wire.example/a b", nil},
            {"https://", nil},
            {"https://wire.example/" <> String.duplicate("a", 2_100), nil}
          ] do
        assert only_item(rss_item("<title>L</title><link>#{raw}</link>")).link == expected,
               raw
      end
    end

    test "the source domain is the lower-cased host of an http or https source URL" do
      assert only_item(
               rss_item(
                 ~s(<title>S</title><source url="https://News.Origin.Example:8443/f">O</source>)
               )
             ).source_domain ==
               "news.origin.example"

      assert only_item(
               rss_item(~s(<title>S</title><source url="ftp://origin.example/f">O</source>))
             ).source_domain ==
               nil

      assert only_item(rss_item("<title>S</title><source>No URL</source>")).source_domain == nil
    end

    test "a guid is plain text, its whitespace collapsed and capped" do
      item = only_item(rss_item("<title>G</title><guid>  id\n 1  </guid>"))
      assert item.guid == "id 1"

      long = only_item(rss_item("<title>G</title><guid>#{String.duplicate("g", 2_000)}</guid>"))
      assert String.length(long.guid) == Parser.guid_max()
    end

    test "a feed with no item reads as an empty list" do
      assert Parser.parse(~s(<rss version="2.0"><channel><title>T</title></channel></rss>)) ==
               {:ok, %{format: :rss, items: []}}
    end

    test "an item nested anywhere but under the channel is not an item" do
      body =
        ~s(<rss version="2.0"><channel><title>T</title><image><item><title>No</title></item></image>) <>
          "<item><title>Yes</title></item></channel></rss>"

      assert {:ok, %{items: [%Item{title: "Yes"}]}} = Parser.parse(body)
    end
  end

  # User story:
  # As the operator who registers an Atom 1.0 feed (a regulator's or an
  # issuer's filings),
  # I want each entry read into the same item shape,
  # so that the news layer treats both formats alike.
  #
  # Acceptance criteria:
  # - The root is `feed` in the Atom namespace; its entries come out in
  #   order.
  # - The link is the `alternate` link (or one without `rel`); the guid is
  #   the entry's `id`.
  # - `published_at` is `published`, else `updated`, read as RFC 3339 and
  #   kept to the second in UTC.
  # - The excerpt is the summary, else the content (XHTML content's text).
  # - `source_domain` is the host of the `<source>`'s alternate link.
  describe "Atom 1.0" do
    test "the sample feed's entries, in order" do
      assert {:ok, %{format: :atom, items: [first, second]}} =
               Parser.parse(fixture("atom_sample.xml"))

      assert first == %Item{
               title: "Example Industries files an annual report",
               link: "https://filings.example/doc/1",
               guid: "urn:synthetic:filing:1",
               published_at: ~U[2026-11-04 21:05:00Z],
               excerpt: "The annual report is available.",
               source_domain: "origin.example"
             }

      assert second == %Item{
               title: "Sample Corp: update",
               link: "https://filings.example/doc/2",
               guid: "urn:synthetic:filing:2",
               published_at: ~U[2026-11-05 08:00:00Z],
               excerpt: "First paragraph. Second paragraph.",
               source_domain: nil
             }
    end

    test "an unreadable or date-only timestamp is nil" do
      for raw <- ["2026-11-05", "yesterday", "2026-13-01T00:00:00Z", ""] do
        item = only_item(atom_entry("<title>D</title><updated>#{raw}</updated>"))
        assert item.published_at == nil, raw
      end
    end

    test "the alternate link wins over self and enclosure links, wherever it stands" do
      item =
        only_item(
          atom_entry(
            ~s(<title>L</title><link rel="self" href="https://f.example/self"/>) <>
              ~s(<link rel="alternate" href="https://f.example/alt"/>)
          )
        )

      assert item.link == "https://f.example/alt"
    end
  end
end
