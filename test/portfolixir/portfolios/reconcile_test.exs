defmodule Portfolixir.Portfolios.ReconcileTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Reconcile

  @guidance "resolve a difference by booking the missing transaction of the correct kind; " <>
              "balance snapshots and unpriced deliveries are last resorts that distort cost basis"
  @weak_caveat "confirm the security before booking"

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Example AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  defp accounts!(prefix) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "#{prefix} Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "#{prefix} Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "#{prefix} Depot"
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  defp buy!(%{portfolio: portfolio, cash: cash, depot: depot}, security, quantity) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: quantity,
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })
  end

  defp row(identifier, quantity, extra \\ %{}) do
    Map.merge(
      %{identifier: identifier, quantity: Decimal.new(quantity), currency: nil, security_id: nil},
      extra
    )
  end

  # User story:
  # As the operating agent reconciling an external broker position list,
  # I want each row matched through the ADR-0029 stable-identity ladder with
  # its matched tier reported and the quantity delta computed exactly,
  # so that a discrepancy is an exact, bookable fact instead of arithmetic
  # done in a token predictor's head (ADR-0029 6, FR-35).
  #
  # Acceptance criteria:
  # - An ISIN-shaped identifier resolves via tier 1 (current ISIN) with
  #   matched_via :isin; a recorded former ISIN resolves with :former_isin.
  # - ledger_quantity, external_quantity and delta are Decimal-exact,
  #   delta = external - ledger (negative when the ledger holds more).
  # - The response embeds the resolution guidance verbatim.
  describe "identity ladder matching" do
    test "matches by current ISIN with an exact positive delta" do
      accounts = accounts!("Isin")
      security = security!(%{name: "Identified AG", isin: "DE0007100000"})
      buy!(accounts, security, "10")

      result = Reconcile.run([row("de0007100000", "12.5")])

      assert result.guidance == @guidance
      assert [matched] = result.matched
      assert matched.security.id == security.id
      assert matched.matched_via == :isin
      refute matched.weak_match
      assert matched.caveat == nil
      assert Decimal.eq?(matched.ledger_quantity, Decimal.new("10"))
      assert Decimal.eq?(matched.external_quantity, Decimal.new("12.5"))
      assert Decimal.eq?(matched.delta, Decimal.new("2.5"))
    end

    test "matches by recorded former ISIN with matched_via :former_isin" do
      accounts = accounts!("Alias")
      security = security!(%{name: "Renamed AG", isin: "DE0007100000"})
      buy!(accounts, security, "3")

      {:ok, _} = Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007164600")

      result = Reconcile.run([row("DE0007100000", "3")])

      assert [matched] = result.matched
      assert matched.security.id == security.id
      assert matched.matched_via == :former_isin
      assert Decimal.eq?(matched.delta, Decimal.new("0"))
    end

    test "an ISIN-shaped identifier enters tier 1 only and never falls through" do
      accounts = accounts!("IsinOnly")
      # A security literally NAMED like a valid ISIN must not be name-matched
      # by an ISIN-shaped identifier: tier 1 only, per ADR-0029 6.
      decoy = security!(%{name: "US0378331005", currency_code: "EUR"})
      buy!(accounts, decoy, "1")

      result = Reconcile.run([row("US0378331005", "1", %{currency: "EUR"})])

      assert result.matched == []
      assert [unmatched] = result.unmatched
      assert unmatched.identifier == "US0378331005"
      assert unmatched.reason == :no_match
    end

    test "matches by WKN with matched_via :wkn, no weak-match caveat" do
      accounts = accounts!("Wkn")
      security = security!(%{name: "Wkn AG", wkn: "710000"})
      buy!(accounts, security, "7")

      result = Reconcile.run([row(" 710000 ", "7")])

      assert [matched] = result.matched
      assert matched.security.id == security.id
      assert matched.matched_via == :wkn
      refute matched.weak_match
      assert Decimal.eq?(matched.delta, Decimal.new("0"))
    end

    test "matches by ticker+currency with the weak-match caveat" do
      accounts = accounts!("Ticker")
      security = security!(%{name: "Ticker AG", ticker_symbol: "TCK"})
      buy!(accounts, security, "4")

      result = Reconcile.run([row("tck", "4", %{currency: "eur"})])

      assert [matched] = result.matched
      assert matched.security.id == security.id
      assert matched.matched_via == :ticker
      assert matched.weak_match
      assert matched.caveat == @weak_caveat
    end

    test "matches by name+currency with the weak-match caveat and exact negative delta" do
      accounts = accounts!("Name")
      security = security!(%{name: "Nameonly Corp"})
      buy!(accounts, security, "10")

      result = Reconcile.run([row(" Nameonly Corp ", "9.5", %{currency: "EUR"})])

      assert [matched] = result.matched
      assert matched.security.id == security.id
      assert matched.matched_via == :name
      assert matched.weak_match
      assert matched.caveat == @weak_caveat
      assert Decimal.eq?(matched.delta, Decimal.new("-0.5"))
    end
  end

  # User story:
  # As the operating agent,
  # I want the exactly-one rule applied ACROSS THE UNION of the remaining
  # tiers for non-ISIN identifiers,
  # so that a string matching one security's WKN and another's ticker is
  # surfaced as ambiguous with candidates, never silently picked (ADR-0029 6).
  #
  # Acceptance criteria:
  # - Cross-tier ambiguity (WKN of A, ticker of B) reports both candidates.
  # - The same identifier hitting several tiers of ONE security still counts
  #   as exactly one and matches via the strongest tier.
  describe "union exactly-one rule" do
    test "a WKN-of-A / ticker-of-B identifier is ambiguous with both candidates" do
      accounts = accounts!("Union")
      a = security!(%{name: "Alpha AG", wkn: "AMBIG1"})
      b = security!(%{name: "Beta AG", ticker_symbol: "AMBIG1"})
      buy!(accounts, a, "1")
      buy!(accounts, b, "2")

      result = Reconcile.run([row("AMBIG1", "3", %{currency: "EUR"})])

      assert result.matched == []
      assert [ambiguous] = result.ambiguous
      assert ambiguous.identifier == "AMBIG1"
      assert Enum.sort(Enum.map(ambiguous.candidates, & &1.id)) == Enum.sort([a.id, b.id])
    end

    test "one security hit through several tiers matches via the strongest tier" do
      accounts = accounts!("MultiTier")
      security = security!(%{name: "Sametick AG", wkn: "SAME01", ticker_symbol: "SAME01"})
      buy!(accounts, security, "5")

      result = Reconcile.run([row("SAME01", "5", %{currency: "EUR"})])

      assert [matched] = result.matched
      assert matched.security.id == security.id
      assert matched.matched_via == :wkn
      refute matched.weak_match
    end
  end

  # User story:
  # As the operating agent,
  # I want a currency-less row kept out of the currency-qualified tiers 3-4,
  # so that a bare ticker or name is reported unmatched instead of guessed
  # into the wrong currency's security (ADR-0029 6).
  #
  # Acceptance criteria:
  # - A currency-less name/ticker row is unmatched with a currency_required
  #   reason, even when a (name, currency) row would match uniquely.
  test "a currency-less name row is unmatched, never guessed" do
    accounts = accounts!("NoCurrency")
    security = security!(%{name: "Bitcoin", ticker_symbol: "BTC"})
    buy!(accounts, security, "1")

    result = Reconcile.run([row("Bitcoin", "1")])

    assert result.matched == []
    assert [unmatched] = result.unmatched
    assert unmatched.identifier == "Bitcoin"
    assert unmatched.reason == :currency_required
  end

  # User story:
  # As the operating agent,
  # I want rows resolving to the same security aggregated,
  # so that I never see two contradictory deltas for one position (ADR-0029 6).
  #
  # Acceptance criteria:
  # - External quantities of duplicate identifiers are summed exactly.
  # - The aggregation is noted (aggregated flag, contributing rows listed).
  test "duplicate identifiers aggregate into one row with summed external quantity" do
    accounts = accounts!("Aggregate")
    security = security!(%{name: "Split Lot AG", isin: "DE0008404005"})
    buy!(accounts, security, "10")

    result = Reconcile.run([row("DE0008404005", "4.25"), row("DE0008404005", "5.75")])

    assert [matched] = result.matched
    assert matched.aggregated
    assert length(matched.rows) == 2
    assert Decimal.eq?(matched.external_quantity, Decimal.new("10.00"))
    assert Decimal.eq?(matched.delta, Decimal.new("0"))
  end

  # User story:
  # As the operating agent,
  # I want ledger positions absent from the external list surfaced,
  # so that a position the broker no longer shows is a visible gap, not a
  # silent omission (FR-7).
  #
  # Acceptance criteria:
  # - A held security matched by no row appears under missing_from_list with
  #   its exact ledger quantity.
  # - Matched securities do not appear there.
  test "held ledger positions absent from the list are surfaced" do
    accounts = accounts!("Missing")
    listed = security!(%{name: "Listed AG", isin: "DE0005557508"})
    absent = security!(%{name: "Forgotten AG", isin: "FR0000120271"})
    buy!(accounts, listed, "2")
    buy!(accounts, absent, "6.5")

    result = Reconcile.run([row("DE0005557508", "2")])

    assert [missing] = result.missing_from_list
    assert missing.security.id == absent.id
    assert Decimal.eq?(missing.ledger_quantity, Decimal.new("6.5"))
  end

  # User story:
  # As the operating agent,
  # I want an explicit security_id pin to override the ladder,
  # so that a decided identity sticks without re-deciding each call.
  #
  # Acceptance criteria:
  # - A pinned row matches that security regardless of its identifier.
  # - An unknown pinned id is surfaced as unmatched, never silently dropped.
  test "an explicit security_id pins the match; an unknown pin is surfaced" do
    accounts = accounts!("Pin")
    security = security!(%{name: "Pinned AG"})
    buy!(accounts, security, "3")

    result =
      Reconcile.run([
        row("whatever the broker calls it", "3", %{security_id: security.id}),
        row("ghost", "1", %{security_id: security.id + 1_000_000})
      ])

    assert [matched] = result.matched
    assert matched.security.id == security.id
    assert matched.matched_via == :pinned
    assert Decimal.eq?(matched.delta, Decimal.new("0"))

    assert [unmatched] = result.unmatched
    assert unmatched.reason == :unknown_security_id
  end

  # User story:
  # As the operating agent,
  # I want an optional portfolio scope bounding the compare,
  # so that I can reconcile one depot list without other portfolios' positions
  # bleeding into the deltas — and the response states its basis (FR-13).
  #
  # Acceptance criteria:
  # - Unscoped: quantities sum across the whole instance; basis says so.
  # - portfolio_id scope: only that portfolio's ledger quantities count.
  test "the portfolio scope bounds the compare and the basis states it" do
    first = accounts!("ScopeOne")
    second = accounts!("ScopeTwo")
    security = security!(%{name: "Everywhere AG", isin: "DE0007164600"})
    buy!(first, security, "10")
    buy!(second, security, "4")

    unscoped = Reconcile.run([row("DE0007164600", "14")])
    assert unscoped.basis.scope == :instance
    assert unscoped.basis.portfolio_id == nil
    assert [matched] = unscoped.matched
    assert Decimal.eq?(matched.ledger_quantity, Decimal.new("14"))
    assert Decimal.eq?(matched.delta, Decimal.new("0"))

    scoped = Reconcile.run([row("DE0007164600", "14")], portfolio_id: first.portfolio.id)
    assert scoped.basis.scope == :portfolio
    assert scoped.basis.portfolio_id == first.portfolio.id
    assert scoped.basis.as_of == Date.utc_today()
    assert [scoped_match] = scoped.matched
    assert Decimal.eq?(scoped_match.ledger_quantity, Decimal.new("10"))
    assert Decimal.eq?(scoped_match.delta, Decimal.new("4"))
  end

  # User story:
  # As a maintainer of the reconcile engine and its API/MCP presenters,
  # I want the verbatim guidance and weak-match caveat exposed as pure helpers,
  # so that every surface embeds the exact same ADR-0029 6 text without
  # re-deriving it.
  #
  # Acceptance criteria:
  # - guidance/0 and weak_match_caveat/0 return the canonical strings.
  test "exposes the verbatim guidance and weak-match caveat as helpers" do
    assert Reconcile.guidance() == @guidance
    assert Reconcile.weak_match_caveat() == @weak_caveat
  end

  # User story:
  # As the operating agent,
  # I want only strings that validate as ISINs (format AND check digit) to
  # enter tier 1,
  # so that an ISIN-shaped-but-invalid string or a non-string never masquerades
  # as an ISIN match (ADR-0029 6).
  #
  # Acceptance criteria:
  # - isin?/1 accepts a valid ISIN, rejects a bad check digit, a wrong shape,
  #   and any non-string value.
  test "isin?/1 accepts valid ISINs and rejects bad ones and non-strings" do
    assert Reconcile.isin?("DE0007100000")
    refute Reconcile.isin?("DE0007100001")
    refute Reconcile.isin?("NOTANISIN")
    refute Reconcile.isin?(nil)
    refute Reconcile.isin?(123)
  end

  # User story:
  # As the operating agent,
  # I want an identifier that normalizes to blank kept out of every tier,
  # so that a whitespace-only identifier is reported unmatched rather than
  # matched against an empty key (ADR-0029 6 normalization boundary).
  #
  # Acceptance criteria:
  # - A whitespace-only identifier carrying a currency is unmatched (:no_match),
  #   never matched.
  test "a whitespace-only identifier normalizes to blank and stays unmatched" do
    accounts = accounts!("Blank")
    security = security!(%{name: "Blank Boundary AG", ticker_symbol: "BBA"})
    buy!(accounts, security, "1")

    result = Reconcile.run([row("   ", "1", %{currency: "EUR"})])

    assert result.matched == []
    assert [unmatched] = result.unmatched
    assert unmatched.reason == :no_match
  end
end
