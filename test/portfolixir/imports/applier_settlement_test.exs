defmodule Portfolixir.Imports.ApplierSettlementTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Imports.Applier
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  # All figures are synthetic (the ADR-0033 fixture family).

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import FX Portfolio",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp usd_security! do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Imported US Equity",
        ticker_symbol: "IUS",
        isin: "US0000000001",
        currency_code: "USD",
        asset_class: "equity"
      })

    security
  end

  defp buy_entry(overrides) do
    struct!(
      %Entry{
        source_row: 1,
        kind: "buy",
        date: ~D[2026-01-15],
        currency_code: "EUR",
        gross_amount: Decimal.new("800.00"),
        quantity: Decimal.new("10"),
        price: Decimal.new("80.00"),
        security: %{isin: "US0000000001", name: "Imported US Equity", currency: "USD"},
        pp_portfolio_name: "PP Depot",
        pp_account_name: "PP Cash"
      },
      overrides
    )
  end

  defp apply!(entry, portfolio) do
    {:ok, _result} =
      Applier.apply(%Preview{entries: [entry]}, %{
        portfolio_id: portfolio.id,
        default_currency_code: "EUR"
      })

    Repo.one!(from(t in Transaction, where: t.type == ^entry.kind))
  end

  # User story (ADR-0033 / issue #569):
  # As a maintainer importing a Portfolio Performance export that books a
  # USD security's buy in EUR (the account currency),
  # I want the applier to persist the ADR-0015 settlement fields with the
  # security-currency leg derived from the stored hub rate at the booking
  # date,
  # so that the cost fold can carry an honest cost pair without ever looking
  # a rate up at read time.
  #
  # Acceptance criteria:
  # - With a stored EUR-hub rate at the booking date (1 EUR = 1.25 USD):
  #   settlement_amount = 800.00 EUR, security_amount = 1000.00 USD,
  #   settlement_fx_rate = 0.80 (settlement per 1 security unit).
  # - All three are Decimal columns, derived at WRITE time.
  test "a cross-currency PP buy persists the derived settlement legs" do
    portfolio = portfolio!()
    usd_security!()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-15],
          rate: "1.25",
          source: "manual"
        }
      ])

    tx = apply!(buy_entry(%{}), portfolio)

    assert tx.currency_code == "EUR"
    assert Decimal.equal?(tx.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(tx.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.80"))
  end

  # Acceptance criteria (#395's guard meets the importer; closing act, both
  # hunters): Portfolio Performance prints the per-share Kurs rounded, while
  # the entry's cash amount — a JSON row's amount, a CSV row's Gesamtpreis
  # (ADR-0053; PP's Betrag is the gross value) — is the exact cash the
  # broker settled. The settlement amount is therefore the cash amount net
  # of fees and taxes — the guard's own relation, inverted — not quantity ×
  # the rounded Kurs, which missed it by more than a cent and made the guard
  # refuse the whole import.
  test "a cross-currency PP buy settles on its cash amount, not the rounded Kurs" do
    portfolio = portfolio!()
    usd_security!()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-15],
          rate: "1.25",
          source: "manual"
        }
      ])

    tx =
      apply!(
        buy_entry(%{
          gross_amount: Decimal.new("805.03"),
          quantity: Decimal.new("13"),
          price: Decimal.new("61.54"),
          fees: Decimal.new("4.95")
        }),
        portfolio
      )

    assert Decimal.equal?(tx.gross_amount, Decimal.new("805.03"))
    assert Decimal.equal?(tx.settlement_amount, Decimal.new("800.08"))
    assert Decimal.equal?(tx.security_amount, Decimal.new("1000.10"))
  end

  # User story (ADR-0053 §1 meets ADR-0033):
  # As a maintainer importing a Portfolio Performance CSV that buys a USD
  # security against a EUR account,
  # I want the settlement legs read off the cash the row books, its
  # Gesamtpreis, net of its fees and taxes,
  # so that the trade amount is PP's Betrag and the guard holds.
  #
  # Acceptance criteria:
  # - A PP-faithful Kauf (Betrag 800,00, Gebühren 4,95, Steuern 1,05,
  #   Gesamtpreis 806,00) books 806.00 and settles 800.00 EUR, the Betrag,
  #   converted at 1 EUR = 1.25 USD to 1000.00 USD.
  test "a cross-currency PP CSV buy settles on its Gesamtpreis net of fees and taxes" do
    portfolio = portfolio!()
    usd = usd_security!()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-15],
          rate: "1.25",
          source: "manual"
        }
      ])

    csv = """
    Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
    2026-01-15 10:00:00;Kauf;Imported US Equity;10;80,00;800,00;4,95;1,05;806,00;PP Depot;PP Cash;;
    """

    {:ok, %Preview{errors: [], entries: [entry]} = preview} =
      PortfolioPerformance.parse(csv, filename: "pp.csv")

    # The CSV carries no currency, so the preview's choice names the USD
    # security, as the operator makes it.
    key = SecurityResolver.key(SecurityResolver.effective_ref(entry))

    {:ok, _result} =
      Applier.apply(preview, %{
        portfolio_id: portfolio.id,
        default_currency_code: "EUR",
        security_mappings: %{key => {:existing, usd.id}}
      })

    tx = Repo.one!(from(t in Transaction, where: t.type == "buy"))

    assert tx.security_id == usd.id
    assert Decimal.equal?(tx.gross_amount, Decimal.new("806.00"))
    assert Decimal.equal?(tx.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(tx.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.80"))
  end

  # User story (ADR-0033 requirement 4 — honesty over availability):
  # As a maintainer importing the same buy without any stored rate for the
  # booking date,
  # I want the settlement fields left empty instead of guessed,
  # so that the position's decomposition reads honestly unavailable.
  test "a cross-currency PP buy with no stored rate keeps the fields nil" do
    portfolio = portfolio!()
    usd_security!()

    tx = apply!(buy_entry(%{}), portfolio)

    assert is_nil(tx.security_amount)
    assert is_nil(tx.settlement_amount)
    assert is_nil(tx.settlement_fx_rate)
  end

  # User story (counter-metric):
  # As a maintainer importing an ordinary same-currency buy,
  # I want no settlement fields stored,
  # so that the same-currency majority keeps behaving exactly as before.
  test "a same-currency PP buy stores no settlement fields" do
    portfolio = portfolio!()

    entry =
      buy_entry(%{
        security: %{isin: "DE0000000001", name: "Imported EU Equity", currency: "EUR"},
        currency_code: "EUR"
      })

    tx = apply!(entry, portfolio)

    assert is_nil(tx.security_amount)
    assert is_nil(tx.settlement_amount)
    assert is_nil(tx.settlement_fx_rate)
  end

  # User story (sells too):
  # As a maintainer importing a cross-currency sell,
  # I want the same derived settlement legs on the sell row,
  # so that removals slice the cost pair with the same honesty as buys.
  test "a cross-currency PP sell persists the derived settlement legs" do
    portfolio = portfolio!()
    usd_security!()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-03-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    entry =
      buy_entry(%{
        kind: "sell",
        date: ~D[2026-03-01],
        gross_amount: Decimal.new("400.00"),
        quantity: Decimal.new("5"),
        price: Decimal.new("80.00")
      })

    tx = apply!(entry, portfolio)

    assert Decimal.equal?(tx.settlement_amount, Decimal.new("400.00"))
    assert Decimal.equal?(tx.security_amount, Decimal.new("500.00"))
    assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.80"))
  end

  # User story (#1199, Sprint 21 α1; the ADR-0015 amendment of 2026-10-09,
  # point 1 and identity 5):
  # As a maintainer importing a file into an account that already exists,
  # I want an entry priced in neither its security's currency nor its
  # account's refused and named by its row,
  # so that the importer's copy of the currency check refuses what the
  # ledger refuses, and no rate stored between the entry's currency and the
  # security's lets a third currency in.
  #
  # Acceptance criteria:
  # - A buy of the USD security priced in CHF into the existing EUR account,
  #   with the CHF and USD hub rates stored (so the import derives legs from
  #   CHF to USD), is refused: the apply names row 2 and the error on
  #   currency_code names USD and EUR. Before the check it was booked.
  # - Nothing of that apply is stored.
  test "an entry priced in a third currency into an existing account is refused by its row" do
    portfolio = portfolio!()
    usd_security!()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-15],
          rate: "1.25",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "CHF",
          date: ~D[2026-01-15],
          rate: "0.90",
          source: "manual"
        }
      ])

    # The first apply creates "PP Cash" in EUR, the currency of its booking.
    first = apply!(buy_entry(%{}), portfolio)

    assert Repo.get!(Portfolixir.Portfolios.CashAccount, first.cash_account_id).currency_code ==
             "EUR"

    chf_entry =
      buy_entry(%{
        source_row: 2,
        date: ~D[2026-01-15],
        currency_code: "CHF",
        gross_amount: Decimal.new("720.00"),
        quantity: Decimal.new("8"),
        price: Decimal.new("90.00")
      })

    assert {:error, %{row: 2, reason: {:insert_failed, changeset}}} =
             Applier.apply(%Preview{entries: [chf_entry]}, %{
               portfolio_id: portfolio.id,
               default_currency_code: "EUR"
             })

    assert errors_on(changeset)[:currency_code] == [
             "must be USD (the security's currency) or EUR (the cash account's)"
           ]

    assert Repo.aggregate(Transaction, :count) == 1
  end

  # User story (#1199, H53; the ADR-0050 amendment of 2026-10-09, point 2):
  # As the operator dropping a file again whose apply would be refused for
  # a booking priced in a third currency,
  # I want the preview's dry run to stop where the apply stops,
  # so that it never releases a name, or counts a row booked, on a run the
  # apply would never finish.
  #
  # Acceptance criteria:
  # - The buy of 800.00 EUR stored; the re-export moves it to 10:30 and adds
  #   the buy of the USD security priced 720.00 CHF into the EUR account
  #   (the CHF and USD hub rates stored): the apply refuses row 2. The dry
  #   run stops on it, so the counts stay on the hash layers: 2 new, 0
  #   economics. (Mutation: without the third-currency refusal in the
  #   simulated insert the dry run runs on and counts the moved buy
  #   economics 1.)
  test "the dry run stops where the apply refuses an entry priced in a third currency" do
    portfolio = portfolio!()
    usd_security!()
    store_usd_and_chf_rates!()
    apply!(buy_entry(%{}), portfolio)

    redrop = %Preview{
      entries: [
        buy_entry(%{time: ~T[10:30:00]}),
        buy_entry(%{
          source_row: 2,
          currency_code: "CHF",
          gross_amount: Decimal.new("720.00"),
          quantity: Decimal.new("8"),
          price: Decimal.new("90.00")
        })
      ]
    }

    assert {:error, %{row: 2, reason: {:insert_failed, _changeset}}} =
             Applier.apply(redrop, %{portfolio_id: portfolio.id})

    assert %{new: 2, economics: 0} = Applier.reimport_counts(redrop, portfolio.id).total
  end

  # User story (H53; the ADR-0050 amendment of 2026-10-09, point 2):
  # As the operator dropping a file again that opens a new cash account and
  # books a deposit onto it in another currency, without a rate,
  # I want the preview's dry run to judge the account it would create in
  # the currency the apply creates it in,
  # so that the dry run stops where the apply refuses the deposit.
  #
  # Acceptance criteria:
  # - The buy of 800.00 EUR stored; the re-export moves it to 10:30, opens
  #   "PP Savings" with a deposit of 50.00 EUR and adds a deposit of 20.00
  #   USD onto it: the apply refuses row 3 (a cross-currency settlement
  #   needs its rate). The dry run stops on it, so the counts stay on the
  #   hash layers: 3 new, 0 economics. (Mutation: without the currencies of
  #   the accounts the dry run would create, the USD deposit passes and the
  #   moved buy counts economics 1.)
  test "the dry run judges an account it would create in the currency the apply creates it in" do
    portfolio = portfolio!()
    usd_security!()
    store_usd_and_chf_rates!()
    apply!(buy_entry(%{}), portfolio)

    redrop = %Preview{
      entries: [
        buy_entry(%{time: ~T[10:30:00]}),
        savings_deposit(2, "EUR", "50.00"),
        savings_deposit(3, "USD", "20.00")
      ]
    }

    assert {:error, %{row: 3, reason: {:insert_failed, _changeset}}} =
             Applier.apply(redrop, %{portfolio_id: portfolio.id})

    assert %{new: 3, economics: 0} = Applier.reimport_counts(redrop, portfolio.id).total
  end

  defp store_usd_and_chf_rates! do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-15],
          rate: "1.25",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "CHF",
          date: ~D[2026-01-15],
          rate: "0.90",
          source: "manual"
        }
      ])
  end

  defp savings_deposit(row, currency, amount) do
    %Entry{
      source_row: row,
      kind: "deposit",
      date: ~D[2026-01-16],
      currency_code: currency,
      gross_amount: Decimal.new(amount),
      pp_account_name: "PP Savings"
    }
  end
end
