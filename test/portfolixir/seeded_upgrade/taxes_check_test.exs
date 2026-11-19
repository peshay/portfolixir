defmodule Portfolixir.SeededUpgrade.TaxesCheckTest do
  # The taxes CHECK (Sprint 30 plan, A4, #1356; risk tier: stored data) over
  # the transactions an instance already holds. The migration counts the rows
  # whose taxes are negative before it adds
  # `transactions_taxes_non_negative_check`, and refuses to run while any
  # exists, naming each by id: which correction a row needs is the
  # operator's choice, never the migration's, and the migration changes no
  # row. No such row should exist, since the changeset refuses one; the
  # guard is for a row some writer stored past it. Every value is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the taxes CHECK: the schema an instance upgrading
  # to it starts from.
  @before_check 20_261_112_210_000

  @constraint "transactions_taxes_non_negative_check"

  # User story:
  # As the operator upgrading an instance whose ledger holds taxes of zero
  # and of a positive amount,
  # I want the upgrade to add the taxes check and change nothing,
  # so that the release boots and every later writer is held to the rule.
  #
  # Acceptance criteria:
  # - Seeded before the check with a deposit without taxes and a deposit
  #   with positive taxes, the database migrates to head.
  # - The check exists and is validated, and both rows are unchanged.
  # - After the upgrade a raw insert with negative taxes is refused with the
  #   check's name.
  @tag seeded_upgrade: 20_261_119_170_000
  test "the taxes check is added over a ledger without negative taxes",
       %{seeded_upgrade: migration} do
    upgrade =
      SeededUpgrade.upgrade!(
        from: @before_check,
        seed: fn db ->
          world = seed_world(db)

          Map.merge(world, %{
            untaxed: insert_deposit!(db, world, Decimal.new("0")),
            taxed: insert_deposit!(db, world, Decimal.new("1.25"))
          })
        end
      )

    world = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert %{rows: [[true]]} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT convalidated FROM pg_constraint WHERE conname = $1",
               [@constraint]
             )

    assert %{rows: rows} =
             SeededUpgrade.query!(upgrade, "SELECT id, taxes FROM transactions ORDER BY id")

    assert rows == [
             [world.untaxed, Decimal.new("0.000000")],
             [world.taxed, Decimal.new("1.250000")]
           ]

    error =
      assert_raise Postgrex.Error, fn ->
        SeededUpgrade.journaled!(upgrade, fn ->
          insert_deposit!(upgrade, world, Decimal.new("-0.01"))
        end)
      end

    assert %{postgres: %{code: :check_violation, constraint: @constraint}} = error
  end

  # User story:
  # As the operator upgrading an instance on which a writer that bypassed
  # the changeset stored negative taxes,
  # I want the upgrade to stop and name each such row,
  # so that I correct it myself rather than the upgrade choosing how.
  #
  # Acceptance criteria:
  # - Seeded before the check with two deposits whose taxes are negative and
  #   one whose taxes are zero, the upgrade stops at the taxes migration.
  # - The error names each negative row's id and not the clean row's, and
  #   names the remedy that works while this release cannot start: the
  #   pre-upgrade backup, the previous release and the tax_refund kind.
  # - No row is changed: the check is absent and both rows keep their taxes.
  @tag seeded_upgrade: 20_261_119_170_000
  test "the taxes check refuses to run over negative taxes and names each row" do
    parent = self()

    error =
      assert_raise ExUnit.AssertionError, fn ->
        SeededUpgrade.upgrade!(
          from: @before_check,
          seed: fn db ->
            world = seed_world(db)

            seeded = %{
              first: insert_deposit!(db, world, Decimal.new("-2.50")),
              clean: insert_deposit!(db, world, Decimal.new("0")),
              second: insert_deposit!(db, world, Decimal.new("-0.000001"))
            }

            send(parent, {:seeded, db, seeded})
            seeded
          end
        )
      end

    assert_received {:seeded, db, seeded}

    assert error.message =~ "stopped at 20261119170000_check_transaction_taxes_non_negative.exs"
    assert error.message =~ "transactions holds negative taxes"
    assert error.message =~ "transaction ##{seeded.first}"
    assert error.message =~ "transaction ##{seeded.second}"
    refute error.message =~ "transaction ##{seeded.clean}"
    assert error.message =~ "tax_refund"
    assert error.message =~ "previous release"
    assert error.message =~ "backup"

    # The scratch database stays until the test exits: the upgrade's
    # transaction rolled back, so no row changed and no check was added.
    assert %{rows: [[0]]} =
             SeededUpgrade.query!(
               db,
               "SELECT count(*) FROM pg_constraint WHERE conname = $1",
               [@constraint]
             )

    assert %{rows: rows} =
             SeededUpgrade.query!(db, "SELECT id, taxes FROM transactions ORDER BY id")

    assert rows == [
             [seeded.first, Decimal.new("-2.500000")],
             [seeded.clean, Decimal.new("0.000000")],
             [seeded.second, Decimal.new("-0.000001")]
           ]
  end

  # -- seeds: plain SQL, in the shape of the schema before the check ----------

  defp seed_world(db) do
    portfolio =
      insert!(db, "INSERT INTO portfolios #{row(~w(name base_currency_code))}", [
        "Upgrade Portfolio",
        "EUR"
      ])

    cash =
      insert!(db, "INSERT INTO cash_accounts #{row(~w(portfolio_id name currency_code))}", [
        portfolio,
        "Upgrade Cash",
        "EUR"
      ])

    %{portfolio: portfolio, cash: cash}
  end

  defp insert_deposit!(db, world, taxes) do
    insert!(
      db,
      "INSERT INTO transactions " <>
        row(~w(portfolio_id cash_account_id type date currency_code gross_amount taxes)),
      [world.portfolio, world.cash, "deposit", ~D[2026-02-01], "EUR", Decimal.new("250"), taxes]
    )
  end

  # `(columns..., inserted_at, updated_at) VALUES ($1, ..., now, now)
  # RETURNING id`, as the repository's seeded cases build it.
  defp row(columns) do
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    "(#{Enum.join(columns, ", ")}, inserted_at, updated_at) " <>
      "VALUES (#{placeholders}, LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
  end

  defp insert!(db, sql, params) do
    %{rows: [[id]]} = SeededUpgrade.query!(db, sql, params)
    id
  end
end
