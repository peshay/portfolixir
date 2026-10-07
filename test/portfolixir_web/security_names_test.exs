defmodule PortfolixirWeb.SecurityNamesTest do
  # The table rows' twin rule (#1057, board
  # `mockups/ux-design-2026-10-04/06-phone-wealth`, pick J6.2 A): one shared
  # function decides, per table, which rows read the same and what tells them
  # apart, so the Positions table and the contribution table cannot drift
  # into two rules. Plain maps in the shape both tables carry; every name and
  # identifier is synthetic.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias PortfolixirWeb.SecurityNames

  defp row(security_id, name, extra \\ %{}),
    do: Map.merge(%{security_id: security_id, name: name, isin: nil}, extra)

  defp ids(rows, key), do: rows |> SecurityNames.put_twin_ids(key) |> Enum.map(& &1.twin_id)

  # User story (#1057, pick J6.2 A):
  # As the operator reading a table of positions,
  # I want an identifier after a name only where two rows of the table would
  # read the same,
  # so that the common row stays as quiet as today and a twin says which
  # security it is.
  #
  # Acceptance criteria:
  # - A key one security alone carries gets no identifier.
  # - Twins take the first of the chain ISIN, WKN that is present on every
  #   twin and distinct across them; else each takes its number.
  # - An empty string counts as absent.
  # - The same security twice under one key is no collision.
  test "the chain is ISIN, else WKN, else the number, and only on a collision" do
    assert ids([row(1, "Alpha"), row(2, "Beta")], & &1.name) == [nil, nil]

    isins = [row(1, "Twin", %{isin: "XSNAMES00011"}), row(2, "Twin", %{isin: "XSNAMES00029"})]
    assert ids(isins, & &1.name) == [{:isin, "XSNAMES00011"}, {:isin, "XSNAMES00029"}]

    wkns = [
      row(1, "Twin", %{isin: "XSNAMES00011", wkn: "NAMES1"}),
      row(2, "Twin", %{isin: "", wkn: "NAMES2"})
    ]

    assert ids(wkns, & &1.name) == [{:wkn, "NAMES1"}, {:wkn, "NAMES2"}]

    same_wkn = [row(7, "Twin", %{wkn: "NAMES1"}), row(9, "Twin", %{wkn: "NAMES1"})]
    assert ids(same_wkn, & &1.name) == [{:number, 7}, {:number, 9}]

    # One twin with only an ISIN, the other with only a WKN: neither
    # identifier is on every twin, so both take their number.
    isin_wkn = [row(11, "Twin", %{isin: "XSNAMES00011"}), row(12, "Twin", %{wkn: "NAMES2"})]
    assert ids(isin_wkn, & &1.name) == [{:number, 11}, {:number, 12}]

    # A payload without a WKN field (the contribution's) falls through too.
    assert ids([row(3, "Twin"), row(4, "Twin")], & &1.name) == [{:number, 3}, {:number, 4}]

    assert ids([row(5, "Twin"), row(5, "Twin")], & &1.name) == [nil, nil]
  end

  # User story (#1057, pick J6.2 A; the review of PR γ U4):
  # As the operator reading a table of positions,
  # I want a name to count as a twin wherever the table holds another
  # security under it, whichever depot either sits in,
  # so that two securities never read as one row printed twice — a depot
  # name is no tie-breaker, because two depots may share a name and the
  # Depot column can be switched off.
  #
  # Acceptance criteria:
  # - The collision is decided over every row of the list by the displayed
  #   name: one name held by two securities in two depots tags both.
  # - One security held in two depots is never its own twin: no identifier.
  # - Every row of a colliding name is tagged, wherever it sits in the list,
  #   and every row of one security carries the same identifier.
  test "a twin is the same name for another security, over the whole table" do
    rows = [
      row(1, "Twin", %{depot: "A", isin: "XSNAMES00011"}),
      row(2, "Solo", %{depot: "A"}),
      row(3, "Twin", %{depot: "B", isin: "XSNAMES00029"}),
      row(4, "Held twice", %{depot: "A", isin: "XSNAMES00037"}),
      row(4, "Held twice", %{depot: "B", isin: "XSNAMES00037"}),
      row(1, "Twin", %{depot: "B", isin: "XSNAMES00011"})
    ]

    assert ids(rows, & &1.name) == [
             {:isin, "XSNAMES00011"},
             nil,
             {:isin, "XSNAMES00029"},
             nil,
             nil,
             {:isin, "XSNAMES00011"}
           ]
  end

  # User story (#1057, pick J6.2 A; the review of PR γ U4):
  # As the operator reading two names that look the same on the screen,
  # I want them to count as twins even where their stored bytes differ,
  # so that a name in decomposed Unicode, or with a doubled space the
  # browser collapses, still says which security it is.
  #
  # Acceptance criteria:
  # - Names are compared as a reader sees them: Unicode NFC, and every run
  #   of whitespace one space (HTML collapses it), edges trimmed.
  # - Nothing more is folded: `SecurityResolver.skeleton/1` also lowercases,
  #   applies NFKC and folds Cyrillic and Greek lookalikes, which is
  #   "looks alike to a reader" for the import's at-risk check, not "reads
  #   the same in this table". Case stays significant here.
  test "names that read the same collide, whatever their bytes" do
    nfc = :unicode.characters_to_nfc_binary("M\u00FCller AG")
    nfd = :unicode.characters_to_nfd_binary("M\u00FCller AG")
    refute nfc == nfd

    assert ids(
             [row(1, nfc, %{isin: "XSNAMES00011"}), row(2, nfd, %{isin: "XSNAMES00029"})],
             & &1.name
           ) ==
             [{:isin, "XSNAMES00011"}, {:isin, "XSNAMES00029"}]

    assert ids([row(1, "Juniper Rail AG"), row(2, "Juniper  Rail AG")], & &1.name) ==
             [{:number, 1}, {:number, 2}]

    assert ids([row(1, "Juniper Rail AG"), row(2, " Juniper\tRail AG ")], & &1.name) ==
             [{:number, 1}, {:number, 2}]

    # Case is what a reader sees, so it stays significant.
    assert ids([row(1, "Juniper Rail AG"), row(2, "JUNIPER RAIL AG")], & &1.name) == [nil, nil]

    # A row without a name never collides.
    assert ids([row(1, nil), row(2, nil)], & &1.name) == [nil, nil]
  end

  # User story (#1057; the PR γ closing act, edge-case hunter #3):
  # As the operator holding a security whose name was pasted from a web page
  # or a PDF,
  # I want a name with a no-break space to count as the twin of the same
  # name with a plain space,
  # so that two rows that print "Lumen Werke AG" identically still say which
  # security each one is.
  #
  # Acceptance criteria:
  # - U+00A0 (no-break space), U+2007 (figure space) and U+202F (narrow
  #   no-break space) read as a plain space: `String.split/1` keeps them as
  #   part of a word, so they are normalised before the runs collapse.
  # - Any other character stays significant.
  test "a no-break space reads as the plain space it prints as" do
    for space <- [" ", " ", " "] do
      assert SecurityNames.display_key("Lumen#{space}Werke AG") == "Lumen Werke AG"

      assert ids([row(1, "Lumen Werke AG"), row(2, "Lumen#{space}Werke AG")], & &1.name) ==
               [{:number, 1}, {:number, 2}]
    end

    assert SecurityNames.display_key(" Lumen   Werke AG ") ==
             "Lumen Werke AG"

    assert SecurityNames.display_key("   ") == nil
    assert ids([row(1, "Lumen Werke AG"), row(2, "Lumen-Werke AG")], & &1.name) == [nil, nil]
  end

  # User story (#1057, pick J6.2 A, rule ②; the review of PR γ U4):
  # As the operator reading a twin's row, with my eyes or with a screen
  # reader,
  # I want the identifier as a quiet tag after the name that a screen reader
  # names, with a real word break before it,
  # so that it reads as "<name> ISIN <value>" and not as a second name, a
  # bare code or one run-together word.
  #
  # Acceptance criteria:
  # - The identifier renders as `span.twin-id`, preceded by a real space in
  #   the normal flow: the name may wrap before the identifier, and the
  #   text never runs "AGXS…" together.
  # - The value follows a visually hidden "ISIN"/"WKN" and a real space,
  #   both outside the hidden span: a `.visually-hidden` box is absolutely
  #   positioned, so spaces at its edges collapse and cannot separate
  #   anything. The space inside `.twin-id` follows the one before it and
  #   collapses on the screen, so the margin and one word space separate the
  #   identifier visually.
  # - A number needs no label: it reads "no. <id>", with no hidden span.
  # - No identifier renders nothing, not even the space.
  # - The exact HTML is pinned, because a text extraction with a separator
  #   hides whether the spaces are real.
  test "the identifier renders muted after the name with a hidden label" do
    assert render_twin(tag: {:isin, "XSNAMES00011"}) ==
             ~s( <span class="twin-id"><span class="visually-hidden">ISIN</span> XSNAMES00011</span>)

    assert render_twin(tag: {:wkn, "NAMES1"}) ==
             ~s( <span class="twin-id"><span class="visually-hidden">WKN</span> NAMES1</span>)

    assert render_twin(tag: {:number, 42}) == ~s( <span class="twin-id">no. 42</span>)

    assert render_twin(tag: nil) == ""
  end

  # Untrimmed: the leading space is part of what is pinned. A trailing
  # newline from the template would be markup the call sites inherit.
  defp render_twin(assigns), do: render_component(&SecurityNames.twin_id/1, assigns)
end
