defmodule PortfolixirWeb.FloorSecondPassLiveTest do
  # Sprint 19 PR γ U5, board ux-design-2026-10-04/07-floor (Part 7 of the
  # design pass; picks J7 = A and J7.2 = A): what the floor's second pass
  # changes in the rendered markup — the page result slots, the balance's
  # words, the role label on the phone card, and the merge record's ISIN
  # line. The CSS half is pinned in
  # test/invariants/css_floor_second_pass_test.exs.
  #
  # Every name, figure, identifier and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Risk.PolicyRuleDialog

  # User story (#1064, J7 = A; board 07, J7):
  # As the operator deleting a booking under the coral accent in the dark
  # theme,
  # I want the page to say in a word whether it deleted the booking or found
  # it gone,
  # so that I do not read "deleted" where it said "no longer exists" — the
  # two looked identical, in the same colour, with no word.
  #
  # Acceptance criteria:
  # - The history's result slot is `AppShell.inline_result`: a success reads
  #   as a note ("Note", the asterisk), a refusal as a problem ("Problem",
  #   the octagon), each with the dismiss; no `.alert-success` or
  #   `.alert-error` stays on the page.
  # - The problem lands in the `role="alert"` region, the note in the
  #   `role="status"` one; the dismiss clears the result.
  test "the history's delete result says Note, a gone booking says Problem", %{conn: conn} do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    security = create_security!(name: "Global Aktien ETF", ticker: "GAE")
    deposit!(world, "5000", ~D[2026-09-03])
    buy = buy!(world, security, quantity: "40", price: "62.50", date: ~D[2026-09-22])
    other = buy!(world, security, quantity: "4", price: "60", date: ~D[2026-09-24])

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(
             view,
             "#transactions-result.inline-result--page[data-role='action-result']"
           )

    ask_delete(view, buy)
    view |> element("#booking-delete-confirm") |> render_click()

    note = view |> element("#transactions-result-status .data-note--note") |> render()
    assert text(note) =~ "Note Transaction deleted: Buy · Global Aktien ETF · 2026-09-22."
    assert note =~ ~s(class="inline-result__dismiss")
    refute has_element?(view, ".alert-success")

    view |> element("#transactions-result .inline-result__dismiss") |> render_click()
    refute has_element?(view, "#transactions-result .data-note")

    ask_delete(view, other)

    {:ok, _gone} =
      Ledger.delete_transaction(Actor.api_token_rw("agent"), Ledger.get_transaction(other.id))

    view |> element("#booking-delete-confirm") |> render_click()

    problem = view |> element("#transactions-result-alert .data-note--problem") |> render()
    assert text(problem) =~ "Problem That transaction no longer exists."
    refute has_element?(view, ".alert-error")
  end

  # User story (#1064, J7 = A; the PR γ closing act, design critic's
  # judgement (c)):
  # As the operator who saved a booking's note on an English page,
  # I want the result to read "Note Booking note saved",
  # so that the severity word and the message do not stutter "Note Note
  # saved" now that every result carries its word.
  #
  # Acceptance criteria:
  # - The English message names what was saved, "Booking note saved", after
  #   the note's word "Note".
  # - German keeps "Notiz gespeichert" after "Hinweis", which never stuttered.
  test "a saved booking note does not read Note Note saved", %{conn: conn} do
    world = base_world(name: "Notizen", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit = deposit!(world, "1500", ~D[2026-09-03])

    for {query, expected} <- [
          {"", "Note Booking note saved"},
          {"?locale=de", "Hinweis Notiz gespeichert"}
        ] do
      {:ok, view, _html} = live(conn, "/transactions" <> query)
      view |> element("#tx-kebab-#{deposit.id}") |> render_click()
      view |> element("#tx-edit-#{deposit.id}") |> render_click()

      view
      |> form("#note-form", %{"note" => %{"notes" => "per the bank statement"}})
      |> render_submit()

      note = view |> element("#transactions-result-status .data-note--note") |> render() |> text()
      assert note =~ expected
      refute note =~ "Note Note"
    end
  end

  # User story (#1064, J7 = A: "Accounts & depots renders .alert-* and an
  # inline_result a few lines apart — A makes them one"):
  # As the operator changing a cash account's role,
  # I want the answer where every other answer on the page lands,
  # so that one page has one result slot, with its word.
  #
  # Acceptance criteria:
  # - A changed role answers as a note in `#accounts-result`; the page
  #   carries no `.alert-success` / `.alert-error` slot any more.
  # - A refused role answers as a problem in the same slot, in its
  #   `role="alert"` region.
  # - The dismiss empties the slot (the page has a catch-all handler, so a
  #   missing one would fail silently).
  test "Accounts answers in its one result slot", %{conn: conn} do
    %{cash: cash} = base_world(name: "Konten", cash_name: "Girokonto", depot_name: "Depot 1")

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> form("#liquidity-role-form-#{cash.id}", %{"liquidity_role" => "reserve"})
    |> render_change()

    assert view |> element("#accounts-result .data-note--note") |> render() |> text() =~
             "Note Cash account updated"

    refute has_element?(view, ".alert-success")
    refute has_element?(view, ".alert-error")

    view |> element("#accounts-result .inline-result__dismiss") |> render_click()
    refute has_element?(view, "#accounts-result .data-note")

    render_hook(view, "set_liquidity_role", %{
      "account_id" => to_string(cash.id),
      "liquidity_role" => "not-a-role"
    })

    assert view |> element("#accounts-result-alert .data-note--problem") |> render() |> text() =~
             "Problem Could not update cash account"

    refute has_element?(view, ".alert-error")
  end

  # User story (#1064, J7 = A):
  # As the operator creating a bucket, a category or a rule,
  # I want each page's answer to carry its word and its dismiss,
  # so that no page tells its outcome by colour alone.
  #
  # Acceptance criteria:
  # - Buckets, Classifications and Risk answer a success as a note in their
  #   result slot (`#buckets-result`, `#classifications-result`,
  #   `#policy-rules-result`, each an `.inline-result--page`), with the
  #   dismiss, and render no `.alert-success`.
  # - Each dismiss empties its slot (every page has a catch-all handler, so a
  #   missing one would fail silently).
  # - The "new classification" page answers a refused name as a problem in
  #   its own slot.
  test "Buckets, Classifications and Risk answer with a note", %{conn: conn} do
    world = base_world(name: "Regeln")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
    start = Date.add(Date.utc_today(), -5)
    deposit!(world, "1000", start)
    buy!(world, security, quantity: "2", price: "100", date: start)
    put_quote!(security, start, "100")

    {:ok, buckets, _html} = live(conn, "/buckets")
    buckets |> form("#bucket-form", bucket: %{name: "Altersvorsorge"}) |> render_submit()

    assert buckets
           |> element("#buckets-result.inline-result--page .data-note--note")
           |> render()
           |> text() =~
             "Note Bucket created"

    refute has_element?(buckets, ".alert-success")
    buckets |> element("#buckets-result .inline-result__dismiss") |> render_click()
    refute has_element?(buckets, "#buckets-result .data-note")

    {:ok, tree} =
      Portfolixir.Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

    {:ok, classes, _html} = live(conn, "/classifications/#{tree.id}")
    render_async(classes)
    classes |> form("form.category-form", category: %{name: "Wachstum"}) |> render_submit()

    assert classes
           |> element("#classifications-result.inline-result--page .data-note--note")
           |> render()
           |> text() =~
             "Note Category created"

    refute has_element?(classes, ".alert-success")
    classes |> element("#classifications-result .inline-result__dismiss") |> render_click()
    refute has_element?(classes, "#classifications-result .data-note")

    # The "new classification" page has the error half of the slot.
    {:ok, new, _html} = live(conn, "/classifications/new")
    new |> form("#classification-form", classification: %{name: ""}) |> render_submit()

    assert has_element?(
             new,
             "#classifications-result.inline-result--page #classifications-result-alert .data-note--problem"
           )

    refute has_element?(new, ".alert-error")

    {:ok, risk, _html} = live(conn, "/risk")
    send(risk.pid, {PolicyRuleDialog, {:saved, "Rule saved"}})

    assert risk
           |> element("#policy-rules-result.inline-result--page .data-note--note")
           |> render()
           |> text() =~
             "Note Rule saved"

    refute has_element?(risk, ".alert-success")
    risk |> element("#policy-rules-result .inline-result__dismiss") |> render_click()
    refute has_element?(risk, "#policy-rules-result .data-note")
  end

  # User story (#1064; the closing act of PR γ, the design critic's #8):
  # As the operator on the German Buckets page,
  # I want a refused name to read in German, with the field named as the
  # form names it,
  # so that the problem U5 put in the page's slot does not say "name has
  # already been taken" in an otherwise German screen.
  #
  # Acceptance criteria:
  # - A bucket or view name that is taken, or blank, is refused in the
  #   page's language through the app's changeset message
  #   (`FieldLabel.changeset_message/1`, the `errors` domain): "Name ist
  #   bereits vergeben", "Name darf nicht leer sein".
  # - Creating and renaming answer alike, as a problem in `#buckets-result`.
  test "a Buckets refusal reads in the page's language", %{conn: conn} do
    {:ok, _taken} = Portfolixir.Buckets.create_bucket(Actor.owner_ui(), %{name: "Kern"})
    {:ok, _taken} = Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Langfrist"})
    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

    {:ok, buckets, _html} = live(conn, "/buckets")
    buckets |> form("#bucket-form", bucket: %{name: "Kern"}) |> render_submit()

    problem = fn ->
      buckets
      |> element("#buckets-result #buckets-result-alert .data-note--problem")
      |> render()
      |> text()
    end

    assert problem.() =~ "Problem Name ist bereits vergeben"
    refute problem.() =~ "has already been taken"

    buckets |> form("#view-form", view: %{name: "Langfrist"}) |> render_submit()
    assert problem.() =~ "Problem Name ist bereits vergeben"

    buckets |> form("#view-form", view: %{name: ""}) |> render_submit()
    assert problem.() =~ "Problem Name darf nicht leer sein"
  end

  # User story (#1085, J7.2 = A; board 07.4 (a)):
  # As the operator reading a cash account's balance,
  # I want the date beside it to say what it is — the last booking,
  # so that "Stand 31.03.2026" does not read as a six-month-old balance when
  # it is today's.
  #
  # Acceptance criteria:
  # - The balance cell reads "last booking <date>" (de "letzte Buchung
  #   <date>"), the KPI strip's own word, under a msgid of its own; "as of"
  #   stays at its three other call sites.
  # - A balance with no booking keeps its quiet dash and no date line.
  test "the balance's date is its last booking", %{conn: conn} do
    %{cash: cash} = base_world(name: "Konten", cash_name: "Girokonto", depot_name: "Depot 1")

    {:ok, _} =
      Ledger.set_cash_balance(Actor.owner_ui(), cash, %{date: ~D[2026-08-01], amount: "1250.00"})

    {:ok, view, _html} = live(conn, "/portfolios")

    assert view |> element("#cash-balance-#{cash.id} .cash-balance__asof") |> render() |> squish() ==
             "last booking #{Format.date(~D[2026-08-01], "en")}"

    {:ok, de, _html} = live(conn, "/portfolios?locale=de")

    assert de |> element("#cash-balance-#{cash.id} .cash-balance__asof") |> render() |> squish() ==
             "letzte Buchung 01.08.2026"

    # A cash account no booking has touched: the quiet dash, no date line.
    %{cash: empty} = base_world(name: "Leer", cash_name: "Tagesgeld", depot_name: "Depot 2")
    {:ok, view, _html} = live(conn, "/portfolios")

    assert view |> element("#cash-balance-#{empty.id}") |> render() |> squish() == "—"
    refute has_element?(view, "#cash-balance-#{empty.id} .cash-balance__asof")
  end

  # User story (#1085, rule ⑦; and U6's ⓘ, board 08 ④):
  # As the operator on a phone reading a cash account's card,
  # I want "Liquiditätsrolle" beside the select, with its ⓘ next to the word,
  # so that "Verfügbares Cash" is not a value without a name, and the ⓘ does
  # not stand alone.
  #
  # Acceptance criteria:
  # - The select's label carries `.liquidity-role-field__label`, not
  #   `.visually-hidden`: the stylesheet hides it only above 640 px, where
  #   the column head states it.
  # - In the field the label comes first, then the ⓘ, then the select.
  test "the role select carries its label, the ⓘ beside the word", %{conn: conn} do
    %{cash: cash} = base_world(name: "Konten", cash_name: "Girokonto", depot_name: "Depot 1")

    {:ok, view, _html} = live(conn, "/portfolios?locale=de")

    field =
      view |> element("#liquidity-role-form-#{cash.id}") |> render() |> Floki.parse_fragment!()

    [label] = Floki.find(field, "label")
    assert Floki.attribute(label, "class") == ["liquidity-role-field__label"]
    assert Floki.attribute(label, "for") == ["liquidity-role-#{cash.id}"]
    assert String.trim(Floki.text(label)) == "Liquiditätsrolle"

    [form] = field

    assert form |> Floki.children() |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == "input")) ==
             ["label", "details", "select"]
  end

  # User story (#1067; board 07.5):
  # As the operator reading back an agent's merge of two securities,
  # I want the ISIN line only where a security carried an ISIN,
  # so that the record does not say "stays; is now a former ISIN" with
  # nothing in either slot.
  #
  # Acceptance criteria:
  # - The line keys on the ISINs the record holds, not on the choice it was
  #   given: neither side → no line; the target only → no line (nothing
  #   changed); the source only → "<ISIN> adopted from the source"; both →
  #   the given choice's sentence, as before — "stays" for keep, "adopted"
  #   for adopt.
  # - A merge records a given choice only where it made one (#1159), so the
  #   record of `neither` holds none; a record stored before that, which
  #   holds the choice as given with no ISIN on either side, still reads no
  #   line.
  test "the ISIN line follows the stored ISINs, not the given choice", %{conn: conn} do
    agent = Actor.api_token_rw("synthetic")

    # A merge with no ISIN on a side resolves that side's stored identity by
    # its name (ADR-0050 §9), so each pair is a twin name, as a duplicate is.
    neither =
      merge!(
        agent,
        create_security!(name: "Alder Creek Timber Fund", ticker: nil),
        create_security!(name: "Alder Creek Timber Fund", ticker: nil)
      )

    target_only =
      merge!(
        agent,
        create_security!(name: "Wrenfield Gardens AG", ticker: nil),
        create_security!(name: "Wrenfield Gardens AG", ticker: nil, isin: "DE0000000009")
      )

    source_only =
      merge!(
        agent,
        create_security!(name: "Tamarisk Mining Ltd", ticker: nil, isin: "XS0000000017"),
        create_security!(name: "Tamarisk Mining Ltd", ticker: nil)
      )

    both =
      merge!(
        agent,
        create_security!(name: "Kestrel Robotik SE", ticker: nil, isin: "XS0000000025"),
        create_security!(name: "Kestrel Robotik SE", ticker: nil, isin: "XS0000000033")
      )

    adopted =
      merge!(
        agent,
        create_security!(name: "Brightwater Utilities plc", ticker: nil, isin: "XS0000000041"),
        create_security!(name: "Brightwater Utilities plc", ticker: nil, isin: "DE0000000017"),
        "adopt_source_isin"
      )

    older =
      record_like!(
        neither,
        900_004,
        &put_in(&1, ["choices", "identity_choice"], "keep_target_isin")
      )

    {:ok, view, _html} = live(conn, "/portfolios")

    assert isin_line(view, neither) == nil
    assert isin_line(view, older) == nil
    assert isin_line(view, target_only) == nil
    assert isin_line(view, source_only) == "XS0000000017 adopted from the source"
    assert isin_line(view, both) == "XS0000000033 stays; XS0000000025 is now a former ISIN"
    # The adopt sentence carries the ISIN change's date (its format is U3's).
    assert isin_line(view, adopted) =~
             ~r/^XS0000000041 adopted; DE0000000017 is now a former ISIN · change dated \S+$/

    assert get_in(neither.manifest, ["choices", "identity_choice"]) == nil
  end

  # User story (#1067; board 07.5; the PR γ closing act's coverage pass):
  # As the operator reading back a merge record an older build, an agent or
  # a hand-written row left in a shape the screen did not write,
  # I want the ISIN line to stay honest about what the record holds,
  # so that a blank ISIN, a missing choice or an unreadable date never
  # prints an empty slot or a crash.
  #
  # Acceptance criteria:
  # - A blank ISIN is no ISIN: a record whose target ISIN is spaces reads as
  #   the source's alone, "<ISIN> adopted from the source".
  # - Two ISINs and no recorded choice: no line, because the record does not
  #   say which one stayed.
  # - An ISIN change's date the record does not hold as a date is said as
  #   stored, never dropped and never reformatted.
  test "the ISIN line reads a blank ISIN, a missing choice and an unreadable date",
       %{conn: conn} do
    agent = Actor.api_token_rw("synthetic")

    adopted =
      merge!(
        agent,
        create_security!(name: "Saltmarsh Logistik SE", ticker: nil, isin: "XS0000000058"),
        create_security!(name: "Saltmarsh Logistik SE", ticker: nil, isin: "DE0000000025"),
        "adopt_source_isin"
      )

    blank_target =
      record_like!(adopted, 900_001, fn manifest ->
        manifest
        |> put_in(["identifiers", "target_isin"], "  ")
        |> put_in(["choices", "identity_choice"], "keep_target_isin")
      end)

    no_choice =
      record_like!(
        adopted,
        900_002,
        &update_in(&1, ["choices"], fn choices -> Map.delete(choices, "identity_choice") end)
      )

    unreadable_date =
      record_like!(
        adopted,
        900_003,
        &put_in(&1, ["identifier_aliases", "created", "changed_on"], "nicht datiert")
      )

    {:ok, view, _html} = live(conn, "/portfolios")

    assert isin_line(view, blank_target) == "XS0000000058 adopted from the source"
    assert isin_line(view, no_choice) == nil

    assert isin_line(view, unreadable_date) ==
             "XS0000000058 adopted; DE0000000025 is now a former ISIN · change dated nicht datiert"
  end

  # User story (#1167):
  # As the operator reading back a merge whose kept security took the
  # duplicate's ISIN,
  # I want that ISIN named once, on its own line,
  # so that the master data line does not count it a second time.
  #
  # Acceptance criteria:
  # - An ISIN only the source carried is named on the ISIN line alone; the
  #   master data line counts the other fields adopted: the ISIN and a
  #   ticker adopted read "1 field adopted, the target had none", the ISIN
  #   alone leaves no master data line.
  # - With an ISIN on both sides none is adopted, and a ticker adopted still
  #   reads "1 field adopted, the target had none".
  # - It is a read: the stored record keeps its shape, its
  #   identifiers.adopted listing the ISIN as before.
  test "the master data line counts an ISIN adopted from the source no second time",
       %{conn: conn} do
    agent = Actor.api_token_rw("synthetic")

    with_ticker =
      merge!(
        agent,
        create_security!(name: "Heronsgate Shipping AG", ticker: "HRS", isin: "XS0000000066"),
        create_security!(name: "Heronsgate Shipping AG", ticker: nil)
      )

    isin_alone =
      merge!(
        agent,
        create_security!(name: "Marlpit Ceramics SE", ticker: nil, isin: "XS0000000074"),
        create_security!(name: "Marlpit Ceramics SE", ticker: nil)
      )

    both =
      merge!(
        agent,
        create_security!(name: "Quillon Data AG", ticker: "QDA", isin: "XS0000000082"),
        create_security!(name: "Quillon Data AG", ticker: nil, isin: "XS0000000090")
      )

    {:ok, view, _html} = live(conn, "/portfolios")

    assert record_line(view, with_ticker, "ISIN") == "XS0000000066 adopted from the source"
    assert record_line(view, with_ticker, "Master data") == "1 field adopted, the target had none"
    assert record_line(view, isin_alone, "ISIN") == "XS0000000074 adopted from the source"
    assert record_line(view, isin_alone, "Master data") == nil
    assert record_line(view, both, "Master data") == "1 field adopted, the target had none"

    assert Enum.map(with_ticker.manifest["identifiers"]["adopted"], & &1["field"]) ==
             ["isin", "ticker_symbol"]
  end

  # A record in `record`'s shape for another source row, its manifest
  # changed by `change` — the shape a row the screen did not write can have.
  defp record_like!(record, source_id, change) do
    {:ok, like} =
      Lifecycle.record_merge(Actor.api_token_rw("synthetic"), %{
        kind: :security,
        source_id: source_id,
        target_id: record.target_id,
        source_snapshot: record.source_snapshot,
        manifest: change.(record.manifest),
        plan_digest: record.plan_digest
      })

    like
  end

  defp merge!(actor, source, target, choice \\ "keep_target_isin") do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_security(actor, source.id, target.id, %{
        plan_digest: preview.plan_digest,
        identity_choice: choice
      })

    record
  end

  defp isin_line(view, record), do: record_line(view, record, "ISIN")

  # The value of a merge record's line by its label, or nil without one.
  defp record_line(view, record, label) do
    view
    |> element("#merge-records tr[data-merge='#{record.id}'] .merge-manifest__counts")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("dt, dd")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
    |> Enum.chunk_every(2)
    |> Enum.find_value(fn
      [^label, value] -> value
      _line -> nil
    end)
  end

  defp ask_delete(view, tx) do
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-delete-#{tx.id}") |> render_click()
  end

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.replace(~r/\s+/, " ")

  defp squish(html), do: html |> text() |> String.trim()
end
