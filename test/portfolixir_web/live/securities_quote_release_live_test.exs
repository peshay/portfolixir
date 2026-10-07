defmodule PortfolixirWeb.SecuritiesQuoteReleaseLiveTest do
  # T-9's human view (Sprint 17 V2; board
  # ux-design-2026-10-01/03-quote-release, pick G3-A): a data note on the
  # security's Quotes tab counts its manual quotes over the whole history, and
  # its remedy "Release…" opens a range dialog whose confirm runs the journaled
  # release (Portfolixir.Catalog.Quotes.release_manual/4). Every name, close
  # and date is synthetic; dates are relative to the host's calendar day.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.QuoteSync.Fake
  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Clock
  alias Portfolixir.Journal.Entry
  alias Portfolixir.Lifecycle
  alias Portfolixir.Repo
  alias Portfolixir.SingleFlight

  # A provider that answers every security with a close on each of the six
  # to four days before today — the days the setup pins by hand among them.
  # A module, not the per-process Fake: the sync runs in a Task the test's
  # process dictionary does not reach.
  defmodule ClosingAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider

    @impl true
    def id, do: :closing

    @impl true
    def fetch(_security, _opts) do
      today = Portfolixir.Clock.today()
      {:ok, Enum.map(-6..-4, &%{date: Date.add(today, &1), close: "101.00"})}
    end
  end

  # A provider whose precondition is the security's currency, answering with
  # the provider contract's skip reason (`QuoteSync.Provider`): every stored
  # security carries a currency, so no stored security makes the shipped
  # adapter answer it.
  defmodule CurrencyBoundAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider

    @impl true
    def id, do: :currency_bound

    @impl true
    def fetch(_security, _opts), do: {:error, :missing_currency}
  end

  setup do
    today = Clock.today()
    day = &Date.add(today, &1)

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Meridian Global Equity ETF",
        currency_code: "EUR",
        asset_class: "etf",
        provider: "portfolio_performance"
      })

    # Provider closes on the last ten days; two of them pinned by hand, and an
    # older stretch of manual closes three years back, outside the chart's
    # one-year range.
    {:ok, _} =
      Quotes.upsert_many(
        security.id,
        Enum.map(-10..-1, &%{date: day.(&1), close: "100.00", source: "portfolio_performance"})
      )

    {:ok, _} =
      Quotes.upsert_authored(Actor.api_token_rw("synthetic"), security.id, [
        %{"date" => Date.to_iso8601(day.(-1100)), "close" => "80.00"},
        %{"date" => Date.to_iso8601(day.(-1099)), "close" => "80.50"},
        %{"date" => Date.to_iso8601(day.(-5)), "close" => "104.00"},
        %{"date" => Date.to_iso8601(day.(-4)), "close" => "104.20"}
      ])

    # A displayed date reads the page's language (Sprint 19 U3, board 05):
    # `de` for the note, the chips and the result; `iso` for the fields.
    %{
      security: security,
      day: day,
      iso: &Date.to_iso8601(day.(&1)),
      de: &PortfolixirWeb.Format.date(day.(&1), "de")
    }
  end

  defp with_adapter(_ctx) do
    config = Application.get_env(:portfolixir, QuoteSync, [])

    Application.put_env(
      :portfolixir,
      QuoteSync,
      Keyword.put(config, :adapter_for, %{"portfolio_performance" => Fake})
    )

    on_exit(fn -> Application.put_env(:portfolixir, QuoteSync, config) end)
    :ok
  end

  defp with_closing_adapter(_ctx) do
    config = Application.get_env(:portfolixir, QuoteSync, [])

    Application.put_env(
      :portfolixir,
      QuoteSync,
      Keyword.put(config, :adapter_for, %{"portfolio_performance" => ClosingAdapter})
    )

    on_exit(fn -> Application.put_env(:portfolixir, QuoteSync, config) end)
    :ok
  end

  # The sync runs in a Task and answers with :sync_done; the busy flag on
  # the toolbar's sync button clears when it has landed.
  defp await_sync(view, tries \\ 100)

  defp await_sync(view, 0), do: refute(has_element?(view, "button#sync-prices[disabled]"))

  defp await_sync(view, tries) do
    if has_element?(view, "button#sync-prices[disabled]") do
      Process.sleep(20)
      await_sync(view, tries - 1)
    else
      :ok
    end
  end

  defp quotes_tab(conn, security),
    do: live(conn, "/securities/#{security.id}?tab=quotes&locale=de")

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp manual_dates(security) do
    SecurityQuote
    |> where([q], q.security_id == ^security.id and q.source == "manual")
    |> order_by([q], asc: q.date)
    |> select([q], q.date)
    |> Repo.all()
  end

  # User story:
  # As the operator reading a security's quotes,
  # I want the Quotes tab to say how many of its stored quotes are manual and
  # from when to when, over the whole history and not only the chart's range,
  # so that I know a pinned close exists before I wonder why the sync left it
  # (pick G3-A ①, ②).
  #
  # Acceptance criteria:
  # - A note above the table: "N manuelle Kurse in der gespeicherten
  #   Historie, vom <first> bis <last>." counting every stored manual quote,
  #   the dates as <time datetime>.
  # - It says a manual quote has precedence until released, and carries
  #   "Freigeben…" as its remedy.
  test "the Quotes tab names the manual quotes of the whole history", ctx do
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)

    note = "#detail-tab-panel-quotes [data-role='manual-quotes-note']"

    assert text(view, note) =~
             "4 manuelle Kurse in der gespeicherten Historie, vom #{ctx.de.(-1100)} bis #{ctx.de.(-4)}."

    assert text(view, note) =~
             "Ein manueller Kurs hat Vorrang: Die Kursaktualisierung lässt ihn stehen, bis er freigegeben wird."

    assert has_element?(view, "#{note} time[datetime='#{ctx.iso.(-1100)}']")
    assert text(view, "#{note} [data-role='release-manual-quotes']") == "Freigeben…"
  end

  # User story:
  # As the operator of a security with only provider quotes, or only manual
  # ones,
  # I want no note where nothing is pinned, and the note to say so where
  # everything is,
  # so that an all-clear is not a finding and a demo dataset is not a puzzle
  # (pick G3-A ①, A7).
  #
  # Acceptance criteria:
  # - No manual quote: no note and no "Freigeben…".
  # - Every stored quote manual: the note adds "alle gespeicherten Kurse sind
  #   manuell".
  test "no note without a manual quote, and says so when every quote is manual", ctx do
    plain = create_security!(name: "Northwind Utilities", ticker: nil)

    {:ok, _} =
      Quotes.upsert_many(plain.id, [
        %{date: ctx.day.(-2), close: "54.20", source: "portfolio_performance"}
      ])

    {:ok, view, _html} = quotes_tab(ctx.conn, plain)
    refute has_element?(view, "[data-role='manual-quotes-note']")
    refute has_element?(view, "[data-role='release-manual-quotes']")

    pinned = create_security!(name: "Halvorsen Shipping Bond 2031", ticker: nil)

    {:ok, _} =
      Quotes.upsert_authored(Actor.owner_ui(), pinned.id, [
        %{"date" => ctx.iso.(-3), "close" => "98.00"},
        %{"date" => ctx.iso.(-2), "close" => "98.40"}
      ])

    {:ok, view, _html} = quotes_tab(ctx.conn, pinned)

    assert text(view, "[data-role='manual-quotes-note']") =~
             "2 manuelle Kurse in der gespeicherten Historie, vom #{ctx.de.(-3)} bis #{ctx.de.(-2)}; alle gespeicherten Kurse sind manuell."
  end

  # User story:
  # As the operator about to release manual quotes,
  # I want a dialog titled with the security, its range prefilled with the
  # first and last manual date, the stretches as chips, what happens in one
  # sentence, and a confirm that names how many,
  # so that I confirm a range I can read (pick G3-A ③–⑥).
  #
  # Acceptance criteria:
  # - "Freigeben…" opens a native dialog "Manuelle Kurse freigeben — <name>".
  # - Von/Bis are ISO text fields prefilled with the first and last manual
  #   date; one chip per stretch ("<from> – <to> · n") plus "Alle · N", the
  #   chip matching the pair pressed.
  # - The consequence sentence: removed, journaled with their closes,
  #   provider quotes stay, the next sync fills the days, until then none.
  # - The confirm is .button-danger "4 manuelle Kurse freigeben"; a chip
  #   fills the pair and the confirm follows it.
  test "the release dialog: range, stretches, consequence and a counted confirm", ctx do
    with_adapter(ctx)
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)

    view |> element("[data-role='release-manual-quotes']") |> render_click()

    dialog = "#quote-release-dialog"

    assert text(view, "#{dialog} .modal-head h2") ==
             "Manuelle Kurse freigeben — Meridian Global Equity ETF"

    assert view |> element("#quote-release-from") |> render() =~ ~s(value="#{ctx.iso.(-1100)}")
    assert view |> element("#quote-release-to") |> render() =~ ~s(value="#{ctx.iso.(-4)}")

    chips =
      view
      |> element("#{dialog} [data-role='release-stretches']")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("button.filter-chip")

    assert Enum.map(chips, &(&1 |> Floki.text() |> String.split() |> Enum.join(" "))) == [
             "Alle · 4",
             "#{ctx.de.(-1100)} – #{ctx.de.(-1099)} · 2",
             "#{ctx.de.(-5)} – #{ctx.de.(-4)} · 2"
           ]

    assert Enum.map(chips, &Floki.attribute(&1, "aria-pressed")) == [
             ["true"],
             ["false"],
             ["false"]
           ]

    assert text(view, "#{dialog} [data-role='release-consequence']") ==
             "Die manuellen Schlusskurse im Zeitraum werden entfernt und mit ihren Werten im Journal festgehalten; Kurse des Anbieters im Zeitraum bleiben, wie sie sind. Die nächste Kursaktualisierung speichert für die freigegebenen Tage den Schlusskurs des Anbieters, bis dahin haben sie keinen Kurs."

    refute has_element?(view, "#{dialog} .data-note--attention")

    assert text(view, "#{dialog} [data-role='quote-release-confirm']") ==
             "4 manuelle Kurse freigeben"

    assert has_element?(view, "#{dialog} button.button-danger[data-role='quote-release-confirm']")

    view
    |> element("#{dialog} [data-role='release-stretches'] button", "#{ctx.de.(-5)} – ")
    |> render_click()

    assert view |> element("#quote-release-from") |> render() =~ ~s(value="#{ctx.iso.(-5)}")

    assert text(view, "#{dialog} [data-role='quote-release-confirm']") ==
             "2 manuelle Kurse freigeben"
  end

  # User story:
  # As the operator of a security whose provider the quote sync cannot ask,
  # I want the dialog to say the released days stay empty,
  # so that I do not release a close nothing will replace by mistake (A3).
  #
  # Acceptance criteria:
  # - An attention note at the head of the dialog: the sync fetches no
  #   quotes for this security, the released days stay without a quote.
  # - The consequence drops its sentence about the next sync.
  test "without a sync adapter the dialog warns that the days stay empty", ctx do
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    assert text(view, "#quote-release-dialog .data-note--attention") =~
             "Für dieses Wertpapier holt die Kursaktualisierung keine Kurse: Die freigegebenen Tage bleiben ohne Kurs."

    refute text(view, "#quote-release-dialog [data-role='release-consequence']") =~
             "nächste Kursaktualisierung"
  end

  # User story:
  # As the operator who typed a range without a manual quote, or a "Bis"
  # before its "Von",
  # I want the confirm to say why it waits, and the wrong field named,
  # so that nothing is written by a range I did not mean (A4, A6).
  #
  # Acceptance criteria:
  # - A valid range with no manual quote: the confirm "Freigeben" disabled,
  #   its reason beside it ("Kein manueller Kurs im Zeitraum.").
  # - "Bis" before "Von": Enter in a field, or the confirm, shows "Das
  #   Enddatum liegt vor dem Startdatum." at the field (aria-invalid), the
  #   dialog stays, nothing is written; a field that is no date says "Kein
  #   Datum — Format JJJJ-MM-TT" in the app's words.
  # - Enter in a field on a range that holds manual quotes writes nothing:
  #   only the confirm releases (closing act, γ D1).
  test "a range without a manual quote waits, and a reversed range is refused at the field",
       ctx do
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    view
    |> form("#quote-release-form", release: %{from: ctx.iso.(-3), to: ctx.iso.(-1)})
    |> render_change()

    confirm = "#quote-release-dialog [data-role='quote-release-confirm']"
    assert text(view, confirm) == "Freigeben"
    assert has_element?(view, "#{confirm}[disabled]")

    assert text(view, "#quote-release-dialog .merge-footer__why") ==
             "Kein manueller Kurs im Zeitraum."

    view
    |> form("#quote-release-form", release: %{from: ctx.iso.(-4), to: ctx.iso.(-1100)})
    |> render_change()

    refute has_element?(view, "#{confirm}[disabled]")
    view |> form("#quote-release-form") |> render_submit()

    assert text(view, "#quote-release-dialog [data-role='quote-release-error']") ==
             "Das Enddatum liegt vor dem Startdatum."

    assert view |> element("#quote-release-to") |> render() =~ ~s(aria-invalid="true")
    assert length(manual_dates(ctx.security)) == 4

    view |> element(confirm) |> render_click()

    assert text(view, "#quote-release-dialog [data-role='quote-release-error']") ==
             "Das Enddatum liegt vor dem Startdatum."

    assert length(manual_dates(ctx.security)) == 4

    view
    |> form("#quote-release-form", release: %{from: "2026-02-30", to: ctx.iso.(-4)})
    |> render_submit()

    assert text(view, "#quote-release-dialog [data-role='quote-release-error']") =~ "Kein Datum"
    assert view |> element("#quote-release-from") |> render() =~ ~s(aria-invalid="true")
    assert length(manual_dates(ctx.security)) == 4

    # Enter on the whole range: re-counted and checked, never released.
    view
    |> form("#quote-release-form", release: %{from: ctx.iso.(-1100), to: ctx.iso.(-4)})
    |> render_submit()

    refute has_element?(view, "#quote-release-dialog [data-role='quote-release-error']")
    assert text(view, confirm) == "4 manuelle Kurse freigeben"
    assert length(manual_dates(ctx.security)) == 4
    assert has_element?(view, "#quote-release-dialog")
  end

  # User story:
  # As the operator who confirmed a release,
  # I want the closes released through the journaled write, the dialog
  # closed, and the result said in the tab with the sync as the next step,
  # so that I see what happened where I started (A5).
  #
  # Acceptance criteria:
  # - Confirming releases the manual quotes of the range as the operator
  #   (one journal entry, owner_ui), provider quotes untouched.
  # - The dialog closes; a note in the Quotes tab says how many were released
  #   from when to when (the answer's count), that the next sync stores the
  #   provider's close, with "Kurse aktualisieren"; it is dismissible.
  # - Where the release takes the last manual quote and with it the
  #   "Freigeben…" that opened the dialog, the dialog names the result's
  #   dismiss as where the focus goes (closing act, γ D2).
  # - The data note now counts what is left.
  test "confirming releases through the journal and reports in the tab", ctx do
    with_adapter(ctx)
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    view
    |> element(
      "#quote-release-dialog [data-role='release-stretches'] button",
      "#{ctx.de.(-5)} – "
    )
    |> render_click()

    view |> element("[data-role='quote-release-confirm']") |> render_click()

    assert manual_dates(ctx.security) == [ctx.day.(-1100), ctx.day.(-1099)]

    assert [entry] =
             Repo.all(
               from(e in Entry,
                 where: e.resource_type == "security_quotes" and e.operation == :delete
               )
             )

    assert entry.actor_type == :owner_ui
    refute has_element?(view, "#quote-release-dialog")

    hook = File.read!("lib/portfolixir_web/layout_view.ex")
    assert hook =~ ~s{this.el.getAttribute("data-focus-fallback")}
    assert hook =~ "document.querySelector(this.focusFallback)"

    result = "#detail-tab-panel-quotes #quotes-release-result"

    assert text(view, result) =~
             "2 manuelle Kurse freigegeben, vom #{ctx.de.(-5)} bis #{ctx.de.(-4)}. Die nächste Kursaktualisierung speichert für diese Tage den Schlusskurs des Anbieters."

    assert has_element?(
             view,
             "#{result} button[phx-click='sync_quotes_released']",
             "Kurse aktualisieren"
           )

    assert text(view, "[data-role='manual-quotes-note']") =~
             "2 manuelle Kurse in der gespeicherten Historie, vom #{ctx.de.(-1100)} bis #{ctx.de.(-1099)}."

    view |> element("#{result} .inline-result__dismiss") |> render_click()
    refute text(view, result) =~ "freigegeben"
  end

  # User story:
  # As the operator of a security the sync cannot refill,
  # I want the result to say the released days stay without a quote, and no
  # sync button,
  # so that the follow-up the page offers is one that can help (A5, UX-DR25 ③).
  #
  # Acceptance criteria:
  # - Without an adapter the result's second sentence is "Für dieses
  #   Wertpapier holt die Kursaktualisierung keine Kurse: Diese Tage bleiben
  #   ohne Kurs." and there is no "Kurse aktualisieren".
  # - Releasing every manual quote leaves no note and no "Freigeben…".
  test "without an adapter the result says the days stay empty", ctx do
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    assert has_element?(
             view,
             ~s(#quote-release-dialog[data-focus-fallback="#quotes-release-result .inline-result__dismiss"])
           )

    view |> element("[data-role='quote-release-confirm']") |> render_click()

    assert manual_dates(ctx.security) == []

    result = "#detail-tab-panel-quotes #quotes-release-result"

    assert text(view, result) =~
             "4 manuelle Kurse freigegeben, vom #{ctx.de.(-1100)} bis #{ctx.de.(-4)}. Für dieses Wertpapier holt die Kursaktualisierung keine Kurse: Diese Tage bleiben ohne Kurs."

    refute has_element?(view, "#{result} [data-role='release-sync']")
    refute has_element?(view, "[data-role='manual-quotes-note']")
  end

  # User story:
  # As the operator whose agent merged the shown security away meanwhile,
  # I want "Freigeben…" to follow the merge to the survivor,
  # so that the page shows the security that now holds the quotes instead of
  # failing (closing act, γ correctness CR-1).
  #
  # Acceptance criteria:
  # - Clicking "Freigeben…" for a security merged away since the page showed
  #   it opens no dialog and patches to the survivor with its merged notice.
  test "Release… on a security merged away meanwhile follows the merge", ctx do
    # The same name, so the merge resolves the source's stored identity.
    target = create_security!(name: "Meridian Global Equity ETF", ticker: nil)
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)

    {:ok, preview} = Lifecycle.preview_security_merge(ctx.security.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.api_token_rw("synthetic"), ctx.security.id, target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false
      })

    view |> element("[data-role='release-manual-quotes']") |> render_click()

    assert_patch(view)
    refute has_element?(view, "#quote-release-dialog")
    assert has_element?(view, "#security-row-#{target.id}.is-selected")
    assert has_element?(view, "#security-detail-pane [data-role='merged-notice']")
  end

  # User story:
  # As the operator confirming a release,
  # I want the write to release the number of manual quotes the confirm
  # named, and to be asked again when the range holds another number by now,
  # so that I never approve two and release three (closing act, γ CR-2).
  #
  # Acceptance criteria:
  # - When a manual quote lands in the range after the dialog counted it,
  #   confirming writes nothing; the dialog says how many the range holds now
  #   and the confirm names the new count.
  # - Confirming again releases them all.
  test "a range recounted since the confirm was shown is asked again", ctx do
    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    assert text(view, "[data-role='quote-release-confirm']") == "4 manuelle Kurse freigeben"

    {:ok, _} =
      Quotes.upsert_authored(Actor.api_token_rw("synthetic"), ctx.security.id, [
        %{"date" => ctx.iso.(-50), "close" => "95.00"}
      ])

    view |> element("[data-role='quote-release-confirm']") |> render_click()

    assert length(manual_dates(ctx.security)) == 5
    assert has_element?(view, "#quote-release-dialog")

    assert text(view, "[data-role='quote-release-error']") ==
             "Der Zeitraum enthält inzwischen 5 manuelle Kurse — prüfen und erneut bestätigen."

    refute has_element?(view, "#quote-release-from[aria-invalid]")
    refute has_element?(view, "#quote-release-to[aria-invalid]")
    assert text(view, "[data-role='quote-release-confirm']") == "5 manuelle Kurse freigeben"

    view |> element("[data-role='quote-release-confirm']") |> render_click()

    assert manual_dates(ctx.security) == []
    refute has_element?(view, "#quote-release-dialog")
  end

  # User story:
  # As the operator of a security with many stretches of manual quotes, or a
  # single one,
  # I want the chips to say when they leave stretches out, and not to repeat
  # "Alle",
  # so that a prefilled date no chip shows is explained (closing act, γ D3,
  # n7) — and a single release reads in the singular (γ n6).
  #
  # Acceptance criteria:
  # - Seven stretches: "Alle · N" and five chips, the newest; below them "Die
  #   5 neuesten von 7 Abschnitten; „Alle“ umfasst jeden."
  # - A one-day stretch's chip names its day once.
  # - One stretch only: "Alle" alone, no hint.
  # - Releasing one quote: "… für diesen Tag …".
  test "the chips say the cut, name a day once and never repeat All", ctx do
    with_adapter(ctx)

    many = create_security!(name: "Halvorsen Shipping Bond 2031", ticker: nil)

    {:ok, many} =
      Catalog.update_security(Actor.owner_ui(), many, %{provider: "portfolio_performance"})

    # Seven stretches 20 days apart, each split from the next by a provider
    # close; the newest is one day.
    {:ok, _} =
      Quotes.upsert_many(
        many.id,
        Enum.map(
          0..6,
          &%{date: ctx.day.(-195 + 20 * &1), close: "50.00", source: "portfolio_performance"}
        )
      )

    {:ok, _} =
      Quotes.upsert_authored(
        Actor.api_token_rw("synthetic"),
        many.id,
        for k <- 0..6, offset <- if(k == 6, do: [0], else: [0, 1]) do
          %{"date" => ctx.iso.(-200 + 20 * k + offset), "close" => "51.00"}
        end
      )

    {:ok, view, _html} = quotes_tab(ctx.conn, many)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    chips =
      view
      |> element("#quote-release-dialog [data-role='release-stretches']")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("button.filter-chip")
      |> Enum.map(&(&1 |> Floki.text() |> String.split() |> Enum.join(" ")))

    assert length(chips) == 6
    assert hd(chips) == "Alle · 13"
    assert List.last(chips) == "#{ctx.de.(-80)} · 1"

    assert text(view, "#quote-release-dialog [data-role='release-stretches-cut']") ==
             "Die 5 neuesten von 7 Abschnitten; „Alle“ umfasst jeden."

    # One stretch, one day: "Alle" alone, no cut, and a singular result.
    single = create_security!(name: "Northwind Utilities", ticker: nil)

    {:ok, single} =
      Catalog.update_security(Actor.owner_ui(), single, %{provider: "portfolio_performance"})

    {:ok, _} =
      Quotes.upsert_authored(Actor.api_token_rw("synthetic"), single.id, [
        %{"date" => ctx.iso.(-7), "close" => "12.00"}
      ])

    {:ok, view, _html} = quotes_tab(ctx.conn, single)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    assert text(view, "#quote-release-dialog [data-role='release-stretches']") == "Alle · 1"
    refute has_element?(view, "[data-role='release-stretches-cut']")

    view |> element("[data-role='quote-release-confirm']") |> render_click()

    assert text(view, "#detail-tab-panel-quotes #quotes-release-result") =~
             "Ein manueller Kurs freigegeben, am #{ctx.de.(-7)}. Die nächste Kursaktualisierung speichert für diesen Tag den Schlusskurs des Anbieters."
  end

  # User story (#1012; board ux-design-2026-10-02/07-phone-390, H7.1b):
  # As the operator who pinned closes by hand,
  # I want the sync's result to say how many manual quotes stayed where the
  # provider returned a close for the same day,
  # so that I know why a manual day did not change, instead of reading
  # "Kurse aktualisiert." and wondering.
  #
  # Acceptance criteria:
  # - Where the sync kept manual quotes against a provider close, the result
  #   adds "N manuelle Kurse blieben stehen, wo der Anbieter einen
  #   Schlusskurs lieferte." — the sum of `skipped_manual` over every
  #   security the sync touched, singular "Ein manueller Kurs blieb stehen,
  #   …" for one.
  # - The manual quotes are untouched; the day without one takes the
  #   provider's close.
  # - Without such a collision the result is today's sentence alone.
  test "the sync's result counts the manual quotes that stayed", ctx do
    with_closing_adapter(ctx)
    {:ok, view, _html} = live(ctx.conn, "/securities?locale=de")

    {_result, log} =
      ExUnit.CaptureLog.with_log(fn ->
        view |> element("button#sync-prices") |> render_click()
        await_sync(view)
      end)

    assert log =~ "manual quote row(s)"

    assert text(view, "#securities-action-result") =~
             "Kurse aktualisiert. 2 manuelle Kurse blieben stehen, wo der Anbieter einen Schlusskurs lieferte."

    assert manual_dates(ctx.security) == [
             ctx.day.(-1100),
             ctx.day.(-1099),
             ctx.day.(-5),
             ctx.day.(-4)
           ]

    # One pin left in the provider's days: the singular.
    {:ok, _} =
      Quotes.release_manual(Actor.owner_ui(), ctx.security.id, ctx.day.(-5), ctx.day.(-5))

    ExUnit.CaptureLog.with_log(fn ->
      view |> element("button#sync-prices") |> render_click()
      await_sync(view)
    end)

    assert text(view, "#securities-action-result") =~
             "Kurse aktualisiert. Ein manueller Kurs blieb stehen, wo der Anbieter einen Schlusskurs lieferte."

    # No pin left there: the sentence of today, alone.
    {:ok, _} =
      Quotes.release_manual(Actor.owner_ui(), ctx.security.id, ctx.day.(-4), ctx.day.(-4))

    view |> element("button#sync-prices") |> render_click()
    await_sync(view)

    assert text(view, "#securities-action-result") =~ "Kurse aktualisiert."
    refute text(view, "#securities-action-result") =~ "blieb"
  end

  # User story (#1033; board ux-design-2026-10-02/07-phone-390, H7.4, code
  # only):
  # As the operator who just released manual quotes of one security,
  # I want "Kurse aktualisieren" in the release result to sync that
  # security,
  # so that the follow-up refills the released days without querying every
  # provider in the catalog, and its answer is about the security I am
  # looking at.
  #
  # Acceptance criteria:
  # - The follow-up syncs the released security only
  #   (`QuoteSync.sync_security/2`): another security with the same
  #   provider gets no quote from it.
  # - The released day takes the provider's close; a manual quote the
  #   release left keeps its place and is counted (H7.1b).
  # - The follow-up clears the release result, and its own result lands in
  #   the page-level slot, as before: "Kurse aktualisiert. Ein manueller
  #   Kurs blieb stehen, …".
  test "the release result's sync syncs the released security only", ctx do
    with_closing_adapter(ctx)

    other = create_security!(name: "Halvorsen Shipping ASA", ticker: nil)

    {:ok, other} =
      Catalog.update_security(Actor.owner_ui(), other, %{provider: "portfolio_performance"})

    {:ok, view, _html} = quotes_tab(ctx.conn, ctx.security)
    view |> element("[data-role='release-manual-quotes']") |> render_click()

    view
    |> form("#quote-release-form", release: %{from: ctx.iso.(-5), to: ctx.iso.(-5)})
    |> render_change()

    view |> element("[data-role='quote-release-confirm']") |> render_click()

    result = "#detail-tab-panel-quotes #quotes-release-result"
    follow_up = "#{result} button[phx-click='sync_quotes_released'][data-role='release-sync']"
    assert has_element?(view, follow_up, "Kurse aktualisieren")

    {_result, log} =
      ExUnit.CaptureLog.with_log(fn ->
        view |> element(follow_up) |> render_click()
        await_sync(view)
      end)

    assert log =~ "manual quote row(s) for security ##{ctx.security.id}"

    assert Repo.all(from(q in SecurityQuote, where: q.security_id == ^other.id)) == []

    assert Repo.get_by!(SecurityQuote, security_id: ctx.security.id, date: ctx.day.(-5)).source ==
             "portfolio_performance"

    assert manual_dates(ctx.security) == [ctx.day.(-1100), ctx.day.(-1099), ctx.day.(-4)]

    refute text(view, result) =~ "freigegeben"

    assert text(view, "#securities-action-result") =~
             "Kurse aktualisiert. Ein manueller Kurs blieb stehen, wo der Anbieter einen Schlusskurs lieferte."
  end

  # User story (#1033; board 07, H7.4, "stated for the story"):
  # As the operator syncing one security,
  # I want a skipped sync to say why in words,
  # so that "Kurssync übersprungen: no_provider_adapter" does not ask me to
  # read an atom.
  #
  # Acceptance criteria:
  # - The reasons the single path can reach read as words:
  #   `:no_provider_adapter`, `:missing_ticker`, `:missing_currency` and
  #   `:sync_in_progress` (the single-flight lock held by another sync).
  test "a skipped single sync says why in words", ctx do
    {:ok, view, _html} = live(ctx.conn, "/securities?locale=de")

    render_click(view, "row_action", %{"action" => "sync", "id" => to_string(ctx.security.id)})
    await_sync(view)

    assert text(view, "#securities-action-result") =~
             "Kurssync übersprungen: Für dieses Wertpapier gibt es keinen Kursanbieter."

    refute text(view, "#securities-action-result") =~ "no_provider_adapter"
  end

  # User story (#1033; board 07, H7.4 — the story above, its other three
  # reasons):
  # As the operator syncing one security,
  # I want every skip the single path can reach to say why in words,
  # so that no reason reaches me as an atom.
  #
  # Acceptance criteria:
  # - A provider that needs the ticker, on a security without one: "Der
  #   Kursanbieter braucht den Ticker des Wertpapiers."
  # - A provider that needs the currency: "Das Wertpapier hat keine
  #   Währung."
  # - A sync of the security already running (the single-flight lock held
  #   by another sync): "Eine Kursaktualisierung dieses Wertpapiers läuft
  #   bereits."
  test "the other skip reasons of a single sync read as words, too", ctx do
    config = Application.get_env(:portfolixir, QuoteSync, [])
    on_exit(fn -> Application.put_env(:portfolixir, QuoteSync, config) end)

    sync = fn adapter ->
      Application.put_env(
        :portfolixir,
        QuoteSync,
        Keyword.put(config, :adapter_for, %{"portfolio_performance" => adapter})
      )

      {:ok, view, _html} = live(ctx.conn, "/securities?locale=de")
      render_click(view, "row_action", %{"action" => "sync", "id" => to_string(ctx.security.id)})
      await_sync(view)
      text(view, "#securities-action-result")
    end

    # The shipped adapter refuses a security without a ticker before it
    # makes any request.
    assert sync.(Yahoo) =~
             "Kurssync übersprungen: Der Kursanbieter braucht den Ticker des Wertpapiers."

    assert sync.(CurrencyBoundAdapter) =~
             "Kurssync übersprungen: Das Wertpapier hat keine Währung."

    test_pid = self()

    holder =
      spawn_link(fn ->
        SingleFlight.run({:quote_sync, ctx.security.id}, fn ->
          send(test_pid, :holding)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :holding

    assert sync.(ClosingAdapter) =~
             "Kurssync übersprungen: Eine Kursaktualisierung dieses Wertpapiers läuft bereits."

    send(holder, :release)
  end
end
