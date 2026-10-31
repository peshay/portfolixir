defmodule PortfolixirWeb.CashflowBackfillTest do
  # Issue #737 (Sprint 9 D-1): the exclusion notice on the Cash-flow facets
  # regains a live control — the one-shot historical backfill (UX-DR25's
  # no-dead-control clause, which is why the Sprint 8 control was removed).
  # async: false — the fake's history response is shared through the
  # application env because the backfill runs in the view's own task.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Fx.RateSync.Fake
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.WorldFixtures

  setup do
    on_exit(fn -> Fake.clear_shared_history_response() end)
    :ok
  end

  defp d1_fixture do
    world = WorldFixtures.base_world(name: "Realized", currency: "EUR")
    gbp = WorldFixtures.create_security!(name: "Pound Equity", ticker: "PGB", currency: "GBP")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.buy!(gbp_world, gbp,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp_world, gbp,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    world
  end

  # User story (issue #737):
  # As a local portfolio maintainer reading "1 sale could not be converted",
  # I want the notice to offer the backfill of the historical ECB series right
  # there,
  # so that the stated limit has a remedy on the surface instead of a dead end
  # — and the sale leaves the exclusion as soon as its date has a rate.
  #
  # Acceptance criteria:
  # - The realized exclusion note carries the backfill control with the limit
  #   that remains stated (a day the ECB did not publish stays excluded).
  # - Clicking it runs the backfill in the background; on success the facet
  #   re-reads: the note is gone, excluded.count is 0 and the converted total
  #   is the exact Decimal.
  test "the realized exclusion note backfills the series and the sale converts", %{conn: conn} do
    d1_fixture()

    Fake.put_shared_history_response(
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "GBP",
           date: ~D[2026-02-20],
           rate: "0.85",
           source: "ecb"
         }
       ]}
    )

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    note = view |> element(~s([data-role="realized-excluded"])) |> render()
    assert note =~ "Pound Equity"
    assert note =~ "Backfill historical rates"
    assert note =~ "did not publish stays excluded"
    refute note =~ "Rate sync fetches current rates only"

    # UX-DR25, found by the design critic in the Sprint 13 closing act: the
    # note has to sit in the same section as the figures it qualifies and
    # BEFORE them — it spent one round under the matrix, inside a collapsed
    # disclosure, below every number it is about, with its remedy collapsed
    # with it.
    section = view |> element("#realized-trades") |> render()
    assert [{note_at, _}] = Regex.run(~r/realized-excluded/, section, return: :index)
    assert [{figures_at, _}] = Regex.run(~r/realized-figures/, section, return: :index)
    assert note_at < figures_at
    assert section =~ "fx-backfill-button"
    refute view |> element("#realized-annual") |> render() =~ "realized-excluded"

    clicking = view |> element("#fx-backfill-button") |> render_click()
    assert clicking =~ "Backfilling…"

    render_async(view)
    html = render_async(view)

    # The sale converted: the note is gone, the February figure is on screen.
    refute has_element?(view, ~s([data-role="realized-excluded"]))
    assert RealizedGains.report().excluded.count == 0

    # The engine's own arithmetic: EUR-hub triangulation, amount × (1 / rate).
    expected = Decimal.mult(Decimal.new("40"), Decimal.div(Decimal.new(1), Decimal.new("0.85")))
    [%{months: months}] = RealizedGains.report().annual
    assert Decimal.equal?(months[2], expected)
    assert html =~ "47.06"
  end

  test "a failed backfill is named in the note, nothing else changes", %{conn: conn} do
    d1_fixture()
    Fake.put_shared_history_response({:error, :boom})

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    log =
      capture_log(fn ->
        view |> element("#fx-backfill-button") |> render_click()
        render_async(view)
      end)

    assert log =~ "fx history fetch failed via #{inspect(Fake)}: :boom"

    result = view |> element(~s([data-role="fx-backfill-result"])) |> render()
    assert result =~ "Backfill failed"
    assert has_element?(view, ~s([data-role="realized-excluded"]))
    assert RealizedGains.report().excluded.count == 1
  end

  # Review round: a backfill that stores rates but not the missing date keeps
  # the note and reports what it stored; the flows and costs facets carry the
  # same control in their exclusion notes.
  test "a backfill that misses the date keeps the note and reports the count", %{conn: conn} do
    d1_fixture()

    Fake.put_shared_history_response(
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "GBP",
           date: ~D[2026-02-19],
           rate: "0.90",
           source: "ecb"
         }
       ]}
    )

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    view |> element("#fx-backfill-button") |> render_click()
    render_async(view)

    note = view |> element(~s([data-role="realized-excluded"])) |> render()
    assert note =~ "Pound Equity"
    assert note =~ "Backfill stored 1 rate."
    assert RealizedGains.report().excluded.count == 1
  end

  test "the flows and costs exclusion notes carry the backfill control", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Flows", currency: "EUR")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    # A GBP deposit and a GBP fee on a day with no stored rate: excluded on
    # both facets.
    WorldFixtures.deposit!(gbp_world, "100", ~D[2026-02-20], currency: "GBP")

    {:ok, _} =
      Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: gbp_world.cash.id,
        type: "fee",
        date: ~D[2026-02-20],
        gross_amount: "5",
        currency_code: "GBP"
      })

    {:ok, flows, _} = live(conn, "/cashflow?tab=flows")
    assert flows |> element(~s([data-role="flows-excluded"])) |> render() =~ "fx-backfill-button"

    {:ok, costs, _} = live(conn, "/cashflow?tab=costs")
    assert costs |> element(~s([data-role="costs-excluded"])) |> render() =~ "fx-backfill-button"
  end

  # User story (#1150, Sprint 21 γ4; board ux-design-2026-10-09/04-wealth-income
  # ⑤ and its found while drawing 7 and 8; the issue's comment of
  # 2026-10-31):
  # As the operator reading the Cash-flow page in German,
  # I want the backfill control and the Flows and Costs notes and ⓘ to say
  # "Wechselkurs", never "Kurs",
  # so that the control beside a note about exchange rates does not read as
  # a fetch of security quotes.
  #
  # Acceptance criteria:
  # - The control's sentence opens "Die tägliche Synchronisation der
  #   Wechselkurse kann einen vergangenen Tag nicht nachtragen." and the
  #   button reads "Historische Wechselkurse nachladen"; a result reads
  #   "Nachladen hat 1 Wechselkurs gespeichert."
  # - The Flows and Costs notes say "kein gespeicherter Wechselkurs"; their
  #   ⓘ say "zum Wechselkurs", "kein Wechselkurs gespeichert" and "zum
  #   Wechselkurs eines Nachbartags".
  # - None of them says "Kurssynchronisation", "Historische Kurse" or "kein
  #   gespeicherter Kurs".
  test "the German backfill control and the Flows and Costs notes say Wechselkurs", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Flows", currency: "EUR")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.deposit!(gbp_world, "100", ~D[2026-02-20], currency: "GBP")

    {:ok, _} =
      Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: gbp_world.cash.id,
        type: "fee",
        date: ~D[2026-02-20],
        gross_amount: "5",
        currency_code: "GBP"
      })

    for {tab, role, note_word} <- [
          {"flows", "flows-excluded", "kein gespeicherter Wechselkurs zu seinem Buchungsdatum"},
          {"costs", "costs-excluded", "kein gespeicherter Wechselkurs zu seinem Buchungsdatum"}
        ] do
      {:ok, view, _} = live(conn, "/cashflow?tab=#{tab}&locale=de")
      note = view |> element(~s([data-role="#{role}"])) |> render()
      info = view |> element(~s([data-role="facet-composition"])) |> render()

      assert note =~ note_word, tab

      assert note =~
               "Die tägliche Synchronisation der Wechselkurse kann einen vergangenen Tag nicht nachtragen.",
             tab

      assert view |> element("#fx-backfill-button") |> render() =~
               "Historische Wechselkurse nachladen"

      assert info =~ "zum Wechselkurs", tab
      assert info =~ "kein Wechselkurs gespeichert", tab
      assert info =~ "zum Wechselkurs eines Nachbartags", tab

      for old <- [
            "Kurssynchronisation",
            "Historische Kurse",
            "kein gespeicherter Kurs",
            "zum Kurs",
            "kein Kurs"
          ] do
        refute note =~ old, "#{tab}: #{old}"
        refute info =~ old, "#{tab}: #{old}"
      end
    end

    Fake.put_shared_history_response(
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "GBP",
           date: ~D[2026-02-19],
           rate: "0.90",
           source: "ecb"
         }
       ]}
    )

    {:ok, view, _html} = live(conn, "/cashflow?tab=costs&locale=de")
    view |> element("#fx-backfill-button") |> render_click()
    render_async(view)

    assert view |> element(~s([data-role="fx-backfill-result"])) |> render() =~
             "Nachladen hat 1 Wechselkurs gespeichert."
  end

  # User story (#1150's rule, the review of the γ4 range):
  # As the operator reading German,
  # I want every sentence that means an exchange rate to say "Wechselkurs",
  # beyond the backfill control and the Flows and Costs facets,
  # so that "Kurs" keeps meaning a security's price everywhere.
  #
  # Acceptance criteria:
  # - The Income facet's ⓘ converts "zum letzten gespeicherten Wechselkurs"
  #   and excludes a payment "ohne solchen Wechselkurs".
  # - The hint that no security-currency cost is derivable (a security's
  #   Holdings tab and the sell preview) ends "kein gespeicherter
  #   Wechselkurs am Buchungstag".
  test "the Income facet's ⓘ and the cost-basis hint say Wechselkurs in German", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Income", currency: "EUR")

    {:ok, _} =
      Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "interest",
        date: ~D[2026-02-20],
        gross_amount: "5",
        currency_code: "EUR"
      })

    {:ok, view, _} = live(conn, "/cashflow?locale=de")
    info = view |> element(~s([data-role="facet-composition"])) |> render()

    assert info =~
             "zum letzten gespeicherten Wechselkurs an oder vor dem jeweiligen Buchungsdatum"

    assert info =~ "eine Zahlung ohne solchen Wechselkurs ist ausgeschlossen"
    refute info =~ "Kurs an oder vor"

    hint =
      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        Gettext.gettext(
          PortfolixirWeb.Gettext,
          "No security-currency cost is derivable from the recorded booking (no settlement legs, no stored rate at the booking date)."
        )
      end)

    assert hint ==
             "Aus der erfassten Buchung ist kein Einstand in Wertpapierwährung ableitbar (keine Abrechnungsbeine, kein gespeicherter Wechselkurs am Buchungstag)."
  end
end
