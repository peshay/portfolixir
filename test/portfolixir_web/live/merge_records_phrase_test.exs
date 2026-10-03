defmodule PortfolixirWeb.MergeRecordsPhraseTest do
  # Sprint 18 pick H8.7 (#1032, the UI half; board
  # ux-design-2026-10-02/08-dialogs-copy, before/after; ADR-0050 §12, §13):
  # a security merge's result phrase counts every removal it made — the
  # duplicates the operator chose and a same-day split collapsed with the
  # target's — in the merge record list and in the result right after the
  # merge; and an empty merge reads "nothing to check" for every kind. The
  # merge record's payload is unchanged: the words key on the source having
  # moved nothing. Every name, identifier, amount and date is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    %{portfolio: portfolio}
  end

  defp squish(nodes), do: nodes |> Floki.text() |> String.split() |> Enum.join(" ")

  defp record_row(view, record) do
    view
    |> element("#merge-records .merge-records-table tr[data-merge='#{record.id}']")
    |> render()
    |> Floki.parse_fragment!()
  end

  defp check_line(row),
    do: row |> Floki.find(".merge-manifest__counts dd") |> List.last() |> squish()

  # User story (#1032, the UI half; pick H8.7, board 08-dialogs-copy):
  # As the operator reading back what a security merge did,
  # I want its result phrase to name the split it collapsed with the
  # target's, not only the duplicates I chose,
  # so that the phrase and the opened counts tell one story.
  #
  # Acceptance criteria:
  # - The result right after the merge reads "Merged into …: 1 booking
  #   moved, 1 split collapsed."
  # - The merge record's phrase reads "1 Buchung verschoben, 1 Split
  #   zusammengelegt" in German, the open line's own word, after the
  #   duplicates and before the quotes; no total ("2 entfernt").
  test "a security merge's phrase counts the split it collapsed", %{conn: conn} = ctx do
    giro = cash!(ctx.portfolio, "Girokonto")
    depot = depot!(ctx.portfolio, "Depot 1", giro)
    target = security!("Kestrel Industrial Group NV", "XS0000000017")
    source = security!("Kestrel Industrial Group NV", "XS0000000025")
    deposit!(ctx.portfolio, giro, "5000.00", ~D[2025-01-02])
    buy!(ctx.portfolio, depot, giro, target, "10", "100.00", ~D[2025-01-10])
    buy!(ctx.portfolio, depot, giro, source, "5", "110.00", ~D[2025-02-10])
    split!(ctx.portfolio, target, ~D[2025-09-01], {2, 1})
    split!(ctx.portfolio, source, ~D[2025-09-01], {2, 1})

    {:ok, view, _html} = live(conn, "/securities")

    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{source.id}"])
    )
    |> render_click()

    view |> element("#row-menu-#{source.id} [data-role='menu-merge']") |> render_click()

    view
    |> element("#security-merge-dialog form[data-role='merge-search']")
    |> render_change(%{merge: %{q: target.name}})

    view
    |> element("#security-merge-dialog form[data-role='merge-target-form']")
    |> render_change(%{merge: %{target_id: "#{target.id}"}})

    view |> element("#security-merge-dialog [data-role='merge-continue']") |> render_click()

    view
    |> element("#security-merge-dialog form[data-role='merge-choice-form']")
    |> render_change(%{merge: %{identity: "keep_target_isin"}})

    view |> element("#security-merge-dialog [data-role='merge-confirm']") |> render_click()
    render_async(view)

    assert view
           |> element("#securities-action-result [role=status]")
           |> render()
           |> Floki.parse_fragment!()
           |> squish() =~
             "Merged into Kestrel Industrial Group NV: 1 booking moved, 1 split collapsed."

    record = Lifecycle.merge_of(:security, source.id)

    {:ok, view, _html} = live(conn, "/portfolios?locale=de")
    row = record_row(view, record)

    assert squish(Floki.find(row, ".merge-manifest > summary")) ==
             "1 Buchung verschoben, 1 Split zusammengelegt"
  end

  # User story (#1032, the UI half):
  # As the operator reading back a merge of an account that held nothing,
  # I want it to read "nothing to check" whatever its kind,
  # so that an empty cash merge does not claim a balance check an empty
  # depot merge does not.
  #
  # Acceptance criteria:
  # - An empty cash account merged into one with bookings reads "nichts zu
  #   prüfen" (not "Saldo an 3 Tagen bestätigt"); so does an empty one into
  #   an empty one.
  # - A cash merge that moved bookings still reads "Saldo an N Tagen
  #   bestätigt".
  test "an empty merge reads nothing to check, for a cash account too", %{conn: conn} = ctx do
    target = cash!(ctx.portfolio, "Tagesgeld")
    deposit!(ctx.portfolio, target, "100.00", ~D[2026-01-05])
    deposit!(ctx.portfolio, target, "40.00", ~D[2026-01-06])
    empty = cash!(ctx.portfolio, "Tagesgeld alt")
    into_history = merge_cash!(Actor.api_token_rw("synthetic"), empty, target)

    lone = cash!(ctx.portfolio, "Leer")
    other = cash!(ctx.portfolio, "Auch leer")
    into_nothing = merge_cash!(Actor.owner_ui(), lone, other)

    moving = cash!(ctx.portfolio, "Festgeld")
    deposit!(ctx.portfolio, moving, "10.00", ~D[2026-01-07])
    moved = merge_cash!(Actor.owner_ui(), moving, target)

    {:ok, view, _html} = live(conn, "/portfolios?locale=de")

    assert view |> record_row(into_history) |> check_line() == "nichts zu prüfen"
    assert view |> record_row(into_nothing) |> check_line() == "nichts zu prüfen"
    assert view |> record_row(moved) |> check_line() =~ ~r/^Saldo an \d+ Tagen bestätigt$/

    {:ok, view, _html} = live(conn, "/portfolios")
    assert view |> record_row(into_history) |> check_line() == "nothing to check"
  end

  defp merge_cash!(actor, source, target) do
    {:ok, preview} = Lifecycle.preview_cash_merge(source.id, target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_cash_account(actor, source.id, target.id, %{
        plan_digest: preview.plan_digest
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
        asset_class: "equity"
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

  defp split!(portfolio, security, date, {numerator, denominator}) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        security_id: security.id,
        type: "split",
        date: date,
        currency_code: security.currency_code,
        split_ratio_numerator: numerator,
        split_ratio_denominator: denominator
      })

    tx
  end
end
