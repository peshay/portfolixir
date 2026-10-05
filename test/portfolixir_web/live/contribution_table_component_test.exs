defmodule PortfolixirWeb.Portfolio.ContributionTableComponentTest do
  # FR-41, ADR-0051 §12: the contribution table's states and words, rendered
  # from engine-shaped results the walk produces only on worlds a page test
  # would have to contort (a failed walk, a nameless security, a tie at the
  # tenth place). Invented figures only.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Portfolio.ContributionTable

  defp d(value), do: Decimal.new(value)

  defp position(id, contribution, overrides \\ %{}) do
    Map.merge(
      %{
        security_id: id,
        name: "Position #{id}",
        isin: nil,
        start_value: d("100"),
        net_flows: d("0"),
        income: d("0"),
        costs: d("0"),
        end_value: Decimal.add(d("100"), d(contribution)),
        contribution: d(contribution),
        held_at_start: true,
        held_at_end: true,
        unvalued_days: 0,
        unvalued_reason: nil
      },
      overrides
    )
  end

  defp result(positions, accounts \\ []) do
    total = Enum.reduce(positions, d("0"), &Decimal.add(&1.contribution, &2))

    %{
      start_date: ~D[2026-01-01],
      end_date: ~D[2026-06-30],
      base_currency: "EUR",
      positions: positions,
      remainder: %{
        interest: d("0"),
        standalone_fees_and_taxes: d("0"),
        cash_currency_effect: d("0")
      },
      totals: %{result: total, positions: total, remainder: d("0")},
      unvalued_cash_accounts: accounts
    }
  end

  defp account(id, name, overrides \\ %{}) do
    Map.merge(
      %{
        cash_account_id: id,
        name: name,
        currency_code: "CHF",
        balance: d("2000"),
        unvalued_days: 18,
        unvalued_reason: :no_rate,
        unvalued_through_end: false,
        first_rate_date: ~D[2026-03-02]
      },
      overrides
    )
  end

  defp render_table(contribution, opts \\ []) do
    render_component(&ContributionTable.table/1,
      contribution: contribution,
      failed?: Keyword.get(opts, :failed?, false),
      show_all?: false,
      period_label: "YTD",
      view_name: "Everything"
    )
  end

  defp text(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Floki.text(sep: " ")
    |> String.split()
    |> Enum.join(" ")
  end

  # The note as it reads: the test DOM's separator also lands between a
  # closing tag and the full stop after it.
  defp sentence(html, selector),
    do: html |> text(selector) |> String.replace(" .", ".") |> String.replace(" ,", ",")

  # User story (FR-41, ADR-0051 §12, board pick A):
  # As a local portfolio maintainer whose contribution walk failed,
  # I want the table to say so instead of computing forever,
  # so that I know a reload is the remedy.
  #
  # Acceptance criteria:
  # - A failed walk renders the problem note "Computation failed. Reload
  #   retries." and no table, whatever result the page still holds.
  test "a failed walk is the problem note, never a table" do
    html = render_table(result([position(1, "5")]), failed?: true)

    assert text(html, "[data-role='contribution-failed']") =~
             "Computation failed. Reload retries."

    assert Floki.find(Floki.parse_fragment!(html), "#contribution-table") == []
  end

  # User story (FR-41, ADR-0051 §10 and §12):
  # As a local portfolio maintainer reading the table's rows,
  # I want every row named and every unvalued reason in words,
  # so that a security stored without a name, a position sold out inside the
  # period and a missing exchange rate each read for what they are.
  #
  # Acceptance criteria:
  # - A position without a name reads as its ISIN; without either, as "—".
  # - A position held at the start but not at the end says "no longer held
  #   at the end" under its name.
  # - A position that counted zero for lack of a rate is named in the note
  #   with "no exchange rate stored".
  test "rows name a nameless security, a sold-out position and a missing rate" do
    positions = [
      position(1, "30", %{name: nil, isin: "XSEXMPL40031"}),
      position(2, "20", %{name: nil}),
      position(3, "-10", %{held_at_end: false, end_value: d("0")}),
      position(4, "-15", %{unvalued_days: 12, unvalued_reason: :no_rate})
    ]

    html = render_table(result(positions))

    assert text(html, "#contribution-table tr[data-security-id='1'] td:first-child") ==
             "XSEXMPL40031"

    assert text(html, "#contribution-table tr[data-security-id='2'] td:first-child") == "—"

    assert text(html, "#contribution-table tr[data-security-id='3'] td:first-child") ==
             "Position 3 no longer held at the end"

    assert text(html, "[data-role='contribution-unvalued']") =~
             "Position 4 (12 days, no exchange rate stored)"
  end

  # User story (#1055, ADR-0051 §10, board J2 A):
  # As a local portfolio maintainer whose CHF account held money before the
  # instance had a CHF rate,
  # I want the note under the table to name the account the way it names a
  # position, and the currency-effect row to carry the account's marker,
  # so that the jump in that row reads as a deposit that became visible, not
  # as a currency gain.
  #
  # Acceptance criteria:
  # - One account: "One cash account counted zero on some days of the
  #   period: Tagesgeld CHF (2,000.00 CHF, 18 days, no exchange rate
  #   stored)." and, when its first rate arrived inside the period, "With the
  #   first exchange rate on 2026-03-02, its whole balance entered the
  #   “Currency effect on cash” — that is no currency gain." (dates ISO in
  #   English); an account emptied before its rate gets the first sentence
  #   only.
  # - An account still at zero on the period's last day reads "One cash
  #   account counts zero until the end of the period: …" (board J2 A, pin
  #   a2), "… zählt bis zum Ende des Zeitraums null" in German.
  # - A negative balance reads "— that is no currency loss"; balances of
  #   both signs "— that is neither a currency gain nor a currency loss".
  # - The note names the positions first and the accounts after them, in one
  #   note; with accounts only, the note still renders.
  # - Several accounts: the plural sentences, and one sentence naming each
  #   account whose first rate arrived, with its date.
  # - A balance below a cent keeps its digits: "0.004 CHF", never "0.00".
  # - An empty window that still held an account at zero shows the
  #   empty-state sentence and the note.
  # - The currency-effect row carries `.contribution-unvalued-mark` per
  #   account, "Tagesgeld CHF: 18 days at zero", and so does the phone
  #   remainder row; the other two lines carry none.
  test "an account that counted zero is named in the note and marked on the currency row" do
    html =
      render_table(
        result([position(4, "-15", %{unvalued_days: 12, unvalued_reason: :no_rate})], [
          account(7, "Tagesgeld CHF")
        ])
      )

    note = sentence(html, "[data-role='contribution-unvalued']")

    assert note =~
             "One position counted zero on some days of the period: Position 4 (12 days, " <>
               "no exchange rate stored). It stays in the sum, as in the result above. " <>
               "One cash account counted zero on some days of the period: Tagesgeld CHF " <>
               "(2,000.00 CHF, 18 days, no exchange rate stored). With the first exchange " <>
               "rate on 2026-03-02, its whole balance entered the “Currency effect on cash” " <>
               "— that is no currency gain."

    assert text(
             html,
             "#contribution-table tr[data-line='cash_currency_effect'] .contribution-unvalued-mark"
           ) ==
             "Tagesgeld CHF: 18 days at zero"

    for line <- ["interest", "standalone_fees_and_taxes"] do
      assert text(html, "#contribution-table tr[data-line='#{line}'] .contribution-unvalued-mark") ==
               ""
    end

    assert text(html, "[data-role='contribution-phone-rest'] .phone-row__ids") ==
             "Interest 0.00 · Fees/taxes 0.00 · Currency 0.00 · Tagesgeld CHF: 18 days at zero"

    # Still at zero on the last day: pin a2's sentence. No position and no
    # line moved: the empty-state sentence, and the account still named.
    through_end = account(7, "Tagesgeld CHF", %{unvalued_through_end: true, first_rate_date: nil})
    alone = render_table(result([], [through_end]))
    assert text(alone, "[data-role='contribution-empty']") =~ "Nothing to break down"

    assert sentence(alone, "[data-role='contribution-unvalued']") ==
             "Attention One cash account counts zero until the end of the period: Tagesgeld " <>
               "CHF (2,000.00 CHF, 18 days, no exchange rate stored)."

    # Emptied before its rate came: the first sentence only.
    emptied = render_table(result([], [account(7, "Leer CHF", %{first_rate_date: nil})]))

    assert sentence(emptied, "[data-role='contribution-unvalued']") ==
             "Attention One cash account counted zero on some days of the period: Leer CHF " <>
               "(2,000.00 CHF, 18 days, no exchange rate stored)."

    # An overdraft: its rate brought a loss into the line, which is none.
    overdraft = render_table(result([], [account(7, "Konto CHF", %{balance: d("-500")})]))

    assert sentence(overdraft, "[data-role='contribution-unvalued']") =~
             "(-500.00 CHF, 18 days, no exchange rate stored). With the first exchange rate on " <>
               "2026-03-02, its whole balance entered the “Currency effect on cash” — that is " <>
               "no currency loss."

    # Three accounts: two whose rate came, of both signs, one still at zero.
    three =
      render_table(
        result([position(1, "5")], [
          account(8, "Sparkonto CHF", %{balance: d("400"), unvalued_days: 11}),
          account(9, "Overdraft CHF", %{balance: d("-0.004")}),
          account(10, "USD Settlement", %{
            currency_code: "USD",
            balance: d("1850"),
            unvalued_days: 30,
            unvalued_through_end: true,
            first_rate_date: nil
          })
        ])
      )

    note = sentence(three, "[data-role='contribution-unvalued']")

    assert note ==
             "Attention 2 cash accounts counted zero on some days of the period: Sparkonto CHF " <>
               "(400.00 CHF, 11 days, no exchange rate stored), Overdraft CHF (-0.004 CHF, 18 " <>
               "days, no exchange rate stored). With their first exchange rates, the whole " <>
               "balances of Sparkonto CHF (2026-03-02), Overdraft CHF (2026-03-02) entered the " <>
               "“Currency effect on cash” — that is neither a currency gain nor a currency " <>
               "loss. One cash account counts zero until the end of the period: USD " <>
               "Settlement (1,850.00 USD, 30 days, no exchange rate stored)."

    assert text(
             three,
             "#contribution-table tr[data-line='cash_currency_effect'] .contribution-unvalued-mark"
           ) ==
             "Sparkonto CHF: 11 days at zero Overdraft CHF: 18 days at zero " <>
               "USD Settlement: 30 days at zero"

    # Every balance valued: no note, no marker.
    none = render_table(result([position(1, "5")]))
    assert text(none, "[data-role='contribution-unvalued']") == ""
    assert text(none, ".contribution-unvalued-mark") == ""
  end

  # User story (#1055, board J2 A, pin a2):
  # As a local portfolio maintainer reading German,
  # I want the account sentences in the board's words,
  # so that "Kurs" keeps meaning a security's price and a balance still at
  # zero reads as one.
  #
  # Acceptance criteria:
  # - A balance whose first exchange rate came: "Mit dem ersten Wechselkurs
  #   am 02.03.2026 kam sein ganzer Saldo in den „Währungseffekt auf
  #   Bargeld“ — das ist kein Währungsgewinn."; an overdraft "— das ist kein
  #   Währungsverlust".
  # - A balance still at zero on the last day: "Ein Verrechnungskonto zählt
  #   bis zum Ende des Zeitraums null: …"; two: "2 Verrechnungskonten zählen
  #   bis zum Ende des Zeitraums null: …".
  test "the account sentences in German" do
    previous = Gettext.get_locale(PortfolixirWeb.Gettext)

    try do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      gain = render_table(result([], [account(7, "Tagesgeld CHF")]))

      assert sentence(gain, "[data-role='contribution-unvalued']") ==
               "Achtung Ein Verrechnungskonto zählte an einigen Tagen des Zeitraums null: " <>
                 "Tagesgeld CHF (2.000,00 CHF, 18 Tage, kein Wechselkurs gespeichert). Mit dem " <>
                 "ersten Wechselkurs am 02.03.2026 kam sein ganzer Saldo in den „Währungseffekt " <>
                 "auf Bargeld“ — das ist kein Währungsgewinn."

      loss = render_table(result([], [account(7, "Konto CHF", %{balance: d("-500")})]))

      assert sentence(loss, "[data-role='contribution-unvalued']") =~
               "— das ist kein Währungsverlust."

      still = %{unvalued_through_end: true, first_rate_date: nil}

      one = render_table(result([], [account(7, "Tagesgeld CHF", still)]))

      assert sentence(one, "[data-role='contribution-unvalued']") ==
               "Achtung Ein Verrechnungskonto zählt bis zum Ende des Zeitraums null: " <>
                 "Tagesgeld CHF (2.000,00 CHF, 18 Tage, kein Wechselkurs gespeichert)."

      two =
        render_table(
          result([], [account(7, "Tagesgeld CHF", still), account(8, "Sparkonto CHF", still)])
        )

      assert sentence(two, "[data-role='contribution-unvalued']") =~
               "Achtung 2 Verrechnungskonten zählen bis zum Ende des Zeitraums null: "
    after
      Gettext.put_locale(PortfolixirWeb.Gettext, previous)
    end
  end

  # User story (FR-41, board pick A):
  # As a local portfolio maintainer with more than ten positions,
  # I want the ten largest by absolute amount, ties kept in the table's
  # order,
  # so that the shown rows do not change between two renders of one result.
  #
  # Acceptance criteria:
  # - Two positions of equal absolute contribution at the tenth place: the
  #   one earlier in the table's order is shown, the later one hidden.
  test "a tie at the tenth place keeps the table's order" do
    # Nine clear leaders, then +5 (id 10) and -5 (id 11) tie on amount, then
    # a smaller one (id 12).
    leaders = for id <- 1..9, do: position(id, Integer.to_string(100 - id))
    positions = leaders ++ [position(10, "5"), position(12, "1"), position(11, "-5")]

    shown = ContributionTable.shown_positions(positions, false)

    assert Enum.map(shown, & &1.security_id) == Enum.to_list(1..10)
  end
end
