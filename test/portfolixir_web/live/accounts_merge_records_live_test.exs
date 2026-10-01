defmodule PortfolixirWeb.AccountsMergeRecordsLiveTest do
  # ADR-0050 §12's human view (Sprint 17 V1; board
  # ux-design-2026-10-01/02-merge-records, pick G2-A): the merge records as a
  # collapsed section at the end of Accounts & depots, every kind in one
  # list, newest first, read-only. The list reads what GET /api/v1/merges
  # carries (Portfolixir.Lifecycle.list_merges/1 and manifest_summary/1).
  # Every name, identifier, amount and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Clock
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.Delete
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.PortfolioAccounts.MergeRecords

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    %{portfolio: portfolio, today: Clock.today() |> Calendar.strftime("%d.%m.%Y")}
  end

  # User story:
  # As the operator who merged accounts, depots and securities over weeks,
  # I want one list of every merge at the end of Accounts & depots, newest
  # first, saying when, what kind, what went into what, what it did and
  # who ran it,
  # so that I can read back what the merges did without asking the agent
  # (ADR-0050 §12; pick G2-A).
  #
  # Acceptance criteria:
  # - A section "Zusammenführungen" after the accounts table and before the
  #   compatibility records, its list collapsed under "N Einträge · zuletzt
  #   <date>".
  # - One table for all three kinds, newest first: the date, the kind, the
  #   source (muted, not struck) → the target (a link), the result in the
  #   confirmation's own words, and "Operator" or "Agent".
  # - Read-only: no button, no form and no undo wording in the section.
  test "lists every merge newest first in one collapsed section", ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    old = cash!(ctx.portfolio, "Tagesgeld")
    deposit!(ctx.portfolio, old, "100.00", ~D[2026-01-05])
    deposit!(ctx.portfolio, old, "40.00", ~D[2026-01-06])
    cash_merge = merge_cash!(Actor.api_token_rw("synthetic"), old, giro)

    depot_1 = depot!(ctx.portfolio, "Depot 1", giro)
    depot_2 = depot!(ctx.portfolio, "Depot 2 (alt)", giro)
    depot_merge = merge_depot!(Actor.owner_ui(), depot_2, depot_1)

    target = security!("Alder Creek Timber Fund", "XS0000000017")
    source = security!("Alder Creek Timber Fund Class B", "XS0000000025")
    buy!(ctx.portfolio, depot_1, giro, source, "2", "10.00", ~D[2026-02-02])

    {:ok, 1} =
      Quotes.upsert_many(source.id, [
        %{date: ~D[2026-02-02], close: "10.00", source: "portfolio_performance"}
      ])

    security_merge =
      merge_security!(Actor.api_token_rw("synthetic"), source, target, "keep_target_isin")

    {:ok, view, _html} = live(ctx.conn, "/portfolios?locale=de")

    html = render(view)
    assert html =~ ~r/id="accounts-panel".*id="merge-records".*id="portfolio-admin"/s

    section = view |> element("#merge-records") |> render() |> Floki.parse_fragment!()
    assert Floki.text(Floki.find(section, "h2")) =~ "Zusammenführungen"

    [disclosure] = Floki.find(section, "details.section-disclosure")
    assert Floki.attribute(disclosure, "open") == []

    assert squish(Floki.find(disclosure, "[data-role='merge-records-summary']")) ==
             "3 Einträge · zuletzt #{ctx.today}"

    rows = Floki.find(section, ".merge-records-table tbody tr")

    assert Enum.map(rows, &(Floki.attribute(&1, "data-merge") |> hd())) ==
             Enum.map([security_merge, depot_merge, cash_merge], &to_string(&1.id))

    [security_row, depot_row, cash_row] = rows

    assert squish(Floki.find(security_row, ".cell-date")) == ctx.today
    assert squish(Floki.find(security_row, ".cell-kind")) == "Wertpapier"

    assert squish(Floki.find(security_row, ".merge-record__source")) ==
             "Alder Creek Timber Fund Class B"

    assert Floki.attribute(Floki.find(security_row, "a.merge-record__target"), "href") ==
             ["/securities/#{target.id}"]

    assert squish(Floki.find(security_row, ".merge-manifest > summary")) ==
             "1 Buchung verschoben, 1 Kurs ergänzt"

    assert squish(Floki.find(security_row, ".cell-actor")) == "Agent"

    assert squish(Floki.find(depot_row, ".cell-kind")) == "Depot"
    assert squish(Floki.find(depot_row, ".cell-actor")) == "Operator"

    # A depot that held nothing had nothing to check, and says so.
    assert depot_row |> Floki.find(".merge-manifest__counts dd") |> List.last() |> squish() ==
             "nichts zu prüfen"

    assert Floki.attribute(Floki.find(depot_row, "a.merge-record__target"), "href") ==
             ["#account-row-depot-#{depot_1.id}"]

    assert squish(Floki.find(cash_row, ".cell-kind")) == "Verrechnungskonto"
    assert squish(Floki.find(cash_row, ".merge-record__source")) == "Tagesgeld"
    assert squish(Floki.find(cash_row, "a.merge-record__target")) == "Girokonto"

    assert squish(Floki.find(cash_row, ".merge-manifest > summary")) ==
             "2 Buchungen verschoben"

    # Read-only (ADR-0050 §12): nothing in the section writes, and nothing
    # suggests a merge can be taken back.
    assert Floki.find(section, "button") == []
    assert Floki.find(section, "form") == []
    refute Floki.text(section) =~ ~r/rückgängig|undo/i
  end

  # User story:
  # As the operator reading what a merge did,
  # I want its result to open into the count per table, the choice I made
  # and the check the merge passed, in words,
  # so that "6 removed" says what was removed and why (pick G2-A ③).
  #
  # Acceptance criteria:
  # - The result's summary is the confirmation's phrase; the removed
  #   bookings are named per reason in the disclosure.
  # - Each table with a figure other than zero is a line with a fixed
  #   German label; the choice and the check are lines of their own.
  # - No manifest key reaches the screen.
  test "a result opens into the counts per table, the choice and the check", ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    old = cash!(ctx.portfolio, "Tagesgeld (alt)")
    deposit!(ctx.portfolio, old, "50.00", ~D[2026-03-02])
    deposit!(ctx.portfolio, giro, "50.00", ~D[2026-03-02])
    deposit!(ctx.portfolio, old, "70.00", ~D[2026-03-03])
    transfer!(ctx.portfolio, old, giro, "20.00", ~D[2026-03-04])

    {:ok, preview} = Lifecycle.preview_cash_merge(old.id, giro.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_cash_account(Actor.owner_ui(), old.id, giro.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: true
      })

    {:ok, view, _html} = live(ctx.conn, "/portfolios?locale=de")

    [row] =
      view
      |> element("#merge-records")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find(".merge-records-table tbody tr")

    assert squish(Floki.find(row, ".merge-manifest > summary")) ==
             "1 Buchung verschoben, 2 entfernt"

    counts = Floki.find(row, ".merge-manifest__counts")

    lines =
      Map.new(
        Enum.zip(
          counts |> Floki.find("dt") |> Enum.map(&squish/1),
          counts |> Floki.find("dd") |> Enum.map(&squish/1)
        )
      )

    assert lines["Buchungen"] ==
             "1 verschoben · 1 Duplikat entfernt · 1 interne Umbuchung entfallen"

    assert lines["Frühere Namen"] == "1 übernommen"
    assert lines["Wahl"] == "gleiche Buchungen: als Duplikate entfernt"
    assert lines["Prüfung"] =~ ~r/^Saldo an \d+ Tagen bestätigt$/

    text = row |> Floki.find(".merge-manifest") |> Floki.text()

    for key <- ~w(collapse_key_equal deleted_by_reason internal_transfer collapsed_duplicate
                  dates_checked restated_anchors former_names transactions) do
      refute text =~ key
    end
  end

  # User story:
  # As the operator whose earlier merge target was merged on or deleted,
  # I want the row to say where the bookings live now, or that the target is
  # gone,
  # so that a merge chain never ends at a name the page no longer shows
  # (pick G2-A ⑥).
  #
  # Acceptance criteria:
  # - A target a later merge took away: its recorded name, muted, and
  #   "jetzt in <survivor>" linking the live end of the chain.
  # - A target deleted since: "ein inzwischen gelöschtes Depot", no link.
  test "a later merge reads 'now in', a deleted target names its kind", ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    tagesgeld = cash!(ctx.portfolio, "Tagesgeld")
    old = cash!(ctx.portfolio, "Tagesgeld (alt)")
    first = merge_cash!(Actor.owner_ui(), old, tagesgeld)
    merge_cash!(Actor.owner_ui(), tagesgeld, giro)

    depot_3 = depot!(ctx.portfolio, "Depot 3", giro)
    depot_4 = depot!(ctx.portfolio, "Depot 4", giro)
    gone = merge_depot!(Actor.owner_ui(), depot_3, depot_4)

    {:ok, _deleted} =
      Delete.remove(Actor.owner_ui(), Portfolios.get_securities_account(depot_4.id))

    {:ok, view, _html} = live(ctx.conn, "/portfolios?locale=de")
    section = view |> element("#merge-records") |> render() |> Floki.parse_fragment!()

    chained = Floki.find(section, ".merge-records-table tr[data-merge='#{first.id}']")
    assert squish(Floki.find(chained, ".merge-record__target")) == "Tagesgeld"
    assert Floki.find(chained, "a.merge-record__target") == []
    assert squish(Floki.find(chained, ".merge-record__later")) == "jetzt in Girokonto"

    assert Floki.attribute(Floki.find(chained, ".merge-record__later a"), "href") ==
             ["#account-row-cash-#{giro.id}"]

    deleted = Floki.find(section, ".merge-records-table tr[data-merge='#{gone.id}']")

    assert squish(Floki.find(deleted, ".merge-record__target--deleted")) ==
             "ein inzwischen gelöschtes Depot"

    assert Floki.find(deleted, "a") == []
  end

  # User story:
  # As the operator looking at an account that absorbed another,
  # I want the date in its "merged from" line to take me to that merge's
  # record,
  # so that the survivor's line and the list are one reading (pick G2-A ⑤,
  # replacing G13.1's "the line links nothing").
  #
  # Acceptance criteria:
  # - The date in "zusammengeführt aus … · <date>" links
  #   /portfolios?merge=<record id>#merge-records.
  # - That URL renders the section open and that record's result open.
  test "the survivor's date opens its record in the list", ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    old = cash!(ctx.portfolio, "Tagesgeld")
    other = cash!(ctx.portfolio, "Festgeld")
    record = merge_cash!(Actor.owner_ui(), old, giro)
    later = merge_cash!(Actor.owner_ui(), other, cash!(ctx.portfolio, "Sparkonto"))

    {:ok, view, _html} = live(ctx.conn, "/portfolios?locale=de")

    link = element(view, "#account-row-cash-#{giro.id} [data-role='account-merged-link']")
    assert render(link) =~ ctx.today
    assert render(link) =~ ~s(href="/portfolios?merge=#{record.id}#merge-records")

    {:ok, view, _html} = live(ctx.conn, "/portfolios?locale=de&merge=#{record.id}")
    section = view |> element("#merge-records") |> render() |> Floki.parse_fragment!()

    assert [_] = Floki.find(section, "details.section-disclosure[open]")

    assert [_] =
             Floki.find(
               section,
               ".merge-records-table tr[data-merge] details.merge-manifest[open]"
             )

    assert [_] =
             Floki.find(
               section,
               ".merge-records-table tr[data-merge='#{record.id}'] details.merge-manifest[open]"
             )

    assert Floki.find(
             section,
             ".merge-records-table tr[data-merge='#{later.id}'] details.merge-manifest[open]"
           ) == []
  end

  # User story:
  # As the operator on an instance where nothing was merged yet,
  # I want the section to say in one sentence where a merge starts,
  # so that the list's absence is not read as a missing feature (pick G2-A ⑦).
  #
  # Acceptance criteria:
  # - One .empty-state sentence naming "Zusammenführen in…" in the row
  #   menus; no list, no disclosure and no action.
  test "an empty list names where a merge starts and offers nothing", %{conn: conn} = ctx do
    cash!(ctx.portfolio, "Girokonto")
    {:ok, view, _html} = live(conn, "/portfolios?locale=de")

    section = view |> element("#merge-records") |> render() |> Floki.parse_fragment!()

    assert squish(Floki.find(section, ".empty-state")) ==
             "Noch keine Zusammenführung — „Zusammenführen in…“ steht im Zeilenmenü jedes Kontos, Depots und Wertpapiers."

    assert Floki.find(section, "details") == []
    assert Floki.find(section, "table") == []
    assert Floki.find(section, "button") == []
  end

  # User story:
  # As the operator on a phone,
  # I want each merge as a two-line row — what went into what over date,
  # kind and who — with its result opening full width beneath,
  # so that nothing scrolls sideways at 390 px (UX-DR27; pick G2-A ④).
  #
  # Acceptance criteria:
  # - Beside the table, one .phone-row per merge in the same order: the
  #   pair as the name line, "date · kind · by" as the identifier line, and
  #   the same result disclosure.
  test "phone rows carry the pair over date, kind and who", ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    old = cash!(ctx.portfolio, "Tagesgeld")
    record = merge_cash!(Actor.api_token_rw("synthetic"), old, giro)

    {:ok, view, _html} = live(ctx.conn, "/portfolios?locale=de")

    [row] =
      view
      |> element("#merge-records")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("ul.merge-records__rows > li.phone-row")

    assert Floki.attribute(row, "data-merge") == [to_string(record.id)]
    assert squish(Floki.find(row, ".phone-row__name")) =~ ~r/^Tagesgeld\s*→?\s*in\s*Girokonto$/

    assert squish(Floki.find(row, ".phone-row__ids")) ==
             "#{ctx.today} · Verrechnungskonto · Agent"

    assert [_] = Floki.find(row, "details.merge-manifest")
  end

  # User story:
  # As the maintainer adding a merge writer or a manifest key,
  # I want a test that fails when a key the writers emit has no fixed label,
  # so that a raw key never reaches the operator's screen (the board's
  # first finding, Sprint 17 V1).
  #
  # Acceptance criteria:
  # - Every key path of manifest_summary that the three merge writers emit
  #   (cash account, depot, security with an adopted ISIN) is a labelled
  #   path of the list, and each line it feeds has a German label.
  # - Every reason a writer gives a removed booking is labelled.
  test "every manifest key the three writers emit has a fixed label", ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    old = cash!(ctx.portfolio, "Tagesgeld")
    deposit!(ctx.portfolio, old, "10.00", ~D[2026-01-05])
    cash_record = merge_cash!(Actor.owner_ui(), old, giro)

    depot_1 = depot!(ctx.portfolio, "Depot 1", giro)
    depot_2 = depot!(ctx.portfolio, "Depot 2", giro)
    depot_record = merge_depot!(Actor.owner_ui(), depot_2, depot_1)

    target = security!("Alder Creek Timber Fund", "XS0000000017")
    source = security!("Alder Creek Timber Fund Class B", "XS0000000025")
    security_record = merge_security!(Actor.owner_ui(), source, target, "adopt_source_isin")

    labelled = MergeRecords.labelled_paths()

    emitted =
      for record <- [cash_record, depot_record, security_record],
          path <- record.manifest |> Lifecycle.manifest_summary() |> leaf_paths(),
          uniq: true,
          do: path

    assert emitted -- labelled == []
    assert ["identifier_aliases", "created", "former_isin"] in emitted

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      for path <- labelled do
        label = MergeRecords.line_label(MergeRecords.line_of(path))
        assert is_binary(label) and label != ""
      end

      assert MergeRecords.line_label(:bookings) == "Buchungen"
      assert MergeRecords.line_label(:check) == "Prüfung"
    end)

    reasons =
      for file <- ~w(cash_merge depot_merge security_merge),
          [_, reason] <-
            Regex.scan(
              ~r/reason: :(\w+),\s+superseded_by:/,
              File.read!("lib/portfolixir/lifecycle/#{file}.ex")
            ),
          uniq: true,
          do: reason

    assert Enum.sort(reasons) ==
             ~w(collapsed_duplicate collapsed_split folded_anchor internal_transfer)

    for reason <- reasons do
      assert ["transactions", "deleted_by_reason", reason] in labelled
    end
  end

  # User story:
  # As the operator of an instance with more merges than the list shows,
  # I want the summary to say it shows the newest only,
  # so that a list cut at the API's page is not read as complete (UX-DR26).
  #
  # Acceptance criteria:
  # - When more records exist than are shown, the summary reads
  #   "die neuesten N · zuletzt <date>" instead of "N Einträge".
  test "a list cut at its page says it shows the newest only" do
    record = %{
      id: 7,
      kind: :cash_account,
      date: ~D[2026-09-30],
      source_name: "Tagesgeld",
      target: {:live, %{name: "Girokonto", href: "#account-row-cash-1"}},
      actor: :operator,
      summary: %{"transactions" => %{"moved" => 3, "deleted" => 0, "deleted_by_reason" => %{}}}
    }

    html =
      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        render_component(&MergeRecords.section/1, records: [record], more?: true)
      end)

    summary = html |> Floki.parse_fragment!() |> Floki.find("[data-role='merge-records-summary']")
    assert squish(summary) == "die neuesten 1 · zuletzt 30.09.2026"
    refute html =~ "merge-records-focus-missing"

    # A link naming a merge past the cut (a survivor's date, closing act γ):
    # the section opens and says the merge is not among those listed,
    # instead of opening nothing without a word.
    past =
      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        render_component(&MergeRecords.section/1, records: [record], more?: true, focus: 3)
      end)
      |> Floki.parse_fragment!()

    assert [_] = Floki.find(past, "details.section-disclosure[open]")

    assert squish(Floki.find(past, "[data-role='merge-records-focus-missing']")) ==
             "Die Zusammenführung, die der Link nennt, steht nicht unter den neuesten 1."

    # A complete list: an id it does not carry names no merge, so nothing
    # is said, as before.
    whole = render_component(&MergeRecords.section/1, records: [record], focus: 3)
    refute whole =~ "merge-records-focus-missing"
  end

  # Acceptance criteria (closing act γ D8):
  # - The section and each entry clear the sticky top bar when a link
  #   scrolls to them (scroll-margin-top), and the entry a link opened is
  #   scrolled to the top by the MergeFocus hook and its visible result
  #   summary focused, once per opened id.
  test "the opened entry clears the top bar and is brought into view", ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    record = merge_cash!(Actor.owner_ui(), cash!(ctx.portfolio, "Tagesgeld"), giro)

    {:ok, view, _html} = live(ctx.conn, "/portfolios?merge=#{record.id}")

    assert has_element?(
             view,
             "#merge-records[phx-hook='MergeFocus'][data-focus='#{record.id}']"
           )

    css = File.read!("priv/static/app.css")
    assert css =~ ~r/#merge-records,\s*\.merge-records \[data-merge\]\s*\{[^}]*scroll-margin-top/

    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.MergeFocus")
      |> Enum.at(1)
      |> String.split("Hooks.")
      |> hd()

    assert hook =~ "details.merge-manifest[open] > summary"
    assert hook =~ "offsetParent !== null"
    assert hook =~ ~s[scrollIntoView({ block: "start" })]
    assert hook =~ "focus({ preventScroll: true })"
  end

  # -- helpers ---------------------------------------------------------------------

  defp leaf_paths(map, prefix \\ []) when is_map(map) do
    if map == %{} do
      [prefix]
    else
      Enum.flat_map(map, fn
        {key, value} when is_map(value) -> leaf_paths(value, prefix ++ [key])
        {key, _value} -> [prefix ++ [key]]
      end)
    end
  end

  defp squish(nodes), do: nodes |> Floki.text() |> String.split() |> Enum.join(" ")

  defp merge_cash!(actor, source, target) do
    {:ok, preview} = Lifecycle.preview_cash_merge(source.id, target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_cash_account(actor, source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    record
  end

  defp merge_depot!(actor, source, target) do
    {:ok, preview} = Lifecycle.preview_depot_merge(source.id, target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_depot(actor, source.id, target.id, %{plan_digest: preview.plan_digest})

    record
  end

  defp merge_security!(actor, source, target, identity) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_security(actor, source.id, target.id, %{
        plan_digest: preview.plan_digest,
        identity_choice: identity
      })

    record
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp depot!(portfolio, name, cash) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        cash_account_id: cash.id
      })

    depot
  end

  defp security!(name, isin) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        isin: isin,
        currency_code: "EUR",
        asset_class: "etf"
      })

    security
  end

  defp deposit!(portfolio, account, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: account.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp transfer!(portfolio, from, to, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: from.id,
        counter_cash_account_id: to.id,
        type: "cash_transfer",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp buy!(portfolio, depot, cash, security, quantity, price, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: quantity,
        price: price,
        currency_code: "EUR"
      })

    tx
  end
end
