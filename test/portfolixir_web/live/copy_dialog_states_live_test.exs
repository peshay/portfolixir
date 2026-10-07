defmodule PortfolixirWeb.CopyDialogStatesLiveTest do
  # Sprint 19 PR γ U6, board 08 (`ux-design-2026-10-04/08-copy-dialogs`),
  # pick J8 = A: the words a newcomer misread (#1090) and "journalisiert" in
  # the buy/sell drawer (#1074), the split wizard's preview under a conflict
  # (#1066), a merge target deleted while the security dialog was open
  # (#1072), a retired rule subject in the Risk findings (#944), the plan
  # editor's refusals naming their row (#945), and two of the board's "found
  # while drawing" strings (the catalog-wide ones are pinned in
  # `test/invariants/microcopy_voice_test.exs`).
  #
  # Every name, identifier, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      buy!: 3,
      create_security!: 1,
      deposit!: 3,
      put_quote!: 3,
      put_quotes!: 2,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Targets

  defp text(html) when is_binary(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.replace(~r/\s+/, " ")

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp world_with_holding do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")

    security =
      create_security!(name: "Nordwind Industrie AG", ticker: "NWI", asset_class: "equity")

    deposit!(world, "5000", Date.add(Date.utc_today(), -60))
    buy!(world, security, quantity: "40", price: "62.5", date: Date.add(Date.utc_today(), -50))
    Map.put(world, :security, security)
  end

  describe "#1090 — the words a newcomer misread" do
    # User story (#1090, board 08 ①):
    # As a newcomer reading Wealth → Holdings,
    # I want the line under "Positions" to say what one row is and what values
    # it,
    # so that I do not read a sentence about the API as one about the table.
    #
    # Acceptance criteria:
    # - The basis line reads "One row per depot and security, valued at the
    #   latest stored price." and names neither the API nor a projection.
    test "the Positions basis line is about the rows", %{conn: conn} do
      Classifications.ensure_builtins()
      world_with_holding()
      {:ok, view, _html} = live(conn, "/portfolio")
      render_async(view)

      basis = view |> element("[data-role='positions-basis']") |> render() |> text()

      assert String.trim(basis) ==
               "One row per depot and security, valued at the latest stored price."

      refute basis =~ "API"
      refute basis =~ "projection"
    end

    # User story (#1090, board 08 ②):
    # As an operator using the German interface,
    # I want the theme menu named in German,
    # so that the top bar speaks one language.
    #
    # Acceptance criteria:
    # - The theme menu's title, hidden label and group read "Erscheinungsbild";
    #   the English interface keeps "Theme".
    test "the theme menu is named Erscheinungsbild in German", %{conn: conn} do
      {:ok, view, _html} = live(german(conn), "/")

      assert has_element?(view, "#theme-mode[aria-label='Erscheinungsbild']")
      assert has_element?(view, "#theme-mode summary[title='Erscheinungsbild']")
      assert has_element?(view, "#theme-mode .theme-menu-list[aria-label='Erscheinungsbild']")
      refute has_element?(view, "#theme-mode summary[title='Theme']")

      {:ok, english, _html} = live(conn, "/")
      assert has_element?(english, "#theme-mode summary[title='Theme']")
    end

    # User story (#1090, board 08 ③):
    # As a newcomer reading the Overview,
    # I want the wealth card to say "since the start of the year" in words,
    # so that I do not have to know what "YTD" stands for; the card is a link
    # and cannot carry an ⓘ.
    #
    # Acceptance criteria:
    # - The card's change reads "year to date" (de "seit Jahresbeginn"), never
    #   the token "YTD".
    test "the wealth card says year to date in words", %{conn: conn} do
      world_with_holding()

      {:ok, view, _html} = live(conn, "/")
      render_async(view)
      card = view |> element("[data-role='card-ttwror']") |> render() |> text()
      assert card =~ "year to date"
      refute card =~ "YTD"

      {:ok, view, _html} = live(german(conn), "/")
      render_async(view)
      card = view |> element("[data-role='card-ttwror']") |> render() |> text()
      assert card =~ "seit Jahresbeginn"
      refute card =~ "YTD"
    end

    # User story (#1090, board 08 ④):
    # As a newcomer on Accounts & depots,
    # I want "Liquidity role" and "Buckets" defined where they head their
    # columns,
    # so that two domain words do not stand there unexplained.
    #
    # Acceptance criteria:
    # - Each head carries an ⓘ (a <details> disclosure) with its one-sentence
    #   definition.
    # - Under 640 px, where the head is hidden, the role's ⓘ rides in each
    #   cash row beside its role control and the Buckets ⓘ after each chip
    #   group's scope line, with the same words.
    test "the liquidity role and buckets heads carry their definitions", %{conn: conn} do
      base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
      {:ok, view, _html} = live(conn, "/portfolios")

      role =
        "Liquidity role — how a cash account counts: free cash enters the cash quote; reserve and credit line do not."

      buckets =
        "Buckets — tags on depots and cash accounts. A view picks buckets and narrows every figure to their accounts; an account can carry several."

      head = view |> element("#accounts-table thead") |> render()
      doc = Floki.parse_fragment!(head)

      assert [_] =
               Floki.find(
                 doc,
                 "th details.metric-tooltip summary[aria-label='About the liquidity role']"
               )

      assert [_] =
               Floki.find(doc, "th details.metric-tooltip summary[aria-label='About buckets']")

      assert text(head) =~ role
      assert text(head) =~ buckets

      assert view
             |> element("#accounts-table tbody td.cell-role [data-role='liquidity-role-info']")
             |> render()
             |> text() =~
               role

      assert view
             |> element(
               "#accounts-table tbody .bucket-chip-group [data-role='buckets-info']",
               buckets
             )
             |> has_element?()
    end

    # User story (#1090, board 08 ④; the review of Sprint 19 U5):
    # As a keyboard or screen-reader user on a phone,
    # I want each ⓘ on Accounts & depots once, where the rows carry it,
    # so that Tab does not stop on two definitions I cannot see.
    #
    # Acceptance criteria:
    # - Under 640 px the head is visually hidden, but its two ⓘ summaries
    #   stayed in the tab order; there they take `display: none`, which
    #   removes them from the tab order and the accessibility tree. The
    #   rows' copies serve the phone.
    # - Above 640 px nothing hides them.
    test "under 640 px the head's two ⓘ leave the tab order" do
      css = File.read!("priv/static/app.css")

      [_, card] =
        Regex.run(~r/@media \(max-width: 640px\) \{\s*\.accounts-table thead \{(.*?)\n\}/s, css) ||
          flunk("no 640 px block for the accounts table")

      assert card =~ ~r/\.accounts-table thead \.metric-tooltip \{\s*display: none;\s*\}/

      refute css =~ ~r/\n\.accounts-table thead \.metric-tooltip \{/,
             "the head's ⓘ are hidden only under 640 px"
    end

    # User story (#1090, board 08 ⑤):
    # As a newcomer reading the contribution table on a phone,
    # I want a row's flow to say that it moved into or out of the position,
    # so that "outflow" beside a gain does not read as money leaving the
    # portfolio.
    #
    # Acceptance criteria:
    # - A position bought in the period reads "inflow into the position
    #   1,000.00" (de "Zufluss in die Position 1.000,00").
    # - A position sold in the period for more than it cost reads "outflow
    #   from the position 100.00" (de "Abfluss aus der Position 100,00").
    # - Neither phone row says the bare "inflow 1,000.00" / "outflow 100.00".
    test "the contribution phone rows say which way the flow went", %{conn: conn} do
      Classifications.ensure_builtins()
      world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
      alpha = create_security!(name: "Alpha Industrial AG", ticker: "ALPH")
      gamma = create_security!(name: "Gamma Robotics NV", ticker: "GAMR")
      d0 = Date.add(Portfolixir.Clock.today(), -40)

      deposit!(world, "10000", d0)
      buy!(world, alpha, quantity: "10", price: "100", date: d0)
      buy!(world, gamma, quantity: "5", price: "200", date: Date.add(d0, 5))
      sell!(world, gamma, quantity: "5", price: "220", date: Date.add(d0, 20))
      put_quotes!(alpha, [{d0, "100"}, {Portfolixir.Clock.today(), "120"}])
      put_quotes!(gamma, [{Date.add(d0, 5), "200"}, {Date.add(d0, 20), "220"}])

      phone_row = fn view, security ->
        view
        |> element("#contribution-phone-rows li[data-security-id='#{security.id}']")
        |> render()
        |> text()
      end

      {:ok, view, _html} = live(conn, "/portfolio")
      render_async(view)

      assert phone_row.(view, alpha) =~ "inflow into the position 1,000.00"
      assert phone_row.(view, gamma) =~ "outflow from the position 100.00"
      refute phone_row.(view, alpha) =~ "· inflow 1,000.00"
      refute phone_row.(view, gamma) =~ "· outflow 100.00"

      {:ok, view, _html} = live(german(conn), "/portfolio")
      render_async(view)

      assert phone_row.(view, alpha) =~ "Zufluss in die Position 1.000,00"
      assert phone_row.(view, gamma) =~ "Abfluss aus der Position 100,00"
    end

    # User story (#1090, board 08 ⑥):
    # As the operator deleting a booking,
    # I want the dialog's journal sentence to say what the journal keeps,
    # so that "kept" and "gone" do not stand in one sentence.
    #
    # Acceptance criteria:
    # - The sentence reads "The audit journal records the deletion with every
    #   value; the booking cannot be restored." (de "Das Audit-Journal hält die
    #   Löschung mit allen Werten fest; wiederherstellen lässt sich die
    #   Buchung nicht.").
    test "the delete dialog says the journal records the deletion", %{conn: conn} do
      world = world_with_holding()
      [tx | _] = Portfolixir.Ledger.list_transactions_for_portfolio(world.portfolio.id)

      for {conn, sentence} <- [
            {conn,
             "The audit journal records the deletion with every value; the booking cannot be restored."},
            {german(conn),
             "Das Audit-Journal hält die Löschung mit allen Werten fest; wiederherstellen lässt sich die Buchung nicht."}
          ] do
        {:ok, view, _html} = live(conn, "/transactions")
        view |> element("#tx-kebab-#{tx.id}") |> render_click()
        view |> element("#tx-delete-#{tx.id}") |> render_click()

        dialog = view |> element("#booking-delete-dialog") |> render() |> text()
        assert dialog =~ sentence
        refute dialog =~ "keeps the booking"
        refute dialog =~ "behält die Buchung"
      end
    end

    # User story (#1090, board 08 ⑥; the review of U6):
    # As the operator deleting a split booked in several portfolios,
    # I want the journal sentence to say what it records for every row the
    # split carries,
    # so that two rows and three rows read as plainly as one.
    #
    # Acceptance criteria:
    # - Two rows: "The audit journal records the deletion of both rows." (de
    #   "Das Audit-Journal hält die Löschung beider Zeilen fest.").
    # - Three rows: "The audit journal records the deletion of all 3 rows."
    #   (de "Das Audit-Journal hält die Löschung aller 3 Zeilen fest.").
    test "the split delete dialog counts the rows the journal records", %{conn: conn} do
      date = Date.add(Date.utc_today(), -10)
      security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")

      for {name, cash, depot} <- [
            {"Hauptportfolio", "Girokonto", "Depot 1"},
            {"Sparplan-Portfolio", "Tagesgeld", "Depot 2"}
          ] do
        world = base_world(name: name, cash_name: cash, depot_name: depot)
        buy!(world, security, quantity: "10", price: "80", date: Date.add(date, -20))
      end

      book = fn ->
        Splits.book_split(Actor.owner_ui(), %{
          security_id: security.id,
          date: date,
          ratio_numerator: 2,
          ratio_denominator: 1
        })
      end

      {:ok, [row | _]} = book.()

      journal_sentence = fn conn ->
        {:ok, view, _html} = live(conn, "/transactions")
        view |> element("#tx-kebab-#{row.id}") |> render_click()
        view |> element("#tx-delete-#{row.id}") |> render_click()
        view |> element("#booking-delete-dialog") |> render() |> text()
      end

      assert journal_sentence.(conn) =~ "The audit journal records the deletion of both rows."

      assert journal_sentence.(german(conn)) =~
               "Das Audit-Journal hält die Löschung beider Zeilen fest."

      third = base_world(name: "Depot-Portfolio", cash_name: "Kasse", depot_name: "Depot 3")
      buy!(third, security, quantity: "5", price: "80", date: Date.add(date, -20))
      {:ok, [_third_row]} = book.()

      assert journal_sentence.(conn) =~ "The audit journal records the deletion of all 3 rows."

      assert journal_sentence.(german(conn)) =~
               "Das Audit-Journal hält die Löschung aller 3 Zeilen fest."
    end

    # User story (#1074, board 08 ⑦):
    # As the operator correcting a buy in the drawer,
    # I want the sub line in plain words,
    # so that it says what the notes-only drawer says, never "journaled".
    #
    # Acceptance criteria:
    # - The sub line reads "Corrects the booking in place; the derived
    #   holdings follow, and the journal records the change." (de "…, und das
    #   Journal hält die Änderung fest.").
    test "the buy/sell drawer says the journal records the change", %{conn: conn} do
      world = world_with_holding()

      [tx] =
        world.portfolio.id
        |> Portfolixir.Ledger.list_transactions_for_portfolio()
        |> Enum.filter(&(&1.type == "buy"))

      for {conn, sentence, word} <- [
            {conn,
             "Corrects the booking in place; the derived holdings follow, and the journal records the change.",
             "journaled"},
            {german(conn),
             "Korrigiert die Buchung an Ort und Stelle; die abgeleiteten Bestände folgen, und das Journal hält die Änderung fest.",
             "journalisiert"}
          ] do
        {:ok, view, _html} = live(conn, "/transactions")
        view |> element("#tx-kebab-#{tx.id}") |> render_click()
        view |> element("#tx-edit-#{tx.id}") |> render_click()

        sub = view |> element("#booking-drawer .detail-pane-sub") |> render() |> text()
        assert String.trim(sub) == sentence
        refute sub =~ word
      end
    end
  end

  describe "#1090 — the wealth card while it recomputes" do
    setup do
      Memo.reset()
      # `lifetimes: []` keeps the registry defaults, as the stale-serve test
      # does, independent of what config.exs activates.
      DerivedConfig.enable!(lifetimes: [])
      :ok
    end

    # User story (#1090, board 08 ③; UX-DR20; the review of U6):
    # As a newcomer opening the Overview while its figure recomputes,
    # I want the last known figure to say its period in words too,
    # so that the pending card does not bring back the "YTD" the settled
    # card dropped.
    #
    # Acceptance criteria:
    # - The pending card's label reads "year to date" (de "seit
    #   Jahresbeginn"), never "YTD".
    # - Its sentence reads "Last known: …% year to date — one booking through
    #   …, as of …. Recomputing." (de "Letzter Stand: …% seit Jahresbeginn —
    #   eine Buchung bis …, per …. Wird neu berechnet.").
    test "the pending wealth card says year to date in words", %{conn: conn} do
      {card, label, sentence} = pending_wealth_card(conn)

      refute card =~ "YTD"
      assert label == "year to date"

      assert sentence =~
               ~r/^Last known: [+-]?[\d.,]+% year to date — one booking through .+, as of .+\. Recomputing\.$/u
    end

    test "the German pending wealth card says seit Jahresbeginn", %{conn: conn} do
      {card, label, sentence} = pending_wealth_card(german(conn))

      refute card =~ "YTD"
      assert label == "seit Jahresbeginn"

      assert sentence =~
               ~r/^Letzter Stand: [+-]?[\d.,]+% seit Jahresbeginn — eine Buchung bis .+, per .+\. Wird neu berechnet\.$/u
    end
  end

  # Books one booking this year, computes the figure, then supersedes it with
  # a second booking: the previous figure is what the pending card serves
  # (ADR-0032 §6). The card is read from the first connected render, before
  # the recompute lands and swaps it for the settled card.
  defp pending_wealth_card(conn) do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    security = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    today = Date.utc_today()

    buy!(world, security,
      quantity: "10",
      price: "100",
      date: Enum.max([Date.add(today, -30), Date.new!(today.year, 1, 1)], Date)
    )

    Performance.view_analysis(nil, base_currency: "EUR")
    buy!(world, security, quantity: "10", price: "110", date: ~D[2024-04-02])

    {:ok, _view, html} = live(conn, "/")
    doc = Floki.parse_document!(html)
    find_text = fn selector -> doc |> Floki.find(selector) |> Floki.text() |> String.trim() end

    {find_text.("[data-role='overview-stale']"),
     find_text.("[data-role='overview-stale'] > span"),
     find_text.("[data-role='stale-ttwror']") |> String.replace(~r/\s+/u, " ")}
  end

  describe "#1066 — the split wizard's preview under a conflict (J8 A)" do
    setup do
      world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")

      security =
        create_security!(name: "Kestrel Robotik SE", ticker: "KRS", asset_class: "equity")

      buy!(world, security, quantity: "30", price: "80", date: Date.add(Date.utc_today(), -40))
      date = Date.add(Date.utc_today(), -10)

      {:ok, [_row]} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: security.id,
          date: date,
          ratio_numerator: 1,
          ratio_denominator: 2
        })

      %{security: security, date: date}
    end

    defp fill_wizard(conn, security, numerator, denominator, date) do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}")
      view |> element("#detail-record-split") |> render_click()

      view
      |> form("#split-wizard-form", %{
        "split" => %{
          "ratio_numerator" => numerator,
          "ratio_denominator" => denominator,
          "date" => Date.to_iso8601(date)
        }
      })
      |> render_change()

      view
    end

    # User story (#1066, board 08 J8, variant A):
    # As the operator whose "Record split" warns that another ratio is booked
    # on the day,
    # I want the preview to show no quantity the refusal will never let
    # happen, and the warning to say why,
    # so that I do not read two figures from two worlds as the split's
    # effect.
    #
    # Acceptance criteria:
    # - While the conflicting-ratio warning shows, "Quantity after (at date)"
    #   and "Resulting position (today)" read the not-computable "—" in the
    #   muted voice (`.split-na`); "Quantity before" keeps its figure.
    # - The warning ends "…, and the preview shows no quantity after it." (de
    #   "…, und die Vorschau zeigt keine Stückzahl danach.").
    # - Without a conflict the preview prints its figures as before.
    test "a conflicting ratio previews no quantity after it", %{conn: conn} = ctx do
      view = fill_wizard(conn, ctx.security, "4", "1", ctx.date)

      warning =
        view
        |> element("#split-wizard-warnings [data-warning='conflicting_split_ratio']")
        |> render()
        |> text()

      assert warning =~
               "A split with a different ratio is already booked for this security on this date (1:2). Booking is refused while it stands, and the preview shows no quantity after it."

      assert view
             |> element("#split-wizard-preview td[data-role='qty-before']")
             |> render()
             |> text() =~
               "30"

      for role <- ~w(qty-after qty-current) do
        assert view
               |> element("#split-wizard-preview td.split-na[data-role='#{role}'] [aria-hidden]")
               |> render()
               |> text()
               |> String.trim() == "—"
      end

      german = fill_wizard(german(conn), ctx.security, "4", "1", ctx.date)

      assert german
             |> element("#split-wizard-warnings [data-warning='conflicting_split_ratio']")
             |> render()
             |> text() =~
               "Die Buchung wird abgelehnt, solange er steht, und die Vorschau zeigt keine Stückzahl danach."

      # The same ratio on another day conflicts with nothing: figures as before.
      other = fill_wizard(conn, ctx.security, "4", "1", Date.add(ctx.date, -5))

      refute has_element?(
               other,
               "#split-wizard-warnings [data-warning='conflicting_split_ratio']"
             )

      refute has_element?(other, "#split-wizard-preview td.split-na")

      assert other
             |> element("#split-wizard-preview td[data-role='qty-after']")
             |> render()
             |> text() =~ "120"
    end

    # User story (#1066, board 08 J8, variant A; UX-DR7; the review of U6):
    # As the operator reading the split wizard with a screen reader,
    # I want each not-computable "after" cell to say why it holds no figure,
    # so that the dash is not read as a bare symbol, or skipped, without a
    # reason.
    #
    # Acceptance criteria:
    # - The dash is hidden from assistive technology (`aria-hidden`).
    # - Beside it a visually hidden sentence reads "no quantity after: a
    #   different ratio is booked on this day" (de "keine Stückzahl danach:
    #   an diesem Tag ist ein anderes Verhältnis gebucht"), in both cells.
    test "the conflict dash gives its reason to a screen reader", %{conn: conn} = ctx do
      for {conn, sentence} <- [
            {conn, "no quantity after: a different ratio is booked on this day"},
            {german(conn),
             "keine Stückzahl danach: an diesem Tag ist ein anderes Verhältnis gebucht"}
          ] do
        view = fill_wizard(conn, ctx.security, "4", "1", ctx.date)

        for role <- ~w(qty-after qty-current) do
          cell = "#split-wizard-preview td.split-na[data-role='#{role}']"

          assert view
                 |> element("#{cell} [aria-hidden='true']")
                 |> render()
                 |> text()
                 |> String.trim() == "—"

          assert view
                 |> element("#{cell} .visually-hidden")
                 |> render()
                 |> text()
                 |> String.trim() == sentence
        end
      end
    end

    # User story (#1066, board 08 J8, variant A; the review of U6):
    # As the operator recording a split that is already booked with the same
    # ratio on the same day,
    # I want the preview to keep its figures,
    # so that only a conflicting ratio, whose figures the refusal never lets
    # happen, turns them into the dash.
    #
    # Acceptance criteria:
    # - The same ratio on the same day shows the "already booked" warning,
    #   not the conflicting-ratio one.
    # - No cell is the not-computable dash: "Quantity before", "Quantity
    #   after (at date)" and "Resulting position (today)" print their figures.
    test "the same ratio booked on the same day keeps the figures", %{conn: conn} = ctx do
      view = fill_wizard(conn, ctx.security, "1", "2", ctx.date)

      assert has_element?(view, "#split-wizard-warnings [data-warning='already_booked']")

      refute has_element?(
               view,
               "#split-wizard-warnings [data-warning='conflicting_split_ratio']"
             )

      refute has_element?(view, "#split-wizard-preview td.split-na")

      figures =
        for role <- ~w(qty-before qty-after qty-current) do
          view
          |> element("#split-wizard-preview td[data-role='#{role}']")
          |> render()
          |> text()
          |> String.trim()
        end

      assert figures == ["30", "15", "15"]
    end
  end

  describe "#1072 — a merge target deleted while the dialog was open" do
    defp existing_arbolia! do
      {:ok, existing} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Arbolia Inc.",
          ticker_symbol: "ARBL",
          isin: "USEXMPL10014",
          currency_code: "USD",
          asset_class: "equity",
          provider: "portfolio_performance",
          online_id: "usexmpl10014",
          feed: "PORTFOLIO_PERFORMANCE"
        })

      existing
    end

    defp open_conflict(view) do
      view |> element("#open-new-dialog") |> render_click()
      view |> element("button[phx-value-mode='security']") |> render_click()

      view
      |> element("#security-form-dialog form")
      |> render_change(%{"dialog_query" => "arbolia"})

      view |> element("#security-form-dialog .search-result") |> render_click()

      view
      |> element("#security-form-dialog .market-list button[phx-value-idx='0']")
      |> render_click()

      assert has_element?(view, "#security-form-dialog", "This security already exists")
      view
    end

    # User story (#1072, board 08.3; H8.6):
    # As the operator merging a found listing's online fields into the
    # security it matched,
    # I want a match deleted meanwhile (by the agent, or in another tab) to
    # close the dialog, reload the list and say why,
    # so that the page does not restart silently and lose my search.
    #
    # Acceptance criteria:
    # - "Merge online fields" on a match deleted meanwhile closes the dialog;
    #   the page's result slot reads "“Arbolia Inc.” was deleted meanwhile;
    #   the list is reloaded."; the LiveView process stays alive.
    # - "Update existing" (the same conflict's save) answers the same way,
    #   not with an in-dialog alert.
    test "both conflict buttons answer a vanished match with the H8.6 note", %{conn: conn} do
      for click <- [:merge, :save] do
        existing = existing_arbolia!()
        {:ok, view, _html} = live(conn, "/securities")
        open_conflict(view)

        {:ok, _} = Catalog.delete_security(Actor.owner_ui(), existing)

        case click do
          :merge ->
            view
            |> element("#security-form-dialog button", "Merge online fields")
            |> render_click()

          :save ->
            view
            |> element("#security-form-dialog form#security-dialog-form")
            |> render_submit(%{
              "security" => %{"name" => "Arbolia Inc.", "currency_code" => "USD"}
            })
        end

        assert Process.alive?(view.pid)
        refute has_element?(view, "#security-form-dialog")

        assert view |> element("#securities-action-result") |> render() |> text() =~
                 "“Arbolia Inc.” was deleted meanwhile; the list is reloaded."

        # The note takes the focus, as H8.6's does: its control went with
        # the dialog.
        assert_push_event(view, "focus-into-view", %{id: "securities-action-result"})
        refute render(view) =~ "it was deleted after the dialog opened"
      end
    end

    # User story (#1072, board 08.3; the name the dialog knows):
    # As the operator whose match was created after the list loaded and
    # deleted before I merged,
    # I want the note to name it all the same,
    # so that the closed dialog is never silent.
    #
    # Acceptance criteria:
    # - The note names the match by the dialog's own record when the stale
    #   list does not carry it.
    test "a match the list never showed is named from the dialog", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")
      existing = existing_arbolia!()
      open_conflict(view)
      {:ok, _} = Catalog.delete_security(Actor.owner_ui(), existing)

      view |> element("#security-form-dialog button", "Merge online fields") |> render_click()

      assert Process.alive?(view.pid)
      refute has_element?(view, "#security-form-dialog")

      assert view |> element("#securities-action-result") |> render() |> text() =~
               "“Arbolia Inc.” was deleted meanwhile; the list is reloaded."
    end

    # User story (#1072, board 08.3; H8.6's merge note):
    # As the operator whose match was merged into another security while the
    # dialog was open,
    # I want the note to name the survivor and link it,
    # so that I can go where the online fields belong now.
    #
    # Acceptance criteria:
    # - "Merge online fields" on a match merged away meanwhile closes the
    #   dialog; the note reads "“Arbolia Inc.” was merged into Arbolia
    #   Holdings Inc. meanwhile; the list is reloaded.", the survivor a link
    #   to its detail with its name in <bdi>.
    test "a match merged away meanwhile names its survivor", %{conn: conn} do
      existing = existing_arbolia!()

      {:ok, survivor} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Arbolia Holdings Inc.",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, view, _html} = live(conn, "/securities")
      open_conflict(view)

      {:ok, preview} = Lifecycle.preview_security_merge(existing.id, survivor.id)

      {:ok, _record, :applied} =
        Lifecycle.merge_security(
          Actor.api_token_rw("synthetic-agent"),
          existing.id,
          survivor.id,
          %{
            plan_digest: preview.plan_digest,
            collapse_key_equal: false,
            identity_choice: "keep_target_isin"
          }
        )

      view |> element("#security-form-dialog button", "Merge online fields") |> render_click()

      assert Process.alive?(view.pid)
      refute has_element?(view, "#security-form-dialog")

      assert view |> element("#securities-action-result") |> render() |> text() =~
               "“Arbolia Inc.” was merged into Arbolia Holdings Inc. meanwhile; the list is reloaded."

      assert has_element?(
               view,
               ~s(#securities-action-result a[href^="/securities/#{survivor.id}"] bdi),
               "Arbolia Holdings Inc."
             )
    end
  end

  describe "#944 — a retired rule subject keeps its name" do
    defp today, do: Portfolixir.Clock.today()

    # User story (#944, board 08.4):
    # As the operator reading my own rules on Wealth → Risk,
    # I want a rule on a security I have since retired to name it,
    # so that "Weight · Security · Cap" never leaves me guessing which one.
    #
    # Acceptance criteria:
    # - The finding's words name the retired security, in <bdi>.
    # - A retired security that shares its name with an active one is told
    #   apart by its ISIN.
    # - The new-rule dialog still does not offer the retired security.
    test "the findings name a retired subject from the stored row", %{conn: conn} do
      world = base_world(name: "Regeln")
      start = Date.add(today(), -5)
      deposit!(world, "10000", start)

      nordwind =
        create_security!(
          name: "Nordwind Industrie AG",
          ticker: "NWI",
          isin: "DE000000000A",
          asset_class: "equity"
        )

      twin =
        create_security!(
          name: "Nordwind Industrie AG",
          ticker: "NWJ",
          isin: "DE000000000B",
          asset_class: "equity"
        )

      buy!(world, nordwind, quantity: "10", price: "124", date: start)
      put_quote!(nordwind, start, "124")

      {:ok, rule} =
        PolicyRules.create_rule(
          Actor.owner_ui(),
          %{
            portfolio_id: world.portfolio.id,
            name: "Einzeltitel-Grenze",
            version: %{
              subject_type: "security",
              security_id: nordwind.id,
              measure: "weight",
              kind: "cap",
              threshold: "8",
              severity: "warn",
              valid_from: start
            }
          },
          today: start
        )

      {:ok, _} = Catalog.update_security(Actor.owner_ui(), nordwind, %{is_retired: true})

      {:ok, view, _html} = live(conn, "/risk")

      words =
        view
        |> element("#policy-findings tr[data-rule-id='#{rule.id}'] .policy-rule__words")
        |> render()

      assert words =~ "<bdi>Nordwind Industrie AG · DE000000000A</bdi>"
      refute text(words) =~ "Weight · Security ·"

      view |> element("button", "New rule") |> render_click()
      refute has_element?(view, "option[value='security:#{nordwind.id}']")
      assert has_element?(view, "option[value='security:#{twin.id}']")
    end

    # User story (#944, board 08.4; the review of U6):
    # As the operator with a rule on a retired security and another on its
    # active twin,
    # I want both rules to tell their subject apart the same way,
    # so that the two findings do not read as one security named twice, once
    # with its ISIN and once without.
    #
    # Acceptance criteria:
    # - The rule on the retired twin names it with its ISIN.
    # - The rule on the active twin names it with its ISIN as well: both
    #   labels come from one set of tags over every subject the words name.
    test "twins named in two rules both carry their identifier", %{conn: conn} do
      world = base_world(name: "Regeln")
      start = Date.add(today(), -5)
      deposit!(world, "10000", start)

      retired =
        create_security!(
          name: "Nordwind Industrie AG",
          ticker: "NWI",
          isin: "DE000000000A",
          asset_class: "equity"
        )

      active =
        create_security!(
          name: "Nordwind Industrie AG",
          ticker: "NWJ",
          isin: "DE000000000B",
          asset_class: "equity"
        )

      for security <- [retired, active] do
        buy!(world, security, quantity: "10", price: "124", date: start)
        put_quote!(security, start, "124")
      end

      retired_rule = security_cap_rule!(world, retired, "Grenze alt", start)
      active_rule = security_cap_rule!(world, active, "Grenze neu", start)
      {:ok, _} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})

      {:ok, view, _html} = live(conn, "/risk")

      words = fn rule ->
        view
        |> element("#policy-findings tr[data-rule-id='#{rule.id}'] .policy-rule__words")
        |> render()
      end

      assert words.(retired_rule) =~ "<bdi>Nordwind Industrie AG · DE000000000A</bdi>"
      assert words.(active_rule) =~ "<bdi>Nordwind Industrie AG · DE000000000B</bdi>"
    end

    defp security_cap_rule!(world, security, name, start) do
      {:ok, rule} =
        PolicyRules.create_rule(
          Actor.owner_ui(),
          %{
            portfolio_id: world.portfolio.id,
            name: name,
            version: %{
              subject_type: "security",
              security_id: security.id,
              measure: "weight",
              kind: "cap",
              threshold: "8",
              severity: "warn",
              valid_from: start
            }
          },
          today: start
        )

      rule
    end
  end

  describe "#945 — the plan refusals name their row" do
    setup do
      world = base_world(name: "Planwelt", cash_name: "Giro", depot_name: "Depot")
      owner = Actor.owner_ui()
      {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategie"})

      {:ok, world_cat} =
        Classifications.create_category(owner, %{classification_id: tree.id, name: "Aktien Welt"})

      {:ok, europe} =
        Classifications.create_category(owner, %{
          classification_id: tree.id,
          name: "Aktien Europa"
        })

      nordwind = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
      wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")

      for security <- [nordwind, wrenfield] do
        {:ok, _} = Classifications.assign_security(owner, security.id, tree.id, europe.id)
        buy!(world, security, quantity: "10", price: "10")
      end

      {:ok, _} =
        Targets.set_targets(owner, world.portfolio.id, tree.id, [
          %{"category_id" => world_cat.id, "target_weight" => "0.45"},
          %{"category_id" => europe.id, "target_weight" => "0.5"}
        ])

      %{
        tree: tree,
        world_cat: world_cat,
        europe: europe,
        nordwind: nordwind,
        wrenfield: wrenfield
      }
    end

    defp submit_plan(view, params) do
      view |> form("#soll-plan-form") |> render_submit(params) |> text()
    end

    # User story (#945, board 08.5):
    # As the operator saving a plan with several categories and open position
    # rows,
    # I want a refused weight to name its row before the rule,
    # so that I do not hunt for the input by eye.
    #
    # Acceptance criteria:
    # - A category weight: "Target of “Aktien Welt”: at most four decimal
    #   places in percent".
    # - A position: "Position target of “Nordwind Industrie AG” under “Aktien
    #   Europa”: at most four decimal places in percent".
    # - The cash target: "Cash target: at most four decimal places in
    #   percent".
    # - The 0–100 % refusal follows the same pattern ("…: must lie between 0
    #   and 100 %").
    # - Stored names sit in <bdi>; nothing is written, not even a valid row
    #   saved in the same batch as the refused one.
    test "a refused weight names its row first", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, "/classifications/#{ctx.tree.id}")
      render_async(view)

      w = "#{ctx.world_cat.id}"
      e = "#{ctx.europe.id}"

      assert submit_plan(view, %{"weights" => %{w => "12.34567"}, "cash_target" => ""}) =~
               "Target of “Aktien Welt”: at most four decimal places in percent"

      assert submit_plan(view, %{
               "weights" => %{w => "45"},
               "positions" => %{
                 e => %{"#{ctx.nordwind.id}" => "12.33333", "#{ctx.wrenfield.id}" => "8"}
               },
               "cash_target" => ""
             }) =~
               "Position target of “Nordwind Industrie AG” under “Aktien Europa”: at most four decimal places in percent"

      # The Wrenfield row was valid, and it went down with the refused one.
      assert Portfolixir.Portfolios.first_portfolio().id
             |> Targets.list_position_targets(classification_id: ctx.tree.id) == []

      assert submit_plan(view, %{"weights" => %{w => "45"}, "cash_target" => "10.00001"}) =~
               "Cash target: at most four decimal places in percent"

      assert submit_plan(view, %{"weights" => %{w => "150"}, "cash_target" => ""}) =~
               "Target of “Aktien Welt”: must lie between 0 and 100 %"

      assert submit_plan(view, %{
               "weights" => %{w => "45"},
               "positions" => %{e => %{"#{ctx.nordwind.id}" => "150"}},
               "cash_target" => ""
             }) =~
               "Position target of “Nordwind Industrie AG” under “Aktien Europa”: must lie between 0 and 100 %"

      assert submit_plan(view, %{"weights" => %{w => "45"}, "cash_target" => "150"}) =~
               "Cash target: must lie between 0 and 100 %"

      html =
        view
        |> form("#soll-plan-form")
        |> render_submit(%{"weights" => %{w => "12.34567"}, "cash_target" => ""})

      assert html =~ "<bdi>Aktien Welt</bdi>"

      [world_target] =
        Portfolixir.Portfolios.first_portfolio().id
        |> Targets.list_targets(classification_id: ctx.tree.id)
        |> Enum.filter(&(&1.category_id == ctx.world_cat.id))

      assert Decimal.equal?(world_target.target_weight, Decimal.new("0.45"))

      {:ok, german, _html} = live(german(conn), "/classifications/#{ctx.tree.id}")
      render_async(german)

      assert submit_plan(german, %{
               "weights" => %{w => "45"},
               "positions" => %{e => %{"#{ctx.nordwind.id}" => "12.33333"}},
               "cash_target" => ""
             }) =~
               "Positionsziel von „Nordwind Industrie AG“ unter „Aktien Europa“: höchstens vier Nachkommastellen in Prozent"
    end

    # User story (#945, board 08.5, found while drawing; the review of U6):
    # As the operator typing a target with two decimal places, or one above
    # 100 % or below 0 %,
    # I want the browser to let me submit it,
    # so that the store, which keeps four places in percent between 0 and
    # 100 %, decides, and its refusal naming the row is what I read instead
    # of the browser's "Value must be less than or equal to 100."
    #
    # Acceptance criteria:
    # - The category, position and cash inputs carry step="any" and neither
    #   `min` nor `max`.
    # - A negative target, which the browser's min="0" used to stop, meets
    #   the row-first range refusal.
    test "the plan inputs leave the step and the range to the store", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, "/classifications/#{ctx.tree.id}")
      render_async(view)

      inputs = [
        "#soll-weight-#{ctx.world_cat.id}",
        "#soll-position-#{ctx.europe.id}-#{ctx.nordwind.id}",
        "#soll-cash-target"
      ]

      for input <- inputs do
        assert has_element?(view, "#{input}[step='any']")
        refute has_element?(view, "#{input}[min]")
        refute has_element?(view, "#{input}[max]")
      end

      refute has_element?(view, "#soll-plan-form input[step='0.1']")

      assert submit_plan(view, %{
               "weights" => %{"#{ctx.world_cat.id}" => "-5"},
               "cash_target" => ""
             }) =~
               "Target of “Aktien Welt”: must lie between 0 and 100 %"
    end
  end

  describe "found while drawing (board 08)" do
    # User story (board 08, found while drawing; #1074's sibling strings):
    # As the operator renaming one of my rules in the German interface,
    # I want the rename note to say that the journal records the change,
    # so that it reads as the drawers do, never "journalisiert".
    #
    # Acceptance criteria:
    # - The rename-only note reads "…; das Journal hält die Änderung fest,
    #   und der bisherige Name bleibt dort lesbar." (en "…; the journal
    #   records the change, and the previous name stays readable there.").
    test "the rule rename note says the journal records the change", %{conn: conn} do
      world = base_world(name: "Regeln")
      start = Date.add(Portfolixir.Clock.today(), -5)
      deposit!(world, "1000", start)

      {:ok, rule} =
        PolicyRules.create_rule(
          Actor.owner_ui(),
          %{
            portfolio_id: world.portfolio.id,
            name: "Barreserve mindestens 1 %",
            version: %{
              subject_type: "cash",
              measure: "weight",
              kind: "floor",
              threshold: "1",
              severity: "warn",
              valid_from: start
            }
          },
          today: start
        )

      for {conn, sentence, word} <- [
            {conn, "the journal records the change, and the previous name stays readable there.",
             "journaled"},
            {german(conn),
             "das Journal hält die Änderung fest, und der bisherige Name bleibt dort lesbar.",
             "journalisiert"}
          ] do
        {:ok, view, _html} = live(conn, "/risk")
        view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()
        view |> form("#policy-rule-form", rule: %{name: "Barreserve"}) |> render_change()

        note = view |> element("[data-role='policy-rule-rename-note']") |> render() |> text()
        assert note =~ sentence
        refute note =~ word
      end
    end

    # User story (board 08, found while drawing):
    # As the operator opening a security's row menu in German,
    # I want "Logo verwalten…" to keep the ellipsis of "Manage logo…",
    # so that the item says, as every other one does, that it opens a dialog.
    #
    # Acceptance criteria:
    # - The row menu's logo item reads "Logo verwalten…".
    test "the German row menu's logo item keeps its ellipsis", %{conn: conn} do
      security = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
      {:ok, view, _html} = live(german(conn), "/securities")
      render_click(view, "open_row_menu", %{"id" => "#{security.id}"})

      assert view
             |> element("button[phx-value-action='manage_logo'][phx-value-id='#{security.id}']")
             |> render()
             |> text()
             |> String.trim() == "Logo verwalten…"
    end
  end
end
