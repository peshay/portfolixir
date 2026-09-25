defmodule PortfolixirWeb.RowKebabNamesTest do
  # The tax surface's fixtures are not sandbox-isolated by account (the tax
  # tests run synchronously), so this file does too.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Tax

  defp label(view, selector) do
    [label] =
      view
      |> element(selector)
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("aria-label")

    label
  end

  # User story (#870; DESIGN.md → Do's and Don'ts, accessible names; WCAG
  # 2.4.6 and 4.1.2):
  # As an operator using a screen reader, tabbing a list or listing the
  # page's buttons,
  # I want each row's actions button to say which row it acts on,
  # so that I do not hear "Open actions menu" dozens of times and guess.
  #
  # Acceptance criteria:
  # - Every row kebab is named "Actions for <the row>": on /securities (table
  #   and phone row) the security, on /portfolios the depot, on /buckets the
  #   view or the bucket, on /snapshots the snapshot, on /tax the statement
  #   (institution and date) or the allowance order (institution), on
  #   /classifications the tree.
  # - A transaction row's kebab carries a composed name — kind, subject,
  #   date — on the table and on the phone row alike.
  # - Nothing a sighted reader sees changes: no visible text is added.
  test "every row kebab is named for its row", %{conn: conn} do
    world = base_world(name: "Namen")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
    buy = buy!(world, security, quantity: "10", price: "124", date: ~D[2026-09-01])
    deposit = deposit!(world, "5000", ~D[2026-08-15])

    {:ok, view, html} = live(conn, "/securities")
    refute html =~ "Open actions menu"

    for kebab <- ["#row-kebab-#{security.id}", "#phone-kebab-#{security.id}"] do
      assert label(view, kebab) == "Actions for Nordic Timber Holdings AB"
    end

    {:ok, view, html} = live(conn, "/transactions")
    refute html =~ "Open actions menu"

    for kebab <- ["#tx-kebab-#{buy.id}", "#tx-phone-kebab-#{buy.id}"] do
      assert label(view, kebab) == "Actions for Buy, Nordic Timber Holdings AB, 2026-09-01"
    end

    assert label(view, "#tx-kebab-#{deposit.id}") == "Actions for Deposit, Local Cash, 2026-08-15"

    {:ok, view, html} = live(conn, "/portfolios")
    refute html =~ "Open actions menu"
    assert label(view, "#account-kebab-#{world.depot.id}") == "Actions for Main Depot"

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Spielgeld"})
    {:ok, spekulativ} = Buckets.create_view(Actor.owner_ui(), %{name: "Spekulativ"})

    {:ok, view, html} = live(conn, "/buckets")
    refute html =~ "Open actions menu"
    assert label(view, "#view-kebab-#{spekulativ.id}") == "Actions for Spekulativ"
    assert label(view, "#bucket-kebab-#{bucket.id}") == "Actions for Spielgeld"

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Vor dem Umbau", as_of: ~D[2026-09-02]})

    {:ok, view, html} = live(conn, "/snapshots")
    refute html =~ "Open actions menu"
    assert label(view, "#snapshot-kebab-#{snapshot.id}") == "Actions for Vor dem Umbau"

    {:ok, statement} =
      Tax.create_snapshot(
        Actor.owner_ui(),
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
        today: ~D[2026-01-15]
      )

    {:ok, order} =
      Tax.put_allowance_order(Actor.owner_ui(), %{
        holder: "Owner",
        institution: "Second Bank",
        tax_year: 2025,
        amount_granted: Decimal.new("1000.00")
      })

    {:ok, view, html} = live(conn, "/tax?holder=Owner&year=2025")
    refute html =~ "Open actions menu"

    assert label(view, "#tax-row-kebab-statement-#{statement.id}") ==
             "Actions for Example Bank, 2025-12-31"

    assert label(view, "#tax-row-kebab-order-#{order.id}") == "Actions for Second Bank"

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

    {:ok, view, html} = live(conn, "/classifications")
    refute html =~ "Open actions menu"
    assert label(view, "#tree-kebab-#{tree.id}") == "Actions for Strategie"
  end

  # Acceptance criteria (#870): on a German page the name reads
  # "Aktionen für <the row>", the transaction's parts in German too.
  test "the row kebab's name reads in German on a German page", %{conn: conn} do
    world = base_world(name: "Namen")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
    buy = buy!(world, security, quantity: "10", price: "124", date: ~D[2026-09-01])

    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

    {:ok, view, _html} = live(conn, "/securities")
    assert label(view, "#row-kebab-#{security.id}") == "Aktionen für Nordic Timber Holdings AB"

    {:ok, view, _html} = live(conn, "/transactions")

    assert label(view, "#tx-kebab-#{buy.id}") ==
             "Aktionen für Kauf, Nordic Timber Holdings AB, 01.09.2026"
  end
end
