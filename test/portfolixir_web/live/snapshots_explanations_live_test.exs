defmodule PortfolixirWeb.SnapshotsExplanationsLiveTest do
  # Board `ux-design-2026-11-03-sprint23-i1` on Snapshots (Sprint 23 Lane I;
  # idea I1, variant R): the comparison's cost definition leaves its basis
  # line for a new ⓘ beside the heading (①), the basis clauses stay (②),
  # the limitation note states no data fact and joins the same ⓘ (reading
  # 3), and the gaps note gains its count and clamps (③ ⑧). The cost figure
  # reads "40.00 EUR" (#1321). Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.WorldFixtures

  # As of 2026-02-15: 5 EUR Stock at 110 and two positions without a quote
  # (Unquoted Alpha, Unquoted Beta). After it, a top-up buy of 1 at 110
  # with a fee of 40: the comparison's transaction costs.
  defp seed! do
    world = WorldFixtures.base_world(name: "Snap", currency: "EUR")
    sec = WorldFixtures.create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")

    book = fn attrs ->
      {:ok, _} =
        Ledger.create_transaction(
          Actor.owner_ui(),
          Map.merge(%{portfolio_id: world.portfolio.id, currency_code: "EUR"}, attrs)
        )
    end

    buy = fn security, quantity, price, gross, date, fees ->
      book.(%{
        cash_account_id: world.cash.id,
        securities_account_id: world.depot.id,
        security_id: WorldFixtures.security_id_for(security),
        type: "buy",
        date: date,
        quantity: quantity,
        price: price,
        gross_amount: gross,
        fees: fees
      })
    end

    deposit = fn amount, date ->
      book.(%{cash_account_id: world.cash.id, type: "deposit", date: date, gross_amount: amount})
    end

    deposit.("610", ~D[2026-01-02])
    buy.(sec, "5", "110", "550", ~D[2026-01-05], "0")

    for {name, ticker} <- [{"Unquoted Alpha", "UQA"}, {"Unquoted Beta", "UQB"}] do
      ghost = WorldFixtures.create_security!(name: name, ticker: ticker, currency: "EUR")
      buy.(ghost, "3", "10", "30", ~D[2026-01-20], "0")
    end

    WorldFixtures.put_quote!(sec, ~D[2026-01-05], "110")
    WorldFixtures.put_quote!(sec, ~D[2026-02-14], "110")
    WorldFixtures.put_quote!(sec, ~D[2026-03-10], "120")

    {:ok, _snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Before restructuring",
        as_of: ~D[2026-02-15]
      })

    deposit.("150", ~D[2026-02-20])
    buy.(sec, "1", "110", "150", ~D[2026-02-20], "40")
    world
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> squish()
  end

  defp lines(view, selector) do
    view
    |> element(selector)
    |> render()
    |> String.split(~r/<br\s*\/?>/)
    |> Enum.map(&(&1 |> LazyHTML.from_fragment() |> LazyHTML.text() |> squish()))
  end

  @comparison "[data-role='snapshot-comparison']"

  # User story (board `ux-design-2026-11-03-sprint23-i1`, Snapshots ① ② ③ ⑧;
  # reading 3; #1321):
  # As the operator reading whether holding would have won,
  # I want the comparison's basis on the page, its definitions behind one
  # ⓘ beside the heading, and the positions it leaves out counted first,
  # so that the figures read without a paragraph of method and nothing
  # left out is hidden.
  #
  # Acceptance criteria:
  # - The heading sits in `.section-title` with the section's ⓘ, which
  #   holds two lines: "Transaction costs = fees and taxes booked on trades
  #   since then; standalone fees, taxes and dividend withholding stay
  #   inside the return on both sides" and "The comparison is gross and
  #   price development only — dividends are not yet included.".
  # - The basis line reads "since 2026-02-15 · in EUR · gross, price
  #   development only"; the limitation note is gone.
  # - The gaps note clamps (its own id) and reads "Not included: 2 positions
  #   with no usable quote or exchange rate at the as-of date — Unquoted
  #   Alpha, Unquoted Beta"; in German „Nicht enthalten: 2 Positionen ohne
  #   verwendbaren Kurs oder Wechselkurs zum Stichtag — …“, the basis
  #   „seit 15.02.2026 · in EUR · brutto, nur Kursentwicklung“.
  # - The transaction costs read "40.00 EUR", a text space before the
  #   currency.
  test "the comparison's method sits in the heading's ⓘ, its gaps are counted and clamp",
       %{conn: conn} do
    seed!()

    {:ok, view, _html} = live(conn, "/snapshots")

    title = @comparison <> " header.section-head > .section-title"
    assert text(view, title <> " > h2") == "Comparison against “Before restructuring”"

    assert lines(view, title <> " > details[data-role='section-info'] p[role='tooltip']") == [
             "Transaction costs = fees and taxes booked on trades since then; standalone fees, taxes and dividend withholding stay inside the return on both sides",
             "The comparison is gross and price development only — dividends are not yet included."
           ]

    assert text(view, @comparison <> " [data-role='comparison-basis']") ==
             "since 2026-02-15 · in EUR · gross, price development only"

    refute has_element?(view, "[data-role='comparison-limitation']")

    gaps =
      @comparison <> " .comparison-notes > .data-note--clamped[data-role='comparison-gaps'][id]"

    assert text(view, gaps <> " .data-note__text") ==
             "Not included: 2 positions with no usable quote or exchange rate at the as-of date — Unquoted Alpha, Unquoted Beta"

    assert text(view, "#comparison-costs [data-role='transaction-costs']") == "40.00 EUR"

    {:ok, de_view, _html} = live(conn, "/snapshots?locale=de")

    assert text(de_view, gaps <> " .data-note__text") ==
             "Nicht enthalten: 2 Positionen ohne verwendbaren Kurs oder Wechselkurs zum Stichtag — Unquoted Alpha, Unquoted Beta"

    assert text(de_view, @comparison <> " [data-role='comparison-basis']") ==
             "seit 15.02.2026 · in EUR · brutto, nur Kursentwicklung"

    assert [
             "Transaktionskosten = seitdem auf Handelsgeschäften gebuchte Gebühren und Steuern; " <>
               _,
             "Der Vergleich ist brutto und nur Kursentwicklung — Dividenden sind noch nicht enthalten."
           ] = lines(de_view, title <> " > details[data-role='section-info'] p[role='tooltip']")
  end
end
