defmodule Portfolixir.SeededUpgrade.ProviderCurrencyTest do
  # #1415 (Sprint 28 Q3): the migration that adds `provider_currency` and
  # `provider_currency_at` to the securities. Both are nullable and additive,
  # so the rule asks for no case; the plan does, because the set the column
  # feeds must not read a security synced before the column existed as a
  # mismatch: a null provider currency is not yet known, never a finding.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the provider currency.
  @before_provider_currency 20_261_108_140_000

  # User story (#1415):
  # As the operator upgrading an instance whose securities were synced by a
  # release that never kept the provider's currency,
  # I want those securities to read "not yet known" after the upgrade,
  # so that the Overview names no currency mismatch the instance has not
  # seen, and the first sync after the upgrade is what fills the column.
  #
  # Acceptance criteria:
  # - Seeded with a EUR and a USD security, each with synced provider quotes,
  #   the database migrates to head and both securities and their quotes are
  #   kept.
  # - Both read `provider_currency` and `provider_currency_at` null.
  @tag seeded_upgrade: 20_261_109_101_500
  test "a security synced before the column reads not yet known, never a mismatch",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_provider_currency, seed: &seed_synced/1)

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert %{rows: [[nil, nil], [nil, nil]]} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT provider_currency, provider_currency_at FROM securities ORDER BY id"
             )

    assert %{rows: [[4]]} = SeededUpgrade.query!(upgrade, "SELECT count(*) FROM security_quotes")
  end

  defp seed_synced(db) do
    for {name, currency} <- [{"Alpha", "EUR"}, {"Beta", "USD"}] do
      security =
        insert!(
          db,
          """
          INSERT INTO securities
            (name, currency_code, ticker_symbol, provider, inserted_at, updated_at)
          VALUES ($1, $2, $3, 'portfolio_performance', LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
          RETURNING id
          """,
          [name, currency, String.upcase(name)]
        )

      for {date, close} <- [{~D[2026-10-01], "100.00"}, {~D[2026-10-02], "101.00"}] do
        SeededUpgrade.query!(
          db,
          """
          INSERT INTO security_quotes
            (security_id, date, close, source, inserted_at, updated_at)
          VALUES ($1, $2, $3, 'portfolio_performance', LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
          """,
          [security, date, Decimal.new(close)]
        )
      end

      security
    end
  end

  defp insert!(db, sql, params) do
    %{rows: [[id]]} = SeededUpgrade.query!(db, sql, params)
    id
  end
end
