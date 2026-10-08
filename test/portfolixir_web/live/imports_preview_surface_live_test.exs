defmodule PortfolixirWeb.ImportsPreviewSurfaceLiveTest do
  # The import preview's own surface (Sprint 20 PR α A5), as the board
  # `ux-design-2026-10-07/01-import-preview` draws its before/afters: a
  # re-drop whose rows are all hits (#1168, ②), and the board's "found while
  # drawing" items fixed in the story (D-14).
  #
  # The board's world: Test-Cash, Tagesgeld and Depot Muster, imported from
  # Portfolio Performance and dropped again. Every name, amount and
  # identifier is synthetic.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  @nothing_new "No mapping needed: the import books nothing under this name."

  describe "a re-drop whose rows are all hits (#1168; board 01 ②)" do
    # User story (#1168):
    # As the operator who drops an export again whose bookings are all
    # imported,
    # I want the preview to lead with "nothing will be booked" and to ask for
    # no mapping it does not need,
    # so that a re-drop does not read like a fresh import.
    #
    # Acceptance criteria (board 01 ②, after; found while drawing 3):
    # - The nothing-to-import note leads the preview: under the format line,
    #   before the cards, outside the apply form, said once.
    # - A row with no new booking shows no select: its count keeps "nothing to
    #   create", and `.mapping-target` holds one `.mapping-basis` line, "No
    #   mapping needed: the import books nothing under this name.", in German
    #   "Keine Zuordnung nötig: Der Import bucht unter diesem Namen nichts."
    # - What Apply sends is unchanged: the row carries its prefill as hidden
    #   inputs under the select's names, `cash[<key>]`, `depot[<key>][target]`
    #   and `depot[<key>][cash]`.
    # - The bucket-tag panel is not shown: the file creates no account.
    # - "Confirm import" stays enabled, and confirming books nothing.
    test "the note leads, no row asks for a mapping, and the confirm books nothing",
         %{conn: conn} do
      portfolio = portfolio!()
      applied!(portfolio, history())
      test_cash = named!(CashAccount, "Test-Cash")
      tagesgeld = named!(CashAccount, "Tagesgeld")
      depot = named!(SecuritiesAccount, "Depot Muster")

      {:ok, view, _html} = live(conn, "/imports")
      upload!(view, history())

      assert has_element?(view, "[data-role='nothing-to-import'] + .import-stats")
      refute has_element?(view, "form#pp-import-apply [data-role='nothing-to-import']")
      assert count(view, "[data-role='nothing-to-import']") == 1

      assert text(view, "[data-role='nothing-to-import'] .data-note__body") ==
               "All 5 entries are already imported. The import creates nothing: no booking, no account, no depot, no security."

      for {kind, name, fields} <- [
            {"cash", "Test-Cash",
             [{"cash[#{key("cash", "Test-Cash")}]", "existing:#{test_cash.id}"}]},
            {"cash", "Tagesgeld",
             [{"cash[#{key("cash", "Tagesgeld")}]", "existing:#{tagesgeld.id}"}]},
            {"depot", "Depot Muster",
             [
               {"depot[#{key("depot", "Depot Muster")}][target]", "existing:#{depot.id}"},
               {"depot[#{key("depot", "Depot Muster")}][cash]", "pp:Test-Cash"}
             ]}
          ] do
        refute has_element?(view, row(kind, name) <> " select"), name

        assert text(view, row(kind, name) <> " [data-role='mapping-count']") =~
                 "nothing to create"

        assert text(view, row(kind, name) <> " .mapping-target [data-role='mapping-nothing-new']") ==
                 @nothing_new

        for {field, value} <- fields do
          assert has_element?(
                   view,
                   ~s(#{row(kind, name)} .mapping-target input[type="hidden"][name="#{field}"][value="#{value}"])
                 ),
                 "#{name}: #{field}"
        end
      end

      refute has_element?(view, "#import-bucket-tag")
      refute has_element?(view, "input[name='bucket_tag']")

      refute has_element?(view, "#pp-import-confirm[disabled]")
      refute has_element?(view, "#import-missing-hint")

      before = counts()
      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Created transactions: 0"
      assert counts() == before

      {:ok, view, _html} = live(german(conn), "/imports")
      upload!(view, history())

      assert text(view, row("cash", "Test-Cash") <> " [data-role='mapping-nothing-new']") ==
               "Keine Zuordnung nötig: Der Import bucht unter diesem Namen nichts."
    end

    # User story (#1168):
    # As the operator who drops an export again with a few new bookings,
    # I want only the rows that book something to ask for a mapping,
    # so that I decide what matters and nothing else.
    #
    # Acceptance criteria (board 01 ②: the rule is per row):
    # - Tagesgeld, with a new interest payment, keeps its select; the lead
    #   note is not shown, and the bucket-tag panel is.
    # - Depot Muster, with a new delivery, keeps both selects.
    # - Test-Cash has nothing new, but the depot with new bookings names it as
    #   its cash account ("pp:Test-Cash"), so it keeps its select: that
    #   depot's link reads it.
    # - Once the depot's cash account is an existing account instead, no row
    #   with new bookings links Test-Cash, and its row shows the line.
    test "a row with new bookings asks, and a cash row a new depot links keeps its select",
         %{conn: conn} do
      portfolio = portfolio!()
      applied!(portfolio, history())
      test_cash = named!(CashAccount, "Test-Cash")
      drop = history() ++ [interest("Tagesgeld", "1.40", "2026-03-31"), delivery("Depot Muster")]

      {:ok, view, _html} = live(conn, "/imports")
      upload!(view, drop)

      refute has_element?(view, "[data-role='nothing-to-import']")
      assert has_element?(view, "#import-bucket-tag")

      assert has_element?(view, row("cash", "Tagesgeld") <> " select")
      assert has_element?(view, row("depot", "Depot Muster") <> " select[name$='[target]']")
      assert has_element?(view, row("depot", "Depot Muster") <> " select[name$='[cash]']")
      refute has_element?(view, row("cash", "Tagesgeld") <> " [data-role='mapping-nothing-new']")

      assert text(view, row("cash", "Test-Cash") <> " [data-role='mapping-count']") =~
               "nothing to create"

      assert has_element?(view, row("cash", "Test-Cash") <> " select")
      refute has_element?(view, row("cash", "Test-Cash") <> " [data-role='mapping-nothing-new']")

      view
      |> element("form#pp-import-apply")
      |> render_change(
        keyed(%{"depot" => %{"Depot Muster" => %{"cash" => "existing:#{test_cash.id}"}}})
      )

      refute has_element?(view, row("cash", "Test-Cash") <> " select")

      assert text(view, row("cash", "Test-Cash") <> " [data-role='mapping-nothing-new']") ==
               @nothing_new
    end

    # User story (#1168):
    # As the operator who drops again an export whose depot only ever
    # received deliveries, so the file names no cash account for it,
    # I want the preview not to ask for that depot's cash account,
    # so that a file that books nothing can be confirmed.
    #
    # Acceptance criteria (#1168's report: "Vor dem Import noch zuzuordnen:
    # Verrechnungskonto für Depot …" for a depot that now exists):
    # - The depot's row shows no select and no still-to-map hint names it.
    # - "Confirm import" is enabled, and confirming books nothing.
    test "a depot whose file names no cash account is not asked for one", %{conn: conn} do
      portfolio = portfolio!()
      applied!(portfolio, history())
      test_cash = named!(CashAccount, "Test-Cash")

      {:ok, preview} =
        Imports.parse_portfolio_performance(body([delivery("Depot Zwei")]), filename: "d.json")

      {:ok, _result} =
        Imports.apply(preview, %{
          portfolio: {:existing, portfolio.id},
          cash_accounts: %{},
          depots: %{
            "Depot Zwei" => %{target: {:create, "Depot Zwei"}, cash: {:existing, test_cash.id}}
          }
        })

      rows = history() ++ [delivery("Depot Zwei")]

      {:ok, view, _html} = live(conn, "/imports")
      upload!(view, rows)

      refute has_element?(view, row("depot", "Depot Zwei") <> " select")

      assert text(view, row("depot", "Depot Zwei") <> " [data-role='mapping-nothing-new']") ==
               @nothing_new

      refute has_element?(view, "#import-missing-hint")
      refute has_element?(view, "#pp-import-confirm[disabled]")

      before = counts()
      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Created transactions: 0"
      assert counts() == before
    end
  end

  # User story (#1168):
  # As the operator reading a re-drop on a desktop,
  # I want a depot row with nothing to map to read like the cash rows,
  # so that all rows with nothing new line up.
  #
  # Acceptance criteria (board 01, rule ③):
  # - Above 720 px a depot row whose target is its last child (no cash
  #   select) takes the cash rows' two columns; under 720 px every row is one
  #   column already, so the rule sits in a `min-width: 721px` block.
  test "a depot row with no select takes the cash rows' columns above 720 px (rule ③)" do
    assert File.read!("priv/static/app.css") =~
             ~r/@media \(min-width: 721px\) \{\s*\.mapping-row\.depot:has\(> \.mapping-target:last-child\) \{\s*grid-template-columns: minmax\(10rem, 1fr\) minmax\(14rem, 1\.4fr\);\s*\}\s*\}/
  end

  describe "the bucket tag starts empty (#1174; board 01 ⑦, found while drawing 5)" do
    # User story (#1174):
    # As the operator whose import creates accounts,
    # I want the bucket tag to start empty and to say that it is optional,
    # so that an import never invents a group I did not name, nor labels a
    # converted bank file as a Portfolio Performance import.
    #
    # Acceptance criteria:
    # - The field starts empty and shows its placeholder, "e.g. PP Import" /
    #   "z. B. PP Import".
    # - The sentence over it reads "Optional: a bucket tag for the accounts
    #   this import creates." / "Optional: ein Bucket-Tag für die Konten, die
    #   dieser Import anlegt.", and the "No tag" checkbox is gone: the empty
    #   field already means no tag.
    # - Confirming with the field left empty creates the accounts and no
    #   bucket; a tag typed into it still tags them.
    test "the field starts empty, says it is optional, and an untouched one tags nothing",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/imports")
      upload!(view, history())

      assert has_element?(
               view,
               ~s(#import-bucket-tag input[name="bucket_tag"][value=""][placeholder="e.g. PP Import"])
             )

      assert text(view, "#import-bucket-tag") =~
               "Optional: a bucket tag for the accounts this import creates."

      refute text(view, "#import-bucket-tag") =~ "get the bucket tag"
      refute has_element?(view, "input[name='bucket_skip']")

      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import complete"

      assert Portfolios.count_cash_accounts() == 2
      assert Portfolixir.Buckets.list_buckets() == []

      {:ok, view, _html} = live(german(conn), "/imports")
      upload!(view, [interest("Reserve", "2.00", "2026-04-30")])

      assert has_element?(
               view,
               ~s(#import-bucket-tag input[name="bucket_tag"][value=""][placeholder="z. B. PP Import"])
             )

      assert text(view, "#import-bucket-tag") =~
               "Optional: ein Bucket-Tag für die Konten, die dieser Import anlegt."

      view
      |> element("form#pp-import-apply")
      |> render_submit(%{"bucket_tag" => "Reserven"})

      assert render_async(view, 1_000) =~ "Import abgeschlossen"
      assert [%{name: "Reserven"} = bucket] = Portfolixir.Buckets.list_buckets()
      reserve = named!(CashAccount, "Reserve")
      assert Portfolixir.Buckets.cash_account_bucket_ids(reserve.id) == [bucket.id]
    end
  end

  describe "a fresh instance's portfolio record (#1173; board 01 ⑥)" do
    # User story (#1173):
    # As the operator, or the agent beside me, importing into an instance that
    # holds no portfolio record yet,
    # I want the preview to say which portfolio record the import creates,
    # so that nobody has to guess where the import books.
    #
    # Acceptance criteria:
    # - With no portfolio record, a second muted line under the format line
    #   reads "No portfolio record yet: the import creates “Default” (EUR) and
    #   books into it." / "Noch kein Portfoliodatensatz: Der Import legt
    #   „Default“ (EUR) an und bucht darin."; the name and the currency are
    #   the ones the default portfolio is created with.
    # - Confirming creates that record and books into it.
    # - Once a portfolio record exists the line is gone: with one there is
    #   nothing to say (UX-DR2).
    test "the preview names the record the import creates, and only on a fresh instance",
         %{conn: conn} do
      {:ok, view, _html} = live(german(conn), "/imports")
      upload!(view, history())

      assert text(view, "[data-role='import-portfolio']") ==
               "Noch kein Portfoliodatensatz: Der Import legt „Default“ (EUR) an und bucht darin."

      {:ok, view, _html} = live(conn, "/imports")
      upload!(view, history())

      assert has_element?(
               view,
               ".workspace-section > h2 + p.muted + p.muted[data-role='import-portfolio']"
             )

      assert text(view, "[data-role='import-portfolio']") ==
               "No portfolio record yet: the import creates “Default” (EUR) and books into it."

      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import complete"

      assert [%{id: id, name: "Default", base_currency_code: "EUR"}] =
               Portfolios.list_portfolios()

      assert Ledger.list_transactions() |> Enum.map(& &1.portfolio_id) |> Enum.uniq() == [id]

      {:ok, view, _html} = live(conn, "/imports")
      upload!(view, history() ++ [interest("Tagesgeld", "1.40", "2026-03-31")])
      refute has_element?(view, "[data-role='import-portfolio']")
    end
  end

  describe "the counts by kind add up to the entries (board 01, found while drawing 2)" do
    # User story:
    # As the operator reading a preview whose dividend splits off a tax
    # refund,
    # I want the counts by kind to add up to the "Entries" card,
    # so that two figures of one preview never disagree.
    #
    # Acceptance criteria:
    # - The refund split off a row counts under its own kind: "Einträge 3"
    #   over "Einlage 1", "Dividende 1" and "Steuererstattung 1".
    test "a refund split off a row counts under its own kind", %{conn: conn} do
      {:ok, view, _html} = live(german(conn), "/imports")

      drop!(
        view,
        "refund.csv",
        """
        Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
        2026-01-02 00:00:00;Einlage;;;;1.000,00;;;1.000,00;Test-Cash;;;
        2026-03-16 00:00:00;Dividende;Synthetic AG;10;;20,00;;-1,00;;Test-Cash;;;
        """,
        "text/csv"
      )

      assert text(view, ".import-stats .import-stat-card:first-child .label") == "Einträge"
      assert text(view, ".import-stats .import-stat-card:first-child .value") == "3"

      chips =
        view
        |> element(".kind-chips")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find(".kind-chip")
        |> Enum.map(fn chip ->
          {Floki.find(chip, ".name") |> Floki.text(),
           Floki.find(chip, ".count") |> Floki.text() |> String.to_integer()}
        end)
        |> Map.new()

      assert chips == %{"Einlage" => 1, "Dividende" => 1, "Steuererstattung" => 1}
    end
  end

  describe "the done page names a skipped row in the page's words (board 01, found while drawing 1)" do
    @refund_header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

    # User story:
    # As the operator reading what an import skipped,
    # I want each skipped record named in the page's language, a split-off
    # refund by its row and its kind, under a heading that counts in words,
    # so that I can find each one in the file and know why it was left out.
    #
    # Acceptance criteria:
    # - No reason in the applier's English ("skipped: zero or missing
    #   gross_amount for fee", "the row it was split from (row 3) was not
    #   imported") and no internal id ("3.tax_refund.1"): a fee of 0,00 reads
    #   "Zeile 4: Gebühren ohne Betrag — nichts zu buchen", and the refund
    #   split off the internal transfer in row 3 reads "Zeile 3
    #   (Steuererstattung): die Zeile selbst wurde nicht importiert".
    # - The heading is a real plural: "2 nicht importierbare Datensätze
    #   übersprungen:"; one record reads "Skipped one unimportable record:".
    test "a skipped fee and a skipped refund, in German and in English", %{conn: conn} do
      file =
        @refund_header <>
          "2026-01-02 00:00:00;Einlage;;;;1.000,00;;;1.000,00;Test-Cash;;;\n" <>
          "2026-02-02 00:00:00;Umbuchung (Ausgang);;;;50,00;;-1,00;;Test-Cash;Test-Cash;;\n" <>
          "2026-03-02 00:00:00;Gebühren;;;;0,00;;;0,00;Test-Cash;;;\n"

      {:ok, view, _html} = live(german(conn), "/imports")
      drop!(view, "skips.csv", file, "text/csv")
      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import abgeschlossen"

      assert text(view, "[data-role='skipped-entries'] p") ==
               "2 nicht importierbare Datensätze übersprungen:"

      assert texts(view, "[data-role='skipped-entries'] li") |> Enum.sort() == [
               "Zeile 3 (Steuererstattung): die Zeile selbst wurde nicht importiert",
               "Zeile 4: Gebühren ohne Betrag — nichts zu buchen"
             ]

      refute text(view, "[data-role='skipped-entries']") =~ "skipped"
      refute text(view, "[data-role='skipped-entries']") =~ "tax_refund"

      {:ok, view, _html} = live(conn, "/imports")

      drop!(
        view,
        "fee.csv",
        @refund_header <> "2026-03-09 00:00:00;Gebühren;;;;0,00;;;0,00;Test-Cash;;;\n",
        "text/csv"
      )

      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import complete"
      assert text(view, "[data-role='skipped-entries'] p") == "Skipped one unimportable record:"

      assert texts(view, "[data-role='skipped-entries'] li") == [
               "Row 2: Fee without an amount — nothing to book"
             ]
    end

    # User story (the α closing act, A5's leftover):
    # As the operator reading which records no security could be found for,
    # I want each reason in the page's language, naming the securities by
    # name,
    # so that I know what to decide when I import the file again, without
    # the applier's English, its record numbers or its ADR references.
    #
    # Acceptance criteria:
    # - Two purchases of "Foo AG" under two ISINs: the second matches the
    #   security the first created except for its ISIN, and reads "Zeile 3:
    #   ein wahrscheinlicher Treffer, „Foo AG“, weicht bei einem stärkeren
    #   Identifikator ab — möglicherweise ein noch nicht erfasster
    #   ISIN-Wechsel", in English "Row 3: a likely match, “Foo AG”, differs
    #   on a stronger identifier — possibly an ISIN change not recorded yet".
    # - A purchase whose WKN leads to the security an earlier row created and
    #   whose name leads to a stored one reads "Row 3: different identifiers
    #   point at different existing securities: “Foo AG” and “Bar Holding”".
    # - A purchase whose WKN two securities share (a stored one, and one the
    #   operator chose to create on an earlier row) reads "Row 3: 2 existing
    #   securities share this identifier: WKN"; a shared ticker reads
    #   "… ticker and currency", a shared name "… name and currency".
    # - No "#", no "ADR" and no "ambiguous match" on the page.
    test "a record no security resolves for is named in the page's words", %{conn: conn} do
      # Each import's deposit is a booking of its own, so no name of a later
      # file is known to the stored history while another is not (#904).
      {:ok, view, _html} = live(german(conn), "/imports")

      upload!(view, [
        deposit("Test-Cash", "5000.00", "2026-01-02"),
        purchase("Foo AG", %{"isin" => "DE000EXMPL25"}, "2026-01-15"),
        purchase("Foo AG", %{"isin" => "DE000EXMPL33"}, "2026-01-16")
      ])

      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import abgeschlossen"

      assert texts(view, "[data-role='unresolved-entries'] li") == [
               "Zeile 3: ein wahrscheinlicher Treffer, „Foo AG“, weicht bei einem stärkeren Identifikator ab — möglicherweise ein noch nicht erfasster ISIN-Wechsel"
             ]

      {:ok, view, _html} = live(conn, "/imports")

      upload!(view, [
        deposit("Test-Cash", "5000.00", "2026-01-03"),
        purchase("Qux AG", %{"isin" => "DE000EXMPL41"}, "2026-01-15"),
        purchase("Qux AG", %{"isin" => "DE000EXMPL58"}, "2026-01-16")
      ])

      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import complete"

      assert texts(view, "[data-role='unresolved-entries'] li") == [
               "Row 3: a likely match, “Qux AG”, differs on a stronger identifier — possibly an ISIN change not recorded yet"
             ]

      {:ok, _bar} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Bar Holding",
          currency_code: "EUR",
          ticker_symbol: "BARH"
        })

      {:ok, view, _html} = live(conn, "/imports")

      upload!(view, [
        deposit("Test-Cash", "5000.00", "2026-01-04"),
        purchase("Foo Neu AG", %{"wkn" => "SYN001"}, "2026-02-15"),
        purchase("Bar Holding", %{"wkn" => "SYN001", "ticker" => "BARH"}, "2026-02-16")
      ])

      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import complete"

      assert texts(view, "[data-role='unresolved-entries'] li") == [
               "Row 3: different identifiers point at different existing securities: “Foo Neu AG” and “Bar Holding”"
             ]

      # A stored security, a first row the operator chooses to create
      # beside it (its ISIN differs), and a second row whose identifier
      # both then carry: for each tier that can be shared.
      for {tier, stored, first, second, date, label} <- [
            {:wkn, %{name: "Share Class A", wkn: "AMB002", isin: "XS000SYNTH19"},
             {"Share Class Neu", %{"isin" => "DE000EXMPL66", "wkn" => "AMB002"}},
             {"Share Class Other", %{"wkn" => "AMB002"}}, "2026-01-05", "WKN"},
            {:ticker, %{name: "Ticker Fund", ticker_symbol: "TCKA", isin: "XS000SYNTH27"},
             {"Ticker Fund Neu", %{"isin" => "DE000EXMPL74", "ticker" => "TCKA"}},
             {"Ticker Fund Other", %{"ticker" => "TCKA"}}, "2026-01-06", "ticker and currency"},
            {:name, %{name: "Namesake Fund", isin: "XS000SYNTH35"},
             {"Namesake Fund", %{"isin" => "DE000EXMPL82"}}, {"Namesake Fund", %{}}, "2026-01-07",
             "name and currency"}
          ] do
        {:ok, _stored} =
          Catalog.create_security(Actor.owner_ui(), Map.put(stored, :currency_code, "EUR"))

        {first_name, first_ids} = first
        {second_name, second_ids} = second

        rows = [
          deposit("Test-Cash", "5000.00", date),
          purchase(first_name, first_ids, "2026-03-15"),
          purchase(second_name, second_ids, "2026-03-16")
        ]

        {:ok, view, _html} = live(conn, "/imports")
        upload!(view, rows)

        {:ok, preview} =
          Imports.parse_portfolio_performance(body(rows), filename: "synthetic.json")

        %{resolutions: resolutions} = Imports.resolve_securities(preview)
        decision = Enum.find(resolutions, &(&1.status == :needs_decision)).key
        choice = %{"security" => %{decision => %{"choice" => "create"}}}

        view |> element("form#pp-import-apply") |> render_change(choice)
        view |> element("form#pp-import-apply") |> render_submit(choice)
        assert render_async(view, 1_000) =~ "Import complete", "#{tier}"

        assert texts(view, "[data-role='unresolved-entries'] li") == [
                 "Row 3: 2 existing securities share this identifier: #{label}"
               ],
               "#{tier}"

        refute text(view, "[data-role='unresolved-entries']") =~ ~r/#|ADR|ambiguous match/
      end
    end

    # User story:
    # As the operator who drops a file again whose dividend split off a
    # refund,
    # I want the refund among the records already booked named by its row and
    # its kind, with what it books,
    # so that no internal id and no "a row of the file" stands in the list.
    #
    # Acceptance criteria:
    # - The refund split off the dividend in row 3 reads "Zeile 3
    #   (Steuererstattung): Steuererstattung 16.03.2026 · Synthetic AG · 1,00
    #   EUR · Test-Cash" among the identical rows.
    test "a refund already booked is named by its row and its kind", %{conn: conn} do
      file =
        @refund_header <>
          "2026-01-02 00:00:00;Einlage;;;;1.000,00;;;1.000,00;Test-Cash;;;\n" <>
          "2026-03-16 00:00:00;Dividende;Synthetic AG;10;;20,00;;-1,00;;Test-Cash;;;\n"

      {:ok, view, _html} = live(conn, "/imports")
      drop!(view, "refund.csv", file, "text/csv")
      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Created transactions: 3"

      {:ok, view, _html} = live(german(conn), "/imports")
      drop!(view, "refund.csv", file, "text/csv")
      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Import abgeschlossen"

      rows = texts(view, "[data-role='duplicate-group'] li")

      assert "Zeile 3 (Steuererstattung): Steuererstattung 16.03.2026 · Synthetic AG · 1,00 EUR · Test-Cash" in rows

      refute Enum.any?(rows, &(&1 =~ "tax_refund" or &1 =~ "Zeile der Datei"))
    end
  end

  # --- the exports ---------------------------------------------------------------

  # The history the instance imported (board 01): Test-Cash, Tagesgeld and
  # Depot Muster.
  defp history do
    [
      %{
        "type" => "DEPOSIT",
        "account" => "Test-Cash",
        "date" => "2026-01-02",
        "currency" => "EUR",
        "amount" => num("2000.00")
      },
      %{
        "type" => "CASH_TRANSFER",
        "account" => "Test-Cash",
        "otherAccount" => "Tagesgeld",
        "date" => "2026-01-05",
        "currency" => "EUR",
        "amount" => num("500.00")
      },
      %{
        "type" => "PURCHASE",
        "account" => "Test-Cash",
        "portfolio" => "Depot Muster",
        "date" => "2026-01-15",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num("1000.00"),
        "shares" => num("10"),
        "security" => @fund
      },
      interest("Tagesgeld", "1.25", "2026-01-31"),
      interest("Tagesgeld", "1.30", "2026-02-28")
    ]
  end

  defp interest(account, amount, date) do
    %{
      "type" => "INTEREST",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  # Shares delivered into a depot: a booking that names no cash account.
  defp deposit(account, amount, date) do
    %{
      "type" => "DEPOSIT",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  defp purchase(name, identifiers, date) do
    %{
      "type" => "PURCHASE",
      "account" => "Test-Cash",
      "portfolio" => "Depot Muster",
      "date" => date,
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => num("100.00"),
      "shares" => num("10"),
      "security" => Map.merge(%{"name" => name, "currency" => "EUR"}, identifiers)
    }
  end

  defp delivery(depot) do
    %{
      "type" => "INBOUND_DELIVERY",
      "portfolio" => depot,
      "date" => "2026-03-02",
      "currency" => "EUR",
      "amount" => num("200.00"),
      "shares" => num("2"),
      "security" => @fund
    }
  end

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  defp body(rows), do: Jason.encode!(%{"version" => 1, "transactions" => rows})

  defp applied!(portfolio, rows) do
    {:ok, preview} = Imports.parse_portfolio_performance(body(rows), filename: "synthetic.json")
    {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    :ok
  end

  # The preview's counts are refined in the background once the file is
  # parsed; the page is read after that.
  defp upload!(view, rows), do: drop!(view, "synthetic.json", body(rows), "application/json")

  defp drop!(view, name, content, type) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  # --- reading the page --------------------------------------------------------------

  defp key(kind, name), do: Mapping.row_key(kind, name)

  defp row(kind, name), do: "#mapping-#{kind}-#{key(kind, name)}"

  defp keyed(%{} = params) do
    Enum.reduce(["cash", "depot"], params, fn kind, acc ->
      case Map.get(acc, kind) do
        %{} = rows -> Map.put(acc, kind, Map.new(rows, fn {n, v} -> {key(kind, n), v} end))
        _other -> acc
      end
    end)
  end

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp texts(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.map(&(&1 |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()))
  end

  defp count(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> length()
  end

  defp german(conn), do: put_req_header(conn, "accept-language", "de-DE,de;q=0.9")

  # --- the world -------------------------------------------------------------

  defp portfolio!(name \\ "PP Import Target") do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end

  defp named!(schema, name), do: Repo.one!(from(a in schema, where: a.name == ^name))

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: Portfolios.count_securities_accounts(),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end
end
