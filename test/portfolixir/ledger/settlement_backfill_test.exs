defmodule Portfolixir.Ledger.SettlementBackfillTest do
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementBackfill
  alias Portfolixir.Repo

  # Synthetic ADR-0033 fixture figures only.

  defp world do
    world = base_world(name: "Backfill World", cash_name: "BF Cash", depot_name: "BF Depot")
    security = create_security!(name: "Backfill US Equity", ticker: "BUS", currency: "USD")
    Map.put(world, :security, security)
  end

  # An imported cross-currency row before ADR-0033: EUR-booked buy of the USD
  # security, no settlement fields.
  defp legacy_import_buy!(w, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: Keyword.get(opts, :type, "buy"),
        date: Keyword.get(opts, :date, ~D[2026-01-15]),
        quantity: Keyword.get(opts, :quantity, "10"),
        price: Keyword.get(opts, :price, "80.00"),
        currency_code: "EUR"
      })

    tx
  end

  defp seed_rate!(date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: rate, source: "manual"}
      ])
  end

  # User story (ADR-0033 / issue #569, one-time auditable backfill):
  # As a maintainer with existing imported cross-currency rows,
  # I want a one-time backfill that derives the ADR-0015 settlement fields
  # from the stored hub rate at each row's booking date, journaled per row,
  # so that historic imports gain an honest cost pair without any silent
  # data mutation.
  #
  # Acceptance criteria:
  # - A EUR-booked buy of a USD security at rate 1 EUR = 1.25 USD gains
  #   settlement_amount 800.00 EUR, security_amount 1000.00 USD and
  #   settlement_fx_rate 0.80.
  # - The update is journaled (auditable, ADR-0017).
  # - A second run changes nothing (idempotent).
  test "backfills derivable rows, journaled and idempotent" do
    w = world()
    tx = legacy_import_buy!(w)
    seed_rate!(~D[2026-01-15], "1.25")

    assert {:ok, summary} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert summary.updated == 1
    assert summary.skipped_no_rate == 0

    reloaded = Ledger.get_transaction(tx.id)
    assert Decimal.equal?(reloaded.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(reloaded.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(reloaded.settlement_fx_rate, Decimal.new("0.80"))

    # Journaled under the backfill actor (ADR-0017 — auditable).
    tx_id = to_string(tx.id)

    assert Repo.exists?(
             from(e in Journal.Entry,
               where:
                 e.resource_type == "transaction" and e.resource_id == ^tx_id and
                   e.operation == :update
             )
           )

    assert {:ok, second} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert second.updated == 0
    assert second.skipped_no_rate == 0
  end

  # User story (honesty over availability):
  # As a maintainer whose row's booking date has no stored rate,
  # I want the row skipped and reported, never guessed,
  # so that the backfill cannot invent a native leg.
  test "a row with no stored rate at its booking date is skipped" do
    w = world()
    tx = legacy_import_buy!(w)

    assert {:ok, summary} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert summary.updated == 0
    assert summary.skipped_no_rate == 1

    reloaded = Ledger.get_transaction(tx.id)
    assert is_nil(reloaded.security_amount)
    assert is_nil(reloaded.settlement_amount)
    assert is_nil(reloaded.settlement_fx_rate)
  end

  # User story (counter-metric):
  # As a maintainer with ordinary same-currency rows and already-settled
  # ADR-0015 rows,
  # I want the backfill to leave them untouched,
  # so that only the broken import form is repaired.
  test "same-currency and already-settled rows are not touched" do
    world = base_world(name: "BF Same", cash_name: "BFS Cash", depot_name: "BFS Depot")
    eur = create_security!(name: "Backfill EU Equity", ticker: "BEU", currency: "EUR")

    {:ok, same_ccy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: eur.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        currency_code: "EUR"
      })

    usd = create_security!(name: "Backfill US Settled", ticker: "BSS", currency: "USD")

    {:ok, settled} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "100.00",
        currency_code: "USD",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })

    assert {:ok, summary} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))
    assert summary.updated == 0
    assert summary.skipped_no_rate == 0

    assert is_nil(Ledger.get_transaction(same_ccy.id).security_amount)

    reloaded = Ledger.get_transaction(settled.id)
    assert Decimal.equal?(reloaded.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(reloaded.settlement_fx_rate, Decimal.new("0.80"))
  end
end
