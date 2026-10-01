defmodule Portfolixir.SeededUpgrade.Sprint16Test do
  # Sprint 16's two upgrade-path catches that would have stopped the release
  # from booting (Sprint 16 retrospective, "upgrade migrations over legacy
  # rows"), replayed by the seeded-upgrade harness (Sprint 17, Lane G-1,
  # #995): each case seeds, with plain SQL, the rows a Sprint 15 instance
  # could hold, migrates to head and reads the migrated shape.
  #
  # Both are mutation-verified: putting the defect back makes the case fail
  # with the error the release would have stopped on (the evidence is in the
  # commit that adds them).
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The last migration Sprint 15's release shipped (E24 A1, the policy
  # rules): the schema an instance upgrading to Sprint 16 starts from.
  @sprint15_head 20_260_923_120_000

  # User story:
  # As the operator upgrading a self-hosted instance whose agent once re-typed
  # an imported deposit into a balance anchor over the API,
  # I want the upgrade's migrations to finish over that row,
  # so that the release boots, the row keeps the content hash that stops a
  # re-import from booking it twice, and no new row reaches that state.
  #
  # Acceptance criteria:
  # - Seeded at Sprint 15's head with a hashed balance anchor, a hashed
  #   deposit and an unhashed anchor, the database migrates to head.
  # - The import-hash kind check exists NOT VALID, the re-typed anchor keeps
  #   its type and its hash, the other rows are untouched, and the upgrade's
  #   log names the anchor.
  # - After the upgrade a new balance anchor carrying a hash is refused.
  @tag seeded_upgrade: 20_260_925_130_000
  test "the import-hash kind check does not stop the upgrade over a re-typed hashed row",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @sprint15_head, seed: &seed_retyped_anchor/1)
    world = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert %{rows: [[false]]} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT convalidated FROM pg_constraint WHERE conname = $1",
               ["transactions_import_hash_kind_check"]
             )

    assert %{rows: rows} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT id, type, import_hash FROM transactions ORDER BY id"
             )

    assert rows == [
             [world.retyped_anchor, "balance_adjustment", "synthetic-retyped-deposit"],
             [world.deposit, "deposit", "synthetic-deposit"],
             [world.anchor, "balance_adjustment", nil]
           ]

    assert upgrade.log =~ "transaction ##{world.retyped_anchor} (balance_adjustment)"
    refute upgrade.log =~ "transaction ##{world.deposit} "

    error =
      assert_raise Postgrex.Error, fn ->
        SeededUpgrade.journaled!(upgrade, fn ->
          insert_transaction!(upgrade, world, "balance_adjustment", "synthetic-new-anchor")
        end)
      end

    assert %{postgres: %{code: :check_violation}} = error
    assert %{postgres: %{constraint: "transactions_import_hash_kind_check"}} = error
  end

  # User story:
  # As the operator upgrading a self-hosted instance on which I edited one
  # policy rule and retired another more than two days ago,
  # I want the upgrade's author backfill to finish,
  # so that the release boots and every stored version names its author.
  #
  # Acceptance criteria:
  # - Seeded at Sprint 15's head with an edit's predecessor closed ten days
  #   ago, its open successor and a rule retired five days ago, each with its
  #   journaled creation, the database migrates to head.
  # - Each version carries the author its creation's actor names (agent for
  #   an API token, operator for the owner's screen), its period is
  #   unchanged, and each backfill write is journaled under the backfill's
  #   system job.
  @tag seeded_upgrade: 20_260_926_121_500
  test "the author backfill does not stop the upgrade over versions closed days ago",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @sprint15_head, seed: &seed_closed_versions/1)
    versions = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert %{rows: rows} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT id, author, valid_from, valid_until FROM policy_rule_versions ORDER BY id"
             )

    assert rows == [
             [versions.predecessor.id, "agent" | versions.predecessor.period],
             [versions.successor.id, "agent" | versions.successor.period],
             [versions.retired.id, "operator" | versions.retired.period]
           ]

    assert %{rows: backfilled} =
             SeededUpgrade.query!(
               upgrade,
               """
               SELECT resource_id FROM audit_journal
                WHERE resource_type = 'policy_rule_version' AND operation = 'update'
                  AND actor_type = 'system_job' AND actor_label = 'policy_author_backfill'
                ORDER BY resource_id::bigint
               """
             )

    assert backfilled ==
             Enum.map([versions.predecessor, versions.successor, versions.retired], fn version ->
               [Integer.to_string(version.id)]
             end)
  end

  # -- seeds: plain SQL, in the shape of Sprint 15's schema ---------------------

  # A deposit imported with its content hash and re-typed to a balance anchor
  # by a later PATCH (which kept the hash), beside an ordinary hashed deposit
  # and an anchor recorded by hand.
  defp seed_retyped_anchor(db) do
    world = seed_world(db)
    retyped = insert_transaction!(db, world, "balance_adjustment", "synthetic-retyped-deposit")
    deposit = insert_transaction!(db, world, "deposit", "synthetic-deposit")
    anchor = insert_transaction!(db, world, "balance_adjustment", nil)

    Map.merge(world, %{retyped_anchor: retyped, deposit: deposit, anchor: anchor})
  end

  # An edited rule (its predecessor version closed ten days ago, its successor
  # open) written by an API token, and a rule the owner retired five days ago,
  # each version with the creation entry the journal holds for it.
  defp seed_closed_versions(db) do
    world = seed_world(db)

    security =
      insert!(db, "INSERT INTO securities #{row(~w(name currency_code))}", [
        "Synthetic Basin Minerals",
        "EUR"
      ])

    edited = insert_rule!(db, world, "Edited on the previous release")
    retired_rule = insert_rule!(db, world, "Retired on the previous release")
    predecessor = insert_version!(db, {edited, security}, {-30, -10}, "api_token_rw")
    successor = insert_version!(db, {edited, security}, {-9, nil}, "api_token_rw")
    retired = insert_version!(db, {retired_rule, security}, {-20, -5}, "owner_ui")

    %{predecessor: predecessor, successor: successor, retired: retired}
  end

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

  defp insert_transaction!(db, world, type, import_hash) do
    insert!(
      db,
      "INSERT INTO transactions " <>
        row(~w(portfolio_id cash_account_id type date currency_code gross_amount import_hash)),
      [world.portfolio, world.cash, type, ~D[2026-02-01], "EUR", Decimal.new("250"), import_hash]
    )
  end

  defp insert_rule!(db, world, name) do
    insert!(db, "INSERT INTO policy_rules #{row(~w(portfolio_id name))}", [world.portfolio, name])
  end

  # A cap on one security's weight, in force from `from_days` (relative to the
  # database's current date) to `until_days` (nil: open), and its creation
  # entry in the journal under `actor_type`. Answers its id and its period as
  # stored.
  defp insert_version!(db, {rule, security}, {from_days, until_days}, actor_type) do
    %{rows: [[id | period]]} =
      SeededUpgrade.query!(
        db,
        """
        INSERT INTO policy_rule_versions
          (policy_rule_id, subject_type, security_id, measure, kind, threshold, severity,
           valid_from, valid_until, inserted_at, updated_at)
        VALUES ($1, 'security', $2, 'weight', 'cap', 10, 'hard',
                CURRENT_DATE + $3::integer, CURRENT_DATE + $4::integer,
                LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
        RETURNING id, valid_from, valid_until
        """,
        [rule, security, from_days, until_days]
      )

    SeededUpgrade.query!(
      db,
      """
      INSERT INTO audit_journal
        (actor_type, actor_label, operation, resource_type, resource_id, "after", inserted_at)
      VALUES ($1, 'synthetic-actor', 'create', 'policy_rule_version', $2::text,
              jsonb_build_object('id', $3::bigint), now())
      """,
      [actor_type, Integer.to_string(id), id]
    )

    %{id: id, period: period}
  end

  # `(columns..., inserted_at, updated_at) VALUES ($1, ..., now, now)
  # RETURNING id` for an insert of one row.
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
