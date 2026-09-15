defmodule PortfolixirWeb.TaxLiveTest do
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Tax

  # User story (2026-07-25, ADR-0031, story 19.6):
  # As a local portfolio maintainer,
  # I want to enter and review the snapshots in the app,
  # so that recording a new statement is a two-minute job once a year.
  #
  # Acceptance criteria:
  # - The pots render with the statement's printed sign so the row is visually
  #   comparable to the paper, while storage stays magnitudes.
  # - The trim budget is stated with its as-of date and marked stale once newer
  #   investment income can have landed.
  # - Consistency advisories are shown as fact plus remedy, terse and
  #   impersonal, with domain terms behind an ⓘ tooltip.

  defp record!(overrides) do
    attrs =
      Map.merge(
        %{
          institution: "Example Bank",
          holder: "Owner",
          tax_year: 2025,
          as_of: ~D[2025-12-31],
          taxable_income: Decimal.new("12000.00"),
          allowance_granted: Decimal.new("1000.00"),
          allowance_used: Decimal.new("1000.00"),
          loss_pot_equities: Decimal.new("2500.00"),
          withholding_tax_credited: Decimal.new("200.00"),
          capital_gains_tax_withheld: Decimal.new("2550.00"),
          solidarity_surcharge_withheld: Decimal.new("140.25")
        },
        overrides
      )

    {:ok, snapshot} = Tax.create_snapshot(Actor.owner_ui(), attrs, today: ~D[2026-01-15])
    snapshot
  end

  test "records a statement and reads the trim budget off it", %{conn: conn} do
    {:ok, live, html} = live(conn, "/tax?holder=Owner&year=2025")

    assert html =~ "No statement recorded for this year."

    html =
      live
      |> form("#tax-statement-form", %{
        "statement" => %{
          "institution" => "Example Bank",
          "as_of" => "2025-12-31",
          "taxable_income" => "12000.00",
          "allowance_granted" => "1000.00",
          "allowance_used" => "1000.00",
          "loss_pot_equities" => "2500.00",
          "withholding_tax_credited" => "200.00",
          "capital_gains_tax_withheld" => "2550.00",
          "solidarity_surcharge_withheld" => "140.25"
        }
      })
      |> render_submit()

    assert html =~ "Example Bank"
    assert html =~ "as of"

    [stored] = Tax.list_snapshots(holder: "Owner", tax_year: 2025)
    # Storage stays magnitudes even though the surface prints the sign.
    assert Decimal.equal?(stored.loss_pot_equities, Decimal.new("2500.00"))
    assert Decimal.equal?(stored.taxable_income, Decimal.new("12000.00"))
  end

  test "an empty money field is recorded as zero, not as a cast error", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/tax?holder=Owner&year=2025")

    live
    |> form("#tax-statement-form", %{
      "statement" => %{
        "institution" => "Example Bank",
        "as_of" => "2025-12-31",
        "loss_pot_equities" => "1000.00",
        "taxable_income" => ""
      }
    })
    |> render_submit()

    [stored] = Tax.list_snapshots(holder: "Owner", tax_year: 2025)
    assert Decimal.equal?(stored.taxable_income, Decimal.new("0"))
  end

  test "the pots render with the statement's printed sign", %{conn: conn} do
    record!(%{})

    {:ok, _live, html} = live(conn, "/tax?holder=Owner&year=2025")

    # Loss pots print negative on the paper; the taxable income does not.
    assert html =~ "-2.500,00" or html =~ "-2,500.00"
    refute html =~ "-12.000,00"
    refute html =~ "-12,000.00"
  end

  test "the trim budget carries its as-of date and a stale marker", %{conn: conn} do
    record!(%{})

    {:ok, _live, html} = live(conn, "/tax?holder=Owner&year=2025")

    assert html =~ "as of"
    assert html =~ "31.12.2025" or html =~ "2025-12-31"
    # The as-of lies far in the past (over the age threshold) for any real
    # "today", so the figure is stale.
    assert html =~ "Stale"
  end

  # User story (issue #667):
  # As a local portfolio maintainer reading the tax page,
  # I want the staleness warning to be a function of activity, not only of
  # the calendar,
  # so that a fresh statement is not permanently flagged as noise while a
  # statement invalidated by yesterday's dividend is flagged immediately.
  #
  # Acceptance criteria:
  # - A recent statement (within the age threshold) with no tax-relevant
  #   bookings since its as_of shows no staleness warning.
  # - The same statement with a tax-relevant booking after its as_of shows
  #   the warning naming the bookings.
  test "the staleness warning reacts to activity, not the mere passage of a day", %{conn: conn} do
    today = Date.utc_today()
    as_of = Date.add(today, -5)

    {:ok, _} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        %{
          institution: "Example Bank",
          holder: "Owner",
          tax_year: today.year,
          as_of: as_of,
          allowance_granted: Decimal.new("1000.00"),
          allowance_used: Decimal.new("200.00"),
          loss_pot_equities: Decimal.new("2500.00")
        },
        today: today
      )

    scope = "/tax?holder=Owner&year=#{today.year}"
    {:ok, live, html} = live(conn, scope)

    refute html =~ "Stale"

    # A tax-relevant booking lands after the statement's as_of.
    {:ok, portfolio} =
      Portfolixir.Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Tax LV",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolixir.Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Tax LV Cash",
        currency_code: "EUR"
      })

    {:ok, _} =
      Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "interest",
        date: Date.add(today, -2),
        gross_amount: "10.00",
        currency_code: "EUR"
      })

    # The same scope re-read after the booking (the segmented control
    # patches the URL; a patch to the current scope reloads it).
    html = render_patch(live, scope)

    assert html =~ "Stale"
    assert html =~ "tax-relevant booking"
  end

  test "a mis-transcribed figure surfaces as fact plus remedy, not a rejection", %{conn: conn} do
    record!(%{
      capital_gains_tax_withheld: Decimal.new("5250.00"),
      solidarity_surcharge_withheld: Decimal.new("288.75")
    })

    {:ok, _live, html} = live(conn, "/tax?holder=Owner&year=2025")

    assert html =~ "reconstructed from the statement"
    assert html =~ "Re-check the figure against the statement."
    # Impersonal: the advisory states the fact, it does not address the reader.
    refute html =~ "you "
  end

  test "an incomplete roll-up says which institution it is missing", %{conn: conn} do
    record!(%{})

    {:ok, _order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Other Bank",
        tax_year: 2025,
        amount_granted: Decimal.new("500.00")
      })

    {:ok, _live, html} = live(conn, "/tax?holder=Owner&year=2025")

    assert html =~ "Incomplete"
    assert html =~ "Other Bank"
  end

  test "the recorded-not-derived explanation sits behind a disclosure, not in the sightline", %{
    conn: conn
  } do
    {:ok, _live, html} = live(conn, "/tax")

    assert html =~ "ⓘ"
    assert html =~ "<details"
    assert html =~ "FIFO"
    assert html =~ "not tax advice"
  end

  test "a hard rule blocks the save and says which figure contradicts which", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/tax?holder=Owner&year=2025")

    html =
      live
      |> form("#tax-statement-form", %{
        "statement" => %{
          "institution" => "Example Bank",
          "as_of" => "2025-12-31",
          "allowance_granted" => "1000.00",
          "allowance_used" => "1200.00"
        }
      })
      |> render_submit()

    assert html =~ "must not exceed the granted allowance"
    assert Tax.list_snapshots(holder: "Owner", tax_year: 2025) == []
  end

  test "a negative input is rejected with the magnitude convention", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/tax?holder=Owner&year=2025")

    html =
      live
      |> form("#tax-statement-form", %{
        "statement" => %{
          "institution" => "Example Bank",
          "as_of" => "2025-12-31",
          "loss_pot_equities" => "-2500.00"
        }
      })
      |> render_submit()

    assert html =~ "without its sign"
  end

  test "a recorded statement can be corrected and deleted", %{conn: conn} do
    snapshot = record!(%{})

    {:ok, live, _html} = live(conn, "/tax?holder=Owner&year=2025")

    live |> element("button.row-actions__kebab") |> render_click()
    live |> element(~s([role="menu"] button[phx-click=edit_statement])) |> render_click()

    live
    |> form("#tax-statement-form", %{
      "statement" => %{
        "institution" => "Example Bank",
        "as_of" => "2025-12-31",
        "loss_pot_equities" => "3000.00",
        "note" => "page 4"
      }
    })
    |> render_submit()

    {:ok, corrected} = Tax.fetch_snapshot(snapshot.id)
    assert Decimal.equal?(corrected.loss_pot_equities, Decimal.new("3000.00"))
    assert corrected.note == "page 4"

    live |> element("button.row-actions__kebab") |> render_click()
    live |> element(~s([role="menu"] button[phx-click=delete_statement])) |> render_click()
    assert Tax.list_snapshots(holder: "Owner", tax_year: 2025) == []
  end

  test "a configured Freistellungsauftrag can be recorded and removed", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/tax?holder=Owner&year=2025")

    html =
      live
      |> form("#tax-order-form", %{
        "order" => %{"institution" => "Example Bank", "amount_granted" => "1000.00"}
      })
      |> render_submit()

    assert html =~ "Example Bank"
    assert [order] = Tax.list_allowance_orders(holder: "Owner", tax_year: 2025)
    assert Decimal.equal?(order.amount_granted, Decimal.new("1000.00"))

    live |> element(~s(button.row-actions__kebab[phx-value-kind="order"])) |> render_click()
    live |> element(~s([role="menu"] button[phx-click=delete_allowance_order])) |> render_click()
    assert Tax.list_allowance_orders(holder: "Owner", tax_year: 2025) == []
  end

  test "the remaining advisories render with their own fact and remedy", %{conn: conn} do
    {:ok, _profile} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2024-01-01],
        church_tax_liable: true,
        church_tax_rate: Decimal.new("0.09")
      })

    # An earlier statement of the same year, so the later one can fall below it.
    record!(%{
      as_of: ~D[2025-06-30],
      capital_gains_tax_withheld: Decimal.new("2493.89"),
      solidarity_surcharge_withheld: Decimal.new("137.16"),
      church_tax_withheld: Decimal.new("224.45")
    })

    record!(%{
      as_of: ~D[2025-12-31],
      capital_gains_tax_withheld: Decimal.new("1000.00"),
      solidarity_surcharge_withheld: Decimal.new("55.00"),
      church_tax_withheld: Decimal.new("500.00")
    })

    for institution <- ["Bank X", "Bank Y"] do
      {:ok, _} =
        Tax.put_allowance_order(Actor.owner_ui(), %{
          holder: "Owner",
          institution: institution,
          tax_year: 2025,
          amount_granted: Decimal.new("800.00")
        })
    end

    {:ok, _live, html} = live(conn, "/tax?holder=Owner&year=2025")

    # C5 church tax, C6 monotonicity, C8 allowance budget across institutions.
    assert html =~ "church-tax rate of the profile in force"
    assert html =~ "Year-to-date figures do not fall"
    assert html =~ "Redistribute the orders with the banks."
  end

  test "an instance with no recorded statement still renders its empty state", %{conn: conn} do
    {:ok, _live, html} = live(conn, "/tax")

    assert html =~ "No statement recorded for this year."
    assert html =~ "No statement recorded for this taxpayer and year."
  end

  # User story (#795):
  # As a local portfolio maintainer reading the Tax page,
  # I want the budget as a fill level with its composition beside it, the
  # recorded statements as a list whose findings are data notes with the
  # check control inside, and the entry forms behind a disclosure,
  # so that the page answers "how much can be sold tax-free" first and asks
  # for input only on demand.
  #
  # Acceptance criteria:
  # - Taxpayer and year are segmented controls; the budget renders as a
  #   meter (track, fill, remaining amount, as-of basis line, no threshold
  #   colouring) with the composition beside it and its ⓘ.
  # - The staleness state is a data note with the "Record a new statement"
  #   control inside; the incomplete roll-up is a data note.
  # - Statements are a list; each finding is a data note at attention
  #   severity with the check control inside; "Correct" and "Delete" live in
  #   the row menu, never as standing buttons.
  # - Both forms are closed disclosures; the orders list sits behind a
  #   disclosure carrying its purpose line; no free-standing paragraph
  #   remains.

  defp doc(html), do: Floki.parse_document!(html)

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  test "the budget is a meter with its composition beside it and the scope is segmented", %{
    conn: conn
  } do
    record!(%{allowance_used: Decimal.new("640.00")})
    record!(%{holder: "Partner", tax_year: 2024, as_of: ~D[2024-12-31]})

    {:ok, live, html} = live(conn, "/tax?holder=Owner&year=2025")
    doc = doc(html)

    # Segmented scope: the holders and the years, the selected one current.
    assert text(Floki.find(doc, ~s([data-role="tax-holders"] a[aria-current="true"]))) == "Owner"
    assert "Partner" in Enum.map(Floki.find(doc, ~s([data-role="tax-holders"] a)), &text([&1]))
    assert text(Floki.find(doc, ~s([data-role="tax-years"] a[aria-current="true"]))) == "2025"
    refute Floki.find(doc, "#tax-scope-form") != []

    # The meter: 640 of 1.000 used, the remaining 2.860 (2.500 + 360) as the value.
    meter = Floki.find(doc, ~s([data-role="budget-meter"]))
    assert [fill] = Floki.find(meter, ".budget-meter__fill")
    assert Floki.attribute(fill, "style") == ["width: 64%"]
    assert text(Floki.find(meter, ~s([data-role="budget-value"]))) =~ "2,860.00"
    basis = text(Floki.find(meter, ~s([data-role="budget-basis"])))
    assert basis =~ "640.00"
    assert basis =~ "1,000.00"
    assert basis =~ "2025-12-31"
    assert basis =~ "Example Bank"

    # The composition beside it, with the recorded-not-derived ⓘ.
    composition = Floki.find(doc, ~s([data-role="budget-composition"]))
    assert text(composition) =~ "Loss pot, equities"
    assert text(composition) =~ "Remaining allowance"
    assert text(composition) =~ "360.00"
    assert [_] = Floki.find(composition, "details")
    assert text(composition) =~ "not tax advice"

    # No free-standing paragraph remains.
    assert Floki.find(doc, ".workspace-page p.muted") == []

    # Switching the taxpayer patches the scope.
    live |> element(~s([data-role="tax-holders"] a), "Partner") |> render_click()
    assert_patch(live, "/tax?holder=Partner&year=2025")
    assert render(live) =~ "No statement recorded for this year."
  end

  test "the stale state and the incomplete roll-up are data notes with the remedy inside", %{
    conn: conn
  } do
    record!(%{})

    {:ok, _} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Other Bank",
        tax_year: 2025,
        amount_granted: "500.00"
      })

    {:ok, live, html} = live(conn, "/tax?holder=Owner&year=2025")
    doc = doc(html)

    stale = Floki.find(doc, ~s([data-role="budget-stale"]))
    assert [_] = Floki.find(doc, ~s([data-role="budget-stale"].data-note--attention))
    assert text(stale) =~ "Stale"
    assert [_] = Floki.find(stale, "button[phx-click=open_statement_form]")
    assert [_] = Floki.find(doc, ~s([data-role="budget-incomplete"].data-note--attention))
    assert text(Floki.find(doc, ~s([data-role="budget-incomplete"]))) =~ "Other Bank"
    refute Floki.find(doc, ".alert-warning") != []
    refute Floki.find(doc, ".badge-warning") != []

    # The control inside the note opens the closed statement form.
    assert [_] = Floki.find(doc, "#tax-statement-panel[hidden]")

    live
    |> element(~s([data-role="budget-stale"] button[phx-click=open_statement_form]))
    |> render_click()

    assert Floki.find(doc(render(live)), "#tax-statement-panel[hidden]") == []
  end

  test "a finding is a data note with the check control inside; correct and delete sit in the row menu",
       %{
         conn: conn
       } do
    record!(%{capital_gains_tax_withheld: Decimal.new("2000.00")})

    {:ok, live, html} = live(conn, "/tax?holder=Owner&year=2025")
    doc = doc(html)

    findings = Floki.find(doc, ~s([data-role="statement-finding"]))
    assert findings != []

    assert length(Floki.find(doc, ~s([data-role="statement-finding"].data-note--attention))) ==
             length(findings)

    assert text(findings) =~ "reconstructed from the statement"
    assert Enum.all?(findings, &(Floki.find(&1, "button[phx-click]") != []))
    assert Floki.find(doc, ".tax-findings") == []

    # No standing Correct / Delete buttons on the row; the kebab opens the menu.
    assert Floki.find(doc, ~s(.tax-statement > * > button[phx-click=delete_statement])) == []
    assert Floki.find(doc, ~s([role="menu"])) == []
    live |> element("button.row-actions__kebab") |> render_click()
    menu = Floki.find(doc(render(live)), ~s([role="menu"]))
    assert text(menu) =~ "Correct"
    assert text(menu) =~ "Delete"
    assert [_] = Floki.find(menu, "button[phx-click=delete_statement][data-confirm]")
  end

  test "both forms are closed disclosures and the orders sit behind one with their purpose", %{
    conn: conn
  } do
    record!(%{})

    {:ok, _} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Example Bank",
        tax_year: 2025,
        amount_granted: "1000.00"
      })

    {:ok, live, html} = live(conn, "/tax?holder=Owner&year=2025")
    doc = doc(html)

    assert [_] = Floki.find(doc, "#tax-statement-panel[hidden]")
    assert [_] = Floki.find(doc, "#tax-order-panel[hidden]")
    assert [toggle] = Floki.find(doc, ~s(button[aria-controls="tax-statement-panel"]))
    assert Floki.attribute(toggle, "aria-expanded") == ["false"]

    live |> element(~s(button[aria-controls="tax-statement-panel"])) |> render_click()
    opened = doc(render(live))
    assert Floki.find(opened, "#tax-statement-panel[hidden]") == []

    assert [_] =
             Floki.find(
               opened,
               ~s(button[aria-controls="tax-statement-panel"][aria-expanded="true"])
             )

    # The sign convention is field help on the amounts, not a paragraph.
    assert [_] = Floki.find(opened, "#tax-amount-help")
    assert [_ | _] = Floki.find(opened, ~s(input[aria-describedby~="tax-amount-help"]))
    refute html =~ "Enter every amount without its sign."

    orders = Floki.find(doc, ~s(details[data-role="orders"]))
    assert text(orders) =~ "Example Bank"
    assert text(orders) =~ "What was instructed per institution"
  end
end
