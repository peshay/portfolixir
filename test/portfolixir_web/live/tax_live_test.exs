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
    {:ok, live, _html} = live(conn, "/tax")

    html =
      live
      |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
      |> render_change()

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
    {:ok, live, _html} = live(conn, "/tax")

    live
    |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
    |> render_change()

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

    {:ok, live, _html} = live(conn, "/tax")

    html =
      live
      |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
      |> render_change()

    # Loss pots print negative on the paper; the taxable income does not.
    assert html =~ "-2.500,00" or html =~ "-2,500.00"
    refute html =~ "-12.000,00"
    refute html =~ "-12,000.00"
  end

  test "the trim budget carries its as-of date and a stale marker", %{conn: conn} do
    record!(%{})

    {:ok, live, _html} = live(conn, "/tax")

    html =
      live
      |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
      |> render_change()

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

    {:ok, live, _html} = live(conn, "/tax")

    html =
      live
      |> form("#tax-scope-form", %{
        "scope" => %{"holder" => "Owner", "tax_year" => Integer.to_string(today.year)}
      })
      |> render_change()

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

    html =
      live
      |> form("#tax-scope-form", %{
        "scope" => %{"holder" => "Owner", "tax_year" => Integer.to_string(today.year)}
      })
      |> render_change()

    assert html =~ "Stale"
    assert html =~ "tax-relevant booking"
  end

  test "a mis-transcribed figure surfaces as fact plus remedy, not a rejection", %{conn: conn} do
    record!(%{
      capital_gains_tax_withheld: Decimal.new("5250.00"),
      solidarity_surcharge_withheld: Decimal.new("288.75")
    })

    {:ok, live, _html} = live(conn, "/tax")

    html =
      live
      |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
      |> render_change()

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

    {:ok, live, _html} = live(conn, "/tax")

    html =
      live
      |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
      |> render_change()

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
    {:ok, live, _html} = live(conn, "/tax")

    live
    |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
    |> render_change()

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
    {:ok, live, _html} = live(conn, "/tax")

    live
    |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
    |> render_change()

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

    {:ok, live, _html} = live(conn, "/tax")

    live
    |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
    |> render_change()

    live |> element("button[phx-click=edit_statement]") |> render_click()

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

    live |> element("button[phx-click=delete_statement]") |> render_click()
    assert Tax.list_snapshots(holder: "Owner", tax_year: 2025) == []
  end

  test "a configured Freistellungsauftrag can be recorded and removed", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/tax")

    live
    |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
    |> render_change()

    html =
      live
      |> form("#tax-order-form", %{
        "order" => %{"institution" => "Example Bank", "amount_granted" => "1000.00"}
      })
      |> render_submit()

    assert html =~ "Example Bank"
    assert [order] = Tax.list_allowance_orders(holder: "Owner", tax_year: 2025)
    assert Decimal.equal?(order.amount_granted, Decimal.new("1000.00"))

    live |> element("button[phx-click=delete_allowance_order]") |> render_click()
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

    {:ok, live, _html} = live(conn, "/tax")

    html =
      live
      |> form("#tax-scope-form", %{"scope" => %{"holder" => "Owner", "tax_year" => "2025"}})
      |> render_change()

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
end
