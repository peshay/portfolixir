defmodule PortfolixirWeb.ImportsUnseenNameLiveTest do
  # ADR-0050 §2's first limit and its amendment of 2026-10-07 on the Imports
  # page (#904; risk-tier: import idempotency, ADR-0036), as the Sprint 20
  # board `ux-design-2026-10-07/01-import-preview` ① draws it (pick L1 = A):
  # a cash-account or depot name with no hash hit, in a file whose other
  # names have hits, gets no prefill — whatever resolution would have
  # prefilled — and Apply waits for a choice. The identities P1 to P5 are
  # pinned here, one test each; the signal itself in
  # `Portfolixir.Imports.UnseenNameProbeTest`. The amendment of 2026-10-09
  # (#1195) lets the dry run's answer release a name whose rows are all
  # booked on its resolution; P6 to P10 pin that end to end. The page's
  # dry run runs in the background, and P7 and P10 read the page before it
  # answers through the seam `hold_refine!/0` opens.
  #
  # The board's world: Test-Cash, Tagesgeld and Depot Muster, imported from
  # Portfolio Performance; then "Tagesgeld" is renamed "Tagesgeld Extra" (or
  # the depot "Depot Muster Neu") in Portfolio Performance and exported
  # again. Every name, amount and identifier is synthetic.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  @cash_note "No booking under this name has been imported yet, though the file's other names have. If the account was renamed in Portfolio Performance, choose the existing account here; otherwise “+ Create new”."
  @depot_note "No booking under this name has been imported yet, though the file's other names have. If the depot was renamed in Portfolio Performance, choose the existing depot here; otherwise “+ Create new”."

  # User story:
  # As the operator who renamed an account in Portfolio Performance and
  # dropped its export again,
  # I want the renamed row to wait for my choice instead of prefilling a new
  # account, and the import to book nothing once I pick the account it was
  # renamed from,
  # so that one confirm never books that account's whole history a second
  # time.
  #
  # Acceptance criteria (P1; amendment points 2 and 3):
  # - "Tagesgeld Extra" (its rows a transfer from Test-Cash and two interest
  #   payments) is not prefilled: its select reads "Decide…", where today's
  #   prefill reads "+ Create new: Tagesgeld Extra". Test-Cash and Depot
  #   Muster keep today's prefill.
  # - Its row's attention note says no booking under this name is known and
  #   names both remedies; Confirm is disabled and described by the
  #   still-to-map hint naming the account; a submit of the undecided row is
  #   refused and writes nothing.
  # - Mapped onto Tagesgeld, the "remember" box appears, ticked, the note
  #   stays, and Confirm inserts nothing — zero transactions, cash accounts,
  #   depots and securities — and "Tagesgeld Extra" becomes a former name of
  #   Tagesgeld.
  test "P1: a renamed cash account waits for a choice, and its old account books nothing",
       %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    tagesgeld = named!(CashAccount, "Tagesgeld")
    drop = history(savings: "Tagesgeld Extra")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    today = today_prefill(drop, portfolio)
    assert today["cash"]["Tagesgeld Extra"] == "create:Tagesgeld Extra"

    assert selected(view, "cash", "Tagesgeld Extra") == ""
    assert selected(view, "cash", "Test-Cash") == today["cash"]["Test-Cash"]
    assert selected(view, "depot", "Depot Muster") == today["depot"]["Depot Muster"]

    assert note(view, "cash", "Tagesgeld Extra") == @cash_note
    refute has_element?(view, row("cash", "Test-Cash") <> " [data-role='mapping-unseen-name']")

    refute has_element?(
             view,
             row("depot", "Depot Muster") <> " [data-role='mapping-unseen-name']"
           )

    assert has_element?(
             view,
             "#pp-import-confirm[disabled][aria-describedby='import-missing-hint']"
           )

    assert view |> element("#import-missing-hint") |> render() =~ "cash account: Tagesgeld Extra"

    before = counts()
    view |> element("form#pp-import-apply") |> render_submit()
    assert render(view) =~ "Pick a target for cash account Tagesgeld Extra."
    assert counts() == before

    form = element(view, "form#pp-import-apply")
    render_change(form, keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{tagesgeld.id}"}}))

    assert note(view, "cash", "Tagesgeld Extra") == @cash_note

    assert view
           |> element(row("cash", "Tagesgeld Extra") <> " [data-role='mapping-remember']")
           |> render() =~
             "“Tagesgeld Extra” becomes a former name of Tagesgeld; once a booking under the name has been imported, a future import maps the name by itself."

    assert has_element?(
             view,
             ~s(#{row("cash", "Tagesgeld Extra")} input[type="checkbox"][name="remember[cash][#{row_key("cash", "Tagesgeld Extra")}]"][checked])
           )

    refute has_element?(view, "#pp-import-confirm[disabled]")
    refute has_element?(view, "#import-missing-hint")

    view |> element("form#pp-import-apply") |> render_submit()
    assert render_async(view, 1_000) =~ "Created transactions: 0"

    assert counts() == before
    assert Repo.get!(CashAccount, tagesgeld.id).former_names == ["Tagesgeld Extra"]
  end

  # User story:
  # As the operator whose renamed account's new name is already the name of
  # another of my accounts,
  # I want that row to wait for my choice as well,
  # so that the history does not land on that other account a second time
  # (ADR-0050 §2: the prefill "looks legitimate, and the history would land
  # there a second time").
  #
  # Acceptance criteria (P1's variant onto a live name; board 01 ①, "Settled
  # by the amendment, not only for :none"):
  # - "Tagesgeld Extra" is the live name of an empty account. Today's prefill
  #   names that account; the probe withholds it, and the row carries the
  #   note.
  # - Mapped onto Tagesgeld, the import inserts nothing and nothing lands on
  #   the other account; the name is not remembered, because it is the other
  #   account's live name, and the row says so.
  test "P1 onto a live name: a name another account carries waits as well", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    tagesgeld = named!(CashAccount, "Tagesgeld")
    other = cash!(portfolio, "Tagesgeld Extra")
    drop = history(savings: "Tagesgeld Extra")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    assert today_prefill(drop, portfolio)["cash"]["Tagesgeld Extra"] == "existing:#{other.id}"
    assert selected(view, "cash", "Tagesgeld Extra") == ""
    assert note(view, "cash", "Tagesgeld Extra") == @cash_note

    assert has_element?(
             view,
             "#pp-import-confirm[disabled][aria-describedby='import-missing-hint']"
           )

    form = element(view, "form#pp-import-apply")
    render_change(form, keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{tagesgeld.id}"}}))

    assert has_element?(
             view,
             row("cash", "Tagesgeld Extra") <> " [data-role='mapping-not-remembered']"
           )

    before = counts()
    view |> element("form#pp-import-apply") |> render_submit()
    assert render_async(view, 1_000) =~ "Created transactions: 0"

    assert counts() == before
    assert Ledger.list_transactions() |> Enum.filter(&(&1.cash_account_id == other.id)) == []
    assert Repo.get!(CashAccount, tagesgeld.id).former_names == []
  end

  # User story:
  # As the operator whose renamed account's new name is a former name of
  # another of my accounts,
  # I want that row to wait for my choice, without a line claiming it was
  # matched,
  # so that the prefill never routes the history onto that account.
  #
  # Acceptance criteria (P1's variant onto a former name):
  # - "Tagesgeld Extra" is a former name of "Festgeld". Today's prefill names
  #   Festgeld through it; the probe withholds it, and the row carries the
  #   note and no "matched by a former name" line, chosen or not.
  test "P1 onto a former name: a name another account remembers waits as well", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())

    {:ok, festgeld} =
      Portfolios.update_cash_account(Actor.owner_ui(), cash!(portfolio, "Tagesgeld Extra"), %{
        name: "Festgeld"
      })

    drop = history(savings: "Tagesgeld Extra")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    assert today_prefill(drop, portfolio)["cash"]["Tagesgeld Extra"] == "existing:#{festgeld.id}"
    assert selected(view, "cash", "Tagesgeld Extra") == ""
    assert note(view, "cash", "Tagesgeld Extra") == @cash_note
    refute has_element?(view, row("cash", "Tagesgeld Extra") <> " [data-role='mapping-basis']")

    form = element(view, "form#pp-import-apply")
    render_change(form, keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{festgeld.id}"}}))

    refute has_element?(view, row("cash", "Tagesgeld Extra") <> " [data-role='mapping-basis']")
    assert note(view, "cash", "Tagesgeld Extra") == @cash_note
    refute has_element?(view, "#pp-import-confirm[disabled]")
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P8):
  # As the operator who re-drops a drifted export of an account nobody
  # renamed, or an account renamed in Portfolixir and in Portfolio
  # Performance alike,
  # I want the row prefilled once the dry run finds every booking under the
  # name already booked on the account it leads to,
  # so that a drop that books nothing stops asking.
  #
  # Acceptance criteria (amendment points 1 and 2):
  # - The purchase re-exported at 10:30: once the dry run answers, "Depot
  #   Muster" reads "1 booking already imported · nothing to create", carries
  #   Depot Muster as its choice, has no note, and Confirm needs no choice.
  # - "Tagesgeld" renamed "Tagesgeld Extra" on both sides: the row reads "3
  #   bookings already imported · nothing to create" and carries the renamed
  #   account, with no note and no still-to-map hint.
  test "P8: a drifted depot and a name renamed in both programs are prefilled once the dry run answers",
       %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    depot = named!(SecuritiesAccount, "Depot Muster")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, history(time: "10:30"))

    assert count_text(view, "depot", "Depot Muster") ==
             "1 booking already imported · nothing to create"

    assert selected(view, "depot", "Depot Muster") == "existing:#{depot.id}"
    assert unseen_notes(view) == []
    refute has_element?(view, "#pp-import-confirm[disabled]")
    refute has_element?(view, "#import-missing-hint")

    {:ok, renamed} =
      Portfolios.update_cash_account(Actor.owner_ui(), named!(CashAccount, "Tagesgeld"), %{
        name: "Tagesgeld Extra"
      })

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, history(savings: "Tagesgeld Extra"))

    assert count_text(view, "cash", "Tagesgeld Extra") ==
             "3 bookings already imported · nothing to create"

    assert selected(view, "cash", "Tagesgeld Extra") == "existing:#{renamed.id}"
    assert unseen_notes(view) == []
    refute has_element?(view, "#pp-import-confirm[disabled]")
    refute has_element?(view, "#import-missing-hint")
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P6):
  # As the operator who re-drops a file whose names the stored history
  # holds under another hash, or under a name I mapped and remembered,
  # I want the drop to ask nothing once the dry run answers, and again
  # nothing on the next drop,
  # so that a question I would answer without reading is never asked.
  #
  # Acceptance criteria (each of the issue's three re-drops, dropped twice):
  # - once the dry run answers, no row carries the unseen-name note, no
  #   still-to-map hint shows, and Confirm is enabled;
  # - each apply inserts nothing: zero transactions, cash accounts, depots
  #   and securities.
  for {case_name, world} <- [
        {"the purchase re-exported at 10:30", :drifted},
        {"P1's file again after its name was mapped and remembered", :remembered},
        {"an account renamed in Portfolixir and in Portfolio Performance alike", :both}
      ] do
    @tag world: world
    test "P6: the issue's three re-drops ask nothing once the dry run answers, twice — #{case_name}",
         %{conn: conn, world: world} do
      portfolio = portfolio!()
      applied!(portfolio, history())
      drop = p6_world!(world, portfolio)

      for _drop <- 1..2 do
        {:ok, view, _html} = live(conn, "/imports")
        upload!(view, drop)

        assert unseen_notes(view) == []
        refute has_element?(view, "#import-missing-hint")
        refute has_element?(view, "#pp-import-confirm[disabled]")

        before = counts()
        view |> element("form#pp-import-apply") |> render_submit()
        assert render_async(view, 1_000) =~ "Created transactions: 0"
        assert counts() == before
      end
    end
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P7):
  # As the operator who mapped a renamed name onto its old account and
  # remembered it,
  # I want a later export that brings a new booking under that name to ask
  # once more, and the same file without it to be prefilled,
  # so that a remembered name never vouches for a booking on its own.
  #
  # Acceptance criteria (amendment point 3):
  # - P1's file without a new booking: before the dry run answers,
  #   "Tagesgeld Extra" is withheld ("Decide…" and the note); once it
  #   answers, it carries Tagesgeld and no note.
  # - The later export adding 1.35 EUR of interest on 2026-03-31 reads "3
  #   bookings already imported · 1 new" and stays withheld after the answer,
  #   with the note and no "matched by a former name" line.
  # - Mapped onto Tagesgeld, it inserts exactly that one booking, on
  #   Tagesgeld; the next drop of that export knows the name by its hash: no
  #   note, nothing to create.
  test "P7: a remembered former name asks once more for a new booking, and is prefilled when every row is booked",
       %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    tagesgeld = named!(CashAccount, "Tagesgeld")
    renamed = history(savings: "Tagesgeld Extra")
    remembered!(portfolio, renamed)

    hold_refine!()
    {:ok, view, _html} = live(conn, "/imports")
    upload_unanswered!(view, renamed)

    assert selected(view, "cash", "Tagesgeld Extra") == ""
    assert note(view, "cash", "Tagesgeld Extra") == @cash_note

    release_refine!()
    render_async(view)

    assert selected(view, "cash", "Tagesgeld Extra") == "existing:#{tagesgeld.id}"
    assert unseen_notes(view) == []

    later = renamed ++ [interest("Tagesgeld Extra", "1.35", "2026-03-31")]

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, later)

    assert count_text(view, "cash", "Tagesgeld Extra") == "3 bookings already imported · 1 new"
    assert selected(view, "cash", "Tagesgeld Extra") == ""
    assert note(view, "cash", "Tagesgeld Extra") == @cash_note
    refute has_element?(view, row("cash", "Tagesgeld Extra") <> " [data-role='mapping-basis']")
    assert has_element?(view, "#pp-import-confirm[disabled]")

    form = element(view, "form#pp-import-apply")
    render_change(form, keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{tagesgeld.id}"}}))

    marker = max_transaction_id()
    view |> element("form#pp-import-apply") |> render_submit()
    assert render_async(view, 1_000) =~ "Created transactions: 1"

    assert booked_after(marker, portfolio) == [
             {"interest", ~D[2026-03-31], "1.35", "Tagesgeld", nil}
           ]

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, later)

    assert count_text(view, "cash", "Tagesgeld Extra") ==
             "4 bookings already imported · nothing to create"

    assert unseen_notes(view) == []
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P9):
  # As the operator whose renamed account carries one booking the stored
  # history lacks,
  # I want the row to keep waiting after the dry run answers,
  # so that a name whose rows would book anything is never prefilled.
  #
  # Acceptance criteria (amendment point 4):
  # - "Tagesgeld" renamed "Tagesgeld Extra" on both sides, and the export
  #   adds 1.35 EUR of interest: the row reads "3 bookings already imported
  #   · 1 new", "Decide…", the note, and Confirm waits, named in the
  #   still-to-map hint.
  test "P9: a name booked but for one new row still waits", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())

    {:ok, _renamed} =
      Portfolios.update_cash_account(Actor.owner_ui(), named!(CashAccount, "Tagesgeld"), %{
        name: "Tagesgeld Extra"
      })

    {:ok, view, _html} = live(conn, "/imports")

    upload!(
      view,
      history(savings: "Tagesgeld Extra") ++ [interest("Tagesgeld Extra", "1.35", "2026-03-31")]
    )

    assert count_text(view, "cash", "Tagesgeld Extra") == "3 bookings already imported · 1 new"
    assert selected(view, "cash", "Tagesgeld Extra") == ""
    assert note(view, "cash", "Tagesgeld Extra") == @cash_note

    assert has_element?(
             view,
             "#pp-import-confirm[disabled][aria-describedby='import-missing-hint']"
           )

    assert view |> element("#import-missing-hint") |> render() =~ "cash account: Tagesgeld Extra"
  end

  # User story (#1195, Sprint 21 α8; ADR-0050 as amended on 2026-10-09, P10):
  # As the operator reading the preview while its dry run still runs,
  # I want a withheld row to stay withheld until the dry run answers, a
  # choice I make meanwhile to stand, and a dry run that stops to release
  # nothing,
  # so that nothing is ever prefilled on a guess.
  #
  # Acceptance criteria (amendment point 2; board 07 ④, Nachher 1 and 2):
  # - P8's drop, read before the dry run answers: "Depot Muster" shows
  #   "Decide…", the note, its count dimmed with the cue "provisional ·
  #   recomputing", and Confirm disabled, named in the still-to-map hint.
  #   The answer releases it: Depot Muster, no note, no cue, Confirm
  #   enabled.
  # - "Depot Zwei" chosen for the row before the answer stays chosen.
  # - With a new deposit under "Festgeld", a name two accounts carry from
  #   before the name guard, the dry run stops: the depot's count stays on
  #   the hash layers ("1 booking new") and the row stays withheld.
  test "P10: a withheld row waits for the dry run's answer, and a choice made before it stands",
       %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    depot = named!(SecuritiesAccount, "Depot Muster")
    drifted = history(time: "10:30")

    hold_refine!()
    {:ok, view, _html} = live(conn, "/imports")
    upload_unanswered!(view, drifted)

    assert selected(view, "depot", "Depot Muster") == ""
    assert note(view, "depot", "Depot Muster") == @depot_note

    assert view
           |> element(row("depot", "Depot Muster") <> " [data-role='mapping-count']")
           |> render() =~ "provisional · recomputing"

    assert has_element?(
             view,
             "#pp-import-confirm[disabled][aria-describedby='import-missing-hint']"
           )

    assert view |> element("#import-missing-hint") |> render() =~ "target depot: Depot Muster"

    release_refine!()
    render_async(view)

    assert selected(view, "depot", "Depot Muster") == "existing:#{depot.id}"
    assert unseen_notes(view) == []
    refute render(view) =~ "provisional · recomputing"
    refute has_element?(view, "#pp-import-confirm[disabled]")

    zwei = depot!(portfolio, "Depot Zwei", named!(CashAccount, "Test-Cash"))

    hold_refine!()
    {:ok, view, _html} = live(conn, "/imports")
    upload_unanswered!(view, drifted)

    view
    |> element("form#pp-import-apply")
    |> render_change(
      keyed(%{
        "depot" => %{
          "Depot Muster" => %{"target" => "existing:#{zwei.id}", "cash" => "pp:Test-Cash"}
        }
      })
    )

    release_refine!()
    render_async(view)

    assert selected(view, "depot", "Depot Muster") == "existing:#{zwei.id}"

    legacy_cash!(portfolio, "Festgeld")
    legacy_cash!(portfolio, "Festgeld")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drifted ++ [deposit("Festgeld", "300.00", "2026-03-02")])

    assert count_text(view, "depot", "Depot Muster") == "1 booking new"
    assert selected(view, "depot", "Depot Muster") == ""
    assert note(view, "depot", "Depot Muster") == @depot_note
    assert has_element?(view, "#pp-import-confirm[disabled]")
  end

  # User story:
  # As the operator whose account really is new in an export that also
  # carries known accounts,
  # I want "+ Create new" to book exactly what the prefill booked before the
  # probe,
  # so that the probe stops the default and never a choice.
  #
  # Acceptance criteria (P2):
  # - The renamed drop with "Tagesgeld Extra" mapped to "+ Create new"
  #   inserts the same bookings — kind, date, amount, accounts — as today's
  #   prefill inserts for the same drop in a second portfolio holding the
  #   same history: three bookings on a new "Tagesgeld Extra", one cash
  #   account, no depot, no security.
  test "P2: \"+ Create new\" inserts exactly what today's prefill inserts", %{conn: conn} do
    portfolio = portfolio!()
    twin = portfolio!("Twin")
    applied!(portfolio, history())
    applied!(twin, history())
    drop = history(savings: "Tagesgeld Extra")

    # Today's prefill, applied in the twin: what the default booked before.
    marker = max_transaction_id()
    {:ok, today} = Imports.apply(parse!(drop), today_params(drop, twin))
    today_rows = booked_after(marker, twin)

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    form = element(view, "form#pp-import-apply")
    render_change(form, keyed(%{"cash" => %{"Tagesgeld Extra" => "create:Tagesgeld Extra"}}))
    refute has_element?(view, "#pp-import-confirm[disabled]")

    marker = max_transaction_id()
    securities = Catalog.count_securities()
    view |> element("form#pp-import-apply") |> render_submit()
    assert render_async(view, 1_000) =~ "Created transactions: 3"

    assert booked_after(marker, portfolio) == today_rows

    assert today_rows == [
             {"cash_transfer", ~D[2026-01-05], "500.000000", "Test-Cash", "Tagesgeld Extra"},
             {"interest", ~D[2026-01-31], "1.250000", "Tagesgeld Extra", nil},
             {"interest", ~D[2026-02-28], "1.300000", "Tagesgeld Extra", nil}
           ]

    assert today.created_transactions == 3
    assert today.created_cash_accounts == 1
    assert today.created_securities_accounts == 0
    assert today.created_securities == 0
    assert Catalog.count_securities() == securities

    assert in_portfolio(CashAccount, portfolio) |> Enum.map(& &1.name) |> Enum.sort() ==
             ["Tagesgeld", "Tagesgeld Extra", "Test-Cash"]

    assert in_portfolio(SecuritiesAccount, portfolio) |> Enum.map(& &1.name) == ["Depot Muster"]
  end

  # User story:
  # As the operator importing a file for the first time,
  # I want every row prefilled as before,
  # so that the probe costs nothing where no history can be booked twice.
  #
  # Acceptance criteria (P3):
  # - On a portfolio holding a hand-made "Test-Cash" and no imported booking,
  #   every row of the file is prefilled exactly as today's prefill does:
  #   Test-Cash onto the account of that name, the others "+ Create new".
  # - No row carries the note, and Confirm is enabled.
  test "P3: a file in which no name has a hit prefills exactly as today", %{conn: conn} do
    portfolio = portfolio!()
    cash!(portfolio, "Test-Cash")
    drop = history()

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    today = today_prefill(drop, portfolio)
    assert today["cash"]["Tagesgeld"] == "create:Tagesgeld"
    assert prefill_on_page(view, drop) == today
    refute has_element?(view, "[data-role='mapping-unseen-name']")
    refute has_element?(view, "#pp-import-confirm[disabled]")
  end

  # User story:
  # As the operator dropping a later export of accounts already imported,
  # I want every row prefilled as before, a former name included,
  # so that the probe never asks where every name is known.
  #
  # Acceptance criteria (P4):
  # - The history plus one new interest payment and one new deposit on
  #   Test-Cash, after Test-Cash was renamed "Girokonto" in Portfolixir:
  #   every name has a hit, and every row is prefilled exactly as today's
  #   prefill does, Test-Cash through its former name with that line under
  #   the select. (Since #1168 a row with no new booking shows no select, so
  #   the former-name row carries a new booking here.)
  # - No row carries the note, and Confirm is enabled.
  test "P4: a file in which every name has a hit prefills exactly as today", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())

    {:ok, _} =
      Portfolios.update_cash_account(Actor.owner_ui(), named!(CashAccount, "Test-Cash"), %{
        name: "Girokonto"
      })

    drop =
      history() ++
        [
          interest("Tagesgeld", "1.40", "2026-03-31"),
          %{
            "type" => "DEPOSIT",
            "account" => "Test-Cash",
            "date" => "2026-04-01",
            "currency" => "EUR",
            "amount" => num("100.00")
          }
        ]

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    assert prefill_on_page(view, drop) == today_prefill(drop, portfolio)
    refute has_element?(view, "[data-role='mapping-unseen-name']")

    assert view |> element(row("cash", "Test-Cash") <> " [data-role='mapping-basis']") |> render() =~
             "matched by a former name — Girokonto, formerly “Test-Cash”"

    refute has_element?(view, "#pp-import-confirm[disabled]")
  end

  # User story:
  # As the operator who renamed a depot in Portfolio Performance,
  # I want the depot's row to wait for my choice as a renamed cash account's
  # does,
  # so that its holdings are not bought a second time into a new depot.
  #
  # Acceptance criteria (P5):
  # - "Depot Muster Neu" is not prefilled; its row carries the depot's note;
  #   Confirm is disabled and the hint names the target depot.
  # - Mapped onto Depot Muster, the import inserts nothing (zero
  #   transactions, cash accounts, depots and securities) and "Depot Muster
  #   Neu" becomes a former name of Depot Muster.
  test "P5: a renamed depot waits for a choice, and its old depot books nothing", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    depot = named!(SecuritiesAccount, "Depot Muster")
    drop = history(depot: "Depot Muster Neu")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    today = today_prefill(drop, portfolio)
    assert today["depot"]["Depot Muster Neu"] == "create:Depot Muster Neu"
    assert selected(view, "depot", "Depot Muster Neu") == ""
    assert selected(view, "cash", "Test-Cash") == today["cash"]["Test-Cash"]
    assert selected(view, "cash", "Tagesgeld") == today["cash"]["Tagesgeld"]

    assert note(view, "depot", "Depot Muster Neu") == @depot_note

    assert has_element?(
             view,
             "#pp-import-confirm[disabled][aria-describedby='import-missing-hint']"
           )

    assert view |> element("#import-missing-hint") |> render() =~
             "target depot: Depot Muster Neu"

    form = element(view, "form#pp-import-apply")

    render_change(
      form,
      keyed(%{"depot" => %{"Depot Muster Neu" => %{"target" => "existing:#{depot.id}"}}})
    )

    assert has_element?(
             view,
             row("depot", "Depot Muster Neu") <> " [data-role='mapping-remember']"
           )

    refute has_element?(view, "#pp-import-confirm[disabled]")

    before = counts()
    view |> element("form#pp-import-apply") |> render_submit()
    assert render_async(view, 1_000) =~ "Created transactions: 0"

    assert counts() == before
    assert Repo.get!(SecuritiesAccount, depot.id).former_names == ["Depot Muster Neu"]
  end

  # User story (the α closing act, coverage):
  # As the operator who renamed a depot and the cash account it settles
  # through,
  # I want the still-to-map line to name both for the depot's row,
  # so that I know the depot needs a target and a cash account.
  #
  # Acceptance criteria:
  # - "Test-Cash Neu" and "Depot Muster Neu" both wait for a choice;
  #   Confirm is disabled and the hint names "depot and its cash account:
  #   Depot Muster Neu" beside "cash account: Test-Cash Neu".
  test "a renamed depot whose cash account was renamed too names both", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    drop = history(cash: "Test-Cash Neu", depot: "Depot Muster Neu")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, drop)

    assert selected(view, "depot", "Depot Muster Neu") == ""
    assert selected(view, "cash", "Test-Cash Neu") == ""
    assert has_element?(view, "#pp-import-confirm[disabled]")

    hint = view |> element("#import-missing-hint") |> render()
    assert hint =~ "cash account: Test-Cash Neu"
    assert hint =~ "depot and its cash account: Depot Muster Neu"
  end

  # User story:
  # As the operator whose renamed account's new name two of my accounts
  # carry from before the name guard,
  # I want the row to say both that the name is ambiguous and that no
  # booking under it is known,
  # so that I do not take one of the two for the account the history lives
  # on.
  #
  # Acceptance criteria (the amendment's point 2 beside ADR-0050 §4):
  # - The row is not prefilled and carries the unseen note first, directly
  #   under the select, then the ambiguous note naming the candidates.
  # - Confirm is disabled and described by the still-to-map hint.
  test "an ambiguous name unknown to the stored history carries both notes", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    legacy_cash!(portfolio, "Tagesgeld Extra")
    legacy_cash!(portfolio, "Tagesgeld Extra")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, history(savings: "Tagesgeld Extra"))

    assert selected(view, "cash", "Tagesgeld Extra") == ""
    assert note(view, "cash", "Tagesgeld Extra") == @cash_note

    roles =
      view
      |> element(row("cash", "Tagesgeld Extra") <> " .mapping-target")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find(".data-note")
      |> Enum.flat_map(&Floki.attribute(&1, "data-role"))

    assert roles == ["mapping-unseen-name", "mapping-ambiguous"]

    assert has_element?(
             view,
             "#pp-import-confirm[disabled][aria-describedby='import-missing-hint']"
           )

    assert view |> element("#import-missing-hint") |> render() =~ "cash account: Tagesgeld Extra"
  end

  # User story:
  # As the operator reading the preview in German,
  # I want the renamed row, its note and the reason the confirm waits in
  # German, as board 01 ① draws them,
  # so that I know what to choose.
  #
  # Acceptance criteria (board 01 ①, variant A):
  # - The select reads "Entscheiden…"; the note reads the board's German
  #   sentence for a cash account and for a depot.
  # - "Import bestätigen" is disabled and described by "Vor dem Import noch
  #   zuzuordnen: Verrechnungskonto: Tagesgeld Extra".
  # - Once Tagesgeld is chosen, the note stays and "Zuordnung merken" says
  #   „Tagesgeld Extra“ wird früherer Name von Tagesgeld.
  test "the row in German, as board 01 draws it", %{conn: conn} do
    portfolio = portfolio!()
    applied!(portfolio, history())
    tagesgeld = named!(CashAccount, "Tagesgeld")
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, history(savings: "Tagesgeld Extra", depot: "Depot Muster Neu"))

    assert view
           |> element(
             row("cash", "Tagesgeld Extra") <>
               " select[name='cash[#{row_key("cash", "Tagesgeld Extra")}]'] option[selected]"
           )
           |> render() =~ "Entscheiden…"

    assert note(view, "cash", "Tagesgeld Extra") ==
             "Unter diesem Namen ist noch keine Buchung importiert, unter den anderen Namen dieser Datei schon. Wurde das Konto in Portfolio Performance umbenannt, hier das bestehende Konto wählen, sonst „+ Neu anlegen“."

    assert note(view, "depot", "Depot Muster Neu") ==
             "Unter diesem Namen ist noch keine Buchung importiert, unter den anderen Namen dieser Datei schon. Wurde das Depot in Portfolio Performance umbenannt, hier das bestehende Depot wählen, sonst „+ Neu anlegen“."

    assert view
           |> element(row("cash", "Tagesgeld Extra") <> " [data-role='mapping-unseen-name']")
           |> render() =~
             "Achtung"

    assert has_element?(
             view,
             "#pp-import-confirm[disabled][aria-describedby='import-missing-hint']"
           )

    assert view |> element("#import-missing-hint") |> render() |> text() =~
             "Vor dem Import noch zuzuordnen: Verrechnungskonto: Tagesgeld Extra"

    form = element(view, "form#pp-import-apply")
    render_change(form, keyed(%{"cash" => %{"Tagesgeld Extra" => "existing:#{tagesgeld.id}"}}))

    assert has_element?(
             view,
             row("cash", "Tagesgeld Extra") <> " [data-role='mapping-unseen-name']"
           )

    assert view
           |> element(row("cash", "Tagesgeld Extra") <> " [data-role='mapping-remember']")
           |> render()
           |> text() =~
             "„Tagesgeld Extra“ wird früherer Name von Tagesgeld; sobald eine Buchung unter dem Namen importiert ist, ordnet ein künftiger Import den Namen selbst zu."
  end

  # User story:
  # As the operator reading the preview on a phone,
  # I want a mapping row's note to take the note's full width under its word,
  # so that its sentence is not squeezed into 180 px beside it.
  #
  # Acceptance criteria (board 01's rule ①, and its found-while-drawing item
  # 8 for the ambiguous row's note in the same place):
  # - Under 560 px the unseen name's note and the ambiguous name's note wrap
  #   their body under the glyph and the word, in the correction note's
  #   selector list.
  test "the row's notes wrap under 560 px (board 01, rule ①)" do
    css = File.read!("priv/static/app.css")

    [block] =
      Regex.run(
        ~r/@media \(max-width: 560px\) \{\s*#import-correction-table-wrapper.*?\n\}/s,
        css
      )

    assert block =~
             ~r/#import-correction \.data-note,\s*\[data-role="mapping-unseen-name"\],\s*\[data-role="mapping-ambiguous"\] \{\s*flex-wrap: wrap;/

    assert block =~
             ~r/#import-correction \.data-note__body,\s*\[data-role="mapping-unseen-name"\] \.data-note__body,\s*\[data-role="mapping-ambiguous"\] \.data-note__body \{\s*flex-basis: 100%;/
  end

  # --- the exports ---------------------------------------------------------------

  # The history the instance imported (board 01 ①). `names` renames any of
  # its accounts as Portfolio Performance exports it after a rename.
  defp history(names \\ []) do
    cash = Keyword.get(names, :cash, "Test-Cash")
    savings = Keyword.get(names, :savings, "Tagesgeld")
    depot = Keyword.get(names, :depot, "Depot Muster")
    time = Keyword.get(names, :time, "10:00")

    [
      %{
        "type" => "DEPOSIT",
        "account" => cash,
        "date" => "2026-01-02",
        "currency" => "EUR",
        "amount" => num("2000.00")
      },
      %{
        "type" => "CASH_TRANSFER",
        "account" => cash,
        "otherAccount" => savings,
        "date" => "2026-01-05",
        "currency" => "EUR",
        "amount" => num("500.00")
      },
      %{
        "type" => "PURCHASE",
        "account" => cash,
        "portfolio" => depot,
        "date" => "2026-01-15",
        "time" => time,
        "currency" => "EUR",
        "amount" => num("1000.00"),
        "shares" => num("10"),
        "security" => @fund
      },
      interest(savings, "1.25", "2026-01-31"),
      interest(savings, "1.30", "2026-02-28")
    ]
  end

  defp deposit(account, amount, date) do
    %{
      "type" => "DEPOSIT",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => num(amount)
    }
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

  # A JSON number written as its literal digits, never through a float.
  defp num(digits), do: Jason.Fragment.new(digits)

  defp body(rows), do: Jason.encode!(%{"version" => 1, "transactions" => rows})

  defp parse!(rows) do
    {:ok, preview} = Imports.parse_portfolio_performance(body(rows), filename: "synthetic.json")
    preview
  end

  defp applied!(portfolio, rows) do
    {:ok, _result} = Imports.apply(parse!(rows), %{portfolio_id: portfolio.id})
    :ok
  end

  # The preview's counts are refined in the background once the file is
  # parsed; the page is read after that.
  defp upload!(view, rows) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: "synthetic.json",
        content: body(rows),
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("synthetic.json")

    render_async(view)
  end

  # P10's seam (ADR-0050 as amended on 2026-10-09): the page's dry run, once
  # started on this test's behalf, waits until `release_refine!/0`, so the
  # page can be read before the dry run answers.
  defp hold_refine! do
    Application.put_env(:portfolixir, :imports_refine_gate, self())
    on_exit(fn -> Application.delete_env(:portfolixir, :imports_refine_gate) end)
  end

  defp release_refine! do
    assert_receive {:imports_refine_gate, task}, 5_000
    Application.delete_env(:portfolixir, :imports_refine_gate)
    send(task, {:imports_refine_gate, :release})
  end

  # The upload alone: the page as it reads before the dry run answers.
  defp upload_unanswered!(view, rows) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: "synthetic.json",
        content: body(rows),
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("synthetic.json")
  end

  # "Tagesgeld Extra" mapped onto Tagesgeld with "Remember this mapping"
  # on, as the page sends it: it inserts nothing and records the name.
  defp remembered!(portfolio, rows) do
    assert {:ok, %{created_transactions: 0}} =
             Imports.apply(parse!(rows), %{
               portfolio: {:existing, portfolio.id},
               cash_accounts: %{
                 "Test-Cash" => {:existing, named!(CashAccount, "Test-Cash").id},
                 "Tagesgeld Extra" => {:existing, named!(CashAccount, "Tagesgeld").id}
               },
               depots: %{
                 "Depot Muster" => %{
                   target: {:existing, named!(SecuritiesAccount, "Depot Muster").id},
                   cash: "Test-Cash"
                 }
               }
             })

    assert named!(CashAccount, "Tagesgeld").former_names == ["Tagesgeld Extra"]
  end

  # The world of each of P6's three re-drops, and the drop.
  defp p6_world!(:drifted, _portfolio), do: history(time: "10:30")

  defp p6_world!(:remembered, portfolio) do
    renamed = history(savings: "Tagesgeld Extra")
    remembered!(portfolio, renamed)
    renamed
  end

  defp p6_world!(:both, _portfolio) do
    {:ok, _renamed} =
      Portfolios.update_cash_account(Actor.owner_ui(), named!(CashAccount, "Tagesgeld"), %{
        name: "Tagesgeld Extra"
      })

    history(savings: "Tagesgeld Extra")
  end

  # --- the prefill before the probe ------------------------------------------------

  # The prefill as it stood before the probe, per row: the shared resolution
  # (ADR-0050 §4) — an exact live or a former name onto its account, a name
  # found by neither "+ Create new", an ambiguous one nothing.
  defp today_prefill(rows, portfolio) do
    %{cash_accounts: cash, depots: depots} =
      Imports.resolve_accounts(parse!(rows), portfolio_id: portfolio.id)

    %{
      "cash" => Map.new(cash, fn {name, resolution} -> {name, choice(resolution, name)} end),
      "depot" => Map.new(depots, fn {name, resolution} -> {name, choice(resolution, name)} end)
    }
  end

  defp choice({:ok, id, _tier}, _name), do: "existing:#{id}"
  defp choice(:none, name), do: "create:#{name}"
  defp choice({:ambiguous, _tier, _ids}, _name), do: ""

  # Today's prefill as the applier's mapping, bound to `portfolio`.
  defp today_params(rows, portfolio) do
    preview = parse!(rows)
    today = today_prefill(rows, portfolio)
    cash_names = Mapping.unique_cash_pp_names(preview)

    %{
      portfolio: {:existing, portfolio.id},
      cash_accounts:
        Map.new(today["cash"], fn {name, value} -> {name, applier_choice(value)} end),
      depots:
        Map.new(today["depot"], fn {name, value} ->
          default_cash = Mapping.default_cash_for_depot(preview, name)

          {name,
           %{
             target: applier_choice(value),
             cash: if(default_cash in cash_names, do: default_cash)
           }}
        end)
    }
  end

  defp applier_choice("existing:" <> id), do: {:existing, String.to_integer(id)}
  defp applier_choice("create:" <> name), do: {:create, name}

  # What the page prefilled, read off each row's select.
  defp prefill_on_page(view, rows) do
    preview = parse!(rows)

    %{
      "cash" => Map.new(Mapping.unique_cash_pp_names(preview), &{&1, selected(view, "cash", &1)}),
      "depot" =>
        Map.new(Mapping.unique_depot_pp_names(preview), &{&1, selected(view, "depot", &1)})
    }
  end

  # --- reading the page --------------------------------------------------------------

  defp row_key(kind, name), do: Mapping.row_key(kind, name)

  defp row(kind, name), do: "#mapping-#{kind}-#{row_key(kind, name)}"

  # The value of the option a row's account select shows as chosen; on a
  # row with no new booking, which shows no select since #1168 (board 01 ②),
  # the value its hidden input carries under the select's name.
  defp selected(view, "cash", name),
    do: selected_in(view, row("cash", name), "cash[#{row_key("cash", name)}]")

  defp selected(view, "depot", name),
    do: selected_in(view, row("depot", name), "depot[#{row_key("depot", name)}][target]")

  defp selected_in(view, row, field) do
    if has_element?(view, "#{row} select[name='#{field}']") do
      view
      |> element("#{row} select[name='#{field}']")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("option[selected]")
      |> Floki.attribute("value")
      |> case do
        [value] -> value
        [] -> nil
      end
    else
      view
      |> element(~s(#{row} input[type="hidden"][name="#{field}"]))
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("value")
      |> hd()
    end
  end

  # A row's count, as one line of text.
  defp count_text(view, kind, name) do
    view
    |> element(row(kind, name) <> " [data-role='mapping-count']")
    |> render()
    |> text()
  end

  # Every unseen-name note the page shows.
  defp unseen_notes(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[data-role='mapping-unseen-name']")
  end

  # The unseen name's note, its body as one line of text.
  defp note(view, kind, name) do
    view
    |> element(row(kind, name) <> " [data-role='mapping-unseen-name'] .data-note__body")
    |> render()
    |> text()
  end

  defp text(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp keyed(%{} = params) do
    params
    |> key_rows("cash")
    |> key_rows("depot")
  end

  defp key_rows(params, kind) do
    case Map.get(params, kind) do
      %{} = rows ->
        Map.put(params, kind, Map.new(rows, fn {name, v} -> {row_key(kind, name), v} end))

      _other ->
        params
    end
  end

  # --- the world -------------------------------------------------------------

  defp portfolio!(name \\ "PP Import Target") do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
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
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  # A duplicate name from before the name guard, inserted the way the old
  # writer did.
  defp legacy_cash!(portfolio, name) do
    {:ok, %{account: account}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :account,
        Ecto.Changeset.change(%CashAccount{}, %{
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        })
      )
      |> Portfolixir.Journal.record(Actor.owner_ui(),
        resource_type: "cash_account",
        operation: :create,
        source: :account
      )
      |> Repo.transaction()

    account
  end

  defp named!(schema, name), do: Repo.one!(from(a in schema, where: a.name == ^name))

  defp in_portfolio(schema, portfolio),
    do: Repo.all(from(a in schema, where: a.portfolio_id == ^portfolio.id))

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: Portfolios.count_securities_accounts(),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end

  defp max_transaction_id, do: Repo.one(from(t in Transaction, select: max(t.id))) || 0

  # The bookings `portfolio` gained after `marker`: kind, date, amount, and
  # the names of the accounts they stand on, in booking order.
  defp booked_after(marker, portfolio) do
    names = Map.new(in_portfolio(CashAccount, portfolio), &{&1.id, &1.name})

    from(t in Transaction,
      where: t.id > ^marker and t.portfolio_id == ^portfolio.id,
      order_by: [asc: t.date, asc: t.id]
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      {t.type, t.date, Decimal.to_string(t.gross_amount, :normal), names[t.cash_account_id],
       names[t.counter_cash_account_id]}
    end)
  end
end
